#requires -Version 5.1

function Wait-RamBrowserCdpTask {
    param($Task, [datetime]$Deadline)
    while (-not $Task.IsCompleted) {
        if ([datetime]::UtcNow -ge $Deadline) { throw 'Browser connection timed out.' }
        if ('System.Windows.Forms.Application' -as [type]) { [Windows.Forms.Application]::DoEvents() }
        [Threading.Thread]::Sleep(10)
    }
    return $Task.GetAwaiter().GetResult()
}

function Get-RamLoginCdpTarget {
    param([ValidateRange(1,65535)][int]$Port, [switch]$AllowBlank)
    $request = [Net.HttpWebRequest]::Create("http://127.0.0.1:$Port/json/list")
    $request.AllowAutoRedirect = $false
    $request.Proxy = $null
    $request.Timeout = 2000
    $request.ReadWriteTimeout = 2000
    $response = $null; $stream = $null; $buffer = $null
    try {
        $deadline = [datetime]::UtcNow.AddSeconds(2)
        $response = Wait-RamBrowserCdpTask -Task ($request.GetResponseAsync()) -Deadline $deadline
        if ([int]$response.StatusCode -ne 200) { throw 'Browser target discovery failed.' }
        if ($response.ContentLength -gt 1048576) { throw 'Browser response is too large.' }
        $stream = $response.GetResponseStream()
        $buffer = New-Object IO.MemoryStream
        $chunk = New-Object byte[] 8192
        do {
            $count = Wait-RamBrowserCdpTask -Task ($stream.ReadAsync($chunk,0,$chunk.Length)) -Deadline $deadline
            if ($buffer.Length + $count -gt 1048576) { throw 'Browser response is too large.' }
            $buffer.Write($chunk,0,$count)
        } while ($count -gt 0)
        try { $targets = ([Text.UTF8Encoding]::new($false,$true)).GetString($buffer.ToArray()) | ConvertFrom-Json }
        catch { throw 'Browser returned an invalid target response.' }
        foreach ($target in $targets) {
            $url = $null
            if ($target.type -ne 'page' -or -not [uri]::TryCreate([string]$target.url,[UriKind]::Absolute,[ref]$url)) { continue }
            if (($AllowBlank -and $url.AbsoluteUri -in @('about:blank','data:text/html,AltHub')) -or
                ($url.Scheme -eq 'https' -and ($url.DnsSafeHost -eq 'roblox.com' -or $url.DnsSafeHost.EndsWith('.roblox.com',[StringComparison]::OrdinalIgnoreCase)))) {
                return [string]$target.webSocketDebuggerUrl
            }
        }
        return $null
    } finally {
        $request.Abort()
        if ($null -ne $buffer) { $buffer.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
    }
}

function Invoke-RamLoginCdpCommand {
    param(
        [ValidateRange(1,65535)][int]$Port,
        [string]$Target,
        [ValidateSet('Network.getCookies','Network.deleteCookies','Page.navigate')][string]$Method
    )
    $uri = $null
    if (-not [uri]::TryCreate($Target,[UriKind]::Absolute,[ref]$uri) -or
        $uri.Scheme -ne 'ws' -or $uri.DnsSafeHost -ne '127.0.0.1' -or $uri.Port -ne $Port -or
        $uri.AbsolutePath -notmatch '^/devtools/page/[^/]+$' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'Browser returned an invalid local connection address.'
    }
    $socket = New-Object Net.WebSockets.ClientWebSocket
    $cancel = New-Object Threading.CancellationTokenSource
    $message = New-Object IO.MemoryStream
    try {
        $deadline = [datetime]::UtcNow.AddSeconds(3)
        $cancel.CancelAfter(3000)
        $socket.Options.Proxy = $null
        [void](Wait-RamBrowserCdpTask -Task ($socket.ConnectAsync($uri,$cancel.Token)) -Deadline $deadline)
        $parameters = switch ($Method) {
            'Network.getCookies' { @{ urls = @('https://www.roblox.com/') } }
            'Network.deleteCookies' { @{ name = '.ROBLOSECURITY'; url = 'https://www.roblox.com/' } }
            'Page.navigate' { @{ url = 'https://www.roblox.com/login' } }
        }
        $request = [Text.Encoding]::UTF8.GetBytes((@{id=1;method=$Method;params=$parameters} | ConvertTo-Json -Compress -Depth 4))
        [void](Wait-RamBrowserCdpTask -Task ($socket.SendAsync([ArraySegment[byte]]::new($request),[Net.WebSockets.WebSocketMessageType]::Text,$true,$cancel.Token)) -Deadline $deadline)
        $chunk = New-Object byte[] 8192
        while ($true) {
            $frame = Wait-RamBrowserCdpTask -Task ($socket.ReceiveAsync([ArraySegment[byte]]::new($chunk),$cancel.Token)) -Deadline $deadline
            if ($frame.MessageType -ne [Net.WebSockets.WebSocketMessageType]::Text) { throw 'Browser connection closed or returned non-text data.' }
            if ($message.Length + $frame.Count -gt 1048576) { throw 'Browser response is too large.' }
            $message.Write($chunk,0,$frame.Count)
            if (-not $frame.EndOfMessage) { continue }
            try { $reply = ([Text.UTF8Encoding]::new($false,$true)).GetString($message.ToArray()) | ConvertFrom-Json }
            catch { throw 'Browser returned an invalid protocol response.' }
            $message.SetLength(0)
            $message.Position = 0
            if ($reply.id -ne 1) { continue }
            if ($null -ne $reply.error) { throw 'Browser rejected the cookie request.' }
            return $reply.result
        }
    } finally {
        $cancel.Cancel()
        $socket.Abort()
        $socket.Dispose()
        $cancel.Dispose()
        $message.Dispose()
    }
}

function Get-RamBrowserLoginCookie {
    param([ValidateRange(1,65535)][int]$Port)
    $target = Get-RamLoginCdpTarget -Port $Port
    if (-not $target) { return $null }
    $result = Invoke-RamLoginCdpCommand -Port $Port -Target $target -Method 'Network.getCookies'
    foreach ($cookie in $result.cookies) {
        if ($cookie.name -ceq '.ROBLOSECURITY' -and $cookie.domain -in @('.roblox.com','roblox.com','www.roblox.com') -and $cookie.value -is [string]) {
            return $cookie.value
        }
    }
    return $null
}

function Initialize-RamLoginCdpSession {
    param([ValidateRange(1,65535)][int]$Port)
    $target = Get-RamLoginCdpTarget -Port $Port -AllowBlank
    if (-not $target) { return $null }
    $result = Invoke-RamLoginCdpCommand -Port $Port -Target $target -Method 'Network.getCookies'
    $previousCookie = $null
    foreach ($cookie in $result.cookies) {
        if ($cookie.name -ceq '.ROBLOSECURITY' -and $cookie.domain -in @('.roblox.com','roblox.com','www.roblox.com') -and $cookie.value -is [string]) {
            $previousCookie = $cookie.value
            break
        }
    }
    [void](Invoke-RamLoginCdpCommand -Port $Port -Target $target -Method 'Network.deleteCookies')
    $navigation = Invoke-RamLoginCdpCommand -Port $Port -Target $target -Method 'Page.navigate'
    if ($navigation.errorText) { throw 'Browser could not open the sign-in page.' }
    return [pscustomobject]@{ PreviousCookie = $previousCookie }
}

function Clear-RamBrowserLoginCookie {
    param([ValidateRange(1,65535)][int]$Port)
    $target = Get-RamLoginCdpTarget -Port $Port -AllowBlank
    if (-not $target) { return $false }
    # Remove the local copy, not the server session saved by AltHub or device cookies.
    [void](Invoke-RamLoginCdpCommand -Port $Port -Target $target -Method 'Network.deleteCookies')
    return $true
}
