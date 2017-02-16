function Get-HPOAInventory {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$OA,
        [string]$Username = "Admin"
    )

    #Todo
    #-support Mezz cards

    $pw = Get-SecureStringCredentials Admin -PlainPassword

    Write-Host "$($OA): Connecting to Onboard Administrator and finding enclosures"
    $main_connection = Connect-HPOA -OA $OA -Username $Username -Password $pw
    Write-Debug "here"
    $enclosures = @(Get-HPOATopology -Connection $main_connection | Select-Object -ExpandProperty LinkedEnclosureInfo | Sort-Object EnclosureName)
    Write-Host "$($OA): $($enclosures.count) enclosures found"

    $inventory = @()
    foreach($_e in $enclosures) {
        Write-Host ""
        Write-Host "$($_e.EnclosureName): Collecting details"
        $_connect = Connect-HPOA -OA $_e.IPAddress -Username $Username -Password $pw
        $_status = Get-HPOAServerStatus -Connection $_connect | Select-Object -expand blade
        $_portmap = Get-HPOAServerPortMap -Connection $_connect | Select-Object -ExpandProperty ServerPortMap
        $inventory += GetServerInfo -connection $_connect -enclosure $_e.EnclosureName -status $_status -portmap $_portmap
    }

    if($inventory.count -gt 0) { Export-Results $inventory -ExportName "HP_Inventory_$OA" }
}

function GetServerInfo($connection,$enclosure,$status,$portmap) {
    $results = @()
    $bays = Get-HPOAServerInfo -Connection $connection | Select-Object -ExpandProperty ServerBlade
    foreach($_b in $bays) {
        if($_b.BladeStatus -eq "No Server Blade Installed") {
            Write-Host "$($_b.Bay): No Server Blade Installed"
            $results += [pscustomobject][ordered]@{
                Enclosure = $enclosure
                Bay = $_b.Bay
                Server_Name = "Blank"
                Status = ""
                Power = ""
                Blade_Model = ""
                Blade_Firmware = ""
                Part_Number = ""
                Serial_Number = ""
                Memory = ""
                CPU_Count = ""
                CPU_Type = ""
                ILO_Type = ""
                ILO_Address = ""
                ILO_Firmware = ""
                MezzCards = ""
                FCoE1 = ""
                FCoE2 = ""
            }
        } else {
            Write-Host "$($_b.Bay): $($_b.ServerName)"
            $_cpu = $_b.CPU  
            $_management = $_b.ManagementProcessorInformation

            if($_b.FlexFabricEmbeddedEthernet) {
                $_flexembedded_fcoe = $_b.FlexFabricEmbeddedEthernet | Get-Member | Where-Object{$_.Name -like "*FCoE*"}
                $_fcoe1 = $_flexembedded_fcoe[0].Definition.Substring($_flexembedded_fcoe[0].Definition.LastIndexOf(" ")+1)
                $_fcoe2 = $_flexembedded_fcoe[1].Definition.Substring($_flexembedded_fcoe[0].Definition.LastIndexOf(" ")+1)
            } elseif($_b.FLBAdapter) {
                $_flbadapter_fcoe = $_b.FLBAdapter | Get-Member | Where-Object{$_.Name -like "*FCoE*"}
                $_fcoe1 = $_flbadapter_fcoe[0].Definition.Substring($_flbadapter_fcoe[0].Definition.LastIndexOf(" ")+1)
                $_fcoe2 = $_flbadapter_fcoe[1].Definition.Substring($_flbadapter_fcoe[0].Definition.LastIndexOf(" ")+1)
            } else {
                $_fcoe1 = "Error"
                $_fcoe1 = "Error"
            }

            $_mezzcards = @($portmap | Where-Object{$_.Bay -eq $_b.Bay} | Select-Object -ExpandProperty PortMapping | Where-Object{$_.Slotstatus -eq "Present"})
            $results += [pscustomobject][ordered]@{
                Enclosure = $enclosure
                Bay = $_b.Bay
                Server_Name = $_b.ServerName
                Status = ($status | Where-Object{$_.Bay -eq $_b.Bay}).Health
                Power = ($status | Where-Object{$_.Bay -eq $_b.Bay}).Power
                Blade_Model = $_b.ProductName
                Blade_Firmware = $_b.ROMVersion
                Part_Number = $_b.PartNumber
                Serial_Number = $_b.SerialNumber
                Memory = $_b.Memory
                CPU_Count = $_cpu.count
                CPU_Type = @($_cpu.value)[0]
                ILO_Type = $_management.Type
                ILO_Address = $_management.IPAddress
                ILO_Firmware = $_management.FirmwareVersion
                MezzCards = $_mezzcards.Count
                FCoE1 = $_fcoe1
                FCoE2 = $_fcoe2
            }
        }
    }  
    Disconnect-HPOA $connection
    return $results
}

function Start-ILO {
    [cmdletbinding()]
    param (
        $Name,
        $HPInventoryPath = "$global:ReportsPath"
    )

    if(!(Test-Path $HPInventoryPath)) {
        Write-Host "Path '$HPInventoryPath' not found. Defaulting to current location" -ForegroundColor Yellow
        $exportPath = (Get-Location).Path
    }

    $HPInventories = Get-ChildItem "$HPInventoryPath\*.csv" | Where-Object{$_.name -like "HP_Inventory_*"}
    $HPInventories | ForEach-Object{ Add-Member -InputObject $_ -MemberType NoteProperty -Name Type -Value ($_.Name -replace "_(\d{8})_(\d{6})\.csv") -Force }
    $OAs = @($HPInventories | Select-Object -Unique -ExpandProperty Type)
    $all = @()
    foreach($_o in $OAs) {
        Write-Host "Working on $_o"
        $all += @(Import-Csv ($HPInventories | Where-Object{$_.Name -like "$_o*.csv"} | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName)
    }
    $filtered = @($all | Where-Object{$_.Server_Name -like "*$Name*"})

    if($filtered.count -ne 1) {
        Write-Host "Select a server from the list"
        for($i = 1; $i -lt $filtered.count + 1; $i++) { Write-Host "[$i] $($filtered[$i-1].Server_Name) `t $($filtered[$i-1].ILO_Address)" }
        $option = Read-Host
    } else { $option = 0 }

    switch -Regex ($option) {
        "\d" { 
            Write-Host "Launching IE for $($filtered[$option-1].Server_Name)"
            Get-SecureStringCredentials -Username admin -PlainPassword | clip.exe
            Start-Process -FilePath "C:\Program Files\Internet Explorer\iexplore.exe" -ArgumentList "http://$($filtered[$option-1].ILO_Address)"
        }
        default { }
    }
}
