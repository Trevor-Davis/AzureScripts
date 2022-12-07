#Variables
$Sub = "3988f2d0-8066-42fa-84f2-5d72f80901da"


Connect-AzAccount 
Select-AzSubscription -Subscription $Sub
$resourceGroups = Get-AzResourceGroup
foreach ($resourceGroup in $resourceGroups) {
    $ResourceGroupName = $resourceGroup.ResourceGroupName
    $count = (Get-AzResource | Where-Object{ $_.ResourceGroupName -match $ResourceGroupName }).Count
    if ($count -eq 0) {
        Write-Host "$ResourceGroupName has no resources. Deleting ... "
        Remove-AzResourceGroup -Name $ResourceGroupName -Force:$true

}
}