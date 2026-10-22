function Invoke-SecurityDiagnosticProcess {
    <#
    .SYNOPSIS
    Runs a caller-selected diagnostic executable with bounded time and output.
    .PARAMETER Executable
    Existing executable path. Callers own the read-only command allowlist.
    .PARAMETER Arguments
    Literal arguments passed without a command shell.
    .PARAMETER TimeoutSeconds
    Maximum local process wait. Timed-out clients are stopped, not the WSL VM.
    .PARAMETER IsolatedNodeDefaults
    Removes inherited Node preload/trust overrides in this child only, without reading values.
    .EXAMPLE
    Invoke-SecurityDiagnosticProcess -Executable C:/Windows/System32/curl.exe -Arguments @('-q', '--version')
    .NOTES
    Output is returned to the collector, which must select safe fields before saving.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Executable,
        [Parameter(Mandatory)] [string[]]$Arguments,
        [ValidateRange(1, 180)] [int]$TimeoutSeconds = 25,
        [switch]$IsolatedNodeDefaults
    )
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    if ($IsolatedNodeDefaults) {
        if ([System.IO.Path]::GetFileName($Executable) -ine 'node.exe') { throw 'Node isolation requires node.exe.' }
        foreach ($name in @('NODE_OPTIONS', 'NODE_EXTRA_CA_CERTS', 'NODE_USE_SYSTEM_CA',
            'NODE_TLS_REJECT_UNAUTHORIZED', 'NODE_USE_ENV_PROXY', 'SSL_CERT_FILE', 'SSL_CERT_DIR')) {
            [void]$start.Environment.Remove($name)
        }
    }
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            throw 'Diagnostic client timed out.'
        }
        $outText = $stdout.GetAwaiter().GetResult()
        $errText = $stderr.GetAwaiter().GetResult()
        if ($outText.Length -gt 500000 -or $errText.Length -gt 50000) { throw 'Diagnostic output limit exceeded.' }
        [pscustomobject]@{ exit_code = $process.ExitCode; stdout = $outText; stderr = $errText }
    } finally { $process.Dispose() }
}
