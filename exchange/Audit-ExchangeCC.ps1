[cmdletbinding()]
Param(
    $settingsfile = "audit-exchangecc-settings.csv",
    $exportfilename = "audit-exchangecc-results.csv",
    $knownccfilename = "audit-exchangecc-known.csv",
    $unknownccfilename = "audit-exchangecc-unknown.csv"
)

#$ewsprofile = New-MessageOps.EWSProfile -ExchangeVersion "Exchange2010_SP1" -Impersonation -Identity admin@domain.local
#$ewsprofile = New-MessageOps.EWSProfile -ExchangeVersion "Exchange2010_SP1" -UseDefaultCredentials $true -Identity admin@domain.local
#Search-MessageOps.CrawlMailFolder -identity "admin@domain.local" -ewsprofile $ewsprofile -folderpath "\\inbox\test" -creditcard $true

import-module MessageOps-Exchange

function Crawl-MailFolderCC($profile,$id,$fp) {
    try { $ccinfo = Search-MessageOps.CrawlMailFolder -identity $id -ewsprofile $profile -folderpath $fp -creditcard $true | select To,From,Subject,Received,CardType,CardNumberAsDetected }
    catch { Write-Host "Crawling failed for $id"; $id | Out-File pci-exchangecc-failures.txt -Append }
    if($ccinfo) {
        $ccinfo | %{Add-Member -inputobject $_ -MemberType NoteProperty -Name Identity -Force -Value "$id"}
        $ccinfo | %{Add-Member -inputobject $_ -MemberType NoteProperty -Name Folder -Force -Value "$fp"}

        $knowncc = @(import-csv $knownccfilename | Select Card,@{Name="Hits";Expression={[int32]$_.hits}})
        $unknowncc = @(import-csv $unknownccfilename | Select Card,@{Name="Hits";Expression={[int32]$_.hits}})
        foreach($cc in $ccinfo) {
            if($knowncc.card -contains $cc.CardNumberAsDetected) {
                Write-Host "Found known CC $($cc.cardnumberasdetected)"
                $knowncc[[array]::IndexOf($knowncc.card,$cc.CardNumberAsDetected)].hits++
                $ccinfo = $ccinfo | ?{$_.CardNumberAsDetected -ne $cc.CardNumberAsDetected}
            } else {
                $cchash = get-stringhash $cc.CardNumberAsDetected
                if($unknowncc.card -contains $cchash) { $unknowncc[[array]::IndexOf($unknowncc.card,$cchash)].hits++
                } else { $unknowncc += New-Object PSObject -Property @{Card="$cchash";Hits=1} }
            }
        }

        $knowncc | Export-Csv $knownccfilename -NoTypeInformation
        $unknowncc | Export-Csv $unknownccfilename -NoTypeInformation
        return $ccinfo | select To,From,Subject,Received,CardType,Identity,Folder
    } else { return }
}

function Get-StringHash([String] $String,$HashName = "MD5") { 
    $StringBuilder = New-Object System.Text.StringBuilder 
    [System.Security.Cryptography.HashAlgorithm]::Create($HashName).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String))|%{ [Void]$StringBuilder.Append($_.ToString("x2")) } 
    $StringBuilder.ToString() 
}

$cred = Get-Credential -Message "Enter password" -UserName "domain\svcAdmin"
$ewsprofile = New-MessageOps.EWSProfile -ExchangeVersion "Exchange2010_SP1" -Impersonation -Identity admin@domain.local -Credential $cred
$mailboxes = import-csv mailboxes.csv | select -Skip 1278

$folders = Import-Csv $settingsfile -ErrorAction Stop; $i = 0
$foldercount = import-csv $settingsfile | measure-object | select -expand count
foreach($m in $mailboxes) {
    $results = @(); $i++; $j = 0
    $identity = $m.primarysmtpaddress.tostring()
    Write-Host "Crawling $identity"
    while ($j -lt $foldercount) {
        if($mailboxes.count -gt 0) { Write-Progress -Activity "Crawling $identity [$i/$($mailboxes.count)]" -Status "Checking $($folders[$j].Folder)" -PercentComplete (($i/$mailboxes.count)*100) }
        Write-Host "Crawling $($folders[$j].Folder)"
        $results += Crawl-MailFolderCC $ewsprofile $identity $folders[$j].FolderPath; $j++
    }
    if($results.count -gt 0) { Write-Host "Found $($results.count) CC numbers"; $results | Export-Csv $exportfilename -NoTypeInformation -Append } else { Write-Host "No CC numbers found" }
}