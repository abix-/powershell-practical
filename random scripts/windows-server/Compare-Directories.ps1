[cmdletbinding()]
param (
    $source,
    $destinations,
    [switch]$showsuccess = $false,
    $logname = "compare.log",
    $rotation_threshold_mb = 10,
    [switch]$recursive = $false,
    [switch]$bysubfolder = $false,
    [switch]$excludeconfigs = $false
)

if($destinations.EndsWith(".txt")) { $destinations = gc $destinations }

function getHash($filepath) {
    try {
        $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
        $hash = [System.BitConverter]::ToString($md5.ComputeHash([System.IO.File]::ReadAllBytes($filepath))).Replace("-","")
    }
    catch { $hash = "file not found" }
    $obj = New-Object PSObject -Property @{
        File = $filepath
        Hash = $hash
    }
    return $obj
}

function writeToObj($destination,$mismatches="N/A") {
    $obj= New-Object PSObject -Property @{
            Destination = $destination
            Mismatches = $mismatches
    }
    return $obj
}

function doValidation($source,$destinations,$foldername="N/A") {
    $results = @()
    LogToFile "Starting to compare $source"
    $sourcehashes = @()
    $sourcefiles = gci -File -Path $source -Recurse
    if($excludeconfigs) { $sourcefiles = $sourcefiles | ?{($_.Name.ToLower()).EndsWith(".config") -ne $true} }
    $i = 0; $j = 1
    foreach($sourcefile in $sourcefiles) {
        $i++
        if($i % 50 -eq 0 -or $i -eq $sourcefiles.count) { Write-Progress -Activity "Generating Source MD5Sums [Step $j of $($destinations.count + 1)]" -Status "$($sourcefile.fullname) [$i/$($sourcefiles.count)]" -PercentComplete (($i/($sourcefiles.count))*100) }
        $obj = getHash $sourcefile.FullName
        $sourcehashes += $obj
    }
    foreach($destination in $destinations) {
        if($destination) {
            $j++
            if($foldername -ne "N/A") { $destination += "\$foldername" }
            $tempmismatchcount = 0
            Write-Host "Working on $destination"
            LogToFile "Working on $destination"
            if(Test-Path $destination) {
                $i = 0
                foreach($sourcehash in $sourcehashes) {
                    $i++
                    $filename = $sourcehash.file.substring($source.Length+1)
                    $temphash = getHash "$destination\$filename"
                    if($i % 50 -eq 0 -or $i -eq $sourcehashes.count) { Write-Progress -Activity "Comparing MD5Sums with $destination [Step $j of $($destinations.count + 1)]" -Status "$destination\$filename [$i/$($sourcehashes.count)]" -PercentComplete (($i/($sourcehashes.count))*100) }
                    if($sourcehash.hash -ne $temphash.hash) {
                        if($temphash.hash -ne "File not found") {
                            Write-host "$($filename): $($sourcehash.hash) does not match $($temphash.hash)" -ForegroundColor Red
                            LogToFile "$($filename): $($sourcehash.hash) does not match $($temphash.hash)"
                            $tempmismatchcount++
                        } else {
                            Write-host "$($filename): $($temphash.hash)" -ForegroundColor Red
                            LogToFile "$($filename): $($temphash.hash)"
                            $tempmismatchcount++
                        }
                    } else {
                        if($showsuccess -eq $true) {
                            Write-Host "$($filename): $($sourcehash.hash) matches" -ForegroundColor Green
                            LogToFile "$($filename): $($sourcehash.hash) matches"
                        }
                    }
                }
            } else  {
                Write-Host "The folder does not exist" -ForegroundColor Red
                LogToFile "The folder does not exist"
            }
            if($tempmismatchcount -eq 0 -and (Test-Path $destination)) {
                Write-Host "All files match" -ForegroundColor Green
                LogToFile "All files match"
            } elseif($tempmismatchcount -gt 0 -and (Test-Path $destination)) {
                LogToFile "File mismatch found in $destination"
                LogToFile "$tempmismatchcount files do not match"
                $obj = writeToObj $destination $tempmismatchcount
                $results += $obj
            }
            Write-Host ""
        }
    }
    LogToFile "Finished comparing $source"
    return $results
}

function LogToFile($message) {
    $date = Get-Date -f yyy-MM-dd
    $time = Get-Date -f HH:mm:ss
    if(Test-Path "$logname") {
        $filesize = (Get-Item "$logname").length/1MB
        if ($filesize -gt $rotation_threshold_mb) {
            Remove-Item "$logname"
            Write-Host "The log reached a maximum size of $rotation_threshold_mb MB and was purged."
            "$date $time - The log reached a maximum size of $rotation_threshold_mb MB and was purged." | Out-File "$logname" -append
        }
    }
    "$date $time - $message" | Out-File "$logname"-append
}

$allresults = @()
if(!$recursive) {
    doValidation $source $destinations
} elseif ($bysubfolder -eq $true) {
    $folders = gci $source | ?{ $_.PSIsContainer }
    foreach($folder in $folders) {
        $results = doValidation $folder.FullName $destinations $folder.name
        $allresults += $results
    }
    $allresults | select Destination,Mismatches | Export-Csv compare-mismatches.csv -NoTypeInformation
} elseif ($bysubfolder -eq $false) {
    $folders = gci $source | ?{ $_.PSIsContainer }
    foreach($destination in $destinations) {
        foreach($folder in $folders) {
            $results = doValidation $folder.FullName $destination $folder.name
            $allresults += $results
        }
    }
    $allresults | select Destination,Mismatches | Export-Csv compare-mismatches.csv -NoTypeInformation
}