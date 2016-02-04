[cmdletbinding()]
Param (
    $sourcecluster = "sourceCluster",
    $destcluster = "destCluster",
    $transferlimit = 3500,
    $svmotionlimit = 5,
    $servers,
    $sourcevmcluster
)

function MoveVM($vm) {
    $destdatastore = get-datastorecluster $destcluster | get-datastore | sort freespacegb -descending | select -first 1 | Get-Random
    $vmused = "{0:N2}" -f $vm.usedspacegb
    $destdatastorefree = "{0:N2}" -f $destdatastore.freespacegb
    Write-Verbose "Migrating $($vm.name)`($vmused GB`) to $($destdatastore.name)`($destdatastorefree GB Free`)"
    $vm | Move-VM -Datastore $destdatastore -RunAsync | Out-Null
}

if($servers) {  
    Write-Verbose "Getting VM objects"
    if($servers.EndsWith(".txt")) { $servers = gc $servers }
    $tomove = $servers | %{get-vm $_}
    $tomovesize = ($tomove | Measure-Object -Sum -Property UsedSpaceGB).sum
} elseif($sourcevmcluster) {
    $allvms = Get-Cluster $sourcevmcluster | get-vm | sort name
    $destdatastores = get-datastorecluster $destcluster | get-datastore | select -expand Name | sort
    $vmsondatastore = @()
    foreach($d in $destdatastores) { $vmsondatastore += get-vm -Datastore $d }
    $tomove = Compare-Object $allvms $vmsondatastore -PassThru
    $tomovesize = ($tomove | Measure-Object -Sum -Property UsedSpaceGB).sum
} else {
    $vms = get-datastorecluster $sourcecluster | get-datastore | get-vm | sort name
    $tomove = @(); $tomovesize = 0

    Write-Verbose "Finding random VMs to migrate"; $j = 0
    while($tomovesize -lt $transferlimit) {
        $randomvm = $vms | Get-Random
        $randomvmused = "{0:N2}" -f $randomvm.usedspacegb
        if(($randomvm.usedspacegb + $tomovesize) -lt $transferlimit -and $randomvm.usedspacegb -ne $null) {
            Write-Verbose "$($randomvm.name): Random VM added to queue with $randomvmused GB";
            $vms = $vms | ?{$_ -ne $randomvm}; $tomove += $randomvm
        } else { break }
        $tomovesize = ($tomove | Measure-Object -Sum -Property UsedSpaceGB).sum
    }

    Write-Verbose "Finding small VMs to migrate"
    $vms = $vms | sort UsedSpaceGB; $i = 0
    while($tomovesize -lt $transferlimit -and $i -lt $vms.count) {
        $i
        $smallvm = $vms[$i]
        $smallvmused = "{0:N2}" -f $smallvm.UsedSpaceGB
        if(($smallvmused.usedspacegb + $tomovesize) -lt $transferlimit) { 
            Write-Verbose "$($smallvm.name): Small VM added to queue with $smallvmused GB";
            $vms = $vms | ?{$_ -ne $smallvm}; $tomove += $smallvm
        } else { break }
        $tomovesize = ($tomove | Measure-Object -Sum -Property UsedSpaceGB).sum; $i++
    }
}

Write-Host "$("{0:N2}" -f $tomovesize) GB in $($tomove.count) VMs will be migrated $svmotionlimit at a time from to $destcluster"
$tomove | select Name,PowerState,@{n="UsedSpaceGB";e={"{0:N2}" -f $_.usedspacegb}}
$option = Read-Host "continue, exit"
switch($option) {
    "continue" { }
    "c" { }
    "exit" { Exit }
    default { Exit }
}

foreach($vm in $tomove) {
    $tasks = get-task -status Running | ?{$_.name -like "*RelocateVM_Task*"}
    if($tasks.count -lt $svmotionlimit) { MoveVM $vm } else {
        while($tasks.count -ge $svmotionlimit) {
            Write-Verbose "Storage vMotions are limited to $svmotionlimit"
            Start-Sleep -Seconds 60
            $tasks = get-task -status Running | ?{$_.name -like "*RelocateVM_Task*"}
        }
        MoveVM $vm
    }
}