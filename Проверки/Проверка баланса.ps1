#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart

# Все HTTP-ответы искусственные: ни вход, ни баланс в Roblox не запрашиваются.
$script:BalanceClient=[pscustomobject]@{ Delay=$true; FailBalance=$false; Calls=(New-Object Collections.ArrayList) }
$script:BalanceClient | Add-Member ScriptMethod SendAsync {
    param($req,$token)
    $key=if($req.RequestUri.AbsolutePath.EndsWith('/authenticated')){'auth'}elseif($req.RequestUri.AbsolutePath.EndsWith('/currency')){'balance'}elseif($req.RequestUri.AbsolutePath.EndsWith('/validate-membership')){'premium'}else{'created'}
    $body=switch($key){'auth'{'{"id":123,"name":"Fixture"}'}'balance'{'{"robux":0}'}'premium'{'false'}'created'{'{"created":"2020-01-02T00:00:00Z"}'}}
    $status=if($key -eq 'balance' -and $this.FailBalance){429}else{200}
    $response=New-Object Net.Http.HttpResponseMessage([Net.HttpStatusCode]$status)
    $response.Content=New-Object Net.Http.StringContent($body)
    $source=New-Object 'System.Threading.Tasks.TaskCompletionSource[System.Net.Http.HttpResponseMessage]'
    [void]$this.Calls.Add([pscustomobject]@{Key=$key;Host=$req.RequestUri.Host;HasCookie=$req.Headers.Contains('Cookie');Source=$source;Response=$response})
    if($key -eq 'auth' -or -not $this.Delay){$source.SetResult($response)}
    return $source.Task
}
function Get-RamHttpClient { return $script:BalanceClient }
function Assert-Balance { param([bool]$Value,[string]$Message) if(-not $Value){throw $Message} }
function Tick-Balance { if($null -ne $script:CookieCheckState){$script:CookieCheckState.NextAt=[datetime]::MinValue; Invoke-RamCookieCheckPump} }
function Start-BalanceFixture {
    $script:Settings=Get-RamDefaultSettings
    $script:Accounts=@((New-RamAccount -Alias 'Fixture' -Cookie 'FAKE-COOKIE'))
    $script:UI=@{Form=(New-Object Windows.Forms.Form)}
    Start-RamCookieCheckBatch -Accounts $script:Accounts -Quiet
    $script:UI.CookieCheckTimer.Stop()
    Tick-Balance; Tick-Balance
}
try {
    Start-BalanceFixture
    Assert-Balance ($null -ne $script:CookieCheckState.InfoJob -and -not $script:CookieCheckState.InfoJob.Task.IsCompleted) 'Баланс запрошен не асинхронно'
    Tick-Balance
    Assert-Balance ($script:Accounts[0].Robux -eq -1) 'Незавершённый запрос изменил баланс'
    foreach($call in $script:BalanceClient.Calls | Where-Object Key -ne 'auth'){$call.Source.SetResult($call.Response)}
    Tick-Balance; Tick-Balance
    Assert-Balance ($script:Accounts[0].Robux -eq 0 -and $script:Accounts[0].Premium -eq 'no' -and $script:Accounts[0].Created -eq '2020-01-02') 'Ноль Robux или данные аккаунта потеряны'
    Assert-Balance ($null -eq $script:CookieCheckState) 'Проверка не завершилась'
    'PASS: batch check loads balance, Premium and date without blocking; zero is retained'
    Assert-Balance (-not ($script:BalanceClient.Calls | Where-Object {($_.Key -eq 'created' -and $_.HasCookie) -or $_.Host -notmatch '(^|\.)roblox\.com$'})) 'Кука ушла не тому запросу'
    'PASS: authentication stays on Roblox; public account date has no cookie'
    $script:UI.Form.Dispose()
    $script:BalanceClient.Calls.Clear();$script:BalanceClient.Delay=$false;$script:BalanceClient.FailBalance=$true
    Start-BalanceFixture
    $script:Accounts[0].Robux=700
    Tick-Balance;Tick-Balance
    Assert-Balance ($script:Accounts[0].Robux -eq 700 -and $script:Accounts[0].CookieOk -eq 'yes') 'Сбой баланса испортил вход или прежнее значение'
    'PASS: balance HTTP failure retains the previous value and valid login'
    $script:UI.Form.Dispose()
    $script:BalanceClient.Calls.Clear();$script:BalanceClient.Delay=$true
    Start-BalanceFixture
    Dispose-RamFormRuntime
    Assert-Balance ($null -eq $script:CookieCheckState -and $null -eq $script:UI.CookieCheckTimer) 'Закрытие оставило зависшую проверку'
    'PASS: closing or switching menus cancels pending checks and permits a new check'
} finally {
    Dispose-RamFormRuntime
    if($script:UI.Form){$script:UI.Form.Dispose()}
}
if(-not $NoPause){[void](Read-Host 'Enter')}
