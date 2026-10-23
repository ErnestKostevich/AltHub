#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# Import only the production functions under test; no user data or windows.
foreach ($entry in @(
    @{ File='modules/Storage.ps1'; Names=@('Get-RamDefaultSettings','Load-RamSettings') },
    @{ File='modules/Accounts.ps1'; Names=@('Invoke-RamPendingTile') }
)) {
    $parseErrors=$null; $tokens=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $entry.File),[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Production source has parse errors.' }
    foreach ($name in $entry.Names) {
        $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
        if (-not $definition) { throw "Missing production function: $name" }
        Set-Item -LiteralPath ("Function:script:" + $name) -Value $definition.Body.GetScriptBlock()
    }
}
function Get-RamDefaultUiLanguage { 'en' }
function Get-RamBridgeHotkeyChoices { 'F10' }
function Get-RamSettingsPath { 'memory-settings' }
function Test-Path { param($LiteralPath) if ($LiteralPath -ne 'memory-settings') { throw 'Unexpected filesystem access.' }; $script:HasSettings }
function Get-Content { param($LiteralPath,[switch]$Raw,$Encoding) if ($LiteralPath -ne 'memory-settings') { throw 'Unexpected filesystem access.' }; $script:SettingsJson }
function Get-RamText { param($Text,$Arguments) $Text }
function Write-RamLog { param($Text,$Kind) }
function Invoke-RamTileWindows { param([switch]$Quiet) $script:TileCalls++ }
function Assert-Tile { param([bool]$Value,[string]$Message) if (-not $Value) { throw $Message } }
$script:Failed=0
function Case { param($Name,[scriptblock]$Body) try { & $Body; "PASS: $Name" } catch { $script:Failed++; "FAIL: $Name - $($_.Exception.Message)" } }

Case 'Fresh install does not opt into automatic window placement' {
    $script:HasSettings=$false
    $settings=Load-RamSettings
    Assert-Tile (-not $settings.AutoTile) 'Automatic placement enabled by default.'
    Assert-Tile ($settings.TileMode -eq 'grid') 'Manual grid choice changed.'
}
Case 'Old settings without AutoTile inherit the safe default' {
    $script:HasSettings=$true; $script:SettingsJson='{"MenuLayoutRevision":2,"Theme":"dark"}'
    Assert-Tile (-not (Load-RamSettings).AutoTile) 'Missing property opted into automatic placement.'
}
foreach ($saved in @($false,$true)) {
    $script:SavedValue=$saved
    Case "Explicit saved preference survives: $saved" {
        $script:HasSettings=$true; $script:SettingsJson=(@{MenuLayoutRevision=2;AutoTile=$script:SavedValue} | ConvertTo-Json)
        Assert-Tile ((Load-RamSettings).AutoTile -eq $script:SavedValue) 'Saved preference overwritten.'
    }
}
Case 'Disabling automatic placement cancels an already pending arrangement' {
    $script:Settings=Get-RamDefaultSettings; $script:Settings.AutoTile=$false
    $script:Instances=@{a=[pscustomobject]@{Handle=[IntPtr]::new(111)}}
    $script:PendingTileUntil=(Get-Date).AddSeconds(25); $script:TileCalls=0
    Invoke-RamPendingTile
    Assert-Tile ($script:TileCalls -eq 0) 'Windows moved after disabling automatic placement.'
    Assert-Tile ($script:PendingTileUntil -eq [datetime]::MinValue) 'Pending placement was not cleared.'
}
Case 'Explicit opt-in still waits for all windows and then arranges once' {
    $script:Settings.AutoTile=$true; $script:TileCalls=0
    $script:Instances=@{a=[pscustomobject]@{Handle=[IntPtr]::new(111)};b=[pscustomobject]@{Handle=[IntPtr]::Zero}}
    $script:PendingTileUntil=(Get-Date).AddSeconds(25)
    Invoke-RamPendingTile
    Assert-Tile ($script:TileCalls -eq 0 -and $script:PendingTileUntil -ne [datetime]::MinValue) 'Did not wait for the second window.'
    $script:Instances.b.Handle=[IntPtr]::new(222)
    Invoke-RamPendingTile; Invoke-RamPendingTile
    Assert-Tile ($script:TileCalls -eq 1 -and $script:PendingTileUntil -eq [datetime]::MinValue) 'Opt-in arrangement did not run exactly once.'
}
Case 'Opt-in timeout arranges only when at least one window exists' {
    $script:TileCalls=0; $script:Instances.b.Handle=[IntPtr]::Zero
    $script:PendingTileUntil=(Get-Date).AddSeconds(-1)
    Invoke-RamPendingTile
    Assert-Tile ($script:TileCalls -eq 1) 'Ready window was not arranged after timeout.'
    $script:TileCalls=0; $script:Instances.a.Handle=[IntPtr]::Zero
    $script:PendingTileUntil=(Get-Date).AddSeconds(-1)
    Invoke-RamPendingTile
    Assert-Tile ($script:TileCalls -eq 0 -and $script:PendingTileUntil -eq [datetime]::MinValue) 'Empty window handles caused placement.'
}
if ($script:Failed) { throw "$script:Failed automatic-placement regression checks failed." }
if (-not $NoPause) { [void](Read-Host 'Enter') }
