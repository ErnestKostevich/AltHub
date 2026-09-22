#requires -Version 5.1
function New-RamForm {
    $form = New-Object System.Windows.Forms.Form
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    return $form
}

<#
================================================================================
 Theme.ps1 — тёмное оформление
================================================================================
 Палитра и самодельные элементы интерфейса: скруглённые кнопки и карточки,
 нарисованные вручную со сглаживанием. Обычные кнопки Windows не умеют в
 тёмную тему и скруглённые углы, поэтому рисуем сами.

 Здесь нет никакой логики — только внешний вид.
================================================================================
#>

# --------------------------------------------------------------- палитры ----
#
# Три темы на выбор. Меняется в Настройках, применяется при перезапуске окна.
# Все цвета берутся ТОЛЬКО отсюда — по коду нигде нет вписанных вручную оттенков.

# =========================================================== цвет: утилиты ===
#
# Всё, что нужно конструктору тем: перевод цвета в строку и обратно, работа
# в HSL и вывод целой палитры из одного акцента. Держим это здесь, рядом с
# палитрами, чтобы цвета всей программы задавались из одного места.

function Get-RamDpiScale {
    <#
      Во сколько раз экран крупнее обычного (96 точек на дюйм):
      1.0 при 100%, 1.25 при 125%, 1.5 при 150%.

      $Global:RamForceScale — подмена для Самопроверки. Она позволяет
      прогнать всю вёрстку при 125% и 150%, НЕ трогая системный масштаб
      экрана. На живом запуске такой переменной нет и берётся настоящий DPI.
    #>
    if ($null -ne $Global:RamForceScale) { return [double]$Global:RamForceScale }
    if ($null -ne $script:RamDpiScale)   { return $script:RamDpiScale }

    $sc = 1.0
    try {
        $f = New-Object System.Windows.Forms.Form
        $g = $f.CreateGraphics()
        $sc = $g.DpiY / 96.0
        $g.Dispose(); $f.Dispose()
    } catch { }
    $script:RamDpiScale = [Math]::Max(1.0, $sc)
    return $script:RamDpiScale
}

function Get-RamMetrics {
    <#
      Единая таблица отступов и высот В НАСТОЯЩИХ ПИКСЕЛЯХ текущего масштаба.

      Все числа вёрстки берутся отсюда. Вписывать координаты и отступы прямо
      в код окон нельзя: именно из-за этого при 125% и 150% подписи наезжали
      на кнопки — шрифт рос вместе с масштабом, а числа оставались прежними.
    #>
    param([double]$Scale = 0)

    if ($Scale -le 0) { $Scale = Get-RamDpiScale }
    $k = { param($v) [int][Math]::Round($v * $Scale) }

    @{
        Scale    = $Scale
        GapSm    = & $k 4
        Gap      = & $k 8
        GapLg    = & $k 16
        PadX     = & $k 28
        PadY     = & $k 22
        RowH     = & $k 34
        RowHSm   = & $k 30
        RowHLg   = & $k 38
        LabelH   = & $k 20
        CaptionH = & $k 18
        BtnPadX  = & $k 28
        BtnMinW  = & $k 110
        CardPad  = & $k 24
        StripeH  = & $k 4
        ScrollW  = & $k 17
    }
}

function Measure-RamText {
    <#
      Размер надписи текущим шрифтом темы.
      -MaxWidth больше нуля включает перенос по словам.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        $Font,
        [int]$MaxWidth = 0
    )

    if ($null -eq $Font) { $Font = $Global:RamTheme.FontBody }
    if ([string]::IsNullOrEmpty($Text)) { return (New-Object System.Drawing.Size(0, 0)) }

    if ($MaxWidth -gt 0) {
        # Чуть уже заданной ширины: Label рисует текст с внутренними полями, и
        # строка, «влезшая» по полной ширине, при отрисовке переносилась или
        # обрезалась многоточием.
        $sc = 1.0
        if ($null -ne $Global:RamTheme -and $null -ne $Global:RamTheme.M) { $sc = [double]$Global:RamTheme.M.Scale }
        $fitW = [Math]::Max(1, $MaxWidth - [Math]::Max(6, [int][Math]::Round(4 * $sc)))
        return [System.Windows.Forms.TextRenderer]::MeasureText(
            $Text, $Font,
            (New-Object System.Drawing.Size($fitW, 4000)),
            [System.Windows.Forms.TextFormatFlags]::WordBreak)
    }
    return [System.Windows.Forms.TextRenderer]::MeasureText($Text, $Font)
}

function ConvertTo-RamHex {
    <# Color -> '#RRGGBB'. #>
    param([Parameter(Mandatory)][System.Drawing.Color]$Color)
    '#{0:X2}{1:X2}{2:X2}' -f $Color.R, $Color.G, $Color.B
}

function ConvertFrom-RamHex {
    <#
      '#RRGGBB' (или 'RRGGBB', или короткое '#RGB') -> Color.
      Возвращает $null, если строка не похожа на цвет — вызывающий решает,
      что делать, а не получает исключение посреди отрисовки.
    #>
    param([string]$Hex)
    if ([string]::IsNullOrWhiteSpace($Hex)) { return $null }
    $h = $Hex.Trim().TrimStart('#')
    if ($h.Length -eq 3) { $h = "$($h[0])$($h[0])$($h[1])$($h[1])$($h[2])$($h[2])" }
    if ($h.Length -ne 6) { return $null }
    $n = 0
    if (-not [int]::TryParse($h, [System.Globalization.NumberStyles]::HexNumber,
                             [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $null }
    return [System.Drawing.Color]::FromArgb(($n -shr 16) -band 255, ($n -shr 8) -band 255, $n -band 255)
}

function ConvertTo-RamHsl {
    <# Color -> @{ H = 0..360; S = 0..1; L = 0..1 }. #>
    param([Parameter(Mandatory)][System.Drawing.Color]$Color)
    $r = $Color.R / 255.0; $g = $Color.G / 255.0; $b = $Color.B / 255.0
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $l = ($max + $min) / 2.0
    $h = 0.0; $sat = 0.0
    $d = $max - $min
    if ($d -ne 0) {
        $sat = if ($l -gt 0.5) { $d / (2.0 - $max - $min) } else { $d / ($max + $min) }
        if     ($max -eq $r) { $h = (($g - $b) / $d) % 6.0 }
        elseif ($max -eq $g) { $h = (($b - $r) / $d) + 2.0 }
        else                 { $h = (($r - $g) / $d) + 4.0 }
        $h *= 60.0
        if ($h -lt 0) { $h += 360.0 }
    }
    return @{ H = $h; S = $sat; L = $l }
}

function ConvertFrom-RamHsl {
    <# H (0..360), S/L (0..1) -> Color. #>
    param([double]$H, [double]$S, [double]$L)
    $S = [Math]::Max(0.0, [Math]::Min(1.0, $S))
    $L = [Math]::Max(0.0, [Math]::Min(1.0, $L))
    if ($S -eq 0) {
        $v = [int][Math]::Round($L * 255)
        return [System.Drawing.Color]::FromArgb($v, $v, $v)
    }
    $q = if ($L -lt 0.5) { $L * (1 + $S) } else { $L + $S - $L * $S }
    $pp = 2 * $L - $q
    $hk = ($H % 360) / 360.0
    $conv = {
        param($t)
        if ($t -lt 0) { $t += 1 }
        if ($t -gt 1) { $t -= 1 }
        if ($t -lt 1.0/6) { return $pp + ($q - $pp) * 6 * $t }
        if ($t -lt 1.0/2) { return $q }
        if ($t -lt 2.0/3) { return $pp + ($q - $pp) * (2.0/3 - $t) * 6 }
        return $pp
    }
    $r = & $conv ($hk + 1.0/3)
    $g = & $conv $hk
    $b = & $conv ($hk - 1.0/3)
    return [System.Drawing.Color]::FromArgb(
        [int][Math]::Round($r * 255),
        [int][Math]::Round($g * 255),
        [int][Math]::Round($b * 255))
}

function Get-RamPaletteColorKeys {
    <#
      Полный список цветовых ключей палитры с человеческими названиями —
      для полного редактора тем. Порядок = порядок в редакторе.

      Ok/Warn/Danger/DangerHov сюда НЕ входят: это цвета смысла (успех,
      предупреждение, опасность), их нельзя перекрашивать в зелёный ради
      красоты — красный должен читаться как красный. Их конструктор задаёт
      сам, подгоняя под светлую или тёмную основу.
    #>
    @(
        [pscustomobject]@{ Key = 'Bg';        Title = 'Фон окна' }
        [pscustomobject]@{ Key = 'Panel';     Title = 'Боковое меню и тулбар' }
        [pscustomobject]@{ Key = 'Card';      Title = 'Карточка аккаунта' }
        [pscustomobject]@{ Key = 'CardHover'; Title = 'Карточка под мышью' }
        [pscustomobject]@{ Key = 'CardSel';   Title = 'Выделение' }
        [pscustomobject]@{ Key = 'Border';    Title = 'Границы и обводка' }
        [pscustomobject]@{ Key = 'Text';      Title = 'Основной текст' }
        [pscustomobject]@{ Key = 'Muted';     Title = 'Приглушённый текст' }
        [pscustomobject]@{ Key = 'Accent';    Title = 'Акцент (кнопки, галочки)' }
        [pscustomobject]@{ Key = 'AccentHov'; Title = 'Акцент под мышью' }
        [pscustomobject]@{ Key = 'LogBack';   Title = 'Фон журнала' }
    )
}

function New-RamDerivedPalette {
    <#
      Собирает ЦЕЛУЮ палитру из одного акцентного цвета и типа основы.
      На этом держится «простой» режим конструктора: человек выбирает главный
      цвет и светло/темно — остальные 15 оттенков считаются так, чтобы всё
      гарантированно читалось.

      Base: 'dark' | 'light' | 'black' (AMOLED-чёрный).

      Нейтральные тона (фон, панель, карточка, текст) — это НЕ чистый серый,
      а серый с лёгкой примесью акцентного тона: так тема выглядит цельной,
      а не «цветная кнопка на сером». Насыщенность примеси маленькая, иначе
      фон начинает давить на глаза.
    #>
    param(
        [Parameter(Mandatory)][System.Drawing.Color]$Accent,
        [ValidateSet('dark','light','black')][string]$Base = 'dark',
        # Насколько сильно тон акцента примешан к нейтральным (фон, панели,
        # карточки). -1 = взять значение по умолчанию для этой основы.
        [double]$Tint = -1,
        # Сдвиг светлоты всех нейтральных. Нужен, чтобы готовые темы
        # различались не только тоном, но и глубиной.
        [double]$Lift = 0
    )

    $hsl = ConvertTo-RamHsl -Color $Accent
    $h   = $hsl.H
    $mk  = { param($sat, $lum) ConvertFrom-RamHsl -H $h -S $sat -L ([Math]::Max(0.0, [Math]::Min(1.0, $lum))) }

    if ($Base -eq 'light') {
        # ПОЧЕМУ ЗДЕСЬ НЕ L = 1.0.
        # В HSL при светлоте ровно 1.0 формула даёт чистый белый при ЛЮБОМ
        # тоне и любой насыщенности. Раньше Panel и Card считались как
        # (0.02, 1.00) — и все светлые темы получались пиксель-в-пиксель
        # одинаковыми. Отсюда жалоба «Небо и Светлая ничем не отличаются».
        # Держим потолок ниже единицы, чтобы тон вообще мог проявиться.
        if ($Tint -lt 0) { $Tint = 0.45 }

        return @{
            Bg        = & $mk $Tint            (0.955 + $Lift)
            Panel     = & $mk ($Tint * 0.55)   (0.995 + $Lift)
            Card      = & $mk ($Tint * 0.40)   (0.992 + $Lift)
            CardHover = & $mk ($Tint * 0.85)   (0.940 + $Lift)
            CardSel   = & $mk 0.85             (0.895 + $Lift)
            Border    = & $mk ($Tint * 0.70)   (0.855 + $Lift)
            Text      = & $mk 0.28             0.13
            Muted     = & $mk 0.18             0.44
            Accent    = $Accent
            AccentHov = & $mk ([Math]::Min(1.0, $hsl.S + 0.05)) ([Math]::Min(0.62, $hsl.L + 0.08))
            Ok        = ConvertFrom-RamHsl -H 150 -S 0.72 -L 0.34
            Warn      = ConvertFrom-RamHsl -H  35 -S 0.92 -L 0.38
            Danger    = ConvertFrom-RamHsl -H   2 -S 0.66 -L 0.49
            DangerHov = ConvertFrom-RamHsl -H   2 -S 0.72 -L 0.59
            LogBack   = & $mk ($Tint * 0.45)   (0.985 + $Lift)
        }
    }

    # Тёмная основа. 'black' — почти чёрный фон для AMOLED-экранов.
    #
    # Примесь тона раньше была 0.10, и на тёмном это давало разброс каналов
    # всего ±2 — темы «Изумруд» и «Океан» отличались фоном на 2 единицы RGB
    # при пороге различимости 5–8. Подняли до заметного.
    # Скобочный if как выражение PowerShell 5.1 не понимает — только присваивание.
    $isBlack = ($Base -eq 'black')
    if ($Tint -lt 0) {
        if ($isBlack) { $Tint = 0.30 } else { $Tint = 0.26 }
    }

    if ($isBlack) {
        $bgL = 0.030; $panL = 0.070; $cardL = 0.110; $logL = 0.020
    } else {
        $bgL = 0.095; $panL = 0.135; $cardL = 0.175; $logL = 0.075
    }
    $bgL   += $Lift
    $panL  += $Lift
    $cardL += $Lift
    $logL  += $Lift

    return @{
        Bg        = & $mk $Tint            $bgL
        Panel     = & $mk ($Tint * 0.92)   $panL
        Card      = & $mk ($Tint * 0.85)   $cardL
        CardHover = & $mk ($Tint * 1.05)   ($cardL + 0.05)
        CardSel   = & $mk 0.50             ($cardL + 0.06)
        Border    = & $mk ($Tint * 0.75)   ($cardL + 0.11)
        Text      = & $mk 0.16             0.95
        Muted     = & $mk 0.14             0.62
        Accent    = $Accent
        AccentHov = & $mk ([Math]::Min(1.0, $hsl.S + 0.04)) ([Math]::Min(0.80, $hsl.L + 0.10))
        Ok        = ConvertFrom-RamHsl -H 145 -S 0.60 -L 0.53
        Warn      = ConvertFrom-RamHsl -H  38 -S 0.90 -L 0.50
        Danger    = ConvertFrom-RamHsl -H   0 -S 0.83 -L 0.60
        DangerHov = ConvertFrom-RamHsl -H   0 -S 0.90 -L 0.68
        LogBack   = & $mk ($Tint * 0.85)   $logL
    }
}

function Get-RamCustomThemes {
    <# Свои темы пользователя из настроек. Пусто, если настроек ещё нет. #>
    if ($null -eq $script:Settings) { return @() }
    if (-not ($script:Settings.PSObject.Properties.Name -contains 'CustomThemes')) { return @() }
    return @($script:Settings.CustomThemes | Where-Object { $_ -and $_.Key })
}

function Get-RamCustomPalette {
    <#
      Собирает палитру из сохранённой своей темы (цвета там строками '#RRGGBB').
      $null, если темы с таким ключом нет.

      Недостающие цвета достаём из тёмной темы, а не падаем: файл темы мог
      прийти из будущей версии, где ключей больше, или из чужих рук.
    #>
    param([string]$Name)

    $theme = Get-RamCustomThemes | Where-Object { $_.Key -eq $Name } | Select-Object -First 1
    if ($null -eq $theme) { return $null }

    $fallback = Get-RamPalette -Name 'dark'
    $pal = @{ Key = [string]$theme.Key; Title = [string]$theme.Title }

    $keys = @('Bg','Panel','Card','CardHover','CardSel','Border','Text','Muted',
              'Accent','AccentHov','Ok','Warn','Danger','DangerHov','LogBack')
    foreach ($k in $keys) {
        $col = $null
        if ($theme.Colors.PSObject.Properties.Name -contains $k) {
            $col = ConvertFrom-RamHex -Hex ([string]$theme.Colors.$k)
        }
        $pal[$k] = if ($null -ne $col) { $col } else { $fallback[$k] }
    }
    return $pal
}

function ConvertTo-RamThemeRecord {
    <#
      Палитра (Color-объекты) -> запись для сохранения (цвета строками).
      Именно это уходит в настройки и в файл темы для друга.
    #>
    param([Parameter(Mandatory)]$Palette, [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Title)

    $colors = [ordered]@{}
    $keys = @('Bg','Panel','Card','CardHover','CardSel','Border','Text','Muted',
              'Accent','AccentHov','Ok','Warn','Danger','DangerHov','LogBack')
    foreach ($k in $keys) { $colors[$k] = ConvertTo-RamHex -Color $Palette[$k] }

    [pscustomobject]@{
        Key    = $Key
        Title  = $Title
        Colors = [pscustomobject]$colors
    }
}

function Get-RamPalette {
    param([string]$Name = 'dark')

    $c = { param($r, $g, $b) [System.Drawing.Color]::FromArgb($r, $g, $b) }

    # Свои темы из настроек — первыми: если человек назвал свою тему как
    # стоковую, важнее его выбор.
    $custom = Get-RamCustomPalette -Name $Name
    if ($null -ne $custom) { return $custom }

    switch ($Name) {

        # Полночь — глубокий синий с фиолетовым акцентом
        'midnight' {
            return @{
                Key       = 'midnight'; Title = 'Полночь'
                Bg        = & $c  16  18  34
                Panel     = & $c  23  26  46
                Card      = & $c  32  36  62
                CardHover = & $c  42  47  79
                CardSel   = & $c  55  45 104
                Border    = & $c  52  58  92
                Text      = & $c 233 236 250
                Muted     = & $c 141 149 186
                Accent    = & $c 139 108 255
                AccentHov = & $c 165 141 255
                Ok        = & $c  45 212 160
                Warn      = & $c 250 176  74
                Danger    = & $c 240  91 122
                DangerHov = & $c 248 130 155
                LogBack   = & $c  12  14  28
            }
        }

        # Светлая — для тех, кому тёмное не заходит
        'light' {
            return @{
                Key       = 'light'; Title = 'Светлая'
                Bg        = & $c 243 245 249
                Panel     = & $c 255 255 255
                Card      = & $c 255 255 255
                CardHover = & $c 238 243 252
                CardSel   = & $c 219 234 254
                Border    = & $c 213 219 230
                Text      = & $c  24  28  38
                Muted     = & $c 106 116 133
                Accent    = & $c   0 122 214
                AccentHov = & $c  32 148 236
                Ok        = & $c  22 148  82
                Warn      = & $c 191 120   8
                Danger    = & $c 205  44  44
                DangerHov = & $c 226  76  76
                LogBack   = & $c 250 251 253
            }
        }

        # --- Собранные из акцента одной строкой. Держим их так, а не таблицей
        #     из 15 цветов: если поправить формулу вывода, все они обновятся
        #     разом и останутся согласованными. Ручные — только три первых,
        #     их трогать незачем.

        # Тон + СВОЯ глубина и своя примесь. Одного тона мало: без разницы
        # в светлоте и насыщенности темы выглядят как один и тот же серый
        # интерфейс с перекрашенной кнопкой.

        'emerald' {  # Изумруд — глубокая зелёная
            $p = New-RamDerivedPalette -Accent ([System.Drawing.Color]::FromArgb(16, 185, 129)) -Base 'dark' -Tint 0.34 -Lift -0.012
            $p.Key = 'emerald'; $p.Title = 'Изумруд'; return $p
        }
        'sunset' {   # Закат — тёплая, чуть светлее прочих
            $p = New-RamDerivedPalette -Accent ([System.Drawing.Color]::FromArgb(251, 113, 64)) -Base 'dark' -Tint 0.30 -Lift 0.022
            $p.Key = 'sunset'; $p.Title = 'Закат'; return $p
        }
        'rose' {     # Роза — тёплая розовая, средней глубины
            $p = New-RamDerivedPalette -Accent ([System.Drawing.Color]::FromArgb(244, 94, 150)) -Base 'dark' -Tint 0.26 -Lift 0.008
            $p.Key = 'rose'; $p.Title = 'Роза'; return $p
        }
        'ocean' {    # Океан — холодная бирюза, светлее изумруда
            $p = New-RamDerivedPalette -Accent ([System.Drawing.Color]::FromArgb(34, 197, 211)) -Base 'dark' -Tint 0.28 -Lift 0.030
            $p.Key = 'ocean'; $p.Title = 'Океан'; return $p
        }
        'grape' {    # Виноград — самая насыщенная и тёмная
            $p = New-RamDerivedPalette -Accent ([System.Drawing.Color]::FromArgb(168, 120, 245)) -Base 'dark' -Tint 0.40 -Lift -0.004
            $p.Key = 'grape'; $p.Title = 'Виноград'; return $p
        }
        'amoled' {   # Чёрная — почти чёрный фон для AMOLED
            $p = New-RamDerivedPalette -Accent ([System.Drawing.Color]::FromArgb(0, 162, 255)) -Base 'black' -Tint 0.24
            $p.Key = 'amoled'; $p.Title = 'Чёрная'; return $p
        }
        'sky' {      # Небо — светлая, отчётливо голубая (не серая, как Светлая)
            $p = New-RamDerivedPalette -Accent ([System.Drawing.Color]::FromArgb(14, 130, 233)) -Base 'light' -Tint 0.62 -Lift -0.012
            $p.Key = 'sky'; $p.Title = 'Небо'; return $p
        }

        # Тёмная — по умолчанию, нейтральная под стиль Roblox
        default {
            return @{
                Key       = 'dark'; Title = 'Тёмная'
                Bg        = & $c  24  26  31
                Panel     = & $c  31  34  40
                Card      = & $c  39  43  51
                CardHover = & $c  48  53  62
                CardSel   = & $c  30  58  82
                Border    = & $c  56  62  72
                Text      = & $c 240 243 247
                Muted     = & $c 150 158 170
                Accent    = & $c   0 162 255
                AccentHov = & $c  51 181 255
                Ok        = & $c  34 197  94
                Warn      = & $c 245 158  11
                Danger    = & $c 239  68  68
                DangerHov = & $c 248 113 113
                LogBack   = & $c  20  22  26
            }
        }
    }
}

function Get-RamStockThemeList {
    <# Встроенные темы. Порядок = порядок в меню выбора. #>
    @(
        [pscustomobject]@{ Key = 'dark';     Title = 'Тёмная'   },
        [pscustomobject]@{ Key = 'midnight'; Title = 'Полночь'  },
        [pscustomobject]@{ Key = 'emerald';  Title = 'Изумруд'  },
        [pscustomobject]@{ Key = 'ocean';    Title = 'Океан'    },
        [pscustomobject]@{ Key = 'grape';    Title = 'Виноград' },
        [pscustomobject]@{ Key = 'rose';     Title = 'Роза'     },
        [pscustomobject]@{ Key = 'sunset';   Title = 'Закат'    },
        [pscustomobject]@{ Key = 'amoled';   Title = 'Чёрная'   },
        [pscustomobject]@{ Key = 'light';    Title = 'Светлая'  },
        [pscustomobject]@{ Key = 'sky';      Title = 'Небо'     }
    )
}

function Get-RamThemeList {
    <# Стоковые темы плюс свои из настроек. #>
    $list = @(Get-RamStockThemeList)
    foreach ($ct in Get-RamCustomThemes) {
        $list += [pscustomobject]@{ Key = [string]$ct.Key; Title = [string]$ct.Title; Custom = $true }
    }
    return @($list)
}

function New-RamFont {
    <#
      Шрифт в ПИКСЕЛЯХ от единого масштаба Get-RamDpiScale.

      На живом запуске это ровно тот же размер, что и в пунктах: пункт × DPI / 72.
      Зато при подмене масштаба ($Global:RamForceScale) шрифт и метрики всегда
      согласованы, на любом экране — пункты такой подмены не слушаются и растут
      ещё и с настоящим DPI.
    #>
    param(
        [string]$Family = 'Segoe UI',
        [double]$Points = 9.5,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )
    $px = [single]($Points * 96.0 / 72.0 * (Get-RamDpiScale))
    return New-Object System.Drawing.Font($Family, $px, $Style, [System.Drawing.GraphicsUnit]::Pixel)
}

function Set-RamTheme {
    <# Ставит палитру и добавляет к ней шрифты — шрифты общие для всех тем. #>
    param([string]$Name = 'dark')

    # Если тема не нашлась (например, файл настроек ссылается на удалённую
    # свою тему) — откатываемся на тёмную, а не падаем.
    $known = @(Get-RamThemeList | ForEach-Object { $_.Key })
    if ($known -notcontains $Name) { $Name = 'dark' }
    $p = Get-RamPalette -Name $Name

    if ($null -ne $Global:RamTheme) {
        foreach ($name in @('FontBig','FontTitle','FontBody','FontSmall','FontMono')) {
            try { if ($null -ne $Global:RamTheme.$name) { $Global:RamTheme.$name.Dispose() } } catch { }
        }
    }
    if ($null -ne $script:RamEmojiFonts) {
        foreach ($font in @($script:RamEmojiFonts.Values)) { try { $font.Dispose() } catch { } }
    }

    # ШРИФТЫ — В ПИКСЕЛЯХ ОТ ТОГО ЖЕ МАСШТАБА, ЧТО И ВСЕ МЕТРИКИ (New-RamFont).
    # Раньше размер задавался в пунктах и ещё умножался на подменённый масштаб.
    # Пункты сами растут с настоящим DPI экрана, поэтому при подмене масштаба
    # (Самопроверка, стенд вёрстки) шрифт масштабировался дважды: на экране
    # со 200% «проверка 150%» рисовала текст втрое крупнее расчёта, и вся
    # проверка вёрстки на крупном масштабе проверяла неправду.
    $p.FontBig   = New-RamFont -Family 'Segoe UI Semibold' -Points 15
    $p.FontTitle = New-RamFont -Family 'Segoe UI Semibold' -Points 11
    $p.FontBody  = New-RamFont -Family 'Segoe UI'          -Points 9.5
    $p.FontSmall = New-RamFont -Family 'Segoe UI'          -Points 8.5
    $p.FontMono  = New-RamFont -Family 'Consolas'          -Points 9

    # Кэш эмодзи-шрифтов держит РАЗМЕР, поэтому при смене масштаба его надо
    # выбросить — иначе смайлики останутся прежней величины.
    $script:RamEmojiFonts = @{}

    # Метрики пересобираются вместе с темой: они зависят от масштаба.
    $p.M = Get-RamMetrics

    $Global:RamTheme = $p
    return $p
}

# Тема по умолчанию — чтобы модуль можно было подключать и отдельно.
Set-RamTheme -Name 'dark' | Out-Null

if (-not ('Ram.Dwm' -as [type])) {
@'
using System;
using System.Runtime.InteropServices;

namespace Ram {
    public static class Dwm {
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        // Тёмная рамка окна средствами самой Windows. На старых сборках просто
        // ничего не произойдёт — заголовок останется светлым.
        public static void UseDarkTitleBar(IntPtr hwnd) {
            int on = 1;
            if (DwmSetWindowAttribute(hwnd, 20, ref on, sizeof(int)) != 0) {
                DwmSetWindowAttribute(hwnd, 19, ref on, sizeof(int));
            }
        }
    }
}
'@ | ForEach-Object { Add-Type -TypeDefinition $_ -ErrorAction SilentlyContinue }
}

if (-not ('Ram.ScrollTheme' -as [type])) {
@'
using System;
using System.Runtime.InteropServices;

namespace Ram {
    public static class ScrollTheme {
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
        private static extern int SetWindowTheme(IntPtr hwnd, string app, string idList);

        // Тёмные полосы прокрутки — та же тема, что у Проводника в тёмном
        // режиме. На старых сборках Windows полоса просто останется светлой.
        public static void Apply(IntPtr hwnd, bool dark) {
            SetWindowTheme(hwnd, dark ? "DarkMode_Explorer" : "Explorer", null);
        }
    }
}
'@ | ForEach-Object { Add-Type -TypeDefinition $_ -ErrorAction SilentlyContinue }
}

function Test-RamThemeIsDark {
    <# Тёмная ли тема — по яркости фона: своя тема тоже бывает и светлой, и тёмной. #>
    $bg = $Global:RamTheme.Bg
    if ($null -eq $bg) { return $true }
    return (($bg.R * 299 + $bg.G * 587 + $bg.B * 114) / 1000) -lt 128
}

function Set-RamScrollTheme {
    <#
      Полоса прокрутки в цвет темы. Раньше на тёмной теме она оставалась
      системной белой — светлая полоса во всю высоту списка.
      Хендл окна появляется не сразу, поэтому ставим и при его создании.
    #>
    param([Parameter(Mandatory)]$Control)
    if ($Control.IsHandleCreated) {
        try { [Ram.ScrollTheme]::Apply($Control.Handle, (Test-RamThemeIsDark)) } catch { }
    }
    $Control.Add_HandleCreated({ try { [Ram.ScrollTheme]::Apply($this.Handle, (Test-RamThemeIsDark)) } catch { } })
}

function Set-RamDarkTitleBar {
    <# Тёмная рамка окна — только для тёмных тем. На светлой она смотрелась бы
       чужеродно, там оставляем системную. #>
    param($Form)
    if ($Global:RamTheme.Key -eq 'light') { return }
    try { [Ram.Dwm]::UseDarkTitleBar($Form.Handle) } catch { }
}

# ---------------------------------------------------------------- смайлики --
#
# Названия игр в Roblox сплошь и рядом содержат смайлики: «[🌙] Elemental
# Dungeons». Шрифт Segoe UI их не содержит, поэтому вместо картинки рисуется
# пустой квадратик.
#
# Проверено опытом: Segoe UI Emoji рисует смайлики правильно, а буквы Windows
# при этом подставляет из обычного шрифта — то есть текст не портится. Поэтому
# подписи со смайликами просто переключаем на этот шрифт.
#
# Исключение — то, что мы рисуем сами через Graphics.DrawString (кнопки,
# статусы) и моноширинный журнал: там подстановки шрифта нет, и смайлики
# приходится вычищать.

$script:RamEmojiFonts = @{}

function Test-RamHasEmoji {
    <# Есть ли в строке символы, которых нет в обычном шрифте интерфейса. #>
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    # Суррогатные пары (всё, что выше BMP) + стрелки, значки и модификаторы.
    return ($Text -match '[\uD800-\uDBFF][\uDC00-\uDFFF]') -or
           ($Text -match '[\u2190-\u2BFF\uFE0F\u20E3\u3030\u303D]')
}

function Get-RamEmojiFont {
    <# Шрифт со смайликами того же размера. Кэшируем: создание шрифта не
       бесплатно, а подписи перестраиваются часто. #>
    param([Parameter(Mandatory)][System.Drawing.Font]$Like)

    $key = '{0}|{1}|{2}' -f $Like.Size, [int]$Like.Style, [int]$Like.Unit
    if ($script:RamEmojiFonts.ContainsKey($key)) { return $script:RamEmojiFonts[$key] }

    try {
        # Единица — та же, что у образца: размер темы теперь в пикселях.
        $f = New-Object System.Drawing.Font('Segoe UI Emoji', $Like.Size, $Like.Style, $Like.Unit)
    } catch {
        $f = $Like
    }
    $script:RamEmojiFonts[$key] = $f
    return $f
}

function Remove-RamEmoji {
    <# Убирает смайлики и подчищает пустые скобки, которые от них остаются:
       «[🌙] Elemental Dungeons» -> «Elemental Dungeons». #>
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }

    $t = [regex]::Replace($Text, '[\uD800-\uDBFF][\uDC00-\uDFFF]', '')
    $t = [regex]::Replace($t,    '[\u2190-\u2BFF\uFE0F\u20E3\u3030\u303D]', '')
    $t = $t -replace '\[\s*\]', ''
    $t = $t -replace '\(\s*\)', ''
    $t = $t -replace '\s{2,}', ' '
    return $t.Trim()
}

function New-RamRoundRect {
    <# Путь скруглённого прямоугольника — основа всей отрисовки. #>
    param(
        [Parameter(Mandatory)][System.Drawing.Rectangle]$Rect,
        [int]$Radius = 8
    )
    $d = $Radius * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($Radius -le 0) {
        $path.AddRectangle($Rect)
    } else {
        $path.AddArc($Rect.X,                 $Rect.Y,                  $d, $d, 180, 90)
        $path.AddArc($Rect.Right - $d,        $Rect.Y,                  $d, $d, 270, 90)
        $path.AddArc($Rect.Right - $d,        $Rect.Bottom - $d,        $d, $d,   0, 90)
        $path.AddArc($Rect.X,                 $Rect.Bottom - $d,        $d, $d,  90, 90)
        $path.CloseFigure()
    }
    return $path
}

function Set-RamDoubleBuffered {
    <# Убирает мерцание при перерисовке. Свойство скрытое, поэтому рефлексия. #>
    param([Parameter(Mandatory)]$Control)
    try {
        $prop = $Control.GetType().GetProperty('DoubleBuffered',
                    [System.Reflection.BindingFlags]'Instance,NonPublic')
        if ($null -ne $prop) { $prop.SetValue($Control, $true, $null) }
    } catch { }
}

function Get-RamScaled {
    <#
      Число, подогнанное под масштаб экрана.

      Нужен потому, что высоты кнопок по всему главному окну были вписаны
      числами (26, 28, 32, 34, 36). Шрифт при 125% и 150% растёт, высота
      остаётся — и надпись обрезается по вертикали, вплоть до полностью
      пустой кнопки. Ширина так не ломается: New-RamButton считает её от
      надписи сам, а заданное число там — только минимум.
    #>
    param([Parameter(Mandatory)][int]$Value)
    $sc = 1.0
    if ($null -ne $Global:RamTheme -and $null -ne $Global:RamTheme.M) { $sc = $Global:RamTheme.M.Scale }
    return [int][Math]::Round($Value * $sc)
}

# ======================================================== значки-рисунки =====
#
# ЗАЧЕМ. Раньше значки кнопок были символами шрифта («◉», «▣», «⚿»). Такие
# символы у каждого шрифта свои: где-то они мелкие, где-то жирные, где-то
# вместо значка пустой прямоугольник. Выглядело это разнобойно и заметно
# старее, чем нужно.
#
# Здесь значки РИСУЮТСЯ линиями в квадрате 24x24 и растягиваются под нужный
# размер. Толщина линии одна на все значки, поэтому весь ряд в меню выглядит
# единым набором, одинаково на 100%, 125% и 150%.

function Get-RamGlyphNames {
    @('user','gamepad','profile','chart','history','bolt','play','stop',
      'windows','key','gear','help','plus','search','trash','assign')
}

function Test-RamGlyph {
    param([string]$Name)
    if (-not $Name) { return $false }
    return ((Get-RamGlyphNames) -contains $Name)
}

function Draw-RamGlyph {
    <#
      Рисует значок $Name линиями внутри прямоугольника $Rect цветом $Color.
      Все координаты — в сетке 24x24, поэтому значок одинаково правильный
      при любом размере.
    #>
    param(
        [Parameter(Mandatory)]$G,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Rect,
        [Parameter(Mandatory)][System.Drawing.Color]$Color
    )

    $size = [Math]::Min([single]$Rect.Width, [single]$Rect.Height)
    if ($size -le 4) { return }
    $u  = $size / 24.0
    $ox = [single]($Rect.X + ($Rect.Width  - $size) / 2.0)
    $oy = [single]($Rect.Y + ($Rect.Height - $size) / 2.0)

    $pt = {
        param($x, $y)
        New-Object System.Drawing.PointF(([single]($ox + $x * $u)), ([single]($oy + $y * $u)))
    }
    $rc = {
        param($x, $y, $w, $h)
        New-Object System.Drawing.RectangleF(([single]($ox + $x * $u)), ([single]($oy + $y * $u)),
                                             ([single]($w * $u)), ([single]($h * $u)))
    }

    $pen = New-Object System.Drawing.Pen($Color, [single]([Math]::Max(1.3, $size / 12.0)))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $brush = New-Object System.Drawing.SolidBrush($Color)

    $old = $G.SmoothingMode
    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    try {
        switch ($Name) {

            'user' {      # аккаунты — голова и плечи
                $G.DrawEllipse($pen, (& $rc 8 3 8 8))
                $G.DrawArc($pen, (& $rc 4 12.5 16 13), 200, 140)
            }

            'profile' {   # профили — тот же человек, но в рамке-медальоне
                $G.DrawEllipse($pen, (& $rc 9 4 6 6))
                $G.DrawArc($pen, (& $rc 5.5 12 13 11), 200, 140)
                $G.DrawEllipse($pen, (& $rc 2.5 2.5 19 19))
            }

            'gamepad' {   # игры — геймпад: корпус с рожками, крестовина и две кнопки
                $p = New-Object System.Drawing.Drawing2D.GraphicsPath
                $p.AddBezier((& $pt 4.5 11.5), (& $pt 4.8 6.5), (& $pt 8 6.2), (& $pt 9.2 8.2))
                $p.AddLine((& $pt 9.2 8.2), (& $pt 14.8 8.2))
                $p.AddBezier((& $pt 14.8 8.2), (& $pt 16 6.2), (& $pt 19.2 6.5), (& $pt 19.5 11.5))
                $p.AddBezier((& $pt 19.5 11.5), (& $pt 19.8 17.5), (& $pt 17.3 18.3), (& $pt 15.6 15.3))
                $p.AddBezier((& $pt 15.6 15.3), (& $pt 14.6 13.6), (& $pt 9.4 13.6), (& $pt 8.4 15.3))
                $p.AddBezier((& $pt 8.4 15.3), (& $pt 6.7 18.3), (& $pt 4.2 17.5), (& $pt 4.5 11.5))
                $p.CloseFigure()
                $G.DrawPath($pen, $p)
                $p.Dispose()
                $G.DrawLine($pen, (& $pt 6.4 11.6), (& $pt 9.4 11.6))
                $G.DrawLine($pen, (& $pt 7.9 10.1), (& $pt 7.9 13.1))
                $G.FillEllipse($brush, (& $rc 16.6 9.6 1.9 1.9))
                $G.FillEllipse($brush, (& $rc 14.3 11.9 1.9 1.9))
            }

            'chart' {     # статистика — три столбика
                $G.DrawLine($pen, (& $pt 6 18), (& $pt 6 12))
                $G.DrawLine($pen, (& $pt 12 18), (& $pt 12 7))
                $G.DrawLine($pen, (& $pt 18 18), (& $pt 18 14))
            }

            'history' {   # журнал — часы со стрелкой назад
                $G.DrawArc($pen, (& $rc 3.5 3.5 17 17), 60, 300)
                $G.DrawLine($pen, (& $pt 12 8), (& $pt 12 12.4))
                $G.DrawLine($pen, (& $pt 12 12.4), (& $pt 15.4 14.4))
                $G.DrawLine($pen, (& $pt 3.4 8.6), (& $pt 6.6 6.4))
                $G.DrawLine($pen, (& $pt 3.4 8.6), (& $pt 3.2 4.8))
            }

            'bolt' {      # фаст-настройка — молния
                $p = New-Object System.Drawing.Drawing2D.GraphicsPath
                $p.AddPolygon(@((& $pt 13.5 2.5), (& $pt 6 13.5), (& $pt 11 13.5),
                                (& $pt 10 21.5), (& $pt 18 10.5), (& $pt 13 10.5)))
                $p.CloseFigure()
                $G.DrawPath($pen, $p)
                $p.Dispose()
            }

            'play' {      # запустить — треугольник
                $p = New-Object System.Drawing.Drawing2D.GraphicsPath
                $p.AddPolygon(@((& $pt 8 5.5), (& $pt 19 12), (& $pt 8 18.5)))
                $G.FillPath($brush, $p)
                $p.Dispose()
            }

            'stop' {      # закрыть — квадрат со скруглением
                $r = & $rc 6.5 6.5 11 11
                $p = New-RamRoundRect -Rect (New-Object System.Drawing.Rectangle(
                        [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height)) -Radius ([int][Math]::Max(2, 2.2 * $u))
                $G.FillPath($brush, $p)
                $p.Dispose()
            }

            'windows' {   # окна — сетка 2x2
                $G.DrawRectangle($pen, [single]($ox + 3.5 * $u), [single]($oy + 3.5 * $u), [single](7 * $u), [single](7 * $u))
                $G.DrawRectangle($pen, [single]($ox + 13.5 * $u), [single]($oy + 3.5 * $u), [single](7 * $u), [single](7 * $u))
                $G.DrawRectangle($pen, [single]($ox + 3.5 * $u), [single]($oy + 13.5 * $u), [single](7 * $u), [single](7 * $u))
                $G.DrawRectangle($pen, [single]($ox + 13.5 * $u), [single]($oy + 13.5 * $u), [single](7 * $u), [single](7 * $u))
            }

            'key' {       # проверить входы — ключ
                $G.DrawEllipse($pen, (& $rc 3 3 8.5 8.5))
                $G.DrawLine($pen, (& $pt 10.4 11.2), (& $pt 20.5 21.3))
                $G.DrawLine($pen, (& $pt 17.4 18.2), (& $pt 15.2 20.4))
                $G.DrawLine($pen, (& $pt 19.6 20.4), (& $pt 17.4 22.6))
            }

            'gear' {      # настройки — шестерёнка: зубчатый обод и отверстие в центре
                $p = New-Object System.Drawing.Drawing2D.GraphicsPath
                $p.AddPolygon(@(
                    (& $pt 18.6 12.23), (& $pt 21.05 13.68), (& $pt 19.58 17.21), (& $pt 16.83 16.5),
                    (& $pt 16.5 16.83), (& $pt 17.21 19.58), (& $pt 13.68 21.05), (& $pt 12.23 18.6),
                    (& $pt 11.77 18.6), (& $pt 10.32 21.05), (& $pt 6.79 19.58), (& $pt 7.5 16.83),
                    (& $pt 7.17 16.5), (& $pt 4.42 17.21), (& $pt 2.95 13.68), (& $pt 5.4 12.23),
                    (& $pt 5.4 11.77), (& $pt 2.95 10.32), (& $pt 4.42 6.79), (& $pt 7.17 7.5),
                    (& $pt 7.5 7.17), (& $pt 6.79 4.42), (& $pt 10.32 2.95), (& $pt 11.77 5.4),
                    (& $pt 12.23 5.4), (& $pt 13.68 2.95), (& $pt 17.21 4.42), (& $pt 16.5 7.17),
                    (& $pt 16.83 7.5), (& $pt 19.58 6.79), (& $pt 21.05 10.32), (& $pt 18.6 11.77)
                ))
                $p.CloseFigure()
                $G.DrawPath($pen, $p)
                $p.Dispose()
                $G.DrawEllipse($pen, (& $rc 9.4 9.4 5.2 5.2))
            }

            'help' {      # справка — вопрос в кружке
                $G.DrawEllipse($pen, (& $rc 2.5 2.5 19 19))
                $G.DrawArc($pen, (& $rc 8.4 6.4 7.2 7.2), 170, 230)
                $G.DrawLine($pen, (& $pt 12 13.2), (& $pt 12 15.2))
                $G.FillEllipse($brush, (& $rc 11 17.2 2 2))
            }

            'plus' {
                $G.DrawLine($pen, (& $pt 12 6), (& $pt 12 18))
                $G.DrawLine($pen, (& $pt 6 12), (& $pt 18 12))
            }

            'search' {
                $G.DrawEllipse($pen, (& $rc 4 4 12 12))
                $G.DrawLine($pen, (& $pt 15.5 15.5), (& $pt 20.5 20.5))
            }

            'trash' {     # удалить — мусорная корзина: крышка, ручка, корпус, рёбра
                $G.DrawLine($pen, (& $pt 5 7), (& $pt 19 7))
                $G.DrawLine($pen, (& $pt 9.5 7), (& $pt 9.5 4.5))
                $G.DrawLine($pen, (& $pt 9.5 4.5), (& $pt 14.5 4.5))
                $G.DrawLine($pen, (& $pt 14.5 4.5), (& $pt 14.5 7))
                $G.DrawLine($pen, (& $pt 6.3 7), (& $pt 7.2 20))
                $G.DrawLine($pen, (& $pt 7.2 20), (& $pt 16.8 20))
                $G.DrawLine($pen, (& $pt 16.8 20), (& $pt 17.7 7))
                $G.DrawLine($pen, (& $pt 10.3 10.2), (& $pt 10.7 17))
                $G.DrawLine($pen, (& $pt 13.7 10.2), (& $pt 13.3 17))
            }

            'assign' {    # назначить отмеченным — метка-пин с галочкой внутри
                $p = New-Object System.Drawing.Drawing2D.GraphicsPath
                $p.AddBezier((& $pt 4.5 10.5), (& $pt 4.5 5.8), (& $pt 8 2.5), (& $pt 12 2.5))
                $p.AddBezier((& $pt 12 2.5), (& $pt 16 2.5), (& $pt 19.5 5.8), (& $pt 19.5 10.5))
                $p.AddBezier((& $pt 19.5 10.5), (& $pt 19.5 15.3), (& $pt 14.3 20.3), (& $pt 12 22.3))
                $p.AddBezier((& $pt 12 22.3), (& $pt 9.7 20.3), (& $pt 4.5 15.3), (& $pt 4.5 10.5))
                $p.CloseFigure()
                $G.DrawPath($pen, $p)
                $p.Dispose()
                $G.DrawLine($pen, (& $pt 8.2 10.6), (& $pt 11 13.4))
                $G.DrawLine($pen, (& $pt 11 13.4), (& $pt 16 7.8))
            }
        }
    } catch { }

    $G.SmoothingMode = $old
    $pen.Dispose()
    $brush.Dispose()
}


function New-RamButton {
    <#
      Кнопка на основе Panel: рисуем сами, чтобы получить тёмный фон,
      скруглённые углы и нормальное наведение мышью.

      Kind: primary | normal | danger | ghost
    #>
    param(
        # Mandatory снят: кнопки-иконки без подписи (-IconOnly) передают
        # -Text '' — пустую строку. PowerShell у Mandatory-параметра типа
        # string отклоняет '' как «пустой аргумент», даже если сам параметр
        # присутствует в вызове, и кидает ошибку привязки параметра прямо
        # при запуске. Явное значение по умолчанию ''  сохраняет то же
        # поведение для всех обычных кнопок (они как и раньше обязаны
        # передавать текст), просто без строгой проверки, которая здесь
        # мешает, а не помогает.
        [string]$Text = '',
        # ЭТО МИНИМУМ, а не обещание: если надпись длиннее, кнопка будет шире.
        [int]$Width  = 150,
        [int]$Height = 34,
        [ValidateSet('primary','normal','danger','ghost')][string]$Kind = 'normal',
        [scriptblock]$OnClick,
        [string]$Tooltip,
        [int]$Radius = 7,
        # Не подгонять под текст: ширина ровно такая, как просили, длинное
        # обрезать многоточием. Нужно там, где кнопка прибита к краю окна.
        [switch]$Fixed,
        # ЗНАЧОК СЛЕВА — ОТДЕЛЬНО ОТ ТЕКСТА, А НЕ ВПИСАН В НЕГО ПРОБЕЛАМИ.
        #
        # Раньше значок был первым символом надписи («   ▣   Игры»), и его
        # размер совпадал с размером текста — на глаз получалось мельче, чем
        # хотелось, а расстояние до текста «на глаз» пробелами у разных строк
        # расходилось на пиксель-два (разные символы разной ширины). Теперь
        # значок — свой слот фиксированной ширины с собственным, более
        # крупным шрифтом: одинаковый размер и одно и то же место у каждой
        # кнопки меню, а текст после него всегда начинается в одной точке.
        [string]$Icon,
        [double]$IconScale = 1.35,
        # Квадратная кнопка-иконка без подписи (▶ ✎ ■ в карточке аккаунта):
        # значок должен стоять по центру ВСЕЙ кнопки, а не в узком слоте
        # слева от текста, как в кнопках бокового меню. Раньше для таких
        # кнопок вообще не использовали -Icon, а клали символ псевдографики
        # прямо в -Text ('✎') — на мелком шрифте он не читался как гаечный
        # ключ/шестерёнка и выглядел как непонятная закорючка.
        [switch]$IconOnly,
        # Надпись по левому краю с полем — для пунктов бокового меню.
        [ValidateSet('center','left')][string]$Align = 'center'
    )

    $t = $Global:RamTheme

    # МЕРИМ ДО СОЗДАНИЯ.
    # Раньше кнопка расширялась под текст ПОСЛЕДНЕЙ строкой перед возвратом —
    # то есть уже после того, как вызывающий прикинул её размер, и прямо перед
    # тем, как он поставит соседа по жёсткой координате. При обычном шрифте это
    # почти не срабатывало, а при 125% и 150% надписи вырастали, кнопки лезли
    # друг на друга и вылезали за край панели. Теперь размер окончателен сразу.
    $pad  = if ($null -ne $t.M) { $t.M.BtnPadX } else { 26 }
    # Слот под значок — фиксированной ширины, от масштаба, но одинаковый у
    # ВСЕХ кнопок с значком: так их подписи выстраиваются в один столбец.
    $iconSlotW = 0
    $iconFont = $null
    if ($Icon) {
        $iconFont = New-Object System.Drawing.Font($t.FontBody.FontFamily, [single]($t.FontBody.Size * $IconScale), $t.FontBody.Style, $t.FontBody.Unit)
        $scaleForIcon = 1
        if ($null -ne $t.M) { $scaleForIcon = $t.M.Scale }
        $iconSlotW = [int][Math]::Round(28 * $scaleForIcon)
    }
    $need = (Measure-RamText -Text $Text -Font $t.FontBody).Width + $pad + $iconSlotW
    if ($Fixed) { $wantW = $Width } else { $wantW = [Math]::Max($Width, $need) }
    $colors = Get-RamButtonColors -Kind $Kind

    $btn = New-Object System.Windows.Forms.Panel
    $btn.Size      = New-Object System.Drawing.Size($wantW, $Height)
    $btn.BackColor = [System.Drawing.Color]::Transparent
    $btn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btn.Margin    = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    Set-RamDoubleBuffered $btn

    # Состояние храним прямо на элементе через Tag, чтобы обработчики были без замыканий.
    $btn.Tag = [pscustomobject]@{
        Font     = $t.FontBody
        Caption  = $Text
        Back     = $colors.Back
        Hover    = $colors.Hover
        Fore     = $colors.Fore
        Border   = $colors.Border
        Radius   = $Radius
        IsHover  = $false
        IsDown   = $false
        Enabled  = $true
        Icon     = $Icon
        IconFont = $iconFont
        IconSlotW = $iconSlotW
        IconOnly = [bool]$IconOnly
        Align    = $Align
        # Полоска цвета темы у левого края — признак активного пункта меню.
        ActiveBar = $false
    }

    $btn.Add_Paint({
        param($s, $e)
        $st = $s.Tag
        $g  = $e.Graphics
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        $path = New-RamRoundRect -Rect $rect -Radius $st.Radius

        $fill = if (-not $st.Enabled) { $Global:RamTheme.Panel }
                elseif ($st.IsDown)   { [System.Drawing.Color]::FromArgb(200, $st.Hover) }
                elseif ($st.IsHover)  { $st.Hover }
                else                  { $st.Back }

        $brush = New-Object System.Drawing.SolidBrush($fill)
        $g.FillPath($brush, $path)
        $brush.Dispose()

        if ($null -ne $st.Border) {
            $pen = New-Object System.Drawing.Pen($st.Border, 1)
            $g.DrawPath($pen, $path)
            $pen.Dispose()
        }
        $path.Dispose()

        $fore = if ($st.Enabled) { $st.Fore } else { $Global:RamTheme.Muted }

        if ($st.ActiveBar) {
            $sc = $Global:RamTheme.M.Scale
            $barW = [Math]::Max(2, [int][Math]::Round(3 * $sc))
            $barH = [int]($s.Height * 0.5)
            $barRect = New-Object System.Drawing.Rectangle(([int][Math]::Round(4 * $sc)), [int](($s.Height - $barH) / 2), $barW, $barH)
            $barPath = New-RamRoundRect -Rect $barRect -Radius ([Math]::Max(1, [int]($barW / 2)))
            $barBrush = New-Object System.Drawing.SolidBrush($Global:RamTheme.Accent)
            $g.FillPath($barBrush, $barPath)
            $barBrush.Dispose(); $barPath.Dispose()
        }

        # ЗНАЧОК — В СВОЁМ СЛОТЕ СЛЕВА, ТЕКСТ — ПОСЛЕ НЕГО.
        # У кнопки без значка (IconSlotW = 0) текст просто по центру, как и
        # было раньше — старое поведение не трогаем.
        #
        # IconOnly — отдельный случай: квадратная кнопка без подписи вообще
        # (▶ ⚙ ■ в карточке аккаунта). Значок здесь рисуется по центру ВСЕЙ
        # кнопки, а не в узком слоте слева от текста — слот уже, чем сама
        # кнопка, и значок съезжал бы влево вместо центра квадрата.
        if ($st.IconOnly -and (Test-RamGlyph -Name $st.Icon)) {
            $side = [single]([Math]::Min($s.Width, $s.Height) * 0.5)
            $gRect = New-Object System.Drawing.RectangleF(
                         ([single](($s.Width  - $side) / 2.0)),
                         ([single](($s.Height - $side) / 2.0)), $side, $side)
            Draw-RamGlyph -G $g -Name $st.Icon -Rect $gRect -Color $fore
            return
        }

        $textX = 2
        $textW = $s.Width - 4
        if ($st.IconSlotW -gt 0) {
            $iconRect = New-Object System.Drawing.RectangleF(
                            ([single]($st.IconSlotW * 0.18)), 0,
                            ([single]($st.IconSlotW * 0.82)), ([single]$s.Height))
            if (Test-RamGlyph -Name $st.Icon) {
                # Нарисованный значок: одна и та же толщина линии у всех
                # кнопок, никакой зависимости от того, есть ли символ в шрифте.
                $side = [single]([Math]::Min($iconRect.Width, $s.Height * 0.55))
                $gRect = New-Object System.Drawing.RectangleF(
                             ([single]($iconRect.X + ($iconRect.Width - $side) / 2.0)),
                             ([single](($s.Height - $side) / 2.0)), $side, $side)
                Draw-RamGlyph -G $g -Name $st.Icon -Rect $gRect -Color $fore
            } else {
                $sfIcon = New-Object System.Drawing.StringFormat
                $sfIcon.Alignment     = [System.Drawing.StringAlignment]::Center
                $sfIcon.LineAlignment = [System.Drawing.StringAlignment]::Center
                $ib = New-Object System.Drawing.SolidBrush($fore)
                $g.DrawString($st.Icon, $st.IconFont, $ib, $iconRect, $sfIcon)
                $ib.Dispose(); $sfIcon.Dispose()
            }
            $textX = [int]$st.IconSlotW
            $textW = $s.Width - [int]$st.IconSlotW - 4
        }

        # ТЕКСТ РИСУЕМ ТЕМ ЖЕ, ЧЕМ МЕРИЛИ. Ширину кнопки считает
        # Measure-RamText через TextRenderer (GDI). Раньше подпись рисовалась
        # Graphics.DrawString (GDI+) — у двух движков разные метрики, и на 150%
        # кнопка сама себе обрезала подпись многоточием, хотя место под неё
        # было посчитано. Со значком — по левому краю оставшегося места,
        # чтобы текст стоял на одном расстоянии от значка у любой длины.
        $flags = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                 [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
                 [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor
                 [System.Windows.Forms.TextFormatFlags]::NoPrefix
        if ($st.IconSlotW -gt 0) { $flags = $flags -bor [System.Windows.Forms.TextFormatFlags]::Left }
        elseif ([string]$st.Align -eq 'left') {
            $flags = $flags -bor [System.Windows.Forms.TextFormatFlags]::Left
            $textX = [int][Math]::Round(14 * $Global:RamTheme.M.Scale)
            $textW = $s.Width - $textX - 4
        }
        else                     { $flags = $flags -bor [System.Windows.Forms.TextFormatFlags]::HorizontalCenter }
        [System.Windows.Forms.TextRenderer]::DrawText(
            $g, [string]$st.Caption, $st.Font,
            (New-Object System.Drawing.Rectangle($textX, 0, [Math]::Max(1, $textW), $s.Height)),
            $fore, $flags)
    })

    $btn.Add_MouseEnter({ $this.Tag.IsHover = $true;  $this.Invalidate() })
    $btn.Add_MouseLeave({ $this.Tag.IsHover = $false; $this.Tag.IsDown = $false; $this.Invalidate() })
    $btn.Add_MouseDown( { $this.Tag.IsDown  = $true;  $this.Invalidate() })
    $btn.Add_MouseUp(   { $this.Tag.IsDown  = $false; $this.Invalidate() })

    # Договор с раскладчиком: он спрашивает Natural, чтобы отвести место,
    # и Fixed, чтобы понять, можно ли резать многоточием.
    $btn.Tag | Add-Member -NotePropertyName Kind    -NotePropertyValue 'button' -Force
    $btn.Tag | Add-Member -NotePropertyName Fixed   -NotePropertyValue ([bool]$Fixed) -Force
    $btn.Tag | Add-Member -NotePropertyName MinW    -NotePropertyValue $Width -Force
    $btn.Tag | Add-Member -NotePropertyName Natural -NotePropertyValue (New-Object System.Drawing.Size($wantW, $Height)) -Force

    if ($null -ne $OnClick) { $btn.Add_Click($OnClick) }

    if ($Tooltip) {
        $tt = New-Object System.Windows.Forms.ToolTip
        $tt.SetToolTip($btn, $Tooltip)
        $btn.Tag | Add-Member -NotePropertyName ToolTipOwner -NotePropertyValue $tt -Force
        $btn.Add_Disposed({ try { if ($null -ne $this.Tag.ToolTipOwner) { $this.Tag.ToolTipOwner.Dispose() } } catch { } })
    }

    return $btn
}

function Get-RamButtonColors {
    <# Цвета кнопки по её виду. Вынесено, чтобы вид можно было менять на лету
       (Set-RamButtonKind), а не только при создании. #>
    param([ValidateSet('primary','normal','danger','ghost')][string]$Kind = 'normal')

    $t = $Global:RamTheme
    switch ($Kind) {
        'primary' { @{ Back = $t.Accent;  Hover = $t.AccentHov; Fore = [System.Drawing.Color]::White; Border = $null } }
        'danger'  { @{ Back = $t.Danger;  Hover = $t.DangerHov; Fore = [System.Drawing.Color]::White; Border = $null } }
        'ghost'   { @{ Back = $t.Panel;   Hover = $t.CardHover; Fore = $t.Muted;                      Border = $t.Border } }
        default   { @{ Back = $t.Card;    Hover = $t.CardHover; Fore = $t.Text;                       Border = $t.Border } }
    }
}

function Set-RamButtonKind {
    <# Перекрасить уже созданную кнопку. Размер не трогаем: кнопка может быть
       привязана к краю окна, и рост вширь увёл бы её за экран. #>
    param($Button, [ValidateSet('primary','normal','danger','ghost')][string]$Kind)
    if ($null -eq $Button -or $null -eq $Button.Tag) { return }

    $c = Get-RamButtonColors -Kind $Kind
    $Button.Tag.Back   = $c.Back
    $Button.Tag.Hover  = $c.Hover
    $Button.Tag.Fore   = $c.Fore
    $Button.Tag.Border = $c.Border
    $Button.Invalidate()
}

function Set-RamButtonEnabled {
    <#
      Выключенная кнопка обязана быть выключенной ПО ДЕЛУ, а не только на вид.

      Раньше здесь менялся лишь цвет: обработчик Click оставался на месте, и
      серая кнопка прекрасно нажималась. Гасим саму панель — WinForms тогда
      не отдаёт ей ни щелчки, ни наведение мышью, а рисование по Paint
      продолжает работать, поэтому вид не портится.
    #>
    param($Button, [bool]$Enabled)
    if ($null -eq $Button -or $null -eq $Button.Tag) { return }
    $Button.Tag.Enabled = $Enabled
    $Button.Enabled = $Enabled
    if (-not $Enabled) { $Button.Tag.IsHover = $false; $Button.Tag.IsDown = $false }
    $Button.Cursor = if ($Enabled) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default }
    $Button.Invalidate()
}

function Set-RamButtonText {
    <#
      Меняет надпись и пересчитывает ширину.

      Если кнопка прибита к ПРАВОМУ краю, растём влево — иначе она уедет за
      край окна. Раньше ширину намеренно не трогали и надпись просто не
      влезала; отсюда была подпорка «поставим ширину с запасом под обе
      надписи», которая ломалась на крупном масштабе.
    #>
    param($Button, [string]$Text, [switch]$KeepWidth)
    if ($null -eq $Button -or $null -eq $Button.Tag) { return }
    $Button.Tag.Caption = $Text

    $t    = $Global:RamTheme
    $pad  = if ($null -ne $t.M) { $t.M.BtnPadX } else { 26 }
    $iconSlotW = 0
    if ($Button.Tag.PSObject.Properties.Name -contains 'IconSlotW') { $iconSlotW = [int]$Button.Tag.IconSlotW }
    $need = (Measure-RamText -Text $Text -Font $Button.Tag.Font).Width + $pad + $iconSlotW
    $Button.Tag.Natural = New-Object System.Drawing.Size($need, $Button.Height)

    $fixed = $false
    if ($Button.Tag.PSObject.Properties.Name -contains 'Fixed') { $fixed = [bool]$Button.Tag.Fixed }

    if (-not $KeepWidth -and -not $fixed) {
        $minW = $Button.Width
        if ($Button.Tag.PSObject.Properties.Name -contains 'MinW') { $minW = [int]$Button.Tag.MinW }
        $w = [Math]::Max($need, $minW)
        if ($w -ne $Button.Width) {
            $anchor   = $Button.Anchor
            $toRight  = (($anchor -band [System.Windows.Forms.AnchorStyles]::Right) -ne 0) -and
                        (($anchor -band [System.Windows.Forms.AnchorStyles]::Left) -eq 0)
            $wasRight = $Button.Right
            $Button.Width = $w
            if ($toRight) { $Button.Left = $wasRight - $w }
        }
    }
    $Button.Invalidate()
}

function New-RamLabel {
    param(
        [string]$Text,
        [int]$X, [int]$Y, [int]$Width, [int]$Height = 20,
        $Font,
        $Color,
        [string]$Align = 'left',
        # Свободный текст пользователя (имя аккаунта, заметка, название игры).
        # Такой не влезает по определению — для него многоточие это нормально,
        # и проверка вёрстки на него ругаться не должна.
        [switch]$Truncatable,
        # ФОН ПОД ПОДПИСЬЮ — СПЛОШНОЙ, А НЕ Transparent.
        #
        # BackColor = Transparent у System.Windows.Forms.Label не даёт
        # настоящей прозрачности: контрол одноразово копирует то, что было
        # под ним на момент отрисовки, вместо того чтобы каждый раз честно
        # брать актуальный фон родителя. На карточке аккаунта это давало
        # «второй фон» — старый, не смытый кусок кадра, который проступал
        # из-под подписи при живом ресайзе окна. Сплошная заливка того же
        # цвета, что у карточки под ней, убирает источник бага полностью:
        # заливать нечего кэшировать, GDI просто рисует прямоугольник перед
        # текстом на каждом кадре.
        # По умолчанию — цвет обычной карточки (берём из активной темы,
        # какая бы она ни была: Полночь, Изумруд, своя). Если подпись стоит
        # на другом фоне (например, на панели, а не на карточке), передать
        # его явно через -BackFill.
        $BackFill
    )
    $t = $Global:RamTheme
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $Text
    $l.Location  = New-Object System.Drawing.Point($X, $Y)
    $l.Size      = New-Object System.Drawing.Size($Width, $Height)
    $l.Font      = if ($null -ne $Font)  { $Font }  else { $t.FontBody }

    # Смайлики: либо рисуем настоящим шрифтом, либо вычищаем — как выбрано
    # в настройках. Переменной может ещё не быть (модуль подключают и отдельно),
    # тогда считаем, что показываем.
    if (Test-RamHasEmoji -Text $Text) {
        $show = $true
        if ($null -ne $Global:RamShowEmoji) { $show = [bool]$Global:RamShowEmoji }
        if ($show) { $l.Font = Get-RamEmojiFont -Like $l.Font }
        else       { $l.Text = Remove-RamEmoji -Text $Text }
    }
    $l.ForeColor = if ($null -ne $Color) { $Color } else { $t.Text }
    $l.BackColor = if ($null -ne $BackFill) { $BackFill } else { $t.Card }
    # Если текст всё-таки не влезает — многоточие вместо обрубленного слова.
    # Так обрезка хотя бы выглядит осмысленно, а не как сломанная вёрстка.
    $l.AutoEllipsis = $true
    # Tag хранит и признак «обрезаемый текст» (как раньше, читают по имени
    # свойства Truncatable), и, для сплошного фона, сам цвет заливки — чтобы
    # Sync-RamCardLabelFill мог найти и обновить его при смене состояния
    # карточки (выделение и т.п.).
    $l.Tag = [pscustomobject]@{ Truncatable = [bool]$Truncatable; Fill = $l.BackColor }

    # ПОДЛОЖКА БЕЗ -BackFill — ПО ТОМУ, КУДА ПОДПИСЬ ПОЛОЖИЛИ.
    # Сплошная заливка по умолчанию была цветом КАРТОЧКИ. Подписи вне карточек
    # (боковое меню, фон окна, нижняя строка) получали чужой цвет и выглядели
    # серыми прямоугольниками под текстом. Явно -BackFill не передавался нигде.
    # Теперь при попадании в контейнер подпись берёт его фон; на карточке —
    # цвет карточки (им дальше управляет Sync-RamCardLabelFill), потому что у
    # самой карточки BackColor — это фон окна под скруглёнными углами.
    if ($null -eq $BackFill) {
        $l.Add_ParentChanged({
            $node = $this.Parent
            $fill = $null
            while ($null -ne $node) {
                $tg = $node.Tag
                if ($null -ne $tg -and $tg.PSObject -and
                    ($tg.PSObject.Properties.Name -contains 'IsHover') -and
                    ($tg.PSObject.Properties.Name -contains 'Selected')) {
                    $fill = $Global:RamTheme.Card
                    break
                }
                if ($node.BackColor.A -eq 255) { $fill = $node.BackColor; break }
                $node = $node.Parent
            }
            if ($null -ne $fill) {
                $this.BackColor = $fill
                if ($null -ne $this.Tag -and ($this.Tag.PSObject.Properties.Name -contains 'Fill')) { $this.Tag.Fill = $fill }
            }
        })
    }
    $l.TextAlign = switch ($Align) {
        'right'  { [System.Drawing.ContentAlignment]::MiddleRight }
        'center' { [System.Drawing.ContentAlignment]::MiddleCenter }
        default  { [System.Drawing.ContentAlignment]::MiddleLeft }
    }
    return $l
}

function Mix-RamColor {
    <# Ручное альфа-смешение: имитирует наложение полупрозрачного Color
       (Overlay, с его собственным Alpha) поверх непрозрачного фона (Base).
       Нужно там, где сам контрол (Label, обычная заливка в Tag.Fill) не
       умеет рисовать настоящую полупрозрачность — только сплошной цвет —
       но результат должен визуально совпадать с тем, что происходит в
       Add_Paint карточки через FromArgb(alpha, Accent) поверх Graphics.
       Без этого фон карточки подсвечивался бы при перетаскивании, а фон
       текстовых подписей поверх него — нет, и получалось два разных
       фона под одной и той же карточкой. #>
    param([System.Drawing.Color]$Base, [System.Drawing.Color]$Overlay)
    $a = $Overlay.A / 255.0
    $r = [int]([Math]::Round($Overlay.R * $a + $Base.R * (1 - $a)))
    $g = [int]([Math]::Round($Overlay.G * $a + $Base.G * (1 - $a)))
    $b = [int]([Math]::Round($Overlay.B * $a + $Base.B * (1 - $a)))
    return [System.Drawing.Color]::FromArgb(255, $r, $g, $b)
}

function Sync-RamCardLabelFill {
    <#
      Перекрашивает фон всех подписей на карточке под её актуальный цвет
      (обычная / выделенная / цель перетаскивания), чтобы сплошной фон
      лейбла (см. New-RamLabel) не «отставал» от заливки карточки при
      смене состояния — иначе под текстом на миг виден прежний, более
      тёмный или светлый прямоугольник, то есть тот же самый эффект
      «второго фона», просто по другой причине.
      Зовать сразу после того, как поменяли $card.Tag.Selected/IsHover/
      DropLine и перед тем, как перерисовать карточку.
    #>
    param([Parameter(Mandatory)]$Card)
    $st = $Card.Tag
    $t  = $Global:RamTheme
    $fill = if ($st.Selected) { $t.CardSel } elseif ($st.IsHover) { $t.CardHover } else { $t.Card }
    # DropLine — карточка-цель при перетаскивании: та же полупрозрачная
    # подсветка, что Add_Paint карточки накладывает на СВОЙ фон поверх
    # $path (см. FromArgb(70, Accent) там) — здесь того же эффекта
    # приходится добиваться вручную (Mix-RamColor), потому что у
    # обычного Label фон не бывает по-настоящему полупрозрачным.
    if ($st.DropLine) {
        $fill = Mix-RamColor -Base $fill -Overlay ([System.Drawing.Color]::FromArgb(70, $t.Accent))
    }
    foreach ($c in $Card.Controls) {
        if ($c -is [System.Windows.Forms.Label]) {
            $c.BackColor = $fill
            if ($null -ne $c.Tag -and ($c.Tag.PSObject.Properties.Name -contains 'Fill')) {
                $c.Tag.Fill = $fill
            }
        } elseif ($null -ne $c.Tag -and ($c.Tag.PSObject.Properties.Name -contains 'Fill') -and
                  ($c.Tag.PSObject.Properties.Name -contains 'Caption')) {
            # Панель статуса (New-RamStatusDot) — своя заливка в Paint,
            # не BackColor контрола, поэтому обновляем через Tag.Fill.
            $c.Tag.Fill = $fill
            $c.Invalidate()
        }
    }
}

function New-RamTextBox {
    <# Тёмное поле ввода. У обычного TextBox нельзя убрать белую рамку,
       поэтому кладём его внутрь нарисованной панели. #>
    param(
        [int]$Width, [int]$Height = 32,
        [switch]$Multiline,
        [string]$Value = ''
    )
    $t = $Global:RamTheme

    $host_ = New-Object System.Windows.Forms.Panel
    $host_.Size      = New-Object System.Drawing.Size($Width, $Height)
    $host_.BackColor = [System.Drawing.Color]::Transparent
    Set-RamDoubleBuffered $host_

    $host_.Add_Paint({
        param($s, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        $path = New-RamRoundRect -Rect $rect -Radius 6
        $brush = New-Object System.Drawing.SolidBrush($Global:RamTheme.Bg)
        $e.Graphics.FillPath($brush, $path)
        $brush.Dispose()
        $pen = New-Object System.Drawing.Pen($Global:RamTheme.Border, 1)
        $e.Graphics.DrawPath($pen, $path)
        $pen.Dispose(); $path.Dispose()
    })

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.BorderStyle = 'None'
    $tb.BackColor   = $t.Bg
    $tb.ForeColor   = $t.Text
    $tb.Font        = $t.FontBody
    $tb.Text        = $Value
    if ($Multiline) {
        $tb.Multiline  = $true
        $tb.ScrollBars = 'Vertical'
        $tb.Location   = New-Object System.Drawing.Point(9, 7)
        $tb.Size       = New-Object System.Drawing.Size(($Width - 18), ($Height - 14))
        Set-RamScrollTheme -Control $tb
    } else {
        # ВАЖНО. У однострочного TextBox высоту задаёт ШРИФТ: заданные 17 px
        # он игнорирует. На крупном масштабе экрана поле становится выше своей
        # панели и вылезает за неё. Поэтому панель подтягиваем под факт.
        $tb.Size     = New-Object System.Drawing.Size(($Width - 18), 17)
        $needH = $tb.Height + 14
        if ($needH -gt $host_.Height) {
            $host_.Size = New-Object System.Drawing.Size($Width, $needH)
        }
        $tb.Location = New-Object System.Drawing.Point(9, [int](($host_.Height - $tb.Height) / 2))
    }
    # Поле лежит внутри нарисованной рамки с отступом. Если кликнуть по рамке,
    # а не точно по тексту, фокус никуда не встанет — и человек решит, что
    # «вставка не работает». Поэтому клик по рамке переводим на само поле.
    $host_.Cursor = [System.Windows.Forms.Cursors]::IBeam
    $host_.Add_Click({ $this.Tag.Focus() })

    # Ctrl+V / Ctrl+A / Ctrl+C / Ctrl+X в многострочном поле WinForms
    # по умолчанию не обрабатывает — добавляем сами.
    $tb.Add_KeyDown({
        param($sender, $e)
        if (-not $e.Control) { return }
        $handled = $true
        switch ($e.KeyCode) {
            'V' { if ([System.Windows.Forms.Clipboard]::ContainsText()) { $sender.Paste() } }
            'A' { $sender.SelectAll() }
            'C' { if ($sender.SelectedText) { [System.Windows.Forms.Clipboard]::SetText($sender.SelectedText) } }
            'X' { if ($sender.SelectedText) { [System.Windows.Forms.Clipboard]::SetText($sender.SelectedText); $sender.SelectedText = '' } }
            default { $handled = $false }
        }
        if ($handled) { $e.SuppressKeyPress = $true; $e.Handled = $true }
    })

    $host_.Controls.Add($tb)
    $host_.Tag = $tb          # доступ к самому полю: $panel.Tag.Text
    return $host_
}

function New-RamCard {
    <# Скруглённая карточка-подложка. Дочерние элементы кладём с прозрачным
       фоном — они будут видны поверх нарисованного скругления. #>
    param([int]$Width, [int]$Height, [int]$Radius = 10)

    $card = New-Object System.Windows.Forms.Panel
    $card.Size      = New-Object System.Drawing.Size($Width, $Height)
    # Фон СПЛОШНОЙ (цвет окна), а скруглённая плашка рисуется поверх в Paint.
    # Если сделать фон прозрачным, дочерние подписи с прозрачным фоном возьмут
    # цвет не карточки, а контейнера — и плашка под ними пропадёт.
    $card.BackColor = $Global:RamTheme.Bg
    $card.Margin    = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    Set-RamDoubleBuffered $card

    $card.Tag = [pscustomobject]@{
        Radius   = $Radius
        IsHover  = $false
        Selected = $false
        AccountId = ''
        DropLine = $null
    }

    $card.Add_Paint({
        param($s, $e)
        $st = $s.Tag
        $t  = $Global:RamTheme
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        $path = New-RamRoundRect -Rect $rect -Radius $st.Radius

        $fill = if ($st.Selected) { $t.CardSel } elseif ($st.IsHover) { $t.CardHover } else { $t.Card }
        $brush = New-Object System.Drawing.SolidBrush($fill)
        $e.Graphics.FillPath($brush, $path)
        $brush.Dispose()

        # УКАЗАТЕЛЬ МЕСТА ВСТАВКИ ПРИ ПЕРЕТАСКИВАНИИ.
        #
        # Раньше здесь рисовалась толстая акцентная черта у верхнего или
        # нижнего края карточки — видно, КУДА встанет схваченная карточка
        # при отпускании, но выглядело как техническая пометка «разрез
        # между слотами», а не как «вот эта карточка, с которой сейчас
        # поменяются местами». Теперь вместо черты подсвечивается вся
        # карточка-цель целиком — тем же акцентным цветом, что и у
        # схваченной карточки (см. Selected/CardSel выше), но заметно
        # слабее: сама схваченная карточка красится сплошным $t.CardSel,
        # а карточка под курсором — тем же оттенком с низкой
        # непрозрачностью, наложенным поверх её обычной заливки (ДО рамки
        # и до Dispose пути — path нужен ещё и здесь, и для рамки ниже).
        # Это читается как «эту карточку сейчас потеснят», а не просто как
        # линия-разделитель.
        if ($st.DropLine) {
            $overlay = [System.Drawing.Color]::FromArgb(70, $t.Accent)
            $ob = New-Object System.Drawing.SolidBrush($overlay)
            $e.Graphics.FillPath($ob, $path)
            $ob.Dispose()
        }

        $pen = New-Object System.Drawing.Pen($(if ($st.Selected) { $t.Accent } else { $t.Border }), 1)
        $e.Graphics.DrawPath($pen, $path)
        $pen.Dispose(); $path.Dispose()
    })

    return $card
}

function Get-RamGroupShort {
    <# Короткая подпись набора для тесных мест (под аватаркой на карточке
       аккаунта) — «Основной» -> «Основа», «Твины» -> «Твин». Сама группа
       ($a.Group) остаётся как есть везде, где по ней фильтруют или ищут
       (Get-RamVisibleAccounts, GroupFilter и т.д.) — это только то, что
       показываем человеку в самом тесном месте карточки. Любое другое,
       незнакомое имя набора (свои, пользовательские) остаётся как есть —
       сокращаем только эти два «встроенных» варианта. #>
    param([string]$Group)
    switch ($Group) {
        'Основной' { return 'Основа' }
        'Твины'    { return 'Твин' }
        default    { return $Group }
    }
}

function Get-RamStatusDotHeight {
    <#
      Высота панели статуса — от шрифта, а не числом. Раньше было 22 точки на
      статус и 10 на строку набора: строка набора была меньше самого шрифта уже
      на 100%, а на 150% название набора под «не запущен» обрезалось снизу.
    #>
    param([switch]$WithSuffix)
    $m = $Global:RamTheme.M
    $line = (Measure-RamText -Text 'Ay' -Font $Global:RamTheme.FontSmall).Height
    $main = [Math]::Max([int][Math]::Round(22 * $m.Scale), $line + [int][Math]::Round(4 * $m.Scale))
    if ($WithSuffix) { return $main + $line }
    return $main
}

function New-RamStatusDot {
    <#
      Цветной кружок статуса + подпись.

      -NoDot переключает в режим подписи под аватаркой: сама рамка аватарки
      уже красится в цвет статуса (см. Set-RamStatusDot -Avatar), поэтому
      здесь кружок лишний — только центрированный цветной текст на всю
      ширину.

      -GroupSuffix — короткая метка набора («Основа»/«Твин», см.
      Get-RamGroupShort), рисуется ВТОРОЙ СТРОКОЙ под статусом, а не в
      одну строку с ним через « · ». Раньше и то и другое пробовали
      уместить в одну строку («не запущен · Твин») — на панели шириной
      с аватарку это тут же обрезалось многоточием, и даже сам статус
      («не запущен»), который раньше всегда влезал целиком, стал
      обрезаться из-за добавленного хвоста. Метка меняется только при
      пересборке карточки (Build-RamCards), а не по таймеру состояния —
      в отличие от Caption/Color, которые обновляет Set-RamStatusDot
      каждые пару секунд.
    #>
    param([int]$X, [int]$Y, [int]$Width = 150, [switch]$NoDot, [switch]$Center, $BackFill, [string]$GroupSuffix)

    $hasSuffix = -not [string]::IsNullOrWhiteSpace($GroupSuffix)
    # Первая строка (статус) держит СВОЮ прежнюю высоту (22px) — её
    # позиция и размер не меняются в зависимости от GroupSuffix, иначе сам
    # статус («не запущен») сдвигается с привычного места и норовит
    # обрезаться под аватаркой (см. комментарий у вызова в UiMain.ps1).
    # Вторая строка — чистая прибавка ВНИЗ поверх этих 22px, а не замена
    # части их высоты. Сделана короче первой (12 против 22) — под ней всё
    # ещё есть небольшой запас до низа карточки (см. Get-RamCardHeight),
    # а не вплотную 0px.
    $rowH = if ($hasSuffix) { (Measure-RamText -Text 'Ay' -Font $Global:RamTheme.FontSmall).Height } else { 0 }
    $totalH = Get-RamStatusDotHeight -WithSuffix:$hasSuffix

    $p = New-Object System.Windows.Forms.Panel
    $p.Location  = New-Object System.Drawing.Point($X, $Y)
    $p.Size      = New-Object System.Drawing.Size($Width, $totalH)
    # Тот же случай, что у New-RamLabel: Transparent здесь не настоящая
    # прозрачность, а кэш кадра на момент отрисовки — на карточке аккаунта
    # это давало «второй фон», не смытый остаток кадра под подписью статуса
    # при живом ресайзе. Заливаем сами, сплошным цветом карточки, перед тем
    # как рисовать точку и текст — тогда кэшировать нечего.
    $p.BackColor = [System.Drawing.Color]::Transparent
    $fillNow = if ($null -ne $BackFill) { $BackFill } else { $Global:RamTheme.Card }
    $p.Tag = [pscustomobject]@{ Caption = 'не запущен'; Color = $Global:RamTheme.Muted; NoDot = [bool]$NoDot; Center = [bool]$Center; Fill = $fillNow; GroupSuffix = $GroupSuffix; RowH = $rowH }
    Set-RamDoubleBuffered $p

    $p.Add_Paint({
        param($s, $e)
        $st = $s.Tag
        $g = $e.Graphics
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $fb = New-Object System.Drawing.SolidBrush($st.Fill)
        $g.FillRectangle($fb, 0, 0, $s.Width, $s.Height)
        $fb.Dispose()

        $hasSuffix = -not [string]::IsNullOrWhiteSpace($st.GroupSuffix)
        $statusH = if ($hasSuffix) { $s.Height - $st.RowH } else { $s.Height }

        $textX = 0; $textW = $s.Width
        if (-not $st.NoDot) {
            # Кружок и отступ подписи — от масштаба: раньше 8×8 в точке (0, 7)
            # и 14 точек отступа на любом экране, и на 150% крошечный кружок
            # висел выше середины выросшей строки.
            $sc = $Global:RamTheme.M.Scale
            $d = [int][Math]::Round(8 * $sc)
            $b = New-Object System.Drawing.SolidBrush($st.Color)
            $g.FillEllipse($b, 0, [int](($statusH - $d) / 2), $d, $d)
            $b.Dispose()
            $textX = [int][Math]::Round(14 * $sc); $textW = $s.Width - $textX
        }

        $sf = New-Object System.Drawing.StringFormat
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        if ($st.Center) { $sf.Alignment = [System.Drawing.StringAlignment]::Center }
        # Без NoWrap длинные подписи ("Выключение...") переносились на вторую
        # строку и обрезались снизу — панель под статус высотой всего 22px.
        # NoWrap + EllipsisCharacter держит подпись в одну строку, обрезая
        # многоточием, если совсем не влезает, вместо переноса.
        $sf.FormatFlags     = [System.Drawing.StringFormatFlags]::NoWrap
        $sf.Trimming        = [System.Drawing.StringTrimming]::EllipsisCharacter

        $tb = New-Object System.Drawing.SolidBrush($st.Color)
        $g.DrawString($st.Caption, $Global:RamTheme.FontSmall, $tb,
                      (New-Object System.Drawing.RectangleF($textX, 0, $textW, $statusH)), $sf)
        $tb.Dispose()

        if ($hasSuffix) {
            $gb = New-Object System.Drawing.SolidBrush($Global:RamTheme.Accent)
            $g.DrawString($st.GroupSuffix, $Global:RamTheme.FontSmall, $gb,
                          (New-Object System.Drawing.RectangleF($textX, $statusH, $textW, $st.RowH)), $sf)
            $gb.Dispose()
        }

        $sf.Dispose()
    })

    return $p
}

function Set-RamStatusDot {
    <#
      Перерисовываем ТОЛЬКО при смене подписи или цвета.

      Раньше Invalidate() звался безусловно, а зовут эту функцию по каждому
      аккаунту каждые две секунды из таймера. На двадцати аккаунтах это
      двадцать принудительных перерисовок GDI+ в секунду при совершенно
      неподвижной картинке — программа грела процессор, ничего не делая.

      -Avatar необязателен: если передан, рамка аватарки красится в тот же
      цвет, что и статус (у Set-RamAvatarBorderColor своя проверка "цвет не
      поменялся" — лишней перерисовки от этого не прибавляется).
    #>
    param($Dot, [string]$Caption, $Color, $Avatar)
    if ($null -ne $Avatar) { Set-RamAvatarBorderColor -Box $Avatar -Color $Color }

    if ($null -eq $Dot) { return }

    $sameText  = ([string]$Dot.Tag.Caption -eq [string]$Caption)
    $sameColor = ($null -ne $Dot.Tag.Color -and $null -ne $Color -and
                  $Dot.Tag.Color.ToArgb() -eq $Color.ToArgb())
    if ($sameText -and $sameColor) { return }

    $Dot.Tag.Caption = $Caption
    $Dot.Tag.Color   = $Color
    $Dot.Invalidate()
}

function New-RamAvatarBox {
    <# Круглая аватарка с заглушкой, пока картинка не загрузилась. #>
    param([int]$Size = 52)

    $p = New-Object System.Windows.Forms.Panel
    $p.Size      = New-Object System.Drawing.Size($Size, $Size)
    $p.BackColor = [System.Drawing.Color]::Transparent
    # BorderColor красится в цвет статуса через Set-RamAvatarBorderColor.
    # По умолчанию — нейтральная обводка темы: в классическом виде меню
    # рамка не должна становиться цветной сама по себе.
    $p.Tag = [pscustomobject]@{ Image = $null; Letter = '?'; BorderColor = $Global:RamTheme.Border }
    Set-RamDoubleBuffered $p

    $p.Add_Paint({
        param($s, $e)
        $st = $s.Tag
        $g = $e.Graphics
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddEllipse($rect)

        if ($null -ne $st.Image) {
            $state = $g.Save()
            try {
                $g.SetClip($path)
                $g.DrawImage($st.Image, $rect)
            } finally {
                $g.Restore($state)
            }
        } else {
            $b = New-Object System.Drawing.SolidBrush($Global:RamTheme.Panel)
            $g.FillPath($b, $path)
            $b.Dispose()

            $tb = New-Object System.Drawing.SolidBrush($Global:RamTheme.Muted)
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment     = [System.Drawing.StringAlignment]::Center
            $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
            $g.DrawString($st.Letter, $Global:RamTheme.FontTitle, $tb,
                          (New-Object System.Drawing.RectangleF(0, 0, $s.Width, $s.Height)), $sf)
            $tb.Dispose(); $sf.Dispose()
        }

        # Рамка — индикатор состояния аккаунта, ей нужно быть заметной: две
        # точки на 100%, три на 150%. Раньше это было фиксированные 2 пикселя,
        # которые на крупном масштабе снова становились волоском.
        $borderColor = if ($null -ne $st.BorderColor) { $st.BorderColor } else { $Global:RamTheme.Border }
        $pen = New-Object System.Drawing.Pen($borderColor, [single][Math]::Max(1, [Math]::Round(2 * $Global:RamTheme.M.Scale)))
        $g.DrawPath($pen, $path)
        $pen.Dispose(); $path.Dispose()
    })

    return $p
}

function Set-RamAvatarImage {
    param($Box, $Image, [string]$Letter)
    if ($null -eq $Box) { return }
    if ($null -ne $Image)  { $Box.Tag.Image  = $Image }
    if ($Letter)           { $Box.Tag.Letter = $Letter.Substring(0,1).ToUpper() }
    $Box.Invalidate()
}

function Set-RamAvatarBorderColor {
    <# Красит рамку аватарки в цвет статуса. Перерисовываем только при
       смене цвета — этот вызов идёт из того же цикла таймера, что и
       Set-RamStatusDot, по каждому аккаунту. #>
    param($Box, $Color)
    if ($null -eq $Box -or $null -eq $Color) { return }

    $same = ($null -ne $Box.Tag.BorderColor -and $Box.Tag.BorderColor.ToArgb() -eq $Color.ToArgb())
    if ($same) { return }

    $Box.Tag.BorderColor = $Color
    $Box.Invalidate()
}

# ------------------------------------------------------ всплывающее меню ----
#
# WinForms рисует ContextMenuStrip системными цветами: в тёмной теме это белый
# прямоугольник посреди тёмного окна. Настройки цветов у него нет — только
# подмена таблицы цветов целиком. Отсюда этот маленький класс.

@'
using System.Drawing;
using System.Windows.Forms;

public class RamMenuColors : ProfessionalColorTable
{
    public static Color Back   = Color.FromArgb(39, 43, 51);
    public static Color Hover  = Color.FromArgb(48, 53, 62);
    public static Color Border = Color.FromArgb(58, 62, 74);

    public override Color ToolStripDropDownBackground   { get { return Back;   } }
    public override Color MenuItemSelected              { get { return Hover;  } }
    public override Color MenuItemSelectedGradientBegin { get { return Hover;  } }
    public override Color MenuItemSelectedGradientEnd   { get { return Hover;  } }
    public override Color MenuItemBorder                { get { return Hover;  } }
    public override Color MenuBorder                    { get { return Border; } }
    public override Color ImageMarginGradientBegin      { get { return Back;   } }
    public override Color ImageMarginGradientMiddle     { get { return Back;   } }
    public override Color ImageMarginGradientEnd        { get { return Back;   } }
    public override Color SeparatorDark                 { get { return Border; } }
    public override Color SeparatorLight                { get { return Border; } }
}
'@ | ForEach-Object {
    Add-Type -TypeDefinition $_ -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' -ErrorAction SilentlyContinue
}

function New-RamContextMenu {
    <# Пустое меню в цветах текущей темы. Пункты добавляет Add-RamMenuItem. #>
    $t = $Global:RamTheme

    # Цвета статические: тема одна на всю программу, а меню создаётся часто.
    try {
        [RamMenuColors]::Back   = $t.Card
        [RamMenuColors]::Hover  = $t.CardHover
        [RamMenuColors]::Border = $t.Border
    } catch { }

    $m = New-Object System.Windows.Forms.ContextMenuStrip
    $m.ShowImageMargin = $false
    $m.BackColor       = $t.Card
    $m.ForeColor       = $t.Text
    $m.Font            = $t.FontBody
    try {
        $m.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer((New-Object RamMenuColors))
    } catch { }
    return $m
}

function Add-RamMenuItem {
    <#
      Пункт меню.

      Tag обязателен там, где меню строится в цикле по аккаунтам: замыкание
      запомнило бы последний аккаунт цикла, а $this.Tag внутри обработчика —
      именно свой. Те же грабли уже ловили на кнопках карточек.
    #>
    param(
        [Parameter(Mandatory)]$Menu,
        [string]$Text,
        [scriptblock]$OnClick,
        $Tag,
        $Color,
        [switch]$Separator,
        [switch]$Disabled
    )

    if ($Separator) {
        [void]$Menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        return $null
    }

    $it = New-Object System.Windows.Forms.ToolStripMenuItem
    $it.Text = $Text
    $it.Tag  = $Tag

    if ($Disabled) {
        $it.Enabled   = $false
        $it.ForeColor = $Global:RamTheme.Muted
    } else {
        $it.ForeColor = if ($null -ne $Color) { $Color } else { $Global:RamTheme.Text }
        if ($null -ne $OnClick) { $it.Add_Click($OnClick) }
    }

    [void]$Menu.Items.Add($it)
    return $it
}

function New-RamCheckBox {
    <# Тёмная галочка, нарисованная вручную. Растёт вместе со шрифтом:
       иначе при крупном масштабе экрана она выглядит крошечной рядом
       с подписью. #>
    param([int]$X, [int]$Y)

    $sc = 1.0
    if ($null -ne $Global:RamTheme.M) { $sc = [double]$Global:RamTheme.M.Scale }
    $side = [int][Math]::Round(20 * $sc)

    $c = New-Object System.Windows.Forms.Panel
    $c.Location  = New-Object System.Drawing.Point($X, $Y)
    $c.Size      = New-Object System.Drawing.Size($side, $side)
    $c.BackColor = [System.Drawing.Color]::Transparent
    $c.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $c.Tag       = [pscustomobject]@{ Checked = $false }
    Set-RamDoubleBuffered $c

    $c.Add_Paint({
        param($s, $e)
        $t = $Global:RamTheme
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        # Рисунок задан в координатах 20x20 — растягиваем его под текущий
        # размер, чтобы не переписывать все числа ниже.
        $k = $s.Width / 20.0
        if ($k -ne 1.0) { $g.ScaleTransform($k, $k) }

        $rect = New-Object System.Drawing.Rectangle(1, 1, 17, 17)
        $path = New-RamRoundRect -Rect $rect -Radius 5

        if ($s.Tag.Checked) {
            $b = New-Object System.Drawing.SolidBrush($t.Accent)
            $g.FillPath($b, $path); $b.Dispose()
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
            $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
            $g.DrawLines($pen, @(
                (New-Object System.Drawing.Point(5, 9)),
                (New-Object System.Drawing.Point(8, 12)),
                (New-Object System.Drawing.Point(14, 6))
            ))
            $pen.Dispose()
        } else {
            $pen = New-Object System.Drawing.Pen($t.Muted, 1.5)
            $g.DrawPath($pen, $path); $pen.Dispose()
        }
        $path.Dispose()
    })

    $c.Add_Click({ $this.Tag.Checked = -not $this.Tag.Checked; $this.Invalidate() })
    return $c
}

function New-RamScrollPanel {
    <# Контейнер со скроллом под карточки. #>
    param([int]$Width, [int]$Height)
    $fp = New-Object System.Windows.Forms.FlowLayoutPanel
    $fp.Size          = New-Object System.Drawing.Size($Width, $Height)
    $fp.BackColor     = $Global:RamTheme.Bg
    $fp.FlowDirection = 'TopDown'
    $fp.WrapContents  = $false
    $fp.AutoScroll    = $true
    $fp.Padding       = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
    Set-RamDoubleBuffered $fp
    Set-RamScrollTheme -Control $fp
    return $fp
}
