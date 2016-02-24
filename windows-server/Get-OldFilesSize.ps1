[cmdletbinding()]
Param (
    $scandir="c:\windows"
)

Write-Host "Finding files in $scandir that have not been modified recently."

$allfiles = get-childitem "$scandir" -recurse | where-object {$_.mode -notmatch "d"} | select fullname,lastwritetime,length

$days = "60","90","180","365","547","730","912","1095"
foreach($day in $days) {
    $dayfiles = $allfiles | where-object {$_.lastwritetime -lt (get-date).AddDays(-$day)}
    $sizeb = $dayfiles | Measure-Object -Property Length -Sum
    $sizegb = $sizeb.sum/1gb
    $nicesizegb = "{0:N2}" -f $sizegb

    Write-Host "There are $($dayfiles.count) files that have not been modified in $day days using $nicesizegb GB."
}