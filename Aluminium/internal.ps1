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
        $results,
        $exportPath = (Get-Location).Path,
        $exportName = "results"
    )

    if($exportPath -match "[aA-zZ]:\\$") {
        $exportPath += "Reports\$($exportName)_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
    } else { $exportPath += "\Reports\$($exportName)_$(Get-Date -Format yyyyMMdd_HHmmss).csv" }

    $exportPathParent = Split-Path -Path $exportPath -Parent
    if(!(Test-Path $exportPathParent)) {
        Write-Verbose "Creating $exportPath"
        New-Item -Path $exportPathParent -ItemType Directory | Out-Null
    }

    if($results.count -gt 0) {
        #if(!$exportPath) { $exportPath = "$($PSScriptRoot)\Reports\$(($MyInvocation.PSCommandPath.Substring($MyInvocation.PSCommandPath.LastIndexOf("\") + 1)) -replace '.ps1')" + "_$(Get-Date -Format yyyyMMdd_HHmmss).csv" }
        $results | Export-Csv -NoTypeInformation -Path $exportPath
        Write-Host "Results exported to $exportPath" -ForegroundColor Green
    }
}

function Search-Object {
    param(
        [Parameter(ValueFromPipeline = $true)]$InputObject = $new,
        [Parameter(ParameterSetName='Property')][string]$Property,
        [Parameter(ParameterSetName='Value')][string]$Value,
        [int]$Depth = 3
    )
    if([System.Management.Automation.LanguagePrimitives]::GetEnumerator($InputObject)) { $InputObject = $InputObject[0] }
    $all = GetProperties -Object $InputObject -Depth 0
    Write-Host "[Depth 0] $($all.count) base properties"

    for($i = 1; $i -le $depth; $i++) {
        $this = @($all | ?{$_.Depth -eq ($i - 1) -and $_.Properties -ge 1})
        Write-Host "[Depth $i] $($this.count) properties"
        foreach($_t in $this) {
            $parent = Invoke-Expression "`$InputObject.$($_t.Path)"
            if($i -gt 1) { $conflict = @($all | ?{$_.Value -eq $_t.Value -and $_.Type -eq $_t.Type}) }
            if($conflict.count -lt 3) {
                    $all += GetProperties -Object $parent -Path ($_t.Path) -Depth $i
            } else { Write-Host "Skipping $($_t.Name)" }
        }
    }

    switch($PSCmdlet.ParameterSetName) {
        "Property" { $all | ?{ $_.name -like "*$Property*" } | select Path,Value,Type }
        "Value" { $all | ?{ $_.Value -like "*$Value*" } | select Path,Value,Type }
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
    #Get unique credentials
    $vcenters = Import-Csv "$($PSScriptRoot)\vcenters.csv"
    foreach($_u in ($vcenters.Credentials | select -Unique)) {
        if($cred = Get-SecureStringCredentials -Username $_u -Credentials) {
            Write-Host "Loaded $_u credentials from SecureString"
        } else { $cred = Get-Credential -Message "Enter password" -UserName $_u }
        $vcenters | ?{$_.Credentials -eq $_u} | %{ Add-Member -InputObject $_ -MemberType NoteProperty -Name Credential -Value $cred -Force }
    }

    #Connect PowerShell to all vCenters. Launch vSphere client if flagged
    foreach($_v in $vcenters) {
        Write-Host "[PowerCLI] Connecting to $($_v.vCenter) as $($_v.Credential.Username)"
        Connect-VIServer -Credential $_v.Credential -server $_v.VCenter -Protocol https | Out-Null
        if($_v.StartClient -eq "Yes") {
            Write-Host "[vSphere Client] Connecting to $($_v.vCenter) as $($_v.Credential.Username)"
            Start-Process -FilePath "C:\Program Files (x86)\VMware\Infrastructure\Virtual Infrastructure Client\Launcher\VpxClient.exe" -ArgumentList "-s $($_v.vCenter) -u $($_v.Credential.username) -p $($_v.Credential.GetNetworkCredential().Password)"
        }
    }

    #Run Test-vCenters
    Write-Host "Starting checks against connected vCenters"
    Test-vCenters
}