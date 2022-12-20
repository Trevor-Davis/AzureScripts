#azure login function
function createresourcegroup {

  param (
      $resourcegroup,
      $region,
      $sub
  )
  $test = Get-AzResourceGroup -Name $resourcegroup  -Location $region -ErrorAction:Ignore

  if ($test.count -eq 1) {
    write-Host -ForegroundColor Blue "
  $resourcegroup Already Exists ... Skipping to Next Step"   
    }
      
    if ($test.count -eq 0) {
    write-host -foregroundcolor Yellow "
  Creating Resource Group $resourcegroup"
    $command = New-AzResourceGroup -Name $resourcegroup -Location $region 
    $command | ConvertTo-Json
    
    $test = Get-AzResourceGroup -Name $resourcegroup -ErrorAction:Ignore
    If($test.count -eq 0){
    Write-Host -ForegroundColor Red "
  Resource Group $resourcegroup Failed to Create"
    Exit
    }
    else {
      write-Host -ForegroundColor Green "
  Resource Group $resourcegroup Successfully Created"
      }
    }
  }