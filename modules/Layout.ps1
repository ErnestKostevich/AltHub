#requires -Version 5.1
<#
================================================================================
 Layout.ps1 — раскладка окон
================================================================================
 ЗАЧЕМ ЭТОТ ФАЙЛ.

 Раньше весь интерфейс расставлялся вручную: сто двадцать мест вида
 New-Object System.Drawing.Point(400, 158). Пока экран обычный, оно кое-как
 держалось. Но подписи и кнопки меряются ШРИФТОМ, а шрифт растёт вместе с
 масштабом экрана — при 125% и 150% текст становился шире, а координаты
 оставались прежними, и элементы наезжали друг на друга.

 Здесь раскладка считается ПО ФАКТУ: сколько места занял текст этим шрифтом,
 столько и отводится. Поэтому одинаково правильно и на 100%, и на 150%.

 ВАЖНО: раскладчик работает НЕМЕДЛЕННО. Он не откладывает вычисления до показа
 окна, а сразу присваивает элементам их координаты. Благодаря этому
 Самопроверка может собрать окно, не показывая его, и увидеть ровно то, что
 увидит человек.

 Правило на весь проект: координаты назначаются ТОЛЬКО отсюда.
================================================================================
#>

function Set-RamBounds {
    <#
      Единственное место, где элементу назначаются координаты и размер.
      Ширина или высота 0 означает «не менять».
    #>
    param(
        [Parameter(Mandatory)]$Control,
        [int]$X, [int]$Y, [int]$Width = 0, [int]$Height = 0,
        [string]$Anchor = ''
    )

    if ($Width  -le 0) { $Width  = $Control.Width }
    if ($Height -le 0) { $Height = $Control.Height }

    $Control.SetBounds($X, $Y, $Width, $Height)

    if ($Anchor) {
        $Control.Anchor = [System.Windows.Forms.AnchorStyles]$Anchor
    }

    # Составные элементы (поле ввода, карточка) сами перекладывают внутренности.
    if ($null -ne $Control.Tag -and
        $Control.Tag.PSObject.Properties.Name -contains 'OnResize' -and
        $null -ne $Control.Tag.OnResize) {
        & $Control.Tag.OnResize $Control
    }
    return $Control
}

function Measure-RamControl {
    <#
      Естественный размер элемента: сколько ему нужно, чтобы ничего не резалось.

      Самодельные контролы объявляют это сами в Tag.Natural (см. Theme.ps1).
      Для остальных меряем текст их шрифтом.
    #>
    param([Parameter(Mandatory)]$Control)

    if ($null -ne $Control.Tag -and
        $Control.Tag.PSObject.Properties.Name -contains 'Natural' -and
        $null -ne $Control.Tag.Natural) {
        return $Control.Tag.Natural
    }

    if ($Control -is [System.Windows.Forms.Label]) {
        $sz = Measure-RamText -Text $Control.Text -Font $Control.Font
        return (New-Object System.Drawing.Size(($sz.Width + 2), [Math]::Max($sz.Height, $Control.Height)))
    }

    return (New-Object System.Drawing.Size($Control.Width, $Control.Height))
}

function New-RamLayout {
    <#
      Курсор раскладки внутри контейнера.

      Ширина содержимого считается от контейнера за вычетом полей, и всё, что
      кладётся дальше, физически не может из неё выйти.
    #>
    param(
        [Parameter(Mandatory)]$Container,
        [int]$PadX = -1, [int]$PadY = -1, [int]$Gap = -1,
        [int]$Width = 0
    )

    $m = $Global:RamTheme.M
    if ($PadX -lt 0) { $PadX = $m.PadX }
    if ($PadY -lt 0) { $PadY = $m.PadY }
    if ($Gap  -lt 0) { $Gap  = $m.Gap  }

    if ($Width -le 0) {
        $cw = $Container.ClientSize.Width
        if ($cw -le 0) { $cw = $Container.Width }
        $Width = $cw - ($PadX * 2)
    }

    [pscustomobject]@{
        Container = $Container
        X         = $PadX
        Y         = $PadY
        Width     = [Math]::Max(1, $Width)
        Gap       = $Gap
        PadX      = $PadX
        PadY      = $PadY
        Bottom    = $PadY
        MaxRight  = $PadX
    }
}

function Add-RamGap {
    <# Явный отступ вместо магических чисел в координатах. #>
    param([Parameter(Mandatory)]$Layout, [int]$Height = -1)
    if ($Height -lt 0) { $Height = $Global:RamTheme.M.Gap }
    $Layout.Y += $Height
    $Layout.Bottom = $Layout.Y
    return $Layout
}

function Add-RamRow {
    <#
      Ряд элементов по горизонтали.

        -Items   массив контролов, либо @{ Control; Width; Fill }
        -Align   left | right | center | spread
        -Fill    элемент, забирающий весь остаток ширины

      Ширина элемента: явно заданная -> Fill -> измеренная.
      Возвращает высоту ряда; курсор съезжает вниз.
    #>
    param(
        [Parameter(Mandatory)]$Layout,
        [Parameter(Mandatory)][object[]]$Items,
        [ValidateSet('left','right','center','spread')][string]$Align = 'left',
        [ValidateSet('top','middle','bottom')][string]$VAlign = 'middle',
        [int]$Gap = -1,
        [int]$Height = 0,
        $Fill = $null
    )

    if ($Gap -lt 0) { $Gap = $Layout.Gap }

    # --- нормализуем список и меряем
    $cells = @()
    foreach ($it in $Items) {
        if ($null -eq $it) { continue }
        $ctl = $it; $w = 0
        if ($it -is [hashtable]) {
            $ctl = $it['Control']
            if ($it.ContainsKey('Width')) { $w = [int]$it['Width'] }
        }
        if ($null -eq $ctl) { continue }
        if ($w -le 0) { $w = (Measure-RamControl -Control $ctl).Width }
        $cells += [pscustomobject]@{ Control = $ctl; Width = [Math]::Max(1, $w) }
    }
    if ($cells.Count -eq 0) { return 0 }

    # --- высота ряда
    $rowH = $Height
    if ($rowH -le 0) {
        foreach ($c in $cells) { if ($c.Control.Height -gt $rowH) { $rowH = $c.Control.Height } }
    }

    # --- растягиваемый элемент забирает остаток
    $fixed = 0
    foreach ($c in $cells) { $fixed += $c.Width }
    $totalGap = $Gap * [Math]::Max(0, $cells.Count - 1)

    if ($null -ne $Fill) {
        $rest = $Layout.Width - $totalGap
        foreach ($c in $cells) { if ($c.Control -ne $Fill) { $rest -= $c.Width } }
        foreach ($c in $cells) { if ($c.Control -eq $Fill) { $c.Width = [Math]::Max(1, $rest) } }
        $fixed = 0
        foreach ($c in $cells) { $fixed += $c.Width }
    }

    $used = $fixed + $totalGap

    # --- стартовая позиция и шаг
    $x = $Layout.X
    $step = $Gap
    switch ($Align) {
        'right'  { $x = $Layout.X + $Layout.Width - $used }
        'center' { $x = $Layout.X + [int](($Layout.Width - $used) / 2) }
        'spread' {
            if ($cells.Count -gt 1) {
                $step = [int](($Layout.Width - $fixed) / ($cells.Count - 1))
                if ($step -lt $Gap) { $step = $Gap }
            }
        }
    }
    if ($x -lt $Layout.X) { $x = $Layout.X }

    # --- раскладываем
    foreach ($c in $cells) {
        $y = $Layout.Y
        switch ($VAlign) {
            'middle' { $y = $Layout.Y + [int](($rowH - $c.Control.Height) / 2) }
            'bottom' { $y = $Layout.Y + $rowH - $c.Control.Height }
        }
        if ($y -lt $Layout.Y) { $y = $Layout.Y }

        [void](Set-RamBounds -Control $c.Control -X $x -Y $y -Width $c.Width)
        if ($null -eq $c.Control.Parent) { $Layout.Container.Controls.Add($c.Control) }

        $right = $x + $c.Width
        if ($right -gt $Layout.MaxRight) { $Layout.MaxRight = $right }
        $x += $c.Width + $step
    }

    $Layout.Y += $rowH + $Layout.Gap
    $Layout.Bottom = $Layout.Y
    return $rowH
}

function Add-RamStack {
    <# Столбик: каждый элемент на своей строке во всю ширину колонки. #>
    param(
        [Parameter(Mandatory)]$Layout,
        [Parameter(Mandatory)][object[]]$Items,
        [int]$Gap = -1,
        [ValidateSet('fill','left','right','center')][string]$Align = 'fill'
    )

    $total = 0
    foreach ($it in $Items) {
        if ($null -eq $it) { continue }
        if ($Align -eq 'fill') {
            $total += (Add-RamRow -Layout $Layout -Items @(@{ Control = $it; Width = $Layout.Width }) -Gap $Gap)
        } else {
            $total += (Add-RamRow -Layout $Layout -Items @($it) -Align $Align -Gap $Gap)
        }
    }
    return $total
}

function Add-RamField {
    <#
      Пара «подпись + элемент» — это добрая половина всех окон.

        -Placement above  подпись сверху
        -Placement side   подпись слева, фиксированной ширины

      Подпись создаётся здесь и получает ширину колонки, поэтому обрезаться
      по определению не может. Длинное пояснение уходит в подсказку при
      наведении, а не второй строкой — иначе оно съедает место.
    #>
    param(
        [Parameter(Mandatory)]$Layout,
        [Parameter(Mandatory)][string]$Caption,
        [Parameter(Mandatory)]$Control,
        [ValidateSet('above','side')][string]$Placement = 'above',
        [int]$CaptionWidth = 0,
        $Font, $Color,
        [string]$Hint = ''
    )

    $t = $Global:RamTheme
    if ($null -eq $Font)  { $Font  = $t.FontSmall }
    if ($null -eq $Color) { $Color = $t.Muted }

    $capH = (Measure-RamText -Text $Caption -Font $Font).Height + 2
    $lbl = New-RamLabel -Text $Caption -X 0 -Y 0 -Width 10 -Height $capH -Font $Font -Color $Color

    if ($Placement -eq 'side') {
        if ($CaptionWidth -le 0) {
            $CaptionWidth = (Measure-RamText -Text $Caption -Font $Font).Width + $t.M.Gap
        }
        [void](Add-RamRow -Layout $Layout -Items @(
            @{ Control = $lbl; Width = $CaptionWidth },
            @{ Control = $Control; Width = ($Layout.Width - $CaptionWidth - $t.M.Gap) }
        ) -VAlign 'middle')
    } else {
        [void](Add-RamRow -Layout $Layout -Items @(@{ Control = $lbl; Width = $Layout.Width }) -Gap 2 -Height $capH)
        [void](Add-RamRow -Layout $Layout -Items @(@{ Control = $Control; Width = $Layout.Width }))
    }

    if ($Hint) {
        try {
            $tip = New-Object System.Windows.Forms.ToolTip
            $tip.SetToolTip($Control, $Hint)
            $tip.SetToolTip($lbl, $Hint)
        } catch { }
    }
    return $Control
}

function Add-RamColumns {
    <#
      Делит остаток ширины на колонки и возвращает по курсору на каждую.
      -Weights @(1,1) — поровну; @(400,0) — первой 400, второй остаток.
    #>
    param(
        [Parameter(Mandatory)]$Layout,
        [Parameter(Mandatory)][int[]]$Weights,
        [int]$Gap = -1
    )

    if ($Gap -lt 0) { $Gap = $Global:RamTheme.M.GapLg }
    $count = $Weights.Count
    $avail = $Layout.Width - ($Gap * [Math]::Max(0, $count - 1))

    # Явные ширины (больше единицы) берутся как есть, нули и единицы делят остаток.
    $fixedSum = 0; $flex = 0
    foreach ($w in $Weights) { if ($w -gt 1) { $fixedSum += $w } else { $flex++ } }
    $flexW = if ($flex -gt 0) { [int](($avail - $fixedSum) / $flex) } else { 0 }

    $cols = @()
    $x = $Layout.X
    foreach ($w in $Weights) {
        $cw = if ($w -gt 1) { $w } else { $flexW }
        $cols += [pscustomobject]@{
            Container = $Layout.Container
            X         = $x
            Y         = $Layout.Y
            Width     = [Math]::Max(1, $cw)
            Gap       = $Layout.Gap
            PadX      = $Layout.PadX
            PadY      = $Layout.PadY
            Bottom    = $Layout.Y
            MaxRight  = $x
        }
        $x += $cw + $Gap
    }
    return $cols
}

function Close-RamColumns {
    <# Двигает главный курсор ниже самой длинной колонки. #>
    param([Parameter(Mandatory)]$Layout, [Parameter(Mandatory)][object[]]$Columns)

    $low = $Layout.Y
    foreach ($c in $Columns) {
        if ($c.Y -gt $low) { $low = $c.Y }
        if ($c.MaxRight -gt $Layout.MaxRight) { $Layout.MaxRight = $c.MaxRight }
    }
    $Layout.Y = $low
    $Layout.Bottom = $low
    return $Layout
}

function Add-RamButtonBar {
    <#
      Ряд кнопок внизу окна — единственный способ их поставить.

      Договорённость на весь проект, чтобы окна перестали быть разными:
        главное действие  — крайнее справа;
        «Отмена»/«Закрыть» — слева от него;
        второстепенное («В файл», «Обновить») — прижато к левому краю.

      Ширины меряются ДО расстановки, поэтому кнопка не может внезапно
      расшириться под текст и сдвинуть соседа.
    #>
    param(
        [Parameter(Mandatory)]$Layout,
        $Primary,
        [object[]]$Secondary = @(),
        [object[]]$Extra = @()
    )

    $m = $Global:RamTheme.M

    # Правая группа: второстепенные слева от главной, главная — крайняя.
    $right = @()
    foreach ($b in $Secondary) { if ($null -ne $b) { $right += $b } }
    if ($null -ne $Primary) { $right += $Primary }

    $leftW = 0
    foreach ($b in $Extra) { if ($null -ne $b) { $leftW += (Measure-RamControl -Control $b).Width + $m.Gap } }

    $rowH = 0
    foreach ($b in ($right + $Extra)) { if ($null -ne $b -and $b.Height -gt $rowH) { $rowH = $b.Height } }
    if ($rowH -le 0) { $rowH = $m.RowH }

    $y = $Layout.Y

    # левая группа
    $x = $Layout.X
    foreach ($b in $Extra) {
        if ($null -eq $b) { continue }
        $w = (Measure-RamControl -Control $b).Width
        [void](Set-RamBounds -Control $b -X $x -Y ($y + [int](($rowH - $b.Height) / 2)) -Width $w)
        if ($null -eq $b.Parent) { $Layout.Container.Controls.Add($b) }
        $x += $w + $m.Gap
    }

    # правая группа
    $totalRight = 0
    foreach ($b in $right) { $totalRight += (Measure-RamControl -Control $b).Width + $m.Gap }
    $x = $Layout.X + $Layout.Width - $totalRight + $m.Gap
    if ($x -lt $Layout.X + $leftW) { $x = $Layout.X + $leftW }

    foreach ($b in $right) {
        $w = (Measure-RamControl -Control $b).Width
        [void](Set-RamBounds -Control $b -X $x -Y ($y + [int](($rowH - $b.Height) / 2)) -Width $w)
        if ($null -eq $b.Parent) { $Layout.Container.Controls.Add($b) }
        $x += $w + $m.Gap
        if ($x -gt $Layout.MaxRight) { $Layout.MaxRight = $x }
    }

    $Layout.Y += $rowH + $Layout.Gap
    $Layout.Bottom = $Layout.Y
    return $rowH
}

function Complete-RamLayout {
    <#
      Закрывает раскладку: размер контейнера считается ПО СОДЕРЖИМОМУ, а не
      задаётся константой. Именно из-за жёстких размеров окна при 150% не
      влезали в экран.

      -ClampToScreen обрезает по рабочей области, чтобы окно нельзя было
      сделать больше экрана.
    #>
    param(
        [Parameter(Mandatory)]$Layout,
        [int]$MinWidth = 0,
        [int]$MinHeight = 0,
        [switch]$ClampToScreen
    )

    $m = $Global:RamTheme.M
    $w = [Math]::Max($MinWidth,  $Layout.Width + ($Layout.PadX * 2))
    $h = [Math]::Max($MinHeight, $Layout.Bottom + $Layout.PadY)

    if ($ClampToScreen) {
        try {
            # $Global:RamForceWorkArea — подменённый экран Самопроверки. Без
            # него проверка на 150% зажимала окно по настоящему маленькому
            # столу разработчика и ругалась на несуществующую тесноту.
            if ($null -ne $Global:RamForceWorkArea) {
                $waW = [int]$Global:RamForceWorkArea.Width
                $waH = [int]$Global:RamForceWorkArea.Height
            } else {
                $wa  = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
                $waW = $wa.Width
                $waH = $wa.Height
            }
            if ($w -gt $waW) { $w = $waW }
            if ($h -gt $waH) { $h = $waH }
        } catch { }
    }

    if ($Layout.Container -is [System.Windows.Forms.Form]) {
        $Layout.Container.ClientSize = New-Object System.Drawing.Size($w, $h)
    } else {
        $Layout.Container.Size = New-Object System.Drawing.Size($w, $h)
    }
    return $Layout.Container
}
