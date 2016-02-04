[cmdletbinding()]
Param (
    [Parameter(Position=0,Mandatory=$true)]
    $stack,
    $seconds = 120,
    $csv = "tcs_servers.csv",
    $range
)

$minutes =  "{0:N2}" -f ($seconds/60)
$config = Import-Csv $csv
$servers = $config | ?{$_.role -eq "WEB" -and $_.stack -eq $stack}
if($range) { $servers = $servers | ?{$_.name -like "*-WEB$range" } }
if($servers.count -le 1) { Write-Host "Error in reading config. Aborting."; Exit }

$i = 0
foreach($server in $servers) {
    $i++
    Write-Host "";Write-Host "Resetting IIS on $($server.name)"
    iisreset.exe $($server.name)
    
    if($i % 5 -eq 0 -and $i -lt $servers.count -and $seconds -ne 0) { 
        Write-Host "Waiting for $minutes minutes"
        Start-Sleep -s $seconds
   }
}