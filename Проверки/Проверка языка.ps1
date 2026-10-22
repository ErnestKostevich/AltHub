#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart
function Assert-Language {param([bool]$Value,[string]$Message) if(-not $Value){throw $Message}}
$script:Settings=Get-RamDefaultSettings
$script:Settings.UiLanguage='ru'
Assert-Language ((Get-RamText -Text 'Настройки') -eq 'Настройки') 'Русская подпись изменилась'
$locale=$script:Settings.Locale
$script:Settings.UiLanguage='en'
Assert-Language ((Get-RamText -Text 'Настройки') -eq 'Settings') 'Нет английского перевода настроек'
Assert-Language ((Get-RamText -Text 'отмечено: {0} из {1}' -Arguments @(1,13)) -eq 'selected: 1 of 13') 'Подстановки потерялись'
Assert-Language ($script:Settings.Locale -eq $locale) 'Язык AltHub изменил язык Roblox'
'PASS: separate UI language, explicit Russian fixture and safe English formatting'
$script:Settings.UiLanguage='unknown'
$fallbackCaption=if((Get-RamDefaultUiLanguage) -eq 'ru'){'Настройки'}else{'Settings'}
Assert-Language ((Get-RamText -Text 'Настройки') -eq $fallbackCaption) 'Invalid language did not use the system UI default'
Assert-Language ((Get-RamText -Text 'CUSTOM USER VALUE') -eq 'CUSTOM USER VALUE') 'Неизвестный текст не сохранился'
'PASS: missing or invalid translations fall back without altering user text'

# Все записи ограничены уникальной временной папкой; реальные входы не загружаются.
$script:LanguageTestDir=Join-Path ([IO.Path]::GetTempPath()) ('althub-language-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $script:LanguageTestDir)
function Get-RamDataDir { return $script:LanguageTestDir }
function Get-LanguageControls {
    param($Parent)
    foreach($child in $Parent.Controls){$child; Get-LanguageControls $child}
}
function Stop-LanguageTimers {
    foreach($value in $script:UI.Values){if($value -is [Windows.Forms.Timer]){$value.Stop()}}
}
function Assert-LanguageCaption {
    param($Control,[string]$Where)
    if($script:Settings.UiLanguage -ne 'en'){return}
    if($Control -isnot [Windows.Forms.Label] -and $Control -isnot [Windows.Forms.Button]){return}
    $caption=[string]$Control.Text
    if($Control.Tag -and $Control.Tag.PSObject.Properties.Name -contains 'Caption'){$caption=[string]$Control.Tag.Caption}
    foreach($custom in @('Настройки','Аккаунты','Игры','Сценарии','Отмена','Сохранить','Русский')){$caption=$caption.Replace($custom,'')}
    $caption=$caption.Replace([string]$script:AppAuthor,'')
    $caption=$caption -replace '[А-Яа-яЁё]+\\','' -replace '[А-Яа-яЁё]+\.ps1',''
    Assert-Language ($caption -notmatch '[А-Яа-яЁё]') "Russian UI caption in ${Where}: $caption"
}
function Test-LanguageTrayDisposal {
    param([string]$Language,[string]$Style)
    $first=$null;$second=$null;$firstTray=$null;$secondTray=$null
    $oldClose=$script:Settings.OnClose;$oldInstances=$script:Instances;$oldReadOnly=$script:ReadOnly
    try {
        $script:Settings.UiLanguage=$Language;$script:Settings.MenuStyle=$Style
        $script:Settings.OnClose='tray';$script:Instances=@{};$script:ReadOnly=$true
        $script:UI=@{};$script:Cards=@{}
        $first=New-RamMainForm;Stop-LanguageTimers;$firstTray=$script:UI.Tray
        Assert-Language ($null -eq $firstTray -or -not $firstTray.Visible) "Read-only fixture published a tray icon: $Style/$Language"
        $first.Dispose();$first=$null;$firstTray=$null
        $script:ReadOnly=$false
        $script:UI=@{};$script:Cards=@{}
        $first=New-RamMainForm;Stop-LanguageTimers;$firstTray=$script:UI.Tray
        Assert-Language ($null -ne $firstTray -and $firstTray.Visible) "First real tray icon missing: $Style/$Language"
        $script:UI=@{};$script:Cards=@{}
        $second=New-RamMainForm;Stop-LanguageTimers;$secondTray=$script:UI.Tray
        Assert-Language ($null -ne $secondTray -and $secondTray.Visible) "Second real tray icon missing: $Style/$Language"
        $first.Dispose()
        Assert-Language (-not $firstTray.Visible) "Disposed form leaked its tray icon: $Style/$Language"
        Assert-Language ($secondTray.Visible) "Disposing old form removed new form's tray icon: $Style/$Language"
        $second.Dispose()
        Assert-Language (-not $secondTray.Visible) "Disposed second form leaked its tray icon: $Style/$Language"
    } finally {
        Stop-LanguageTimers
        foreach($tray in @($firstTray,$secondTray)){if($null -ne $tray){$tray.Visible=$false;$tray.Dispose()}}
        foreach($form in @($first,$second)){if($null -ne $form){$form.Dispose()}}
        $script:Settings.OnClose=$oldClose;$script:Instances=$oldInstances;$script:ReadOnly=$oldReadOnly
    }
}
try {
    $script:ReadOnly=$false
    foreach($language in @('ru','en')){
        $script:Settings=Get-RamDefaultSettings
        $script:Settings.UiLanguage=$language
        $script:Settings.Locale='de-de'
        Save-RamSettings -Settings $script:Settings
        $loaded=Load-RamSettings
        Assert-Language ($loaded.UiLanguage -eq $language -and $loaded.Locale -eq 'de-de') 'UI language or Roblox locale lost after JSON reload'
    }
    foreach($invalid in @('unknown','', $null)){
        $script:Settings.UiLanguage=$invalid
        Save-RamSettings -Settings $script:Settings
        Assert-Language ((Load-RamSettings).UiLanguage -eq (Get-RamDefaultUiLanguage)) 'Invalid persisted UI language did not use the system default'
    }
    [IO.File]::WriteAllText((Get-RamSettingsPath),'{"Locale":"en-us"}',[Text.Encoding]::UTF8)
    Assert-Language ((Load-RamSettings).UiLanguage -eq (Get-RamDefaultUiLanguage)) 'Legacy settings without UI language did not use the system default'
    $script:ReadOnly=$true
    'PASS: independent language JSON roundtrip and legacy/invalid defaults in private storage'

    $catalog=Get-RamEnglishCatalog
    Assert-Language ($catalog.Count -gt 1000) 'English catalog is incomplete'
    foreach($source in $catalog.Keys){
        $sourceArgs=@([regex]::Matches($source,'\{(\d+)(?:[^{}]*)\}') | ForEach-Object {$_.Groups[1].Value} | Sort-Object)
        $englishArgs=@([regex]::Matches($catalog[$source],'\{(\d+)(?:[^{}]*)\}') | ForEach-Object {$_.Groups[1].Value} | Sort-Object)
        Assert-Language (($sourceArgs -join ',') -ceq ($englishArgs -join ',')) ("Placeholder mismatch: $source")
        if($sourceArgs.Count){
            $arguments=@();for($i=0;$i -le [int]($sourceArgs | Measure-Object -Maximum).Maximum;$i++){$arguments+=('value-'+$i)}
            $script:Settings.UiLanguage='en'
            [void](Get-RamText -Text $source -Arguments $arguments)
        }
        if($source.Contains("`n")){
            $script:Settings.UiLanguage='en'
            $windowsSource=$source.Replace("`n","`r`n")
            Assert-Language ((Get-RamText -Text $windowsSource) -ceq $catalog[$source]) 'CRLF source did not resolve LF English catalog key'
            $script:Settings.UiLanguage='ru'
            Assert-Language ((Get-RamText -Text $windowsSource) -ceq $windowsSource) 'Russian multiline text line endings changed'
        }
    }
    $parseTokens=$null;$parseErrors=$null
    $wizardAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/UiWizard.ps1'),[ref]$parseTokens,[ref]$parseErrors)
    Assert-Language ($parseErrors.Count -eq 0) 'Wizard source parser errors'
    $wizardTexts=@($wizardAst.FindAll({param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.Contains("`n") -and $node.Value -match '[А-Яа-яЁё]'},$true))
    Assert-Language ($wizardTexts.Count -gt 0) 'No multiline wizard fixture found'
    $script:Settings.UiLanguage='en'
    foreach($text in $wizardTexts){
        Assert-Language ((Get-RamText -Text $text.Value) -cne $text.Value) 'Actual PS1 wizard multiline text fell back to Russian'
    }
    'PASS: English catalog preserves every format placeholder and formats translated templates'

    $script:Settings=Get-RamDefaultSettings
    $script:Settings.UiLanguage='ru'
    $script:Settings.ConfirmOnExit=$false;$script:Settings.OnClose='exit'
    $script:Settings.Locale='en_us'
    $a=New-RamAccount -Alias 'Настройки' -Cookie 'LANGUAGE TEST FIXTURE'
    $a.Username='LanguageFixture';$a.UserId=0;$a.Group='Аккаунты';$a.GameName='Игры';$a.PlaceId='1';$a.Note='Сохранить';$a.Order=10
    $b=New-RamAccount -Alias 'Сценарии' -Cookie 'LANGUAGE TEST FIXTURE'
    $b.Username='LanguageFixture2';$b.UserId=0;$b.Group='Отмена';$b.GameName='Настройки';$b.PlaceId='2';$b.Order=20
    $script:Accounts=@($a,$b)
    $script:Settings.Games=@([pscustomobject]@{Title='Игры';PlaceId='1';LinkCode=''},[pscustomobject]@{Title='Настройки';PlaceId='2';LinkCode=''})
    $script:Settings.Profiles=@((New-RamLaunchProfile -Name 'Сценарии' -Accounts @($a,$b)))
    [void]$script:LaunchQueue.Add($b.Id)
    $script:Instances[$a.Id]=[pscustomobject]@{ProcessId=999999;Handle=[IntPtr]::Zero;Started=Get-Date}
    $queueBefore=@($script:LaunchQueue)-join ','
    $instancesBefore=@($script:Instances.Keys | Sort-Object)-join ','
    $accountsBefore=ConvertTo-Json -InputObject $script:Accounts -Depth 5 -Compress
    foreach($language in @('ru','en')){
        $script:Settings.UiLanguage=$language
        foreach($scale in @(1.0,1.25,1.5,2.0)){
            $Global:RamForceScale=$scale;$script:RamDpiScale=$null
            $Global:RamForceWorkArea=[pscustomobject]@{Width=[int](1600*$scale);Height=[int](1000*$scale)}
            Set-RamTheme -Name 'dark' | Out-Null
            Write-Host ("Checking language={0}, DPI={1}%" -f $language,[int](100*$scale))
            foreach($style in @('classic','water','wide')){
                $script:Settings.MenuStyle=$style;$script:UI=@{};$script:Cards=@{}
                $form=New-RamMainForm
                try {
                    Stop-LanguageTimers
                    $captions=@(Get-LanguageControls $form | ForEach-Object {$_.Text.Trim();if($_.Tag -and $_.Tag.PSObject.Properties.Name -contains 'Caption'){([string]$_.Tag.Caption).Trim()}})
                    Assert-Language ($captions -contains (Get-RamText -Text 'Аккаунты')) "Accounts navigation is not localized: $style/$language"
                    Assert-Language ($captions -contains (Get-RamText -Text 'Настройки')) "Settings navigation is not localized: $style/$language"
                    foreach($section in @('accounts','games','profiles','stats','log')){
                        Show-RamSection -Key $section
                        if($section -eq 'accounts'){
                            Build-RamCards
                            Assert-Language ($script:Cards[$a.Id].Name.Text -ceq 'Настройки') "Custom account alias translated in $style/$language"
                            Assert-Language ($script:Cards[$a.Id].Game.Text -match 'Игры') "Custom game name translated in $style/$language"
                        }
                        foreach($control in @(Get-LanguageControls $form)){
                            Assert-LanguageCaption -Control $control -Where "$style/$language/$scale/$section"
                            if($control -is [Windows.Forms.Button] -and $control.Tag -and $control.Tag.PSObject.Properties.Name -contains 'Natural' -and -not $control.Tag.Fixed){
                                Assert-Language ($control.Tag.Natural.Width -le $control.Width+1) "Button clipped: $style/$language/$scale/$section/$($control.Text)"
                            }
                        }
                    }
                } finally {Stop-LanguageTimers;$form.Dispose()}
            }
            foreach($window in @(Get-RamCheckableWindows | Where-Object {-not $_.Main})){
                $form=& $window.Build
                Assert-Language ($null -ne $form) "BuildOnly dialog missing: $($window.Name)/$language/$scale"
                try {
                    if($window.Name -eq (Get-RamText -Text 'настройки')){
                        $combo=@(Get-LanguageControls $form | Where-Object {$_.Name -eq 'ramUiLanguageCombo'})[0]
                        Assert-Language ((Get-RamComboValue $combo) -eq $language) 'Settings selector displays wrong language'
                        Assert-Language (($combo.Tag.Value -join ',') -eq 'ru,en') 'Settings selector must offer Russian and English'
                    }
                    foreach($control in @(Get-LanguageControls $form)){
                        Assert-LanguageCaption -Control $control -Where "$($window.Name)/$language/$scale"
                        if($control -is [Windows.Forms.Button] -and $control.Tag -and $control.Tag.PSObject.Properties.Name -contains 'Natural' -and -not $control.Tag.Fixed){
                            Assert-Language ($control.Tag.Natural.Width -le $control.Width+1) "Dialog button clipped: $($window.Name)/$language/$scale/$($control.Text)"
                        }
                    }
                } finally {$form.Dispose()}
            }
        }
    }
    Assert-Language ((ConvertTo-Json -InputObject $script:Accounts -Depth 5 -Compress) -ceq $accountsBefore) 'Rendering languages modified aliases/groups/games/account order'
    Assert-Language ((@($script:LaunchQueue)-join ',') -ceq $queueBefore) 'Rendering languages modified launch queue'
    Assert-Language ((@($script:Instances.Keys | Sort-Object)-join ',') -ceq $instancesBefore) 'Rendering languages modified running instances'
    Assert-Language ($script:Settings.Locale -ceq 'en_us') 'Rendering languages modified Roblox locale'
    foreach($language in @('ru','en')){
        foreach($style in @('classic','water','wide')){Test-LanguageTrayDisposal -Language $language -Style $style}
    }
    'PASS: Russian/English three menus and all BuildOnly dialogs at 100/125/150/200 percent preserve user data and runtime state'

    # Настоящий ShowDialog/Save/Cancel, но без системного ввода и внешних границ.
    function Build-RamCards {}
    function Write-RamLog {}
    $Global:RamForceScale=1.0;$script:RamDpiScale=$null
    Set-RamTheme -Name 'dark' | Out-Null
    $Global:RamNoDialogs=$false
    $script:ReadOnly=$false
    foreach($case in @(@{Action='Cancel';From='ru';To='en'},@{Action='Save';From='ru';To='en'},@{Action='Cancel';From='en';To='ru'},@{Action='Save';From='en';To='ru'})){
        $action=$case.Action
        $script:Settings.UiLanguage=$case.From;$script:RebuildUi=$false
        Save-RamSettings -Settings $script:Settings
        $savedBefore=[IO.File]::ReadAllText((Get-RamSettingsPath))
        $script:UI=@{Form=(New-RamForm)}
        $script:LanguageModalError=$null
        $timer=New-Object Windows.Forms.Timer
        $timer.Interval=50
        $script:LanguageModalAction=$action
        $script:LanguageModalTarget=$case.To
        $timer.Add_Tick({
            $this.Stop()
            try {
                $dialog=@([Windows.Forms.Application]::OpenForms | Where-Object {$_.Controls.Find('ramUiLanguageCombo',$true).Count -gt 0})[0]
                Assert-Language ($null -ne $dialog) 'Settings dialog not found'
                $combo=$dialog.Controls.Find('ramUiLanguageCombo',$true)[0]
                for($i=0;$i -lt $combo.Tag.Count;$i++){if($combo.Tag[$i].Value -eq $script:LanguageModalTarget){$combo.SelectedIndex=$i;break}}
                $button=$dialog.Controls.Find(('ramSettings'+$script:LanguageModalAction),$true)[0]
                $button.PerformClick()
            } catch {$script:LanguageModalError=$_.Exception.Message;foreach($dialog in @([Windows.Forms.Application]::OpenForms)){$dialog.Close()}}
        })
        try {$timer.Start();Show-RamSettingsDialog} finally {$timer.Stop();$timer.Dispose();$script:UI.Form.Dispose()}
        Assert-Language ($null -eq $script:LanguageModalError) $script:LanguageModalError
        if($action -eq 'Cancel'){
            Assert-Language ($script:Settings.UiLanguage -eq $case.From -and -not $script:RebuildUi) 'Cancel changed language or rebuilt UI'
            Assert-Language ([IO.File]::ReadAllText((Get-RamSettingsPath)) -ceq $savedBefore) 'Cancel persisted language changes'
        } else {
            Assert-Language ($script:Settings.UiLanguage -eq $case.To -and $script:RebuildUi) 'Save did not apply language and request UI rebuild'
            Assert-Language ((Load-RamSettings).UiLanguage -eq $case.To) 'Save did not persist selected language'
        }
        Assert-Language ($script:Settings.Locale -eq 'en_us') 'Settings language selection changed Roblox locale'
        Assert-Language ((@($script:LaunchQueue)-join ',') -ceq $queueBefore) 'Settings language selection modified launch queue'
        Assert-Language ((@($script:Instances.Keys | Sort-Object)-join ',') -ceq $instancesBefore) 'Settings language selection modified running instances'
        Assert-Language ((ConvertTo-Json -InputObject $script:Accounts -Depth 5 -Compress) -ceq $accountsBefore) 'Settings language selection modified account data or order'
    }
    'PASS: real settings Save persists Russian/English both ways; Cancel preserves language and disk state'
} finally {
    $script:ReadOnly=$true;$Global:RamNoDialogs=$true
    $Global:RamForceScale=$null;$Global:RamForceWorkArea=$null
    $resolved=(Resolve-Path -LiteralPath $script:LanguageTestDir).Path
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -match '^althub-language-[0-9a-f]{32}$') {Remove-Item -LiteralPath $resolved -Recurse -Force}
}
if(-not $NoPause){[void](Read-Host 'Enter')}
