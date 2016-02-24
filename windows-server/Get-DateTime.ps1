[cmdletbinding()]
Param (
    $servers
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }

function writeToObj($server,$datetime="N/A") {
    $obj= New-Object PSObject -Property @{
        Server = $server
        "Date/Time" = $datetime
    }
    return $obj
}

$allobj = @()
foreach ($server in $servers){
    Write-Host "Working on $server"
    $dt_str = "N/A"
    $dt = gwmi win32_operatingsystem -computer $server
    if($dt) {
        $dt_str = $dt.converttodatetime($dt.localdatetime)
        $obj = writeToObj $server $dt_str
        $allobj += $obj
    }
}

$allobj | select Server,"Date/Time"