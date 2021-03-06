[cmdletbinding()]
Param (
    [Parameter(Mandatory=$true)]
    $server
)

$results = @()
$status = Connect-VIServer wh-vc01.domain.local
$vms = Get-VMHost $server | Get-VM

foreach($vm in $vms) {
    $data = New-Object PSObject -Property @{
        "Name" = $vm.Name
        "MemoryReservationLockToMax" = $vm.ExtensionData.Config.MemoryReservationLockedToMax
    }
    $results += $data
}

$results | ft