cvi | Out-Null

#Define the amount of CPU shares to recommend per vCPU
$dev_shares = 1000
$qc_shares = 1500
$perf_shares = 2000

$pools = Get-Cluster CLUSTER | Get-ResourcePool | ?{$_.Name -like "DEV-*" -or $_.Name -like "QC-*"} | sort Name
foreach($pool in $pools) {
    $processors = $pool | Get-VM | Measure-Object -Sum -Property NumCpu
    if($pool.Name -like "DEV-*") { $recommended_shares = $processors.Sum * $dev_shares }
    if($pool.Name -like "QC-*") { $recommended_shares = $processors.Sum * $qc_shares }
    if($pool.NumCpuShares -ne $recommended_shares) {
        $confirm = Read-Host "$($pool): For $($processors.count) VMs with $($processors.Sum) processors, CPU shares of $recommended_shares are recommended. Current value is $($pool.NumCpuShares). Change now?"

        switch ($confirm) {
        "Y" { $pool | Set-ResourcePool -CpuSharesLevel Custom -NumCpuShares $recommended_shares | Out-Null }
        "N" { }
        }
    } else { Write-Host "$($pool): Already configured optimally with $($pool.numcpushares) shares" }
}