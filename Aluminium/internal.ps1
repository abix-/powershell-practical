function Set-PowerCLITitle($vcenter) {
    $productName = "PowerCLI"
    $version = Get-PowerCLIVersion
    if($vcenter) { $windowTitle = "[{2}] - $productName {0}.{1}" -f $version.Major, $version.Minor, $vcenter } 
    else { $windowTitle = "$productName {0}.{1}" -f $version.Major, $version.Minor }
    $host.ui.RawUI.WindowTitle = $windowTitle
}

function Export-Results {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeLine=$True)]$results,
        $exportPath = $global:ReportsPath,
        $exportName = "results",
        [switch]$appendTimestamp = $true,
        [switch]$excel = $false
    )

    if(!(Test-Path $exportPath)) {
        Write-Host "Path '$exportPath' not found. Defaulting to current location" -ForegroundColor Yellow
        $exportPath = (Get-Location).Path
    }

    if($exportPath -match "[aA-zZ]:\\$") { $exportPath += "Reports\$($exportName)"} 
    else { $exportPath += "\$($exportName)" }

    if($appendTimestamp) {
        $exportPath += "_$(Get-Date -Format yyyyMMdd_HHmmss)"
    }

    $exportPathParent = Split-Path -Path $exportPath -Parent
    if(!(Test-Path $exportPathParent)) {
        Write-Verbose "Creating $exportPath"
        New-Item -Path $exportPathParent -ItemType Directory | Out-Null
    }

    if($results.count -gt 0) {
        if($excel) {
            $exportPath += ".xlsx"
            $results | Export-Excel -TableName $exportName -TableStyle Medium2 -Path $exportPath -AutoSize
        } else {
            $exportPath += ".csv"
            $results | Export-Csv -NoTypeInformation -Path $exportPath
        }
        Write-Host "Results exported to $exportPath" -ForegroundColor Green
    }
}

function Search-Object {
    param(
        [Parameter(ValueFromPipeline = $true)]$InputObject = $new,
        [Parameter(ParameterSetName='Property')][string]$Property,
        [Parameter(ParameterSetName='Value')][string]$Value,
        [int]$Depth = 1
    )
    if([System.Management.Automation.LanguagePrimitives]::GetEnumerator($InputObject)) { $InputObject = $InputObject[0] }
    $all = GetProperties -Object $InputObject -Depth 0
    Write-Host "[Depth 0] $($all.count) properties"

    for($i = 1; $i -le $depth; $i++) {
        $this = @($all | Where-Object{$_.Depth -eq ($i - 1) -and $_.Properties -ge 1})
        Write-Host "[Depth $i] $($this.count) properties"
        foreach($_t in $this) {
            $parent = Invoke-Expression "`$InputObject.$($_t.Path)"
            #Write-Debug "here"
            Write-Host "[$($_t.Path)] $($_t.type)"
            if($_t.Type -eq "VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost") { Write-Debug "here" }
            $conflict = @($all | Where-Object{$_.Value -eq $_t.Value -and $_.Type -eq $_t.Type})
            if($conflict.count -lt 2) {
                    $newprops = GetProperties -Object $parent -Path ($_t.Path) -Depth $i
                    Write-Debug "hi"
                    foreach($_n in $newprops) {
                        $conflict = @($all | Where-Object{$_.Value -eq $_n.Value -and $_.Type -eq $_n.Type})
                        if($conflict.Count -lt 2) {
                            $all += $_n
                        } else { Write-Host "Skipping sub $($_n.Name)" }
                    }

            } else { Write-Host "Skipping $($_t.Name)" }
        }
    }

    switch($PSCmdlet.ParameterSetName) {
        "Property" { $all | Where-Object{ $_.name -like "*$Property*" } | Select-Object Path,Value,Type }
        "Value" { $all | Where-Object{ $_.Value -like "*$Value*" } | Select-Object Path,Value,Type }
        default { $all }
    }
}

function GetProperties($Object,$Path,$Depth) {
    $results = @()
    if(!$object) { Write-Host "Oops"; return }
    foreach($_c in $object.PSObject.Properties) {
        if($path) { $newpath = "$path.$($_c.Name)" } else { $newpath = "$($_c.Name)" }
        $child = Invoke-Expression "`$InputObject.$newpath"  
        if($child) {
        $child_properties = @($child.PSObject.Properties)
            Write-Verbose "[$depth] [$newpath] $($child_properties.count) sub-properties"
            $results += [pscustomobject][ordered]@{
                Path = $newpath
                Name = $_c.Name
                Value = $_c.Value
                Type = $_c.TypeNameofValue
                IsSettable = $_c.IsSettable
                Properties = ($child_properties.count)
                Depth = $Depth
            }
        } else { Write-Verbose "[$depth] [$newpath] no child found" }
    }
    return $results
}

function Start-Day {
    [cmdletbinding()]
    param ( )
    Connect-vCenter start-day

    #Run Test-vCenters
    Write-Host "Starting checks against connected vCenters"
    Test-vCenter
}

function Set-ClipboardText {
    Add-Type -AssemblyName PresentationCore
    [Windows.Clipboard]::GetText() | clip.exe
}

function Get-IBMInfo {
    Get-VMHost | Sort-Object Name |Get-View |
    Select-Object Name, 
    @{N=“Model“;E={$_.Hardware.SystemInfo.Vendor+ “ “ + $_.Hardware.SystemInfo.Model}},
    @{N="ProcessorType";E={$_.Hardware.CpuPkg.Description -replace '\s+',' '}},
    @{N="ProcessorSockets";E={$_.Hardware.CpuInfo.NumCpuPackages}},
    @{N="ProcessorCores";E={$_.Hardware.CpuInfo.NumCpuCores}} | Export-Csv vmhosts_20160711.csv -NoTypeInformation

    Get-VM | Sort-Object Name | Select-Object Name,@{N="Host";E={$_.VMHost}},@{N="CPU Count";E={$_.NumCPU}} | Export-Csv vms_20160711.csv -NoTypeInformation
}

function Copy-VMHostFiles {
    [cmdletbinding()]
    param (
        $servers,
        $source = $Global:VMHostFirmwarePath
    )

    if($servers.EndsWith(".txt")) { $servers = Get-Content $servers | Sort-Object }

    $rootpw = Get-SecureStringCredentials -PlainPassword -Username root
    $sourcefiles = Get-ChildItem $source

    foreach($_s in $servers) {
        Write-Host "[$_s] Starting SSH and copying files"
        Get-VMHost $_s | Get-VMHostService | Where-Object {$_.Key -eq "TSM-SSH"} | Start-VMHostService
        foreach($file in $sourcefiles) {
            Write-Output y | C:\Scripts\New-VMHost\pscp.exe -scp -pw "$rootpw" "$($file.FullName)" "root@$($_s):/tmp/"
        }
        Get-VMHost $_s | Get-VMHostService | Where-Object {$_.Key -eq "TSM-SSH"} | Stop-VMHostService -Confirm:$false
        Write-Host ""
    }
}

function Import-Variables {
    [cmdletbinding()]
    param (
        $settingsFile = "$PSScriptRoot\settings.csv"
    )

    #If the settings file does not exist
    if(!(Test-Path $settingsFile)) {
        #Create a default settings.csv

        $settings = @()
        Write-Host $settingsFile does not exist. Creating with defaults.
        $settings += [pscustomobject][ordered]@{
            Setting = "AdminUsername"
            Value = "Default"
        }
        $settings += [pscustomobject][ordered]@{
            Setting = "ReportsPath"
            Value = "\\path\to\file"
        }
        $settings += [pscustomobject][ordered]@{
            Setting = "VMHostFirmwarePath"
            Value = "\\path\to\file"
        }

        $settings | Export-Csv $settingsFile -NoTypeInformation
        Import-Variables
    } else {
        #Load the settings and create global variables
        $settings = Import-Csv $settingsFile
        foreach($_s in $settings) {
            Set-Variable -Name $_s.Setting -Value $_s.Value -Scope Global
        }
    }
}

function Set-AdminUsername {
    [cmdletbinding()]
    param (
        $settingsFile = "$PSScriptRoot\settings.csv"
    )

    $newAdminUserName = Read-Host "Username for Administrator actions?"

    #Load the settings
    $settings = Import-Csv $settingsFile
   
    #Remove the old AdminUsername
    $newsettings = $settings | Where-Object{$_.Setting -ne "AdminUsername"}

    #Add the new AdminUsername
    $newsettings += [pscustomobject][ordered]@{
        Setting = "AdminUsername"
        Value = $newAdminUserName
    }

    #Export the new settings
    $newsettings | Export-Csv $settingsFile -NoTypeInformation

    #Import the variables
    Import-Variables
}

Import-Variables
