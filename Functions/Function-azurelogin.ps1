#azure login function
function azurelogin {

  param (
      $subtoconnect,
      $tenanttoconnect
  )
  $sublist = @()
  $sublist = Get-AzSubscription -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
  $checksub = $sublist -match $subtoconnect
  $getazcontext = Get-AzContext
  If ($checksub.Count -eq 1 -and $getazcontext.Subscription.Id -eq $subtoconnect) {" "}
  if ($checksub.Count -eq 1 -and $getazcontext.Subscription.Id -ne $subtoconnect) {Set-AzContext -SubscriptionId $subtoconnect -WarningAction SilentlyContinue}
  if ($checksub.Count -eq 0) {Connect-AzAccount -Subscription $subtoconnect -TenantId $tenanttoconnect -WarningAction SilentlyContinue}
  }
