[cmdletbinding()]
Param (
    $temppath = "C:\Windows\Temp",
    $pg_disk = 0,
    $data_disk = 0
)

New-Item –path "$temppath\listdisk.txt" –itemtype file –force | OUT-NULL
Add-Content –path "$temppath\listdisk.txt" “LIST DISK”
$LISTDISK=(DISKPART.exe /S "$temppath\LISTDISK.TXT")
$TOTALDISK=($LISTDISK.Count)-9

$LISTDISK

for ($d=0;$d -le $TOTALDISK;$d++) {
    $SIZE=$LISTDISK[-1-$d].substring(25,9).replace(" ","")
    $DISKID=$LISTDISK[-1-$d].substring(7,5).trim()
    if($SIZE -eq "5120MB" -or $SIZE -eq "5GB") {
        $pg_disk = $DISKID
    } elseif($SIZE -eq "10GB") {
        $data_disk = $DISKID
    }
}

if($pg_disk -ne 0) {
    Write-Host "Pagefile disk found on disk $pg_disk"
    $dp_script += @"
select disk $pg_disk
clean
convert gpt
create partition primary
format quick fs=ntfs label="Pagefile"
assign letter="P"
"@
}

if($data_disk -ne 0) {
    Write-Host "Data disk found on disk $data_disk"
    $dp_script += @"

select disk $data_disk
clean
convert gpt
create partition primary
format quick fs=ntfs label="Data"
assign letter="G"
"@
}

if($dp_script) {
    $dp_script | Out-File "$temppath\format-drives_script.txt" -Encoding ascii
    DISKPART.EXE /S "$temppath\format-drives_script.txt"
    Remove-Item "$temppath\format-drives_script.txt"
}

Remove-Item -Path "$temppath\listdisk.txt"