[cmdletbinding()]
Param (
    $searchbase = "OU=Corporate,DC=domain,DC=wh",
    $dc = "my-dc.domain.local",
    $property = "msDS-SourceObjectDN"
)

Import-Module ActiveDirectory
Write-Host "Domain Controller:`t$dc"
Write-Host "Search Base:`t`t$searchbase"
Write-Host "Property:`t`t$property"
$users = Get-ADUser -filter * -server $dc -properties $property -searchbase $searchbase | ?{$_.$property}
$users | sort SamAccountName | Select Name,SamAccountName,$property
if($users) { if(($users.gettype()).basetype.name -eq "Array"){$count = $users.count}else{$count = 1}} else { $count = 0 } 
Write-Host "$count users found"