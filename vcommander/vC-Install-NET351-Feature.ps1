Import-Module ServerManager

Write-Host "Installing .NET 3.5.1 Feature"
Add-WindowsFeature NET-Framework-Core | Out-Null