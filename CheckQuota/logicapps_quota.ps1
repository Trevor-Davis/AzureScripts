$ErrorActionPreference = "Stop"

Write-Host "Azure Logic Apps Standard / Microsoft.Web quota check"
Write-Host "----------------------------------------------------"

Write-Host ""
Write-Host "Checking prerequisites..."

$azCommand = Get-Command az -ErrorAction SilentlyContinue
if ($null -eq $azCommand) {
  throw "Azure CLI is not installed. Install it from https://aka.ms/installazurecliwindows, then rerun this script."
}

Write-Host "Azure CLI found."

$quotaExtension = az extension show --name quota -o json 2>$null
if ([string]::IsNullOrWhiteSpace($quotaExtension)) {
  Write-Host "Azure CLI quota extension is not installed. Installing..."
  az extension add --name quota | Out-Null
  Write-Host "Azure CLI quota extension installed."
} else {
  Write-Host "Azure CLI quota extension found."
}

$sub = Read-Host "Enter Azure subscription ID"
$regionInput = Read-Host "Enter Azure region to check, for example eastus or East US"

$region = $regionInput.Trim().ToLowerInvariant().Replace(" ", "")
$scope = "/subscriptions/$sub/providers/Microsoft.Web/locations/$region"

Write-Host ""
Write-Host "Checking Azure CLI login..."
$accountJson = az account show -o json 2>$null

if ([string]::IsNullOrWhiteSpace($accountJson)) {
  Write-Host "You are not logged in. Opening Azure CLI login..."
  az login | Out-Null
  $accountJson = az account show -o json 2>$null

  if ([string]::IsNullOrWhiteSpace($accountJson)) {
    throw "Azure CLI login failed or no account is available."
  }
}

$account = $accountJson | ConvertFrom-Json
Write-Host ("Logged in as: " + $account.user.name)

Write-Host ""
Write-Host ("Checking access to subscription " + $sub + "...")
$targetSubJson = az account show --subscription $sub -o json 2>$null

if ([string]::IsNullOrWhiteSpace($targetSubJson)) {
  throw ("This signed-in account cannot access subscription " + $sub + ". Confirm the subscription ID and account permissions.")
}

$targetSub = $targetSubJson | ConvertFrom-Json
Write-Host ("Subscription accessible: " + $targetSub.name + " [" + $targetSub.id + "]")

az account set --subscription $sub

Write-Host ""
Write-Host ("Checking Microsoft.Web quota entries in " + $region + "...")
$quotaJson = az quota list --scope $scope -o json
$quota = $quotaJson | ConvertFrom-Json

$quotaResults =
  $quota |
  Where-Object {
    ($_.name.value + " " + $_.name.localizedValue + " " + $_.resourceName + " " + $_.unit) -match "M1|Logic|Workflow|Microsoft.Web|serverfarm|plan|site|Standard|Premium|Basic"
  } |
  Select-Object `
    @{Name="Name";Expression={$_.name.localizedValue}},
    @{Name="Resource";Expression={$_.name.value}},
    @{Name="Current";Expression={$_.currentValue}},
    @{Name="Limit";Expression={$_.limit.value}},
    @{Name="Unit";Expression={$_.unit}}

if ($null -ne $quotaResults) {
  $quotaResults | Format-Table -AutoSize
} else {
  Write-Host "No matching quota entries returned by Azure Quota API."
}

Write-Host ""
Write-Host ("Checking Microsoft.Web regional usage entries in " + $region + "...")
$usageJson = az rest --method get --url ("https://management.azure.com/subscriptions/" + $sub + "/providers/Microsoft.Web/locations/" + $region + "/usages?api-version=2023-12-01") -o json
$usage = ($usageJson | ConvertFrom-Json).value

$usageResults =
  $usage |
  Select-Object `
    @{Name="Name";Expression={$_.name.localizedValue}},
    @{Name="Resource";Expression={$_.name.value}},
    @{Name="Current";Expression={$_.currentValue}},
    @{Name="Limit";Expression={$_.limit}},
    @{Name="Unit";Expression={$_.unit}}

if ($null -ne $usageResults) {
  $usageResults | Format-Table -AutoSize
} else {
  Write-Host "No Microsoft.Web usage entries returned."
}

Write-Host ""
Write-Host "Checking Workflow Standard regional availability for WS1, WS2, and WS3..."

$workflowSkus = @("WS1", "WS2", "WS3")
$allSkuAvailability = @()

foreach ($workflowSku in $workflowSkus) {
  Write-Host ""
  Write-Host ("Checking regions where " + $workflowSku + " is listed as available...")

  try {
    $locationsJson = az appservice list-locations --sku $workflowSku -o json
    $locations = $locationsJson | ConvertFrom-Json

    if ($null -eq $locations) {
      Write-Host ("No regions returned for " + $workflowSku + ".")
    } else {
      foreach ($location in $locations) {
        $locationNameNormalized = ($location.name -replace " ", "").ToLowerInvariant()

        $allSkuAvailability += New-Object PSObject -Property @{
          Sku = $workflowSku
          Region = $location.name
          DisplayName = $location.displayName
          IsTargetRegion = ($locationNameNormalized -eq $region)
        }
      }
    }
  } catch {
    Write-Host ("Could not check regional availability for " + $workflowSku + ".")
  }
}

Write-Host ""
Write-Host "Workflow Standard regional availability summary:"

$regionAvailability = @()
$availabilityGroups = $allSkuAvailability | Group-Object -Property Region

foreach ($availabilityGroup in $availabilityGroups) {
  $groupItems = @($availabilityGroup.Group)
  $displayName = $groupItems[0].DisplayName
  $availableSkus = ($groupItems | Sort-Object -Property Sku | Select-Object -ExpandProperty Sku) -join ", "
  $regionNameNormalized = ($availabilityGroup.Name -replace " ", "").ToLowerInvariant()

  $regionAvailability += New-Object PSObject -Property @{
    Region = $availabilityGroup.Name
    DisplayName = $displayName
    AvailableSkus = $availableSkus
    IsTargetRegion = ($regionNameNormalized -eq $region)
  }
}

if ($regionAvailability.Count -gt 0) {
  $regionAvailability |
    Sort-Object -Property Region |
    Select-Object `
      @{Name="Region";Expression={$_.Region}},
      @{Name="DisplayName";Expression={$_.DisplayName}},
      @{Name="AvailableSkus";Expression={$_.AvailableSkus}} |
    Format-Table -AutoSize
} else {
  Write-Host "No Workflow Standard regional availability data returned for WS1, WS2, or WS3."
}

Write-Host ""
Write-Host ("Target region Workflow Standard availability for " + $region + ":")
$targetAvailability = $regionAvailability | Where-Object { $_.IsTargetRegion -eq $true }

if ($null -ne $targetAvailability) {
  $targetAvailability |
    Select-Object Region, DisplayName, AvailableSkus |
    Format-Table -AutoSize
} else {
  Write-Host ("WARNING: WS1, WS2, and WS3 are not listed as available in " + $region + ".")
}

Write-Host ""
Write-Host "Summary guidance:"
Write-Host "- WS1, WS2, and WS3 are Logic Apps Standard / Workflow Standard App Service plan SKUs."
Write-Host "- The region lists show where each SKU is generally offered."
Write-Host "- If Current is lower than Limit, visible Microsoft.Web quota is available."
Write-Host "- If Current equals Limit, request additional Microsoft.Web quota for the region."
Write-Host "- If the target region is not listed for WS1, WS2, or WS3, choose a supported region or confirm regional support."
Write-Host "- If quota is available and the target region is listed but deployment still fails, the issue may be live regional SKU capacity rather than visible subscription quota."
