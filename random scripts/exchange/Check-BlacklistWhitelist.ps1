[cmdletbinding()]
Param (
    $inboxes = @{"blacklist@domain.local"="blacklist.cf";"whitelist@domain.local"="whitelist.cf"},
    $usernames = ("blacklist","whitelist"),
    $password = "REMOVED",
    $domain   = "domain.local",
    $scriptpath = "G:\jobs\",
    $listpath = "G:\jobs"
)

function connectMailbox($username) {
    Write-Host "Connecting to $username@domain.local"
    [void] [Reflection.Assembly]::LoadFile("G:\Jobs\Microsoft.Exchange.WebServices.dll")
    try { $s = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService([Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2010) }
    catch { $s = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService([Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2007_SP1) }
    $s.Credentials = New-Object Net.NetworkCredential($username, $password, 'domain.local')
    #$s.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    #$s.UseDefaultCredentials = $true
    $s.AutodiscoverUrl("$username@domain.local")
    $inbox = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($s,[Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox)
    return $inbox
}

 function writeToObj($address,$from,$datetime,$subject) { 
    $obj= New-Object PSObject -Property @{ 
        Address = $address
        From = $from 
        DateTime = $datetime
        Subject = $subject
    } 
    return $obj 
} 

function findAddresses($allemails,$username) {
    Write-Host "Finding addresses"
    $alladdresses = @()
    $psPropertySet = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
    $psPropertySet.RequestedBodyType = [Microsoft.Exchange.WebServices.Data.BodyType]::Text
    $allobj = @()
    foreach($email in $allemails) {
        $email.load($psPropertySet)
        $ataddresses = (Select-String -InputObject $email.body.text -Pattern "@$username=(\w+@\w+.\w+)" -AllMatches).matches.groups.value | ?{$_ -notlike "@$username=*"}
        if($ataddresses) { foreach($address in $ataddresses) { $allobj += writeToObj $address.ToLower() $email.Sender $email.DateTimeReceived $email.subject } }
        if(!$ataddresses) {
            $addresses1 = (Select-String -InputObject $email.body.text -Pattern "From: (\w+@\w+.\w+)" -AllMatches).matches.groups.value | ?{$_ -notlike "From:*"}
            $addresses2 = (Select-String -InputObject $email.body.text -Pattern "mailto:(\w+@\w+.\w+)" -AllMatches).matches.groups.value | ?{$_ -notlike "mailto:*"}
            if($addresses1) { foreach($address in $addresses1) { $allobj += writeToObj $address.ToLower() $email.Sender $email.DateTimeReceived $email.subject } }
            if($addresses2) { foreach($address in $addresses2) { $allobj += writeToObj $address.ToLower() $email.Sender $email.DateTimeReceived $email.subject } }
        }
        $email.Delete([Microsoft.Exchange.WebServices.Data.DeleteMode]::HardDelete)
    }
    $allobj = $allobj | ?{$_.address -notlike "*@domain.local" -and $_.address -notlike "*@domain.local" -and $_.address -notlike "*@domain.local" -and $_.address -notlike "*@domain.local"} | Sort-Object -Property Address -Unique
    return $allobj
}

function EmailResults($addresses,$username) {
    $global:smtpserver = "smtp.domain.local"
    $msg = new-object Net.Mail.MailMessage
    $smtp = new-object Net.Mail.SmtpClient($global:smtpserver)
    $msg.From = "exchange_monitor@domain.local"
    $msg.To.Add("admin@domain.local")
    $msg.subject = "Exchange $username@domain.local monitor"
    $msg.body += "The following addresses have been added to $username.cf`r`n`r`n"
    foreach($address in $addresses) {
        $msg.body += "Address: $($address.address)`r`n"
        $msg.body += "From: $($address.from)`r`n"
        $msg.body += "DateTime: $($address.datetime)`r`n"
        $msg.body += "Subject: $($address.subject)`r`n`r`n"
    }
    $smtp.Send($msg)
}

function recordAddresses($addresses,$username) {
    $list = @()
    $newaddresses = @()
    if($username -eq "blacklist") { $oldlist = Get-Content $listpath\blacklist.cf; $otherlist = Get-Content $listpath\whitelist.cf }
    if($username -eq "whitelist") { $oldlist = Get-Content $listpath\whitelist.cf; $otherlist = Get-Content $listpath\blacklist.cf }
    foreach($address in $addresses) {
        if(!($oldlist -match $address.address)) { 
            $list += "$($username)_from $($address.address)"
            $newaddresses += writeToObj $address.address $address.from $address.datetime $address.subject
        }
        if($otherlist -match $address.address) {
            if($username -eq "blacklist") { $otherlist -notmatch $address.address | Out-File $listpath\whitelist.cf; $otherlist = Get-Content $listpath\whitelist.cf }
            if($username -eq "whitelist") { $otherlist -notmatch $address.address | Out-File $listpath\blacklist.cf; $otherlist = Get-Content $listpath\blacklist.cf }
        }
    }
    $list | Out-File "listpath\$($username).cf" -Append
    $addresses | select Address,From,DateTime,Subject | Export-Csv -NoTypeInformation "$scriptpath\$($username)_log.csv"
    Write-Host "Added $($list.count) addresses to $($username).cf"
    return $newaddresses
}

foreach($username in $usernames) {
    $inbox = $null
    $inbox = connectMailbox $username
    if($inbox -eq $null) { continue }
    try { $allemails = $inbox.FindItems($inbox.totalcount) }
    catch { Write-Host "No items in inbox"; continue }
    $addresses = findAddresses $allemails $username
    if($addresses) { 
        $addresses = recordAddresses $addresses $username
        if($addresses) { emailResults $addresses $username }
    }
}