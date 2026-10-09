#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart

# Граница с Roblox заменена заглушками: тест не запускает клиент, не получает
# билеты входа и не читает/меняет настоящий XML настроек.
function Get-RamRecommendedAccountCount { 1000 }
function Test-RamRobloxUpdating { $script:PreflightCalls++; return $script:Updating }
function Get-RamRobloxPlayerPath { 'C:\test\RobloxPlayerBeta.exe' }
function Restore-RamOwnClientSettings { param([string]$Reason) $script:RestoreCalls++ }
function Apply-RamAccountClientSettings {
    param($Account)
    [void]$script:SettingsWritten.Add([pscustomobject]@{Id=$Account.Id; Graphics=$Account.Graphics; Volume=$Account.Volume})
    return @('graphics','fps','volume','window')
}
function Start-RamRobloxInstance {
    param($Account,$PlayerPath,$Locale,[switch]$Minimized)
    [void]$script:Started.Add([string]$Account.Id)
    if ($script:RateLimit -and $script:Started.Count -eq 1) {
        $rateError = New-Object Exception('simulated rate limit')
        $rateError.Data['RamRetryAfter']=3
        throw $rateError
    }
    if ($script:FailId -eq [string]$Account.Id) { throw 'simulated client failure' }
    return [pscustomobject]@{Id=(9000+$script:Started.Count)}
}
function Get-RamRobloxWindow {
    param($ProcessId,$TimeoutSec)
    if ($script:WindowReady) { return [IntPtr]::new(-1) }
    return [IntPtr]::Zero
}
function Get-RamRobloxProcesses {
    foreach ($inst in $script:Instances.Values) { [pscustomobject]@{Id=$inst.ProcessId;WorkingSet64=50MB} }
}
function Assert-Queue {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}
function Reset-QueueFixture {
    if ($script:UI.LaunchTimer) { $script:UI.LaunchTimer.Dispose() }
    $script:Settings=Get-RamDefaultSettings
    $script:Settings.KeepMutex=$false; $script:Settings.MultiInstanceNoticeShown=$true
    $script:Settings.AutoTile=$false
    $script:UI=@{LaunchTimer=(New-Object Windows.Forms.Timer)}; $script:Cards=@{}
    $script:Instances=@{}; $script:LaunchQueue=New-Object Collections.ArrayList
    $script:LaunchTries=@{}; $script:LaunchFailed=@{}; $script:LastLaunchFailures=@{}
    $script:LaunchSuppressedIds=@{}; $script:LaunchPaused=$false; $script:LaunchTickActive=$false
    $script:NextLaunchTime=[datetime]::MinValue; $script:PendingTileUntil=[datetime]::MinValue
    $script:AwaitWindowFor=''; $script:AwaitSettingsKey=''; $script:AwaitSettingsReadyAt=[datetime]::MinValue
    $script:PlayerPath='C:\test\RobloxPlayerBeta.exe'; $script:UndoStack=New-Object Collections.ArrayList
    $script:Started=New-Object Collections.ArrayList; $script:SettingsWritten=New-Object Collections.ArrayList
    $script:RateLimit=$false; $script:FailId=''; $script:Updating=$false; $script:WindowReady=$false
    $script:PreflightCalls=0; $script:RestoreCalls=0
    $a=New-RamAccount -Alias BASE -Cookie TEST -PlaceId '111'
    $a.Graphics='10'; $a.Volume='100'; $a.FramerateCap='240'; $a.Fullscreen='no'
    $b=New-RamAccount -Alias TWIN -Cookie TEST -PlaceId '222'
    $b.Graphics='1'; $b.Volume='0'; $b.FramerateCap='30'; $b.Fullscreen='no'
    $c=New-RamAccount -Alias OTHER -Cookie TEST -PlaceId '333'
    $c.Graphics='10'; $c.Volume='100'; $c.FramerateCap='240'; $c.Fullscreen='no'
    $script:Accounts=@($a,$b,$c)
}

$failed=$false
try {
    Reset-QueueFixture
    $a=$script:Accounts[0]; $b=$script:Accounts[1]
    $ids=@(Add-RamToLaunchQueue -Accounts @($a,$b) -PassThru)
    Assert-Queue ($ids.Count -eq 2) 'enqueue did not return the accepted accounts'
    Invoke-RamNextLaunch
    $script:NextLaunchTime=[datetime]::MinValue
    Invoke-RamNextLaunch
    Assert-Queue ($script:Started.Count -eq 1) 'next client started before the previous window'
    $script:WindowReady=$true
    Invoke-RamNextLaunch
    Assert-Queue ($script:Started.Count -eq 1) 'window appearance bypassed the settings grace period'
    $script:AwaitSettingsReadyAt=(Get-Date).AddSeconds(-1)
    Invoke-RamNextLaunch
    Assert-Queue (($script:Started -join ',') -eq (@($a.Id,$b.Id) -join ',')) 'FIFO order was lost'
    Assert-Queue ($script:SettingsWritten[0].Graphics -eq '10' -and $script:SettingsWritten[1].Graphics -eq '1') 'settings were mixed'
    $script:NextLaunchTime=[datetime]::MinValue
    Invoke-RamNextLaunch
    Assert-Queue ($script:AwaitWindowFor -eq $b.Id) 'last client lost its settings protection'
    [void](Add-RamToLaunchQueue -Accounts @($script:Accounts[2]) -PassThru)
    $script:NextLaunchTime=[datetime]::MinValue
    Invoke-RamNextLaunch
    Assert-Queue ($script:Started.Count -eq 2) 'late batch overwrote the last client settings'
    Write-Host 'PASS: FIFO, different settings and a late batch preserve the XML guard'

    Reset-QueueFixture
    $a=$script:Accounts[0]; $b=$script:Accounts[1]; $same=$script:Accounts[2]
    [void](Add-RamToLaunchQueue -Accounts @($a,$same,$b) -PassThru)
    Invoke-RamNextLaunch
    $script:FailId=$same.Id; $script:NextLaunchTime=[datetime]::MinValue
    Invoke-RamNextLaunch
    Assert-Queue ($script:AwaitWindowFor -eq $a.Id) 'failure of an identical-settings client cleared the previous guard'
    $script:NextLaunchTime=[datetime]::MinValue
    Invoke-RamNextLaunch
    Assert-Queue ($script:Started.Count -eq 2) 'different settings started after a failed client without waiting'
    Write-Host 'PASS: failed launches do not remove another client XML protection'

    Reset-QueueFixture
    $a=$script:Accounts[0]; $b=$script:Accounts[1]; $script:RateLimit=$true
    [void](Add-RamToLaunchQueue -Accounts @($a,$b) -PassThru)
    Invoke-RamNextLaunch
    Assert-Queue ($script:LaunchQueue[0] -eq $a.Id -and $script:NextLaunchTime -gt (Get-Date)) 'rate limit retry changed the order or skipped its delay'
    Set-RamLaunchPaused -Paused $true
    Invoke-RamNextLaunch
    Assert-Queue ($script:Started.Count -eq 1 -and -not $script:LaunchTickActive) 'paused tick launched or held the tick guard'
    Stop-RamLaunchQueue
    $preflight=$script:PreflightCalls
    Add-RamToLaunchQueue -Accounts @($a,$b) -Unattended
    Assert-Queue ($script:LaunchQueue.Count -eq 0 -and $script:PreflightCalls -eq $preflight) 'automation undid a manual cancellation'
    $script:LaunchTries[$b.Id]=99; $delay=$script:NextLaunchTime
    $ids=@(Add-RamToLaunchQueue -Accounts @($b) -PassThru)
    Assert-Queue ($ids.Count -eq 1 -and -not $script:LaunchSuppressedIds.ContainsKey($b.Id)) 'manual restart remained suppressed'
    Assert-Queue (-not $script:LaunchTries.ContainsKey($b.Id) -and $script:NextLaunchTime -eq $delay) 'manual retry kept stale attempts or erased the cooldown'
    Write-Host 'PASS: pause, rate limit, cancellation and manual retry keep their contracts'

    Reset-QueueFixture
    $a=$script:Accounts[0]; $script:FailId=$a.Id
    [void](Add-RamToLaunchQueue -Accounts @($a) -PassThru)
    for($i=0;$i -lt 3;$i++){ $script:NextLaunchTime=[datetime]::MinValue; Invoke-RamNextLaunch }
    Invoke-RamNextLaunch
    Assert-Queue ($script:Started.Count -eq 3 -and $script:LastLaunchFailures.ContainsKey($a.Id)) 'terminal failure disappeared after reporting'
    Write-Host 'PASS: terminal errors remain available for retry'

    Reset-QueueFixture
    $a=$script:Accounts[0]; $b=$script:Accounts[1]
    $script:Settings.TileMode='main'; $profile=New-RamLaunchProfile -Name TEST -Accounts @($a,$b)
    $a.Graphics='5'; $b.Volume='30'; $script:Settings.TileMode='grid'; $script:Updating=$true
    Invoke-RamRunProfile -Profile $profile
    Assert-Queue ($a.Graphics -eq '5' -and $b.Volume -eq '30' -and $script:Settings.TileMode -eq 'grid' -and $script:UndoStack.Count -eq 0) 'rejected scenario mutated accounts or layout'
    $script:Updating=$false
    Invoke-RamRunProfile -Profile $profile
    Assert-Queue ($a.Graphics -eq '10' -and $b.Volume -eq '0' -and $script:LaunchQueue.Count -eq 2 -and $script:Settings.MainAccountId -eq $a.Id) 'accepted scenario was not committed'
    Invoke-RamUndo
    Assert-Queue ($script:Accounts[0].Graphics -eq '5' -and $script:Accounts[1].Volume -eq '30' -and $script:Settings.TileMode -eq 'grid') 'scenario undo was incomplete'
    Write-Host 'PASS: rejected scenarios are atomic; accepted scenarios and undo retain different settings'

    Reset-QueueFixture
    $script:Settings.AutoTile=$true
    function Show-RamLaunchReport {
        Invoke-RamNextLaunch
        [void]$script:LaunchQueue.Add($script:Accounts[1].Id)
        $script:UI.LaunchTimer.Start()
    }
    Invoke-RamNextLaunch
    Assert-Queue ($script:Started.Count -eq 0 -and $script:LaunchQueue.Count -eq 1 -and -not $script:LaunchTickActive -and $script:PendingTileUntil -eq [datetime]::MinValue) 'nested reporting tick launched twice or tiled a new batch'
    Write-Host 'PASS: re-entrant ticks and a new batch during reporting are safe'
} catch {
    $failed=$true
    Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
} finally {
    if ($script:UI.LaunchTimer) { $script:UI.LaunchTimer.Stop(); $script:UI.LaunchTimer.Dispose() }
}
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
if ($failed) { exit 1 }
