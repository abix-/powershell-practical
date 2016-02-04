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
    WriteHost "Creating $localname"
    try {
        $vss = New-VirtualSwitch -VMHost $server -Name $localname -ErrorAction Stop
        $dvpgs = Get-VDPortgroup -VDSwitch $_d -ErrorAction Stop | ?{$_.Name -notlike "*Uplinks*" -and $_.Name -notlike "*vmMGMT*" -and $_.Name -notlike "*vMotion*" -and $_.Name -notlike "*iSCSI0*" -and $_.Name -notlike "*Pernix*"} | sort Name
        foreach($_dvpg in $dvpgs) {
            $vlan = $null
            $vlan = $_dvpg.vlanconfiguration.vlanid
            $pgname = $_dvpg.Name
            WriteHost "$($_d.name) - Creating $pgname port group"
            if($vlan) { New-VirtualPortGroup -VirtualSwitch $vss -Name $pgname -VLanId $vlan -ErrorAction Stop | Out-Null }
            else { New-VirtualPortGroup -VirtualSwitch $vss -Name $pgname -ErrorAction Stop | Out-Null}
        }
    }
    catch { WriteHost $_.Exception.Message -color "Red" }
}