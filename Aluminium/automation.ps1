function connectvCenter {
    if(-not (Get-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue)){ 
        Add-PSSnapin VMware.VimAutomation.Core
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
        Set-PowerCLIConfiguration -DefaultVIServerMode multiple -confirm:$false | Out-Null
        Try{Disconnect-VIServer * -Force -Confirm:$False}          
        Catch{<# Nothing to do - no open connections!#>}
    }
    if($vcenter -match "6"){
        $vmcred = (Get-Credential -UserName $("$env:USERDOMAIN"+"\"+"$env:USERNAME") -Message "AD Credentials with access to $vCenter")
        Connect-VIServer $vCenter -Credential $vmcred
    }
    else{Connect-VIServer $vCenter}
}

function disconnectvCenter {
    Disconnect-VIServer $vCenter -Confirm:$false
}

function finishUp() {
    writeLog -message "starting finishUp function"
    Remove-Item "\\$isowebstore\ISO\$datetime\$vmhost\$iso" -Recurse:$true -Confirm:$false -Force -Verbose
    Start-Sleep 5
    Remove-Item "\\$isowebstore\ISO\$datetime\" -Recurse:$true -Confirm:$false -Force -Verbose
    writeLog -message "files archived - endoflog"
    if($logpath) { Copy-Item $logpath $archivePath\$("$project"+"_"+"$datetime"+"$filetype") }
    $archivefiles = Get-ChildItem $archivePath | sort LastWriteTime
    if($archivefiles.count -gt $archivefilestokeep) { $archivefiles | select -First ($archivefiles.count - $archivefilestokeep) | Remove-Item }
}

function mountISOpowerOn {
    <#
    .SYNOPSIS
    Mounts an ISO URL to a specified Chassis/Bay, then powers on the blade
    #>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$chassis,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$bay,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$oapw,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ilopw,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()]$iso_url
    )
    
    #Get ILO IP
    $ilo_ip = (data\plink.exe  -l Administrator -pw $hppw $chassis "SHOW SERVER INFO $bay") -match "IP Address:" -replace "IP Address: " -replace "`t"

    $hponcfg_mountiso = @"
HPONCFG BAY  << *
<RIBCL VERSION='2.0'> <LOGIN USER_LOGIN='Administrator' PASSWORD='password'> <RIB_INFO MODE='write'> <INSERT_VIRTUAL_MEDIA DEVICE='CDROM' IMAGE_URL='ISOLOCATION'/> <SET_VM_STATUS DEVICE='CDROM'> <VM_BOOT_OPTION VALUE='CONNECT'/> <VM_WRITE_PROTECT VALUE='YES' /> </SET_VM_STATUS> </RIB_INFO> </LOGIN> </RIBCL>
*
"@ | %{ $_ -Replace "ISOLOCATION", "$iso_url" } | %{ $_ -Replace "BAY",$bay }

$iloiso = $mountisotemp 

    Read-Host "continuing is untested!!!"

    #Mount ISO
    .\plink.exe  -l Admin -pw $oapw $chassis $iloiso

    #Power On
    .\plink.exe  -l iloadmin -pw $ilopw $ilo_ip "power on"
}

function mountESXiso {
    $mountisotemp = @"
    HPONCFG BAY  << *
    <RIBCL VERSION='2.0'> <LOGIN USER_LOGIN='Administrator' PASSWORD='password'> <RIB_INFO MODE='write'> <INSERT_VIRTUAL_MEDIA DEVICE='CDROM' IMAGE_URL='ISOLOCATION'/> <SET_VM_STATUS DEVICE='CDROM'> <VM_BOOT_OPTION VALUE='CONNECT'/> <VM_WRITE_PROTECT VALUE='YES' /> </SET_VM_STATUS> </RIB_INFO> </LOGIN> </RIBCL>
    *
"@
    $setperbootefi = @"
    HPONCFG BAY  << *
    <RIBCL VERSION='2.0'> <LOGIN USER_LOGIN='Administrator' PASSWORD='password'> <SERVER_INFO MODE='write'> <SET_PERSISTENT_BOOT> <DEVICE value = 'Boot000D'/> <DEVICE value = 'Boot000E'/> <DEVICE value = 'Boot0008'/> <DEVICE value = 'Boot0009'/> <DEVICE value = 'Boot000A'/> <DEVICE value = 'Boot000B'/> <DEVICE value = 'Boot000C'/> </SET_PERSISTENT_BOOT> </SERVER_INFO> </LOGIN> </RIBCL>
    *
"@
    $setperbootleg = @"
    HPONCFG BAY  << *
    <RIBCL VERSION='2.0'> <LOGIN USER_LOGIN='Administrator' PASSWORD='password'> <SERVER_INFO MODE='write'> <SET_PERSISTENT_BOOT> <DEVICE value='CDROM'/> <DEVICE value='USB'/> <DEVICE value='HDD'/> <DEVICE value='NETWORK1'/> </SET_PERSISTENT_BOOT> </SERVER_INFO> </LOGIN> </RIBCL>
    *
"@
    $setlegboot = @"
    HPONCFG BAY  << *
    <RIBCL VERSION='2.0'> <LOGIN USER_LOGIN='Administrator' PASSWORD='password'> <SERVER_INFO MODE='write'> <SET_PENDING_BOOT_MODE VALUE='LEGACY'/> </SERVER_INFO> </LOGIN> </RIBCL>
    *
"@
    $iso = Get-ChildItem \\$isowebstore\ISO\$datetime\$vmhost | where {$_.Extension -match "iso"}
    $null = echo y | data\plink.exe -ssh $chassis -l Administrator -pw $hppw exit | Out-Null
    $iloa = data\plink.exe  -l Administrator -pw $hppw $chassis "SHOW SERVER INFO $bay" 
    $ilo = $iloa -match "IP Address:" -replace "IP Address: "
    $iloiso = $mountisotemp | %{ $_ -Replace "ISOLOCATION", "http://$isowebstore/$datetime/$vmhost/$iso" } | %{ $_ -Replace "BAY",$bay }
    $bootorderefi = $setperbootefi | %{ $_ -Replace "BAY",$bay }
    $bootorderlegacy = $setperbootleg | %{ $_ -Replace "BAY",$bay }
    $legacyboot = $setlegboot | %{ $_ -Replace "BAY",$bay }
    if ($($ilo.Trim()) -match $ipvali) {
        $ilo = $($ilo.Trim())
        Write-Host "Got ILO IP of $ilo"
        writeLog -message "Got ILO IP of $ilo"
        $null = echo y | data\plink.exe -ssh $ilo -l Administrator -pw $hppw exit | Out-Null
        Start-Process data\plink.exe -ArgumentList "-l Administrator -pw $hppw $ilo set /map1/enetport1 SystemName=$("$($vmhost.Split(".")[0])"+"-ilo")"
        Write-Host "setILOSystemName"
        writeLog -message "setILOSystemName"
        Start-Sleep 45
        $null = data\plink.exe  -l Administrator -pw $hppw $chassis $bootorderefi
        Write-Host "setPersistentBoot_EFI"
        writeLog -message "setPersistentBoot_EFI"
        Start-Sleep 5
        $null = data\plink.exe  -l Administrator -pw $hppw $chassis $legacyboot
        Write-Host "setLegacyBoot"
        writeLog -message "setLegacyBoot"
        Start-Sleep 5
        $null = data\plink.exe  -l Administrator -pw $hppw $chassis $bootorderlegacy
        Write-Host "setPersistentBoot_Legacy"
        writeLog -message "setPersistentBoot_Legacy"
        Start-Sleep 5
        Write-Host "mounting ISO and powering on server"
        writeLog -message "mounting ISO and powering on server"
        $null = data\plink.exe  -l Administrator -pw $hppw $chassis $iloiso
        Write-Host "setISOconnected"
        writeLog -message "setISOconnected"
        Start-Sleep 5
        data\plink.exe  -l Administrator -pw $hppw $ilo "power on"
    }
    else {
        Write-Host -foregroundcolor Red "ILO IP Address Could not be retreived from HP OA"
        writeLog -message -foregroundcolor Red "ILO IP Address Could not be retreived from HP OA"
        $script:ilo = (Read-Host "Please enter the ILO IP address for bay $bay in $chassis")
        $null = echo y | data\plink.exe -ssh $ilo -l Administrator -pw $hppw exit | Out-Null
        Start-Process data\plink.exe -ArgumentList "-l Administrator -pw $hppw $ilo set /map1/enetport1 SystemName=$("$($vmhost.Split(".")[0])"+"-ilo")"
        Write-Host "setILOSystemName"
        writeLog -message "setILOSystemName"
        Start-Sleep 45
        $null = data\plink.exe  -l Administrator -pw $hppw $chassis $bootorderefi
        Write-Host "setPersistentBoot_EFI"
        writeLog -message "setPersistentBoot_EFI"
        Start-Sleep 5
        $null = data\plink.exe  -l Administrator -pw $hppw $chassis $legacyboot
        Write-Host "setLegacyBoot"
        writeLog -message "setLegacyBoot"
        Start-Sleep 5
        $null = data\plink.exe  -l Administrator -pw $hppw $chassis $bootorderlegacy
        Write-Host "setPersistentBoot_Legacy"
        writeLog -message "setPersistentBoot_Legacy"
        Start-Sleep 5
        Write-Host "mounting ISO and powering on server"
        writeLog -message "mounting ISO and powering on server"
        $null = data\plink.exe  -l Administrator -pw $hppw $chassis $iloiso
        Write-Host "setISOconnected"
        writeLog -message "setISOconnected"
        Start-Sleep 5
        data\plink.exe  -l Administrator -pw $hppw $ilo "power on"
    }
    Write-Host "Calling createDNSentry"
    writeLog -message "Calling createDNSentry"
    createDNSentry
}

function checkILOLicense {
    $ilolictemp = @"
    HPONCFG BAY  << *
    <RIBCL VERSION='2.0'> <LOGIN USER_LOGIN='Administrator' PASSWORD='password'> <RIB_INFO MODE='write'> <LICENSE> <ACTIVATE KEY='PUTYOURILOADVANCEDKEYHERE'/> </LICENSE> </RIB_INFO> </LOGIN> </RIBCL>
    *
"@
    $iloverifytemp = @"
    HPONCFG BAY  << *
    <RIBCL VERSION='2.0'> <LOGIN USER_LOGIN='Administrator' PASSWORD='password'> <RIB_INFO MODE='read'> <GET_ALL_LICENSES/> </RIB_INFO> </LOGIN> </RIBCL>
    *
"@
    $iloliccheck = $iloverifytemp | %{ $_ -Replace "BAY",$bay }
    Write-Host "ILO license check command running on bay $bay in $chassis"
    writeLog -message "ILO license check command running on bay $bay in $chassis"
    $lictype = data\plink.exe  -l Administrator -pw $hppw $chassis $iloliccheck
    if ($lictype -match "Advanced") {
        Write-Host "ILO license found:" $($lictype -match "Advanced").Replace("<LICENSE_TYPE VALUE=","").Replace("/>","").Trim()
        #writeLog -message "ILO license found: $($($lictype -match "Advanced").Replace("<LICENSE_TYPE VALUE=","").Replace("/>","").Trim())"
    }
    elseif ($lictype -match "Standard"){
        Write-Host "ILO license found:" $($lictype -match "Standard").Replace("<LICENSE_TYPE VALUE=","").Replace("/>","").Trim()
        #writeLog -message "ILO license found: $($($lictype -match "Standard").Replace("<LICENSE_TYPE VALUE=","").Replace("/>","").Trim())"
        Write-Host "ILO license not Advanced, installing new license key"
        writeLog -message "ILO license not Advanced, installing new license key"
        $ilolicupdate = $ilolictemp | %{ $_ -Replace "BAY",$bay }
        $installlic = data\plink.exe  -l Administrator -pw $hppw $chassis $ilolicupdate
    }
    Write-Host "Calling mountESXiso"
    writeLog -message "Calling mountESXiso"
    mountESXiso
}

function Add-ILOSysAdminAccount {
    <#
    .SYNOPSIS
    Creates the iloadmin account with full permissions on a specified blade
    .DESCRIPTION
    .Uses plink.exe and HPONCFG to send 
    #>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$chassis,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$bay,
        [string]$oapw,
        [string]$ilopw
    )

    if($oapw.length -eq 0) { $oapw = getAccountCredentials "HP OA Admin" }
    if($ilopw.length -eq 0) { $ilopw = getAccountCredentials "iloadmin" }
    WriteLog -Subject "ILO" -Message "$chassis Bay $bay - Creating iloadmin, changing permissions, and setting password"
    $hponcfg_createaccount = @"
HPONCFG BAY << *
<RIBCL VERSION='2.0'>
    <LOGIN USER_LOGIN='NotUsed' PASSWORD='UsingOAlogin'>
        <USER_INFO MODE='write'>
            <ADD_USER 
                USER_NAME='iloadmin'
                USER_LOGIN='iloadmin'
                PASSWORD='NEWPASSWORD'>
            </ADD_USER>
        </USER_INFO>
    </LOGIN>
</RIBCL>
*
"@ | %{ $_ -Replace "NEWPASSWORD",$ilopw -Replace "BAY",$bay }
    $hponcfg_changepw = @"
HPONCFG BAY << *
<RIBCL VERSION='2.0'>
    <LOGIN USER_LOGIN='NotUsed' PASSWORD='UsingOAlogin'>
        <USER_INFO MODE='write'>
            <MOD_USER USER_LOGIN='iloadmin'>
                <PASSWORD value='NEWPASSWORD'/>
                <ADMIN_PRIV value='Yes'/>
                <REMOTE_CONS_PRIV value='Yes'/>
                <RESET_SERVER_PRIV value='Yes'/>
                <VIRTUAL_MEDIA_PRIV value='Yes'/>
                <CONFIG_ILO_PRIV value='Yes'/>
            </MOD_USER>
        </USER_INFO>
    </LOGIN>
</RIBCL>
*
"@ | %{ $_ -Replace "NEWPASSWORD",$ilopw -Replace "BAY",$bay }
    .\New-VMHost\plink.exe -l Admin -pw $oapw $chassis $hponcfg_createaccount
    .\New-VMHost\plink.exe -l Admin -pw $oapw $chassis $hponcfg_changepw
}

function setHPPowerLevel() {
    [cmdletbinding()]
    param (
        $vmhost,
        $model,
        $rootpw
    )
    #require vcenter connection?
    #enable ssh?

    $conrep_g7 = @"
    <?xml version="1.0" encoding="UTF-8"?>
<Conrep version="4.0.0.0" originating_platform="ProLiant BL490c G7" originating_family="I28" originating_romdate="07/02/2013" originating_processor_manufacturer="Intel">
  <Section name="HP_Power_Regulator" helptext="Allows tuning of the system power usage">HP_Static_High_Performance_Mode</Section>
  <Section name="HP_Power_Profile" helptext="Selects the level of power versus performance for the system.">Maximum_Performance</Section>
  <Section name="NIC_1_Personality">FCoE</Section>
  <Section name="NIC_2_Personality">FCoE</Section>
</Conrep>
"@

    $conrep_g8 = @"
<?xml version="1.0" encoding="UTF-8"?>
<Conrep version="4.0.0.0" originating_platform="ProLiant BL460c Gen8" originating_family="I31" originating_romdate="06/01/2015" originating_processor_manufacturer="Intel">
  <Section name="HP_Power_Regulator" helptext="Allows tuning of the system power usage">HP_Static_High_Performance_Mode</Section>
  <Section name="HP_Power_Profile" helptext="Selects the level of power versus performance for the system.">Maximum_Performance</Section>
  <Section name="NIC_1_Personality">FCoE</Section>
  <Section name="NIC_2_Personality">FCoE</Section>
</Conrep>
"@

    $conrep_g9 = @"
<?xml version="1.0" encoding="UTF-8"?>
<Conrep version="4.0.0.0" originating_platform="ProLiant BL460c Gen9" originating_family="I36" originating_romdate="09/24/2015" originating_processor_manufacturer="Intel(R) Corporation">
  <Section name="HP_Power_Regulator" helptext="Allows tuning of the system power usage">HP_Static_High_Performance_Mode</Section>
  <Section name="HP_Power_Profile" helptext="Selects the level of power versus performance for the system.">Maximum_Performance</Section>
</Conrep>
"@

    if($rootpw.length -eq 0) { $rootpw = Read-Host "root password" }
    switch($model) {
        "G7" { $conrep = $conrep_g7 }
        "G8" { $conrep = $conrep_g8 }
        "G9" { $conrep = $conrep_g9 }
    }
    
    $workingPath = "$projectPath\$datetime"
    New-Item $workingPath -type directory -ErrorAction SilentlyContinue | Out-Null
    $conrep | Out-File "$workingPath\conrep.dat"
    $location = "root"+"@"+"$vmhost"+":/opt/hp/tools/"
    .\New-VMHost\pscp.exe -pw $rootpw "$workingPath\conrep.dat" $location
    .\New-VMHost\plink.exe -l root -pw $rootpw $vmhost "/opt/hp/tools/conrep -l -x /opt/hp/tools/conrep.xml -f /opt/hp/tools/conrep.dat"
}

function createESXiDNS {
    [cmdletbinding()]
    param (
        $VMHostFQDN,
        $VMHostIP,
        $DNSServer,
        $dacred
    )
    if($dacred.length -eq 0) { $dacred = Get-Credential -Message "AD Credentials with access to create DNS records" }
    Write-Debug "test"
    $VMHostSplit = $VMHostFQDN.split(".")
    $VMHostDomain = "$($VMHostSplit[-2]).$($VMHostSplit[-1])"
    $vmhostshort = $VMHostFQDN -replace ".$VMHostDomain",""
    Write-Host "[$($VMHostFQDN)] Creating A and PTR records on $($DNSServer) for $($VMHostIP)"
    Write-Host "dnscmd.exe $($DNSServer) /recordAdd $VMHostDomain $vmhostshort /CreatePTR A $VMHostIP"
    Read-Host "Press enter to create the DNS entries"
    Start-Process dnscmd -ArgumentList "$($DNSServer) /recordAdd $VMHostDomain $vmhostshort /CreatePTR A $VMHostIP" -NoNewWindow -Credential $dacred
}

function joinvCenter {
    [cmdletbinding()]
    param (
        $vmhost,
        $cluster,
        $rootpw
    )

    if($rootpw.length -eq 0) { $rootpw = Read-Host "root password" }

    #Ping host repeatedly until its online
    $alive = $false
    while($alive -eq $false) {
        WriteLog -Subject "vSphere" -Message "Pinging $vmhost"
        $alive = Test-Connection $vmhost -Count 1 -Quiet
        if($alive -eq $false) { Start-Sleep -Seconds 15 }
    }

    WriteLog "Adding host to vCenter"
    Add-VMHost -name $vmhost -location $cluster -user root -password $rootpw -force
}

function enableHostSSH {
    # Check to see if the SSH service is running on the host, if it isn't, start it
    $sshservice = Get-VMHost $vmhost | Get-VMHostService | Where-Object {$_.Key -eq "TSM-SSH"}
    if (!$sshservice.Running) {
        Start-VMHostService -HostService $sshservice -Confirm:$false | Out-Null
        writeLog -message "started sshservice"
    }
}

function disableHostSSH {
    $sshservice = Get-VMHost $vmhost | Get-VMHostService | Where-Object {$_.Key -eq "TSM-SSH"}
    Stop-VMHostService -HostService $SSHService -Confirm:$false | Out-Null
    writeLog -message "stopping sshservice"
}

function renameLocalDS {
    writeLog -message "renaming local datastores"
    $ds = Get-VMHost $vmhost | Get-Datastore | where {$_.Name -match "datastore1*"}
    if ($ds.count -gt 0) {
        $dsname = $vmhost.Name.Replace(".us.local","")
        $newdsname = Set-Datastore $ds -Name $dsname-local -Confirm:$false
        writeLog -message "$ds1 renamed to $dsname-local on $vmhost"
        Write-Host "calling setALUA"
        writeLog -message "calling setALUA"
        setALUA
    }
    else {
        writeLog -message "No local datastore found"
        Write-Host "calling setALUA"
        writeLog -message "calling setALUA"
        setALUA
    }
}

function setSyslog {
    Get-AdvancedSetting -Entity (Get-VMHost $vmhost) -Name "Syslog.global.logHost" | Set-AdvancedSetting -Value $("tcp://" + "$syslogserver" + ":10515") -Confirm:$false
    Get-AdvancedSetting -Entity (Get-VMHost $vmhost) -Name "Syslog.global.logDirUnique" | Set-AdvancedSetting -Value $true -Confirm:$false
}

function setALUA {
    writeLog -message "setting ALUA"
    $set = data\plink.exe -ssh $vmhost -l root -pw $esxpw -batch "esxcli storage nmp satp rule add -s 'VMW_SATP_ALUA' -P 'VMW_PSP_RR' -O 'iops=1' -c 'tpgs_on' -V '3PARdata' -M 'VV' -e 'HP 3PAR Custom Rule'"
    $validate3par = data\plink.exe -ssh $vmhost -l root -pw $esxpw -batch "esxcli storage nmp satp rule list | grep '3PARdata'"
    $set = data\plink.exe -ssh $vmhost -l root -pw $esxpw -batch "esxcli storage nmp satp rule add -s 'VMW_SATP_ALUA' -P 'VMW_PSP_RR' -c 'tpgs_on' -V 'COMPELNT' -e 'Dell Compellent Custom Rule'"
    $validatecml = data\plink.exe -ssh $vmhost -l root -pw $esxpw -batch "esxcli storage nmp satp rule list | grep 'COMPELNT'"
    writeLog -message "$validate3par"
    writeLog -message "$validatecml"
    Write-Host "calling createFirewallRule"
    writeLog -message "calling createFirewallRule"
    createFirewallRule
    #removeStandardSwitch
}

function removeStandardSwitch {
    writeLog -message "removing standard switch"
    $vswitch = Get-VMHost $vmhost | Get-VirtualSwitch | where {$_.Name -match "vSwitch0"}
    Remove-VirtualSwitch $vswitch -Confirm:$false
}

function enterMaintenanceMode {
    $desired = "Enabled"
    $maintModeStatus = Set-VMHost -VMHost $vmhost -State Maintenance
        if ($maintModeStatus -eq "Disabled") {
            do { 
                Write-Host "Waiting for $vmhost to fully enter maintenance mode"
                $entermaint = Set-VMHost -VMHost $vmhost -State Maintenance
                Write-Host "Checking to see if $vmhost entered maintenance mode"
                $current = (data\plink.exe -ssh $vmhost -l root -pw $esxpw -batch "esxcli system maintenanceMode get") -eq $desired
                $maintModeStatus = $current
            } 
            Until ($maintModeStatus -eq $desired)
        }
}

function updateVMHost ($vmhost) {
    if (-not (Get-PSSnapin VMware.VumAutomation -ErrorAction SilentlyContinue)) {
        Add-PSSnapIn VMware.VumAutomation
    }
    $baseline1 = Get-Baseline -Name "Q4 - 2015"
    writeLog -message "putting host $vmhost in maintenance mode"
    enterMaintenanceMode $vmhost
    writeLog -message "scanning host $vmhost"
    Scan-Inventory -Entity $vmhost
    writeLog -message "remediating host $vmhost against $($baseline1.Name)"
    Remediate-Inventory -Entity $vmhost -Baseline $baseline1 -Confirm:$false
}

function getAccountCredentials($account) { return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((Read-Host "Password for $account" -AsSecureString))) }
 
function getCredentials() {
    $securestrings = Import-Csv C:\scripts\securestrings.csv

    $temp = [System.Runtime.InteropServices.marshal]::SecureStringToBSTR((($securestrings | ?{$_.Username -eq "root"}).SecureString | ConvertTo-SecureString))
    $script:rootpw = [System.Runtime.InteropServices.marshal]::PtrToStringAuto($temp)

    $temp = [System.Runtime.InteropServices.marshal]::SecureStringToBSTR((($securestrings | ?{$_.Username -eq "backupadmin"}).SecureString | ConvertTo-SecureString))
    $script:backupadminpw = [System.Runtime.InteropServices.marshal]::PtrToStringAuto($temp)

    $temp = [System.Runtime.InteropServices.marshal]::SecureStringToBSTR((($securestrings | ?{$_.Username -eq "Admin"}).SecureString | ConvertTo-SecureString))
    $script:oapw = [System.Runtime.InteropServices.marshal]::PtrToStringAuto($temp)

    $temp = [System.Runtime.InteropServices.marshal]::SecureStringToBSTR((($securestrings | ?{$_.Username -eq "iloadmin"}).SecureString | ConvertTo-SecureString))
    $script:ilopw = [System.Runtime.InteropServices.marshal]::PtrToStringAuto($temp)

    #$script:rootpw = $securestrings | ?{$_.Username -eq "root"}
    #$script:backupadminpw = getAccountCredentials "backupadmin"
    #$script:oapw = getAccountCredentials "HP OA Admin"
    #$script:ilopw = getAccountCredentials "iloadmin"
    #$script:dacred = Get-Credential -Message "AD Credentials with access to create DNS records"
}

function Get-SecureStringCredentials() {
    [cmdletbinding(DefaultParameterSetName="Credentials")]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Username,
        [string]$secureStringsFile = "C:\scripts\securestrings.csv",
        [Parameter(ParameterSetName="PlainPassword")][switch]$PlainPassword,
        [Parameter(ParameterSetName="Credentials")][switch]$Credentials
    )
    
    try { $secureStrings = Import-Csv $secureStringsFile -ErrorAction Stop }
    catch { Write-Host "Failed to import $secureStringsFile. Aborting."; Return }

    $secureCredentials = @($secureStrings | ?{$_.Username -eq $Username -and $_.SecureString})
    if($secureCredentials.Count -eq 1) {
        switch($PSCmdlet.ParameterSetName) {
            "PlainPassword" {
                $temp = [System.Runtime.InteropServices.marshal]::SecureStringToBSTR(($secureCredentials.SecureString | ConvertTo-SecureString))
                return [System.Runtime.InteropServices.marshal]::PtrToStringAuto($temp)
            }
            "Credentials" {
                return New-Object System.Management.Automation.PSCredential -ArgumentList ($secureCredentials.Username),($secureCredentials.SecureString | ConvertTo-SecureString)
            }
        }
    } elseif($secureCredentials.Count -gt 1) {
        Write-Host "[$username] Multiple matching usernames found. This is not supported. Remove duplicates from $secureStringsFile"
    } else {
        Write-Host "[$username] Username/password not found in $secureStringsFile"
    }
}

function Add-SecureStringCredentials() {
    [cmdletbinding()]
    param (
        [string]$Username,
        [string]$Password,
        [string]$secureStringsFile = "C:\scripts\securestrings.csv"
    )

    if(!($Username)) { $Username = Read-Host "Username" }
    if(!($Password)) { $Password = Read-Host "Password" -AsSecureString | ConvertFrom-SecureString }

    try { $secureStrings = Import-Csv $secureStringsFile -ErrorAction Stop }
    catch { Write-Host "Failed to import $secureStringsFile. Aborting."; Return }
    
    $secureStrings += [pscustomobject][ordered]@{
        Username = $Username
        SecureString = $Password
    }

    $secureStrings | Export-Csv -NoTypeInformation $secureStringsFile
    Write-Host "Added $Username to $secureStringsFile"
}

function createESXiISO {
    [cmdletbinding()]
    param (
        $currenthost,
        $ISO_sourcePath = "C:\Scripts\$project\ISO",
        $rootpw
    )
    #kickstart: disabled bpdu, mpio, syslog
    #5.1 vs 6.0 disable ipv6
    if($rootpw.length -eq 0) { $rootpw = getAccountCredentials "root" }

    Clear-Host
    $workingPath = "$projectPath\$datetime"
    New-Item $workingPath -type directory -ErrorAction SilentlyContinue | Out-Null
    $vmhostfqdn = $($currenthost.VMHost)

    try {
        $installmedia = (Get-ChildItem $ISO_sourcePath -ErrorAction Stop | ?{$_.Extension -eq ".iso" -and $_.Name -like "*$($currenthost.ESXiVersion)*"})
        $installmediapath = $installmedia.FullName
    }
    catch { Write-Host $_.Exception -ForegroundColor Red ; Exit }

    #Licensing
    if ($installmedia -match "ESXi-5") {
        $script:licensekey = "5keyhere"
        $version = "5.x"
    } elseif ($installmedia -match "ESXi-6") {
        $script:licensekey = "6key"
        $version = "6.x"
    } else { 
        writeLog -Subject "CreationCheck" -Message "Could not determine the ESXi version, please check install media and try again" -logfile $logpath
        Break
    }

    $currenthost | select *
    #display license, root pw, ip, netmask, gateway, hostname, dnsserver
    #Write-Host "VMHost FQDN: `t`t$vmhostfqdn"
    #Write-Host "VMHost IP: `t`t$($currenthost.ManagementIP)"
    #Write-Host "VMHost Subnet Mask: `t$($currenthost.SubnetMask)"
    #Write-Host "VMHost Gateway: `t$($currenthost.Gateway)"
    #Write-Host "VMHost DNS: `t`t$($currenthost.DNS1)"
    #Write-Host "VMHost Version: `t$($currenthost.ESXiVersion)"
    #Write-Host ""
    #Write-Host "ESXi ISO: `t`t$($installmedia)"
    #Write-Host "ESXi License: `t`t$($script:licensekey)"
    Write-Host ""
    Write-Host "root PW: $($script:rootpw)"
    Write-Host "Hit enter to start building the ISO"  
    Read-Host

    WriteLog -Subject "CreateKickstart" -Message "Creating for $vmhostfqdn" -LogFile $logpath
    $ksFilename = "$workingPath\KS.CFG"
    Get-Content $projectPath\KS.CFG | %{ $_ -replace "PASSWORD",$script:rootpw -replace "IPADDRESS",$currenthost.ManagementIP -replace "NETWORKMASK",$currenthost.SubnetMask `
        -replace "NETWORKGATEWAY",$currenthost.Gateway -replace "VMHOSTNAME",$vmhostfqdn -replace "DNSSERVER1",$currenthost.DNS1 -replace "DNSSERVER2",$currenthost.DNS2 `
        -replace "LICENSEKEY",$licensekey -replace "VLANMGMT",$currenthost."ManagementVLAN" -replace "DNSSUFFIX",$currenthost.DNSSuffix } | Out-File $ksFilename -Encoding ascii
    WriteLog -Subject "CreateKickstart" -Message "Built at $ksFilename" -LogFile $logpath

    WriteLog -Subject "CreateCustomISO" -Message "Creating for $vmhostfqdn" -LogFile $logpath
    $isoFilename = "$installmedia" + "_$vmhostfqdn" + ".iso"
    $isoFullPath = "$projectPath\$datetime\$isoFilename"
    WriteLog -Subject "CreateCustomISO" -Message "Copying $($installmedia.Fullname) to $($isoFullPath)" -LogFile $logpath
    Copy-Item $installmedia.FullName -Destination $isoFullPath

    #add kickstart to iso
    WriteLog -Subject "CreateCustomISO" -Message "Adding customized BOOT.CFG and KS.CFG" -LogFile $logpath

    #Extract BOOT.CFG, rename BOOT.CFG, add KS.cfg
    Start-Process $projectPath\miso.exe -ArgumentList "$isoFullPath -x $workingPath boot.cfg" -Wait -NoNewWindow
    Copy-Item $workingPath\BOOT.CFG $workingPath\defaultBOOT.CFG
    Get-Content $workingPath\defaultBOOT.CFG | %{ $_ -Replace "kernelopt=runweasel","kernelopt=ks=cdrom:/KS.CFG netdevice=vmnic0" } | Out-File $workingPath\BOOT.CFG -Encoding ascii

    #Delete original boot.cfg
    Start-Process $projectPath\miso.exe -ArgumentList "$isoFullPath -d boot.cfg" -Wait -NoNewWindow
    Start-Process $projectPath\miso.exe -ArgumentList "$isoFullPath -f `"EFI\BOOT`" -d boot.cfg" -Wait -NoNewWindow
    #Add modified boot.cfg
    Start-Process $projectPath\miso.exe -ArgumentList "$isoFullPath -a $workingpath\BOOT.CFG" -Wait -NoNewWindow
    Start-Process $projectPath\miso.exe -ArgumentList "$isoFullPath -f `"EFI\BOOT`" -a $workingpath\BOOT.CFG" -Wait -NoNewWindow
    #Add ks.cfg
    Start-Process $projectPath\miso.exe -ArgumentList "$isoFullPath -a $ksFilename" -Wait -NoNewWindow
    Start-Process $projectPath\miso.exe -ArgumentList "$isoFullPath -f `"EFI\BOOT`" -a $ksFilename" -Wait -NoNewWindow
}

function setESXIPostConfig {
    [cmdletbinding()]
    param(
        $vCenter,
        $VMHost,
        $rootpw,
        $backupadminpw,
        $ntpserver = ""
    )
    
    $obj = Get-VMHost -Server $vCenter -Name $VMHost
    if((Get-VMHostNtpServer -VMHost $obj) -eq "$ntpserver") {
        Write-Host "NTP already configured for $ntpserver"
    } else {
        Write-Host "Setting NTP to time.domain.local"
        Add-VmHostNtpServer -VMHost $obj -NtpServer "time.domain.local"
        Get-VMHostFirewallException -VMHost $obj  | where {$_.Name -eq "NTP client"} | Set-VMHostFirewallException -Enabled:$true
    }
    Write-Host "Starting NTP Service"
    Get-VmHostService -VMHost $obj | Where-Object {$_.key -eq "ntpd"} | Start-VMHostService
    Get-VmHostService -VMHost $obj | Where-Object {$_.key -eq "ntpd"} | Set-VMHostService -policy "automatic"

    if($backupadminpw.length -eq 0) { $backupadminpw = Read-Host "backupadmin password" }
    $esxcli = Get-EsxCli -Server $vCenter -VMHost $VMHost
    if(@($esxcli.system.account.list() | ?{$_.UserID -eq "backupadmin"}).count -eq 0) {
        Write-Host "Creating backupadmin"
        $esxcli.system.account.add("backupadmin","backupadmin","$backupadminpw","$backupadminpw")
    } else {
        Write-Host "backupadmin already exists. Setting password"
        $esxcli.system.account.set("backupadmin","backupadmin","$backupadminpw","$backupadminpw")
    }
    Write-Host "Granting Admin rights for backupadmin"
    $esxcli.system.permission.set($false,"backupadmin","Admin")
}

function pressEnter { Read-Host "Press Enter to continue" }

function New-VMHost {
    <#
    Script: New-VMHost.ps1
    Author: Joe Titra and Al Iannacone
    Version: 2.8

    Todo:
    -spp possible?
    -test onblahhpjax109 -- g9 blades!!
    -better writelog with color support
    -verbose logging
    -ilo keys to cmdletbinding
    -record isofilename and build status?

    Blade
    -changes blade power settings
    #>
    [cmdletbinding()]
    Param (
        $VMHostsFile = "VMHost_testing.csv",
        $project = "New-VMHost",
        $projectPath = "C:\Scripts\$project",
        $logfilePath = "C:\Scripts\$project\Logs",
        $archivefilestokeep = 300,
        $datetime = (Get-Date -format yyyy-MM-dd_HHmmss),
        $isowebstore = "serverwithiishere",
        $logpath = ("$logfilePath\$project"+"_"+"$datetime"+".log")
    )

    #validate whichever settings are possible, display values and confirm
    #select one host at a time, status in column, written back to config
    #once complete, start on next host?

    #Manual Effort
    #determine: hostname, esxi vers, chassis, bay, subnet
    #create tickets: master, ip(management and vmotion), trunking
    #after ESXI installed and WWN logged into fabric: create storage ticket

    #get settings: vcenter name, cluster, chassis, bay, esxi version, syslog? ask for name -- USE CSV!
    #get networking: hostname, management ip, vmotion ip, subnet mask, gateway, dns
    try {
        $script:vmhosts = @(Import-Csv $VMHostsFile -ErrorAction Stop)
        WriteLog -Subject "Initialization" -Message "$($VMHostsFile): Loaded $($script:vmhosts.count) VM Hosts" -logfile $logpath
        #check that no values are blank!
    }
    catch { Write-Host $_.Exception -ForegroundColor Red; Read-host; Exit }

    #Test/create report path
    if(!(Test-Path $logfilePath)){ New-Item $logfilePath -type directory | Out-Null }
    else{ Write-Verbose "$($logfilePath) - Path already exists" }
    $CurrentHostIndex = 0
    $CurrentHost = $vmhosts[$CurrentHostIndex]

    do {
        WriteLog -Subject "Initialization" -Message "Current Host: $($CurrentHost.VMHost)" -logfile $logpath
        Clear-Host
        $scriptPath = (Get-Location).Path
        Write-Host "VM Hosts to build: " -NoNewline
        foreach($_h in $vmhosts) { Write-Host "$($_h.VMhost) " -NoNewline }
        Write-Host ""
        Write-Host "Current Host:`t$($currentHost.VMHost)"
        Write-Host ""
        Write-Host "ESXi root PW: $($script:rootpw)"
        Write-Host "ESXi backupadmin PW: $($script:backupadminpw)"
        Write-Host "OA Admin PW: $($script:oapw)"
        Write-Host "ILO iloadmin PW: $($script:ilopw)"
        Write-Host ""
        Write-Host "1. Load root, backupadmin, OA Admin, and iloadmin credentials from SecureString"
        Write-Host "2. Create iloadmin and set password"
        Write-Host "3. [Testing]Create DNS entry"
        Write-Host "4. Create Custom ESXi ISO"
        Write-Host "5. [Not implemented] Mount ESXi ISO & Power On Blade"
        Write-Host "6. ESXi Required - Set HP Power Profile(G7,G8,G9) and NIC Personality(G7,G8)"
        Write-Host "7. ESXi Required - Add VM Host to vCenter"
        Write-Host "8. ESXi Required - Configure NTP, create backupadmin"
        Write-Host ""
        $option = Read-Host "1-8, vmhost HOSTNAME, exit"
        $lastoption = $option 
        switch -wildcard ($option) {
            "vmhost *" {
                $newvmhostname = $option.Split(" ")[1]
                $newvmhost = @($VMHosts | ?{ $_.VMHost -like "*$newvmhostname*"  })
                if($newvmhost.Count -eq 0) {
                    Write-Host "$newvmhostname not found"
                } elseif($newvmhost.Count -eq 1) {
                    Write-Host "Selecting $($newvmhost[0].VMHost)"
                    $CurrentHost = $newvmhost[0]
                } elseif($newvmhost.Count -eq 2) {
                    Write-Host "More than one VMHost maches '$newvmhostname', selecting $($newvmhost[0].VMHost)."
                    $CurrentHost = $newvmhost[0]
                }
                pressEnter
            }
            "1" { getCredentials }
            "2" { Add-ILOSysAdminAccount -chassis $CurrentHost.chassis -bay $CurrentHost.bay -oapw $script:oapw -ilopw $script:ilopw ; pressEnter }
            "3" { createESXiDNS -VMHostFQDN $currentHost.VMHost -VMHostIP $CurrentHost.ManagementIP -DNSServer $CurrentHost.DNS1 -dacred $script:dacred; pressEnter}
            "4" { createESXiISO -currenthost $CurrentHost -rootpw $script:rootpw ; pressEnter }
            "5" { }
            "6" { setHPPowerLevel -VMHost $CurrentHost.VMHost -Model $CurrentHost.Model -rootpw $script:rootpw; pressEnter }
            "7" { joinvcenter -VMHost $currenthost.VMHost -Cluster $CurrentHost.cluster -rootpw $script:rootpw; pressEnter }
            "8" { setESXIPostConfig -VMHost $CurrentHost.VMhost -vCenter $CurrentHost.vCenter -rootpw $script:rootpw -backupadminpw $script:backupadminpw ; pressEnter }
            "exit" { Exit }
            default { }
        }
    } while ($option -ne "exit")
}

#connectvCenter when? never....check vcenter connection!

##Blade
#run SPP unattended - POSSIBLE?
#change nic personality - POSSIBLE?
#applies ilo license - NEEDED?
#mount custom iso to the ilo console - NEEDED?
#power on

##Provision
#waits for vmhost to finish provisioning
#enter maintenace mode - WHEN?

##Post-Configuration
#changes ESXi DNS settings post-install
#rename local datastores
#change multipathing policies - NEEDED?
#disable various esxi services!
#notify log insight add
#patch with VUM - POSSIBLE?
#connect to Nexus 1K? - POSSIBLE?
#add vMotion IP - POSSIBLE?
#after storage - set syslog and scratch - POSSIBLE?

##Admin
#add to orion - POSSIBLE?
#add to spike - POSSIBLE?
#submit for itam - POSSIBLE?

#collectHostData
#disconnectvCenter

#needs log threshold and rotation

function WriteLog {
    [cmdletbinding()]
    #requires -Version 3.0
    param (
        [Parameter(Mandatory=$true,Position=0)]$subject,
        [Parameter(Mandatory=$true,Position=1)]$message,
        [Parameter(Position=2)]$logfile,
        [Parameter(Position=3)]$fcolor="White"
    )
    $datetime = (Get-Date -Format yyyy-MM-ddTHH:mm:ss)
    if(!$logfile -and $MyInvocation.PSCommandPath -ne $null) {
        $logfile = "$($PSScriptRoot)\$(($MyInvocation.PSCommandPath.Substring($MyInvocation.PSCommandPath.LastIndexOf("\") + 1)) -replace '.ps1').txt"
    } elseif(!$logfile) {
        $logfile = "$($PSScriptRoot)\$($datetime -replace ":").log"
        Write-Verbose "Unable to set log name from script name. Defaulting to $logfile in script directory"
    }
    Write-Verbose "Logging to $logfile"

    Write-Host "[$subject] $message" -ForegroundColor $fcolor
    "$datetime [$subject] $message" | Out-File -FilePath $logfile -Append
    if($color -eq "red") { Write-Host "Aborting script"; Exit }
}


#
function Move-VMtovCenter {
    <#
        .SYNOPSIS
        Move VM(s) between a SourcevCenter and DestinationvCenter. Testing has been done from 5.1(1000v) to 6.0(VDS & 1000v) and 6.0(VDS & 1000v) to 5.1(1000v)
        .DESCRIPTION
        Each VM is Powered Off on the Source, registered on a random host in the Destination cluster, network labels are updated, then the VM is Powered On. By default, confirmation is requested before powering off a VM and VDS switches which start with "N1K" (Ciscso 1000v) are ignored
        .EXAMPLE
        Move VMs listed in testvms.txt from SourevCenter(5.1) to DestinationvCenter(6.0). Do not prompt for confirmation
        Move-VMtovCenter -Names .\testvms.txt -SourcevCenter "vcenter51.domain.local" -DestinationvCenter "vcenter60.domain.local" -Force
        .EXAMPLE
        Move VMs listed in testvms.txt from SourevCenter(6.0) to DestinationvCenter(5.1). Do not prompt for confirmation. Look on Nexus 1Ks when updating VM NIC port group
        Move-VMtovCenter -Names .\testvms.txt -SourcevCenter "vcenter60.domain.local" -DestinationvCenter "vcenter51.domain.local" -Force -UseN1K:$true
        .PARAMETER Names
        A single VM name or the path to a .txt file with a list of VM names.
        .PARAMETER Force
        Defaults to $false. When set to $true, no confirmation is requested before powering off a VM on the SourcevCenter
        .PARAMETER UseN1K
        Defaults to $false. When set to $true, VDS switches which start with "N1K" (Ciscso 1000v) are used when updating VM NIC port groups
        .PARAMETER DestinationCluster
        If specified, VM(s) are migrated into this cluster instead of whichever cluster they are already in
    #>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)]$Names,
        [string]$SourcevCenter = "vcenter51.domain.local",
        [string]$DestinationvCenter = "vcenter60.domain.local",
        [string]$DestinationCluster,
        [switch]$Force = $false,
        [switch]$UseN1K = $false,
        $logfile = "c:\scripts\_VM_Migrations.log",
        $vSphereAdmin = "DOMAIN\admin",
        $SourcePrefix = "_DONOTUSE_"
    )
    #todo 
    ##-validate functional port group 
    ##rename vm after move?
    ##destination network accessible?
    ##add support for partial migration - if renamed and powered off on source, but also powered off on dest(needs nic updated, power on)

    try {
        if($global:DefaultVIServers) { Disconnect-VIServer -Server $global:DefaultVIServers -Force -ErrorAction SilentlyContinue -Confirm:$false }
        $scred = Get-SecureStringCredentials -Username $vSphereAdmin -Credentials
        $dcred = Get-SecureStringCredentials -Username $vSphereAdmin -Credentials
        WriteLog "$SourcevCenter" "Connecting as $vSphereAdmin" $logfile
        Connect-VIServer -Credential $scred -server $SourcevCenter -Protocol https -ErrorAction Stop | Out-Null
        WriteLog "$DestinationvCenter" "Connecting as $vSphereAdmin" $logfile
        Connect-VIServer -Credential $dcred -Server $DestinationvCenter -Protocol https -ErrorAction Stop | Out-Null
    }

    catch {
        WriteLog "ERROR" "Failed to connect to Source and Destination vCenters. Aborting" $logfile "Red"
        Return
    }

    if($Names.EndsWith(".txt")) { 
        $VMNames = @(Get-Content $Names) 
    } else { $VMNames = $Names }

    foreach($Name in $VMNames) {
        #Shutdown VM on SourcevCenter
        $step = "ShutdownAsk"

        try { $source_vm = Get-VM -Server $SourcevCenter -Name $Name -ErrorAction Stop }
        catch { WriteLog "$Name on $SourcevCenter" "VM not found. Skipping" $logfile "Red"; Continue }

        do {
            if($source_vm.PowerState -eq "PoweredOff") {
                WriteLog "$($source_vm.Name) on $SourcevCenter" "VM is powered off" $logfile
            } else {
                if($step -eq "ShutdownAsk") {
                    if(!$Force) { Read-Host "[$($source_vm.Name) on $SourcevCenter] Press enter to attempt guest shutdown" }
                    try {
                        WriteLog "$($source_vm.Name) on $SourcevCenter" "Attempting guest shutdown" $logfile
                        Shutdown-VMGuest -Server $SourcevCenter -VM $source_vm -Confirm:$false -ErrorAction Stop | Out-Null 
                    }
                    catch {
                        if(!$Force) { Read-Host "[$($source_vm.Name) on $SourcevCenter] Guest shutdown failed. Press enter to force shutdown" }
                        WriteLog "$($source_vm.Name) on $SourcevCenter" "Attempting forced shutdown" $logfile
                        Stop-VM -Server $SourcevCenter -VM $source_vm -Confirm:$false | Out-Null
                    }
                    $step = "ShutdownWait"
                } elseif($step -eq "ShutdownWait") {
                    WriteLog "$($source_vm.Name) on $SourcevCenter" "Waiting for VM to shut down" $logfile
                }
            }
            Start-Sleep -Seconds 5
            $source_vm = Get-VM -Server $SourcevCenter -Name $Name
        } while ($source_vm.PowerState -ne "PoweredOff")
   
        #Get VMX, source cluster, and destination VM Host
        $vm_vmx = ($source_vm.ExtensionData.LayoutEx.File | ?{$_.Name -like "*.vmx"}).Name
        Write-Verbose "[$($source_vm.Name)] VMX found at $vm_vmx"
        $vm_cluster = (Get-Cluster -VM $source_vm).Name
        if(!$DestinationCluster) {
            $vm_dest_host =  Get-Cluster -Server $DestinationvCenter -Name $vm_cluster | Get-VMHost | Get-Random
        } else {
            $vm_dest_host = Get-Cluster -Server $DestinationvCenter -Name $DestinationCluster | Get-VMHost | Get-Random
        }
        
        #Register VMX on Destination vCenter
        if(Get-VM -Server $DestinationvCenter -Name $Name -ErrorAction SilentlyContinue) {
            WriteLog "$($source_vm.Name) on $DestinationvCenter" "VM already registered" $logfile
        } else {
            WriteLog "$($source_vm.Name) on $DestinationvCenter" "Registering VMX in Cluster $vm_cluster on $vm_dest_host" $logfile
            New-VM -Server $DestinationvCenter -VMFilePath "$vm_vmx" -VMHost $vm_dest_host | Out-Null
        }

        try { $dest_vm = Get-VM -Server $DestinationvCenter -Name $Name  -ErrorAction Stop }
        catch { $_.Exception.Message; Return }

        #Skip VM if its already PoweredOn in the Destination vCenter
        if($dest_vm.PowerState -eq "PoweredOn") {
            WriteLog "$($dest_vm.Name) on $DestinationvCenter" "VM is already Powered On. Has this already been migrated? Skipping VM" $logfile "DarkYellow"
            continue
        }

        #Rename source VM and add prefix
        $source_vm_newname = $SourcePrefix + ($source_vm.Name)
        WriteLog "$($source_vm.Name) on $DestinationvCenter" "Renaming to $source_vm_newname"
        Set-VM -VM $source_vm -Name $source_vm_newname -Confirm:$false | Out-Null

        #Update port group on all NICs
        $source_nics = @(Get-NetworkAdapter -Server $SourcevCenter -VM $source_vm)
        if($UseN1K) {
            $dest_pgs =  @(Get-VDSwitch -Server $DestinationvCenter -VMHost $vm_dest_host | Get-VDPortgroup)
        } else {
            $dest_pgs =  @(Get-VDSwitch -Server $DestinationvCenter -VMHost $vm_dest_host | ?{$_.Name -notlike "N1K*"} | Get-VDPortgroup)
        }
        
        foreach($_s in $source_nics) {
            $source_networkName = $_s.NetworkName
            $dest_pg = $dest_pgs | ?{$_.Name -eq $source_networkName}
            Write-Debug "test"
            #WriteVerbose "$($dest_vm.Name) on $DestinationvCenter" "$source_networkName - Found $($dest_pg.count) matching port group(s)" $logfile
            if($dest_pg.Count -eq 1) {
                WriteLog "$($dest_vm.Name) on $DestinationvCenter" "$($_s.Name) - $source_networkName - Updating port group " $logfile
                Get-NetworkAdapter -VM $dest_vm | ?{$_.Name -eq $_s.Name} | Set-NetworkAdapter -Portgroup $dest_pg -Confirm:$false | Out-Null
            } elseif($dest_pg.Count -gt 1) {
                WriteLog "$($dest_vm.Name) on $DestinationvCenter" "$($_s.Name) - $source_networkName - Multiple matching port groups located. Aborting" $logfile "Red"
                $dest_pg | Select Name,Key,PortBinding,VDSwitch
                return
            } else {
                WriteLog "$($dest_vm.Name) on $DestinationvCenter" "$($_s.Name) - $source_networkName - Port group NOT FOUND. Aborting" $logfile "Red"
                Return
            }
        }

        #Power On
        WriteLog "$($dest_vm.Name) on $DestinationvCenter" "Powering on" $logfile
        Start-VM -VM $dest_vm -Confirm:$false | Out-Null
        Get-VMQuestion -VM $dest_vm | Set-VMQuestion -Option "button.uuid.movedTheVM" -Confirm:$false        
    }
    Disconnect-VIServer -Server $SourcevCenter -Confirm:$false
    Disconnect-VIServer -Server $DestinationvCenter -Confirm:$false
}

function Start-VMHostMigration {
    [cmdletbinding()]
    Param (
        [Parameter(ParameterSetName="VMHost")][Parameter(ParameterSetName="Cluster")][string]$SourcevCenter = "vcenter51.domain.local",
        [Parameter(ParameterSetName="VMHost")][Parameter(ParameterSetName="Cluster")][string]$DestinationvCenter = "vcenter60.domain.local",
        [Parameter(ParameterSetName="VMHost")]$VMHost = "vmhost51.domain.local",
        [Parameter(ParameterSetName="Cluster",Mandatory=$true)]$Cluster,
        [string]$vSphereAdmin = "DOMAIN\admin",
        $logfile = "c:\scripts\_VM_Migrations.log"
    )

    $servers = @()
    $currentHostIndex = 0
    $lastoption = $null
    $lastmessage = $null

    try {
        if($global:DefaultVIServers) { Disconnect-VIServer -Server $global:DefaultVIServers -Force -ErrorAction SilentlyContinue -Confirm:$false }
        $scred = Get-SecureStringCredentials -Username $vSphereAdmin -Credentials
        $dcred = Get-SecureStringCredentials -Username $vSphereAdmin -Credentials
        WriteLog "$SourcevCenter" "Connecting as $vSphereAdmin" $logfile
        Connect-VIServer -Credential $scred -server $SourcevCenter -Protocol https -ErrorAction Stop | Out-Null
        WriteLog "$DestinationvCenter" "Connecting as $vSphereAdmin" $logfile
        Connect-VIServer -Credential $dcred -Server $DestinationvCenter -Protocol https -ErrorAction Stop | Out-Null
    }

    catch {
        WriteLog "$SourcevCenter & $DestinationvCenter" "Failed to connect to Source and Destination vCenters. Aborting" $logfile "Red"
        Return
    }

    if($cluster) {
        $servers = Get-Cluster -Server $SourcevCenter $cluster | get-vmhost | select -expand Name | sort
    } elseif($VMHost) {
        $servers += $VMHost
    }

    do {
        $currentHost = $servers[$currentHostIndex]
        Clear-Host
        $scriptPath = (Get-Location).Path
        Write-Host "Source vCenter:`t`t$SourcevCenter"
        Write-Host "Destination vCenter:`t$DestinationvCenter"
        Write-Host "VM Hosts to migrate: " -NoNewline
        foreach($_s in $servers) { Write-Host "$_s " -NoNewline }
        Write-Host ""; Write-Host ""
        Write-Host "Current Host:`t$currentHost"
        if($lastoption) { Write-Host "Last option:`t$lastoption" -ForegroundColor Green; Write-Host "$global:lastmessage" -ForegroundColor Green }
        Write-Host ""
        Write-Host "1. Copy DVS configuration to VSS"
        Write-Host "2. [TESTING]Migrate 1 uplink and VMK interfaces to VSS"
        Write-Host "3. [TESTING]Migrate all VMs on DVS to VSS"
        Write-Host "4. [TESTING]Disconnect from all DVS, remove from source vCenter, connect to new vCenter"
        Write-Host "5. [TESTING]Connect to DVS, add 1 uplink, and migrate VMK interfaces to DVS"
        Write-Host "6. [TESTING]Migrate all VMs on VSS to DVS, migrate remaining uplinks to DVS, delete VSS"
        Write-Host ""
        $option = Read-Host "1-6, next host, previous host, exit"
        $lastoption = $option 
        switch($option) {
            "1" { Copy-DVStoVSS -vCenter $SourcevCenter -VMHost $currentHost -Credentials $scred -logfile $logfile; pressEnter }
            "2" { Move-UplinkMgmt_DVStoVSS -vCenter $SourcevCenter -VMHost $currentHost -Credentials $scred -logfile $logfile; pressEnter  }
            "3" {  }
            "4" {  }
            "5" {  }
            "6" {  }
            "next host" { $currentHostIndex++; $lastoption = $null }
            "previous host" { $currentHostIndex--; $lastoption = $null }
            "exit" { Exit }
            default { drawMenu $servers }
        }
    } while($option -ne "exit")
}

function Copy-DVStoVSS {
    [cmdletbinding()]
    Param (
        [string]$vCenter = "vcenter51.domain.local",
        [string]$VMHost = "vmhost51.domain.local",
        $Credentials,
        [string]$logfile
    )
    
    if($global:DefaultVIServers) { Disconnect-VIServer -Server $global:DefaultVIServers -Force -ErrorAction SilentlyContinue -Confirm:$false }

    if(!$Credentials) { $Credentials = Get-Credential -Message "vSphere Administrator for $vCenter" }
    try {
        WriteLog "$vCenter" "Connecting" $logfile
        Connect-VIServer -Credential $Credentials -server $vCenter -Protocol https -ErrorAction Stop | Out-Null
    }
    catch {
        WriteLog "$vCenter" "Failed to connect to vCenter. Aborting" $logfile "Red"
        Return
    }

    try { 
        WriteLog "$vCenter" "Getting VMHost data" $logfile
        $host_obj = Get-VMHost $VMHost -ErrorAction Stop 
    }
    catch { WriteLog "$vCenter" "Failed to read VMHost data" "Red"; Return }

    try { 
        WriteLog "$VMHost" "Getting DVS data" $logfile
        $host_dvs  = Get-VDSwitch -Server $vCenter -VMHost $host_obj  -ErrorAction Stop | sort Name 
    }
    catch { WriteLog "$VMHost" "Failed to read DVS data" "Red"; Return }

    foreach($_d in $host_dvs) {
        $localname = "l-$($_d.name)"
        WriteLog "$vmhost" "$localname - Creating VSS from $($_d.Name)"
        try {
            $vss = New-VirtualSwitch -VMHost $VMHost -Name $localname -ErrorAction Stop
            $dvpgs = Get-VDPortgroup -VDSwitch $_d -ErrorAction Stop | ?{$_.Name -notlike "UPLINKS" -and $_.Name -notlike "Unused_Or_Quarantine_Uplink" -and $_.Name -notlike "Unused_Or_Quarantine_Veth" -and $_.Name -notlike "ESXi-HOST_MGMT" -and $_.Name -notlike "vMOTION"} | sort Name
            foreach($_dvpg in $dvpgs) {
                $vlan = $null
                $vlan = $_dvpg.vlanconfiguration.vlanid
                $pgname = $_dvpg.Name
                WriteLog "$vmhost" "$localname - Creating $pgname port group" $logfile
                if($vlan) { New-VirtualPortGroup -VirtualSwitch $vss -Name $pgname -VLanId $vlan -ErrorAction Stop | Out-Null }
                else { New-VirtualPortGroup -VirtualSwitch $vss -Name $pgname -ErrorAction Stop | Out-Null}
            }
        }
        catch { WriteLog "$vmhost" $_.Exception.Message $logfile "Red" }
    }
    if($global:DefaultVIServers) { Disconnect-VIServer -Server $global:DefaultVIServers -Force -ErrorAction SilentlyContinue -Confirm:$false }
}

function Move-UplinkMgmt_DVStoVSS {
    [cmdletbinding()]
    Param (
        [string]$vCenter = "vcenter51.domain.local",
        [string]$VMHost = "vmhost51.domain.local",
        $Credentials,
        [string]$logfile
    )

    if($global:DefaultVIServers) { Disconnect-VIServer -Server $global:DefaultVIServers -Force -ErrorAction SilentlyContinue -Confirm:$false }

    if(!$Credentials) { $Credentials = Get-Credential -Message "vSphere Administrator for $vCenter" }
    try {
        WriteLog $vCenter "Connecting" $logfile
        Connect-VIServer -Credential $Credentials -server $vCenter -Protocol https -ErrorAction Stop | Out-Null
    }
    catch { WriteLog $vCenter "Failed to connect to vCenter. Aborting" $logfile "Red"; Return }

    try { 
        WriteLog $VMHost "Getting VMHost data" $logfile
        $host_obj = Get-VMHost -Server $vCenter $server -ErrorAction Stop 
    }
    catch { WriteLog $VMHost "Failed to read VMHost data. Aborting" $logfile "Red"; Return }

    try { 
        WriteLog $VMHost "Getting DVS data" $logfile
        $dvs  = Get-VDSwitch -Server $vCenter -VMHost $host_obj -ErrorAction Stop | sort Name 
    }
    catch { WriteLog $VMHost "Failed to read DVS data. Aborting" $logfile "Red"; Return }

    foreach($_d in $dvs) {
        $localname = "l-$($_d.name)"
        $pnic = $null
        $vmk = $null

        try { 
            WriteLog $VMHost "$localname - Getting port group data" $logfile
            $dvpgs = Get-VDPortgroup -VDSwitch $_d -ErrorAction Stop | ?{$_.Name -like "ESXi-HOST_MGMT" -or $_.Name -like "vMOTION"} | sort Name 
        }
        catch { WriteLog $VMHost "$localname - Failed to get port group data" $logfile "Red" }

        try { 
            WriteLog $VMHost "Getting VSS, PNIC, and VMK data" $logfile
            $vss = Get-VirtualSwitch -Standard -VMHost $server -ErrorAction Stop | ?{$_.Name -eq $localname} 
            $pnic = Get-VMHostNetworkAdapter -DistributedSwitch $_d -Physical -ErrorAction Stop | ?{$_.VMHost.Name -eq $server} | sort Name
            $vmk = Get-VMHostNetworkAdapter -DistributedSwitch $_d -VMKernel -ErrorAction Stop | ?{$_.VMHost.Name -eq $server} | sort Name
        }
        catch { WriteLog $VMHost "Failed to read VSS data. Aborting" -color "Red"; Return }
    
        if($pnic.count -ge 2) { $pnic_array = @($pnic | select -First ($pnic.count - 1)) }else { WriteHost "$localname - Only $($pnic.count) physicals NICs found. Skipping." -color "Yellow"; Continue }
        #if($pnic.count/2 -ge 1 -and $pnic.count -gt 0) { $pnic_array = @($pnic | select -First 1) } else { WriteHost "$localname - Only $($pnic.count) physicals NICs found. Skipping." -color "Yellow"; Continue }
    
        $pg_array = @()
        foreach($_v in $vmk) {
            try {
                $vlan = $null
                $vlan = ($dvpgs | ?{$_.Name -eq $_v.PortGroupName}).vlanconfiguration.vlanid
                WriteLog $VMHost "$localname - Creating port group $($_v.PortGroupName) on VLAN $vlan" $logfile
                if($vlan) { $newpg = New-VirtualPortGroup -VirtualSwitch $vss -Name $_v.PortGroupName -VLanId $vlan -ErrorAction Stop }
                else { $newpg = New-VirtualPortGroup -VirtualSwitch $vss -Name $_v.PortGroupName -ErrorAction Stop }
                #Write-Host $pg_array.GetType().ToString()
                $pg_array += $newpg
            }
            catch { WriteLog "ERROR" $_.Exception $logfile ;WriteLog $VMHost "$localname - Failed to create port group $($_v.PortGroupName). Aborting" $logfile "Red"; Return }
        }

        if($vmk -and $pnic) {
            WriteLog $vmhost "$localname - Moving PNIC and $($vmk.count) VMKernel interfaces" $logfile
            Add-VirtualSwitchPhysicalNetworkAdapter -VirtualSwitch $vss -VMHostVirtualNic $vmk -VirtualNicPortgroup $pg_array -VMHostPhysicalNic $pnic_array -Confirm:$false
        } elseif($pnic) {
            WriteLog $VMHost "$localname - Moving PNIC" $logfile
            Add-VirtualSwitchPhysicalNetworkAdapter -VirtualSwitch $vss -VMHostPhysicalNic $pnic_array -Confirm:$false
        }
    }
    if($global:DefaultVIServers) { Disconnect-VIServer -Server $global:DefaultVIServers -Force -ErrorAction SilentlyContinue -Confirm:$false }
}

#helper
#connect to source/destination
#look for vms on dest
#if they are powered on, see if tools is running
#if tools is running, get a non-null ip
#attempt to ping
#once can ping, unregister vm?