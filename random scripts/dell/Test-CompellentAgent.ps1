[cmdletbinding()]
Param (
    $servers,
    $port = 27355,
    $agentpath = "c$\Program Files (x86)\Compellent Technologies\Enterprise Services Agent",
    $agentexe = "EMServerAgent.exe"
)

function TestPort {
    Param(
        [parameter(ParameterSetName='ComputerName', Position=0)][string]$ComputerName,
        [parameter(ParameterSetName='IP', Position=0)][System.Net.IPAddress]$IPAddress,
        [parameter(Mandatory=$true , Position=1)][int]$Port,
        [parameter(Position=2)][ValidateSet("TCP", "UDP")][string]$Protocol = "TCP"
        )
    $RemoteServer = If ([string]::IsNullOrEmpty($ComputerName)) {$IPAddress} Else {$ComputerName};

    If ($Protocol -eq 'TCP') { $test = New-Object System.Net.Sockets.TcpClient;
    } elseif($Protocol -eq 'UDP') { $test = New-Object System.Net.Sockets.UdpClient; }
    Try {
        Write-Verbose "$($RemoteServer) - Connecting via $($Protocol) to port $($Port)"
        $test.Connect($RemoteServer, $Port)
        Write-Verbose "$($RemoteServer) - Connection successful"
        $status = "Open"
    }
    Catch { Write-Verbose "$($RemoteServer):$($Port) - Connection failed"; $status = "Closed" }
    Finally { $test.Dispose() }
    return $status
}

function GetCompellentAgentVersion($server) {
    try {
        Write-Verbose "$($server) - Getting file information for \\$server\$agentpath\$agentexe"
        $version = (Get-ItemProperty -Path "\\$server\$agentpath\$agentexe" -ErrorAction STOP).VersionInfo.ProductVersion
    }
    catch { $version = $_.Exception.Message }
    return $version
}

Add-PSSnapin Compellent.StorageCenter.PSSnapin
if($servers.EndsWith(".txt")) { $servers = gc $servers | sort }

$all = @()
if($servers) {
    $i = 0
    foreach($server in $servers) { $i++
        Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status " " -PercentComplete (($i/$servers.count)*100)
        Write-Verbose "$($server): Starting tests"
        $status = TestPort $server $port
        $version = GetCompellentAgentVersion $server

        $all += New-Object PSObject -Property @{
            Server = $server
            "Agent Port" = $status
            "Agent Version" = $version
        }
    }
}

$all | select Server,"Agent Port","Agent Version"
