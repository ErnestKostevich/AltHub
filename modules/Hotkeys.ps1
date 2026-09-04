#requires -Version 5.1
<#
================================================================================
 Hotkeys.ps1 — глобальные горячие клавиши и значок в часах
================================================================================
 ГОРЯЧИЕ КЛАВИШИ.
 Обычные клавиши формы работают, только пока окно AltHub впереди. А нужно,
 чтобы Ctrl+1..9 переключали окна аккаунтов прямо во время игры. Для этого
 используется штатный механизм Windows: RegisterHotKey + невидимое окно,
 которое ловит сообщение WM_HOTKEY (0x0312).

 Это ровно то, чем пользуются любые программы с глобальными сочетаниями.
 Никаких перехватов клавиатуры, никаких хуков на чужие процессы, никакого
 чтения нажатий — Windows сама присылает сообщение, когда нажали именно наше
 сочетание, и только его.

 ЗНАЧОК В ЧАСАХ — обычный NotifyIcon из WinForms.

 Оба механизма полностью снимаются при выходе (Unregister-RamHotkeys).
================================================================================
#>

if (-not ('Ram.HotkeyWindow' -as [type])) {
@'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Ram {

    public class HotkeyEventArgs : EventArgs {
        public int Id;
        public HotkeyEventArgs(int id) { Id = id; }
    }

    // Невидимое окно, которому Windows шлёт WM_HOTKEY.
    public class HotkeyWindow : NativeWindow, IDisposable {

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        private const int WM_HOTKEY = 0x0312;

        public event EventHandler<HotkeyEventArgs> Pressed;

        public HotkeyWindow() {
            CreateHandle(new CreateParams());
        }

        public bool Register(int id, uint modifiers, uint virtualKey) {
            return RegisterHotKey(Handle, id, modifiers, virtualKey);
        }

        public void Unregister(int id) {
            try { UnregisterHotKey(Handle, id); } catch { }
        }

        protected override void WndProc(ref Message m) {
            if (m.Msg == WM_HOTKEY) {
                EventHandler<HotkeyEventArgs> h = Pressed;
                if (h != null) { h(this, new HotkeyEventArgs(m.WParam.ToInt32())); }
            }
            base.WndProc(ref m);
        }

        public void Dispose() {
            DestroyHandle();
        }
    }

    // Освобождение значка. Bitmap.GetHicon() выдаёт handle, который система
    // сама не заберёт: без DestroyIcon он течёт при каждой перерисовке значка,
    // то есть при каждой смене темы.
    public static class IconTools {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool DestroyIcon(IntPtr handle);
    }
}
'@ | ForEach-Object {
        Add-Type -TypeDefinition $_ -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' -ErrorAction Stop
    }
}

$Global:RamHotkeyWindow = $null
$Global:RamHotkeyIds    = @()

function Register-RamHotkeys {
    <#
      Вешает Ctrl+1 .. Ctrl+9 на переключение окон аккаунтов.
      Обработчик получает номер (1..9) и сам решает, что делать.

      Если сочетание уже занято другой программой, Windows просто откажет —
      это не ошибка, просто та цифра работать не будет.
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$OnPressed,
        # Создать окно-приёмник, но НЕ занимать Ctrl+1..9. Нужно, когда
        # переключение окон выключено, а приём входа из браузера — включён:
        # обоим нужно одно и то же скрытое окно, но клавиши разные.
        [switch]$SkipSwitchKeys
    )

    Unregister-RamHotkeys

    try {
        $Global:RamHotkeyWindow = New-Object Ram.HotkeyWindow
    } catch {
        $Global:RamHotkeyWindow = $null
        return 0
    }

    $Global:RamHotkeyWindow.Add_Pressed($OnPressed)

    $MOD_CONTROL = 0x0002
    $ok = 0
    if ($SkipSwitchKeys) { return 0 }
    for ($i = 1; $i -le 9; $i++) {
        $vk = 0x30 + $i          # VK_1 .. VK_9
        if ($Global:RamHotkeyWindow.Register($i, $MOD_CONTROL, $vk)) {
            $Global:RamHotkeyIds += $i
            $ok++
        }
    }
    return $ok
}

function Get-RamBridgeHotkeyChoices {
    <# Клавиши, которые можно назначить на приём входа из браузера. #>
    return @('F8', 'F9', 'F10', 'F11', 'Ctrl+Alt+A')
}

function Get-RamBridgeHotkeySpec {
    <#
      Переводит название клавиши в пару «модификаторы, код клавиши» для
      RegisterHotKey. Возвращает $null, если название незнакомое.
    #>
    param([string]$Name)
    $MOD_CONTROL = 0x0002
    $MOD_ALT     = 0x0001
    switch ($Name) {
        'F8'         { return @{ Mods = 0;                        Vk = 0x77 } }
        'F9'         { return @{ Mods = 0;                        Vk = 0x78 } }
        'F10'        { return @{ Mods = 0;                        Vk = 0x79 } }
        'F11'        { return @{ Mods = 0;                        Vk = 0x7A } }
        'Ctrl+Alt+A' { return @{ Mods = ($MOD_CONTROL -bor $MOD_ALT); Vk = 0x41 } }
    }
    return $null
}

function Register-RamBridgeHotkey {
    <#
      Клавиша приёма входа из браузера. Регистрируется ОТДЕЛЬНО от Ctrl+1..9
      и только пока приём включён: глобальная клавиша отбирается у всей
      системы разом, и держать F10 занятой без надобности нельзя.

      Номер 20 — чтобы не пересечься с 1..9 у переключения окон.
    #>
    param([Parameter(Mandatory)][string]$Key)
    if ($null -eq $Global:RamHotkeyWindow) { return $false }

    $spec = Get-RamBridgeHotkeySpec -Name $Key
    if ($null -eq $spec) { return $false }

    if ($Global:RamHotkeyWindow.Register(20, $spec.Mods, $spec.Vk)) {
        $Global:RamHotkeyIds += 20
        return $true
    }
    return $false
}

function Unregister-RamBridgeHotkey {
    if ($null -eq $Global:RamHotkeyWindow) { return }
    try { $Global:RamHotkeyWindow.Unregister(20) } catch { }
    $Global:RamHotkeyIds = @($Global:RamHotkeyIds | Where-Object { $_ -ne 20 })
}

function Unregister-RamHotkeys {
    if ($null -eq $Global:RamHotkeyWindow) { return }
    foreach ($id in $Global:RamHotkeyIds) { $Global:RamHotkeyWindow.Unregister($id) }
    try { $Global:RamHotkeyWindow.Dispose() } catch { }
    $Global:RamHotkeyWindow = $null
    $Global:RamHotkeyIds    = @()
}

# ------------------------------------------------------------ значок ------

function New-RamTrayIcon {
    <#
      Рисуем значок сами, чтобы не таскать за собой файл .ico — иначе пришлось
      бы класть в папку двоичный файл, а весь смысл проекта в том, что тут
      только читаемый текст.
    #>
    param([System.Drawing.Color]$Accent)

    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

        $rect = New-Object System.Drawing.Rectangle(0, 0, 31, 31)
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $d = 12
        $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
        $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
        $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
        $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
        $path.CloseFigure()

        $b = New-Object System.Drawing.SolidBrush($Accent)
        $g.FillPath($b, $path)
        $b.Dispose(); $path.Dispose()

        $f  = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)
        $tb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $g.DrawString('A', $f, $tb, (New-Object System.Drawing.RectangleF(0, 0, 32, 32)), $sf)
        $f.Dispose(); $tb.Dispose(); $sf.Dispose()
    } finally {
        $g.Dispose()
    }

    # ЗНАЧОК ДЕЛАЕМ ЧЕРЕЗ ПОТОК, А НЕ ЧЕРЕЗ Clone().
    #
    # Icon.FromHandle не владеет handle: полученный значок продолжает на него
    # ссылаться, и Clone() эту зависимость не разрывает. В 1.2 сюда добавили
    # DestroyIcon ради утечки — и значок в часах перестал появляться вообще:
    # NotifyIcon.Visible при этом честно говорит true, но рисовать системе
    # уже нечего.
    #
    # Поэтому сохраняем значок в память как настоящий .ico и собираем из
    # потока — такой значок ни от чего не зависит. Handle после этого можно
    # спокойно освободить, и утечки тоже нет.
    $hicon = $bmp.GetHicon()
    $result = $null
    try {
        $src = [System.Drawing.Icon]::FromHandle($hicon)
        try {
            $ms = New-Object System.IO.MemoryStream
            try {
                $src.Save($ms)
                $ms.Position = 0
                $result = New-Object System.Drawing.Icon($ms)
            } finally { $ms.Dispose() }
        } finally { $src.Dispose() }
    } finally {
        try { [void][Ram.IconTools]::DestroyIcon($hicon) } catch { }
        $bmp.Dispose()
    }
    return $result
}

$Global:RamSingleMutex = $null

function Test-RamAlreadyRunning {
    <#
      Одна копия программы на компьютер.

      Зачем это важнее, чем кажется. Если окно почему-то не видно (свернули
      в часы, а значок уехал под стрелку; система спрятала окно при запуске),
      человек делает единственное разумное — жмёт ярлык ещё раз. Раньше это
      открывало ВТОРУЮ копию: первая оставалась висеть невидимой, держала
      горячие клавиши и замки мультизапуска. Именно так у автора и появилась
      строка «Ctrl+1..9 занял кто-то другой» — это была его же потерянная копия.

      Теперь повторный запуск возвращает окно уже работающей программы.

      Возвращает $true, если программа уже запущена (и мы её разбудили).
    #>
    $created = $false
    try {
        $Global:RamSingleMutex = New-Object System.Threading.Mutex($true, 'Global\AltHubSingleInstance', [ref]$created)
    } catch {
        # Не вышло взять замок — не мешаем запуску, это всего лишь удобство.
        return $false
    }

    if ($created) { return $false }

    # Замок занят: будим уже запущенную копию и уходим.
    try { [void](Show-RamRunningInstance) } catch { }
    return $true
}

function Show-RamRunningInstance {
    <# Поднимает окно уже запущенной копии: ищем его по заголовку и классу. #>
    $me = $PID
    $found = $false
    $cb = [Ram.Native+EnumWindowsProc]{
        param($h, $l)
        $q = 0
        [void][Ram.Native]::GetWindowThreadProcessId($h, [ref]$q)
        if ($q -ne $me) {
            $title = [Ram.Native]::TitleOf($h)
            $cls   = [Ram.Native]::ClassOf($h)
            if ($title -eq 'AltHub' -and $cls -like 'WindowsForms*') {
                [void][Ram.Native]::ShowWindow($h, 9)   # SW_RESTORE
                [void][Ram.Native]::ShowWindow($h, 1)   # SW_SHOWNORMAL
                [void][Ram.Native]::SetForegroundWindow($h)
                $script:found = $true
                return $false
            }
        }
        return $true
    }
    [void][Ram.Native]::EnumWindows($cb, [IntPtr]::Zero)
    return $found
}

function Clear-RamSingleInstance {
    <# Отпускает замок при выходе. #>
    if ($null -ne $Global:RamSingleMutex) {
        try { $Global:RamSingleMutex.ReleaseMutex() } catch { }
        try { $Global:RamSingleMutex.Dispose() } catch { }
        $Global:RamSingleMutex = $null
    }
}

function New-RamDesktopShortcut {
    <#
      Ярлык «AltHub» на рабочем столе.

      Указывает на AltHub.vbs, а не на .ps1 напрямую: так PowerShell стартует
      вообще без окна консоли. Иконку берём из data\althub.ico, который к
      этому моменту уже нарисован (см. Get-RamAppIcon).

      Возвращает @{ Ok; Path; Error } — окну надо показать понятный ответ,
      а не свалиться с исключением.
    #>
    $res = [pscustomobject]@{ Ok = $false; Path = ''; Error = '' }
    try {
        $target = Join-Path $script:Root 'AltHub.vbs'
        if (-not (Test-Path -LiteralPath $target)) {
            $res.Error = "Рядом с программой нет AltHub.vbs — распакуй архив целиком."
            return $res
        }

        $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AltHub.lnk'
        $sh  = New-Object -ComObject WScript.Shell
        $s   = $sh.CreateShortcut($lnk)
        $s.TargetPath       = 'wscript.exe'
        $s.Arguments        = '"' + $target + '"'
        $s.WorkingDirectory = $script:Root
        $s.Description      = 'AltHub — менеджер аккаунтов Roblox'

        $ico = Join-Path (Get-RamDataDir) 'althub.ico'
        if (-not (Test-Path -LiteralPath $ico)) { [void](Get-RamAppIcon) }
        if (Test-Path -LiteralPath $ico) { $s.IconLocation = $ico }

        $s.Save()
        $res.Ok = $true
        $res.Path = $lnk
    } catch {
        $res.Error = $_.Exception.Message
    }
    return $res
}

function Get-RamAppIcon {
    <#
      Значок программы: один на весь запуск.

      Рисуется один раз и раздаётся всем окнам — главному, мастеру первого
      запуска, диалогам. Заодно кладётся в data\althub.ico, откуда его берёт
      ярлык на рабочем столе.

      Возвращает $null, если нарисовать не вышло: окно тогда просто останется
      с системным значком, ронять программу из-за иконки незачем.
    #>
    param([switch]$Fresh)

    if (-not $Fresh -and $null -ne $script:RamAppIcon) { return $script:RamAppIcon }

    try {
        $accent = $Global:RamTheme.Accent
        $script:RamAppIcon = New-RamTrayIcon -Accent $accent
        [void](Save-RamAppIcon -Path (Join-Path (Get-RamDataDir) 'althub.ico') -Accent $accent)
    } catch {
        $script:RamAppIcon = $null
    }
    return $script:RamAppIcon
}

function Set-RamWindowIcon {
    <# Ставит окну значок программы. Без него в панели задач висел безымянный
       значок PowerShell, и программа выглядела как чужой скрипт. #>
    param($Form)
    if ($null -eq $Form) { return }
    try {
        $icon = Get-RamAppIcon
        if ($null -ne $icon) { $Form.Icon = $icon }
    } catch { }
}

function Save-RamAppIcon {
    <#
      Кладёт значок программы в файл .ico рядом с данными.

      Нужен ярлыку на рабочем столе: у ярлыка иконку можно взять только из
      файла. В самом репозитории двоичных файлов по-прежнему нет — .ico
      рождается здесь, на машине пользователя, из того же рисунка, что и
      значок в часах.

      Возвращает путь к файлу или пустую строку, если не вышло.
    #>
    param([Parameter(Mandatory)][string]$Path, $Accent)

    if ($null -eq $Accent) { $Accent = $Global:RamTheme.Accent }
    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $icon = New-RamTrayIcon -Accent $Accent
        try {
            $fs = [System.IO.File]::Create($Path)
            try { $icon.Save($fs) } finally { $fs.Dispose() }
        } finally { $icon.Dispose() }
        return $Path
    } catch {
        return ''
    }
}
