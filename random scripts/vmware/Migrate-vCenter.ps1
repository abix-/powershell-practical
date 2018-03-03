[cmdletbinding()]
Param (
    [Parameter(ParameterSetName="server")][Parameter(ParameterSetName="cluster")]$SourcevCenter = "my-vcenter.domain.local",
    [Parameter(ParameterSetName="server")][Parameter(ParameterSetName="cluster")]$DestvCenter = "jaxf-vc101.domain.local",
    [Parameter(ParameterSetName="server",Mandatory=$true)]$server,
    [Parameter(ParameterSetName="cluster",Mandatory=$true)]$cluster
)

#things done by script
#create: vss for each dvs, and matching port groups on the vss
#migrate: vmk interfaces twice
#modify: network configuration for every vm twice

function drawMenu($servers) {
    Clear-Host
    $scriptPath = (Get-Location).Path
    Write-Host "Source vCenter:`t`t$SourcevCenter"
    Write-Host "Destination vCenter:`t$DestvCenter"
    Write-Host "VM Hosts to migrate: " -NoNewline
    foreach($_s in $servers) { Write-Host "$_s " -NoNewline }
    Write-Host ""; Write-Host ""
    Write-Host "Current Host:`t$currentHost"
    if($lastoption) { Write-Host "Last option:`t$lastoption" -ForegroundColor Green; Write-Host "$global:lastmessage" -ForegroundColor Green }
    Write-Host ""
    Write-Host "1. Copy DVS configuration to VSS"
    Write-Host "2. Migrate 1 uplink and VMK interfaces to VSS"
    Write-Host "3. Migrate all VMs on DVS to VSS"
    Write-Host "4. Disconnect from all DVS, remove from source vCenter, connect to new vCenter"
    Write-Host "5. Connect to DVS, add 1 uplink, and migrate VMK interfaces to DVS"
    Write-Host "6. Migrate all VMs on VSS to DVS, migrate remaining uplinks to DVS, delete VSS"
    Write-Host ""
    $option = Read-Host "1-6, next host, previous host, exit"
    $lastoption = $option 
    switch($option) {
        "1" { .\Copy-DVStoVSS.ps1 -vcenter $SourcevCenter -server $currentHost; showMessage -message $option; drawMenu $servers }
        "2" { .\MoveUplinkMgmt-DVStoVSS.ps1 -vcenter $SourcevCenter -server $currentHost; showMessage -message $option; drawMenu $servers }
        "3" { .\MoveVM-DVStoVSS.ps1 -vcenter $SourcevCenter -server $currentHost; showMessage -message $option; drawMenu $servers }
        "4" { stepFour; showMessage -message $option; drawMenu $servers }
        "5" { .\MoveUplinkMgmt-VSStoDVS.ps1 -vcenter $DestvCenter -server $currentHost; showMessage -message $option; drawMenu $servers }
        "6" { .\MoveVM-VSStoDVS.ps1 -vcenter $DestvCenter -server $currentHost; showMessage -message $option; drawMenu $servers }
        "next host" { $currentHostIndex++; $currentHost = $servers[$currentHostIndex]; $lastoption = $null; drawMenu $servers }
        "previous host" { $currentHostIndex--; $currentHost = $servers[$currentHostIndex]; $lastoption = $null; drawMenu $servers }
        "exit" { Exit }
        default { drawMenu $servers }
    }
}

function showMessage($message) {
    Write-Host ""    
    switch($message) {
        "1" { $global:lastmessage = "Confirm that VSS have been created which match the configuration of the DVS" }
        "2" { $global:lastmessage = "Confirm that 1 uplink and all VMK interfaces are on the VSS and that all datastores are still accessible" }
        "3" { $global:lastmessage = "Confirm that all VMs are on the VSS and still pingable" }
        "4" { $global:lastmessage = "Confirm that VM host is connected to new vCenter in the expected cluster" }
        #"4" { Write-Host "$currentHost - Manually disconnect from all DVS, disconnect from $SourcevCenter, and connect to $DestvCenter" -ForegroundColor Green}
        "5" { $global:lastmessage = "Confirm that all DVS have 1 uplink and all VMK interfaces are on the DVS" }
        "6" { $global:lastmessage = "Migration should be complete. Validate functionality." }
    }
    Write-Host "$currentHost - $($global:lastmessage)" -ForegroundColor Green
    Read-Host
}

function WriteHost($message,$color="White") { Write-Host "$($currentHost): $($message)" -ForegroundColor $color; if($color -eq "Red") { Exit } }

function stepFour() {
    $vmhost = $null
    $dvs = $null
    $clusterobj = $null

    try { WriteHost "Connecting to $SourcevCenter"; Connect-VIServer $SourcevCenter -ErrorAction Stop | Out-Null }
    catch { WriteHost "Failed to connect to $SourcevCenter" -color Red }

    try { WriteHost "Getting VMHost data"; $vmhost = Get-VMHost $currentHost -ErrorAction Stop; $clustername = $vmhost.Parent.Name }
    catch { WriteHost "Failed to read VMHost data" }

    try { if($vmhost) { WriteHost "Getting DVS data"; $dvs  = $vmhost | Get-VDSwitch -ErrorAction Stop | sort Name } }
    catch { WriteHost "Failed to read DVS data" }

    if($dvs) {
        WriteHost "Found $($dvs.count) DVS to remove"
        foreach($_d in $dvs) {
            WriteHost "$_d - Removing host from DVS"
            Remove-VDSwitchVMHost -VDSwitch $_d -VMHost $vmhost -Confirm:$false 
        }
    }

    if($vmhost) {
        WriteHost "Disconnecting host from $SourcevCenter"
        Set-VMHost -VMHost $vmhost -State Disconnected  -Confirm:$false
        WriteHost "Waiting for 15 seconds"; Start-Sleep -Seconds 15
        WriteHost "Removing host from $SourcevCenter"
        Remove-VMHost -VMHost $vmhost -ErrorAction Stop -Confirm:$false
        WriteHost "Waiting for 15 seconds"; Start-Sleep -Seconds 15
    }
    
    try { WriteHost "Connecting to $DestvCenter"; Connect-VIServer $DestvCenter -ErrorAction Stop | Out-Null }
    catch { WriteHost "Failed to connect to $DestvCenter" -color Red }

    
    writeHost "Getting cluster object and credentials"
    $clusterobj = Get-Cluster -Name $clustername -ErrorAction Stop
    $cred = Get-Credential -Message "$currentHost root credentials" -ErrorAction Stop
  
    if($clusterobj -and $cred) {
        Write-Host "Adding VM host to $DestvCenter in $clustername"; 
        Add-VMHost -Name $currentHost -Location $clusterobj -Credential $cred -ErrorAction Stop -Force
    } else { Write-Host "clusterobj and credentials are required to add vm hosts" }
}

$servers = @()
$currentHostIndex = 0
$lastoption = $null
$lastmessage = $null

if($cluster) {
    Connect-VIServer $SourcevCenter | Out-Null
    $servers = Get-Cluster $cluster | get-vmhost | select -expand Name | sort
} elseif($server) {
    $servers += $server
}

$currentHost = $servers[$currentHostIndex]
drawMenu $servers