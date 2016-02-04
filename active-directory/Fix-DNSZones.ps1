[cmdletbinding()]
Param (
    [Parameter(Mandatory=$true)]$domain,
    [Parameter(Mandatory=$true)]$ref_dc,
    $target_dc
)

filter set-type {
    param([hashtable]$type_hash)
    foreach ($key in $($type_hash.keys)){
        $_.$key = $($_.$key -as $type_hash[$key])
    }
    $_
}

$dcs = Import-Csv "$((Get-Location).Path)\Check-DNSZones_$($domain).csv" | set-type -type_hash @{'DomainController'=[string];'PrimaryZones'=[int];'SecondaryZones'=[int]}
$sec_zones = Import-Csv "$((Get-Location).Path)\Check-DNSZones_$($domain)_secondary.csv"
#$master_dc = $dcs | Sort-Object -Property SecondaryZones -Descending | Select-Object -First 1
$master_dc = $dcs | ?{$_.DomainController -eq $ref_dc}
if($master_dc) {
Write-Host "Using $($master_dc.DomainController) as the reference. Primary:$($master_dc.PrimaryZones)  Secondary:$($master_dc.SecondaryZones)"} 
else { Write-Host "$($ref_dc) not found. Aborting"; Exit }
$master_zones = $sec_zones | ?{$_.DomainController -eq $master_dc.DomainController -and $_.SecondaryZone -ne "ndr.tf"}
$master_zones | select DomainController,SecondaryZone,MasterServer0,MasterServer1,MasterServer2,MasterServer3
Write-Host "Loaded $($master_zones.count) secondary zones from '$((Get-Location).Path)\Check-DNSZones_$($domain).csv'"
Pause

if(!$target_dc) {
    $otherdcs = $dcs | ?{$_.DomainController -ne $master_dc.DomainController}
} else {
    $otherdcs = $dcs | ?{$_.DomainController -eq $target_dc}
}

foreach($_m in $master_zones) {
    $_m_masters = ("$($_m.MasterServer0) $($_m.MasterServer1) $($_m.MasterServer2) $($_m.MasterServer3)").Trim()
    $m_array = @()
    if($_m.MasterServer0) { $m_array += $_m.MasterServer0 }
    if($_m.MasterServer1) { $m_array += $_m.MasterServer1 }
    if($_m.MasterServer2) { $m_array += $_m.MasterServer2 }
    if($_m.MasterServer3) { $m_array += $_m.MasterServer3 }
    foreach($_o in $otherdcs) {
        $_zone = $sec_zones | ?{$_.DomainController -eq $_o.DomainController -and $_.SecondaryZone -eq $_m.SecondaryZone}
        if($_zone) {
            Write-Verbose "$($_m.SecondaryZone) - $($_o.DomainController) - Exists!"
            $_zone_masters = ("$($_zone.MasterServer0) $($_zone.MasterServer1) $($_zone.MasterServer2) $($_zone.MasterServer3)").Trim()
            if($_m_masters -ne $_zone_masters) {
                Write-Host "$($_m.SecondaryZone) - $($_o.DomainController) - local '$($_zone_masters)' is not equal to reference '$($_m_masters)'" -ForegroundColor Red
                if($confirm -ne "A") { $confirm = Read-Host "Change masters to '$($_m_masters)'? - Yes/No/All (Y/N/A)" }
                switch ($confirm) {
                    {($_ -like "Y") -or ($_ -like "A")} {
                        Write-Host "$($_m.SecondaryZone) - $($_o.DomainController) - Changing masters to $_m_masters" -ForegroundColor Green
                        $script = "C:\windows\system32\dnscmd.exe /zoneresetmasters $($_m.SecondaryZone) $($_m_masters)"
                        $servername = $_o.DomainController -replace ".domain.local","" -replace ".domain.local",""
                        Invoke-VMScript -VM $servername -ScriptText $script -ScriptType Bat -RunAsync
                    }
                    "N" {Write-Host "Skipped change"}
                }
            } else {
                Write-Verbose "$($_m.SecondaryZone) - $($_o.DomainController) - '$($_m_masters)' is equal to '$($_zone_masters)'"
            }
        } else {
            Write-Host "$($_m.SecondaryZone) - $($_o.DomainController) - Does not exist" -ForegroundColor Red
            if($confirm -ne "A") { $confirm = Read-Host "Create zone with '$($_m_masters)'? - Yes/No/All (Y/N/A)" }
            $test = $_m.SecondaryZone
            Write-Host $test
            switch ($confirm) {
                {($_ -like "Y") -or ($_ -like "A")} { ([WMIClass]"\\$($_o.DomainController)\root\MicrosoftDNS:MicrosoftDNS_Zone").CreateZone(($test), 1, $false, "$test.dns", $m_array) }
                "N" {Write-Host "Skipped change"}
            }
            $test = $null               
        }
    }
}