#************************************************************************************************************
# Disclaimer
#
# This sample script is not supported under any Microsoft standard support program or service. This sample
# script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties
# including, without limitation, any implied warranties of merchantability or of fitness for a particular
# purpose. The entire risk arising out of the use or performance of this sample script and documentation
# remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation,
# production, or delivery of this script be liable for any damages whatsoever (including, without limitation,
# damages for loss of business profits, business interruption, loss of business information, or other
# pecuniary loss) arising out of the use of or inability to use this sample script or documentation, even
# if Microsoft has been advised of the possibility of such damages.
#
#************************************************************************************************************
# Source: https://github.com/jonasatgit/scriptrepo

<#
.SYNOPSIS
Script to create update deployments based on Automatic Deployment Rules. 

.DESCRIPTION
Script to create update deployments based on Automatic Deployment Rules (ADR). Everything has to be configured in a JSON ScheduleDefinitionFile like the collection,
the update group and the exact schedule times. The JSON file helps to keep the deployments consistent and to schedule on exact date and times with more flexibility 
as possible with an ADR.

.PARAMETER ScheduleDefinitionFile
The path to the JSON ScheduleDefinitionFile

.PARAMETER UseOffsetDays
Switch parameter. Can be used to force the script to only run on a specific day after Patch Tuesday. The offset must be defined with the parameter "OffsetDays"
If the parameter is used and the "OffsetDays" are set to 1 for example, the script will only run the day after Patch Tuesday and will stop its activities every other day. 

.PARAMETER OffsetDays
Number of days when the script should be run after Patch Tuesday. Must be set when UseOffsetDays is set.

.PARAMETER Deploy
Switch parameter to deploy without validation. Needs to be used when the script has to run as a scheduled task.

.PARAMETER DeleteOrArchiveGroups
Switch parameter to delete Or ArchiveGroups. If NOT used the settings of DeleteUpdateGroups and ArchiveUpdateGroups of the JSON file will be ignored. 

.INPUTS
Just the JSON file. You cannot pipe objects to the script.

.OUTPUTS
Just normal console output and a logfile named after the script. 

.EXAMPLE
Run manually and choose which deployments to create using a gridview
.\Create.PatchDeployments.ps1 -ScheduleDefinitionFile -ScheduleDefinitionFile "D:\CUSTOM\UpdateDeployments\ScheduleServerDeployments.json

.EXAMPLE
Use offset days to restrict the day the script can run to a certain day after patch Tuesday. Helpful if the script needs to run the day after patch Tuesday for example
.\Create.PatchDeployments.ps1 -ScheduleDefinitionFile -ScheduleDefinitionFile "D:\CUSTOM\UpdateDeployments\ScheduleServerDeployments.json -UseOffsetDays -OffsetDays 1 -Deploy

.EXAMPLE
When run within a scheduled task: 
"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass –NoProfile -Noninteractive –Command "& {"D:\CUSTOM\Create-PatchDeployments.ps1" -ScheduleDefinitionFile "D:\CUSTOM\ScheduleServerDeployments.json -Deploy"; exit $LASTEXITCODE}"

.LINK
https://github.com/jonasatgit/scriptrepo

#>
[CmdletBinding(DefaultParametersetName='None')]
param
(
    #param 1 $ScheduleDefinitionFile path to JSON definition file
    [Parameter(Mandatory=$false)]
    [string]$ScheduleDefinitionFile,
    [parameter(ParameterSetName = 'OffsetDays',Mandatory=$false)]
    [switch]$UseOffsetDays=$false,
    [parameter(ParameterSetName = 'OffsetDays',Mandatory=$true)]	
    [int]$OffsetDays=0, 
    [Parameter(Mandatory=$false)]
    [switch]$Deploy,
    [Parameter(Mandatory=$false)]
    [switch]$DeleteOrArchiveGroups
)


#region PARAMETERS 
[string]$ScriptVersion = "20210308"
[string]$global:Component = $MyInvocation.MyCommand
[string]$global:LogFile = "$($PSScriptRoot)\$($global:Component).Log"
[bool]$global:ErrorOutput = $false
#endregion

#region Write-ScriptLog
<#
.Synopsis
   Logging function
.DESCRIPTION
   Logging function
.EXAMPLE
   Write-ScriptLog -LogFile [Logfile] -Message "something happened" -Component "Scriptv002" -Severity Error  
.EXAMPLE
   Write-ScriptLog -LogFile [Logfile] -Message "something happened" -Component "Scriptv002" -Severity Error -WriteToEventLog Yes -EventlogName Application -EventID 456
#> 
Function Write-ScriptLog
{

    #Define and validate parameters
    [CmdletBinding()]
    Param
    (
        #Path to the log file
        [parameter(Mandatory=$false)]
        [String]$LogFile = $global:LogFile,

        #The information to log
        [parameter(Mandatory=$True)]
        [String]$Message,

        #The source of the error
        [parameter(Mandatory=$false)]
        [String]$Component = $global:Component,

        #The severity (1 - Information, 2- Warning, 3 - Error) for better reading purposes is variable in string
        [parameter(Mandatory=$false)]
        [ValidateSet("Information","Warning","Error")]
        [String]$Severity = 'Information',

        #The Eventlog Name
        [parameter(Mandatory=$False)]
        [ValidateSet("Application","System")]
        [String]$EventlogName="Application",

        #EventID
        [parameter(Mandatory=$false)]
        [Single]$EventID=1,

        #Write to eventlog
        [parameter(Mandatory=$false)]
        [ValidateSet("Yes","No")]
        [String]$WriteToEventLog = "No"
    )

    if ($WriteToEventLog -eq "Yes")
    {
        # check if eventsource exists otherwise create eventsource
        if ([System.Diagnostics.EventLog]::SourceExists($Component) -eq $false)
        {
            try
            {
                [System.Diagnostics.EventLog]::CreateEventSource($Component, $EventlogName )
            }
            catch
            {
                exit 2
            }
         }
        Write-EventLog –LogName $EventlogName –Source $Component –EntryType $Severity –EventID $EventID –Message $Message
    }

    # save severity in single for cmtrace severity
    [single]$cmSeverity=1
    switch ($Severity) 
        { 
            "Information" {$cmSeverity=1} 
            "Warning" {$cmSeverity=2} 
            "Error" {$cmSeverity=3} 
        }

    #Obtain UTC offset
    $DateTime = New-Object -ComObject WbemScripting.SWbemDateTime 
    $DateTime.SetVarDate($(Get-Date))
    $UtcValue = $DateTime.Value
    $UtcOffset = $UtcValue.Substring(21, $UtcValue.Length - 21)

    #Create the line to be logged
    $LogLine =  "<![LOG[$Message]LOG]!>" +
                "<time=`"$(Get-Date -Format HH:mm:ss.mmmm)$($UtcOffset)`" " +
                "date=`"$(Get-Date -Format M-d-yyyy)`" " +
                "component=`"$Component`" " +
                "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +
                "type=`"$cmSeverity`" " +
                "thread=`"$([Threading.Thread]::CurrentThread.ManagedThreadId)`" " +
                "file=`"`">"

    #Write the line to the passed log file
    $LogLine | Out-File -Append -Encoding UTF8 -FilePath $LogFile
}
#endregion


#region Rollover-Logfile
<#
.Synopsis
   Will create a new logfile if a specified file size is reached
.DESCRIPTION
   Will create a new logfile if a specified file size is reached
.EXAMPLE
   Rollover-Logfile -Logfile C:\temp\logfile.log -MaxFileSizeKB 2048
.EXAMPLE
   Rollover-Logfile -Logfile C:\temp\logfile.log
#> 
function Rollover-Logfile
{
[CmdletBinding()]
Param(
      #Path to test
      [parameter(Mandatory=$True)]
      $Logfile,
      
      #max Size in KB
      [parameter(Mandatory=$false)]
      [int]$MaxFileSizeKB = 1024
    )

    if (Test-Path $Logfile)
    {
        $getLogfile = Get-Item $logFile
        $logfileSize = $getLogfile.Length/1024
        $newName = ($getLogfile.BaseName)
        $newName += ".lo_"
        $newLogFile = "$($getLogfile.Directory)\$newName"

        if ($logfileSize -gt $MaxFileSizeKB)
        {
            if (Test-Path $newLogFile)
            {
                #need to delete old file first
                Remove-Item -Path $newLogFile -Force -ErrorAction SilentlyContinue
            }
            Rename-Item -Path $logFile -NewName $newName -Force -ErrorAction SilentlyContinue
        }
    }
}
#endregion


#region Get-SCCMSiteInfo
<#
.Synopsis
   Will retrieve the ConfigMgr SiteCode from the local Site Server and the siteserver name
.DESCRIPTION
   Will retrieve the ConfigMgr SiteCode from the local Site Server and the siteserver name
.EXAMPLE
   Get-SCCMSiteInfo
.EXAMPLE
   Get-SCCMSiteInfo "No Parameters"
#> 
function Get-SCCMSiteInfo
{
    try
    {
        # registry: need to be admin to read
        #$SiteCode = (Get-ItemProperty -Path "Registry::HKLM\SOFTWARE\Microsoft\SMS\Identification" -Name "Site Code" -ErrorAction Stop).'Site Code'
        # wmi: don't need to be admin to read
        $ProviderInfo = (Get-WmiObject -Namespace root\sms -query "select SiteCode, Machine from SMS_ProviderLocation where ProviderForLocalSite = True") | Select-Object SiteCode, Machine -First 1
    }
    catch
    {
        return $null
    }
    return $ProviderInfo

}
#endregion

#region Find-DayOfWeek
<#
.Synopsis
   Will return the specific date and time of day within a week. 
.DESCRIPTION
   This function can help to find the second Tuesday to use that date for patch deployments. 
   Use the parameter -Startdate to find the day within a specific month instead of the current month.
   The -Time parameter will add a specified time to the date in the format mm:ss
.EXAMPLE
   Find-DayOfWeek -Weekday Tuesday -week 2 -Time "22:00"
.EXAMPLE
   Find-DayOfWeek -Weekday Tuesday -week 2 -Time "22:00" -StartDate "2015-12-3"
#> 
function Find-DayOfWeek
{
    param(
        [parameter(Mandatory=$true)]
        [validateset("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday")]
        [string]$Weekday,
        [parameter(Mandatory=$true)]
        [validateset(1,2,3,4,5)]
        [int]$Week,
        [parameter(Mandatory=$true)]
        [string]$Time,
        [parameter(Mandatory=$false)]
        $StartDate = (Get-Date)
        )
    
    $DateFormat = "yyyy-MM-dd"
    $dtToday = Get-Date($StartDate)
    $strMonth=$dtToday.Month.ToString()
    $strYear=$dtToday.Year.ToString()

    # find first day of month
    $startDate = get-date("$strYear-$strMonth-1")

    # find day we are looking for
    while ($startDate.DayOfWeek -ine $WeekDay)
        { 
            $startDate = $startDate.AddDays(1)
        }
    # add 7 days for every week we are looking for
    $startDate = $startDate.AddDays(7*($Week-1))
    # add time to date
    $startDate = Get-Date($startDate) -format "$DateFormat $Time"
    return $startDate
}
#endregion 

#region Find-DayOfMonth
<#
.Synopsis
   Will return the specific date and time of day within a month. 
.DESCRIPTION
   This function can help to find the exact datetime value of a day in a month. Like the first or last day or any other da in between.
   Use the parameter -Startdate to find the day within a specific month instead of the current month.
   The -Time parameter will add a specified time to the date in the format mm:ss
.EXAMPLE
   Find-DayOfMonth -DayOfMonth 1 -Time "22:00"
   For the first day of the month
.EXAMPLE
   Find-DayOfMonth -LastDayOfMonth -Time "22:00"
   For the last day of the month
.EXAMPLE
   Find-DayOfMonth -DayOfMonth 3 -Time "22:00" -StartDate ((get-date).AddMonths(1))
   For the 3rd day in the next month
#> 
function Find-DayOfMonth
{
    [CmdletBinding(DefaultParametersetName='None')]
    param(
        [parameter(ParameterSetName = 'DaysOfMonthSet',Mandatory=$True)]
        [int]$DayOfMonth,
        [parameter(ParameterSetName = 'LastDayOfMonthSet',Mandatory=$True)]
        [switch]$LastDayOfMonth,
        [parameter(Mandatory=$true)]
        [string]$Time,
        [parameter(Mandatory=$false)]
        $StartDate = (Get-Date)
        )
    
    $DateFormat = "yyyy-MM-dd"
    $dtToday = Get-Date($StartDate)
    $strMonth=$dtToday.Month.ToString()
    $strYear=$dtToday.Year.ToString()

    # calculate last day of month
    $daysInMonth = [datetime]::DaysInMonth($strYear,$strMonth)

    if ($LastDayOfMonth)
    {
        # use last day of month
        $startDate = get-date("$strYear-$strMonth-$daysInMonth")
    }
    else
    {
        # prevent errors if the day zero was choosen and set if to 1
        if ($DayOfMonth -eq 0)
        {
            $DayOfMonth = 1
        }

        if ($DayOfMonth -gt $daysInMonth)
        {
            # error not enough days in month. Use last day
            $startDate = get-date("$strYear-$strMonth-$daysInMonth")
        }
        else
        {
            # use the day specified via parameter
            $startDate = get-date("$strYear-$strMonth-$DayOfMonth")
        }
    }

    # add time to date
    $startDate = Get-Date($startDate) -format "$DateFormat $Time"
    return $startDate
}
#endregion 

#region Get-ADRScheduleTimes
<#
.Synopsis
   Will convert the integer of days and the string of time to actual datetimes, based on the defined startDate
.DESCRIPTION
   Will convert the integer of days and the string of time to actual datetimes, based on the defined startDate
.EXAMPLE
   $schedules | Get-ADRScheduleTimes
   $schedules needs to be the ADRs Part of the JSON definition file: "$schedules.ADRSchedules.ADRs"
#>
function Get-ADRScheduleTimes
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [object]$Schedule
    )
 
    Begin
    {
        $arrayList = New-Object System.Collections.ArrayList
        $comp = ($MyInvocation.MyCommand)
    }
    Process
    {
        $DateFormat = "yyyy-MM-dd"
        # calculate base-startdate first, to make sure we pick the right date in the right month
        # determine if we need to calculate the day or the week and the day of the month
        # this will define the base date from wich we will deploy based on what is set in "$Schedule.StartDays" and "$Schedule.DeadlineDays"
        if ($Schedule.StartWeekInMonth -and $Schedule.StartWeekdayInMonth)
        {
            # we need to find the day and the week of the month. Like the 2nd Tuesday for example.  
            $baseStartDate = Find-DayOfWeek -Weekday ($Schedule.StartWeekdayInMonth) -Week ($Schedule.StartWeekInMonth) -Time ($Schedule.StartTime) -StartDate ((Get-Date).AddMonths($Schedule.StartMonth))
        }
        else
        {
            if(-NOT($Schedule.StartDayInMonth))
            {
                # day in month is missing, using last day of month
                Write-ScriptLog -Message "Day in month is missing, using last day of month for: `"$($Schedule.CollectionName)`"" -Component $comp -Severity Warning
                $baseStartDate = Find-DayOfMonth -LastDayOfMonth -Time ($Schedule.StartTime) -StartDate ((Get-Date).AddMonths($Schedule.StartMonth))
            }
            else
            {
                # we need to find the day of a month
                if ($Schedule.StartDayInMonth -ieq 'Last')
                {
                    $baseStartDate = Find-DayOfMonth -LastDayOfMonth -Time ($Schedule.StartTime) -StartDate ((Get-Date).AddMonths($Schedule.StartMonth))
                }
                else
                {
                    $baseStartDate = Find-DayOfMonth -DayOfMonth $Schedule.StartDayInMonth -Time ($Schedule.StartTime) -StartDate ((Get-Date).AddMonths($Schedule.StartMonth))
                }
            }
        }

        # add start and deadline days to baseStartdate and add time
        $startDateTime = (Get-Date($baseStartDate)).AddDays(($Schedule.StartDays))
        $startDateTime = Get-Date($startDateTime) -format "$DateFormat $($Schedule.StartTime)"

        $deadlineDateTime = (Get-Date($baseStartDate)).AddDays(($Schedule.DeadlineDays))
        $deadlineDateTime = Get-Date($deadlineDateTime) -format "$DateFormat $($Schedule.DeadlineTime)"

        # copy object to add new properties and to not change the existing object
        $obScheduleOut = $Schedule.psobject.copy()
        # add schedule times to object
        $obScheduleOut | Add-Member -MemberType NoteProperty -Name StartDateTime -Value ($startDateTime)
        $obScheduleOut | Add-Member -MemberType NoteProperty -Name DeadlineDatetime -Value ($deadlineDateTime)

        [void]$arrayList.Add($obScheduleOut)
    }
    End
    {
        return $arrayList
    }
}
#endregion


#region New-SCCMSoftwareUpdateDeployment
<#
.Synopsis
   Will create SoftwareUpdate Deployments using a custom schedules object
.DESCRIPTION
   Will create SoftwareUpdate Deployments using a custom schedules object
.EXAMPLE
   New-SCCMSoftwareUpdateDeployment -Schedules $CustomSchedulesObject
.EXAMPLE
   $CustomSchedulesObjects | New-SCCMSoftwareUpdateDeployment
#>
function New-SCCMSoftwareUpdateDeployment
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [object]$Schedule,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false)]
        [int]$CollectionCount,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$SiteCode,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$ProviderMachineName
    )
 
    Begin
    {
        $i=0
        $comp = ($MyInvocation.MyCommand)
    }
    Process
    {
        $i++
        Write-ScriptLog -Message "------------------------------" -Component $comp
        Write-ScriptLog -Message "COLLECTION $i of $($CollectionCount):" -Component $comp
        Write-ScriptLog -Message "    `"$(($Schedule.CollectionName).ToUpper())`" -> of deployment process for collection..." -Component $comp
        Write-ScriptLog -Message "    " -Component $comp
        Write-ScriptLog -Message "    DEPLOYMENT SETTINGS:" -Component $comp
        Write-ScriptLog -Message "    Deployment enabled ------------------------------>> $($Schedule.SetCMSoftwareUpdateDeploymentEnable)" -Component $comp
        Write-ScriptLog -Message "    RemoveUpdateDeploymentsFirst--------------------->> $($Schedule.RemoveUpdateDeploymentsFirst)" -Component $comp
        Write-ScriptLog -Message "    StartDateTime ----------------------------------->> $($Schedule.StartDatetime)" -Component $comp
        Write-ScriptLog -Message "    DeadlineDateTime: ------------------------------->> $($Schedule.DeadlineDateTime)" -Component $comp
        Write-ScriptLog -Message "    DeploymentType: --------------------------------->> $($Schedule.NewCMSoftwareUpdateDeploymentDeploymentType)" -Component $comp
        Write-ScriptLog -Message "    Use WoL: ---------------------------------------->> $($Schedule.NewCMSoftwareUpdateDeploymentSendWakeupPacket)" -Component $comp
        Write-ScriptLog -Message "    VerbosityLevel: --------------------------------->> $($Schedule.NewCMSoftwareUpdateDeploymentVerbosityLevel)" -Component $comp
        Write-ScriptLog -Message "    TimeBasedOn: ------------------------------------>> $($Schedule.NewCMSoftwareUpdateDeploymentTimeBasedOn)" -Component $comp
        Write-ScriptLog -Message "    UserNotification: ------------------------------->> $($Schedule.NewCMSoftwareUpdateDeploymentUserNotification)" -Component $comp
        Write-ScriptLog -Message "    SoftwareInstallation outside of Maintenance: ---->> $($Schedule.NewCMSoftwareUpdateDeploymentSoftwareInstallation)" -Component $comp
        Write-ScriptLog -Message "    AllowRestart  outside of Maintenance: ----------->> $($Schedule.NewCMSoftwareUpdateDeploymentAllowRestart)" -Component $comp
        Write-ScriptLog -Message "    Supress RestartServer: -------------------------->> $($Schedule.NewCMSoftwareUpdateDeploymentRestartServer)" -Component $comp
        Write-ScriptLog -Message "    Supress RestartWorkstation: --------------------->> $($Schedule.NewCMSoftwareUpdateDeploymentRestartWorkstation)" -Component $comp
        Write-ScriptLog -Message "    PostRebootFullScan if Update needs restart: ----->> $($Schedule.NewCMSoftwareUpdateDeploymentRequirePostRebootFullScan)" -Component $comp
        Write-ScriptLog -Message "    DP Download ProtectedType: ---------------------->> $($Schedule.NewCMSoftwareUpdateDeploymentProtectedType)" -Component $comp
        Write-ScriptLog -Message "    DP Download UnprotectedType: -------------------->> $($Schedule.NewCMSoftwareUpdateDeploymentUnprotectedType)" -Component $comp
        Write-ScriptLog -Message "    UseBranchCache if possible: --------------------->> $($Schedule.NewCMSoftwareUpdateDeploymentUseBranchCache)" -Component $comp
        Write-ScriptLog -Message "    DownloadFromMicrosoftUpdate: -------------------->> $($Schedule.NewCMSoftwareUpdateDeploymentDownloadFromMicrosoftUpdate)" -Component $comp
        Write-ScriptLog -Message "    " -Component $comp

        <#
            There are two main processes here:
            #1 Clean all update deployments from the collection and deploy new update groups.
            #2 Leave the deployments as they are and just deploy new update groups, which are not yet deployed

            In both cases older groups could be deleted or archived if set so in the JSON file
        #>

        # checking existence of collection first
        try
        {
            $checkCollection = Get-CMCollection -Name "$($Schedule.CollectionName)" -ErrorAction Stop
        }
        catch
        {
            Write-ScriptLog -Message "Could not get collection: `"$($Schedule.CollectionName)`"" -Severity Error -Component $comp
            Write-ScriptLog -Message "$($Error[0].Exception)" -Severity Error -Component $comp   
            $global:ErrorOutput = $true 
            break             
        }

        if ($checkCollection)
        {
                
            #check if we need to remove the deployments first
            if ($Schedule.RemoveUpdateDeploymentsFirst -eq $true)
            {
                # remove existing deployments first
                # if error occurs, retry for 3 times
                # 0x80004005 might happen in some SQL deadlock situations with update deployments 
                [bool]$noError = $true
                [int]$maxRetries = 3
                [int]$retryCounter = 0
                [int]$retyTimoutInSeconds = 180
                do
                {
                    try
                    {
                        Write-ScriptLog -Message "    DEPLOYMENT REMOVAL:" -Component $comp
                        $noError = $true
                        [array]$softwareUpdateDeployments = Get-CMSoftwareUpdateDeployment -CollectionName "$($Schedule.CollectionName)" -ErrorAction Stop
                        Write-ScriptLog -Message "        Found $($softwareUpdateDeployments.Count) update deployments." -Component $comp
                        if ($softwareUpdateDeployments.Count -ge 1)
                        {
                            $softwareUpdateDeployments | Remove-CMSoftwareUpdateDeployment -Force -ErrorAction Stop
                        }

                    }
                    catch
                    {
                        Write-ScriptLog -Message "        Could not remove deployment!" -Severity Error -Component $comp 
                        Write-ScriptLog -Message "        $($Error[0].Exception)" -Severity Error -Component $comp 
                        Write-ScriptLog -Message "        will retry for $maxRetries times" -Component $comp
                        Write-ScriptLog -Message "        will also wait for $retyTimoutInSeconds seconds" -Component $comp
                        $noError = $false
                        $retryCounter++
                        Start-Sleep -Seconds $retyTimoutInSeconds
                    }
                }
                until ($noError -or $retryCounter -ge  $maxRetries)

                if(($noError -eq $false) -or ($retryCounter -ge  $maxRetries))
                {
                    Write-ScriptLog -Message "    Too many errors trying to delete deployments. Stopping Script!" -Severity Error -Component $comp    
                    Stop-ScriptExec -exitCode 1
                }

                if ($softwareUpdateDeployments.Count -ge 1)
                {
                    Write-ScriptLog -Message "        Update deployments successfully removed!" -Component $comp
                    Write-ScriptLog -Message "        Will wait 10 seconds for process to finish..." -Component $comp
                    # wait for 10 seconds so that delete command can finish
                    Start-Sleep -Seconds 10
                }
            } # end update deployment removal

            # getting assigments IDs and group IDs to check if the group we choose is deployed already
            try
            {
                [array]$updateGroupAssignmentPerCollection = Get-WmiObject -Namespace "root\sms\site_$($SiteCode)" -ComputerName ($ProviderMachineName) -Query "select AssignmentID, AssignedUpdateGroup, TargetCollectionID from SMS_UpdateGroupAssignment where TargetCollectionID ='$($checkCollection.CollectionID)'" -ErrorAction Stop
            }
            Catch
            {
                Write-ScriptLog -Message "        Could not get updategroup assignements from SMS_UpdateGroupAssignment for TargetCollectionID $($checkCollection.CollectionID)" -Severity Error -Component $comp 
                Write-ScriptLog -Message "        $($Error[0].Exception)" -Severity Error -Component $comp 
                $global:ErrorOutput = $true
                break
            }    
                
            # checking update groups and starting deployment process
            # creating list of groups for deployment process
            $groupsForDeploymentProcess = New-Object System.Collections.ArrayList
            Write-ScriptLog -Message "    GROUP SELECTION:" -Component $comp
            # pick latest update group, check if already deployed and delete group if set so via script parameter
            foreach ($UpdateGroup in $Schedule.UpdateGroups)
            {
                Write-ScriptLog -Message "        Working on group: `"$UpdateGroup`"" -Component $comp

                # get groups per name and sort by creation date to be able to delete the older ones
                # used get-wmiobject to speed up the process, because Get-CMSoftwareUpdateGroup will also load lazy properties
                try
                {
                    [array]$UpdateGroupObjects = Get-WmiObject -Namespace "root\sms\site_$($SiteCode)" -ComputerName ($ProviderMachineName) -Query "Select CI_ID, LocalizedDisplayName, DateCreated from SMS_AuthorizationList where LocalizedDisplayName like '$($UpdateGroup)%'" -ErrorAction Stop
                }
                Catch
                {
                    Write-ScriptLog -Message "        Could not get updategroups with name like $UpdateGroup%" -Severity Error -Component $comp 
                    Write-ScriptLog -Message "        $($Error[0].Exception)" -Severity Error -Component $comp 
                    $global:ErrorOutput = $true  
                }                    

                if ($UpdateGroupObjects)
                {
                    [array]$UpdateGroupObjectsSorted = $UpdateGroupObjects | Sort-Object DateCreated -Descending 
                    Write-ScriptLog -Message "            Found $($UpdateGroupObjects.Count) with same name." -Component $comp
                    Write-ScriptLog -Message "            `"$($UpdateGroupObjectsSorted[0].LocalizedDisplayName)`" is latest group (based on DateCreated) and will be used for deployment" -Component $comp

                    # check if latest group is already deployed if the deployments schould not be removed
                    if ($UpdateGroupObjectsSorted[0].CI_ID -in $updateGroupAssignmentPerCollection.AssignedUpdateGroup)
                    {
                        Write-ScriptLog -Message "            `"$($UpdateGroupObjectsSorted[0].LocalizedDisplayName)`" already deployed. Will skip group!" -Severity Warning -Component $comp 
                    }
                    else
                    {
                        $tmpUpdGroupObj = New-Object psobject | Select-Object UpdateGroupCIID, LocalizedDisplayName, DeploymentName, DeploymentDescription
                        # deploy using the first group in the list
                            
                        $tmpUpdGroupObj.UpdateGroupCIID = $UpdateGroupObjectsSorted[0].CI_ID
                        $tmpUpdGroupObj.LocalizedDisplayName = $UpdateGroupObjectsSorted[0].LocalizedDisplayName
                        # like 20181212-0346
                        $DeploymenNameSuffix = Get-date -format "yyyyMMdd-hhmmss"
                        $tmpUpdGroupObj.DeploymentName = "$UpdateGroup $DeploymenNameSuffix"
                        $tmpUpdGroupObj.DeploymentDescription = "$UpdateGroup $DeploymenNameSuffix"

                        [void]$groupsForDeploymentProcess.Add($tmpUpdGroupObj)
                    }
                } 
                else 
                {
                    Write-ScriptLog -Message "            No group like `"$UpdateGroup`" found!" -Severity Error -Component $comp
                    $global:ErrorOutput = $true
                } #END  if ($UpdateGroupObjects.Count -gt 0)
            } #END foreach group
                
            if ($groupsForDeploymentProcess)
            {
                Write-ScriptLog -Message "    UPDATE DEPLOYMENTS:" -Severity Information -Component $comp
                Write-ScriptLog -Message "            Selected $($groupsForDeploymentProcess.Count) group/s for Deployment" -Severity Information -Component $comp

                foreach($updateGroupForDeployment in $groupsForDeploymentProcess)
                {
                    $paramSplatting = [ordered]@{
                                SoftwareUpdateGroupId = $updateGroupForDeployment.UpdateGroupCIID
                                CollectionName = $($Schedule.CollectionName)
                                DeploymentName = $updateGroupForDeployment.DeploymentName
                                Description = $updateGroupForDeployment.DeploymentDescription
                                DeploymentType = ($Schedule.NewCMSoftwareUpdateDeploymentDeploymentType)
                                SendWakeupPacket = ($Schedule.NewCMSoftwareUpdateDeploymentSendWakeupPacket)
                                VerbosityLevel = ($Schedule.NewCMSoftwareUpdateDeploymentVerbosityLevel)
                                TimeBasedOn = ($Schedule.NewCMSoftwareUpdateDeploymentTimeBasedOn)
                                AvailableDateTime = ($Schedule.StartDatetime)
                                UserNotification = ($Schedule.NewCMSoftwareUpdateDeploymentUserNotification)
                                SoftwareInstallation = ($Schedule.NewCMSoftwareUpdateDeploymentSoftwareInstallation)
                                AllowRestart = ($Schedule.NewCMSoftwareUpdateDeploymentAllowRestart)
                                RestartServer = ($Schedule.NewCMSoftwareUpdateDeploymentRestartServer)
                                RestartWorkstation = ($Schedule.NewCMSoftwareUpdateDeploymentRestartWorkstation)
                                PersistOnWriteFilterDevice = $false
                                GenerateSuccessAlert = $false
                                ProtectedType = ($Schedule.NewCMSoftwareUpdateDeploymentProtectedType)
                                UnprotectedType = ($Schedule.NewCMSoftwareUpdateDeploymentUnprotectedType)
                                UseBranchCache = ($Schedule.NewCMSoftwareUpdateDeploymentUseBranchCache)
                                RequirePostRebootFullScan = ($Schedule.NewCMSoftwareUpdateDeploymentRequirePostRebootFullScan)
                                DownloadFromMicrosoftUpdate = ($Schedule.NewCMSoftwareUpdateDeploymentDownloadFromMicrosoftUpdate)
                    } # end paramsplatting
                            
                    # add deadline datetime if deploymenttype is required
                    if($Schedule.NewCMSoftwareUpdateDeploymentDeploymentType -ieq "Required")
                    {
                        $paramSplatting.add("DeadlineDateTime", "$($Schedule.DeadlineDateTime)")
                    }


                    # if error occurs, retry for 3 times
                    # 0x80004005 might happen in some SQL deadlock situations with update deployments 
                    [bool]$noError = $true
                    [int]$maxRetries = 3
                    [int]$retryCounter = 0
                    [int]$retyTimoutInSeconds = 180
                    do
                    {
                        $noError = $true
                        try 
                        {
                            Write-ScriptLog -Message "            Deploy: `"$($updateGroupForDeployment.LocalizedDisplayName)`"..." -Component $comp
                            # deploy update group
                            $retval = New-CMSoftwareUpdateDeployment @paramSplatting -AcceptEula -ErrorAction Stop
                        }
                        catch
                        {
                            Write-ScriptLog -Message "            Could not create deployment!" -Severity Error -Component $comp 
                            Write-ScriptLog -Message "            $($Error[0].Exception)" -Severity Error -Component $comp 
                            Write-ScriptLog -Message "            will retry for $maxRetries times" -Component $comp
                            Write-ScriptLog -Message "            will also wait for $retyTimoutInSeconds seconds" -Component $comp
                            $noError = $false
                            $retryCounter++
                            Start-Sleep -Seconds $retyTimoutInSeconds
                        }
                    }
                    until ($noError -or $retryCounter -ge  $maxRetries)

                    if(($noError -eq $false) -or ($retryCounter -ge  $maxRetries))
                    {
                        Write-ScriptLog -Message "            Too many errors trying to create deployments. Stopping Script!" -Severity Error -Component $comp    
                        Stop-ScriptExec -exitCode 1
                    }
                    
                    # if error occurs, retry for 3 times
                    # 0x80004005 might happen in some SQL deadlock situations with update deployments 
                    [bool]$noError = $true
                    [int]$maxRetries = 3
                    [int]$retryCounter = 0
                    [int]$retyTimoutInSeconds = 180
                    do
                    {
                        $noError = $true
                        try
                        {                               
                            # additional step to set description because of bug in New-CMSoftwareUpdateDeployment and to disable deployment if set so
                            if (($Schedule.SetCMSoftwareUpdateDeploymentEnable) -eq $false)
                            {
                                Write-ScriptLog -Message "            Setting deployment to DISABLED!" -Severity Warning -Component $comp 
                                $retval | Set-CMSoftwareUpdateDeployment -Enable $false -Description ($updateGroupForDeployment.DeploymentDescription) -ErrorAction Stop
                            }
                            else
                            {
                                $retval | Set-CMSoftwareUpdateDeployment -Description ($updateGroupForDeployment.DeploymentDescription) -ErrorAction Stop
                            }
                        }
                        catch
                        {
                            Write-ScriptLog -Message "            Could not set deployment!" -Severity Error -Component $comp 
                            Write-ScriptLog -Message "            $($Error[0].Exception)" -Severity Error -Component $comp 
                            Write-ScriptLog -Message "            will retry for $maxRetries times" -Component $comp
                            Write-ScriptLog -Message "            will also wait for $retyTimoutInSeconds seconds" -Component $comp
                            $noError = $false
                            $retryCounter++
                            Start-Sleep -Seconds $retyTimoutInSeconds
                        }

                    }
                    until ($noError -or $retryCounter -ge  $maxRetries)

                    if(($noError -eq $false) -or ($retryCounter -ge  $maxRetries))
                    {
                        Write-ScriptLog -Message "            Too many errors trying to set deployments. Stopping Script!" -Severity Error -Component $comp    
                        Stop-ScriptExec -exitCode 1
                    }
                }
            }
        }
        else
        {
            #Write-ScriptLog -Message "Collection not found: $($Schedule.CollectionName)" -Severity Error 
            Write-ScriptLog -Message "COLLECTION: `"$(($Schedule.CollectionName).ToUpper())`" not found!" -Severity Error -Component $comp 
            $global:ErrorOutput = $true
        } # end -> if($checkCollection)

    } # end -> function process
}
#endregion

#region Delete-ObsoleteUpdateGroups
function Delete-ObsoleteUpdateGroups
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [object]$DeleteUpdateGroupSettings,
        [Parameter(Mandatory=$true)]
        [string]$SiteCode,
        [Parameter(Mandatory=$true)]
        [string]$ProviderMachineName,
        [Parameter(Mandatory=$false)]
        [switch]$Delete     
    )

    $comp = ($MyInvocation.MyCommand)

    [int]$MinUpdateGroupsToKeep = $deleteUpdateGroupSettings.MinUpdateGroupsToKeep
    [int]$maxUpdateGroupCreationDays = $deleteUpdateGroupSettings.MaxUpdateGroupCreationDays

    Write-ScriptLog -Message "DELETE UpdateGroups:"-Component $comp
    # pick latest update group
    foreach ($UpdateGroup in $DeleteUpdateGroupSettings.DeleteUpdateGroupList)
    {
        Write-ScriptLog -Message "        Working on group: `"$UpdateGroup`""-Component $comp

        # get groups per name and sort by creation date to be able to delete the older ones
        # used get-wmiobject to speed up the process, because Get-CMSoftwareUpdateGroup will also load lazy properties
        try
        {
            [array]$UpdateGroupObjects = Get-WmiObject -Namespace "root\sms\site_$($SiteCode)" -ComputerName ($ProviderMachineName) -Query "Select CI_ID, LocalizedDisplayName, DateCreated from SMS_AuthorizationList where LocalizedDisplayName like '$($UpdateGroup)%'" -ErrorAction Stop
        }
        Catch
        {
            Write-ScriptLog -Message "        Could not get updategroups with name like $UpdateGroup%" -Severity Error -Component $comp 
            Write-ScriptLog -Message "        $($Error[0].Exception)" -Severity Error -Component $comp 
            $global:ErrorOutput = $true  
        }                    
   

        if ($UpdateGroupObjects)
        {
            [array]$UpdateGroupObjectsSorted = $UpdateGroupObjects | Sort-Object DateCreated -Descending 
            Write-ScriptLog -Message "            Found $($UpdateGroupObjects.Count) with same name." -Component $comp
            # making sure always one group remains with "$UpdateGroupObjects.count -gt 1"
            if($UpdateGroupObjects.count -ge $MinUpdateGroupsToKeep -and $UpdateGroupObjects.count -gt 1)
            {
                #start with min groups to keep until the end of the array
                $UpdateGroupObjectsSorted[$MinUpdateGroupsToKeep..$UpdateGroupObjectsSorted.GetUpperBound(0)] | ForEach-Object {
                    try
                    {
                        $updateGroupDateCreated = ""
                        $updateGroupDateCreated = [Management.ManagementDateTimeConverter]::ToDateTime(($_.DateCreated))
                    }
                    catch
                    {
                        Write-ScriptLog -Message "        Creation Date conversion failed" -Severity Error -Component $comp
                        Write-ScriptLog -Message "        $($Error[0].Exception)" -Severity Error -Component $comp
                        $global:ErrorOutput = $true
                        Continue # with Foreach-Object and skip that one
                    }

                    # work on groups older than $maxUpdateGroupCreationDays
                    if(($updateGroupDateCreated).AddDays($maxUpdateGroupCreationDays) -lt (Get-Date))
                    {
                        try
                        {
                            if ($Delete)
                            {
                                Write-ScriptLog -Message "        `"$($_.LocalizedDisplayName)`" will be deleted. Creation Date: `"$(Get-Date($updateGroupDateCreated) -Format 'yyy-MM-dd')`"" -Severity Warning -Component $comp
                                Remove-CMSoftwareUpdateGroup -Name $($_.LocalizedDisplayName) -Force -ErrorAction Stop
                            }
                            else
                            {
                                Write-ScriptLog -Message "        `"$($_.LocalizedDisplayName)`" WOULD be deleted. Creation Date: `"$(Get-Date($updateGroupDateCreated) -Format 'yyy-MM-dd')`"" -Severity Warning
                            }
                        }
                        Catch
                        {
                            $global:ErrorOutput = $true
                            Write-ScriptLog -Message "            Deletion of group faild: $($Error[0].Exception)" -Severity Warning 
                            # continue with script
                        }
                    }
                    else
                    {
                        Write-ScriptLog -Message "        `"$($_.LocalizedDisplayName)`" skipping, not old enough. Creation Date: `"$(Get-Date($updateGroupDateCreated) -Format 'yyy-MM-dd')`""
                    }       
                }
            }
            else
            {
                Write-ScriptLog -Message "        Skipping group, because of MinUpdateGroupsToKeep setting"   
            }
        }
    }

}
#endregion

#region Archive-ObsoleteUpdateGroups
function Archive-ObsoleteUpdateGroups
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [object]$ArchiveUpdateGroupSettings,
        [Parameter(Mandatory=$true)]
        [string]$SiteCode,
        [Parameter(Mandatory=$true)]
        [string]$ProviderMachineName,
        [Parameter(Mandatory=$false)]
        [switch]$Archive,    
        [Parameter(Mandatory=$false)]
        [string]$ArchiveGroupPrefix = "ARCHIVE"    
    )

    $comp = ($MyInvocation.MyCommand)

    [int]$MinUpdateGroupsToKeep = $ArchiveUpdateGroupSettings.MinUpdateGroupsToKeep
    [int]$maxUpdateGroupCreationDays = $ArchiveUpdateGroupSettings.MaxUpdateGroupCreationDays
    Write-ScriptLog -Message "ARCHIVE UpdateGroups:" -Component $comp
    
    # pick latest update group
    foreach ($UpdateGroup in $ArchiveUpdateGroupSettings.ArchiveUpdateGroupList)
    {
        Write-ScriptLog -Message "        Working on group: `"$UpdateGroup`"" -Component $comp
        $ArchiveGroupName = "{0}_{1}" -f $ArchiveGroupPrefix, $UpdateGroup
        Write-ScriptLog -Message "        ArchiveGroupName: `"$ArchiveGroupName`"" -Component $comp

        # get groups per name and sort by creation date to be able to archive the older ones
        # used get-wmiobject to speed up the process, because Get-CMSoftwareUpdateGroup will also load lazy properties
        try
        {
            [array]$UpdateGroupObjects = Get-WmiObject -Namespace "root\sms\site_$($SiteCode)" -ComputerName ($ProviderMachineName) -Query "Select CI_ID, LocalizedDisplayName, DateCreated from SMS_AuthorizationList where LocalizedDisplayName like '$($UpdateGroup)%'" -ErrorAction Stop
        }
        Catch
        {
            Write-ScriptLog -Message "        Could not get updategroups with name like $UpdateGroup%" -Severity Error -Component $comp
            Write-ScriptLog -Message "        $($Error[0].Exception)" -Severity Error -Component $comp 
            $global:ErrorOutput = $true  
        }                    
   
  
        if ($UpdateGroupObjects)
        {
            [array]$UpdateGroupObjectsSorted = $UpdateGroupObjects | Sort-Object DateCreated -Descending 
            Write-ScriptLog -Message "            Found $($UpdateGroupObjects.Count) with same name." -Component $comp
            # making sure always one group remains with "$UpdateGroupObjects.count -gt 1"
            if($UpdateGroupObjects.count -ge $MinUpdateGroupsToKeep -and $UpdateGroupObjects.count -gt 1)
            {
                #start with min groups to keep until the end of the array
                $UpdateGroupObjectsSorted[$MinUpdateGroupsToKeep..$UpdateGroupObjectsSorted.GetUpperBound(0)] | ForEach-Object {
                    try
                    {
                        $updateGroupDateCreated = ""
                        $updateGroupDateCreated = [Management.ManagementDateTimeConverter]::ToDateTime(($_.DateCreated))
                    }
                    catch
                    {
                        Write-ScriptLog -Message "        Creation Date conversion failed" -Severity Error -Component $comp
                        Write-ScriptLog -Message "        $($Error[0].Exception)" -Severity Error -Component $comp
                        $global:ErrorOutput = $true
                        Continue # with Foreach-Object and skip that one
                    }

                    # work on groups older than $maxUpdateGroupCreationDays
                    if(($updateGroupDateCreated).AddDays($maxUpdateGroupCreationDays) -lt (Get-Date))
                    {
                        if ($Archive)
                        {
                            Write-ScriptLog -Message "        `"$($_.LocalizedDisplayName)`" will be archived. Creation Date: `"$(Get-Date($updateGroupDateCreated) -Format 'yyy-MM-dd')`"" -Severity Warning -Component $comp
                            # getting updates of group and checking for archive group
                            try
                            {
                                [array]$ArchiveUpdateGroupObject = Get-WmiObject -Namespace "root\sms\site_$($SiteCode)" -ComputerName ($ProviderMachineName) -Query "Select CI_ID, LocalizedDisplayName, DateCreated from SMS_AuthorizationList where LocalizedDisplayName = '$($ArchiveGroupName)'" -ErrorAction Stop
                                [array]$updatesOfGroup = Get-CMSoftwareUpdate -UpdateGroupId ($_.CI_ID) -Fast -ErrorAction Stop | Where-Object {$_.IsExpired -eq $false}
                            }
                            catch
                            {
                                Write-ScriptLog -Message "        `"Get-CMSoftwareUpdate -UpdateGroupId ($($_.CI_ID))`" failed" -Severity Error -Component $comp
                                Write-ScriptLog -Message "        Or `"Get-WMIObject of SMS_AuthorizationList`" failed" -Severity Error -Component $comp
                                Write-ScriptLog -Message "        $($Error[0].Exception)" -Severity Error -Component $comp
                                $global:ErrorOutput = $true
                                Continue # with Foreach-Object and skip that one                                
                            }

                            Write-ScriptLog -Message "        Found $($updatesOfGroup.Count) updates in group" -Component $comp
                                
                            [bool]$addUpdatesFailed = $false
                            if($ArchiveUpdateGroupObject)
                            {
                                Write-ScriptLog -Message "        Found archive updategroup: `"$($ArchiveGroupName)`"" -Component $comp
                                try
                                {
                                    $null = $updatesOfGroup | Add-CMSoftwareUpdateToGroup -SoftwareUpdateGroupId ($ArchiveUpdateGroupObject.CI_ID) -ErrorAction Stop
                                }
                                Catch
                                {
                                    Write-ScriptLog -Message "        Failed to add updates to archive group" -Severity Error -Component $comp
                                    Write-ScriptLog -Message "        $($Error[0].Exception)" -Severity Error -Component $comp
                                    Write-ScriptLog -Message "        Skipping group" -Severity Warning -Component $comp
                                    $addUpdatesFailed = $true
                                    $global:ErrorOutput = $true                                  
                                }
                            }
                            else
                            {
                                Write-ScriptLog -Message "        No archive updategroup found. Need to create one: `"$($ArchiveGroupName)`"" -Component $comp
                                try
                                {
                                    $null = $updatesOfGroup | New-CMSoftwareUpdateGroup -Name "$ArchiveGroupName" -ErrorAction Stop
                                }
                                Catch
                                {
                                    Write-ScriptLog -Message "        Failed to create new archive group" -Severity Error -Component $comp
                                    Write-ScriptLog -Message "        $($Error[0].Exception)" -Severity Error -Component $comp  
                                    Write-ScriptLog -Message "        Skipping group" -Severity Warning -Component $comp
                                    $addUpdatesFailed = $true
                                    $global:ErrorOutput = $true 
                                }                                
                            }
                            #>
                            if (-NOT ($addUpdatesFailed))
                            {
                                Write-ScriptLog -Message "        Added $($updatesOfGroup.Count) updates to archive group" -Component $comp
                                Write-ScriptLog -Message "        Removing old group..." -Component $comp
                                try
                                {
                                    #Remove-CMSoftwareUpdateGroup -Name $($_.LocalizedDisplayName) -Force -ErrorAction Stop   
                                }
                                catch
                                {
                                    Write-ScriptLog -Message "        Failed to delete group `"$($_.LocalizedDisplayName)`"" -Severity Error -Component $comp
                                    Write-ScriptLog -Message "        $($Error[0].Exception)" -Severity Error -Component $comp  
                                    $global:ErrorOutput = $true                                     
                                }
                            }


                        }
                        else
                        {
                            Write-ScriptLog -Message "        `"$($_.LocalizedDisplayName)`" WOULD be archived. Creation Date: `"$(Get-Date($updateGroupDateCreated) -Format 'yyy-MM-dd')`"" -Severity Warning -Component $comp
                        } # end of: if ($Archive)

                    }
                    else
                    {
                        Write-ScriptLog -Message "        `"$($_.LocalizedDisplayName)`" skipping, not old enough. Creation Date: `"$(Get-Date($updateGroupDateCreated) -Format 'yyy-MM-dd')`"" -Component $comp
                    }  # end of: if(($updateGroupDateCreated).AddDays($maxUpdateGroupCreationDays) -lt (Get-Date))     
                }
            } 
            else
            {
                Write-ScriptLog -Message "        Skipping group, because of MinUpdateGroupsToKeep setting" -Component $comp   
            } # end of: if($UpdateGroupObjects.count -ge $MinUpdateGroupsToKeep -and $UpdateGroupObjects.count -gt 1)
        } # end of: if ($UpdateGroupObjects)
    } # end of: foreach ($UpdateGroup in $ArchiveUpdateGroupSettings.ArchiveUpdateGroupList)

}
#endregion

#region Stop-ScriptExec
Function Stop-ScriptExec
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [int]$exitCode
    )

    if ($stopwatch.IsRunning)
    {
        $stopwatch.Stop()
    }

    if ($global:lastLocation)
    {
        Set-Location -Path $global:lastLocation -ErrorAction SilentlyContinue
    }

    Write-ScriptLog -Message "Script runtime: $($stopwatch.Elapsed.TotalMinutes) total minutes"
    Write-ScriptLog -Message "Script end!"
    Write-ScriptLog -Message "Will stop script with exitcode: $exitCode"
    exit $exitCode 

}
#endregion


#region MAIN SCRIPT
#-----------------------------------------------------------------------------------------
Rollover-Logfile -Logfile $LogFile -MaxFileSizeKB 2048

$global:stopwatch = New-Object System.Diagnostics.Stopwatch
$stopwatch.Start()
Write-ScriptLog -Message "    "
Write-ScriptLog -Message "Script $Component started"
Write-ScriptLog -Message "Scriptversion: $ScriptVersion"

#region Check offset days and calculate if script if allowed to run or not
if ($UseOffsetDays)
{
    Write-ScriptLog -Message "The script is set to use $OffsetDays offset days based on the 2nd Tuesday! Will calculate date..."
    $currentDateString = (Get-Date -Format "yyyy-MM-dd").ToString()
    $calculatedOffsetDate = (Find-DayOfWeek -Weekday Tuesday -Week 2 -Time '23:00') # find the 2nd Tuesday and add offset days to it
    $calculatedOffsetDate = (Get-date($calculatedOffsetDate)).AddDays($OffsetDays)
    $calculatedOffsetDate = (Get-Date($calculatedOffsetDate) -Format "yyyy-MM-dd")

    if ($currentDateString -eq $calculatedOffsetDate)
    {
        Write-ScriptLog -Message "Calculated offset date `"$calculatedOffsetDate`" matches with the current date `"$currentDateString`". Will proceed with script!"
    }
    else
    {
        Write-ScriptLog -Message "Calculated offset date `"$calculatedOffsetDate`" does not match with the current date `"$currentDateString`"" -Severity Warning 
        Stop-ScriptExec -exitCode 0
    }
}
#endregion

$StartDate = Find-DayOfWeek -Weekday Tuesday -week 2 -Time "22:00" # time is irrelevant in that case, but a requirement for the function
Write-ScriptLog -Message "Calculated the second tuesday of the month: $(Get-Date($StartDate) -format u)"

#region read def file
# if the script runs in deploy mode, a -ScheduleDefinitionFile has to be specified
if (-NOT ($ScheduleDefinitionFile))
{
    if ($Deploy)
    {   
        Write-ScriptLog -Message "Script is set to deploy to collections"
        Write-ScriptLog -Message "No definition file specified with parameter -ScheduleDefinitionFile" -Severity Error 
        Stop-ScriptExec -exitCode 1
    }
    else 
    {
        # let the user running the script decide which file to use
        Write-ScriptLog -Message "No definition file specified with parameter -ScheduleDefinitionFile"
        Write-ScriptLog -Message "Let user choose a file via Out-GridView..." 
        $ScheduleDefinitionFileObject = Get-ChildItem (Split-Path -path $PSCommandPath) -Filter '*.json' | Select-Object Name, Length, LastWriteTime, FullName | Out-GridView -Title 'Choose a JSON configfile' -OutputMode Single
        if (-NOT ($ScheduleDefinitionFileObject))
        {
            Write-ScriptLog -Message "No definition file selected" -Severity Warning
            Stop-ScriptExec -exitCode 0         
        }
    }
}

Write-ScriptLog -Message "DefinitionFile to load: $($ScheduleDefinitionFileObject.Name)"
try
{ 
    $schedules = (Get-Content -Path ($ScheduleDefinitionFileObject.FullName) -ErrorAction Stop) -join "`n" | ConvertFrom-Json -ErrorAction Stop
}
Catch
{
    Write-ScriptLog -Message "Could not load JSON definition file!" -Severity Error 
    Write-ScriptLog -Message "$($Error[0].Exception)" -Severity Error 
    Stop-ScriptExec -exitCode 1 
}
#endregion

#region Check SCCM sitecode
Write-ScriptLog -Message "LOAD ConfigMgr data"
$ProviderInfo = Get-SCCMSiteInfo
if (-not $ProviderInfo)
{
    Write-ScriptLog -Message "Could not get the ConfigMgr SiteCode!" -Severity Error 
    Stop-ScriptExec -exitCode 1
}
else
{
    $ProviderMachineName = $ProviderInfo.Machine
    $SiteCode = $ProviderInfo.SiteCode
    Write-ScriptLog -Message "    ConfigMgr SiteCode: $SiteCode"
    Write-ScriptLog -Message "    ConfigMgr ProviderMachineName: $ProviderMachineName"    
}
#endregion

#region Load SCCM cmdlets
try
{
    # Import the ConfigurationManager.psd1 module 
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" -ErrorAction Stop  
    # Connect to the site drive if it is not already present
    if (-NOT (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) 
    {
        $null = New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName -ErrorAction Stop
    }

    # Set the current location to be the site code.
    $global:lastLocation = (Get-Location -ErrorAction SilentlyContinue).Path 
    $null = Set-Location -Path "$($SiteCode):" -ErrorAction Stop
    Write-ScriptLog -Message "    Path: `"$($SiteCode):`""
}
catch
{
    Write-ScriptLog -Message "Could not load ConfigMgr CmdLets" -Severity Error 
    Write-ScriptLog -Message "$($Error[0].Exception)" -Severity Error 
    Stop-ScriptExec -exitCode 1 
}
Write-ScriptLog -Message "    ConfigMgr CmdLets loaded!"
#endregion


#region read update group settings
$deleteUpdateGroupSettings = $schedules.ADRSchedules.DeleteUpdateGroups
$archiveUpdateGroupSettings = $schedules.ADRSchedules.ArchiveUpdateGroups

if (-NOT($deleteUpdateGroupSettings -and $archiveUpdateGroupSettings))
{
    Write-ScriptLog -Message "Could not get Delete- or ArchiveUpgradeGroups section from definitionfile!" -Severity Error 
    Stop-ScriptExec -exitCode 1 
}

Write-ScriptLog -Message "DELETE old UpdateGroups section is set to:"
Write-ScriptLog -Message "    DeleteUpdateGroups: $($deleteUpdateGroupSettings.DeleteUpdateGroups)"
Write-ScriptLog -Message "    MinUpdateGroupsToKeep: $($deleteUpdateGroupSettings.MinUpdateGroupsToKeep)"
Write-ScriptLog -Message "    MaxUpdateGroupCreationDays: $($deleteUpdateGroupSettings.MaxUpdateGroupCreationDays)"
Write-ScriptLog -Message "    Count of groups: $($deleteUpdateGroupSettings.DeleteUpdateGroupList.Count)"

Write-ScriptLog -Message "ARCHIVE old UpdateGroups section is set to:"
Write-ScriptLog -Message "    ArchiveUpdateGroups: $($archiveUpdateGroupSettings.ArchiveUpdateGroups)"
Write-ScriptLog -Message "    MinUpdateGroupsToKeep: $($archiveUpdateGroupSettings.MinUpdateGroupsToKeep)"
Write-ScriptLog -Message "    MaxUpdateGroupCreationDays: $($archiveUpdateGroupSettings.MaxUpdateGroupCreationDays)"
Write-ScriptLog -Message "    Count of groups: $($archiveUpdateGroupSettings.ArchiveUpdateGroupList.Count)"
#endregion


#region validate delete and archive groups
Write-ScriptLog -Message "VALIDATE UpdateGroup lists..."
[bool]$duplicateGroupFound = $false
$deleteUpdateGroupSettings.DeleteUpdateGroupList | ForEach-Object {

    if ($_ -in $archiveUpdateGroupSettings.ArchiveUpdateGroupList)
    {
        Write-ScriptLog -Message "    UpdateGroup `"$_`" is part of both group lists." -Severity Warning    
        $duplicateGroupFound = $true
    }
}
if ($duplicateGroupFound)
{
    Write-ScriptLog -Message "    VALIDAT failed. Will skip group delete/archive actions" -Severity Warning
    $global:ErrorOutput = $true
}
else
{
    Write-ScriptLog -Message "    VALIDATE succeeded"

    # start delete process
    if (($deleteUpdateGroupSettings.DeleteUpdateGroups) -eq $true)
    {
        if ($DeleteOrArchiveGroups)
        {
            Delete-ObsoleteUpdateGroups -DeleteUpdateGroupSettings $deleteUpdateGroupSettings -SiteCode $SiteCode -ProviderMachineName $ProviderMachineName -Delete
        }
        else
        {
            Delete-ObsoleteUpdateGroups -DeleteUpdateGroupSettings $deleteUpdateGroupSettings -SiteCode $SiteCode -ProviderMachineName $ProviderMachineName
        }
    }


    # start archive process
    if (($archiveUpdateGroupSettings.ArchiveUpdateGroups) -eq $true)
    {
        if ($DeleteOrArchiveGroups)
        {
            Archive-ObsoleteUpdateGroups -ArchiveUpdateGroupSettings $archiveUpdateGroupSettings -SiteCode $SiteCode -ProviderMachineName $ProviderMachineName -Archive
        }
        else
        {
            Archive-ObsoleteUpdateGroups -ArchiveUpdateGroupSettings $archiveUpdateGroupSettings -SiteCode $SiteCode -ProviderMachineName $ProviderMachineName
        }
    }
}

#enregion

#region  create schedule times
# this section will convert the intiger values to actual datetimes based in the startdate. So 7 days from the 2nd Tuesday are differnt than 7 days from the first day of the month
try
{ 
    $schedulesWithDate = [string]::Empty
    if (-NOT ($Deploy))
    {
        # output schedules if they should not be deployed automatically
        Write-ScriptLog -Message "GET SCHEDULETIMES:"
        Write-ScriptLog -Message "    Converting configuration entries into actual datetime values..."
        [array]$propertyList  = $null
        $propertyList += 'CollectionName'
        $propertyList += 'UpdateGroups'
        $propertyList += 'SetCMSoftwareUpdateDeploymentEnable'
        $propertyList += 'StartDateTime'
        $propertyList += 'DeadlineDatetime'
        $propertyList += 'StartMonth'
        $propertyList += 'StartDayInMonth'
        $propertyList += 'StartWeekInMonth'
        $propertyList += 'StartWeekdayInMonth'
        $propertyList += 'StartDays'
        $propertyList += 'DeadlineDays'
        $propertyList += 'StartTime'
        $propertyList += 'DeadlineTime'
        $propertyList += 'RemoveUpdateDeploymentsFirst'
        $propertyList += 'NewCMSoftwareUpdateDeploymentAllowRestart'
        $propertyList += 'NewCMSoftwareUpdateDeploymentDeploymentType'
        $propertyList += 'NewCMSoftwareUpdateDeploymentDownloadFromMicrosoftUpdate'
        $propertyList += 'NewCMSoftwareUpdateDeploymentProtectedType'
        $propertyList += 'NewCMSoftwareUpdateDeploymentRequirePostRebootFullScan'
        $propertyList += 'NewCMSoftwareUpdateDeploymentRestartServer'
        $propertyList += 'NewCMSoftwareUpdateDeploymentRestartWorkstation'
        $propertyList += 'NewCMSoftwareUpdateDeploymentSendWakeupPacket'
        $propertyList += 'NewCMSoftwareUpdateDeploymentSoftwareInstallation'
        $propertyList += 'NewCMSoftwareUpdateDeploymentTimeBasedOn'
        $propertyList += 'NewCMSoftwareUpdateDeploymentUnprotectedType'
        $propertyList += 'NewCMSoftwareUpdateDeploymentUseBranchCache'
        $propertyList += 'NewCMSoftwareUpdateDeploymentUserNotification'
        $propertyList += 'NewCMSoftwareUpdateDeploymentVerbosityLevel'

        $schedulesWithDate = $schedules.ADRSchedules.ADRs | Get-ADRScheduleTimes | Select-Object -Property $propertyList | Out-GridView -Title "Schedule Settings" -PassThru

        if (-NOT $schedulesWithDate) # nothing selected, nothing to do
        {
            Write-ScriptLog -Message "No collection selected. Will stop script" -Severity Warning
            $stopwatch.Stop()
            Write-ScriptLog -Message "Script runtime: $($stopwatch.Elapsed.TotalMinutes) total minutes"
            Stop-ScriptExec -exitCode 0 
        }
    }
    else
    {
        Write-ScriptLog -Message "Script is set to deploy to collections"
        Write-ScriptLog -Message "GET SCHEDULETIMES:"
        Write-ScriptLog -Message "    Converting configuration entries into actual datetime values..."
        $schedulesWithDate = $schedules.ADRSchedules.ADRs | Get-ADRScheduleTimes
    }
}
catch
{
    Write-ScriptLog -Message "Could not create schedule times!" -Severity Error 
    Write-ScriptLog -Message "$($Error[0].Exception)" -Severity Error 
    Stop-ScriptExec -exitCode 1  
}



#region create deployments
if ($schedulesWithDate)
{
    $schedulesWithDate | New-SCCMSoftwareUpdateDeployment -CollectionCount ($schedulesWithDate.CollectionName.count) -SiteCode $SiteCode -ProviderMachineName $ProviderMachineName
}
else 
{
    Write-ScriptLog -Message "No schedules found or selected"
}

#endregion

# return error to pass to the scheduled task for monitoring purposes
if ($global:ErrorOutput)
{
    Write-ScriptLog -Message "Error occured, check log file!" -Severity Warning 
    Stop-ScriptExec -exitCode 1 
}
else
{
    Stop-ScriptExec -exitCode 0
}
#-------------------------------------------------------------------------------------------
#endregion


