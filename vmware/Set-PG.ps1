$vms = Get-Cluster CLUSTER | Get-VM | sort Name
$pgs = $newdev | select -Unique -ExpandProperty NIC1_PortGroup 
foreach($_p in $pgs) {
    $destpg = Get-VirtualPortGroup -name $_p
    foreach($_n in $newdev) {
        $vm = $null
        $adapter = $null
        try {
            $vm = $vms | ?{$_.name -eq $_n.Name} 
            if($vm -ne $null) {
                Write-Host "$($_n.Name) - Starting config"
                $adapter = $vm | Get-NetworkAdapter -ErrorAction STOP
                if($adapter.NetworkName -ne $destpg.Name) {
                    $vm
                    $adapter
                    Write-Host "$($_n.Name) - Setting $($adapter.name) port group to $($destpg.Name)"
                    Set-NetworkAdapter -NetworkAdapter $adapter -Portgroup $destpg -Confirm:$false 
                } else { Write-Host "$($_n.Name) - Port group is already set to $($destpg.Name)" }
            } else { Write-Host "$($_n.Name) - No VM found. Skipping" }
        }

        catch { Write-Host $_.Exception -ForegroundColor Red  }
    }
}