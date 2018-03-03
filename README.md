This repository contains random scripts and a PowerShell/PowerCLI module named Aluminium. Each script was written to solve an operational or engineering puzzle for my VMware vSphere environments. An ideal world would have a description of the puzzle, the constraints, and reasoning into why I wrote the script the way I did. I neither recorded nor recall the details.

## Aluminium
The 146 functions in Aluminium allow me to increase efficiency and minimize mundane efforts. Some functions require ImportExcel, ReportHTML, PoshRSJob, or HP Scripting Tools modules. A few examples:<br>
* **Connect-SSHPutty**: starts SSH service on VMHost, launches Putty with credentials, then stops SSH service when Putty is closed
* **Get-HBAHostFirmware**: get VMHost NIC driver and FCoE driver/firmware version<br>
* **Get-HPOAInventory**: connects to a HP Onboard Administrator, discovers all linked enclosures, then creates a CSV report of identified hardware<br>
* **Get-VMDatastoreDetails**: creates detailed report for all VMDKs for a list of VMs<br>
* **Get-NTP_Health**: reports on VMHost time dift by using ConfigManager.DateTimeSystem to get time on VMHosts and comparing to local time<br>
* **Invoke-DefragDatastoreCluster**: shuffle VMDKs between datastores in datastore cluster to optimally fill each datastore to 83%. Results in continguous free space<br>
* **Move-VMConfig**: migrates a VM's configuration files(VMX, nvram, etc) to the same datastore as Hard Disk 1. Useful during SAN/datastore migrations<br>
* **Move-VMtovCenter**: migrates a VM between vCenters by unregistering a VM from a Source vCenter, registering it on a destination vCenter, updating the NIC network labels, and powering on the VM. Tested between vCenter 5.1U3 and vCenter 6.0U1<br>
* **New-VMHost**: work in progress. accelerates ESXi VMHost build times. Modifies ILO users, creates custom ESXi ISO, adds vMotion IP, sets NTP, configures persistent logging, and changes advanced settings<br>
* **Optimize-ClusterBalance**: supports Round Robin and Quick balancing. Round Robin balances VMs across a cluster by splitting into unique types, then Round Robining evenly across all hosts. Quick makes the minimum required vMotions to balance a cluster based on allocated VM Host memory<br>
* **Set-DNS**: uses export from Get-DNS to set static DNS settings on multiple Windows servers<br>
* **Start-ApplicanceHealthReport**: creates HTML report on disk usage, service status, ssh status, and vSphere web client response time for vSphere appliances with Invoke-VMScript and regex. Uses Get-Service and Get-WMIObject on Windows. Uses df, chkconfig in a cron job, and systemctl on Linux. This is less aggravating than working with SCOM<br>
* **Start-ClusterCapacityReport**: creates a HTML report on vCPU/vRAM allocation, usage, availability, and contention for each Cluster. HTML report has separate tabs for each Cluster. Connects to vROPs with REST and PowerShell. Requires CPU contention report in vROPs<br>
* **Start-ClusterCapacitySummary**: creates a XLSX summary on vCPU/vRAM allocation, usage, availability, and contention for each vSphere vSphere Cluster. CPU Usage is calculated for 9AM to 5PM and 5PM to 9AM. Connects to vROPs with REST and PowerShell. Requires CPU contention report in vROPs<br>
* **Start-DatastoreMigration**: migrates VMs from a source Datastore/DatastoreCluster/MigrationGroup to a destination DatastoreCluster. Supports FillDatastorePercent to limit how full each datastore gets. Defaults to two svMotions at a time. Has been used to migrate 500TB+ between storage arrays<br>
* **Start-ILO**: reads the output from Get-HPOAInventory to quickly launch Internet Explorer for ILO IP
* **Test-ESXiAccount**: validates that assumed credentials are valid on VMHosts<br>

## Random Scripts
These random scripts were written before I learned about PowerShell Modules. I haven't needed them in a few years and the ones I still use have been moved into the Aluminium module.

## Why?
This respository is a reference for the next person with a puzzle. I highly recommend searching GitHub for a PowerShell cmdlet then checking the Code results. Uncommented code examples are much better than no code examples.

## Next
* Add comments
* Continue to increment
* Add explanations about the puzzles and constraints
* Commit useless snippets

This will never be complete and will always be fun
