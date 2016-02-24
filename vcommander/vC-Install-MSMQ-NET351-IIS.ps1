Import-Module ServerManager

Write-Host "Installing MSMQ-Server"
Add-WindowsFeature MSMQ-Server | Out-Null

Write-Host "Installing .NET 3.5.1 Feature"
Add-WindowsFeature NET-Framework-Core | Out-Null

Write-Host "Installing IIS Role"
Add-WindowsFeature Web-Server | Out-Null