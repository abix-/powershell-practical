function Get-HPOAInventory {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$OA,
        [string]$Username = "Admin",
        [Parameter(Mandatory=$true)][string]$Password,
        [string]$exportPath = "$($PSScriptRoot)\Reports\HP_Inventory_$($OA)_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
    )

    #Todo
    #-support Mezz cards

    Write-Host "$($OA): Connecting to Onboard Administrator and finding enclosures"
    $main_connection = Connect-HPOA -OA $OA -Username $Username -Password $Password
    $enclosures = @(Get-HPOATopology -Connection $main_connection | select -ExpandProperty LinkedEnclosureInfo | Sort EnclosureName)
    Write-Host "$($OA): $($enclosures.count) enclosures found"

    $inventory = @()
    foreach($_e in $enclosures) {
        Write-Host ""
        Write-Host "$($_e.EnclosureName): Collecting details"
        $_connect = Connect-HPOA -OA $_e.IPAddress -Username $Username -Password $Password
        $_status = Get-HPOAServerStatus -Connection $_connect | select -expand blade
        $inventory += GetServerInfo -connection $_connect -enclosure $_e.EnclosureName -status $_status
    }

    if($inventory.count -gt 0) { Export-Results $inventory -ExportName "HP_Inventory_$OA" }
}

function GetServerInfo($connection,$enclosure,$status) {
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
                FCoE1 = ""
                FCoE2 = ""
            }
        } else {
            Write-Host "$($_b.Bay): $($_b.ServerName)"
            $_cpu = $_b.CPU  
            $_management = $_b.ManagementProcessorInformation

            if($_b.FlexFabricEmbeddedEthernet) {
                $_flexembedded_fcoe = $_b.FlexFabricEmbeddedEthernet | Get-Member | ?{$_.Name -like "*FCoE*"}
                $_fcoe1 = $_flexembedded_fcoe[0].Definition.Substring($_flexembedded_fcoe[0].Definition.LastIndexOf(" ")+1)
                $_fcoe2 = $_flexembedded_fcoe[1].Definition.Substring($_flexembedded_fcoe[0].Definition.LastIndexOf(" ")+1)
            } elseif($_b.FLBAdapter) {
                $_flbadapter_fcoe = $_b.FLBAdapter | Get-Member | ?{$_.Name -like "*FCoE*"}
                $_fcoe1 = $_flbadapter_fcoe[0].Definition.Substring($_flbadapter_fcoe[0].Definition.LastIndexOf(" ")+1)
                $_fcoe2 = $_flbadapter_fcoe[1].Definition.Substring($_flbadapter_fcoe[0].Definition.LastIndexOf(" ")+1)
            } else {
                $_fcoe1 = "Error"
                $_fcoe1 = "Error"
            }
            $results += [pscustomobject][ordered]@{
                Enclosure = $enclosure
                Bay = $_b.Bay
                Server_Name = $_b.ServerName
                Status = ($status | ?{$_.Bay -eq $_b.Bay}).Health
                Power = ($status | ?{$_.Bay -eq $_b.Bay}).Power
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
        $HPInventoryPath = "C:\Scripts\Reports"
    )
    $HPInventories = Get-ChildItem $HPInventoryPath | ?{$_.name -like "HP_Inventory_*"}
    $HPInventories | %{ Add-Member -InputObject $_ -MemberType NoteProperty -Name Type -Value ($_.Name -replace "_(\d{8})_(\d{6})\.csv") -Force }
    $OAs = @($HPInventories | Select-Object -Unique -ExpandProperty Type)
    $all = @()
    foreach($_o in $OAs) { $all += Import-Csv ($HPInventories | ?{$_.Name -like "$_o*"} | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName }
    $filtered = @($all | ?{$_.Server_Name -like "*$Name*"})

    Write-Host "Select a server from the list"
    for($i = 1; $i -lt $filtered.count + 1; $i++) { Write-Host "[$i] $($filtered[$i-1].Server_Name) `t $($filtered[$i-1].ILO_Address)" }
    $option = Read-Host
    switch -Regex ($option) {
        "\d" { 
            Write-Host "Launching IE for $($filtered[$option-1].Server_Name)"
            Start-Process -FilePath "C:\Program Files\Internet Explorer\iexplore.exe" -ArgumentList "http://$($filtered[$option-1].ILO_Address)"
        }
        default { }
    }
}