Function Get-DatastoreMountInfo {
    <#
    .DESCRIPTION https://communities.vmware.com/docs/DOC-18008
    .NOTES  Author:  Alan Renouf
    #>
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline=$true)]
		$Datastore
	)
	Process {
		$AllInfo = @()
		if (-not $Datastore) {
			$Datastore = Get-Datastore
		}
		Foreach ($ds in $Datastore) {  
			if ($ds.ExtensionData.info.Vmfs) {
				$hostviewDSDiskName = $ds.ExtensionData.Info.vmfs.extent[0].diskname
				if ($ds.ExtensionData.Host) {
					$attachedHosts = $ds.ExtensionData.Host
					Foreach ($VMHost in $attachedHosts) {
						$hostview = Get-View $VMHost.Key
						$hostviewDSState = $VMHost.MountInfo.Mounted
						$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
						$devices = $StorageSys.StorageDeviceInfo.ScsiLun
						Foreach ($device in $devices) {
							$Info = "" | Select-Object Datastore, VMHost, Lun, Mounted, State
							if ($device.canonicalName -eq $hostviewDSDiskName) {
								$hostviewDSAttachState = ""
								if ($device.operationalState[0] -eq "ok") {
									$hostviewDSAttachState = "Attached"							
								} elseif ($device.operationalState[0] -eq "off") {
									$hostviewDSAttachState = "Detached"							
								} else {
									$hostviewDSAttachState = $device.operationalstate[0]
								}
								$Info.Datastore = $ds.Name
								$Info.Lun = $hostviewDSDiskName
								$Info.VMHost = $hostview.Name
								$Info.Mounted = $HostViewDSState
								$Info.State = $hostviewDSAttachState
								$AllInfo += $Info
							}
						}
						
					}
				}
			}
		}
		$AllInfo
	}
}

Function Invoke-DetachDatastore {
    <#
    .DESCRIPTION https://communities.vmware.com/docs/DOC-18008
    .NOTES  Author:  Alan Renouf
    #>
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline=$true)]
		$Datastore
	)
	Process {
		if (-not $Datastore) {
			Write-Host "No Datastore defined as input"
			Exit
		}
		Foreach ($ds in $Datastore) {
			$hostviewDSDiskName = $ds.ExtensionData.Info.vmfs.extent[0].Diskname
			if ($ds.ExtensionData.Host) {
				$attachedHosts = $ds.ExtensionData.Host
				Foreach ($VMHost in $attachedHosts) {
					$hostview = Get-View $VMHost.Key
					$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
					$devices = $StorageSys.StorageDeviceInfo.ScsiLun
					Foreach ($device in $devices) {
						if ($device.canonicalName -eq $hostviewDSDiskName) {
							$LunUUID = $Device.Uuid
							Write-Host "Detaching LUN $($Device.CanonicalName) from host $($hostview.Name)..."
							$StorageSys.DetachScsiLun($LunUUID);
						}
					}
				}
			}
		}
	}
}

Function Invoke-UnmountDatastore {
    <#
    .DESCRIPTION https://communities.vmware.com/docs/DOC-18008
    .NOTES  Author:  Alan Renouf
    #>
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline=$true)]
		$Datastore
	)
	Process {
		if (-not $Datastore) {
			Write-Host "No Datastore defined as input"
			Exit
		}
		Foreach ($ds in $Datastore) {
			$hostviewDSDiskName = $ds.ExtensionData.Info.vmfs.extent[0].Diskname
			if ($ds.ExtensionData.Host) {
				$attachedHosts = $ds.ExtensionData.Host
				Foreach ($VMHost in $attachedHosts) {
					$hostview = Get-View $VMHost.Key
					$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
					Write-Host "Unmounting VMFS Datastore $($DS.Name) from host $($hostview.Name)..."
					$StorageSys.UnmountVmfsVolume($DS.ExtensionData.Info.vmfs.uuid);
				}
			}
		}
	}
}

Function Invoke-MountDatastore {
    <#
    .DESCRIPTION https://communities.vmware.com/docs/DOC-18008
    .NOTES  Author:  Alan Renouf
    #>
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline=$true)]
		$Datastore
	)
	Process {
		if (-not $Datastore) {
			Write-Host "No Datastore defined as input"
			Exit
		}
		Foreach ($ds in $Datastore) {
			$hostviewDSDiskName = $ds.ExtensionData.Info.vmfs.extent[0].Diskname
			if ($ds.ExtensionData.Host) {
				$attachedHosts = $ds.ExtensionData.Host
				Foreach ($VMHost in $attachedHosts) {
					$hostview = Get-View $VMHost.Key
					$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
					Write-Host "Mounting VMFS Datastore $($DS.Name) on host $($hostview.Name)..."
					$StorageSys.MountVmfsVolume($DS.ExtensionData.Info.vmfs.uuid);
				}
			}
		}
	}
}

Function Invoke-AttachDatastore {
    <#
    .DESCRIPTION https://communities.vmware.com/docs/DOC-18008
    .NOTES  Author:  Alan Renouf
    #>
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline=$true)]
		$Datastore
	)
	Process {
		if (-not $Datastore) {
			Write-Host "No Datastore defined as input"
			Exit
		}
		Foreach ($ds in $Datastore) {
			$hostviewDSDiskName = $ds.ExtensionData.Info.vmfs.extent[0].Diskname
			if ($ds.ExtensionData.Host) {
				$attachedHosts = $ds.ExtensionData.Host
				Foreach ($VMHost in $attachedHosts) {
					$hostview = Get-View $VMHost.Key
					$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
					$devices = $StorageSys.StorageDeviceInfo.ScsiLun
					Foreach ($device in $devices) {
						if ($device.canonicalName -eq $hostviewDSDiskName) {
							$LunUUID = $Device.Uuid
							Write-Host "Attaching LUN $($Device.CanonicalName) to host $($hostview.Name)..."
							$StorageSys.AttachScsiLun($LunUUID);
						}
					}
				}
			}
		}
	}
}

function Get-FreeScsiLun {
    <#  
    .SYNOPSIS  Find free SCSI LUNs  
    .DESCRIPTION The function will find the free SCSI LUNs
      on an ESXi server
    .NOTES  Author:  Luc Dekens  
    .PARAMETER VMHost
        The VMHost where to look for the free SCSI LUNs  
    .EXAMPLE
       PS> Get-FreeScsiLun -VMHost $esx
    .EXAMPLE
       PS> Get-VMHost | Get-FreeScsiLun
    #>
    [cmdletbinding()]
    #Requires -Version 3.0
    param (
        [parameter(ValueFromPipeline = $true,Position=1)][ValidateNotNullOrEmpty()]
        [VMware.VimAutomation.Client20.VMHostImpl]$VMHost
    )

    process{
        $storMgr = Get-View $VMHost.ExtensionData.ConfigManager.DatastoreSystem
        $storMgr.QueryAvailableDisksForVmfs($null) | ForEach-Object{
            New-Object PSObject -Property @{
                VMHost = $VMHost.Name
                CanonicalName = $_.CanonicalName
                Uuid = $_.Uuid
                CapacityGB = [Math]::Round($_.Capacity.Block * $_.Capacity.BlockSize / 1GB,2)
            }
        }
    }
}

function Get-FolderPath{
    [cmdletbinding()]
    <#
    .SYNOPSIS
    Returns the folderpath for a folder
    .DESCRIPTION
    The function will return the complete folderpath for
    a given folder, optionally with the "hidden" folders
    included. The function also indicats if it is a "blue"
    or "yellow" folder.
    .NOTES
    Authors:  Luc Dekens
    .PARAMETER Folder
    On or more folders
    .PARAMETER ShowHidden
    Switch to specify if "hidden" folders should be included
    in the returned path. The default is $false.
    .EXAMPLE
    PS> Get-FolderPath -Folder (Get-Folder -Name "MyFolder")
    .EXAMPLE
    PS> Get-Folder | Get-FolderPath -ShowHidden:$true
    #>
 
    param(
        [parameter(valuefrompipeline = $true,position = 0,HelpMessage = "Enter a folder")]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.FolderImpl[]]$Folder,
        [switch]$ShowHidden = $false
    )
 
    begin{
        $excludedNames = "Datacenters","vm","host"
    }
 
    process{
        $Folder | ForEach-Object{
            $fld = $_.Extensiondata
            $fldType = "yellow"
            if($fld.ChildType -contains "VirtualMachine"){
                $fldType = "blue"
            }
            $path = $fld.Name
            $parentName = $null
            while($fld.Parent){
            $fld = Get-View $fld.Parent
            if($parentName -eq $null) { $parentName = $fld.Name }
                if((!$ShowHidden -and $excludedNames -notcontains $fld.Name) -or $ShowHidden){
                    $path = $fld.Name + "\" + $path
                }
            }
      
            $row = "" | Select-Object Name,Parent,Path,Type
            $row.Name = $_.Name
            $row.Parent = $parentName
            $row.Path = $path
            $row.Type = $fldType
            $row
        }
    }
}

function Get-VMFolderPath
{
 <#
   .Synopsis

    Get vm folder path. From Datacenter to folder that keeps the vm.

   .Description

    This function returns vm folder path. As a parameter it takes the 
	current folder in which the vm resides. This function can throw
	either 'name' or 'moref' output. Moref output can be obtained
	using the -moref switch.

	.Example

    get-vm 'vm123' | get-vmfolderpath

    Function will take folderid parameter from pipeline
	
   .Example

    get-vmfolderpath (get-vm myvm123|get-view).parent

    Function has to take as first parameter the moref of vm parent
	folder. 
	DC\VM\folfder2\folderX\vmvm123
	Parameter will be the folderX moref
	
   .Example

    get-vmfolderpath (get-vm myvm123|get-view).parent -moref

    Instead of names in output, morefs will be given.


	.Parameter folderid

    This is the moref of the parent directory for vm.Our starting
	point.Can be obtained in serveral ways. One way is to get it
	by: (get-vm 'vm123'|get-view).parent  
	or: (get-view -viewtype virtualmachine -Filter @{'name'=
	'vm123'}).parent
	
   .Parameter moref

    Add -moref when invoking function to obtain moref values

   .Notes

    NAME:  Get-VMFolderPath

    AUTHOR: Grzegorz Kulikowski

    LASTEDIT: 09/14/2012
	
	NOT WORKING ? #powercli @ irc.freenode.net 

   .Link

    http://psvmware.wordpress.com

 #>

    param(
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$folderid,
        [switch]$moref,
        $vCenter
    )

    if($vCenter) { $folderparent=get-view $folderid -Server $vCenter }
    else { $folderparent=get-view $folderid }

	if ($folderparent.name -ne 'vm'){
		if($moref){$path=$folderparent.moref.toString()+'\'+$path}
			else{
				$path=$folderparent.name+'\'+$path
			}
		if ($folderparent.parent){
			if($moref){get-vmfolderpath $folderparent.parent.tostring() -moref}
			  else{
			    get-vmfolderpath($folderparent.parent.tostring())
			  }
		}
	}else {
	if ($moref){
	return (get-view $folderparent.parent).moref.tostring()+"\"+$folderparent.moref.tostring()+"\"+$path
	}else {
			return (get-view $folderparent.parent).name.toString()+'\'+$folderparent.name.toString()+'\'+$path
	  		}
	}
}

filter ColorWord2 {
    <#
    .DESCRIPTION http://stackoverflow.com/questions/7362097/color-words-in-powershell-script-format-table-output
    .NOTES Author: stevethethread, Remko
    #>
    param(
        [string[]] $word,
        [string[]] $color
    )
    $all = $_
    $lines = ($_ -split '\r\n')

    $lines | ForEach-Object {
        $line = $_      
        $x = -1

        $word | ForEach-Object {
            $x++
            $item = $_      

            $index = $line.IndexOf($item, [System.StringComparison]::InvariantCultureIgnoreCase)                            
                while($index -ge 0){
                    Write-Host $line.Substring(0,$index) -NoNewline                 
                    Write-Host $line.Substring($index, $item.Length) -NoNewline -ForegroundColor $color[$x]
                    $used =$item.Length + $index
                    $remain = $line.Length - $used
                    $line =$line.Substring($used, $remain)
                    $index = $line.IndexOf($item, [System.StringComparison]::InvariantCultureIgnoreCase)
                }
            }
        Write-Host $line
    } 
}

filter Set-VMBIOSSetup 
{ 
   param( 
        [switch]$Disable, 
        [switch]$PassThru 
   )
   if($_ -is [VMware.VimAutomation.Types.VirtualMachine]) 
    { 
       trap { throw $_ }        
        
       $vmbo = New-Object VMware.Vim.VirtualMachineBootOptions 
       $vmbo.EnterBIOSSetup = $true 
        
       if($Disable) 
        { 
           $vmbo.EnterBIOSSetup = $false 
        } 

       $vmcs = New-Object VMware.Vim.VirtualMachineConfigSpec 
       $vmcs.BootOptions = $vmbo 

        ($_ | Get-View).ReconfigVM($vmcs) 
        
       if($PassThru) 
        { 
           Get-VM $_ 
        } 
    } 
   else 
    { 
       Write-Error “Wrong object type. Only virtual machine objects are allowed.“ 
    } 
}

function SwitchGuestToolsVersion($version) {
    <#
    .DESCRIPTION http://blog.igics.com/2016/11/powercli-script-to-report-vmtools.html
    #>
    Switch ($version) {  
        7302 {$GuestToolsVersion = "7.4.6"}  
        7303 {$GuestToolsVersion = "7.4.7"}  
        7304 {$GuestToolsVersion = "7.4.8"}  
        8192 {$GuestToolsVersion = "8.0.0"}  
        8194 {$GuestToolsVersion = "8.0.2"}  
        8195 {$GuestToolsVersion = "8.0.3"}  
        8196 {$GuestToolsVersion = "8.0.4"}  
        8197 {$GuestToolsVersion = "8.0.5"}  
        8198 {$GuestToolsVersion = "8.0.6"}  
        8199 {$GuestToolsVersion = "8.0.7"}  
        8290 {$GuestToolsVersion = "8.3.2"}  
        8295 {$GuestToolsVersion = "8.3.7"}  
        8300 {$GuestToolsVersion = "8.3.12"}  
        8305 {$GuestToolsVersion = "8.3.17"}  
        8306 {$GuestToolsVersion = "8.3.18"}  
        8307 {$GuestToolsVersion = "8.3.19"}  
        8384 {$GuestToolsVersion = "8.6.0"}  
        8389 {$GuestToolsVersion = "8.6.5"}  
        8394 {$GuestToolsVersion = "8.6.10"}  
        8395 {$GuestToolsVersion = "8.6.11"}  
        8396 {$GuestToolsVersion = "8.6.12"}  
        8397 {$GuestToolsVersion = "8.6.13"}  
        8398 {$GuestToolsVersion = "8.6.14"}  
        8399 {$GuestToolsVersion = "8.6.15"}  
        8400 {$GuestToolsVersion = "8.6.16"}  
        8401 {$GuestToolsVersion = "8.6.17"}  
        9216 {$GuestToolsVersion = "9.0.0"}  
        9217 {$GuestToolsVersion = "9.0.1"}  
        9221 {$GuestToolsVersion = "9.0.5"}  
        9226 {$GuestToolsVersion = "9.0.10"}  
        9227 {$GuestToolsVersion = "9.0.11"}  
        9228 {$GuestToolsVersion = "9.0.12"}  
        9229 {$GuestToolsVersion = "9.0.13"}  
        9231 {$GuestToolsVersion = "9.0.15"}  
        9232 {$GuestToolsVersion = "9.0.16"}  
        9233 {$GuestToolsVersion = "9.0.17"}  
        9344 {$GuestToolsVersion = "9.4.0"}  
        9349 {$GuestToolsVersion = "9.4.5"}  
        9350 {$GuestToolsVersion = "9.4.6"}  
        9354 {$GuestToolsVersion = "9.4.10"}  
        9355 {$GuestToolsVersion = "9.4.11"}  
        9356 {$GuestToolsVersion = "9.4.12"}  
        9359 {$GuestToolsVersion = "9.4.15"}  
        9536 {$GuestToolsVersion = "9.10.0"}  
        9537 {$GuestToolsVersion = "9.10.1"}  
        9541 {$GuestToolsVersion = "9.10.5"}  
        10240 {$GuestToolsVersion = "10.0.0"}  
        10245 {$GuestToolsVersion = "10.0.5"}  
        10246 {$GuestToolsVersion = "10.0.6"}  
        10247 {$GuestToolsVersion = "10.0.8"}  
        10249 {$GuestToolsVersion = "10.0.9"}  
        10252 {$GuestToolsVersion = "10.0.12"}  
        10272 {$GuestToolsVersion = "10.1.0"}  
        0   {$GuestToolsVersion = "Not installed"}  
        2147483647 {$GuestToolsVersion = "3rd party"}  
        default {$GuestToolsVersion = "Unknown"}  
    }

    return $GuestToolsVersion
}
