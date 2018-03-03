Import-Module PSRemoteRegistry
$servers = gc stacks.txt

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
    Write-Host "Working on $server"
    if($isalive) {
        try { $os = gwmi win32_operatingsystem -cn $server -ea "STOP" | select caption }
        catch { $cstatus = "WMI Query Failed" }

        if($os -like "*2008*") {
            $userauth = GetDWord $server "SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-TCP\" "UserAuthentication"
            if($userauth -eq "0x0") {
                Write-Host "$server - Enabling NLA Authentication"
                Set-RegDWord -CN $server -Hive LocalMachine -Key "SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-TCP\" -Value "UserAuthentication" -Data 1 -Force
            }
        } elseif($cstatus -eq "WMI Query Failed") {
            Write-Host "$server - WMI Query Failed"
        } else {
            Write-Host "Only Server 2008 supports NLA Authentication"
        }
    } else {
        Write-Host "$server - Failed to connect to remote registry"
    }
}