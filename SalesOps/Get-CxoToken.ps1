<#
.SYNOPSIS
    Captures CX Observe API bearer tokens from a signed-in Microsoft Edge session.

.DESCRIPTION
    Get-CxoConsumption.ps1 talks to the CX Observe domain APIs, which need delegated
    tokens. Azure CLI is not consented to those APIs, and device-code sign-in is blocked
    by Conditional Access (the tenant requires a managed device, which the device-code
    flow cannot present).

    This script works around that by launching Edge with the DevTools Protocol enabled,
    loading the CX Observe pages that call those APIs, and reading the Authorization
    header straight off the outgoing requests. No password or token is ever typed,
    stored on disk, or logged.

    A dedicated Edge profile lives under %LOCALAPPDATA%\CxoConsumption\edge-profile so
    it never disturbs your normal browser. You sign in once; later runs reuse that
    profile's cookies and complete silently.

.PARAMETER Tpid
    TPID used to drive the two pages that trigger the APIs. Any TPID you can see works.

.PARAMETER Consumption
    Capture only the Consumption token (skips the customer-name lookup token).

.PARAMETER Visible
    Show the browser window. Required the first time so you can sign in.
    After that the script can run headless via -Headless.

.PARAMETER Headless
    Force headless. Only works once the profile already holds a valid session.

.PARAMETER TimeoutSeconds
    How long to wait for both tokens (default 180). Allow time for interactive sign-in.

.OUTPUTS
    PSCustomObject with ConsumptionToken and CustomerToken (raw "Bearer ..." strings).

.EXAMPLE
    $t = .\Get-CxoToken.ps1
    $env:CXO_TOKEN = $t.ConsumptionToken
    $env:CXO_CUSTOMER_TOKEN = $t.CustomerToken

.EXAMPLE
    # Usually you don't call this directly - Get-CxoConsumption.ps1 -AutoToken does it.
    .\Get-CxoConsumption.ps1 -Tpid 642489 -AutoToken -Hierarchy

.NOTES
    Tokens are short lived (about an hour) and are returned in memory only.
#>
[CmdletBinding()]
param(
    [string]$Tpid = '642489',
    [switch]$Consumption,
    [switch]$Visible,
    [switch]$Headless,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

$ProfileDir = Join-Path $env:LOCALAPPDATA 'CxoConsumption\edge-profile'
$needCustomer = -not $Consumption

function Find-Edge {
    $paths = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    $cmd = Get-Command msedge.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'Could not locate msedge.exe.'
}

function Get-FreePort {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop(); return $port
}

function Send-Cdp {
    param($Socket, [int]$Id, [string]$Method, [hashtable]$Params = @{})
    $msg = @{ id = $Id; method = $Method; params = $Params } | ConvertTo-Json -Depth 6 -Compress
    $buf = [ArraySegment[byte]]::new([Text.Encoding]::UTF8.GetBytes($msg))
    $Socket.SendAsync($buf, 'Text', $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
}

function Receive-Cdp {
    param($Socket, [int]$WaitMs = 500)
    $buffer = [byte[]]::new(65536)
    $seg = [ArraySegment[byte]]::new($buffer)
    $sb = [Text.StringBuilder]::new()
    $cts = [Threading.CancellationTokenSource]::new($WaitMs)
    try {
        do {
            $res = $Socket.ReceiveAsync($seg, $cts.Token).GetAwaiter().GetResult()
            [void]$sb.Append([Text.Encoding]::UTF8.GetString($buffer, 0, $res.Count))
        } while (-not $res.EndOfMessage)
        return $sb.ToString()
    } catch { return $null } finally { $cts.Dispose() }
}

# ------------------------------------------------------------------ launch Edge

$edge = Find-Edge
$port = Get-FreePort
New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null

$firstRun = -not (Test-Path (Join-Path $ProfileDir 'Default'))
$showWindow = $Visible -or $firstRun -or (-not $Headless)

$edgeArgs = @(
    "--remote-debugging-port=$port"
    "--user-data-dir=`"$ProfileDir`""
    '--no-first-run'
    '--no-default-browser-check'
    '--disable-features=msEdgeSplitScreen,msImplicitSignin'
    'about:blank'
)
if (-not $showWindow) { $edgeArgs = @('--headless=new') + $edgeArgs }

if ($firstRun) {
    Write-Host 'First run: a browser window will open. Sign in with your @microsoft.com account.' -ForegroundColor Yellow
}

$proc = Start-Process -FilePath $edge -ArgumentList $edgeArgs -PassThru
$socket = $null

try {
    # wait for the DevTools endpoint
    $wsUrl = $null
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline -and -not $wsUrl) {
        Start-Sleep -Milliseconds 400
        try {
            $tabs = Invoke-RestMethod "http://127.0.0.1:$port/json/list" -TimeoutSec 3
            $page = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
            if ($page) { $wsUrl = $page.webSocketDebuggerUrl }
        } catch { }
    }
    if (-not $wsUrl) { throw "Edge DevTools endpoint never came up on port $port." }

    $socket = [Net.WebSockets.ClientWebSocket]::new()
    $socket.ConnectAsync([Uri]$wsUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()

    $id = 0
    Send-Cdp $socket (++$id) 'Network.enable' | Out-Null

    $urls = [ordered]@{}
    if ($needCustomer) {
        $preset = '%7B%22SearchFields%22%3A%5B%22EntityName%22%2C%22TPID%22%5D%2C%22SortColumns%22%3A%5B%5D%2C%22Filters%22%3A%5B%5D%7D'
        $urls['customer'] = "https://cxp.azure.com/cxobserve/allcustomers?search=$Tpid&searchType=Customer&scope=customer&presetFilter=$preset"
    }
    $urls['consumption'] = "https://cxp.azure.com/cxobserve/customers/ch:customer::tpid:$Tpid/consumption/usage"

    $consTok = $null; $custTok = $null
    $overall = (Get-Date).AddSeconds($TimeoutSeconds)

    foreach ($key in $urls.Keys) {
        Send-Cdp $socket (++$id) 'Page.navigate' @{ url = $urls[$key] } | Out-Null
        Write-Host ("Loading {0} page ..." -f $key) -ForegroundColor DarkGray

        $stage = (Get-Date).AddSeconds([math]::Min(90, $TimeoutSeconds))
        while ((Get-Date) -lt $stage -and (Get-Date) -lt $overall) {
            $raw = Receive-Cdp $socket 800
            if (-not $raw) {
                if ($consTok -and ($custTok -or -not $needCustomer)) { break }
                continue
            }
            foreach ($line in ($raw -split "(?<=\})(?=\{`"method`")")) {
                if ($line -notmatch 'requestWillBeSent') { continue }
                try { $evt = $line | ConvertFrom-Json } catch { continue }
                $req = $evt.params.request
                if (-not $req) { continue }
                $auth = $req.headers.authorization
                if (-not $auth) { $auth = $req.headers.Authorization }
                if (-not $auth) { continue }
                if ($req.url -like '*consumption-trafficmanager*') { $consTok = $auth }
                if ($req.url -like '*customerdom-trafficmanager*')  { $custTok = $auth }
            }
            if ($consTok -and ($custTok -or -not $needCustomer)) { break }
            if ($key -eq 'customer' -and $custTok) { break }
        }
        if ($consTok -and ($custTok -or -not $needCustomer)) { break }
    }

    if (-not $consTok) {
        throw 'Did not capture a Consumption token. Re-run with -Visible and finish signing in.'
    }
    if ($needCustomer -and -not $custTok) {
        Write-Warning 'Captured the Consumption token but not the Customer token; customer-name lookup will be skipped.'
    }

    [pscustomobject]@{
        ConsumptionToken = $consTok
        CustomerToken    = $custTok
        CapturedAt       = Get-Date
    }
}
finally {
    if ($socket) {
        try { $socket.Dispose() } catch { }
    }
    if ($proc -and -not $proc.HasExited) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
    }
    # Edge spawns children; clean up any left holding our profile dir
    Get-Process msedge -ErrorAction SilentlyContinue |
        Where-Object { $_.StartTime -gt (Get-Date).AddMinutes(-10) -and $_.Path -eq $edge } |
        Where-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine -like "*$ProfileDir*" } |
        ForEach-Object { try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch { } }
}
