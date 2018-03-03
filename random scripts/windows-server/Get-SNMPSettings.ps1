[cmdletbinding()]
Param (
    $servers
)

Import-Module psrr
$datetime = Get-Date -format yyyy-MM-dd_HHmmss

function GetDWord($server,$key,$value) {
    try { 
        $key = Get-RegDWord -CN $server -Hive LocalMachine -Key $key -Value $value -ea "STOP"
        $dword = $key.Data
    }
    catch { $dword = "Key does not exist" }
    return $dword
}

$allresults = @()
$i = 0
foreach($server in $servers) {
    $results = New-Object PSObject
    $i++

    $results | Add-Member -MemberType NoteProperty -Name Server -Force -Value $server

    $results | Add-Member -MemberType NoteProperty -Name Server -Force -Value (GetDWord $server "SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-TCP\" "MinEncryptionLevel")


    $allresults += $results
}