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

function Get-RamPalette {
    param([ValidateSet('dark','midnight','light')][string]$Name = 'dark')

    $c = { param($r, $g, $b) [System.Drawing.Color]::FromArgb($r, $g, $b) }

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

function Get-RamThemeList {
    @(
        [pscustomobject]@{ Key = 'dark';     Title = 'Тёмная'  },
        [pscustomobject]@{ Key = 'midnight'; Title = 'Полночь' },
        [pscustomobject]@{ Key = 'light';    Title = 'Светлая' }
    )
}

function Set-RamTheme {
    <# Ставит палитру и добавляет к ней шрифты — шрифты общие для всех тем. #>
    param([string]$Name = 'dark')

    if (@('dark','midnight','light') -notcontains $Name) { $Name = 'dark' }
    $p = Get-RamPalette -Name $Name

    $p.FontBig   = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $p.FontTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $p.FontBody  = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $p.FontSmall = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $p.FontMono  = New-Object System.Drawing.Font('Consolas', 9)

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
        [int]$Width  = 150,
        [int]$Height = 34,
        [ValidateSet('primary','normal','danger','ghost')][string]$Kind = 'normal',
        [scriptblock]$OnClick,
        [string]$Tooltip,
        [int]$Radius = 7
    )

    $t = $Global:RamTheme
    $colors = Get-RamButtonColors -Kind $Kind

    $btn = New-Object System.Windows.Forms.Panel
    $btn.Size      = New-Object System.Drawing.Size($Width, $Height)
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

    # Если надпись не влезает в заданную ширину — расширяем кнопку. Ширины
    # проставлены на глаз, а длина слов зависит от языка и от масштаба экрана,
    # поэтому надёжнее померить и подвинуть, чем надеяться.
    $need = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $t.FontBody).Width + 26
    if ($need -gt $btn.Width) { $btn.Width = $need }

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
    param($Button, [bool]$Enabled)
    if ($null -eq $Button -or $null -eq $Button.Tag) { return }
    $Button.Tag.Enabled = $Enabled
    $Button.Cursor = if ($Enabled) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default }
    $Button.Invalidate()
}

function Set-RamButtonText {
    param($Button, [string]$Text)
    if ($null -eq $Button -or $null -eq $Button.Tag) { return }
    $Button.Tag.Caption = $Text
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
        $tb.Location = New-Object System.Drawing.Point(9, [int](($Height - 17) / 2))
        $tb.Size     = New-Object System.Drawing.Size(($Width - 18), 17)
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
    param($Dot, [string]$Caption, $Color)
    if ($null -eq $Dot) { return }
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
    <# Тёмная галочка, нарисованная вручную. #>
    param([int]$X, [int]$Y)

    $c = New-Object System.Windows.Forms.Panel
    $c.Location  = New-Object System.Drawing.Point($X, $Y)
    $c.Size      = New-Object System.Drawing.Size(20, 20)
    $c.BackColor = [System.Drawing.Color]::Transparent
    $c.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $c.Tag       = [pscustomobject]@{ Checked = $false }
    Set-RamDoubleBuffered $c

    $c.Add_Paint({
        param($s, $e)
        $t = $Global:RamTheme
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

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
