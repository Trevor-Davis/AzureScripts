$ResourceGroupName = "tredavisstorage"
$SnapshotName = "jumpboxsnap"
$sasExpiryDuration = "15000"
$storageAccountName = "tredavisstorage"
$storageAccountKey = "KNTkSNxrB+zAc7i2pg1WiVmY071cqLbM1nHg4XiUT23fjbgyM8Eq2iKm+8sFa5yW3GM0FYsGaM2LrMdtyJcbLw=="
$storageContainerName = "publicshare"
$destinationVHDFileName = "virtualworkloads-jumpbox"

#create the sas token to access snapshot
$sas = Grant-AzSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $SnapshotName  -DurationInSecond $sasExpiryDuration -Access Read

$destinationContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

Start-AzStorageBlobCopy -AbsoluteUri $sas.AccessSAS -DestContainer $storageContainerName -DestContext $destinationContext -DestBlob $destinationVHDFileName

$command = Get-AzStorageBlobCopyState -Context $destinationContext -Blob $destinationVHDFileName -Container $storageContainerName
$status = $command.Status
$bytescopied = $command.BytesCopied
$totalbytes = $command.TotalBytes
$percentcomplete = ($bytescopied / $totalbytes).tostring("P")
write-Host -ForegroundColor Blue "Copying Snapshot $snapshotname to Azure Storage Account $storageAccountName
"
write-Host -ForegroundColor Yellow "$percentcomplete Copied | Job Status: $status | " -NoNewline
write-host -ForegroundColor White "Next Update in 2 Minutes" 
while ($status.Status -ne 'Success') {
  Start-Sleep -Seconds 120
  $command = Get-AzStorageBlobCopyState -Context $destinationContext -Blob $destinationVHDFileName -Container $storageContainerName
  $status = $command.Status
  $bytescopied = $command.BytesCopied
  $totalbytes = $command.TotalBytes
  $percentcomplete = ($bytescopied / $totalbytes).tostring("P")
  write-Host -ForegroundColor Yellow "$percentcomplete Copied | Job Status: $status | " -NoNewline
  write-host -ForegroundColor White "Next Update in 2 Minutes"
}
write-Host -ForegroundColor Green "Current Status: $percentcomplete Copied | Job Status: $status"

https://www.pachehra.com/2019/06/movecopy-snapshot-from-one-region-to.html