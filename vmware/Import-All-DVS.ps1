[cmdletbinding()]
Param (
    [Parameter(Mandatory=$true)]$vcenter
)

function WriteHost($message,$color="White") { Write-Host "$($message)" -ForegroundColor $color; if($color -eq "Red") { Exit } }

try { Connect-VIServer $vcenter -ErrorAction Stop | Out-Null }
catch { WriteHost "Failed to connect to $vcenter" -color Red }

$dvsfiles = Get-ChildItem C:\Scripts\*-DVS.csv
foreach($_d in $dvsfiles) {
    $dcname = $_d.name.substring(0,$_d.Name.LastIndexOf("-"))
    Write-Host "Working on $dcname"

    try { $dc = Get-Datacenter $dcname -ErrorAction Stop }
    catch { WriteHost "No datacenter found named $dcname" -color Red  }

    try { $dvs = Get-ChildItem "C:\Scripts\$dcname-DVS.csv" -ErrorAction Stop | select -ExpandProperty fullname | Import-Csv }
    catch { WriteHost "$dcname - Failed to load DVS file" -color Red }

    try { $pgs = Get-ChildItem "C:\Scripts\$dcname-PortGroups.csv" -ErrorAction Stop | select -ExpandProperty fullname | Import-Csv }
    catch { WriteHost "$dcname - Failed to load port group file" -color Red }

    foreach($_dv in $dvs) {
        $dvsname = $_dv.Name
        try { $mydvs = Get-VDSwitch -Name $dvsname -ErrorAction Stop }
        catch { 
            WriteHost "$dcname - Creating $dvsname DVS with $($_dv.NumUplinkPorts) uplink ports"
            New-VDSwitch -Name $dvsname -Location $dc -LinkDiscoveryProtocol CDP -LinkDiscoveryProtocolOperation Both -NumUplinkPorts $_dv.NumUplinkPorts -Version 5.1.0
            Start-Sleep -Seconds 10
            $mydvs = Get-VDSwitch -Name $dvsname
        }

        $oldgroups = $mydvs | Get-VDPortgroup
        $newgroups = $pgs | ?{$_.VDSwitch -eq $dvsname}

        foreach($_n in $newgroups) {
            if(!($oldgroups.Name.Contains($_n.Name))) {
                Write-Host "$dcname - $dvsname - Adding $($_n.Name) port group"
                New-VDPortgroup -Name $_n.Name -NumPorts $_n.NumPorts -VlanId $_n.Vlan -VDSwitch $mydvs
            } else { Write-Host "$dcname - $dvsname - $($_n.Name) port group already exists" }
        }
        
    }
}