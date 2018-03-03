[cmdletbinding()]
Param (
    [alias("s")]
    [Parameter(Mandatory=$true)]
    $dc,
    [Parameter(Mandatory=$true)]
    $domain
)

Import-Module activedirectory

function GetStaticARecords($server, $domain) {
    return Get-WmiObject -Class MicrosoftDNS_AType -NameSpace Root\MicrosoftDNS  -ComputerName $server -Filter "DomainName = '$domain'" | ?{$_.timestamp -eq "0"}
}

function TestIP($ipaddress) {
    if((Test-Connection -ComputerName $ipaddress -count 1 -ErrorAction 0)) { $online = "Online" } 
    else { $online = "Offline" }
    return $online
}

function GetWin32ComputerName($ipaddress) {
    try { 
        $info = get-wmiobject win32_computersystem -computername $ipaddress -ea "STOP" 
        $name = $info.Name
        $domain = $info.Domain
    }
    catch {
        $name = "WMI QUERY FAILED"
        $domain = "WMI QUERY FAILED"
    }
    return $name,$domain
}

$visionapp = import-csv visionapp.csv -delimiter ";"
$adcomputers = get-adcomputer -server $dc -filter *
$staticarecords = GetStaticARecords $dc $domain #| where{$_.ownername -like "BETA*"}
$allobj = @()
$i = 1
foreach($staticarecord in $staticarecords) {
    if($staticarecords.count -gt 1) { Write-Progress -Activity "Working on $($staticarecord.Ownername)" -Status "[$i/$($staticarecords.count)]" -PercentComplete (($i/$staticarecords.count)*100) }
    $i++
    $online = TestIP $staticarecord.ipaddress
    if($online -eq "Online") { $wmiinfo = GetWin32Computername $staticarecord.ipaddress }
    else { 
        $wmiinfo = @("N/A","N/A") 
    }

    $dnscomputername = $staticarecord.Ownername.ToUpper()
    $dnscomputername = $dnscomputername.substring(0,$dnscomputername.IndexOf("."))
    $dnsdomain = $domain.ToUpper()
    $dnsip = $staticarecord.ipaddress
    $wmicomputername = $wmiinfo[0].ToUpper()
    $wmidomain = $wmiinfo[1].ToUpper()
    $dnswmicomputernamematches = "False"
    $dnswmidomainmatches = "False"
    $dnsinva = "False"
    $wmiinva = "False"
    $dnsinad = "False"
    $wmiinad = "False"
    
    if($dnscomputername -eq $wmicomputername) { $dnswmicomputernamematches = "True" }
    elseif(($wmicomputername -eq "WMI QUERY FAILED") -or ($wmicomputername -eq "N/A")) { $dnswmicomputernamematches = "N/A" }
    if($dnsdomain -eq $wmidomain) { $dnswmidomainmatches = "True" }
    elseif(($wmidomain -eq "WMI QUERY FAILED") -or ($wmidomain -eq "N/A")) { $dnswmidomainmatches = "N/A" }
    if($visionapp.Name.Contains($dnscomputername)) { $dnsinva = "True" }
    if($visionapp.Name.Contains($wmicomputername)) { $wmiinva = "True" }
    elseif(($wmicomputername -eq "WMI QUERY FAILED") -or ($wmicomputername -eq "N/A")) { $wmiinva = "N/A" }
    if($adcomputers.Name.ToUpper().Contains($dnscomputername)) { $dnsinad = "True" }
    if($adcomputers.Name.ToUpper().Contains($wmicomputername)) { $wmiinad = "True" }

    $obj = New-Object PSObject -Property @{
        "DNS CN" = $dnscomputername
        "DNS Domain" = $dnsdomain 
        "DNS IP Address" = $dnsip
        Online = $online.ToUpper()
        "WMI CN" = $wmicomputername
        "WMI Domain" = $wmidomain
        "DNS/WMI CN Match" = $dnswmicomputernamematches
        "DNS/WMI Domain Match" = $dnswmidomainmatches
        "DNS CN in VA" = $dnsinva
        "WMI CN in VA" = $wmiinva
        "DNS CN in AD" = $dnsinad
        "WMI CN in AD" = $wmiinad
    }
    $allobj += $obj
}

$allobj | select "DNS CN","DNS Domain","DNS IP Address",Online,"WMI CN","WMI Domain","DNS/WMI CN Match","DNS/WMI Domain Match","DNS CN in VA","WMI CN in VA","DNS CN in AD","WMI CN in AD"