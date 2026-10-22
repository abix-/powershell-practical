<#
.SYNOPSIS
Collects allowlisted read-only RouterOS device and network inventory.
.DESCRIPTION
Uses the configured read-only SSH identity with strict host verification.
Never exports configuration or queries credentials. Optional unavailable
tables are recorded as errors, not interpreted as empty networks.
.PARAMETER RouterAddress
The router's management address.
.PARAMETER Username
An existing read-only SSH account.
.PARAMETER IdentityFile
Existing SSH identity path, passed directly to SSH without reading its contents.
.PARAMETER OutputPath
Local JSON evidence file. Keep private network inventory outside public Git.
.PARAMETER SecurityEvidence
Also collects account logs and selected account/persistence metadata.
.EXAMPLE
./Get-MikrotikInventory.ps1 -RouterAddress 192.168.88.1 -Username inventory -IdentityFile C:/keys/router_readonly -OutputPath C:/Windows/Temp/mikrotik-inventory.json
.NOTES
Requires PowerShell 7 and OpenSSH. No configuration changes or active scans.
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
if ($SecurityEvidence -and (Test-Path -LiteralPath $OutputPath)) {
    throw 'Choose a new security evidence path; previous evidence is preserved.'
}
$sshCommand = Get-Command ssh.exe -ErrorAction SilentlyContinue
$sshPath = if ($sshCommand) { $sshCommand.Source } else { 'C:/Program Files/Git/usr/bin/ssh.exe' }
if (-not (Test-Path -LiteralPath $sshPath -PathType Leaf)) { throw 'OpenSSH was not found.' }
if ($RouterAddress -notmatch '^[a-zA-Z0-9.:_-]+$' -or $Username -notmatch '^[a-zA-Z0-9._-]+$') {
    throw 'Invalid SSH destination.'
}

# Retained fields are selected again locally because RouterOS can include extras.
$queries = [ordered]@{
    resource = '/system/resource/print as-value'
    routerboard = '/system/routerboard/print as-value'
    update_status = '/system/package/update/print as-value'
    packages = '/system/package/print as-value proplist=name,version,disabled'
    leases = '/ip/dhcp-server/lease/print as-value proplist=address,mac-address,host-name,status,last-seen,active-address,active-mac-address,server'
    arp = '/ip/arp/print as-value proplist=address,mac-address,interface,status,complete,invalid'
    ipv6_neighbors = '/ipv6/neighbor/print as-value proplist=address,mac-address,interface,status'
    neighbors = '/ip/neighbor/print as-value proplist=address,address6,mac-address,identity,platform,version,board,interface'
    bridge_hosts = '/interface/bridge/host/print as-value proplist=mac-address,on-interface,bridge,local,dynamic,vid'
    wireless_clients = '/interface/wireless/registration-table/print as-value proplist=mac-address,interface,last-ip'
    wifi_clients = '/interface/wifi/registration-table/print as-value proplist=mac-address,interface'
    services = '/ip/service/print as-value proplist=name,port,disabled,address,vrf'
    interfaces = '/interface/print as-value proplist=name,type,running,disabled,mac-address'
    interface_lists = '/interface/list/member/print as-value proplist=list,interface,disabled'
    firewall = '/ip/firewall/filter/print as-value proplist=chain,action,disabled,protocol,dst-port,src-port,src-address,dst-address,in-interface,in-interface-list,src-address-list,dst-address-list,connection-state,connection-nat-state,ipsec-policy'
    nat = '/ip/firewall/nat/print as-value proplist=chain,action,disabled,protocol,dst-port,to-addresses,to-ports,in-interface,in-interface-list'
    ipv6_firewall = '/ipv6/firewall/filter/print as-value proplist=chain,action,disabled,protocol,dst-port,src-port,src-address,dst-address,in-interface,in-interface-list,src-address-list,dst-address-list,connection-state,ipsec-policy'
}

$securityQueries = [ordered]@{}
if ($SecurityEvidence) {
    # Explicit get calls avoid retrieving script bodies, event actions or secrets.
    $securityTables = [ordered]@{
        account_logs = @{ menu = '/log'; fields = @('time', 'topics', 'message'); filter = ' where topics~"account" or message~"login failure"' }
        device_mode = @{ menu = '/system/device-mode'; fields = @('mode', 'flagged', 'flagging-enabled'); single = $true }
        router_clock = @{ menu = '/system/clock'; fields = @('date', 'time', 'time-zone-name', 'gmt-offset'); single = $true }
        users = @{ menu = '/user'; fields = @('name', 'group', 'disabled', 'address', 'last-logged-in') }
        groups = @{ menu = '/user/group'; fields = @('name', 'policy') }
        active_users = @{ menu = '/user/active'; fields = @('name', 'address', 'via', 'when') }
        scripts = @{ menu = '/system/script'; fields = @('name', 'owner', 'policy', 'last-started', 'run-count') }
        scheduler = @{ menu = '/system/scheduler'; fields = @('name', 'owner', 'disabled', 'start-date', 'start-time', 'interval', 'next-run', 'run-count', 'policy') }
        netwatch = @{ menu = '/tool/netwatch'; fields = @('host', 'type', 'disabled', 'status') }
        dns = @{ menu = '/ip/dns'; fields = @('servers', 'dynamic-servers', 'allow-remote-requests'); single = $true }
        socks = @{ menu = '/ip/socks'; fields = @('enabled', 'port'); single = $true }
        proxy = @{ menu = '/ip/proxy'; fields = @('enabled', 'port'); single = $true }
        containers = @{ menu = '/container'; fields = @('name', 'status', 'interface', 'root-dir') }
        certificates = @{ menu = '/certificate'; fields = @('name', 'common-name', 'issuer', 'fingerprint', 'trusted') }
        dns_static = @{ menu = '/ip/dns/static'; fields = @('name', 'type', 'address', 'disabled') }
        logging = @{ menu = '/system/logging'; fields = @('topics', 'action', 'disabled') }
        log_actions = @{ menu = '/system/logging/action'; fields = @('name', 'target', 'memory-lines', 'disk-file-name', 'remote') }
    }
    foreach ($entry in $securityTables.GetEnumerator()) {
        $table = $entry.Value
        $pairs = foreach ($field in $table.fields) {
            $selector = if ($table.single) { '' } else { '$id ' }
            '"' + $field + '"=[' + $table.menu + '/get ' + $selector + $field + ']'
        }
        $record = '{' + ($pairs -join ';') + '}'
        $command = if ($table.single) {
            ':put [:serialize to=json options=json.no-string-conversion ' + $record + ']'
        } else {
            ':local out "["; :local sep ""; :foreach id in=[' + $table.menu + '/find' + $table.filter + '] do={ :set out ($out . $sep . [:serialize to=json options=json.no-string-conversion ' + $record + ']); :set sep "," }; :put ($out . "]")'
        }
        $securityQueries[$entry.Key] = $command
    }
    # Capture the bounded memory account log before the inventory SSH logins.
    $combined = [ordered]@{ account_logs = $securityQueries.account_logs }
    foreach ($entry in $queries.GetEnumerator()) { $combined[$entry.Key] = $entry.Value }
    foreach ($entry in $securityQueries.GetEnumerator()) {
        if ($entry.Key -ne 'account_logs') { $combined[$entry.Key] = $entry.Value }
    }
    $queries = $combined
}

$results = [ordered]@{}
foreach ($entry in $queries.GetEnumerator()) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $sshPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $remoteCommand = ':put [:serialize to=json options=json.no-string-conversion [' + $entry.Value + ']]'
    if ($securityQueries.Contains($entry.Key)) { $remoteCommand = $entry.Value }
    foreach ($argument in @('-T', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'IdentitiesOnly=yes', '-o', 'ConnectTimeout=10', '-o', 'ConnectionAttempts=1', '-i', $IdentityFile, "$Username@$RouterAddress", $remoteCommand)) {
        $startInfo.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(25000)) {
            $process.Kill($true)
            throw "SSH timeout collecting $($entry.Key)."
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) { throw "SSH failed collecting $($entry.Key): $stderr" }
        try {
            $data = ConvertFrom-Json -InputObject $stdout -AsHashtable -ErrorAction Stop
            $fields = if ($securityQueries.Contains($entry.Key)) {
                $securityTables[$entry.Key].fields
            } elseif ($entry.Key -eq 'resource') {
                @('version', 'board-name', 'architecture-name', 'uptime', 'free-hdd-space', 'total-hdd-space', 'free-memory', 'total-memory')
            } elseif ($entry.Key -eq 'routerboard') {
                @('model', 'firmware-type', 'factory-firmware', 'current-firmware', 'upgrade-firmware')
            } elseif ($entry.Key -eq 'update_status') {
                @('channel', 'installed-version', 'latest-version', 'status')
            } else {
                ($entry.Value -split 'proplist=', 2)[1] -split ','
            }
            $selectedRows = @(
                foreach ($row in $data) {
                    if ($null -eq $row) { continue }
                    if ($row -isnot [System.Collections.IDictionary]) { throw 'Expected a RouterOS record.' }
                    $selected = [ordered]@{}
                    foreach ($field in $fields) {
                        if ($row.Contains($field)) { $selected[$field] = $row[$field] }
                    }
                    $selected
                }
            )
            $data = if ($entry.Key -eq 'resource') { $selectedRows[0] } else { $selectedRows }
            if ($entry.Key -eq 'resource' -and -not $data.version) {
                throw 'RouterOS version missing.'
            }
            $results[$entry.Key] = @{ status = 'observed'; data = $data }
        }
        catch {
            # Never persist unexpected raw device output.
            $results[$entry.Key] = @{ status = 'unverified'; error = 'RouterOS did not return the requested JSON table.' }
        }
        if ($entry.Key -eq 'resource' -and $results.resource.status -ne 'observed') {
            throw 'Could not verify router identity and version; inventory stopped.'
        }
    }
    finally { $process.Dispose() }
}
$report = [ordered]@{
    observed_at = [DateTime]::UtcNow.ToString('o')
    router_address = $RouterAddress
    scope = 'Read-only router observations; device firmware and complete network coverage require separate verification.'
    observations = $results
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolvedOutput))
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resolvedOutput -Encoding utf8
[pscustomobject]$report
