[cmdletbinding()]
Param (
    [alias("s")]
    $server,
    $servers
)

function CreateServicesObj($server,$status,$service="N/A",$startmode="N/A",$state="N/A",$user="N/A"){
    $obj = New-Object PSObject -Property @{
        Server = $server
        Status = $status
        Service = $service
        StartMode = $startmode
        State = $state
        User = $user
    }
    return $obj
}

function GetServicesData($server) {
    if((Test-Connection -ComputerName $server -count 1 -ErrorAction 0)) {
        $status = "Online"
        try { $services = gwmi win32_service -cn $server -ea "STOP" }
        catch { $status = "WMI Query Failed" }
        if($services) {
            $servicesobj = @()
            $nonsystemservices = $services | where {$_.StartName -ne "LocalSystem" -and $_.StartName -ne "NT AUTHORITY\LocalService" -and $_.StartName -ne "NT Authority\NetworkService" -and $_.StartName -ne "NT AUTHORITY\LOCAL SERVICE" -and $_.StartName -ne "NT AUTHORITY\NETWORK SERVICE" }
            foreach($service in $nonsystemservices) {         
                $serviceobj = CreateServicesObj $server $status $service.Name $service.StartMode $service.State $service.StartName
                $servicesobj += $serviceobj
            }
        } elseif($status -eq "WMI Query Failed") { $servicesobj = CreateServicesObj $server "WMI Query Failed" }
    } else { $servicesobj = CreateServicesObj $server "Offline" }
    return $servicesobj
}

function ConnectToScheduleService($servername) {
    $schedule = New-Object -com("Schedule.Service")
    $pstatus = TestConnection $servername
    if($pstatus -eq "Online") {
        while($status -ne "Online" -and $attempts -lt 3) {
            try {
                Write-Verbose "$servername - Connecting to Schedule Service"
                $schedule.connect($servername)
                $status = "Online"
            }
            catch {
                Write-Verbose "$servername - Failed to connect"
                $attempts++
                $status = "Offline"
            }
        }
    } else {
        Write-Verbose "$servername - Did not respond to ping"
        $status = $pstatus 
    }
    return $schedule,$status
}

function TestConnection($server) {
    if((Test-Connection -ComputerName $server -count 1 -ErrorAction 0)) { $online = "Online" } 
    else { $online = "Offline" }
    return $online
}

function GetCustomTasks($schedule,$servername) {
    try {
        $tasks = $schedule.GetFolder("\").gettasks(1) 
        $customtasks = $tasks | where {$_.XML -notlike "*<UserId>System</UserId>*" -and $_.XML -notlike "*<UserId>S-1-5-18</UserId>*" -and $_.XML -notlike "*<UserId>S-1-5-19</UserId>*" -and $_.XML -notlike "*<UserId>S-1-5-20</UserId>*" }
    }
    catch {
        Write-Verbose "$servername - Failed to read Scheduled Tasks"
        $customtasks = "Failed to read Scheduled Tasks"
    }
    if(!$customtasks) { $customtasks = "No custom tasks"}
    return $customtasks
}

function GetTasksData($server) {
    $allobjs = @()
    $scheduleservice = ConnectToScheduleService $server
    if($scheduleservice[1] -eq "Online") {
        $customtasks = GetCustomTasks $scheduleservice[0] $server
        if($customtasks -ne "No custom tasks" -and $customtasks -ne "Failed to read Scheduled Tasks") {
            foreach($customtask in $customtasks) {
                Write-Verbose "Parsing task $($customtask.Name)"
                $xml = ParseXML $customtask
                $state = SwitchTaskState $customtask.State
                $obj = WriteTasksObj $server $scheduleservice[1] $customtask.Name $customtask.Enabled $state $xml[2] $customtask.LastRunTime $customtask.NextRunTime
                $allobjs += $obj
            }
        } else {
            Write-Verbose "$server - $customtasks"
            $allobjs = WriteTasksObj $server $customtasks
        } 
    } else {
        $allobjs = WriteTasksObj $server $scheduleservice[1]
    }
    return $allobjs
}

function WriteTasksObj($server,$status,$task="N/A",$enabled="N/A",$state="N/A",$user="N/A",$lastrun="N/A",$nextrun="N/A"){
    $obj = New-Object PSObject -Property @{
        Server = $server
        Status = $status
        Task = $task
        Enabled = $enabled
        State = $state
        User = $user
        LastRun = $lastrun
        NextRun = $nextrun
    }
    return $obj
}

function SwitchTaskState($taskstate) {
    switch ($taskstate) {
        1 {$state = "Disabled"}
        2 {$state = "Queued"}
        3 {$state = "Ready"}
        4 {$state = "Running"}
        default {$state = "Unknown"}
    }
    return $state
}

function ParseXML($purgetask) {
    $bad = $purgetask.xml -match "<Command>(?<command>.*)</Command>"
    try { $command = $matches['command'] }
    catch { $command = "Not defined" }
    $bad = $purgetask.xml -match "<Arguments>(?<arguments>.*)</Arguments>"
    try { $arguments = $matches['arguments'] }
    catch { $arguments = "Not defined" }
    $bad = $purgetask.xml -match "<UserID>(?<user>.*)</UserID>"
    try { $runas = $matches['user'] }
    catch { $runas = "Not defined" }
    return $command,$arguments,$runas
}

if($server) {
    GetServicesData $server | Select Server,Status,Service,StartMode,State,User
    GetTasksData $server | Select Server,Status,Task,Enabled,State,User,LastRun,NextRun
} elseif($servers) {
    $allobj,$alltasksobj = @(),@()
    $serverlist = get-content $servers
    foreach($server in $serverlist) {
        $i++
        Write-Progress -Activity "Working on $server" -Status "[$i/$($serverlist.count)]" -PercentComplete (($i/$serverlist.count)*100)
        $servicesobj = GetServicesData $server
        $allservicesobj += $servicesobj
        $tasksobj = GetTasksData $server 
        $alltasksobj += $tasksobj
    }
    $allservicesobj | Sort-Object Server,Service | Select Server,Status,Service,StartMode,State,User | export-csv services.csv -NoTypeInformation
    $alltasksobj | Sort-Object Server,Task | Select Server,Status,Task,Enabled,State,User,LastRun,NextRun | export-csv tasks.csv -NoTypeInformation
    Write-Host "Results have been written to services.csv and tasks.csv"
} else { Write-Host "The -server or -servers switch is required" }