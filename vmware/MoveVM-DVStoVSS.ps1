[cmdletbinding()]
Param (
    [Parameter(Mandatory=$true)]$vcenter,
    [Parameter(Mandatory=$true)]$server
)

function WriteHost($message,$color="White") { Write-Host "$($server): $($message)" -ForegroundColor $color; if($color -eq "Red") { Exit } }

try { Connect-VIServer $vcenter -ErrorAction Stop | Out-Null }
catch { WriteHost "Failed to connect to $vcenter" -color Red }

try { WriteHost "Getting VMHost data"; $vmhost = Get-VMHost $server -ErrorAction Stop }
catch { WriteHost "Failed to read VMHost data" -color "Red" }

try { WriteHost "Getting DVS data"; $dvs  = $vmhost | Get-VDSwitch -ErrorAction Stop | sort Name }
catch { WriteHost "Failed to read DVS data" -color "Red" }

foreach($_d in $dvs) {
    $localname = "l-$($_d.name)"
    try { WriteHost "$localname - Getting VSS data"; $vss = Get-VirtualSwitch -Standard -VMHost $server -ErrorAction Stop | ?{$_.Name -eq $localname} }
    catch { WriteHost "$localname - Failed to read VSS data" -color "Red" }

    try { WriteHost "$($_d.name) - Getting port group data"; $dvpgs = Get-VDPortgroup -VDSwitch $_d | sort Name }
    catch { WriteHost "$($_d.name) - Failed to get port group data" -color "Red" }

    foreach($_dvpg in $dvpgs) {
        Write-Host "Working on $($_d.name)\$($_dvpg.name)"
        $vmsNetworkAdapters = Get-VM -RelatedObject $_dvpg | ?{$_.VMHost.Name -eq $server} | Get-NetworkAdapter | ?{$_.networkname -eq $_dvpg.name}
        if($vmsNetworkAdapters) {
            Write-Host "Migrating $($vmsNetworkAdapters.count) VMs"
            $vsp = $vss | Get-VirtualPortGroup -Name $_dvpg.name
            if(!$vsp) { Write-Host "Port group on vSwitch not found. Aborting"; Exit }
            Set-NetworkAdapter -NetworkAdapter $vmsNetworkAdapters -Portgroup $vsp -Confirm:$false
        }
    }
}