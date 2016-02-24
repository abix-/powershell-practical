[cmdletbinding()]
param(
    $folder
)

if($folder -eq $null) { 
    $app = new-object -com Shell.Application; $browse = $app.BrowseForFolder(0, "Select Folder", 0, 0)
    if ($browse -eq $null) { Write-Host "You did not provide a valid path. Aborting"; Exit }
    $folder = $browse.self.path
}

if(!(Test-Path $folder)) { Write-Host "$folder is inaccessible. Aborting"; Exit }
try { $allfiles = gci -Recurse $folder | ?{$_.psiscontainer -eq $false} }
catch { Write-Host "Failed to read data from $folder. Aborting."; Exit }

$dateregex = "([\d]+)[- /.]([\d]+)[- /.]([\d]+)"
if($folder -match $dateregex) {
    $calcdate = "{0:MM/dd/yy}" -f [datetime]$matches[0]
    $calcweek = get-date $calcdate -uformat %V
    $calcmonth = get-date $calcdate -format "MMMM yyyy"
    $dayofweek = (get-date $calcdate).dayofweek.value__
    switch ($dayofweek) 
    {
        0 { $sunday = get-date $calcdate ; $saturday = (get-date $calcdate).AddDays(6) }
        1 { $sunday = (get-date $calcdate).AddDays(-1) ; $saturday = (get-date $calcdate).AddDays(5) }
        2 { $sunday = (get-date $calcdate).AddDays(-2) ; $saturday = (get-date $calcdate).AddDays(4) }
        3 { $sunday = (get-date $calcdate).AddDays(-3) ; $saturday = (get-date $calcdate).AddDays(3) }
        4 { $sunday = (get-date $calcdate).AddDays(-4) ; $saturday = (get-date $calcdate).AddDays(2) }
        5 { $sunday = (get-date $calcdate).AddDays(-5) ; $saturday = (get-date $calcdate).AddDays(1) }
        6 { $sunday = (get-date $calcdate).AddDays(-6) ; $saturday = (get-date $calcdate).AddDays(0) }
    }
    $sunday = get-date $sunday -Format "MM/dd/yy"
    $saturday = get-date $saturday -Format "MM/dd/yy"
}

$allobj = @()
foreach($file in $allfiles) {
    $i++
    Write-Progress -Activity "Working on $($file.name) [$i/$($allfiles.count)]" -Status " " -PercentComplete (($i/$allfiles.count)*100)
    $filesizekb = $null
    $filesizekb = "{0:N1}" -f ($file[0].length/1Kb)
    $fileowner = (get-acl $file.FullName).owner
    $allobj += New-Object PSObject -Property @{ 
        Date = $calcdate
        Filename = $file.name
        "Size (KB)" = $filesizekb
        Type = $file.Extension
        Created = $file.CreationTime
        "Last Accessed" = $file.LastAccessTime
        "Last Modified" = $file.LastWriteTime
        "Folder and name" = $file.FullName
        Owner = $fileowner
        "Week Number" = $calcweek
        Month = "=""$calcmonth"""
        "Week Range" = "$sunday - $saturday"
    }  
}

$o = 0
do { $o++ } while (Test-Path folderinfo$o.csv)
$allobj | Select Date,Filename,"Size (KB)",Type,Created,"Last Accessed","Last Modified","Folder and name",Owner,"Week Number","Month","Week Range" | Export-Csv C:\Scripts\folderinfo$o.csv -NoTypeInformation
ii C:\Scripts\folderinfo$o.csv