#requires -Version 5.1
<#
================================================================================
 modules\UiWizard.ps1 — мастер первого запуска
================================================================================
 Пять шагов: железо, тема, аккаунты, кто основной, готово. Каждый шаг можно
 пропустить, из любого места можно выйти — программа останется рабочей.

 Ни одной координаты числом: всё считает раскладчик из Layout.ps1, размер
 окна выводится из содержимого.

 В сеть отсюда ничего не ходит: шаг «аккаунты» просто зовёт те же окна, что
 и кнопка «Добавить» в главном окне.
================================================================================
#>

function Get-RamWizardSteps {
    <# Порядок шагов. Отдельной функцией: и мастер, и Самопроверка должны
       видеть один и тот же список. #>
    @(
        [pscustomobject]@{ Key = 'hello';    Title = 'Знакомство'      },
        [pscustomobject]@{ Key = 'theme';    Title = 'Оформление'      },
        [pscustomobject]@{ Key = 'accounts'; Title = 'Аккаунты'        },
        [pscustomobject]@{ Key = 'main';     Title = 'Основной'        },
        [pscustomobject]@{ Key = 'done';     Title = 'Готово'          }
    )
}

function Invoke-RamFirstRun {
    <#
      Обёртка над окном мастера.

      Смена темы требует пересборки окна — цвета запоминаются кнопками в момент
      создания. Поэтому мастер закрывается и открывается снова на том же шаге,
      уже в новых цветах. Для человека это выглядит как мгновенная смена темы.
    #>
    param([switch]$Force)

    if (-not $Force) {
        if ([bool]$script:Settings.FirstRunDone) { return }
        # У кого аккаунты уже есть — это не первый запуск, а обновление с
        # прошлой версии. Навязывать им мастер незачем: он открывается из
        # «Справки», когда понадобится.
        if (@($script:Accounts).Count -gt 0) {
            $script:Settings.FirstRunDone = $true
            Save-RamSettings -Settings $script:Settings
            Write-RamLog 'Мастер настройки доступен в «Справке» — «Пройти настройку заново».' 'info'
            return
        }
    }

    $step = 0
    while ($true) {
        $r = Show-RamFirstRun -StartStep $step
        if ($null -eq $r) { break }
        if ([string]$r.Action -eq 'restyle') {
            $step = [int]$r.Step
            continue
        }
        break
    }

    $script:Settings.FirstRunDone = $true
    Save-RamSettings -Settings $script:Settings
}

function Show-RamFirstRun {
    <#
      Само окно. Возвращает:
        $null                       — закрыли крестиком или прошли до конца
        @{ Action='restyle'; Step } — сменили тему, окно надо пересобрать
    #>
    param(
        [int]$StartStep = 0,
        # Только для Самопроверка.ps1: собрать окно и вернуть, не показывая.
        [switch]$BuildOnly
    )

    $t     = $Global:RamTheme
    $m     = $t.M
    $steps = @(Get-RamWizardSteps)

    if ($StartStep -lt 0) { $StartStep = 0 }
    if ($StartStep -ge $steps.Count) { $StartStep = $steps.Count - 1 }

    # ---------------------------------------------------------------- размеры
    # Ширина — по самой длинной строке, которую нельзя переносить.
    $widest = 0
    foreach ($s in @('Менеджер прочитает вход из приложения Roblox',
                     'Окно браузера  —  войти руками, как на сайте',
                     'Все способы  —  вставить пачкой, из своего браузера, из файла')) {
        $w = (Measure-RamText -Text $s -Font $t.FontBody).Width
        if ($w -gt $widest) { $widest = $w }
    }
    $pageW = [Math]::Max($widest + $m.GapLg * 2, [int][Math]::Round(560 * $m.Scale))

    # ------------------------------------------------------------------ форма
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Настройка AltHub'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterScreen'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size(($pageW + $m.PadX * 2), 600)
    $dlg.Add_HandleCreated({ Set-RamDarkTitleBar $this })
    Set-RamWindowIcon $dlg

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Location  = New-Object System.Drawing.Point(0, 0)
    $stripe.Size      = New-Object System.Drawing.Size($dlg.ClientSize.Width, $m.StripeH)
    $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $root = New-RamLayout -Container $dlg
    [void](Add-RamGap -Layout $root -Height $m.StripeH)

    $titleH = (Measure-RamText -Text 'Ay' -Font $t.FontBig).Height + 2
    $lblTitle = New-RamLabel -Text 'Настройка AltHub' -X 0 -Y 0 -Width 10 -Height $titleH -Font $t.FontBig
    $lblTitle.Name = 'ramWizTitle'
    [void](Add-RamRow -Layout $root -Height $titleH -Gap $m.GapSm -Items @(@{ Control = $lblTitle; Width = $root.Width }))

    $capH = (Measure-RamText -Text 'Ay' -Font $t.FontSmall).Height + 2
    $lblStep = New-RamLabel -Text '' -X 0 -Y 0 -Width 10 -Height $capH -Font $t.FontSmall -Color $t.Muted
    $lblStep.Name = 'ramWizStep'
    [void](Add-RamRow -Layout $root -Height $capH -Gap $m.GapSm -Items @(@{ Control = $lblStep; Width = $root.Width }))

    # Полоска прогресса: рисуем сами, штатная в тёмной теме белая.
    $bar = New-Object System.Windows.Forms.Panel
    $bar.Name      = 'ramWizBar'
    $bar.Height    = [Math]::Max(4, [int][Math]::Round(6 * $m.Scale))
    $bar.BackColor = [System.Drawing.Color]::Transparent
    $bar.Tag       = [pscustomobject]@{ Done = 1; Total = $steps.Count }
    Set-RamDoubleBuffered $bar
    $bar.Add_Paint({
        param($s, $e)
        $th = $Global:RamTheme
        $g  = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $b1 = New-Object System.Drawing.SolidBrush($th.Panel)
        $g.FillRectangle($b1, 0, 0, $s.Width, $s.Height); $b1.Dispose()
        $frac = 0.0
        if ($s.Tag.Total -gt 0) { $frac = [double]$s.Tag.Done / [double]$s.Tag.Total }
        $w = [int]($s.Width * $frac)
        if ($w -gt 0) {
            $b2 = New-Object System.Drawing.SolidBrush($th.Accent)
            $g.FillRectangle($b2, 0, 0, $w, $s.Height); $b2.Dispose()
        }
    })
    [void](Add-RamRow -Layout $root -Height $bar.Height -Items @(@{ Control = $bar; Width = $root.Width }))

    $contentY = $root.Y
    $pages    = @{}

    $newPage = {
        param([string]$key)
        $p = New-Object System.Windows.Forms.Panel
        $p.Name      = "ramPage_$key"
        $p.Location  = New-Object System.Drawing.Point($root.X, $contentY)
        $p.Size      = New-Object System.Drawing.Size($pageW, 4000)
        $p.BackColor = [System.Drawing.Color]::Transparent
        $p.Visible   = $false
        $dlg.Controls.Add($p)
        $pages[$key] = $p
        return (New-RamLayout -Container $p -PadX 0 -PadY 0 -Width $pageW)
    }

    $addText = {
        param($lay, [string]$text, $font, $color)
        if ($null -eq $font)  { $font  = $t.FontBody }
        if ($null -eq $color) { $color = $t.Text }
        $h = (Measure-RamText -Text $text -Font $font -MaxWidth $lay.Width).Height + 2
        $lb = New-RamLabel -Text $text -X 0 -Y 0 -Width 10 -Height $h -Font $font -Color $color
        [void](Add-RamRow -Layout $lay -Height $h -Gap $m.GapSm -Items @(@{ Control = $lb; Width = $lay.Width }))
        return $lb
    }

    # ============================================================ 1. знакомство
    $p1 = & $newPage 'hello'
    [void](& $addText $p1 'AltHub держит несколько аккаунтов Roblox открытыми одновременно и раскладывает их окна по экрану. Пароли ему не нужны — он работает с уже выполненным входом.' $t.FontBody $t.Text)
    [void](Add-RamGap -Layout $p1 -Height $m.Gap)

    $adv = Get-RamHardwareAdvice
    [void](& $addText $p1 'ТВОЙ КОМПЬЮТЕР' $t.FontSmall $t.Muted)
    [void](& $addText $p1 (Get-RamHardwareSummary) $t.FontBody $t.Text)
    [void](& $addText $p1 $adv.Text $t.FontSmall $t.Muted)
    [void](Add-RamGap -Layout $p1 -Height $m.Gap)
    [void](& $addText $p1 'Дальше выберем оформление, добавим аккаунты и разберёмся, какой из них основной. Любой шаг можно пропустить и вернуться к нему позже — «Справка» -> «Пройти настройку заново».' $t.FontSmall $t.Muted)

    # =============================================================== 2. тема
    $p2 = & $newPage 'theme'
    [void](& $addText $p2 'Выбери, как AltHub будет выглядеть. Тему видно сразу: окно перерисуется целиком.' $t.FontSmall $t.Muted)
    [void](Add-RamGap -Layout $p2 -Height $m.GapSm)

    $cbTheme = New-RamCombo -X 0 -Y 0 -Width $p2.Width -Items (Get-RamThemeItems) -Value ([string]$script:Settings.Theme)
    $cbTheme.Name = 'ramWizTheme'
    [void](Add-RamRow -Layout $p2 -Items @(@{ Control = $cbTheme; Width = $p2.Width }))

    $btnApply = New-RamButton -Text 'Показать эту тему' -Width 1 -Height $m.RowHSm -Kind 'primary' -OnClick {
        $form = $this.FindForm()
        $cb   = $form.Controls.Find('ramWizTheme', $true) | Select-Object -First 1
        if ($null -eq $cb) { return }
        $key = Get-RamComboValue $cb
        if (-not $key) { return }
        # Возвращаем наверх, на каком шаге стоим: обёртка соберёт окно заново
        # в новых цветах и вернёт человека ровно сюда.
        $form.Tag = [pscustomobject]@{ Action = 'restyle'; Step = [int]$form.Controls.Find('ramWizStep', $true)[0].Tag; ThemeKey = $key }
        $form.Close()
    }
    $btnOwn = New-RamButton -Text 'Собрать свою' -Width 1 -Height $m.RowHSm -Kind 'ghost' -OnClick {
        $key = Show-RamThemeConstructor
        if (-not $key) { return }
        $form = $this.FindForm()
        $cb   = $form.Controls.Find('ramWizTheme', $true) | Select-Object -First 1
        if ($null -ne $cb) { Set-RamComboItems -Combo $cb -Items (Get-RamThemeItems) -Value $key }
    }
    [void](Add-RamRow -Layout $p2 -Items @($btnApply, $btnOwn) -Gap $m.Gap)
    [void](& $addText $p2 'В конструкторе можно взять любую основу и любой цвет акцента — остальные цвета подберутся сами.' $t.FontSmall $t.Muted)

    # =========================================================== 3. аккаунты
    $p3 = & $newPage 'accounts'
    # ЭТОТ СПИСОК ОБЯЗАН СОВПАДАТЬ С ЭКРАНОМ ДОБАВЛЕНИЯ.
    # Он этого не делал: мастер первого запуска показывал четыре способа и
    # ни словом не упоминал вход через окно браузера, хотя тот уже был в
    # программе. Человек проходил мастер, не находил обещанного способа и
    # делал единственный возможный вывод — что его нет. Самопроверка теперь
    # сверяет эти два места между собой.
    [void](& $addText $p3 'Способов много, но начать проще всего с первых двух. Остальные — на экране «Добавить».' $t.FontSmall $t.Muted)
    [void](Add-RamGap -Layout $p3 -Height $m.GapSm)

    $bApp = New-RamButton -Text 'Из приложения Roblox  —  проще всего' -Width 1 -Height $m.RowH -Kind 'primary' -OnClick {
        [void](Show-RamAddWizard)
        Update-RamWizardAccountCount -Form $this.FindForm()
    }
    $bWindow = New-RamButton -Text 'Окно браузера  —  войти руками, как на сайте' -Width 1 -Height $m.RowH -Kind 'ghost' -OnClick {
        $f = $this.FindForm()
        $cookie = $null
        try { $cookie = Show-RamExternalBrowserLoginWindow }
        catch {
            Write-RamLog "Окно входа: $($_.Exception.Message)" 'err'
            Show-RamError -Text ('Не удалось открыть окно входа:' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message)
        }
        # ЗДЕСЬ БЫЛО ХУЖЕ ВСЕГО: ни ветки на закрытое окно, ни ветки на
        # отвергнутую Roblox куку. И провал, и отказ проходили совсем без
        # слов, даже без журнала. А это первое, что видит человек в программе.
        if ($cookie) {
            $r = Import-RamAccountLine -Line $cookie
            if ($r -and $r.Ok) {
                Save-RamState
                Write-RamLog "Через окно браузера добавлен аккаунт: $($r.Alias)" 'ok'
                Show-RamMessage -Kind 'ok' -Message ('Добавлен аккаунт:' + [Environment]::NewLine + [Environment]::NewLine + $r.Alias)
            } else {
                $why = if ($r -and $r.Error) { $r.Error } else { 'Roblox не подтвердил вход' }
                Write-RamLog "Окно браузера: вход не принят — $why" 'err'
                Show-RamError -Text ('Вход прошёл, но аккаунт не добавился:' + [Environment]::NewLine +
                                     [Environment]::NewLine + $why)
            }
        } else {
            Write-RamLog 'Окно браузера: закрыто без получения входа.' 'warn'
            Show-RamMessage -Kind 'warn' -Message (
                'Аккаунт не добавлен: окно браузера закрылось раньше, чем вход прошёл.' +
                [Environment]::NewLine + [Environment]::NewLine +
                'Либо ты закрыл его сам, либо истекло время ожидания. Можно попробовать ещё раз.')
        }
        Update-RamWizardAccountCount -Form $f
    }
    $bAll = New-RamButton -Text 'Все способы  —  вставить пачкой, из своего браузера, из файла' -Width 1 -Height $m.RowH -Kind 'ghost' -OnClick {
        Show-RamAddChooser
        Update-RamWizardAccountCount -Form $this.FindForm()
    }
    $bManual = New-RamButton -Text 'Вручную  —  вставить куку самому' -Width 1 -Height $m.RowH -Kind 'ghost' -OnClick {
        $new = Show-RamAccountDialog
        if ($null -ne $new) {
            $script:Accounts = @(@($script:Accounts) + $new)
            Save-RamState
            Write-RamLog "Добавлен аккаунт '$($new.Alias)'." 'ok'
        }
        Update-RamWizardAccountCount -Form $this.FindForm()
    }
    [void](Add-RamStack -Layout $p3 -Items @($bApp, $bWindow, $bAll, $bManual) -Align 'fill' -Gap $m.GapSm)

    [void](Add-RamGap -Layout $p3 -Height $m.GapSm)
    $lblCount = New-RamLabel -Text '' -X 0 -Y 0 -Width 10 -Height $capH -Font $t.FontSmall -Color $t.Muted
    $lblCount.Name = 'ramWizCount'
    [void](Add-RamRow -Layout $p3 -Height $capH -Items @(@{ Control = $lblCount; Width = $p3.Width }))

    # ========================================================== 4. основной
    $p4 = & $newPage 'main'
    [void](& $addText $p4 'Основной — тот, которым ты играешь сам. Ему поставим максимум графики и звук, остальным — минимальную нагрузку, чтобы не съедали машину.' $t.FontSmall $t.Muted)
    [void](Add-RamGap -Layout $p4 -Height $m.GapSm)

    $cbMain = New-RamCombo -X 0 -Y 0 -Width $p4.Width -Items @([pscustomobject]@{ Text = '— выберу позже —'; Value = '' }) -Value ''
    $cbMain.Name = 'ramWizMain'
    [void](Add-RamField -Layout $p4 -Caption 'Основной аккаунт' -Control $cbMain)

    $bAssign = New-RamButton -Text 'Расставить наборы' -Width 1 -Height $m.RowH -Kind 'primary' -OnClick {
        $form = $this.FindForm()
        $cb   = $form.Controls.Find('ramWizMain', $true) | Select-Object -First 1
        $id   = Get-RamComboValue $cb
        if (-not $id) { Show-RamInfo 'Сначала выбери основной аккаунт в списке.'; return }

        $n = 0
        foreach ($a in @($script:Accounts)) {
            $key = if ([string]$a.Id -eq $id) { 'main' } else { 'twink' }
            if (Set-RamAccountPreset -Account $a -Key $key) { $n++ }
        }
        Save-RamState
        Build-RamCards
        Write-RamLog "Наборы расставлены на $n аккаунтов." 'ok'
        Show-RamInfo "Готово. Основному — максимум графики, остальным ($($n - 1)) — «Твинк, легко тянет».`n`nЛюбой аккаунт можно перенастроить: правый клик по карточке."
    }
    [void](Add-RamRow -Layout $p4 -Items @($bAssign))
    [void](& $addText $p4 'Если аккаунтов ещё нет — вернись на шаг назад или пропусти: наборы можно расставить в любой момент.' $t.FontSmall $t.Muted)

    # ============================================================== 5. готово
    $p5 = & $newPage 'done'
    [void](& $addText $p5 'Всё, можно работать.' $t.FontBody $t.Text)
    [void](Add-RamGap -Layout $p5 -Height $m.GapSm)
    [void](& $addText $p5 ("Отметь галочками нужные аккаунты и нажми «Запустить» — окна поднимутся по очереди и разложатся по экрану.`n`n" +
                           "Правый клик по карточке — игра, наборы настроек, починка входа.`n`n" +
                           "Пройти эту настройку заново можно из «Справки».") $t.FontSmall $t.Muted)
    [void](Add-RamGap -Layout $p5 -Height $m.Gap)

    $btnShortcut = New-RamButton -Text 'Сделать ярлык на рабочем столе' -Width 1 -Height $m.RowH -Kind 'ghost' `
                                 -Tooltip 'Запуск одним кликом, без чёрного окна консоли' -OnClick {
        $r = New-RamDesktopShortcut
        if ($r.Ok) {
            Set-RamButtonText -Button $this -Text 'Ярлык создан ✓'
            Set-RamButtonEnabled -Button $this -Enabled $false
            Write-RamLog "Ярлык создан: $($r.Path)" 'ok'
        } else {
            Show-RamError "Не вышло создать ярлык.`n`n$($r.Error)"
        }
    }
    [void](Add-RamRow -Layout $p5 -Items @($btnShortcut))
    [void](& $addText $p5 'Ярлык запускает AltHub без чёрного окна консоли и со своей иконкой.' $t.FontSmall $t.Muted)

    # --------------------------------------------------- выравнивание страниц
    $pageH = 0
    foreach ($k in $pages.Keys) {
        $b = $pages[$k].Controls | ForEach-Object { $_.Bottom } | Measure-Object -Maximum
        if ([int]$b.Maximum -gt $pageH) { $pageH = [int]$b.Maximum }
    }
    foreach ($k in $pages.Keys) { $pages[$k].Size = New-Object System.Drawing.Size($pageW, $pageH) }

    $root.Y = $contentY + $pageH
    $root.Bottom = $root.Y
    [void](Add-RamGap -Layout $root -Height $m.GapLg)

    $line = New-Object System.Windows.Forms.Panel
    $line.Size      = New-Object System.Drawing.Size($root.Width, 1)
    $line.BackColor = $t.Border
    [void](Add-RamRow -Layout $root -Items @(@{ Control = $line; Width = $root.Width }) -Height 1)

    # ------------------------------------------------------------------- низ
    $btnSkip = New-RamButton -Text 'Пропустить настройку' -Width 1 -Height $m.RowH -Kind 'ghost' -OnClick {
        $this.FindForm().Close()
    }
    $btnBack = New-RamButton -Text 'Назад' -Width 1 -Height $m.RowH -OnClick {
        Step-RamWizard -Form $this.FindForm() -Delta -1
    }
    # Ширина сразу под самую длинную надпись, какую эта кнопка когда-либо
    # получит. Иначе на последнем шаге «Далее» превращается в «Начать работу»,
    # кнопка расширяется вправо от своего места и вылезает за край окна.
    $nextW = (Measure-RamText -Text 'Начать работу' -Font $t.FontBody).Width + $m.BtnPadX
    $btnNext = New-RamButton -Text 'Далее' -Width $nextW -Height $m.RowH -Kind 'primary' -OnClick {
        Step-RamWizard -Form $this.FindForm() -Delta 1
    }
    $btnBack.Name = 'ramWizBack'
    $btnNext.Name = 'ramWizNext'
    [void](Add-RamButtonBar -Layout $root -Primary $btnNext -Secondary @($btnBack) -Extra @($btnSkip))

    [void](Complete-RamLayout -Layout $root -ClampToScreen)
    $stripe.Size = New-Object System.Drawing.Size($dlg.ClientSize.Width, $m.StripeH)

    $dlg.Tag = $null
    Set-RamWizardStep -Form $dlg -Index $StartStep

    if ($BuildOnly) { return $dlg }

    [void]$dlg.ShowDialog()
    $res = $dlg.Tag
    $dlg.Dispose()

    if ($null -ne $res -and [string]$res.Action -eq 'restyle') {
        $script:Settings.Theme = [string]$res.ThemeKey
        Save-RamSettings -Settings $script:Settings
        Set-RamTheme -Name $script:Settings.Theme | Out-Null
        return $res
    }
    return $null
}

function Set-RamWizardStep {
    <#
      Показывает шаг с указанным номером и приводит в порядок подписи, полоску
      прогресса и кнопки.

      Всё берётся из формы, ничего из замыканий: обработчики кнопок живут
      дольше, чем вызов Show-RamFirstRun, и локалы им уже недоступны.
    #>
    param([Parameter(Mandatory)]$Form, [int]$Index)

    $steps = @(Get-RamWizardSteps)
    if ($Index -lt 0) { $Index = 0 }
    if ($Index -ge $steps.Count) { $Index = $steps.Count - 1 }
    $key = [string]$steps[$Index].Key

    foreach ($c in $Form.Controls) {
        if ([string]$c.Name -like 'ramPage_*') { $c.Visible = ([string]$c.Name -eq "ramPage_$key") }
    }

    $lblStep = $Form.Controls.Find('ramWizStep', $true) | Select-Object -First 1
    if ($null -ne $lblStep) {
        $lblStep.Tag  = $Index
        $lblStep.Text = ('Шаг {0} из {1}  ·  {2}' -f ($Index + 1), $steps.Count, $steps[$Index].Title)
    }

    $bar = $Form.Controls.Find('ramWizBar', $true) | Select-Object -First 1
    if ($null -ne $bar) {
        $bar.Tag.Done  = $Index + 1
        $bar.Tag.Total = $steps.Count
        $bar.Invalidate()
    }

    $back = $Form.Controls.Find('ramWizBack', $true) | Select-Object -First 1
    if ($null -ne $back) { Set-RamButtonEnabled -Button $back -Enabled ($Index -gt 0) }

    $next = $Form.Controls.Find('ramWizNext', $true) | Select-Object -First 1
    if ($null -ne $next) {
        if ($Index -eq $steps.Count - 1) { Set-RamButtonText -Button $next -Text 'Начать работу' }
        else                             { Set-RamButtonText -Button $next -Text 'Далее' }
    }

    if ($key -eq 'accounts') { Update-RamWizardAccountCount -Form $Form }
    if ($key -eq 'main')     { Update-RamWizardMainList     -Form $Form }
}

function Step-RamWizard {
    <# Кнопки «Назад» и «Далее». С последнего шага «Далее» закрывает мастер. #>
    param([Parameter(Mandatory)]$Form, [int]$Delta)

    $steps = @(Get-RamWizardSteps)
    $lbl   = $Form.Controls.Find('ramWizStep', $true) | Select-Object -First 1
    $cur   = 0
    if ($null -ne $lbl -and $null -ne $lbl.Tag) { $cur = [int]$lbl.Tag }

    $next = $cur + $Delta
    if ($next -ge $steps.Count) { $Form.Close(); return }
    if ($next -lt 0) { $next = 0 }
    Set-RamWizardStep -Form $Form -Index $next
}

function Update-RamWizardAccountCount {
    <# Живой счётчик добавленного на третьем шаге. #>
    param($Form)
    if ($null -eq $Form) { return }
    $lbl = $Form.Controls.Find('ramWizCount', $true) | Select-Object -First 1
    if ($null -eq $lbl) { return }

    $n = @($script:Accounts).Count
    if ($n -eq 0) {
        $lbl.Text = 'Пока не добавлено ни одного аккаунта.'
    } else {
        $lbl.Text = "Добавлено аккаунтов: $n"
    }
}

function Update-RamWizardMainList {
    <# Заполняет список основного аккаунта тем, что успели добавить. #>
    param($Form)
    if ($null -eq $Form) { return }
    $cb = $Form.Controls.Find('ramWizMain', $true) | Select-Object -First 1
    if ($null -eq $cb) { return }

    $items = @([pscustomobject]@{ Text = '— выберу позже —'; Value = '' })
    foreach ($a in @($script:Accounts)) {
        $items += [pscustomobject]@{ Text = [string]$a.Alias; Value = [string]$a.Id }
    }
    $keep = Get-RamComboValue $cb
    Set-RamComboItems -Combo $cb -Items $items -Value $keep
}
