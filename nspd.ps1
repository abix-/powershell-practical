function SetGlobals() {
    $head = "<style>"
    $head = $head + "BODY{background-color:white;}"
    $head = $head + "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}"
    $head = $head + "TH{border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color:#777d6a}"
    $head = $head + "TD{border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color:#d2d8c7}"
    $global:head = $head + "</style>"
	$global:rawdatadir = "raw"
	$global:reportdir = "reports"
	#$global:ports = "-p '21,22,23,25,53,67,69,80,110,123,135,143,389,443,445,515,995,1433,1434,3389,8530,8531'"
    $global:ports = "-p '22,23,80,443,445'"
	$global:options = "-sT -O -sV --script 'smb-os-discovery'"
}

function gNmap($type,$targets,$ports,$options,$fullpath) {
	LogtoFile "Nmap arguments: $($ports) $($options)"
	LogToFile "$($targets.count) $($type) found"
	if (!(Test-Path -path $fullpath\$rawdatadir)) { $status = mkdir $fullpath\$rawdatadir }
   	foreach($target in $targets) {
   		$count++
		if($type -eq "subnets") {
			$target_file = "$($target.subnet)_$($target.mask)"
			$target_name = "$($target.subnet)/$($target.mask)"
		}
		elseif($type -eq "ips") {
			$target_file = "$($target.ip)"
			$target_name = "$($target.ip)"
		}
		$percentage = "{0:P2}" -f ($count/$targets.count)
       	LogToFile "Starting nmap for $target_name -- $($percentage) complete."
       	$all_args = "$($ports) $($options) -oA '$fullpath\$rawdatadir\$target_file' $($target_name)"
		Invoke-Expression "nmap $all_args"
		LogToFile "Results written to $fullpath\$rawdatadir\$target_file"
   	}
}

#region - Parsing functions
function ParseRawXML($filedir,$fullpath) {
    LogToFile "Reading all XML files into memory."
    $parsed_xml = .$filedir\Parse-Nmap.ps1 "$fullpath\$rawdatadir\*.xml"
    LogToFile "Parsed all XML files into memory."
    return $parsed_xml
}

function ParseWindowsServer($parsed_xml,$fullpath) {
    LogToFile "Parsing Windows Server data from Nmap XML files."
    $windows_servers = $parsed_xml | where {($_.Script -match "Windows") -and ($_.Script -notmatch "Windows XP") -and ($_.Script -notmatch "Windows 7")}
    if($windows_servers) {
        $windows_servers | export-csv -NoTypeInformation "$fullpath\reports\systems\full_windows_servers.csv"
        $windows_servers = $windows_servers | Select-Object @{ Name="Domain"; Expression= {$result = $_.Script -match "\bName:.*"; $hostdomain = $matches[0].Substring(6); $index = $hostdomain.indexof("\"); $hostdomain.substring(0,$index)} },
            @{ Name="Hostname";Expression= {$result = $_.Script -match "\bName:.*"; $hostdomain = $matches[0].Substring(6); $index = $hostdomain.indexof("\"); $hostdomain.substring($index+1)} },
            @{ Name="IP";Expression= {$_.IPv4} },Services,@{ Name="OS";Expression= { $result = $_.Script -match "\bOS:.*"; echo $matches[0].Substring(4) } }
        $windows_servers = $windows_servers | Sort-Object Hostname
        $windows_servers | NiceConvertToHTML "<H2>All Windows Servers</H2>" "Hostname" "700"| out-file "$fullpath\reports\systems\windows_servers.html"
        $windows_servers | export-csv -NoTypeInformation "$fullpath\reports\systems\windows_servers.csv"
        LogToFile "Windows Server information has been written to file."
    }
    else { Write-Host "No Windows Server devices found." }
}

function ParseWindowsXP($parsed_xml,$fullpath) {
    LogToFile "Parsing Windows XP data from Nmap XML files."
    $windows_xp = $parsed_xml | where {($_.Script -match "Windows XP")}
    if($windows_xp)
    {
        #$windows_xp = $windows_xp | Select-Object @{ Name="Hostname";Expression= {$result = $_.Script -match "\bName:.*"; $matches[0].Substring(6)} },@{ Name="IP";Expression= {$_.IPv4} },Services,
        #    @{ Name="OS";Expression= { $result = $_.Script -match "\bOS:.*"; echo $matches[0].Substring(4) } }
        $windows_xp = $windows_xp | Select-Object @{ Name="Domain"; Expression= {$result = $_.Script -match "\bName:.*"; $hostdomain = $matches[0].Substring(6); $index = $hostdomain.indexof("\"); $hostdomain.substring(0,$index)} },
            @{ Name="Hostname";Expression= {$result = $_.Script -match "\bName:.*"; $hostdomain = $matches[0].Substring(6); $index = $hostdomain.indexof("\"); $hostdomain.substring($index+1)} },
            @{ Name="IP";Expression= {$_.IPv4} },Services,@{ Name="OS";Expression= { $result = $_.Script -match "\bOS:.*"; echo $matches[0].Substring(4) } }
		$windows_xp = $windows_xp | Sort-Object Hostname
        $windows_xp | NiceConvertToHTML "<H2>All Windows XP Computers</H2>" | out-file "$fullpath\reports\systems\windows_xp.html" 
        $windows_xp | export-csv -NoTypeInformation "$fullpath\reports\systems\windows_xp.csv"
        LogToFile "Windows XP information has been written to file."
    }
    else { Write-Host "No Windows XP devices found." }
}

function ParseWindows7($parsed_xml,$fullpath) {
    LogToFile "Parsing Windows 7 data from Nmap XML files."
    $windows_7 = $parsed_xml | where {($_.Script -match "Windows 7")}
	Write-Host "hai"
    if($windows_7)
    {
        #$windows_xp = $windows_xp | Select-Object @{ Name="Hostname";Expression= {$result = $_.Script -match "\bName:.*"; $matches[0].Substring(6)} },@{ Name="IP";Expression= {$_.IPv4} },Services,
        #    @{ Name="OS";Expression= { $result = $_.Script -match "\bOS:.*"; echo $matches[0].Substring(4) } }
        $windows_7 = $windows_7 | Select-Object @{ Name="Domain"; Expression= {$result = $_.Script -match "\bName:.*"; $hostdomain = $matches[0].Substring(6); $index = $hostdomain.indexof("\"); $hostdomain.substring(0,$index)} },
            @{ Name="Hostname";Expression= {$result = $_.Script -match "\bName:.*"; $hostdomain = $matches[0].Substring(6); $index = $hostdomain.indexof("\"); $hostdomain.substring($index+1)} },
            @{ Name="IP";Expression= {$_.IPv4} },Services,@{ Name="OS";Expression= { $result = $_.Script -match "\bOS:.*"; echo $matches[0].Substring(4) } }
		$windows_7 = $windows_7 | Sort-Object Hostname
        $windows_7 | NiceConvertToHTML "<H2>All Windows 7 Computers</H2>" | out-file "$fullpath\reports\systems\windows_7.html" 
        $windows_7 | export-csv -NoTypeInformation "$fullpath\reports\systems\windows_7.csv"
        LogToFile "Windows 7 information has been written to file."
    }
    else { Write-Host "No Windows 7 devices found." }
}

function ParseNotWindows($parsed_xml,$fullpath) {
    LogToFile "Parsing Non-Windows data from Nmap XML files."
    $not_windows = $parsed_xml | where {($_.Script -notmatch "Windows")}
    if($not_windows) {
        $not_windows = $not_windows | Select-Object @{ Name="Hostname";Expression= {$_.FQDN} },@{ Name="IP";Expression= {$_.IPv4 } },Services,@{ Name="smb-os-discovery";Expression= {$_.Script} } |
            where {($_.Services -notmatch "Cisco|3Com|Integrated Lights-Out|Canon|3389|Printer|HP|Microsoft Windows|Xerox|Mbedthis-Appweb 2.3.1 ssl|Mbedthis-Appweb 2.0.4|Mbedthis-Appweb 2.4.0|APC")}
        $not_windows = $not_windows | Sort-Object Hostname
        $not_windows | NiceConvertToHTML "<H2>All Non-Windows Devices</H2>" | out-file "$fullpath\reports\systems\not_windows.html" 
        $not_windows | export-csv "$fullpath\reports\systems\not_windows.csv"
        LogToFile "Non-Windows information has been written to file."
    }
    else { Write-Host "No Non-Windows devices found." }
}

function ParseCisco($fullpath) {
	LogToFile "Starting to read all .nmap files into memory"
    $nmap_files = gci $fullpath\$rawdatadir\*.nmap | Select-Object Name
    foreach($nmap_file in $nmap_files) {
        LogToFile "Parsing data from $($nmap_file.Name)"
        $file = Get-Content "$fullpath\$rawdatadir\$($nmap_file.Name)"
        $data = @()
        foreach($line in $file) {
            if ($line -match "\ANmap scan report for") {
                $fullname = $line.substring(21)
                $indexofparen = $fullname.IndexOf("(")
                if($indexofparen -gt 0) {
                    $hostname = $fullname.substring(0,$indexofparen)
                    $indexofendparen = $fullname.IndexOf(")")
                    $ip = $fullname.substring($indexofparen+1)
                    $ip = $ip.substring(0,$ip.length-1)
                }
                else {
                    $ip = $fullname
                    $hostname = "Unknown"
                }
            }
            if ($line -match "\A22/tcp") { $temp = $line.substring(8); $22 = $temp.substring(0,$temp.IndexOf(" ")) }
            if ($line -match "\A23/tcp") { $temp = $line.substring(8); $23 = $temp.substring(0,$temp.IndexOf(" ")) }
            if ($line -match "\ARunning") { $index = $line.IndexOf(":"); $running = $line.substring($index+2) }
            if ($line -match "\AOS details:") { $os = $line.substring(12) }
            if ($line -match "\ADevice type:") { $type = $line.substring(13) }
            if($running) {
                $obj = New-Object PSObject -Property @{
                    "IP" = $ip
                    "Hostname" = $hostname
                    "Port 22" = $22
                    "Port 23" = $23
                    "Device Type" = $type
                    "Running" = $running
                    "OS" = $os
                }
                $data += $obj
                $ip,$22,$23,$running,$os = ""
            }
        }

        $data = $data | Select-Object "IP","Hostname","Port 22","Port 23","Device Type","Running","OS"
        $data = $data | Where {($_.running -match "Cisco|Dell|Juniper|Riverbed") -or ($_.os -match "Cisco|Dell|Juniper|Riverbed")}
        $data = $data | Where {($_.OS -notmatch "Cisco IP Phone")}
        $data = $data | Where {($_."Device Type" -notlike "VoIP phone")}
        $data = $data | Where {($_."Port 22" -notmatch "closed") -or ($_."Port 23" -notmatch "closed")}
        #$data = $data | Where {($_."IP" -notmatch ".129")}
        if ($data) {
            $alldata += $data
        }
    }
	if($alldata) {
	    LogToFile "Outputting final list of Cisco devices to CSV"
		if (!(Test-Path -path $fullpath\$reportdir)) { $status = mkdir $fullpath\$reportdir }
	    $alldata | export-csv "$fullpath\$reportdir\cisco.csv" -NoTypeInformation
	} else { LogToFile "No Cisco devices found" }
}

function ParseItAll($fullpath) {
    if (!(Test-Path -path $fullpath\$reportdir)) { $status = mkdir $fullpath\$reportdir }
    if (!(Test-Path -path $fullpath\reports\systems)) { $status = mkdir $fullpath\reports\systems }
    $filedir = Convert-Path (Get-Location -PSProvider FileSystem)
    $parsed_xml = ParseRawXML $filedir $fullpath
    ParseWindowsServer $parsed_xml $fullpath
    ParseWindowsXP $parsed_xml $fullpath
    ParseNotWindows $parsed_xml $fullpath
    ParseWindows7 $parsed_xml $fullpath
	ParseCisco $fullpath
}
#endregion - Parsing functions

#region - Menu functions
function DrawMenu {
    param ($menuItems, $menuPosition, $menuTitel)
    $fcolor = $host.UI.RawUI.ForegroundColor
    $bcolor = $host.UI.RawUI.BackgroundColor
    $l = $menuItems.length
    cls
    $menuwidth = $menuTitel.length + 4
    Write-Host ("*" * $menuwidth) -fore $fcolor -back $bcolor
    Write-Host "* $menuTitel *" -fore $fcolor -back $bcolor
    Write-Host ("*" * $menuwidth) -fore $fcolor -back $bcolor
    for ($i = 0; $i -le $l;$i++) {
        if ($i -eq $menuPosition) {
            Write-Host "$($menuItems[$i])" -fore $bcolor -back $fcolor
        } else {
            Write-Host "$($menuItems[$i])" -fore $fcolor -back $bcolor
        }
    }
}

function Menu {
    param ([array]$menuItems, $menuTitel = "MENU")
    $vkeycode = 0
    $pos = 0
    DrawMenu $menuItems $pos $menuTitel
    While ($vkeycode -ne 13) {
        $press = $host.ui.rawui.readkey("NoEcho,IncludeKeyDown")
        $vkeycode = $press.virtualkeycode
        Write-host "$($press.character)" -NoNewLine
        If ($vkeycode -eq 38) {$pos--}
        If ($vkeycode -eq 40) {$pos++}
        if ($pos -lt 0) {$pos = 0}
        if ($pos -ge $menuItems.length) {$pos = $menuItems.length -1}
        DrawMenu $menuItems $pos $menuTitel
    }
    Write-Output $($menuItems[$pos])
}

function Main {
    $options = "Nmap subnets and parse XML results","Nmap IPs and parse XML results","Parse Nmap XML results","Perform Server Nmap/NCentral diff","Perform Cisco Nmap/NCentral diff","Nmap subnets for Cisco devices","Parse Nmap results for Cisco devices","Quit"
    $selection = Menu $options "Nmap scanning, parsing, and diffing (NSPD)"
    cls
    SwitchChoices $selection
}

function SwitchChoices($selection) {
    switch ($selection) {
        "Nmap subnets and parse XML results" { gDoNmap "subnets" }
        "Nmap IPs and parse XML results" { gDoNmap "ips" }
        "Parse NMap XML results" { DoNmapParse }
        "Perform Server Nmap/NCentral diff" { DoNmapNCentralDiff }
        "Perform Cisco Nmap/NCentral diff" { DoNmapNCentralDiffCisco }
        "Nmap subnets for Cisco devices" { DoNmapForCisco }
        "Parse Nmap results for Cisco devices" { DoNmapParseCisco }
        "Quit" { Exit }
    }
}
#endregion - Menu functions

#region - Do functions
function gDoNmap($type) {
	$name = Read-Host "Job name"
    $fullpath = MakeFullPath $name
    $targets = @(GetCSV "$type")
    gNmap $type $targets $global:ports $global:options $fullpath
    ParseItAll $fullpath
}

function DoNmapParse {
    $fullpath = GetPath "Path to previous job"
    ParseItAll $fullpath
}

function DoNmapNcentralDiff {
    $fullpath = GetPath "Path to previous job"
    $ncentral = @(GetCSV "NCentral")
    
    $ncentral = $ncentral | select-object @{ Name="Hostname";Expression= {$_."Discovered Name"}},@{ Name="IP";Expression= {$_."Network Address"}},@{Name ="Device Name";Expression= {$_."Device Name"}}  
    $windows_servers = import-csv "$fullpath\reports\systems\windows_servers.csv"
    $diffed = diff -referenceobject $windows_servers -differenceobject $ncentral -property Hostname,IP -includeequal -passthru
    if (!(Test-Path -path $fullpath\reports\ncentral_vs_server_scan_diff)) { $status = mkdir $fullpath\reports\ncentral_vs_server_scan_diff }
    
    $both = $windows_servers | where {$_.SideIndicator -eq '=='}
    $both = $both | Select-Object Domain,Hostname,IP,Services,OS | Sort-Object Hostname
    $both | NiceConvertToHTML "<H2>Devices in NCentral and discovered servers list</H2>" | out-file "$fullpath\reports\ncentral_vs_server_scan_diff\both.html"
    $both | export-csv "$fullpath\reports\ncentral_vs_server_scan_diff\both.csv" -NoType
        
    $ncentral_only = $ncentral | where {$_.SideIndicator -eq '=>'}
    $ncentral_only = $ncentral_only | Select-Object Hostname,IP,"Device Name"| Sort-Object Hostname
    $ncentral_only | NiceConvertToHTML "<H2>Devices only in NCentral</H2>" | out-file "$fullpath\reports\ncentral_vs_server_scan_diff\only_ncentral.html"
    $ncentral_only | export-csv "$fullpath\reports\ncentral_vs_server_scan_diff\only_ncentral.csv" -NoType
        
    $discovered_only = $windows_servers | where {$_.SideIndicator -eq '<='}
    $discovered_only = $discovered_only | Select-Object Domain,Hostname,IP,Services,OS | Sort-Object Hostname
    
    $discovered_only_webserver = $discovered_only | where {$_.Services -match "tcp:80"}
    $discovered_only_webserver | NiceConvertToHTML "Any devices listed here are listening on port 80 and may already be listed in NCentral on another IP.<br>These alternate IPs may need to have the website that runs on the listed IP monitored" | out-file "$fullpath\reports\ncentral_vs_server_scan_diff\not_ncentral_webservers.html"
    $discovered_only_webserver | export-csv "$fullpath\reports\ncentral_vs_server_scan_diff\not_ncentral_webservers.csv" -NoType

    $discovered_only_not_webserver = $discovered_only | where {$_.Services -notmatch "tcp:80"}
    $discovered_only_not_webserver | NiceConvertToHTML "Any devices listed here were <b>not</b> found in NCentral.<br><br>This diff compared the hostname/IP of discovered servers against the NCentral hostname/IP of devices.<br>Devices may be listed here because....<br>-The subnet that the device is on was not scanned because it was not listed in subnets.csv`
        <br>-The server has be decommissioned but not removed from monitoring<br>-The device was off when the subnet was scanned<br>-Hostname/IP in NCentral differs from Hostname/IP of the discovered servers" | out-file "$fullpath\reports\ncentral_vs_server_scan_diff\not_ncentral.html"
    $discovered_only_not_webserver | export-csv "$fullpath\reports\ncentral_vs_server_scan_diff\not_ncentral.csv" -NoType
}

function DoNmapNcentralDiffCisco {
    $fullpath = GetPath "Path to previous job"
    $ncentral = @(GetCSV "NCentral")
    
    $ncentral = $ncentral | select-object @{ Name="IP";Expression= {$_."Network Address"}},@{Name ="Device Name";Expression= {$_."Device Name"}},"Device Class","Make / Model"
    $cisco = import-csv "$fullpath\$reportdir\cisco.csv"
    $diffed = diff -referenceobject $cisco -differenceobject $ncentral -property IP -includeequal -passthru
    if (!(Test-Path -path $fullpath\reports\ncentral_vs_cisco_scan_diff)) { $status = mkdir $fullpath\reports\ncentral_vs_cisco_scan_diff }
    
    $both = $cisco | where {$_.SideIndicator -eq '=='}
    $both = $both | Select-Object IP,Hostname,"Port 22","Port 23","Device Type","Running","OS" | Sort-Object IP
    $both | NiceConvertToHTML "<H2>Devices in NCentral and discovered Cisco devices list</H2>" | out-file "$fullpath\reports\ncentral_vs_cisco_scan_diff\both.html"
    $both | export-csv "$fullpath\reports\ncentral_vs_cisco_scan_diff\both.csv" -NoType
        
    $ncentral_only = $ncentral | where {$_.SideIndicator -eq '=>'}
    $ncentral_only = $ncentral_only | Select-Object IP,"Device Name","Device Class","Make / Model" | Sort-Object IP
    $ncentral_only | NiceConvertToHTML "<H2>Devices only in NCentral</H2>" | out-file "$fullpath\reports\ncentral_vs_cisco_scan_diff\only_ncentral.html"
    $ncentral_only | export-csv "$fullpath\reports\ncentral_vs_cisco_scan_diff\only_ncentral.csv" -NoType
        
    $discovered_only = $cisco | where {$_.SideIndicator -eq '<='}
    $discovered_only = $discovered_only | Select-Object IP,Hostname,"Port 22","Port 23","Device Type","Running","OS" | Sort-Object IP
    $discovered_only| NiceConvertToHTML "<H2>Devices not in NCentral</H2>" | out-file "$fullpath\reports\ncentral_vs_cisco_scan_diff\not_ncentral.html"
    $discovered_only | export-csv "$fullpath\reports\ncentral_vs_cisco_scan_diff\not_ncentral.csv" -NoType
    
}

function DoNmapSCCMDiff {
    $fullpath = GetPath "Path to previous job"
	$sccm = @(GetCSV "SCCM")
	
    $nmap = import-csv "$fullpath\$reportdir\systems\windows_servers.csv"
	$nmap = $nmap | Sort-Object Hostname -Unique | Where {$_.Domain -match "MPS|MODCON|DMZ1|DEVMPS"}
    $diffed = diff -referenceobject $nmap -differenceobject $sccm -property Hostname -includeequal -passthru
    if (!(Test-Path -path $fullpath\$reportdir\wsus_vs_nmap_scan_diff)) { $status = mkdir $fullpath\$reportdir\wsus_vs_nmap_scan_diff }
    
    $both = $nmap | where {$_.SideIndicator -eq '=='}
    $both = $both | Select-Object Domain,Hostname,IP,Services,OS | Sort-Object Hostname
    $both | NiceConvertToHTML "<H2>Devices in SCCM and discovred with Nmap</H2>" | out-file "$fullpath\$reportdir\wsus_vs_nmap_scan_diff\both.html"
    $both | export-csv "$fullpath\$reportdir\wsus_vs_nmap_scan_diff\both.csv" -NoType

	$discovered_only = $nmap | where {$_.SideIndicator -eq '<='}
    $discovered_only = $discovered_only | Select-Object Domain,Hostname,IP,Services,OS | Sort-Object Hostname
    $discovered_only| NiceConvertToHTML "<H2>Devices not in SCCM</H2>" | out-file "$fullpath\$reportdir\wsus_vs_nmap_scan_diff\not_sccm.html"
    $discovered_only | export-csv "$fullpath\$reportdir\wsus_vs_nmap_scan_diff\not_sccm.csv" -NoType
	
	$sccm_only = $sccm | where {$_.SideIndicator -eq '=>'}
    $sccm_only  = $sccm_only  | Select-Object Domain,Hostname,IP,Services,OS | Sort-Object Hostname
    $sccm_only | NiceConvertToHTML "<H2>Devices only in SCCM</H2>" | out-file "$fullpath\$reportdir\wsus_vs_nmap_scan_diff\only_sccm.html"
    $sccm_only | export-csv "$fullpath\$reportdir\wsus_vs_nmap_scan_diff\only_sccm.csv" -NoType
}

function DoNmapForCisco {
    $name = Read-Host "Job name"
    $fullpath = MakeFullPath $name
    $subnets = @(GetCSV "subnet")
    NmapSubnetsCisco $subnets $fullpath
    #ParseNmapFileForCisco $subnets $fullpath
    ParseCisco $fullpath
}

function DoNmapParseCisco {
    $fullpath = GetPath "Path to previous job"
    #$subnets = @(GetCSV "subnet")
    #ParseNmapFileForCisco $subnets $fullpath
	ParseCisco $fullpath
}


#endregion - Do functions

#region - Misc functions
function GetPath($name) {
    $pathvalid = $false
    while(!$pathvalid) {
        $fullpath = Read-Host $name
        if(!(Test-Path $fullpath)) {
            Write-Host "Invalid Path. Try again."
        }
        elseif(!(Test-Path $fullpath\$rawdatadir)) {
            Write-Host "There is no $($rawdatadir) folder at that path. Try again."
        }
        else {
            $pathvalid = $true
            return $fullpath
        } 
    }
}

function MakeFullPath($name) {
    $today = Get-Date -format yyyyMMMdd_HHmmss
    $filedir = Convert-Path (Get-Location -PSProvider FileSystem)
    $fullpath = $filedir + "\" + $name + "_" + $today
    if (!(Test-Path -path $fullpath)) { $status = mkdir $fullpath }
    return $fullpath
}

function GetCSV($name) {
    $csvvalid = $false
    while(!$csvvalid) {
        $subnetfile = Read-Host "Path to $($name) CSV"    
        if(!(Test-Path $subnetfile)) { 
            Write-Host "$($subnetfile) does not exist. Try again."
        }
        elseif(!($subnetfile.substring($subnetfile.LastIndexOf(".")+1) -eq "csv")) {
            Write-Host "$($subnetfile) is not a CSV. Try again."
        }
        else {
			$csv = @(Import-Csv $subnetfile)
            if(!$csv) {
                Write-Host "The CSV is empty. Try again."
            }
            else {
                $csvvalid = $true
                return $csv
            }
        }
    }
}

function LogToFile ([string]$output) { Write-Host $output; "$(Get-Date -format G) -- $($output)" | out-File -append "$fullpath\log.txt" }

function NiceConvertToHTML ($body) { 
    $html = $input | convertto-html -head $global:head -body $body 
    $html | foreach {if($_ -like "*<td>*"){$_ -replace "<td>", "<td><pre>"}elseif($_ -like "*</td>*"){$_ -replace "</td>", "</pre></td>"}else{$_}}
}

function out-excel
{
	param ($worksheetname,$worksheetnumber = 1,[string[]]$property,[switch]$raw)

	begin {
	  # start Excel and open a new workbook
	  Write-Host Starting to write to XLS
	  $Excel = New-Object -Com Excel.Application
	  #$Excel.visible = $True
	  $Excel = $Excel.Workbooks.Add()
	  $Sheet = $Excel.Worksheets.Item($worksheetnumber)
	  # initialize our row counter and create an empty hashtable
	  # which will hold our column headers
	  if($worksheetname) { $Sheet.Name = $worksheetname }
	  $Row = 1
	  $HeaderHash = @{}
	}

	process {
	  if ($_ -eq $null) {return}
	  if ($Row -eq 1) {
	    # when we see the first object, we need to build our header table
	    if (-not $property) {
	      # if we haven’t been provided a list of properties,
	      # we’ll build one from the object’s properties
	      $property=@()
	      if ($raw) {
	        $_.properties.PropertyNames | %{$property+=@($_)}
	      } else {
	        $_.PsObject.get_properties() | % {$property += @($_.Name.ToString())}
	      }
	    }
	   $Column = 1
	    foreach ($header in $property) {
	      # iterate through the property list and load the headers into the first row
	      # also build a hash table so we can retrieve the correct column number
	      # when we process each object
	      $HeaderHash[$header] = $Column
	      $Sheet.Cells.Item($Row,$Column) = $header.toupper()
	      $Column ++
	    }
	    # set some formatting values for the first row
	    $WorkBook = $Sheet.UsedRange
	    $WorkBook.Interior.ColorIndex = 19
	    $WorkBook.Font.ColorIndex = 11
	    $WorkBook.Font.Bold = $True
	    $WorkBook.HorizontalAlignment = -4108
	  }
	  $Row ++
	  foreach ($header in $property) {
	    # now for each object we can just enumerate the headers, find the matching property
	    # and load the data into the correct cell in the current row.
	    # this way we don’t have to worry about missing properties
	    # or the “ordering” of the properties
	    if ($thisColumn = $HeaderHash[$header]) {
	      if ($raw) {
	        $Sheet.Cells.Item($Row,$thisColumn) = [string]$_.properties.$header
	      } else {
	        $Sheet.Cells.Item($Row,$thisColumn) = [string]$_.$header
	      }
	    }
	  }
	  #$Excel.visible = $True
	}

	end {
	  # now just resize the columns and we’re finished
	  if ($Row -gt 1) { [void]$WorkBook.EntireColumn.AutoFit() }
	  $Excel.visible = $True
	  Write-Host Finished writing to XLS
	}
}
#endregion - Misc functions

SetGlobals
Main