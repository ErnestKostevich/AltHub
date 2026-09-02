#requires -Version 5.1
<#
================================================================================
 modules\UiMain.ps1 — главное окно и его разделы
================================================================================
 Карточки аккаунтов, боковое меню, разделы «Аккаунты», «Игры», «Профили»,
 «Статистика» и «Журнал», значок в часах и сборка самого окна.
================================================================================
#>

# --------------------------------------------------------- карточки ---------

function Get-RamCardWidth {
    if (-not $script:UI.ContainsKey('Cards')) { return 1000 }
    return [Math]::Max(700, $script:UI.Cards.ClientSize.Width - 24)
}

function Get-RamLabelColors {
    <# Цветные метки для группировки глазом. #>
    $t = $Global:RamTheme
    return @(
        [pscustomobject]@{ Key = '';       Text = 'без метки'; Color = $t.Border },
        [pscustomobject]@{ Key = 'red';    Text = 'красная';   Color = [System.Drawing.Color]::FromArgb(239,  68,  68) },
        [pscustomobject]@{ Key = 'orange'; Text = 'оранжевая'; Color = [System.Drawing.Color]::FromArgb(245, 158,  11) },
        [pscustomobject]@{ Key = 'green';  Text = 'зелёная';   Color = [System.Drawing.Color]::FromArgb( 34, 197,  94) },
        [pscustomobject]@{ Key = 'blue';   Text = 'синяя';     Color = [System.Drawing.Color]::FromArgb( 59, 130, 246) },
        [pscustomobject]@{ Key = 'purple'; Text = 'фиолетовая';Color = [System.Drawing.Color]::FromArgb(168,  85, 247) }
    )
}

function Get-RamLabelColor {
    param([string]$Key)
    $found = Get-RamLabelColors | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    if ($null -eq $found -or [string]::IsNullOrWhiteSpace($Key)) { return $null }
    return $found.Color
}

function Get-RamGroups {
    <# Все существующие наборы, по алфавиту. #>
    $g = @()
    foreach ($a in $script:Accounts) {
        $name = [string]$a.Group
        if (-not [string]::IsNullOrWhiteSpace($name) -and $g -notcontains $name) { $g += $name }
    }
    return @($g | Sort-Object)
}

function Get-RamOrderedAccounts {
    <# Порядок в списке задаётся полем Order — оно меняется перетаскиванием. #>
    $i = 0
    foreach ($a in $script:Accounts) {
        if ([int]$a.Order -eq 0) { $a.Order = ++$i * 10 }
    }
    return @($script:Accounts | Sort-Object { [int]$_.Order })
}

function Set-RamAccountOrder {
    <# Переставляет аккаунт на новое место в списке. #>
    param([string]$Id, [int]$NewIndex)

    $ordered = @(Get-RamOrderedAccounts)
    $moving  = $ordered | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($null -eq $moving) { return $false }

    $rest = @($ordered | Where-Object { $_.Id -ne $Id })
    if ($NewIndex -lt 0) { $NewIndex = 0 }
    if ($NewIndex -gt $rest.Count) { $NewIndex = $rest.Count }

    $final = @()
    if ($NewIndex -gt 0) { $final += $rest[0..($NewIndex - 1)] }
    $final += $moving
    if ($NewIndex -lt $rest.Count) { $final += $rest[$NewIndex..($rest.Count - 1)] }

    $step = 0
    foreach ($a in $final) { $a.Order = ($step += 10) }
    return $true
}

function Test-RamAccountMatches {
    <# Подходит ли аккаунт под строку поиска. Ищем по названию, нику, ID,
       игре, заметке и набору. #>
    param($Account, [string]$Query)

    if ([string]::IsNullOrWhiteSpace($Query)) { return $true }
    $q = $Query.Trim()

    foreach ($field in @($Account.Alias, $Account.Username, [string]$Account.UserId,
                         $Account.GameName, [string]$Account.PlaceId,
                         $Account.Note, $Account.Group)) {
        if ($field -and $field.ToString().IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Get-RamVisibleAccounts {
    <# Что показывать: с учётом поиска и выбранного набора. #>
    $list = @(Get-RamOrderedAccounts)

    if (-not [string]::IsNullOrWhiteSpace($script:GroupFilter)) {
        $list = @($list | Where-Object { [string]$_.Group -eq $script:GroupFilter })
    }
    return @($list | Where-Object { Test-RamAccountMatches -Account $_ -Query $script:Filter })
}

function Build-RamCards {
    <# Полная пересборка списка карточек. Вызывается при изменении состава,
       фильтра, порядка или режима отображения. #>
    if (-not $script:UI.ContainsKey('Cards')) { return }

    $t      = $Global:RamTheme
    $host_  = $script:UI.Cards
    $W      = Get-RamCardWidth
    $compact = [bool]$script:Settings.CompactCards
    $cardH  = if ($compact) { 56 } else { 92 }

    # Запоминаем отметки, чтобы не сбрасывались.
    $checked = @{}
    foreach ($id in $script:Cards.Keys) {
        if ($script:Cards[$id].Check.Tag.Checked) { $checked[$id] = $true }
    }

    $host_.SuspendLayout()
    try {
        # Controls.Clear() только вынимает элементы из списка. Каждый из них —
        # это окно Windows со своими ресурсами GDI, и без Dispose они висят до
        # сборки мусора. На пересборке по каждой букве в поиске это утекало
        # заметно, поэтому освобождаем явно.
        foreach ($old in @($host_.Controls)) {
            try {
                if ($null -ne $old.ContextMenuStrip) { $old.ContextMenuStrip.Dispose(); $old.ContextMenuStrip = $null }
                $old.Dispose()
            } catch { }
        }
        $host_.Controls.Clear()
        $script:Cards = @{}
        $script:AvatarQueue.Clear()

        $visible = @(Get-RamVisibleAccounts)

        if (@($script:Accounts).Count -eq 0) {
            $empty = New-RamCard -Width $W -Height 150
            $host_.Controls.Add($empty)
            $empty.Controls.Add((New-RamLabel -Text 'Пока ни одного аккаунта' -X 28 -Y 30 -Width 500 -Height 28 -Font $t.FontTitle))
            $empty.Controls.Add((New-RamLabel -Text 'Войди в приложении Roblox под нужным аккаунтом и нажми «Добавить» вверху — менеджер заберёт вход сам, пароль вводить не надо.' `
                                              -X 28 -Y 62 -Width ($W - 56) -Height 44 -Font $t.FontBody -Color $t.Muted))
            return
        }

        if ($visible.Count -eq 0) {
            $none = New-RamCard -Width $W -Height 92
            $host_.Controls.Add($none)
            $why = if ($script:GroupFilter) { "В наборе «$($script:GroupFilter)» ничего не нашлось" }
                   else { "По запросу «$($script:Filter)» ничего не нашлось" }
            $none.Controls.Add((New-RamLabel -Text $why -X 28 -Y 22 -Width ($W - 56) -Height 26 -Font $t.FontTitle))
            $none.Controls.Add((New-RamLabel -Text 'Сбрось поиск или выбери набор «Все» вверху' `
                                             -X 28 -Y 50 -Width ($W - 56) -Height 22 -Font $t.FontBody -Color $t.Muted))
            return
        }

        foreach ($a in $visible) {
            $card = New-RamCard -Width $W -Height $cardH
            $card.Tag.AccountId = $a.Id
            $card.Tag | Add-Member -NotePropertyName Stripe `
                                   -NotePropertyValue (Get-RamLabelColor -Key ([string]$a.Color)) -Force
            $host_.Controls.Add($card)

            # Цветная метка рисуется полоской слева
            $card.Add_Paint({
                param($s, $e)
                if ($null -eq $s.Tag.Stripe) { return }
                $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $r = New-Object System.Drawing.Rectangle(1, 8, 5, ($s.Height - 16))
                $path = New-RamRoundRect -Rect $r -Radius 2
                $b = New-Object System.Drawing.SolidBrush($s.Tag.Stripe)
                $e.Graphics.FillPath($b, $path)
                $b.Dispose(); $path.Dispose()
            })

            if ($compact) {
                $chk = New-RamCheckBox -X 18 -Y 18
                # Аватарку сдвигаем за галочкой: та растёт вместе со шрифтом.
                $avSize = 32; $avY = 12; $avX = [Math]::Max(46, (18 + $chk.Width + 8))
                # 5, а не 7: имя рисуется шрифтом покрупнее и высотой 24,
                # поэтому при подписи на Y=26 они налезали друг на друга.
                $nameY = 4; $subY = 28; $nameX = 88; $nameW = 200
                $gameX = 300; $gameY = 17; $gameW = 210
                $dotX  = 528; $dotY = 17
                $btnY  = 12; $btnH = 32
            } else {
                $chk = New-RamCheckBox -X 18 -Y 36
                $avSize = 52; $avY = 20; $avX = [Math]::Max(48, (18 + $chk.Width + 8))
                $nameY = 13; $subY = 37; $nameX = 112; $nameW = 236
                $gameX = 360; $gameY = 32; $gameW = 240
                $dotX  = 640; $dotY = 36
                $btnY  = 29; $btnH = 34
            }

            $chk.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
            if ($checked.ContainsKey($a.Id)) { $chk.Tag.Checked = $true }
            $card.Controls.Add($chk)

            $av = New-RamAvatarBox -Size $avSize
            $av.Location = New-Object System.Drawing.Point($avX, $avY)
            $card.Controls.Add($av)
            Set-RamAvatarImage -Box $av -Image $null -Letter $(if ($a.Alias) { $a.Alias } else { '?' })

            $cached = $null
            if ([int64]$a.UserId -gt 0) {
                $file = Join-Path (Get-RamAvatarDir) "$($a.UserId).png"
                if (Test-Path -LiteralPath $file) { $cached = Get-RamImageFromFile -Path $file }
            }
            if ($null -ne $cached) { Set-RamAvatarImage -Box $av -Image $cached -Letter $a.Alias }

            # Имя и набор — две отдельные подписи. Раньше они склеивались в одну
            # строку фиксированной ширины, и длинное название набора обрезалось
            # прямо посреди слова. Теперь ширину имени меряем, а набору отдаём
            # то, что осталось.
            # Место сначала отдаём набору (он короткий и должен читаться целиком),
            # остаток — имени. Раньше было наоборот, и название набора обрезалось
            # посреди слова.
            $maxTextW = $gameX - $nameX - 14

            $groupW = 0
            $showGroup = (-not $compact) -and (-not [string]::IsNullOrWhiteSpace($a.Group))
            if ($showGroup) {
                $groupW = [System.Windows.Forms.TextRenderer]::MeasureText($a.Group, $t.FontSmall).Width + 12
                if ($groupW -gt 150) { $groupW = 150 }
                # Имени должно остаться хотя бы на пару слов.
                if ($maxTextW - $groupW - 8 -lt 70) { $groupW = 0; $showGroup = $false }
            }

            $aliasW = $maxTextW - $groupW - $(if ($showGroup) { 8 } else { 0 })
            $aliasNeed = [System.Windows.Forms.TextRenderer]::MeasureText($a.Alias, $t.FontTitle).Width + 6
            if ($aliasNeed -lt $aliasW) { $aliasW = $aliasNeed }

            # Высота имени — по шрифту, а не «24 всегда»: на крупном масштабе
            # заголовок выше, и фиксированная высота давала наложение.
            # Ограничиваем расстоянием до подписи под ней — в ОБОИХ режимах.
            $nameH = [Math]::Max(18, (Measure-RamText -Text 'Ay' -Font $t.FontTitle).Height + 2)
            $nameH = [Math]::Min($nameH, ($subY - $nameY))
            $lblName = New-RamLabel -Text $a.Alias -X $nameX -Y $nameY -Width $aliasW -Height $nameH `
                                    -Font $t.FontTitle -Truncatable
            $card.Controls.Add($lblName)

            $lblGroup = $null
            if ($showGroup) {
                $lblGroup = New-RamLabel -Text $a.Group -X ($nameX + $aliasW + 8) -Y ($nameY + 3) `
                                         -Width $groupW -Height 20 -Font $t.FontSmall -Color $t.Accent -Truncatable
                $card.Controls.Add($lblGroup)
            }

            $sub = if ($a.Username) { "@$($a.Username)  ·  ID $($a.UserId)" } else { 'вход не проверен' }
            # Коротко: длинная подсказка съедала строку целиком и прятала ник.
            # Что делать — написано на красной кнопке внизу.
            if ([string]$a.CookieOk -eq 'no') { $sub = 'вход мёртв   ·   ' + $sub }
            if ($compact -and -not [string]::IsNullOrWhiteSpace($a.Group)) { $sub = "[$($a.Group)]  $sub" }
            $subColor = if ([string]$a.CookieOk -eq 'no') { $t.Danger } else { $t.Muted }
            $lblSub = New-RamLabel -Text $sub -X $nameX -Y $subY -Width $maxTextW -Height 20 `
                                   -Font $t.FontSmall -Color $subColor -Truncatable
            $card.Controls.Add($lblSub)

            $lblNote = $null
            if (-not $compact -and -not [string]::IsNullOrWhiteSpace($a.Note)) {
                $lblNote = New-RamLabel -Text $a.Note -X $nameX -Y 60 -Width $maxTextW -Height 20 `
                                        -Font $t.FontSmall -Color $t.Muted -Truncatable
                $card.Controls.Add($lblNote)
            }

            if (-not $compact) {
                $card.Controls.Add((New-RamLabel -Text 'ИГРА' -X $gameX -Y 14 -Width 100 -Height 16 -Font $t.FontSmall -Color $t.Muted))
            }

            $gameTxt = if ($a.GameName) { $a.GameName }
                       elseif ($a.PlaceId) { "ID $($a.PlaceId)" }
                       else { 'просто Roblox' }
            if ($a.LinkCode) { $gameTxt += '  · приват' }
            $lblGame = New-RamLabel -Text $gameTxt -X $gameX -Y $gameY -Width $gameW -Height 22 `
                                    -Color $(if ($a.PlaceId) { $t.Text } else { $t.Muted }) -Truncatable
            $card.Controls.Add($lblGame)

            if (-not $compact) {
                $summary = Get-RamAccountSettingsSummary -Account $a
                if ($summary) {
                    $card.Controls.Add((New-RamLabel -Text $summary -X $gameX -Y 58 -Width 280 -Height 20 `
                                                    -Font $t.FontSmall -Color $t.Muted -Truncatable))
                }

                # Справка: Robux, Premium, дата регистрации
                $facts = @()
                if ([int]$a.Robux -ge 0)      { $facts += "$($a.Robux) R$" }
                if ([string]$a.Premium -eq 'yes') { $facts += 'Premium' }
                if ($a.Created)               { $facts += "с $($a.Created)" }
                if ($facts.Count -gt 0) {
                    # Truncatable: это справка, а не управление. На крупном
                    # масштабе она длиннее места, и многоточие тут уместнее,
                    # чем распирать карточку.
                    $card.Controls.Add((New-RamLabel -Text ($facts -join '  ·  ') -X 660 -Y 58 -Width 220 -Height 20 `
                                                    -Font $t.FontSmall -Color $t.Muted -Truncatable))
                }
            }

            $dot = New-RamStatusDot -X $dotX -Y $dotY -Width 150
            $card.Controls.Add($dot)

            # -Fixed: это квадратные значки, их ширина задана намеренно.
            # Без него кнопка подгоняется под текст и налезает на соседнюю.
            $bPlay = New-RamButton -Text '▶' -Width 46 -Height $btnH -Fixed -Kind 'primary' -Tooltip 'Запустить этот аккаунт' -OnClick {
                Add-RamToLaunchQueue -Accounts @((Get-RamAccountById -Id $this.Tag.AccountId))
            }
            $bPlay.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
            $bPlay.Location = New-Object System.Drawing.Point(($W - 172), $btnY)
            $card.Controls.Add($bPlay)

            $bEdit = New-RamButton -Text '✎' -Width 46 -Height $btnH -Fixed -Tooltip 'Настройки аккаунта' -OnClick {
                $old = Get-RamAccountById -Id $this.Tag.AccountId
                if ($null -eq $old) { return }
                $new = Show-RamAccountDialog -Account $old
                if ($null -ne $new) {
                    foreach ($p in $new.PSObject.Properties.Name) { $old.$p = $new.$p }
                    Save-RamState
                    Build-RamCards
                    Write-RamLog "Изменён аккаунт '$($old.Alias)'." 'ok'
                }
            }
            $bEdit.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
            $bEdit.Location = New-Object System.Drawing.Point(($W - 120), $btnY)
            $card.Controls.Add($bEdit)

            $bStop = New-RamButton -Text '■' -Width 46 -Height $btnH -Fixed -Tooltip 'Закрыть окно этого аккаунта' -OnClick {
                $inst = $script:Instances[$this.Tag.AccountId]
                if ($null -eq $inst) { return }
                $acc = Get-RamAccountById -Id $this.Tag.AccountId
                if (Stop-RamRobloxInstance -ProcessId $inst.ProcessId) {
                    Write-RamLog "'$($acc.Alias)' закрыт." 'ok'
                }
                $script:Instances.Remove($this.Tag.AccountId)
                Update-RamCardStates
            }
            $bStop.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
            $bStop.Location = New-Object System.Drawing.Point(($W - 68), $btnY)
            $card.Controls.Add($bStop)

            # --- клик по пустому месту переключает отметку
            $toggle = {
                if ($script:DragMoved) { return }   # это было перетаскивание, а не клик
                $c = $this
                while ($null -ne $c -and $null -eq $c.Tag.AccountId) { $c = $c.Parent }
                if ($null -eq $c) { return }
                $entry = $script:Cards[$c.Tag.AccountId]
                if ($null -eq $entry) { return }
                $entry.Check.Tag.Checked = -not $entry.Check.Tag.Checked
                $entry.Check.Invalidate()
                Update-RamStatusLine
            }

            # --- перетаскивание карточки меняет порядок
            $dragDown = {
                param($s, $e)
                if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
                $c = $s
                while ($null -ne $c -and $null -eq $c.Tag.AccountId) { $c = $c.Parent }
                if ($null -eq $c) { return }
                $script:DragId    = $c.Tag.AccountId
                $script:DragMoved = $false
                $script:DragStart = [System.Windows.Forms.Cursor]::Position.Y
            }
            $dragMove = {
                param($s, $e)
                if ([string]::IsNullOrEmpty($script:DragId)) { return }
                if ([Math]::Abs([System.Windows.Forms.Cursor]::Position.Y - $script:DragStart) -gt 12) {
                    $script:DragMoved = $true
                    $script:UI.Cards.Cursor = [System.Windows.Forms.Cursors]::SizeNS
                }
            }
            $dragUp = {
                param($s, $e)
                if ([string]::IsNullOrEmpty($script:DragId)) { return }
                $id = $script:DragId
                $script:DragId = ''
                $script:UI.Cards.Cursor = [System.Windows.Forms.Cursors]::Default
                if (-not $script:DragMoved) { return }

                $host2 = $script:UI.Cards
                $pt = $host2.PointToClient([System.Windows.Forms.Cursor]::Position)
                $rowH = $(if ($script:Settings.CompactCards) { 56 } else { 92 }) + 8
                $logicalY = $pt.Y - $host2.AutoScrollPosition.Y
                $idx = [int][math]::Floor($logicalY / $rowH)

                if (Set-RamAccountOrder -Id $id -NewIndex $idx) {
                    Save-RamState
                    Build-RamCards
                }
            }

            $clickable = @($card, $lblName, $lblSub, $lblGame, $av)
            if ($null -ne $lblGroup) { $clickable += $lblGroup }
            foreach ($ctl in $clickable) {
                $ctl.Add_MouseDown($dragDown)
                $ctl.Add_MouseMove($dragMove)
                $ctl.Add_MouseUp($dragUp)
                $ctl.Add_Click($toggle)
            }
            if ($null -ne $lblNote) { $lblNote.Add_Click($toggle) }

            # Правый клик по карточке — меню действий ровно для неё.
            $menu = New-RamCardMenu -AccountId $a.Id
            foreach ($ctl in $clickable) { $ctl.ContextMenuStrip = $menu }
            if ($null -ne $lblNote) { $lblNote.ContextMenuStrip = $menu }
            $dot.ContextMenuStrip = $menu

            $script:Cards[$a.Id] = @{
                Card = $card; Check = $chk; Avatar = $av
                Name = $lblName; Sub = $lblSub; Game = $lblGame; Dot = $dot
                Play = $bPlay; Stop = $bStop
                AvatarLoaded = ($null -ne $cached)
            }

            if ([int64]$a.UserId -gt 0 -and $null -eq $cached) { [void]$script:AvatarQueue.Add($a.Id) }
        }
    } finally {
        $host_.ResumeLayout()
    }

    Update-RamCardStates
    Update-RamHeaderCounts
    Update-RamGroupBar
    Update-RamStatusLine
}

function Update-RamCardStates {
    <# Обновляет только статусы — вызывается по таймеру, карточки не пересоздаёт. #>
    $t = $Global:RamTheme

    foreach ($a in $script:Accounts) {
        $entry = $script:Cards[$a.Id]
        if ($null -eq $entry) { continue }

        $inst = $script:Instances[$a.Id]
        if ($null -ne $inst) {
            if ($inst.Handle -ne [IntPtr]::Zero) {
                Set-RamStatusDot -Dot $entry.Dot -Caption 'в игре' -Color $t.Ok
            } else {
                Set-RamStatusDot -Dot $entry.Dot -Caption 'загружается...' -Color $t.Warn
            }
        } elseif ($script:LaunchQueue -contains $a.Id) {
            Set-RamStatusDot -Dot $entry.Dot -Caption 'в очереди' -Color $t.Accent
        } else {
            Set-RamStatusDot -Dot $entry.Dot -Caption 'не запущен' -Color $t.Muted
        }
    }
    Update-RamHeaderCounts
    Update-RamStatusLine
}

function Update-RamOneAvatar {
    <#
      Аватарки грузятся НЕ БЛОКИРУЯ окно.

      Раньше здесь был обычный синхронный запрос, да ещё и три подряд за такт
      двухсекундного таймера. При таймауте клиента 25 секунд и мёртвой сети
      окно замирало почти на две с половиной минуты за один тик — это и была
      самая дорогая операция во всей программе.

      Теперь это маленький автомат: за такт делается ОДИН короткий шаг.
      Если запрос ещё в пути — сразу выходим, не потратив ничего.

      Шаги:
        нет задачи + очередь не пуста -> спросить адрес картинки
        адрес получен                 -> начать скачивание
        картинка скачана              -> сохранить и показать
    #>

    # --- есть незавершённая задача?
    if ($null -ne $script:AvatarJob) {
        $job = $script:AvatarJob
        if (-not $job.Net.Task.IsCompleted) { return }   # ещё летит, ждать не будем

        $script:AvatarJob = $null
        $a = Get-RamAccountById -Id $job.Id
        $entry = $script:Cards[$job.Id]

        if ($job.Stage -eq 'url') {
            $r = Complete-RamGetAsync -Job $job.Net
            $imageUrl = ''
            if ($r.Ok) {
                try {
                    $data = ($r.Body | ConvertFrom-Json).data
                    if ($data -and $data.Count -gt 0) { $imageUrl = [string]$data[0].imageUrl }
                } catch { }
            }
            if ([string]::IsNullOrWhiteSpace($imageUrl) -or $null -eq $a) {
                $script:AvatarSkip[[string]$job.UserId] = [int]$script:AvatarSkip[[string]$job.UserId] + 1
                return
            }
            $script:AvatarJob = [pscustomobject]@{
                Id = $job.Id; UserId = $job.UserId; Stage = 'img'
                Net = (Start-RamGetAsync -Url $imageUrl -TimeoutSec 10)
            }
            return
        }

        # --- пришла сама картинка
        $r = Complete-RamGetAsync -Job $job.Net -AsBytes
        if (-not $r.Ok -or $null -eq $r.Bytes -or $r.Bytes.Length -lt 100) {
            $script:AvatarSkip[[string]$job.UserId] = [int]$script:AvatarSkip[[string]$job.UserId] + 1
            return
        }
        try {
            $dir = Get-RamAvatarDir
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $file = Join-Path $dir "$($job.UserId).png"
            [System.IO.File]::WriteAllBytes($file, $r.Bytes)

            if ($null -ne $a -and $null -ne $entry) {
                $img = Get-RamImageFromFile -Path $file
                if ($null -ne $img) {
                    Set-RamAvatarImage -Box $entry.Avatar -Image $img -Letter $a.Alias
                    $entry.AvatarLoaded = $true
                }
            }
        } catch { }
        return
    }

    # --- задачи нет: берём следующего из очереди
    if ($script:AvatarQueue.Count -eq 0) { return }

    $id = $script:AvatarQueue[0]
    $script:AvatarQueue.RemoveAt(0)

    $a = Get-RamAccountById -Id $id
    $entry = $script:Cards[$id]
    if ($null -eq $a -or $null -eq $entry -or $a.UserId -le 0) { return }

    # Два неудачных захода подряд — больше не дёргаем до перезапуска.
    # Иначе при недоступном интернете очередь долбится вечно.
    if ([int]$script:AvatarSkip[[string]$a.UserId] -ge 2) { return }

    # Свежая копия уже лежит в кэше — сеть не нужна вовсе.
    $cached = Get-RamCachedAvatarFile -UserId $a.UserId -CacheDir (Get-RamAvatarDir)
    if ($null -ne $cached) {
        $img = Get-RamImageFromFile -Path $cached
        if ($null -ne $img) {
            Set-RamAvatarImage -Box $entry.Avatar -Image $img -Letter $a.Alias
            $entry.AvatarLoaded = $true
        }
        return
    }

    $script:AvatarJob = [pscustomobject]@{
        Id = $id; UserId = $a.UserId; Stage = 'url'
        Net = (Start-RamGetAsync -Url (Get-RamAvatarUrl -UserId $a.UserId) -TimeoutSec 10)
    }
}

function Set-RamCookieAlive {
    <# Пометить вход живым — после удачной проверки или починки. #>
    param([Parameter(Mandatory)]$Account)
    $Account.CookieOk        = 'yes'
    $Account.CookieCheckedAt = (Get-Date).ToString('s')
}

function Clear-RamAppSession {
    <#
      Заставляет приложение Roblox забыть текущий вход, НЕ разлогинивая
      аккаунт на сервере: файл входа уезжает в копию, а сама сессия остаётся
      живой. Возвращает $true, если получилось.

      Менять аккаунт надо именно так. Кнопка «Выйти» внутри Roblox убивает
      вход на сервере — и сохранённая здесь кука мгновенно становится
      мёртвой. С этого начинается почти каждое «аккаунт перестал запускаться».
    #>
    param([string]$Label = 'session')

    $running = @(Get-RamRobloxProcesses)
    if ($running.Count -gt 0) {
        if (-not (Confirm-Ram "Чтобы сменить аккаунт, надо закрыть Roblox (открыто окон: $($running.Count)).`n`nЗакрыть сейчас?")) { return $false }
        foreach ($p in $running) { [void](Stop-RamRobloxInstance -ProcessId $p.Id) }
        Start-Sleep -Milliseconds 2000
    }

    try {
        $backup = Clear-RamRobloxSession -Label $Label
        Write-RamLog ('Вход приложения отложен в копию: ' + (Split-Path -Leaf $backup)) 'ok'
        return $true
    } catch {
        Show-RamError $_.Exception.Message
        return $false
    }
}

function Build-RamCardMenuItems {
    <#
      Наполняет меню карточки пунктами по текущему состоянию аккаунта.
      Возвращает $false, если аккаунта уже нет — тогда меню не открываем.

      Вынесено из обработчика отдельной функцией, чтобы Самопроверка могла
      позвать её напрямую и посмотреть, что получилось.
    #>
    param([Parameter(Mandatory)]$Menu, [Parameter(Mandatory)][string]$AccountId)

    $m   = $Menu
    $id  = $AccountId
    $acc = Get-RamAccountById -Id $id
    if ($null -eq $acc) { return $false }

    $t       = $Global:RamTheme
    $running = ($null -ne $script:Instances[$id])
    $dead    = ([string]$acc.CookieOk -eq 'no')

    $m.Items.Clear()

    [void](Add-RamMenuItem -Menu $m -Text $acc.Alias -Disabled)
    [void](Add-RamMenuItem -Menu $m -Separator)

    [void](Add-RamMenuItem -Menu $m -Text '▶  Запустить' -Tag $id -OnClick {
        Add-RamToLaunchQueue -Accounts @((Get-RamAccountById -Id ([string]$this.Tag)))
    })

    if ($running) {
        [void](Add-RamMenuItem -Menu $m -Text 'Показать окно' -Tag $id -OnClick {
            $inst = $script:Instances[[string]$this.Tag]
            if ($null -ne $inst -and $inst.Handle -ne [IntPtr]::Zero) {
                [void](Set-RamWindowForeground -Handle $inst.Handle)
            }
        })
        [void](Add-RamMenuItem -Menu $m -Text '■  Закрыть окно' -Tag $id -OnClick {
            $id2  = [string]$this.Tag
            $inst = $script:Instances[$id2]
            if ($null -eq $inst) { return }
            $acc2 = Get-RamAccountById -Id $id2
            if (Stop-RamRobloxInstance -ProcessId $inst.ProcessId) {
                Write-RamLog "'$($acc2.Alias)' закрыт." 'ok'
            }
            $script:Instances.Remove($id2)
            Update-RamCardStates
        })
    }

    [void](Add-RamMenuItem -Menu $m -Separator)

    [void](Add-RamMenuItem -Menu $m -Text 'Задать игру...' -Tag $id -OnClick {
        Invoke-RamAssignGame -Accounts @((Get-RamAccountById -Id ([string]$this.Tag)))
    })
    [void](Add-RamMenuItem -Menu $m -Text 'Настройки аккаунта...' -Tag $id -OnClick {
        $old = Get-RamAccountById -Id ([string]$this.Tag)
        if ($null -eq $old) { return }
        $new = Show-RamAccountDialog -Account $old
        if ($null -ne $new) {
            foreach ($p in $new.PSObject.Properties.Name) { $old.$p = $new.$p }
            Save-RamState
            Build-RamCards
            Write-RamLog "Изменён аккаунт '$($old.Alias)'." 'ok'
        }
    })

    # Готовые наборы — подменю, чтобы не растягивать основное на четыре пункта.
    # Ключ набора и аккаунт лежат в Tag одной строкой: обработчик берёт своё,
    # а не последнее из цикла.
    $sub = New-Object System.Windows.Forms.ToolStripMenuItem
    $sub.Text      = 'Готовый набор настроек'
    $sub.ForeColor = $t.Text
    $sub.Tag       = $id
    $cur = Get-RamMatchingPreset -Account $acc
    foreach ($p in Get-RamAccountPresets) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem
        $mi.Text      = $(if ([string]$p.Key -eq $cur) { '● ' + $p.Title } else { '    ' + $p.Title })
        $mi.ToolTipText = [string]$p.Hint
        $mi.ForeColor = $t.Text
        $mi.Tag       = ($id + '|' + $p.Key)
        $mi.Add_Click({
            $parts = ([string]$this.Tag) -split '\|'
            $acc2  = Get-RamAccountById -Id $parts[0]
            if ($null -eq $acc2) { return }
            if (Set-RamAccountPreset -Account $acc2 -Key $parts[1]) {
                Save-RamState
                Build-RamCards
                $pr = Get-RamPreset -Key $parts[1]
                Write-RamLog "'$($acc2.Alias)': набор «$($pr.Title)» — $(Get-RamAccountSettingsSummary -Account $acc2)." 'ok'
            }
        })
        [void]$sub.DropDownItems.Add($mi)
    }
    [void]$m.Items.Add($sub)

    $fixText  = if ($dead) { 'Починить вход  —  сейчас мёртв' } else { 'Обновить вход из приложения Roblox' }
    # Красный оставлен разрушительному пункту («Убрать»). Мёртвый вход — это
    # предупреждение, а не опасность: чинить его совершенно безопасно.
    $fixColor = if ($dead) { $t.Warn } else { $null }
    [void](Add-RamMenuItem -Menu $m -Text $fixText -Tag $id -Color $fixColor -OnClick {
        $acc2 = Get-RamAccountById -Id ([string]$this.Tag)
        if ($null -eq $acc2) { return }
        if (Invoke-RamRepairCookie -Account $acc2) {
            Set-RamCookieAlive -Account $acc2
            Save-RamState
            Build-RamCards
            Show-RamInfo "Вход «$($acc2.Alias)» на месте."
        }
    })

    [void](Add-RamMenuItem -Menu $m -Separator)

    [void](Add-RamMenuItem -Menu $m -Text 'Скопировать приглашение (для переноса себе)' -Tag $id -OnClick {
        $acc2 = Get-RamAccountById -Id ([string]$this.Tag)
        if ($null -eq $acc2) { return }
        if ([string]::IsNullOrWhiteSpace($acc2.Cookie)) { Show-RamInfo 'У этого аккаунта нет сохранённого входа.'; return }
        $code = ConvertTo-RamInviteCode -Account $acc2
        try { [System.Windows.Forms.Clipboard]::SetText($code) } catch { }
        Show-RamInfo ("Приглашение скопировано в буфер обмена.`n`nВнутри — доступ к аккаунту, поэтому это для переноса СЕБЕ на другой компьютер, а не для раздачи. " +
                      "На другом компьютере открой «Добавить» -> «Ещё способы» -> «Вставить пачкой» и вставь его.")
        Write-RamLog "Создано приглашение для «$($acc2.Alias)» (в буфер обмена)." 'info'
    })

    [void](Add-RamMenuItem -Menu $m -Separator)

    [void](Add-RamMenuItem -Menu $m -Text 'Убрать из менеджера' -Tag $id -Color $t.Danger -OnClick {
        Invoke-RamDeleteSelected -Accounts @((Get-RamAccountById -Id ([string]$this.Tag)))
    })

    return $true
}

function New-RamCardMenu {
    <#
      Меню по правому клику на карточке — то же, что кнопки, но без
      расстановки галочек: действие применяется ровно к этому аккаунту.

      Пункты пересобираются в момент открытия. Пока меню не открыли, аккаунт
      мог запуститься или вылететь, и «Закрыть окно» должно быть по факту,
      а не по тому, что было при отрисовке карточки.
    #>
    param([Parameter(Mandatory)][string]$AccountId)

    $menu = New-RamContextMenu
    $menu.Tag = $AccountId
    $menu.Add_Opening({
        param($s, $e)
        if (-not (Build-RamCardMenuItems -Menu $s -AccountId ([string]$s.Tag))) { $e.Cancel = $true }
    })
    return $menu
}


function Show-RamQuickSetup {
    <#
      Мастер быстрой настройки под типичный расклад: один основной аккаунт,
      которым играешь, и твины, которые просто стоят на приватном сервере.

      Что делает:
        основному  — свой набор, графика на максимум, звук включён;
        твинам     — свой набор, графика 1, звук 0, 30 FPS и общая игра;
        раскладка  — основной крупно, твины мелко справа;
        профиль    — «Твины на випку», чтобы поднимать их одной кнопкой.

      Ничего не делает молча: показывает, что именно поменяется, и спрашивает.
    #>
    param(
        # Только для Самопроверка.ps1: собрать окно и вернуть, не показывая.
        [switch]$BuildOnly
    )

    if (@($script:Accounts).Count -lt 2) {
        Show-RamInfo 'Для быстрой настройки нужно хотя бы два аккаунта: основной и твин.'
        return
    }

    $t = $Global:RamTheme

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Быстрая настройка'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size(690, 470)
    $dlg.Add_HandleCreated({ Set-RamDarkTitleBar $this })

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Size = New-Object System.Drawing.Size(660, 4); $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $dlg.Controls.Add((New-RamLabel -Text 'Быстрая настройка' -X 28 -Y 22 -Width 500 -Height 32 -Font $t.FontBig))

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = @'
Одним играешь, остальные стоят на приватном сервере.
  основному — графика на максимум, звук включён
  твинам    — графика 1, звук 0, 30 кадров, общая игра
  окна      — основной крупно слева, твины мелко справа
  профиль   — «Твины на випку», одной кнопкой
'@
    $hint.Location  = New-Object System.Drawing.Point(28, 60)
    $hint.Size      = New-Object System.Drawing.Size(604, 132)
    $hint.Font      = $t.FontBody
    $hint.ForeColor = $t.Muted
    $hint.BackColor = [System.Drawing.Color]::Transparent
    $dlg.Controls.Add($hint)

    $dlg.Controls.Add((New-RamLabel -Text 'ОСНОВНОЙ АККАУНТ — ИМ ТЫ ИГРАЕШЬ' -X 28 -Y 204 -Width 400 -Height 18 -Font $t.FontSmall -Color $t.Muted))
    $accItems = @()
    foreach ($a in (Get-RamOrderedAccounts)) {
        $lbl = $a.Alias
        if ($a.Username) { $lbl += "  (@$($a.Username))" }
        $accItems += [pscustomobject]@{ Text = $lbl; Value = $a.Id }
    }
    $cbMain = New-RamCombo -X 28 -Y 224 -Width 604 -Items $accItems -Value $accItems[0].Value
    $dlg.Controls.Add($cbMain)

    $dlg.Controls.Add((New-RamLabel -Text 'ИГРА ДЛЯ ТВИНОВ' -X 28 -Y 262 -Width 500 -Height 18 -Font $t.FontSmall -Color $t.Muted))

    $gameItems = @([pscustomobject]@{ Text = '— оставить как есть —'; Value = '' })
    foreach ($g in (Get-RamGameSuggestions)) { $gameItems += $g }
    $cbGame = New-RamCombo -X 28 -Y 282 -Width 604 -Items $gameItems -Value ''
    $dlg.Controls.Add($cbGame)

    $tbGame = New-RamTextBox -Width 480 -Height 32 -Value ''
    $tbGame.Location = New-Object System.Drawing.Point(28, 320)
    $dlg.Controls.Add($tbGame)

    $btnPaste = New-RamButton -Text 'Вставить' -Width 110 -Height 32 -OnClick {
        try {
            if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                $tbGame.Tag.Text = [System.Windows.Forms.Clipboard]::GetText().Trim()
            }
        } catch { }
    }
    $btnPaste.Location = New-Object System.Drawing.Point(522, 320)
    $dlg.Controls.Add($btnPaste)

    $dlg.Controls.Add((New-RamLabel -Text 'Поле важнее списка: если вставишь сюда ссылку, возьмётся она.' `
                                    -X 28 -Y 362 -Width 630 -Height 20 -Font $t.FontSmall -Color $t.Muted))

    $cbSameGame = New-RamCheckBox -X 28 -Y 384
    $dlg.Controls.Add($cbSameGame)
    # Подпись за галочкой: та растёт вместе со шрифтом.
    $lblSame = New-RamLabel -Text 'Основному поставить ту же игру' -X (28 + $cbSameGame.Width + 8) -Y 383 -Width 400 -Height 24
    $lblSame.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lblSame.Add_Click({ $cbSameGame.Tag.Checked = -not $cbSameGame.Tag.Checked; $cbSameGame.Invalidate() })
    $dlg.Controls.Add($lblSame)

    $btnGo = New-RamButton -Text 'Настроить' -Width 150 -Height 38 -Kind 'primary' -OnClick {
        $this.FindForm().Tag = $true; $this.FindForm().Close()
    }
    $btnGo.Location = New-Object System.Drawing.Point(340, 418)
    $dlg.Controls.Add($btnGo)

    $btnNo = New-RamButton -Text 'Отмена' -Width 130 -Height 38 -OnClick {
        $this.FindForm().Tag = $false; $this.FindForm().Close()
    }
    $btnNo.Location = New-Object System.Drawing.Point(502, 418)
    $dlg.Controls.Add($btnNo)
    $dlg.Tag = $false

    if ($BuildOnly) { return $dlg }

    [void]$dlg.ShowDialog()
    $go       = [bool]$dlg.Tag
    $mainId   = Get-RamComboValue $cbMain
    $gamePick = Get-RamComboValue $cbGame
    $gameText = $tbGame.Tag.Text.Trim()
    $sameGame = [bool]$cbSameGame.Tag.Checked
    $dlg.Dispose()

    if (-not $go) { return }

    # Разбираем игру: поле важнее выпадающего списка.
    $game = $null
    $raw = if ($gameText) { $gameText } else { $gamePick }
    if ($raw) {
        $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        try   { $game = Resolve-RamGameInput -Value $raw }
        catch { Show-RamError $_.Exception.Message; return }
        finally { $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::Default }
    }

    Push-RamUndo -Label 'быстрая настройка'
    $main   = Get-RamAccountById -Id $mainId
    $twinks = @($script:Accounts | Where-Object { $_.Id -ne $mainId })

    if ($null -eq $main) { Show-RamError 'Основной аккаунт не найден.'; return }

    # --- основной
    $main.Group        = 'Основной'
    $main.Color        = 'green'
    $main.Graphics     = '10'
    $main.Volume       = '80'
    $main.FramerateCap = ''
    $main.Fullscreen   = ''
    $main.Order        = 10
    if ($null -ne $game -and $sameGame -and $game.PlaceId) {
        $main.PlaceId  = $game.PlaceId
        $main.GameName = $game.GameName
        $main.LinkCode = $game.LinkCode
    }

    # --- твины
    $i = 1
    foreach ($a in $twinks) {
        $a.Group        = 'Твины'
        $a.Color        = 'blue'
        $a.Graphics     = '1'
        $a.Volume       = '0'
        $a.FramerateCap = '30'
        $a.Fullscreen   = 'no'
        $a.Order        = 10 + ($i++ * 10)
        if ($null -ne $game -and $game.PlaceId) {
            $a.PlaceId  = $game.PlaceId
            $a.GameName = $game.GameName
            $a.LinkCode = $game.LinkCode
        }
    }

    # --- раскладка и профиль
    $script:Settings.TileMode = 'main'
    $script:Settings.AutoTile = $true
    if ($null -ne $game -and $game.PlaceId) {
        Add-RamSavedGame -PlaceId $game.PlaceId -LinkCode $game.LinkCode `
                         -Title $(if ($game.GameName) { $game.GameName } else { "ID $($game.PlaceId)" })

        $prof = [pscustomobject]@{
            Name     = 'Твины на випку'
            Group    = 'Твины'
            PlaceId  = $game.PlaceId
            GameName = $game.GameName
            LinkCode = $game.LinkCode
        }
        $rest = @(Get-RamProfiles | Where-Object { $_.Name -ne $prof.Name })
        $script:Settings.Profiles = @(@($prof) + $rest | Select-Object -First 20)
    }

    Save-RamSettings -Settings $script:Settings
    Save-RamState
    Build-RamCards
    Update-RamProfilesPanel

    $what = if ($null -ne $game -and $game.GameName) { $game.GameName }
            elseif ($null -ne $game -and $game.PlaceId) { "ID $($game.PlaceId)" }
            else { 'игра не менялась' }

    Write-RamLog "Быстрая настройка: основной «$($main.Alias)», твинов $($twinks.Count), игра — $what." 'ok'
    Show-RamInfo ("Готово.`n`nОсновной: $($main.Alias) — графика 10, звук 80%.`n" +
                  "Твины ($($twinks.Count)): графика 1, звук 0, 30 кадров.`n" +
                  "Игра: $what`n`n" +
                  'Окна теперь раскладываются «основной крупно, твины мелко». ' +
                  'В разделе «Профили» появился «Твины на випку».')
}

function Invoke-RamScheduleCheck {
    <#
      Автозапуск по расписанию. Проверяется раз в 30 секунд.
      Срабатывает один раз за сутки в указанную минуту.
    #>
    if ($null -eq $script:Settings) { return }
    $time = [string]$script:Settings.AutoStartAtTime
    if ([string]::IsNullOrWhiteSpace($time)) { return }
    if ($time -notmatch '^(\d{1,2}):(\d{2})$') { return }

    $h = [int]$Matches[1]; $m = [int]$Matches[2]
    $now = Get-Date
    if ($now.Hour -ne $h -or $now.Minute -ne $m) { return }

    $today = $now.ToString('yyyy-MM-dd')
    if ($script:LastScheduleRun -eq $today) { return }
    $script:LastScheduleRun = $today

    $group = [string]$script:Settings.AutoStartGroup
    $targets = if ([string]::IsNullOrWhiteSpace($group)) { @(Get-RamOrderedAccounts) }
               else { @($script:Accounts | Where-Object { [string]$_.Group -eq $group }) }

    if ($targets.Count -eq 0) {
        Write-RamLog "Расписание ${time} сработало, но запускать нечего." 'warn'
        return
    }

    Write-RamLog "Расписание ${time}: поднимаю $($targets.Count) аккаунтов$(if($group){" из набора «$group»"})." 'ok'
    Add-RamToLaunchQueue -Accounts $targets
}

# --------------------------------------------------------------- окно -------

function Get-RamSections {
    @(
        [pscustomobject]@{ Key = 'accounts'; Text = 'Аккаунты'   },
        [pscustomobject]@{ Key = 'games';    Text = 'Игры'       },
        [pscustomobject]@{ Key = 'profiles'; Text = 'Профили'    },
        [pscustomobject]@{ Key = 'stats';    Text = 'Статистика' },
        [pscustomobject]@{ Key = 'log';      Text = 'Журнал'     }
    )
}

function Show-RamSection {
    <# Переключение разделов бокового меню. #>
    param([string]$Key)

    $script:Section = $Key
    if ($script:Settings) {
        $script:Settings.Section = $Key
        Save-RamSettings -Settings $script:Settings
    }

    foreach ($k in $script:UI.Panels.Keys) {
        $script:UI.Panels[$k].Visible = ($k -eq $Key)
    }
    foreach ($k in $script:UI.NavButtons.Keys) {
        $b = $script:UI.NavButtons[$k]
        $b.Tag.Back  = $(if ($k -eq $Key) { $Global:RamTheme.Accent } else { $Global:RamTheme.Panel })
        $b.Tag.Hover = $(if ($k -eq $Key) { $Global:RamTheme.AccentHov } else { $Global:RamTheme.CardHover })
        $b.Tag.Fore  = $(if ($k -eq $Key) { [System.Drawing.Color]::White } else { $Global:RamTheme.Text })
        $b.Invalidate()
    }

    if ($Key -eq 'stats')    { Update-RamStatsPanel }
    if ($Key -eq 'games')    { Update-RamGamesPanel }
    if ($Key -eq 'profiles') { Update-RamProfilesPanel }
}

function Update-RamGroupBar {
    <# Полоска наборов над списком: Все + по одной кнопке на набор. #>
    if (-not $script:UI.ContainsKey('GroupBar')) { return }

    $t   = $Global:RamTheme
    $bar = $script:UI.GroupBar
    $bar.SuspendLayout()
    try {
        $bar.Controls.Clear()

        $items = @([pscustomobject]@{ Key = ''; Text = 'Все' })
        foreach ($g in Get-RamGroups) { $items += [pscustomobject]@{ Key = $g; Text = $g } }

        if ($items.Count -le 1) { $bar.Visible = $false; return }
        $bar.Visible = $true

        foreach ($it in $items) {
            $active = ([string]$script:GroupFilter -eq [string]$it.Key)
            $w = [System.Windows.Forms.TextRenderer]::MeasureText($it.Text, $t.FontSmall).Width + 28

            $b = New-RamButton -Text $it.Text -Width $w -Height 28 -Radius 14 `
                               -Kind $(if ($active) { 'primary' } else { 'ghost' }) -OnClick {
                $script:GroupFilter = $this.Tag.GroupKey
                Build-RamCards
            }
            $b.Tag | Add-Member -NotePropertyName GroupKey -NotePropertyValue $it.Key -Force
            $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
            $bar.Controls.Add($b)
        }
    } finally {
        $bar.ResumeLayout()
    }
}

function Update-RamStatsPanel {
    <# Раздел «Статистика»: сколько раз запускался, сколько наиграно, вылеты. #>
    if (-not $script:UI.ContainsKey('StatsHost')) { return }

    $t = $Global:RamTheme
    $h = $script:UI.StatsHost
    $W = [Math]::Max(700, $h.ClientSize.Width - 24)

    $h.SuspendLayout()
    try {
        $h.Controls.Clear()

        $totalLaunch = 0; $totalCrash = 0; $totalSec = 0
        foreach ($a in $script:Accounts) {
            $totalLaunch += [int]$a.LaunchCount
            $totalCrash  += [int]$a.CrashCount
            $totalSec    += [int]$a.PlaySeconds
        }

        $head = New-RamCard -Width $W -Height 76
        $h.Controls.Add($head)
        $head.Controls.Add((New-RamLabel -Text 'Всего' -X 24 -Y 12 -Width 200 -Height 22 -Font $t.FontSmall -Color $t.Muted))
        $head.Controls.Add((New-RamLabel -Text ("запусков: $totalLaunch    ·    вылетов: $totalCrash    ·    наиграно: " + (Format-RamDuration $totalSec)) `
                                         -X 24 -Y 34 -Width ($W - 48) -Height 26 -Font $t.FontTitle))

        foreach ($a in (Get-RamOrderedAccounts)) {
            $row = New-RamCard -Width $W -Height 64
            $h.Controls.Add($row)

            $stripe = Get-RamLabelColor -Key ([string]$a.Color)
            $row.Tag | Add-Member -NotePropertyName Stripe -NotePropertyValue $stripe -Force
            $row.Add_Paint({
                param($s, $e)
                if ($null -eq $s.Tag.Stripe) { return }
                $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $r = New-Object System.Drawing.Rectangle(1, 8, 5, ($s.Height - 16))
                $path = New-RamRoundRect -Rect $r -Radius 2
                $b = New-Object System.Drawing.SolidBrush($s.Tag.Stripe)
                $e.Graphics.FillPath($b, $path); $b.Dispose(); $path.Dispose()
            })

            $row.Controls.Add((New-RamLabel -Text $a.Alias -X 24 -Y 10 -Width 240 -Height 22 -Font $t.FontTitle -Truncatable))
            $sub = if ($a.Username) { "@$($a.Username)" } else { 'вход не проверен' }
            $row.Controls.Add((New-RamLabel -Text $sub -X 24 -Y 32 -Width 240 -Height 20 -Font $t.FontSmall -Color $t.Muted -Truncatable))

            $row.Controls.Add((New-RamLabel -Text 'ЗАПУСКОВ' -X 290 -Y 10 -Width 110 -Height 16 -Font $t.FontSmall -Color $t.Muted))
            $row.Controls.Add((New-RamLabel -Text ([string][int]$a.LaunchCount) -X 290 -Y 28 -Width 110 -Height 22))

            $row.Controls.Add((New-RamLabel -Text 'ВЫЛЕТОВ' -X 400 -Y 10 -Width 110 -Height 16 -Font $t.FontSmall -Color $t.Muted))
            $row.Controls.Add((New-RamLabel -Text ([string][int]$a.CrashCount) -X 400 -Y 28 -Width 110 -Height 22 `
                                            -Color $(if ([int]$a.CrashCount -gt 0) { $t.Warn } else { $t.Text })))

            $row.Controls.Add((New-RamLabel -Text 'НАИГРАНО' -X 510 -Y 10 -Width 160 -Height 16 -Font $t.FontSmall -Color $t.Muted))
            $row.Controls.Add((New-RamLabel -Text (Format-RamDuration ([int]$a.PlaySeconds)) -X 510 -Y 28 -Width 160 -Height 22))

            $last = if ($a.LastUsed) {
                try { ([datetime]$a.LastUsed).ToString('dd.MM HH:mm') } catch { [string]$a.LastUsed }
            } else { 'ни разу' }
            $row.Controls.Add((New-RamLabel -Text 'ПОСЛЕДНИЙ ЗАПУСК' -X 680 -Y 10 -Width 230 -Height 16 -Font $t.FontSmall -Color $t.Muted))
            $row.Controls.Add((New-RamLabel -Text $last -X 680 -Y 28 -Width 180 -Height 22))
        }
    } finally {
        $h.ResumeLayout()
    }
}

function Format-RamDuration {
    param([int]$Seconds)
    if ($Seconds -le 0) { return '—' }
    $ts = [TimeSpan]::FromSeconds($Seconds)
    if ($ts.TotalHours -ge 1) { return ('{0} ч {1} мин' -f [int]$ts.TotalHours, $ts.Minutes) }
    if ($ts.TotalMinutes -ge 1) { return ('{0} мин' -f [int]$ts.TotalMinutes) }
    return ('{0} с' -f $ts.Seconds)
}

function Show-RamPopularGamesDialog {
    <#
      Показывает популярные сейчас игры из Roblox и даёт добавить выбранные в
      «Мои игры». Список тянется вживую (Get-RamPopularGames); если интернета
      нет — честно об этом говорим и не притворяемся.
    #>
    param([switch]$BuildOnly)

    $t = $Global:RamTheme
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Популярные игры Roblox'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.ForeColor       = $t.Text
    $dlg.Font            = $t.FontBody
    $popW = [Math]::Max(560, [int](560 * $Global:RamTheme.M.Scale * 0.78))
    $dlg.ClientSize      = New-Object System.Drawing.Size($popW, 560)

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Size = New-Object System.Drawing.Size(560, 4); $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $dlg.Controls.Add((New-RamLabel -Text 'Популярные сейчас' -X 24 -Y 20 -Width 400 -Height 30 -Font $t.FontBig))
    $dlg.Controls.Add((New-RamLabel -Text 'Список берётся прямо из Roblox. Отметь нужные и добавь.' `
                                    -X 24 -Y 54 -Width 500 -Height 20 -Font $t.FontSmall -Color $t.Muted))

    $listHost = New-RamScrollPanel -Width 512 -Height 400
    $listHost.Location = New-Object System.Drawing.Point(24, 84)
    $dlg.Controls.Add($listHost)

    $rowChecks = @{}

    $fill = {
        $listHost.Controls.Clear()
        $rowChecks.Clear()
        $listHost.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $games = @(Get-RamPopularGames -Limit 30)
        $listHost.Cursor = [System.Windows.Forms.Cursors]::Default

        if ($games.Count -eq 0) {
            $listHost.Controls.Add((New-RamLabel -Text 'Roblox не ответил — проверь интернет и нажми «Обновить».' `
                                                 -X 8 -Y 12 -Width 480 -Height 40 -Font $t.FontBody -Color $t.Muted))
            return
        }
        $y = 0
        foreach ($g in $games) {
            $card = New-RamCard -Width 492 -Height 48
            $card.Location = New-Object System.Drawing.Point(0, $y)
            $listHost.Controls.Add($card)

            $chk = New-RamCheckBox -X 14 -Y 14
            $card.Controls.Add($chk)
            $card.Controls.Add((New-RamLabel -Text ([string]$g.Title) -X 48 -Y 6 -Width 320 -Height 20 -Font $t.FontTitle -Truncatable))
            $players = if ($g.Players -ge 1000) { "$([math]::Round($g.Players/1000.0,1))K играют" } else { "$($g.Players) играют" }
            $card.Controls.Add((New-RamLabel -Text "$players   ·   ID $($g.PlaceId)" -X 48 -Y 26 -Width 320 -Height 18 -Font $t.FontSmall -Color $t.Muted))

            $rowChecks[$g.PlaceId] = [pscustomobject]@{ Check = $chk; Game = $g }
            $y += 56
        }
    }.GetNewClosure()

    $btnRefresh = New-RamButton -Text 'Обновить' -Width 130 -Height 34 -Kind 'ghost' -OnClick ({ & $fill }.GetNewClosure())
    $btnRefresh.Location = New-Object System.Drawing.Point(24, 500)
    $refreshW = (Measure-RamControl -Control $btnRefresh).Width
    $dlg.Controls.Add($btnRefresh)

    $btnAdd = New-RamButton -Text 'Добавить отмеченные' -Width 220 -Height 34 -Kind 'primary' -OnClick ({
        $picked = @($rowChecks.Values | Where-Object { $_.Check.Tag.Checked })
        if ($picked.Count -eq 0) { Show-RamInfo 'Отметь галочками нужные игры.'; return }
        foreach ($row in $picked) { Add-RamSavedGame -PlaceId $row.Game.PlaceId -LinkCode '' -Title $row.Game.Title }
        Save-RamSettingsNow
        Write-RamLog "В «Мои игры» добавлено из популярных: $($picked.Count)." 'ok'
        Show-RamInfo "Добавлено игр: $($picked.Count). Они теперь в разделе «Игры» и в списке при назначении."
        $this.FindForm().Close()
    }.GetNewClosure())
    $addW = (Measure-RamControl -Control $btnAdd).Width
    $dlg.Controls.Add($btnAdd)

    $btnClose = New-RamButton -Text 'Закрыть' -Width 100 -Height 34 -OnClick { $this.FindForm().Close() }
    $closeW = (Measure-RamControl -Control $btnClose).Width
    $btnClose.Location = New-Object System.Drawing.Point(($popW - 24 - $closeW), 500)
    $addX = [Math]::Max((24 + $refreshW + 12), ($popW - 24 - $closeW - 12 - $addW))
    $btnAdd.Location   = New-Object System.Drawing.Point($addX, 500)
    $dlg.Controls.Add($btnClose)

    if ($BuildOnly) { return $dlg }

    $dlg.Add_Shown({ & $fill }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

function Update-RamGamesPanel {
    <# Раздел «Игры»: сохранённые игры, назначить отмеченным, удалить. #>
    if (-not $script:UI.ContainsKey('GamesHost')) { return }

    $t = $Global:RamTheme
    $h = $script:UI.GamesHost
    $W = [Math]::Max(700, $h.ClientSize.Width - 24)

    $h.SuspendLayout()
    try {
        $h.Controls.Clear()

        $games = @($script:Settings.Games)
        if ($games.Count -eq 0) {
            $c = New-RamCard -Width $W -Height 110
            $h.Controls.Add($c)
            $c.Controls.Add((New-RamLabel -Text 'Список пуст' -X 24 -Y 20 -Width 400 -Height 26 -Font $t.FontTitle))
            $c.Controls.Add((New-RamLabel -Text 'Игры попадают сюда сами, как только назначишь их аккаунтам кнопкой «Игра для отмеченных». Дальше их можно ставить одним кликом.' `
                                          -X 24 -Y 48 -Width ($W - 48) -Height 44 -Font $t.FontBody -Color $t.Muted))
            return
        }

        foreach ($g in $games) {
            if ($null -eq $g) { continue }
            $row = New-RamCard -Width $W -Height 64
            $h.Controls.Add($row)

            $row.Controls.Add((New-RamLabel -Text ([string]$g.Title) -X 24 -Y 10 -Width 460 -Height 22 -Font $t.FontTitle -Truncatable))
            $meta = "ID $($g.PlaceId)"
            if ($g.LinkCode) { $meta += '   ·   приватный сервер' }
            $row.Controls.Add((New-RamLabel -Text $meta -X 24 -Y 32 -Width 460 -Height 20 -Font $t.FontSmall -Color $t.Muted -Truncatable))

            $bSet = New-RamButton -Text 'Назначить отмеченным' -Width 210 -Height 34 -Kind 'primary' -OnClick {
                $targets = @(Get-RamTargetAccounts)
                if ($targets.Count -eq 0) { Show-RamInfo 'Сначала отметь аккаунты в разделе «Аккаунты».'; return }
                $g2 = $this.Tag.Game
                foreach ($a in $targets) {
                    $a.PlaceId  = [string]$g2.PlaceId
                    $a.GameName = ([string]$g2.Title) -replace ' \(приватный сервер\)$', ''
                    $a.LinkCode = [string]$g2.LinkCode
                }
                Save-RamState
                Build-RamCards
                Write-RamLog "«$($g2.Title)» назначена аккаунтам: $($targets.Count)." 'ok'
            }
            $bSet.Tag | Add-Member -NotePropertyName Game -NotePropertyValue $g -Force
            $row.Controls.Add($bSet)

            $bDel = New-RamButton -Text 'Убрать' -Width 100 -Height 34 -OnClick {
                $g2 = $this.Tag.Game
                $script:Settings.Games = @(@($script:Settings.Games) | Where-Object {
                    -not ($_.PlaceId -eq $g2.PlaceId -and [string]$_.LinkCode -eq [string]$g2.LinkCode)
                })
                Save-RamSettings -Settings $script:Settings
                Update-RamGamesPanel
                Write-RamLog "«$($g2.Title)» убрана из списка игр." 'ok'
            }
            $bDel.Tag | Add-Member -NotePropertyName Game -NotePropertyValue $g -Force
            $row.Controls.Add($bDel)

            # Ставим обе от правого края и по ФАКТИЧЕСКОЙ ширине: кнопки
            # расширяются под надпись, и жёсткие отступы на крупном масштабе
            # давали наложение.
            $bDelW = (Measure-RamControl -Control $bDel).Width
            $bSetW = (Measure-RamControl -Control $bSet).Width
            $bDel.Location = New-Object System.Drawing.Point(($W - 24 - $bDelW), 15)
            $bSet.Location = New-Object System.Drawing.Point(($W - 24 - $bDelW - 12 - $bSetW), 15)
        }
    } finally {
        $h.ResumeLayout()
    }
}

function Get-RamStarterProfiles {
    <#
      Готовые профили запуска для старта. Все — на «все аккаунты» (набор пустой),
      поэтому работают у любого сразу, без настройки наборов. Игры — известные
      и стабильные по placeId, так что ссылки не протухают.

      Это шаблоны: выбранный превращается в обычный профиль пользователя,
      который дальше можно править и удалять как свой.
    #>
    @(
        [pscustomobject]@{ Name = 'Все в Blox Fruits';       Group = ''; PlaceId = '2753915549'; GameName = 'Blox Fruits';       LinkCode = '' }
        [pscustomobject]@{ Name = 'Все в Brookhaven';        Group = ''; PlaceId = '4924922222'; GameName = 'Brookhaven RP';     LinkCode = '' }
        [pscustomobject]@{ Name = 'Все в Adopt Me!';         Group = ''; PlaceId = '920587237';  GameName = 'Adopt Me!';         LinkCode = '' }
        [pscustomobject]@{ Name = 'Все в Murder Mystery 2';  Group = ''; PlaceId = '142823291';  GameName = 'Murder Mystery 2';  LinkCode = '' }
        [pscustomobject]@{ Name = 'Все в Pet Simulator 99';  Group = ''; PlaceId = '8737899170'; GameName = 'Pet Simulator 99';  LinkCode = '' }
        [pscustomobject]@{ Name = 'Все в Grow a Garden';     Group = ''; PlaceId = '126884695634066'; GameName = 'Grow a Garden'; LinkCode = '' }
        [pscustomobject]@{ Name = 'Все просто в Roblox';     Group = ''; PlaceId = '';           GameName = '';                  LinkCode = '' }
    )
}

function Add-RamStarterProfile {
    <# Кладёт готовый профиль в список пользователя (как обычный сохранённый). #>
    param([Parameter(Mandatory)]$Profile)

    $entry = [pscustomobject]@{
        Name     = [string]$Profile.Name
        Group    = [string]$Profile.Group
        PlaceId  = [string]$Profile.PlaceId
        GameName = [string]$Profile.GameName
        LinkCode = [string]$Profile.LinkCode
    }
    $rest = @(Get-RamProfiles | Where-Object { $_.Name -ne $entry.Name })
    $script:Settings.Profiles = @(@($entry) + $rest | Select-Object -First 20)
    Save-RamSettings -Settings $script:Settings
    Write-RamLog "Готовый профиль «$($entry.Name)» добавлен." 'ok'
}

function Update-RamProfilesPanel {
    <# Раздел «Профили»: сохранённые связки набор+игра. #>
    if (-not $script:UI.ContainsKey('ProfilesHost')) { return }

    $t = $Global:RamTheme
    $h = $script:UI.ProfilesHost
    $W = [Math]::Max(700, $h.ClientSize.Width - 24)

    $h.SuspendLayout()
    try {
        $h.Controls.Clear()

        $profiles = @(Get-RamProfiles)
        if ($profiles.Count -eq 0) {
            $c = New-RamCard -Width $W -Height 120
            $h.Controls.Add($c)
            $c.Controls.Add((New-RamLabel -Text 'Профилей пока нет' -X 24 -Y 20 -Width 400 -Height 26 -Font $t.FontTitle))
            $c.Controls.Add((New-RamLabel -Text 'Отметь нужные аккаунты в разделе «Аккаунты», задай им игру, потом нажми здесь «Сохранить текущее как профиль». Дальше весь набор запускается одной кнопкой.' `
                                          -X 24 -Y 48 -Width ($W - 48) -Height 50 -Font $t.FontBody -Color $t.Muted))
            return
        }

        foreach ($pr in $profiles) {
            $row = New-RamCard -Width $W -Height 64
            $h.Controls.Add($row)

            $row.Controls.Add((New-RamLabel -Text ([string]$pr.Name) -X 24 -Y 10 -Width 420 -Height 22 -Font $t.FontTitle -Truncatable))
            $meta = if ($pr.Group) { "набор «$($pr.Group)»" } else { 'все аккаунты' }
            if ($pr.GameName) { $meta += "   ·   $($pr.GameName)" }
            elseif ($pr.PlaceId) { $meta += "   ·   ID $($pr.PlaceId)" }
            if ($pr.LinkCode) { $meta += '   ·   приватный сервер' }
            $row.Controls.Add((New-RamLabel -Text $meta -X 24 -Y 32 -Width 560 -Height 20 -Font $t.FontSmall -Color $t.Muted -Truncatable))

            $bRun = New-RamButton -Text '▶  Запустить профиль' -Width 200 -Height 34 -Kind 'primary' -OnClick {
                Invoke-RamRunProfile -Profile $this.Tag.Profile
            }
            $bRun.Tag | Add-Member -NotePropertyName Profile -NotePropertyValue $pr -Force
            $row.Controls.Add($bRun)

            $bDel = New-RamButton -Text 'Убрать' -Width 100 -Height 34 -OnClick {
                $nm = $this.Tag.Profile.Name
                $script:Settings.Profiles = @(Get-RamProfiles | Where-Object { $_.Name -ne $nm })
                Save-RamSettings -Settings $script:Settings
                Update-RamProfilesPanel
                Write-RamLog "Профиль «$nm» убран." 'ok'
            }
            $bDel.Tag | Add-Member -NotePropertyName Profile -NotePropertyValue $pr -Force
            $row.Controls.Add($bDel)

            $bDelW = (Measure-RamControl -Control $bDel).Width
            $bRunW = (Measure-RamControl -Control $bRun).Width
            $bDel.Location = New-Object System.Drawing.Point(($W - 24 - $bDelW), 15)
            $bRun.Location = New-Object System.Drawing.Point(($W - 24 - $bDelW - 12 - $bRunW), 15)
        }
    } finally {
        $h.ResumeLayout()
    }
}

function Update-RamTrayMenu {
    <# Меню значка в часах: быстрый запуск без открытия окна. #>
    if ($null -eq $script:UI.TrayMenu) { return }

    $m = $script:UI.TrayMenu
    $m.Items.Clear()

    $mShow = New-Object System.Windows.Forms.ToolStripMenuItem('Открыть AltHub')
    $mShow.Add_Click({ $f = $script:UI.Form; $f.Show(); $f.WindowState = 'Normal'; [void]$f.Activate() })
    [void]$m.Items.Add($mShow)
    [void]$m.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    foreach ($pr in (Get-RamProfiles)) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem("Профиль: $($pr.Name)")
        $mi.Tag = $pr
        $mi.Add_Click({ Invoke-RamRunProfile -Profile $this.Tag })
        [void]$m.Items.Add($mi)
    }

    foreach ($g in (Get-RamGroups)) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem("Набор: $g")
        $mi.Tag = $g
        $mi.Add_Click({
            $gr = $this.Tag
            Add-RamToLaunchQueue -Accounts @($script:Accounts | Where-Object { [string]$_.Group -eq $gr })
        })
        [void]$m.Items.Add($mi)
    }

    if ($m.Items.Count -gt 2) { [void]$m.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) }

    $mStop = New-Object System.Windows.Forms.ToolStripMenuItem('Закрыть все окна Roblox')
    $mStop.Add_Click({
        foreach ($pr in (Get-RamRobloxProcesses)) { [void](Stop-RamRobloxInstance -ProcessId $pr.Id) }
        $script:Instances.Clear()
        Update-RamCardStates
    })
    [void]$m.Items.Add($mStop)

    $mExit = New-Object System.Windows.Forms.ToolStripMenuItem('Выход')
    $mExit.Add_Click({ $script:UI.Form.Close() })
    [void]$m.Items.Add($mExit)
}

function Get-RamCheckableWindows {
    <#
      Все окна программы — списком, чтобы Самопроверка обходила их все.

      ЗАЧЕМ РЕЕСТР. Раньше окна перечислялись прямо в проверке вручную, и
      список отстал: проверялись четыре окна из одиннадцати. Именно поэтому
      наложение в конструкторе тем (кнопка «Подробно» поверх превью) никто
      не замечал — это окно просто не проверялось.

      Правило: появилось новое окно с -BuildOnly — добавь его сюда.
    #>
    @(
        @{ Name = 'главное';       Main = $true
           Sections = @('accounts','games','profiles','stats','log')
           Build = { New-RamMainForm } }
        @{ Name = 'мастер';        Build = { Show-RamAddWizard -BuildOnly } }
        @{ Name = 'аккаунт';       Build = { Show-RamAccountDialog -Account $script:Accounts[0] -BuildOnly } }
        @{ Name = 'настройки';     Build = { Show-RamSettingsDialog -BuildOnly } }
        @{ Name = 'конструктор';   Build = { Show-RamThemeConstructor -BuildOnly } }
        @{ Name = 'пачкой';        Build = { Show-RamBatchAddDialog -BuildOnly } }
        @{ Name = 'из браузера';   Build = { Show-RamBrowserGuide -BuildOnly } }
        @{ Name = 'популярные';    Build = { Show-RamPopularGamesDialog -BuildOnly } }
        @{ Name = 'быстрая';       Build = { Show-RamQuickSetup -BuildOnly } }
        @{ Name = 'мастер1';       Build = { Show-RamFirstRun -StartStep 0 -BuildOnly }; Pages = $true }
        @{ Name = 'мастер1/тема';  Build = { Show-RamFirstRun -StartStep 1 -BuildOnly }; Pages = $true }
        @{ Name = 'мастер1/акк';   Build = { Show-RamFirstRun -StartStep 2 -BuildOnly }; Pages = $true }
        @{ Name = 'мастер1/осн';   Build = { Show-RamFirstRun -StartStep 3 -BuildOnly }; Pages = $true }
        @{ Name = 'мастер1/готово';Build = { Show-RamFirstRun -StartStep 4 -BuildOnly }; Pages = $true }
        @{ Name = 'сообщение';     Build = { Show-RamMessage -Message 'Короткое сообщение для проверки вёрстки.' -BuildOnly } }
        @{ Name = 'сообщение/дл';  Build = { Show-RamMessage -Message ('Длинное сообщение. ' * 12) -Kind 'warn' -BuildOnly } }
        @{ Name = 'сообщение/да';  Build = { Show-RamMessage -Message 'Вопрос с двумя кнопками?' -YesNo -BuildOnly } }
        @{ Name = 'сообщение/4';   Build = { Show-RamMessage -Message 'Выбор из нескольких действий.' -Buttons @(
                                                @{ Text = 'Забрать вход';    Value = 'take';   Kind = 'primary' },
                                                @{ Text = 'Сменить аккаунт'; Value = 'switch' },
                                                @{ Text = 'Пропустить';      Value = 'skip'   },
                                                @{ Text = 'Хватит';          Value = 'stop'   }) -BuildOnly } }
        @{ Name = 'ввод';          Build = { Show-RamInputDialog -Title 'Ввод' -Prompt 'Вставь ссылку на игру или её номер.' -BuildOnly } }
        @{ Name = 'ввод/список';   Build = { Show-RamInputDialog -Title 'Игра' -Prompt 'Выбери из сохранённых или вставь свою.' -Suggestions @(
                                                [pscustomobject]@{ Text = 'Blox Fruits'; Value = '1' },
                                                [pscustomobject]@{ Text = 'Очень длинное название игры для проверки'; Value = '2' }) -BuildOnly } }
    )
}

function New-RamMainForm {
    $t = $Global:RamTheme
    $metrics = $t.M   # НЕ $m: ниже есть foreach ($m in ...), он бы её затёр

    # ------------------------------------------------------------------------
    # РАЗМЕРЫ СЧИТАЮТСЯ, А НЕ ВПИСЫВАЮТСЯ.
    #
    # Раньше здесь стояли числа: боковое меню 210, кнопки в нём 178, панель
    # разделов 1120. Пока экран обычный, всё сходилось. Но надписи меряются
    # шрифтом, а шрифт растёт вместе с масштабом экрана: при 150% кнопке
    # «Быстрая настройка» нужен 261 пиксель, а меню оставалось 210 — и она
    # вылезала за край. То же и с панелями кнопок.
    #
    # Теперь ширина меню выводится из самой длинной надписи в нём.
    # ------------------------------------------------------------------------
    $navTexts = @()
    foreach ($sec in Get-RamSections) { $navTexts += ('   ' + $sec.Text) }
    $navTexts += @('   Быстрая настройка', '   Настройки', '   Справка')

    $navW = 0
    foreach ($tx in $navTexts) {
        $w = (Measure-RamText -Text $tx -Font $t.FontBody).Width + $metrics.BtnPadX
        if ($w -gt $navW) { $navW = $w }
    }
    $navBtnW = [Math]::Max([int](178 * $metrics.Scale), $navW)
    $sideW   = $navBtnW + ($metrics.GapLg * 2)
    $contentX = $sideW + $metrics.GapLg

    $formW = [Math]::Max(1360, $contentX + [int](1120 * $metrics.Scale) + $metrics.GapLg)
    $formH = [Math]::Max(820,  [int](820 * $metrics.Scale))

    # В экран окно тоже должно влезать.
    #
    # $Global:RamForceWorkArea — подмена для Самопроверки. Настоящий экран
    # со 150% — это, как правило, и физически больший экран (2560 или 3840
    # точек), поэтому проверять крупный шрифт на маленьком рабочем столе
    # нечестно: получится теснота, которой у людей не бывает.
    try {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $waW = $wa.Width; $waH = $wa.Height
        if ($null -ne $Global:RamForceWorkArea) {
            $waW = [int]$Global:RamForceWorkArea.Width
            $waH = [int]$Global:RamForceWorkArea.Height
        }
        if ($formW -gt $waW) { $formW = $waW }
        if ($formH -gt $waH) { $formH = $waH }
    } catch { }

    $form = New-Object System.Windows.Forms.Form
    $form.Text          = $script:AppName
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.ClientSize    = New-Object System.Drawing.Size($formW, $formH)
    # Минимум — тоже по факту: боковое меню плюс место под карточку.
    $form.MinimumSize   = New-Object System.Drawing.Size(
                              ($contentX + [int](700 * $metrics.Scale) + $metrics.GapLg + 16),
                              [Math]::Min($formH, [int](700 * $metrics.Scale)))
    $form.StartPosition = 'CenterScreen'
    $form.BackColor     = $t.Bg
    $form.ForeColor     = $t.Text
    $form.Font          = $t.FontBody
    Set-RamDoubleBuffered $form
    $form.Add_HandleCreated({ Set-RamDarkTitleBar $this })

    # Перетаскивание файла на окно: список кук/приглашений или файл настроек.
    # Курсор «копировать» показываем только для файлов — на текст и прочее не
    # реагируем, чтобы не сбивать с толку.
    $form.AllowDrop = $true
    $form.Add_DragEnter({
        param($src, $e)
        if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
        } else {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::None
        }
    })
    $form.Add_DragDrop({
        param($src, $e)
        $files = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
        foreach ($f in $files) { Import-RamDroppedFile -Path $f }
    })

    $script:UI.Panels     = @{}
    $script:UI.NavButtons = @{}

    # =================================================== боковое меню ========
    $side = New-Object System.Windows.Forms.Panel
    $side.Location  = New-Object System.Drawing.Point(0, 0)
    $side.Size      = New-Object System.Drawing.Size($sideW, $formH)
    $side.BackColor = $t.Panel
    $side.Anchor    = 'Top,Left,Bottom'
    $form.Controls.Add($side)

    $side.Controls.Add((New-RamLabel -Text $script:AppName -X ($metrics.GapLg + 6) -Y 22 -Width ($sideW - $metrics.GapLg * 2) -Height 32 -Font $t.FontBig))
    $side.Controls.Add((New-RamLabel -Text "v$($script:AppVersion)" -X ($metrics.GapLg + 8) -Y 54 -Width ($sideW - $metrics.GapLg * 2) -Height 18 `
                                     -Font $t.FontSmall -Color $t.Muted))

    $y = 96
    foreach ($sec in Get-RamSections) {
        $b = New-RamButton -Text ('   ' + $sec.Text) -Width $navBtnW -Height 40 -Radius 8 -OnClick {
            Show-RamSection -Key $this.Tag.SectionKey
        }
        $b.Tag | Add-Member -NotePropertyName SectionKey -NotePropertyValue $sec.Key -Force
        $b.Tag.Border = $null
        $b.Location = New-Object System.Drawing.Point($metrics.GapLg, $y)
        $side.Controls.Add($b)
        $script:UI.NavButtons[$sec.Key] = $b
        $y += 46
    }

    $bQuick = New-RamButton -Text '   Быстрая настройка' -Width $navBtnW -Height 40 -Radius 8 -Kind 'ghost' `
                            -Tooltip 'Разложить всё под расклад «основной + твины на випке»' -OnClick {
        Show-RamQuickSetup
    }
    $bQuick.Location = New-Object System.Drawing.Point($metrics.GapLg, ($y + 14))
    $side.Controls.Add($bQuick)
    $y += 46

    $bSettings = New-RamButton -Text '   Настройки' -Width $navBtnW -Height 40 -Radius 8 -Kind 'ghost' -OnClick {
        Show-RamSettingsDialog
    }
    $bSettings.Location = New-Object System.Drawing.Point($metrics.GapLg, ($y + 14))
    $side.Controls.Add($bSettings)

    $bHelp = New-RamButton -Text '   Справка' -Width $navBtnW -Height 40 -Radius 8 -Kind 'ghost' -OnClick {
        $ans = Show-RamMessage -Title 'Справка' -Kind 'info' -Message (
            "Пройти настройку заново — тот самый мастер первого запуска: железо, тема, аккаунты, наборы.`n`n" +
            "Открыть README — подробное описание всего, что умеет AltHub."
        ) -Buttons @(
            @{ Text = 'Пройти настройку заново'; Value = 'wizard'; Kind = 'primary' },
            @{ Text = 'Открыть README';          Value = 'readme' },
            @{ Text = 'Закрыть';                 Value = 'no'     }
        )
        switch ([string]$ans) {
            'wizard' {
                Invoke-RamFirstRun -Force
                Build-RamCards
            }
            'readme' {
                $readme = Join-Path $script:Root 'README.md'
                if (Test-Path -LiteralPath $readme) { Start-Process notepad.exe $readme }
                else { Show-RamInfo 'README.md не найден рядом со скриптом.' }
            }
        }
    }
    $bHelp.Location = New-Object System.Drawing.Point($metrics.GapLg, ($y + 60))
    $side.Controls.Add($bHelp)

    $lblAuthor = New-RamLabel -Text $script:AppAuthor -X 24 -Y 780 -Width 170 -Height 20 `
                              -Font $t.FontSmall -Color $t.Muted
    $lblAuthor.Anchor = 'Left,Bottom'
    $side.Controls.Add($lblAuthor)

    # Полезная ширина и высота содержимого — от них пляшут все пять разделов.
    $contentW = $formW - $contentX - $metrics.GapLg
    $contentH = $formH - 56 - [int](28 * $metrics.Scale)

    # =================================================== верхняя строка ======
    # Ширина обрывается до поля поиска: на крупном масштабе подпись
    # дорастала до него и налезала.
    $sub = New-RamLabel -Text '' -X ($contentX + 8) -Y 22 -Width ($formW - $contentX - 340) -Height 22 -Font $t.FontSmall -Color $t.Muted -Truncatable
    $sub.Anchor = 'Top,Left'
    $form.Controls.Add($sub)
    $script:UI.Subtitle = $sub

    $search = New-RamTextBox -Width 300 -Height 32
    $search.Location = New-Object System.Drawing.Point(($formW - 300 - $metrics.GapLg), 16)
    $search.Anchor   = 'Top,Right'
    $form.Controls.Add($search)
    $script:UI.Search = $search

    # Подсказка живёт внутри самого поля: отдельная метка поверх поля в
    # WinForms постоянно оказывается под ним и остаётся невидимой.
    $script:SearchPlaceholder = 'поиск: имя, ник, игра, заметка'
    $script:SearchIsHint      = $true

    $sTb = $search.Tag
    $sTb.Text      = $script:SearchPlaceholder
    $sTb.ForeColor = $t.Muted
    # Кнопки у нас нарисованные панели, фокус они не принимают. Без этого
    # WinForms при открытии окна сам ставит фокус в поиск, срабатывает
    # GotFocus и подсказка стирается ещё до того, как её кто-то увидел.
    $sTb.TabStop = $false

    $sTb.Add_GotFocus({
        if ($script:SearchIsHint) {
            $script:SearchIsHint = $false
            $this.Text = ''
            $this.ForeColor = $Global:RamTheme.Text
        }
    })
    $sTb.Add_LostFocus({
        if ([string]::IsNullOrEmpty($this.Text)) {
            $script:SearchIsHint = $true
            $this.Text = $script:SearchPlaceholder
            $this.ForeColor = $Global:RamTheme.Muted
        }
    })
    # Поиск с задержкой. Раньше Build-RamCards звалась на КАЖДОЕ нажатие
    # клавиши — полная пересборка всего списка с созданием десятка контролов
    # и своего меню на каждую карточку. Теперь ждём, пока человек перестанет
    # печатать, и пересобираем один раз.
    $searchTimer = New-Object System.Windows.Forms.Timer
    $searchTimer.Interval = 250
    $searchTimer.Add_Tick({
        $this.Stop()
        Invoke-RamSafe -What 'поиск' -Body { Build-RamCards }
    })
    $script:UI.SearchTimer = $searchTimer

    $sTb.Add_TextChanged({
        if ($script:SearchIsHint) { return }
        $script:Filter = $this.Text
        $script:UI.SearchTimer.Stop()
        $script:UI.SearchTimer.Start()
    })

    # =================================================== раздел: аккаунты ====
    $pAcc = New-Object System.Windows.Forms.Panel
    $pAcc.Location  = New-Object System.Drawing.Point($contentX, 56)
    $pAcc.Size      = New-Object System.Drawing.Size($contentW, $contentH)
    $pAcc.BackColor = $t.Bg
    $pAcc.Anchor    = 'Top,Left,Right,Bottom'
    $form.Controls.Add($pAcc)
    $script:UI.Panels['accounts'] = $pAcc

    # Две панели: левая растёт слева направо, правая прижата к правому краю.
    # Одной панелью не обойтись — при узком окне кнопки уезжали за край.
    $bar = New-Object System.Windows.Forms.FlowLayoutPanel
    $bar.Location      = New-Object System.Drawing.Point(0, 0)
    # Ширина с запасом: кнопки автоматически расширяются под длину надписи,
    # и «Удалить» при ровно 700px уже не помещалась.
    # Левая панель забирает всё, что осталось от правой, и ПЕРЕНОСИТ кнопки
    # на вторую строку, если не влезли. Раньше ширина была прибита к 720, и на
    # крупном масштабе «Удалить» просто уезжала за край.
    $barRW = [int](390 * $metrics.Scale)
    $bar.Size          = New-Object System.Drawing.Size(($contentW - $barRW - $metrics.GapLg), 44)
    $bar.WrapContents  = $true
    $bar.BackColor     = $t.Bg
    $bar.FlowDirection = 'LeftToRight'
    $bar.WrapContents  = $false
    $bar.Anchor        = 'Top,Left'
    $pAcc.Controls.Add($bar)

    $barR = New-Object System.Windows.Forms.FlowLayoutPanel
    $barR.Location      = New-Object System.Drawing.Point(($contentW - $barRW), 0)
    $barR.Size          = New-Object System.Drawing.Size($barRW, 44)
    $barR.BackColor     = $t.Bg
    $barR.FlowDirection = 'RightToLeft'
    $barR.WrapContents  = $false
    $barR.Anchor        = 'Top,Right'
    $pAcc.Controls.Add($barR)

    $bar.Controls.Add((New-RamButton -Text '＋  Добавить' -Width 138 -Height 38 -Kind 'primary' -Tooltip 'Мастер добавления аккаунтов' -OnClick { Show-RamAddWizard }))
    $bar.Controls.Add((New-RamButton -Text 'Все' -Width 70 -Height 38 -Tooltip 'Отметить или снять отметку со всех' -OnClick {
        $any = $false
        foreach ($id in $script:Cards.Keys) { if (-not $script:Cards[$id].Check.Tag.Checked) { $any = $true } }
        Set-RamAllChecked $any
    }))
    $bar.Controls.Add((New-RamButton -Text 'Игра' -Width 86 -Height 38 -Tooltip 'Назначить игру отмеченным аккаунтам' -OnClick { Invoke-RamAssignGame }))
    $bar.Controls.Add((New-RamButton -Text 'Набор' -Width 92 -Height 38 -Tooltip 'Собрать отмеченные аккаунты в набор' -OnClick { Invoke-RamAssignGroup }))
    $bar.Controls.Add((New-RamButton -Text 'Метка' -Width 92 -Height 38 -Tooltip 'Цветная метка для отмеченных' -OnClick { Invoke-RamAssignColor }))
    $bar.Controls.Add((New-RamButton -Text 'Удалить' -Width 96 -Height 38 -Tooltip 'Убрать отмеченные из менеджера' -OnClick { Invoke-RamDeleteSelected }))

    # Правая группа выкладывается справа налево, поэтому порядок обратный.
    $bTile = New-RamButton -Text 'Окна' -Width 92 -Height 38 `
                           -Tooltip 'Левый клик — разложить, правый — выбрать раскладку' -OnClick { Invoke-RamTileWindows }
    $barR.Controls.Add($bTile)

    $barR.Controls.Add((New-RamButton -Text '■  Закрыть' -Width 116 -Height 38 -Tooltip 'Закрыть окна отмеченных' -OnClick { Invoke-RamStopSelected }))

    $bPlay = New-RamButton -Text '▶  Запустить' -Width 150 -Height 38 -Kind 'primary' -OnClick {
        $targets = @(Get-RamTargetAccounts)
        if ($targets.Count -eq 0) { $targets = @(Get-RamVisibleAccounts) }
        Add-RamToLaunchQueue -Accounts $targets
    }
    $barR.Controls.Add($bPlay)

    $tileMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $tileMenu.BackColor = $t.Card
    $tileMenu.ForeColor = $t.Text
    $tileMenu.ShowImageMargin = $false
    foreach ($m in @(
        @{ K = 'main';    T = 'Основной крупно, твины мелко' },
        @{ K = 'grid';    T = 'Сеткой' },
        @{ K = 'cascade'; T = 'Каскадом' },
        @{ K = 'columns'; T = 'Колонками' },
        @{ K = 'rows';    T = 'Строками' })) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($metrics.T)
        $mi.Tag = $metrics.K
        $mi.Add_Click({
            $script:Settings.TileMode = $this.Tag
            Save-RamSettings -Settings $script:Settings
            Invoke-RamTileWindows -Mode $this.Tag
        })
        [void]$tileMenu.Items.Add($mi)
    }
    $miSave = New-Object System.Windows.Forms.ToolStripMenuItem('Запомнить места окон')
    $miSave.Add_Click({ Save-RamWindowPositions })
    [void]$tileMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$tileMenu.Items.Add($miSave)
    $script:UI.TileMenu = $tileMenu

    $bTile.Add_MouseUp({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
            $script:UI.TileMenu.Show($sender, $e.Location)
        }
    })

    # полоска наборов
    $groupBar = New-Object System.Windows.Forms.FlowLayoutPanel
    # Перенос строк считаем ЯВНО: пока окно не показано, WinForms раскладку
    # сам не выполняет, и кнопки остались бы в одну строку за краем панели.
    $bar.PerformLayout()
    $barR.PerformLayout()

    # Высота панели кнопок зависит от того, перенеслись ли они на вторую
    # строку, поэтому следующий ряд ставим от её фактического низа.
    $barBottom = [Math]::Max(44, $bar.PreferredSize.Height)
    $bar.Height = $barBottom
    $bar.PerformLayout()
    $groupBar.Location      = New-Object System.Drawing.Point(0, ($barBottom + $metrics.GapSm))
    $groupBar.Size          = New-Object System.Drawing.Size($contentW, ([int](34 * $metrics.Scale) + 6))
    $groupBar.BackColor     = $t.Bg
    $groupBar.FlowDirection = 'LeftToRight'
    $groupBar.WrapContents  = $false
    $groupBar.Anchor        = 'Top,Left,Right'
    $groupBar.Visible       = $false
    $pAcc.Controls.Add($groupBar)
    $script:UI.GroupBar = $groupBar

    $cards = New-RamScrollPanel -Width $contentW -Height ($contentH - $barBottom - $metrics.GapSm - 40)
    $cards.Location = New-Object System.Drawing.Point(0, ($barBottom + $metrics.GapSm + 40))
    $cards.Anchor   = 'Top,Left,Right,Bottom'
    $pAcc.Controls.Add($cards)
    $script:UI.Cards = $cards

    # =================================================== раздел: игры =======
    $pGames = New-Object System.Windows.Forms.Panel
    $pGames.Location  = New-Object System.Drawing.Point($contentX, 56)
    $pGames.Size      = New-Object System.Drawing.Size($contentW, $contentH)
    $pGames.BackColor = $t.Bg
    $pGames.Anchor    = 'Top,Left,Right,Bottom'
    $pGames.Visible   = $false
    $form.Controls.Add($pGames)
    $script:UI.Panels['games'] = $pGames

    $pGames.Controls.Add((New-RamLabel -Text 'Мои игры' -X 0 -Y 0 -Width 400 -Height 32 -Font $t.FontBig))
    $pGames.Controls.Add((New-RamLabel -Text 'Отметь аккаунты в разделе «Аккаунты», потом нажми «Назначить отмеченным» у нужной игры' `
                                       -X 0 -Y 32 -Width 900 -Height 22 -Font $t.FontSmall -Color $t.Muted))

    $btnPopular = New-RamButton -Text 'Популярные из Roblox' -Width 220 -Height 36 -Kind 'primary' `
                                -Tooltip 'Показать игры, в которые сейчас играют больше всего, и добавить их в список' -OnClick {
        Show-RamPopularGamesDialog
        Update-RamGamesPanel
    }
    $btnPopular.Location = New-Object System.Drawing.Point(900, 8)
    $btnPopular.Anchor   = 'Top,Right'
    $pGames.Controls.Add($btnPopular)

    $gamesHost = New-RamScrollPanel -Width $contentW -Height ($contentH - 66)
    $gamesHost.Location = New-Object System.Drawing.Point(0, 66)
    $gamesHost.Anchor   = 'Top,Left,Right,Bottom'
    $pGames.Controls.Add($gamesHost)
    $script:UI.GamesHost = $gamesHost

    # =================================================== раздел: профили ====
    $pProf = New-Object System.Windows.Forms.Panel
    $pProf.Location  = New-Object System.Drawing.Point($contentX, 56)
    $pProf.Size      = New-Object System.Drawing.Size($contentW, $contentH)
    $pProf.BackColor = $t.Bg
    $pProf.Anchor    = 'Top,Left,Right,Bottom'
    $pProf.Visible   = $false
    $form.Controls.Add($pProf)
    $script:UI.Panels['profiles'] = $pProf

    $pProf.Controls.Add((New-RamLabel -Text 'Профили запуска' -X 0 -Y 0 -Width 400 -Height 32 -Font $t.FontBig))
    # Ширина обрывается ДО кнопок справа: подпись шла на все 900 и залезала
    # под них верхней кромкой. Кнопки при этом подняты на Y=0, чтобы между
    # ними и подписью оставался зазор.
    $pProf.Controls.Add((New-RamLabel -Text 'Связка «набор аккаунтов + игра». Одной кнопкой ставит игру всем и запускает.' `
                                      -X 0 -Y 34 -Width 540 -Height 22 -Font $t.FontSmall -Color $t.Muted -Truncatable))

    $bStarter = New-RamButton -Text '＋ Готовый профиль  ▾' -Width 220 -Height 32 -Kind 'primary' `
                              -Tooltip 'Добавить готовый профиль с популярной игрой — работает сразу' -OnClick {
        $menu = New-RamContextMenu
        foreach ($sp in Get-RamStarterProfiles) {
            [void](Add-RamMenuItem -Menu $menu -Text $sp.Name -Tag $sp -OnClick {
                Add-RamStarterProfile -Profile $this.Tag
                Update-RamProfilesPanel
            })
        }
        $menu.Show($this, (New-Object System.Drawing.Point(0, $this.Height)))
    }
    # Ставим ниже, после создания обеих: ширина зависит от надписи и масштаба.
    $pProf.Controls.Add($bStarter)

    $bSaveProf = New-RamButton -Text 'Сохранить текущее как профиль' -Width 280 -Height 32 -Kind 'ghost' -OnClick {
        Invoke-RamSaveProfile
    }
    $pProf.Controls.Add($bSaveProf)

    # От правого края: на крупном масштабе жёсткие X давали наложение.
    $saveW    = (Measure-RamControl -Control $bSaveProf).Width
    $starterW = (Measure-RamControl -Control $bStarter).Width
    $bSaveProf.Location = New-Object System.Drawing.Point(($contentW - $saveW), 0)
    $bStarter.Location  = New-Object System.Drawing.Point(($contentW - $saveW - $metrics.Gap - $starterW), 0)

    $profHost = New-RamScrollPanel -Width $contentW -Height ($contentH - 66)
    $profHost.Location = New-Object System.Drawing.Point(0, 66)
    $profHost.Anchor   = 'Top,Left,Right,Bottom'
    $pProf.Controls.Add($profHost)
    $script:UI.ProfilesHost = $profHost

    # =================================================== раздел: статистика ==
    $pStats = New-Object System.Windows.Forms.Panel
    $pStats.Location  = New-Object System.Drawing.Point($contentX, 56)
    $pStats.Size      = New-Object System.Drawing.Size($contentW, $contentH)
    $pStats.BackColor = $t.Bg
    $pStats.Anchor    = 'Top,Left,Right,Bottom'
    $pStats.Visible   = $false
    $form.Controls.Add($pStats)
    $script:UI.Panels['stats'] = $pStats

    $pStats.Controls.Add((New-RamLabel -Text 'Статистика' -X 0 -Y 0 -Width 400 -Height 32 -Font $t.FontBig))

    $bResetStats = New-RamButton -Text 'Обнулить' -Width 120 -Height 32 -Kind 'ghost' -OnClick {
        if (-not (Confirm-Ram 'Обнулить всю статистику? Сами аккаунты и игры останутся на месте.')) { return }
        foreach ($a in $script:Accounts) { $a.LaunchCount = 0; $a.CrashCount = 0; $a.PlaySeconds = 0 }
        Save-RamState
        Update-RamStatsPanel
        Write-RamLog 'Статистика обнулена.' 'ok'
    }
    $bResetStats.Location = New-Object System.Drawing.Point(420, 2)
    $pStats.Controls.Add($bResetStats)

    $statsHost = New-RamScrollPanel -Width $contentW -Height ($contentH - 46)
    $statsHost.Location = New-Object System.Drawing.Point(0, 46)
    $statsHost.Anchor   = 'Top,Left,Right,Bottom'
    $pStats.Controls.Add($statsHost)
    $script:UI.StatsHost = $statsHost

    # =================================================== раздел: журнал ======
    $pLog = New-Object System.Windows.Forms.Panel
    $pLog.Location  = New-Object System.Drawing.Point($contentX, 56)
    $pLog.Size      = New-Object System.Drawing.Size($contentW, $contentH)
    $pLog.BackColor  = $t.Bg
    $pLog.Anchor    = 'Top,Left,Right,Bottom'
    $pLog.Visible   = $false
    $form.Controls.Add($pLog)
    $script:UI.Panels['log'] = $pLog

    $pLog.Controls.Add((New-RamLabel -Text 'Журнал' -X 0 -Y 0 -Width 400 -Height 32 -Font $t.FontBig))

    $bCopyLog = New-RamButton -Text 'Скопировать' -Width 130 -Height 32 -Kind 'ghost' -OnClick {
        try { [System.Windows.Forms.Clipboard]::SetText($script:UI.Log.Text); Write-RamLog 'Журнал скопирован в буфер.' 'ok' } catch { }
    }
    # По фактической ширине: на крупном масштабе надписи длиннее и кнопки
    # налезали друг на друга.
    $copyW  = (Measure-RamControl -Control $bCopyLog).Width
    $bCopyLog.Location = New-Object System.Drawing.Point(420, 2)
    $pLog.Controls.Add($bCopyLog)

    $bClearLog = New-RamButton -Text 'Очистить' -Width 120 -Height 32 -Kind 'ghost' -OnClick {
        $script:UI.Log.Clear()
    }
    $bClearLog.Location = New-Object System.Drawing.Point((420 + $copyW + $metrics.Gap), 2)
    $pLog.Controls.Add($bClearLog)

    $logHost = New-Object System.Windows.Forms.Panel
    $logHost.Location  = New-Object System.Drawing.Point(0, 46)
    $logHost.Size      = New-Object System.Drawing.Size($contentW, ($contentH - 46))
    $logHost.BackColor = $t.LogBack
    $logHost.Padding   = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)
    $logHost.Anchor    = 'Top,Left,Right,Bottom'
    $pLog.Controls.Add($logHost)

    $log = New-Object System.Windows.Forms.TextBox
    $log.Multiline   = $true
    $log.ReadOnly    = $true
    $log.ScrollBars  = 'Vertical'
    $log.BorderStyle = 'None'
    $log.BackColor   = $t.LogBack
    $log.ForeColor   = $t.Muted
    $log.Font        = $t.FontMono
    $log.Dock        = 'Fill'
    $logHost.Controls.Add($log)
    $script:UI.Log = $log

    # =================================================== строка состояния ====
    $fixW  = [Math]::Max([int](190 * $metrics.Scale), (Measure-RamText -Text 'Починить входы (99)' -Font $t.FontBody).Width + $metrics.BtnPadX)
    $lineY = $formH - [int](28 * $metrics.Scale)
    $st = New-RamLabel -Text '' -X $contentX -Y ($lineY + 4) -Width ($contentW - $fixW - $metrics.GapLg) -Height 20 -Font $t.FontSmall -Color $t.Muted
    $st.Anchor = 'Left,Right,Bottom'
    $form.Controls.Add($st)
    $script:UI.Status = $st

    # Ширина фиксированная и с запасом под обе надписи: кнопка привязана к
    # правому краю, и если дать ей расти под текст, она уедет за экран.
    #
    # Правый край — ровно 1346, как у карточек и у панели кнопок наверху
    # (панель разделов: X=226, ширина 1120). Раньше кнопка кончалась на 1336
    # и на десять пикселей не доходила до общей линии.
    #
    # Верх — 792, первая строка под панелью разделов (она занимает 56..791).
    # Раньше кнопка стояла на 788 и залезала на панель четырьмя пикселями,
    # а фон у кнопок прозрачный: в этой полоске проступал фон окна вместо
    # фона панели. Заодно ставим фон сплошным — эмуляция прозрачности здесь
    # ни к чему.
    $bFix = New-RamButton -Text 'Проверить входы' -Width $fixW -Height 26 -Fixed -Kind 'ghost' `
                          -Tooltip 'Проверить, живы ли входы. Если есть мёртвые — пройтись по ним и взять заново из приложения Roblox' `
                          -OnClick {
                              if ([string]$this.Tag.Mode -like 'fix*') { Invoke-RamRepairAll }
                              else { Invoke-RamCheckCookies }
                          }
    $bFix.Tag | Add-Member -NotePropertyName Mode -NotePropertyValue 'check' -Force
    $bFix.BackColor = $t.Bg
    $bFix.Location  = New-Object System.Drawing.Point(($formW - $metrics.GapLg - $fixW), $lineY)
    $bFix.Anchor    = 'Right,Bottom'
    $form.Controls.Add($bFix)
    $script:UI.FixAll = $bFix

    # =================================================== таймеры ============
    $lt = New-Object System.Windows.Forms.Timer
    $lt.Interval = 500
    $lt.Add_Tick({ Invoke-RamSafe -What 'очередь запуска' -Body { Invoke-RamNextLaunch } })
    $script:UI.LaunchTimer = $lt

    $ut = New-Object System.Windows.Forms.Timer
    $ut.Interval = 2000
    $ut.Add_Tick({ Invoke-RamSafe -What 'обновление состояния' -Body { Update-RamInstances } })
    $ut.Start()
    $script:UI.UpdateTimer = $ut

    $sch = New-Object System.Windows.Forms.Timer
    $sch.Interval = 30000
    $sch.Add_Tick({ Invoke-RamSafe -What 'расписание и присмотр' -Body { Invoke-RamScheduleCheck; Invoke-RamWatchCheck } })
    $sch.Start()
    $script:UI.ScheduleTimer = $sch

    $form.Add_ResizeEnd({
        Invoke-RamSafe -What 'перестройка после изменения размера' -Body {
            Build-RamCards
            Update-RamStatsPanel
            Update-RamGamesPanel
            Update-RamProfilesPanel
        }
    })

    # =================================================== горячие клавиши ====
    $form.KeyPreview = $true
    $form.Add_KeyDown({
        param($sender, $e)
        $inText = ($sender.ActiveControl -is [System.Windows.Forms.TextBox])

        if ($e.Control -and $e.KeyCode -eq 'F') {
            Show-RamSection -Key 'accounts'
            $script:UI.Search.Tag.Focus()
            if (-not $script:SearchIsHint) { $script:UI.Search.Tag.SelectAll() }
            $e.Handled = $true; return
        }
        if ($e.KeyCode -eq 'Escape') {
            if ($script:Filter) {
                $script:UI.Search.Tag.Text = ''
                $script:Filter = ''
                $sender.ActiveControl = $null
                Build-RamCards
            }
            $e.Handled = $true; return
        }
        if ($inText) { return }

        switch ($e.KeyCode) {
            'F5'     { Build-RamCards; Update-RamStatsPanel; Write-RamLog 'Обновлено.' 'info'; $e.Handled = $true }
            'Delete' { Invoke-RamDeleteSelected; $e.Handled = $true }
            'A'      { if ($e.Control) { Set-RamAllChecked $true; $e.Handled = $true } }
            'T'      { if ($e.Control) { Invoke-RamTileWindows; $e.Handled = $true } }
            'Z'      { if ($e.Control) { Invoke-RamUndo;         $e.Handled = $true } }
            'Return' {
                $t2 = @(Get-RamTargetAccounts)
                if ($t2.Count -eq 0) { $t2 = @(Get-RamVisibleAccounts) }
                Add-RamToLaunchQueue -Accounts $t2
                $e.Handled = $true
            }
            'D1' { Show-RamSection -Key 'accounts'; $e.Handled = $true }
            'D2' { Show-RamSection -Key 'games';    $e.Handled = $true }
            'D3' { Show-RamSection -Key 'stats';    $e.Handled = $true }
            'D4' { Show-RamSection -Key 'log';      $e.Handled = $true }
        }
    })

    $form.Add_FormClosing({
        param($sender, $e)
        if ($script:Settings.ConfirmOnExit -and $script:Instances.Count -gt 0) {
            if (-not (Confirm-Ram "Запущено клиентов: $($script:Instances.Count).`n`nЗакрыть менеджер? Сами окна Roblox продолжат работать, но новые аккаунты запустить будет нельзя, пока менеджер закрыт.")) {
                $e.Cancel = $true
                return
            }
        }
        # Каждый шаг отдельно: сбой одного не должен мешать остальным и уж
        # тем более ронять программу прямо в момент закрытия.
        Invoke-RamSafe -What 'сохранение при закрытии' -Body { Save-RamState }
        Invoke-RamSafe -What 'снятие замков'          -Body { Disable-RamMultiInstance }
        Invoke-RamSafe -What 'снятие горячих клавиш'  -Body { Unregister-RamHotkeys }
        if ($null -ne $script:UI.Tray) {
            $script:UI.Tray.Visible = $false
            $script:UI.Tray.Dispose()
        }
    })

    # =================================================== значок в часах =====
    if ($script:Settings.MinimizeToTray) {
        $ni = New-Object System.Windows.Forms.NotifyIcon
        try { $ni.Icon = New-RamTrayIcon -Accent $t.Accent } catch { }
        $ni.Text    = $script:AppName
        $ni.Visible = $true
        $script:UI.Tray = $ni

        $ni.Add_DoubleClick({
            $f = $script:UI.Form
            $f.Show(); $f.WindowState = 'Normal'; [void]$f.Activate()
        })

        $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
        $trayMenu.BackColor = $t.Card
        $trayMenu.ForeColor = $t.Text
        $ni.ContextMenuStrip = $trayMenu
        $script:UI.TrayMenu = $trayMenu

        $ni.Add_MouseUp({
            param($sender, $e)
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) { Update-RamTrayMenu }
        })
    }

    $form.Add_Resize({
        if ($script:Settings.MinimizeToTray -and $this.WindowState -eq 'Minimized' -and $null -ne $script:UI.Tray) {
            $this.Hide()
            return
        }

        # ПОЧЕМУ ЗДЕСЬ, А НЕ ТОЛЬКО В ResizeEnd.
        # ResizeEnd бывает лишь когда окно тянут за край мышью. Разворот на
        # весь экран и возврат обратно его НЕ поднимают — поэтому карточки
        # оставались прежней ширины, и в полноэкранном режиме справа зияла
        # пустота. Ловим смену состояния окна и пересобираем списки.
        if ($script:LastWindowState -ne $this.WindowState) {
            $script:LastWindowState = $this.WindowState
            if ($this.WindowState -ne 'Minimized') {
                Invoke-RamSafe -What 'перестройка после разворота' -Body {
                    Build-RamCards
                    Update-RamStatsPanel
                    Update-RamGamesPanel
                    Update-RamProfilesPanel
                }
            }
        }
    })

    # На всякий случай снимаем фокус и после показа окна.
    $form.Add_Shown({
        $this.ActiveControl = $null
        Show-RamSection -Key $script:Section
    })

    $script:UI.Form = $form
    return $form
}


