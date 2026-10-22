<#
.SYNOPSIS
Preserves selected read-only Windows security observations in a private JSON file.
.DESCRIPTION
Collects bounded structured events and account, startup, process and network
metadata. Never reads command lines, script bodies, credentials or browser data.
Unavailable sections remain unverified. This is triage, not a clean bill of health.
.PARAMETER OutputPath
Private evidence file outside public Git. Existing files are never overwritten.
.PARAMETER Days
Requested event lookback, limited by log retention and a per-log event cap.
.EXAMPLE
./Get-WindowsSecurityEvidence.ps1 -OutputPath C:/Windows/Temp/desktop-security.json
.NOTES
Requires Windows and PowerShell 7.5+. Some observations require administrator access.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$OutputPath,
    [ValidateRange(1, 90)] [int]$Days = 30
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows is required.' }
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $resolvedOutput) { throw 'Choose a new evidence path; previous evidence is preserved.' }
$startedAt = [DateTime]::UtcNow.ToString('o')
$observations = [ordered]@{}

function Save-Observation {
    param ([string]$Name, [scriptblock]$Collect)
    $started = [DateTime]::UtcNow.ToString('o')
    try {
        $data = @(& $Collect)
        $observations[$Name] = @{ status = 'observed'; started_at = $started; data = $data }
    } catch {
        # Do not save raw exceptions, which can include unexpected provider data.
        $observations[$Name] = @{
            status = 'unverified'; started_at = $started
            error_type = $_.Exception.GetType().FullName; error_id = $_.FullyQualifiedErrorId
        }
    }
}

# Retain structured allowlisted fields only, never rendered messages or script text.
$eventFields = @('TargetUserName', 'TargetDomainName', 'SubjectUserName', 'SubjectDomainName',
    'IpAddress', 'IpPort', 'LogonType', 'AuthenticationPackageName', 'Status', 'SubStatus',
    'MemberName', 'MemberSid', 'TaskName', 'UserName', 'ServiceName', 'ServiceType',
    'StartType', 'AccountName', 'Threat Name', 'Detection User', 'Action Name')
$eventQueries = [ordered]@{
    security_events = @{ LogName = 'Security'; Id = @(1102, 4719, 4720, 4722, 4726, 4732, 4624, 4625, 4648, 4672) }
    defender_events = @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = @(1116, 1117, 1118, 1119, 5001, 5007) }
    service_events = @{ LogName = 'System'; Id = @(104, 7045) }
    task_events = @{ LogName = 'Microsoft-Windows-TaskScheduler/Operational'; Id = @(106, 140, 141) }
    rdp_events = @{ LogName = 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'; Id = @(1149) }
}
foreach ($entry in $eventQueries.GetEnumerator()) {
    $query = $entry.Value
    $query.StartTime = (Get-Date).AddDays(-$Days)
    Save-Observation -Name $entry.Key -Collect {
        $log = Get-WinEvent -ListLog $query.LogName
        $oldest = if ($log.RecordCount -gt 0) { Get-WinEvent -LogName $query.LogName -Oldest -MaxEvents 1 }
        $events = @()
        try { $events = @(Get-WinEvent -FilterHashtable $query -MaxEvents 2000) }
        catch {
            if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
        }
        $rows = foreach ($event in $events) {
            [xml]$xml = $event.ToXml()
            $fields = [ordered]@{}
            foreach ($datum in $xml.Event.EventData.Data) {
                if ($datum.Name -in $eventFields) { $fields[$datum.Name] = [string]$datum.'#text' }
            }
            [pscustomobject]@{
                time_utc = $event.TimeCreated.ToUniversalTime().ToString('o')
                id = $event.Id; record_id = $event.RecordId; fields = $fields
            }
        }
        [pscustomobject]@{
            log_name = $query.LogName; enabled = $log.IsEnabled; total_records = $log.RecordCount
            oldest_available_utc = if ($oldest) { $oldest.TimeCreated.ToUniversalTime().ToString('o') } else { $null }
            requested_start_utc = $query.StartTime.ToUniversalTime().ToString('o')
            cap = 2000; possibly_truncated = ($events.Count -eq 2000); events = @($rows)
        }
    }
}
Save-Observation 'os' {
    Get-CimInstance Win32_OperatingSystem -Property Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime |
        Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime
    Get-ItemProperty 'HKLM:/SOFTWARE/Microsoft/Windows NT/CurrentVersion' -Name DisplayVersion, UBR |
        Select-Object DisplayVersion, UBR
}
Save-Observation 'updates' { Get-HotFix | Select-Object HotFixID, Description, InstalledOn }
Save-Observation 'defender_status' {
    Get-MpComputerStatus | Select-Object AMServiceEnabled, AntivirusEnabled, AntispywareEnabled,
        RealTimeProtectionEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, NISEnabled,
        AntivirusSignatureVersion, AntivirusSignatureLastUpdated, QuickScanEndTime, FullScanEndTime,
        IsTamperProtected, DefenderSignaturesOutOfDate
}
Save-Observation 'defender_detections' {
    Get-MpThreatDetection | Select-Object ThreatID, InitialDetectionTime, LastThreatStatusChangeTime,
        ActionSuccess, ThreatStatusID, CurrentThreatExecutionStatusID, RemediationTime
}
Save-Observation 'defender_preferences' {
    Get-MpPreference | Select-Object DisableRealtimeMonitoring, DisableBehaviorMonitoring,
        DisableIOAVProtection, DisableScriptScanning, DisableIntrusionPreventionSystem
}
Save-Observation 'defender_policy' {
    foreach ($path in @('HKLM:/SOFTWARE/Policies/Microsoft/Windows Defender',
        'HKLM:/SOFTWARE/Policies/Microsoft/Windows Defender/Real-Time Protection')) {
        if (Test-Path $path) {
            $key = Get-Item $path
            foreach ($name in @('DisableAntiSpyware', 'DisableAntiVirus', 'DisableRealtimeMonitoring',
                'DisableBehaviorMonitoring', 'DisableIOAVProtection', 'DisableOnAccessProtection')) {
                $value = $key.GetValue($name)
                if ($null -ne $value) { [pscustomobject]@{ path = $path; name = $name; value = $value } }
            }
        }
    }
}
Save-Observation 'antivirus_products' {
    Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct -Property displayName, productState |
        Select-Object displayName, productState
}
Save-Observation 'local_users' {
    Get-LocalUser | Select-Object Name, Enabled, LastLogon, PasswordLastSet, PrincipalSource,
        @{ Name = 'SID'; Expression = { $_.SID.Value } }
}
Save-Observation 'administrators' {
    Get-LocalGroupMember -SID 'S-1-5-32-544' | Select-Object Name, ObjectClass, PrincipalSource,
        @{ Name = 'SID'; Expression = { $_.SID.Value } }
}
Save-Observation 'tasks' {
    Get-CimInstance -Namespace root/Microsoft/Windows/TaskScheduler -ClassName MSFT_ScheduledTask -Property TaskName, TaskPath, State |
        Select-Object TaskName, TaskPath, State
}
Save-Observation 'task_executables' {
    $scheduler = New-Object -ComObject 'Schedule.Service'
    $scheduler.Connect()
    function Get-TaskFolderEvidence {
        param ($Folder)
        try {
            foreach ($task in $Folder.GetTasks(1)) {
                try {
                    $actions = foreach ($action in $task.Definition.Actions) {
                        [pscustomobject]@{
                            type = $action.Type
                            executable = if ($action.Type -eq 0) { $action.Path } else { $null }
                        }
                    }
                    [pscustomobject]@{
                        path = $task.Path; enabled = $task.Enabled; state = $task.State
                        last_run = $task.LastRunTime; last_result = $task.LastTaskResult
                        actions = @($actions); status = 'observed'
                    }
                } catch {
                    [pscustomobject]@{ path = $task.Path; status = 'unverified'; error_type = $_.Exception.GetType().FullName }
                }
            }
            foreach ($folderChild in $Folder.GetFolders(0)) { Get-TaskFolderEvidence $folderChild }
        } catch {
            [pscustomobject]@{ folder = $Folder.Path; status = 'unverified'; error_type = $_.Exception.GetType().FullName }
        }
    }
    Get-TaskFolderEvidence ($scheduler.GetFolder('\'))
}
Save-Observation 'startup' {
    Get-CimInstance Win32_StartupCommand -Property Name, Location, User | Select-Object Name, Location, User
}
Save-Observation 'services' {
    Get-CimInstance Win32_Service -Property Name, DisplayName, State, StartMode, StartName |
        Select-Object Name, DisplayName, State, StartMode, StartName
}
Save-Observation 'wmi_persistence' {
    foreach ($class in @('__EventFilter', 'CommandLineEventConsumer', 'ActiveScriptEventConsumer', '__FilterToConsumerBinding')) {
        $properties = if ($class -eq '__FilterToConsumerBinding') { @('Filter', 'Consumer') } else { @('Name') }
        foreach ($item in (Get-CimInstance -Namespace root/subscription -ClassName $class -Property $properties)) {
            if ($class -eq '__FilterToConsumerBinding') {
                [pscustomobject]@{
                    class = $class; filter_name = $item.Filter.Name
                    consumer_class = $item.Consumer.CimSystemProperties.ClassName
                    consumer_name = $item.Consumer.Name
                }
            } else { [pscustomobject]@{ class = $class; name = $item.Name } }
        }
    }
}
Save-Observation 'processes' {
    Get-Process | Select-Object Id, ProcessName, Path, StartTime
}
Save-Observation 'project_executables' {
    foreach ($process in (Get-Process | Where-Object ProcessName -in @('onelog', 'onelog-mcp', 'jbot'))) {
        if (-not $process.Path) { throw 'Project executable path unavailable.' }
        $file = Get-Item -LiteralPath $process.Path
        $before = $file.LastWriteTimeUtc
        $hash = (Get-FileHash -LiteralPath $process.Path -Algorithm SHA256).Hash
        $file.Refresh()
        [pscustomobject]@{
            name = $process.ProcessName; pid = $process.Id; path = $process.Path
            process_started_utc = $process.StartTime.ToUniversalTime().ToString('o')
            file_written_utc = $file.LastWriteTimeUtc.ToString('o'); bytes = $file.Length
            sha256 = $hash; changed_during_hash = ($before -ne $file.LastWriteTimeUtc)
            scope = 'On-disk image hash; does not establish integrity of loaded process memory.'
        }
    }
}
Save-Observation 'project_log_metadata' {
    $appRoot = Join-Path $env:APPDATA 'onelog'
    if (Test-Path -LiteralPath $appRoot) {
        Get-ChildItem -LiteralPath $appRoot -Filter 'onelog.*.log' -File |
            Select-Object FullName, Length, CreationTimeUtc, LastWriteTimeUtc
    }
    $logRoot = Join-Path $appRoot 'logs'
    if (Test-Path -LiteralPath $logRoot) {
        Get-ChildItem -LiteralPath $logRoot -Filter '*.log' -File -Recurse |
            Select-Object FullName, Length, CreationTimeUtc, LastWriteTimeUtc
    }
}
Save-Observation 'running_executable_signatures' {
    $paths = Get-Process | Where-Object Path | Select-Object -ExpandProperty Path -Unique
    foreach ($path in $paths) {
        try {
            $signature = Get-AuthenticodeSignature -LiteralPath $path
            [pscustomobject]@{
                path = $path; status = [string]$signature.Status
                signer = $signature.SignerCertificate.Subject
                sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            }
        } catch {
            [pscustomobject]@{ path = $path; status = 'unverified'; error_type = $_.Exception.GetType().FullName }
        }
    }
}
Save-Observation 'tcp' {
    $names = @{}
    Get-Process | ForEach-Object { $names[$_.Id] = $_.ProcessName }
    Get-NetTCPConnection | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State,
        OwningProcess, @{ Name = 'process_name'; Expression = { $names[[int]$_.OwningProcess] } }
}
Save-Observation 'firewall' {
    Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
}
Save-Observation 'firewall_inbound_allow_rules' {
    foreach ($rule in (Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow)) {
        $application = $rule | Get-NetFirewallApplicationFilter
        $ports = $rule | Get-NetFirewallPortFilter
        $addresses = $rule | Get-NetFirewallAddressFilter
        [pscustomobject]@{
            name = $rule.Name; display_name = $rule.DisplayName; profile = [string]$rule.Profile
            program = $application.Program; protocol = [string]$ports.Protocol
            local_ports = $ports.LocalPort; remote_ports = $ports.RemotePort
            local_addresses = $addresses.LocalAddress; remote_addresses = $addresses.RemoteAddress
        }
    }
}
Save-Observation 'remote_desktop' {
    Get-ItemProperty 'HKLM:/SYSTEM/CurrentControlSet/Control/Terminal Server' -Name fDenyTSConnections |
        Select-Object fDenyTSConnections
}
Save-Observation 'installed_apps' {
    foreach ($root in @('HKLM:/SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall',
        'HKLM:/SOFTWARE/WOW6432Node/Microsoft/Windows/CurrentVersion/Uninstall',
        'HKCU:/SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall')) {
        if (Test-Path $root) {
            Get-ChildItem $root | ForEach-Object {
                $key = $_
                $row = [ordered]@{}
                foreach ($name in @('DisplayName', 'DisplayVersion', 'Publisher', 'InstallLocation')) {
                    $row[$name] = $key.GetValue($name)
                }
                if ($row.DisplayName) { [pscustomobject]$row }
            }
        }
    }
}
$report = [ordered]@{
    started_at = $startedAt; completed_at = [DateTime]::UtcNow.ToString('o')
    timezone = (Get-TimeZone).Id
    scope = 'Read-only triage metadata. Event retention, permissions and collection caps limit coverage. No absence-of-compromise claim.'
    observations = $observations
}
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolvedOutput))
$json = $report | ConvertTo-Json -Depth 20 -WarningAction Stop
$stream = [System.IO.File]::Open($resolvedOutput, [System.IO.FileMode]::CreateNew)
try {
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }
[pscustomobject]@{
    started_at = $startedAt; output_path = $resolvedOutput
    sha256 = (Get-FileHash -LiteralPath $resolvedOutput -Algorithm SHA256).Hash
    observations = $observations
}
