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
.SYNOPSIS
Script to analyze ConfigMgr applications, create Intune win32 app packages and upload them to Intune.

.DESCRIPTION
This script will connect to the ConfigMgr database and retrieve all audit messages since the last run. 
It will then load the correct message DLL and replace the placeholders with the actual data. 
The script will then display the messages in a gridview and allow the user to select the messages to be exported to a new table in the ConfigMgr database.

IMPORTANT: The script needs to run in the 32bit version of PowerShell in order to use the 32bit ConfigMgr dlls

The following steps need to be done before running the script:
1. Create a new database to store the exported audit messages in
2. Run the script with the -ShowAuditTableDefinition switch to get the SQL command to create a required table
3. Run the SQL command in the new database to create the table
4. Run the script with the correct parameters every day to export audit messages and import them into the new table

Script is based on: https://learn.microsoft.com/en-us/mem/configmgr/develop/core/servers/manage/about-configuration-manager-component-status-messages
And: https://devblogs.microsoft.com/powershell-community/reading-configuration-manager-status-messages-with-powershell/

.PARAMETER CMSQLServer
The SQL server name (and instance name where appropriate) of the ConfigMgr database
Either SQL Server fqdn like this: CM02.contoso.local
Or SQL server fqdn and instance name like this: CM02.contoso.local\INST02

.PARAMETER CMDatabase
The name of the ConfigMgr database

.PARAMETER AuditSQLServer
The SQL server name (and instance name where appropriate) of the new database to store the exported audit messages in
Either SQL Server fqdn like this: CM02.contoso.local
Or SQL server fqdn and instance name like this: CM02.contoso.local\INST02

.PARAMETER AuditDatabase
The name of the ConfigMgr database

.PARAMETER OutputLanguage
The language in which the message text should be returned
Default is en-us

.PARAMETER RunSilent
Switch parameter to run the script without showing anything to the user.
Default is $false which will show a gridview with all messages and allow the user to select the messages to be imported into the AuditStatusMessages table.
If set, the script will not show the gridview and will import all messages into the AuditStatusMessages table directly

.PARAMETER LogFolder
The path to the folder to store the logfile in
Default is the script folder

#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$False, HelpMessage="The SQL server name (and instance name where appropriate)")]
    [string]$CMSQLServer = "CM02.contoso.local\INST02",
    [Parameter(Mandatory=$False, HelpMessage="The name of the ConfigMgr database")]
    [string]$CMDatabase = "CM_P02",
    [Parameter(Mandatory=$False, HelpMessage="The SQL server name (and instance name where appropriate)")]
    [string]$AuditSQLServer = "CM02.contoso.local\INST02",
    [Parameter(Mandatory=$False, HelpMessage="The name of the ConfigMgr database")]
    [string]$AuditDatabase = "CM_AuditData",
    [Parameter(Mandatory=$False, HelpMessage="The language in which the message text should be returned")]
    [ValidateSet("de-de", "en-us")]
    [string]$OutputLanguage = "en-us",
    [Parameter(Mandatory=$False, HelpMessage="Should the script run silently?")]
    [Switch]$RunSilent,
    [Parameter(Mandatory=$False, HelpMessage="The path to the folder to store the logfile in")]
    [string]$LogFolder,
    [Parameter(Mandatory=$False, HelpMessage="Show audit table definition")]
    [switch]$ShowAuditTableDefinition,
    [Parameter(Mandatory=$False, HelpMessage="If the custom audit table has no data yet, run the script once with this prameter and provide the minimum audit datetime value as string in the following format: yyyy-MM-dd HH:mm:ss.fff")]
    [string]$MinAuditStartDatetimeString = '2024-01-08 08:22:36.137'
)


#region audit table definition
$auditTableInfo = @'
------------------------------------------------------
-- Table definition for AuditStatusMessages
-- This table will store the exported audit messages
-- Change the database name to your needs before running the script: "USE [CM_AuditData]"
-- Run the  SQL script in SQL Management Stuido to create the table
-- Then run the PowerShell script with the correct parameters to export the audit messages into the new table
------------------------------------------------------
USE [CM_AuditData]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[AuditStatusMessages](
	[RecordID] [bigint] NOT NULL,
	[SeverityName] [nvarchar](128) NULL,
	[Severity] [int] NULL,
	[SiteCode] [nvarchar](3) NOT NULL,
	[TopLevelSiteCode] [nvarchar](3) NULL,
	[MessageID] [int] NOT NULL,
	[MessageType] [int] NULL,
	[ModuleName] [nvarchar](128) NOT NULL,
	[Component] [nvarchar](128) NOT NULL,
	[MachineName] [nvarchar](128) NOT NULL,
	[TimeUTC] [datetime] NOT NULL,
	[DeleteTimeUTC] [datetime] NOT NULL,
	[MessageText] [nvarchar](max) NULL,
 CONSTRAINT [AuditStatusMessages_PK] PRIMARY KEY CLUSTERED 
(
	[RecordID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
ALTER TABLE [dbo].[AuditStatusMessages]  WITH NOCHECK ADD  CONSTRAINT [StatusMessages_RecordID_Partition_CK] CHECK NOT FOR REPLICATION (([RecordID]>=(72057594037927936.) AND [RecordID]<=(144115188075855871.)))
GO
ALTER TABLE [dbo].[AuditStatusMessages] CHECK CONSTRAINT [StatusMessages_RecordID_Partition_CK]
GO
'@
#endregion


#region show audit definition
if ($ShowAuditTableDefinition)
{
    Write-Host $auditTableInfo
    break
}
#endregion


#region check for 32bit powershell
if ([Environment]::Is64BitProcess)
{
    Write-Warning "The script needs to run in the 32bit version of PowerShell in order to use the 32bit ConfigMgr dlls"
    break
}
#endregion


#region Logfile
if (-NOT($LogFolder))
{
    $Global:LogFilePath = '{0}\{1}.log' -f $PSScriptRoot ,($MyInvocation.MyCommand)
}
else 
{
    $Global:LogFilePath = '{0}\{1}.log' -f $LogFolder, ($MyInvocation.MyCommand)
}
#endregion


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
        [String]$LogFile=$Global:LogFilePath,

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
        [string]$OutputMode = 'Log'
    )


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
        [parameter(Mandatory=$False)]
        [string]$Logfile= $Global:LogFilePath,
        
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

Invoke-LogfileRollover
Write-CMTraceLog -Message "  "
Write-CMTraceLog -Message "  "
Write-CMTraceLog -Message "Starting script"

#region type definition
Write-CMTraceLog -Message "Adding type definition for Win32Api"
Add-Type -TypeDefinition @"
namespace Win32Api
{
    using System;
    using System.Text;
    using System.Runtime.InteropServices;

    public class kernel32
    {

        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern IntPtr GetModuleHandle(
            string lpModuleName
        );

        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern int FormatMessage(
            uint dwFlags,
            IntPtr lpSource,
            uint dwMessageId,
            uint dwLanguageId,
            StringBuilder msgOut,
            uint nSize,
            string[] Arguments
        );

                [DllImport("kernel32", SetLastError=true, CharSet = CharSet.Unicode)]
        public static extern IntPtr LoadLibrary(
            string lpFileName
        );

    }

}
"@
#endregion


#region language
switch ($OutputLanguage)
{
    'de-de' 
    {
        Write-CMTraceLog -Message "Setting language of exported messages to de-de"
        $dllPath = ('{0}\i386\00000407' -f ($env:SMS_ADMIN_UI_PATH | Split-Path -Parent))    
    }
    'en-us' 
    {
        Write-CMTraceLog -Message "Setting language of exported messages de-de"
        $dllPath = ('{0}\i386\00000409' -f ($env:SMS_ADMIN_UI_PATH | Split-Path -Parent))    
    }
}

if (-NOT (Test-Path $dllPath))
{
    Write-CMTraceLog "Path not found: `"$dllPath`"" -Severity Error
    Write-CMTraceLog "End script with error"
    break
}
#endregion



#region Getting last status messages time from custom audit table
# before doing anything, we need the last adit log entry datetime from our custom DB
try 
{
    $query = "SELECT convert(varchar, max(stat.TimeUTC), 121) as [LastTime], Count(1) as [EntryCounter] FROM [dbo].[AuditStatusMessages] stat"
    $connectionString = "Server=$AuditSQLServer;Database=$AuditDatabase;Integrated Security=SSPI;"
    Write-CMTraceLog -Message "Connect to SQL to get last status messages time from custom audit table"
    write-cmtracelog -Message "SQL connection string: `"$connectionString`""
    Write-CMTraceLog -Message "SQL query: `"$query`""
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    $connection.Open()
    # Run the query
    $command = $connection.CreateCommand()
    $command.CommandText = $query
    $reader = $command.ExecuteReader()
    $table = new-object "System.Data.DataTable"
    # Load data
    $table.Load($reader) 
    # Close the connection
    $connection.Close()
}
catch 
{
    Write-CMTraceLog -Message "SQL connect failed: $($_)" -Severity Error
    if ($connection.State -ieq 'open')
    {
        $connection.Close()
    }
    Write-CMTraceLog -Message "End script with error"
    Exit
}

# Used for the SQL query to get the status messages either with a date greater than or greater or equal
$queryOperator = '>'
if ($Table.Rows.EntryCounter[0] -eq 0)
{
    Write-CMTraceLog -Message "No SQL results found with query! Table might be new." -Severity Warning
    if($MinAuditStartDatetimeString)
    {
        Write-CMTraceLog -Message "Parameter -MinAuditStartDatetimeString is set to: `"$MinAuditStartDatetimeString`" will use that as start date"
        $StartDateTimeValue = $MinAuditStartDatetimeString
        # We need to set the query operator to include the datetime which was passed via parameter
        $queryOperator = '>='
    }
    else
    {
        Write-CMTraceLog -Message "No results from SQL query and parameter -MinAuditStartDatetimeString not set"
        Write-CMTraceLog -Message "If the table was just created, get the minimum audit datetime with the following query from the ConfigMgr database:"
        Write-CMTraceLog -Message "`"SELECT convert(varchar, min(smsgs.Time), 121) as [MinTime] FROM v_StatusMessage smsgs where smsgs.MessageType = 768`""
        Write-CMTraceLog -Message "Then run the script again with the -MinAuditStartDatetimeString parameter to get all the audit messages since that date"
        Write-CMTraceLog -Message "End script with error"
        Exit
    }

}
else
{
    $StartDateTimeValue = $table.LastTime
}


# regex to check if the value is indead in the format of a datetime like 2024-06-12 22:23:43.070
if ($StartDateTimeValue -notmatch '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}.\d{3}$')
{
    Write-CMTraceLog -Message "No valid datetime found in SQL results for startdatetime" -Severity Error
    Write-CMTraceLog -Message "Current value: `"$StartDateTimeValue`" Expected format like: 2024-06-12 22:23:43.070 => yyyy-MM-dd HH:mm:ss.fff"
    Write-CMTraceLog -Message "End script with error"
    Exit
}
#endregion


#region Get all new audit messages from ConfigMgr DB
# Define the SQL query
$Query = @"
SELECT smsgs.RecordID
	,smsgs.MessageID
	,smsgs.Type&0x0000FF00 as MessageType
	,smsgs.MachineName
	,smsgs.ModuleName
	,convert(varchar, smsgs.Time, 121) as [TimeUTC] ---- convert to ISO 8601 format like: 2024-06-12 22:23:43.070
	,convert(varchar, smsgs.DeleteTime, 121) as [DeleteTimeUTC] ---- convert to ISO 8601 format like: 2024-06-12 22:23:43.070
	,smsgs.SiteCode
	,smsgs.TopLevelSiteCode
	,smsgs.Component
	,Case when smsgs.ID&0xF0000000 = '1073741824' THEN '1073741824' --Informational
        WHEN smsgs.ID&0xF0000000 = '-2147483648' THEN '2147483648' --Warning
        WHEN smsgs.ID&0xF0000000 = '-1073741824' THEN '3221225472' --Error
		END As [Severity]
	,CASE smsgs.ID&0xF0000000
		WHEN -1073741824 THEN 'Error'
		WHEN 1073741824 THEN 'Informational'
		WHEN -2147483648 THEN 'Warning'
		ELSE 'Unknown'
		END As [SeverityName]
	,case smsgs.Type&0x0000FF00
		WHEN 256 THEN 'Milestone'
		WHEN 512 THEN 'Detail'
		WHEN 768 THEN 'Audit'
		WHEN 1024 THEN 'NT Event'
		ELSE 'Unknown'
		END AS [Type]
	,modNames.MsgDLLName
	,smwis.InsString1
	,smwis.InsString2
	,smwis.InsString3
	,smwis.InsString4
	,smwis.InsString5
	,smwis.InsString6
	,smwis.InsString7
	,smwis.InsString8
	,smwis.InsString9
	,smwis.InsString10            
FROM StatusMessages as smsgs with (nolock)
join v_StatMsgWithInsStrings smwis with (nolock) on smsgs.RecordID = smwis.RecordID
join v_StatMsgModuleNames modNames with (nolock) on smsgs.ModuleName = modNames.ModuleName
where smsgs.Type&0x0000FF00 = 768 -- only audit messages
and smsgs.Time {0} '{1}' 
Order by smsgs.Time DESC
"@

# addind operator and datetime value
$query = $query -f $queryOperator, $StartDateTimeValue


try 
{    
    $connectionString = "Server=$CMSQLServer;Database=$CMDatabase;Integrated Security=SSPI;"
    Write-CMTraceLog -Message "Connect to SQL to get all new audit messages from ConfigMgr DB since UTC time: `"$($StartDateTimeValue)`""
    write-cmtracelog -Message "SQL connection string: `"$connectionString`""
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    $connection.Open()
    # Run the query
    $command = $connection.CreateCommand()
    $command.CommandText = ($query -f $queryOperator, $StartDateTimeValue)
    $reader = $command.ExecuteReader()
    $table = new-object "System.Data.DataTable"
    # Load data
    $table.Load($reader) 
    # Close the connection
    $connection.Close()
}
catch 
{
    Write-CMTraceLog -Message "SQL connect failed: $($_)" -Severity Error
    Write-CMTraceLog -Message "In case the audit table is not available, you can get the defintion with the -ShowAuditTableDefinition switch"
    Write-CMTraceLog -Message "Then run the SQL command in in the correct database to create the table"
    if ($connection.State -ieq 'open')
    {
        $connection.Close()
    }
    Write-CMTraceLog -Message "End script with error"
    Exit
}

if ($Table.Rows.count -eq 0)
{
    Write-CMTraceLog -Message "No new audit messages found in ConfigMgr DB since UTC time: $($StartDateTimeValue)" -Severity Warning
    Write-CMTraceLog -Message "End script"
    break
}
else
{
    Write-CMTraceLog -Message "Found: $($Table.Rows.Count) audit status messages with time >= `"$($StartDateTimeValue)`""
}
#endregion


#region Load the correct message DLL and replace the placeholders with the actual data
Write-CMTraceLog -Message "Load the correct message DLL per message and replace the placeholders with the actual data to construct the message text"
$statusMessageList = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($Row in $Table.Rows)
{

    try 
    {   
        $statusMessage = [PSCustomObject][ordered]@{
                RecordID = $row.RecordID
                SeverityName = $Row.SeverityName
                Severity = $Row.Severity
                Type = $Row.Type
                MessageType = $row.MessageType
                SiteCode = $Row.SiteCode
                TopLevelSiteCode = $Row.TopLevelSiteCode
                TimeUTC = $Row.TimeUTC
                DeleteTimeUTC = $Row.DeleteTimeUTC
                MachineName = $Row.MachineName
                Component = $Row.Component
                ModuleName = $Row.ModuleName
                MessageID = $Row.MessageID
                MessageText = $null
                }
                

        # load required dll
        $smsMsgsPath = '{0}\{1}' -f $dllPath, $Row.MsgDLLName
        $moduleHandle = [Win32Api.kernel32]::GetModuleHandle("$smsMsgsPath") 

        # zero means module not loaded
        if ($moduleHandle -eq 0) {
                [void][Win32Api.kernel32]::LoadLibrary("$smsMsgsPath")
                $moduleHandle = [Win32Api.kernel32]::GetModuleHandle("$smsMsgsPath")
        }

        # Buffer size for output message.
        $bufferSize = [int]16384 
        # StringBuilder to hold message.
        $bufferOutput = New-Object 'System.Text.StringBuilder' -ArgumentList $bufferSize

        $lastError = $null
        $message = $null
        # Lets get the correct message text
        $result = [Win32Api.kernel32]::FormatMessage(
                0x00000800 -bor 0x00000200 # FORMAT_MESSAGE_FROM_HMODULE | FORMAT_MESSAGE_IGNORE_INSERTS
                ,$moduleHandle
                ,($Row.Severity) -bor ($Row.MessageID)  
                ,0 # languageID. 0 = Default.
                ,$bufferOutput
                ,$bufferSize
                ,$null 
        )

        # zero means error
        if ($result -eq 0) 
        { 
            $lastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error() 
            # We cannot continue if we have an error with the next message, because there is no logic yet to handle this and add specific messages later
            Write-CMTraceLog -Message "`"[Win32Api.kernel32]::FormatMessage()`" caused an error: $($lastError)" -Severity Error
            Write-CMTraceLog -Message "Error caused by status message record: $($row.RecordID)"
            Write-CMTraceLog -Message "End script with error"
            Exit
        }

        # We now need to replace the placeholder with the actual data
        $message = $bufferOutput.ToString().Replace("%11","").Replace("%12","").Replace("%3%4%5%6%7%8%9%10","").Replace("%1",$row.InsString1).Replace("%2",$Row.InsString2).Replace("%3",$Row.InsString3).Replace("%4",$Row.InsString4).Replace("%5",$Row.InsString5).Replace("%6",$Row.InsString6).Replace("%7",$Row.InsString7).Replace("%8",$Row.InsString8).Replace("%9",$Row.InsString9).Replace("%10",$Row.InsString10)

        # replacing linebreaks and double periods at the end
        #-replace '\. \.\s*$', '.' # not replacing the double period, since ConfigMgr console does also show these. This way the messages are constistent.
        $statusMessage.MessageText = $message -replace "`r`n`r`n" 

        $statusMessageList.Add($statusMessage)
    }
    catch 
    {
        Write-CMTraceLog -Message "FormatMessage method failed: $($_)" -Severity Error
        Write-CMTraceLog -Message "End script with error"
        Exit
    }
}
#endregion



#region show gridview if not run silent
if (-Not ($RunSilent))
{
    [array]$selectedStatusMessages = $statusMessageList | Out-GridView -OutputMode Multiple -Title 'Select the messages you want to import into the AuditStatusMessages table'
    if ($selectedStatusMessages.count -gt 0)
    {
        $statusMessageList = $selectedStatusMessages
        Write-CMTraceLog -Message "User selected $($selectedStatusMessages.count) messages"
    }
    else
    {
        Write-CMTraceLog -Message "Nothing selected in GridView. Script will end!" -Severity Warning
        break
    }
}
#endregion


#region Import the messages into the AuditStatusMessages table
$insertStatement = @'
	INSERT INTO [CM_AuditData].[dbo].[AuditStatusMessages](RecordID,SeverityName,Severity,SiteCode,TopLevelSiteCode,MessageID,MessageType,ModuleName,Component,MachineName,TimeUTC,DeleteTimeUTC,MessageText)
	VALUES ('{0}','{1}','{2}','{3}','{4}','{5}','{6}','{7}','{8}','{9}','{10}','{11}','{12}')
'@


if ($statusMessageList)
{
    Write-CMTraceLog -Message "Will try to import $($statusMessageList.count) audit status messages into custom table"

    Try 
    {
        #Define connction string of target database
        $connectionString = "Server=$AuditSQLServer;Database=$AuditDatabase;Integrated Security=SSPI;"
        Write-CMTraceLog -Message "Connect to SQL to import the messages into the AuditStatusMessages table"
        write-cmtracelog -Message "SQL connection string: `"$connectionString`""
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        $cmd = $connection.CreateCommand()
    }
    Catch 
    {
        Write-CMTraceLog -Message "SQL connect failed: $($_)" -Severity Error
        if ($connection.State -ieq 'open')
        {
            $connection.Close()
        }
        Write-CMTraceLog -Message "End script with error"
        Exit
    }

    foreach ($entry in $statusMessageList)
    {
        Try
        {    
            $cmd.CommandText = $insertStatement -f $entry.RecordID,$entry.SeverityName,$entry.Severity,$entry.SiteCode,$entry.TopLevelSiteCode,$entry.MessageID,$entry.MessageType,$entry.ModuleName,$entry.Component,$entry.MachineName,$entry.TimeUTC,$entry.DeleteTimeUTC,$entry.MessageText
            $null = $cmd.ExecuteNonQuery()
        }
        Catch
        {
            if ($_ -imatch 'Cannot insert duplicate key')
            {
                Write-CMTraceLog -Message "RecordID $($entry.RecordID) already exists in the AuditStatusMessages table. Will be ignored" -Severity Warning
                continue
            }    
            else
            {
                Write-CMTraceLog -Message "Error: $($_)" -Severity Error
                Write-CMTraceLog -Message "End script with error"
                if ($connection.State -ieq 'open')
                {
                    $connection.Close()
                }
                Exit
            }
        }
    }
    #Close the connection
    if ($connection.State -ieq 'open')
    {
        $connection.Close()
    }
    Write-CMTraceLog -Message "Entries imported!"
}
Write-CMTraceLog -Message "End script"
#endregion