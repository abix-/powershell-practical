<#
.SYNOPSIS
Preserves exact OneLog release firewall rules and proposes reversible restrictions.
.DESCRIPTION
Selects only the two release-program rules identified in a prior private evidence
report. Reads their current PersistentStore rules and every associated filter.
Writes proposed parameter sets and exact inverse parameter sets as JSON data.
Never invokes a firewall-writing command, changes profiles or touches debug rules.
.PARAMETER EvidencePath
Private report from Get-WindowsSecurityEvidence with inbound-rule observations.
.PARAMETER ProgramPath
Exact OneLog release executable; no wildcard program matching.
.PARAMETER OutputPath
New private plan and rollback JSON path outside public Git.
.EXAMPLE
./Get-OnelogFirewallPlan.ps1 -EvidencePath C:/Windows/Temp/evidence.json -ProgramPath C:/code/onelog/target/release/onelog.exe -OutputPath C:/Windows/Temp/onelog-firewall-plan.json
.NOTES
Requires Windows, PowerShell 7.5+ and elevated firewall read access. Plan review is
not approval to apply it; actual loopback and paired-phone validation is required.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$EvidencePath,
    [Parameter(Mandatory)] [string]$ProgramPath,
    [Parameter(Mandatory)] [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows is required.' }
if (Test-Path -LiteralPath $OutputPath) { throw 'Choose a new plan path.' }
$startedAt = [DateTime]::UtcNow.ToString('o')
$program = [System.IO.Path]::GetFullPath($ProgramPath)
if (-not (Test-Path -LiteralPath $program -PathType Leaf)) { throw 'Release executable does not exist.' }
$evidenceHash = (Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash
$seed = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if ($seed.observations.firewall_inbound_allow_rules.status -ne 'observed') { throw 'Seed firewall observation is unavailable.' }
$seedRules = @($seed.observations.firewall_inbound_allow_rules.data | Where-Object {
    $_.program -and [System.IO.Path]::GetFullPath($_.program) -ieq $program
})
if ($seedRules.Count -ne 2) { throw 'Expected exactly the release TCP and UDP rules; manual review required.' }

function ConvertTo-FlatFirewallRecord {
    param ($Record)
    $result = [ordered]@{}
    # NetSecurity exposes cmdlet aliases such as Program over raw CIM properties.
    $properties = $Record.PSObject.Properties | Where-Object Name -notin @('CimClass', 'CimInstanceProperties',
        'CimSystemProperties', 'PSComputerName', 'RunspaceId', 'PSShowComputerName')
    foreach ($property in $properties) {
        $value = $property.Value
        if ($value -is [Enum]) { $value = [string]$value }
        if ($value -is [Microsoft.Management.Infrastructure.CimInstance]) {
            $value = [string]$value.CimSystemProperties.Path
        }
        $result[$property.Name] = $value
    }
    if (-not $result.Count) { throw 'Firewall provider returned no capturable properties.' }
    $result
}
$filterCommands = [ordered]@{
    application = 'Get-NetFirewallApplicationFilter'
    service = 'Get-NetFirewallServiceFilter'
    port = 'Get-NetFirewallPortFilter'
    address = 'Get-NetFirewallAddressFilter'
    interface = 'Get-NetFirewallInterfaceFilter'
    interface_type = 'Get-NetFirewallInterfaceTypeFilter'
    security = 'Get-NetFirewallSecurityFilter'
}
$proposals = foreach ($savedRule in $seedRules) {
    $rules = @(Get-NetFirewallRule -PolicyStore PersistentStore -Name $savedRule.name)
    if ($rules.Count -ne 1 -or $rules[0].Name -cne $savedRule.name) { throw 'Exact saved rule identity no longer resolves uniquely.' }
    $rule = $rules[0]
    if ([string]$rule.Enabled -ne 'True' -or [string]$rule.Direction -ne 'Inbound' -or [string]$rule.Action -ne 'Allow') {
        throw 'Selected rule state changed; review before proposing modifications.'
    }
    $filters = [ordered]@{}
    foreach ($entry in $filterCommands.GetEnumerator()) {
        $records = @($rule | & $entry.Value)
        if ($records.Count -ne 1) { throw "Unexpected $($entry.Key) filter count." }
        $filters[$entry.Key] = ConvertTo-FlatFirewallRecord $records[0]
    }
    if ([System.IO.Path]::GetFullPath($filters.application.Program) -ine $program) { throw 'Live rule belongs to another executable.' }
    $protocol = [string]$filters.port.Protocol
    $tcp = $protocol -in @('TCP', '6')
    $udp = $protocol -in @('UDP', '17')
    if (-not ($tcp -or $udp)) { throw 'Selected rule is not TCP or UDP.' }
    if ((@($filters.port.LocalPort) -join ',') -ne 'Any' -or (@($filters.address.RemoteAddress) -join ',') -ne 'Any') {
        throw 'Broad rule conditions changed; review instead of overwriting newer restrictions.'
    }
    [pscustomobject]@{
        name = $rule.Name; protocol = if ($tcp) { 'TCP' } else { 'UDP' }
        current_rule = ConvertTo-FlatFirewallRecord $rule; current_filters = $filters
        proposed_command = 'Set-NetFirewallRule'
        proposed_parameters = @{
            Name = $rule.Name; PolicyStore = 'PersistentStore'
            LocalPort = if ($tcp) { @('31300', '31301') } else { @('31302') }
            RemoteAddress = if ($tcp) { @('LocalSubnet', '127.0.0.1', '::1') } else { @('LocalSubnet') }
        }
        rollback_command = 'Set-NetFirewallRule'
        rollback_parameters = @{
            Name = $rule.Name; PolicyStore = 'PersistentStore'
            LocalPort = @($filters.port.LocalPort); RemoteAddress = @($filters.address.RemoteAddress)
        }
    }
}
if (@($proposals | Where-Object protocol -eq 'TCP').Count -ne 1 -or @($proposals | Where-Object protocol -eq 'UDP').Count -ne 1) {
    throw 'Expected one TCP and one UDP release rule.'
}
$report = [ordered]@{
    started_at = $startedAt; completed_at = [DateTime]::UtcNow.ToString('o')
    program = $program; program_sha256 = (Get-FileHash -LiteralPath $program -Algorithm SHA256).Hash
    source_evidence = [System.IO.Path]::GetFullPath($EvidencePath); source_sha256 = $evidenceHash
    applied = $false; rules = @($proposals)
    required_validation = @('Review exact rule identities and all filter backup data against live state before any change.',
        'Retain current profile, program, enabled state, package/service, interface and security conditions.',
        'Coordinate with orchestrator; no reboot or blanket firewall/network change.',
        'Verify loopback MCP and authenticated LAN phone sync plus UDP pairing/discovery after the reviewed change.',
        'If validation fails, restore only LocalPort and RemoteAddress using each exact inverse parameter set.',
        'Leave debug/test and all unrelated rules untouched. Stale broad rules remain separately open.')
    scope = 'Read-only evidence and data-only proposal. Only LocalPort and RemoteAddress would change on two exact release rules. No commands applied.'
}
$resolved = [System.IO.Path]::GetFullPath($OutputPath)
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolved))
$json = $report | ConvertTo-Json -Depth 15 -WarningAction Stop
$stream = [System.IO.File]::Open($resolved, [System.IO.FileMode]::CreateNew)
try {
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }
[pscustomobject]@{ started_at = $startedAt; sha256 = (Get-FileHash $resolved -Algorithm SHA256).Hash }
