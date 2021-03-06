[cmdletbinding()]
Param (
    [alias("s")]
    [Parameter(ParameterSetName='server')]
    $server,
    [alias("c")]
    [Parameter(ParameterSetName='csv')]
    $csv,
    [alias("u")]
    $user,
    [switch]$add,
    [switch]$remove,
    [alias("g")]
    [switch]$group
)

function Add-DomainGroupLocalAdmin($computer,$domain,$username) {
    Write-Host "$computer - Adding group $domain\$username to local Administrator group"
    $Group = [ADSI]"WinNT://$Computer/Administrators,group"
    $User = [ADSI]"WinNT://$Domain/$Username,group"
    $Group.Add($User.Path)
}

function Remove-DomainGroupLocalAdmin($computer,$domain,$username) {
    Write-Host "$computer - Removing group $domain\$username from local Administrator group"
    $Group = [ADSI]"WinNT://$Computer/Administrators,group"
    $User = [ADSI]"WinNT://$Domain/$Username,group"
    $Group.Remove($User.Path)
}

function Add-DomainUserLocalAdmin($computer,$domain,$username) {
    Write-Host "$computer - Adding user $domain\$username to local Administrator group"
    $Group = [ADSI]"WinNT://$Computer/Administrators,group"
    $User = [ADSI]"WinNT://$Domain/$Username,user"
    $Group.Add($User.Path)
}

function Remove-DomainUserLocalAdmin($computer,$domain,$username) {
    Write-Host "$computer - Removing user $domain\$username from local Administrator group"
    $Group = [ADSI]"WinNT://$Computer/Administrators,group"
    $User = [ADSI]"WinNT://$Domain/$Username,user"
    $Group.Remove($User.Path)
}

function GetCSV($csvfile) {
   if(!(Test-Path $csvfile)) { 
        Write-Verbose "$($csvfile) does not exist. Try again."
   }
   elseif(!($csvfile.substring($csvfile.LastIndexOf(".")+1) -eq "csv")) {
        Write-Verbose "$($csvfile) is not a CSV. Try again."
   }
   else {
			$csv = @(Import-Csv $csvfile)
        if(!$csv) {
            Write-Verbose "The CSV is empty. Try again."
        }
        else {
            $csvvalid = $true
            return $csv
        }
    }
}

if($server) {
    $username = $user.substring($user.IndexOf("\")+1)
    try { $domain = $user.substring(0,$user.IndexOf("\")) }
    catch { Write-Host "Local accounts are not supported" }
    
    if($domain) {
        if($add) {
            if(!$group) {
                Add-DomainUserLocalAdmin $server $domain $username
            } else {
                Add-DomainGroupLocalAdmin $server $domain $username
            }
        } elseif($remove) {
            if(!$group) {
                Remove-DomainUserLocalAdmin $server $domain $username
            } else {
                Remove-DomainGroupLocalAdmin $server $domain $username
            }
        } else {
            Write-Host "You must add a -add or -remove switch"
        }
    }   
} elseif($csv) {
    $servers = @(GetCSV $csv)
    foreach($server in $servers) {
        if(!$user) {
            $username = $server.user.substring($server.user.IndexOf("\")+1)
            try { $domain = $server.user.substring(0,$server.user.IndexOf("\")) }
            catch { Write-Host "Local accounts are not supported" }
        } else {
            $username = $user.substring($user.IndexOf("\")+1)
            try { $domain = $user.substring(0,$user.IndexOf("\")) }
            catch { Write-Host "Local accounts are not supported" }
        }
        if($domain) {
            if($add) {
                if(!$group) {
                    Add-DomainUserLocalAdmin $server.Name $domain $username
                } else {
                    Add-DomainGroupLocalAdmin $server.Name $domain $username
                }
            } elseif($remove) {
                if(!$group) {
                    Remove-DomainUserLocalAdmin $server.Name $domain $username
                } else {
                    Remove-DomainGroupLocalAdmin $server.Name $domain $username
                }
            } else {
                Write-Host "You must add a -add or -remove switch"
            }
        }
    }
}