function Test-MigrationResults {
    [cmdletbinding()]
    param (
        $servers
    )

    Write-Host
    Write-Host "Starting to compare 5.1 and 6.0 results"

    $serversclean = $servers | ForEach-Object{$_ -replace ".txt" -replace "\." -replace "\\"}
    $results51file = @(Get-ChildItem "C:\Scripts\Reports" | Where-Object{$_.Name -like "MigrationValidation_$($serversclean)_5.1*"} | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if($results51file.count -ne 1) {
        Write-Host "[5.1 results] Not found. Was this run for 5.1?"
        Return
    } else {
        $results51 = Import-Csv $results51file.Fullname
        Write-Host "[5.1 results] Located at $($results51file[0].Fullname)"
    }

    $results60file = @(Get-ChildItem "C:\Scripts\Reports" | Where-Object{$_.Name -like "MigrationValidation_$($serversclean)_6.0*"} | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if($results60file.count -ne 1) {
        Write-Host "[6.0 results] Not found. Was this run for 6.0?"
        Return
    } else {
        $results60 = Import-Csv $results60file.Fullname
        Write-Host "[6.0 results] Located at $($results60file[0].Fullname)"
    }

    $compareresults = @()
    foreach($result60 in $results60) {           
        $vmname = $result60.Server
        $ip60 = $result60.IP
        $pingip60 = $result60.PingIP
        $pingvm60 = $result60.PingVM
        $wmivm60 = $result60.WMIVM

        $result51 = $results51 | Where-Object{$_.Server -eq $vmname}
        $ip51 = $result51.IP
        $pingip51 = $result51.PingIP
        $pingvm51 = $result51.PingVM
        $wmivm51 = $result51.WMIVM

        if($ip60 -eq $ip51) {
            Write-Verbose "[$vmname] IP: $ip60 matches $ip51"
            $ipmatch = "Validated"
        } else {
            Write-Verbose "[$vmname] IP: $ip60 does not match $ip51"
            $ipmatch = "Does Not Match"
        }

        if($pingip60 -eq $pingip51) {
            Write-Verbose "[$vmname] PingIP: $pingip60 matches $pingip51"
            $pingipmatch = "Validated"
        } else {
            Write-Verbose "[$vmname] PingIP: $pingip60 does not matche $pingip51"
            $pingipmatch = "Does Not Match"
        }

        if($pingvm60 -eq $pingvm51) {
            Write-Verbose "[$vmname] PingVM: $pingvm60 matches $pingvm51"
            $pingvmmatch = "Validated"
        } else {
            Write-Verbose "[$vmname] PingVM: $pingvm60 does not matche $pingvm51"
            $pingvmmatch = "Does Not Match"
        }

        if($wmivm60 -eq $wmivm51) {
            Write-Verbose "[$vmname] WMIVM: $wmivm60 matches $wmivm51"
            $wmivmmatch = "Validated"
        } else {
            Write-Verbose "[$vmname] WMIVM: $wmivm60 does not matche $wmivm51"
            $wmivmmatch = "Does Not Match"
        }

        $compareresults += [pscustomobject][ordered]@{
            Server = $vmname
            IP_Match = $ipmatch
            PingIP_Match = $pingipmatch
            PingVM_Match = $pingvmmatch
            WMIVM_Match = $wmivmmatch
        }
    }
    
    if($compareresults) {
        $compareresults | Format-Table | Out-String | ColorWord2 -word 'Does Not Match ','Validated' -color 'Red','Green'
        Export-Results -results $compareresults -exportName MigrationValidation_$($serversclean)_Validation
    }
}

function Test-PortGroups {
    [cmdletbinding()]
    param(
        $vm = "al-test001",
        $GuestUser = "Administrator",
        $VMHost,
        $VDSwitch,
        $FailPause
    )

    $vmobj = Get-VM $vm
    if($VDSwitch) {
        $portgroups = Get-VM $vm | Get-VMHost | Get-VDSwitch $VDSwitch | Get-VDPortgroup | Sort-Object Name | Where-Object{$_.name -like "*_24*"}
    } else {
        $portgroups = Get-VM $vm | Get-VMHost | Get-VDSwitch | Get-VDPortgroup | Sort-Object Name | Where-Object{$_.name -like "*_24*"}
    }

    if($vmhost) {
        $vmhosts = Get-VMHost $VMHost
    } else {
        $vmhosts = Get-VM $vm | Get-Cluster | Get-VMHost | Sort-Object Name
    }
    
    $pw = Get-SecureStringCredentials -Username "Admin" -PlainPassword
    $results = @()

    foreach($_pg in $portgroups) {
        #Find an available IP
        $subnet = $_pg.Name -match "_(?<subnet>\d{1,3}\.\d{1,3}\.\d{1,3})" | ForEach-Object{$matches['subnet']}
        $newip = "none"
        Write-Host "[$subnet.0] Looking for available IP"
        $gateway = "$subnet.1"
        foreach($i in (240..250)) {
            $testip = "$subnet.$i"
            if(Test-Connection -ComputerName $testip -Count 2 -ErrorAction SilentlyContinue) {
                Write-Host "[$subnet.0] $testip responded to ping"
                $newip = "none"
            } else {
                Write-Host "[$subnet.0] $testip did not respond to ping"
                $newip = $testip
                break
            }
        }

        if($newip -ne "none") {
            Write-Host "[$subnet.0] $newip will be used for testing"

            #Get the current nic information
            $nics = @(Get-VMGuestNetwork -vm $vmobj -GuestUser $GuestUser -GuestPassword $pw)
            if($nics.count -gt 1) {            
                Write-Host "[$vm] Multiple NICs found. Aborting"
                Return
            }

            #Change the IP on VM NIC
            Set-VMGuestNetwork -vm $vmobj -GuestUser $GuestUser -GuestPassword $pw -nicAlias $nics[0].InterfaceAlias -nicIP $newip -nicMask "255.255.255.0" -nicGateway $gateway

            #Change the port group on VM NIC
            Write-Host "[$vm] Changing port group to $($_pg.Name)"
            Get-NetworkAdapter -VM $vmobj | Set-NetworkAdapter -NetworkName $_pg -Confirm:$false | Out-Null
        }

        #vMotion VM between all hosts in cluster
        foreach($_h in $vmhosts) {
            $ping = "N/A"
            if($newip -ne "none") {
                Write-Host "[$vm] vMotioning to $($_h.Name)"
                Move-VM -VM $vmobj -Destination $_h | Out-Null

                #Ping VM and record results
                if(Test-Connection -ComputerName $newip -Count 1 -ErrorAction SilentlyContinue) {
                    $ping = "Pass"
                    Write-Host "[$vm] VM responded to ping" -ForegroundColor Green
                } else {
                    $ping = "Fail"
                    Write-Host "[$vm] VM did not respond to ping on $newip" -ForegroundColor Red
                    if($FailPause -eq $true) {
                        Write-Host "[$vm] Status of manual ping?" -ForegroundColor Yellow
                        $ping = Read-Host
                    }
                }
            }

            #Record the results
            $results += [pscustomobject][ordered]@{
                VM = $vm
                PortGroup = $_pg.Name
                IP = $newip
                VMHost = $_h.Name
                Ping = $ping
            }
        }
    }
    if($results) { Export-Results -results $results -exportName Test-PortGroups_$vm }
}

function Test-MigrationGroup {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)]$servers,
        [Parameter(Mandatory=$true)][string]$version,
        [Parameter(Mandatory=$true)]$GuestCredentials,
        [switch]$export = $false
    )

    if($servers.EndsWith(".txt")) { $serverlist = @(Get-Content $servers) }
    $serversclean = $servers | ForEach-Object{$_ -replace ".txt" -replace "\." -replace "\\"}

    $results = @()
    foreach($_s in $serverlist) {
        try {
            $vm = get-vm $_s -ErrorAction Stop
            $ip = $vm.Guest.IPAddress[0]
            Write-Host "[$_s] IP is $ip" -ForegroundColor Green
        }
        catch {
            $ip = "Fail"
            Write-Host "[$_s] Failed to determine IP" -ForegroundColor Red
        }

        if($ip -ne "Fail" -and $ip) {
            if(Test-Connection -ComputerName $ip -Count 1 -ErrorAction SilentlyContinue) {
                $pingip = "Pass"
                Write-Host "[$_s] IP responded to ping" -ForegroundColor Green
            } else {
                $pingip = "Fail"
                Write-Host "[$_s] IP did not respond to ping" -ForegroundColor Red
            }
        } else {
            Write-Host "[$_s] IP ping skipped"
        }

        if(Test-Connection -ComputerName $_s -Count 1 -ErrorAction SilentlyContinue) {
            $pingvm = "Pass"
            Write-Host "[$_s] VM responded to ping" -ForegroundColor Green
        } else {
            $pingvm = "Fail"
            Write-Host "[$_s] VM did not respond to ping" -ForegroundColor Red
        }

        if(Get-WmiObject -ComputerName $_s -Class win32_operatingsystem -cred $GuestCredentials -ErrorAction SilentlyContinue) {
            $wmi = "Pass"
            Write-Host "[$_s] WMI query passed" -ForegroundColor Green
        } else {
            $wmi = "Fail"
            Write-Host "[$_s] WMI query failed" -ForegroundColor Red
        }

        $results += [pscustomobject][ordered]@{
            "Server" = $_s
            "Version" = $version
            "IP" = $ip
            "PingIP" = $pingip
            "PingVM" = $pingvm
            "WMIVM" = $wmi
        }
    }

    if($results) {
        $results | Format-Table
        Export-Results -results $results -exportName MigrationValidation_$($serversclean)_$version
    }

    if($version -eq "6.0") {
        Write-Host "Comparing to 5.1 results..."

        $allresults51 = Get-ChildItem "C:\Scripts\Reports" | Where-Object{$_.Name -like "MigrationValidation_$($serversclean)_5.1*"}
        $results51file = @($allresults51 | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if($results51file.count -ne 1) {
            Write-Host "[5.1 results] Not found. Was this run first on 5.1?"
            Return
        } else {
            $results51 = Import-Csv $results51file.Fullname
            Write-Host "[5.1 results] Located at $($results51file[0].Fullname)"
        }

        $compareresults = @()
        foreach($_r in $results) {           
            $vmname = $_r.Server
            $ip60 = $_r.IP
            $pingip60 = $_r.PingIP
            $pingvm60 = $_r.PingVM
            $wmivm60 = $_r.WMIVM

            $thisresult51 = $results51 | Where-Object{$_.Server -eq $_r.Server}
            $ip51 = $thisresult51.IP
            $pingip51 = $thisresult51.PingIP
            $pingvm51 = $thisresult51.PingVM
            $wmivm51 = $thisresult51.WMIVM


            if($ip60 -eq $ip51) {
                Write-Host "[$vmname] IP: $ip60 matches $ip51" -ForegroundColor Green
                $ipmatch = "Matches"
            } else {
                Write-Host "[$vmname] IP: $ip60 does not match $ip51" -ForegroundColor Red
                $ipmatch = "Does Not Match"
            }

            if($pingip60 -eq $pingip51) {
                Write-Host "[$vmname] PingIP: $pingip60 matches $pingip51" -ForegroundColor Green
                $pingipmatch = "Matches"
            } else {
                Write-Host "[$vmname] PingIP: $pingip60 does not matche $pingip51" -ForegroundColor Red
                $pingipmatch = "Does Not Match"
            }

            if($pingvm60 -eq $pingvm51) {
                Write-Host "[$vmname] PingVM: $pingvm60 matches $pingvm51" -ForegroundColor Green
                $pingvmmatch = "Matches"
            } else {
                Write-Host "[$vmname] PingVM: $pingvm60 does not matche $pingvm51" -ForegroundColor Red
                $pingvmmatch = "Does Not Match"
            }

            if($wmivm60 -eq $wmivm51) {
                Write-Host "[$vmname] WMIVM: $wmivm60 matches $wmivm51" -ForegroundColor Green
                $wmivmmatch = "Matches"
            } else {
                Write-Host "[$vmname] WMIVM: $wmivm60 does not matche $wmivm51" -ForegroundColor Red
                $wmivmmatch = "Does Not Match"
            }

            $compareresults += [pscustomobject][ordered]@{
                Server = $_r.Server
                IP_Match = $ipmatch
                PingIP_Match = $pingipmatch
                PingVM_Match = $pingvmmatch
                WMIVM_Match = $wmivmmatch
            }
        }
        if($compareresults) {
            $compareresults
            if($export) { Export-Results -results $compareresults -exportName MigrationValidation_$($serversclean)_Validation }
        }
    }
}

function Test-VMX {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True,Position=1)]
        [string]$Name
    )

    if($Name.EndsWith(".txt")) { 
        $Names = @(Get-Content $Name) 
    } else { $Names = $Name }

    foreach($_name in $Names ) {
        try { 
            Get-VM $_name | Set-VMBIOSSetup 
            Get-VM $_name | Set-VMBIOSSetup -Disable
            Write-Host "[$_name] VMX modified successfully"
        }
        catch {
            Write-Host "[$_name] Failed to enable/disable forcing entry to BIOS on next startup"
            $_name | Out-File bad_vmx.txt -Append
        }
    }
}

function Test-vCenterConnected {
    if($global:DefaultVIServers.count -eq 0) {
        Write-Host "Connect to a vCenter first using Connect-VIServer." -ForegroundColor Red
        return $false
    }

    if(@(Get-View -ViewType Datacenter -Property Name).Count -gt 0) { return $true }
    return $false
}

function Test-vCenter {
    [cmdletbinding()]
    param (
        $ForegroundColor = "Blue",
        $BackgroundColor = "Gray"
    )
    if((Test-vCenterConnected) -eq $false) { return }

    $hosts = Get-VMHost | Sort-Object Name
    $hostsView = Get-View -ViewType HostSystem -Property Name,RunTime | Sort-Object Name
    $vmview = Get-View -ViewType VirtualMachine -Property Name,Runtime | Sort-Object Name
    Write-Host "`nVMHosts: $($hosts.count)`nVMs: $($vmview.count)`n" -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor

    $nonconnected = @($hosts | Where-Object{$_.ConnectionState -ne "Connected"})
    Write-Host "Hosts not in Connected state: $($nonconnected.Count)" -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    Write-Output $nonconnected | Select-Object Name,ConnectionState | Out-Default
    Write-Host

    $lowuptime = @($hostsView | Select-Object Name,@{N="UptimeHours"; E={[math]::abs((new-timespan (Get-Date) $_.Runtime.BootTime).TotalHours)}} | Where-Object{$_.UptimeHours -le 120})
    Write-Host "Hosts with less than 5 days of uptime: $($lowuptime.count)" -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    Write-Output $lowuptime | Select-Object Name,UptimeHours | Sort-Object UptimeHours | Out-Default
    Write-Host ""

    $hostservices = @($hosts | Get-VMHostService)

    $sshrunning = @($hostservices | Where-Object{$_.Key -eq "TSM-SSH" -and $_.Running -eq "True"})
    Write-Host "Hosts with SSH Running: $($sshrunning.Count)" -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    Write-Output $sshrunning | Select-Object -ExpandProperty vmhost | Select-Object -ExpandProperty name | Out-Default
    Write-Host ""

    $shellrunning = @($hostservices | Where-Object{$_.Key -eq "TSM" -and $_.Running -eq "True"})
    Write-Host "Hosts with ESXi Shell Running: $($shellrunning.Count)" -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    Write-Output $shellrunning | Select-Object -ExpandProperty vmhost | Select-Object -ExpandProperty name | Out-Default
    Write-Host ""
    
    $needconsolidation = @($vmview | Where-Object{$_.Runtime.ConsolidationNeeded})
    Write-Host "VMs which need consolidation: $($needconsolidation.count)" -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    Write-Output $needconsolidation | Select-Object -ExpandProperty Name | Out-Default

    $vms = Get-VM
    $nonavprxdisks = @($vms | Where-Object{$_.Name -like "*avprx*"} | Get-HardDisk | Where-Object{$_.Filename -notlike "*avprx*"})
    Write-Host "Non-Avamar Hard Disks attached to Avamar Proxies: $($nonavprxdisks.count)" -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    Write-Output $nonavprxdisks | Select-Object Parent,FileName | Out-Default
    
    $snaps = @($vms | Get-Snapshot)
    Write-Host "Snapshots: $($snaps.count)" -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    Write-Output $snaps | Select-Object VM,Created,Description,SizeGB | Out-Default

    Measure-DatastoreClusterCapacity
}

function Test-ESXiAccount {
    [cmdletbinding()]
    param (
        [Parameter(ValueFromPipeline=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost,
        [string]$account = "admin"
    )

    begin {
        $account_pw = Get-SecureStringCredentials -Username $account -PlainPassword
        $results = @()
    }

    process {
        $VMHostName = $VMHost.Name
        try {
            Connect-VIServer $VMHostName -User $account -Password $account_pw -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
            $status = "Validated"
            Write-Host "$($VMHostName): Validated password for $account"
            Disconnect-VIServer $VMHostName -Force -Confirm:$false
        }

        catch {
            Write-Host "$($VMHostName): Failed to connect as $account"
            $status = "Failed"
        }

        $results += [pscustomobject][ordered]@{
            Host = $VMHostName
            Account = $account
            Status = $status
        }
    }

    end {
        $results
    }
}

function Test-VMStorage {
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [string]$datastore_inventory_path = "$($global:ReportsPath)\Datastore_Inventory*",
        [string]$rdm_inventory_path = "$($global:ReportsPath)\RDM_Inventory*"
    )

    #point at datastore
    #check again rdm list - tell if not/is rdm
    #check against datastore list - tell if not/is rdm

    try {
        $ds_inventory_csv = Get-ChildItem $datastore_inventory_path -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $ds_inventory = Import-Csv $ds_inventory_csv -ErrorAction Stop

        $rdm_inventory_csv = Get-ChildItem $rdm_inventory_path -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $rdm_inventory = Import-Csv $rdm_inventory_csv  -ErrorAction Stop

        Write-Host "[$($ds_inventory_csv)] Loaded $($ds_inventory.count) datastores"
        Write-Host "[$($rdm_inventory_csv)] Loaded $($rdm_inventory.count) RDMs"
        Write-Host
     }
    catch { Write-Host $_.Exception -ForegroundColor Red ; return }

    if($Name.Length -eq 5) {
        $deviceIDCharArray = $Name.ToCharArray()
        [string]$converted = ""
        foreach($_d in $deviceIDCharArray) { $converted += "{0:x}" -f ([byte][char]"$_d") }
        $Filter = $converted
    } else { $Filter = $Name -replace ":" }

    $selected = @($ds_inventory | Where-Object{$_."NAA.ID" -like "*$Filter*"})
    if($selected.Count -eq 0) { $selected = @($ds_inventory | Where-Object{$_.Datastore -like "*$Filter*"}) }
    $rdm_selected = @($rdm_inventory | Where-Object{$_."ScsiCanonicalName" -like "*$Filter*"})

    if($converted) {
        Write-Host "DeviceID: $Name"
        Write-Host "DeviceID Conversion: $converted"
    }

    Write-Host "Datstores: Found $($selected.count) matching datstore(s)" -ForegroundColor Blue -BackgroundColor Gray
    if($selected.count -gt 0) { 
        foreach($_s in $selected) {
            if((Test-vCenterConnected) -eq $false) { return }
            $vms = @(Get-Datastore -Name $_s.Datastore | Get-VM)
            Write-Host "NAA.ID: $($_s."NAA.ID")"
            Write-Host "Datastore: $($_s.Datastore)"
            Write-Host "VMs: $($vms.count)"
            $vms | Sort-Object Name
        }
    }

    Write-Host
    Write-Host "RDMs: Found $($rdm_selected.count) matching RDM(s)" -ForegroundColor Blue -BackgroundColor Gray
    if($rdm_selected.count -gt 0) { $rdm_selected  }
}
