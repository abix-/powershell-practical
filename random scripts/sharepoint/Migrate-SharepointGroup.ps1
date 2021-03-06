[cmdletbinding()]
Param (
    [parameter(Mandatory=$true)]
    $adgroup,
    [parameter(Mandatory=$true)]
    $url,
    [parameter(Mandatory=$true)]
    $group
)

$session = new-pssession -cn wh-dc01

try { 
    icm { import-module activedirectory }  -session $session
    $members = icm -session $session -script { param($adgroup) get-adgroupmember $adgroup -ea "STOP" } -args $adgroup
}
catch {
    Write-Host $error[0] -foregroundcolor "red"
    Exit
}

remove-pssession wh-dc01

if($members) {
    foreach($member in $members) {
        Write-Host "Adding $($member.SamAccountName) to $group"
        & stsadm.exe -o gl-adduser2 -url $url -userlogin $($member.SamAccountName) -group $group  
    }
} else {
    Write-Host "There are no members in $adgroup."
}

remove-pssession -cn wh-dc01