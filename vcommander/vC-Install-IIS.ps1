Import-Module ServerManager

Write-Host "Installing IIS Role"
Add-WindowsFeature Web-Server | Out-Null