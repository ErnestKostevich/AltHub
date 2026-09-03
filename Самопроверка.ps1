#requires -Version 5.1
<#
================================================================================
 Самопроверка.ps1 — прогнать все внутренние проверки самому
================================================================================
 Запуск:
   powershell -NoProfile -ExecutionPolicy Bypass -File "Самопроверка.ps1"

 Файл data\accounts.dat НЕ ТРОГАЕТСЯ: шифрование проверяется в памяти, без
 записи на диск. Ни один твой аккаунт не пострадает.

 Твоя кука тоже НЕ показывается: проверка хранилища приложения Roblox выводит
 только ИМЕНА найденных кук и длину значений, но никогда сами значения.

 Из сети дёргается только публичная аватарка (без куки) — и то лишь чтобы
 убедиться, что картинки грузятся.
================================================================================
#>

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# Подключаем главный файл в режиме "без запуска окна" — он сам подтянет модули.
. (Join-Path $root 'AltHub.ps1') -NoAutoStart

# Окно не запускается, поэтому настройки надо поднять руками: часть проверок
# с ними работает. Запись на диск при этом всё равно заблокирована.
$script:Settings = Load-RamSettings

$total  = 0
$passed = 0

function Get-RamAllSource {
    <# Весь исходный код одной строкой: AltHub.ps1 плюс все модули.
       После разбиения файла по смыслу искать только в AltHub.ps1 нельзя —
       проверка «режим main доживает до раскладки» на этом и сорвалась. #>
    $files = @((Join-Path $root 'AltHub.ps1')) + (Get-ChildItem (Join-Path $root 'modules\*.ps1')).FullName
    return (($files | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n")
}

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

Write-Host ''
Write-Host 'AltHub — самопроверка' -ForegroundColor Cyan
Write-Host '--------------------------------------------------'

Check 'Синтаксис всех файлов' {
    $files = @((Join-Path $root 'AltHub.ps1'), (Join-Path $root 'Самопроверка.ps1')) +
             (Get-ChildItem (Join-Path $root 'modules\*.ps1')).FullName
    foreach ($f in $files) {
        $errors = $null; $tokens = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
        if ($errors.Count) {
            throw "$(Split-Path -Leaf $f), строка $($errors[0].Extent.StartLineNumber): $($errors[0].Message)"
        }
    }
    "проверено файлов: $($files.Count)"
}

Check 'Разбор ссылок на игру' {
    $cases = @(
        @{ In = 'https://www.roblox.com/games/920587237/Adopt-Me'; Want = '920587237' },
        @{ In = '920587237';                                       Want = '920587237' },
        @{ In = 'https://roblox.com/games/606849621/X?a=b';        Want = '606849621' },
        @{ In = 'ерунда';                                          Want = ''          }
    )
    foreach ($c in $cases) {
        $got = ConvertTo-RamPlaceId -Value $c.In
        if ($got -ne $c.Want) { throw "'$($c.In)' дал '$got', ожидалось '$($c.Want)'" }
    }
    $lc = ConvertTo-RamLinkCode -Value 'https://www.roblox.com/games/1/X?privateServerLinkCode=aBc-1_x'
    if ($lc -ne 'aBc-1_x') { throw "код приватного сервера: '$lc'" }
    if (-not (Test-RamJobId -Value '11111111-2222-3333-4444-555555555555')) { throw 'верный JobId отвергнут' }
    if (Test-RamJobId -Value 'не-guid') { throw 'неверный JobId принят' }
    "проверок: $($cases.Count + 3)"
}

Check 'Шифрование DPAPI (в памяти, файл не трогается)' {
    if (-not (Test-RamDpapiAvailable)) { throw 'DPAPI недоступен в этой версии PowerShell' }
    $secret = 'кука _|WARNING:-DO-NOT-SHARE-THIS.--ТЕСТ-и-кириллица'
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($secret)
    $env1   = Protect-RamBytes -Data $bytes -Password ''
    if ($env1.mode -ne 'dpapi') { throw "режим '$($env1.mode)'" }
    if ($env1.data -match 'WARNING') { throw 'СЕКРЕТ ВИДЕН В ЗАШИФРОВАННОМ ВИДЕ!' }
    $back = [System.Text.Encoding]::UTF8.GetString((Unprotect-RamBytes -Envelope $env1 -Password ''))
    if ($back -ne $secret) { throw 'расшифровка не совпала с исходником' }
    "шифротекст $($env1.data.Length) симв., открытого текста внутри нет"
}

Check 'Шифрование AES-256 + мастер-пароль (в памяти)' {
    $secret = 'кука _|WARNING:-DO-NOT-SHARE-THIS.--ТЕСТ'
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($secret)
    $env2   = Protect-RamBytes -Data $bytes -Password 'пароль-Тест-123'
    if ($env2.mode -ne 'aes') { throw "режим '$($env2.mode)'" }
    if ($env2.data -match 'WARNING') { throw 'СЕКРЕТ ВИДЕН В ЗАШИФРОВАННОМ ВИДЕ!' }

    $back = [System.Text.Encoding]::UTF8.GetString((Unprotect-RamBytes -Envelope $env2 -Password 'пароль-Тест-123'))
    if ($back -ne $secret) { throw 'расшифровка не совпала с исходником' }

    $rejected = $false
    try { [void](Unprotect-RamBytes -Envelope $env2 -Password 'неверный') } catch { $rejected = $true }
    if (-not $rejected) { throw 'НЕВЕРНЫЙ ПАРОЛЬ НЕ ОТКЛОНЁН!' }

    $tampered = $env2.PSObject.Copy()
    $raw = [Convert]::FromBase64String($tampered.data)
    $raw[0] = $raw[0] -bxor 1
    $tampered.data = [Convert]::ToBase64String($raw)
    $caught = $false
    try { [void](Unprotect-RamBytes -Envelope $tampered -Password 'пароль-Тест-123') } catch { $caught = $true }
    if (-not $caught) { throw 'ПОДМЕНА ФАЙЛА НЕ ОБНАРУЖЕНА!' }

    'неверный пароль и подмена байта отклонены'
}

Check 'Клиент Roblox — берётся самая новая версия' {
    $exe = Get-RamRobloxPlayerPath
    if (-not (Test-Path -LiteralPath $exe)) { throw "путь не существует: $exe" }

    $clients = Get-RamRobloxClients
    if ($clients.Count -eq 0) { throw 'ни одного клиента не найдено' }
    if ($clients[0].Path -ne $exe) { throw 'запускается не самая новая версия' }

    # Список обязан быть отсортирован по убыванию версии
    for ($i = 1; $i -lt $clients.Count; $i++) {
        if ($clients[$i].Version -gt $clients[$i-1].Version) { throw 'версии отсортированы неверно' }
    }

    $reg = Get-RamRegisteredPlayerPath
    $note = ''
    if ($reg -and $reg -ne $exe) { $note = ' (в реестре ещё старая — правильно, что не она)' }
    "версия $($clients[0].Version), всего установлено: $($clients.Count)$note"
}

Check 'Хранилище входов приложения Roblox' {
    if (-not (Test-RamRobloxCookieFile)) {
        throw 'файл не найден — войди в приложение Roblox хотя бы раз (куки придётся вставлять вручную)'
    }
    $records = Read-RamRobloxCookieStore
    if ($records.Count -eq 0) { throw 'файл прочитан, но записей в нём нет' }

    $hasAuth = $records | Where-Object { $_.Name -eq '.ROBLOSECURITY' }
    if (-not $hasAuth) { throw 'запись .ROBLOSECURITY отсутствует — в приложении сейчас никто не вошёл' }

    # Печатаем ТОЛЬКО имена и длины. Значения не выводятся никогда.
    $names = ($records | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', '
    $len   = ($hasAuth | Select-Object -First 1).Value.Length
    $age   = Get-RamRobloxCookieFileAge
    $ageTxt = if ($null -ne $age) { ', обновлён ' + [int]$age.TotalHours + ' ч назад' } else { '' }
    "записей: $($records.Count) [$names]; длина .ROBLOSECURITY: $len симв.$ageTxt"
}

Check 'Сборка строки запуска' {
    $pl = New-RamPlaceLauncherUrl -PlaceId '920587237' -BrowserTrackerId '123456789012'
    if ($pl -notmatch '^https://assetgame\.roblox\.com/game/PlaceLauncher\.ashx\?request=RequestGame&') { throw "обычный вход: $pl" }

    $plPriv = New-RamPlaceLauncherUrl -PlaceId '1' -BrowserTrackerId '2' -LinkCode 'CODE'
    if ($plPriv -notmatch 'request=RequestPrivateGame' -or $plPriv -notmatch 'linkCode=CODE') { throw "приватный сервер: $plPriv" }

    $plJob = New-RamPlaceLauncherUrl -PlaceId '1' -BrowserTrackerId '2' -JobId '11111111-2222-3333-4444-555555555555'
    if ($plJob -notmatch 'request=RequestGameJob' -or $plJob -notmatch 'gameId=1111') { throw "конкретный сервер: $plJob" }

    $uri = New-RamLaunchUri -AuthTicket 'TICKET123' -PlaceLauncherUrl $pl -BrowserTrackerId '123456789012' -Locale 'ru_ru'
    if ($uri -notmatch '^roblox-player:1\+launchmode:play\+gameinfo:TICKET123\+launchtime:\d{13}\+placelauncherurl:https%3A%2F%2Fassetgame') { throw "формат строки: $uri" }
    if ($uri -notmatch '\+browsertrackerid:123456789012\+robloxLocale:ru_ru\+gameLocale:ru_ru\+channel:$') { throw "хвост строки: $uri" }
    'все три режима входа + итоговая строка roblox-player:'
}

Check 'Запуск без игры (просто открыть Roblox)' {
    $uri = New-RamLaunchUri -AuthTicket 'TICKET123' -PlaceLauncherUrl '' -BrowserTrackerId '123456789012' -Locale 'ru_ru'
    if ($uri -notmatch '^roblox-player:1\+launchmode:app\+gameinfo:TICKET123\+launchtime:\d{13}\+browsertrackerid:123456789012') {
        throw "строка режима app: $uri"
    }
    if ($uri -match 'placelauncherurl') { throw 'в режиме без игры остался адрес игры' }
    'launchmode:app собирается, адреса игры в строке нет'
}

Check 'Разбор ссылок «Поделиться»' {
    $sh = ConvertTo-RamShareLink -Value 'https://www.roblox.com/share?code=9b0cc1a540d3aa4cbe1b4ed18ad8b899&type=Server'
    if ($null -eq $sh) { throw 'share-ссылка не распознана' }
    if ($sh.Code -ne '9b0cc1a540d3aa4cbe1b4ed18ad8b899') { throw "код: $($sh.Code)" }
    if ($sh.Type -ne 'Server') { throw "тип: $($sh.Type)" }

    if ($null -ne (ConvertTo-RamShareLink -Value 'https://www.roblox.com/games/123/X')) { throw 'обычная ссылка принята за share' }
    if ($null -ne (ConvertTo-RamShareLink -Value '123456')) { throw 'число принято за share' }

    # Поиск полей на любой глубине ответа Roblox
    $fake = '{"shareLinkType":"Server","privateServerInviteData":{"linkCode":"AbC","placeId":606849621,"status":"Valid"}}' | ConvertFrom-Json
    if ((Find-RamJsonValue -Node $fake -Name 'placeId')  -ne 606849621) { throw 'placeId не найден во вложенном ответе' }
    if ((Find-RamJsonValue -Node $fake -Name 'linkCode') -ne 'AbC')     { throw 'linkCode не найден во вложенном ответе' }
    'код и тип извлекаются, вложенные поля ответа находятся'
}

Check 'Пустой ввод игры = просто Roblox' {
    $g = Resolve-RamGameInput -Value ''
    if ($g.PlaceId -ne '' -or $g.LinkCode -ne '') { throw 'пустой ввод дал непустую игру' }
    $bad = $false
    try { [void](Resolve-RamGameInput -Value 'какая-то ерунда') } catch { $bad = $true }
    if (-not $bad) { throw 'мусор принят за ссылку' }
    'пусто -> без игры, мусор -> понятная ошибка'
}

Check 'Раскладка 5 окон сеткой' {
    $lay = Get-RamTileLayout -Count 5 -Columns 0 -Margin 4
    if ($lay.Count -ne 5) { throw "получено ячеек: $($lay.Count)" }
    for ($i = 0; $i -lt 5; $i++) {
        for ($j = $i + 1; $j -lt 5; $j++) {
            $A = $lay[$i]; $B = $lay[$j]
            if (($A.X -lt $B.X + $B.Width) -and ($B.X -lt $A.X + $A.Width) -and
                ($A.Y -lt $B.Y + $B.Height) -and ($B.Y -lt $A.Y + $A.Height)) {
                throw "ячейки $i и $j перекрываются"
            }
        }
    }
    "окно $($lay[0].Width)x$($lay[0].Height), перекрытий нет"
}

Check 'Раскладки окон: сетка, каскад, колонки, строки, основной крупно' {
    foreach ($mode in @('grid','cascade','columns','rows','main')) {
        $lay = Get-RamTileLayout -Count 5 -Columns 0 -Margin 4 -Mode $mode
        if ($lay.Count -ne 5) { throw "${mode} дал $($lay.Count) ячеек" }
        foreach ($c in $lay) {
            if ($c.Width -lt 400 -or $c.Height -lt 300) { throw "${mode}: окно $($c.Width)x$($c.Height) слишком мелкое" }
            if ($c.X -lt -50 -or $c.Y -lt -50) { throw "${mode}: окно уехало за экран" }
        }
    }
    # В сетке окна не должны перекрываться
    $g = Get-RamTileLayout -Count 5 -Mode 'grid'
    for ($i = 0; $i -lt 5; $i++) { for ($j = $i + 1; $j -lt 5; $j++) {
        $A = $g[$i]; $B = $g[$j]
        if (($A.X -lt $B.X + $B.Width) -and ($B.X -lt $A.X + $A.Width) -and
            ($A.Y -lt $B.Y + $B.Height) -and ($B.Y -lt $A.Y + $A.Height)) { throw 'сетка перекрывается' }
    }}
    # «Основной крупно»: первое окно должно быть заметно больше остальных
    $m = Get-RamTileLayout -Count 5 -Mode 'main'
    if ($m[0].Width -le $m[1].Width) { throw 'в режиме «основной крупно» первое окно не больше остальных' }
    if ($m[0].Height -le $m[1].Height) { throw 'основное окно не выше остальных' }
    for ($i = 1; $i -lt 5; $i++) {
        if ($m[$i].X -lt $m[0].X + $m[0].Width) { throw 'мелкие окна налезают на основное' }
    }
    'все пять режимов считаются, сетка без перекрытий, основной крупнее твинов'
}

Check 'Поиск по аккаунтам' {
    $a = New-RamAccount -Alias 'Основной' -Cookie 'x' -PlaceId '123'
    $a.Username = 'TestPlayer'; $a.UserId = 1234567; $a.GameName = 'Blox Fruits'

    foreach ($q in @('основ', 'TESTPLAY', '12345', 'blox', '123')) {
        if (-not (Test-RamAccountMatches -Account $a -Query $q)) { throw "не нашёл по запросу '$q'" }
    }
    if (Test-RamAccountMatches -Account $a -Query 'мимо') { throw 'нашёл там, где нечего находить' }
    if (-not (Test-RamAccountMatches -Account $a -Query '')) { throw 'пустой запрос должен показывать всех' }
    'ищет по названию, нику, ID и игре, регистр не важен'
}

Check 'Экспорт настроек не содержит кук' {
    $keep = $script:Accounts
    try {
        $a = New-RamAccount -Alias 'Тест' -PlaceId '123' `
                            -Cookie '_|WARNING:-DO-NOT-SHARE-THIS.--СЕКРЕТ-КОТОРЫЙ-НЕ-ДОЛЖЕН-УТЕЧЬ'
        $a.Username = 'test'; $a.UserId = 1; $a.GameName = 'Игра'
        $script:Accounts = @($a)

        $tmp = Join-Path $env:TEMP ('althub-export-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            $cnt = Export-RamSetup -Path $tmp
            if ($cnt -ne 1) { throw "выгружено $cnt аккаунтов вместо 1" }

            $text = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8
            if ($text -match 'WARNING')       { throw 'КУКА ПОПАЛА В ФАЙЛ ЭКСПОРТА!' }
            if ($text -match 'СЕКРЕТ')        { throw 'КУКА ПОПАЛА В ФАЙЛ ЭКСПОРТА!' }
            if ($text -match 'ROBLOSECURITY') { throw 'КУКА ПОПАЛА В ФАЙЛ ЭКСПОРТА!' }
            if ($text -notmatch 'Тест')       { throw 'название аккаунта не выгрузилось' }
            if ($text -notmatch 'Игра')       { throw 'игра не выгрузилась' }

            "файл $([math]::Round((Get-Item $tmp).Length / 1kb, 1)) КБ, кук внутри нет"
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    } finally {
        $script:Accounts = $keep
    }
}

Check 'Мультизапуск: оба замка' {
    # Второй замок можно взять только пока не запущен ни один Roblox. Если
    # клиент открыт — это условие среды, а не поломка: честно сообщаем и
    # не притворяемся, что проверили.
    if (@(Get-RamRobloxProcesses).Count -gt 0) {
        return 'ПРОПУЩЕНО: открыт Roblox, второй замок сейчас не взять. Закрой окна и прогони снова.'
    }

    $lock = Enable-RamMultiInstance
    if (-not $lock.MutexHeld) { Disable-RamMultiInstance; throw 'ROBLOX_singletonMutex не захвачен' }

    $mutexVisible = $false
    try { $m = [System.Threading.Mutex]::OpenExisting('ROBLOX_singletonMutex'); $mutexVisible = $true; $m.Dispose() } catch { }

    # Главное: имя события должно перестать открываться КАК СОБЫТИЕ.
    $eventBlocked = $lock.EventBlocked

    Disable-RamMultiInstance

    # После освобождения имя должно снова стать свободным.
    $freed = -not (Test-RamSingletonEventTaken)

    if (-not $mutexVisible) { throw 'ROBLOX_singletonMutex не виден другим процессам' }
    if (-not $eventBlocked) { throw 'имя ROBLOX_singletonEvent не заблокировано — новый клиент сможет закрыть предыдущий' }
    if (-not $freed)        { throw 'после выхода имя ROBLOX_singletonEvent осталось занятым' }

    'оба замка берутся и корректно отпускаются'
}

Check 'Проверочный режим не трогает твои данные' {
    if (-not $script:ReadOnly) { throw 'режим только-чтение не включился — проверки могут затереть аккаунты' }

    $path = Get-RamAccountsPath
    if (-not (Test-Path -LiteralPath $path)) { return 'файла аккаунтов ещё нет, затирать нечего' }

    $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash

    # Пробуем записать заведомый мусор — запись обязана быть заблокирована.
    $keep = $script:Accounts
    try {
        $junk = New-RamAccount -Alias 'МУСОР' -Cookie 'FAKE' -PlaceId '1'
        $script:Accounts = @($junk)
        Save-RamState
    } finally {
        $script:Accounts = $keep
    }

    $after = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($after -ne $before) { throw 'ЗАПИСЬ ПРОШЛА — проверки могут испортить твои аккаунты!' }

    # Замок должен стоять на самой записи, а не только в Save-RamState:
    # диалог настроек при смене шифрования зовёт Save-RamAccounts напрямую.
    $keep2 = $script:Accounts
    try {
        $script:Accounts = @((New-RamAccount -Alias 'МУСОР-2' -Cookie 'FAKE'))
        Save-RamAccounts -Accounts $script:Accounts -Password ''
    } finally {
        $script:Accounts = $keep2
    }
    $after2 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($after2 -ne $before) { throw 'прямой вызов Save-RamAccounts пробил защиту — тест затирает аккаунты!' }

    # Настройки тоже должны быть защищены
    $sp = Get-RamSettingsPath
    if (Test-Path -LiteralPath $sp) {
        $sBefore = (Get-FileHash -LiteralPath $sp -Algorithm SHA256).Hash
        Save-RamSettings -Settings $script:Settings
        $sAfter  = (Get-FileHash -LiteralPath $sp -Algorithm SHA256).Hash
        if ($sAfter -ne $sBefore) { throw 'настройки перезаписались из проверочного режима' }
    }

    'запись аккаунтов и настроек из проверочного режима заблокирована'
}

Check 'Мои игры: список сохранённых' {
    $keep = $script:Settings.Games
    try {
        $script:Settings.Games = @()

        Add-RamSavedGame -PlaceId '111' -LinkCode ''     -Title 'Первая'
        Add-RamSavedGame -PlaceId '222' -LinkCode 'CODE' -Title 'Вторая'
        Add-RamSavedGame -PlaceId '111' -LinkCode ''     -Title 'Первая'   # дубль

        $g = @($script:Settings.Games)
        if ($g.Count -ne 2) { throw "после дубля стало $($g.Count) записей вместо 2" }
        if ($g[0].PlaceId -ne '111') { throw 'последняя использованная не всплыла наверх' }

        # переполнение списка
        for ($i = 1; $i -le 20; $i++) { Add-RamSavedGame -PlaceId "9$i" -LinkCode '' -Title "Игра $i" }
        if (@($script:Settings.Games).Count -gt 15) { throw 'список не ограничен 15 записями' }

        # значение из списка должно разбираться обратно
        $sug = Get-RamGameSuggestions
        if ($sug.Count -eq 0) { throw 'подсказки пустые' }

        $script:Settings.Games = @()
        Add-RamSavedGame -PlaceId '606849621' -LinkCode 'aBc-1_x' -Title 'Тест'
        $val = (Get-RamGameSuggestions)[0].Value
        $parsed = Resolve-RamGameInput -Value $val
        if ($parsed.PlaceId -ne '606849621') { throw "разбор значения из списка: '$val'" }
        if ($parsed.LinkCode -ne 'aBc-1_x')  { throw 'код приватного сервера потерялся' }
    } finally {
        $script:Settings.Games = $keep
    }
    'дубли убираются, список ограничен 15, выбор разбирается обратно'
}

Check 'Резервные копии входа приложения' {
    if (-not (Test-RamRobloxCookieFile)) { return 'файла входа нет, проверять нечего' }

    $src    = Get-RamRobloxCookieFile
    $srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash

    $backup = Backup-RamRobloxSession -Label 'самопроверка'
    if ($null -eq $backup) { throw 'копия не создалась' }
    try {
        $bh = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
        if ($bh -ne $srcHash) { throw 'копия не совпала с оригиналом' }

        $nowHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
        if ($nowHash -ne $srcHash) { throw 'оригинал изменился при копировании' }
    } finally {
        Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
    }
    'копия создаётся, совпадает с оригиналом, оригинал не трогается'
}

Check 'Настройки клиента для аккаунта' {
    # Пересчёт уровня графики в то, что понимает Roblox
    foreach ($case in @(
        @{ In = 'auto'; Saved = 0 },
        @{ In = '1';    Saved = 1 },
        @{ In = '10';   Saved = 10 },
        @{ In = '99';   Saved = 10 })) {
        $r = Convert-RamGraphicsToLevels -Graphics $case.In
        if ($null -eq $r) { throw "'$($case.In)' дал null" }
        if ($r.Saved -ne $case.Saved) { throw "'$($case.In)' -> $($r.Saved), ждали $($case.Saved)" }
        if ($r.Slider -lt 1 -or $r.Slider -gt 21) { throw "ползунок вне 1..21 для '$($case.In)'" }
    }
    if ($null -ne (Convert-RamGraphicsToLevels -Graphics '')) { throw 'пустое значение должно давать null' }

    # Аккаунт без настроек не должен трогать файл Roblox
    $plain = New-RamAccount -Alias 'без настроек' -Cookie 'x'
    if (Test-RamAccountHasClientSettings -Account $plain) { throw 'пустой аккаунт считается настроенным' }

    $tuned = New-RamAccount -Alias 'настроенный' -Cookie 'x'
    $tuned.Graphics = '1'; $tuned.Volume = '0'
    if (-not (Test-RamAccountHasClientSettings -Account $tuned)) { throw 'настроенный аккаунт не распознан' }

    if (Test-RamRobloxSettingsFile) {
        $path = Get-RamRobloxSettingsPath
        $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        [void](Apply-RamAccountClientSettings -Account $plain)
        $after = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($after -ne $before) { throw 'ФАЙЛ НАСТРОЕК ROBLOX ИЗМЕНИЛСЯ, хотя у аккаунта ничего не задано' }
    }

    $sum = Get-RamAccountSettingsSummary -Account $tuned
    if ($sum -notmatch 'графика 1') { throw "подпись для карточки: '$sum'" }
    'пересчёт уровней верен, пустой аккаунт файл Roblox не трогает'
}

Check 'Обновление куки на лету' {
    <#
      Roblox иногда присылает свежую .ROBLOSECURITY в Set-Cookie. Если её не
      подхватывать, сохранённый вход рано или поздно умирает — это и была
      причина «куки постоянно вылетают».
    #>
    $long = '_|WARNING:-DO-NOT-SHARE-THIS.--test.|_' + ('A' * 400)

    $got = Get-RamRefreshedCookie -SetCookieHeaders @(
        ".ROBLOSECURITY=$long; domain=.roblox.com; path=/; expires=Wed, 01 Jan 2031 00:00:00 GMT; secure; HttpOnly")
    if ($got -ne $long) { throw 'свежая кука не извлеклась из Set-Cookie' }

    $got2 = Get-RamRefreshedCookie -SetCookieHeaders @(
        'RBXEventTrackerV2=CreateDate=1/1/2026; path=/', ".ROBLOSECURITY=$long; path=/; HttpOnly")
    if ($got2 -ne $long) { throw 'не нашлась среди нескольких кук' }

    if ($null -ne (Get-RamRefreshedCookie -SetCookieHeaders @('__cf_bm=abc; path=/'))) {
        throw 'нашли то, чего нет'
    }
    # Разлогин присылает пустое значение — это не обновление
    if ($null -ne (Get-RamRefreshedCookie -SetCookieHeaders @('.ROBLOSECURITY=; expires=Thu, 01 Jan 1970 00:00:00 GMT'))) {
        throw 'пустая кука принята за обновление'
    }
    if ($null -ne (Get-RamRefreshedCookie -SetCookieHeaders $null)) { throw 'null сломал разбор' }

    # Обработчик должен обновлять именно тот аккаунт, чья кука совпала
    $keep = $script:Accounts
    try {
        $a1 = New-RamAccount -Alias 'Первый' -Cookie 'КУКА-1'
        $a2 = New-RamAccount -Alias 'Второй' -Cookie 'КУКА-2'
        $script:Accounts = @($a1, $a2)

        Update-RamRefreshedCookie -OldCookie 'КУКА-1' -NewCookie 'КУКА-1-НОВАЯ'
        if ($a1.Cookie -ne 'КУКА-1-НОВАЯ') { throw 'кука не обновилась' }
        if ($a2.Cookie -ne 'КУКА-2')       { throw 'задело соседний аккаунт' }

        Update-RamRefreshedCookie -OldCookie 'ЧУЖАЯ' -NewCookie 'ПОДМЕНА'
        if ($a1.Cookie -ne 'КУКА-1-НОВАЯ' -or $a2.Cookie -ne 'КУКА-2') { throw 'чужое обновление что-то поменяло' }
    } finally {
        $script:Accounts = $keep
    }

    # Ответ должен нести список Set-Cookie отдельным полем
    $r = Invoke-RamRequest -Method GET -Url 'https://www.roblox.com/'
    if ($null -eq $r.PSObject.Properties['SetCookies']) { throw 'в ответе нет поля SetCookies' }

    "разбор верный, обновляется только нужный аккаунт, Roblox прислал $(@($r.SetCookies).Count) заголовков"
}

Check 'Смайлики в названиях игр' {
    $withEmoji = '[' + [char]::ConvertFromUtf32(0x1F319) + '] Elemental Dungeons'

    if (-not (Test-RamHasEmoji -Text $withEmoji)) { throw 'смайлик не распознан' }
    if (Test-RamHasEmoji -Text 'Blox Fruits')     { throw 'обычное название принято за смайлик' }
    if (Test-RamHasEmoji -Text 'Игра по-русски')  { throw 'кириллица принята за смайлик' }

    $clean = Remove-RamEmoji -Text $withEmoji
    if ($clean -ne 'Elemental Dungeons') { throw "после вычистки: '$clean'" }
    if ((Remove-RamEmoji -Text 'Blox Fruits') -ne 'Blox Fruits') { throw 'обычное название испортилось' }

    # Подпись со смайликом должна получить шрифт, который их рисует
    $l1 = New-RamLabel -Text $withEmoji -X 0 -Y 0 -Width 200
    if ($l1.Font.Name -ne 'Segoe UI Emoji') { throw "подпись со смайликом: шрифт $($l1.Font.Name)" }
    $l2 = New-RamLabel -Text 'Обычная' -X 0 -Y 0 -Width 200
    if ($l2.Font.Name -eq 'Segoe UI Emoji') { throw 'обычной подписи зря сменили шрифт' }

    # Журнал моноширинный — туда смайлики попадать не должны
    $script:UI = @{}
    $safe = Remove-RamEmoji -Text ("Запуск -> " + $withEmoji)
    if (Test-RamHasEmoji -Text $safe) { throw 'смайлик просочился в строку журнала' }

    'распознаются, вычищаются, подписям подставляется нужный шрифт'
}

Check 'Одна галочка читается как одна' {
    <#
      Грабли PowerShell: функция, вернувшая ОДИН элемент, отдаёт его не
      массивом, а одиночным объектом. У PSCustomObject .Count тогда пустой,
      и проверка `if ($x.Count -gt 0)` молча становится ложной — из-за этого
      одна поставленная галочка читалась как «галочек нет».
    #>
    function Test-RamOneItem { $x = @([pscustomobject]@{ Alias = 'Один' }); return @($x) }

    $r = Test-RamOneItem
    if ($null -ne $r.Count) {
        # Если однажды PowerShell это починит — хорошо, но полагаться нельзя.
    }
    if (@(Test-RamOneItem).Count -ne 1) { throw 'обёртка @() не даёт верный счёт' }

    # Ни одного вызова этих функций без обёртки @() остаться не должно
    $root = Split-Path -Parent $PSCommandPath
    $paths = @((Join-Path $root '*.ps1'), (Join-Path $root 'modules\*.ps1'))
    $names = 'TargetAccounts|ActionTargets|VisibleAccounts|Profiles|Groups|OrderedAccounts|RobloxClients|SessionBackups'

    $loose = Select-String -Path $paths -Pattern ('\$\w+ = Get-Ram(' + $names + ')\b[^|]*$') |
             Where-Object { $_.Line -notmatch '= @\(' -and $_.Filename -ne 'Самопроверка.ps1' }
    if ($loose) {
        throw ('вызов без обёртки @(): ' + $loose[0].Filename + ':' + $loose[0].LineNumber)
    }

    'счёт верен для одного элемента, необёрнутых вызовов нет'
}

Check 'Наборы, метки и порядок' {
    $keep = $script:Accounts
    try {
        $a1 = New-RamAccount -Alias 'Первый'  -Cookie 'x'; $a1.Group = 'Фарм';     $a1.Color = 'green'
        $a2 = New-RamAccount -Alias 'Второй'  -Cookie 'x'; $a2.Group = 'Фарм'
        $a3 = New-RamAccount -Alias 'Третий'  -Cookie 'x'; $a3.Group = 'Торговля'
        $script:Accounts = @($a1, $a2, $a3)

        $g = Get-RamGroups
        if ($g.Count -ne 2) { throw "наборов найдено $($g.Count) вместо 2" }

        $script:GroupFilter = 'Фарм'
        if ((Get-RamVisibleAccounts).Count -ne 2) { throw 'фильтр по набору неверен' }
        $script:GroupFilter = ''
        if ((Get-RamVisibleAccounts).Count -ne 3) { throw 'сброс фильтра не сработал' }

        # порядок: третий наверх
        [void](Set-RamAccountOrder -Id $a3.Id -NewIndex 0)
        $order = @(Get-RamOrderedAccounts | ForEach-Object { $_.Alias })
        if ($order[0] -ne 'Третий') { throw "порядок после перемещения: $($order -join ',')" }

        # метка даёт цвет, пустая — нет
        if ($null -eq (Get-RamLabelColor -Key 'green')) { throw 'цвет метки не найден' }
        if ($null -ne (Get-RamLabelColor -Key ''))      { throw 'пустая метка не должна давать цвет' }

        # поиск по заметке и набору
        $a1.Note = 'основной фармер'
        if (-not (Test-RamAccountMatches -Account $a1 -Query 'фарме')) { throw 'поиск по заметке не работает' }
        if (-not (Test-RamAccountMatches -Account $a3 -Query 'торгов')) { throw 'поиск по набору не работает' }
    } finally {
        $script:Accounts = $keep
        $script:GroupFilter = ''
    }
    'наборы, фильтр, порядок, метки и поиск работают'
}

Check 'Отмена последнего действия (Ctrl+Z)' {
    $keep      = $script:Accounts
    $keepStack = $script:UndoStack
    try {
        $script:UndoStack = New-Object System.Collections.ArrayList

        $a1 = New-RamAccount -Alias 'Первый' -Cookie 'x'; $a1.GameName = 'Игра А'; $a1.PlaceId = '111'
        $a2 = New-RamAccount -Alias 'Второй' -Cookie 'x'; $a2.GameName = 'Игра Б'; $a2.PlaceId = '222'
        $script:Accounts = @($a1, $a2)

        # Снимок, затем порча — ровно как при неудачном «убрать игру».
        Push-RamUndo -Label 'проверка'
        foreach ($a in $script:Accounts) { $a.PlaceId = ''; $a.GameName = '' }
        if ($script:Accounts[0].PlaceId -ne '') { throw 'подготовка не сработала' }

        Invoke-RamUndo

        if (@($script:Accounts).Count -ne 2)        { throw 'после отмены не два аккаунта' }
        if ($script:Accounts[0].PlaceId -ne '111')  { throw 'игра первого не вернулась' }
        if ($script:Accounts[1].GameName -ne 'Игра Б') { throw 'название игры второго не вернулось' }
        if ($script:Accounts[0].Id -ne $a1.Id)      { throw 'после отмены подменились Id аккаунтов' }
        if ($script:UndoStack.Count -ne 0)          { throw 'шаг не снялся со стопки' }

        # Отменять нечего — падать не должно.
        Invoke-RamUndo

        # Глубина стопки ограничена, иначе память утекает на копиях списка.
        for ($i = 0; $i -lt 15; $i++) { Push-RamUndo -Label "шаг $i" }
        if ($script:UndoStack.Count -ne 10) { throw "в стопке $($script:UndoStack.Count) шагов вместо 10" }
        if ($script:UndoStack[9].Label -ne 'шаг 14') { throw 'из стопки вытесняются не самые старые шаги' }

        # Снимок должен быть КОПИЕЙ: правка аккаунта не должна менять снимок.
        $script:UndoStack.Clear()
        Push-RamUndo -Label 'копия'
        $script:Accounts[0].Alias = 'Испорчен'
        if ($script:UndoStack[0].Accounts[0].Alias -eq 'Испорчен') {
            throw 'снимок ссылается на живые объекты — отмена ничего не вернёт'
        }
    } finally {
        $script:Accounts  = $keep
        $script:UndoStack = $keepStack
    }
    'снимок, возврат, глубина 10 и независимость копии — всё верно'
}

Check 'Живая строка состояния' {
    $keep      = $script:Accounts
    $keepStack = $script:UndoStack
    $keepHold  = $script:StatusHoldUntil
    $hadStatus = $script:UI.ContainsKey('Status')
    $keepLabel = if ($hadStatus) { $script:UI.Status } else { $null }

    $lbl = New-Object System.Windows.Forms.Label
    try {
        $script:UI.Status       = $lbl
        $script:UndoStack       = New-Object System.Collections.ArrayList
        $script:StatusHoldUntil = [datetime]::MinValue

        $a1 = New-RamAccount -Alias 'Живой' -Cookie 'x'; $a1.CookieOk = 'yes'
        $a2 = New-RamAccount -Alias 'Мёртвый' -Cookie 'x'; $a2.CookieOk = 'no'
        $script:Accounts = @($a1, $a2)

        Update-RamStatusLine
        if ($lbl.Text -notmatch 'отмечено: 0 из 2') { throw "строка без счёта отмеченных: $($lbl.Text)" }
        if ($lbl.Text -notmatch 'мёртвый вход: 1')  { throw "строка не показывает мёртвый вход: $($lbl.Text)" }

        # Разовое сообщение обязано пережить тик таймера, иначе его не прочитать.
        Set-RamStatus 'разовое сообщение'
        Update-RamStatusLine
        if ($lbl.Text -ne 'разовое сообщение') { throw 'живая строка затирает разовое сообщение сразу же' }

        # ...но не навсегда.
        $script:StatusHoldUntil = [datetime]::MinValue
        Update-RamStatusLine
        if ($lbl.Text -eq 'разовое сообщение') { throw 'строка застряла на разовом сообщении' }

        # Пустой список не должен показывать "отмечено: 0 из 0".
        $script:Accounts = @()
        Update-RamStatusLine
        if ($lbl.Text -notmatch 'аккаунтов пока нет') { throw "пустой список: $($lbl.Text)" }
    } finally {
        $lbl.Dispose()
        $script:Accounts        = $keep
        $script:UndoStack       = $keepStack
        $script:StatusHoldUntil = $keepHold
        if ($hadStatus) { $script:UI.Status = $keepLabel } else { [void]$script:UI.Remove('Status') }
    }
    'счёт отмеченных, мёртвые входы и удержание сообщения работают'
}

Check 'Кнопки выбора в диалоге' {
    # Именно этот ряд кнопок показывает починка входов. Раньше он ронял всю
    # программу: локальная $kind писала в параметр $Kind окна, а у того
    # ValidateSet без значения 'normal'. Окно модальное, поэтому поймать это
    # можно только вот так — собрав ряд отдельно от окна.
    $set = @(
        @{ Text = 'Забрать вход';    Value = 'take';   Kind = 'primary' },
        @{ Text = 'Сменить аккаунт'; Value = 'switch' },
        @{ Text = 'Пропустить';      Value = 'skip'   },
        @{ Text = 'Хватит';          Value = 'stop'   }
    )

    $width = 48
    foreach ($b in $set) { $width += [Math]::Max(110, (Get-RamDialogButtonWidth -Text $b.Text)) + 8 }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.ClientSize = New-Object System.Drawing.Size($width, 200)
    try {
        $made = @(Add-RamDialogButtons -Dialog $dlg -Buttons $set -Y 100 -Width $width)
        if ($made.Count -ne $set.Count) { throw "создано кнопок: $($made.Count) из $($set.Count)" }

        # Значение должно лежать на своей кнопке, иначе придёт чужой ответ.
        foreach ($b in $set) {
            $hit = @($made | Where-Object { $_.Tag.Caption -eq $b.Text })
            if ($hit.Count -ne 1)            { throw "кнопка '$($b.Text)' не найдена" }
            if ($hit[0].Tag.Value -ne $b.Value) { throw "у '$($b.Text)' значение '$($hit[0].Tag.Value)'" }
        }

        # Порядок слева направо совпадает с порядком в списке.
        $order = @($made | Sort-Object Left | ForEach-Object { $_.Tag.Caption })
        $want  = @($set | ForEach-Object { $_.Text })
        if (($order -join '|') -ne ($want -join '|')) { throw "порядок: $($order -join ', ')" }

        # Ничего не вылезает за края и не налезает друг на друга.
        $sorted = @($made | Sort-Object Left)
        for ($i = 0; $i -lt $sorted.Count; $i++) {
            $b = $sorted[$i]
            if ($b.Left -lt 0)          { throw "'$($b.Tag.Caption)' вылезла за левый край" }
            if ($b.Right -gt $width)    { throw "'$($b.Tag.Caption)' вылезла за правый край" }
            if ($i -gt 0 -and $b.Left -lt $sorted[$i - 1].Right) {
                throw "'$($b.Tag.Caption)' налезает на соседнюю"
            }
        }
    } finally {
        $dlg.Dispose()
    }
    "$($set.Count) кнопки строятся, значения не путаются, порядок и края в норме"
}

Check 'Переменные не спорят с ValidateSet' {
    # Ловушка на целый класс ошибок. Имена переменных в PowerShell
    # регистронезависимы, поэтому локальная $kind внутри функции с параметром
    # $Kind пишет ИМЕННО В ПАРАМЕТР. А ValidateSet проверяется при каждом
    # присваивании — значит программа падает необрабатываемым исключением.
    # Один раз так и вышло: «значение normal недопустимо для переменной Kind».
    $files = @((Join-Path $root 'AltHub.ps1')) + (Get-ChildItem (Join-Path $root 'modules\*.ps1')).FullName
    $bad = @()
    $seen = 0

    foreach ($f in $files) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
        $funcs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

        foreach ($fn in $funcs) {
            if ($null -eq $fn.Body.ParamBlock) { continue }

            $limited = @{}
            foreach ($prm in $fn.Body.ParamBlock.Parameters) {
                foreach ($att in $prm.Attributes) {
                    if ($att.TypeName.Name -match 'ValidateSet') {
                        $limited[$prm.Name.VariablePath.UserPath.ToLower()] = $true
                    }
                }
            }
            if ($limited.Count -eq 0) { continue }
            $seen += $limited.Count

            $asns = $fn.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)
            foreach ($asn in $asns) {
                if ($asn.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
                $name = $asn.Left.VariablePath.UserPath.ToLower()
                if (-not $limited.ContainsKey($name)) { continue }
                $bad += "$(Split-Path -Leaf $f):$($asn.Extent.StartLineNumber) — `$$name это параметр $($fn.Name) с ValidateSet"
            }
        }
    }

    if ($bad.Count -gt 0) { throw ($bad -join ' | ') }
    "проверено параметров с ограниченным набором: $seen, ни один не переписывается изнутри"
}

Check 'Графика не перетирается соседним запуском' {
    # Файл настроек у Roblox один на все клиенты. Если запустить следующий
    # аккаунт раньше, чем предыдущий клиент дочитает свои настройки, тот
    # подхватит чужую графику. Так у основного и появлялась графика 1.
    $keepInst  = $script:Instances
    $keepQueue = $script:LaunchQueue
    $keepAcc   = $script:Accounts
    $keepFor   = $script:AwaitWindowFor
    $keepUntil = $script:AwaitWindowUntil
    try {
        $main = New-RamAccount -Alias 'Основной' -Cookie 'x'
        $main.Graphics = '10'; $main.Volume = '80'
        $alt  = New-RamAccount -Alias 'Твинк' -Cookie 'x'
        $alt.Graphics = '1'; $alt.Volume = '0'; $alt.FramerateCap = '30'
        $alt2 = New-RamAccount -Alias 'Твинк 2' -Cookie 'x'
        $alt2.Graphics = '1'; $alt2.Volume = '0'; $alt2.FramerateCap = '30'
        $script:Accounts = @($main, $alt, $alt2)

        # Слепки: одинаковые твинки должны совпадать, основной — отличаться.
        if ((Get-RamClientSettingsKey -Account $alt) -ne (Get-RamClientSettingsKey -Account $alt2)) {
            throw 'у одинаковых твинков разные слепки настроек'
        }
        if ((Get-RamClientSettingsKey -Account $main) -eq (Get-RamClientSettingsKey -Account $alt)) {
            throw 'основной и твинк считаются одинаковыми'
        }
        if ((Get-RamClientSettingsKey -Account (New-RamAccount -Alias 'Пустой' -Cookie 'x')) -ne '') {
            throw 'у аккаунта без настроек слепок не пустой'
        }

        $script:Instances  = @{}
        $script:LaunchQueue = New-Object System.Collections.ArrayList

        # Запустили основного, следующий в очереди твинк — настройки другие,
        # значит надо дождаться окна основного.
        $script:Instances[$main.Id] = [pscustomobject]@{ ProcessId = 999999; Handle = [IntPtr]::Zero; Started = (Get-Date) }
        [void]$script:LaunchQueue.Add($alt.Id)
        Set-RamSettingsWait -Launched $main
        if ($script:AwaitWindowFor -ne $main.Id) { throw 'не стал ждать, хотя настройки разные' }
        if (Test-RamSettingsFileFree) { throw 'разрешил писать файл, не дождавшись окна основного' }

        # Окно появилось — можно писать.
        $script:Instances[$main.Id].Handle = [IntPtr]::new(4242)
        if (-not (Test-RamSettingsFileFree)) { throw 'окно есть, а всё ещё ждёт' }
        if ($script:AwaitWindowFor -ne '') { throw 'ожидание не снялось' }

        # Два одинаковых твинка подряд — ждать нечего, иначе очередь тормозит зря.
        $script:Instances[$alt.Id] = [pscustomobject]@{ ProcessId = 999998; Handle = [IntPtr]::Zero; Started = (Get-Date) }
        $script:LaunchQueue.Clear(); [void]$script:LaunchQueue.Add($alt2.Id)
        Set-RamSettingsWait -Launched $alt
        if ($script:AwaitWindowFor -ne '') { throw 'ждёт окна там, где настройки совпадают' }

        # Очередь пуста — ждать тоже нечего.
        $script:LaunchQueue.Clear()
        Set-RamSettingsWait -Launched $main
        if ($script:AwaitWindowFor -ne '') { throw 'ждёт окна с пустой очередью' }

        # Окно так и не появилось — по истечении срока очередь идёт дальше.
        $script:LaunchQueue.Clear(); [void]$script:LaunchQueue.Add($alt.Id)
        Set-RamSettingsWait -Launched $main
        $script:AwaitWindowUntil = (Get-Date).AddSeconds(-1)
        $script:Instances[$main.Id].Handle = [IntPtr]::Zero
        if (-not (Test-RamSettingsFileFree)) { throw 'висит после истечения срока ожидания' }

        # Процесс пропал — ожидание должно сняться само.
        $script:LaunchQueue.Clear(); [void]$script:LaunchQueue.Add($alt.Id)
        Set-RamSettingsWait -Launched $main
        $script:Instances.Remove($main.Id)
        if (-not (Test-RamSettingsFileFree)) { throw 'ждёт клиента, которого уже нет' }
    } finally {
        $script:Instances       = $keepInst
        $script:LaunchQueue     = $keepQueue
        $script:Accounts        = $keepAcc
        $script:AwaitWindowFor  = $keepFor
        $script:AwaitWindowUntil = $keepUntil
    }
    'ждёт только когда настройки разные, не висит по таймауту и на пропавшем клиенте'
}

Check 'Раскладка ждёт появления окон' {
    $keepInst = $script:Instances
    $keepTile = $script:PendingTileUntil
    try {
        # Режим «основной крупно» обязан доживать до раскладки: его ставит
        # «Быстрая настройка», а раньше он молча подменялся сеткой.
        $src = Get-RamAllSource
        if ($src -notmatch "'grid','cascade','columns','rows','main'") {
            throw 'режим main снова не пускают в раскладку — выбор подменится сеткой'
        }

        $script:Instances = @{}

        # Ничего не запущено — ждать нечего, ожидание должно сняться.
        $script:PendingTileUntil = (Get-Date).AddSeconds(25)
        Invoke-RamPendingTile
        if ($script:PendingTileUntil -ne [datetime]::MinValue) { throw 'ожидание не снялось на пустом списке' }

        # Два процесса, окно есть только у одного — раскладку надо придержать.
        $script:Instances['a'] = [pscustomobject]@{ ProcessId = 1; Handle = [IntPtr]::new(111); Started = (Get-Date) }
        $script:Instances['b'] = [pscustomobject]@{ ProcessId = 2; Handle = [IntPtr]::Zero;      Started = (Get-Date) }
        $script:PendingTileUntil = (Get-Date).AddSeconds(25)
        Invoke-RamPendingTile
        if ($script:PendingTileUntil -eq [datetime]::MinValue) {
            throw 'разложил, не дождавшись второго окна — снова будет на одно меньше'
        }

        # Время вышло — дальше держать нельзя, раскладываем что есть.
        $script:PendingTileUntil = (Get-Date).AddSeconds(-1)
        Invoke-RamPendingTile
        if ($script:PendingTileUntil -ne [datetime]::MinValue) { throw 'ожидание висит после истечения срока' }

        # Запуск сразу после появления всех окон ждать не должен.
        $script:Instances['b'].Handle = [IntPtr]::new(222)
        $script:PendingTileUntil = (Get-Date).AddSeconds(25)
        Invoke-RamPendingTile
        if ($script:PendingTileUntil -ne [datetime]::MinValue) { throw 'ждёт, хотя окна уже у всех' }

        # Без ожидания функция не должна делать ничего.
        $script:PendingTileUntil = [datetime]::MinValue
        Invoke-RamPendingTile
    } finally {
        $script:Instances        = $keepInst
        $script:PendingTileUntil = $keepTile
    }
    'раскладка ждёт окна, не висит по таймауту, режим «основной крупно» доживает'
}

Check 'Поля ввода читаются через .Tag.Text' {
    # New-RamTextBox отдаёт ПАНЕЛЬ-обёртку, само поле лежит в .Tag. У панели
    # свой собственный .Text, поэтому обращение к $поле.Text молча читает и
    # пишет не туда. Так сломались сразу два места: тема сохранялась всегда
    # под именем «Моя тема», а «Добавить из браузера» считало любую вставку
    # слишком короткой и отказывалось работать.
    $files = @((Join-Path $root 'AltHub.ps1')) + (Get-ChildItem (Join-Path $root 'modules\*.ps1')).FullName
    $bad = @()
    foreach ($f in $files) {
        $lines = Get-Content -LiteralPath $f
        # Идём сверху вниз и помним, чем переменная является ПРЯМО СЕЙЧАС.
        # Одно и то же имя ($box) в файле бывает и обычным TextBox, и
        # обёрткой — без учёта переприсваивания проверка врёт.
        $vars = @{}
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $ln = $lines[$i]
            if ($ln -match '^\s*\$(\w+)\s*=\s*New-RamTextBox')  { $vars[$Matches[1]] = $true;  continue }
            if ($ln -match '^\s*\$(\w+)\s*=\s*(New-Object|New-RamCombo|New-RamButton|New-RamLabel)') { $vars.Remove($Matches[1]); continue }
            foreach ($v in @($vars.Keys)) {
                if ($ln -match ('\$' + [regex]::Escape($v) + '\.Text\b')) {
                    $bad += "$(Split-Path -Leaf $f):$($i+1)  `$$v.Text вместо `$$v.Tag.Text"
                }
            }
        }
    }
    if ($bad.Count) { throw ($bad -join ' | ') }

    # И проверим на живом контроле, что обёртка правда прячет поле в Tag.
    $tb = New-RamTextBox -Width 200 -Height 30 -Value 'проверка'
    if ([string]$tb.Text -eq 'проверка') { throw 'обёртка вдруг стала пробрасывать Text — проверку надо переписать' }
    if ([string]$tb.Tag.Text -ne 'проверка') { throw 'значение не дошло до самого поля' }
    $tb.Dispose()

    "полей через New-RamTextBox: разобрано, обращений мимо .Tag нет"
}

Check 'Пароль не попадает в журнал' {
    # Вход по паролю убран, но вырезка пароля в журнале осталась: он не должен
    # попасть в журнал ни при каких обстоятельствах, даже из текста ошибки.
    # вырезаем его в Write-RamLog, до вывода и на экран, и в файл.
    $keepUi = $script:UI
    try {
        $box = New-Object System.Windows.Forms.TextBox
        $box.Multiline = $true
        $script:UI = @{ Log = $box }

        $secret = 'Sup3rSecretPass!'
        Write-RamLog ('Ответ сервера: {"ctype":"Username","cvalue":"vasya","password":"' + $secret + '"}') 'err'
        Write-RamLog ("password=$secret") 'err'
        Write-RamLog ("password: $secret") 'err'

        if ($box.Text -match [regex]::Escape($secret)) { throw 'пароль виден в журнале' }
        if ($box.Text -notmatch 'пароль скрыт') { throw 'пароль не заменён пометкой' }

        # И кука по-прежнему режется.
        $box.Clear()
        Write-RamLog ('вход: _|WARNING:-DO-NOT-SHARE-THIS' + ('A' * 300)) 'info'
        if ($box.Text -match 'AAAAAAAAAA') { throw 'кука снова видна в журнале' }
    } finally {
        $script:UI = $keepUi
    }
    'пароль и кука вырезаются до вывода'
}

Check 'Нет обхода защиты от ботов' {
    # Вход по логину и паролю убран: Roblox закрыл его проверкой proofofwork —
    # вычислительной головоломкой против ботов. Решать её за человека нельзя,
    # это ровно обход защиты. Проверяем, что ни решателей капчи, ни этой
    # головоломки в коде не появилось.
    $src = Get-RamAllSource
    foreach ($bad in @('anti-captcha', 'anticaptcha', '2captcha', 'rucaptcha', 'capmonster', 'capsolver')) {
        if ($src -match [regex]::Escape($bad)) { throw "в коде появился сервис разгадывания капчи: $bad" }
    }
    # Вход по паролю ходил ровно на этот адрес. Его возвращение и означало бы,
    # что кто-то снова полез в закрытую Roblox дверь.
    if ($src -match 'auth\.roblox\.com/v2/login') {
        throw 'вернулся вход по паролю — Roblox закрыл его проверкой proofofwork'
    }
    if ($src -match 'challenge/v1/continue') {
        throw 'вернулось прохождение «вызова» Roblox — это часть входа по паролю'
    }
    'решателей капчи нет, вход по паролю не вернулся'
}
Check 'Окно не прячется без значка в часах' {
    # Самая дорогая ошибка 1.1: значок в часах не создавался, а окно всё равно
    # уходило по Hide(). Программа исчезала целиком — ни в панели задач, ни
    # в часах, и вернуть её было нечем.
    $src = Get-RamAllSource

    # 1. Прятать разрешено только вместе с проверкой TrayOk.
    if ($src -notmatch '\$script:UI\.TrayOk') { throw 'признак TrayOk пропал из кода' }
    foreach ($m in [regex]::Matches($src, '(?m)^.*\$this\.Hide\(\).*$|(?m)^.*\$sender\.Hide\(\).*$')) {
        # Ищем ближайшее условие выше — оно обязано упоминать TrayOk.
        $idx = $src.IndexOf($m.Value)
        $before = $src.Substring([Math]::Max(0, $idx - 400), [Math]::Min(400, $idx))
        if ($before -notmatch 'TrayOk') {
            throw "окно прячется без проверки значка: $($m.Value.Trim())"
        }
    }

    # 2. Создание значка больше не глотает ошибку молча.
    if ($src -match 'try\s*\{\s*\$ni\.Icon\s*=\s*New-RamTrayIcon[^}]*\}\s*catch\s*\{\s*\}') {
        throw 'сбой создания значка снова глотается пустым catch'
    }

    # 3. Умолчания скучные: без настройки окно остаётся в панели задач.
    $d = Get-RamDefaultSettings
    if ($d.PSObject.Properties.Name -contains 'OnMinimize') {
        throw 'настройка OnMinimize вернулась — минус обязан ВСЕГДА сворачивать в панель задач'
    }
    if ($d.OnClose -notin @('exit','tray')) { throw "непонятное умолчание крестика: $($d.OnClose)" }
    if ([bool]$d.TrayConfirmed) { throw 'по умолчанию значок в часах не может считаться подтверждённым' }

    'прятать окно можно только при живом значке, умолчания безопасные'
}

Check 'Очередь запуска идёт по порядку списка' {
    # Список сортируется по Order, а отмеченных раньше собирали по порядку
    # хранения массива. Аккаунт, добавленный последним, стоял в списке
    # третьим, а запускался шестым.
    $keepAcc   = $script:Accounts
    $keepCards = $script:Cards
    try {
        $a1 = New-RamAccount -Alias 'Первый'   -Cookie 'x'; $a1.Order = 10
        $a2 = New-RamAccount -Alias 'Второй'   -Cookie 'x'; $a2.Order = 20
        $a3 = New-RamAccount -Alias 'Поздний'  -Cookie 'x'; $a3.Order = 15   # в списке между ними
        # В массиве он ПОСЛЕДНИЙ — как и бывает у только что добавленного.
        $script:Accounts = @($a1, $a2, $a3)

        $script:Cards = @{}
        foreach ($a in $script:Accounts) {
            $cb = New-RamCheckBox -X 0 -Y 0
            $cb.Tag.Checked = $true
            $script:Cards[$a.Id] = [pscustomobject]@{ Check = $cb }
        }

        $order = @(Get-RamTargetAccounts | ForEach-Object { $_.Alias })
        $want  = @('Первый', 'Поздний', 'Второй')
        if (($order -join ',') -ne ($want -join ',')) {
            throw "очередь «$($order -join ', ')» вместо «$($want -join ', ')»"
        }

        # И то же самое должно быть видно в списке.
        $shown = @(Get-RamOrderedAccounts | ForEach-Object { $_.Alias })
        if (($shown -join ',') -ne ($order -join ',')) {
            throw "список «$($shown -join ', ')» разошёлся с очередью «$($order -join ', ')»"
        }
    } finally {
        $script:Accounts = $keepAcc
        $script:Cards    = $keepCards
    }
    'отмеченные отдаются в порядке списка, а не хранения'
}

Check 'Профиль запускает именно отмеченных' {
    $keepAcc = $script:Accounts
    $keepSet = $script:Settings
    try {
        $script:Accounts = @(
            (New-RamAccount -Alias 'A' -Cookie 'x'),
            (New-RamAccount -Alias 'B' -Cookie 'x'),
            (New-RamAccount -Alias 'C' -Cookie 'x')
        )
        # Профиль с поимённым списком не должен подменяться «всеми».
        $prof = [pscustomobject]@{
            Name = 'Двое'; Group = ''; PlaceId = ''; GameName = ''; LinkCode = ''
            Ids  = @($script:Accounts[0].Id, $script:Accounts[2].Id)
        }
        $ids = @($prof.Ids | Where-Object { $_ })
        $picked = @(Get-RamOrderedAccounts | Where-Object { $ids -contains [string]$_.Id })
        if ($picked.Count -ne 2) { throw "по списку выбрано $($picked.Count) вместо 2" }
        if ($picked.Alias -contains 'B') { throw 'в запуск попал неотмеченный аккаунт' }

        # Старый профиль без Ids по-прежнему работает по набору.
        $old = [pscustomobject]@{ Name = 'Старый'; Group = ''; PlaceId = ''; GameName = ''; LinkCode = '' }
        if ($old.PSObject.Properties.Name -contains 'Ids') { throw 'у старого профиля откуда-то взялся Ids' }
    } finally {
        $script:Accounts = $keepAcc
        $script:Settings = $keepSet
    }
    'поимённый список важнее набора, старые профили не ломаются'
}

Check 'Выключенная кнопка не нажимается' {
    # Раньше Set-RamButtonEnabled только перекрашивал кнопку, а обработчик
    # Click оставался живым — серая кнопка отлично срабатывала.
    $script:clicked = 0
    $b = New-RamButton -Text 'Проба' -OnClick { $script:clicked++ }

    $host1 = New-Object System.Windows.Forms.Form
    $host1.Controls.Add($b)

    Set-RamButtonEnabled -Button $b -Enabled $false
    if ($b.Enabled) { throw 'после выключения панель кнопки осталась включённой' }
    if ($b.Tag.Enabled) { throw 'состояние в Tag не обновилось' }

    Set-RamButtonEnabled -Button $b -Enabled $true
    if (-not $b.Enabled -or -not $b.Tag.Enabled) { throw 'кнопка не включилась обратно' }

    # И надпись на выключенной кнопке должна оставаться читаемой размером.
    Set-RamButtonEnabled -Button $b -Enabled $false
    if ($b.Tag.IsHover -or $b.Tag.IsDown) { throw 'осталось состояние наведения на выключенной кнопке' }

    $host1.Dispose()
    'выключение гасит саму панель, состояние наведения сбрасывается'
}

Check 'Кнопка состояния входов не мигает' {
    $keep    = $script:Accounts
    $had     = $script:UI.ContainsKey('FixAll')
    $keepBtn = if ($had) { $script:UI.FixAll } else { $null }

    $btn = New-RamButton -Text 'Проверить входы' -Width 190 -Height 28 -Kind 'ghost'
    $btn.Tag | Add-Member -NotePropertyName Mode -NotePropertyValue 'check' -Force
    try {
        $script:UI.FixAll = $btn

        $a1 = New-RamAccount -Alias 'Живой' -Cookie 'x'; $a1.CookieOk = 'yes'
        $script:Accounts = @($a1)
        Update-RamLoginButton
        if ($btn.Tag.Caption -ne 'Проверить входы') { throw "при живых входах надпись: $($btn.Tag.Caption)" }
        if ($btn.Tag.Mode -ne 'check')              { throw "при живых входах режим: $($btn.Tag.Mode)" }

        $a2 = New-RamAccount -Alias 'Мёртвый' -Cookie 'x'; $a2.CookieOk = 'no'
        $script:Accounts = @($a1, $a2)
        Update-RamLoginButton
        if ($btn.Tag.Caption -ne 'Починить входы (1)') { throw "при мёртвом входе надпись: $($btn.Tag.Caption)" }
        if ($btn.Tag.Mode -ne 'fix:1')                 { throw "при мёртвом входе режим: $($btn.Tag.Mode)" }

        # Повторный вызов не должен ничего менять: он идёт по таймеру каждые
        # две секунды, и лишняя перерисовка — это и есть мигание.
        $was = $btn.Tag.Mode
        Update-RamLoginButton
        if ($btn.Tag.Mode -ne $was) { throw 'состояние скачет при повторном вызове' }

        # Обе надписи обязаны влезать: кнопка привязана к правому краю окна
        # и расти вширь под текст ей нельзя.
        foreach ($cap in @('Проверить входы', 'Починить входы (99)')) {
            $need = [System.Windows.Forms.TextRenderer]::MeasureText($cap, $btn.Tag.Font).Width + 26
            if ($need -gt $btn.Width) { throw "'$cap' не влезает: нужно $need, кнопка $($btn.Width)" }
        }

        # Главное про этот баг: кнопка не должна прятаться. Пропадающая кнопка
        # дёргала макет и оставляла след на перерисовке.
        $src = Get-RamAllSource
        if ($src -match '\$script:UI\.FixAll\.Visible\s*=') {
            throw 'кнопку входов где-то снова прячут — мигание вернётся'
        }
    } finally {
        $script:Accounts = $keep
        if ($had) { $script:UI.FixAll = $keepBtn } else { [void]$script:UI.Remove('FixAll') }
        $btn.Dispose()
    }
    'два состояния, надписи влезают, лишних перерисовок и пряток нет'
}

Check 'Меню правого клика по карточке' {
    $keep = $script:Accounts
    try {
        $acc = New-RamAccount -Alias 'Подопытный' -Cookie 'x'
        $acc.CookieOk = 'no'
        $script:Accounts = @($acc)

        $menu = New-RamCardMenu -AccountId $acc.Id
        if (-not (Build-RamCardMenuItems -Menu $menu -AccountId $acc.Id)) {
            throw 'меню не собралось для существующего аккаунта'
        }

        $texts = @($menu.Items | ForEach-Object { $_.Text })
        foreach ($need in @('Запустить', 'Задать игру...', 'Настройки аккаунта...', 'Убрать из менеджера')) {
            if (-not ($texts | Where-Object { $_ -like "*$need*" })) {
                throw "в меню нет пункта '$need': $($texts -join ' | ')"
            }
        }
        if ($texts[0] -ne 'Подопытный') { throw 'первой строкой меню должно быть имя аккаунта' }
        if (-not ($texts | Where-Object { $_ -like '*мёртв*' })) {
            throw 'мёртвый вход не отмечен в меню'
        }
        # Аккаунт не запущен — «Закрыть окно» показывать нечего.
        if ($texts | Where-Object { $_ -like '*Закрыть окно*' }) {
            throw 'предлагает закрыть окно у незапущенного аккаунта'
        }

        # Обработчики должны брать аккаунт из Tag, а не из замыкания цикла:
        # иначе меню всех карточек будут работать по последнему аккаунту.
        # Заодно и вложенные пункты подменю: составной ключ вида «id|набор»
        # тоже обязан начинаться с нужного аккаунта.
        $checkItems = {
            param($items, [string]$where)
            foreach ($it in $items) {
                if ($it -is [System.Windows.Forms.ToolStripSeparator]) { continue }
                if (-not $it.Enabled) { continue }
                $tag = [string]$it.Tag
                if ($tag -ne $acc.Id -and -not $tag.StartsWith($acc.Id + '|')) {
                    throw "у пункта '$where$($it.Text)' в Tag не тот аккаунт"
                }
                if ($it.PSObject.Properties.Name -contains 'DropDownItems' -and
                    $it.DropDownItems.Count -gt 0) {
                    & $checkItems $it.DropDownItems ("$($it.Text) -> ")
                }
            }
        }
        & $checkItems $menu.Items ''

        # Подменю наборов должно быть на месте и полным.
        $subItem = $menu.Items | Where-Object { $_.Text -like '*Готовый набор*' } | Select-Object -First 1
        if ($null -eq $subItem) { throw 'в меню нет подменю готовых наборов' }
        if ($subItem.DropDownItems.Count -ne @(Get-RamAccountPresets).Count) {
            throw "в подменю наборов $($subItem.DropDownItems.Count) пунктов вместо $(@(Get-RamAccountPresets).Count)"
        }

        # Удалённый аккаунт — меню открываться не должно.
        $script:Accounts = @()
        if (Build-RamCardMenuItems -Menu $menu -AccountId $acc.Id) {
            throw 'меню собирается для уже удалённого аккаунта'
        }

        $menu.Dispose()
    } finally {
        $script:Accounts = $keep
    }
    'пункты собираются по факту, аккаунт берётся из Tag, удалённый не открывается'
}

Check 'Цвет: перевод в строку и обратно' {
    foreach ($hex in @('#00A2FF', '#000000', '#FFFFFF', '#8B6CFF')) {
        $c = ConvertFrom-RamHex -Hex $hex
        if ($null -eq $c) { throw "не разобрал $hex" }
        if ((ConvertTo-RamHex -Color $c) -ne $hex) { throw "$hex не совпал после round-trip" }
    }
    # короткая форма и мусор
    if ((ConvertTo-RamHex -Color (ConvertFrom-RamHex -Hex '#0af')) -ne '#00AAFF') { throw 'короткий hex разобран неверно' }
    if ($null -ne (ConvertFrom-RamHex -Hex 'привет')) { throw 'мусор должен давать $null' }
    if ($null -ne (ConvertFrom-RamHex -Hex '')) { throw 'пустая строка должна давать $null' }

    # HSL round-trip — с допуском на округление
    foreach ($hex in @('#00A2FF', '#10B981', '#F45E96')) {
        $c = ConvertFrom-RamHex -Hex $hex
        $hsl = ConvertTo-RamHsl -Color $c
        $c2 = ConvertFrom-RamHsl -H $hsl.H -S $hsl.S -L $hsl.L
        foreach ($ch in @('R','G','B')) {
            if ([Math]::Abs($c.$ch - $c2.$ch) -gt 2) { throw "$hex не совпал в HSL round-trip по $ch" }
        }
    }
    'hex и HSL переводятся туда-обратно, мусор не роняет'
}

Check 'Тема из акцента всегда читаемая' {
    # Главная гарантия простого режима: какой цвет ни возьми, текст на фоне
    # должен быть виден. Проверяем контраст по яркости на десятке акцентов
    # и на всех трёх основах.
    $accents = @('#00A2FF','#8B6CFF','#10B981','#F45E96','#FB7140','#F59E0B','#EF4444','#FFFFFF','#101010','#22C5D3')
    foreach ($base in @('dark','light','black')) {
        foreach ($hex in $accents) {
            $pal = New-RamDerivedPalette -Accent (ConvertFrom-RamHex -Hex $hex) -Base $base
            $bgL = (ConvertTo-RamHsl -Color $pal.Bg).L
            $txL = (ConvertTo-RamHsl -Color $pal.Text).L
            if ([Math]::Abs($txL - $bgL) -lt 0.45) {
                throw "основа $base, акцент $hex — текст сливается с фоном (разница $([Math]::Round([Math]::Abs($txL-$bgL),2)))"
            }
            # карточка должна отличаться от фона, иначе не видно границ
            $cardL = (ConvertTo-RamHsl -Color $pal.Card).L
            if ([Math]::Abs($cardL - $bgL) -lt 0.015 -and $base -ne 'light') {
                throw "основа $base, акцент $hex — карточка сливается с фоном"
            }
            # все 15 ключей должны быть цветами
            foreach ($k in @('Bg','Panel','Card','CardHover','CardSel','Border','Text','Muted','Accent','AccentHov','Ok','Warn','Danger','DangerHov','LogBack')) {
                if ($pal[$k] -isnot [System.Drawing.Color]) { throw "ключ $k не цвет при $base/$hex" }
            }
        }
    }
    'текст читается на фоне при любом акценте и любой основе'
}

Check 'Стоковые темы на месте' {
    $stock = Get-RamStockThemeList
    if ($stock.Count -lt 8) { throw "стоковых тем всего $($stock.Count), ждали хотя бы 8" }
    foreach ($th in $stock) {
        $pal = Set-RamTheme -Name $th.Key
        if ($pal.Key -ne $th.Key) { throw "тема $($th.Key) собралась под ключом $($pal.Key)" }
        if ($null -eq $pal.Accent -or $null -eq $pal.Bg) { throw "у темы $($th.Key) нет базовых цветов" }
    }
    # неизвестная тема откатывается на тёмную, а не роняет
    if ((Set-RamTheme -Name 'нет-такой-темы').Key -ne 'dark') { throw 'неизвестная тема не откатилась на тёмную' }
    Set-RamTheme -Name 'dark' | Out-Null
    "стоковых тем: $($stock.Count), все собираются, неизвестная откатывается"
}

Check 'Стоковые темы отличаются на глаз' {
    # Жалоба была прямая: «Небо и Светлая ничем не отличаются». И правда —
    # Panel и Card у обеих выходили пиксель-в-пиксель белыми, потому что при
    # светлоте ровно 1.0 формула HSL даёт чистый белый при любом тоне.
    # Порог различимости на глаз — примерно 5-8 единиц RGB, берём 9 с запасом.
    $limit = 9

    $dist = {
        param($a, $b)
        [Math]::Sqrt([Math]::Pow($a.R - $b.R, 2) + [Math]::Pow($a.G - $b.G, 2) + [Math]::Pow($a.B - $b.B, 2))
    }

    $stock = @(Get-RamStockThemeList)
    $pal = @{}
    foreach ($t in $stock) { $pal[$t.Key] = Get-RamPalette -Name $t.Key }

    # Сравниваем только темы одной основы: светлую с тёмной сравнивать незачем.
    $isLight = {
        param($p)
        (ConvertTo-RamHsl -Color $p.Bg).L -gt 0.5
    }

    $worst = 999.0; $worstPair = ''
    for ($i = 0; $i -lt $stock.Count; $i++) {
        for ($j = $i + 1; $j -lt $stock.Count; $j++) {
            $a = $pal[$stock[$i].Key]; $b = $pal[$stock[$j].Key]
            if ((& $isLight $a) -ne (& $isLight $b)) { continue }

            # Тема считается отличимой, если разошёлся хотя бы один из
            # крупных планов: фон, панель или карточка.
            $best = 0.0
            foreach ($k in @('Bg', 'Panel', 'Card')) {
                $d = & $dist $a[$k] $b[$k]
                if ($d -gt $best) { $best = $d }
            }
            if ($best -lt $worst) {
                $worst = $best
                $worstPair = "$($stock[$i].Title) / $($stock[$j].Title)"
            }
        }
    }

    if ($worst -lt $limit) {
        throw "темы «$worstPair» неразличимы: расхождение $([Math]::Round($worst,1)) при пороге $limit"
    }

    # И отдельно — то, с чего началась жалоба: панели светлых тем не должны
    # быть поголовно чисто белыми.
    $lightKeys = @($stock | Where-Object { & $isLight $pal[$_.Key] } | ForEach-Object { $_.Key })
    if ($lightKeys.Count -ge 2) {
        $whites = @($lightKeys | Where-Object { (ConvertTo-RamHex -Color $pal[$_].Panel) -eq '#FFFFFF' })
        if ($whites.Count -eq $lightKeys.Count) {
            throw 'у всех светлых тем панель чисто белая — тон снова не проявляется'
        }
    }

    "самая близкая пара: $worstPair = $([Math]::Round($worst,1)) при пороге $limit"
}

Check 'Свои темы: запись, чтение, файл' {
    $keep = if ($script:Settings.PSObject.Properties.Name -contains 'CustomThemes') { $script:Settings.CustomThemes } else { @() }
    try {
        $script:Settings.CustomThemes = @()

        # собрать из акцента, записать, прочитать обратно
        $pal = New-RamDerivedPalette -Accent (ConvertFrom-RamHex -Hex '#8B6CFF') -Base 'dark'
        $rec = ConvertTo-RamThemeRecord -Palette $pal -Key 'custom-test' -Title 'Проверочная'
        if ($rec.Colors.Accent -ne '#8B6CFF') { throw "акцент записался как $($rec.Colors.Accent)" }

        $script:Settings.CustomThemes = @($rec)

        # появилась ли она в общем списке
        $inList = Get-RamThemeList | Where-Object { $_.Key -eq 'custom-test' }
        if ($null -eq $inList) { throw 'своя тема не попала в список' }
        if (-not $inList.Custom) { throw 'своя тема не помечена как своя' }

        # собирается ли палитра из записи
        $back = Get-RamCustomPalette -Name 'custom-test'
        if ($null -eq $back) { throw 'палитра своей темы не собралась' }
        if ((ConvertTo-RamHex -Color $back.Accent) -ne '#8B6CFF') { throw 'акцент своей темы потерялся' }

        # своя тема важнее стоковой с тем же ключом
        $palByName = Get-RamPalette -Name 'custom-test'
        if ($palByName.Title -ne 'Проверочная') { throw 'Get-RamPalette не отдал свою тему' }

        # битый цвет в файле темы не роняет — подменяется запасным
        $rec.Colors.Bg = 'не-цвет'
        $script:Settings.CustomThemes = @($rec)
        $back2 = Get-RamCustomPalette -Name 'custom-test'
        if ($back2.Bg -isnot [System.Drawing.Color]) { throw 'битый цвет уронил сборку темы' }
    } finally {
        $script:Settings.CustomThemes = $keep
    }
    'тема пишется, читается, попадает в список и переживает битый цвет'
}

Check 'Приглашение althub:// туда-обратно' {
    $keep = $script:Accounts
    try {
        $a = New-RamAccount -Alias 'Перенос' -Cookie ('_|WARNING:-DO-NOT-SHARE-THIS.--' + ('Z' * 90))
        $a.PlaceId = '2753915549'; $a.GameName = 'Blox Fruits'; $a.LinkCode = 'srv1'
        $a.Graphics = '1'; $a.Volume = '0'; $a.FramerateCap = '30'; $a.Group = 'Твины'; $a.Color = 'blue'; $a.Note = 'заметка'

        $code = ConvertTo-RamInviteCode -Account $a
        if (-not $code.StartsWith('althub://v1/')) { throw 'код без префикса althub://' }

        $back = ConvertFrom-RamInviteCode -Code $code
        if ($null -eq $back) { throw 'код не разобрался обратно' }
        if ($back.cookie -ne $a.Cookie)   { throw 'кука не совпала' }
        if ($back.gameName -ne 'Blox Fruits') { throw 'игра потерялась' }
        if ($back.graphics -ne '1')       { throw 'графика потерялась' }
        if ($back.group -ne 'Твины')      { throw 'набор потерялся' }

        # мусор не роняет
        foreach ($bad in @('просто строка', 'althub://v1/!!невалид', '', 'althub://v2/xxx')) {
            if ($null -ne (ConvertFrom-RamInviteCode -Code $bad)) { throw "мусор '$bad' разобрался как код" }
        }
    } finally {
        $script:Accounts = $keep
    }
    'аккаунт с игрой и настройками переживает упаковку в приглашение и обратно'
}

Check 'Пачка и брошенный файл не роняют на мусоре' {
    $keep = $script:Accounts
    try {
        $script:Accounts = @()

        # батч на пустом и мусоре: без исключений, ничего не добавлено
        $sum = Import-RamAccountBatch -Text "`n`n   `nкороткая-строка`n"
        if ($sum.Added -ne 0)   { throw "добавил из мусора: $($sum.Added)" }
        if ($sum.Total -ne 1)   { throw "непустых строк насчитал $($sum.Total), ждали 1" }
        if ($sum.Failed -lt 1)  { throw 'короткая строка должна была провалиться' }

        # одиночная строка: пустая -> $null, короткая -> Ok=false без падения
        if ($null -ne (Import-RamAccountLine -Line '   ')) { throw 'пустая строка должна давать $null' }
        $r = Import-RamAccountLine -Line 'abc'
        if ($r.Ok) { throw 'мусор не должен добавляться' }

        # брошенный файл-настройки (без кук) не создаёт аккаунтов
        $tmp = Join-Path $env:TEMP ('ram-drop-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            '{"app":"AltHub","games":[],"accounts":[]}' | Set-Content -LiteralPath $tmp -Encoding UTF8
            $before = @($script:Accounts).Count
            # Import-RamDroppedFile показывает окно — проверяем только, что путь
            # к настройкам распознаётся и аккаунты не плодятся. Дёргаем разбор
            # напрямую вместо диалога:
            $j = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
            $isSetup = ($j.PSObject.Properties.Name -contains 'games')
            if (-not $isSetup) { throw 'файл настроек не распознан как настройки' }
            if (@($script:Accounts).Count -ne $before) { throw 'разбор настроек наплодил аккаунты' }
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    } finally {
        $script:Accounts = $keep
    }
    'пачка, одиночная строка и файл настроек не роняют и не плодят мусор'
}

Check 'Разбор популярных игр из Roblox' {
    # Разбор ответа explore-api проверяем на заготовленном JSON, без сети:
    # сеть капризна, а логика отбора должна работать одинаково.
    $fake = @'
{"sorts":[
  {"contentType":"Filters","games":null},
  {"contentType":"Games","sortDisplayName":"Top Trending","games":[
     {"name":"Игра А","rootPlaceId":"111","playerCount":5000},
     {"name":"Игра Б","rootPlaceId":"222","playerCount":9000},
     {"name":"","rootPlaceId":"333","playerCount":1},
     {"name":"Без ID","rootPlaceId":"","playerCount":2}
  ]},
  {"contentType":"Games","sortDisplayName":"Top Playing Now","games":[
     {"name":"Игра Б","rootPlaceId":"222","playerCount":9000},
     {"name":"Игра В","rootPlaceId":"444","playerCount":7000}
  ]}
]}
'@ | ConvertFrom-Json

    $g = @(ConvertFrom-RamExploreSorts -Data $fake -Limit 30)
    if ($g.Count -ne 3) { throw "разобрано $($g.Count) игр вместо 3 (дубли/пустые не отсеялись)" }
    if ($g[0].Title -ne 'Игра Б' -or $g[0].Players -ne 9000) { throw 'не отсортировано по числу игроков' }
    if (($g | Where-Object { [string]::IsNullOrWhiteSpace($_.Title) }).Count -gt 0) { throw 'просочилась игра без названия' }
    if (($g | Where-Object { [string]::IsNullOrWhiteSpace($_.PlaceId) }).Count -gt 0) { throw 'просочилась игра без ID' }
    $ids = @($g | ForEach-Object { $_.PlaceId })
    if (($ids | Select-Object -Unique).Count -ne $ids.Count) { throw 'остались дубли по ID' }

    # предел соблюдается
    if ((ConvertFrom-RamExploreSorts -Data $fake -Limit 2).Count -ne 2) { throw 'предел Limit не соблюдён' }

    # пустой и битый ответ не роняют
    if ((ConvertFrom-RamExploreSorts -Data $null).Count -ne 0) { throw 'null должен давать 0 игр' }
    if ((ConvertFrom-RamExploreSorts -Data ([pscustomobject]@{ sorts = $null })).Count -ne 0) { throw 'пустые sorts должны давать 0' }

    'отбор, дедуп, сортировка и пределы работают; пустой ответ не роняет'
}

Check 'Замыкания не трогают script-переменные' {
    # ГРАБЛИ, СТОИВШИЕ АВАРИИ У ЛЮДЕЙ. Внутри .GetNewClosure() модификатор
    # script: указывает на область динамического модуля, а не файла: чтение
    # даёт $null, запись теряется. Так упало «Добавить отмеченные» в
    # популярных играх и молча ломались счётчики добавленных аккаунтов.
    # Проверяем разбором AST, чтобы это не вернулось никогда.
    $files = @((Join-Path $root 'AltHub.ps1')) + (Get-ChildItem (Join-Path $root 'modules\*.ps1')).FullName
    $bad = @(); $total = 0

    foreach ($f in $files) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
        $calls = $ast.FindAll({
            param($x) $x -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                      "$($x.Member.Value)" -eq 'GetNewClosure'
        }, $true)
        $total += $calls.Count

        foreach ($c in $calls) {
            $sb = $c.Expression
            if ($sb -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) { continue }
            $vars = $sb.FindAll({ param($x) $x -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
            foreach ($v in $vars) {
                if ($v.VariablePath.IsScript) {
                    $bad += ('{0}:{1} — {2}' -f (Split-Path -Leaf $f), $v.Extent.StartLineNumber, $v.VariablePath.UserPath)
                }
            }
        }
    }

    if ($bad.Count -gt 0) {
        throw ('внутри замыканий есть обращения к script-области (там они не работают): ' + ($bad -join ' | '))
    }
    "замыканий $total, ни одно не обращается к script-области"
}

Check 'Есть защита от падения' {
    # Без глобального перехватчика любая ошибка в обработчике поднимает окно
    # WinForms с кнопкой «Выход», которая убивает процесс. Именно так у людей
    # приложение «само закрывалось».
    foreach ($fn in @('Register-RamCrashGuard', 'Invoke-RamSafe', 'Write-RamCrashDump')) {
        if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { throw "нет функции $fn" }
    }

    # Ошибка внутри Invoke-RamSafe не должна прорываться наружу.
    $after = $false
    Invoke-RamSafe -What 'проверка' -Body { throw 'нарочно' }
    $after = $true
    if (-not $after) { throw 'ошибка прорвалась сквозь Invoke-RamSafe' }

    # Значение при этом возвращается как обычно.
    if ((Invoke-RamSafe -What 'проверка' -Body { 7 }) -ne 7) { throw 'значение не вернулось' }

    # Все таймеры главного окна обязаны быть под защитой.
    $src = Get-RamAllSource
    foreach ($m in [regex]::Matches($src, '\.Add_Tick\(\{(.*?)\}\)', 'Singleline')) {
        if ($m.Groups[1].Value -notmatch 'Invoke-RamSafe') {
            throw ('таймер без защиты: ' + $m.Groups[1].Value.Trim())
        }
    }
    'перехватчик, безопасный вызов и защищённые таймеры на месте'
}

Check 'Ограничение частоты не морозит окно' {
    # Раньше 429 обрабатывался через Start-Sleep до 30 секунд прямо в тике
    # таймера — окно замерзало. И главное: добыча CSRF-токена вызывалась вне
    # try/catch, поэтому цикл повторов умирал на первом круге и пятый аккаунт
    # молча пропадал. Отсюда и «максимум четыре».
    $ex = New-RamRateLimitError -Seconds 12
    if (-not $ex.Data.Contains('RamRetryAfter')) { throw 'ошибка не несёт паузу' }
    if ([int]$ex.Data['RamRetryAfter'] -ne 12)   { throw 'пауза потерялась' }

    # Пауза берётся из ответа, абсурдные значения отсекаются.
    if ((Get-RamRetryAfterSeconds -Response ([pscustomobject]@{ Headers = @{ 'retry-after' = '7' } }) -Default 8) -ne 7) { throw 'заголовок retry-after не учтён' }
    if ((Get-RamRetryAfterSeconds -Response ([pscustomobject]@{ Headers = @{} }) -Default 8) -ne 8) { throw 'нет запасного значения' }
    if ((Get-RamRetryAfterSeconds -Response ([pscustomobject]@{ Headers = @{ 'retry-after' = '9999' } }) -Default 8) -ne 8) { throw 'абсурдная пауза не отсечена' }

    # В добыче билета не должно остаться сна, а CSRF обязан быть под try.
    $fn = (Get-Command Get-RamAuthTicket).Definition
    if ($fn -match 'Start-Sleep') { throw 'в билете запуска снова появился Start-Sleep' }
    if ($fn -notmatch '(?s)try\s*\{\s*\$csrf\s*=\s*Get-RamCsrfToken') { throw 'добыча CSRF снова вне try/catch' }

    # Токен берём не с того же эндпоинта, что и билет: иначе двойная нагрузка.
    $api = Get-Content (Join-Path $root 'modules\RobloxApi.ps1') -Raw
    $iCat  = $api.IndexOf('catalog.roblox.com/v1/catalog/items/details')
    $iAuth = $api.IndexOf("auth.roblox.com/v1/authentication-ticket/'; Body = '' }")
    if ($iCat -le 0 -or $iAuth -le 0 -or $iCat -gt $iAuth) { throw 'auth.roblox.com снова первый источник CSRF' }

    if ([Net.ServicePointManager]::DefaultConnectionLimit -lt 16) { throw 'лимит соединений не поднят' }
    'пауза передаётся наверх, сна в UI нет, источники токена разведены'
}

Check 'Подхват уже работающих клиентов' {
    $keepAcc  = $script:Accounts
    $keepInst = $script:Instances
    try {
        $a1 = New-RamAccount -Alias 'Основной' -Cookie 'x'
        $a2 = New-RamAccount -Alias 'Твинк 1'  -Cookie 'x'
        $a2.BrowserTrackerId = '123456789012'
        $script:Accounts  = @($a1, $a2)
        $script:Instances = @{}

        # Чужой процесс не должен присваиваться наугад.
        if ($null -ne (Get-RamClientOwner -ProcessId 999999 -Handle ([IntPtr]::Zero))) {
            throw 'неизвестный процесс опознан как чей-то аккаунт'
        }

        # Подхват на пустом месте не падает.
        [void](Restore-RamAdoptRunningClients)

        # BrowserTrackerId должен сохраняться в аккаунт, иначе после
        # перезапуска опознать клиент будет нечем.
        $lnk = Get-Content (Join-Path $root 'modules\Launcher.ps1') -Raw
        if ($lnk -notmatch '\$Account\.BrowserTrackerId\s*=\s*\$btid') {
            throw 'BrowserTrackerId снова не сохраняется в аккаунт'
        }

        # Подхват обязан вызываться при старте.
        $src = Get-RamAllSource
        if ($src -notmatch 'Restore-RamAdoptRunningClients') { throw 'подхват не вызывается при старте' }
    } finally {
        $script:Accounts  = $keepAcc
        $script:Instances = $keepInst
    }
    'чужой процесс не присваивается, btid сохраняется, подхват подключён к старту'
}

Check 'Главное окно живёт в Application.Run' {
    # Самая глубокая ошибка всей этой истории. ShowDialog завершается не
    # только когда окно закрыли, но и когда его ПРЯЧУТ: как только Visible
    # становится false, модальный цикл выходит, скрипт доходит до конца и
    # процесс завершается. Поэтому любая попытка «убрать в часы» убивала
    # программу — со стороны это выглядело как «свернул, и оно закрылось».
    $src = Get-RamAllSource

    if ($src -match '\$form\.ShowDialog\(\)') {
        throw 'главное окно снова показывается через ShowDialog — Hide() будет убивать программу'
    }
    if ($src -notmatch '\[System\.Windows\.Forms\.Application\]::Run\(\$form\)') {
        throw 'пропал Application::Run — окно должно жить в обычном цикле сообщений'
    }
    if ($src -match '(?s)Add_Resize\(\{.{0,600}?\$this\.Hide\(\)') {
        throw 'сворачивание снова прячет окно — так его и теряли'
    }
    'окно живёт в Application.Run, сворачивание его не прячет'
}

Check 'Все меню оформлены темой' {
    # Меню в часах создавалось сырым ContextMenuStrip: слева оставался
    # «жёлоб под значки», который тема не красит, и на тёмном оформлении это
    # была белая полоса во всю высоту меню.
    # Сырое меню разрешено ровно в одном месте — внутри самой обёртки
    # New-RamContextMenu (modules\Theme.ps1). Везде остальное запрещено.
    foreach ($f in (Get-ChildItem (Join-Path $root 'modules\*.ps1')).FullName + @((Join-Path $root 'AltHub.ps1'))) {
        if ((Split-Path -Leaf $f) -eq 'Theme.ps1') { continue }
        $txt = Get-Content -LiteralPath $f -Raw -Encoding UTF8
        foreach ($m in [regex]::Matches($txt, '(?m)^\s*\$(\w+)\s*=\s*New-Object System\.Windows\.Forms\.ContextMenuStrip')) {
            throw "$(Split-Path -Leaf $f): меню «$($m.Groups[1].Value)» создаётся мимо New-RamContextMenu — будет неокрашенная полоса слева"
        }
    }

    # И сама обёртка обязана убирать жёлоб и ставить отрисовщик темы.
    $menu = New-RamContextMenu
    try {
        if ($menu.ShowImageMargin) { throw 'жёлоб под значки снова включён' }
        if ($null -eq $menu.Renderer) { throw 'у меню нет отрисовщика темы' }
        if ($menu.BackColor -ne $Global:RamTheme.Card) { throw 'фон меню не из темы' }
    } finally { $menu.Dispose() }

    'меню создаются через New-RamContextMenu, полосы слева нет'
}

Check 'Одна копия программы на компьютер' {
    # Без этого потерянное окно вернуть нечем: повторный клик по ярлыку
    # открывал вторую копию, а первая оставалась висеть невидимой и держала
    # горячие клавиши.
    $src = Get-RamAllSource
    foreach ($need in @('Test-RamAlreadyRunning', 'Show-RamRunningInstance', 'Clear-RamSingleInstance')) {
        if ($src -notmatch [regex]::Escape($need)) { throw "пропала защита от второго запуска: $need" }
    }
    if ($src -notmatch 'AltHubSingleInstance') { throw 'пропал именованный замок одной копии' }
    'замок на месте, повторный запуск возвращает окно'
}
Check 'Окна и оформление собираются' {
    $form = New-RamMainForm
    if ($form.Controls.Count -lt 5) { throw "в главном окне только $($form.Controls.Count) элементов" }

    foreach ($sec in @('accounts','games','stats','log')) {
        if (-not $script:UI.Panels.ContainsKey($sec)) { throw "нет раздела '$sec'" }
        if (-not $script:UI.NavButtons.ContainsKey($sec)) { throw "нет кнопки раздела '$sec'" }
    }

    # Переключение разделов не должно падать
    foreach ($sec in @('games','stats','log','accounts')) { Show-RamSection -Key $sec }

    $script:UI.UpdateTimer.Stop()
    $script:UI.ScheduleTimer.Stop()
    $form.Dispose()

    $wiz = Show-RamAddWizard -BuildOnly
    if ($wiz.Controls.Count -lt 8) { throw "в мастере только $($wiz.Controls.Count) элементов" }
    $wiz.Dispose()

    # конструктор тем — простой и подробный режим
    $con = Show-RamThemeConstructor -BuildOnly
    if ($con.Controls.Count -lt 10) { throw "в конструкторе только $($con.Controls.Count) элементов" }
    $con.Dispose()

    # диалоги добавления
    $bd = Show-RamBatchAddDialog -BuildOnly
    if ($bd.Controls.Count -lt 4) { throw "в пачечном добавлении только $($bd.Controls.Count) элементов" }
    $bd.Dispose()

    $bg = Show-RamBrowserGuide -BuildOnly
    if ($bg.Controls.Count -lt 4) { throw "в браузерном гиде только $($bg.Controls.Count) элементов" }
    $bg.Dispose()

    'главное окно, разделы, мастер, конструктор тем и диалоги добавления строятся без ошибок'
}

Check 'Нижняя строка выровнена' {
    $form = New-RamMainForm
    try {
        $pAcc = $script:UI.Panels['accounts']
        $fix  = $script:UI.FixAll
        $st   = $script:UI.Status

        # Кнопка входов должна кончаться там же, где карточки и панель кнопок
        # наверху: иначе она на глаз не доходит до общей правой линии.
        if ($fix.Right -ne $pAcc.Right) {
            throw "правый край кнопки $($fix.Right), а у содержимого $($pAcc.Right)"
        }
        # Фон у кнопок прозрачный, и налезание на панель показывало бы в этой
        # полоске фон окна вместо фона панели.
        if ($fix.Top -lt $pAcc.Bottom) {
            throw "кнопка залезает на панель разделов на $($pAcc.Bottom - $fix.Top) px"
        }
        if ($fix.Bottom -gt $form.ClientSize.Height) { throw 'кнопка вылезла за низ окна' }
        if ($st.Right -ge $fix.Left) { throw 'строка состояния налезает на кнопку' }

        $script:UI.UpdateTimer.Stop()
        $script:UI.ScheduleTimer.Stop()
    } finally {
        $form.Dispose()
    }
    'кнопка входов на общей правой линии, панель не задета, строка не налезает'
}

Check 'Вёрстка держится на 100%, 125% и 150%' {
    <#
      Обходит ВСЕ окна программы и проверяет три вещи:
        1) текст влезает в отведённое место;
        2) элемент не вылезает за свой контейнер и за окно;
        3) соседи не налезают друг на друга.

      И делает это трижды — при обычном масштабе экрана, при 125% и при 150%.

      ЗАЧЕМ ТРИ МАСШТАБА. Подписи меряются шрифтом, а шрифт растёт вместе с
      масштабом экрана. Координаты в пикселях — нет. Поэтому вёрстка, которая
      идеальна на машине разработчика, на 150% разъезжается: подписи наезжают
      на кнопки, а кнопки вылезают за край панели. Системный масштаб при этом
      не трогаем — просто подменяем шрифты темы через $Global:RamForceScale.

      ЗАЧЕМ РЕЕСТР ОКОН. Раньше окна перечислялись здесь руками, список отстал
      и проверялись четыре из одиннадцати. Из-за этого наложение в конструкторе
      тем никто не видел. Теперь список живёт рядом с окнами.

      ВНИМАНИЕ НА ОБЛАСТЬ ВИДИМОСТИ. Список найденного обязан быть именно
      $script:bad. Вложенные функции ниже пишут в него, и если завести здесь
      обычный локальный $bad, то это будут ДВЕ РАЗНЫЕ переменные: находки
      уйдут в одну, а проверяться будет пустая другая. Ровно из-за этого
      прошлая версия проверки была зелёной всегда, даже когда наложения были.
    #>
    $script:bad = @()

    # Панели разделов главного окна лежат друг на друге НАРОЧНО: это стопка
    # страниц, видна всегда одна. Их пересечения — не ошибка.
    $stack = @{}

    function Test-RamFits {
        param($Control, [string]$Where)

        # --- кнопка: надпись должна влезать
        if ($null -ne $Control.Tag -and
            $Control.Tag.PSObject.Properties.Name -contains 'Caption' -and
            $Control.Tag.PSObject.Properties.Name -contains 'Natural') {
            $fixed = $false
            if ($Control.Tag.PSObject.Properties.Name -contains 'Fixed') { $fixed = [bool]$Control.Tag.Fixed }
            if (-not $fixed -and $Control.Tag.Natural.Width -gt $Control.Width + 1) {
                $script:bad += "${Where}: кнопка «$($Control.Tag.Caption)» не влезает ($($Control.Tag.Natural.Width)px в $($Control.Width)px)"
            }
        }

        # --- подпись
        if ($Control -is [System.Windows.Forms.Label]) {
            $txt  = [string]$Control.Text
            $free = ([string]$Control.Tag -eq 'truncatable')
            if ($txt -and -not $Control.AutoSize -and -not $free) {
                $multi = ($txt -match "`n") -or ($Control.Height -ge $Control.Font.Height * 1.8)
                if ($multi) {
                    $sz = Measure-RamText -Text $txt -Font $Control.Font -MaxWidth $Control.Width
                    if ($sz.Height -gt $Control.Height + 2) {
                        $script:bad += "${Where}: многострочная не влезла по высоте ($($sz.Height)px в $($Control.Height)px)"
                    }
                } else {
                    $one = (Measure-RamText -Text $txt -Font $Control.Font).Width
                    if ($one -gt $Control.Width + 1) {
                        $script:bad += "${Where}: подпись «$txt» ($($one)px в $($Control.Width)px)"
                    }
                }
            }
        }

        # --- не вылезает за контейнер. ТЕПЕРЬ И ДЛЯ ДЕТЕЙ САМОЙ ФОРМЫ:
        # раньше эта ветка их исключала, поэтому в диалогах, где всё лежит
        # прямо на окне, выход за край был невидим в принципе.
        if ($null -ne $Control.Parent) {
            $par = $Control.Parent
            $box = $par.ClientSize
            $scrollable = ($par -is [System.Windows.Forms.FlowLayoutPanel] -and $par.AutoScroll)

            if ($Control.Left -lt -1 -or $Control.Top -lt -1) {
                $script:bad += "${Where}: элемент за левым/верхним краем ($($Control.Left),$($Control.Top))"
            }
            if ($Control.Right -gt $box.Width + 1) {
                $script:bad += "${Where}: вылезает вправо (край $($Control.Right) при ширине $($box.Width))"
            }
            # Прокручиваемым разрешаем расти вниз, но не вбок.
            if (-not $scrollable -and $Control.Bottom -gt $box.Height + 1) {
                $script:bad += "${Where}: вылезает вниз (край $($Control.Bottom) при высоте $($box.Height))"
            }
        }

        foreach ($child in $Control.Controls) { Test-RamFits -Control $child -Where $Where }
    }

    function Test-RamOverlap {
        <# Соседи не должны налезать друг на друга.
           По Visible фильтровать нельзя: у непоказанного окна всё числится
           невидимым, и проверка молча пропустила бы всё. #>
        param($Parent, [string]$Where)

        $kids = @()
        foreach ($c in $Parent.Controls) {
            if ($c -is [System.Windows.Forms.FlowLayoutPanel]) { continue }
            $kids += $c
        }

        for ($i = 0; $i -lt $kids.Count; $i++) {
            for ($j = $i + 1; $j -lt $kids.Count; $j++) {
                $x = $kids[$i]; $y = $kids[$j]
                if ($x.Height -le 6 -or $y.Height -le 6) { continue }   # полоски-акценты

                # Стопка страниц — лежат друг на друге по замыслу.
                if ($stack.ContainsKey($x) -and $stack.ContainsKey($y)) { continue }
                # То же для диалогов с разделами: панели зовутся ramPage_*.
                if ([string]$x.Name -like 'ramPage_*' -and [string]$y.Name -like 'ramPage_*') { continue }

                $r = [System.Drawing.Rectangle]::Intersect($x.Bounds, $y.Bounds)
                # Порога нет: у соприкасающихся прямоугольников пересечение
                # пустое, поэтому любое ненулевое — это уже настоящее наложение.
                # Со старым порогом «больше двух пикселей» кнопка на подписи
                # в разделе «Профили» проходила ровно по границе.
                if ($r.Width -gt 0 -and $r.Height -gt 0) {
                    $xn = if ($x -is [System.Windows.Forms.Label]) { "«$($x.Text)»" }
                          elseif ($null -ne $x.Tag -and $x.Tag.PSObject.Properties.Name -contains 'Caption') { "кнопка «$($x.Tag.Caption)»" }
                          else { $x.GetType().Name }
                    $yn = if ($y -is [System.Windows.Forms.Label]) { "«$($y.Text)»" }
                          elseif ($null -ne $y.Tag -and $y.Tag.PSObject.Properties.Name -contains 'Caption') { "кнопка «$($y.Tag.Caption)»" }
                          else { $y.GetType().Name }
                    $script:bad += "${Where}: наложение $xn и $yn на $($r.Width)x$($r.Height)px"
                }
            }
        }

        foreach ($c in $Parent.Controls) {
            if ($c.Controls.Count -gt 0) { Test-RamOverlap -Parent $c -Where $Where }
        }
    }

    # --- подопытные данные: длинные названия, смайлики, мёртвый вход
    $keepAcc     = $script:Accounts
    $keepGames   = $script:Settings.Games
    $keepProf    = $script:Settings.Profiles
    $keepCompact = $script:Settings.CompactCards
    $keepTray    = $script:Settings.OnClose
    $keepScale   = $Global:RamForceScale
    $keepTheme   = $script:Settings.Theme

    try {
        $script:Settings.OnClose = 'exit'

        $a1 = New-RamAccount -Alias 'Основной' -Cookie 'x' -PlaceId '1'
        $a1.Username = 'TestPlayer'; $a1.UserId = 1234567
        $a1.Group = 'Основные аккаунты'; $a1.Note = 'заметка подлиннее для проверки'
        $a1.GameName = 'Elemental Dungeons'; $a1.Robux = 12345; $a1.Premium = 'yes'; $a1.Created = '2022-11-16'
        $a1.Graphics = '10'; $a1.Volume = '100'; $a1.FramerateCap = '240'

        $a2 = New-RamAccount -Alias 'Твинк с очень длинным именем аккаунта' -Cookie 'x'
        $a2.Username = 'VeryLongUserNameHere'; $a2.UserId = 7654321
        $a2.Group = 'Твины на приватном сервере'; $a2.CookieOk = 'no'
        $a2.GameName = '[🌙] Elemental Dungeons'; $a2.Graphics = '1'; $a2.Volume = '0'; $a2.FramerateCap = '30'

        $script:Accounts = @($a1, $a2)
        $script:Settings.Games = @(
            [pscustomobject]@{ Title = 'Blox Fruits'; PlaceId = '2753915549'; LinkCode = '' },
            [pscustomobject]@{ Title = '[🌙] Игра с очень длинным названием для проверки'; PlaceId = '111'; LinkCode = 'abc' }
        )
        $script:Settings.Profiles = @(
            [pscustomobject]@{ Name = 'Твины на випку'; Group = 'Твины на приватном сервере'; PlaceId = '111'; GameName = 'Elemental Dungeons'; LinkCode = 'abc' }
        )

        foreach ($scale in @(1.0, 1.25, 1.5)) {
            $Global:RamForceScale = $scale
            $script:RamDpiScale   = $null
            # Эталонный экран растёт вместе с масштабом: настоящий монитор
            # со 150% — это и физически больший монитор. Иначе мы бы проверяли
            # крупный шрифт на маленьком столе и получали тесноту на пустом месте.
            $Global:RamForceWorkArea = [pscustomobject]@{
                Width  = [int](1600 * $scale)
                Height = [int](1000 * $scale)
            }
            Set-RamTheme -Name $script:Settings.Theme | Out-Null

            foreach ($w in Get-RamCheckableWindows) {
                $form = $null
                try { $form = & $w.Build } catch {
                    $script:bad += "$($w.Name)@$($scale): окно не собралось — $($_.Exception.Message)"
                    continue
                }
                if ($null -eq $form) { continue }

                try {
                    $stack = @{}
                    if ($w.Main -and $script:UI.ContainsKey('Panels')) {
                        foreach ($pnl in $script:UI.Panels.Values) { $stack[$pnl] = $true }
                    }

                    if ($w.Sections) {
                        foreach ($sec in $w.Sections) {
                            Show-RamSection -Key $sec
                            if ($sec -eq 'accounts') { Build-RamCards }
                            Test-RamFits   -Control $form -Where "$($w.Name)/$sec@$scale"
                            Test-RamOverlap -Parent $form -Where "$($w.Name)/$sec@$scale"
                        }
                        $script:Settings.CompactCards = $true
                        Show-RamSection -Key 'accounts'; Build-RamCards
                        Test-RamFits   -Control $form -Where "$($w.Name)/компакт@$scale"
                        Test-RamOverlap -Parent $form -Where "$($w.Name)/компакт@$scale"
                        $script:Settings.CompactCards = $false
                    } else {
                        Test-RamFits   -Control $form -Where "$($w.Name)@$scale"
                        Test-RamOverlap -Parent $form -Where "$($w.Name)@$scale"
                    }
                } finally {
                    if ($w.Main) {
                        foreach ($tn in @('UpdateTimer','ScheduleTimer','LaunchTimer','SearchTimer','StartupTimer')) {
                            if ($script:UI.ContainsKey($tn) -and $null -ne $script:UI[$tn]) { $script:UI[$tn].Stop() }
                        }
                    }
                    $form.Dispose()
                }
            }
        }
    } finally {
        $script:Accounts = $keepAcc
        $script:Settings.Games = $keepGames
        $script:Settings.Profiles = $keepProf
        $script:Settings.CompactCards = $keepCompact
        $script:Settings.OnClose = $keepTray
        $Global:RamForceScale = $keepScale
        $Global:RamForceWorkArea = $null
        $script:RamDpiScale = $null
        Set-RamTheme -Name $keepTheme | Out-Null
    }

    if ($script:bad.Count -gt 0) {
        $show = $script:bad | Select-Object -First 6
        throw ($script:bad.Count.ToString() + ' шт.: ' + ($show -join ' | '))
    }
    'все окна на трёх масштабах: ничего не обрезано, не вылезает и не налезает'
}

Check 'Аватарки грузятся (публичный запрос, без куки)' {
    $dir = Join-Path $env:TEMP ('ram-avatar-test-' + [guid]::NewGuid().ToString('N'))
    try {
        $file = Get-RamAvatarFile -UserId 1 -CacheDir $dir
        if (-not $file -or -not (Test-Path -LiteralPath $file)) { throw 'картинка не скачалась (нет интернета?)' }
        $img = Get-RamImageFromFile -Path $file
        if ($null -eq $img) { throw 'файл скачался, но это не картинка' }
        $size = "$($img.Width)x$($img.Height)"
        $img.Dispose()
        "аватарка $size получена и легла в кэш"
    } finally {
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Check 'Фильтр журнала не пропускает куки' {
    $line = 'сообщение _|WARNING:-DO-NOT-SHARE-THIS.--Do-not-share.AAAA конец'
    $safe = $line -replace '_\|WARNING[^\s]*', '<кука скрыта>'
    if ($safe -match 'WARNING' -or $safe -match 'AAAA') { throw 'кука прошла в журнал' }
    'строки с .ROBLOSECURITY вырезаются'
}

Check 'В коде нет опасных конструкций и посторонних адресов' {
    $paths = @((Join-Path $root '*.ps1'), (Join-Path $root 'modules\*.ps1'))

    $hits = Select-String -Path $paths -Pattern 'Invoke-Expression|\bIEX\b|DownloadString|DownloadFile' |
            Where-Object { $_.Filename -ne 'Самопроверка.ps1' }
    if ($hits) { throw ('найдено: ' + (($hits | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) -join ', ')) }

    # Часть найденных строк — regex-шаблоны из этого же файла, где точки
    # экранированы (assetgame\.roblox\.com). Снимаем экранирование и берём
    # хост своим разбором: [Uri] на таких строках падает.
    $urls = Select-String -Path $paths -Pattern 'https?://[^\s"'')]+' -AllMatches |
            ForEach-Object { $_.Matches.Value } |
            ForEach-Object { $_ -replace '\\', '' } |
            ForEach-Object { if ($_ -match '^https?://([^/?#]+)') { $Matches[1] } } |
            Sort-Object -Unique
    if (-not $urls) { throw 'не найдено ни одного адреса — проверка не сработала' }
    foreach ($h in $urls) {
        if ($h -notmatch '(^|\.)roblox\.com$' -and $h -notmatch '(^|\.)rbxcdn\.com$') {
            throw "посторонний адрес в коде: $h"
        }
    }
    "домены в коде: $($urls -join ', ')"
}

Write-Host '--------------------------------------------------'
if ($passed -eq $total) {
    Write-Host "Пройдено $passed из $total — всё в порядке." -ForegroundColor Green
} else {
    Write-Host "Пройдено $passed из $total — есть проблемы, смотри красное выше." -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'Нажми Enter, чтобы закрыть.' -ForegroundColor DarkGray
[void](Read-Host)
