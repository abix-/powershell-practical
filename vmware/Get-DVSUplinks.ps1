[cmdletbinding()]
Param (
    [Parameter(Mandatory=$true)]$vcenter
)

function WriteHost($message,$color="White") { Write-Host "$($server): $($message)" -ForegroundColor $color; if($color -eq "Red") { Exit } }

try { Connect-VIServer $vcenter -ErrorAction Stop | Out-Null }
catch { WriteHost "Failed to connect to $vcenter" -color Red }


Write-Host "Getting DVS data"
$dvs = Get-VDSwitch | sort Name
$results = @()
foreach($_d in $dvs) {
    Write-Host "Working on $($_d.Name)"
    $uplinks = $_d | Get-VMHostNetworkAdapter -Physical | Select VMHost,DeviceName,Mac
    Write-Host "Found $($uplinks.count) uplinks"
    foreach($_u in $uplinks) {
        $results += New-Object PSObject -Property @{
            VMHost = $_u.VMHost
            DVSwitch = $_d.Name
            DeviceName = $_u.DeviceName
            MAC = $_u.Mac
        }
    }
}

Write-Host "Exporting $($results.count) results to file"
$results | sort VMHost | Select VMHost,DVSwitch,DeviceName,MAC | Export-Csv $vcenter-DVS-Uplinks.csv -NoTypeInformation