Import-Module ServerManager

Write-Host "Installing MSMQ-Server"
Add-WindowsFeature MSMQ-Server | Out-Null