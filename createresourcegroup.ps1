$filename = "azurelogin-function.ps1"
Invoke-WebRequest -uri "https://raw.githubusercontent.com/Trevor-Davis/AzureScripts/main/Functions/$filename" `
-OutFile $env:TEMP\AVSDeploy\$filename
Clear-Host
. $env:TEMP\AVSDeploy\$filename

if ($global:skipmanualinputs -ne "Yes") {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $sub = [Microsoft.VisualBasic.Interaction]::InputBox('Subscription:', ' ')
    
    Add-Type -AssemblyName Microsoft.VisualBasic
    $region = [Microsoft.VisualBasic.Interaction]::InputBox('Region to Create Resource Group:', ' ')
    
    Add-Type -AssemblyName Microsoft.VisualBasic
    $resourcegroupname = [Microsoft.VisualBasic.Interaction]::InputBox('Resource Group To Create:', ' ')
}


New-AzResourceGroup -Name $resourcegroupname -Location $region

azurelogin -subtoconnect $sub

#References
#https://www.delftstack.com/howto/powershell/powershell-input-box/