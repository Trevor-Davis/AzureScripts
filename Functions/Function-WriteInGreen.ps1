#azure login function
function writeingreen {

  param (
      $messagetowrite 
  )
Write-Host -ForegroundColor Green "$messagetowrite"
Exit-PSHostProcess}

