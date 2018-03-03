$vmhosts = get-content hosts_ord.txt
foreach($vmhost in $vmhosts) {
    Write-Host "Working on $vmhost"
    Get-VMHost $vmhost | Get-VMHostService | Where {$_.Key –eq “TSM-SSH”} | Start-VMHostService
}