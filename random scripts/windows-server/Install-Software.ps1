[cmdletbinding()]
Param (
    $server,
    $stack,
    $file
    #$csv = "tcs_servers.csv",
)

if($csv) {
    $config = Import-Csv $csv
    #$servers = $config | ?{$_.role -eq "WEB" -and $_.stack -eq $stack}
    if($range) { $servers = $servers | ?{$_.name -like "*-WEB$range" } }
    if($servers -eq $null) { Write-Host "Error in reading config. Aborting."; Exit }
} else {
    if($server.EndsWith(".txt")) { $servers = gc $server }
}

$cred = get-Credential -Message "Local admin on the servers"

foreach($server in $servers) {
    $i++
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status " " -PercentComplete (($i/$servers.count)*100)
    #Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "Copying $file" -PercentComplete (($i/$servers.count)*100)
    #Write-Host "Working on $server"
    #Copy-VMGuestFile -Source $file -Destination C:\Windows\Temp -VM $server -LocalToGuest -GuestCredential $cred
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "Installing $file" -PercentComplete (($i/$servers.count)*100)
    $script = @"
    \\ord-dc001.domain.local\LogRhythm$\install64.bat
"@
    Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat #-RunAsync
}