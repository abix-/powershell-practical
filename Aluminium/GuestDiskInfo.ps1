$volTab = @()
foreach($disk in (Get-CimInstance -ComputerName $compName -ClassName Win32_DiskDrive)){
    foreach($partition in (Get-CimAssociatedInstance -InputObject $disk -ResultClassName Win32_DiskPartition)){
        Get-CimAssociatedInstance -InputObject $partition -ResultClassName Win32_LogicalDisk | %{
            $voltab += [pscustomobject][ordered]@{
                SCSIBus = $disk.SCSIBus
                SCSIBus2 = ($disk.SCSIPort-2)
                SCSITarget = $disk.SCSiTargetID
                DriveLetter = $_.DeviceID
                Label = $_.VolumeName
                SerialNumber = $disk.SerialNumber
            }
        }
    }
}
$volTab | ConvertTo-Csv
