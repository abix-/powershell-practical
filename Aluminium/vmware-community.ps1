function Get-DatastoreMountInfo {
    <#
    .SYNOPSIS 
    Gets the Mounted State and Attached State of a Datastore for all VMHosts it is seen by
    .NOTES 
    Author: Alan Renouf
    .LINK 
    https://communities.vmware.com/docs/DOC-18008
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
    .SYNOPSIS
    Detaches a Datastore from all VMHosts is seen by
    .NOTES  
    Author: Alan Renouf
    .LINK 
    https://communities.vmware.com/docs/DOC-18008
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
    .SYNOPSIS
    Unmounts a Datastore from all VMHosts is seen by
    .NOTES  
    Author: Alan Renouf
    .LINK 
    https://communities.vmware.com/docs/DOC-18008
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
    .SYNOPSIS
    Mounts a Datastore on all VMHosts is seen by
    .NOTES  
    Author: Alan Renouf
    .LINK 
    https://communities.vmware.com/docs/DOC-18008
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
    .SYNOPSIS
    Attaches a Datastore on all VMHosts is seen by
    .NOTES  
    Author: Alan Renouf
    .LINK 
    https://communities.vmware.com/docs/DOC-18008
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
    .SYNOPSIS  
    Find free SCSI LUNs on an ESXi server
    .NOTES
    Author: Luc Dekens  
    .PARAMETER VMHost
    The VMHost where to look for the free SCSI LUNs  
    .EXAMPLE
    PS> Get-FreeScsiLun -VMHost $esx
    .EXAMPLE
    PS> Get-VMHost | Get-FreeScsiLun
    .LINK
    http://www.lucd.info/2013/01/15/find-free-scsi-luns/
    #>
    [cmdletbinding()]
    #Requires -Version 3.0
    param (
        [parameter(ValueFromPipeline = $true,Position=1)][ValidateNotNullOrEmpty()]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
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

function Get-FolderPath {
    <#
    .SYNOPSIS
    Returns the folderpath for a folder
    .DESCRIPTION
    The function will return the complete folderpath for
    a given folder, optionally with the "hidden" folders
    included. The function also indicats if it is a "blue"
    or "yellow" folder.
    .NOTES
    Author: Luc Dekens
    .PARAMETER Folder
    On or more folders
    .PARAMETER ShowHidden
    Switch to specify if "hidden" folders should be included
    in the returned path. The default is $false.
    .EXAMPLE
    PS> Get-FolderPath -Folder (Get-Folder -Name "MyFolder")
    .EXAMPLE
    PS> Get-Folder | Get-FolderPath -ShowHidden:$true
    .LINK
    http://www.lucd.info/2010/10/21/get-the-folderpath/
    #>
    [cmdletbinding()]
    param(
        [parameter(valuefrompipeline = $true,position = 0,HelpMessage = "Enter a folder")]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Folder[]]$Folder,
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

function Get-VMFolderPath {
    <#
    .SYNOPSIS
    Get vm folder path. From Datacenter to folder that keeps the vm.
    .DESCRIPTION
    This function returns vm folder path. As a parameter it takes the 
	current folder in which the vm resides. This function can throw
	either 'name' or 'moref' output. Moref output can be obtained
	using the -moref switch.
    .EXAMPLE
    get-vm 'vm123' | get-vmfolderpath
    Function will take folderid parameter from pipeline
    .EXAMPLE
    get-vmfolderpath (get-vm myvm123|get-view).parent
    Function has to take as first parameter the moref of vm parent
	folder. 
	DC\VM\folfder2\folderX\vmvm123
	Parameter will be the folderX moref
    .EXAMPLE
    get-vmfolderpath (get-vm myvm123|get-view).parent -moref
    Instead of names in output, morefs will be given.
	.PARAMETER folderid
    This is the moref of the parent directory for vm.Our starting
	point.Can be obtained in serveral ways. One way is to get it
	by: (get-vm 'vm123'|get-view).parent  
	or: (get-view -viewtype virtualmachine -Filter @{'name'=
	'vm123'}).parent
    .PARAMETER moref
    Add -moref when invoking function to obtain moref values
    .NOTES
    AUTHOR: Grzegorz Kulikowski
    LAST EDIT: 09/14/2012
	NOT WORKING ? #powercli @ irc.freenode.net 
    .LINK
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
    .SYNOPSIS
    Colors words from pipeline input
    .NOTES 
    Author: stevethethread, Remko
    .LINK
    http://stackoverflow.com/questions/7362097/color-words-in-powershell-script-format-table-output
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

filter Set-VMBIOSSetup {
    <#
    .SYNOPSIS
    Force a VM to enter BIOS setup screen on next reboot
    .NOTES
    Author: Shay Levy
    .LINK
    http://blogs.microsoft.co.il/scriptfanatic/2009/08/27/force-a-vm-to-enter-bios-setup-screen-on-next-reboot/
    #>
   param( 
        [switch]$Disable, 
        [switch]$PassThru 
   )
   if($_ -is [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]) 
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
    .SYNOPSIS
    Determines the VMware Tools version from the value reported by Get-View
    .NOTES
    Author: David Pasek
    .LINK
    http://blog.igics.com/2016/11/powercli-script-to-report-vmtools.html
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
        10277 {$GuestToolsVersion = "10.1.5"}  
        0   {$GuestToolsVersion = "Not installed"}  
        2147483647 {$GuestToolsVersion = "3rd party"}  
        default {$GuestToolsVersion = "Unknown"}  
    }
    return $GuestToolsVersion
}


function UnixToPsDate([int]$UnixTime){
    [System.DateTimeOffset]::FromUnixTimeSeconds($UnixTime).datetime.tolocaltime()
}

Function Get-NtpTime {

<#
.Synopsis
   Gets (Simple) Network Time Protocol time (SNTP/NTP, rfc-1305, rfc-2030) from a specified server
.DESCRIPTION
   This function connects to an NTP server on UDP port 123 and retrieves the current NTP time.
   Selected components of the returned time information are decoded and returned in a PSObject.
.PARAMETER Server
   The NTP Server to contact.  Uses pool.ntp.org by default.
.PARAMETER MaxOffset
   The maximum acceptable offset between the local clock and the NTP Server, in milliseconds.
   The script will throw an exception if the time difference exceeds this value (on the assumption
   that the returned time may be incorrect).  Default = 10000 (10s).
.PARAMETER NoDns
   (Switch) If specified do not attempt to resolve Version 3 Secondary Server ReferenceIdentifiers.
.EXAMPLE
   Get-NtpTime uk.pool.ntp.org
   Gets time from the specified server.
.EXAMPLE
   Get-NtpTime | fl *
   Get time from default server (pool.ntp.org) and displays all output object attributes.
.OUTPUTS
   A PSObject containing decoded values from the NTP server.  Pipe to fl * to see all attributes.
.FUNCTIONALITY
   Gets NTP time from a specified server.
#>

    [CmdletBinding()]
    [OutputType()]
    Param (
        [String]$Server = 'pool.ntp.org',
        [Int]$MaxOffset = 10000,     # (Milliseconds) Throw exception if network time offset is larger
        [Switch]$NoDns               # Do not attempt to lookup V3 secondary-server referenceIdentifier
    )


    # NTP Times are all UTC and are relative to midnight on 1/1/1900
    $StartOfEpoch=New-Object DateTime(1900,1,1,0,0,0,[DateTimeKind]::Utc)   


    Function OffsetToLocal($Offset) {
    # Convert milliseconds since midnight on 1/1/1900 to local time
        $StartOfEpoch.AddMilliseconds($Offset).ToLocalTime()
    }


    # Construct a 48-byte client NTP time packet to send to the specified server
    # (Request Header: [00=No Leap Warning; 011=Version 3; 011=Client Mode]; 00011011 = 0x1B)

    [Byte[]]$NtpData = ,0 * 48
    $NtpData[0] = 0x1B    # NTP Request header in first byte


    $Socket = New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork,
                                            [Net.Sockets.SocketType]::Dgram,
                                            [Net.Sockets.ProtocolType]::Udp)
    $Socket.SendTimeOut = 2000  # ms
    $Socket.ReceiveTimeOut = 2000   # ms

    Try {
        $Socket.Connect($Server,123)
    }
    Catch {
        Write-Error "Failed to connect to server $Server"
        Throw 
    }


# NTP Transaction -------------------------------------------------------

        $t1 = Get-Date    # t1, Start time of transaction... 
    
        Try {
            [Void]$Socket.Send($NtpData)
            [Void]$Socket.Receive($NtpData)  
        }
        Catch {
            Write-Error "Failed to communicate with server $Server"
            Throw
        }

        $t4 = Get-Date    # End of NTP transaction time

# End of NTP Transaction ------------------------------------------------

    $Socket.Shutdown("Both") 
    $Socket.Close()

# We now have an NTP response packet in $NtpData to decode.  Start with the LI flag
# as this is used to indicate errors as well as leap-second information

    # Check the Leap Indicator (LI) flag for an alarm condition - extract the flag
    # from the first byte in the packet by masking and shifting 

    $LI = ($NtpData[0] -band 0xC0) -shr 6    # Leap Second indicator
    If ($LI -eq 3) {
        Throw 'Alarm condition from server (clock not synchronized)'
    } 

    # Decode the 64-bit NTP times

    # The NTP time is the number of seconds since 1/1/1900 and is split into an 
    # integer part (top 32 bits) and a fractional part, multipled by 2^32, in the 
    # bottom 32 bits.

    # Convert Integer and Fractional parts of the (64-bit) t3 NTP time from the byte array
    $IntPart = [BitConverter]::ToUInt32($NtpData[43..40],0)
    $FracPart = [BitConverter]::ToUInt32($NtpData[47..44],0)

    # Convert to Millseconds (convert fractional part by dividing value by 2^32)
    $t3ms = $IntPart * 1000 + ($FracPart * 1000 / 0x100000000)

    # Perform the same calculations for t2 (in bytes [32..39]) 
    $IntPart = [BitConverter]::ToUInt32($NtpData[35..32],0)
    $FracPart = [BitConverter]::ToUInt32($NtpData[39..36],0)
    $t2ms = $IntPart * 1000 + ($FracPart * 1000 / 0x100000000)

    # Calculate values for t1 and t4 as milliseconds since 1/1/1900 (NTP format)
    $t1ms = ([TimeZoneInfo]::ConvertTimeToUtc($t1) - $StartOfEpoch).TotalMilliseconds
    $t4ms = ([TimeZoneInfo]::ConvertTimeToUtc($t4) - $StartOfEpoch).TotalMilliseconds
 
    # Calculate the NTP Offset and Delay values
    $Offset = (($t2ms - $t1ms) + ($t3ms-$t4ms))/2
    $Delay = ($t4ms - $t1ms) - ($t3ms - $t2ms)

    # Make sure the result looks sane...
    If ([Math]::Abs($Offset) -gt $MaxOffset) {
        # Network server time is too different from local time
        Throw "Network time offset exceeds maximum ($($MaxOffset)ms)"
    }

    # Decode other useful parts of the received NTP time packet

    # We already have the Leap Indicator (LI) flag.  Now extract the remaining data
    # flags (NTP Version, Server Mode) from the first byte by masking and shifting (dividing)

    $LI_text = Switch ($LI) {
        0    {'no warning'}
        1    {'last minute has 61 seconds'}
        2    {'last minute has 59 seconds'}
        3    {'alarm condition (clock not synchronized)'}
    }

    $VN = ($NtpData[0] -band 0x38) -shr 3    # Server version number

    $Mode = ($NtpData[0] -band 0x07)     # Server mode (probably 'server')
    $Mode_text = Switch ($Mode) {
        0    {'reserved'}
        1    {'symmetric active'}
        2    {'symmetric passive'}
        3    {'client'}
        4    {'server'}
        5    {'broadcast'}
        6    {'reserved for NTP control message'}
        7    {'reserved for private use'}
    }

    # Other NTP information (Stratum, PollInterval, Precision)

    $Stratum = [UInt16]$NtpData[1]   # Actually [UInt8] but we don't have one of those...
    $Stratum_text = Switch ($Stratum) {
        0                            {'unspecified or unavailable'}
        1                            {'primary reference (e.g., radio clock)'}
        {$_ -ge 2 -and $_ -le 15}    {'secondary reference (via NTP or SNTP)'}
        {$_ -ge 16}                  {'reserved'}
    }

    $PollInterval = $NtpData[2]              # Poll interval - to neareast power of 2
    $PollIntervalSeconds = [Math]::Pow(2, $PollInterval)

    $PrecisionBits = $NtpData[3]      # Precision in seconds to nearest power of 2
    # ...this is a signed 8-bit int
    If ($PrecisionBits -band 0x80) {    # ? negative (top bit set)
        [Int]$Precision = $PrecisionBits -bor 0xFFFFFFE0    # Sign extend
    } else {
        # ..this is unlikely - indicates a precision of less than 1 second
        [Int]$Precision = $PrecisionBits   # top bit clear - just use positive value
    }
    $PrecisionSeconds = [Math]::Pow(2, $Precision)
    

<# Reference Identifier, notes: 

   This is a 32-bit bitstring identifying the particular reference source. 
   
   In the case of NTP Version 3 or Version 4 stratum-0 (unspecified) or 
   stratum-1 (primary) servers, this is a four-character ASCII string, 
   left justified and zero padded to 32 bits. NTP primary (stratum 1) 
   servers should set this field to a code identifying the external reference 
   source according to the following list. If the external reference is one 
   of those listed, the associated code should be used. Codes for sources not
   listed can be contrived as appropriate.

      Code     External Reference Source
      ----------------------------------------------------------------
      LOCL     uncalibrated local clock used as a primary reference for
               a subnet without external means of synchronization
      PPS      atomic clock or other pulse-per-second source
               individually calibrated to national standards
      DCF      Mainflingen (Germany) Radio 77.5 kHz
      MSF      Rugby (UK) Radio 60 kHz
      GPS      Global Positioning Service
   
   In NTP Version 3 secondary servers, this is the 32-bit IPv4 address of the 
   reference source. 
   
   In NTP Version 4 secondary servers, this is the low order 32 bits of the 
   latest transmit timestamp of the reference source. 

#>

    # Determine the format of the ReferenceIdentifier field and decode
    
    If ($Stratum -le 1) {
        # Response from Primary Server.  RefId is ASCII string describing source
        $ReferenceIdentifier = [String]([Char[]]$NtpData[12..15] -join '')
    }
    Else {

        # Response from Secondary Server; determine server version and decode

        Switch ($VN) {
            3       {
                        # Version 3 Secondary Server, RefId = IPv4 address of reference source
                        $ReferenceIdentifier = $NtpData[12..15] -join '.'

                        If (-Not $NoDns) {
                            If ($DnsLookup =  Resolve-DnsName $ReferenceIdentifier -QuickTimeout -ErrorAction SilentlyContinue) {
                                $ReferenceIdentifier = "$ReferenceIdentifier <$($DnsLookup.NameHost)>"
                            }
                        }
                        Break
                    }

            4       {
                        # Version 4 Secondary Server, RefId = low-order 32-bits of  
                        # latest transmit time of reference source
                        $ReferenceIdentifier = [BitConverter]::ToUInt32($NtpData[15..12],0) * 1000 / 0x100000000
                        Break
                    }

            Default {
                        # Unhandled NTP version...
                        $ReferenceIdentifier = $Null
                    }
        }
    }


    # Calculate Root Delay and Root Dispersion values
    
    $RootDelay = [BitConverter]::ToInt32($NtpData[7..4],0) / 0x10000
    $RootDispersion = [BitConverter]::ToUInt32($NtpData[11..8],0) / 0x10000


    # Finally, create output object and return

    $NtpTimeObj = [PSCustomObject]@{
        NtpServer = $Server
        NtpTime = OffsetToLocal($t4ms + $Offset)
        NtpTimeUTC = (OffsetToLocal($t4ms + $Offset)).ToUniversalTime()
        Offset = $Offset
        OffsetSeconds = [Math]::Round($Offset/1000, 3)
        Delay = $Delay
        t1ms = $t1ms
        t2ms = $t2ms
        t3ms = $t3ms
        t4ms = $t4ms
        t1 = OffsetToLocal($t1ms)
        t2 = OffsetToLocal($t2ms)
        t3 = OffsetToLocal($t3ms)
        t4 = OffsetToLocal($t4ms)
        LI = $LI
        LI_text = $LI_text
        NtpVersionNumber = $VN
        Mode = $Mode
        Mode_text = $Mode_text
        Stratum = $Stratum
        Stratum_text = $Stratum_text
        PollIntervalRaw = $PollInterval
        PollInterval = New-Object TimeSpan(0,0,$PollIntervalSeconds)
        Precision = $Precision
        PrecisionSeconds = $PrecisionSeconds
        ReferenceIdentifier = $ReferenceIdentifier
        RootDelay = $RootDelay
        RootDispersion = $RootDispersion
        Raw = $NtpData   # The undecoded bytes returned from the NTP server
    }

    # Set the default display properties for the returned object
    [String[]]$DefaultProperties =  'NtpServer', 'NtpTime', 'NtpTimeUtc', 'OffsetSeconds', 'NtpVersionNumber', 
                                    'Mode_text', 'Stratum', 'ReferenceIdentifier'

    # Create the PSStandardMembers.DefaultDisplayPropertySet member
    $ddps = New-Object Management.Automation.PSPropertySet('DefaultDisplayPropertySet', $DefaultProperties)

    # Attach default display property set and output object
    $PSStandardMembers = [Management.Automation.PSMemberInfo[]]$ddps 
    $NtpTimeObj | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value $PSStandardMembers -PassThru
}

function Find-ThinDisk {
<#
.SYNOPSIS
Returns all virtual disks that are Thin
.DESCRIPTION
The function returns all the Thin disks it finds on the datastore(s)
passed to the function
.NOTES
Authors:	Luc Dekens
.PARAMETER Datastore
On or more datastore objects returned by Get-Datastore
.PARAMETER Thin
If this switch is $true, only Thin virtual disks are returned. If the
switch is set to $false, all non-Thin virtual disks are returned.
.EXAMPLE
PS> Get-Datastore | Find-ThinDisk
.EXAMPLE
PS> Find-ThinDisk -Datastore (Get-Datastore -Name "DS*")
#>
param(
[parameter(valuefrompipeline = $true, mandatory = $true,
HelpMessage = "Enter a datastore")]
[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.DatastoreImpl[]]$Datastore,
[switch]$Thin = $true
)
begin{
if((Get-PowerCLIVersion).Build -lt 264274){
Write-Error "The script requires at least PowerCLI 4.1 !"
exit
}
$searchspec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
$query = New-Object VMware.Vim.VmDiskFileQuery
$query.Details = New-Object VMware.Vim.VmDiskFileQueryFlags
$query.Details.capacityKb = $true
$query.Details.controllerType = $true
$query.Details.diskExtents = $true
$query.Details.diskType = $true
$query.Details.hardwareVersion = $true
$query.Details.thin = $true
$query.Filter = New-Object VMware.Vim.VmDiskFileQueryFilter
$query.Filter.Thin = $Thin
$searchspec.Query += $query
}
process{
$Datastore | %{
$dsBrowser = Get-View $_.Extensiondata.Browser
$datastorepath = "[" + $_.Name + "]"
$taskMoRef = $dsBrowser.SearchDatastoreSubFolders_Task($datastorePath, $searchSpec)
$task = Get-View $taskMoRef
while ("running","queued" -contains $task.Info.State){
$task.UpdateViewData("Info.State")
}
$task.UpdateViewData("Info.Result")
if($task.Info.Result){
foreach ($folder in $task.Info.Result){
if($folder.File){
foreach($file in $folder.File){
$record = "" | Select DSName,Path,VmdkName
$record.DSName = $_.Name
$record.Path = $folder.FolderPath
$record.VmdkName = $file.Path
$record
}
}
}
}
}
}
}

function Get-VMHostIODevice {
    #Highly copied from
    #https://www.powershellgallery.com/packages/vDocumentation/2.0.0/Content/Public%5CGet-ESXIODevice.ps1
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost,
        [switch]$export = $false
    )

    begin {
        $results = @()
    }

    process {
        Write-Host "Working on $($VMHost.Name)"
        $esxcli2 = Get-EsxCli -VMHost $VMHost.Name -v2

        $pciDevices = $esxcli2.hardware.pci.list.Invoke() | ?{$_.VMKernelName -match "(vmnic.*|vmhba.*)" -and $_.DeviceName -notlike "*Smart Array*"} | Sort-Object -Property VMKernelName

        foreach($pciDevice in $pciDevices) {
            $device = $vmhost | Get-VMHostPciDevice | Where-Object { $pciDevice.Address -match $_.Id }
            Write-Verbose -Message ((Get-Date -Format G) + "`tGet driver version for: " + $pciDevice.ModuleName)
            $driverVersion = $esxcli2.system.module.get.Invoke(@{module = $pciDevice.ModuleName}) | Select-Object -ExpandProperty Version

            if ($pciDevice.VMKernelName -like 'vmnic*') {
                #Get NIC Firmware version 
                Write-Verbose -Message ((Get-Date -Format G) + "`tGet Firmware version for: " + $pciDevice.VMKernelName)
                $vmnicDetail = $esxcli2.network.nic.get.Invoke(@{nicname = $pciDevice.VMKernelName})
                $firmwareVersion = $vmnicDetail.DriverInfo.FirmwareVersion

                #Get NIC driver VIB package version 
                $driverVib = $esxcli2.software.vib.list.Invoke() | Select-Object -Property Name, Version | Where-Object {$_.Name -eq $vmnicDetail.DriverInfo.Driver -or $_.Name -eq "net-" + $vmnicDetail.DriverInfo.Driver -or $_.Name -eq "net55-" + $vmnicDetail.DriverInfo.Driver}
                $vibName = $driverVib.Name
                $vibVersion = $driverVib.Version
            } elseif ($pciDevice.VMKernelName -like 'vmhba*') {
                if ($pciDevice.DeviceName -match "smart array") {
                    Write-Verbose -Message ((Get-Date -Format G) + "`tGet Firmware version for: " + $pciDevice.VMKernelName)
                    $hpsa = $vmhost.ExtensionData.Runtime.HealthSystemRuntime.SystemHealthInfo.NumericSensorInfo | Where-Object {$_.Name -match "HP Smart Array"}
                    $firmwareVersion = (($hpsa.Name -split "firmware")[1]).Trim()
                }
                else {
                    Write-Verbose -Message ((Get-Date -Format G) + "`tSkip Firmware version check for: " + $pciDevice.DeviceName)
                    $firmwareVersion = $null
                }
            } #END if/ese

            $cluster = $VMHost | Get-Cluster

            $results += [pscustomobject][ordered]@{
                Cluster = $cluster.Name
                VMHost = $VMHost.Name
                VMKernel = $pciDevice.VMKernelName
                Device = $pciDevice.DeviceName
                VID = $device.VendorID
                DID = $device.DeviceID
                SVID = $device.SubVendorID
                SDID = $device.SubDeviceID
                "Firmware Version" = $firmwareVersion
                Driver = $pciDevice.ModuleName
                "Driver Version" = $driverVersion
                Vendor = $pciDevice.VendorName
                Slot = $pciDevice.SlotDescription
            }
        }
    }

    end {
        $results | Sort VMHost,SlotDescription
        if($export) { Export-Results -Results $results -ExportName Get-VMHostIODevice -excel }

    }
}

function Get-VMHostiSCSIBinding {
<#
    .SYNOPSIS
    Function to get the iSCSI Binding of a VMHost.
    
    .DESCRIPTION
    Function to get the iSCSI Binding of a VMHost.
    
    .PARAMETER VMHost
    VMHost to get iSCSI Binding for.

    .PARAMETER HBA
    HBA to use for iSCSI

    .INPUTS
    String.
    System.Management.Automation.PSObject.

    .OUTPUTS
    VMware.VimAutomation.ViCore.Impl.V1.EsxCli.EsxCliObjectImpl.

    .EXAMPLE
    PS> Get-VMHostiSCSIBinding -VMHost ESXi01 -HBA "vmhba32"
    
    .EXAMPLE
    PS> Get-VMHost ESXi01,ESXi02 | Get-VMHostiSCSIBinding -HBA "vmhba32"
    #https://raw.githubusercontent.com/jonathanmedd/PowerCLITools/master/Functions/Get-VMHostiSCSIBinding.psm1
#>
[CmdletBinding()][OutputType('VMware.VimAutomation.ViCore.Impl.V1.EsxCli.EsxCliObjectImpl')]

    Param
    (

    [parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [ValidateNotNullOrEmpty()]
    [PSObject[]]$VMHost,

    
    [parameter(Mandatory=$true,ValueFromPipeline=$false)]
    [ValidateNotNullOrEmpty()]
    [String]$HBA
    )    

    begin {

    }
    
    process {    
    
        foreach ($ESXiHost in $VMHost){

            try {            

                if ($ESXiHost.GetType().Name -eq "string"){
                
                    try {
						$ESXiHost = Get-VMHost $ESXiHost -ErrorAction Stop
					}
					catch [Exception]{
						Write-Warning "VMHost $ESXiHost does not exist"
					}
                }
                
                elseif ($ESXiHost -isnot [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]){
					Write-Warning "You did not pass a string or a VMHost object"
					Return
				}                
            
                # --- Check for the iSCSI HBA
                try {

                    $iSCSIHBA = $ESXiHost | Get-VMHostHba -Device $HBA -Type iSCSI -ErrorAction Stop
                }
                catch [Exception]{

                    Write-Warning "Specified iSCSI HBA does not exist for $ESXIHost"
                    Return
                }

                # --- Set the iSCSI Binding via ESXCli
                Write-Verbose "Getting iSCSI Binding for $ESXiHost"
                $ESXCli = Get-EsxCli -VMHost $ESXiHost                

                $ESXCli.iscsi.networkportal.list($HBA)
            }
            catch [Exception]{
        
                throw "Unable to get iSCSI Binding config"
            }
        }   
    }
    end {
        
    }
}


function Disable-KeepVMDKsTogether {
    [cmdletbinding()]
    param (
        $DatastoreCluster
    )

    #https://communities.vmware.com/thread/528775

    #dscName = 'MyDSC'

    if($DatastoreCluster -eq "all") {
        $DatastoreCluster = @(get-datastorecluster | ?{$_.name -notlike "*actifio*"} | Select-Object -expand name)
    }

    foreach($_DSC in $DatastoreCluster) {
        write-host "Working on $_DSC"
        $spec = New-Object VMware.Vim.StorageDrsConfigSpec

        $dsc = Get-DatastoreCluster -Name $_DSC
        $dsc | Get-VM | %{

            $vm = New-Object VMware.Vim.StorageDrsVmConfigSpec
            $vm.Operation = 'edit'
            $vm.Info = New-Object VMware.Vim.StorageDrsVmConfigInfo
            $vm.Info.vm = $_.ExtensionData.MoRef
            $vm.Info.Enabled = $true
            $vm.Info.intraVmAffinity = $false
            $vm.Info.Behavior = [VMware.Vim.StorageDrsPodConfigInfoBehavior]::automated

            $spec.VmConfigSpec += $vm
        }

        $si = Get-View ServiceInstance -Server $global:DefaultVIServer
        $storMgr = Get-View -id $si.Content.StorageResourceManager -Server $global:DefaultVIServer
        $storMgr.ConfigureStorageDrsForPod($dsc.ExtensionData.MoRef,$spec,$true)
    }
}
