[cmdletbinding()]
Param (
    $csv,
    [switch]$cred
)

function GetCSV($csvfile) {
   if(!(Test-Path $csvfile)) { 
        Write-Verbose "$($csvfile) does not exist. Try again."
   }
   elseif(!($csvfile.substring($csvfile.LastIndexOf(".")+1) -eq "csv")) {
        Write-Verbose "$($csvfile) is not a CSV. Try again."
   }
   else {
	    $csv = @(Import-Csv $csvfile)
        if(!$csv) {
            Write-Verbose "The CSV is empty. Try again."
        }
        else {
            $csvvalid = $true
            return $csv
        }
    }
}

function GetNic($server,$credential,$eaction) {
    if(!$cred) { 
        $nic = get-vm $server | Get-VMGuestNetworkInterface -ea $eaction| where {($_.name -like "*Local Area Connection*") -and ($_.description -like "*Ethernet Adapter*")}
    } else { 
        $nic = get-vm $server | Get-VMGuestNetworkInterface -guestcredential $credential -ea $eaction | where {($_.name -like "*Local Area Connection*") -and ($_.description -like "*Ethernet Adapter*")} 
    }
    return $nic
}

function SetNic($nic,$server,$credential,$eaction,$newdns) {
    if(!$cred) { $nope = Set-VMGuestNetworkInterface -VmGuestNetworkInterface $nic -Ip $server.Ip -Netmask $server.SubnetMask -Gateway $server.DefaultGateway -Dns $newdns -ea $eaction -IPPolicy $server.IPPolicy -DnsPolicy $server.DnsPolicy } 
    else { $nope = Set-VMGuestNetworkInterface -VmGuestNetworkInterface $nic -Ip $server.Ip -Netmask $server.SubnetMask -Gateway $server.DefaultGateway -Dns $newdns -guestcredential $credential -ea $eaction -IPPolicy $server.IPPolicy -DnsPolicy $server.DnsPolicy }
    return $nope
}

$servers = @(import-csv $csv)
#$connection = connect-viserver my-vcenter.domain.local

if($cred) {
    $credential1 = Get-Credential -credential $null
}

$vms = Get-Cluster DEVQC | Get-VM | sort Name
foreach($server in $servers) {
    $vm = $null
    $nic = ""
    $vm = $vms | ?{$_.name -eq $server.Hostname}
    if($vm.PowerState -eq "PoweredOn") {
        Write-Host "$($server.Hostname) - Connecting"
        try { $nic = GetNic $server.Hostname $credential1 "STOP" }
        catch { 
            Write-Host "$($server.Hostname) - Failed to connect with credential1"
            if(!$credential2) { $credential2 = Get-Credential -credential $null }
            Write-Host "$($server.Hostname) - Attempting connection with credential2"
            $nic = GetNic $server.Hostname $credential2 "CONTINUE"
        }
    
        Write-Progress -Status "Working on $($server.hostname)" -Activity "Changing settings"
        if($nic.count -gt 1) {
            Write-Host "There is more than one NIC on $server. No actions performed."
        } elseif($nic) {
            if($($server.'Primary DNS')) {
                [array]$newdns = $($server.'Primary DNS')
                if($($server.'Secondary DNS')) {
                    $newdns += $($server.'Secondary DNS')
                }
                if($($server.'Tertiary DNS')) {
                    $newdns += $($server.'Tertiary DNS')
                }
            } else {
                Write-Host "You must have a primary DNS specified in the input CSV"
            }
            try { $after = SetNic $nic $server $credential1 "STOP" $newdns }
            catch { $after = SetNic $nic $server $credential2 "CONTINUE" $newdns }
            #$after | fl
        }
    } elseif($vm.PowerState -eq "PoweredOff") {
        Write-Host "$($server.Hostname) - VM is powered off"
    }
} 