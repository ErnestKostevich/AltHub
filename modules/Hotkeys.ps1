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
    param([Parameter(Mandatory)][scriptblock]$OnPressed)

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
    for ($i = 1; $i -le 9; $i++) {
        $vk = 0x30 + $i          # VK_1 .. VK_9
        if ($Global:RamHotkeyWindow.Register($i, $MOD_CONTROL, $vk)) {
            $Global:RamHotkeyIds += $i
            $ok++
        }
    }
    return $ok
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

    $hicon = $bmp.GetHicon()
    $icon  = [System.Drawing.Icon]::FromHandle($hicon)
    # Копия нужна, чтобы значок пережил освобождение исходной картинки.
    $clone = $icon.Clone()
    $bmp.Dispose()
    return $clone
}
