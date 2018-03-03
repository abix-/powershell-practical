[cmdletbinding()]
Param (
    $server
)

function writeToObj($computername,$dn="N/A",$cardholder="N/A") {
    $obj= New-Object PSObject -Property @{
        ComputerName = $computername
        DN = $dn
        Cardholder = $cardholder
    }
    return $obj
}

$computers = Get-ADComputer -filter * -searchbase "DC=LOCAL,DC=DOMAIN" -server "domain.local"

$allobj = @()
foreach($srv in $server) {
    $dn = $computers | where{$_.Name -eq $srv} | select -expand DistinguishedName
    if(!$dn) { $dn = "Not found"  }
    if($dn.Contains("OU=Cardholder")) { $iscardholder = "Yes" }
    else { $iscardholder = "No" }
    $obj = writeToObj $srv $dn $iscardholder
    $allobj += $obj
}

$allobj