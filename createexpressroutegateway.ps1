#variables
$vnet = $global:exrvnetname
$resourcegroup = $global:exrgwrg
$exrgwipname = $global:exrgwipname
$region = $global:exrgwregion
$exrgwname = $global:exrgwname
$sub = $global:avssub
$tenant = ""
$gatewaysubnetaddressspace = $global:gatewaysubnetaddressspace

#DO NOT MODIFY BELOW THIS LINE #################################################

#Azure Login

$filename = "Function-azurelogin.ps1"
write-host "Downloading" $filename
Invoke-WebRequest -uri "https://raw.githubusercontent.com/Trevor-Davis/AzureScripts/main/Functions/$filename" -OutFile $env:TEMP\$folder\$filename
. $env:TEMP\$filename

if ($tenanttoconnect -ne "") {
  azurelogin -subtoconnect $sub -tenanttoconnect $tenant
}
else {
  azurelogin -subtoconnect $sub 
}

#Execution

#get some info   
$vnetforgateway = Get-AzVirtualNetwork -Name $vnet -ResourceGroupName $resourcegroup -ErrorAction:Ignore
$vnetforgateway | ConvertTo-Json

#Create GatewaySubnet

$test = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnetforgateway -ErrorAction:Ignore
if ($test.count -eq 0) {
Add-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnetforgateway -AddressPrefix $gatewaysubnetaddressspace
$vnetforgateway | Set-AzVirtualNetwork
$vnetforgateway = Get-AzVirtualNetwork -Name $vnet -ResourceGroupName $resourcegroup -ErrorAction:Ignore

}
$subnet = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnetforgateway -ErrorAction:Ignore
$subnet | ConvertTo-Json

#create public IP

$test = Get-AzPublicIpAddress -Name $exrgwipname -ResourceGroupName $resourcegroup -ErrorAction:Ignore
if ($test.count -eq 0) {
$pip = New-AzPublicIpAddress -Name $exrgwipname -ResourceGroupName $resourcegroup -Location $region -AllocationMethod Dynamic -ErrorAction:Ignore
$pip | ConvertTo-Json

$ipconf = New-AzVirtualNetworkGatewayIpConfig -Name $exrgwipname -SubnetId $subnet.Id -PublicIpAddressId $pip.Id -ErrorAction:Ignore
$ipconf | ConvertTo-Json
}
else {
  $ipconf = New-AzVirtualNetworkGatewayIpConfig -Name $exrgwipname -SubnetId $subnet.Id -PublicIpAddressId $test.Id -ErrorAction:Ignore
  $ipconf | ConvertTo-Json
}

#test to see if ExR GW exists
$test = Get-AzVirtualNetworkGateway -ResourceGroupName $resourcegroup -Name $exrgwname -ErrorAction:Ignore

if ($test.count -eq 1){Write-Host -ForegroundColor Blue "
ExpressRoute Gateway $exrgwname Already Exists"
}

if ($test.count -eq 0){

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
