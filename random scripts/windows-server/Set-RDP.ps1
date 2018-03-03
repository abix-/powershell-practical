Import-Module PSRemoteRegistry
$servers = gc pciservers.txt

function GetDWord($server,$key,$value) {
    
    try { 
        $exists = Get-RegDWord -CN $server -Hive LocalMachine -Key $key -Value $value -ea "STOP" -AsHex
        $dword = $exists.Data
    }
    catch { $dword = "Key does not exist" }
    return $dword
}

foreach($server in $servers)
{
    $isalive = Test-RegKey -CN $server -Hive LocalMachine -Key "Software" -Ping
    $encryption = "N/A"
    if($isalive) {
        $cstatus = "Connected"
        Write-Host "Working on $server"
        $encryption = GetDWord $server "SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-TCP\" "MinEncryptionLevel"
        if($encryption -eq "0x2") {
            Write-Host "Setting value on $server"
            Set-RegDWord -CN $server -Hive LocalMachine -Key "SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-TCP\" -Value MinEncryptionLevel -Data 3 -Force
        }
    } else {
        Write-Host "$server - Failed to connect to remote registry"
        $cstatus = "Failed to connect"
    }
}