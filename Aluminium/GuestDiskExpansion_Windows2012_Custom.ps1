$SCSIBus = "0"
$SCSITarget = "3"
$ScriptFile = "C:\Temp\diskpart_script.txt"

#WMI: Determine the DriveLabel and DriveLetter from SCSIBus and SCSITarget
$volumes = @()
Get-WmiObject -Class win32_diskDrive | ?{$_.SCSIBus -eq $SCSIBus -and $_.SCSITargetID -eq $SCSITarget} | %{
    $disk = $_
    $query = "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='$($_.DeviceID)'} WHERE ResultClass=Win32_DiskPartition"

    Get-WmiObject -Query $query | %{
        $partition = $_
        $query = "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($_.DeviceID)'} WHERE ResultClass=Win32_LogicalDisk"
        
        Get-WmiObject -Query $query | %{
            $volumes += [pscustomobject][ordered]@{
                SCSIBus = $disk.SCSIBus
                SCSITarget = $disk.SCSITargetID
                DriveLabel = $_.VolumeName
                DriveLetter = $_.DeviceID -replace ":"
            }
        }
    }
}

#Proceed if 1 volume found from WMI
if($volumes.count -gt 1) {
    Write-Host "More than 1 volume found. Aborting"
    Return
} elseif($volumes.count -eq 0) {
    Write-Host "No volumes found. Aborting"
    Return
} else {
    $volume = $volumes[0]
    Write-Host "[$($SCSIBus):$($SCSITarget)] DriveLetter='$($volume.DriveLetter)'"
}

#Diskpart: Rescan disks
Write-Output "RESCAN" | Out-File $ScriptFile -Encoding utf8
$output = @(diskpart.exe /S $ScriptFile)
if($LASTEXITCODE -ne 0) {
    Write-Host "[Rescan] Diskpart returned Exit Code $LASTEXITCODE"
    return $output
} else {
    Write-Host "[Rescan] Completed successfully"
}

#Diskpart: List all disks
Write-Output "LIST DISK" | Out-File $ScriptFile -Encoding utf8
$output = @(diskpart.exe /S $ScriptFile)
if($LASTEXITCODE -ne 0) {
    Write-Host "[List Disk] Diskpart returned Exit Code $LASTEXITCODE"
    return $output
} else {
    $diskids = $output | ?{$_ -match "Disk (?<DiskID>\d+)\s+"} | %{$matches['DiskID']}
    Write-Host "[List Disk] Found $($diskids.count) disks"
}

#Diskpart: Abort if disk not found
if($diskids -notcontains $volume.SCSITarget) {
    Write-Host "[List Disk] DiskID $SCSITarget not found"
    return
}

#Diskpart: Get partitions on disk
Write-Output "SELECT DISK $($volume.SCSITarget)" | Out-File $ScriptFile -Encoding utf8
Write-Output "DETAIL DISK" | Out-File $ScriptFile -Encoding utf8 -Append
$output = @(diskpart.exe /S $ScriptFile)

#Diskpart: Use regex to parse output and get VolumeID by using DriveLetter
if($LASTEXITCODE -ne 0) {
    Write-Host "[Detail Disk] Diskpart returned Exit Code $LASTEXITCODE"
    return $output
} else {
    $diskpart_volumes = @()
    $output | ?{$_ -match "Volume (?<VolumeID>\d+)\s+(?<DriveLetter>\w)\s+(?<DriveLabel>.*) \s+NTFS"} | %{
        if($matches['DriveLetter'] -eq $volume.DriveLetter) {
            $diskpart_volumes += [pscustomobject][ordered]@{
                VolumeID = $matches['VolumeID']
                DriveLetter = $matches['DriveLetter']
                DriveLabel = $matches['DriveLabel']
            }
        }
    }
}

#Proceed if 1 volume found from DiskPart
if($diskpart_volumes.count -eq 1) {
    $diskpart_volume = $diskpart_volumes[0]
    Write-Host "[$($SCSIBus):$($SCSITarget)] VolumeID='$($diskpart_volume.VolumeID)' found at DriveLetter='$($diskpart_volume.DriveLetter)'"
} elseif($diskpart_volumes.count -gt 1) {
    Write-Host "[$($SCSIBus):$($SCSITarget)] More than 1 volume found. This is not supported. Aborting"
    return
} else {
    Write-Host "[$($SCSIBus):$($SCSITarget)] No volumes found. Aborting"
    return
}
