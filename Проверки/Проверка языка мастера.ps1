#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart
function Assert-WizardLanguage {param([bool]$Value,[string]$Message) if(-not $Value){throw $Message}}
$script:WizardLanguageDir=Join-Path ([IO.Path]::GetTempPath()) ('althub-wizard-language-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $script:WizardLanguageDir)
function Get-RamDataDir {return $script:WizardLanguageDir}
function Get-RamHardwareAdvice {return [pscustomobject]@{Text='Fixture hardware advice'}}
function Get-RamHardwareSummary {return 'Fixture hardware'}
function Write-RamLog {}
$script:Settings=Get-RamDefaultSettings
$script:Settings.UiLanguage='ru'
$script:Settings.Locale='de-de'
$script:Accounts=@([pscustomobject]@{Id='fixture';Alias='User text';Group='Fixture'})
$script:LaunchQueue=@('fixture-queue');$script:Instances=@{Fixture='running'}
$script:ReadOnly=$false
$beforeAccounts=ConvertTo-Json -InputObject $script:Accounts -Compress
$beforeTheme=$script:Settings.Theme;$beforeMenu=$script:Settings.MenuStyle
try {
    foreach($language in @('ru','en')){
        foreach($scale in @(1.0,1.25,1.5,2.0)){
            $script:Settings.UiLanguage=$language
            $Global:RamForceScale=$scale;$script:RamDpiScale=$null
            Set-RamTheme -Name 'dark' | Out-Null
            $form=Show-RamFirstRun -BuildOnly
            try {
                $combo=$form.Controls.Find('ramWizLanguage',$true)
                Assert-WizardLanguage ($combo.Count -eq 1) 'First wizard step has no language selector'
                $combo=$combo[0]
                Assert-WizardLanguage ($combo.Parent.Name -eq 'ramPage_hello') 'Language selector is not on first step'
                Assert-WizardLanguage (($combo.Tag.Value -join ',') -ceq 'ru,en') 'Language options differ from supported languages'
                Assert-WizardLanguage ((Get-RamComboValue $combo) -ceq $language) 'Wrong selected language'
                Assert-WizardLanguage ($combo.Left -ge 0 -and $combo.Right -le $combo.Parent.ClientSize.Width) 'Language selector overflows at DPI'
                foreach($index in 0..4){
                    Set-RamWizardStep -Form $form -Index $index
                    Assert-WizardLanguage ([int]$form.Controls.Find('ramWizStep',$true)[0].Tag -eq $index) 'Wizard navigation changed'
                }
                Assert-WizardLanguage ($form.Text -ceq (Get-RamText -Text 'Настройка AltHub')) 'Wizard title did not translate'
            } finally {$form.Dispose()}
        }
    }
    'PASS: first-step Russian/English selector and five-step navigation at 100/125/150/200 percent'

    $Global:RamForceScale=1.0;$script:RamDpiScale=$null
    Set-RamTheme -Name 'dark' | Out-Null
    foreach($case in @(@{From='ru';To='en';Step=0},@{From='en';To='ru';Step=2},@{From='ru';To='invalid';Step=0})){
        $script:Settings.UiLanguage=$case.From
        Save-RamSettings -Settings $script:Settings
        $savedBefore=[IO.File]::ReadAllText((Get-RamSettingsPath))
        $script:WizardLanguageCase=$case;$script:WizardLanguageError=$null
        $timer=New-Object Windows.Forms.Timer
        $timer.Interval=40
        $timer.Add_Tick({
            $this.Stop()
            try {
                $dialog=@([Windows.Forms.Application]::OpenForms | Where-Object {$_.Controls.Find('ramWizLanguage',$true).Count -gt 0})[0]
                Assert-WizardLanguage ($null -ne $dialog) 'Modal wizard not found'
                $combo=$dialog.Controls.Find('ramWizLanguage',$true)[0]
                $target=if($script:WizardLanguageCase.From -eq 'ru'){1}else{0}
                if($script:WizardLanguageCase.To -eq 'invalid'){$combo.Tag[$target].Value='invalid'}
                $combo.SelectedIndex=$target
                if($script:WizardLanguageCase.To -eq 'invalid'){
                    Assert-WizardLanguage ($null -eq $dialog.Tag) 'Invalid language requested a rebuild'
                    $dialog.Close()
                }
            } catch {$script:WizardLanguageError=$_.Exception.Message;foreach($open in @([Windows.Forms.Application]::OpenForms)){$open.Close()}}
        })
        try {$timer.Start();$result=Show-RamFirstRun -StartStep $case.Step} finally {$timer.Stop();$timer.Dispose()}
        Assert-WizardLanguage ($null -eq $script:WizardLanguageError) $script:WizardLanguageError
        if($case.To -eq 'invalid'){
            Assert-WizardLanguage ($script:Settings.UiLanguage -eq $case.From -and $null -eq $result) 'Invalid language was applied'
            Assert-WizardLanguage ([IO.File]::ReadAllText((Get-RamSettingsPath)) -ceq $savedBefore) 'Invalid language changed saved settings'
        } else {
            Assert-WizardLanguage ($result.Action -eq 'restyle' -and $result.Step -eq $case.Step) 'Language switch lost wizard step'
            Assert-WizardLanguage ($script:Settings.UiLanguage -eq $case.To -and (Load-RamSettings).UiLanguage -eq $case.To) 'Language switch not persisted'
            $rebuilt=Show-RamFirstRun -StartStep $result.Step -BuildOnly
            try {Assert-WizardLanguage ($rebuilt.Text -ceq (Get-RamText -Text 'Настройка AltHub')) 'Rebuilt wizard language wrong'} finally {$rebuilt.Dispose()}
        }
        Assert-WizardLanguage ($script:Settings.Locale -eq 'de-de' -and $script:Settings.Theme -eq $beforeTheme -and $script:Settings.MenuStyle -eq $beforeMenu) 'Language switch changed unrelated settings'
        Assert-WizardLanguage ((ConvertTo-Json -InputObject $script:Accounts -Compress) -ceq $beforeAccounts) 'Language switch changed accounts'
        Assert-WizardLanguage ($script:LaunchQueue[0] -eq 'fixture-queue' -and $script:Instances.Fixture -eq 'running') 'Language switch changed runtime state'
    }
    'PASS: actual modal language callbacks persist both ways, retain current step and reject unsupported values'

    # Drive only these private forms; no global keyboard or mouse input.
    foreach($withMain in @($false,$true)){
    $script:UI=@{};$script:RebuildUi=$false
    if($withMain){$script:UI.Form=New-RamForm}
    $script:Settings.UiLanguage='ru';$script:Settings.FirstRunDone=$false
    $script:WizardLanguagePhase=0;$script:WizardLanguageError=$null
    $timer=New-Object Windows.Forms.Timer
    $timer.Interval=40
    $timer.Add_Tick({
        try {
            $dialog=@([Windows.Forms.Application]::OpenForms | Where-Object {$_.Controls.Find('ramWizLanguage',$true).Count -gt 0})[0]
            Assert-WizardLanguage ($null -ne $dialog) 'Wrapper did not reopen wizard'
            if($script:WizardLanguagePhase -eq 0){
                $script:WizardLanguagePhase=1
                $dialog.Controls.Find('ramWizLanguage',$true)[0].SelectedIndex=1
                return
            }
            $this.Stop()
            Assert-WizardLanguage ($script:Settings.UiLanguage -eq 'en') 'Wrapper reopened in wrong language'
            Assert-WizardLanguage ($dialog.Text -ceq (Get-RamText -Text 'Настройка AltHub')) 'Wrapper reopened untranslated wizard'
            Assert-WizardLanguage ([int]$dialog.Controls.Find('ramWizStep',$true)[0].Tag -eq 0) 'Wrapper did not retain first step'
            $dialog.Controls.Find('ramWizNext',$true)[0].PerformClick()
            Assert-WizardLanguage ([int]$dialog.Controls.Find('ramWizStep',$true)[0].Tag -eq 1) 'Next button failed after switching language'
            $dialog.Controls.Find('ramWizBack',$true)[0].PerformClick()
            Assert-WizardLanguage ([int]$dialog.Controls.Find('ramWizStep',$true)[0].Tag -eq 0) 'Back button failed after switching language'
            $skip=$dialog.Controls.Find('ramWizSkip',$true)[0]
            Assert-WizardLanguage ($null -ne $skip) 'Skip button missing'
            $skip.PerformClick()
        } catch {$script:WizardLanguageError=$_.Exception.Message;$this.Stop();foreach($open in @([Windows.Forms.Application]::OpenForms)){$open.Close()}}
    })
    try {$timer.Start();Invoke-RamFirstRun -Force} finally {$timer.Stop();$timer.Dispose()}
    Assert-WizardLanguage ($null -eq $script:WizardLanguageError) $script:WizardLanguageError
    Assert-WizardLanguage ($script:WizardLanguagePhase -eq 1 -and $script:Settings.FirstRunDone -and (Load-RamSettings).UiLanguage -eq 'en') 'Wrapper did not persist completed/skipped onboarding'
    if($withMain){
        Assert-WizardLanguage ($script:RebuildUi -and $script:UI.Form.IsDisposed) 'Existing main form was not closed for translated rebuild'
        'PASS: rerunning wizard requests translated main UI rebuild only after onboarding closes'
    } else {
        Assert-WizardLanguage (-not $script:RebuildUi) 'First-start wizard requested rebuild without a main form'
        'PASS: real first-run wrapper immediately rebuilds in English; Next, Back and Skip remain functional'
    }
    }
} finally {
    $script:ReadOnly=$true;$Global:RamForceScale=$null;$script:RamDpiScale=$null
    $resolved=(Resolve-Path -LiteralPath $script:WizardLanguageDir).Path
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -match '^althub-wizard-language-[0-9a-f]{32}$'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
if(-not $NoPause){[void](Read-Host 'Enter')}
