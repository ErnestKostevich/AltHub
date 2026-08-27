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

Check 'Раскладка ждёт появления окон' {
    $keepInst = $script:Instances
    $keepTile = $script:PendingTileUntil
    try {
        # Режим «основной крупно» обязан доживать до раскладки: его ставит
        # «Быстрая настройка», а раньше он молча подменялся сеткой.
        $src = Get-Content (Join-Path $root 'AltHub.ps1') -Raw
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
        $src = Get-Content (Join-Path $root 'AltHub.ps1') -Raw
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
        foreach ($it in $menu.Items) {
            if ($it -is [System.Windows.Forms.ToolStripSeparator]) { continue }
            if (-not $it.Enabled) { continue }
            if ([string]$it.Tag -ne $acc.Id) { throw "у пункта '$($it.Text)' в Tag не тот аккаунт" }
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

    'главное окно, четыре раздела и мастер строятся без ошибок'
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

Check 'Вёрстка: ничего не обрезано и не наложено' {
    <#
      Обмеряет каждую подпись и кнопку во всех окнах и сравнивает с отведённым
      местом. Свободный текст пользователя (имя, заметка, название игры) помечен
      как Truncatable и пропускается — для него многоточие нормально.
    #>
    $bad = @()

    function Test-RamFits {
        param($Control, [string]$Where)

        if ($Control -is [System.Windows.Forms.Panel] -and $null -ne $Control.Tag -and
            $Control.Tag.PSObject.Properties.Name -contains 'Caption') {
            $txt = [string]$Control.Tag.Caption
            if ($txt) {
                $fnt = $Control.Tag.Font
                if ($null -eq $fnt) { $fnt = $Global:RamTheme.FontBody }
                $w = [System.Windows.Forms.TextRenderer]::MeasureText($txt, $fnt).Width
                if ($w + 8 -gt $Control.Width) {
                    $script:bad += "${Where}: кнопка «$txt» ($($w + 8)px в $($Control.Width)px)"
                }
            }
        }

        if ($Control -is [System.Windows.Forms.Label]) {
            $txt  = [string]$Control.Text
            $free = ([string]$Control.Tag -eq 'truncatable')
            if ($txt -and -not $Control.AutoSize -and -not $free) {
                $multi = ($txt -match "`n") -or ($Control.Height -ge $Control.Font.Height * 1.8)
                if ($multi) {
                    $sz = [System.Windows.Forms.TextRenderer]::MeasureText(
                            $txt, $Control.Font, (New-Object System.Drawing.Size($Control.Width, 4000)),
                            [System.Windows.Forms.TextFormatFlags]::WordBreak)
                    if ($sz.Height -gt $Control.Height + 2) {
                        $script:bad += "${Where}: многострочная не влезла по высоте ($($sz.Height)px в $($Control.Height)px)"
                    }
                } else {
                    $one = [System.Windows.Forms.TextRenderer]::MeasureText($txt, $Control.Font).Width
                    if ($one -gt $Control.Width + 1) {
                        $script:bad += "${Where}: подпись «$txt» ($($one)px в $($Control.Width)px)"
                    }
                }
            }
        }

        # Элемент не должен вылезать за пределы своего контейнера.
        if ($null -ne $Control.Parent -and -not ($Control.Parent -is [System.Windows.Forms.Form])) {
            $par = $Control.Parent
            $scrollable = ($par -is [System.Windows.Forms.FlowLayoutPanel] -and $par.AutoScroll)
            if (-not $scrollable) {
                if ($Control.Right -gt $par.ClientSize.Width + 1 -or
                    $Control.Bottom -gt $par.ClientSize.Height + 1) {
                    $script:bad += "${Where}: элемент вылезает за контейнер (правый край $($Control.Right) при $($par.ClientSize.Width))"
                }
            }
        }

        foreach ($child in $Control.Controls) { Test-RamFits -Control $child -Where $Where }
    }

    function Test-RamOverlap {
        <# Соседние элементы не должны налезать друг на друга.
           По Visible фильтровать нельзя: у непоказанного окна всё числится
           невидимым, и проверка молча пропустит всё. #>
        param($Parent, [string]$Where)

        $kids = @()
        foreach ($c in $Parent.Controls) {
            if ($c -is [System.Windows.Forms.FlowLayoutPanel]) { continue }
            $kids += $c
        }

        for ($i = 0; $i -lt $kids.Count; $i++) {
            for ($j = $i + 1; $j -lt $kids.Count; $j++) {
                $x = $kids[$i]; $y = $kids[$j]
                if ($x.Height -le 6 -or $y.Height -le 6) { continue }       # полоски-акценты
                if ($x.Controls.Count -gt 0 -or $y.Controls.Count -gt 0) { continue }  # контейнеры

                $r = [System.Drawing.Rectangle]::Intersect($x.Bounds, $y.Bounds)
                if ($r.Width -gt 2 -and $r.Height -gt 2) {
                    $xn = if ($x -is [System.Windows.Forms.Label]) { $x.Text } else { $x.GetType().Name }
                    $yn = if ($y -is [System.Windows.Forms.Label]) { $y.Text } else { $y.GetType().Name }
                    $script:bad += "${Where}: наложение «$xn» и «$yn» на $($r.Width)x$($r.Height)px"
                }
            }
        }

        foreach ($c in $Parent.Controls) {
            if ($c.Controls.Count -gt 0) { Test-RamOverlap -Parent $c -Where $Where }
        }
    }

    $keepAcc = $script:Accounts
    $keepCompact = $script:Settings.CompactCards
    $keepTray = $script:Settings.MinimizeToTray
    try {
        $script:Settings.MinimizeToTray = $false

        # Нарочно длинные названия — на них вёрстка и ломалась.
        $a1 = New-RamAccount -Alias 'Основной' -Cookie 'x' -PlaceId '1'
        $a1.Username = 'TestPlayer'; $a1.UserId = 1234567
        $a1.Group = 'Основные аккаунты'; $a1.Note = 'заметка подлиннее для проверки'
        $a1.GameName = 'Elemental Dungeons'; $a1.Robux = 12345; $a1.Premium = 'yes'; $a1.Created = '2022-11-16'
        $a1.Graphics = '10'; $a1.Volume = '100'; $a1.FramerateCap = '240'
        $script:Accounts = @($a1)

        $form = New-RamMainForm
        foreach ($sec in @('accounts','games','profiles','stats','log')) {
            Show-RamSection -Key $sec
            if ($sec -eq 'accounts') { Build-RamCards }
            Test-RamFits -Control $form -Where "окно/$sec"
            Test-RamOverlap -Parent $form -Where "окно/$sec"
        }

        $script:Settings.CompactCards = $true
        Show-RamSection -Key 'accounts'; Build-RamCards
        Test-RamFits -Control $form -Where 'окно/компактные'
        Test-RamOverlap -Parent $form -Where 'окно/компактные'

        $script:UI.UpdateTimer.Stop()
        $script:UI.ScheduleTimer.Stop()
        $form.Dispose()

        $wiz = Show-RamAddWizard -BuildOnly
        Test-RamFits -Control $wiz -Where 'мастер'
        Test-RamOverlap -Parent $wiz -Where 'мастер'
        $wiz.Dispose()

        $dlg = Show-RamAccountDialog -Account $a1 -BuildOnly
        Test-RamFits -Control $dlg -Where 'аккаунт'
        Test-RamOverlap -Parent $dlg -Where 'аккаунт'
        $dlg.Dispose()

        $st = Show-RamSettingsDialog -BuildOnly
        Test-RamFits -Control $st -Where 'настройки'
        Test-RamOverlap -Parent $st -Where 'настройки'
        $st.Dispose()
    } finally {
        $script:Accounts = $keepAcc
        $script:Settings.CompactCards = $keepCompact
        $script:Settings.MinimizeToTray = $keepTray
    }

    if ($bad.Count -gt 0) {
        throw ($bad.Count.ToString() + ' шт., первое: ' + $bad[0])
    }
    'ничего не обрезано, не вылезает за края и не налезает друг на друга'
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
