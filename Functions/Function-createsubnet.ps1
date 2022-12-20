$Success = 99

function createsubnet {

  param (
      $subnetname,
      $virtualNetwork,
      $subnetaddressprefix,

      $vnetaddressprefix,
      $gatewaysubnetprefix
  )

#Create Subnet

$subnet = @{
  Name = $subnetname
  VirtualNetwork = $virtualNetwork
  AddressPrefix = $subnetaddressprefix
}
$subnetConfig = Add-AzVirtualNetworkSubnetConfig @subnet
$subnetConfig | ConvertTo-Json

$test = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $virtualNetwork -Name $subnetname

if ($test.count -eq 1) {$Success = 1}
if ($test.count -eq 0) {$Success = 0}
}


