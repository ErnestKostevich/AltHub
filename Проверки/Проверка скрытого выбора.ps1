#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart
$script:Settings = Get-RamDefaultSettings
$script:Accounts = @(1..6 | ForEach-Object {
    $a = New-RamAccount -Alias "Selection-fixture-$_"
    $a.Group = if ($_ -le 3) { 'A' } else { 'B' }
    $a.Order = $_
    $a
})
$script:GroupFilter = 'B'
$script:Filter = ''
$script:CheckedIds = @{}
foreach ($a in $script:Accounts) { $script:CheckedIds[[string]$a.Id] = $true }
$script:Cards = @{}
$script:ConfirmCalls = @()
$script:ConfirmAnswer = $false
$script:QueuedIds = @()
$script:InputCalls = 0
$script:StopCalls = 0
$script:SelectionStatusBody = (Get-Command Update-RamStatusLine).ScriptBlock
function Show-RamInputDialog { $script:InputCalls++; throw 'Cancelled bulk action opened its editor' }
function Stop-RamRobloxInstance { param($ProcessId) $script:StopCalls++; return $true }
function Confirm-Ram { param([string]$Message, [string]$Title) $script:ConfirmCalls += $Message; return $script:ConfirmAnswer }
function Show-RamInfo { param([string]$Message) }
function Update-RamStatusLine { }
function Add-RamToLaunchQueue { param([object[]]$Accounts) $script:QueuedIds = @($Accounts | ForEach-Object Id) }
function Assert-Selection { param([bool]$Value,[string]$Message) if (-not $Value) { throw $Message } }

Assert-Selection ((Get-RamHiddenSelectionCount) -eq 3) 'Hidden selection count is incorrect'
Assert-Selection (@(Get-RamTargetAccounts).Count -eq 6 -and $script:ConfirmCalls.Count -eq 0) 'Pure target read prompted or lost selection'
$script:Filter = 'Selection-fixture-6'
Assert-Selection ((Get-RamHiddenSelectionCount) -eq 5) 'Search-hidden selection count is incorrect'
$script:Filter = ''
$cancelled = @(Get-RamActionTargets -What 'fixture')
Assert-Selection ($cancelled.Count -eq 0 -and $script:CheckedIds.Count -eq 6) 'Cancel must leave selection unchanged and return no fallback targets'
Assert-Selection ($script:ConfirmCalls.Count -eq 1 -and $script:ConfirmCalls[0] -match '6' -and $script:ConfirmCalls[0] -match '3') 'Confirmation must state total and hidden counts'
Invoke-RamLaunchSelected
Assert-Selection ($script:QueuedIds.Count -eq 0) 'Cancelled hidden selection launched visible fallback accounts'
Invoke-RamAssignGroup
Invoke-RamAssignGame
Invoke-RamAssignColor
Invoke-RamSaveProfile
$script:Instances = @{}
foreach ($a in $script:Accounts) { $script:Instances[[string]$a.Id] = [pscustomobject]@{ ProcessId = 999999 } }
Invoke-RamStopSelected
Assert-Selection ($script:InputCalls -eq 0 -and $script:StopCalls -eq 0) 'Cancelled action reached an editor or closed a client'
Assert-Selection (@($script:Accounts | Where-Object { $_.Group -notin @('A','B') -or $_.PlaceId -or $_.Color }).Count -eq 0) 'Cancellation mutated account metadata'
Assert-Selection (@($script:Instances.Values | Where-Object { $_.PSObject.Properties.Name -contains 'ClosedByUser' }).Count -eq 0) 'Cancelled close suppressed future instance tracking'
'PASS: hidden cancellation is non-mutating; pure reads do not prompt; launch has no fallback'

$script:ConfirmAnswer = $true
$confirmed = @(Get-RamActionTargets -What 'fixture')
Assert-Selection ($confirmed.Count -eq 6) 'Confirmed action omitted checked accounts from another group'
Invoke-RamLaunchSelected
Assert-Selection ($script:QueuedIds.Count -eq 6) 'Confirmed cross-group launch lost accounts'
'PASS: confirmation retains both selected groups'

Clear-RamCheckedAccounts
foreach ($a in @(Get-RamVisibleAccounts)) { $script:CheckedIds[[string]$a.Id] = $true }
$script:ConfirmCalls = @()
Assert-Selection (@(Get-RamActionTargets).Count -eq 3 -and $script:ConfirmCalls.Count -eq 0) 'Visible-only selection added an unnecessary prompt'
Clear-RamCheckedAccounts
Assert-Selection ($script:CheckedIds.Count -eq 0) 'Clear all retained hidden checks'
$script:ConfirmAnswer = $false
Assert-Selection (@(Get-RamActionTargets).Count -eq 0 -and $script:ConfirmCalls.Count -eq 1) 'Unselected action must retain the existing apply-to-visible confirmation'
$script:ConfirmAnswer = $true
Assert-Selection (@(Get-RamActionTargets).Count -eq 3) 'Apply-to-visible confirmation returned the wrong group'
$confirmCount = $script:ConfirmCalls.Count
Invoke-RamLaunchSelected
Assert-Selection ($script:QueuedIds.Count -eq 3 -and $script:ConfirmCalls.Count -eq $confirmCount) 'Unselected launch must retain visible-account fallback without an added prompt'
$script:QueuedIds = @()
$script:Filter = 'no-fixture-matches-this'
Invoke-RamLaunchSelected
Assert-Selection ($script:QueuedIds.Count -eq 0 -and @(Get-RamActionTargets).Count -eq 0) 'An empty list acquired fallback targets'
$script:Filter = ''
'PASS: visible selection, clear-all and unselected confirmation retain intended behavior'

$script:Settings.UiLanguage = 'en'
foreach ($a in $script:Accounts) { $script:CheckedIds[[string]$a.Id] = $true }
$script:ConfirmCalls = @()
[void](Get-RamActionTargets)
Assert-Selection ($script:ConfirmCalls[0] -notmatch '[А-Яа-яЁё]' -and $script:ConfirmCalls[0] -match '6' -and $script:ConfirmCalls[0] -match '3') 'English hidden-selection confirmation is untranslated'
'PASS: English confirmation preserves both counts'

$script:ReadOnly = $true
$Global:RamForceScale = 1
$Global:RamForceWorkArea = [pscustomobject]@{ Width = 1920; Height = 1040 }
foreach ($language in @('ru','en')) {
    $script:Settings.UiLanguage = $language
    foreach ($style in @('classic','water','wide')) {
        $script:Settings.MenuStyle = $style
        $script:Settings.OnClose = 'exit'
        $script:Settings.ConfirmOnExit = $false
        $script:UI = @{}; $script:Cards = @{}; $script:Instances = @{}
        $script:StatusHoldUntil = [datetime]::MinValue
        $script:CheckedIds = @{}
        foreach ($a in $script:Accounts) { $script:CheckedIds[[string]$a.Id] = $true }
        Set-RamTheme -Name dark | Out-Null
        $form = New-RamMainForm
        try {
            foreach ($value in $script:UI.Values) { if ($value -is [Windows.Forms.Timer]) { $value.Stop() } }
            Build-RamCards
            & $script:SelectionStatusBody
            $suffix = Get-RamText -Text 'скрытых отметок: {0}' -Arguments @(3)
            Assert-Selection ($script:UI.Status.Text.Contains($suffix)) "Missing hidden count: $style/$language"
            $caption = Get-RamText -Text 'Снять все отметки'
            $clearItem = @($script:UI.ActionMenu.Items | Where-Object { $_.Text -eq $caption })
            Assert-Selection ($clearItem.Count -eq 1) "Missing clear-all menu item: $style/$language"
            $clearItem[0].PerformClick()
            Assert-Selection ($script:CheckedIds.Count -eq 0) "Clear menu retained hidden checks: $style/$language"
            Assert-Selection (@($script:Cards.Values | Where-Object { $_.Check.Tag.Checked }).Count -eq 0) "Clear menu retained visible checks: $style/$language"
        } finally {
            foreach ($value in $script:UI.Values) { if ($value -is [Windows.Forms.Timer]) { $value.Stop(); $value.Dispose() } }
            $form.Dispose()
        }
    }
}
'PASS: hidden status and actual clear-menu callbacks work in all three menus, RU/EN'
if (-not $NoPause) { [void](Read-Host 'Enter') }
