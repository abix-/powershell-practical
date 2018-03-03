[cmdletbinding()]
param(
    $destination = "\\server.domain.local\c$",
    $text = "This is not a test`n", 
    $folder = "." ,
    $sizes = (500kb,5mb,10mb), 
    $fileprefix = "TestFile",
    $testcount = 5
)

function convertSizeUnit($_size) { 
    switch ($_size) { 
        { $_ -ge 1TB } { $sizeText = "$($_/1TB)T"; break;} 
        { $_ -ge 1GB } { $sizeText = "$($_/1GB)G"; break;} 
        { $_ -ge 1MB } { $sizeText = "$($_/1MB)M"; break;} 
        { $_ -ge 1KB } { $sizeText = "$($_/1KB)K"; break;} 
        default { $sizeText = "${_}B" } 
    } 
    return $sizeText 
}

function createFile($_text, $_size, $_folder = '.') {
    $fileName = "test" + (convertSizeUnit $_size) + ".tmp"
    if(Test-Path $_folder\$fileName) { 
        Write-Verbose "Deleting old file at $_folder\$fileName"
        Remove-Item $_folder\$fileName
    }
    Write-Verbose "$($filename): Creating $_size byte file at $_folder\$filename"
    fsutil.exe file createnew $filename $_size.tostring()
    $results = New-Object PSObject -Property @{
        Path = $_folder
        Filename = $filename
        Fullname = "$_folder\$filename"
        Size = $_size
    }
    return $results
}


function Copy-File {
    param( [string]$from, [string]$to)
    $ffile = [io.file]::OpenRead($from)
    $tofile = [io.file]::OpenWrite($to)
    $filename = ($from.Split("\") | select -Last 1)
    Write-Progress -Activity "Copying file" -status $filename -PercentComplete 0
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew();
        [byte[]]$buff = new-object byte[] (4096*1024)
        [long]$total = [long]$count = 0
        do {
            $count = $ffile.Read($buff, 0, $buff.Length)
            $tofile.Write($buff, 0, $count)
            $total += $count
            [int]$pctcomp = ([int]($total/$ffile.Length* 100));
            $secselapsed = [int]($sw.elapsedmilliseconds.ToString())/1000;
            $mselapsed = [int]($sw.elapsedmilliseconds.ToString())/1000;
            if ( $secselapsed -ne 0 ) { [single]$xferrate = (($total/$secselapsed)/1mb);
            } else { [single]$xferrate = 0.0 }
            if ($total % 1mb -eq 0) {
                if($pctcomp -gt 0) { [int]$secsleft = ((($secselapsed/$pctcomp)* 100)-$secselapsed);
                } else { [int]$secsleft = 0 };
                Write-Progress `
                    -Activity ($pctcomp.ToString() + "% Copying file at " + "{0:n2}" -f $xferrate + " MB/s")`
                    -status ($from.Split("\")|select -last 1) `
                    -PercentComplete $pctcomp `
                    -SecondsRemaining $secsleft;
            }
        } while ($count -gt 0)
    $sw.Stop();
    $sw.Reset();
    }
    finally {
        $speed = "{0:n2}" -f (($ffile.length/$secselapsed)/1mb)
        Write-Verbose "$filename copied in $secselapsed seconds at $speed MB/s"
        $ffile.Close();
        $tofile.Close();
    }
}

function reportResults($_allresults) {
    $report = @()
    $files = $_allresults | select -ExpandProperty Filename -Unique
    foreach($file in $files) {
        $tests = $_allresults | ?{$_.filename -eq $file -and $_.status -eq "OK"}
        $failedtests = $_allresults | ?{$_.filename -eq $file -and $_.status -ne "OK"}
        $minwrite = ($tests | sort writembps | select -First 1).writembps
        $maxwrite = ($tests | sort writembps -Descending | select -First 1).writembps
        $avgwrite = [math]::Round(($tests | Measure-Object -Property writembps -Average).Average,2)

        $minread = ($tests | sort readmbps | select -First 1).readmbps
        $maxread = ($tests | sort readmbps -Descending | select -First 1).readmbps
        $avgread = [math]::Round(($tests | Measure-Object -Property readmbps -Average).Average,2)

        $writesecondsavg = [math]::Round(($tests | Measure-Object -Property writeseconds -Average).Average,2)
        $readsecondsavg = [math]::Round(($tests | Measure-Object -Property readseconds -Average).Average,2)

        $report += New-Object PSObject -Property @{
            Source = $tests[0].source
            Destination = $tests[0].destination
            Tests = $tests.count
            TestsFailed = $failedtests.count
            Filename = $file
            FilesizeMB = [Math]::Round($tests[0].filesize/1mb,2)
            WriteMbpsMin = $minwrite
            WriteMbpsMax = $maxwrite
            WriteMbpsAvg = $avgwrite
            WriteSecondsAvg = $writesecondsavg
            ReadMbpsMin = $minread
            ReadMbpsMax = $maxread
            ReadMbpsAvg = $avgread
            ReadSecondsAvg = $readsecondsavg
        }
        
    }
    return $report
}

$sourcewmi = gwmi win32_computersystem
$source = "$($sourcewmi.name).$($sourcewmi.domain)"
$allresults = @()
foreach($dst in $destination) {
    foreach($size in $sizes) {
        $testfile = createFile $text $size
        $i = 1
        while($i -le $testcount) {
            Write-Verbose "Starting loop $i of $testcount"
            try {
                if(Test-Path "$PSScriptRoot\$($testfile.filename)" -ErrorAction Stop) {


                    Write-Verbose "$($testfile.filename): Copying from $PSScriptRoot\$($testfile.filename) to $destination\$($testfile.filename)"
                    $writetest =  Measure-Command { Copy-File "$PSScriptRoot\$($testfile.filename)" "$destination\$($testfile.filename)" }
                    Write-Verbose "$($testfile.filename): Copying from $destination\$($testfile.filename) to $PSScriptRoot\$($testfile.filename)"
                    $readtest =  Measure-Command { Copy-File "$destination\$($testfile.filename)" "$PSScriptRoot\$($testfile.filename)" }
                    $WriteMbps = [Math]::Round((($testfile.size * 8) / $WriteTest.TotalSeconds) / 1048576,2)
                    $ReadMbps = [Math]::Round((($testfile.size * 8) / $ReadTest.TotalSeconds) / 1048576,2)
                    $status = "OK"
                }
                Remove-Item "$destination\$($testfile.filename)"
            }

            catch {
                $WriteMbps = $ReadMbps = 0
                $WriteTest = $ReadTest = New-TimeSpan -Days 0
                $status = $_.exception.message
            }         

            $allresults += New-Object PSObject -Property @{
                Source = $source
                Destination = $dst
                Status = $status
                Filename = $testfile.filename
                Filesize = $testfile.size
                WriteSeconds = [Math]::Round($writetest.TotalSeconds,2)
                WriteMS = [Math]::Round($writetest.TotalMilliseconds,2)
                WriteMbps = $WriteMbps
                ReadSeconds = [Math]::Round($readtest.TotalSeconds,2)
                ReadMS = [Math]::Round($readtest.TotalMilliseconds,2)
                ReadMbps = $ReadMbps
            }
            $i++
        }
        Remove-Item "$PSScriptRoot\$($testfile.filename)"
    }
}

#add local admin check

$failed = $allresults | ?{$_.status -ne "OK"}
if($failed) { $failed | select source,filename,destination,status | fl }

if($allresults) { reportResults $allresults | select Source,Destination,Tests,TestsFailed,Filename,FilesizeMB,WriteSecondsAvg,WriteMbpsMin,WriteMbpsMax,WriteMbpsAvg,ReadSecondsAvg,ReadMbpsMin,ReadMbpsMax,ReadMbpsAvg }