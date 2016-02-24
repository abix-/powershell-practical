[CmdletBinding()]
param(

[Parameter(Position=0)]
[System.String]
$ComputerName = ‘.’,

[Parameter(Position=1)]
[System.String]
$Share,

[Parameter(Position=2)]
[System.String]
$OutputFile
)

function Translate-AccessMask($val){
Switch ($val)
{
2032127 {“FullControl”; break}
1179785 {“Read”; break}
1180063 {“Read, Write”; break}
1179817 {“ReadAndExecute”; break}
-1610612736 {“ReadAndExecuteExtended”; break}
1245631 {“ReadAndExecute, Modify, Write”; break}
1180095 {“ReadAndExecute, Write”; break}
268435456 {“FullControl (Sub Only)”; break}
default {$AccessMask = $val; break}
}
}

function Translate-AceType($val){
Switch ($val)
{
0 {“Allow”; break}
1 {“Deny”; break}
2 {“Audit”; break}
}
}

# Create calculated properties
$ShareProperty = @{n=”Share”;e={$ShareName}}
$AccessMask = @{n=”AccessMask”;e={Translate-AccessMask $_.AccessMask}}
$AceType = @{n=”AceType”;e={Translate-AceType $_.AceType}}
$Trustee = @{n=”Trustee”;e={$_.Trustee.Name}}

if ($Share){

$filter=”name=’$Share’”

$WMIQuery = Get-WmiObject -Class Win32_LogicalShareSecuritySetting -ComputerName $ComputerName -filter $filter | ForEach-Object {
$ShareName = $_.name
$_.GetSecurityDescriptor().Descriptor.DACL | Select-Object $Shareproperty,$AccessMask,$AceType,$Trustee}
}

else {
$WMIQuery = Get-WmiObject -Class Win32_LogicalShareSecuritySetting -ComputerName $ComputerName | ForEach-Object {
$ShareName = $_.name
$_.GetSecurityDescriptor().Descriptor.DACL | Select-Object $Shareproperty,$AccessMask,$AceType,$Trustee }
}

if ($OutputFile){
$WMIQuery | Export-Csv $OutputFile -NoTypeInformation
}

else {
$WMIQuery | Format-Table -AutoSize
}