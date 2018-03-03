[cmdletbinding()]
Param (
    $domain,
    $server
)

function WriteToObj($server,$state="N/A",$sessionid="N/A",$clientname="N/A",$useraccount="N/A",$connecttime="N/A",$idletime="N/A") {
    $obj = New-Object PSObject -Property @{
        Server = $computer
        SessionID = $sessionid
        State = $state
        ClientName = $clientname
        UserAccount = $useraccount
        ConnectTime = $connecttime
        IdleTime = $idletime
    }
    return $obj
}

Import-Module PSTerminalServices
Import-Module ActiveDirectory

if($domain) {
    $computers = Get-ADComputer -Server $domain -filter * | select -expand Name
} elseif($file) {
    $computers = Get-Content $file
} elseif($server) {
    $computers = $server
}

if($computers) {
    $allsessions = @()
    $i = 0
    foreach($computer in $computers) {
        $i++
        Write-Progress -Activity "Working on $computer" -Status "[$i/$($computers.count)]" -PercentComplete (($i/$computers.count)*100)
        try  {
            if((Test-Connection -ComputerName $computer -count 1 -ErrorAction 0)) {
                $sessions = Get-TSSession -computername "$computer" | ?{$_.UserAccount -ne $null} | select @{Name="Server";Expression={$_.Server.ServerName}},SessionID,State,ClientName,UserAccount,ConnectTime,IdleTime
            } else  { $sessions = WriteToObj $computer "Offline" }
        }
        catch {
            $sessions = WriteToObj $computer "Offline"
        }
        $allsessions += $sessions
    }
    $allsessions
} else {
    Write-Host "No computers found"
}