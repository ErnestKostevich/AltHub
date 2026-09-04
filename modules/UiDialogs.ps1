#requires -Version 5.1
<#
================================================================================
 modules\UiDialogs.ps1 — все диалоговые окна
================================================================================
 Сообщения, ввод, пароль, мастера добавления аккаунтов, окно аккаунта,
 конструктор тем и настройки.

 В сеть отсюда ничего не ходит напрямую: за это отвечает RobloxApi.ps1.
================================================================================
#>

# ------------------------------------------------------ тёмные диалоги ------

function Get-RamDialogButtonWidth {
    <# Ширина кнопки диалога под её надпись. Отдельно, чтобы ширину окна и
       ширину самих кнопок считало одно и то же место. #>
    param([Parameter(Mandatory)][string]$Text)
    # Тот же отступ, что и в New-RamButton, иначе на крупном масштабе расчёт
    # ширины окна и фактическая ширина кнопок расходятся, и они налезают.
    $pad = if ($null -ne $Global:RamTheme.M) { $Global:RamTheme.M.BtnPadX } else { 34 }
    return (Measure-RamText -Text $Text -Font $Global:RamTheme.FontBody).Width + $pad
}

function Add-RamDialogButtons {
    <#
      Ряд кнопок внизу диалога. Выкладываем справа налево, поэтому идём по
      списку с конца: первая кнопка в списке оказывается самой левой, как её
      и описали.

      Вынесено из Show-RamMessage отдельной функцией по двум причинам.
      Во-первых, так ряд можно проверить, не показывая окно. Во-вторых — и это
      важнее — здесь НЕТ параметра $Kind.

      ГРАБЛИ POWERSHELL. Имена переменных регистронезависимы. Внутри
      Show-RamMessage есть параметр $Kind с ValidateSet('info','ok','warn',
      'error'), и локальная строчка «$kind = 'normal'» писала именно в него.
      ValidateSet проверяется при КАЖДОМ присваивании, а не только при
      разборе аргументов, — поэтому окно падало с необрабатываемым
      исключением, а не просто вело себя странно.
    #>
    param(
        [Parameter(Mandatory)]$Dialog,
        [Parameter(Mandatory)][object[]]$Buttons,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Width
    )

    $made = @()
    $x = $Width - 24

    for ($i = $Buttons.Count - 1; $i -ge 0; $i--) {
        $b     = $Buttons[$i]
        $bKind = if ($b.Kind) { [string]$b.Kind } else { 'normal' }
        $minW  = if ($null -ne $Global:RamTheme.M) { $Global:RamTheme.M.BtnMinW } else { 110 }
        $bw    = [Math]::Max($minW, (Get-RamDialogButtonWidth -Text $b.Text))

        $btn = New-RamButton -Text $b.Text -Width $bw -Height 34 -Kind $bKind -OnClick {
            $f = $this.FindForm()
            $f.Tag = $this.Tag.Value
            $f.Close()
        }
        $btn.Tag | Add-Member -NotePropertyName Value -NotePropertyValue $b.Value -Force

        $x -= $bw
        $btn.Location = New-Object System.Drawing.Point($x, $Y)
        $x -= 8
        $Dialog.Controls.Add($btn)
        $made += $btn
    }

    return @($made)
}

function Show-RamMessage {
    <#
      Тёмное окно сообщения вместо системного MessageBox — тот всегда белый
      и выбивается из оформления.
      С -YesNo возвращает $true/$false, иначе $null.
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'AltHub',
        [ValidateSet('info','ok','warn','error')][string]$Kind = 'info',
        [switch]$YesNo,
        # Свой набор кнопок: массив @{ Text; Value; Kind }. Возвращает Value
        # нажатой кнопки, а при закрытии окна крестиком — $null.
        [object[]]$Buttons = @(),
        # Только для Самопроверки: собрать окно и вернуть, не показывая.
        [switch]$BuildOnly
    )

    $t = $Global:RamTheme
    $accent = switch ($Kind) {
        'ok'    { $t.Ok }
        'warn'  { $t.Warn }
        'error' { $t.Danger }
        default { $t.Accent }
    }

    $width = 480

    # Со своим набором кнопок окно расширяем под них, иначе крайняя уедет
    # за край — на четырёх кнопках это заметно.
    if ($Buttons.Count -gt 0) {
        $need = 48
        $minW = if ($null -ne $Global:RamTheme.M) { $Global:RamTheme.M.BtnMinW } else { 110 }
        foreach ($b in $Buttons) { $need += [Math]::Max($minW, (Get-RamDialogButtonWidth -Text $b.Text)) + 8 }
        if ($need -gt $width) { $width = $need }
    }

    $textW = $width - 48
    $size  = [System.Windows.Forms.TextRenderer]::MeasureText(
                $Message, $t.FontBody,
                (New-Object System.Drawing.Size($textW, 1000)),
                [System.Windows.Forms.TextFormatFlags]::WordBreak)
    $textH = [Math]::Max(40, [Math]::Min(420, $size.Height + 8))

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = $Title
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.ForeColor       = $t.Text
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size($width, (76 + $textH + 56))

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Location  = New-Object System.Drawing.Point(0, 0)
    $stripe.Size      = New-Object System.Drawing.Size($width, 4)
    $stripe.BackColor = $accent
    $dlg.Controls.Add($stripe)

    $dlg.Controls.Add((New-RamLabel -Text $Title -X 24 -Y 22 -Width ($width - 48) -Height 28 `
                                    -Font $t.FontTitle -Color $t.Text))

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = $Message
    $lbl.Location  = New-Object System.Drawing.Point(24, 60)
    $lbl.Size      = New-Object System.Drawing.Size($textW, $textH)
    $lbl.Font      = $t.FontBody
    $lbl.ForeColor = $t.Text
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $dlg.Controls.Add($lbl)

    $btnY = 70 + $textH
    $result = $null

    if ($Buttons.Count -gt 0) {
        [void](Add-RamDialogButtons -Dialog $dlg -Buttons $Buttons -Y $btnY -Width $width)
        $dlg.Tag = $null
    } elseif ($YesNo) {
        $yes = New-RamButton -Text 'Да' -Width 110 -Height 34 -Kind 'primary' -OnClick {
            $this.FindForm().Tag = $true
            $this.FindForm().Close()
        }
        $yesW = (Measure-RamControl -Control $yes).Width
        $dlg.Controls.Add($yes)

        $no = New-RamButton -Text 'Отмена' -Width 110 -Height 34 -OnClick {
            $this.FindForm().Tag = $false
            $this.FindForm().Close()
        }
        $noW = (Measure-RamControl -Control $no).Width
        $no.Location  = New-Object System.Drawing.Point(($width - 24 - $noW), $btnY)
        $yes.Location = New-Object System.Drawing.Point(($width - 24 - $noW - 8 - $yesW), $btnY)
        $dlg.Controls.Add($no)

        $dlg.Tag = $false
    } else {
        $ok = New-RamButton -Text 'Понятно' -Width 130 -Height 34 -Kind 'primary' -OnClick {
            $this.FindForm().Close()
        }
        $ok.Location = New-Object System.Drawing.Point(($width - 24 - (Measure-RamControl -Control $ok).Width), $btnY)
        $dlg.Controls.Add($ok)
    }

    if ($BuildOnly) { return $dlg }

    [void]$dlg.ShowDialog()
    if     ($Buttons.Count -gt 0) { $result = $dlg.Tag }
    elseif ($YesNo)               { $result = [bool]$dlg.Tag }
    $dlg.Dispose()
    return $result
}

function Show-RamError { param([string]$Text, [string]$Title = 'Ошибка')
    [void](Show-RamMessage -Message $Text -Title $Title -Kind 'error') }

function Show-RamInfo  { param([string]$Text, [string]$Title = 'AltHub')
    [void](Show-RamMessage -Message $Text -Title $Title -Kind 'info') }

function Confirm-Ram   { param([string]$Text, [string]$Title = 'Подтверждение')
    return (Show-RamMessage -Message $Text -Title $Title -Kind 'warn' -YesNo) }

function Show-RamInputDialog {
    <# Тёмное окно с одним полем ввода. Возвращает строку или $null. #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Prompt = '',
        [string]$Value  = '',
        [switch]$Password,
        # Готовые варианты: массив @{ Text; Value }. Выбор подставляется в поле.
        [object[]]$Suggestions = @(),
        # Только для Самопроверки: собрать окно и вернуть, не показывая.
        [switch]$BuildOnly
    )

    $t = $Global:RamTheme
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = $Title
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.Font            = $t.FontBody
    $hasSug = (@($Suggestions).Count -gt 0 -and -not $Password)
    $dlgH   = if ($hasSug) { 288 } else { 210 }
    $dlg.ClientSize      = New-Object System.Drawing.Size(520, $dlgH)

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Size = New-Object System.Drawing.Size(520, 4)
    $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $dlg.Controls.Add((New-RamLabel -Text $Title -X 24 -Y 22 -Width 472 -Height 26 -Font $t.FontTitle))
    if ($Prompt) {
        $lblPrompt = New-Object System.Windows.Forms.Label
        $lblPrompt.Text      = $Prompt
        $lblPrompt.Location  = New-Object System.Drawing.Point(24, 52)
        $lblPrompt.Size      = New-Object System.Drawing.Size(472, 52)
        $lblPrompt.Font      = $t.FontSmall
        $lblPrompt.ForeColor = $t.Muted
        $lblPrompt.BackColor = [System.Drawing.Color]::Transparent
        $dlg.Controls.Add($lblPrompt)
    }

    $boxY = 110
    if ($hasSug) {
        $dlg.Controls.Add((New-RamLabel -Text 'СОХРАНЁННЫЕ ИГРЫ — ВЫБЕРИ ИЗ СПИСКА' -X 24 -Y 108 -Width 472 -Height 18 `
                                        -Font $t.FontSmall -Color $t.Muted))
        $cbSug = New-Object System.Windows.Forms.ComboBox
        $cbSug.Location      = New-Object System.Drawing.Point(24, 128)
        $cbSug.Size          = New-Object System.Drawing.Size(472, 26)
        $cbSug.DropDownStyle = 'DropDownList'
        $cbSug.FlatStyle     = 'Flat'
        $cbSug.BackColor     = $t.Card
        $cbSug.ForeColor     = $t.Text
        [void]$cbSug.Items.Add('— не выбрано —')
        foreach ($sg in $Suggestions) { [void]$cbSug.Items.Add($sg.Text) }
        foreach ($sg in $Suggestions) {
            if (Test-RamHasEmoji -Text ([string]$sg.Text)) { $cbSug.Font = Get-RamEmojiFont -Like $cbSug.Font; break }
        }
        $cbSug.SelectedIndex = 0
        $dlg.Controls.Add($cbSug)

        $dlg.Controls.Add((New-RamLabel -Text 'ИЛИ ВСТАВЬ ССЫЛКУ ВРУЧНУЮ' -X 24 -Y 162 -Width 472 -Height 18 `
                                        -Font $t.FontSmall -Color $t.Muted))
        $boxY = 182
    }

    # Ширину поля считаем ЗАРАНЕЕ. Внутри New-RamTextBox лежит настоящий
    # TextBox фиксированного размера, и ужать панель постфактум нельзя —
    # поле останется прежним и вылезет наружу.
    if ($Password) {
        $boxWidth = 472
    } else {
        $pasteW   = (Get-RamDialogButtonWidth -Text 'Вставить')
        $boxWidth = 520 - 48 - $pasteW - 8
    }
    $box = New-RamTextBox -Width $boxWidth -Height 34 -Value $Value
    $box.Location = New-Object System.Drawing.Point(24, $boxY)
    if ($Password) { $box.Tag.UseSystemPasswordChar = $true }
    $dlg.Controls.Add($box)

    if (-not $Password) {
        # Ctrl+V работает, но кнопка нагляднее — особенно когда длинную ссылку
        # копируешь из браузера и не хочешь промахнуться мимо поля.
        $btnPasteIn = New-RamButton -Text 'Вставить' -Width $pasteW -Height 34 -Fixed -OnClick {
            try {
                if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                    $t = [System.Windows.Forms.Clipboard]::GetText()
                    if (-not [string]::IsNullOrWhiteSpace($t)) {
                        $box.Tag.Text = $t.Trim()
                        $box.Tag.Focus()
                        $box.Tag.SelectionStart = $box.Tag.TextLength
                    }
                }
            } catch { }
        }
        # От правого края: кнопка расширяется под надпись и на крупном
        # масштабе вылезала за окно.
        $btnPasteIn.Location = New-Object System.Drawing.Point((520 - 24 - (Measure-RamControl -Control $btnPasteIn).Width), $boxY)
        $dlg.Controls.Add($btnPasteIn)
    }

    if ($hasSug) {
        # Выбор из списка сразу подставляется в поле — дальше всё как обычно.
        $cbSug.Add_SelectedIndexChanged({
            $i = $cbSug.SelectedIndex
            if ($i -le 0) { return }
            $box.Tag.Text = $Suggestions[$i - 1].Value
        })
    }

    $ok = New-RamButton -Text 'OK' -Width 110 -Height 34 -Kind 'primary' -OnClick {
        $this.FindForm().Tag = $true
        $this.FindForm().Close()
    }
    $okW2 = (Measure-RamControl -Control $ok).Width
    $dlg.Controls.Add($ok)

    $cancel = New-RamButton -Text 'Отмена' -Width 110 -Height 34 -OnClick {
        $this.FindForm().Tag = $false
        $this.FindForm().Close()
    }
    # От правого края и по фактической ширине: на крупном масштабе надписи
    # длиннее, и жёсткие координаты выносили «Отмену» за окно.
    $cancelW2 = (Measure-RamControl -Control $cancel).Width
    $cancel.Location = New-Object System.Drawing.Point((520 - 24 - $cancelW2), ($dlgH - 52))
    $ok.Location     = New-Object System.Drawing.Point((520 - 24 - $cancelW2 - 8 - $okW2), ($dlgH - 52))
    $dlg.Controls.Add($cancel)

    $dlg.Tag = $false
    if ($BuildOnly) { return $dlg }

    $dlg.Add_Shown({ $box.Tag.Focus(); $box.Tag.SelectAll() })
    [void]$dlg.ShowDialog()

    $accepted = [bool]$dlg.Tag
    $text = $box.Tag.Text
    $dlg.Dispose()

    if (-not $accepted) { return $null }
    return $text
}

function Show-RamPasswordDialog {
    param(
        [string]$Title  = 'Мастер-пароль',
        [string]$Prompt = 'Введите мастер-пароль:',
        [switch]$Confirm
    )

    $p1 = Show-RamInputDialog -Title $Title -Prompt $Prompt -Password
    if ($null -eq $p1) { return $null }

    if ($Confirm) {
        $p2 = Show-RamInputDialog -Title $Title -Prompt 'Повторите тот же пароль:' -Password
        if ($null -eq $p2) { return $null }
        if ($p1 -ne $p2) {
            Show-RamError 'Пароли не совпадают. Попробуй ещё раз.'
            return (Show-RamPasswordDialog -Title $Title -Prompt $Prompt -Confirm:$Confirm)
        }
    }
    return $p1
}


# ------------------------------------------- мастер добавления аккаунтов ----

function Show-RamBatchAddDialog {
    <#
      Вставить сразу несколько аккаунтов: по строке на аккаунт. Каждая строка —
      либо кука .ROBLOSECURITY, либо приглашение althub://. Порядок строк не
      важен, пустые пропускаются.

      Возвращает число реально добавленных — вызывающий обновляет список.
    #>
    param([switch]$BuildOnly)

    $t = $Global:RamTheme
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Вставить пачкой'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.ForeColor       = $t.Text
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size(600, 460)

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Size = New-Object System.Drawing.Size(600, 4); $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $dlg.Controls.Add((New-RamLabel -Text 'Вставить пачкой' -X 28 -Y 22 -Width 400 -Height 30 -Font $t.FontBig))
    # Явные переносы: одной строкой текст не влезает ни при каком масштабе.
    $batchHint = "По одному аккаунту на строку. Строка — это либо кука`n(.ROBLOSECURITY целиком), либо приглашение althub://."
    $dlg.Controls.Add((New-RamLabel -Text $batchHint `
                                    -X 28 -Y 58 -Width 544 -Height 48 -Font $t.FontSmall -Color $t.Muted))

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline   = $true
    $box.ScrollBars  = 'Vertical'
    $box.WordWrap    = $false
    $box.Location    = New-Object System.Drawing.Point(28, 114)
    $box.Size        = New-Object System.Drawing.Size(544, 240)
    $box.BackColor   = $t.LogBack
    $box.ForeColor   = $t.Text
    $box.BorderStyle = 'FixedSingle'
    $box.Font        = $t.FontMono
    $dlg.Controls.Add($box)

    $lblResult = New-RamLabel -Text '' -X 28 -Y 366 -Width 544 -Height 40 -Font $t.FontSmall -Color $t.Muted
    $dlg.Controls.Add($lblResult)

    # Ответ наружу отдаём через хэш: он захватывается по ссылке и переживает
    # .GetNewClosure(). Запись в $script: отсюда потерялась бы молча.
    $result = @{ Added = 0 }

    $btnGo = New-RamButton -Text 'Добавить все' -Width 180 -Height 36 -Kind 'primary' -OnClick ({
        $text = $box.Text
        if ([string]::IsNullOrWhiteSpace($text)) { Show-RamInfo 'Вставь хотя бы одну куку или приглашение.'; return }

        $this.FindForm().Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $sum = Import-RamAccountBatch -Text $text
        $this.FindForm().Cursor = [System.Windows.Forms.Cursors]::Default

        $result.Added = $sum.Added
        $parts = @()
        if ($sum.Added -gt 0)   { $parts += "добавлено: $($sum.Added)" }
        if ($sum.Updated -gt 0) { $parts += "обновлено: $($sum.Updated)" }
        if ($sum.Failed -gt 0)  { $parts += "не вышло: $($sum.Failed)" }
        $msg = if ($parts.Count -gt 0) { $parts -join ', ' } else { 'ничего не разобрал' }
        if ($sum.Failed -gt 0 -and $sum.Errors.Count -gt 0) {
            $msg += "  ·  первая причина: $($sum.Errors[0])"
        }
        $lblResult.Text = $msg
        $lblResult.ForeColor = if ($sum.Failed -gt 0 -and $sum.Added -eq 0) { $t.Danger } else { $t.Ok }

        if ($sum.Added -gt 0 -or $sum.Updated -gt 0) {
            Build-RamCards
            Update-RamHeaderCounts
            Write-RamLog "Пачкой: добавлено $($sum.Added), обновлено $($sum.Updated), не вышло $($sum.Failed)." 'ok'
        }
    }.GetNewClosure())
    $btnGo.Location = New-Object System.Drawing.Point(28, 410)
    $dlg.Controls.Add($btnGo)

    $btnClose = New-RamButton -Text 'Закрыть' -Width 120 -Height 36 -OnClick { $this.FindForm().Close() }
    $btnClose.Location = New-Object System.Drawing.Point(452, 410)
    $dlg.Controls.Add($btnClose)

    if ($BuildOnly) { return $dlg }

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $result.Added
}

function Show-RamBrowserGuide {
    <#
      Добавить аккаунт из БРАУЗЕРА безопасным способом.

      ВАЖНО. Мы НЕ лезем в хранилище кук браузера — это ровно то, что делают
      стилеры, и на новых Chrome/Edge оно всё равно закрыто app-bound
      шифрованием. Вместо этого открываем roblox.com и показываем, как забрать
      свою куку руками через DevTools. Работает в любом браузере, ничего не
      расшифровывается за спиной.

      Возвращает $true, если аккаунт добавили.
    #>
    param([switch]$BuildOnly)

    $t = $Global:RamTheme
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Из браузера'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.ForeColor       = $t.Text
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size(620, 470)

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Size = New-Object System.Drawing.Size(620, 4); $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $dlg.Controls.Add((New-RamLabel -Text 'Добавить из браузера' -X 28 -Y 22 -Width 460 -Height 30 -Font $t.FontBig))

    $steps = @'
Куку берём руками из самого браузера — AltHub в его хранилище не лезет.
Это безопасно и работает в любом браузере.

  1. Нажми «Открыть Roblox» ниже и войди под нужным аккаунтом.
  2. Нажми F12 — откроются инструменты разработчика.
  3. Вкладка Application (или «Приложение»)  ->  слева Cookies  ->  https://www.roblox.com
  4. Найди строку .ROBLOSECURITY, скопируй её значение (двойной клик по Value, Ctrl+C).
  5. Вставь сюда, в поле ниже, и нажми «Добавить».

Значение длинное и начинается с _|WARNING:-DO-NOT-SHARE-THIS... — это нормально,
так и должно быть. Никому его не показывай: это ключ от аккаунта.
'@
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $steps
    # Всё, что ниже, отсчитывается от фактического низа инструкции: её
    # высота зависит от шрифта, а он растёт вместе с масштабом экрана.
    $stepsH = [Math]::Max(210, (Measure-RamText -Text $steps -Font $t.FontBody -MaxWidth 564).Height + 10)
    $yOpen  = 58 + $stepsH + 12
    $yBox   = $yOpen + 50
    $yHint  = $yBox + 42
    $yBtns  = $yHint + 32
    $dlg.ClientSize = New-Object System.Drawing.Size(620, ($yBtns + 60))

    $lbl.Location = New-Object System.Drawing.Point(28, 58)
    # Высота по факту: на крупном масштабе фиксированные 210 px обрезали
    # последние строки инструкции.
    $lbl.Size = New-Object System.Drawing.Size(564, ([Math]::Max(210, (Measure-RamText -Text $steps -Font $t.FontBody -MaxWidth 564).Height + 10)))
    $lbl.Font = $t.FontBody
    $lbl.ForeColor = $t.Text
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $dlg.Controls.Add($lbl)

    $btnOpen = New-RamButton -Text 'Открыть Roblox в браузере' -Width 260 -Height 34 -Kind 'ghost' -OnClick {
        try { Start-Process 'https://www.roblox.com/home' } catch { Show-RamError 'Не получилось открыть браузер.' }
    }
    $btnOpen.Location = New-Object System.Drawing.Point(28, $yOpen)
    $dlg.Controls.Add($btnOpen)

    # $box — это ПАНЕЛЬ-обёртка, само поле лежит в .Tag. Читать надо
    # $box.Tag.Text: у панели свой пустой .Text, и проверка «длина меньше 50»
    # срабатывала всегда, сколько бы куку ни вставляли.
    $box = New-RamTextBox -Width 564 -Height 30
    $box.Location = New-Object System.Drawing.Point(28, $yBox)
    $dlg.Controls.Add($box)
    $dlg.Controls.Add((New-RamLabel -Text 'Сюда вставь значение .ROBLOSECURITY' -X 28 -Y $yHint -Width 400 -Height 18 -Font $t.FontSmall -Color $t.Muted))

    # То же самое: хэш вместо $script:-флага, иначе результат не дойдёт.
    $result = @{ Ok = $false }
    $btnAdd = New-RamButton -Text 'Добавить' -Width 160 -Height 36 -Kind 'primary' -OnClick ({
        $val = ([string]$box.Tag.Text).Trim()
        if ($val.Length -lt 50) { Show-RamError 'Похоже, вставилось не всё. Значение .ROBLOSECURITY длинное.'; return }
        $this.FindForm().Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $r = Import-RamAccountLine -Line $val
        $this.FindForm().Cursor = [System.Windows.Forms.Cursors]::Default
        if ($r.Ok) {
            $result.Ok = $true
            Build-RamCards; Update-RamHeaderCounts
            Write-RamLog "Из браузера добавлен «$($r.Alias)»." 'ok'
            Show-RamInfo "Готово, добавлен «$($r.Alias)»."
            $this.FindForm().Close()
        } else {
            Show-RamError "Не вышло: $($r.Error)"
        }
    }.GetNewClosure())
    $btnAdd.Location = New-Object System.Drawing.Point(28, $yBtns)
    $dlg.Controls.Add($btnAdd)

    $btnClose = New-RamButton -Text 'Закрыть' -Width 120 -Height 36 -OnClick { $this.FindForm().Close() }
    $btnClose.Location = New-Object System.Drawing.Point(472, $yBtns)
    $dlg.Controls.Add($btnClose)

    if ($BuildOnly) { return $dlg }

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $result.Ok
}

function Import-RamDroppedFile {
    <#
      Обрабатывает файл, бросённый на окно. Это либо выгрузка настроек
      (althub-setup.json — там НЕТ кук, только игры и раскладка), либо
      текстовый список кук/приглашений (по строке на аккаунт).

      Решаем по содержимому, а не по расширению: у людей файлы называются
      как попало.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $raw = ''
    try { $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop } catch {
        Show-RamError 'Не получилось прочитать файл.'; return
    }

    # Файл настроек? У него в JSON есть "app" и "accounts" без кук.
    $looksLikeSetup = $false
    try {
        $j = $raw | ConvertFrom-Json
        if ($j.PSObject.Properties.Name -contains 'games' -or $j.PSObject.Properties.Name -contains 'accounts') { $looksLikeSetup = $true }
    } catch { }

    if ($looksLikeSetup) {
        try {
            $r = Import-RamSetup -Path $Path
            Show-RamInfo "Из файла применено: настроек $($r.Settings), игр $($r.Games).`n`nАккаунты по нему не создаются — в выгрузке настроек кук нет."
        } catch { Show-RamError $_.Exception.Message }
        return
    }

    # Иначе — список кук/приглашений.
    $sum = Import-RamAccountBatch -Text $raw
    if ($sum.Total -eq 0) { Show-RamInfo 'В файле не нашлось ни куки, ни приглашения.'; return }
    Build-RamCards; Update-RamHeaderCounts
    Show-RamInfo "Из файла: добавлено $($sum.Added), обновлено $($sum.Updated), не вышло $($sum.Failed)."
    Write-RamLog "Из брошенного файла: добавлено $($sum.Added), обновлено $($sum.Updated)." 'ok'
}

function Update-RamAddedList {
    <#
      Перерисовывает список «Добавлено за этот заход» и раздвигает окно под
      его настоящую высоту.

      Раньше это была подпись жёсткой высоты 56 px: три строки влезали,
      четвёртая и дальше просто обрезались, и человек не видел, что аккаунт
      добавился. Теперь высота меряется по тексту, а нижний ряд кнопок и само
      окно съезжают на разницу.

      Всё ищется по именам через форму: обработчики живут дольше, чем вызов
      Show-RamAddWizard, и локалы им уже недоступны.
    #>
    param(
        $Form,
        [AllowNull()][AllowEmptyCollection()][object[]]$Names
    )
    if ($null -eq $Form) { return }

    $lbl = $Form.Controls.Find('ramAddedList', $true) | Select-Object -First 1
    if ($null -eq $lbl) { return }

    if ($null -eq $Names) { $Names = @() }
    $list = @($Names)

    # Больше десятка строк окно бы вытолкнуло за экран — остаток сворачиваем
    # в одну строку, но счёт остаётся честным.
    $maxRows = 10
    if ($list.Count -eq 0) {
        $text = '— пока ничего —'
    } elseif ($list.Count -le $maxRows) {
        $text = ($list | ForEach-Object { '  ✓  ' + $_ }) -join [Environment]::NewLine
    } else {
        $head = $list[0..($maxRows - 1)] | ForEach-Object { '  ✓  ' + $_ }
        $text = ($head -join [Environment]::NewLine) +
                [Environment]::NewLine + ('     и ещё {0}' -f ($list.Count - $maxRows))
    }
    $lbl.Text = $text

    $need = (Measure-RamText -Text $text -Font $lbl.Font -MaxWidth $lbl.Width).Height + 4
    $min  = [int][Math]::Round(56 * $Global:RamTheme.M.Scale)
    if ($need -lt $min) { $need = $min }

    $delta = $need - $lbl.Height
    if ($delta -eq 0) { return }
    $lbl.Height = $need

    foreach ($n in @('ramAddMore', 'ramAddHint', 'ramAddDone')) {
        $c = $Form.Controls.Find($n, $true) | Select-Object -First 1
        if ($null -ne $c) { $c.Top = $c.Top + $delta }
    }
    $Form.ClientSize = New-Object System.Drawing.Size(
        $Form.ClientSize.Width, ($Form.ClientSize.Height + $delta))
}

function Show-RamAddWizard {
    <#
      Главный способ добавить аккаунты для того, кто не хочет лезть в F12.
      Читает куку прямо из открытого приложения Roblox, показывает, чей это
      аккаунт, и добавляет его одной кнопкой. Дальше — сменил аккаунт в
      приложении, нажал "Проверить снова".
    #>
    param(
        # Только для Самопроверка.ps1: собрать окно и вернуть, не показывая.
        [switch]$BuildOnly
    )

    $t = $Global:RamTheme
    $w = @{ Cookie = ''; User = $null; Added = @(); Busy = $false }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Добавление аккаунтов'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.Font            = $t.FontBody
    $howto = @'
Менеджер читает, под каким аккаунтом ты сейчас вошёл в приложении Roblox,
и забирает этот вход себе. Пароль не нужен.

  1. Войди в приложении Roblox под нужным аккаунтом
  2. Нажми «Проверить снова» — появится ник этого аккаунта
  3. Нажми «Добавить этот аккаунт»
  4. Нажми «Сменить аккаунт» — и снова с шага 1

НИКОГДА не жми «Выйти» в самом Roblox: эта кнопка убивает вход на сервере,
и аккаунт, который ты только что добавил, перестанет запускаться. Кнопка
«Сменить аккаунт» делает то же самое, но безопасно — приложение просто
забывает вход, а на сервере он остаётся живым.
'@

    # Высота окна складывается из фактической высоты блоков. Раньше все
    # координаты были вписаны числами под обычный шрифт, и на масштабе 125%
    # длинная инструкция вырастала и наезжала на карточку под ней.
    $howH  = [Math]::Max(228, (Measure-RamText -Text $howto -Font $t.FontBody -MaxWidth 624).Height + 10)
    $yCard = 62 + $howH + 12
    $yRow1 = $yCard + 110
    $yRow2 = $yRow1 + 46
    $yAdd  = $yRow2 + 50
    $yBot  = $yAdd + 94
    $dlgH  = $yBot + 92

    $dlgW = [Math]::Max(680, [int](680 * $Global:RamTheme.M.Scale))
    $dlg.ClientSize      = New-Object System.Drawing.Size($dlgW, $dlgH)

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Size = New-Object System.Drawing.Size(680, 4); $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $dlg.Controls.Add((New-RamLabel -Text 'Добавление аккаунтов' -X 28 -Y 24 -Width 620 -Height 32 -Font $t.FontBig))

    $lblHow = New-Object System.Windows.Forms.Label
    $lblHow.Text      = $howto
    $lblHow.Location  = New-Object System.Drawing.Point(28, 62)
    # Высота по факту: текст меряется шрифтом, и на крупном масштабе
    # фиксированные 228 px обрезали последние строки.
    $lblHow.Size      = New-Object System.Drawing.Size(624, $howH)
    $lblHow.Font      = $t.FontBody
    $lblHow.ForeColor = $t.Muted
    $lblHow.BackColor = [System.Drawing.Color]::Transparent
    $dlg.Controls.Add($lblHow)

    # --- карточка "кто сейчас в приложении"
    $card = New-RamCard -Width 624 -Height 96
    $card.Location = New-Object System.Drawing.Point(28, $yCard)
    $dlg.Controls.Add($card)

    $av = New-RamAvatarBox -Size 60
    $av.Location = New-Object System.Drawing.Point(18, 18)
    $card.Controls.Add($av)

    $lblWho = New-RamLabel -Text 'Проверяю приложение Roblox...' -X 94 -Y 22 -Width 400 -Height 26 -Font $t.FontTitle
    $card.Controls.Add($lblWho)

    $lblWho2 = New-RamLabel -Text '' -X 94 -Y 48 -Width 500 -Height 30 -Font $t.FontSmall -Color $t.Muted
    $card.Controls.Add($lblWho2)

    # --- кнопки
    $btnRefresh = New-RamButton -Text 'Проверить снова' -Width 180 -Height 38
    $btnRefresh.Location = New-Object System.Drawing.Point(28, $yRow1)
    $xRow = 28 + (Measure-RamControl -Control $btnRefresh).Width + 12
    $dlg.Controls.Add($btnRefresh)

    $btnAdd = New-RamButton -Text 'Добавить этот аккаунт' -Width 240 -Height 38 -Kind 'primary'
    $btnAdd.Location = New-Object System.Drawing.Point($xRow, $yRow1)
    $xRow += (Measure-RamControl -Control $btnAdd).Width + 12
    $dlg.Controls.Add($btnAdd)

    $btnManual = New-RamButton -Text 'Ввести куку вручную' -Width 180 -Height 38 -Kind 'ghost'
    $btnManual.Location = New-Object System.Drawing.Point($xRow, $yRow1)
    $dlg.Controls.Add($btnManual)

    # --- список добавленного
    $dlg.Controls.Add((New-RamLabel -Text 'Добавлено за этот заход:' -X 28 -Y $yAdd -Width 300 -Height 22 `
                                    -Font $t.FontSmall -Color $t.Muted))

    # Высота этого списка ФИКСИРОВАННОЙ быть не может: сколько аккаунтов
    # добавят за заход, столько строк и будет. С жёсткими 56 px помещалось
    # ровно три, четвёртый и дальше просто обрезались.
    $lblAdded = New-Object System.Windows.Forms.Label
    $lblAdded.Name      = 'ramAddedList'
    $lblAdded.Text      = '— пока ничего —'
    $lblAdded.Location  = New-Object System.Drawing.Point(28, ($yAdd + 24))
    $lblAdded.Size      = New-Object System.Drawing.Size(624, 56)
    $lblAdded.Font      = $t.FontBody
    $lblAdded.ForeColor = $t.Ok
    $lblAdded.BackColor = [System.Drawing.Color]::Transparent
    $dlg.Controls.Add($lblAdded)

    # Главная кнопка всего мастера: сменить аккаунт, не убив забранный вход.
    $btnSwitch = New-RamButton -Text 'Сменить аккаунт (безопасно)' -Width 260 -Height 38 -Kind 'primary' `
                               -Tooltip 'Закрыть Roblox и заставить его забыть вход, не разлогинивая на сервере'
    $btnSwitch.Location = New-Object System.Drawing.Point(28, $yRow2)
    $dlg.Controls.Add($btnSwitch)

    $btnRestore = New-RamButton -Text 'Вернуть прошлый вход' -Width 220 -Height 38 -Kind 'ghost' `
                                -Tooltip 'Положить обратно последний сохранённый вход приложения'
    $btnRestore.Location = New-Object System.Drawing.Point((28 + (Measure-RamControl -Control $btnSwitch).Width + 12), $yRow2)
    $dlg.Controls.Add($btnRestore)

    $btnSwitch.Add_Click({
        $label = if ($null -ne $w.User) { $w.User.Name } else { 'session' }
        if (-not (Clear-RamAppSession -Label $label)) { return }

        $lblWho.Text  = 'Приложение больше никого не помнит'
        $lblWho.ForeColor = $t.Ok
        $lblWho2.Text = 'Открой Roblox, войди под следующим аккаунтом и нажми «Проверить снова». Вход предыдущего аккаунта остался живым.'
        $lblWho2.ForeColor = $t.Muted
        Set-RamAvatarImage -Box $av -Image $null -Letter '?'
        $av.Tag.Image = $null; $av.Invalidate()
        Set-RamButtonEnabled $btnAdd $false
    })

    $btnRestore.Add_Click({
        $backups = @(Get-RamSessionBackups)
        if ($backups.Count -eq 0) { Show-RamInfo 'Сохранённых входов пока нет.'; return }

        $running = @(Get-RamRobloxProcesses)
        if ($running.Count -gt 0) {
            if (-not (Confirm-Ram "Надо закрыть Roblox (открыто окон: $($running.Count)). Закрыть сейчас?")) { return }
            foreach ($p in $running) { [void](Stop-RamRobloxInstance -ProcessId $p.Id) }
            Start-Sleep -Milliseconds 2000
        }

        try {
            [void](Restore-RamRobloxSession -BackupPath $backups[0].FullName)
            Write-RamLog ('Вход приложения восстановлен из ' + $backups[0].Name) 'ok'
            Show-RamInfo ("Вход возвращён из копии:`n`n$($backups[0].Name)`n`nОткрой Roblox — там снова будет тот аккаунт.")
        } catch {
            Show-RamError $_.Exception.Message
        }
    })

    # --- ещё способы добавить: пачкой / из браузера / из файла
    $refreshAdded = {
        param($n, $how)
        if ($n -gt 0) {
            $w.Added += "аккаунтов $n ($how)"
            Update-RamAddedList -Form $lblAdded.FindForm() -Names $w.Added
        }
    }.GetNewClosure()

    $btnMore = New-RamButton -Text 'Ещё способы  ▾' -Width 180 -Height 38 -Kind 'ghost' `
                             -Tooltip 'Вставить несколько кук сразу, забрать из браузера или из файла'
    $btnMore.Name = 'ramAddMore'
    $btnMore.Location = New-Object System.Drawing.Point(28, $yBot)
    $moreW = (Measure-RamControl -Control $btnMore).Width
    $dlg.Controls.Add($btnMore)

    $moreMenu = New-RamContextMenu
    [void](Add-RamMenuItem -Menu $moreMenu -Text 'Вставить пачкой (несколько кук сразу)' -OnClick ({
        $n = Show-RamBatchAddDialog
        & $refreshAdded $n 'пачкой'
    }.GetNewClosure()))
    [void](Add-RamMenuItem -Menu $moreMenu -Text 'Из браузера (Chrome, Edge, ...)' -OnClick ({
        if (Show-RamBrowserGuide) { & $refreshAdded 1 'из браузера' }
    }.GetNewClosure()))
    [void](Add-RamMenuItem -Menu $moreMenu -Separator)
    [void](Add-RamMenuItem -Menu $moreMenu -Text 'Из файла (список кук или приглашений)...' -OnClick {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'Текст или JSON (*.txt;*.json)|*.txt;*.json|Все файлы (*.*)|*.*'
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Import-RamDroppedFile -Path $ofd.FileName }
    })
    $btnMore.Add_Click({ $moreMenu.Show($this, (New-Object System.Drawing.Point(0, $this.Height))) }.GetNewClosure())

    $lblDropHint = New-RamLabel -Text 'Подсказка: список кук или файл настроек можно просто перетащить на главное окно.' `
                                -X (28 + $moreW + 12) -Y ($yBot + 2) -Width 260 -Height 72 -Font $t.FontSmall -Color $t.Muted
    $lblDropHint.Name = 'ramAddHint'
    $dlg.Controls.Add($lblDropHint)

    $btnDone = New-RamButton -Text 'Готово' -Width 130 -Height 38 -Kind 'primary' -OnClick {
        $this.FindForm().Close()
    }
    $btnDone.Name = 'ramAddDone'
    $btnDone.Location = New-Object System.Drawing.Point(($dlgW - 28 - (Measure-RamControl -Control $btnDone).Width), $yBot)
    $dlg.Controls.Add($btnDone)

    # --- логика
    $refresh = {
        if ($w.Busy) { return }
        $w.Busy = $true
        Set-RamButtonEnabled $btnAdd $false
        $lblWho.Text  = 'Читаю приложение Roblox...'
        $lblWho.ForeColor = $t.Text
        $lblWho2.Text = ''
        Set-RamAvatarImage -Box $av -Image $null -Letter '?'
        $av.Tag.Image = $null; $av.Invalidate()
        $dlg.Refresh()

        try {
            $cookie = Import-RamCurrentAccountCookie
            $user   = Get-RamAuthenticatedUser -Cookie $cookie

            $w.Cookie = $cookie
            $w.User   = $user

            $exists = $null
            foreach ($a in $script:Accounts) { if ($a.UserId -eq $user.Id) { $exists = $a } }

            $lblWho.Text = $user.Name
            $lblWho.ForeColor = $t.Text

            $age = Get-RamRobloxCookieFileAge
            $ageTxt = if ($null -ne $age) {
                if ($age.TotalMinutes -lt 90) { 'вход сохранён ' + [int]$age.TotalMinutes + ' мин назад' }
                else { 'вход сохранён ' + [int]$age.TotalHours + ' ч назад' }
            } else { '' }

            if ($null -ne $exists) {
                $lblWho2.Text = "ID $($user.Id) · уже в списке как «$($exists.Alias)» — можно обновить вход. $ageTxt"
                $lblWho2.ForeColor = $t.Warn
                Set-RamButtonText $btnAdd 'Обновить вход этого аккаунта'
            } else {
                $lblWho2.Text = "ID $($user.Id) · новый аккаунт. $ageTxt"
                $lblWho2.ForeColor = $t.Muted
                Set-RamButtonText $btnAdd 'Добавить этот аккаунт'
            }
            Set-RamButtonEnabled $btnAdd $true

            $file = Get-RamAvatarFile -UserId $user.Id -CacheDir (Get-RamAvatarDir)
            $img  = Get-RamImageFromFile -Path $file
            if ($null -ne $img) { Set-RamAvatarImage -Box $av -Image $img -Letter $user.Name }
            else { Set-RamAvatarImage -Box $av -Image $null -Letter $user.Name }

        } catch {
            $lblWho.Text = 'Не вижу входа в приложении Roblox'
            $lblWho.ForeColor = $t.Danger
            $lblWho2.Text = $_.Exception.Message
            $lblWho2.ForeColor = $t.Muted
            Set-RamAvatarImage -Box $av -Image $null -Letter '?'
            Set-RamButtonEnabled $btnAdd $false
        } finally {
            $w.Busy = $false
        }
    }

    $btnRefresh.Add_Click($refresh)

    $btnAdd.Add_Click({
        if ($null -eq $w.User -or [string]::IsNullOrWhiteSpace($w.Cookie)) { return }
        try {
            $res = Add-RamAccountFromCookie -Cookie $w.Cookie
            $name = $res.Account.Alias

            if ($res.IsNew) {
                $w.Added += $name
                Write-RamLog "Добавлен аккаунт '$name' из приложения Roblox." 'ok'
            } else {
                Write-RamLog "Обновлён вход аккаунта '$name'." 'ok'
                if ($w.Added -notcontains ($name + ' (обновлён)')) { $w.Added += ($name + ' (обновлён)') }
            }

            Update-RamAddedList -Form $lblAdded.FindForm() -Names $w.Added
            Set-RamButtonEnabled $btnAdd $false

            $lblWho2.Text = 'Готово. Теперь нажми «Сменить аккаунт (безопасно)» внизу — и войди под следующим. Кнопку «Выйти» в самом Roblox не трогай.'
            $lblWho2.ForeColor = $t.Ok

            Build-RamCards
            Update-RamHeaderCounts
        } catch {
            Show-RamError "Не получилось добавить аккаунт:`n`n$($_.Exception.Message)"
        }
    })

    $btnManual.Add_Click({
        $acc = Show-RamAccountDialog -Account $null
        if ($null -ne $acc) {
            $script:Accounts = @($script:Accounts) + $acc
            Save-RamState
            $w.Added += ($acc.Alias + ' (вручную)')
            Update-RamAddedList -Form $lblAdded.FindForm() -Names $w.Added
            Build-RamCards
            Update-RamHeaderCounts
            Write-RamLog "Добавлен аккаунт '$($acc.Alias)' вручную." 'ok'
        }
    })

    if ($BuildOnly) { return $dlg }

    $dlg.Add_Shown($refresh)
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ------------------------------------------------- диалог: аккаунт ----------

function New-RamCombo {
    <#
      Тёмный выпадающий список из набора @{Text;Value}.

      WinForms у списка типа DropDownList просто игнорирует BackColor и рисует
      его системными цветами — в тёмной теме получается белый прямоугольник.
      Поэтому строки рисуем сами (DrawMode = OwnerDrawFixed).
    #>
    param(
        [int]$X, [int]$Y, [int]$Width,
        [Parameter(Mandatory)][object[]]$Items,
        [string]$Value = '',
        # Ноль — взять высоту строки текущего масштаба. Прежние жёсткие 26 px
        # при 150% обрезали текст: шрифт вырос, коробка осталась прежней.
        [int]$Height = 0
    )
    $t = $Global:RamTheme
    $m = $t.M
    if ($Height -le 0) { if ($null -ne $m) { $Height = $m.RowHSm } else { $Height = 26 } }

    $cb = New-Object System.Windows.Forms.ComboBox
    $cb.Location      = New-Object System.Drawing.Point($X, $Y)
    $cb.Size          = New-Object System.Drawing.Size($Width, $Height)
    $cb.DropDownStyle = 'DropDownList'
    $cb.FlatStyle     = 'Flat'
    $cb.BackColor     = $t.Card
    $cb.ForeColor     = $t.Text
    $cb.Font          = $t.FontBody
    $cb.DrawMode      = 'OwnerDrawFixed'
    $cb.ItemHeight    = (Measure-RamText -Text 'Ay' -Font $t.FontBody).Height + 6

    $cb.Add_DrawItem({
        param($sender, $e)
        $th = $Global:RamTheme
        $selected = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)

        $back = if ($selected) { $th.Accent } else { $th.Card }
        $fore = if ($selected) { [System.Drawing.Color]::White } else { $th.Text }

        $b = New-Object System.Drawing.SolidBrush($back)
        $e.Graphics.FillRectangle($b, $e.Bounds)
        $b.Dispose()

        if ($e.Index -ge 0 -and $e.Index -lt $sender.Items.Count) {
            # TextRenderer, а не DrawString: он умеет подставлять шрифт под
            # смайлики в названиях игр.
            $rect = New-Object System.Drawing.Rectangle(
                ($e.Bounds.X + 4), $e.Bounds.Y, ($e.Bounds.Width - 8), $e.Bounds.Height)
            [System.Windows.Forms.TextRenderer]::DrawText(
                $e.Graphics, [string]$sender.Items[$e.Index], $sender.Font, $rect, $fore,
                ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                 [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor
                 [System.Windows.Forms.TextFormatFlags]::NoPrefix))
        }
    })

    foreach ($it in $Items) { [void]$cb.Items.Add($it.Text) }
    foreach ($it in $Items) {
        if (Test-RamHasEmoji -Text ([string]$it.Text)) { $cb.Font = Get-RamEmojiFont -Like $cb.Font; break }
    }

    $idx = 0
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ([string]$Items[$i].Value -eq [string]$Value) { $idx = $i; break }
    }
    $cb.SelectedIndex = $idx
    $cb.Tag = $Items
    return $cb
}

function Get-RamComboValue {
    param($Combo)
    if ($null -eq $Combo -or $Combo.SelectedIndex -lt 0) { return '' }
    return [string]$Combo.Tag[$Combo.SelectedIndex].Value
}

function Get-RamThemeItems {
    <# Список тем в виде пар для New-RamCombo: показываем подпись, храним ключ. #>
    $items = @()
    foreach ($th in Get-RamThemeList) { $items += [pscustomobject]@{ Text = $th.Title; Value = $th.Key } }
    return ,$items
}

function Set-RamComboItems {
    <# Перезаполнить список. Пары Text/Value лежат в Tag, поэтому менять
       только Items нельзя — Get-RamComboValue начнёт врать. #>
    param($Combo, [Parameter(Mandatory)][object[]]$Items, [string]$Value = '')
    if ($null -eq $Combo) { return }

    $Combo.Items.Clear()
    foreach ($it in $Items) { [void]$Combo.Items.Add($it.Text) }
    $Combo.Tag = $Items

    $idx = 0
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ([string]$Items[$i].Value -eq [string]$Value) { $idx = $i; break }
    }
    if ($Items.Count -gt 0) { $Combo.SelectedIndex = $idx }
}

function Show-RamAccountDialog {
    <# Полные настройки одного аккаунта. Возвращает объект или $null. #>
    param(
        $Account,
        # Только для Самопроверка.ps1: собрать окно и вернуть, не показывая.
        [switch]$BuildOnly
    )

    $t = $Global:RamTheme
    $isNew = ($null -eq $Account)

    $acc = New-RamAccount
    if (-not $isNew) {
        foreach ($p in $acc.PSObject.Properties.Name) {
            if ($Account.PSObject.Properties.Name -contains $p) { $acc.$p = $Account.$p }
        }
    }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = $(if ($isNew) { 'Новый аккаунт' } else { "Аккаунт: $($acc.Alias)" })
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size(920, 620)
    $dlg.Add_HandleCreated({ Set-RamDarkTitleBar $this })

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Size = New-Object System.Drawing.Size(920, 4); $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $dlg.Controls.Add((New-RamLabel -Text $dlg.Text -X 28 -Y 20 -Width 560 -Height 32 -Font $t.FontBig))

    # ============================================ ЛЕВАЯ КОЛОНКА: кто и куда ==
    $L = 28; $LW = 400

    $dlg.Controls.Add((New-RamLabel -Text 'НАЗВАНИЕ В СПИСКЕ' -X $L -Y 66 -Width 300 -Height 18 -Font $t.FontSmall -Color $t.Muted))
    $tbAlias = New-RamTextBox -Width $LW -Height 32 -Value $acc.Alias
    $tbAlias.Location = New-Object System.Drawing.Point($L, 86)
    $dlg.Controls.Add($tbAlias)

    $dlg.Controls.Add((New-RamLabel -Text 'КУКА .ROBLOSECURITY' -X $L -Y 128 -Width 300 -Height 18 -Font $t.FontSmall -Color $t.Muted))
    $tbCookie = New-RamTextBox -Width $LW -Height 64 -Multiline -Value $acc.Cookie
    $tbCookie.Location = New-Object System.Drawing.Point($L, 148)
    $dlg.Controls.Add($tbCookie)

    $btnFromApp = New-RamButton -Text 'Из приложения' -Width 194 -Height 30 -OnClick {
        try {
            $c = Import-RamCurrentAccountCookie
            $tbCookie.Tag.Text = $c
            $lblWho.Text = 'Кука получена. Нажми «Проверить».'
            $lblWho.ForeColor = $t.Ok
        } catch { Show-RamError $_.Exception.Message }
    }
    $btnFromApp.Location = New-Object System.Drawing.Point($L, 220)
    $dlg.Controls.Add($btnFromApp)

    $btnCheck = New-RamButton -Text 'Проверить' -Width 198 -Height 30 -Kind 'primary' -OnClick {
        $c = $tbCookie.Tag.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($c)) { Show-RamError 'Сначала вставь куку.'; return }
        $dlg.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        try {
            $u = Get-RamAuthenticatedUser -Cookie $c
            $acc.Username = $u.Name; $acc.UserId = $u.Id
            $lblWho.Text = "Аккаунт: $($u.Name)  (ID $($u.Id))"
            $lblWho.ForeColor = $t.Ok
            if ([string]::IsNullOrWhiteSpace($tbAlias.Tag.Text) -or $tbAlias.Tag.Text -eq 'Новый аккаунт') {
                $tbAlias.Tag.Text = $u.Name
            }
        } catch {
            $lblWho.Text = "Не прошло: $($_.Exception.Message)"
            $lblWho.ForeColor = $t.Danger
        } finally { $dlg.Cursor = [System.Windows.Forms.Cursors]::Default }
    }
    $btnCheck.Location = New-Object System.Drawing.Point(($L + 202), 220)
    $dlg.Controls.Add($btnCheck)

    $lblWho = New-RamLabel -Text $(if ($acc.Username) { "Аккаунт: $($acc.Username)  (ID $($acc.UserId))" } else { 'Аккаунт не проверен' }) `
                           -X $L -Y 256 -Width $LW -Height 22 -Font $t.FontSmall -Color $t.Muted
    $dlg.Controls.Add($lblWho)

    $dlg.Controls.Add((New-RamLabel -Text 'ИГРА — ССЫЛКА ИЛИ ID' -X $L -Y 288 -Width $LW -Height 18 -Font $t.FontSmall -Color $t.Muted))
    $tbPlace = New-RamTextBox -Width 258 -Height 32 -Value $acc.PlaceId
    $tbPlace.Location = New-Object System.Drawing.Point($L, 308)
    $dlg.Controls.Add($tbPlace)

    $btnResolve = New-RamButton -Text 'Узнать' -Width 134 -Height 32 -OnClick {
        if ([string]::IsNullOrWhiteSpace($tbPlace.Tag.Text)) {
            $acc.GameName = ''
            $lblGame.Text = 'Игра не задана — Roblox просто откроется'
            $lblGame.ForeColor = $t.Muted
            return
        }
        $dlg.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        try {
            $g = Resolve-RamGameInput -Value $tbPlace.Tag.Text
            $tbPlace.Tag.Text = $g.PlaceId
            if ($g.LinkCode) { $tbLink.Tag.Text = $g.LinkCode }
            $acc.GameName = $g.GameName
            if ($g.GameName) {
                $lblGame.Text = "Игра: $($g.GameName)" + $(if ($g.LinkCode) { '  (приватный сервер)' } else { '' })
                $lblGame.ForeColor = $t.Ok
            } else {
                $lblGame.Text = "ID игры: $($g.PlaceId) — название не получено"
                $lblGame.ForeColor = $t.Warn
            }
        } catch {
            $lblGame.Text = $_.Exception.Message.Split([char]10)[0]
            $lblGame.ForeColor = $t.Danger
        } finally { $dlg.Cursor = [System.Windows.Forms.Cursors]::Default }
    }
    $btnResolve.Location = New-Object System.Drawing.Point(($L + 266), 308)
    $dlg.Controls.Add($btnResolve)

    $lblGame = New-RamLabel -Text $(if ($acc.GameName) { "Игра: $($acc.GameName)" } else { 'Название игры не загружено' }) `
                            -X $L -Y 348 -Width $LW -Height 20 -Font $t.FontSmall -Color $t.Muted -Truncatable
    $dlg.Controls.Add($lblGame)

    $dlg.Controls.Add((New-RamLabel -Text 'ПРИВАТНЫЙ СЕРВЕР' -X $L -Y 378 -Width $LW -Height 18 -Font $t.FontSmall -Color $t.Muted))
    $tbLink = New-RamTextBox -Width $LW -Height 32 -Value $acc.LinkCode
    $tbLink.Location = New-Object System.Drawing.Point($L, 398)
    $dlg.Controls.Add($tbLink)

    $dlg.Controls.Add((New-RamLabel -Text 'JOBID КОНКРЕТНОГО СЕРВЕРА' -X $L -Y 440 -Width $LW -Height 18 -Font $t.FontSmall -Color $t.Muted))
    $tbJob = New-RamTextBox -Width $LW -Height 32 -Value $acc.JobId
    $tbJob.Location = New-Object System.Drawing.Point($L, 460)
    $dlg.Controls.Add($tbJob)

    # =========================================== ПРАВАЯ КОЛОНКА: настройки ===
    # Здесь координат больше нет: колонка ведёт себя сама, поэтому ряд готовых
    # наборов удалось вставить, ничего под ним не двигая руками.
    $R = 480; $RW = 412
    $mm = $t.M

    $rc = New-RamLayout -Container $dlg -PadX 0 -PadY 0 -Width $RW
    $rc.X = $R; $rc.Y = 66; $rc.Gap = $mm.Gap

    $capH = (Measure-RamText -Text 'Ay' -Font $t.FontSmall).Height + 2
    [void](Add-RamRow -Layout $rc -Height $capH -Gap $mm.GapSm -Items @(
        @{ Control = (New-RamLabel -Text 'ГОТОВЫЕ НАБОРЫ' -X 0 -Y 0 -Width 10 -Height $capH -Font $t.FontSmall -Color $t.Muted)
           Width   = $RW }
    ))

    # Кнопки наборов. Ключ живёт на самой кнопке, а списки обработчик находит
    # через форму по имени — так он не зависит от локалов этой функции.
    $presetBtns = @()
    foreach ($p in Get-RamAccountPresets) {
        $pb = New-RamButton -Text ([string]$p.Title) -Width 1 -Height $mm.RowHSm -Kind 'ghost' `
                            -Tooltip ([string]$p.Hint) -OnClick {
            $form = $this.FindForm()
            $key  = [string]$this.Tag.PresetKey
            $pr   = Get-RamPreset -Key $key
            if ($null -eq $pr -or $null -eq $form) { return }
            $find = { param($n) $form.Controls.Find($n, $true) | Select-Object -First 1 }
            Set-RamComboItems -Combo (& $find 'ramAccGfx')  -Items (Get-RamGraphicsChoices)   -Value $pr.Graphics
            Set-RamComboItems -Combo (& $find 'ramAccFps')  -Items (Get-RamFpsChoices)        -Value $pr.Fps
            Set-RamComboItems -Combo (& $find 'ramAccFull') -Items (Get-RamFullscreenChoices) -Value $pr.Screen
            $vc = & $find 'ramAccVol'
            if ($null -ne $vc) { Set-RamComboItems -Combo $vc -Items $vc.Tag -Value $pr.Volume }
        }
        $pb.Tag | Add-Member -NotePropertyName 'PresetKey' -NotePropertyValue ([string]$p.Key) -Force
        $presetBtns += $pb
    }
    # Столбиком во всю ширину колонки. По две в ряд надписи не влезали на
    # 150% и уезжали за край, а резать их многоточием — терять смысл кнопки.
    [void](Add-RamStack -Layout $rc -Items $presetBtns -Align 'fill' -Gap $mm.GapSm)

    $noteH = (Measure-RamText -Text 'Один щелчок ставит графику, кадры и звук. Дальше можно поправить руками.' -Font $t.FontSmall -MaxWidth $RW).Height + 2
    [void](Add-RamRow -Layout $rc -Height $noteH -Gap $mm.GapSm -Items @(
        @{ Control = (New-RamLabel -Text 'Один щелчок ставит графику, кадры и звук. Дальше можно поправить руками.' `
                                   -X 0 -Y 0 -Width 10 -Height $noteH -Font $t.FontSmall -Color $t.Muted)
           Width   = $RW }
    ))
    [void](Add-RamGap -Layout $rc -Height $mm.GapSm)

    [void](Add-RamRow -Layout $rc -Height $capH -Gap $mm.GapSm -Items @(
        @{ Control = (New-RamLabel -Text 'НАСТРОЙКИ КЛИЕНТА ДЛЯ ЭТОГО АККАУНТА' -X 0 -Y 0 -Width 10 -Height $capH -Font $t.FontSmall -Color $t.Muted)
           Width   = $RW }
    ))

    # Ширина подписей — по самой длинной, а не назначенная числом.
    $rowCaps = @('Качество графики', 'Предел кадров (FPS)', 'Режим окна', 'Громкость', 'Набор', 'Цветная метка')
    $capW = 0
    foreach ($c in $rowCaps) {
        $w = (Measure-RamText -Text $c -Font $t.FontBody).Width
        if ($w -gt $capW) { $capW = $w }
    }
    $capW += $mm.GapLg
    $fieldW = $RW - $capW - $mm.Gap

    $addRight = {
        param([string]$caption, $control)
        $h = (Measure-RamText -Text $caption -Font $t.FontBody).Height + 2
        [void](Add-RamRow -Layout $rc -VAlign 'middle' -Items @(
            @{ Control = (New-RamLabel -Text $caption -X 0 -Y 0 -Width 10 -Height $h); Width = $capW },
            @{ Control = $control; Width = $fieldW }
        ))
    }

    $cbGfx = New-RamCombo -X 0 -Y 0 -Width $fieldW -Items (Get-RamGraphicsChoices) -Value ([string]$acc.Graphics)
    $cbGfx.Name = 'ramAccGfx'
    & $addRight 'Качество графики' $cbGfx

    $cbFps = New-RamCombo -X 0 -Y 0 -Width $fieldW -Items (Get-RamFpsChoices) -Value ([string]$acc.FramerateCap)
    $cbFps.Name = 'ramAccFps'
    & $addRight 'Предел кадров (FPS)' $cbFps

    $cbFull = New-RamCombo -X 0 -Y 0 -Width $fieldW -Items (Get-RamFullscreenChoices) -Value ([string]$acc.Fullscreen)
    $cbFull.Name = 'ramAccFull'
    & $addRight 'Режим окна' $cbFull

    $volItems = @([pscustomobject]@{ Text = 'не трогать'; Value = '' })
    foreach ($v in @(0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100)) {
        $volItems += [pscustomobject]@{ Text = "$v%"; Value = [string]$v }
    }
    $cbVol = New-RamCombo -X 0 -Y 0 -Width $fieldW -Items $volItems -Value ([string]$acc.Volume)
    $cbVol.Name = 'ramAccVol'
    & $addRight 'Громкость' $cbVol

    # --- набор и метка
    [void](Add-RamGap -Layout $rc -Height $mm.GapSm)
    [void](Add-RamRow -Layout $rc -Height $capH -Gap $mm.GapSm -Items @(
        @{ Control = (New-RamLabel -Text 'НАБОР И МЕТКА' -X 0 -Y 0 -Width 10 -Height $capH -Font $t.FontSmall -Color $t.Muted)
           Width   = $RW }
    ))

    $tbGroup = New-RamTextBox -Width $fieldW -Height $mm.RowHSm -Value $acc.Group
    & $addRight 'Набор' $tbGroup

    $colorItems = @()
    foreach ($c in Get-RamLabelColors) { $colorItems += [pscustomobject]@{ Text = $c.Text; Value = $c.Key } }
    $cbColor = New-RamCombo -X 0 -Y 0 -Width $fieldW -Items $colorItems -Value ([string]$acc.Color)
    & $addRight 'Цветная метка' $cbColor

    [void](Add-RamGap -Layout $rc -Height $mm.GapSm)
    [void](Add-RamRow -Layout $rc -Height $capH -Gap $mm.GapSm -Items @(
        @{ Control = (New-RamLabel -Text 'ЗАМЕТКА — ВИДНА НА КАРТОЧКЕ' -X 0 -Y 0 -Width 10 -Height $capH -Font $t.FontSmall -Color $t.Muted)
           Width   = $RW }
    ))
    $tbNote = New-RamTextBox -Width $RW -Height $mm.RowHSm -Value $acc.Note
    [void](Add-RamRow -Layout $rc -Items @(@{ Control = $tbNote; Width = $RW }))

    # --- место окна
    $winTxt = if ([int]$acc.WindowW -gt 0) {
        "Место окна запомнено: $($acc.WindowX);$($acc.WindowY)  размер $($acc.WindowW)x$($acc.WindowH)"
    } else { 'Место окна не запомнено' }
    $winH = (Measure-RamText -Text $winTxt -Font $t.FontSmall -MaxWidth $RW).Height + 2
    $lblWin = New-RamLabel -Text $winTxt -X 0 -Y 0 -Width 10 -Height $winH -Font $t.FontSmall -Color $t.Muted
    [void](Add-RamRow -Layout $rc -Height $winH -Gap $mm.GapSm -Items @(@{ Control = $lblWin; Width = $RW }))

    $btnForgetWin = New-RamButton -Text 'Забыть место окна' -Width 1 -Height $mm.RowHSm -Kind 'ghost' -OnClick {
        $acc.WindowX = -1; $acc.WindowY = -1; $acc.WindowW = -1; $acc.WindowH = -1
        $lblWin.Text = 'Место окна не запомнено'
    }
    [void](Add-RamRow -Layout $rc -Items @($btnForgetWin))

    # ============================================================== низ ======
    # Низ считается от самой длинной колонки, а не от прежних жёстких 560:
    # правая колонка теперь растёт вместе со шрифтом, и на 125% упиралась
    # прямо в кнопку «Сохранить».
    $lowest = 0
    foreach ($c in $dlg.Controls) { if ($c.Bottom -gt $lowest) { $lowest = $c.Bottom } }

    $bar = New-RamLayout -Container $dlg -PadX 28 -PadY 0 -Width (920 - 56)
    $bar.Y = $lowest + $mm.GapLg
    $bar.Bottom = $bar.Y

    $btnSave = New-RamButton -Text 'Сохранить' -Width 1 -Height $mm.RowHLg -Kind 'primary' -OnClick {
        $this.FindForm().Tag = $true; $this.FindForm().Close()
    }
    $btnCancel = New-RamButton -Text 'Отмена' -Width 1 -Height $mm.RowHLg -OnClick {
        $this.FindForm().Tag = $false; $this.FindForm().Close()
    }
    [void](Add-RamButtonBar -Layout $bar -Primary $btnSave -Secondary @($btnCancel))
    [void](Complete-RamLayout -Layout $bar -MinWidth 920 -ClampToScreen)
    $stripe.Size = New-Object System.Drawing.Size($dlg.ClientSize.Width, $mm.StripeH)
    $dlg.Tag = $false

    if ($BuildOnly) { return $dlg }

    [void]$dlg.ShowDialog()
    $accepted = [bool]$dlg.Tag
    if (-not $accepted) { $dlg.Dispose(); return $null }

    if ([string]::IsNullOrWhiteSpace($tbCookie.Tag.Text)) {
        $dlg.Dispose()
        Show-RamError 'Без куки аккаунт запустить нельзя — ничего не сохранено.'
        return $null
    }
    if ($null -ne (ConvertTo-RamShareLink -Value $tbPlace.Tag.Text)) {
        $dlg.Dispose()
        Show-RamError 'Ссылка «Поделиться» ещё не разобрана. Открой аккаунт снова и нажми «Узнать».'
        return $null
    }

    $acc.Alias   = if ($tbAlias.Tag.Text.Trim()) { $tbAlias.Tag.Text.Trim() } else { 'Без названия' }
    $acc.Cookie  = $tbCookie.Tag.Text.Trim()
    $acc.PlaceId = ConvertTo-RamPlaceId -Value $tbPlace.Tag.Text
    $acc.JobId   = if (Test-RamJobId -Value $tbJob.Tag.Text) { $tbJob.Tag.Text.Trim() } else { '' }
    $acc.Note    = $tbNote.Tag.Text.Trim()
    $acc.Group   = $tbGroup.Tag.Text.Trim()

    $acc.Graphics     = Get-RamComboValue $cbGfx
    $acc.FramerateCap = Get-RamComboValue $cbFps
    $acc.Fullscreen   = Get-RamComboValue $cbFull
    $acc.Volume       = Get-RamComboValue $cbVol
    $acc.Color        = Get-RamComboValue $cbColor

    $lc = ConvertTo-RamLinkCode -Value $tbLink.Tag.Text
    if (-not $lc -and $tbLink.Tag.Text.Trim() -match '^[A-Za-z0-9_\-]{6,}$') { $lc = $tbLink.Tag.Text.Trim() }
    $acc.LinkCode = $lc

    $dlg.Dispose()
    return $acc
}

# ------------------------------------------------- диалог: настройки --------

function Save-RamCustomTheme {
    <#
      Кладёт свою тему в настройки. Если тема с таким ключом уже есть —
      заменяет её (это редактирование), иначе добавляет новую.
    #>
    param([Parameter(Mandatory)]$Record)

    $list = @($script:Settings.CustomThemes | Where-Object { $_ -and $_.Key -ne $Record.Key })
    $list += $Record
    $script:Settings.CustomThemes = @($list)
    Save-RamSettings -Settings $script:Settings
}

function Remove-RamCustomTheme {
    <# Удаляет свою тему по ключу. #>
    param([Parameter(Mandatory)][string]$Key)
    $script:Settings.CustomThemes = @($script:Settings.CustomThemes | Where-Object { $_ -and $_.Key -ne $Key })
    Save-RamSettings -Settings $script:Settings
}

function Draw-RamThemePreview {
    <#
      Рисует уменьшенный макет главного окна в переданных цветах. Нужен, чтобы
      конструктор показывал результат сразу, не перезапуская программу.
      Палитра лежит в $Panel.Tag.Palette (хэш Color-значений).
    #>
    param($Panel, $Graphics)

    $pal = $Panel.Tag.Palette
    if ($null -eq $pal) { return }
    $g = $Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $W = $Panel.Width; $H = $Panel.Height

    $brush = { param($col) New-Object System.Drawing.SolidBrush($col) }
    $round = {
        param($x, $y, $w, $h, $r, $col)
        $rect = New-Object System.Drawing.Rectangle($x, $y, $w, $h)
        $path = New-RamRoundRect -Rect $rect -Radius $r
        $b = & $brush $col
        $g.FillPath($b, $path); $b.Dispose(); $path.Dispose()
    }

    # фон
    $bg = & $brush $pal.Bg; $g.FillRectangle($bg, 0, 0, $W, $H); $bg.Dispose()
    # боковая панель
    $sb = & $brush $pal.Panel; $g.FillRectangle($sb, 0, 0, 108, $H); $sb.Dispose()

    $fTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $fSmall = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $fBody  = New-Object System.Drawing.Font('Segoe UI', 8)

    # логотип
    $tb = & $brush $pal.Text
    $g.DrawString('AltHub', $fTitle, $tb, 14, 12)
    # активный пункт меню
    & $round 12 40 84 26 6 $pal.Accent
    $wb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.DrawString('Аккаунты', $fSmall, $wb, 22, 46); $wb.Dispose()
    $mb = & $brush $pal.Muted
    foreach ($pair in @(@('Игры', 74), @('Профили', 96), @('Статистика', 118))) {
        $g.DrawString($pair[0], $fSmall, $mb, 22, $pair[1])
    }
    $mb.Dispose(); $tb.Dispose()

    # верхние кнопки
    & $round 122 12 74 24 6 $pal.Accent
    $wb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.DrawString('Добавить', $fSmall, $wb, 132, 18); $wb.Dispose()
    foreach ($bx in @(202, 262, 322)) {
        & $round $bx 12 52 24 6 $pal.Card
        $bb = & $brush $pal.Border
        $pen = New-Object System.Drawing.Pen($pal.Border, 1)
        $g.DrawRectangle($pen, $bx, 12, 52, 24); $pen.Dispose(); $bb.Dispose()
    }

    # карточки
    $cardX = 122; $cardW = $W - $cardX - 12
    $tb = & $brush $pal.Text; $mb = & $brush $pal.Muted; $ab = & $brush $pal.Accent
    $y = 48
    $labelCols = @($pal.Ok, $pal.Accent, $pal.Warn)
    for ($i = 0; $i -lt 3; $i++) {
        $ch = 52
        & $round $cardX $y $cardW $ch 8 $pal.Card
        # цветная метка слева
        & $round ($cardX + 3) ($y + 8) 4 ($ch - 16) 2 $labelCols[$i]
        # аватар-кружок
        $ell = & $brush $pal.CardHover
        $g.FillEllipse($ell, ($cardX + 14), ($y + 10), 30, 30); $ell.Dispose()
        # имя + ник
        $name = @('Основной', 'Твинк 1', 'Твинк 2')[$i]
        $g.DrawString($name, $fBody, $tb, ($cardX + 54), ($y + 9))
        $g.DrawString('@demo · ID 000', $fSmall, $mb, ($cardX + 54), ($y + 28))
        # статус-точка
        $dotCol = if ($i -eq 0) { $pal.Ok } else { $pal.Muted }
        $dot = & $brush $dotCol
        $g.FillEllipse($dot, ($cardX + $cardW - 118), ($y + 22), 8, 8); $dot.Dispose()
        # кнопка play
        & $round ($cardX + $cardW - 92) ($y + 12) 26 26 6 $pal.Accent
        # галочка (выделение) у второй карточки
        if ($i -eq 1) {
            & $round ($cardX + 12) ($y + 18) 16 16 5 $pal.Accent
        } else {
            $pen = New-Object System.Drawing.Pen($pal.Muted, 1.4)
            $rr = New-Object System.Drawing.Rectangle(($cardX + 12), ($y + 18), 16, 16)
            $pp = New-RamRoundRect -Rect $rr -Radius 5
            $g.DrawPath($pen, $pp); $pen.Dispose(); $pp.Dispose()
        }
        $y += $ch + 8
    }
    $tb.Dispose(); $mb.Dispose(); $ab.Dispose()

    # нижняя строка + семафор Ok/Warn/Danger как три точки
    $mb = & $brush $pal.Muted
    $g.DrawString('отмечено: 1 из 3', $fSmall, $mb, 122, ($H - 22)); $mb.Dispose()
    $sx = $W - 92
    foreach ($sem in @($pal.Ok, $pal.Warn, $pal.Danger)) {
        $sb2 = & $brush $sem; $g.FillEllipse($sb2, $sx, ($H - 20), 10, 10); $sb2.Dispose(); $sx += 16
    }

    $fTitle.Dispose(); $fSmall.Dispose(); $fBody.Dispose()
}

function Show-RamThemeConstructor {
    <#
      Конструктор своих тем.

      Простой режим: главный цвет + светлая/тёмная/чёрная основа — остальные
      15 оттенков считаются сами (New-RamDerivedPalette), результат всегда
      читаемый. Кнопка «Подробно» раскрывает ручную правку каждого цвета для
      тех, кому надо.

      Всё видно сразу в живом превью справа — перезапуск нужен только чтобы
      применить готовую тему к самому окну.

      $EditKey — ключ своей темы, которую открыли на редактирование.
      $BuildOnly — только для Самопроверки: собрать окно и вернуть, не показывая.
    #>
    param([string]$EditKey = '', [switch]$BuildOnly)

    $t = $Global:RamTheme

    # --- рабочее состояние
    $existing = $null
    if ($EditKey) { $existing = Get-RamCustomThemes | Where-Object { $_.Key -eq $EditKey } | Select-Object -First 1 }

    $state = @{
        Base    = 'dark'
        Accent  = (ConvertFrom-RamHex -Hex '#00A2FF')
        Palette = $null
        Manual  = @{}     # ключ -> Color: ручные переопределения
        Detailed = $false
    }
    if ($null -ne $existing) {
        $pal = Get-RamCustomPalette -Name $EditKey
        $state.Palette = $pal
        $state.Accent  = $pal.Accent
        # тёмная или светлая основа — по яркости фона
        $state.Base = if ((ConvertTo-RamHsl -Color $pal.Bg).L -gt 0.5) { 'light' }
                      elseif ((ConvertTo-RamHsl -Color $pal.Bg).L -lt 0.05) { 'black' }
                      else { 'dark' }
        foreach ($k in @('Bg','Panel','Card','CardHover','CardSel','Border','Text','Muted','Accent','AccentHov','Ok','Warn','Danger','DangerHov','LogBack')) {
            $state.Manual[$k] = $pal[$k]
        }
    }

    function Script:Rebuild-Palette {
        param($st)
        # Базовая палитра из акцента и основы, поверх — ручные переопределения.
        $auto = New-RamDerivedPalette -Accent $st.Accent -Base $st.Base
        foreach ($k in @($st.Manual.Keys)) { $auto[$k] = $st.Manual[$k] }
        $st.Palette = $auto
    }
    if ($null -eq $state.Palette) { Rebuild-Palette $state }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Конструктор тем'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.ForeColor       = $t.Text
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size(880, 640)

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Size = New-Object System.Drawing.Size(880, 4); $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $dlg.Controls.Add((New-RamLabel -Text 'Конструктор тем' -X 28 -Y 22 -Width 400 -Height 30 -Font $t.FontBig))

    # --- превью справа
    $preview = New-Object System.Windows.Forms.Panel
    $preview.Location = New-Object System.Drawing.Point(452, 64)
    $preview.Size     = New-Object System.Drawing.Size(400, 300)
    $preview.Tag      = [pscustomobject]@{ Palette = $state.Palette }
    Set-RamDoubleBuffered $preview
    $preview.Add_Paint({ param($src, $e) Draw-RamThemePreview -Panel $src -Graphics $e.Graphics })
    $dlg.Controls.Add($preview)
    $dlg.Controls.Add((New-RamLabel -Text 'Так будет выглядеть окно' -X 452 -Y 372 -Width 400 -Height 20 -Font $t.FontSmall -Color $t.Muted))

    $refreshPreview = {
        Rebuild-Palette $state
        $preview.Tag.Palette = $state.Palette
        $preview.Invalidate()
    }.GetNewClosure()

    # Кнопки-образцы подробной правки. Объявляем ЗДЕСЬ, до пресетов акцента:
    # их клики зовут $refreshSwatches, а замыкание запоминает переменную в
    # момент создания. $swatchButtons — хэш, поэтому заполнить его можно и
    # позже: замыкание держит ссылку на тот же объект.
    $swatchButtons = @{}
    $refreshSwatches = {
        foreach ($k in @($swatchButtons.Keys)) { $swatchButtons[$k].BackColor = $state.Palette[$k] }
    }.GetNewClosure()

    # --- имя
    $dlg.Controls.Add((New-RamLabel -Text 'Название темы' -X 28 -Y 70 -Width 200 -Height 20 -Font $t.FontSmall -Color $t.Muted))
    # Значение задаём через -Value и читаем через .Tag.Text: у панели-обёртки
    # свой собственный .Text, и запись в него не доходила до поля, а чтение
    # возвращало старое значение. Из-за этого тема всегда сохранялась под
    # именем «Моя тема», как бы её ни назвали.
    $tbName = New-RamTextBox -Width 360 -Height 30 -Value $(
        if ($null -ne $existing) { [string]$existing.Title } else { 'Моя тема' })
    $tbName.Location = New-Object System.Drawing.Point(28, 92)
    $dlg.Controls.Add($tbName)

    # --- основа
    $dlg.Controls.Add((New-RamLabel -Text 'Основа' -X 28 -Y 132 -Width 200 -Height 20 -Font $t.FontSmall -Color $t.Muted))
    $baseButtons = @{}
    $baseDefs = @(@('dark','Тёмная'), @('light','Светлая'), @('black','Чёрная'))
    $bx = 28
    foreach ($bd in $baseDefs) {
        $key = $bd[0]
        $btn = New-RamButton -Text $bd[1] -Width 116 -Height 32 -Kind $(if ($state.Base -eq $key) { 'primary' } else { 'ghost' }) -OnClick ({
            $state.Base = $this.Tag.BaseKey
            foreach ($k in $baseButtons.Keys) { Set-RamButtonKind -Button $baseButtons[$k] -Kind $(if ($k -eq $state.Base) { 'primary' } else { 'ghost' }) }
            & $refreshPreview
        }.GetNewClosure())
        $btn.Tag | Add-Member -NotePropertyName BaseKey -NotePropertyValue $key -Force
        $btn.Location = New-Object System.Drawing.Point($bx, 154)
        $dlg.Controls.Add($btn)
        $baseButtons[$key] = $btn
        # Шаг по фактической ширине: на крупном масштабе надписи длиннее и
        # кнопки налезали друг на друга.
        $bx += (Measure-RamControl -Control $btn).Width + 8
    }

    # --- акцент: пресеты + свой
    $dlg.Controls.Add((New-RamLabel -Text 'Главный цвет' -X 28 -Y 198 -Width 200 -Height 20 -Font $t.FontSmall -Color $t.Muted))
    $presets = @('#00A2FF','#8B6CFF','#10B981','#22C5D3','#A878F5','#F45E96','#FB7140','#F59E0B','#EF4444','#16A34A')
    $px = 28; $py = 220
    foreach ($hex in $presets) {
        $sw = New-Object System.Windows.Forms.Panel
        $sw.Size = New-Object System.Drawing.Size(32, 32)
        $sw.Location = New-Object System.Drawing.Point($px, $py)
        $sw.BackColor = (ConvertFrom-RamHex -Hex $hex)
        $sw.Cursor = [System.Windows.Forms.Cursors]::Hand
        $sw.Tag = $hex
        $sw.Add_Click({
            $state.Accent = (ConvertFrom-RamHex -Hex $this.Tag)
            # смена акцента сбрасывает ручную правку акцентных ключей, но не
            # трогает то, что человек уже поменял руками в других местах
            $state.Manual.Remove('Accent'); $state.Manual.Remove('AccentHov')
            & $refreshPreview
            if ($state.Detailed) { & $refreshSwatches }
        }.GetNewClosure())
        $dlg.Controls.Add($sw)
        $px += 38
        if ($px -gt 28 + 38 * 5 - 1) { $px = 28; $py += 38 }
    }

    $btnCustomAccent = New-RamButton -Text 'Свой цвет...' -Width 140 -Height 30 -Kind 'ghost' -OnClick {
        $cd = New-Object System.Windows.Forms.ColorDialog
        $cd.FullOpen = $true
        $cd.Color = $state.Accent
        if ($cd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $state.Accent = $cd.Color
            $state.Manual.Remove('Accent'); $state.Manual.Remove('AccentHov')
            & $refreshPreview
            if ($state.Detailed) { & $refreshSwatches }
        }
        $cd.Dispose()
    }.GetNewClosure()
    $btnCustomAccent.Location = New-Object System.Drawing.Point(232, 258)
    $dlg.Controls.Add($btnCustomAccent)

    # --- подробная правка (по кнопке)
    $detailHost = New-Object System.Windows.Forms.Panel
    $detailHost.Location = New-Object System.Drawing.Point(28, 300)
    $detailHost.Size     = New-Object System.Drawing.Size(384, 272)
    $detailHost.BackColor = $t.Bg
    $detailHost.Visible = $false
    $dlg.Controls.Add($detailHost)

    $keyDefs = Get-RamPaletteColorKeys
    $ry = 0
    foreach ($kd in $keyDefs) {
        $key = $kd.Key
        $lbl = New-RamLabel -Text $kd.Title -X 44 -Y ($ry + 4) -Width 250 -Height 18 -Font $t.FontSmall -Color $t.Text
        $detailHost.Controls.Add($lbl)
        $sw = New-Object System.Windows.Forms.Panel
        $sw.Size = New-Object System.Drawing.Size(28, 20)
        $sw.Location = New-Object System.Drawing.Point(0, ($ry + 2))
        $sw.BackColor = $state.Palette[$key]
        $sw.Cursor = [System.Windows.Forms.Cursors]::Hand
        $sw.Tag = $key
        $sw.Add_Click({
            $cd = New-Object System.Windows.Forms.ColorDialog
            $cd.FullOpen = $true
            $cd.Color = $state.Palette[$this.Tag]
            if ($cd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $state.Manual[$this.Tag] = $cd.Color
                & $refreshPreview
                & $refreshSwatches
            }
            $cd.Dispose()
        }.GetNewClosure())
        $detailHost.Controls.Add($sw)
        $swatchButtons[$key] = $sw
        $ry += 24
    }

    $btnDetail = New-RamButton -Text 'Подробно  ▾' -Width 150 -Height 30 -Kind 'ghost' -OnClick ({
        $state.Detailed = -not $state.Detailed
        $detailHost.Visible = $state.Detailed
        Set-RamButtonText -Button $this -Text $(if ($state.Detailed) { 'Свернуть  ▴' } else { 'Подробно  ▾' })
        if ($state.Detailed) { & $refreshSwatches }
    }.GetNewClosure())
    # Правее пресетов, над detailHost (тот появляется ниже, y=300).
    # Левее превью: оно начинается с X=430, и кнопка не должна его задевать.
    $btnDetail.Location = New-Object System.Drawing.Point(232, 220)
    $dlg.Controls.Add($btnDetail)

    # --- низ: файл + сохранить/отмена
    # Имя программы забираем ДО замыкания: внутри него $script: не виден.
    $appName = $script:AppName
    $btnToFile = New-RamButton -Text 'В файл...' -Width 130 -Height 34 -Kind 'ghost' -OnClick ({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = 'Тема AltHub (*.althub-theme.json)|*.althub-theme.json'
        $sfd.FileName = ((($tbName.Tag.Text) -replace '[^\w\-]', '_') + '.althub-theme.json')
        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $rec = ConvertTo-RamThemeRecord -Palette $state.Palette -Key ('custom-tmp') -Title ([string]$tbName.Tag.Text)
        $payload = [pscustomobject]@{ app = $appName; kind = 'theme'; theme = $rec }
        ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $sfd.FileName -Encoding UTF8
        Show-RamInfo "Тема сохранена в файл. Можешь отдать её другу — он откроет её кнопкой «Из файла...»."
    }.GetNewClosure())
    $btnToFile.Location = New-Object System.Drawing.Point(28, 588)
    $dlg.Controls.Add($btnToFile)

    $btnFromFile = New-RamButton -Text 'Из файла...' -Width 130 -Height 34 -Kind 'ghost' -OnClick ({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'Тема AltHub (*.althub-theme.json)|*.althub-theme.json|JSON (*.json)|*.json'
        if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        try {
            $data = Get-Content -LiteralPath $ofd.FileName -Raw | ConvertFrom-Json
            $th = if ($data.PSObject.Properties.Name -contains 'theme') { $data.theme } else { $data }
            if (-not ($th.PSObject.Properties.Name -contains 'Colors')) { throw 'в файле нет цветов темы' }
            $tbName.Tag.Text = [string]$th.Title
            $state.Manual = @{}
            foreach ($k in @('Bg','Panel','Card','CardHover','CardSel','Border','Text','Muted','Accent','AccentHov','Ok','Warn','Danger','DangerHov','LogBack')) {
                if ($th.Colors.PSObject.Properties.Name -contains $k) {
                    $col = ConvertFrom-RamHex -Hex ([string]$th.Colors.$k)
                    if ($null -ne $col) { $state.Manual[$k] = $col }
                }
            }
            if ($state.Manual.ContainsKey('Accent')) { $state.Accent = $state.Manual['Accent'] }
            & $refreshPreview
            if ($state.Detailed) { & $refreshSwatches }
        } catch { Show-RamError "Не получилось прочитать файл темы: $($_.Exception.Message)" }
    }.GetNewClosure())
    $btnFromFile.Location = New-Object System.Drawing.Point(164, 588)
    $dlg.Controls.Add($btnFromFile)

    $btnSave = New-RamButton -Text 'Сохранить тему' -Width 180 -Height 34 -Kind 'primary' -OnClick ({
        $title = ([string]$tbName.Tag.Text).Trim()
        if ([string]::IsNullOrWhiteSpace($title)) { Show-RamError 'Дай теме название.'; return }

        # ключ: у редактируемой — прежний, у новой — из имени + случайный хвост,
        # чтобы две темы с одинаковым именем не столкнулись
        $key = if ($EditKey) { $EditKey } else {
            'custom-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
        }
        $rec = ConvertTo-RamThemeRecord -Palette $state.Palette -Key $key -Title $title
        Save-RamCustomTheme -Record $rec
        Write-RamLog "Тема «$title» сохранена." 'ok'
        $dlg.Tag = $key
        $dlg.Close()
    }.GetNewClosure())
    $saveW2 = (Measure-RamControl -Control $btnSave).Width
    $dlg.Controls.Add($btnSave)

    $btnCancel = New-RamButton -Text 'Отмена' -Width 120 -Height 34 -OnClick { $this.FindForm().Close() }
    $cancelW = (Measure-RamControl -Control $btnCancel).Width
    $btnCancel.Location = New-Object System.Drawing.Point((880 - 28 - $cancelW), 588)
    $btnSave.Location   = New-Object System.Drawing.Point((880 - 28 - $cancelW - 12 - $saveW2), 588)
    $dlg.Controls.Add($btnCancel)

    $dlg.Tag = $null
    if ($BuildOnly) { return $dlg }

    [void]$dlg.ShowDialog()
    $key = $dlg.Tag
    $dlg.Dispose()
    return $key
}

function Show-RamSettingsDialog {
    <#
      Настройки разложены по смыслу: слева переключатель разделов, справа
      страница. Раньше это была одна простыня в 978 px высотой — одиннадцать
      галочек подряд, а колонка тем висела сбоку сама по себе, и под ней
      пустовало пол-окна. При масштабе 125% и 150% окно переставало влезать
      в экран целиком.

      Ни одной координаты числом: всё считает раскладчик из Layout.ps1, размер
      окна выводится из содержимого.
    #>
    param(
        # Только для Самопроверка.ps1: собрать окно и вернуть, не показывая.
        [switch]$BuildOnly
    )

    $t   = $Global:RamTheme
    $m   = $t.M
    $s   = $script:Settings
    $def = Get-RamDefaultSettings

    $tips = New-Object System.Windows.Forms.ToolTip
    $tips.AutoPopDelay = 15000
    $tips.InitialDelay = 400

    # ---------------------------------------------------------------- размеры
    # Ширина страницы = самая длинная подпись + галочка. Не наоборот: именно
    # подгонка текста под заранее выбранное число и давала обрезанные подписи.
    $captions = @(
        'Писать имя аккаунта в заголовок окна',
        'Поднимать аккаунт заново, если клиент вылетел',
        'Проверять входы при открытии менеджера',
        'Раскладывать окна сеткой сразу после запуска',
        'Ставить окна на запомненные для аккаунта места',
        'Ctrl+1…9 переключают окна аккаунтов',
        'Компактные карточки',
        'Показывать смайлики в названиях игр',
        'Спрашивать при закрытии менеджера',
        'Сворачивать в часы, а не в панель задач',
        'Писать журнал в файл (data\logs)'
    )
    $capW = 0
    foreach ($c in $captions) {
        $w = (Measure-RamText -Text $c -Font $t.FontBody).Width
        if ($w -gt $capW) { $capW = $w }
    }

    $probe = New-RamCheckBox -X 0 -Y 0
    $boxW  = $probe.Width
    $probe.Dispose()

    $pageW = $capW + $boxW + $m.Gap + $m.GapLg
    $minW  = [int][Math]::Round(440 * $m.Scale)
    if ($pageW -lt $minW) { $pageW = $minW }

    $navTitles = @(
        @{ Key = 'launch'; Text = 'Запуск'     },
        @{ Key = 'window'; Text = 'Окна'       },
        @{ Key = 'look';   Text = 'Вид'        },
        @{ Key = 'auto';   Text = 'Автоматика' },
        @{ Key = 'store';  Text = 'Хранилище'  },
        @{ Key = 'bridge'; Text = 'Из браузера' },
        @{ Key = 'misc';   Text = 'Прочее'     }
    )
    $navW = 0
    foreach ($n in $navTitles) {
        $w = (Measure-RamText -Text $n.Text -Font $t.FontBody).Width + $m.BtnPadX
        if ($w -gt $navW) { $navW = $w }
    }

    # ------------------------------------------------------------------ форма
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Настройки'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size(($m.PadX * 2 + $navW + $m.GapLg + $pageW), 600)

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Location  = New-Object System.Drawing.Point(0, 0)
    $stripe.Size      = New-Object System.Drawing.Size($dlg.ClientSize.Width, $m.StripeH)
    $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $root = New-RamLayout -Container $dlg
    [void](Add-RamGap -Layout $root -Height $m.StripeH)

    $titleH = (Measure-RamText -Text 'Настройки' -Font $t.FontBig).Height + 2
    [void](Add-RamRow -Layout $root -Items @(
        @{ Control = (New-RamLabel -Text 'Настройки' -X 0 -Y 0 -Width 10 -Height $titleH -Font $t.FontBig)
           Width   = $root.Width }
    ) -Height $titleH)
    [void](Add-RamGap -Layout $root -Height $m.GapSm)

    $contentY = $root.Y
    $pageX    = $root.X + $navW + $m.GapLg

    # ------------------------------------------------------- помощники страниц
    $pages   = @{}
    $navBtns = @{}

    # Страница строится с запасом по высоте, потом все выравниваются по самой
    # длинной. Иначе высоту пришлось бы задавать константой — ровно та ошибка,
    # из-за которой окно не влезало в экран при крупном масштабе.
    $newPage = {
        param([string]$key)
        $p = New-Object System.Windows.Forms.Panel
        $p.Name      = "ramPage_$key"
        $p.Location  = New-Object System.Drawing.Point($pageX, $contentY)
        $p.Size      = New-Object System.Drawing.Size($pageW, 4000)
        $p.BackColor = [System.Drawing.Color]::Transparent
        $p.Visible   = $false
        $dlg.Controls.Add($p)
        $pages[$key] = $p
        return (New-RamLayout -Container $p -PadX 0 -PadY 0 -Width $pageW)
    }

    # Заголовок группы внутри страницы.
    $addHead = {
        param($lay, [string]$text, [switch]$First)
        if (-not $First) { [void](Add-RamGap -Layout $lay -Height $m.Gap) }
        $h = (Measure-RamText -Text $text -Font $t.FontSmall).Height + 2
        [void](Add-RamRow -Layout $lay -Items @(
            @{ Control = (New-RamLabel -Text $text -X 0 -Y 0 -Width 10 -Height $h -Font $t.FontSmall -Color $t.Muted)
               Width   = $lay.Width }
        ) -Height $h -Gap $m.GapSm)
    }

    # Пояснение серым: что настройка делает и что советуется. Просил именно
    # подсказки прямо в окне, а не только всплывающие.
    $addNote = {
        param($lay, [string]$text, [int]$indent = 0)
        $w = $lay.Width - $indent
        $h = (Measure-RamText -Text $text -Font $t.FontSmall -MaxWidth $w).Height + 2
        $lb = New-RamLabel -Text $text -X 0 -Y 0 -Width 10 -Height $h -Font $t.FontSmall -Color $t.Muted
        $oldX = $lay.X; $oldW = $lay.Width
        $lay.X = $oldX + $indent; $lay.Width = $w
        [void](Add-RamRow -Layout $lay -Items @(@{ Control = $lb; Width = $w }) -Height $h -Gap $m.GapSm)
        $lay.X = $oldX; $lay.Width = $oldW
        return $lb
    }

    # Галочка с подписью и пояснением под ней.
    $addCheck = {
        param($lay, [string]$text, [bool]$checked, [string]$note)

        $cb = New-RamCheckBox -X 0 -Y 0
        $cb.Tag.Checked = $checked

        $lh = (Measure-RamText -Text $text -Font $t.FontBody).Height + 2
        $lb = New-RamLabel -Text $text -X 0 -Y 0 -Width 10 -Height $lh
        $lb.Cursor = [System.Windows.Forms.Cursors]::Hand
        $lb.Tag = $cb
        $lb.Add_Click({ $this.Tag.Tag.Checked = -not $this.Tag.Tag.Checked; $this.Tag.Invalidate() })

        $rowH = [Math]::Max($cb.Height, $lh)
        [void](Add-RamRow -Layout $lay -Items @(
            @{ Control = $cb; Width = $cb.Width },
            @{ Control = $lb; Width = ($lay.Width - $cb.Width - $m.Gap) }
        ) -Gap $m.Gap -Height $rowH -VAlign 'middle')

        if ($note) { [void](& $addNote $lay $note ($cb.Width + $m.Gap)) }
        [void](Add-RamGap -Layout $lay -Height $m.GapSm)
        return $cb
    }

    # ------------------------------------------------------------ 1. «Запуск»
    $pl = & $newPage 'launch'

    & $addHead $pl 'ТВОЁ ЖЕЛЕЗО' -First
    $adv = Get-RamHardwareAdvice
    [void](& $addNote $pl (Get-RamHardwareSummary))
    [void](& $addNote $pl $adv.Text)

    & $addHead $pl 'КАК ЗАПУСКАТЬ'

    $numDelay = New-Object System.Windows.Forms.NumericUpDown
    $numDelay.Size        = New-Object System.Drawing.Size([int](110 * $m.Scale), $m.RowHSm)
    $numDelay.BorderStyle = 'FixedSingle'
    $numDelay.BackColor   = $t.Bg
    $numDelay.ForeColor   = $t.Text
    $numDelay.Minimum = 1; $numDelay.Maximum = 120; $numDelay.Value = [int]$s.LaunchDelaySec
    [void](Add-RamRow -Layout $pl -Items @(
        @{ Control = (New-RamLabel -Text 'Пауза между запусками, сек' -X 0 -Y 0 -Width 10 `
                                   -Height ((Measure-RamText -Text 'Пауза между запусками, сек' -Font $t.FontBody).Height + 2))
           Width   = ($pl.Width - $numDelay.Width - $m.Gap) },
        @{ Control = $numDelay; Width = $numDelay.Width }
    ) -VAlign 'middle')
    [void](& $addNote $pl 'Советуем 8-10. Меньше пяти Roblox не успевает подхватить предыдущее окно, и аккаунт может не войти.')
    [void](Add-RamGap -Layout $pl -Height $m.GapSm)

    $localeItems = @(
        [pscustomobject]@{ Text = 'Русский'; Value = 'ru_ru' },
        [pscustomobject]@{ Text = 'English'; Value = 'en_us' }
    )
    $cbLocale = New-RamCombo -X 0 -Y 0 -Width ([int](170 * $m.Scale)) -Items $localeItems -Value ([string]$s.Locale)
    [void](Add-RamRow -Layout $pl -Items @(
        @{ Control = (New-RamLabel -Text 'Язык клиента Roblox' -X 0 -Y 0 -Width 10 `
                                   -Height ((Measure-RamText -Text 'Язык клиента Roblox' -Font $t.FontBody).Height + 2))
           Width   = ($pl.Width - $cbLocale.Width - $m.Gap) },
        @{ Control = $cbLocale; Width = $cbLocale.Width }
    ) -VAlign 'middle')

    & $addHead $pl 'ПОВЕДЕНИЕ'
    $cbRename  = & $addCheck $pl 'Писать имя аккаунта в заголовок окна' ([bool]$s.RenameWindows) `
                 'Окно подписывается «Roblox — Имя». Так их видно в панели задач, и менеджер узнаёт свои клиенты после перезапуска. Советуем включить.'
    $cbRestart = & $addCheck $pl 'Поднимать аккаунт заново, если клиент вылетел' ([bool]$s.AutoRestart) `
                 'Если Roblox закрылся сам, менеджер запустит его снова — до трёх раз подряд. По умолчанию выключено: при проблемах со связью даёт лишние попытки входа.'
    $cbCheck   = & $addCheck $pl 'Проверять входы при открытии менеджера' ([bool]$s.CheckOnStart) `
                 'На старте проверяет, живы ли сохранённые входы. Занимает несколько секунд, зато не узнаёшь о протухшей куке в момент запуска.'

    # -------------------------------------------------------------- 2. «Окна»
    $pw = & $newPage 'window'
    & $addHead $pw 'РАСКЛАДКА ОКОН' -First

    $numCols = New-Object System.Windows.Forms.NumericUpDown
    $numCols.Size        = New-Object System.Drawing.Size([int](110 * $m.Scale), $m.RowHSm)
    $numCols.BorderStyle = 'FixedSingle'
    $numCols.BackColor   = $t.Bg
    $numCols.ForeColor   = $t.Text
    $numCols.Minimum = 0; $numCols.Maximum = 6; $numCols.Value = [int]$s.TileColumns
    [void](Add-RamRow -Layout $pw -Items @(
        @{ Control = (New-RamLabel -Text 'Колонок в сетке' -X 0 -Y 0 -Width 10 `
                                   -Height ((Measure-RamText -Text 'Колонок в сетке' -Font $t.FontBody).Height + 2))
           Width   = ($pw.Width - $numCols.Width - $m.Gap) },
        @{ Control = $numCols; Width = $numCols.Width }
    ) -VAlign 'middle')
    [void](& $addNote $pw 'Ноль — подобрать самому под число открытых окон. Так и советуем.')
    [void](Add-RamGap -Layout $pw -Height $m.GapSm)

    $cbTile   = & $addCheck $pw 'Раскладывать окна сеткой сразу после запуска' ([bool]$s.AutoTile) `
                'Как только все клиенты поднялись, окна расставляются по экрану без наложений.'
    $cbSavedW = & $addCheck $pw 'Ставить окна на запомненные для аккаунта места' ([bool]$s.UseSavedWindows) `
                'У каждого аккаунта своё место на экране — то, где ты его оставил в прошлый раз. Перебивает общую сетку.'
    $cbHotkey = & $addCheck $pw 'Ctrl+1…9 переключают окна аккаунтов' ([bool]$s.HotkeySwitch) `
                'Быстрое переключение между клиентами с клавиатуры, не отрывая рук от игры.'

    # --------------------------------------------------------------- 3. «Вид»
    $pv = & $newPage 'look'
    & $addHead $pv 'ТЕМА ОФОРМЛЕНИЯ' -First

    $cbTheme = New-RamCombo -X 0 -Y 0 -Width $pv.Width -Items (Get-RamThemeItems) -Value ([string]$s.Theme)
    $cbTheme.Name = 'ramThemeCombo'
    [void](Add-RamRow -Layout $pv -Items @(@{ Control = $cbTheme; Width = $pv.Width }))

    # -Width 1 — «мерить по надписи». Без этого каждая берёт минимум по
    # умолчанию (150 px), и три кнопки в ряд просят 466 px при странице в 440.
    $btnNewTheme = New-RamButton -Text '＋ Своя тема' -Width 1 -Height $m.RowHSm -Kind 'ghost' `
                                 -Tooltip 'Собрать свою тему: основа, цвет акцента, всё остальное подберётся' -OnClick {
        $key = Show-RamThemeConstructor
        if ($key) {
            $cb = $this.FindForm().Controls.Find('ramThemeCombo', $true) | Select-Object -First 1
            if ($null -ne $cb) { Set-RamComboItems -Combo $cb -Items (Get-RamThemeItems) -Value $key }
        }
    }
    $btnEditTheme = New-RamButton -Text 'Изменить' -Width 1 -Height $m.RowHSm -Kind 'ghost' `
                                  -Tooltip 'Изменить выбранную свою тему' -OnClick {
        $cb = $this.FindForm().Controls.Find('ramThemeCombo', $true) | Select-Object -First 1
        $cur = Get-RamComboValue $cb
        $picked = Get-RamThemeList | Where-Object { $_.Key -eq $cur } | Select-Object -First 1
        if ($null -eq $picked -or -not $picked.Custom) {
            Show-RamInfo 'Менять можно только свои темы. Стоковые используй как основу: открой «＋ Своя тема» и настрой под себя.'
            return
        }
        $key = Show-RamThemeConstructor -EditKey $picked.Key
        if ($key) { Set-RamComboItems -Combo $cb -Items (Get-RamThemeItems) -Value $key }
    }
    $btnDelTheme = New-RamButton -Text 'Удалить' -Width 1 -Height $m.RowHSm -Kind 'ghost' `
                                 -Tooltip 'Удалить выбранную свою тему' -OnClick {
        $cb = $this.FindForm().Controls.Find('ramThemeCombo', $true) | Select-Object -First 1
        $cur = Get-RamComboValue $cb
        $picked = Get-RamThemeList | Where-Object { $_.Key -eq $cur } | Select-Object -First 1
        if ($null -eq $picked -or -not $picked.Custom) {
            Show-RamInfo 'Удалять можно только свои темы. Стоковые встроены и никуда не денутся.'
            return
        }
        if (-not (Confirm-Ram "Удалить свою тему «$($picked.Title)»?")) { return }
        Remove-RamCustomTheme -Key $picked.Key
        Set-RamComboItems -Combo $cb -Items (Get-RamThemeItems) -Value 'dark'
        Write-RamLog "Тема «$($picked.Title)» удалена." 'ok'
    }
    [void](Add-RamRow -Layout $pv -Items @($btnNewTheme, $btnEditTheme, $btnDelTheme) -Gap $m.Gap)
    [void](& $addNote $pv 'Тема применится после перезапуска менеджера — цвета запоминаются в момент отрисовки окна. Запущенные клиенты Roblox при этом не закроются.')

    & $addHead $pv 'КАРТОЧКИ АККАУНТОВ'
    $cbCompact = & $addCheck $pv 'Компактные карточки' ([bool]$s.CompactCards) `
                 'Ниже и плотнее — больше аккаунтов помещается на экран. Удобно, когда их больше десяти.'
    $cbEmoji   = & $addCheck $pv 'Показывать смайлики в названиях игр' ([bool]$s.ShowEmoji) `
                 'Выключи, если вместо значков видны пустые квадраты — так бывает на старых сборках Windows.'

    # -------------------------------------------------------- 4. «Автоматика»
    $pa = & $newPage 'auto'
    & $addHead $pa 'ЗАПУСК ПО РАСПИСАНИЮ' -First

    $tbTime = New-RamTextBox -Width ([int](150 * $m.Scale)) -Height $m.RowHSm -Value ([string]$s.AutoStartAtTime)
    $timeW  = (Measure-RamControl -Control $tbTime).Width
    [void](Add-RamRow -Layout $pa -Items @(
        @{ Control = (New-RamLabel -Text 'Время, ЧЧ:ММ' -X 0 -Y 0 -Width 10 `
                                   -Height ((Measure-RamText -Text 'Время, ЧЧ:ММ' -Font $t.FontBody).Height + 2))
           Width   = ($pa.Width - $timeW - $m.Gap) },
        @{ Control = $tbTime; Width = $timeW }
    ) -VAlign 'middle')

    $groupItems = @([pscustomobject]@{ Text = 'все аккаунты'; Value = '' })
    foreach ($g in (Get-RamGroups)) { $groupItems += [pscustomobject]@{ Text = $g; Value = $g } }
    $cbAutoGroup = New-RamCombo -X 0 -Y 0 -Width $pa.Width -Items $groupItems -Value ([string]$s.AutoStartGroup)
    [void](Add-RamField -Layout $pa -Caption 'Какой набор поднимать' -Control $cbAutoGroup)
    [void](& $addNote $pa 'Пустое время — расписание выключено. Срабатывает раз в сутки, менеджер должен быть открыт.')

    & $addHead $pa 'ПРИСМОТР'
    $watchItems = @([pscustomobject]@{ Text = 'выключен'; Value = '' })
    foreach ($g in (Get-RamGroups)) { $watchItems += [pscustomobject]@{ Text = $g; Value = $g } }
    $cbWatch = New-RamCombo -X 0 -Y 0 -Width $pa.Width -Items $watchItems -Value ([string]$s.WatchGroup)
    [void](Add-RamField -Layout $pa -Caption 'Держать в игре набор' -Control $cbWatch)
    [void](& $addNote $pa 'Каждые полминуты проверяет набор и поднимает тех, кого нет в игре. Полезно для фарма, но держит связь с Roblox постоянно.')

    # --------------------------------------------------------- 5. «Хранилище»
    $ps = & $newPage 'store'
    & $addHead $ps 'ШИФРОВАНИЕ' -First

    $mode = Get-RamStorageMode
    $modeText = switch ($mode) {
        'dpapi'  { 'Сейчас: DPAPI — привязка к твоей учётной записи Windows, пароль не нужен. Файл не откроется ни на другом компьютере, ни у другого пользователя.' }
        'aes'    { 'Сейчас: AES-256 с мастер-паролем. Файл переносится на другой компьютер, пароль спрашивается при запуске.' }
        'none'   { 'Файла ещё нет — он появится при первом сохранении и будет зашифрован DPAPI.' }
        default  { 'Не удалось определить режим шифрования.' }
    }
    $lblMode = & $addNote $ps $modeText

    $btnPwd = New-RamButton -Text 'Включить мастер-пароль' -Height $m.RowHSm -OnClick {
        $p = Show-RamPasswordDialog -Title 'Новый мастер-пароль' -Prompt 'Придумай мастер-пароль:' -Confirm
        if ($null -eq $p) { return }
        if ($p.Length -lt 4) { Show-RamError 'Слишком короткий пароль — хотя бы 4 символа.'; return }
        try {
            Save-RamAccounts -Accounts @($script:Accounts) -Password $p
            $script:MasterPassword = $p
            $lblMode.Text = 'Сейчас: AES-256 с мастер-паролем.'
            Write-RamLog 'Хранилище перешифровано под мастер-пароль.' 'ok'
            Show-RamInfo 'Готово. Теперь при запуске будет спрашиваться пароль.'
        } catch { Show-RamError $_.Exception.Message }
    }
    $btnDpapi = New-RamButton -Text 'Вернуться на DPAPI' -Height $m.RowHSm -OnClick {
        try {
            Save-RamAccounts -Accounts @($script:Accounts) -Password ''
            $script:MasterPassword = ''
            $lblMode.Text = 'Сейчас: DPAPI — привязка к твоей учётной записи Windows, пароль не нужен.'
            Write-RamLog 'Хранилище перешифровано под DPAPI.' 'ok'
            Show-RamInfo 'Готово. Пароль больше не спрашивается.'
        } catch { Show-RamError $_.Exception.Message }
    }
    [void](Add-RamRow -Layout $ps -Items @($btnPwd, $btnDpapi) -Gap $m.Gap)

    & $addHead $ps 'ПЕРЕНОС НАСТРОЕК'
    [void](& $addNote $ps 'Файл сохраняется у тебя на диске и никуда не отправляется. Внутри только названия аккаунтов и игры — кук там нет, войти по нему нельзя.')

    $btnExport = New-RamButton -Text 'Выгрузить в файл' -Height $m.RowHSm -OnClick {
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter   = 'Настройки AltHub (*.json)|*.json'
        $sfd.FileName = 'althub-setup.json'
        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        try {
            $cnt = Export-RamSetup -Path $sfd.FileName
            Write-RamLog "Настройки выгружены ($cnt аккаунтов, без кук)." 'ok'
            Show-RamInfo ("Готово. Файл сохранён у тебя на диске и никуда не отправляется.`n`n" +
                          "Пригодится для переноса на другой компьютер.`n`n" + $sfd.FileName)
        } catch { Show-RamError $_.Exception.Message }
    }
    $btnImport = New-RamButton -Text 'Загрузить из файла' -Height $m.RowHSm -OnClick {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'Настройки AltHub (*.json)|*.json'
        if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        try {
            $r = Import-RamSetup -Path $ofd.FileName
            Write-RamLog "Загружено: настроек $($r.Settings), игр $($r.Games)." 'ok'
            Show-RamInfo "Готово. Настроек применено: $($r.Settings), игр добавлено: $($r.Games).`n`nАккаунты не создавались — их надо добавить своим мастером, иначе войти будет нечем."
        } catch { Show-RamError $_.Exception.Message }
    }
    [void](Add-RamRow -Layout $ps -Items @($btnExport, $btnImport) -Gap $m.Gap)

    # ------------------------------------------------------------ 6. «Прочее»
    # -------------------------------------------------- N. «Из браузера»
    $pb = & $newPage 'bridge'
    & $addHead $pb 'ВХОД ИЗ ТВОЕГО БРАУЗЕРА' -First
    [void](& $addNote $pb ('Ты уже сидишь на roblox.com под нужным аккаунтом. Жмёшь клавишу — ' +
                           'и аккаунт в списке. Без F12 и без копирования куки.'))
    [void](& $addNote $pb ('Чтобы это заработало, в браузер надо один раз поставить расширение-мост ' +
                           'из папки extension. Иначе куку из твоего браузера не достать никак: она ' +
                           'помечена HttpOnly, скриптам со страницы не видна, а в файле браузера ' +
                           'зашифрована и заперта, пока браузер запущен. Лезть туда AltHub не будет — ' +
                           'этим занимаются программы-воришки.'))

    $cbBridge = & $addCheck $pb 'Принимать вход из браузера' ([bool]$s.BridgeEnabled) `
                ('Пока выключено, AltHub не занимает ни одного порта и принимать ему нечего. ' +
                 'Включённый приём слушает только 127.0.0.1 — петлю внутри твоего компьютера.')

    $keyItems = @()
    foreach ($k in (Get-RamBridgeHotkeyChoices)) {
        $keyItems += [pscustomobject]@{ Text = $k; Value = $k }
    }
    $cbKey = New-RamCombo -X 0 -Y 0 -Width ([int](250 * $m.Scale)) -Items $keyItems -Value ([string]$s.BridgeHotkey)
    [void](Add-RamRow -Layout $pb -VAlign 'middle' -Items @(
        @{ Control = (New-RamLabel -Text 'Клавиша приёма' -X 0 -Y 0 -Width 10 `
                                   -Height ((Measure-RamText -Text 'Клавиша приёма' -Font $t.FontBody).Height + 2))
           Width   = ($pb.Width - $cbKey.Width - $m.Gap) },
        @{ Control = $cbKey; Width = $cbKey.Width }
    ))
    [void](& $addNote $pb ('Клавиша глобальная: пока приём включён, она занята во всех программах сразу. ' +
                           'Поэтому её можно поменять — а можно вообще не пользоваться ею и жать кнопку ' +
                           'AltHub на панели браузера.'))
    [void](Add-RamGap -Layout $pb -Height $m.GapSm)

    # ЖИВОЕ СОСТОЯНИЕ, А НЕ ТОЛЬКО ГАЛОЧКА.
    # Галочка говорит, чего человек хочет. Она не говорит, получилось ли:
    # клавишу могла забрать другая программа, расширение могло быть не
    # установлено. Без этой строки оставалось только жать клавишу и гадать.
    $stateTxt = if (-not [bool]$s.BridgeEnabled) {
        'Сейчас: приём выключен, порт не занят.'
    } elseif ((Get-RamBridgePort) -le 0) {
        'Сейчас: приём включён, но порт занять не вышло — все порты диапазона заняты.'
    } elseif (Test-RamBridgeExtensionSeen) {
        "Сейчас: жду на клавише $($s.BridgeHotkey), расширение на связи. Можно пользоваться."
    } else {
        "Сейчас: жду на клавише $($s.BridgeHotkey), но расширение ещё ни разу не отзывалось — похоже, оно не установлено в браузере."
    }
    [void](& $addNote $pb $stateTxt)
    [void](Add-RamGap -Layout $pb -Height $m.GapSm)

    $bHow = New-RamButton -Text 'Как поставить расширение' -Height $m.RowH -OnClick {
        Show-RamExtensionGuide
    }
    [void](Add-RamRow -Layout $pb -Items @(@{ Control = $bHow; Width = (Measure-RamControl -Control $bHow).Width }))

    & $addHead $pb 'ОКНО БРАУЗЕРА ДЛЯ ВХОДА'
    [void](& $addNote $pb ('Отдельное окно настоящего Chrome, где ты входишь руками. Капчу, если она ' +
                           'вылезет, проходишь сам — за тебя её никто не разгадывает.'))
    if (Test-RamChromeForTestingReady) {
        [void](& $addNote $pb 'Chrome for Testing уже скачан и используется — капча в нём выпадает реже всего.')
    } else {
        [void](& $addNote $pb ('Сейчас берётся Edge или Chrome, которые у тебя уже стоят. Можно скачать ' +
                               'Chrome for Testing — официальную сборку Chromium от Google: у неё чистый ' +
                               'профиль и обычный отпечаток браузера, поэтому Roblox выдаёт самую лёгкую ' +
                               'капчу. Это ~150 МБ, и качается только по кнопке.'))
        $bCft = New-RamButton -Text 'Скачать Chrome for Testing…' -Height $m.RowH -OnClick {
            Show-RamChromeForTestingConsent
        }
        [void](Add-RamRow -Layout $pb -Items @(@{ Control = $bCft; Width = (Measure-RamControl -Control $bCft).Width }))
    }

    $pm = & $newPage 'misc'
    & $addHead $pm 'МЕНЕДЖЕР' -First
    $cbConfirm = & $addCheck $pm 'Спрашивать при закрытии менеджера' ([bool]$s.ConfirmOnExit) `
                 'Переспрашивает, если закрываешь AltHub с запущенными клиентами. Сами клиенты при этом не закрываются.'
    $cbLogFile = & $addCheck $pm 'Писать журнал в файл (data\logs)' ([bool]$s.LogToFile) `
                 'Пригодится, если что-то пойдёт не так: в журнале видно, на каком шаге сорвался запуск. Паролей и кук там нет.'

    # Две отдельные настройки вместо одной галочки: раньше «Сворачивать в часы»
    # описывало только минус, а про крестик не говорило ничего — и никто, включая
    # автора, не мог сказать наверняка, что делает каждая кнопка.
    & $addHead $pm 'КУДА ДЕВАЕТСЯ ОКНО'
    [void](& $addNote $pm 'Кнопка «свернуть» всегда сворачивает окно в панель задач — так его невозможно потерять. Настраивается только крестик.')

    $closeItems = @(
        [pscustomobject]@{ Text = 'закрыть менеджер'; Value = 'exit' },
        [pscustomobject]@{ Text = 'убрать в часы';    Value = 'tray' }
    )
    $cbOnClose = New-RamCombo -X 0 -Y 0 -Width ([int](250 * $m.Scale)) -Items $closeItems -Value ([string]$s.OnClose)
    [void](Add-RamRow -Layout $pm -VAlign 'middle' -Items @(
        @{ Control = (New-RamLabel -Text 'Крестик' -X 0 -Y 0 -Width 10 `
                                   -Height ((Measure-RamText -Text 'Крестик' -Font $t.FontBody).Height + 2))
           Width   = ($pm.Width - $cbOnClose.Width - $m.Gap) },
        @{ Control = $cbOnClose; Width = $cbOnClose.Width }
    ))
    [void](& $addNote $pm 'В часах программа продолжает работать: расписание и присмотр не останавливаются. Значок в Windows 11 может прятаться под стрелкой ^ — перетащи его оттуда, чтобы был на виду.')

    & $addHead $pm 'НАСТРОЙКИ САМОГО ROBLOX'
    [void](& $addNote $pm 'AltHub меняет графику, звук и FPS в общем файле настроек Roblox. Эта кнопка возвращает то, что было до первого запуска через менеджер.')
    $btnRestoreGfx = New-RamButton -Text 'Вернуть настройки Roblox как было' -Height $m.RowHSm -Kind 'ghost' -OnClick {
        try {
            [void](Restore-RamRobloxSettings)
            Write-RamLog 'Настройки графики и звука Roblox возвращены к исходным.' 'ok'
            Show-RamInfo 'Готово. В Roblox вернулись твои прежние графика, звук и FPS.'
        } catch { Show-RamError $_.Exception.Message }
    }
    [void](Add-RamRow -Layout $pm -Items @($btnRestoreGfx))

    # ------------------------------------------- выравнивание страниц и меню
    $pageH = 0
    foreach ($k in $pages.Keys) {
        $b = $pages[$k].Controls | ForEach-Object { $_.Bottom } | Measure-Object -Maximum
        $h = [int]$b.Maximum
        if ($h -gt $pageH) { $pageH = $h }
    }

    $navRowH = $m.RowH
    $navNeed = ($navRowH + $m.GapSm) * $navTitles.Count
    if ($navNeed -gt $pageH) { $pageH = $navNeed }

    foreach ($k in $pages.Keys) {
        $pages[$k].Size = New-Object System.Drawing.Size($pageW, $pageH)
    }

    $navLay = New-RamLayout -Container $dlg -PadX 0 -PadY 0 -Width $navW
    $navLay.X = $root.X
    $navLay.Y = $contentY
    $navLay.Gap = $m.GapSm

    foreach ($n in $navTitles) {
        $b = New-RamButton -Text ([string]$n.Text) -Width $navW -Height $navRowH -Kind 'ghost' -Fixed
        # Ключ страницы живёт на самой кнопке, а обработчик ищет всё через
        # форму. Ни одной захваченной переменной: локалы функции живут только
        # пока она на стеке, и обработчик, собранный с -BuildOnly, их уже не
        # видит — на этом переключатель разделов один раз и сломался.
        $b.Tag | Add-Member -NotePropertyName 'PageKey' -NotePropertyValue ([string]$n.Key) -Force
        $b.Add_Click({
            $form = $this.FindForm()
            if ($null -eq $form) { return }
            $want = 'ramPage_' + [string]$this.Tag.PageKey
            foreach ($c in $form.Controls) {
                if ([string]$c.Name -like 'ramPage_*') {
                    $c.Visible = ([string]$c.Name -eq $want)
                } elseif ($null -ne $c.Tag -and
                          $c.Tag.PSObject.Properties.Name -contains 'PageKey') {
                    if ([string]$c.Tag.PageKey -eq [string]$this.Tag.PageKey) {
                        Set-RamButtonKind -Button $c -Kind 'primary'
                    } else {
                        Set-RamButtonKind -Button $c -Kind 'ghost'
                    }
                }
            }
        })
        $navBtns[[string]$n.Key] = $b
        [void](Add-RamRow -Layout $navLay -Items @(@{ Control = $b; Width = $navW }) -Height $navRowH)
    }

    $root.Y = $contentY + $pageH
    $root.Bottom = $root.Y
    [void](Add-RamGap -Layout $root -Height $m.GapLg)

    $line = New-Object System.Windows.Forms.Panel
    $line.Size      = New-Object System.Drawing.Size($root.Width, 1)
    $line.BackColor = $t.Border
    [void](Add-RamRow -Layout $root -Items @(@{ Control = $line; Width = $root.Width }) -Height 1)

    # ------------------------------------------------------------------- низ
    $btnReset = New-RamButton -Text 'Вернуть рекомендованное' -Height $m.RowH -Kind 'ghost' `
                              -Tooltip 'Вернуть все переключатели к тому, что советуем по умолчанию' -OnClick {
        if (-not (Confirm-Ram "Вернуть все настройки к рекомендованным?`n`nАккаунты, игры и темы не тронутся — только переключатели в этом окне.")) { return }
        $numDelay.Value        = [int]$def.LaunchDelaySec
        $numCols.Value         = [int]$def.TileColumns
        Set-RamComboItems -Combo $cbLocale -Items $cbLocale.Tag -Value ([string]$def.Locale)
        $cbRename.Tag.Checked  = [bool]$def.RenameWindows
        $cbRestart.Tag.Checked = [bool]$def.AutoRestart
        $cbCheck.Tag.Checked   = [bool]$def.CheckOnStart
        $cbTile.Tag.Checked    = [bool]$def.AutoTile
        $cbSavedW.Tag.Checked  = [bool]$def.UseSavedWindows
        $cbHotkey.Tag.Checked  = [bool]$def.HotkeySwitch
        $cbCompact.Tag.Checked = [bool]$def.CompactCards
        $cbEmoji.Tag.Checked   = [bool]$def.ShowEmoji
        $cbConfirm.Tag.Checked = [bool]$def.ConfirmOnExit
        Set-RamComboItems -Combo $cbOnClose -Items $cbOnClose.Tag -Value ([string]$def.OnClose)
        $cbLogFile.Tag.Checked = [bool]$def.LogToFile
        foreach ($c in @($cbRename,$cbRestart,$cbCheck,$cbTile,$cbSavedW,$cbHotkey,$cbCompact,$cbEmoji,$cbConfirm,$cbLogFile)) {
            $c.Invalidate()
        }
        Show-RamInfo 'Готово. Осталось нажать «Сохранить».'
    }

    $btnOk = New-RamButton -Text 'Сохранить' -Height $m.RowH -Kind 'primary' -OnClick {
        $this.FindForm().Tag = $true; $this.FindForm().Close()
    }
    $btnNo = New-RamButton -Text 'Отмена' -Height $m.RowH -OnClick {
        $this.FindForm().Tag = $false; $this.FindForm().Close()
    }
    [void](Add-RamButtonBar -Layout $root -Primary $btnOk -Secondary @($btnNo) -Extra @($btnReset))

    $dlg.Tag = $false
    [void](Complete-RamLayout -Layout $root -ClampToScreen)
    $stripe.Size = New-Object System.Drawing.Size($dlg.ClientSize.Width, $m.StripeH)

    # Открываем первый раздел тем же путём, каким это делает нажатие в меню.
    foreach ($k in $pages.Keys) { $pages[$k].Visible = ($k -eq 'launch') }
    foreach ($k in $navBtns.Keys) {
        if ($k -eq 'launch') { Set-RamButtonKind -Button $navBtns[$k] -Kind 'primary' }
        else                 { Set-RamButtonKind -Button $navBtns[$k] -Kind 'ghost'   }
    }

    if ($BuildOnly) { return $dlg }

    [void]$dlg.ShowDialog()

    if ([bool]$dlg.Tag) {
        $s.LaunchDelaySec   = [int]$numDelay.Value
        $s.Locale           = Get-RamComboValue $cbLocale
        $s.TileColumns      = [int]$numCols.Value
        $s.RenameWindows    = [bool]$cbRename.Tag.Checked
        $s.AutoTile         = [bool]$cbTile.Tag.Checked
        $s.ConfirmOnExit    = [bool]$cbConfirm.Tag.Checked
        $s.AutoRestart      = [bool]$cbRestart.Tag.Checked
        $s.CompactCards     = [bool]$cbCompact.Tag.Checked
        $s.UseSavedWindows  = [bool]$cbSavedW.Tag.Checked
        $s.AutoStartGroup   = Get-RamComboValue $cbAutoGroup
        $s.WatchGroup       = Get-RamComboValue $cbWatch
        $s.ShowEmoji        = [bool]$cbEmoji.Tag.Checked
        $s.LogToFile        = [bool]$cbLogFile.Tag.Checked
        $s.HotkeySwitch     = [bool]$cbHotkey.Tag.Checked
        $s.OnClose          = Get-RamComboValue $cbOnClose
        $s.CheckOnStart     = [bool]$cbCheck.Tag.Checked

        # Приём из браузера включаем и выключаем СРАЗУ, не дожидаясь
        # перезапуска: иначе человек ставит галочку, жмёт клавишу — и ничего
        # не происходит, потому что порт ещё не занят.
        $bridgeWas = [bool]$s.BridgeEnabled
        $keyWas    = [string]$s.BridgeHotkey
        $s.BridgeEnabled = [bool]$cbBridge.Tag.Checked
        $s.BridgeHotkey  = Get-RamComboValue $cbKey
        if ($bridgeWas -ne $s.BridgeEnabled -or $keyWas -ne $s.BridgeHotkey) {
            Invoke-RamSafe -What 'переключение приёма из браузера' -Body { Update-RamCookieBridgeState }
        }
        $Global:RamShowEmoji = $s.ShowEmoji

        $tm = $tbTime.Tag.Text.Trim()
        if ($tm -eq '' -or $tm -match '^\d{1,2}:\d{2}$') {
            $s.AutoStartAtTime = $tm
        } else {
            Show-RamError 'Время расписания должно быть в виде ЧЧ:ММ, например 19:30. Оставил как было.'
        }

        $oldTheme = $s.Theme
        $themeKey = Get-RamComboValue $cbTheme
        $picked = Get-RamThemeList | Where-Object { $_.Key -eq $themeKey } | Select-Object -First 1
        if ($picked) { $s.Theme = $picked.Key }

        Save-RamSettings -Settings $s
        Build-RamCards
        Write-RamLog 'Настройки сохранены.' 'ok'

        if ($s.Theme -ne $oldTheme) {
            $dlg.Dispose()
            # Цвета запоминаются в момент создания кнопок и карточек, поэтому
            # тема применяется только при новом окне.
            if (Confirm-Ram "Тема «$($picked.Title)» сохранена.`n`nЧтобы она применилась, менеджер нужно перезапустить. Сделать это сейчас?`n`nЗапущенные окна Roblox не закроются.") {
                Restart-AltHub
            }
            return
        }
    }
    $dlg.Dispose()
}

# ============================================================ вход из браузера

function Show-RamExtensionGuide {
    <#
      Как поставить расширение-мост в СВОЙ браузер. Один раз, руками.

      Почему руками, а не «нажми кнопку и всё»: Chrome 137 убрал флаг
      командной строки --load-extension у обычных сборок именно затем, чтобы
      программы не подсовывали расширения молча. Ручная установка через режим
      разработчика работает по-прежнему — и это правильно: расширение получает
      доступ к куке твоего аккаунта, такое решение должен принимать человек,
      а не программа за него.
    #>
    param([switch]$BuildOnly)

    $t = $Global:RamTheme
    $m = $t.M
    $dir = Get-RamExtensionDir

    $steps = @'
Один раз, минуты на две. Дальше вход добавляется одной клавишей.

  1. Открой в браузере страницу расширений:
       Chrome  —  chrome://extensions
       Edge    —  edge://extensions
  2. Включи «Режим разработчика» (справа сверху в Chrome, слева снизу в Edge).
  3. Нажми «Загрузить распакованное» и укажи папку, путь к которой ниже.
  4. Закрепи значок AltHub рядом с адресной строкой — по нему и жать.

Готово. Теперь на любой странице roblox.com, где ты вошёл в нужный аккаунт:
жми клавишу приёма — или значок AltHub на панели браузера.
'@

    $note = @'
Что расширение может и чего не может. Оно читает ровно одну куку —
.ROBLOSECURITY с roblox.com — и отправляет её на 127.0.0.1, то есть на этот же
компьютер, запущенному AltHub. Наружу не уходит ничего: других адресов в его
коде нет, и самопроверка падает, если они появятся. Прав на другие сайты,
историю и закладки у него нет — это видно в manifest.json, он в той же папке
и открывается блокнотом.
'@

    $w = 0
    foreach ($line in (($steps + "`n" + $note) -split "`r?`n")) {
        $lw = (Measure-RamText -Text $line -Font $t.FontBody).Width
        if ($lw -gt $w) { $w = $lw }
    }
    $pageW = [Math]::Max($w + $m.GapLg, [int][Math]::Round(560 * $m.Scale))

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Расширение для входа из браузера'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.ForeColor       = $t.Text
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size(($pageW + $m.PadX * 2), 560)
    $dlg.Add_HandleCreated({ Set-RamDarkTitleBar $this })
    Set-RamWindowIcon $dlg

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Location  = New-Object System.Drawing.Point(0, 0)
    $stripe.Size      = New-Object System.Drawing.Size($dlg.ClientSize.Width, $m.StripeH)
    $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $lay = New-RamLayout -Container $dlg
    [void](Add-RamGap -Layout $lay -Height $m.StripeH)

    $titleH = (Measure-RamText -Text 'Ay' -Font $t.FontBig).Height + 2
    [void](Add-RamRow -Layout $lay -Height $titleH -Gap $m.GapSm -Items @(
        @{ Control = (New-RamLabel -Text 'Расширение-мост' -X 0 -Y 0 -Width 10 -Height $titleH -Font $t.FontBig)
           Width   = $lay.Width }
    ))

    $stepsH = (Measure-RamText -Text $steps -Font $t.FontBody -MaxWidth $lay.Width).Height + 4
    [void](Add-RamRow -Layout $lay -Height $stepsH -Items @(
        @{ Control = (New-RamLabel -Text $steps -X 0 -Y 0 -Width 10 -Height $stepsH -Font $t.FontBody)
           Width   = $lay.Width }
    ))
    [void](Add-RamGap -Layout $lay -Height $m.GapSm)

    $capH = (Measure-RamText -Text 'Ay' -Font $t.FontSmall).Height + 2
    [void](Add-RamRow -Layout $lay -Height $capH -Gap $m.GapSm -Items @(
        @{ Control = (New-RamLabel -Text 'ПАПКА РАСШИРЕНИЯ' -X 0 -Y 0 -Width 10 -Height $capH -Font $t.FontSmall -Color $t.Muted)
           Width   = $lay.Width }
    ))

    $bOpen = New-RamButton -Text 'Открыть папку' -Height $m.RowHSm -OnClick {
        $d = Get-RamExtensionDir
        if (Test-Path -LiteralPath $d) { Start-Process 'explorer.exe' -ArgumentList "`"$d`"" | Out-Null }
    }
    $bCopy = New-RamButton -Text 'Скопировать путь' -Height $m.RowHSm -OnClick {
        try { [System.Windows.Forms.Clipboard]::SetText((Get-RamExtensionDir)) } catch { }
    }
    $openW = (Measure-RamControl -Control $bOpen).Width
    $copyW = (Measure-RamControl -Control $bCopy).Width
    $tbDir = New-RamTextBox -Width ($lay.Width - $openW - $copyW - $m.Gap * 2) -Height $m.RowHSm -Value $dir
    $tbDir.Tag.ReadOnly = $true
    [void](Add-RamRow -Layout $lay -VAlign 'middle' -Items @(
        @{ Control = $tbDir; Width = ($lay.Width - $openW - $copyW - $m.Gap * 2) },
        @{ Control = $bOpen; Width = $openW },
        @{ Control = $bCopy; Width = $copyW }
    ))
    [void](Add-RamGap -Layout $lay -Height $m.Gap)

    $noteH = (Measure-RamText -Text $note -Font $t.FontSmall -MaxWidth $lay.Width).Height + 4
    [void](Add-RamRow -Layout $lay -Height $noteH -Items @(
        @{ Control = (New-RamLabel -Text $note -X 0 -Y 0 -Width 10 -Height $noteH -Font $t.FontSmall -Color $t.Muted)
           Width   = $lay.Width }
    ))

    [void](Add-RamGap -Layout $lay -Height $m.Gap)
    $bClose = New-RamButton -Text 'Понятно' -Height $m.RowHLg -Kind 'primary' -OnClick { $this.FindForm().Close() }
    [void](Add-RamButtonBar -Layout $lay -Primary $bClose)
    [void](Complete-RamLayout -Layout $lay -ClampToScreen)
    $stripe.Size = New-Object System.Drawing.Size($dlg.ClientSize.Width, $m.StripeH)

    if ($BuildOnly) { return $dlg }
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

function Show-RamChromeForTestingConsent {
    <#
      Согласие на скачивание Chrome for Testing. Отдельное окно, а не молчаливая
      закачка: ~150 МБ чужого исполняемого файла, который программа потом сама
      же и запустит, — это ровно то, о чём человека надо спросить прямо.

      Никакого «мы уже скачали, вот кнопка отмены»: до нажатия «Скачать» в сеть
      за ним не уходит ни одного запроса.
    #>
    param([switch]$BuildOnly)

    $t = $Global:RamTheme
    $m = $t.M

    $body = @'
Зачем. Для способа «окно браузера» AltHub открывает настоящий Chrome, где ты
входишь руками. Roblox выдаёт капчу тем сложнее, чем подозрительнее ему кажется
браузер. У Chrome for Testing обычный отпечаток настоящего Chrome и свой чистый
профиль, поэтому капча выпадает реже всего — а часто и вовсе не выпадает.

Что качается. Chrome for Testing — официальная сборка Chromium, которую
выпускает сама Google. Примерно 150 МБ, один раз, в папку data\chrome-for-testing
рядом с программой. Твой обычный Chrome или Edge при этом не трогаются.

Откуда качается. Список сборок — с googlechromelabs.github.io, сам архив — с
storage.googleapis.com. Это единственные два адреса за пределами roblox.com, на
которые AltHub вообще может обратиться, и только по этой кнопке.

Можно и не качать. Без него вход через окно браузера тоже работает — возьмётся
Edge или Chrome, которые у тебя уже стоят. Просто капча будет попадаться чаще.
Все остальные способы добавить аккаунт от этого не зависят вовсе.
'@

    $w = 0
    foreach ($line in ($body -split "`r?`n")) {
        $lw = (Measure-RamText -Text $line -Font $t.FontBody).Width
        if ($lw -gt $w) { $w = $lw }
    }
    $pageW = [Math]::Max($w + $m.GapLg, [int][Math]::Round(560 * $m.Scale))

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Скачать Chrome for Testing?'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.ForeColor       = $t.Text
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size(($pageW + $m.PadX * 2), 480)
    $dlg.Add_HandleCreated({ Set-RamDarkTitleBar $this })
    Set-RamWindowIcon $dlg

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Location  = New-Object System.Drawing.Point(0, 0)
    $stripe.Size      = New-Object System.Drawing.Size($dlg.ClientSize.Width, $m.StripeH)
    $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $lay = New-RamLayout -Container $dlg
    [void](Add-RamGap -Layout $lay -Height $m.StripeH)

    $titleH = (Measure-RamText -Text 'Ay' -Font $t.FontBig).Height + 2
    [void](Add-RamRow -Layout $lay -Height $titleH -Gap $m.GapSm -Items @(
        @{ Control = (New-RamLabel -Text 'Скачать Chrome for Testing?' -X 0 -Y 0 -Width 10 -Height $titleH -Font $t.FontBig)
           Width   = $lay.Width }
    ))

    $bodyH = (Measure-RamText -Text $body -Font $t.FontBody -MaxWidth $lay.Width).Height + 4
    [void](Add-RamRow -Layout $lay -Height $bodyH -Items @(
        @{ Control = (New-RamLabel -Text $body -X 0 -Y 0 -Width 10 -Height $bodyH -Font $t.FontBody -Color $t.Muted)
           Width   = $lay.Width }
    ))

    [void](Add-RamGap -Layout $lay -Height $m.Gap)
    $bGo = New-RamButton -Text 'Скачать (~150 МБ)' -Height $m.RowHLg -Kind 'primary' -OnClick {
        $this.FindForm().Tag = $true; $this.FindForm().Close()
    }
    $bNo = New-RamButton -Text 'Не надо' -Height $m.RowHLg -OnClick {
        $this.FindForm().Tag = $false; $this.FindForm().Close()
    }
    [void](Add-RamButtonBar -Layout $lay -Primary $bGo -Secondary @($bNo))
    [void](Complete-RamLayout -Layout $lay -ClampToScreen)
    $stripe.Size = New-Object System.Drawing.Size($dlg.ClientSize.Width, $m.StripeH)
    $dlg.Tag = $false

    if ($BuildOnly) { return $dlg }
    [void]$dlg.ShowDialog()
    $agreed = [bool]$dlg.Tag
    $dlg.Dispose()
    if (-not $agreed) { return $false }

    return (Request-RamChromeForTesting)
}

function Show-RamAddChooser {
    <#
      Экран «Добавить аккаунты». То, что открывается по кнопке «＋ Добавить».

      ПОЧЕМУ ТАК. Способов добавить аккаунт много, и это осознанно: если один
      перестанет работать (Roblox уже закрывал вход по паролю), должны остаться
      другие. Но вываливать все семь одинаковыми строками — значит заставлять
      человека выбирать из того, в чём он не разбирается. Поэтому три главные
      кнопки крупно, поле для вставки под ними, а остальное — под «Ещё способы»:
      выбор не уменьшился, но глаза больше не разбегаются.
    #>
    param([switch]$BuildOnly)

    $t = $Global:RamTheme
    $m = $t.M

    $ways = @(
        @{ Title = 'Окно браузера'
           Note  = 'Открою настоящий Chrome, войдёшь руками. Лучший способ для твинков: пароль остаётся между тобой и Roblox, капчу, если вылезет, проходишь сам.'
           Key   = 'window' },
        @{ Title = 'Из приложения Roblox'
           Note  = 'Возьму тот вход, под которым ты уже сидишь в самом Roblox. Пароль не нужен вовсе — удобнее всего для основного аккаунта.'
           Key   = 'app' },
        @{ Title = 'Из своего браузера, по клавише'
           Note  = 'Ты уже открыл roblox.com под нужным аккаунтом — жмёшь клавишу, и он здесь. Нужно один раз поставить расширение-мост.'
           Key   = 'bridge' }
    )

    # Ширина — от самой длинной пояснительной строки, а не назначена числом.
    $pageW = [int][Math]::Round(600 * $m.Scale)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Добавить аккаунты'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.ForeColor       = $t.Text
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size(($pageW + $m.PadX * 2), 640)
    $dlg.Add_HandleCreated({ Set-RamDarkTitleBar $this })
    Set-RamWindowIcon $dlg

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Location  = New-Object System.Drawing.Point(0, 0)
    $stripe.Size      = New-Object System.Drawing.Size($dlg.ClientSize.Width, $m.StripeH)
    $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $lay = New-RamLayout -Container $dlg
    [void](Add-RamGap -Layout $lay -Height $m.StripeH)

    $titleH = (Measure-RamText -Text 'Ay' -Font $t.FontBig).Height + 2
    [void](Add-RamRow -Layout $lay -Height $titleH -Gap $m.GapSm -Items @(
        @{ Control = (New-RamLabel -Text 'Добавить аккаунты' -X 0 -Y 0 -Width 10 -Height $titleH -Font $t.FontBig)
           Width   = $lay.Width }
    ))

    $bigH = [int][Math]::Round($m.RowHLg * 1.35)
    $first = $true
    foreach ($way in $ways) {
        # Яркая только первая: три одинаково кричащие кнопки не помогают
        # выбрать, а наоборот — глазу не за что зацепиться.
        $kind = if ($first) { 'primary' } else { 'normal' }
        $first = $false
        $b = New-RamButton -Text $way.Title -Height $bigH -Kind $kind
        $b.Tag | Add-Member -NotePropertyName WayKey -NotePropertyValue $way.Key -Force
        $b.Add_Click({
            $f = $this.FindForm()
            $f.Tag = $this.Tag.WayKey
            $f.Close()
        })
        [void](Add-RamRow -Layout $lay -Height $bigH -Gap $m.GapSm -Items @(
            @{ Control = $b; Width = $lay.Width }
        ))
        $nh = (Measure-RamText -Text $way.Note -Font $t.FontSmall -MaxWidth $lay.Width).Height + 2
        [void](Add-RamRow -Layout $lay -Height $nh -Items @(
            @{ Control = (New-RamLabel -Text $way.Note -X 0 -Y 0 -Width 10 -Height $nh -Font $t.FontSmall -Color $t.Muted)
               Width   = $lay.Width }
        ))
    }

    # ------------------------------------------------------------- поле вставки
    [void](Add-RamGap -Layout $lay -Height $m.Gap)
    $capH = (Measure-RamText -Text 'Ay' -Font $t.FontSmall).Height + 2
    [void](Add-RamRow -Layout $lay -Height $capH -Gap $m.GapSm -Items @(
        @{ Control = (New-RamLabel -Text 'ИЛИ ПРОСТО ВСТАВЬ СЮДА' -X 0 -Y 0 -Width 10 -Height $capH -Font $t.FontSmall -Color $t.Muted)
           Width   = $lay.Width }
    ))
    $hint = 'Одна кука, список кук по строке на каждую или приглашение althub:// — разберусь само.'
    $hh = (Measure-RamText -Text $hint -Font $t.FontSmall -MaxWidth $lay.Width).Height + 2
    [void](Add-RamRow -Layout $lay -Height $hh -Gap $m.GapSm -Items @(
        @{ Control = (New-RamLabel -Text $hint -X 0 -Y 0 -Width 10 -Height $hh -Font $t.FontSmall -Color $t.Muted)
           Width   = $lay.Width }
    ))

    $boxH = [int][Math]::Round(96 * $m.Scale)
    $tbPaste = New-RamTextBox -Width $lay.Width -Height $boxH -Value '' -Multiline
    [void](Add-RamRow -Layout $lay -Height $boxH -Items @(@{ Control = $tbPaste; Width = $lay.Width }))
    [void](Add-RamGap -Layout $lay -Height $m.GapSm)

    $bPaste = New-RamButton -Text 'Добавить из поля' -Height $m.RowH -OnClick ({
        $txt = $tbPaste.Tag.Text
        if ([string]::IsNullOrWhiteSpace($txt)) {
            Show-RamMessage -Message 'Поле пустое. Вставь туда куку или список кук.'
            return
        }
        $r = Import-RamAccountBatch -Text $txt
        Save-RamState
        Build-RamCards
        $tbPaste.Tag.Text = ''
        $parts = @()
        if ($r.Added   -gt 0) { $parts += "добавлено: $($r.Added)" }
        if ($r.Updated -gt 0) { $parts += "обновлено: $($r.Updated)" }
        if ($r.Failed  -gt 0) { $parts += "не вышло: $($r.Failed)" }
        $msg = if ($parts.Count) { ($parts -join ', ') } else { 'ничего не разобрал' }
        if ($r.Failed -gt 0 -and $r.Errors.Count -gt 0) {
            $msg += [Environment]::NewLine + [Environment]::NewLine + 'Почему не вышло:' + [Environment]::NewLine +
                    (($r.Errors | Select-Object -Unique -First 4) -join [Environment]::NewLine)
        }
        Show-RamMessage -Message $msg
    }.GetNewClosure())

    $bMore = New-RamButton -Text 'Ещё способы  ▾' -Height $m.RowH -Kind 'ghost'
    $moreMenu = New-RamContextMenu
    [void](Add-RamMenuItem -Menu $moreMenu -Text 'Из браузера через F12 — покажу по шагам' -OnClick {
        [void](Show-RamBrowserGuide)
        Build-RamCards
    })
    [void](Add-RamMenuItem -Menu $moreMenu -Text 'Вставить пачкой, в отдельном окне' -OnClick {
        [void](Show-RamBatchAddDialog)
        Build-RamCards
    })
    [void](Add-RamMenuItem -Menu $moreMenu -Separator)
    [void](Add-RamMenuItem -Menu $moreMenu -Text 'Из файла (список кук или приглашений)...' -OnClick {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'Текст или JSON (*.txt;*.json)|*.txt;*.json|Все файлы (*.*)|*.*'
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            Import-RamDroppedFile -Path $ofd.FileName
            Build-RamCards
        }
    })
    $bMore.Add_Click({ $moreMenu.Show($this, (New-Object System.Drawing.Point(0, $this.Height))) }.GetNewClosure())

    $bDone = New-RamButton -Text 'Готово' -Height $m.RowH -OnClick { $this.FindForm().Close() }

    $pw = (Measure-RamControl -Control $bPaste).Width
    $mw = (Measure-RamControl -Control $bMore).Width
    $dw = (Measure-RamControl -Control $bDone).Width
    # «Готово» — своей шириной у правого края, а не растянутое на весь
    # остаток строки: растянутая кнопка выглядит главной, хотя это выход.
    $spacer = New-Object System.Windows.Forms.Panel
    $spacer.BackColor = [System.Drawing.Color]::Transparent
    [void](Add-RamRow -Layout $lay -VAlign 'middle' -Items @(
        @{ Control = $bPaste;  Width = $pw },
        @{ Control = $bMore;   Width = $mw },
        @{ Control = $spacer;  Width = [Math]::Max(0, ($lay.Width - $pw - $mw - $dw - $m.Gap * 3)) },
        @{ Control = $bDone;   Width = $dw }
    ))

    [void](Complete-RamLayout -Layout $lay -ClampToScreen)
    $stripe.Size = New-Object System.Drawing.Size($dlg.ClientSize.Width, $m.StripeH)
    $dlg.Tag = ''

    if ($BuildOnly) { return $dlg }

    [void]$dlg.ShowDialog()
    $choice = [string]$dlg.Tag
    $dlg.Dispose()

    switch ($choice) {
        'window' {
            $cookie = $null
            try {
                $cookie = Show-RamExternalBrowserLoginWindow
            } catch {
                Write-RamLog "Окно входа: $($_.Exception.Message)" 'err'
                Show-RamError -Text ('Не удалось открыть окно входа:' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message)
                return
            }
            if ($cookie) {
                $r = Import-RamAccountLine -Line $cookie
                if ($r -and $r.Ok) {
                    Save-RamState; Build-RamCards
                    Write-RamLog "Через окно браузера добавлен аккаунт: $($r.Alias)" 'ok'
                    Show-RamMessage -Message "Готово: $($r.Alias)"
                } else {
                    $why = if ($r -and $r.Error) { $r.Error } else { 'неизвестная ошибка' }
                    Show-RamError -Text ('Вход прошёл, но аккаунт не добавился:' + [Environment]::NewLine + [Environment]::NewLine + $why)
                }
            } else {
                Write-RamLog 'Окно входа закрыто без получения входа.' 'warn'
            }
        }
        'app' {
            Show-RamAddWizard
        }
        'bridge' {
            Show-RamBridgeHowTo
        }
    }
}

function Show-RamBridgeHowTo {
    <#
      Что делать, если человек выбрал «из своего браузера». Либо приём уже
      включён и расширение стоит — тогда просто напоминаем клавишу, либо
      ведём к настройке. Разбираем случаи честно, а не показываем одну
      инструкцию всем подряд.
    #>
    if (-not [bool]$script:Settings.BridgeEnabled) {
        if (Confirm-Ram ('Приём из браузера сейчас выключен.' + [Environment]::NewLine + [Environment]::NewLine +
                         'Включить его и показать, как поставить расширение-мост в браузер? Это делается один раз.')) {
            $script:Settings.BridgeEnabled = $true
            Save-RamSettings -Settings $script:Settings
            Invoke-RamSafe -What 'включение приёма из браузера' -Body { Update-RamCookieBridgeState }
            Show-RamExtensionGuide
        }
        return
    }

    if (-not (Test-RamBridgeExtensionSeen)) {
        Show-RamExtensionGuide
        return
    }

    $key = [string]$script:Settings.BridgeHotkey
    Show-RamMessage -Message ('Всё готово.' + [Environment]::NewLine + [Environment]::NewLine +
                              "Открой roblox.com под нужным аккаунтом и нажми $key — или значок AltHub на панели браузера.")
}
