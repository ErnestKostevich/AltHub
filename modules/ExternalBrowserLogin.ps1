#requires -Version 5.1
<#
  Manual Roblox sign-in in an isolated AltHub browser profile.
  Installed Edge/Chrome is the default; Chrome for Testing is optional.
  BrowserLoginCdp reads only the Roblox session cookie through a temporary
  loopback connection. It does not inspect the user's personal browser profile.
  Only the previous Roblox session cookie is removed between sign-ins;
  device cookies remain. No captcha solving, stealth flags or silent download.
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
        $ver = if ($script:AppVersion) { $script:AppVersion } else { '1.4' }
        $client.DefaultRequestHeaders.UserAgent.ParseAdd("AltHub/$ver (Chrome-for-Testing setup)")
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

    $form = New-RamForm
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
    $pct.Text     = (Get-RamText -Text 'подключаюсь...')
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
                $pct.Text = (Get-RamText -Text '{0} %    {1} из {2} МБ' -Arguments @([string]($p),[string]($mbGot),[string]($mbTot)))
            } else {
                $pct.Text = ((Get-RamText -Text 'скачано {0} МБ') -f [Math]::Round($got / 1MB, 1))
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
    Write-RamLog (Get-RamText -Text 'Chrome for Testing: спрашиваю у Google свежую сборку Stable/win64.') 'info'

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

    Write-RamLog (Get-RamText -Text 'Chrome for Testing: качаю {0} (один раз, потом лежит в data\chrome-for-testing).' -Arguments @([string]($ver))) 'info'

    $zip = Join-Path $env:TEMP ('althub-cft-' + [guid]::NewGuid().ToString('N') + '.zip')
    $unpack = Join-Path $dir '_unpack'
    try {
        Invoke-RamVisibleDownload `
            -Title 'AltHub — Chrome for Testing' `
            -Hint (Get-RamText -Text 'Один раз скачивается официальный Chromium от Google. Размер зависит от версии; ход скачивания показан в окне. Обычный Chrome/Edge не затрагивается.') `
            -Url $zipUrl `
            -OutFile $zip

        if (Test-Path -LiteralPath $unpack) {
            Remove-Item -LiteralPath $unpack -Recurse -Force -ErrorAction SilentlyContinue
        }
        [void](New-Item -ItemType Directory -Path $unpack -Force)

        Write-RamLog (Get-RamText -Text 'Chrome for Testing: распаковываю архив.') 'info'
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
        Write-RamLog (Get-RamText -Text 'Chrome for Testing {0} готов: {1}' -Arguments @([string]($ver),[string]($final))) 'ok'
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
            Write-RamLog (Get-RamText -Text 'Chrome for Testing старше 45 дней. Обновить можно кнопкой в настройках — сам он не качается.') 'info'
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
      Установленный Edge/Chrome; сначала браузер по умолчанию Windows,
      если он поддерживается. Никакие команды из реестра не исполняются.
    #>
    $candidates = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )
    $preferChrome = $false
    try { $preferChrome = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction Stop).ProgId -like 'ChromeHTML*' } catch { }
    if ($preferChrome) { $candidates = @($candidates | Sort-Object { if ($_ -like '*\Google\Chrome\*') { 0 } else { 1 } }) }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }

    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'
    )
    if ($preferChrome) { $regPaths = @($regPaths | Sort-Object { if ($_ -like '*\chrome.exe') { 0 } else { 1 } }) }
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
        'edge'  { 'edge-login-profile' }
        default { 'chrome-login-profile' }
    }
    $dir = Join-Path (Get-RamDataDir) $name

    # ПРОГРЕТЫЙ ПРОФИЛЬ НЕ ВЫБРАСЫВАЕМ. До 1.4 обычный Chrome и Edge жили в
    # общей папке externalbrowserprofile. Капча Roblox (Arkose) узнаёт
    # устройство по накопленному профилю и со временем показывает задания
    # проще. Новая пустая папка вернула бы каждому человеку после обновления
    # капчу «как в первый раз» — поэтому старую переносим, а не заводим чистую.
    if ($Kind -ne 'cft' -and -not (Test-Path -LiteralPath $dir)) {
        $legacy = Join-Path (Get-RamDataDir) 'externalbrowserprofile'
        if (Test-Path -LiteralPath $legacy) {
            try {
                if (-not (Stop-RamProfileBrowsers -ProfileDir $legacy)) { throw 'Previous sign-in profile is still busy.' }
                Move-Item -LiteralPath $legacy -Destination $dir -ErrorAction Stop
                Write-RamLog (Get-RamText -Text 'Профиль окна входа перенесён из externalbrowserprofile в {0} — прогрев сохранён.' -Arguments @([string]($name))) 'info'
            } catch {
                # Папку держит работающий браузер. Пользуемся ею под старым
                # именем: пустой профиль хуже некрасивого имени папки.
                Write-RamLog (Get-RamText -Text 'Старый профиль окна входа занят, пользуюсь им без переноса: {0}' -Arguments @([string]((Get-RamErrorText -Text ($($_.Exception.Message)))))) 'warn'
                return $legacy
            }
        }
    }

    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    return $dir
}

function Get-RamProfileBrowserProcesses {
    param([Parameter(Mandatory)][string]$ProfileDir)
    $full = [System.IO.Path]::GetFullPath($ProfileDir).TrimEnd('\')
    $escaped = [regex]::Escape($full)
    $profileArg = '(?:^|\s)(?:"--user-data-dir=' + $escaped + '"|--user-data-dir="' + $escaped + '"|--user-data-dir=' + $escaped + ')(?=\s|$)'
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction Stop |
        Where-Object { [string]$_.CommandLine -match $profileArg }
}

function Stop-RamProfileBrowsers {
    <# Завершает только процессы браузера, запущенные с точным профилем AltHub. #>
    param([Parameter(Mandatory)][string]$ProfileDir)
    $full = [System.IO.Path]::GetFullPath($ProfileDir).TrimEnd('\')
    $procs = @(Get-RamProfileBrowserProcesses -ProfileDir $ProfileDir)
    foreach ($p in $procs) {
        try {
            $process = Get-Process -Id ([int]$p.ProcessId) -ErrorAction Stop
            [void]$process.CloseMainWindow()
        } catch { }
    }
    $grace = [datetime]::UtcNow.AddSeconds(2)
    while ($procs.Count -gt 0 -and [datetime]::UtcNow -lt $grace) {
        Start-Sleep -Milliseconds 100
        $procs = @(Get-RamProfileBrowserProcesses -ProfileDir $ProfileDir)
    }
    foreach ($p in ($procs | Sort-Object ProcessId -Descending)) {
        try { Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction Stop } catch { }
    }
    $until = (Get-Date).AddSeconds(4)
    do {
        $left = @(Get-RamProfileBrowserProcesses -ProfileDir $ProfileDir)
        if ($left.Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $until)
    if ($left.Count -eq 0) {
        foreach ($name in @('SingletonLock','SingletonSocket','SingletonCookie')) {
            $lockPath = Join-Path $full $name
            if (([System.IO.Path]::GetFullPath($lockPath)).StartsWith($full, [System.StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    return ($left.Count -eq 0)
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
      протокол браузера, только внутри этого профиля.
      Плюс правим Preferences: exit_type=Normal, exited_cleanly=true,
      чтобы Chrome не показывал жёлтую плашку восстановления.
    #>
    param([Parameter(Mandatory)][string]$ProfileDir)

    $default = Join-Path $ProfileDir 'Default'
    if (-not (Test-Path -LiteralPath $default)) { [void](New-Item -ItemType Directory -Path $default -Force) }

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
                catch { Write-RamLog (Get-RamText -Text 'Профиль: не удалось удалить {0}: {1}' -Arguments @([string]($($_.Name)),[string]((Get-RamErrorText -Text ($($_.Exception.Message)))))) 'warn' }
            }
    }
    $sessionsDir = Join-Path $default 'Sessions'
    if (Test-Path -LiteralPath $sessionsDir) {
        try { Remove-Item -LiteralPath $sessionsDir -Recurse -Force -ErrorAction Stop }
        catch { Write-RamLog (Get-RamText -Text 'Профиль: не удалось очистить Sessions\: {0}' -Arguments @([string]((Get-RamErrorText -Text ($($_.Exception.Message)))))) 'warn' }
    }

    $prefsPath = Join-Path $default 'Preferences'
        try {
            $prefs = if (Test-Path -LiteralPath $prefsPath) {
                Get-Content -LiteralPath $prefsPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } else { [pscustomobject]@{} }
            if ($null -eq $prefs.profile) {
                $prefs | Add-Member -NotePropertyName 'profile' -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $prefs.profile | Add-Member -NotePropertyName 'exit_type'      -NotePropertyValue 'Normal' -Force
            $prefs.profile | Add-Member -NotePropertyName 'exited_cleanly' -NotePropertyValue $true    -Force
            foreach ($name in @('translate','intl')) {
                if ($null -eq $prefs.$name) { $prefs | Add-Member -NotePropertyName $name -NotePropertyValue ([pscustomobject]@{}) -Force }
            }
            $prefs.translate | Add-Member -NotePropertyName 'enabled' -NotePropertyValue $false -Force
            $prefs.intl | Add-Member -NotePropertyName 'accept_languages' -NotePropertyValue 'en-US,en' -Force
            ($prefs | ConvertTo-Json -Depth 100 -Compress) |
                Set-Content -LiteralPath $prefsPath -Encoding UTF8 -NoNewline
        } catch {
            Write-RamLog (Get-RamText -Text 'Профиль: не удалось поправить Preferences: {0}' -Arguments @([string]((Get-RamErrorText -Text ($($_.Exception.Message)))))) 'warn'
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



function Show-RamExternalBrowserLoginWindow {
    param(
        [string]$Root = $script:Root,
        [ValidateRange(1,1800)][int]$TimeoutSeconds = 300
    )
    # DoEvents keeps the form responsive, but must not permit nested sign-in.
    if ($script:RamExternalBrowserLoginBusy) { return $null }
    $script:RamExternalBrowserLoginBusy = $true
    $profileDir = $null; $browserProc = $null; $started = $false
    $connectionFailed = $false; $resultCookie = $null; $stage = 'profile'; $failureType = 'unavailable'
    $safeReasons = @{
        'Browser connection timed out.' = 'timeout'
        'Browser target discovery failed.' = 'discovery-status'
        'Browser response is too large.' = 'response-size'
        'Browser returned an invalid target response.' = 'discovery-json'
        'Browser returned an invalid local connection address.' = 'endpoint-rejected'
        'Browser connection closed or returned non-text data.' = 'channel-closed'
        'Browser returned an invalid protocol response.' = 'protocol-json'
        'Browser rejected the cookie request.' = 'protocol-rejected'
        'Browser could not open the sign-in page.' = 'navigation-failed'
    }
    try {
        $browserKind = 'system'
        if ($null -ne $script:Settings -and $script:Settings.BrowserLoginBrowser -eq 'cft') { $browserKind = 'cft' }
        $browserExe = if ($browserKind -eq 'cft') { Get-RamChromeForTestingPath } else { Get-RamInstalledBrowserPath }
        if (-not $browserExe) {
            [void](Show-RamMessage -Kind 'warn' -Message (Get-RamText -Text 'Выбранный браузер не найден. В настройках «Из браузера» выбери установленный Chrome/Edge или отдельно скачай Chrome for Testing. Вход ничего не скачивает автоматически.'))
            return $null
        }
        if ($browserKind -ne 'cft') { $browserKind = if ($browserExe -match 'msedge\.exe$') { 'edge' } else { 'chrome' } }
        $profileDir = Get-RamExternalBrowserProfileDir -Kind $browserKind
        if (-not (Stop-RamProfileBrowsers -ProfileDir $profileDir)) {
            [void](Show-RamMessage -Kind 'warn' -Message (Get-RamText -Text 'Предыдущее окно входа ещё занято. Закрой его и повтори. Профиль не изменён.'))
            return $null
        }
        Clear-RamExternalBrowserProfileState -ProfileDir $profileDir
        $port = Get-RamFreeLocalPort
        $procArgs = @(
            (ConvertTo-RamChromeArg -Name '--user-data-dir' -Value $profileDir)
            "--remote-debugging-port=$port"
            '--remote-debugging-address=127.0.0.1'
            '--no-first-run'
            '--no-default-browser-check'
            '--disable-session-crashed-bubble'
            '--disable-features=Translate'
            '--lang=en-US'
            '--window-size=520,760'
            '--window-position=200,120'
        )
        if ($browserKind -eq 'edge') { $procArgs += @('--no-service-autorun','--disable-sync','--edge-skip-first-run') }
        $windowArgs = $procArgs
        $procArgs += '--app=data:text/html,AltHub'
        $appWindow = $true
        Write-RamLog (Get-RamText -Text 'Окно входа: {0}; отдельный профиль AltHub, без расширения и скачивания браузера.' -Arguments @($browserKind)) 'info'
        $browserProc = Start-RamLoginBrowser -BrowserExe $browserExe -ProcArgs $procArgs
        $started = $true
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $connectDue = (Get-Date).AddSeconds(15)
        $launchGrace = (Get-Date).AddSeconds(3)
        $session = $null; $previousCookie = $null; $lastCandidate = $null; $retryAt = [datetime]::MinValue
        $authRetryAt = [datetime]::MinValue
        $nextPoll = [datetime]::MinValue; $failures = 0
        while ((Get-Date) -lt $deadline) {
            [Windows.Forms.Application]::DoEvents()
            $now = Get-Date
            if ($now -ge $deadline) { break }
            if ($now -lt $nextPoll) { Start-Sleep -Milliseconds 50; continue }
            $nextPoll = $now.AddMilliseconds(400)
            # Edge/Chrome can hand off startup to another process in this profile.
            if ($null -ne $browserProc -and $browserProc.HasExited -and $now -ge $launchGrace -and
                @(Get-RamProfileBrowserProcesses -ProfileDir $profileDir).Count -eq 0) {
                # A clean early exit is cancellation, not proof that app mode failed.
                if ($appWindow -and $null -eq $session -and $browserProc.ExitCode -is [int] -and $browserProc.ExitCode -ne 0) {
                    Write-RamLog (Get-RamText -Text 'Компактное окно браузера завершилось с кодом {0}; пробую обычное окно один раз.' -Arguments @($browserProc.ExitCode)) 'warn'
                    $appWindow = $false
                    $browserProc = Start-RamLoginBrowser -BrowserExe $browserExe -ProcArgs ($windowArgs + @('--new-window','about:blank'))
                    $launchGrace = $now.AddSeconds(3)
                    $connectDue = $now.AddSeconds(15)
                    continue
                }
                break
            }
            try {
                if ($null -eq $session) {
                    $stage = 'connection'
                    $session = Initialize-RamLoginCdpSession -Port $port
                    if ($null -ne $session) { $previousCookie = $session.PreviousCookie }
                    elseif ($now -ge $connectDue) { $connectionFailed = $true; break }
                    continue
                }
                $stage = 'cookie-read'
                $candidate = Get-RamBrowserLoginCookie -Port $port
                $failures = 0
                if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate -ceq $previousCookie) { continue }
                if ($candidate.Length -gt 16384 -or $candidate -match '[\x00-\x20\x7f]') { continue }
                if ($now -lt $authRetryAt) { continue }
                if ($candidate -ceq $lastCandidate -and $now -lt $retryAt) { continue }
                $lastCandidate = $candidate
                $stage = 'account-validation'
                $check = Test-RamAuthenticatedUser -Cookie $candidate
                if ($check.State -eq 'valid') { $resultCookie = $candidate; break }
                $retryAt = if ($check.State -eq 'unauthorized') { $deadline } else { $now.AddSeconds(5) }
                if ($check.State -ne 'unauthorized') {
                    $cooldown = 5
                    if ($check.State -eq 'rate_limited' -and ($check.RetryAfterSeconds -is [int] -or $check.RetryAfterSeconds -is [long])) {
                        $cooldown = [Math]::Max(5,[int]$check.RetryAfterSeconds)
                    }
                    $authRetryAt = $now.AddSeconds($cooldown)
                }
            } catch {
                # A closing tab can briefly lose its target; never log protocol bodies/cookies.
                $failures++
                $failureType = $_.Exception.GetType().Name
                if ($safeReasons.ContainsKey($_.Exception.Message)) { $failureType = $safeReasons[$_.Exception.Message] }
                if (($null -eq $session -and (Get-Date) -ge $connectDue) -or ($null -ne $session -and $failures -ge 3)) {
                    $connectionFailed = $true; break
                }
            }
        }
    } catch {
        $connectionFailed = $true
        $failureType = $_.Exception.GetType().Name
    } finally {
        try {
            if ($started) {
                try {
                    if (-not (Clear-RamBrowserLoginCookie -Port $port)) {
                        Write-RamLog (Get-RamText -Text 'Окно входа уже закрыто: удалить локальную куку через браузер не удалось. Следующий вход очистит её до открытия Roblox.') 'warn'
                    }
                } catch {
                    Write-RamLog (Get-RamText -Text 'Локальная кука окна входа не очищена. Следующий вход очистит её до открытия Roblox.') 'warn'
                }
            }
            if ($started -and $profileDir -and -not (Stop-RamProfileBrowsers -ProfileDir $profileDir)) {
                $connectionFailed = $true; $stage = 'cleanup'; $failureType = 'profile-busy'
            }
        } catch { $connectionFailed = $true; $stage = 'cleanup'; $failureType = $_.Exception.GetType().Name }
        finally { $script:RamExternalBrowserLoginBusy = $false }
    }
    if ($connectionFailed) {
        $resultCookie = $null
        Write-RamLog (Get-RamText -Text 'Окно входа: сбой на этапе {0} ({1}).' -Arguments @($stage,$failureType)) 'warn'
        Write-RamLog (Get-RamText -Text 'Не удалось подключить окно входа. Вход не получен; данные аккаунта не изменены.') 'warn'
        [void](Show-RamMessage -Kind 'warn' -Message (Get-RamText -Text 'Не удалось подключить окно входа. Возможны ограничения политик браузера или ошибка запуска. Можно выбрать другой браузер в настройках «Из браузера» или другой способ добавления аккаунта. Chrome for Testing необязателен.'))
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
            [void](Show-RamMessage -Message ((Get-RamText -Text 'Chrome for Testing скачан и готов.') + [Environment]::NewLine + [Environment]::NewLine +
                                      (Get-RamText -Text 'Чтобы использовать его для входа, выбери Chrome for Testing в настройках «Из браузера» и сохрани настройки.')))
            return $true
        }
    } catch {
        Write-RamLog (Get-RamText -Text 'Chrome for Testing скачать не вышло: {0}' -Arguments @([string]((Get-RamErrorText -Text ($($_.Exception.Message)))))) 'err'
        [void](Show-RamError -Text ((Get-RamText -Text 'Скачать не получилось:') + [Environment]::NewLine + [Environment]::NewLine +
                             $_.Exception.Message + [Environment]::NewLine + [Environment]::NewLine +
                             (Get-RamText -Text 'Можно выбрать установленный Chrome/Edge в настройках «Из браузера» или другой способ добавления аккаунта без скачивания.')))
    }
    return $false
}
