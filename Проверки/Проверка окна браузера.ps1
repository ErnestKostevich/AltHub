#requires -Version 5.1
param([ValidateSet('system','cft')][string]$Browser='system',[switch]$CloseWindow,[switch]$NoPause)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'AltHub.ps1') -NoAutoStart
$script:SmokeCft=Get-RamChromeForTestingPath
$script:SmokeData=Join-Path ([IO.Path]::GetTempPath()) ('althub-browser-smoke-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $script:SmokeData)
function Get-RamDataDir {return $script:SmokeData}
function Get-RamChromeForTestingPath {return $script:SmokeCft}
$script:Settings=Get-RamDefaultSettings
$script:Settings.BrowserLoginBrowser=$Browser
$script:Settings.UiLanguage='en'
$script:Messages=[Collections.Generic.List[string]]::new()
function Show-RamMessage {param($Kind,$Message,$Buttons) [void]$script:Messages.Add([string]$Message);return $null}
function Write-RamLog {param($Text,$Kind)}
function Test-RamAuthenticatedUser {throw 'Unexpected authentication attempt in empty test profile'}
$script:ActualInitialize=(Get-Command Initialize-RamLoginCdpSession).ScriptBlock
function Initialize-RamLoginCdpSession {
    param($Port)
    $script:SmokePort=$Port
    $session=& $script:ActualInitialize -Port $Port
    if($null -ne $session){
        if($session.PreviousCookie){throw 'Empty profile unexpectedly contained a login'}
        $script:Connected=$true
    }
    return $session
}
$script:ActualCookie=(Get-Command Get-RamBrowserLoginCookie).ScriptBlock
function Get-RamBrowserLoginCookie {
    param($Port)
    $script:CookiePolls++
    $cookie=& $script:ActualCookie -Port $Port
    if($cookie){throw 'Unexpected login in empty test profile'}
    if($CloseWindow -and -not $script:WindowClosed){
        foreach($own in @(Get-RamProfileBrowserProcesses -ProfileDir $script:SmokeProfile)){
            $ownProcess=Get-Process -Id $own.ProcessId -ErrorAction SilentlyContinue
            if($null -ne $ownProcess -and $ownProcess.MainWindowHandle -ne [IntPtr]::Zero){
                $script:WindowClosed=$ownProcess.CloseMainWindow()
            }
        }
    }
    return $null
}
for($round=1;$round -le 2;$round++){
    $script:Connected=$false;$script:CookiePolls=0;$script:Messages.Clear()
    $script:WindowClosed=$false
    $kind=if($Browser -eq 'cft'){'cft'}elseif((Get-RamInstalledBrowserPath) -match 'msedge\.exe$'){'edge'}else{'chrome'}
    $script:SmokeProfile=Get-RamExternalBrowserProfileDir -Kind $kind
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 12
    if($null -ne $value -or -not $script:Connected -or $script:CookiePolls -lt 1 -or $script:Messages.Count){throw "Browser smoke round $round failed: connected=$script:Connected; polls=$script:CookiePolls; warnings=$($script:Messages.Count)"}
    if($CloseWindow -and (-not $script:WindowClosed -or $watch.Elapsed.TotalSeconds -ge 11)){throw 'Closing the sign-in window did not cancel promptly'}
    $socket=[Net.Sockets.TcpClient]::new()
    try {
        $task=$socket.ConnectAsync('127.0.0.1',$script:SmokePort)
        try{[void]$task.Wait(1000)}catch{}
        if($socket.Connected){throw 'Browser debugging port remained open after sign-in cleanup'}
    }finally{$socket.Dispose()}
    $kind=if($Browser -eq 'cft'){'cft'}elseif((Get-RamInstalledBrowserPath) -match 'msedge\.exe$'){'edge'}else{'chrome'}
    $profile=Get-RamExternalBrowserProfileDir -Kind $kind
    $prefs=Get-Content -LiteralPath (Join-Path $profile 'Default/Preferences') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($prefs.translate.enabled -ne $false -or $prefs.intl.accept_languages -notlike 'en*'){throw 'Translation preference was not retained'}
    "PASS: $Browser round $round - connected, Roblox navigation, empty-cookie polling, port closed, translation preference retained"
}
"Isolated test profile: $script:SmokeData"
if(-not $NoPause){[void](Read-Host 'Enter')}
