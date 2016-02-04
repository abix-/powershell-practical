[cmdletbinding()]
Param (
    $servers
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }

$script = @"
diskpart.exe /s C:\Windows\system32\mylocaldrives.txt
ping -n 11 127.0.0.1 >nul
shutdown /r /t 0
"@

$cred = get-Credential

foreach($server in $servers) {
    Write-Host "Working on $server"
    Copy-VMGuestFile -Source mylocaldrives.txt -Destination C:\Windows\system32 -VM $server -LocalToGuest -GuestCredential $cred
    Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat -RunAsync
}