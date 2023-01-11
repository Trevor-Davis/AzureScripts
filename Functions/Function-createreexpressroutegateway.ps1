function createexrgateway {

  param (
      $vnet,
      $resourcegroup,
      $exrgwname,
      $region
  )
#get some info   
 $vnetforgateway = Get-AzVirtualNetwork -Name $vnet -ResourceGroupName $resourcegroup -ErrorAction:Ignore
 $vnetforgateway | ConvertTo-Json
 
 $subnet = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnetforgateway -ErrorAction:Ignore
 $subnet | ConvertTo-Json
 
 #create public IP
 $pip = New-AzPublicIpAddress -Name $exrgwipname -ResourceGroupName $resourcegroup -Location $region -AllocationMethod Dynamic -ErrorAction:Ignore
 $pip | ConvertTo-Json
 
 $ipconf = New-AzVirtualNetworkGatewayIpConfig -Name $exrgwipname -Subnet $subnet -PublicIpAddress $pip -ErrorAction:Ignore
 $ipconf | ConvertTo-Json
 
 #create the gateway

Write-Host -ForegroundColor Yellow "
Creating a ExpressRoute Gateway ... this could take 30-40 minutes ..."
$command = New-AzVirtualNetworkGateway -Name $exrgwname -ResourceGroupName $resourcegroup -Location $region -IpConfigurations $ipconf -GatewayType Expressroute -GatewaySku Standard
$command | ConvertTo-Json


$test = Get-AzVirtualNetworkGateway -Name $exrgwname -ResourceGroupName $resourcegroup -ErrorAction Ignore

If($test.count -eq 0){Write-Host -ForegroundColor Red "
ExpressRoute Gateway $exrgwname Failed to Create"
Exit}
If($test.count -eq 1){Write-Host -ForegroundColor Green "
ExpressRoute Gateway $exrgwname Created"}
}