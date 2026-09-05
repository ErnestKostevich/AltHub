#requires -Version 5.1
<#
  ExternalBrowserLogin.ps1
  -------------------------
  Восьмой способ входа: запускаем НАСТОЯЩИЙ Chrome как отдельный процесс
  с постоянным профилем и расширением-мостом из папки extension\.
  Пользователь логинится руками на roblox.com — расширение само отправляет
  .ROBLOSECURITY на локальный HTTP-listener, который здесь поднимаем.

  Браузер, в порядке предпочтения:
    1) Chrome for Testing, ЕСЛИ он уже лежит в data\chrome-for-testing\.
       Это официальный Chromium от Google — тот же бинарник, которым
       пользуется Roblox Account Manager. У него настоящий Chrome-отпечаток
       (WebGL, canvas, шрифты, аудио), --load-extension работает всегда
       (ограничение Chrome 137+ касается только branded-сборок), и Arkose
       обычно даёт низкий риск → 1–2 лёгких раунда капчи вместо цепочки.
       САМ ОН НЕ КАЧАЕТСЯ. ~150 МБ чужого исполняемого файла — не то, что
       программа тянет молча: скачивание начинается только после того, как
       человек нажал кнопку в окне согласия, где написано что, откуда и
       сколько весит (см. Request-RamChromeForTesting).
    2) Системный Edge — он ещё понимает --load-extension. Отпечаток Edge со
       свежим профилем даёт более злую капчу, но работает без скачиваний.
    3) Системный Chrome — последним: на 137+ расширение просто не грузится,
       и мы это замечаем (расширение не здоровается) и говорим прямо.

  Почему НЕ сносим файл Cookies профиля:
    Вместе с .ROBLOSECURITY в той базе лежат RBXEventTrackerV2 (browserid)
    и rbx-ip2 — метки «этого устройства». Если сносить базу целиком, для
    Roblox каждый вход — совершенно новое устройство → максимальная
    сложность капчи. Старую сессионную куку снимает само расширение,
    точечно, а метки устройства остаются.

  Чего здесь нет и не будет: авторешения капчи, подмены canvas/WebGL,
  прокси-ротации, флагов, прячущих автоматизацию. Капчу человек проходит
  руками в открытом окне.

  Отдельно про --disable-blink-features=AutomationControlled: он был здесь
  и убран. Этот флаг существует ровно для одного — прятать navigator.webdriver
  от проверок на бота. Браузером мы не управляем (ни CDP, ни WebDriver),
  человек сам печатает пароль и сам проходит капчу, поэтому webdriver и так
  не выставлен и флаг ничего не менял. Оставлять в проекте строку, которая
  выглядит как обход антибот-проверки, — врать о том, чем программа
  занимается. Заодно убран --test-type: он прятал предупреждающую плашку
  браузера, а прятать от человека предупреждения мы не будем.

  Приватность: расширение стучит исключительно на 127.0.0.1 на порт,
  который сами открываем на этот один вход. Порт закрывается сразу
  после получения куки либо по таймауту/отмене.
#>

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor [Net.ServicePointManager]::SecurityProtocol
} catch { }

Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

function Get-RamChromeForTestingDir {
    Join-Path (Get-RamDataDir) 'chrome-for-testing'
}

function Get-RamChromeForTestingExe {
    <# Возвращает путь к уже лежащему chrome.exe либо $null. #>
    $dir = Get-RamChromeForTestingDir
    if (-not (Test-Path -LiteralPath $dir)) { return $null }

    $direct = Join-Path $dir 'chrome.exe'
    if (Test-Path -LiteralPath $direct) { return $direct }

    $found = Get-ChildItem -LiteralPath $dir -Filter 'chrome.exe' -Recurse -File -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($null -ne $found) { return $found.FullName }
    return $null
}

function Save-RamHttpFile {
    <#
      Скачивает URL в файл кусками, чтобы можно было обновлять прогресс
      и не держать весь zip в памяти. OnProgress получает (скачано, всего).
    #>
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile,
        [scriptblock]$OnProgress
    )

    $handler = New-Object System.Net.Http.HttpClientHandler
    try {
        $handler.AutomaticDecompression =
            [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    } catch { }

    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(30)
    try {
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('AltHub/1.2 (Chrome-for-Testing setup)')
    } catch { }

    try {
        $resp = $client.GetAsync(
            $Url,
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
        ).GetAwaiter().GetResult()

        if (-not $resp.IsSuccessStatusCode) {
            throw "HTTP $([int]$resp.StatusCode) при скачивании Chrome for Testing."
        }

        $total = [int64]0
        if ($resp.Content.Headers.ContentLength.HasValue) {
            $total = [int64]$resp.Content.Headers.ContentLength.Value
        }

        $inStream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $out = [System.IO.File]::Create($OutFile)
        try {
            $buffer = New-Object byte[] (262144)
            $got = [int64]0
            while (($n = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $out.Write($buffer, 0, $n)
                $got += $n
                if ($OnProgress) {
                    try { [void](& $OnProgress $got $total) } catch { }
                }
            }
            if ($got -lt 1MB) {
                throw "Скачанный файл слишком маленький ($got байт) — похоже, пришла не сборка Chrome."
            }
        } finally {
            $out.Dispose()
            $inStream.Dispose()
            $resp.Dispose()
        }
    } finally {
        $client.Dispose()
    }
}

function Invoke-RamVisibleDownload {
    <# Модельное окно прогресса, чтобы главное окно не казалось зависшим. #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Hint,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.ClientSize      = New-Object System.Drawing.Size(470, 128)
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.ShowInTaskbar   = $false
    $form.TopMost         = $true
    if ($script:UI -and $script:UI.ContainsKey('Form') -and $null -ne $script:UI.Form) {
        try { $form.Owner = $script:UI.Form } catch { }
    }

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(16, 14)
    $label.Size     = New-Object System.Drawing.Size(438, 40)
    $label.Text     = $Hint
    $form.Controls.Add($label)

    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Location = New-Object System.Drawing.Point(16, 60)
    $bar.Size     = New-Object System.Drawing.Size(438, 22)
    $bar.Minimum  = 0
    $bar.Maximum  = 100
    $form.Controls.Add($bar)

    $pct = New-Object System.Windows.Forms.Label
    $pct.Location = New-Object System.Drawing.Point(16, 90)
    $pct.Size     = New-Object System.Drawing.Size(438, 22)
    $pct.Text     = 'подключаюсь...'
    $form.Controls.Add($pct)

    $form.Show()
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        Save-RamHttpFile -Url $Url -OutFile $OutFile -OnProgress {
            param($got, $total)
            if ($total -gt 0) {
                $p = [int][Math]::Min(100, [Math]::Floor(($got * 100.0) / $total))
                if ($p -ge 0 -and $p -le 100) { $bar.Value = $p }
                $mbGot = [Math]::Round($got / 1MB, 1)
                $mbTot = [Math]::Round($total / 1MB, 1)
                $pct.Text = "$p %    $mbGot из $mbTot МБ"
            } else {
                $pct.Text = ('скачано {0} МБ' -f [Math]::Round($got / 1MB, 1))
            }
            [System.Windows.Forms.Application]::DoEvents()
        }
    } finally {
        try { $form.Close() } catch { }
        try { $form.Dispose() } catch { }
    }
}

function Install-RamChromeForTesting {
    <#
      Скачивает официальный Chrome for Testing (канал Stable, win64) и
      распаковывает в data\chrome-for-testing\. Возвращает путь к chrome.exe.
      Если что-то пошло не так — кидает ошибку, вызывающий откатывается
      на системный браузер.
    #>
    $dir = Get-RamChromeForTestingDir
    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }

    $jsonUrl = 'https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json'
    Write-RamLog 'Chrome for Testing: спрашиваю у Google свежую сборку Stable/win64.' 'info'

    $meta = $null
    try {
        $meta = Invoke-RestMethod -Uri $jsonUrl -TimeoutSec 30
    } catch {
        throw "Не удалось получить список сборок Chrome for Testing: $($_.Exception.Message)"
    }

    $ver = [string]$meta.channels.Stable.version
    $asset = @($meta.channels.Stable.downloads.chrome |
               Where-Object { [string]$_.platform -eq 'win64' } |
               Select-Object -First 1)
    $zipUrl = $null
    if ($asset) { $zipUrl = [string]$asset.url }
    if ([string]::IsNullOrWhiteSpace($zipUrl)) {
        throw 'В списке сборок Google нет Chrome for Testing для win64.'
    }
    if ([string]::IsNullOrWhiteSpace($ver)) { $ver = 'unknown' }

    Write-RamLog "Chrome for Testing: качаю $ver (один раз, потом лежит в data\chrome-for-testing)." 'info'

    $zip = Join-Path $env:TEMP ('althub-cft-' + [guid]::NewGuid().ToString('N') + '.zip')
    $unpack = Join-Path $dir '_unpack'
    try {
        Invoke-RamVisibleDownload `
            -Title 'AltHub — Chrome for Testing' `
            -Hint 'Один раз скачивается официальный Chromium от Google (~150 МБ). Это тот же браузер, которым пользуется RAM. Твой обычный Chrome/Edge не затрагивается.' `
            -Url $zipUrl `
            -OutFile $zip

        if (Test-Path -LiteralPath $unpack) {
            Remove-Item -LiteralPath $unpack -Recurse -Force -ErrorAction SilentlyContinue
        }
        [void](New-Item -ItemType Directory -Path $unpack -Force)

        Write-RamLog 'Chrome for Testing: распаковываю архив.' 'info'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $unpack)

        $exe = Get-ChildItem -LiteralPath $unpack -Filter 'chrome.exe' -Recurse -File -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($null -eq $exe) {
            throw 'В архиве Google нет chrome.exe — формат сборки изменился.'
        }

        # Переносим содержимое папки с chrome.exe наверх data\chrome-for-testing\,
        # чтобы путь был стабильным между запусками.
        $payloadDir = $exe.DirectoryName
        Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne '_unpack' } |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        Get-ChildItem -LiteralPath $payloadDir -Force | ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination (Join-Path $dir $_.Name) -Force
        }

        $final = Join-Path $dir 'chrome.exe'
        if (-not (Test-Path -LiteralPath $final)) {
            throw 'После распаковки chrome.exe не оказался в data\chrome-for-testing\.'
        }

        Set-Content -LiteralPath (Join-Path $dir 'version.txt') -Value $ver -Encoding ASCII
        Write-RamLog "Chrome for Testing $ver готов: $final" 'ok'
        return $final
    } finally {
        if (Test-Path -LiteralPath $zip) {
            Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $unpack) {
            Remove-Item -LiteralPath $unpack -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-RamChromeForTestingPath {
    <#
      Только УЖЕ СКАЧАННЫЙ Chrome for Testing. Ничего не качает и в сеть не
      ходит: если его нет — возвращает $null, и вызывающий берёт системный
      браузер.

      Раньше эта функция при отсутствии файла молча тянула ~150 МБ с серверов
      Google, а раз в 45 дней — ещё раз, «на обновление». Программа, которая
      обещает «ничего не устанавливается, внутри только текстовые файлы», не
      может сама притащить и запустить чужой исполняемый файл. Скачиванием
      теперь занимается Request-RamChromeForTesting — и только после того,
      как человек нажал кнопку в окне, где написано, что именно качается.
    #>
    $existing = Get-RamChromeForTestingExe
    if (-not $existing) { return $null }

    try {
        $ageDays = ((Get-Date) - (Get-Item -LiteralPath $existing).LastWriteTime).TotalDays
        if ($ageDays -gt 45) {
            Write-RamLog 'Chrome for Testing старше 45 дней. Обновить можно кнопкой в настройках — сам он не качается.' 'info'
        }
    } catch { }
    return $existing
}

function Test-RamChromeForTestingReady {
    <# Есть ли уже скачанный Chrome for Testing. Для интерфейса и проверок. #>
    return [bool](Get-RamChromeForTestingExe)
}

function Get-RamInstalledBrowserPath {
    <#
      Системный браузер на случай, если CfT нет. Edge раньше Chrome:
      на branded Chrome 137+ флаг --load-extension тихо игнорируется.
    #>
    $candidates = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }

    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'
    )
    foreach ($r in $regPaths) {
        if (Test-Path -LiteralPath $r) {
            $p = (Get-ItemProperty -LiteralPath $r -ErrorAction SilentlyContinue).'(default)'
            if ($p -and (Test-Path -LiteralPath $p)) { return $p }
        }
    }

    return $null
}

function Get-RamFreeLocalPort {
    <# Находит свободный TCP-порт в диапазоне для эфемерных портов. #>
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $listener.Stop()
    return $port
}

function ConvertTo-RamChromeArg {
    <# Собирает --flag=value, в кавычках если в пути есть пробел. #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Value)
    if ($Value -match '\s') {
        return ('{0}="{1}"' -f $Name, $Value)
    }
    return ('{0}={1}' -f $Name, $Value)
}

function Get-RamExternalBrowserProfileDir {
    <#
      Свой профиль под каждый тип браузера. Нельзя кормить Chrome
      профилем, который пожил в Edge: разные client hints, разный
      Local State — для Arkose это выглядит странно.
    #>
    param([Parameter(Mandatory)][string]$Kind)

    $name = switch ($Kind) {
        'cft'   { 'cft-profile' }
        default { 'externalbrowserprofile' }
    }
    $dir = Join-Path (Get-RamDataDir) $name
    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    return $dir
}

function Clear-RamExternalBrowserProfileState {
    <#
      Между входами чистим в профиле всё, из-за чего Chrome «помнит»
      прошлый вход и переоткрывает вкладки:
        - Login Data*          — сохранённые пароли,
        - Web Data*            — автозаполнение форм,
        - History*             — история,
        - Current/Last Session, Current/Last Tabs, папка Sessions/
                               — из-за них при следующем запуске
                                 восстанавливаются старые вкладки и
                                 всплывает «Chrome закрылся некорректно».
      Cookies и Local Storage НЕ трогаем: там RBXEventTrackerV2 /
      browserid — метки устройства для Arkose. .ROBLOSECURITY снимет
      уже расширение внутри профиля.
      Плюс правим Preferences: exit_type=Normal, exited_cleanly=true,
      чтобы Chrome не показывал жёлтую плашку восстановления.
    #>
    param([Parameter(Mandatory)][string]$ProfileDir)

    $default = Join-Path $ProfileDir 'Default'
    if (-not (Test-Path -LiteralPath $default)) { return }

    $patterns = @(
        'Login Data*', 'Web Data*', 'History*',
        'Current Session', 'Current Tabs', 'Last Session', 'Last Tabs',
        'Top Sites*', 'Visited Links', 'Network Action Predictor*',
        'Shortcuts*', 'Favicons*'
    )
    foreach ($pat in $patterns) {
        Get-ChildItem -LiteralPath $default -Filter $pat -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop }
                catch { Write-RamLog "Профиль: не удалось удалить $($_.Name): $($_.Exception.Message)" 'warn' }
            }
    }
    $sessionsDir = Join-Path $default 'Sessions'
    if (Test-Path -LiteralPath $sessionsDir) {
        try { Remove-Item -LiteralPath $sessionsDir -Recurse -Force -ErrorAction Stop }
        catch { Write-RamLog "Профиль: не удалось очистить Sessions\: $($_.Exception.Message)" 'warn' }
    }

    $prefsPath = Join-Path $default 'Preferences'
    if (Test-Path -LiteralPath $prefsPath) {
        try {
            $raw   = Get-Content -LiteralPath $prefsPath -Raw -ErrorAction Stop
            $prefs = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $prefs.profile) {
                $prefs | Add-Member -NotePropertyName 'profile' -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $prefs.profile | Add-Member -NotePropertyName 'exit_type'      -NotePropertyValue 'Normal' -Force
            $prefs.profile | Add-Member -NotePropertyName 'exited_cleanly' -NotePropertyValue $true    -Force
            ($prefs | ConvertTo-Json -Depth 100 -Compress) |
                Set-Content -LiteralPath $prefsPath -Encoding UTF8 -NoNewline
        } catch {
            Write-RamLog "Профиль: не удалось поправить Preferences: $($_.Exception.Message)" 'warn'
        }
    }
}


function Invoke-RamBrowserWarmup {
    <#
      Прогрев «холодного» браузера: первый запуск CfT после установки
      (или на новом профиле) тратит секунды на инициализацию профиля,
      GPU- и шрифтовых кэшей. Если сразу открыть окно входа, навигация
      стартует раньше готовности браузера и страница зависает на сером
      экране с URL вместо заголовка. Поэтому сначала делаем короткий
      запуск на about:blank БЕЗ app-режима, ждём появления окна и гасим
      процесс. Прогрев выполняется только когда профиля ещё нет
      (нет папки Default) — дальше он не нужен.
    #>
    param(
        [Parameter(Mandatory)][string]$BrowserExe,
        [Parameter(Mandatory)][string]$ProfileDir
    )

    if (Test-Path -LiteralPath (Join-Path $ProfileDir 'Default')) { return }

    Write-RamLog 'Первый запуск браузера: прогреваю профиль, чтобы окно входа открылось сразу.' 'info'
    $warmProc = $null
    try {
        $warmArgs = @(
            (ConvertTo-RamChromeArg -Name '--user-data-dir' -Value $ProfileDir)
            '--no-first-run'
            '--no-default-browser-check'
            '--disable-session-crashed-bubble'
            '--window-size=10,10'
            '--window-position=-32000,-32000'
            'about:blank'
        )
        $warmProc = Start-Process -FilePath $BrowserExe -ArgumentList $warmArgs -PassThru
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt 15) {
            [System.Windows.Forms.Application]::DoEvents()
            if ($warmProc.HasExited) { break }
            $warmProc.Refresh()
            if ($warmProc.MainWindowHandle -ne [IntPtr]::Zero) {
                # Окно поднялось — браузер живой, даём ещё секунду на
                # догрузку кэшей и выключаем.
                Start-Sleep -Seconds 1
                break
            }
            Start-Sleep -Milliseconds 200
        }
    } catch {
        Write-RamLog "Прогрев профиля не удался (не критично): $($_.Exception.Message)" 'warn'
    } finally {
        if ($null -ne $warmProc -and -not $warmProc.HasExited) {
            try { $warmProc.CloseMainWindow() | Out-Null } catch { }
            Start-Sleep -Milliseconds 400
            if (-not $warmProc.HasExited) { try { $warmProc.Kill() } catch { } }
        }
    }
}

function Start-RamLoginBrowser {
    <# Запускает окно входа; возвращает объект процесса. #>
    param(
        [Parameter(Mandatory)][string]$BrowserExe,
        [Parameter(Mandatory)][object[]]$ProcArgs
    )
    return (Start-Process -FilePath $BrowserExe -ArgumentList $ProcArgs -PassThru)
}

function Test-RamLoginWindowStuck {
    <#
      Признак зависшего серого экрана: у окна вместо заголовка документа
      отображается сам URL (документ так и не загрузился). Возвращает
      $true, если окно есть, но заголовок выглядит как URL/host.
    #>
    param([Parameter(Mandatory)]$Proc)
    try { $Proc.Refresh() } catch { return $false }
    if ($Proc.HasExited) { return $false }
    if ($Proc.MainWindowHandle -eq [IntPtr]::Zero) { return $false }
    $title = [string]$Proc.MainWindowTitle
    if ([string]::IsNullOrWhiteSpace($title)) { return $true }
    # URL-образный заголовок: «www.roblox.com/login», «roblox.com» и т.п.
    if ($title -match '^[a-z0-9.-]+\.[a-z]{2,}(/|$)') { return $true }
    return $false
}

function Show-RamExternalBrowserLoginWindow {
    <#
      Запускает Chrome for Testing (или системный Edge/Chrome) с
      расширением-мостом, ждёт куку .ROBLOSECURITY через локальный
      HTTP-listener, закрывает браузер и возвращает куку.
      $null, если пользователь закрыл браузер сам или истёк таймаут.

      Параметр $TimeoutSeconds — сколько ждать вход (по умолчанию 5 минут).
    #>
    param(
        [string]$Root = $script:Root,
        [int]$TimeoutSeconds = 300
    )

    $browserKind = 'cft'
    $browserExe  = Get-RamChromeForTestingPath
    if (-not $browserExe) {
        $browserExe = Get-RamInstalledBrowserPath
        if ($browserExe -and ($browserExe -match 'msedge\.exe$')) {
            $browserKind = 'edge'
        } else {
            $browserKind = 'chrome'
        }
        if ($browserExe) {
            Write-RamLog "Chrome for Testing недоступен — открываю системный браузер ($browserKind). Капча может быть злее, чем в RAM." 'warn'
        }
    }
    if (-not $browserExe) {
        throw 'Не найден браузер. Нужен либо доступ в сеть для Chrome for Testing, либо установленный Chrome/Edge.'
    }

    $extensionDir = Join-Path $Root 'extension'
    if (-not (Test-Path -LiteralPath (Join-Path $extensionDir 'manifest.json'))) {
        throw "Не найдено расширение-мост (ожидалось в $extensionDir\manifest.json)."
    }

    # Постоянный профиль: возраст, шрифтовый кэш, RBXEventTrackerV2.
    # Не удаляем его между входами и НЕ сносим файл Cookies — старую
    # .ROBLOSECURITY снимет расширение, точечно.
    $profileDir = Get-RamExternalBrowserProfileDir -Kind $browserKind

    $port = Get-RamFreeLocalPort

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://127.0.0.1:$port/")
    try {
        $listener.Start()
    } catch {
        throw "Не удалось поднять локальный listener на порту $port`: $($_.Exception.Message)"
    }

    # CORS для fetch() из service worker расширения (origin chrome-extension://...).
    # '*' безопасен: сервер слушает только 127.0.0.1 и живёт минуты одного входа.
    function Write-RamCorsHeaders([System.Net.HttpListenerResponse]$resp) {
        $resp.Headers.Add('Access-Control-Allow-Origin', '*')
        $resp.Headers.Add('Access-Control-Allow-Methods', 'POST, OPTIONS')
        $resp.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
    }

    $resultCookie = $null
    $browserProc  = $null

    try {
        $loginUrl = "https://www.roblox.com/login?althub_port=$port"

        # Чистим следы прошлого входа (пароли/автозаполнение/история/сессии),
        # но сохраняем Cookies и Local Storage — там метки устройства.
        try { Clear-RamExternalBrowserProfileState -ProfileDir $profileDir } catch {
            Write-RamLog "Профиль: уборка не удалась: $($_.Exception.Message)" 'warn'
        }

        $procArgs = @(
            (ConvertTo-RamChromeArg -Name '--user-data-dir' -Value $profileDir)
            (ConvertTo-RamChromeArg -Name '--load-extension' -Value $extensionDir)
            (ConvertTo-RamChromeArg -Name '--disable-extensions-except' -Value $extensionDir)
            # Здесь БЫЛИ --disable-blink-features=AutomationControlled и
            # --test-type. Первый прячет navigator.webdriver от проверок на
            # бота, второй убирает предупреждающую плашку самого браузера.
            # Оба убраны намеренно, подробности в шапке файла.
            #
            # IsolateOrigins / site-per-process тоже НЕ трогаем — но по
            # обратной причине: отключённая изоляция сайтов читается из JS,
            # и для Arkose это сильный сигнал бота. Тут интересы совпадают.
            '--no-first-run'
            '--no-default-browser-check'
            # На случай, если Chrome решит восстановить сессию несмотря на
            # почищенные файлы — гасим и баббл, и восстановление.
            '--disable-session-crashed-bubble'
            '--disable-features=ChromeWhatsNewUI,Translate,PrivacySandboxSettings4,OptimizationHints,InterestFeedContentSuggestions'
            # Фиксированный размер окна — как у Puppeteer в RAM.
            '--window-size=520,760'
            '--window-position=200,120'
        )

        if ($browserKind -eq 'edge') {
            # Только для системного Edge: не подтягивать аккаунт Microsoft
            # в изолированный профиль входа.
            $procArgs += @(
                '--no-service-autorun'
                '--disable-sync'
                '--edge-skip-first-run'
            )
        }

        # App-mode: одно окно, без панели вкладок и омнибокса — ровно как
        # в RAM. Обязательно ПОСЛЕДНИМ аргументом и вместо позиционного URL.
        $procArgs += ('--app={0}' -f $loginUrl)

        Write-RamLog "Внешний браузер: $browserKind  $browserExe  (порт моста $port)" 'info'
        Write-RamLog "Внешний браузер: профиль $profileDir" 'info'
        Write-RamLog "Внешний браузер: расширение $extensionDir" 'info'
 
         # Прогрев холодного профиля: без него первая навигация стартует
        # раньше готовности браузера и окно виснет на сером экране.
        Invoke-RamBrowserWarmup -BrowserExe $browserExe -ProfileDir $profileDir

        $browserProc = Start-RamLoginBrowser -BrowserExe $browserExe -ProcArgs $procArgs

        # Принудительная активация окна для устранения серого экрана при холодном старте
        Start-Sleep -Milliseconds 600
        if ($null -ne $browserProc -and -not $browserProc.HasExited) {
            for ($i = 0; $i -lt 15; $i++) {
                if ($browserProc.MainWindowHandle -ne [IntPtr]::Zero) {
                    try {
                        [Microsoft.VisualBasic.Interaction]::AppActivate($browserProc.Id)
                    } catch { }
                    break
                }
                Start-Sleep -Milliseconds 100
            }
        }

        # Сторожок против серого экрана: даём странице время прогрузиться
        # (холодный профиль может быть медленным) и проверяем заголовок
        # окна. Если вместо заголовка документа там URL — страница не
        # загрузилась; перезапускаем окно один раз (ровно то, что вручную
        # делает «закрыть и нажать Окно входа»). Порт и listener те же,
        # поэтому расширение отработает как обычно.
        Start-Sleep -Seconds 6
        if ($null -ne $browserProc -and (Test-RamLoginWindowStuck -Proc $browserProc)) {
            Write-RamLog 'Окно входа зависло на сером экране — перезапускаю его автоматически.' 'warn'
            try { $browserProc.CloseMainWindow() | Out-Null } catch { }
            Start-Sleep -Milliseconds 600
            if (-not $browserProc.HasExited) { try { $browserProc.Kill() } catch { } }
            # ЖДЁМ, ПОКА ОН ДЕЙСТВИТЕЛЬНО УМРЁТ. Chrome держит SingletonLock
            # на папке профиля; пока он его не отпустил, новый chrome.exe не
            # запускается, а передаёт задание старому и мгновенно завершается
            # сам. Дальше цикл видит HasExited и решает, что человек закрыл
            # окно, хотя окно на экране открыто.
            try { [void]$browserProc.WaitForExit(5000) } catch { }
            Start-Sleep -Milliseconds 1200
            $browserProc = Start-RamLoginBrowser -BrowserExe $browserExe -ProcArgs $procArgs
            Start-Sleep -Milliseconds 600
            if ($null -ne $browserProc -and -not $browserProc.HasExited) {
                for ($i = 0; $i -lt 15; $i++) {
                    if ($browserProc.MainWindowHandle -ne [IntPtr]::Zero) {
                        try {
                            [Microsoft.VisualBasic.Interaction]::AppActivate($browserProc.Id)
                        } catch { }
                        break
                    }
                    Start-Sleep -Milliseconds 100
                }
            }
        }

        $getContextTask = $listener.GetContextAsync()
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        # Расширение здоровается сразу, как только увидит адрес со своим
        # портом. Если за 25 секунд не поздоровалось — его в этом браузере
        # нет (обычный Chrome 137+ молча игнорирует --load-extension), и
        # ждать пять минут бессмысленно.
        $goneSince   = $null
        $sawHello    = $false
        $helloDue    = (Get-Date).AddSeconds(25)
        $noExtension = $false

        while ($true) {
            [System.Windows.Forms.Application]::DoEvents()

            if ($getContextTask.IsCompleted) {
                $context = $getContextTask.GetAwaiter().GetResult()

                Write-RamCorsHeaders $context.Response

                if ($context.Request.HttpMethod -eq 'OPTIONS') {
                    $context.Response.StatusCode = 204
                    $context.Response.Close()
                    $getContextTask = $listener.GetContextAsync()
                    continue
                }

                $reqStream = $context.Request.InputStream
                $reader    = New-Object System.IO.StreamReader($reqStream, [System.Text.Encoding]::UTF8)
                $body      = $reader.ReadToEnd()
                $reader.Dispose()

                $reqPath = $context.Request.Url.AbsolutePath.ToLowerInvariant()
                if ($reqPath -eq '/hello') { $sawHello = $true }
                if ($reqPath -eq '/cookie' -and -not [string]::IsNullOrWhiteSpace($body)) {
                    $resultCookie = $body.Trim()
                }

                $respBytes = [System.Text.Encoding]::UTF8.GetBytes('ok')
                $context.Response.ContentType = 'text/plain'
                $context.Response.OutputStream.Write($respBytes, 0, $respBytes.Length)
                $context.Response.Close()

                if ($resultCookie) { break }

                $getContextTask = $listener.GetContextAsync()
            }

            if ($null -ne $browserProc -and $browserProc.HasExited) {
                # Не спешим: в первые секунды «процесс исчез» чаще означает,
                # что chrome.exe передал задание уже работающей копии и вышел
                # сам, а не что человек закрыл окно.
                if ($null -eq $goneSince) { $goneSince = Get-Date }
                if (((Get-Date) - $goneSince).TotalSeconds -ge 3) {
                    Write-RamLog 'Внешний браузер: процесс закрыт пользователем до получения куки.' 'info'
                    break
                }
            } else {
                $goneSince = $null
            }

            if (-not $sawHello -and (Get-Date) -gt $helloDue) {
                # Обещание из шапки этого файла, наконец выполненное.
                Write-RamLog 'Внешний браузер: расширение не загрузилось — этот браузер игнорирует --load-extension.' 'err'
                $noExtension = $true
                break
            }

            if ((Get-Date) -gt $deadline) {
                Write-RamLog 'Внешний браузер: истёк таймаут ожидания входа.' 'warn'
                break
            }

            Start-Sleep -Milliseconds 250
        }
    } catch {
        Write-RamLog "Внешний браузер: ошибка во время входа: $($_.Exception.Message)" 'err'
    } finally {
        try { $listener.Stop() } catch { }
        try { $listener.Close() } catch { }

        if ($null -ne $browserProc -and -not $browserProc.HasExited) {
            try { $browserProc.CloseMainWindow() | Out-Null } catch { }
            Start-Sleep -Milliseconds 500
            if (-not $browserProc.HasExited) {
                try { $browserProc.Kill() } catch { }
            }
        }
    }

    if ($noExtension) {
        Show-RamMessage -Kind 'warn' -Message (
            'В этом браузере расширение-мост не загрузилось, поэтому забрать вход из него нечем.' +
            [Environment]::NewLine + [Environment]::NewLine +
            'Так ведёт себя обычный Chrome 137 и новее: он намеренно игнорирует загрузку расширений из командной строки.' +
            [Environment]::NewLine + [Environment]::NewLine +
            'Что делать: скачать Chrome for Testing кнопкой в настройках, разделе «Из браузера» — там этот способ работает всегда. Либо пользоваться другими способами добавить аккаунт.')
    }
    return $resultCookie
}
function Request-RamChromeForTesting {
    <#
      ЕДИНСТВЕННОЕ МЕСТО, откуда вообще может начаться скачивание Chrome for
      Testing. Зовётся только из окна согласия (Show-RamChromeForTestingConsent),
      то есть после того, как человек прочитал, что качается и откуда, и нажал
      кнопку. Самопроверка следит, чтобы Install-RamChromeForTesting не звали
      больше ниоткуда.

      Возвращает $true, если браузер скачан и готов.
    #>
    try {
        $exe = Install-RamChromeForTesting
        if ($exe) {
            Show-RamMessage -Message ('Chrome for Testing скачан и готов.' + [Environment]::NewLine + [Environment]::NewLine +
                                      'Теперь вход через окно браузера будет открываться в нём — капча в нём попадается реже всего.')
            return $true
        }
    } catch {
        Write-RamLog "Chrome for Testing скачать не вышло: $($_.Exception.Message)" 'err'
        Show-RamError -Text ('Скачать не получилось:' + [Environment]::NewLine + [Environment]::NewLine +
                             $_.Exception.Message + [Environment]::NewLine + [Environment]::NewLine +
                             'Ничего страшного: вход через окно браузера работает и на Edge или Chrome, которые уже стоят.')
    }
    return $false
}
