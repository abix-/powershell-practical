[cmdletbinding()]
Param (
    $servers,
    $site
)

if(!$servers) {
    $servers = Import-Csv $csv
    if($stack) { $servers = $servers | ?{$_.stack -eq "$stack"} }
    if($role) { $servers = $servers | ?{$_.role -eq "$role"} }
    if($regex) { $servers = $servers | ?{$_.name -like "$regex"} }
    if($servers -eq $null) { Write-Host "Error in reading config. Aborting."; Exit }
    $servers = $servers | select -ExpandProperty FQDN
} else {
    if($servers.EndsWith(".txt")) { $servers = gc $servers }
}

$cred = get-Credential -Message "Local admin on the servers"

foreach($server in $servers) {
    $i++
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status " " -PercentComplete (($i/$servers.count)*100)
    #Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "Copying $file" -PercentComplete (($i/$servers.count)*100)
    Write-Host "Working on $server"
    #Copy-VMGuestFile -Source $file -Destination C:\Windows\Temp -VM $server -LocalToGuest -GuestCredential $cred
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "Starting installation" -PercentComplete (($i/$servers.count)*100)
    $script = @"
    \\dc.domain.local\LogRhythm$\update-compellentagent.bat
"@
    Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat -RunAsync
}