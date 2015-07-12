#If the number of messages in a queue are above this value, the queue will be purged.
$threshold = 500000

#Logging configuration
$path = "G:\Jobs"
$logname = "msmq_monitor.log"
$rotation_threshold_mb = 10

function EmailResults($computername,$queuename,$messagecount) {
    $global:smtpserver = "smtpserver.domain.local"
    $msg = new-object Net.Mail.MailMessage
    $smtp = new-object Net.Mail.SmtpClient($global:smtpserver)
    $msg.From = "msmq_monitor@domain.local"
    $msg.To.Add("Notify-MSMQPurge@domain.com")
    $msg.subject = "$($computername): $queuename has been purged of $messagecount messages"
    $msg.body = "$($computername): $queuename has been purged of $messagecount messages."
    $msg.body += "`r`n`r`nThreshold: $threshold messages"
    $smtp.Send($msg)
}

function LogToFile($message) {
    $date = Get-Date -f yyy-MM-dd
    $time = Get-Date -f HH:mm:ss

    if(Test-Path "$path\$logname") {
        $filesize = (Get-Item "$path\$logname").length/1MB
        if ($filesize -gt $rotation_threshold_mb) {
            Remove-Item "$path\$logname"
            Write-Host "The log reached a maximum size of $rotation_threshold_mb MB and was purged."
            "$date $time - The log reached a maximum size of $rotation_threshold_mb MB and was purged." | Out-File "$path\$logname" -append
        }
    }

    Write-Host $message
    "$date $time - $message" | Out-File "$path\$logname"-append
}

[reflection.assembly]::loadwithpartialname("system.messaging") | out-null
$pqs = [system.messaging.messagequeue]::getprivatequeuesbymachine(".")
$wmiqueues = gwmi -class Win32_PerfRawData_MSMQ_MSMQQueue | Select Name,MessagesInQueue
Write-Host "The queue purge threshold is $threshold."
foreach($pq in $pqs) {
   $fullqueuename = $pq.formatName.substring(10)
   $messagecount = ($wmiqueues | ?{$_.Name -like "$fullqueuename"}).MessagesInQueue
   if($messagecount -gt $threshold) {
      LogToFile "$($pq.QueueName) has $messagecount messages. This is above the threshold of $threshold messages. Purging queue."
      $computername = "$env:computername.$env:userdnsdomain"
      EmailResults $computername $pq.QueueName $messagecount
      $pq.Purge()
   } else {
      LogToFile "$($pq.QueueName) has $messagecount messages. This is below the threshold of $threshold messages. No action taken."
   }
}