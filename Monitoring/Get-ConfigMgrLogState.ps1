<#
.Synopsis
    Get-ConfigMgrLogState is designed to monitor logfiles and output the result in different ways

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

    Get-ConfigMgrLogState is designed to monitor logfiles and output the result in different ways. (See parameter OutputMode for more details)
    If parameter -InScriptConfigFile is set to $true the script will use the contents of variable: $logEntryListJSON.
    If parameter -InScriptConfigFile is set to $false the script will use an external JSON config file called: "Get-ConfigMgrLogState.ps1.json"
    The file can be created by copying the contents of $logEntryListJSON from "$logEntryListJSON = @'" to "'@"
    The variable $logEntryListJSON also contains the documentation of the various settings. 
    The script needs to run at least as often as the lowest interval configured in $logEntryListJSON or the JSON file.
    
    There is one extra dependency  when HTMLMail is used as the outputmode. "Send-CustomMonitoringMail.ps1" is required in that case. 
    
    JSON definition:
    {
        "LogEntries": [
            {
                "Name": "Name of lofile or type of check to be performed",
                "Description": "Description of this item",
                "LogPath": "IMPORTANT: needs to have two backslash in path. Path to a logfile like this: C:\\temp\\logfile.log",
                "SuccessString": "String we expect in case of success. Lile 'Script successful'. Can also contain regular expression. Like: '(string1)|(string2)'",
                "Interval": "The interval we expect the SuccessString to be written. Possible values are: Daily, Weekly or Monthly",
                "IntervalDay": "The day we expect the SuccessString to be written if 'Interval' is set to Weekly or Monthly. Like: Monday or Tuesday",
                "IntervalWeek": "Only valid if 'Interval' is set to 'Monthly'. Number for the week we expect the SuccessString to be written. Like 2 for the second week in a month.",
                "IntervalTime": "Time we expect the SuccessString to be written in 24h format like 15:00",
                "TimespanMinutes": "Number of minutes to be added before and after 'IntervalTime'. 60 will add 60 minutes before and after to the value of 'IntervalTime'. Otherweise the script will only look for an entry at exactly 15:00 for example.",
                "DateFormat": "Date format of log entries. ONLY Cmtrace.exe log format supported at the moment. Either: DMY or MDY. DMY = day, month, year or ddMMyyyy | MDY = month, day, year or MMddyyy",
                "IgnorePreviousEntries": "Either true or false. If set to true and if we are probing before the time we would expect a log entry, we should not look one day, week or month back and test the last result instead",
                "RunOnActiveNodeOnly": "Either true or false. True means, the specific scan will only be performed if the ConfigMgr node running the script is the active node. (Only valid in ConfigMgr HA scenarios)",
                "RunOnSystemList": "Comma seperated list of system fqdns the check should be performed on. If empty, the test will be performed on any system"
            }
        ]
    }   

    IMPORTANT: 
    Parameter: "-OutputMode 'GridView'" shows each log line to have the search string and not just the overall result per check. Best for troubleshooting. 

.EXAMPLE
    .\Get-ConfigMgrLogState

.PARAMETER OutputMode
    Parameter to be able to output the results in a GridView, special JSON format, special JSONCompressed format,
    a simple PowerShell objekt PSObject or via HTMLMail.
    The HTMLMail mode requires the script "Send-CustomMonitoringMail.ps1" to be in the same folder.

.PARAMETER NoCacheState
    Switch parameter. If set the script will NOT output its current state to a JSON file.
    If not set the script will always cache its state to a JSON file.
    The file will be stored next to the script or a path set via parameter "CachePath"
    The filename will look like this: [name-of-script.ps1]_[Name of user running the script]_CACHE.json

.PARAMETER CachePath
    Path to store the JSON cache file. Default value is root path of script. 

.PARAMETER ProbeTime 
    Datetime parameter to be able to set a specific datetime to simulate a script run in the past or future. Example value: (Get-Date('2022-06-14 01:00'))
    Can help to simulate a specific run date and run time for the script. If not specific the current local datetime will be used

.PARAMETER PrtgLookupFileName
    Name of a PRTG value lookup file. 

.PARAMETER InScriptConfigFile
    Is set the embedded config in a here-String as $referenceDataJSON will be used instead of an external file
    This can be helpful if the script should not have an external config file.
    If not set the script will look for a file called Get-ConfigMgrInboxFileCount.ps1.json either next to this script or in the 
    path specified via parameter -ConfigFilePath

.PARAMETER ConfigFilePath
    Path to the configfile called Get-ConfigMgrInboxFileCount.ps1.json. JSON can be created using the content of the in script variable $logEntryListJSON

.PARAMETER WriteLog
    Switch parameter If set, the script will write a log. Helpful during testing. 

.PARAMETER LogPath
    Path of the log file if parameter -WriteLog $true. The script will create the logfile next to the script if no path specified.

.PARAMETER DontOutputScriptstate
    If set the script will NOT output its overall state as an extra object. Otherwise the script will output its state. 

.PARAMETER TestMode
    If set, the script will use the value of parameter -OutputTestData to output dummy data objects

.PARAMETER OutputTestData
    NOT USED at the momment. Number of dummy test data objects. Helpful to test a monitoring solution without any actual ConfigMgr errors.

.PARAMETER SendAllMails
    If set, the script will send an email even if there are no errors.

.EXAMPLE
    .\Get-ConfigMgrLogState

.EXAMPLE
    .\Get-ConfigMgrLogState -OutputMode 'GridView'

.EXAMPLE
    .\Get-ConfigMgrLogState -ProbeTime (Get-Date('2022-06-14 01:00'))

.EXAMPLE
    .\Get-ConfigMgrLogState -WriteLog

.EXAMPLE
    .\Get-ConfigMgrLogState -WriteLog-LogPath "C:\Temp"

.INPUTS
   None

.OUTPUTS
   Depends on OutputMode

.LINK
    https://github.com/jonasatgit/scriptrepo

#>
[CmdletBinding()]
param
(
    [parameter(Mandatory=$false,ValueFromPipeline=$false)]
    [datetime]$ProbeTime = (get-date), # Test example: (Get-Date('2022-06-14 01:00'))
    [Parameter(Mandatory=$false)]
    [ValidateSet("JSON","GridView", "MonAgentJSON", "MonAgentJSONCompressed","HTMLMail","PSObject","PrtgString","PrtgJSON")]
    [String]$OutputMode = "PSObject",
    [Parameter(Mandatory=$false)]
    [String]$MailInfotext = 'Status about monitored logfiles. This email is sent every day!',
    [Parameter(Mandatory=$false)]
    [switch]$NoCacheState,
    [Parameter(Mandatory=$false)]
    [string]$CachePath,
    [Parameter(Mandatory=$false)]
    [string]$PrtgLookupFileName,
    [Parameter(Mandatory=$false)]
    [switch]$InScriptConfigFile,  
    [Parameter(Mandatory=$false)]
    [string]$ConfigFilePath,     
    [Parameter(Mandatory=$false)]
    [switch]$WriteLog,
    [Parameter(Mandatory=$false)]
    [string]$LogPath,
    [Parameter(Mandatory=$false)]
    [switch]$DontOutputScriptstate,
    [Parameter(Mandatory=$false)]
    [switch]$TestMode,
    [Parameter(Mandatory=$false)]
    [ValidateRange(0,60)]
    [int]$OutputTestData=0,
    [Parameter(Mandatory=$false)]
    [switch]$SendAllMails
)

#region admin check
#Ensure that the Script is running with elevated permissions
if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Warning 'The script needs admin rights to run. Start PowerShell with administrative rights and run the script again'
    return 
}
#endregion


#region log entry list
$logEntryListJSON = @'
{
    "DOCUMENTATION": [
        {
            "Name": "Name of logfile or type of check to be performed",
            "Description": "Description of this item",
            "LogPath": "IMPORTANT: needs to have two backslashes in path. Path to a logfile like this: C:\\temp\\logfile.log",
            "SuccessString": "String we expect in case of success. Like: 'Script successful'. Can also contain regular expression. Like: '(string1)|(string2)'",
            "Interval": "The interval we expect the SuccessString to be written. Possible values are: Daily, Weekly or Monthly",
            "IntervalDay": "The day we expect the SuccessString to be written if 'Interval' is set to Weekly or Monthly. Like: Monday or Tuesday",
            "IntervalWeek": "Only valid if 'Interval' is set to 'Monthly'. Number for the week we expect the SuccessString to be written. Like 2 for the second week in a month.",
            "IntervalTime": "Time we expect the SuccessString to be written in 24h format like 15:00",
            "TimespanMinutes": "Number of minutes to be added before and after 'IntervalTime'. 60 will add 60 minutes before and after to the value of 'IntervalTime'. Otherweise the script will only look for an entry at exactly 15:00 for example.",
            "DateFormat": "Date format of log entries. ONLY Cmtrace.exe log format supported at the moment. Either: DMY or MDY. DMY = day, month, year or ddMMyyyy | MDY = month, day, year or MMddyyy",
            "IgnorePreviousEntries": "Either true or false. If set to true and if we are probing before the time we would expect a log entry, we should not look one day, week or month back and test the last result instead",
            "RunOnActiveNodeOnly": "Either true or false. True means, the specific scan will only be performed if the ConfigMgr node running the script is the active node. (Only valid in ConfigMgr HA scenarios)",
            "RunOnSystemList": "Comma seperated list of system fqdns the check should be performed on. If empty, the test will be performed on any system"
        }
    ],
    "LogEntries": [
            {
                "Name": "Configmgr Backup Monitor",
                "Description": "Will monitor backup stuff",
                "LogPath": "E:\\Program Files\\Microsoft Configuration Manager\\Logs\\smsbkup.log",
                "SuccessString": "Backup completed",
                "Interval": "Daily",
                "IntervalDay": "",
                "IntervalWeek": 0,
                "IntervalTime": "02:00",
                "TimespanMinutes": 60,
                "DateFormat": "MDY",
                "IgnorePreviousEntries": true,
                "RunOnActiveNodeOnly": true,
                "RunOnSystemList": ""
            },
            {
                "Name": "ConfigMgr PatchCycle Monitor",
                "Description": "Will validate patch stuff",
                "LogPath": "E:\\CUSTOM\\LogTest\\monthlytest.log",
                "SuccessString": "Script done!",
                "Interval": "Monthly",
                "IntervalDay": "Tuesday",
                "IntervalWeek": 2,
                "IntervalTime": "22:00",
                "TimespanMinutes": 60,
                "DateFormat": "MDY",
                "IgnorePreviousEntries": false,
                "RunOnActiveNodeOnly": false,
                "RunOnSystemList": "test1.contoso.local"
            },
            {
                "Name": "ConfigMgr weekly Collection export",
                "Description": "Will export weekly stuff",
                "LogPath": "E:\\CUSTOM\\LogTest\\weeklytest.log",
                "SuccessString": "Collections exported!",
                "Interval": "Monthly",
                "IntervalDay": "Tuesday",
                "IntervalWeek": 2,
                "IntervalTime": "22:00",
                "TimespanMinutes": 60,
                "DateFormat": "MDY",
                "IgnorePreviousEntries": true,
                "RunOnActiveNodeOnly": false,
                "RunOnSystemList": ""
            },
            {
                "Name": "ConfigMgr no there test",
                "Description": "Will export weekly stuff",
                "LogPath": "E:\\CUSTOM\\LogTest\\weeklytest-missing.log",
                "SuccessString": "Collections exported!",
                "Interval": "Weekly",
                "IntervalDay": "Wednesday",
                "IntervalWeek": 0,
                "IntervalTime": "22:00",
                "TimespanMinutes": 60,
                "DateFormat": "MDY",
                "IgnorePreviousEntries": true,
                "RunOnActiveNodeOnly": false,
                "RunOnSystemList": ""
            },
            {
                "Name": "DAILY TEST",
                "Description": "Will export daily stuff",
                "LogPath": "E:\\CUSTOM\\LogTest\\dailytest.log",
                "SuccessString": "Important log line",
                "Interval": "Daily",
                "IntervalDay": "",
                "IntervalWeek": 0,
                "IntervalTime": "03:00",
                "TimespanMinutes": 120,
                "DateFormat": "MDY",
                "IgnorePreviousEntries": false,
                "RunOnActiveNodeOnly": false,
                "RunOnSystemList": ""
            }
    ]
}
'@
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

    If (($OutputMode -eq "Console") -or ($OutputMode -eq "ConsoleAndLog"))
    {
        Write-Host $Message -ForegroundColor $color
    }
    
    If (($OutputMode -eq "Log") -or ($OutputMode -eq "ConsoleAndLog"))
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

#region Test-ConfigMgrActiveSiteSystemNode
<#
.Synopsis
   function Test-ConfigMgrActiveSiteSystemNode 

.DESCRIPTION
   Test if a given FQDN is the active ConfigMgr Site System node
   Function to read from HKLM:\SOFTWARE\Microsoft\SMS\Identification' 'Site Servers' and determine the active site server node
   Possible values could be: 
        1;server1.contoso.local;
       1;server1.contoso.local;0;server2.contoso.local;
        0;server1.contoso.local;1;server2.contoso.local;

.PARAMETER SiteSystemFQDN
   FQDN of site system

.EXAMPLE
   Test-ConfigMgrActiveSiteSystemNode -SiteSystemFQDN 'server1.contoso.local'
#>
function Test-ConfigMgrActiveSiteSystemNode
{
    param
    (
        [string]$SiteSystemFQDN
    )

    $siteServers = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\SMS\Identification' -Name 'Site Servers' -ErrorAction SilentlyContinue
    if ($siteServers)
    {
        # Extract site system values from registry property 
        $siteSystemHashTable = @{}
        $siteSystems = [regex]::Matches(($siteServers.'Site Servers'),'(\d;[a-zA-Z0-9._-]+)')
        if($siteSystems.Count -gt 1)
        {
            # HA site systems found
            foreach ($SiteSystemNode in $siteSystems)
            {
                $tmpArray = $SiteSystemNode.value -split ';'
                $siteSystemHashTable.Add($tmpArray[1].ToLower(),$tmpArray[0]) 
            }
        }
        else
        {
            # single site system found
            $tmpArray = $siteSystems.value -split ';'
            $siteSystemHashTable.Add($tmpArray[1].ToLower(),$tmpArray[0]) 
        }
        
        return $siteSystemHashTable[($SiteSystemFQDN).ToLower()]
    }
    else
    {
        return $null
    }
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

#region ConvertTo-CustomMonitoringObject
<# 
.Synopsis
   Function ConvertTo-CustomMonitoringObject

.DESCRIPTION
   Will convert a specific input object to a custom JSON like object
   Which then can be used as an input object for a custom monitoring solution

.PARAMETER InputObject
   Well defined input object

.EXAMPLE
   $CustomObject | ConvertTo-CustomMonitoringObject
#>
Function ConvertTo-CustomMonitoringObject
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [object]$InputObject,
        [Parameter(Mandatory=$true)]
        [ValidateSet("MonAgentObject", "PrtgObject")]
        [string]$OutputType,
        [Parameter(Mandatory=$false)]
        [string]$PrtgLookupFileName        
    )

    Begin
    {
        $resultsObject = New-Object System.Collections.ArrayList
        switch ($OutputType)
        {
            'MonAgentObject'
            {
                $outObject = New-Object psobject | Select-Object InterfaceVersion, Results
                $outObject.InterfaceVersion = 1  
            }
            'PrtgObject'
            {
                $outObject = New-Object psobject | Select-Object prtg
            }
        }  
    }
    Process
    {
        switch ($OutputType) 
        {
            'MonAgentObject' 
            {  
                # Adding infos to short description field
                Switch ($InputObject.CheckType)
                {
                    'Certificate'
                    {
                        [string]$shortDescription = $InputObject.Description -replace "\'", "" -replace '>','_' # Remove some chars like quotation marks or >    
                    }
                    'Inbox'
                    {
                        [string]$shortDescription = $InputObject.Description -replace "\'", "" -replace '>','_' # Remove some chars like quotation marks or >    
                    }
                    Default 
                    {
                        [string]$shortDescription = '{0}:{1}:{2}' -f $InputObject.Name, $env:COMPUTERNAME, ($InputObject.Description -replace "\'", "" -replace '>','_') # Remove some chars like quotation marks or >
                    }
                }

                # ShortDescription has a 300 character limit
                if ($shortDescription.Length -gt 300)
                {
                    $shortDescription = $shortDescription.Substring(0, 299) 
                } 


                switch ($InputObject.Status) 
                {
                    'Ok' {$outState = 0}
                    'Warning' {$outState = 1}
                    'Error' {$outState = 2}
                    Default {$outState = 3}
                }

                $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
                $tmpResultObject.Name = $InputObject.Name -replace "\'", "" -replace '>','_'
                $tmpResultObject.Epoch = 0 # NOT USED at the moment. FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
                $tmpResultObject.Status = $outState
                $tmpResultObject.ShortDescription = $shortDescription
                $tmpResultObject.Debug = ''
                [void]$resultsObject.Add($tmpResultObject)
            }
            'PrtgObject'
            {
                if ($PrtgLookupFileName)
                {
                    $tmpResultObject = New-Object psobject | Select-Object Channel, Value, ValueLookup
                    $tmpResultObject.ValueLookup = $PrtgLookupFileName
                }
                else 
                {
                    $tmpResultObject = New-Object psobject | Select-Object Channel, Value
                }
               
                $tmpResultObject.Channel = $InputObject.Name -replace "\'", "" -replace '>','_'
                if ($InputObject.Status -ieq 'Ok')
                {
                    $tmpResultObject.Value = 0
                }
                else
                {
                    $tmpResultObject.Value = 1
                }                    
                [void]$resultsObject.Add($tmpResultObject)  
            }
        }                  
    }
    End
    {
        switch ($OutputType)
        {
            'MonAgentObject'
            {
                $outObject.Results = $resultsObject
                $outObject
            }
            'PrtgObject'
            {
                $tmpPrtgResultObject = New-Object psobject | Select-Object result
                $tmpPrtgResultObject.result = $resultsObject
                $outObject.prtg = $tmpPrtgResultObject
                $outObject
            }
        }  

    }
}
#endregion

#region log path
if ($WriteLog)
{
    if (-NOT($LogPath))
    {
        $Global:LogFilePath = '{0}\{1}.log' -f $PSScriptRoot ,($MyInvocation.MyCommand)
    }
    else 
    {
        $Global:LogFilePath = '{0}\{1}.log' -f $LogPath, ($MyInvocation.MyCommand)
    }
}
if($WriteLog){Write-CMTraceLog -Message " " -Component ($MyInvocation.MyCommand)}
if($WriteLog){Write-CMTraceLog -Message "Script startet" -Component ($MyInvocation.MyCommand)}
#endregion

#region system name
# get system FQDN if possible
$win32Computersystem = Get-WmiObject -Class win32_computersystem -ErrorAction SilentlyContinue
if ($win32Computersystem)
{
    $systemName = '{0}.{1}' -f $win32Computersystem.Name, $win32Computersystem.Domain   
}
else
{
    $systemName = $env:COMPUTERNAME
}
#endregion


#region pre main log logic
# temp results object and corresponding property list
[array]$propertyList = 'Name'
$propertyList += 'CheckType'
$propertyList += 'Status'
$propertyList += 'Description'
$propertyList += 'LogPath'
$propertyList += 'LogDateTime'
$propertyList += 'ProbeTime'
$propertyList += 'StartTime'
$propertyList += 'EndTime'
$propertyList += 'Interval'
$propertyList += 'IntervalDay'
$propertyList += 'IntervalWeek'
$propertyList += 'SuccessString'
$propertyList += 'LineNumber'
$propertyList += 'Line'
#$propertyList += 'Thread'
$propertyList += 'TimeZoneOffset'
$propertyList += 'ItemDescription'
$propertyList += 'NodeType'
$propertyList += 'RunOnSystemList'

if (-NOT($CachePath))
{
    $CachePath = $PSScriptRoot
}
#endregion

#region Generic Script state object
# We always need a generic script state object. Especially if we have no errors
$tmpScriptStateObj = New-Object psobject | Select-Object $propertyList
$tmpScriptStateObj.Name = 'Script:{0}' -f $systemName 
$tmpScriptStateObj.CheckType = 'Script'
$tmpScriptStateObj.Status = 'Ok'
$tmpScriptStateObj.Description = "Overall state of script"
#endregion

#region get config data
if ($InScriptConfigFile)
{
    if($WriteLog){Write-CMTraceLog -Message "Using in script config file" -Component ($MyInvocation.MyCommand)}
    $logEntryListJSONObject = $logEntryListJSON | ConvertFrom-Json
}
else 
{
    if (-NOT($ConfigFilePath))
    {
        $ConfigFilePath = $PSScriptRoot
        $configFileFullName = '{0}\{1}.json' -f $ConfigFilePath, ($MyInvocation.MyCommand)
    }
    else 
    {
        # Do we have a path or a file?
        if ($ConfigFilePath -match '\.json')
        {
            $configFileFullName = $ConfigFilePath
        }
        else 
        {
            $configFileFullName = '{0}\{1}.json' -f $ConfigFilePath, ($MyInvocation.MyCommand)
        }
    }    
    
    if($WriteLog){Write-CMTraceLog -Message "Using: $configFileFullName" -Component ($MyInvocation.MyCommand)}
    if (Test-Path $configFileFullName)
    {
        $logEntryListJSONObject = Get-Content -Path $configFileFullName | ConvertFrom-Json
    }
    else 
    {
        $tmpScriptStateObj.Status = 'Error'
        $tmpScriptStateObj.Description = ('Path not found: {0}' -f $configFileFullName)
    }
}
#endregion

#region MAIN LOG LOGIC
$logEntrySearchResultList = New-Object System.Collections.ArrayList
if ($TestMode)
{
    if($WriteLog){Write-CMTraceLog -Message "Will create $OutputTestData test alarms" -Component ($MyInvocation.MyCommand)}
    # create dummy entries
    for ($i = 1; $i -le $OutputTestData; $i++)
    { 
        $tmpLogEntryObject = New-Object PSCustomObject | Select-Object $propertyList
        $tmpLogEntryObject.Name = 'DummyData:Logentry_{0}' -f $i.ToString('00')
        $tmpLogEntryObject.CheckType = 'DummyData'
        $tmpLogEntryObject.Status = "Error" # Set to nothing to force string format
        $tmpLogEntryObject.Description = "This is just a dummy data object" # Set to nothing to force string format
        $tmpLogEntryObject.LogPath = "C:\Windows\logs\CBS\CBS.log"
        $tmpLogEntryObject.LogDateTime = (Get-Date).AddDays(-1)
        $tmpLogEntryObject.ProbeTime = Get-Date
        $tmpLogEntryObject.StartTime = (Get-Date).AddMinutes(-120)
        $tmpLogEntryObject.EndTime = (Get-Date).AddMinutes(120)
        $tmpLogEntryObject.Interval = $logEntryItem.Interval
        $tmpLogEntryObject.IntervalDay = $logEntryItem.IntervalDay
        $tmpLogEntryObject.IntervalWeek = 0
        $tmpLogEntryObject.SuccessString = "(Update Installed)|(Success)"
        $tmpLogEntryObject.LineNumber = Get-Random -Minimum 1 -Maximum 5000
        $tmpLogEntryObject.Line = "The was Update Installed" # Set to nothing to force string format
        #$tmpLogEntryObject.Thread = "" # Set to nothing to force string format
        $tmpLogEntryObject.TimeZoneOffset = "60" # Set to nothing to force string format
        $tmpLogEntryObject.ItemDescription = 'Dummy entry'
        $tmpLogEntryObject.NodeType = "Active" # Set to nothing to force string format
        $tmpLogEntryObject.RunOnSystemList = 'server01.contoso.local'
        [void]$logEntrySearchResultList.Add($tmpLogEntryObject)
    }
}
else 
{
    # Parse logentries from JSON
    foreach ($logEntryItem in $logEntryListJSONObject.LogEntries)
    {
        if($WriteLog){Write-CMTraceLog -Message "Working on: $($logEntryItem.LogPath)" -Component ($MyInvocation.MyCommand)}
        Write-Verbose "$("{0,-35}-> Working on: {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))"
        $timeSpanObject = $null
        $timeSpanObject = New-Object PSCustomObject | Select-Object StartTime, EndTime
        # will be set to false if we are running the script before the calculated datetime and if IgnorePreviousEntries is set to $true
        # IgnorePreviousEntries = $true means, if we are before the calculated datetime, we should not look one day, week or month back and test the last result instead
        # We simply ignore the log for now in that case
        $checkRequired = $true 
        # Tmp object to track log parse status
        $tmpLogEntryObject = New-Object PSCustomObject | Select-Object $propertyList
        $tmpLogEntryObject.Name = 'LogCheck:{0}' -f $logEntryItem.Name
        $tmpLogEntryObject.CheckType = 'LogCheck'
        $tmpLogEntryObject.Status = "" # Set to nothing to force string format
        $tmpLogEntryObject.Description = "" # Set to nothing to force string format
        $tmpLogEntryObject.LogPath = $logEntryItem.LogPath
        $tmpLogEntryObject.LogDateTime #= [datetime]::MinValue # Set to min value to force datime format
        $tmpLogEntryObject.ProbeTime = $ProbeTime
        $tmpLogEntryObject.StartTime #= [datetime]::MinValue # Set to min value to force datime format
        $tmpLogEntryObject.EndTime #= [datetime]::MinValue # Set to min value to force datime format
        $tmpLogEntryObject.Interval = $logEntryItem.Interval
        $tmpLogEntryObject.IntervalDay = $logEntryItem.IntervalDay
        $tmpLogEntryObject.IntervalWeek = $logEntryItem.IntervalWeek
        $tmpLogEntryObject.SuccessString = $logEntryItem.SuccessString
        $tmpLogEntryObject.LineNumber = 0 # Set to zero to force int format
        $tmpLogEntryObject.Line = "" # Set to nothing to force string format
        #$tmpLogEntryObject.Thread = "" # Set to nothing to force string format
        $tmpLogEntryObject.TimeZoneOffset = "" # Set to nothing to force string format
        $tmpLogEntryObject.ItemDescription = $logEntryItem.Description
        $tmpLogEntryObject.NodeType = "" # Set to nothing to force string format
        $tmpLogEntryObject.RunOnSystemList = $logEntryItem.RunOnSystemList


        $DateFormat = "yyyy-MM-dd"
        # We need to calculate the log datetime based on the definition first
        # We then create a TimeSpan object in which the log event needs to happen
        Switch ($logEntryItem.Interval) 
        {
            "Hourly" 
            {
                Write-Error "$("{0,-35}-> Hourly not implemented yet" -f  $($logEntryItem.Name))"
                if($WriteLog){Write-CMTraceLog -Message "Hourly not implemented yet" -Severity Error -Component ($MyInvocation.MyCommand)}
            }
            "Daily" 
            {
                # Date and time the action should have happened
                $calculatedDateTime = Get-Date($ProbeTime) -format "$DateFormat $($logEntryItem.IntervalTime)"
                $timeSpanObject.StartTime = (Get-Date($calculatedDateTime)).AddMinutes(-$logEntryItem.TimespanMinutes)
                $timeSpanObject.EndTime = (Get-Date($calculatedDateTime)).AddMinutes($logEntryItem.TimespanMinutes)
                # We need to check if we are running the script before or after the calculated time to not look at the wrong timeframe
                if ((get-date($ProbeTime)) -lt $timeSpanObject.EndTime)
                {
                    Write-Verbose "$("{0,-35}-> Probetime before calculated logtime" -f  $($logEntryItem.Name))"
                    # IgnorePreviousEntries = $false means, we should look one day back and test the last result instead
                    if ($logEntryItem.IgnorePreviousEntries -eq $false)
                    {
                        Write-Verbose "$("{0,-35}-> IgnorePreviousEntries=false. Wee need to look one day back." -f  $($logEntryItem.Name))"
                        $calculatedDateTime = (get-date($calculatedDateTime)).AddDays(-1) # Looking one day back
                        $timeSpanObject.StartTime = (Get-Date($calculatedDateTime)).AddMinutes(-$logEntryItem.TimespanMinutes)
                        $timeSpanObject.EndTime = (Get-Date($calculatedDateTime)).AddMinutes($logEntryItem.TimespanMinutes)
                    }
                    # IgnorePreviousEntries = $true means, we should NOT look one day back and skip the test for now
                    else 
                    {
                        $checkRequired = $false
                        Write-Verbose "$("{0,-35}-> No check required. Probetime before calculated logtime and IgnorePreviousEntries=true" -f  $($logEntryItem.Name))"
                    }
                }
                $tmpLogEntryObject.StartTime = $timeSpanObject.StartTime
                $tmpLogEntryObject.EndTime  = $timeSpanObject.EndTime
            }
            "Weekly" 
            {
                $calculatedDateTime = Get-Date($ProbeTime) -format "$DateFormat $($logEntryItem.IntervalTime)"
                # looking for the correct day in the past if we are not running on the specific day
                $calculatedDateTime = (Get-Date($calculatedDateTime))
                while ($calculatedDateTime.DayOfWeek -ine $logEntryItem.IntervalDay)
                {
                    Write-Verbose "$("{0,-35}-> Looking for the correct day. Calculated: {1} Looking for: {2}" -f  $($logEntryItem.Name), $($calculatedDateTime.DayOfWeek), $($logEntryItem.IntervalDay))"
                    # looking for the exact date of a day specified in the log definition. 
                    # Like Wednesday of the current week.
                    $calculatedDateTime = $calculatedDateTime.AddDays(-1) # going one day back and test again
                }
                Write-Verbose "$("{0,-35}-> Looking for the correct day. Calculated: {1} Looking for: {2}" -f  $($logEntryItem.Name), $($calculatedDateTime.DayOfWeek), $($logEntryItem.IntervalDay))"

                $timeSpanObject.StartTime = (Get-Date($calculatedDateTime)).AddMinutes(-$logEntryItem.TimespanMinutes)
                $timeSpanObject.EndTime = (Get-Date($calculatedDateTime)).AddMinutes($logEntryItem.TimespanMinutes)
                    
                if ((get-date($ProbeTime)) -lt $timeSpanObject.EndTime)
                {
                    Write-Verbose "$("{0,-35}-> Probetime before calculated logtime" -f  $($logEntryItem.Name))"
                    # IgnorePreviousEntries = $false means, we should look one week back and test the last result instead
                    if ($logEntryItem.IgnorePreviousEntries -eq $false)
                    {
                        Write-Verbose "$("{0,-35}-> IgnorePreviousEntries=false. Wee need to look one week back." -f  $($logEntryItem.Name))"
                        # going one week back, since we are probing before the calculated datetime and we are allowed to look one week back
                        $calculatedDateTime = $calculatedDateTime.AddDays(-7)
                        $timeSpanObject.StartTime = (Get-Date($calculatedDateTime)).AddMinutes(-$logEntryItem.TimespanMinutes)
                        $timeSpanObject.EndTime = (Get-Date($calculatedDateTime)).AddMinutes($logEntryItem.TimespanMinutes)              
                    }
                    # IgnorePreviousEntries = $true means, we should NOT look one day back and skip the test for now
                    else 
                    {
                        $checkRequired = $false
                        Write-Verbose "$("{0,-35}-> No check required. Probetime before calculated logtime and IgnorePreviousEntries=true" -f  $($logEntryItem.Name))"
                    }
                }
                $tmpLogEntryObject.StartTime = $timeSpanObject.StartTime
                $tmpLogEntryObject.EndTime  = $timeSpanObject.EndTime
            }
            "Monthly" 
            {
                $calculatedDateTime = Find-DayOfWeek -Weekday $logEntryItem.IntervalDay -Week $logEntryItem.IntervalWeek -Time $logEntryItem.IntervalTime -StartDate $ProbeTime
                $timeSpanObject.StartTime = (Get-Date($calculatedDateTime)).AddMinutes(-$logEntryItem.TimespanMinutes)
                $timeSpanObject.EndTime = (Get-Date($calculatedDateTime)).AddMinutes($logEntryItem.TimespanMinutes)
                    
                if ((get-date($ProbeTime)) -lt $timeSpanObject.EndTime)
                {
                    Write-Verbose "$("{0,-35}-> Probetime before calculated logtime" -f  $($logEntryItem.Name))"
                    # IgnorePreviousEntries = $false means, we should look one day back and test the last result instead
                    if ($logEntryItem.IgnorePreviousEntries -eq $false)
                    {
                        Write-Verbose "$("{0,-35}-> IgnorePreviousEntries=false. Wee need to look one month back." -f  $($logEntryItem.Name))"
                        $calculatedDateTime = Find-DayOfWeek -Weekday $logEntryItem.IntervalDay -Week $logEntryItem.IntervalWeek -Time $logEntryItem.IntervalTime -StartDate ((get-date($calculatedDateTime)).AddMonths(-1))
                        $timeSpanObject.StartTime = (Get-Date($calculatedDateTime)).AddMinutes(-$logEntryItem.TimespanMinutes)
                        $timeSpanObject.EndTime = (Get-Date($calculatedDateTime)).AddMinutes($logEntryItem.TimespanMinutes)
                    }
                    # IgnorePreviousEntries = $true means, we should NOT look one day back and skip the test for now
                    else 
                    {
                        $checkRequired = $false
                        Write-Verbose "$("{0,-35}-> No check required. Probetime before calculated logtime and IgnorePreviousEntries=true" -f  $($logEntryItem.Name))"
                    }
                }
                $tmpLogEntryObject.StartTime = $timeSpanObject.StartTime
                $tmpLogEntryObject.EndTime  = $timeSpanObject.EndTime
            }
        } 
        # Done with time calculations

        # Validate if we need to run any check
        if ($checkRequired -eq $false)
        {
            # Nothing to for now for this log file
            $tmpLogEntryObject.Status = "OK"
            $tmpLogEntryObject.Description = "Probe time before log time. Nothing to do"
            [void]$logEntrySearchResultList.Add($tmpLogEntryObject)
            Write-Verbose "$("{0,-35}-> Probetime before calculated logtime. Nothing to do." -f  $($logEntryItem.Name))"
        }
        else 
        {
            # Check if we are only allowed to run the test on an active ConfigMgr site server
            # Or if we are allowed regardless of any active passive node
            # And only if RunOnSystemList either contains no entry or the correct servername
            $allowedToRun = $false
            if ([string]::IsNullOrEmpty($logEntryItem.RunOnSystemList))
            {
                $allowedToRun = $true      
            }
            else
            {
                if (($logEntryItem.RunOnSystemList) -match $systemName)
                {
                    $allowedToRun = $true   
                }
            }

            $isActiveNode = $false
            $isPassiveNode = $false
            $isNoNode = $false
            Switch (Test-ConfigMgrActiveSiteSystemNode -SiteSystemFQDN $systemName)
            {
                0{$isPassiveNode = $true;$nodeType = 'Passive'}
                1{$isActiveNode = $true;$nodeType = 'Active'}
                Default{$isNoNode = $true;$nodeType = 'NoConfigMgrNode'}
            }
            $tmpLogEntryObject.NodeType = $nodeType
                
            # Simpler representation: -> If (((RunOnActiveNodeOnly = $true -and IsActiveNode = $true) -or RunOnActiveNodeOnly = $false) -and $allowedToRun)
            if (((($logEntryItem.RunOnActiveNodeOnly) -and ($isActiveNode)) -or $logEntryItem.RunOnActiveNodeOnly -eq $false) -and $allowedToRun)
            {
                if (-NOT(Test-Path -Path $logEntryItem.LogPath))
                {
                    $tmpLogEntryObject.Status = "Error"
                    $tmpLogEntryObject.Description = 'Path not found: {0}' -f $logEntryItem.LogPath
                    [void]$logEntrySearchResultList.Add($tmpLogEntryObject)
                    Write-Verbose "$("{0,-35}-> Path not found: {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))" 
                }
                else 
                {
                    if ($timeSpanObject.StartTime)
                    {
                        $tmpLogEntryObject.StartTime = $timeSpanObject.StartTime
                        $tmpLogEntryObject.EndTime  = $timeSpanObject.EndTime

                        # Looking for given log entry
                        $foundLogEntryInTimeFrame = $false
                        $parseResult = Select-String -Path $logEntryItem.LogPath -Pattern $logEntryItem.SuccessString
                        If ($parseResult)
                        {
                            foreach($resultLine in $parseResult)
                            {
                                # Custom object per found log entry
                                $tmpLogLineObject = New-Object PSCustomObject | Select-Object $propertyList
                                $tmpLogLineObject.Name = 'LogCheck:{0}' -f $logEntryItem.Name
                                $tmpLogLineObject.CheckType = 'LogCheck'
                                $tmpLogLineObject.Status = "" # Set to nothing to force string format
                                $tmpLogLineObject.Description = "" # Set to nothing to force string format
                                $tmpLogLineObject.ProbeTime = $ProbeTime
                                $tmpLogLineObject.StartTime = $timeSpanObject.StartTime
                                $tmpLogLineObject.EndTime  = $timeSpanObject.EndTime
                                $tmpLogLineObject.Interval = $logEntryItem.Interval
                                $tmpLogLineObject.IntervalDay = $logEntryItem.IntervalDay
                                $tmpLogLineObject.IntervalWeek = $logEntryItem.IntervalWeek
                                $tmpLogLineObject.LogPath = $logEntryItem.LogPath
                                $tmpLogLineObject.SuccessString = $logEntryItem.SuccessString
                                $tmpLogLineObject.Line = $resultLine.Line
                                $tmpLogLineObject.LineNumber = $resultLine.LineNumber
                                $tmpLogLineObject.ItemDescription = $logEntryItem.Description
                                $tmpLogLineObject.NodeType = $nodeType
                                $tmpLogLineObject.RunOnSystemList = $logEntryItem.RunOnSystemList
                                                        
                                # Parsing log line mainly to extract datetime by looking for different datetime strings
                            
                                # Log line example: 
                                # <04-04-2022 02:16:54.419+420>"
                                $Matches = $null # resetting matches
                                $null = $resultLine.Line -match "(?<datetime>\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}.\d*(\+|\-)\d*)"
                                if ($Matches)
                                {
                                    Write-Verbose "$("{0,-35}-> DateTime extracted from logline: {1} of log: {2}" -f  $($logEntryItem.Name), $($resultLine.LineNumber) ,$($logEntryItem.LogPath))"
                                    #$tmpLogLineObject.Thread = (($Matches.thread) -replace "(thread=)", "")
                                
                                    # splitting at timezone offset -> plus or minus 480 for example: '02-22-2021 03:19:10.431+480'
                                    $datetimeSplit = (($Matches.datetime) -split '(\+|\-)(\d*$)') -split '\.' # last split is to remove milliseconds
                                    Switch ($logEntryItem.DateFormat)
                                    {
                                        'DMY'
                                        {
                                            $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeSplit[0], 'dd-MM-yyyy HH:mm:ss', $null)
                                        }
                                        'MDY'
                                        {
                                            $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeSplit[0], 'MM-dd-yyyy HH:mm:ss', $null)
                                        }
                                    }
                                
                                    # adding timezoneoffset $datetimeSplit[2] = "+ or -", $datetimeSplit[3] = minutes
                                    $tmpLogLineObject.TimeZoneOffset = "{0}{1}" -f $datetimeSplit[2], $datetimeSplit[3]
                                }
                                
                                if (-NOT ($tmpLogLineObject.LogDateTime))
                                {
                                    # Log line example:
                                    # "<time="05:37:21.726-420" date="06-14-2022" component="Backup-ConfigMgrData.ps1" context="" type="1" thread="2316" file="Backup-ConfigMgrData.ps1">"
                                    $Matches = $null # resetting matches
                                    $null = $resultLine.Line -match '(?<time>time="\d{2}:\d{2}:\d{2}.\d*(\+|\-)\d*).*(?<date>date="\d{1,2}-\d{1,2}-\d{4})'
                                    if ($Matches)
                                    {
                                        Write-Verbose "$("{0,-35}-> Date and Time seperatly extracted from logline: {1} of log: {2}" -f  $($logEntryItem.Name), $($resultLine.LineNumber) ,$($logEntryItem.LogPath))"
                                        #$tmpLogLineObject.Thread = (($Matches.thread) -replace '(thread=")', '')
                                    
                                        # splitting at timezone offset -> plus or minus 480 for example: '02-22-2021 03:19:10.431+480'
                                        $timeSplit = (($Matches.time -replace '(Time=")', '') -split '(\+|\-)(\d*$)') -split '\.' # last split is to remove milliseconds
                                        $datetimeString = "{0} {1}" -f ($Matches.date -replace '(Date=")', ''), $timeSplit[0]

                                        Switch -Regex ($datetimeString)
                                        {
                                            '\d{1}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}' 
                                            {
                                                Switch ($logEntryItem.DateFormat)
                                                {
                                                    'DMY'
                                                    {
                                                        $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeString, 'd-MM-yyyy HH:mm:ss', $null)
                                                    }
                                                    'MDY'
                                                    {
                                                        $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeString, 'M-dd-yyyy HH:mm:ss', $null)
                                                    }
                                                }                                            
                                            }
                                            '\d{2}-\d{1}-\d{4} \d{2}:\d{2}:\d{2}'
                                            {
                                                Switch ($logEntryItem.DateFormat)
                                                {
                                                    'DMY'
                                                    {
                                                        $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeString, 'dd-M-yyyy HH:mm:ss', $null)
                                                    }
                                                    'MDY'
                                                    {
                                                        $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeString, 'MM-d-yyyy HH:mm:ss', $null)
                                                    }
                                                }                                             
                                            }
                                            '\d{1}-\d{1}-\d{4} \d{2}:\d{2}:\d{2}'
                                            {
                                                Switch ($logEntryItem.DateFormat)
                                                {
                                                    'DMY'
                                                    {
                                                        $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeString, 'd-M-yyyy HH:mm:ss', $null)
                                                    }
                                                    'MDY'
                                                    {
                                                        $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeString, 'M-d-yyyy HH:mm:ss', $null)
                                                    }
                                                }                                             
                                            }
                                            '\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}'
                                            {
                                                Switch ($logEntryItem.DateFormat)
                                                {
                                                    'DMY'
                                                    {
                                                        $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeString, 'dd-MM-yyyy HH:mm:ss', $null)   
                                                    }
                                                    'MDY'
                                                    {
                                                        $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeString, 'MM-dd-yyyy HH:mm:ss', $null)
                                                    }
                                                }                                             
                                            }
                                        }
                                        # adding timezoneoffset $timeSplit[2] = "+ or -", $timeSplit[3] = minutes
                                        $tmpLogLineObject.TimeZoneOffset = "{0}{1}" -f $timeSplit[2], $timeSplit[3]
                                    }
                                }

                                if (-NOT ($tmpLogLineObject.LogDateTime))
                                {
                                    $tmpLogLineObject.Status = 'Error'
                                    $tmpLogLineObject.Description = 'DateTime could not be extracted from log! Is the correct DateFormat set?'
                                    Write-Verbose "$("{0,-35}-> DateTime could not be extracted from log: {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))"
                                }

                                # Check if the log line was written during the calculated "allowed" timeframe
                                If (($tmpLogLineObject.LogDateTime -ge $timeSpanObject.StartTime) -and ($tmpLogLineObject.LogDateTime -le $timeSpanObject.EndTime))
                                {
                                    $tmpLogLineObject.Status = 'OK'
                                    $foundLogEntryInTimeFrame = $true
                                    Write-Verbose "$("{0,-35}-> Success string found in given timeframe in line: {1} of log: {2}" -f  $($logEntryItem.Name), $($resultLine.LineNumber) ,$($logEntryItem.LogPath))"
                                }

                                # Add log entry to output object
                                [void]$logEntrySearchResultList.Add($tmpLogLineObject)                    

                            } # end foreach $parseResult

                            if (-NOT ($foundLogEntryInTimeFrame))
                            {
                                $tmpLogEntryObject.Status = 'Error'
                                $tmpLogEntryObject.Description = 'Success string not found in given timeframe'
                                [void]$logEntrySearchResultList.Add($tmpLogEntryObject)
                                Write-Verbose "$("{0,-35}-> Success string not found in given timeframe: {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))"
                            }

                        }
                        else 
                        {
                            # no result in log found
                            $tmpLogEntryObject.Status = 'Error'
                            $tmpLogEntryObject.Description = 'Success string not found in log!'
                            [void]$logEntrySearchResultList.Add($tmpLogEntryObject)
                            Write-Verbose "$("{0,-35}-> Success string not found in log! {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))"
                        } # END If ($parseResult)

                    }
                    else 
                    {
                        $tmpLogEntryObject.Status = "Error"
                        $tmpLogEntryObject.Description = "Could not calculate time"
                        [void]$logEntrySearchResultList.Add($tmpLogEntryObject)
                        Write-Verbose "$("{0,-35}-> No time calculated. Not able to test logfile: {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))"
                    } # END if ($timeSpanObject.StartTime)
                } # end (-NOT(Test-Path -Path $logEntryItem.LogPath))
            }
            else 
            {
                $tmpLogEntryObject.Status = "OK"
                $tmpLogEntryObject.Description = "Test only allowed to run on active node or specific system"
                [void]$logEntrySearchResultList.Add($tmpLogEntryObject)
                Write-Verbose "$("{0,-35}-> No time calculated. Not able to test logfile: {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))"                
            } # end Test-ConfigMgrActiveSiteSystemNode
            
        } # end if ($checkRequired -eq $false)
    }
} # end Testmode
#endregion

#region limit outputlist for some output modes
$resultObject = New-Object System.Collections.ArrayList
# Adding overall script output
if (-Not ($DontOutputScriptstate))
{
    [void]$logEntrySearchResultList.Add($tmpScriptStateObj)
}
# Group the results by log name to be able to look at the overall result
if($WriteLog){Write-CMTraceLog -Message "Grouping results to limit overall output to the latest entries" -Component ($MyInvocation.MyCommand)}
$logEntrySearchResultListGroups = $logEntrySearchResultList | Group-Object -Property Name
              
foreach ($groupItem in $logEntrySearchResultListGroups)
{
    # Do we have a good result?
    #$goodResults = $null
    #[array]$goodResults = $groupItem.group | Where-Object {$_.Status -ieq 'OK'}
    If($groupItem.group | Where-Object {$_.Status -ieq 'OK'})
    {
        [void]$resultObject.Add(($groupItem.group | Where-Object {$_.Status -ieq 'OK'}))        
    }
    else
    {
        [void]$resultObject.Add(($groupItem.group | Select-Object -Last 1)) # pick the last bad result to limit the output
                       
    }
}
#endregion


#region cache state
# In case we need to know wich logs are already in error state
# Not really required but can be helpful in case a logentry was deleted from the definition file 
if (-NOT ($NoCacheState))
{
    if($WriteLog){Write-CMTraceLog -Message "Script will cache alert states" -Component ($MyInvocation.MyCommand)}
    # we need to store one cache file per user running the script to avoid 
    # inconsistencies if the script is run by different accounts on the same machine
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($currentUser.Name -match '\\')
    {
        $userName = ($currentUser.Name -split '\\')[1]
    }
    else 
    {
        $userName = $currentUser.Name
    }

    # Get cache file
    $cacheFileName = '{0}\{1}_{2}_CACHE.json' -f $CachePath, ($MyInvocation.MyCommand), ($userName.ToLower())
															   
    if (Test-Path $cacheFileName)
    {
        # Found a file lets load it
        $i=0
        $cacheFileObject = Get-Content -Path $cacheFileName | ConvertFrom-Json
        foreach ($cacheItem in $cacheFileObject)
        {
            $i++
            if(-NOT($resultObject.Where({$_.Name -eq $cacheItem.Name})))
            {
                # Item not in the list of active errors anymore
                # Lets copy the item and change the state to OK
                $cacheItem.Status = 'Ok'
                $cacheItem.Description = ""
                [void]$resultObject.add($cacheItem) 
            }
        }
        if($WriteLog){Write-CMTraceLog -Message "Found $i alarm/s in cache file" -Component ($MyInvocation.MyCommand)}
    }

    # Lets output the current state for future runtimes 
    # BUT only error states
    $resultObject | Where-Object {$_.Status -ine 'Ok'} | ConvertTo-Json | Out-File -FilePath $cacheFileName -Encoding utf8 -Force
}
#endregion

#region Limit output to some properties
$resultObject = $resultObject | Select-Object Name, Status, Description, LogPath, LogDateTime, Interval, IntervalDay, Intervalweek
#endregion

#region Output
if($WriteLog){Write-CMTraceLog -Message "Output of data as: `"$OutputMode`"" -Component ($MyInvocation.MyCommand)}
switch ($OutputMode) 
{
    "GridView" 
    {  
        # Output full list
        $logEntrySearchResultList | Out-GridView -Title 'Full list of log parse results'
    }
    "MonAgentJSON" 
    {
        $resultObject | ConvertTo-CustomMonitoringObject -OutputType MonAgentObject | ConvertTo-Json -Depth 2
    }
    "MonAgentJSONCompressed"
    {
        $resultObject | ConvertTo-CustomMonitoringObject -OutputType MonAgentObject | ConvertTo-Json -Depth 2 -Compress
    }
    "HTMLMail"
    {      
        # Reference email script
        .$PSScriptRoot\Send-CustomMonitoringMail.ps1

        # Adding the scriptname to the subject
        $subjectTypeName = ($MyInvocation.MyCommand.Name) -replace '.ps1', ''

        $paramsplatting = @{
            MailMessageObject = $resultObject
            MailInfotext = '{0}<br>{1}' -f $systemName, $MailInfotext
        }  
        
        # If there are bad results, lets change the subject of the mail
        if($resultObject | Where-Object {$_.Status -ine 'OK'})
        {
            $MailSubject = 'FAILED: {0} state from: {1}' -f $subjectTypeName, $systemName
            $paramsplatting.add("MailSubject", $MailSubject)

            Send-CustomMonitoringMail @paramsplatting -HighPrio            
        }
        else 
        {
            if ($SendAllMails)
            {
                $MailSubject = 'OK: {0} state from: {1}' -f $subjectTypeName, $systemName
                $paramsplatting.add("MailSubject", $MailSubject)

                Send-CustomMonitoringMail @paramsplatting
            }
        }
    }
    "PSObject"
    {
        $resultObject   
    }
    "PRTGString"
    {
        $badResults = $resultObject | Where-Object {$_.Status -ine 'OK'}
        if ($badResults)
        {
            $resultString = '{0}:ConfigMgr log monitor failures' -f $badResults.count
            Write-Output $resultString
        }
        else
        {
            Write-Output "0:No ConfigMgr log monitor failures"
        }
    }
    "PRTGJSON"
    {
        $resultObject | ConvertTo-CustomMonitoringObject -OutputType PrtgObject -PrtgLookupFileName $PrtgLookupFileName | ConvertTo-Json -Depth 3
    }
    "JSON"
    {
        $resultObject | ConvertTo-Json -Depth 5
    }
}
if($WriteLog){Write-CMTraceLog -Message "End of script" -Component ($MyInvocation.MyCommand)}
#endregion 
