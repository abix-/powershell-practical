<#
.SYNOPSIS
Inspects the official latest Windows app package without installing or launching it.
.DESCRIPTION
Downloads only the x64 MSIX linked by OpenAI deployment documentation over verified
Windows HTTPS. Reads public package identity and Node entry metadata. Extracts only
node.exe entries, verifies independent vendor signatures and tests signed candidates
with the existing TLS diagnostic. Never extracts app settings or credentials.
.PARAMETER Directory
New private candidate directory outside Git.
.PARAMETER PackagePath
Existing previously downloaded MSIX to inspect instead of downloading again.
.EXAMPLE
./Test-CodexUpdateCandidate.ps1 -Directory C:/Windows/Temp/codex-candidate
.NOTES
MSIX signature and expected package identity are checked. Candidate Node tests do
not prove the installed app will select that runtime or update detached runtimes.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$Directory,
    [string]$PackagePath
)
$ErrorActionPreference = 'Stop'
$target = [System.IO.Path]::GetFullPath($Directory)
if (Test-Path -LiteralPath $target) { throw 'Choose a new candidate directory.' }
[void][System.IO.Directory]::CreateDirectory($target)
$uri = 'https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix'
$path = Join-Path $target 'ChatGPT-x64.msix'
if ($PackagePath) {
    $path = (Get-Item -LiteralPath $PackagePath -ErrorAction Stop).FullName
} else {
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$handler.UseCookies = $false
$handler.UseDefaultCredentials = $false
$handler.UseProxy = $false
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(120)
try {
    $response = $client.GetAsync($uri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    try {
        [void]$response.EnsureSuccessStatusCode()
        $length = $response.Content.Headers.ContentLength
        $drive = Get-PSDrive -Name ([System.IO.Path]::GetPathRoot($target).TrimEnd(':', '\'))
        if ($length -and $length -gt $drive.Free) { throw 'Insufficient space for official app candidate.' }
        $inputStream = $response.Content.ReadAsStream()
        $outputStream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew)
        try { $inputStream.CopyTo($outputStream) }
        finally { $inputStream.Dispose(); $outputStream.Dispose() }
    } finally { $response.Dispose() }
} finally { $client.Dispose(); $handler.Dispose() }
}
$packageSignature = Get-AuthenticodeSignature -LiteralPath $path
$signatureRecord = @{ status = [string]$packageSignature.Status; signer = $packageSignature.SignerCertificate.Subject }
if ($packageSignature.Status -ne 'Valid') { throw 'MSIX package signature is not valid.' }
$zip = [System.IO.Compression.ZipFile]::OpenRead($path)
$nodes = [System.Collections.Generic.List[object]]::new()
try {
    $manifestEntry = $zip.GetEntry('AppxManifest.xml')
    if (-not $manifestEntry) { throw 'Candidate lacks package manifest.' }
    $reader = [System.IO.StreamReader]::new($manifestEntry.Open())
    try { $manifestText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $xmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($manifestText), $settings)
    try { $manifest = [System.Xml.XmlDocument]::new(); $manifest.XmlResolver = $null; $manifest.Load($xmlReader) }
    finally { $xmlReader.Dispose() }
    $identity = $manifest.DocumentElement.SelectSingleNode("*[local-name()='Identity']")
    if (-not $identity) { throw 'Candidate lacks package identity.' }
    if ($identity.GetAttribute('Name') -ne 'OpenAI.Codex' -or $identity.GetAttribute('Publisher') -ne 'CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B') {
        throw 'Candidate identity does not match the installed OpenAI.Codex publisher.'
    }
    foreach ($entry in ($zip.Entries | Where-Object FullName -match '(^|/)node\.exe$')) {
        $nodeDirectory = Join-Path $target "candidate-node-$($nodes.Count)"
        [void][System.IO.Directory]::CreateDirectory($nodeDirectory)
        $nodePath = Join-Path $nodeDirectory 'node.exe'
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $nodePath, $false)
        $signature = Get-AuthenticodeSignature -LiteralPath $nodePath
        $record = @{ entry = $entry.FullName; path = $nodePath; sha256 = (Get-FileHash -LiteralPath $nodePath -Algorithm SHA256).Hash
            file_version = (Get-Item -LiteralPath $nodePath).VersionInfo.FileVersion; signature_status = [string]$signature.Status
            signer = $signature.SignerCertificate.Subject }
        if ($signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match 'OpenJS Foundation|OpenAI OpCo') {
            $trustPath = Join-Path $nodeDirectory 'trust.json'
            & (Join-Path $PSScriptRoot 'Test-NodeTrustEvidence.ps1') -NodePath $nodePath -OutputPath $trustPath
            $record.trust_path = $trustPath
            $record.trust_sha256 = (Get-FileHash -LiteralPath $trustPath -Algorithm SHA256).Hash
        } else { $record.reason = 'Candidate Node not executed: expected independent valid vendor signature unavailable.' }
        $nodes.Add($record)
    }
    $report = @{ collected_at = [DateTime]::UtcNow.ToString('o'); source = $uri; package_path = $path
        package_sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        package_signature = $signatureRecord
        identity = @{ name = $identity.GetAttribute('Name'); version = $identity.GetAttribute('Version'); publisher = $identity.GetAttribute('Publisher') }
        node_entries = @($nodes.ToArray())
        scope = 'Signed candidate inspection only; input is official HTTPS download or caller-selected existing package. MSIX signature and matching OpenAI package identity checked. No app installation/launch; detached runtime selection/update remains unverified.' }
} finally { $zip.Dispose() }
$receiptPath = Join-Path $target 'candidate.json'
[System.IO.File]::WriteAllText($receiptPath, ($report | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$saved = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if ($saved.identity.version -ne $report.identity.version) { throw 'Saved candidate identity mismatch.' }
Write-Output "PASS: official app candidate metadata saved to $receiptPath; no installation performed."
Write-Output "SHA256: $((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash)"
