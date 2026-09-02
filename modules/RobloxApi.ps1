#requires -Version 5.1
<#
================================================================================
 RobloxApi.ps1 — все обращения к серверам Roblox
================================================================================
 ЭТО ЕДИНСТВЕННЫЙ ФАЙЛ ВО ВСЕЙ ПРОГРАММЕ, КОТОРЫЙ ХОДИТ В СЕТЬ.
 Полный список адресов, куда он обращается:

   https://auth.roblox.com/v1/authentication-ticket/   — получить билет входа
   https://users.roblox.com/v1/users/authenticated     — узнать ник по куке
   https://apis.roblox.com/universes/v1/places/...     — узнать universeId игры
   https://games.roblox.com/v1/games?universeIds=...   — узнать название игры
   https://economy.roblox.com/v1/users/{id}/currency   — сколько Robux
   https://premiumfeatures.roblox.com/v1/users/...     — есть ли Premium
   https://users.roblox.com/v1/users/{id}              — дата регистрации
   https://thumbnails.roblox.com/v1/users/avatar-headshot — адрес аватарки
   https://tr.rbxcdn.com/...  (CDN самих картинок)     — скачать аватарку

 К двум последним кука НЕ отправляется — аватарки публичные.

 Больше никуда. Ни на какие свои сервера, ни на GitHub, ни в телеметрию.
 Проверить можно файрволом или Fiddler'ом — адреса выше единственные.

 Кука .ROBLOSECURITY уходит ТОЛЬКО в домены roblox.com в заголовке Cookie,
 то есть ровно туда же, куда её отправляет твой браузер при обычном заходе
 на сайт. В логи программы кука не пишется (см. Write-RamLog в главном файле).
================================================================================
#>

# Roblox требует TLS 1.2, а PowerShell 5.1 по умолчанию его не включает.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor [Net.ServicePointManager]::SecurityProtocol
} catch { }

# По умолчанию .NET разрешает лишь 2 одновременных соединения на хост. При
# запуске пачки аккаунтов это лишнее горлышко — поднимаем.
try { [Net.ServicePointManager]::DefaultConnectionLimit = 64 } catch { }

Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

$script:RamHttp = $null

# ============================================================================
#  ОБНОВЛЕНИЕ КУКИ НА ЛЕТУ
#
#  Roblox время от времени выдаёт НОВУЮ .ROBLOSECURITY в заголовке Set-Cookie,
#  а старую через некоторое время перестаёт принимать. Браузер эту новую куку
#  подхватывает — потому он и не разлогинивается месяцами.
#
#  Раньше здесь стоял HttpClient с UseCookies = false, и такие обновления
#  просто выбрасывались. Из-за этого сохранённая кука рано или поздно умирала,
#  и аккаунт приходилось добавлять заново — та самая «нестабильность».
#
#  Теперь Set-Cookie читается, и если Roblox прислал свежую .ROBLOSECURITY,
#  вызывается обработчик: он сохраняет её в аккаунт. Сам этот файл про
#  аккаунты ничего не знает — обработчик регистрирует главная программа.
# ============================================================================
$script:RamOnCookieRefresh = $null

function Register-RamCookieRefreshHandler {
    <# Обработчик получает (старая кука, новая кука). #>
    param([Parameter(Mandatory)][scriptblock]$Handler)
    $script:RamOnCookieRefresh = $Handler
}

function Get-RamRefreshedCookie {
    <#
      Достаёт новую .ROBLOSECURITY из заголовков Set-Cookie ответа.
      Возвращает значение или $null, если Roblox куку не обновлял.
    #>
    param([string[]]$SetCookieHeaders)

    if ($null -eq $SetCookieHeaders) { return $null }

    foreach ($line in $SetCookieHeaders) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^\s*\.ROBLOSECURITY=') { continue }

        # Значение — до первой точки с запятой; дальше идут срок, path и прочее.
        $val = ($line -replace '^\s*\.ROBLOSECURITY=', '')
        $semi = $val.IndexOf(';')
        if ($semi -ge 0) { $val = $val.Substring(0, $semi) }
        $val = $val.Trim()

        # Пустое значение = Roblox гасит куку (разлогин). Это не обновление.
        if ($val.Length -lt 50) { continue }
        return $val
    }
    return $null
}

function Get-RamHttpClient {
    if ($null -ne $script:RamHttp) { return $script:RamHttp }

    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseCookies             = $false   # заголовок Cookie ставим сами
    $handler.AllowAutoRedirect      = $true
    try {
        $handler.AutomaticDecompression =
            [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    } catch { }

    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(25)
    $script:RamHttp = $client
    return $client
}

function Invoke-RamRequest {
    <#
      Тонкая обёртка над HttpClient. Возвращает Status/Headers/Body и НЕ кидает
      исключение на 4xx — коды ошибок нам нужны (403 приносит CSRF-токен).
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST')][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        [string]$Cookie,
        [string]$Csrf,
        [string]$Body
    )

    $client = Get-RamHttpClient
    $req = New-Object System.Net.Http.HttpRequestMessage(
        [System.Net.Http.HttpMethod]::new($Method), $Url)

    if (-not [string]::IsNullOrWhiteSpace($Cookie)) {
        $req.Headers.TryAddWithoutValidation('Cookie', ".ROBLOSECURITY=$Cookie") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($Csrf)) {
        $req.Headers.TryAddWithoutValidation('X-CSRF-TOKEN', $Csrf) | Out-Null
    }
    $req.Headers.TryAddWithoutValidation('Referer', 'https://www.roblox.com/') | Out-Null
    $req.Headers.TryAddWithoutValidation('Origin',  'https://www.roblox.com')  | Out-Null
    $req.Headers.TryAddWithoutValidation('Accept',  'application/json')        | Out-Null
    $req.Headers.TryAddWithoutValidation('User-Agent', 'Roblox/WinInet')       | Out-Null

    if ($Method -eq 'POST') {
        $payload = if ($null -eq $Body) { '' } else { $Body }
        $req.Content = New-Object System.Net.Http.StringContent(
            $payload, [System.Text.Encoding]::UTF8, 'application/json')
    }

    $resp = $client.SendAsync($req).GetAwaiter().GetResult()
    try {
        $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()

        $hdrs = @{}
        foreach ($h in $resp.Headers)         { $hdrs[$h.Key.ToLowerInvariant()] = ($h.Value -join ', ') }
        foreach ($h in $resp.Content.Headers) { $hdrs[$h.Key.ToLowerInvariant()] = ($h.Value -join ', ') }

        # Set-Cookie забираем отдельным списком: склеивать его через запятую
        # нельзя — внутри значения встречается «expires=Wed, 01 Jan ...»,
        # и склейка ломает разбор.
        $setCookies = @()
        try {
            if ($resp.Headers.Contains('Set-Cookie')) {
                $setCookies = @($resp.Headers.GetValues('Set-Cookie'))
            }
        } catch { }

        # Roblox прислал свежую куку — сообщаем наверх, чтобы её сохранили.
        if (-not [string]::IsNullOrWhiteSpace($Cookie) -and $setCookies.Count -gt 0) {
            $fresh = Get-RamRefreshedCookie -SetCookieHeaders $setCookies
            if ($fresh -and $fresh -ne $Cookie -and $null -ne $script:RamOnCookieRefresh) {
                try { & $script:RamOnCookieRefresh $Cookie $fresh } catch { }
            }
        }

        return [pscustomobject]@{
            Status     = [int]$resp.StatusCode
            Headers    = $hdrs
            SetCookies = $setCookies
            Body       = $text
        }
    } finally {
        $resp.Dispose()
        $req.Dispose()
    }
}

# ----------------------------------------------------------- CSRF-токен ----

# Кэш CSRF-токенов. Токен привязан к сессии и живёт долго, а вот запросы к
# auth.roblox.com Roblox считает и при частых обращениях начинает отвечать 429.
# При пяти аккаунтах подряд это ровно тот случай, когда последний не запускался.
# Ключ — короткий отпечаток куки, сама кука в ключах не хранится.
$script:RamCsrfCache = @{}

function Get-RamCookieKey {
    param([string]$Cookie)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Cookie))
    } finally {
        $sha.Dispose()
    }
    return ([BitConverter]::ToString($b) -replace '-', '').Substring(0, 16)
}

function Clear-RamCsrfCache {
    param([string]$Cookie = '')
    if ([string]::IsNullOrEmpty($Cookie)) { $script:RamCsrfCache = @{}; return }
    $script:RamCsrfCache.Remove((Get-RamCookieKey -Cookie $Cookie))
}

function New-RamRateLimitError {
    <#
      Ошибка «Roblox просит подождать». Несёт в себе, сколько именно ждать,
      чтобы вызывающий мог отложить попытку, а НЕ засыпать в UI-потоке.
      Раньше здесь стоял Start-Sleep до 30 секунд, и всё окно замерзало.
    #>
    param([int]$Seconds = 8, [string]$Message = '')

    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "Roblox просит сбавить темп. Повторю через $Seconds с."
    }
    $ex = New-Object System.Exception($Message)
    $ex.Data['RamRetryAfter'] = $Seconds
    return $ex
}

function Get-RamRetryAfterSeconds {
    <# Достаёт паузу из ответа Roblox (заголовок retry-after), с потолком. #>
    param($Response, [int]$Default = 8)

    $wait = $Default
    if ($null -ne $Response -and $Response.Headers.ContainsKey('retry-after')) {
        $ra = 0
        if ([int]::TryParse($Response.Headers['retry-after'], [ref]$ra) -and $ra -gt 0 -and $ra -le 120) {
            $wait = $ra
        }
    }
    return $wait
}

function Get-RamCsrfToken {
    <#
      Roblox требует CSRF-токен на любой POST. Получаем его штатно: делаем
      POST без токена, ловим 403 и заголовок x-csrf-token.

      Специально берём его с authentication-ticket, а НЕ с популярного
      /v2/logout: тот при неудачном стечении реально разлогинивает аккаунт
      и убивает куку. Создание билета входа ничего на аккаунте не меняет.
    #>
    param(
        [Parameter(Mandatory)][string]$Cookie,
        # Пропустить кэш и сходить за свежим токеном.
        [switch]$Force
    )

    $key = Get-RamCookieKey -Cookie $Cookie
    if (-not $Force -and $script:RamCsrfCache.ContainsKey($key)) {
        $c = $script:RamCsrfCache[$key]
        if ((Get-Date) -lt $c.Until) { return $c.Token }
    }

    # Несколько источников токена подряд: Roblox время от времени меняет,
    # какие эндпоинты отвечают 403 с заголовком, а какие — сразу 401.
    # Все три запроса безобидны и ничего на аккаунте не меняют.
    # ПОРЯДОК ВАЖЕН. Раньше первым стоял authentication-ticket — тот же самый
    # эндпоинт, что и сам билет запуска. Каждый аккаунт бил по нему дважды, и
    # на пятом Roblox включал ограничение частоты. Теперь токен берём с
    # ненагруженных эндпоинтов, а auth.roblox.com оставлен на крайний случай.
    $sources = @(
        @{ Url = 'https://catalog.roblox.com/v1/catalog/items/details'; Body = '{"items":[{"itemType":"Asset","id":1}]}' },
        @{ Url = 'https://apis.roblox.com/sharelinks/v1/resolve-link'; Body = '{"linkId":"0","linkType":"Server"}' },
        @{ Url = 'https://auth.roblox.com/v1/authentication-ticket/'; Body = '' }
    )

    # Все три — только чтение. Эндпоинты вроде /v2/logout или /v1/account/pin
    # сюда попасть не должны никогда: первый убивает куку, второй меняет
    # настройки аккаунта.

    $lastStatus = 0
    $lastResponse = $null
    foreach ($src in $sources) {
        try {
            $r = Invoke-RamRequest -Method POST -Url $src.Url -Cookie $Cookie -Body $src.Body
        } catch {
            continue
        }
        $lastResponse = $r
        if ($r.Headers.ContainsKey('x-csrf-token')) {
            $tok = $r.Headers['x-csrf-token']
            if (-not [string]::IsNullOrWhiteSpace($tok)) {
                $script:RamCsrfCache[$key] = [pscustomobject]@{
                    Token = $tok
                    Until = (Get-Date).AddMinutes(20)
                }
                return $tok
            }
        }
        $lastStatus = $r.Status
    }

    # Ограничение частоты — это НЕ проблема аккаунта. Отдаём его отдельной
    # ошибкой с паузой, чтобы очередь запуска просто подождала и повторила.
    if ($lastStatus -eq 429) {
        throw (New-RamRateLimitError -Seconds (Get-RamRetryAfterSeconds -Response $lastResponse))
    }

    # Токен не дали. Прежде чем винить куку, проверим её отдельным запросом —
    # иначе легко получить враньё «кука протухла» на живом аккаунте.
    $who = $null
    try { $who = Get-RamAuthenticatedUser -Cookie $Cookie } catch { }

    if ($null -ne $who) {
        throw "Кука рабочая (аккаунт $($who.Name)), но Roblox не выдал CSRF-токен (HTTP $lastStatus). Это отказ сервера, а не проблема аккаунта — запусти Диагностика.ps1 и покажи вывод."
    }
    throw 'Кука недействительна или протухла — добавь аккаунт заново через мастер.'
}

# --------------------------------------------------------- билет запуска ----

function Get-RamAuthTicket {
    <#
      Двухшаговый штатный механизм самого Roblox:
        1) POST authentication-ticket без CSRF → 403 и заголовок x-csrf-token
           (ничего не меняет на аккаунте, просто отбивка);
        2) тот же POST с этим токеном → заголовок rbx-authentication-ticket.

      Билет одноразовый и живёт меньше минуты — поэтому берём его
      непосредственно перед стартом клиента, а не заранее.

      Специально НЕ используется популярный трюк с POST /v2/logout для добычи
      CSRF: при неудачном стечении он реально разлогинивает аккаунт и убивает
      куку. Здесь такого риска нет.
    #>
    param([Parameter(Mandatory)][string]$Cookie)

    $url = 'https://auth.roblox.com/v1/authentication-ticket/'

    # До трёх попыток: протухший CSRF-токен обновляем и пробуем снова.
    #
    # ГЛАВНОЕ ИСПРАВЛЕНИЕ. Раньше Get-RamCsrfToken звался ВНЕ try/catch, и его
    # исключение при 429 убивало весь цикл попыток на первом же круге — ветка
    # обработки 429 ниже не выполнялась никогда. Отсюда и «максимум четыре
    # аккаунта»: пятому не доставалось билета, и он молча пропадал.
    #
    # Теперь «слишком часто» на любом шаге поднимается наверх отдельной
    # ошибкой с паузой, а очередь запуска откладывает аккаунт и берётся за
    # него позже. Спать в UI-потоке нельзя — окно замерзало на полминуты.
    $r2 = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {

        try {
            $csrf = Get-RamCsrfToken -Cookie $Cookie -Force:($attempt -gt 1)
        } catch {
            throw   # в том числе «слишком часто» — с паузой внутри
        }
        $r2 = Invoke-RamRequest -Method POST -Url $url -Cookie $Cookie -Csrf $csrf -Body ''

        if ($r2.Headers.ContainsKey('rbx-authentication-ticket')) {
            $ticket = $r2.Headers['rbx-authentication-ticket']
            if (-not [string]::IsNullOrWhiteSpace($ticket)) { return $ticket }
        }

        # 403 с новым токеном в заголовке = токен протух, надо повторить.
        if ($r2.Status -eq 403 -and $r2.Headers.ContainsKey('x-csrf-token')) {
            Clear-RamCsrfCache -Cookie $Cookie
            continue
        }

        if ($r2.Status -eq 429) {
            Clear-RamCsrfCache -Cookie $Cookie
            throw (New-RamRateLimitError -Seconds (Get-RamRetryAfterSeconds -Response $r2))
        }

        break
    }

    if ($r2.Status -eq 401 -or $r2.Status -eq 403) {
        # Опять же: сначала убеждаемся, что кука действительно мертва.
        $who = $null
        try { $who = Get-RamAuthenticatedUser -Cookie $Cookie } catch { }
        if ($null -ne $who) {
            throw "Кука рабочая (аккаунт $($who.Name)), но Roblox отказал в билете запуска (HTTP $($r2.Status)). Запусти Диагностика.ps1 и покажи вывод."
        }
        throw 'Кука недействительна или протухла — добавь аккаунт заново через мастер.'
    }
    throw "Roblox не выдал билет запуска (HTTP $($r2.Status))."
}

# ------------------------------------------------------------- аккаунт ------

function Get-RamAuthenticatedUser {
    <# Проверка куки: кто мы. Возвращает Id / Name / DisplayName. #>
    param([Parameter(Mandatory)][string]$Cookie)

    $r = Invoke-RamRequest -Method GET -Url 'https://users.roblox.com/v1/users/authenticated' -Cookie $Cookie
    if ($r.Status -eq 401) { throw 'Кука недействительна или протухла.' }
    if ($r.Status -ne 200) { throw "Ошибка проверки куки (HTTP $($r.Status))." }

    $o = $r.Body | ConvertFrom-Json
    return [pscustomobject]@{
        Id          = [int64]$o.id
        Name        = [string]$o.name
        DisplayName = [string]$o.displayName
    }
}

# ---------------------------------------------------------------- игра ------

function ConvertFrom-RamExploreSorts {
    <#
      Достаёт список игр из ответа explore-api get-sorts. Вынесено отдельно от
      сетевого вызова, чтобы разбор можно было проверить без интернета.

      Берём сорта с играми (contentType = 'Games'), предпочитая «сейчас играют»
      и «в тренде». Склеиваем, убираем повторы по rootPlaceId, сортируем по
      числу игроков. Всё — терпимо к пропущенным полям: формат чужой и может
      меняться.
    #>
    param($Data, [int]$Limit = 30)

    if ($null -eq $Data -or $null -eq $Data.sorts) { return @() }

    # порядок предпочтения сортов
    $rank = @{ 'Top Playing Now' = 0; 'Top Trending' = 1; 'Popular' = 2 }
    $sorts = @($Data.sorts | Where-Object { $_ -and $_.contentType -eq 'Games' -and $_.games })
    $sorts = @($sorts | Sort-Object @{ Expression = { if ($rank.ContainsKey([string]$_.sortDisplayName)) { $rank[[string]$_.sortDisplayName] } else { 99 } } })

    $seen = @{}
    $out  = @()
    foreach ($sort in $sorts) {
        foreach ($g in $sort.games) {
            if ($null -eq $g) { continue }
            $place = [string]$g.rootPlaceId          # НЕ $pid: это автопеременная (PID процесса), только чтение
            $name = [string]$g.name
            if ([string]::IsNullOrWhiteSpace($place) -or [string]::IsNullOrWhiteSpace($name)) { continue }
            if ($seen.ContainsKey($place)) { continue }
            $seen[$place] = $true
            $players = 0; [void][int]::TryParse([string]$g.playerCount, [ref]$players)
            $out += [pscustomobject]@{ Title = $name; PlaceId = $place; Players = $players }
        }
    }
    $out = @($out | Sort-Object -Property Players -Descending)
    if ($out.Count -gt $Limit) { $out = @($out[0..($Limit - 1)]) }
    return @($out)
}

function Get-RamPopularGames {
    <#
      Тянет популярные сейчас игры из Roblox (тот же список, что и на главной
      странице «Discover»). Без авторизации. При любой сетевой беде возвращает
      пустой список — вызывающий покажет понятное сообщение, а не свалится.
    #>
    param([int]$Limit = 30)

    try {
        $sid = [guid]::NewGuid().ToString()
        $r = Invoke-RamRequest -Method GET -Url "https://apis.roblox.com/explore-api/v1/get-sorts?sessionId=$sid"
        if ($r.Status -ne 200) { return @() }
        $data = $r.Body | ConvertFrom-Json
        return @(ConvertFrom-RamExploreSorts -Data $data -Limit $Limit)
    } catch {
        return @()
    }
}

function Get-RamPlaceName {
    <# Название игры по placeId. Без авторизации, чисто для удобства списка. #>
    param([Parameter(Mandatory)][string]$PlaceId)

    try {
        $r = Invoke-RamRequest -Method GET -Url "https://apis.roblox.com/universes/v1/places/$PlaceId/universe"
        if ($r.Status -ne 200) { return '' }
        $universeId = ($r.Body | ConvertFrom-Json).universeId
        if (-not $universeId) { return '' }

        $r2 = Invoke-RamRequest -Method GET -Url "https://games.roblox.com/v1/games?universeIds=$universeId"
        if ($r2.Status -ne 200) { return '' }
        $data = ($r2.Body | ConvertFrom-Json).data
        if ($data -and $data.Count -gt 0) { return [string]$data[0].name }
    } catch { }
    return ''
}

# ------------------------------------------------------- сведения о себе ----

function Get-RamAccountInfo {
    <#
      Собирает то, что полезно видеть, не заходя в игру: сколько Robux,
      есть ли Premium, когда зарегистрирован аккаунт.

      Robux и Premium — это данные ТВОЕГО аккаунта, поэтому запрос идёт с
      кукой. Дата регистрации публичная, кука для неё не нужна.

      Ни один из этих запросов ничего не меняет: всё только на чтение.
      Если какой-то не отвечает — просто оставляем поле пустым, ради
      справочной строки ломать запуск незачем.
    #>
    param(
        [Parameter(Mandatory)][string]$Cookie,
        [Parameter(Mandatory)][int64]$UserId
    )

    $info = [pscustomobject]@{ Robux = -1; Premium = ''; Created = '' }
    if ($UserId -le 0) { return $info }

    try {
        $r = Invoke-RamRequest -Method GET -Url "https://economy.roblox.com/v1/users/$UserId/currency" -Cookie $Cookie
        if ($r.Status -eq 200) {
            $o = $r.Body | ConvertFrom-Json
            if ($null -ne $o.robux) { $info.Robux = [int]$o.robux }
        }
    } catch { }

    try {
        $r = Invoke-RamRequest -Method GET -Url "https://premiumfeatures.roblox.com/v1/users/$UserId/validate-membership" -Cookie $Cookie
        if ($r.Status -eq 200) {
            $info.Premium = $(if ($r.Body.Trim() -eq 'true') { 'yes' } else { 'no' })
        }
    } catch { }

    try {
        $r = Invoke-RamRequest -Method GET -Url "https://users.roblox.com/v1/users/$UserId"
        if ($r.Status -eq 200) {
            $o = $r.Body | ConvertFrom-Json
            if ($o.created) {
                try { $info.Created = ([datetime]$o.created).ToString('yyyy-MM-dd') }
                catch { $info.Created = [string]$o.created }
            }
        }
    } catch { }

    return $info
}

# -------------------------------------------------------------- аватар ------

function Start-RamGetAsync {
    <#
      Запускает GET и СРАЗУ возвращает задачу, не дожидаясь ответа.

      ЗАЧЕМ. Всё остальное в программе ходит в сеть синхронно
      (SendAsync(...).GetAwaiter().GetResult()) — для запуска аккаунта это
      нормально, там всё равно нечего делать. А вот аватарки грузились так же
      и прямо в тике таймера: три штуки за такт при таймауте клиента 25 секунд.
      На плохой сети окно замирало до двух с половиной минут за один тик.

      Теперь вызывающий раз в такт заглядывает в .Task.IsCompleted и не ждёт
      ни миллисекунды. У задачи свой короткий срок: аватарка — украшение,
      висеть из-за неё нельзя.
    #>
    param([Parameter(Mandatory)][string]$Url, [int]$TimeoutSec = 10)

    $client = Get-RamHttpClient
    $req = New-Object System.Net.Http.HttpRequestMessage(
        [System.Net.Http.HttpMethod]::new('GET'), $Url)
    $req.Headers.TryAddWithoutValidation('User-Agent', 'Roblox/WinInet') | Out-Null

    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter([TimeSpan]::FromSeconds($TimeoutSec))

    return [pscustomobject]@{
        Task = $client.SendAsync($req, $cts.Token)
        Req  = $req
        Cts  = $cts
    }
}

function Complete-RamGetAsync {
    <#
      Забирает результат запущенной задачи. Возвращает @{ Ok; Body; Bytes }.
      Ничего не ждёт: звать только когда .Task.IsCompleted уже истинно.
    #>
    param([Parameter(Mandatory)]$Job, [switch]$AsBytes)

    $res = [pscustomobject]@{ Ok = $false; Body = ''; Bytes = $null }
    try {
        if ($Job.Task.Status -ne [System.Threading.Tasks.TaskStatus]::RanToCompletion) { return $res }
        $resp = $Job.Task.Result
        try {
            if (-not $resp.IsSuccessStatusCode) { return $res }
            if ($AsBytes) { $res.Bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult() }
            else          { $res.Body  = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() }
            $res.Ok = $true
        } finally { $resp.Dispose() }
    } catch { }
    finally {
        try { $Job.Req.Dispose() } catch { }
        try { $Job.Cts.Dispose() } catch { }
    }
    return $res
}

function Get-RamAvatarUrl {
    <# Адрес картинки аватарки. Публичный запрос, кука не нужна. #>
    param([Parameter(Mandatory)][int64]$UserId)
    return "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=$UserId&size=150x150&format=Png&isCircular=false"
}

function Get-RamCachedAvatarFile {
    <#
      Путь к уже лежащей в кэше аватарке, если она свежая. Скачиванием НЕ
      занимается — этим ведает неблокирующая очередь в главном файле.
    #>
    param([Parameter(Mandatory)][int64]$UserId, [Parameter(Mandatory)][string]$CacheDir, [int]$MaxAgeDays = 14)

    if ($UserId -le 0) { return $null }
    $file = Join-Path $CacheDir "$UserId.png"
    if (Test-Path -LiteralPath $file) {
        $age = (Get-Date) - (Get-Item -LiteralPath $file).LastWriteTime
        if ($age.TotalDays -lt $MaxAgeDays) { return $file }
    }
    return $null
}

function Invoke-RamDownloadBytes {
    <# Скачивание картинки. Используется только для аватарок. #>
    param([Parameter(Mandatory)][string]$Url)

    $client = Get-RamHttpClient
    $req = New-Object System.Net.Http.HttpRequestMessage(
        [System.Net.Http.HttpMethod]::new('GET'), $Url)
    $req.Headers.TryAddWithoutValidation('User-Agent', 'Roblox/WinInet') | Out-Null

    $resp = $client.SendAsync($req).GetAwaiter().GetResult()
    try {
        if (-not $resp.IsSuccessStatusCode) { return $null }
        return $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    } finally {
        $resp.Dispose(); $req.Dispose()
    }
}

function Get-RamAvatarFile {
    <#
      Кладёт аватарку пользователя в кэш и возвращает путь к файлу.
      Два запроса: адрес картинки у thumbnails.roblox.com, сама картинка —
      с их CDN (домен вида tr.rbxcdn.com). Кука при этом НЕ отправляется:
      аватарки публичные, авторизация не нужна.
    #>
    param(
        [Parameter(Mandatory)][int64]$UserId,
        [Parameter(Mandatory)][string]$CacheDir,
        [int]$MaxAgeDays = 14
    )

    if ($UserId -le 0) { return $null }
    if (-not (Test-Path -LiteralPath $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }

    $file = Join-Path $CacheDir "$UserId.png"
    if (Test-Path -LiteralPath $file) {
        $age = (Get-Date) - (Get-Item -LiteralPath $file).LastWriteTime
        if ($age.TotalDays -lt $MaxAgeDays) { return $file }
    }

    try {
        $url = "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=$UserId&size=150x150&format=Png&isCircular=false"
        $r = Invoke-RamRequest -Method GET -Url $url
        if ($r.Status -ne 200) { return $(if (Test-Path -LiteralPath $file) { $file } else { $null }) }

        $entry = ($r.Body | ConvertFrom-Json).data
        if (-not $entry -or $entry.Count -eq 0) { return $null }
        $imageUrl = [string]$entry[0].imageUrl
        if ([string]::IsNullOrWhiteSpace($imageUrl)) { return $null }

        $bytes = Invoke-RamDownloadBytes -Url $imageUrl
        if ($null -eq $bytes -or $bytes.Length -lt 100) { return $null }

        [System.IO.File]::WriteAllBytes($file, $bytes)
        return $file
    } catch {
        return $(if (Test-Path -LiteralPath $file) { $file } else { $null })
    }
}

function Get-RamImageFromFile {
    <# Загружает картинку в память копией, чтобы файл не остался заблокирован. #>
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $ms    = New-Object System.IO.MemoryStream(,$bytes)
        try {
            # Копия в Bitmap, чтобы можно было закрыть поток. Раньше поток
            # оставался жить вместе с картинкой и не освобождался никогда —
            # при каждой пересборке списка это утекало.
            $src = [System.Drawing.Image]::FromStream($ms)
            try   { return (New-Object System.Drawing.Bitmap($src)) }
            finally { $src.Dispose() }
        } finally { $ms.Dispose() }
    } catch {
        return $null
    }
}

# --------------------------------------------------------- разбор ссылок ----

function ConvertTo-RamPlaceId {
    <#
      Принимает что угодно из буфера обмена и достаёт placeId:
        123456789
        https://www.roblox.com/games/123456789/Some-Name
        roblox.com/games/123456789?privateServerLinkCode=ABC
    #>
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $s = $Value.Trim()

    if ($s -match '^\d+$') { return $s }
    if ($s -match '/games/(\d+)')      { return $Matches[1] }
    if ($s -match '[?&]placeId=(\d+)') { return $Matches[1] }

    return ''
}

function ConvertTo-RamLinkCode {
    <# Достаёт код приватного сервера из ссылки-приглашения. #>
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $s = $Value.Trim()

    if ($s -match '[?&]privateServerLinkCode=([A-Za-z0-9_\-]+)') { return $Matches[1] }
    if ($s -match '[?&]linkCode=([A-Za-z0-9_\-]+)')              { return $Matches[1] }

    return ''
}

function ConvertTo-RamShareLink {
    <#
      Новый формат ссылок Roblox «Поделиться»:
        https://www.roblox.com/share?code=9b0cc1a5...&type=Server

      В самой ссылке НЕТ ни ID игры, ни кода сервера — там только код
      приглашения. Что за ним стоит, знает только сервер Roblox, поэтому
      такую ссылку надо расшифровывать запросом (см. Resolve-RamShareLink).

      Возвращает @{ Code; Type } или $null, если это не share-ссылка.
    #>
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $s = $Value.Trim()

    if ($s -notmatch 'roblox\.com/share') { return $null }
    if ($s -notmatch '[?&]code=([A-Za-z0-9_\-]+)') { return $null }
    $code = $Matches[1]

    $type = 'Server'
    if ($s -match '[?&]type=([A-Za-z]+)') { $type = $Matches[1] }

    return [pscustomobject]@{ Code = $code; Type = $type }
}

function Find-RamJsonValue {
    <#
      Ищет поле по имени на любой глубине ответа. Нужно потому, что Roblox
      время от времени меняет вложенность в ответе resolve-link, а нам важны
      только placeId и linkCode — где бы они ни лежали.
    #>
    param($Node, [Parameter(Mandatory)][string]$Name, [int]$Depth = 0)

    if ($null -eq $Node -or $Depth -gt 8) { return $null }

    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $Node.PSObject.Properties) {
            if ($p.Name -ieq $Name) { return $p.Value }
        }
        foreach ($p in $Node.PSObject.Properties) {
            $r = Find-RamJsonValue -Node $p.Value -Name $Name -Depth ($Depth + 1)
            if ($null -ne $r) { return $r }
        }
    } elseif ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
        foreach ($item in $Node) {
            $r = Find-RamJsonValue -Node $item -Name $Name -Depth ($Depth + 1)
            if ($null -ne $r) { return $r }
        }
    }
    return $null
}

function Resolve-RamShareLink {
    <#
      Спрашивает у Roblox, что стоит за кодом share-ссылки.
      Запрос требует авторизации, поэтому нужна кука любого твоего аккаунта —
      той же, которой ты и так заходишь. Ничего на аккаунте не меняется,
      это запрос на чтение.

      Возвращает @{ PlaceId; LinkCode; GameName; Status }.
    #>
    param(
        [Parameter(Mandatory)][string]$Cookie,
        [Parameter(Mandatory)][string]$Code,
        [string]$LinkType = 'Server'
    )

    $csrf = Get-RamCsrfToken -Cookie $Cookie
    $body = ConvertTo-Json -InputObject @{ linkId = $Code; linkType = $LinkType } -Compress

    $r = Invoke-RamRequest -Method POST -Url 'https://apis.roblox.com/sharelinks/v1/resolve-link' `
                           -Cookie $Cookie -Csrf $csrf -Body $body

    if ($r.Status -eq 400) { throw 'Roblox не принял эту ссылку — возможно, она уже недействительна.' }
    if ($r.Status -eq 401) { throw 'Кука недействительна или протухла — добавь аккаунт заново.' }
    if ($r.Status -ne 200) { throw "Roblox не расшифровал ссылку (HTTP $($r.Status))." }

    $obj = $r.Body | ConvertFrom-Json

    $placeId  = Find-RamJsonValue -Node $obj -Name 'placeId'
    $linkCode = Find-RamJsonValue -Node $obj -Name 'linkCode'
    $status   = Find-RamJsonValue -Node $obj -Name 'status'
    $gameName = Find-RamJsonValue -Node $obj -Name 'placeName'
    if (-not $gameName) { $gameName = Find-RamJsonValue -Node $obj -Name 'gameName' }

    if ($status -and "$status" -notmatch '^(Valid|Success|Ok)$') {
        throw "Roblox ответил про эту ссылку: $status. Скорее всего, приглашение истекло."
    }
    if (-not $placeId -or "$placeId" -eq '0') {
        throw 'Roblox расшифровал ссылку, но не вернул ID игры. Открой ссылку в браузере и скопируй адрес игры оттуда.'
    }

    return [pscustomobject]@{
        PlaceId  = [string]$placeId
        LinkCode = [string]$linkCode
        GameName = [string]$gameName
        Status   = [string]$status
    }
}

function Test-RamJobId {
    <# JobId сервера — это GUID. #>
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value.Trim() -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
}
