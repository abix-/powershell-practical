$status = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint")
$site = New-Object Microsoft.SharePoint.SPSite("http://intranet")
$webs = $site.AllWebs

foreach($web in $webs) {
    $lists = $web.Lists
    foreach($list in $lists) {
        if($list.HasUniqueRoleAssignments) {
            Write-Host "http://intranet$($list.DefaultViewUrl)"
        }
    }
}