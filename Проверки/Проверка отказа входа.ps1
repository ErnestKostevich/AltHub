#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $root 'modules/ExternalBrowserLogin.ps1')
$script:RealProfileCleanup=[scriptblock]::Create((Get-Command Clear-RamExternalBrowserProfileState).Definition)
$script:RealProfileProcessQuery=[scriptblock]::Create((Get-Command Get-RamProfileBrowserProcesses).Definition)
$script:RealProfileStop=[scriptblock]::Create((Get-Command Stop-RamProfileBrowsers).Definition)
function Get-RamText {param([string]$Text,[object[]]$Arguments=@()) if($Arguments.Count){return $Text -f $Arguments};return $Text}
function Get-RamErrorText {param([string]$Text) return $Text}
function Write-RamLog {param($Text,$Kind) [void]$script:Logs.Add([string]$Text)}
function Show-RamMessage {param($Message,$Kind,$Buttons) [void]$script:Messages.Add([string]$Message);return $null}
function Show-RamError {param($Text) [void]$script:Messages.Add([string]$Text);return $null}
function Show-RamChromeForTestingConsent {$script:Consents++;return $false}
function Install-RamChromeForTesting {if($script:InstallThrows){throw 'synthetic download failure'};return 'fake-cft.exe'}
function Get-RamChromeForTestingPath {return $script:Cft}
function Get-RamInstalledBrowserPath {return $script:Installed}
function Get-RamExternalBrowserProfileDir {param($Kind) $script:ChosenKind=$Kind;return 'memory-profile'}
function Get-RamFreeLocalPort {return 60938}
function Get-RamProfileBrowserProcesses {
    param($ProfileDir)
    if($script:ProfileWindowOpen){return [pscustomobject]@{ProcessId=123}}
    return @()
}
function Clear-RamExternalBrowserProfileState {[void]$script:Order.Add('clear')}
function Stop-RamProfileBrowsers {
    param($ProfileDir)
    [void]$script:Order.Add('stop')
    if($script:StopResults.Count){return $script:StopResults.Dequeue()}
    return (-not $script:StopFails)
}
function Invoke-RamBrowserWarmup {}
function Set-RamWindowForeground {}
function Test-Path {param($LiteralPath) return $true}
function Get-Date {$script:Tick++;return [datetime]'2026-10-20' + [timespan]::FromSeconds($script:Tick)}
function Start-Sleep {param($Milliseconds,$Seconds)}
function Start-RamLoginBrowser {
    param($BrowserExe,$ProcArgs)
    $script:Starts++;$script:LaunchExe=$BrowserExe;$script:LaunchArgs=$ProcArgs
    [void]$script:Order.Add('start')
    return $script:Process
}
function Initialize-RamLoginCdpSession {
    param($Port)
    $script:Initializations++;[void]$script:Order.Add('initialize')
    if($script:InitThrows){throw $script:InitError}
    return [pscustomobject]@{PreviousCookie=$script:OldCookie}
}
function Get-RamBrowserLoginCookie {
    param($Port)
    $script:Polls++
    if($script:Polls -ge $script:CloseAfterPoll){$script:Process.HasExited=$true;$script:ProfileWindowOpen=$false}
    if($script:Cookies.Count){return $script:Cookies.Dequeue()}
    return $script:RepeatCookie
}
function Clear-RamBrowserLoginCookie {
    param($Port)
    [void]$script:Order.Add('cookie-clear')
    if($script:CookieClearFails){throw 'synthetic-private-cleanup-cookie'}
    return $true
}
function Test-RamAuthenticatedUser {
    param($Cookie)
    [void]$script:Checks.Add([pscustomobject]@{Cookie=$Cookie;Time=$script:Tick})
    if($script:AuthStates.Count){return @{State=$script:AuthStates.Dequeue();RetryAfterSeconds=$script:RetryAfterSeconds}}
    return @{State=$script:AuthState}
}
function New-Object {
    param([string]$TypeName,[object[]]$ArgumentList)
    if($TypeName -eq 'System.Net.HttpListener'){throw 'Legacy extension transport must not bind a port'}
    return Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
}
function Reset-LoginTest {
    $script:Settings=[pscustomobject]@{BrowserLoginBrowser='system';UiLanguage='ru'}
    $script:RamExternalBrowserLoginBusy=$false
    $script:Cft='fake-cft.exe';$script:Installed='fake-msedge.exe'
    $script:Starts=0;$script:Consents=0;$script:Tick=0;$script:Polls=0;$script:Initializations=0
    $script:StopFails=$false;$script:InitThrows=$false;$script:InstallThrows=$false
    $script:CookieClearFails=$false
    $script:InitError='synthetic browser policy failure'
    $script:StopResults=[Collections.Queue]::new()
    $script:LaunchExe='';$script:LaunchArgs=@();$script:ChosenKind=''
    $script:OldCookie=$null;$script:RepeatCookie=$null;$script:CloseAfterPoll=[int]::MaxValue
    $script:AuthState='valid'
    $script:RetryAfterSeconds=5
    $script:ProfileWindowOpen=$true
    $script:Logs=[Collections.Generic.List[string]]::new();$script:Messages=[Collections.Generic.List[string]]::new()
    $script:Order=[Collections.Generic.List[string]]::new();$script:Checks=[Collections.Generic.List[object]]::new()
    $script:Cookies=[Collections.Queue]::new();$script:AuthStates=[Collections.Queue]::new()
    $script:Process=[pscustomobject]@{HasExited=$false;ExitCode=0;MainWindowHandle=[IntPtr]::Zero}
    $script:Process | Add-Member ScriptMethod CloseMainWindow {$this.HasExited=$true;return $true}
    $script:Process | Add-Member ScriptMethod Kill {$this.HasExited=$true}
}
function Assert-Login {param($Condition,$Message) if(-not $Condition){throw $Message}}
$failed=[Collections.Generic.List[string]]::new();$script:passed=0
function Test-LoginCase {
    param($Name,[scriptblock]$Run)
    try {Reset-LoginTest;& $Run;$script:passed++;"PASS: $Name"}
    catch {[void]$failed.Add($Name+': '+$_.Exception.Message);"FAIL: $Name : $($_.Exception.Message)"}
}
Test-LoginCase 'System default works without CfT or download consent' {
    $script:Cft=$null;$script:Process.HasExited=$true
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 8
    Assert-Login ($null -eq $value -and $script:Starts -eq 1 -and $script:Consents -eq 0) 'System default did not launch independently'
}
Test-LoginCase 'Installed CfT never overrides system selection' {
    $script:Process.HasExited=$true
    [void](Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 8)
    Assert-Login ($script:ChosenKind -eq 'edge' -and $script:Starts -eq 1) 'System selection was ignored'
}
Test-LoginCase 'Explicit CfT selection remains available' {
    $script:Settings.BrowserLoginBrowser='cft';$script:Process.HasExited=$true
    [void](Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 8)
    Assert-Login ($script:ChosenKind -eq 'cft' -and $script:Starts -eq 1 -and $script:Consents -eq 0) 'Explicit CfT selection failed'
}
Test-LoginCase 'Missing explicit CfT does not silently fall back to system browser' {
    $script:Settings.BrowserLoginBrowser='cft';$script:Cft=$null
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 8
    Assert-Login ($null -eq $value -and $script:Starts -eq 0 -and $script:Consents -eq 0 -and $script:Messages.Count -gt 0) 'Missing explicit CfT silently changed browser'
}
foreach($language in @('ru','en')){
    Test-LoginCase "Missing chosen browser: scalar null and no download ($language)" {
        $script:Settings.UiLanguage=$language;$script:Cft=$null;$script:Installed=$null
        $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 8
        Assert-Login ($null -eq $value -and $script:Starts -eq 0 -and $script:Consents -eq 0 -and $script:Messages.Count -gt 0) 'Missing browser produced a sign-in/download or lacked warning'
    }
}
Test-LoginCase 'Stop own profile before clearing; launch arguments are constrained' {
    $script:Process.HasExited=$true
    [void](Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 8)
    Assert-Login (($script:Order -join ',') -match '^stop,clear,start') 'Profile state changed before browser stopped'
    $argsText=$script:LaunchArgs -join ' '
    Assert-Login ($argsText -match '--remote-debugging-port=60938' -and $argsText -match '--lang=en-US' -and $argsText -match '--app=data:text/html,AltHub') 'Missing browser launch contract'
    Assert-Login ($argsText -notmatch 'load-extension|remote-allow-origins|AutomationControlled|remote-debugging-port=0|incognito') 'Unsafe or obsolete launch flag'
}
Test-LoginCase 'Busy profile is not cleared or launched' {
    $script:StopFails=$true
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 8
    Assert-Login ($null -eq $value -and $script:Starts -eq 0 -and -not $script:Order.Contains('clear')) 'Busy profile was modified'
    Assert-Login (-not $script:RamExternalBrowserLoginBusy) 'Busy guard leaked after failure'
}
Test-LoginCase 'Reentrant login does not touch the active profile' {
    $script:RamExternalBrowserLoginBusy=$true
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 8
    Assert-Login ($null -eq $value -and $script:Starts -eq 0 -and $script:Order.Count -eq 0) 'Reentrant login touched active profile'
    Assert-Login $script:RamExternalBrowserLoginBusy 'Inner call cleared the outer busy guard'
}
Test-LoginCase 'Previous cookie is banned; only new authenticated cookie returns' {
    $script:OldCookie='synthetic-old';$script:Cookies.Enqueue('synthetic-old');$script:Cookies.Enqueue('synthetic-new')
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 30
    Assert-Login ($value -is [string] -and $value -eq 'synthetic-new') 'Did not return the new scalar cookie'
    Assert-Login ($script:Checks.Count -eq 1 -and $script:Checks[0].Cookie -eq 'synthetic-new') 'Previous cookie was authenticated'
    Assert-Login (-not $script:RamExternalBrowserLoginBusy) 'Busy guard leaked after success'
}
Test-LoginCase 'Launcher exit does not cancel a live own-profile browser window' {
    $script:Process.HasExited=$true
    $script:RepeatCookie='synthetic-handoff-cookie'
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 30
    Assert-Login ($value -ceq 'synthetic-handoff-cookie' -and $script:Initializations -eq 1 -and $script:Checks.Count -eq 1) 'Launcher handoff was mistaken for browser closure'
}
Test-LoginCase 'Failed cleanup rejects a validated cookie and releases busy guard' {
    $script:StopResults.Enqueue($true);$script:StopResults.Enqueue($false)
    $script:RepeatCookie='synthetic-cleanup-cookie'
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 30
    Assert-Login ($null -eq $value -and $script:Checks.Count -eq 1) 'Cleanup failure returned a validated sign-in'
    Assert-Login (-not $script:RamExternalBrowserLoginBusy -and $script:Messages.Count -gt 0) 'Cleanup failure leaked busy guard or omitted warning'
    Assert-Login (($script:Logs -join ' ') -match 'profile-busy' -and ($script:Logs -join ' ') -notmatch 'synthetic-cleanup-cookie') 'Cleanup diagnostic was missing or exposed cookie'
}
Test-LoginCase 'Protocol diagnostics allowlist reason codes and exclude raw error contents' {
    foreach($fixture in @(
        @{Error='Browser connection timed out.';Code='timeout'},
        @{Error='Browser returned an invalid protocol response.';Code='protocol-json'},
        @{Error='synthetic-private-error-cookie';Code='RuntimeException'}
    )) {
        Reset-LoginTest
        $script:InitThrows=$true;$script:InitError=$fixture.Error
        $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 30
        $log=$script:Logs -join ' '
        Assert-Login ($null -eq $value -and $log.Contains('('+$fixture.Code+')')) 'Stable protocol reason code missing'
        Assert-Login ($log -notmatch 'synthetic-private-error-cookie' -and -not $script:RamExternalBrowserLoginBusy) 'Raw protocol error leaked or busy guard remained'
    }
}
Test-LoginCase 'Unchanged unauthorized cookie is authenticated once' {
    $script:RepeatCookie='synthetic-invalid';$script:AuthState='unauthorized'
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 30
    Assert-Login ($null -eq $value -and $script:Checks.Count -eq 1 -and $script:Polls -gt 1) 'Repeated unauthorized cookie caused repeated validation'
}
foreach($state in @('rate_limited','network_error')){
    Test-LoginCase "Temporary $state respects cooldown across candidate changes" {
        $script:RepeatCookie='synthetic-retry';$script:AuthStates.Enqueue($state);$script:AuthStates.Enqueue('valid')
        if($state -eq 'rate_limited') {
            $script:RetryAfterSeconds=30
        }
        $script:Cookies.Enqueue('synthetic-before-cooldown')
        $script:Cookies.Enqueue('synthetic-rotated-during-cooldown')
        $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 45
        Assert-Login ($value -eq 'synthetic-retry' -and $script:Checks.Count -eq 2) 'Temporary validation failure was not retried'
        Assert-Login (($script:Checks[1].Time-$script:Checks[0].Time) -ge $script:RetryAfterSeconds) 'Retry-After was ignored or bypassed by a changed cookie'
    }
}
Test-LoginCase 'Timeout returns scalar null and releases guard' {
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 8
    Assert-Login ($null -eq $value -and -not $script:RamExternalBrowserLoginBusy) 'Timeout returned an account or leaked guard'
}
Test-LoginCase 'Closing browser returns scalar null' {
    $script:CloseAfterPoll=1
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 30
    Assert-Login ($null -eq $value -and $script:Polls -le 2 -and -not $script:RamExternalBrowserLoginBusy) 'Closing browser was not respected'
}
Test-LoginCase 'Browser policy failure produces no fake sign-in' {
    $script:InitThrows=$true
    $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 8
    Assert-Login ($null -eq $value -and $script:Checks.Count -eq 0 -and -not $script:RamExternalBrowserLoginBusy) 'Policy failure produced an account or leaked guard'
}
Test-LoginCase 'Malformed cookie is not sent to authenticated-user API' {
    foreach($cookie in @('synthetic'+[char]13+[char]10+'injected','contains space',('x'*16385))) {
        $script:RepeatCookie=$cookie
        $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 8
        Assert-Login ($null -eq $value -and $script:Checks.Count -eq 0) 'Malformed cookie reached authentication'
    }
}
Test-LoginCase 'Download helper remains scalar Boolean on success and failure' {
    $value=Request-RamChromeForTesting
    Assert-Login ($value -is [bool] -and $value) 'Successful download result was polluted'
    $script:InstallThrows=$true;$value=Request-RamChromeForTesting
    Assert-Login ($value -is [bool] -and -not $value) 'Failed download result was polluted'
}
Test-LoginCase 'Profile preferences suppress translation without changing unrelated data or cookies' {
    $profile=Join-Path ([IO.Path]::GetTempPath()) ('althub-profile-test-'+[guid]::NewGuid().ToString('N'))
    $default=Join-Path $profile 'Default'
    [void][IO.Directory]::CreateDirectory($default)
    try {
        $preferences=Join-Path $default 'Preferences';$cookies=Join-Path $default 'Cookies'
        [IO.File]::WriteAllText($preferences,'{"custom":{"keep":42},"translate":{"enabled":true,"keep":"unchanged"},"intl":{"accept_languages":"ru,en","keep":true}}')
        [IO.File]::WriteAllText($cookies,'synthetic-device-cookie-data')
        & {
            function Test-Path {param($LiteralPath) Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}
            & $script:RealProfileCleanup -ProfileDir $profile
        }
        $prefs=[IO.File]::ReadAllText($preferences) | ConvertFrom-Json
        Assert-Login ($prefs.translate.enabled -eq $false -and $prefs.intl.accept_languages -eq 'en-US,en') 'Translation/language preferences incorrect'
        Assert-Login ($prefs.custom.keep -eq 42 -and $prefs.translate.keep -eq 'unchanged' -and $prefs.intl.keep) 'Unrelated preferences changed'
        Assert-Login ([IO.File]::ReadAllText($cookies) -ceq 'synthetic-device-cookie-data') 'Device cookie file changed'
    } finally {
        $resolved=[IO.Path]::GetFullPath($profile)
        if($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('althub-profile-test-')) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
Test-LoginCase 'Profile process query matches exact quoted paths, not lookalikes' {
    $profile='C:\synthetic\AltHub Login'
    $script:ProcessFixtures=@(
        [pscustomobject]@{ProcessId=1;CommandLine='msedge.exe "--user-data-dir=C:\synthetic\AltHub Login" --new-window about:blank'},
        [pscustomobject]@{ProcessId=2;CommandLine='chrome.exe --user-data-dir="C:\synthetic\AltHub Login" --new-window about:blank'},
        [pscustomobject]@{ProcessId=3;CommandLine='chrome.exe "--user-data-dir=c:\SYNTHETIC\althub login"'},
        [pscustomobject]@{ProcessId=4;CommandLine='chrome.exe "--user-data-dir=C:\synthetic\AltHub Login-other"'},
        [pscustomobject]@{ProcessId=5;CommandLine='chrome.exe "--user-data-dir=C:\synthetic\AltHub Login"suffix'},
        [pscustomobject]@{ProcessId=6;CommandLine='chrome.exe --user-data-dir="C:\synthetic\AltHub Login\nested"'},
        [pscustomobject]@{ProcessId=7;CommandLine='chrome.exe --different--user-data-dir="C:\synthetic\AltHub Login"'}
    )
    $matches=@(& {
        function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) return $script:ProcessFixtures}
        & $script:RealProfileProcessQuery -ProfileDir $profile
    })
    Assert-Login (($matches.ProcessId -join ',') -eq '1,2,3') 'Profile query accepted an adjacent/similar browser profile'
}
Test-LoginCase 'Success and timeout clear only browser auth before closing its profile' {
    foreach($success in @($true,$false)) {
        Reset-LoginTest
        if($success){$script:RepeatCookie='synthetic-new-cookie'}
        $value=Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 30
        Assert-Login ($script:Order.Contains('cookie-clear')) 'Browser auth cookie was not cleared'
        Assert-Login ($script:Order.IndexOf('cookie-clear') -lt ($script:Order.Count-1) -and $script:Order[$script:Order.Count-1] -eq 'stop') 'Browser closed before auth cleanup'
        if($success){Assert-Login ($value -ceq 'synthetic-new-cookie') 'Browser deletion changed returned AltHub cookie'}
    }
}
Test-LoginCase 'Auth cleanup failure is logged safely and still closes the owned profile' {
    $script:CookieClearFails=$true;$script:RepeatCookie='synthetic-new-cookie'
    [void](Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 30)
    Assert-Login ($script:Order[$script:Order.Count-1] -eq 'stop' -and -not $script:RamExternalBrowserLoginBusy) 'Cleanup failure prevented profile close'
    Assert-Login (($script:Logs -join ' ') -notmatch 'synthetic-private-cleanup-cookie' -and $script:Logs.Count -gt 1) 'Cleanup error leaked secret or was silent'
}
Test-LoginCase 'Early user close stays closed; only failed app startup may fall back once' {
    foreach($exitCode in @(0,1)) {
        Reset-LoginTest
        $script:Process.HasExited=$true;$script:Process.ExitCode=$exitCode;$script:ProfileWindowOpen=$false
        $script:InitThrows=$true
        [void](Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 30)
        if($exitCode -eq 0){Assert-Login ($script:Starts -eq 1) 'Early user close reopened the browser'}
        else {Assert-Login ($script:Starts -eq 2 -and ($script:LaunchArgs -join ' ') -match '--new-window about:blank' -and ($script:Logs -join ' ') -match '1') 'Failed app startup fallback was unbounded or silent'}
    }
    Reset-LoginTest
    $script:CloseAfterPoll=1
    [void](Show-RamExternalBrowserLoginWindow -Root $root -TimeoutSeconds 30)
    Assert-Login ($script:Starts -eq 1) 'An initialized sign-in was restarted'
}
Test-LoginCase 'Owned browser gets graceful close before a bounded force fallback' {
    foreach($graceful in @($true,$false)) {
        $script:CloseWasCalled=$false;$script:ForceWasCalled=$false;$script:Graceful=$graceful
        & {
            function Get-RamProfileBrowserProcesses {
                param($ProfileDir)
                if(-not $script:ForceWasCalled -and -not ($script:CloseWasCalled -and $script:Graceful)){return [pscustomobject]@{ProcessId=123}}
            }
            function Get-Process {
                param($Id,$ErrorAction)
                $process=[pscustomobject]@{}
                $process | Add-Member ScriptMethod CloseMainWindow {$script:CloseWasCalled=$true;return $true}
                return $process
            }
            function Stop-Process {
                param($Id,[switch]$Force,$ErrorAction)
                Assert-Login $script:CloseWasCalled 'Force occurred before graceful close'
                $script:ForceWasCalled=$true
            }
            Assert-Login (& $script:RealProfileStop -ProfileDir 'C:\synthetic\own-login') 'Owned profile did not stop'
        }
        Assert-Login ($script:CloseWasCalled -and $script:ForceWasCalled -eq (-not $graceful)) 'Graceful exit unnecessarily forced or fallback missing'
    }
}
"Browser login: $passed passed, $($failed.Count) failed"
if($failed.Count){throw ($failed -join [Environment]::NewLine)}
