[cmdletbinding()]
Param (
    [alias("s")]
    $server,
    $csv
)

function GetCSV($csvfile) {
   if(!(Test-Path $csvfile)) { Write-Verbose "$($csvfile) does not exist. Try again." }
   elseif(!($csvfile.substring($csvfile.LastIndexOf(".")+1) -eq "csv")) { Write-Verbose "$($csvfile) is not a CSV. Try again." }
   else {
	    $csv = @(Import-Csv $csvfile)
        if(!$csv) { Write-Verbose "The CSV is empty. Try again." }
        else {
            $csvvalid = $true
            return $csv
        }
    }
}

Function DoSomething($server) {
    if((Test-Connection -ComputerName $server -count 1 -ErrorAction 0)) {
        $status = "Online"
        #Things to do to $server
    } else { $status = "Offline" }

    $obj = New-Object PSObject -Property @{
        Server = $server
        Online = $status
    }
    return $obj
}

if($server) {
    DoSomething $server
} elseif($csv) {
    $allobj = @()
    $servers = @(GetCSV $csv)
    foreach($server in $servers) {
        Write-Progress -Activity "Working on $($server.name)" -Status "[$i/$($servers.count)]" -PercentComplete (($i/$servers.count)*100)
        $obj = DoSomething $server.Name
        $allobj += $obj
        $i++
    }
    $allobj
} else {
    Write-Host "The -server or -csv switch is required"
}