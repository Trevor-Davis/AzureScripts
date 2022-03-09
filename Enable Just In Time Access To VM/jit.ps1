$vmname = "VirtualWorkloads-Jumpbox"
$sub = "3988f2d0-8066-42fa-84f2-5d72f80901da"
$rg = "VirtualWorkloads-AVS"
$myip = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content


function azurelogin {

  param (
      $subtoconnect
  )


  $sublist = @()
  $sublist = Get-AzSubscription
  $checksub = $sublist -match $subtoconnect
  $getazcontext = Get-AzContext
  If ($checksub.Count -eq 1 -and $getazcontext.Subscription.Id -eq $subtoconnect) {" "}
  if ($checksub.Count -eq 1 -and $getazcontext.Subscription.Id -ne $subtoconnect) {Set-AzContext -SubscriptionId $subtoconnect}
  if ($checksub.Count -eq 0) {Connect-AzAccount -Subscription $subtoconnect}

  }

$ErrorActionPreference = "SilentlyContinue"; $WarningPreference = "SilentlyContinue"
azurelogin -subtoconnect $sub
$ErrorActionPreference = "Continue"; $WarningPreference = "Continue"

  $MyResource = Get-AzResource -Id "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$vmname"
  $JitPolicy = (@{
          id    = $MyResource.ResourceId; 
              ports=(@{
       number=3389;
       endTimeUtc=(Get-Date -AsUTC).AddHours(3);
       allowedSourceAddressPrefix=@($myip)})})

       $ActivationVM = @($JitPolicy)
       
       $command = Start-AzJitNetworkAccessPolicy -ResourceGroupName $($MyResource.ResourceGroupName) -Location $MyResource.Location -Name "default" -VirtualMachine $ActivationVM
$commandoutput = $command | ConvertTo-Json

write-Host $commandoutput -ForegroundColor Green