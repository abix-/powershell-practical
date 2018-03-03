[cmdletbinding()]
param (
	[parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
	[string[]] $servers = $env:computername,
    $scriptPath = (Get-Location).Path
)

function AddtoObj($cn="N/A",$stat="N/A",$index="N/A",$ip="N/A",$pdns="N/A",$sdns="N/A",$tdns="N/A",$dhcp="N/A",$name="N/A") {
    $obj = New-Object -Type PSObject
    $obj | Add-Member -MemberType NoteProperty -Name ComputerName -Value $cn
    $obj | Add-Member -MemberType NoteProperty -Name Status -Value $stat
    $obj | Add-Member -MemberType NoteProperty -Name "NIC Index" -Value $index
    $obj | Add-Member -MemberType NoteProperty -Name "IP Address" -Value $ip
	$obj | Add-Member -MemberType NoteProperty -Name "Primary DNS" -Value $pdns
	$obj | Add-Member -MemberType NoteProperty -Name "Secondary DNS" -Value $sdns
    $obj | Add-Member -MemberType NoteProperty -Name "Tertiary DNS" -Value $tdns
	$obj | Add-Member -MemberType NoteProperty -Name IsDHCPEnabled -Value $dhcp
	$obj | Add-Member -MemberType NoteProperty -Name NetworkName -Value $name
    return $obj
}


$results = @()
if($servers.EndsWith(".txt")) {
    $output = $servers  -replace "\\","_" -replace "\.txt","" -replace "\.",""
    $outputFile = "$scriptPath\Get-DNS$($output).csv"
    $servers = gc $servers
} else { $outputFile = "$scriptPath\$servers.csv" }
foreach($_s in $servers) {
    $i++
    Write-Progress -Status "[$i/$($servers.count)] $($_s) " -Activity "Gathering Data" -PercentComplete (($i/$servers.count)*100)
    $result = @()
    $networks = $null
	if(Test-Connection -ComputerName $_s -Count 3 -ea 0) {
		try {
			$Networks = Get-WmiObject -Class Win32_NetworkAdapterConfiguration `
						-Filter IPEnabled=TRUE `
						-ComputerName $_s `
						-ErrorAction Stop
		} catch {
			Write-Host "Failed to Query $_s. Error details: $_"
            $result = AddtoObj $_s.ToUpper() "Failed WMI Query"
            $results += $result
            continue
		}
		foreach($Network in $Networks) {
			$DNSServers = $Network.DNSServerSearchOrder
			$NetworkName = $Network.Description
			If(!$DNSServers) {
				$PrimaryDNSServer = $SecondaryDNSServer = $TertiaryDNSServer = "N/A"
			} else {
                if($Network.DNSServerSearchOrder[0]) { $PrimaryDNSServer = $DNSServers[0] } else { $PrimaryDNSServer = "N/A" }
                if($Network.DNSServerSearchOrder[1]) { $SecondaryDNSServer = $DNSServers[1] } else { $SecondaryDNSServer = "N/A" }
                if($Network.DNSServerSearchOrder[2]) { $TertiaryDNSServer = $DNSServers[2] } else { $TertiaryDNSServer = "N/A" }
            }
			If($network.DHCPEnabled) { $IsDHCPEnabled = $true } else { $IsDHCPEnabled = $false }
            $results += AddtoObj $_s.ToUpper() "Online" $network.Index $network.IPAddress[0] $PrimaryDNSServer $SecondaryDNSServer $TertiaryDNSServer $IsDHCPEnabled $NetworkName
		}
	} else {
		Write-Host "$_s not reachable"
        $results += AddtoObj $_s.ToUpper() "Ping Failed"
	}
}
$results
$results | Export-Csv $outputFile -NoTypeInformation
Write-Host "Results have been written to '$outputFile'"