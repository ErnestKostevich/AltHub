#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules/Localization.ps1')
. (Join-Path $root 'modules/Storage.ps1')
function Assert-SystemLanguage {param([bool]$Value,[string]$Message) if(-not $Value){throw $Message}}
$script:SystemLanguageTestDir=Join-Path ([IO.Path]::GetTempPath()) ('althub-system-language-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $script:SystemLanguageTestDir)
function Get-RamDataDir {return $script:SystemLanguageTestDir}
function Get-RamBridgeHotkeyChoices {return @('F10')}
$oldCulture=[Threading.Thread]::CurrentThread.CurrentUICulture
try {
    $script:ReadOnly=$false
    foreach($case in @(@('ru-RU','ru'),@('en-US','en'),@('de-DE','en'),@('','en'))){
        [Threading.Thread]::CurrentThread.CurrentUICulture=[Globalization.CultureInfo]::GetCultureInfo($case[0])
        $script:Settings=$null;$script:RamStartupUiLanguage=$null
        Assert-SystemLanguage ((Get-RamUiLanguage) -eq $case[1]) "Early default mismatch for $($case[0])"
        Assert-SystemLanguage ((Get-RamDefaultSettings).UiLanguage -eq $case[1]) "Settings default mismatch for $($case[0])"
        [IO.File]::WriteAllText((Get-RamSettingsPath),'{"Locale":"de-de"}',[Text.Encoding]::UTF8)
        $loaded=Load-RamSettings
        Assert-SystemLanguage ($loaded.UiLanguage -eq $case[1] -and $loaded.Locale -eq 'de-de') 'Legacy settings migration changed Roblox locale or selected wrong UI language'
        foreach($explicit in @('ru','en')){
            $script:Settings=Get-RamDefaultSettings;$script:Settings.UiLanguage=$explicit
            Save-RamSettings $script:Settings
            Assert-SystemLanguage ((Load-RamSettings).UiLanguage -eq $explicit) 'Saved explicit language was replaced by OS default'
            Assert-SystemLanguage ((Get-RamUiLanguage) -eq $explicit) 'Runtime explicit language was replaced by OS default'
        }
        $script:Settings.UiLanguage='unknown';Save-RamSettings $script:Settings
        Assert-SystemLanguage ((Load-RamSettings).UiLanguage -eq $case[1]) 'Invalid JSON language did not use OS default'
        Assert-SystemLanguage ((Get-RamUiLanguage) -eq $case[1]) 'Invalid runtime language did not use OS default'
        "PASS: OS UI culture '$($case[0])', defaults, legacy JSON, explicit RU/EN and invalid settings"
    }
    Assert-SystemLanguage ((Get-RamDefaultUiLanguage -Culture $null) -eq 'en') 'Missing culture should use English'
    'PASS: missing culture uses English without changing Roblox locale'
} finally {
    [Threading.Thread]::CurrentThread.CurrentUICulture=$oldCulture
    Remove-Item -LiteralPath (Get-RamSettingsPath) -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:SystemLanguageTestDir -Force -ErrorAction SilentlyContinue
}
