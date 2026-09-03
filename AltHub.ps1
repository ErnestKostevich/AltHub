#requires -Version 5.1
<#
================================================================================
 AltHub — менеджер аккаунтов Roblox
================================================================================
 Автор: Эрнест Костевич (Ernest Kostevich)
 Версия: 1.2
 Лицензия: MIT — см. файл LICENSE рядом. Можно свободно передавать друзьям,
 менять под себя и распространять дальше, сохраняя это указание авторства.

 Запуск нескольких аккаунтов Roblox одновременно, каждый в своём окне,
 каждый в нужной игре.

 Ничего не устанавливается, ничего не скачивается, ничего не компилируется.
 Это обычные текстовые .ps1-файлы — открой любым блокнотом и прочитай.

 Запускать через "AltHub.vbs" или "Запустить.cmd" (или: powershell -ExecutionPolicy Bypass
 -STA -File AltHub.ps1).

 Разбор по файлам. Сам AltHub.ps1 — только точка входа: состояние, журнал и
 подключение модулей. Всё остальное разложено по смыслу, чтобы любой файл
 можно было прочитать целиком и убедиться, что там нет ничего лишнего.

   Данные и внешний мир
     modules\Storage.ps1      — шифрование и хранение аккаунтов на диске
     modules\RobloxApi.ps1    — ЕДИНСТВЕННЫЙ файл, который ходит в сеть
     modules\CookieImport.ps1 — забирает куку из открытого приложения Roblox
     modules\RobloxSettings.ps1 — графика, звук и FPS для каждого аккаунта
     modules\Presets.ps1      — железо компьютера и готовые наборы настроек
     modules\Launcher.ps1     — мультизапуск и старт клиента
     modules\WindowTools.ps1  — заголовки и раскладка окон
     modules\Hotkeys.ps1      — глобальные Ctrl+1..9 и значок в часах

   Действия над аккаунтами
     modules\Accounts.ps1     — очередь запуска, наборы, профили, починка входов

   Внешний вид
     modules\Theme.ps1        — цвета и нарисованные вручную элементы
     modules\Layout.ps1       — раскладчик: ни одной координаты числом
     modules\UiMain.ps1       — главное окно и его разделы
     modules\UiDialogs.ps1    — все диалоговые окна
     modules\UiWizard.ps1     — мастер первого запуска
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

# ----------------------------------------------------------------------------
# МЕСТО НА ДИСКЕ.
#
# Несколько маленьких системных помощников (работа с окнами, горячие клавиши,
# чтение хранилища Roblox) компилируются на лету через Add-Type. Компилятору
# нужно место во временной папке. Если диск забит под ноль, Add-Type падает
# с невнятным «Недостаточно места на диске», и человек видит просто аварию
# на ровном месте.
#
# Поэтому проверяем заранее и говорим прямо, в чём дело.
# ----------------------------------------------------------------------------
try {
    $tempDrive = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetTempPath())
    $free = (New-Object System.IO.DriveInfo($tempDrive)).AvailableFreeSpace
    if ($free -lt 150MB) {
        $mb = [math]::Round($free / 1MB)
        [void][System.Windows.Forms.MessageBox]::Show(
            ("На диске $tempDrive почти не осталось места (свободно $mb МБ).`n`n" +
             "AltHub не сможет запуститься: Windows негде создать временные файлы.`n`n" +
             "Освободи хотя бы 500 МБ на этом диске и открой программу заново."),
            'AltHub — мало места на диске',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        exit 1
    }
} catch { }

$script:Root = $PSScriptRoot
. (Join-Path $script:Root 'modules\Theme.ps1')
. (Join-Path $script:Root 'modules\Layout.ps1')
. (Join-Path $script:Root 'modules\Storage.ps1')
. (Join-Path $script:Root 'modules\RobloxApi.ps1')
. (Join-Path $script:Root 'modules\CookieImport.ps1')
. (Join-Path $script:Root 'modules\Hotkeys.ps1')
. (Join-Path $script:Root 'modules\RobloxSettings.ps1')
. (Join-Path $script:Root 'modules\Presets.ps1')
. (Join-Path $script:Root 'modules\Launcher.ps1')
. (Join-Path $script:Root 'modules\WindowTools.ps1')
. (Join-Path $script:Root 'modules\UiWizard.ps1')
. (Join-Path $script:Root 'modules\UiDialogs.ps1')
. (Join-Path $script:Root 'modules\Accounts.ps1')
. (Join-Path $script:Root 'modules\UiMain.ps1')

# ------------------------------------------------------------ состояние -----

$script:Accounts       = @()      # список аккаунтов
$script:Settings       = $null    # настройки
$script:MasterPassword = ''       # пустая строка = режим DPAPI
$script:UI             = @{}      # ссылки на элементы главного окна
$script:Cards          = @{}      # Id аккаунта -> элементы его карточки
$script:Instances      = @{}      # Id аккаунта -> запущенный клиент
$script:LaunchQueue    = New-Object System.Collections.ArrayList
$script:AvatarQueue    = New-Object System.Collections.ArrayList
$script:AvatarJob      = $null    # текущая незавершённая загрузка аватарки
$script:AvatarSkip     = @{}      # UserId -> сколько раз не вышло скачать
$script:GameNameJob    = $null    # текущая незавершённая догрузка названия игры
$script:GameNameSkip   = @{}      # placeId -> сколько раз не вышло узнать название
$script:AppCookieStamp = 0        # время записи хранилища кук клиента
$script:AppOffer       = $null    # замеченный в приложении аккаунт, ещё не добавленный
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
$script:WarnedAboutLoad  = $false                                 # предупреждали ли про перегруз машины
$script:AwaitWindowFor   = ''                                      # см. Test-RamSettingsFileFree
$script:LaunchTries      = @{}     # Id -> сколько раз пробовали запустить
$script:LaunchFailed     = @{}     # Id -> почему не вышло (для отчёта в конце)
$script:AwaitWindowUntil = [datetime]::MinValue
$script:LastWindowState  = 'Normal'   # см. обработчик Resize главного окна
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
$script:AppVersion = '1.2'
$script:AppAuthor  = 'Эрнест Костевич'

function Get-RamAvatarDir { Join-Path (Get-RamDataDir) 'avatars' }

# ------------------------------------------------------------- утилиты ------

function Write-RamLog {
    <# Пишем в окно журнала. Секреты в журнал не попадают: кука, длинные токены
       и пароль вырезаются ДО вывода — и на экран, и в файл. #>
    param([string]$Message, [string]$Level = 'info')

    $safe = $Message -replace '_\|WARNING[^\s]*', '<кука скрыта>'
    $safe = $safe    -replace '[A-Za-z0-9_\-]{200,}', '<длинный токен скрыт>'
    # Пароль появился в программе вместе с входом по логину (Get-RamLoginCookie).
    # Сам по себе он в журнал не отправляется никогда, но если тело запроса
    # случайно попадёт в текст ошибки — вырезаем и его.
    $safe = $safe -replace '(?i)("?password"?\s*[:=]\s*)"[^"]*"', '$1"<пароль скрыт>"'
    $safe = $safe -replace '(?i)(password\s*[:=]\s*)\S+', '$1<пароль скрыт>'
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

function Invoke-RamSafe {
    <#
      Выполняет блок и не даёт ошибке уронить программу.

      ЗАЧЕМ. Главное окно живёт внутри ShowDialog(), то есть try/catch вокруг
      старта после входа в цикл сообщений уже не работает. А при
      $ErrorActionPreference = 'Stop' любая мелочь в обработчике таймера
      становится необрабатываемым исключением: WinForms показывает своё окно
      «Необрабатываемое исключение» с кнопкой «Выход», и она убивает процесс.
      Отсюда и жалобы «приложение резко взяло и закрылось».

      Поэтому всё, что тикает в фоне, оборачивается сюда: ошибка попадает
      в журнал, а программа продолжает работать.
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$Body,
        [string]$What = 'фоновая задача'
    )
    try { & $Body }
    catch {
        try { Write-RamLog "Сбой ($What): $($_.Exception.Message)" 'err' } catch { }
        try { Write-RamCrashDump -Error $_ -What $What } catch { }
    }
}

function Write-RamCrashDump {
    <#
      Кладёт подробности ошибки в data\logs\crash-ГГГГ-ММ-ДД.log.
      Нужно, чтобы на жалобу «просто закрылось» было что посмотреть.
      Куки сюда не попадают: текст прогоняется через тот же фильтр, что и журнал.
    #>
    param($Error, [string]$What = '')

    if ($script:ReadOnly) { return }
    try {
        $path = Join-Path (Get-RamLogDir) ('crash-' + (Get-Date).ToString('yyyy-MM-dd') + '.log')
        $lines = @(
            '=' * 70
            (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $What
            'Сообщение: ' + $Error.Exception.Message
            'Тип: '       + $Error.Exception.GetType().FullName
        )
        if ($Error.InvocationInfo) { $lines += 'Место: ' + $Error.InvocationInfo.PositionMessage }
        if ($Error.ScriptStackTrace) { $lines += 'Стек:', $Error.ScriptStackTrace }

        # Тот же фильтр, что и в журнале: кука в файл не попадёт.
        $safe = foreach ($l in $lines) {
            ($l -replace '_\|WARNING[^\s]*', '<кука скрыта>') -replace '[A-Za-z0-9_\-]{200,}', '<длинный токен скрыт>'
        }
        Add-Content -LiteralPath $path -Value $safe -Encoding UTF8
    } catch { }
}

function Register-RamCrashGuard {
    <#
      Ставит перехватчики необработанных исключений.

      Без них любая ошибка в обработчике события поднимает штатное окно
      WinForms, где кнопка «Выход» немедленно убивает процесс вместе со всеми
      несохранёнными данными. С ними — человек видит понятное окно и решает
      сам, а подробности уже лежат в crash-логе.
    #>
    try {
        [System.Windows.Forms.Application]::SetUnhandledExceptionMode(
            [System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    } catch { }

    try {
        [System.Windows.Forms.Application]::add_ThreadException({
            param($sender, $e)
            try { Write-RamLog "Сбой в интерфейсе: $($e.Exception.Message)" 'err' } catch { }
            try {
                Write-RamCrashDump -Error ([pscustomobject]@{
                    Exception        = $e.Exception
                    InvocationInfo   = $null
                    ScriptStackTrace = $e.Exception.StackTrace
                }) -What 'интерфейс'
            } catch { }
            try {
                Show-RamError ("Что-то пошло не так, но программа продолжит работать.`n`n" +
                               "$($e.Exception.Message)`n`n" +
                               'Подробности записаны в data\logs\crash-*.log — покажи этот файл, если повторится.')
            } catch { }
        })
    } catch { }

    try {
        [System.AppDomain]::CurrentDomain.add_UnhandledException({
            param($sender, $e)
            try { Write-RamCrashDump -Error ([pscustomobject]@{
                    Exception        = $e.ExceptionObject
                    InvocationInfo   = $null
                    ScriptStackTrace = ''
                }) -What 'вне интерфейса' } catch { }
        })
    } catch { }
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

# ------------------------------------------------------------- старт --------

function Start-AltHub {
    # Перехватчики ставим ПЕРВЫМ делом: с этого момента ни одна ошибка
    # не сможет молча убить процесс.
    Register-RamCrashGuard

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
                $script:Accounts = @(Load-RamAccounts -Password $p)
                $script:MasterPassword = $p
                break
            } catch {
                Show-RamError $_.Exception.Message
            }
        }
    } else {
        try {
            $script:Accounts = @(Load-RamAccounts -Password '')
        } catch {
            Show-RamError "Не удалось прочитать сохранённые аккаунты:`n`n$($_.Exception.Message)`n`nСписок будет пустым, файл не тронут."
            $script:Accounts = @()
        }
    }

    # Мастер первого запуска — до главного окна: он может сменить тему, а
    # цвета запоминаются кнопками в момент создания.
    Invoke-RamSafe -What 'мастер первого запуска' -Body { Invoke-RamFirstRun }

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

    # Клиенты Roblox могли остаться работать с прошлого раза — подхватываем их,
    # иначе они числятся закрытыми и присмотр наплодит дубликаты.
    Invoke-RamSafe -What 'подхват работающих клиентов' -Body { [void](Restore-RamAdoptRunningClients) }

    Build-RamCards
    Set-RamStatus 'Готово к работе.'

    # Проверку входов делаем не сразу, а первым тиком таймера: окно уже
    # нарисовано, и человек видит, что происходит, а не пустой экран.
    if ($script:Settings.CheckOnStart -and @($script:Accounts).Count -gt 0) {
        $startupCheck = New-Object System.Windows.Forms.Timer
        $startupCheck.Interval = 900
        $startupCheck.Add_Tick({
            $this.Stop()
            Invoke-RamSafe -What 'проверка входов при старте' -Body {
                Set-RamStatus 'Проверяю входы...'
                Invoke-RamStartupCookieCheck
                Set-RamStatus 'Готово к работе.'
            }
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
