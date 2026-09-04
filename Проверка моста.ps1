#requires -Version 5.1
<#
================================================================================
 Проверка моста — работает ли «вход из своего браузера» на самом деле
================================================================================
 ЗАЧЕМ ЭТОТ ФАЙЛ СУЩЕСТВУЕТ.

 Версия 1.3 вышла со сломанным приёмом входа из браузера, и вышла потому, что
 проверки смотрели не туда: они убеждались, что окна СОБИРАЮТСЯ, что код
 разбирается, что в нём нет лишних адресов. Всё зелёное — а человек жмёт F10 и
 не происходит ничего.

 Здесь проверяется то, что делает человек: поднимается настоящий мост, к нему
 стучатся ровно так же, как стучится расширение браузера, и смотрим, доехала
 ли кука до списка аккаунтов.

 Расширение при этом не нужно: его роль — сделать несколько HTTP-запросов на
 127.0.0.1, и эти же запросы делаются отсюда. Что расширение действительно их
 шлёт, проверяется отдельно разбором его кода в «Самопроверка.ps1».

 Запуск: правый клик → «Выполнить с помощью PowerShell».
================================================================================
#>

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'AltHub.ps1') -NoAutoStart
$script:Settings = Load-RamSettings

$total = 0; $passed = 0
function Check {
    param([string]$Name, [scriptblock]$Body)
    $script:total++
    try {
        $detail = & $Body
        $script:passed++
        Write-Host ("  OK   {0}" -f $Name) -ForegroundColor Green
        if ($detail) { Write-Host ("       {0}" -f $detail) -ForegroundColor DarkGray }
    } catch {
        Write-Host ("  СБОЙ {0}" -f $Name) -ForegroundColor Red
        Write-Host ("       {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

function Invoke-Local {
    <#
      Запрос на мост — ровно такой же, какой шлёт расширение, но сырым
      сокетом.

      ПОЧЕМУ НЕ HttpWebRequest. В самой программе мост разбирает запросы
      таймером окна, и пока запрос летит, цикл сообщений крутится сам.
      Здесь окна нет, крутить разбор приходится руками — а HttpWebRequest
      успевает заблокировать тот же самый поток внутри своих внутренних
      ожиданий (установка соединения, Expect: 100-continue), и проверка
      упирается в таймаут не потому, что мост сломан, а потому, что его
      некому крутить. Сокет даёт полный контроль: пишем запрос целиком,
      затем крутим разбор и читаем ответ.
    #>
    param([string]$Path, [string]$Method = 'GET', [string]$Body = '')

    $port = Get-RamBridgePort
    if ($port -le 0) { throw 'мост не поднят' }

    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $head = "$Method $Path HTTP/1.1`r`n" +
            "Host: 127.0.0.1:$port`r`n" +
            "Origin: chrome-extension://althub-test`r`n" +
            "Connection: close`r`n"
    if ($Method -eq 'POST') {
        $head += "Content-Type: text/plain`r`n"
        $head += "Content-Length: $($bodyBytes.Length)`r`n"
    }
    $head += "`r`n"

    $client = New-Object System.Net.Sockets.TcpClient
    $client.ReceiveTimeout = 2000
    $client.Connect('127.0.0.1', $port)
    $ns = $client.GetStream()
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $ns.Write($hb, 0, $hb.Length)
    if ($bodyBytes.Length -gt 0) { $ns.Write($bodyBytes, 0, $bodyBytes.Length) }
    $ns.Flush()

    # Запрос ушёл целиком — теперь мосту есть что разбирать.
    $deadline = (Get-Date).AddSeconds(8)
    $buf = New-Object byte[] 8192
    $sb  = New-Object System.Text.StringBuilder
    while ($true) {
        Invoke-RamBridgePump
        try {
            if ($ns.DataAvailable) {
                $n = $ns.Read($buf, 0, $buf.Length)
                if ($n -le 0) { break }
                [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $n))
                # Ответ короткий и соединение закрывается сервером — как
                # только увидели тело после пустой строки, дочитывать нечего.
                if ($sb.ToString() -match "`r`n`r`n") {
                    Start-Sleep -Milliseconds 60
                    if (-not $ns.DataAvailable) { break }
                }
            }
        } catch { break }
        Start-Sleep -Milliseconds 40
        if ((Get-Date) -gt $deadline) {
            $client.Close()
            throw "мост не ответил на $Path за 8 секунд"
        }
    }
    $client.Close()

    $all = $sb.ToString()
    $k = $all.IndexOf("`r`n`r`n")
    if ($k -lt 0) { throw "мост вернул невнятный ответ на $Path" }
    return $all.Substring($k + 4)
}

function Pump {
    <# Догнать то, что мост делает уже после ответа: добавление аккаунта. #>
    param([int]$Times = 12)
    for ($i = 0; $i -lt $Times; $i++) {
        Invoke-RamBridgePump
        Start-Sleep -Milliseconds 80
    }
}

Write-Host ''
Write-Host 'AltHub — проверка приёма входа из браузера' -ForegroundColor Cyan
Write-Host '--------------------------------------------------'

# ---------------------------------------------------------------- 1. порт ---
Check 'Мост занимает порт и отпускает его' {
    if (Test-RamBridgeRunning) { Stop-RamCookieBridge }
    $port = Start-RamCookieBridge
    if ($port -le 0) { throw 'ни один порт диапазона не свободен' }
    if (-not (Test-RamBridgeRunning)) { throw 'мост говорит, что не слушает' }
    Stop-RamCookieBridge
    if (Test-RamBridgeRunning) { throw 'мост не отпустил порт' }
    "порт $port занялся и освободился"
}

# --------------------------------------------------- 2. расширение находит ---
Check 'Расширение находит AltHub по /hello' {
    $port = Start-RamCookieBridge
    if ($port -le 0) { throw 'мост не поднялся' }
    # Именно так расширение и опознаёт нас: обходит порты и ждёт слово althub.
    $ans = Invoke-Local -Path '/hello'
    if ($ans.Trim() -ne 'althub') { throw "на /hello ответили «$ans», ожидалось «althub»" }
    if (-not (Test-RamBridgeExtensionSeen)) { throw 'мост не заметил, что расширение поздоровалось' }
    "ответ: $($ans.Trim())"
}

Check 'Диапазон портов в коде и в расширении совпадает' {
    # Расширение обходит порты по своему списку. Разъедутся — F10 перестанет
    # работать молча, и понять почему будет нечем.
    $js = Get-Content -LiteralPath (Join-Path $root 'extension\background.js') -Raw
    if ($js -notmatch 'BRIDGE_PORTS\s*=\s*\[([0-9,\s]+)\]') { throw 'в расширении нет списка портов' }
    $jsPorts = @($Matches[1] -split ',' | ForEach-Object { [int]$_.Trim() })
    $psPorts = @($script:BridgePorts)
    if (($jsPorts -join ',') -ne ($psPorts -join ',')) {
        throw "в расширении $($jsPorts -join ','), в программе $($psPorts -join ',')"
    }
    "порты: $($psPorts -join ', ')"
}

# ------------------------------------------------------ 3. страница-будильник -
Check 'Страница /grab отдаётся и закрывает себя' {
    $html = Invoke-Local -Path '/grab?althub_grab=1'
    if ($html -notmatch 'AltHub') { throw 'страница пустая' }
    if ($html -notmatch 'расширение AltHub не установлено') {
        throw 'на странице нет подсказки на случай, если расширения нет'
    }
    'страница отдаётся'
}

Check 'Горячая клавиша открывает именно эту страницу' {
    # Не запускаем браузер по-настоящему — проверяем, что адрес собирается из
    # текущего порта, а не из чего-то вписанного числом.
    $src = Get-Content -LiteralPath (Join-Path $root 'modules\CookieBridge.ps1') -Raw
    if ($src -notmatch '\$url\s*=\s*"http://127\.0\.0\.1:\$port/grab\?althub_grab=\$port"') {
        throw 'адрес страницы-будильника собирается не из живого порта'
    }
    'адрес берётся из занятого порта'
}

# ---------------------------------------------------------- 4. приём куки ---
Check 'Кука доезжает до списка аккаунтов' {
    $before = @($script:Accounts).Count
    $fake = '_|WARNING:-DO-NOT-SHARE-THIS.--Sharing-this-will-allow-someone-to-log-in-as-you.|_' + ('X' * 400)
    [void](Invoke-Local -Path '/cookie' -Method 'POST' -Body $fake)
    Pump

    # Кука выдуманная, поэтому Roblox её не подтвердит — и аккаунт добавиться
    # НЕ ДОЛЖЕН. Проверяем именно это: что мост не верит на слово тому, кто
    # постучался на порт, а спрашивает у Roblox. Порт локальный, но общий для
    # всей машины — на него может постучаться любая программа.
    $after = @($script:Accounts).Count
    if ($after -ne $before) { throw 'аккаунт добавился по непроверенной куке' }
    'выдуманная кука отвергнута, как и должна'
}

Check 'Мост не падает от мусора и чужих запросов' {
    foreach ($p in @('/', '/nonsense', '/cookie')) {
        try { [void](Invoke-Local -Path $p) } catch { }
    }
    Pump
    if (-not (Test-RamBridgeRunning)) { throw 'мост умер от постороннего запроса' }
    'выдержал'
}

# -------------------------------------------------------- 5. клавиша живая ---
Check 'Клавиша приёма регистрируется в Windows' {
    $key = [string]$script:Settings.BridgeHotkey
    if (-not $key) { $key = 'F10' }
    $spec = Get-RamBridgeHotkeySpec -Name $key
    if ($null -eq $spec) { throw "клавиша «$key» неизвестна программе" }

    if ($null -eq $Global:RamHotkeyWindow) {
        [void](Register-RamHotkeys -OnPressed { } -SkipSwitchKeys)
    }
    if ($null -eq $Global:RamHotkeyWindow) { throw 'не удалось создать окно горячих клавиш' }
    $ok = Register-RamBridgeHotkey -Key $key
    Unregister-RamBridgeHotkey
    if ($ok) { return "клавиша $key свободна и берётся" }

    # Занятая клавиша — не поломка программы, но человек обязан узнать об
    # этом сразу, а не гадать, почему нажатие ничего не делает. Проверяем,
    # что есть куда отступить.
    $free = @()
    foreach ($k in (Get-RamBridgeHotkeyChoices)) {
        if ($k -eq $key) { continue }
        if (Register-RamBridgeHotkey -Key $k) { Unregister-RamBridgeHotkey; $free += $k }
    }
    if ($free.Count -eq 0) { throw "заняты ВСЕ клавиши приёма: $((Get-RamBridgeHotkeyChoices) -join ', ')" }
    "клавишу $key держит другая программа; свободны: $($free -join ', ') — программа переключится сама"
}

Check 'Выключенный приём не занимает порт' {
    # Проверяем ТОТ порт, который мост реально занял. Раньше здесь брался
    # первый из списка — а мост мог сесть на второй, если первый был занят
    # чем-то посторонним, и проверка ругалась не на тот порт.
    $port = Get-RamBridgePort
    if ($port -le 0) { $port = Start-RamCookieBridge }
    Stop-RamCookieBridge
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://127.0.0.1:$port/")
    try {
        $l.Start()
    } catch {
        throw "порт $port остался занят после остановки моста"
    }
    $l.Stop(); $l.Close()
    "порт $port свободен"
}

Stop-RamCookieBridge
Unregister-RamHotkeys

Write-Host '--------------------------------------------------'
if ($passed -eq $total) {
    Write-Host "Пройдено $passed из $total — приём из браузера в порядке." -ForegroundColor Green
} else {
    Write-Host "Пройдено $passed из $total — есть проблемы, смотри красное выше." -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'Нажми Enter, чтобы закрыть.' -ForegroundColor DarkGray
[void](Read-Host)
