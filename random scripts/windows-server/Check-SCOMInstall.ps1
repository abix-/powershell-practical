$servers = @(import-csv("servers.csv"))

foreach($server in $servers)
{
    if((Test-Connection -ComputerName $server -count 1 -ErrorAction 0)) {
        $cstatus = "Connected"
        $exists = Test-RegKey -CN $server.name -Hive LocalMachine -Key "Software\Microsoft\Microsoft Operations Manager\3.0\Agent Management Groups\MyCompany"
        if($exists) {
            Write-Host "$($server.name) - Removing MyCompany key"
            Remove-RegKey -CN $server.name -Hive LocalMachine -Key "Software\Microsoft\Microsoft Operations Manager\3.0\Agent Management Groups\MyCompany" -R -F
            $status = "Removed"
        } else {
            Write-Host "$($server.name) - The MyCompany key does not exist on this server"
            $status = "Does not exist"
        }
        
    } else {
        Write-Host "$($server.name) - Failed to connect to remote registry"
        $cstatus = "Failed to connect"
        $status = "N/A"
        $fstatus = "N/A"
    }
    
    $objOutput = New-Object PSObject -Property @{
        Server = $server.name
        Connected = $cstatus
        MyCompany = $status
        MyCompanyCorp = $fstatus
    }
    
    $objreport+=@($objoutput)
}

$objreport | select Server, Connected, MyCompany, MyCompanyCorp | export-csv -notype report.csv
