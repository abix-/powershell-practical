[cmdletbinding()]
Param (
    $server,
    $domain
)

cvi | Out-Null
if($server) { $vmhosts = Get-VMHost $server }
elseif($domain) { $vmhosts = Get-VMHost | ?{$_.Name -like "*$domain" } }
else { $vmhosts = Get-VMHost | ?{$_.Name -like "*domain.local"} | sort name }
$cred = Get-Credential
foreach($v in $vmhosts) {
    Write-Host "Working on $($v.name)"
    Connect-VIServer -server $v.name -Credential $cred -OutVariable $out
    Get-VMHostSnmp | Set-VMHostSnmp -Enabled:$true -ReadOnlyCommunity ffreadonly1
}