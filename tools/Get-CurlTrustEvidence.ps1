<#
.SYNOPSIS
Checks deployed Windows curl clients against public eMudhra TLS test hosts.
.DESCRIPTION
Uses the installed Windows and Git curl binaries with default verification,
curl config disabled, no credentials, no redirects and no response bodies.
One valid positive control precedes fourteen public bad-chain tests per client.
Classifies certificate rejection separately from DNS/timeouts/other TLS failures.
.PARAMETER OutputPath
New private JSON evidence path outside public Git.
.EXAMPLE
./Get-CurlTrustEvidence.ps1 -OutputPath C:/Windows/Temp/curl-trust.json
.NOTES
No trust store, software, process or configuration changes. This checks these
curl clients, not every application or the Git HTTPS transport configuration.
#>
[CmdletBinding()]
param ([Parameter(Mandatory)] [string]$OutputPath)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputPath) { throw 'Choose a new evidence path.' }
. (Join-Path $PSScriptRoot 'Invoke-SecurityDiagnosticProcess.ps1')
$started = [DateTime]::UtcNow.ToString('o')
$candidates = @('C:/Windows/System32/curl.exe', 'C:/Program Files/Git/mingw64/bin/curl.exe',
    'C:/Program Files/Git/usr/bin/curl.exe')
$hostsToCheck = @('rustsec.org')
foreach ($issuer in @('dv-g3b', 'dv-g3c', 'ov-g3b', 'ov-g3c', 'ev-g3b', 'ev-g3c')) {
    foreach ($crossSign in @('', '-aaa')) { $hostsToCheck += "$issuer$crossSign-emudhra.we-have-a-problem.com" }
}
$hostsToCheck += @('dv-g3b-noct-emudhra.we-have-a-problem.com', 'dv-g3b-aaa-noct-emudhra.we-have-a-problem.com')
$clients = foreach ($path in $candidates) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $version = Invoke-SecurityDiagnosticProcess $path @('-q', '--version')
    if ($version.exit_code) { throw 'curl version unavailable.' }
    $checks = foreach ($hostname in $hostsToCheck) {
        try {
            $arguments = @('-q', '--proto', '=https', '--head', '--output', 'NUL', '--write-out', '%{http_code}',
                '--connect-timeout', '5', '--max-time', '12', '--max-redirs', '0', '--silent', '--show-error', "https://$hostname/")
            $result = Invoke-SecurityDiagnosticProcess $path $arguments -TimeoutSeconds 16
            $revoked = $result.stderr -match 'CRYPT_E_REVOKED|CERT_E_REVOKED|0x80092010|revoked'
            $rejected = $result.exit_code -eq 60 -or $revoked
            $classification = if ($result.exit_code -eq 0) { 'tls_accepted' }
                elseif ($rejected) { 'certificate_rejected' } else { 'unverified_transport_failure' }
            [pscustomobject]@{
                host = $hostname; expected = if ($hostname -eq 'rustsec.org') { 'tls_accepted' } else { 'certificate_rejected' }
                exit_code = $result.exit_code; classification = $classification
                revocation_specific = $revoked
                http_status = if ($result.stdout.Trim() -match '^\d{3}$') { $result.stdout.Trim() } else { $null }
            }
        } catch {
            [pscustomobject]@{ host = $hostname; classification = 'unverified_transport_failure'; error_id = $_.FullyQualifiedErrorId }
        }
    }
    [pscustomobject]@{
        path = $path; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        version = ($version.stdout -split '\r?\n')[0]; checks = @($checks)
        positive_control_passed = ($checks[0].classification -eq 'tls_accepted')
        bad_chain_tls_accepted = @($checks | Where-Object { $_.host -ne 'rustsec.org' -and $_.classification -eq 'tls_accepted' }).Count
        bad_chain_certificate_rejected = @($checks | Where-Object { $_.host -ne 'rustsec.org' -and $_.classification -eq 'certificate_rejected' }).Count
        transport_unknown = @($checks | Where-Object classification -eq 'unverified_transport_failure').Count
    }
}
$report = [ordered]@{
    started_at = $started; completed_at = [DateTime]::UtcNow.ToString('o')
    source = 'https://emudhra.we-have-a-problem.com/'
    bad_hosts_per_client = 14; clients = @($clients)
    scope = 'Actual curl binaries only, curlrc disabled; inherited environment and automatic platform trust updates not controlled. No trust bypass, credentials or HTTP body downloads. TLS acceptance of an incident host is a finding, not evidence that this desktop was previously attacked.'
}
$resolved = [System.IO.Path]::GetFullPath($OutputPath)
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolved))
$json = $report | ConvertTo-Json -Depth 12 -WarningAction Stop
$stream = [System.IO.File]::Open($resolved, [System.IO.FileMode]::CreateNew)
try { $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json); $stream.Write($bytes, 0, $bytes.Length) }
finally { $stream.Dispose() }
[pscustomobject]@{ started_at = $started; sha256 = (Get-FileHash $resolved -Algorithm SHA256).Hash }
