[cmdletbinding()]
Param (
    $server,
    $zone,
    $master,
    $secondary
)

foreach($srv in $server) {
    Write-Host "$($srv): Adding $zone..."
    dnscmd $srv /zoneadd $zone /secondary $master $secondary
}