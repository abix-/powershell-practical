[cmdletbinding()]
Param (
    $vmhost
)

function writeToObj($vmhost,$firmware="N/A",$driver="N/A") {
    return 
}

if($vmhost.EndsWith(".txt")) { $vmhost = gc $vmhost }

$allobj = @()
foreach($v in $vmhost) {
    $i++
    $nic = "N/A"
    Write-Progress -Activity "Reading data from $v" -Status "[$i/$($vmhost.count)]" -PercentComplete (($i/$vmhost.count)*100)
    $esxcli = Get-EsxCli -VMHost $v
    $nic = $esxcli.network.nic.get("vmnic4")
    $allobj += New-Object PSObject -Property @{
        Host = $vmhost
        Firmware = $firmware
        Driver = $driver
    }
    
    writeToObj $v $nic.driverinfo.firmwareversion $nic.driverinfo.version
}

$allobj | select Host, Firmware, Driver