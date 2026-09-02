#requires -Version 5.1
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
        BtnPadX  = & $k 34
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
        return [System.Windows.Forms.TextRenderer]::MeasureText(
            $Text, $Font,
            (New-Object System.Drawing.Size($MaxWidth, 4000)),
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

function Set-RamTheme {
    <# Ставит палитру и добавляет к ней шрифты — шрифты общие для всех тем. #>
    param([string]$Name = 'dark')

    # Если тема не нашлась (например, файл настроек ссылается на удалённую
    # свою тему) — откатываемся на тёмную, а не падаем.
    $known = @(Get-RamThemeList | ForEach-Object { $_.Key })
    if ($known -notcontains $Name) { $Name = 'dark' }
    $p = Get-RamPalette -Name $Name

    # Шрифты заданы в ПУНКТАХ, поэтому на настоящем экране 150% они уже
    # крупнее сами по себе — умножать не надо. А вот когда Самопроверка
    # притворяется, что масштаб 150% на обычном экране, умножить необходимо,
    # иначе эффект просто не воспроизведётся.
    $fs = 1.0
    if ($null -ne $Global:RamForceScale) { $fs = [double]$Global:RamForceScale }

    $p.FontBig   = New-Object System.Drawing.Font('Segoe UI Semibold', (15  * $fs))
    $p.FontTitle = New-Object System.Drawing.Font('Segoe UI Semibold', (11  * $fs))
    $p.FontBody  = New-Object System.Drawing.Font('Segoe UI',          (9.5 * $fs))
    $p.FontSmall = New-Object System.Drawing.Font('Segoe UI',          (8.5 * $fs))
    $p.FontMono  = New-Object System.Drawing.Font('Consolas',          (9   * $fs))

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

    $key = '{0}|{1}' -f $Like.Size, [int]$Like.Style
    if ($script:RamEmojiFonts.ContainsKey($key)) { return $script:RamEmojiFonts[$key] }

    try {
        $f = New-Object System.Drawing.Font('Segoe UI Emoji', $Like.Size, $Like.Style)
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

function New-RamButton {
    <#
      Кнопка на основе Panel: рисуем сами, чтобы получить тёмный фон,
      скруглённые углы и нормальное наведение мышью.

      Kind: primary | normal | danger | ghost
    #>
    param(
        [Parameter(Mandatory)][string]$Text,
        # ЭТО МИНИМУМ, а не обещание: если надпись длиннее, кнопка будет шире.
        [int]$Width  = 150,
        [int]$Height = 34,
        [ValidateSet('primary','normal','danger','ghost')][string]$Kind = 'normal',
        [scriptblock]$OnClick,
        [string]$Tooltip,
        [int]$Radius = 7,
        # Не подгонять под текст: ширина ровно такая, как просили, длинное
        # обрезать многоточием. Нужно там, где кнопка прибита к краю окна.
        [switch]$Fixed
    )

    $t = $Global:RamTheme

    # МЕРИМ ДО СОЗДАНИЯ.
    # Раньше кнопка расширялась под текст ПОСЛЕДНЕЙ строкой перед возвратом —
    # то есть уже после того, как вызывающий прикинул её размер, и прямо перед
    # тем, как он поставит соседа по жёсткой координате. При обычном шрифте это
    # почти не срабатывало, а при 125% и 150% надписи вырастали, кнопки лезли
    # друг на друга и вылезали за край панели. Теперь размер окончателен сразу.
    $pad  = if ($null -ne $t.M) { $t.M.BtnPadX } else { 26 }
    $need = (Measure-RamText -Text $Text -Font $t.FontBody).Width + $pad
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
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment     = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        # Без NoWrap длинная надпись переносится на вторую строку и обрезается
        # по высоте — выглядит как «текст немного обрезан».
        $sf.FormatFlags   = [System.Drawing.StringFormatFlags]::NoWrap
        $sf.Trimming      = [System.Drawing.StringTrimming]::EllipsisCharacter

        $tb = New-Object System.Drawing.SolidBrush($fore)
        $g.DrawString($st.Caption, $st.Font, $tb,
                      (New-Object System.Drawing.RectangleF(2, 0, ($s.Width - 4), $s.Height)), $sf)
        $tb.Dispose(); $sf.Dispose()
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
    $need = (Measure-RamText -Text $Text -Font $Button.Tag.Font).Width + $pad
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
        [switch]$Truncatable
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
    $l.BackColor = [System.Drawing.Color]::Transparent
    # Если текст всё-таки не влезает — многоточие вместо обрубленного слова.
    # Так обрезка хотя бы выглядит осмысленно, а не как сломанная вёрстка.
    $l.AutoEllipsis = $true
    if ($Truncatable) { $l.Tag = 'truncatable' }
    $l.TextAlign = switch ($Align) {
        'right'  { [System.Drawing.ContentAlignment]::MiddleRight }
        'center' { [System.Drawing.ContentAlignment]::MiddleCenter }
        default  { [System.Drawing.ContentAlignment]::MiddleLeft }
    }
    return $l
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

        $pen = New-Object System.Drawing.Pen($(if ($st.Selected) { $t.Accent } else { $t.Border }), 1)
        $e.Graphics.DrawPath($pen, $path)
        $pen.Dispose(); $path.Dispose()
    })

    return $card
}

function New-RamStatusDot {
    <# Цветной кружок статуса + подпись. #>
    param([int]$X, [int]$Y, [int]$Width = 150)

    $p = New-Object System.Windows.Forms.Panel
    $p.Location  = New-Object System.Drawing.Point($X, $Y)
    $p.Size      = New-Object System.Drawing.Size($Width, 22)
    $p.BackColor = [System.Drawing.Color]::Transparent
    $p.Tag = [pscustomobject]@{ Caption = 'не запущен'; Color = $Global:RamTheme.Muted }
    Set-RamDoubleBuffered $p

    $p.Add_Paint({
        param($s, $e)
        $st = $s.Tag
        $g = $e.Graphics
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $b = New-Object System.Drawing.SolidBrush($st.Color)
        $g.FillEllipse($b, 0, 7, 8, 8)
        $b.Dispose()

        $tb = New-Object System.Drawing.SolidBrush($st.Color)
        $sf = New-Object System.Drawing.StringFormat
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $g.DrawString($st.Caption, $Global:RamTheme.FontSmall, $tb,
                      (New-Object System.Drawing.RectangleF(14, 0, ($s.Width - 14), $s.Height)), $sf)
        $tb.Dispose(); $sf.Dispose()
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
    #>
    param($Dot, [string]$Caption, $Color)
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
    $p.Tag = [pscustomobject]@{ Image = $null; Letter = '?' }
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
            $old = $g.Clip
            $g.SetClip($path)
            $g.DrawImage($st.Image, $rect)
            $g.Clip = $old
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

        $pen = New-Object System.Drawing.Pen($Global:RamTheme.Border, 1)
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
    return $fp
}
