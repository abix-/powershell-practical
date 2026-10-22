<#
.SYNOPSIS
Collects event-retention evidence and requires readable Security and archive metadata.
.PARAMETER OutputPath
New private JSON evidence path.
.PARAMETER Days
Requested investigation window in days.
.EXAMPLE
./Test-WindowsLogCoverage.ps1 -OutputPath C:/Windows/Temp/log-coverage.json -Days 30
.NOTES
Success verifies collection, not full historical coverage or absence of compromise.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$OutputPath,
    [ValidateRange(1, 90)] [int]$Days = 30
)
$ErrorActionPreference = 'Stop'
$result = & (Join-Path $PSScriptRoot 'Get-WindowsLogCoverage.ps1') @PSBoundParameters
$saved = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if ($saved.observed_at -ne $result.observed_at) { throw 'Evidence does not match this run.' }
if ((Get-FileHash $OutputPath -Algorithm SHA256).Hash -ne $result.sha256) { throw 'Evidence hash changed.' }
$security = @($saved.live_logs | Where-Object name -eq 'Security')[0]
if ($security.status -ne 'observed' -or $saved.archive_status -ne 'observed') { throw 'Security retention or archive listing remains unverified; report preserved.' }
Write-Output "PASS: retention evidence preserved at $OutputPath"
Write-Output "SHA256: $($result.sha256)"
