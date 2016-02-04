Add-PSSnapin VMware.VimAutomation.Core

$vcenter = "my-vcenter.domain.local"
$threshold = -3
$absthreshold = [math]::Abs($threshold)

Connect-VIServer $vcenter | Out-Null

$snaps = Get-VM | get-snapshot | select VM,Name,SizeMB,Created | sort VM | ?{$_.VM -notlike "*VDI-SOURCE*" -and $_.VM -notlike "replica*" -and $_.Created -lt ((get-date).adddays($threshold))}
$consolidations = Get-VM | sort VM | ?{$_.Extensiondata.Runtime.ConsolidationNeeded -and $_.VM -notlike "*VDI-SOURCE*" -and $_.VM -notlike "replica*"}

if($snaps -or $consolidations) {
    $global:smtpserver = "smtp-wh.domain.local"
    $msg = new-object Net.Mail.MailMessage
    $smtp = new-object Net.Mail.SmtpClient($global:smtpserver)
    $msg.From = "vmware_monitor@domain.local"
    $msg.To.Add("Notify-VMSnapshots@domain.local")   
    $msg.subject = "$($vcenter):"
}

if($snaps) {
    if($snaps.count -gt 1) {
        $snapscount = $snaps.count
    } else { $snapscount = 1 } 
    Write-Host "$snapscount old snapshots have been found."
    $msg.subject += " $snapscount old snapshots have been found."
    $msg.body = "The following VMS have snapshots that are older than $absthreshold days:`r`n`r`n"
    foreach($snap in $snaps) {
        $prettysnapmb = "{0:N2}" -f $snap.SizeMB
        $msg.body += "VM: $($snap.VM)`r`n"
        $msg.body += "Description: $($snap.Name)`r`n"
        $msg.body += "Size: $prettysnapmb MB`r`n"
        $msg.body += "Created: $($snap.Created)`r`n"
        $msg.body += "`r`n"
    }
} else { Write-Host "No snapshots older than $absthreshold days found" }

if($consolidations) {
    if($consolidations.count -gt 1) {
        $consolcount = $consolidations.count
    } else { $consolcount = 1 } 
    Write-Host "$consolcount VMs are requesting consolidation."
    $msg.subject += " $consolcount VMs are requesting consolidation."
    if($snaps) { $msg.body += "`r`n" }
    $msg.body += "The following VMS are requesting consolidation:`r`n`r`n"
    foreach($consolidation in $consolidations) {
        $msg.body += "VM: $($consolidation.Name)`r`n"
        $msg.body += "PowerState: $($consolidation.PowerState)`r`n"
        $msg.body += "`r`n"
    }
} else { Write-Host "No VMS are currently requesting consolidation" }

if($snaps -or $consolidations) {
    $smtp.Send($msg)
}