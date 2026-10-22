<#
.SYNOPSIS
Stages official Node and Python security artifacts without installing anything.
.DESCRIPTION
Uses verified Windows HTTPS, official Node checksums and Authenticode, and PyPI
wheel SHA256 metadata. Keeps downloads and receipt in a new private directory.
Never invokes installers, Python, pip or package startup hooks.
.PARAMETER Directory
New private staging directory outside Git.
.EXAMPLE
./Get-SecurityPatchArtifacts.ps1 -Directory C:/Windows/Temp/security-patches
.NOTES
Pinned review targets: Node26.12.1 x64, pip26.2.2 and certifi2026.10.19.
Staging does not patch existing processes or establish application compatibility.
#>
[CmdletBinding()]
param ([Parameter(Mandatory)] [string]$Directory)
$ErrorActionPreference = 'Stop'
$directoryPath = [System.IO.Path]::GetFullPath($Directory)
if (Test-Path -LiteralPath $directoryPath) { throw 'Choose a new staging directory.' }
[void][System.IO.Directory]::CreateDirectory($directoryPath)
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$handler.UseCookies = $false
$handler.UseDefaultCredentials = $false
$handler.UseProxy = $false
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(120)
$artifacts = [System.Collections.Generic.List[object]]::new()
$started = [DateTime]::UtcNow.ToString('o')
function Save-PublicArtifact {
    param ([uri]$Uri, [string]$Name)
    if ($Uri.Scheme -ne 'https' -or $Uri.Host -notin @('nodejs.org', 'pypi.org', 'files.pythonhosted.org') -or $Uri.UserInfo) {
        throw 'Artifact URL outside official HTTPS allowlist.'
    }
    $response = $client.GetAsync($Uri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    try {
        [void]$response.EnsureSuccessStatusCode()
        $path = Join-Path $directoryPath $Name
        $inputStream = $response.Content.ReadAsStream()
        $outputStream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew)
        try { $inputStream.CopyTo($outputStream) }
        finally { $inputStream.Dispose(); $outputStream.Dispose() }
        return $path
    } finally { $response.Dispose() }
}
try {
    $sumsPath = Save-PublicArtifact 'https://nodejs.org/dist/v26.12.1/SHASUMS256.txt' 'SHASUMS256.txt'
    $sums = [System.IO.File]::ReadAllLines($sumsPath)
    foreach ($relative in @('win-x64/node.exe', 'node-v26.12.1-x64.msi')) {
        $name = [System.IO.Path]::GetFileName($relative)
        $match = @($sums | Where-Object { $_ -match ('^[a-f0-9]{64}\s+' + [regex]::Escape($relative) + '$') })
        if ($match.Count -ne 1) { throw 'Official Node checksum entry is missing or ambiguous.' }
        $expected = ($match[0] -split '\s+')[0]
        $uri = "https://nodejs.org/dist/v26.12.1/$relative"
        $path = Save-PublicArtifact $uri $name
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($hash -ine $expected) { throw 'Node download does not match official SHA256.' }
        $signature = Get-AuthenticodeSignature -LiteralPath $path
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'OpenJS Foundation') {
            throw 'Node artifact lacks a valid expected publisher signature.'
        }
        $artifacts.Add(@{ name = $name; path = $path; source = $uri; sha256 = $hash
            signature_status = [string]$signature.Status; signer = $signature.SignerCertificate.Subject })
    }
    foreach ($package in @(@{ name = 'pip'; version = '26.2.2' }, @{ name = 'certifi'; version = '2026.10.19' })) {
        $metadataUri = "https://pypi.org/pypi/$($package.name)/$($package.version)/json"
        $metadataPath = Save-PublicArtifact $metadataUri "$($package.name)-release.json"
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json -AsHashtable
        if ($metadata.info.name -ne $package.name -or $metadata.info.version -ne $package.version) { throw 'Unexpected PyPI release metadata.' }
        $filename = "$($package.name)-$($package.version)-py3-none-any.whl"
        $files = @($metadata.urls | Where-Object { $_.filename -eq $filename -and $_.packagetype -eq 'bdist_wheel' -and -not $_.yanked })
        if ($files.Count -ne 1 -or $files[0].digests.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Expected unyanked wheel unavailable.' }
        $path = Save-PublicArtifact $files[0].url $filename
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($hash -ine $files[0].digests.sha256) { throw 'Wheel does not match official PyPI SHA256.' }
        $artifacts.Add(@{ name = $filename; path = $path; source = $files[0].url; sha256 = $hash
            package = $package.name; version = $package.version; signature_status = 'Not applicable; PyPI SHA256 verified' })
    }
    $report = @{ started_at = $started; completed_at = [DateTime]::UtcNow.ToString('o'); artifacts = @($artifacts.ToArray())
        node_checksum_manifest_sha256 = (Get-FileHash -LiteralPath $sumsPath -Algorithm SHA256).Hash
        scope = 'Verified staging only; no installer/package execution, runtime replacement, global environment changes or restarts. Node PGP signature not independently verified; binary Authenticode and HTTPS official hashes verified.' }
    $receiptPath = Join-Path $directoryPath 'artifacts.json'
    [System.IO.File]::WriteAllText($receiptPath, ($report | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    [pscustomobject]@{ receipt_path = $receiptPath; sha256 = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash }
} finally { $client.Dispose(); $handler.Dispose() }
