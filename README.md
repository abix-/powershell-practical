This repository contains random scripts and a PowerShell module named Aluminium which I use to support vSphere. Each script was written to solve an operational or engineering puzzle. In a perfect world I would have a description of the puzzle, the constraints, and reasoning into why I wrote the script the way I did. I neither recorded nor remember all the details.

## Aluminium
The 146 functions in Aluminium allow me to increase efficiency and minimize mundane efforts. Here are a few examples:<br>
* **Get-VMHostFirmware**: get NIC driver and FCoE driver/firmware version for VMHosts<br>
* **Get-HPOAInventory**: connects to a HP Onboard Administrator, discovers all linked enclosures, then creates a CSV report of identified hardware<br>
* **Set-DNS**: using export from Get-DNS, static DNS settings on Windows servers can be updated in bulk<br>
* **Optimize-ClusterBalance**: Supports Round Robin and Quick balancing. Round Robin balances VMs across a cluster by splitting into unique types, then Round Robining evenly across all hosts. Quick makes the minimum required vMotions to balance a cluster based on allocated VM Host memory.
* **New-VMHost**: work in progress to accelerate ESXi VM Host build times. Modifies ILO users, creates custom ESXi ISO, performs install post-configuration.
* **Get-VMDatastoreDetails**: creates detailed report for all VMDKs for a list of VMs
* **Move-VMtovCenter**: migrates a VM between vCenters by unregistering a VM from a Source vCenter, registering it on a destination vCenter, updating the NIC network labels, and powering on the VM. Tested between vCenter 5.1U3 and vCenter and 6.0U1
* **Invoke-DefragDatastoreCluster**: Shuffle VMDKs between datastores on datastore cluster to optimally fill each datastore to 83%. Results in continguous free space<br>
* **Start-ClusterCapacityReport**: Creates a Cluster Capacity HTML Report on vCPU/vRAM allocation, usage, availability, and contention for each Cluster. HTML report has separate tabs for each Cluster. Requires ImportExcel and ReportHTML modules. Connects to vROPs with REST. Requires CPU contention report in vROPs<br>
* **Start-ClusterCapacitySummary**: Creates a Cluster Capacity XLSX Summary on CPU/vRAM allocation, usage, availability, and contention for each Cluster. CPU Usage is calculated for 9AM to 5PM and 5PM to 9AM. Requires ImportExcel and ReportHTML modules. Connects to vROPs with REST. Requires CPU contention report in vROPs<br>
* **Start-ApplicanceHealthReport**: Creates HTML report on the disk usage, service status, ssh status, and vSphere web client response time for vSphere VMs by using Invoke-VMScript.
* **Start-DatastoreMigration**: Migrates VMs from a source Datastore/DatastoreCluster/MigrationGroup to a destination DatastoreCluster. Supports FillDatastorePercent to limit how full each datastore gets. Defaults to two svMotions at a time. Has been used to migrate 500TB+ between arrays.

My intention is for this respository to be a reference for the next guy who comes along. If you did not get here by searching GitHub for a PowerShell cmdlet, I recommend doing this and then checking the Code results. Uncommented code examples are much better than no code examples.

## Next
* Upload all my semi-useful scripts  
* Add comments to every function  
* Continue to improve random scripts  
* Add explanations about the puzzles, constraints, and reasoning  
* Commit unfinished useless snippets without explanation  

This will never be complete but will always be fun.
