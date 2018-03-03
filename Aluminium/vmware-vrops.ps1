function Get-OMRestHeader {
    <#
    .SYNOPSIS
    Creates a request header for calls to the vROPS REST API
    #>
    param (
        [string]$ContentType,
        [string]$token,
        [switch]$AcceptJson = $true
    )
    #Create object to store headers
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    #Json Content-Type will be sent from Client to Server
    $headers.Add(‘Content-Type’, ‘application/json;charset=utf-8’)
    #Json will be accepted from Server to Client
    if($AcceptJson) { $headers.Add('Accept', 'application/json') }
    #Add Authorization token
    if($token) { $headers.Add("Authorization", "vRealizeOpsToken $token") }
    return $headers
}

function Get-OMRestToken {
    <#
    .SYNOPSIS 
    Gets a vROPS Authentication token. Token is used in other functions for authentication with the vROPS REST API.
    #>
    param (
        [string]$api = "suite-api/api/auth/token/acquire",
        [string]$username,
        [string]$password
    )

    $headers = Get-OMRestHeader

    $body = @{
        username = $username
        password = $password
    } | ConvertTo-Json

    Write-Host "Getting vROPs Authentication token"
    try { $token = Invoke-RestMethod -Method:POST -Uri "https://$global:vROPsServer/$api" -Body $body -Headers $headers -ErrorAction Stop
        return $token.token
    }
    catch { 
        Write-Host $_.Exception.Message -ForegroundColor Red
        Return
    }
}

function Get-OMRestResource {
    <#
    .SYNOPSIS
    Gets a list of all vROPS resources through the vROPS REST API
    #>
    param (
        [string]$api = "suite-api/api/resources?pageSize=10000",
        [string]$Name,
        [string]$ResourceKind,
        [string][Parameter(Mandatory=$true)]$Token
    )

    if($ResourceKind) { $api += "&resourceKind=$resourceKind" }
    $headers = Get-OMRestHeader -token $Token
    $response = Invoke-RestMethod -Method:GET -Uri "https://$global:vROPsServer/$api" -Headers $headers | Select-Object -ExpandProperty resourceList | Select-Object identifier,@{n="name";e={$_.resourcekey.name}}
    if($Name) {
        $response | ?{$_.name -eq $Name}
    }  else {
        $response
    }
}

function Get-OMRestReportDefinition {
    <#
    .SYNOPSIS
    Gets a list of all vROPS Reports through the vROPS REST API
    #>
    param (
        [string]$api = "suite-api/api/reportdefinitions?pageSize=10000",
        [string][Parameter(Mandatory=$true)]$token
    )

    $headers = Get-OMRestHeader -token $token
    Invoke-RestMethod -Method:GET -Uri "https://$global:vROPsServer/$api" -Headers $headers
    
}

function Invoke-OMRestCreateReport {
    <#
    .SNYOPSIS
    Generates a report for a vROPS Resource through the vROPS REST API
    #>
    param (
        [string]$api = "suite-api/api/reports",
        [string][Parameter(Mandatory=$true)]$resourceID,
        [string][Parameter(Mandatory=$true)]$reportDefinitionID,
        [string][Parameter(Mandatory=$true)]$token
    )

    $headers = Get-OMRestHeader -token $token

    $travSpec = @{
        name = "vSphere Hosts and Clusters"
        rootAdapterKindKey = "VMWARE"
        rootResourceKindKey = "vSphere World"
    }

    $body = @{
        resourceId = $resourceID
        reportDefinitionId = $reportDefinitionID
        traversalSpec = $travSpec
    } | ConvertTo-Json

    Invoke-RestMethod -Method:POST -Uri "https://$global:vROPsServer/$api" -Headers $headers -Body $body
}

function Get-OMRestReport {
    <#
    .SYNOPSIS
    Gets the state of a vROPS Report through the vROPS REST API
    #>
    param (
        [string]$api = "suite-api/api/reports",
        [string][Parameter(Mandatory=$true)]$id,
        [string]$token
    )

    $headers = Get-OMRestHeader -token $token
    $api += "/$id"
    Invoke-RestMethod -Method:GET -Uri "https://$global:vROPsServer/$api" -Headers $headers
}

function Invoke-OMRestDownloadReport {
    <#
    .SYNOPSIS
    Download a generated vROPS Report through the vROPS REST API
    #>
    param (
        [string]$api = "suite-api/api/reports",
        [string][Parameter(Mandatory=$true)]$id,
        [string]$format = "CSV",
        [string]$token,
        [string]$OutFile
    )

    $headers = Get-OMRestHeader -token $token -AcceptJson:$false
    $api += "/$id/download"
    if($format) { $api += "?format=CSV" }

    if($Outfile) {
        Invoke-RestMethod -Method:GET -Uri "https://$global:vROPsServer/$api" -Headers $headers -OutFile $OutFile
    } else {
        Invoke-RestMethod -Method:GET -Uri "https://$global:vROPsServer/$api" -Headers $headers
    }
}

function Get-OMRestStat {
    <#
    .SYNOPSIS
    Gets Statistics for a vROPS Resource using the vROPs REST API. Not finished

    .NOTES
    http://winplat.net/2015/12/14/powershell-convert-date-and-time-to-unix-or-epoch-format/
    http://winplat.net/2015/12/14/powershell-convert-unix-or-epoch-time-to-readable-format/
    https://github.com/PowerShell/PowerShell/issues/2195
    #>
    param (
        $ResourceID,
        $StatKey,
        $From = ((Get-Date).AddMonths(-1)),
        $To,
        $RollUpType,
        $IntervalType,
        $IntervalCount,
        $api = "suite-api/api/resources"
    )

    $headers = Get-OMRestHeader -token $token

    $api += "$id/stats?resourceId=$ResourceID&statKey=$StatKey"

    if($RollUpType) { $api += "&rollUpType=$RollUpType" }
    if($IntervalType) { $api += "&intervalType=$IntervalType" }
    if($IntervalCount) { $api += "&intervalQuantifier=$IntervalCount" }
    if($From) {
        Write-Host "hi"
        $fromUnix = [int][double]::Parse((get-date ($From).toUniversalTime() -UFormat +%s))
        $api += "&begin=$fromUnix" 
    }

    $api

    $response = Invoke-RestMethod -Method:GET -Uri "https://$global:vROPsServer/$api" -Headers $headers #-Body $body

    Write-Output $response.values."stat-list".stat
}

function Get-OMStat9to5 {
    <#
    .SYNOPSIS
    Gets stats from vROPs fro a resource during business hours (9am to 5pm)
    #>
    param (
        $Resource,
        $Key,
        $From,
        $To
    )

    $days = [int]($to - $from).TotalDays
    
    $results = @()
    1..$days | %{
        $todaydate = $from.date.AddDays($_ - 1) #Midnight
        $today9am = $todaydate.AddHours(9) #9AM = Midnight + 9 hours
        $today5pm = $today9am.AddHours(8) #5PM = 9AM + 8 hours
        $results += Get-OMStat -Resource $Resource -Key $Key -From $today9am -To $today5pm -RollupType Max -IntervalType Minutes -IntervalCount 60 | Select Resource,Time,Key,@{N="Value";E={ [math]::Round($_.Value,2) }}
    }
    
    return $results
}

function Get-OMStat5to9 {
    <#
    .SYNOPSIS
    Gets stats from vROPs for a resource during off hours (5pm to 9am)
    #>
    param (
        $Resource,
        $Key,
        $From,
        $To
    )

    $days = [int]($to - $from).TotalDays
    
    $results = @()
    1..$days | %{
        $todaydate = $from.date.AddDays($_ - 1) #Midnight
        $today5pm = $todaydate.AddHours(17) #5pm = Midnight + 17 hours
        $tomorrow9am = $today5pm.AddHours(16) #9AM the next day = 5pm + 16 hours
        $results += Get-OMStat -Resource $Resource -Key $Key -From $today5pm -To $tomorrow9am -RollupType Max -IntervalType Minutes -IntervalCount 60 | Select Resource,Time,Key,@{N="Value";E={ [math]::Round($_.Value,2) }}
    }
    
    return $results
}
