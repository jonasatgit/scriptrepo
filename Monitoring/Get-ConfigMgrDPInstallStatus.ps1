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
 
#>
[CmdletBinding()]
param
(
    [string]$providerServeName = $env:COMPUTERNAME,
    [string]$queueFolder = 'E:\CUSTOM\DPInstallTest\Queue',
    [string]$successFolder = 'E:\CUSTOM\DPInstallTest\Success',
    [string]$failureFolder = 'E:\CUSTOM\DPInstallTest\Failure',
    [bool]$moveFiles = $true,
    [bool]$sendMail = $true,
    [string]$mailserver = 'mail.contoso.local',
    [string]$mailTo = 'admin@contoso.local',
    [string]$mailFrom = 'admin@contoso.local',
    [int]$statusMessageDaySearchLimit = 70, # How many days we should look for status messages. Just to further decrease the result
    [int]$maxCheckTimeInDays = 2 # How many days a DP can still be in installing state until we assume a problem with a DP
)
 
 
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
 
Write-CMTraceLog -Message " "
Write-CMTraceLog -Message "Start of script "
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
        $maxTimeoutReached = $false
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
            $wmiQuery = "SELECT PackageID FROM SMS_DPContentInfo WHERE NALPath = '$($dpNALPath[0])'" # Need to use the first item of the array in case we find multiple install messages for one DP in given timeframe
            [array]$smsDPContentInfo = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wmiQuery
            $assignedContentCount = $smsDPContentInfo.Count
            $assignedContentCount++ # we need to add one package for the hidden default package
  
            # Now getting the overall DP status to be able to check for missing content
            $wmiQuery = "SELECT * FROM SMS_DPStatusInfo Where Name = '$($dpToCheck)'"
            [array]$smsDPStatusInfo = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wmiQuery
            Write-CMTraceLog -Message "$dpToCheck NumberAssigned $($assignedContentCount), NumberInstalled $($smsDPStatusInfo.NumberInstalled), NumberErrors $($smsDPStatusInfo.NumberErrors), NumberInProgress $($smsDPStatusInfo.NumberInProgress), NumberUnknown $($smsDPStatusInfo.NumberUnknown)"
            $mailBody = "DP: $dpToCheck<br>NumberAssigned: $($assignedContentCount)<br>NumberInstalled: $($smsDPStatusInfo.NumberInstalled)<br>NumberErrors: $($smsDPStatusInfo.NumberErrors)<br>NumberInProgress: $($smsDPStatusInfo.NumberInProgress)<br>NumberUnknown: $($smsDPStatusInfo.NumberUnknown)"
 
            # Compare installed versus assigned
            if ($smsDPStatusInfo.NumberInstalled -eq $assignedContentCount)
            {
                # All assigned content seems to be installed
                Write-CMTraceLog -Message "$dpToCheck all assigned content distributed. Will move file to success folder"
                If ($moveFiles){Move-Item -Path ($log.FullName) -Destination $successFolder -Force}
                If ($sendMail)
                {
                    $paramSplatting = @{
                        From = $mailFrom
                        To = $mailTo
                        SmtpServer = $mailserver
                        Subject = "$dpToCheck DP install successful. Will move file to success folder"
                        Body = $mailBody
                   
                    }
                    Send-MailMessage @paramSplatting -BodyAsHtml
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
                            To = $mailTo
                            SmtpServer = $mailserver
                            Subject = "$dpToCheck Content still not there yet. Max timeout reached. Will move file to failure"
                            Body = $mailBody
                   
                        }
                        Send-MailMessage @paramSplatting -BodyAsHtml -Priority High
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
                                To = $mailTo
                                SmtpServer = $mailserver
                                Subject = "$dpToCheck content still not there yet. Nothing in progress anymore. We need to assume a problem with the DP. Will move file to failure"
                                Body = $mailBody
                   
                            }
                            Send-MailMessage @paramSplatting -BodyAsHtml -Priority High
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
                If ($sendMail){Send-MailMessage -From $mailFrom -SmtpServer $mailserver -Subject "$dpToCheck No install success found. Max timeout reached. Will move file to failure" -To $mailTo -Priority High}
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
