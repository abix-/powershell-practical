<#
.SYNOPSIS
Verifies staged vendor patches and tests portable fixed Node before installation.
.PARAMETER Directory
New private staging directory. Existing installations are not changed.
.EXAMPLE
./Test-SecurityPatchArtifacts.ps1 -Directory C:/Windows/Temp/security-patches
.NOTES
Success requires verified artifacts, a valid TLS control and rejection of all
fourteen incident chains by the new portable Node runtime. Does not install it.
#>
[CmdletBinding()]
param ([Parameter(Mandatory)] [string]$Directory)
$ErrorActionPreference = 'Stop'
$result = & (Join-Path $PSScriptRoot 'Get-SecurityPatchArtifacts.ps1') @PSBoundParameters
$receipt = Get-Content -LiteralPath $result.receipt_path -Raw | ConvertFrom-Json -AsHashtable
if ((Get-FileHash -LiteralPath $result.receipt_path -Algorithm SHA256).Hash -ne $result.sha256) { throw 'Artifact receipt changed.' }
if ($receipt.artifacts.Count -ne 4) { throw 'Incomplete patch staging.' }
foreach ($artifact in $receipt.artifacts) {
    if ((Get-FileHash -LiteralPath $artifact.path -Algorithm SHA256).Hash -ne $artifact.sha256) { throw 'Staged artifact changed.' }
}
$nodePath = ($receipt.artifacts | Where-Object name -eq 'node.exe').path
$trustPath = Join-Path ([System.IO.Path]::GetFullPath($Directory)) 'fixed-node-trust.json'
& (Join-Path $PSScriptRoot 'Test-NodeTrustEvidence.ps1') -NodePath $nodePath -OutputPath $trustPath
$trust = Get-Content -LiteralPath $trustPath -Raw | ConvertFrom-Json -AsHashtable
if ($trust.receipt.node_version -ne '26.12.1' -or -not $trust.receipt.positive_control_passed) { throw 'Fixed Node identity/control failed.' }
$rejected = @($trust.receipt.checks | Where-Object { $_.host -ne 'rustsec.org' -and $_.classification -eq 'certificate_rejected' })
if ($rejected.Count -ne 14) { throw 'Fixed portable Node did not reject all fourteen incident chains.' }
Write-Output "PASS: four official patch artifacts verified; portable Node control passed and fourteen incident chains rejected. No installation performed."
Write-Output "Artifact receipt SHA256: $($result.sha256)"
