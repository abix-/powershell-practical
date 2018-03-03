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

try { WriteHost "Getting VSS data"; $vss = Get-VirtualSwitch -Standard -VMHost $server -ErrorAction Stop | ?{$_.Name -like "l-*"} | sort Name }
catch { WriteHost "Failed to read VSS data" -color "Red" }

foreach($_v in $vss) {
    $dvsname = $_v.Name.Substring(2)
    $vssuplink = @()

    try { WriteHost "$dvsname - Getting DVS data"; $dvs  = $vmhost | Get-VDSwitch $dvsname -ErrorAction Stop | sort Name }
    catch { WriteHost "$dvsname - Failed to read DVS data" -color "Red" }

    try { WriteHost "$($_v.Name) - Getting port group data"; $pgs = Get-VirtualPortGroup -VirtualSwitch $_v | sort Name }
    catch { WriteHost "$($_v.Name) - Failed to get port group data" -color "Red" }

    foreach($_pg in $pgs) {
        WriteHost "Working on $($_v.Name)\$($_pg.Name)"
        $vmsNetworkAdapters = Get-VM -RelatedObject $_pg | ?{$_.VMHost.Name -eq $server} | Get-NetworkAdapter | ?{$_.networkname -eq $_pg.name}
        if($vmsNetworkAdapters) {
            Write-Host "Migrating $($vmsNetworkAdapters.count) VMs"
            $dvsp = $dvs | Get-VirtualPortGroup -Name $_pg.name
            if(!$dvsp) { Write-Host "Port group on vSwitch not found. Aborting"; Exit }
            Set-NetworkAdapter -NetworkAdapter $vmsNetworkAdapters -Portgroup $dvsp -Confirm:$false
        } else { WriteHost "No VMs found to migrate" }
    }

    #
    #check to ensure all VMs off local switches
    Write-Host ""
    Read-Host "All VMs have been moved to the DVS. Proceed with uplink migration and local switch deletion?"
    $vssuplink = $_v | Get-VMHostNetworkAdapter -Physical | ?{$_.VMHost.Name -eq $server}
    if($vssuplink -and $vssuplink.count -gt 1) {
        foreach($_uplink in $vssuplink) {
            WriteHost "$dvsname - Adding $($_uplink.DeviceName) to $dvsname"
            $dvs | Add-VDSwitchPhysicalNetworkAdapter -VMHostPhysicalNic $_uplink -Confirm:$false 
        }
    }
    else { WriteHost "No VSS uplink found to migrate" }

    WriteHost "Deleting $($_v.Name) vSwitch"
    Remove-VirtualSwitch -VirtualSwitch $_v -Confirm:$false
}