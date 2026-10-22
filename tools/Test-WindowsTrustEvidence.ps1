<#
.SYNOPSIS
Runs read-only Windows trust diagnostics and checks the preserved evidence.
.PARAMETER OutputPath
New private JSON output path.
.EXAMPLE
./Test-WindowsTrustEvidence.ps1 -OutputPath C:/Windows/Temp/windows-trust.json
.NOTES
Acceptance of a compromised certificate is reported as a finding, not hidden.
#>
[CmdletBinding()]
param ([Parameter(Mandatory)] [string]$OutputPath)
$ErrorActionPreference = 'Stop'
$result = & (Join-Path $PSScriptRoot 'Get-WindowsTrustEvidence.ps1') -OutputPath $OutputPath
$saved = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if ($saved.started_at -ne $result.started_at) { throw 'Evidence does not match this run.' }
if ((Get-FileHash $OutputPath -Algorithm SHA256).Hash -ne $result.sha256) { throw 'Evidence hash changed.' }
if ($saved.decisions.Count -ne $saved.manifest_count) { throw 'Not all certificate paths were tested.' }
Write-Output "PASS: Windows trust observations saved to $OutputPath"
Write-Output "SHA256: $($result.sha256)"
foreach ($row in $saved.decisions) {
    if ($row.accepted_no_revocation) { Write-Warning "Accepted without revocation: $($row.name), issuer $($row.issuer)" }
}
