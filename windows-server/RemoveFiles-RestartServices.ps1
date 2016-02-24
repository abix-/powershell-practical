$servers = @("SRV1","SRV2")
$path = "g$\test"
$service = "Windows Time"

function GetNewestFile($server,$path) {
    try { $newest_file = (GCI \\$server\$path -ErrorAction "STOP" | sort LastWriteTime -Descending)[0] }
    catch { Write-Host "$($server): Failed to determine the newest file"; Write-Host ""; $newest_file = "Failed" }
    return $newest_file
}

foreach($server in $servers) {
    $newest_file = GetNewestFile $server $path
    if($newest_file -ne "Failed") {
        $filesize = [math]::truncate($newest_file.Length/1mb)
        Write-Host "Server: $server"
        Write-Host "Filename: $($newest_file.FullName)"
        Write-Host "Filesize: $filesize MB"
        Write-Host "Date modified: $($newest_file.LastWriteTime)"
        $confirm = Read-Host "Do you want to delete this file? (Y/N)"
        switch ($confirm) { "Y" { Remove-Item \\$server\$path\$newest_file; Write-Host "File Deleted"; Write-Host ""} }
    }
}

foreach($server in $servers) {
    Write-Host "$($server): Restarting $service service"
    Restart-Service -InputObject $(Get-Sevice -ComputerName $server -Name $service); 
}