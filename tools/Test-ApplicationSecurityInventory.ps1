<#
.SYNOPSIS
Runs targeted read-only application inventory and checks its evidence.
.PARAMETER OutputPath
New private JSON evidence path.
.EXAMPLE
./Test-ApplicationSecurityInventory.ps1 -OutputPath C:/Windows/Temp/application-security.json
.NOTES
Unavailable NAS, container or runtime surfaces remain unverified, never absent.
#>
[CmdletBinding()]
param ([Parameter(Mandatory)] [string]$OutputPath)
$ErrorActionPreference = 'Stop'
$result = & (Join-Path $PSScriptRoot 'Get-ApplicationSecurityInventory.ps1') @PSBoundParameters
$saved = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if ($saved.started_at -ne $result.started_at) { throw 'Evidence does not match this run.' }
if ((Get-FileHash $OutputPath -Algorithm SHA256).Hash -ne $result.sha256) { throw 'Evidence hash changed.' }
foreach ($name in @('windows_apps', 'windows_processes', 'windows_services')) {
    if ($saved.observations[$name].status -ne 'observed') { throw "Required desktop inventory $name remains unverified." }
}
Write-Output "PASS: targeted application inventory saved to $OutputPath"
Write-Output "SHA256: $($result.sha256)"
foreach ($entry in $saved.observations.GetEnumerator()) {
    if ($entry.Value.status -ne 'observed') { Write-Warning "$($entry.Key) remains unverified." }
}
