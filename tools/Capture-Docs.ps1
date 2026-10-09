#requires -Version 5.1
<#
  Пересобирает скриншоты README из настоящих WinForms-окон AltHub.
  Использует только выдуманные аккаунты и режим -NoAutoStart, поэтому не читает
  куки, не пишет настройки и не запускает Roblox.
#>
param([string]$OutputDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs'))

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'AltHub.ps1') -NoAutoStart

if (-not (Test-Path -LiteralPath $OutputDir)) {
    [void](New-Item -ItemType Directory -Path $OutputDir)
}
$stampPath = Join-Path $OutputDir 'screenshots-version.txt'
[IO.File]::WriteAllText($stampPath,'in-progress',[Text.Encoding]::ASCII)

function Save-RamDocsForm {
    param(
        [Parameter(Mandatory)]$Form,
        [Parameter(Mandatory)][string]$Name,
        [switch]$Maximized,
        [int]$ClientWidth=0,
        [int]$ClientHeight=0
    )
    try {
        if ($script:UI.UpdateTimer) { $script:UI.UpdateTimer.Stop() }
        if ($script:UI.ScheduleTimer) { $script:UI.ScheduleTimer.Stop() }
        $Form.ShowInTaskbar = $false
        $Form.StartPosition = 'CenterScreen'
        if($ClientWidth -gt 0){$Form.ClientSize=New-Object Drawing.Size($ClientWidth,$ClientHeight);Update-RamAfterResize -Force}
        $Form.Show()
        if ($Maximized) { $Form.WindowState='Maximized'; [Windows.Forms.Application]::DoEvents(); Update-RamAfterResize -Force }
        [Windows.Forms.Application]::DoEvents()
        $Form.PerformLayout()
        $Form.Refresh()
        [Windows.Forms.Application]::DoEvents()

        $bmp = New-Object Drawing.Bitmap($Form.Width, $Form.Height)
        try {
            $Form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)))
            $path = Join-Path $OutputDir $Name
            $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png)
            Write-Host ("  {0,-28} {1}x{2}" -f $Name, $bmp.Width, $bmp.Height)
        } finally { $bmp.Dispose() }
    } finally {
        if ($script:UI.UpdateTimer)   { try { $script:UI.UpdateTimer.Stop() } catch {} }
        if ($script:UI.ScheduleTimer) { try { $script:UI.ScheduleTimer.Stop() } catch {} }
        $Form.Close()
        $Form.Dispose()
    }
}

function Find-RamDocsButton {
    param($Parent, [string]$Caption)
    foreach ($c in $Parent.Controls) {
        $text = [string]$c.Text
        if ($c.Tag -and $c.Tag.PSObject.Properties.Name -contains 'Caption') {
            $text = [string]$c.Tag.Caption
        }
        if ($c -is [Windows.Forms.Button] -and $text -eq $Caption) { return $c }
        if ($c.Controls.Count) {
            $found = Find-RamDocsButton -Parent $c -Caption $Caption
            if ($found) { return $found }
        }
    }
    return $null
}

# Полностью искусственная витрина: ни одного настоящего имени или входа.
$script:Settings = Get-RamDefaultSettings
$script:Settings.OnClose = 'exit'
$script:Settings.ConfirmOnExit = $false
$script:Settings.Theme = 'dark'
$script:Settings.CompactCards = $false
$script:Settings.MenuWindowGeometry = @{}
$script:Settings.Games = @(
    [pscustomobject]@{ Title='Blox Fruits'; PlaceId='2753915549'; LinkCode='' },
    [pscustomobject]@{ Title='Elemental Dungeons'; PlaceId='10515146389'; LinkCode='' }
)
$script:Settings.Profiles = @(
    [pscustomobject]@{ Name='Основной + твинки'; Group='Твинки'; PlaceId='10515146389'; GameName='Elemental Dungeons'; LinkCode='' }
)
Set-RamTheme -Name 'dark' | Out-Null

$a1 = New-RamAccount -Alias 'Основной' -Cookie 'DEMO'
$a1.Username='DemoPlayer'; $a1.UserId=0; $a1.CookieOk='yes'; $a1.Group='Основные'
$a1.GameName='Elemental Dungeons'; $a1.PlaceId='10515146389'; $a1.Graphics='8'; $a1.FramerateCap='144'; $a1.Volume='75'
$a1.Robux=2450; $a1.Premium='yes'; $a1.LaunchCount=12; $a1.PlaySeconds=18420

$a2 = New-RamAccount -Alias 'Твинк для фарма' -Cookie 'DEMO'
$a2.Username='DemoTwin'; $a2.UserId=0; $a2.CookieOk='yes'; $a2.Group='Твинки'
$a2.GameName='Blox Fruits'; $a2.PlaceId='2753915549'; $a2.Graphics='2'; $a2.FramerateCap='60'; $a2.Volume='0'
$a2.LaunchCount=7; $a2.PlaySeconds=9630

$a3 = New-RamAccount -Alias 'Торговый аккаунт' -Cookie 'DEMO'
$a3.Username='TradeDemo'; $a3.UserId=0; $a3.CookieOk='no'; $a3.Group='Торговля'
$a3.GameName='Просто Roblox'; $a3.Graphics='1'; $a3.FramerateCap='30'; $a3.Volume='20'

$script:Accounts = @($a1, $a2, $a3)
$script:Settings.TileMode = 'main'
$script:Settings.Profiles = @((New-RamLaunchProfile -Name 'Основа + твинки' -Accounts @($a1,$a2)))
$script:Instances[$a1.Id] = [pscustomobject]@{ ProcessId=999999; Handle=[IntPtr]::new(123); Started=(Get-Date) }
[void]$script:LaunchQueue.Add($a2.Id)
$script:NextLaunchTime = (Get-Date).AddSeconds(8)
$script:LaunchPaused = $true
$script:LastLaunchFailures[$a3.Id] = 'Roblox не ответил. Повтори запуск после проверки входа.'

Write-Host 'Главные окна:'
foreach ($shot in @(
    @{ Key='classic'; File='menu-pulse.png'     },
    @{ Key='water';   File='menu-water.png'     },
    @{ Key='wide';    File='menu-dashboard.png' }
)) {
    $script:Settings.MenuStyle = $shot.Key
    $script:Section = 'accounts'
    $script:UI = @{}; $script:Cards = @{}
    $main = New-RamMainForm
    # В обычном запуске эти функции вызывает AltHub.ps1 сразу после сборки
    # формы. Здесь точка входа отключена, поэтому заполняем страницы вручную.
    Build-RamCards
    Update-RamGamesPanel
    Update-RamProfilesPanel
    Update-RamStatsPanel
    Save-RamDocsForm -Form $main -Name $shot.File
    $script:UI = @{}; $script:Cards = @{}
    $scenarios = New-RamMainForm
    Build-RamCards
    Show-RamSection -Key 'profiles'
    Save-RamDocsForm -Form $scenarios -Name ($shot.File.Replace('.png','-scenarios.png'))
}

Write-Host 'Один аккаунт, статистика и полный экран:'
$keepDocsAccounts=$script:Accounts
$script:Accounts=@($a1)
$script:Settings.Theme='light'
Set-RamTheme -Name 'light' | Out-Null
foreach($shot in @(
    @{Key='wide';Section='accounts';File='dashboard-search.png';Full=$false},
    @{Key='wide';Section='stats';File='dashboard-statistics.png';Full=$false},
    @{Key='classic';Section='accounts';File='pulse-fullscreen.png';Full=$true},
    @{Key='water';Section='accounts';File='water-fullscreen.png';Full=$true}
)) {
    $script:Settings.MenuStyle=$shot.Key;$script:Section='accounts'
    $script:UI=@{};$script:Cards=@{}
    $main=New-RamMainForm
    Build-RamCards
    Show-RamSection -Key $shot.Section
    if($shot.Key -eq 'wide') {
        Save-RamDocsForm -Form $main -Name $shot.File -ClientWidth (Get-RamScaled 710) -ClientHeight (Get-RamScaled 560)
    } else { Save-RamDocsForm -Form $main -Name $shot.File -Maximized:$shot.Full }
}
$script:Accounts=$keepDocsAccounts
$script:Settings.Theme='dark'
Set-RamTheme -Name 'dark' | Out-Null

Write-Host 'Диалоги:'
$script:Section = 'accounts'
$script:Settings.MenuStyle = 'classic'
$script:UI = @{}; $script:Cards = @{}
Save-RamDocsForm -Form (Show-RamLaunchCenter -BuildOnly) -Name 'launch-center.png'
Save-RamDocsForm -Form (Show-RamFirstRun -BuildOnly) -Name 'wizard.png'
Save-RamDocsForm -Form (Show-RamAccountDialog -Account $a1 -BuildOnly) -Name 'account.png'
Save-RamDocsForm -Form (Show-RamThemeConstructor -BuildOnly) -Name 'constructor.png'

$settings = Show-RamSettingsDialog -BuildOnly
Save-RamDocsForm -Form $settings -Name 'settings.png'

# Закрытие окна настроек прогоняет тот же обработчик, что и обычная кнопка
# «Сохранить». Для второго кадра гарантируем допустимую задержку даже при
# запуске генератора поверх настроек от очень старой версии.
$script:Settings | Add-Member -NotePropertyName LaunchDelaySec -NotePropertyValue 3 -Force
$appearance = Show-RamSettingsDialog -BuildOnly
$appearance.ShowInTaskbar = $false
$appearance.Show()
[Windows.Forms.Application]::DoEvents()
foreach ($c in $appearance.Controls) {
    if ([string]$c.Name -like 'ramPage_*') {
        $c.Visible = ([string]$c.Name -eq 'ramPage_look')
    } elseif ($c.Tag -and $c.Tag.PSObject.Properties.Name -contains 'PageKey') {
        Set-RamButtonKind -Button $c -Kind $(if ([string]$c.Tag.PageKey -eq 'look') { 'primary' } else { 'ghost' })
    }
}
[Windows.Forms.Application]::DoEvents()
Save-RamDocsForm -Form $appearance -Name 'themes.png'

Write-Host 'Скриншоты документации обновлены.' -ForegroundColor Green
Copy-Item -LiteralPath (Join-Path $OutputDir 'menu-dashboard.png') -Destination (Join-Path $OutputDir 'screenshot-dark.png') -Force
Copy-Item -LiteralPath (Join-Path $OutputDir 'menu-pulse.png') -Destination (Join-Path $OutputDir 'screenshot-light.png') -Force
Copy-Item -LiteralPath (Join-Path $OutputDir 'menu-water.png') -Destination (Join-Path $OutputDir 'screenshot-midnight.png') -Force
[IO.File]::WriteAllText($stampPath,$script:AppVersion,[Text.Encoding]::ASCII)
