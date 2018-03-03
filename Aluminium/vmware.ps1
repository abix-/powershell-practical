function Set-VMHostAdvancedSetting {
    <#
    .SYNOPSIS
    Change the advanced settings for multiple vSphere VM Hosts.
    .DESCRIPTION
    Uses Get-AdvancedSetting and Set-AdvancedSetting to change the advanced setting.
    #>
    [cmdletbinding()]
    Param (
        $vmhosts,
        [Parameter(Mandatory=$true)]$Name,
        [Parameter(Mandatory=$true)]$value,
        $confirm = $false
    )
    if($vmhosts.EndsWith(".txt")) { $vmhosts = @(Get-Content $vmhosts) } 
    foreach($_v in $vmhosts) {
        try { $vm = Get-VMHost $_v -ErrorAction Stop }
        catch { Write-Host "$($_v): VMHost not found" -ForegroundColor Red; continue }
        $current = Get-AdvancedSetting -Entity $vm -Name $Name
        #if($confirm != $false) {
        Write-Host "$($_v): $($setting) is set to $($current.Value). Set to $($value)?"
        $option = Read-Host
        switch($option) {
            "Y" {
                Write-Host "$($_v): Setting $($setting) to $($value)"
                Set-AdvancedSetting -AdvancedSetting $current -Value $value 
            }
            "N" { }
            "A" { $confirm = $true }
        }
    }
}

function Get-DatastoreDetails {
    <#
    .SYNOPSIS
    Gets Capacity
    #>
    [cmdletbinding()]
    param (
        [string]$Name = "",
        [string]$Parent
    )

    if($Parent) {
        $ParentObj = Get-VIObject -Name $Parent
        $ParentvCenter = $ParentObj.UID | Where-Object{$_ -match "@(?<vcenter>.*):443"} | ForEach-Object{$matches['vcenter']}
        $datastores = @(Get-View -Server $ParentvCenter -ViewType Datastore -SearchRoot $ParentObj.MoRef -Filter @{"Name"="$Name"})
        Write-Verbose "[$Name] Found $($datastores.count) datastores in $ParentvCenter\$Parent"
    } else {
        $datastores = @(Get-View -ViewType Datastore -Filter @{"Name"="$Name"})
        Write-Verbose "[$Name] Found $($datastores.count) datastores"
    }
    $results = @()
    foreach($_d in ($datastores | Select-Object -ExpandProperty Summary)) {
        Write-Verbose "[$($_d.Name)] Processing datastore"
        $capgb = (($_d.Capacity)/1GB)
        $provgb = (($_d.Capacity – $_d.FreeSpace + $_d.Uncommitted)/1GB)
        $results += [pscustomobject][ordered]@{
            Name = $_d.Name
            "CapacityGB" = "{0:N2}" -f $capgb
            "MaxUsableGB" = "{0:N2}" -f ($capgb * 0.80)
            "FreeGB" = "{0:N2}" -f ($_d.FreeSpace/1GB)
            "ProvisionedGB" = "{0:N2}" -f $provgb
            "OverProvisionedGB" = "{0:N2}" -f ($provgb - $capgb)
            "OverProvisionedPercent" = "{0:N2}" -f (($provgb/$capgb)*100)
        }
    }
    return $results | Sort-Object Name
}

function Get-vCenterFromUID($uid) {
    $uid | Where-Object{$_ -match "@(?<vcenter>.*):443"} | ForEach-Object{$matches['vcenter']}
}

function Get-VIObject {
    <#
    (1.0)
    #>
    [cmdletbinding()]
    param (
        $Name = "",
        $Type
        #$Parent
    )
    $Types = @("Datacenter", "ClusterComputeResource", "HostSystem", "VirtualMachine", "Datastore")
    if($Type) {
        return Get-View -ViewType $Type -Filter @{"Name"="$Name"} | Get-VIObjectByVIView
    } else {
        foreach($_t in $Types) {
            Write-Verbose "Checking $_T"
            $views = @(Get-View -ViewType $_t -Filter @{"Name"="$Name"})
            if($views.count -gt 0) {
                Write-Verbose "[$Name] Found $_t object"
                return Get-VIObjectByVIView -VIView $views
            }
        }
    }
    Write-Warning "[$Name] No VMware object found"
}

function Get-VMHostMetrics {
    <#
    .SYNOPSIS
    (BETA)
    Comments are out of date. Update needed.
    Collect configuration metrics for a VMHost, Cluster, Datacenter, or vCenter. For each VM Host found, these metrics are collected:
    -Parent object(Cluster, Datacenter)
    -Hardware model
    -ESXi build 
    -IP address 
    -VMs on host
    -physical CPUs(pCPU) on host
    -virtual CPUs(vCPU) allocated
    -vCPU to pCPU ratio

    .DESCRIPTION
    Connect to vCenter with Connect-VIServer before using this script.
    Written with PowerShell v3.0 and PowerCLI 6.0(2548067).

    .EXAMPLE
    .\Get-VMHostMetrics -cluster
    #>
    [cmdletbinding(DefaultParameterSetName="Name")]
    Param (
        [Parameter(ParameterSetName="Name",Position=0)]$Name = "",
        [Parameter(ParameterSetName="Parent",Position=1)]$Parent,
        [switch]$report = $true,
        [string]$reportName = "VMHostMetrics_"
    )

    if($global:defaultviservers) {
        if($global:defaultviservers.count -eq 1) {
            $vCenter = $global:defaultviservers[0].name
        } else { $vCenter = "multiple"  }
    }

    #Switch the Parameter Set and collect the appropriate VMware object(s)
    $all = @()
    try { 
        switch($PSCmdlet.ParameterSetName) {
            "Parent" {
                $ParentObj = Get-VIObject -Name $Parent
                $vCenter = $ParentObj.UID | Where-Object{$_ -match "@(?<vcenter>.*):443"} | ForEach-Object{$matches['vcenter']}
                $VMHostViews = @(Get-View -Server $vCenter -ViewType HostSystem -SearchRoot $ParentObj.ExtensionData.MoRef -Property Name)
                Write-Host "[$vCenter] Found $($VMHostViews.count) VMHosts in $Parent"
            }
            "Name" {
                $VMHostViews = @(Get-View -ViewType HostSystem -Filter @{"Name"="$Name"} -Property Name)
                Write-Host "[$vCenter] Found $($VMHostViews.count) VMHosts matching '$Name'"
            }
        }

        if($VMHostViews.Count -eq 0) {
            Write-Host "No VMHosts found. Aborting."
            Return    
        } else { $vmhosts = $VMHostViews | Sort-Object Name | Get-VIObjectByVIView }
    }
    catch { 
        Write-Host -ForegroundColor Red $_.Exception.Message; 
        Return 
    }

    #Determine configuration metrics
    foreach($_vmhost in $vmhosts) {
        Write-Host "[$($_vmhost.Name)] Collecting data"
        $view = $_vmhost | Get-View
        $vms = $_vmhost | Get-VM
        $totalCPU = ($vms | Measure-Object -Sum -Property NumCPU).Sum
        if(!$totalCPU) { $totalCPU = 0 }
        $ratio = "{0:N3}" -f ($totalCPU/$_vmhost.NumCPU)
        $totalGB = ($vms | Measure-Object -Sum -Property MemoryGB).Sum
        if(!$totalGB) { $totalGB = 0 }
        $ramratio = "{0:N3}" -f ($totalGB/$_vmhost.MemoryTotalGB)

        #Create an ordered PS Custom Object and store the metrics
        $all += [pscustomobject][ordered]@{
            VMHost = [string]$_vmhost.name
            vCenter = $_vmhost.uid | Where-Object{$_ -match "@(?<vcenter>.*):443"} | ForEach-Object{$matches['vcenter']}
            Cluster = [string]$_vmhost.Parent
            Model = [string]$_vmhost.Model
            Build = [int]$view.Config.Product.Build
            IPAddress = ($_vmhost | Get-VMHostNetworkAdapter) | Where-Object{$_.ManagementTrafficEnabled} | Select-Object -ExpandProperty IP
            VMs = [int]$vms.count
            #MaxCPU_24hour = "{0:N2}" -f ($_vmhost | Get-Stat -Stat cpu.usage.average -MaxSamples 12 -IntervalSecs 7200 | Measure-Object -Maximum -Property Value).Maximum
            #AvgCPU_24hour = "{0:N2}" -f ($_vmhost | Get-Stat -Stat cpu.usage.average -MaxSamples 12 -IntervalSecs 7200 | Measure-Object -Average -Property Value).Average
            #MaxMem_24hour = "{0:N2}" -f ($_vmhost | Get-Stat -Stat mem.usage.average -MaxSamples 12 -IntervalSecs 7200 | Measure-Object -Maximum -Property Value).Maximum
            #AvgMem_24hour = "{0:N2}" -f ($_vmhost | Get-Stat -Stat mem.usage.average -MaxSamples 12 -IntervalSecs 7200 | Measure-Object -Average -Property Value).Average
            pCPU = [int]$_vmhost.NumCPU
            vCPU = [int]$totalCPU
            CPURatio = [double]$ratio
            pRAM = [int]$_vmhost.MemoryTotalGB
            vRAM = [int]$totalGB
            RAMRatio = [double]$ramratio
        }
    }

    #Show results and export report
    $all | Sort-Object VMHost
    if($report -eq $true -and $all.count -gt 0) {
        $reportName += $vCenter
        Export-Results -results $all -exportName $reportName -excel
    }
}

function Get-VMDiskMap {
	[Cmdletbinding()]
    #Requires -Version 3.0
	param([Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)][string]$VM)
	begin { }
	process {
		if ($VM) {
			$VmView = Get-View -ViewType VirtualMachine -Filter @{"Name" = $VM}	   
			foreach ($VirtualSCSIController in ($VMView.Config.Hardware.Device | Where-Object {$_.DeviceInfo.Label -match "SCSI Controller"})) {
				foreach ($VirtualDiskDevice in ($VMView.Config.Hardware.Device | Where-Object {$_.ControllerKey -eq $VirtualSCSIController.Key})) {
					$VirtualDisk = "" | Select-Object VM,SCSIController, DiskName, SCSI_Id, DiskFile,  DiskSize, WindowsDisks
					$VirtualDisk.VM = $VM
					$VirtualDisk.SCSIController = $VirtualSCSIController.DeviceInfo.Label
					$VirtualDisk.DiskName = $VirtualDiskDevice.DeviceInfo.Label
					$VirtualDisk.SCSI_Id = "$($VirtualSCSIController.BusNumber) : $($VirtualDiskDevice.UnitNumber)"
					$VirtualDisk.DiskFile = $VirtualDiskDevice.Backing.FileName
					$VirtualDisk.DiskSize = $VirtualDiskDevice.CapacityInKB * 1KB / 1GB

					$LogicalDisks = @()
					# Look up path for this disk using WMI.
					$thisVirtualDisk = get-wmiobject -class "Win32_DiskDrive" -namespace "root\CIMV2" -computername $VM | Where-Object {$_.SCSIBus -eq $VirtualSCSIController.BusNumber -and $_.SCSITargetID -eq $VirtualDiskDevice.UnitNumber}
					# Look up partition using WMI.
					$Disk2Part = Get-WmiObject Win32_DiskDriveToDiskPartition -computername $VM | Where-Object {$_.Antecedent -eq $thisVirtualDisk.__Path}
					foreach ($thisPartition in $Disk2Part) {
						#Look up logical drives for that partition using WMI.
						$Part2Log = Get-WmiObject -Class Win32_LogicalDiskToPartition -computername $VM | Where-Object {$_.Antecedent -eq $thisPartition.Dependent}
						foreach ($thisLogical in $Part2Log) {
							if ($thisLogical.Dependent -match "[A-Z]:") {
								$LogicalDisks += $matches[0]
							}
						}
					}

					$VirtualDisk.WindowsDisks = $LogicalDisks
					Write-Output $VirtualDisk
				}
			}
		}
	}
	end {
	}
}

function Connect-vCenter {
    <#
    .SYNOPSIS
    Menu for connecting PowerShell and the vSphere Client to vCenter
    .DESCRIPTION
    Edit vcenters.csv and edit the list of vCenters and associated username
    #>
    [cmdletbinding()]
    param (
        [Parameter(Position=0)][string]$vCenter,
        [switch]$all,
        [switch]$client,
        [switch]$StartDay
    )

    #Import vcenters.csv
    $vcenters = Import-Csv "$($PSScriptRoot)\vcenters.csv"

    #Draw menu if needed
    if(!$vCenter) {
        Write-Host "Select a server from the list"
        for($i = 1; $i -lt $vcenters.count + 1; $i++) { Write-Host "[$i] $($vcenters[$i-1].vCenter)" }
        $option = Read-Host "#, all, start-day"
    } else {
        $option = $vCenter
    }

    #Switch $option to determine selected vCenter
    switch -Regex ($option) {
        "\d{1},\d{1}" { #Connect to multiple vCenters by number
            Write-Host "Disconnecting from all connected vCenters"
            if($global:DefaultVIServers) { Disconnect-VIServer -Server $global:DefaultVIServers -Force -ErrorAction SilentlyContinue -Confirm:$false }

            $options = $option.Split(",")
            foreach($_o in $options) {
                $destvCenter = $vcenters[$_o-1]
                $cred = Get-SecureStringCredentials -Username $destvCenter.Credentials -Credentials
                ConnectClients -vCenter $destvCenter.vCenter -Credential $cred -Client:$client
            }
            Set-PowerCLITitle "Multiple vCenters"
            break
        }
        "\A\d{1}" { #Connect to one vCenter by number
            Write-Host "Disconnecting from all connected vCenters"
            if($global:DefaultVIServers) { Disconnect-VIServer -Server $global:DefaultVIServers -Force -ErrorAction SilentlyContinue -Confirm:$false }

            #Assign variable to selected vCenter and get user credentials
            $destvCenter = $vcenters[$option-1]
            $cred = Get-SecureStringCredentials -Username $destvCenter.Credentials -Credentials
            ConnectClients -vCenter $destvCenter.vCenter -Credential $cred -Client:$client
            Set-PowerCLITitle $destvCenter.vCenter
            break
        }
        "all" { #Connect to all vCenters
            $connectioneeded = @()
            foreach($_v in $vcenters) {
                if($Global:DefaultVIServers.Name -notcontains $_v.vCenter) {
                    Write-Host "[$($_v.vCenter)] Connect-VIServer needed" ; $connectioneeded += $_v
                } else { Write-Host "$($_v.vCenter): Already connected" }
            }
            #Determine unique usernames and connect to vCenters
            foreach($_u in ($connectioneeded.Credentials | Select-Object -Unique)) {
                $cred = Get-SecureStringCredentials -Username $_u -Credentials
                foreach($_v in ($connectioneeded | Where-Object{$_.Credentials -eq $_u})) {
                    ConnectClients -vCenter $_v.vCenter -Credential $cred -Client:$client
                }
            }
            Set-PowerCLITitle "All vCenters"
            break
        }
        "start-day" { #Launch Clients based on settings in vcenters.csv
            #Get unique credentials
            foreach($_u in ($vcenters.Credentials | Select-Object -Unique)) {
                $cred = Get-SecureStringCredentials -Username $_u -Credentials
                $vcenters | Where-Object{$_.Credentials -eq $_u} | ForEach-Object{ Add-Member -InputObject $_ -MemberType NoteProperty -Name Credential -Value $cred -Force }
            }

            #Connect PowerShell to all vCenters. Launch vSphere client if flagged
            foreach($_v in $vcenters) {
                if($_v."Start-Day" -eq "Yes") {
                    [switch]$client = $true
                } else {
                    [switch]$client = $false
                }
                ConnectClients -vCenter $_v.vCenter -Credential $_v.credential -Client:$client
            }
            Set-PowerCLITitle "All vCenters"
            break
        }
        default { Write-Host "$option - Invalid Option" }
    }
}

function ConnectClients {
    [cmdletbinding()]
    param (
        [string]$vCenter,
        $Credential,
        [switch]$Client
    )
    #if -client switch is used, launch vSphere client and connect with credentials
    if($client) {
        Write-Host "[$vCenter] Launching vSphere Client as $($Credential.Username) "
        Start-Process -FilePath "C:\Program Files (x86)\VMware\Infrastructure\Virtual Infrastructure Client\Launcher\VpxClient.exe" -ArgumentList "-s $vCenter -u $($Credential.username) -p $($Credential.GetNetworkCredential().Password)" 
    }
            
    #Connect to selected vCenter
    Write-Host "[$vCenter] Connecting PowerCLI as $($Credential.Username)"
    Connect-VIServer -Credential $Credential -server $vCenter -Protocol https
}

function Start-MultipleVM {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true)]$servers,
        $seconds = 5
    )

    #Read servers from file
    if($servers.EndsWith(".txt")) { $servers = Get-Content $servers | Sort-Object }

    #Get VM objects. On error, catch the exception and exit
    try { $vms = Get-VM $servers -ErrorAction Stop | Sort-Object Name }
    catch { 
        Write-Host $_.Exception.message -ForegroundColor Red
        Write-Host "Failed to find VM(s). Did you use 'Connect-VIServer vCenterServer'?"; 
        Return 
    }

    #Assign variables and show VM list
    $poweredoff = $($vms | Where-Object{$_.PowerState -eq "PoweredOff"})
    $poweredon = $($vms | Where-Object{$_.PowerState -eq "PoweredOn"})
    $vms

    #Show count of PoweredOff/PoweredOn
    Write-Host ""
    Write-Host "Powered Off: $($poweredoff.count)    Powered On: $($poweredOn.count)"

    #Prompt for confirmation, then startup the VMs
    if($poweredoff.count -gt 0) {
        $option = Read-Host  "Enter 'go' to start the PoweredOff VMs. Waiting $($seconds) seconds between VMs."
        switch($option) {
            "go" {
                foreach($_v in $poweredoff) {
                    Write-Host "$($_v.name) - Starting up"
                    Start-VM -VM $_v -Confirm:$false
                    Start-Sleep $seconds
                }
            }
            default { Write-Host "Exiting"; Return }
        }
    }
}

function Stop-MultipleVM {
    [cmdletbinding()]
    #Requires -Version 3.0
    Param (
        [Parameter(Mandatory=$true)]$servers,
        $seconds = 5
    )

    #Read servers from file
    if($servers.EndsWith(".txt")) { $servers = Get-Content $servers | Sort-Object }

    #Get VM objects. On error, catch the exception and exit
    try { $vms = Get-VM $servers -ErrorAction Stop | Sort-Object Name }
    catch { 
        Write-Host $_.Exception.message -ForegroundColor Red
        Write-Host "Failed to find VM(s). Did you use 'Connect-VIServer vCenterServer'?"; 
        Return 
    }

    #Assign variables and show VM list
    $poweredoff = $($vms | Where-Object{$_.PowerState -eq "PoweredOff"})
    $poweredon = $($vms | Where-Object{$_.PowerState -eq "PoweredOn"})
    $vms

    #Show count of PoweredOff/PoweredOn
    Write-Host ""
    Write-Host "Powered Off: $($poweredoff.count)    Powered On: $($poweredOn.count)"

    #Prompt for confirmation, then shutdown the VMs
    if($poweredon.count -gt 0) {
        $option = Read-Host  "Enter 'stop' to shutdown the PoweredOn VMs. Waiting $($seconds) seconds between VMs."
        switch($option) {
            "stop" {
                foreach($_v in $poweredon) {
                    Write-Host "$($_v.name) - Shutting down"
                    Stop-VMGuest -VM $_v -Confirm:$false
                    Start-Sleep $seconds
                }
            }
            default { Write-Host "Exiting"; Return }
        }
    }
}

function Set-ESXiFirewall {
    <#
    .SYNOPSIS
    Quick enable/disable the VUM Firewall Exception on VMHosts, Clusters, and Datacenters.
    Connect to the target vCenter first with 'Connect-VIServer -server $name'

    .DESCRIPTION
    Written with PowerShell v3.0 and PowerCLI 6.0(2548067).

    .EXAMPLE
    Check status of VUM exception on all VMHosts
    Get-VMHost | sort Name | Get-VMHostFirewallException -Name "vCenter Update Manager" | select VMHost,Name, Enabled, OutgoingPorts

    .EXAMPLE
    Disable VUM exception on VMHOST.DOMAIN.LOCAL
    .\Set-VUM_Firewall.ps1 -vmhost VMHOST.DOMAIN.LOCAL -enabled $false
    .EXAMPLE
    Enable VUM exception on all VMHosts in GOLD Cluster
    .\Set-VUM_Firewall.ps1 -cluster GOLD -enabled $true

    .EXAMPLE
    Disable VUM exception on all VMHosts in PRODUCTION Datacenter
    Set-VUM_Firewall.ps1 -datacenter PRODUCTION -enabled $false
    #>
    [cmdletbinding()]
    #Requires -Version 3.0
    Param (
        [Parameter(ParameterSetName="VMHost",Mandatory=$true,Position=0)]
        [string]$vmhost,
        [Parameter(ParameterSetName="Cluster",Mandatory=$true)]
        [string]$cluster,
        [Parameter(ParameterSetName="Datacenter",Mandatory=$true)]
        [string]$datacenter,
        [Parameter(ParameterSetName="VMHost")]
        [Parameter(ParameterSetName="Cluster")]
        [Parameter(ParameterSetName="Datacenter")]
        [bool]$enabled = $false,
        $exception = "SNMP Server"
    )

    try {
        switch($PSCmdlet.ParameterSetName) {
            "VMHost" { 
                $h = Get-VMHost $vmhost -ErrorAction Stop; SetException $h
                }
            "Cluster" { 
                $c = Get-Cluster $cluster -ErrorAction Stop | Get-VMHost | Sort-Object Name
                foreach($_c in $c) { SetException $_c } 
                }
            "Datacenter" { 
                $c = Get-Datacenter $datacenter -ErrorAction Stop | Get-VMHost | Sort-Object Name
                foreach($_c in $c) { SetException $_c }
            }
        }
    }
    catch { Write-Host $_.Exception.message -ForegroundColor Red; Return }
}

function Get-VMHosts {
    try { 
        switch($PSCmdlet.ParameterSetName) {
            "Parent" {
                $ParentObj = Get-VIObject -Name $Parent
                $ParentvCenter = $ParentObj.UID | Where-Object{$_ -match "@(?<vcenter>.*):443"} | ForEach-Object{$matches['vcenter']}
                $VMHostViews = @(Get-View -Server $ParentvCenter -ViewType HostSystem -SearchRoot $ParentObj.ExtensionData.MoRef -Property Name)
                Write-Host "[$Parent] Found $($VMHostViews.count) VMHosts Views in $ParentvCenter\$Parent"
                $reportName += $Parent
            }
            "Name" {
                $VMHostViews = @(Get-View -ViewType HostSystem -Filter @{"Name"="$Name"} -Property Name)
                Write-Host "[$Name] Found $($VMHostViews.count) VMHosts"
                $reportName += $Name
            }
        }

        if($VMHostViews.Count -eq 0) {
            Write-Host "No VMHosts found. Aborting."
            Return    
        } else {
            $vmhosts = $VMHostViews | Sort-Object Name | Get-VIObjectByVIView
        }
    }
    catch { Write-Host -ForegroundColor Red $_.Exception.Message; Return }
    return $vmhosts
}

function Get-VMDetails {
    <#
    .DESCRIPTION
    Get details for one or many(from a .txt file) VMs on cluster, vCPU, vRAM, disks, allocated disk space, and networking configuration.
    .EXAMPLE
    Get details on myservername
    PS> Get-VMDetails myservername
    .EXAMPLE
    Get details on multiple servers in manyservers.txt
    PS>  Get-VMDetails manyservers.txt
    #>
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)]$Name,
        [switch]$export = $false
    )
    if($Name.EndsWith(".txt")) { $Name = @(Get-Content $Name) | Select-Object -Unique } 
    try { $allvms = Get-VM -ErrorAction Stop }
    catch { Write-Host "Failed to get VMs. Are you connected to vCenter?" -ForegroundColor Red; Return }

    $results = @()
    foreach($_s in $Name) {
        Write-Host "$($_s): Collecting metrics"
        $vms = @($allvms | Where-Object{$_.name -eq "$_s"})
        if($vms.count -eq 0) { Write-Host "$($_s): VM not found. Skipping." -ForegroundColor Red; Continue } 
        elseif($vms.count -gt 1) { Write-Warning "$($_s): Found $($vms.count) matching VMs" }
        foreach($vm in $vms) {
            $NetworkType0 = $NetworkType1 = ""
            $NetworkLabel0 = $NetworkLabel1 = ""
            
            $adapters = $vm | Get-NetworkAdapter
            if($adapters) {
                $adapters | ForEach-Object{$i=0} {
                    Set-Variable -Name NetworkType$i -Value $_.Type
                    Set-Variable -Name NetworkLabel$i -Value $_.NetworkName
                    $i++
                }
            }
            $disks = $vm | Get-HardDisk
            $results += [pscustomobject][ordered]@{
                Name = $vm.Name
                PowerState = $vm.PowerState
                Cluster = ($vm | Get-Cluster).Name
                #VMHost = ($vm | Get-VMHost).Name
                #DatastoreCluster = ( $vm | Get-DatastoreCluster).Name
                #Datastore = ($VM | Get-datastore | select -first 1).Name
                "NetworkLabel-1" = $NetworkLabel0
                Folder = $vm.Folder.Name
                NumCPU = $vm.NumCpu
                MemoryGB = [math]::Round($vm.MemoryGB,2)
                Disks = $disks.count
                AllocatedGB = [math]::Round(($disks | Measure-Object -Property CapacityGB -Sum).Sum,2)
                "NetworkType-1" = $NetworkType0
                "NetworkType-2" = $NetworkType1
                "NetworkLabel-2" = $NetworkLabel1
                "IP" = $vm.Guest.IPAddress[0]
                "IP-2" = $vm.Guest.IPAddress[1]
            }
        }
    }
    Write-Output $results
    if($export) { Export-Results -Results $results -ExportName Get-VMDetails -excel }
}

function Get-VMDatastoreDetails {
    <#
    .DESCRIPTION
    Get datastore details for one or many(from a .txt file) VMs. By default this data is exported to csv.
    .EXAMPLE
    Get details on MYSERVERNAME
    PS> .\Get-VMDatastoreDetails.ps1 MYSEVERNAME
    .EXAMPLE
    Get details on multiple servers in manyservers.txt
    PS> .\Get-VMDatastoreDetails.ps1 manyservers.txt
    #>
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)]$servers,
        [switch]$export = $false
    )
    if($servers.EndsWith(".txt")) { $servers = @(Get-Content $servers) }
    try { $allvms = Get-VM -ErrorAction Stop }
    catch { Write-Host "Failed to get VMs. Are you connected to vCenter?" -ForegroundColor Red; Return }

    $all = @()
    foreach ($_s in $servers){
        Write-Host "$($_s): Collecting data"
        $vms = @($allvms | Where-Object{$_.name -eq "$_s"})
        if($vms.count -eq 0) { Write-Host "$($_s): VM not found. Skipping." -ForegroundColor Red; Continue } 
        elseif($vms.count -gt 1) { Write-Warning "$($_s): Found $($vms.count) matching VMs" }

        foreach($vm in $vms) {
            try { 
                $VMDKs = $VM | Get-HardDisk -ErrorAction Stop 
                $VMView = $VM | Get-View
            }
            catch { Write-Host "$($_s): Failed to get hard disks. Skipping." -ForegroundColor Red; Continue }
            if($VMDKs) {
	            foreach ($VMDK in $VMDKs) {
                    $Info = $VMView.Config.Hardware.Device | where {$_.GetType().Name -eq "VirtualDisk"} | where {$_.DeviceInfo.Label -eq $VMDK.Name}
		            if ($VMDK -ne $null){
			            $CapacityGB = $VMDK.CapacityKB/1024/1024
			            $CapacityGB = [int]$CapacityGB
                        $datastore = $VMDK.FileName.Split(']')[0].TrimStart('[')
			            $datastoreobject = Get-Datastore $datastore | Select-Object -First 1
                        $all += [pscustomobject][ordered]@{
			                Name = $_s
                            Cluster = ($vm | Get-Cluster).Name
                            "Hard Disk" = $VMDK.Name
                            "SCSI-Controller" = $info.ControllerKey
                            "SCSI-ID" = $info.UnitNumber
                            VMDKFileName = $VMDK.Filename
                            VMDKPath = $VMDK.FileName.Split(']')[1].TrimStart('[ ')
                            VMDKCapacityGB = $CapacityGB
                            VMDKType = $VMDK.DiskType
                            VMDKFormat = $VMDK.StorageFormat
			                Datastore = $datastore
                            DatastoreCapacityGB = "{0:N2}" -f $datastoreobject.CapacityGB
                            DatastoreFreeGB = "{0:N2}" -f $datastoreobject.FreeSpaceGB
                            DatastoreFreePercent = "{0:N2}" -f (($datastoreobject.FreeSpaceGB/$datastoreobject.CapacityGB)*100)
                            ScsiCanonicalName = $vmdk.ScsiCanonicalName
                            DeviceName = $vmdk.DeviceName
                        }
		            }
	            }
            }
        }
    }
    $all = $all | Sort-Object Name
    if($export) { Export-Results -Results $all -ExportName Get-VMDatastoreDetails -excel }
    else { Write-Output $all }
}

function Get-SyslogSettings {
    [cmdletbinding()]
    Param (
        [Parameter(ParameterSetName="VMHost",Mandatory=$true,Position=0)]
        [string]$vmhost,
        [Parameter(ParameterSetName="Cluster",Mandatory=$true)]
        [string]$cluster,
        [Parameter(ParameterSetName="Datacenter",Mandatory=$true)]
        [string]$datacenter,
        [Parameter(ParameterSetName="vCenter",Mandatory=$true)]
        [switch]$vcenter,
        [switch]$export = $true,
        [string]$reportName = "SyslogSettings_"
    )

    #need to remove .16 from hosts

    #Switch the Parameter Set and collect the appropriate VMware object
    $all = @()
    try {
        switch($PSCmdlet.ParameterSetName) {
            "VMHost" {
                #Collect metrics from one host and append to $all
                $h = Get-VMHost $vmhost -ErrorAction Stop; $all += GetSyslogSettings $h
                $reportName += $vmhost
                }
            "Cluster" { 
                #Loop through each host in the cluster, collect metrics, append to $all
                $h = Get-Cluster $cluster -ErrorAction Stop | Get-VMHost | Sort-Object Name
                $reportName += $cluster
                foreach($_h in $h) { Write-Host "$cluster - $_h - Collecting data"; $all += GetSyslogSettings $_h  }     
                }
            "Datacenter" {
                #Loop thrugh each host in the datacenter, collect metrics, append to $all
                $h = Get-Datacenter $datacenter -ErrorAction Stop | Get-VMHost | Sort-Object Name
                $reportName += $datacenter
                foreach($_h in $h) { Write-Host "$datacenter - $_h - Collecting data"; $all += GetSyslogSettings $_h  }
            }
            "vCenter" {
                #Loop all hosts in vCenter, collect metrics, append to $all
                $h = Get-VMHost -ErrorAction Stop | Sort-Object Name 
                $reportName += "$($global:DefaultVIServer[0].name)"
                foreach($_h in $h) { Write-Host "$_h - Collecting data"; $all += GetSyslogSettings $_h }      
            }
        }
    }
    catch { Write-Host -ForegroundColor Red $_.Exception.Message; Return }

    $all | Sort-Object VMHost

    #Export report
    if($export -eq $true) {
        Export-Results -results $all -exportName $reportName -excel
    }
}

function Set-ESXiFirewall {
    <#
    .SYNOPSIS
    Quick enable/disable the VUM Firewall Exception on VMHosts, Clusters, and Datacenters.
    Connect to the target vCenter first with 'Connect-VIServer -server $name'

    .DESCRIPTION
    Written with PowerShell v3.0 and PowerCLI 6.0(2548067).

    .EXAMPLE
    Check status of VUM exception on all VMHosts
    Get-VMHost | sort Name | Get-VMHostFirewallException -Name "vCenter Update Manager" | select VMHost,Name, Enabled, OutgoingPorts

    .EXAMPLE
    Disable VUM exception on VMHOST.DOMAIN.LOCAL
    .\Set-VUM_Firewall.ps1 -vmhost VMHOST.DOMAIN.LOCAL -enabled $false
    .EXAMPLE
    Enable VUM exception on all VMHosts in GOLD Cluster
    .\Set-VUM_Firewall.ps1 -cluster GOLD -enabled $true

    .EXAMPLE
    Disable VUM exception on all VMHosts in PRODUCTION Datacenter
    Set-VUM_Firewall.ps1 -datacenter PRODUCTION -enabled $false
    #>

    [cmdletbinding()]
    Param (
        [Parameter(ParameterSetName="VMHost",Mandatory=$true,Position=0)]
        [string]$vmhost,
        [Parameter(ParameterSetName="Cluster",Mandatory=$true)]
        [string]$cluster,
        [Parameter(ParameterSetName="Datacenter",Mandatory=$true)]
        [string]$datacenter,
        [Parameter(ParameterSetName="VMHost")]
        [Parameter(ParameterSetName="Cluster")]
        [Parameter(ParameterSetName="Datacenter")]
        [bool]$enabled = $false,
        $exception = "SNMP Server"
    )

    try {
        switch($PSCmdlet.ParameterSetName) {
            "VMHost" { 
                $h = Get-VMHost $vmhost -ErrorAction Stop; SetException $h
                }
            "Cluster" { 
                $c = Get-Cluster $cluster -ErrorAction Stop | Get-VMHost | Sort-Object Name
                foreach($_c in $c) { SetException $_c } 
                }
            "Datacenter" { 
                $c = Get-Datacenter $datacenter -ErrorAction Stop | Get-VMHost | Sort-Object Name
                foreach($_c in $c) { SetException $_c }
            }
        }
    }
    catch { Write-Host $_.Exception.message -ForegroundColor Red; Return }
}

function Get-NTP_Health {
    <#
    .SYNOPSIS
    Collects time metrics for all VMHosts in a VMware object(host, cluster, datacenter, host) and reports on Time Drift(between local time and server time) and NTP Configuration.

    .DESCRIPTION
    Using -details
    Written with PowerShell v3.0 and PowerCLI 6.0(2548067).

    .EXAMPLE
    Get detailed information for a specific host
    .\Get-NTP_Health.ps1 -VMHost VMHOST.DOMAIN.LOCAL -details

    Get basic information(Time Drift) for GOLD cluster
    .\Get-NTP_Health.ps1 -Cluster GOLD

    #>
    [cmdletbinding(DefaultParameterSetName="Name")]
    Param (
        [Parameter(ParameterSetName="Name")]$Name = "",
        [Parameter(ParameterSetName="Parent")]$Parent,
        #[Parameter(ParameterSetName="VMHost",Mandatory=$true,Position=0)]
        #[string]$vmhost,
        #[Parameter(ParameterSetName="Cluster",Mandatory=$true)]
        #[string]$cluster,
        #[Parameter(ParameterSetName="Datacenter",Mandatory=$true)]
        #[string]$datacenter,
        #[Parameter(ParameterSetName="vCenter",Mandatory=$true)]
        #[switch]$vcenter,
        [switch]$details = $false
    )

    
    try { 
        switch($PSCmdlet.ParameterSetName) {
            "Parent" {
                $ParentObj = Get-VIObject -Name $Parent
                $ParentvCenter = $ParentObj.UID | Where-Object{$_ -match "@(?<vcenter>.*):443"} | ForEach-Object{$matches['vcenter']}
                $VMHostViews = @(Get-View -Server $ParentvCenter -ViewType HostSystem -SearchRoot $ParentObj.ExtensionData.MoRef -Property Name)
                Write-Host "[$Parent] Found $($VMHostViews.count) VMHosts in $ParentvCenter\$Parent"
                $reportName += $Parent
            }
            "Name" {
                $VMHostViews = @(Get-View -ViewType HostSystem -Filter @{"Name"="$Name"} -Property Name)
                Write-Host "[$Name] Found $($VMHostViews.count) VMHosts"
                $reportName += $Name
            }
        }

        if($VMHostViews.Count -eq 0) {
            Write-Host "No VMHosts found. Aborting."
            Return    
        } else {
            $vmhosts = $VMHostViews | Sort-Object Name | Get-VIObjectByVIView
        }
    }
    catch { Write-Host -ForegroundColor Red $_.Exception.Message; Return }

    $all = @()
    foreach($_h in $vmhosts) {
        Write-Host "[$($_h.Name)] Getting NTP metrics"
        $all += GetHealth $_h
    }

    switch($details) {
        $false { $all | Select-Object VMHost,NTPServer0,TimeDrift }
        $true { $all }
    }
}

function Get-HostLogs {
    <#
    .SYNOPSIS
    Collect all ESXi host logs from a specified VMHost and downloads them $DestinationPath.

    .DESCRIPTION
    Written with PowerShell v3.0 and PowerCLI 6.0(2548067).

    .EXAMPLE
    Get all the logs from HostA
    .\Get-HostLogs.ps1 -vmhost HostA.domain.local
    #>

    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)]$vmhost,
        [string]$DestinationPath = "C:\HostLogs"
    )

    #Get a VMHost object and the Log Types
    try { $h = Get-VMHost $vmhost; $k = $h | Get-LogType }
    catch { Write-Host $_.Exception.Message -ForegroundColor Red; Quit }
    $datetime = Get-Date -Format yy-MM-dd_HH-mm-ss

    #Foreach Log Type....
    foreach($_k in $k) {
        $log = $null
        Write-Host "[$vmhost] - $_k - Collection started"

        #Create the output folder if it doesnt exist
        $outfolder = "$DestinationPath\$vmhost"
        if(!(Test-Path -path $outfolder)) {
            Write-Host "[$vmhost] - Creating $outfolder directory"
            New-item $outfolder -ItemType directory | Out-Null
        }

        #Get a log of the current Log Type from the VMHost
        $log = Get-Log -key $_k.Key -VMHost $h | Select-Object -ExpandProperty Entries

        #Output the log to file
        $output = "$outfolder\$($datetime)_$($_k).log"
        $log | Out-File $output -Encoding ascii
        Write-Host "[$vmhost] - $_k - Exported to $output"
    }
}

function Connect-SSHPutty {
    <#
    .SYNOPSIS
    Start the SSH service and connect to a given VMhost using Putty. When Putty closes, the SSH service will be stopped. If no VMHost is given, a menu of all VM hosts on the currently connected vCenter will be shown. Connect to vCenter with Connect-VIServer before using this.

    .DESCRIPTION
    Written with PowerShell v3.0 and PowerCLI 6.0(2548067).

    .EXAMPLE
    On VMHostA, start the SSH Service and connect using Putty
    .\Connect-SSHPutty.ps1 -vmhost VMHOST.DOMAIN.LOCAL

    .EXAMPLE
    Choose VM host from a menu
    .\Connect-SSHPutty.ps1
    #>
    [cmdletbinding()]
    Param (
        [Parameter(Position=0)][string]$VMHostname,
        [Parameter(Position=1)][string]$Username,
        [string]$PuttyPath = "C:\scripts\putty.exe"
    )

    #Get all VMHosts
    Write-Host "Querying vCenter for VMHosts..." 
    try { $vmhosts = Get-VMHost -ErrorAction Stop | Sort-Object Name }
    catch { Write-Host $_.Exceptption.Message -ForegroundColor Red; Return }

    #Filter on $VMHostName
    if($VMHostname) { $vmhosts = $vmhosts | Where-Object{$_.name -like "*$VMHostname*"} }
    
    #Draw a menu of VMHosts
    if($vmhosts.count -ne 1) {
        Write-Host "Select a VMHost"
        for($i = 1; $i -lt $vmhosts.count+1; $i++) { Write-Host "[$i] $($vmhosts[$i-1].name)" }
        $option = Read-Host
    } else { $option = 0 }

    #Switch the chosen $option and assign $vmhost
    switch -Regex ($option) {
        "\d" { $vmhost = $vmhosts[$option-1] }
        default { Write-Host "$option - Invalid Option"; Return }
    }

    if(!(Test-Path $PuttyPath)) { Write-Host "$PuttyPath not found."; Return }
    try {
        #If SSH is not running, start it
        $ssh = Get-VMHost $vmhost -ErrorAction Stop | Get-VMHostService | Where-Object{$_.Key -eq "TSM-SSH"}
        if($ssh.Running -ne $true) { 
            Write-Host "[$vmhost] Starting SSH"
            $ssh | Start-VMHostService -confirm:$false
        }

        #Create argument list. Attempt to load credentials from SecureString
        $arglist = "-ssh "
        if($username) {
            $arglist += "$username@$vmhost "
            $pass = Get-SecureStringCredentials -Username $username -PlainPassword
            if($pass) { $arglist += "-pw $pass" }
        } else { $arglist += "$vmhost" }

        #Launch Putty with arguments
        Start-Process -FilePath $PuttyPath -ArgumentList $arglist -Wait

        #If SSH is Running, stop it
        $ssh = Get-VMHost $vmhost -ErrorAction Stop | Get-VMHostService | Where-Object{$_.Key -eq "TSM-SSH"}
        if($ssh.Running -eq $true) { 
            Write-Host "[$vmhost] Stopping SSH"
            $ssh | Stop-VMHostService -confirm:$false 
        }
    }
    catch { Write-Host $_.Exception.Message -ForegroundColor Red; Return }
}

function Get-DatastoreInventory {
    [cmdletbinding()]
    Param (
    )

    $inventory = @()
    Get-Datastore | Where-Object{$_.ExtensionData.Info.GetType().Name -eq "VmfsDatastoreInfo"} | ForEach-Object{
      if ($_) {
        Write-Host "[$($_.Name)] Collecting data"
        $ds = $_
        $inventory += $ds.ExtensionData.Info.Vmfs.Extent | Select-Object -Property @{Name="Datastore";Expression={$ds.Name}},@{Name="NAA.ID";Expression={$_.DiskName}}
      }
    }

    $inventory = $inventory | Select-Object -Unique -Property Datastore,"NAA.ID"
    if($inventory.count -gt 0) { Export-Results -results $inventory -exportName Datastore_Inventory }

    $rdm_inventory = @(Get-VM | Get-HardDisk -DiskType "RawPhysical","RawVirtual" | Select-Object Parent,Name,DiskType,ScsiCanonicalName,DeviceName)
    if($rdm_inventory.Count -gt 0) { Export-Results -results $rdm_inventory -exportName RDM_Inventory }
}

function Get-HBAFirmware {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost,
        $Driver = "lpfc"
    )

    process {
        if($VMHost.ConnectionState -eq "Connected" -or $VMHost.ConnectionState -eq "Maintenance") {
            Write-Verbose "[$($VMHost.Name)] Getting Firmware data"

            #Get data from ESXCLI
            $esxcli = Get-EsxCLI -VMHost $VMHost.Name -v2
            $nics = @($esxcli.network.nic.list.invoke())

            #Nic0
            $nicArgs = $esxcli.network.nic.get.createArgs()
            $nicArgs.nicname = $nics[0].name
            $nic0 = @($esxcli.network.nic.get.Invoke($nicArgs))

            #FCoE
            $fcoeArgs = $esxcli.system.module.get.createArgs()
            $fcoeArgs.module = $Driver
            $fcoe = $esxcli.system.module.get.Invoke($fcoeArgs)

            [pscustomobject][ordered]@{
                VMHost = $VMHost.Name
                NIC_Count = $nics.count
                FCoE_Driver = $fcoe.Version
                FCoE_Firmware = $nic0.DriverInfo.FirmwareVersion
                NIC_Driver = $nic0.driverinfo.Version
                NIC_Name = $nics[0].Description
            }
        } else {
            Write-Host "[$($VMHost.Name)] VMHost is not Connected or in Maintenance Mode"
        }
    }
}

function Get-VM_PortGroup_Mapping {
    $results = @()
    $vms = Get-vm
    Write-Host "Found $($vms.count) VMs"
    foreach($vm in $vms) {
        $cluster = Get-Cluster -VM $vm
        foreach($nic in (Get-NetworkAdapter -VM $vm)) {
            Write-Host "[$($vm.Name)] Reading configuration on $($nic.Name)"
            try { $pg = Get-VDPortgroup -NetworkAdapter $nic -ErrorAction Stop }
            catch { $pg = "ERROR" }
            try { $vds = Get-VDSwitch -RelatedObject $pg -ErrorAction Stop }
            catch { $vds = "ERROR" }
            $vc = $vm.uid | Where-Object{$_ -match "@(?<vcenter>.*):443"} | ForEach-Object{$matches['vcenter']}
            $results += [pscustomobject][ordered]@{
                VM = $vm.Name
                vCenter = $vc
                Cluster = $cluster.Name
                VM_NIC = $nic.Name
                PortGroup = $pg.Name
                VDS = $vds.Name
            }
        }
    }
    $results | Sort-Object VM
}

function Optimize-ClusterBalance {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true)]$cluster,
        $style = "Quick",
        $constraint = "vRAM",
        $exclusions = "(AVAMARPROXY.*|-CRITICALSERVER.*)",
        $vmotionlimit = 3,
        [switch]$whatif = $true
    )

    if($cluster -eq "all") {
        $cluster = @(get-cluster | select -expand name)
    }

    foreach($c in $cluster) {
        #Group the VMs into Types
        $types = GetVMTypes $c
        #Create a plan to balance the Types based on allocated VM Host CPU ratio round robin
        switch($style) {
            "RoundRobin" { $vmhosts = BalanceRoundRobin $c $types $constraint }
            "Quick" { $vmhosts = BalanceQuick $c $types $constraint }
        }
        CompareBeforeAfter $vmhosts 
        MigrateVMs -VMHosts $vmhosts -Cluster $c -WhatIf:$whatif
    }
}

function Convert-SRMxmlToDRcsv {
    <#
    .DESCRIPTION
    Used https://ssbkang.com/2016/02/09/powercli-report-review-srm-source-destination-network-settings as a reference
    C:\Program Files\VMware\VMware vCenter Site Recovery Manager\bin\?dr-ip-reporter.exe

    1. Generate a srm-export.xml by using dr-ip-reporter.exe on the VM with SRM 5.1
    dr-ip-reporter.exe --cfg "C:\Program Files\VMware\VMware vCenter Site Recovery Manager\config\vmware-dr.xml" --out "D:\temp\srm-export.xml" --vc "VCENTER.DOMAIN.LOCAL"

    2. Use this function to reswizzle the SRM export into three formats. For use with a script which updates DNS after SRM does the failover, this function resolves the 
    hostname for each VM, then exports a CSV of VMs with ProtectedIP and RecoveryIP. This export can be done for each protection group or as a single file.
    
    .EXAMPLE
    For migrating between SRM 5.1 to SRM 5.8+, a CSV with all Recovery Plan settings can be exported(nic index, ip, subnet, gateway, dns, suffixes)
    Convert-SRMxmlToDRcsv -SRMxmlExport .\srm-export.xml -fullExport

    .EXAMPLE
    Exports multiple CSVs of VMs with ProtectedIP and RecoveryIP for each Protection Group
    Convert-SRMxmlToDRcsv -byProtectionGroup

    .EXAMPLE
    Exports a CSV of VMs with ProtectedIP and RecoveryIP.
    Convert-SRMxmlToDRcsv -byProtectionGroup:$false
    #>
    [cmdletbinding(DefaultParameterSetName="Full")]
    param (
       $SRMxmlExport =  "C:\Scripts\srm-export.xml",
       [Parameter(ParameterSetName="DR")][switch]$byProtectionGroup = $false,
       [Parameter(ParameterSetName="Full")][switch]$fullExport = $false
    )
    [xml]$input_file = Get-Content $SRMxmlExport
    switch($PSCmdlet.ParameterSetName) {
        "DR" {
            $results = @()
            $input_file.DrMappings.ProtectionGroups.ProtectionGroup | Sort-Object Name | ForEach-Object {
                $protection_group = $_.Name
                $protected_ip = ""
                $recovery_ip = ""
                $_.ProtectedVm | Sort-Object Name | ForEach-Object {
                    $vm = $_.Name
                    try { $vm_hostname = [system.net.dns]::gethostbyname($vm).hostname }
                    catch { 
                        Write-Host "[$vm] Failed to query hostname from DNS. Defaulting to $vm.corporate.domain.local"
                        $vm_hostname = $vm + ".corporate.domain.local"
                    }
                    $_.CustomizationSpec | Sort-Object Site | ForEach-Object {
                        $ip_settings = $_.ConfigRoot.e.ipSettings
                        if($ip_settings) {
                            if($_.Site -eq "Site-1") {
                                $protected_ip = $ip_settings.ip.ipAddress
                            } elseif($_.Site -eq "Site-2") {
                                $recovery_ip = $ip_settings.ip.ipAddress
                            }
                        }
                    }
                    $results += [pscustomobject][ordered]@{
                        Hostname = $vm_hostname
                        ProtectedIP = $protected_ip
                        RecoveryIP = $recovery_ip
                    }
                }
                if($byProtectionGroup) {
                    Export-Results -results $results -exportName $protection_group -AppendTimestamp:$false
                    $results = @()
                }
            }
            if(!$byProtectionGroup) { Export-Results -results $results -exportName SRM_Export }
        }
        "Full" {
            $protection_groups = @()
            $input_file.DrMappings.ProtectionGroups.ProtectionGroup | Sort-Object Name | ForEach-Object {
                $protection_groups += [pscustomobject][ordered]@{
                    ProtectionGroup = $_.Name
                    ProtectionGroupID = $_.ID
                }
            }
            Write-Verbose "Detected $($protection_groups.count) protection groups"
            
            $recovery_plans = @()
            $input_file.DrMappings.RecoveryPlans.RecoveryPlan | Sort-Object Name | ForEach-Object {
                $id = $_.ProtectionGroup
                $protection_group = $protection_groups | Where-Object{$_.ProtectionGroupID -eq $id} | Select-Object -ExpandProperty ProtectionGroup
                $recovery_plans += [pscustomobject][ordered]@{
                    RecoveryPlan = $_.Name
                    ProtectionGroup = $protection_group
                }
            }
            Write-Verbose "Found $($recovery_plans.count) recovery plans"

            $results = @()
            $input_file.DrMappings.ProtectionGroups.ProtectionGroup | Sort-Object Name | ForEach-Object {
                $protection_group = $_.Name
                $_.ProtectedVm | Sort-Object Name | ForEach-Object {
                    $vm = $_.Name
                    $recovery_plan = $recovery_plans | Where-Object{$_.ProtectionGroup -eq $protection_group} | Select-Object -ExpandProperty RecoveryPlan
                    $_.CustomizationSpec | Sort-Object Site | ForEach-Object {
                        $site = $_.Site
                        $_.ConfigRoot.e | ForEach-Object {
                            $nic = $_.id
                            $ip_address = $subnetmask = $gateway = $dns0 = $dns1 = $dns2 = ""
                            $dnssuffix0 = $dnssuffix1 = $dnssuffix2 = $dnssuffix3 = $dnssuffix4 = ""
                            $ip_settings = $_.ipSettings
                            $dns_suffixes = $_.dnsSuffixes

                            if ($ip_settings) {
                                $ip_address = $ip_settings.ip.ipAddress
                                $subnetmask = $ip_settings.subnetMask
                                $gateway = $ip_settings.gateway.e."#text"
                                $ip_settings.dnsServerList.e | ForEach-Object { Set-Variable -Name "DNS$($_.id)" -Value $_."#text" }
                            }

                            if($dns_suffixes) {
                                $dns_suffixes.e | ForEach-Object { Set-Variable -Name "DNSSuffix$($_.id)" -Value $_."#text" }
                            }
                            $results += [pscustomobject][ordered]@{
                                ProtectionGroup = $protection_group
                                RecoveryPlan = $recovery_plan
                                VM = $vm
                                Site = $site
                                NIC = $nic
                                IPAddress = $ip_address
                                SubnetMask = $subnetmask
                                Gateway = $gateway
                                DNS0 = $dns0
                                DNS1 = $dns1
                                DNS2 = $dns2
                                DNSSuffix0 = $dnssuffix0
                                DNSSuffix1 = $dnssuffix1
                                DNSSuffix2 = $dnssuffix2
                                DNSSuffix3 = $dnssuffix3
                                DNSSuffix4 = $dnssuffix4
                            }
                        }
                    }
                }
            }
            Export-Results -results $results -exportName SRM_Full_Export
        }
    }
}

function Measure-Environment {
    $Types = @("Datacenter","ClusterComputeResource","Folder","HostSystem","VirtualMachine","Datastore","DistributedVirtualSwitch","VmwareDistributedVirtualSwitch","DistributedVirtualPortgroup","Network")
    foreach($_t in $Types) {
        $views = @(get-view -ViewType $_t -Property Name)
        Write-Host "$($views.count)`t`t$_t"
    }
}

Function Set-UsbDevice {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True,Position=1)]
        [string]$Name
    )
    
    #Get our VM then then ID
    $VM = Get-VM $Name  
    $Id = $VM.Id  
    
    #Create a new Virtual Machine Configuration Specification
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec 
    $deviceCfg = New-Object VMware.Vim.VirtualDeviceConfigSpec
    $deviceCfg.operation = "add"
    $deviceCfg.device = New-Object VMware.Vim.VirtualUSBController
    $deviceCfg.device.key = -1
    $deviceCfg.device.Connectable = New-Object VMware.Vim.VirtualDeviceConnectInfo
    $deviceCfg.Device.Connectable.StartConnected = $true
    $deviceCfg.Device.Connectable.AllowGuestControl = $false
    $deviceCfg.Device.Connectable.Connected = $true
    $devicecfg.Device.ControllerKey = 100
    $deviceCfg.Device.busNumber = -1
    $deviceCfg.Device.autoConnectDevices = $true
    $spec.DeviceChange += $deviceCfg
    
    #Apply the new spec
    $_this = Get-View -Id "$Id"  
    $_this.ReconfigVM_Task($spec)  
}

function Invoke-HostMath {
    param (
        [Parameter(ValueFromPipeLine=$True)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$vm,
        $label,
        $reportCSV = "C:\Scripts\Reports\HostMath.csv",
        [switch]$export = $false
    )
    begin {
        $vms = @()
        $g9_cores = 24
        $g9_memory = 512
        $g8_cores = 16
        $g8_memory = 256
        $g7_cores = 12
        $g7_memory = 192
    }

    process {
        $vms += $vm
    }
    End {
        if($label -eq $null) { $Label = "VMs" }

        $vms_cores = ($vms | Measure-Object -Sum -Property NumCPU).Sum
        $vms_memory = [system.math]::Ceiling(($vms | Measure-Object -Sum -Property MemoryGB).Sum)

        $vm_60_requiredgb = [system.math]::Ceiling(($vms_memory * 1.4))
        $vm_2to1_requiredcores = [system.math]::Ceiling(($vms_cores / 2))

        $g9_60_hosts = [system.math]::Ceiling($vm_60_requiredgb/$g9_memory)
        $g9_2to1_hosts = [system.math]::Ceiling(($vm_2to1_requiredcores / $g9_cores))

        $g8_60_hosts = [system.math]::Ceiling($vm_60_requiredgb/$g8_memory)
        $g8_2to1_hosts = [system.math]::Ceiling(($vm_2to1_requiredcores / $g8_cores))

        $g7_60_hosts = [system.math]::Ceiling($vm_60_requiredgb/$g7_memory)
        $g7_2to1_hosts = [system.math]::Ceiling(($vm_2to1_requiredcores / $g7_cores))

        $results = [pscustomobject][ordered]@{
            Label = $label
            VM_Count = $vms.count
            VM_Cores = $vms_cores
            VM_Memory = $vms_memory
            "VM_60%_Mem__ReqGB" = $vm_60_requiredgb
            "VM_CPU2to1__ReqCores" = $vm_2to1_requiredcores

            "G9_60%_Mem__Hosts" = $g9_60_hosts
            "G9_60%_Mem__CPURatio" =  [system.math]::Round(($vms_cores / ($g9_60_hosts *  $g9_cores)),1)
            "G9_CPU2to1__Hosts" = $g9_2to1_hosts
            "G9_CPU2to1__MemGB" =  ($g9_2to1_hosts * $g9_memory)

            "G8_60%_Mem__Hosts" = $g8_60_hosts
            "G8_60%_Mem__CPURatio" =  [system.math]::Round(($vms_cores / ($g8_60_hosts *  $g8_cores)),1)
            "G8_CPU2to1__Hosts" = $g8_2to1_hosts
            "G8_CPU2to1__MemGB" =  ($g8_2to1_hosts * $g8_memory)

            "G7_60%_Mem__Hosts" = $g7_60_hosts
            "G7_60%_Mem__CPURatio" =  [system.math]::Round(($vms_cores / ($g7_60_hosts *  $g7_cores)),1)
            "G7_CPU2to1__Hosts" = $g7_2to1_hosts
            "G7_CPU2to1__MemGB" =  ($g7_2to1_hosts * $g7_memory)
        }

        if($export) {
            if(!(Test-Path $reportCSV)) {
                Write-Host "Exporting results to $reportCSV" -ForegroundColor Green
                $results | Export-Csv $reportCSV -NoTypeInformation
            } else {
                $report = @(Import-Csv $reportCSV)
                Write-Host "Appending results to $reportCSV" -ForegroundColor Green
                $report += $results
                $report | Export-Csv $reportCSV -NoTypeInformation
            }
        } else {
            $results
        }
    }
}

function Export-1000v {
    [cmdletbinding()]
    Param (
    )

    try { 
        WriteLog "Initialization" "Getting DVS data"
        $dvs  = @(Get-VDSwitch  -ErrorAction Stop | Sort-Object Name)
        $vcenter = $dvs[0].uid | Where-Object{$_ -match "@(?<vcenter>.*):443"} | ForEach-Object{$matches['vcenter']}
    }
    catch { WriteLog "ERROR" "Failed to get DVS data" "Red"; Return }

    $results = @()
    foreach($_d in $dvs) {
        $vdsname = "$($_d.name)"
        WriteLog "$vdsname" "Getting configuration"
        try {
            $dvpgs = Get-VDPortgroup -VDSwitch $_d -ErrorAction Stop | Sort-Object Name
            foreach($_dvpg in $dvpgs) {
                $vlan = $null
                $vlan = $_dvpg.vlanconfiguration.vlanid
                $pgname = $_dvpg.Name
                if(!$vlan) {
                    $pgName | Where-Object{$_ -match "VLAN_(?<vlanid>[0-9]*)_.*"} | ForEach-Object{
                        if($matches['vlanid']) {
                            $vlan = $matches['vlanid']
                            WriteLog "$vdsname" "$pgname [VLAN == $vlan ]"
                        }
                    }
                }
                $results += [pscustomobject][ordered]@{
                    N1K = $vdsname
                    PortGroup = $pgname
                    VLANID = $vlan
                    NumPorts = $_dvpg.NumPorts
                    PortBinding = $_dvpg.PortBinding
                }
            }
        }
        catch { WriteLog "ERROR" $_.Exception.Message $logfile "Red" }
    }
    Export-Results -results $results -exportName "1000v_Export_$($vCenter)"
}

function Import-1000v {
    [cmdletbinding()]
    param (
        $1000v_CSV
    )

    $portgroups = Import-Csv $1000v_CSV
    $dvs = @($portgroups | Select-Object -Unique N1K | Select-Object -ExpandProperty N1K | Sort-Object)

    foreach($_d in $dvs) {
        try {
            $vdspgs = $portgroups | Where-Object{$_.N1K -eq $_d -and $_.VLANID}
            $vdspgs_skipped = $portgroups | Where-Object{$_.N1K -eq $_d -and !($_.VLANID)}
            foreach($_pg in $vdspgs_skipped) {
                WriteLog "$_d" "No VLANID defined for $($_pg.PortGroup). Skipping"
            }
            if($vdspgs[0].ImportVDS) { $vdsname = $vdspgs[0].ImportVDS }
            else { $vdsname = Read-Host "[$_d] Which VDS should this configuration be imported into?" }
            $vds_obj = Get-VDSwitch -Name $vdsname -ErrorAction Stop
            WriteLog "$vdsname" "VDS found"
        }

        catch {
            if($_.Exception.Message -like "*was not found using the specified filter*") {
                WriteLog "$vdsname" "VDS does not exist. Creating..."

                if($vdspgs[0].ImportDatacenter) { $datacenter = $vdspgs[0].ImportDatacenter }
                else { $datacenter = Read-Host "[$vdsname] Which Datacenter should this be created in?" }

                $datacenter_obj = Get-Datacenter -Name $datacenter
                if($datacenter_obj) {
                    New-VDSwitch -Name $vdsname -Location $datacenter_obj -NumUplinkPorts 2
                    $vds_obj = Get-VDSwitch -Name $vdsname -ErrorAction Stop
                } else {
                    WriteLog "$vdsname" "Failed to find $datacenter datacenter"
                }
            } else {
                WriteLog "ERROR" $_.Exception.Message
            }
        }

        $vdsCurrentpgs = @(Get-VDPortgroup -VDSwitch $vds_obj)
        foreach($_pg in $vdspgs) {
            $pg_name = $_pg.PortGroup
            if(@($vdsCurrentpgs | Where-Object{$_.Name -eq $pg_name}).count -eq 0) {
                WriteLog "$vdsname" "$pg_name does not exist. Creating"
                New-VDPortgroup -VDSwitch $vds_obj -Name $pg_name -VlanId $_pg.VLANID -NumPorts 256
            } else {
                WriteLog "$vdsname" "$pg_name already exists. Skipping"
            }
        }
    }

}

function Export-VCRoles {
    [cmdletbinding()]
    param (
    )
    $roles = Get-VIRole | Where-Object{$_.IsSystem -eq $false}
    $vcenter = Get-vCenterFromUID $roles[0].Uid

    $results = @()
    foreach ($role in $roles) {
        WriteLog "$($role.name)" "Getting Privileges"
        $privs = Get-VIPrivilege -Role $role 
        foreach($_p in $privs) {
            $results += [pscustomobject][ordered]@{
                Role = $role.Name
                Description = $role.Description
                RoleID = $role.Id
                ID = $_p.Id
            }
        }
    }
    Export-Results -exportName "$($vCenter)_Role_Privileges" -results $results
}

function Import-VCRoles {
    [cmdletbinding()]
    param (
        $CSV
    )

    $privs = Import-Csv $CSV
    $roles_ids = $privs | Select-Object RoleID -Unique -ExpandProperty RoleID
    $roles_obj = Get-VIRole

    foreach($_id in $roles_ids) {
        $role_privs_new = $privs | Where-Object{$_.RoleID -eq $_id}
        if([int]$_id -lt 5000) {
            $role_name = $role_privs_new[0].Role
        } else {
            $role_name = $role_privs_new[0].Description
        }
        
        if($roles_obj.Name.Contains($role_name)) {
            WriteLog "$role_name" "Role exists" -fcolor "Green"
        } else {
            WriteLog "$role_name" "Creating role" -fcolor "Yellow"
            New-VIRole -Name $role_name
        }

        $role_privs_current = @(Get-VIRole $role_name | Get-VIPrivilege)
        foreach($_p in $role_privs_new) {
            if($role_privs_current.id.Contains($_p.Id) -eq $false) {
                WriteLog "$role_name" "Adding $($_p.Id) to role" -fcolor "Yellow"
                try {
                    $priv_new = Get-VIPrivilege -Id $_p.Id -ErrorAction Stop
                    Set-VIRole -Role $role_name -AddPrivilege $priv_new
                }
                catch {
                    WriteLog "$role_name" "$($_p.ID) privilege does not exist" -fcolor "Red"
                }
                
            } else {
                WriteLog "$role_name" "$($_p.Id) prviliege already exists" -fcolor "Green"
            }
        }
    }
}

function Export-VCFolders {
    [cmdletbinding()]    
    $folders = Get-Folder
    $vcenter = Get-vCenterFromUID $folders[0].Uid

    $results = @()
    foreach($_f in $folders) {
        Write-Host "Working on $($_f.Name)"
        $fpath = Get-FolderPath -Folder $_f

        $results += [pscustomobject][ordered]@{
            Folder = $fpath.Name
            Parent = $fpath.Parent
            Path = $fpath.Path
            Type = $fpath.Type
        }
    }

    Export-Results -results $results -exportName "$($vcenter)_FolderPaths"
}

function Import-VCFolders {
    [cmdletbinding()]
    param (
        $CSV
    )

    $folders = Import-Csv $csv | Where-Object{$_.Type -eq "blue" -and $_.Folder -ne "vm"}

    foreach($_f in ($folders | Where-Object{$_.Parent -eq "vm"})) {
        try { 
            Get-Folder -Name $_f.Folder -ErrorAction Stop | Out-Null
            Write-Host "$($_f.Folder) Folder already exists"
        }
        Catch { 
            Write-Host "Creating $($_f.Folder)"
            New-Folder -Name $_f.Folder -Location (Get-Folder vm) }
    }

    foreach($_f in ($folders | Where-Object{$_.Parent -ne "vm"})) {
        try { 
            Get-Folder -Location $_f.Parent -Name $_f.Folder -ErrorAction Stop | Out-Null
            Write-Host "$($_f.Folder) Folder already exists in $($_f.Parent)"
        }
        Catch { 
            Write-Host "Creating $($_f.Folder)"
            New-Folder -Name $_f.Folder -Location (Get-Folder $_f.Parent) }
    }
}

function Start-MigrationMonitor {
    [cmdletbinding()]
    param (
        $servers = ".\mgtest.txt",
        [string]$label,
        $throttle = 5
    )

    $rscompleted = 0
    Get-RSJob | Where-Object{$_.State -eq "Completed"} | Remove-RSJob -ErrorAction SilentlyContinue
    $GuestCredentials = Get-SecureStringCredentials $global:AdminUsername

    if($servers.EndsWith(".txt")) { 
        $serverlist = @(Get-Content $servers) 
    } else { $serverlist = @($servers) }

    #Populate $ServerStatus with initial values
    $ServerStatus = @()
    foreach($_s in $serverlist) {
        $ServerStatus += [pscustomobject][ordered]@{
            "Server" = $_s
            "IP" = "Unknown"
            "PingIP" = "Unknown"
            "PingVM" = "Unknown"
            "WMIVM" = "Unknown"
        }
    }
    #$ServerStatus = $ServerStatus | Sort Server
    
    $mode = "Testing"
    $refresneeded = $true
    while($mode -ne "Validation") {
        #Get results from completed runspaces and update $ServerStatus
        $rsjobs_complete = @(Get-RSJob | Where-Object{$_.state -eq "Completed" -and $_.Name -like "MV__*"})
        if($rsjobs_complete.Count -gt 0) {
            Write-Verbose "Processing $($rsjobs_complete.count) complete runspaces"
            foreach($rsjob in $rsjobs_complete) {
                $rsjob_results = Receive-RSJob -Id $rsjob.ID
                $rsjob_server = ($rsjob.name -split "_+")[1]
                $rsjob_test = ($rsjob.name -split "_+")[2]
                ($ServerStatus | Where-Object{$_.Server -eq $rsjob_server}).$rsjob_test = $rsjob_results
                $rscompleted++
                Remove-RSJob -Id $rsjob.ID
            }
            $refreshneeded = $true
        } else { $refreshneeded = $false }

        #Change the $mode to Validation after all testing has finished
        $completed = @($ServerStatus | Where-Object{$_.IP -notmatch "(Unknown|Testing)" -and $_.PingIP -match "(Pass|Fail|Unknown)" -and $_.PingVM -match "(Pass|Fail)" -and $_.WMIVM -match "(Pass|Fail)" -and $_.InvokeVM -match "(Pass|Fail)"})
        if($completed.count -eq $ServerStatus.count) { $mode = "Validation" }

        #Display the current $ServerStatus
        $rsjobs = @(Get-RSJob)
        if($refreshneeded) {
            #Read-Host

            Clear-Host
            if($label) {  Write-Host "Label: `t`t`t`t$Label" }
            #Write-Host "Mode:`t`t`t`t$mode"
            Write-Host "Completed:`t`t`t$($completed.count)/$($serverstatus.count)"
            Write-Host "Runspaces Active/Completed:`t$($rsjobs.count)/$rscompleted"
            $ServerStatus | Format-Table | Out-String | ColorWord2 -word 'Fail','Pass' -color 'Red','Green'
        }

        $i = 0
        $tests = @("IP","PingIP","PingVM","WMIVM","InvokeVM")
        :outer foreach($server in $ServerStatus) {
            foreach($test in $tests) {
                $rsscript = $null
                $arglist = @{}

                if($server.$test -eq "Unknown") {
                    switch($test) {
                        "IP" {
                            $vm = Get-VM $server.Server -ErrorAction SilentlyContinue
                            #Get the last IPv4 address
                            if($vm) { $arglist = @($vm.Guest.IPAddress | Where-Object{$_ -notlike "*:*" -and $_ -notlike "169.*"} | Select-Object -Last 1) } 
                            else { $arglist = @($null) }
                            
                            $rsscript = {
                                param($ip)
                                if($ip -ne $null) {
                                    return $ip
                                } else { return 'Fail' }
                            }
                        }
                        "PingIP" {
                            if($server.IP -ne "Unknown" -and $server.IP -ne "Testing" -and $server.IP -ne "Fail") {
                                $arglist = @($server.IP)
                                $rsscript = {
                                    param ($Computername)
                                    try {
                                        if(Test-Connection -ComputerName $Computername -Count 1 -ErrorAction Stop) {
                                            return 'Pass'
                                        } else { return 'Fail' }
                                    }
                                    catch { return 'Fail' }
                                }
                            }
                        }
                        "PingVM" {
                            $arglist = @($server.Server)
                            $rsscript = {
                                param($ComputerName)
                                try {
                                    if(Test-Connection -ComputerName $ComputerName -Count 1 -ErrorAction SilentlyContinue) {
                                        return 'Pass'
                                    } else { return 'Fail' }
                                }
                                catch { return 'Fail' }
                            }
                        }
                        "WMIVM" {
                            $arglist = @($server.Server,$GuestCredentials)
                            $rsscript = {
                                param($ComputerName, $GuestCredentials)
                                try {
                                    if(Get-WmiObject -ComputerName $ComputerName -Class win32_operatingsystem -cred $GuestCredentials -ErrorAction Stop) {
                                        return 'Pass'
                                    } else { return 'Fail' }
                                }
                                catch { return 'Fail' }
                            }
                        }
                        "InvokeVM" {
                            $arglist = @($server.Server,$GuestCredentials)
                            $rsscript = {
                                param($ComputerName, $GuestCredentials)
                                try {
                                    if(Invoke-VMScript -VM $ComputerName -ScriptText 'Get-wmiObject -class win32_operatingsystem' -GuestCredential $GuestCredentials -ScriptType Powershell -ErrorAction Stop) {
                                        return 'Pass'
                                    } else { return 'Fail' }
                                }
                                catch { return 'Fail' }
                            }
                        }
                    }
                } elseif($server.$test -like "Fail x*") {
                    $failcount = ($server.$test).Substring(5)
                    switch($test) {
                        "IP" {
                            $vm = Get-VM $server.Server -ErrorAction SilentlyContinue
                            #Get the last IPv4 address
                            if($vm) { $arglist = @($vm.Guest.IPAddress | Where-Object{$_ -notlike "*:*" -and $_ -notlike "169.*"} | Select-Object -Last 1) } 
                            else { $arglist = @($null) }
                            
                            $rsscript = {
                                param($ip)
                                if($ip -ne $null) {
                                    return $ip
                                } else { return "Fail x$failcount" }
                            }
                        }
                    }
                }

                #Start a runspace
                if($rsscript -ne $null) {
                    $server.$test = "Testing"
                    Write-Verbose "[$($server.Server)] Starting $test test"
                    Start-RSJob -Name "MV__$($server.Server)__$test" -ArgumentList $arglist -ScriptBlock $rsscript -Throttle 15 | Out-Null
                    $i++
                    if($i -ge $throttle) { break outer }
                }
            }
        }
        Start-Sleep -Milliseconds 250
    }

    if($ServerStatus -and $label) {
        $serversclean = $servers | ForEach-Object{$_ -replace ".txt" -replace "\." -replace "\\"}
        Export-Results -results $ServerStatus -exportName MigrationValidation_$($serversclean)_$label
    }

    if($mode -eq "Validation" -and $label -eq "6.0") {
        Test-MigrationResults -servers $servers
    }
}

function Get-VMGuestNetwork {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM,
        [Parameter(Mandatory=$true)][string]$GuestUser,
        [Parameter(Mandatory=$true)][string]$GuestPassword 
    )

    $vmoutput = Invoke-VMScript -ScriptText '(get-netipaddress | ?{$_.AddressFamily -eq "IPv4" -and $_.IPAddress -ne "127.0.0.1"} | Select InterfaceAlias,InterfaceIndex,IpAddress | ConvertTo-CSV)' `
                -ScriptType Powershell -VM $vm -GuestUser $GuestUser -GuestPassword $GuestPassword

    if($vmoutput.ExitCode -eq 0) {
        #Write-Host "[$($vm.name)] Invoke-VMScript ran successfully"
        $nics = @($vmoutput.ScriptOutput | ConvertFrom-Csv)
        #Write-Host "[$($vm.name)] Found $($nics.count) NIC"
        foreach($_n in $nics) {
            Write-Host "[$($vm.name)] Interface=[$($_n.InterfaceAlias)] CurrentIP=[$($_n.IPAddress)]"
        }
        return $nics
    } else {
        Write-Host "[$($vm.name)] Invoke-VMScript returned Exit Code of $($vmoutput.ExitCode)"
        Return
    }
}

function Set-VMGuestNetwork {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$vm,
        [Parameter(Mandatory=$true)][string]$GuestUser,
        [Parameter(Mandatory=$true)][string]$GuestPassword,
        [string]$nicAlias,
        [string]$nicIP,
        $nicMask,
        $nicGateway
    )
    Write-Host "[$($vm.name)] Changing IP for interface $nicAlias to $nicIP"
    $changingIp = '%WINDIR%\system32\netsh.exe interface ipv4 set address name="' + $nicAlias + '" source=static address=' + $nicIP + ' mask=' + $nicMask + ' gateway=' + $nicGateway + ' gwmetric=1 store=persistent'
    $out = Invoke-VMScript -ScriptText $changingIp -ScriptType bat -VM ($vm.name) -GuestUser $GuestUser -GuestPassword $GuestPassword
}

function Start-DatastoreMigration {
    [cmdletbinding()]
    Param (
        [Parameter(ParameterSetName="VM")]$SourceVM,
        [Parameter(ParameterSetName="Datastore")]$SourceDatastore,
        [Parameter(ParameterSetName="DatastoreCluster")]$SourceDatastoreCluster,
        [Parameter(ParameterSetName="MigrationGroup")]$MigrationGroup,
        $MigrationGroupFile = "Migration_Groups.xlsx",
        $DestinationDatastoreCluster,
        $DestinationDatastore,
        $transferlimit = 100000,
        $svmotionlimit = 2,
        $FillDatastorePercent = 75,
        $Confirm = $false
    )

    switch($PSCmdlet.ParameterSetName) {
        "VM" {
            WriteLog "Prep" "Getting VM objects"
            if($SourceVM.EndsWith(".txt")) {
                if(Test-Path($SourceVM)) {
                    $SourceVM = Get-Content "$SourceVM"
                } else {
                    $SourceVM = Get-Content "$PSScriptRoot\$SourceVM"
                }
            }
            
            $allVMs = Get-VM
            $vmsObj = @()
            foreach($_s in $SourceVM) {
                $vmsObj += @($allVMs | ?{$_.Name -eq $_s}) 
            }
        }
        "Datastore" {
            if($SourceDatastore.EndsWith(".txt")) { $SourceDatastore = @(Get-Content $SourceDatastore) }
            $vmsObj = Get-Datastore $SourceDatastore | Get-VM | Sort-Object Name
        }
        "DatastoreCluster" {
            $vmsObj = Get-DatastoreCluster $SourceDatastoreCluster | Get-Datastore | Get-VM | Sort-Object Name
        }
        "MigrationGroup" {
            if(Test-Path($MigrationGroupFile)) {
                $MigrationGroups = Import-Excel $MigrationGroupFile
            } else {
                $MigrationGroups = Import-Excel "$PSScriptRoot\$MigrationGroupFile"
            }
            $thisMG = @($MigrationGroups | ?{$_."Migration Group" -eq $MigrationGroup})
            
            

            $allVMs = Get-VM
            $vmsObj = @()
            foreach($_s in $thisMG) {
                $vmsObj += @($allVMs | ?{$_.Name -eq $_s.Name}) 
            }

        }
    }

    WriteLog "Prep" "Getting HardDisk objects"
    $disks = $vmsObj | Get-HardDisk
    if($DestinationDatastoreCluster) { 
        $dest = $DestinationDatastoreCluster 
        $destDatastores = Get-DatastoreCluster $dest | Get-Datastore
    }
    elseif($DestinationDatastore) { $dest = $DestinationDatastore }
    else { 
        WriteLog "Prep" "Destination required" 
        Return
    }

    $vmdks = @()
    foreach($_d in $disks) {
        $dsName = $_d.FileName.Split(']')[0].TrimStart('[')
        if($SourceDatastore) {
            #If migrating from a SourceDatastore, only migrate VMDKs from the SourceDatastore
            if($SourceDatastore -contains $dsName) {
                WriteLog "Plan" "Adding $($_d.Filename) to VMDK list"
                $vmdks += $_d
            } else {
                WriteLog "Plan" "Skipping $($_d.Filename)"
            }
        } elseif($DestinationDatastoreCluster -and $destDatastores.Name.Contains($dsname)) {
            #If migrating to a DestinationDatastoreCluster, only migrate VMDKs which aren't already on the datastore cluster
            WriteLog "Plan" "Skipping $($_d.Filename). Already on $DestinationDatastoreCluster"
        } else {
            WriteLog "Plan" "Adding $($_d.Filename) to VMDK list"
            $vmdks += $_d
        }
    }
               
    WriteLog "Plan" "Finding smallests VMDKs to migrate"           
    $tomove = @(); $tomovesize = 0
    $vmdks = $vmdks | Sort-Object CapacityGB; $i = 0
    while($tomovesize -lt $transferlimit -and $i -lt $vmdks.count) {
        $smallvmdk = $vmdks[$i]
        $smallvmdkused = [math]::Round($smallvmdk.CapacityGB,2)
        if(($smallvmdkused + $tomovesize) -lt $transferlimit) { 
            WriteLog "Plan" "$($smallvmdk.filename): $smallvmdkused GB VMDK added to queue"
            $tomove += $smallvmdk
        } else { 
            WriteLog "Plan" "Transfer limit $transferlimit GB reached"
            break 
        }
        $tomovesize = ($tomove | Measure-Object -Sum -Property CapacityGB).sum; $i++
    }

    WriteLog "Verify" "$("{0:N2}" -f $tomovesize) GB in $($tomove.count) VMDKs will be migrated $svmotionlimit at a time to $dest"
    $tomove | Select-Object Parent,Filename,CapacityGB | Out-Default
    
    if($confirm -ne $true) {
        $option = Read-Host "continue, exit"
        switch($option) {
            "continue" { }
            "c" { }
            "exit" { Exit }
            default { Exit }
        }
    }

    foreach($vmdk in $tomove) {
        $success = $false
        $w = 0
        while($success -ne $true) {
            $tasks = @(get-task -status Running | Where-Object{$_.name -like "*RelocateVM_Task*"})
            if($tasks.count -lt $svmotionlimit) {
                if($DestinationDatastoreCluster) {
                    MoveVMDK -vmdk $vmdk -DestinationDatastoreCluster $dest -FillDatastoreFirst:$true -FillDatastorePercent $FillDatastorePercent
                } elseif($DestinationDatastore) {
                    MoveVMDK -vmdk $vmdk -DestinationDatastore $dest -FillDatastorePercent $FillDatastorePercent
                }
                $success = $true
                Start-Sleep -Seconds 5
            } else {
                $w++
                if($w -eq 1) {
                    WriteLog "Waiting for other svMotions" ""
                } elseif($w -eq 4) {
                    $w = 0
                }
                Start-Sleep -Seconds 15
            }
        }
    }
}

function Move-VMConfig {
    [cmdletbinding()]
    param (
        [Parameter(Position=0,ParameterSetName="VM")]$Name,
        [Parameter(Position=0,ParameterSetName="MigrationGroup")]$MigrationGroup,
        $MigrationGroupFile = "Migration_Groups.xlsx",
        $svMotionLimit = 1
    )

    switch($PSCmdlet.ParameterSetName) {
        "VM" {
            WriteLog "Prep" "Getting VM objects"
            $vms = @()
            if($Name.EndsWith(".txt")) {
                if(Test-Path($Name)) {
                    $VMList = Get-Content $Name
                } else {
                    $VMList = Get-Content "$PSScriptRoot\$Name"
                }
                $allVMs = Get-VM
                foreach($_vm in $VMList) {
                    $vms += @($allVMs | ?{$_.Name -eq $_vm}) 
                } 
            } else {
                $VMs += Get-VM $Name
            }
        }

        "MigrationGroup" {
            if(Test-Path($MigrationGroupFile)) {
                $MigrationGroups = Import-Excel $MigrationGroupFile
            } else {
                $MigrationGroups = Import-Excel "$PSScriptRoot\$MigrationGroupFile"
            }
            $thisMG = @($MigrationGroups | ?{$_."Migration Group" -eq $MigrationGroup})
            
            $allVMs = Get-VM
            $vmsObj = @()
            foreach($_s in $thisMG) {
                $vms += @($allVMs | ?{$_.Name -eq $_s.Name}) 
            }
        }
    }

    foreach($vm in $vms) {
        $disk1 = Get-HardDisk -VM $vm | Select-Object -First 1
        $disk1ds = $disk1.FileName.Split(']')[0].TrimStart('[')

        $vm_vmx = ($vm.ExtensionData.LayoutEx.File | Where-Object{$_.Name -like "*.vmx"}).Name
        $vm_vmx_ds = $vm_vmx.Split(']')[0].TrimStart('[')
        if($vm_vmx_ds -ne $disk1ds) {
            $moveNeeded = $true
        } else {
            WriteLog "Prep" "[$($vm.Name)] Configuration files already on $disk1ds"
            $moveNeeded = $false
        }

        while($moveNeeded) {
            $w = 0
            $tasks = @(Get-Task | Where-Object{$_.name -like "*RelocateVM_Task*" -and $_.State -ne "success"})
            if($tasks.count -lt $svMotionLimit) {
                WriteLog "Migration" "[$($vm.Name)] svMotioning configuration files from $vm_vmx_ds to $disk1ds"

                $destinationds = Get-Datastore -Name $disk1ds

                $spec = New-Object VMware.Vim.VirtualMachineRelocateSpec
                $spec.Datastore = $destinationds.Extensiondata.Moref

                Get-HardDisk -VM $vm | %{
                    $disk = New-Object VMware.Vim.VirtualMachineRelocateSpecDiskLocator
                    $disk.diskId = $_.Extensiondata.Key
                    $disk.datastore = $_.Extensiondata.Backing.Datastore
                    $spec.disk += $disk
                }

                $vm.ExtensionData.RelocateVM_Task($spec, "defaultPriority") | Out-Null
                Start-Sleep -Seconds 5
                break
            } else {
                $w++
                if($w -eq 1) {
                    WriteLog "Waiting for other svMotions" ""
                } elseif($w -eq 4) {
                    $w = 0
                }
                Start-Sleep -Seconds 15
            }
        }
    }
}

function Get-VMDisks {
    [cmdletbinding()]
    param (
        [Parameter(ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM
    )

    process {
        $VMView = Get-View -VIObject $vm

        $results = @()
        ForEach ($VirtualSCSIController in ($VMView.Config.Hardware.Device | Where-Object {$_.DeviceInfo.Label -match "SCSI Controller"})) {
            ForEach ($VirtualDiskDevice  in ($VMView.Config.Hardware.Device | Where-Object {$_.ControllerKey -eq $VirtualSCSIController.Key})) {
                $results += [pscustomobject][ordered]@{
                    VM = $VM.Name
                    HostName = $VMView.Guest.HostName
                    PowerState = $VM.PowerState
                    DiskFile = $VirtualDiskDevice.Backing.FileName
                    DiskName = $VirtualDiskDevice.DeviceInfo.Label
                    DiskSizeKB = $VirtualDiskDevice.CapacityInKB * 1KB
                    DiskSizeGB = $VirtualDiskDevice.CapacityInKB / 1024 / 1024
                    BusNumber = $VirtualSCSIController.BusNumber
                    UnitNumber = $VirtualDiskDevice.UnitNumber
                }
            }
        }
        $results
    }
}

function Expand-VMDisk {
    <#
    .Example
    Get-VM VMName | Get-HardDisk | Select-Object -Last 1 | Expand-VMDisk
    #>
    [cmdletbinding()]
    param (
        [Parameter(ValueFromPipeline=$true)]$HardDisk,
        $expandScript = "C:\Scripts\GuestDiskExpansion_Windows2012-part1.ps1",
        $expandScriptCustom = "C:\Scripts\GuestDiskExpansion_Windows2012_Custom.ps1"
    )

    begin {
        $cred = Get-SecureStringCredentials -Username "Dev\user.Dev" -Credentials
        $localcred = Get-SecureStringCredentials -Username "Administrator" -Credentials
        $localpass = Get-SecureStringCredentials -Username "Admin" -PlainPassword
    }

    process {
        $vm = Get-VM -Name $HardDisk.Parent
        $vmdisk = @(Get-VMDisks -VM $vm | Where-Object{$_.DiskFile -eq $HardDisk.Filename})
        if($vmdisk.count -eq 1) {
            Write-Host "[$($vmdisk.BusNumber):$($vmdisk.UnitNumber)] Disk filename is $($HardDisk.Filename)"

            #Customize expand script and output to file
            $script1 = Get-Content $expandScript -Raw | ForEach-Object{ $_ -replace "BUSSCSI",$vmdisk.BusNumber -replace "TARGETSCSI",$vmdisk.UnitNumber } #| Out-File $expandScriptCustom
            $script1

            #Copy customized expand script to VM
            #Copy-VMGuestFile -LocalToGuest -Source $expandScriptCustom -Destination C:\temp\GuestDiskExpansion.ps1 -VM $($vm.name) -Force # -GuestCredential $localcred -HostCredential $cred

            #Run custuomized expand script on VM
            #$credxml = Import-Clixml
            #$testscript = "$testcred = (New-Object -TypeName System.Management.Automation.PSCredential -argumentlist admin,($pass_string | ConvertTo-SecureString));Start-Process powershell -ArgumentList '-noprofile -noninteractive -command C:\temp\GuestDiskExpansion.ps1'"
            #$testscript = "C:\temp\GuestDiskExpansion.ps1"
            Invoke-VMScript -VM $vm -ScriptText $script1 -GuestUser "admin" -GuestPassword $localpass -ScriptType Powershell #| Select-Object -ExpandProperty ScriptOutput
        }
    }
}

function Invoke-DisableDeleteCoredumpFile {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
    )

    process {
        Write-Host "[$($vmhost.Name)] Disabling & deleting coredump file"
        $esxcli = Get-EsxCli -VMHost $vmhost -V2
    
        $esxargs = $esxcli.system.coredump.file.set.CreateArgs()
        $esxargs.enable = $false
        $esxcli.system.coredump.file.set.Invoke($esxargs)

        $esxargs = $esxcli.system.coredump.file.remove.CreateArgs()
        $esxargs.force = $true
        $esxcli.system.coredump.file.remove.Invoke($esxargs)
    }
}

function Get-VMHostAdvancedSetting {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost,
        [Parameter(Mandatory=$true)]$Name
    )

    process {
        Get-AdvancedSetting -Entity $VMHost -Name $Name | Select-Object Entity,Name,Value
    }
}

function Set-VMHostAdvancedSetting {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost,
        [Parameter(Mandatory=$true)]$Name,
        [Parameter(Mandatory=$true)]$Value
    )

    process {
        $setting = Get-AdvancedSetting -Entity $VMHost -Name $Name

        if($setting.Value -ne $Value) {
            Write-Host "[$($VMHost.Name)] Setting $Name to $value"
            Set-AdvancedSetting -AdvancedSetting $setting -Value $Value -Confirm:$false
        } else {
            Write-Host "[$($VMHost.Name)] $Name already set to $value" -ForegroundColor Green
        }
    }
}

$esxi_hardening = @{
    "UserVars.ESXiShellInteractiveTimeOut" = 900
    "UserVars.ESXiShellTimeOut" = 900
    "Security.AccountUnlockTime" = 900
    "Security.AccountLockFailures" = 3
    "Security.PasswordQualityControl" = "retry=3 min=disabled,disabled,disabled,8,8"
}

function Get-VMHostHardening {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
    )

    process {
        foreach($key in $esxi_hardening.Keys) {
            $value = $esxi_hardening.Item($key)
            $current = Get-VMHostAdvancedSetting -VMHost $VMHost -Name $key
            if($current.Value -eq $value) {
                Write-Host "[$($VMHost.Name)] '$key' already set to $value" -ForegroundColor Green
            } else {
                Write-Host "[$($VMHost.Name)] '$key' doesn't match $value" -ForegroundColor Red
            }
        }
    }
}

function Set-VMHostHardening {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
    )

    process {
        foreach($key in $esxi_hardening.Keys) {
            $value = $esxi_hardening.Item($key)
            Set-VMHostAdvancedSetting -VMHost $VMHost -Name $key -value $value
        }
    }
}

function Measure-VMHostDatastores {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
    )

    process {
        $datastores = $vmhost | Get-Datastore

        $VMHost | Select-Object Name,@{Name="Datastores";Expression={$datastores.Count}}
    }
}

function Test-SRMRecoveryPlan {
    [cmdletbinding()]
    param (
        $RecoveryPlan = "RP_SRM_Testing"
        
    )

    #connect to srm
    $srm = Connect-SrmServer
    $srmapi = $srm.ExtensionData

    #find the recovery plan
    $RecoveryPlans = $srmapi.Recovery.ListPlans()
    foreach($_rp in $RecoveryPlans) {
        $rp_info = $_rp.GetInfo()
        if($rp_info.Name -eq $RecoveryPlan) {
            $rp = $_rp
            break
        }
    }

    Write-Host "$RecoveryPlan found at $($rp.moref)"

    #if the status is not ready, abort
    if($rp_info.State -eq "Protecting") {
        Write-Host "Recovery Plan testing needs to be initiated from the other SRM instance. Aborting" -ForegroundColor Red
        Return
    } elseif($rp_info.State -ne "Ready") {
        Write-Host "Recovery plan is '$($rp_info.State)' instead 'Ready.' Aborting" -ForegroundColor Red
        Return
    }

    #ask for confirmation, then start testing
    Read-Host "Recovery Plan is Ready. Press Enter to start Testing"
    [VMware.VimAutomation.Srm.Views.SrmRecoveryPlanRecoveryMode] $RecoveryMode = 'Test'
    $rp.Start($RecoveryMode)
    $rp_info = $rp.GetInfo()

    #wait for testing to finish
    while($rp_info.State -ne "NeedsCleanup") {
        Write-Host "Recovery Plan Test is '$($rp_info.State)'..."
        Start-Sleep -Seconds 10
        $rp_info = $rp.GetInfo()
    }

    #report test status
    Write-Host "Recovery Plan Test completed"
    $test_results = ($srmapi.Recovery.GetHistory($rp.Moref)).GetRecoveryResult(1)
    $test_results

    #ask for confirmation, then start test cleanup
    Read-Host "Press Enter to start Cleanup"

    #start cleanup
    [VMware.VimAutomation.Srm.Views.SrmRecoveryPlanRecoveryMode] $RecoveryMode = 'Cleanup'
    $rp.Start($RecoveryMode)
    $rp_info = $rp.GetInfo()

    #wait for cleanup to finish
    while($rp_info.State -ne "Ready") {
        Write-Host "Recovery Plan Cleanup is '$($rp_info.State)'..."
        Start-Sleep -Seconds 10
        $rp_info = $rp.GetInfo()
    }

    Write-Host "Recovery Plan Test Cleanup completed"
    $cleanup_results = ($srmapi.Recovery.GetHistory($rp.Moref)).GetRecoveryResult(1)
    $cleanup_results

    #email results. tbd
}

function New-SRMAlarms {
    [cmdletbinding()]
    param (
        $AlarmCSV = ".\srm-alarms.csv"
    )

    $alarms = Import-Csv $AlarmCSV

    foreach($_a in $alarms) {

    }
}

function Get-VMHostStoragePaths {
    $results = @()
    foreach($cluster in get-cluster | Sort-Object Name) {
        foreach($vmhost in ($cluster | Get-VMHost  | ?{$_.ConnectionState -eq "Connected"} | Sort-Object Name)) {
            foreach($hba in (Get-VMHostHba -VMHost $vmhost -Type "FibreChannel" | Sort-Object Device)){
                 $target = ((Get-View $hba.VMhost).Config.StorageDevice.ScsiTopology.Adapter | Where-Object {$_.Adapter -eq $hba.Key}).Target
                 $luns = @(Get-ScsiLun -Hba $hba  -LunType "disk" -ErrorAction SilentlyContinue)
                 $nrPaths = ($target | ForEach-Object{$_.Lun.Count} | Measure-Object -Sum).Sum
                 if($target.count -ne 0) {
                    Write-Host $vmhost.Name $hba.Device "Targets:" $target.Count "Devices:" $luns.Count "Paths:" $nrPaths
                    $results += [pscustomobject][ordered]@{
                        Cluster = $cluster.Name
                        VMHost = $vmhost.Name
                        HBA = $hba.Device
                        Targets = $target.Count
                        Devices = $luns.Count
                        Paths = $nrPaths
                    }
                 }
            }
        }
    }

    Export-Results -results $results -exportName StoragePaths
}

function Get-VMHostDatastoreCount {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
    )

    process {
        if($VMHost.ConnectionState -eq "Connected" -or $VMHost.ConnectionState -eq "Maintenance") {
            $datastores = $VMHost | Get-Datastore | Measure-Object
            [pscustomobject][ordered]@{
                Cluster = $VMHost.Parent.Name
                VMHost = $VMHost.Name
                Datastores = $datastores.Count
            }
        } else {
            Write-Host "[$($_.Name)] Is not connected or in Maintenance Mode. Skipping"
        }
    }
}

function Invoke-FindVM {
    [cmdletbinding()]
    param (
        $ComputerNamesFile = ".\not-accounted.txt"
    )

    $ComputerNames = Get-Content $ComputerNamesFile
    $results = @()

    foreach($_c in $ComputerNames) {
        $vm = $null
        $cluster = "N/A"
        try { 
            $vm = Get-VM -Name $_c -ErrorAction Stop
            $vm_exists = "Yes"
        }
        catch {
            $vm_exists = "No"
        }

        if($vm -ne $null) {
            try {
                $cluster = $vm | Get-Cluster -ErrorAction Stop | Select-Object -ExpandProperty Name
            }
            catch {
                $cluster = "Not Found"
            }
        }

        Write-Host "[$_c] Exists=$vm_exists Cluster=$cluster"

        $results += [pscustomobject][ordered]@{
            VM = $_c
            Exists = $vm_exists
            Cluster = $cluster
        }
    }

    $results
    Export-Results -results $results -exportName FindVM
}

function Set-VMHostLogDir {
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
    )

    process {
        $template_ds = $null
        $ds = get-datastore -vmhost $VMHost
        $template_ds = $ds | Where-Object{$_.name -like "*template_iso_*"} | Select-Object -First 1
        if($template_ds -ne $null) {
            $shortname = $VMHost.name.Split(".")[0]
            $logdir = "[$($template_ds.name)] scratch/logs/.locker-$shortname"

            $setting = Get-AdvancedSetting -Entity $VMHost -Name syslog.global.logdir
            if($setting.Value -ne $logdir) {
                Write-Host "[$shortname] setting syslog.global.logdir to $logdir"
                Set-AdvancedSetting -AdvancedSetting $setting -Value $logdir -Confirm:$false
            } else {
                Write-Host "[$shortname] syslog.global.logdir already set to $logdir"
            }
        }  
    }
}

function Get-VMToolsHWStatus {
    [cmdletbinding()]
    param (
        [switch]$export = $false
    )

    $results = @()
    $clusters = Get-Cluster | Sort-Object Name
    foreach($_c in $clusters) {
        $vc = Get-vCenterFromUID -uid $_c.Uid
        $views = Get-view -Server $vc -ViewType VirtualMachine -Property Name,Summary,Config,Guest,Parent -SearchRoot $_c.ExtensionData.MoRef
        $folders = Get-View -Server $vc -ViewType Folder -Property Name

        foreach($_v in $views) {
            $results += [pscustomobject][ordered]@{
                Name = $_v.Name
                PowerState = $_v.Summary.Runtime.PowerState
                vCenter = $vc
                Cluster = $_c.Name
                Folder = $folders | ?{$_.MoRef -eq $_v.Parent} | Select-Object -ExpandProperty Name
                GuestOS = $_v.Config.GuestFullName
                HWVersion = $_v.Config.Version
                ToolsUpgradePolicy = $_v.Config.Tools.ToolsUpgradePolicy
                ToolsVersion = SwitchGuestToolsVersion($_v.Guest.ToolsVersion)
                ToolsVersion2 = $_v.Guest.ToolsVersion
                ToolsStatus = $_v.Guest.ToolsStatus
                ToolsStatus2 = $_v.Guest.ToolsVersionStatus2
            }
        }
    }
    
    #Write-Output $results 
    if($export) { Export-Results -results $results -exportName VM_HWTools_Status -excel }
}

function Invoke-VMToolsHardwareUpdate {
    <#
    .PREREQUISITIES
    Assign a VMware Tools and VM Hardware Baseline in VM and Templates view
    Connect to vCenter with Connect-VIServer
    VMs must be Powered On

    MANUAL EFFORT
    1. Find VM in VUM
    2. Scan for Updates
    3. Remediate VMware Tools. Wait
    4. Remediate Hardware Version. Wait
    5. Validate updated VMware Tools Version and Hardware Version
    6. Delete snapshots
    Math: (Number of VMs to Update) x 6 = Effort
    Example: 900 * 6 = 5400

    .POWERSHELL EFFORT
    1. Create list of VMs
    2. Run Invoke-VMToolsHardwareUpdate. Wait for prep
    3. Type 'go'
    4. Type 'cleanup'
    Math: (Number of RFCs) * 4 = Effort
    Example: 12 * 4 = 48
    #>
    [cmdletbinding()]
    param (
        $Servers = "tools_testing.txt",
        $SecondsAfterToolsInstall = 30,
        $toolsBaseline = "VMware Tools Upgrade to Match Host (Predefined)",
        $hardwareBaseline = "VM Hardware Upgrade to Match Host (Predefined)"
    )

    #todo:
    #testing on 3 vms
    #error handling

    #read list of vms from file
    if($Servers.EndsWith(".txt")) { 
        $serverlist = @(Get-Content $Servers) 
    } else { $serverlist = @($Servers) }

    #foreach vm
    $ServerStatus = @()
    foreach($_s in $serverlist) {
        #set state to 'toolsCheck'
        $ServerStatus += [pscustomobject][ordered]@{
            VM = $_s
            State = "prep"
            Message = $null
            ToolsVersion = "Unknown"
            ToolsStatus = "Unknown"
            ToolsCompletedTime = $null
            HardwareVersion = "Unknown"
            HardwareCompletedTime = $null
            TaskID = $null
        }
    }

    $mode = "Testing"
    $refreshneeded = $true
    while($mode -ne "Validation") {
        if($refreshneeded) {
            Clear-Host
            $ServerStatus | Select-Object VM,State,Message,ToolsVersion,ToolsStatus,HardwareVersion | Format-Table -AutoSize | Out-String | ColorWord2 -word 'Success','Failed' -color 'Green','Red'
        }

        $completed = @($ServerStatus | Where-Object{$_.State -match "(Success|Error)"})
        if($completed.Count -eq $ServerStatus.count) {
            $successful = @($ServerStatus | Where-Object{$_.State -eq "Success"})

            $option = Read-Host "Type 'cleanup' delete all snapshots on the $($successful.count) successful VMs"
            switch($option) {
                "cleanup" {
                    $successful | %{ Get-VM $_.VM | Get-Snapshot | Remove-Snapshot -Confirm:$false -RunAsync}
                    Write-Host "Delete snapshot placeholder"; Return 
                }
                default { return }
            }
        }

        $lastServerStatus = $ServerStatus
        foreach($_s in $ServerStatus) {
            $vm = $null
            $Name = $_s.VM
            switch($_s.State) {
                "prep" {
                    $_s.Message = "Getting state"
                    $view = Get-View -ViewType VirtualMachine -Filter @{"Name"=$Name} -Property Name,Guest,Config,Runtime,Snapshot
                    $ToolsStatus = $view.Guest.ToolsStatus
                    $ToolsVersion = SwitchGuestToolsVersion($view.Config.Tools.ToolsVersion)

                    $_s.HardwareVersion = $view.Config.Version
                    $_s.ToolsStatus = $ToolsStatus
                    $_s.ToolsVersion = $ToolsVersion
                    $_s.Message = ""
                    if($view.Runtime.Powerstate -eq "poweredOn") {
                        if($view.Snapshot -eq $null) {
                            $_s.State = "ready"
                        } else {
                            $_s.State = "errorSnapshot"
                            $_s.Message = "VM already has snapshot"
                        }
                    } elseif($view.Runtime.PowerState -eq "poweredOff") {
                        $_s.State = "errorPower"
                        $_s.Message = "Must be Powered On"
                    }
                    break
                }

                "ready" {
                    $ready = @($ServerStatus | Where-Object{$_.State -eq "ready"})
                    if($ready.Count -eq $ServerStatus.count) {
                        $option = Read-Host "Type 'go' to update VMware Tools and Hardware Version on $($ServerStatus.count) VMs"
                        switch($option) {
                            "go" { $ServerStatus | %{ $_.State = "toolsCheck" } }
                            default { return }
                        }
                    }
                    break
                }

                "toolsCheck" {                   
                    $_s.Message = "Checking Tools Compliance"
                    $vm = get-vm $Name
                    $baseline = Get-Baseline -Name $toolsBaseline

                    #scan for updates. wait
                    Scan-Inventory -Entity $vm -UpdateType VmToolsUpgrade

                    #get the compliance state for tools
                    $compliance = Get-Compliance -Entity $vm -Baseline $baseline | Select-Object -ExpandProperty Status
                    switch($compliance) {
                        #set state to toolsNeeded or toolsCompliant or toolsFailed(if previous install failed)
                        "NotCompliant" {
                            $_s.Message = "Tools not compliant"
                            $_s.State = "toolsNeeded"
                        }
                        "Compliant" {
                            $_s.Message = "Tools compliant"
                            $_s.State = "toolsCompliant"
                        }
                        default { Write-Host "something broke"; Return }
                    }
                    break
                }

                "toolsNeeded" {
                    $_s.Message = "Starting Tools update"
                    $vm = get-vm $Name
                    $baseline = Get-Baseline -Name $toolsBaseline

                    #invoke tools remediation
                    $task = Remediate-Inventory -Entity $vm -Baseline $baseline -GuestCreateSnapshot:$true -RunAsync -Confirm:$false
                    #set state to toolsInstalling
                    $_s.TaskID = $task.ID
                    $_s.State = "toolsUpdating"
                    break
                }

                "toolsUpdating" {
                    #wait for remediation to complete then set state to toolsCheck
                    $task = Get-Task -Id $_s.TaskID
                    if($task.State -eq "Running") {
                        $_s.Message = "Waiting for Tools update"
                    } elseif($task.State -eq "Error") {
                        $_s.Message = "Tools update failed"
                        $_s.State = "Error"
                    } elseif($task.State -eq "Success") {
                        $_s.Message = "Tools updated"
                        $_s.State = "toolsCheck"
                    }
                    break
                }

                "toolsCompliant" {
                    $_s.Message = "Validating Tools"
                    #get the tools status and tools version
                    $view = Get-View -ViewType VirtualMachine -Filter @{"Name"=$Name} -Property Name,Guest
                    $ToolsStatus = $view.Guest.ToolsStatus
                    $ToolsVersion = SwitchGuestToolsVersion($view.Guest.ToolsVersion)

                    #if tools status is Running and tools version is 10.0.6, set state to hardwareCheck
                    Write-Verbose "[$Name] VMware Tools is '$ToolsStatus' on version '$ToolsVersion'"
                    $_s.ToolsStatus = $ToolsStatus
                    $_s.ToolsVersion = $ToolsVersion


                    if($ToolsStatus -eq "toolsOK" -and $ToolsVersion -eq "10.0.6") {
                        $_s.State = "hardwareCheck"
                        $_s.ToolsCompletedTime = Get-Date
                    }
                    break
                }

                "hardwareCheck" {
                    #wait for 60 seconds after tools installation
                    $secondsSinceToolsCompleted = (((Get-Date) - ($_s.ToolsCompletedTime)).TotalSeconds)

                    if($secondsSinceToolsCompleted -gt $SecondsAfterToolsInstall) {
                        $_s.Message = "Checking Hardware Compliance"
                        $vm = get-vm $Name
                        $baseline = Get-Baseline -Name $hardwareBaseline

                        #scan for updates. wait
                        Scan-Inventory -Entity $vm -UpdateType VmHardwareUpgrade

                        #get the compliance state for hardware
                        $compliance = Get-Compliance -Entity $vm -Baseline $baseline | select -ExpandProperty Status

                        switch($compliance) {
                            #set the state to hardwareNeeded or hardwareCompliant or hardwareFailed(if previous install failed)
                            "NotCompliant" {
                                $_s.Message = "Hardware is not compliant"
                                $_s.State = "hardwareNeeded"
                            }
                            "Compliant" {
                                $_s.Message = "Hardware is compliant"
                                $_s.State = "hardwareCompliant"
                            }
                            default { Write-Host "something broke"; Return }
                        }

                    } else {
                        $_s.Message = "Waiting for $("{0:N0}" -f $secondsSinceToolsCompleted)/$SecondsAfterToolsInstall seconds"
                    }
                    break
                }

                "hardwareNeeded" {
                    $_s.Message = "Starting Hardware update"
                    $vm = get-vm $Name
                    $baseline = Get-Baseline -Name $hardwareBaseline

                    #invoke hardware remediation
                    $task = Remediate-Inventory -Entity $vm -Baseline $baseline -GuestCreateSnapshot:$true -RunAsync -Confirm:$false
                    #set state to hardwareInstalling
                    $_s.TaskID = $task.ID
                    $_s.State = "hardwareUpdating"
                    break
                }

                "hardwareUpdating" {
                    #wait for remediation to complete then set state to toolsCheck
                    $task = Get-Task -Id $_s.TaskID
                    if($task.State -eq "Running") {
                        $_s.Message = "Waiting for Hardware update"
                    } elseif($task.State -eq "Error") {
                        $_s.Message = "Hardware update failed"
                        $_s.State = "Error"
                    } elseif($task.State -eq "Success") {
                        $_s.Message = "Hardware updated"
                        $_s.State = "hardwareCheck"
                    }
                    break
                }

                "hardwareCompliant" {
                    #get the hardware version
                    $_s.Message = "Validating Hardware"
                    $view = Get-View -ViewType VirtualMachine -Filter @{"Name"=$Name} -Property Name,Config
                    $_s.HardwareVersion = $view.Config.Version
                    if($_s.HardwareVersion -eq "vmx-11") {
                        $_s.State = "Success"
                        $_s.Message = ""
                    } else {
                        $_s.State = "Error"
                        $_s.Message = "Not on Hardware Version 11"
                    }
                }

                default { }
            }
            Start-Sleep -Milliseconds 1000
        }

        if($lastServerStatus -ne $ServerStatus) {
            $refreshneeded = $true
        } else {
            $refreshneeded = $false
        }
    }
}

function Get-VMGuestDiskInfo() {
    <#
    .SYNOPSISrea
    Provides Guest Disk information for a VM
    #>
    [cmdletbinding(DefaultParameterSetName="Name")]
    param (
        [Parameter(ParameterSetName='Name',Mandatory=$true,Position=0)]$Name,
        [Parameter(ParameterSetName='VM',ValueFromPipeline=$true,Mandatory=$true)]$VM,
        $InfoScript = "$PSScriptRoot\GuestDiskInfo2.ps1",
        [switch]$export
    )

    begin {
        $localpass = Get-SecureStringCredentials -Username "Admin" -PlainPassword
        $guestcred = Get-SecureStringCredentials -Username "DOMAIN\Username"
        $allresults = @()
        $script1 = Get-Content $InfoScript -Raw
    }

    process {
        $results = @()
        switch($PSCmdlet.ParameterSetName) {
            "Name" {
                try { $vm = Get-VM $Name -ErrorAction Stop }
                catch { Write-Host $_.Exception.Message -ForegroundColor Red; Return }
            }
        }

        if($vm.Guest.GuestFamily -ne "windowsGuest") {
            Write-Host "[$($vm.name)] This is only supported on Windows VMs"
            Return
        }

        #Use Get-CIMInstance through Invoke-VMScript to get the DriveLetters and Labels
        $vmoutput = Invoke-VMScript -VM $vm -ScriptText $script1 -GuestCredential $guestcred -ScriptType Powershell
        switch($vmoutput.ExitCode) {
            0 { 
                $volTab = @($vmoutput.ScriptOutput | ConvertFrom-Csv)
                Write-Verbose "[$($vm.name)] Invoke-VMScript found $($volTab.count) disks"
                #$voltab
            }
            default { Write-Host "[$($vm.name)] Invoke-VMScript returned Exit Code of $($vmoutput.ExitCode)"; Return }
        }

        $vmDatacenterView = $vm | Get-Datacenter | Get-View
        $virtualDiskManager = Get-View -Id VirtualDiskManager-virtualDiskManager
        #Populate results PSObject from Get-SCSiController and Get-HardDisk
        foreach($ctrl in Get-ScsiController -VM $vm){
            foreach($disk in (Get-HardDisk -VM $vm | where{$_.ExtensionData.ControllerKey -eq $ctrl.Key})){
                $vmHardDiskUuid = $virtualDiskManager.queryvirtualdiskuuid($disk.Filename, $vmDatacenterView.MoRef) | foreach {$_.replace(' ','').replace('-','')}  
                $results += [pscustomobject][ordered]@{
                    VM = $vm.name
                    DiskName = $disk.Name
                    VMDK = $disk.Filename
                    DriveLetter = ""
                    Label = ""
                    CapacityGB = ""
                    FreeSpaceGB = ""
                    HardDiskUUID = $vmHardDiskUuid
                }
            }
        }

        #Match the DriveLetter and Label from WMI to the results
        foreach($_r in $results) {
            $thisvol = @($volTab | ?{$_.SerialNumber -eq $_r.HardDiskUUID})
            if($thisvol.count -eq 1) {
                $_r.DriveLetter = $thisvol.DriveLetter
                $_r.Label = $thisvol.Label
            } elseif($thisvol.count -gt 1) {
                Write-Host "[$($vm.name)] More than one WMI volume matches serial number $($_r.HardDiskUUID). Skipping DriveLetter, Label, Capacity, and FreeSpace"
            } else {
                Write-Host "[$($vm.name)] Cannot find WMI volume for '$($_r.DiskName)' '$($_r.HardDiskUUID)'. Skipping DriveLetter, Label, Capacity, and FreeSpace"
            }
        }

        #Match the CapacityGB and FreeSpaceGB from Get-VMGuest to the results
        $guestdisks = @($vm | Get-VMGuest | Select-Object -ExpandProperty Disks)
        foreach($_r in $results) {
            #If the DriveLetter was previously determined
            if($_r.DriveLetter -ne "") {
                $thisdisk = @($guestdisks | ?{$_.Path -eq "$($_r.DriveLetter)\"})
                if($thisdisk.count -eq 1) {
                    $_r.CapacityGB = ("{0:N2}" -f $thisdisk.CapacityGB)
                    $_r.FreeSpaceGB = ("{0:N2}" -f $thisdisk.FreeSpaceGB)
                } elseif($thisdisk.count -gt 1) {
                    Write-Host "[$($vm.name)] More than one Get-VMGuest Disk matches $($_r.DriveLetter). Skipping CapacityGB and FreeSpaceGB"
                } else {
                    Write-Host "[$($vm.name)] No Get-VMGuest Disk found at $($_r.DriveLetter). Skipping CapacityGB and FreeSpaceGB"
                }
            }
        }
        
        $allresults += $results
    }

    end {
        #Write-Output $allresults
        if($export) { Export-Results -results $allresults -exportName Get-VMGuestDiskInfo -excel }
    }
}

function Invoke-CreateServiceCrontab {
    [cmdletbinding()]
    param (
        $VM,
        $Password
    )

    if(!$Password) {
        $password = Read-Host "Password"
    }

    try { 
        $results = Invoke-VMScript -VM $VM -ScriptText "crontab -l | grep '/sbin/chkconfig' || (crontab -l | grep -v '#' ; echo '*/5 * * * * /sbin/chkconfig > /tmp/service-status.txt; chmod o+r /tmp/service-status.txt')| crontab -" -GuestUser "root" -GuestPassword $password -ErrorAction Stop | Select-Object -ExpandProperty ScriptOutput
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Return "Error"
    }

    return $results
}

function Invoke-CreateServiceCrontab2 {
    [cmdletbinding()]
    param (
        $VM,
        $Password
    )

    if(!$Password) {
        $password = Read-Host "Password"
    }

    try { 
        $results = Invoke-VMScript -VM $VM -ScriptText "crontab -l | grep '/sbin/service' || (echo '*/5 * * * * /sbin/service --status-all > /tmp/service-status.txt; chmod o+r /tmp/service-status.txt')| crontab -" -GuestUser "root" -GuestPassword $password -ErrorAction Stop | Select-Object -ExpandProperty ScriptOutput
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Return "Error"
    }

    return $results
}

function Get-VMGuestAdapterRSS {
    [cmdletbinding()]
    param (
        [Parameter(ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM,
        [Parameter(Mandatory=$true)][string]$GuestUser,
        [Parameter(Mandatory=$true)][string]$GuestPassword 
    )

    $vmoutput = Invoke-VMScript -ScriptText 'Get-NetAdapterRSS | Select SystemName,InterfaceAlias,ifDesc,Enabled | ConvertTo-CSV' `
                -ScriptType Powershell -VM $vm -GuestUser $GuestUser -GuestPassword $GuestPassword

    if($vmoutput.ExitCode -eq 0) {
        $adapters = @($vmoutput.ScriptOutput | ConvertFrom-Csv)
        Write-Output $adapters        
    } else {
        Write-Host "[$($vm.name)] Invoke-VMScript returned Exit Code of $($vmoutput.ExitCode)"
        Return
    }
}

function Get-VMInventory {
    [cmdletbinding()]
    param (
        [switch]$export,
        [string]$exportName = "VM_Inventory"
    )

    $vms = Get-VM | Sort Name

    $results = @()
    foreach($_v in $vms) {
        Write-Host "Processing $($_v.Name)"
        $results += [pscustomobject][ordered]@{
            VM = $_v.Name
            Cluster = ($_v | Get-Cluster).Name
            PowerState = $_v.PowerState
            "IPAddress-1" = $_v.Guest.IPAddress[0]
        }
    }

    if($export -eq $true -and $results.count -gt 0) {
        Export-Results -results $results -exportName $exportName 
    }
}

function Invoke-DefragDatastoreCluster {
    [cmdletbinding()]
    param (
        $DatastoreCluster,
        [int]$DatastoreFillPercent = 83,
        [int]$CloseEnough = 50,
        [int]$svMotionLimit = 1
    )

    #80% DatastoreFillPercent == 1229 GB Preferred
    #83% DatastoreFillPercent == 1044 GB Preferred

    if($DatastoreCluster -eq "all") {
        #Disable-KeepVMDKsTogether all
        $DatastoreCluster = @(get-datastorecluster | Select-Object -expand name)
    }

    foreach($_DSC in $datastoreCluster) {
        #Get Datastores and VMs for Datastore Cluster
        Write-Host "[$_DSC] Getting Datastores and VMs"
        $DSs = @(Get-DatastoreCluster -Name $_DSC | Get-Datastore -Refresh | Sort Name)
        
        #Get-VM | Where-Object {$_.PowerState –eq “PoweredOn”} | Get-CDDrive | FT Parent, IsoPath
        $VMs = @(Get-DatastoreCluster -Name $_DSC | Get-VM | ?{ $_ | Get-CDDrive | ?{ $_.ConnectionState.Connected -eq $false}})

        $DSCount = 0
        :WorkWork do {
            #Get a refreshed datastore object
            $_ds = Get-Datastore -Name $DSs[$DSCount].Name -Refresh
        
            #Math
            $PreferredFreeGB = [math]::Round($_ds.CapacityGB - ($_ds.CapacityGB * ($DatastoreFillPercent/100)),0)
            $diff = $_ds.FreeSpaceGB - $PreferredFreeGB

            #If the datastore has free space and the difference is greather than 50GB
            if($_ds.FreeSpaceGB -gt $PreferredFreeGB -and $diff -gt $CloseEnough) {
                WriteLog $_ds.Name "FreeGB $([math]::Round($_ds.FreeSpaceGB,0))GB greater than PreferredGB $PreferredFreeGB`GB"

                #Get Hard Disks for all VMs in the Datastore Cluster
                Write-Verbose "$($_ds.Name) Getting Hard Disks on VMs"
                $HDs = @($VMs | Get-HardDisk -DiskType Flat)

                #Get possible HDs from other datastores
                $donorDSNames = @($DSs | Select-Object -Skip ($DSCount+1) -ExpandProperty Name | Sort-Object -Descending)
                $donorHds = @()
                foreach($_donor in $donorDSNames) {
                    $donorHDs += @($HDs | ?{$_.Filename -like "*$_donor*"})
                }
                $donorHds = $donorHds | Sort-Object -Property CapacityGB -Descending
            
                #Check to see if moving the hard disk wont exceed PreferredFreeGB
                foreach($_hd in $donorHDs) {
                    $AfterFreeGB = [math]::Round($_ds.FreeSpaceGB - $_hd.CapacityGB,0)
                    if($AfterFreeGB -gt $PreferredFreeGB) {
                        do {
                            $success = $false
                            $tasks = @(get-task | Where-Object{$_.name -like "*RelocateVM_Task*" -and $_.state -ne "Success"})
                            if($tasks.count -lt $svMotionLimit) {
                                WriteLog $_ds.Name "Moving $($_hd.CapacityGB) GB $($_hd.Filename). After svMotion:$AfterFreeGB GB Free"
                                Move-HardDisk -HardDisk $_hd -Datastore $_ds -Confirm:$false | Out-Null
                                $success = $true
                            } else {
                                Write-Host "Waiting for other svMotions"
                                Start-Sleep -Seconds 60
                            }
                        } while ($success -ne $true)
                    
                        continue WorkWork
                    } else {
                        Write-Verbose "Moving $($_hd.FileName) with $($_hd.CapacityGB) GB will not work. $AfterFreeGB is less than $PreferredFreeGB"
                    }
                }
                Write-Host "[$($_ds.Name)] No defrag possible"
            } else {
                WriteLog $_ds.Name "Datastore is nominal"
            }
            $DSCount = $DSCount + 1
        } while ($DSCount -lt $DSs.Count)
    }

    if($DatastoreCluster -eq "all") {
        #Disable-KeepVMDKsTogether all
    }
}

function Test-VMHostIODevice {
    [cmdletbinding()]
    param (
        [parameter(ValueFromPipeline=$True)]$Input,
        [switch]$export
    )

    #650FLB: Emulex Corporation Emulex OneConnect OCe14000, FCoE Initiator
    #554FLB & 554M: ServerEngines Corporation Emulex OneConnect OCe11100 FCoE Initiator
    #534M not seen
    #$StorageControllers = @($VMHost| Get-VMHostPciDevice -DeviceClass SerialBusController | ?{$_.Name -notlike "*intel*" -and $_.Name -notlike "*hewlett-packard*"})

    #650FLB: Emulex Corporation HP FlexFabric 20Gb 2-port 650FLB Adapter
    #554FLB: Emulex Corporation HP FlexFabric 10Gb 2-port 554FLB Adapter
    #554M: Emulex Corporation HP FlexFabric 10Gb 2-port 554M Adapter
    #534M: Broadcom Corporation QLogic 57810 10 Gigabit Ethernet Adapter
    #$NetworkControllers = @($VMHost | Get-VMHostPciDevice | ?{$_.DeviceClass -eq "NetworkController"})

    #load the latest file
    if(!$Input) {
        $input = Get-ChildItem "$global:ReportsPath\*.xlsx" | Where-Object{$_.name -like "Get-VMHostIODevice*"} | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Import-Excel        #$Input = Import-Excel "\\path\to\file"
    }

    $results = @()
    $steps = @()
    #Check the NICs
    foreach($nic in @($Input | ?{$_.VMKernel -match "(vmnic.*|vmhba.*)"})) {
        $FWVersionState = "N/A"
        switch($nic.Device) {
            #FCoE: 650FLB
            "Emulex OneConnect OCe14000, FCoE Initiator" {
                #Check driver
                $wanted = "11.1.183.633"
                if($nic."Driver Version" -like "*$wanted*") {
                    $DriverVersionState = "Pass"
                } else {
                    $DriverVersionState = "Fail"
                    $steps += "[$($nic.VMHost)] Update lpfc driver from $($nic."Driver Version") to $wanted with VUM"
                }
            }

            #FCoE: 554FLB and 554M
            "Emulex OneConnect OCe11100 FCoE Initiator" {
                #Check driver
                $wanted = "11.1.183.633"
                if($nic."Driver Version" -like "*$wanted*") {
                    $DriverVersionState = "Pass"
                } else {
                    $DriverVersionState = "Fail"
                    $steps += "[$($nic.VMHost)] Update lpfc driver from $($nic."Driver Version") to $wanted with VUM"
                }
            }

            #Network: 650FLB
            "HP FlexFabric 20Gb 2-port 650FLB Adapter" {
                #Check driver
                $wanted = "11.1.145.0"
                if($nic."Driver Version" -like "*$wanted*") {
                    $DriverVersionState = "Pass"
                } else {
                    $DriverVersionState = "Fail"
                    $steps += "[$($nic.VMHost)] Update elxnet driver from $($nic."Driver Version") to $wanted with VUM"
                }

                #Check firmware
                $wanted = "11.1.183.62"
                if($nic."Firmware Version" -eq $wanted) {
                    $FWVersionState = "Pass"
                } else {
                    $FWVersionState = "Fail"
                    $steps += "[$($nic.VMHost)] Update 650FLB firmware from $($nic."Firmware Version") to $wanted with SPP 2017.04.0"
                }
            }

            #Network: 554FLB
            "HP FlexFabric 10Gb 2-port 554FLB Adapter" {
                #Check driver
                $wanted = "11.1.145.0"
                if($nic."Driver Version" -like "*$wanted*") {
                    $DriverVersionState = "Pass"
                } else {
                    $DriverVersionState = "Fail"
                    $steps += "[$($nic.VMHost)] Update elxnet driver from $($nic."Driver Version") to $wanted with VUM"
                }

                #Check firmware
                $wanted = "11.1.183.23"
                if($nic."Firmware Version" -eq $wanted) {
                    $FWVersionState = "Pass"
                } else {
                    $FWVersionState = "Fail"
                    $steps += "[$($nic.VMHost)] Update 554FLB firmware $($nic."Firmware Version") to $wanted with SPP 2017.04.0"
                }
            }

            #Network: 554M
            "HP FlexFabric 10Gb 2-port 554M Adapter" {
                #Check driver
                $wanted = "11.1.145.0"
                if($nic."Driver Version" -like "*$wanted*") {
                    $DriverVersionState = "Pass"
                } else {
                    $DriverVersionState = "Fail"
                    $steps += "[$($nic.VMHost)] Update elxnet driver from $($nic."Driver Version") to $wanted with VUM"
                }

                #Check firmware
                $wanted = "11.1.183.23"
                if($nic."Firmware Version" -eq $wanted) {
                    $FWVersionState = "Pass"
                } else {
                    $FWVersionState = "Fail"
                    $steps += "[$($nic.VMHost)] Update 554M firmware from $($nic."Firmware Version") to $wanted with SPP 2017.04.0"
                }
            }

            #Network: 534M
            "QLogic 57810 10 Gigabit Ethernet Adapter" {
                #Check driver
                $wanted = "2.713.10.v60.4"
                if($nic."Driver Version" -like "*$wanted*") {
                    $DriverVersionState = "Pass"
                } else {
                    $DriverVersionState = "Fail"
                    $steps += "[$($nic.VMHost)] Update bnx2x driver from $($nic."Driver Version") to $wanted with VUM"
                }

                #Check firmware
                $wanted = "bc 7.13.75"
                if($nic."Firmware Version" -eq $wanted) {
                    $FWVersionState = "Pass"
                } else {
                    $FWVersionState = "Fail"
                    $steps += "[$($nic.VMHost)] Update 534M firmware from $($nic."Firmware Version") to $wanted with SPP 2017.04.0"
                }
            }

            default {
                $FWVersionState = "Error"
                $DriverVersionState = "Fail"
            }
        }

        $results += [pscustomobject][ordered]@{
            Cluster = $nic.Cluster
            VMHost = $nic.VMHost
            Device = $nic.Device
            "FW Version" = $nic."Firmware Version"
            "FW State" = $FWVersionState
            Driver = $nic.Driver
            "Driver Version" = $nic."Driver Version"
            "Driver State" = $DriverVersionState
        }
    }

    #Filter out duplicates
    $results = $results | Select Cluster,VMHost,Device,"FW Version","FW State",Driver,"Driver Version","Driver State" -Unique
    Write-Output $results

    #List the steps needed for remediation
    $steps | Select -Unique | %{ Write-Host $_ }
    
    if($export) { Export-Results -Results $results -ExportName Test-VMHostIODevices -excel }
}

function Invoke-CleanVMHostCoreDump {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
    )

    process {
        $esxcli = Get-EsxCli -VMHost $VMHost.Name -V2
        $shortName = $VMHost.Name.Split(".")[0]

        #Delete old dumpfiles
        $dumpfiles = $esxcli.system.coredump.file.list.invoke() | ?{$_.Path -notlike "*VMName"}
        foreach($dumpfile in $dumpfiles) {
            Write-Host "Removing $($dumpfile.Path)"
            $dumpArgs = $esxcli.system.coredump.file.remove.CreateArgs()
            $dumpArgs.file = $dumpfile.Path
            $dumpArgs.force = $true
            $esxcli.system.coredump.file.remove.Invoke($dumpArgs)
        }
    }
}

function Set-VMHostCoreDump {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost

    )

    process {
        $esxcli = Get-EsxCli -VMHost $VMHost.Name -V2
        $shortName = $VMHost.Name.Split(".")[0]
        $Site = $VMHost.Name.Split("-")[0].ToUpper()

        #Delete old dumpfiles
        $dumpfiles = $esxcli.system.coredump.file.list.invoke() | ?{$_.Path -like "*$shortName*"}
        foreach($dumpfile in $dumpfiles) {
            Write-Host "Removing $($dumpfile.Path)..." -NoNewline
            
            $dumpArgs = $esxcli.system.coredump.file.remove.CreateArgs()
            $dumpArgs.file = $dumpfile.Path
            $dumpArgs.force = $true
            $result = $esxcli.system.coredump.file.remove.Invoke($dumpArgs)
            switch($result) {
                "true" { Write-Host "Success" -ForegroundColor Green }
                default { Write-Host "Failed" -ForegroundColor Red }
            }
        }

        #Create a new dumpfile
        
        $newArgs = $esxcli.system.coredump.file.add.CreateArgs()
        $newArgs.datastore = "Template_ISO__$Site"
        $newArgs.file = $shortName

        Write-Host "Creating coredump on $($newArgs.datastore)..." -NoNewline
        $result = $esxcli.system.coredump.file.add.Invoke($newArgs)
        switch($result) {
                "true" { Write-Host "Success" -ForegroundColor Green }
                default { Write-Host "Failed" -ForegroundColor Red }
        }

        #Activate the new dumpfile
        $newdumpfile = @($esxcli.system.coredump.file.list.invoke() | ?{$_.Path -like "*$shortName*"})
        if($newdumpfile.count -eq 1) {
            Write-Host "Setting $($newdumpfile.Path) as Active..." -NoNewline
            $setArgs = $esxcli.system.coredump.file.set.CreateArgs()
            $setArgs.path = $newdumpfile[0].Path
            $result = $esxcli.system.coredump.file.set.Invoke($setArgs)
            switch($result) {
                "true" { Write-Host "Success" -ForegroundColor Green }
                default { Write-Host "Failed" -ForegroundColor Red }
            }
        }

    }

}

function Set-VMToolsPolicy {
    [cmdletbinding()]
    param (
        $Servers
    )

    if($servers.Endswith(".txt")) {
        $Servers = Get-Content $servers
    } else {
        $Servers = @("$Servers")
    }

    $vms = @()
    foreach($_s in $servers) {
        $vms += get-vm $_s
    }

    foreach($vm in $vms) { 
        $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
        $spec.changeVersion = $vm.ExtensionData.Config.ChangeVersion
        $spec.tools = New-Object VMware.Vim.ToolsConfigInfo
        $spec.tools.toolsUpgradePolicy = "upgradeAtPowerCycle"
 
        $_this = Get-View -Id $vm.Id
        $_this.ReconfigVM_Task($spec)
    }
}
