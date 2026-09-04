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
// ===================== ТРИ СПОСОБА, КАК ЭТО ЗАПУСКАЕТСЯ =====================
//
// 1) КНОПКА НА ПАНЕЛИ (или Alt+Shift+A). Ты уже сидишь на roblox.com под
//    нужным аккаунтом — жмёшь значок AltHub рядом с адресной строкой.
//    Расширение ищет AltHub на нескольких портах подряд и отдаёт куку ему.
//    Ничего не открывается и не мигает.
//
// 2) F10 ИЗ САМОГО ALTHUB. AltHub открывает в браузере по умолчанию свою
//    страницу http://127.0.0.1:ПОРТ/grab, расширение видит переход на неё,
//    забирает куку, отдаёт и закрывает вкладку. Вкладка мелькает на долю
//    секунды — это цена за то, что иначе усыплённое расширение не разбудить.
//    Адрес локальный, поэтому на серверы Roblox не уходит ни номер порта,
//    ни сам факт нажатия.
//
// 3) ОКНО ВХОДА ALTHUB. AltHub сам запускает отдельное окно браузера с этим
//    расширением и открывает roblox.com/login?althub_port=ПОРТ. Здесь, и
//    ТОЛЬКО здесь, перед входом снимается старая .ROBLOSECURITY: иначе Chrome
//    восстановит прошлую сессию и мы отдадим не тот аккаунт. Метки устройства
//    (RBXEventTrackerV2 / browserid, rbx-ip2) не трогаются — без них Roblox
//    считает каждый вход новым железом и поднимает сложность капчи.

// Порты, на которых AltHub ждёт куку от кнопки и горячей клавиши. Фиксированный
// небольшой диапазон, а не один порт: вдруг соседняя программа занята первым.
const BRIDGE_PORTS = [52713, 52714, 52715, 52716, 52717];

// --- состояние окна входа (способ 3) ---
let loginPort = null;
let alreadySent = false;
let readyToCapture = false;
let preparing = false;
const bannedValues = new Set();

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

async function postCookie(port, value) {
  const resp = await fetch('http://127.0.0.1:' + port + '/cookie', {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain' },
    body: value
  });
  return resp.ok;
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
      if (t === 'althub') return port;
    } catch {
      // порт закрыт или занят кем-то другим — идём дальше
    }
  }
  return null;
}

async function grabAndSend(closeTabId) {
  const value = await readRobloSecurity();
  if (!value) {
    console.log('[AltHub] на roblox.com нет входа — нечего передавать');
    await notify('В браузере нет входа на roblox.com. Зайди в аккаунт и повтори.');
    if (closeTabId) { try { await chrome.tabs.remove(closeTabId); } catch {} }
    return false;
  }

  const port = await findBridgePort();
  if (!port) {
    console.log('[AltHub] AltHub не отвечает ни на одном порту моста');
    await notify('AltHub не отвечает. Открой его и включи приём в настройках.');
    if (closeTabId) { try { await chrome.tabs.remove(closeTabId); } catch {} }
    return false;
  }

  let ok = false;
  try {
    ok = await postCookie(port, value);
  } catch (e) {
    console.log('[AltHub] отправка не удалась:', e);
  }
  console.log('[AltHub] передано в AltHub на порт', port, '=', ok);
  if (closeTabId) { try { await chrome.tabs.remove(closeTabId); } catch {} }
  return ok;
}

async function notify(text) {
  // Тихо: без прав на уведомления просто пишем в консоль расширения.
  // Человек всё равно увидит результат в самом AltHub.
  console.log('[AltHub] ' + text);
}

chrome.action.onClicked.addListener(() => { grabAndSend(null); });
chrome.commands.onCommand.addListener((cmd) => {
  if (cmd === 'althub-grab') grabAndSend(null);
});

// ============================ способ 3: окно входа ============================

async function removeRobloSecurity() {
  let list = [];
  try {
    list = await chrome.cookies.getAll({ name: '.ROBLOSECURITY' });
  } catch (e) {
    console.log('[AltHub] cookies.getAll ошибка:', e);
    return;
  }
  for (const c of list) {
    if (!isRobloxHost(c.domain)) continue;
    if (c.value) bannedValues.add(c.value);
    try {
      await chrome.cookies.remove({ url: cookieUrl(c), name: '.ROBLOSECURITY' });
      console.log('[AltHub] снята старая .ROBLOSECURITY с', c.domain, c.path);
    } catch (e) {
      console.log('[AltHub] не удалось снять куку с', c.domain, e);
    }
  }
}

async function prepareSession() {
  if (preparing || readyToCapture || !loginPort) return;
  preparing = true;
  try {
    // Один проход достаточно: onCompleted и onChanged подстрахуют повторной
    // проверкой bannedValues, если сессия восстановится позже. Раньше здесь
    // был sleep(800) + повторная уборка — на холодном профиле это держало
    // хранилище кук занятым ровно тогда, когда страница пыталась их читать
    // для своей навигации, и переход подвисал на сером экране.
    await removeRobloSecurity();
    readyToCapture = true;
  } catch (e) {
    console.log('[AltHub] prepareSession ошибка:', e);
    readyToCapture = true;
  } finally {
    preparing = false;
  }
}

async function noteLoginPort(p) {
  if (!p || p === loginPort) {
    if (p && !readyToCapture && !preparing) await prepareSession();
    return;
  }
  loginPort = p;
  alreadySent = false;
  readyToCapture = false;
  bannedValues.clear();
  console.log('[AltHub] окно входа: порт', p);
  await prepareSession();

  // Здороваемся сразу: так AltHub понимает, что расширение вообще
  // загрузилось. На обычном Chrome 137+ флаг --load-extension молча
  // игнорируется, расширения нет, и без этого приветствия AltHub впустую
  // ждал бы пять минут вместо того, чтобы честно сказать, что не вышло.
  try { await fetch('http://127.0.0.1:' + p + '/hello'); } catch {}
}

async function trySendLoginCookie() {
  if (alreadySent || !loginPort || !readyToCapture) return;

  const value = await readRobloSecurity();
  if (!value) return;

  if (bannedValues.has(value)) {
    // Chrome восстановил прошлую сессию уже после уборки. Это НЕ новый вход.
    console.log('[AltHub] это ещё старая кука, снимаю снова и жду настоящую');
    await removeRobloSecurity();
    return;
  }

  alreadySent = true;
  try {
    await postCookie(loginPort, value);
    console.log('[AltHub] окно входа: кука передана');
  } catch (e) {
    console.log('[AltHub] окно входа: отправка не удалась:', e);
    alreadySent = false;
  }
}

// ============================ переходы по страницам ============================

chrome.webNavigation.onCommitted.addListener((d) => {
  if (d.frameId !== 0) return;
  let host;
  try { host = new URL(d.url).hostname; } catch { return; }

  // способ 2: наша собственная страница на 127.0.0.1
  if (isLoopback(host)) {
    const p = extractPortFromUrl(d.url, 'althub_grab');
    if (p) {
      // Намеренно без await: обработчик не должен держать переход.
      grabAndSend(d.tabId).catch((e) => console.log('[AltHub] grab ошибка:', e));
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
    noteLoginPort(p).catch((e) => console.log('[AltHub] noteLoginPort ошибка:', e));
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
