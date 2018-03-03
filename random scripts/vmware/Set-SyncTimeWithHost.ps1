[cmdletbinding()]
Param (
    $servers,
    [switch]$enable = $False
)

function getAllViews() {
    try { Write-Host "Querying vCenter for all views"; $VMViews = Get-View -ViewType VirtualMachine | Sort Name }
    catch { Write-Host "Failed to retreive data from vCenter. Are you connected?"; Exit }
    return $VMViews
}

if($enable -eq $False) { Write-Host "Disabling SyncTimeWithHost" }
else { Write-Host "Enabling SyncTimeWithHost" }

$VMViews = getAllViews
foreach($server in $servers) {
    Write-Host "Working on $server"
    $VMView = $VMViews | ?{$_.name -like $server}
    $VMPostConfig                          = $Null
    $VMPostConfig                          = New-Object VMware.Vim.VirtualMachineConfigSpec
    $VMPostConfig.Tools                    = New-Object VMware.Vim.ToolsConfigInfo
    $VMPostConfig.Tools.SyncTimeWithHost   = $enable
    $VMView.ReconfigVM($VMPostConfig)
}