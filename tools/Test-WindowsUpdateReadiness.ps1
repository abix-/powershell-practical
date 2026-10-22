<#
.SYNOPSIS
Runs read-only Windows update inventory and verifies preserved evidence.
.PARAMETER OutputPath
New private JSON output path.
.EXAMPLE
./Test-WindowsUpdateReadiness.ps1 -OutputPath C:/Windows/Temp/windows-update-readiness.json
.NOTES
An unavailable or partially successful update search is reported, never treated as up to date.
#>
[CmdletBinding()]
param ([Parameter(Mandatory)] [string]$OutputPath)
$ErrorActionPreference = 'Stop'
$result = & (Join-Path $PSScriptRoot 'Get-WindowsUpdateReadiness.ps1') @PSBoundParameters
$saved = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if ($saved.started_at -ne $result.started_at) { throw 'Evidence does not match this run.' }
if ((Get-FileHash $OutputPath -Algorithm SHA256).Hash -ne $result.sha256) { throw 'Evidence hash changed.' }
if ($saved.observations.os.status -ne 'observed') { throw 'OS identity remains unverified.' }
Write-Output "PASS: readiness evidence preserved at $OutputPath"
Write-Output "SHA256: $($result.sha256)"
foreach ($entry in $saved.observations.GetEnumerator()) {
    if ($entry.Value.status -ne 'observed') { Write-Warning "$($entry.Key) remains unverified: $($entry.Value.error_id)" }
}
if ($saved.observations.offered_updates.status -eq 'observed' -and $saved.observations.offered_updates.data[0].result_code -ne 2) {
    Write-Warning 'Update search did not succeed completely; do not infer patch compliance.'
}
