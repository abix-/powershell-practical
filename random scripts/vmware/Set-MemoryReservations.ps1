# Examples:
# Remove MemoryReservationLockToMax for all servers in the my-cluster cluster
# .\Set-MemoryReservations.ps1 -cluster my-cluster -remove
#
# Add MemoryReservationLockToMax for all servers in the my-cluster cluster
# .\Set-MemoryReservations.ps1 -cluster jax-devqc -add
#
# Add MemoryReservationLockToMax for all servers in the my-cluster cluster that begin with QC*
# .\Set-MemoryReservations.ps1 -cluster my-cluster -add -filter QC*
#
# The -filter option utilizes the "-like" operator and may require wildcards to product results.
# For instance..use *QC* to filter for QC in the middle of the VM name, QC* to filter for QC at the beginning
# of the VM name, and *QC to filter for QC at the end of the VM name.

[cmdletbinding()]
Param (
    [Parameter(Mandatory=$true)]
    $cluster,
    [switch]$add,
    [switch]$remove,
    $filter
)

function Set-Reservation($vm){
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    if($add) {
        $spec.memoryReservationLockedToMax = $true 
        $status = $vm.ExtensionData.ReconfigVM_Task($spec)
        Write-Host "$($vm.Name) - MemoryReservationLockToMax has been added"
    } elseif($remove) {
        $spec.memoryReservationLockedToMax = $false
        $status = $vm.ExtensionData.ReconfigVM_Task($spec)
        Write-Host "$($vm.Name) - MemoryReservationLockToMax has been removed"
    }
}

#$status = Connect-VIServer wh-vc01.domain.local
$vms = Get-Cluster $cluster | Get-VM

if($filter) {
    $vms = $vms | where{$_.Name -like $filter}
    Write-Host "The following VMs match the defined filter:"
    $vms
}

if($add -or $remove) {
    foreach($vm in $vms) {
        if($confirm -ne "A") {
            if($add) {
                if(!$vm.ExtensionData.Config.MemoryReservationLockedToMax) {
                    $confirm = Read-Host "$($vm.Name) - Add MemoryReservationLockToMax? (Y/N/A)"
                } else {
                    Write-Host "$($vm.name) - MemoryReservationLockToMax is already set"
                    $confirm = "N"
                }
            } elseif($remove) {
                if($vm.ExtensionData.Config.MemoryReservationLockedToMax) {
                    $confirm = Read-Host "$($vm.Name) - Remove MemoryReservationLockToMax? (Y/N/A)"
                } else {
                    Write-Host "$($vm.name) - MemoryReservationLockToMax is not set"
                }
            }
        }
        
        switch ($confirm) {
        "Y" {Set-Reservation $vm}
        "N" {}
        "A" {Set-Reservation $vm}
        }
    }
} else {
    Write-Host "You must add either -add or -remove when running this cmdlet"
}
