[cmdletbinding()]
Param (
    [parameter(Mandatory=$true)]
    $csv
)

$report = @()
$servers = import-csv $csv
foreach($server in $servers) {
    $line = "" | Select VMName, VMIp, MAC, WebURL, Protocol, Port, Path
    $line.VMName = $server.Name
    try { $line.VMIp = [System.Net.Dns]::GetHostByName("$($server.Name)").HostName }
    catch { $line.VMIp = $server.Name }
    $line.Protocol = "RDP"
    $line.Port = "3389"
    $line.Path = ""
    $report += $line   
}

$report | Sort Path, VMName | ConvertTo-Csv -NoTypeInformation -Delimiter ";" | Select -Skip 1 | Out-File -FilePath physical.csv -Encoding ascii