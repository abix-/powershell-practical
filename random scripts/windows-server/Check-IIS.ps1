[cmdletbinding()]
Param (
    [Parameter(ParameterSetName="Servers",Mandatory=$true)]$servers,
    [Parameter(ParameterSetName="MyPlatform")]$datacenter,
    [Parameter(ParameterSetName="MyPlatform")]$stack,
    [Parameter(ParameterSetName="MyPlatform")]$role,
    [Parameter(ParameterSetName="Servers",Mandatory=$true)]
    [Parameter(ParameterSetName="MyPlatform",Mandatory=$true)]$service,
    [Parameter(ParameterSetName="MyPlatform")]$range,
    #[Parameter(Mandatory=$true)]$startmode,
    $MyPlatformcsv = "MyPlatform_servers.csv",
    $settings = "MyPlatform_services.csv",
    #$logdir = "C:\img_test",
    $Tail = 5000
)

#take MyPlatform server list..
#foreach server
#looks in logfile directories and find logs
#logparser to do tailing of $last lines
#top10 for..
##status codes,requests per hour,top uris requestsed,requests/sec

##Query-EventViewerLogs
##**Parses saved Event Viewer logs based on the SQL query defined in the script body.

function Query-EventViewerLogs{
    Param (
        [string]$logDir,
        $Queries
    )

    Begin{
        Write-Verbose "Loading Log Query"
	    $Parser = New-Object -COM MSUtil.LogQuery
	    $InputType = New-Object -COM MSUtil.LogQuery.IISW3CInputFormat
	    $OutputType = New-Object -COM MSUtil.LogQuery.CSVOutputFormat
	
        Write-Verbose "Finding delicious logs in $logDir"
        $logFiles = @()
        $logFiles = Get-ChildItem $LogDir | ?{$_.Extension -eq ".log"} | sort LastWriteTime -Descending | select Fullname,Name
	    $OutPath = (Get-Location).Path
        Write-Verbose "Found $($logFiles.length) logs"
	    If (!(Test-Path $OutPath\LogQuery)){New-Item -Path "$OutPath\LogQuery" -ItemType Directory -Force}
    }
    Process{
	    Foreach ($LogFile in $LogFiles){
            $TmpFilename = "$OutPath\LogQuery\tmp_$($logfile.name)"
            $Output = "$OutPath\LogQuery\EventLogSearch_$($LogFile.Name).csv"

            try { Remove-Item $TmpFilename -Force -ErrorAction SilentlyContinue }
            catch { }
            $tmptiming = Measure-Command {
                Get-Content $LogFile.fullname -First 4 | Out-File $TmpFilename -Encoding ascii
		        Get-Content $LogFile.fullname -Tail $Tail | Out-File $TmpFilename -Encoding ascii -Append
            }
            Write-Verbose "Temp file created at $TmpFilename in $($tmptiming.Milliseconds) milliseconds"

            foreach($q in $Queries) {
                $Query = "$($q.Select) FROM '$TmpFilename' $($q.Filter)"
                Write-Verbose "Parsing $($LogFile.Fullname): $Query"
                $querytiming = Measure-Command { Get-LPRecordSet -query $query | Out-Default }
                Write-Verbose "Query executed in $($querytiming.Milliseconds) milliseconds"
            }
            Remove-Item $TmpFilename -Force
	    }
    }
    End{
	    Write-Verbose "Taking out the garbage"
	    Remove-Variable -Name Parser -Force
	    Remove-Variable -Name InputType -Force
	    Remove-Variable -Name OutputType -Force
    }
}

function Invoke-LPExecute([string] $query, $inputtype) { 
    $LPQuery = new-object -com MSUtil.LogQuery
	if($inputtype){ $LPRecordSet = $LPQuery.Execute($query, $inputtype)	}
	else { $LPRecordSet = $LPQuery.Execute($query) }
    return $LPRecordSet
}

function Get-LPRecord($LPRecordSet){
	$LPRecord = new-Object System.Management.Automation.PSObject
	if( -not $LPRecordSet.atEnd()) {
		$Record = $LPRecordSet.getRecord()
		for($i = 0; $i -lt $LPRecordSet.getColumnCount();$i++) { $LPRecord | add-member NoteProperty $LPRecordSet.getColumnName($i) -value $Record.getValue($i)	}
	}
	return $LPRecord
}

function Get-LPRecordSet([string]$query){
	# Execute Query
	$LPRecordSet = Invoke-LPExecute $query
	$LPRecords = new-object System.Management.Automation.PSObject[] 0
	for(; -not $LPRecordSet.atEnd(); $LPRecordSet.moveNext()) {
		$LPRecord = Get-LPRecord($LPRecordSet)
		$LPRecords += new-Object System.Management.Automation.PSObject	
        $RecordCount = $LPQueryResult.length-1
        $LPRecords[$RecordCount] = $LPRecord
	}
	$LPRecordSet.Close();
    Write-Verbose "$($LPRecords.count) rows returned"
	return $LPRecords
}

function loadSettings() {
    try {
        $s = import-csv $settings | ?{$_.Service -eq $service}
        Write-Verbose $s
    }

    catch {
        if($role -and !$servers) {
            $s = New-Object PSObject -Property @{
                Service = $service
                Servers = ".*"
                Role = $role
            }
        } else { Write-Host "Failed to recognize or guess service. If guessing, -role is required."; Exit }
    }
    return $s
}

function getServers($_settings) {
    $destinations = @()
    if($PSCmdlet.ParameterSetName -eq "MyPlatform") {
        Write-Verbose "MyPlatform Mode"
        $MyPlatform = Import-Csv $MyPlatformcsv
        Write-Verbose "$($MyPlatform.count) servers found in MyPlatform"
        $allservers = $MyPlatform | ?{$_.name -match $_settings.servers -and $_.role -eq $_settings.role} | sort Name
        if($range) { $allservers = $allservers | ?{$_.name -like "*$range" } }
        Write-Verbose "Found $($allservers.count) MyPlatform servers across all environments"       
        if($stack) { foreach($_s in $stack) { $destinations += ($allservers | ?{$_.stack -eq "$_s"} | select -ExpandProperty Name | sort) }
        } elseif($datacenter) { foreach($_d in $datacenter) { $destinations += ($allservers | ?{$_.datacenter -eq "$_d"} | select -ExpandProperty Name | sort) }  }
        else { Write-Host "You must specify a -stack or -datacenter"; Exit }
    } elseif($PSCmdlet.ParameterSetName -eq "Servers") {
        if($servers.EndsWith(".txt")) { $destinations = gc $servers }
    }
    if($destinations.count -eq 0) { Write-Host "No destinations found. Ask Abix how to use me."; Exit }
    return $destinations
}

$settings = loadSettings
$servers = getServers $settings
$queries = Import-Csv iisqueries.csv

foreach($server in $servers) {
    $results = Query-EventViewerLogs -logDir "$server\g$\LogFiles\" -Queries $queries
    $results
}