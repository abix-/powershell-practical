<#
.SYNOPSIS
Applies the reviewed signed Codex MSIX with deferred registration and no forced exit.
.DESCRIPTION
Requires the exact tested official package hash/signature and matching installed
family. Preserves version/disk evidence and uses only Add-AppxPackage with
DeferRegistrationWhenPackagesAreInUse. Does not close or restart any session.
.PARAMETER PackagePath
Verified official OpenAI.Codex26.1016.8622.0 MSIX.
.PARAMETER OutputPath
New private deployment receipt path.
.EXAMPLE
./Test-DeferredCodexUpdate.ps1 -PackagePath C:/Windows/Temp/ChatGPT-x64.msix -OutputPath C:/Windows/Temp/codex-deferred.json
.NOTES
Use only after owners have saved their checkpoints. App registration does not
prove replacement of already selected detached Node runtimes or app TLS behavior.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$PackagePath,
    [Parameter(Mandatory)] [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputPath) { throw 'Choose a new deployment receipt path.' }
$principal = [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = @('-NoProfile', '-File', "`"$PSCommandPath`"", '-PackagePath', "`"$PackagePath`"", '-OutputPath', "`"$OutputPath`"")
    $worker = Start-Process -FilePath (Get-Command pwsh.exe).Source -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru -Wait
    if ($worker.ExitCode -ne 0) { throw "Elevated deferred deployment failed with exit $($worker.ExitCode); inspect receipt." }
    if (-not (Test-Path -LiteralPath $OutputPath)) { throw 'Deferred deployment returned no receipt.' }
    return
}
$report = [ordered]@{ started_at = [DateTime]::UtcNow.ToString('o'); forced_shutdown = $false; app_restart_performed = $false; reboot_performed = $false }
try {
    $path = (Get-Item -LiteralPath $PackagePath).FullName
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hash -ne '9085CF2E2EB5081F894A2CF334E1F36DBB9438ECB409D20195AA2FE1ECFCB4C8') { throw 'MSIX no longer matches the tested candidate.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -ne 'CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B') { throw 'MSIX signature/publisher mismatch.' }
    $report.package_path = $path
    $report.package_sha256 = $hash
    Import-Module Appx -UseWindowsPowerShell -ErrorAction Stop
    $before = @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop)
    if ($before.Count -ne 1 -or $before[0].PackageFamilyName -ne 'OpenAI.Codex_2p2nqsd0c76g0') { throw 'Expected installed package family not found.' }
    $report.before = @{ version = [string]$before[0].Version; package_full_name = $before[0].PackageFullName; location = $before[0].InstallLocation }
    $free = (Get-PSDrive -Name C).Free
    $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
    try { $expanded = ($zip.Entries | Measure-Object -Property Length -Sum).Sum } finally { $zip.Dispose() }
    $report.disk = @{ free_bytes = $free; candidate_expanded_bytes = $expanded }
    if ($free -lt $expanded) { throw 'Insufficient free C: space for the expanded app candidate.' }
    if ([version]$before[0].Version -lt [version]'26.1016.8622.0') {
        Add-AppxPackage -Path $path -DeferRegistrationWhenPackagesAreInUse -ErrorAction Stop
        $report.status = 'deferred_registration_requested'
    } else { $report.status = 'candidate_or_newer_already_registered' }
    $after = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop
    $report.after = @{ version = [string]$after.Version; package_full_name = $after.PackageFullName; location = $after.InstallLocation }
    $report.active_detached_runtime_verified = $false
} catch { $report.status = 'failed'; $report.error_id = $_.FullyQualifiedErrorId; throw }
finally {
    $report.completed_at = [DateTime]::UtcNow.ToString('o')
    $resolved = [System.IO.Path]::GetFullPath($OutputPath)
    $stream = [System.IO.File]::Open($resolved, [System.IO.FileMode]::CreateNew)
    try { $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($report | ConvertTo-Json -Depth 8)); $stream.Write($bytes, 0, $bytes.Length) }
    finally { $stream.Dispose() }
}
$saved = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -AsHashtable
if ($saved.package_sha256 -ne $hash -or $saved.forced_shutdown) { throw 'Saved deferred deployment receipt mismatch.' }
Write-Output "PASS: signed app update registration requested without forced exit. Selected detached runtime and next-launch checks remain pending."
Write-Output "SHA256: $((Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash)"
