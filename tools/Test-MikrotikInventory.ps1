<#
.SYNOPSIS
Runs read-only RouterOS discovery and verifies its saved evidence.
.PARAMETER RouterAddress
Router management address.
.PARAMETER Username
Existing read-only SSH account.
.PARAMETER IdentityFile
Existing SSH identity path, never read by this script.
.PARAMETER OutputPath
Local private JSON evidence file.
.PARAMETER SecurityEvidence
Collect account logs and selected security metadata, reporting missing access.
.EXAMPLE
./Test-MikrotikInventory.ps1 -RouterAddress 192.168.88.1 -Username inventory -IdentityFile C:/keys/router_readonly -OutputPath C:/Windows/Temp/mikrotik-inventory.json
.NOTES
Checks observation integrity, not whether devices are patched or safe.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$RouterAddress,
    [Parameter(Mandatory)] [string]$Username,
    [Parameter(Mandatory)] [string]$IdentityFile,
    [Parameter(Mandatory)] [string]$OutputPath,
    [switch]$SecurityEvidence
)
$ErrorActionPreference = 'Stop'
$report = & (Join-Path $PSScriptRoot 'Get-MikrotikInventory.ps1') @PSBoundParameters
$saved = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if ($saved.observed_at -ne $report.observed_at) { throw 'Saved inventory does not match this run.' }
foreach ($table in @('resource', 'leases', 'arp', 'bridge_hosts', 'services')) {
    if ($saved.observations[$table].status -ne 'observed') { throw "Required table $table remains unverified." }
}
if (-not $saved.observations.resource.data.version) { throw 'RouterOS version missing.' }
if ($SecurityEvidence) {
    foreach ($table in @('account_logs', 'device_mode', 'users', 'scripts', 'scheduler')) {
        if ($saved.observations[$table].status -ne 'observed') { throw "Required security table $table remains unverified." }
    }
}
Write-Output "PASS: router identity and core discovery tables saved to $OutputPath"
Write-Output "SHA256: $((Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash)"
foreach ($entry in $saved.observations.GetEnumerator()) {
    if ($entry.Value.status -ne 'observed') { Write-Warning "$($entry.Key) remains unverified." }
}
