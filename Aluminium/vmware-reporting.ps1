function Invoke-ClusterCapacityReport {
    <#
    .SYNOPSIS
    Creates a VMware Cluster Capacity report using data from vCenter and vROPS
    #>

    #http://www.azurefieldnotes.com/2016/08/04/powershellhtmlreportingpart1/
    #Todo
    #change cpu contention to be a top 10/15 list for vms
    #discuss trending during meeting
    #add cmdlet help
    #add csv export. needed? dont think so

    #Steps
    #(2 steps: Get VMHosts & VMs from vCenter
    #11 steps: Do Math
    #4 steps Generate a report, download report, process report, delete report)
    #+
    #5 steps: Assemble HTML report
    #22 steps per cluster + 5 steps

    [cmdletbinding()]
    param (
        [Object[]]$Clusters,
        [Object[]]$AllVMHosts,
        [Object[]]$AllVMs,
        [string]$vROPServer = "VMName",
        [ValidateNotNullOrEmpty()][string]$vROPUser,
        [ValidateNotNullOrEmpty()][string]$vROPPass,
        $ConsolidationRatiosCSV = "$PSScriptRoot\ratios.csv",
        $From = ((Get-Date).AddMonths(-1)),
        $To = (Get-Date),
        [switch]$OnePage = $false
    )

    $results = @()

    $global:vROPsServer = $vROPServer

    Write-Host "Connecting to $vROPServer"
    $vrops = Connect-OMServer -Server $vROPServer -Username $vROPUser -Password $vROPPass
    $usageMHzKey = Get-OMStatKey -Name "cpu|usagemhz_average" -ResourceKind ClusterComputeResource
    $memConsumedKey = Get-OMStatKey -Name "mem|consumed_average" -ResourceKind ClusterComputeResource
    $cpuContentionKey = Get-OMStatKey -Name "cpu|capacity_contentionPct" -ResourceKind ClusterComputeResource
    $ramContentionKey = Get-OMStatKey -Name "mem|host_contentionPct" -ResourceKind ClusterComputeResource

    #Consolidation Ratios Data
    $AllConsolidationRatios = Import-Csv $ConsolidationRatiosCSV

    #Get vROPs Token
    $token = Get-OMRestToken -username $vROPUser -password $vROPPass

    #Create object to store the settings
    $settings = [pscustomobject][ordered]@{
        From = $From
        To = $To
        vROPServer = $vROPServer
        ConsolidationRatioCSV = $ConsolidationRatiosCSV
        GeneratedBy = "$env:UserDomain\$env:Username"
    }

    $timestamp = (Get-Date -Format yyyyMMdd_HHmmss)
    
    foreach($cluster in $Clusters) {
        $cname = $cluster.name

        Write-Host "[$cname] Getting VMHosts and VMs from vCenter results"
        $vmhosts = @($allvmhosts | ?{$_.Cluster -eq $cname})
        
        $vms = @()
        $vmhosts | %{
            $vmhostname =  $_.Name
            $vms += @($AllVMs | ?{$_.VMHostName -eq $vmhostname})
        }
        write-host "[$cname] $($vmhosts.count) VMHosts and $($vms.count) VMs"

        Write-Host "[$cname] Doing Math"
        $vmCount = ($vms | Measure-Object).count
        $vmHostCount = ($vmhosts | Measure-Object).Count

        #Physical Raw Capacity
        $PhysicalRawCapacity = [pscustomobject][ordered]@{
            Name = "Physical Total Capacity"
            "pCPU (cores)" = "{0:N0}" -f [int]($vmhosts | Measure-Object -Property NumCPU -Sum).Sum
            "pCPU (MHz)" = "{0:N1}" -f [float]($vmhosts | Measure-Object -Property CPUTotalMhz -Sum).Sum
            "pRAM (GB)" = "{0:N0}" -f [int]($vmhosts | Measure-Object -Property MemoryTotalGB -Sum).Sum
        }

        #High Availability Buffer: 1 VMHost's resources
        #This works because all of our Clusters have identical VMHosts
        #An alternative might be to sort all VMHosts by highest CPU/RAM and use the first VMHost
        
        #High Availability Buffer
        $haBufferPercent = (@($AllConsolidationRatios | ?{$_.Cluster -eq $cname}) | Select-Object -ExpandProperty "HA Buffer Percent")
        $HABuffer = [pscustomobject][ordered]@{
            Name = "High Availability Buffer"
            "pCPU (cores)" = "{0:N0}" -f [math]::Ceiling(([int]$PhysicalRawCapacity."pCPU (cores)" * ($haBufferPercent/100)))
            "pCPU (MHz)" = "{0:N0}" -f [math]::Ceiling(([float]$PhysicalRawCapacity."pCPU (MHz)" * ($haBufferPercent/100)))
            "pRAM (GB)" = "{0:N0}" -f [math]::Ceiling(([int]$PhysicalRawCapacity."pRAM (GB)" * ($haBufferPercent/100)))
        }

        #Physical Usable Capacity: Total - HA Buffer
        $PhysicalUsableCapacity = [pscustomobject][ordered]@{
            Name = "Physical Usable Capacity"
            "pCPU (cores)" = "{0:N0}" -f ([int]$PhysicalRawCapacity."pCPU (cores)" - $HABuffer."pCPU (cores)")
            "pCPU (MHz)" = "{0:N1}" -f ([float]$PhysicalRawCapacity."pCPU (MHz)" - $HABuffer."pCPU (MHz)")
            "pRAM (GB)" = "{0:N0}" -f ([int]$PhysicalRawCapacity."pRAM (GB)" - $HABuffer."pRAM (GB)")
        }

        #Virtual Consolidation Ratio
        $cpuRatioFull = [string](@($AllConsolidationRatios | ?{$_.Cluster -eq $cname}) | Select-Object -ExpandProperty "vCPU to pCPU Ratio")
        $memRatioFull = [string](@($AllConsolidationRatios | ?{$_.Cluster -eq $cname}) | Select-Object -ExpandProperty "vRAM to pRAM Ratio")
        $VirtualRatio = [pscustomobject][ordered]@{
            Name = "Virtual Consolidation Ratio"
            "vCPU (cores)" = $cpuRatioFull
            "vCPU Multiplier" = [float]($cpuRatioFull.Substring(0,$cpuRatioFull.LastIndexOf(":")))
            "vRAM (GB)" = $memRatioFull
            "vRAM Multiplier" = [float]($memRatioFull.Substring(0,$memRatioFull.LastIndexOf(":")))
        }

        #Virtual Maxium Allocation
        $VirtualMaxAllocation = [pscustomobject][ordered]@{
            Name = "Virtual Usable Capacity"
            "vCPU (cores)" = "{0:N0}" -f ([int]$PhysicalUsableCapacity."pCPU (cores)" * $VirtualRatio."vCPU Multiplier")
            "vRAM (GB)" = "{0:N0}" -f ([int]$PhysicalUsableCapacity."pRAM (GB)" * $VirtualRatio."vRAM Multiplier")
        }

        #VM Allocations
        $VMAllocations = [pscustomobject][ordered]@{
            Name =  "Virtual Machine Allocations"
            Count = ($vms | Measure-Object).Count
            "vCPU (cores)" = "{0:N0}" -f ($vms | Measure-Object -Property NumCPU -Sum).Sum
            "vRAM (GB)" = "{0:N0}" -f ($vms | Measure-Object -Property MemoryGB -Sum).Sum
        }

        #Virtual Available Capacity
        $VirtualAvailableCapacity = [pscustomobject][ordered]@{
            Name = "Virtual Available Capacity"
            "vCPU (cores)" = "{0:N0}" -f ([int]$VirtualMaxAllocation."vCPU (cores)" - $VMAllocations."vCPU (cores)")
            "vRAM (GB)" = "{0:N0}" -f ([int]$VirtualMaxAllocation."vRAM (GB)" - $VMAllocations."vRAM (GB)")
        }

        Write-Host "[$cname] Getting metrics from vROPs"
        $vrops_resource = Get-OMResource -Name $cname -ResourceKind ClusterComputeResource

        #CPU Usage 
        $usageMHzAvgAll = Get-OMStat -Resource $vrops_resource -Key $usageMHzKey -From $From -To $To -RollupType Max -IntervalType Minutes -IntervalCount 60 | Select Resource,Time,Key,@{N="Value";E={ [math]::Round($_.Value,2) }}
        $usageMHz = [pscustomobject][ordered]@{
            Name = "CPU Usage (MHz)"
            Minimum = "{0:N1}" -f ($usageMHzAvgAll | Measure-Object -Property Value -Minimum).Minimum
            Maximum = "{0:N1}" -f ($usageMHzAvgAll | Measure-Object -Property Value -Maximum).Maximum
            Average = "{0:N1}" -f ($usageMHzAvgAll | Measure-Object -Property Value -Average).Average
        }

        #RAM Consumed
        $memConsumedData = Get-OMStat -Resource $vrops_resource -Key $memConsumedKey -From $From -To $To -RollupType Max -IntervalType Minutes -IntervalCount 60 | Select-Object Time,@{N="Value";E={ [math]::Round($_.Value/1024/1024,2) }}
        $memConsumed = [pscustomobject][ordered]@{
            Name = "RAM Consumed (GB)"
            Minimum = "{0:N1}" -f (($memConsumedData | Measure-Object -Property Value -Minimum).Minimum/1024/1024)
            Maximum = "{0:N1}" -f (($memConsumedData | Measure-Object -Property Value -Maximum).Maximum/1024/1024)
            Average = "{0:N1}" -f (($memConsumedData | Measure-Object -Property Value -Average).Average/1024/1024)
        }

        #CPU Average Usage at Start/End of period
        $cpuStart = "{0:N1}" -f (Get-OMStat -Resource $vrops_resource -Key $usageMHzKey -From $From -To ($From).AddDays(5) -RollupType Avg -IntervalType Minutes -IntervalCount 1 | Measure-Object -Property Value -Average).Average
        $cpuEnd = "{0:N1}" -f (Get-OMStat -Resource $vrops_resource -Key $usageMHzKey -From $To.AddDays(-5) -To $To -RollupType Avg -IntervalType Minutes -IntervalCount 1 | Measure-Object -Property Value -Average).Average
        $cpuUsageGrowth = [pscustomobject][ordered]@{
            Name = "Average CPU Usage (MHz)"
            "First 5 Days" = $cpuStart
            "Last 5 Days" = $cpuEnd
            Growth = "{0:N1}" -f ($cpuEnd - $cpuStart)
        }

        #RAM Average Consumption at Start/End of period
        $ramStart = "{0:N1}" -f (Get-OMStat -Resource $vrops_resource -Key $memConsumedKey -From $From -To ($From).AddDays(5) -RollupType Avg -IntervalType Minutes -IntervalCount 1 | Select-Object Time,@{N="Value";E={$_.Value/1024/1024}} | Measure-Object -Property Value -Average).Average
        $ramEnd = "{0:N1}" -f (Get-OMStat -Resource $vrops_resource -Key $memConsumedKey -From $To.AddDays(-5) -To $To -RollupType Avg -IntervalType Minutes -IntervalCount 1 | Select-Object Time,@{N="Value";E={$_.Value/1024/1024}} | Measure-Object -Property Value -Average).Average
        $ramConsumptionGrowth = [pscustomobject][ordered]@{
            Name = "Average RAM Consumption (GB)"
            "First 5 Days" = $ramStart
            "Last 5 Days" = $ramEnd
            Growth = "{0:N1}" -f ($ramEnd -$ramStart)
        }

        #Create VM CPU Contention report through vROPs REST API
        $reportObj = Invoke-OMRestCreateReport -token $token -resourceID $vrops_resource.ID -reportDefinitionID "6c12d374-a34c-4da1-bcb7-d0c5f420e35b"

        #Wait for report generation
        do {
            
           $reportStatus = Get-OMRestReport -token $token -id $reportObj.id
           Write-Host "[$cname] $($reportStatus.Status) VM CPU Contention Report"
           Start-Sleep -Seconds 1
        } while ($reportStatus.Status -ne "COMPLETED")

        #Download VM CPU Contention report
        $cpuReportTemp = "C:\temp\$($cname)_CPU_$($timestamp).csv"
        Invoke-OMRestDownloadReport -token $token -id $reportObj.id | Out-File -FilePath $cpuReportTemp
        $vmCPUContention = Import-Csv -Path $cpuReportTemp | Sort-Object { [float]$_."Max CPU Contention" } -Descending | Select-Object -First 15 @{N="Virtual Machine";E={$_.'ï»¿"Name"'}},`
                                                                 @{N="Cluster";E={$cname}},
                                                                 @{N="Max CPU Contention Float";E={ [float]($_."Max CPU Contention") }},`
                                                                 @{N="Max CPU Contention";E={"$(("{0:N3}" -f ([float]$_."Max CPU Contention")))%"}},`
                                                                 @{N="Min CPU Contention";E={"$(("{0:N3}" -f ([float]$_."Min CPU Contention")))%"}},`
                                                                 @{N="Avg CPU Contention";E={"$(("{0:N3}" -f ([float]$_."Avg CPU Contention")))%"}}                                                                
        Remove-Item $cpuReportTemp
    
        #Create VM RAM Contention report through vROPs REST API
        $reportObj = Invoke-OMRestCreateReport -token $token -resourceID $vrops_resource.ID -reportDefinitionID "2e613c34-8b87-4be0-a995-08f3c65f86e2"

        #Wait for report generation
        do {
           $reportStatus = Get-OMRestReport -token $token -id $reportObj.id
           Write-Host "[$cname] $($reportStatus.Status) VM RAM Contention Report"
           Start-Sleep -Seconds 1
        } while ($reportStatus.Status -ne "COMPLETED")
    

        #Download VM RAM Contention report
        $ramReportTemp = "C:\temp\$($cname)_RAM_$($timestamp).csv"
        Invoke-OMRestDownloadReport -token $token -id $reportObj.id | Out-File -FilePath $ramReportTemp
        $vmRAMContention = Import-Csv -Path $ramReportTemp | Sort-Object { [float]$_."Max RAM Contention" } -Descending | Select-Object -First 15 @{N="Virtual Machine";E={$_.'ï»¿"Name"'}},`
                                                                 @{N="Cluster";E={$cname}},
                                                                 @{N="Max RAM Contention Float";E={ [float]($_."Max RAM Contention") }},`
                                                                 @{N="Max RAM Contention";E={"$(("{0:N3}" -f ([float]$_."Max RAM Contention")))%"}},`
                                                                 @{N="Min RAM Contention";E={"$(("{0:N3}" -f ([float]$_."Min RAM Contention")))%"}},`
                                                                 @{N="Avg RAM Contention";E={"$(("{0:N3}" -f ([float]$_."Avg RAM Contention")))%"}}
        Remove-Item $ramReportTemp
        
        #Create Physical Capacity object
        $PhysicalCapacity = @()
        $PhysicalCapacity += $PhysicalRawCapacity
        $PhysicalCapacity += $HABuffer
        $PhysicalCapacity += $PhysicalUsableCapacity

        #Create Virtual Capacity object
        $VirtualCapacity = @()
        $VirtualCapacity += $VirtualRatio
        $VirtualCapacity += $VirtualMaxAllocation
        $VirtualCapacity += $VMAllocations
        $VirtualCapacity += $VirtualAvailableCapacity

        #Create object to store the results
        $results += [pscustomobject][ordered]@{
            Cluster = $Cluster.Name
            vCenter = (Get-vCenterFromUID $Cluster.UID)
            VMHosts = $vmhosts
            VMHostCount = $vmHostCount
            VMCount = $vmCount
            PhysicalCapacity = $PhysicalCapacity
            VirtualCapacity = $VirtualCapacity
            PhysicalRawCapacity = $PhysicalRawCapacity
            HABuffer = $HABuffer
            PhysicalUsableCapacity = $PhysicalUsableCapacity
            VirtualRatio = $VirtualRatio
            VirtualMaxAllocation = $VirtualMaxAllocation
            VMAllocations = $VMAllocations
            VirtualAvailableCapacity = $VirtualAvailableCapacity
            UsageMHzData = $usageMHzAvgAll
            UsageMHz = $usageMHz
            MemConsumedData = $memConsumedData
            MemConsumed = $memConsumed
            CPUUsageGrowth = $cpuUsageGrowth
            RAMConsumptionGrowth = $ramConsumptionGrowth
            VMCPUContention = $vmCPUContention
            VMRAMContention = $vmRAMContention
        }
    }

    Disconnect-OMServer * -Confirm:$false
    NewClusterCapacityReport -ReportData $results -Settings $settings -OnePage:$OnePage
}

function NewClusterCapacityReport {
    <#
    .SYNOPSIS
    Assembles a HTML report for VMware Cluster Capacity. Should only be called by Invoke-ClusterCapacityReport
    #>
    [cmdletbinding()]
    param (
        $ReportData,
        $Settings,
        $GlossaryCSV = "$PSScriptRoot\glossary.csv",
        $ReportPath = "\\path\to\file",
        [switch]$OnePage = $false
    )

    Import-Module ReportHtml -Force -ErrorAction SilentlyContinue

    $ReportData = @($ReportData | Sort-Object Cluster)

    #Create a comma separated list of the vCenters
    $vCenters = @($ReportData | Select-Object -ExpandProperty vCenter -Unique | Sort-Object)
    $vCenterList = ""
    for($i = 0; $i -lt $vCenters.Count; $i++) {
        $vCenterList += $vCenters[$i]
        if($vCenters[$i +1]) {
            $vCenterList += ", "
        }
    }
    
    #Start the report
    $rpt = @()
    $rpt += Get-HTMLOpenPage -TitleText "VMware Cluster Capacity: $vCenterList" -LeftLogoName Corporate -RightLogoName Alternate

    if(!$OnePage) {
        #Define tabs
        $tabNames = @("Overview") + @($ReportData | Select-Object -ExpandProperty Cluster)
        $rpt += Get-HTMLTabHeader -TabNames $tabNames
    }

    #Physical Capacity Summary
    $PhysicalCapacitySummary = $ReportData | Select-Object Cluster,`
        @{N="Total pCPU (cores)";E={$_.PhysicalRawCapacity."pCPU (cores)"}},`
        @{N="Total pRAM (GB)";E={$_.PhysicalRawCapacity."pRAM (GB)"}},
        @{N="HA Buffer CPU (cores)";E={$_.HABuffer."pCPU (cores)"}},
        @{N="HA Buffer RAM (GB)";E={$_.HABuffer."pRAM (GB)"}},
        @{N="Usable pCPU (cores)";E={$_.PhysicalUsableCapacity."pCPU (cores)"}},
        @{N="Usable pRAM (GB)";E={$_.PhysicalUsableCapacity."pRAM (GB)"}}

    #Virtual Capacity Summary
    $VirtualCapacitySummary = $ReportData | Select-Object Cluster,`
        @{N="vCPU:pCPU Ratio";E={$_.VirtualRatio."vCPU (cores)"}},`
        @{N="vRAM:pCPU Ratio";E={$_.VirtualRatio."vRAM (GB)"}},
        @{N="Usable vCPU (cores)";E={$_.VirtualMaxAllocation."vCPU (cores)"}},
        @{N="Usable vRAM (GB)";E={$_.VirtualMaxAllocation."vRAM (GB)"}},
        @{N="Allocated vCPU (cores)";E={$_.VMAllocations."vCPU (cores)"}},
        @{N="Allocated vRAM (GB)";E={$_.VMAllocations."vRAM (GB)"}},
        @{N="Available vCPU (cores)";E={$_.VirtualAvailableCapacity."vCPU (cores)"}},
        @{N="Available vRAM (GB)";E={$_.VirtualAvailableCapacity."vRAM (GB)"}}

    #Virtual Machine Contention Summaries
    $VMCPUContentionSummary = $ReportData | Select-Object -ExpandProperty VMCPUContention | Sort-Object "Max CPU Contention Float" -Descending | Select "Virtual Machine","Cluster","Max CPU Contention","Min CPU Contention","Avg CPU Contention" | Select-Object -First 30 
    $VMRAMContentionSummary = $ReportData | Select-Object -ExpandProperty VMRAMContention | Sort-Object "Max RAM Contention Float" -Descending | Select "Virtual Machine","Cluster","Max RAM Contention","Min RAM Contention","Avg RAM Contention" | Select-Object -First 30 

    #Overview Tab
    if(!$OnePage) {
        $rpt += Get-HTMLTabContentOpen -TabName "Overview" -TabHeading $null
    } else {
        $rpt += Get-HTMLContentOpen -HeaderText "Overview" -headerClass bigHeader -textClass bigText
    }
        $rpt += Get-HTMLContentOpen -HeaderText "Parameters"
            $rpt += Get-HTMLContentText -Heading "vCenter" -Detail $vCenterList
            $rpt += Get-HTMLContentText -Heading "Clusters" -Detail $ReportData.count
            $rpt += Get-HTMLContentText -Heading "VMHosts" -Detail ($ReportData.VMHostCount | Measure-Object -Sum).Sum
            $rpt += Get-HTMLContentText -Heading "VMs" -Detail ($ReportData.VMCount | Measure-Object -Sum).Sum
            $rpt += Get-HTMLContentText -Heading "From" -Detail $Settings.From
            $rpt += Get-HTMLContentText -Heading "To" -Detail $Settings.To
            $rpt += Get-HTMLContentText -Heading "vRealize Operations Manager Server" -Detail $Settings.vROPServer
            $rpt += Get-HTMLContentText -Heading "Consolidation Ratio CSV" -Detail $Settings.ConsolidationRatioCSV
            $rpt += Get-HTMLContentText -Heading "Generated By" -Detail $Settings.GeneratedBy
        $rpt += Get-HTMLContentClose

        $rpt += Get-HTMLContentOpen -HeaderText "Physical Capacity"
            $rpt += Get-HTMLContentTable -ArrayOfObjects $PhysicalCapacitySummary
        $rpt += Get-HTMLContentClose

        $rpt += Get-HTMLContentOpen -HeaderText "Virtual Capacity"
            $rpt += Get-HTMLContentTable -ArrayOfObjects $VirtualCapacitySummary
        $rpt += Get-HTMLContentClose

        $rpt += Get-HTMLContentOpen -HeaderText "Virtual Machine Contention - Top 30"
            $rpt += Get-HTMLColumn1of2
                $rpt += Get-HTMLContentOpen -HeaderText "CPU Contention"
                $rpt += Get-HTMLContentTable -ArrayOfObjects ($VMCPUContentionSummary | Select-Object "Virtual Machine","Cluster","Max CPU Contention","Min CPU Contention","Avg CPU Contention")
                $rpt += Get-HTMLContentClose
            $rpt += Get-HTMLColumnClose
            $rpt += Get-HTMLColumn2of2
                $rpt += Get-HTMLContentOpen -HeaderText "RAM Contention"
                $rpt += Get-HTMLContentTable -ArrayOfObjects ($VMRAMContentionSummary | Select-Object "Virtual Machine","Cluster","Max RAM Contention","Min RAM Contention","Avg RAM Contention")
                $rpt += Get-HTMLContentClose
            $rpt += Get-HTMLColumnClose
        $rpt += Get-HTMLContentClose

    if(!$OnePage) {
        $rpt += Get-HTMLTabContentClose
    }

    #For each cluster....
    foreach($_r in $ReportData) {

        if(!$OnePage) {
            $rpt += Get-HTMLTabContentOpen -TabName $_r.Cluster -TabHeading $null
        } else {
            $rpt += Get-HTMLContentOpen -HeaderText $_r.Cluster -headerClass bigHeader -textClass bigText
        }

        #Allocated/Available vCPU Pie Chart
        $availablevCPUPieChart = Get-HTMLPieChartObject
        $availablevCPUPieChart.Title = "vCPU (cores)"
        $availablevCPUPieChart.Size.Height = 300
        $availablevCPUPieChart.Size.Width = 300

        #Allocated vCPUs
        $availablevCPUPieData = @()
        $availablevCPUPieData += [pscustomobject]@{
            Name = "Allocated vCPUs"
            Count = [float]$_r.VMAllocations."vCPU (cores)"
            Amount = $_r.VMAllocations."vCPU (cores)"
        }

        #Available vCPUs
        $availableCores = [float]$_r.VirtualAvailableCapacity."vCPU (cores)"
        if($availableCores -lt 0) {
            $availableCores = 0
        }

        $availablevCPUPieData += [pscustomobject]@{
            Name = "Available vCPUs"
            Count = $availableCores
            Amount = $_r.VirtualAvailableCapacity."vCPU (cores)"
        }

        #Allocated/Available vRAM Pie Chart
        $availablevRAMPieChart = Get-HTMLPieChartObject
        $availablevRAMPieChart.Title = "vRAM (GB)"
        $availablevRAMPieChart.Size.Height = 300
        $availablevRAMPieChart.Size.Width = 300

        #Allocated vRAM
        $availablevRAMPieData = @()
        $availablevRAMPieData += [pscustomobject]@{
            Name = "Allocated vRAM"
            Count = [float]$_r.VMAllocations."vRAM (GB)"
            Amount = $_r.VMAllocations."vRAM (GB)"
        }

        #Available vRAM
        $availableRAM = [float]$_r.VirtualAvailableCapacity."vRAM (GB)"
        if($availableRAM -lt 0) {
            $availableRAM = 0
        }

        $availablevRAMPieData += [pscustomobject]@{
            Name = "Available vRAM"
            Count = $availableRAM
            Amount = $_r.VirtualAvailableCapacity."vRAM (GB)"
        }

        #CPU Usage Line Chart
        $cpuUsageLineChart = Get-HTMLLineChartObject -DataSetName "CPU Usage" -DataSetName2 "Physical Usable Capacity"
        $cpuUsageLineChart.Title = "Hourly CPU Usage (MHz)"
        $cpuUsageLineChart.Size.Width = 400

        #CPU Demand Line Chart - Max CPU Limit
        $maxCPURepeat = @()
        $maxCPU = [float]($_r.PhysicalUsableCapacity."pCPU (MHz)")
        foreach($_i in $_r.UsageMHzData) {
            $maxCPURepeat += [pscustomobject]@{
                Value = $maxCPU
            }
        }

        #RAM Consumed Line Chart
        $memConsumedLineChart = Get-HTMLLineChartObject -DataSetName "RAM Consumed" -DataSetName2 "Physical Usable Capacity"
        $memConsumedLineChart.Title = "Hourly RAM Consumption (GB)"
        $memConsumedLineChart.Size.Width = 400

        #RAM Consumed Line Chart - Max Memory Limit
        $maxMemRepeat = @()
        $maxMem = [float]($_r.PhysicalUsableCapacity."pRAM (GB)")
        foreach($_i in $_r.MemConsumedData) {
            $maxMemRepeat += [pscustomobject]@{
                Value = $maxmem
            }
        }

        #Create the report
        $rpt += Get-HTMLContentOpen -HeaderText "Summary"
            $rpt += Get-HTMLContentText -Heading "VMHosts" -Detail $_r.VMHostCount
            $rpt += Get-HTMLContentText -Heading "VMs" -Detail $_r.VMCount
        $rpt += Get-HTMLContentClose

        $rpt += Get-HTMLContentOpen -HeaderText "VMHosts"
            $rpt += Get-HTMLContentTable ($_r.VMHosts | Sort-Object Name | Select-Object Name, Model, @{N="CPU (cores)";E={$_.NumCPU}}, @{N="CPU (MHz)";E={"{0:N1}" -f $_.CPUTotalMHz}}, @{N="RAM (GB)";E={"{0:N0}" -f $_.MemoryTotalGB}})
        $rpt += Get-HTMLContentClose
     
        $rpt += Get-HTMLColumn1of2
            $rpt += Get-HTMLContentOpen -HeaderText "Physical Capacity"
            $rpt += Get-HTMLContentTable -ArrayOfObjects $_r.PhysicalCapacity -NoSortableHeader
            $rpt += Get-HTMLContentClose
        $rpt += Get-HTMLColumnClose

        $rpt += Get-HTMLColumn2of2
            $rpt += Get-HTMLContentOpen -HeaderText "Virtual Capacity"
            $rpt += Get-HTMLContentTable -ArrayOfObjects ($_r.VirtualCapacity | Select-Object Name,"vCPU (cores)","vRAM (GB)") -NoSortableHeader
            $rpt += Get-HTMLContentClose
        $rpt += Get-HTMLColumnClose

        $rpt += Get-HTMLContentOpen -HeaderText "Virtual Resource Availability"
            $rpt += Get-HTMLColumn1of2
                $rpt += Get-HTMLPieChart -ChartObject $availablevCPUPieChart -DataSet $availablevCPUPieData
                $rpt += Get-HTMLContentTable -ArrayOfObjects ($availablevCPUPieData | Select-Object Name,Amount) -NoSortableHeader
            $rpt += Get-HTMLColumnClose
            $rpt += Get-HTMLColumn2of2
                $rpt += Get-HTMLPieChart -ChartObject $availablevRAMPieChart -DataSet $availablevRAMPieData
                $rpt += Get-HTMLContentTable -ArrayOfObjects ($availablevRAMPieData | Select-Object Name,Amount) -NoSortableHeader
            $rpt += Get-HTMLColumnClose
        $rpt += Get-HTMLContentClose

        $rpt += Get-HTMLContentOpen -HeaderText "Physical Resource Usage"
            $rpt += Get-HTMLColumn1of2
                $rpt += Get-HTMLLineChart -ChartObject $cpuUsageLineChart -DataSet $_r.UsageMHzData -DataSet2 $maxCPURepeat
                $rpt += Get-HTMLContentTable -ArrayOfObjects $_r.UsageMHz -NoSortableHeader
                $rpt += Get-HTMLContentTable -ArrayOfObjects $_r.CPUUsageGrowth -NoSortableHeader
            $rpt += Get-HTMLColumnClose
            $rpt += Get-HTMLColumn2of2
                $rpt += Get-HTMLLineChart -ChartObject $memConsumedLineChart -DataSet $_r.MemConsumedData -DataSet2 $maxMemRepeat
                $rpt += Get-HTMLContentTable -ArrayOfObjects $_r.MemConsumed -NoSortableHeader
                $rpt += Get-HTMLContentTable -ArrayOfObjects $_r.RAMConsumptionGrowth -NoSortableHeader
            $rpt += Get-HTMLColumnClose
        $rpt += Get-HTMLContentClose

        $rpt += Get-HTMLContentOpen -HeaderText "Virtual Machine Contention - Top 15"
            $rpt += Get-HTMLColumn1of2
                $rpt += Get-HTMLContentOpen -HeaderText "CPU Contention"
                $rpt += Get-HTMLContentTable -ArrayOfObjects ($_r.VMCPUContention | Sort-Object "Max CPU Contention Float" -Descending | Select-Object "Virtual Machine","Max CPU Contention","Min CPU Contention","Avg CPU Contention")
                $rpt += Get-HTMLContentClose
            $rpt += Get-HTMLColumnClose
            $rpt += Get-HTMLColumn2of2
                $rpt += Get-HTMLContentOpen -HeaderText "RAM Contention"
                $rpt += Get-HTMLContentTable -ArrayOfObjects ($_r.VMRAMContention | Sort-Object "Max RAM Contention Float" -Descending | Select-Object "Virtual Machine","Max RAM Contention","Min RAM Contention","Avg RAM Contention")
                $rpt += Get-HTMLContentClose
            $rpt += Get-HTMLColumnClose
        $rpt += Get-HTMLContentClose
        if(!$OnePage) {
            $rpt += Get-HTMLTabContentClose
        } else {
            $rpt += Get-HTMLContentClose

        }
    }

    #Glossary
    $glossary = Import-Csv -Path $GlossaryCSV
    $rpt += Get-HTMLContentOpen -HeaderText "Glossary" -headerClass bigHeader -textClass bigText 
        $rpt += Get-HTMLContentTable $glossary -NoSortableHeader
    $rpt += Get-HTMLContentClose

    $rpt += Get-HTMLClosePage

    $reportName = "ClusterCapacity"
    if($vCenters.Count -eq 1) {
        $reportName += "_$vCenters"   
    }
    $reportName += "_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Save-HTMLReport -ReportContent $rpt -ReportPath $ReportPath -ReportName $reportName

    #Output report URI to results.prop for Jenkins Environmental Variable injection
    "ReportURI=$ReportPath\$reportName.html" | Out-File "$PSScriptRoot\results.prop" -Encoding ascii
}

Function Get-HTMLLineChartObject {
    <#
	.SYNOPSIS
	Creates a Line Chart object for use with Get-HTMLLineChart
    #>
    [CmdletBinding()]
    param(
		[ValidateSet("line")]
		[String]
		$ChartType = 'line',
		[Parameter(Mandatory=$false)]
		[ValidateSet("Random","Generated")]
		$ColorScheme,
        $DataSetName = "Data",
        $DataSetName2 = "Data"
	)

	$ChartSize = New-Object PSObject -Property @{`
		Width = 500
		Height = 400
	}
	
	$DataDefinition = New-Object PSObject -Property @{`
		DataSetName = $DataSetName
        DataSetName2 = $DataSetName2
		DataNameColumnName = "Time"
		DataValueColumnName = "Value"
	}
	
	if ($ColorScheme -eq "Generated") {$thisColorScheme = 'Generated' + [string](Get-Random -Minimum 1 -Maximum 8)}
	elseif ($ColorScheme -eq "Random") {$thisColorScheme = 'Random' }
	else {$thisColorScheme = 'ColorScheme2'}

	$ChartStyle = New-Object PSObject -Property @{`
		ChartType = $ChartType
		ColorSchemeName = "$thisColorScheme"
		Showlabels= $true
		borderWidth = "1"
		responsive = 'false'
		animateScale = 'true'
        animateRotate = 'true'
		legendPosition = 'bottom'
	}
	
	$ChartObject = New-Object PSObject -Property @{`
		ObjectName = -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_})
		Title = ""
		Size = $ChartSize
		DataDefinition = $DataDefinition
		ChartStyle = $ChartStyle
	}
	
	return $ChartObject
}

Function Get-HTMLLineChart {
    <#
	.SYNOPSIS
	Creates a Line Chart with Chart.js
    #>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true)]
		$ChartObject,
		[Parameter(Mandatory=$true)]
		[Array]
		$DataSet,
		[Parameter(Mandatory=$false)]
        $Options,
        $DataSet2
	)

	$DataCount = $DataSet.Count
	Write-Verbose "Data Set counnt is $DataCount"

	if ($ChartObject.ChartStyle.ColorSchemeName -ne 'Random')
	{
		if ($Options -eq $null) {
			#Write-Verbose "Default Colour Schemes selected, selecting $($ChartObject.ChartStyle.ColorSchemeName)"
			#$ColorSchemes =	Get-HTMLColorSchemes 
			$ChartColorScheme = $GlobalColorSchemes.($ChartObject.ChartStyle.ColorSchemeName) | select -First $DataCount
		} else {
			Write-Verbose "Options Colour Schemes selected, selecting $($ChartObject.ChartStyle.ColorSchemeName)"
			$ChartColorScheme = $Options.ColorSchemes.($ChartObject.ChartStyle.ColorSchemeName) | select -First $DataCount
		}
		if ($ChartColorScheme.Count -lt $DataCount) {
			#Write-Warning ("Colorscheme " +  $ChartObject.ChartStyle.ColorSchemeName + " only has " + $ChartColorScheme.Count + " schemes, you have $DataCount Records.  ")
			Write-Warning "Generating Color Schemes" 
			$ChartColorScheme = GenerateRandomColorScheme -numberofschemes $DataCount
		}
	}
	else
	{
		$ChartColorScheme = GenerateRandomColorScheme -numberofschemes $DataCount
	}
		
	$ofs = ','
	$CJSHeader  = @()
	$CJSHeader += '<canvas id="' + $ChartObject.ObjectName + '" width="'+ $ChartObject.Size.Width + '" height="' + $ChartObject.Size.Height +'"></canvas>'
	$CJSHeader += '<script>'
	$CJSHeader += 'var ctx = document.getElementById("' + $ChartObject.ObjectName + '");'
	$CJSHeader += 'var ' + $ChartObject.ObjectName + ' = new Chart(ctx, {'
	$CJSHeader += "	type: '$($ChartObject.ChartStyle.ChartType)',"
	
	
	$CJSData = @()
	$CJSData = "	data:	{"+ "`n"
	if ($ChartObject.ChartStyle.Showlabels) {
		$ofs ='","'
		$CJSData += '		labels: ["' +"$($DataSet.($ChartObject.DataDefinition.DataNameColumnName))" + '"],' + "`n"
	}
	
	$CJSData += "		datasets: [{" + "`n"
	$CJSData += "			label: '$($chartobject.DataDefinition.datasetname)'," + "`n"
	$ofs =","
    $CJSData += "           fill: false," + "`n"
	$CJSData += "			data: [" + "$($DataSet | % {$_.($ChartObject.DataDefinition.DataValueColumnName)})" +"]," + "`n"
	$ofs ="','"
	$CJSData += "			backgroundColor: ['rgba(75,192,192,0.7)']," + "`n"
	$CJSData += "			borderWidth: $($ChartObject.ChartStyle.borderWidth)," + "`n"
	$CJSData +=	"	        borderColor: 'rgba(75,192,192,1)'," + "`n"
    $CJSData +=	"	        pointBorderColor: 'rgba(75,192,192,1)'," + "`n"
    $CJSData +=	"	        pointBackgroundColor: '#fff'," + "`n"
    $CJSData +=	"	        pointBorderWidth: 1," + "`n"
    $CJSData +=	"	        pointHoverRadius: 1," + "`n"
    $CJSData +=	"	        pointHoverBackgroundColor: 'rgba(75,192,192,1)'," + "`n"
    $CJSData +=	"	        pointHoverBorderColor: 'rgba(220,220,220,1)'," + "`n"
    $CJSData +=	"	        pointHoverBorderWidth: 2," + "`n"
    $CJSData +=	"	        pointRadius: 1," + "`n"
    $CJSData +=	"	        pointHitRadius: 5," + "`n"
    if(!$DataSet2) {
	    $CJSData += "		}]"+ "`n"
    } else {
        $CJSData += "	},{" + "`n"
        $CJSData += "			label: '$($chartobject.DataDefinition.datasetname2)'," + "`n"
        $CJSData += "           fill: false," + "`n"
        $CJSData += "			data: ['" + "$($DataSet2 | % {$_.($ChartObject.DataDefinition.DataValueColumnName)})" +"']," + "`n"
        $ofs ="','"
        $CJSData +=	"	        pointRadius: 0," + "`n"
        $CJSData +=	"	        borderWidth: 3," + "`n"
        $CJSData +=	"	        borderColor: 'rgba(0,0,0,1)'," + "`n"
        $CJSData +=	"	        backgroundColor: 'rgba(0,0,0,1)'," + "`n"
        $CJSData +=	"	        pointBorderWidth: 1," + "`n"
        $CJSData +=	"	        pointHoverRadius: 1," + "`n"
        $CJSData +=	"	        pointHitRadius: 2," + "`n"
        $CJSData += "			}]" + "`n"
    }
	$CJSData += "	},"	
	$ofs =""
	
	$CJSOptions = @()
	$cjsOptions += '	options: {'
	#responsive
	$cjsOptions += "		responsive: $($ChartObject.ChartStyle.responsive),"
	#legend
	$cjsOptions += "		legend: {
                position: '$($ChartObject.ChartStyle.legendposition)',
            },"
	#Title
	if ($ChartObject.Title -ne '') {
		$cjsOptions += "		title: {
				display: true,
				text: '$($ChartObject.Title)'
			},"
	}
    $cjsOptions += "
    		scales: {
			yAxes: [{
				ticks: {
					beginAtZero: true
				}
			}]
		},"
	$cjsOptions += "	},"
	#animation
	$cjsOptions += "	animation: {
                animateScale: $($ChartObject.ChartStyle.animateScale),
                animateRotate: $($ChartObject.ChartStyle.animateRotate)
            }"
	$CJSOptions += "});	"
	$CJSFooter = " </script>"
	
	$CJS  = @()
	$CJS += $CJSHeader
	$CJS += $CJSData
	$CJS += $CJSOptions 
	$CJS += $CJSFooter

	write-output $CJS
}

function Start-ClusterCapacityReportOld {
    param (
        $vROPUser = "svc.account",
        $vROPPass,
        $DevServiceAccount = "DevCORP\svc.account",
        $ProdServiceAccount = "DOMAIN\Username",
        $ServicePassword,
        [switch]$OnePage
    )

    #Import required modules
    if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) { . “D:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” }
    if ( !(Get-Module -Name ReportHTML -ErrorAction SilentlyContinue) ) { Import-Module "C:\Program Files (x86)\WindowsPowerShell\Modules\ReportHTML\1.3.0.7\ReportHTML.psm1" -ErrorAction SilentlyContinue }

    
    if(!$vROPPass) {
        $vROPPass = Get-SecureStringCredentials -Username $vROPUser -PlainPassword
    }

    if(!$ServicePassword) {
        $ServicePassword = Get-SecureStringCredentials -Username $DevServiceAccount -PlainPassword
    }

    #Dot source required functions
    #. $PSScriptRoot/vmware.ps1

    #Specific actions depending on ComputerName
    if($env:computername -eq "VMName") {
        #Connect to JAX Production and generate report
        Connect-VIServer -Server vcenter-1 -User $ProdServiceAccount -Password $ServicePassword
        Get-Cluster | Invoke-ClusterCapacityReport -vROPUser $vROPUser -vROPPass $vROPPass -OnePage:$OnePage
        Disconnect-VIServer -Server vcenter-1 -Confirm:$false

        #Connect to TPA Production and generate report
        Connect-VIServer -Server vcenter-2 -User $ProdServiceAccount -Password $ServicePassword
        Get-Cluster | Invoke-ClusterCapacityReport -vROPUser $vROPUser -vROPPass $vROPPass -OnePage:$OnePage
        Disconnect-VIServer -Server vcenter-2 -Confirm:$false
    } else {
        Get-Cluster | Invoke-ClusterCapacityReport -vROPUser $vROPUser -vROPPass $vROPPass -OnePage:$OnePage
    }
}

function Start-ClusterCapacityReport {
    [cmdletbinding()]
    param (
        $vROPUser = "svc.account",
        $vROPPass,
        $DevServiceAccount = "DevCORP\svc.account",
        $ProdServiceAccount = "DOMAIN\Username",
        $ServicePassword
    )

    #Import required modules
    if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) { . “D:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” }
    if ( !(Get-Module -Name ImportExcel -ErrorAction SilentlyContinue) ) { Import-Module "C:\Program Files (x86)\WindowsPowerShell\Modules\ImportExcel\ImportExcel.psm1" }
    if ( !(Get-Module -Name ReportHTML -ErrorAction SilentlyContinue) ) { Import-Module "C:\Program Files (x86)\WindowsPowerShell\Modules\ReportHTML\1.3.0.7\ReportHTML.psm1" }

    if(!$vROPPass) {
        $vROPPass = Get-SecureStringCredentials -Username $vROPUser -PlainPassword
    }

    if(!$ServicePassword) {
        $ServicePassword = Get-SecureStringCredentials -Username $DevServiceAccount -PlainPassword
    }

    #Specific actions depending on ComputerName
    if($env:computername -eq "VMName") {
        #Connect to vCenters
        Connect-VIServer -Server VMName -User $ProdServiceAccount -Password $ServicePassword
        Connect-VIServer -Server VMName -User $ProdServiceAccount -Password $ServicePassword
        
        #import Dev data
        $AllClusters = @()
        $AllVMHosts = @()
        $AllVMs = @()

        #If allclusters.csv exists from Dev run, then import
        if(Test-Path -Path "$PSScriptRoot\allclusters.csv") {
            write-host "Importing Dev Clusters"
            $AllClusters += (Import-Csv -Path "$PSScriptRoot\allclusters.csv")
        }

        #If allvmhosts.csv exists from Dev run, then import
        if(Test-Path -Path "$PSScriptRoot\allvmhosts.csv") {
            write-host "Importing Dev VMHosts"
            $AllVMHosts += (Import-Csv -Path "$PSScriptRoot\allvmhosts.csv")
        }

        #If allclusters.csv exists from Dev run, then import
        if(Test-Path -Path "$PSScriptRoot\allvms.csv") {
            write-host "Importing Dev VMs"
            $AllVMs += (Import-Csv -Path "$PSScriptRoot\allvms.csv")
        }

        #Get Clusters, VMHosts, and VMs from vCenter
        $NewClusters,$NewVMHosts,$NewVMs = Get-ClustersVMHostsVMs
        $AllClusters += $NewClusters
        $AllVMHosts += $NewVMHosts
        $AllVMs += $NewVMs
        
        #Connect to JAX Production and generate report
        Invoke-ClusterCapacityReport -Clusters $AllClusters -AllVMHosts $AllVMHosts -AllVMs $AllVMs -vROPUser $vROPUser -vROPPass $vROPPass
    } elseif($env:computername -eq "VMName") {
        #Connect to vCenter
        Connect-VIServer -Server VMName -User $DevServiceAccount -Password $ServicePassword

        #Get Clusters, VMHosts, and VMs from vCenter
        $AllClusters,$AllVMHosts,$AllVMs = Get-ClustersVMHostsVMs

        #Output to file for report generation on VMName
        $AllClusters | Export-Csv -NoTypeInformation -Path "$PSScriptRoot\allclusters.csv"
        $AllVMHosts | Export-Csv -NoTypeInformation -Path "$PSScriptRoot\allvmhosts.csv"
        $AllVMs | Export-Csv -NoTypeInformation -Path "$PSScriptRoot\allvms.csv"
    } else {
        $AllClusters,$AllVMHosts,$AllVMs = Get-ClustersVMHostsVMs
        Invoke-ClusterCapacityReport -Clusters $AllClusters -AllVMHosts $AllVMHosts -AllVMs $AllVMs -vROPUser $vROPUser -vROPPass $vROPPass
    }
}

function Start-ClusterCapacitySummary {
    [cmdletbinding()]
    param (
        $vROPUser = "svc.account",
        $vROPPass,
        $DevServiceAccount = "DevCORP\svc.account",
        $ProdServiceAccount = "DOMAIN\Username",
        $ServicePassword
    )

    #Import required modules
    if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) { . “D:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” }
    if ( !(Get-Module -Name ImportExcel -ErrorAction SilentlyContinue) ) { Import-Module "C:\Program Files (x86)\WindowsPowerShell\Modules\ImportExcel\ImportExcel.psm1" -ErrorAction SilentlyContinue; Import-Module ImportExcel -ErrorAction SilentlyContinue }
    
    if(!$vROPPass) {
        $vROPPass = Get-SecureStringCredentials -Username $vROPUser -PlainPassword
    }

    if(!$ServicePassword) {
        $ServicePassword = Get-SecureStringCredentials -Username $DevServiceAccount -PlainPassword
    }

    #Specific actions depending on ComputerName
    if($env:computername -eq "VMName") {
        #Connect to vCenters
        Connect-VIServer -Server VMName -User $ProdServiceAccount -Password $ServicePassword
        Connect-VIServer -Server VMName -User $ProdServiceAccount -Password $ServicePassword
        
        #import Dev data
        $AllClusters = @()
        $AllVMHosts = @()
        $AllVMs = @()

        #If allclusters.csv exists from Dev run, then import
        if(Test-Path -Path "$PSScriptRoot\allclusters.csv") {
            write-host "Importing Dev Clusters"
            $AllClusters += (Import-Csv -Path "$PSScriptRoot\allclusters.csv")
        }

        #If allvmhosts.csv exists from Dev run, then import
        if(Test-Path -Path "$PSScriptRoot\allvmhosts.csv") {
            write-host "Importing Dev VMHosts"
            $AllVMHosts += (Import-Csv -Path "$PSScriptRoot\allvmhosts.csv")
        }

        #If allclusters.csv exists from Dev run, then import
        if(Test-Path -Path "$PSScriptRoot\allvms.csv") {
            write-host "Importing Dev VMs"
            $AllVMs += (Import-Csv -Path "$PSScriptRoot\allvms.csv")
        }

        #Get Clusters, VMHosts, and VMs from vCenter
        $NewClusters,$NewVMHosts,$NewVMs = Get-ClustersVMHostsVMs
        $AllClusters += $NewClusters
        $AllVMHosts += $NewVMHosts
        $AllVMs += $NewVMs
        
        #Connect to JAX Production and generate summary
        Invoke-ClusterCapacitySummary -Clusters $AllClusters -AllVMHosts $AllVMHosts -AllVMs $AllVMs -vROPUser $vROPUser -vROPPass $vROPPass
    } elseif($env:computername -eq "VMName") {
        #Connect to vCenter
        Connect-VIServer -Server VMName -User $DevServiceAccount -Password $ServicePassword

        #Get Clusters, VMHosts, and VMs from vCenter
        $AllClusters,$AllVMHosts,$AllVMs = Get-ClustersVMHostsVMs

        #Output to file for report generation on VMName
        $AllClusters | Export-Csv -NoTypeInformation -Path "$PSScriptRoot\allclusters.csv"
        $AllVMHosts | Export-Csv -NoTypeInformation -Path "$PSScriptRoot\allvmhosts.csv"
        $AllVMs | Export-Csv -NoTypeInformation -Path "$PSScriptRoot\allvms.csv"
    } else {
        $AllClusters,$AllVMHosts,$AllVMs = Get-ClustersVMHostsVMs
        Invoke-ClusterCapacitySummary -Clusters $AllClusters -AllVMHosts $AllVMHosts -AllVMs $AllVMs -vROPUser $vROPUser -vROPPass $vROPPass
    }
}

function Get-ClustersVMHostsVMs {
    [cmdletbinding()]
    param (
    )

    Write-Host "Getting Clusters, VMHosts, and VMs from vCenter"
    $AllClusters = @(Get-Cluster | Select Name,UID)
    $AllVMHosts = @(Get-VMHost | Select Name,@{N='Cluster';E={$_.Parent.Name}},NumCPU,CPUTotalMhz,MemoryTotalGB)
    $AllVMs = @(Get-VM | Select Name,@{N='VMHostName';E={$_.VMHost.Name}},NumCPU,MemoryGB)

    return $AllClusters,$AllVMHosts,$AllVMs
}

function Invoke-ClusterCapacitySummary {
    #Steps
    #(2 steps: Get VMHosts & VMs from vCenter
    #11 steps: Do Math
    #4 steps: Excel formulas
    #4 steps Generate a report, download report, process report, delete report)
    #+
    #5 steps: Assemble XLSX report
    #4 steps: Conditional Formatting
    #30 steps per cluster + 9 steps
    [cmdletbinding()]
    param (
        [Object[]]$Clusters,
        [Object[]]$AllVMHosts,
        [Object[]]$AllVMs,
        $ConsolidationRatiosCSV = "$PSScriptRoot\ratios.csv",
        [string]$vROPServer = "VMName",
        [ValidateNotNullOrEmpty()][string]$vROPUser = "svc.account",
        [ValidateNotNullOrEmpty()][string]$vROPPass,
        $From = ((Get-Date).AddMonths(-1)),
        $To = (Get-Date),
        [string]$ReportPath = "\\path\to\file"
    )

    $results = @()

    #Consolidation Ratios Data
    $AllConsolidationRatios = Import-Csv $ConsolidationRatiosCSV

    #Create object to store the settings
    $settings = [pscustomobject][ordered]@{
        From = $From
        To = $To
        vROPServer = $vROPServer
        ConsolidationRatioCSV = $ConsolidationRatiosCSV
        GeneratedBy = "$env:UserDomain\$env:Username"
    }

    $timestamp = (Get-Date -Format yyyyMMdd_HHmmss)

    $global:vROPsServer = $vROPServer

    if(!$vROPPass) {
        $vROPPass = Get-SecureStringCredentials -Username $vROPUser -PlainPassword
    }

    Write-Host "Connecting to $vROPServer"
    $vrops = Connect-OMServer -Server $vROPServer -Username $vROPUser -Password $vROPPass
    $cpuUsageKey = Get-OMStatKey -Name "cpu|capacity_usagepct_average" -ResourceKind ClusterComputeResource

    #Get vROPs Token
    $token = Get-OMRestToken -username $vROPUser -password $vROPPass

    $rowID = 2
    foreach($cluster in ($clusters | Sort Name)) {
        $cname = $cluster.name

        Write-Host "[$cname] Getting VMHosts and VMs from vCenter results"
        $vmhosts = @($allvmhosts | ?{$_.Cluster -eq $cname})
        
        $vms = @()
        $vmhosts | %{
            $vmhostname =  $_.Name
            $vms += @($AllVMs | ?{$_.VMHostName -eq $vmhostname})
        }
        write-host "[$cname] $($vmhosts.count) VMHosts and $($vms.count) VMs"

        Write-Host "[$cname] Doing Math"

        #VMs and VMHosts
        $vmCount = ($vms | Measure-Object).count
        $vmHostCount = ($vmhosts | Measure-Object).Count

        #Total pCPU and pRAM
        $totalpCPU = [int]($vmhosts | Measure-Object -Property NumCPU -Sum).Sum
        $totalpRAM = [int]($vmhosts | Measure-Object -Property MemoryTotalGB -Sum).Sum

        #High Availability Buffer
        $haBufferPercent = (@($AllConsolidationRatios | ?{$_.Cluster -eq $cname}) | Select-Object -ExpandProperty "HA Buffer Percent")
        $haBufferCPU =  [int]($totalpCPU * ($haBufferPercent/100))
        $haBufferRAM =  [int]($totalpRAM * ($haBufferPercent/100))

        #Usable pCPU and pRAM
        $usablepCPU = $totalpCPU - $haBufferCPU
        $usablepRAM = $totalpRAM - $haBufferRAM

        #Target vCPU:pCPU and vRAM:pRAM Ratios
        $cpuRatioFull = [string](@($AllConsolidationRatios | ?{$_.Cluster -eq $cname}) | Select-Object -ExpandProperty "vCPU to pCPU Ratio")
        $cpuRatioMultiplier = [float]($cpuRatioFull.Substring(0,$cpuRatioFull.LastIndexOf(":")))
        $ramRatioFull = [string](@($AllConsolidationRatios | ?{$_.Cluster -eq $cname}) | Select-Object -ExpandProperty "vRAM to pRAM Ratio")
        $ramRatioMultiplier = [float]($ramRatioFull.Substring(0,$ramRatioFull.LastIndexOf(":")))

        #Usable vCPU and vRAM
        $usablevCPU = $usablepCPU * $cpuRatioMultiplier
        $usablevRAM = $usablepRAM * $ramRatioMultiplier

        #Allocated vCPU and vRAM
        $allocatedvCPU = [int]($vms | Measure-Object -Property NumCPU -Sum).Sum
        $allocatedvRAM = [int]($vms | Measure-Object -Property MemoryGB -Sum).Sum

        #AVailable vCPU and vRAM
        $availablevCPU = $usablevCPU - $allocatedvCPU
        $availablevRAM = $usablepRAM - $allocatedvRAM

        Write-Host "[$cname] Getting metrics from vROPs"
        $vrops_resource = Get-OMResource -Name $cname -ResourceKind ClusterComputeResource

        #CPU Usage %: 9AM to 5PM
        $cpuUsage9to5All = Get-OMStat9to5 -Resource $vrops_resource -Key $cpuUsageKey -From $From -To $To
        $cpuUsage9to5Min = [math]::Round(($cpuUsage9to5All | Measure-Object -Property Value -Minimum).Minimum,2)
        $cpuUsage9to5Max = [math]::Round(($cpuUsage9to5All | Measure-Object -Property Value -Maximum).Maximum,2)
        $cpuUsage9to5Avg = [math]::Round(($cpuUsage9to5All | Measure-Object -Property Value -Average).Average,2)

        #95th Percentile: Sort by the highest values, discard the highest 5%, next highest sample is 95th percentile
        $skipCount = $cpuUsage9to5All.Value.Count * 0.05 #Multiply sample count by 5% to determine number to skip
        $cpuUsage9to595th = $cpuUsage9to5All.Value | Sort-Object -Descending | Select -Skip $skipCount -First 1

        #CPU Usage %: 5PM to 9AM
        $cpuUsage5to9All = Get-OMStat5to9 -Resource $vrops_resource -Key $cpuUsageKey -From $From -To $To
        $cpuUsage5to9Min = [math]::Round(($cpuUsage5to9All | Measure-Object -Property Value -Minimum).Minimum,2)
        $cpuUsage5to9Max = [math]::Round(($cpuUsage5to9All | Measure-Object -Property Value -Maximum).Maximum,2)
        $cpuUsage5to9Avg = [math]::Round(($cpuUsage5to9All | Measure-Object -Property Value -Average).Average,2)

        #95th Percentile: Sort by the highest values, discard the highest 5%, next highest sample is 95th percentile
        $skipCount = $cpuUsage5to9All.Value.Count * 0.05 #Multiply sample count by 5% to determine number to skip
        $cpuUsage5to995th = $cpuUsage5to9All.Value | Sort-Object -Descending | Select -Skip $skipCount -First 1

        #CPU Contention on VMs
        #Create VM CPU Contention report through vROPs REST API
        $reportObj = Invoke-OMRestCreateReport -token $token -resourceID $vrops_resource.ID -reportDefinitionID "6c12d374-a34c-4da1-bcb7-d0c5f420e35b"

        #Wait for report generation
        do {
           $reportStatus = Get-OMRestReport -token $token -id $reportObj.id
           Write-Host "[$cname] $($reportStatus.Status) VM CPU Contention Report"
           Start-Sleep -Seconds 1
        } while ($reportStatus.Status -ne "COMPLETED")

        #Download VM CPU Contention report
        $cpuReportTemp = "C:\temp\$($cname)_CPU_$($timestamp).csv"
        Invoke-OMRestDownloadReport -token $token -id $reportObj.id | Out-File -FilePath $cpuReportTemp
        $vmCPUContention = Import-Csv -Path $cpuReportTemp | Sort-Object { [float]$_."Max CPU Contention" } -Descending | Select-Object @{N="Virtual Machine";E={$_.'ï»¿"Name"'}},`
                                                                 @{N="Cluster";E={$cname}},
                                                                 @{N="Max CPU Contention";E={[math]::Round(([float]$_."Max CPU Contention"),3)}},`
                                                                 @{N="Min CPU Contention";E={[math]::Round(([float]$_."Min CPU Contention"),3)}},`
                                                                 @{N="Avg CPU Contention";E={[math]::Round(([float]$_."Avg CPU Contention"),3)}}
        Remove-Item $cpuReportTemp

        #Top Max CPU Contention
        $maxVMCPUContention = $vmCPUContention | Select-Object -ExpandProperty "Max CPU Contention" | Sort-Object -Descending
        $cpuContentionTopMax = $maxVMCPUContention | Select-Object -First 1

        #95th Percentile: Sort by the highest values, discard the highest 5%, next highest sample is 95th percentile
        $skipCount = $maxVMCPUContention.Count * 0.05 #Multiply sample count by 5% to determine number to skip
        $cpuContention95thMax = $maxVMCPUContention | Sort-Object -Descending | Select-Object -Skip $skipCount -First 1

        #Top Avg CPU Contention
        $avgVMCPUContention = $vmCPUContention | Select-Object -ExpandProperty "Avg CPU Contention" | Sort-Object -Descending
        $cpuContentionTopAvg = $avgVMCPUContention | Select-Object -First 1

        #95th Percentile: Sort by the highest values, discard the highest 5%, next highest sample is 95th percentile
        $skipCountavg = $avgVMCPUContention.Count * 0.05 #Multiply sample count by 5% to determine number to skip
        $cpuContention95thAvg = $avgVMCPUContention | Sort-Object -Descending | Select-Object -Skip $skipCountavg -First 1

        #CPU Formulas
        #D: Total pCPU = vCenter Query
        #E: HA Buffer % = configured per cluster
        #F: Usable pCPU = Total pCPU - (Total pCPU * (HA Buffer %/100))
        $UsablepCPUFormula = "=(D$rowID-ROUNDUP(D$rowID*(E$rowID/100),0))"
        Write-Host "[$cname] Usable pCPU formula is $UsablepCPUFormula"

        #G: vCPU Multiplier = configured per cluster
        #H: Usable vCPU = Usable pCPU * vCPU Multiplier
        $UsablevCPUFormula = "=INT(F$rowID*G$rowID)"
        Write-Host "[$cname] Usable vCPU formula is $UsablevCPUFormula"

        #I: Allocated vCPU = vCenter Query
        #J: Available vCPU = Usable vCPU - Allocated vCPU
        $AvailablevCPUFormula = "=(H$rowID-I$rowID)"
        Write-Host "[$cname] Available vCPU formula is $AvailablevCPUFormula"

        #RAM Formulas
        #D: Total pCPU = vCenter Query
        #E: HA Buffer % = configured per cluster
        #F: Usable pCPU = Total pCPU - (Total pCPU * (HA Buffer %/100))
        $UsablepRAMFormula = "=(D$rowID-ROUNDUP(D$rowID*(E$rowID/100),0))"
        Write-Host "[$cname] Usable pRAM formula is $UsablepRAMFormula"

        #G: vCPU Multiplier = configured per cluster
        #H: Usable vCPU = Usable pCPU * vCPU Multiplier
        $UsablevRAMFormula = "=INT(F$rowID*G$rowID)"
        Write-Host "[$cname] Usable vRAM formula is $UsablevRAMFormula"

        #I: Allocated vCPU = vCenter Query
        #J: Available vCPU = Usable vCPU - Allocated vCPU
        $AvailablevRAMFormula = "=(H$rowID-I$rowID)"
        Write-Host "[$cname] Available vRAM formula is $AvailablevRAMFormula"

        $results += [pscustomobject][ordered]@{
            Cluster = $cname
            VMs = $vmCount
            VMHosts = $vmHostCount
            "Total pCPU" = $totalpCPU
            "Total pRAM" = $totalpRAM
            "HA Buffer %" = $haBufferPercent
            "Usable pCPU Old" = $usablepCPU
            "Usable pRAM Old" = $usablepRAM
            "Usable pCPU" = $UsablepCPUFormula
            "Usable pRAM" = $UsablepRAMFormula
            "Target vCPU:pCPU Ratio" = $cpuRatioFull
            "Target vRAM:pRAM Ratio" = $ramRatioFull
            "vCPU Multiplier" = $cpuRatioMultiplier
            "vRAM Multiplier" = $ramRatioMultiplier
            "Usable vCPU Old" = $usablevCPU
            "Usable vRAM Old" = $usablevRAM
            "Usable vCPU" = $UsablevCPUFormula
            "Usable vRAM" = $UsablevRAMFormula
            "Allocated vCPU" = $allocatedvCPU
            "Allocated vRAM" = $allocatedvRAM
            "Available vCPU Old" = $availablevCPU
            "Available vRAM Old" = $availablevRAM
            "Available vCPU" = $AvailablevCPUFormula
            "Available vRAM" = $AvailablevRAMFormula
            "Min" = $cpuUsage9to5Min
            "Max" = $cpuUsage9to5Max
            "Avg" = $cpuUsage9to5Avg
            "95th Percentile" = $cpuUsage9to595th
            "Min " = $cpuUsage5to9Min
            "Max " = $cpuUsage5to9Max
            "Avg " = $cpuUsage5to9Avg
            "95th Percentile " = $cpuUsage5to995th
            "Highest VM" = $cpuContentionTopMax
            "95th Percentile all VMs" = $cpuContention95thMax
            "Highest VM " = $cpuContentionTopAvg
            "95th Percentile all VMs " = $cpuContention95thAvg
        }
        $rowid++
     }

    $exportFilename = "$ReportPath\ClusterCapacitySummary_$timestamp.xlsx"

    $allocationRowId = $rowid - 1;
    Write-Host "allocationrowid is $allocationRowId"

    $results | Select-Object Cluster,VMs,VMHosts,"Total pCPU","HA Buffer %","Usable pCPU","vCPU Multiplier","Usable vCPU","Allocated vCPU","Available vCPU" | Export-Excel -Path $exportFilename -WorkSheetname "CPU Allocation" -TableName CPU -TableStyle Medium2 -AutoSize `
        -ConditionalText $(
            New-ConditionalText -ConditionalType LessThan 1  -ConditionalTextColor Red -BackgroundColor LightSalmon -Range "`$J`$2:`$J$allocationRowId"
            New-ConditionalText -ConditionalType GreaterThanOrEqual 1 -ConditionalTextColor Green -BackgroundColor LightGreen -Range "`$J`$2:`$J$allocationRowId")

    $results | Select-Object Cluster,VMs,VMHosts,"Total pRAM","HA Buffer %","Usable pRAM","vRAM Multiplier","Usable vRAM","Allocated vRAM","Available vRAM" | Export-Excel -Path $exportFilename -WorkSheetname "RAM Allocation" -TableName RAM -TableStyle Medium2 -AutoSize `
            -ConditionalText $(
            New-ConditionalText -ConditionalType LessThan 1  -ConditionalTextColor Red -BackgroundColor LightSalmon -Range "`$J`$2:`$J$allocationRowId"
            New-ConditionalText -ConditionalType GreaterThanOrEqual 1 -ConditionalTextColor Green -BackgroundColor LightGreen -Range "`$J`$2:`$J$allocationRowId")
    
    "CPU Usage % 9AM to 5PM" | Export-Excel -path $exportFilename -WorksheetName "CPU Usage" -StartRow 1 -StartColumn 2 -MergeRight 3 -MergePretty
    "CPU Usage % 5PM to 9AM" | Export-Excel -path $exportFilename -WorksheetName "CPU Usage" -StartRow 1 -StartColumn 6 -MergeRight 3 -MergePretty
    $results | Select-Object Cluster,"Min","Max","Avg","95th Percentile","Min ","Max ","Avg ","95th Percentile " | Export-Excel -Path $exportFilename -WorkSheetname "CPU Usage" -TableName CPUUsage -TableStyle Medium2 -AutoSize -StartRow 2 `
        -ConditionalText $(
            New-ConditionalText -ConditionalType LessThanOrEqual 33 -ConditionalTextColor Green -BackgroundColor LightGreen -Range "`$B`$3:`$I$rowID"
            New-ConditionalText -ConditionalType LessThan 70 -ConditionalTextColor DarkGoldenrod -BackgroundColor Yellow -Range "`$B`$3:`$I$rowID"
            New-ConditionalText -ConditionalType GreaterThanOrEqual 70 -ConditionalTextColor Red -BackgroundColor LightSalmon -Range "`$B`$3:`$I$rowID")

    "Max CPU Contention %" | Export-Excel -path $exportFilename -WorksheetName "CPU Contention" -StartRow 1 -StartColumn 2 -MergeRight 1 -MergePretty
    "Avg CPU Contention %" | Export-Excel -path $exportFilename -WorksheetName "CPU Contention" -StartRow 1 -StartColumn 4 -MergeRight 1 -MergePretty
    $results | Select-Object Cluster,"Highest VM","95th Percentile all VMs","Highest VM ","95th Percentile all VMs " | Export-Excel -Path $exportFilename -WorkSheetname "CPU Contention" -TableName CPUContention -TableStyle Medium2 -AutoSize -StartRow 2 `
        -ConditionalText $(
            New-ConditionalText -ConditionalType LessThanOrEqual 5 -ConditionalTextColor Green -BackgroundColor LightGreen -Range "`$B`$3:`$E$rowID"
            New-ConditionalText -ConditionalType LessThan 10 -ConditionalTextColor DarkGoldenrod -BackgroundColor Yellow -Range "`$B`$3:`$E$rowID"
            New-ConditionalText -ConditionalType GreaterThanOrEqual 10 -ConditionalTextColor Red -BackgroundColor LightSalmon -Range "`$B`$3:`$E$rowID")
    
    #Output report URI to results.prop for Jenkins Environmental Variable injection
    "ReportURI=$exportFilename" | Out-File "$PSScriptRoot\results.prop" -Encoding ascii
}

function Invoke-ClusterCapacityTrend {
    [cmdletbinding()]
    param (
        [string]$ReportPath = "\\path\to\file",
        $tabs = @("CPU Allocation","RAM Allocation"),
        $reportName = "ClusterCapacityTrend",
        $report = $true
    )

    $reports = Get-ChildItem "$ReportPath\ClusterCapacitySummary*.xlsx"

    $CPUAllocationData = @()
    $CPUUsageData = @()
    $CPUContentionData = @()
    foreach($_r in $reports) {
        $reportFilename = $_r.FullName
        Write-Host "Processing $reportFilename"
        $datetime = $reportFilename.substring(($reportFilename.indexof("_")+1)) -replace ".xlsx"
        $date = $datetime.substring(0,$datetime.indexof("_"))

        
        $CPUAllocation = Import-Excel $reportFilename -WorksheetName "CPU Allocation" | ?{$_."vCPU Multiplier"}
        foreach($line in $CPUAllocation) {
            
            $HABufferpCPU = [math]::Ceiling($line."Total pCPU" * ($line."HA Buffer %"/100))
            $UsablepCPU = $line."Total pCPU" - $HABufferpCPU
            $UsablevCPU = $UsablepCPU * $line."vCPU Multiplier"
            $AvailablevCPU = $UsablevCPU - $line."Allocated vCPU"

            #write-host "[$datetime] $($line.Cluster) has $($availablevcpu) vCPU available"

            $CPUAllocationData += [pscustomobject][ordered]@{
                DateTime = $datetime
                Cluster = $line.Cluster
                VMs = $line.VMs
                "Allocated vCPU" = $line."Allocated vCPU"
                "Available vCPU" = $AvailablevCPU
            }
        }

        $CPUUsage = Import-Excel $reportFilename -WorksheetName "CPU Usage" -NoHeader | ?{$_.P1 -ne $null -and $_.P1 -ne "Cluster"}
        foreach($line in $CPUUsage) {
            $CPUUsageData += [pscustomobject][ordered]@{
                DateTime = $datetime
                Cluster = $line.P1
                "9AM to 5PM - Max Usage" = $line.P3
                "9AM to 5PM - 95th Percentile" = $line.P5
                "5PM to 9AM - Max Usage" = $line.P7
                "5PM to 9AM - 95th Percentile" = $line.P9
            }
        }

        $CPUContention = Import-Excel $reportFilename -WorksheetName "CPU Contention" -NoHeader | ?{$_.P1 -ne $null -and $_.P1 -ne "Cluster"}
        foreach($line in $CPUContention) {
            $CPUContentionData += [pscustomobject][ordered]@{
                DateTime = $datetime
                Cluster = $line.P1
                "Highest CPU Contention - 1 VM" = $line.P2
                "Max CPU Contention - 95th Percentile" = $line.P3
                "Avg CPU Contention - 95th Percentile" = $line.P5
            }
        }
    }

    if($report -eq $true) {
        $timestamp = (Get-Date -Format yyyyMMdd_HHmmss)
        $exportFilename = "$ReportPath\ClusterCapacityTrend_$timestamp.xlsx"

        $CPUAllocationData | Export-Excel -Path $exportFilename -WorkSheetname "CPU Allocation" -TableName CPUAllocationTable -TableStyle Medium2 -AutoSize -IncludePivotTable -PivotRows DateTime -PivotColumns Cluster -PivotData @{"Allocated vCPU" = "sum";"Available vCPU" = "sum"} -IncludePivotChart:$true -ChartType LineMarkers -NoTotalsInPivot
        $CPUUsageData | Export-Excel -Path $exportFilename -WorkSheetname "CPU Usage Data" -TableName CPUUsageTable -TableStyle Medium2 -AutoSize -IncludePivotTable -PivotRows DateTime -PivotColumns Cluster -PivotData @{"9AM to 5PM - Max Usage" = "sum";"9AM to 5PM - 95th Percentile" = "sum";"5PM to 9AM - Max Usage" = "sum";"5PM to 9AM - 95th Percentile" = "sum"} -IncludePivotChart:$true -ChartType LineMarkers -NoTotalsInPivot
        $CPUContentionData | Export-Excel -Path $exportFilename -WorkSheetname "CPU Contention Data" -TableName CPUContentionTable -TableStyle Medium2 -AutoSize -IncludePivotTable -PivotRows DateTime -PivotColumns Cluster -PivotData @{"Highest CPU Contention - 1 VM" = "sum";"Max CPU Contention - 95th Percentile" = "sum";"Avg CPU Contention - 95th Percentile" = "sum"} -IncludePivotChart:$true -ChartType LineMarkers -NoTotalsInPivot

        Export-Results -results $results -exportName $reportName -excel
    }
}
