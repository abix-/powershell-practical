[cmdletbinding()]
Param (
    $clusters = @("MyCluster"),
    $exclusions = "(-WTFLOL.*)",
    $vmotionlimit = 5,
    [switch]$whatif = $true,
    $MaintenanceMode
)

function GetClusterTypes($c) {
    $all = @()
    if(!$MaintenanceMode) { $vms = get-cluster $c | Get-VM | sort name }
    else { $vms = get-cluster $c | Get-VM | sort name | ?{$_.VMHost.Name -eq $MaintenanceMode } }
    $vms | %{add-member -inputobject $_ -membertype noteproperty -name Type -value ($_.name -replace "\d{3}") -force}
   
    $othervms = @()
    foreach($t in ($vms | select -ExpandProperty Type -Unique)) {
        $typevms = $vms | ?{$_.name -like "$t*"}
        Write-Verbose "$($t): Found $($typevms.count) VMs"
        if($typevms.count -gt 1) {
            $all += New-Object PSObject -Property @{
                Type = $t
                Count = $typevms.count
                MemoryGB = ($typevms | Measure-Object -Sum -Property MemoryGB).sum
                NumCpu = ($typevms | Measure-Object -Sum -Property NumCpu).sum
                VMs = $typevms
            }
        } else { $othervms += $typevms }
    }

    if($othervms.count -gt 0) {
        $all += New-Object PSObject -Property @{
            Type = "Other"
            Count = $othervms.count
            MemoryGB = ($othervms | Measure-Object -Sum -Property MemoryGB).sum
            NumCpu = ($othervms | Measure-Object -Sum -Property NumCpu).sum
            VMs = $othervms
        }
    }
    return $all | sort NumCpu
}

function BalanceByOrder($c) {
    if(!$MaintenanceMode) { 
        $vmhosts = Get-Cluster $c | Get-VMHost | ?{$_.ConnectionState -eq "Connected" -and $_.PowerState -eq "PoweredOn"}
    }
    else {
        Write-Host "All VMs will be moved off of $MaintenanceMode"
        $vmhosts = Get-Cluster $c | Get-VMHost | ?{$_.ConnectionState -eq "Connected" -and $_.PowerState -eq "PoweredOn" -and $_.Name -ne $MaintenanceMode} 
    }
    $types = GetClusterTypes $c
    $idealratio = ($types.vms | Measure-Object -Sum -Property NumCpu).Sum / ($vmhosts | Measure-Object -Sum -Property NumCpu).sum
    $idealram = ($types.vms | Measure-Object -Sum -Property MemoryGB).Sum / $vmhosts.count

    Write-Host "Ideal CPU ratio is $idealratio. Ideal RAM allocation is $idealram GB."
    $hostindex = 0
    foreach($t in $types) {
        foreach($vm in $t.vms) {
            Add-Member -InputObject $vmhosts[$hostindex] -MemberType NoteProperty -Name CurrentRatio -Value (($vmhosts[$hostindex].vms | Measure-Object -Sum -Property NumCPU).sum / $vmhosts[$hostindex].NumCpu) -Force 
            if(($vmhosts[$hostindex].CurrentRatio)/$idealratio -gt .85) { 
                Write-Verbose "Need to find a new host because $($vmhosts[$hostindex].CurrentRatio) is too high on $($vmhosts[$hostindex].name)"
                $vmhosts | %{Add-Member -InputObject $_ -MemberType NoteProperty -Name CurrentRatio -Value (($_.vms | Measure-Object -Sum -Property NumCPU).sum / $_.NumCpu) -Force}
                $hostindex = $vmhosts.name.indexof(($vmhosts | sort CurrentRatio | select -First 1).name)
                Write-Verbose "Ratio is lowest on $($vmhosts[$hostindex].name) with a ratio of $($vmhosts[$hostindex].CurrentRatio)"
            }

            Write-Verbose "$($vm.name) goes on $($vmhosts[$hostindex].name)"
            Add-Member -InputObject $vm -MemberType NoteProperty -Name TargetVMHost -Value ($vmhosts[$hostindex].Name) -Force
            if($vmhosts[$hostindex]) {
                $temp = @($vmhosts[$hostindex].VMs); $temp += $vm
                Add-Member -inputobject $vmhosts[$hostindex] -membertype noteproperty -name VMs -value @($temp) -force
            } else { Add-Member -inputobject $vmhosts[$hostindex] -membertype noteproperty -name VMs -value @($vm) -force }
            $hostindex++; if($hostindex -ge $vmhosts.count) { $hostindex = 0 }
        }
    }
    return $vmhosts | sort Name
}


function CompareLoads($vmhosts) {
    foreach($vmhost in $vmhosts) {
        $prodvms = $vmhost | Get-VM | sort name
        $prodratio = ($prodvms | Measure-Object -Sum -Property NumCpu).sum / $vmhost.NumCpu
        $newratio = ($vmhost.vms | Measure-Object -Sum -Property NumCpu).sum / $vmhost.NumCpu
        Write-Host "$($vmhost.name): CPU Ratio : From $prodratio to $newratio"

        $prodgb = ($prodvms | Measure-Object -Sum -Property MemoryGB).sum
        $newgb = ($vmhost.vms | Measure-Object -Sum -Property MemoryGB).sum
        Write-Host "$($vmhost.name): RAM allocation : From $prodgb GB to $newgb GB"
    }
}

function vMotionVM($vmstomove,$vm) {
    if($vm.TargetVMHost -eq $vm.VMHost) {
        Write-Host "$($vm.name): Already on $($vm.TargetVMHost)"
    } else { 
        Write-Host "$($vm.name): vMotioning to $($vm.TargetVMHost)"
        if($whatif -eq $false) { $vm | Move-VM -Destination $vm.TargetVMHost -RunAsync }
    }
    return $vmstomove | ?{$_ -ne $randomvm}
}

function MigrateVMs($vmhosts) {
    $vmstomove = $vmhosts.vms | ?{$_ -ne $null -and $_.name -notmatch $exclusions}
    $excludedvms = $vmhosts.vms | ?{$_.name -match $exclusions -and $_.vmhost.name -ne $_.targetvmhost} | sort Name
    if($excludedvms) {
        Write-Host "`nThese VMs will not be vMotioned because of exclusions. Migrate these manually."
        $excludedvms | select name,@{n="SourceVMHost";e={$_.VMHost.name}},TargetVMHost
        Write-Host "`n"
    }

    while($vmstomove.count -gt 0) {
        $randomvm = $vmstomove | Get-Random
        $i = 0
        while($randomvm.TargetVMHost -eq $lastvm.TargetVMHost -and $i -lt 5) {
            Write-Verbose "Finding a new VM to move..."
            $randomvm = $vmstomove | Get-Random
            $i++
        }

        $tasks = Get-Task -Status Running | ?{$_.name -like "*RelocateVM_Task*"}
        if($tasks.count -lt $vmotionlimit) { 
            $vmstomove = vMotionVM $vmstomove $randomvm; $lastvm = $randomvm 
        } else {
            while($tasks.count -ge $vmotionlimit) {
                Write-Verbose "vMotions are limited to $vmotionlimit"
                Start-Sleep -Seconds 15
                $tasks = Get-Task -Status Running | ?{$_.name -like "*RelocateVM_Task*"}
            }
            $vmstomove = vMotionVM $vmstomove $randomvm; $lastvm = $randomvm
        }
    }
}

foreach($c in $clusters) {
    $types = GetClusterTypes $c
    $vmhosts = BalancebyOrder $c
    CompareLoads $vmhosts
    MigrateVMs $vmhosts
    if($MaintenanceMode) { $mainthost = Get-VMHost $MaintenanceMode; Set-VMHost -State Maintenance -VMHost $mainthost }
}