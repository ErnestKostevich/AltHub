#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart
$script:ReliabilityFixture=Join-Path ([IO.Path]::GetTempPath()) ('althub-account-reliability-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $script:ReliabilityFixture)
function Get-RamDataDir { $script:ReliabilityFixture }
function Write-RamLog { param($Message,$Level) }
function Set-RamStatus { param($Message) }
function Assert-Reliability { param([bool]$Value,[string]$Message) if(-not $Value){throw $Message} }
$failures=New-Object Collections.ArrayList
function Test-Reliability {
    param([string]$Name,[scriptblock]$Body)
    try { & $Body; "PASS: $Name" } catch { [void]$failures.Add("${Name}: $($_.Exception.Message)"); "FAIL: $Name" }
}
function New-CheckFixture {
    $a=New-RamAccount -Alias 'Synthetic';$a.Cookie='fixture-old';$a.CookieOk='yes';$a.Robux=123
    $script:Accounts=@($a)
    $script:CookieCheckState=[pscustomobject]@{
        Queue=(New-Object Collections.ArrayList);Job=[pscustomobject]@{Task=[pscustomobject]@{IsCompleted=$true}}
        InfoJob=$null;Current=[pscustomobject]@{Account=$a;Cookie='fixture-old';Attempts=1}
        Ok=0;Bad=0;Unknown=0;Dead=(New-Object Collections.ArrayList);Total=1;Quiet=$true;NextAt=[datetime]::MinValue
    }
    [void]$script:CookieCheckState.Queue.Add([pscustomobject]@{Account=$a;Cookie=$null;Attempts=0})
    return $a
}
try {
    $script:ReadOnly=$false;$script:AccountsWriteBlocked=$false
    $original=New-RamAccount -Alias 'Stored fixture';$original.Cookie='synthetic-not-a-live-cookie'
    Save-RamAccounts -Accounts @($original)
    Test-Reliability 'direct write obeys unreadable-store guard' {
        $before=(Get-FileHash (Get-RamAccountsPath)).Hash
        $script:AccountsWriteBlocked=$true;$blocked=$false
        try { Save-RamAccounts -Accounts @() } catch { $blocked=$true } finally { $script:AccountsWriteBlocked=$false }
        Assert-Reliability ($blocked -and (Get-FileHash (Get-RamAccountsPath)).Hash -eq $before) 'Direct save replaced the protected original or reported success'
    }
    Save-RamAccounts -Accounts @($original)
    Test-Reliability 'failed replacement preserves store and removes temporary file' {
        $before=(Get-FileHash (Get-RamAccountsPath)).Hash
        $stream=[IO.File]::Open((Get-RamAccountsPath),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $blocked=$false
        try { try { Save-RamAccounts -Accounts @() } catch { $blocked=$true } } finally { $stream.Dispose() }
        Assert-Reliability ($blocked -and (Get-FileHash (Get-RamAccountsPath)).Hash -eq $before) 'Locked original was changed or failure was hidden'
        Assert-Reliability (@(Get-ChildItem -LiteralPath $script:ReliabilityFixture -Filter '*.tmp').Count -eq 0) 'Failed write left a temporary envelope'
    }
    Test-Reliability 'encrypted rotation keeps five recoverable versions and reloads' {
        foreach($n in 1..7){$original.Alias="Stored fixture $n";Save-RamAccounts -Accounts @($original)}
        $loaded=@(Load-RamAccounts)
        Assert-Reliability ($loaded.Count -eq 1 -and $loaded[0].Alias -eq 'Stored fixture 7') 'Round trip lost records'
        $backups=@(Get-ChildItem -LiteralPath (Join-Path $script:ReliabilityFixture 'backups/accounts') -Filter '*.dat')
        Assert-Reliability ($backups.Count -eq 5) 'Backup rotation did not keep five versions'
        foreach($backup in $backups){$envelope=Get-Content -LiteralPath $backup.FullName -Raw -Encoding UTF8 | ConvertFrom-Json;$bytes=Unprotect-RamBytes -Envelope $envelope;try{Assert-Reliability (@(ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString($bytes))).Count -eq 1) 'Backup cannot recover account'}finally{[Array]::Clear($bytes,0,$bytes.Length)}}
        Save-RamAccounts -Accounts @($original) -Password 'Synthetic master password'
        Assert-Reliability ((Get-RamStorageMode) -eq 'aes' -and @(Load-RamAccounts -Password 'Synthetic master password')[0].Alias -eq 'Stored fixture 7') 'AES re-encryption failed'
        $before=(Get-FileHash (Get-RamAccountsPath)).Hash;$wrongPasswordRejected=$false
        try{[void](Load-RamAccounts -Password 'Wrong synthetic password')}catch{$wrongPasswordRejected=$true}
        Assert-Reliability ($wrongPasswordRejected -and (Get-FileHash (Get-RamAccountsPath)).Hash -eq $before) 'Wrong password altered the encrypted store'
        Save-RamAccounts -Accounts @($original)
        Assert-Reliability ((Get-RamStorageMode) -eq 'dpapi' -and @(Load-RamAccounts)[0].Alias -eq 'Stored fixture 7') 'Returning to DPAPI failed'
    }
    function Complete-RamAuthCheckAsync { param($Job) [pscustomobject]@{State='unauthorized';User=$null;Message='Synthetic 401';RetryAfterSeconds=1} }
    Test-Reliability 'stale unauthorized response cannot invalidate a renewed login' {
        $a=New-CheckFixture;$a.Cookie='fixture-new'
        Invoke-RamCookieCheckPump
        Assert-Reliability ($a.CookieOk -eq 'yes' -and $script:CookieCheckState.Bad -eq 0) 'Old 401 invalidated renewed cookie'
    }
    Test-Reliability 'removed or replaced account cannot receive a stale response' {
        $a=New-CheckFixture;$replacement=New-RamAccount -Alias 'Replacement';$replacement.Id=$a.Id;$replacement.Cookie='fixture-new';$replacement.CookieOk='yes';$script:Accounts=@($replacement)
        Invoke-RamCookieCheckPump
        Assert-Reliability ($a.CookieOk -eq 'yes' -and $replacement.CookieOk -eq 'yes' -and $script:CookieCheckState.Bad -eq 0) 'Detached account was mutated or queued for repair'
    }
    Test-Reliability 'stale balance result cannot overwrite renewed account metadata' {
        $a=New-CheckFixture;$a.Cookie='fixture-new'
        $script:CookieCheckState.Job=$null;$script:CookieCheckState.InfoJob=[pscustomobject]@{Task=[pscustomobject]@{IsCompleted=$true}}
        function Complete-RamAccountInfoAsync {param($Job) [pscustomobject]@{Robux=999;Premium='yes';Created='2000-01-01'} }
        Invoke-RamCookieCheckPump
        Assert-Reliability ($a.Robux -eq 123) 'Old metadata overwrote renewed account'
    }
    Test-Reliability 'current 401 invalidates while transient failures preserve state' {
        foreach($state in @('unauthorized','rate_limited','transient')){
            function Complete-RamAuthCheckAsync {param($Job) [pscustomobject]@{State=$state;User=$null;Message='Synthetic result';RetryAfterSeconds=1} }
            $a=New-CheckFixture;$script:CookieCheckState.Current.Attempts=2
            Invoke-RamCookieCheckPump
            Assert-Reliability ($a.CookieOk -eq $(if($state -eq 'unauthorized'){'no'}else{'yes'})) "Wrong classification: $state"
        }
    }
    if($failures.Count){throw ($failures -join [Environment]::NewLine)}
} finally {
    $script:ReadOnly=$true;$script:AccountsWriteBlocked=$false;$script:CookieCheckState=$null
    $resolved=[IO.Path]::GetFullPath($script:ReliabilityFixture)
    if($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^althub-account-reliability-[a-f0-9]{32}$'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
