[cmdletbinding()]
Param (
    [parameter(Mandatory=$true)]
    $csv = "results.csv",
    [parameter(Mandatory=$true)]
    $threshold,
    [parameter(Mandatory=$true)]
    $sendquota,
    [parameter(Mandatory=$true)]
    $warningquota
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

$users = @(GetCSV $csv)
foreach($user in $users) {
    if(($user."TotalItemSize (MB)" -lt $threshold) -and ($user."ProhibitSendQuota (MB)" -ne $sendquota) -and ($user."ProhibitSendQuota (MB)" -ne $warningquota)) {
        Write-Host "$($user.username) can be adjusted"
    }
}