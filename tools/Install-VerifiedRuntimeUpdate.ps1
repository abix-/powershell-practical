<#
.SYNOPSIS
Installs the reviewed Node or Python security update from verified local artifacts.
.DESCRIPTION
Rechecks pinned hashes, saves before metadata and performs only the selected update.
Node uses elevation and MSI with reboot/Restart Manager shutdown disabled. Python
uses offline wheels and -I -S, skipping startup hooks, user paths and pip config.
No existing application is terminated or restarted. Run through the test wrapper.
.PARAMETER Target
Node or Python. Each operation has an independent evidence receipt.
.PARAMETER ArtifactDirectory
Previously verified patch directory with official artifacts.
.PARAMETER OutputPath
New private install receipt path; MSI log is kept beside it.
.EXAMPLE
./Install-VerifiedRuntimeUpdate.ps1 -Target Node -ArtifactDirectory C:/Windows/Temp/patches -OutputPath C:/Windows/Temp/node-install.json
.NOTES
Node MSI may request UAC. Exit3010 means restart required, not full remediation.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [ValidateSet('Node', 'Python')] [string]$Target,
    [Parameter(Mandatory)] [string]$ArtifactDirectory,
    [Parameter(Mandatory)] [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputPath) { throw 'Choose a new install evidence path.' }
$principal = [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent())
if ($Target -eq 'Node' -and -not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = @('-NoProfile', '-File', "`"$PSCommandPath`"", '-Target', $Target,
        '-ArtifactDirectory', "`"$ArtifactDirectory`"", '-OutputPath', "`"$OutputPath`"")
    $worker = Start-Process -FilePath (Get-Command pwsh.exe).Source -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru -Wait
    if ($worker.ExitCode -ne 0) { throw "Elevated update failed with exit $($worker.ExitCode); inspect saved receipt." }
    if (-not (Test-Path -LiteralPath $OutputPath)) { throw 'Elevated installer did not return evidence.' }
    return
}
. (Join-Path $PSScriptRoot 'Invoke-SecurityDiagnosticProcess.ps1')
$report = [ordered]@{ started_at = [DateTime]::UtcNow.ToString('o'); target = $Target; reboot_performed = $false; applications_restarted = $false }
try {
    if ($Target -eq 'Node') {
        $artifact = (Get-Item -LiteralPath (Join-Path $ArtifactDirectory 'node-v26.12.1-x64.msi')).FullName
        $expected = 'F32A2844504ED8D73449DDB480385F69CB436BC9409A89E2049AE83447078457'
        if ((Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash -ne $expected) { throw 'Node MSI hash mismatch.' }
        $signature = Get-AuthenticodeSignature -LiteralPath $artifact
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'OpenJS Foundation') { throw 'Node MSI signature mismatch.' }
        $installed = Get-Item -LiteralPath 'C:/Program Files/nodejs/node.exe'
        $report.before = @{ version = $installed.VersionInfo.FileVersion; path = $installed.FullName; sha256 = (Get-FileHash -LiteralPath $installed.FullName -Algorithm SHA256).Hash }
        $report.artifact_sha256 = $expected
        # Windows Installer's SYSTEM service cannot read the private evidence ACL.
        $installRoot = Join-Path 'C:/Windows/Temp' ('node-security-msi-' + [Guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($installRoot)
        $acl = Get-Acl -LiteralPath $installRoot
        $system = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')
        $rule = [System.Security.AccessControl.FileSystemAccessRule]::new($system, 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $installRoot -AclObject $acl
        $installCopy = Join-Path $installRoot 'node-v26.12.1-x64.msi'
        Copy-Item -LiteralPath $artifact -Destination $installCopy -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $installCopy -Algorithm SHA256).Hash -ne $expected) { throw 'Installer copy hash mismatch.' }
        $report.installer_copy = $installCopy
        $logPath = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetFullPath($OutputPath), '.msi.log')
        $report.msi_log = $logPath
        $arguments = @('/i', "`"$installCopy`"", '/qn', '/norestart', 'REBOOT=ReallySuppress', 'MSIRESTARTMANAGERCONTROL=Disable', '/log', "`"$logPath`"")
        $worker = Start-Process -FilePath 'C:/Windows/System32/msiexec.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
        $report.exit_code = $worker.ExitCode
        $report.restart_required = $worker.ExitCode -eq 3010
        if ($worker.ExitCode -notin @(0, 3010)) { throw "Node installer failed with exit $($worker.ExitCode)." }
    } else {
        $expected = @{
            'pip-26.2.2-py3-none-any.whl' = 'FD7F4DFA8190E014013B9F08F3E973F4E4C26FFD179A204895533A7254813A70'
            'certifi-2026.10.19-py3-none-any.whl' = '42D35340CC5B9BA78E818DDBFF0C5B1C2B779DE448A340FD1B989F5FA8670E1B'
        }
        foreach ($entry in $expected.GetEnumerator()) {
            if ((Get-FileHash -LiteralPath (Join-Path $ArtifactDirectory $entry.Key) -Algorithm SHA256).Hash -ne $entry.Value) { throw 'Python wheel hash mismatch.' }
        }
        $sitePackages = Join-Path $env:LOCALAPPDATA 'Programs/Python/Python312/Lib/site-packages'
        $report.before = @(foreach ($name in @('pip', 'certifi')) {
            foreach ($directory in Get-ChildItem -LiteralPath $sitePackages -Directory -Filter "$name-*.dist-info") {
                $metadata = Join-Path $directory.FullName 'METADATA'
                @{ name = $name; metadata_path = $metadata; version_headers = @(Get-Content -LiteralPath $metadata -TotalCount 12 | Where-Object { $_ -match '^(Name|Version):' }) }
            }
        })
        $python = Join-Path $env:LOCALAPPDATA 'Programs/Python/Python312/python.exe'
        $result = Invoke-SecurityDiagnosticProcess $python @('-I', '-S', (Join-Path $PSScriptRoot 'install-python-security.py'), $ArtifactDirectory) -TimeoutSeconds 180
        $report.exit_code = $result.exit_code
        $report.installer_stderr = $result.stderr
        if ($result.exit_code -ne 0) { throw 'Offline Python security update failed; inspect private stderr receipt.' }
    }
    $report.status = 'installer_completed'
} catch {
    $report.status = 'failed'
    $report.error_id = $_.FullyQualifiedErrorId
    throw
} finally {
    $report.completed_at = [DateTime]::UtcNow.ToString('o')
    $resolved = [System.IO.Path]::GetFullPath($OutputPath)
    $stream = [System.IO.File]::Open($resolved, [System.IO.FileMode]::CreateNew)
    try { $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($report | ConvertTo-Json -Depth 8)); $stream.Write($bytes, 0, $bytes.Length) }
    finally { $stream.Dispose() }
}
