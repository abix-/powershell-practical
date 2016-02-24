[cmdletbinding()]
Param (
    $servers
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }

$cred = get-Credential -Message "Local admin on the servers"
$times = @{"001" = "06:00:00";"002" = "06:00:00";"003" = "06:00:00";"004" = "06:00:00";"005" = "06:05:00";"006" = "06:05:00";"007" = "06:05:00";"008" = "06:05:00";"009" = "06:10:00";"010" = "06:10:00";"011" = "06:10:00";"012" = "06:10:00";"013" = "06:15:00";"014" = "06:15:00";"015" = "06:15:00";"016" = "06:15:00";"017" = "06:20:00";"018" = "06:20:00";"019" = "06:20:00";"020" = "06:20:00";"021" = "06:25:00";"022" = "06:25:00";"023" = "06:25:00";"024" = "06:25:00";"025" = "06:30:00";"026" = "06:30:00";"027" = "06:30:00";"028" = "06:30:00";"029" = "06:35:00";"030" = "06:35:00";"031" = "06:35:00";"032" = "06:35:00";"033" = "06:40:00";"034" = "06:40:00";"035" = "06:40:00";"036" = "06:40:00";"037" = "06:45:00";"038" = "06:45:00";"039" = "06:45:00";"040" = "06:45:00";}



foreach($server in $servers) {
    $i++
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status "Fixing stuff" -PercentComplete (($i/$servers.count)*100)
    Write-Host "Working on $server"
    $webservernumber = $server.substring($server.LastIndexOf("-")+4)
    if($webservernumber) {
        $script = @"
        C:\windows\system32\inetsrv\appcmd.exe set apppool /apppool.name: POOL /recycling.periodicRestart.schedule.[value='06:00:00'].value:$($times[$webservernumber])
        C:\windows\system32\inetsrv\appcmd.exe set config /section:staticContent /+"[fileExtension='.json',mimeType='application/json']"
        C:\windows\system32\inetsrv\appcmd.exe delete apppool "ASP.NET v4.0"
        C:\windows\system32\inetsrv\appcmd.exe delete apppool "ASP.NET v4.0 Classic"
        C:\windows\system32\inetsrv\appcmd.exe delete apppool "Classic .NET AppPool"
"@
        Invoke-VMScript -VM $server -ScriptText $script -GuestCredential $cred -ScriptType Bat
    } else {
        Write-Host "$($server): Server name does not appear valid"
    }
}