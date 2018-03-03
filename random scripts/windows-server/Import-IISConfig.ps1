[cmdletbinding()]
Param (
    [Parameter(Mandatory=$true)]$servers,
    [Parameter(Mandatory=$true)][string]$site,
    [Parameter(Mandatory=$true)][string]$pool,
    [Parameter(ParameterSetName="Clean")][switch]$clean,
    [Parameter(ParameterSetName="Clean")][string]$service
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }
if($PSCmdlet.ParameterSetName -eq "Clean") { if([string]::IsNullOrEmpty($service)) { Write-Host "You are attempting to use -clean without -service. Aborting."; Exit } }

$cred = get-Credential -Message "Local admin on the servers"

foreach($server in $servers) {
    $i++
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status " " -PercentComplete (($i/$servers.count)*100)
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "Copying configuration files" -PercentComplete (($i/$servers.count)*100)
    Write-Host "Working on $server"
    Copy-VMGuestFile -Source $pool -Destination C:\Windows\Temp -VM $server -LocalToGuest -GuestCredential $cred
    Copy-VMGuestFile -Source $site -Destination C:\Windows\Temp -VM $server -LocalToGuest -GuestCredential $cred
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "Configuring IIS" -PercentComplete (($i/$servers.count)*100)
    $script = @"
    C:\Windows\system32\inetsrv\appcmd.exe add apppool /in < C:\Windows\Temp\$pool
    C:\Windows\system32\inetsrv\appcmd.exe add site /in < C:\Windows\Temp\$site
    DEL C:\Windows\Temp\$pool
    DEL C:\Windows\Temp\$site
"@
    if($PSCmdlet.ParameterSetName -eq "Clean") {
        $cleanscript = @"
        C:\windows\system32\inetsrv\appcmd.exe delete apppool "$service"
        C:\Windows\system32\inetsrv\appcmd.exe delete site "$service"
"@
    $script = $cleanscript + "`n" + $script
    }
    Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat #-RunAsync
}