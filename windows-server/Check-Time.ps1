[cmdletbinding()]
Param (
    $csv = "tcs_servers.csv",
    [Parameter(Mandatory=$true)]
    $stack,
    $range
)

$config = Import-Csv $csv
$servers = $config | ?{$_.stack -eq $stack}
if($range) { $servers = $servers | ?{$_.name -like "*-$range" } }
if($servers -eq $null) { Write-Host "Error in reading config. Aborting."; Exit }

$allobj = @()
foreach($server in $servers) {
    $i++
    Write-Progress -Activity "Reading time on $($server.name)" -Status "[$i/$($servers.count)]" -PercentComplete (($i/$servers.count)*100)
    try { $dt = gwmi -class win32_operatingsystem -ComputerName $server.fqdn -ErrorAction STOP }
    catch { $dt = "Error" }
    if($dt -ne "Error") { $dt_str = $dt.converttodatetime($dt.localdatetime) }
    else { $dt_str = "Error" }
    $obj= New-Object PSObject -Property @{
        Server = $server.name
        Time = $dt_str
    }
    $allobj += $obj
}

$allobj | sort Server | Select Server, Time