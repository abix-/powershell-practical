[cmdletbinding()]
Param (
    [Parameter(Mandatory=$true)]$domain
)

Import-Module ActiveDirectory
$results = @()
$zoneresults = @()
$outputFile = "$((Get-Location).Path)\Check-DNSZones_$($domain).csv"
$outputZoneFile = "$((Get-Location).Path)\Check-DNSZones_$($domain)_secondary.csv"
$dcs = Get-ADDomainController -filter * -Server $domain | Select-Object -ExpandProperty HostName | Sort-Object
foreach($_d in $dcs) {
    $zones = gwmi -Class microsoftdns_zone -namespace root\microsoftdns -ComputerName $_d
    $pri_zones = @($zones | ?{$_.ZoneType -eq 1})
    $sec_zones = @($zones | ?{$_.ZoneType -eq 2})
    Write-Host "$_d - Found $($pri_zones.count) primary zones and $($sec_zones.count) secondary zones"
    $results += New-Object PSObject -Property @{
            DomainController = $_d
            PrimaryZones = $pri_zones.count
            SecondaryZones = $sec_zones.count
    }

    foreach($_s in $sec_zones) {
        $zoneresults += New-Object PSObject -Property @{
            DomainController = $_d
            SecondaryZone = $_s.Name
            MasterServer0 = $_s.MasterServers[0]
            MasterServer1 = $_s.MasterServers[1]
            MasterServer2 = $_s.MasterServers[2]
            MasterServer3 = $_s.MasterServers[3]
            LastSuccessfulXfr = $_s.LastSuccessfulXfr
            LastSuccessfulSoaCheck = $_s.LastSuccessfulSoaCheck
        }
    }
}

$results | select DomainController, PrimaryZones, SecondaryZones
$results | select DomainController, PrimaryZones, SecondaryZones | Export-Csv $outputFile -NoTypeInformation
$zoneresults | select DomainController,SecondaryZone,MasterServer0,MasterServer1,MasterServer2,MasterServer3,LastSuccessfulXfr,LastSuccessfulSoaCheck | Export-Csv $outputZoneFile -NoTypeInformation