$vnet = "tredavis-vnet"
$resourcegroup = "tredavis"
$addressprefix = "10.2.1.0/24" #Must Be in this format
$subnetname = "AzureBastionSubnet"
$region = "SouthCentral US"
$sub = "1178f22f-6ce4-45e3-bd92-ba89930be5be"



########### DO NOT MODIFY BELOW THIS LINE ##############


#Azure Login

$filename = "Function-azurelogin.ps1"
Invoke-WebRequest -uri "https://raw.githubusercontent.com/Trevor-Davis/AzureScripts/main/Functions/$filename" -OutFile $env:TEMP\$folder\$filename
. $env:TEMP\$filename

if ($tenanttoconnect -ne "") {
  azurelogin -subtoconnect $sub -tenanttoconnect $tenant
}
else {
  azurelogin -subtoconnect $sub 
}


#Execution

$virtualNetwork = Get-AzVirtualNetwork -Name $vnet -ResourceGroupName $resourcegroup
Add-AzVirtualNetworkSubnetConfig -Name $subnetname -VirtualNetwork $virtualNetwork -AddressPrefix $addressprefix
$virtualNetwork | Set-AzVirtualNetwork
$publicip = New-AzPublicIpAddress -ResourceGroupName $resourcegroup -name "bastionpublicip" -location $region -AllocationMethod Static -Sku Standard
New-AzBastion -ResourceGroupName $resourcegroup -Name "$vnet-bastion" -PublicIpAddressRgName $resourcegroup -PublicIpAddressName "bastionpublicip" -VirtualNetworkRgName $resourcegroup -VirtualNetworkName $vnet -Sku "Standard"
