[cmdletbinding()]
Param (
    [alias("s")]
    [Parameter(Mandatory=$true)]
    $servers = ""
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }

$allobj = @()
foreach($server in $servers) {
    try { $name = gwmi win32_computersystem -computername $server | select -expand Name }
    catch { $name = "Error" }
    $allobj += New-Object PSObject -Property @{
        Cluster = $server
        "Active Node" = $name
    }
}
$allobj | sort Cluster | select Cluster,"Active Node"
