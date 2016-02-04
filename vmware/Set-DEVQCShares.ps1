[cmdletbinding()]
Param (
    $configfile = "Set-DEVQCShares.csv",
    $catchall = "zMisc"
)

Add-PSSnapin vmware.vimautomation.core
Connect-VIServer my-vcenter.domain.local | Out-Null

function getPool($cluster,$poolname) {
    try {
        $rpool = Get-ResourcePool -Location $cluster -Name $poolname -ErrorAction Stop
        Write-Host "$($poolname): Pre-existing Resource Pool found"
    }
    catch {
        Write-Host "$($poolname): Creating Resource Pool"
        New-ResourcePool -Location $cluster -Name $poolname | Out-Null
        $rpool = Get-ResourcePool -Location $cluster -Name $poolname
    }
    return $rpool
}

Connect-VIServer my-vcenter.domain.local | Out-Null
$config = @(Import-Csv $configfile)
foreach($s in $config) {
    #Get or create resource pool
    $cluster = Get-Cluster $s.cluster
    $rpool = getPool $cluster $s.ResourcePool

    #Remove non-matching VMs from pool
    $vms = Get-ResourcePool -Location $cluster -Name $s.ResourcePool | Get-VM | sort Name
    $defaultpool = Get-ResourcePool -Location $cluster -name Resources
    foreach($vm in $vms) {
        if(!($vm.Name -match "$($s.RegexInclude)" -and $vm.Name -notmatch "$($s.RegexExclude)")) {
            Write-Host "$($s.ResourcePool): Moving $($vm.name) to default resource pool"
            Move-VM -Destination $defaultpool -vm $vm -RunAsync | Out-Null
        }
    }

    #Get list of VMs that belong in pool and set pool CPU shares
    $vms = Get-Cluster $s.cluster | Get-VM | Sort Name | ?{$_.Name -match $($s.RegexInclude)} | ?{$_.Name -notmatch $($s.RegexExclude)}
    if($vms) {
        $poolshares = ($vms | Measure-Object -Sum -Property NumCpu).Sum * $s.SharesPerCore
        if($rpool.NumCpuShares -ne $poolshares) {
            Write-Host "$($s.ResourcePool): Changing CPU shares from $($rpool.numcpushares) to $poolshares"
            Set-ResourcePool -ResourcePool $rpool -CpuSharesLevel Custom -NumCpuShares $poolshares | Out-Null
        }

        #Move VMs into pool
        foreach($vm in $vms) {
            if($vm.ResourcePool -ne $rpool) {
                Write-Host "$($s.ResourcePool): Moving $($vm.Name) into Resource Pool"
                Move-VM -Destination $rpool -vm $vm -RunAsync | Out-Null
            } else { Write-Verbose "$($s.ResourcePool): $($vm.Name) already in the pool" }
        }
    } else { Write-Host "$($s.ResourcePool): No VM found that matches $($s.RegexInclude) and does not match $($s.RegexExclude)" }
}

$catch_clusters = @("DEVQC")
foreach($cluster in $catch_clusters) {
    #Move VMs into catch all
    $vms = Get-Cluster $cluster | get-vm | sort Name | ?{$_.ResourcePool.name -eq "Resources" }
    $dpool = getPool $cluster $catchall
    Write-Host "$($dpool): Moving $($vms.count) VMs into the catch all resource pool"
    foreach($vm in $vms) {
        Write-Host "$($dpool): Moving $($vm.name) to resource pool"
        Move-VM -Destination $dpool -vm $vm | Out-Null 
    }

    #Determine and set CPU shares for catch all
    $dpool = Get-ResourcePool -Location $cluster -Name $catchall
    $vms =  $dpool | Get-VM
    $poolshares = ($vms | Measure-Object -Sum -Property NumCpu).Sum * 750
    if($dpool.NumCpuShares -ne $poolshares) {
        Write-Host "$($dpool.name): Changing CPU shares from $($dpool.numcpushares) to $poolshares"
        Set-ResourcePool -ResourcePool $dpool -CpuSharesLevel Custom -NumCpuShares $poolshares | Out-Null
    }
}