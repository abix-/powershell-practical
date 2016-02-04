[cmdletbinding()]
param ()

function CheckAccountOnComputers() {
    $Computers = Import-CSV -Path "c:\scripts\adminservers.csv"
    $cred = Get-Credential
    foreach ($Computer in $Computers) {
    	$Computername	=	$Computer.Name.toupper()
    	$Isonline	=	"OFFLINE"
    	$PasswordValidationStatus		=	"FAILED"
    	Write-Verbose "Working on $Computername"
        
        if((Test-Connection -ComputerName $Computername -count 1 -ErrorAction 0)) {
    		$Isonline = "ONLINE"
    		Write-Verbose "`t$Computername is Online"
    	} else { Write-Verbose "`t$Computername is OFFLINE" }
        
        try {
            gwmi win32_computersystem -computer $computername -credential $cred
            $PasswordValidationStatus = "SUCCESS"
            
    	}
    	catch {
    		Write-Verbose "`tFailed to validate the password for $($computer.username). Error: $_"
    	}
        
        $obj = New-Object -TypeName PSObject -Property @{
     		ComputerName = $Computername
            Username = $cred.UserName
     		IsOnline = $Isonline
     		PasswordValid = $PasswordValidationStatus
    	}
        
        $obj | Select ComputerName, Username, IsOnline, PasswordValid
        
    }

}

CheckAccountOnComputers