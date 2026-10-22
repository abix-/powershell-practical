<#
.SYNOPSIS
Records installed OpenAI app metadata and read-only Windows package update queries.
.DESCRIPTION
Reads app package/version and running executable metadata, then asks winget for
installed Codex and official Store product details. Does not accept agreements,
install, update, restart, read app settings or touch vendor-owned runtime files.
.PARAMETER OutputPath
New private JSON evidence path outside Git.
.EXAMPLE
./Test-CodexUpdateReadiness.ps1 -OutputPath C:/Windows/Temp/codex-update.json
.NOTES
Package availability does not establish that a release includes patched Node.
Store product identity must match the installed app before any update is proposed.
#>
[CmdletBinding()]
param ([Parameter(Mandatory)] [string]$OutputPath)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputPath) { throw 'Choose a new evidence path.' }
. (Join-Path $PSScriptRoot 'Invoke-SecurityDiagnosticProcess.ps1')
$observations = [ordered]@{}
try {
    Import-Module Appx -UseWindowsPowerShell -ErrorAction Stop
    $packages = @(Get-AppxPackage -Name '*OpenAI*' -ErrorAction Stop |
        Select-Object Name, Version, PackageFullName, PackageFamilyName, InstallLocation, Status, SignatureKind)
    $observations.app_packages = @{ status = 'observed'; data = $packages }
    $observations.packaged_node = @(foreach ($package in $packages) {
        if ($package.Name -ne 'OpenAI.Codex') { continue }
        $nodePath = Join-Path $package.InstallLocation 'app/resources/cua_node/bin/node.exe'
        if (Test-Path -LiteralPath $nodePath -PathType Leaf) {
            $file = Get-Item -LiteralPath $nodePath
            @{ package_version = [string]$package.Version; path = $file.FullName; version = $file.VersionInfo.FileVersion
                sha256 = (Get-FileHash -LiteralPath $nodePath -Algorithm SHA256).Hash
                scope = 'Packaged file metadata only; does not prove executable access or active detached runtime selection.' }
        }
    })
} catch { $observations.app_packages = @{ status = 'unverified'; error_id = $_.FullyQualifiedErrorId } }
$observations.running_executables = @(Get-Process | Where-Object { $_.ProcessName -match '^(codex|chatgpt)$' -and $_.Path } |
    ForEach-Object { $file = Get-Item -LiteralPath $_.Path
        @{ pid = $_.Id; path = $file.FullName; file_version = $file.VersionInfo.FileVersion; product_version = $file.VersionInfo.ProductVersion } })
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if ($winget) {
    foreach ($query in @(
        @{ name = 'installed_codex'; arguments = @('list', '--name', 'Codex', '--disable-interactivity') },
        @{ name = 'installed_store_product'; arguments = @('list', '--id', '9PLM9XGG6VKS', '--source', 'msstore', '--disable-interactivity') },
        @{ name = 'official_store_product'; arguments = @('show', '--id', '9PLM9XGG6VKS', '--source', 'msstore', '--disable-interactivity') }
    )) {
        try {
            $result = Invoke-SecurityDiagnosticProcess $winget.Source $query.arguments -TimeoutSeconds 35
            $observations[$query.name] = @{ exit_code = $result.exit_code; stdout = $result.stdout; stderr = $result.stderr
                status = if ($result.exit_code -eq 0) { 'observed' } else { 'unverified' } }
        } catch { $observations[$query.name] = @{ status = 'unverified'; error_id = $_.FullyQualifiedErrorId } }
    }
} else { $observations.winget = @{ status = 'unverified'; reason = 'winget unavailable.' } }
$report = @{ collected_at = [DateTime]::UtcNow.ToString('o'); observations = $observations
    scope = 'Read-only package availability and executable metadata. No evidence yet that any available app update fixes embedded Node; no runtime or application changes.' }
$resolved = [System.IO.Path]::GetFullPath($OutputPath)
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolved))
$stream = [System.IO.File]::Open($resolved, [System.IO.FileMode]::CreateNew)
try { $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($report | ConvertTo-Json -Depth 8)); $stream.Write($bytes, 0, $bytes.Length) }
finally { $stream.Dispose() }
$saved = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if ($saved.collected_at -ne $report.collected_at) { throw 'Saved update evidence mismatch.' }
Write-Output "PASS: package update evidence saved to $resolved; availability is not a bundled-runtime fix claim."
Write-Output "SHA256: $((Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash)"
