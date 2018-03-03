Import-Module ActiveDirectory

function EmailResults($computername,$queuename,$messagecount) {
    $global:smtpserver = "smtp.domain.local"
    $msg = new-object Net.Mail.MailMessage
    $smtp = new-object Net.Mail.SmtpClient($global:smtpserver)
    $msg.From = "msmq_monitor@domain.local"
    $msg.To.Add("Notify-MSMQPurge@domain.local")
    $msg.subject = "$($computername): $queuename has been purged of $messagecount messages"
    $msg.body = "$($computername): $queuename has been purged of $messagecount messages."
    $msg.body += "`r`n`r`nThreshold: $threshold messages"
    $smtp.Send($msg)
}

$lockedaccounts = Search-ADAccount -LockedOut