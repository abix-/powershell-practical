<#
.SYNOPSIS
Runs deployed curl TLS checks and verifies saved evidence and matrix completeness.
.PARAMETER OutputPath
New private JSON evidence path.
.EXAMPLE
./Test-CurlTrustEvidence.ps1 -OutputPath C:/Windows/Temp/curl-trust.json
.NOTES
Collection success does not mean secure clients. Accepted bad chains are findings.
#>
[CmdletBinding()]
param ([Parameter(Mandatory)] [string]$OutputPath)
$ErrorActionPreference = 'Stop'
$result = & (Join-Path $PSScriptRoot 'Get-CurlTrustEvidence.ps1') @PSBoundParameters
$saved = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if ($saved.started_at -ne $result.started_at) { throw 'Evidence does not match this run.' }
if ((Get-FileHash $OutputPath -Algorithm SHA256).Hash -ne $result.sha256) { throw 'Evidence hash changed.' }
if (-not $saved.clients.Count) { throw 'No installed curl client was tested.' }
foreach ($client in $saved.clients) {
    if ($client.checks.Count -ne 15) { throw 'Incomplete positive/bad-host matrix.' }
    if (-not $client.positive_control_passed) { Write-Warning "Valid TLS control failed for $($client.path); rejection alone is not sufficient." }
    if ($client.bad_chain_tls_accepted) { Write-Warning "$($client.path) accepted $($client.bad_chain_tls_accepted) compromised-chain hosts." }
    if ($client.transport_unknown) { Write-Warning "$($client.path) has $($client.transport_unknown) unverified transport results." }
}
Write-Output "PASS: curl trust evidence saved to $OutputPath"
Write-Output "SHA256: $($result.sha256)"
