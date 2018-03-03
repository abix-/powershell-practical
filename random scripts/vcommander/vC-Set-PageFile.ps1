[cmdletbinding()]
Param (
	[Parameter(Position=1,ParameterSetName="SetPageFileSize")]
	[Alias('is')]
	[Int32]$InitialSize=4096,
	[Parameter(Position=2,ParameterSetName="SetPageFileSize")]
	[Alias('ms')]
	[Int32]$MaximumSize=4096,
	[Parameter(Position=3)]
	[Alias('dl')]
	[String]$DriveLetter="P",
    [Parameter(Position=0,ParameterSetName="SetPageFileSize")]
    [alias("cn")]
    $computername="localhost"
)

function writeToObj($computername,$status="N/A",$driveletter="N/A",$minsize="N/A",$maxsize="N/A") {
    $obj= New-Object PSObject -Property @{
        ComputerName = $computername
        Status = $status
        DriveLetter = $driveletter
        MinSize = $minsize
        MaxSize = $maxsize
    }
    return $obj
}

function SetPageFile($ComputerName,$DL,$InitialSize,$MaximumSize) {
    if(Test-Path \\$ComputerName\$DL$\ -ea "STOP") {
        $PageFile = Get-WmiObject -ComputerName $ComputerName -Class Win32_PageFileSetting
        Try	{
	        If($PageFile -ne $null) {
		        $PageFile.Delete()
	        }
		        Set-WmiInstance -ComputerName $ComputerName -Class Win32_PageFileSetting -Arguments @{name="$($DL):\pagefile.sys"; InitialSize = 0; MaximumSize = 0} `
		        -EnableAllPrivileges |Out-Null
			
		        $PageFile = Get-WmiObject -ComputerName $ComputerName -Class Win32_PageFileSetting -Filter "SettingID='pagefile.sys @ $($DL):'"
			
		        $PageFile.InitialSize = $InitialSize
		        $PageFile.MaximumSize = $MaximumSize
		        [Void]$PageFile.Put()
			
		        Write-Host  "$($computername): Created pagefile on $($DL): successfully. Size: $($InitialSize)MB to $($MaximumSize)MB."
                $results = writeToObj $computername "Success" $DL $InitialSize $MaximumSize
        }
        Catch {
            $results = writeToObj $computername "Permission Failure"
	        Write-Host "$($computername): No Permission - Failed to set page file size on ""$($DL):"""
        }
    } else {
        $results = writeToObj $computername "Drive does not exist"
        Write-Host "$($computername): The $($DL): drive was not found. No action taken."
    }
    return $results
}

foreach($computer in $computername) {
    $i++
    $results = SetPageFile $computer $driveletter $InitialSize $MaximumSize
    $results | select Computername,Status,DriveLetter,MinSize,MaxSize
}