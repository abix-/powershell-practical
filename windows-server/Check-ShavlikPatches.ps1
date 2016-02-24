[cmdletbinding()]
Param (
    [alias("s")]
    [Parameter(Mandatory=$true)]
    $servers = ""
)

function writeToObj($server,$status="N/A",$patches="N/A") {
    $obj= New-Object PSObject -Property @{
            Server = $server
            Status = $status
            Patches = $patches
    }
    return $obj
}

if($servers.EndsWith(".txt")) { $servers = gc $servers }
$genericpath = "\\SERVERNAME\c$\Windows\ProPatches\Patches"
$allobj = @()

foreach($server in $servers) {
    $files = $null
    if((Test-Connection -ComputerName $server -count 1 -ErrorAction 0)) {
        $unc = $genericpath.Replace("SERVERNAME",$server)
        $files = Get-ChildItem $unc
        $allobj += writeToObj $server "Online" $files.count
    } else { $allobj += writeToObj $server "Offline" } 
}
$allobj | Select Server,Status,Patches