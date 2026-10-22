#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/BrowserLoginCdp.ps1')

function Assert-Cdp {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function Start-CdpFixture {
    param([string]$Mode = 'normal',[string]$PageUrl = 'https://www.roblox.com/login')
    $reserve = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $reserve.Start(); $port = $reserve.LocalEndpoint.Port; $reserve.Stop()
    $listener = New-Object Net.HttpListener
    $listener.Prefixes.Add("http://127.0.0.1:$port/")
    $listener.Start()
    $commands = New-Object 'Collections.Concurrent.ConcurrentQueue[string]'
    $worker = [powershell]::Create()
    [void]$worker.AddScript({
        param($Listener,$Port,$Mode,$PageUrl,$Commands)
        try {
            $connections = 0
            while ($Listener.IsListening) {
                $context = $Listener.GetContext()
                if (-not $context.Request.IsWebSocketRequest) {
                    $targets = @(
                        @{type='worker';url='https://www.roblox.com/';webSocketDebuggerUrl="ws://127.0.0.1:$Port/devtools/page/worker"},
                        @{type='page';url='https://roblox.com.evil.invalid/';webSocketDebuggerUrl="ws://127.0.0.1:$Port/devtools/page/evil"},
                        @{type='page';url=$PageUrl;webSocketDebuggerUrl="ws://127.0.0.1:$Port/devtools/page/test"}
                    )
                    $body = [Text.Encoding]::UTF8.GetBytes(($targets | ConvertTo-Json -Compress))
                    if ($Mode -eq 'redirect') { $context.Response.StatusCode=302; $context.Response.RedirectLocation='http://example.invalid/' }
                    $context.Response.OutputStream.Write($body,0,$body.Length)
                    $context.Response.Close()
                    continue
                }
                $socket = $context.AcceptWebSocketAsync([NullString]::Value).GetAwaiter().GetResult().WebSocket
                try {
                    $bytes = New-Object byte[] 8192
                    $received = $socket.ReceiveAsync([ArraySegment[byte]]::new($bytes),[Threading.CancellationToken]::None).GetAwaiter().GetResult()
                    $request = [Text.Encoding]::UTF8.GetString($bytes,0,$received.Count)
                    $Commands.Enqueue($request)
                    if ($Mode -eq 'timeout') { [Threading.Thread]::Sleep(3600); break }
                    if ($Mode -eq 'closed') {
                        $socket.CloseOutputAsync([Net.WebSockets.WebSocketCloseStatus]::NormalClosure,'',[Threading.CancellationToken]::None).GetAwaiter().GetResult()
                        break
                    }
                    $domain = if ($Mode -eq 'domain') { '.roblox.com.evil.invalid' } else { '.roblox.com' }
                    $response = @{id=1;result=@{note=[string][char]0x00E9;cookies=@(@{name='.ROBLOSECURITY';domain=$domain;value='synthetic-test-value'},@{name='other';domain='.roblox.com';value='ignored'})}} | ConvertTo-Json -Depth 5 -Compress
                    if ($Mode -eq 'error') { $response='{"id":1,"error":{"code":-1,"message":"fixture error"}}' }
                    if ($Mode -eq 'invalid') { $response='private-synthetic-token-not-json' }
                    if ($Mode -eq 'large') { $response='x' * 1048577 }
                    if ($Mode -eq 'fragment') {
                        foreach ($ignored in @('{"method":"Network.event"}','{"id":99,"result":{}}')) {
                            $eventBytes = [Text.Encoding]::UTF8.GetBytes($ignored)
                            $socket.SendAsync([ArraySegment[byte]]::new($eventBytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
                        }
                    }
                    $reply = [Text.Encoding]::UTF8.GetBytes($response)
                    if ($Mode -eq 'fragment') {
                        $middle = [Array]::IndexOf($reply,[byte]0xC3) + 1
                        $socket.SendAsync([ArraySegment[byte]]::new($reply,0,$middle),[Net.WebSockets.WebSocketMessageType]::Text,$false,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
                        $socket.SendAsync([ArraySegment[byte]]::new($reply,$middle,$reply.Length-$middle),[Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
                    } else {
                        $socket.SendAsync([ArraySegment[byte]]::new($reply),[Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
                    }
                    $connections++
                    $socket.CloseOutputAsync([Net.WebSockets.WebSocketCloseStatus]::NormalClosure,'',[Threading.CancellationToken]::None).GetAwaiter().GetResult()
                    [Threading.Thread]::Sleep(100)
                    if ($Mode -ne 'init' -or $connections -ge 3) { break }
                } finally { $socket.Dispose() }
            }
        } catch {
            if ($Listener.IsListening -and $Mode -notin @('large','timeout')) { throw }
        }
    }).AddArgument($listener).AddArgument($port).AddArgument($Mode).AddArgument($PageUrl).AddArgument($commands)
    $async = $worker.BeginInvoke()
    return @{Listener=$listener;Worker=$worker;Async=$async;Port=$port;Commands=$commands}
}

function Stop-CdpFixture {
    param($Fixture)
    $Fixture.Listener.Stop()
    $Fixture.Listener.Close()
    $Fixture.Worker.Stop()
    $Fixture.Worker.Dispose()
}

$fixture = Start-CdpFixture -Mode fragment
try {
    $value = Get-RamBrowserLoginCookie -Port $fixture.Port
    Assert-Cdp ($value -eq 'synthetic-test-value') 'Fragmented reply or event filtering failed.'
    $command = $fixture.Commands.ToArray()[0] | ConvertFrom-Json
    Assert-Cdp ($command.method -eq 'Network.getCookies') 'Unexpected CDP method.'
    Assert-Cdp (@($command.params.urls).Count -eq 1 -and $command.params.urls[0] -ceq 'https://www.roblox.com/') 'Cookie URL scope widened.'
    'PASS: real local WebSocket, fragments, events, response ID, cookie scope'
} finally { Stop-CdpFixture $fixture }

foreach ($mode in @('domain','closed','timeout','large','error','invalid','redirect')) {
    $fixture = Start-CdpFixture -Mode $mode
    try {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $failed = $false; $value = $null
        try { $value = Get-RamBrowserLoginCookie -Port $fixture.Port } catch {
            $failed = $true
            Assert-Cdp ($_.Exception.Message -notmatch 'private-synthetic-token') 'Response contents leaked in an exception.'
        }
        if ($mode -eq 'domain') { Assert-Cdp ($null -eq $value -and -not $failed) 'Foreign cookie domain accepted.' }
        else { Assert-Cdp $failed "Expected failure: $mode" }
        Assert-Cdp ($watch.Elapsed.TotalSeconds -lt 6) "Unbounded operation: $mode"
        "PASS: $mode"
    } finally { Stop-CdpFixture $fixture }
}

foreach ($url in @('https://roblox.com.evil.invalid/','http://www.roblox.com/','about:blank','data:text/html,AltHub','data:text/html,other')) {
    $fixture = Start-CdpFixture -PageUrl $url
    try { Assert-Cdp ($null -eq (Get-RamLoginCdpTarget -Port $fixture.Port)) 'Unsafe target accepted.' }
    finally { Stop-CdpFixture $fixture }
}
foreach ($url in @('data:text/html,AltHub','data:text/html,other')) {
    $fixture = Start-CdpFixture -PageUrl $url
    try {
        $target=Get-RamLoginCdpTarget -Port $fixture.Port -AllowBlank
        Assert-Cdp (($null -ne $target) -eq ($url -ceq 'data:text/html,AltHub')) 'Bootstrap target allowlist widened.'
    } finally { Stop-CdpFixture $fixture }
}
'PASS: exact non-secret app bootstrap target only during initialization'
$fixture = Start-CdpFixture
try {
    Assert-Cdp (Clear-RamBrowserLoginCookie -Port $fixture.Port) 'Final cookie cleanup did not run.'
    $command=$fixture.Commands.ToArray()[0] | ConvertFrom-Json
    Assert-Cdp ($command.method -ceq 'Network.deleteCookies' -and $command.params.name -ceq '.ROBLOSECURITY' -and $command.params.url -ceq 'https://www.roblox.com/') 'Final cookie cleanup widened scope.'
    'PASS: final local auth deletion is name and URL scoped without server logout'
} finally { Stop-CdpFixture $fixture }
$fixture = Start-CdpFixture -PageUrl 'about:blank' -Mode init
try {
    $result = Initialize-RamLoginCdpSession -Port $fixture.Port
    Assert-Cdp ($result.PreviousCookie -eq 'synthetic-test-value') 'Previous cookie not captured.'
    $commands = @($fixture.Commands.ToArray() | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-Cdp (($commands.method -join ',') -eq 'Network.getCookies,Network.deleteCookies,Page.navigate') 'Preparation order incorrect.'
    Assert-Cdp ($commands[1].params.name -ceq '.ROBLOSECURITY' -and $commands[1].params.url -ceq 'https://www.roblox.com/') 'Deletion scope widened.'
    Assert-Cdp ($commands[2].params.url -ceq 'https://www.roblox.com/login') 'Navigation scope widened.'
    'PASS: blank preparation, previous cookie, scoped deletion and navigation'
} finally { Stop-CdpFixture $fixture }

foreach ($target in @('ws://localhost:12345/devtools/page/a','ws://127.0.0.1:12346/devtools/page/a','wss://127.0.0.1:12345/devtools/page/a','ws://127.0.0.1:12345/devtools/browser/a','ws://user@127.0.0.1:12345/devtools/page/a','ws://127.0.0.1:12345/devtools/page/a?extra=1')) {
    $failed=$false
    try { Invoke-RamLoginCdpCommand -Port 12345 -Target $target -Method Network.getCookies } catch { $failed=$true }
    Assert-Cdp $failed 'Unsafe WebSocket address accepted.'
}
'PASS: exact loopback host, port and page path validation'
'Browser protocol checks passed.'
if (-not $NoPause) { [void](Read-Host 'Enter') }
