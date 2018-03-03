[cmdletbinding()]
Param (
    [parameter(Mandatory=$true)]$servers,
    [parameter(Mandatory=$true)]$xml,
    [parameter(Mandatory=$true)]$taskname = "Weblog_Purge",
    [parameter(Mandatory=$true)]$runas = "domain.local\svcTasks"
)

if($servers.EndsWith(".txt")) { $servers = gc $servers }
if(!(Test-Path $xml)) { Write-Host "$xml does not exist. Aborting" }

$pass = Read-Host "Password for $runas" -AsSecureString
$plainpass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))

foreach($server in $servers) {
    Write-Host "Working on $server"
    if((Test-Connection -ComputerName $server -count 1 -ErrorAction 0)) { schtasks.exe /create /s "$server" /ru "$runas"  /rp "$plainpass" /xml $xml /tn "$taskname" }
    else { Write-Host "$server did not respond to ping. Skipping" }
}