<#
.SYNOPSIS
Turns off Discord desktop's process observer (game detection and exe fingerprinting).
.DESCRIPTION
Discord's discord_utils.node keeps snapshotting every running process and its
loaded modules to detect games, costing 30 to 50 percent of one core while idle,
and no Discord setting stops it. This script edits Discord's own JavaScript
wrapper for that module (modules\discord_utils-*\discord_utils\index.js) so the
observer functions do nothing. The original is kept as index.js.orig.

Every Discord update installs a fresh, unpatched copy in a new app-1.0.xxxx
folder. -Watch keeps running and patches new copies as they appear; -Register
makes a scheduled task that starts -Watch at logon. A Discord that already
loaded an unpatched copy needs a restart for the patch to take effect.
.PARAMETER Root
Discord's install folder. Defaults to %LOCALAPPDATA%\Discord.
.PARAMETER Watch
Keep running: patch whenever Discord writes a new copy, and check once a minute.
.PARAMETER Register
Create or replace the logon task that runs this script with -Watch, and start it.
.PARAMETER Unregister
Remove the logon task. Patched files stay patched.
.EXAMPLE
./Disable-DiscordProcessObserver.ps1
.EXAMPLE
./Disable-DiscordProcessObserver.ps1 -Register
.NOTES
Windows, PowerShell 7+. Log: %LOCALAPPDATA%\discord-observer-patch.log.
Prior art: BetterDiscord DoNotTrack (zerebos/BetterDiscordAddons) and Vesktop
stub setObservedGamesCallback the same way.
#>
[CmdletBinding(DefaultParameterSetName = 'Once')]
param (
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'Discord'),
    [Parameter(ParameterSetName = 'Watch')] [switch]$Watch,
    [Parameter(ParameterSetName = 'Register')] [switch]$Register,
    [Parameter(ParameterSetName = 'Unregister')] [switch]$Unregister
)
$ErrorActionPreference = 'Stop'
$taskName = 'Discord process observer patch'
$logPath = Join-Path $env:LOCALAPPDATA 'discord-observer-patch.log'
$marker = '// local patch: turn off the process observer'
$anchor = "const nativeUtils = require('./discord_utils.node');"
$patch = @"
$marker (game detection and exe fingerprinting)
for (const name of [
    'setObservedGamesCallback',
    'setObservedGamesCallback2',
    'setCandidateGamesCallback',
    'setGameDetectionCallback',
    'setGameCandidateOverrides',
    'setProcessObserverCollectExecutableFingerprint',
    'setProcessObserverSteamSkuDetection',
    'setProcessObserverUserId',
    'setRobloxSubgameDetectionConfig',
    'getExecutableFingerprintForProcess',
    'startGameEvents',
]) {
    if (typeof nativeUtils[name] === 'function') {
        nativeUtils[name] = () => undefined;
    }
}
console.log('discord_utils local patch: process observer disabled');
"@

function Write-PatchLog {
    param ([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $logPath -Value $line
    Write-Verbose $line
}

function Set-ObserverPatch {
    <#
    .SYNOPSIS
    Patches every unpatched discord_utils index.js under the root; one result per file.
    #>
    param ([string]$Root)
    $files = @(Get-ChildItem -Path (Join-Path $Root 'app-*\modules\discord_utils-*\discord_utils\index.js') -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        $text = [System.IO.File]::ReadAllText($file.FullName)
        $status = if ($text.Contains($marker)) {
            'already patched'
        }
        elseif (-not $text.Contains($anchor)) {
            Write-PatchLog "anchor line missing, not patched: $($file.FullName)"
            'anchor missing'
        }
        else {
            $original = "$($file.FullName).orig"
            if (-not (Test-Path -LiteralPath $original)) {
                Copy-Item -LiteralPath $file.FullName -Destination $original
            }
            $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
            $index = $text.IndexOf($anchor) + $anchor.Length
            $block = $newline + ($patch -replace "`r?`n", $newline)
            [System.IO.File]::WriteAllText($file.FullName, $text.Insert($index, $block))
            Write-PatchLog "patched: $($file.FullName)"
            'patched'
        }
        [pscustomobject][ordered]@{ Status = $status; Path = $file.FullName }
    }
}

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed task '$taskName'."
    return
}

if ($Register) {
    $pwsh = (Get-Command pwsh).Source
    $arguments = '-NoProfile -WindowStyle Hidden -File "{0}" -Watch' -f $PSCommandPath
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Host "Registered and started task '$taskName'."
    return
}

Set-ObserverPatch -Root $Root
if (-not $Watch) { return }

Write-PatchLog "watching $Root"
$watcher = [System.IO.FileSystemWatcher]::new($Root, 'index.js')
$watcher.IncludeSubdirectories = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite, DirectoryName'
while ($true) {
    # Wakes on any index.js written under Discord, or after a minute regardless.
    $null = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 60000)
    Start-Sleep -Milliseconds 500
    try { $null = Set-ObserverPatch -Root $Root }
    catch { Write-PatchLog "error: $($_.Exception.Message)" }
}
