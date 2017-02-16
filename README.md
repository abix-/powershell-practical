This repository contains random scripts and a PowerShell module named Aluminium which I use to support vSphere. Each script was written to solve an operational or engineering puzzle. In a perfect world I would have a description of the puzzle, the constraints, and reasoning into why I wrote the script the way I did. Clearly, I neither recorded nor remember all the details.

## Aluminium
The 53 functions in Aluminium allow me to increase efficiency and minimize mundane efforts. Here are a few examples:<br>
* **Get-VMHostFirmware**: get NIC driver and FCoE driver/firmware version for VMHosts<br>
* **Get-HPOAInventory**: connects to a HP Onboard Administrator, discovers all linked enclosures, then creates a CSV report of identified hardware<br>
* **Set-DNS**: using export from Get-DNS, static DNS settings on Windows servers can be updated in bulk<br>
* **Start-Day**: connects to multiple vCenters with PowerShell and launches vSphere Clients using SecureStrings, then starts checks against all vCenters
* **Optimize-ClusterBalance**: Supports Round Robin and Quick balancing. Round Robin balances VMs across a cluster by splitting into unique types, then Round Robining evenly across all hosts. Quick makes the minimum required vMotions to balance a cluster based on allocated VM Host memory.
* **New-VMHost**: work in progress to accelerate ESXi VM Host build times. Modifies ILO users, creates custom ESXi ISO, performs install post-configuration.
* **Get-VMDatastoreDetails**: creates detailed report for all VMDKs for a list of VMs
* **Move-VMtovCenter**: migrates a VM between vCenters by unregistering a VM from a Source vCenter, registering it on a destination vCenter, updating the NIC network labels, and powering on the VM. Tested between vCenter 5.1U3 and vCenter and 6.0U1

My intention is for this respository to be a reference for the next guy who comes along. If you did not get here by searching GitHub for a PowerShell cmdlet, I recommend doing this and then checking the Code results. Uncommented code examples are much better than no code examples.

## Next
* Upload all my semi-useful scripts  
* Add comments to every function  
* Continue to improve random scripts  
* Add explanations about the puzzles, constraints, and reasoning  
* Commit unfinished useless snippets without explanation  

This will never be complete but will always be fun.