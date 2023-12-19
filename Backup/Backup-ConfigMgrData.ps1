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
    Backup-ConfigMgrData is designed to backup additional ConfigMgr data

.DESCRIPTION
    Backup-ConfigMgrData is designed to backup additional ConfigMgr data.
    It can either run after the ConfigMgr backup task or standalone with the backup task disabled.
    The script can be scheduled via a scheduled task or the Afterbackup.bat file in "<ConfigMgrInstallationFolder>\Inboxes\Smsbkup.box"
    The script works in the following way:
    Step 1: It will look for a file called "Backup-ConfigMgrData.ps1.xml". The XML file contains basic information for the script to backup data and has seperate description. 
    Step 2: A logfile will be created called "Backup-ConfigMgrData.ps1.log" and important steps will be written to the application eventlog.
    Step 3: Required ConfigMgr data like the SiteCode, the SQL Server name and other important information are read from the ConfigMgr site.
    Step 4: All path configured in "Backup-ConfigMgrData.ps1.xml" will be tested. The script stops in the case of a missing path. 
    Step 5: All custom path configured in "Backup-ConfigMgrData.ps1.xml" will either be copied to the backup directory directly or to a temp location to be compressed later. 
            The script will also create txt files and PowerShell scripts with detailed instructions for the recovery process.
            00-Recover-Site-without-SQL-unattended.ini  -> ConfigMgr setup unattend.ini file. To be able to recover without the requirement for manual data input.
            Step-01-Setup-machine.txt                   -> General recovery instructions and basic OS and ConfigMgr data.
            Step-02-Install-Roles.txt                   -> Instructions to install required roles and features.	
            Step-02-Install-Roles.txt.ps1               -> Script to install required roles and features.
            Step-03-Install-SQLServer.txt               -> Instructions to install SQL in the case SQL failed. Contains SQL version and port configuration. As well as a list of SQL backups and their location
            Step-04-Install-ADK.txt                     -> Instructions to install ADK and version info
            Step-05-ConfigureWSUS.txt                   -> Instructions to configure WSUS for the recovery process. Only if WSUS failed as well. 
            Step-06-CopyCustomFiles.txt                 -> Instructions to recover custom files and folders. 	
            Step-07-Import-IISConfig.txt	            -> Instructions to recover IIS configurations in case customizations where made.
            Step-07-Import-IISConfig.txt.ps1	        -> Script to recover IIS configurations.
            Step-08-Import-ScheduledTasks.txt	        -> Instructions to recover scheduled tasks.
            Step-08-Import-ScheduledTasks.txt.ps1	    -> Script to recover scheduled tasks.
            Step-09-Validate-Certificates.txt	        -> Instructions to validate certificates for the recovery process.
            Step-10-InstallSSRSAndImportReports.txt	    -> Instructions for the Reporting Services recovery. The script also exports all available reports from SSRS to the backup location
            Step-11-CopySourceFilesOrContentLibrary.txt -> Instructions to copy source files and ContentLibrary data back to its original location.
            Step-12-RecoverConfigMgr.txt                -> Recovery instructions to recover ConfigMgr either manually or via a unattend.ini file. 	
            Step-13-Set-ServiceAccountPasswords.txt	    -> Instructions for post recovery tasks

    Step 6: If configured in "Backup-ConfigMgrData.ps1.xml" the script will backup either all SQL databases or all user databases or databases specified as "DatabaseList".
    Step 7: If configured in "Backup-ConfigMgrData.ps1.xml" the script will compress custom backups.
            If the ConfigMgr backup task is NOT enabled, the script will also compress the CD.Latest folder and will add zip-file to the backup
    Step 8: The script will rename the current backup folder and will add a string in the format of: 'yyyyMMdd-hhmmss'.
            To ensure no future backup process will overwrite the folder. 
    Step 9: If configured in "Backup-ConfigMgrData.ps1.xml" the script will copy the whole backup folder to a second location.
            If configured in "Backup-ConfigMgrData.ps1.xml" the script will copy ContentLibrary or Source folders to a backup location using RoboCopy.
            Any folder can be copied that way. For example a folder containing operating system and SQL server images to have them at the same location as the backup. 
    Step 10: The script will delete old backup folders based on "MaxBackupDays" and "MaxBackups" configured in "Backup-ConfigMgrData.ps1.xml"
    Step 11: The script will copy its logfile and the "Backup-ConfigMgrData.ps1.xml" to the backup location to make the files accessible in case of the need for recovery.
    
.EXAMPLE
    .\Backup-ConfigMgrData.ps1

.LINK
    https://github.com/jonasatgit/scriptrepo

#>
$scriptVersion = '20231218'

# Base variables
[string]$scriptPath = $PSScriptRoot

[string]$configXMLFileName = "{0}.xml" -f ($MyInvocation.MyCommand.Name)
[string]$configXMLFilePath = "{0}\{1}" -f $scriptPath, $configXMLFileName

[string]$global:logFile = "{0}\{1}.log" -f $scriptPath, ($MyInvocation.MyCommand.Name)
[string]$global:scriptName = $MyInvocation.MyCommand.Name
[string]$global:Component = "ConfigMgrBackupScript" # Eventsource for eventlog entries
[string]$logFilePath = $PSScriptRoot



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

#region Check Robocopy Result
Function Check-RoboCopyResultFromLog
{
    param([string]$LogFilePath)
    # .NET Framework 4.5 is required
    # Check Summary like this
    #               Total    Copied   Skipped  Mismatch    FAILED    Extras
    #    Dirs :       168        47         0         0         0         0
    #   Files :       206        63       143         0         0         0
    
    
        $dirsTotal = 0
        $dirsCopied = 0
        $dirsSkipped = 0
        $dirsMismatch = 0
        $dirsFAILED = 0
        $dirsExtras = 0
        $filesTotal = 0
        $filesCopied = 0
        $filesSkipped = 0
        $filesMismatch = 0
        $filesFAILED = 0
        $filesExtras = 0
        # grep last 13 lines to avaluate the copy summary
        $roboCopyResult = Get-Content $LogFilePath -Last 13
        $bolFound = $false
        $roboCopyResult | ForEach-Object {
                # english and german language
                if(($_).Contains('Dirs :') -or ($_).Contains('Verzeich.:'))
                {
                    $bolFound = $true
                    $a = ($_).Replace('Dirs :','Dirs:')
                    $a = ($a).split(" ",[StringSplitOptions]'RemoveEmptyEntries') # .NET Framework 4.5
                    $dirsTotal = $a[1]
                    $dirsCopied = $a[2]
                    $dirsSkipped = $a[3]
                    $dirsMismatch = $a[4]
                    $dirsFAILED = $a[5]
                    $dirsExtras = $a[6]
                }
                # english and german language
                if(($_).Contains('Files :') -or ($_).Contains('Dateien:'))
                {
                    $bolFound = $true
                    $a = ($_).Replace('Files :','Files:')
                    $a = ($a).split(" ",[StringSplitOptions]'RemoveEmptyEntries') # .NET Framework 4.5
                    $filesTotal = $a[1]
                    $filesCopied = $a[2]
                    $filesSkipped = $a[3]
                    $filesMismatch = $a[4]
                    $filesFAILED = $a[5]
                    $filesExtras = $a[6]
                }
            }
    
        $props = @{
            ResultFoundInLog = $bolFound
            DirsTotal = $dirsTotal
            DirsCopied = $dirsCopied
            DirsSkipped = $dirsSkipped
            DirsMismatch = $dirsMismatch
            DirsFAILED = $dirsFAILED
            DirsExtras = $dirsExtras
            FilesTotal = $filesTotal
            FilesCopied = $filesCopied
            FilesSkipped = $filesSkipped
            FilesMismatch = $filesMismatch
            FilesFAILED = $filesFAILED
            FilesExtras = $filesExtras
        }
    
        $outObject = New-Object psobject -Property $props
    
        return $outObject
}
#endregion
   
    
#region Start-RoboCopy
Function Start-RoboCopy
{
    [CmdletBinding()]
    Param(
          [parameter(Mandatory=$True,ValueFromPipeline=$false)]
          [string]$Source,
          [parameter(Mandatory=$True,ValueFromPipeline=$false)]
          [string]$Destination,
          [parameter(Mandatory=$True,ValueFromPipeline=$false)]
          [string]$CommonRobocopyParams,
          [parameter(Mandatory=$True,ValueFromPipeline=$false)]
          [string] $RobocopyLogPath,
          [parameter(Mandatory=$False,ValueFromPipeline=$false)]
          [string]$IPG = 0
          # IPG will effect the overall runtime of the script
        )
        # /MIR :: MIRror a directory tree (equivalent to /E plus /PURGE)
        # /NP :: No Progress - don't display percentage copied.
        # /NDL :: No Directory List - don't log directory names.
        # /NC :: No Class - don't log file classes.
        # /BYTES :: Print sizes as bytes.
        # /NJH :: No Job Header.
        # /NJS :: No Job Summary.
    
        # example CommonRobocopyParams = '/MIR /NP /NDL /NC /BYTES /NJH /NJS'
        $ArgumentList = '"{0}" "{1}" /LOG:"{2}" /ipg:{3} {4}' -f $Source, $Destination, $RobocopyLogPath, $IPG, $CommonRobocopyParams
    
        #Check if robocopy is accessible
        
        Write-CMTraceLog -Message "Start RoboCopy with the following parameters: `"$ArgumentList`""
        
        $roboCopyPath = "C:\windows\system32\robocopy.exe"
        if(-NOT(Test-Path $roboCopyPath))
        {
            Write-CMTraceLog -Message "Robocopy not found: `"$roboCopyPath`"" -Type Error -LogType LogAndEventlog
            Invoke-StopScriptIfError
        }
    
        try
        {
            $Robocopy = Start-Process -FilePath $roboCopyPath -ArgumentList $ArgumentList -Verbose -PassThru -Wait -WindowStyle Hidden -ErrorAction Stop
        }
        Catch
        {

            Write-CMTraceLog -Message "RoboCopy failed" -Type Error -LogType LogAndEventlog
            Write-CMTraceLog -Message "$($error[0].Exception)" -Type Error -LogType LogAndEventlog
            Invoke-StopScriptIfError      
        }
        
        $copyResult = Check-RoboCopyResultFromLog -LogFilePath $RobocopyLogPath
        Write-CMTraceLog -Message "RoboCopy result..."
        Write-CMTraceLog -Message "$copyResult"
        if($copyResult.ResultFoundInLog -eq $true -and $copyResult.FilesFAILED -eq 0 -and $copyResult.DirsFAILED -eq 0)
        {    
            Write-CMTraceLog -Message "Copy process successful. Logfile: `"$RobocopyLogPath`""
            Write-CMTraceLog -Message " "
        }
        else
        {
            Write-CMTraceLog -Message "Copy process failed. Logfile: `"$RobocopyLogPath`"" -Type Error -LogType LogAndEventlog
            Write-CMTraceLog -Message "Stopping script!" -Type Warning
            Invoke-StopScriptIfError   
        }
    
    }
#endregion


#region Rename-FolderCustom
#-----------------------------------------
Function Rename-FolderCustom
{

#Validate path and write log or eventlog
[CmdletBinding()]
Param
(
    #Path to test
    [parameter(Mandatory=$True,ValueFromPipeline=$true)]
    $Folder
)

begin{}
    
process
    {
        foreach ($folderName in $Folder)
        {
            [string]$folderDateTimeSuffix = (Get-Date -Format yyyyMMdd-HHmmss).ToString()
            [string]$newFolderName = "{0}-{1}" -f $folderName.Name, $folderDateTimeSuffix

  
            try{
                Rename-Item -Path $folderName.Fullname -NewName $newFolderName -Force -ErrorAction Stop
            }
            Catch{
                Write-CMTraceLog -Message "Folder -$($folderName.Fullname)- could not be renamed. Error: $($error[0].Exception)" -LogType 'LogAndEventlog' -type error
                Invoke-StopScriptIfError
            }
            Write-CMTraceLog -Message "Rename successful. Previous: $($folderName.Fullname) New: $newFolderName"
        }
    }
 
end
  {
        Write-CMTraceLog -Message "-------------------------------------"
  }

}
#-----------------------------------------
#endregion


#region Delete-OldFolders
#-----------------------------------------
Function Delete-OldFolders
{

#Validate path and write log or eventlog
[CmdletBinding()]
Param(
      #Path to test
      [parameter(Mandatory=$True,ValueFromPipeline=$true)]
      $Folder,
      [parameter(Mandatory=$True,ValueFromPipeline=$false)]
      $MaxBackupDays

    )


begin
    {
        Write-CMTraceLog -Message "Start delete of old folders"
    }
 
process
    {
        foreach ($folderName in $Folder)
        {
            Write-CMTraceLog -Message "Will work on folder: `"$($folderName.Name)`""
            # determine timespan between today and the creation time of the folder | Example: 2014-10-20T0933259633693
            # Using folder name instead of actual creation date, to prevent copied folders to be removed
            # Will work with 
            $Matches = $null # Reset matches
            $timeSpan = $null # Reset timespan
            # Type1 = "2022-06-14T015442" from "2022-06-14T015442-P02Backup"
            # Type2 = "20220614-045715"   from "P02Backup-20220614-045715"
            $outVar = $folderName.Name -match '(?<type1>\d{4}-\d{2}-\d{2}T\d{6})|(?<type2>\d{8}-\d{6})'
            Switch ($Matches.Keys)
            {
                "type1" {
                            $datetimeString = $Matches[0].Substring(0,10)
                            $datetimeObj = [Datetime]::ParseExact($datetimeString, 'yyyy-MM-dd', $null)
                        }
                "type2" {
                            $datetimeString = $Matches[0].Substring(0,8)
                            $datetimeObj = [Datetime]::ParseExact($datetimeString, 'yyyyMMdd', $null)
                        }
            }
            $timeSpan = New-TimeSpan -Start (Get-Date) -End ($datetimeObj)

            if (-NOT $timeSpan)
            {
                Write-CMTraceLog -Message "Not able to determine creationdate based on foldername for: `"$folderName`"" -Type warning
                Write-CMTraceLog -Message "Threfore not able to delete folder!" -Type warning
            }
            else 
            {
                if ($timeSpan.Days -ge -$MaxBackupDays)
                {
                    Write-CMTraceLog -Message "Folder not old enough: $($timeSpan.Days) days."
                }
                else
                {
                    Write-CMTraceLog -Message "Folder too old: $($timeSpan.Days) days. Will delete!" -type warning
                    try
                    {
                        # OLD:Changed in V1.2 Remove-Item -Path $folderName.Fullname -Recurse -Force -ErrorAction Stop
                        $del_cmdcommand = ''
                        $del_cmdcommand = 'rd /S /Q ' + $folderName.Fullname
                        cmd /c $del_cmdcommand
                    }
                    Catch
                    {
                        Write-CMTraceLog -Message "Folder `"$($folderName.Fullname)`" delete not successful. Error: $($error[0].Exception)" -LogType 'LogAndEventlog' -type error
                        Invoke-StopScriptIfError
                    }
                    Write-CMTraceLog -Message "Delete successful! `"$($folderName.Fullname)`"" -LogType 'LogAndEventlog'
                }            
            }
        }
    }
 
end
  {
        Write-CMTraceLog -Message "-------------------------------------"
  }

}
#-----------------------------------------
#endregion

#region Get-ConfigMgrSiteInfo
function Get-ConfigMgrSiteInfo
{
    [array]$propertyList  = $null
    $propertyList += 'SiteCode'
    $propertyList += 'ParentSiteCode'
    $propertyList += 'InstallDirectory'
    $propertyList += 'SiteName'
    $propertyList += 'SiteServerDomain'
    $propertyList += 'SiteServerName'
    $propertyList += 'SiteServerPlatform'
    $propertyList += 'SiteType'
    $propertyList += 'SQLDatabaseName'
    $propertyList += 'SQLServerName'
    $propertyList += 'SQLDatabase'
    $propertyList += 'SQLInstance'
    $propertyList += 'SQLDatabaseFile'
    $propertyList += 'SQLDatabaseLogFile'
    $propertyList += 'SQLServerSSBCertificateThumbprint'
    $propertyList += 'SQLSSBPort' # was 'SSBPort'
    $propertyList += 'SQLServicePort'
    $propertyList += 'LocaleID'
    $propertyList += 'FullVersion'
    $propertyList += 'SUPList'
    $propertyList += 'SSRSList'
    $propertyList += 'CloudConnector'
    $propertyList += 'CloudConnectorServer'
    $propertyList += 'CloudConnectorOfflineMode'
    $propertyList += 'SMSProvider'
    $propertyList += 'BackupPath'
    $propertyList += 'BackupEnabled'
    $propertyList += 'ConsoleInstalled'
    $outObject = New-Object psobject | Select-Object $propertyList

    $providerLocation = Get-CimInstance -Namespace "root\sms" -Query 'Select * From SMS_ProviderLocation Where ProviderForLocalSite=1' -ErrorAction Stop | Select-Object -First 1
    if ($providerLocation)
    {
        $SiteCode = $providerLocation.SiteCode

        $outObject.SiteCode = $SiteCode
        $outObject.SMSProvider = $providerLocation.Machine
        $outObject.CloudConnector = 0 # setting service connection point to not installed. Will change later if detected as installed
        $outObject.ConsoleInstalled = 0 # same as with cloud connector  
        
        $siteDefinition = Get-CimInstance -Namespace "root\sms\site_$SiteCode" -query "SELECT * FROM SMS_SCI_SiteDefinition WHERE FileType=2 AND ItemName='Site Definition' AND ItemType='Site Definition' AND SiteCode='$($SiteCode)'"
        if ($siteDefinition)
        {
            $outObject.ParentSiteCode = $siteDefinition.ParentSiteCode
            $outObject.InstallDirectory = $siteDefinition.InstallDirectory
            $outObject.SiteName = $siteDefinition.SiteName
            $outObject.SiteServerDomain = $siteDefinition.SiteServerDomain
            $outObject.SiteServerName = $siteDefinition.SiteServerName
            $outObject.SiteServerPlatform = $siteDefinition.SiteServerPlatform
            $outObject.SiteType = $siteDefinition.SiteType
            $outObject.SQLDatabaseName = $siteDefinition.SQLDatabaseName
            $outObject.SQLServerName = $siteDefinition.SQLServerName

            # Extract DB Info
            $sqlDBInfo = $outObject.SQLDatabaseName -split '\\'
            if ($sqlDBInfo.Count -eq 2)
            {
                $outObject.SQLDatabase = $sqlDBInfo[1]
                $outObject.SQLInstance = $sqlDBInfo[0]
            }
            else
            {
                $outObject.SQLDatabase = $sqlDBInfo
                $outObject.SQLInstance = "Default"
            }

            # Adding filenames
            $outObject.SQLDatabaseFile = "{0}.mdf" -f $outObject.SQLDataBase
            $outObject.SQLDatabaseLogFile = "{0}_log.ldf" -f $outObject.SQLDataBase
            # Adding SQL Port info
            $outObject.SQlServicePort = ($siteDefinition.props | Where-Object {$_.PropertyName -eq 'SQlServicePort'} | Select-Object -ExpandProperty Value)
            $outObject.SQLSSBPort = ($siteDefinition.props | Where-Object {$_.PropertyName -eq 'SSBPort'} | Select-Object -ExpandProperty Value)
            # Adding language and version
            $outObject.LocaleID = ($siteDefinition.props | Where-Object {$_.PropertyName -eq 'LocaleID'} | Select-Object -ExpandProperty Value)
            $outObject.FullVersion = ($siteDefinition.props | Where-Object {$_.PropertyName -eq 'Full Version'} | Select-Object -ExpandProperty Value1)

            # get list of role servers
            $SysResUse = Get-CimInstance -Namespace "root\sms\site_$SiteCode" -query "select * from SMS_SCI_SysResUse where SiteCode = '$($SiteCode)'" | Select-Object NetworkOsPath, RoleName, PropLists, Props 
            if ($SysResUse)
            {
                $outSupListObj = New-Object System.Collections.ArrayList
                # Iterate through each SUP
                $supList = ($SysResUse | Where-Object {$_.RoleName -eq 'SMS Software Update Point'}) 
                foreach ($sup in $supList)
                {
                    $propertyList = $null
                    $propertyList += 'SUPName'
                    $propertyList += 'UseProxy'
                    $propertyList += 'ProxyName'
                    $propertyList += 'ProxyServerPort'
                    $propertyList += 'AnonymousProxyAccess'
                    $propertyList += 'UserName'
                    $propertyList += 'UseProxyForADR'
                    $propertyList += 'IsIntranet'
                    $propertyList += 'Enabled'
                    $propertyList += 'DBServerName'
                    $propertyList += 'WSUSIISPort'
                    $propertyList += 'WSUSIISSSLPort'
                    $propertyList += 'SSLWSUS'
                    $propertyList += 'UseParentWSUS'
                    $propertyList += 'WSUSAccessAccount'
                    $propertyList += 'AllowProxyTraffic' # CMG traffic
                    $tmpSupObj = New-Object pscustomobject | Select-Object $propertyList

                    $tmpSupObj.SUPName = $sup.NetworkOsPath -replace '\\\\',''
                    $tmpSupObj.UseProxy = $sup.props | Where-Object {$_.PropertyName -eq 'UseProxy'} | Select-Object Value -ExpandProperty Value
                    $tmpSupObj.ProxyName = $sup.props | Where-Object {$_.PropertyName -eq 'ProxyName'} | Select-Object Value -ExpandProperty Value
                    $tmpSupObj.ProxyServerPort = $sup.props | Where-Object {$_.PropertyName -eq 'ProxyServerPort'} | Select-Object Value -ExpandProperty Value
                    $tmpSupObj.AnonymousProxyAccess = $sup.props | Where-Object {$_.PropertyName -eq 'AnonymousProxyAccess'} | Select-Object Value -ExpandProperty Value
                    $tmpSupObj.UserName = $sup.props | Where-Object {$_.PropertyName -eq 'UserName'} | Select-Object Value -ExpandProperty Value
                    $tmpSupObj.UseProxyForADR = $sup.props | Where-Object {$_.PropertyName -eq 'UseProxyForADR'} | Select-Object Value -ExpandProperty Value
                    $tmpSupObj.Enabled = $sup.props | Where-Object {$_.PropertyName -eq 'Enabled'} | Select-Object Value -ExpandProperty Value
                    $tmpSupObj.DBServerName = $sup.props | Where-Object {$_.PropertyName -eq 'DBServerName'} | Select-Object Value2 -ExpandProperty Value2
                    $tmpSupObj.WSUSIISPort = $sup.props | Where-Object {$_.PropertyName -eq 'WSUSIISPort'} | Select-Object Value -ExpandProperty Value
                    $tmpSupObj.WSUSIISSSLPort = $sup.props | Where-Object {$_.PropertyName -eq 'WSUSIISSSLPort'} | Select-Object Value -ExpandProperty Value
                    $tmpSupObj.SSLWSUS = $sup.props | Where-Object {$_.PropertyName -eq 'SSLWSUS'} | Select-Object Value -ExpandProperty Value
                    $tmpSupObj.UseParentWSUS = $sup.props | Where-Object {$_.PropertyName -eq 'UseParentWSUS'} | Select-Object Value -ExpandProperty Value
                    $tmpSupObj.WSUSAccessAccount = $sup.props | Where-Object {$_.PropertyName -eq 'WSUSAccessAccount'} | Select-Object Value -ExpandProperty Value
                    $tmpSupObj.AllowProxyTraffic = $sup.props | Where-Object {$_.PropertyName -eq 'AllowProxyTraffic'} | Select-Object Value -ExpandProperty Value
                    [void]$outSupListObj.add($tmpSupObj)

                }
                $outObject.SUPList = $outSupListObj

                $outSSRSListObj = New-Object System.Collections.ArrayList
                # Iterate through each SSRS
                $ssrsList = ($SysResUse | Where-Object {$_.RoleName -eq 'SMS SRS Reporting Point'})
                foreach ($ssrs in $ssrsList)
                {
                    $propertyList = $null
                    $propertyList += 'SSRSName'
                    $propertyList += 'DatabaseServerName'
                    $propertyList += 'RootFolder'
                    $propertyList += 'ReportServerInstance'
                    $propertyList += 'Username'
                    $propertyList += 'ReportServerUri'
                    $propertyList += 'ReportManagerUri'
                    $propertyList += 'Version'
                    $tmpSSRSObj = New-Object pscustomobject | Select-Object $propertyList

                    $tmpSSRSObj.SSRSName = $ssrs.NetworkOsPath -replace '\\\\',''
                    $tmpSSRSObj.DatabaseServerName = $ssrs.props | Where-Object {$_.PropertyName -eq 'DatabaseServerName'} | Select-Object Value2 -ExpandProperty Value2
                    $tmpSSRSObj.ReportServerInstance = $ssrs.props | Where-Object {$_.PropertyName -eq 'ReportServerInstance'} | Select-Object Value2 -ExpandProperty Value2
                    $tmpSSRSObj.ReportManagerUri = $ssrs.props | Where-Object {$_.PropertyName -eq 'ReportManagerUri'} | Select-Object Value2 -ExpandProperty Value2
                    $tmpSSRSObj.ReportServerUri = $ssrs.props | Where-Object {$_.PropertyName -eq 'ReportServerUri'} | Select-Object Value2 -ExpandProperty Value2
                    $tmpSSRSObj.RootFolder = $ssrs.props | Where-Object {$_.PropertyName -eq 'RootFolder'} | Select-Object Value2 -ExpandProperty Value2
                    $tmpSSRSObj.Username = $ssrs.props | Where-Object {$_.PropertyName -eq 'Username'} | Select-Object Value2 -ExpandProperty Value2
                    $tmpSSRSObj.Version = $ssrs.props | Where-Object {$_.PropertyName -eq 'Version'} | Select-Object Value2 -ExpandProperty Value2
                   
                    [void]$outSSRSListObj.add($tmpSSRSObj)
                    
                }
                $outObject.SSRSList = $outSSRSListObj


                $CloudConnectorServer = ($SysResUse | Where-Object {$_.RoleName -eq 'SMS Dmp Connector'})
                if ($CloudConnectorServer)
                {
                    $outObject.CloudConnector = 1
                    $outObject.CloudConnectorServer = ($CloudConnectorServer.NetworkOsPath -replace '\\\\','') 
                    $outObject.CloudConnectorOfflineMode = (($CloudConnectorServer.Props | Where-Object {$_.PropertyName -eq 'OfflineMode'}).value)
                }               
            }
            else
            {
                return $false
            }

            $backupInfo = Get-CimInstance -Namespace "root\sms\site_$SiteCode" -query "SELECT * FROM SMS_SiteControlItem where ItemName = 'Backup SMS Site Server' and SiteCode = '$($SiteCode)'"
            if ($backupInfo)
            {
                $outObject.BackupEnabled = $backupInfo.Enabled
                $outObject.BackupPath = $backupInfo.DeviceName
            }
            else
            {
                return $false
            }

            # Is console installed on site server?
            if (Get-ItemProperty -Path HKLM:\SOFTWARE\WOW6432Node\Microsoft\ConfigMgr10\AdminUI -Name 'AdminUILog' -ErrorAction SilentlyContinue)
            {
                $outObject.ConsoleInstalled = 1
            }
        }
        else
        {
            return $false
        }
    }
    else
    {
        return $false
    }

    return $outObject
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


#region New-ZipFile
#-----------------------------------------
Function New-ZipFile{
[CmdletBinding()]
Param(
   
      #max Size in KB
      [parameter(Mandatory=$True,ValueFromPipeline=$true)]
      [string]$FolderToArchive,
      [parameter(Mandatory=$True,ValueFromPipeline=$false)]
      [string]$PathToSaveFileTo,
      [parameter(Mandatory=$True,ValueFromPipeline=$false)]
      [string]$TempZipFileFolder,
      [parameter(Mandatory=$True,ValueFromPipeline=$false)]
      [ValidateSet("Yes","No")]
      [string]$UseStaticFolderName = 'No',
      [string]$FileName = 'CustomBackup'
    )

    begin
    {
        Write-Verbose "Start Zip process"
        $random = Get-Random
        $newTempFolder = md "$TempZipFileFolder\$random" -ErrorAction Stop
       Write-Verbose "Temp folder is: $newTempFolder"
    }
 
    process
    {
        # create one zip file for each folder to support folders with same name
        foreach ($folderName in $FolderToArchive)
        {
            if($UseStaticFolderName -ieq 'No')
            {
                $i=0
                do
                {
                    # find ununsed filenames e.g. / 0.zip / 1.zip /3.zip
                    $i++
                    $ZipFileName = "$newTempFolder\$i.zip"
    
                }while(Test-Path $ZipFileName)

                # write Info file with sourcefolder and zipfilename
                $infoLine = "$FolderToArchive = $i.zip"
                $infoLine | Out-File -Append -Encoding UTF8 -FilePath "$newTempFolder\$i-README.txt" -Force -ErrorAction SilentlyContinue
            }
            else
            {
                $ZipFileName = "$newTempFolder\$FileName.zip"
            }


            # create zip file       
            Write-CMTraceLog -Message "Will compress folder: `"$folderName`"" -Component ($MyInvocation.MyCommand.Name)
            try
            {
                Add-Type -Assembly System.IO.Compression.FileSystem -ErrorAction Stop
                $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
                [System.IO.Compression.ZipFile]::CreateFromDirectory($folderName, $ZipFileName, $compressionLevel, $false)
            }
            Catch
            {
                Write-CMTraceLog -Message "Folder compression failed!" -Component ($MyInvocation.MyCommand.Name) -Type Error -LogType 'LogAndEventlog' 
                Write-CMTraceLog -Message "$($error[0].Exception)" -Component ($MyInvocation.MyCommand.Name) -Type Error -LogType 'LogAndEventlog'
                Invoke-StopScriptIfError
            }
            Write-CMTraceLog -Message "Compression of folder done!" -Component ($MyInvocation.MyCommand.Name)
        }
     }
     
    end
    {
        # copy zip files
        Write-CMTraceLog -Message "Copy zip files to: `"$PathToSaveFileTo`""
        try
        {
            # create folder with empty file
            New-Item -ItemType directory -Path "$PathToSaveFileTo" -Force | Out-Null 
            Copy-Item -Path $ZipFileName $PathToSaveFileTo -Force -Recurse -Container -ErrorAction Stop
        }
        Catch
        {
            Write-CMTraceLog "Error: $($error[0].Exception)" -LogType 'LogAndEventlog' -Type Error -LogType 'LogAndEventlog'
            Invoke-StopScriptIfError
        }

        Write-CMTraceLog -Message "Delete temp folder: `"$newTempFolder`""
        try
        {
            Remove-Item -Path $newTempFolder -Recurse -Force -ErrorAction Stop
        }
        Catch
        {
            Write-CMTraceLog -Message "Error: $($error[0].Exception)" -LogType 'LogAndEventlog' -Type Error
            Write-CMTraceLog -Message "Skipping deletion..."
        }
    }

}
#-----------------------------------------
#endregion


#region Get-InstalledWindowsFeatureAsInstallString
#-----------------------------------------
function Get-InstalledWindowsFeatureAsInstallString{

    $InstallString = "Install-WindowsFeature -Name"
    $i = 0
    (Get-WindowsFeature | Where-Object installed | Select-Object Name).Foreach({ 
    
        if($i -eq 0)
        {
            $InstallString = "$InstallString $($_.Name)"
        }
        else
        {
            $InstallString = "$InstallString,$($_.Name)"
        }
        $i++

    })

    return $InstallString
}
#-----------------------------------------
#endregion


#region Backup-WebConfigurationAndCopyFolder
#-----------------------------------------
function Backup-WebConfigurationAndCopyFolder 
{
    param
    (
        [string]$BackupPath,
        [string]$RecoveryScriptFileName
    )
    
    [string]$IISBackupFolder = "$env:windir\system32\inetsrv\backup"


$restoreWebConfigScript = @'

$scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
Copy-Item -Path "$scriptPath\$BackupName" -Destination "$env:windir\system32\inetsrv\backup" -Force -Recurse
Restore-WebConfiguration -Name $BackupName

'@

    #check if cmdlet exists
    if(-NOT(Get-Module WebAdministration))
    {
        Import-Module WebAdministration
        Write-CMTraceLog -Message "Needed to run `"Import-Module WebAdministration`"" -Component ($MyInvocation.MyCommand.Name)
    }
    
    if(Get-Command Backup-WebConfiguration -ErrorAction SilentlyContinue)
    {
        Write-CMTraceLog -Message "Backup-WebConfiguration cmdlet found!" -Component ($MyInvocation.MyCommand.Name)
    }
    else
    {
        Write-CMTraceLog -Message "Backup-WebConfiguration cmdlet not found" -Component ($MyInvocation.MyCommand.Name) -Type Error -LogType 'LogAndEventlog'
        Invoke-StopScriptIfError
    }

    $WebConfigurationBackupName = 'WebBackup_{0}' -f (Get-Date -format 'yyy-MM-ddThhmmss')
    try
    {
        Write-CMTraceLog -Message "Creating IIS backup..." -Component ($MyInvocation.MyCommand.Name)
        Backup-WebConfiguration -Name $WebConfigurationBackupName | Out-Null
    
    }
    catch
    {
        Write-CMTraceLog -Message "IIS backup failed" -Component ($MyInvocation.MyCommand.Name) -Type Error -LogType 'LogAndEventlog'
        Write-CMTraceLog -Message "$($error[0].Exception)" -Component ($MyInvocation.MyCommand.Name) -Type Error
        Invoke-StopScriptIfError 
    }

    try
    {
        Write-CMTraceLog -Message "Copy `"$IISBackupFolder\$WebConfigurationBackupName`" to `"$BackupPath`"" -Component ($MyInvocation.MyCommand.Name)
        Copy-Item -Path "$IISBackupFolder\$WebConfigurationBackupName" $BackupPath -Recurse -Force -ErrorAction Stop

        Write-CMTraceLog -Message "Create `"$RecoveryScriptFileName`"" -Component ($MyInvocation.MyCommand.Name)
        # adding correct variable value to recovery ps1 file.
        '$BackupName = "{0}"' -f $($WebConfigurationBackupName) | Out-File -FilePath "$RecoveryScriptFileName" -Force
        $restoreWebConfigScript | Out-File -FilePath "$RecoveryScriptFileName" -Append
    }
    catch
    {
        Write-CMTraceLog -Message "Copy IIS backup failed" -Component ($MyInvocation.MyCommand.Name) -Type Error -LogType 'LogAndEventlog'
        Write-CMTraceLog -Message "$($error[0].Exception)" -Component ($MyInvocation.MyCommand.Name) -Type Error
        Invoke-StopScriptIfError       
    }

    #delete older backups to avoid having multiple backups
    Get-ChildItem $IISBackupFolder | Where-Object {$_.name -ne $WebConfigurationBackupName} | ForEach-Object {

        Write-CMTraceLog -Message "Delete temp IIS Backup files: `"$($_.FullName)`"" -Component ($MyInvocation.MyCommand.Name)
        
        try
        {
            $del_cmdcommand = "rd /S /Q $($_.FullName)"
            cmd /c $del_cmdcommand
        }
        Catch
        {
            Write-CMTraceLog -Message "Delete failed: $($error[0].InnerException)" -Component ($MyInvocation.MyCommand.Name) -Type Error
            Write-CMTraceLog -Message "Will ignore error and continue" -Component ($MyInvocation.MyCommand.Name) -Type Warning
        }
     }
}
#-----------------------------------------
#endregion


#region Export-ScheduledTasksCustom 
Function Export-ScheduledTasksCustom 
{
    param
    (
        [string]$BackupFolder,
        [string]$TaskPathRoot,
        [string]$RecoveryScriptFileName
    )

$ImportScript = @'
function Import-ScheduledTasksCustom {
  [CmdletBinding()]
  param
  (
      [parameter(Mandatory=$True,ValueFromPipeline=$true)]
      $TaskXMFile
  )
 
  begin {
      
  }
 
  process {
 
    write-host "Beginning process loop"
 
    foreach ($TaskXML in $TaskXMFile) {
      
      if ($pscmdlet.ShouldProcess($computer)) {
        
            $InfofilePath = "$($TaskXML.DirectoryName)\$($TaskXML.BaseName)_Infofile.txt"
            $InfofilePath
            if(Test-Path -Path $InfofilePath){
                $Task = Get-Content $TaskXML.FullName | Out-String
                $TaskName = $TaskXML.BaseName
                $TaskPath = (Get-Content $InfofilePath).Replace('TaskPath:','')

                Register-ScheduledTask -Xml $Task -TaskName $TaskName -TaskPath $TaskPath -Force

             }else{
             
                Write-Host "infofile not found"
             }

      }
    }
  }
} 
 

$scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

dir "$scriptPath\ScheduledTasks" -Filter '*.xml' | Import-ScheduledTasksCustom
'@
    

    $ImportScript | Out-File -FilePath "$RecoveryScriptFileName" -Force
    $BackupFolder = "$BackupFolder\ScheduledTasks"
    $Tasks = Get-ScheduledTask | Where-Object {$_.Taskpath -like "*$TaskPathRoot*"} 

    if (-NOT ($Tasks))
    {
        Write-CMTraceLog -Message "No scheduled tasks found in: `"$TaskPathRoot`"" -Component ($MyInvocation.MyCommand.Name) -Type Error -LogType LogAndEventlog
        Invoke-StopScriptIfError
    }
    else 
    { 
        $Tasks | ForEach-Object {

            Write-CMTraceLog -Message "Backup of scheduled task: $($_.TaskName)" -Component ($MyInvocation.MyCommand.Name)
            
            New-Item -ItemType directory -Path "$BackupFolder" -Force | Out-Null

            $filePath = "$BackupFolder\$($_.TaskName).xml"

            "TaskPath:$($_.Taskpath)" | Out-File "$BackupFolder\$($_.TaskName)_Infofile.txt"
            
            try 
            {
                Export-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath | out-file -FilePath $filePath -Force -ErrorAction Stop
            }
            catch 
            {
                Write-CMTraceLog -Message "Not able to export scheduled task: `"$($_.TaskName)`"" -Component ($MyInvocation.MyCommand.Name) -Type Error -LogType LogAndEventlog
                Invoke-StopScriptIfError
            }
            
        
        }
    }
}
#endregion


#region Export-SSRSReports
function Export-SSRSReports
{
    param
    (
        [object]$SiteInfo,
        [string]$BackupPath
    )

    try
    {
        foreach ($SSRSServer in $SiteInfo.SSRSList) 
        {
            $ReportServerUri = $SSRSServer.ReportServerUri
            #$ReportServerUri

            $ReportServerRemoteName = $SSRSServer.SSRSName
            #$ReportServerRemoteName

            # set FQDN as SSRS uri if not already present
            if($ReportServerUri -notcontains $ReportServerRemoteName)
            {
                $ReportServerUri = $ReportServerUri -replace '(//.*/)',"//$ReportServerRemoteName/"
            }
            $ReportServerUri = "$ReportServerUri/ReportService2010.asmx?wsdl"
            #$ReportServerUri

            Write-CMTraceLog -Message "Connecting to: `"$ReportServerUri`""
            $Proxy = New-WebServiceProxy -Uri $ReportServerUri -Namespace "SSRS" -UseDefaultCredential ;
 
            #check out all members of $Proxy
            #$Proxy | Get-Member
            #http://msdn.microsoft.com/en-us/library/aa225878(v=SQL.80).aspx

            #second parameter means recursive
            $items = $Proxy.ListChildren("/", $true) | Select-Object TypeName, Path, ID, Name | Where-Object {$_.TypeName -eq "Report" -or $_.TypeName -eq "DataSet"};

            #create a new folder where we will save the files
            #PowerShell datetime format codes http://technet.microsoft.com/en-us/library/ee692801.aspx
 
            #create a timestamped folder, format similar to 2011-Mar-28-0850PM
            $folderName = "SSRS-{0}" -f (Get-Date -Format yyyyMMdd-HHmmss).ToString()
            $fullFolderName = "$BackupPath\$folderName";
            [System.IO.Directory]::CreateDirectory($fullFolderName) | out-null
            Write-CMTraceLog -Message "Exporting $($items.Count) reports to: `"$fullFolderName`""
            foreach($item in $items)
            {
                #need to figure out if it has a folder name
                $subfolderName = split-path $item.Path;
                $reportName = split-path $item.Path -Leaf;
                $fullSubfolderName = $fullFolderName + $subfolderName;
                if(-not(Test-Path $fullSubfolderName))
                {
                    #note this will create the full folder hierarchy
                    [System.IO.Directory]::CreateDirectory($fullSubfolderName) | out-null
                }

                if($item.TypeName -eq 'DataSet')
                {

                    $fullReportFileName = $fullSubfolderName + "\" + $item.Name +  ".rsd";
                }
                else
                {
                    $fullReportFileName = $fullSubfolderName + "\" + $item.Name +  ".rdl";
                }

                if($fullReportFileName.Length -ge 256)
                {
                    Write-CMTraceLog -Message "Not able to export report since the name is $($fullReportFileName.Length) characters long!" -Type Warning
                    Write-CMTraceLog -Message "Name: `"$fullReportFileName`""
                }
                else
                {
                    Write-Verbose "FileNameLength: $(($fullReportFileName.Length).ToString("000")) => `"$fullReportFileName`""
                    $bytes = $Proxy.GetItemDefinition($item.Path)
                    [System.IO.File]::WriteAllBytes("$fullReportFileName", $bytes)
                }
            } # end foreach($item in $items)
        } # end foreach ($SSRSServer in $SiteInfo.SSRSList)
    }
    catch
    {
        Write-CMTraceLog -Message "ERROR: $($error[0].Exception)" -Type Error -LogType 'LogAndEventlog'
        Invoke-StopScriptIfError
    }
}
#endregion

#region Get-InstalledADKInfo
function Get-InstalledADKInfo
{
    $adkInstallPath = "Registry::HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots" 

    $adkInfo = Get-ChildItem $adkInstallPath -ErrorAction SilentlyContinue
    if($adkInfo)
    {
        $outObject = New-Object psobject | Select-Object ADKVersion, InstalledItems
        $outObject.ADKVersion = $adkInfo| Split-Path -leaf
        
        $adkInstalledItems = Get-ChildItem "$adkInstallPath\$adkVersion" -Recurse -ErrorAction SilentlyContinue
        if($adkInstalledItems)
        {
            $outObject.InstalledItems = $adkInstalledItems.Property
        }

    }
    else
    {
        return $false
    }
    return $outObject
}
#endregion

#region New-ConfigMgrRecoveryFile
<#
.Synopsis
    New-ConfigMgrRecoveryFile will create a new ConfigMgr unattend recovery ini file
.DESCRIPTION
    New-ConfigMgrRecoveryFile will create a new ConfigMgr unattend recovery ini file
    Refer to the documentation for more informations: https://docs.microsoft.com/en-us/mem/configmgr/core/servers/manage/unattended-recovery
#>
Function New-ConfigMgrRecoveryFile
{
    param
    (
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$IniFilePathAndName,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [ValidateSet("RecoverPrimarySite","RecoverCCAR")] # RecoverCCAR = CAS recovery
        [string]$Action,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [ValidateSet("0-NotFromCDLatest","1-FromCDLatest")] # 
        [string]$CDLatest,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [ValidateSet("1-SiteServerAndSQLServer","2-SiteServerOnly","4-SQLServerOnly")] # What components to recover-> 1: Site server and SQL Server, 2: Site server only, 4: SQL Server only
        [string]$ServerRecoveryOptions,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [ValidateSet("10-RestoreFromBackup","20-ManuallyRecovered","40-CreateNewDatabase","80-Skip")] # 10: Restore from backup, 20: Manually recovered, 40: Create new database, 80: Skip
        [string]$DatabaseRecoveryOptions, # Specify how setup recovers the site database in SQL Server. * Only required when ServerRecoveryOptions is 1 or 4.
         [parameter(Mandatory=$False,ValueFromPipeline=$false)]
        [string]$ReferenceSite, # FQDN of reference site. The reference primary site that the CAS uses to recover global data. * Only required when DatabaseRecoveryOptions is 40. See note 5
        [parameter(Mandatory=$False,ValueFromPipeline=$false)]        
        [string]$SiteServerBackupLocation, # The path to the site server backup set. If you don't specify a value, setup reinstalls the site without restoring it from a backup set.   
        [parameter(Mandatory=$False,ValueFromPipeline=$false)] 
        [string]$BackupLocation, # The path to the site database backup set. * Required when ServerRecoveryOptions is 1 or 4, and DatabaseRecoveryOptions is 10.
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$ProductID,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$SiteCode,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$SiteName,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$SMSInstallDir,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$SDKServer,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$PrerequisiteComp,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$PrerequisitePath,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$AdminConsole,
        [parameter(Mandatory=$False,ValueFromPipeline=$false)]
        [int]$JoinCEIP=0,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$SQLServerName,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [int]$SQLServerPort,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$DatabaseName,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [int]$SQLSSBPort,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$CloudConnector,
        [parameter(Mandatory=$False,ValueFromPipeline=$false)]
        [string]$CloudConnectorServer,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$UseProxy,
        [parameter(Mandatory=$False,ValueFromPipeline=$false)]
        [string]$ProxyName,
        [parameter(Mandatory=$False,ValueFromPipeline=$false)]
        [string]$ProxyPort,
        [parameter(Mandatory=$False,ValueFromPipeline=$false)]
        [string]$CCARSiteServer
        #>
    )
 
    # What type to recover
    # Recover a primary site
    # Recover a CAS
    "[Identification]" | out-file -FilePath $IniFilePathAndName -Force
    "Action={0}" -f $Action | out-file -FilePath $IniFilePathAndName -Append

    # When you run setup from the CD.Latest folder, include this key and value. This value tells setup that you're using media from CD.Latest.
    if ($CDLatest -eq "1-FromCDLatest")
    {
        "CDLatest=1" | out-file -FilePath $IniFilePathAndName -Append
    }

    "" | out-file -FilePath $IniFilePathAndName -Append
    "[RecoveryOptions]" | out-file -FilePath $IniFilePathAndName -Append
    # What components to recover
    # 1: Site server and SQL Server
    # 2: Site server only
    # 4: SQL Server only
    $ServerRecoveryOptionsValue = $ServerRecoveryOptions.Substring(0,1)
    "ServerRecoveryOptions={0}" -f $ServerRecoveryOptionsValue | out-file -FilePath $IniFilePathAndName -Append

    # Specify how setup recovers the site database in SQL Server. * Only required when ServerRecoveryOptions is 1 or 4.
    # 10: Restore from backup
    # 20: Manually recovered
    # 40: Create new database
    # 80: Skip
    $DatabaseRecoveryOptionsValue = $DatabaseRecoveryOptions.Substring(0,2)
    if ($ServerRecoveryOptionsValue -in (1,4))
    {
        "DatabaseRecoveryOptions={0}" -f $DatabaseRecoveryOptionsValue | out-file -FilePath $IniFilePathAndName -Append
    }

    # The reference primary site that the CAS uses to recover global data. * Only required when DatabaseRecoveryOptions is 40.
    if ($DatabaseRecoveryOptionsValue -eq 40)
    {
        if (-NOT ($ReferenceSite))
        {
            Write-Warning  'ReferenceSite parameter required if -Create new database- is set.'
        }
        else
        {
            "ReferenceSite={0}" -f $ReferenceSite | out-file -FilePath $IniFilePathAndName -Append  
        }
    }

    # The path to the site server backup set. If you don't specify a value, setup reinstalls the site without restoring it from a backup set.
    if ($SiteServerBackupLocation)
    {
        "SiteServerBackupLocation={0}" -f $SiteServerBackupLocation | out-file -FilePath $IniFilePathAndName -Append 
    }

    # The path to the site database backup set. * Required when ServerRecoveryOptions is 1 or 4, and DatabaseRecoveryOptions is 10.
    if (($ServerRecoveryOptionsValue -in (1,4)) -and ($DatabaseRecoveryOptionsValue -eq 10))
    {
        if (-NOT ($BackupLocation))
        {
            Write-Warning  'BackupLocation parameter required when ServerRecoveryOptions is 1 or 4, and DatabaseRecoveryOptions is 10'
        }
        else
        {
            "BackupLocation={0}" -f $BackupLocation | out-file -FilePath $IniFilePathAndName -Append  
        }    
    }

    "" | out-file -FilePath $IniFilePathAndName -Append
    "[Options]" | out-file -FilePath $IniFilePathAndName -Append
    "ProductID={0}" -f $ProductID | out-file -FilePath $IniFilePathAndName -Append
    "SiteCode={0}" -f $SiteCode | out-file -FilePath $IniFilePathAndName -Append
    "SiteName={0}" -f $SiteName | out-file -FilePath $IniFilePathAndName -Append
    "SMSInstallDir={0}" -f $SMSInstallDir | out-file -FilePath $IniFilePathAndName -Append
    "SDKServer={0}" -f $SDKServer | out-file -FilePath $IniFilePathAndName -Append
    "PrerequisiteComp={0}" -f $PrerequisiteComp | out-file -FilePath $IniFilePathAndName -Append
    "PrerequisitePath={0}" -f $PrerequisitePath | out-file -FilePath $IniFilePathAndName -Append
    if ($ServerRecoveryOptionsValue -in (1,2))
    {
        "AdminConsole={0}" -f $AdminConsole | out-file -FilePath $IniFilePathAndName -Append
    }
    "JoinCEIP={0}" -f $JoinCEIP | out-file -FilePath $IniFilePathAndName -Append

    "" | out-file -FilePath $IniFilePathAndName -Append
    "[SQLConfigOptions]" | out-file -FilePath $IniFilePathAndName -Append
    "SQLServerName={0}" -f $SQLServerName | out-file -FilePath $IniFilePathAndName -Append
    "SQLServerPort={0}" -f $SQLServerPort | out-file -FilePath $IniFilePathAndName -Append
    "DatabaseName={0}" -f $DatabaseName | out-file -FilePath $IniFilePathAndName -Append
    "SQLSSBPort={0}" -f $SQLSSBPort | out-file -FilePath $IniFilePathAndName -Append

    "" | out-file -FilePath $IniFilePathAndName -Append
    "[CloudConnectorOptions]" | out-file -FilePath $IniFilePathAndName -Append
    "CloudConnector={0}" -f $CloudConnector | out-file -FilePath $IniFilePathAndName -Append
    if ($CloudConnector -eq 1)
    {
        "CloudConnectorServer={0}" -f $CloudConnectorServer | out-file -FilePath $IniFilePathAndName -Append # Only required when CloudConnector equals 1.
        "UseProxy={0}" -f $UseProxy | out-file -FilePath $IniFilePathAndName -Append # Only required when CloudConnector equals 1.
    }

    if ($UseProxy -eq 1)
    {
        "ProxyName={0}" -f $ProxyName | out-file -FilePath $IniFilePathAndName -Append # Only required when UseProxy equals 1
        "ProxyPort={0}" -f $ProxyPort | out-file -FilePath $IniFilePathAndName -Append # Only required when UseProxy equals 1
    }
}
#endregion

#region Function Get-SQLBackupMetadata
<#
.Synopsis
    Get-SQLBackupMetadata
.DESCRIPTION
    Get-SQLBackupMetadata
.EXAMPLE
    Get-SQLBackupMetadata -SQLServerName [SQL server fqdn\instance name]
.EXAMPLE
    Get-SQLBackupMetadata -SQLServerName 'sql1.contoso.local'
.EXAMPLE
    Get-SQLBackupMetadata -SQLServerName 'sql2.contoso.local\instance2'
.PARAMETER $SQLServerName
    FQDN of SQL Server with instancename in case of a named instance
#>
function Get-SQLBackupMetadata
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$SQLServerName
    )

    $commandName = $MyInvocation.MyCommand.Name
    Write-CMTraceLog -Message "Export SQL backup metadata" -Component ($commandName)
    $connectionString = "Server=$SQLServerName;Database=msdb;Integrated Security=True"
    Write-Verbose "$commandName`: Connecting to SQL: `"$connectionString`""
    
    $SqlQuery = @'
    USE msdb
    select top 30 BS.database_name 	
        ,BS.backup_start_date
        ,BS.backup_finish_date
        ,[backup_type] = Case when BS.type = 'D' then 'FullBackup'
        when BS.type = 'I' then 'DifferentialBackup'
        when BS.type = 'L' then 'LogBackup'
        when BS.type = 'F' then 'FilegroupBackup'
        when BS.type = 'G' then 'DifferentialFileBackup'
        when BS.type = 'P' then 'PartialBackup'
        when BS.type = 'Q' then 'DifferentialPartialBackup' end
        ,BS.compatibility_level
        ,BS.backup_size
        ,BS.compressed_backup_size
        ,BS.collation_name
        ,BS.recovery_model
        --,BS.user_name -- Who initiated the backup
        ,FAM.physical_device_name
        ,BS.is_damaged
        ,BS.has_backup_checksums
    from dbo.backupset BS
    inner join dbo.backupmediafamily FAM on FAM.media_set_id = BS.backup_set_id
    where FAM.physical_device_name not like '%{%'
    order by BS.backup_finish_date desc
'@

    try 
    {
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = $connectionString
        $SqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $SqlCmd.Connection = $SqlConnection
        $SqlCmd.CommandText = $SqlQuery
        $SqlAdapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter
        Write-Verbose "$commandName`: Running Query: `"$SqlQuery`""
        $SqlAdapter.SelectCommand = $SqlCmd
        $ds = New-Object -TypeName System.Data.DataSet
        $SqlAdapter.Fill($ds) | Out-Null
        $SqlCmd.Dispose()
    }
    catch 
    {
        Write-CMTraceLog -Type Error -Message "Connection to SQL server failed" -Component ($commandName) -LogType LogAndEventlog
        Write-CMTraceLog -Type Error -Message "$($Error[0].Exception)" -Component ($commandName) -LogType LogAndEventlog     
        Invoke-StopScriptIfError   
    }

    if ($SqlConnection)
    {
        if($SqlConnection.state -ieq 'Open')
        {
            Write-CMTraceLog -Message "Will close SQL connection" -Component ($MyInvocation.MyCommand.Name)
            $SqlConnection.Close()
        }
    }

    return $ds.tables[0]
}
#endregion


#region Function Get-SQLPermissionsAndLogins
<#
.Synopsis
    Get-SQLPermissionsAndLogins
.DESCRIPTION
    Get-SQLPermissionsAndLogins
.EXAMPLE
    Get-SQLPermissionsAndLogins -SQLServerName [SQL server fqdn\instance name]
.EXAMPLE
    Get-SQLPermissionsAndLogins -SQLServerName 'sql1.contoso.local'
.EXAMPLE
    Get-SQLPermissionsAndLogins -SQLServerName 'sql2.contoso.local\instance2'
.PARAMETER $SQLServerName
    FQDN of SQL Server with instancename in case of a named instance
#>
function Get-SQLPermissionsAndLogins
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$SQLServerName
    )

    $commandName = $MyInvocation.MyCommand.Name
    Write-CMTraceLog -Message "Export SQL permissions and logins" -Component ($commandName)
    $connectionString = "Server=$SQLServerName;Database=msdb;Integrated Security=True"
    Write-Verbose "$commandName`: Connecting to SQL: `"$connectionString`""
    
    $SqlQuery = @'
    USE msdb
    SELECT pr.principal_id, pr.name, pr.type_desc,   
    pe.state_desc, pe.permission_name   
    FROM sys.server_principals AS pr   
    JOIN sys.server_permissions AS pe   
    ON pe.grantee_principal_id = pr.principal_id;
'@

    try 
    {
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = $connectionString
        $SqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $SqlCmd.Connection = $SqlConnection
        $SqlCmd.CommandText = $SqlQuery
        $SqlAdapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter
        Write-Verbose "$commandName`: Running Query: `"$SqlQuery`""
        $SqlAdapter.SelectCommand = $SqlCmd
        $ds = New-Object -TypeName System.Data.DataSet
        $SqlAdapter.Fill($ds) | Out-Null
        $SqlCmd.Dispose()
    }
    catch 
    {
        Write-CMTraceLog -Type Error -Message "Connection to SQL server failed" -Component ($commandName) -LogType LogAndEventlog
        Write-CMTraceLog -Type Error -Message "$($Error[0].Exception)" -Component ($commandName) -LogType LogAndEventlog     
        Invoke-StopScriptIfError   
    }

    if ($SqlConnection)
    {
        if($SqlConnection.state -ieq 'Open')
        {
            Write-CMTraceLog -Message "Will close SQL connection" -Component ($MyInvocation.MyCommand.Name)
            $SqlConnection.Close()
        }
    }

    return $ds.tables[0]
}
#endregion


#region Function Start-SQLDatabaseBackup
<#
.Synopsis
    Start-SQLDatabaseBackup
.DESCRIPTION
    Will backup a database or multiple database files
.EXAMPLE
    Start-SQLDatabaseBackup -SQLServerName [SQL server fqdn\instance name]
.EXAMPLE
    Start-SQLDatabaseBackup -SQLServerName 'sql1.contoso.local'
.EXAMPLE
    Start-SQLDatabaseBackup -SQLServerName 'sql2.contoso.local\instance2'
.PARAMETER SQLServerName
    FQDN of SQL Server with instancename in case of a named instance
.PARAMETER BackupFolder
    Folder to save the backups to. UNC or local. The function will create a sub-folder called 'SQLBackup'
.PARAMETER SQLDBNameList
    Array of database names
.PARAMETER BackupMode
    Either "AllDatabases" or "AllUserDatabases" to backup everything or just all user databases. If set, parameter "SQLDBNameList" will be ignored
#>
Function Start-SQLDatabaseBackup
{
    [CmdletBinding(DefaultParametersetName='Default')]
    param 
    (
        [Parameter(Mandatory=$true)]
        [string]$SQLServerName,
        [Parameter(Mandatory=$true)]
        [string]$BackupFolder,
        [parameter(ParameterSetName = 'SQLDBNameList',Mandatory=$false)]
        [string[]]$SQLDBNameList=('ReportServer'),
        [parameter(ParameterSetName = 'BackupMode',Mandatory=$false)]
        [ValidateSet("AllDatabases", "AllUserDatabases")]
        [string]$BackupMode
    )

    # We might need to create a folder
    $sqlBackupFolder = '{0}\SQLBackup' -f $BackupFolder
    try
    {
        # making sure we have a valid backup folder
        if(-NOT(Test-Path $sqlBackupFolder))
        {
            $null = [system.io.directory]::CreateDirectory("$sqlBackupFolder")
        }
    }
    catch
    {
        Write-CMTraceLog -Type Error -Message "ERROR: Folder could not be created `"$sitebackupPath`"" -Component ($MyInvocation.MyCommand.Name) -LogType 'LogAndEventlog'
        Write-CMTraceLog -Type Error -Message "$($Error[0].exception)" -Component ($MyInvocation.MyCommand.Name) -LogType 'LogAndEventlog'
        Invoke-StopScriptIfError
    }

    Write-CMTraceLog -Message "Will connect to: $SQLServerName" -Component ($MyInvocation.MyCommand.Name)
    try 
    {
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = "Integrated Security=SSPI;Persist Security Info=False;Initial Catalog=msdb;Data Source=$SQLServerName;Connection Timeout=20"
        $SqlConnection.Open()
    }
    catch 
    {
        Write-CMTraceLog -Type Error -Message "Connection to SQL server failed" -Component ($MyInvocation.MyCommand.Name) -LogType 'LogAndEventlog'
        Invoke-StopScriptIfError
    }

    # Query to get user DBs#
    if ($BackupMode -ieq "AllUserDatabases")
    {
        $userDBQuery = "USE Master SELECT name, database_id, create_date FROM sys.databases Where name not in ('master','tempdb','model','msdb');"
    }

    # Query for all DBs
    if ($BackupMode -ieq "AllDatabases")
    {
        $userDBQuery = "USE Master SELECT name, database_id, create_date FROM sys.databases Where name not in ('tempdb');"
    }

    if (($BackupMode -ieq "AllDatabases") -or ($BackupMode -ieq "AllUserDatabases"))
    {
        Write-CMTraceLog -Message "Getting list of databases from SQL. Since BackupMode is set to: $($BackupMode)" -Component ($MyInvocation.MyCommand.Name)
        try 
        {
            # Get all user databases
            $SqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
            $SqlCmd.Connection = $SqlConnection
            $SqlCmd.CommandText = $userDBQuery
            $SqlAdapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter
            Write-Verbose "$commandName`: Running Query: `"$userDBQuery`""
            $SqlAdapter.SelectCommand = $SqlCmd
            $ds = New-Object -TypeName System.Data.DataSet
            $SqlAdapter.Fill($ds) | Out-Null
            $SqlCmd.Dispose()
            
            $listOfUserDBs = $ds.tables[0]         
        }
        catch 
        {
            Write-CMTraceLog -Type Error -Message "Connection to SQL server failed" -Component ($MyInvocation.MyCommand.Name) -LogType 'LogAndEventlog'
            Write-CMTraceLog -Type Error -Message "$($Error[0].Exception)" -Component ($MyInvocation.MyCommand.Name) -LogType 'LogAndEventlog'
            Invoke-StopScriptIfError           
        }
    }

    # If we have a list of DBs. Use them instead of a provided list from parameter $SQLDBNameList
    if ($listOfUserDBs)
    {
        $SQLDBNameList = $listOfUserDBs.Name
    }

    [string]$backupDatetime = get-date -f 'yyyyMMdd_HHmmss' # Will be added to the backup file name
    foreach ($dbName in $SQLDBNameList)
    {
        Write-CMTraceLog -Message "Will try to backup database: $dbName" -Component ($MyInvocation.MyCommand.Name)
        try 
        {
            # Backup variable definition
            [string]$backupFileFullName = '{0}\{1}_backup_{2}.bak' -f $sqlBackupFolder, $dbName, $backupDatetime
            [string]$backupName = '{0}-Full Database Backup' -f $dbName
            $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
            $SqlCmd.CommandText = "BACKUP DATABASE [$dbName] TO  DISK = N'$backupFileFullName' WITH NOFORMAT, NOINIT,  NAME = N'$backupName', SKIP, NOREWIND, NOUNLOAD, COMPRESSION, STATS = 10"
            $SqlCmd.Connection = $SqlConnection
            $SqlCmd.CommandTimeout = 0 
            $null = $SqlCmd.ExecuteScalar()
        }
        catch 
        {
            Write-CMTraceLog -Type Error -Message "DB backup failed" -Component ($MyInvocation.MyCommand.Name) -LogType 'LogAndEventlog'
            if ($Error[0].Exception -match '(Access is denied)|(error 5)')
            {
                Write-CMTraceLog -Type Error -Message "Access is denied" -Component ($MyInvocation.MyCommand.Name)
                Write-CMTraceLog -Type Error -Message "SQL service account might not have write access to: $BackupFolder" -Component ($MyInvocation.MyCommand.Name)
            }
            else 
            {
                Write-CMTraceLog -Type Error -Message "Database backup failed" -Component ($MyInvocation.MyCommand.Name)
                Write-CMTraceLog -Type Error -Message "$($Error[0].Exception)" -Component ($MyInvocation.MyCommand.Name)
            }
            Invoke-StopScriptIfError      
        }
    }

    if ($SqlConnection)
    {
        if($SqlConnection.state -ieq 'Open')
        {
            Write-CMTraceLog -Message "Will close SQL connection" -Component ($MyInvocation.MyCommand.Name)
            $SqlConnection.Close()
        }
    }
}
#endregion

#region Get-SQLVersionInfo
<#
.Synopsis
    Get-SQLVersionInfo
.DESCRIPTION
    Get-SQLVersionInfo
.EXAMPLE
    Get-SQLVersionInfo -SQLServerName [SQL server fqdn\instance name]
.EXAMPLE
    Get-SQLVersionInfo -SQLServerName 'sql1.contoso.local'
.EXAMPLE
    Get-SQLVersionInfo -SQLServerName 'sql2.contoso.local\instance2'
.PARAMETER SQLServerName
    FQDN of SQL Server with instancename in case of a named instance
#>
Function Get-SQLVersionInfo
{
    param
    (
        [string]$SQLServerName
    )

    $commandName = $MyInvocation.MyCommand.Name
    Write-CMTraceLog -Message "Get SQL version info" -Component ($commandName)
    $connectionString = "Server=$SQLServerName;Database=msdb;Integrated Security=True"
    Write-Verbose "$commandName`: Connecting to SQL: `"$connectionString`""
    
    $SqlQuery = 'USE msdb;SELECT @@Version as [SQLVersion]'

    try 
    {
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = $connectionString
        $SqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $SqlCmd.Connection = $SqlConnection
        $SqlCmd.CommandText = $SqlQuery
        $SqlAdapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter
        Write-Verbose "$commandName`: Running Query: `"$SqlQuery`""
        $SqlAdapter.SelectCommand = $SqlCmd
        $ds = New-Object -TypeName System.Data.DataSet
        $SqlAdapter.Fill($ds) | Out-Null
        $SqlCmd.Dispose()
    }
    catch 
    {
        Write-CMTraceLog -Type Error -Message "Connection to SQL server failed" -Component ($commandName) -LogType LogAndEventlog
        Write-CMTraceLog -Type Error -Message "$($Error[0].Exception)" -Component ($commandName) -LogType LogAndEventlog     
        Invoke-StopScriptIfError   
    }
    return $ds.tables[0]
}
#endregion

#region
<#
.SYNOPSIS
    Function to export MECM site server information into a JSON file
#>
Function Export-SystemRoleInformation
{
    param
    (
        [parameter(Mandatory=$true)]
        [string]$ProviderMachineName,
        [parameter(Mandatory=$true)]
        [string]$SiteCode,
        [parameter(Mandatory=$true)]
        [string]$OutputFilePath,
        [parameter(Mandatory=$false)]
        [string]$DefaultConfigFile = '{0}\Default-FirewallRuleConfig.json' -f $PSScriptRoot,
        [parameter(Mandatory=$false)]
        [ValidateSet("IPv4","IPv6","All")]
        [string]$IPType = "IPv4"
    )
  
    $defaultDefinition = $null
    <#
    if (-NOT (Test-Path $DefaultConfigFile))
    {
        Write-host "$(Get-date -Format u): Default Firewall config file not found. Output will only contain some example rules: `"$($DefaultConfigFile)`"" -ForegroundColor Yellow
    }
    else
    {
        $defaultDefinition = Get-Content $DefaultConfigFile | ConvertFrom-Json
    }
    #>
    try
    {
        $siteSystems = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -Query "SELECT * FROM SMS_SCI_SysResUse WHERE NALType = 'Windows NT Server'" -ErrorAction Stop
        # getting sitecode and parent to have hierarchy information
        $siteCodeHash = @{}
        $siteCodeInfo = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -ClassName SMS_SCI_SiteDefinition -ErrorAction Stop
    }
    Catch
    {
        Write-CMTraceLog -Type Error -Message "Could not get site info" -Component ($commandName) -LogType LogAndEventlog
        Write-CMTraceLog -Type Error -Message "$($Error[0].Exception)" -Component ($commandName) -LogType LogAndEventlog
        Invoke-StopScriptIfError
    }
    $siteCodeInfo | ForEach-Object {   
        if ([string]::IsNullOrEmpty($_.ParentSiteCode))
        {
            $siteCodeHash.Add($_.SiteCode,$_.SiteCode)
        }
        else
        {
            $siteCodeHash.Add($_.SiteCode,$_.ParentSiteCode)
        }
    }

    Function Get-IPAddressFromName
    {
        param
        (
            [string]$SystemName,
            [ValidateSet("IPv4","IPv6","All")]
            [string]$Type = "IPv4"
        )
        
        $LocalSystemIPAddressList = @()
        $dnsObject = Resolve-DnsName -Name $systemName -ErrorAction SilentlyContinue
        if ($dnsObject)
        {
            switch ($Type) 
            {
                "All" {$LocalSystemIPAddressList += ($dnsObject).IPAddress}
                "IPv4" {$LocalSystemIPAddressList += ($dnsObject | Where-Object {$_.Type -eq 'A'}).IPAddress}
                "IPv6" {$LocalSystemIPAddressList += ($dnsObject | Where-Object {$_.Type -eq 'AAAA'}).IPAddress}
            }
            return $LocalSystemIPAddressList
        }
    }

    # Get a list of all site servers and their sitecodes 
    $siteCodeHashTable = @{}
    $sqlRoleHashTable = @{}
    $siteServerTypes = $siteSystems | Where-Object {$_.Type -in (1,2,4) -and $_.RoleName -eq 'SMS Site Server'}
    $siteServerTypes | ForEach-Object {
    
        switch ($_.Type)
        {
            1 
            {
                $siteHashValue = 'SecondarySite'
                $sqlHashValue = 'SECSQLServerRole'
            }
            
            2 
            {
                $siteHashValue = 'PrimarySite'
                $sqlHashValue = 'PRISQLServerRole'
            }
            
            4 
            {
                $siteHashValue = 'CentralAdministrationSite'
                $sqlHashValue = 'CASSQLServerRole'
            }
            #8 {'NotCoLocatedWithSiteServer'}
        }

        $siteCodeHashTable.Add($_.SiteCode, $siteHashValue)
        $sqlRoleHashTable.Add($_.SiteCode, $sqlHashValue)
    }
    
    
    $outObject = New-Object System.Collections.ArrayList
    foreach ($system in $siteSystems)
    {
        switch ($system.RoleName)
        {
            'SMS SQL Server' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = $sqlRoleHashTable[$system.SiteCode] # specific role like PRI, CAS, SEC or WSUS SQL 
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)

                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'SQLServerRole'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Site Server' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = $siteCodeHashTable[$system.SiteCode] # specific role like PRI, CAS or SEC
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)

                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'SiteServer'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)

            }
            'SMS Provider' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'SMSProvider'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Software Update Point' 
            {
                if ($siteCodeHashTable[$system.SiteCode] -eq 'CentralAdministrationSite')
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'CentralSoftwareUpdatePoint'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)                
                }

                if ($siteCodeHashTable[$system.SiteCode] -eq 'SecondarySite')
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'SecondarySoftwareUpdatePoint'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)                
                }
                else
                {             
                    $useParentWSUS = $system.Props | Where-Object {$_.PropertyName -eq 'UseParentWSUS'}
                    if ($useParentWSUS.Value -eq 1)
                    {
                        $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                        $tmpObj.Role = 'PrimarySoftwareUpdatePoint'
                        $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                        $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                        $tmpObj.SiteCode = $system.SiteCode
                        $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                        [void]$outObject.Add($tmpObj)
                    }
                }

                $supSQLServer = $system.Props | Where-Object {$_.PropertyName -eq 'DBServerName'}
                if (-NOT ([string]::IsNullOrEmpty($supSQLServer.Value2)))
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'SUPSQLServerRole'
                  
                    $systemNameFromNetworkOSPath = $system.NetworkOSPath -replace '\\\\'
                    [array]$dbServerName = $supSQLServer.Value2 -split '\\' # extract servername from server\instancename string
                    # making sure we have a FQDN
                    if ($systemNameFromNetworkOSPath -like "$($dbServerName[0])*")
                    {
                        $tmpObj.FullQualifiedDomainName = $systemNameFromNetworkOSPath
                    }
                    else 
                    {
                        if ($dbServerName[0] -notmatch '\.') # in case we don't have a FQDN, create one based on the FQDN of the initial system  
                        {
                            [array]$fqdnSplit =  $systemNameFromNetworkOSPath -split '\.' # split FQDN to easily replace hostname
                            $fqdnSplit[0] = $dbServerName[0] # replace hostname
                            $tmpObj.FullQualifiedDomainName = $fqdnSplit -join '.' # join back to FQDN
                        }   
                        else 
                        {
                            $tmpObj.FullQualifiedDomainName = $dbServerName[0] 
                        }              
                    }
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)                    
                }
                
                
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'SoftwareUpdatePoint'            
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)

                #Write-host "$(Get-date -Format u): If SUSDB of: `"$($tmpObj.FullQualifiedDomainName)`" is hosted on a SQL cluster, make sure to add each cluster node to the JSON config with role `"SUPSQLServerRole`" " -ForegroundColor Yellow

            }
            'SMS Endpoint Protection Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'EndpointProtectionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Distribution Point' 
            {

                $isPXE = $system.Props | Where-Object {$_.PropertyName -eq 'IsPXE'}
                if ($isPXE.Value -eq 1)
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'DistributionPointPXE'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)                
                }

                $isPullDP = $system.Props | Where-Object {$_.PropertyName -eq 'IsPullDP'}
                if ($isPullDP.Value -eq 1)
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'PullDistributionPoint'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)
    
                    $pullSources = $system.PropLists | Where-Object {$_.PropertyListName -eq 'SourceDistributionPoints'}
                    if (-NOT $pullSources)
                    {
                        #Write-host "$(Get-date -Format u): No DP sources found for PullDP" -ForegroundColor Yellow
                    }
                    else
                    {
    
                        $pullSources.Values | ForEach-Object {
                                $Matches = $null
                                $retVal = $_ -match '(DISPLAY=\\\\)(.+)(\\")'
                                if ($retVal)
                                {
                                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                                    $tmpObj.Role = 'PullDistributionPointSource'
                                    $tmpObj.FullQualifiedDomainName = ($Matches[2])
                                    $tmpObj.PullDistributionPointToSource = $system.NetworkOSPath -replace '\\\\'
                                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($Matches[2]) -Type $IPType
                                    $tmpObj.SiteCode = $system.SiteCode
                                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                                    [void]$outObject.Add($tmpObj)
                                }
                                else
                                {
                                    #Write-host "$(Get-date -Format u): No DP sources found for PullDP" -ForegroundColor Yellow
                                }
                            }
                    }
                }
    
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'DistributionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Management Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'ManagementPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS SRS Reporting Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'ReportingServicePoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Dmp Connector' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'ServiceConnectionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'Data Warehouse Service Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'DataWarehouseServicePoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Cloud Proxy Connector' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'CMGConnectionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS State Migration Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'StateMigrationPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Fallback Status Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'FallbackStatusPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Component Server' 
            {
                # Skip role since no firewall rule diretly tied to it
            }
            'SMS Site System' 
            {
                # Skip role since no firewall rule diretly tied to it
            }
            'SMS Notification Server' 
            {
                # Skip role since no firewall rule diretly tied to it
            }
            <#
            'SMS Certificate Registration Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'CertificateRegistrationPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            #>
            Default 
            {
                #Write-host "$(Get-date -Format u): Role `"$($system.RoleName)`" not supported by the script at the moment. Create you own firewallrules and definitions in the config file if desired." -ForegroundColor Yellow
            }
    
            <# still missing
                SMS Device Management Point
                SMS Multicast Service Point
                SMS AMT Service Point
                AI Update Service Point
                SMS Enrollment Server
                SMS Enrollment Web Site            
                SMS DM Enrollment Service
            #>
    
        }
    }
    
    # group roles by system to have a by system list
    $systemsArrayList = New-Object System.Collections.ArrayList
    foreach ($itemGroup in ($outObject | Group-Object -Property FullQualifiedDomainName))
    {
        $roleList = @()
        $pullDPList = @()
        foreach ($item in $itemGroup.Group)
        {
            $roleList += $item.Role
            if (-NOT ([string]::IsNullOrEmpty($item.PullDistributionPointToSource)))
            {
                $pullDPList += $item.PullDistributionPointToSource
            }
        }
        [array]$roleList = $roleList | Select-Object -Unique
        [array]$pullDPList = $pullDPList | Select-Object -Unique
    
        $itemList = [ordered]@{
            FullQualifiedDomainName = $itemGroup.Name
            IPAddress = $itemGroup.Group[0].IPAddress -join ','
            SiteCode = $itemGroup.Group[0].SiteCode
            ParentSiteCode = $itemGroup.Group[0].ParentSiteCode
            Description = ""
            RoleList = $roleList
            PullDistributionPointToSourceList = $pullDPList
        }
      
        [void]$systemsArrayList.Add($itemList)
    }
        
    #$tmpObjRuleDefinition = New-Object pscustomobject | Select-Object FirewallRuleDefinition
    $tmpObjDefinitions = New-Object pscustomobject | Select-Object SystemAndRoleList #, RuleDefinition, ServiceDefinition
    
    # Example Rule Definition
    $tmpRuleArrayList = New-Object System.Collections.ArrayList
    $servicesList = @("RPC","RPCUDP","RPCServicesDynamic","HTTPS")
    $exampleRule = [ordered]@{
                RuleName = "MECM Console to SMS provider"
                Source = "MECMConsole"
                Destination = "SiteServer"
                Direction = "Inbound"
                Action = "Allow"
                Profile = "Any"
                Group = "MECM"
                Description = "Console to WMI SMS provider connection. HTTPS for AdminService"
                Services = $servicesList
            }
    [void]$tmpRuleArrayList.Add($exampleRule)
    
    $tmpServiceArrayList = New-Object System.Collections.ArrayList
    # Example Service Definition
    $exampleService = [ordered]@{
                Name = "RPC"
                Protocol = "TCP"
                Port = "RPCEPMAP"
                Program = "%systemroot%\system32\svchost.exe"
                Description = "RPC Endpoint Mapper"
            }
    [void]$tmpServiceArrayList.Add($exampleService)
    
    # Example Service Definition
    $exampleService = [ordered]@{
                Name = "HTTPS"
                Protocol = "TCP"
                Port = "443"
                Program = ""
                Description = "Https"
            }
    [void]$tmpServiceArrayList.Add($exampleService)
    
    if ($defaultDefinition)
    {
        # build object for JSON output using default config file as reference
        $tmpObjDefinitions.SystemAndRoleList = $systemsArrayList
        #$tmpObjDefinitions.RuleDefinition = $defaultDefinition.FirewallRuleDefinition.RuleDefinition
        #$tmpObjDefinitions.ServiceDefinition = $defaultDefinition.FirewallRuleDefinition.ServiceDefinition
        #$tmpObjRuleDefinition.FirewallRuleDefinition = $tmpObjDefinitions
    }
    else
    {
        # build object for JSON output
        $tmpObjDefinitions.SystemAndRoleList = $systemsArrayList
        #$tmpObjDefinitions.RuleDefinition = $tmpRuleArrayList
        #$tmpObjDefinitions.ServiceDefinition = $tmpServiceArrayList
        #$tmpObjRuleDefinition.FirewallRuleDefinition = $tmpObjDefinitions
    }
    
    $tmpObjDefinitions | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFilePath -Force
    #Write-host "$(Get-date -Format u): Data exported to: `"$OutputFilePath`"" -ForegroundColor Green
}
#endregion

#region Invoke-StopScript
Function Invoke-StopScriptIfError
{
    param
    (
        [parameter(Mandatory=$false)]
        [ValidateSet("LogOnly","EventlogOnly","LogAndEventlog")]
        [string]$LogType = 'LogAndEventlog'
    )

    if ($global:SendErrorMail -ieq 'Yes')
    {
        Write-CMTraceLog -Message "Mail will be sent" -Component $global:Component -LogType $LogType
        # Copy logfile to the same location with a different name to avoid file locking
        $newLogFileTemp = $global:logFile -replace '\.', "-$(get-date -Format 'yyyyMMddhhmm')."
        Copy-Item $global:logFile -Destination $newLogFileTemp -Force -ErrorAction SilentlyContinue

        $paramSplatting = @{
            SmtpServer = $global:MailServer
            To = $global:MailTo
            From = $global:MailFrom
            Subject = "Backup script failed on $($env:Computername)"
            Body = "Backup script failed on $($env:Computername). Logfile attached."
            Priority = 'High'
        }

        # Add logfile if copy worked
        if (Test-Path $newLogFileTemp)
        {
            $paramSplatting['Attachments'] = $newLogFileTemp
        }

        try 
        {
            Send-MailMessage @paramSplatting -ErrorAction Stop
        }
        catch 
        {
            Write-CMTraceLog -Message "Mail could not be sent" -Component $global:Component -LogType $LogType -Type Error
            Write-CMTraceLog -Message "$($Error[0].Exception)" -Component $global:Component -LogType $LogType -Type Error
        }        
    }

    Write-CMTraceLog -Message "Will stop script" -Component $global:Component -LogType $LogType
    Remove-Item -Path $newLogFileTemp -Force -ErrorAction SilentlyContinue
    exit 2
}
#endregion


#-----------------------------------------
# Main Script starts here
#-----------------------------------------SCCMbackupPath
#region Step 1
#-----------------------------------------
# read config file and set variables
$stoptWatch = New-Object System.Diagnostics.Stopwatch
$stoptWatch.Start()
try
{
    # if config path not found, logfile will be created in script folder
    if (-NOT(Test-Path $configXMLFilePath))
    {
        Write-CMTraceLog -Message "ConfigFile not found `"$configXMLFilePath`"!" -Type Error -LogType 'LogAndEventlog'
        Invoke-StopScriptIfError
    }
    else
    {
        [xml]$xmlConfig = Get-Content $configXMLFilePath
    }


    # setting variables from config file
    [string]$sccmBackupPath = $xmlConfig.sccmbackup.SCCMbackupPath
    [int]$maxBackupDays = $xmlConfig.sccmbackup.MaxBackupDays
    [int]$maxBackups = $xmlConfig.sccmbackup.MaxBackups # this value wins over maxBackupDays
    [string]$LicenseKey = $xmlConfig.sccmbackup.LicenseKey
    [int]$maxLogFileSizeKB = $xmlConfig.sccmbackup.MaxLogfileSize
    [string[]]$customFoldersToBackup = $xmlConfig.sccmbackup.CustomFoldersToBackup.Folder
    [string]$custombackupFolderName = $xmlConfig.sccmbackup.CustomFolderBackupName
    [string]$CheckSQLFiles = $xmlConfig.sccmbackup.CheckSQLFiles
    [string]$zipCustomBackup = $xmlConfig.sccmbackup.ZipCustomBackup
    [string]$tempZipFileFolder = $xmlConfig.sccmbackup.TempZipFileFolder
    [string[]]$contentLibraryPathLive = $xmlConfig.sccmbackup.ContentLibraryPathLive.Folder
    [string]$contentLibraryPathBackup = $xmlConfig.sccmbackup.ContentLibraryPathBackup
    [string]$standBybackupPath = $xmlConfig.sccmbackup.StandByBackupPath
    [string]$copyToStandByServer = $xmlConfig.sccmbackup.CopyToStandByServer
    [string]$copyContentLibrary = $xmlConfig.sccmbackup.CopyContentLibrary
    [string]$excludeSQLFilesFromStandByCopy = $xmlConfig.sccmbackup.ExcludeSQLFilesFromStandByCopy
    [string]$BackupIIS = $xmlConfig.sccmbackup.BackupIIS
    [string]$BackupScheduledTasks = $xmlConfig.sccmbackup.BackupScheduledTasks
    [string]$BackupScheduledTasksRootPath = $xmlConfig.sccmbackup.BackupScheduledTasksRootPath
    [string]$BackupSQLDatabases = $xmlConfig.sccmbackup.BackupSQLDatabases
    [string]$BackupWSUSDatabase = $xmlConfig.sccmbackup.BackupWSUSDatabase
    [string[]]$BackupDatabaseList = $xmlConfig.sccmbackup.DatabaseList.DatabaseName
    [string]$ExportSQLBackupData = $xmlConfig.sccmbackup.ExportSQLBackupData
    [string]$ExportSQLLogins = $xmlConfig.sccmbackup.ExportSQLLogins
    [string]$ExportConfigMgrRoleData = $xmlConfig.sccmbackup.ExportConfigMgrRoleData
    [string]$global:SendErrorMail = $xmlConfig.sccmbackup.SendErrorMail
    [string]$global:SendSuccessMail = $xmlConfig.sccmbackup.SendSuccessMail
    [string]$global:MailServer = $xmlConfig.sccmbackup.SMTPServer
    [string]$global:MailFrom = $xmlConfig.sccmbackup.MailFrom
    [string[]]$global:MailTo = $xmlConfig.sccmbackup.MailToList.MailToEntry
    
}
catch
{
    Write-CMTraceLog -Message "Not able to read config file" -Type Error -LogType 'LogAndEventlog' 
    Invoke-StopScriptIfError
}
#-----------------------------------------
#endregion Step 1 End
#-----------------------------------------


#-----------------------------------------
#region Step 2
#-----------------------------------------
# Rollover Logfile and Start Logging in File
if (-NOT($maxLogFileSizeKB))
{
    $maxLogFileSizeKB = 2048
}
Rollover-Logfile -Logfile $global:logFile -MaxFileSizeKB $maxLogFileSizeKB


#$scriptVersion
Write-CMTraceLog -Message " "
Write-CMTraceLog -Message "-------------------------------------"
Write-CMTraceLog -Message "Starting ConfigMgr backup script version: $($scriptVersion) See logfile for more details. Log: $logFile" -LogType 'LogAndEventlog'
#-----------------------------------------
#endregion Step 2 End
#-----------------------------------------


#-----------------------------------------
#region Step 3
#-----------------------------------------
# read configmgr site info and populate data

$siteInfo = Get-ConfigMgrSiteInfo
if (-NOT($siteInfo))
{
    Write-CMTraceLog -Type Error -Message 'Could not get ConfigMgrSiteInfo!' -LogType 'LogAndEventlog'
    Invoke-StopScriptIfError
}
Write-Verbose $siteInfo

# Do not Change variables here
[string]$siteBackupFolder = "{0}Backup" -f $siteInfo.SiteCode
[string]$sitebackupPath = "{0}\{1}" -f $sccmBackupPath, $siteBackupFolder
#[string]$databaseFileName = "$($siteInfo.DatabaseFileName)"
#[string]$databaseLogName = "$($siteInfo.DatabaseLogName)"
[string]$databaseFileName = $siteInfo.SQLDatabaseFile
[string]$databaseLogName = $siteInfo.SQLDatabaseLogFile
[string]$cdLatestFolder = '{0}\cd.latest' -f $siteInfo.InstallDirectory

[string]$sqlBackupFilepath = "{0}\{1}\SiteDBServer\{2}" -f $sccmBackupPath, $siteBackupFolder, $databaseFileName
[string]$sqlBackupLogfilePath = "{0}\{1}\SiteDBServer\{2}" -f $sccmBackupPath, $siteBackupFolder ,$databaseLogName

[string]$sitebackupPathNewName = "{0}-{1}" -f ($sitebackupPath | Split-Path -Leaf),  (get-date -Format 'yyyyMMdd-hhmmss')

Write-CMTraceLog -Message "-------------------------------------"
Write-CMTraceLog -Message "------> Script parameters"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "SCCM backup path:", $sccmBackupPath)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Site backup folder:", $sitebackupPath)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Site backup folder newname:", $sitebackupPathNewName)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "CD.Latest folder:" ,$cdLatestFolder)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Custom Backup foldername:", $custombackupFolderName)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Zip custom backup:", $zipCustomBackup)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Temp Zip foldername:", $tempZipFileFolder)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Max backup days:", $maxBackupDays)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Max backup files:", $maxBackups)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Check SQL files:",  $CheckSQLFiles)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "SQL backup file:", $sqlBackupFilepath)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "SQL backup log file:", $sqlBackupLogfilePath)"
foreach($Folder in $customFoldersToBackup)
{
    Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Additional backup folder:", $Folder)"
}
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Copy to StandByServer:", $copyToStandByServer)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "StandByServer backup path:", $standBybackupPath)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Copy ContentLibrary:", $copyContentLibrary)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "ContentLibrary backup destination:", $contentLibraryPathBackup)"
foreach($Folder in $contentLibraryPathLive)
{
    Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "ContentLibrary folder:", $Folder)"
}
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Exclude SQL files from StandBy:", $excludeSQLFilesFromStandByCopy)"
#Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Event source:", $eventSource)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "BackupWSUSDatabase:", $BackupWSUSDatabase)"
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "BackupSQLDatabases:", $BackupSQLDatabases)"
foreach($database in $BackupDatabaseList)
{
    Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "Databasename:", $database)"
}
Write-CMTraceLog -Message "$("{0,-35}{1}" -f  "ExportSQLBackupData:", $ExportSQLBackupData)"
#-----------------------------------------
#endregion Step 3 End
#-----------------------------------------


#-----------------------------------------
#region Step 4
#-----------------------------------------
# Check all needed path for script execution
Write-CMTraceLog -Message "-------------------------------------"
Write-CMTraceLog -Message "------> Checking folder existence..."

if ($copyToStandByServer -ieq 'Yes')
{
    if ($standBybackupPath -eq $sccmBackupPath)
    {
        Write-CMTraceLog -Type Error -Message "ERROR: SCCM backup path cannot be the same as StandBy backup path" -LogType LogAndEventlog
        Invoke-StopScriptIfError
    }

    if ($standBybackupPath -eq $contentLibraryPathBackup)
    {
        Write-CMTraceLog -Type Error -Message "ERROR: StandBy backup path cannot be the same as ContentLibrary backup path" -LogType LogAndEventlog
        Invoke-StopScriptIfError
    }
}

$customFoldersToBackup | ForEach-Object {
    if (($_ -eq $tempZipFileFolder) -or ($tempZipFileFolder -like "$_*"))
    {
        Write-CMTraceLog -Type Error -Message "ERROR: ZIP temp folder cannot be part of the custom backup list" -LogType LogAndEventlog
        Invoke-StopScriptIfError
    }
}


<#
if (($standBybackupPath -like "$sccmBackupPath*") -or ($contentLibraryPathBackup -like "$sccmBackupPath*"))
{
    Write-CMTraceLog -Type Error -Message "ERROR: StandBy backup path and or ContentLibrary backup path cannot be a sub-folder withing the normal backup path!"
    exit 1
}
#>

# Put folders together to check them all at once
$pathToCheck = $customFoldersToBackup
$pathToCheck += $sccmBackupPath
$pathToCheck += $tempZipFileFolder

# adding path to list if condition is met
if($siteInfo.BackupEnabled)
{
    $pathToCheck += $sitebackupPath
    $pathToCheck += "{0}\CD.Latest" -f  $sitebackupPath # CD.Latest needs to be in the backup folder
}
else
{
    try
    {
        # making sure we have a valid backup folder
        if(-NOT(Test-Path $sitebackupPath))
        {
            [system.io.directory]::CreateDirectory("$sitebackupPath") | Out-Null
        }
    }
    catch
    {
        Write-CMTraceLog -Type Error -Message "ERROR: Folder could not be created `"$sitebackupPath`"" -LogType LogAndEventlog
        Write-CMTraceLog -Type Error -Message "$($Error[0].exception)" -LogType LogAndEventlog
        Invoke-StopScriptIfError
    }
}

# adding path to list if condition is met
if ($CheckSQLFiles -ieq 'Yes')
{
    $pathToCheck += $sqlBackupFilepath
    $pathToCheck += $sqlBackupLogfilePath
}

# adding path to list if condition is met
if ($copyToStandByServer -ieq 'Yes')
{
    
    $pathToCheck += $standBybackupPath
}

if($copyContentLibrary -ieq 'Yes')
{
    $pathToCheck += $contentLibraryPathLive
    $pathToCheck += $contentLibraryPathBackup
}

# check existence of all folders neccessary
[bool]$missingPath = $false
$pathToCheck | ForEach-Object {

    if (-NOT(Test-Path $_))
    {
        Write-CMTraceLog -Message "Path does not exist or not enough rights: `"$_`"" -Type Warning
        $missingPath = $true
    }
    else 
    {
        Write-CMTraceLog -Message "Path exists: `"$_`""
    }
}

if ($missingPath)
{
    Write-CMTraceLog -Message "Missing path error. See log: $($global:LogFile) for more info" -Type Error -LogType LogAndEventlog
    Invoke-StopScriptIfError
}
#-----------------------------------------
#endregion Step 4 End
#-----------------------------------------


#-----------------------------------------
#region Step 5
#-----------------------------------------
# Backup Custom Items either directly to the backup folder or to a temp location to zip everything togehter
Write-CMTraceLog -Message "-------------------------------------"
Write-CMTraceLog -Message "------> Backing up custom folder"
if ($zipCustomBackup -ieq 'Yes')
{
    $tempCustomBackupPath = "{0}\{1}" -f $tempZipFileFolder, $custombackupFolderName
}
else
{
    $tempCustomBackupPath = "{0}\{1}" -f $sitebackupPath, $custombackupFolderName
}

# Test if we need to clean up the folder from a previous failed run
if (Test-Path $tempCustomBackupPath)
{
    if (Get-ChildItem $tempCustomBackupPath -Recurse)
    {
        Write-CMTraceLog -Message "Custom data backup path has data from a previous run. Will delete. `"$($tempCustomBackupPath)`""
        Get-ChildItem $tempCustomBackupPath -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue | Out-Null    
    }
}
# backup custom folder
Get-item $customFoldersToBackup | ForEach-Object {
    $BackupPathTemp = $tempCustomBackupPath
    $newFolderStructure = ''
    # from "C:\Temp\Testfolder" to "C_Temp\Testfolder" to know the origin and to avoid duplicate folder names
    if($_.FullName.Contains(':')){$newFolderStructure = $_.FullName.Replace(':\','_')}
    # from \\server.domain.local\Backup$\Folder1 to server.domain.local\Backup$\Folder1
    if($_.FullName.Contains('\\')){$newFolderStructure = $_.FullName.Remove('0','2')}
    
    $BackupPathTemp = "$tempCustomBackupPath\$newFolderStructure"
    
    Write-CMTraceLog -Message "Copy folder `"$($_.FullName)`" to: `"$BackupPathTemp`" "
    try
    {
        Copy-Item -Path $_ -Destination $BackupPathTemp -Recurse -Force -ErrorAction Stop
    }
    Catch
    {
        Write-CMTraceLog -Message "Failed to copy folder: `"$($_.FullName)`"" -Type Error
        Write-CMTraceLog -Message "$($error[0].Exception)" -Type Error -LogType 'LogAndEventlog'
        Invoke-StopScriptIfError
    }  
}
#--------------

#-------------#
Write-CMTraceLog -Message "-------------------------------------"
Write-CMTraceLog -Message "------> Creating recovery files..."
# create infofiles for each recovery step:
$recoveryFile01 = "$tempCustomBackupPath\Step-01-Setup-machine.txt"
$recoveryFile02 = "$tempCustomBackupPath\Step-02-Install-Roles.txt"
$recoveryFile03 = "$tempCustomBackupPath\Step-03-Install-SQLServer.txt"
$recoveryFile04 = "$tempCustomBackupPath\Step-04-Install-ADK.txt"
$recoveryFile05 = "$tempCustomBackupPath\Step-05-ConfigureWSUS.txt" 
$recoveryFile06 = "$tempCustomBackupPath\Step-06-CopyCustomFiles.txt"
$recoveryFile07 = "$tempCustomBackupPath\Step-07-Import-IISConfig.txt"
$recoveryFile08 = "$tempCustomBackupPath\Step-08-Import-ScheduledTasks.txt"
$recoveryFile09 = "$tempCustomBackupPath\Step-09-Validate-Certificates.txt"
$recoveryFile10 = "$tempCustomBackupPath\Step-10-InstallSSRSAndImportReports.txt"
$recoveryFile11 = "$tempCustomBackupPath\Step-11-CopySourceFilesOrContentLibrary.txt"
$recoveryFile12 = "$tempCustomBackupPath\Step-12-RecoverConfigMgr.txt"
$recoveryFile13 = "$tempCustomBackupPath\Step-13-Set-ServiceAccountPasswords.txt"

"---" | Out-File -FilePath $recoveryFile01 -Force
"---" | Out-File -FilePath $recoveryFile02 -Force
"---" | Out-File -FilePath $recoveryFile03 -Force
"---" | Out-File -FilePath $recoveryFile04 -Force
"---" | Out-File -FilePath $recoveryFile05 -Force
"---" | Out-File -FilePath $recoveryFile06 -Force
"---" | Out-File -FilePath $recoveryFile07 -Force
"---" | Out-File -FilePath $recoveryFile08 -Force
"---" | Out-File -FilePath $recoveryFile09 -Force
"---" | Out-File -FilePath $recoveryFile10 -Force
"---" | Out-File -FilePath $recoveryFile11 -Force
"---" | Out-File -FilePath $recoveryFile12 -Force
"---" | Out-File -FilePath $recoveryFile13 -Force

#-----------------------------------------
#region Recovery Step 1
#-----------------------------------------
# system specific info first

$generalRecoveryInfo = @"
Before starting with the recovery process, determine what needs to be recovered and only choose appropriate steps from the below list.
Disaster scenarios:
 
 Scenario 1: 
     The ConfigMgr Site Server operating system is affected and the OS needs to be re-installed.
     The database is not affected and can still be used or was recovered manually.
 Actions: 
     Install a new server with the same name as before. The name is important! 
     SiteServerName: $($siteInfo.SiteServerName)
     Also install a new SQL server. Could be a different supported SQL version and server name.
     Make sure the new server has the same sizing as before (can be foubnd in additiona step files 88-92).
     Make sure the new server has the same AD groups as before (can be foubnd in additiona step files 88-92).
     Make sure the new server has the same administrators as before (can be foubnd in additiona step files 88-92).
     Make sure the new server has the same software installed as before (can be foubnd in additiona step files 88-92).
     Start with Step-02-install-Roles.txt and continue with the other step-files.
     

 Scenario 2:
     The ConfigMgr Site Server is affected, but the operating system is still working.
 Actions:
     SiteServerName: $($siteInfo.SiteServerName)
     Perform a sitereset with the following steps
     Run "$($siteInfo.InstallDirectory)\bin\X64\setup.exe"
     Choose "Perform site maintenance or reset this site"
     Choose "Reset site with no configuration changes"
     Wait for the sitereset to happen and review sitecomp.log
     If the reset does not help, uninstall the site 
     Run "$($siteInfo.InstallDirectory)\bin\X64\setup.exe"
     Choose "Uninstall this Configuration Manager site"
     Mark "Do not remove the primary site database"
     Delete "HKLM\Software\Microsoft\SMS" if the entry is still there
     Delete any registry entries STARTING WITH: "SMS" from: "HKLM\System\CurrentControlSet\Services"
        "SMS_EXECUTIVE" or "SMSvcHost 3.0.0.0" for example
     Restart the server
     Use Step-File 12 and 13 to recover the site

     
 Scenario 3:
     Only the ConfigMgr database failed
 Actions:
    SiteServerName: $($siteInfo.SiteServerName)
    To avoid any inconsistencies between the database and the installed ConfigMgr, uninstall the site before proceeding
    Run "$($siteInfo.InstallDirectory)\bin\X64\setup.exe"
    Choose "Uninstall this Configuration Manager site"
    Mark "Do not remove the primary site database"
    Delete "HKLM\Software\Microsoft\SMS" if the entry is still there
    Delete any registry entries STARTING WITH: "SMS" from: "HKLM\System\CurrentControlSet\Services"
        "SMS_EXECUTIVE" or "SMSvcHost 3.0.0.0" for example
    Restart the server
    Use Step-File 3 to recover the database
    Use Step-File 12 and 13 to recover the site
     
   
     
 Scenario 4:
     The ConfigMgr Site Server and the database is affected
 Actions:
     SiteServerName: $($siteInfo.SiteServerName)
     Use Step-File 3 to recover the database
     Perform a sitereset
     Run "$($siteInfo.InstallDirectory)\bin\X64\setup.exe"
     Choose "Perform site maintenance or reset this site"
     Choose "Reset site with no configuration changes"
     If the reset does not help, uninstall the site and use Step-File 12 to recover the site
     Use the option to not restore the database in the recovery wizard
   
     
 Scenario 5: 
     The operating system of the Primary Site and the database are affected
 Actions:
     Install a new server with the same name as before. The name is important! 
     SiteServerName: $($siteInfo.SiteServerName)
     Also install a new SQL server. Could be a different supported SQL version and server name.
     Make sure the new server has the same sizing as before (can be foubnd in additiona step files 88-92).
     Make sure the new server has the same AD groups as before (can be foubnd in additiona step files 88-92).
     Make sure the new server has the same administrators as before (can be foubnd in additiona step files 88-92).
     Make sure the new server has the same software installed as before (can be foubnd in additiona step files 88-92).
     Start with Step-02-install-Roles.txt and continue with the other step-files.
"@


# NOTE Create extra file just for the infos and change infos above

Write-CMTraceLog -Message "Create: `"$recoveryFile01`""
try 
{  
    $generalRecoveryInfo | Out-File -FilePath $recoveryFile01 -Append

@"

    -----------------------------------------------
    SITE SERVER DATA
    -----------------------------------------------'
    A potential new system needs to have the exact same name as the old one!
    Name: $($siteInfo.SiteServerName)

    The system also needs to have the same rights and AD group memberships as before.
    The new system also needs rights in AD for AD publishing. Full control for folder and subfolder of the "System Management" container
    More can be found here: https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/network/extend-the-active-directory-schema#step-2-the-system-management-container

    Use the additional files called Step-88 or 89.. to Step-92.. to get more information about the system and its configuration.

"@  | Out-File -FilePath $recoveryFile01 -Append

    if ($ExportConfigMgrRoleData -ieq 'Yes')
    {
        $ListFileSiteSystems = '{0}\Step-88-ListOfSiteSystems.txt'  -f ($recoveryFile01 | Split-Path -Parent)
        Export-SystemRoleInformation -SiteCode ($siteInfo.SiteCode) -ProviderMachineName ($siteInfo.SMSProvider) -OutputFilePath $ListFileSiteSystems
    }


    $ListFileDiskAndVolumeConfig = '{0}\Step-89-DiskAndVolumeConfig.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$ListFileDiskAndVolumeConfig`""
    '-----------------------------------------------' | Out-File -FilePath $ListFileDiskAndVolumeConfig -Append
    'Local Disk configuration:' | Out-File -FilePath $ListFileDiskAndVolumeConfig -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileDiskAndVolumeConfig -Append
    Get-Disk | Select-Object Number, FriendlyName, ProvisioningType, @{Name='TotalSizeGB'; Expression={ $_.Size /1024/1024/1024}}, PartitionStyle | 
        Format-List * | 
        Out-File -FilePath $ListFileDiskAndVolumeConfig -Append


    ' ' | Out-File -FilePath $ListFileDiskAndVolumeConfig -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileDiskAndVolumeConfig -Append
    'Local Volume configuration:' | Out-File -FilePath $ListFileDiskAndVolumeConfig -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileDiskAndVolumeConfig -Append
    Get-Volume | Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType, @{Name='TotalSizeGB'; Expression={ $_.Size /1024/1024/1024}} | 
        Format-List * | 
        Out-File -FilePath $ListFileDiskAndVolumeConfig -Append

    $ListFileRAMAndCPUConfig = '{0}\Step-90-RAMAndCPUConfig.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$ListFileRAMAndCPUConfig`""
    ' ' | Out-File -FilePath $ListFileRAMAndCPUConfig -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileRAMAndCPUConfig -Append
    'Local Processor configuration:' | Out-File -FilePath $ListFileRAMAndCPUConfig -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileRAMAndCPUConfig -Append
    Get-WmiObject -Namespace root\cimv2 -class win32_processor | Select-Object DeviceID, Name, CurrentClockSpeed, NumberOfCores, NumberOfLogicalProcessors | 
        Format-List * | 
        Out-File -FilePath $ListFileRAMAndCPUConfig -Append


    ' ' | Out-File -FilePath $ListFileRAMAndCPUConfig -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileRAMAndCPUConfig -Append
    'Local RAM configuration:' | Out-File -FilePath $ListFileRAMAndCPUConfig -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileRAMAndCPUConfig -Append
    $memDetails = Get-WmiObject -Namespace root\cimv2 -class Win32_PhysicalMemory | Measure-Object -Sum -Property Capacity
    ('Memory modules: {0}' -f $memDetails.Count) | Out-File -FilePath $ListFileRAMAndCPUConfig -Append
    ('Total capacity: {0}GB' -f ($memDetails.Sum /1024/1024/1024)) | Out-File -FilePath $ListFileRAMAndCPUConfig -Append
        
    $ListFileInstalledUpdates = '{0}\Step-91-ListOfInstalledUpdates.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$ListFileInstalledUpdates`""
    ' ' | Out-File -FilePath $ListFileInstalledUpdates -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileInstalledUpdates -Append
    'Installed Updates:' | Out-File -FilePath $ListFileInstalledUpdates -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileInstalledUpdates -Append
    Get-WmiObject Win32_Quickfixengineering | Out-File -FilePath $ListFileInstalledUpdates -Append

    $ListFileADConfiguration = '{0}\Step-92-ADConfiguration.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$ListFileADConfiguration`""
    ' ' | Out-File -FilePath $ListFileADConfiguration -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileADConfiguration -Append
    'AD Info of System:' | Out-File -FilePath $ListFileADConfiguration -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileADConfiguration -Append
    $computerADInfo = (New-Object System.DirectoryServices.DirectorySearcher("(&(objectCategory=computer)(objectClass=computer)(cn=$env:Computername))")).FindOne().GetDirectoryEntry()
    "LDAP path: $($computerADInfo.Path)" | Out-File -FilePath $ListFileADConfiguration -Append
    ' ' | Out-File -FilePath $ListFileADConfiguration -Append
    'AD groups the system is a member of:' | Out-File -FilePath $ListFileADConfiguration -Append
    $computerADInfo.memberOf | ForEach-Object { $_ | Out-File -FilePath $ListFileADConfiguration -Append }


    $ListFileIPConfiguration = '{0}\Step-93-IPConfiguration.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$ListFileIPConfiguration`""
    ' ' | Out-File -FilePath $ListFileIPConfiguration -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileIPConfiguration -Append
    'IP configuration:' | Out-File -FilePath $ListFileIPConfiguration -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileIPConfiguration -Append
    $ipConfig = ipconfig /all
    $ipConfig | Out-File -FilePath $ListFileIPConfiguration -Append

    $ListFileOfShareConfiguration = '{0}\Step-94-ShareConfiguration.txt' -f ($recoveryFile01 | Split-Path -Parent)
    ' ' | Out-File -FilePath $ListFileOfShareConfiguration -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileOfShareConfiguration -Append
    'Share configuration:' | Out-File -FilePath $ListFileOfShareConfiguration -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileOfShareConfiguration -Append
    Get-CimInstance Win32_Share | Format-List Name, Path, Description | Out-File -FilePath $ListFileOfShareConfiguration -Append


    $ListFileOfCertificates = '{0}\Step-95-ListOfCertificates.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$ListFileOfCertificates`""
    ' ' | Out-File -FilePath $ListFileOfCertificates -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileOfCertificates -Append
    'List of system certificates:' | Out-File -FilePath $ListFileOfCertificates -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileOfCertificates -Append
    $certList = Get-ChildItem -Path Cert:\LocalMachine\my -ErrorAction SilentlyContinue
    $certList | Format-List Thumbprint, Subject, FriendlyName, Issuer, NotAfter, NotBefore, DNSNameList, EnhancedKeyUsageList | Out-File -FilePath $ListFileOfCertificates -Append


    $ListFileOfInstalledSoftware = '{0}\Step-96-ListOfInstalledSoftware.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$ListFileOfInstalledSoftware`""
    ' ' | Out-File -FilePath $ListFileOfInstalledSoftware -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileOfInstalledSoftware -Append
    'List of installed software (32Bit and 64Bit)' | Out-File -FilePath $ListFileOfInstalledSoftware -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileOfInstalledSoftware -Append
    $path1 = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $path2 = 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty -Path $path1, $path2 |
        Select-Object -Property DisplayName, DisplayVersion, Publisher, InstallDate | 
        Sort-Object -Property DisplayName -Descending | Format-Table -AutoSize |
        Out-File -FilePath $ListFileOfInstalledSoftware -Append

    $ListFileOfLocalGroupsFile = '{0}\Step-97-ListOfLocalGroups.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$ListFileOfLocalGroupsFile`""
    ' ' | Out-File -FilePath $ListFileOfLocalGroupsFile -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileOfLocalGroupsFile -Append
    'List of local groups and group members:' | Out-File -FilePath $ListFileOfLocalGroupsFile -Append
    '-----------------------------------------------' | Out-File -FilePath $ListFileOfLocalGroupsFile -Append
    $localGroupList = Get-LocalGroup -ErrorAction SilentlyContinue | ForEach-Object {'-------------------------------------------------------------------------------'; net localgroup $_.Name}
    $localGroupList = $localGroupList -replace 'The command completed successfully.'
    $localGroupList | Out-File -FilePath $ListFileOfLocalGroupsFile -Append

    <#
    ' ' | Out-File -FilePath $recoveryFile01 -Append
    '-----------------------------------------------' | Out-File -FilePath $recoveryFile01 -Append
    'Event-Info:' | Out-File -FilePath $recoveryFile01 -Append
    '-----------------------------------------------' | Out-File -FilePath $recoveryFile01 -Append
    'A list of warning and error events 25h prior to the backup can be found in additiona files called:' | Out-File -FilePath $recoveryFile01 -Append
    #>
    $ApplicationEventsFile = '{0}\Step-98-ApplicationEventsExport.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$ApplicationEventsFile`""
    $SecurityEventsFile = '{0}\Step-98-SecurityEventsExport.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$SecurityEventsFile`""
    $SystemEventsFile = '{0}\Step-98-SystemEventsExport.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$SystemEventsFile`""

    "   $($ApplicationEventsFile | Split-Path -Leaf)" | Out-File -FilePath $recoveryFile01 -Append
    "   $($SecurityEventsFile | Split-Path -Leaf)" | Out-File -FilePath $recoveryFile01 -Append
    "   $($SystemEventsFile | Split-Path -Leaf)" | Out-File -FilePath $recoveryFile01 -Append
    #'The list might helpt to analyze a problem which caused ConfigMgr to stop working' | Out-File -FilePath $recoveryFile01 -Append
    Get-WinEvent -FilterHashTable @{LogName='Application'; Level=2,3; StartTime=(Get-Date).AddHours(-25)} -ErrorAction SilentlyContinue | 
        Format-List TimeCreated, LevelDisplayName, ProviderName, Message | out-file -FilePath $ApplicationEventsFile -Force
    Get-WinEvent -FilterHashTable @{LogName='Security'; Level=2,3; StartTime=(Get-Date).AddHours(-25)} -ErrorAction SilentlyContinue | 
        Format-List TimeCreated, LevelDisplayName, ProviderName, Message | out-file -FilePath $SecurityEventsFile -Force
    Get-WinEvent -FilterHashTable @{LogName='System'; Level=2,3; StartTime=(Get-Date).AddHours(-25)} -ErrorAction SilentlyContinue | 
        Format-List TimeCreated, LevelDisplayName, ProviderName, Message | out-file -FilePath $SystemEventsFile -Force

    <#
    ' ' | Out-File -FilePath $recoveryFile01 -Append
    '-----------------------------------------------' | Out-File -FilePath $recoveryFile01 -Append
    'Export of CCM and SMS registry entries' | Out-File -FilePath $recoveryFile01 -Append
    '-----------------------------------------------' | Out-File -FilePath $recoveryFile01 -Append
    'Both exports are saved in seperate files and are called:' | Out-File -FilePath $recoveryFile01 -Append
    #>
    
    $CCMRegExportFile = '{0}\Step-99-CCM-RegistryExport.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$CCMRegExportFile`""
    $SMSRegExportFile = '{0}\Step-99-SMS-RegistryExport.txt' -f ($recoveryFile01 | Split-Path -Parent)
    Write-CMTraceLog -Message "Create: `"$SMSRegExportFile`""

    "   $($CCMRegExportFile | Split-Path -Leaf)" | Out-File -FilePath $recoveryFile01 -Append
    "   $($SMSRegExportFile | Split-Path -Leaf)" | Out-File -FilePath $recoveryFile01 -Append
    'They might help to identify any wrong settings or missing settings after a recovery process' | Out-File -FilePath $recoveryFile01 -Append
   
    $regExportParam = @('export','HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\CCM',$CCMRegExportFile)
    Start-Process -FilePath Reg.exe -ArgumentList $regExportParam -Wait -WindowStyle Hidden 

    $regExportParam = @('export','HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\SMS',$SMSRegExportFile)
    Start-Process -FilePath Reg.exe -ArgumentList $regExportParam -Wait -WindowStyle Hidden 

}
catch
{
    Write-CMTraceLog -Message "Not able to backup system info!" -LogType 'LogAndEventlog'  -Type Error
    Write-CMTraceLog -Message "$($error[0].Exception)" -Type Error
    Write-CMTraceLog -Message "Not stopping script at that point..."
}

if (-NOT(Test-Path "$sitebackupPath\$custombackupFolderName"))
{
    New-Item -Path $sitebackupPath -Name $custombackupFolderName -ItemType Directory -Force | Out-Null
}
Write-CMTraceLog -Message "Create: 00-Recover-Site-without-SQL-unattended.ini"
# Lets create an unattended recovery file for all scenarios without an automated SQL recovery
# https://docs.microsoft.com/en-us/mem/configmgr/core/servers/manage/unattended-recovery
$paramSplatting = @{
    IniFilePathAndName = "{0}\{1}\00-Recover-Site-without-SQL-unattended.ini" -f $sitebackupPath, $custombackupFolderName
    Action = 'RecoverPrimarySite'
    CDLatest = '1-FromCDLatest'
    ServerRecoveryOptions = '2-SiteServerOnly'
    DatabaseRecoveryOptions = '80-Skip'
    ReferenceSite = ''
    SiteServerBackupLocation = '{0}\{1}' -f $sccmBackupPath, $sitebackupPathNewName
    BackupLocation = '{0}\{1}\SiteDBServer' -f $sccmBackupPath, $sitebackupPathNewName
    ProductID = $LicenseKey
    SiteCode = $siteInfo.SiteCode
    SiteName = $siteInfo.SiteName
    SMSInstallDir = $siteInfo.InstallDirectory
    SDKServer = $siteInfo.SMSProvider
    PrerequisiteComp = 1 # 1 = already downloaded, 0 = needs to be downloaded
    PrerequisitePath = '{0}\{1}\CD.Latest\redist' -f $sccmBackupPath, $sitebackupPathNewName
    AdminConsole = $siteInfo.ConsoleInstalled
    SQLServerName = $siteInfo.SQLServerName
    SQLServerPort = $siteInfo.SQlServicePort
    DatabaseName = $siteInfo.SQLDatabaseName
    SQLSSBPort = $siteInfo.SQLSSBPort
    CloudConnector = $siteInfo.CloudConnector
    CloudConnectorServer = $siteInfo.CloudConnectorServer
    UseProxy = '0'
    ProxyName = ''
    ProxyPort = ''
}
# create new recovery file
New-ConfigMgrRecoveryFile @paramSplatting

#-----------------------------------------
#endregion Recovery Step 1
#-----------------------------------------

#-----------------------------------------
#region Recovery Step 2
#-----------------------------------------
# backup windows features to install
Write-CMTraceLog -Message "Create: `"$recoveryFile02`""
try
{
    Write-CMTraceLog -Message "creating `"$recoveryFile02.ps1`""
    "Run `"{0}.ps1`" to install all previous installed roles and features." -f ($recoveryFile02 | split-path -Leaf) | Out-File -FilePath $recoveryFile02 -Append
    "Run the script in PowerShell and do not just copy the script content into the ISE and run it there." | Out-File -FilePath $recoveryFile02 -Append
    "The following is the complete feature list:" | Out-File -FilePath $recoveryFile02 -Append
    "-------------------------------------------" | Out-File -FilePath $recoveryFile02 -Append
    Get-WindowsFeature | Out-File -FilePath $recoveryFile02 -Append
    Get-InstalledWindowsFeatureAsInstallString | Out-File "$recoveryFile02.ps1" -Force
}
catch
{
    Write-CMTraceLog -Message "Not able to get installed roles and features!" -LogType 'LogAndEventlog'  -Type Error
    Write-CMTraceLog -Message "$($error[0].Exception)" -Type Error
    Write-CMTraceLog -Message "Not stopping script at that point..."
}
#-----------------------------------------
#endregion Recovery Step 2
#-----------------------------------------


#-----------------------------------------
#region Recovery Step 3
#-----------------------------------------
#install SQL Server
#$recoveryFile03
Write-CMTraceLog -Message "Create: `"$recoveryFile03`""
if ($siteInfo.SQLInstance -eq "Default")
{
    $sqlServerConnectionString = $siteInfo.SQLServerName
}
else 
{
    $sqlServerConnectionString = '{0}\{1}' -f $siteInfo.SQLServerName, $siteInfo.SQLInstance  
}


$sqlRecoveryInfo = @"
Install new SQL Server if necessary. The most important SQL information can be found below.
Use a supported version and same edition of SQL Server. 
Do not switch from SQL Standard to SQL Enterprise or vice versa. 
More information about how to restore databases can be found here: https://docs.microsoft.com/en-us/sql/relational-databases/backup-restore/restore-a-database-backup-using-ssms
Restore each database (not only the ConfigMgr one) and proceed with the recovery process. 
If you use different ports fpr SQL server you need to use the ports during recovery in the ConfigMgr setup wizard.
Make sure the database logins are set as logins in SQL under Security\Logins. Otherwise the login cannot be used to access the database.

"@
$sqlRecoveryInfo  | Out-File -FilePath $recoveryFile03 -Append


if ($BackupSQLDatabases -ieq 'yes')
{
    'Use the SQL backups in folder "SQLBackup" to restore the required databases' | Out-File -FilePath $recoveryFile03 -Append
}

$siteInfo | Select-Object SQLServerName, SQLSSBPort, SQlServicePort, SQLDatabaseName, SQLDatabase, SQLInstance | 
    Format-List * | Out-File -FilePath $recoveryFile03 -Append

'SQL Version:' | Out-File -FilePath $recoveryFile03 -Append
'-------------------------' | Out-File -FilePath $recoveryFile03 -Append
 Get-SQLVersionInfo -SQLServerName $sqlServerConnectionString | Select-Object SQLVersion -ExpandProperty SQLVersion | Out-File -FilePath $recoveryFile03 -Append

if ($ExportSQLLogins -ieq 'yes')
{
    'SQL Permissions and Logins:' | Out-File -FilePath $recoveryFile03 -Append
    '-------------------------' | Out-File -FilePath $recoveryFile03 -Append
    'Use the below list to validate SQL permissions and logins. Create new logins if logins are missing.' | Out-File -FilePath $recoveryFile03 -Append
    Get-SQLPermissionsAndLogins $sqlServerConnectionString | Out-File -FilePath $recoveryFile03 -Append
}

if ($ExportSQLBackupData -ieq 'yes')
{
    'SQL Backup Metadata:' | Out-File -FilePath $recoveryFile03 -Append
    '-------------------------' | Out-File -FilePath $recoveryFile03 -Append
    'You can use the "SQL Backup Metadata" (shown below) to find the right backup to be recovered. Only the last 30 backups are visible in the list.' | Out-File -FilePath $recoveryFile03 -Append
    Get-SQLBackupMetadata -SQLServerName $sqlServerConnectionString | Out-File -FilePath $recoveryFile03 -Append
}
#-----------------------------------------
#endregion Recovery Step 3
#-----------------------------------------


#-----------------------------------------
#region Recovery Step 4
#-----------------------------------------
# output of current system configuration for easy recovery
Write-CMTraceLog -Message "Create: `"$recoveryFile04`""
try
{
    'Install the same ADK version as before.' | Out-File -FilePath $recoveryFile04 -Append
    #'You can use a command with the list of features like this:' | Out-File -FilePath $recoveryFile04 -Append
    #'adksetup.exe /quiet /installpath c:\ADK /features OptionId.DeploymentTools ' | Out-File -FilePath $recoveryFile04 -Append
    'Installed ADK Version and components:' | Out-File -FilePath $recoveryFile04 -Append
    '-----------------------------------------------'  | Out-File -FilePath $recoveryFile04 -Append
    $InstalledADKInfo = Get-InstalledADKInfo
    if($InstalledADKInfo)
    {
        $InstalledADKInfo.ADKVersion  | Out-File -FilePath $recoveryFile04 -Append
        $InstalledADKInfo.InstalledItems | Format-List *  | Out-File -FilePath $recoveryFile04 -Append
    }
    else
    {
        'ADK not detected!'  | Out-File -FilePath $recoveryFile04 -Append
    }
}
catch
{
    'ADK not detected!'  | Out-File -FilePath $recoveryFile04 -Append    
}
#-----------------------------------------
#endregion Recovery Step 4
#-----------------------------------------


#-----------------------------------------
#region Recovery Step 5
#-----------------------------------------
# $recoveryFile05
# configure WSUS
Write-CMTraceLog -Message "Create: `"$recoveryFile05`""
$tempTextString = @"
Configure WSUS before proceeding if WSUS was installed on the failed machine.
Make sure to configure WSUS to use SSL in case that was set before.
More details can be found here:
https://docs.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/2-configure-wsus#23-secure-wsus-with-the-secure-sockets-layer-protocol
Skip this step if the WSUS server has not been affected by a failure.

The SQL backup folder might also contain the SUSDB database backup depending on the configuration.

WSUS Infos:
"@ 
$tempTextString | Out-File -FilePath $recoveryFile05 -Append

$siteInfo.SUPList | Format-List * | Out-File -FilePath $recoveryFile05 -Append
#-----------------------------------------
#endregion Recovery Step 5
#-----------------------------------------


#-----------------------------------------
#region Recovery Step 6
#-----------------------------------------
# unzip custom backup and copy files to the original location
#$recoveryFile06
Write-CMTraceLog -Message "Create: `"$recoveryFile06`""
$contentRecoveryInfo = @'
Unzip the custom backup and copy each folder to it's original place before proceeding.
The folder E_CUSTOM\scripts" for example, should be copied to "E:\CUSTOM\scripts".
The path has been normalized to store the data as easy as possible. 
'@

$contentRecoveryInfo | Out-File -FilePath $recoveryFile06 -Append
#-----------------------------------------
#endregion Recovery Step 6
#-----------------------------------------


#-----------------------------------------
#region Recovery Step 7
#-----------------------------------------
# $recoveryFile07
# backup of IIS Config
Write-CMTraceLog -Message "Create: `"$recoveryFile07`""
if ($BackupIIS -ieq 'Yes')
{
    "Run the script: `"{0}.ps1`" to recover the IIS webconfig." -f ($recoveryFile07 | Split-Path -Leaf) | Out-File -FilePath $recoveryFile07 -Append
    "Only needed if custom website configurations had been made." | Out-File -FilePath $recoveryFile07 -Append
    "Run the script in PowerShell and do not just copy the script content into the ISE and run it there." | Out-File -FilePath $recoveryFile07 -Append
    Backup-WebConfigurationAndCopyFolder -BackupPath $tempCustomBackupPath -RecoveryScriptFileName "$recoveryFile07.ps1"
}
else
{
    Write-CMTraceLog -Message "IIS Backup not set in config file!" -Type Warning
}
#-----------------------------------------
#endregion Recovery Step 7
#-----------------------------------------


#-----------------------------------------
#region Recovery Step 8
#-----------------------------------------
# $recoveryFile08
# backup of scheduled tasks
Write-CMTraceLog -Message "Create: `"$recoveryFile08`""
if($BackupScheduledTasks -ieq 'Yes')
{
    "Run the script: `"{0}.ps1`" to import all scheduled tasks again." -f ($recoveryFile08 | split-Path -Leaf) | Out-File -FilePath $recoveryFile08 -Append
    "Re-enter any service account passwords if needed for a scheduled task." -f ($recoveryFile08 | split-Path -Leaf) | Out-File -FilePath $recoveryFile08 -Append
    Export-ScheduledTasksCustom -BackupFolder $tempCustomBackupPath -TaskPathRoot $BackupScheduledTasksRootPath -RecoveryScriptFileName "$recoveryFile08.ps1"
}
else
{
    Write-CMTraceLog -Message "ScheduledTask Backup not set in config file!" -Type Warning
}
#-----------------------------------------
#endregion Recovery Step 8
#-----------------------------------------




#-----------------------------------------
#region Recovery Step 9
#-----------------------------------------
# $recoveryFile09
# validate certs
Write-CMTraceLog -Message "Create: `"$recoveryFile09`""
"Validate certificates before proceeding. The site might need certificates in order to function correctly" | Out-File -FilePath $recoveryFile09 -Append
"A list of certificates can be found in the certificate info file or the first step file." | Out-File -FilePath $recoveryFile09 -Append

#-----------------------------------------
#endregion Recovery Step 9
#-----------------------------------------



#-----------------------------------------
#region Recovery Step 10
#-----------------------------------------
# $recoveryFile10
# install ssrs
Write-CMTraceLog -Message "Create: `"$recoveryFile10`""
if($xmlConfig.sccmbackup.BackupSSRSRDLs -ieq 'Yes')
{
    Write-CMTraceLog -Message "-------------------------------------"
    Write-CMTraceLog -Message "------> Backing up SSRS reports..."
    "Install and configure SSRS. Refer to the original installation guide. " | Out-File -FilePath $recoveryFile10 -Append
    "Import as many reports as you need into SSRS by using the files in the backup folders." | Out-File -FilePath $recoveryFile10 -Append
    
    Export-SSRSReports -SiteInfo $siteInfo -BackupPath $tempCustomBackupPath
}
else 
{
$tempTextString = @"
SSRS report backup is disabled in config file.
Steps to recover SSRS:
Install a new operating system
Install the same SSRS version as shown below
Restore the SSRS database (in case you made a backup)
Reconfigure SSRS. Use the info below to create the same report server URI etc.
SSRS Install doku: https://learn.microsoft.com/en-us/sql/reporting-services/install-windows/install-reporting-services?view=sql-server-ver16
NOTE: The encryption key is only required if you restored the SSRS database and if you need to use the same report subscriptions as before. 
"@
    $tempTextString  | Out-File -FilePath $recoveryFile10 -Append
}
"SSRS Infos:" | Out-File -FilePath $recoveryFile10 -Append
$siteInfo.SSRSList | Format-List * | Out-File -FilePath $recoveryFile10 -Append
#-----------------------------------------
#endregion Recovery Step 10
#-----------------------------------------


#-----------------------------------------
#region Recovery Step 11
#-----------------------------------------
# $recoveryFile11
# CopySourceFilesOrContentLibrary
Write-CMTraceLog -Message "Create: `"$recoveryFile11`""
$contentRecoveryInfo = @'
Copy the backup source files to the source directory.
Copy the ContentLibrary onto the system if the ContentLibrary was backed up before. 
Otherwise invoke a content update after the last step of the process on all packages, 
apps and other items to restore the ContentLibrary from the source files.
Without the ContentLibrary on a primary site no content can be distributed or re-distributed to distribution points
and a content update is required. 
'@

$contentRecoveryInfo| Out-File -FilePath $recoveryFile11 -Append

#-----------------------------------------
#endregion Recovery Step 11
#-----------------------------------------



#-----------------------------------------
#region Recovery Step 12
#-----------------------------------------
# $recoveryFile12
# RecoverConfigMgr
# Create different commands for network or local path
Write-CMTraceLog -Message "Create: `"$recoveryFile12`""
if ($sccmBackupPath -match '\\\\')
{
    $cmdCommand = @"
Type: "net use Q:\ {0}\{1}"
Type: "Q:"
Type: "CD .\CD.Latest\SMSSETUP\BIN\X64"
Type: "setup.exe /script Q:\{2}\00-Recover-Site-without-SQL-unattended.ini"
"@ -f $sccmBackupPath, $sitebackupPathNewName, $custombackupFolderName
}
else 
{
    $cmdCommand = @"
Type: "{0}\{1}\CD.Latest\SMSSETUP\BIN\X64.setup.exe /script {2}\{3}\{4}\00-Recover-Site-without-SQL-unattended.ini"
"@ -f $sccmBackupPath, $sitebackupPathNewName, $sccmBackupPath, $sitebackupPathNewName, $custombackupFolderName
}



$recoverConfigMgrInfo = @"
Unzip the cd.latest.zip file onto the new site server or into the same folder as the backup.
Start ConfigMgr Setup from the cd.Latest folder of the backup via splash.hta.
NOTE: Change the paths if you renamed the backup or copied the backup to another location.
Backup path: "{0}\{1}\CD.Latest\splash.hta" 
Click on "Install" and "Next"
Choose "Recover a site"
Choose the option: "Use a site database that has been manually recovered"
Since the database should be recovered during step 3 using SQL methods. 
Use the below information to set the correct values for the recovery process
Note: Make sure the latest ConfigMgr client is installed on the site server.

OR

use the "00-Recover-Site-without-SQL-unattended.ini" to recover the site without user interaction or the need to provide the correct values.
NOTE: Make sure the correct key is used in the INI file!
NOTE: Change the paths if you renamed the backup or copied the backup to another location. Do the same in the INI file. 
Start the setup process by opening a CMD as administrator
{2}

"@ -f $sccmBackupPath, $sitebackupPathNewName, $cmdCommand

"ConfigMgr installation key: $($LicenseKey)" | Out-File -FilePath $recoveryFile12 -Append 
$recoverConfigMgrInfo | Out-File -FilePath $recoveryFile12 -Append
$siteInfo | Out-File -FilePath $recoveryFile12 -Append
#-----------------------------------------
#endregion Recovery Step 12
#-----------------------------------------



#-----------------------------------------
#region Recovery Step 13
#-----------------------------------------
# $recoveryFile13
# Set-ServiceAccountPasswords
Write-CMTraceLog -Message "Create: `"$recoveryFile13`""
$recoverConfigMgrPasswords = @'
Follow the post recovery options listed in:
    C:\ConfigMgrPostRecoveryActions.html

Reenter user account passwords after site recovery
    Open the Configuration Manager console and connect to the recovered site.
    Go to the Administration workspace, expand Security, and then select Accounts.
    Set the password for each account.

Reenter PXE passwords
    In the Configuration Manager console, go to the Administration workspace, and select the Distribution Points node. 
    Any on-premises distribution point with Yes in the PXE column is enabled for PXE and may have a password set.

Validate shared folder
    Make sure to share all required folders again. Use the share info file to verify the shares.
    One of the Step-88 to Step-92... files contains the share info.

Configure SSL for site system roles that use IIS
    When you recover site systems that run IIS that are configured for HTTPS, reconfigure IIS to use the correct web server certificate.

Update content
    If the whole ContentLibrary has previously been recovered, there might be no need to update each content.
    But if the ContentLibrary has NOT been recovered and only the source files are available, each package, app, image, bootmedia, 
    driver package etc. needs to be updated in the console. This will result in traffic to each Distribution Point.
    
Regenerate the certificates for distribution points
    After you restore a site, the distmgr.log might list the following entry for one or more distribution points: 
    Failed to decrypt cert PFX data. This entry indicates that the distribution point certificate data can't be decrypted by the site. 
    To resolve this issue, regenerate or reimport the certificate for affected distribution points in th Distribution Point PXE settings.

Recreate bootable media and prestaged media
    Re-create any task sequence boot media such as ISO files or USB drives

Reenter task sequence passwords
    It might be required to reenter the passwords of task sequence steps like the "Join Domain" step of each task sequence in use.
    But before doing that, test the OS Installation first. 

Test OS installation and overall function
    The last step in the recovery process is to test the operating system, app and update installation to verify the successful recovery

Possible problems:
    Problem #1
    In case the task sequence cannot use any collection or computer variable, check the following:
    
    Collection-Variables:
    The result from the following SQL query should be the value of "Last Row Version" of "HKLM\SOFTWARE\Microsoft\SMS\COMPONENTS\SMS_COLLECTION_EVALUATOR":
        select top 1 CEP.CollectionID, CEP.LastModificationTime, CEP.rowversion
        from CEP_CollectionExtendedProperties CEP 
        order
        by rowversion desc
    
    Computer-Variables:
    The result from the following SQL query should be the value of "Last Row Version" of "HKLM\SOFTWARE\Microsoft\SMS\COMPONENTS\SMS_POLICY_PROVIDER\MEPHandler":
        select top 1 MEP.MachineID, MEP.LastModificationTime, MEP.rowversion
        from MEP_MachineExtendedProperties MEP
        join System_Disc SYD on SYD.ItemKey = MEP.MachineID
        order by MEP.rowversion desc

    Problem #2
    In case the clients are not installing any new updates, make sure the values of "ContentVersion" and "SyncToVersion" are higher than the result from the following SQL query:
        --SQL statement:
        ;WITH XMLNAMESPACES ( DEFAULT 'http://schemas.microsoft.com/SystemsCenterConfigurationManager/2009/07/10/DesiredConfiguration') 
        SELECT MAX(CI.SDMPackageDigest.value('(/DesiredConfigurationDigest/SoftwareUpdateBundle/ConfigurationMetadata/Provider/Operation[@Name="Detect"]/Parameter/Property[@Name="MinCatalogVersion"]/@Value)[1]', 'int')) MinCatalogVersion  
        FROM [CI_ConfigurationItems] as CI  
        WHERE CIType_ID = 8  

        HKLM\\SOFTWARE\Microsoft\SMS\Components\SMS_WSUS_SYNC_MANAGER
        "ContentVersion"=1430 <- just example entries
        "SyncToVersion"=1430 <- just example entries
        "LastAttemptVersion"=1429 <- just example entries

'@

$recoverConfigMgrPasswords | Out-File -FilePath $recoveryFile13 -Append

#-----------------------------------------
#endregion Recovery Step 13
#-----------------------------------------


#-----------------------------------------
#region Step 6 Database Backup
#-----------------------------------------
Write-CMTraceLog -Message "-------------------------------------"
Write-CMTraceLog -Message "------> SQL database backup..."

#create connection string for SQL Server
if ($siteInfo.SQLInstance -eq "Default")
{
    $sqlServerConnectionString = $siteInfo.SQLServerName
}
else 
{
    $sqlServerConnectionString = '{0}\{1}' -f $siteInfo.SQLServerName, $siteInfo.SQLInstance  
}

# Actual backup of SQL databases
if ($BackupSQLDatabases -ieq 'yes')
{
    if ($BackupDatabaseList.Count -eq 1)
    {
        Start-SQLDatabaseBackup -BackupFolder $sitebackupPath -SQLServerName $sqlServerConnectionString -BackupMode ($BackupDatabaseList[0])
    }
    else 
    {
        Start-SQLDatabaseBackup -BackupFolder $sitebackupPath -SQLServerName $sqlServerConnectionString -SQLDBNameList $BackupDatabaseList    
    }
}
else 
{
    Write-CMTraceLog -Message "------> Skipped. Not enabled."
}

Write-CMTraceLog -Message "-------------------------------------"
Write-CMTraceLog -Message "------> WSUS database backup..."

# We dont want to backup the database twice in case it runs on the same SQL Server as the ConfigMgr db
# In case we need to compare netbios name and DB we need to extract that from something like this: CM02.contoso.local
$sqlServerNetbiosOnly = $siteInfo.SQLServerName -replace '\..*'
[bool]$supDBRunsOnSameSQLServer = $false

if ($siteInfo.SQLInstance -eq "Default")
{
    # we just need to check the servername
    if ($siteInfo.SUPList.DBServerName -imatch $siteInfo.SQLServerName) 
    {
        $supDBRunsOnSameSQLServer = $true
    }
    elseif ($siteInfo.SUPList.DBServerName -imatch $sqlServerNetbiosOnly)
    {
        $supDBRunsOnSameSQLServer = $true
    }
}
else
{
    # we also need to check the instancename, could be different
    if (($siteInfo.SUPList.DBServerName -imatch $siteInfo.SQLServerName) -and ($siteInfo.SUPList.DBServerName -imatch $siteInfo.SQLInstance)) 
    {
        $supDBRunsOnSameSQLServer = $true
    }
    elseif (($siteInfo.SUPList.DBServerName -imatch $sqlServerNetbiosOnly) -and ($siteInfo.SUPList.DBServerName -imatch $siteInfo.SQLInstance))
    {
        $supDBRunsOnSameSQLServer = $true
    }
}

if ($BackupWSUSDatabase -ieq 'Yes')
{
    if ($supDBRunsOnSameSQLServer)
    {
        Write-CMTraceLog -Message "WSUS database runs on the same SQL Server as the ConfigMgr database. Skipping WSUS database backup." -Type Warning
        Write-CMTraceLog -Message "WSUS database should be part of the normal SQL backup in that case" -Type Warning
    }
    else
    {
        Start-SQLDatabaseBackup -BackupFolder $sitebackupPath -SQLServerName ($siteInfo.SUPList.dbservername) -SQLDBNameList 'SUSDB'
    }
}
else 
{
    Write-CMTraceLog -Message "Skipped. Not enabled."
}
#-----------------------------------------
#endregion Step 6 End
#-----------------------------------------



#-----------------------------------------
#region Step 7
#-----------------------------------------
Write-CMTraceLog -Message "-------------------------------------"
Write-CMTraceLog -Message "------> Compression of custom folder..."
# create zip file of custom backup
if ($zipCustomBackup -ieq 'Yes')
{
    Get-item $tempCustomBackupPath | New-ZipFile -PathToSaveFileTo "$sitebackupPath\$custombackupFolderName" -TempZipFileFolder $tempZipFileFolder -UseStaticFolderName Yes

    Start-Sleep 1
    try
    {
        $del_cmdcommand = "rd /S /Q $tempCustomBackupPath"
        cmd /c $del_cmdcommand
    }
    Catch{}
}


if(-NOT ($siteInfo.BackupEnabled))
{
    Write-CMTraceLog -Message "-------------------------------------"
    Write-CMTraceLog -Message "------> Compression of cd.latest folder. Since ConfigMgr backup task is not enabled."
    # zipping cd.latest
    Get-item $cdLatestFolder | New-ZipFile -PathToSaveFileTo "$sitebackupPath" -TempZipFileFolder $tempZipFileFolder -UseStaticFolderName Yes -FileName "cd.Latest"
}
#-----------------------------------------
#endregion Step 7 End
#-----------------------------------------


#-----------------------------------------
#region Step 8
#-----------------------------------------
Write-CMTraceLog -Message "-------------------------------------"
Write-CMTraceLog -Message "------> Creating main readme file..."
if ($zipCustomBackup -ieq 'Yes')
{
    $tempTextString = 'Unpack the zip file under {0}\{1} and start with the Step-01-Setup-machine.txt file to recover the site' -f $sitebackupPath, $custombackupFolderName
    $tempTextString | Out-File -FilePath "$sitebackupPath\README.txt" -Force
    "The zip file can be unpacked to the same folder or directly onto the new machine." | Out-File -FilePath "$sitebackupPath\README.txt" -Append
}
else
{
    $tempTextString = 'Start with the Step-01-Setup-machine.txt file to recover the site in folder {0}\{1}' -f $sitebackupPath, $custombackupFolderName
    $tempTextString | Out-File -FilePath "$sitebackupPath\README.txt" -Force

}

$tempTextString = @"

List of folders and files and their meaning:
----------------------------------------
CustomBackups:  Contains the custom backup files either as zip file or as folders.
SQLBackup:      Contains the SQL backup files. Only created if the SQL backup option is enabled.
CD.Latest.zip:  Contains the cd.latest folder of the ConfigMgr installation media if the built-in ConfigMgr backup task is not enabled.

Other files and folders could be created in case the built-in ConfigMgr backup task is enabled.
The built-in ConfigMgr backup task will always contain the cd.latest folder of the ConfigMgr installation media (not compressed).
"@ 

$tempTextString | Out-File -FilePath "$sitebackupPath\README.txt" -Append


# Rename Backup Folder
Write-CMTraceLog -Message "-------------------------------------"
Write-CMTraceLog -Message "------> Rename backup folder..."
try
{
    Rename-Item -Path $sitebackupPath -NewName $sitebackupPathNewName -Force -ErrorAction Stop
}
Catch
{
    Write-CMTraceLog -Message "Renaming folder `"$($sitebackupPath)`" not possible. Error: $($error[0].Exception)" -LogType 'LogAndEventlog' -type error
    Invoke-StopScriptIfError
}
Write-CMTraceLog -Message "Folder renamed. Old: $($sitebackupPath) New: $sitebackupPathNewName"
#-----------------------------------------
#endregion Step 8 End
#-----------------------------------------


#-----------------------------------------
#region Step 9
#-----------------------------------------

# copy backup data to standby Server for easy recovery
if ($copyToStandByServer -ieq 'Yes')
{
    Write-CMTraceLog -Message "-------------------------------------"
    Write-CMTraceLog -Message "------> Copy content files..."
    if ($excludeSQLFilesFromStandByCopy -ieq 'Yes')
    {
        # copy Backup data to Standby Server for easy recovery
        Write-CMTraceLog -Message "Start of Robocopy for ConfigMgr Backup Data WITHOUT SQL Files to StandBy Server..."
        Write-CMTraceLog -Message "WITHOUT SQL Files refers only to the default ConfigMgr SQL Files of the default ConfigMgr backup task."
        Write-CMTraceLog -Message "Custom SQL Files are still copied."
        Start-RoboCopy -Source $sccmBackupPath -Destination $standBybackupPath -RobocopyLogPath "$logFilePath\StandbyRC.log" -IPG 2 -CommonRobocopyParams "/MIR /E /NP /R:10 /W:10 /ZB /XF $databaseFileName $databaseLogName"
    } 
    else
    {
        Write-CMTraceLog -Message "Start of Robocopy for ConfigMgr Backup Data with SQL Files to StandBy Server..."
        Start-RoboCopy -Source $sccmBackupPath -Destination $standBybackupPath -RobocopyLogPath "$logFilePath\StandbyRC.log" -IPG 2 -CommonRobocopyParams "/MIR /E /NP /R:10 /W:10 /ZB"
    }
}

# copy content library to standby Server or other destination for easy recovery
if ($copyContentLibrary -ieq 'Yes')
{
    Write-CMTraceLog -Message "Start of Robocopy for ContentLibrary..."
    $i = 0
    $contentLibraryPathLive | ForEach-Object { 
        $i++
     
        $sourceCLName = (get-item $_).Name
        $newcontentLibraryPathBackup = "$contentLibraryPathBackup\$sourceCLName"
        if (Test-Path $newcontentLibraryPathBackup)
        {
                #nothing to do
        }
        else
        { 
            # create content folder to copy files to it
            try 
            {
                $retval = mkdir "$newcontentLibraryPathBackup" -Force -ErrorAction Stop
            }
            catch
            {
                Write-CMTraceLog -Message "ContentLibrary folder could not be created: $newcontentLibraryPathBackup" -LogType 'LogAndEventlog' -type error
                Invoke-StopScriptIfError
            }
        }
        #NOTE run robocopy with /MIR only manually to prevent deletion of content library on the backup server
        Start-RoboCopy -Source $_ -Destination $newcontentLibraryPathBackup -RobocopyLogPath "$logFilePath\CLibraryRClog$i.log" -IPG 2 -CommonRobocopyParams "/MIR /E /NP /R:10 /W:10 /ZB" 
    }
    
}
#-----------------------------------------
#endregion Step 9 End
#-----------------------------------------


#-----------------------------------------
#region Step 10
#-----------------------------------------
# Delete old Backup Folders
# Exclude siteCode Backup folder and any other folder shorter then 34 caracters to prevent acidentally deletion. Not the best filter...
Write-CMTraceLog -Message "-------------------------------------"
Write-CMTraceLog -Message "------> Start to delete old backup folders..."
$foldersToDelete = $null
$foldersToDelete = Get-ChildItem -Path $sccmBackupPath -Directory | Where-Object {$_.Name -match '(\d{4}-\d{2}-\d{2}T\d{6})|(\d{8}-\d{6})'}
Write-CMTraceLog -Message "Folder to delete: $sccmBackupPath -> $($foldersToDelete.Count)"
Write-CMTraceLog -Message "Max Backups value: $maxBackups"
# sort to select the oldest folders
$foldersToDelete = $foldersToDelete | Sort-Object -Descending
# select the folders except the max Backup value
$foldersToDelete = $foldersToDelete | Select-Object -Skip $maxBackups

if ($null -eq $foldersToDelete)
{
    Write-CMTraceLog -Message "Nothing to delete."
}
else
{
    Write-CMTraceLog -Message "Delete folder..."
    $foldersToDelete | Delete-OldFolders -MaxBackupDays $maxBackupDays
}
#-----------------------------------------
#endregion Step 10 End
#-----------------------------------------

$stoptWatch.Stop()
$scriptDurationString = "{0}h:{1}m:{2}s" -f $stoptWatch.Elapsed.Hours, $stoptWatch.Elapsed.Minutes, $stoptWatch.Elapsed.Seconds
if ($global:SendSuccessMail -ieq 'Yes')
{
    $paramSplatting = @{
        SmtpServer = $global:MailServer
        To = $global:MailTo
        From = $global:MailFrom
        Subject = "Backup script finished on $($env:Computername)"
        Body = "Backup script finished on $($env:Computername)"
        #Attachments = $global:logFile
    }

    try 
    {
        Send-MailMessage @paramSplatting -ErrorAction Stop
    }
    catch 
    {
        Write-CMTraceLog -Type Error -Message "Mail could not be sent" -LogType 'LogAndEventlog'
        Write-CMTraceLog -Type Error -Message "Error: $($error[0].Exception)" -LogType 'LogAndEventlog'
    }
}
Write-CMTraceLog -Message "Stopping script! Runtime: $scriptDurationString" -LogType 'LogAndEventlog'
#-----------------------------------------
#region Step 11
#-----------------------------------------
# copy log and config file for easy access
Copy-Item -Path $logFile -Destination $sccmBackupPath -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -Path $configXMLFilePath -Destination $sccmBackupPath -Force -ErrorAction SilentlyContinue

if ($copyToStandByServer -ieq 'Yes')
{
    Copy-Item -Path $logFilePath -Destination $standBybackupPath -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path $configXMLFilePath -Destination $standBybackupPath -Force -ErrorAction SilentlyContinue
}
#-----------------------------------------
#endregion Step 11 End
#-----------------------------------------

# End Script
exit 0
