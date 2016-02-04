[cmdletbinding()]
Param (
    $clusters = @("CLUSTER1","CLUSTER2")
)

if(($clusters.gettype()).basetype.name -ne "Array" -and $clusters.EndsWith(".txt")) { $clusters = gc $clusters }

Add-PSSnapin vmware.vimautomation.core
Connect-VIServer my-vcenter.domain.local | Out-Null

$clusters = Get-Cluster | Select -Expand Name | sort

function writeToClusterObj([string]$cluster,[string]$haenabled="N/A",[string]$hostmonitoring="N/A",[string]$admissioncontrol="N/A") {
    $obj= New-Object PSObject -Property @{
        Cluster = $cluster
        "HA Enabled" = $haenabled
        "Host Monitoring" = $hostmonitoring
        "Admission Control" = $admissioncontrol
    }
    return $obj
}

function writeToHostObj([string]$cluster,[string]$vmhost,[string]$alarmactions="N/A") {
    $obj= New-Object PSObject -Property @{
        Cluster = $cluster
        Host = $vmhost
        "Alarm Actions" = $alarmactions
    }
    return $obj
}

function EmailResults($clusterfail,$hostfail) {
    $global:smtpserver = "smtp.domain.local"
    $msg = new-object Net.Mail.MailMessage
    $smtp = new-object Net.Mail.SmtpClient($global:smtpserver)
    $msg.From = "vmware_monitor@domain.local"
    $msg.To.Add("admin@domain.local")
    $msg.subject = "Cluster Configuration Review"
    if($clusterfail) {
        $msg.body += "The following clusters are misconfigured`r`n"
        foreach($cluster in $clusterfail) {
            $msg.body += "Cluster: $($cluster.cluster)`r`n"
            $msg.body += "HA Enabled: $($cluster."HA Enabled")`r`n"
            $msg.body += "Host Monitoring: $($cluster."Host Monitoring")`r`n"
            $msg.body += "Admission Control: $($cluster."Admission Control")`r`n`r`n"
        }
    }

    if($hostfail) {
        $msg.body += "The following hosts do not have alarm actions enabled`r`n"
        foreach($vmhost in $hostfail) {
            $msg.body += "$($vmhost.host)`r`n"
        }
    }
    $smtp.Send($msg)
}

$allclusterobj = @()
$allhostobj = @()
foreach($cluster in $clusters) {
    $i++
    Write-Progress -Activity "Working on $cluster [$i/$($clusters.count)]" -Status "Reading configuration for cluster" -PercentComplete (($i/$clusters.count)*100)
    $m = Get-Cluster $cluster
    if($m) {
        if($m.ExtensionData.Configuration.DasConfig.HostMonitoring -eq "enabled") { $hostmonitoring = "True" } else { $hostmonitoring = "False" }
        $allclusterobj += writeToClusterObj $cluster $m.HAEnabled $hostmonitoring $m.HAAdmissionControlEnabled
        $vmhosts = Get-Cluster $cluster | Get-VMHost | Sort Name
        foreach($vmhost in $vmhosts) {
            Write-Progress -Activity "Working on $cluster [$i/$($clusters.count)]" -Status "Reading configuration for $($vmhost.name)" -PercentComplete (($i/$clusters.count)*100)
            $allhostobj += writeToHostObj $cluster $vmhost.Name $vmhost.ExtensionData.AlarmActionsEnabled
        }
    } else {
        $allclusterobj += writeToClusterObj $cluster "Failed to query" "Failed to query" "Failed to query"
    }
}

$clusterfail = $allclusterobj | ?{$_."HA Enabled" -eq "False" -or $_."Host Monitoring" -eq "False" -or $_."Admission Control" -eq "False"} | sort Cluster
$hostfail = $allhostobj | ?{$_."Alarm Actions" -eq "False"} | sort Host
if($clusterfail -or $hostfail) { EmailResults $clusterfail $hostfail }