<#
.SYNOPSIS
Collects Windows update, ESU license metadata and pending-restart observations.
.DESCRIPTION
Reads selected OS, policy, service and disk metadata, public ESU license status,
Windows Update history and the updates offered by the configured update service.
The search can contact the update service and update its search cache. Never
downloads/installs updates, accepts EULAs, activates licenses or restarts Windows.
.PARAMETER OutputPath
New private JSON evidence path outside public Git.
.EXAMPLE
./Get-WindowsUpdateReadiness.ps1 -OutputPath C:/Windows/Temp/windows-update-readiness.json
.NOTES
PowerShell 7.5+ on Windows. Missing ESU product rows do not establish consumer enrollment.
#>
[CmdletBinding()]
param ([Parameter(Mandatory)] [string]$OutputPath)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows is required.' }
if (Test-Path -LiteralPath $OutputPath) { throw 'Choose a new evidence path.' }
$observations = [ordered]@{}
$startedAt = [DateTime]::UtcNow.ToString('o')
function Save-ReadinessObservation {
    param ([string]$Name, [scriptblock]$Collect)
    $started = [DateTime]::UtcNow.ToString('o')
    try {
        $observations[$Name] = @{ status = 'observed'; started_at = $started; data = @(& $Collect) }
    } catch {
        $observations[$Name] = @{ status = 'unverified'; started_at = $started
            error_type = $_.Exception.GetType().FullName; error_id = $_.FullyQualifiedErrorId
            hresult = ('0x{0:X8}' -f $_.Exception.HResult) }
    }
}
Save-ReadinessObservation 'os' {
    Get-CimInstance Win32_OperatingSystem -Property Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime |
        Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime
    Get-ItemProperty 'HKLM:/SOFTWARE/Microsoft/Windows NT/CurrentVersion' -Name DisplayVersion, UBR |
        Select-Object DisplayVersion, UBR
}
Save-ReadinessObservation 'installed_updates' { Get-HotFix | Select-Object HotFixID, Description, InstalledOn }
Save-ReadinessObservation 'esu_license_rows' {
    $filter = "ID='f520e45e-7413-4a34-a497-d2765967d094' OR ID='1043add5-23b1-4afb-9a0f-64343c8f3f8d' OR ID='83d49986-add3-41d7-ba33-87c7bfb5c0fb'"
    Get-CimInstance SoftwareLicensingProduct -Filter $filter -Property Name, Description, LicenseStatus |
        Select-Object Name, Description, LicenseStatus
}
Save-ReadinessObservation 'services' {
    Get-CimInstance Win32_Service -Filter "Name='wuauserv' OR Name='BITS' OR Name='UsoSvc' OR Name='WaaSMedicSvc' OR Name='sppsvc'" -Property Name, State, StartMode |
        Select-Object Name, State, StartMode
}
Save-ReadinessObservation 'system_disk' {
    Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -Property DeviceID, FreeSpace, Size, FileSystem |
        Select-Object DeviceID, FreeSpace, Size, FileSystem
}
Save-ReadinessObservation 'pending_restart' {
    $systemInfo = New-Object -ComObject 'Microsoft.Update.SystemInfo'
    [pscustomobject]@{
        windows_update_reboot_required = $systemInfo.RebootRequired
        servicing_reboot_pending = Test-Path 'HKLM:/SOFTWARE/Microsoft/Windows/CurrentVersion/Component Based Servicing/RebootPending'
        update_reboot_registry_present = Test-Path 'HKLM:/SOFTWARE/Microsoft/Windows/CurrentVersion/WindowsUpdate/Auto Update/RebootRequired'
    }
}
Save-ReadinessObservation 'update_policy' {
    foreach ($path in @('HKLM:/SOFTWARE/Policies/Microsoft/Windows/WindowsUpdate',
        'HKLM:/SOFTWARE/Policies/Microsoft/Windows/WindowsUpdate/AU')) {
        if (Test-Path $path) {
            $key = Get-Item $path
            foreach ($name in @('DisableWindowsUpdateAccess', 'DoNotConnectToWindowsUpdateInternetLocations',
                'TargetReleaseVersion', 'TargetReleaseVersionInfo', 'NoAutoUpdate', 'AUOptions', 'UseWUServer')) {
                $value = $key.GetValue($name)
                if ($null -ne $value) { [pscustomobject]@{ path = $path; name = $name; value = $value } }
            }
        }
    }
}
$session = New-Object -ComObject 'Microsoft.Update.Session'
$session.ClientApplicationID = 'Read-only security readiness inventory'
$searcher = $session.CreateUpdateSearcher()
Save-ReadinessObservation 'update_history' {
    $count = [Math]::Min(50, $searcher.GetTotalHistoryCount())
    if ($count -gt 0) {
        foreach ($entry in $searcher.QueryHistory(0, $count)) {
            [pscustomobject]@{ date = $entry.Date; title = $entry.Title
                operation = [int]$entry.Operation; result_code = [int]$entry.ResultCode
                hresult = ('0x{0:X8}' -f $entry.HResult) }
        }
    }
}
function Get-UpdateSearchEvidence {
    param ([string]$Criteria)
    $result = $searcher.Search($Criteria)
    $updates = foreach ($update in $result.Updates) {
        [pscustomobject]@{
            title = $update.Title; update_id = $update.Identity.UpdateID
            revision = $update.Identity.RevisionNumber; kb = @($update.KBArticleIDs)
            severity = $update.MsrcSeverity; categories = @($update.Categories | ForEach-Object Name)
            downloaded = $update.IsDownloaded; eula_accepted = $update.EulaAccepted
            max_download_bytes = $update.MaxDownloadSize
            reboot_behavior = [int]$update.InstallationBehavior.RebootBehavior
        }
    }
    [pscustomobject]@{ result_code = [int]$result.ResultCode; updates = @($updates)
        server_selection = [int]$searcher.ServerSelection; online = $searcher.Online }
}
Save-ReadinessObservation 'offered_updates' { Get-UpdateSearchEvidence "IsInstalled=0 and Type='Software' and IsHidden=0" }
Save-ReadinessObservation 'hidden_updates' { Get-UpdateSearchEvidence "IsInstalled=0 and Type='Software' and IsHidden=1" }
$report = [ordered]@{
    started_at = $startedAt; completed_at = [DateTime]::UtcNow.ToString('o')
    scope = 'Read-only readiness and configured-service update search. Does not establish consumer ESU enrollment, full patch compliance or authorization to reboot. No update installation, license activation or policy changes.'
    observations = $observations
}
$resolved = [System.IO.Path]::GetFullPath($OutputPath)
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolved))
$json = $report | ConvertTo-Json -Depth 15 -WarningAction Stop
$stream = [System.IO.File]::Open($resolved, [System.IO.FileMode]::CreateNew)
try {
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }
[pscustomobject]@{ started_at = $startedAt; sha256 = (Get-FileHash $resolved -Algorithm SHA256).Hash }
