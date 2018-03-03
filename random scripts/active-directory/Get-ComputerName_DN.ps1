[cmdletbinding()]
Param (
    $server
)

function writeToObj($ip,$dn="N/A",$cardholder="N/A",$cn="N/A") {
    $obj= New-Object PSObject -Property @{
        IP = $ip
        ComputerName = $cn
        DN = $dn
        Cardholder = $cardholder
    }
    return $obj
}

function getComputerName($ip){
    Write-Host "Working on $ip"
    try { $name = gwmi win32_computersystem -computername $ip | select -expand Name }
    catch { $name = "Error" }
    return $name
}

$computers = Get-ADComputer -filter * -searchbase "DC=FF,DC=P10" -server "domain.local"

$allobj = @()
foreach($srv in $server) {
    $name = getComputerName $srv
    $dn = $computers | where{$_.Name -eq $name} | select -expand DistinguishedName
    if(!$dn) { $dn = "Not found"  }
    if($dn.Contains("OU=Cardholder")) { $iscardholder = "Yes" }
    else { $iscardholder = "No" }
    $obj = writeToObj $srv $dn $iscardholder $name
    $allobj += $obj
}

$allobj | select IP,ComputerName,DN,Cardholder
$allobj | select IP,ComputerName,DN,Cardholder | export-csv computername_dn.csv -notype