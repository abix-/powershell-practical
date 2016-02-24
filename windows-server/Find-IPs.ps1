[cmdletbinding()]
Param (
    $file
)

$log = gc $file
$ips = [regex]::matches($log,"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b") | sort value | select value -unique

foreach($ip in $ips) {
    ([system.dns]::gethostbyaddress("$ip.value")).Hostname
}