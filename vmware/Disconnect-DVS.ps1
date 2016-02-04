[cmdletbinding()]
Param (
    [Parameter(Mandatory=$true)]$server
)

function WriteHost($message,$color="White") { Write-Host "$($server): $($message)" -ForegroundColor $color; if($color -eq "Red") { Exit } }
try { WriteHost "Getting VMHost data"; $vmhost = Get-VMHost $server -ErrorAction Stop }
catch { WriteHost "Failed to read VMHost data" -color "Red" }
try { WriteHost "Getting DVS data"; $dvs  = $vmhost | Get-VDSwitch -ErrorAction Stop | sort Name }
catch { WriteHost "Failed to read DVS data" -color "Red" }

foreach($_d in $dvs) {
    #disconnect host from the 
}

#need to record host,dvswitch,uplink