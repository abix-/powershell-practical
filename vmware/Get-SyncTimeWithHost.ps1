[cmdletbinding()]
Param (
    $servers = "server",
    [switch]$all = $false
)

function writeToObj($server,$synctime) {
    return New-Object PSObject -Property @{
        Server = $server
        SyncTimeWithHost = $synctime
    }
}

function getAllViews() {
    try { Write-Host "Querying vCenter for all views"; $VMViews = Get-View -ViewType VirtualMachine | Sort Name }
    catch { Write-Host "Failed to retreive data from vCenter. Are you connected?"; Exit }
    return $VMViews
}

if($servers.EndsWith(".txt")) { $servers = gc $servers }

$i = 0
$allobj = @()
if($all -eq $false) {
    if($servers.count -gt 30) {
        $VMViews = getAllViews
        foreach($server in $servers) {
            $i++; Write-Progress -Activity "Collecting data for $server" -Status "[$i/$($servers.count)]" -PercentComplete (($i/$servers.count)*100)
            $VMView = $VMViews | ?{$_.name -like $server}
            $allobj += writeToObj $server $VMView.Config.Tools.SyncTimeWithHost
        }
    } else {
        foreach($server in $servers) {
            $i++; Write-Progress -Activity "Collecting data for $server" -Status "[$i/$($servers.count)]" -PercentComplete (($i/$servers.count)*100)
            $VMView = Get-View -ViewType VirtualMachine -filter @{"Name"="$server"}
            $allobj += writeToObj $server $VMView.Config.Tools.SyncTimeWithHost
        }
    }
} else {
    $VMViews = getAllViews
    foreach($VMView in $VMViews) {
        $i++; Write-Progress -Activity "Collecting data for $($vmview.name)" -Status "[$i/$($vmviews.count)]" -PercentComplete (($i/$vmviews.count)*100)
        $allobj += writeToObj $VMView.name $VMView.Config.Tools.SyncTimeWithHost
    }
}

$allobj | Select Server,SyncTimeWithHost

#$allobj | Select Server,SyncTimeWithHost | ?{$_.SyncTimeWithHost -eq "True"} | Export-Csv badsync.csv -notype