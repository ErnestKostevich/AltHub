#requires -Version 5.1
<#
================================================================================
 Проверка запуска.ps1 — проверяет то, что видит человек
================================================================================
 Запуск:
   powershell -NoProfile -ExecutionPolicy Bypass -File "Проверка запуска.ps1"

 ЗАЧЕМ ОН НУЖЕН.
 Самопроверка.ps1 гоняет код и собирает окна «вхолостую», не показывая их.
 Этого оказалось мало: три выпуска подряд были зелёными по всем проверкам и
 при этом ломались у человека с первого клика — то окно не появлялось, то
 вместо запуска сыпался мусор, то значок в часах был пустым. Такой класс
 ошибок «холодная» проверка увидеть не может в принципе.

 Этот стенд запускает программу ТАК ЖЕ, КАК ЧЕЛОВЕК — двойным кликом по
 AltHub.vbs — и смотрит глазами Windows: появилось ли окно, нет ли чёрной
 консоли, что происходит при сворачивании и закрытии, не плодятся ли копии.

 ВАЖНО: гонять на РАСПАКОВАННОМ АРХИВЕ, а не на рабочей папке. Ломалось
 именно то, что попадало в архив (кодировки файлов, .vbs), — в рабочей папке
 это выглядело нормально.

 Ничего не меняет в твоих данных: работает во временной копии.
================================================================================
#>

param(
    # Папка со сборкой. По умолчанию — та, где лежит этот файл.
    [string]$Path = $PSScriptRoot,
    # Не удалять временную копию после прогона (чтобы посмотреть журнал).
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace RamCheck -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
[DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
'@

$script:total = 0
$script:passed = 0

function Step {
    param([string]$Name, [scriptblock]$Body)
    $script:total++
    try {
        $detail = & $Body
        $script:passed++
        Write-Host ("  OK   {0}" -f $Name) -ForegroundColor Green
        if ($detail) { Write-Host ("       {0}" -f $detail) -ForegroundColor DarkGray }
    } catch {
        Write-Host ("  СБОЙ {0}" -f $Name) -ForegroundColor Red
        Write-Host ("       {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

# --------------------------------------------------------------- окна ------

function Get-RamWindowsOf {
    <# Все окна процесса: дескриптор, видимость, заголовок и класс. #>
    param([int]$ProcessId)
    $found = New-Object System.Collections.ArrayList
    $cb = [RamCheck.Win+EnumWindowsProc]{
        param($h, $l)
        $q = 0
        [void][RamCheck.Win]::GetWindowThreadProcessId($h, [ref]$q)
        if ($q -eq $ProcessId) {
            $sb = New-Object System.Text.StringBuilder 512
            [void][RamCheck.Win]::GetWindowTextW($h, $sb, 512)
            $cn = New-Object System.Text.StringBuilder 256
            [void][RamCheck.Win]::GetClassNameW($h, $cn, 256)
            [void]$found.Add([pscustomobject]@{
                Handle  = $h
                Visible = [RamCheck.Win]::IsWindowVisible($h)
                Title   = $sb.ToString()
                Class   = $cn.ToString()
            })
        }
        return $true
    }
    [void][RamCheck.Win]::EnumWindows($cb, [IntPtr]::Zero)
    return @($found)
}

function Get-RamAppWindow {
    <# Главное окно AltHub среди окон процесса. #>
    param([int]$ProcessId)
    foreach ($w in (Get-RamWindowsOf -ProcessId $ProcessId)) {
        if ($w.Title -eq 'AltHub' -and $w.Class -like 'WindowsForms*') { return $w }
    }
    return $null
}

function Get-RamConsoleWindows {
    <# Видимые окна консоли процесса — их быть не должно. #>
    param([int]$ProcessId)
    $bad = @()
    foreach ($w in (Get-RamWindowsOf -ProcessId $ProcessId)) {
        if (-not $w.Visible) { continue }
        if ($w.Class -match 'ConsoleWindowClass|CASCADIA_HOSTING|PseudoConsoleWindow') {
            $bad += ("{0} [{1}]" -f $w.Class, $w.Title)
        }
    }
    return $bad
}

function Wait-RamAppWindow {
    <# Ждём появления окна до N секунд. Возвращает @{ Proc; Win } или $null. #>
    param([int[]]$Before, [int]$Seconds = 25)
    $until = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $until) {
        foreach ($p in @(Get-Process -Name powershell -ErrorAction SilentlyContinue)) {
            if ($Before -contains $p.Id) { continue }
            $w = Get-RamAppWindow -ProcessId $p.Id
            if ($null -ne $w -and $w.Visible) {
                return [pscustomobject]@{ Proc = $p; Win = $w }
            }
        }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

function Get-RamOurProcesses {
    param([int[]]$Before)
    return @(Get-Process -Name powershell -ErrorAction SilentlyContinue |
             Where-Object { $Before -notcontains $_.Id })
}

function Stop-RamAll {
    param([int[]]$Before)
    foreach ($p in (Get-RamOurProcesses -Before $Before)) {
        try { $p.Kill() } catch { }
    }
    Start-Sleep -Seconds 1
}

# --------------------------------------------------------------- подготовка -

Write-Host ''
Write-Host 'AltHub — проверка запуска (то, что видит человек)' -ForegroundColor Cyan
Write-Host '--------------------------------------------------'

$src = (Resolve-Path $Path).Path
if (-not (Test-Path -LiteralPath (Join-Path $src 'AltHub.ps1'))) {
    Write-Host "  В папке нет AltHub.ps1: $src" -ForegroundColor Red
    Read-Host 'Enter — выход'; exit 1
}

# Работаем во временной копии: настоящие данные не трогаем.
$work = Join-Path $env:TEMP ('althub-launch-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
foreach ($f in (Get-ChildItem -LiteralPath $src -File)) { Copy-Item $f.FullName $work }
foreach ($d in @('modules', 'tools')) {
    $p = Join-Path $src $d
    if (Test-Path -LiteralPath $p) { Copy-Item $p $work -Recurse }
}
Write-Host ("  Копия для прогона: {0}" -f $work) -ForegroundColor DarkGray

# Мастер первого запуска здесь только мешает: он показывает СВОЁ окно, и
# главное до проверки не доходит. Отмечаем настройку пройденной, чтобы
# проверять именно то, что человек видит каждый день.
$dataDir = Join-Path $work 'data'
New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
$seed = [pscustomobject]@{
    FirstRunDone     = $true
    CheckOnStart     = $false   # без сети: проверка входов тут не нужна
    OnClose          = 'tray'   # проверяем самый опасный режим
    # Вопрос «видишь значок?» задаётся человеку, а стенду отвечать некому —
    # иначе проверка крестика упрётся в модальное окно. Отмечаем заранее.
    TrayConfirmed    = $true
    TrayHintShown    = $true
    WindowFixApplied = $true
}
ConvertTo-Json -InputObject $seed -Depth 3 |
    Set-Content -LiteralPath (Join-Path $dataDir 'settings.json') -Encoding UTF8
Write-Host ''

$vbs = Join-Path $work 'AltHub.vbs'

# Оставшиеся с прошлого прогона копии надо убрать: они держат замок «одна
# копия», и тогда проверка второго запуска врёт — новая копия честно не
# запускается, но не потому, что защита сработала, а потому что мешает старая.
foreach ($p in @(Get-Process -Name powershell -ErrorAction SilentlyContinue)) {
    if ($null -ne (Get-RamAppWindow -ProcessId $p.Id)) {
        try { $p.Kill() } catch { }
    }
}
Start-Sleep -Seconds 2

$before = @(Get-Process -Name powershell -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })

# --------------------------------------------------------------- проверки ---

$app = $null

Step 'Окно появляется после двойного клика по AltHub.vbs' {
    if (-not (Test-Path -LiteralPath $vbs)) { throw 'AltHub.vbs нет в сборке' }
    Start-Process wscript.exe -ArgumentList $vbs
    $script:app = Wait-RamAppWindow -Before $before -Seconds 30
    if ($null -eq $script:app) {
        throw 'окно AltHub так и не появилось — для человека это выглядит как «не запускается»'
    }
    "окно нашлось за отведённое время, процесс $($script:app.Proc.Id)"
}

Step 'Чёрного окна консоли нет' {
    if ($null -eq $script:app) { throw 'пропущено: окна нет' }
    $bad = Get-RamConsoleWindows -ProcessId $script:app.Proc.Id
    if ($bad.Count) { throw ('видно консоль: ' + ($bad -join ', ')) }
    'у процесса нет ни одного видимого окна консоли'
}

Step 'Минус сворачивает окно, а не прячет его' {
    if ($null -eq $script:app) { throw 'пропущено: окна нет' }
    $h = $script:app.Win.Handle
    # WM_SYSCOMMAND / SC_MINIMIZE — то же, что нажатие на минус
    [void][RamCheck.Win]::PostMessageW($h, 0x0112, [IntPtr]0xF020, [IntPtr]::Zero)
    Start-Sleep -Seconds 3

    if (-not [RamCheck.Win]::IsWindow($h)) { throw 'окно исчезло совсем' }
    if (-not [RamCheck.Win]::IsWindowVisible($h)) {
        throw 'окно спрятано, а не свёрнуто — из панели задач оно пропало, вернуть нечем'
    }
    if (-not [RamCheck.Win]::IsIconic($h)) { throw 'окно не свернулось' }

    # возвращаем обратно
    [void][RamCheck.Win]::PostMessageW($h, 0x0112, [IntPtr]0xF120, [IntPtr]::Zero)
    Start-Sleep -Seconds 2
    'свёрнуто в панель задач и восстановилось'
}

Step 'Второй запуск возвращает окно, а не открывает копию' {
    if ($null -eq $script:app) { throw 'пропущено: окна нет' }
    # Считаем ОКНА, а не процессы. Процесс второй копии живёт несколько секунд,
    # пока подгружает модули, и только потом понимает, что программа уже
    # запущена, и уходит. Человека же волнует одно: не появилось ли второе окно.
    Start-Process wscript.exe -ArgumentList $vbs
    Start-Sleep -Seconds 14

    $windows = 0
    foreach ($p in @(Get-Process -Name powershell -ErrorAction SilentlyContinue)) {
        if ($null -ne (Get-RamAppWindow -ProcessId $p.Id)) { $windows++ }
    }
    if ($windows -gt 1) {
        throw "на экране $windows окон AltHub — вторая копия всё-таки открылась"
    }
    if ($windows -eq 0) { throw 'после повторного запуска не осталось ни одного окна' }
    if (-not [RamCheck.Win]::IsWindowVisible($script:app.Win.Handle)) {
        throw 'повторный запуск не вернул окно'
    }
    'копия не появилась, окно на месте'
}

Step 'Крестик не оставляет программу без следа' {
    if ($null -eq $script:app) { throw 'пропущено: окна нет' }
    $h = $script:app.Win.Handle
    # ИМЕННО WM_SYSCOMMAND / SC_CLOSE — это нажатие на крестик.
    # Простой WM_CLOSE со стороны Windows считает закрытием из диспетчера
    # задач (CloseReason = TaskManagerClosing), и программа тогда НЕ уходит
    # в часы — и правильно делает. Проверять надо тем же событием, что
    # получает программа от живого клика.
    [void][RamCheck.Win]::SendMessageW($h, 0x0112, [IntPtr]0xF060, [IntPtr]::Zero)
    Start-Sleep -Seconds 5

    # Смотрим на КОНКРЕТНЫЙ процесс, а не «есть ли вообще наши»: к этому шагу
    # уже запускалась и завершилась вторая копия, и общий счётчик врал.
    $proc = $null
    try { $proc = Get-Process -Id $script:app.Proc.Id -ErrorAction Stop } catch { }
    $alive   = ($null -ne $proc -and -not $proc.HasExited)
    $winAlive = [RamCheck.Win]::IsWindow($h)
    $winVis   = $winAlive -and [RamCheck.Win]::IsWindowVisible($h)

    if (-not $alive) { return 'крестик закрыл программу — режим «закрыть»' }
    if ($alive -and -not $winVis) {
        return 'крестик убрал в часы: процесс жив, окно скрыто, вернуть можно значком или повторным запуском'
    }
    throw 'после крестика окно осталось на экране — ни закрылось, ни ушло в часы'
}

# --------------------------------------------------------------- уборка -----

Stop-RamAll -Before $before
if (-not $Keep) {
    try { Remove-Item -LiteralPath $work -Recurse -Force } catch { }
} else {
    Write-Host ("  Копия оставлена: {0}" -f $work) -ForegroundColor DarkGray
}

Write-Host ''
Write-Host '--------------------------------------------------'
if ($script:passed -eq $script:total) {
    Write-Host ("Пройдено {0} из {1} — запуск в порядке." -f $script:passed, $script:total) -ForegroundColor Green
} else {
    Write-Host ("Пройдено {0} из {1} — есть проблемы, смотри красное выше." -f $script:passed, $script:total) -ForegroundColor Red
}
Write-Host ''
Read-Host 'Enter — закрыть'
