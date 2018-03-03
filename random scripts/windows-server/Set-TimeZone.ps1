[cmdletbinding()]
Param (
    $servers
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }
$cred = get-Credential -Message "Local admin on the servers"

foreach($server in $servers) {
    $script = 'C:\Windows\system32\tzutil.exe /s "Eastern Standard Time"'
    Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat -RunAsync
}