<#
.SYNOPSIS
Reads exact firewall state and verifies the data-only proposal and rollback scope.
.PARAMETER EvidencePath
Private existing inbound-rule evidence.
.PARAMETER ProgramPath
Exact OneLog release executable.
.PARAMETER OutputPath
New private plan JSON path.
.EXAMPLE
./Test-OnelogFirewallPlan.ps1 -EvidencePath C:/Windows/Temp/evidence.json -ProgramPath C:/code/onelog/target/release/onelog.exe -OutputPath C:/Windows/Temp/plan.json
.NOTES
Does not apply firewall changes or establish phone/network acceptance.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$EvidencePath,
    [Parameter(Mandatory)] [string]$ProgramPath,
    [Parameter(Mandatory)] [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
try {
    $result = & (Join-Path $PSScriptRoot 'Get-OnelogFirewallPlan.ps1') @PSBoundParameters
} catch {
    $diagnostic = @{ error_id = $_.FullyQualifiedErrorId; error_type = $_.Exception.GetType().FullName
        script = [System.IO.Path]::GetFileName($_.InvocationInfo.ScriptName); line = $_.InvocationInfo.ScriptLineNumber
        stack = $_.ScriptStackTrace }
    $errorPath = [System.IO.Path]::GetFullPath($OutputPath + '.error.json')
    $stream = [System.IO.File]::Open($errorPath, [System.IO.FileMode]::CreateNew)
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($diagnostic | ConvertTo-Json))
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
    throw
}
$saved = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if ($saved.started_at -ne $result.started_at) { throw 'Plan does not match this run.' }
if ((Get-FileHash $OutputPath -Algorithm SHA256).Hash -ne $result.sha256) { throw 'Plan hash changed.' }
if ($saved.applied -or $saved.rules.Count -ne 2) { throw 'Unexpected plan scope.' }
foreach ($rule in $saved.rules) {
    foreach ($filter in @('application', 'service', 'port', 'address', 'interface', 'interface_type', 'security')) {
        if (-not $rule.current_filters[$filter].Count) { throw "Missing $filter backup." }
    }
    if (-not $rule.current_filters.application.Program -or -not $rule.current_filters.port.LocalPort) { throw 'Adapted program/port aliases missing from backup.' }
    if (($rule.proposed_parameters.Keys | Sort-Object) -join ',' -cne 'LocalPort,Name,PolicyStore,RemoteAddress') { throw 'Proposal changes unexpected fields.' }
    if ($rule.proposed_parameters.Name -cne $rule.name -or $rule.rollback_parameters.Name -cne $rule.name) { throw 'Rule identity changed.' }
    if ((@($rule.rollback_parameters.LocalPort) -join ',') -ne 'Any' -or (@($rule.rollback_parameters.RemoteAddress) -join ',') -ne 'Any') { throw 'Rollback does not match captured broad conditions.' }
    $expectedPorts = if ($rule.protocol -eq 'TCP') { '31300,31301' } else { '31302' }
    if ((@($rule.proposed_parameters.LocalPort) -join ',') -ne $expectedPorts) { throw 'Unexpected proposed ports.' }
    $expectedSources = if ($rule.protocol -eq 'TCP') { 'LocalSubnet,127.0.0.1,::1' } else { 'LocalSubnet' }
    if ((@($rule.proposed_parameters.RemoteAddress) -join ',') -ne $expectedSources) { throw 'Unexpected proposed source scope.' }
}
Write-Output "PASS: exact rule/filter backup and unapplied proposal saved to $OutputPath"
Write-Output "SHA256: $($result.sha256)"
