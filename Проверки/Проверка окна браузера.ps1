#requires -Version 5.1
param([ValidateSet('system','cft')][string]$Browser='system',[switch]$CloseWindow,[switch]$CookiePersistence,[switch]$NoPause)
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
$script:ActualClear=(Get-Command Clear-RamBrowserLoginCookie).ScriptBlock
function Invoke-SmokeCookieFixture {
    param([int]$Port,[switch]$SeedOld,[switch]$SeedNew)
    # Test-only cookie seeding; production CDP remains restricted to its three commands.
    $target=Get-RamLoginCdpTarget -Port $Port -AllowBlank
    if(-not $target){throw 'Test browser target not ready'}
    $method='Network.getCookies';$parameters=@{urls=@('https://www.roblox.com/')}
    if($SeedOld -or $SeedNew){
        $method='Network.setCookies'
        $parameters=@{cookies=@(@{name='.ROBLOSECURITY';value=$(if($SeedOld){'synthetic-old-login'}else{'synthetic-new-login'});domain='.roblox.com';path='/';secure=$true;httpOnly=$true;expires=[DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds()})}
        if($SeedOld){
            foreach($url in @('https://roblox.com/','https://www.roblox.com/')){
                $parameters.cookies+=@{name='.ROBLOSECURITY';value='synthetic-old-login';url=$url;path='/';secure=$true;httpOnly=$true;expires=[DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds()}
            }
            $parameters.cookies+=@{name='AltHubSyntheticDevice';value='synthetic-device';domain='.roblox.com';path='/';secure=$true;expires=[DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds()}
        }
    }
    $socket=[Net.WebSockets.ClientWebSocket]::new();$cancel=[Threading.CancellationTokenSource]::new()
    try{
        $cancel.CancelAfter(5000)
        $socket.Options.Proxy=$null
        $socket.ConnectAsync([uri]$target,$cancel.Token).GetAwaiter().GetResult()
        $bytes=[Text.Encoding]::UTF8.GetBytes((@{id=1;method=$method;params=$parameters}|ConvertTo-Json -Depth 6 -Compress))
        $socket.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,$cancel.Token).GetAwaiter().GetResult()
        $response=[IO.MemoryStream]::new()
        try{
            $buffer=New-Object byte[] 8192
            do{
                $frame=$socket.ReceiveAsync([ArraySegment[byte]]::new($buffer),$cancel.Token).GetAwaiter().GetResult()
                if($frame.MessageType -ne [Net.WebSockets.WebSocketMessageType]::Text -or $response.Length+$frame.Count -gt 1048576){throw 'Test protocol response rejected'}
                $response.Write($buffer,0,$frame.Count)
            }while(-not $frame.EndOfMessage)
            $reply=[Text.Encoding]::UTF8.GetString($response.ToArray())|ConvertFrom-Json
            if($reply.id -ne 1 -or $reply.error){throw 'Test cookie command failed'}
            return $reply.result
        }finally{$response.Dispose()}
    }finally{$socket.Abort();$socket.Dispose();$cancel.Dispose()}
}
function Assert-SmokeCookies {
    param([int]$Port,[bool]$AuthExpected)
    $result=Invoke-SmokeCookieFixture -Port $Port
    $auth=@($result.cookies|Where-Object {$_.name -ceq '.ROBLOSECURITY'})
    $device=@($result.cookies|Where-Object {$_.name -ceq 'AltHubSyntheticDevice' -and $_.value -ceq 'synthetic-device'})
    if(($auth.Count -gt 0) -ne $AuthExpected -or $device.Count -ne 1){throw "Synthetic auth/device cookie invariant failed: auth=$($auth.Count); old=$(@($auth|Where-Object {$_.value -ceq 'synthetic-old-login'}).Count); device=$($device.Count); expected-auth=$AuthExpected"}
}
if($CookiePersistence){
    if($CloseWindow){throw 'CookiePersistence tests successful cleanup, not manual close'}
    function Test-RamAuthenticatedUser {
        param($Cookie)
        if($Cookie -cne 'synthetic-new-login'){throw 'Unexpected test authentication input'}
        return @{State='valid'}
    }
    function Clear-RamBrowserLoginCookie {
        param($Port)
        $cleared=& $script:ActualClear -Port $Port
        Assert-SmokeCookies -Port $Port -AuthExpected $false
        $script:CleanupVerified=$true
        return $cleared
    }
}
$script:ActualInitialize=(Get-Command Initialize-RamLoginCdpSession).ScriptBlock
function Initialize-RamLoginCdpSession {
    param($Port)
    $script:SmokePort=$Port
    if($CookiePersistence -and (Get-RamLoginCdpTarget -Port $Port -AllowBlank)){
        if($script:CookieRound -eq 1){
            [void](Invoke-SmokeCookieFixture -Port $Port -SeedOld)
            Assert-SmokeCookies -Port $Port -AuthExpected $true
        }else{Assert-SmokeCookies -Port $Port -AuthExpected $false}
    }
    $session=& $script:ActualInitialize -Port $Port
    if($null -ne $session){
        if($CookiePersistence){
            if(($script:CookieRound -eq 1 -and $session.PreviousCookie -cne 'synthetic-old-login') -or ($script:CookieRound -gt 1 -and $session.PreviousCookie)){throw 'Previous synthetic login invariant failed'}
            Assert-SmokeCookies -Port $Port -AuthExpected $false
            $script:CleanupVerified=$false
        }elseif($session.PreviousCookie){throw 'Empty profile unexpectedly contained a login'}
        $script:Connected=$true
    }
    return $session
}
$script:ActualCookie=(Get-Command Get-RamBrowserLoginCookie).ScriptBlock
function Get-RamBrowserLoginCookie {
    param($Port)
    $script:CookiePolls++
    if($CookiePersistence){[void](Invoke-SmokeCookieFixture -Port $Port -SeedNew)}
    $cookie=& $script:ActualCookie -Port $Port
    if($cookie -and -not $CookiePersistence){throw 'Unexpected login in empty test profile'}
    if($CloseWindow -and -not $script:WindowClosed){
        foreach($own in @(Get-RamProfileBrowserProcesses -ProfileDir $script:SmokeProfile)){
            $ownProcess=Get-Process -Id $own.ProcessId -ErrorAction SilentlyContinue
            if($null -ne $ownProcess -and $ownProcess.MainWindowHandle -ne [IntPtr]::Zero){
                $script:WindowClosed=$ownProcess.CloseMainWindow()
            }
        }
    }
    if($CookiePersistence){return $cookie}
    return $null
}
for($round=1;$round -le 2;$round++){
    $script:Connected=$false;$script:CookiePolls=0;$script:Messages.Clear()
    $script:WindowClosed=$false
    $script:CookieRound=$round;$script:CleanupVerified=$false
    $kind=if($Browser -eq 'cft'){'cft'}elseif((Get-RamInstalledBrowserPath) -match 'msedge\.exe$'){'edge'}else{'chrome'}
    $script:SmokeProfile=Get-RamExternalBrowserProfileDir -Kind $kind
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 12
    $resultExpected=if($CookiePersistence){$value -ceq 'synthetic-new-login' -and $script:CleanupVerified}else{$null -eq $value}
    if(-not $resultExpected -or -not $script:Connected -or $script:CookiePolls -lt 1 -or $script:Messages.Count){throw "Browser smoke round $round failed: connected=$script:Connected; polls=$script:CookiePolls; warnings=$($script:Messages.Count)"}
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
    if($CookiePersistence){"PASS: $Browser round $round - clean before navigation, final auth absent, device retained, reopen clean, port closed"}
    else{"PASS: $Browser round $round - connected, Roblox navigation, empty-cookie polling, port closed, translation preference retained"}
}
"Isolated test profile: $script:SmokeData"
if(-not $NoPause){[void](Read-Host 'Enter')}
