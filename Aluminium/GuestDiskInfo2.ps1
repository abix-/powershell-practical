$volumes = @()
Get-WmiObject -Class win32_diskDrive | %{
    $disk = $_
    $query = "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='$($_.DeviceID)'} WHERE ResultClass=Win32_DiskPartition"

    Get-WmiObject -Query $query | %{
        $partition = $_
        $query = "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($_.DeviceID)'} WHERE ResultClass=Win32_LogicalDisk"
        
        Get-WmiObject -Query $query | %{
            $volumes += New-Object PSObject -Property @{
                SCSIBus = $disk.SCSIBus
                SCSITarget = $disk.SCSITargetID
                Label = $_.VolumeName
                DriveLetter = $_.DeviceID
                SerialNumber = $disk.SerialNumber
            }
        }
    }
}
$volumes | ConvertTo-Csv
