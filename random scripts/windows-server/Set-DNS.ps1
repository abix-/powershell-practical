[CmdletBinding(SupportsShouldProcess=$false, ConfirmImpact='Medium')]
param (
    [Parameter(Position = 1,Mandatory = $true)]
    [alias("c")]
    $csv
)


function Set-DNS($computer,$nic,$newDNS) {
    $x = $nic.SetDNSServerSearchOrder($newDNS) 
    if($x.ReturnValue -eq 0) { Write-Host "$computer - Successfully changed DNS Servers" } 
    else { Write-Host "$computer - Failed to change DNS Servers" }
}
    
$servers = @(Import-Csv $csv)
foreach ($_s in $servers){
    $nics = $null
    $thisnic = $null
    Write-Progress -Status "Working on $($_s.ComputerName)" -Activity "Gathering Data"
    if((Test-Connection -ComputerName $_s.ComputerName -count 1 -ErrorAction 0)) {  
        $nics = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE -ComputerName $_s.ComputerName -ErrorAction Stop
        if($_s.'NIC Index' -and $_s.'Primary DNS') {
            $thisnic = $nics | ?{$_.Index -eq $_s.'NIC Index'}
                if($thisnic) {
                Write-Host "$($_s.ComputerName) - $($_s.'NIC Index') - Current DNS Servers: $($thisnic.DNSServerSearchOrder)"
                Write-Host "$($_s.ComputerName) - $($_s.'NIC Index') - Set DNS servers to: $($_s.'Primary DNS') $($_s.'Secondary DNS') $($_s.'Tertiary DNS')"
            
                if($($_s.'Primary DNS')) {
                    [array]$newdns = $($_s.'Primary DNS')
                    if($($_s.'Secondary DNS') -ne "N/A") { $newdns += $($_s.'Secondary DNS') }
                    if($($_s.'Tertiary DNS') -ne "N/A") { $newdns += $($_s.'Tertiary DNS') }
                } else { Write-Host "You must have a Primary DNS specified in the input CSV"; pause; continue }
           
                if($confirm -ne "A") { $confirm = Read-Host "$($_s.ComputerName) - Yes/No/All (Y/N/A)" }
                switch ($confirm) {
                    "Y" {Set-DNS $_s.ComputerName $thisnic $newdns}
                    "N" {}
                    "A" {Set-DNS $_s.ComputerName $thisnic $newdns}
                }
            } else { Write-Host "$($_s.ComputerName) - $($_s.'NIC Index') - NIC not found" }
        } else { Write-Host "The input CSV does not appear to be valid results from Get-DNS.ps1"; Exit }     
    } else { Write-Host "$($_s.ComputerName)  - Is offline" } 
}