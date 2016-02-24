<#
.SYNOPSIS
Deploy-Service.ps1 deploys IIS and Windows services to a list of servers which can be provided with a couple different methods.

.DESCRIPTION
Deploy-Service.ps1 deploys IIS services using appcmd.exe and Windows services using New-Service via Invoke-VMScript to allow execution on remote systems behind firewalls. IIS services are deployed by importing XML files of previously exported sites and apppools. Windows services are created fresh on every run. Both services can be cleanly installed by specifying the -clean switch as well as the -service parameter.

.PARAMETER servers
The name of a VM in vCenter or a text file containing the names of multiple VMs. If this parameter is used, the $csv parameter is ignored.

.EXAMPLE
Deploy an IIS service to DEV-S01-WEB001
.\Deploy-Service.ps1 -servers DEV-S01-WEB001 -site mysite.xml -apppool mypool.xml

.EXAMPLE
Do a clean deployment of an IIS service to DEV-S01-WEB001. This deletes the site and apppool first, then deploys it again.
.\Deploy-Service.ps1 -servers DEV-S01-WEB001 -site mysite.xml -apppool mypool.xml -clean -service "My IIS Service"

.EXAMPLE
Deploy a Windows service to DEV-S01-WEB001
.\Deploy-Service.ps1 -servers DEV-S01-WEB001 
#>

[cmdletbinding()]
Param (
    [Parameter(Mandatory=$true)][string]$service,
    [Parameter(ParameterSetName="Servers",Mandatory=$true)]
    [Parameter(ParameterSetName="IIS",Mandatory=$true)]
    [Parameter(ParameterSetName="Windows",Mandatory=$true)]$servers,
    [Parameter(ParameterSetName="TCS")]$datacenter,
    [Parameter(ParameterSetName="TCS")]$stack,
    [Parameter(ParameterSetName="TCS")]$role,
    [Parameter(ParameterSetName="TCS")]$range,
    [Parameter(ParameterSetName="IIS")]$PoolXML,
    [Parameter(ParameterSetName="IIS")]$SiteXML,
    [Parameter(ParameterSetName="Windows")]$BinaryPath,
    [Parameter(ParameterSetName="Windows")]$StartMode,
    $servicepath = "C:\Scripts\Services",
    [switch]$clean,
    [switch]$async,
    $tcs_servers = "tcs_servers.csv",
    $tcs_services = "tcs_services.csv",
    $tcs_services_config = "tcs_services_config.csv"
)

function loadSettings() {
    try {
        $s = import-csv $tcs_services | ?{ $_.Service -eq $service }
        $t = import-csv $tcs_services_config | ?{ $_.Service -eq $service }
        Write-Verbose $s
        Write-Verbose $t
        if($s.count -gt 1 -or $t.count -gt 1) { Write-Host "More than one service found. Aborting"; Exit }
    }
    catch {
        if($PSCmdlet.ParameterSetName -eq "TCS") {
            $s = New-Object PSObject -Property @{
                Service = $service
                Servers = ".*"
                Role = $role
                Path = ""
                Type = $type
            }
            if($type -eq "Windows") {
                $t = New-Object PSObject -Property @{
                    Service = $service
                    BinaryPath = $binarypath
                    StartMode = $startmode
                    Type = $type
                }
            } elseif($type -eq "IIS") {
                $t = New-Object PSObject -Property @{
                    Service = $service
                    PoolXML = $poolxml
                    SiteXML = $sitexml
                    Type = $type
                }
            }
        } elseif($PSCmdlet.ParameterSetName -eq "IIS" -or $PSCmdlet.ParameterSetName -eq "Windows") {
            $s = New-Object PSObject -Property @{
                Service = $service
                Servers = ""
                Role = ""
                Path = ""
            }
            if($PSCmdlet.ParameterSetName -eq "IIS") {
                $t = New-Object PSObject -Property @{
                    Service = $service
                    PoolXML = $poolxml
                    SiteXML = $sitexml
                    Type = $PSCmdlet.ParameterSetName
                }

            } elseif($PSCmdlet.ParameterSetName -eq "Windows") {
                $t = New-Object PSObject -Property @{
                    Service = $service
                    BinaryPath = $binarypath
                    StartMode = $startmode
                    Type = $PSCmdlet.ParameterSetName
                }
            }
        }  else { Write-Host "Service not recognized. We will respond on the basis of your support entitlement."; Exit }
    }
    return $s,$t
}

function getServers($_settings) {
    $destinations = @()
    if($PSCmdlet.ParameterSetName -eq "TCS") {
        Write-Verbose "TCS Mode"
        $s = Import-Csv $tcs_servers
        Write-Verbose "$($s.count) servers found in TCS"
        $allservers = $s | ?{$_.name -match $_settings.servers -and $_.role -eq $_settings.role} | sort Name
        Write-Verbose "Found $($allservers.count) TCS servers across all environments"     
        if($stack) { foreach($_s in $stack) { $destinations += ($allservers | ?{$_.stack -eq "$_s"} | select -ExpandProperty Name | sort) }
        } elseif($datacenter) { foreach($_d in $datacenter) { $destinations += ($allservers | ?{$_.datacenter -eq "$_d"} | select -ExpandProperty Name | sort) }  }
        else { Write-Host "You must specify a -stack or -datacenter"; Exit }
    } elseif($PSCmdlet.ParameterSetName -eq "Servers" -or $PSCmdlet.ParameterSetName -eq "IIS" -or $PSCmdlet.ParameterSetName -eq "Windows") {
        if($servers.EndsWith(".txt")) { $destinations = gc $servers }
        else { $destinations = $servers }
    }
    if($destinations.count -eq 0) { Write-Host "No destinations found. Ask Al how to use me."; Exit }
    return $destinations
}

function askConfirmation($_settings,$_config,$servers,$servicecredential) {
    Clear-Host
    Write-Host "Service:`t$($_settings.service)"
    Write-Host "Service Type:`t$($_config.type)"
    if($_config.type -eq "IIS") {
        Write-Host "Site:`t`t$($_config.sitexml)"
        Write-Host "AppPool:`t$($_config.poolxml)"
    } elseif($_config.type -eq "Windows") {
        Write-Host "BinaryPath:`t$($_config.binarypath)"
        Write-Host "StartMode:`t$($_config.StartMode)"
        Write-Host "Credential:`t$($servicecredential.username)"
    }
    if($datacenter) { Write-Host "Datacenter:`t$datacenter"
    } elseif($stack) { Write-Host "Stack:`t`t$($stack.ToUpper())" }
    if($range) { Write-Host "Range:`t`t$range" }
    Write-Host "destinations, install, exit"
    $option = Read-Host 
    switch -regex ($option) {
        "destinations$" { $servers; Pause; askConfirmation $_settings $_config $servers $servicecredential }
        "install$" { }
        "exit$" { Exit }
        default { askConfirmation $_settings $_config $servers $servicecredential }
    }
}

Write-Verbose $PSCmdlet.ParameterSetName
$service_settings,$service_config = loadSettings
$servers = getServers $service_settings
Connect-VIServer jaxf-vc101.domain.local | Out-Null

#vCenter connection test
try { $allvms = get-view -viewtype virtualmachine -property Name -ErrorAction STOP | select -expand Name | sort }
catch { Write-Host "Failed to query vCenter. Connect to vCenter and try again."; Exit }

#IIS deployment pre-validation
if($type -eq "IIS") {
    try { Get-Content "$servicepath\$($service_config.poolxml)" -ErrorAction STOP | Out-Null }
    catch { Write-Host "$servicepath\$($service_config.poolxml) does not exist"; Exit }
    try { Get-Content "$servicepath\$($service_config.sitexml)" -ErrorAction STOP | Out-Null }
    catch { Write-Host "$servicepath\$($service_config.sitexml) does not exist"; Exit }
    if($clean) { if([string]::IsNullOrEmpty($service)) { Write-Host "You are attempting to use -clean without -service. Aborting."; Exit } }
}

#Main execution
$servicecredential = Get-Credential -Message "Service account for $service"
askConfirmation $service_settings $service_config $servers $servicecredential
$cred = get-Credential -Message "Local admin on the servers"
$i = 0 
foreach($server in $servers) {
    $i++
    Write-Progress -Activity "Deploying service to $server [$i/$($servers.count)]" -Status " " -PercentComplete (($i/$servers.count)*100)
    if($allvms -notcontains $server) { Write-Host "No VM found named $server. Skipping."; Continue }
    if($service_config.type -eq "IIS") {
        if($servicecredential.username -like "*@domain.local") { $username = "p10\" + $servicecredential.username.split("@")[0] }
        else { $username = $servicecredential.username }
        Copy-VMGuestFile -Source "$servicepath\$($service_config.poolxml)" -Destination C:\Windows\Temp -VM $server -LocalToGuest -GuestCredential $cred
        Copy-VMGuestFile -Source "$servicepath\$($service_config.sitexml)" -Destination C:\Windows\Temp -VM $server -LocalToGuest -GuestCredential $cred
        Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "Configuring IIS" -PercentComplete (($i/$servers.count)*100)
        $script = @"
        C:\Windows\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe -ga $username
        C:\Windows\system32\inetsrv\appcmd.exe add apppool /in < "C:\Windows\Temp\$($service_config.poolxml)"
        C:\Windows\system32\inetsrv\appcmd.exe add site /in < "C:\Windows\Temp\$($service_config.sitexml)"
        DEL C:\Windows\Temp\$($service_config.poolxml)
        DEL C:\Windows\Temp\$($service_config.sitexml)
"@
        if($clean) {
            $cleanscript = @"
            C:\windows\system32\inetsrv\appcmd.exe delete apppool "$($service_settings.service)"
            C:\Windows\system32\inetsrv\appcmd.exe delete site "$($service_settings.service)"
"@
            $script = $cleanscript + "`n" + $script
        }
        if($async) { Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat -RunAsync } 
        else { Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat }
    }
    elseif($service_config.type -eq "Windows") {      
        $script = @"
        C:\Windows\system32\ntrights.exe +r SeServiceLogonRight -u $($servicecredential.username)
        sc.exe create "$($service_settings.service)" binPath= "$($service_config.BinaryPath)" start= "$($service_config.StartMode)" obj= "$($servicecredential.username)" password= $($servicecredential.GetNetworkCredential().Password)        
"@
        if($clean) {
            $cleanscript = @"
            sc.exe stop "$($service_settings.service)"
            ping -n 3 127.0.0.1 >nul
            sc.exe delete "$($service_settings.service)"
"@
            $script = $cleanscript + "`n" + $script
        }
        Copy-VMGuestFile -Source "ntrights.exe" -Destination C:\Windows\system32 -VM $server -LocalToGuest -GuestCredential $cred
        if($async) { Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Powershell -RunAsync } 
        else { Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat }
    }
}