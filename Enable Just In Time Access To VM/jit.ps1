$myip = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content
$vmname = "VirtualWorkloads-Jumpbox"
$sub = "3988f2d0-8066-42fa-84f2-5d72f80901da"
$rg = "VirtualWorkloads-AVS"
$region = "westus"

function azurelogin {

  param (
      $subtoconnect
  )
$ErrorActionPreference = "SilentlyContinue"; $WarningPreference = "SilentlyContinue"

$sublist = @()
  $sublist = Get-AzSubscription
  $checksub = $sublist -match $sub
  If ($checksub.Count -eq 1 -and $checksub.id -eq $subtoconnect) {}
  if ($checksub.Count -eq 1 -and $checksub.id -ne $subtoconnect) {Set-AzContext -Subscription $subtoconnect}
  if ($checksub.Count -eq 0) {Connect-AzAccount -Subscription $subtoconnect}
$ErrorActionPreference = "Continue"; $WarningPreference = "Continue"


  }
  
azurelogin -subtoconnect $sub




$JitPolicyVm1 = (@{
    id="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$vmname";
    ports=(@{
       number=3389;
       endTimeUtc=(Get-Date -AsUTC).AddHours(3);
       allowedSourceAddressPrefix=@($myip)})})

       $JitPolicyArr=@($JitPolicyVm1)

       Start-AzJitNetworkAccessPolicy -ResourceId "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Security/locations/$region/jitNetworkAccessPolicies/default" -VirtualMachine $JitPolicyArr



