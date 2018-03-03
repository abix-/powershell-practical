function Get-TaskPlus {
    <#  
    .SYNOPSIS  Returns vSphere Task information   
    .DESCRIPTION The function will return vSphere task info. The
      available parameters allow server-side filtering of the
      results
    .NOTES  Author:  Luc Dekens  
    .PARAMETER Alarm
      When specified the function returns tasks triggered by
      specified alarm
    .PARAMETER Entity
      When specified the function returns tasks for the
      specific vSphere entity
    .PARAMETER Recurse
      Is used with the Entity. The function returns tasks
      for the Entity and all it's children
    .PARAMETER State
      Specify the State of the tasks to be returned. Valid
      values are: error, queued, running and success
    .PARAMETER Start
      The start date of the tasks to retrieve
    .PARAMETER Finish
      The end date of the tasks to retrieve.
    .PARAMETER UserName
      Only return tasks that were started by a specific user
    .PARAMETER MaxSamples
      Specify the maximum number of tasks to return
    .PARAMETER Reverse
      When true, the tasks are returned newest to oldest. The
      default is oldest to newest
    .PARAMETER Server
      The vCenter instance(s) for which the tasks should
      be returned
    .PARAMETER Realtime
      A switch, when true the most recent tasks are also returned.
    .PARAMETER Details
      A switch, when true more task details are returned
    .PARAMETER Keys
      A switch, when true all the keys are returned
    .EXAMPLE
      PS> Get-TaskPlus -Start (Get-Date).AddDays(-1)
    .EXAMPLE
      PS> Get-TaskPlus -Alarm $alarm -Details
    #>
    [CmdletBinding()]
    param(
        [VMware.VimAutomation.ViCore.Impl.V1.Alarm.AlarmDefinitionImpl]$Alarm,
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl]$Entity,
        [switch]$Recurse = $false,
        [VMware.Vim.TaskInfoState[]]$State,
        [DateTime]$Start,
        [DateTime]$Finish,
        [string]$UserName,
        [int]$MaxSamples = 500,
        [switch]$Reverse = $true,
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl[]]$Server = $global:DefaultVIServer,
        [switch]$Realtime,
        [switch]$Details,
        [switch]$Keys,
        [int]$WindowSize = 100
    )

  begin {
    function Get-TaskDetails {
      param(
        [VMware.Vim.TaskInfo[]]$Tasks
      )
      begin{
        $psV3 = $PSversionTable.PSVersion.Major -ge 3
      }

      process{
        $tasks | ForEach-Object{
          if($psV3){
            $object = [ordered]@{}
          }
          else {
            $object = @{}
          }
          $object.Add("Name",$_.Name)
          $object.Add("Description",$_.Description.Message)
          if($Details){$object.Add("DescriptionId",$_.DescriptionId)}
          if($Details){$object.Add("Task Created",$_.QueueTime)}
          $object.Add("Task Started",$_.StartTime)
          if($Details){$object.Add("Task Ended",$_.CompleteTime)}
          $object.Add("State",$_.State)
          $object.Add("Result",$_.Result)
          $object.Add("Entity",$_.EntityName)
          $object.Add("VIServer",$VIObject.Name)
          $object.Add("Error",$_.Error.ocalizedMessage)
          if($Details){
            $object.Add("Cancelled",(&{if($_.Cancelled){"Y"}else{"N"}}))
            $object.Add("Reason",$_.Reason.GetType().Name.Replace("TaskReason",""))
            $object.Add("AlarmName",$_.Reason.AlarmName)
            $object.Add("AlarmEntity",$_.Reason.EntityName)
            $object.Add("ScheduleName",$_.Reason.Name)
            $object.Add("User",$_.Reason.UserName)
          }
          if($keys){
            $object.Add("Key",$_.Key)
            $object.Add("ParentKey",$_.ParentTaskKey)
            $object.Add("RootKey",$_.RootTaskKey)
          }

          New-Object PSObject -Property $object
        }
      }
    }

    $filter = New-Object VMware.Vim.TaskFilterSpec
    if($Alarm){
      $filter.Alarm = $Alarm.ExtensionData.MoRef
    }
    if($Entity){
      $filter.Entity = New-Object VMware.Vim.TaskFilterSpecByEntity
      $filter.Entity.entity = $Entity.ExtensionData.MoRef
      if($Recurse){
        $filter.Entity.Recursion = [VMware.Vim.TaskFilterSpecRecursionOption]::all
      }
      else{
        $filter.Entity.Recursion = [VMware.Vim.TaskFilterSpecRecursionOption]::self
      }
    }
    if($State){
      $filter.State = $State
    }
    if($Start -or $Finish){
      $filter.Time = New-Object VMware.Vim.TaskFilterSpecByTime
      $filter.Time.beginTime = $Start
      $filter.Time.endTime = $Finish
      $filter.Time.timeType = [vmware.vim.taskfilterspectimeoption]::startedTime
    }
    if($UserName){
      $userNameFilterSpec = New-Object VMware.Vim.TaskFilterSpecByUserName
      $userNameFilterSpec.UserList = $UserName
      $filter.UserName = $userNameFilterSpec
    }
    $nrTasks = 0
  }

  process {
    foreach($viObject in $Server){
      $si = Get-View ServiceInstance -Server $viObject
      $tskMgr = Get-View $si.Content.TaskManager -Server $viObject 

      if($Realtime -and $tskMgr.recentTask){
        $tasks = Get-View $tskMgr.recentTask
        $selectNr = [Math]::Min($tasks.Count,$MaxSamples-$nrTasks)
        Get-TaskDetails -Tasks[0..($selectNr-1)]
        $nrTasks += $selectNr
      }

      $tCollector = Get-View ($tskMgr.CreateCollectorForTasks($filter))

      if($Reverse){
        $tCollector.ResetCollector()
        $taskReadOp = $tCollector.ReadPreviousTasks
      }
      else{
        $taskReadOp = $tCollector.ReadNextTasks
      }
      do{
        $tasks = $taskReadOp.Invoke($WindowSize)
        if(!$tasks){exit}
        $selectNr = [Math]::Min($tasks.Count,$MaxSamples-$nrTasks)
        Get-TaskDetails -Tasks $tasks[0..($selectNr-1)]
        $nrTasks += $selectNr
      }while($nrTasks -lt $MaxSamples)
    }
    $tCollector.DestroyCollector()
  }
}

function Start-ChromePlus {
    [cmdletbinding()]
    #requires -Version 3.0
    param (
        $chromeExe = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        $plusFlags = "--cipher-suite-blacklist=0x0088,0x0087,0x0039,0x0038,0x0044,0x0045,0x0066,0x0032,0x0033,0x0016,0x0013"
    )
    taskkill.exe /F /IM chrome.exe /T
    Write-Host "Starting Chrome with $plusFlags"
    Start-Process $chromeExe -ArgumentList $plusFlags
}

function FunctionTemplate {
    [cmdletbinding()]
    #requires -Version 3.0
    param (
    )
    $csv = Import-Csv .\CX-500.csv
    foreach($_c in $csv) {
        Write-Debug "debugging time"
        Write-Host "$_c is my name"
    }
}

Export-ModuleMember *-*