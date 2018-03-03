[cmdletbinding()]
Param (
    $servers
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }

$allobj = @()
foreach($server in $servers) {
    $i++
    [string]$folderexists = "Failed to query"
    Write-Progress -Activity "Working on $server [$i/$($servers.count)]" -Status " " -PercentComplete (($i/$servers.count)*100)
    $folderexists = Test-Path "\\$server\c$\Program Files\System Center Operations Manager"
    $obj= New-Object PSObject -Property @{
            Server = $server
            Installed = $folderexists
    }
    $allobj += $obj
}

$allobj | select Server,Installed