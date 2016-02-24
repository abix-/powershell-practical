[cmdletbinding()]
Param (
    $source,
    $destination,
    $zip
)

$date = Get-Date -format yyyy-MM-dd
if(Test-Path $source) {

} else { Write-Host "$source does not exist" }

#7zip the source to the destination
#delete the original contents

function Stolen {
    if(Test-Path \\fileserver\g$\path\$service) {
        if($nohistory) { $switches += "-xr!history" }
        if($nooutboundbatfiles) { 
            if($switches) {
                $switches += " -xr!outboundbatfiles"
            } else {
                $switches += "-xr!outboundbatfiles"
            }
        }
        #$switches
        & "C:\Program Files\7-Zip\7z.exe" a -tzip \\fileserver\g$\path\$date\$service.zip \\fileserver\g$\path\$service -mx9 $switches
    } else {
        Write-Host "There is no folder named at \\fileserver\g$\path\$service"
    }
}