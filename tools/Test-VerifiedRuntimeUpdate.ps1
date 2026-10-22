<#
.SYNOPSIS
Applies one verified runtime security update and checks its installed TLS path.
.PARAMETER Target
Node or Python. Does not terminate running applications or reboot.
.PARAMETER ArtifactDirectory
Previously verified official patch directory.
.PARAMETER Directory
New private evidence directory for installation and trust receipts.
.EXAMPLE
./Test-VerifiedRuntimeUpdate.ps1 -Target Python -ArtifactDirectory C:/Windows/Temp/patches -Directory C:/Windows/Temp/python-update
.NOTES
Existing long-running processes may retain old code. Client relaunch is separate.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [ValidateSet('Node', 'Python')] [string]$Target,
    [Parameter(Mandatory)] [string]$ArtifactDirectory,
    [Parameter(Mandatory)] [string]$Directory
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Directory) { throw 'Choose a new evidence directory.' }
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetFullPath($Directory))
$installPath = Join-Path $Directory 'install.json'
& (Join-Path $PSScriptRoot 'Install-VerifiedRuntimeUpdate.ps1') -Target $Target -ArtifactDirectory $ArtifactDirectory -OutputPath $installPath
$trustPath = Join-Path $Directory 'trust.json'
if ($Target -eq 'Node') {
    & (Join-Path $PSScriptRoot 'Test-NodeTrustEvidence.ps1') -NodePath 'C:/Program Files/nodejs/node.exe' -OutputPath $trustPath
    $trust = (Get-Content -LiteralPath $trustPath -Raw | ConvertFrom-Json -AsHashtable).receipt
    if ($trust.node_version -ne '26.12.1') { throw 'Installed Node is not the fixed version; check installer/pending restart evidence.' }
} else {
    . (Join-Path $PSScriptRoot 'Invoke-SecurityDiagnosticProcess.ps1')
    $python = Join-Path $env:LOCALAPPDATA 'Programs/Python/Python312/python.exe'
    $result = Invoke-SecurityDiagnosticProcess $python @('-I', '-S', (Join-Path $PSScriptRoot 'check-python-trust.py')) -TimeoutSeconds 180
    if ($result.exit_code) { throw 'Python installed-client TLS check failed.' }
    $trust = $result.stdout | ConvertFrom-Json -AsHashtable
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($trustPath), ($trust | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    if ($trust.pip_version -ne '26.2.2' -or $trust.certifi_version -ne '2026.10.19') { throw 'Python packages are not the fixed versions.' }
}
$rejected = @($trust.checks | Where-Object { $_.host -ne 'rustsec.org' -and $_.classification -eq 'certificate_rejected' })
if (-not $trust.positive_control_passed -or $rejected.Count -ne 14) { throw 'Installed runtime did not pass valid control plus fourteen incident rejections.' }
Write-Output "PASS: $Target security update installed; new process passed valid control and rejected fourteen incident chains. Existing applications were not restarted."
Write-Output "Install receipt SHA256: $((Get-FileHash -LiteralPath $installPath -Algorithm SHA256).Hash)"
Write-Output "Trust receipt SHA256: $((Get-FileHash -LiteralPath $trustPath -Algorithm SHA256).Hash)"
