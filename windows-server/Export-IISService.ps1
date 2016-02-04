[cmdletbinding()]
Param (
    $servers,
    $service
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }

$cred = get-Credential -Message "Local admin on the servers"

foreach($server in $servers) {
    $i++
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status " " -PercentComplete (($i/$servers.count)*100)
    Write-Host "Working on $server"
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "Exporting configurations" -PercentComplete (($i/$servers.count)*100)
    $script = @"
    C:\windows\system32\inetsrv\appcmd.exe list apppool "$service" /config /xml > C:\Windows\Temp\$service-pool.xml
    C:\windows\system32\inetsrv\appcmd.exe list site "$service" /config /xml > C:\Windows\Temp\$service-site.xml
"@
    Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat
    Copy-VMGuestFile -Source C:\Windows\Temp\$service-pool.xml -Destination C:\Scripts\Services -VM $server -GuestToLocal -GuestCredential $cred
    Copy-VMGuestFile -Source C:\Windows\Temp\$service-site.xml -Destination C:\Scripts\Services -VM $server -GuestToLocal -GuestCredential $cred
    $cleanup = @"
    DEL C:\Windows\Temp\$service-pool.xml
    DEL C:\Windows\Temp\$service-site.xml
"@
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "Cleaning up" -PercentComplete (($i/$servers.count)*100)
    Invoke-VMScript -VM $server -ScriptText $cleanup -GuestCredential $cred -ScriptType Bat
}