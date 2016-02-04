$vmhosts = Get-VMHost

$allprocessors = 0
foreach($vmhost in $vmhosts) {
    $processors = $vmhost.extensiondata.hardware.cpuinfo.numcpupackages
    Write-Host "$($vmhost.name) - $processors"
    $allprocessors += $processors
}

Write-Host "There are currently $allprocessors in use"