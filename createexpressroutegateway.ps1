$filename = "azurelogin-function.ps1"
Invoke-WebRequest -uri "https://raw.githubusercontent.com/Trevor-Davis/AzureScripts/main/Functions/$filename" `
-OutFile $env:TEMP\AVSDeploy\$filename
Clear-Host
. $env:TEMP\AVSDeploy\$filename


if ($buildhol_ps1 -notmatch "Yes" -and $avsdeploy_ps1 -notmatch "Yes"){
  Write-Host "No"
    $sub = "abf039b4-3e19-40ad-a85e-93937bd8a4bc"
    $vnetgwsub = $global:sub
    $vnet = "avs-hol-vnet"
    $vnetrg = "AVS-VMwareExplore-HOL-RG"
    $exrgwrg = $global:vnetrg
    $exrgwregion ="westeurope"
    $exrgwname = "ExRGWforAVSHOL" #the new ExR GW name.
    $exrgwipname = "ExRGWforAVSHOL-IP" #name of the public IP for ExR GW
    $exrgwipconf = "gwipconf" #
}

  azurelogin -subtoconnect $vnetgwsub
    
  $getvirtualnetwork = Get-AzVirtualNetwork -Name $vnet -ResourceGroupName $vnetrg
  $getvirtualnetwork
  
  $setvirtualnetwork = Set-AzVirtualNetwork -VirtualNetwork $vnet
  $setvirtualnetwork
  
  $subnet = Get-AzVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -VirtualNetwork $setvirtualnetwork
  $subnet
  
  $pip = New-AzPublicIpAddress -Name $exrgwipname -ResourceGroupName $exrgwrg -Location $exrgwregion -AllocationMethod Dynamic
  $pip
  if ($pip.ProvisioningState -ne "Succeeded"){Write-Host -ForegroundColor Red "Creation of the Public IP Failed"
  Exit}
  
  $ipconf = New-AzVirtualNetworkGatewayIpConfig -Name $exrgwipconf -Subnet $subnet -PublicIpAddress $pip
  $ipconf
  
  Write-Host -ForegroundColor Yellow "
  Creating a ExpressRoute Gateway ... this could take 30-40 minutes ..."
  $command = New-AzVirtualNetworkGateway -Name $exrgwname -ResourceGroupName $exrgwrg -Location $exrgwregion -IpConfigurations $ipconf -GatewayType Expressroute -GatewaySku Standard
  $command | ConvertTo-Json
  
  $timeStamp = Get-Date -Format "hh:mm"
  $provisioningstate = Get-AzVirtualNetworkGateway -Name $exrgwname -ResourceGroupName $exrgwrg
  $currentprovisioningstate = $provisioningstate.ProvisioningState

  
  If ("Succeeded" -ne $currentprovisioningstate)
  {
Write-Host -ForegroundColor Red "ExpressRoute Gateway Deployment Failed"
Exit
  }
  
  if("Succeeded" -eq $currentprovisioningstate)
  {
    Write-Host -ForegroundColor Green "$timestamp - ExpressRoute Gateway is Deployed"
    
  }
  