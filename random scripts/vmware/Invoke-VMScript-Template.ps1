[cmdletbinding()]
Param (
    $servers,
    $file
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }
$cred = get-Credential -Message "Local admin on the servers"

foreach($server in $servers) {
    $i++
    Write-Host "Working on $server"
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "Doing stuff" -PercentComplete (($i/$servers.count)*100)
    #Copy-VMGuestFile -Source $file -Destination C:\Windows\Temp -VM $server -LocalToGuest -GuestCredential $cred
    $script = @"
    Insert anything batch here
"@
    Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat #-RunAsync
}