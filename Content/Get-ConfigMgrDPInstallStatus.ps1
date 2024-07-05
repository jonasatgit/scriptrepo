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
<#
.Synopsis
    Script to monitor ConfigMgr DO installations and content transfer state
.DESCRIPTION
    Script to monitor ConfigMgr DO installations and content transfer state
    In and output needs three folders.
    A queue folder to read which DP to monitor
    A failure folder to be able to move logfiles of failed DP installations to it
    A success folder to be able to move logfiles of successful DP installations to it
    The script can also send status mails per DP
   
.EXAMPLE
    Get-ConfigMgrDPInstallStatus.ps1
    Will run the script with default settings
 
.PARAMETER ProviderServeName
    The name of the provider server. Default is the local computername
 
.PARAMETER QueueFolder
    The folder where the logfiles to be monitored are located. Default is E:\CUSTOM\DPInstallTest\Queue
 
.PARAMETER SuccessFolder
    The folder where the logfiles of successful DP installations are moved to. Default is E:\CUSTOM\DPInstallTest\Success
 
.PARAMETER FailureFolder
    The folder where the logfiles of failed DP installations are moved to. Default is E:\CUSTOM\DPInstallTest\Failure
 
.PARAMETER MoveFiles
    If set to $true, the script will move the logfiles to the success or failure folder. Default is $true
    If set to $false, the script will not move the logfiles to the success or failure folder.
 
.PARAMETER SendMail
    If set to $true, the script will send a mail in case of success or failure. Default is $true
    If set to $false, the script will not send a mail in case of success or failure.
 
.PARAMETER Mailserver
    The mailserver to use for sending mails. Default is mail.contoso.local
 
.PARAMETER MailToInCaseOfSuccess
    Mail address list to send a mail in case of success.
 
.PARAMETER MailToInCaseOfFailure
    Mail address list to send a mail in case of failure.
 
.PARAMETER MailFrom
    Mail address to send the mail from.
 
.PARAMETER StatusMessageDaySearchLimit
    How many days we should look for status messages. Just to further decrease the result. Default is 70
 
.PARAMETER MaxCheckTimeInDays
    How many days a DP can still be in installing state until we assume a problem with a DP. Default is 2
 
#>
[CmdletBinding()]
param
(
    [string]$ProviderServeName = $env:COMPUTERNAME,
    [string]$QueueFolder = 'E:\CUSTOM\DPInstallTest\Queue',
    [string]$SuccessFolder = 'E:\CUSTOM\DPInstallTest\Success',
    [string]$FailureFolder = 'E:\CUSTOM\DPInstallTest\Failure',
    [bool]$MoveFiles = $true,
    [bool]$SendMail = $true,
    [string]$Mailserver = 'mail.contoso.local',
    [string[]]$MailToInCaseOfSuccess = ('test@contoso.local'),
    [string[]]$MailToInCaseOfFailure = ('test@contoso.local'),
    [string]$MailFrom = 'test@contoso.local',
    [int]$StatusMessageDaySearchLimit = 70, # How many days we should look for status messages. Just to further decrease the result
    [int]$MaxCheckTimeInDays = 2 # How many days a DP can still be in installing state until we assume a problem with a DP
)
[string]$versionOfScript = '20240628'
[string]$global:logFile = "{0}\{1}.log" -f $PSScriptRoot, (($MyInvocation.MyCommand.Name) -replace '.ps1','')
[string]$global:Component = (($MyInvocation.MyCommand.Name) -replace '.ps1','')
 
#region Write-CMTraceLog
<#
.Synopsis
    Will write cmtrace readable log files.
.EXAMPLE
    Write-CMTraceLog -Message "Starting script" -LogFile "C:\temp\logfile.log"
.EXAMPLE
    Write-CMTraceLog -Message "Starting script" -LogFile "C:\temp\logfile.log" -LogType LogOnly
.EXAMPLE
    Write-CMTraceLog -Message "Script has failed" -LogFile "C:\temp\logfile.log" -EventlogName "Application" -LogType 'LogAndEventlog' -Type Error
.PARAMETER Message
    Text to be logged
.PARAMETER Type
    The type of message to be logged. Either Info, Warning or Error
.PARAMETER LogFile
    Path to the logfile
.PARAMETER Component
    The name of the component logging the message
.PARAMETER EventlogName
    Either "Application" or "System". Application is default.
.PARAMETER LogType
    One of three possible strings: "LogOnly","EventlogOnly","LogAndEventlog"
#>
Function Write-CMTraceLog
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
        [String]$Type = 'Information',
        #The Eventlog Name
        [parameter(Mandatory=$False)]
        [ValidateSet("Application","System")]
        [String]$EventlogName="Application",
        #Type of log to write
        [parameter(Mandatory=$false)]
        [ValidateSet("LogOnly","EventlogOnly","LogAndEventlog")]
        [string]$LogType = 'LogOnly'
    )
    [single]$EventID=10
    switch ($Type)
        {
            "Information" {$EventID=10}
            "Warning" {$EventID=20}
            "Error" {$EventID=30}
        }
    if (($LogType -ieq "EventlogOnly") -or ($LogType -ieq "LogAndEventlog"))
    {
        # always use the global component name for eventlog and nothing else
        # check if eventsource exists otherwise create eventsource
        if ([System.Diagnostics.EventLog]::SourceExists($global:Component) -eq $false)
        {
            try
            {
                [System.Diagnostics.EventLog]::CreateEventSource($global:Component, $EventlogName )
            }
            catch
            {
                exit 2
            }
         }
        Write-EventLog -LogName $EventlogName -Source $global:Component -EntryType $Type -EventID $EventID -Message $Message
    }
    if (($LogType -ieq "LogOnly") -or ($LogType -ieq "LogAndEventlog"))
    {
        # save severity in single for cmtrace severity
        [single]$cmSeverity=1
        switch ($Type)
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
}
#endregion
 
#region Rollover-Logfile
<#
.Synopsis
    Function Rollover-Logfile
 
.DESCRIPTION
    Will rename a logfile from ".log" to ".lo_".
    Old ".lo_" files will be deleted
 
.PARAMETER MaxFileSizeKB
    Maximum file size in KB in order to determine if a logfile needs to be rolled over or not.
    Default value is 1024 KB.
 
.EXAMPLE
    Rollover-Logfile -Logfile "C:\Windows\Temp\logfile.log" -MaxFileSizeKB 2048
#>
Function Rollover-Logfile
{
#Validate path and write log or eventlog
[CmdletBinding()]
Param(
      #Path to test
      [parameter(Mandatory=$True)]
      [string]$Logfile,
     
      #max Size in KB
      [parameter(Mandatory=$False)]
      [int]$MaxFileSizeKB = 1024
    )
 
    if (Test-Path $Logfile)
    {
        $getLogfile = Get-Item $Logfile
        if ($getLogfile.PSIsContainer)
        {
            # Just a folder. Skip actions
        }
        else
        {
            $logfileSize = $getLogfile.Length/1024
            $newName = "{0}.lo_" -f $getLogfile.BaseName
            $newLogFile = "{0}\{1}" -f ($getLogfile.FullName | Split-Path -Parent), $newName
 
            if ($logfileSize -gt $MaxFileSizeKB)
            {
                if(Test-Path $newLogFile)
                {
                    #need to delete old file first
                    Remove-Item -Path $newLogFile -Force -ErrorAction SilentlyContinue
                }
                Rename-Item -Path ($getLogfile.FullName) -NewName $newName -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
#-----------------------------------------
#endregion
 
 
#region hash tables
# Possible package status states: https://learn.microsoft.com/en-us/mem/configmgr/develop/reference/core/servers/configure/sms_packagestatusdistpointssummarizer-server-wmi-class
$stateHashTable = @{
    0 = 'INSTALLED'
    1 = 'INSTALL_PENDING'
    2 = 'INSTALL_RETRYING'
    3 = 'INSTALL_FAILED'
    4 = 'REMOVAL_PENDING'
    5 = 'REMOVAL_RETRYING'
    6 = 'REMOVAL_FAILED'
    7 = 'CONTENT_UPDATING'
    8 = 'CONTENT_MONITORING'
}
 
# Possible types: https://learn.microsoft.com/en-us/mem/configmgr/develop/reference/core/servers/configure/sms_packagestatusdistpointssummarizer-server-wmi-class
$pkgTypeHashTable = @{
    0 = 'PKG_TYPE_REGULAR'
    3 = 'PKG_TYPE_DRIVER'
    4 = 'PKG_TYPE_TASK_SEQUENCE'
    5 = 'PKG_TYPE_SWUPDATES'
    6 = 'PKG_TYPE_DEVICE_SETTING'
    7 = 'PKG_TYPE_VIRTUAL_APP'
    8 = 'PKG_CONTENT_PACKAGE'
    257 = 'PKG_TYPE_IMAGE'
    258 = 'PKG_TYPE_BOOTIMAGE'
    259 = 'PKG_TYPE_OSINSTALLIMAGE'
}
 
 
# Possible message states
$messageStateHash = @{
    1 = 'SUCCESS'
    2 = 'PENDING'
    3 = 'ERROR'
}
#endregion
 
Rollover-Logfile -Logfile $global:logFile
 
Write-CMTraceLog -Message " "
Write-CMTraceLog -Message "Start of script. Version: `"$versionOfScript`""
 
# Lets check if the folders exists first
If (-not (Test-Path -Path $QueueFolder))
{
    Write-CMTraceLog -Message "Queue folder does not exist: `"$QueueFolder`"" -Type Error
    exit 1
}
If (-not (Test-Path -Path $SuccessFolder))
{
    Write-CMTraceLog -Message "Success folder does not exist: `"$SuccessFolder`"" -Type Error
    exit 1
}
If (-not (Test-Path -Path $FailureFolder))
{
    Write-CMTraceLog -Message "Failure folder does not exist: `"$FailureFolder`"" -Type Error
    exit 1
}
 
 
# Getting SMS provider and sitecode
$ProviderInfo = Get-WmiObject -ComputerName $providerServeName -Namespace "root\sms" -query "select SiteCode, Machine from SMS_ProviderLocation where ProviderForLocalSite = True" -ErrorAction Stop
$ProviderInfo = $ProviderInfo | Select-Object SiteCode, Machine -First 1
Write-CMTraceLog -Message "Found sitecode: $($ProviderInfo.SiteCode) and providerserver: $($ProviderInfo.Machine)"
# Date string in the format of yyyyMMdd minus $statusMessageDaySearchLimit days to limit status message query
$dateString = Get-date ((Get-Date).AddDays(-$statusMessageDaySearchLimit)) -Format 'yyyyMMdd'
[array]$logFiles = Get-ChildItem -Path $queueFolder -Filter '*.log'
Write-CMTraceLog -Message "Found $($logFiles.count) logfiles to work with"
if ($logFiles)
{
    # Looking for a message like this:
    # Information,Milestone,P02,1/31/2024 1:40:23 AM,CM02.CONTOSO.LOCAL,SMS_DISTRIBUTION_MANAGER,2399,Successfully completed the installation or upgrade of the distribution point on computer "["Display=\\dp01.contoso.local\"]MSWNET:["SMS_SITE=P02"]\\dp01.contoso.local\".
    $wmiQuery = "select * from SMS_StatusMessage as ME inner join SMS_StatMsgAttributes as AT on AT.RecordID = ME.RecordID where ME.Component = 'SMS_DISTRIBUTION_MANAGER' and ME.MessageID = 2399 and ME.Time >= '$($dateString)'"
    [array]$queryResult = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wmiQuery
    Write-CMTraceLog -Message "Found: $($queryResult.count) DP install success message/s"
    # Store in extra variable and add dummy to be able to imatch with result
    $dpNameList = @('dummyvalue1')
    $dpNameList += 'dummyvalue2'
    $dpNameList += $queryResult.AT.AttributeValue
    foreach($log in $logFiles)
    {
        $dpContentList = [System.Collections.Generic.List[pscustomobject]]::new()
        $maxTimeoutReached = $false
        Write-CMTraceLog -Message "------------"
        Write-CMTraceLog -Message "Logname: `"$($log.Name)`""
        $regexResult = [regex]::Matches($log, '(?<dpName>.*)_(?<DateTime>\d*_\d*_\d*_\d*_\d*_\d*)')
        $dpToCheck = ($regexResult.Groups.Where({$_.Name -eq 'dpName'})).Value
        $logDateTimeString = ($regexResult.Groups.Where({$_.Name -eq 'DateTime'})).Value
        try
        {
            $logDateTime = $null
            $logDateTime = [Datetime]::ParseExact($logDateTimeString, 'dd_MM_yyyy_HH_mm_ss', $null)
        }
        Catch
        {
            Write-CMTraceLog -Message "$dpToCheck not able to parse datetime. $($_)" -Type Warning
            $maxTimeoutReached = $true
        }
        if ($logDateTime)
        {
            $timespan = New-TimeSpan -Start $logDateTime -End (Get-Date)
            if ($timespan.TotalDays -gt $maxCheckTimeInDays)
            {
                Write-CMTraceLog -Message "$dpToCheck logtime over limit of $maxCheckTimeInDays days. Will move file to failure in case we find no install message or successful content distribution"
                $maxTimeoutReached = $true
            }
        }
        Write-CMTraceLog -Message "$dpToCheck is extracted DP name"
        Write-CMTraceLog -Message "$dpToCheck extracted datetime: $logDateTimeString"
 
        if ($dpNameList -imatch $dpToCheck)
        {
            # DP install seems to be done if we have a status message for the DP
            Write-CMTraceLog -Message "$dpToCheck DP installed successful"
 
            # Get list of assigned content to the DP
            [array]$dpNALPath = ($dpNameList -imatch $dpToCheck) -replace '\\', '\\' # we need to add some "\" for the WMI query to work
           
            Write-CMTraceLog -Message "$dpToCheck Getting list of assigned content for DP"
            $query = "select PackageID, Status, PackageType from SMS_DistributionPoint where ServerNALPath = '$($dpNALPath[0])'"
            [array]$contentAssignedToDP = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "Root\SMS\Site_$($ProviderInfo.SiteCode)" -Query $query
            Write-CMTraceLog -Message "$dpToCheck Getting list of contentent from status summarizer for DP"
            $query = "select PackageID, State from SMS_PackageStatusDistPointsSummarizer where ServerNALPath = '$($dpNALPath[0])'"
            [array]$contentFromStatusSummarizer = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "Root\SMS\Site_$($ProviderInfo.SiteCode)" -Query $query
            # create hashtable to be able to lookup fast
            $dpContentStatusSummarizerHash = @{}
            foreach($item in $contentFromStatusSummarizer)
            {
                if (-NOT $dpContentStatusSummarizerHash.ContainsKey($item.PackageID))
                {            
                    $dpContentStatusSummarizerHash[$item.PackageID] = if($stateHashTable.[int]($item.State)){$stateHashTable.[int]($item.State)}else{'UNKNOWN'}
                }
            }
 
            Write-CMTraceLog -Message "$dpToCheck Getting list of content status messages for DP"
            $query = "SELECT DPName, PackageID, MessageState FROM SMS_DPStatusDetails WHERE DPName = '$($dpToCheck)' and PackageID <> ''"
            [array]$dpContentMessageStatusDetails = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "Root\SMS\Site_$($ProviderInfo.SiteCode)" -Query $query
            # create hashtable to be able to lookup fast
            $dpContentStateMessageHash = @{}
            foreach($item in $dpContentMessageStatusDetails)
           {
                if (-NOT $dpContentStateMessageHash.ContainsKey($item.PackageID))
                {            
                    $dpContentStateMessageHash[$item.PackageID] = if($messageStateHash[[int]$item.MessageState]){$messageStateHash[[int]$item.MessageState]}else{'UNKNOWN'}
                }
            }
 
            Write-CMTraceLog -Message "$dpToCheck Getting overall DP status for DP"
            $query = "SELECT * FROM SMS_DPStatusInfo Where Name = '$($dpToCheck)'"
            [array]$smsDPStatusInfo = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "Root\SMS\Site_$($ProviderInfo.SiteCode)" -Query $query
  
            if($contentAssignedToDP.count -gt 0)
            {
                foreach($content in $contentAssignedToDP)
                {
              
                    # DP status message state
                    if($dpContentStateMessageHash[$content.PackageID])
                    {
                        $DPPackageStatusMessageState = $dpContentStateMessageHash[$content.PackageID]      
                    }
                    else
                    {
                        $DPPackageStatusMessageState = 'UNKNOWN'
                    }
                
                    # Summarizer state
                    if($dpContentStatusSummarizerHash[$content.PackageID])
                    {
                        $summarizerState = $dpContentStatusSummarizerHash[$content.PackageID]      
                    }
                    else
                    {
                        $summarizerState = 'UNKNOWN'
                    }
               
                    # Get DP Status Info. This is the class that results in the pie diagram for each DP in the configMgr console
                    if(($smsDPStatusInfo.NumberErrors -eq 0) -and ($smsDPStatusInfo.NumberInProgress -eq 0) -and ($smsDPStatusInfo.NumberUnknown -eq 0))
                    {
                        $DPStatusInfoState = 'SUCCESS'
                    }
                    else
                    {
                        $DPStatusInfoState = 'WARNING'   
                    }
                            
                         
                    # create temp object  
                    $tmpObj = [pscustomobject][ordered]@{
                        Servername = $dpToCheck
                        PackageID= $content.PackageID
                        Type = $pkgTypeHashTable.[int]($content.PackageType)
                        AssignedToDPState = $stateHashTable.[int]($content.Status)
                        SendToDPState = $summarizerState
                        SuccessMessageFromDPState = $DPPackageStatusMessageState
                        DPStatusInfoState = $DPStatusInfoState
                        OverallState = 'SUCCESS'
                    }
              
                    # add overall state to list
                    if($tmpObj.AssignedToDPState -ine 'Installed')
                    {
                        $tmpObj.OverallState = 'FAILED'
                    }
 
                    if($tmpObj.SendToDPState -ine 'Installed')
                    {
                        $tmpObj.OverallState = 'FAILED'
                    }              
                
                    if($tmpObj.SuccessMessageFromDPState -ine 'Success')
                    {
                        $tmpObj.OverallState = 'FAILED'
                    }
               
                    # If the main DP state is okay, we can assume that all content has been transferred but some states are not correct yet
                    # That should also be fixed with a re-distribution, but is not a huge problem
                    if(($tmpObj.DPStatusInfoState -ieq 'SUCCESS') -and ($tmpObj.OverallState -ieq 'FAILED'))
                    {
                        $tmpObj.OverallState = 'WARNING'
                    }
                    # add item to list
                    $dpContentList.add($tmpObj)             
                }     
            }
 
            $dpSendStats = $dpContentList.SendToDPState | Group-Object | Select-Object Name, Count
            $dpOverallStats = $dpContentList.OverallState | Group-Object | Select-Object Name, Count
            $successCounter = $dpOverallStats | Where-Object {$_.Name -ieq 'SUCCESS'} | Select-Object Count
 
            Write-CMTraceLog -Message "$dpToCheck NumberAssigned $($contentAssignedToDP.count), NumberInstalled $($successCounter.count), NumberErrors $($smsDPStatusInfo.NumberErrors), NumberInProgress $($smsDPStatusInfo.NumberInProgress), NumberUnknown $($smsDPStatusInfo.NumberUnknown)"
            $mailBody = "DP: $dpToCheck<br>NumberAssigned: $($contentAssignedToDP.count)<br>NumberInstalled: $($successCounter.count)<br>NumberErrors: $($smsDPStatusInfo.NumberErrors)<br>NumberInProgress: $($smsDPStatusInfo.NumberInProgress)<br>NumberUnknown: $($smsDPStatusInfo.NumberUnknown)"
 
            # Compare installed versus assigned
            if ($successCounter.count -eq $contentAssignedToDP.count)
            {
                # All assigned content seems to be installed
                Write-CMTraceLog -Message "$dpToCheck all assigned content distributed. Will move file to success folder"
                If ($moveFiles){Move-Item -Path ($log.FullName) -Destination $successFolder -Force}
                If ($sendMail)
                {
                    $paramSplatting = @{
                        From = $mailFrom
                        To = $MailToInCaseOfSuccess
                        SmtpServer = $mailserver
                        Subject = "$dpToCheck DP install successful. Will move file to success folder"
                        Body = $mailBody
                    }
 
                    try
                    {
                        Send-MailMessage @paramSplatting -BodyAsHtml -ErrorAction Stop   
                    }
                    catch
                    {
                        Write-CMTraceLog -Message "Error sending mail: $($_)" -Type Warning
                    }                   
                }
            }
            else
            {
                # Looks like content is not there yet
                # If we are over the timeout limit, we need to stop the script
                if ($maxTimeoutReached)
                {
                    Write-CMTraceLog -Message "$dpToCheck Content still not there yet. Max timeout reached. Will move file to failure" -Type Warning
                    If ($moveFiles){Move-Item -Path ($log.FullName) -Destination $failureFolder -Force}
                    If ($sendMail)
                    {
                        $paramSplatting = @{
                            From = $mailFrom
                            To = $MailToInCaseOfFailure
                            SmtpServer = $mailserver
                            Subject = "$dpToCheck Content still not there yet. Max timeout reached. Will move file to failure"
                            Body = $mailBody
                        }
 
                        try
                        {
                            Send-MailMessage @paramSplatting -BodyAsHtml -Priority High -ErrorAction Stop   
                        }
                        catch
                        {
                            Write-CMTraceLog -Message "Error sending mail: $($_)" -Type Warning
                        }
                    }             
                }
                else
                {
                    # If nothing is in progress we should not wait any longer and fail
                    # We might need to test if the script starttime and DP install time is too close to actually start contentn ditribution
                    if ($smsDPStatusInfo.NumberInProgress -eq 0)
                    {
                        Write-CMTraceLog -Message "$dpToCheck content still not there yet. Nothing in progress anymore. We need to assume a problem with the DP. Will move file to failure" -Type Warning
                        If ($moveFiles){Move-Item -Path ($log.FullName) -Destination $failureFolder -Force}
                        If ($sendMail)
                        {
                            $paramSplatting = @{
                                From = $mailFrom
                                To = $MailToInCaseOfFailure
                                SmtpServer = $mailserver
                                Subject = "$dpToCheck content still not there yet. Nothing in progress anymore. We need to assume a problem with the DP. Will move file to failure"
                                Body = $mailBody
                            }
 
                            try
                            {
                                Send-MailMessage @paramSplatting -BodyAsHtml -Priority High -ErrorAction Stop   
                            }
                            catch
                            {
                                Write-CMTraceLog -Message "Error sending mail: $($_)" -Type Warning
                            }
                    }            
                    }
                    else
                    {
                        Write-CMTraceLog -Message "$dpToCheck Content still in progress. Will check again with next script run"
                    }                 
                }
            }
        }
        else
        {
            if ($maxTimeoutReached)
            {
                Write-CMTraceLog -Message "$dpToCheck No install success found. Max timeout reached. Will move file to failure" -Type Warning
                If ($moveFiles){Move-Item -Path ($log.FullName) -Destination $failureFolder -Force}
                If ($sendMail)
                {
                    $paramSplatting = @{
                        From = $mailFrom
                        To = $MailToInCaseOfFailure
                        SmtpServer = $mailserver
                        Subject = "$dpToCheck No install success found. Max timeout reached. Will move file to failure"
                        Body = $mailBody
                    }
                   
                    try
                    {
                        Send-MailMessage @paramSplatting -BodyAsHtml -Priority High -ErrorAction Stop   
                    }
                    catch
                    {
                        Write-CMTraceLog -Message "Error sending mail: $($_)" -Type Warning
                    }
                }
            }
            else
            {
                Write-CMTraceLog -Message "$dpToCheck No install success found so far. Will be checked again next time the script runs"
            }
        }
    }
}
else
{
    Write-CMTraceLog -Message "Nothing found in queue folder: `"$queueFolder`""
}
Write-CMTraceLog -Message "End of script"