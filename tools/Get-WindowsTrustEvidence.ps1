<#
.SYNOPSIS
Collects Windows public trust metadata and eMudhra chain decisions.
.DESCRIPTION
Downloads the incident's public certificate manifests over verified HTTPS,
validates certificate hashes, reads public Root/CA/Disallowed stores and builds
chains with AIA certificate downloads and revocation fetching disabled. Never imports
certificates, reads private keys or changes trust settings. This is not an online
TLS test and rejection for missing roots is not proof of explicit distrust.
.PARAMETER OutputPath
New private JSON evidence file outside public Git.
.EXAMPLE
./Get-WindowsTrustEvidence.ps1 -OutputPath C:/Windows/Temp/windows-trust.json
.NOTES
Requires Windows and PowerShell 7.5+. Uses the current user's Windows chain engine.
#>
[CmdletBinding()]
param ([Parameter(Mandatory)] [string]$OutputPath)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows is required.' }
if (Test-Path -LiteralPath $OutputPath) { throw 'Choose a new evidence path.' }
$startedAt = [DateTime]::UtcNow.ToString('o')
$baseUri = 'https://emudhra.we-have-a-problem.com/'
$intermediateResponse = Invoke-WebRequest -Uri ($baseUri + 'impacted-intermediates.json') -TimeoutSec 30
$rootResponse = Invoke-WebRequest -Uri ($baseUri + 'roots.json') -TimeoutSec 30
$intermediates = @($intermediateResponse.Content | ConvertFrom-Json -AsHashtable)
$roots = @($rootResponse.Content | ConvertFrom-Json -AsHashtable)
if ($intermediates.Count -lt 8 -or $intermediates.Count -gt 32 -or $roots.Count -gt 16) { throw 'Unexpected public manifest size.' }
$publicCertificates = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($item in @($intermediates) + @($roots)) {
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem($item.pem)
        $actualHash = $certificate.GetCertHashString([System.Security.Cryptography.HashAlgorithmName]::SHA256)
        if ($item.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or $actualHash -ne $item.sha256) {
            $certificate.Dispose()
            throw 'Public certificate does not match its manifest hash.'
        }
        $publicCertificates.Add(@{ manifest = $item; certificate = $certificate })
    }
    $storeRows = foreach ($location in @('CurrentUser', 'LocalMachine')) {
        foreach ($name in @('Root', 'CA', 'Disallowed')) {
            $store = [System.Security.Cryptography.X509Certificates.X509Store]::new($name, $location)
            try {
                $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly -bor
                    [System.Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly)
                $certificates = foreach ($certificate in $store.Certificates) {
                    [pscustomobject]@{
                        subject = $certificate.Subject; issuer = $certificate.Issuer
                        sha256 = $certificate.GetCertHashString([System.Security.Cryptography.HashAlgorithmName]::SHA256)
                        not_after = $certificate.NotAfter.ToUniversalTime().ToString('o')
                    }
                }
                [pscustomobject]@{ location = $location; store = $name; status = 'observed'; certificates = @($certificates) }
            } catch {
                [pscustomobject]@{ location = $location; store = $name; status = 'unverified'; error_type = $_.Exception.GetType().FullName }
            } finally { $store.Dispose() }
        }
    }
    $decisions = foreach ($item in $publicCertificates | Where-Object { $_.manifest.usage }) {
        $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
        try {
            $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            $chain.ChainPolicy.DisableCertificateDownloads = $true
            foreach ($extra in $publicCertificates) { [void]$chain.ChainPolicy.ExtraStore.Add($extra.certificate) }
            $oid = if ($item.manifest.usage -eq 'tls') { '1.3.6.1.5.5.7.3.1' } else { '1.3.6.1.5.5.7.3.3' }
            [void]$chain.ChainPolicy.ApplicationPolicy.Add([System.Security.Cryptography.Oid]::new($oid))
            $accepted = $chain.Build($item.certificate)
            $statuses = @($chain.ChainStatus | ForEach-Object { [string]$_.Status })
            [pscustomobject]@{
                name = $item.manifest.name; issuer = $item.manifest.issued_by; usage = $item.manifest.usage
                sha256 = $item.manifest.sha256; accepted_no_revocation = $accepted
                statuses = $statuses; explicit_distrust = ($statuses -contains 'ExplicitDistrust')
                chain = @($chain.ChainElements | ForEach-Object {
                    @{ subject = $_.Certificate.Subject; sha256 = $_.Certificate.GetCertHashString([System.Security.Cryptography.HashAlgorithmName]::SHA256) }
                })
            }
        } finally { $chain.Dispose() }
    }
    $policy = foreach ($path in @('HKLM:/SOFTWARE/Policies/Microsoft/SystemCertificates/AuthRoot',
        'HKLM:/SOFTWARE/Microsoft/SystemCertificates/AuthRoot/AutoUpdate')) {
        if (Test-Path $path) {
            $key = Get-Item $path
            foreach ($name in @('DisableRootAutoUpdate', 'EnableDisallowedCertAutoUpdate', 'LastSyncTime')) {
                $value = $key.GetValue($name)
                if ($null -ne $value) { @{ path = $path; name = $name; value = $value } }
            }
        }
    }
    $report = [ordered]@{
        started_at = $startedAt; completed_at = [DateTime]::UtcNow.ToString('o')
        source = $baseUri; manifest_count = $intermediates.Count
        source_manifest_sha256 = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes([string]$intermediateResponse.Content)))
        scope = 'Windows chain observations with revocation fetching and AIA downloads disabled. Automatic Windows CTL activity is not controlled. No online TLS or native-tls runtime coverage. No certificate imports or private-key reads.'
        public_stores = @($storeRows); auto_update_metadata = @($policy); decisions = @($decisions)
    }
    $resolved = [System.IO.Path]::GetFullPath($OutputPath)
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolved))
    $json = $report | ConvertTo-Json -Depth 15 -WarningAction Stop
    $stream = [System.IO.File]::Open($resolved, [System.IO.FileMode]::CreateNew)
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
    [pscustomobject]@{ started_at = $startedAt; output_path = $resolved; sha256 = (Get-FileHash $resolved -Algorithm SHA256).Hash }
} finally {
    foreach ($item in $publicCertificates) { $item.certificate.Dispose() }
}
