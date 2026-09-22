#requires -Version 5.1
<#
================================================================================
 modules\UiPulse.ps1 — вид меню «Pulse»
================================================================================
 Узкое боковое меню, полоса действий над списком и список аккаунтов строками,
 как в таблице: имя, игра, три кнопки одной ширины у правого края.

 Раскладку окна считает одна функция — Update-RamPulseLayout, по тем же
 правилам, что и «Dashboard»: высота подписи — строка её шрифта, ширина
 кнопки — ширина надписи, отступы — из одной шкалы (8, 12, 16, 20 точек при
 100%), всё нижнее стоит от фактического низа верхнего.
================================================================================
#>

function Get-RamPulseMetrics {
    $t = $Global:RamTheme
    $m = $t.M
    # Замыкание: снаружи этой функции $m не существует, а K зовут отовсюду.
    $scale = [double]$m.Scale
    $k = { param($n) [int][Math]::Round($n * $scale) }.GetNewClosure()
    $line = { param($f) (Measure-RamText -Text 'Ау' -Font $f).Height + (& $k 2) }
    [pscustomobject]@{
        Scale   = $m.Scale
        K       = $k
        Pad     = & $k 20
        Gap     = $m.Gap
        GapSm   = $m.GapSm
        GapMd   = & $k 12
        GapLg   = $m.GapLg
        NavH    = & $k 36
        NavGap  = & $k 2
        BtnH    = $m.RowH
        RowBtnH = $m.RowHSm
        Title   = & $line $t.FontTitle
        Body    = & $line $t.FontBody
        Small   = & $line $t.FontSmall
        Big     = & $line $t.FontBig
        Scroll  = [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
    }
}

function New-RamPulseNavItem {
    <# Пункт бокового меню: надпись слева, без рамки, подсветка при наведении. #>
    param([string]$Text, [int]$Width, [scriptblock]$OnClick, [string]$Tooltip, [switch]$Muted)
    $t = $Global:RamTheme
    $pm = Get-RamPulseMetrics
    $b = New-RamButton -Text $Text -Width $Width -Height $pm.NavH -Radius ([int][Math]::Round(8 * $pm.Scale)) -Fixed -Align left `
                       -Tooltip $Tooltip -OnClick $OnClick
    $b.Tag.Border = $null
    $b.Tag.Back   = $t.Panel
    $b.Tag.Hover  = $t.CardHover
    $b.Tag.Fore   = $(if ($Muted) { $t.Muted } else { $t.Text })
    return $b
}

function New-RamMainFormClassic {
    $t  = $Global:RamTheme
    $pm = Get-RamPulseMetrics
    $k  = $pm.K
    $menuStyle = Get-RamMenuStyle
    $script:UI.MenuLayout = 'classic'
    $script:UI.Panels     = @{}
    $script:UI.NavButtons = @{}

    # --- ширина бокового меню: по самой длинной надписи, в разумных пределах
    $navTexts = @((Get-RamSections | ForEach-Object { $_.Text }) + @('Быстрая настройка', 'Настройки', 'Справка'))
    $navNeed = 0
    foreach ($tx in $navTexts) {
        $w = (Measure-RamText -Text $tx -Font $t.FontBody).Width + (& $k 28) + (& $k 8)
        if ($w -gt $navNeed) { $navNeed = $w }
    }
    $navW  = [Math]::Min((& $k 240), [Math]::Max((& $k 176), $navNeed))
    $sideW = $navW + (& $k 12) * 2

    # --- стартовый размер
    $formW = $sideW + [int]([int]$menuStyle.BaseContent * $pm.Scale) + $pm.Pad * 2
    $formH = [int](720 * $pm.Scale)
    $waW = 0; $waH = 0
    try {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $waW = $wa.Width; $waH = $wa.Height
        if ($null -ne $Global:RamForceWorkArea) {
            $waW = [int]$Global:RamForceWorkArea.Width
            $waH = [int]$Global:RamForceWorkArea.Height
        }
    } catch { }

    $form = New-RamForm
    $form.Text          = $script:AppName
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.ClientSize    = New-Object System.Drawing.Size($formW, $formH)
    $frameW = $form.Width  - $form.ClientSize.Width
    $frameH = $form.Height - $form.ClientSize.Height
    if ($waW -gt 0 -and $waH -gt 0) {
        $formW = [Math]::Min($formW, $waW - $frameW)
        $formH = [Math]::Min($formH, $waH - $frameH)
        $form.ClientSize = New-Object System.Drawing.Size($formW, $formH)
    }
    $form.StartPosition = 'CenterScreen'
    $form.BackColor     = $t.Bg
    $form.ForeColor     = $t.Text
    $form.Font          = $t.FontBody
    Set-RamDoubleBuffered $form
    $form.Add_HandleCreated({ Set-RamDarkTitleBar $this })
    Set-RamWindowIcon $form

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
        foreach ($f in @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))) { Import-RamDroppedFile -Path $f }
    })

    $ui = [ordered]@{ SideW = $sideW; NavW = $navW }

    # =================================================== боковое меню ========
    $side = New-Object System.Windows.Forms.Panel
    $side.BackColor = $t.Panel
    $form.Controls.Add($side)
    $ui.Side = $side

    $brand = New-RamLabel -Text $script:AppName -X 0 -Y 0 -Width $navW -Height $pm.Big -Font $t.FontBig
    $side.Controls.Add($brand)
    $ui.Brand = $brand
    $brandSub = New-RamLabel -Text ("Pulse  ·  v$($script:AppVersion)") -X 0 -Y 0 -Width $navW -Height $pm.Small -Font $t.FontSmall -Color $t.Muted
    $side.Controls.Add($brandSub)
    $ui.BrandSub = $brandSub

    $navItems = @()
    foreach ($sec in Get-RamSections) {
        $b = New-RamPulseNavItem -Text $sec.Text -Width $navW -OnClick { Show-RamSection -Key $this.Tag.SectionKey }
        $b.Tag | Add-Member -NotePropertyName SectionKey -NotePropertyValue $sec.Key -Force
        $side.Controls.Add($b)
        $script:UI.NavButtons[$sec.Key] = $b
        $navItems += $b
    }
    $ui.NavItems = $navItems

    $bQuick = New-RamPulseNavItem -Text 'Быстрая настройка' -Width $navW -Muted `
                                  -Tooltip 'Разложить всё под расклад «основной + твины на випке»' -OnClick { Show-RamQuickSetup }
    $side.Controls.Add($bQuick)
    $ui.BQuick = $bQuick

    # Сводка: три строки «подпись — число», числа ровно у правого края.
    $summary = New-RamCard -Width $navW -Height 10 -Radius ([int][Math]::Round(10 * $pm.Scale))
    # Под скруглёнными углами — цвет боковой панели, а не окна: иначе углы тёмные.
    $summary.BackColor = $t.Panel
    $side.Controls.Add($summary)
    $ui.Summary = $summary
    $sumPad = $pm.GapMd
    $rowH = [Math]::Max($pm.Small, $pm.Body)
    $valW = (Measure-RamText -Text '9999' -Font $t.FontBody).Width + $pm.GapSm
    $counts = @{}
    $ry = $sumPad
    foreach ($row in @(@{ Key = 'Accounts'; Cap = 'Аккаунтов' }, @{ Key = 'Running'; Cap = 'Запущено' }, @{ Key = 'Queue'; Cap = 'В очереди' })) {
        $summary.Controls.Add((New-RamLabel -Text $row.Cap -X $sumPad -Y $ry -Width ($navW - $sumPad * 2 - $valW) -Height $rowH -Font $t.FontSmall -Color $t.Muted))
        $val = New-RamLabel -Text '0' -X ($navW - $sumPad - $valW) -Y $ry -Width $valW -Height $rowH -Font $t.FontBody -Align 'right'
        $summary.Controls.Add($val)
        $counts[$row.Key] = $val
        $ry += $rowH + $pm.GapSm
    }
    $summary.Height = $ry - $pm.GapSm + $sumPad
    $script:UI.SidebarCounts = [pscustomobject]@{ Accounts = $counts.Accounts; Running = $counts.Running; Queue = $counts.Queue }

    $bSettings = New-RamPulseNavItem -Text 'Настройки' -Width $navW -Muted -OnClick { Show-RamSettingsDialog }
    $bHelp     = New-RamPulseNavItem -Text 'Справка'   -Width $navW -Muted -OnClick { Invoke-RamHelpMenu }
    $side.Controls.Add($bSettings); $side.Controls.Add($bHelp)
    $ui.BSettings = $bSettings; $ui.BHelp = $bHelp

    $author = New-RamLabel -Text $script:AppAuthor -X 0 -Y 0 -Width $navW -Height $pm.Small -Font $t.FontSmall -Color $t.Muted -Truncatable
    $side.Controls.Add($author)
    $ui.Author = $author

    # =================================================== верх содержимого ====
    $sub = New-RamLabel -Text '' -X 0 -Y 0 -Width 10 -Height $pm.Small -Font $t.FontSmall -Color $t.Muted -Truncatable
    $form.Controls.Add($sub)
    $script:UI.Subtitle = $sub
    $ui.Subtitle = $sub

    $search = New-RamModernSearch -Width ([int][Math]::Round(280 * $pm.Scale))
    $form.Controls.Add($search)
    $script:UI.Search = $search
    $ui.Search = $search

    # =================================================== подвал ==============
    $st = New-RamLabel -Text '' -X 0 -Y 0 -Width 10 -Height $pm.Small -Font $t.FontSmall -Color $t.Muted -Truncatable
    $st.Add_Click({ Invoke-RamAppOffer })
    $form.Controls.Add($st)
    $script:UI.Status = $st

    $fixW = [Math]::Max((Get-RamModernTextWidth -Text 'Починить входы (99)'), (Get-RamModernTextWidth -Text 'Проверить входы'))
    $bFix = New-RamButton -Text 'Проверить входы' -Width $fixW -Height $pm.RowBtnH -Fixed -Kind 'ghost' `
                          -Tooltip 'Проверить, живы ли входы. Если есть мёртвые — пройтись по ним и взять заново из приложения Roblox' `
                          -OnClick {
                              if ([string]$this.Tag.Mode -like 'fix*') { Invoke-RamRepairAll }
                              else { Invoke-RamCheckCookies }
                          }
    $bFix.Tag | Add-Member -NotePropertyName Mode -NotePropertyValue 'check' -Force
    $form.Controls.Add($bFix)
    $script:UI.FixAll = $bFix
    $ui.BFix = $bFix

    # =================================================== разделы =============
    $sections = @{}
    $newSection = {
        param([string]$Key)
        $p = New-Object System.Windows.Forms.Panel
        $p.BackColor = $Global:RamTheme.Bg
        $p.Visible   = $false
        $form.Controls.Add($p)
        $script:UI.Panels[$Key] = $p
        return $p
    }
    $newTitle = {
        param([string]$Text)
        New-RamLabel -Text $Text -X 0 -Y 0 -Width ((Measure-RamText -Text $Text -Font $Global:RamTheme.FontTitle).Width + $pm.Gap) -Height $pm.Title -Font $Global:RamTheme.FontTitle
    }

    # ---------------------------------------------------------- аккаунты ----
    $pAcc = & $newSection 'accounts'
    $bAdd = New-RamButton -Text 'Добавить' -Width 1 -Height $pm.BtnH -Kind 'primary' -Tooltip 'Все способы добавить аккаунт' -OnClick { Show-RamAddChooser }
    $bAll = New-RamButton -Text 'Все' -Width 1 -Height $pm.BtnH -Tooltip 'Отметить или снять отметку со всех' -OnClick {
        $any = $false
        foreach ($id in $script:Cards.Keys) { if (-not $script:Cards[$id].Check.Tag.Checked) { $any = $true } }
        Set-RamAllChecked $any
    }
    $bSel = New-RamButton -Text 'С отмеченными  ▾' -Width 1 -Height $pm.BtnH -Tooltip 'Игра, набор, метка, удаление — для отмеченных аккаунтов'
    $selMenu = New-RamContextMenu
    [void](Add-RamMenuItem -Menu $selMenu -Text 'Назначить игру'      -OnClick { Invoke-RamAssignGame })
    [void](Add-RamMenuItem -Menu $selMenu -Text 'Собрать в набор'     -OnClick { Invoke-RamAssignGroup })
    [void](Add-RamMenuItem -Menu $selMenu -Text 'Поставить метку'     -OnClick { Invoke-RamAssignColor })
    [void](Add-RamMenuItem -Menu $selMenu -Separator)
    [void](Add-RamMenuItem -Menu $selMenu -Text 'Убрать из менеджера' -OnClick { Invoke-RamDeleteSelected })
    $bSel.Add_Click({ $selMenu.Show($this, (New-Object System.Drawing.Point(0, $this.Height))) }.GetNewClosure())

    $bTile = New-RamButton -Text 'Окна' -Width 1 -Height $pm.BtnH -Tooltip 'Левый клик — разложить, правый — выбрать раскладку' -OnClick { Invoke-RamTileWindows }
    $script:UI.BtnTile  = $bTile
    $script:UI.TileMenu = New-RamTileWindowsMenu
    $bTile.Add_MouseUp({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) { $script:UI.TileMenu.Show($sender, $e.Location) }
    })
    $bClose = New-RamButton -Text 'Закрыть' -Width 1 -Height $pm.BtnH -Tooltip 'Закрыть окна отмеченных' -OnClick { Invoke-RamStopSelected }
    $bLaunch = New-RamButton -Text 'Запустить' -Width 1 -Height $pm.BtnH -Kind 'primary' `
                             -Tooltip 'Запустить отмеченные свёрнутыми. Если ничего не отмечено — все, что сейчас видно в списке' -OnClick {
        $targets = @(Get-RamTargetAccounts)
        if ($targets.Count -eq 0) { $targets = @(Get-RamVisibleAccounts) }
        Add-RamToLaunchQueue -Accounts $targets
    }
    $script:UI.BtnLaunch = $bLaunch
    foreach ($c in @($bAdd, $bAll, $bSel, $bTile, $bClose, $bLaunch)) { $pAcc.Controls.Add($c) }

    $chips = New-Object System.Windows.Forms.Panel
    $chips.BackColor = $t.Bg
    $chips.Visible   = $false
    $pAcc.Controls.Add($chips)
    $script:UI.ModernChips = $chips

    $cards = New-RamScrollPanel -Width 100 -Height 100
    $pAcc.Controls.Add($cards)
    $script:UI.Cards = $cards
    $sections['accounts'] = [pscustomobject]@{ Panel = $pAcc; Title = $null; Left = @($bAdd, $bAll, $bSel); Right = @($bTile, $bClose, $bLaunch); Hint = $null; Chips = $chips; Body = $cards }

    # ---------------------------------------------------------- игры --------
    $pGames = & $newSection 'games'
    $gTitle = & $newTitle 'Мои игры'
    $bOwnGame = New-RamButton -Text 'Добавить игру' -Width 1 -Height $pm.BtnH -Kind 'primary' `
                              -Tooltip 'Добавить игру по ссылке, приглашению на приватный сервер или по номеру' -OnClick {
        $val = Show-RamInputDialog -Title 'Своя игра' `
                 -Prompt ("Вставь ссылку на игру, приглашение на приватный сервер или просто её номер.`n" +
                          'Название подтянется само.')
        if ([string]::IsNullOrWhiteSpace($val)) { return }
        $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        try   { $g = Resolve-RamGameInput -Value $val }
        catch { Show-RamError $_.Exception.Message; return }
        finally { $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::Default }
        if ($null -eq $g -or -not $g.PlaceId) {
            Show-RamError 'Не удалось понять, что это за игра. Нужна ссылка на игру, приглашение на приватный сервер или номер игры.'
            return
        }
        $title = if ($g.GameName) { $g.GameName } else { "ID $($g.PlaceId)" }
        Add-RamSavedGame -PlaceId $g.PlaceId -LinkCode $g.LinkCode -Title $title
        Update-RamGamesPanel
        Write-RamLog "В список игр добавлена «$title»." 'ok'
    }
    $bPopular = New-RamButton -Text 'Популярные из Roblox' -Width 1 -Height $pm.BtnH `
                              -Tooltip 'Показать игры, в которые сейчас играют больше всего, и добавить их в список' -OnClick {
        Show-RamPopularGamesDialog
        Update-RamGamesPanel
    }
    $gHint = New-RamLabel -Text 'Добавь игру ссылкой или из популярных. Потом отметь аккаунты в разделе «Аккаунты» и нажми на игре «Назначить отмеченным».' `
                          -X 0 -Y 0 -Width 10 -Height $pm.Small -Font $t.FontSmall -Color $t.Muted
    $gamesHost = New-RamScrollPanel -Width 100 -Height 100
    foreach ($c in @($gTitle, $bOwnGame, $bPopular, $gHint, $gamesHost)) { $pGames.Controls.Add($c) }
    $script:UI.GamesHost = $gamesHost
    $script:UI.BtnAddGame = $bOwnGame
    $sections['games'] = [pscustomobject]@{ Panel = $pGames; Title = $gTitle; Left = @(); Right = @($bOwnGame, $bPopular); Hint = $gHint; Chips = $null; Body = $gamesHost }

    # ---------------------------------------------------------- профили -----
    $pProf = & $newSection 'profiles'
    $pTitle = & $newTitle 'Профили запуска'
    $bStarter = New-RamButton -Text 'Готовый профиль  ▾' -Width 1 -Height $pm.BtnH -Kind 'primary' `
                              -Tooltip 'Добавить готовый профиль с популярной игрой — работает сразу'
    $profMenu = New-RamContextMenu
    foreach ($sp in Get-RamStarterProfiles) {
        [void](Add-RamMenuItem -Menu $profMenu -Text $sp.Name -Tag $sp -OnClick {
            Add-RamStarterProfile -Profile $this.Tag
            Update-RamProfilesPanel
        })
    }
    $bStarter.Add_Click({ $profMenu.Show($this, (New-Object System.Drawing.Point(0, $this.Height))) }.GetNewClosure())
    $bSaveProf = New-RamButton -Text 'Сохранить текущее как профиль' -Width 1 -Height $pm.BtnH -OnClick { Invoke-RamSaveProfile }
    $script:UI.BtnAddProfile = $bSaveProf
    $pHint = New-RamLabel -Text 'Связка «набор аккаунтов + игра». Одной кнопкой ставит игру всем и запускает.' `
                          -X 0 -Y 0 -Width 10 -Height $pm.Small -Font $t.FontSmall -Color $t.Muted
    $profHost = New-RamScrollPanel -Width 100 -Height 100
    foreach ($c in @($pTitle, $bStarter, $bSaveProf, $pHint, $profHost)) { $pProf.Controls.Add($c) }
    $script:UI.ProfilesHost = $profHost
    $sections['profiles'] = [pscustomobject]@{ Panel = $pProf; Title = $pTitle; Left = @(); Right = @($bStarter, $bSaveProf); Hint = $pHint; Chips = $null; Body = $profHost }

    # ---------------------------------------------------------- статистика --
    $pStats = & $newSection 'stats'
    $sTitle = & $newTitle 'Статистика'
    $bReset = New-RamButton -Text 'Обнулить' -Width 1 -Height $pm.BtnH -Kind 'ghost' -OnClick {
        if (-not (Confirm-Ram 'Обнулить всю статистику? Сами аккаунты и игры останутся на месте.')) { return }
        foreach ($a in $script:Accounts) { $a.LaunchCount = 0; $a.CrashCount = 0; $a.PlaySeconds = 0 }
        Save-RamState
        Update-RamStatsPanel
        Write-RamLog 'Статистика обнулена.' 'ok'
    }
    $statsHost = New-RamScrollPanel -Width 100 -Height 100
    foreach ($c in @($sTitle, $bReset, $statsHost)) { $pStats.Controls.Add($c) }
    $script:UI.StatsHost = $statsHost
    $sections['stats'] = [pscustomobject]@{ Panel = $pStats; Title = $sTitle; Left = @(); Right = @($bReset); Hint = $null; Chips = $null; Body = $statsHost }

    # ---------------------------------------------------------- журнал ------
    $pLog = & $newSection 'log'
    $lTitle = & $newTitle 'Журнал'
    $bCopyLog = New-RamButton -Text 'Скопировать' -Width 1 -Height $pm.BtnH -Kind 'ghost' -OnClick {
        try {
            [System.Windows.Forms.Clipboard]::SetText($script:UI.Log.Text)
            Set-RamStatus 'Журнал скопирован в буфер обмена.'
        } catch {
            Show-RamMessage -Kind 'warn' -Message "Скопировать журнал не вышло: буфер обмена сейчас занят другой программой.`n`nПопробуй ещё раз через секунду."
        }
    }
    $bClearLog = New-RamButton -Text 'Очистить' -Width 1 -Height $pm.BtnH -Kind 'ghost' -OnClick {
        $script:UI.Log.Clear()
        [void]$script:LogLines.Clear()
        Set-RamStatus 'Журнал в окне очищен. Файлы журнала в data\logs не тронуты.'
    }
    $logHost = New-Object System.Windows.Forms.Panel
    $logHost.BackColor = $t.LogBack
    $logHost.Padding   = New-Object System.Windows.Forms.Padding(($pm.Gap + $pm.GapSm), $pm.Gap, $pm.Gap, $pm.Gap)
    $log = New-Object System.Windows.Forms.TextBox
    $log.Multiline   = $true
    $log.ReadOnly    = $true
    $log.ScrollBars  = 'Vertical'
    $log.BorderStyle = 'None'
    $log.BackColor   = $t.LogBack
    $log.ForeColor   = $t.Muted
    $log.Font        = $t.FontMono
    $log.Dock        = 'Fill'
    Set-RamScrollTheme -Control $log
    $logHost.Controls.Add($log)
    $script:UI.Log = $log
    if ($script:LogLines.Count -gt 0) {
        $log.Text = (@($script:LogLines) -join [Environment]::NewLine) + [Environment]::NewLine
        $log.SelectionStart = $log.TextLength
        $log.ScrollToCaret()
    }
    foreach ($c in @($lTitle, $bCopyLog, $bClearLog, $logHost)) { $pLog.Controls.Add($c) }
    $sections['log'] = [pscustomobject]@{ Panel = $pLog; Title = $lTitle; Left = @(); Right = @($bCopyLog, $bClearLog); Hint = $null; Chips = $null; Body = $logHost }

    $ui.Sections = $sections
    $script:UI.Pulse = [pscustomobject]$ui
    $script:UI.Form = $form
    $script:UI.FreshFocusTimer = New-RamFreshWindowTimer

    # --- минимальный размер: меню плюс строка аккаунта с кнопками
    $minClientW = $sideW + $pm.Pad * 2 + [int][Math]::Round([int]$menuStyle.MinCardWidth * $pm.Scale) + $pm.Scroll + $pm.Gap
    $minClientH = [int][Math]::Round(560 * $pm.Scale)
    if ($waW -gt 0 -and $waH -gt 0) {
        $minClientW = [Math]::Min($minClientW, $waW - $frameW)
        $minClientH = [Math]::Min($minClientH, $waH - $frameH)
    }
    $form.MinimumSize = New-Object System.Drawing.Size(($minClientW + $frameW), ($minClientH + $frameH))

    Register-RamMainFormRuntime -Form $form

    Restore-RamMainWindowBounds -Form $form
    $script:LastWindowState = $form.WindowState
    Update-RamPulseLayout
    $script:UI.MenuLayout = 'classic'
    return $form
}

function Update-RamPulseLayout {
    <# Раскладка всего окна вида «Pulse» — по текущему размеру и разделу. #>
    if (-not $script:UI.ContainsKey('Pulse') -or $null -eq $script:UI.Pulse) { return }
    $ui = $script:UI.Pulse
    $form = $script:UI.Form
    if ($null -eq $form -or $form.IsDisposed -or $null -eq $ui.Side -or $ui.Side.IsDisposed) { return }
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return }

    $pm = Get-RamPulseMetrics
    $k  = $pm.K
    $cw = $form.ClientSize.Width
    $ch = $form.ClientSize.Height
    $centerIn = { param($ctl, [int]$top, [int]$h) [int]($top + ($h - $ctl.Height) / 2) }

    # ------------------------------------------------------ боковое меню -----
    $side = $ui.Side
    $side.Location = New-Object System.Drawing.Point(0, 0)
    $side.Size = New-Object System.Drawing.Size($ui.SideW, $ch)
    $sx = & $k 12
    $textX = $sx + (& $k 14)

    $y = & $k 20
    $ui.Brand.Location = New-Object System.Drawing.Point($textX, $y)
    $ui.Brand.Width = $ui.NavW - (& $k 14)
    $y = $ui.Brand.Bottom
    $ui.BrandSub.Location = New-Object System.Drawing.Point($textX, $y)
    $ui.BrandSub.Width = $ui.NavW - (& $k 14)
    $y = $ui.BrandSub.Bottom + (& $k 20)

    foreach ($b in $ui.NavItems) {
        $b.Location = New-Object System.Drawing.Point($sx, $y)
        $y += $b.Height + $pm.NavGap
    }
    $y += $pm.GapMd
    $ui.BQuick.Location = New-Object System.Drawing.Point($sx, $y)
    $y = $ui.BQuick.Bottom + $pm.GapLg

    # Низ: автор у самого края, над ним «Настройки» и «Справка».
    $ui.Author.Location = New-Object System.Drawing.Point($textX, ($ch - (& $k 16) - $ui.Author.Height))
    $ui.Author.Width = $ui.NavW - (& $k 14)
    $ui.BHelp.Location = New-Object System.Drawing.Point($sx, ($ui.Author.Top - $pm.GapMd - $ui.BHelp.Height))
    $ui.BSettings.Location = New-Object System.Drawing.Point($sx, ($ui.BHelp.Top - $pm.NavGap - $ui.BSettings.Height))

    # Сводка — между верхней и нижней группой, если помещается.
    $ui.Summary.Location = New-Object System.Drawing.Point($sx, $y)
    $ui.Summary.Visible = (($ui.Summary.Bottom + $pm.GapLg) -le $ui.BSettings.Top)

    # ------------------------------------------------------ верх и низ -------
    $cx = $ui.SideW + $pm.Pad
    $right = $cw - $pm.Pad
    $topH = $pm.BtnH
    $topY = $pm.GapLg
    $ui.Search.Location = New-Object System.Drawing.Point(($right - $ui.Search.Width), (& $centerIn $ui.Search $topY $topH))
    $ui.Subtitle.Location = New-Object System.Drawing.Point($cx, (& $centerIn $ui.Subtitle $topY $topH))
    $ui.Subtitle.Width = [Math]::Max(10, $ui.Search.Left - $pm.GapLg - $cx)

    $footH = $pm.RowBtnH + $pm.GapLg
    $footY = $ch - $footH
    $ui.BFix.Location = New-Object System.Drawing.Point(($right - $ui.BFix.Width), (& $centerIn $ui.BFix $footY $footH))
    $status = $script:UI.Status
    $status.Location = New-Object System.Drawing.Point($cx, (& $centerIn $status $footY $footH))
    $status.Width = [Math]::Max(10, $ui.BFix.Left - $pm.GapLg - $cx)

    # ------------------------------------------------------ разделы ----------
    $secTop = $topY + $topH + $pm.GapMd
    $secH = [Math]::Max(1, $footY - $secTop)
    $secW = [Math]::Max(1, $cw - $ui.SideW - $pm.Pad)
    foreach ($key in @($ui.Sections.Keys)) {
        $sec = $ui.Sections[$key]
        $p = $sec.Panel
        if ($null -eq $p -or $p.IsDisposed) { continue }
        $p.Location = New-Object System.Drawing.Point(($ui.SideW + $pm.Pad), $secTop)
        $p.Size = New-Object System.Drawing.Size($secW, $secH)

        # Строки — до зарезервированной полосы прокрутки, кнопки — до того же края.
        $isList = ($sec.Body -is [System.Windows.Forms.FlowLayoutPanel])
        $lineW = if ($isList) { [Math]::Max(1, $secW - $pm.Pad - $pm.Scroll - $pm.Gap + $pm.Pad) } else { [Math]::Max(1, $secW - $pm.Pad) }
        if ($isList) { $lineW = [Math]::Max(1, $secW - $pm.Scroll - $pm.Gap) }

        $y = 0
        $rowBottom = 0
        if ($null -ne $sec.Title) {
            $sec.Title.Location = New-Object System.Drawing.Point(0, (& $centerIn $sec.Title 0 $pm.BtnH))
            $rowBottom = Set-RamModernFlow -Left @() -Right $sec.Right -X ($sec.Title.Right + $pm.GapLg) -Y 0 -Width ([Math]::Max(1, $lineW - $sec.Title.Right - $pm.GapLg))
            $rowBottom = [Math]::Max($rowBottom, $pm.BtnH)
        } else {
            $rowBottom = Set-RamModernFlow -Left $sec.Left -Right $sec.Right -X 0 -Y 0 -Width $lineW
        }
        $y = $rowBottom + $pm.GapMd

        if ($null -ne $sec.Hint) {
            $hintH = (Measure-RamText -Text $sec.Hint.Text -Font $sec.Hint.Font -MaxWidth ([Math]::Max(1, $lineW - $pm.Gap))).Height + $pm.GapSm
            $sec.Hint.Location = New-Object System.Drawing.Point(0, $y)
            $sec.Hint.Size = New-Object System.Drawing.Size($lineW, $hintH)
            $y += $hintH + $pm.GapSm
        }

        if ($null -ne $sec.Chips -and $script:UI.ModernChipsShown) {
            $chipBottom = Set-RamModernFlow -Left @($sec.Chips.Controls) -X 0 -Y 0 -Width $lineW
            $sec.Chips.Location = New-Object System.Drawing.Point(0, $y)
            $sec.Chips.Size = New-Object System.Drawing.Size($lineW, [Math]::Max(1, $chipBottom))
            $y += $chipBottom + $pm.GapMd
        }

        $bodyW = if ($isList) { $secW } else { [Math]::Max(1, $secW - $pm.Pad) }
        $bodyH = [Math]::Max(1, $secH - $y - $(if ($isList) { 0 } else { $pm.GapMd }))
        $sec.Body.Location = New-Object System.Drawing.Point(0, $y)
        $sec.Body.Size = New-Object System.Drawing.Size($bodyW, $bodyH)
    }
}

# ------------------------------------------------------ строки аккаунтов ----

function Get-RamPulseRowLayout {
    <#
      Строка аккаунта:
        ▌ [☐] (ав)  Имя  набор          Игра                         [Пуск][Правка][Закрыть]
                    @ник · ID          настройки · заметка · R$
      Колонки имени и игры делят ширину по долям, кнопки — одной ширины.
    #>
    param([int]$Width, [switch]$Compact)
    $t  = $Global:RamTheme
    $pm = Get-RamPulseMetrics
    $k  = $pm.K
    $padX = & $k 16
    $padY = & $k 12
    $avS  = if ($Compact) { & $k 28 } else { & $k 40 }
    $chkS = & $k 20
    $textBlockH = if ($Compact) { $pm.Title } else { $pm.Title + $pm.Small }
    $H = [Math]::Max($avS, $textBlockH) + $padY * 2
    if ($Compact) { $H = [Math]::Max($avS, $textBlockH) + (& $k 8) * 2 }

    $btnH = if ($Compact) { & $k 26 } else { $pm.RowBtnH }
    $labels = if ($Compact) { @('Пуск', 'Вход', 'Изм.', 'Стоп') } else { @('Пуск', 'Войти', 'Правка', 'Закрыть') }
    $btnW = 0
    foreach ($l in $labels) { $bw = Get-RamModernTextWidth -Text $l; if ($bw -gt $btnW) { $btnW = $bw } }
    $btnGap = $pm.GapSm + (& $k 2)
    $btnsW = $btnW * 3 + $btnGap * 2
    $btnX = $Width - $padX - $btnsW

    $chkX = $padX + (& $k 4)
    $avX = $chkX + $chkS + $pm.GapMd
    $textX = $avX + $avS + $pm.GapMd
    $flex = [Math]::Max((& $k 120), $btnX - $pm.GapLg - $textX)
    # Имя — не шире 320 точек: на широком окне лишнее уходит игре, и колонка
    # игры начинается рядом с именем, а не посреди строки.
    $nameW = [Math]::Min((& $k 320), [int]($flex * 0.44))
    $gameX = $textX + $nameW + $pm.GapLg
    $gameW = [Math]::Max((& $k 40), $btnX - $pm.GapLg - $gameX)
    $textTop = [int](($H - $textBlockH) / 2)

    [pscustomobject]@{
        Width = $Width; Height = $H; Compact = [bool]$Compact
        CheckX = $chkX; CheckY = [int](($H - $chkS) / 2)
        AvatarX = $avX; AvatarY = [int](($H - $avS) / 2); AvatarSize = $avS
        TextX = $textX; NameW = $nameW; GameX = $gameX; GameW = $gameW
        Line1Y = $textTop; Line2Y = $textTop + $pm.Title
        BtnY = [int](($H - $btnH) / 2); BtnH = $btnH; BtnW = $btnW; BtnGap = $btnGap; BtnX = $btnX
        Labels = $labels
    }
}

function Build-RamCardsClassic {
    <# Полная пересборка строк аккаунтов вида «Pulse». #>
    if (-not $script:UI.ContainsKey('Cards') -or $null -eq $script:UI.Cards) { return }
    $t  = $Global:RamTheme
    $pm = Get-RamPulseMetrics
    $panel = $script:UI.Cards
    $compact = [bool]$script:Settings.CompactCards

    foreach ($id in @($script:Cards.Keys)) {
        $entry = $script:Cards[$id]
        if ($null -ne $entry -and $entry.Check.Tag.Checked) { $script:CheckedIds[[string]$id] = $true }
        else { [void]$script:CheckedIds.Remove([string]$id) }
    }

    $listScroll = Enter-RamListRebuild -Panel $panel
    try {
        Clear-RamPanelControls -Panel $panel
        $script:Cards = @{}
        $script:AvatarQueue.Clear()
        $W = Get-RamCardWidth

        $visible = @(Get-RamVisibleAccounts)
        if (@($script:Accounts).Count -eq 0) {
            $panel.Controls.Add((New-RamNoticeCard -Width $W -Title 'Пока ни одного аккаунта' `
                -Text 'Войди в приложении Roblox под нужным аккаунтом и нажми «Добавить» — менеджер заберёт вход сам, пароль вводить не надо.'))
        } elseif ($visible.Count -eq 0) {
            $why = if ($script:GroupFilter) { "В наборе «$($script:GroupFilter)» ничего не нашлось" }
                   else { "По запросу «$($script:Filter)» ничего не нашлось" }
            $panel.Controls.Add((New-RamNoticeCard -Width $W -Title $why -Text 'Сбрось поиск (Esc) или выбери набор «Все».'))
        } else {
            $L = Get-RamPulseRowLayout -Width $W -Compact:$compact
            foreach ($a in $visible) { $panel.Controls.Add((New-RamPulseRow -Account $a -Layout $L)) }
        }
    } finally {
        Exit-RamListRebuild -Panel $panel -ScrollY $listScroll
    }

    Update-RamCardStates
    Update-RamHeaderCounts
    Update-RamGroupBar
    Update-RamStatusLine
}

function New-RamPulseRow {
    param([Parameter(Mandatory)]$Account, [Parameter(Mandatory)]$Layout)
    $t  = $Global:RamTheme
    $pm = Get-RamPulseMetrics
    $a  = $Account
    $L  = $Layout

    $card = New-RamCard -Width $L.Width -Height $L.Height -Radius ([int][Math]::Round(10 * $pm.Scale))
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, $pm.Gap)
    $card.Tag.AccountId = $a.Id
    $card.Tag | Add-Member -NotePropertyName Stripe -NotePropertyValue (Get-RamLabelColor -Key ([string]$a.Color)) -Force

    # Метка — полоса по левому краю строки, ровно по её скруглению.
    $card.Add_Paint({
        param($s, $e)
        $th = $Global:RamTheme
        $sc = $th.M.Scale
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        if ($null -ne $s.Tag.Stripe) {
            $path = New-RamRoundRect -Rect $rect -Radius $s.Tag.Radius
            $state = $g.Save()
            try {
                $g.SetClip($path)
                $b = New-Object System.Drawing.SolidBrush($s.Tag.Stripe)
                $g.FillRectangle($b, 0, 0, [Math]::Max(3, [int][Math]::Round(4 * $sc)), $s.Height)
                $b.Dispose()
            } finally { $g.Restore($state); $path.Dispose() }
        }
        $entry = $script:Cards[[string]$s.Tag.AccountId]
        if ($null -ne $entry -and $entry.Check.Tag.Checked) {
            $w = [single][Math]::Max(2, [Math]::Round(2 * $sc))
            $inset = [int][Math]::Ceiling($w / 2)
            $r2 = New-Object System.Drawing.Rectangle($inset, $inset, ($s.Width - 1 - $inset * 2), ($s.Height - 1 - $inset * 2))
            $path2 = New-RamRoundRect -Rect $r2 -Radius ([Math]::Max(1, [int]$s.Tag.Radius - $inset))
            $ap = New-Object System.Drawing.Pen($th.Accent, $w)
            $g.DrawPath($ap, $path2)
            $ap.Dispose(); $path2.Dispose()
        }
    })

    $chk = New-RamCheckBox -X $L.CheckX -Y $L.CheckY
    $chk.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
    if ($script:CheckedIds.ContainsKey([string]$a.Id)) { $chk.Tag.Checked = $true }
    $chk.Add_Click({
        $id = [string]$this.Tag.AccountId
        if ($this.Tag.Checked) { $script:CheckedIds[$id] = $true }
        else { [void]$script:CheckedIds.Remove($id) }
        if ($script:Cards.ContainsKey($id)) { $script:Cards[$id].Card.Invalidate() }
        Update-RamStatusLine
    })
    $card.Controls.Add($chk)

    $av = New-RamAvatarBox -Size $L.AvatarSize
    $av.Location = New-Object System.Drawing.Point($L.AvatarX, $L.AvatarY)
    $card.Controls.Add($av)
    Set-RamAvatarImage -Box $av -Image $null -Letter $(if ($a.Alias) { $a.Alias } else { '?' })
    $cached = $null
    if ([int64]$a.UserId -gt 0) {
        $file = Join-Path (Get-RamAvatarDir) "$($a.UserId).png"
        if (Test-Path -LiteralPath $file) { $cached = Get-RamCachedAvatarImage -UserId $a.UserId -Path $file }
    }
    if ($null -ne $cached) { Set-RamAvatarImage -Box $av -Image $cached -Letter $a.Alias }

    # --- колонка имени: имя и набор, под ними ник
    $groupW = 0
    $showGroup = -not [string]::IsNullOrWhiteSpace($a.Group)
    if ($showGroup) {
        $groupW = [Math]::Min([int]($L.NameW * 0.45), (Measure-RamText -Text ([string]$a.Group) -Font $t.FontSmall).Width + $pm.GapSm)
    }
    $aliasNeed = (Measure-RamText -Text ([string]$a.Alias) -Font $t.FontTitle).Width + $pm.GapSm
    $aliasW = [Math]::Max(1, [Math]::Min($aliasNeed, $L.NameW - $(if ($showGroup) { $groupW + $pm.GapSm } else { 0 })))
    $lblName = New-RamLabel -Text $a.Alias -X $L.TextX -Y $L.Line1Y -Width $aliasW -Height $pm.Title -Font $t.FontTitle -Truncatable
    $card.Controls.Add($lblName)
    $lblGroup = $null
    if ($showGroup) {
        $gy = $L.Line1Y + [int](($pm.Title - $pm.Small) / 2) + 1
        $lblGroup = New-RamLabel -Text ([string]$a.Group) -X ($L.TextX + $aliasW + $pm.GapSm) -Y $gy -Width $groupW -Height $pm.Small `
                                 -Font $t.FontSmall -Color $t.Accent -Truncatable
        $card.Controls.Add($lblGroup)
    }

    $lblSub = $null
    if (-not $L.Compact) {
        $subParts = @()
        if ([string]$a.CookieOk -eq 'no') { $subParts += 'вход мёртв' }
        if ($a.Username) { $subParts += "@$($a.Username)" } else { $subParts += 'вход не проверен' }
        if ([int64]$a.UserId -gt 0) { $subParts += "ID $($a.UserId)" }
        $lblSub = New-RamLabel -Text ($subParts -join '  ·  ') -X $L.TextX -Y $L.Line2Y -Width $L.NameW -Height $pm.Small -Font $t.FontSmall `
                               -Color $(if ([string]$a.CookieOk -eq 'no') { $t.Danger } else { $t.Muted }) -Truncatable
        $card.Controls.Add($lblSub)
    }

    # --- колонка игры: игра, под ней настройки клиента, заметка и Robux
    $gameTxt = if ($a.GameName) { [string]$a.GameName } elseif ($a.PlaceId) { "ID $($a.PlaceId)" } else { 'просто Roblox' }
    if ($a.LinkCode) { $gameTxt += '  ·  приват' }
    $lblGame = New-RamLabel -Text $gameTxt -X $L.GameX -Y $L.Line1Y -Width $L.GameW -Height $pm.Title `
                            -Color $(if ($a.PlaceId) { $t.Text } else { $t.Muted }) -Truncatable
    $card.Controls.Add($lblGame)
    $lblMeta = $null
    if (-not $L.Compact) {
        $metaParts = @()
        $summary = Get-RamAccountSettingsSummary -Account $a
        if ($summary) { $metaParts += $summary }
        if (-not [string]::IsNullOrWhiteSpace($a.Note)) { $metaParts += [string]$a.Note }
        if ([int]$a.Robux -ge 0) { $metaParts += "$($a.Robux) R$" }
        if ($metaParts.Count -gt 0) {
            $lblMeta = New-RamLabel -Text ($metaParts -join '  ·  ') -X $L.GameX -Y $L.Line2Y -Width $L.GameW -Height $pm.Small `
                                    -Font $t.FontSmall -Color $t.Muted -Truncatable
            $card.Controls.Add($lblMeta)
        }
    }

    # --- три кнопки одной ширины у правого края
    $x = $L.BtnX
    if ([string]$a.CookieOk -eq 'no') {
        $bPlay = New-RamButton -Text $L.Labels[1] -Width $L.BtnW -Height $L.BtnH -Fixed -Kind 'danger' `
                               -Tooltip 'Войти в этот аккаунт заново — вход умер' -OnClick { Invoke-RamRelogin -Id $this.Tag.AccountId }
    } else {
        $bPlay = New-RamButton -Text $L.Labels[0] -Width $L.BtnW -Height $L.BtnH -Fixed -Kind 'primary' `
                               -Tooltip 'Запустить этот аккаунт свёрнутым' -OnClick { Add-RamToLaunchQueue -Accounts @((Get-RamAccountById -Id $this.Tag.AccountId)) }
    }
    $bPlay.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
    $bPlay.Location = New-Object System.Drawing.Point($x, $L.BtnY)
    $card.Controls.Add($bPlay)
    $x += $L.BtnW + $L.BtnGap

    $bEdit = New-RamButton -Text $L.Labels[2] -Width $L.BtnW -Height $L.BtnH -Fixed -Tooltip 'Настройки аккаунта' `
                           -OnClick { Invoke-RamCardEdit -Id $this.Tag.AccountId }
    $bEdit.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
    $bEdit.Location = New-Object System.Drawing.Point($x, $L.BtnY)
    $card.Controls.Add($bEdit)
    $x += $L.BtnW + $L.BtnGap

    $bStop = New-RamButton -Text $L.Labels[3] -Width $L.BtnW -Height $L.BtnH -Fixed -Tooltip 'Закрыть окно этого аккаунта' `
                           -OnClick { Invoke-RamCardStop -Id ([string]$this.Tag.AccountId) }
    $bStop.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
    $bStop.Location = New-Object System.Drawing.Point($x, $L.BtnY)
    $card.Controls.Add($bStop)

    Add-RamModernCardMouse -Card $card -AccountId $a.Id -Controls @($lblName, $lblGroup, $lblSub, $lblGame, $lblMeta, $av)

    $script:Cards[$a.Id] = @{
        Card = $card; Check = $chk; Avatar = $av
        Name = $lblName; Sub = $lblSub; Game = $lblGame; Dot = $null
        Play = $bPlay; Edit = $bEdit; Stop = $bStop
        AvatarLoaded = ($null -ne $cached)
    }
    if ([int64]$a.UserId -gt 0 -and $null -eq $cached) { [void]$script:AvatarQueue.Add($a.Id) }
    return $card
}

function Update-RamCardStatesClassic {
    <#
      Состояние в «Pulse» — цветом рамки аватарки и подсказкой при наведении:
      зелёная — в игре, жёлтая — загружается, синяя — в очереди, красная —
      вход мёртв. Отдельной колонки с подписью нет.
    #>
    $t = $Global:RamTheme
    foreach ($a in $script:Accounts) {
        $entry = $script:Cards[$a.Id]
        if ($null -eq $entry) { continue }
        $inst = $script:Instances[$a.Id]
        if ($null -ne $inst) {
            if ($inst.Handle -ne [IntPtr]::Zero) { Set-RamAvatarBorderColor -Box $entry.Avatar -Color $t.Ok }
            else { Set-RamAvatarBorderColor -Box $entry.Avatar -Color $t.Warn }
        } elseif ($script:LaunchQueue -contains $a.Id) {
            Set-RamAvatarBorderColor -Box $entry.Avatar -Color $t.Accent
        } else {
            $border = if ([string]$a.CookieOk -eq 'no') { $t.Danger } else { $t.Border }
            Set-RamAvatarBorderColor -Box $entry.Avatar -Color $border
        }
    }
    Update-RamHeaderCounts
    Update-RamStatusLine
}
