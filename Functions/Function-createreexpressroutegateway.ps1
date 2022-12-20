#azure login function
function createexrgateway {

  param (
      $vnet,
      $resourcegroup,
      $sub,
      $exrgwname,
      $region
  )
#get some info   
 $vnetforgateway = Get-AzVirtualNetwork -Name $vnet -ResourceGroupName $resourcegroup -ErrorAction:Ignore
 $vnetforgateway
 
 $subnet = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnetforgateway -ErrorAction:Ignore
 $subnet
 
 #create public IP
 $pip = New-AzPublicIpAddress -Name $exrgwipname -ResourceGroupName $resourcegroup -Location $region -AllocationMethod Dynamic -ErrorAction:Ignore
 $pip
 
 $ipconf = New-AzVirtualNetworkGatewayIpConfig -Name $exrgwipname -Subnet $subnet -PublicIpAddress $pip -ErrorAction:Ignore
 $ipconf
 
 #create the gateway

Write-Host -ForegroundColor Yellow "
Creating a ExpressRoute Gateway ... this could take 30-40 minutes ..."
$command = New-AzVirtualNetworkGateway -Name $exrgwname -ResourceGroupName $resourcegroup -Location $region -IpConfigurations $ipconf -GatewayType Expressroute -GatewaySku Standard
$command | ConvertTo-Json


$test = Get-AzVirtualNetworkGateway -Name $exrgwname -ResourceGroupName $resourcegroup -ErrorAction Ignore

If($test.count -eq 1){$Success = 1}
If($test.count -eq 0){$Success = 0}

}