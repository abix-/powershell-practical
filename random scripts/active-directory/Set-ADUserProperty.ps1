[cmdletbinding()]
Param (
    [Parameter(
        Position=0, 
        Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)
    ]$users,
    $searchbase = "OU=Corporate,DC=domain,DC=wh",
    $dc = "my-dc.domain.local",
    [Parameter(Mandatory=$true)][string]$property,
    [Parameter(Mandatory=$true)]$value,
    [switch]$clear
)

if($users.gettype().fullname -ne "Microsoft.ActiveDirectory.Management.ADUser") { Write-Host "The -users parameter must pass a Microsoft.ActiveDirectory.Management.ADUser object from Get-ADUser";Exit}




Import-Module ActiveDirectory
Write-Host "Domain Controller:`t$dc"
Write-Host "Search Base:`t`t$searchbase"
Write-Host "Property:`t`t$property"
Write-Host "Value:`t`t`t$value`n`n"
#Write-Host "Changing"
Set-ADUser -Identity $users -Server $dc -add @{$property=$null} -Verbose




#$users = Get-ADUser -filter * -server $dc -properties $property -searchbase $searchbase | ?{$_.$property}
#$users | sort SamAccountName | Select Name,SamAccountName,$property
#if(($users.gettype()).basetype.name -eq "Array"){$count = $users.count}else{$count = 1}
#Write-Host "$count users found"
# = "msDS-SourceObjectDN",