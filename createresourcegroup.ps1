#Variables
$rgname = $global:avsrgname
$regionfordeployment = $global:regionfordeployment
$sub = $global:avssub
$tenant = ""



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
$test = Get-AzResourceGroup -Name $rgname -ErrorAction:Ignore

if ($test.count -eq 1) {
write-Host -ForegroundColor Blue "
Resource Group $rgname Already Exists"   
}
  
if ($test.count -eq 0) {
write-host -foregroundcolor Yellow "
Creating Resource Group $rgname"
$command = New-AzResourceGroup -Name $rgname -Location $regionfordeployment
$command | ConvertTo-Json

$test = Get-AzResourceGroup -Name $rgname -ErrorAction:Ignore
If($test.count -eq 0){
Write-Host -ForegroundColor Red "
Resource Group $rgname Failed to Create"
Exit
}
else {
  write-Host -ForegroundColor Green "
Resource Group $rgname Successfully Created"
  }
}

Remove-Item $env:TEMP\$filename



