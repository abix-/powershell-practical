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
    $pnic = $null
    $vmk = $null

    try { WriteHost "Getting port group data for $($_d.name)"; $dvpgs = Get-VDPortgroup -VDSwitch $_d -ErrorAction Stop | ?{$_.Name -like "*vmMGMT*" -or $_.Name -like "*vMotion*" -or $_.Name -like "*iSCSI0*"} | sort Name }
    catch { WriteHost "Failed to get port gorup data for $($_d.name)" -color "Red" }

    try { 
        WriteHost "Getting VSS, PNIC, and VMK data"
        $vss = Get-VirtualSwitch -Standard -VMHost $server -ErrorAction Stop | ?{$_.Name -eq $localname} 
        $pnic = Get-VMHostNetworkAdapter -DistributedSwitch $_d -Physical -ErrorAction Stop | ?{$_.VMHost.Name -eq $server} | sort Name
        $vmk = Get-VMHostNetworkAdapter -DistributedSwitch $_d -VMKernel -ErrorAction Stop | ?{$_.VMHost.Name -eq $server} | sort Name
    }
    catch { WriteHost "Failed to read VSS data" -color "Red" }
    
    if($pnic.count -ge 2) { $pnic_array = @($pnic | select -First ($pnic.count - 1)) }else { WriteHost "$localname - Only $($pnic.count) physicals NICs found. Skipping." -color "Yellow"; Continue }
    #if($pnic.count/2 -ge 1 -and $pnic.count -gt 0) { $pnic_array = @($pnic | select -First 1) } else { WriteHost "$localname - Only $($pnic.count) physicals NICs found. Skipping." -color "Yellow"; Continue }
    
    $pg_array = @()
    foreach($_v in $vmk) {
        try {
            $vlan = $null
            $vlan = ($dvpgs | ?{$_.Name -eq $_v.PortGroupName}).vlanconfiguration.vlanid
            WriteHost "$localname - Creating port group $($_v.PortGroupName) on VLAN $vlan";
            if($vlan) { $newpg = New-VirtualPortGroup -VirtualSwitch $vss -Name $_v.PortGroupName -VLanId $vlan -ErrorAction Stop }
            else { $newpg = New-VirtualPortGroup -VirtualSwitch $vss -Name $_v.PortGroupName -ErrorAction Stop }
            if($dvs.name -eq "dvSwitch-FAKW_Trunk" -and ($newpg.Name -like "dvPG-vmMGMT*" -or $newpg.Name -like "dvPG-vMotion*")) {
                WriteHost "Setting policy to IP hash"
                Get-NicTeamingPolicy -VirtualPortGroup $newpg | Set-NicTeamingPolicy -LoadBalancingPolicy LoadBalanceIP 
            }
            #Write-Host $pg_array.GetType().ToString()
            $pg_array += $newpg
        }
        catch { Write-Host $_.Exception ;WriteHost "$localname - Failed to create port group $($_v.PortGroupName)" -color "Red" }
    }

    if($vmk -and $pnic) {
        WriteHost "$localname - Moving PNIC and $($vmk.count) VMKernel interfaces"
        Add-VirtualSwitchPhysicalNetworkAdapter -VirtualSwitch $vss -VMHostVirtualNic $vmk -VirtualNicPortgroup $pg_array -VMHostPhysicalNic $pnic_array -Confirm:$false
    } elseif($pnic) {
        WriteHost "$localname - Moving PNIC"
        Add-VirtualSwitchPhysicalNetworkAdapter -VirtualSwitch $vss -VMHostPhysicalNic $pnic_array -Confirm:$false
    }
}