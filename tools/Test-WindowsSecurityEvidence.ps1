<#
.SYNOPSIS
Runs the permanent read-only Windows collector and validates its saved evidence.
.PARAMETER OutputPath
New private JSON evidence path outside public Git.
.PARAMETER Days
Requested event lookback in days.
.PARAMETER RequireSecurityLog
Fail if the Security event log or inbound firewall rules cannot be read.
.PARAMETER AuthenticationAndFirewallOnly
Collect targeted events and firewall exposure without repeating executable hashing.
.EXAMPLE
./Test-WindowsSecurityEvidence.ps1 -OutputPath C:/Windows/Temp/desktop-security.json
.NOTES
Tests collection integrity, not whether the desktop is uncompromised.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$OutputPath,
    [ValidateRange(1, 90)] [int]$Days = 30,
    [switch]$RequireSecurityLog,
    [switch]$AuthenticationAndFirewallOnly
)
$ErrorActionPreference = 'Stop'
$result = & (Join-Path $PSScriptRoot 'Get-WindowsSecurityEvidence.ps1') -OutputPath $OutputPath -Days $Days -AuthenticationAndFirewallOnly:$AuthenticationAndFirewallOnly
$saved = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if ($saved.started_at -ne $result.started_at) { throw 'Evidence does not match this collection.' }
if ((Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash -ne $result.sha256) { throw 'Evidence hash changed.' }
if ($saved.observations.os.status -ne 'observed') { throw 'Operating system identity remains unverified.' }
if ($RequireSecurityLog) {
    foreach ($name in @('security_events', 'security_changes', 'security_failures', 'security_remote_logons', 'firewall_inbound_allow_rules')) {
        if ($saved.observations[$name].status -ne 'observed') { throw "Required elevated evidence $name remains unverified; report preserved." }
    }
}
foreach ($entry in $saved.observations.GetEnumerator()) {
    if ($entry.Value.status -notin @('observed', 'unverified')) { throw 'Invalid observation status.' }
    if ($entry.Value.status -eq 'unverified') { Write-Warning "$($entry.Key) remains unverified: $($entry.Value.error_id)" }
}
Write-Output "PASS: read-only desktop evidence saved to $OutputPath"
Write-Output "SHA256: $($result.sha256)"
