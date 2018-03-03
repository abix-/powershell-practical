This repository contains my Aluminium PowerShell module, community scripts, and random scripts. Each script was used to solve an operational or engineering puzzle for my VMware vSphere environments. An ideal world would have a description of the puzzle, the constraints, and reasoning into why I wrote the script the way I did. I neither recorded nor recall the details

## Aluminium
The 146 functions increase efficiency, minimize mundane, and create reports. Most functions require [PowerCLI](https://www.powershellgallery.com/packages/VMware.PowerCLI), [ImportExcel](https://github.com/dfinke/ImportExcel), [ReportHTML](https://www.powershellgallery.com/packages/ReportHTML), [PoshRSJob](https://github.com/proxb/PoshRSJob), or [HP Scripting Tools](https://www.hpe.com/us/en/product-catalog/detail/pip.scripting-tools-for-windows-powershell.5440657.html) modules. A few examples:<br>
* **Connect-SSHPutty**: uses Start-VMHostService, launches Putty with credentials, then Stop-VMHostService when Putty is closed
* **Get-HBAFirmware**: gets VMHost NIC driver and FCoE driver/firmware version with Get-EsxCLI<br>
* **Get-HPOAInventory**: connects to a HP Onboard Administrator, discovers all linked enclosures, then creates a CSV report of identified hardware. Uses Connect-HPOA, Get-HPOATopology, Get-HPOAServerStatus, and Get-HPOAServerPortMap<br>
* **Get-VMDatastoreDetails**: creates detailed report for all VMDKs for multiple VMs with Get-VM and Get-View<br>
* **Get-NTP_Health**: reports on VMHost time dift using ExtensionData.ConfigManager.DateTimeSystem to get time from VMHosts then compare to local time<br>
* **Invoke-DefragDatastoreCluster**: shuffle VMDKs with Move-HardDisk between datastores in datastore cluster to optimally fill each datastore to 83%. Results in continguous free space<br>
* **Move-VMConfig**: migrates a VM's configuration files(VMX, nvram, etc) to the same datastore as Hard Disk 1 with VirtualMachineRelocateSpec. Useful during SAN/datastore migrations<br>
* **Move-VMtovCenter**: migrates a VM between vCenters by unregistering a VM from a Source vCenter, registering it on a destination vCenter, updating the NIC network labels, and powering on the VM. Tested between vCenter 5.1U3 and vCenter 6.0U1<br>
* **New-VMHost**: work in progress. accelerates ESXi VMHost build times. Modifies ILO users with HPONCFG, creates custom ESXi ISO with ImgBurn, adds vMotion IP, Add-VMHostNtpServer, configures persistent logging, and Set-AdvancedSetting<br>
* **Optimize-ClusterBalance**: supports Round Robin and Quick balancing. Round Robin balances VMs in a cluster by splitting into unique types then Round Robining evenly between VMHosts. Quick makes the minimum required vMotions to balance a cluster based on allocated VMHost memory. Uses Move-VM, Add-Member, and math<br>
* **Set-DNS**: uses export from Get-DNS to set static DNS settings on multiple Windows servers using Get-WmiObject Win32_NetworkAdapterConfiguration<br>
* **Start-ApplicanceHealthReport**: creates HTML report on disk usage, application service status, SSH service status, and vSphere web client response time for vSphere appliances with Invoke-VMScript and regex. Uses Get-Service and Get-WMIObject on Windows. Uses df, chkconfig in a cron job, and systemctl on Linux. This is less aggravating than working with SCOM<br>
* **Start-ClusterCapacityReport**: creates detailed HTML report on vCPU/vRAM allocation, usage, availability, and contention for each vSphere Cluster. Connects to vROPs with Connect-OMServer and Invoke-RestMethod. Requires CPU contention report in vROPs<br>
* **Start-ClusterCapacitySummary**: creates summarized XLSX report on vCPU/vRAM allocation, usage, availability, and contention for each vSphere Cluster. CPU Usage is calculated for 9AM-5PM and 5PM-9AM. Connects to vROPs with Connect-OMServer and Invoke-RestMethod. Requires CPU contention report in vROPs<br>
* **Start-DatastoreMigration**: migrates VMs from a source Datastore/DatastoreCluster/MigrationGroup to a destination DatastoreCluster. Supports FillDatastorePercent to limit how full each datastore gets. Defaults to two svMotions at a time. I'ved migrated 500TB+ with this<br>
* **Start-ILO**: reads the output from Get-HPOAInventory to quickly Start-Process Internet Explorer for ILO IP
* **Test-ESXiAccount**: validates that assumed credentials are valid on VMHosts with Test-ESXiAccount<br>
* **Test-PortGroups**: validates the trunking configuration of VMHosts by moving a VM between every PortGroup on a VMHost. Will Set-VMGuestNetwork with an IP(based on PortGroup name) for each PortGroup then ping with Test-Connection and finally set the next PortGroup with Set-NetworkAdapter. The cycle repeats until all PortGroups have been tested. A ping failure likely indicates a trunking/networking misconfiguration
* **Test-VMHostIODevice**: uses output from Get-VMHostIODevice to validate that driver/firmware for FCoE and Network devices are at assumed revision

## Random Scripts
The random scripts were written before I learned about Modules. I haven't needed them in a few years and the ones I still use have been copied into the Aluminium module.

## Why?
This respository is a reference for the next person with a puzzle. I highly recommend searching GitHub for a PowerShell cmdlet then checking the Code results. Uncommented code examples are much better than no code examples.

## Next
* Add comments
* Continue to increment
* Add explanations about the puzzles and constraints
* Commit useless snippets

This will never be complete and will always be fun
