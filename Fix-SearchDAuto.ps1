[cmdletbinding()]
Param (
    [alias("s")]
    [Parameter(Mandatory=$true)]
    $servers = ""
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }

foreach($server in $servers) {
    if((Test-Connection -ComputerName $server -count 1 -ErrorAction 0)) {
        Write-Host "$server - Changing settings"
        sc.exe \\$server config "MyServiceSearch" start= delayed-auto reset= 1800 actions= restart/5000
    } else { Write-Host "$server - Offline" }
}