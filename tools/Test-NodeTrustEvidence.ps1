<#
.SYNOPSIS
Checks installed Node bundled-CA TLS defaults with isolated child options.
.DESCRIPTION
Clears child-only preload/trust overrides without reading their values, executes
the repository's built-in-module-only test and preserves its public-host results.
Does not change global environment, Node installation or running applications.
.PARAMETER OutputPath
New private JSON evidence path.
.PARAMETER NodePath
Existing node.exe to check. Defaults to the installed PATH command.
.EXAMPLE
./Test-NodeTrustEvidence.ps1 -OutputPath C:/Windows/Temp/node-trust.json
.NOTES
Fifteen checks: one valid control and fourteen public incident hosts. Accepted
incident chains are findings; runtime configuration of existing apps is separate.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$OutputPath,
    [string]$NodePath
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputPath) { throw 'Choose a new evidence path.' }
. (Join-Path $PSScriptRoot 'Invoke-SecurityDiagnosticProcess.ps1')
$executable = if ($NodePath) { (Get-Item -LiteralPath $NodePath -ErrorAction Stop).FullName }
    else { (Get-Command node.exe -ErrorAction Stop).Source }
$started = [DateTime]::UtcNow.ToString('o')
$result = Invoke-SecurityDiagnosticProcess -Executable $executable -Arguments @('--use-bundled-ca', (Join-Path $PSScriptRoot 'check-node-trust.mjs')) -TimeoutSeconds 150 -IsolatedNodeDefaults
if ($result.exit_code) { throw 'Node diagnostic failed; no unverified raw output persisted.' }
$receipt = $result.stdout | ConvertFrom-Json -AsHashtable -ErrorAction Stop
if ($receipt.checks.Count -ne 15) { throw 'Incomplete Node TLS test matrix.' }
$report = [ordered]@{
    started_at = $started; completed_at = [DateTime]::UtcNow.ToString('o')
    executable = $executable; sha256 = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash
    fixture_sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'check-node-trust.mjs') -Algorithm SHA256).Hash
    receipt = $receipt
}
$resolved = [System.IO.Path]::GetFullPath($OutputPath)
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolved))
$json = $report | ConvertTo-Json -Depth 12 -WarningAction Stop
$stream = [System.IO.File]::Open($resolved, [System.IO.FileMode]::CreateNew)
try { $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json); $stream.Write($bytes, 0, $bytes.Length) }
finally { $stream.Dispose() }
$saved = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json -AsHashtable -DateKind String
if ($saved.started_at -ne $started -or $saved.receipt.checks.Count -ne 15) { throw 'Saved Node evidence mismatch.' }
$accepted = @($receipt.checks | Where-Object { $_.host -ne 'rustsec.org' -and $_.classification -eq 'tls_accepted' }).Count
if ($accepted) { Write-Warning "Installed Node bundled defaults accepted $accepted incident hosts." }
if (-not $receipt.positive_control_passed) { Write-Warning 'Positive control failed; negative results alone are insufficient.' }
Write-Output "PASS: Node default trust evidence saved to $OutputPath"
Write-Output "SHA256: $((Get-FileHash $resolved -Algorithm SHA256).Hash)"
