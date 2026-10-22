#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
$moduleRoot=Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'
. (Join-Path $moduleRoot 'Storage.ps1')
. (Join-Path $moduleRoot 'Accounts.ps1')
$script:Settings=[pscustomobject]@{RenameWindows=$true;MainAccountId=''}
function Assert-Caption {param([bool]$Value,[string]$Message) if(-not $Value){throw $Message}}
function Get-RamWindowTitle {param($Handle) if($script:CaptionReadFails){throw 'Synthetic read failure'};return $script:CaptionTitles[[int64]$Handle]}
function Get-RamWindowProcessId {param($Handle) return $script:CaptionPids[[int64]$Handle]}
function Test-RamWindowAlive {param($Handle) return $script:CaptionTitles.ContainsKey([int64]$Handle)}
function Set-RamWindowTitle {
    param($Handle,$Title)
    if($script:CaptionWriteFails){return $false}
    $script:CaptionWrites++;$script:CaptionTitles[[int64]$Handle]=$Title;return $true
}
function New-CaptionFixture {
    $a=New-RamAccount -Alias 'Fixture account'
    $script:Accounts=@($a);$script:Settings.MainAccountId=$a.Id;$script:Settings.RenameWindows=$true
    $script:CaptionTitles=@{[int64]301='Roblox game caption'};$script:CaptionPids=@{[int64]301=501}
    $script:CaptionReadFails=$false;$script:CaptionWriteFails=$false;$script:CaptionWrites=0
    $script:Instances=@{};$inst=[pscustomobject]@{Handle=[IntPtr]301;ProcessId=501}
    $script:Instances[$a.Id]=$inst
    return $a
}
$a=New-CaptionFixture;$inst=$script:Instances[$a.Id]
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
Assert-Caption ($script:CaptionTitles[[int64]301] -ceq 'Roblox — Fixture account') 'Owned main account was not renamed'
$script:Settings.RenameWindows=$false
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
Assert-Caption ($script:CaptionTitles[[int64]301] -ceq 'Roblox game caption') 'Turning off did not restore original game caption'
'PASS: checkbox restores the original caption without relaunch, including the main account'
$a=New-CaptionFixture;$script:Settings.RenameWindows=$false
Update-RamInstanceWindowTitle -Id $a.Id -Instance $script:Instances[$a.Id]
Assert-Caption ($script:CaptionWrites -eq 0) 'Already disabled option changed the game caption'
'PASS: already-disabled setting leaves a custom game title untouched'
$a=New-CaptionFixture;$inst=$script:Instances[$a.Id]
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
$script:CaptionTitles[[int64]301]='Externally changed title';$script:Settings.RenameWindows=$false
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
$script:Settings.RenameWindows=$true
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
Assert-Caption ($script:CaptionTitles[[int64]301] -ceq 'Externally changed title') 'External title was overwritten'
'PASS: external title changes are not overwritten by restore or the next poll'
$a=New-CaptionFixture;$inst=$script:Instances[$a.Id]
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
$script:CaptionTitles[[int64]302]='Replacement window';$script:CaptionPids[[int64]302]=501;$inst.Handle=[IntPtr]302;$script:Settings.RenameWindows=$false
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
Assert-Caption ($script:CaptionTitles[[int64]302] -ceq 'Replacement window') 'Old original title restored to replacement handle'
$inst.Handle=[IntPtr]301;$script:CaptionPids[[int64]301]=999
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
Assert-Caption ($script:CaptionTitles[[int64]301] -ceq 'Roblox — Fixture account') 'Reused foreign handle was edited'
'PASS: changed HWND and foreign process ownership block stale restoration'
$a=New-CaptionFixture;$inst=$script:Instances[$a.Id];$script:CaptionWriteFails=$true
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
$script:CaptionWriteFails=$false;$script:Settings.RenameWindows=$false
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
Assert-Caption ($script:CaptionWrites -eq 0) 'Failed native rename created false ownership'
$script:CaptionReadFails=$true;$script:Settings.RenameWindows=$true
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
Assert-Caption ($script:CaptionWrites -eq 0) 'Failed native read led to a title write'
'PASS: native read and write failures do not invent an original or restore ownership'
$a=New-CaptionFixture;$inst=$script:Instances[$a.Id]
$script:CaptionTitles[[int64]301]='Roblox — Fixture account';$script:Settings.RenameWindows=$false
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
Assert-Caption ($script:CaptionTitles[[int64]301] -ceq 'Roblox') 'Legacy owned title was not restored to Roblox'
'PASS: exact legacy AltHub caption restores safely when original is unavailable'
$a=New-CaptionFixture;$inst=$script:Instances[$a.Id]
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
$a.Alias='Updated fixture'
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
$script:Settings.RenameWindows=$false
Update-RamInstanceWindowTitle -Id $a.Id -Instance $inst
Assert-Caption ($script:CaptionTitles[[int64]301] -ceq 'Roblox game caption') 'Alias update replaced original caption snapshot'
'PASS: alias updates keep the first original caption for restoration'
