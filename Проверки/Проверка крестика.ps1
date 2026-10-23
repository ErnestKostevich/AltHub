#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart

# Only our forms/receiver are addressed; production activation messages are pumped normally.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RamCloseRaceNative {
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr h,uint message,IntPtr low,IntPtr high);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
    public static bool PostOwnActivation(IntPtr h,long stamp) {
        uint pid; GetWindowThreadProcessId(h,out pid);
        if(pid!=(uint)System.Diagnostics.Process.GetCurrentProcess().Id) { return false; }
        return PostMessage(h,RegisterWindowMessage("AltHub.Activate.v1"),
            new IntPtr(unchecked((int)(uint)stamp)),new IntPtr(unchecked((int)(uint)((ulong)stamp>>32))));
    }
}
'@
$root=Split-Path -Parent $PSScriptRoot
function Assert-CloseRace {param([bool]$Value,[string]$Message) if(-not $Value){throw $Message}}
function Get-CloseHandler {
    param([string]$Path)
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$null,[ref]$null)
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_FormClosing'},$true)
    Assert-CloseRace ($null -ne $node) "Missing FormClosing: $Path"
    return $node.Arguments[0].ScriptBlock.GetScriptBlock()
}
$handlers=@{water=(Get-CloseHandler (Join-Path $root 'modules/UiMain.ps1')); modern=(Get-CloseHandler (Join-Path $root 'modules/UiModern.ps1'))}
function Confirm-RamTrayVisible { return $true }
function Show-RamTrayHint {}
function Save-RamMainWindowGeometry {param($Form) if($script:DuringSave){& $script:DuringSave} }
function Save-RamState { $script:SaveCalls++ }
function Disable-RamMultiInstance {}
function Clear-RamSingleInstance {}
function Confirm-Ram {param($Text) return $script:AcceptExit}
function New-CloseRaceFixture {
    param([string]$Style)
    $script:Settings=Get-RamDefaultSettings
    $script:Settings.OnClose='tray';$script:Settings.TrayConfirmed=$true;$script:Settings.ConfirmOnExit=$true
    $script:Instances=@{};$script:RebuildUi=$false;$script:RestartRequested=$false
    $script:SaveCalls=0;$script:AcceptExit=$true
    $script:RamLastMainHideAt=0L;$script:RamLastMainShowAt=0L
    $script:RamMainHideInProgress=$false;$script:RamPendingMainShowAt=0L;$script:DuringSave=$null
    $form=New-Object Windows.Forms.Form
    $form.Text='AltHub close-race fixture';$form.ShowInTaskbar=$false
    $form.StartPosition='Manual';$form.Location=New-Object Drawing.Point(-20000,-20000)
    $script:UI=@{Form=$form;TrayOk=$true;TrayMenu=(New-Object Windows.Forms.ContextMenuStrip)}
    $handler=if($Style -eq 'water'){$handlers.water}else{$handlers.modern}
    $form.Add_FormClosing($handler)
    $form.Show()
    [void](Register-RamHotkeys -OnPressed {} -SkipSwitchKeys)
    Assert-CloseRace ($null -ne $Global:RamHotkeyWindow) 'Receiver not created'
    $script:ReceiverHandle=$Global:RamHotkeyWindow.Handle
    Update-RamTrayMenu
    return $form
}
function New-CloseRequestTime {
    $stamp=[Diagnostics.Stopwatch]::GetTimestamp()
    while($stamp -le $script:RamLastMainHideAt -or $stamp -le $script:RamLastMainShowAt){$stamp=[Diagnostics.Stopwatch]::GetTimestamp()}
    return $stamp
}
function Send-CloseRequest {
    param([long]$Stamp)
    Assert-CloseRace ([RamCloseRaceNative]::PostOwnActivation($script:ReceiverHandle,$Stamp)) 'Posting owned activation failed'
}
function Pump-CloseRequests {[Windows.Forms.Application]::DoEvents()}
function Assert-CloseHidden {
    Assert-CloseRace (-not $script:UI.Form.IsDisposed -and -not [RamCloseRaceNative]::IsWindowVisible($script:UI.Form.Handle)) 'X did not stay hidden'
}
$failures=0;$passed=0
function Check-CloseRace {
    param([string]$Name,[scriptblock]$Body)
    try { & $Body; $script:passed++; "PASS: $Name" } catch { $script:failures++; "FAIL: $Name : $($_.Exception.Message)" }
}
foreach($style in @('water','classic','modern')) {
    $form=New-CloseRaceFixture $style
    try {
        Check-CloseRace "$style duplicate before X, X stays hidden" {
            Send-CloseRequest (New-CloseRequestTime);Pump-CloseRequests
            $form.Close()
            Assert-CloseHidden
        }
        Check-CloseRace "$style NEW duplicate after X intentionally restores" {
            Send-CloseRequest (New-CloseRequestTime);Pump-CloseRequests
            Assert-CloseRace ([RamCloseRaceNative]::IsWindowVisible($form.Handle)) 'New explicit activation was suppressed'
        }
        Check-CloseRace "$style old queued duplicate dispatched after X stays hidden" {
            Send-CloseRequest (New-CloseRequestTime)
            $form.Close();Pump-CloseRequests
            Assert-CloseHidden
        }
        Check-CloseRace "$style duplicate started before X but posts after X stays hidden" {
            $started=New-CloseRequestTime
            $form.Close()
            Send-CloseRequest $started;Pump-CloseRequests
            Assert-CloseHidden
        }
        Check-CloseRace "$style fresh activation during hide is restored after hide completes" {
            $script:DuringSave={Send-CloseRequest (New-CloseRequestTime);Pump-CloseRequests}
            try {$form.Close()} finally {$script:DuringSave=$null}
            Assert-CloseRace ([RamCloseRaceNative]::IsWindowVisible($form.Handle)) 'Fresh during-hide activation lost'
            Assert-CloseRace (-not $script:RamMainHideInProgress -and $script:RamPendingMainShowAt -eq 0) 'Hide left pending state'
        }
        Check-CloseRace "$style nested X supersedes pending fresh activation" {
            $script:DuringSave={
                Send-CloseRequest (New-CloseRequestTime);Pump-CloseRequests
                Hide-RamMainWindow -Form $script:UI.Form
            }
            try {$form.Close()} finally {$script:DuringSave=$null}
            Assert-CloseHidden
        }
        Check-CloseRace "$style duplicate and reversed older requests do not move accepted boundary" {
            $older=New-CloseRequestTime;$newer=New-CloseRequestTime
            Send-CloseRequest $newer;Send-CloseRequest $older;Send-CloseRequest $newer;Pump-CloseRequests
            Assert-CloseRace ($script:RamLastMainShowAt -eq $newer -and [RamCloseRaceNative]::IsWindowVisible($form.Handle)) 'Old/duplicate activation accepted'
        }
        Check-CloseRace "$style future and invalid activation requests cannot show" {
            $form.Close()
            Assert-CloseRace (-not [Ram.HotkeyWindow]::RequestShow($script:ReceiverHandle,0L)) 'Zero timestamp accepted'
            Assert-CloseRace (-not [Ram.HotkeyWindow]::RequestShow($script:ReceiverHandle,-1L)) 'Negative timestamp accepted'
            Send-CloseRequest 0L;Send-CloseRequest (-1L)
            Send-CloseRequest ([long]::MaxValue);Pump-CloseRequests
            Assert-CloseHidden
        }
        Check-CloseRace "$style hotkeys disabled still has receiver; same-title ordinary form is not eligible" {
            Assert-CloseRace ($Global:RamHotkeyIds.Count -eq 0 -and $script:ReceiverHandle -ne [IntPtr]::Zero) 'No-key receiver unavailable'
            Assert-CloseRace (-not [Ram.HotkeyWindow]::IsActivationWindow($script:ReceiverHandle)) 'NoAutoStart fixture advertised as running user application'
            $form.Text='AltHub'
            Assert-CloseRace (-not [Ram.HotkeyWindow]::IsActivationWindow($form.Handle)) 'Title-only ordinary form eligible'
            Assert-CloseRace (-not [Ram.HotkeyWindow]::RequestShow($form.Handle,(New-CloseRequestTime))) 'Unmarked form accepted'
        }
        Check-CloseRace "$style maximized X hide and fresh show preserve maximized state" {
            Show-RamMainWindow
            $form.WindowState=[Windows.Forms.FormWindowState]::Maximized
            $form.Close()
            Assert-CloseHidden
            Assert-CloseRace ($form.WindowState -eq [Windows.Forms.FormWindowState]::Maximized) 'X changed maximized state'
            Send-CloseRequest (New-CloseRequestTime);Pump-CloseRequests
            Assert-CloseRace ([RamCloseRaceNative]::IsWindowVisible($form.Handle) -and $form.WindowState -eq [Windows.Forms.FormWindowState]::Maximized) 'Fresh show lost maximized state'
        }
        Check-CloseRace "$style tray Exit closes exactly once after hide" {
            $script:UI.TrayMenu.Items[$script:UI.TrayMenu.Items.Count-1].PerformClick()
            Assert-CloseRace ($form.IsDisposed -and $script:SaveCalls -eq 1) 'Explicit tray Exit did not close/save'
        }
    } finally {
        Unregister-RamHotkeys
        Check-CloseRace "$style disposed receiver no longer accepts requests" {
            Assert-CloseRace (-not [Ram.HotkeyWindow]::IsActivationWindow($script:ReceiverHandle)) 'Disposed marker retained'
            Assert-CloseRace (-not [Ram.HotkeyWindow]::RequestShow($script:ReceiverHandle,(New-CloseRequestTime))) 'Disposed receiver accepted request'
        }
        $script:UI.TrayMenu.Dispose();$form.Dispose()
    }
    $form=New-CloseRaceFixture $style
    try {
        Check-CloseRace "$style Cancel explicit Exit preserves subsequent X hide" {
            $script:Instances=@{fake=[pscustomobject]@{ProcessId=-1}};$script:AcceptExit=$false
            $script:UI.TrayMenu.Items[$script:UI.TrayMenu.Items.Count-1].PerformClick()
            Assert-CloseRace (-not $form.IsDisposed -and $script:SaveCalls -eq 0) 'Cancelled Exit disposed/saved'
            $form.Close()
            Assert-CloseRace (-not $form.IsDisposed -and -not [RamCloseRaceNative]::IsWindowVisible($form.Handle)) 'Cancel poisoned later X'
        }
    } finally {Unregister-RamHotkeys;$script:UI.TrayMenu.Dispose();$form.Dispose()}
}
Check-CloseRace 'entry captures duplicate intent before module loading' {
    $entry=Get-Content -LiteralPath (Join-Path $root 'AltHub.ps1') -Raw
    $capture=$entry.IndexOf('$script:RamActivationStartedAt = [Diagnostics.Stopwatch]::GetTimestamp()')
    $load=$entry.IndexOf("'modules\Hotkeys.ps1'")
    Assert-CloseRace ($capture -ge 0 -and $load -gt $capture) 'Entry stamp missing or too late'
}
Check-CloseRace 'activation receiver creation failure propagates instead of silently disabling activation' {
    function New-Object {
        param([string]$TypeName)
        if($TypeName -eq 'Ram.HotkeyWindow'){throw 'synthetic receiver creation failure'}
        Microsoft.PowerShell.Utility\New-Object -TypeName $TypeName
    }
    $failure=$null
    try {[void](Register-RamHotkeys -OnPressed {} -SkipSwitchKeys)} catch {$failure=$_}
    Assert-CloseRace ($null -ne $failure -and $failure.Exception.Message -match 'synthetic receiver creation failure') 'Receiver failure silently became zero hotkeys'
    Assert-CloseRace ($null -eq $Global:RamHotkeyWindow) 'Failed receiver remained registered'
}
"RESULT: $passed passed, $failures failed"
if(-not $NoPause){[void](Read-Host 'Enter')}
if($failures){exit 1}
