function createresourcegroup {

  param (
      $resourcegroup,
      $region
  )

#test to see if RG exists
$test = Get-AzResourceGroup -Name $resourcegroup -Location $region 

If($test.count -eq 1){
Write-Host -ForegroundColor Blue "
Resource Group $resourcegroup Already Exists"

}

if ($test.count -eq 0){


write-host -foregroundcolor Yellow "
Creating Resource Group $resourcegroup"
$command = New-AzResourceGroup -Name $resourcegroup -Location $region 
$command | ConvertTo-Json
    
$test = Get-AzResourceGroup -Name $resourcegroup -Location $region 

If($test.count -eq 0){
Write-Host -ForegroundColor Red "
Resource Group $resourcegroup Failed to Create"
Exit
else {
      write-Host -ForegroundColor Green "
Resource Group $resourcegroup Successfully Created"
      }
    }
  }
}