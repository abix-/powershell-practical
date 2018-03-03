[cmdletbinding()]
Param (
    $servers
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }

$cred = get-Credential -Message "Local admin on the servers"

foreach($server in $servers) {
    $i++
    Write-Host "Working on $server"
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "Configuring IIS" -PercentComplete (($i/$servers.count)*100)
    $script = @"
    C:\Windows\system32\inetsrv\appcmd.exe set config /section:isapiFilters /-[name='ISAPI_Rewrite_32']
    C:\Windows\system32\inetsrv\appcmd.exe set config /section:isapiFilters /-[name='ISAPI_Rewrite_x64']
"@
    Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat #-RunAsync
}