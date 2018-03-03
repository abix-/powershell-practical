[cmdletbinding()]
Param (
    [Parameter(ParameterSetName="Servers",Mandatory=$true)]$servers,
    [Parameter(ParameterSetName="TCS")]$datacenter,
    [Parameter(ParameterSetName="TCS")]$stack,
    [Parameter(ParameterSetName="TCS")]$role,
    [Parameter(ParameterSetName="Servers",Mandatory=$true)]
    [Parameter(ParameterSetName="TCS",Mandatory=$true)]$service,
    [Parameter(ParameterSetName="TCS")]$range,
    [switch]$get,
    [switch]$stop,
    [switch]$start,
    [switch]$iis = $false,
    $tcscsv = "tcs_servers.csv",
    $settings = "tcs_services.csv"
)

function loadSettings() {
    try {
        $s = import-csv $settings | ?{$_.Service -eq $service}
        Write-Verbose $s
    }

    catch {
        if($role -and !$servers) {
            $s = New-Object PSObject -Property @{
                Service = $service
                Servers = ".*"
                Role = $role
            }
        } else { Write-Host "Failed to recognize or guess service. If guessing, -role is required."; Exit }
    }
    return $s
}

function getServers($_settings) {
    $destinations = @()
    if($PSCmdlet.ParameterSetName -eq "TCS") {
        Write-Verbose "TCS Mode"
        $tcs = Import-Csv $tcscsv
        Write-Verbose "$($tcs.count) servers found in TCS"
        $allservers = $tcs | ?{$_.name -match $_settings.servers -and $_.role -eq $_settings.role} | sort Name
        if($range) { $allservers = $allservers | ?{$_.name -match "*$range" } }
        Write-Verbose "Found $($allservers.count) TCS servers across all environments"       
        if($stack) { foreach($_s in $stack) { $destinations += ($allservers | ?{$_.stack -eq "$_s"} | select -ExpandProperty Name | sort) }
        } elseif($datacenter) { foreach($_d in $datacenter) { $destinations += ($allservers | ?{$_.datacenter -eq "$_d"} | select -ExpandProperty Name | sort) }  }
        else { Write-Host "You must specify a -stack or -datacenter"; Exit }
    } elseif($PSCmdlet.ParameterSetName -eq "Servers") {
        if($servers.EndsWith(".txt")) { $destinations = gc $servers }
    }
    if($destinations.count -eq 0) { Write-Host "No destinations found. Ask Al how to use me."; Exit }
    return $destinations
}

$settings = loadSettings
$servers = getServers $settings
if(!$get -and !$stop -and !$start) { Write-Host "You must use -get, -stop, or -start"; Exit }

if(!$iis) {
    $services = Get-Service -ComputerName $servers -Include $service -Verbose | sort MachineName
    if($get) { $services | select MachineName,Name,Status } 
    elseif ($stop) { $services | sort MachineName | Stop-Service } 
    elseif ($start) { $services | Start-Service }
} else {
    $pool = Get-WmiObject -namespace "root\webadministration" -class applicationpool -computername $servers -Authentication 6 | ?{$_.name -like $service}
    if($get) { 
        $output = @()
        foreach($_p in $pool) {
            switch (($_p.getstate()).returnvalue) {
                "3" { $status = "Stopped" }
                "1" { $status = "Running" }
                default { $status = ($_p.getstate()).returnvalue }
            }
            $output += New-Object PSObject -Property @{
                MachineName = $_p.__Server
                Name = $_p.Name
                Status = $status
            }
        }
        $output | select MachineName,Name,Status
     } 
    elseif ($stop) { $pool.Stop() } 
    elseif ($start) { $pool.Start() }
}