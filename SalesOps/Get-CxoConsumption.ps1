<#
.SYNOPSIS
    Pulls Azure SKU / service / subscription consumption for a TPID from the CX Observe
    (cxp.azure.com) Consumption domain API.

.DESCRIPTION
    CX Observe's UI is backed by a REST "insights/aspects" API. This script calls it directly
    so you get the full result set (not just the top N the tiles render) as CSV.

    Endpoint:
      POST https://consumption-trafficmanager-wus3-prod.trafficmanager.net
           /api/insights/ch:customer::tpid:<TPID>/aspects/<aspect>
           ?startDate=..&endDate=..&unit=month&view=pivotedchart&aggregation=Sum

    The "Select" array in the body chooses the grouping dimension. An OData-style
    Filter lets you scope one dimension by another, which is how -Hierarchy rolls
    SKUs (L5) up under their parent product (L4).

    AUTH - the API needs a delegated token for
    api://31390d6a-f361-4eb0-922a-ca3a563f3ad1/user_impersonation:

      1. -AutoToken   RECOMMENDED. Runs Get-CxoToken.ps1, which drives a scripted Edge
                      session and lifts the bearer token off the live requests. Sign in
                      once; the dedicated Edge profile keeps you signed in afterwards.
      2. -Token       Paste from F12 > Network > any consumption-trafficmanager request
                      > Request Headers > authorization.
      3. $env:CXO_TOKEN            same value as -Token
         $env:CXO_CUSTOMER_TOKEN   optional; from a customerdom-trafficmanager request,
                                   used only to resolve the customer name for folder naming.

      -DeviceLogin still exists but is BLOCKED on tenants whose Conditional Access
      requires a managed device: the device-code flow cannot present device identity
      and fails with "your admin requires the device requesting access to be managed."
      Prefer -AutoToken.

    Tokens last about an hour. Nothing is written to disk except the optional
    encrypted refresh token used by -DeviceLogin.

.EXAMPLE
    # Simplest full pull - captures its own token, resolves the customer name
    .\Get-CxoConsumption.ps1 -Tpid 642489 -AutoToken -Hierarchy

.EXAMPLE
    .\Get-CxoConsumption.ps1 -Tpid 642489 -Token $env:CXO_TOKEN -Months 12 -OutDir .\out

.EXAMPLE
    # Adds <stem>_product_sku_hierarchy.csv : Service -> Product -> SKU with % of product.
    # On PowerShell 7 the ~450 calls run 8-way parallel (about 40s); 5.1 runs sequentially.
    .\Get-CxoConsumption.ps1 -Tpid 642489 -AutoToken -Hierarchy -Throttle 12

.EXAMPLE
    # Turn the hierarchy into an Excel pivot workbook
    .\Get-CxoConsumption.ps1 -Tpid 642489 -AutoToken -Hierarchy -OutDir .\out
    python .\New-CxoPivot.py .\out\642489_MORGAN_STANLEY\642489_MORGAN_STANLEY_product_sku_hierarchy.csv

.EXAMPLE
    # Send output anywhere; the folder is created if it does not exist.
    # Writes to  C:\Reports\CXO\642489\
    .\Get-CxoConsumption.ps1 -Tpid 642489 -OutDir 'C:\Reports\CXO'

    # Writes straight into C:\Reports\CXO\  (no TPID subfolder)
    .\Get-CxoConsumption.ps1 -Tpid 642489 -OutDir 'C:\Reports\CXO' -NoTpidSubfolder

    # Relative paths, ~ and environment variables all work
    .\Get-CxoConsumption.ps1 -Tpid 642489 -OutDir '%OneDrive%\Documents\Capacity'

.NOTES
    Data returned is Microsoft Confidential \ Microsoft FTE. Keep it internal.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tpid,

    [string]$Token,

    [switch]$DeviceLogin,

    # Launch a scripted Edge session (Get-CxoToken.ps1) to capture the API tokens
    # from your signed-in CX Observe session. Use this when you have no token to hand -
    # device-code sign-in is blocked by Conditional Access on managed-device tenants.
    [switch]$AutoToken,

    [int]$Months = 6,

    [datetime]$StartDate,

    [datetime]$EndDate,

    [ValidateSet('consumptionunits', 'compute', 'storage')]
    [string[]]$Aspects = @('consumptionunits'),

    # Also emit a Service -> Product -> SKU rollup by filtering L5 per L4 product.
    # Costs ~1 request per service and per product (a few hundred), so it takes a minute.
    [switch]$Hierarchy,

    # Customer name used in the <TPID>_<CustomerName> folder and file names.
    # Looked up automatically from the CX Observe Customer domain; supply it to
    # skip the lookup or to override the official name.
    [string]$CustomerName,

    # Where to write the CSVs. Accepts absolute or relative paths, ~, and
    # environment variables (e.g. "%OneDrive%\Reports"). Created if missing.
    # Default: a <TPID> subfolder next to this script.
    [string]$OutDir,

    # By default a <TPID> subfolder is appended to -OutDir so multi-TPID runs
    # don't collide. Use -NoTpidSubfolder to write straight into -OutDir.
    [switch]$NoTpidSubfolder,

    # Parallel request fan-out for -Hierarchy. Requires PowerShell 7+; on 5.1 the
    # script automatically falls back to sequential calls. Set to 1 to force sequential.
    [ValidateRange(1, 32)]
    [int]$Throttle = 8,

    [int]$Top = 5000
)

$ErrorActionPreference = 'Stop'

$ApiBase   = 'https://consumption-trafficmanager-wus3-prod.trafficmanager.net'
$CustBase  = 'https://customerdom-trafficmanager-wus3-prod.trafficmanager.net'
$ApiScope  = 'api://31390d6a-f361-4eb0-922a-ca3a563f3ad1/user_impersonation'
$CustScope = 'api://0428270b-93cb-496a-8e6f-d323b13aaa27/user_impersonation'
$ClientId  = '7d401da2-e710-4600-be01-f048d5e307fa'   # CX Observe SPA
$TenantId  = '72f988bf-86f1-41af-91ab-2d7cd011db47'   # microsoft.com
$CacheDir  = Join-Path $env:LOCALAPPDATA 'CxoConsumption'
$CacheFile = Join-Path $CacheDir 'refresh.dat'

# Dimensions available on the consumptionunits aspect.
# L3 exists but is empty in the source data, so it is excluded by default.
$Dimensions = [ordered]@{
    'L1_ServiceFamily'   = 'workload_dimensions_service_level_1'
    'L2_ServiceName'     = 'workload_dimensions_service_level_2'
    'L4_ProductName'     = 'workload_dimensions_service_level_4'
    'L5_SKU'             = 'workload_dimensions_service_level_5'
    'SubscriptionName'   = 'SubscriptionName'
    'SubscriptionGuid'   = 'SubscriptionGuid'
}

function Protect-Text([string]$Text) {
    Add-Type -AssemblyName System.Security
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $enc = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'CurrentUser')
    [Convert]::ToBase64String($enc)
}

function Unprotect-Text([string]$Blob) {
    Add-Type -AssemblyName System.Security
    $enc = [Convert]::FromBase64String($Blob)
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect($enc, $null, 'CurrentUser')
    [Text.Encoding]::UTF8.GetString($bytes)
}

function Get-TokenFromRefresh {
    param([string]$Scope = $ApiScope)
    if (-not (Test-Path $CacheFile)) { return $null }
    try {
        $rt = Unprotect-Text (Get-Content $CacheFile -Raw)
        $resp = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Body @{
                client_id     = $ClientId
                grant_type    = 'refresh_token'
                refresh_token = $rt
                scope         = "$Scope offline_access"
            }
        if ($resp.refresh_token) {
            New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
            Set-Content -Path $CacheFile -Value (Protect-Text $resp.refresh_token)
        }
        return $resp.access_token
    } catch {
        Write-Verbose "Refresh failed: $($_.Exception.Message)"
        return $null
    }
}

function Get-TokenByDeviceCode {
    $dc = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode" `
        -Body @{ client_id = $ClientId; scope = "$ApiScope offline_access" }

    Write-Host ''
    Write-Host $dc.message -ForegroundColor Yellow
    Write-Host ''
    Start-Process $dc.verification_uri | Out-Null

    $deadline = (Get-Date).AddSeconds([int]$dc.expires_in)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds ([int]$dc.interval)
        try {
            $resp = Invoke-RestMethod -Method Post `
                -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                -Body @{
                    client_id   = $ClientId
                    grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
                    device_code = $dc.device_code
                }
            if ($resp.refresh_token) {
                New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
                Set-Content -Path $CacheFile -Value (Protect-Text $resp.refresh_token)
            }
            return $resp.access_token
        } catch {
            $err = ''
            if ($_.ErrorDetails.Message) { $err = ($_.ErrorDetails.Message | ConvertFrom-Json).error }
            if ($err -eq 'authorization_pending') { continue }
            if ($err -eq 'slow_down') { Start-Sleep -Seconds 5; continue }
            throw "Device code sign-in failed: $($_.ErrorDetails.Message)"
        }
    }
    throw 'Device code sign-in timed out.'
}

function Invoke-TokenCapture {
    # Runs Get-CxoToken.ps1 (sibling script) and caches the result for this session.
    if ($script:CapturedTokens) { return $script:CapturedTokens }

    $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $grabber = Join-Path $root 'Get-CxoToken.ps1'
    if (-not (Test-Path $grabber)) {
        throw "AutoToken needs Get-CxoToken.ps1 next to this script (looked in $root)."
    }

    Write-Host 'Capturing tokens from your CX Observe session ...' -ForegroundColor DarkGray
    $script:CapturedTokens = & $grabber -Tpid $Tpid
    return $script:CapturedTokens
}

function Resolve-AccessToken {
    if ($Token)           { return ($Token           -replace '^\s*Bearer\s+', '') }
    if ($env:CXO_TOKEN)   { return ($env:CXO_TOKEN   -replace '^\s*Bearer\s+', '') }
    if ($AutoToken) {
        $t = (Invoke-TokenCapture).ConsumptionToken
        if ($t) { return ($t -replace '^\s*Bearer\s+', '') }
        throw 'Token capture did not return a Consumption token.'
    }
    $t = Get-TokenFromRefresh
    if ($t) { return $t }
    if ($DeviceLogin) { return Get-TokenByDeviceCode }
    throw @'
No token available. Pick one:
  -AutoToken                       capture from a scripted Edge session (recommended)
  -Token '<bearer ...>'            paste from F12 > Network > consumption-trafficmanager
  $env:CXO_TOKEN = '<bearer ...>'  same, via environment variable
(-DeviceLogin is blocked by Conditional Access on managed-device tenants.)
'@
}

function ConvertTo-SafeName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $s = $Name.Trim()
    # strip characters Windows forbids in paths, collapse whitespace
    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) { $s = $s.Replace($c, ' ') }
    $s = ($s -replace '[,]', ' ') -replace '\s+', ' '
    $s = $s.Trim().Trim('.')
    $s = $s -replace ' ', '_'
    if ($s.Length -gt 60) { $s = $s.Substring(0, 60).TrimEnd('_') }
    return $s
}

function Get-CxoCustomerName {
    param([string]$Tpid)

    # Needs a customer-domain token; from -AutoToken capture, env var, or cached refresh.
    $custToken = $null
    if ($env:CXO_CUSTOMER_TOKEN) {
        $custToken = $env:CXO_CUSTOMER_TOKEN -replace '^\s*Bearer\s+', ''
    } elseif ($AutoToken) {
        $custToken = (Invoke-TokenCapture).CustomerToken -replace '^\s*Bearer\s+', ''
    } else {
        $custToken = Get-TokenFromRefresh -Scope $CustScope
    }
    if (-not $custToken) { return $null }

    $uri = "$CustBase/api/Insights/ch:special:all/aspects/ch:aspect:search:azurecustomers" +
           '?startDate=2024-01-01T00:00:00.000Z&endDate=' +
           (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') +
           '&unit=week&view=List&topFacets=0'

    $body = @{
        Facets                  = @()
        Filter                  = "TPID eq '$Tpid'"
        IncludeTotalResultCount = $true
        OrderBy                 = @()
        QueryType               = 'Full'
        SearchMode              = 'All'
        SearchText              = ''
        Skip                    = 0
        Top                     = 1
        SearchFields            = @('TPID')
        Select                  = @('EntityId', 'EntityName', 'TPID')
    } | ConvertTo-Json -Compress

    try {
        $r = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/json' `
                -Headers @{ Authorization = "Bearer $custToken" }
        if ($r.Results -and $r.Results.Count -gt 0) { return $r.Results[0].Document.EntityName }
    } catch {
        Write-Verbose "Customer name lookup failed: $($_.Exception.Message)"
    }
    return $null
}

function Resolve-OutputDirectory {
    param([string]$Path, [string]$FolderName, [switch]$NoSub)

    $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $root
    } else {
        $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
        if ($Path -like '~*') { $Path = Join-Path $HOME $Path.Substring(1).TrimStart('\', '/') }
        if (-not [System.IO.Path]::IsPathRooted($Path)) {
            $Path = Join-Path (Get-Location).Path $Path
        }
    }

    if (-not $NoSub) { $Path = Join-Path $Path $FolderName }

    try   { $full = [System.IO.Path]::GetFullPath($Path) }
    catch { throw "Invalid -OutDir path: '$Path' ($($_.Exception.Message))" }

    if (-not (Test-Path -LiteralPath $full)) {
        New-Item -ItemType Directory -Force -Path $full | Out-Null
    } elseif (-not (Get-Item -LiteralPath $full).PSIsContainer) {
        throw "-OutDir points to a file, not a folder: $full"
    }

    # confirm we can actually write there
    $probe = Join-Path $full ".cxo_write_test"
    try {
        Set-Content -LiteralPath $probe -Value 'x' -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force
    } catch {
        throw "Cannot write to -OutDir '$full': $($_.Exception.Message)"
    }

    return $full
}

function Invoke-CxoAspect {
    param([string]$AccessToken, [string]$Aspect, [string]$Dimension,
          [string]$Start, [string]$End, [int]$TopN, [string]$Filter = '')

    $uri = '{0}/api/insights/ch:customer::tpid:{1}/aspects/ch:aspect:{2}?startDate={3}&endDate={4}&unit=month&view=pivotedchart&aggregation=Sum' `
           -f $ApiBase, $Tpid, $Aspect, $Start, $End

    $body = @{
        Facets                  = @()
        Filter                  = $Filter      # OData-style, e.g. "<col> eq 'value'"
        IncludeTotalResultCount = $false
        OrderBy                 = @()
        QueryType               = 'Full'
        SearchMode              = 'All'
        SearchText              = ''
        Skip                    = 0
        Top                     = $TopN          # server ignores Skip; ask for everything at once
        SearchFields            = @()
        Select                  = @($Dimension)
    } | ConvertTo-Json -Compress

    Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/json' `
        -Headers @{ Authorization = "Bearer $AccessToken" }
}

function Get-CxoHierarchy {
    param([string]$AccessToken, [string]$Start, [string]$End)

    $L2 = 'workload_dimensions_service_level_2'
    $L4 = 'workload_dimensions_service_level_4'
    $L5 = 'workload_dimensions_service_level_5'

    $useParallel = ($PSVersionTable.PSVersion.Major -ge 7) -and ($Throttle -gt 1)

    # Sequential helper (PS 5.1 path, and used for the small ungrouped calls).
    $get = {
        param($dim, $filter)
        try { Invoke-CxoAspect -AccessToken $AccessToken -Aspect 'consumptionunits' -Dimension $dim `
                               -Start $Start -End $End -TopN $Top -Filter $filter }
        catch { @() }
    }

    # Fan out one filtered request per parent value. Returns a hashtable keyed by parent label.
    function Invoke-FanOut {
        param([string[]]$Parents, [string]$ParentCol, [string]$ChildCol, [string]$Activity)

        $result = @{}
        if (-not $Parents -or $Parents.Count -eq 0) { return $result }

        if ($useParallel) {
            $uriFmt = '{0}/api/insights/ch:customer::tpid:{1}/aspects/ch:aspect:consumptionunits?startDate={2}&endDate={3}&unit=month&view=pivotedchart&aggregation=Sum' `
                      -f $ApiBase, $Tpid, $Start, $End
            Write-Host ("  {0}: {1} calls, {2} at a time ..." -f $Activity, $Parents.Count, $Throttle)

            $pairs = $Parents | ForEach-Object -ThrottleLimit $Throttle -Parallel {
                $parent = $_
                $body = @{
                    Facets = @(); Filter = "$using:ParentCol eq '$($parent -replace "'","''")'"
                    IncludeTotalResultCount = $false; OrderBy = @(); QueryType = 'Full'
                    SearchMode = 'All'; SearchText = ''; Skip = 0; Top = $using:Top
                    SearchFields = @(); Select = @($using:ChildCol)
                } | ConvertTo-Json -Compress

                $rows = @()
                for ($attempt = 1; $attempt -le 3; $attempt++) {
                    try {
                        $rows = Invoke-RestMethod -Uri $using:uriFmt -Method Post -Body $body `
                                    -ContentType 'application/json' `
                                    -Headers @{ Authorization = "Bearer $using:AccessToken" }
                        break
                    } catch {
                        if ($attempt -eq 3) { $rows = @() } else { Start-Sleep -Milliseconds (250 * $attempt) }
                    }
                }
                [pscustomobject]@{ Parent = $parent; Rows = $rows }
            }
            foreach ($p in $pairs) { $result[$p.Parent] = $p.Rows }
        }
        else {
            $i = 0
            foreach ($parent in $Parents) {
                $i++
                Write-Progress -Activity $Activity -Status $parent `
                    -PercentComplete (100 * $i / [math]::Max($Parents.Count, 1))
                $result[$parent] = & $get $ChildCol ("$ParentCol eq '{0}'" -f ($parent -replace "'", "''"))
            }
            Write-Progress -Activity $Activity -Completed
        }
        return $result
    }

    Write-Host 'Mapping Service (L2) -> Product (L4) ...'
    $services = & $get $L2 ''
    $l4ByService = Invoke-FanOut -Parents @($services.Label) -ParentCol $L2 -ChildCol $L4 -Activity 'Service -> Product'

    $parentOfProduct = @{}
    foreach ($svc in $services.Label) {
        foreach ($p in $l4ByService[$svc]) {
            if (-not $parentOfProduct.ContainsKey($p.Label)) { $parentOfProduct[$p.Label] = $svc }
        }
    }

    Write-Host 'Expanding Product (L4) -> SKU (L5) ...'
    $products = & $get $L4 ''
    $l5ByProduct = Invoke-FanOut -Parents @($products.Label) -ParentCol $L4 -ChildCol $L5 -Activity 'Product -> SKU'

    foreach ($p in $products) {
        $pAcu = if ($p.Values -and $p.Values[0]) { [double]$p.Values[0].Value } else { 0 }
        $skus = $l5ByProduct[$p.Label]

        if (-not $skus) {
            [pscustomobject]@{ Tpid=$Tpid; ServiceName_L2=$parentOfProduct[$p.Label]; ProductName_L4=$p.Label
                               ProductACU=[math]::Round($pAcu,4); SKU_L5='(no SKU detail)'; SKU_ACU=$null; PctOfProduct=$null }
            continue
        }
        foreach ($s in $skus) {
            $sAcu = if ($s.Values -and $s.Values[0]) { [double]$s.Values[0].Value } else { 0 }
            [pscustomobject]@{
                Tpid           = $Tpid
                ServiceName_L2 = $parentOfProduct[$p.Label]
                ProductName_L4 = $p.Label
                ProductACU     = [math]::Round($pAcu, 4)
                SKU_L5         = $s.Label
                SKU_ACU        = [math]::Round($sAcu, 4)
                PctOfProduct   = if ($pAcu) { [math]::Round(100 * $sAcu / $pAcu, 2) } else { $null }
            }
        }
    }
}

# ---------------------------------------------------------------- main

if (-not $EndDate)   { $EndDate   = (Get-Date).Date.AddDays(1).AddSeconds(-1) }
if (-not $StartDate) { $StartDate = (Get-Date).Date.AddMonths(-$Months) }
$startIso = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$endIso   = $EndDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

$accessToken = Resolve-AccessToken

# Build the <TPID>_<CustomerName> naming stem used for the folder and every file.
if (-not $CustomerName) { $CustomerName = Get-CxoCustomerName -Tpid $Tpid }
$safeCustomer = ConvertTo-SafeName $CustomerName
$Stem = if ($safeCustomer) { "{0}_{1}" -f $Tpid, $safeCustomer } else { $Tpid }

if (-not $safeCustomer) {
    Write-Warning "Could not resolve the customer name for TPID $Tpid (needs -DeviceLogin or -CustomerName). Falling back to '$Tpid'."
}

$nameForDisplay = if ($CustomerName) { $CustomerName } else { '(unknown)' }
$OutDir = Resolve-OutputDirectory -Path $OutDir -FolderName $Stem -NoSub:$NoTpidSubfolder
Write-Host ("Customer     : {0}" -f $nameForDisplay) -ForegroundColor DarkCyan
Write-Host ("Output folder: {0}" -f $OutDir) -ForegroundColor DarkCyan

$all = New-Object System.Collections.Generic.List[object]

foreach ($aspect in $Aspects) {
    $dims = if ($aspect -eq 'consumptionunits') { $Dimensions } else {
        [ordered]@{ 'SubscriptionName' = 'SubscriptionName'; 'SubscriptionGuid' = 'SubscriptionGuid' }
    }

    foreach ($name in $dims.Keys) {
        Write-Host ("[{0}] {1} ..." -f $aspect, $name) -NoNewline
        try {
            $rows = Invoke-CxoAspect -AccessToken $accessToken -Aspect $aspect -Dimension $dims[$name] `
                                     -Start $startIso -End $endIso -TopN $Top
        } catch {
            Write-Host " FAILED: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        $recs = foreach ($r in $rows) {
            [pscustomobject]@{
                Tpid      = $Tpid
                Aspect    = $aspect
                Dimension = $name
                Name      = $r.Label
                Value     = if ($r.Values -and $r.Values[0]) { [math]::Round([double]$r.Values[0].Value, 4) } else { $null }
                StartDate = $StartDate.ToString('yyyy-MM-dd')
                EndDate   = $EndDate.ToString('yyyy-MM-dd')
            }
        }

        $recs | Export-Csv -NoTypeInformation -Encoding UTF8 `
            -Path (Join-Path $OutDir ("{0}_{1}_{2}.csv" -f $Stem, $aspect, $name))
        $recs | ForEach-Object { $all.Add($_) }
        Write-Host (" {0} rows" -f @($recs).Count) -ForegroundColor Green
    }
}

$combined = Join-Path $OutDir ("{0}_all.csv" -f $Stem)
$all | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $combined

if ($Hierarchy) {
    $tree = Get-CxoHierarchy -AccessToken $accessToken -Start $startIso -End $endIso
    $treePath = Join-Path $OutDir ("{0}_product_sku_hierarchy.csv" -f $Stem)
    $tree | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $treePath
    Write-Host ("Hierarchy: {0} rows -> {1}" -f @($tree).Count, $treePath) -ForegroundColor Cyan
}

Write-Host ''
Write-Host ("Total {0} rows -> {1}" -f $all.Count, $combined) -ForegroundColor Cyan
$all | Where-Object Dimension -eq 'L5_SKU' | Sort-Object Value -Descending |
    Select-Object -First 15 Name, Value | Format-Table -AutoSize

