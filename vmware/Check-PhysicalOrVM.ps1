[cmdletbinding()]
Param (
    [alias("s")]
    $server,
    $csv
)

function GetCSV($csvfile) {
   if(!(Test-Path $csvfile)) { 
        Write-Verbose "$($csvfile) does not exist. Try again."
   }
   elseif(!($csvfile.substring($csvfile.LastIndexOf(".")+1) -eq "csv")) {
        Write-Verbose "$($csvfile) is not a CSV. Try again."
   }
   else {
	    $csv = @(Import-Csv $csvfile)
        if(!$csv) {
            Write-Verbose "The CSV is empty. Try again."
        }
        else {
            $csvvalid = $true
            return $csv
        }
    }
}

Function isVM($server) {
    if((Test-Connection -ComputerName $server -count 1 -ErrorAction 0)) {
        $wmiobj = Get-WmiObject -Class Win32_ComputerSystem -ComputerName $server
        if($wmiobj) {
            if($wmiobj.Manufacturer.ToLower() -match "vmware") {
                $status = "Virtual"    
            } else {
                $status = "Physical"
            }
        } else {
            $status = "Failed to perform WMI query"
        }
    } else {
        $status = "Offline"
    }

    $obj = New-Object PSObject -Property @{
        Server = $server
        Type = $status
    }
    return $obj
}

if($server) {
    isVM $server
} elseif($csv) {
    $allobj = @()
    $servers = @(GetCSV $csv)
    foreach($server in $servers) {
        Write-Progress -Activity "Working on $($server.name)" -PercentComplete (($i/$servers.count)*100)
        $obj = isVM $server.Name
        $allobj += $obj
        $i++
    }
    $allobj | sort-object Type
}