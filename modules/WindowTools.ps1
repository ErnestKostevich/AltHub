#requires -Version 5.1
<#
================================================================================
 WindowTools.ps1 — работа с окнами Roblox
================================================================================
 Переименование заголовков и раскладка окон сеткой, чтобы не путаться,
 в каком окне какой аккаунт.

 Используются только обычные функции user32.dll, которыми пользуется любой
 оконный менеджер Windows: перечислить окна, прочитать заголовок, задать
 заголовок, подвинуть окно. Никакого чтения/записи чужой памяти, никаких
 хуков и инъекций — античит Roblox такие вызовы не трогает, потому что это
 то же самое, что делает Alt+Tab или диспетчер задач.
================================================================================
#>

if (-not ('Ram.Native' -as [type])) {
@'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace Ram {
    public static class Native {
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool SetWindowText(IntPtr hWnd, string text);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after,
                                               int x, int y, int cx, int cy, uint flags);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int cmd);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        // Собрать видимые окна с заголовком, принадлежащие процессу.
        public static List<IntPtr> WindowsOfProcess(uint targetPid) {
            List<IntPtr> found = new List<IntPtr>();
            EnumWindows(delegate(IntPtr h, IntPtr l) {
                uint pid;
                GetWindowThreadProcessId(h, out pid);
                if (pid == targetPid && IsWindowVisible(h) && GetWindowTextLength(h) > 0) {
                    found.Add(h);
                }
                return true;
            }, IntPtr.Zero);
            return found;
        }

        public static string TitleOf(IntPtr h) {
            int len = GetWindowTextLength(h);
            if (len <= 0) { return ""; }
            StringBuilder sb = new StringBuilder(len + 2);
            GetWindowText(h, sb, sb.Capacity);
            return sb.ToString();
        }

        public static string ClassOf(IntPtr h) {
            StringBuilder sb = new StringBuilder(256);
            GetClassName(h, sb, sb.Capacity);
            return sb.ToString();
        }
    }
}
'@ | ForEach-Object { Add-Type -TypeDefinition $_ -ErrorAction Stop }
}

# Флаги SetWindowPos
$script:SWP_NOZORDER   = 0x0004
$script:SWP_NOACTIVATE = 0x0010
$script:SWP_SHOWWINDOW = 0x0040

function Get-RamRobloxWindow {
    <#
      Находит главное окно клиента по PID процесса.
      Клиент рисует окно не сразу — ждём до -TimeoutSec секунд.
      Класс окна у Roblox: WINDOWSCLIENT.
    #>
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [int]$TimeoutSec = 45
    )

    # TimeoutSec = 0 → один быстрый проход без ожидания (для опроса из таймера).
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        foreach ($h in [Ram.Native]::WindowsOfProcess([uint32]$ProcessId)) {
            $cls = [Ram.Native]::ClassOf($h)
            if ($cls -eq 'WINDOWSCLIENT' -or [Ram.Native]::TitleOf($h) -match 'Roblox') {
                return $h
            }
        }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Milliseconds 400
    } while ($true)
    return [IntPtr]::Zero
}

function Set-RamWindowTitle {
    <# Пишем имя аккаунта в заголовок окна.
       Клиент иногда возвращает своё название обратно — тогда просто
       вызываем ещё раз позже; на саму игру это никак не влияет. #>
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [Parameter(Mandatory)][string]$Title
    )
    if ($Handle -eq [IntPtr]::Zero) { return $false }
    try { return [Ram.Native]::SetWindowText($Handle, $Title) }
    catch { return $false }
}

function Get-RamWindowRect {
    <# Где сейчас стоит окно. Нужно, чтобы запомнить место под каждый аккаунт. #>
    param([Parameter(Mandatory)][IntPtr]$Handle)
    if ($Handle -eq [IntPtr]::Zero) { return $null }
    try {
        $r = New-Object Ram.Native+RECT
        if (-not [Ram.Native]::GetWindowRect($Handle, [ref]$r)) { return $null }
        return [pscustomobject]@{
            X = $r.Left; Y = $r.Top
            Width = ($r.Right - $r.Left); Height = ($r.Bottom - $r.Top)
        }
    } catch { return $null }
}

function Set-RamWindowBounds {
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [int]$X, [int]$Y, [int]$Width, [int]$Height
    )
    if ($Handle -eq [IntPtr]::Zero) { return $false }
    try {
        # 1 = SW_SHOWNORMAL: выводим из свёрнутого/развёрнутого состояния,
        # иначе окно не подвинется.
        [Ram.Native]::ShowWindow($Handle, 1) | Out-Null
        $flags = $script:SWP_NOZORDER -bor $script:SWP_NOACTIVATE -bor $script:SWP_SHOWWINDOW
        return [Ram.Native]::SetWindowPos($Handle, [IntPtr]::Zero, $X, $Y, $Width, $Height, $flags)
    } catch { return $false }
}

function Set-RamWindowForeground {
    param([Parameter(Mandatory)][IntPtr]$Handle)
    if ($Handle -eq [IntPtr]::Zero) { return $false }
    try {
        [Ram.Native]::ShowWindow($Handle, 1) | Out-Null
        return [Ram.Native]::SetForegroundWindow($Handle)
    } catch { return $false }
}

function Test-RamWindowAlive {
    param([IntPtr]$Handle)
    if ($null -eq $Handle -or $Handle -eq [IntPtr]::Zero) { return $false }
    try { return [Ram.Native]::IsWindow($Handle) } catch { return $false }
}

function Get-RamTileLayout {
    <#
      Считает координаты окон на рабочем столе (без панели задач).

      Mode:
        grid     — сетка, по умолчанию; для 5 окон выйдет 3x2
        cascade  — каскадом со сдвигом, окна крупные и налезают друг на друга
        columns  — колонками во всю высоту
        rows     — строками во всю ширину
        main     — первое окно большое слева, остальные мелкие столбиком
                   справа. Ровно то, что нужно, когда играешь основным,
                   а твины просто стоят на випке

      Columns = 0 → для сетки подбираем сами.
    #>
    param(
        [Parameter(Mandatory)][int]$Count,
        [int]$Columns = 0,
        [int]$Margin  = 4,
        [ValidateSet('grid','cascade','columns','rows','main')][string]$Mode = 'grid'
    )

    if ($Count -le 0) { return @() }

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    # Ниже этих размеров Roblox начинает вести себя странно.
    $minW = 480
    $minH = 360

    $layout = @()

    switch ($Mode) {

        'cascade' {
            # Крупные окна лесенкой: удобно, когда нужно быстро переключаться
            # между аккаунтами, а не видеть все сразу.
            $step = 42
            $w = [math]::Floor($area.Width  * 0.62)
            $h = [math]::Floor($area.Height * 0.72)
            if ($w -lt $minW) { $w = $minW }
            if ($h -lt $minH) { $h = $minH }

            # Лесенка не должна уехать за экран — если окон много, начинаем заново.
            $perRun = [math]::Max(1, [math]::Floor(($area.Width - $w - $Margin) / $step))

            for ($i = 0; $i -lt $Count; $i++) {
                $k = $i % $perRun
                $layout += [pscustomobject]@{
                    X      = [int]($area.X + $Margin + $k * $step)
                    Y      = [int]($area.Y + $Margin + $k * $step)
                    Width  = [int]$w
                    Height = [int]$h
                }
            }
        }

        'main' {
            # Первому — большая часть экрана, остальным — узкая колонка справа.
            $sideW = [math]::Floor($area.Width * 0.30)
            if ($sideW -lt $minW) { $sideW = $minW }

            $mainW = $area.Width - $sideW - $Margin * 3
            if ($mainW -lt $minW) { $mainW = $minW }
            $mainH = $area.Height - $Margin * 2

            $layout += [pscustomobject]@{
                X      = [int]($area.X + $Margin)
                Y      = [int]($area.Y + $Margin)
                Width  = [int]$mainW
                Height = [int]$mainH
            }

            $others = $Count - 1
            if ($others -gt 0) {
                $cellH = [math]::Floor(($area.Height - $Margin * ($others + 1)) / $others)
                if ($cellH -lt $minH) { $cellH = $minH }
                $sx = $area.X + $mainW + $Margin * 2

                for ($i = 0; $i -lt $others; $i++) {
                    $layout += [pscustomobject]@{
                        X      = [int]$sx
                        Y      = [int]($area.Y + $Margin + $i * ($cellH + $Margin))
                        Width  = [int]$sideW
                        Height = [int]$cellH
                    }
                }
            }
        }

        'columns' {
            $cols  = if ($Columns -gt 0) { $Columns } else { $Count }
            $cellW = [math]::Floor(($area.Width - $Margin * ($cols + 1)) / $cols)
            $cellH = $area.Height - $Margin * 2
            if ($cellW -lt $minW) { $cellW = $minW }
            if ($cellH -lt $minH) { $cellH = $minH }

            for ($i = 0; $i -lt $Count; $i++) {
                $c = $i % $cols
                $layout += [pscustomobject]@{
                    X      = [int]($area.X + $Margin + $c * ($cellW + $Margin))
                    Y      = [int]($area.Y + $Margin)
                    Width  = [int]$cellW
                    Height = [int]$cellH
                }
            }
        }

        'rows' {
            $rows  = if ($Columns -gt 0) { $Columns } else { $Count }
            $cellW = $area.Width - $Margin * 2
            $cellH = [math]::Floor(($area.Height - $Margin * ($rows + 1)) / $rows)
            if ($cellW -lt $minW) { $cellW = $minW }
            if ($cellH -lt $minH) { $cellH = $minH }

            for ($i = 0; $i -lt $Count; $i++) {
                $r = $i % $rows
                $layout += [pscustomobject]@{
                    X      = [int]($area.X + $Margin)
                    Y      = [int]($area.Y + $Margin + $r * ($cellH + $Margin))
                    Width  = [int]$cellW
                    Height = [int]$cellH
                }
            }
        }

        default {
            $cols = if ($Columns -gt 0) { $Columns } else { [math]::Ceiling([math]::Sqrt($Count)) }
            if ($cols -lt 1) { $cols = 1 }
            $rows = [math]::Ceiling($Count / $cols)

            $cellW = [math]::Floor(($area.Width  - $Margin * ($cols + 1)) / $cols)
            $cellH = [math]::Floor(($area.Height - $Margin * ($rows + 1)) / $rows)
            if ($cellW -lt $minW) { $cellW = $minW }
            if ($cellH -lt $minH) { $cellH = $minH }

            for ($i = 0; $i -lt $Count; $i++) {
                $c = $i % $cols
                $r = [math]::Floor($i / $cols)
                $layout += [pscustomobject]@{
                    X      = [int]($area.X + $Margin + $c * ($cellW + $Margin))
                    Y      = [int]($area.Y + $Margin + $r * ($cellH + $Margin))
                    Width  = [int]$cellW
                    Height = [int]$cellH
                }
            }
        }
    }

    return $layout
}
