function SetException($h) {
    try { $ex = Get-VMHostFirewallException -VMHost $h -Name $exception -ErrorAction Stop }
    catch { Write-Host "$h - $exception Exception not found"; return }
    if($ex.Enabled -ne $enabled) {
        Write-Host "$h - changing $exception Exception to $enabled"
        Set-VMHostFirewallException -Exception $ex -Enabled $enabled
    } else { Write-Host "$h - $exception Exception is already $enabled" }
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
        $disks = $v | Get-HardDisk -ErrorAction Stop | Where-Object{$_.filename -notlike "*snap*"}
        foreach($_d in $disks.Filename) { $ds_list += $_d.Substring(1,$_d.IndexOf("]") - 1) }
        $ds_list = $ds_list | Select-Object -Unique
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

function BalanceQuick {
    [cmdletbinding()]
    param(
        $cluster,
        $types,
        $constraint
    )
    #goal: create a plan to reduce the load on the busiest vmhosts with least number of vmotions
    #Determine which VMHosts are Connected and Powered On
    $vmhosts = Get-Cluster $c | Get-VMHost | Where-Object{$_.ConnectionState -eq "Connected" -and $_.PowerState -eq "PoweredOn"}
    $vmhosts | ForEach-Object{Add-Member -InputObject $_ -MemberType NoteProperty -Name VMs -Value @($_ | Get-VM) -Force }

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

        $busy_hosts = @($vmhosts | Sort-Object MemoryAllocated -Descending | Where-Object{$_.MemoryAllocated -gt $idealram})
        $idle_host = $vmhosts | Sort-Object MemoryAllocated | Select-Object -First 1
        
        if($busy_hosts.count -gt 0 -and $lastMove -ne "fail") {
            Write-Host "[$c] $($busy_hosts.count) hosts over $($idealram)GB. Looking for balancing opportunities."
            foreach($_host in $busy_hosts) {
                foreach($_vm in ($_host.vms | Sort-Object -Property MemoryGB -Descending)) {
                    if(($idle_host.MemoryAllocated + $_vm.MemoryGB) -lt $idealram) {
                        Write-Host "[$c] $($_host.Name) - $($_vm.name) $($_vm.memorygb)GB will vMotion to $($idle_host.name)"
                        Add-Member -InputObject $_host -MemberType NoteProperty -Name VMs -Value (@($_host.VMs) | Where-Object{$_ -ne $_vm}) -Force
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
        $vms = Get-Cluster $c -ErrorAction Stop | Get-VM | Sort-Object Name
    }

    catch { WriteLog "Startup-Failed" "Unable to find cluster '$c' on vCenter. Are you connected to vCenter?"; Return }
    Write-Host "[$($c)] Sorting $($vms.count) VMs"
    #Using regex, remove two or three numbers at the end of the VM, and add the Type as a NoteProperty on the VM object. This shortens prod-exchange101 into prod-exchange.
    $vms | ForEach-Object{ Add-Member -InputObject $_ -MemberType NoteProperty -Name Type -Value ($_.Name -replace "(\d{3}$|\d{2}$)") -Force }
   
    #Select the unique Types found
    foreach($t in ($vms | Select-Object -ExpandProperty Type -Unique)) {
        #Find all VMs matching the current Type
        $typevms = $vms | Where-Object{$_.Type -eq $t}
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
    return $results | Sort-Object NumCpu
}

#Create a plan to balance VMs across a cluster by determing ideal CPU ratio and RAM allocation, then looping through VM types and assigning VMs to the VMHost with the lowest CPU Ratio.
#VMs are round robined onto hosts as long as the CPU Ratio is below 85% of the ideal CPU Ratio. If it is above, the VM is assigned to the VMHost with the lowest CPU Ratio.
#VMs are not actually moved, but rather just assigned locations to be moved to.
function BalanceRoundRobin($c,$types,$idealtype) {
    #Determine which VMHosts are Connected and Powered On
    $vmhosts = Get-Cluster $c | Get-VMHost | Where-Object{$_.ConnectionState -eq "Connected" -and $_.PowerState -eq "PoweredOn"}
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
                $vmhosts | ForEach-Object{Add-Member -InputObject $_ -MemberType NoteProperty -Name CurrentRatio -Value (($_.vms | Measure-Object -Sum -Property NumCPU).sum / $_.NumCpu) -Force}
                #Set the hostindex to the index of the VMHost with the lowest CurrentRatio
                $hostindex = $vmhosts.name.indexof(($vmhosts | Sort-Object CurrentRatio | Select-Object -First 1).name)
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
    return $vmhosts | Sort-Object Name
}

#Compare the before and after CPU ratios and memory allocations
function CompareBeforeAfter($vmhosts) {
    #Intiailize array to store results
    $results = @()
    foreach($vmhost in $vmhosts) {
        #Calculate and store before/after details
        $currVMs = $vmhost | Get-VM | Sort-Object name
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
    return $vmstomove | Where-Object{$_ -ne $vm}
}

#Choose a random VM and move it to it's target VM Host. Exclusions can be set. If too many vMotions are running at once, wait till below threshold, then continue.
function MigrateVMs($vmhosts) {
    #Determine which VMs are going to move
    #$vmstomove = @()
    $vmstomove = @($vmhosts.vms | Where-Object{$_ -ne $null -and $_.name -notmatch $exclusions -and $_.targetvmhost -ne $null})
    if($vmstomove.Count -eq 0) {
        Write-Host "No VMs to balance."
        return
    }
    Write-Host "There are $($vmstomove.count) VMs to vMotion to complete this balancing. Hit Enter to start balancing"
    Read-Host

    #Determine which VMs are not going to move because of exclusions and will need to be manually migrated
    $excludedvms = $vmhosts.vms | Where-Object{$_.name -match $exclusions -and $_.vmhost.name -ne $_.targetvmhost} | Sort-Object Name
    if($excludedvms) {
        Write-Host "`nThese VMs will not be vMotioned because of exclusions. Migrate these manually."
        $excludedvms | Select-Object name,@{n="SourceVMHost";e={$_.VMHost.name}},TargetVMHost
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
        $tasks = Get-Task -Status Running | Where-Object{$_.name -like "*RelocateVM_Task*"}
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
                $tasks = Get-Task -Status Running | Where-Object{$_.name -like "*RelocateVM_Task*"}
            }
            #Move a random VM to it's target VM Host
            $vmstomove = vMotionVM $vmstomove $randomvm; $lastvm = $randomvm
        }
    }
}

function MoveVM($vm) {
    $destdatastore = get-datastorecluster $destcluster | get-datastore | Sort-Object freespacegb -descending | Select-Object -first 1
    $vmused = "{0:N2}" -f $vm.usedspacegb
    $destdatastorefree = "{0:N2}" -f $destdatastore.freespacegb
    Write-Verbose "Migrating $($vm.name)`($vmused GB`) to $($destdatastore.name)`($destdatastorefree GB Free`)"
    $vm | Move-VM -Datastore $destdatastore -RunAsync | Out-Null
}

function MoveVMDK {
    [cmdletbinding()]
    param (
        $VMDK,
        [Parameter(ParameterSetName="Datastore")]$DestinationDatastore,
        [Parameter(ParameterSetName="DatastoreCluster")]$DestinationDatastoreCluster
    )

    switch($PSCmdlet.ParameterSetName) {
        "Datastore" { $destdatastore = Get-Datastore $DestinationDatastore }
        "DatastoreCluster" { $destdatastore = Get-DatastoreCluster $DestinationDatastore | Get-Datastore | Sort-Object freespacegb -descending | Select-Object -first 1 }
    }

    $vmdkcapacity = "{0:N2}" -f $vmdk.capacitygb
    $destdatastorefree = "{0:N2}" -f $destdatastore.freespacegb
    Write-Host "Migrating $($vmdk.filename)`($vmdkcapacity GB`) to $($destdatastore.name)`($destdatastorefree GB Free`)"
    Move-HardDisk -HardDisk $vmdk -Datastore $destdatastore -RunAsync -Confirm:$false
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

function SetException($h) {
    try { $ex = Get-VMHostFirewallException -VMHost $h -Name $exception -ErrorAction Stop }
    catch { Write-Host "$h - $exception Exception not found"; return }
    if($ex.Enabled -ne $enabled) {
        Write-Host "$h - changing $exception Exception to $enabled"
        Set-VMHostFirewallException -Exception $ex -Enabled $enabled
    } else { Write-Host "$h - $exception Exception is already $enabled" }
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
