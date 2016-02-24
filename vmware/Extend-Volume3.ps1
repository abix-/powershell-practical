[cmdletbinding()]
Param (
    $servers
)

#$vms = get-vm | ?{$_.Name -like "JAX-*-SRCH*"} | sort
#$vms = get-vm | ?{$_.Name -like "ORD-*-SRCH*"} | sort
#
#foreach($vm in $vms ) { $vm | get-harddisk | ?{$_.capacitygb -eq 6} | Set-HardDisk -CapacityKB 10485760 -Confirm:$false}

if($servers.EndsWith(".txt")) { $servers = gc $servers }

$script = @"
diskpart.exe /s C:\Windows\system32\extend.txt
"@

$cred = get-Credential

foreach($server in $servers) {
    Write-Host "Working on $server"
    Copy-VMGuestFile -Source extend.txt -Destination C:\Windows\system32 -VM $server -LocalToGuest -GuestCredential $cred
    Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat -RunAsync
}