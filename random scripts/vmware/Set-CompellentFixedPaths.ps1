[cmdletbinding()]
Param (
    $cluster
)

foreach($c in $cluster) { $i = 0
    foreach($lun in (Get-Cluster $c | Get-VMHost | Get-ScsiLun | ?{$_.Vendor -eq "COMPELNT" -and $_.CapacityMB -GT 100000})) {
        $paths = Get-ScsiLunPath -ScsiLun $lun
        if($i -ge $paths.count) { $i = 0 }
        Write-Host "Setting $($lun.runtimename) to $($paths[$i].name)"
        #Set-ScsiLun -ScsiLun $lun -MultipathPolicy Fixed -PreferredPath $paths[$i]
        #Start-Sleep -Seconds 30; 
        $i++
    }
}


#Get-Cluster ClusterNameHere | Get-VMHost | Get-ScsiLun | where {$_.Vendor -eq "COMPELNT" –and $_.Multipathpolicy -eq "Fixed"} | Set-ScsiLun -Multipathpolicy RoundRobin