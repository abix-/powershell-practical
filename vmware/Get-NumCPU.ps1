cvi | Out-Null

function writeToObj($server,$hostcpu,$ratio,$allocatedcpu) {
    $obj= New-Object PSObject -Property @{
        Host = $server
        HostCPUs = $hostcpu
        AllocatedCPUs = $allocatedcpu
        Ratio = $ratio
    }
    return $obj
}


$servers = Get-Cluster | Get-VMHost

$allobj = @()
foreach($server in $servers) {
    Write-Host "Working on $($server.name)"
    $vms = get-vmhost $server.Name | get-vm

    $totalcpu = 0
    foreach($vm in $vms) {
        $totalcpu += $vm.numcpu
    }

    $ratio = $totalcpu / $server.NumCPU

    $obj = writeToObj $server.Name $server.NumCPU $ratio $totalcpu
    $allobj += $obj
}

$allobj | select Host,HostCPUs,AllocatedCPUs,Ratio | Sort Host