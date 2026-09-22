// AltHub Cookie Bridge — background.js
//
// ЧТО ЭТО ДЕЛАЕТ, ОДНОЙ ФРАЗОЙ: отдаёт куку .ROBLOSECURITY твоего аккаунта
// Roblox запущенному на этом же компьютере AltHub — и больше никому.
//
// КУДА УХОДЯТ ДАННЫЕ: только на http://127.0.0.1 — это твой же компьютер,
// такой запрос физически не выходит в сеть. Других адресов в этом файле нет,
// и проверка «Самопроверка.ps1» разбирает его и падает, если появятся.
//
// ЧТО ОНО ЧИТАЕТ: ровно одну куку — .ROBLOSECURITY с доменов roblox.com.
// Ни истории, ни закладок, ни других сайтов: в manifest.json нет и прав на них.
//
// ============ ГЛАВНАЯ ТОНКОСТЬ, ИЗ-ЗА КОТОРОЙ ВСЁ ЛОМАЛОСЬ ============
//
// Расширения третьего манифеста НЕ ЖИВУТ ПОСТОЯННО. Chrome усыпляет их через
// полминуты бездействия и будит на событие — а при пробуждении все переменные
// в памяти начинаются с нуля.
//
// Раньше номер порта, на который надо отдать куку, хранился просто в
// переменной. AltHub передавал его в адресе страницы входа, расширение
// запоминало — и засыпало, пока человек печатал логин, пароль и проходил
// капчу. Вход проходил успешно, кука появлялась, расширение просыпалось на
// это событие — и не знало, куда её отдавать. Окно входа висело открытым,
// AltHub молчал. Выглядело как «вошёл, и ничего не произошло».
//
// Поэтому всё, что нужно пережить сон, лежит в chrome.storage.session: он
// живёт, пока открыт браузер, и очищается сам при закрытии.
//
// ===================== ТРИ СПОСОБА, КАК ЭТО ЗАПУСКАЕТСЯ =====================
//
// 1) КНОПКА НА ПАНЕЛИ (или Alt+Shift+A). Ты уже сидишь на roblox.com под
//    нужным аккаунтом — жмёшь значок AltHub рядом с адресной строкой.
//    Расширение ищет AltHub на нескольких портах подряд и отдаёт куку ему.
//
// 2) КЛАВИША ИЗ САМОГО ALTHUB. AltHub открывает в браузере по умолчанию свою
//    страницу http://127.0.0.1:ПОРТ/grab, расширение видит переход на неё,
//    забирает куку, отдаёт и закрывает вкладку. Адрес локальный, поэтому на
//    серверы Roblox не уходит ни номер порта, ни факт нажатия.
//
// 3) ОКНО ВХОДА ALTHUB. AltHub сам запускает отдельное окно браузера с этим
//    расширением и открывает roblox.com/login?althub_port=ПОРТ. Здесь, и
//    ТОЛЬКО здесь, перед входом снимается старая .ROBLOSECURITY: иначе Chrome
//    восстановит прошлую сессию и мы отдадим не тот аккаунт. Метки устройства
//    (RBXEventTrackerV2 / browserid, rbx-ip2) не трогаются — без них Roblox
//    считает каждый вход новым железом и поднимает сложность капчи.

// Порты, на которых AltHub ждёт куку от кнопки и горячей клавиши. Фиксированный
// небольшой диапазон, а не один порт: вдруг соседняя программа занята первым.
// Тот же список продублирован в modules\CookieBridge.ps1, и проверка следит,
// чтобы они не разъехались.
const BRIDGE_PORTS = [52713, 52714, 52715, 52716, 52717];

// --------------------------------------------------------------- состояние --

const S = {
  async get() {
    try {
      const v = await chrome.storage.session.get(['loginPort', 'loginToken', 'ready', 'sent', 'banned']);
      return {
        loginPort: v.loginPort || null,
        loginToken: v.loginToken || '',
        ready: !!v.ready,
        sent: !!v.sent,
        banned: Array.isArray(v.banned) ? v.banned : []
      };
    } catch (e) {
      console.log('[AltHub] состояние не прочиталось:', e);
      return { loginPort: null, loginToken: '', ready: false, sent: false, banned: [] };
    }
  },
  async set(patch) {
    try {
      await chrome.storage.session.set(patch);
    } catch (e) {
      console.log('[AltHub] состояние не записалось:', e);
    }
  }
};

let preparing = false;   // только внутри одного пробуждения, наружу не нужно

function isRobloxHost(host) {
  try {
    return /(?:^|\.)roblox\.com$/i.test(String(host).replace(/^\./, ''));
  } catch {
    return false;
  }
}

function isLoopback(host) {
  return host === '127.0.0.1';
}

function extractPortFromUrl(url, param) {
  try {
    const p = new URL(url).searchParams.get(param);
    return p ? parseInt(p, 10) : null;
  } catch {
    return null;
  }
}

function cookieUrl(cookie) {
  const host = String(cookie.domain || '').replace(/^\./, '');
  const path = cookie.path || '/';
  return (cookie.secure ? 'https://' : 'http://') + host + path;
}

async function readRobloSecurity() {
  try {
    const c = await chrome.cookies.get({
      url: 'https://www.roblox.com',
      name: '.ROBLOSECURITY'
    });
    return c && c.value ? c.value : null;
  } catch (e) {
    console.log('[AltHub] не смог прочитать куку:', e);
    return null;
  }
}

async function postCookie(port, token, value) {
  const resp = await fetch('http://127.0.0.1:' + port + '/cookie?token=' + encodeURIComponent(token || ''), {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain' },
    body: value
  });
  const text = (await resp.text()).trim();
  return { ok: resp.ok && text === 'ok', status: resp.status, text };
}

// ============================ способы 1 и 2 ============================

async function findBridgePort() {
  // Спрашиваем каждый порт по очереди: «ты AltHub?». Отвечает только он —
  // на чужом порту запрос либо не пройдёт, либо вернёт не то слово.
  for (const port of BRIDGE_PORTS) {
    try {
      const r = await fetch('http://127.0.0.1:' + port + '/hello', { method: 'GET' });
      if (!r.ok) continue;
      const t = (await r.text()).trim();
      if (t.startsWith('althub:')) return { port, token: t.substring(7) };
    } catch {
      // порт закрыт или занят кем-то другим — идём дальше
    }
  }
  return null;
}

async function badge(text, title, color) {
  // ЕДИНСТВЕННЫЙ СПОСОБ ОТВЕТИТЬ ЧЕЛОВЕКУ В БРАУЗЕРЕ.
  // Клик по значку AltHub раньше не давал вообще ничего: ни при успехе, ни
  // при неудаче. Сообщение показывал AltHub — но его окно всплывает ЗА
  // браузером, и человек, глядя в браузер, видел «ничего не произошло».
  // Бейдж на самом значке видно там, куда человек и смотрит.
  try {
    await chrome.action.setBadgeText({ text: text });
    if (color) await chrome.action.setBadgeBackgroundColor({ color: color });
    if (title) await chrome.action.setTitle({ title: title });
    if (text) {
      setTimeout(function () {
        chrome.action.setBadgeText({ text: '' });
        chrome.action.setTitle({ title: 'Передать этот аккаунт Roblox в AltHub' });
      }, 6000);
    }
  } catch {}
}

async function tellProblem(port, token, reason) {
  // МОЛЧАНИЕ — ХУДШИЙ ОТВЕТ. Раньше при любой неудаче расширение просто
  // закрывало вкладку, и со стороны это выглядело как «нажал, мигнуло,
  // ничего не произошло» — не отличить от полностью сломанной программы.
  // Теперь причина уезжает в AltHub, и он говорит её словами.
  if (!port) return;
  try {
    await fetch('http://127.0.0.1:' + port + '/problem?token=' + encodeURIComponent(token || ''), {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain' },
      body: reason
    });
  } catch {}
}

async function grabAndSend(closeTabId, knownPort, knownToken) {
  const bridge = knownPort ? { port: knownPort, token: knownToken } : await findBridgePort();
  const port = bridge && bridge.port;
  const token = bridge && bridge.token;

  const value = await readRobloSecurity();
  if (!value) {
    console.log('[AltHub] на roblox.com нет входа — нечего передавать');
    await badge('нет', 'AltHub: в браузере нет входа на roblox.com', '#d9534f');
    await tellProblem(port, token, 'В браузере нет входа на roblox.com. Открой сайт и войди в нужный аккаунт, потом нажми ещё раз.');
    if (closeTabId) { try { await chrome.tabs.remove(closeTabId); } catch {} }
    return false;
  }

  if (!port) {
    // Сказать через AltHub некому — он и есть тот, кто не отвечает. Значит
    // отвечаем сами, прямо на значке.
    console.log('[AltHub] AltHub не отвечает ни на одном порту моста');
    await badge('!', 'AltHub не запущен или приём из браузера выключен', '#d9534f');
    if (closeTabId) { try { await chrome.tabs.remove(closeTabId); } catch {} }
    return false;
  }

  let ok = false;
  try {
    const result = await postCookie(port, token, value);
    ok = result.ok;
    if (!ok) {
      await badge('!', result.status === 422 ? 'AltHub: Roblox не подтвердил этот вход' : 'AltHub: вход не принят', '#d9534f');
    }
  } catch (e) {
    console.log('[AltHub] отправка не удалась:', e);
    await badge('!', 'AltHub: отправить вход не вышло', '#d9534f');
    await tellProblem(port, token, 'Кука прочиталась, но отправить её в AltHub не вышло: ' + e);
  }
  if (ok) { await badge('OK', 'AltHub: вход передан', '#5cb85c'); }
  console.log('[AltHub] передано в AltHub на порт', port, '=', ok);
  if (closeTabId) { try { await chrome.tabs.remove(closeTabId); } catch {} }
  return ok;
}

chrome.action.onClicked.addListener(() => { grabAndSend(null); });
chrome.commands.onCommand.addListener((cmd) => {
  if (cmd === 'althub-grab') grabAndSend(null);
});

// ============================ способ 3: окно входа ============================

async function removeRobloSecurity() {
  let list = [];
  let ok = true;
  try {
    list = await chrome.cookies.getAll({ name: '.ROBLOSECURITY' });
  } catch (e) {
    console.log('[AltHub] cookies.getAll ошибка:', e);
    return false;
  }
  const st = await S.get();
  const banned = st.banned.slice();
  for (const c of list) {
    if (!isRobloxHost(c.domain)) continue;
    if (c.value && banned.indexOf(c.value) < 0) banned.push(c.value);
    try {
      await chrome.cookies.remove({ url: cookieUrl(c), name: '.ROBLOSECURITY' });
      console.log('[AltHub] снята старая .ROBLOSECURITY с', c.domain, c.path);
    } catch (e) {
      ok = false;
      console.log('[AltHub] не удалось снять куку с', c.domain, e);
    }
  }
  await S.set({ banned: banned });
  return ok;
}

async function prepareSession() {
  if (preparing) return;
  const st = await S.get();
  if (st.ready || !st.loginPort) return;
  preparing = true;
  let cleaned = false;
  try {
    // Один проход достаточно: onCompleted и onChanged подстрахуют повторной
    // проверкой запрещённых значений. Раньше здесь был sleep + повторная
    // уборка — на холодном профиле это держало хранилище кук занятым ровно
    // тогда, когда страница пыталась их читать для своей навигации, и переход
    // подвисал на сером экране.
    cleaned = await removeRobloSecurity();
    if (!cleaned) throw new Error('не удалось очистить старую сессию Roblox');
  } catch (e) {
    console.log('[AltHub] prepareSession ошибка:', e);
  } finally {
    const now = await S.get();
    if (now.loginPort) await S.set({ ready: cleaned });
    preparing = false;
  }
}

async function noteLoginPort(p, token) {
  if (!p) return;
  const st = await S.get();
  if (st.loginPort === p && st.loginToken === (token || '')) {
    if (!st.ready) await prepareSession();
    return;
  }
  await S.set({ loginPort: p, loginToken: token || '', ready: false, sent: false, banned: [] });
  console.log('[AltHub] окно входа: порт', p);
  await prepareSession();

  // Будильник заводим здесь, в начале входа, — и только если его ещё нет,
  // иначе каждое пробуждение сбрасывало бы его отсчёт заново.
  try {
    const a = await chrome.alarms.get('althub-login-watch');
    if (!a) { await chrome.alarms.create('althub-login-watch', { periodInMinutes: 0.5 }); }
  } catch {}

  // Здороваемся сразу: так AltHub понимает, что расширение вообще
  // загрузилось. На обычном Chrome 137+ флаг --load-extension молча
  // игнорируется, расширения нет, и без этого приветствия AltHub впустую
  // ждал бы пять минут вместо того, чтобы честно сказать, что не вышло.
  try { await fetch('http://127.0.0.1:' + p + '/hello'); } catch {}
}

async function trySendLoginCookie() {
  const st = await S.get();
  if (st.sent || !st.loginPort || !st.ready) return;

  const value = await readRobloSecurity();
  if (!value) return;

  if (st.banned.indexOf(value) >= 0) {
    // Chrome восстановил прошлую сессию уже после уборки. Это НЕ новый вход.
    console.log('[AltHub] это ещё старая кука, снимаю снова и жду настоящую');
    await removeRobloSecurity();
    setTimeout(() => { trySendLoginCookie().catch(() => {}); }, 500);
    return;
  }

  try {
    const result = await postCookie(st.loginPort, st.loginToken, value);
    if (!result.ok) throw new Error('HTTP ' + result.status + ': ' + result.text);
    await S.set({ sent: true });
    console.log('[AltHub] окно входа: кука подтверждена и передана');
  } catch (e) {
    console.log('[AltHub] окно входа: отправка не удалась:', e);
    await S.set({ sent: false });
  }
}

// ============================ переходы по страницам ============================

async function noteLoginPortAndReload(p, tabId, token) {
  // Снять старую куку и ПЕРЕЗАГРУЗИТЬ страницу.
  //
  // Запрос на roblox.com/login уходит ещё со старой .ROBLOSECURITY: снять её
  // мы успеваем только после того, как переход уже зафиксирован. Roblox
  // видит живую сессию и уводит с формы входа на главную — под прошлым
  // аккаунтом. Кука к этому моменту уже снята локально и попала в
  // запрещённые, поэтому отправлять нечего, а обновить страницу человеку
  // нечем: режим --app не даёт ни адресной строки, ни кнопки обновления.
  const before = await S.get();
  const first = before.loginPort !== p;
  await noteLoginPort(p, token);
  if (first && tabId) {
    try { await chrome.tabs.reload(tabId); } catch {}
  }
}

chrome.webNavigation.onCommitted.addListener((d) => {
  if (d.frameId !== 0) return;
  let host;
  try { host = new URL(d.url).hostname; } catch { return; }

  // способ 2: наша собственная страница на 127.0.0.1
  if (isLoopback(host)) {
    const loginPort = extractPortFromUrl(d.url, 'althub_login');
    if (loginPort) {
      const token = new URL(d.url).searchParams.get('althub_token') || '';
      noteLoginPort(loginPort, token)
        .then(() => chrome.tabs.update(d.tabId, { url: 'https://www.roblox.com/login' }))
        .catch((e) => console.log('[AltHub] login bootstrap ошибка:', e));
      return;
    }
    const p = extractPortFromUrl(d.url, 'althub_grab');
    if (p) {
      // Порт уже известен из адреса — не ищем его заново по всему диапазону.
      // Намеренно без await: обработчик не должен держать переход.
      const token = new URL(d.url).searchParams.get('althub_token') || '';
      grabAndSend(d.tabId, p, token).catch((e) => console.log('[AltHub] grab ошибка:', e));
    }
    return;
  }

  // способ 3: окно входа
  if (!isRobloxHost(host)) return;
  const p = extractPortFromUrl(d.url, 'althub_port');
  if (p) {
    // Тоже без await: уборка кук трогает хранилище, и на холодном профиле
    // это может занять заметное время — ожидание здесь подвешивало саму
    // навигацию страницы.
    const token = new URL(d.url).searchParams.get('althub_token') || '';
    noteLoginPortAndReload(p, d.tabId, token).catch((e) => console.log('[AltHub] noteLoginPort ошибка:', e));
  }
});

chrome.webNavigation.onCompleted.addListener((d) => {
  if (d.frameId !== 0) return;
  try {
    if (!isRobloxHost(new URL(d.url).hostname)) return;
  } catch {
    return;
  }
  trySendLoginCookie();
});

// Ловит Set-Cookie на XHR после капчи, без полной навигации (SPA).
chrome.cookies.onChanged.addListener((info) => {
  if (info.removed) return;
  if (info.cookie.name !== '.ROBLOSECURITY') return;
  if (!isRobloxHost(info.cookie.domain)) return;
  trySendLoginCookie();
});

// ПОСЛЕДНЯЯ СТРАХОВКА. События выше могут не прийти: Roblox после входа
// меняет страницу своими средствами, без полной навигации, а Set-Cookie мог
// случиться в тот момент, когда расширение спало. Поэтому пока идёт вход,
// раз в 20 секунд просто проверяем, не появилась ли новая кука.
// chrome.alarms будит расширение, даже если оно уснуло, — на этом всё и держится.
chrome.alarms.onAlarm.addListener(async (a) => {
  if (a.name !== 'althub-login-watch') return;
  const st = await S.get();
  if (!st.ready) {
    await prepareSession();
  }
  if (!st.loginPort || st.sent) {
    // Вход закончен — будильник больше не нужен. Заводится он заново в
    // noteLoginPort, при начале следующего входа: раньше его создавал только
    // код верхнего уровня, то есть лишь при холодном пробуждении, и «последняя
    // страховка» отсутствовала ровно тогда, когда была нужна.
    try { await chrome.alarms.clear('althub-login-watch'); } catch {}
    return;
  }
  await trySendLoginCookie();
});
