<#
.SYNOPSIS
Inventories Plex/PHP and selected runtimes on Windows, running WSL and containers.
.DESCRIPTION
Reads allowlisted app/version/process metadata, installed Linux package names,
container image/name/port metadata and public Plex identity version endpoints.
Never reads command lines, environment variables, credentials or app databases.
Does not start stopped WSL distributions, containers, services or workloads.
.PARAMETER OutputPath
New private JSON evidence path outside public Git.
.EXAMPLE
./Get-ApplicationSecurityInventory.ps1 -OutputPath C:/Windows/Temp/application-security.json
.NOTES
Windows/PowerShell 7.5+. Plex probes are restricted to this desktop and the known NAS.
#>
[CmdletBinding()]
param ([Parameter(Mandatory)] [string]$OutputPath)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputPath) { throw 'Choose a new evidence path.' }
. (Join-Path $PSScriptRoot 'Invoke-SecurityDiagnosticProcess.ps1')
$started = [DateTime]::UtcNow.ToString('o')
$observations = [ordered]@{}
function Save-ApplicationObservation {
    param ([string]$Name, [scriptblock]$Collect)
    try { $observations[$Name] = @{ status = 'observed'; data = @(& $Collect) } }
    catch { $observations[$Name] = @{ status = 'unverified'; error_id = $_.FullyQualifiedErrorId; error_type = $_.Exception.GetType().FullName } }
}
Save-ApplicationObservation 'windows_apps' {
    foreach ($root in @('HKLM:/SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall',
        'HKLM:/SOFTWARE/WOW6432Node/Microsoft/Windows/CurrentVersion/Uninstall',
        'HKCU:/SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall')) {
        if (Test-Path $root) {
            foreach ($key in Get-ChildItem $root) {
                $name = $key.GetValue('DisplayName')
                if ($name -match 'Plex|PHP|Apache|nginx|Node.js|Python|Git|OpenSSL|Java|Docker') {
                    @{ name = $name; version = $key.GetValue('DisplayVersion')
                        publisher = $key.GetValue('Publisher'); location = $key.GetValue('InstallLocation') }
                }
            }
        }
    }
}
Save-ApplicationObservation 'windows_processes' {
    Get-Process | Where-Object ProcessName -match 'plex|^php|httpd|nginx|node|python|java|docker|wsl|k3s' |
        Select-Object Id, ProcessName, Path
}
Save-ApplicationObservation 'windows_services' {
    Get-CimInstance Win32_Service -Property Name, DisplayName, State, StartMode |
        Where-Object { $_.Name -match 'plex|php|nginx|apache|w3svc|iis' -or $_.DisplayName -match 'Plex|PHP|nginx|Apache|World Wide Web' } |
        Select-Object Name, DisplayName, State, StartMode
}
Save-ApplicationObservation 'node_process_ancestry' {
    $processes = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, ExecutablePath, CreationDate)
    foreach ($nodeProcess in ($processes | Where-Object Name -eq 'node.exe')) {
        $current = $nodeProcess
        $ancestry = for ($depth = 0; $depth -lt 5 -and $null -ne $current; $depth++) {
            @{ pid = $current.ProcessId; parent_pid = $current.ParentProcessId; name = $current.Name
                path = $current.ExecutablePath; created_at = $current.CreationDate }
            $childCreated = $current.CreationDate
            $parentId = $current.ParentProcessId
            $current = $processes | Where-Object { $_.ProcessId -eq $parentId -and $_.CreationDate -le $childCreated } | Select-Object -First 1
        }
        @{ node_pid = $nodeProcess.ProcessId; ancestry = @($ancestry)
            scope = 'Executable ancestry only; does not establish script identity or application TLS options.' }
    }
}
Save-ApplicationObservation 'windows_known_binaries' {
    $paths = @('C:/Program Files/Plex/Plex Media Server/Plex Media Server.exe',
        'C:/Program Files (x86)/Plex/Plex Media Server/Plex Media Server.exe',
        'C:/php/php.exe', 'C:/tools/php/php.exe', 'C:/xampp/php/php.exe')
    foreach ($name in @('php.exe', 'node.exe', 'curl.exe', 'git.exe')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { $paths += $command.Source }
    }
    foreach ($path in ($paths | Sort-Object -Unique)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $file = Get-Item -LiteralPath $path
            @{ path = $file.FullName; version = $file.VersionInfo.FileVersion
                product_version = $file.VersionInfo.ProductVersion; sha256 = (Get-FileHash $file.FullName -Algorithm SHA256).Hash }
        }
    }
}
Save-ApplicationObservation 'python_package_metadata' {
    $root = Join-Path $env:LOCALAPPDATA 'Programs/Python/Python312/Lib/site-packages'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Known Python package directory unavailable.' }
    foreach ($package in @('certifi', 'pip', 'litellm', 'requests', 'urllib3')) {
        $directories = @(Get-ChildItem -LiteralPath $root -Directory -Filter "$package-*.dist-info")
        if (-not $directories.Count) {
            @{ package = $package; status = 'not_found_in_checked_directory'; root = $root }
        }
        foreach ($directory in $directories) {
            $metadata = Join-Path $directory.FullName 'METADATA'
            $name = $null
            $version = $null
            foreach ($line in [System.IO.File]::ReadLines($metadata)) {
                if ($line -eq '') { break }
                if ($line -match '^Name: ([A-Za-z0-9_.-]+)$') { $name = $Matches[1] }
                if ($line -match '^Version: ([A-Za-z0-9_.+!-]+)$') { $version = $Matches[1] }
            }
            if (-not $name -or -not $version) { throw 'Package metadata lacks expected name/version headers.' }
            @{ package = $name; version = $version; metadata_path = $metadata; status = 'observed' }
        }
    }
}
$docker = Get-Command docker.exe -ErrorAction SilentlyContinue
if ($docker) {
    Save-ApplicationObservation 'docker_containers' {
        $format = '{"id":{{json .ID}},"image":{{json .Image}},"name":{{json .Names}},"state":{{json .State}},"ports":{{json .Ports}}}'
        $result = Invoke-SecurityDiagnosticProcess $docker.Source @('ps', '--all', '--no-trunc', '--format', $format)
        if ($result.exit_code) { throw 'Docker container inventory unavailable.' }
        foreach ($line in ($result.stdout -split '\r?\n' | Where-Object { $_.Trim() })) { $line | ConvertFrom-Json -AsHashtable }
    }
} else { $observations.docker_containers = @{ status = 'unverified'; reason = 'Docker CLI not available; no absence claim.' } }
$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
$running = @()
if ($wsl) {
    Save-ApplicationObservation 'running_wsl' {
        $result = Invoke-SecurityDiagnosticProcess $wsl.Source @('--list', '--running', '--quiet')
        if ($result.exit_code) { throw 'Running WSL distribution list unavailable.' }
        $script:running = @($result.stdout.Replace([string][char]0, '') -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $script:running
    }
    if ('Ubuntu-24.04' -in $running) {
        Save-ApplicationObservation 'ubuntu_packages' {
            $format = '${binary:Package}\t${Version}\t${db:Status-Status}\n'
            $result = Invoke-SecurityDiagnosticProcess $wsl.Source @('--distribution', 'Ubuntu-24.04', '--exec', 'dpkg-query', '-W', ('-f=' + $format))
            if ($result.exit_code) { throw 'Ubuntu package inventory unavailable.' }
            foreach ($line in ($result.stdout -split '\r?\n')) {
                $fields = $line -split "`t"
                if ($fields.Count -eq 3 -and $fields[0] -match '^(php|plex|ca-certificates|openssl|curl|nodejs|python3($|-pip)|libssl)') {
                    @{ name = $fields[0]; version = $fields[1]; state = $fields[2] }
                }
            }
        }
        Save-ApplicationObservation 'k3s_pod_images' {
            $columns = 'custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,IMAGES:.spec.containers[*].image,INIT_IMAGES:.spec.initContainers[*].image'
            $result = Invoke-SecurityDiagnosticProcess $wsl.Source @('--distribution', 'Ubuntu-24.04', '--exec', 'sudo', '-n', 'k3s', 'kubectl', 'get', 'pods', '--all-namespaces', '--request-timeout=10s', '-o', $columns)
            if ($result.exit_code) { throw 'k3s pod metadata unavailable.' }
            $result.stdout.Trim()
        }
    } else {
        $observations.ubuntu_packages = @{ status = 'unverified'; reason = 'Known Ubuntu distribution is not running; not started.' }
        $observations.k3s_pod_images = @{ status = 'unverified'; reason = 'Known Ubuntu distribution is not running; not started.' }
    }
} else { $observations.running_wsl = @{ status = 'unverified'; reason = 'WSL CLI unavailable.' } }
foreach ($address in @('127.0.0.1', '192.168.88.45')) {
    Save-ApplicationObservation ('plex_identity_' + $address) {
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect = $false
        $handler.UseCookies = $false
        $handler.UseDefaultCredentials = $false
        $handler.UseProxy = $false
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [TimeSpan]::FromSeconds(6)
        try {
            $response = $client.GetAsync("http://${address}:32400/identity").GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) { throw 'Plex public identity endpoint did not answer successfully.' }
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ($body.Length -gt 16384) { throw 'Unexpected identity response size.' }
            $settings = [System.Xml.XmlReaderSettings]::new()
            $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
            $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($body), $settings)
            try {
                $xml = [System.Xml.XmlDocument]::new()
                $xml.XmlResolver = $null
                $xml.Load($reader)
            } finally { $reader.Dispose() }
            if (-not $xml.MediaContainer.version) { throw 'Plex version missing.' }
            @{ address = $address; port = 32400; version = [string]$xml.MediaContainer.version
                scope = 'Unauthenticated version observation; other ports/instances and actual security backports require separate verification.' }
        } finally { $client.Dispose(); $handler.Dispose() }
    }
}
$report = [ordered]@{
    started_at = $started; completed_at = [DateTime]::UtcNow.ToString('o')
    scope = 'Targeted metadata only. No credential/config reads, command lines, container environment or stopped-runtime startup. No absence-of-compromise or complete application inventory claim.'
    observations = $observations
}
$resolved = [System.IO.Path]::GetFullPath($OutputPath)
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolved))
$json = $report | ConvertTo-Json -Depth 12 -WarningAction Stop
$stream = [System.IO.File]::Open($resolved, [System.IO.FileMode]::CreateNew)
try { $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json); $stream.Write($bytes, 0, $bytes.Length) }
finally { $stream.Dispose() }
[pscustomobject]@{ started_at = $started; sha256 = (Get-FileHash $resolved -Algorithm SHA256).Hash }
