<#
.SYNOPSIS
Records Windows event retention and standard archived-event-log availability.
.DESCRIPTION
Reads selected live-log metadata and oldest/newest event timestamps. Lists only
standard Archive-*.evtx files, with their hashes and timestamp bounds. Never
renders event messages, reads script payloads or changes logging settings.
Archive availability does not mean its events have been reviewed.
.PARAMETER OutputPath
New private JSON evidence path outside public Git.
.PARAMETER Days
Requested investigation window in days.
.EXAMPLE
./Get-WindowsLogCoverage.ps1 -OutputPath C:/Windows/Temp/log-coverage.json -Days 30
.NOTES
Requires Windows and PowerShell 7.5+. Security-log access requires elevation.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$OutputPath,
    [ValidateRange(1, 90)] [int]$Days = 30
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows is required.' }
if (Test-Path -LiteralPath $OutputPath) { throw 'Choose a new evidence path.' }
$now = [DateTime]::UtcNow
$windowStart = $now.AddDays(-$Days)
$logNames = @('Security', 'System', 'Application',
    'Microsoft-Windows-Windows Defender/Operational',
    'Microsoft-Windows-TaskScheduler/Operational',
    'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational',
    'Microsoft-Windows-PowerShell/Operational', 'Windows PowerShell')
$liveLogs = foreach ($name in $logNames) {
    try {
        $config = Get-WinEvent -ListLog $name
        $oldest = $null
        $newest = $null
        if ($config.RecordCount -gt 0) {
            $oldest = (Get-WinEvent -LogName $name -Oldest -MaxEvents 1).TimeCreated.ToUniversalTime()
            $newest = (Get-WinEvent -LogName $name -MaxEvents 1).TimeCreated.ToUniversalTime()
        }
        [pscustomobject]@{
            name = $name; status = 'observed'; enabled = $config.IsEnabled
            mode = [string]$config.LogMode; max_bytes = $config.MaximumSizeInBytes
            records = $config.RecordCount; log_file = $config.LogFilePath
            oldest_utc = if ($oldest) { $oldest.ToString('o') } else { $null }
            newest_utc = if ($newest) { $newest.ToString('o') } else { $null }
            starts_before_requested_window = ($null -ne $oldest -and $oldest -le $windowStart)
            scope = 'Retention bounds only; not proof of uninterrupted auditing or reviewed events.'
        }
    } catch {
        [pscustomobject]@{ name = $name; status = 'unverified'; error_id = $_.FullyQualifiedErrorId }
    }
}
$archiveDirectory = Join-Path $env:windir 'System32/winevt/Logs'
$archiveStatus = 'observed'
$archiveError = $null
$archives = @()
try {
    $archives = @(foreach ($file in (Get-ChildItem -LiteralPath $archiveDirectory -Filter 'Archive-*.evtx' -File)) {
        try {
            $oldest = Get-WinEvent -Path $file.FullName -Oldest -MaxEvents 1
            $newest = Get-WinEvent -Path $file.FullName -MaxEvents 1
            [pscustomobject]@{
                path = $file.FullName; bytes = $file.Length; written_utc = $file.LastWriteTimeUtc.ToString('o')
                sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
                oldest_utc = $oldest.TimeCreated.ToUniversalTime().ToString('o')
                newest_utc = $newest.TimeCreated.ToUniversalTime().ToString('o')
                overlaps_requested_window = ($newest.TimeCreated.ToUniversalTime() -ge $windowStart)
                status = 'observed'; events_reviewed = $false
            }
        } catch {
            [pscustomobject]@{ path = $file.FullName; status = 'unverified'; error_id = $_.FullyQualifiedErrorId }
        }
    })
} catch { $archiveStatus = 'unverified'; $archiveError = $_.FullyQualifiedErrorId }
$shadowStatus = 'observed'
$shadowError = $null
$shadows = @()
try {
    $shadows = @(Get-CimInstance Win32_ShadowCopy -Property InstallDate, DeviceObject, VolumeName |
        Select-Object InstallDate, DeviceObject, VolumeName)
} catch { $shadowStatus = 'unverified'; $shadowError = $_.FullyQualifiedErrorId }
$report = [ordered]@{
    observed_at = $now.ToString('o'); requested_start_utc = $windowStart.ToString('o')
    requested_end_utc = $now.ToString('o'); live_logs = @($liveLogs)
    archive_directory = $archiveDirectory; archive_status = $archiveStatus
    archive_error = $archiveError; archives = $archives
    shadow_copy_status = $shadowStatus; shadow_copy_error = $shadowError; shadow_copies = $shadows
    scope = 'Only standard Windows event archive directory checked. Other exports/backups and NAS/router logs require separate evidence.'
}
$resolved = [System.IO.Path]::GetFullPath($OutputPath)
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolved))
$json = $report | ConvertTo-Json -Depth 10 -WarningAction Stop
$stream = [System.IO.File]::Open($resolved, [System.IO.FileMode]::CreateNew)
try {
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }
[pscustomobject]@{ observed_at = $report.observed_at; sha256 = (Get-FileHash $resolved -Algorithm SHA256).Hash }
