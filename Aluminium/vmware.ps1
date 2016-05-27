function Set-VMHostAdvancedSetting {
    <#
    .SYNOPSIS
    (1.0)
    Change the advanced settings for multiple vSphere VM Hosts.
    .DESCRIPTION
    Uses Get-AdvancedSetting and Set-AdvancedSetting to change the advanced setting.
    #>
    [cmdletbinding()]
    Param (
        $vmhosts,
        [Parameter(Mandatory=$true)]$setting,
        [Parameter(Mandatory=$true)]$value,
        $confirm = $false
    )
    if($vmhosts.EndsWith(".txt")) { $vmhosts = @(Get-Content $vmhosts) } 
    foreach($_v in $vmhosts) {
        try { $vm = Get-VMHost $_v -ErrorAction Stop }
        catch { Write-Host "$($_v): VMHost not found" -ForegroundColor Red; continue }
        $current = Get-AdvancedSetting -Entity $vm -Name $setting
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
    (1.0)
    #>
    [cmdletbinding()]
    param (
        [string]$Name = "",
        [string]$Parent
    )

    if($Parent) {
        $ParentObj = Get-VIObject -Name $Parent
        $ParentvCenter = $ParentObj.UID | ?{$_ -match "@(?<vcenter>.*):443"} | %{$matches['vcenter']}
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
        Write-Debug "hi"
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
    return $results | Sort Name
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
    [cmdletbinding()]
    Param (
        [Parameter(ParameterSetName="Name")]$Name,
        [Parameter(ParameterSetName="Parent")]$Parent,
        [switch]$report = $true,
        [string]$reportName = "VMHostMetrics_"
    )

    #Switch the Parameter Set and collect the appropriate VMware object(s)
    $all = @()
    try { 
        switch($PSCmdlet.ParameterSetName) {
            "Parent" {
                $ParentObj = Get-VIObject -Name $Parent
                $ParentvCenter = $ParentObj.UID | ?{$_ -match "@(?<vcenter>.*):443"} | %{$matches['vcenter']}
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
            $vmhosts = $VMHostViews | Sort Name | Get-VIObjectByVIView
        }
    }
    catch { Write-Host -ForegroundColor Red $_.Exception.Message; Return }

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
            vCenter = $_vmhost.uid | ?{$_ -match "@(?<vcenter>.*):443"} | %{$matches['vcenter']}
            Cluster = [string]$_vmhost.Parent
            Model = [string]$_vmhost.Model
            Build = [int]$view.Config.Product.Build
            IPAddress = ($_vmhost | Get-VMHostNetworkAdapter) | ?{$_.ManagementTrafficEnabled} | Select-Object -ExpandProperty IP
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
    $all | sort VMHost
    if($report -eq $true -and $all.count -gt 0) {
        Export-Results -results $all -exportName $reportName
    }
}

function Connect-AllvCenters {
    <#
    .SYNOPSIS
    (1.0)
    Prompt for user credentials and connect PowerShell to multiple vCenters
    .DESCRIPTION
    Edit vcenters.csv and edit the list of vCenters and associated username
    #>
    [cmdletbinding()]
    param ()
    $connectioneeded = @()
    #Read vCenter/Credentials from file
    $vcenters = Import-Csv "$($PSScriptRoot)\vcenters.csv"
    #Filter out connected vcenters
    foreach($_v in $vcenters) {
        if($Global:DefaultVIServers.Name -notcontains $_v.vCenter) {
            Write-Host "$($_v.vCenter): Connect-VIServer needed"; $connectioneeded += $_v
        } else { Write-Host "$($_v.vCenter): Already connected" }
    }
    #Determine unique usernames and connect to vCenters
    $users = $connectioneeded.Credentials | select -Unique
    foreach($_u in $users) {
        if($cred = Get-SecureStringCredentials -Username $_u -Credentials) {
        Write-Host "Loaded $_u from SecureString"
        } else { $cred = Get-Credential -Message "Enter password" -UserName $_u }
        foreach($_v in ($connectioneeded | ?{$_.Credentials -eq $_u})) { Connect-VIServer -Credential $cred -server $_v.VCenter -Protocol https }
    }
    Write-Host ""
}

function Get-FreeScsiLun {
    <#  
    .SYNOPSIS  Find free SCSI LUNs  
    .DESCRIPTION The function will find the free SCSI LUNs
      on an ESXi server
    .NOTES  Author:  Luc Dekens  
    .PARAMETER VMHost
        The VMHost where to look for the free SCSI LUNs  
    .EXAMPLE
       PS> Get-FreeScsiLun -VMHost $esx
    .EXAMPLE
       PS> Get-VMHost | Get-FreeScsiLun
    #>
    [cmdletbinding()]
    #Requires -Version 3.0
    param (
        [parameter(ValueFromPipeline = $true,Position=1)][ValidateNotNullOrEmpty()]
        [VMware.VimAutomation.Client20.VMHostImpl]$VMHost
    )

    process{
        $storMgr = Get-View $VMHost.ExtensionData.ConfigManager.DatastoreSystem
        $storMgr.QueryAvailableDisksForVmfs($null) | %{
            New-Object PSObject -Property @{
                VMHost = $VMHost.Name
                CanonicalName = $_.CanonicalName
                Uuid = $_.Uuid
                CapacityGB = [Math]::Round($_.Capacity.Block * $_.Capacity.BlockSize / 1GB,2)
            }
        }
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
			foreach ($VirtualSCSIController in ($VMView.Config.Hardware.Device | where {$_.DeviceInfo.Label -match "SCSI Controller"})) {
				foreach ($VirtualDiskDevice in ($VMView.Config.Hardware.Device | where {$_.ControllerKey -eq $VirtualSCSIController.Key})) {
					$VirtualDisk = "" | Select VM,SCSIController, DiskName, SCSI_Id, DiskFile,  DiskSize, WindowsDisks
					$VirtualDisk.VM = $VM
					$VirtualDisk.SCSIController = $VirtualSCSIController.DeviceInfo.Label
					$VirtualDisk.DiskName = $VirtualDiskDevice.DeviceInfo.Label
					$VirtualDisk.SCSI_Id = "$($VirtualSCSIController.BusNumber) : $($VirtualDiskDevice.UnitNumber)"
					$VirtualDisk.DiskFile = $VirtualDiskDevice.Backing.FileName
					$VirtualDisk.DiskSize = $VirtualDiskDevice.CapacityInKB * 1KB / 1GB

					$LogicalDisks = @()
					# Look up path for this disk using WMI.
					$thisVirtualDisk = get-wmiobject -class "Win32_DiskDrive" -namespace "root\CIMV2" -computername $VM | where {$_.SCSIBus -eq $VirtualSCSIController.BusNumber -and $_.SCSITargetID -eq $VirtualDiskDevice.UnitNumber}
					# Look up partition using WMI.
					$Disk2Part = Get-WmiObject Win32_DiskDriveToDiskPartition -computername $VM | Where {$_.Antecedent -eq $thisVirtualDisk.__Path}
					foreach ($thisPartition in $Disk2Part) {
						#Look up logical drives for that partition using WMI.
						$Part2Log = Get-WmiObject -Class Win32_LogicalDiskToPartition -computername $VM | Where {$_.Antecedent -eq $thisPartition.Dependent}
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

function Connect-vCenters {
    <#
    .SYNOPSIS
    Menu for connecting PowerShell and the vSphere Client to vCenter
    .DESCRIPTION
    Edit vcenters.csv and edit the list of vCenters and associated username
    #>
    [cmdletbinding()]
    param ([switch]$client)

    #Read vcenters.csv and draw menu
    $vcenters = Import-Csv "$($PSScriptRoot)\vcenters.csv"
    Write-Host "Select a server from the list"
    for($i = 1; $i -lt $vcenters.count + 1; $i++) { Write-Host "[$i] $($vcenters[$i-1].vCenter)" }

    #Switch $option to determine selected vCenter
    $option = Read-Host
    switch -Regex ($option) {
        "\d" {
            #Assign variable to selected vCenter and get user credentials
            $destvCenter = $vcenters[$option-1]
            if($cred = Get-SecureStringCredentials -Username $destvCenter.Credentials -Credentials) {
                Write-Host "Loaded $($destvCenter.Credentials) from SecureString"
            } else { $cred = Get-Credential -UserName $destvCenter.Credentials -Message $destvCenter.vCenter }

            #if -client switch is used, launch vSphere client and connect with credentials
            if($client) { Start-Process -FilePath "C:\Program Files (x86)\VMware\Infrastructure\Virtual Infrastructure Client\Launcher\VpxClient.exe" -ArgumentList "-s $($destvCenter.vCenter) -u $($cred.username) -p $($cred.GetNetworkCredential().Password)" }
            
            #Disconnect from all vCenters and connect to selected vCenter
            Write-Host "Connecting to $($destvCenter.vCenter)"
            if($global:DefaultVIServers) { Disconnect-VIServer -Server $global:DefaultVIServers -Force -ErrorAction SilentlyContinue -Confirm:$false }
            Connect-VIServer -Credential $cred -server $destvCenter.vCenter -Protocol https
            Set-PowerCLITitle $destvCenter.vCenter
        }
        default { Write-Host "$option - Invalid Option" }
    }
}

function Test-ESXiAccount {
    <#
    .SYNOPSIS
    Test local ESXi accounts on VM hosts
    .DESCRIPTION
    Attempts to connect directly to multiple VM Hosts using specified credentials
    #>
    [cmdletbinding()]
    Param (
        [string]$vmhostPath = "$($PSScriptRoot)\VMHosts_All_20160211.csv",
        [string]$account = "vadmin",
        [string]$vcenter,
        [string]$reportPath = "$($PSScriptRoot)\Reports\Test-ESXiAccount_"
    )

    try { 
        $hosts = Import-Csv $vmhostPath -ErrorAction Stop
        Write-Host "$($vmhostPath): Loaded $($hosts.count) hosts"
        if($vcenter) { 
            $hosts = $hosts | ?{$_.vCenter -like $vcenter}
            Write-Host "$($vmhostPath): Filtered to $($hosts.count) hosts on $($vcenter)"
        }
    }
    catch { Write-Host "$($vmhostPath): Failed to load CSV. Aborting."; Exit-PSSession }
    $account_pw_secure = Read-Host "Password for $account" -AsSecureString
    $account_pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($account_pw_secure))
    Write-Host ""

    $results = @()
    foreach($_h in $hosts) {
        try {
            Connect-VIServer $_h.VMHost -User $account -Password $account_pw -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
            $status = "Validated"
            Write-Host "$($_h.VMHost): Validated password for $account"
            Disconnect-VIServer $_h.VMHost -Force -Confirm:$false
        }

        catch {
            Write-Host "$($_h.VMHost): Failed to connect as $account"
            $status = "Failed"
        }

        $results += [pscustomobject][ordered]@{
            Host = $_h.VMHost
            vCenter = $_h.vCenter
            Account = $account
            Status = $status
        }
    }

    if($results.count -gt 0) {
        if($vcenter) { $reportPath += "$($vcenter)_" }
        $reportPath += "$($account)_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
        $results | Export-Csv -NoTypeInformation -Path $reportPath
        Write-Host "Results exported to $reportPath" -ForegroundColor Green
    }
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
    $poweredoff = $($vms | ?{$_.PowerState -eq "PoweredOff"})
    $poweredon = $($vms | ?{$_.PowerState -eq "PoweredOn"})
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
    $poweredoff = $($vms | ?{$_.PowerState -eq "PoweredOff"})
    $poweredon = $($vms | ?{$_.PowerState -eq "PoweredOn"})
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
                    Shutdown-VMGuest -VM $_v -Confirm:$false
                    Start-Sleep $seconds
                }
            }
            default { Write-Host "Exiting"; Return }
        }
    }
}

function SetException($h) {
    try { $ex = Get-VMHostFirewallException -VMHost $h -Name $exception -ErrorAction Stop }
    catch { Write-Host "$h - $exception Exception not found"; return }
    if($ex.Enabled -ne $enabled) {
        Write-Host "$h - changing $exception Exception to $enabled"
        Set-VMHostFirewallException -Exception $ex -Enabled $enabled
    } else { Write-Host "$h - $exception Exception is already $enabled" }
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
                $c = Get-Cluster $cluster -ErrorAction Stop | Get-VMHost | sort Name
                foreach($_c in $c) { SetException $_c } 
                }
            "Datacenter" { 
                $c = Get-Datacenter $datacenter -ErrorAction Stop | Get-VMHost | sort Name
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
                $ParentvCenter = $ParentObj.UID | ?{$_ -match "@(?<vcenter>.*):443"} | %{$matches['vcenter']}
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
            $vmhosts = $VMHostViews | Sort Name | Get-VIObjectByVIView
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
        [switch]$export = $false,
        [string]$exportName = "$($PSScriptRoot)\Reports\VMDetails"
    )
    if($Name.EndsWith(".txt")) { $Name = @(Get-Content $Name) | Select-Object -Unique } 
    try { $allvms = Get-VM -ErrorAction Stop }
    catch { Write-Host "Failed to get VMs. Are you connected to vCenter?" -ForegroundColor Red; Return }

    $results = @()
    foreach($_s in $Name) {
        Write-Host "$($_s): Collecting metrics"
        $vms = @($allvms | ?{$_.name -eq "$_s"})
        if($vms.count -eq 0) { Write-Host "$($_s): VM not found. Skipping." -ForegroundColor Red; Continue } 
        elseif($vms.count -gt 1) { Write-Warning "$($_s): Found $($vms.count) matching VMs" }
        foreach($vm in $vms) {
            $NetworkType0 = $NetworkType1 = ""
            $NetworkLabel0 = $NetworkLabel1 = ""
            
            $adapters = $vm | Get-NetworkAdapter
            if($adapters) {
                $adapters | %{$i=0} {
                    Set-Variable -Name NetworkType$i -Value $_.Type
                    Set-Variable -Name NetworkLabel$i -Value $_.NetworkName
                    $i++
                }
            }
            $disks = $vm | Get-HardDisk
            Write-Debug "hi"
            $results += [pscustomobject][ordered]@{
                Name = $vm.Name
                PowerState = $vm.PowerState
                Cluster = ($vm | Get-Cluster).Name
                NumCPU = $vm.NumCpu
                MemoryGB = $vm.MemoryGB
                Disks = $disks.count
                AllocatedGB = ($disks | Measure-Object -Property CapacityGB -Sum).Sum
                "NetworkType-1" = $NetworkType0
                "NetworkLabel-1" = $NetworkLabel0
                "IP-1" = $vm.Guest.IPAddress[0]
                "NetworkType-2" = $NetworkType1
                "NetworkLabel-2" = $NetworkLabel1
                "IP-2" = $vm.Guest.IPAddress[1]
            }
        }
    }
    Write-Output $results
    if($export) { Export-Results -Results $results -ExportName Get-VMDetails }
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
        [switch]$export = $false,
        [string]$exportName = "$($PSScriptRoot)\Reports\VMDatastoreDetails"
    )
    if($servers.EndsWith(".txt")) { $servers = @(Get-Content $servers) }
    try { $allvms = Get-VM -ErrorAction Stop }
    catch { Write-Host "Failed to get VMs. Are you connected to vCenter?" -ForegroundColor Red; Return }

    $all = @()
    foreach ($_s in $servers){
        Write-Host "$($_s): Collecting data"
        $vms = @($allvms | ?{$_.name -eq "$_s"})
        if($vms.count -eq 0) { Write-Host "$($_s): VM not found. Skipping." -ForegroundColor Red; Continue } 
        elseif($vms.count -gt 1) { Write-Warning "$($_s): Found $($vms.count) matching VMs" }

        foreach($vm in $vms) {
            try { $VMDKs = $VM | Get-HardDisk -ErrorAction Stop }
            catch { Write-Host "$($_s): Failed to get hard disks. Skipping." -ForegroundColor Red; Continue }
            if($VMDKs) {
	            foreach ($VMDK in $VMDKs) {
		            if ($VMDK -ne $null){
			            $CapacityGB = $VMDK.CapacityKB/1024/1024
			            $CapacityGB = [int]$CapacityGB
                        $datastore = $VMDK.FileName.Split(']')[0].TrimStart('[')
			            $datastoreobject = Get-Datastore $datastore | Select-Object -First 1
                        $all += [pscustomobject][ordered]@{
			                Name = $_s
                            VMDKFileName = $VMDK.Filename
                            VMDKPath = $VMDK.FileName.Split(']')[1].TrimStart('[ ')
                            VMDKCapacityGB = $CapacityGB
                            VMDKFormat = $VMDK.StorageFormat
			                Datastore = $datastore
                            DatastoreCapacityGB = "{0:N2}" -f $datastoreobject.CapacityGB
                            DatastoreFreeGB = "{0:N2}" -f $datastoreobject.FreeSpaceGB
                            DatastoreFreePercent = "{0:N2}" -f (($datastoreobject.FreeSpaceGB/$datastoreobject.CapacityGB)*100)
                        }
		            }
	            }
            }
        }
    }
    $all = $all | sort Name
    if($export) { Export-Results -Results $all -ExportName Get-VMDatastoreDetails }
    else { Write-Output $all }
}

function Test-vCenters {
    Connect-AllvCenters

    $hosts = Get-VMHost | Sort-Object Name
    $hostsView = Get-View -ViewType HostSystem -Property Name,RunTime
    Write-Host "`nTotal hosts: $($hosts.count)"
    Write-host ""

    $nonconnected= @($hosts | ?{$_.ConnectionState -ne "Connected"})
    Write-Host "Hosts not in Connected state: $($nonconnected.Count)"
    if($nonconnected.Count -gt 0) { $nonconnected | Select-Object -ExpandProperty Name }
    Write-Host ""

    $lowuptime = @($hostsView | Select Name,@{N="UptimeHours"; E={[math]::abs((new-timespan (Get-Date) $_.Runtime.BootTime).TotalHours)}} | ?{$_.UptimeHours -le 120})
    Write-Host "Hosts with less than 5 days of uptime: $($lowuptime.count)"
    if($lowuptime.Count -gt 0) { $lowuptime | Select-Object Name,UptimeHours | Sort-Object UptimeHours }
    Write-Host ""

    $hostservices = @($hosts | Get-VMHostService)

    $sshrunning = @($hostservices | ?{$_.Key -eq "TSM-SSH" -and $_.Running -eq "True"})
    Write-Host "Hosts with SSH Running: $($sshrunning.Count)"
    if($sshrunning.count -gt 0) { (($sshrunning | Select-Object -ExpandProperty vmhost) | Select-Object -ExpandProperty name); Write-Host "" }

    $shellrunning = @($hostservices | ?{$_.Key -eq "TSM" -and $_.Running -eq "True"})
    Write-Host "Hosts with ESXi Shell Running: $($shellrunning.Count)"
    if($shellrunning.count -gt 0) { (($shellrunning | Select-Object -ExpandProperty vmhost) | Select-Object -ExpandProperty name); Write-Host "" }

    $vmview = Get-View -ViewType VirtualMachine -Property Name, "Runtime" | Sort-Object Name
    $needconsolidation = @($vmview | ?{$_.Runtime.ConsolidationNeeded})
    Write-Host "`nTotal VMs: $($vmview.count)`nVMs which need consolidation: $($needconsolidation.count)"
    if($needconsolidation.count -gt 0) { $needconsolidation | Select-Object -ExpandProperty Name }

    $vms = Get-VM
    $nonavprxdisks = @($vms | ?{$_.Name -like "*avprx*"} | Get-HardDisk | ?{$_.Filename -notlike "*avprx*"})
    Write-Host "Non-Avamar Hard Disks attached to Avamar Proxies: $($nonavprxdisks.count)"
    if($nonavprxdisks.count -gt 0) { $nonavprxdisks | Select-Object Parent,FileName }

    $snaps = @($vms | Get-Snapshot)
    Write-Host "Snapshots: $($snaps.count)"
    if($snaps.count -gt 0) { $snaps | select VM,Created,Description,SizeGB }
}

function checkVM($v) {
    #Check Floppy existence
    if($v | Get-FloppyDrive) { $FloppyExists = $true}
    else { $FloppyExists = $false }

    #Check that only VMXNET3 exists
    foreach($nic in ($v | Get-NetworkAdapter)) { if($nic.Type -ne "Vmxnet3") { $OnlyVMXStatus = $false } }
    if($OnlyVMXStatus -eq $null) { $OnlyVMXStatus = $true }

    #Check datastore count, usage
    $ds_list = @()
    try {
        $disks = $v | Get-HardDisk -ErrorAction Stop | ?{$_.filename -notlike "*snap*"}
        foreach($_d in $disks.Filename) { $ds_list += $_d.Substring(1,$_d.IndexOf("]") - 1) }
        $ds_list = $ds_list | select -Unique
        $ds_count = $ds_list.count
    }
    catch { Write-Host "$v - Error getting datastore information"; $ds_list = "Error"; $ds_count = "Error" }

    $results = [pscustomobject][ordered]@{
        Name = $v.Name
        HardwareVersion = $v.Version
        FloppyExists = $FloppyExists
        "Only-VMXNET3" = $OnlyVMXStatus
        DatastoreCount = $ds_count
        Datastores = $ds_list
        ProvisionedGB = ($disks | Measure-Object -Sum -Property CapacityGB).Sum
    }
    return $results
}

function Test-VMStorage {
    [cmdletbinding(DefaultParametersetName="naaOrDatastore")]
    Param (
        [Parameter(ParameterSetName="naaOrdatastore",Mandatory=$true,Position=0)][string]$naaOrdatastore,
        [Parameter(ParameterSetName="deviceID",Mandatory=$true,Position=0)][string]$deviceID,
        [string]$datastore_inventory_path = "C:\Scripts\Reports\Datastore_Inventory*",
        [string]$rdm_inventory_path = "C:\Scripts\Reports\RDM_Inventory*"
    )

    #point at datastore
    #check again rdm list - tell if not/is rdm
    #check against datastore list - tell if not/is rdm

    try {
        $ds_inventory_csv = Get-ChildItem $datastore_inventory_path -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $ds_inventory = Import-Csv $ds_inventory_csv -ErrorAction Stop

        $rdm_inventory_csv = Get-ChildItem $rdm_inventory_path -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $rdm_inventory = Import-Csv $rdm_inventory_csv  -ErrorAction Stop

        Write-Host "$($ds_inventory_csv): $($ds_inventory.count) datastores"
        Write-Host "$($rdm_inventory_csv): $($rdm_inventory.count) RDMs"
        Write-Host ""
     }
    catch { Write-Host $_.Exception -ForegroundColor Red ; return }

    switch($PSCmdlet.ParameterSetName) {
        "naaOrdatastore" {
            if($naaOrdatastore.StartsWith("naa.")) {
                $selected = @($ds_inventory | ?{$_."NAA.ID" -like "*$naaOrdatastore*"})
                if($selected.count -gt 0) { Write-Host "Datstores: Found $($selected.count) matching datstores" }

                $rdm_selected = @($rdm_inventory | ?{$_."ScsiCanonicalName" -like "*$naaOrdatastore*"})
                if($rdm_selected.count -gt 0) { 
                    Write-Host "RDMs: Found $($rdm_selected.count) matching RDMs" 
    
                }
            } else {
                $selected = $ds_inventory | ?{$_.Datastore -like "*$naaOrdatastore*"}
            }
        }
        "deviceID" {

        }
    }


    if($selected) {
        foreach($_s in $selected) {
            $vms = @(Get-Datastore -Name $_s.Datastore | Get-VM)
            if($PSCmdlet.ParameterSetName -eq "deviceID") {
                Write-Host "DeviceID: $deviceID"
            }
            Write-Host "Datastore: $($_s.Datastore)"
            Write-Host "NAA.ID: $($_s."NAA.ID")"
            Write-Host "VMs: $($vms.count)"
            $vms | Sort Name
        }
    }
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
        [switch]$report = $true,
        [string]$reportName = "$($PSScriptRoot)\Reports\SyslogSettings_"
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
                $h = Get-Cluster $cluster -ErrorAction Stop | Get-VMHost | sort Name
                $reportName += $cluster
                foreach($_h in $h) { Write-Host "$cluster - $_h - Collecting data"; $all += GetSyslogSettings $_h  }     
                }
            "Datacenter" {
                #Loop thrugh each host in the datacenter, collect metrics, append to $all
                $h = Get-Datacenter $datacenter -ErrorAction Stop | Get-VMHost | sort Name
                $reportName += $datacenter
                foreach($_h in $h) { Write-Host "$datacenter - $_h - Collecting data"; $all += GetSyslogSettings $_h  }
            }
            "vCenter" {
                #Loop all hosts in vCenter, collect metrics, append to $all
                $h = Get-VMHost -ErrorAction Stop | Sort Name 
                $reportName += "$($global:DefaultVIServer[0].name)"
                foreach($_h in $h) { Write-Host "$_h - Collecting data"; $all += GetSyslogSettings $_h }      
            }
        }
    }
    catch { Write-Host -ForegroundColor Red $_.Exception.Message; Return }

    $all | Sort-Object VMHost

    #Export report
    if($report -eq $true) {
        $reportName += "_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
        $all | Export-csv $reportName -notype
        Write-Host "Metrics have been written to $reportName"
    }
}

function GetSyslogSettings($h) {
    #Create an ordered PS Custom Object and store the metrics
    $results = [pscustomobject][ordered]@{
        VMHost = [string]$h.name
        Cluster = [string]$h.Parent
        "Syslog.global.logDir" = ($h | Get-AdvancedSetting -Name Syslog.global.logDir).Value
        "Syslog.global.logHost" = ($h | Get-AdvancedSetting -Name Syslog.global.logHost).Value
    }
    return $results
}

function SetException($h) {
    try { $ex = Get-VMHostFirewallException -VMHost $h -Name $exception -ErrorAction Stop }
    catch { Write-Host "$h - $exception Exception not found"; return }
    if($ex.Enabled -ne $enabled) {
        Write-Host "$h - changing $exception Exception to $enabled"
        Set-VMHostFirewallException -Exception $ex -Enabled $enabled
    } else { Write-Host "$h - $exception Exception is already $enabled" }
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
                $c = Get-Cluster $cluster -ErrorAction Stop | Get-VMHost | sort Name
                foreach($_c in $c) { SetException $_c } 
                }
            "Datacenter" { 
                $c = Get-Datacenter $datacenter -ErrorAction Stop | Get-VMHost | sort Name
                foreach($_c in $c) { SetException $_c }
            }
        }
    }
    catch { Write-Host $_.Exception.message -ForegroundColor Red; Return }
}

function GetHealth($h) {
    #retrieve NTPD information
    $ntpservice = Get-VMHostService -VMHost $h | Where-Object {$_.key -eq "ntpd"}
    $results = [pscustomobject][ordered]@{
        VMHost = $h.name
        VMHostTZ = $h.timezone
        NTPDisRunning = $ntpservice.running
        NTPDPolicy = $ntpservice.Policy
    }

    #retrieve NTP Servers configured, report only first 4
    $ntpserver = @($h | Get-VMHostNtpServer)
    for ($index = 0; $index -lt 4; $index++) {
        if ($ntpserver[$index]) { $results | Add-Member -Name "NTPServer$($index)" -Value $ntpserver[$index] -MemberType NoteProperty }
        else { $results| Add-Member -Name "NTPServer$($index)" -Value "none" -MemberType NoteProperty }
    }

    #calculate time difference between host and system this script is invoked from
    $hosttimesystem = get-view $h.ExtensionData.ConfigManager.DateTimeSystem
    $timedrift = ($hosttimesystem.QueryDateTime() - [DateTime]::UtcNow).TotalSeconds
    $results | Add-Member -Name "TimeDrift" -Value $timedrift -MemberType NoteProperty
    return $results
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
        [switch]$details = $false
    )

    $all = @()
    try { 
        switch($PSCmdlet.ParameterSetName) {
            "Parent" {
                $ParentObj = Get-VIObject -Name $Parent
                $ParentvCenter = $ParentObj.UID | ?{$_ -match "@(?<vcenter>.*):443"} | %{$matches['vcenter']}
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
            $vmhosts = $VMHostViews | Sort Name | Get-VIObjectByVIView
        }
    }
    catch { Write-Host -ForegroundColor Red $_.Exception.Message; Return }



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
        $log = Get-Log -key $_k.Key -VMHost $h | select -ExpandProperty Entries

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
        [Parameter(Position=0)]$vmhost,
        [string]$PuttyPath = "C:\scripts\putty.exe"
    )

    if(!$vmhost) {
        Write-Host "Querying vCenter for VMHosts..." 
        try { $vmhosts = Get-VMHost -ErrorAction Stop | sort Name }
        catch { Write-Host $_.Exceptption.Message -ForegroundColor Red; Return }

        #Draw a menu of VMHosts
        Write-Host "Select a VMHost"
        for($i = 1; $i -lt $vmhosts.count+1; $i++) { Write-Host "[$i] $($vmhosts[$i-1].name)" }
        $option = Read-Host

        #Switch the chosen $option and assign $vmhost
        switch -Regex ($option) {
            "\d" { $vmhost = $vmhosts[$option-1] }
            default { Write-Host "$option - Invalid Option"; Return }
        }
    }

    if(!(Test-Path $PuttyPath)) { Write-Host "$PuttyPath not found."; Return }
    try {
        #If SSH is not running, start it
        $ssh = Get-VMHost $vmhost -ErrorAction Stop | Get-VMHostService | ?{$_.Key -eq "TSM-SSH"}
        if($ssh.Running -ne $true) { 
            Write-Host "[$vmhost] Starting SSH"
            $ssh | Start-VMHostService -confirm:$false
        }
        #Connect Putty with SSH to root@$vmhost and wait for it to exit
        Start-Process -FilePath $PuttyPath -ArgumentList "-ssh vadmin@$vmhost" -Wait

        #If SSH is Running, stop it
        $ssh = Get-VMHost $vmhost -ErrorAction Stop | Get-VMHostService | ?{$_.Key -eq "TSM-SSH"}
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
        #[string]$exportPath = "C:\Scripts\Reports\Datastore_Inventory_$(Get-Date -Format yyyyMMdd_HHmmss).csv",
        #[string]$rdm_exportPath = "C:\Scripts\Reports\RDM_Inventory_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
    )

    $inventory = @()
    Get-Datastore | ?{$_.ExtensionData.Info.GetType().Name -eq "VmfsDatastoreInfo"} | %{
      if ($_) {
        Write-Host "[$($_.Name)] Collecting data"
        $ds = $_
        $inventory += $ds.ExtensionData.Info.Vmfs.Extent | Select-Object -Property @{Name="Datastore";Expression={$ds.Name}},@{Name="NAA.ID";Expression={$_.DiskName}}
      }
    }

    $inventory = $inventory | Select-Object -Unique -Property Datastore,"NAA.ID"
    if($inventory.count -gt 0) {
        Export-Results -results $inventory -exportName Datastore_Inventory
        #$inventory | Export-Csv -NoTypeInformation -Path $exportPath
        #Write-Host "Results exported to $exportPath" -ForegroundColor Green
    }

    Get-VM | Get-HardDisk -DiskType "RawPhysical","RawVirtual" | Select Parent,Name,DiskType,ScsiCanonicalName,DeviceName | Export-Results -results $_ -exportName RDM_Inventory
}

function Test-ConnectedvCenter {
    if($global:DefaultVIServers.count -eq 0) {
        Write-Host "Connect to a vCenter first using Connect-VIServer." -ForegroundColor Red
        return
    }

    if(@(Get-View -ViewType Datacenter -Property Name).Count -gt 0) { return $true }
    return $false
}

function Get-VMHostFirmware {
    [cmdletbinding()]
    param (
        $Name = "",
        $Parent,
        $Driver = "lpfc"
    )
    #Test-ConnectedvCenter
    if($Parent) {
        $ParentObj = Get-VIObject -Name $Parent
        $ParentvCenter = $ParentObj.UID | ?{$_ -match "@(?<vcenter>.*):443"} | %{$matches['vcenter']}
        $vmhosts = @(Get-View -Server $ParentvCenter -ViewType HostSystem -SearchRoot $ParentObj.ExtensionData.MoRef -Filter @{"Name"="$Name"})
        Write-Verbose "[$Name] Found $($vmhosts.count) VMHosts in $ParentvCenter\$Parent"
    } else {
        $vmhosts = @(Get-View -ViewType HostSystem -Filter @{"Name"="$Name"})
        Write-Verbose "[$Name] Found $($vmhosts.count) VMHosts"
    }

    $results = @()
    foreach($_v in $vmhosts) {
        $i++
        Write-Progress -Activity "Reading data from $($_v.Name)" -Status "[$i/$($vmhosts.count)]" -PercentComplete (($i/$vmhosts.count)*100)
        $esxcli = Get-EsxCLI -VMHost $_v.Name
        $nics = @($esxcli.network.nic.list())
        $nic0_details = @($esxcli.network.nic.get($nics[0].Name))
        $lpfc = @()
        write-debug "hi"
        $results += [pscustomobject][ordered]@{
            VMHost = $_v.Name
            NIC_Count = $nics.count
            NIC_Name = $nics[0].Description
            FCoE_Driver = ($esxcli.system.module.get($Driver)).Version
            FCoE_Firmware = $nic0_details.DriverInfo.FirmwareVersion
            NIC_Driver = $nic0_details.driverinfo.Version
        }
    }
    Write-Output $results
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
            $vc = $vm.uid | ?{$_ -match "@(?<vcenter>.*):443"} | %{$matches['vcenter']}
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
        $constraint = "RAM",
        $exclusions = "(AVAMARPROXY.*|-CRITICALSERVER.*)",
        $vmotionlimit = 4,
        [switch]$whatif = $true
    )

    foreach($c in $cluster) {
        #Group the VMs into Types
        $types = GetVMTypes $c
        #Create a plan to balance the Types based on allocated VM Host CPU ratio round robin
        switch($style) {
            "RoundRobin" { $vmhosts = BalanceRoundRobin $c $types $constraint }
            "Quick" { $vmhosts = BalanceQuick $c $types $constraint }
        }
        CompareBeforeAfter $vmhosts 
        MigrateVMs $vmhosts
    }
}

function BalanceQuick {
    [cmdletbinding()]
    param(
        $cluster,
        $types,
        $constraint
    )
    #goal: create a plan to reduce the load on the busiest vmhosts with least number of vmotions
    #Determine which VMHosts are Connected and Powered On
    $vmhosts = Get-Cluster $c | Get-VMHost | ?{$_.ConnectionState -eq "Connected" -and $_.PowerState -eq "PoweredOn"}
    $vmhosts | %{Add-Member -InputObject $_ -MemberType NoteProperty -Name VMs -Value @($_ | Get-VM) -Force }

    #Determine an "ideal" CPU ratio by dividing the sum of all VM CPUs by the sum of all VMHost CPUs
    $idealcpu = ($types.vms | Measure-Object -Sum -Property NumCpu).Sum / ($vmhosts | Measure-Object -Sum -Property NumCpu).sum
    
    #Determine an "ideal" RAM allocation by dividing the sum of all VM memory by the number of VMHosts
    $idealram = ($types.vms | Measure-Object -Sum -Property MemoryGB).Sum / $vmhosts.count
    Write-Host "[$c] Ideal CPU ratio is $idealcpu. Ideal RAM allocation is $idealram GB."

    $success = "empty"
    do {
        #Calculate CPU Ratio and Memory Allocation
        foreach($_v in $vmhosts) {
            Add-Member -InputObject $_v -MemberType NoteProperty -Name CPURatio -Value (($_v.vms | Measure-Object -Sum -Property NumCPU).sum / $_v.NumCpu) -Force
            Add-Member -InputObject $_v -MemberType NoteProperty -Name MemoryAllocated -Value ($_v.vms | Measure-Object -Sum -Property MemoryGB).sum -Force
        }

        $busy_hosts = @($vmhosts | Sort-Object MemoryAllocated -Descending | ?{$_.MemoryAllocated -gt $idealram})
        $idle_host = $vmhosts | Sort-Object MemoryAllocated | Select-Object -First 1
        
        if($busy_hosts.count -gt 0 -and $lastMove -ne "fail") {
            Write-Host "[$c] $($busy_hosts.count) hosts over $($idealram)GB. Looking for balancing opportunities."
            foreach($_host in $busy_hosts) {
                foreach($_vm in ($_host.vms | Sort-Object -Property MemoryGB -Descending)) {
                    if(($idle_host.MemoryAllocated + $_vm.MemoryGB) -lt $idealram) {
                        Write-Host "[$c] $($_host.Name) - $($_vm.name) $($_vm.memorygb)GB will vMotion to $($idle_host.name)"
                        Add-Member -InputObject $_host -MemberType NoteProperty -Name VMs -Value (@($_host.VMs) | ?{$_ -ne $_vm}) -Force
                        Add-Member -InputObject $_vm -MemberType NoteProperty -Name TargetVMHost -Value ($idle_host.Name) -Force
                        Add-Member -InputObject $idle_host -MemberType NoteProperty -Name VMs -Value (@($idle_host.VMs) + $_vm) -Force
                        $lastMove = "success"
                        break
                    } else {
                        write-Verbose "$($_vm.name) $($_vm.memorygb) will NOT fit on the idle host"
                        $lastMove = "fail"
                    }
                }
                if($lastMove -eq "success") { break }
                elseif($lastMove -eq "fail") { Write-Host "[$c] $($_host.name) - No balancing opportunities found" }
            }
        } else {
            Write-Host "[$c] More balancing not possible"
            $success = "turtles"
        }
    } while($success -ne "turtles")
    return $vmhosts
}

function GetVMTypes($c) {
    #Initialize array to store results
    $results = @()
    try {
    #Get all VMs in target cluster
        $vms = Get-Cluster $c -ErrorAction Stop | Get-VM | sort Name
    }

    catch { WriteLog "Startup-Failed" "Unable to find cluster '$c' on vCenter. Are you connected to vCenter?"; Return }
    Write-Host "[$($c)] Sorting $($vms.count) VMs"
    #Using regex, remove two or three numbers at the end of the VM, and add the Type as a NoteProperty on the VM object. This shortens prod-exchange101 into prod-exchange.
    $vms | %{ Add-Member -InputObject $_ -MemberType NoteProperty -Name Type -Value ($_.Name -replace "(\d{3}$|\d{2}$)") -Force }
   
    #Select the unique Types found
    foreach($t in ($vms | select -ExpandProperty Type -Unique)) {
        #Find all VMs matching the current Type
        $typevms = $vms | ?{$_.Type -eq $t}
        Write-Verbose "$($t): Found $($typevms.count) VMs"
        #Create an object to store the count, memory, and cpu for all VMs of the current Type
        $results += New-Object PSObject -Property @{
            Type = $t
            Count = $typevms.count
            MemoryGB = ($typevms | Measure-Object -Sum -Property MemoryGB).sum
            NumCpu = ($typevms | Measure-Object -Sum -Property NumCpu).sum
            VMs = $typevms
        }
    }
    #Return VM Types for further processing
    Write-Host "[$($c)] Sorted $(($results | Measure-Object -Property count -Sum).Sum) VMs into $($results.count) types"
    return $results | sort NumCpu
}

#Create a plan to balance VMs across a cluster by determing ideal CPU ratio and RAM allocation, then looping through VM types and assigning VMs to the VMHost with the lowest CPU Ratio.
#VMs are round robined onto hosts as long as the CPU Ratio is below 85% of the ideal CPU Ratio. If it is above, the VM is assigned to the VMHost with the lowest CPU Ratio.
#VMs are not actually moved, but rather just assigned locations to be moved to.
function BalanceRoundRobin($c,$types,$idealtype) {
    #Determine which VMHosts are Connected and Powered On
    $vmhosts = Get-Cluster $c | Get-VMHost | ?{$_.ConnectionState -eq "Connected" -and $_.PowerState -eq "PoweredOn"}
    #Determine an "ideal" CPU ratio by dividing the sum of all VM CPUs by the sum of all VMHost CPUs
    $idealcpu = ($types.vms | Measure-Object -Sum -Property NumCpu).Sum / ($vmhosts | Measure-Object -Sum -Property NumCpu).sum
    #Determine an "ideal" RAM allocation by dividing the sum of all VM memory by the number of VMHosts
    $idealram = ($types.vms | Measure-Object -Sum -Property MemoryGB).Sum / $vmhosts.count
    Write-Host "[$c] Ideal CPU ratio is $idealcpu. Ideal RAM allocation is $idealram GB."

    $hostindex = 0
    #For each of the Types
    foreach($t in $types) {
        #For each VM in the current Type
        foreach($vm in $t.vms) {
            $thisHost = $vmhosts[$hostindex]
            #Find out the CPU ratio of $vmhost[$hostindex] and add it as a property
            Add-Member -InputObject $thisHost -MemberType NoteProperty -Name CurrentRatio -Value (($thisHost.vms | Measure-Object -Sum -Property NumCPU).sum / $thisHost.NumCpu) -Force 
            #If the VMHost CurrentRatio is greater than 85% of the ideal ratio, find a new host for placement
            if($idealtype = "RAM") { $ideal = $idealram }
            elseif($idealtype -eq "CPU") { $ideal = $idealcpu }
            if(($thisHost.CurrentRatio)/$ideal -gt .85) { 
                Write-Verbose "[$($thisHost.name)] CPU Ratio $($thisHost.CurrentRatio) is too high. Looking for new host"
                #Calculate the CurrentRatio for all hosts in the cluster
                $vmhosts | %{Add-Member -InputObject $_ -MemberType NoteProperty -Name CurrentRatio -Value (($_.vms | Measure-Object -Sum -Property NumCPU).sum / $_.NumCpu) -Force}
                #Set the hostindex to the index of the VMHost with the lowest CurrentRatio
                $hostindex = $vmhosts.name.indexof(($vmhosts | sort CurrentRatio | select -First 1).name)
                $thisHost = $vmhosts[$hostindex]
                Write-Verbose "[$($thisHost.name)] Lowest ratio is $($thisHost.CurrentRatio)"
            }

            #Add a property to the VM to indicate its Target VMHost
            Write-Verbose "[$($thishost.name)] Assigning $($vm.name)"
            Add-Member -InputObject $vm -MemberType NoteProperty -Name TargetVMHost -Value ($thisHost.Name) -Force
            #If VMs have already been assigned to the Target VMHost
            if($thisHost.VMs) {
                #Update the VMs property and add the new VM
                Add-Member -InputObject $thisHost -MemberType NoteProperty -Name VMs -Value ((@($thisHost.VMs) + $vm)) -Force
            } else { Add-Member -InputObject $thisHost -MemberType NoteProperty -Name VMs -Value @($vm) -Force }
            #After each VM placement, increment $hostindex
            $hostindex++; if($hostindex -ge $vmhosts.count) { $hostindex = 0 }
        }
    }
    #Return balancing plan for further processing
    return $vmhosts | sort Name
}

#Compare the before and after CPU ratios and memory allocations
function CompareBeforeAfter($vmhosts) {
    #Intiailize array to store results
    $results = @()
    foreach($vmhost in $vmhosts) {
        #Calculate and store before/after details
        $currVMs = $vmhost | Get-VM | sort name
        $results += [pscustomobject][ordered]@{
            VMHost = $vmhost.Name
            BeforeCPURatio = "{0:P0}" -f (($currVMs | Measure-Object -Sum -Property NumCpu).sum / $vmhost.NumCpu)
            AfterCPURatio = "{0:P0}" -f (($vmhost.vms | Measure-Object -Sum -Property NumCpu).sum / $vmhost.NumCpu)
            BeforeMemoryGB = "{0:N2}" -f ($currVMs | Measure-Object -Sum -Property MemoryGB).sum
            AfterMemoryGB = "{0:N2}" -f ($vmhost.vms | Measure-Object -Sum -Property MemoryGB).sum
        }
    }
    #Display before/after details
    $results | Sort-Object AfterMemoryGB -Descending | Format-Table -AutoSize
}

function vMotionVM($vmstomove,$vm) {
    if($vm.TargetVMHost -eq $vm.VMHost) {
        #If the VM is already on the target VM Host, do nothing
        Write-Host "[$($vm.name)] Already on $($vm.TargetVMHost)"
    } else {
        #If $whatif is equal to false, move the VM to it's target host
        Write-Host "[$($vm.name)] vMotioning from $($vm.VMHost.name) to $($vm.TargetVMHost)"
        if($whatif -eq $false) { $vm | Move-VM -Destination $vm.TargetVMHost -RunAsync | out-null }
    }
    #Remove the VM from the move list, and return it
    return $vmstomove | ?{$_ -ne $vm}
}

#Choose a random VM and move it to it's target VM Host. Exclusions can be set. If too many vMotions are running at once, wait till below threshold, then continue.
function MigrateVMs($vmhosts) {
    #Determine which VMs are going to move
    #$vmstomove = @()
    $vmstomove = @($vmhosts.vms | ?{$_ -ne $null -and $_.name -notmatch $exclusions -and $_.targetvmhost -ne $null})
    if($vmstomove.Count -eq 0) {
        Write-Host "No VMs to balance."
        return
    }
    Write-Host "There are $($vmstomove.count) VMs to vMotion to complete this balancing. Hit Enter to start balancing"
    Read-Host

    #Determine which VMs are not going to move because of exclusions and will need to be manually migrated
    $excludedvms = $vmhosts.vms | ?{$_.name -match $exclusions -and $_.vmhost.name -ne $_.targetvmhost} | sort Name
    if($excludedvms) {
        Write-Host "`nThese VMs will not be vMotioned because of exclusions. Migrate these manually."
        $excludedvms | select name,@{n="SourceVMHost";e={$_.VMHost.name}},TargetVMHost
        Write-Host "`n"
    }

    #Loop while there are VMs left to move
    while($vmstomove.count -gt 0) {
        #Pick a random VM from the list
        $randomvm = $vmstomove | Get-Random
        
        #If the TargetVMHost of the random VM is the same as the last moved VM, pick a new VM. Repeat up to 5 times. This prevents all the vMotions from happening to the same VMHost.
        $i = 0
        while($randomvm.TargetVMHost -eq $lastvm.TargetVMHost -and $i -lt 5) {
            Write-Verbose "Finding a new VM to migrate..."
            $randomvm = $vmstomove | Get-Random
            $i++
        }

        #Get all the current vMotion tasks from vCenter
        $tasks = Get-Task -Status Running | ?{$_.name -like "*RelocateVM_Task*"}
        #If there are less running vMotion tasks than the limit....
        if($tasks.count -lt $vmotionlimit) { 
            #Move a random VM to it's target VM Host
            $vmstomove = vMotionVM $vmstomove $randomvm; $lastvm = $randomvm 
        } else {
            #While there are too many vMotions running...
            while($tasks.count -ge $vmotionlimit) {
                #Write a verbose message, wait 15 seconds, then check again
                Write-Verbose "vMotions are limited to $vmotionlimit"
                Start-Sleep -Seconds 15
                $tasks = Get-Task -Status Running | ?{$_.name -like "*RelocateVM_Task*"}
            }
            #Move a random VM to it's target VM Host
            $vmstomove = vMotionVM $vmstomove $randomvm; $lastvm = $randomvm
        }
    }
}

function Convert-SRMxmlToDRcsv {
    <#
    .DESCRIPTION
    Used https://ssbkang.com/2016/02/09/powercli-report-review-srm-source-destination-network-settings as a reference

    1. Generate a srm-export.xml by using dr-ip-reporter.exe on the VM with SRM 5.1
    dr-ip-reporter.exe --cfg "C:\Program Files\VMware\VMware vCenter Site Recovery Manager\config\vmware-dr.xml" --out "D:\temp\srm-export.xml" --vc "VCENTER.DOMAIN.LOCAL"

    2. Use this function to reswizzle the SRM export into three formats. For use with a script which updates DNS after SRM does the failover, this function resolves the 
    hostname for each VM, then exports a CSV of VMs with ProtectedIP and RecoveryIP. This export can be done for each protection group or as a single file.
    
    .EXAMPLE
    For migrating between SRM 5.1 to SRM 5.8+, a CSV with all Recovery Plan settings can be exported(nic index, ip, subnet, gateway, dns, suffixes)
    Convert-SRMxmlToDRcsv -fullExport

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
            $input_file.DrMappings.ProtectionGroups.ProtectionGroup | Sort Name | ForEach-Object {
                $protection_group = $_.Name
                $protected_ip = ""
                $recovery_ip = ""
                $_.ProtectedVm | Sort Name | ForEach-Object {
                    $vm = $_.Name
                    try { $vm_hostname = [system.net.dns]::gethostbyname($vm).hostname }
                    catch { 
                        Write-Host "[$vm] Failed to query hostname from DNS. Defaulting to $vm.corporate.citizensfla.com"
                        $vm_hostname = $vm + ".corporate.citizensfla.com"
                    }
                    $_.CustomizationSpec | Sort Site | ForEach-Object {
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
            $input_file.DrMappings.ProtectionGroups.ProtectionGroup | Sort Name | ForEach-Object {
                $protection_groups += [pscustomobject][ordered]@{
                    ProtectionGroup = $_.Name
                    ProtectionGroupID = $_.ID
                }
            }
            Write-Verbose "Detected $($protection_groups.count) protection groups"
            
            $recovery_plans = @()
            $input_file.DrMappings.RecoveryPlans.RecoveryPlan | Sort Name | ForEach-Object {
                $id = $_.ProtectionGroup
                $protection_group = $protection_groups | ?{$_.ProtectionGroupID -eq $id} | Select-Object -ExpandProperty ProtectionGroup
                $recovery_plans += [pscustomobject][ordered]@{
                    RecoveryPlan = $_.Name
                    ProtectionGroup = $protection_group
                }
            }
            Write-Verbose "Found $($recovery_plans.count) recovery plans"

            $results = @()
            $input_file.DrMappings.ProtectionGroups.ProtectionGroup | Sort Name | ForEach-Object {
                $protection_group = $_.Name
                $_.ProtectedVm | Sort Name | ForEach-Object {
                    $vm = $_.Name
                    $recovery_plan = $recovery_plans | ?{$_.ProtectionGroup -eq $protection_group} | Select-Object -ExpandProperty RecoveryPlan
                    $_.CustomizationSpec | Sort Site | ForEach-Object {
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
                                $ip_settings.dnsServerList.e | % { Set-Variable -Name "DNS$($_.id)" -Value $_."#text" }
                            }

                            if($dns_suffixes) {
                                $dns_suffixes.e | % { Set-Variable -Name "DNSSuffix$($_.id)" -Value $_."#text" }
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

filter Set-VMBIOSSetup 
{ 
   param( 
        [switch]$Disable, 
        [switch]$PassThru 
   )
   if($_ -is [VMware.VimAutomation.Types.VirtualMachine]) 
    { 
       trap { throw $_ }        
        
       $vmbo = New-Object VMware.Vim.VirtualMachineBootOptions 
       $vmbo.EnterBIOSSetup = $true 
        
       if($Disable) 
        { 
           $vmbo.EnterBIOSSetup = $false 
        } 

       $vmcs = New-Object VMware.Vim.VirtualMachineConfigSpec 
       $vmcs.BootOptions = $vmbo 

        ($_ | Get-View).ReconfigVM($vmcs) 
        
       if($PassThru) 
        { 
           Get-VM $_ 
        } 
    } 
   else 
    { 
       Write-Error “Wrong object type. Only virtual machine objects are allowed.“ 
    } 
} 

function Test-VMX {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True,Position=1)]
        [string]$Name
    )

    if($Name.EndsWith(".txt")) { 
        $Names = @(Get-Content $Name) 
    } else { $Names = $Name }

    foreach($_name in $Names ) {
        try { 
            Get-VM $_name | Set-VMBIOSSetup 
            Get-VM $_name | Set-VMBIOSSetup -Disable
            Write-Host "[$_name] VMX modified successfully"
        }
        catch {
            Write-Host "[$_name] Failed to enable/disable forcing entry to BIOS on next startup"
            $_name | Out-File bad_vmx.txt -Append
        }
    }
}