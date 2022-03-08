$myip = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content
$vmname = "VirtualWorkloads-Jumpbox"
$sub = "3988f2d0-8066-42fa-84f2-5d72f80901da"
$rg = "VirtualWorkloads-AVS"
$region = "westus"


$JitPolicyVm1 = (@{
    id="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$vmname";
    ports=(@{
       number=3389;
       endTimeUtc=(Get-Date -AsUTC).AddHours(3);
       allowedSourceAddressPrefix=@($myip)})})

       $JitPolicyArr=@($JitPolicyVm1)

       Start-AzJitNetworkAccessPolicy -ResourceId "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Security/locations/$region/jitNetworkAccessPolicies/default" -VirtualMachine $JitPolicyArr



