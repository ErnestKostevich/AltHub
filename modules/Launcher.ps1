#requires -Version 5.1
<#
================================================================================
 Launcher.ps1 — поиск клиента, мультизапуск и старт игры
================================================================================
 Здесь три вещи:

 1) Поиск RobloxPlayerBeta.exe — берём САМУЮ НОВУЮ из установленных версий,
    определяя её по версии самого файла. Реестр для этого не годится: Roblox
    обновляется молча и обновляет ветку реестра с задержкой, а запуск
    устаревшего клиента приводит к тому, что он дёргает установщик, а тот
    закрывает уже открытые окна Roblox.
    Ничего не скачиваем и не устанавливаем: запускаем твой уже установленный
    клиент, просто правильной версии.

 2) Мультизапуск — два замка, оба берутся ДО первого запуска Roblox.

    Замок 1: "ROBLOX_singletonMutex" — классическая одиночная блокировка
    клиента. Держим его, пока открыт менеджер.

    Замок 2: "ROBLOX_singletonEvent" — вот здесь главное, и здесь же обычно
    ломаются самодельные менеджеры. На нынешних версиях клиента уже открытый
    Roblox ЖДЁТ на этом событии, а каждый новый клиент его ВЗВОДИТ. Получив
    сигнал, старый клиент закрывает своё окно. В его собственном логе это
    видно дословно:

        [FLog::WndProcessCheck] ... EventWaitResultUpdate
        [FLog::Systray] Main thread: Received close main window request

    Поэтому просто "держать" событие бесполезно — его именно взводят.
    Мы занимаем ЭТО ЖЕ ИМЯ мьютексом: в Windows пространство имён объектов
    ядра общее для всех типов, так что после этого Roblox не может ни создать
    событие, ни открыть его — подать команду "закройся" ему становится нечем.

    Оба замка — штатные вызовы CreateMutex. Никакого вмешательства в процесс
    Roblox, никакой инъекции в память, никаких драйверов.

 3) Сборка строки запуска. Точно та же строка roblox-player:1+..., которую
    формирует сайт Roblox в браузере, когда ты жмёшь "Play". Разница только
    в том, что билет входа (gameinfo) мы берём для нужного аккаунта.
================================================================================
#>

# --------------------------------------------------------- поиск клиента ----

function Get-RamRobloxClients {
    <#
      Все установленные клиенты с их версиями, новейший первым.

      Почему не по реестру: Roblox обновляется молча, кладёт новую версию в
      соседнюю папку, а ветку реестра обновляет не сразу. Если запустить
      устаревший клиент, он сам дёрнет установщик — а тот ЗАКРЫВАЕТ уже
      открытые окна Roblox. Со стороны это выглядит как "первое окно
      закрылось, осталось только последнее", хотя мультизапуск тут ни при чём.

      Поэтому версию определяем по самому файлу, а не по реестру.
    #>
    $versions = Join-Path $env:LOCALAPPDATA 'Roblox\Versions'
    if (-not (Test-Path -LiteralPath $versions)) { return @() }

    $found = @()
    foreach ($dir in (Get-ChildItem -LiteralPath $versions -Directory -ErrorAction SilentlyContinue)) {
        $exe = Join-Path $dir.FullName 'RobloxPlayerBeta.exe'
        if (-not (Test-Path -LiteralPath $exe)) { continue }

        $item = Get-Item -LiteralPath $exe
        if ($item.Length -lt 100000) { continue }   # недокачанный файл

        # FileVersion выглядит как "0, 735, 3, 7351147" — приводим к [version].
        $ver = $null
        try {
            $digits = $item.VersionInfo.FileVersion -replace '[^0-9,]', ''
            $parts  = @($digits -split ',' | Where-Object { $_ -ne '' } | Select-Object -First 4)
            if ($parts.Count -ge 2) { $ver = [version]($parts -join '.') }
        } catch { }
        if ($null -eq $ver) { $ver = [version]'0.0.0.0' }

        $found += [pscustomobject]@{
            Path    = $exe
            Folder  = $dir.Name
            Version = $ver
            Written = $item.LastWriteTime
        }
    }

    return @($found | Sort-Object Version, Written -Descending)
}

function Get-RamRegisteredPlayerPath {
    <# Что прописано в реестре как обработчик roblox-player. Может отставать. #>
    $regPaths = @(
        'HKCU:\Software\Classes\roblox-player\shell\open\command',
        'HKCU:\Software\roblox-player\shell\open\command',
        'HKLM:\SOFTWARE\Classes\roblox-player\shell\open\command'
    )
    foreach ($rp in $regPaths) {
        try {
            $cmd = (Get-ItemProperty -LiteralPath $rp -ErrorAction Stop).'(default)'
            if ($cmd -match '"([^"]+RobloxPlayerBeta\.exe)"') {
                if (Test-Path -LiteralPath $Matches[1]) { return $Matches[1] }
            }
        } catch { }
    }
    return $null
}

function Get-RamRobloxPlayerPath {
    <# Путь к клиенту, который надо запускать: всегда САМЫЙ НОВЫЙ из
       установленных. Реестр — только запасной вариант. #>
    $clients = @(Get-RamRobloxClients)
    if ($clients.Count -gt 0) { return $clients[0].Path }

    $reg = Get-RamRegisteredPlayerPath
    if ($reg) { return $reg }

    throw 'RobloxPlayerBeta.exe не найден. Установлен ли обычный (не из Microsoft Store) Roblox?'
}

function Test-RamRobloxUpdating {
    <# Идёт ли прямо сейчас обновление. Во время него запускать бессмысленно:
       установщик закроет всё, что успело открыться. #>
    foreach ($n in @('RobloxPlayerInstaller', 'RobloxPlayerLauncher')) {
        if (@(Get-Process -Name $n -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
    }
    return $false
}

function Get-RamOutdatedClientWarning {
    <# Текст предупреждения, если реестр указывает на устаревший клиент.
       Иначе $null. Нужно только для понятного сообщения в журнале. #>
    $clients = @(Get-RamRobloxClients)
    if ($clients.Count -lt 2) { return $null }

    $reg = Get-RamRegisteredPlayerPath
    if (-not $reg) { return $null }

    $regEntry = $clients | Where-Object { $_.Path -eq $reg } | Select-Object -First 1
    if ($null -eq $regEntry) { return $null }
    if ($regEntry.Version -ge $clients[0].Version) { return $null }

    return "Roblox обновился: в реестре ещё старая версия $($regEntry.Version), запускаю новую $($clients[0].Version). Иначе старый клиент дёрнул бы установщик, а тот закрывает открытые окна."
}

function Test-RamMicrosoftStoreRoblox {
    <# Версия из Microsoft Store работает в песочнице и мультизапуск с ней
       не заводится. Полезно предупредить заранее. #>
    try {
        $pkg = Get-AppxPackage -Name 'ROBLOXCORPORATION.ROBLOX' -ErrorAction SilentlyContinue
        return ($null -ne $pkg)
    } catch { return $false }
}

# --------------------------------------------------------- мультизапуск -----

# Держим объекты в глобальной области, чтобы сборщик мусора .NET их не убрал:
# как только мьютекс уничтожится, мультизапуск перестанет работать.
$Global:RamRobloxMutex     = $null
$Global:RamRobloxEventLock = $null

function Test-RamSingletonEventTaken {
    <# $true, если имя ROBLOX_singletonEvent занято НАСТОЯЩИМ событием.
       Так бывает, когда Roblox уже запущен: тогда занять имя мьютексом
       мы уже не сможем, и мультизапуск не включится. #>
    try {
        $e = [System.Threading.EventWaitHandle]::OpenExisting('ROBLOX_singletonEvent')
        $e.Dispose()
        return $true
    } catch {
        return $false
    }
}

function Enable-RamMultiInstance {
    <#
      Берёт оба замка. Возвращает объект состояния:
        MutexHeld        — держим ROBLOX_singletonMutex
        EventBlocked     — имя ROBLOX_singletonEvent занято нами (главное!)
        RobloxWasRunning — Roblox был запущен раньше нас, замок 2 недоступен
    #>
    $eventWasReal = Test-RamSingletonEventTaken

    if ($null -eq $Global:RamRobloxMutex) {
        try   { $Global:RamRobloxMutex = New-Object System.Threading.Mutex($true, 'ROBLOX_singletonMutex') }
        catch { $Global:RamRobloxMutex = $null }
    }

    # Занимаем имя события мьютексом — но только если его ещё не занял
    # настоящим событием уже работающий клиент.
    if ($null -eq $Global:RamRobloxEventLock -and -not $eventWasReal) {
        try   { $Global:RamRobloxEventLock = New-Object System.Threading.Mutex($true, 'ROBLOX_singletonEvent') }
        catch { $Global:RamRobloxEventLock = $null }
    }

    # Убеждаемся, что имя действительно больше не открывается как событие.
    $blocked = $false
    if ($null -ne $Global:RamRobloxEventLock) {
        $blocked = -not (Test-RamSingletonEventTaken)
    }

    return [pscustomobject]@{
        MutexHeld        = ($null -ne $Global:RamRobloxMutex)
        EventBlocked     = $blocked
        RobloxWasRunning = $eventWasReal
    }
}

function Disable-RamMultiInstance {
    <# Отпускаем оба замка при выходе. Уже открытые окна Roblox не пострадают:
       замки нужны только в момент старта нового клиента. #>
    foreach ($name in 'RamRobloxMutex', 'RamRobloxEventLock') {
        $obj = Get-Variable -Name $name -Scope Global -ValueOnly -ErrorAction SilentlyContinue
        if ($null -eq $obj) { continue }
        try { $obj.ReleaseMutex() } catch { }
        try { $obj.Dispose()      } catch { }
        Set-Variable -Name $name -Scope Global -Value $null
    }
}

# ------------------------------------------------------- строка запуска -----

function New-RamPlaceLauncherUrl {
    <#
      Адрес PlaceLauncher.ashx — это то, что клиент дёрнет сам, чтобы получить
      конкретный сервер. Три режима:
        обычный вход          request=RequestGame
        конкретный сервер     request=RequestGameJob&gameId=<JobId>
        приватный сервер      request=RequestPrivateGame&linkCode=<код>
    #>
    param(
        [Parameter(Mandatory)][string]$PlaceId,
        [Parameter(Mandatory)][string]$BrowserTrackerId,
        [string]$JobId,
        [string]$LinkCode
    )

    $base    = 'https://assetgame.roblox.com/game/PlaceLauncher.ashx'
    $attempt = [guid]::NewGuid().ToString()

    if (-not [string]::IsNullOrWhiteSpace($LinkCode)) {
        return "$base`?request=RequestPrivateGame&browserTrackerId=$BrowserTrackerId&placeId=$PlaceId&accessCode=&linkCode=$LinkCode&joinAttemptId=$attempt&joinAttemptOrigin=JoinPrivateServer"
    }
    if (-not [string]::IsNullOrWhiteSpace($JobId)) {
        return "$base`?request=RequestGameJob&browserTrackerId=$BrowserTrackerId&placeId=$PlaceId&gameId=$JobId&isPlayTogetherGame=false&joinAttemptId=$attempt&joinAttemptOrigin=JoinServer"
    }
    return "$base`?request=RequestGame&browserTrackerId=$BrowserTrackerId&placeId=$PlaceId&isPlayTogetherGame=false&joinAttemptId=$attempt&joinAttemptOrigin=PlayButton"
}

function New-RamLaunchUri {
    <#
      Два режима:
        launchmode:play — сразу в игру, нужен адрес PlaceLauncher;
        launchmode:app  — просто открыть Roblox под этим аккаунтом, дальше
                          человек сам выберет игру в клиенте.
      Вход в аккаунт в обоих случаях один и тот же — по билету в gameinfo.
    #>
    param(
        [Parameter(Mandatory)][string]$AuthTicket,
        [string]$PlaceLauncherUrl,
        [Parameter(Mandatory)][string]$BrowserTrackerId,
        [string]$Locale = 'ru_ru'
    )

    $launchTime = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

    if ([string]::IsNullOrWhiteSpace($PlaceLauncherUrl)) {
        return "roblox-player:1+launchmode:app+gameinfo:$AuthTicket+launchtime:$launchTime+browsertrackerid:$BrowserTrackerId+robloxLocale:$Locale+gameLocale:$Locale+channel:"
    }

    $encoded = [System.Uri]::EscapeDataString($PlaceLauncherUrl)

    # Формат один в один как у кнопки "Play" на сайте.
    return "roblox-player:1+launchmode:play+gameinfo:$AuthTicket+launchtime:$launchTime+placelauncherurl:$encoded+browsertrackerid:$BrowserTrackerId+robloxLocale:$Locale+gameLocale:$Locale+channel:"
}

# ------------------------------------------------------------- запуск -------

function Start-RamRobloxInstance {
    <#
      Запускает один клиент под конкретным аккаунтом.
      Возвращает объект Process (нужен, чтобы потом найти его окно).
    #>
    param(
        [Parameter(Mandatory)]$Account,
        [Parameter(Mandatory)][string]$PlayerPath,
        [string]$PlaceId,
        [string]$JobId,
        [string]$LinkCode,
        [string]$Locale = 'ru_ru'
    )

    if ([string]::IsNullOrWhiteSpace($PlaceId)) { $PlaceId  = $Account.PlaceId  }
    if ([string]::IsNullOrWhiteSpace($JobId))   { $JobId    = $Account.JobId    }
    if ([string]::IsNullOrWhiteSpace($LinkCode)){ $LinkCode = $Account.LinkCode }

    # Игра не задана — это не ошибка: откроем клиент на главной под этим
    # аккаунтом, а игру человек выберет сам уже внутри Roblox.
    if ([string]::IsNullOrWhiteSpace($Account.Cookie)) {
        throw "У аккаунта '$($Account.Alias)' не сохранена кука."
    }

    # Постоянный на аккаунт. Раньше он генерировался заново на каждый запуск
    # и тут же выбрасывался — а он нужен, чтобы после перезапуска менеджера
    # опознать уже работающий клиент по его командной строке.
    $btid = $Account.BrowserTrackerId
    if ([string]::IsNullOrWhiteSpace($btid)) {
        $btid = [string](Get-Random -Minimum 100000000000 -Maximum 999999999999)
        $Account.BrowserTrackerId = $btid
    }

    # Билет берём в самый последний момент — он живёт меньше минуты.
    $ticket = Get-RamAuthTicket -Cookie $Account.Cookie

    $plUrl = ''
    if (-not [string]::IsNullOrWhiteSpace($PlaceId)) {
        $plUrl = New-RamPlaceLauncherUrl -PlaceId $PlaceId -BrowserTrackerId $btid `
                                         -JobId $JobId -LinkCode $LinkCode
    }
    $uri   = New-RamLaunchUri -AuthTicket $ticket -PlaceLauncherUrl $plUrl `
                              -BrowserTrackerId $btid -Locale $Locale

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName         = $PlayerPath
    $psi.Arguments        = '"' + $uri + '"'
    $psi.WorkingDirectory = Split-Path -Parent $PlayerPath
    $psi.UseShellExecute  = $true      # запуск от имени текущего пользователя

    $proc = [System.Diagnostics.Process]::Start($psi)

    # Билет одноразовый; в памяти он больше не нужен.
    $ticket = $null
    $uri    = $null

    return $proc
}

function Get-RamRobloxProcesses {
    <# Все живые клиенты Roblox — чтобы показывать статус и уметь закрывать. #>
    Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue
}

function Stop-RamRobloxInstance {
    param([Parameter(Mandatory)][int]$ProcessId)
    try {
        $p = Get-Process -Id $ProcessId -ErrorAction Stop
        $p.CloseMainWindow() | Out-Null
        if (-not $p.WaitForExit(3000)) { $p.Kill() }
        return $true
    } catch {
        return $false
    }
}
