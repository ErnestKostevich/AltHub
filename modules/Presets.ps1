#requires -Version 5.1
<#
================================================================================
 modules\Presets.ps1 — железо компьютера и готовые наборы настроек
================================================================================
 В сеть не ходит и ничего не пишет на диск. Только читает сведения о железе
 через CIM и раздаёт готовые наборы настроек для аккаунта.

 Зачем: людям некогда разбираться, что такое «SavedQualityLevel» и сколько
 клиентов вытянет их ноутбук. Один щелчок должен давать разумный результат.
================================================================================
#>

# --------------------------------------------------------------- железо ----

function Get-RamHardware {
    <#
      Память, ядра, видеокарта и экран. Запрос к CIM небыстрый (сотни
      миллисекунд), поэтому спрашиваем один раз за запуск и запоминаем.

      -Fresh заставляет спросить заново.

      Ничего не бросает: на машине с урезанным WMI просто вернутся нули, и
      всё, что на этом построено, обязано это пережить.
    #>
    param([switch]$Fresh)

    if (-not $Fresh -and $null -ne $script:RamHardwareCache) { return $script:RamHardwareCache }

    $ramGb   = 0.0
    $cores   = 0
    $threads = 0
    $cpuName = ''
    $gpuName = ''
    $vramGb  = 0.0
    $scrW    = 0
    $scrH    = 0

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($null -ne $cs) {
            $ramGb   = [math]::Round([double]$cs.TotalPhysicalMemory / 1GB, 1)
            $threads = [int]$cs.NumberOfLogicalProcessors
        }
    } catch { }

    try {
        foreach ($p in @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)) {
            $cores += [int]$p.NumberOfCores
            if (-not $cpuName) { $cpuName = ([string]$p.Name).Trim() }
        }
    } catch { }

    try {
        # Берём карту с наибольшей памятью: у ноутбуков рядом со встроенной
        # обычно висит дискретная, и интересна как раз она.
        $best = $null
        foreach ($v in @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)) {
            if ($null -eq $best -or [double]$v.AdapterRAM -gt [double]$best.AdapterRAM) { $best = $v }
        }
        if ($null -ne $best) {
            $gpuName = ([string]$best.Name).Trim()
            # AdapterRAM — 32-битное поле: у карт с 4 ГБ и больше оно врёт
            # или переполняется. Отрицательное и нулевое считаем «не знаю».
            $ram = [double]$best.AdapterRAM
            if ($ram -gt 0) { $vramGb = [math]::Round($ram / 1GB, 1) }
        }
    } catch { }

    try {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $scrW = [int]$wa.Width
        $scrH = [int]$wa.Height
    } catch { }

    if ($threads -le 0) { $threads = [int]$env:NUMBER_OF_PROCESSORS }
    if ($threads -le 0) { $threads = 1 }
    if ($cores   -le 0) { $cores = $threads }

    $script:RamHardwareCache = [pscustomobject]@{
        RamGb        = $ramGb
        Cores        = $cores
        Threads      = $threads
        CpuName      = $cpuName
        GpuName      = $gpuName
        VramGb       = $vramGb
        ScreenWidth  = $scrW
        ScreenHeight = $scrH
        Known        = ($ramGb -gt 0)
    }
    return $script:RamHardwareCache
}

function Get-RamRecommendedAccountCount {
    <#
      Сколько клиентов Roblox машина вытянет одновременно.

      Считаем по двум пределам и берём меньший:
        память — один клиент съедает около 1.5 ГБ, системе оставляем 4 ГБ;
        ядра   — примерно один клиент на полтора потока.

      Числа нарочно осторожные. Лучше посоветовать четыре и получить ровную
      работу, чем восемь и своп на весь компьютер.
    #>
    param($Hardware)

    if ($null -eq $Hardware) { $Hardware = Get-RamHardware }
    if (-not $Hardware.Known) { return 2 }

    $free   = [double]$Hardware.RamGb - 4.0
    $byRam  = [int][math]::Floor($free / 1.5)
    $byCpu  = [int][math]::Floor([double]$Hardware.Threads / 1.5)

    $n = [Math]::Min($byRam, $byCpu)
    if ($n -lt 1)  { $n = 1 }
    if ($n -gt 12) { $n = 12 }
    return $n
}

function Get-RamHardwareSummary {
    <# Одна строка про железо — для мастера и для настроек. #>
    param($Hardware)

    if ($null -eq $Hardware) { $Hardware = Get-RamHardware }
    if (-not $Hardware.Known) { return 'Не удалось определить железо — посоветовать нечего, ставь на глаз.' }

    $parts = @()
    $parts += ('{0} ГБ памяти' -f $Hardware.RamGb)
    $parts += ('{0} ядер / {1} потоков' -f $Hardware.Cores, $Hardware.Threads)
    if ($Hardware.GpuName) { $parts += $Hardware.GpuName }
    return ($parts -join '  ·  ')
}

function Get-RamHardwareAdvice {
    <#
      Что из этого следует, по-человечески. Возвращает объект, а не строку:
      мастеру нужен ещё и предлагаемый пресет, и рекомендуемое число окон.
    #>
    param($Hardware)

    if ($null -eq $Hardware) { $Hardware = Get-RamHardware }
    $max = Get-RamRecommendedAccountCount -Hardware $Hardware

    if (-not $Hardware.Known) {
        return [pscustomobject]@{
            MaxAccounts = $max
            Tier        = 'unknown'
            Preset      = 'balanced'
            Text        = 'Железо определить не вышло. Начни с двух аккаунтов и средних настроек, дальше посмотришь по ощущениям.'
        }
    }

    $ram = [double]$Hardware.RamGb
    if ($ram -lt 8) {
        $tier = 'weak';   $preset = 'twink'
        $text = "Машина скромная: {0} ГБ памяти. Больше {1} клиентов сразу лучше не открывать, и всем твинкам ставить графику 1-2." -f $Hardware.RamGb, $max
    } elseif ($ram -lt 16) {
        $tier = 'normal'; $preset = 'balanced'
        $text = "Обычная машина: {0} ГБ памяти. Спокойно потянет {1} клиентов, если твинкам поставить графику пониже." -f $Hardware.RamGb, $max
    } else {
        $tier = 'strong'; $preset = 'balanced'
        $text = "Машина мощная: {0} ГБ памяти, {1} потоков. Потянет {2} клиентов; основному можно ставить максимум графики." -f $Hardware.RamGb, $Hardware.Threads, $max
    }

    return [pscustomobject]@{
        MaxAccounts = $max
        Tier        = $tier
        Preset      = $preset
        Text        = $text
    }
}

# -------------------------------------------------------------- пресеты ----

function Get-RamAccountPresets {
    <#
      Готовые наборы настроек аккаунта.

      Fullscreen у всех «в окне»: AltHub раскладывает окна по экрану, а из
      полноэкранного режима клиент выдёргивать нельзя — раскладка ломается.
      Кому нужен полный экран, ставит его руками в настройках аккаунта.
    #>
    @(
        [pscustomobject]@{
            Key      = 'main'
            Title    = 'Основной — красиво'
            Hint     = 'Максимум графики, без предела кадров, звук на полную. Для того аккаунта, в который реально играешь.'
            Graphics = '10'
            Fps      = '0'
            Volume   = '100'
            Screen   = 'no'
        },
        [pscustomobject]@{
            Key      = 'balanced'
            Title    = 'Сбалансированно'
            Hint     = 'Середина по графике, 60 кадров, звук вполовину. Разумно, если непонятно с чего начать.'
            Graphics = '5'
            Fps      = '60'
            Volume   = '50'
            Screen   = 'no'
        },
        [pscustomobject]@{
            Key      = 'twink'
            Title    = 'Твинк — легко тянет'
            Hint     = 'Графика 2, 60 кадров, звук выключен. Играбельно, но почти не грузит машину.'
            Graphics = '2'
            Fps      = '60'
            Volume   = '0'
            Screen   = 'no'
        },
        [pscustomobject]@{
            Key      = 'farm'
            Title    = 'Фоновый фарм'
            Hint     = 'Минимум графики, 30 кадров, тишина. Для окон, в которые не смотришь.'
            Graphics = '1'
            Fps      = '30'
            Volume   = '0'
            Screen   = 'no'
        }
    )
}

function Get-RamPreset {
    param([Parameter(Mandatory)][string]$Key)
    return (Get-RamAccountPresets | Where-Object { $_.Key -eq $Key } | Select-Object -First 1)
}

function Set-RamAccountPreset {
    <#
      Проставляет аккаунту настройки из набора. Меняет только графику, кадры,
      звук и оконный режим — имя, кука и игра не трогаются.

      Возвращает $true, если набор нашёлся.
    #>
    param(
        [Parameter(Mandatory)]$Account,
        [Parameter(Mandatory)][string]$Key
    )

    $p = Get-RamPreset -Key $Key
    if ($null -eq $p) { return $false }

    $Account.Graphics     = $p.Graphics
    $Account.FramerateCap = $p.Fps
    $Account.Volume       = $p.Volume
    $Account.Fullscreen   = $p.Screen
    return $true
}

function Get-RamPresetChoices {
    <# Пары для New-RamCombo: «не менять» плюс сами наборы. #>
    $items = @([pscustomobject]@{ Text = 'не менять'; Value = '' })
    foreach ($p in Get-RamAccountPresets) {
        $items += [pscustomobject]@{ Text = $p.Title; Value = $p.Key }
    }
    return ,$items
}

function Get-RamMatchingPreset {
    <#
      Какой набор соответствует текущим настройкам аккаунта, если какой-то
      соответствует. Нужно, чтобы в окне аккаунта подсветить выбранный.
    #>
    param($Account)
    if ($null -eq $Account) { return '' }

    foreach ($p in Get-RamAccountPresets) {
        if ([string]$Account.Graphics     -eq $p.Graphics -and
            [string]$Account.FramerateCap -eq $p.Fps      -and
            [string]$Account.Volume       -eq $p.Volume   -and
            [string]$Account.Fullscreen   -eq $p.Screen) {
            return $p.Key
        }
    }
    return ''
}
