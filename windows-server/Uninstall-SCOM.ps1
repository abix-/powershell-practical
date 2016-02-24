[cmdletbinding()]
Param (
    $servers
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }

$cred = get-Credential -Message "Local admin on the servers"

foreach($server in $servers) {
    $i++
    Write-Host "Working on $server"
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "REMOVING SCOM!!!!" -PercentComplete (($i/$servers.count)*100)
    $script = @"
    MsiExec.exe /I{8B21425D-02F3-4B80-88CE-8F79B320D330}
"@
    Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat #-RunAsync
}