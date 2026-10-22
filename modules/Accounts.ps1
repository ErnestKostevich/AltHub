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
    param([object[]]$Accounts = $script:Accounts)
    $copy = @()
    foreach ($src in $Accounts) {
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
    param([Parameter(Mandatory)][string]$Label, [switch]$IncludeLayout)

    [void]$script:UndoStack.Add([pscustomobject]@{
        Label    = $Label
        Accounts = Copy-RamAccounts
        Layout = $(if ($IncludeLayout) { [pscustomobject]@{ TileMode=$script:Settings.TileMode; TileColumns=$script:Settings.TileColumns; AutoTile=$script:Settings.AutoTile; UseSavedWindows=$script:Settings.UseSavedWindows; MainAccountId=$script:Settings.MainAccountId } } else { $null })
        At       = Get-Date
    })
    while ($script:UndoStack.Count -gt 10) { $script:UndoStack.RemoveAt(0) }
}

function Invoke-RamUndo {
    <# Ctrl+Z: вернуть аккаунты в состояние до последнего действия. #>
    if ($script:UndoStack.Count -eq 0) {
        Set-RamStatus (Get-RamText -Text 'Отменять нечего — с открытия программы список не менялся.')
        return
    }

    $last = $script:UndoStack[$script:UndoStack.Count - 1]
    $script:UndoStack.RemoveAt($script:UndoStack.Count - 1)

    $script:Accounts = @($last.Accounts)
    if ($last.PSObject.Properties.Name -contains 'Layout' -and $null -ne $last.Layout) {
        foreach ($field in @('TileMode','TileColumns','AutoTile','UseSavedWindows','MainAccountId')) { $script:Settings.$field = $last.Layout.$field }
    }
    Save-RamState
    Build-RamCards
    Write-RamLog (Get-RamText -Text 'Отменено: {0}.' -Arguments @([string]($($last.Label)))) 'ok'
    Set-RamStatus (Get-RamText -Text 'Отменено: {0}.' -Arguments @([string]($($last.Label))))
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
    if ($script:AccountsWriteBlocked) {
        Write-RamLog (Get-RamText -Text 'Сохранение аккаунтов заблокировано: исходное хранилище не было успешно прочитано.') 'err'
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
        Show-RamError (Get-RamText -Text 'Не удалось сохранить список аккаунтов:

{0}' -Arguments @([string]((Get-RamErrorText -Text ($($_.Exception.Message))))))
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
        if ($line.Length -lt 50) { return @{ Ok = $false; New = $false; Alias = ''; Error = (Get-RamText -Text 'строка слишком короткая для куки') } }
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
    Write-RamLog (Get-RamText -Text '''{0}'': Roblox обновил вход, сохранил свежий.' -Arguments @([string]($($hit.Alias)))) 'ok'
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

    # ПРОВЕРКА ВХОДА — БЕЗ ЗАМОРОЗКИ ОКНА. Раньше здесь стоял синхронный
    # запрос к Roblox прямо в такте таймера: пока Roblox отвечал (до 25 секунд
    # на плохой сети), окно не рисовалось и не отвечало. Теперь такт только
    # ЗАПУСКАЕТ проверку и сразу отпускает окно, а ответ забирает следующий такт.
    if ($null -ne $script:AppWatchJob) {
        if (-not $script:AppWatchJob.Job.Task.IsCompleted) { return }
        $pending = $script:AppWatchJob
        $script:AppWatchJob = $null
        $check = Complete-RamAuthCheckAsync -Job $pending.Job
        if ($check.State -ne 'valid' -or $null -eq $check.User -or -not $check.User.Name) { return }
        # Пока ждали ответа, этот вход могли уже добавить.
        foreach ($a in @($script:Accounts)) {
            if ($null -ne $a -and $a.Cookie -eq $pending.Cookie) { $script:AppOffer = $null; return }
        }
        # [int64], а НЕ [int]: номера аккаунтов Roblox давно перевалили за два
        # миллиарда, и 4062608487 в Int32 не влезает.
        $script:AppOffer = [pscustomobject]@{ Cookie = $pending.Cookie; Name = [string]$check.User.Name; UserId = [int64]$check.User.Id }
        Set-RamStatus (Get-RamText -Text 'В приложении Roblox сейчас «{0}» — нажми сюда, чтобы добавить его в менеджер' -Arguments @([string]($($check.User.Name))))
        Write-RamLog (Get-RamText -Text 'В приложении Roblox замечен «{0}» — его можно добавить одним кликом по строке внизу.' -Arguments @([string]($($check.User.Name)))) 'info'
        return
    }

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

    try {
        $script:AppWatchJob = [pscustomobject]@{ Job = (Start-RamAuthCheckAsync -Cookie $cookie); Cookie = $cookie }
    } catch {
        $script:AppWatchJob = $null
    }
}

function Invoke-RamAppOffer {
    <# Клик по строке состояния, когда там висит предложение добавить аккаунт. #>
    $offer = $script:AppOffer
    if ($null -eq $offer) { return }

    foreach ($a in @($script:Accounts)) {
        if ($null -ne $a -and $a.Cookie -eq $offer.Cookie) { $script:AppOffer = $null; return }
    }

    if (-not (Confirm-Ram (Get-RamText -Text 'Добавить аккаунт «{0}» в менеджер?

Вход берётся из приложения Roblox, пароль не нужен.' -Arguments @([string]($($offer.Name)))))) {
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
            Set-RamStatus (Get-RamText -Text 'Добавлен «{0}»' -Arguments @([string]($($r.User.Name))))
            Write-RamLog (Get-RamText -Text 'Добавлен аккаунт «{0}» из приложения Roblox.' -Arguments @([string]($($r.User.Name)))) 'ok'
        } else {
            Set-RamStatus (Get-RamText -Text 'Вход «{0}» обновлён' -Arguments @([string]($($r.User.Name))))
            Write-RamLog (Get-RamText -Text 'Обновлён вход аккаунта «{0}» из приложения Roblox.' -Arguments @([string]($($r.User.Name)))) 'ok'
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
        Show-RamInfo (Get-RamText -Text 'Все входы живые — чинить нечего.')
        return
    }

    Write-RamLog (Get-RamText -Text 'Починка входов: мёртвых {0}.' -Arguments @([string]($($dead.Count)))) 'info'

    $fixed = 0; $skipped = 0; $stopped = $false

    foreach ($acc in $dead) {
        if (Invoke-RamRepairCookie -Account $acc -Quiet) {
            Set-RamCookieAlive -Account $acc
            $fixed++
            Write-RamLog (Get-RamText -Text '''{0}'': вход подхватился из приложения сам.' -Arguments @([string]($($acc.Alias)))) 'ok'
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
            $msg  = (Get-RamText -Text 'Аккаунт «{0}» — вход мёртв, его надо взять заново.

' -Arguments @([string]($($acc.Alias)))) +
                    (Get-RamText -Text 'Способ первый, быстрее для твинков: нажми «Окно браузера» — откроется ') +
                    (Get-RamText -Text 'настоящий Chrome, войдёшь в «{0}» руками, и вход встанет на место.

' -Arguments @([string]($($acc.Alias)))) +
                    (Get-RamText -Text 'Способ второй, через приложение: открой Roblox под «{0}» и нажми ' -Arguments @([string]($($acc.Alias)))) +
                    (Get-RamText -Text '«Забрать вход». Если в приложении сейчас другой аккаунт — «Сменить аккаунт»: ') +
                    (Get-RamText -Text 'Roblox закроется и забудет вход, а на сервере он останется живым. ') +
                    (Get-RamText -Text 'Кнопку «Выйти» внутри Roblox не трогай, она убивает вход насовсем.

') +
                    (Get-RamText -Text 'Осталось починить: {0}' -Arguments @([string]($left)))

            $ans = Show-RamMessage -Message $msg -Title (Get-RamText -Text 'Починка входов') -Kind 'warn' -Buttons @(
                @{ Text = (Get-RamText -Text 'Окно браузера');   Value = 'window'; Kind = 'primary' },
                @{ Text = (Get-RamText -Text 'Забрать вход');    Value = 'take'   },
                @{ Text = (Get-RamText -Text 'Сменить аккаунт'); Value = 'switch' },
                @{ Text = (Get-RamText -Text 'Пропустить');      Value = 'skip'   },
                @{ Text = (Get-RamText -Text 'Хватит');          Value = 'stop'   }
            )

            switch ([string]$ans) {
                'window' {
                    $cookie = $null
                    try { $cookie = Show-RamExternalBrowserLoginWindow }
                    catch {
                        Write-RamLog (Get-RamText -Text 'Починка входов: {0}' -Arguments @([string]((Get-RamErrorText -Text ($($_.Exception.Message)))))) 'err'
                        Show-RamError -Text ((Get-RamText -Text 'Не удалось открыть окно входа:') + [Environment]::NewLine +
                                             [Environment]::NewLine + $_.Exception.Message)
                    }
                    if ($cookie) {
                        $r = Import-RamAccountLine -Line $cookie
                        if ($r -and $r.Ok) {
                            if ($r.Alias -eq $acc.Alias) {
                                $fixed++
                                $done = $true
                                Write-RamLog (Get-RamText -Text '''{0}'': вход обновлён через окно браузера.' -Arguments @([string]($($acc.Alias)))) 'ok'
                            } else {
                                # Вошли не под тем — говорим прямо, а не молча
                                # засчитываем починку.
                                Write-RamLog (Get-RamText -Text 'Ожидался «{0}», вошли под «{1}».' -Arguments @([string]($($acc.Alias)),[string]($($r.Alias)))) 'warn'
                                Show-RamInfo ((Get-RamText -Text 'Вошли под «{0}», а не под «{1}».' -Arguments @([string]($($r.Alias)),[string]($($acc.Alias)))) + [Environment]::NewLine +
                                              [Environment]::NewLine + (Get-RamText -Text 'Он добавлен в список, но вход в «{0}» остался мёртвым.' -Arguments @([string]($($acc.Alias)))))
                            }
                        } else {
                            $why = if ($r -and $r.Error) { $r.Error } else { (Get-RamText -Text 'Roblox не подтвердил вход') }
                            Show-RamError -Text ((Get-RamText -Text 'Вход не подошёл:') + [Environment]::NewLine + [Environment]::NewLine + $why)
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
        $tail = if ($stopped) { (Get-RamText -Text ' Остальные оставили как есть.') } else { '' }
        Write-RamLog (Get-RamText -Text 'Починка входов: восстановлено {0} из {1}.' -Arguments @([string]($fixed),[string]($($dead.Count)))) 'ok'
        Show-RamInfo (Get-RamText -Text 'Починено входов: {0} из {1}.{2}' -Arguments @([string]($fixed),[string]($($dead.Count)),[string]($tail)))
    } else {
        Write-RamLog (Get-RamText -Text 'Починка входов: ничего не восстановлено.') 'warn'
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
    param([string]$What = (Get-RamText -Text 'это действие'))

    $checked = @(Get-RamTargetAccounts)
    if ($checked.Count -gt 0) {
        if (Confirm-RamHiddenSelection -Accounts $checked -What $What) { return $checked }
        return @()
    }

    $visible = @(Get-RamVisibleAccounts)
    if ($visible.Count -eq 0) {
        Show-RamInfo (Get-RamText -Text 'Список пуст — некого выбирать.')
        return @()
    }

    $where = if ($script:GroupFilter) { (Get-RamText -Text ' из набора «{0}»' -Arguments @([string]($($script:GroupFilter)))) }
             elseif ($script:Filter)  { (Get-RamText -Text ' из найденных') }
             else { '' }

    if (Confirm-Ram ((Get-RamText -Text 'Галочки не стоят.

Применить {0} ко всем показанным аккаунтам{1} (их {2})?' -Arguments @([string]($What),[string]($where),[string]($($visible.Count)))))) {
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

function Get-RamHiddenSelectionCount {
    param([object[]]$Accounts = @(Get-RamTargetAccounts))
    $visibleIds = @{}
    foreach ($a in @(Get-RamVisibleAccounts)) { $visibleIds[[string]$a.Id] = $true }
    return @($Accounts | Where-Object { -not $visibleIds.ContainsKey([string]$_.Id) }).Count
}

function Confirm-RamHiddenSelection {
    param([object[]]$Accounts, [string]$What = (Get-RamText -Text 'это действие'))
    $hidden = Get-RamHiddenSelectionCount -Accounts $Accounts
    if ($hidden -eq 0) { return $true }
    return (Confirm-Ram (Get-RamText -Text 'Отмечено аккаунтов: {0}. Из них скрыто текущим набором или поиском: {1}.

Применить «{2}» ко всем отмеченным, включая скрытые? Отмена ничего не изменит.' -Arguments @($Accounts.Count, $hidden, $What)))
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
        if ($script:CheckedIds.ContainsKey([string]$a.Id)) { $res += $a }
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
            UiLanguage     = $script:Settings.UiLanguage
            BrowserLoginBrowser = $script:Settings.BrowserLoginBrowser
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
        foreach ($k in @('LaunchDelaySec','Locale','UiLanguage','BrowserLoginBrowser','Theme','TileMode','TileColumns',
                         'RenameWindows','AutoTile','AutoRestart')) {
            if ($obj.settings.PSObject.Properties.Name -contains $k) {
                if($k -eq 'UiLanguage' -and $obj.settings.$k -notin @('ru','en')){continue}
                if($k -eq 'BrowserLoginBrowser' -and $obj.settings.$k -notin @('system','cft')){continue}
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
        Show-RamInfo (Get-RamText -Text 'Отметь галочками, кого убрать. Для удаления AltHub нарочно не берёт всех подряд.')
        return
    }

    $names = ($targets | ForEach-Object { $_.Alias }) -join ', '
    if (-not (Confirm-Ram (Get-RamText -Text 'Убрать из менеджера: {0} ?

Сами аккаунты Roblox не пострадают — сотрутся только сохранённые здесь данные.' -Arguments @([string]($names))))) { return }

    Push-RamUndo -Label (Get-RamText -Text 'удаление аккаунтов ({0})' -Arguments @([string]($($targets.Count))))
    $ids = $targets | ForEach-Object { $_.Id }
    $script:Accounts = @($script:Accounts | Where-Object { $ids -notcontains $_.Id })
    foreach ($id in $ids) { [void]$script:CheckedIds.Remove([string]$id) }
    Save-RamState
    Build-RamCards
    Write-RamLog (Get-RamText -Text 'Удалено аккаунтов: {0}.' -Arguments @([string]($($targets.Count)))) 'ok'
}

function Set-RamAllChecked {
    param([bool]$Checked)
    foreach ($id in $script:Cards.Keys) {
        if ($Checked) { $script:CheckedIds[[string]$id] = $true }
        else { [void]$script:CheckedIds.Remove([string]$id) }
        $script:Cards[$id].Check.Tag.Checked = $Checked
        $script:Cards[$id].Check.Invalidate()
    }
    Update-RamStatusLine
}

function Clear-RamCheckedAccounts {
    $script:CheckedIds.Clear()
    Set-RamAllChecked $false
}

function Invoke-RamLaunchSelected {
    $targets = @(Get-RamTargetAccounts)
    if ($targets.Count -eq 0) { $targets = @(Get-RamVisibleAccounts) }
    elseif (-not (Confirm-RamHiddenSelection -Accounts $targets -What (Get-RamText -Text 'Запустить'))) { return }
    if ($targets.Count -gt 0) { Add-RamToLaunchQueue -Accounts $targets }
}

# ----------------------------------------------------------- запуск ---------

function Add-RamToLaunchQueue {
    <#
      -Unattended — зов из таймера: расписание, присмотр за набором,
      автоперезапуск вылетевших. Модальных окон в этом режиме нет: окно,
      открытое ночью, ждёт человека до утра, а таймер, крутящий модальный
      цикл, успевает войти в очередь запуска второй раз. Всё, что обычно
      спрашивается, решается безопасно и пишется в журнал и нижнюю строку.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Accounts,
        [switch]$Unattended,
        [switch]$PassThru
    )

    if ($Accounts.Count -eq 0) {
        if ($Unattended) { Write-RamLog (Get-RamText -Text 'Запускать некого: список пуст.') 'warn'; return }
        Show-RamInfo (Get-RamText -Text 'Никто не отмечен. Поставь галочки слева у нужных аккаунтов.')
        return
    }

    $Accounts = @($Accounts | Where-Object {
        $null -ne $_ -and -not $script:Instances.ContainsKey([string]$_.Id) -and
        $script:LaunchQueue -notcontains [string]$_.Id -and
        (-not $Unattended -or -not $script:LaunchSuppressedIds.ContainsKey([string]$_.Id))
    })
    if ($Accounts.Count -eq 0) {
        if (-not $Unattended) { Set-RamStatus (Get-RamText -Text 'Новых аккаунтов для запуска нет: они уже работают или стоят в очереди.') }
        return
    }

    # Больше окон, чем вытягивает машина — предупреждаем один раз за запуск.
    # Не запрещаем: сколько тянет его компьютер, человек знает лучше нас.
    $willRun = $Accounts.Count + @($script:Instances.Keys).Count + $script:LaunchQueue.Count
    $canRun  = Get-RamRecommendedAccountCount
    if ($willRun -gt $canRun -and -not $script:WarnedAboutLoad -and $Unattended) {
        # Без человека не спрашиваем: сколько окон поднимать ночью, он решил сам,
        # когда настраивал расписание.
        $script:WarnedAboutLoad = $true
        Write-RamLog (Get-RamText -Text 'Запускаю {0} окон при рекомендованных {1} — так настроено расписание или присмотр.' -Arguments @([string]($willRun),[string]($canRun))) 'warn'
    }
    if ($willRun -gt $canRun -and -not $script:WarnedAboutLoad) {
        $script:WarnedAboutLoad = $true
        $hw = Get-RamHardware
        $ans = Show-RamMessage -Title (Get-RamText -Text 'Много окон сразу') -Kind 'warn' -Message (
            (Get-RamText -Text 'Собираешься держать открытыми {0} клиентов Roblox.

' -Arguments @([string]($willRun))) +
            "$(Get-RamHardwareSummary -Hardware $hw)`n`n" +
            (Get-RamText -Text 'На такой машине уверенно идут примерно {0}. Больше — начнёт подтормаживать всё, включая основной аккаунт.

' -Arguments @([string]($canRun))) +
            (Get-RamText -Text 'Помогает поставить твинкам набор «Фоновый фарм»: правый клик по карточке -> «Готовый набор настроек».')
        ) -Buttons @(
            @{ Text = (Get-RamText -Text 'Всё равно запустить'); Value = 'go'; Kind = 'primary' },
            @{ Text = (Get-RamText -Text 'Отмена');              Value = 'no' }
        )
        if ([string]$ans -ne 'go') {
            Write-RamLog (Get-RamText -Text 'Запуск отменён: просили {0} окон при рекомендованных {1}.' -Arguments @([string]($willRun),[string]($canRun))) 'info'
            return
        }
    }

    # ПЕРВЫЙ МУЛЬТИЗАПУСК — ОДИН РАЗ СКАЗАТЬ ЧЕСТНО, ЧЕМ ЭТО ГРОЗИТ.
    # Не пугать и не врать: несколько аккаунтов Roblox разрешает сам, а запуск
    # нескольких клиентов разом официально не поддерживает. Самый частый
    # сюрприз — телепорт между играми срабатывает только в последнем окне.
    if (-not $Unattended -and $willRun -ge 2 -and -not [bool]$script:Settings.MultiInstanceNoticeShown) {
        $ans = Show-RamMessage -Title (Get-RamText -Text 'Несколько окон Roblox сразу') -Kind 'info' -Message (
            (Get-RamText -Text 'Иметь несколько аккаунтов Roblox разрешает сам — переключатель до пяти аккаунтов есть прямо в клиенте. AltHub не меняет Roblox и не лезет в его память: он запускает официальный клиент и раскладывает окна.

') +
            (Get-RamText -Text 'А вот несколько клиентов на одном компьютере Roblox официально называет неподдерживаемым. Это может перестать работать после любого обновления Roblox.

') +
            (Get-RamText -Text 'Что уже известно: переход между играми (телепорт) часто срабатывает только в последнем запущенном окне.

') +
            (Get-RamText -Text 'Банят за поступки, а не за программу: за ботов, накрутку, обход наказаний. Письменного разрешения на менеджеры аккаунтов у Roblox тоже нет — решать тебе.')
        ) -Buttons @(
            @{ Text = (Get-RamText -Text 'Понятно, запускать'); Value = 'go'; Kind = 'primary' },
            @{ Text = (Get-RamText -Text 'Отмена');             Value = 'no' }
        )
        if ([string]$ans -ne 'go') {
            Write-RamLog (Get-RamText -Text 'Запуск отменён после предупреждения о мультизапуске.') 'info'
            return
        }
        $script:Settings.MultiInstanceNoticeShown = $true
        Save-RamSettingsNow
    }

    # Идёт обновление — запускать нельзя: установщик закроет всё, что успеет
    # открыться, и это будет выглядеть как поломка мультизапуска.
    if (Test-RamRobloxUpdating) {
        if ($Unattended) { Write-RamLog (Get-RamText -Text 'Запуск отложен: идёт обновление Roblox.') 'warn'; Set-RamStatus (Get-RamText -Text 'Запуск по расписанию пропущен: Roblox обновлялся.'); return }
        Show-RamInfo (Get-RamText -Text 'Roblox сейчас обновляется.

Подожди, пока обновление закончится, и запусти снова. Если запустить прямо сейчас, установщик закроет открытые окна.')
        Write-RamLog (Get-RamText -Text 'Запуск отменён: идёт обновление Roblox.') 'warn'
        return
    }

    # Путь пересчитываем каждый раз: Roblox мог обновиться прямо во время
    # работы менеджера, и старый путь стал бы устаревшим клиентом.
    try {
        $newPath = Get-RamRobloxPlayerPath
        if ($newPath -ne $script:PlayerPath) {
            $script:PlayerPath = $newPath
            $ver = (Get-RamRobloxClients | Select-Object -First 1).Version
            Write-RamLog (Get-RamText -Text 'Клиент Roblox: версия {0}' -Arguments @([string]($ver))) 'info'
        }
    } catch {
        if ($Unattended) { Write-RamLog (Get-RamText -Text 'Запуск не выполнен: {0}' -Arguments @([string]((Get-RamErrorText -Text ($($_.Exception.Message)))))) 'err'; return }
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
            if ($running.Count -gt 0 -and $Unattended) {
                # Закрывать окна Roblox без человека нельзя: там может идти игра.
                Write-RamLog (Get-RamText -Text 'Запуск не выполнен: Roblox был открыт до менеджера, мультизапуск не включился, а закрывать окна без человека AltHub не будет.') 'warn'
                Set-RamStatus (Get-RamText -Text 'Запуск по расписанию пропущен: сначала закрой открытые окна Roblox.')
                return
            }
            if ($running.Count -gt 0) {
                $ok = Confirm-Ram (
                    (Get-RamText -Text 'Мультизапуск не включится: Roblox уже был открыт до менеджера.

') +
                    (Get-RamText -Text 'Пока это так, каждый новый клиент будет закрывать предыдущий — ') +
                    (Get-RamText -Text 'и в итоге останется одно окно.

') +
                    (Get-RamText -Text 'Закрыть сейчас все окна Roblox (открыто: {0}) и включить мультизапуск?' -Arguments @([string]($($running.Count)))))
                if (-not $ok) {
                    Write-RamLog (Get-RamText -Text 'Запуск отменён: мультизапуск выключен, окна Roblox не закрыты.') 'warn'
                    return
                }
                foreach ($p in $running) { [void](Stop-RamRobloxInstance -ProcessId $p.Id) }
                $script:Instances.Clear()
                Start-Sleep -Milliseconds 2500

                $lock = Enable-RamMultiInstance
                if ($lock.EventBlocked) {
                    Write-RamLog (Get-RamText -Text 'Окна Roblox закрыты, мультизапуск включён.') 'ok'
                } else {
                    Show-RamError (Get-RamText -Text 'Не получилось включить мультизапуск даже после закрытия окон. Закрой Roblox вручную через диспетчер задач и попробуй снова.')
                    return
                }
            } else {
                Write-RamLog (Get-RamText -Text 'Мультизапуск не включён, хотя Roblox не запущен — странно. Перезапусти менеджер.') 'warn'
            }
        }
    }

    $added = 0
    $addedIds = New-Object Collections.ArrayList
    foreach ($a in $Accounts) {
        # Игра не задана — не беда: клиент откроется на главной под этим
        # аккаунтом, игру человек выберет сам.
        if ($script:Instances.ContainsKey($a.Id)) {
            Write-RamLog (Get-RamText -Text 'Пропуск ''{0}'': уже запущен.' -Arguments @([string]($($a.Alias)))) 'warn'
            continue
        }
        if ($script:LaunchQueue -contains $a.Id) { continue }
        [void]$script:LaunchQueue.Add($a.Id)
        [void]$addedIds.Add([string]$a.Id)
        if (-not $Unattended) { $script:LaunchSuppressedIds.Remove([string]$a.Id) }
        $script:LaunchTries.Remove([string]$a.Id)
        $script:LastLaunchFailures.Remove([string]$a.Id)
        $script:LaunchFailed.Remove([string]$a.Id)
        $added++
    }

    if ($added -eq 0) {
        Update-RamCardStates
        # Ответ и на «делать нечего»: ▶ на уже запущенном аккаунте молчала.
        if (-not $Unattended) { Set-RamStatus (Get-RamText -Text 'Все выбранные аккаунты уже запущены или стоят в очереди.') }
        return
    }

    $script:PendingTileUntil = [datetime]::MinValue
    Write-RamLog (Get-RamText -Text 'В очередь добавлено: {0}. Пауза между запусками — {1} с.' -Arguments @([string]($added),[string]($($script:Settings.LaunchDelaySec)))) 'info'
    if ($script:NextLaunchTime -lt (Get-Date)) { $script:NextLaunchTime = Get-Date }
    $script:UI.LaunchTimer.Start()
    Update-RamCardStates
    if ($PassThru) { return @($addedIds) }
}

function Set-RamLaunchPaused {
    param([bool]$Paused)
    $script:LaunchPaused = $Paused
    Update-RamCardStates
    Set-RamStatus $(if ($Paused) { (Get-RamText -Text 'Очередь на паузе. Открытые окна Roblox продолжают работать.') } else { (Get-RamText -Text 'Очередь продолжена.') })
}

function Invoke-RamAccountPrimaryAction {
    param([string]$Id)
    $a = Get-RamAccountById -Id $Id
    if ($null -eq $a) { return }
    if ($script:Instances.ContainsKey($Id)) {
        $handle = $script:Instances[$Id].Handle
        if ($handle -ne [IntPtr]::Zero) { [void](Set-RamWindowForeground -Handle $handle) }
        else { Set-RamStatus (Get-RamText -Text 'Окно Roblox ещё загружается.') }
    } elseif ($script:LaunchQueue -contains $Id) { Show-RamLaunchCenter }
    elseif ([string]$a.CookieOk -eq 'no') { Invoke-RamRelogin -Id $Id }
    else { Add-RamToLaunchQueue -Accounts @($a) }
}

function Remove-RamQueuedAccount {
    param([string]$Id)
    if ($script:LaunchQueue -notcontains $Id) { Set-RamStatus (Get-RamText -Text 'Этот аккаунт уже вышел из очереди.'); return }
    $script:LaunchSuppressedIds[$Id] = $true
    $script:LaunchQueue.Remove($Id)
    $script:LaunchTries.Remove($Id)
    if ($script:LaunchQueue.Count -eq 0) { $script:LaunchPaused = $false }
    Update-RamCardStates
}

function Stop-RamLaunchQueue {
    $count = $script:LaunchQueue.Count
    foreach ($id in @($script:LaunchQueue)) { $script:LaunchSuppressedIds[[string]$id] = $true }
    $script:LaunchQueue.Clear()
    $script:LaunchTries = @{}
    $script:LaunchFailed = @{}
    $script:LaunchPaused = $false
    if ($script:UI.LaunchTimer) { $script:UI.LaunchTimer.Stop() }
    # Ожидание чтения XML сохраняем для возможного следующего запуска.
    Update-RamCardStates
    Set-RamStatus (Get-RamText -Text 'Отменено запусков: {0}. Эти аккаунты не будут автоматически перезапускаться до ручного запуска или перезапуска AltHub.' -Arguments @([string]($count)))
}

function Invoke-RamRetryFailedLaunches {
    $targets = @(Get-RamOrderedAccounts | Where-Object { $script:LastLaunchFailures.ContainsKey([string]$_.Id) })
    if ($targets.Count -eq 0) { Set-RamStatus (Get-RamText -Text 'Неудавшихся запусков для повтора нет.'); return }
    Set-RamStatus (Get-RamText -Text 'Повторяю неудавшиеся запуски: {0}.' -Arguments @([string]($($targets.Count))))
    Add-RamToLaunchQueue -Accounts $targets
}

function Get-RamLaunchSnapshot {
    $positions = @{}
    for ($i=0; $i -lt $script:LaunchQueue.Count; $i++) { $positions[[string]$script:LaunchQueue[$i]] = $i + 1 }
    $processes = @{}
    foreach ($p in @(Get-RamRobloxProcesses)) { $processes[[int]$p.Id] = $p }
    $rows = @(); $memory = 0
    foreach ($a in @(Get-RamOrderedAccounts)) {
        $id = [string]$a.Id; $state = ''; $detail = ''; $ram = 0
        if ($script:Instances.ContainsKey($id)) {
            $inst = $script:Instances[$id]
            $closing = (($null -ne $script:Stopping -and $script:Stopping.ContainsKey($id)) -or
                ($inst.PSObject.Properties.Name -contains 'ClosingByOs' -and [bool]$inst.ClosingByOs))
            $state = if ($closing) { (Get-RamText -Text 'Закрывается') } elseif ($inst.Handle -eq [IntPtr]::Zero) { (Get-RamText -Text 'Загрузка клиента') } else { (Get-RamText -Text 'Окно открыто') }
            if ($processes.ContainsKey([int]$inst.ProcessId)) { $ram = [int]($processes[[int]$inst.ProcessId].WorkingSet64 / 1MB) }
            $memory += $ram
        } elseif ($positions.ContainsKey($id)) {
            $state = $(if ($script:LaunchPaused) { (Get-RamText -Text 'Пауза') } else { (Get-RamText -Text 'В очереди') }) + " · №$($positions[$id])"
        } elseif ($script:LastLaunchFailures.ContainsKey($id)) {
            $state = (Get-RamText -Text 'Не запустился')
            $detail = Get-RamErrorText -Text (Protect-RamMessage -Message ([string]$script:LastLaunchFailures[$id]))
        } else { continue }
        $rows += [pscustomobject]@{ Id=$id; Name=[string]$a.Alias; State=$state; Detail=$detail; MemoryMb=$ram
            Game=$(if ($a.GameName) { [string]$a.GameName } elseif ($a.PlaceId) { "ID $($a.PlaceId)" } else { (Get-RamText -Text 'Roblox без игры') })
            Settings=(Get-RamAccountSettingsSummary -Account $a) }
    }
    $wait = [int][Math]::Max(0.0, ($script:NextLaunchTime - (Get-Date)).TotalSeconds)
    $different = (-not [string]::IsNullOrEmpty($script:AwaitWindowFor) -and $script:Instances.ContainsKey([string]$script:AwaitWindowFor) -and (Test-RamNextSettingsDiffer))
    if ($different) { $wait = [Math]::Max($wait, [int][Math]::Max(0.0, ($script:AwaitSettingsReadyAt - (Get-Date)).TotalSeconds)) }
    $waitingForWindow = ($different -and $script:Instances.ContainsKey([string]$script:AwaitWindowFor) -and $script:Instances[$script:AwaitWindowFor].Handle -eq [IntPtr]::Zero)
    return [pscustomobject]@{ Rows=$rows; MemoryMb=$memory; Queued=$script:LaunchQueue.Count
        Running=$script:Instances.Count; Failed=@($rows | Where-Object { $_.State -eq (Get-RamText -Text 'Не запустился') }).Count; Paused=$script:LaunchPaused; WaitSeconds=$wait; WaitingForWindow=$waitingForWindow }
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
        Write-RamLog (Get-RamText -Text 'Настройки графики Roblox возвращены к твоим{0}.' -Arguments @([string]($note))) 'info'
    } catch {
        # Обычно значит, что клиент ещё запущен — вернём в следующий раз.
    }
}

function Test-RamNextSettingsDiffer {
    if ($script:LaunchQueue.Count -eq 0) { return $false }
    $next = Get-RamAccountById -Id ([string]$script:LaunchQueue[0])
    return ($null -ne $next -and (Get-RamClientSettingsKey -Account $next) -ne $script:AwaitSettingsKey)
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
    if ([string]::IsNullOrEmpty($script:AwaitWindowFor) -or -not (Test-RamNextSettingsDiffer)) { return $true }

    $inst = $script:Instances[$script:AwaitWindowFor]
    if ($null -eq $inst) {
        $script:AwaitWindowFor = ''
        $script:AwaitSettingsKey = ''
        $script:AwaitSettingsReadyAt = [datetime]::MinValue
        return $true
    }

    if ($inst.Handle -eq [IntPtr]::Zero) {
        $inst.Handle = Get-RamRobloxWindow -ProcessId $inst.ProcessId -TimeoutSec 0
    }
    if ($inst.Handle -ne [IntPtr]::Zero) {
        if ((Get-Date) -lt $script:AwaitSettingsReadyAt) { return $false }
        $script:AwaitWindowFor = ''
        $script:AwaitSettingsKey = ''
        $script:AwaitSettingsReadyAt = [datetime]::MinValue
        return $true
    }

    if ((Get-Date) -ge $script:AwaitWindowUntil) {
        $prev = Get-RamAccountById -Id $script:AwaitWindowFor
        $who  = if ($null -ne $prev) { $prev.Alias } else { (Get-RamText -Text 'предыдущий') }
        Write-RamLog (Get-RamText -Text '''{0}'': окно не появилось вовремя. Запускаю следующего — настройки графики могли не успеть примениться.' -Arguments @([string]($who))) 'warn'
        $script:AwaitWindowFor = ''
        $script:AwaitSettingsKey = ''
        $script:AwaitSettingsReadyAt = [datetime]::MinValue
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

    $script:AwaitWindowFor   = $Launched.Id
    $script:AwaitSettingsKey = Get-RamClientSettingsKey -Account $Launched
    $script:AwaitWindowUntil = (Get-Date).AddSeconds(60)
    # Появление окна ещё не гарантирует, что медленная машина уже дочитала
    # GlobalBasicSettings. Даём клиенту минимум 15 секунд от старта перед
    # тем, как перезаписывать файл настройками следующего аккаунта.
    $script:AwaitSettingsReadyAt = $script:LastLaunchAt.AddSeconds(15)
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
        $name = if ($null -ne $acc) { $acc.Alias } else { (Get-RamText -Text 'аккаунт') }
        $lines += "• $name — $($script:LaunchFailed[$id])"
    }
    $script:LaunchFailed = @{}

    Write-RamLog (Get-RamText -Text 'Не запустились: {0}.' -Arguments @([string]($($lines.Count)))) 'warn'
    # Программа свёрнута в часы (обычно — запуск по расписанию): модальное окно
    # ждало бы человека до утра. Причины — в журнал и нижнюю строку.
    $formVisible = ($script:UI.ContainsKey('Form') -and $null -ne $script:UI.Form -and $script:UI.Form.Visible)
    $centerVisible = ($script:UI.ContainsKey('LaunchCenter') -and $null -ne $script:UI.LaunchCenter -and -not $script:UI.LaunchCenter.IsDisposed -and $script:UI.LaunchCenter.Visible)
    if (-not $formVisible -or $centerVisible) {
        foreach ($l in $lines) { Write-RamLog ((Get-RamText -Text 'Не запустился ') + $l.TrimStart('•', ' ')) 'warn' }
        Set-RamStatus (Get-RamText -Text 'Запустились не все: {0} — причины в журнале.' -Arguments @([string]($($lines.Count))))
        return
    }
    Show-RamInfo ((Get-RamText -Text 'Запустились не все. Не вышло у этих:

') + ($lines -join "`n") +
                  (Get-RamText -Text '

Чаще всего помогает пауза побольше между запусками — она в Настройках.'))
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
            Write-RamLog (Get-RamText -Text 'Подхвачен уже работающий клиент: «{0}».' -Arguments @([string]($($acc.Alias)))) 'ok'
        } else {
            $unknown++
        }
    }

    if ($unknown -gt 0) {
        Write-RamLog (Get-RamText -Text 'Работают ещё клиенты Roblox: {0} — под каким аккаунтом, определить не вышло.' -Arguments @([string]($unknown))) 'warn'
    }
    if ($found -gt 0 -or $unknown -gt 0) {
        Update-RamCardStates
        Update-RamHeaderCounts
    }
    return $found
}

function Invoke-RamNextLaunch {
    if ($script:LaunchTickActive) { return }
    $script:LaunchTickActive = $true
    try {
    if ($script:LaunchPaused -and $script:LaunchQueue.Count -gt 0) { return }
    if ($script:LaunchQueue.Count -eq 0) {
        $script:UI.LaunchTimer.Stop()
        $script:LaunchTries = @{}
        Show-RamLaunchReport
        if ($script:LaunchQueue.Count -gt 0) { return }

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

    Set-RamStatus (Get-RamText -Text 'Запускаю «{0}»...' -Arguments @([string]($($a.Alias))))
    $where = if ($a.GameName) { $a.GameName } elseif ($a.PlaceId) { (Get-RamText -Text 'игра {0}' -Arguments @([string]($($a.PlaceId)))) } else { (Get-RamText -Text 'главная Roblox (без игры)') }
    Write-RamLog (Get-RamText -Text 'Запуск ''{0}'' -> {1}' -Arguments @([string]($($a.Alias)),[string]($where))) 'info'

    try {
        # Настройки клиента пишутся в общий файл Roblox прямо сейчас — клиент
        # прочитает их при старте. Поэтому это делается перед каждым запуском,
        # а не один раз.
        $applied = @()
        try {
            $applied = Apply-RamAccountClientSettings -Account $a
            if ($applied.Count -gt 0) {
                $script:SettingsTouched = $true
                Write-RamLog (Get-RamText -Text '''{0}'': параметры записаны в XML Roblox — {1}' -Arguments @([string]($($a.Alias)),[string]($($applied -join ', ')))) 'info'
            } elseif ($script:ClientSettingsSkippedReason) {
                Write-RamLog "'$($a.Alias)': $($script:ClientSettingsSkippedReason)" 'warn'
                Set-RamStatus (Get-RamText -Text '''{0}'': Roblox запускается; персональные настройки применятся после создания XML.' -Arguments @([string]($($a.Alias))))
            }
        } catch {
            $settingsError = $_.Exception.Message
            Write-RamLog (Get-RamText -Text '''{0}'': настройки клиента не применились — {1}' -Arguments @([string]($($a.Alias)),[string]($settingsError))) 'err'
            # Если человек явно задал графику/звук/режим окна, молча запускать
            # с чужими общими настройками нельзя. Раньше запуск продолжался,
            # в журнале было предупреждение, а со стороны всё выглядело как
            # полностью неработающая функция.
            throw "Настройки клиента для '$($a.Alias)' не применились: $settingsError Запуск отменён, чтобы не открыть аккаунт с неверной графикой или звуком."
        }

        $proc = Start-RamRobloxInstance -Account $a -PlayerPath $script:PlayerPath -Locale $script:Settings.Locale `
                                        -Minimized:([bool]$script:Settings.LaunchMinimized)
        $script:LastLaunchAt = Get-Date

        $script:Instances[$a.Id] = [pscustomobject]@{
            ProcessId = $proc.Id
            Handle    = [IntPtr]::Zero
            Started   = Get-Date
            MinimizeOnShow = [bool]$script:Settings.LaunchMinimized
            DesiredFullscreen = [string]$a.Fullscreen
            WindowStateRecheckAt = [datetime]::MinValue
        }
        $a.LastUsed    = (Get-Date).ToString('s')
        $a.LaunchCount = [int]$a.LaunchCount + 1
        $script:RestartCount[$a.Id] = 0
        Write-RamLog (Get-RamText -Text '''{0}'' стартовал (PID {1}).' -Arguments @([string]($($a.Alias)),[string]($($proc.Id)))) 'ok'

        Set-RamSettingsWait -Launched $a
    } catch {
        $err = $_
        $msg = $err.Exception.Message
        Write-RamLog "'$($a.Alias)': $msg" 'err'

        # Запуск сорвался, а настройки графики мы в общий файл уже записали.
        # Оставлять их нельзя: откроешь Roblox вручную — и получишь графику
        # твина вместо своей.
        Restore-RamOwnClientSettings -Reason (Get-RamText -Text 'запуск не состоялся')

        # «Слишком часто» — это не отказ, а просьба подождать. Возвращаем
        # аккаунт в НАЧАЛО очереди и просто сдвигаем время следующей попытки.
        # Спать здесь нельзя: код крутится в тике таймера, окно замёрзнет.
        $retryAfter = 0
        try { if ($null -ne $err.Exception.Data -and $err.Exception.Data.Contains('RamRetryAfter')) {
                  $retryAfter = [int]$err.Exception.Data['RamRetryAfter'] } } catch { }

        if ($retryAfter -gt 0 -and $tries -lt 4) {
            [void]$script:LaunchQueue.Insert(0, $a.Id)
            $script:NextLaunchTime = (Get-Date).AddSeconds($retryAfter)
            Set-RamStatus (Get-RamText -Text 'Roblox просит сбавить темп. «{0}» повторю через {1} с.' -Arguments @([string]($($a.Alias)),[string]($retryAfter)))
            Write-RamLog (Get-RamText -Text '''{0}'': Roblox ограничил частоту, повтор через {1} с (попытка {2}).' -Arguments @([string]($($a.Alias)),[string]($retryAfter),[string]($($tries + 1)))) 'warn'
            Update-RamCardStates
            return
        }

        # Кука умерла — попробуем починить её из приложения Roblox молча.
        # Если там сейчас именно этот аккаунт, вход подхватится сам и мы тут же
        # повторим запуск. Спрашивать в середине пачки запусков некогда.
        if ($msg -match 'недействительна|протухла') {
            if (Invoke-RamRepairCookie -Account $a -Quiet) {
                Write-RamLog (Get-RamText -Text '''{0}'': вход починен, пробую запустить снова.' -Arguments @([string]($($a.Alias)))) 'ok'
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
            Write-RamLog (Get-RamText -Text '''{0}'': попробую ещё раз в конце очереди.' -Arguments @([string]($($a.Alias)))) 'warn'
        } else {
            $script:LaunchFailed[$a.Id] = $msg
            $script:LastLaunchFailures[[string]$a.Id] = $msg
        }
    }

    $script:NextLaunchTime = (Get-Date).AddSeconds([int]$script:Settings.LaunchDelaySec)
    Update-RamCardStates
    } finally { $script:LaunchTickActive = $false }
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
        Write-RamLog (Get-RamText -Text 'Нечего раскладывать: окна так и не появились.') 'warn'
        return
    }
    if ($ready -lt $total) {
        Write-RamLog (Get-RamText -Text 'Раскладываю {0} из {1} — остальные окна не появились вовремя.' -Arguments @([string]($ready),[string](${total}))) 'warn'
    }
    Invoke-RamTileWindows -Quiet
}

function Get-RamLayoutAccounts {
    param([string]$Mode)
    $accounts = @(Get-RamOrderedAccounts)
    if ($Mode -eq 'main' -and $script:Settings.MainAccountId) {
        return @($accounts | Sort-Object { [string]$_.Id -ne [string]$script:Settings.MainAccountId }, { [int]$_.Order })
    }
    return $accounts
}

function Invoke-RamTileWindows {
    # -Quiet — зов автоматики после запуска окон (из таймера): там модальное
    # сообщение некому закрыть. Все пути человека отвечают словами.
    param([string]$Mode = '', [switch]$Quiet)

    $tileMode = if ($Mode) { $Mode } else { [string]$script:Settings.TileMode }
    if (@('grid','cascade','columns','rows','main') -notcontains $tileMode) { $tileMode = 'grid' }

    $live = @()
    foreach ($a in @(Get-RamLayoutAccounts -Mode $tileMode)) {
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
        # Молчаливый выход выглядит как сломанная кнопка. Если раскладывать
        # нечего — так и говорим, и подсказываем, что сделать.
        Write-RamLog (Get-RamText -Text 'Нечего раскладывать: окна ещё не появились.') 'warn'
        # И при левом клике, и при выборе раскладки правым: раньше второй путь
        # молчал — ровно жалоба «нажал окна — мне ничего не написало».
        if (-not $Quiet) {
            Show-RamMessage -Message ((Get-RamText -Text 'Раскладывать нечего: окон Roblox, запущенных через AltHub, сейчас нет.') +
                                      [Environment]::NewLine + [Environment]::NewLine +
                                      (Get-RamText -Text 'Отметь аккаунты, нажми «Запустить», дождись окон — потом «Окна».'))
        }
        return
    }

    # 'main' обязан быть в списке: его ставит «Быстрая настройка», и без него
    # выбор молча подменялся сеткой — в журнале каждый раз было «сеткой»,
    # хотя выбрано «основной крупно».

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
            Write-RamLog (Get-RamText -Text 'Окна расставлены по запомненным местам: {0} шт.' -Arguments @([string]($placed))) 'ok'
            return
        }
        $live = $auto
        if ($live.Count -eq 0) { return }
    }

    $layout = Get-RamTileLayout -Count $live.Count -Columns $script:Settings.TileColumns `
                                -Margin $script:Settings.TileMargin -Mode $tileMode
    for ($i = 0; $i -lt $live.Count; $i++) {
        $c = $layout[$i]
        [void](Set-RamWindowBounds -Handle $live[$i].Handle -X $c.X -Y $c.Y -Width $c.Width -Height $c.Height)
    }

    $names = @{ grid = (Get-RamText -Text 'сеткой'); cascade = (Get-RamText -Text 'каскадом'); columns = (Get-RamText -Text 'колонками'); rows = (Get-RamText -Text 'строками')
                main = (Get-RamText -Text 'основной крупно') }
    Write-RamLog (Get-RamText -Text 'Окна разложены {0}: {1} шт.' -Arguments @([string]($($names[$tileMode])),[string]($($live.Count)))) 'ok'
}

function Update-RamInstanceWindowTitle {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)]$Instance)
    try {
        if (-not $script:Instances.ContainsKey($Id) -or
            -not [object]::ReferenceEquals($Instance, $script:Instances[$Id])) { return }
        $handle = [IntPtr]$Instance.Handle
        if ($handle -eq [IntPtr]::Zero -or -not (Test-RamWindowAlive -Handle $handle) -or
            (Get-RamWindowProcessId -Handle $handle) -ne [int]$Instance.ProcessId) { return }
        $account = Get-RamAccountById -Id $Id
        if ($null -eq $account) { return }
        $current = Get-RamWindowTitle -Handle $handle
        if ([string]::IsNullOrEmpty($current)) { return }
        $want = "Roblox — $($account.Alias)"
        $state = $null
        if ($Instance.PSObject.Properties.Name -contains 'WindowTitleState') { $state = $Instance.WindowTitleState }
        if ($null -ne $state -and ($state.Handle -ne $handle -or $state.ProcessId -ne $Instance.ProcessId)) {
            # Старый заголовок принадлежал другому окну: не восстанавливаем его здесь.
            if (-not $script:Settings.RenameWindows) { return }
            $state = $null
        }
        if ($script:Settings.RenameWindows) {
            if ($null -eq $state) {
                $state = [pscustomobject]@{Handle=$handle;ProcessId=$Instance.ProcessId;
                    Original=$(if ($current -ceq $want) {'Roblox'} else {$current});Applied=$null}
                $Instance | Add-Member -NotePropertyName WindowTitleState -NotePropertyValue $state -Force
            } elseif (($state.Applied -and $current -cne $state.Applied) -or
                      (-not $state.Applied -and $current -cne $state.Original)) { return }
            if ($current -ceq $want -or (Set-RamWindowTitle -Handle $handle -Title $want)) { $state.Applied = $want }
        } elseif ($null -ne $state) {
            if ($state.Applied -and $current -ceq $state.Applied -and
                (Set-RamWindowTitle -Handle $handle -Title $state.Original)) { $state.Applied = $null }
        } elseif ($current -ceq $want) {
            # Точная старая подпись AltHub, созданная до появления снимка оригинала.
            [void](Set-RamWindowTitle -Handle $handle -Title 'Roblox')
        }
    } catch { return }
}

function Update-RamInstances {
    <# Ищем появившиеся окна, подписываем заголовки, убираем закрывшиеся. #>
    if ($script:UpdatingInstances) { return }
    $script:UpdatingInstances = $true
    try {
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
                if ($inst.Handle -ne [IntPtr]::Zero -and
                    $inst.PSObject.Properties.Name -contains 'MinimizeOnShow' -and [bool]$inst.MinimizeOnShow) {
                    # SW_MINIMIZE. Повторять не надо: дальше окно остаётся
                    # свёрнутым, пока человек явно не нажмёт «Показать».
                    if ([string]$inst.DesiredFullscreen -eq 'no') {
                        [void][Ram.Native]::ShowWindow($inst.Handle, 9) # SW_RESTORE: снять maximized
                    }
                    [void][Ram.Native]::ShowWindow($inst.Handle, 7) # SW_SHOWMINNOACTIVE
                    $inst.MinimizeOnShow = $false
                    $inst.WindowStateRecheckAt = (Get-Date).AddSeconds(2)
                }
            } else {
                $inst | Add-Member -NotePropertyName FindSkip -NotePropertyValue ($skip - 1) -Force
            }
        }

        Update-RamInstanceWindowTitle -Id $id -Instance $inst
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

        Write-RamLog (Get-RamText -Text '''{0}'' закрылся{1}.' -Arguments @([string]($($a.Alias)),[string]($(if($null -ne $lived){(Get-RamText -Text ' (был в игре ') + (Format-RamDuration ([int]$lived.TotalSeconds)) + ')'})))) 'info'

        # МУЛЬТИЗАПУСК ПЕРЕСТАЛ РАБОТАТЬ? Защиту Roblox от второго окна AltHub
        # обходит через имя объекта ROBLOX_singletonEvent — а это имя уже менялось
        # (раньше было ROBLOX_singletonMutex). Когда Roblox сменит его снова,
        # «замок взят» будет по-прежнему рапортоваться, но каждое новое окно
        # станет закрывать предыдущее, и автоперезапуск начнёт гонять окна по
        # кругу. Признак: окно, запущенное РАНЬШЕ последнего запуска, само
        # закрылось в первые 20 секунд после него, а новое осталось жить.
        $sinceLaunch = ((Get-Date) - $script:LastLaunchAt).TotalSeconds
        $killedByNew = (-not $byUser -and $null -ne $lived -and $sinceLaunch -lt 20 -and
                        $lived.TotalSeconds -gt ($sinceLaunch + 2) -and $script:Instances.Count -ge 1)
        if ($killedByNew) {
            $script:SingletonKills = [int]$script:SingletonKills + 1
            Write-RamLog (Get-RamText -Text '''{0}'' закрылся сразу после запуска другого окна — похоже, новое окно выбило старое.' -Arguments @([string]($($a.Alias)))) 'warn'
            if ($script:SingletonKills -ge 2 -and -not $script:SingletonKillWarned) {
                $script:SingletonKillWarned = $true
                $msg = ((Get-RamText -Text 'Похоже, мультизапуск перестал работать: каждое новое окно Roblox закрывает предыдущее.') +
                        [Environment]::NewLine + [Environment]::NewLine +
                        (Get-RamText -Text 'Скорее всего, Roblox сменил защиту от второго окна после обновления. AltHub это не чинит сам — ') +
                        (Get-RamText -Text 'нужна новая версия программы. Пока запускай аккаунты по одному.'))
                Write-RamLog $msg 'err'
                Set-RamStatus (Get-RamText -Text 'Мультизапуск, похоже, сломан обновлением Roblox — подробности в журнале.')
                # Окно — только если человек сейчас смотрит на программу: модальное
                # окно из таймера ночью ждало бы его до утра.
                if ($script:UI.ContainsKey('Form') -and $null -ne $script:UI.Form -and $script:UI.Form.Visible) {
                    Show-RamMessage -Kind 'warn' -Title (Get-RamText -Text 'Мультизапуск') -Message $msg
                }
            }
            # По кругу не гоняем: новое окно снова выбьет это.
            continue
        } elseif ($null -ne $lived -and $lived.TotalSeconds -gt 60) {
            $script:SingletonKills = 0
        }

        if (-not $script:Settings.AutoRestart) { continue }

        # Окно, прожившее меньше 20 секунд, скорее всего не «вылетело», а не
        # смогло стартовать — гонять его по кругу бессмысленно.
        if ($null -ne $lived -and $lived.TotalSeconds -lt 20) {
            Write-RamLog (Get-RamText -Text '''{0}'': прожил меньше 20 с, автоперезапуск пропущен.' -Arguments @([string]($($a.Alias)))) 'warn'
            continue
        }

        $tries = 0
        if ($script:RestartCount.ContainsKey($id)) { $tries = [int]$script:RestartCount[$id] }
        if ($tries -ge [int]$script:Settings.AutoRestartMax) {
            Write-RamLog (Get-RamText -Text '''{0}'': достигнут предел автоперезапусков ({1}).' -Arguments @([string]($($a.Alias)),[string]($tries))) 'warn'
            continue
        }

        $script:RestartCount[$id] = $tries + 1
        Write-RamLog (Get-RamText -Text '''{0}'': вылетел, поднимаю заново (попытка {1}).' -Arguments @([string]($($a.Alias)),[string]($($tries + 1)))) 'warn'
        Add-RamToLaunchQueue -Accounts @($a) -Unattended
    }

    # Свои настройки графики возвращаем, когда все окна Roblox закрыты: файл
    # у Roblox общий, и трогать его при живых клиентах нельзя — они перезапишут
    # его своим состоянием при выходе.
    if ($script:SettingsTouched -and $script:Instances.Count -eq 0 -and
        @(Get-RamRobloxProcesses).Count -eq 0 -and
        ((Get-Date) - $script:LastLaunchAt).TotalSeconds -ge 15) {
        Restore-RamOwnClientSettings -Reason (Get-RamText -Text 'все окна Roblox закрыты')
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
    } finally {
        $script:UpdatingInstances = $false
    }
}

function Update-RamFreshRobloxWindow {
    <#
      Частый лёгкий сторожок: ловит первое настоящее окно только что
      запущенного клиента и сворачивает его раньше, чем общий двухсекундный
      опрос успеет показать его поверх остальных программ.
    #>
    if ($null -eq $script:Settings -or -not [bool]$script:Settings.LaunchMinimized) { return }
    foreach ($id in @($script:Instances.Keys)) {
        $inst = $script:Instances[$id]
        if ($null -eq $inst -or $inst.Handle -eq [IntPtr]::Zero) { continue }
        if ($inst.PSObject.Properties.Name -notcontains 'WindowStateRecheckAt' -or
            $inst.WindowStateRecheckAt -eq [datetime]::MinValue -or (Get-Date) -lt $inst.WindowStateRecheckAt) { continue }
        if ($inst.PSObject.Properties.Name -contains 'DesiredFullscreen' -and [string]$inst.DesiredFullscreen -eq 'no') {
            [void][Ram.Native]::ShowWindow($inst.Handle, 9)
        }
        [void][Ram.Native]::ShowWindow($inst.Handle, 7)
        $inst.WindowStateRecheckAt = [datetime]::MinValue
        return
    }
    foreach ($id in @($script:Instances.Keys)) {
        $inst = $script:Instances[$id]
        if ($null -eq $inst -or $inst.Handle -ne [IntPtr]::Zero) { continue }
        if ($inst.PSObject.Properties.Name -notcontains 'MinimizeOnShow' -or -not [bool]$inst.MinimizeOnShow) { continue }

        $handle = Get-RamRobloxWindow -ProcessId $inst.ProcessId -TimeoutSec 0
        if ($handle -ne [IntPtr]::Zero) {
            $inst.Handle = $handle
            if ($inst.PSObject.Properties.Name -contains 'DesiredFullscreen' -and [string]$inst.DesiredFullscreen -eq 'no') {
                [void][Ram.Native]::ShowWindow($handle, 9) # снять maximized/fullscreen restore state
            }
            [void][Ram.Native]::ShowWindow($handle, 7) # SW_SHOWMINNOACTIVE
            $inst.MinimizeOnShow = $false
            $inst.WindowStateRecheckAt = (Get-Date).AddSeconds(2)
            Update-RamInstanceWindowTitle -Id $id -Instance $inst
            Update-RamCardStates
        }
        # Не обходим рабочий стол по одному разу на каждый аккаунт за тик.
        return
    }
}

function New-RamFreshWindowTimer {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 150
    $timer.Add_Tick({ Invoke-RamSafe -What (Get-RamText -Text 'сворачивание свежего окна Roblox') -Body {
        Update-RamForegroundHistory
        Update-RamFreshRobloxWindow
    } })
    $timer.Start()
    return $timer
}

# ------------------------------------------------------- действия ----------

function Invoke-RamAssignGame {
    <#
      Назначить игру отмеченным аккаунтам. С -Accounts работает ровно по ним
      и ни о чём не спрашивает — так зовёт меню правого клика по карточке.
    #>
    param([object[]]$Accounts)

    $targets = if (@($Accounts).Count -gt 0) { @($Accounts) }
               else { @(Get-RamActionTargets -What (Get-RamText -Text 'игру')) }
    if ($targets.Count -eq 0) { return }

    # Отдельный пункт для снятия игры. Раньше игру снимал пустой ввод — и
    # человек, нажавший OK не глядя, молча терял игру у всех отмеченных.
    $suggestions = @([pscustomobject]@{ Text = (Get-RamText -Text '— убрать игру, открывать просто Roblox —'); Value = 'CLEAR' })
    $suggestions += @(Get-RamGameSuggestions)

    $val = Show-RamInputDialog -Title (Get-RamText -Text 'Игра для отмеченных') `
             -Prompt (Get-RamText -Text 'Ссылка на игру, ссылка «Поделиться» (share?code=...), приглашение на приватный сервер или просто ID. Можно выбрать из сохранённых.') `
             -Value '' -Suggestions $suggestions
    if ($null -eq $val) { return }

    # Пусто — значит человек передумал. Ничего не трогаем.
    if ([string]::IsNullOrWhiteSpace($val)) {
        Write-RamLog (Get-RamText -Text 'Игра не менялась — поле осталось пустым.') 'info'
        return
    }

    if ($val.Trim() -eq 'CLEAR') {
        if (-not (Confirm-Ram (Get-RamText -Text 'Убрать игру у отмеченных аккаунтов (их {0})?

Они будут просто открывать Roblox, а игру ты выберешь сам уже в клиенте.' -Arguments @([string]($($targets.Count)))))) { return }
        Push-RamUndo -Label (Get-RamText -Text 'снятие игры')
        foreach ($a in $targets) { $a.PlaceId = ''; $a.GameName = ''; $a.LinkCode = '' }
        Save-RamState
        Build-RamCards
        Write-RamLog (Get-RamText -Text 'Игра снята у аккаунтов ({0}) — Roblox будет просто открываться.' -Arguments @([string]($($targets.Count)))) 'ok'
        return
    }

    $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $g = $null
    try   { $g = Resolve-RamGameInput -Value $val }
    catch { Show-RamError $_.Exception.Message }
    finally { $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::Default }
    if ($null -eq $g) { return }

    if (-not $g.PlaceId) {
        Show-RamError (Get-RamText -Text 'Не понял, что это за игра. Вставь ссылку на игру, ссылку «Поделиться» или ID числом.')
        return
    }

    Push-RamUndo -Label (Get-RamText -Text 'назначение игры')
    foreach ($a in $targets) {
        $a.PlaceId  = $g.PlaceId
        $a.GameName = $g.GameName
        $a.LinkCode = $g.LinkCode
    }
    Save-RamState
    Build-RamCards

    $what = if ($g.GameName) { $g.GameName } else { "ID $($g.PlaceId)" }
    Add-RamSavedGame -PlaceId $g.PlaceId -LinkCode $g.LinkCode -Title $what
    if ($g.LinkCode) { $what += (Get-RamText -Text ' (приватный сервер)') }
    Write-RamLog (Get-RamText -Text '«{0}» назначена аккаунтам: {1}.' -Arguments @([string]($what),[string]($($targets.Count)))) 'ok'

    # Почти всегда игру назначают, чтобы тут же в неё и зайти. Спрашиваем,
    # а не запускаем молча: назначение бывает и «на потом».
    $ask = if ($targets.Count -eq 1) { (Get-RamText -Text 'Запустить «{0}» прямо сейчас?' -Arguments @([string]($($targets[0].Alias)))) }
           else { (Get-RamText -Text 'Запустить эти аккаунты ({0}) прямо сейчас?' -Arguments @([string]($($targets.Count)))) }
    if (Confirm-Ram (Get-RamText -Text 'Игра «{0}» назначена.

{1}' -Arguments @([string]($what),[string]($ask))) (Get-RamText -Text 'Запустить?')) {
        Add-RamToLaunchQueue -Accounts $targets
    }
}

function Invoke-RamAssignGroup {
    <# Собрать отмеченные аккаунты в набор. Пустое имя убирает из набора. #>
    $targets = @(Get-RamActionTargets -What (Get-RamText -Text 'набор'))
    if ($targets.Count -eq 0) { return }

    $sug = @([pscustomobject]@{ Text = (Get-RamText -Text '— убрать из набора —'); Value = 'CLEAR' })
    foreach ($g in Get-RamGroups) { $sug += [pscustomobject]@{ Text = $g; Value = $g } }

    $name = Show-RamInputDialog -Title (Get-RamText -Text 'Набор для отмеченных') `
              -Prompt (Get-RamText -Text 'Название набора — например Фарм или Торговля. Набором можно запускать все аккаунты сразу и фильтровать список.') `
              -Value '' -Suggestions $sug
    if ($null -eq $name) { return }

    $name = $name.Trim()

    # Пусто — передумал. Убрать из набора можно отдельным пунктом списка.
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-RamLog (Get-RamText -Text 'Набор не менялся — поле осталось пустым.') 'info'
        return
    }
    if ($name -eq 'CLEAR') {
        if (-not (Confirm-Ram (Get-RamText -Text 'Убрать отмеченные аккаунты (их {0}) из наборов?' -Arguments @([string]($($targets.Count)))))) { return }
        Push-RamUndo -Label (Get-RamText -Text 'снятие набора')
        foreach ($a in $targets) { $a.Group = '' }
        Save-RamState
        Build-RamCards
        Write-RamLog (Get-RamText -Text 'Аккаунты ({0}) убраны из набора.' -Arguments @([string]($($targets.Count)))) 'ok'
        return
    }
    Push-RamUndo -Label (Get-RamText -Text 'смена набора')
    foreach ($a in $targets) { $a.Group = $name }
    Save-RamState
    Build-RamCards
    Write-RamLog (Get-RamText -Text 'Набор «{0}»: аккаунтов {1}.' -Arguments @([string]($name),[string]($($targets.Count)))) 'ok'
}

function Invoke-RamAssignColor {
    <# Цветная метка для отмеченных. #>
    $targets = @(Get-RamActionTargets -What (Get-RamText -Text 'метку'))
    if ($targets.Count -eq 0) { return }

    $sug = @()
    foreach ($c in Get-RamLabelColors) { $sug += [pscustomobject]@{ Text = $c.Text; Value = $c.Key } }

    $val = Show-RamInputDialog -Title (Get-RamText -Text 'Цветная метка') `
             -Prompt (Get-RamText -Text 'Выбери цвет из списка. Метка рисуется полоской слева на карточке — удобно различать фармеров, торговых и основной.') `
             -Value '' -Suggestions $sug
    if ($null -eq $val) { return }

    $key = $val.Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($key)) {
        Write-RamLog (Get-RamText -Text 'Метка не менялась — поле осталось пустым.') 'info'
        return
    }
    $known = (Get-RamLabelColors | ForEach-Object { $_.Key })
    if ($known -notcontains $key) {
        Show-RamInfo (Get-RamText -Text 'Выбери цвет из списка. Неизвестное значение не было применено.')
        return
    }

    Push-RamUndo -Label (Get-RamText -Text 'смена метки')
    foreach ($a in $targets) { $a.Color = $key }
    Save-RamState
    Build-RamCards
    Write-RamLog (Get-RamText -Text 'Метка обновлена у аккаунтов: {0}.' -Arguments @([string]($($targets.Count)))) 'ok'
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
            Show-RamInfo (Get-RamText -Text 'Чтобы починить вход «{0}», войди под ним в приложении Roblox и нажми «Куки» ещё раз.' -Arguments @([string]($($Account.Alias))))
        }
        return $false
    }

    $who = $null
    try { $who = Get-RamAuthenticatedUser -Cookie $cookie } catch { }
    if ($null -eq $who) { return $false }

    if ([int64]$who.Id -ne [int64]$Account.UserId) {
        if (-not $Quiet) {
            Show-RamInfo ((Get-RamText -Text 'В приложении Roblox сейчас «{0}», а чинить надо «{1}».

' -Arguments @([string]($($who.Name)),[string]($($Account.Alias)))) +
                          (Get-RamText -Text 'Войди в приложении под нужным аккаунтом и нажми «Куки» ещё раз. ') +
                          (Get-RamText -Text 'Для смены аккаунта пользуйся кнопкой «Сменить аккаунт (безопасно)» в мастере — ') +
                          (Get-RamText -Text 'кнопка «Выйти» в самом Roblox убивает вход на сервере.'))
        }
        return $false
    }

    $Account.Cookie   = $cookie
    $Account.Username = $who.Name
    # И СНИМАЕМ МЕТКУ «ВХОД МЁРТВ». Здесь её забыли: соседние пути
    # (Invoke-RamRepairAll и меню карточки) зовут Set-RamCookieAlive, а этот
    # нет. Из-за этого «Починено входов: 1» показывалось, а карточка
    # оставалась красной. Кука только что подтверждена сервером выше.
    $Account.CookieOk        = 'yes'
    $Account.CookieCheckedAt = (Get-Date).ToString('s')
    Save-RamState
    Write-RamLog (Get-RamText -Text '''{0}'': вход восстановлен из приложения Roblox.' -Arguments @([string]($($Account.Alias)))) 'ok'
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

    # Проверка идёт фоновой очередью: окно не замирает, а 429 и обрыв сети
    # не красят живые аккаунты. Мёртвые очередь по окончании молча пробует
    # починить из приложения Roblox — см. Complete-RamCookieCheckBatch.
    Start-RamCookieCheckBatch -Accounts @($script:Accounts) -Quiet
}

function Update-RamAccountCookieState {
    <#
      Спрашивает у Roblox про ОДИН аккаунт: жив ли вход, и заодно освежает
      Robux, Premium и дату регистрации.

      ЗАЧЕМ ОТДЕЛЬНО. Общая кнопка «Проверить входы» обходит все аккаунты и
      занимает время. А человеку часто нужно другое: он только что вошёл под
      одним аккаунтом и хочет увидеть это на его карточке — «типа обновить
      страницу». Гонять ради этого проверку по всему списку незачем.

      Возвращает $true, если вход живой.
    #>
    param([Parameter(Mandatory)]$Account)

    if ([string]::IsNullOrWhiteSpace($Account.Cookie)) {
        $Account.CookieOk        = 'no'
        $Account.CookieCheckedAt = (Get-Date).ToString('s')
        Write-RamLog (Get-RamText -Text '''{0}'': куки нет.' -Arguments @([string]($($Account.Alias)))) 'warn'
        return $false
    }

    $script:LastCookieCheckState = 'transient'
    try {
        $check = Test-RamAuthenticatedUser -Cookie $Account.Cookie
        $script:LastCookieCheckState = $check.State
        if ($check.State -ne 'valid') {
            if ($check.State -eq 'unauthorized') {
                $Account.CookieOk        = 'no'
                $Account.CookieCheckedAt = (Get-Date).ToString('s')
                Write-RamLog "'$($Account.Alias)': $($check.Message)" 'warn'
            } else {
                Write-RamLog (Get-RamText -Text '''{0}'': состояние входа не изменено — {1}' -Arguments @([string]($($Account.Alias)),[string]($($check.Message)))) 'warn'
            }
            return $false
        }
        $u = $check.User
        $Account.Username = $u.Name
        $Account.UserId   = $u.Id

        $inf = Get-RamAccountInfo -Cookie $Account.Cookie -UserId $u.Id
        if ($inf.Robux -ge 0) { $Account.Robux = $inf.Robux }
        if ($inf.Premium)     { $Account.Premium = $inf.Premium }
        if ($inf.Created)     { $Account.Created = $inf.Created }

        $Account.CookieOk        = 'yes'
        $Account.CookieCheckedAt = (Get-Date).ToString('s')

        $extra = ''
        if ($Account.Robux -ge 0) { $extra = ", $($Account.Robux) Robux" }
        Write-RamLog (Get-RamText -Text '''{0}'': вход живой — {1}{2}' -Arguments @([string]($($Account.Alias)),[string]($($u.Name)),[string]($extra))) 'ok'
        return $true
    } catch {
        $script:LastCookieCheckState = 'transient'
        Write-RamLog (Get-RamText -Text '''{0}'': состояние входа не изменено — {1}' -Arguments @([string]($($Account.Alias)),[string]((Get-RamErrorText -Text ($($_.Exception.Message)))))) 'err'
        return $false
    }
}

function Invoke-RamRecheckOne {
    <# «Проверить этот вход» из меню карточки: спросить и сразу показать. #>
    param([Parameter(Mandatory)][string]$Id)

    $acc = Get-RamAccountById -Id $Id
    if ($null -eq $acc) { return }

    if ($script:UI.ContainsKey('Form') -and $null -ne $script:UI.Form) {
        $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    }
    try {
        $alive = Update-RamAccountCookieState -Account $acc
        Save-RamState
        Build-RamCards
    } finally {
        if ($script:UI.ContainsKey('Form') -and $null -ne $script:UI.Form) {
            $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    }

    if ($alive) {
        $extra = if ([int]$acc.Robux -ge 0) { [Environment]::NewLine + "Robux: $($acc.Robux)" } else { '' }
        Show-RamMessage -Kind 'ok' -Message ((Get-RamText -Text 'Вход в «{0}» живой.' -Arguments @([string]($($acc.Alias)))) + $extra)
    } elseif ($script:LastCookieCheckState -eq 'unauthorized') {
        Show-RamMessage -Kind 'warn' -Message ((Get-RamText -Text 'Вход в «{0}» мёртв — его надо взять заново.' -Arguments @([string]($($acc.Alias)))) +
            [Environment]::NewLine + [Environment]::NewLine +
            (Get-RamText -Text 'Красная кнопка на карточке откроет окно браузера, где можно войти руками.'))
    } else {
        Show-RamMessage -Kind 'warn' -Message ((Get-RamText -Text 'Сейчас не удалось проверить вход в «{0}».' -Arguments @([string]($($acc.Alias)))) +
            [Environment]::NewLine + [Environment]::NewLine +
            (Get-RamText -Text 'Его прежнее состояние не изменено. Проверь интернет и повтори позже.'))
    }
}

function Invoke-RamCheckCookies {
    <# Проверить, живы ли входы. #>
    $targets = @(Get-RamTargetAccounts)
    if ($targets.Count -eq 0) { $targets = @(Get-RamVisibleAccounts) }
    if ($targets.Count -eq 0) { Show-RamInfo (Get-RamText -Text 'Аккаунтов пока нет.'); return }

    Start-RamCookieCheckBatch -Accounts $targets
}

function Start-RamCookieCheckBatch {
    param([Parameter(Mandatory)][object[]]$Accounts, [switch]$Quiet)
    if ($null -ne $script:CookieCheckState) {
        Show-RamInfo (Get-RamText -Text 'Проверка входов уже идёт — дождись результата.')
        return
    }
    $queue = New-Object System.Collections.ArrayList
    foreach ($a in $Accounts) { [void]$queue.Add([pscustomobject]@{ Account=$a; Cookie=$null; Attempts=0 }) }
    $script:CookieCheckState = [pscustomobject]@{
        Queue=$queue; Job=$null; InfoJob=$null; Current=$null; Ok=0; Bad=0; Unknown=0
        Dead=(New-Object System.Collections.ArrayList)
        Total=$queue.Count; Quiet=[bool]$Quiet; NextAt=[datetime]::MinValue
    }
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 150
    $timer.Add_Tick({ Invoke-RamSafe -What (Get-RamText -Text 'асинхронная проверка входов') -Body { Invoke-RamCookieCheckPump } })
    $script:UI.CookieCheckTimer = $timer
    $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    Set-RamStatus (Get-RamText -Text 'Проверяю входы: 0 из {0}…' -Arguments @([string]($($queue.Count))))
    $timer.Start()
}

function Invoke-RamCookieCheckPump {
    $st = $script:CookieCheckState
    if ($null -eq $st) { return }
    if ((Get-Date) -lt $st.NextAt) { return }

    if ($null -ne $st.InfoJob) {
        if (-not $st.InfoJob.Task.IsCompleted) { return }
        $info = Complete-RamAccountInfoAsync -Job $st.InfoJob
        $st.InfoJob = $null
        $a = $st.Current.Account
        if (-not [object]::ReferenceEquals($a, (Get-RamAccountById -Id $a.Id)) -or [string]$a.Cookie -cne [string]$st.Current.Cookie) {
            $st.Current=$null; $st.NextAt=(Get-Date).AddMilliseconds(350)
            return
        }
        if ($info.Robux -ge 0) { $a.Robux=$info.Robux }
        if ($info.Premium) { $a.Premium=$info.Premium }
        if ($info.Created) { $a.Created=$info.Created }
        $st.Current=$null
        Set-RamStatus (Get-RamText -Text 'Проверяю входы и баланс: {0} из {1}…' -Arguments @([string]($($st.Total-$st.Queue.Count)),[string]($($st.Total))))
        $st.NextAt=(Get-Date).AddMilliseconds(350)
        return
    }

    if ($null -eq $st.Job -and $st.Queue.Count -gt 0) {
        $st.Current = $st.Queue[0]
        $st.Queue.RemoveAt(0)
        $st.Current.Attempts++
        if ([string]::IsNullOrWhiteSpace([string]$st.Current.Account.Cookie)) {
            $st.Bad++; $st.Current.Account.CookieOk='no'; $st.Current.Account.CookieCheckedAt=(Get-Date).ToString('s')
            [void]$st.Dead.Add($st.Current.Account)
            $st.Current=$null; $st.NextAt=(Get-Date).AddMilliseconds(350)
            return
        }
        $st.Current.Cookie = [string]$st.Current.Account.Cookie
        $st.Job = Start-RamAuthCheckAsync -Cookie $st.Current.Cookie
        return
    }

    if ($null -ne $st.Job) {
        if (-not $st.Job.Task.IsCompleted) { return }
        $result = Complete-RamAuthCheckAsync -Job $st.Job
        $st.Job = $null
        $a = $st.Current.Account
        # Результат старой куки не должен перечеркнуть повторный вход или Undo.
        if (-not [object]::ReferenceEquals($a, (Get-RamAccountById -Id $a.Id)) -or [string]$a.Cookie -cne [string]$st.Current.Cookie) {
            $st.Unknown++; $st.Current=$null; $st.NextAt=(Get-Date).AddMilliseconds(350)
            return
        }
        if ($result.State -eq 'valid') {
            $a.Username=$result.User.Name; $a.UserId=$result.User.Id
            $a.CookieOk='yes'; $a.CookieCheckedAt=(Get-Date).ToString('s'); $st.Ok++
            try {
                $st.InfoJob = Start-RamAccountInfoAsync -Cookie $a.Cookie -UserId $a.UserId
                Set-RamStatus (Get-RamText -Text 'Обновляю баланс «{0}»…' -Arguments @([string]($($a.Alias))))
                return
            } catch { Write-RamLog (Get-RamText -Text '''{0}'': баланс пока не обновлён, прежнее значение сохранено.' -Arguments @([string]($($a.Alias)))) 'warn' }
        } elseif ($result.State -eq 'unauthorized') {
            $a.CookieOk='no'; $a.CookieCheckedAt=(Get-Date).ToString('s'); $st.Bad++
            [void]$st.Dead.Add($a)
        } elseif ($result.State -eq 'rate_limited' -and $st.Current.Attempts -lt 2) {
            [void]$st.Queue.Insert(0,$st.Current)
            $st.NextAt=(Get-Date).AddSeconds([int]$result.RetryAfterSeconds)
            Set-RamStatus (Get-RamText -Text 'Roblox просит паузу — продолжу через {0} с.' -Arguments @([string]($($result.RetryAfterSeconds))))
            $st.Current=$null
            return
        } else {
            $st.Unknown++
            Write-RamLog (Get-RamText -Text '''{0}'': состояние входа не изменено — {1}' -Arguments @([string]($($a.Alias)),[string]($($result.Message)))) 'warn'
        }
        $st.Current=$null
        $done=$st.Total-$st.Queue.Count
        Set-RamStatus (Get-RamText -Text 'Проверяю входы: {0} из {1}…' -Arguments @([string]($done),[string]($($st.Total))))
        $st.NextAt=(Get-Date).AddMilliseconds(350)
    }

    if ($null -eq $st.Job -and $st.Queue.Count -eq 0 -and $null -eq $st.Current) {
        try { $script:UI.CookieCheckTimer.Stop(); $script:UI.CookieCheckTimer.Dispose() } catch { }
        $script:UI.CookieCheckTimer=$null
        $script:UI.Form.Cursor=[System.Windows.Forms.Cursors]::Default
        $script:CookieCheckState=$null
        Save-RamState
        Build-RamCards
        $level=if($st.Bad -eq 0 -and $st.Unknown -eq 0){'ok'}else{'warn'}
        Write-RamLog (Get-RamText -Text 'Проверено: живых {0}, мёртвых {1}, не удалось проверить {2}.' -Arguments @([string]($($st.Ok)),[string]($($st.Bad)),[string]($($st.Unknown)))) $level
        Set-RamStatus (Get-RamText -Text 'Проверка входов завершена.')
        Complete-RamCookieCheckBatch -Ok $st.Ok -Bad $st.Bad -Unknown $st.Unknown -Dead @($st.Dead) -Quiet:$st.Quiet
    }
}

function Get-RamWordForm {
    <# «1 вход, 2 входа, 5 входов, 11 входов, 21 вход». #>
    param([int]$N, [string]$One, [string]$Few, [string]$Many)
    $n100 = [Math]::Abs($N) % 100; $n10 = $n100 % 10
    if ($n100 -ge 11 -and $n100 -le 14) { return $Many }
    if ($n10 -eq 1) { return $One }
    if ($n10 -ge 2 -and $n10 -le 4) { return $Few }
    return $Many
}

function Complete-RamCookieCheckBatch {
    <#
      Итог проверки входов — словами, в каждом исходе.

      ЗАЧЕМ ОТДЕЛЬНО. Когда проверку перевели в фоновую очередь, итог свели к
      трём цифрам, а предложение починить мёртвые входы из приложения Roblox
      осталось в недостижимом коде после return. Человек видел «мёртвых: 2»
      и не знал, что с этим делать.

      -Quiet — проверка при запуске программы: окон не показываем, но мёртвые
      молча пробуем поднять из приложения Roblox, как делалось всегда.
    #>
    param([int]$Ok, [int]$Bad, [int]$Unknown, [object[]]$Dead = @(), [switch]$Quiet)

    if ($Quiet) {
        $fixed = 0
        foreach ($a in $Dead) {
            if (Invoke-RamRepairCookie -Account $a -Quiet) { $fixed++ }
        }
        if ($fixed -gt 0) {
            Build-RamCards
            Write-RamLog (Get-RamText -Text 'Мёртвых входов починено из приложения Roblox: {0}.' -Arguments @([string]($fixed))) 'ok'
        }
        return
    }

    if ($Bad -eq 0 -and $Unknown -eq 0) {
        $word = Get-RamWordForm -N $Ok -One (Get-RamText -Text 'вход') -Few (Get-RamText -Text 'входа') -Many (Get-RamText -Text 'входов')
        Show-RamMessage -Kind 'ok' -Message ((Get-RamText -Text 'Проверено {0} {1} — все живые.

Ничего чинить не нужно.' -Arguments @([string]($Ok),[string]($word))))
        return
    }
    if ($Bad -eq 0) {
        Show-RamMessage -Kind 'warn' -Message ((Get-RamText -Text 'Живых входов: {0}. Не удалось проверить: {1}.

' -Arguments @([string]($Ok),[string]($Unknown))) +
            (Get-RamText -Text 'Эти карточки НЕ помечены мёртвыми — Roblox просто не ответил. Проверь интернет и повтори позже.'))
        return
    }

    $names = (@($Dead) | ForEach-Object { $_.Alias }) -join ', '
    $extra = if ($Unknown -gt 0) { (Get-RamText -Text '

Ещё {0} проверить не удалось — их состояние не менялось.' -Arguments @([string]($Unknown))) } else { '' }
    if (Confirm-Ram ((Get-RamText -Text 'Живых: {0}. Мёртвые входы: {1}.{2}

' -Arguments @([string]($Ok),[string]($names),[string]($extra))) +
                     (Get-RamText -Text 'Попробовать починить мёртвые из приложения Roblox? ') +
                     (Get-RamText -Text 'Починится тот аккаунт, под которым ты сейчас вошёл в приложении.'))) {
        $fixed = 0
        foreach ($a in $Dead) {
            if (Invoke-RamRepairCookie -Account $a -Quiet) { $fixed++ }
        }
        if ($fixed -gt 0) {
            Build-RamCards
            Show-RamInfo (Get-RamText -Text 'Починено входов: {0}.

Остальные — войди под ними в приложении Roblox по очереди и нажимай «Куки», либо жми красную кнопку ↻ на карточке.' -Arguments @([string]($fixed)))
        } else {
            Show-RamInfo ((Get-RamText -Text 'Починить не вышло: в приложении Roblox сейчас другой аккаунт.

') +
                          (Get-RamText -Text 'Войди под нужным и нажми «Куки» ещё раз, либо жми красную кнопку ↻ на карточке — ') +
                          (Get-RamText -Text 'она откроет окно браузера, где можно войти руками.'))
        }
    } else {
        Set-RamStatus (Get-RamText -Text 'Мёртвых входов: {0} — красная кнопка ↻ на карточке откроет окно входа.' -Arguments @([string]($Bad)))
    }
}

function Invoke-RamStopSelected {
    <# Закрыть окна отмеченных аккаунтов. #>
    $targets = @(Get-RamTargetAccounts)
    if ($targets.Count -eq 0) {
        Show-RamMessage -Kind 'warn' -Message (Get-RamText -Text 'Отметь галочками окна, которые нужно закрыть. AltHub не закрывает все аккаунты молча.')
        return
    }
    if (-not (Confirm-RamHiddenSelection -Accounts $targets -What (Get-RamText -Text 'Закрыть'))) { return }
    $n = 0; $failed = 0; $notRunning = 0
    foreach ($a in $targets) {
        $inst = $script:Instances[$a.Id]
        if ($null -eq $inst) { $notRunning++; continue }
        # Закрытие руками — не вылет, счётчик вылетов не трогаем.
        $inst | Add-Member -NotePropertyName ClosedByUser -NotePropertyValue $true -Force
        if (Stop-RamRobloxInstance -ProcessId $inst.ProcessId) { $n++ } else { $failed++ }
    }
    Write-RamLog (Get-RamText -Text 'Закрыто клиентов: {0}; не удалось: {1}; не были запущены: {2}.' -Arguments @([string]($n),[string]($failed),[string]($notRunning))) $(if($failed){'warn'}else{'ok'})
    Update-RamCardStates

    # Отсутствие работы — тоже ответ. Раньше при нечего-закрывать кнопка
    # молчала, и это было неотличимо от поломки.
    if ($n -gt 0) {
        Set-RamStatus ((Get-RamText -Text 'Закрыто окон: {0}') -f $n)
    } elseif ($failed -gt 0) {
        Show-RamMessage -Kind 'warn' -Message (Get-RamText -Text 'Не удалось закрыть окон: {0}. Они остаются под контролем AltHub; попробуй ещё раз или закрой их вручную.' -Arguments @([string]($failed)))
    } else {
        Show-RamMessage -Message (Get-RamText -Text 'Закрывать нечего: сейчас ни одно окно Roblox не запущено через AltHub.')
    }
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
        Show-RamInfo (Get-RamText -Text 'Нечего запоминать: сейчас нет запущенных окон.')
        return
    }
    Save-RamState
    Build-RamCards
    Write-RamLog (Get-RamText -Text 'Места окон запомнены: {0} шт. Дальше окна будут вставать туда же.' -Arguments @([string]($saved))) 'ok'
}

function Invoke-RamFocusAccountByIndex {
    <# Ctrl+1..9: вывести наверх окно N-го аккаунта из видимого списка. #>
    param([int]$Index)

    $list = @(Get-RamVisibleAccounts)
    if ($Index -lt 1 -or $Index -gt $list.Count) { return }

    $a = $list[$Index - 1]
    $inst = $script:Instances[$a.Id]
    if ($null -eq $inst -or $inst.Handle -eq [IntPtr]::Zero) {
        Write-RamLog (Get-RamText -Text 'Ctrl+{0}: «{1}» сейчас не запущен.' -Arguments @([string](${Index}),[string]($($a.Alias)))) 'warn'
        return
    }
    [void](Set-RamWindowForeground -Handle $inst.Handle)
}

function Get-RamProfiles {
    return @($script:Settings.Profiles | Where-Object { $null -ne $_ -and $_.Name })
}

function New-RamLaunchProfile {
    param([string]$Name, [object[]]$Accounts)
    $snapshots = @()
    foreach ($a in $Accounts) {
        $snapshots += [pscustomobject]@{ Id=[string]$a.Id; PlaceId=[string]$a.PlaceId; GameName=[string]$a.GameName
            JobId=[string]$a.JobId; LinkCode=[string]$a.LinkCode; Graphics=[string]$a.Graphics
            FramerateCap=[string]$a.FramerateCap; Volume=[string]$a.Volume; Fullscreen=[string]$a.Fullscreen }
    }
    return [pscustomobject]@{ Name=$Name.Trim(); Group=''; Ids=@($Accounts | ForEach-Object { [string]$_.Id })
        PlaceId=''; GameName=''; LinkCode=''; LaunchSettings=$snapshots
        TileMode=[string]$script:Settings.TileMode; TileColumns=[int]$script:Settings.TileColumns
        AutoTile=[bool]$script:Settings.AutoTile; UseSavedWindows=[bool]$script:Settings.UseSavedWindows
        MainAccountId=$(if (@($Accounts.Id) -contains [string]$script:Settings.MainAccountId) { [string]$script:Settings.MainAccountId } else { [string]$Accounts[0].Id }) }
}

function ConvertTo-RamProfileTargets {
    param($Profile, [object[]]$Accounts)
    $copies = @(Copy-RamAccounts -Accounts $Accounts)
    if ($Profile.PSObject.Properties.Name -contains 'LaunchSettings') {
        $rules = @{ PlaceId='^\d{0,20}$'; JobId='^(|[0-9a-fA-F-]{36})$'; LinkCode='^[A-Za-z0-9_-]{0,200}$'
                    Graphics='^(|auto|[1-9]|10)$'; FramerateCap='^(|\d{1,4})$'; Volume='^(|100|[1-9]?\d)$'; Fullscreen='^(|yes|no)$' }
        $seen = @{}
        foreach ($saved in @($Profile.LaunchSettings)) {
            if ($null -eq $saved -or -not $saved.Id -or $seen.ContainsKey([string]$saved.Id)) { throw 'В сценарии повторён или отсутствует ID аккаунта.' }
            $seen[[string]$saved.Id] = $true
            foreach ($field in $rules.Keys) {
                if ($saved.PSObject.Properties.Name -notcontains $field -or [string]$saved.$field -notmatch $rules[$field]) {
                    throw "В сценарии недопустимое значение $field. Пересохрани сценарий."
                }
            }
            $a = $copies | Where-Object { [string]$_.Id -eq [string]$saved.Id } | Select-Object -First 1
            if ($null -eq $a) { continue }
            foreach ($field in @('PlaceId','GameName','JobId','LinkCode','Graphics','FramerateCap','Volume','Fullscreen')) { $a.$field = [string]$saved.$field }
        }
        foreach ($a in $copies) { if (-not $seen.ContainsKey([string]$a.Id)) { throw 'В сценарии нет настроек одного из выбранных аккаунтов.' } }
    } elseif ($Profile.PlaceId) {
        if ([string]$Profile.PlaceId -notmatch '^\d{1,20}$' -or [string]$Profile.LinkCode -notmatch '^[A-Za-z0-9_-]{0,200}$') { throw 'В профиле неверная ссылка на игру.' }
        foreach ($a in $copies) {
            $a.PlaceId=[string]$Profile.PlaceId; $a.LinkCode=[string]$Profile.LinkCode
            if ($Profile.GameName) { $a.GameName=[string]$Profile.GameName }
        }
    }
    return @($copies)
}

function Get-RamProfileSummary {
    param($Profile)
    if ($Profile.PSObject.Properties.Name -contains 'LaunchSettings') {
        $layout = switch ([string]$Profile.TileMode) { 'grid' {(Get-RamText -Text 'сетка')} 'main' {(Get-RamText -Text 'основа крупно')} 'cascade' {(Get-RamText -Text 'каскад')} 'columns' {(Get-RamText -Text 'колонки')} 'rows' {(Get-RamText -Text 'строки')} default {(Get-RamText -Text 'раскладка')} }
        return (Get-RamText -Text 'Аккаунтов: {0}  ·  {1}' -Arguments @([string]($(@($Profile.Ids).Count)),[string]($layout)))
    }
    $ids = @(); if ($Profile.PSObject.Properties.Name -contains 'Ids') { $ids = @($Profile.Ids) }
    $text = if ($Profile.Group) { (Get-RamText -Text 'набор «{0}»' -Arguments @([string]($($Profile.Group)))) } elseif ($ids.Count) { (Get-RamText -Text 'аккаунтов: {0}' -Arguments @([string]($($ids.Count)))) } else { (Get-RamText -Text 'все аккаунты') }
    if ($Profile.GameName) { $text += "  ·  $($Profile.GameName)" } elseif ($Profile.PlaceId) { $text += "  ·  ID $($Profile.PlaceId)" }
    if ($Profile.LinkCode) { $text += (Get-RamText -Text '  ·  приватный сервер') }
    return $text
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
            Show-RamInfo (Get-RamText -Text 'В профиле «{0}» записаны аккаунты, которых больше нет в списке. Пересохрани профиль.' -Arguments @([string]($($Profile.Name))))
            return
        }
    } elseif ([string]::IsNullOrWhiteSpace([string]$Profile.Group)) {
        $targets = @(Get-RamOrderedAccounts)
    } else {
        $targets = @($script:Accounts | Where-Object { [string]$_.Group -eq [string]$Profile.Group })
    }

    if ($targets.Count -eq 0) {
        Show-RamInfo (Get-RamText -Text 'В профиле «{0}» набор «{1}» пуст — некого запускать.' -Arguments @([string]($($Profile.Name)),[string]($($Profile.Group))))
        return
    }

    if ($script:LaunchQueue.Count -gt 0) {
        Show-RamInfo (Get-RamText -Text 'Сначала заверши или отмени текущую очередь в центре запуска, затем запускай другой сценарий.')
        return
    }
    $targets = @($targets | Where-Object { -not $script:Instances.ContainsKey([string]$_.Id) })
    if ($targets.Count -eq 0) { Set-RamStatus (Get-RamText -Text 'Все аккаунты сценария уже работают.'); return }
    try {
        if ($Profile.PSObject.Properties.Name -contains 'TileMode' -and [string]$Profile.TileMode -notin @('grid','cascade','columns','rows','main')) { throw 'В сценарии неизвестная раскладка окон.' }
        foreach ($field in @('AutoTile','UseSavedWindows')) {
            if ($Profile.PSObject.Properties.Name -contains $field -and $Profile.$field -isnot [bool]) { throw "В сценарии неверное значение $field." }
        }
        if ($Profile.PSObject.Properties.Name -contains 'TileColumns' -and ([string]$Profile.TileColumns -notmatch '^\d{1,2}$' -or [int]$Profile.TileColumns -gt 20)) { throw 'В сценарии неверное число колонок.' }
        if ($Profile.PSObject.Properties.Name -contains 'MainAccountId' -and
            (@($Profile.Ids) -notcontains [string]$Profile.MainAccountId -or $null -eq (Get-RamAccountById -Id ([string]$Profile.MainAccountId)))) { throw 'Основной аккаунт сценария не найден. Пересохрани сценарий.' }
        $prepared = @(ConvertTo-RamProfileTargets -Profile $Profile -Accounts $targets)
    } catch { Show-RamError $_.Exception.Message; return }
    $queuedIds = @(Add-RamToLaunchQueue -Accounts $prepared -PassThru)
    if ($queuedIds.Count -eq 0) { return }
    $targets = @($targets | Where-Object { $queuedIds -contains [string]$_.Id })
    $plan = @{}
    foreach ($copy in $prepared) { $plan[[string]$copy.Id] = $copy }
    Push-RamUndo -Label (Get-RamText -Text 'настройки сценария «{0}»' -Arguments @([string]($($Profile.Name)))) -IncludeLayout
    foreach ($target in $targets) {
        foreach ($field in @('PlaceId','GameName','JobId','LinkCode','Graphics','FramerateCap','Volume','Fullscreen')) { $target.$field = $plan[[string]$target.Id].$field }
    }
    foreach ($field in @('TileMode','TileColumns','AutoTile','UseSavedWindows','MainAccountId')) {
        if ($Profile.PSObject.Properties.Name -contains $field) { $script:Settings.$field = $Profile.$field }
    }
    Save-RamState
    Build-RamCards

    Write-RamLog (Get-RamText -Text 'Профиль «{0}»: запускаю {1} аккаунтов.' -Arguments @([string]($($Profile.Name)),[string]($($targets.Count)))) 'ok'
}

function Invoke-RamSaveProfile {
    <# Сохраняет текущее состояние выбранного набора как профиль. #>
    $targets = @(Get-RamActionTargets -What (Get-RamText -Text 'сохранение в профиль'))
    if ($targets.Count -eq 0) { return }

    $name = Show-RamInputDialog -Title (Get-RamText -Text 'Новый сценарий запуска') `
              -Prompt (Get-RamText -Text 'Сценарий запомнит выбранные аккаунты, игру и настройки каждого, а также раскладку окон. Например «Основа + твинки». Запуск — одной кнопкой.')
    if ([string]::IsNullOrWhiteSpace($name)) { return }

    $entry = New-RamLaunchProfile -Name $name -Accounts $targets

    $rest = @(Get-RamProfiles | Where-Object { $_.Name -ne $entry.Name })
    $script:Settings.Profiles = @(@($entry) + $rest | Select-Object -First 20)
    Save-RamSettings -Settings $script:Settings
    Update-RamProfilesPanel
    Write-RamLog (Get-RamText -Text 'Профиль «{0}» сохранён.' -Arguments @([string]($($entry.Name)))) 'ok'
    # Раздел «Профили» человек в этот момент обычно не видит — он на
    # «Аккаунтах». Без ответа кнопка выглядела не сработавшей.
    Show-RamMessage -Kind 'ok' -Message ((Get-RamText -Text 'Профиль «{0}» сохранён.' -Arguments @([string]($($entry.Name)))) + [Environment]::NewLine +
                                         [Environment]::NewLine + (Get-RamText -Text 'Аккаунтов в нём: {0}. Свои настройки сохранены для каждого. Запускать — в разделе «Сценарии».' -Arguments @([string]($($targets.Count)))))
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

    Write-RamLog (Get-RamText -Text 'Присмотр за набором «{0}»: не в игре {1}, поднимаю.' -Arguments @([string]($group),[string]($($missing.Count)))) 'warn'
    Add-RamToLaunchQueue -Accounts $missing -Unattended
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
    $ways += (Get-RamText -Text 'Открыть окно браузера и войти руками')
    if ([bool]$script:Settings.BridgeEnabled) {
        $ways += (Get-RamText -Text 'Или: открой roblox.com в своём браузере под «{0}» и нажми {1}' -Arguments @([string]($($acc.Alias)),[string]($($script:Settings.BridgeHotkey))))
    }

    $msg = (Get-RamText -Text 'Вход в «{0}» умер.' -Arguments @([string]($($acc.Alias)))) + [Environment]::NewLine + [Environment]::NewLine +
           (Get-RamText -Text 'Продлить его нечем — Roblox не отдаёт новую куку ни на один запрос, это проверено. Нужно войти заново.') +
           [Environment]::NewLine + [Environment]::NewLine + ($ways -join ([Environment]::NewLine)) +
           [Environment]::NewLine + [Environment]::NewLine + (Get-RamText -Text 'Открыть окно браузера сейчас?')

    if (-not (Confirm-Ram $msg)) { return }

    $cookie = $null
    try {
        $cookie = Show-RamExternalBrowserLoginWindow
    } catch {
        Write-RamLog (Get-RamText -Text 'Повторный вход: {0}' -Arguments @([string]((Get-RamErrorText -Text ($($_.Exception.Message)))))) 'err'
        Show-RamError -Text ((Get-RamText -Text 'Не удалось открыть окно входа:') + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message)
        return
    }
    if (-not $cookie) {
        # Раньше здесь была только строка в журнал. Человек закрывал окно
        # или ждал таймаута — и не получал ничего, то есть не мог отличить
        # «я сам отменил» от «программа сломалась».
        Write-RamLog (Get-RamText -Text 'Повторный вход: окно закрыто без входа.') 'warn'
        Show-RamMessage -Kind 'warn' -Message (
            (Get-RamText -Text 'Вход в «{0}» не обновлён.' -Arguments @([string]($($acc.Alias)))) + [Environment]::NewLine + [Environment]::NewLine +
            (Get-RamText -Text 'Окно браузера закрылось раньше, чем вход прошёл: либо ты закрыл его сам, либо истекло время ожидания.') +
            [Environment]::NewLine + [Environment]::NewLine + (Get-RamText -Text 'Можно попробовать ещё раз.'))
        return
    }

    $r = Import-RamAccountLine -Line $cookie
    if ($null -eq $r -or -not $r.Ok) {
        $why = if ($r -and $r.Error) { $r.Error } else { (Get-RamText -Text 'Roblox не подтвердил вход') }
        Show-RamError -Text ((Get-RamText -Text 'Вход не подошёл:') + [Environment]::NewLine + [Environment]::NewLine + $why)
        return
    }

    Save-RamState
    Build-RamCards
    if ($r.Alias -eq $acc.Alias) {
        Write-RamLog (Get-RamText -Text 'Вход в «{0}» обновлён.' -Arguments @([string]($($acc.Alias)))) 'ok'
        Show-RamMessage -Message (Get-RamText -Text 'Готово: вход в «{0}» снова живой.' -Arguments @([string]($($acc.Alias))))
    } else {
        # Вошли под другим аккаунтом — не молчим об этом: старый как был
        # мёртвым, так и остался, а в списке появился ещё один.
        Write-RamLog (Get-RamText -Text 'Ожидался «{0}», а вошли под «{1}» — добавлен отдельным аккаунтом.' -Arguments @([string]($($acc.Alias)),[string]($($r.Alias)))) 'warn'
        Show-RamMessage -Message ((Get-RamText -Text 'Вошли под «{0}», а не под «{1}».' -Arguments @([string]($($r.Alias)),[string]($($acc.Alias)))) + [Environment]::NewLine + [Environment]::NewLine +
                                  (Get-RamText -Text 'Он добавлен в список, но вход в «{0}» так и остался мёртвым.' -Arguments @([string]($($acc.Alias)))))
    }
}
