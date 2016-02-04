#$servers = @("test","test2","test3")
#Add-Member -InputObject $global:servers[0] -NotePropertyName Test1 -NotePropertyValue 2
#$global:servers[0] | gm
#$global:servers[0].test1
#$global:servers

function testFunction($var) {
    $var.test = "WINNER"
}


$global:data = @()
foreach($server in $servers) {
    Write-Host "index is $index"
    $global:data += New-Object PSObject -Property @{
        Server = $server
        Test = "WIN"
    }
}

foreach($d in $global:data) {
    testFunction $d
}

$global:data