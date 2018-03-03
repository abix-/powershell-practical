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

try { WriteHost "Getting VSS data"; $vss = $vmhost | Get-VirtualSwitch -Standard | sort Name | ?{$_.name -like "l-*"} }
catch { WriteHost "Failed to read VSS data" -color Red }

try { WriteHost "Loading DVS Uplink data"; $dvsuplinks = Import-Csv C:\Scripts\my-vcenter.domain.local-DVS-Uplinks.csv -ErrorAction Stop }
catch { WriteHost "Failed to load DVS uplink data" -color Red }

foreach($_v in $vss) {
    WriteHost "Getting $($_v.Name) data"
    $uplinks = @()
    $newuplink = @()
    $myvmks = @()
    $dvsname = $_v.Name.Substring(2)
    $connect = $false
    $connectuplink = $false
    $dvs = $null

    try { $dvs = Get-VDSwitch $dvsname -ErrorAction Stop }
    catch { WriteHost "Failed to find DVS named $dvsname" -color Red }

    #Connect to DVS
    $currentdvs = $vmhost | Get-VDSwitch -ErrorAction Stop
    if($currentdvs -ne $null) {
        if(!($currentdvs.Name.Contains($dvsname))) { WriteHost "$dvsname - Not connected. Starting to connect."; $connect = $true
        } else { WriteHost "$dvsname - Already connected"; $connect = $false }
    } else { WriteHost "$dvsname - Not connected to any switches. Connecting"; $connect = $true }
    
    try { if($connect) { WriteHost "$dvsname - Connecting..."; Add-VDSwitchVMHost -VDSwitch $dvs -VMHost $vmhost -ErrorAction Stop } }
    catch { WriteHost "$dvsname - Failed to connect" -color Red }

    #get a list of all uplinks on host
    #get a list of old uplinks on local
    #all uplinks - old uplinks = free uplink
    $alluplinks = $dvsuplinks | ?{$_.VMHost -eq $server -and $_.DVSwitch -eq $dvsname}
    $olduplinks = $_v | Get-VMHostNetworkAdapter -Physical | ?{$_.VMHost.Name -eq $server}
    #foreach old uplink, remove it from alluplinks. whats left is new
    $newuplink = $alluplinks
    foreach($_o in $olduplinks) { $newuplink = $newuplink | ?{$_.DeviceName -ne $_o.DeviceName } }
    #Write-Host "Found 4 uplinks for $server. $($olduplinks.count) are connected to $($_v.Name). $($newuplink.count) may be connected to $dvsname."

    #aborting because less than 2 uplinks found in file
    if($alluplinks.count -lt 2) { $alluplinks; WriteHost "$dvsname - Less than 2 uplinks found. Aborting" -color Red }
    if($newuplink.Count -gt 1) { $newuplink; WriteHost "$dvsname - More than 1 uplink found. Aborting" -color Red }

    #get a list of current uplinks on dvs - if exists
    #if there is one, do nothing
    $newdvsuplinks = Get-VMHostNetworkAdapter -DistributedSwitch $dvs -Physical | ?{$_.VMHost.Name -eq $server}
    if($newdvsuplinks) {
        if($newdvsuplinks.Name.Contains($newuplink.DeviceName)) { 
            WriteHost "$dvsname - $($newuplink.DeviceName) already connected. Skipping."; $connectuplink = $false 
        }
    } else { $connectuplink = $true }
    
    if($connectuplink) {
        WriteHost "$dvsname - Adding $($newuplink.DeviceName) as uplink"
        $myuplink = $vmhost | Get-VMHostNetworkAdapter -Physical -Name $newuplink.DeviceName
        $dvs | Add-VDSwitchPhysicalNetworkAdapter -VMHostPhysicalNic $myuplink -Confirm:$false
    }

    #Move VMKernel interfaces to DVS
    $myvmks = $_v | Get-VMHostNetworkAdapter -VMKernel
    if($myvmks.count -gt 0) {
        WriteHost "$dvsname - Found $($myvmks.count) VMKernel interfaces to migrate"
        foreach($_m in $myvmks) {
            $pg = $null
            try { $pg = Get-VDPortgroup -VDSwitch $dvs -Name $_m.PortGroupName -ErrorAction Stop }
            catch { WriteHost "$dvsname - No port group found named $($_m.PortGroupName)" }

            if($pg.Name -eq $_m.PortGroupName) { 
                WriteHost "$dvsname - Starting migration for $($_m.Name)"
                Set-VMHostNetworkAdapter -PortGroup $pg -VirtualNic $_m -Confirm:$false
            }
        }
    } else { WriteHost "$dvsname - No VMKernel interfaces found to migrate" }
    
}