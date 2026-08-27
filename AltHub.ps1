#requires -Version 5.1
<#
================================================================================
 AltHub — менеджер аккаунтов Roblox
================================================================================
 Автор: Эрнест Костевич (Ernest Kostevich)
 Версия: 1.0
 Лицензия: MIT — см. файл LICENSE рядом. Можно свободно передавать друзьям,
 менять под себя и распространять дальше, сохраняя это указание авторства.

 Запуск нескольких аккаунтов Roblox одновременно, каждый в своём окне,
 каждый в нужной игре.

 Ничего не устанавливается, ничего не скачивается, ничего не компилируется.
 Это обычные текстовые .ps1-файлы — открой любым блокнотом и прочитай.

 Запускать через "Запустить.cmd" (или: powershell -ExecutionPolicy Bypass
 -STA -File AltHub.ps1).

 Разбор по файлам:
   modules\Storage.ps1      — шифрование и хранение аккаунтов на диске
   modules\RobloxApi.ps1    — ЕДИНСТВЕННЫЙ файл, который ходит в сеть
   modules\CookieImport.ps1 — забирает куку из открытого приложения Roblox
   modules\RobloxSettings.ps1 — графика, звук и FPS для каждого аккаунта
   modules\Hotkeys.ps1      — глобальные Ctrl+1..9 и значок в часах
   modules\Launcher.ps1     — мультизапуск и старт клиента
   modules\WindowTools.ps1  — заголовки и раскладка окон
   modules\Theme.ps1        — тёмное оформление, только внешний вид
================================================================================
#>

[CmdletBinding()]
param(
    # Только для проверочных скриптов: загрузить функции, но не открывать окно.
    # В этом режиме запись в dataccounts.dat ЗАПРЕЩЕНА — см. Save-RamState.
    [switch]$NoAutoStart
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Root = $PSScriptRoot
. (Join-Path $script:Root 'modules\Theme.ps1')
. (Join-Path $script:Root 'modules\Storage.ps1')
. (Join-Path $script:Root 'modules\RobloxApi.ps1')
. (Join-Path $script:Root 'modules\CookieImport.ps1')
. (Join-Path $script:Root 'modules\Hotkeys.ps1')
. (Join-Path $script:Root 'modules\RobloxSettings.ps1')
. (Join-Path $script:Root 'modules\Launcher.ps1')
. (Join-Path $script:Root 'modules\WindowTools.ps1')

# ------------------------------------------------------------ состояние -----

$script:Accounts       = @()      # список аккаунтов
$script:Settings       = $null    # настройки
$script:MasterPassword = ''       # пустая строка = режим DPAPI
$script:UI             = @{}      # ссылки на элементы главного окна
$script:Cards          = @{}      # Id аккаунта -> элементы его карточки
$script:Instances      = @{}      # Id аккаунта -> запущенный клиент
$script:LaunchQueue    = New-Object System.Collections.ArrayList
$script:AvatarQueue    = New-Object System.Collections.ArrayList
$script:NextLaunchTime = [datetime]::MinValue
$script:PlayerPath     = ''
$script:Filter         = ''       # текст поиска по аккаунтам
$script:GroupFilter    = ''       # выбранный набор, пусто = все
$script:DragId         = ''       # что тащим мышью
$script:DragStart      = 0
$script:DragMoved      = $false
$script:Section        = 'accounts'
$script:LastScheduleRun = ''
$script:UndoStack       = New-Object System.Collections.ArrayList  # шаги для Ctrl+Z
$script:StatusHoldUntil = [datetime]::MinValue                     # см. Set-RamStatus
$script:PendingTileUntil = [datetime]::MinValue                    # см. Invoke-RamPendingTile
$script:SettingsTouched = $false   # трогали ли общий файл настроек Roblox
$script:LastLaunchAt    = [datetime]::MinValue
$script:RestartCount   = @{}      # Id аккаунта -> сколько раз перезапускали

# Режим «только чтение». Включается вместе с -NoAutoStart, то есть во всех
# проверочных и диагностических скриптах. Нужен потому, что обработчик закрытия
# окна вызывает Save-RamState — и тестовый прогон, собравший окно с выдуманными
# аккаунтами, при закрытии записал бы их поверх настоящих. Один раз так и
# случилось; теперь это невозможно.
$script:ReadOnly = [bool]$NoAutoStart

$script:AppName    = 'AltHub'
$script:AppVersion = '1.0'
$script:AppAuthor  = 'Эрнест Костевич'

function Get-RamAvatarDir { Join-Path (Get-RamDataDir) 'avatars' }

# ------------------------------------------------------------- утилиты ------

function Write-RamLog {
    <# Пишем в окно журнала. Куки в журнал не попадают: любая строка, похожая
       на .ROBLOSECURITY, режется перед выводом. #>
    param([string]$Message, [string]$Level = 'info')

    $safe = $Message -replace '_\|WARNING[^\s]*', '<кука скрыта>'
    $safe = $safe    -replace '[A-Za-z0-9_\-]{200,}', '<длинный токен скрыт>'
    # Журнал моноширинный, подстановки шрифта в нём нет — смайлики из
    # названий игр вырезаем, иначе будут квадратики.
    $safe = Remove-RamEmoji -Text $safe   # журнал моноширинный, смайликам там не место

    $prefix = switch ($Level) {
        'ok'    { '+' }
        'err'   { '!' }
        'warn'  { '~' }
        default { ' ' }
    }
    $line = '{0} [{1}] {2}' -f (Get-Date).ToString('HH:mm:ss'), $prefix, $safe

    if ($script:UI.ContainsKey('Log') -and $null -ne $script:UI.Log) {
        $script:UI.Log.AppendText($line + [Environment]::NewLine)
    }

    Write-RamLogFile -Line $line
}

function Get-RamLogDir {
    $dir = Join-Path (Get-RamDataDir) 'logs'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Write-RamLogFile {
    <#
      Дублируем журнал в файл data\logs\ГГГГ-ММ-ДД.log — чтобы наутро можно
      было понять, что случилось ночью.
      Строка сюда приходит УЖЕ очищенной от кук (см. Write-RamLog), так что
      в файл секреты не попадают.
    #>
    param([string]$Line)

    if ($null -eq $script:Settings) { return }
    if (-not $script:Settings.LogToFile) { return }
    if ($script:ReadOnly) { return }

    try {
        $path = Join-Path (Get-RamLogDir) ((Get-Date).ToString('yyyy-MM-dd') + '.log')
        Add-Content -LiteralPath $path -Value $Line -Encoding UTF8
    } catch { }
}

function Remove-RamOldLogs {
    <# Держим журналы за две недели, старое чистим — папка не должна расти вечно. #>
    param([int]$KeepDays = 14)
    try {
        $limit = (Get-Date).AddDays(-$KeepDays)
        Get-ChildItem -LiteralPath (Get-RamLogDir) -Filter '*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $limit } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Set-RamStatus {
    <#
      Разовое сообщение в строке внизу. Держится 6 секунд, потом строку снова
      забирает Update-RamStatusLine — иначе живая строка затирала бы сообщение
      на ближайшем же тике таймера, и прочитать его никто бы не успел.
    #>
    param([string]$Text)
    if ($script:UI.ContainsKey('Status') -and $null -ne $script:UI.Status) {
        $script:UI.Status.Text  = $Text
        $script:StatusHoldUntil = (Get-Date).AddSeconds(6)
        $script:UI.Status.Refresh()
    }
}

function Update-RamLoginButton {
    <#
      Кнопка состояния входов внизу справа.

      Она ВСЕГДА на месте и только меняет вид. Раньше она пряталась, когда
      чинить нечего, и от этого дёргалась: появлялась и исчезала на каждом
      тике таймера, а на перерисовке оставляла след. Плюс её видимость
      обновлялась в общей строке состояния — а та на шесть секунд замирает,
      пока показывает разовое сообщение, и кнопка отставала от жизни.

      Теперь у неё два состояния:
        есть мёртвые  -> красная «Починить входы (N)»
        всё живо      -> тихая «Проверить входы»
    #>
    if (-not $script:UI.ContainsKey('FixAll') -or $null -eq $script:UI.FixAll) { return }

    $btn  = $script:UI.FixAll
    $dead = @($script:Accounts | Where-Object { [string]$_.CookieOk -eq 'no' }).Count

    # Перерисовываем только при смене состояния: иначе Invalidate дёргается
    # каждые две секунды по таймеру.
    $mode = if ($dead -gt 0) { "fix:$dead" } else { 'check' }
    if ($btn.Tag.Mode -eq $mode) { return }
    $btn.Tag.Mode = $mode

    if ($dead -gt 0) {
        Set-RamButtonText -Button $btn -Text "Починить входы ($dead)"
        Set-RamButtonKind -Button $btn -Kind 'danger'
    } else {
        Set-RamButtonText -Button $btn -Text 'Проверить входы'
        Set-RamButtonKind -Button $btn -Kind 'ghost'
    }
}

function Update-RamStatusLine {
    <#
      Живая строка внизу: сколько отмечено, кто в игре, что в очереди, сколько
      мёртвых входов и что вернёт Ctrl+Z. Зовётся при каждом изменении списка
      и по таймеру обновления.
    #>
    if ($null -eq $script:Settings) { return }

    # Кнопка входов — до проверки на замирание: она к разовым сообщениям
    # отношения не имеет и отставать от них не должна.
    Update-RamLoginButton

    if (-not $script:UI.ContainsKey('Status') -or $null -eq $script:UI.Status) { return }
    if ((Get-Date) -lt $script:StatusHoldUntil) { return }   # держим сообщение

    $all     = @($script:Accounts).Count
    $checked = @(Get-RamTargetAccounts).Count
    $dead    = @($script:Accounts | Where-Object { [string]$_.CookieOk -eq 'no' }).Count
    $running = $script:Instances.Count
    $queued  = $script:LaunchQueue.Count

    $parts = @()
    if ($all -eq 0) { $parts += 'аккаунтов пока нет — нажми «Добавить»' }
    else            { $parts += "отмечено: $checked из $all" }

    if ($running -gt 0) { $parts += "в игре: $running" }
    if ($queued  -gt 0) {
        $left = [int][Math]::Max(0, ($script:NextLaunchTime - (Get-Date)).TotalSeconds)
        $parts += "в очереди: $queued, следующий через $left с"
    }
    if ($dead -gt 0) {
        $parts += $(if ($dead -eq 1) { 'мёртвый вход: 1' } else { "мёртвых входов: $dead" })
    }
    if ($script:UndoStack.Count -gt 0) {
        $parts += "Ctrl+Z вернёт: $($script:UndoStack[$script:UndoStack.Count - 1].Label)"
    }

    $script:UI.Status.Text = ($parts -join '   •   ')
}

function Update-RamHeaderCounts {
    if (-not $script:UI.ContainsKey('Subtitle')) { return }
    $n = @($script:Accounts).Count
    $r = $script:Instances.Count
    $q = $script:LaunchQueue.Count
    $txt = "аккаунтов: $n   •   запущено: $r"
    if ($q -gt 0) { $txt += "   •   в очереди: $q" }
    if (-not [string]::IsNullOrWhiteSpace($script:Filter)) {
        $txt += "   •   показано: $($script:Cards.Count)"
    }
    if ($script:Settings -and $script:Settings.AutoRestart) { $txt += "   •   автоперезапуск вкл" }
    $script:UI.Subtitle.Text = $txt
}

# ------------------------------------------------------ тёмные диалоги ------

function Get-RamDialogButtonWidth {
    <# Ширина кнопки диалога под её надпись. Отдельно, чтобы ширину окна и
       ширину самих кнопок считало одно и то же место. #>
    param([Parameter(Mandatory)][string]$Text)
    return [System.Windows.Forms.TextRenderer]::MeasureText($Text, $Global:RamTheme.FontBody).Width + 34
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
        $bw    = [Math]::Max(110, (Get-RamDialogButtonWidth -Text $b.Text))

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
        [object[]]$Buttons = @()
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
        foreach ($b in $Buttons) { $need += [Math]::Max(110, (Get-RamDialogButtonWidth -Text $b.Text)) + 8 }
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
        $yes.Location = New-Object System.Drawing.Point(($width - 244), $btnY)
        $dlg.Controls.Add($yes)

        $no = New-RamButton -Text 'Отмена' -Width 110 -Height 34 -OnClick {
            $this.FindForm().Tag = $false
            $this.FindForm().Close()
        }
        $no.Location = New-Object System.Drawing.Point(($width - 126), $btnY)
        $dlg.Controls.Add($no)

        $dlg.Tag = $false
    } else {
        $ok = New-RamButton -Text 'Понятно' -Width 130 -Height 34 -Kind 'primary' -OnClick {
            $this.FindForm().Close()
        }
        $ok.Location = New-Object System.Drawing.Point(($width - 154), $btnY)
        $dlg.Controls.Add($ok)
    }

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
        [object[]]$Suggestions = @()
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

    $boxWidth = if ($Password) { 472 } else { 360 }
    $box = New-RamTextBox -Width $boxWidth -Height 34 -Value $Value
    $box.Location = New-Object System.Drawing.Point(24, $boxY)
    if ($Password) { $box.Tag.UseSystemPasswordChar = $true }
    $dlg.Controls.Add($box)

    if (-not $Password) {
        # Ctrl+V работает, но кнопка нагляднее — особенно когда длинную ссылку
        # копируешь из браузера и не хочешь промахнуться мимо поля.
        $btnPasteIn = New-RamButton -Text 'Вставить' -Width 104 -Height 34 -OnClick {
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
        $btnPasteIn.Location = New-Object System.Drawing.Point(392, $boxY)
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
    $ok.Location = New-Object System.Drawing.Point(272, ($dlgH - 52))
    $dlg.Controls.Add($ok)

    $cancel = New-RamButton -Text 'Отмена' -Width 110 -Height 34 -OnClick {
        $this.FindForm().Tag = $false
        $this.FindForm().Close()
    }
    $cancel.Location = New-Object System.Drawing.Point(390, ($dlgH - 52))
    $dlg.Controls.Add($cancel)

    $dlg.Tag = $false
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
        Save-RamAccounts -Accounts $script:Accounts -Password $script:MasterPassword
    } catch {
        Show-RamError "Не удалось сохранить список аккаунтов:`n`n$($_.Exception.Message)"
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
            # Аккаунт уже есть — просто обновляем куку.
            $a.Cookie   = $Cookie
            $a.Username = $user.Name
            Save-RamState
            return [pscustomobject]@{ Account = $a; IsNew = $false; User = $user }
        }
    }

    $acc = New-RamAccount -Alias $user.Name -Cookie $Cookie -PlaceId $PlaceId
    $acc.Username = $user.Name
    $acc.UserId   = $user.Id
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
    return $res
}

# ------------------------------------------- мастер добавления аккаунтов ----

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
    $dlg.ClientSize      = New-Object System.Drawing.Size(680, 660)

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Size = New-Object System.Drawing.Size(680, 4); $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $dlg.Controls.Add((New-RamLabel -Text 'Добавление аккаунтов' -X 28 -Y 24 -Width 620 -Height 32 -Font $t.FontBig))

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
    $lblHow = New-Object System.Windows.Forms.Label
    $lblHow.Text      = $howto
    $lblHow.Location  = New-Object System.Drawing.Point(28, 62)
    $lblHow.Size      = New-Object System.Drawing.Size(624, 228)
    $lblHow.Font      = $t.FontBody
    $lblHow.ForeColor = $t.Muted
    $lblHow.BackColor = [System.Drawing.Color]::Transparent
    $dlg.Controls.Add($lblHow)

    # --- карточка "кто сейчас в приложении"
    $card = New-RamCard -Width 624 -Height 96
    $card.Location = New-Object System.Drawing.Point(28, 296)
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
    $btnRefresh.Location = New-Object System.Drawing.Point(28, 406)
    $dlg.Controls.Add($btnRefresh)

    $btnAdd = New-RamButton -Text 'Добавить этот аккаунт' -Width 240 -Height 38 -Kind 'primary'
    $btnAdd.Location = New-Object System.Drawing.Point(220, 406)
    $dlg.Controls.Add($btnAdd)

    $btnManual = New-RamButton -Text 'Ввести куку вручную' -Width 180 -Height 38 -Kind 'ghost'
    $btnManual.Location = New-Object System.Drawing.Point(472, 406)
    $dlg.Controls.Add($btnManual)

    # --- список добавленного
    $dlg.Controls.Add((New-RamLabel -Text 'Добавлено за этот заход:' -X 28 -Y 502 -Width 300 -Height 22 `
                                    -Font $t.FontSmall -Color $t.Muted))

    $lblAdded = New-Object System.Windows.Forms.Label
    $lblAdded.Text      = '— пока ничего —'
    $lblAdded.Location  = New-Object System.Drawing.Point(28, 526)
    $lblAdded.Size      = New-Object System.Drawing.Size(624, 56)
    $lblAdded.Font      = $t.FontBody
    $lblAdded.ForeColor = $t.Ok
    $lblAdded.BackColor = [System.Drawing.Color]::Transparent
    $dlg.Controls.Add($lblAdded)

    # Главная кнопка всего мастера: сменить аккаунт, не убив забранный вход.
    $btnSwitch = New-RamButton -Text 'Сменить аккаунт (безопасно)' -Width 260 -Height 38 -Kind 'primary' `
                               -Tooltip 'Закрыть Roblox и заставить его забыть вход, не разлогинивая на сервере'
    $btnSwitch.Location = New-Object System.Drawing.Point(28, 452)
    $dlg.Controls.Add($btnSwitch)

    $btnRestore = New-RamButton -Text 'Вернуть прошлый вход' -Width 220 -Height 38 -Kind 'ghost' `
                                -Tooltip 'Положить обратно последний сохранённый вход приложения'
    $btnRestore.Location = New-Object System.Drawing.Point(300, 452)
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

    $btnDone = New-RamButton -Text 'Готово' -Width 130 -Height 38 -Kind 'primary' -OnClick {
        $this.FindForm().Close()
    }
    $btnDone.Location = New-Object System.Drawing.Point(522, 596)
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

            $lblAdded.Text = ($w.Added | ForEach-Object { '  ✓  ' + $_ }) -join [Environment]::NewLine
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
            $lblAdded.Text = ($w.Added | ForEach-Object { '  ✓  ' + $_ }) -join [Environment]::NewLine
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
        [string]$Value = ''
    )
    $t = $Global:RamTheme
    $cb = New-Object System.Windows.Forms.ComboBox
    $cb.Location      = New-Object System.Drawing.Point($X, $Y)
    $cb.Size          = New-Object System.Drawing.Size($Width, 26)
    $cb.DropDownStyle = 'DropDownList'
    $cb.FlatStyle     = 'Flat'
    $cb.BackColor     = $t.Card
    $cb.ForeColor     = $t.Text
    $cb.Font          = $t.FontBody
    $cb.DrawMode      = 'OwnerDrawFixed'
    $cb.ItemHeight    = 20

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

    $btnFromApp = New-RamButton -Text 'Взять из приложения' -Width 194 -Height 30 -OnClick {
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

    $dlg.Controls.Add((New-RamLabel -Text 'ИГРА — ССЫЛКА ИЛИ ID (ПУСТО = ПРОСТО ОТКРЫТЬ ROBLOX)' -X $L -Y 288 -Width $LW -Height 18 -Font $t.FontSmall -Color $t.Muted))
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
                            -X $L -Y 346 -Width $LW -Height 22 -Font $t.FontSmall -Color $t.Muted
    $dlg.Controls.Add($lblGame)

    $dlg.Controls.Add((New-RamLabel -Text 'ПРИВАТНЫЙ СЕРВЕР — ССЫЛКА-ПРИГЛАШЕНИЕ' -X $L -Y 378 -Width $LW -Height 18 -Font $t.FontSmall -Color $t.Muted))
    $tbLink = New-RamTextBox -Width $LW -Height 32 -Value $acc.LinkCode
    $tbLink.Location = New-Object System.Drawing.Point($L, 398)
    $dlg.Controls.Add($tbLink)

    $dlg.Controls.Add((New-RamLabel -Text 'JOBID КОНКРЕТНОГО СЕРВЕРА' -X $L -Y 440 -Width $LW -Height 18 -Font $t.FontSmall -Color $t.Muted))
    $tbJob = New-RamTextBox -Width $LW -Height 32 -Value $acc.JobId
    $tbJob.Location = New-Object System.Drawing.Point($L, 460)
    $dlg.Controls.Add($tbJob)

    # =========================================== ПРАВАЯ КОЛОНКА: настройки ===
    $R = 480; $RW = 412

    $dlg.Controls.Add((New-RamLabel -Text 'НАСТРОЙКИ КЛИЕНТА ДЛЯ ЭТОГО АККАУНТА' -X $R -Y 66 -Width $RW -Height 18 -Font $t.FontSmall -Color $t.Muted))
    $hint = New-Object System.Windows.Forms.Label
    $hint.Text      = 'Применяются прямо перед запуском именно этого окна. «Не трогать» — оставить как в самом Roblox. Твинам обычно ставят минимум графики и ноль звука, чтобы пять окон не грузили компьютер.'
    $hint.Location  = New-Object System.Drawing.Point($R, 86)
    $hint.Size      = New-Object System.Drawing.Size($RW, 56)
    $hint.Font      = $t.FontSmall
    $hint.ForeColor = $t.Muted
    $hint.BackColor = [System.Drawing.Color]::Transparent
    $dlg.Controls.Add($hint)

    $dlg.Controls.Add((New-RamLabel -Text 'Качество графики' -X $R -Y 150 -Width 190 -Height 22))
    $cbGfx = New-RamCombo -X ($R + 200) -Y 148 -Width 212 -Items (Get-RamGraphicsChoices) -Value ([string]$acc.Graphics)
    $dlg.Controls.Add($cbGfx)

    $dlg.Controls.Add((New-RamLabel -Text 'Предел кадров (FPS)' -X $R -Y 188 -Width 190 -Height 22))
    $cbFps = New-RamCombo -X ($R + 200) -Y 186 -Width 212 -Items (Get-RamFpsChoices) -Value ([string]$acc.FramerateCap)
    $dlg.Controls.Add($cbFps)

    $dlg.Controls.Add((New-RamLabel -Text 'Режим окна' -X $R -Y 226 -Width 190 -Height 22))
    $cbFull = New-RamCombo -X ($R + 200) -Y 224 -Width 212 -Items (Get-RamFullscreenChoices) -Value ([string]$acc.Fullscreen)
    $dlg.Controls.Add($cbFull)

    $volItems = @([pscustomobject]@{ Text = 'не трогать'; Value = '' })
    foreach ($v in @(0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100)) {
        $volItems += [pscustomobject]@{ Text = "$v%"; Value = [string]$v }
    }
    $dlg.Controls.Add((New-RamLabel -Text 'Громкость (музыка и звук)' -X $R -Y 264 -Width 190 -Height 22))
    $cbVol = New-RamCombo -X ($R + 200) -Y 262 -Width 212 -Items $volItems -Value ([string]$acc.Volume)
    $dlg.Controls.Add($cbVol)

    # --- набор и метка
    $dlg.Controls.Add((New-RamLabel -Text 'НАБОР И МЕТКА' -X $R -Y 306 -Width $RW -Height 18 -Font $t.FontSmall -Color $t.Muted))

    $dlg.Controls.Add((New-RamLabel -Text 'Набор' -X $R -Y 330 -Width 190 -Height 22))
    $tbGroup = New-RamTextBox -Width 212 -Height 32 -Value $acc.Group
    $tbGroup.Location = New-Object System.Drawing.Point(($R + 200), 326)
    $dlg.Controls.Add($tbGroup)

    $colorItems = @()
    foreach ($c in Get-RamLabelColors) { $colorItems += [pscustomobject]@{ Text = $c.Text; Value = $c.Key } }
    $dlg.Controls.Add((New-RamLabel -Text 'Цветная метка' -X $R -Y 370 -Width 190 -Height 22))
    $cbColor = New-RamCombo -X ($R + 200) -Y 368 -Width 212 -Items $colorItems -Value ([string]$acc.Color)
    $dlg.Controls.Add($cbColor)

    $dlg.Controls.Add((New-RamLabel -Text 'ЗАМЕТКА — ВИДНА НА КАРТОЧКЕ' -X $R -Y 408 -Width $RW -Height 18 -Font $t.FontSmall -Color $t.Muted))
    $tbNote = New-RamTextBox -Width $RW -Height 32 -Value $acc.Note
    $tbNote.Location = New-Object System.Drawing.Point($R, 428)
    $dlg.Controls.Add($tbNote)

    # --- место окна
    $winTxt = if ([int]$acc.WindowW -gt 0) {
        "Место окна запомнено: $($acc.WindowX);$($acc.WindowY)  размер $($acc.WindowW)x$($acc.WindowH)"
    } else { 'Место окна не запомнено — окно встанет по общей раскладке' }
    $lblWin = New-RamLabel -Text $winTxt -X $R -Y 470 -Width $RW -Height 22 -Font $t.FontSmall -Color $t.Muted
    $dlg.Controls.Add($lblWin)

    $btnForgetWin = New-RamButton -Text 'Забыть место окна' -Width 200 -Height 30 -Kind 'ghost' -OnClick {
        $acc.WindowX = -1; $acc.WindowY = -1; $acc.WindowW = -1; $acc.WindowH = -1
        $lblWin.Text = 'Место окна не запомнено — окно встанет по общей раскладке'
    }
    $btnForgetWin.Location = New-Object System.Drawing.Point($R, 494)
    $dlg.Controls.Add($btnForgetWin)

    # ============================================================== низ ======
    $btnSave = New-RamButton -Text 'Сохранить' -Width 150 -Height 38 -Kind 'primary' -OnClick {
        $this.FindForm().Tag = $true; $this.FindForm().Close()
    }
    $btnSave.Location = New-Object System.Drawing.Point(600, 560)
    $dlg.Controls.Add($btnSave)

    $btnCancel = New-RamButton -Text 'Отмена' -Width 130 -Height 38 -OnClick {
        $this.FindForm().Tag = $false; $this.FindForm().Close()
    }
    $btnCancel.Location = New-Object System.Drawing.Point(762, 560)
    $dlg.Controls.Add($btnCancel)
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

function Show-RamSettingsDialog {
    param(
        # Только для Самопроверка.ps1: собрать окно и вернуть, не показывая.
        [switch]$BuildOnly
    )

    $t = $Global:RamTheme
    $s = $script:Settings

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Настройки'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size(620, 914)

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Size = New-Object System.Drawing.Size(620, 4); $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $dlg.Controls.Add((New-RamLabel -Text 'Настройки' -X 28 -Y 22 -Width 400 -Height 30 -Font $t.FontBig))

    # Ширины подписей = ширине своей колонки. Раньше первая была 500px и
    # накрывала собой три соседние — их просто не было видно.
    $dlg.Controls.Add((New-RamLabel -Text 'Пауза, сек' `
                                    -X 28 -Y 70 -Width 108 -Height 20 -Font $t.FontSmall -Color $t.Muted))
    $numDelay = New-Object System.Windows.Forms.NumericUpDown
    $numDelay.Location    = New-Object System.Drawing.Point(28, 92)
    $numDelay.Size        = New-Object System.Drawing.Size(90, 26)
    $numDelay.BorderStyle = 'FixedSingle'
    $numDelay.BackColor   = $t.Bg
    $numDelay.ForeColor   = $t.Text
    $numDelay.Minimum = 1; $numDelay.Maximum = 120; $numDelay.Value = [int]$s.LaunchDelaySec
    $dlg.Controls.Add($numDelay)

    # Пояснения к тесным колонкам — во всплывающих подсказках: места в ряд
    # на длинный текст нет, а подписи шире колонки накрывают соседние.
    $tips = New-Object System.Windows.Forms.ToolTip
    $tips.AutoPopDelay = 12000
    $tips.SetToolTip($numDelay, 'Пауза между запусками. Меньше 5 секунд Roblox может не успеть подхватить предыдущее окно. При пяти аккаунтах разумно 10-15.')

    $dlg.Controls.Add((New-RamLabel -Text 'Язык клиента' -X 140 -Y 70 -Width 145 -Height 20 -Font $t.FontSmall -Color $t.Muted))
    $cbLocale = New-Object System.Windows.Forms.ComboBox
    $cbLocale.Location      = New-Object System.Drawing.Point(140, 92)
    $cbLocale.Size          = New-Object System.Drawing.Size(130, 26)
    $cbLocale.DropDownStyle = 'DropDownList'
    $cbLocale.FlatStyle     = 'Flat'
    $cbLocale.BackColor     = $t.Card
    $cbLocale.ForeColor     = $t.Text
    [void]$cbLocale.Items.AddRange(@('ru_ru','en_us'))
    $cbLocale.SelectedItem  = $(if ($s.Locale -eq 'en_us') { 'en_us' } else { 'ru_ru' })
    $dlg.Controls.Add($cbLocale)

    $dlg.Controls.Add((New-RamLabel -Text 'Колонок' -X 292 -Y 70 -Width 100 -Height 20 -Font $t.FontSmall -Color $t.Muted))
    $numCols = New-Object System.Windows.Forms.NumericUpDown
    $numCols.Location    = New-Object System.Drawing.Point(292, 92)
    $numCols.Size        = New-Object System.Drawing.Size(90, 26)
    $numCols.BorderStyle = 'FixedSingle'
    $numCols.BackColor   = $t.Bg
    $numCols.ForeColor   = $t.Text
    $numCols.Minimum = 0; $numCols.Maximum = 6; $numCols.Value = [int]$s.TileColumns
    $dlg.Controls.Add($numCols)
    $tips.SetToolTip($numCols, 'Сколько колонок в раскладке окон сеткой. 0 — подобрать автоматически.')

    $dlg.Controls.Add((New-RamLabel -Text 'Тема оформления' -X 400 -Y 70 -Width 140 -Height 20 -Font $t.FontSmall -Color $t.Muted))
    $cbTheme = New-Object System.Windows.Forms.ComboBox
    $cbTheme.Location      = New-Object System.Drawing.Point(400, 92)
    $cbTheme.Size          = New-Object System.Drawing.Size(132, 26)
    $cbTheme.DropDownStyle = 'DropDownList'
    $cbTheme.FlatStyle     = 'Flat'
    $cbTheme.BackColor     = $t.Card
    $cbTheme.ForeColor     = $t.Text
    foreach ($th in Get-RamThemeList) { [void]$cbTheme.Items.Add($th.Title) }
    $currentTheme = (Get-RamThemeList | Where-Object { $_.Key -eq $s.Theme } | Select-Object -First 1)
    $cbTheme.SelectedItem = $(if ($currentTheme) { $currentTheme.Title } else { 'Тёмная' })
    $dlg.Controls.Add($cbTheme)

    # --- галочки
    $mk = {
        param($text, $y, $checked)
        $cb = New-RamCheckBox -X 28 -Y $y
        $dlg.Controls.Add($cb)
        $cb.Tag.Checked = $checked
        $lb = New-RamLabel -Text $text -X 56 -Y ($y - 1) -Width 480 -Height 22
        $lb.Cursor = [System.Windows.Forms.Cursors]::Hand
        $dlg.Controls.Add($lb)
        $lb.Tag = $cb
        $lb.Add_Click({ $this.Tag.Tag.Checked = -not $this.Tag.Tag.Checked; $this.Tag.Invalidate() })
        return $cb
    }

    $cbRename  = & $mk 'Писать имя аккаунта в заголовок окна'                140 ([bool]$s.RenameWindows)
    $cbTile    = & $mk 'Раскладывать окна сеткой сразу после запуска'        174 ([bool]$s.AutoTile)
    $cbConfirm = & $mk 'Спрашивать подтверждение при закрытии менеджера'     208 ([bool]$s.ConfirmOnExit)
    $cbRestart = & $mk 'Поднимать аккаунт заново, если клиент вылетел'        242 ([bool]$s.AutoRestart)
    $cbCompact = & $mk 'Компактные карточки — больше аккаунтов на экране'      276 ([bool]$s.CompactCards)
    $cbSavedW  = & $mk 'Ставить окна на запомненные для аккаунта места'        310 ([bool]$s.UseSavedWindows)
    $cbEmoji   = & $mk 'Показывать смайлики в названиях игр'                   344 ([bool]$s.ShowEmoji)
    $cbLogFile = & $mk 'Писать журнал в файл (data\logs)'                      378 ([bool]$s.LogToFile)
    $cbHotkey  = & $mk 'Ctrl+1..9 переключают окна аккаунтов'                  412 ([bool]$s.HotkeySwitch)
    $cbTray    = & $mk 'Сворачивать в часы, а не в панель задач'               446 ([bool]$s.MinimizeToTray)
    $cbCheck   = & $mk 'Проверять входы при открытии менеджера'                 480 ([bool]$s.CheckOnStart)

    # --- шифрование
    $dlg.Controls.Add((New-RamLabel -Text 'АВТОЗАПУСК ПО РАСПИСАНИЮ И ПРИСМОТР' -X 28 -Y 520 -Width 400 -Height 18 -Font $t.FontSmall -Color $t.Muted))

    $dlg.Controls.Add((New-RamLabel -Text 'Время ЧЧ:ММ' -X 28 -Y 544 -Width 120 -Height 24 -Font $t.FontSmall -Color $t.Muted))
    $tbTime = New-RamTextBox -Width 110 -Height 30 -Value ([string]$s.AutoStartAtTime)
    $tbTime.Location = New-Object System.Drawing.Point(150, 540)
    $dlg.Controls.Add($tbTime)

    $groupItems = @([pscustomobject]@{ Text = 'все аккаунты'; Value = '' })
    foreach ($g in (Get-RamGroups)) { $groupItems += [pscustomobject]@{ Text = $g; Value = $g } }

    $dlg.Controls.Add((New-RamLabel -Text 'Набор' -X 280 -Y 544 -Width 70 -Height 24 -Font $t.FontSmall -Color $t.Muted))
    $cbAutoGroup = New-RamCombo -X 350 -Y 542 -Width 240 -Items $groupItems -Value ([string]$s.AutoStartGroup)
    $dlg.Controls.Add($cbAutoGroup)

    $watchItems = @([pscustomobject]@{ Text = 'выключен'; Value = '' })
    foreach ($g in (Get-RamGroups)) { $watchItems += [pscustomobject]@{ Text = $g; Value = $g } }

    $dlg.Controls.Add((New-RamLabel -Text 'Присматривать за набором' -X 28 -Y 582 -Width 200 -Height 24 -Font $t.FontSmall -Color $t.Muted))
    $cbWatch = New-RamCombo -X 240 -Y 580 -Width 350 -Items $watchItems -Value ([string]$s.WatchGroup)
    $dlg.Controls.Add($cbWatch)

    $dlg.Controls.Add((New-RamLabel -Text 'Присмотр каждые полминуты поднимает тех, кого нет в игре. Расписание срабатывает раз в сутки.' `
                                    -X 28 -Y 612 -Width 560 -Height 20 -Font $t.FontSmall -Color $t.Muted))

    $dlg.Controls.Add((New-RamLabel -Text 'ШИФРОВАНИЕ ХРАНИЛИЩА' -X 28 -Y 642 -Width 400 -Height 18 -Font $t.FontSmall -Color $t.Muted))

    $mode = Get-RamStorageMode
    $lblMode = New-Object System.Windows.Forms.Label
    $lblMode.Text = switch ($mode) {
        'dpapi'  { 'Сейчас: DPAPI — привязка к твоей учётке Windows, пароль не нужен. Файл не откроется ни на другом ПК, ни у другого пользователя.' }
        'aes'    { 'Сейчас: AES-256 с мастер-паролем. Файл переносится на другой ПК, пароль спрашивается при запуске.' }
        'none'   { 'Файла ещё нет — будет создан при первом сохранении (DPAPI).' }
        default  { 'Не удалось определить режим.' }
    }
    $lblMode.Location  = New-Object System.Drawing.Point(28, 664)
    $lblMode.Size      = New-Object System.Drawing.Size(504, 52)
    $lblMode.Font      = $t.FontSmall
    $lblMode.ForeColor = $t.Muted
    $lblMode.BackColor = [System.Drawing.Color]::Transparent
    $dlg.Controls.Add($lblMode)

    $btnPwd = New-RamButton -Text 'Включить мастер-пароль' -Width 240 -Height 34 -OnClick {
        $p = Show-RamPasswordDialog -Title 'Новый мастер-пароль' -Prompt 'Придумай мастер-пароль:' -Confirm
        if ($null -eq $p) { return }
        if ($p.Length -lt 4) { Show-RamError 'Слишком короткий пароль — хотя бы 4 символа.'; return }
        try {
            Save-RamAccounts -Accounts $script:Accounts -Password $p
            $script:MasterPassword = $p
            $lblMode.Text = 'Сейчас: AES-256 с мастер-паролем.'
            Write-RamLog 'Хранилище перешифровано под мастер-пароль.' 'ok'
            Show-RamInfo 'Готово. Теперь при запуске будет спрашиваться пароль.'
        } catch { Show-RamError $_.Exception.Message }
    }
    $btnPwd.Location = New-Object System.Drawing.Point(28, 720)
    $dlg.Controls.Add($btnPwd)

    $btnDpapi = New-RamButton -Text 'Вернуться на DPAPI' -Width 240 -Height 34 -OnClick {
        try {
            Save-RamAccounts -Accounts $script:Accounts -Password ''
            $script:MasterPassword = ''
            $lblMode.Text = 'Сейчас: DPAPI — привязка к твоей учётке Windows, пароль не нужен.'
            Write-RamLog 'Хранилище перешифровано под DPAPI.' 'ok'
            Show-RamInfo 'Готово. Пароль больше не спрашивается.'
        } catch { Show-RamError $_.Exception.Message }
    }
    $btnDpapi.Location = New-Object System.Drawing.Point(292, 720)
    $dlg.Controls.Add($btnDpapi)

    # --- низ
    $dlg.Controls.Add((New-RamLabel -Text 'СОХРАНИТЬ НАСТРОЙКИ В ФАЙЛ — НИКУДА НЕ ОТПРАВЛЯЕТСЯ' -X 28 -Y 764 -Width 460 -Height 18 -Font $t.FontSmall -Color $t.Muted))

    $btnExport = New-RamButton -Text 'Выгрузить в файл' -Width 240 -Height 34 -OnClick {
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter   = 'Настройки AltHub (*.json)|*.json'
        $sfd.FileName = 'althub-setup.json'
        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        try {
            $cnt = Export-RamSetup -Path $sfd.FileName
            Write-RamLog "Настройки выгружены ($cnt аккаунтов, без кук)." 'ok'
            Show-RamInfo ("Готово. Файл сохранён у тебя на диске и никуда не отправляется.`n`n" +
                          "Внутри только названия аккаунтов и игры — кук там нет.`n`n" +
                          "Пригодится для переноса на другой компьютер. Если захочешь, можешь отдать файл другу, " +
                          "но войти по нему в твои аккаунты нельзя.`n`n" + $sfd.FileName)
        } catch { Show-RamError $_.Exception.Message }
    }
    $btnExport.Location = New-Object System.Drawing.Point(28, 786)
    $dlg.Controls.Add($btnExport)

    $btnImport = New-RamButton -Text 'Загрузить из файла' -Width 240 -Height 34 -OnClick {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'Настройки AltHub (*.json)|*.json'
        if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        try {
            $r = Import-RamSetup -Path $ofd.FileName
            Write-RamLog "Загружено: настроек $($r.Settings), игр $($r.Games)." 'ok'
            Show-RamInfo "Готово. Настроек применено: $($r.Settings), игр добавлено: $($r.Games).`n`nАккаунты не создавались — их надо добавить своим мастером, иначе войти будет нечем."
        } catch { Show-RamError $_.Exception.Message }
    }
    $btnImport.Location = New-Object System.Drawing.Point(292, 786)
    $dlg.Controls.Add($btnImport)

    $btnRestoreGfx = New-RamButton -Text 'Вернуть настройки Roblox как было' -Width 300 -Height 30 -Kind 'ghost' -OnClick {
        try {
            [void](Restore-RamRobloxSettings)
            Write-RamLog 'Настройки графики и звука Roblox возвращены к исходным.' 'ok'
            Show-RamInfo 'Готово. В Roblox вернулись твои прежние графика, звук и FPS.'
        } catch { Show-RamError $_.Exception.Message }
    }
    $btnRestoreGfx.Location = New-Object System.Drawing.Point(28, 824)
    $dlg.Controls.Add($btnRestoreGfx)

    $btnOk = New-RamButton -Text 'Сохранить' -Width 140 -Height 36 -Kind 'primary' -OnClick {
        $this.FindForm().Tag = $true; $this.FindForm().Close()
    }
    $btnOk.Location = New-Object System.Drawing.Point(328, 862)
    $dlg.Controls.Add($btnOk)

    $btnNo = New-RamButton -Text 'Отмена' -Width 120 -Height 36 -OnClick {
        $this.FindForm().Tag = $false; $this.FindForm().Close()
    }
    $btnNo.Location = New-Object System.Drawing.Point(476, 862)
    $dlg.Controls.Add($btnNo)
    $dlg.Tag = $false

    if ($BuildOnly) { return $dlg }

    [void]$dlg.ShowDialog()

    if ([bool]$dlg.Tag) {
        $s.LaunchDelaySec = [int]$numDelay.Value
        $s.Locale         = [string]$cbLocale.SelectedItem
        $s.TileColumns    = [int]$numCols.Value
        $s.RenameWindows  = [bool]$cbRename.Tag.Checked
        $s.AutoTile       = [bool]$cbTile.Tag.Checked
        $s.ConfirmOnExit  = [bool]$cbConfirm.Tag.Checked
        $s.AutoRestart      = [bool]$cbRestart.Tag.Checked
        $s.CompactCards     = [bool]$cbCompact.Tag.Checked
        $s.UseSavedWindows  = [bool]$cbSavedW.Tag.Checked
        $s.AutoStartGroup   = Get-RamComboValue $cbAutoGroup
        $s.WatchGroup       = Get-RamComboValue $cbWatch
        $s.ShowEmoji        = [bool]$cbEmoji.Tag.Checked
        $s.LogToFile        = [bool]$cbLogFile.Tag.Checked
        $s.HotkeySwitch     = [bool]$cbHotkey.Tag.Checked
        $s.MinimizeToTray   = [bool]$cbTray.Tag.Checked
        $s.CheckOnStart     = [bool]$cbCheck.Tag.Checked
        $Global:RamShowEmoji = $s.ShowEmoji

        $tm = $tbTime.Tag.Text.Trim()
        if ($tm -eq '' -or $tm -match '^\d{1,2}:\d{2}$') {
            $s.AutoStartAtTime = $tm
        } else {
            Show-RamError 'Время расписания должно быть в виде ЧЧ:ММ, например 19:30. Оставил как было.'
        }

        $oldTheme = $s.Theme
        $picked = Get-RamThemeList | Where-Object { $_.Title -eq [string]$cbTheme.SelectedItem } | Select-Object -First 1
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

function Restart-AltHub {
    <# Перезапуск самого себя: сохраняем данные, отпускаем замки и стартуем
       новый экземпляр тем же способом, каким запустились. #>
    Save-RamState
    Disable-RamMultiInstance

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = (Get-Process -Id $PID).Path
    $psi.Arguments       = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' +
                           (Join-Path $script:Root 'AltHub.ps1') + '"'
    $psi.UseShellExecute = $true
    [void][System.Diagnostics.Process]::Start($psi)

    if ($script:UI.ContainsKey('Form') -and $null -ne $script:UI.Form) {
        $script:Settings.ConfirmOnExit = $false
        $script:UI.Form.Close()
    }
}

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
                $avSize = 32; $avY = 12; $avX = 46
                $nameY = 7; $subY = 26; $nameX = 88; $nameW = 200
                $gameX = 300; $gameY = 17; $gameW = 210
                $dotX  = 528; $dotY = 17
                $btnY  = 12; $btnH = 32
            } else {
                $chk = New-RamCheckBox -X 18 -Y 36
                $avSize = 52; $avY = 20; $avX = 48
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

            $lblName = New-RamLabel -Text $a.Alias -X $nameX -Y $nameY -Width $aliasW -Height 24 `
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
                                                    -Font $t.FontSmall -Color $t.Muted))
                }

                # Справка: Robux, Premium, дата регистрации
                $facts = @()
                if ([int]$a.Robux -ge 0)      { $facts += "$($a.Robux) R$" }
                if ([string]$a.Premium -eq 'yes') { $facts += 'Premium' }
                if ($a.Created)               { $facts += "с $($a.Created)" }
                if ($facts.Count -gt 0) {
                    $card.Controls.Add((New-RamLabel -Text ($facts -join '  ·  ') -X 660 -Y 58 -Width 220 -Height 20 `
                                                    -Font $t.FontSmall -Color $t.Muted))
                }
            }

            $dot = New-RamStatusDot -X $dotX -Y $dotY -Width 150
            $card.Controls.Add($dot)

            $bPlay = New-RamButton -Text '▶' -Width 46 -Height $btnH -Kind 'primary' -Tooltip 'Запустить этот аккаунт' -OnClick {
                Add-RamToLaunchQueue -Accounts @((Get-RamAccountById -Id $this.Tag.AccountId))
            }
            $bPlay.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
            $bPlay.Location = New-Object System.Drawing.Point(($W - 172), $btnY)
            $card.Controls.Add($bPlay)

            $bEdit = New-RamButton -Text '✎' -Width 46 -Height $btnH -Tooltip 'Настройки аккаунта' -OnClick {
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

            $bStop = New-RamButton -Text '■' -Width 46 -Height $btnH -Tooltip 'Закрыть окно этого аккаунта' -OnClick {
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
    <# По одной аватарке за такт таймера, чтобы окно не подвисало. #>
    if ($script:AvatarQueue.Count -eq 0) { return }

    $id = $script:AvatarQueue[0]
    $script:AvatarQueue.RemoveAt(0)

    $a = Get-RamAccountById -Id $id
    $entry = $script:Cards[$id]
    if ($null -eq $a -or $null -eq $entry -or $a.UserId -le 0) { return }

    try {
        $file = Get-RamAvatarFile -UserId $a.UserId -CacheDir (Get-RamAvatarDir)
        $img  = Get-RamImageFromFile -Path $file
        if ($null -ne $img) {
            Set-RamAvatarImage -Box $entry.Avatar -Image $img -Letter $a.Alias
            $entry.AvatarLoaded = $true
        }
    } catch { }
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
            $msg  = "Аккаунт «$($acc.Alias)» — вход мёртв, его надо взять заново.`n`n" +
                    "1. Открой приложение Roblox и войди под «$($acc.Alias)».`n" +
                    "2. Вернись сюда и нажми «Забрать вход».`n`n" +
                    "Если в приложении сейчас другой аккаунт — нажми «Сменить аккаунт»: " +
                    "Roblox закроется и забудет вход, а на сервере он останется живым. " +
                    "Кнопку «Выйти» внутри Roblox не трогай, она убивает вход насовсем.`n`n" +
                    "Осталось починить: $left"

            $ans = Show-RamMessage -Message $msg -Title 'Починка входов' -Kind 'warn' -Buttons @(
                @{ Text = 'Забрать вход';    Value = 'take';   Kind = 'primary' },
                @{ Text = 'Сменить аккаунт'; Value = 'switch' },
                @{ Text = 'Пропустить';      Value = 'skip'   },
                @{ Text = 'Хватит';          Value = 'stop'   }
            )

            switch ([string]$ans) {
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

function Get-RamTargetAccounts {
    <# Отмеченные галочками. #>
    $res = @()
    foreach ($a in $script:Accounts) {
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

function Invoke-RamNextLaunch {
    if ($script:LaunchQueue.Count -eq 0) {
        $script:UI.LaunchTimer.Stop()

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

    $id = $script:LaunchQueue[0]
    $script:LaunchQueue.RemoveAt(0)

    $a = Get-RamAccountById -Id $id
    if ($null -eq $a) { return }

    Set-RamStatus "Запускаю «$($a.Alias)»..."
    $where = if ($a.GameName) { $a.GameName } elseif ($a.PlaceId) { "игра $($a.PlaceId)" } else { 'главная Roblox (без игры)' }
    Write-RamLog "Запуск '$($a.Alias)' -> $where" 'info'

    try {
        # Настройки клиента пишутся в общий файл Roblox прямо сейчас — клиент
        # прочитает их при старте. Поэтому это делается перед каждым запуском,
        # а не один раз.
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
    } catch {
        $msg = $_.Exception.Message
        Write-RamLog "'$($a.Alias)': $msg" 'err'

        # Запуск сорвался, а настройки графики мы в общий файл уже записали.
        # Оставлять их нельзя: откроешь Roblox вручную — и получишь графику
        # твина вместо своей.
        Restore-RamOwnClientSettings -Reason 'запуск не состоялся'

        # Кука умерла — попробуем починить её из приложения Roblox молча.
        # Если там сейчас именно этот аккаунт, вход подхватится сам и мы тут же
        # повторим запуск. Спрашивать в середине пачки запусков некогда.
        if ($msg -match 'недействительна|протухла') {
            if (Invoke-RamRepairCookie -Account $a -Quiet) {
                Write-RamLog "'$($a.Alias)': вход починен, пробую запустить снова." 'ok'
                [void]$script:LaunchQueue.Insert(0, $a.Id)
            }
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
    $dead = @()
    foreach ($id in @($script:Instances.Keys)) {
        $inst = $script:Instances[$id]

        $alive = $false
        try { $alive = -not (Get-Process -Id $inst.ProcessId -ErrorAction Stop).HasExited } catch { $alive = $false }
        if (-not $alive) { $dead += $id; continue }

        if ($inst.Handle -eq [IntPtr]::Zero -or -not (Test-RamWindowAlive -Handle $inst.Handle)) {
            $inst.Handle = Get-RamRobloxWindow -ProcessId $inst.ProcessId -TimeoutSec 0
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
        Save-RamState

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

    Invoke-RamPendingTile

    Update-RamCardStates
    for ($i = 0; $i -lt 3; $i++) { Update-RamOneAvatar }
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

    $targets = if ([string]::IsNullOrWhiteSpace([string]$Profile.Group)) { @(Get-RamOrderedAccounts) }
               else { @($script:Accounts | Where-Object { [string]$_.Group -eq [string]$Profile.Group }) }

    if ($targets.Count -eq 0) {
        Show-RamInfo "В профиле «$($Profile.Name)» набор «$($Profile.Group)» пуст — некого запускать."
        return
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Profile.PlaceId)) {
        foreach ($a in $targets) {
            $a.PlaceId  = [string]$Profile.PlaceId
            $a.GameName = [string]$Profile.GameName
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
    $entry = [pscustomobject]@{
        Name     = $name.Trim()
        Group    = [string]$first.Group
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
    $dlg.ClientSize      = New-Object System.Drawing.Size(660, 470)
    $dlg.Add_HandleCreated({ Set-RamDarkTitleBar $this })

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Size = New-Object System.Drawing.Size(660, 4); $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $dlg.Controls.Add((New-RamLabel -Text 'Быстрая настройка' -X 28 -Y 22 -Width 500 -Height 32 -Font $t.FontBig))

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = @'
Разложит всё под обычный расклад: одним аккаунтом играешь, остальные стоят
на приватном сервере и не грузят компьютер.

  основному  — графика на максимум, звук включён, свой набор
  твинам     — графика 1, звук 0, предел 30 кадров, общая игра
  окна       — основной крупно слева, твины мелко справа
  профиль    — «Твины на випку», поднимает их одной кнопкой
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

    $dlg.Controls.Add((New-RamLabel -Text 'ИГРА ДЛЯ ТВИНОВ — ССЫЛКА НА ВИПКУ ИЛИ ВЫБОР ИЗ СПИСКА' -X 28 -Y 262 -Width 500 -Height 18 -Font $t.FontSmall -Color $t.Muted))

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
                                    -X 28 -Y 356 -Width 604 -Height 20 -Font $t.FontSmall -Color $t.Muted))

    $cbSameGame = New-RamCheckBox -X 28 -Y 384
    $dlg.Controls.Add($cbSameGame)
    $lblSame = New-RamLabel -Text 'Основному поставить ту же игру' -X 56 -Y 383 -Width 400 -Height 22
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
            $row.Controls.Add((New-RamLabel -Text 'ПОСЛЕДНИЙ ЗАПУСК' -X 680 -Y 10 -Width 180 -Height 16 -Font $t.FontSmall -Color $t.Muted))
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
            $bSet.Location = New-Object System.Drawing.Point(($W - 330), 15)
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
            $bDel.Location = New-Object System.Drawing.Point(($W - 118), 15)
            $row.Controls.Add($bDel)
        }
    } finally {
        $h.ResumeLayout()
    }
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
            $bRun.Location = New-Object System.Drawing.Point(($W - 320), 15)
            $row.Controls.Add($bRun)

            $bDel = New-RamButton -Text 'Убрать' -Width 100 -Height 34 -OnClick {
                $nm = $this.Tag.Profile.Name
                $script:Settings.Profiles = @(Get-RamProfiles | Where-Object { $_.Name -ne $nm })
                Save-RamSettings -Settings $script:Settings
                Update-RamProfilesPanel
                Write-RamLog "Профиль «$nm» убран." 'ok'
            }
            $bDel.Tag | Add-Member -NotePropertyName Profile -NotePropertyValue $pr -Force
            $bDel.Location = New-Object System.Drawing.Point(($W - 112), 15)
            $row.Controls.Add($bDel)
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

function New-RamMainForm {
    $t = $Global:RamTheme

    $form = New-Object System.Windows.Forms.Form
    $form.Text          = $script:AppName
    $form.ClientSize    = New-Object System.Drawing.Size(1360, 820)
    # 226 (боковое меню) + 720 (левые кнопки) + 10 + 390 (правые) + поля.
    # Меньше — и две группы кнопок начнут налезать друг на друга.
    $form.MinimumSize   = New-Object System.Drawing.Size(1380, 700)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor     = $t.Bg
    $form.ForeColor     = $t.Text
    $form.Font          = $t.FontBody
    Set-RamDoubleBuffered $form
    $form.Add_HandleCreated({ Set-RamDarkTitleBar $this })

    $script:UI.Panels     = @{}
    $script:UI.NavButtons = @{}

    # =================================================== боковое меню ========
    $side = New-Object System.Windows.Forms.Panel
    $side.Location  = New-Object System.Drawing.Point(0, 0)
    $side.Size      = New-Object System.Drawing.Size(210, 820)
    $side.BackColor = $t.Panel
    $side.Anchor    = 'Top,Left,Bottom'
    $form.Controls.Add($side)

    $side.Controls.Add((New-RamLabel -Text $script:AppName -X 22 -Y 22 -Width 170 -Height 32 -Font $t.FontBig))
    $side.Controls.Add((New-RamLabel -Text "v$($script:AppVersion)" -X 24 -Y 54 -Width 170 -Height 18 `
                                     -Font $t.FontSmall -Color $t.Muted))

    $y = 96
    foreach ($sec in Get-RamSections) {
        $b = New-RamButton -Text ('   ' + $sec.Text) -Width 178 -Height 40 -Radius 8 -OnClick {
            Show-RamSection -Key $this.Tag.SectionKey
        }
        $b.Tag | Add-Member -NotePropertyName SectionKey -NotePropertyValue $sec.Key -Force
        $b.Tag.Border = $null
        $b.Location = New-Object System.Drawing.Point(16, $y)
        $side.Controls.Add($b)
        $script:UI.NavButtons[$sec.Key] = $b
        $y += 46
    }

    $bQuick = New-RamButton -Text '   Быстрая настройка' -Width 178 -Height 40 -Radius 8 -Kind 'ghost' `
                            -Tooltip 'Разложить всё под расклад «основной + твины на випке»' -OnClick {
        Show-RamQuickSetup
    }
    $bQuick.Location = New-Object System.Drawing.Point(16, ($y + 14))
    $side.Controls.Add($bQuick)
    $y += 46

    $bSettings = New-RamButton -Text '   Настройки' -Width 178 -Height 40 -Radius 8 -Kind 'ghost' -OnClick {
        Show-RamSettingsDialog
    }
    $bSettings.Location = New-Object System.Drawing.Point(16, ($y + 14))
    $side.Controls.Add($bSettings)

    $bHelp = New-RamButton -Text '   Справка' -Width 178 -Height 40 -Radius 8 -Kind 'ghost' -OnClick {
        $readme = Join-Path $script:Root 'README.md'
        if (Test-Path -LiteralPath $readme) { Start-Process notepad.exe $readme }
        else { Show-RamInfo 'README.md не найден рядом со скриптом.' }
    }
    $bHelp.Location = New-Object System.Drawing.Point(16, ($y + 60))
    $side.Controls.Add($bHelp)

    $lblAuthor = New-RamLabel -Text $script:AppAuthor -X 24 -Y 780 -Width 170 -Height 20 `
                              -Font $t.FontSmall -Color $t.Muted
    $lblAuthor.Anchor = 'Left,Bottom'
    $side.Controls.Add($lblAuthor)

    # =================================================== верхняя строка ======
    $sub = New-RamLabel -Text '' -X 234 -Y 22 -Width 700 -Height 22 -Font $t.FontSmall -Color $t.Muted
    $sub.Anchor = 'Top,Left'
    $form.Controls.Add($sub)
    $script:UI.Subtitle = $sub

    $search = New-RamTextBox -Width 300 -Height 32
    $search.Location = New-Object System.Drawing.Point(1036, 16)
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
    $sTb.Add_TextChanged({
        if ($script:SearchIsHint) { return }
        $script:Filter = $this.Text
        Build-RamCards
    })

    # =================================================== раздел: аккаунты ====
    $pAcc = New-Object System.Windows.Forms.Panel
    $pAcc.Location  = New-Object System.Drawing.Point(226, 56)
    $pAcc.Size      = New-Object System.Drawing.Size(1120, 736)
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
    $bar.Size          = New-Object System.Drawing.Size(720, 44)
    $bar.BackColor     = $t.Bg
    $bar.FlowDirection = 'LeftToRight'
    $bar.WrapContents  = $false
    $bar.Anchor        = 'Top,Left'
    $pAcc.Controls.Add($bar)

    $barR = New-Object System.Windows.Forms.FlowLayoutPanel
    $barR.Location      = New-Object System.Drawing.Point(730, 0)
    $barR.Size          = New-Object System.Drawing.Size(390, 44)
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
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($m.T)
        $mi.Tag = $m.K
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
    $groupBar.Location      = New-Object System.Drawing.Point(0, 50)
    $groupBar.Size          = New-Object System.Drawing.Size(1120, 34)
    $groupBar.BackColor     = $t.Bg
    $groupBar.FlowDirection = 'LeftToRight'
    $groupBar.WrapContents  = $false
    $groupBar.Anchor        = 'Top,Left,Right'
    $groupBar.Visible       = $false
    $pAcc.Controls.Add($groupBar)
    $script:UI.GroupBar = $groupBar

    $cards = New-RamScrollPanel -Width 1120 -Height 646
    $cards.Location = New-Object System.Drawing.Point(0, 90)
    $cards.Anchor   = 'Top,Left,Right,Bottom'
    $pAcc.Controls.Add($cards)
    $script:UI.Cards = $cards

    # =================================================== раздел: игры =======
    $pGames = New-Object System.Windows.Forms.Panel
    $pGames.Location  = New-Object System.Drawing.Point(226, 56)
    $pGames.Size      = New-Object System.Drawing.Size(1120, 736)
    $pGames.BackColor = $t.Bg
    $pGames.Anchor    = 'Top,Left,Right,Bottom'
    $pGames.Visible   = $false
    $form.Controls.Add($pGames)
    $script:UI.Panels['games'] = $pGames

    $pGames.Controls.Add((New-RamLabel -Text 'Мои игры' -X 0 -Y 0 -Width 400 -Height 32 -Font $t.FontBig))
    $pGames.Controls.Add((New-RamLabel -Text 'Отметь аккаунты в разделе «Аккаунты», потом нажми «Назначить отмеченным» у нужной игры' `
                                       -X 0 -Y 32 -Width 900 -Height 22 -Font $t.FontSmall -Color $t.Muted))

    $gamesHost = New-RamScrollPanel -Width 1120 -Height 670
    $gamesHost.Location = New-Object System.Drawing.Point(0, 66)
    $gamesHost.Anchor   = 'Top,Left,Right,Bottom'
    $pGames.Controls.Add($gamesHost)
    $script:UI.GamesHost = $gamesHost

    # =================================================== раздел: профили ====
    $pProf = New-Object System.Windows.Forms.Panel
    $pProf.Location  = New-Object System.Drawing.Point(226, 56)
    $pProf.Size      = New-Object System.Drawing.Size(1120, 736)
    $pProf.BackColor = $t.Bg
    $pProf.Anchor    = 'Top,Left,Right,Bottom'
    $pProf.Visible   = $false
    $form.Controls.Add($pProf)
    $script:UI.Panels['profiles'] = $pProf

    $pProf.Controls.Add((New-RamLabel -Text 'Профили запуска' -X 0 -Y 0 -Width 400 -Height 32 -Font $t.FontBig))
    $pProf.Controls.Add((New-RamLabel -Text 'Связка «набор аккаунтов + игра». Одной кнопкой ставит игру всем и запускает.' `
                                      -X 0 -Y 32 -Width 900 -Height 22 -Font $t.FontSmall -Color $t.Muted))

    $bSaveProf = New-RamButton -Text 'Сохранить текущее как профиль' -Width 280 -Height 32 -Kind 'ghost' -OnClick {
        Invoke-RamSaveProfile
    }
    $bSaveProf.Location = New-Object System.Drawing.Point(620, 2)
    $pProf.Controls.Add($bSaveProf)

    $profHost = New-RamScrollPanel -Width 1120 -Height 670
    $profHost.Location = New-Object System.Drawing.Point(0, 66)
    $profHost.Anchor   = 'Top,Left,Right,Bottom'
    $pProf.Controls.Add($profHost)
    $script:UI.ProfilesHost = $profHost

    # =================================================== раздел: статистика ==
    $pStats = New-Object System.Windows.Forms.Panel
    $pStats.Location  = New-Object System.Drawing.Point(226, 56)
    $pStats.Size      = New-Object System.Drawing.Size(1120, 736)
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

    $statsHost = New-RamScrollPanel -Width 1120 -Height 690
    $statsHost.Location = New-Object System.Drawing.Point(0, 46)
    $statsHost.Anchor   = 'Top,Left,Right,Bottom'
    $pStats.Controls.Add($statsHost)
    $script:UI.StatsHost = $statsHost

    # =================================================== раздел: журнал ======
    $pLog = New-Object System.Windows.Forms.Panel
    $pLog.Location  = New-Object System.Drawing.Point(226, 56)
    $pLog.Size      = New-Object System.Drawing.Size(1120, 736)
    $pLog.BackColor  = $t.Bg
    $pLog.Anchor    = 'Top,Left,Right,Bottom'
    $pLog.Visible   = $false
    $form.Controls.Add($pLog)
    $script:UI.Panels['log'] = $pLog

    $pLog.Controls.Add((New-RamLabel -Text 'Журнал' -X 0 -Y 0 -Width 400 -Height 32 -Font $t.FontBig))

    $bCopyLog = New-RamButton -Text 'Скопировать' -Width 130 -Height 32 -Kind 'ghost' -OnClick {
        try { [System.Windows.Forms.Clipboard]::SetText($script:UI.Log.Text); Write-RamLog 'Журнал скопирован в буфер.' 'ok' } catch { }
    }
    $bCopyLog.Location = New-Object System.Drawing.Point(420, 2)
    $pLog.Controls.Add($bCopyLog)

    $bClearLog = New-RamButton -Text 'Очистить' -Width 120 -Height 32 -Kind 'ghost' -OnClick {
        $script:UI.Log.Clear()
    }
    $bClearLog.Location = New-Object System.Drawing.Point(558, 2)
    $pLog.Controls.Add($bClearLog)

    $logHost = New-Object System.Windows.Forms.Panel
    $logHost.Location  = New-Object System.Drawing.Point(0, 46)
    $logHost.Size      = New-Object System.Drawing.Size(1120, 690)
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
    $st = New-RamLabel -Text '' -X 226 -Y 796 -Width 900 -Height 20 -Font $t.FontSmall -Color $t.Muted
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
    $bFix = New-RamButton -Text 'Проверить входы' -Width 190 -Height 26 -Kind 'ghost' `
                          -Tooltip 'Проверить, живы ли входы. Если есть мёртвые — пройтись по ним и взять заново из приложения Roblox' `
                          -OnClick {
                              if ([string]$this.Tag.Mode -like 'fix*') { Invoke-RamRepairAll }
                              else { Invoke-RamCheckCookies }
                          }
    $bFix.Tag | Add-Member -NotePropertyName Mode -NotePropertyValue 'check' -Force
    $bFix.BackColor = $t.Bg
    $bFix.Location  = New-Object System.Drawing.Point(1156, 792)
    $bFix.Anchor    = 'Right,Bottom'
    $form.Controls.Add($bFix)
    $script:UI.FixAll = $bFix

    # =================================================== таймеры ============
    $lt = New-Object System.Windows.Forms.Timer
    $lt.Interval = 500
    $lt.Add_Tick({ Invoke-RamNextLaunch })
    $script:UI.LaunchTimer = $lt

    $ut = New-Object System.Windows.Forms.Timer
    $ut.Interval = 2000
    $ut.Add_Tick({ Update-RamInstances })
    $ut.Start()
    $script:UI.UpdateTimer = $ut

    $sch = New-Object System.Windows.Forms.Timer
    $sch.Interval = 30000
    $sch.Add_Tick({ Invoke-RamScheduleCheck; Invoke-RamWatchCheck })
    $sch.Start()
    $script:UI.ScheduleTimer = $sch

    $form.Add_ResizeEnd({
        Build-RamCards
        Update-RamStatsPanel
        Update-RamGamesPanel
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
        Save-RamState
        Disable-RamMultiInstance
        Unregister-RamHotkeys
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

# ------------------------------------------------------------- старт --------

function Start-AltHub {
    $script:Settings = Load-RamSettings

    # Тему надо поставить ДО создания любых элементов: цвета кнопок и карточек
    # запоминаются в момент их создания.
    Set-RamTheme -Name $script:Settings.Theme | Out-Null
    $Global:RamShowEmoji = [bool]$script:Settings.ShowEmoji

    # Ловим обновления куки от Roblox и сразу сохраняем их в аккаунт.
    Register-RamCookieRefreshHandler -Handler {
        param($old, $new)
        Update-RamRefreshedCookie -OldCookie $old -NewCookie $new
    }

    $mode = Get-RamStorageMode
    if ($mode -eq 'aes') {
        while ($true) {
            $p = Show-RamPasswordDialog -Prompt 'Хранилище защищено мастер-паролем:'
            if ($null -eq $p) { return }
            try {
                $script:Accounts = Load-RamAccounts -Password $p
                $script:MasterPassword = $p
                break
            } catch {
                Show-RamError $_.Exception.Message
            }
        }
    } else {
        try {
            $script:Accounts = Load-RamAccounts -Password ''
        } catch {
            Show-RamError "Не удалось прочитать сохранённые аккаунты:`n`n$($_.Exception.Message)`n`nСписок будет пустым, файл не тронут."
            $script:Accounts = @()
        }
    }

    $form = New-RamMainForm

    Write-RamLog "$($script:AppName) v$($script:AppVersion) — автор: $($script:AppAuthor)." 'ok'
    Write-RamLog ('Хранилище: ' + $(switch (Get-RamStorageMode) {
        'aes'   { 'AES-256 + мастер-пароль' }
        'dpapi' { 'DPAPI (привязано к учётке Windows)' }
        default { 'ещё не создано' } })) 'info'

    try {
        $script:PlayerPath = Get-RamRobloxPlayerPath
        $client = Get-RamRobloxClients | Select-Object -First 1
        if ($null -ne $client) {
            Write-RamLog "Клиент Roblox найден: версия $($client.Version)" 'ok'
        } else {
            Write-RamLog 'Клиент Roblox найден.' 'ok'
        }

        $outdated = Get-RamOutdatedClientWarning
        if ($outdated) { Write-RamLog $outdated 'warn' }

        if (Test-RamRobloxUpdating) {
            Write-RamLog 'Прямо сейчас идёт обновление Roblox — дождись его конца, иначе установщик закроет открытые окна.' 'warn'
        }
    } catch {
        Write-RamLog $_.Exception.Message 'err'
        if (Test-RamMicrosoftStoreRoblox) {
            Write-RamLog 'Найдена версия Roblox из Microsoft Store — с ней мультизапуск не работает. Нужна обычная версия с roblox.com.' 'warn'
        }
    }

    if ($script:Settings.KeepMutex) {
        $lock = Enable-RamMultiInstance
        if ($lock.EventBlocked) {
            Write-RamLog 'Мультизапуск включён: оба замка взяты (singletonMutex + singletonEvent).' 'ok'
        } elseif ($lock.RobloxWasRunning) {
            Write-RamLog 'Roblox был открыт ДО менеджера — мультизапуск пока выключен. Закрой все окна Roblox: менеджер предложит сделать это сам при запуске.' 'warn'
        } else {
            Write-RamLog 'Не удалось взять замки мультизапуска. Попробуй перезапустить менеджер.' 'warn'
        }
    }

    if (Test-RamRobloxCookieFile) {
        Write-RamLog 'Приложение Roblox найдено — аккаунты можно добавлять одной кнопкой.' 'ok'
    } else {
        Write-RamLog 'Хранилище входов приложения Roblox не найдено — куки придётся вставлять вручную.' 'warn'
    }

    Remove-RamOldLogs

    if ($script:Settings.HotkeySwitch) {
        $cnt = Register-RamHotkeys -OnPressed {
            param($sender, $e)
            Invoke-RamFocusAccountByIndex -Index $e.Id
        }
        if ($cnt -gt 0) {
            Write-RamLog "Горячие клавиши Ctrl+1..Ctrl+$cnt переключают окна аккаунтов — работают и из игры." 'ok'
        } else {
            Write-RamLog 'Глобальные горячие клавиши занял кто-то другой — Ctrl+1..9 работать не будут.' 'warn'
        }
    }

    if ($script:Settings.WatchGroup) {
        Write-RamLog "Присмотр включён за набором «$($script:Settings.WatchGroup)»: вылетевшие поднимаются сами." 'ok'
    }

    Build-RamCards
    Set-RamStatus 'Готово к работе.'

    # Проверку входов делаем не сразу, а первым тиком таймера: окно уже
    # нарисовано, и человек видит, что происходит, а не пустой экран.
    if ($script:Settings.CheckOnStart -and @($script:Accounts).Count -gt 0) {
        $startupCheck = New-Object System.Windows.Forms.Timer
        $startupCheck.Interval = 900
        $startupCheck.Add_Tick({
            $this.Stop()
            Set-RamStatus 'Проверяю входы...'
            try { Invoke-RamStartupCookieCheck } catch { }
            Set-RamStatus 'Готово к работе.'
        })
        $startupCheck.Start()
        $script:UI.StartupTimer = $startupCheck
    }

    if (@($script:Accounts).Count -eq 0) {
        Write-RamLog 'Аккаунтов пока нет. Нажми «Добавить аккаунты».' 'info'
    }

    [void]$form.ShowDialog()
    $form.Dispose()
}

# Запускается со скрытой консолью, поэтому ошибку старта показываем окном,
# иначе программа просто молча не открылась бы.
if ($NoAutoStart) { return }

try {
    Start-AltHub
} catch {
    $msg = "AltHub не смог запуститься.`n`n" +
           $_.Exception.Message + "`n`n" +
           "Место: " + $_.InvocationInfo.ScriptName + ", строка " + $_.InvocationInfo.ScriptLineNumber
    try {
        [System.Windows.Forms.MessageBox]::Show($msg, 'Ошибка запуска',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } catch {
        Write-Error $msg
    }
}
