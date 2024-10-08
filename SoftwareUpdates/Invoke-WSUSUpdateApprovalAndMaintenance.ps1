<#
.Synopsis
    Script to approve Defender Definition Updates directly in WSUS, cleanup old WSUS files and delete declined updates

.DESCRIPTION
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
 
    Script to approve Defender Definition Updates directly in WSUS, cleanup old WSUS files and delete declined updates
    Each action can be run separately by using the corresponding switch parameter.
    The script can be run in silent mode by using the -RunSilent switch parameter. Whitout this parameter the script will open a grid view to select updates to approve and or delete.
    The script will approve all Defender Definition Updates for the group "All Computers" by default. This can be changed by using the -GroupsForApproval parameter.
    At the moment there is no parameter to change the product category. This can be changed in the script by changing the value of the variable $Categories.
 
    A logfile will be created next to the script with the name of the script and the extension .log. The logfile can be opened with cmtrace.exe from ConfigMgr.
 
.PARAMETER WSUSserver
    The WSUS server to connect to. Default is the local computername.
 
.PARAMETER GroupsForApproval
    The WSUS computer group to approve updates for. Default is "All Computers".
    Other groups have to be created in WSUS before running the script if that is needed.
    
    NOTE: If the WSUS server runs in a different language than English, the group name has to be in the same language.
    The group name is visible in the WSUS console under "Computers".
 
.PARAMETER RunSilent
    Run the script in silent mode. No grid view will be opened for selection of updates to approve or delete.
    This is useful for running the script as a scheduled task.
 
.PARAMETER RunApproveUpdates
    Approve updates for the defined group. Default is $false and will not approve any updates.
 
.PARAMETER RunUnusedFileCleanup
    Run the CleanupUnneededContentFiles task in WSUS. Default is $false and will not run the cleanup task.
 
.PARAMETER RunUnusedFileCleanupOnlyWhenUpdateApproved
    Run the CleanupUnneededContentFiles task in WSUS only when updates are approved before by the task RunApproveUpdates. Default is $false.
 
.PARAMETER RunDeclinedUpdatesCleanup
    Run the cleanup of declined updates. Default is $false and will not run the cleanup task.
    The task will delete declined updates older than the defined threshold in days of parameter DeclinedUpdatesDeletionThresholdDays.

.PARAMETER OutputSQLDeleteQueryToClipboard
    Output the SQL query to delete declined updates to the clipboard. The SQL query can be used in SQL Management Studio to delete updates in SUSDB.
 
.PARAMETER DeclinedUpdatesDeletionThresholdDays
    Specify the number of days between today and the release date for which the declined updates must not be deleted (i.e., updates older than 90 days).
    Default is 120 days.
 
.EXAMPLE
    .\Invoke-WSUSUpdateApprovalAndMaintenance.ps1 -OutputSQLDeleteQueryToClipboard
    Will output the SQL query to delete declined updates to the clipboard. The script will not run anything else.

.EXAMPLE
    .\Invoke-WSUSUpdateApprovalAndMaintenance.ps1 -RunApproveUpdates -RunUnusedFileCleanup -RunDeclinedUpdatesCleanup
    Will approve updates, run cleanup tasks and delete declined updates older than 120 days.
 
.EXAMPLE
    .\Invoke-WSUSUpdateApprovalAndMaintenance.ps1 -RunApproveUpdates -RunUnusedFileCleanup -RunDeclinedUpdatesCleanup -DeclinedUpdatesDeletionThresholdDays 90
    Will approve updates, run cleanup tasks and delete declined updates older than 90 days.
 
.EXAMPLE
    .\Invoke-WSUSUpdateApprovalAndMaintenance.ps1 -RunApproveUpdates -RunUnusedFileCleanup -RunUnusedFileCleanupOnlyWhenUpdateApproved -RunDeclinedUpdatesCleanup
    Will approve updates, run cleanup tasks and delete declined updates older than 120 days. Cleanup tasks will only run if updates are approved before.   
 
.LINK
    https://github.com/jonasatgit/scriptrepo
 
#>
[CmdletBinding()]
param
(
    [string]$WSUSserver = $env:Computername,
    [array]$GroupsForApproval = ("All Computers"),
    [switch]$RunSilent,
    [switch]$RunApproveUpdates,
    [switch]$RunUnusedFileCleanup,
    [switch]$RunUnusedFileCleanupOnlyWhenUpdateApproved,
    [switch]$RunDeclinedUpdatesCleanup,
    [switch]$OutputSQLDeleteQueryToClipboard,
    [int]$DeclinedUpdatesDeletionThresholdDays = 120
)

$script:LogFilePath = '{0}\{1}.log' -f $PSScriptRoot ,($MyInvocation.MyCommand -replace '.ps1') # Next to the script
$script:LogOutputMode = if($RunSilent){"Log"}else{"ConsoleAndLog"}
 
#region Write-CMTraceLog
<#
.Synopsis
    Write-CMTraceLog will writea logfile readable via cmtrace.exe .DESCRIPTION
    Write-CMTraceLog will writea logfile readable via cmtrace.exe (https://www.bing.com/search?q=cmtrace.exe)
.EXAMPLE
    Write-CMTraceLog -Message "file deleted" => will log to the current directory and will use the scripts name as logfile name #>
function Write-CMTraceLog
{
    [CmdletBinding()]
    Param
    (
        #Path to the log file
        [parameter(Mandatory=$false)]
        [String]$LogFile=$script:LogFilePath,
        #The information to log
        [parameter(Mandatory=$true)]
        [String]$Message,
        #The source of the error
        [parameter(Mandatory=$false)]
        [String]$Component=(Split-Path $PSCommandPath -Leaf),
        #severity (1 - Information, 2- Warning, 3 - Error) for better reading purposes this variable as string
        [parameter(Mandatory=$false)]
        [ValidateSet("Information","Warning","Error")]
        [String]$Severity="Information",
        # write to console only
        [Parameter(Mandatory=$false)]
        [ValidateSet("Console","Log","ConsoleAndLog")]
        [string]$OutputMode = $script:LogOutputMode
    )
    if ([string]::IsNullOrEmpty($OutputMode))
    {
        $OutputMode = 'Log'
    }
    # save severity in single for cmtrace severity
    [single]$cmSeverity=1
    switch ($Severity)
        {
            "Information" {$cmSeverity=1; $color = [System.ConsoleColor]::Green; break}
            "Warning" {$cmSeverity=2; $color = [System.ConsoleColor]::Yellow; break}
            "Error" {$cmSeverity=3; $color = [System.ConsoleColor]::Red; break}
        }
    If (($OutputMode -ieq "Console") -or ($OutputMode -ieq "ConsoleAndLog"))
    {
        Write-Host $Message -ForegroundColor $color
    }
  
    If (($OutputMode -ieq "Log") -or ($OutputMode -ieq "ConsoleAndLog"))
    {
        #Obtain UTC offset
        $DateTime = New-Object -ComObject WbemScripting.SWbemDateTime
        $DateTime.SetVarDate($(Get-Date))
        $UtcValue = $DateTime.Value
        $UtcOffset = $UtcValue.Substring(21, $UtcValue.Length - 21)
        #Create the line to be logged
        $LogLine =  "<![LOG[$Message]LOG]!>" +`
                    "<time=`"$(Get-Date -Format HH:mm:ss.mmmm)$($UtcOffset)`" " +`
                    "date=`"$(Get-Date -Format M-d-yyyy)`" " +`
                    "component=`"$Component`" " +`
                    "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
                    "type=`"$cmSeverity`" " +`
                    "thread=`"$PID`" " +`
                    "file=`"`">"
        #Write the line to the passed log file
        $LogLine | Out-File -Append -Encoding UTF8 -FilePath $LogFile
    }
}
#endregion
  
#region Invoke-LogfileRollover
<#
.Synopsis
    Function Invoke-LogfileRollover
.DESCRIPTION
    Will rename a logfile from ".log" to ".lo_".
    Old ".lo_" files will be deleted
.PARAMETER MaxFileSizeKB
    Maximum file size in KB in order to determine if a logfile needs to be rolled over or not.
    Default value is 1024 KB.
.EXAMPLE
    Invoke-LogfileRollover -Logfile "C:\Windows\Temp\logfile.log" -MaxFileSizeKB 2048
#>
Function Invoke-LogfileRollover
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
#endregion
 
#region SQL delete query
$SqlQuery = @'
-------
-- IMPORTANT: Change the SUSDB stored procedure before running this script
-- Read more about it here: https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/spdeleteupdate-slow-performance
USE SUSDB;
-- Delete declined Updates older than 120 days
DECLARE @thresholdDays INT = 120
-- Specify the number of days between today and the release date for which the declined updates must not be deleted (i.e., updates older than 90 days).
DECLARE @testRun BIT = 1 -- Set this to 1 to test without deleting anything. Or zero to actually delete updates
 
-- There shouldn't be any need to modify anything after this line.
DECLARE @uid UNIQUEIDENTIFIER
DECLARE @title NVARCHAR(500)
DECLARE @date DATETIME
 
DECLARE @count INT = 0
 
DECLARE DU CURSOR FOR
SELECT distinct top 20000 MU.UpdateID, U.DefaultTitle, MU.CreationDate from vwMinimalUpdate MU
JOIN PUBLIC_VIEWS.vUpdate U ON MU.UpdateID = U.UpdateId
JOIN dbo.tbRevision rev on MU.LocalUpdateID = rev.LocalUpdateID
WHERE MU.Declined = 1 AND MU.IsLatestRevision = 1 and U.IsWsusInfrastructureUpdate = 0 AND MU.CreationDate < DATEADD(dd,-@thresholdDays,GETDATE())
AND NOT EXISTS (SELECT r.RevisionID FROM dbo.tbRevision r          
               WHERE r.LocalUpdateID = MU.LocalUpdateID          
               AND (EXISTS (SELECT * FROM dbo.tbBundleDependency WHERE BundledRevisionID = r.RevisionID)              
               OR EXISTS (SELECT * FROM dbo.tbPrerequisiteDependency WHERE PrerequisiteRevisionID = r.RevisionID)))
               ORDER BY MU.CreationDate
               PRINT 'Deleting declined updates older than ' + CONVERT(NVARCHAR(5), @thresholdDays) + ' days.' + CHAR(10)
              
OPEN DU
--FETCH NEXT FROM DU INTO @uid, @title, @date
FETCH DU INTO @uid, @title, @date
--WHILE (@@FETCH_STATUS > - 1)
WHILE (@@FETCH_STATUS = 0)
BEGIN  SET @count = @count + 1 
 
               IF @testRun = 0
                              BEGIN
                              PRINT 'Deleting update ' + CONVERT(NVARCHAR(10), @count) + ' UID: ' + CONVERT(NVARCHAR(37), @uid) + ' - (Creation Date ' + CONVERT(NVARCHAR(50), @date) + ') - ' + @title
                              exec spDeleteUpdateByUpdateID @updateID = @uid
                              END
 
               IF @testRun = 1
                              BEGIN
                              PRINT 'SIMULATE: Deleting update ' + CONVERT(NVARCHAR(10), @count) + ' UID: ' + CONVERT(NVARCHAR(37), @uid) + ' - (Creation Date ' + CONVERT(NVARCHAR(50), @date) + ') - ' + @title
                              END
 
               FETCH NEXT FROM DU INTO @uid, @title, @date
END              
 
CLOSE DU
DEALLOCATE DU
PRINT CHAR(10) + 'Attempted to delete ' + CONVERT(NVARCHAR(10), @count) + ' updates.'
'@
#endregion
 
 
if ($OutputSQLDeleteQueryToClipboard)
{
    $SqlQuery | Clip
    Write-Host $SqlQuery -ForegroundColor Gray
    Write-Host "The above SQL query can be used to delete updates in SUSDB" -ForegroundColor Cyan
    Write-Host "The query was copied to the clipboard already and the script will not run anything else" -ForegroundColor Cyan
    Write-Host "Switch to `"Messages`" in SQL query window to show delete messages of the SQL script" -ForegroundColor Cyan
    Exit
}
 
 
 
 
Invoke-LogfileRollover -Logfile $script:LogFilePath -MaxFileSizeKB 2048
Write-CMTraceLog -Message "    "
Write-CMTraceLog -Message "Start of script"
Write-CMTraceLog -Message "RunSilent is set to: $($RunSilent)"
 
#region RunApproveUpdates
if ($RunApproveUpdates)
{
    try
    {
        Write-CMTraceLog -Message "Load assembly: `"Microsoft.UpdateServices.Administration`""
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")

        Write-CMTraceLog -Message "Connect to wsus server: `"$WSUSserver`" via SSL"
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($WSUSserver, $true,8531)

        Write-CMTraceLog -Message "Create WSUS Update scope object: `"Microsoft.UpdateServices.Administration.UpdateScope`""
        $UpdateScope = New-Object Microsoft.UpdateServices.Administration.UpdateScope

        Write-CMTraceLog -Message "Getting update classification of type: `"Definition Updates`""
        $Classification = $wsus.GetUpdateClassifications() | Where-Object {$_.Title -ieq 'Definition Updates'}

        Write-CMTraceLog -Message "Getting category of type product and title: `"Microsoft Defender Antivirus`""
        $Categories = $wsus.GetUpdateCategories() | Where-Object {($_.Type -ieq 'Product') -and ($_.Title -ieq 'Microsoft Defender Antivirus')}
        #Start date for UpdateScope interval to limit findings
        #$UpdateScope.FromCreationDate = (get-date).AddMonths(-1)
        #End date for UpdateScope interval to limit findings
        #$UpdateScope.ToCreationDate = (get-date)
        $UpdateScope.Classifications.Clear()
        $UpdateScope.Classifications.AddRange($Classification)

        $UpdateScope.Categories.Clear()
        $UpdateScope.Categories.AddRange($Categories)

        Write-CMTraceLog -Message "Get updates from wsus server with defined filter criteria"
        $updates = $wsus.GetUpdates($UpdateScope)
    }
    catch
    {
        Write-CMTraceLog -Message "$($_)" -Severity Error
        Write-CMTraceLog -Message "If connection to wsus server: `"$WSUSserver`" via SSL failed, use parameter `"-WSUSserver`" and specify the full fqdn. Example: `"-WSUSserver wsus.contoso.com`"" -Severity Warning
        Write-CMTraceLog -Message "Script failed!" -Severity Warning
        Exit
    }

    Write-CMTraceLog -Message "Found $($updates.count) total updates for defined filter"
    Write-CMTraceLog -Message "Will further filter updates to exclude updates with title like `"platform`", IsSuperseded, IsDeclined, IsApproved"
    [array]$updatesForApproval = $updates | Where-Object {($_.Title -inotlike '*platform*') -and ($_.IsSuperseded -ine 'True') -and ($_.IsDeclined -ine 'True') -and ($_.IsApproved -ine 'True')}
    Write-CMTraceLog -Message "Updates left after filter action: $($updatesForApproval.count)"
    if ($updatesForApproval.count -eq 0)
    {
        Write-CMTraceLog -Message "All required updates already approved"
        if (($RunUnusedFileCleanupOnlyWhenUpdateApproved -eq $true) -and ($RunUnusedFileCleanup -eq $True))
        {
            Write-CMTraceLog -Message "Parameter `"RunUnusedFileCleanupOnlyWhenUpdateApproved`" is set. Will skip RunUnusedFileCleanup to save some time and resources" 
            $RunUnusedFileCleanup = $false
        }
    }
    else
    {
        # Lets now approve updates if we we found some
        if (-Not ($RunSilent))
        {
            Write-CMTraceLog -Message "Script does not run in silent mode. Will open Grid-View for selection"
            [array]$selectedUpdates = $updatesForApproval | Select-Object Title,IsSuperseded,IsApproved,IsDeclined,CreationDate,ArrivalDate,ID | Out-GridView -Title 'Select updates to be approved' -OutputMode Multiple
  
            Write-CMTraceLog -Message "$($selectedUpdates.count) update/s selected"
            if ($selectedUpdates.count -gt 0)
            {
                try
                {
                    foreach ($group in $groupsForApproval)
                    {
                        $computerTargetGroup = $wsus.GetComputerTargetGroups() | Where-Object {$_.Name -ieq $group}
                        if ($computerTargetGroup)
                        {                        
                            foreach ($update in $updatesForApproval)
                            {
                                # Only approve selected updates
                                if ($update.id.updateid.guid -iin $selectedUpdates.id.updateid.guid)
                                {
                                    Write-CMTraceLog -Message "Will try to approve update: `"$($update.Title)`" for group: `"$($group)`""
                                    $update.Approve("Install",$computerTargetGroup)
                                }          
                            }
                        }
                        else
                        {
                            Write-CMTraceLog -Message "Group `"$($group)`" not found in WSUS" -Severity Error
                            Write-CMTraceLog -Message "Script failed!" -Severity Warning
                            Exit                    
                        }
                    }
                }
                Catch
                {
                    Write-CMTraceLog -Message "$($_)" -Severity Error
                    Write-CMTraceLog -Message "Script failed!" -Severity Warning
                    Exit          
                }
            }
            else
            {
                Write-CMTraceLog -Message "No update selected"
                Write-CMTraceLog -Message "Script end"
                exit
            }
        }
        else
        {
            try
            {
                foreach ($group in $groupsForApproval)
                {
                    $computerTargetGroup = $wsus.GetComputerTargetGroups() | Where-Object {$_.Name -ieq $group}
                    if ($computerTargetGroup)
                    {
                        foreach ($update in $updatesForApproval)
                        {
                            Write-CMTraceLog -Message "Will try to approve update: `"$($update.Title)`" for group: `"$($group)`""
                            $null = $update.Approve("Install",$computerTargetGroup)
                        }
                    }
                    else
                    {
                        Write-CMTraceLog -Message "Group `"$($group)`" not found in WSUS" -Severity Error
                        Write-CMTraceLog -Message "Script failed!" -Severity Warning
                        Exit                    
                    }
                }
            }
            catch
            {
                Write-CMTraceLog -Message "$($_)" -Severity Error
                Write-CMTraceLog -Message "Script failed!" -Severity Warning
                Exit
            }
        }
    }
}
#endregion
 
#region RunDeclinedUpdatesCleanup
if ($RunDeclinedUpdatesCleanup)
{
   try {
        Write-CMTraceLog -Message "Load assembly: `"Microsoft.UpdateServices.Administration`""
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
   
        Write-CMTraceLog -Message "Connect to wsus server: `"$WSUSserver`" via SSL"
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($WSUSserver, $true,8531)
   
        Write-CMTraceLog -Message "Create WSUS Update scope object: `"Microsoft.UpdateServices.Administration.UpdateScope`""
        $UpdateScope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
   
        $UpdateScope.Classifications.Clear()
        $UpdateScope.Categories.Clear()
   
        $UpdateScope.ApprovedStates = 'Declined'
        $UpdateScope.ToCreationDate = (Get-Date).AddDays(-$DeclinedUpdatesDeletionThresholdDays)
   
        Write-CMTraceLog -Message "Get updates from wsus server with defined filter criteria. Declined=Yes and CreationDate less than $(Get-date((Get-Date).AddDays(-$DeclinedUpdatesDeletionThresholdDays)) -format u)"
        [array]$updates = $wsus.GetUpdates($UpdateScope)
    }
    catch
    {
        Write-CMTraceLog -Message "$($_)" -Severity Error
        Write-CMTraceLog -Message "Script failed!" -Severity Warning
        Exit
    }
 
    # Just another filter to make sure we are not removing any required updates by accident
    [array]$filteredUpdates = $updates | Where-Object {($_.CreationDate -le (Get-Date).AddDays(-$DeclinedUpdatesDeletionThresholdDays)) -and ($_.IsDeclined -eq 1) -and ($_.IsLatestRevision -eq 1)}
    
    if (-Not ($RunSilent))
    { 
        Write-CMTraceLog -Message "Script does not run in silent mode. Will open Grid-View for selection"   
        [array]$selectedUpdates = $filteredUpdates | Select-Object Title,IsSuperseded,IsApproved,IsDeclined,CreationDate,ArrivalDate,ID | Out-GridView -Title "Select declined updates to be removed from $($filteredUpdates.count) number of updates" -OutputMode Multiple
        Write-CMTraceLog -Message "$($selectedUpdates.count) update/s selected"
    }
    else
    {
        [array]$selectedUpdates = $filteredUpdates
        Write-CMTraceLog -Message "$($selectedUpdates.count) update/s found with filter"     
    }

    if ($selectedUpdates.count -ge 1)
    {
        foreach($update in $selectedUpdates | Sort-Object CreationDate)
        {
            Write-CMTraceLog -Message ('Delete declined update created: {0} Title: {1}' -f (Get-date($update.CreationDate) -format u), $update.title)
            try
            {
                $wsus.DeleteUpdate($update.id.UpdateId.guid)
            }
            Catch
            {
                if ($_.Exception -imatch 'still referenced by other')
                {
                    Write-CMTraceLog -Message ($_.Exception) -Severity Warning
                    Write-CMTraceLog -Message "Update still referenced. Will continue script" -Severity Warning
                }
                else
                {
                    Write-CMTraceLog -Message ($_.Exception) -Severity Error
                    Write-CMTraceLog -Message "Script failed!" -Severity Error
                    Exit   
                }            
            }
        }
    }
}
#endregion

#region RunUnusedFileCleanup
if ($RunUnusedFileCleanup)
{
    $tryAgain = $false
    try
    {
        Write-CMTraceLog -Message "Will try to run CleanupUnneededContentFiles task in WSUS"
        $retVal = Get-WsusServer $wsusserver -PortNumber 8531 -UseSsl | Invoke-WsusServerCleanup -CleanupUnneededContentFiles -ErrorAction Stop
        Write-CMTraceLog -Message "$($retVal.ToString())"
    }
    catch
    {
        Write-CMTraceLog -Message "$($_)" -Severity Error
        Write-CMTraceLog -Message "File cleanup failed or timed out" -Severity Warning
        Write-CMTraceLog -Message "Will wait for 5 minutes to try again" -Severity Warning
        $tryAgain = $true
        Start-Sleep -Seconds 300  
        <#
            We might get an error like this in: "C:\Program Files\Update Services\LogFiles\SoftwareDistribution.log"
            Warning  WsusService.14 DataAccess.GetNextQueuedSubscription              Index #0
            Message: Transaction (Process ID 56) was deadlocked on lock resources with another process and has been chosen as the deadlock victim. Rerun the transaction.
            In that case we need to wait some minutes and try again.
            The output of Invoke-WsusServerCleanup should look like this:
            Diskspace Freed:<int of space freed>
        #>
    }

    # Lets try a second time in case the first try wasn't successful
    if ($tryAgain)
    {
        try
        {
            Write-CMTraceLog -Message "Will try to run CleanupUnneededContentFiles task in WSUS"
            $retVal = Get-WsusServer $wsusserver -PortNumber 8531 -UseSsl | Invoke-WsusServerCleanup -CleanupUnneededContentFiles -ErrorAction Stop
            Write-CMTraceLog -Message "$($retVal.ToString())"
        }
        catch
        {
            Write-CMTraceLog -Message "$($_)" -Severity Error
            Write-CMTraceLog -Message "Script failed!" -Severity Warning
            Exit
        }
    }
}
#endregion
 
Write-CMTraceLog -Message "Script end"