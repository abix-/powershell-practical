[cmdletbinding()]
Param (
    $server
)

function GetVersion($server) {
    if(!(Test-Connection -ComputerName $server -count 1 -ErrorAction 0)) { return "Failed to ping" }
    if(!(Test-Path "\\$server\c$\program files\internet explorer\iexplore.exe")) { return "iexplore.exe does not exist" }
    return (Get-ItemProperty -Path "\\$server\c$\program files\internet explorer\iexplore.exe").VersionInfo.ProductVersion
}

function WriteToObj($server,$version="N/A") {
    $obj = New-Object PSObject -Property @{
        Server = $server
        "IE Version" = $version
    }
    return $obj
}

$allobj = @()
foreach($s in $server) {
    $i++
    Write-Progress -Activity "Working on $s" -Status "[$i/$($server.count)]" -PercentComplete (($i/$server.count)*100)
    $version = GetVersion $s
    $obj = WriteToObj $s.toupper() $version
    $allobj += $obj
}
$allobj | select Server,"IE Version" | sort Server