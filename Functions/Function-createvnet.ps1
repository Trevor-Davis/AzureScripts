$Success = 99

function createvnet {

  param (
      $vnetname,
      $resourcegroup,
      $region,
      $vnetaddressprefix,
      $gatewaysubnetprefix
  )

#Create vNet
write-host -foregroundcolor Yellow "
Creating Virtual Network $vnetname"

$vnet = @{
  Name = $vnetname
  ResourceGroupName = $resourcegroup
  Location = $region
  AddressPrefix = $vnetaddressprefix
}
$virtualNetwork = New-AzVirtualNetwork @vnet 
$virtualNetwork | ConvertTo-Json

$test = Get-AzVirtualNetwork -Name $vnetname -ResourceGroupName $resourcegroup -ErrorAction:Ignore

if ($test.count -eq 1) {$Success = 1}
if ($test.count -eq 0) {$Success = 0}

}