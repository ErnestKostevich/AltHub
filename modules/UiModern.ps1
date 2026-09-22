#requires -Version 5.1
<#
================================================================================
 modules\UiModern.ps1 — вид меню «Новое»
================================================================================
 Вкладки разделов сверху, плитки аккаунтов в сетке по ширине окна, строка
 действий над каждым разделом и нижняя строка состояния.

 ГЛАВНОЕ ПРАВИЛО ЭТОГО ФАЙЛА: НИ ОДНОЙ КООРДИНАТЫ ЧИСЛОМ.
 Высота любой подписи — это высота строки её шрифта. Ширина кнопки — ширина
 её надписи. Отступы — из таблицы метрик темы, которая уже умножена на
 масштаб экрана. Всё, что стоит ниже друг друга, стоит от фактического низа
 соседа. Именно вписанные числа делали «Игры» и «Профили» кривыми на 150% и
 200%: подпись высотой 22 точки при строке шрифта в 41 не рисуется вовсе.

 Значков-рисунков вида H₂O здесь нет намеренно: они часть его меню.

 Раскладку всего окна считает ОДНА функция — Update-RamModernLayout. Она
 зовётся при сборке, на каждое изменение размера и при смене раздела.
================================================================================
#>

# ------------------------------------------------------------ мерки ---------

function Get-RamModernMetrics {
    <# Высоты строк и отступы вида «Новое» — от шрифтов и масштаба. #>
    $t = $Global:RamTheme
    $m = $t.M
    $k = { param($n) [int][Math]::Round($n * $m.Scale) }
    $line = { param($f) (Measure-RamText -Text 'Ау' -Font $f).Height + (& $k 2) }
    [pscustomobject]@{
        Scale  = $m.Scale
        Pad    = & $k 16
        TilePad = & $k 14
        Gap    = $m.Gap
        GapSm  = $m.GapSm
        GapLg  = $m.GapLg
        Title  = & $line $t.FontTitle
        Body   = & $line $t.FontBody
        Small  = & $line $t.FontSmall
        Big    = & $line $t.FontBig
        BtnH   = $m.RowH
        ChipH  = $m.RowHSm
        Avatar = & $k 56
        Check  = & $k 20
        Scroll = [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
    }
}

function Get-RamModernTextWidth {
    <# Ширина кнопки под надпись — та же формула, что внутри New-RamButton. #>
    param([string]$Text)
    return (Measure-RamText -Text $Text -Font $Global:RamTheme.FontBody).Width + $Global:RamTheme.M.BtnPadX
}

function Get-RamModernGrid {
    <#
      Сколько плиток встаёт в ряд и какой они ширины.

      Полосу прокрутки резервируем всегда: иначе с появлением полосы плитки
      становятся уже, сетка пересобирается и правый край дёргается.
      Правое поле плитки (Margin) равно зазору, поэтому ряд из N плиток
      занимает ровно доступную ширину.
    #>
    param([Parameter(Mandatory)]$Panel, [int]$MinWidth = 360, [int]$MaxColumns = 6)
    $mm = Get-RamModernMetrics
    $avail = [Math]::Max(1, $Panel.Width - $mm.Scroll - $mm.Gap)
    $minW  = [int][Math]::Round($MinWidth * $mm.Scale)
    $cols  = [int][Math]::Floor(($avail + $mm.Gap) / ($minW + $mm.Gap))
    $cols  = [Math]::Max(1, [Math]::Min($MaxColumns, $cols))
    $w     = [int][Math]::Floor(($avail - ($cols - 1) * $mm.Gap) / $cols)
    return [pscustomobject]@{ Columns = $cols; Width = [Math]::Max(1, $w); Avail = $avail }
}

function Set-RamModernFlow {
    <#
      Раскладывает кнопки строками слева направо с переносом. Кнопки из
      -Right прижимаются к правому краю последней строки, а если им там
      тесно — уходят строкой ниже. Возвращает низ последней строки.
    #>
    param([object[]]$Left = @(), [object[]]$Right = @(), [int]$X, [int]$Y, [int]$Width)
    $gap = $Global:RamTheme.M.Gap
    $Left  = @($Left  | Where-Object { $null -ne $_ })
    $Right = @($Right | Where-Object { $null -ne $_ })
    $rowH = 0
    foreach ($c in @($Left + $Right)) { if ($c.Height -gt $rowH) { $rowH = $c.Height } }
    if ($rowH -eq 0) { return $Y }

    $cx = $X; $cy = $Y
    foreach ($c in $Left) {
        if ($cx -gt $X -and ($cx + $c.Width) -gt ($X + $Width)) { $cx = $X; $cy += $rowH + $gap }
        $c.Location = New-Object System.Drawing.Point($cx, ($cy + [int](($rowH - $c.Height) / 2)))
        $cx += $c.Width + $gap
    }
    if ($Right.Count -gt 0) {
        $rw = ($Right | Measure-Object -Property Width -Sum).Sum + $gap * ($Right.Count - 1)
        if ($Left.Count -gt 0 -and ($cx + $rw) -gt ($X + $Width)) { $cy += $rowH + $gap }
        $rx = [Math]::Max($X, $X + $Width - $rw)
        foreach ($c in $Right) {
            if ($rx -gt $X -and ($rx + $c.Width) -gt ($X + $Width)) { $rx = $X; $cy += $rowH + $gap }
            $c.Location = New-Object System.Drawing.Point($rx, ($cy + [int](($rowH - $c.Height) / 2)))
            $rx += $c.Width + $gap
        }
    }
    return $cy + $rowH
}

function Enter-RamListRebuild {
    <#
      Перед пересборкой списка с прокруткой.

      Список с AutoScroll держит «ширину содержимого» от прошлой раскладки. Если
      перед сужением окна карточки стояли в две колонки, пересобранные узкие
      карточки раскладывались по ТОЙ ширине — снова по две в ряд — и сами же её
      поддерживали: вторая карточка навсегда торчала за край. На время
      пересборки прокрутку выключаем, место прокрутки запоминаем.
    #>
    param([Parameter(Mandatory)]$Panel)
    $y = 0
    try { $y = -$Panel.AutoScrollPosition.Y } catch { }
    $Panel.SuspendLayout()
    $Panel.AutoScroll = $false
    return $y
}

function Exit-RamListRebuild {
    <# После пересборки: прокрутка обратно и то же место, где человек был. #>
    param([Parameter(Mandatory)]$Panel, [int]$ScrollY = 0)
    $Panel.ResumeLayout()
    $Panel.AutoScroll = $true
    $Panel.PerformLayout()
    if ($ScrollY -gt 0) {
        try { $Panel.AutoScrollPosition = New-Object System.Drawing.Point(0, $ScrollY) } catch { }
    }
}

function Clear-RamPanelControls {
    <# Controls.Clear() только вынимает элементы — окна и GDI освобождаем явно. #>
    param([Parameter(Mandatory)]$Panel)
    foreach ($old in @($Panel.Controls)) {
        try {
            if ($null -ne $old.ContextMenuStrip) { $old.ContextMenuStrip.Dispose(); $old.ContextMenuStrip = $null }
            $old.Dispose()
        } catch { }
    }
    $Panel.Controls.Clear()
}

function Add-RamModernNotice {
    <# Плитка во всю ширину: заголовок и пояснение с переносом по словам. #>
    param([Parameter(Mandatory)]$Panel, [string]$Title, [string]$Text)
    $t  = $Global:RamTheme
    $mm = Get-RamModernMetrics
    $grid = Get-RamModernGrid -Panel $Panel -MinWidth 10 -MaxColumns 1
    $W = $grid.Width
    $textW = [Math]::Max(1, $W - $mm.Pad * 2)
    $textH = (Measure-RamText -Text $Text -Font $t.FontBody -MaxWidth ([Math]::Max(1, $textW - $mm.Gap))).Height + $mm.GapSm
    $card = New-RamCard -Width $W -Height ($mm.Pad + $mm.Title + $mm.GapSm + $textH + $mm.Pad)
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, $mm.Gap, $mm.Gap)
    $card.Controls.Add((New-RamLabel -Text $Title -X $mm.Pad -Y $mm.Pad -Width $textW -Height $mm.Title -Font $t.FontTitle -Truncatable))
    $card.Controls.Add((New-RamLabel -Text $Text -X $mm.Pad -Y ($mm.Pad + $mm.Title + $mm.GapSm) -Width $textW -Height $textH `
                                     -Font $t.FontBody -Color $t.Muted))
    $Panel.Controls.Add($card)
    return $card
}

# ------------------------------------------------------ элементы шапки ------

function New-RamModernTab {
    <# Вкладка раздела: надпись, подсветка наведения, черта под активной. #>
    param([string]$Text, [string]$Key, [int]$Height)
    $t = $Global:RamTheme
    $padX = [int][Math]::Round(14 * $t.M.Scale)
    $w = (Measure-RamText -Text $Text -Font $t.FontBody).Width + $padX * 2

    $p = New-Object System.Windows.Forms.Panel
    $p.Size      = New-Object System.Drawing.Size($w, $Height)
    $p.BackColor = $t.Panel
    $p.Cursor    = [System.Windows.Forms.Cursors]::Hand
    Set-RamDoubleBuffered $p
    $p.Tag = [pscustomobject]@{ Caption = $Text; SectionKey = $Key; Active = $false; IsHover = $false }

    $p.Add_Paint({
        param($s, $e)
        $st = $s.Tag
        $th = $Global:RamTheme
        $sc = $th.M.Scale
        $g  = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $bg = New-Object System.Drawing.SolidBrush($th.Panel)
        $g.FillRectangle($bg, 0, 0, $s.Width, $s.Height)
        $bg.Dispose()

        if ($st.IsHover -and -not $st.Active) {
            $inset = [int][Math]::Round(6 * $sc)
            $r = New-Object System.Drawing.Rectangle(0, $inset, ($s.Width - 1), ($s.Height - $inset * 2))
            $path = New-RamRoundRect -Rect $r -Radius ([int][Math]::Round(8 * $sc))
            $hb = New-Object System.Drawing.SolidBrush($th.CardHover)
            $g.FillPath($hb, $path)
            $hb.Dispose(); $path.Dispose()
        }

        $fore = if ($st.Active) { $th.Accent } elseif ($st.IsHover) { $th.Text } else { $th.Muted }
        $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor
                 [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                 [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
                 [System.Windows.Forms.TextFormatFlags]::NoPrefix
        [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$st.Caption, $th.FontBody,
            (New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)), $fore, $flags)

        if ($st.Active) {
            $lineH = [Math]::Max(2, [int][Math]::Round(3 * $sc))
            $inset = [int][Math]::Round(12 * $sc)
            $ab = New-Object System.Drawing.SolidBrush($th.Accent)
            $g.FillRectangle($ab, $inset, ($s.Height - $lineH), [Math]::Max(1, $s.Width - $inset * 2), $lineH)
            $ab.Dispose()
        }
    })
    $p.Add_MouseEnter({ $this.Tag.IsHover = $true;  $this.Invalidate() })
    $p.Add_MouseLeave({ $this.Tag.IsHover = $false; $this.Invalidate() })
    $p.Add_Click({ Show-RamSection -Key $this.Tag.SectionKey })
    return $p
}

function New-RamModernLogo {
    <# Знак программы: скруглённый квадрат цвета темы с буквой. #>
    param([int]$Size)
    $p = New-Object System.Windows.Forms.Panel
    $p.Size      = New-Object System.Drawing.Size($Size, $Size)
    $p.BackColor = $Global:RamTheme.Panel
    Set-RamDoubleBuffered $p
    $p.Add_Paint({
        param($s, $e)
        $th = $Global:RamTheme
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $r = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        $path = New-RamRoundRect -Rect $r -Radius ([int]($s.Width * 0.28))
        $b = New-Object System.Drawing.SolidBrush($th.Accent)
        $g.FillPath($b, $path)
        $b.Dispose(); $path.Dispose()
        $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor
                 [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                 [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
                 [System.Windows.Forms.TextFormatFlags]::NoPadding
        [System.Windows.Forms.TextRenderer]::DrawText($g, 'A', $th.FontTitle,
            (New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)), [System.Drawing.Color]::White, $flags)
    })
    return $p
}

function Invoke-RamHelpMenu {
    <# «Справка»: мастер заново или README. Общая для кнопки и меню «Ещё». #>
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

function New-RamModernSearch {
    <# Поле поиска с подсказкой внутри и поиском с задержкой. #>
    param([int]$Width)
    $t = $Global:RamTheme
    $search = New-RamTextBox -Width $Width -Height $t.M.RowH
    $script:SearchPlaceholder = 'поиск: имя, ник, игра, заметка'
    $script:SearchIsHint      = $true

    $sTb = $search.Tag
    $sTb.Text      = $script:SearchPlaceholder
    $sTb.ForeColor = $t.Muted
    # Кнопки — нарисованные панели, фокус не принимают. Без этого WinForms
    # при открытии окна ставит фокус в поиск и стирает подсказку.
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
        # Ищут аккаунты — значит, показываем аккаунты.
        if ($script:Section -ne 'accounts') { Show-RamSection -Key 'accounts' }
        $script:UI.SearchTimer.Stop()
        $script:UI.SearchTimer.Start()
    })
    return $search
}

function Set-RamModernSearchWidth {
    <# У поля своя внутренняя TextBox — её ширину тянем вместе с рамкой. #>
    param($Search, [int]$Width)
    if ($null -eq $Search -or $Search.IsDisposed) { return }
    if ($Search.Width -eq $Width) { return }
    $Search.Width = $Width
    $Search.Tag.Width = [Math]::Max(10, $Width - 18)
    $Search.Invalidate()
}

function New-RamTileWindowsMenu {
    <# Меню «Окна» по правому клику: раскладки и «запомнить места». #>
    $tileMenu = New-RamContextMenu
    foreach ($mode in @(
        @{ K = 'main';    T = 'Основной крупно, твины мелко' },
        @{ K = 'grid';    T = 'Сеткой' },
        @{ K = 'cascade'; T = 'Каскадом' },
        @{ K = 'columns'; T = 'Колонками' },
        @{ K = 'rows';    T = 'Строками' })) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($mode.T)
        $mi.Tag = $mode.K
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
    return $tileMenu
}

# --------------------------------------------------------- сборка окна ------

function New-RamMainFormModern {
    $t  = $Global:RamTheme
    $mm = Get-RamModernMetrics
    $menuStyle = Get-RamMenuStyle
    $script:UI.MenuLayout = 'modern'
    $script:UI.Panels     = @{}
    $script:UI.NavButtons = @{}
    $script:UI.Tabs       = @{}

    # --- стартовый размер: от вида меню и масштаба, но не больше экрана
    $formW = [int]([int]$menuStyle.BaseContent * $mm.Scale)
    $formH = [int](720 * $mm.Scale)
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
        # В рабочую область окно обязано влезть ВМЕСТЕ с рамкой.
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

    $ui = [ordered]@{}

    # =================================================== шапка ===============
    $header = New-Object System.Windows.Forms.Panel
    $header.BackColor = $t.Panel
    $form.Controls.Add($header)
    $ui.Header = $header

    # Шапка — одна строка высотой в кнопку плюс поля сверху и снизу.
    $headRowH = $mm.BtnH + $mm.GapLg + $mm.Gap
    $ui.HeadRowH = $headRowH

    $logo = New-RamModernLogo -Size ([int][Math]::Round(30 * $mm.Scale))
    $header.Controls.Add($logo)
    $ui.Logo = $logo

    $brandW = (Measure-RamText -Text $script:AppName -Font $t.FontTitle).Width + $mm.GapSm
    $brand = New-RamLabel -Text $script:AppName -X 0 -Y 0 -Width $brandW -Height $mm.Title -Font $t.FontTitle
    $header.Controls.Add($brand)
    $ui.Brand = $brand

    $verText = "DASHBOARD  ·  v$($script:AppVersion)"
    $verW = (Measure-RamText -Text $verText -Font $t.FontSmall).Width + $mm.Gap
    $ver = New-RamLabel -Text $verText -X 0 -Y 0 -Width $verW -Height $mm.Small -Font $t.FontSmall -Color $t.Accent
    $header.Controls.Add($ver)
    $ui.Version = $ver

    $tabs = @()
    foreach ($sec in Get-RamSections) {
        $tab = New-RamModernTab -Text $sec.Text -Key $sec.Key -Height $headRowH
        $header.Controls.Add($tab)
        $script:UI.Tabs[$sec.Key] = $tab
        $tabs += $tab
    }
    $ui.TabList = $tabs


    $bSettings = New-RamButton -Text 'Настройки' -Width 1 -Height $mm.BtnH -Kind 'ghost' -OnClick { Show-RamSettingsDialog }
    $header.Controls.Add($bSettings)
    $ui.BSettings = $bSettings

    $bMore = New-RamButton -Text 'Ещё  ▾' -Width 1 -Height $mm.BtnH -Kind 'ghost' -Tooltip 'Быстрая настройка, справка, мастер первого запуска'
    $moreMenu = New-RamContextMenu
    [void](Add-RamMenuItem -Menu $moreMenu -Text 'Быстрая настройка' -OnClick { Show-RamQuickSetup })
    [void](Add-RamMenuItem -Menu $moreMenu -Text 'Проверить входы'   -OnClick { Invoke-RamCheckCookies })
    [void](Add-RamMenuItem -Menu $moreMenu -Separator)
    [void](Add-RamMenuItem -Menu $moreMenu -Text 'Справка'           -OnClick { Invoke-RamHelpMenu })
    $bMore.Add_Click({ $moreMenu.Show($this, (New-Object System.Drawing.Point(0, $this.Height))) }.GetNewClosure())
    $header.Controls.Add($bMore)
    $ui.BMore = $bMore

    # =================================================== подвал ==============
    $footer = New-Object System.Windows.Forms.Panel
    $footer.BackColor = $t.Panel
    $form.Controls.Add($footer)
    $ui.Footer = $footer

    $st = New-RamLabel -Text '' -X 0 -Y 0 -Width 10 -Height $mm.Small -Font $t.FontSmall -Color $t.Muted -Truncatable
    # Клик по строке работает, когда в ней висит предложение добавить аккаунт
    # из приложения Roblox (Invoke-RamAppOffer). В остальное время — ничего.
    $st.Add_Click({ Invoke-RamAppOffer })
    $footer.Controls.Add($st)
    $script:UI.Status = $st

    # Ширина прибита под самую длинную надпись («Починить входы (99)»): кнопка
    # живёт у правого края и расти вправо ей некуда.
    $fixW = [Math]::Max((Get-RamModernTextWidth -Text 'Починить входы (99)'), (Get-RamModernTextWidth -Text 'Проверить входы'))
    $bFix = New-RamButton -Text 'Проверить входы' -Width $fixW -Height $mm.ChipH -Fixed -Kind 'ghost' `
                          -Tooltip 'Проверить, живы ли входы. Если есть мёртвые — пройтись по ним и взять заново из приложения Roblox' `
                          -OnClick {
                              if ([string]$this.Tag.Mode -like 'fix*') { Invoke-RamRepairAll }
                              else { Invoke-RamCheckCookies }
                          }
    $bFix.Tag | Add-Member -NotePropertyName Mode -NotePropertyValue 'check' -Force
    $footer.Controls.Add($bFix)
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

    # ---------------------------------------------------------- аккаунты ----
    $pAcc = & $newSection 'accounts'
    $bLaunch = New-RamButton -Text 'Запустить' -Width 1 -Height $mm.BtnH -Kind 'primary' `
                             -Tooltip 'Запустить отмеченные свёрнутыми. Если ничего не отмечено — все, что сейчас видно в списке' -OnClick {
        $targets = @(Get-RamTargetAccounts)
        if ($targets.Count -eq 0) { $targets = @(Get-RamVisibleAccounts) }
        Add-RamToLaunchQueue -Accounts $targets
    }
    $script:UI.BtnLaunch = $bLaunch
    $bClose = New-RamButton -Text 'Закрыть' -Width 1 -Height $mm.BtnH -Tooltip 'Закрыть окна отмеченных' -OnClick { Invoke-RamStopSelected }
    $bTile  = New-RamButton -Text 'Окна' -Width 1 -Height $mm.BtnH -Tooltip 'Левый клик — разложить окна, правый — выбрать раскладку' -OnClick { Invoke-RamTileWindows }
    $script:UI.BtnTile  = $bTile
    $script:UI.TileMenu = New-RamTileWindowsMenu
    $bTile.Add_MouseUp({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) { $script:UI.TileMenu.Show($sender, $e.Location) }
    })
    $bAll = New-RamButton -Text 'Выбрать все' -Width 1 -Height $mm.BtnH -Kind 'ghost' -Tooltip 'Отметить все или снять все отметки' -OnClick {
        $any = $false
        foreach ($id in $script:Cards.Keys) { if (-not $script:Cards[$id].Check.Tag.Checked) { $any = $true } }
        Set-RamAllChecked $any
    }
    $bSel = New-RamButton -Text 'С отмеченными  ▾' -Width 1 -Height $mm.BtnH -Kind 'ghost' `
                          -Tooltip 'Игра, набор, метка, удаление — для отмеченных аккаунтов'
    $selMenu = New-RamContextMenu
    [void](Add-RamMenuItem -Menu $selMenu -Text 'Назначить игру'      -OnClick { Invoke-RamAssignGame })
    [void](Add-RamMenuItem -Menu $selMenu -Text 'Собрать в набор'     -OnClick { Invoke-RamAssignGroup })
    [void](Add-RamMenuItem -Menu $selMenu -Text 'Поставить метку'     -OnClick { Invoke-RamAssignColor })
    [void](Add-RamMenuItem -Menu $selMenu -Separator)
    [void](Add-RamMenuItem -Menu $selMenu -Text 'Убрать из менеджера' -OnClick { Invoke-RamDeleteSelected })
    $bSel.Add_Click({ $selMenu.Show($this, (New-Object System.Drawing.Point(0, $this.Height))) }.GetNewClosure())
    $bAdd = New-RamButton -Text 'Добавить аккаунт' -Width 1 -Height $mm.BtnH -Kind 'primary' -Tooltip 'Все способы добавить аккаунт' -OnClick { Show-RamAddChooser }
    # Поиск ищет только аккаунты — и стоит рядом с ними, а не в общей шапке.
    $search = New-RamModernSearch -Width ([int][Math]::Round(280 * $mm.Scale))
    $script:UI.Search = $search
    $ui.Search = $search
    foreach ($c in @($bAdd, $search, $bAll, $bSel, $bTile, $bClose, $bLaunch)) { $pAcc.Controls.Add($c) }

    # Полоска наборов: кнопки создаёт Update-RamModernChips, ставит — раскладка.
    $chips = New-Object System.Windows.Forms.Panel
    $chips.BackColor = $t.Bg
    $chips.Visible   = $false
    $pAcc.Controls.Add($chips)
    $script:UI.ModernChips = $chips

    $cards = New-RamScrollPanel -Width 100 -Height 100
    $cards.FlowDirection = 'LeftToRight'
    $cards.WrapContents  = $true
    $pAcc.Controls.Add($cards)
    $script:UI.Cards = $cards
    $sections['accounts'] = [pscustomobject]@{ Panel = $pAcc; Left = @($bAdd, $search); Right = @($bAll, $bSel, $bTile, $bClose, $bLaunch); Hint = $null; Chips = $chips; Body = $cards; Search = $search }

    # ---------------------------------------------------------- игры --------
    $pGames = & $newSection 'games'
    $bOwnGame = New-RamButton -Text 'Добавить игру' -Width 1 -Height $mm.BtnH -Kind 'primary' `
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
    $bPopular = New-RamButton -Text 'Популярные из Roblox' -Width 1 -Height $mm.BtnH `
                              -Tooltip 'Показать игры, в которые сейчас играют больше всего, и добавить их в список' -OnClick {
        Show-RamPopularGamesDialog
        Update-RamGamesPanel
    }
    $gamesHint = New-RamLabel -Text 'Добавь игру ссылкой или из популярных. Потом отметь аккаунты во вкладке «Аккаунты» и нажми на игре «Назначить отмеченным».' `
                              -X 0 -Y 0 -Width 10 -Height $mm.Small -Font $t.FontSmall -Color $t.Muted
    $gamesHost = New-RamScrollPanel -Width 100 -Height 100
    $gamesHost.FlowDirection = 'LeftToRight'
    $gamesHost.WrapContents  = $true
    foreach ($c in @($bOwnGame, $bPopular, $gamesHint, $gamesHost)) { $pGames.Controls.Add($c) }
    $script:UI.GamesHost = $gamesHost
    $script:UI.BtnAddGame = $bOwnGame
    $sections['games'] = [pscustomobject]@{ Panel = $pGames; Left = @($bOwnGame, $bPopular); Right = @(); Hint = $gamesHint; Chips = $null; Body = $gamesHost; Search = $null }

    # ---------------------------------------------------------- профили -----
    $pProf = & $newSection 'profiles'
    $bStarter = New-RamButton -Text 'Готовый профиль  ▾' -Width 1 -Height $mm.BtnH -Kind 'primary' `
                              -Tooltip 'Добавить готовый профиль с популярной игрой — работает сразу'
    $profMenu = New-RamContextMenu
    foreach ($sp in Get-RamStarterProfiles) {
        [void](Add-RamMenuItem -Menu $profMenu -Text $sp.Name -Tag $sp -OnClick {
            Add-RamStarterProfile -Profile $this.Tag
            Update-RamProfilesPanel
        })
    }
    $bStarter.Add_Click({ $profMenu.Show($this, (New-Object System.Drawing.Point(0, $this.Height))) }.GetNewClosure())
    $bSaveProf = New-RamButton -Text 'Сохранить текущее как профиль' -Width 1 -Height $mm.BtnH -OnClick { Invoke-RamSaveProfile }
    $script:UI.BtnAddProfile = $bSaveProf
    $profHint = New-RamLabel -Text 'Профиль — это набор аккаунтов и игра. Одной кнопкой ставит игру всем и запускает.' `
                             -X 0 -Y 0 -Width 10 -Height $mm.Small -Font $t.FontSmall -Color $t.Muted
    $profHost = New-RamScrollPanel -Width 100 -Height 100
    $profHost.FlowDirection = 'LeftToRight'
    $profHost.WrapContents  = $true
    foreach ($c in @($bStarter, $bSaveProf, $profHint, $profHost)) { $pProf.Controls.Add($c) }
    $script:UI.ProfilesHost = $profHost
    $sections['profiles'] = [pscustomobject]@{ Panel = $pProf; Left = @($bStarter, $bSaveProf); Right = @(); Hint = $profHint; Chips = $null; Body = $profHost; Search = $null }

    # ---------------------------------------------------------- статистика --
    $pStats = & $newSection 'stats'
    $bReset = New-RamButton -Text 'Обнулить статистику' -Width 1 -Height $mm.BtnH -Kind 'ghost' -OnClick {
        if (-not (Confirm-Ram 'Обнулить всю статистику? Сами аккаунты и игры останутся на месте.')) { return }
        foreach ($a in $script:Accounts) { $a.LaunchCount = 0; $a.CrashCount = 0; $a.PlaySeconds = 0 }
        Save-RamState
        Update-RamStatsPanel
        Write-RamLog 'Статистика обнулена.' 'ok'
    }
    $statsHost = New-RamScrollPanel -Width 100 -Height 100
    $statsHost.FlowDirection = 'LeftToRight'
    $statsHost.WrapContents  = $true
    foreach ($c in @($bReset, $statsHost)) { $pStats.Controls.Add($c) }
    $script:UI.StatsHost = $statsHost
    $sections['stats'] = [pscustomobject]@{ Panel = $pStats; Left = @($bReset); Right = @(); Hint = $null; Chips = $null; Body = $statsHost; Search = $null }

    # ---------------------------------------------------------- журнал ------
    $pLog = & $newSection 'log'
    $bCopyLog = New-RamButton -Text 'Скопировать' -Width 1 -Height $mm.BtnH -Kind 'ghost' -OnClick {
        try {
            [System.Windows.Forms.Clipboard]::SetText($script:UI.Log.Text)
            Set-RamStatus 'Журнал скопирован в буфер обмена.'
        } catch {
            Show-RamMessage -Kind 'warn' -Message "Скопировать журнал не вышло: буфер обмена сейчас занят другой программой.`n`nПопробуй ещё раз через секунду."
        }
    }
    $bClearLog = New-RamButton -Text 'Очистить' -Width 1 -Height $mm.BtnH -Kind 'ghost' -OnClick {
        $script:UI.Log.Clear()
        [void]$script:LogLines.Clear()
        Set-RamStatus 'Журнал в окне очищен. Файлы журнала в data\logs не тронуты.'
    }
    $logHost = New-Object System.Windows.Forms.Panel
    $logHost.BackColor = $t.LogBack
    $logHost.Padding   = New-Object System.Windows.Forms.Padding(($mm.Gap + $mm.GapSm), $mm.Gap, $mm.Gap, $mm.Gap)
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
    foreach ($c in @($bCopyLog, $bClearLog, $logHost)) { $pLog.Controls.Add($c) }
    $sections['log'] = [pscustomobject]@{ Panel = $pLog; Left = @($bCopyLog, $bClearLog); Right = @(); Hint = $null; Chips = $null; Body = $logHost; Search = $null }

    $ui.Sections = $sections
    $script:UI.Modern = [pscustomobject]$ui
    $script:UI.Form = $form

    # --- минимальный размер: вкладки в одну строку и одна плитка аккаунта
    $tabsW = ($tabs | Measure-Object -Property Width -Sum).Sum
    $minClientW = [Math]::Max(
        ($mm.Pad * 2 + $logo.Width + $mm.Gap + $tabsW + $mm.GapLg + $bSettings.Width + $mm.Gap + $bMore.Width),
        ($mm.Pad * 2 + [int][Math]::Round([int]$menuStyle.MinCardWidth * $mm.Scale) + $mm.Scroll + $mm.Gap))
    $minClientH = [int][Math]::Round(560 * $mm.Scale)
    if ($waW -gt 0 -and $waH -gt 0) {
        $minClientW = [Math]::Min($minClientW, $waW - $frameW)
        $minClientH = [Math]::Min($minClientH, $waH - $frameH)
    }
    $form.MinimumSize = New-Object System.Drawing.Size(($minClientW + $frameW), ($minClientH + $frameH))

    Register-RamMainFormRuntime -Form $form

    Restore-RamMainWindowBounds -Form $form
    $script:LastWindowState = $form.WindowState
    Update-RamModernLayout
    $script:UI.MenuLayout = 'modern'
    return $form
}

function Update-RamModernLayout {
    <# Раскладка всего окна вида «Dashboard» — по текущему размеру и разделу. #>
    if (-not $script:UI.ContainsKey('Modern') -or $null -eq $script:UI.Modern) { return }
    $ui = $script:UI.Modern
    $form = $script:UI.Form
    if ($null -eq $form -or $form.IsDisposed -or $null -eq $ui.Header -or $ui.Header.IsDisposed) { return }
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return }

    $mm = Get-RamModernMetrics
    $cw = $form.ClientSize.Width
    $ch = $form.ClientSize.Height
    $pad = $mm.Pad
    $rowH = $ui.HeadRowH
    $centerIn = { param($ctl, [int]$top, [int]$h) [int]($top + ($h - $ctl.Height) / 2) }

    # ------------------------------------------------------------- шапка ----
    # Одна строка: знак, название, вкладки — слева; «Настройки» и «Ещё» — справа.
    $rightW = $ui.BSettings.Width + $mm.Gap + $ui.BMore.Width
    $tabsW = ($ui.TabList | Measure-Object -Property Width -Sum).Sum
    $x = $pad
    $ui.Logo.Location = New-Object System.Drawing.Point($x, (& $centerIn $ui.Logo 0 $rowH))
    $x = $ui.Logo.Right + $mm.Gap

    # Что из названия помещается: целиком, без подписи версии или только знак.
    $spaceForBrand = $cw - $pad - $rightW - $mm.GapLg - $tabsW - $mm.GapLg - $x
    $showVersion = ($ui.Brand.Width + $ui.Version.Width + $mm.GapSm) -le $spaceForBrand
    $showBrand   = $ui.Brand.Width -le $spaceForBrand
    $ui.Brand.Visible = $showBrand
    $ui.Version.Visible = $showBrand -and $showVersion
    if ($showBrand) {
        $ui.Brand.Location = New-Object System.Drawing.Point($x, (& $centerIn $ui.Brand 0 $rowH))
        $x = $ui.Brand.Right
        if ($showVersion) {
            $ui.Version.Location = New-Object System.Drawing.Point(($x + $mm.GapSm), ($ui.Brand.Bottom - $ui.Version.Height - [int]($mm.GapSm / 2)))
            $x = $ui.Version.Right
        }
        $x += $mm.GapLg
    }
    foreach ($tab in $ui.TabList) {
        $tab.Location = New-Object System.Drawing.Point($x, 0)
        $x += $tab.Width
    }
    $ui.BMore.Location = New-Object System.Drawing.Point(($cw - $pad - $ui.BMore.Width), (& $centerIn $ui.BMore 0 $rowH))
    $ui.BSettings.Location = New-Object System.Drawing.Point(($ui.BMore.Left - $mm.Gap - $ui.BSettings.Width), (& $centerIn $ui.BSettings 0 $rowH))
    $ui.Header.Location = New-Object System.Drawing.Point(0, 0)
    $ui.Header.Size = New-Object System.Drawing.Size($cw, $rowH)

    # ------------------------------------------------------------- подвал ---
    $footH = [Math]::Max($ui.BFix.Height, $mm.Small) + $mm.Gap * 2
    $ui.Footer.Location = New-Object System.Drawing.Point(0, ($ch - $footH))
    $ui.Footer.Size = New-Object System.Drawing.Size($cw, $footH)
    $ui.BFix.Location = New-Object System.Drawing.Point(($cw - $pad - $ui.BFix.Width), (& $centerIn $ui.BFix 0 $footH))
    $status = $script:UI.Status
    $status.Size = New-Object System.Drawing.Size([Math]::Max(10, $ui.BFix.Left - $pad * 2), $mm.Small)
    $status.Location = New-Object System.Drawing.Point($pad, (& $centerIn $status 0 $footH))

    # ------------------------------------------------------------- разделы --
    $top = $rowH
    $secH = [Math]::Max(1, $ch - $footH - $top)
    foreach ($key in @($ui.Sections.Keys)) {
        $sec = $ui.Sections[$key]
        $p = $sec.Panel
        if ($null -eq $p -or $p.IsDisposed) { continue }
        $p.Location = New-Object System.Drawing.Point(0, $top)
        $p.Size = New-Object System.Drawing.Size($cw, $secH)

        # Правый край строки действий — ровно там, где кончаются плитки:
        # у списка справа зарезервированы полоса прокрутки и зазор.
        $bodyW = [Math]::Max(1, $cw - $pad)
        $isGrid = ($sec.Body -is [System.Windows.Forms.FlowLayoutPanel])
        $lineW = if ($isGrid) { [Math]::Max(1, $bodyW - $mm.Scroll - $mm.Gap) } else { [Math]::Max(1, $cw - $pad * 2) }

        # Поиск растягивается на всё, что осталось в строке, но в разумных пределах.
        if ($null -ne $sec.Search -and -not $sec.Search.IsDisposed) {
            $others = 0
            foreach ($c in @($sec.Left + $sec.Right)) { if ($c -ne $sec.Search) { $others += $c.Width + $mm.Gap } }
            $gapBetween = $mm.GapLg
            $free = $lineW - $others - $gapBetween
            $minS = [int][Math]::Round(200 * $mm.Scale)
            $maxS = [int][Math]::Round(360 * $mm.Scale)
            $sw = if ($free -ge $minS) { [Math]::Min($maxS, $free) } else { [Math]::Min($maxS, [Math]::Max($minS, $lineW - $sec.Left[0].Width - $mm.Gap)) }
            Set-RamModernSearchWidth -Search $sec.Search -Width $sw
        }

        $y = $mm.GapLg
        $y = (Set-RamModernFlow -Left $sec.Left -Right $sec.Right -X $pad -Y $y -Width $lineW) + $mm.Gap + $mm.GapSm

        if ($null -ne $sec.Hint) {
            $hintH = (Measure-RamText -Text $sec.Hint.Text -Font $sec.Hint.Font -MaxWidth ([Math]::Max(1, $lineW - $mm.Gap))).Height + $mm.GapSm
            $sec.Hint.Location = New-Object System.Drawing.Point($pad, $y)
            $sec.Hint.Size = New-Object System.Drawing.Size($lineW, $hintH)
            $y += $hintH + $mm.GapSm
        }

        if ($null -ne $sec.Chips -and $script:UI.ModernChipsShown) {
            $chipBottom = Set-RamModernFlow -Left @($sec.Chips.Controls) -X 0 -Y 0 -Width $lineW
            $sec.Chips.Location = New-Object System.Drawing.Point($pad, $y)
            $sec.Chips.Size = New-Object System.Drawing.Size($lineW, [Math]::Max(1, $chipBottom))
            $y += $chipBottom + $mm.Gap + $mm.GapSm
        }

        $bodyWidth = if ($isGrid) { $bodyW } else { [Math]::Max(1, $cw - $pad * 2) }
        $bodyH = [Math]::Max(1, $secH - $y - $(if ($isGrid) { 0 } else { $mm.GapLg }))
        $sec.Body.Location = New-Object System.Drawing.Point($pad, $y)
        $sec.Body.Size = New-Object System.Drawing.Size($bodyWidth, $bodyH)
    }
}

function Update-RamShellLayout {
    <# Раскладка окна того вида, что построен сейчас: «Dashboard» или «Pulse». #>
    if ($script:UI.ContainsKey('Modern') -and $null -ne $script:UI.Modern) { Update-RamModernLayout; return }
    if ($script:UI.ContainsKey('Pulse') -and $null -ne $script:UI.Pulse) { Update-RamPulseLayout; return }
}

function Update-RamModernChips {
    <# Полоска наборов: «Все» и по кнопке на набор. Прячется, если наборов нет. #>
    if (-not $script:UI.ContainsKey('ModernChips')) { return }
    $bar = $script:UI.ModernChips
    if ($null -eq $bar -or $bar.IsDisposed) { return }
    $mm = Get-RamModernMetrics

    $items = @([pscustomobject]@{ Key = ''; Text = 'Все' })
    foreach ($g in Get-RamGroups) { $items += [pscustomobject]@{ Key = $g; Text = $g } }

    $bar.SuspendLayout()
    try {
        Clear-RamPanelControls -Panel $bar
        # Visible скрытого раздела всегда false — помним своё решение отдельно.
        $script:UI.ModernChipsShown = ($items.Count -gt 1)
        $bar.Visible = $script:UI.ModernChipsShown
        if ($script:UI.ModernChipsShown) {
            foreach ($it in $items) {
                $active = ([string]$script:GroupFilter -eq [string]$it.Key)
                $b = New-RamButton -Text $it.Text -Width 1 -Height $mm.ChipH -Radius ([int]($mm.ChipH / 2)) `
                                   -Kind $(if ($active) { 'primary' } else { 'ghost' }) -OnClick {
                    $script:GroupFilter = $this.Tag.GroupKey
                    Build-RamCards
                }
                $b.Tag | Add-Member -NotePropertyName GroupKey -NotePropertyValue $it.Key -Force
                $bar.Controls.Add($b)
            }
        }
    } finally {
        $bar.ResumeLayout()
    }
    Update-RamShellLayout
}

# ------------------------------------------------ общая жизнь окна ----------

function Register-RamMainFormRuntime {
    <#
      Таймеры, горячие клавиши, закрытие, значок в часах и реакция на размер.
      Поведение то же, что у классического окна и окна H₂O, — отличается
      только тем, что раскладку зовёт Update-RamShellLayout.
    #>
    param([Parameter(Mandatory)]$Form)

    $lt = New-Object System.Windows.Forms.Timer
    $lt.Interval = 500
    $lt.Add_Tick({ Invoke-RamSafe -What 'очередь запуска' -Body { Invoke-RamNextLaunch } })
    $script:UI.LaunchTimer = $lt
    $script:UI.FreshFocusTimer = New-RamFreshWindowTimer

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

    # Сетку плиток пересобираем, когда движение края на миг замерло, а не на
    # каждый пиксель: это создание контролов заново для каждой плитки.
    $resizeTimer = New-Object System.Windows.Forms.Timer
    $resizeTimer.Interval = 75
    $resizeTimer.Add_Tick({
        $this.Stop()
        Invoke-RamSafe -What 'адаптивная перестройка окна' -Body { Update-RamAfterResize }
    })
    $script:UI.ResizeLiveTimer = $resizeTimer

    $Form.Add_Resize({
        # Минус всегда сворачивает в панель задач и никогда не прячет окно.
        if ($this.WindowState -eq 'Minimized') { return }
        Invoke-RamSafe -What 'раскладка окна' -Body { Update-RamShellLayout }
        if ($null -ne $script:UI.ResizeLiveTimer) {
            $script:UI.ResizeLiveTimer.Stop()
            $script:UI.ResizeLiveTimer.Start()
        }
        # Разворот на весь экран и обратно ResizeEnd не поднимает.
        if ($script:LastWindowState -ne $this.WindowState) {
            $script:LastWindowState = $this.WindowState
            Invoke-RamSafe -What 'перестройка после разворота' -Body { Update-RamAfterResize -Force }
            Invoke-RamSafe -What 'запоминание размера окна' -Body { Save-RamMainWindowGeometry -Form $this }
        }
    })
    $Form.Add_ResizeEnd({
        Invoke-RamSafe -What 'перестройка после изменения размера' -Body { Update-RamAfterResize }
        Invoke-RamSafe -What 'запоминание размера окна' -Body { Save-RamMainWindowGeometry -Form $this }
    })

    $Form.KeyPreview = $true
    $Form.Add_KeyDown({
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
            'D3' { Show-RamSection -Key 'profiles'; $e.Handled = $true }
            'D4' { Show-RamSection -Key 'stats';    $e.Handled = $true }
            'D5' { Show-RamSection -Key 'log';      $e.Handled = $true }
        }
    })

    $Form.Add_FormClosing({
        param($sender, $e)
        $internalClose = ($script:RebuildUi -or $script:RestartRequested)

        # Крестик уводит в часы, только если человек подтвердил, что значок видит.
        if (-not $internalClose -and $script:Settings.OnClose -eq 'tray' -and $script:UI.TrayOk -and
            $e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            if (Confirm-RamTrayVisible) {
                $e.Cancel = $true
                Invoke-RamSafe -What 'запоминание размера окна' -Body { Save-RamMainWindowGeometry -Form $sender }
                $sender.Hide()
                Show-RamTrayHint
                return
            }
        }
        if (-not $internalClose -and $script:Settings.ConfirmOnExit -and $script:Instances.Count -gt 0) {
            if (-not (Confirm-Ram "Запущено клиентов: $($script:Instances.Count).`n`nЗакрыть менеджер? Сами окна Roblox продолжат работать, но новые аккаунты запустить будет нельзя, пока менеджер закрыт.")) {
                $e.Cancel = $true
                return
            }
        }
        Invoke-RamSafe -What 'запоминание размера окна' -Body { Save-RamMainWindowGeometry -Form $sender }
        Dispose-RamFormRuntime
        if ($script:RebuildUi) { return }

        Invoke-RamSafe -What 'сохранение при закрытии' -Body { Save-RamState }
        Invoke-RamSafe -What 'снятие замков'          -Body { Disable-RamMultiInstance }
        Invoke-RamSafe -What 'снятие горячих клавиш'  -Body { Unregister-RamHotkeys }
        Invoke-RamSafe -What 'снятие замка копии'     -Body { Clear-RamSingleInstance }
        if ($null -ne $script:UI.Tray) {
            $script:UI.Tray.Visible = $false
            $script:UI.Tray.Dispose()
        }
    })

    $script:UI.TrayOk = $false
    if ($script:Settings.OnClose -eq 'tray') {
        $ni = New-Object System.Windows.Forms.NotifyIcon
        try {
            $icon = Get-RamAppIcon
            if ($null -eq $icon) { throw 'значок не нарисовался' }
            $ni.Icon    = $icon
            $ni.Text    = $script:AppName
            $ni.Visible = $true
            $script:UI.TrayOk = ($null -ne $ni.Icon -and $ni.Visible)
            if (-not $script:UI.TrayOk) { throw 'значок задан, но система его не приняла' }
        } catch {
            # Без значка крестик обязан просто закрывать — иначе окно спрячется в никуда.
            $script:UI.TrayOk = $false
            Write-RamLog "Значок в часах не создался ($($_.Exception.Message)) — крестик будет просто закрывать программу." 'warn'
        }
        $script:UI.Tray = $ni
        $ni.Add_Click({
            param($sender, $e)
            if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
            Show-RamMainWindow
        })
        $ni.Add_DoubleClick({ Show-RamMainWindow })
        $trayMenu = New-RamContextMenu
        $ni.ContextMenuStrip = $trayMenu
        $script:UI.TrayMenu = $trayMenu
        $ni.Add_MouseUp({
            param($sender, $e)
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) { Update-RamTrayMenu }
        })
    }

    $Form.Add_Shown({
        $this.ActiveControl = $null
        Show-RamSection -Key $script:Section
        # Развёрнутое окно получает настоящие границы только с появлением
        # хендла — раскладку и сетку считаем уже по ним.
        Invoke-RamSafe -What 'раскладка окна при показе' -Body { Update-RamShellLayout; Update-RamAfterResize -Force }

        # Подстраховка от окна, спрятанного способом запуска (SW_HIDE).
        try {
            $h = $this.Handle
            if ($h -ne [IntPtr]::Zero -and -not [Ram.Native]::IsWindowVisible($h)) {
                [void][Ram.Native]::ShowWindow($h, 1)
                [void][Ram.Native]::SetForegroundWindow($h)
                Write-RamLog 'Окно было скрыто способом запуска — показал его принудительно.' 'warn'
            }
        } catch { }
        if ($this.WindowState -eq 'Minimized') { $this.WindowState = 'Normal' }
    })
}

# ------------------------------------------------ действия карточки ---------

function Invoke-RamCardEdit {
    param([string]$Id)
    $old = Get-RamAccountById -Id $Id
    if ($null -eq $old) { return }
    $new = Show-RamAccountDialog -Account $old
    if ($null -ne $new) {
        foreach ($p in $new.PSObject.Properties.Name) { $old.$p = $new.$p }
        Save-RamState
        Build-RamCards
        Write-RamLog "Изменён аккаунт '$($old.Alias)'." 'ok'
    }
}

function Invoke-RamCardStop {
    param([string]$Id)
    $inst = $script:Instances[$Id]
    $acc  = Get-RamAccountById -Id $Id
    if ($null -eq $inst) {
        Set-RamStatus ("Окно «{0}» сейчас не запущено — закрывать нечего." -f $acc.Alias)
        return
    }
    # Закрытие руками — не вылет: счётчик вылетов не трогаем.
    $inst | Add-Member -NotePropertyName ClosedByUser -NotePropertyValue $true -Force
    if ($null -eq $script:Stopping) { $script:Stopping = @{} }
    $script:Stopping[$Id] = $true
    Update-RamCardStates
    try {
        if (Stop-RamRobloxInstance -ProcessId $inst.ProcessId) {
            $script:Instances.Remove($Id)
            Write-RamLog "'$($acc.Alias)' закрыт." 'ok'
        } else {
            Write-RamLog "Не удалось закрыть '$($acc.Alias)' — окно остаётся под контролем менеджера." 'warn'
            Show-RamMessage -Kind 'warn' -Message ("Окно «$($acc.Alias)» закрыть не вышло. Оно по-прежнему под присмотром AltHub — попробуй ещё раз или закрой его вручную.")
        }
    } finally {
        $script:Stopping.Remove($Id)
        Update-RamCardStates
    }
}

function Add-RamModernCardMouse {
    <#
      Клик по пустому месту плитки — отметка, перетаскивание — обмен местами
      с плиткой под курсором, правый клик — меню аккаунта.
    #>
    param([Parameter(Mandatory)]$Card, [object[]]$Controls, [string]$AccountId)

    $toggle = {
        if ($script:DragMoved) { return }
        $c = $this
        while ($null -ne $c -and $null -eq $c.Tag.AccountId) { $c = $c.Parent }
        if ($null -eq $c) { return }
        $entry = $script:Cards[$c.Tag.AccountId]
        if ($null -eq $entry) { return }
        $entry.Check.Tag.Checked = -not $entry.Check.Tag.Checked
        if ($entry.Check.Tag.Checked) { $script:CheckedIds[[string]$c.Tag.AccountId] = $true }
        else { [void]$script:CheckedIds.Remove([string]$c.Tag.AccountId) }
        $entry.Check.Invalidate()
        $entry.Card.Invalidate()
        Update-RamStatusLine
    }
    $dragDown = {
        param($s, $e)
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        $c = $s
        while ($null -ne $c -and $null -eq $c.Tag.AccountId) { $c = $c.Parent }
        if ($null -eq $c) { return }
        $script:DragId     = $c.Tag.AccountId
        $script:DragMoved  = $false
        $script:DragStart  = [System.Windows.Forms.Cursor]::Position
        $script:DragOverId = ''
    }
    $dragMove = {
        param($s, $e)
        if ([string]::IsNullOrEmpty($script:DragId)) { return }
        $pos = [System.Windows.Forms.Cursor]::Position
        if (-not $script:DragMoved -and
            (([Math]::Abs($pos.X - $script:DragStart.X) + [Math]::Abs($pos.Y - $script:DragStart.Y)) -gt [System.Windows.Forms.SystemInformation]::DragSize.Width)) {
            $script:DragMoved = $true
            $script:UI.Cards.Cursor = [System.Windows.Forms.Cursors]::SizeAll
            if ($script:Cards.ContainsKey($script:DragId)) {
                $dc = $script:Cards[$script:DragId].Card
                $dc.Tag.Selected = $true
                Sync-RamCardLabelFill -Card $dc
                $dc.Invalidate()
            }
        }
        if (-not $script:DragMoved) { return }
        $pt = $script:UI.Cards.PointToClient($pos)
        $overId = ''
        foreach ($ctl in $script:UI.Cards.Controls) {
            if ([string]::IsNullOrEmpty($ctl.Tag.AccountId)) { continue }
            if ($ctl.Bounds.Contains($pt)) { $overId = $ctl.Tag.AccountId; break }
        }
        if ($overId -eq $script:DragId) { $overId = '' }
        if ($overId -ne $script:DragOverId) {
            if ($script:DragOverId -and $script:Cards.ContainsKey($script:DragOverId)) {
                $prev = $script:Cards[$script:DragOverId].Card
                $prev.Tag.DropLine = $null
                Sync-RamCardLabelFill -Card $prev
                $prev.Invalidate()
            }
            $script:DragOverId = $overId
            if ($overId -and $script:Cards.ContainsKey($overId)) {
                $nc = $script:Cards[$overId].Card
                $nc.Tag.DropLine = 'swap'
                Sync-RamCardLabelFill -Card $nc
                $nc.Invalidate()
            }
        }
    }
    $dragUp = {
        param($s, $e)
        if ([string]::IsNullOrEmpty($script:DragId)) { return }
        $id = $script:DragId
        $script:DragId = ''
        $script:UI.Cards.Cursor = [System.Windows.Forms.Cursors]::Default
        # Цель запоминаем ДО того, как снимем подсветку.
        $targetId = $script:DragOverId
        if ($script:Cards.ContainsKey($id)) {
            $script:Cards[$id].Card.Tag.Selected = $false
            Sync-RamCardLabelFill -Card $script:Cards[$id].Card
            $script:Cards[$id].Card.Invalidate()
        }
        if ($targetId -and $script:Cards.ContainsKey($targetId)) {
            $oc = $script:Cards[$targetId].Card
            $oc.Tag.DropLine = $null
            Sync-RamCardLabelFill -Card $oc
            $oc.Invalidate()
        }
        $script:DragOverId = ''
        if (-not $script:DragMoved) { return }
        if ($targetId -and $targetId -ne $id) { Push-RamUndo -Label 'обмен карточек местами' }
        if ($targetId -and (Swap-RamAccountOrder -Id $id -WithId $targetId)) {
            Save-RamState
            Build-RamCards
        }
    }

    $menu = New-RamCardMenu -AccountId $AccountId
    foreach ($ctl in @($Card) + @($Controls | Where-Object { $null -ne $_ })) {
        $ctl.Add_MouseDown($dragDown)
        $ctl.Add_MouseMove($dragMove)
        $ctl.Add_MouseUp($dragUp)
        $ctl.Add_Click($toggle)
        $ctl.ContextMenuStrip = $menu
    }
}

# ------------------------------------------------------ плитки аккаунтов ----

function Get-RamModernAccountTileLayout {
    <#
      Геометрия плитки аккаунта. Одна на все плитки ряда — сетка ровная.

        [☐] (аватар)  Имя                 ● состояние
                      @ник · набор
        Игра
        настройки клиента · заметка · Robux
        [      Запустить      ] [Изменить] [Закрыть]
    #>
    param([int]$Width, [switch]$Compact)
    $t  = $Global:RamTheme
    $mm = Get-RamModernMetrics
    $k  = { param($n) [int][Math]::Round($n * $mm.Scale) }
    $pad = $mm.TilePad

    $avS   = if ($Compact) { & $k 36 } else { & $k 44 }
    $headH = [Math]::Max($avS, $mm.Title + $mm.Small)
    $avX   = $pad + $mm.Check + (& $k 10)
    $textX = $avX + $avS + (& $k 12)
    $textTop = $pad + [int](($headH - $mm.Title - $mm.Small) / 2)

    # Состояние компактное: подробность уже дублируется цветом рамки аватара.
    # Длинная подпись «загружается...» раньше съедала треть имени.
    $pillW = (Measure-RamText -Text 'очередь' -Font $t.FontSmall).Width + (& $k 18)
    $nameW = [Math]::Max((& $k 40), $Width - $textX - $pad - $pillW - $mm.Gap)
    $subW  = [Math]::Max((& $k 40), $Width - $textX - $pad)

    $y = $pad + $headH + (& $k 12)
    $gameY = $y; $y += $mm.Body
    $metaY = $y
    if (-not $Compact) { $y += $mm.Small }
    $y += (& $k 12)
    $btnH = $t.M.RowHSm
    $btnY = $y
    $y += $btnH + $pad

    # Три действия равной ширины. Огромная «Запустить» рядом с двумя
    # маленькими кнопками делала плитку визуально перекошенной.
    $actionsW = [Math]::Max(3, $Width - $pad * 2 - $mm.GapSm * 2)
    $playW = [int][Math]::Floor($actionsW / 3)
    $editW = $playW
    $stopW = $actionsW - $playW - $editW
    $playX = $pad
    $editX = $playX + $playW + $mm.GapSm
    $stopX = $editX + $editW + $mm.GapSm

    [pscustomobject]@{
        Width = $Width; Height = $y; Pad = $pad
        CheckX = $pad; CheckY = $pad + [int](($headH - $mm.Check) / 2)
        AvatarX = $avX; AvatarY = $pad + [int](($headH - $avS) / 2); AvatarSize = $avS
        TextX = $textX; NameY = $textTop; NameW = $nameW; SubY = $textTop + $mm.Title; SubW = $subW
        PillRight = $Width - $pad; PillY = $textTop + [int](($mm.Title - (Get-RamStatusDotHeight)) / 2)
        GameY = $gameY; MetaY = $metaY; Compact = [bool]$Compact
        LineW = $Width - $pad * 2
        BtnY = $btnY; BtnH = $btnH; PlayX = $playX; PlayW = $playW; EditX = $editX; EditW = $editW; StopX = $stopX; StopW = $stopW
    }
}

function New-RamModernAccountTile {
    param([Parameter(Mandatory)]$Account, [Parameter(Mandatory)]$Layout)
    $t  = $Global:RamTheme
    $mm = Get-RamModernMetrics
    $a  = $Account
    $L  = $Layout

    $card = New-RamCard -Width $L.Width -Height $L.Height -Radius ([int][Math]::Round(12 * $mm.Scale))
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, $mm.Gap, $mm.Gap)
    $card.Tag.AccountId = $a.Id
    $stripeColor = Get-RamLabelColor -Key ([string]$a.Color)
    if ($null -eq $stripeColor) {
        $stripeColor = Mix-RamColor -Base $t.Card -Overlay ([System.Drawing.Color]::FromArgb(107, $t.Accent))
    }
    $card.Tag | Add-Member -NotePropertyName Stripe -NotePropertyValue $stripeColor -Force

    # Поверх заливки New-RamCard: цветная метка по верхнему краю и рамка отметки.
    Add-RamTopStripe -Card $card
    $card.Add_Paint({
        param($s, $e)
        $th = $Global:RamTheme
        $sc = $th.M.Scale
        $g  = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $pad = [int][Math]::Round(14 * $sc)

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

    $lblName = New-RamLabel -Text $a.Alias -X $L.TextX -Y $L.NameY -Width $L.NameW -Height $mm.Title -Font $t.FontTitle -Truncatable
    $card.Controls.Add($lblName)

    # Ник и набор — одной строкой. «Вход мёртв» здесь не пишем: это скажет
    # метка состояния справа от имени.
    $subParts = @()
    if ($a.Username) { $subParts += "@$($a.Username)" } else { $subParts += 'вход не проверен' }
    if (-not [string]::IsNullOrWhiteSpace($a.Group)) { $subParts += [string]$a.Group }
    $lblSub = New-RamLabel -Text ($subParts -join '  ·  ') -X $L.TextX -Y $L.SubY -Width $L.SubW -Height $mm.Small `
                           -Font $t.FontSmall -Color $t.Muted -Truncatable
    $card.Controls.Add($lblSub)

    # Состояние — метка у правого края напротив имени. Ширину подгоняет
    # Update-RamCardStatesModern под подпись, правый край неподвижен.
    $dot = New-RamStatusDot -X ($L.PillRight - 10) -Y $L.PillY -Width 10
    $dot.Tag | Add-Member -NotePropertyName RightEdge -NotePropertyValue $L.PillRight -Force
    $card.Controls.Add($dot)

    $gameTxt = if ($a.GameName) { [string]$a.GameName } elseif ($a.PlaceId) { "ID $($a.PlaceId)" } else { 'просто Roblox, без игры' }
    if ($a.LinkCode) { $gameTxt += '  ·  приватный сервер' }
    $lblGame = New-RamLabel -Text $gameTxt -X $L.Pad -Y $L.GameY -Width $L.LineW -Height $mm.Body `
                            -Color $(if ($a.PlaceId) { $t.Text } else { $t.Muted }) -Truncatable
    $card.Controls.Add($lblGame)

    $lblMeta = $null
    if (-not $L.Compact) {
        $metaParts = @()
        $summary = Get-RamAccountSettingsSummary -Account $a
        if ($summary) { $metaParts += $summary }
        if (-not [string]::IsNullOrWhiteSpace($a.Note)) { $metaParts += [string]$a.Note }
        if ([int]$a.Robux -ge 0)          { $metaParts += "$($a.Robux) R$" }
        if ([string]$a.Premium -eq 'yes') { $metaParts += 'Premium' }
        if ($metaParts.Count -eq 0) { $metaParts += 'настройки Roblox не меняются' }
        $lblMeta = New-RamLabel -Text ($metaParts -join '  ·  ') -X $L.Pad -Y $L.MetaY -Width $L.LineW -Height $mm.Small `
                                -Font $t.FontSmall -Color $t.Muted -Truncatable
        $card.Controls.Add($lblMeta)
    }

    # У мёртвого входа «Запустить» бесполезен: клиент выкинет на страницу входа.
    if ([string]$a.CookieOk -eq 'no') {
        $bPlay = New-RamButton -Text 'Войти' -Width $L.PlayW -Height $L.BtnH -Fixed -Kind 'danger' `
                               -Tooltip 'Вход умер — войти в этот аккаунт ещё раз' -OnClick { Invoke-RamRelogin -Id $this.Tag.AccountId }
    } else {
        $bPlay = New-RamButton -Text 'Запустить' -Width $L.PlayW -Height $L.BtnH -Fixed -Kind 'primary' `
                               -Tooltip 'Запустить этот аккаунт свёрнутым' -OnClick { Add-RamToLaunchQueue -Accounts @((Get-RamAccountById -Id $this.Tag.AccountId)) }
    }
    $bPlay.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
    $bPlay.Location = New-Object System.Drawing.Point($L.PlayX, $L.BtnY)
    $card.Controls.Add($bPlay)

    $bEdit = New-RamButton -Text 'Изменить' -Width $L.EditW -Height $L.BtnH -Fixed -Tooltip 'Настройки аккаунта' `
                           -OnClick { Invoke-RamCardEdit -Id $this.Tag.AccountId }
    $bEdit.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
    $bEdit.Location = New-Object System.Drawing.Point($L.EditX, $L.BtnY)
    $card.Controls.Add($bEdit)

    $bStop = New-RamButton -Text 'Закрыть' -Width $L.StopW -Height $L.BtnH -Fixed -Tooltip 'Закрыть окно этого аккаунта' `
                           -OnClick { Invoke-RamCardStop -Id ([string]$this.Tag.AccountId) }
    $bStop.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
    $bStop.Location = New-Object System.Drawing.Point($L.StopX, $L.BtnY)
    $card.Controls.Add($bStop)

    Add-RamModernCardMouse -Card $card -AccountId $a.Id -Controls @($lblName, $lblSub, $lblGame, $lblMeta, $av, $dot)

    $script:Cards[$a.Id] = @{
        Card = $card; Check = $chk; Avatar = $av
        Name = $lblName; Sub = $lblSub; Game = $lblGame; Dot = $dot
        Play = $bPlay; Edit = $bEdit; Stop = $bStop
        AvatarLoaded = ($null -ne $cached)
    }
    if ([int64]$a.UserId -gt 0 -and $null -eq $cached) { [void]$script:AvatarQueue.Add($a.Id) }
    return $card
}

function Build-RamCardsModern {
    <# Полная пересборка плиток аккаунтов. #>
    if (-not $script:UI.ContainsKey('Cards') -or $null -eq $script:UI.Cards) { return }
    $panel = $script:UI.Cards
    $compact = [bool]$script:Settings.CompactCards

    # Отметки живут в общей модели: поиск и смена меню их не теряют.
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

        $visible = @(Get-RamVisibleAccounts)
        if (@($script:Accounts).Count -eq 0) {
            [void](Add-RamModernNotice -Panel $panel -Title 'Пока ни одного аккаунта' `
                   -Text 'Войди в приложении Roblox под нужным аккаунтом и нажми «Добавить аккаунт» — менеджер заберёт вход сам, пароль вводить не надо.')
        } elseif ($visible.Count -eq 0) {
            $why = if ($script:GroupFilter) { "В наборе «$($script:GroupFilter)» ничего не нашлось" }
                   else { "По запросу «$($script:Filter)» ничего не нашлось" }
            [void](Add-RamModernNotice -Panel $panel -Title $why -Text 'Сбрось поиск (Esc) или выбери набор «Все».')
        } else {
            $W = Get-RamCardWidth
            $L = Get-RamModernAccountTileLayout -Width $W -Compact:$compact
            foreach ($a in $visible) { $panel.Controls.Add((New-RamModernAccountTile -Account $a -Layout $L)) }
        }
    } finally {
        Exit-RamListRebuild -Panel $panel -ScrollY $listScroll
    }

    Update-RamCardStates
    Update-RamHeaderCounts
    Update-RamGroupBar
    Update-RamStatusLine
}

function Update-RamCardStatesModern {
    <# Только метки состояния — по таймеру, плитки не пересоздаёт. #>
    $t = $Global:RamTheme
    foreach ($a in $script:Accounts) {
        $entry = $script:Cards[$a.Id]
        if ($null -eq $entry) { continue }
        $inst = $script:Instances[$a.Id]
        $osClosing = ($null -ne $inst -and $inst.PSObject.Properties.Name -contains 'ClosingByOs' -and [bool]$inst.ClosingByOs)
        $caption = ''; $color = $t.Muted
        if (($null -ne $script:Stopping -and $script:Stopping.ContainsKey($a.Id)) -or $osClosing) {
            $caption = 'выход'; $color = $t.Danger
        } elseif ($null -ne $inst) {
            if ($inst.Handle -ne [IntPtr]::Zero) { $caption = 'игра'; $color = $t.Ok }
            else { $caption = 'загрузка'; $color = $t.Warn }
        } elseif ($script:LaunchQueue -contains $a.Id) {
            $caption = 'очередь'; $color = $t.Accent
        } elseif ([string]$a.CookieOk -eq 'no') {
            $caption = 'вход'; $color = $t.Danger
        }
        $dot = $entry.Dot
        if ($null -ne $dot -and $null -ne $dot.Tag -and ($dot.Tag.PSObject.Properties.Name -contains 'RightEdge')) {
            # Метка по ширине подписи, прижата к правому краю.
            $w = (Measure-RamText -Text $caption -Font $t.FontSmall).Width + [int][Math]::Round(16 * $t.M.Scale)
            if ($dot.Width -ne $w) { $dot.SetBounds(([int]$dot.Tag.RightEdge - $w), $dot.Top, $w, $dot.Height) }
        }
        Set-RamStatusDot -Dot $dot -Caption $caption -Color $color -Avatar $entry.Avatar
    }
    Update-RamHeaderCounts
    Update-RamStatusLine
}

# ------------------------------------------------------------ игры ----------

function Add-RamTopStripe {
    <#
      Цветная полоса по верхнему краю плитки — ровно по её скруглению, а не
      линией внутри с отступами: так метка читается частью плитки.
    #>
    param([Parameter(Mandatory)]$Card)
    $Card.Add_Paint({
        param($s, $e)
        if ($null -eq $s.Tag.Stripe) { return }
        $sc = $Global:RamTheme.M.Scale
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        $path = New-RamRoundRect -Rect $rect -Radius $s.Tag.Radius
        $state = $g.Save()
        try {
            $g.SetClip($path)
            $b = New-Object System.Drawing.SolidBrush($s.Tag.Stripe)
            $g.FillRectangle($b, 0, 0, $s.Width, [Math]::Max(3, [int][Math]::Round(4 * $sc)))
            $b.Dispose()
        } finally {
            $g.Restore($state)
            $path.Dispose()
        }
    })
}

function New-RamModernActionTile {
    <#
      Плитка «заголовок, подпись, главная кнопка на всю ширину и вторая
      справа» — общая для игр и профилей.
    #>
    param([int]$Width, [string]$Title, [string]$Meta, [string]$PrimaryText, [scriptblock]$OnPrimary,
          [string]$SecondaryText, [scriptblock]$OnSecondary, $TagName, $TagValue, [string]$PrimaryTooltip)
    $t  = $Global:RamTheme
    $mm = Get-RamModernMetrics
    $pad = $mm.TilePad
    $lineW = [Math]::Max(1, $Width - $pad * 2)
    $btnH = $t.M.RowHSm
    $btnY = $pad + $mm.Title + $mm.Small + [int][Math]::Round(12 * $mm.Scale)
    $H = $btnY + $btnH + $pad

    $card = New-RamCard -Width $Width -Height $H -Radius ([int][Math]::Round(12 * $mm.Scale))
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, $mm.Gap, $mm.Gap)
    $card.Controls.Add((New-RamLabel -Text $Title -X $pad -Y $pad -Width $lineW -Height $mm.Title -Font $t.FontTitle -Truncatable))
    $card.Controls.Add((New-RamLabel -Text $Meta -X $pad -Y ($pad + $mm.Title) -Width $lineW -Height $mm.Small -Font $t.FontSmall -Color $t.Muted -Truncatable))

    # Для плиток игр/профилей сохраняем устойчивую пропорцию 2:1. Раньше
    # вторичная кнопка мерилась только по короткому слову «Убрать», а главная
    # занимала весь остаток и выглядела непропорционально огромной.
    $actionsW = [Math]::Max(2, $lineW - $mm.GapSm)
    $secW = [int][Math]::Floor($actionsW / 3)
    $primW = $actionsW - $secW
    $bSec = New-RamButton -Text $SecondaryText -Width $secW -Height $btnH -Fixed -OnClick $OnSecondary
    $bSec.Tag | Add-Member -NotePropertyName $TagName -NotePropertyValue $TagValue -Force
    $bSec.Location = New-Object System.Drawing.Point(($Width - $pad - $secW), $btnY)
    $card.Controls.Add($bSec)

    $bPrim = New-RamButton -Text $PrimaryText -Width $primW -Height $btnH -Fixed -Kind 'primary' -OnClick $OnPrimary -Tooltip $PrimaryTooltip
    $bPrim.Tag | Add-Member -NotePropertyName $TagName -NotePropertyValue $TagValue -Force
    $bPrim.Location = New-Object System.Drawing.Point($pad, $btnY)
    $card.Controls.Add($bPrim)
    return $card
}

function Update-RamGamesPanelModern {
    if (-not $script:UI.ContainsKey('GamesHost')) { return }
    $h = $script:UI.GamesHost
    if ($null -eq $h -or $h.IsDisposed) { return }

    $listScroll = Enter-RamListRebuild -Panel $h
    try {
        Clear-RamPanelControls -Panel $h
        $games = @($script:Settings.Games | Where-Object { $null -ne $_ })
        if ($games.Count -eq 0) {
            [void](Add-RamModernNotice -Panel $h -Title 'Список игр пуст' `
                   -Text 'Нажми «＋ Своя игра» и вставь ссылку — или возьми готовую из популярных. Игры попадают сюда и сами, когда назначаешь их аккаунтам.')
            return
        }
        $grid = Get-RamModernGrid -Panel $h -MinWidth 300
        foreach ($g in $games) {
            $hasTitle = (-not [string]::IsNullOrWhiteSpace([string]$g.Title)) -and ([string]$g.Title -notmatch '^ID \d+$')
            $title = if ($hasTitle) { [string]$g.Title } else { "ID $($g.PlaceId)" }
            # Номер уже в заголовке, если названия нет, — второй раз его не пишем.
            $metaParts = @()
            if ($hasTitle) { $metaParts += "ID $($g.PlaceId)" } else { $metaParts += 'название ещё не подтянулось' }
            if ($g.LinkCode) { $metaParts += 'приватный сервер' }
            $meta = $metaParts -join '  ·  '
            $tile = New-RamModernActionTile -Width $grid.Width -Title $title -Meta $meta -TagName 'Game' -TagValue $g `
                -PrimaryText 'Назначить отмеченным' -PrimaryTooltip 'Поставить эту игру всем отмеченным аккаунтам' -OnPrimary {
                    $targets = @(Get-RamTargetAccounts)
                    if ($targets.Count -eq 0) { Show-RamInfo 'Сначала отметь аккаунты во вкладке «Аккаунты».'; return }
                    $g2 = $this.Tag.Game
                    foreach ($a in $targets) {
                        $a.PlaceId  = [string]$g2.PlaceId
                        $a.GameName = ([string]$g2.Title) -replace ' \(приватный сервер\)$', ''
                        $a.LinkCode = [string]$g2.LinkCode
                    }
                    Save-RamState
                    Build-RamCards
                    Set-RamStatus "Игра назначена аккаунтам: $($targets.Count)."
                    Write-RamLog "«$($g2.Title)» назначена аккаунтам: $($targets.Count)." 'ok'
                } `
                -SecondaryText 'Убрать' -OnSecondary {
                    $g2 = $this.Tag.Game
                    $script:Settings.Games = @(@($script:Settings.Games) | Where-Object {
                        -not ($_.PlaceId -eq $g2.PlaceId -and [string]$_.LinkCode -eq [string]$g2.LinkCode)
                    })
                    Save-RamSettings -Settings $script:Settings
                    Update-RamGamesPanel
                    Write-RamLog "«$($g2.Title)» убрана из списка игр." 'ok'
                }
            $h.Controls.Add($tile)
        }
    } finally {
        Exit-RamListRebuild -Panel $h -ScrollY $listScroll
    }
}

# ------------------------------------------------------------ профили -------

function Update-RamProfilesPanelModern {
    if (-not $script:UI.ContainsKey('ProfilesHost')) { return }
    $h = $script:UI.ProfilesHost
    if ($null -eq $h -or $h.IsDisposed) { return }

    $listScroll = Enter-RamListRebuild -Panel $h
    try {
        Clear-RamPanelControls -Panel $h
        $profiles = @(Get-RamProfiles)
        if ($profiles.Count -eq 0) {
            [void](Add-RamModernNotice -Panel $h -Title 'Профилей пока нет' `
                   -Text 'Отметь нужные аккаунты, задай им игру и нажми «Сохранить текущее как профиль». Дальше весь набор запускается одной кнопкой.')
            return
        }
        $grid = Get-RamModernGrid -Panel $h -MinWidth 300
        foreach ($pr in $profiles) {
            $prIds = @()
            if ($pr.PSObject.Properties.Name -contains 'Ids') { $prIds = @($pr.Ids | Where-Object { $_ }) }
            $meta = if ($pr.Group) { "набор «$($pr.Group)»" } elseif ($prIds.Count) { "аккаунтов: $($prIds.Count)" } else { 'все аккаунты' }
            if ($pr.GameName) { $meta += "  ·  $($pr.GameName)" } elseif ($pr.PlaceId) { $meta += "  ·  ID $($pr.PlaceId)" }
            if ($pr.LinkCode) { $meta += '  ·  приватный сервер' }
            $tile = New-RamModernActionTile -Width $grid.Width -Title ([string]$pr.Name) -Meta $meta -TagName 'Profile' -TagValue $pr `
                -PrimaryText 'Запустить профиль' -PrimaryTooltip 'Поставить игру набору и запустить' -OnPrimary {
                    Invoke-RamRunProfile -Profile $this.Tag.Profile
                } `
                -SecondaryText 'Убрать' -OnSecondary {
                    $nm = $this.Tag.Profile.Name
                    $script:Settings.Profiles = @(Get-RamProfiles | Where-Object { $_.Name -ne $nm })
                    Save-RamSettings -Settings $script:Settings
                    Update-RamProfilesPanel
                    Write-RamLog "Профиль «$nm» убран." 'ok'
                }
            $h.Controls.Add($tile)
        }
    } finally {
        Exit-RamListRebuild -Panel $h -ScrollY $listScroll
    }
}

# ------------------------------------------------------------ статистика ----

function Update-RamStatsPanelModern {
    if (-not $script:UI.ContainsKey('StatsHost')) { return }
    $h = $script:UI.StatsHost
    if ($null -eq $h -or $h.IsDisposed) { return }
    $t  = $Global:RamTheme
    $mm = Get-RamModernMetrics
    $pad = $mm.TilePad
    $radius = [int][Math]::Round(12 * $mm.Scale)

    $listScroll = Enter-RamListRebuild -Panel $h
    try {
        Clear-RamPanelControls -Panel $h

        $totalLaunch = 0; $totalCrash = 0; $totalSec = 0
        foreach ($a in $script:Accounts) {
            $totalLaunch += [int]$a.LaunchCount
            $totalCrash  += [int]$a.CrashCount
            $totalSec    += [int]$a.PlaySeconds
        }

        # --- четыре крупных числа сверху
        $kpis = @(
            @{ Cap = 'АККАУНТОВ'; Val = [string]@($script:Accounts).Count; Color = $t.Text },
            @{ Cap = 'ЗАПУСКОВ';  Val = [string]$totalLaunch; Color = $t.Text },
            @{ Cap = 'ВЫЛЕТОВ';   Val = [string]$totalCrash; Color = $(if ($totalCrash -gt 0) { $t.Warn } else { $t.Text }) },
            @{ Cap = 'НАИГРАНО';  Val = (Format-RamDuration $totalSec); Color = $t.Text }
        )
        $kGrid = Get-RamModernGrid -Panel $h -MinWidth 180 -MaxColumns 4
        $kH = $pad + $mm.Small + $mm.Big + $pad
        $last = $null
        foreach ($kp in $kpis) {
            $tile = New-RamCard -Width $kGrid.Width -Height $kH -Radius $radius
            $tile.Margin = New-Object System.Windows.Forms.Padding(0, 0, $mm.Gap, $mm.Gap)
            $lw = [Math]::Max(1, $kGrid.Width - $pad * 2)
            $tile.Controls.Add((New-RamLabel -Text $kp.Cap -X $pad -Y $pad -Width $lw -Height $mm.Small -Font $t.FontSmall -Color $t.Muted -Truncatable))
            $tile.Controls.Add((New-RamLabel -Text $kp.Val -X $pad -Y ($pad + $mm.Small) -Width $lw -Height $mm.Big -Font $t.FontBig -Color $kp.Color -Truncatable))
            $h.Controls.Add($tile)
            $last = $tile
        }
        if ($null -ne $last) { $h.SetFlowBreak($last, $true) }

        # --- по аккаунтам: имя с ником в строку, четыре числа в ряд или 2×2
        $grid = Get-RamModernGrid -Panel $h -MinWidth 320
        $W = $grid.Width
        $innerW = $W - $pad * 2
        $capLongest = (Measure-RamText -Text 'БЫЛ В ИГРЕ' -Font $t.FontSmall).Width + $mm.Gap
        $perRow = if ([int](($innerW - $mm.Gap * 3) / 4) -ge $capLongest) { 4 } else { 2 }
        $cellW = [int](($innerW - $mm.Gap * ($perRow - 1)) / $perRow)
        $cellH = $mm.Small + $mm.Body
        $rows = [int][Math]::Ceiling(4 / $perRow)
        $rowGap = $mm.Gap
        $cellsY = $pad + $mm.Title + [int][Math]::Round(10 * $mm.Scale)
        $tileH = $cellsY + $cellH * $rows + $rowGap * ($rows - 1) + $pad

        foreach ($a in (Get-RamOrderedAccounts)) {
            $tile = New-RamCard -Width $W -Height $tileH -Radius $radius
            $tile.Margin = New-Object System.Windows.Forms.Padding(0, 0, $mm.Gap, $mm.Gap)
            $stripe = Get-RamLabelColor -Key ([string]$a.Color)
            if ($null -eq $stripe) { $stripe = Mix-RamColor -Base $t.Card -Overlay ([System.Drawing.Color]::FromArgb(107, $t.Accent)) }
            $tile.Tag | Add-Member -NotePropertyName Stripe -NotePropertyValue $stripe -Force
            Add-RamTopStripe -Card $tile

            $nameNeed = (Measure-RamText -Text ([string]$a.Alias) -Font $t.FontTitle).Width + $mm.Gap
            $sub = if ($a.Username) { "@$($a.Username)" } else { 'вход не проверен' }
            $subNeed = (Measure-RamText -Text $sub -Font $t.FontSmall).Width + $mm.Gap
            $nameW = [Math]::Min($nameNeed, [Math]::Max([int]($innerW * 0.6), $innerW - $subNeed - $mm.Gap))
            $tile.Controls.Add((New-RamLabel -Text $a.Alias -X $pad -Y $pad -Width $nameW -Height $mm.Title -Font $t.FontTitle -Truncatable))
            $subX = $pad + $nameW + $mm.GapSm
            $subY = $pad + [int](($mm.Title - $mm.Small) / 2) + 1
            $tile.Controls.Add((New-RamLabel -Text $sub -X $subX -Y $subY -Width ([Math]::Max(1, $pad + $innerW - $subX)) -Height $mm.Small -Font $t.FontSmall -Color $t.Muted -Truncatable))

            $lastRun = if ($a.LastUsed) {
                try { ([datetime]$a.LastUsed).ToString('dd.MM HH:mm') } catch { [string]$a.LastUsed }
            } else { 'ни разу' }
            $cells = @(
                @{ Cap = 'ЗАПУСКОВ';         Val = [string][int]$a.LaunchCount; Color = $t.Text },
                @{ Cap = 'ВЫЛЕТОВ';          Val = [string][int]$a.CrashCount; Color = $(if ([int]$a.CrashCount -gt 0) { $t.Warn } else { $t.Text }) },
                @{ Cap = 'НАИГРАНО';         Val = (Format-RamDuration ([int]$a.PlaySeconds)); Color = $t.Text },
                @{ Cap = 'БЫЛ В ИГРЕ';       Val = $lastRun; Color = $t.Text }
            )
            for ($i = 0; $i -lt 4; $i++) {
                $cx = $pad + ($i % $perRow) * ($cellW + $mm.Gap)
                $cy = $cellsY + [int][Math]::Floor($i / $perRow) * ($cellH + $rowGap)
                $tile.Controls.Add((New-RamLabel -Text $cells[$i].Cap -X $cx -Y $cy -Width $cellW -Height $mm.Small -Font $t.FontSmall -Color $t.Muted -Truncatable))
                $tile.Controls.Add((New-RamLabel -Text $cells[$i].Val -X $cx -Y ($cy + $mm.Small) -Width $cellW -Height $mm.Body -Color $cells[$i].Color -Truncatable))
            }
            $h.Controls.Add($tile)
        }
    } finally {
        Exit-RamListRebuild -Panel $h -ScrollY $listScroll
    }
}
