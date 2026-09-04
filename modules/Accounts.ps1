#requires -Version 5.1
<#
================================================================================
 modules\Accounts.ps1 — операции над аккаунтами и очередь запуска
================================================================================
 Копии и отмена действий, приглашения, разбор вставленных строк, починка
 входов, очередь запуска, раскладка окон, наборы и профили.

 Окон здесь нет — только действия над списком аккаунтов.
================================================================================
#>

# ------------------------------------------------------------- данные -------

function Copy-RamAccounts {
    <# Глубокая копия списка аккаунтов — снимок для отмены действия. #>
    $copy = @()
    foreach ($src in $script:Accounts) {
        $dst = New-RamAccount
        foreach ($p in $dst.PSObject.Properties.Name) {
            if ($src.PSObject.Properties.Name -contains $p) { $dst.$p = $src.$p }
        }
        $copy += $dst
    }
    return @($copy)
}

function Push-RamUndo {
    <#
      Снимок состояния ДО изменения — чтобы Ctrl+Z вернул как было.

      Ставится перед всем, что меняет аккаунты пачкой: игра, набор, метка,
      удаление, быстрая настройка. Ровно те места, где один клик мимо портит
      сразу все отмеченные аккаунты.

      Храним 10 последних шагов: глубже в такой программе не отматывают,
      а каждый шаг — это копия всего списка.
    #>
    param([Parameter(Mandatory)][string]$Label)

    [void]$script:UndoStack.Add([pscustomobject]@{
        Label    = $Label
        Accounts = Copy-RamAccounts
        At       = Get-Date
    })
    while ($script:UndoStack.Count -gt 10) { $script:UndoStack.RemoveAt(0) }
}

function Invoke-RamUndo {
    <# Ctrl+Z: вернуть аккаунты в состояние до последнего действия. #>
    if ($script:UndoStack.Count -eq 0) {
        Set-RamStatus 'Отменять нечего — с открытия программы список не менялся.'
        return
    }

    $last = $script:UndoStack[$script:UndoStack.Count - 1]
    $script:UndoStack.RemoveAt($script:UndoStack.Count - 1)

    $script:Accounts = @($last.Accounts)
    Save-RamState
    Build-RamCards
    Write-RamLog "Отменено: $($last.Label)." 'ok'
    Set-RamStatus "Отменено: $($last.Label)."
}

function Get-RamAccountById {
    param([string]$Id)
    foreach ($a in $script:Accounts) { if ($a.Id -eq $Id) { return $a } }
    return $null
}

function Save-RamState {
    if ($script:ReadOnly) {
        # Проверочный запуск — молча ничего не пишем.
        return
    }
    try {
        # Обёртка @() обязательна. PowerShell разворачивает пустой массив при
        # возврате из функции, поэтому при НУЛЕ аккаунтов $script:Accounts
        # становился пустотой, и сохранение падало с «аргумент имеет значение
        # NULL» — ровно то, что человек видел на чистой установке.
        if ($null -eq $script:Accounts) { $script:Accounts = @() }
        Save-RamAccounts -Accounts @($script:Accounts) -Password $script:MasterPassword
    } catch {
        Show-RamError "Не удалось сохранить список аккаунтов:`n`n$($_.Exception.Message)"
    }
}

function ConvertTo-RamInviteCode {
    <#
      Упаковывает аккаунт (вместе с игрой и настройками) в одну строку
      althub://, которую удобно перенести на другой свой компьютер.

      ВНУТРИ ЛЕЖИТ КУКА — то есть доступ к аккаунту. Это перенос СЕБЕ, а не
      публичная раздача. В интерфейсе так и предупреждаем.
    #>
    param([Parameter(Mandatory)]$Account)

    $payload = [ordered]@{
        v        = 1
        alias    = [string]$Account.Alias
        cookie   = [string]$Account.Cookie
        placeId  = [string]$Account.PlaceId
        linkCode = [string]$Account.LinkCode
        gameName = [string]$Account.GameName
        graphics = [string]$Account.Graphics
        volume   = [string]$Account.Volume
        fps      = [string]$Account.FramerateCap
        group    = [string]$Account.Group
        color    = [string]$Account.Color
        note     = [string]$Account.Note
    }
    $json  = ($payload | ConvertTo-Json -Compress)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return 'althub://v1/' + [Convert]::ToBase64String($bytes)
}

function ConvertFrom-RamInviteCode {
    <#
      Разбирает строку althub://. Возвращает объект с полями аккаунта или
      $null, если строка не похожа на приглашение.
    #>
    param([string]$Code)
    if ([string]::IsNullOrWhiteSpace($Code)) { return $null }
    $c = $Code.Trim()
    if ($c -notmatch '^althub://v1/(.+)$') { return $null }
    $b64 = $Matches[1].Trim()
    try {
        $bytes = [Convert]::FromBase64String($b64)
        $json  = [System.Text.Encoding]::UTF8.GetString($bytes)
        return ($json | ConvertFrom-Json)
    } catch { return $null }
}

function Import-RamAccountLine {
    <#
      Добавляет один аккаунт из строки: это либо приглашение althub://, либо
      голая кука .ROBLOSECURITY. Возвращает @{ Ok; New; Alias; Error }.

      Сеть здесь ОБЯЗАТЕЛЬНА: без проверки куки у Roblox мы не знаем ни ника,
      ни того, живой ли вообще вход. Пустые и мусорные строки отсекаем заранее,
      чтобы не гонять запрос впустую.
    #>
    param([Parameter(Mandatory)][string]$Line)

    $line = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { return $null }

    $invite = ConvertFrom-RamInviteCode -Code $line
    try {
        if ($null -ne $invite) {
            $res = Add-RamAccountFromCookie -Cookie ([string]$invite.cookie) -PlaceId ([string]$invite.placeId)
            $a = $res.Account
            # приглашение несёт ещё игру и настройки — переносим их
            foreach ($pair in @(
                @('LinkCode', $invite.linkCode), @('GameName', $invite.gameName),
                @('Graphics', $invite.graphics), @('Volume', $invite.volume),
                @('FramerateCap', $invite.fps), @('Group', $invite.group),
                @('Color', $invite.color), @('Note', $invite.note))) {
                if (-not [string]::IsNullOrWhiteSpace([string]$pair[1])) { $a.($pair[0]) = [string]$pair[1] }
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$invite.alias)) { $a.Alias = [string]$invite.alias }
            Save-RamState
            return @{ Ok = $true; New = $res.IsNew; Alias = $a.Alias; Error = '' }
        }

        # голая кука: отсекаем очевидный мусор до запроса
        if ($line.Length -lt 50) { return @{ Ok = $false; New = $false; Alias = ''; Error = 'строка слишком короткая для куки' } }
        $res = Add-RamAccountFromCookie -Cookie $line
        return @{ Ok = $true; New = $res.IsNew; Alias = $res.Account.Alias; Error = '' }
    } catch {
        return @{ Ok = $false; New = $false; Alias = ''; Error = $_.Exception.Message }
    }
}

function Import-RamAccountBatch {
    <#
      Добавляет пачку аккаунтов: по строке на аккаунт. Каждая строка — кука
      или приглашение althub://. Возвращает сводку для показа человеку.
    #>
    param([Parameter(Mandatory)][string]$Text)

    $lines = @($Text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $added = 0; $updated = 0; $failed = 0; $names = @(); $errors = @()

    foreach ($ln in $lines) {
        $r = Import-RamAccountLine -Line $ln
        if ($null -eq $r) { continue }
        if ($r.Ok) {
            if ($r.New) { $added++; $names += $r.Alias } else { $updated++ }
        } else {
            $failed++
            $errors += $r.Error
        }
    }

    return [pscustomobject]@{
        Added = $added; Updated = $updated; Failed = $failed
        Names = $names; Errors = $errors; Total = $lines.Count
    }
}

function Add-RamAccountFromCookie {
    <# Создаёт аккаунт по куке, подтягивает ник и UserID. #>
    param(
        [Parameter(Mandatory)][string]$Cookie,
        [string]$PlaceId = ''
    )
    $user = Get-RamAuthenticatedUser -Cookie $Cookie

    foreach ($a in $script:Accounts) {
        if ($a.UserId -eq $user.Id) {
            # Аккаунт уже есть — обновляем куку.
            $a.Cookie   = $Cookie
            $a.Username = $user.Name
            # И СНИМАЕМ МЕТКУ «ВХОД МЁРТВ». Её тут не снимали вообще, ни при
            # одном способе добавления: человек заново входил в аккаунт, кука
            # приезжала живая, программа отвечала «готово» — а карточка
            # оставалась красной с надписью «вход мёртв». Мы только что
            # получили от Roblox имя по этой куке через Get-RamAuthenticatedUser,
            # то есть она заведомо рабочая — молчать об этом нельзя.
            $a.CookieOk     = 'yes'
            $a.CookieCheckedAt = (Get-Date).ToString('s')
            Save-RamState
            return [pscustomobject]@{ Account = $a; IsNew = $false; User = $user }
        }
    }

    $acc = New-RamAccount -Alias $user.Name -Cookie $Cookie -PlaceId $PlaceId
    $acc.Username = $user.Name
    $acc.UserId   = $user.Id
    # Кука только что подтверждена сервером — так и записываем, чтобы новый
    # аккаунт не висел с неизвестным состоянием входа до первой проверки.
    $acc.CookieOk = 'yes'
    $acc.CookieCheckedAt = (Get-Date).ToString('s')
    $script:Accounts = @($script:Accounts) + $acc
    Save-RamState

    return [pscustomobject]@{ Account = $acc; IsNew = $true; User = $user }
}

function Add-RamSavedGame {
    <# Запоминает игру в список «Мои игры», чтобы в следующий раз не искать
       ссылку заново. Новые сверху, дубли по паре PlaceId+LinkCode убираются,
       больше 15 не храним. #>
    param([string]$PlaceId, [string]$LinkCode, [string]$Title)

    if ([string]::IsNullOrWhiteSpace($PlaceId)) { return }
    if ([string]::IsNullOrWhiteSpace($Title))   { $Title = "ID $PlaceId" }
    if ($LinkCode) { $Title = "$Title (приватный сервер)" }

    $entry = [pscustomobject]@{ Title = $Title; PlaceId = $PlaceId; LinkCode = $LinkCode }

    $rest = @()
    foreach ($g in @($script:Settings.Games)) {
        if ($null -eq $g) { continue }
        if ($g.PlaceId -eq $PlaceId -and [string]$g.LinkCode -eq [string]$LinkCode) { continue }
        $rest += $g
    }

    $script:Settings.Games = @(@($entry) + $rest | Select-Object -First 15)
    Save-RamSettings -Settings $script:Settings
}

function Get-RamGameSuggestions {
    <# Список для выпадающего меню в окне выбора игры. #>
    $out = @()
    foreach ($g in @($script:Settings.Games)) {
        if ($null -eq $g -or [string]::IsNullOrWhiteSpace($g.PlaceId)) { continue }
        $val = if ($g.LinkCode) { "$($g.PlaceId)|$($g.LinkCode)" } else { [string]$g.PlaceId }
        $out += [pscustomobject]@{ Text = [string]$g.Title; Value = $val }
    }
    return @($out)
}

function Update-RamRefreshedCookie {
    <#
      Roblox прислал свежую .ROBLOSECURITY вместо старой — сохраняем её.

      Задумывалось как лекарство от «куки постоянно вылетают»: раньше такие
      обновления выбрасывались, старая кука доживала своё и аккаунт приходилось
      заводить заново.

      ВАЖНО, ЧЕСТНО. На практике эта ветка не срабатывает: по журналам Roblox
      на тех запросах, которые делает AltHub, свежую .ROBLOSECURITY не
      присылает — строка про обновление не появилась ни разу. Код правильный
      и вреда не делает, но считать его средством от умирающих входов нельзя.
      Рабочее средство — кнопка «Починить входы».

      В журнал попадает только ник — сама кука никуда не пишется.
    #>
    param([string]$OldCookie, [string]$NewCookie)

    if ([string]::IsNullOrWhiteSpace($NewCookie)) { return }
    if ($OldCookie -eq $NewCookie) { return }

    $hit = $null
    foreach ($a in $script:Accounts) {
        if ($a.Cookie -eq $OldCookie) { $hit = $a; break }
    }
    if ($null -eq $hit) { return }

    $hit.Cookie = $NewCookie
    Clear-RamCsrfCache -Cookie $OldCookie
    Save-RamState
    Write-RamLog "'$($hit.Alias)': Roblox обновил вход, сохранил свежий." 'ok'
}

function Get-RamAnyCookie {
    <# Кука любого добавленного аккаунта. Нужна для запросов, на которые Roblox
       отвечает только авторизованным — например, расшифровка share-ссылки.
       Берём первую попавшуюся: запрос идёт от твоего же аккаунта. #>
    foreach ($a in $script:Accounts) {
        if (-not [string]::IsNullOrWhiteSpace($a.Cookie)) { return $a.Cookie }
    }
    return ''
}

function Update-RamAppAccountWatch {
    <#
      Замечает, что в приложении Roblox сменился аккаунт, и предлагает добавить
      его одной кнопкой.

      Раньше человек должен был сам открыть мастер и нажать «Проверить снова».
      Первый же сторонний пользователь сказал прямо: у соседней программы
      добавление проще. Кука и так лежит в хранилище клиента — остаётся её
      заметить.

      Дёшево: файл читается ТОЛЬКО когда сменилось время его записи. В покое
      это одна проверка атрибутов файла за такт.
    #>
    if ($script:ReadOnly) { return }

    try {
        $f = Get-RamRobloxCookieFile
        if (-not (Test-Path -LiteralPath $f)) { return }
        $stamp = (Get-Item -LiteralPath $f).LastWriteTime.Ticks
        if ($stamp -eq $script:AppCookieStamp) { return }
        $script:AppCookieStamp = $stamp
    } catch { return }

    $cookie = ''
    try { $cookie = Get-RamCookieFromRobloxApp } catch { return }
    if ([string]::IsNullOrWhiteSpace($cookie)) { return }

    # Уже знаем этот вход — предлагать нечего.
    foreach ($a in @($script:Accounts)) {
        if ($null -ne $a -and $a.Cookie -eq $cookie) { $script:AppOffer = $null; return }
    }
    # Тот же самый, про который уже спрашивали — не назойливничаем.
    if ($null -ne $script:AppOffer -and $script:AppOffer.Cookie -eq $cookie) { return }

    $user = $null
    try { $user = Get-RamAuthenticatedUser -Cookie $cookie } catch { return }
    if ($null -eq $user -or -not $user.Name) { return }

    # [int64], а НЕ [int]: номера аккаунтов Roblox давно перевалили за два
    # миллиарда, и 4062608487 в Int32 не влезает. С [int] это падало на
    # каждом такте у любого, чей аккаунт заведён недавно.
    $script:AppOffer = [pscustomobject]@{ Cookie = $cookie; Name = [string]$user.Name; UserId = [int64]$user.Id }
    Set-RamStatus "В приложении Roblox сейчас «$($user.Name)» — нажми сюда, чтобы добавить его в менеджер"
    Write-RamLog "В приложении Roblox замечен «$($user.Name)» — его можно добавить одним кликом по строке внизу." 'info'
}

function Invoke-RamAppOffer {
    <# Клик по строке состояния, когда там висит предложение добавить аккаунт. #>
    $offer = $script:AppOffer
    if ($null -eq $offer) { return }

    foreach ($a in @($script:Accounts)) {
        if ($null -ne $a -and $a.Cookie -eq $offer.Cookie) { $script:AppOffer = $null; return }
    }

    if (-not (Confirm-Ram "Добавить аккаунт «$($offer.Name)» в менеджер?`n`nВход берётся из приложения Roblox, пароль не нужен.")) {
        # Больше про этот вход не спрашиваем, пока в приложении не сменят аккаунт.
        $script:AppOffer = $null
        return
    }

    $script:AppOffer = $null
    try {
        $r = Add-RamAccountFromCookie -Cookie $offer.Cookie
        Build-RamCards
        Update-RamHeaderCounts
        if ($r.IsNew) {
            Set-RamStatus "Добавлен «$($r.User.Name)»"
            Write-RamLog "Добавлен аккаунт «$($r.User.Name)» из приложения Roblox." 'ok'
        } else {
            Set-RamStatus "Вход «$($r.User.Name)» обновлён"
            Write-RamLog "Обновлён вход аккаунта «$($r.User.Name)» из приложения Roblox." 'ok'
        }
    } catch {
        Show-RamError $_.Exception.Message
    }
}

function Get-RamKnownGameName {
    <#
      Название игры, которое уже где-то известно менеджеру: в сохранённых
      играх или у любого аккаунта с тем же placeId.

      Нужно как запасной вариант к Get-RamPlaceName: тот ходит в сеть и при
      любой заминке возвращает пустую строку. Пустая строка, записанная в
      аккаунт, стирала нормальное название, и на карточке вместо
      «Elemental Dungeons» появлялся голый «ID 10515146389».
    #>
    param([string]$PlaceId)
    if ([string]::IsNullOrWhiteSpace($PlaceId)) { return '' }

    foreach ($g in @($script:Settings.Games)) {
        if ($null -ne $g -and [string]$g.PlaceId -eq $PlaceId -and $g.Title) {
            return (([string]$g.Title) -replace ' \(приватный сервер\)$', '')
        }
    }
    foreach ($a in @($script:Accounts)) {
        if ($null -ne $a -and [string]$a.PlaceId -eq $PlaceId -and $a.GameName) { return [string]$a.GameName }
    }
    return ''
}

function Resolve-RamGameInput {
    <#
      Принимает что угодно и возвращает @{ PlaceId; LinkCode; GameName }:

        пусто                          -> всё пусто = "просто открыть Roblox"
        123456789                      -> обычная игра
        .../games/123456789/Name       -> обычная игра
        ...?privateServerLinkCode=XXX  -> игра + приватный сервер
        .../share?code=..&type=Server  -> спрашиваем у Roblox, что за ней стоит

      Последний случай — новый формат ссылок "Поделиться". В самой ссылке нет
      ни ID игры, ни кода сервера, поэтому её приходится расшифровывать
      запросом к Roblox.
    #>
    param([string]$Value)

    $res = [pscustomobject]@{ PlaceId = ''; LinkCode = ''; GameName = '' }
    if ([string]::IsNullOrWhiteSpace($Value)) { return $res }

    # Значение из списка «Мои игры» приходит как "placeId" или "placeId|код".
    if ($Value -match '^(\d+)\|([A-Za-z0-9_\-]+)$') {
        $res.PlaceId  = $Matches[1]
        $res.LinkCode = $Matches[2]
        $res.GameName = Get-RamPlaceName -PlaceId $res.PlaceId
        if (-not $res.GameName) { $res.GameName = Get-RamKnownGameName -PlaceId $res.PlaceId }
        return $res
    }

    $share = ConvertTo-RamShareLink -Value $Value
    if ($null -ne $share) {
        $cookie = Get-RamAnyCookie
        if ([string]::IsNullOrWhiteSpace($cookie)) {
            throw 'Чтобы разобрать ссылку «Поделиться», нужен хотя бы один добавленный аккаунт: Roblox отвечает на такие запросы только авторизованным.'
        }
        $r = Resolve-RamShareLink -Cookie $cookie -Code $share.Code -LinkType $share.Type
        $res.PlaceId  = $r.PlaceId
        $res.LinkCode = $r.LinkCode
        $res.GameName = $r.GameName
        if (-not $res.GameName) { $res.GameName = Get-RamPlaceName -PlaceId $res.PlaceId }
        if (-not $res.GameName) { $res.GameName = Get-RamKnownGameName -PlaceId $res.PlaceId }
        return $res
    }

    $placeId = ConvertTo-RamPlaceId -Value $Value
    if (-not $placeId) {
        throw @'
Не понял, что это за ссылка.

Подойдёт любое из:
  • ссылка на игру — https://www.roblox.com/games/123456/Name
  • ссылка «Поделиться» — https://www.roblox.com/share?code=...&type=Server
  • приглашение на приватный сервер — ...?privateServerLinkCode=...
  • просто ID игры числом

Или оставь поле пустым — тогда Roblox просто откроется, а игру выберешь сам.
'@
    }
    $res.PlaceId  = $placeId
    $res.LinkCode = ConvertTo-RamLinkCode -Value $Value
    $res.GameName = Get-RamPlaceName -PlaceId $placeId
    if (-not $res.GameName) { $res.GameName = Get-RamKnownGameName -PlaceId $placeId }
    return $res
}



function Invoke-RamRepairAll {
    <#
      Проводит по всем мёртвым входам подряд.

      Для каждого сначала тихая попытка забрать куку из приложения Roblox —
      вдруг там уже сидит нужный аккаунт. Если нет, показываем, что делать,
      и ждём. Так пять входов чинятся за один заход, а не пятью заходами
      в мастер.
    #>
    $dead = @($script:Accounts | Where-Object { [string]$_.CookieOk -eq 'no' })
    if ($dead.Count -eq 0) {
        Show-RamInfo 'Все входы живые — чинить нечего.'
        return
    }

    Write-RamLog "Починка входов: мёртвых $($dead.Count)." 'info'

    $fixed = 0; $skipped = 0; $stopped = $false

    foreach ($acc in $dead) {
        if (Invoke-RamRepairCookie -Account $acc -Quiet) {
            Set-RamCookieAlive -Account $acc
            $fixed++
            Write-RamLog "'$($acc.Alias)': вход подхватился из приложения сам." 'ok'
            continue
        }

        $done = $false
        while (-not $done) {
            $left = $dead.Count - $fixed - $skipped
            # ДВА ПУТИ, А НЕ ОДИН.
            # Раньше починка умела только «войди в приложении Roblox и вернись
            # сюда». Для твинков это мучение: приходится по очереди входить в
            # приложение каждым, а Roblox держит только один вход разом. Теперь
            # рядом стоит «Окно браузера» — там вход делается прямо здесь, без
            # хождения в приложение.
            $msg  = "Аккаунт «$($acc.Alias)» — вход мёртв, его надо взять заново.`n`n" +
                    "Способ первый, быстрее для твинков: нажми «Окно браузера» — откроется " +
                    "настоящий Chrome, войдёшь в «$($acc.Alias)» руками, и вход встанет на место.`n`n" +
                    "Способ второй, через приложение: открой Roblox под «$($acc.Alias)» и нажми " +
                    "«Забрать вход». Если в приложении сейчас другой аккаунт — «Сменить аккаунт»: " +
                    "Roblox закроется и забудет вход, а на сервере он останется живым. " +
                    "Кнопку «Выйти» внутри Roblox не трогай, она убивает вход насовсем.`n`n" +
                    "Осталось починить: $left"

            $ans = Show-RamMessage -Message $msg -Title 'Починка входов' -Kind 'warn' -Buttons @(
                @{ Text = 'Окно браузера';   Value = 'window'; Kind = 'primary' },
                @{ Text = 'Забрать вход';    Value = 'take'   },
                @{ Text = 'Сменить аккаунт'; Value = 'switch' },
                @{ Text = 'Пропустить';      Value = 'skip'   },
                @{ Text = 'Хватит';          Value = 'stop'   }
            )

            switch ([string]$ans) {
                'window' {
                    $cookie = $null
                    try { $cookie = Show-RamExternalBrowserLoginWindow }
                    catch {
                        Write-RamLog "Починка входов: $($_.Exception.Message)" 'err'
                        Show-RamError -Text ('Не удалось открыть окно входа:' + [Environment]::NewLine +
                                             [Environment]::NewLine + $_.Exception.Message)
                    }
                    if ($cookie) {
                        $r = Import-RamAccountLine -Line $cookie
                        if ($r -and $r.Ok) {
                            if ($r.Alias -eq $acc.Alias) {
                                $fixed++
                                $done = $true
                                Write-RamLog "'$($acc.Alias)': вход обновлён через окно браузера." 'ok'
                            } else {
                                # Вошли не под тем — говорим прямо, а не молча
                                # засчитываем починку.
                                Write-RamLog "Ожидался «$($acc.Alias)», вошли под «$($r.Alias)»." 'warn'
                                Show-RamInfo ("Вошли под «$($r.Alias)», а не под «$($acc.Alias)»." + [Environment]::NewLine +
                                              [Environment]::NewLine + "Он добавлен в список, но вход в «$($acc.Alias)» остался мёртвым.")
                            }
                        } else {
                            $why = if ($r -and $r.Error) { $r.Error } else { 'Roblox не подтвердил вход' }
                            Show-RamError -Text ('Вход не подошёл:' + [Environment]::NewLine + [Environment]::NewLine + $why)
                        }
                    }
                }
                'take' {
                    if (Invoke-RamRepairCookie -Account $acc) {
                        Set-RamCookieAlive -Account $acc
                        $fixed++
                        $done = $true
                    }
                }
                'switch' { [void](Clear-RamAppSession -Label $acc.Alias) }
                'skip'   { $skipped++; $done = $true }
                default  { $stopped = $true; $done = $true }   # «Хватит» и крестик
            }
        }
        if ($stopped) { break }
    }

    Save-RamState
    Build-RamCards

    if ($fixed -gt 0) {
        $tail = if ($stopped) { ' Остальные оставили как есть.' } else { '' }
        Write-RamLog "Починка входов: восстановлено $fixed из $($dead.Count)." 'ok'
        Show-RamInfo "Починено входов: $fixed из $($dead.Count).$tail"
    } else {
        Write-RamLog 'Починка входов: ничего не восстановлено.' 'warn'
    }
}

function Get-RamActionTargets {
    <#
      Кого затронет действие из панели.

      Раньше кнопки «Игра», «Набор», «Метка» просто отказывались работать без
      галочек, а «Запустить» в той же ситуации брала всех — выглядело как будто
      кнопка сломана. Теперь поведение одинаковое: нет отметок — спрашиваем,
      применить ли ко всем показанным.
    #>
    param([string]$What = 'это действие')

    $checked = @(Get-RamTargetAccounts)
    if ($checked.Count -gt 0) { return $checked }

    $visible = @(Get-RamVisibleAccounts)
    if ($visible.Count -eq 0) {
        Show-RamInfo 'Список пуст — некого выбирать.'
        return @()
    }

    $where = if ($script:GroupFilter) { " из набора «$($script:GroupFilter)»" }
             elseif ($script:Filter)  { ' из найденных' }
             else { '' }

    if (Confirm-Ram ("Галочки не стоят.`n`nПрименить $What ко всем показанным аккаунтам$where (их $($visible.Count))?")) {
        return $visible
    }
    return @()
}

# ВАЖНО про `return @(...)` в функциях ниже.
# PowerShell при возврате разворачивает массив: список из ОДНОГО элемента
# приходит вызывающему как одиночный объект, и .Count на нём не работает.
# Из-за этого одна поставленная галочка читалась как «галочек нет».
# Оператор запятой возвращает массив как есть — не убирать.

# ВАЖНО, ГРАБЛИ POWERSHELL.
# При возврате из функции PowerShell разворачивает массив: список из ОДНОГО
# элемента приходит вызывающему как одиночный объект. А .Count у одиночного
# PSCustomObject возвращает НЕ 1, а пустоту — и проверка `if ($x.Count -gt 0)`
# молча становится ложной. Именно из-за этого одна поставленная галочка
# читалась как «галочек нет».
#
# Лечение — обёртка @(...) на стороне ВЫЗОВА: @(Get-RamTargetAccounts).Count
# верна и для нуля, и для одного, и для многих элементов.
#
# Оператор запятой (return ,@(...)) для этого НЕ годится: он чинит .Count,
# но ломает foreach — тот начинает выдавать весь массив одним элементом.
#
# ВАЖНО, ГРАБЛИ ЗАМЫКАНИЙ.
# $scriptblock.GetNewClosure() создаёт НОВЫЙ динамический модуль. Внутри
# такого замыкания модификатор $script: указывает на область ЭТОГО модуля,
# а не файла. Поэтому:
#   чтение  $script:Settings  ->  $null
#   запись  $script:Флаг = 1  ->  уходит в никуда, снаружи не видна
#
# Так упало «Добавить отмеченные» в популярных играх: Save-RamSettings
# получил $null в обязательный параметр. И так же молча терялись флаги
# «сколько добавлено» в пачечном добавлении и в мастере из браузера.
#
# Лечение:
#   * значения наружу — через захваченный ХЭШ ($result = @{ Added = 0 }),
#     он копируется по ссылке и потому работает;
#   * доступ к состоянию — через ВЫЗОВ ФУНКЦИИ (Save-RamSettingsNow),
#     внутри функции область снова правильная.
#
# Самопроверка ловит этот класс ошибок разбором AST — см. проверку
# «Замыкания не трогают $script:».

function Save-RamSettingsNow {
    <#
      Сохраняет текущие настройки.

      Нужна ровно затем, что из замыканий .GetNewClosure() переменная
      $script:Settings не видна (см. «ГРАБЛИ ЗАМЫКАНИЙ» ниже), а вызов
      функции разрешается как обычно — внутри функции $script: снова
      указывает на область файла.
    #>
    Save-RamSettings -Settings $script:Settings
}

function Get-RamTargetAccounts {
    <#
      Отмеченные галочками — В ТОМ ЖЕ ПОРЯДКЕ, В КАКОМ ОНИ В СПИСКЕ.

      Раньше здесь шёл обход по $script:Accounts, то есть по порядку ХРАНЕНИЯ
      массива, а список на экране сортируется по полю Order. У аккаунта,
      добавленного последним, Order ставит его в середину списка, а в массиве
      он остаётся в конце — и запускался он последним, хотя в списке стоял
      третьим. Обещание «порядок в списке задаёт очередь запуска» не
      выполнялось.
    #>
    $res = @()
    foreach ($a in (Get-RamOrderedAccounts)) {
        $entry = $script:Cards[$a.Id]
        if ($null -ne $entry -and $entry.Check.Tag.Checked) { $res += $a }
    }
    return @($res)
}

function Export-RamSetup {
    <#
      Выгружает НАСТРОЙКИ и СПИСОК ИГР в обычный JSON, чтобы можно было
      отдать другу или перенести на другой компьютер.

      КУКИ НЕ ВЫГРУЖАЮТСЯ. Вообще. В файл попадают только названия аккаунтов
      и назначенные им игры — то есть раскладка твоего набора, а не доступ
      к нему. Каждый заводит свои входы сам через мастер.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $accounts = @()
    foreach ($a in $script:Accounts) {
        $accounts += [pscustomobject]@{
            Alias    = $a.Alias
            PlaceId  = $a.PlaceId
            GameName = $a.GameName
            LinkCode = $a.LinkCode
            JobId    = $a.JobId
            Note     = $a.Note
        }
    }

    $payload = [pscustomobject]@{
        app       = $script:AppName
        version   = $script:AppVersion
        exported  = (Get-Date).ToString('s')
        note      = 'Куки сюда НЕ попадают. Только названия аккаунтов и игры.'
        settings  = [pscustomobject]@{
            LaunchDelaySec = $script:Settings.LaunchDelaySec
            Locale         = $script:Settings.Locale
            Theme          = $script:Settings.Theme
            TileMode       = $script:Settings.TileMode
            TileColumns    = $script:Settings.TileColumns
            RenameWindows  = $script:Settings.RenameWindows
            AutoTile       = $script:Settings.AutoTile
            AutoRestart    = $script:Settings.AutoRestart
        }
        games     = @($script:Settings.Games)
        accounts  = $accounts
    }

    $json = ConvertTo-Json -InputObject $payload -Depth 6

    # Страховка от собственной ошибки: если в выгрузке вдруг окажется что-то
    # похожее на куку — не пишем файл вообще.
    if ($json -match '_\|WARNING' -or $json -match 'ROBLOSECURITY') {
        throw 'В выгрузке обнаружено похожее на куку. Файл не создан.'
    }

    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8 -Force
    return $accounts.Count
}

function Import-RamSetup {
    <# Забирает из файла настройки и список игр. Аккаунты НЕ создаёт: без куки
       они всё равно бесполезны, а куки в файле нет и быть не может. #>
    param([Parameter(Mandatory)][string]$Path)

    $obj = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)

    $applied = 0
    if ($obj.settings) {
        foreach ($k in @('LaunchDelaySec','Locale','Theme','TileMode','TileColumns',
                         'RenameWindows','AutoTile','AutoRestart')) {
            if ($obj.settings.PSObject.Properties.Name -contains $k) {
                $script:Settings.$k = $obj.settings.$k
                $applied++
            }
        }
    }

    $games = 0
    if ($obj.games) {
        $list = @()
        foreach ($g in @($obj.games)) {
            if ($null -eq $g -or [string]::IsNullOrWhiteSpace($g.PlaceId)) { continue }
            $list += [pscustomobject]@{
                Title    = [string]$g.Title
                PlaceId  = [string]$g.PlaceId
                LinkCode = [string]$g.LinkCode
            }
            $games++
        }
        $script:Settings.Games = @($list | Select-Object -First 15)
    }

    Save-RamSettings -Settings $script:Settings
    return [pscustomobject]@{ Settings = $applied; Games = $games }
}

function Invoke-RamDeleteSelected {
    <# Удаление отмеченных. Вынесено отдельно, чтобы работать и с кнопки,
       и с клавиши Delete. Удаление опасное, поэтому здесь без «взять всех
       молча» — только явные галочки либо явный -Accounts из меню карточки. #>
    param([object[]]$Accounts)

    $targets = if (@($Accounts).Count -gt 0) { @($Accounts) } else { @(Get-RamTargetAccounts) }
    if ($targets.Count -eq 0) {
        Show-RamInfo 'Отметь галочками, кого убрать. Для удаления AltHub нарочно не берёт всех подряд.'
        return
    }

    $names = ($targets | ForEach-Object { $_.Alias }) -join ', '
    if (-not (Confirm-Ram "Убрать из менеджера: $names ?`n`nСами аккаунты Roblox не пострадают — сотрутся только сохранённые здесь данные.")) { return }

    Push-RamUndo -Label "удаление аккаунтов ($($targets.Count))"
    $ids = $targets | ForEach-Object { $_.Id }
    $script:Accounts = @($script:Accounts | Where-Object { $ids -notcontains $_.Id })
    Save-RamState
    Build-RamCards
    Write-RamLog "Удалено аккаунтов: $($targets.Count)." 'ok'
}

function Set-RamAllChecked {
    param([bool]$Checked)
    foreach ($id in $script:Cards.Keys) {
        $script:Cards[$id].Check.Tag.Checked = $Checked
        $script:Cards[$id].Check.Invalidate()
    }
    Update-RamStatusLine
}

# ----------------------------------------------------------- запуск ---------

function Add-RamToLaunchQueue {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Accounts)

    if ($Accounts.Count -eq 0) {
        Show-RamInfo 'Никто не отмечен. Поставь галочки слева у нужных аккаунтов.'
        return
    }

    # Пошла новая пачка — раскладка от предыдущей больше не актуальна,
    # иначе она сработает посреди запуска следующих окон.
    $script:PendingTileUntil = [datetime]::MinValue

    # Больше окон, чем вытягивает машина — предупреждаем один раз за запуск.
    # Не запрещаем: сколько тянет его компьютер, человек знает лучше нас.
    $willRun = $Accounts.Count + @($script:Instances.Keys).Count
    $canRun  = Get-RamRecommendedAccountCount
    if ($willRun -gt $canRun -and -not $script:WarnedAboutLoad) {
        $script:WarnedAboutLoad = $true
        $hw = Get-RamHardware
        $ans = Show-RamMessage -Title 'Много окон сразу' -Kind 'warn' -Message (
            "Собираешься держать открытыми $willRun клиентов Roblox.`n`n" +
            "$(Get-RamHardwareSummary -Hardware $hw)`n`n" +
            "На такой машине уверенно идут примерно $canRun. Больше — начнёт подтормаживать всё, включая основной аккаунт.`n`n" +
            "Помогает поставить твинкам набор «Фоновый фарм»: правый клик по карточке -> «Готовый набор настроек»."
        ) -Buttons @(
            @{ Text = 'Всё равно запустить'; Value = 'go'; Kind = 'primary' },
            @{ Text = 'Отмена';              Value = 'no' }
        )
        if ([string]$ans -ne 'go') {
            Write-RamLog "Запуск отменён: просили $willRun окон при рекомендованных $canRun." 'info'
            return
        }
    }

    # Идёт обновление — запускать нельзя: установщик закроет всё, что успеет
    # открыться, и это будет выглядеть как поломка мультизапуска.
    if (Test-RamRobloxUpdating) {
        Show-RamInfo "Roblox сейчас обновляется.`n`nПодожди, пока обновление закончится, и запусти снова. Если запустить прямо сейчас, установщик закроет открытые окна."
        Write-RamLog 'Запуск отменён: идёт обновление Roblox.' 'warn'
        return
    }

    # Путь пересчитываем каждый раз: Roblox мог обновиться прямо во время
    # работы менеджера, и старый путь стал бы устаревшим клиентом.
    try {
        $newPath = Get-RamRobloxPlayerPath
        if ($newPath -ne $script:PlayerPath) {
            $script:PlayerPath = $newPath
            $ver = (Get-RamRobloxClients | Select-Object -First 1).Version
            Write-RamLog "Клиент Roblox: версия $ver" 'info'
        }
    } catch {
        Show-RamError $_.Exception.Message
        return
    }

    # Второй замок (имя ROBLOX_singletonEvent) можно занять только пока не
    # запущен ни один Roblox. Если опоздали — окна придётся закрыть, иначе
    # каждый новый клиент будет закрывать предыдущий.
    if ($script:Settings.KeepMutex) {
        $lock = Enable-RamMultiInstance
        if (-not $lock.EventBlocked) {
            $running = @(Get-RamRobloxProcesses)
            if ($running.Count -gt 0) {
                $ok = Confirm-Ram (
                    "Мультизапуск не включится: Roblox уже был открыт до менеджера.`n`n" +
                    "Пока это так, каждый новый клиент будет закрывать предыдущий — " +
                    "и в итоге останется одно окно.`n`n" +
                    "Закрыть сейчас все окна Roblox (открыто: $($running.Count)) и включить мультизапуск?")
                if (-not $ok) {
                    Write-RamLog 'Запуск отменён: мультизапуск выключен, окна Roblox не закрыты.' 'warn'
                    return
                }
                foreach ($p in $running) { [void](Stop-RamRobloxInstance -ProcessId $p.Id) }
                $script:Instances.Clear()
                Start-Sleep -Milliseconds 2500

                $lock = Enable-RamMultiInstance
                if ($lock.EventBlocked) {
                    Write-RamLog 'Окна Roblox закрыты, мультизапуск включён.' 'ok'
                } else {
                    Show-RamError 'Не получилось включить мультизапуск даже после закрытия окон. Закрой Roblox вручную через диспетчер задач и попробуй снова.'
                    return
                }
            } else {
                Write-RamLog 'Мультизапуск не включён, хотя Roblox не запущен — странно. Перезапусти менеджер.' 'warn'
            }
        }
    }

    $added = 0
    foreach ($a in $Accounts) {
        # Игра не задана — не беда: клиент откроется на главной под этим
        # аккаунтом, игру человек выберет сам.
        if ($script:Instances.ContainsKey($a.Id)) {
            Write-RamLog "Пропуск '$($a.Alias)': уже запущен." 'warn'
            continue
        }
        if ($script:LaunchQueue -contains $a.Id) { continue }
        [void]$script:LaunchQueue.Add($a.Id)
        $added++
    }

    if ($added -eq 0) { Update-RamCardStates; return }

    Write-RamLog "В очередь добавлено: $added. Пауза между запусками — $($script:Settings.LaunchDelaySec) с." 'info'
    $script:NextLaunchTime = Get-Date
    $script:UI.LaunchTimer.Start()
    Update-RamCardStates
}

function Restore-RamOwnClientSettings {
    <#
      Возвращает в общий файл Roblox ТВОИ настройки — те, что были до того,
      как AltHub первый раз что-то в нём поменял.

      Зачем: файл настроек у Roblox один на все окна. После пачки запусков в
      нём остаются настройки последнего твина, и обычный запуск Roblox мимо
      менеджера подхватил бы их.
    #>
    param([string]$Reason = '')

    if (-not $script:SettingsTouched) { return }
    if (-not (Test-Path -LiteralPath (Get-RamSettingsBackupPath))) { return }

    try {
        [void](Restore-RamRobloxSettings)
        $script:SettingsTouched = $false
        $note = if ($Reason) { " ($Reason)" } else { '' }
        Write-RamLog "Настройки графики Roblox возвращены к твоим$note." 'info'
    } catch {
        # Обычно значит, что клиент ещё запущен — вернём в следующий раз.
    }
}

function Test-RamSettingsFileFree {
    <#
      Можно ли уже переписывать общий файл настроек Roblox.

      ГЛАВНОЕ ПРО ГРАФИКУ, ЧИТАТЬ ЦЕЛИКОМ.

      Файл GlobalBasicSettings_13.xml у Roblox ОДИН на все клиенты. Настройки
      аккаунта пишутся в него прямо перед запуском этого аккаунта, а клиент
      читает файл не мгновенно — где-то в первые секунды загрузки. Пока он не
      прочитал, переписывать файл под следующий аккаунт нельзя: предыдущий
      клиент подхватит чужие настройки.

      Именно так ловился баг «у основного иногда графика 1 вместо 10»: твинк
      запускался через 8 секунд и перетирал файл раньше, чем основной успевал
      его прочитать. Когда машина шустрее — основной успевал, и всё было
      нормально. Отсюда «иногда».

      Признак того, что клиент дочитал настройки — появилось его окно. Его и
      ждём, но не дольше отведённого времени: клиент может и не дойти до окна,
      и держать из-за него всю очередь незачем.

      Ждём ТОЛЬКО когда настройки следующего аккаунта отличаются — иначе пять
      одинаковых твинков запускались бы втрое дольше без всякой пользы.
    #>
    if ([string]::IsNullOrEmpty($script:AwaitWindowFor)) { return $true }

    $inst = $script:Instances[$script:AwaitWindowFor]
    if ($null -eq $inst) { $script:AwaitWindowFor = ''; return $true }

    if ($inst.Handle -eq [IntPtr]::Zero) {
        $inst.Handle = Get-RamRobloxWindow -ProcessId $inst.ProcessId -TimeoutSec 0
    }
    if ($inst.Handle -ne [IntPtr]::Zero) {
        $script:AwaitWindowFor = ''
        return $true
    }

    if ((Get-Date) -ge $script:AwaitWindowUntil) {
        $prev = Get-RamAccountById -Id $script:AwaitWindowFor
        $who  = if ($null -ne $prev) { $prev.Alias } else { 'предыдущий' }
        Write-RamLog "'$who': окно не появилось вовремя. Запускаю следующего — настройки графики могли не успеть примениться." 'warn'
        $script:AwaitWindowFor = ''
        return $true
    }

    return $false
}

function Set-RamSettingsWait {
    <#
      Решает, надо ли дождаться окна только что запущенного клиента, прежде
      чем писать настройки следующего. Подробности — в Test-RamSettingsFileFree.
    #>
    param([Parameter(Mandatory)]$Launched)

    $script:AwaitWindowFor = ''
    if ($script:LaunchQueue.Count -eq 0) { return }

    $next = Get-RamAccountById -Id $script:LaunchQueue[0]
    if ($null -eq $next) { return }

    if ((Get-RamClientSettingsKey -Account $next) -eq (Get-RamClientSettingsKey -Account $Launched)) { return }

    $script:AwaitWindowFor   = $Launched.Id
    $script:AwaitWindowUntil = (Get-Date).AddSeconds(60)
}

function Show-RamLaunchReport {
    <#
      Итог пачки запусков. Раньше сорвавшийся аккаунт просто исчезал из
      очереди без следа, и со стороны это выглядело как «запускается только
      четыре». Теперь каждый несостоявшийся попадает сюда с причиной.
    #>
    if ($script:LaunchFailed.Count -eq 0) { return }

    $lines = @()
    foreach ($id in $script:LaunchFailed.Keys) {
        $acc  = Get-RamAccountById -Id $id
        $name = if ($null -ne $acc) { $acc.Alias } else { 'аккаунт' }
        $lines += "• $name — $($script:LaunchFailed[$id])"
    }
    $script:LaunchFailed = @{}

    Write-RamLog "Не запустились: $($lines.Count)." 'warn'
    Show-RamInfo ("Запустились не все. Не вышло у этих:`n`n" + ($lines -join "`n") +
                  "`n`nЧаще всего помогает пауза побольше между запусками — она в Настройках.")
}

function Get-RamClientOwner {
    <#
      Пытается понять, под каким аккаунтом работает клиент Roblox.

      Два ключа, оба уже есть в программе:
        1) заголовок окна — при включённом «писать имя аккаунта в заголовок»
           (по умолчанию так) он равен «Roblox — Имя аккаунта»;
        2) browsertrackerid из командной строки — он постоянный на аккаунт.

      Возвращает аккаунт или $null.

      Командную строку в журнал не пишем НИКОГДА: там же лежит одноразовый
      билет входа.
    #>
    param([Parameter(Mandatory)][int]$ProcessId, [IntPtr]$Handle = [IntPtr]::Zero)

    # --- по заголовку окна
    if ($Handle -ne [IntPtr]::Zero) {
        $title = ''
        try { $title = [Ram.Native]::TitleOf($Handle) } catch { }
        if (-not [string]::IsNullOrWhiteSpace($title)) {
            foreach ($a in $script:Accounts) {
                if ([string]::IsNullOrWhiteSpace($a.Alias)) { continue }
                # Тире в заголовке длинное (—), поэтому сверяем по имени, а не
                # по всей строке целиком.
                if ($title -eq "Roblox — $($a.Alias)" -or $title -eq $a.Alias) { return $a }
            }
        }
    }

    # --- по browsertrackerid
    $known = @($script:Accounts | Where-Object { -not [string]::IsNullOrWhiteSpace($_.BrowserTrackerId) })
    if ($known.Count -gt 0) {
        $cmd = ''
        try {
            $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop).CommandLine
        } catch { }
        if (-not [string]::IsNullOrWhiteSpace($cmd)) {
            foreach ($a in $known) {
                if ($cmd -match ("browsertrackerid:" + [regex]::Escape([string]$a.BrowserTrackerId) + "\b")) { return $a }
            }
        }
    }

    return $null
}

function Restore-RamAdoptRunningClients {
    <#
      Подхватывает клиенты Roblox, которые уже работают.

      ЗАЧЕМ. Список запущенных живёт только в памяти, поэтому после
      перезапуска менеджера работающие аккаунты показывались как «не
      запущен». Это не только вранье в списке: присмотр за набором считал
      их выпавшими и поднимал ДУБЛИКАТЫ, а кнопка «Запустить» открывала
      второго клиента под тем же аккаунтом.

      Опознанные попадают в список как обычно. Неопознанные тоже
      учитываются — под пустым ключом: этого достаточно, чтобы счётчики и
      раскладка были честными.
    #>
    $procs = @(Get-RamRobloxProcesses)
    if ($procs.Count -eq 0) { return 0 }

    $found = 0; $unknown = 0
    foreach ($proc in $procs) {
        # Уже знаем про этот процесс — пропускаем.
        $already = $false
        foreach ($inst in $script:Instances.Values) {
            if ([int]$inst.ProcessId -eq [int]$proc.Id) { $already = $true; break }
        }
        if ($already) { continue }

        $handle = [IntPtr]::Zero
        try { $handle = Get-RamRobloxWindow -ProcessId $proc.Id -TimeoutSec 0 } catch { }

        $acc = Get-RamClientOwner -ProcessId $proc.Id -Handle $handle
        $started = Get-Date
        try { $started = $proc.StartTime } catch { }

        if ($null -ne $acc) {
            if ($script:Instances.ContainsKey($acc.Id)) { continue }
            $script:Instances[$acc.Id] = [pscustomobject]@{
                ProcessId = $proc.Id
                Handle    = $handle
                Started   = $started
                Adopted   = $true
            }
            $found++
            Write-RamLog "Подхвачен уже работающий клиент: «$($acc.Alias)»." 'ok'
        } else {
            $unknown++
        }
    }

    if ($unknown -gt 0) {
        Write-RamLog "Работают ещё клиенты Roblox: $unknown — под каким аккаунтом, определить не вышло." 'warn'
    }
    if ($found -gt 0 -or $unknown -gt 0) {
        Update-RamCardStates
        Update-RamHeaderCounts
    }
    return $found
}

function Invoke-RamNextLaunch {
    if ($script:LaunchQueue.Count -eq 0) {
        $script:UI.LaunchTimer.Stop()
        $script:LaunchTries = @{}
        Show-RamLaunchReport

        # Раскладываем НЕ сразу. Клиент Roblox создаёт окно на несколько
        # секунд позже, чем стартует процесс, поэтому раскладка сразу после
        # запуска последнего аккаунта каждый раз выходила на одно окно
        # меньше, чем запущено. Ждём появления окон — см. Invoke-RamPendingTile.
        if ($script:Settings.AutoTile) {
            $script:PendingTileUntil = (Get-Date).AddSeconds(25)
        }

        Update-RamCardStates
        return
    }
    if ((Get-Date) -lt $script:NextLaunchTime) { return }

    # Пока предыдущий клиент не прочитал свои настройки графики, общий файл
    # трогать нельзя — иначе он подхватит чужие. См. Test-RamSettingsFileFree.
    if (-not (Test-RamSettingsFileFree)) { return }

    $id = $script:LaunchQueue[0]
    $script:LaunchQueue.RemoveAt(0)

    $a = Get-RamAccountById -Id $id
    if ($null -eq $a) { return }

    $tries = 0
    if ($script:LaunchTries.ContainsKey($id)) { $tries = [int]$script:LaunchTries[$id] }
    $script:LaunchTries[$id] = $tries + 1

    Set-RamStatus "Запускаю «$($a.Alias)»..."
    $where = if ($a.GameName) { $a.GameName } elseif ($a.PlaceId) { "игра $($a.PlaceId)" } else { 'главная Roblox (без игры)' }
    Write-RamLog "Запуск '$($a.Alias)' -> $where" 'info'

    try {
        # Настройки клиента пишутся в общий файл Roblox прямо сейчас — клиент
        # прочитает их при старте. Поэтому это делается перед каждым запуском,
        # а не один раз.
        $applied = @()
        try {
            $applied = Apply-RamAccountClientSettings -Account $a
            if ($applied.Count -gt 0) {
                $script:SettingsTouched = $true
                Write-RamLog "'$($a.Alias)': настройки клиента — $($applied -join ', ')" 'info'
            }
        } catch {
            Write-RamLog "'$($a.Alias)': настройки клиента не применились — $($_.Exception.Message)" 'warn'
        }

        $proc = Start-RamRobloxInstance -Account $a -PlayerPath $script:PlayerPath -Locale $script:Settings.Locale
        $script:LastLaunchAt = Get-Date

        $script:Instances[$a.Id] = [pscustomobject]@{
            ProcessId = $proc.Id
            Handle    = [IntPtr]::Zero
            Started   = Get-Date
        }
        $a.LastUsed    = (Get-Date).ToString('s')
        $a.LaunchCount = [int]$a.LaunchCount + 1
        $script:RestartCount[$a.Id] = 0
        Write-RamLog "'$($a.Alias)' стартовал (PID $($proc.Id))." 'ok'

        Set-RamSettingsWait -Launched $a
    } catch {
        $err = $_
        $msg = $err.Exception.Message
        Write-RamLog "'$($a.Alias)': $msg" 'err'

        # Запуск сорвался, а настройки графики мы в общий файл уже записали.
        # Оставлять их нельзя: откроешь Roblox вручную — и получишь графику
        # твина вместо своей.
        $script:AwaitWindowFor = ''
        Restore-RamOwnClientSettings -Reason 'запуск не состоялся'

        # «Слишком часто» — это не отказ, а просьба подождать. Возвращаем
        # аккаунт в НАЧАЛО очереди и просто сдвигаем время следующей попытки.
        # Спать здесь нельзя: код крутится в тике таймера, окно замёрзнет.
        $retryAfter = 0
        try { if ($null -ne $err.Exception.Data -and $err.Exception.Data.Contains('RamRetryAfter')) {
                  $retryAfter = [int]$err.Exception.Data['RamRetryAfter'] } } catch { }

        if ($retryAfter -gt 0 -and $tries -lt 4) {
            [void]$script:LaunchQueue.Insert(0, $a.Id)
            $script:NextLaunchTime = (Get-Date).AddSeconds($retryAfter)
            Set-RamStatus "Roblox просит сбавить темп. «$($a.Alias)» повторю через $retryAfter с."
            Write-RamLog "'$($a.Alias)': Roblox ограничил частоту, повтор через $retryAfter с (попытка $($tries + 1))." 'warn'
            Update-RamCardStates
            return
        }

        # Кука умерла — попробуем починить её из приложения Roblox молча.
        # Если там сейчас именно этот аккаунт, вход подхватится сам и мы тут же
        # повторим запуск. Спрашивать в середине пачки запусков некогда.
        if ($msg -match 'недействительна|протухла') {
            if (Invoke-RamRepairCookie -Account $a -Quiet) {
                Write-RamLog "'$($a.Alias)': вход починен, пробую запустить снова." 'ok'
                [void]$script:LaunchQueue.Insert(0, $a.Id)
                $script:NextLaunchTime = (Get-Date).AddSeconds([int]$script:Settings.LaunchDelaySec)
                Update-RamCardStates
                return
            }
        }

        # Прочие сбои: даём ещё пару попыток в конце очереди, потом сдаёмся
        # и запоминаем причину — молча терять аккаунт нельзя.
        if ($tries -lt 2) {
            [void]$script:LaunchQueue.Add($a.Id)
            Write-RamLog "'$($a.Alias)': попробую ещё раз в конце очереди." 'warn'
        } else {
            $script:LaunchFailed[$a.Id] = $msg
        }
    }

    $script:NextLaunchTime = (Get-Date).AddSeconds([int]$script:Settings.LaunchDelaySec)
    Update-RamCardStates
}

function Invoke-RamPendingTile {
    <#
      Держит раскладку до момента, когда окна реально появятся.

      Зовётся по таймеру обновления, уже после того как тот разобрал, у кого
      из запущенных аккаунтов появилось окно. Раскладываем, когда окна есть
      у всех — или когда ждать надоело: один клиент может и не дойти до окна,
      и держать из-за него остальных незачем.
    #>
    if ($script:PendingTileUntil -eq [datetime]::MinValue) { return }

    $total = $script:Instances.Count
    if ($total -eq 0) {
        $script:PendingTileUntil = [datetime]::MinValue
        return
    }

    $ready = 0
    foreach ($inst in $script:Instances.Values) {
        if ($inst.Handle -ne [IntPtr]::Zero) { $ready++ }
    }

    $timeUp = (Get-Date) -ge $script:PendingTileUntil
    if ($ready -lt $total -and -not $timeUp) { return }

    $script:PendingTileUntil = [datetime]::MinValue

    if ($ready -eq 0) {
        Write-RamLog 'Нечего раскладывать: окна так и не появились.' 'warn'
        return
    }
    if ($ready -lt $total) {
        Write-RamLog "Раскладываю $ready из ${total} — остальные окна не появились вовремя." 'warn'
    }
    Invoke-RamTileWindows
}

function Invoke-RamTileWindows {
    param([string]$Mode = '')

    $live = @()
    foreach ($a in $script:Accounts) {
        $inst = $script:Instances[$a.Id]
        if ($null -eq $inst) { continue }
        if ($inst.Handle -eq [IntPtr]::Zero) {
            $inst.Handle = Get-RamRobloxWindow -ProcessId $inst.ProcessId -TimeoutSec 0
        }
        if ($inst.Handle -ne [IntPtr]::Zero) {
            $inst | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
            $live += $inst
        }
    }

    if ($live.Count -eq 0) {
        Write-RamLog 'Нечего раскладывать: окна ещё не появились.' 'warn'
        return
    }

    $mode = if ($Mode) { $Mode } else { [string]$script:Settings.TileMode }
    # 'main' обязан быть в списке: его ставит «Быстрая настройка», и без него
    # выбор молча подменялся сеткой — в журнале каждый раз было «сеткой»,
    # хотя выбрано «основной крупно».
    if (@('grid','cascade','columns','rows','main') -notcontains $mode) { $mode = 'grid' }

    # Если у аккаунта запомнено своё место — ставим туда, а раскладку
    # считаем только для остальных.
    $auto = @()
    if ($script:Settings.UseSavedWindows -and -not $Mode) {
        foreach ($item in $live) {
            $acc = Get-RamAccountById -Id $item.AccountId
            if ($null -ne $acc -and [int]$acc.WindowW -gt 0 -and [int]$acc.WindowH -gt 0) {
                [void](Set-RamWindowBounds -Handle $item.Handle -X ([int]$acc.WindowX) -Y ([int]$acc.WindowY) `
                                           -Width ([int]$acc.WindowW) -Height ([int]$acc.WindowH))
            } else {
                $auto += $item
            }
        }
        $placed = $live.Count - $auto.Count
        if ($placed -gt 0 -and $auto.Count -eq 0) {
            Write-RamLog "Окна расставлены по запомненным местам: $placed шт." 'ok'
            return
        }
        $live = $auto
        if ($live.Count -eq 0) { return }
    }

    $layout = Get-RamTileLayout -Count $live.Count -Columns $script:Settings.TileColumns `
                                -Margin $script:Settings.TileMargin -Mode $mode
    for ($i = 0; $i -lt $live.Count; $i++) {
        $c = $layout[$i]
        [void](Set-RamWindowBounds -Handle $live[$i].Handle -X $c.X -Y $c.Y -Width $c.Width -Height $c.Height)
    }

    $names = @{ grid = 'сеткой'; cascade = 'каскадом'; columns = 'колонками'; rows = 'строками'
                main = 'основной крупно' }
    Write-RamLog "Окна разложены $($names[$mode]): $($live.Count) шт." 'ok'
}

function Update-RamInstances {
    <# Ищем появившиеся окна, подписываем заголовки, убираем закрывшиеся. #>
    # ОДИН снимок процессов на весь такт. Раньше по каждому экземпляру звался
    # Get-Process -Id, а на уже закрывшемся клиенте он БРОСАЕТ исключение —
    # PowerShell строит ErrorRecord со стеком, и это повторялось каждые две
    # секунды для каждого мёртвого клиента.
    $livePids = @{}
    foreach ($pr in @(Get-RamRobloxProcesses)) { $livePids[[int]$pr.Id] = $pr }

    $dead = @()
    $needSave = $false
    foreach ($id in @($script:Instances.Keys)) {
        $inst = $script:Instances[$id]

        if (-not $livePids.ContainsKey([int]$inst.ProcessId)) { $dead += $id; continue }

        if ($inst.Handle -eq [IntPtr]::Zero -or -not (Test-RamWindowAlive -Handle $inst.Handle)) {
            # Поиск окна — это полный обход ВСЕХ окон рабочего стола (сотни
            # переходов в WinAPI). Пока клиент грузится, окна ещё нет, и раньше
            # этот обход повторялся каждые две секунды для каждого стартующего
            # аккаунта. Ищем не чаще чем раз в три такта, то есть раз в 6 секунд.
            $skip = 0
            if ($inst.PSObject.Properties.Name -contains 'FindSkip') { $skip = [int]$inst.FindSkip }
            if ($skip -le 0) {
                $inst.Handle = Get-RamRobloxWindow -ProcessId $inst.ProcessId -TimeoutSec 0
                $inst | Add-Member -NotePropertyName FindSkip -NotePropertyValue $(if ($inst.Handle -eq [IntPtr]::Zero) { 2 } else { 0 }) -Force
            } else {
                $inst | Add-Member -NotePropertyName FindSkip -NotePropertyValue ($skip - 1) -Force
            }
        }

        if ($inst.Handle -ne [IntPtr]::Zero -and $script:Settings.RenameWindows) {
            $a = Get-RamAccountById -Id $id
            if ($null -ne $a) {
                $want = "Roblox — $($a.Alias)"
                if ([Ram.Native]::TitleOf($inst.Handle) -ne $want) {
                    [void](Set-RamWindowTitle -Handle $inst.Handle -Title $want)
                }
            }
        }
    }

    foreach ($id in $dead) {
        $a = Get-RamAccountById -Id $id
        $lived = $null
        $byUser = $false
        if ($script:Instances.ContainsKey($id)) {
            $inst2  = $script:Instances[$id]
            $lived  = (Get-Date) - $inst2.Started
            if ($inst2.PSObject.Properties.Name -contains 'ClosedByUser') { $byUser = [bool]$inst2.ClosedByUser }
        }
        $script:Instances.Remove($id)

        if ($null -eq $a) { continue }

        # Статистика: наигранное время копим всегда, вылетом считаем только
        # то, что закрылось само и прожило меньше минуты.
        if ($null -ne $lived) {
            $a.PlaySeconds = [int]$a.PlaySeconds + [int]$lived.TotalSeconds
            if (-not $byUser -and $lived.TotalSeconds -lt 60) {
                $a.CrashCount = [int]$a.CrashCount + 1
            }
        }
        $needSave = $true

        Write-RamLog "'$($a.Alias)' закрылся$(if($null -ne $lived){' (был в игре ' + (Format-RamDuration ([int]$lived.TotalSeconds)) + ')'})." 'info'

        if (-not $script:Settings.AutoRestart) { continue }

        # Окно, прожившее меньше 20 секунд, скорее всего не «вылетело», а не
        # смогло стартовать — гонять его по кругу бессмысленно.
        if ($null -ne $lived -and $lived.TotalSeconds -lt 20) {
            Write-RamLog "'$($a.Alias)': прожил меньше 20 с, автоперезапуск пропущен." 'warn'
            continue
        }

        $tries = 0
        if ($script:RestartCount.ContainsKey($id)) { $tries = [int]$script:RestartCount[$id] }
        if ($tries -ge [int]$script:Settings.AutoRestartMax) {
            Write-RamLog "'$($a.Alias)': достигнут предел автоперезапусков ($tries)." 'warn'
            continue
        }

        $script:RestartCount[$id] = $tries + 1
        Write-RamLog "'$($a.Alias)': вылетел, поднимаю заново (попытка $($tries + 1))." 'warn'
        Add-RamToLaunchQueue -Accounts @($a)
    }

    # Свои настройки графики возвращаем, когда все окна Roblox закрыты: файл
    # у Roblox общий, и трогать его при живых клиентах нельзя — они перезапишут
    # его своим состоянием при выходе.
    if ($script:SettingsTouched -and $script:Instances.Count -eq 0 -and
        @(Get-RamRobloxProcesses).Count -eq 0 -and
        ((Get-Date) - $script:LastLaunchAt).TotalSeconds -ge 15) {
        Restore-RamOwnClientSettings -Reason 'все окна Roblox закрыты'
    }

    # Сохраняем ОДИН раз за такт. Раньше Save-RamState вызывался внутри цикла:
    # если разом закрылось десять клиентов, получалось десять шифрований всего
    # списка и десять записей на диск в UI-потоке подряд.
    if ($needSave) { Save-RamState }

    Invoke-RamPendingTile

    Update-RamCardStates
    Update-RamOneAvatar
    Update-RamOneGameName
    Update-RamAppAccountWatch
    if ($script:Section -eq 'stats' -and $dead.Count -gt 0) { Update-RamStatsPanel }
}

# ------------------------------------------------------- действия ----------

function Invoke-RamAssignGame {
    <#
      Назначить игру отмеченным аккаунтам. С -Accounts работает ровно по ним
      и ни о чём не спрашивает — так зовёт меню правого клика по карточке.
    #>
    param([object[]]$Accounts)

    $targets = if (@($Accounts).Count -gt 0) { @($Accounts) }
               else { @(Get-RamActionTargets -What 'игру') }
    if ($targets.Count -eq 0) { return }

    # Отдельный пункт для снятия игры. Раньше игру снимал пустой ввод — и
    # человек, нажавший OK не глядя, молча терял игру у всех отмеченных.
    $suggestions = @([pscustomobject]@{ Text = '— убрать игру, открывать просто Roblox —'; Value = 'CLEAR' })
    $suggestions += @(Get-RamGameSuggestions)

    $val = Show-RamInputDialog -Title 'Игра для отмеченных' `
             -Prompt 'Ссылка на игру, ссылка «Поделиться» (share?code=...), приглашение на приватный сервер или просто ID. Можно выбрать из сохранённых.' `
             -Value '' -Suggestions $suggestions
    if ($null -eq $val) { return }

    # Пусто — значит человек передумал. Ничего не трогаем.
    if ([string]::IsNullOrWhiteSpace($val)) {
        Write-RamLog 'Игра не менялась — поле осталось пустым.' 'info'
        return
    }

    if ($val.Trim() -eq 'CLEAR') {
        if (-not (Confirm-Ram "Убрать игру у отмеченных аккаунтов (их $($targets.Count))?`n`nОни будут просто открывать Roblox, а игру ты выберешь сам уже в клиенте.")) { return }
        Push-RamUndo -Label 'снятие игры'
        foreach ($a in $targets) { $a.PlaceId = ''; $a.GameName = ''; $a.LinkCode = '' }
        Save-RamState
        Build-RamCards
        Write-RamLog "Игра снята у аккаунтов ($($targets.Count)) — Roblox будет просто открываться." 'ok'
        return
    }

    $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $g = $null
    try   { $g = Resolve-RamGameInput -Value $val }
    catch { Show-RamError $_.Exception.Message }
    finally { $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::Default }
    if ($null -eq $g) { return }

    if (-not $g.PlaceId) {
        Show-RamError 'Не понял, что это за игра. Вставь ссылку на игру, ссылку «Поделиться» или ID числом.'
        return
    }

    Push-RamUndo -Label 'назначение игры'
    foreach ($a in $targets) {
        $a.PlaceId  = $g.PlaceId
        $a.GameName = $g.GameName
        $a.LinkCode = $g.LinkCode
    }
    Save-RamState
    Build-RamCards

    $what = if ($g.GameName) { $g.GameName } else { "ID $($g.PlaceId)" }
    Add-RamSavedGame -PlaceId $g.PlaceId -LinkCode $g.LinkCode -Title $what
    if ($g.LinkCode) { $what += ' (приватный сервер)' }
    Write-RamLog "«$what» назначена аккаунтам: $($targets.Count)." 'ok'

    # Почти всегда игру назначают, чтобы тут же в неё и зайти. Спрашиваем,
    # а не запускаем молча: назначение бывает и «на потом».
    $ask = if ($targets.Count -eq 1) { "Запустить «$($targets[0].Alias)» прямо сейчас?" }
           else { "Запустить эти аккаунты ($($targets.Count)) прямо сейчас?" }
    if (Confirm-Ram "Игра «$what» назначена.`n`n$ask" 'Запустить?') {
        Add-RamToLaunchQueue -Accounts $targets
    }
}

function Invoke-RamAssignGroup {
    <# Собрать отмеченные аккаунты в набор. Пустое имя убирает из набора. #>
    $targets = @(Get-RamActionTargets -What 'набор')
    if ($targets.Count -eq 0) { return }

    $sug = @([pscustomobject]@{ Text = '— убрать из набора —'; Value = 'CLEAR' })
    foreach ($g in Get-RamGroups) { $sug += [pscustomobject]@{ Text = $g; Value = $g } }

    $name = Show-RamInputDialog -Title 'Набор для отмеченных' `
              -Prompt 'Название набора — например Фарм или Торговля. Набором можно запускать все аккаунты сразу и фильтровать список.' `
              -Value '' -Suggestions $sug
    if ($null -eq $name) { return }

    $name = $name.Trim()

    # Пусто — передумал. Убрать из набора можно отдельным пунктом списка.
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-RamLog 'Набор не менялся — поле осталось пустым.' 'info'
        return
    }
    if ($name -eq 'CLEAR') {
        if (-not (Confirm-Ram "Убрать отмеченные аккаунты (их $($targets.Count)) из наборов?")) { return }
        Push-RamUndo -Label 'снятие набора'
        foreach ($a in $targets) { $a.Group = '' }
        Save-RamState
        Build-RamCards
        Write-RamLog "Аккаунты ($($targets.Count)) убраны из набора." 'ok'
        return
    }
    Push-RamUndo -Label 'смена набора'
    foreach ($a in $targets) { $a.Group = $name }
    Save-RamState
    Build-RamCards
    Write-RamLog "Набор «$name»: аккаунтов $($targets.Count)." 'ok'
}

function Invoke-RamAssignColor {
    <# Цветная метка для отмеченных. #>
    $targets = @(Get-RamActionTargets -What 'метку')
    if ($targets.Count -eq 0) { return }

    $sug = @()
    foreach ($c in Get-RamLabelColors) { $sug += [pscustomobject]@{ Text = $c.Text; Value = $c.Key } }

    $val = Show-RamInputDialog -Title 'Цветная метка' `
             -Prompt 'Выбери цвет из списка. Метка рисуется полоской слева на карточке — удобно различать фармеров, торговых и основной.' `
             -Value '' -Suggestions $sug
    if ($null -eq $val) { return }

    $key = $val.Trim().ToLower()
    $known = (Get-RamLabelColors | ForEach-Object { $_.Key })
    if ($known -notcontains $key) { $key = '' }

    Push-RamUndo -Label 'смена метки'
    foreach ($a in $targets) { $a.Color = $key }
    Save-RamState
    Build-RamCards
    Write-RamLog "Метка обновлена у аккаунтов: $($targets.Count)." 'ok'
}

function Invoke-RamRepairCookie {
    <#
      Чинит мёртвый вход: смотрит, под кем сейчас сидит приложение Roblox,
      и если это тот же аккаунт — забирает свежую куку.

      Возвращает $true, если починили.
    #>
    param([Parameter(Mandatory)]$Account, [switch]$Quiet)

    $cookie = $null
    try { $cookie = Import-RamCurrentAccountCookie } catch { }
    if ([string]::IsNullOrWhiteSpace($cookie)) {
        if (-not $Quiet) {
            Show-RamInfo "Чтобы починить вход «$($Account.Alias)», войди под ним в приложении Roblox и нажми «Куки» ещё раз."
        }
        return $false
    }

    $who = $null
    try { $who = Get-RamAuthenticatedUser -Cookie $cookie } catch { }
    if ($null -eq $who) { return $false }

    if ([int64]$who.Id -ne [int64]$Account.UserId) {
        if (-not $Quiet) {
            Show-RamInfo ("В приложении Roblox сейчас «$($who.Name)», а чинить надо «$($Account.Alias)».`n`n" +
                          'Войди в приложении под нужным аккаунтом и нажми «Куки» ещё раз. ' +
                          'Для смены аккаунта пользуйся кнопкой «Сменить аккаунт (безопасно)» в мастере — ' +
                          'кнопка «Выйти» в самом Roblox убивает вход на сервере.')
        }
        return $false
    }

    $Account.Cookie   = $cookie
    $Account.Username = $who.Name
    Save-RamState
    Write-RamLog "'$($Account.Alias)': вход восстановлен из приложения Roblox." 'ok'
    return $true
}

function Invoke-RamStartupCookieCheck {
    <#
      Тихая проверка входов при открытии менеджера.

      Смысл простой: узнать о мёртвой куке ДО того, как нажмёшь «Запустить»
      и половина окон не откроется. Что можно — чинит само из приложения
      Roblox, ничего не спрашивая.
    #>
    if (-not $script:Settings.CheckOnStart) { return }
    if (@($script:Accounts).Count -eq 0) { return }

    $ok = 0; $bad = 0; $fixed = 0
    foreach ($a in $script:Accounts) {
        if ([string]::IsNullOrWhiteSpace($a.Cookie)) { $bad++; continue }

        $alive = $false
        try {
            $u = Get-RamAuthenticatedUser -Cookie $a.Cookie
            $a.Username = $u.Name; $a.UserId = $u.Id
            $alive = $true
        } catch { }

        if (-not $alive) {
            # Молчком пробуем поднять свежий вход из приложения Roblox.
            if (Invoke-RamRepairCookie -Account $a -Quiet) {
                try {
                    $u = Get-RamAuthenticatedUser -Cookie $a.Cookie
                    $a.Username = $u.Name; $a.UserId = $u.Id
                    $alive = $true; $fixed++
                } catch { }
            }
        }

        $a.CookieOk        = $(if ($alive) { 'yes' } else { 'no' })
        $a.CookieCheckedAt = (Get-Date).ToString('s')
        if ($alive) { $ok++ } else { $bad++ }
    }

    Save-RamState
    Build-RamCards

    if ($bad -eq 0) {
        Write-RamLog "Входы проверены: живы все $ok." 'ok'
    } else {
        $note = if ($fixed -gt 0) { " Починено из приложения: $fixed." } else { '' }
        Write-RamLog "Входы проверены: живых $ok, мёртвых $bad.$note Мёртвые не запустятся — открой мастер и добавь их заново." 'warn'
    }
}

function Invoke-RamCheckCookies {
    <# Проверить, живы ли входы. #>
    $targets = @(Get-RamTargetAccounts)
    if ($targets.Count -eq 0) { $targets = @(Get-RamVisibleAccounts) }
    if ($targets.Count -eq 0) { Show-RamInfo 'Аккаунтов пока нет.'; return }

    $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $ok = 0; $bad = 0
    $dead = @()
    try {
        foreach ($a in $targets) {
            if ([string]::IsNullOrWhiteSpace($a.Cookie)) {
                Write-RamLog "'$($a.Alias)': куки нет." 'warn'; $bad++; continue
            }
            try {
                $u = Get-RamAuthenticatedUser -Cookie $a.Cookie
                $a.Username = $u.Name; $a.UserId = $u.Id

                # Заодно обновляем справку: Robux, Premium, дата регистрации.
                $inf = Get-RamAccountInfo -Cookie $a.Cookie -UserId $u.Id
                if ($inf.Robux -ge 0) { $a.Robux = $inf.Robux }
                if ($inf.Premium)     { $a.Premium = $inf.Premium }
                if ($inf.Created)     { $a.Created = $inf.Created }

                $a.CookieOk        = 'yes'
                $a.CookieCheckedAt = (Get-Date).ToString('s')

                $extra = ''
                if ($a.Robux -ge 0) { $extra = ", $($a.Robux) Robux" }
                Write-RamLog "'$($a.Alias)': вход живой — $($u.Name)$extra" 'ok'
                $ok++
            } catch {
                $a.CookieOk        = 'no'
                $a.CookieCheckedAt = (Get-Date).ToString('s')
                Write-RamLog "'$($a.Alias)': $($_.Exception.Message)" 'err'
                $bad++
                $dead += $a
            }
        }
        Save-RamState
        Build-RamCards
    } finally {
        $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
    Write-RamLog "Проверено: живых $ok, мёртвых $bad." $(if ($bad -eq 0) { 'ok' } else { 'warn' })

    # Мёртвый вход часто чинится сам: если сейчас в приложении Roblox сидит
    # именно этот аккаунт, свежая кука лежит прямо там.
    if ($dead.Count -gt 0) {
        $names = ($dead | ForEach-Object { $_.Alias }) -join ', '
        if (Confirm-Ram ("Мёртвые входы: $names.`n`nПопробовать починить их из приложения Roblox? " +
                         'Починится тот аккаунт, под которым ты сейчас вошёл в приложении.')) {
            $fixed = 0
            foreach ($a in $dead) {
                if (Invoke-RamRepairCookie -Account $a -Quiet) { $fixed++ }
            }
            if ($fixed -gt 0) {
                Build-RamCards
                Show-RamInfo "Починено входов: $fixed.`n`nОстальные — войди под ними в приложении Roblox по очереди и нажимай «Куки»."
            } else {
                Show-RamInfo ("Починить не вышло: в приложении Roblox сейчас другой аккаунт.`n`n" +
                              'Войди под нужным и нажми «Куки» ещё раз. Для смены пользуйся кнопкой ' +
                              '«Сменить аккаунт (безопасно)» в мастере, а не «Выйти» в самом Roblox.')
            }
        }
    }
}

function Invoke-RamStopSelected {
    <# Закрыть окна отмеченных аккаунтов. #>
    $targets = @(Get-RamTargetAccounts)
    if ($targets.Count -eq 0) { $targets = @($script:Accounts) }
    $n = 0
    foreach ($a in $targets) {
        $inst = $script:Instances[$a.Id]
        if ($null -eq $inst) { continue }
        # Закрытие руками — не вылет, счётчик вылетов не трогаем.
        $inst | Add-Member -NotePropertyName ClosedByUser -NotePropertyValue $true -Force
        if (Stop-RamRobloxInstance -ProcessId $inst.ProcessId) { $n++ }
    }
    Write-RamLog "Закрыто клиентов: $n." 'ok'
    Update-RamCardStates
}

function Save-RamWindowPositions {
    <#
      Запоминает, где сейчас стоят окна запущенных аккаунтов. Дальше при
      каждом запуске окно будет вставать туда же — если в Настройках включено
      «ставить окна на запомненные места».
    #>
    $saved = 0
    foreach ($a in $script:Accounts) {
        $inst = $script:Instances[$a.Id]
        if ($null -eq $inst -or $inst.Handle -eq [IntPtr]::Zero) { continue }

        $r = Get-RamWindowRect -Handle $inst.Handle
        if ($null -eq $r) { continue }
        if ($r.Width -lt 200 -or $r.Height -lt 150) { continue }

        $a.WindowX = $r.X; $a.WindowY = $r.Y
        $a.WindowW = $r.Width; $a.WindowH = $r.Height
        $saved++
    }

    if ($saved -eq 0) {
        Show-RamInfo 'Нечего запоминать: сейчас нет запущенных окон.'
        return
    }
    Save-RamState
    Build-RamCards
    Write-RamLog "Места окон запомнены: $saved шт. Дальше окна будут вставать туда же." 'ok'
}

function Invoke-RamFocusAccountByIndex {
    <# Ctrl+1..9: вывести наверх окно N-го аккаунта из видимого списка. #>
    param([int]$Index)

    $list = @(Get-RamVisibleAccounts)
    if ($Index -lt 1 -or $Index -gt $list.Count) { return }

    $a = $list[$Index - 1]
    $inst = $script:Instances[$a.Id]
    if ($null -eq $inst -or $inst.Handle -eq [IntPtr]::Zero) {
        Write-RamLog "Ctrl+${Index}: «$($a.Alias)» сейчас не запущен." 'warn'
        return
    }
    [void](Set-RamWindowForeground -Handle $inst.Handle)
}

function Get-RamProfiles {
    return @($script:Settings.Profiles | Where-Object { $null -ne $_ -and $_.Name })
}

function Invoke-RamRunProfile {
    <#
      Профиль — сохранённая связка «набор + игра». Одной кнопкой ставит игру
      всем аккаунтам набора и запускает их.
    #>
    param([Parameter(Mandatory)]$Profile)

    # Порядок разбора: поимённый список -> набор -> все.
    # Список важнее набора: его сохраняли ровно из тех аккаунтов, что были
    # отмечены, и подменять их «всеми» нельзя.
    $ids = @()
    if ($Profile.PSObject.Properties.Name -contains 'Ids') { $ids = @($Profile.Ids | Where-Object { $_ }) }

    if ($ids.Count -gt 0) {
        $targets = @(Get-RamOrderedAccounts | Where-Object { $ids -contains [string]$_.Id })
        if ($targets.Count -eq 0) {
            Show-RamInfo "В профиле «$($Profile.Name)» записаны аккаунты, которых больше нет в списке. Пересохрани профиль."
            return
        }
    } elseif ([string]::IsNullOrWhiteSpace([string]$Profile.Group)) {
        $targets = @(Get-RamOrderedAccounts)
    } else {
        $targets = @($script:Accounts | Where-Object { [string]$_.Group -eq [string]$Profile.Group })
    }

    if ($targets.Count -eq 0) {
        Show-RamInfo "В профиле «$($Profile.Name)» набор «$($Profile.Group)» пуст — некого запускать."
        return
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Profile.PlaceId)) {
        foreach ($a in $targets) {
            $a.PlaceId  = [string]$Profile.PlaceId
            if ([string]$Profile.GameName) { $a.GameName = [string]$Profile.GameName }
            $a.LinkCode = [string]$Profile.LinkCode
        }
        Save-RamState
        Build-RamCards
    }

    Write-RamLog "Профиль «$($Profile.Name)»: запускаю $($targets.Count) аккаунтов." 'ok'
    Add-RamToLaunchQueue -Accounts $targets
}

function Invoke-RamSaveProfile {
    <# Сохраняет текущее состояние выбранного набора как профиль. #>
    $targets = @(Get-RamActionTargets -What 'сохранение в профиль')
    if ($targets.Count -eq 0) { return }

    $name = Show-RamInputDialog -Title 'Новый профиль запуска' `
              -Prompt 'Название профиля — например «Фарм в Elemental Dungeons». Профиль запомнит набор и игру отмеченных аккаунтов и будет запускать их одной кнопкой.'
    if ([string]::IsNullOrWhiteSpace($name)) { return }

    $first = $targets[0]

    # Набор запоминаем только если он у ВСЕХ отмеченных один и тот же.
    # Иначе — сохраняем поимённый список: раньше в этом случае в профиль
    # уходил пустой набор, а пустой набор означает «все аккаунты», и профиль
    # поднимал в том числе те, которые не отмечали.
    $groups = @($targets | ForEach-Object { [string]$_.Group } | Sort-Object -Unique)
    $sharedGroup = if ($groups.Count -eq 1 -and $groups[0]) { $groups[0] } else { '' }

    $entry = [pscustomobject]@{
        Name     = $name.Trim()
        Group    = $sharedGroup
        Ids      = @($targets | ForEach-Object { [string]$_.Id })
        PlaceId  = [string]$first.PlaceId
        GameName = [string]$first.GameName
        LinkCode = [string]$first.LinkCode
    }

    $rest = @(Get-RamProfiles | Where-Object { $_.Name -ne $entry.Name })
    $script:Settings.Profiles = @(@($entry) + $rest | Select-Object -First 20)
    Save-RamSettings -Settings $script:Settings
    Update-RamProfilesPanel
    Write-RamLog "Профиль «$($entry.Name)» сохранён." 'ok'
}

function Invoke-RamWatchCheck {
    <#
      Режим «следить и поднимать»: аккаунты выбранного набора должны быть
      в игре. Кого нет — поднимаем.

      Проверяется тем же таймером, что и расписание, раз в полминуты.
    #>
    if ($null -eq $script:Settings) { return }
    $group = [string]$script:Settings.WatchGroup
    if ([string]::IsNullOrWhiteSpace($group)) { return }

    $targets = @($script:Accounts | Where-Object { [string]$_.Group -eq $group })
    if ($targets.Count -eq 0) { return }

    $missing = @()
    foreach ($a in $targets) {
        if ($script:Instances.ContainsKey($a.Id)) { continue }
        if ($script:LaunchQueue -contains $a.Id)  { continue }
        $missing += $a
    }
    if ($missing.Count -eq 0) { return }

    Write-RamLog "Присмотр за набором «$group»: не в игре $($missing.Count), поднимаю." 'warn'
    Add-RamToLaunchQueue -Accounts $missing
}
function Invoke-RamRelogin {
    <#
      Войти заново в конкретный аккаунт — то, что нужно, когда вход умер.

      ЧЕСТНО О ГЛАВНОМ. Продлить .ROBLOSECURITY снаружи невозможно: ни один
      запрос к Roblox не присылает свежую куку, это проверено опытом и лежит
      рядом отдельным скриптом «Проверка входов.ps1». Поэтому «починить» вход
      можно ровно одним способом — войти ещё раз. Здесь это делается в один
      клик и без потерь: свежая кука встаёт на место старой, а игра, набор,
      метка, заметка и место в списке остаются прежними, потому что аккаунт
      узнаётся по UserId и обновляется, а не создаётся заново.
    #>
    param([Parameter(Mandatory)][string]$Id)

    $acc = Get-RamAccountById -Id $Id
    if ($null -eq $acc) { return }

    $ways = @()
    $ways += 'Открыть окно браузера и войти руками'
    if ([bool]$script:Settings.BridgeEnabled) {
        $ways += "Или: открой roblox.com в своём браузере под «$($acc.Alias)» и нажми $($script:Settings.BridgeHotkey)"
    }

    $msg = "Вход в «$($acc.Alias)» умер." + [Environment]::NewLine + [Environment]::NewLine +
           'Продлить его нечем — Roblox не отдаёт новую куку ни на один запрос, это проверено. Нужно войти заново.' +
           [Environment]::NewLine + [Environment]::NewLine + ($ways -join ([Environment]::NewLine)) +
           [Environment]::NewLine + [Environment]::NewLine + 'Открыть окно браузера сейчас?'

    if (-not (Confirm-Ram $msg)) { return }

    $cookie = $null
    try {
        $cookie = Show-RamExternalBrowserLoginWindow
    } catch {
        Write-RamLog "Повторный вход: $($_.Exception.Message)" 'err'
        Show-RamError -Text ('Не удалось открыть окно входа:' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message)
        return
    }
    if (-not $cookie) {
        Write-RamLog 'Повторный вход: окно закрыто без входа.' 'warn'
        return
    }

    $r = Import-RamAccountLine -Line $cookie
    if ($null -eq $r -or -not $r.Ok) {
        $why = if ($r -and $r.Error) { $r.Error } else { 'Roblox не подтвердил вход' }
        Show-RamError -Text ('Вход не подошёл:' + [Environment]::NewLine + [Environment]::NewLine + $why)
        return
    }

    Save-RamState
    Build-RamCards
    if ($r.Alias -eq $acc.Alias) {
        Write-RamLog "Вход в «$($acc.Alias)» обновлён." 'ok'
        Show-RamMessage -Message "Готово: вход в «$($acc.Alias)» снова живой."
    } else {
        # Вошли под другим аккаунтом — не молчим об этом: старый как был
        # мёртвым, так и остался, а в списке появился ещё один.
        Write-RamLog "Ожидался «$($acc.Alias)», а вошли под «$($r.Alias)» — добавлен отдельным аккаунтом." 'warn'
        Show-RamMessage -Message ("Вошли под «$($r.Alias)», а не под «$($acc.Alias)»." + [Environment]::NewLine + [Environment]::NewLine +
                                  "Он добавлен в список, но вход в «$($acc.Alias)» так и остался мёртвым.")
    }
}
