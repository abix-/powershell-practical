function Get-LinuxDiskUsage {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)][string]$VM,
        [Parameter(Mandatory=$true)][string]$GuestUser,
        [string]$GuestPassword
    )

    try { Get-VM $VM -ErrorAction Stop | Out-null }
    catch { Write-Host "[$VM] VM not found"; Return "Error" }

    if(!$GuestPassword) {
        $GuestPassword = Get-SecureStringCredentials -Username $GuestUser -PlainPassword
    }

    try { 
        $results = Invoke-VMScript -VM $VM -ScriptText "df --portability" -GuestUser $GuestUser -GuestPassword $GuestPassword -ErrorAction Stop -ToolsWaitSecs 10 | Select-Object -ExpandProperty ScriptOutput
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red; Return
    }

    return ConvertFrom-LinuxDfOutput $results
}

function Get-WindowsDiskUsage {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)][string]$VM,
        [string]$GuestUser,
        [string]$GuestPassword
    )

    try { Get-VM $VM -ErrorAction Stop | Out-null }
    catch { Write-Host "[$VM] VM not found"; Return "Error" }

    if($GuestUser -and $GuestPassword) {
        $secpasswd = ConvertTo-SecureString $GuestPassword -AsPlainText -Force
        $GuestCredential = New-Object System.Management.Automation.PSCredential ($GuestUser, $secpasswd)
    } elseif($GuestUser -and !$GuestPassword) {
        $GuestCredential = Get-SecureStringCredentials -Username $GuestUser
    } else {
        $GuestCredential = Get-Credential -Message "Guest credentials for $VM"
    }

    $vmoutput = Invoke-VMScript -ScriptText '(Get-WMIObject -class win32_logicaldisk | ConvertTo-CSV)' `
                -ScriptType Powershell -VM $vm -GuestCredential $GuestCredential

    if($vmoutput.ExitCode -eq 0) {
        $disks = $vmoutput.ScriptOutput | ConvertFrom-Csv | Select-Object @{N="MountedOn";E={$_.DeviceID}},
                                                                @{N="CapacityMB";E={ [system.math]::Round($_.Size/1024/1024,1) }},
                                                                @{N="AvailableMB";E={ [system.math]::Round($_.Freespace/1024/1024,1) }},
                                                                @{N="PercentUsed";E={ [system.math]::Round((($_.size-$_.Freespace)/$_.Size)*100,1) }}
        return $disks
    } else {
        Write-Host "[$($vm.name)] Invoke-VMScript returned Exit Code $($vmoutput.ExitCode)"; Return
    }
}

function Get-LinuxServices {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)][string]$VM,
        [Parameter(Mandatory=$true)][string]$GuestUser,
        [string]$GuestPassword,
        [string]$method
    )

    try { Get-VM $VM -ErrorAction Stop | Out-null }
    catch { Write-Host "[$VM] VM not found"; Return "Error" }

    switch($method) {
        "chkconfig" { $scriptText = "cat /tmp/service-status.txt" }
        "systemctl" { $scriptText = "systemctl --type=service --all" }
        "service-status" { $scriptText = "cat /tmp/service-status.txt" }
        default { Write-Host "Unknown method"; Return }
    }

    if($GuestUser -and !$GuestPassword) {
        $GuestPassword = Get-SecureStringCredentials -Username $GuestUser -PlainPassword
    }

    try {
        $results = Invoke-VMScript -VM $VM -ScriptText $scriptText -GuestUser $GuestUser -GuestPassword $GuestPassword -ErrorAction Stop -ToolsWaitSecs 10 | Select-Object -ExpandProperty ScriptOutput
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Return $_.Exception.Message
    }

    switch($method) {
        "chkconfig" { return ConvertFrom-LinuxChkconfigOutput $results }
        "systemctl" { return ConvertFrom-LinuxSystemctlOutput $results }
        "service-status" { return ConvertFrom-LinuxServiceStatusOutput $results }
    }
}

function Get-WindowsServices {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)]$VM,
        [string]$GuestUser,
        [string]$GuestPassword
    )

    try { Get-VM $VM -ErrorAction Stop | Out-null }
    catch { Write-Host "[$VM] VM not found"; Return "Error" }

    if($GuestUser -and $GuestPassword) {
        $secpasswd = ConvertTo-SecureString $GuestPassword -AsPlainText -Force
        $GuestCredential = New-Object System.Management.Automation.PSCredential ($GuestUser, $secpasswd)
    } elseif($GuestUser -and !$GuestPassword) {
        $GuestCredential = Get-SecureStringCredentials -Username $GuestUser
    } else {
        $GuestCredential = Get-Credential -Message "Guest credentials for $VM"
    }

    $vmoutput = Invoke-VMScript -ScriptText '(Get-Service | ConvertTo-CSV)' `
                -ScriptType Powershell -VM $vm -GuestCredential $GuestCredential

    if($vmoutput.ExitCode -eq 0) {
        $services = $vmoutput.ScriptOutput | ConvertFrom-Csv | select-Object `
                        @{N="Service";E={$_.Name}},@{N="Description";E={$_.DisplayName}},Status
        return $services
    } else {
        Write-Host "[$($vm.name)] Invoke-VMScript returned Exit Code of $($vmoutput.ExitCode)"
        Return
    }
}

function Invoke-DiskMonitoring {
    [cmdletbinding()]
    param (
        [string]$VM,
        $DiskMonitors,
        [string]$Method,
        [Parameter(Mandatory=$true)][string]$LinuxUser,
        [Parameter(Mandatory=$true)][string]$LinuxPassword,
        [Parameter(Mandatory=$true)][string]$WindowsUser,
        [Parameter(Mandatory=$true)][string]$WindowsPassword
    )

    #Get all the monitors for this VM
    $vmMonitors = @($DiskMonitors | ?{$_.VM -eq $VM})
    if($vmMonitors.Count -eq 0) { return }

    Write-Host "[$VM] Getting Disk Usage"
    switch($method) {
        "linux" {  $vmDiskUsage = Get-LinuxDiskUsage -VM $VM -GuestUser $LinuxUser -GuestPassword $LinuxPassword }
        "windows" { $vmDiskUsage = Get-WindowsDiskUsage -VM $VM -GuestUser $WindowsUser -GuestPassword $WindowsPassword }
        default { Write-Host "$Method is not a known method"; Return }
    }
    
    $results = @()
    foreach($_m in $vmMonitors) {
        $currentDisk = @($vmDiskUsage | ?{$_.MountedOn -eq $_m.Mount})
        if($currentDisk.count -gt 0) {
            #Review the Available MB
            if($currentDisk.AvailableMB -le $_m.AlertAvailableMB) {
                Write-Host "[$VM] Disk '$($_m.Mount)' has $($currentDisk.AvailableMB)MB available. Below threshold $($_m.AlertAvailableMB)MB" -ForegroundColor Red
                $status = "LowAvailableMB"
            } elseif($currentDisk.PercentUsed -ge $_m.AlertPercentUsed) {
                Write-Host "[$VM] Disk '$($_m.Mount)' is $($currentDisk.PercentUsed)% used. Above threshold $($_m.AlertPercentUsed)%" -ForegroundColor Red
                $status = "HighPercentUsed"
            } elseif($currentDisk.AvailableMB -gt $_m.AlertAvailableMB -and $currentDisk.PercentUsed -lt $_m.AlertPercentUsed) {
                Write-Host "[$VM] Disk '$($_m.Mount)' has $($currentDisk.AvailableMB)MB available. Above threshold $($_m.AlertAvailableMB)MB" -ForegroundColor Green
                Write-Host "[$VM] Disk '$($_m.Mount)' is $($currentDisk.PercentUsed)% used. Below threshold $($_m.AlertPercentUsed)%" -ForegroundColor Green
                $status = "OK"
            } else {
                $status = "Unknown"
            }

            $results += [pscustomobject][ordered]@{
                VM = $VM
                Mount = $_m.Mount
                Status = $status
                CapacityMB = $currentDisk.CapacityMB
                AvailableMB = $currentDisk.AvailableMB
                AlertAvailableMB = $_m.AlertAvailableMB
                PercentUsed = $currentDisk.PercentUsed
                AlertPercentUsed = $_m.AlertPercentUsed
            }
        } else {
            Write-Host "[$VM] Disk $($_m.Mount) not found" -ForegroundColor Red
            $results += [pscustomobject][ordered]@{
                VM = $VM
                Mount = $_m.Mount
                Status= "Error"
                CapacityMB = "Error"
                AvailableMB = "Error"
                AlertAvailableMB = $_m.AlertAvailableMB
                PercentUsed = "Error"
                AlertPercentUsed = $_m.AlertPercentUsed
            }
        } 
    }
    return $results
}

function Invoke-ServiceMonitoring {
    [cmdletbinding()]
    param (
        [string]$VM,
        $ServiceMonitors,
        [string]$Method,
        [Parameter(Mandatory=$true)][string]$LinuxUser,
        [Parameter(Mandatory=$true)][string]$LinuxPassword,
        [Parameter(Mandatory=$true)][string]$WindowsUser,
        [Parameter(Mandatory=$true)][string]$WindowsPassword
    )

    $vmMonitors = $ServiceMonitors | ?{$_.VM -eq $VM}
    if($vmMonitors.Count -eq 0) { return }

    Write-Host "[$VM] Getting Services"
    switch($method) {
        "get-service" { $vmServices = Get-WindowsServices -VM $VM -GuestUser $WindowsUser -GuestPassword $WindowsPassword }
        default { $vmServices = Get-LinuxServices -VM $VM -method $Method -GuestUser $LinuxUser -GuestPassword $LinuxPassword }
    }
 
    $results = @()
    foreach($_m in $vmMonitors) {
        $currentService = @($vmServices | ?{$_.Service -eq $_m.Service})
        if($currentService.count -eq 0) {
            $currentService = @($vmServices | ?{$_.Service -eq $_m.Description})
        }

        if($currentService.count -gt 0) {
            if($currentService.count -gt 1) {
                $currentService = $currentService[0]
            }
            if($currentService.Status -eq "Running") {
                Write-Host "[$VM] '$($_m.Service)' for '$($_m.Description) Service' is $($currentService.Status)" -ForegroundColor Green
            } else {
                Write-Host "[$VM] '$($_m.Service)' for '$($_m.Description) Service' is $($currentService.Status)" -ForegroundColor Red
            }

            $results += [pscustomobject][ordered]@{
                VM = $VM
                Service = $_m.Service
                Description = $_m.Description
                Status = $currentService.Status
            }
        } else {
            Write-Host "[$VM] Service $($_m.Service) not found" -ForegroundColor Red
            $results += [pscustomobject][ordered]@{
                VM = $VM
                Service = $_m.Service
                Description = $_m.Description
                Status = "Error"
            }
        }
    }  
    return $results
}

function ConvertFrom-LinuxChkconfigOutput {
    param([string] $Text)
    [regex] $LineRegex = '^(.+?)\s+(.+)$'
    $Lines = @($Text -split '[\r\n]+')
    foreach ($Line in $Lines) {
        [regex]::Matches($Line, $LineRegex) | foreach {
            [pscustomobject][ordered]@{
                Service = $_.Groups[1].Value
                Status = $_.Groups[2].Value
            }
        }
    }
}

function ConvertFrom-LinuxSystemctlOutput {
    param([string] $Text)
    [regex] $LineRegex = '^\s+(.+?)\s+([^\s]+)\s+(active|inactive|failed)\s+([^\s]+)\s+(.+)$'
    $Lines = @($Text -split '[\r\n]+')
    foreach ($Line in $Lines) {
        [regex]::Matches($Line, $LineRegex) | foreach {
            $statusRegex = $_.Groups[4].Value
            switch($statusRegex) {
                "running" { $status = "Running" }
                "dead" { $status = "Stopped" }
                default { $status = $statusRegex }
            }
            
            [pscustomobject][ordered]@{
                Service = $_.Groups[1].Value
                Load = $_.Groups[2].Value
                Active = $_.Groups[3].Value
                Status = $status
                Description = $_.Groups[5].Value
            }
        }
    }
}

function ConvertFrom-LinuxDfOutput {
    <#
    http://www.powershelladmin.com/wiki/Get_Linux_disk_space_report_in_PowerShell
    #>
    param([string] $Text)
    [regex] $HeaderRegex = '\s*Filesystem\s+1024-blocks\s+Used\s+Available\s+Capacity\s+Mounted\s*on\s*'
    [regex] $LineRegex = '^\s*(.+?)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+\s*%)\s+(.+)\s*$'
    $Lines = @($Text -split '[\r\n]+')
    if ($Lines[0] -match $HeaderRegex) {
        foreach ($Line in ($Lines | Select -Skip 1)) {
            [regex]::Matches($Line, $LineRegex) | foreach {
                [pscustomobject][ordered]@{
                    Filesystem = $_.Groups[1].Value
                    CapacityMB = [decimal] ("{0:N1}" -f ($_.Groups[2].Value/1024))
                    UsedMB = [decimal] ("{0:N1}" -f ($_.Groups[3].Value/1024))
                    AvailableMB = [decimal] ("{0:N1}" -f ($_.Groups[4].Value/1024))
                    PercentUsed = [decimal] ($_.Groups[5].Value -replace '\D')
                    MountedOn = $_.Groups[6].Value
                }
            }
        }
    } else {
        Write-Warning -Message "Error in output. Failed to recognize headers from 'df --portability' output."
    }
}

function ConvertFrom-LinuxServiceStatusOutput {
    [cmdletbinding()]
    param([string] $Text)   
    $Lines = @($Text -split '[\r\n]+')

    #Checking for httpd2: ..unused
    #Checking for appliance management service:..running
    #Checking for UPS monitoring service..unused
    #Checking for service arpd ..unused
    #Checking for service cgconfig..running
    #Checking for service D-Bus daemon..running
    #Checking for ISC DHCPv4 4.x Server: ..unused
    [regex] $LineRegex1 = '^Checking for(?<not_needed> service)? (?<service>[^:]+)(:)?(\s)?\.\.(?<status>.+)$'
    
    #VMware Component Manager is running: PID:5916, Wrapper:STARTED, Java:STARTED
    #VMware Message Bus Config Service is not running.
    #VMware HTTP Reverse Proxy is running.
    #VMware ESXi dump collector is running
    #syslog is running, PID: 7115
    #pg_ctl: server is running (PID: 7223)
    [regex] $LineRegex2 = '^(?<service>[^\(]+)(?<crud>.+)? is (?<status>running|not running)(?<not_needed>.+)?$'
  
    $results = @()
    foreach ($Line in $Lines) {
        [regex]::Matches($Line, $LineRegex1) | foreach {
            
            $statusRegex = $_.Groups['status'].Value
            switch($statusRegex) {
               "running" { $status = "Running" }
               "unused" { $status = "Stopped" }
               default { $status = $statusRegex }
            }

            $results += [pscustomobject][ordered]@{
                Service = ($_.Groups['service'].Value).Trim()
                Status = $status
            }
        }

        [regex]::Matches($Line, $LineRegex2) | foreach {
            $statusRegex = $_.Groups['status'].Value
            switch($statusRegex) {
               "running" { $status = "Running" }
               "not running" { $status = "Stopped" }
               default { $status = $statusRegex }
            }

            $results += [pscustomobject][ordered]@{
                Service = ($_.Groups['service'].Value).Trim()
                Status = $status
            }
        }
    }
    Write-Output $results
}

function New-ApplianceHealthReport {
    [cmdletbinding()]
    param (
        [string]$ReportPath = "\\path\to\file",
        $DiskUsageData,
        $ServiceData,
        $WebClientData,
        $DSCData
    )

    $DiskUsageData = $DiskUsageData | Sort-Object PercentUsed -Descending

    #Start the report
    $rpt = @()
    $rpt += Get-HTMLOpenPage -TitleText "VMware Appliance Health" -LeftLogoName Corporate -RightLogoName Alternate
    
    #Define the tabs
    $tabNames = @("Disk Usage","Services","SSH","Web Client","Datastore Clusters")
    $rpt += Get-HTMLTabHeader -TabNames $tabNames

    #Create 'Disk Usage' tab
    $DiskUsageData = $DiskUsageData | Sort-Object -Property AvailableMB
    $rpt += Get-HTMLTabContentOpen -TabName "Disk Usage" -TabHeading $null
        $red = '$this.Status -ne "Ok"'
        $green = '$this.Status -eq "Ok"'
        $coloredDiskUsage = Set-TableRowColor -ArrayOfObjects $DiskUsageData -Red $red -green $green
        $rpt += Get-HTMLContentTable -ArrayOfObjects $coloredDiskUsage
    $rpt += Get-HTMLTabContentClose

    #Create 'Services' tab
    $MostServiceData = $ServiceData | ?{$_.Service -notlike "*ssh*"} | Sort-Object -Property Status
    $rpt += Get-HTMLTabContentOpen -TabName "Services" -TabHeading $null
        $red = '$this.Status -ne "Running"'
        $green = '$this.Status -eq "Running"'
        $coloredServices = Set-TableRowColor -ArrayOfObjects $MostServiceData -Red $red -Green $green
        $rpt += Get-HTMLContentTable -ArrayOfObjects $coloredServices
    $rpt += Get-HTMLTabContentClose

    #Create 'SSH' tab
    $SSHServiceData = $ServiceData | ?{$_.Service -like "*ssh*"} | Sort-Object -Property Status
    $rpt += Get-HTMLTabContentOpen -TabName "SSH" -TabHeading $null
        $red = '$this.Status -ne "Stopped"'
        $green = '$this.Status -eq "Stopped"'
        $coloredSSHServices = Set-TableRowColor -ArrayOfObjects $SSHServiceData -Red $red -Green $green
        $rpt += Get-HTMLContentTable -ArrayOfObjects $coloredSSHServices
    $rpt += Get-HTMLTabContentClose

    #Create 'Web Client' tab
    $rpt += Get-HTMLTabContentOpen -TabName "Web Client" -TabHeading $null
        $red = '$this.Status -ne "OK"'
        $green = '$this.Status -eq "OK"'
        $coloredWebClient = Set-TableRowColor -ArrayOfObjects $WebClientData -Red $red -Green $green
        $rpt += Get-HTMLContentTable -ArrayOfObjects $coloredWebClient
    $rpt += Get-HTMLTabContentClose

    #Create 'Datastore Clusters' tab
    $rpt += Get-HTMLTabContentOpen -TabName "Datastore Clusters" -TabHeading $null
        $rpt += Get-HTMLContentTable -ArrayOfObjects $DSCData
        $rpt += Get-HTMLContentOpen -HeaderText "Glossary"
        $rpt += Get-HTMLContentText -Heading "CapacityGB" -Detail "Total capacity"
        $rpt += Get-HTMLContentText -Heading "FreeSpaceGB" -Detail "Free space"
        $rpt += Get-HTMLContentText -Heading "AvailableGB" -Detail "Available capacity while reserving 20% on each datastore for Avamar backups"
        $rpt += Get-HTMLContentClose
    $rpt += Get-HTMLTabContentClose

    #Close the report
    $rpt += Get-HTMLClosePage

    #Export the report
    $reportName = "ApplianceHealth"
    $reportName += "_$(Get-Date -Format yyyyMMdd_HHmmss)"
    return Save-HTMLReport -ReportContent $rpt -ReportPath $ReportPath -ReportName $reportName
}

function Start-ApplianceHealthReport{
    [cmdletbinding()]
    param (
        [string]$GuestUser = "user",
        [string]$GuestPassword,
        [string]$ServiceAccount,
        [string]$ServicePassword,
        [string]$MonitorsFile = "$PSScriptRoot\vmware-monitors.xlsx",
        [string]$DiskFile = "$PSScriptRoot\disk-usage.csv",
        [string]$ServiceFile = "$PSScriptRoot\service-status.csv",
        [string]$WebClientFile = "$PSScriptRoot\web-client.csv",
        [string]$DSCFile = "$PSScriptRoot\dsc-capacity.csv"
    )

    #Steps
    #Per Disk
    #7 steps: get disk data
    #Per VM
    #7 steps: get service data
    #Per Web Client
    #2 steps: test web client
    #+
    #15 steps: assemble report

    #Import required modules
    if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) { . “D:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” }
    if ( !(Get-Module -Name ImportExcel -ErrorAction SilentlyContinue) ) { Import-Module "C:\Program Files (x86)\WindowsPowerShell\Modules\ImportExcel\ImportExcel.psm1" }
    if ( !(Get-Module -Name ReportHTML -ErrorAction SilentlyContinue) ) { Import-Module ReportHTML -ErrorAction SilentlyContinue; Import-Module "C:\Program Files (x86)\WindowsPowerShell\Modules\ReportHTML\1.3.0.7\ReportHTML.psm1" -ErrorAction SilentlyContinue }

    #Import Disk and Service Monitors from XLSX
    $VMs = Import-Excel $monitorsFile -WorkSheetname VM
    $diskMonitors = Import-Excel $monitorsFile -WorkSheetname Disk
    $serviceMonitors = Import-Excel $monitorsFile -WorkSheetname Service

    #Filter monitors for site
    if($env:computername -eq "VMName") {
        #Connect to vCenters
        Connect-VIServer -Server VMName -User $ServiceAccount -Password $ServicePassword
        Connect-VIServer -Server VMName -User $ServiceAccount -Password $ServicePassword

        #Create empty arrays
        $DiskData = @()
        $ServiceData = @()
        $WebClientData = @()
        $DSCData = @()

        #If disk-usage.csv exists from Dev run, then add it to the diskData
        if(Test-Path -Path $DiskFile) {
            write-host "Importing Dev disk usage data"
            $DiskData += (Import-Csv -Path $DiskFile)
        }

        #If service-status.csv exists from Dev run, then add it to the serviceData
        if(Test-Path -Path $ServiceFile) {
            write-host "Importing Dev services data"
            $ServiceData += (Import-Csv -Path $ServiceFile)
        }

        #If service-status.csv exists from Dev run, then add it to the serviceData
        if(Test-Path -Path $WebClientFile) {
            write-host "Importing Dev web client data"
            $WebClientData += (Import-Csv -Path $WebClientFile)
        }

        #If dsc-capacity.csv exists from Dev run, then add it to the DSCData
        if(Test-Path -Path $DSCFile) {
            write-host "Importing Dev Datastore Cluster Capacity"
            $DSCData += (Import-Csv -Path $DSCFile)
        }

        #Filter VMs and monitors
        $vms = $vms | ?{$_.VM -like "VMName" -or $_.VM -like "VMName" -or $_.VM -like "VMName"}
        $diskMonitors = $diskMonitors | ?{$_.VM -like "VMName" -or $_.VM -like "VMName" -or $_.VM -like "VMName"}
        $serviceMonitors = $serviceMonitors | ?{$_.VM -like "VMName" -or $_.VM -like "VMName" -or $_.VM -like "VMName"}

        #Collect disk usage and service data
        foreach($_v in $vms) {
            $diskData += @(Invoke-DiskMonitoring -VM $_v.VM -Method $_v.DiskMethod -DiskMonitors $diskMonitors -LinuxUser $GuestUser -LinuxPassword $GuestPassword -WindowsUser $ServiceAccount -WindowsPassword $ServicePassword)
            $serviceData += @(Invoke-ServiceMonitoring -VM $_v.VM -Method $_v.ServiceMethod -ServiceMonitors $serviceMonitors -LinuxUser $GuestUser -LinuxPassword $GuestPassword -WindowsUser $ServiceAccount -WindowsPassword $ServicePassword)
        }

        #Collect Web Client data
        $WebClientData += Test-WebClients -WebClients @("https://VMName","https://VMName")

        #Collect Datastore cluster capacity data
        $DSCData += Measure-DatastoreClusterCapacity
        
        #Generate report
        $ReportURI = New-ApplianceHealthReport -DiskUsageData $diskData -ServiceData $serviceData -WebClientData $WebClientData -DSCData $DSCData

        #Output report URI to results.prop for Jenkins Environmental Variable injection
        "ReportURI=$ReportURI" | Out-File "$PSScriptRoot\results.prop" -Encoding ascii
    } elseif($env:computername -eq "VMName") {
        #Connect to vCenter
        Connect-VIServer -Server VMName -User $ServiceAccount -Password $ServicePassword

        #Filter VMs and monitors
        $vms = $vms | ?{$_.VM -like "VMName" -or $_.VM -like "VMName"}
        $serviceMonitors = $serviceMonitors | ?{$_.VM -like "VMName" -or $_.VM -like "VMName"}
        $diskMonitors = $diskMonitors | ?{$_.VM -like "VMName" -or $_.VM -like "VMName"}

        #Create empty arrays
        $diskData = @()
        $serviceData = @()

        #Collect disk usage and service data
        foreach($_v in $vms) {
            $diskData += @(Invoke-DiskMonitoring -VM $_v.VM -Method $_v.DiskMethod -DiskMonitors $diskMonitors -LinuxUser $GuestUser -LinuxPassword $GuestPassword -WindowsUser $ServiceAccount -WindowsPassword $ServicePassword)
            $serviceData += @(Invoke-ServiceMonitoring -VM $_v.VM -Method $_v.ServiceMethod -ServiceMonitors $serviceMonitors -LinuxUser $GuestUser -LinuxPassword $GuestPassword -WindowsUser $ServiceAccount -WindowsPassword $ServicePassword)
        }

        #Collect Web Client data
        Test-WebClients -WebClients @("https://VMName") | Export-Csv -NoTypeInformation -Path $WebClientFile

        #Collect Datastore cluster capacity data
        $DSCData = Measure-DatastoreClusterCapacity

        #Output to file for report generation on VMName
        $diskData | Export-Csv -NoTypeInformation -Path $DiskFile
        $serviceData | Export-Csv -NoTypeInformation -Path $ServiceFile
        $DSCData | Export-Csv -NoTypeInformation -Path $DSCFile
    } else {
        #Create empty arrays
        $diskData = @()
        $serviceData = @()

        #Collect disk usage and service data
        foreach($_v in $vms) {
            $diskData += Invoke-DiskMonitoring -VM $_v.VM -Method $_v.DiskMethod -DiskMonitors $diskMonitors -LinuxUser $GuestUser -LinuxPassword $GuestPassword -WindowsUser $ServiceAccount -WindowsPassword $ServicePassword
            $serviceData += Invoke-ServiceMonitoring -VM $_v.VM -Method $_v.ServiceMethod -ServiceMonitors $serviceMonitors -LinuxUser $GuestUser -LinuxPassword $GuestPassword -WindowsUser $ServiceAccount -WindowsPassword $ServicePassword
        }      
        
        #Collect Web Client data
        $WebClientData = Test-WebClients -WebClients @("https://VMName","https://VMName","https://VMName")
        
        #Collect Datastore cluster capacity data
        $DSCData = Measure-DatastoreClusterCapacity

        #Create HTML report
        New-ApplianceHealthReport -DiskUsageData $diskData -ServiceData $serviceData -WebClientData $WebClientData -DSCData $DSCData
    }
}

function Test-WebClients {
    [cmdletbinding()]
    param (
        $WebClients
    )
    
    $results = @()
    foreach($_w in $WebClients) {
        try {
            Write-host "Testing $_w"
            $request = $null
            $WebClientContent = $false
            $measure = Measure-Command { $request = Invoke-WebRequest -Uri $_w -ErrorAction Stop -UseBasicParsing }
            $responsetime = $measure.TotalMilliseconds

            if($request.StatusCode -eq 200) {
                $status = "OK"
                $WebClientTest = @($request.Content | ?{ $_ -like "*/vsphere-client/endpoints/live-updates*" })
                if($WebClientTest.count -eq 1) {
                    $WebClientContent = $true
                }
            } else {
                $status = $request.StatusDescription
            }
        }

        catch {
            $status = $_.Exception.Message
            $responsetime = -1
        }

        $results += [pscustomobject][ordered]@{
            URL = $_w
            Status = $status
            ResponseTimeMilliseconds = $responsetime
            WebClientContent = $WebClientContent
        }
    }
    Write-Output $results
}


function Measure-DatastoreClusterCapacity {
    [cmdletbinding()]
    param (
        $DatastoreUsable = .8,
        [switch]$ShowMath = $false
    )

    $dsc = Get-DatastoreCluster

    $results = @()
    foreach($_c in $dsc) {
        $ds = $_c | Get-Datastore

        $cluster_results = @()
        foreach($_ds in $ds) {
            $usableGB = $_ds.CapacityGB * $DatastoreUsable
            $usedGB = $_ds.CapacityGB - $_ds.FreeSpaceGB
            $availableGB = $usableGB - $usedGB
            $cluster_results += [pscustomobject][ordered]@{
                Datastore = $_ds.Name
                CapacityGB = $_ds.CapacityGB
                UsableGB = [math]::Round($usableGB,2)
                UsedGB = [math]::Round($usedGB,2)
                AvailableGB = [math]::Round($availableGB,2)
            }
        }

        if($ShowMath) { $cluster_results | FT }
        
        $results += [pscustomobject][ordered]@{
            DatastoreCluster = $_c.Name
            CapacityGB = $_c.CapacityGB
            FreeSpaceGB = [math]::Round($_c.FreeSpaceGB,2)
            AvailableGB = ($cluster_results | Measure-Object -Property AvailableGB -Sum).sum
        }
    }

    $results
}
