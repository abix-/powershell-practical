[cmdletbinding()]
Param (
    [Parameter(ParameterSetName="Servers",Mandatory=$true)]$servers,
    [Parameter(ParameterSetName="Servers")]$path,
    [Parameter(ParameterSetName="TCS")]$datacenter,
    [Parameter(ParameterSetName="TCS")]$stack,
    [Parameter(ParameterSetName="TCS")]$role,
    [Parameter(ParameterSetName="Servers",Mandatory=$true)]
    [Parameter(ParameterSetName="TCS",Mandatory=$true)]$service,
    [Parameter(ParameterSetName="Servers",Mandatory=$true)]
    [Parameter(ParameterSetName="TCS")][string]$source,
    [Parameter(ParameterSetName="TCS")]$range,
    [switch]$validate = $false,
    $tcscsv = "tcs_servers.csv",
    $settings = "tcs_services.csv",
    $threads = 10
)

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
                Path = "g$\Services\$service"
            }
        } elseif(!$role -and $servers -and $path) {
            $s = New-Object PSObject -Property @{
                Service = $service
                Servers = ""
                Role = ""
                Path = "$path"
            }
        } else { Write-Host "Failed to recognize or assume service. If assuming, -role is required."; Exit }
    }
    return $s
}

function getServers($_settings) {
    $destinations = @()
    if($PSCmdlet.ParameterSetName -eq "TCS") {
        Write-Verbose "TCS Mode"
        $tcs = Import-Csv $tcscsv
        Write-Verbose "$($tcs.count) servers found in TCS"
        $allservers = $tcs | ?{$_.name -match $_settings.servers -and $_.role -eq $_settings.role} | sort Name
        if($range) { $allservers = $allservers | ?{$_.name -like "*$range" } }
        Write-Verbose "Found $($allservers.count) TCS servers across all environments"       
        if($stack) { foreach($_s in $stack) { $destinations += ($allservers | ?{$_.stack -eq "$_s"} | select -ExpandProperty Name | sort) }
        } elseif($datacenter) { foreach($_d in $datacenter) { $destinations += ($allservers | ?{$_.datacenter -eq "$_d"} | select -ExpandProperty Name | sort) }  }
        else { Write-Host "You must specify a -stack or -datacenter"; Exit }
    } elseif($PSCmdlet.ParameterSetName -eq "Servers") {
        if($servers.EndsWith(".txt")) { $destinations = gc $servers }
    }
    if($destinations.count -eq 0) { Write-Host "No destinations found. Ask Al how to use me."; Exit }
    return $destinations
}

function createJobs($_settings,$_servers) {
    $jobs = @()
    foreach($_server in $_servers) { $jobs += "\\" + $_server + "\" + $_settings.path }
    return $jobs
}

function askConfirmation($_settings,$_jobs) {
    Clear-Host
    Write-Host "Service:`t$service"
    Write-Host "Source:`t`t$source"
    Write-Host "Destinations:`t$($_jobs.count)"
    if($datacenter) { Write-Host "Datacenter:`t$datacenter"
    } elseif($stack) { Write-Host "Stack:`t`t$($stack.ToUpper())" }
    if($range) { Write-Host "Range:`t`t$range" }
    Write-Host "Threads:`t$threads"
    Write-Host "source, destination, destinations, deploy, validate, validate full, exit"
    $option = Read-Host 
    switch -regex ($option) {
        "source$" { gci $source -recurse | Format-Table @{n="Filename";e={$_.FullName};width=85},@{n="SizeKB";e={"{0:N2}" -f ($_.length/1kb)};width=10},LastWriteTime; Pause; askConfirmation $_settings $_jobs }
        "destination$" { gci $_jobs[0] -recurse | Format-Table @{n="Filename";e={$_.FullName};width=85},@{n="SizeKB";e={"{0:N2}" -f ($_.length/1kb)};width=10},LastWriteTime; Pause; askConfirmation $_settings $_jobs }
        "destinations$" { $_jobs; Pause; askConfirmation $_settings $_jobs }
        "deploy$" { runJobsRun $_settings $_jobs; Pause; askConfirmation $_settings $_jobs }
        "validate$" { doValidation $_settings $_jobs; Pause; askConfirmation $_settings $_jobs }
        "validate full$" { doValidation $_settings $_jobs $true; Pause; askConfirmation $_settings $_jobs }
        "exit$" { Exit }
        default { askConfirmation $_settings $_jobs }
    }
}

function doPush($_source,$_destination) { 
    $name = "robocopy.exe $_source $_destination /E /R:5 /W:2"
    Write-Host "Starting job: $name" -ForegroundColor Green
    Start-Job -name $name -ScriptBlock {param($_s,$_d) robocopy.exe $_s $_d /E /R:5 } -ArgumentList $_source,$_destination | Out-Null 
}

function runJobsRun($_settings,$_jobs) {
    $todo = $_jobs
    sendEmail $_settings $_jobs
    while($todo.count -gt 0) {
        $i++
        $randomjob = $todo | Get-Random
        $todo = $todo | ?{$_ -notlike $randomjob}
        $running = @(Get-Job | Where-Object { $_.State -eq 'Running' })
        if($running.count -lt $threads) {
            doPush $source $randomjob
            Write-Progress -Activity "Deploying $service files [$i/$($_jobs.count)]" -Status "$randomjob" -PercentComplete (($i/$_jobs.count)*100)
        } else {
            while($running.count -ge $threads) {
                $oldest = $running | sort PSBeginTime
                Write-Host "Waiting for job to finish. Oldest job: $($oldest[0].name)" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                $running = @(Get-Job | Where-Object { $_.State -eq 'Running' })
            }
            doPush $source $randomjob
            Write-Progress -Activity "Deploying $service code [$i/$($_jobs.count)]" -Status "$randomjob" -PercentComplete (($i/$_jobs.count)*100)
        }
    }

    if((@(Get-Job | Where-Object { $_.State -eq 'Running' })).Count -gt 0) {
        while((@(Get-Job | Where-Object { $_.State -eq 'Running' })).Count -gt 0) {
            Write-Host "Waiting for all jobs to finish" -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
    }
}

function sendEmail($_settings,$_jobs) {
    $global:smtpserver = "smtp.domain.local"
    $msg = new-object Net.Mail.MailMessage
    $smtp = new-object Net.Mail.SmtpClient($global:smtpserver)
    $username = [environment]::username
    $domain = [environment]::UserDomainName
    $datetime = (Get-Date -format yyyy-MM-dd_HHmmss)
    $sourcetemp = "$psscriptroot\$($service)_deployment_$($datetime).csv"
    $cleandst = ""
    if($stack) { 
        foreach ($_s in $stack) { $cleandst += "$_s " }
    }elseif($datacenter) { $cleandst += "$datacenter" }

    gci $source -Recurse | select -First 100 FullName,@{n="SizeKB";e={"{0:N2}" -f ($_.length/1kb)}},LastWriteTime,Mode | sort LastWriteTime -Descending | Export-Csv $sourcetemp -NoTypeInformation
    if(Test-Path $sourcetemp) { $att = new-object Net.Mail.Attachment($sourcetemp); $msg.Attachments.Add($att) }
    
    $msg.From = "admin@domain.local"
    $msg.To.Add("InfraChange@intranet.domain.local")
    $msg.Bcc.Add("admin@domain.local")
    $msg.subject = "Deployment started for $($_settings.service) to $cleandst"
    $msg.body += "Server: $($env:computername)`r`n"
    $msg.body += "Service: $($_settings.service)`r`n"
    $msg.body += "Source: $($source)`r`n"
    if($stack) { $msg.body += "Stack: "; foreach ($_s in $stack) { $msg.body += "$_s " }; $msg.body += "`r`n"; }
    if($datacenter) { $msg.body += "Datacenter: $datacenter`r`n"; }
    if($role) { $msg.body += "Role: $role`r`n"; }
    $msg.body += "Threads: $($threads)`r`n`r`n"
    $msg.body += "Destinations:`r`n"
    foreach($_j in $_jobs) { $msg.body += "$_j`r`n" }
    $msg.body += "`r`n"
    $msg.body += "Username: $domain\$username"
    $smtp.Send($msg)
    
    if(Test-Path $sourcetemp) { $att.Dispose(); Remove-Item $sourcetemp }
}

function doValidation($_settings,$_jobs,$full) {
    $sourcehashes = @()
    $sourcefiles = gci -File -Path $source -Recurse
    foreach($sourcefile in $sourcefiles) {
        $obj = getHash $sourcefile.FullName
        $sourcehashes += $obj
    }
    Clear-Host
    foreach($job in $_jobs) {
        $bad = 0
        Write-Host "Working on $job"
        foreach($sourcehash in $sourcehashes) {
            $filename = $sourcehash.file.substring($source.Length+1)
            $temphash = getHash "$job\$filename"
            if($sourcehash.hash -ne $temphash.hash) {
                if($temphash.hash -eq "file not found") { Write-host "$($filename): $($sourcehash.hash) - File not found" -ForegroundColor Red
                } else { Write-host "$($filename): $($sourcehash.hash) does not match $($temphash.hash)" -ForegroundColor Red }
                $bad++
            } else { if($full) { Write-Host "$($filename): MD5Sums match" -ForegroundColor Green } }
        }
        if($bad -eq 0) { Write-Host "All files match" -ForegroundColor Green }
        Write-Host ""
    }
}

function getHash($filepath) {
    try {
        $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
        $hash = [System.BitConverter]::ToString($md5.ComputeHash([System.IO.File]::ReadAllBytes($filepath)))
    }
    catch { $hash = "file not found" }
    $obj = New-Object PSObject -Property @{
        File = $filepath
        Hash = $hash
    }
    return $obj
}

function getSource($source) {
    if(!$source) { $source = "G:\CodePush\$service" }
    return $source
}

$settings = loadSettings
$servers = getServers $settings
$source = getSource $source
$jobs = createJobs $settings $servers
askConfirmation $settings $jobs