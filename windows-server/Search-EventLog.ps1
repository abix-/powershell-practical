[cmdletbinding()]
Param (
    $ComputerName = "localhost",
    $Log = "security",
    $ProviderName,
    $Keywords,
    $ID,
    $Level,
    $StartTime = ((get-date).adddays(-1)),
    $EndTime,
    $UserID,
    $MaxEvents = 100,
    #[switch]$Oldest = $false,
    $Search,
    $Type,
    $creduser = "domain.local\admin"
)

function createHashTable() {
    #if($LogName -like "Security") { $Level -eq $null }
    $hash = @{}
    if($Log) { $hash.Add("LogName",$Log) }
    if($ProviderName) { $hash.Add("ProviderName",$ProviderName) }
    if($Keywords) { $hash.Add("Keywords",$Keywords) }
    if($ID) { $hash.Add("ID",$ID) }
    if($Level) { $hash.Add("Level",$Level) }
    if($StartTime) { $hash.Add("StartTime",$StartTime) }
    if($EndTime) { $hash.Add("EndTime",$EndTime) }
    return $hash
}

function getEventData($events) {
    ForEach ($Event in $Events) {           
        $eventXML = [xml]$Event.ToXml()                    
        For ($i=0; $i -lt $eventXML.Event.EventData.Data.Count; $i++) { Add-Member -InputObject $Event -MemberType NoteProperty -Force -Name $eventXML.Event.EventData.Data[$i].name -Value $eventXML.Event.EventData.Data[$i].'#text' }            
    }
    return $Events
}

function doType() {
    if($type -eq "" ) { }
}

function getEvents($filterhash) {
    #need validation in here
    try { 
        $events = Get-EventLog -LogName $log -ComputerName $ComputerName -Newest 100 -After $StartTime -ErrorAction STOP
    }
    catch {
        Write-Host 
    }
    return $events
}

function filterEvents() {
    $Global:filterevents = ""
    if($id) { $Global:filterevents = getEventData $allevents }
    if($search) { $Global:filterevents = $allevents | ?{$_.message -like "*$search*"}  }
    if($Global:filterevents -eq "") { $Global:filterevents = $allevents }
}

function Main() {
    $Global:allevents = ""

    $filterhash = createHashTable
    $Global:allevents = getEvents $filterhash
    filterEvents
    if($filterevents.count -ne $null -and $filterevents.count -ne 0) {
           drawInfo $events
    } else { Write-Host "No logs found"; Exit }
}

function drawInfo() {
    [gc]::Collect()
    Clear-Host
    Write-Host "Computer:`t$($computername)"
    Write-Host "Log:`t`t$($log)"
    Write-Host "Search String:`t$($search)"
    Write-Host "Results:`t$($filterevents.count)"
    Write-Host ""
    Write-Host "Max Results:`t$($maxevents)"
    $option = Read-Host "refresh csv view exit" 
    switch -Wildcard ($option) {
        "computer *" { $value = getOptionValue $option; $computername = $value; drawInfo }
        "log *" { $value = getOptionValue $option; $log = $value; drawInfo }
        "refresh" { Main }
        "search" { $search = $null; filterEvents; drawInfo }
        "search *" { $value = getOptionValue $option; $search = $value; filterEvents; drawInfo }
        "csv" { $filterevents | Export-Csv t.csv -NoTypeInformation; ii t.csv; drawInfo  }
        "exit" { Exit }
        "view" { $filterevents | Select-Object -Unique TimeWritten,Message,EventID,EntryType,Source,* -ErrorAction SilentlyContinue | Out-GridView; drawInfo }
        default { drawInfo }
    }
}

function getOptionValue($option) {
    return ($option.Split(" "))[1]
}

function doSearch($events) {
    Clear-Host
    Write-Host "Enter a new search string"
    $option = Read-Host
    switch -wildcard ($option) {
        "*" { $search = $option; filterEvents; drawInfo }
        "back" { drawinfo $events }
        "exit" { Exit }
    }
}