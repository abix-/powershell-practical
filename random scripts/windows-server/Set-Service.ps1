[cmdletbinding()]
Param (
    [Parameter(ParameterSetName="Servers",Mandatory=$true)]$servers,
    [Parameter(ParameterSetName="MyPlatform")]$datacenter,
    [Parameter(ParameterSetName="MyPlatform")]$stack,
    [Parameter(ParameterSetName="MyPlatform")]$role,
    [Parameter(ParameterSetName="Servers",Mandatory=$true)]
    [Parameter(ParameterSetName="MyPlatform",Mandatory=$true)]$service,
    [Parameter(ParameterSetName="MyPlatform")]$range,
    [Parameter(Mandatory=$true)]$startmode,
    $myplatformcsv = "myplatform_servers.csv",
    $settings = "myplatform_services.csv"
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
    if($PSCmdlet.ParameterSetName -eq "MyPlatform") {
        Write-Verbose "MyPlatform Mode"
        $myplatform = Import-Csv $myplatformcsv
        Write-Verbose "$($myplatform.count) servers found in MyPlatform"
        $allservers = $myplatform | ?{$_.name -match $_settings.servers -and $_.role -eq $_settings.role} | sort Name
        if($range) { $allservers = $allservers | ?{$_.name -like "*$range" } }
        Write-Verbose "Found $($allservers.count) MyPlatform servers across all environments"       
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
if($startmode -ne "auto" -and $startmode -ne "demand" -and $startmode -ne "disabled" -and $startmode -ne "delayed-auto") { Write-Host "$startmode is not valid.`nValid startmodes: auto, demand, disabled, delayed-auto"; Exit }

foreach($server in $servers) {
    if((Test-Connection -ComputerName $server -count 1 -ErrorAction 0)) {
        Write-Host "$server - Setting $service to $startmode"
        sc.exe \\$server config "$service" start= $startmode
    } else { Write-Host "$server - Offline" }
}