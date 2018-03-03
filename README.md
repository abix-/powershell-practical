This repository contains random scripts and a PowerShell module named Aluminium which I use to support vSphere. Each script was written to solve an operational or engineering puzzle. In a perfect world I would have a description of the puzzle, the constraints, and reasoning into why I wrote the script the way I did. I neither recorded nor recall the details.

## Aluminium
The 146 functions in Aluminium allow me to increase efficiency and minimize mundane efforts. Here are a few examples:<br>
* **Get-HBAHostFirmware**: get NIC driver and FCoE driver/firmware version for VMHosts<br>
* **Get-HPOAInventory**: connects to a HP Onboard Administrator, discovers all linked enclosures, then creates a CSV report of identified hardware<br>
* **Get-VMDatastoreDetails**: creates detailed report for all VMDKs for a list of VMs<br>
* **Get-NTP_Health**: reports on VMHost time dift by using ConfigManager.DateTimeSystem to get time on VMHosts and comparing to local time<br>
* **Invoke-DefragDatastoreCluster**: shuffle VMDKs between datastores on datastore cluster to optimally fill each datastore to 83%. Results in continguous free space<br>
* **Move-VMConfig**: migrates a VM's configuration files(VMX, nvram, etc) to the same datastore as Hard Disk 1. Useful during SAN/datastore migrations<br>
* **Move-VMtovCenter**: migrates a VM between vCenters by unregistering a VM from a Source vCenter, registering it on a destination vCenter, updating the NIC network labels, and powering on the VM. Tested between vCenter 5.1U3 and vCenter and 6.0U1<br>
* **New-VMHost**: work in progress to accelerate ESXi VM Host build times. Modifies ILO users, creates custom ESXi ISO, performs install post-configuration.<br>
* **Optimize-ClusterBalance**: supports Round Robin and Quick balancing. Round Robin balances VMs across a cluster by splitting into unique types, then Round Robining evenly across all hosts. Quick makes the minimum required vMotions to balance a cluster based on allocated VM Host memory.<br>
* **Set-DNS**: using export from Get-DNS, static DNS settings on Windows servers can be updated in bulk<br>
* **Start-ApplicanceHealthReport**: creates HTML report on the disk usage, service status, ssh status, and vSphere web client response time for vSphere VMs by using Invoke-VMScript.<br>
* **Start-ClusterCapacityReport**: creates a Cluster Capacity HTML Report on vCPU/vRAM allocation, usage, availability, and contention for each Cluster. HTML report has separate tabs for each Cluster. Requires ImportExcel and ReportHTML modules. Connects to vROPs with REST. Requires CPU contention report in vROPs<br>
* **Start-ClusterCapacitySummary**: creates a Cluster Capacity XLSX Summary on CPU/vRAM allocation, usage, availability, and contention for each Cluster. CPU Usage is calculated for 9AM to 5PM and 5PM to 9AM. Requires ImportExcel and ReportHTML modules. Connects to vROPs with REST. Requires CPU contention report in vROPs<br>
* **Start-DatastoreMigration**: migrates VMs from a source Datastore/DatastoreCluster/MigrationGroup to a destination DatastoreCluster. Supports FillDatastorePercent to limit how full each datastore gets. Defaults to two svMotions at a time. Has been used to migrate 500TB+ between arrays.<br>
* **Test-ESXiAccount**: validates that assumed credentials are valid on VMHosts<br.

My intention is for this respository to be a reference for the next guy who comes along. If you did not get here by searching GitHub for a PowerShell cmdlet, I recommend doing this and then checking the Code results. Uncommented code examples are much better than no code examples.

## Next
* Add comments
* Continue to increment
* Add explanations about the puzzles and constraints
* Commit useless snippets

This will never be complete but will always be fun
