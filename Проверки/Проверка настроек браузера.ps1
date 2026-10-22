#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart
function Assert-LoginUi {param([bool]$Value,[string]$Message) if(-not $Value){throw $Message}}
function Test-RamChromeForTestingReady {return $false}
function Build-RamCards {}
function Write-RamLog {}
function Confirm-Ram {return $true}
function Show-RamInfo {}
$script:UiBrowserScratch=Join-Path ([IO.Path]::GetTempPath()) ('althub-browser-ui-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $script:UiBrowserScratch)
function Get-RamDataDir {return $script:UiBrowserScratch}
$script:Accounts=@();$script:Instances=@{}
try {
    foreach($lang in @('ru','en')){
        $script:Settings=Get-RamDefaultSettings;$script:Settings.UiLanguage=$lang
        $script:Settings.BrowserLoginBrowser='cft'
        foreach($scale in @(1.0,1.25,1.5,2.0)){
            $Global:RamForceScale=$scale;$script:RamDpiScale=$null
            $Global:RamForceWorkArea=[pscustomobject]@{Width=[int](1920*$scale);Height=[int](1040*$scale)}
            Set-RamTheme -Name dark | Out-Null
            $form=Show-RamSettingsDialog -BuildOnly
            try {
                $combo=$form.Controls.Find('ramBrowserLoginCombo',$true)[0]
                Assert-LoginUi ($null -ne $combo -and (Get-RamComboValue $combo) -eq 'cft') 'Missing downloaded-browser selection was silently replaced'
                Assert-LoginUi ($combo.Width -gt 0 -and $combo.Right -le $combo.Parent.ClientSize.Width) 'Browser combo outside settings page'
            } finally {$form.Dispose()}
            $form=Show-RamChromeForTestingConsent -BuildOnly
            try {
                $text=(@($form.Controls | ForEach-Object Text)-join "`n")
                Assert-LoginUi ($text -notmatch '150') 'Consent still has a false fixed download size'
                if($lang -eq 'en'){Assert-LoginUi ($text -match 'Chrome for Testing is optional' -and $text -notmatch 'необязателен') 'Consent body failed English translation'}
            } finally {$form.Dispose()}
            "PASS: browser settings and optional-download consent $lang/$scale"
        }
        $Global:RamForceScale=1.0;$script:RamDpiScale=$null;Set-RamTheme dark | Out-Null
        $script:ReadOnly=$false
        foreach($action in @('Cancel','Save','Reset')){
            $script:Settings.BrowserLoginBrowser='cft';Save-RamSettings $script:Settings
            $saved=[IO.File]::ReadAllText((Get-RamSettingsPath))
            $script:UI=@{Form=(New-RamForm)};$script:BrowserAction=$action;$script:BrowserModalError=$null
            $timer=New-Object Windows.Forms.Timer;$timer.Interval=50
            $timer.Add_Tick({
                $this.Stop()
                try {
                    $form=@([Windows.Forms.Application]::OpenForms | Where-Object {$_.Controls.Find('ramBrowserLoginCombo',$true).Count -gt 0})[0]
                    $combo=$form.Controls.Find('ramBrowserLoginCombo',$true)[0]
                    if($script:BrowserAction -eq 'Reset'){
                        $caption=Get-RamText -Text 'Вернуть рекомендованное'
                        $reset=@($form.Controls | Where-Object {$_.Tag -and $_.Tag.PSObject.Properties.Name -contains 'Caption' -and $_.Tag.Caption -eq $caption})[0]
                        Assert-LoginUi ($null -ne $reset) 'Reset button not found'
                        $reset.PerformClick()
                    } else {Set-RamComboItems -Combo $combo -Items $combo.Tag -Value 'system'}
                    $buttonName=if($script:BrowserAction -eq 'Cancel'){'ramSettingsCancel'}else{'ramSettingsSave'}
                    $form.Controls.Find($buttonName,$true)[0].PerformClick()
                } catch {$script:BrowserModalError=$_.Exception.Message;foreach($open in @([Windows.Forms.Application]::OpenForms)){$open.Close()}}
            })
            try {$timer.Start();Show-RamSettingsDialog} finally {$timer.Stop();$timer.Dispose();$script:UI.Form.Dispose()}
            Assert-LoginUi ($null -eq $script:BrowserModalError) $script:BrowserModalError
            if($action -eq 'Cancel'){
                Assert-LoginUi ($script:Settings.BrowserLoginBrowser -eq 'cft' -and [IO.File]::ReadAllText((Get-RamSettingsPath)) -ceq $saved) 'Cancel changed the browser setting'
            } else {Assert-LoginUi ($script:Settings.BrowserLoginBrowser -eq 'system' -and (Load-RamSettings).BrowserLoginBrowser -eq 'system') 'Save/reset did not persist system browser'}
            "PASS: browser setting actual $action $lang"
        }
    }
} finally {
    $Global:RamForceScale=$null;$Global:RamForceWorkArea=$null
    Remove-Item -LiteralPath (Get-RamSettingsPath) -Force -ErrorAction SilentlyContinue
    [IO.File]::Delete((Join-Path $script:UiBrowserScratch 'althub.ico'))
    [IO.Directory]::Delete($script:UiBrowserScratch)
}
