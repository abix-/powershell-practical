[cmdletbinding()]
Param (
    #[Parameter(Mandatory=$true)]$vcenter
)

#Get-Cluster $Cluster | Get-VMHost | Get-VDSwitch | Get-VDPortGroup | ?{$_.VlanConfiguration.VlanType -ne "Trunk"} | 
#Select Name,NumPorts,VDSwitch,@{N="Vlan";E={$_.VlanConfiguration.VlanId}} | Export-CSV $Export -UseCulture -NoTypeInformation


$datacenters = Get-Datacenter | sort Name
foreach($_d in $datacenters) {
    Write-Host "Working on $($_d.name)"
    $_d | Get-VDSwitch | sort Name | select Name,NumUplinkPorts | Export-Csv "$($_d.name)-DVS.csv" -UseCulture -NoTypeInformation
    $_d | Get-VDSwitch | Get-VDPortGroup | sort Name | ?{$_.VlanConfiguration.VlanType -ne "Trunk"} | Select Name,NumPorts,VDSwitch,@{N="Vlan";E={$_.VlanConfiguration.VlanId}} | Export-CSV "$($_d.name)-PortGroups.csv" -UseCulture -NoTypeInformation
}