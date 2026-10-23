#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart
$script:RealAddToLaunchQueue=${function:Add-RamToLaunchQueue}
$script:RealStartInstance=${function:Start-RamRobloxInstance}
$script:RealSettingsWait=${function:Set-RamSettingsWait}
$script:RealSettingsFileFree=${function:Test-RamSettingsFileFree}
function Assert-Close {param([bool]$Value,[string]$Message) if(-not $Value){throw $Message}}
function Get-RamText {param([string]$Text,[object[]]$Arguments) if($Arguments){return ($Text -f $Arguments)} $Text}
function Write-RamLog {param($Text,$Level)}
function Set-RamStatus {param($Text)}
function Show-RamMessage {param($Message,$Kind)}
function Update-RamCardStates {}
function Confirm-RamHiddenSelection {param($Accounts,$What) return $script:ConfirmClose}
function Get-RamTargetAccounts { @($script:Accounts | Where-Object {$script:SelectedIds.ContainsKey($_.Id)}) }
function Stop-RamRobloxInstance {param([int]$ProcessId) [void]$script:Stopped.Add($ProcessId); return ($ProcessId -ne 103)}
function New-CloseFixture {
    $script:Accounts=@('one','two','three') | ForEach-Object {$a=New-RamAccount -Alias $_;$a.Id=$_;$a.Group='test';$a.CookieOk='yes';$a}
    $script:Instances=@{};$script:LaunchQueue=New-Object Collections.ArrayList;$script:LaunchTries=@{};$script:LaunchSuppressedIds=@{};$script:LastLaunchFailures=@{};$script:LaunchFailed=@{}
    $script:SelectedIds=@{};$script:Stopping=@{};$script:Stopped=New-Object Collections.ArrayList;$script:ConfirmClose=$true
    $script:Settings=Get-RamDefaultSettings;$script:Settings.WatchGroup='test';$script:Settings.AutoRestart=$true;$script:Settings.AutoTile=$false
    $script:LaunchingAccountId='';$script:LaunchTickActive=$false;$script:LaunchPaused=$false;$script:NextLaunchTime=[datetime]::MinValue
    $script:UI=@{LaunchTimer=[pscustomobject]@{}};$script:UI.LaunchTimer | Add-Member ScriptMethod Stop {}; $script:UI.LaunchTimer | Add-Member ScriptMethod Start {}
}
New-CloseFixture
[void]$script:LaunchQueue.Add('one');[void]$script:LaunchQueue.Add('two');$script:SelectedIds.one=$true
Invoke-RamStopSelected
Assert-Close ($script:LaunchQueue -notcontains 'one' -and $script:LaunchQueue -contains 'two' -and $script:LaunchSuppressedIds.ContainsKey('one')) 'Close did not cancel only selected queued account'
'PASS: selected queued launch cancelled; unrelated queue preserved'
New-CloseFixture
$script:Instances.one=[pscustomobject]@{ProcessId=101;Handle=[IntPtr]::Zero;Started=(Get-Date).AddMinutes(-2)}
$script:Instances.two=[pscustomobject]@{ProcessId=102;Handle=[IntPtr]2;Started=(Get-Date).AddMinutes(-2)}
$script:Instances.three=[pscustomobject]@{ProcessId=103;Handle=[IntPtr]3;Started=(Get-Date).AddMinutes(-2)}
$script:SelectedIds.one=$true;$script:SelectedIds.three=$true
Invoke-RamStopSelected
Assert-Close ($script:Stopped.Count -eq 2 -and $script:Stopped -contains 101 -and $script:Stopped -contains 103 -and $script:Instances.ContainsKey('three') -and $script:Instances.ContainsKey('two') -and $script:Instances.three.ClosedByUser) 'Stop failed/starting process handling changed scope or lost tracking'
'PASS: starting PID closed, failed PID and unrelated instance remain tracked'
New-CloseFixture
[void]$script:LaunchQueue.Add('one');$script:SelectedIds.one=$true;$script:ConfirmClose=$false
Invoke-RamStopSelected
Assert-Close ($script:LaunchQueue -contains 'one' -and $script:LaunchSuppressedIds.Count -eq 0) 'Cancelled hidden-selection confirmation changed state'
'PASS: hidden-selection Cancel has no side effects'
New-CloseFixture
[void]$script:LaunchQueue.Add('one')
Invoke-RamCardStop -Id one
Assert-Close ($script:LaunchQueue.Count -eq 0 -and $script:LaunchSuppressedIds.ContainsKey('one')) 'Card Close ignored queued account'
'PASS: card Close uses same scoped cancellation'
function Add-RamToLaunchQueue {param($Accounts,[switch]$Unattended) foreach($a in $Accounts){if(-not $script:LaunchSuppressedIds.ContainsKey($a.Id)){[void]$script:LaunchQueue.Add($a.Id)}}}
function Get-RamRobloxProcesses { @() }
function Save-RamState {}
function Invoke-RamPendingTile {}
function Update-RamOneAvatar {}
function Update-RamOneGameName {}
function Update-RamAppAccountWatch {}
function Format-RamDuration {param($Seconds) '2m'}
New-CloseFixture
$script:LaunchSuppressedIds.two=$true
$script:Instances.one=[pscustomobject]@{ProcessId=101;Handle=[IntPtr]::Zero;Started=(Get-Date).AddMinutes(-2);ClosedByUser=$true}
$script:Instances.two=[pscustomobject]@{ProcessId=102;Handle=[IntPtr]::Zero;Started=(Get-Date).AddMinutes(-2)}
$script:RestartCount=@{};$script:LastLaunchAt=(Get-Date).AddMinutes(-3);$script:SettingsTouched=$false
Update-RamInstances
Assert-Close ($script:LaunchQueue.Count -eq 0 -and $script:RestartCount.Count -eq 0 -and $script:Accounts[0].CrashCount -eq 0) 'Manual close counted/restarted as crash'
'PASS: manual Close neither crashes nor consumes restart attempt'
New-CloseFixture
$script:LaunchSuppressedIds.one=$true
Invoke-RamWatchCheck
Assert-Close ($script:LaunchQueue -notcontains 'one' -and $script:LaunchQueue -contains 'two') 'WatchGroup resurrected manually closed account'
'PASS: WatchGroup skips suppressed account, still launches other missing accounts'
function Get-RamRecommendedAccountCount { 100 }
function Test-RamRobloxUpdating { $false }
function Get-RamRobloxPlayerPath { 'C:\isolated-fixture\RobloxPlayerBeta.exe' }
Set-Item function:Add-RamToLaunchQueue $script:RealAddToLaunchQueue
New-CloseFixture
$script:Settings.KeepMutex=$false;$script:Settings.MultiInstanceNoticeShown=$true;$script:LaunchSuppressedIds.one=$true
Add-RamToLaunchQueue -Accounts @($script:Accounts[0]) -Unattended
Assert-Close ($script:LaunchQueue.Count -eq 0) 'Unattended launch ignored suppression'
Add-RamToLaunchQueue -Accounts @($script:Accounts[0])
Assert-Close ($script:LaunchQueue -contains 'one' -and -not $script:LaunchSuppressedIds.ContainsKey('one')) 'Manual launch did not reset suppression'
'PASS: automation blocked until explicit manual launch resets suppression'
function Test-RamSettingsFileFree { $true }
function Restore-RamOwnClientSettings {param($Reason) $script:RestoredSettings++}
function Set-RamSettingsWait {param($Launched) & $script:RealSettingsWait -Launched $Launched}
function Start-RamRobloxInstance { throw 'Cancelled launch reached process creation' }
function Apply-RamAccountClientSettings {param($Account) [void](Stop-RamAccountLaunch -Id $Account.Id); @()}
New-CloseFixture
$script:RestoredSettings=0;[void]$script:LaunchQueue.Add('one')
Invoke-RamNextLaunch
Assert-Close ($script:LaunchQueue.Count -eq 0 -and $script:Instances.Count -eq 0 -and $script:RestoredSettings -eq 1 -and -not $script:LaunchTickActive -and -not $script:LaunchingAccountId) 'Close during preparation did not cancel cleanly'
'PASS: reentrant Close during preparation prevents process creation and restores settings'
function Apply-RamAccountClientSettings {param($Account) @()}
function Get-RamAuthTicket {param($Cookie) [void](Stop-RamAccountLaunch -Id one); 'synthetic-ticket'}
function New-RamLaunchUri {param($AuthTicket,$PlaceLauncherUrl,$BrowserTrackerId,$Locale) 'synthetic:fixture'}
New-CloseFixture
$script:Accounts[0].Cookie='synthetic-cookie';$script:Accounts[0].BrowserTrackerId='123'
$script:LaunchingAccountId='one'
$result=& $script:RealStartInstance -Account $script:Accounts[0] -PlayerPath 'C:\isolated-fixture\not-an-executable.exe'
Assert-Close ($null -eq $result -and $script:Stopped.Count -eq 0 -and $script:LaunchSuppressedIds.ContainsKey('one')) 'Close while ticket arrives reached Process.Start'
'PASS: reentrant Close during ticket acquisition prevents Process.Start'
function Start-RamRobloxInstance {param($Account,$PlayerPath,$Locale,[switch]$Minimized) [void](Stop-RamAccountLaunch -Id $Account.Id); [pscustomobject]@{Id=103}}
New-CloseFixture
$script:AwaitWindowFor=''
[void]$script:LaunchQueue.Add('one');Invoke-RamNextLaunch
Assert-Close ($script:Stopped -contains 103 -and $script:Instances.one.ClosedByUser -and $script:LaunchQueue.Count -eq 0 -and $script:LaunchFailed.Count -eq 0 -and $script:AwaitWindowFor -eq 'one') 'Late cancelled process lost after failed stop, was retried, or lost its settings guard'
function Get-RamClientSettingsKey {param($Account) $Account.Id}
[void]$script:LaunchQueue.Add('two')
function Get-RamRobloxWindow {param($ProcessId,$TimeoutSec) [IntPtr]::Zero}
Assert-Close (-not (& $script:RealSettingsFileFree)) 'Next account may overwrite XML while cancelled client survived failed stop and is still starting'
'PASS: late cancelled PID stays tracked after failed stop and guards XML from next launch'
function Start-RamRobloxInstance {param($Account,$PlayerPath,$Locale,[switch]$Minimized) [void](Stop-RamAccountLaunch -Id $Account.Id); $err=New-Object Exception 'fixture throttled';$err.Data['RamRetryAfter']=60;throw $err}
New-CloseFixture
[void]$script:LaunchQueue.Add('one');Invoke-RamNextLaunch
Assert-Close ($script:LaunchQueue.Count -eq 0 -and $script:LaunchFailed.Count -eq 0 -and $script:LastLaunchFailures.Count -eq 0) 'Cancelled failed launch was requeued/reported as failure'
'PASS: cancellation wins over throttled/retry failure'
New-CloseFixture
$script:LaunchingAccountId='one';[void]$script:LaunchQueue.Add('two');Stop-RamLaunchQueue
Assert-Close ($script:LaunchSuppressedIds.ContainsKey('one') -and $script:LaunchSuppressedIds.ContainsKey('two')) 'Stop queue ignored in-progress account'
'PASS: Stop queue suppresses in-flight and waiting accounts'
function Get-RamProfiles { @() }
New-CloseFixture
[void]$script:LaunchQueue.Add('one')
$script:Instances.two=[pscustomobject]@{ProcessId=102;Handle=[IntPtr]::Zero;Started=(Get-Date).AddMinutes(-2)}
$script:Instances.three=[pscustomobject]@{ProcessId=103;Handle=[IntPtr]::Zero;Started=(Get-Date).AddMinutes(-2)}
function Get-RamRobloxProcesses { @([pscustomobject]@{Id=102},[pscustomobject]@{Id=103},[pscustomobject]@{Id=104}) }
$script:UI.TrayMenu=New-Object Windows.Forms.ContextMenuStrip
try {
    Update-RamTrayMenu
    $script:UI.TrayMenu.Items[$script:UI.TrayMenu.Items.Count-2].PerformClick()
    Assert-Close ($script:LaunchQueue.Count -eq 0 -and $script:Instances.ContainsKey('three') -and $script:Stopped.Count -eq 3 -and $script:Stopped -contains 104 -and $script:LaunchSuppressedIds.Count -eq 3) 'Tray Close all lost failed process or ignored queue/global scope'
    'PASS: tray Close all cancels queue, retains failed process and keeps explicit global scope'
} finally {$script:UI.TrayMenu.Dispose()}
function Get-RamRobloxProcesses { @() }
$script:ReadOnly=$true;$Global:RamForceScale=1;$Global:RamForceWorkArea=[pscustomobject]@{Width=1920;Height=1040}
foreach($style in @('classic','water','wide')) {
    New-CloseFixture
    $script:Settings.MenuStyle=$style;$script:Settings.OnClose='exit';$script:Settings.ConfirmOnExit=$false
    $script:UI=@{};$script:Cards=@{};$script:CheckedIds=@{};$script:GroupFilter='';$script:Filter='';$script:StatusHoldUntil=[datetime]::MinValue
    Set-RamTheme -Name dark | Out-Null
    $form=New-RamMainForm
    try {
        foreach($value in $script:UI.Values){if($value -is [Windows.Forms.Timer]){$value.Stop()}}
        [void]$script:LaunchQueue.Add('one');Build-RamCards
        Update-RamCardPrimaryButton -Account $script:Accounts[0] -Entry $script:Cards.one
        Assert-Close $script:Cards.one.Stop.Enabled "Queued card Close disabled: $style"
        $click=[Windows.Forms.Control].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
        [void]$click.Invoke($script:Cards.one.Stop,@([EventArgs]::Empty))
        Assert-Close ($script:LaunchQueue.Count -eq 0 -and $script:LaunchSuppressedIds.ContainsKey('one')) "Actual card handler did not cancel: $style"
        $script:LaunchingAccountId='two'
        $menu=New-Object Windows.Forms.ContextMenuStrip
        try {
            [void](Build-RamCardMenuItems -Menu $menu -AccountId two)
            $close=@($menu.Items | Where-Object {$_.Text -eq (Get-RamText -Text '■  Закрыть окно')})
            Assert-Close ($close.Count -eq 1) "In-flight context Close missing: $style"
            $close[0].PerformClick()
            Assert-Close ($script:LaunchSuppressedIds.ContainsKey('two')) "Context Close did not suppress in-flight launch: $style"
        } finally {$menu.Dispose()}
        "PASS: $style actual card button and in-flight context callback cancel scoped launch"
    } finally {
        foreach($value in $script:UI.Values){if($value -is [Windows.Forms.Timer]){$value.Stop();$value.Dispose()}}
        $form.Dispose()
    }
}
if(-not $NoPause){[void](Read-Host 'Enter')}
