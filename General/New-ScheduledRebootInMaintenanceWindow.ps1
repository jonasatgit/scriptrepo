#************************************************************************************************************
# Disclaimer
# This sample script is not supported under any Microsoft standard support program or service. This sample
# script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties
# including, without limitation, any implied warranties of merchantability or of fitness for a particular
# purpose. The entire risk arising out of the use or performance of this sample script and documentation
# remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation,
# production, or delivery of this script be liable for any damages whatsoever (including, without limitation,
# damages for loss of business profits, business interruption, loss of business information, or other
# pecuniary loss) arising out of the use of or inability to use this sample script or documentation, even
# if Microsoft has been advised of the possibility of such damages.
#************************************************************************************************************
$scriptVersion = '20200212'
#INFO: Always also use powershell 2.0 commands, in case powershell 2.0 is still in use
#INFO: The script can be used whtin a baseline with a recurring schedule or as a script in ConfigMgr directly
#INFO: Main purpose is to ensure 100% patch compliance
# Source: https://github.com/jonasatgit/scriptrepo/tree/master/General

[int]$minutesToRestartBeforeMaintenanceEndTime = 10 # should be at least 4 minutes, otherwise the randomization might not work as expected
[string]$scheduledTaskName = 'SCCM_Custom_Reboot' # name of the scheduled task
[string]$taskDescription = "Will reboot the system around 10 minutes before the SCCM service window ends, if a reboot is still pending and the service window still available."
[string]$scheduledTaskScriptPath = "$env:windir\ccmtools\Schedule-RebootInMaintenanceWindow.ps1" # name and path of the script the scheduled task will run. Will be the content of $scheduledTaskScript
[string]$global:logPath = "$scheduledTaskScriptPath.log"

function Log-Line
{
   param($message)
   $logTime = Get-Date -Format "HH:mm:ss.fff"
   $logDate = Get-Date -Format "MM-dd-yyyy"
   $LogTimePlusBias = "{0}-000" -f $logTime
   $output = "<![LOG[$message]LOG]!>" + "<time=`"$LogTimePlusBias`" "+ "date=`"$LogDate`" " + "component=`"script`" " + "context=`"`" " +"type=`"1`" " + "thread=`"0`" " + "file=`"$Component`">"
   $output | Out-File -FilePath $global:logPath -Encoding utf8 -Append -NoClobber
}

function Log-Rollover
{
    $logFileItem = Get-Item $global:logPath -ErrorAction SilentlyContinue
    if($logFileItem -and ($logFileItem.Length/1024) -gt 1024) # file should be 1mb max
    {
        $newLogFileName = "$($logFileItem.FullName).lo_"
        Remove-Item -Path $newLogFileName -Force -ErrorAction SilentlyContinue # remove old history first
        Rename-Item -Path $global:logPath -NewName $newLogFileName -Force -ErrorAction SilentlyContinue
    }
}

$scheduledTaskScript = @'
#************************************************************************************************************
# Disclaimer
# This sample script is not supported under any Microsoft standard support program or service. This sample
# script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties
# including, without limitation, any implied warranties of merchantability or of fitness for a particular
# purpose. The entire risk arising out of the use or performance of this sample script and documentation
# remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation,
# production, or delivery of this script be liable for any damages whatsoever (including, without limitation,
# damages for loss of business profits, business interruption, loss of business information, or other
# pecuniary loss) arising out of the use of or inability to use this sample script or documentation, even
# if Microsoft has been advised of the possibility of such damages.
#************************************************************************************************************
[string]$global:logPath = "$($MyInvocation.MyCommand.Path).Log" # logfile in the same directory as the script

[int]$maxRebootDays = 40 # max days of system runtime until a reboot will be scheduled even if no reboot has been detected

function Log-Line
{
   param($message)
   $logTime = Get-Date -Format "HH:mm:ss.fff"
   $logDate = Get-Date -Format "MM-dd-yyyy"
   $LogTimePlusBias = "{0}-000" -f $logTime
   $output = "<![LOG[$message]LOG]!>" + "<time=`"$LogTimePlusBias`" "+ "date=`"$LogDate`" " + "component=`"script`" " + "context=`"`" " +"type=`"1`" " + "thread=`"0`" " + "file=`"$Component`">"
   $output | Out-File -FilePath $global:logPath -Encoding utf8 -Append -NoClobber
}

function Get-LastRebootTime
{
    try
    {
        $win32OperatingSystem = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
        $LastBootUpTime = $win32OperatingSystem.ConvertToDateTime($win32OperatingSystem.LastBootUpTime)
        return (New-TimeSpan $LastBootUpTime (Get-Date)).Days
    }catch{}
}


function Test-PendingReboot 
{
    $rebootTypes = New-Object System.Collections.ArrayList
    if(Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue) { [void]$rebootTypes.Add("CBSRebootPending") }
    if(Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue) { [void]$rebootTypes.Add("UpdateRebootRequired") }
    if(Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting" -ErrorAction SilentlyContinue) { [void]$rebootTypes.Add("UpdatePostReboot") }
    if(Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress" -ErrorAction SilentlyContinue) { [void]$rebootTypes.Add("CBSinProgress") }
    if(Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending" -ErrorAction SilentlyContinue) { [void]$rebootTypes.Add("CBSPackagePending") }
    # too many false positives with PendigFileRenameOperations
    #if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue) { [void]$rebootTypes.Add("FileRename") }
    try
    { 
        $rebootStatus = ([wmiclass]"root\ccm\clientsdk:CCM_ClientUtilities").DetermineIfRebootPending()
        if(($rebootStatus) -and ($rebootStatus.RebootPending -or $rebootStatus.IsHardRebootPending)) 
        {
            [void]$rebootTypes.Add("SCCM")
        }
    }catch{}
    if($rebootTypes)
    {
        return $rebootTypes -join ','
    }
    else
    {
        return $false
    }
}

function Test-ServiceWindowAvailable
{    
    [bool]$FallbacktoAllProgramsWindows = $false
    [int]$MaxRunTime = 1
    Try
    {
		# since fallback isnt working all the time, check for both types
        # ServiceWindowType 1 = all, 4 = updates 
		$MW = ([WMIClass]'root\ccm\clientsdk:CCM_ServiceWindowManager')
		$MWAvalailableUpdates = $MW.IsWindowAvailableNow(4,$FallbacktoAllProgramsWindows,$MaxRunTime)
		$MWAvalailableAllTypes = $MW.IsWindowAvailableNow(1,$FallbacktoAllProgramsWindows,$MaxRunTime)
        if(($MWAvalailableUpdates.CanProgramRunNow) -or ($MWAvalailableAllTypes.CanProgramRunNow))
        {
            return $true
        }
        else
        {
            return $false 
        }
    }
    Catch
    {
		return $false
    }
}


Log-Line "-----------Started script: $($MyInvocation.MyCommand.Name)"
$pendingReboot = Test-PendingReboot
$lastRebootDays = Get-LastRebootTime
$serviceWindowAvailability = Test-ServiceWindowAvailable
Log-Line "Status = Pending reboot: $pendingReboot, LastRebootInDays: $lastRebootDays, MaxRebootDays: $maxRebootDays, ServiceWindowAvailable: $serviceWindowAvailability"
# restart if a reboot is pending or the last reboot is $maxRebootDays old and only if a service window is available
if(($pendingReboot -or ($lastRebootDays -gt $maxRebootDays)) -and ($serviceWindowAvailability))
{
    # create eventlog entry with description
    if(-NOT($pendingReboot))
    {
        $rebootComment = "SCCM custom reboot. Reason: Too many days online! LastRebootDays: $($lastRebootDays)"   
    }
    else
    {
        $rebootComment = "SCCM custom reboot. Reason: $($pendingReboot) LastRebootDays: $($lastRebootDays)"
    }
    Log-Line $rebootComment    
    Start-Process -FilePath "shutdown.exe" -ArgumentList  "/f /r /t 20 /d p:2:18 /c `"$($rebootComment)`""
}
else
{
    Log-Line "Will not reboot. See status"
    Log-Line "Done"
}
'@

# delete file in wrong location. Due to a problem with systems just having powershell 2.0
if(Test-Path "C:\Schedule-RebootInMaintenanceWindow.ps1.log")
{
    Remove-Item -Path "C:\Schedule-RebootInMaintenanceWindow.ps1.log" -Force -ErrorAction SilentlyContinue
}

# create folder and empty file, just to have the full path
if(-NOT (Test-Path $scheduledTaskScriptPath))
{
    $temp = New-Item -ItemType File -Path $scheduledTaskScriptPath -Force
}
# output the current file
$scheduledTaskScript | Out-File -FilePath "$scheduledTaskScriptPath" -Force
Log-Line "-----------Started script: $($MyInvocation.MyCommand.Name)"

# get endtime of the next maintenance window
$ServiceWindows = Get-WmiObject -Namespace root\ccm\ClientSDK -query "select * from CCM_ServiceWindow where Type = 1 or Type = 4" -ErrorAction SilentlyContinue
Log-Line "Found $($ServiceWindows.count) ServiceWindows for all deployments or updates"
if($ServiceWindows)
{
    # not taking overlapping servicewindows into account
    $NextServiceWindowEndTime = $ServiceWindows | Sort-Object StartTime | Select-Object -ExpandProperty "EndTime" -First 1
    # calculate endtime
    $NextServiceWindowDateTime = [Management.ManagementDateTimeConverter]::ToDateTime($NextServiceWindowEndTime)
    # convert endtime to local timezone
    $EndTime = $NextServiceWindowDateTime.ToUniversalTime()
    Log-Line "Next ServiceWindow endtime = $($EndTime.ToString("yyyy-MM-dd'T'HH:mm:ss"))"
    # randomize the actual reboot a little bit. Shutdown.exe will also add 20 seconds (see script above in here string @@)
    [int]$secondsToRestartBeforeMaintenanceEndTime = (60*$minutesToRestartBeforeMaintenanceEndTime) - (Get-Random -Minimum 1 -Maximum 180)

    # set actual reboot time from service window endtime
    [string]$RebootTime = (($EndTime).AddSeconds(-$secondsToRestartBeforeMaintenanceEndTime)).ToString("yyyy-MM-dd'T'HH:mm:ss")
    Log-Line "Calculated reboot time = $RebootTime"
}

# remove existing task especially when no service window was found
try
{
	Get-ScheduledTask -TaskName $ScheduledTaskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
}Catch{}

# if we have an endtime, register the task
if ($EndTime)
{
    Log-Line "Try to create or update scheduled task"
    $LASTEXITCODE = '$LASTEXITCODE' # easy to use without escape characters. Will redirekt the script exitcode to the task sheduler.
    $taskCommand = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    $taskArgument = "-ExecutionPolicy Bypass -NoProfile -NonInteractive -Command `"& {`"$($scheduledTaskScriptPath)`"; exit $LASTEXITCODE}`""
    try
    {
        # create scheduled task with custom text and software update install as reason
        $ScheduledTaskAction = New-ScheduledTaskAction -Execute $taskCommand  -Argument $taskArgument
        $ScheduledTaskTrigger = New-ScheduledTaskTrigger -At $RebootTime -Once 
        $ScheduledTaskPrincipal = New-ScheduledTaskPrincipal "System"
        $ScheduledTaskSettingsSet = New-ScheduledTaskSettingsSet -StartWhenAvailable
        $ScheduledTask = New-ScheduledTask -Action $ScheduledTaskAction -Principal $ScheduledTaskPrincipal -Trigger $ScheduledTaskTrigger -Settings $ScheduledTaskSettingsSet -Description $taskDescription
        $temp = Register-ScheduledTask -TaskName $ScheduledTaskName -InputObject $ScheduledTask -ErrorAction Stop
    }
    catch
    {
        Log-Line "Scheduled task creation failed $($Error[0].Exception)"
        Log-Line "Try powershell 2.0 method"
        try
        {
            # try a different method if cmdlets not avilable or if Register-ScheduledTasks fails
            $service = new-object -ComObject("Schedule.Service")
            $service.Connect()
            $rootFolder = $service.GetFolder("\")
            $TaskDefinition = $service.NewTask(0)
            $TaskDefinition.RegistrationInfo.Description = "$TaskDescription"
            $TaskDefinition.Settings.Enabled = $true
            $TaskDefinition.Settings.AllowDemandStart = $true
            $TaskDefinition.Settings.StartWhenAvailable = $true
            $triggers = $TaskDefinition.Triggers
            # https://docs.microsoft.com/windows/win32/api/taskschd/ne-taskschd-task_trigger_type2
            $trigger = $triggers.Create(1)
            $trigger.StartBoundary = $RebootTime
            $trigger.Enabled = $true
            # https://docs.microsoft.com/windows/win32/api/taskschd/nf-taskschd-itaskservice-newtask
            $Action = $TaskDefinition.Actions.Create(0)
            $action.Path = "$TaskCommand"
            $action.Arguments = "$taskArgument"
            # https://docs.microsoft.com/windows/win32/api/taskschd/nf-taskschd-itaskfolder-registertaskdefinition
            [void]$rootFolder.RegisterTaskDefinition("$ScheduledTaskName",$TaskDefinition,6,"System",$null,5)
        }
        catch
        {
            Log-Line "Scheduled task creation failed $($Error[0].Exception)"
            Write-Output 'Failed'
        }
    }
}
Log-Line "Done"
Log-Rollover
Write-Output 'Done'