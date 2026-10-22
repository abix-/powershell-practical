This repository contains my Aluminium PowerShell module, community scripts, and random scripts. Each script was used to solve an operational or engineering puzzle for a VMware vSphere environment. An ideal world would have a description of the puzzle, the constraints, and reasoning into why I wrote the script the way I did. I neither recorded nor recall the details

## Aluminium
The 146 functions increase efficiency, minimize mundane, and create reports. Most functions require [PowerCLI](https://www.powershellgallery.com/packages/VMware.PowerCLI), [ImportExcel](https://github.com/dfinke/ImportExcel), [ReportHTML](https://www.powershellgallery.com/packages/ReportHTML), [PoshRSJob](https://github.com/proxb/PoshRSJob), or [HP Scripting Tools](https://www.hpe.com/us/en/product-catalog/detail/pip.scripting-tools-for-windows-powershell.5440657.html). A few examples:<br>
* **Connect-SSHPutty**: uses Start-VMHostService SSH, launches Putty with credentials, then Stop-VMHostService when Putty is closed
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
* **Start-DatastoreMigration**: storage vMotions VMDKs from a source Datastore/DatastoreCluster/MigrationGroup to a destination DatastoreCluster. Supports FillDatastorePercent to limit how full each datastore gets. Defaults to two svMotions at a time. I'ved migrated 500TB+ with this<br>
* **Start-ILO**: reads the output from Get-HPOAInventory to quickly Start-Process Internet Explorer for ILO IP
* **Test-ESXiAccount**: validates that assumed credentials are valid on VMHosts with Connect-VIServer<br>
* **Test-PortGroups**: validates the trunking on VMHosts by moving a VM between every PortGroup on a VMHost. Will Set-VMGuestNetwork with an IP(based on PortGroup name) for each PortGroup then ping with Test-Connection and finally set the next PortGroup with Set-NetworkAdapter. The cycle repeats until all PortGroups have been tested. A ping failure likely indicates a trunking/networking misconfiguration
* **Test-VMHostIODevice**: uses output from Get-VMHostIODevice to validate that driver/firmware for FCoE and Network devices are at assumed version

## Random Scripts
The random scripts were written before I learned about Modules. I haven't needed them in a few years and the ones I still use have been copied into the Aluminium module.

## RouterOS inventory

`tools/Test-MikrotikInventory.ps1` invokes the permanent read-only diagnostic
and checks the saved router identity and core discovery tables. It requires
PowerShell 7.5+, OpenSSH, an existing trusted host key and a read-only SSH
account. Pass `-RouterAddress`, `-Username`, `-IdentityFile` and `-OutputPath`.
The identity file is passed to SSH; the scripts never read its contents.

Discovery includes DHCP, ARP, IPv6 neighbors, bridge hosts, both wireless
menus, installed packages and selected service/firewall fields. RouterBOOT
versions and free storage/memory support upgrade preparation. Updater status
includes the installed version and any cached download status. Returned
records are filtered locally to the allowlist before saving. Keep the JSON
outside public Git. Missing tables remain unverified; stale addresses and
randomized MACs do not prove a distinct or currently online device. This
checks discovery evidence, not firmware remediation or external reachability.

Add `-SecurityEvidence` to preserve account logs, device-mode flags, account
metadata, script/scheduler names and selected DNS/proxy/logging settings.
These queries use explicit field reads on the router and never retrieve
script bodies, event actions, configuration exports or credentials. Security
evidence requires a new output path. RAM logs can be lost on reboot; an unset
compromise flag cannot establish that a router has never been compromised.

## Windows security evidence

`tools/Test-WindowsSecurityEvidence.ps1 -OutputPath <new-private-json-path>`
invokes the permanent read-only desktop collector and checks saved evidence
identity and SHA256. Requires Windows and PowerShell 7.5+. Run in an elevated
terminal when Security-log access is needed; the script never elevates itself.
Add `-RequireSecurityLog` to fail if Security-log or inbound-rule access is
still missing, while retaining the report for review.

Collects up to 2,000 selected structured events per query over 30 days (override
with `-Days`), retention bounds, Defender state, local accounts, persistence
metadata, installed app versions, processes, TCP endpoints and firewall state.
Task executable paths are read without arguments or running tasks. Enabled
inbound allow rules include application/package, service, port and address
restrictions. Separate account/policy changes, authentication failures and
remote logins keep noisy service events from burying these categories. Every
query retains its oldest/newest selected times and possible truncation flag.
`-AuthenticationAndFirewallOnly` collects this evidence without repeating
executable hashing. Keep an elevated report in a private folder readable by
the investigating user; Windows Temp files can otherwise restrict later reads.
Running accessible executables receive hashes and Authenticode status; project
executables also retain PID/start time and file metadata. OneLog log files are
listed by metadata only. Command lines, event messages, task actions, script
bodies, browser profiles and credential files are excluded. Missing access,
disabled histories and collection caps limit the investigation. Empty threat
history, familiar names and valid signatures do not establish absence of
compromise. The collector makes no remediation changes and never overwrites
an existing evidence file. Keep reports outside public Git.

`tools/Test-WindowsTrustEvidence.ps1 -OutputPath <new-private-json-path>`
reads public Root/CA/Disallowed metadata and checks all certificates from the
[eMudhra incident manifest](https://emudhra.we-have-a-problem.com/).
It validates public certificate hashes, supplies issuer certificates as
untrusted chain material and uses the existing Windows chain engine with
revocation fetching and AIA downloads disabled. Automatic Windows CTL activity
is not controlled. No certificates are imported and no private keys are read.
Explicit distrust is distinct from rejection for an incomplete chain; an empty
Disallowed store enumeration does not prove that Microsoft's CTL blocks are
absent. This check does not replace testing the application's actual TLS path.

`tools/Test-WindowsLogCoverage.ps1 -OutputPath <new-private-json-path> -Days 30`
collects live event-log retention bounds and settings, standard archived EVTX
file metadata/hashes and available shadow-copy metadata. It never changes log
retention or creates snapshots. An empty standard archive directory does not
exclude exports elsewhere. A log starting before the requested window does not
prove continuous auditing; archive discovery does not count as event review.

`tools/Test-WindowsUpdateReadiness.ps1 -OutputPath <new-private-json-path>`
reads OS/build, public ESU volume-license status (never product keys), service
and policy metadata, free system-disk space, restart indicators and update
history. It searches the configured update service for offered and hidden
software updates; this can refresh the Windows Update search cache. It never
downloads/installs updates, accepts EULAs, activates licenses or reboots.
An empty offer list does not establish patch compliance or consumer ESU status.

`tools/Test-OnelogFirewallPlan.ps1 -EvidencePath <private-security-report>`
`-ProgramPath <exact-release-executable> -OutputPath <new-private-plan>`
reads the two exact release-program rules from PersistentStore and captures
all seven associated filter types, including NetSecurity's adapted aliases.
It produces data-only parameter sets for narrowing LocalPort/RemoteAddress,
plus exact inverse parameter sets; it invokes no writing cmdlets. Profiles,
program identity, enabled state and all other conditions remain unchanged.
Debug/test rules are outside this plan. Review against fresh live state and
verify actual loopback MCP plus paired-phone sync/discovery before accepting
any later change. The plan itself does not establish network acceptance.

## Application and runtime security evidence

`tools/Test-ApplicationSecurityInventory.ps1 -OutputPath <new-private-json-path>`
collects targeted Plex/PHP and runtime metadata. It checks Windows installation,
process and service metadata, Node executable ancestry, known binary versions/hashes, installed Python312
package Name/Version headers, Docker container names/images/ports and already
running Ubuntu package/k3s image metadata. Python is never executed. Plex public
identity requests check only localhost and the known NAS, retaining version only.
Stopped WSL distributions are not started. Unreachable services, missing tools
and unchecked installation locations remain explicit inventory gaps.

`tools/Test-CurlTrustEvidence.ps1 -OutputPath <new-private-json-path>` tests
installed Windows/Git curl binaries against one valid control and fourteen
[incident hosts](https://emudhra.we-have-a-problem.com/), including two No CT
chains. Curl configuration is disabled; platform trust updates and inherited
environment are not controlled. This does not establish Git transport settings.

`tools/Test-NodeTrustEvidence.ps1 -OutputPath <new-private-json-path>` uses the
installed Node binary with bundled CAs and child-only preload/trust overrides
removed without reading their values. The same fifteen public HTTPS HEAD checks
use only built-in modules. This measures isolated bundled defaults, not existing
application configuration. Pass `-NodePath <existing-node.exe>` to check another
installed copy. No runtime installation or running app is changed.

These tests preserve evidence and distinguish certificate rejection from unknown
transport failures. Collection PASS does not mean security PASS; accepted incident
chains are reported as findings. No credentials or response bodies are retained.
Keep all reports outside public Git.

`tools/Test-SecurityPatchArtifacts.ps1 -Directory <new-private-directory>` stages
official Node26.12.1 x64 standalone/installer and pip26.2.2/certifi2026.10.19 wheels.
Node downloads must match official SHA256 and valid OpenJS Authenticode; wheels
must match official PyPI release hashes. The new portable Node must pass the valid
control and reject all fourteen incident chains. Installers and Python are never
executed. Existing runtime installations and processes remain unchanged.

`tools/Test-CodexUpdateReadiness.ps1 -OutputPath <new-private-json-path>` records
installed OpenAI Appx identity, executable metadata and read-only winget queries.
Store version Unknown or an unmatched installed package is an explicit gap.
`tools/Test-CodexUpdateCandidate.ps1 -Directory <new-private-directory>` downloads
the latest x64 MSIX linked by official deployment documentation, reads its public
manifest and extracts only Node executables after checking the package signature
and expected OpenAI identity. Only independently valid OpenJS/OpenAI-signed Node
candidates are tested. Pass `-PackagePath <already-downloaded-msix>` to inspect a
saved package without another download. Neither tool installs or launches the app
or proves detached runtime replacement.

`tools/Test-VerifiedRuntimeUpdate.ps1 -Target Node|Python -ArtifactDirectory
<verified-artifacts> -Directory <new-private-evidence>` installs the selected
reviewed update and verifies a new installed client against the valid control and
fourteen incident chains. Node rechecks MSI hash/signature, uses elevation and a
new SYSTEM-readable copy of the public installer, and disables automatic reboots
and Restart Manager shutdown. Python installs only pinned local wheels with
configuration disabled, standard-library-first imports and no startup hooks.
Receipts preserve prior versions, installer results and installed-client checks.
Existing long-running clients must be relaunched separately by their owners.

`tools/Test-DeferredCodexUpdate.ps1 -PackagePath <tested-msix> -OutputPath
<new-private-receipt>` applies only the reviewed same-family package after owner
checkpoints. It verifies the exact candidate hash/signature, disk space and package
identity, then requests deferred registration with elevation for its packaged
service. It never forces an app exit or restart. Selected detached runtime and
next-launch tooling checks remain required even when package registration succeeds.

## Why?
This respository is a reference for the next person with a puzzle. I highly recommend searching GitHub for a PowerShell cmdlet then checking the Code results. Uncommented code examples are much better than no code examples.

## Next
* Add comments
* Continue to increment
* Add explanations about the puzzles and constraints
* Commit useless snippets

This will never be complete and will always be fun
