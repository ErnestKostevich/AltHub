#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart
$script:TrayExitTestDir=Join-Path ([IO.Path]::GetTempPath()) ('althub-tray-exit-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $script:TrayExitTestDir)
function Get-RamDataDir { $script:TrayExitTestDir }
function Assert-TrayExit {param([bool]$Value,[string]$Message) if(-not $Value){throw $Message}}
function Confirm-RamTrayVisible { $script:TrayConfirmCalls++; return $true }
function Confirm-Ram {param($Text) $script:ExitConfirmCalls++; return $script:AcceptExit }
function Show-RamTrayHint {}
function Save-RamMainWindowGeometry {param($Form)}
function Save-RamState { $script:SaveCalls++ }
function Disable-RamMultiInstance { $script:UnlockCalls++ }
function Unregister-RamHotkeys {}
function Clear-RamSingleInstance {}
function Get-RamProfiles { @() }
function Get-RamGroups { @() }
function Stop-RamRobloxInstance { throw 'Closing AltHub must not stop Roblox' }
function Get-TrayExitHandler {
    param([string]$Path)
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$null,[ref]$null)
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_FormClosing'},$true)
    Assert-TrayExit ($null -ne $node) "FormClosing handler missing in $Path"
    return $node.Arguments[0].ScriptBlock.GetScriptBlock()
}
$handlers=@{
    water=(Get-TrayExitHandler (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/UiMain.ps1'))
    modern=(Get-TrayExitHandler (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/UiModern.ps1'))
}
function New-TrayExitFixture {
    param([string]$Style)
    $script:Settings=Get-RamDefaultSettings
    $script:Settings.UiLanguage='en';$script:Settings.OnClose='tray';$script:Settings.ConfirmOnExit=$true
    $script:Instances=@{};$script:RebuildUi=$false;$script:RestartRequested=$false
    $script:TrayConfirmCalls=0;$script:ExitConfirmCalls=0;$script:SaveCalls=0;$script:UnlockCalls=0;$script:AcceptExit=$true
    $form=New-Object Windows.Forms.Form
    $form.ShowInTaskbar=$false
    [void]$form.Handle
    $script:UI=@{Form=$form;TrayOk=$true;TrayMenu=(New-Object Windows.Forms.ContextMenuStrip)}
    $handler=if($Style -eq 'water'){$handlers.water}else{$handlers.modern}
    $form.Add_FormClosing($handler)
    Update-RamTrayMenu
    return $form
}
try {
    foreach($style in @('water','classic','modern')) {
        $form=New-TrayExitFixture $style
        try {
            $form.Close()
            Assert-TrayExit (-not $form.IsDisposed -and $script:TrayConfirmCalls -eq 1 -and $script:SaveCalls -eq 0) "X did not stay in tray: $style"
            $script:UI.TrayMenu.Items[$script:UI.TrayMenu.Items.Count-1].PerformClick()
            Assert-TrayExit ($form.IsDisposed -and $script:TrayConfirmCalls -eq 1 -and $script:SaveCalls -eq 1 -and $script:UnlockCalls -eq 1) "Tray Exit was redirected to tray: $style"
            "PASS: $style X hides, tray Exit closes and saves exactly once"
        } finally {$script:UI.TrayMenu.Dispose();$form.Dispose()}

        $form=New-TrayExitFixture $style
        try {
            $script:Instances=@{fake=[pscustomobject]@{ProcessId=-1}};$script:AcceptExit=$false
            $script:UI.TrayMenu.Items[$script:UI.TrayMenu.Items.Count-1].PerformClick()
            Assert-TrayExit (-not $form.IsDisposed -and $script:ExitConfirmCalls -eq 1 -and $script:SaveCalls -eq 0) "Cancelled Exit closed the form: $style"
            $form.Close()
            Assert-TrayExit (-not $form.IsDisposed -and $script:TrayConfirmCalls -eq 1 -and $script:ExitConfirmCalls -eq 1) "Cancelled Exit changed later X behavior: $style"
            $script:AcceptExit=$true
            $script:UI.TrayMenu.Items[$script:UI.TrayMenu.Items.Count-1].PerformClick()
            Assert-TrayExit ($form.IsDisposed -and $script:ExitConfirmCalls -eq 2 -and $script:Instances.Count -eq 1) "Confirmed Exit failed or stopped Roblox: $style"
            "PASS: $style Cancel preserves tray behavior, confirmed Exit leaves Roblox alone"
        } finally {$script:UI.TrayMenu.Dispose();$form.Dispose()}

        foreach($mode in @('exit','rebuild','restart')) {
            $form=New-TrayExitFixture $style
            try {
                $script:Instances=@{fake=[pscustomobject]@{ProcessId=-1}}
                switch($mode) {'exit'{$script:Settings.OnClose='exit'} 'rebuild'{$script:RebuildUi=$true} 'restart'{$script:RestartRequested=$true}}
                $form.Close()
                Assert-TrayExit ($form.IsDisposed -and $script:TrayConfirmCalls -eq 0) "Close mode interrupted: $style/$mode"
                $expectedSave=if($mode -eq 'rebuild'){0}else{1}
                $expectedConfirm=if($mode -eq 'exit'){1}else{0}
                Assert-TrayExit ($script:SaveCalls -eq $expectedSave -and $script:ExitConfirmCalls -eq $expectedConfirm) "Lifecycle contract changed: $style/$mode"
                "PASS: $style $mode lifecycle preserved"
            } finally {$script:UI.TrayMenu.Dispose();$form.Dispose()}
        }
    }
} finally {$script:RebuildUi=$false;$script:RestartRequested=$false}
if(-not $NoPause){[void](Read-Host 'Enter')}
