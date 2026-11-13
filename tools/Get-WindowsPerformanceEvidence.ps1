<#
.SYNOPSIS
Collects a short, read-only desktop performance sample.
.DESCRIPTION
Samples CPU, memory, disk and GPU counters and ranks processes by CPU used
during that interval. Never collects command lines, environment variables,
window titles, credentials or file contents. Does not change system settings.
.PARAMETER Samples
Number of counter samples, two seconds apart.
.EXAMPLE
pwsh -NoProfile -File ./tools/Get-WindowsPerformanceEvidence.ps1 -Samples 6
.NOTES
Windows and PowerShell 7 are required. Unavailable sections report errors.
#>
[CmdletBinding()]
param ([ValidateRange(2, 15)] [int]$Samples = 6)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows is required.' }
$issues = [Collections.Generic.List[object]]::new()
$started = [DateTime]::UtcNow
$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$logical = [int]$computer.NumberOfLogicalProcessors
$before = @{}
foreach ($process in Get-Process) {
    try { $before[$process.Id] = @{ Cpu = $process.TotalProcessorTime.TotalSeconds; Started = $process.StartTime.ToUniversalTime().Ticks } }
    catch { continue }
}
$timer = [Diagnostics.Stopwatch]::StartNew()
$paths = @(
    '\Processor(_Total)\% Processor Time',
    '\Processor(_Total)\% Privileged Time',
    '\Processor(_Total)\% DPC Time',
    '\Processor(_Total)\% Interrupt Time',
    '\System\Processor Queue Length',
    '\Memory\Available MBytes',
    '\Memory\Committed Bytes',
    '\Memory\Commit Limit',
    '\Memory\Pages Input/sec',
    '\Memory\Page Reads/sec',
    '\PhysicalDisk(*)\Avg. Disk sec/Transfer',
    '\PhysicalDisk(*)\Current Disk Queue Length',
    '\PhysicalDisk(*)\Disk Bytes/sec',
    '\PhysicalDisk(*)\% Idle Time'
)
$counterErrors = @()
$frames = @(Get-Counter -Counter $paths -SampleInterval 2 -MaxSamples $Samples -ErrorAction SilentlyContinue -ErrorVariable counterErrors)
foreach ($errorRecord in $counterErrors) { $issues.Add(@{ Section = 'counters'; ErrorId = $errorRecord.FullyQualifiedErrorId }) }
$elapsed = $timer.Elapsed.TotalSeconds
$processes = foreach ($process in Get-Process) {
    try {
        $old = $before[$process.Id]
        $cpu = $null
        if ($old -and $old.Started -eq $process.StartTime.ToUniversalTime().Ticks) {
            $cpu = [Math]::Round(100 * ($process.TotalProcessorTime.TotalSeconds - $old.Cpu) / $elapsed / $logical, 2)
        }
        [pscustomobject]@{
            Id = $process.Id; Name = $process.ProcessName; CpuPercent = $cpu
            PrivateMiB = [Math]::Round($process.PrivateMemorySize64 / 1MB, 1)
            WorkingMiB = [Math]::Round($process.WorkingSet64 / 1MB, 1)
            Handles = $process.HandleCount; Threads = $process.Threads.Count
        }
    } catch { continue }
}
$counters = foreach ($group in ($frames.CounterSamples | Where-Object Status -eq 0 | Group-Object Path)) {
    $measure = $group.Group | Measure-Object CookedValue -Average -Maximum -Minimum
    [pscustomobject]@{ Counter = $group.Name; Average = [Math]::Round($measure.Average, 4)
        Maximum = [Math]::Round($measure.Maximum, 4); Minimum = [Math]::Round($measure.Minimum, 4) }
}
$gpu = @()
try {
    $gpuFrames = @(Get-Counter '\GPU Engine(*)\Utilization Percentage' -SampleInterval 1 -MaxSamples 2 -ErrorAction Stop)
    $gpu = @($gpuFrames.CounterSamples | Where-Object { $_.Status -eq 0 -and $_.CookedValue -gt 1 } |
        Sort-Object CookedValue -Descending | Select-Object -First 12 |
        ForEach-Object { [pscustomobject]@{ Engine = $_.InstanceName; Percent = [Math]::Round($_.CookedValue, 1) } })
} catch { $issues.Add(@{ Section = 'gpu'; ErrorId = $_.FullyQualifiedErrorId }) }
$drives = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    [pscustomobject]@{ Drive = $_.DeviceID; SizeGiB = [Math]::Round($_.Size / 1GB, 1)
        FreeGiB = [Math]::Round($_.FreeSpace / 1GB, 1) }
})
$diskHealth = @()
try { $diskHealth = @(Get-PhysicalDisk | Select-Object FriendlyName, HealthStatus, OperationalStatus, MediaType) }
catch { $issues.Add(@{ Section = 'disk_health'; ErrorId = $_.FullyQualifiedErrorId }) }
$events = @()
try {
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddHours(-4)
        Id = @(7, 17, 18, 19, 51, 129, 153, 2004, 4101) } -MaxEvents 25 -ErrorAction Stop |
        Select-Object TimeCreated, Id, ProviderName, LevelDisplayName)
} catch {
    if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
        $issues.Add(@{ Section = 'system_events'; ErrorId = $_.FullyQualifiedErrorId })
    }
}
$powerScheme = @(& powercfg.exe /getactivescheme)
[pscustomobject]@{
    StartedUtc = $started.ToString('o'); SampleSeconds = [Math]::Round($elapsed, 1)
    LogicalProcessors = $logical; PhysicalMemoryGiB = [Math]::Round($computer.TotalPhysicalMemory / 1GB, 1)
    FreeMemoryGiB = [Math]::Round($os.FreePhysicalMemory / 1MB, 1)
    UptimeHours = [Math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
    PowerScheme = $powerScheme; Counters = @($counters)
    TopCpu = @($processes | Sort-Object CpuPercent -Descending | Select-Object -First 15)
    TopPrivateMemory = @($processes | Sort-Object PrivateMiB -Descending | Select-Object -First 12)
    ProcessGroups = @($processes | Group-Object Name | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Count = $_.Count
            CpuPercent = [Math]::Round(($_.Group | Measure-Object CpuPercent -Sum).Sum, 2)
            PrivateMiB = [Math]::Round(($_.Group | Measure-Object PrivateMiB -Sum).Sum, 1) }
    } | Sort-Object CpuPercent -Descending | Select-Object -First 15)
    Gpu = $gpu; Drives = $drives; DiskHealth = $diskHealth; RecentSystemEvents = $events; Issues = @($issues.ToArray())
} | ConvertTo-Json -Depth 6
