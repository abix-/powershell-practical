[cmdletbinding()]
Param (
    $servers
)

function writeToObj($server,$status="Offline",$firmware="N/A",$driver="N/A",$wwn="N/A") {
    $obj= New-Object PSObject -Property @{
            Server = $server
            Status = $status
            Firmware = $firmware
            Driver = $driver
            WWN = $wwn
    }
    return $obj
}

if($servers.EndsWith(".txt")) { $servers = gc $servers }

$allobj = @()
foreach($v in $servers) {
    $i++
    Write-Progress -Activity "Reading data from $v" -Status "[$i/$($servers.count)]" -PercentComplete (($i/$servers.count)*100)
    if((Test-Connection -ComputerName $v -count 1 -ErrorAction 0)) {
        try { $hbas = gwmi -class MSFC_FCAdapterHBAAttributes -computer $v -Namespace "root\WMI" -ErrorAction Stop | ?{$_.model -like "QLE8242"} }
        catch { $hbas = $null }
        if($hbas) {
            #foreach($hba in $hbas) {
                #$wwn =  (($hbas[0].NodeWWN) | ForEach-Object {"{0:x}" -f $_}) -join ":" 
                $allobj += writeToObj $v "Online" $hbas[0].firmwareversion $hbas[0].driverversion
            #}
        } else { $allobj += writeToObj $v "No 8242 found" }
    } else { $allobj += writeToObj $v }
}

$allobj | select Server, Status, Firmware, Driver | FT