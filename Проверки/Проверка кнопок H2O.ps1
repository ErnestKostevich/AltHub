#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart
function Assert-WaterButtons {param([bool]$Value,[string]$Message) if(-not $Value){throw $Message}}
function Get-RamCardWidth {return $script:WaterButtonWidth}
function Update-RamHeaderCounts {}
function Update-RamGroupBar {}
function Update-RamStatusLine {}
$script:Settings=Get-RamDefaultSettings
$script:Settings.MenuStyle='water'
$script:Accounts=@((New-RamAccount -Alias 'Fixture account'))
$script:Accounts[0].Username='FixtureUser'
$script:Accounts[0].GameName='Fixture game'
$script:Filter='';$script:GroupFilter='';$script:Instances=@{}
$script:ReadOnly=$true
$oldScale=$Global:RamForceScale
try {
    foreach($language in @('ru','en')){
        $script:Settings.UiLanguage=$language
        foreach($scale in @(1.0,1.25,1.5,2.0)){
            $Global:RamForceScale=$scale;$script:RamDpiScale=$null
            Set-RamTheme -Name dark | Out-Null
            foreach($compact in @($false,$true)){
                $script:Settings.CompactCards=$compact
                foreach($width in @(560,680,681,760)){
                    $script:WaterButtonWidth=[int][Math]::Round($width*$scale)
                    $hostPanel=New-Object Windows.Forms.FlowLayoutPanel
                    $hostPanel.Width=$script:WaterButtonWidth+50;$hostPanel.Height=500
                    $script:UI=@{Cards=$hostPanel};$script:Cards=@{};$script:CheckedIds=@{}
                    try {
                        Build-RamCardsWater
                        $entry=$script:Cards[$script:Accounts[0].Id]
                        Assert-WaterButtons ($null -ne $entry) 'Water fixture card missing'
                        $play=$entry.Play;$edit=$entry.Edit;$stop=$entry.Stop
                        foreach($button in @($play,$edit,$stop)){
                            Assert-WaterButtons ($button.Left -ge 0 -and $button.Top -ge 0 -and $button.Right -le $entry.Card.Width -and $button.Bottom -le $entry.Card.Height) 'Action button outside account card'
                        }
                        Assert-WaterButtons (-not $play.Bounds.IntersectsWith($edit.Bounds) -and -not $play.Bounds.IntersectsWith($stop.Bounds) -and -not $edit.Bounds.IntersectsWith($stop.Bounds)) 'Account actions overlap'
                        if($width -le 680){
                            Assert-WaterButtons ($play.Height -gt $edit.Height -and $edit.Left -eq $stop.Left -and $edit.Bottom -lt $stop.Top -and $play.Right -lt $edit.Left) "Narrow H2O actions are not tall Launch plus stacked Edit/Close: $language/$scale/compact=$compact"
                        } else {
                            Assert-WaterButtons ($play.Top -eq $edit.Top -and $edit.Top -eq $stop.Top -and $play.Height -eq $edit.Height) 'Wide H2O account actions no longer share a row'
                        }
                        Assert-WaterButtons ($entry.Name.Right -lt $play.Left) 'Account name overlaps action area'
                    } finally {
                        foreach($card in @($hostPanel.Controls)){if($card.ContextMenuStrip){$card.ContextMenuStrip.Dispose()};$card.Dispose()}
                        $hostPanel.Dispose()
                    }
                }
            }
            "PASS: H2O narrow/wide action geometry, normal/compact, $language at $([int]($scale*100)) percent"
        }
    }
} finally {
    $Global:RamForceScale=$oldScale;$script:RamDpiScale=$null
}
