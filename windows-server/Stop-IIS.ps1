[cmdletbinding()]
Param (
    [alias("s")]
    [Parameter(Mandatory=$true)]
    $servers = ""
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }

foreach($server in $servers) {
    if((Test-Connection -ComputerName $server -count 1 -ErrorAction 0)) {
        Write-Host "$server - Stopping W3SVC"
        sc.exe \\$server start "W3SVC"
    } else { Write-Host "$server - Offline" }
}