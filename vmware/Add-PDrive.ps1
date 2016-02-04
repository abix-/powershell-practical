[cmdletbinding()]
Param (
    [alias("cn")]
    $computername="localhost"
)

Connect-VIServer my-vcenter.domain.local | Out-Null

foreach($computer in $computername) {
    $vm = $null
    try { $vm = get-vm $computer -ea "STOP"}
    catch { Write-Host "$($computer): No VM found" }
    if($vm) {
        $pdrive = $vm | get-HardDisk | where{$_.capacitykb -eq 5242880}
        if(!$pdrive) {
            New-HardDisk -vm $vm -capacitykb 5242880
        } else {
            Write-Host "$($computer): There is already a 5GB disk on this VM."
        }
    }
}