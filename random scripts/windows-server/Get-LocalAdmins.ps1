# Get Local Administrators on dc01.domain.local
# ./Get-LocalAdmins -server dc01.domain.local
# Results will be output only the console
#
# Get Local Administrators for all servers in servers.txt
# ./Get-LocalAdmins -servers listofservers.txt
# Results will be output to the console and to localadminsreport.csv

[cmdletbinding()]
Param (
    [alias("s")]
    $server,
    $servers
)

function get-localadministrators($computername) {
    $computername = $computername.Trim()
    $fullcomputername = $computername.toupper()
    try { $computername = $computername.substring(0,$computername.IndexOf(".")).toupper() }
    catch { $computername = $computername.toupper() }
    
    if(Test-Connection -Cn $fullcomputername -BufferSize 16 -Count 1 -ea 0 -quiet) {
        try { $ADMINS = get-wmiobject -computername $fullcomputername -query "select * from win32_groupuser where GroupComponent=""Win32_Group.Domain='$computername',Name='administrators'""" -ErrorAction "STOP" | % {$_.partcomponent} }
        catch { 
            Write-Host "$fullcomputername - Failed to perform WMI query"
            $objOutput = New-Object PSObject -Property @{
                Machinename = $computername
                Fullname = "Failed to perform WMI query"
            }
            $objreport+=@($objoutput)
            return $objreport | sort-object DomainName
        }

        if ($admins) {
            Write-Host "$fullcomputername - Reading Administrators data"
            foreach ($ADMIN in $ADMINS) {
                        $admin = $admin.replace("\\$computername\root\cimv2:Win32_UserAccount.Domain=","") # trims the results for a user
                        $admin = $admin.replace("\\$computername\root\cimv2:Win32_Group.Domain=","") # trims the results for a group
                        $admin = $admin.replace('",Name="',"\")
                        $admin = $admin.REPLACE("""","")#strips the last "

                        $objOutput = New-Object PSObject -Property @{
                            Machinename = $computername
                            Fullname = ($admin)
                            DomainName  =$admin.split("\")[0]
                            UserName = $admin.split("\")[1]
                        }

            $objreport+=@($objoutput)
            }
            return $objreport | sort-object DomainName
        }
    } else {
        Write-Host "$fullcomputername - Failed to connect"
        $objOutput = New-Object PSObject -Property @{
            Machinename = $computername
            Fullname = "Failed to connect"
        }
        $objreport+=@($objoutput)
        return $objreport | sort-object DomainName
    }
}

if($server) {
    get-localadministrators $server
} elseif ($servers) {
    $serverlist = Get-Content $servers
    $allobjs = @()
    foreach($server in $serverlist) {
        $obj = get-localadministrators $server
        if($obj) {
            $allobjs += $obj
        }
    }
    $allobjs | select Machinename,Fullname,Domainname,Username
    $allobjs | select Machinename,Fullname,Domainname,Username | export-csv -notype localadminsreport.csv
}