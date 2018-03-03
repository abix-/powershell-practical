Import-Module ServerManager

Write-Host "Installing Application Server"
Add-WindowsFeature Application-Server,AS-Web-Support,AS-WAS-Support,AS-HTTP-Activation,AS-TCP-Activation,AS-Named-Pipes | Out-Null

Write-Host "Installing IIS Roles 1"
Add-WindowsFeature File-Services,Web-Webserver,Web-Http-Redirect,Web-Asp-Net,Web-Log-Libraries,Web-Http-Tracing,Web-Security,Web-Dyn-Compression,Web-Scripting-Tools | Out-Null

Write-Host "Installing IIS Roles 2"
Add-WindowsFeature Web-Mgmt-Service,Web-Mgmt-Compat,Web-Basic-Auth,Web-Windows-Auth,Web-Digest-Auth,Web-Client-Auth,Web-Cert-Auth,Web-Url-Auth,Web-IP-Security | Out-Null

Write-Host "Installing Windows Feature"
Add-WindowsFeature NET-Framework-Core,MSMQ-Server,RSAT-Web-Server | Out-Null