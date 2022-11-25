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
    Get-ConfigMgrLogState is designed to monitor logfiles and output the result in different ways

.DESCRIPTION
    Get-ConfigMgrLogState is designed to monitor logfiles and output the result in different ways. (See parameter OutputMode for more details)
    The script will not use an external config file to avoid any dependencies. Instead the script uses an arraylist of logentries to be tested.
    There is one dependency though when HTMLMail is used as the outputmode. "Send-CustomMonitoringMail.ps1" is required in that case. 
    The script needs to run at least as often as the lowest interval configured in the section described next.
    For each logfile to be monitored, copy the below lines and paste them below the line: "########## Paste new entries below ##########"
    Change the values as required for the log test.

    ########## Copy here ##########
    $logEntry = @{
        Name = "Configmgr Backup Monitor Daily Test"
        Description = "Just a test" # A short description of the logfile and why a test is needed
        LogPath = "C:\Users\sccmops\Downloads\smsbkup.log" # Path and name of a logfile to be parsed
        SuccessString = "Backup completed" # String to look for in case of success. The script will try to find the string in the given timeframe
        Interval = "Daily" # How often we expect the success string to be written to the logfile. Valid strings: "Hourly", "Daily", "Weekly" or "Monthly
        IntervalDay = "" # A specific day we expect the success string to be written. Only valid if "Interval" is set to Weekly or Monthly. Valid strings: "Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday" 
        IntervalWeek = 0 # A specific week we expect the success string to be written. Only valid if "Interval" is set to Monthly
        IntervalTime = "02:00" # Time in 24h format hh:mm. The time we expect a log entry to appear
        TimespanMinutes = 60 # Minutes added to the Intervaltime before and after. This is the timeframe we will look for the SuccessString in the log
        IgnorePreviousEntries = $true or $false. If set to true and if we are probing before the time we would expect a log entry, we should not look one day, week or month back and test the last result instead
        RunOnActiveNodeOnly = $true or $false. If set to true the test will only run on an active ConfigMgr site server.
        RunOnSystemList = Comma seperated list of system fqdns the check should be performed. If empty, the test will be performed on any system
    }
    $logEntryObj = New-Object PSCustomObject -Property $logEntry
    [void]$logEntryList.add($logEntryObj)
    ########## Copy here ##########

.EXAMPLE
    .\Get-ConfigMgrLogState

.PARAMETER OutputMode
    Parameter to be able to output the results in a GridView, special JSON format, special JSONCompressed format,
    a simple PowerShell objekt PSObject or via HTMLMail.
    The HTMLMail mode requires the script "Send-CustomMonitoringMail.ps1" to be in the same folder.

.PARAMETER CacheState
    Boolean parameter. If set to $true, the script will output its current state to a JSON file.
    The file will be stored next to the script or a path set via parameter "CachePath"
    The filename will look like this: CACHE_[name-of-script.ps1].json

.PARAMETER CachePath
    Path to store the JSON cache file. Default value is root path of script. 

.PARAMETER ProbeTime 
    Datetime parameter to be able to set a specific datetime to simulate a script run in the past or future. Example value: (Get-Date('2022-06-14 01:00'))
    Can help to simulate a specific run date and run time for the script. If not specific the current local datetime will be used

.PARAMETER PrtgLookupFileName
    Name of a PRTG value lookup file. 

.PARAMETER OutputTestData
    Number of dummy test data objects. Helpful to test a monitoring solution without any actual ConfigMgr errors.

.EXAMPLE
    .\Get-ConfigMgrLogState

.EXAMPLE
    .\Get-ConfigMgrLogState -OutputMode 'GridView'

.EXAMPLE
    .\Get-ConfigMgrLogState -ProbeTime (Get-Date('2022-06-14 01:00'))

.INPUTS
   None

.OUTPUTS
   GridView, JSON, compressed JSON or HTML mail

.LINK
    https://github.com/jonasatgit/scriptrepo

#>
[CmdletBinding()]
param
(
    [parameter(Mandatory=$false,ValueFromPipeline=$false)]
    [datetime]$ProbeTime = (get-date), # Test example: (Get-Date('2022-06-14 01:00'))
    [Parameter(Mandatory=$false)]
    [ValidateSet("GridView", "LeutekJSON", "LeutekJSONCompressed","HTMLMail","PSObject","PrtgString","PrtgJSON")]
    [String]$OutputMode = "PSObject",
    [Parameter(Mandatory=$false)]
    [String]$MailInfotext = 'Status about monitored logfiles. This email is sent every day!'
)

$VerbosePreference = "silentlyContinue"

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
                "IgnorePreviousEntries": false,
                "RunOnActiveNodeOnly": false,
                "RunOnSystemList": ""
            }
    ]
}
'@
<#
$logEntryListJSON = @'
{
    "LogEntries": [
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
                "IgnorePreviousEntries": false,
                "RunOnActiveNodeOnly": false,
                "RunOnSystemList": ""
            }
            ]
        }
'@
#>
$logEntryListJSONObject = $logEntryListJSON | ConvertFrom-Json
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
        [ValidateSet("LeutekObject", "PrtgObject")]
        [string]$OutputType
    )

    Begin
    {
        $resultsObject = New-Object System.Collections.ArrayList
        switch ($OutputType)
        {
            'LeutekObject'
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
            'LeutekObject' 
            {  
                # Format for ConfigMgrComponentState
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
                    'Log'
                    {
                        Write-Verbose $InputObject.StateDescription
                        [string]$shortDescription = $InputObject.StateDescription -replace "\'", "" -replace '>','_' # Remove some chars like quotation marks or >    
                    }
                    Default 
                    {
                        [string]$shortDescription = $InputObject.PossibleActions -replace "\'", "" -replace '>','_' # Remove some chars like quotation marks or >
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
                $tmpResultObject = New-Object psobject | Select-Object Channel, Value, Warning
                $tmpResultObject.Channel = $InputObject.Name -replace "\'", "" -replace '>','_'
                $tmpResultObject.Value = 0
                if ($InputObject.Status -ieq 'Ok')
                {
                    $tmpResultObject.Warning = 0
                }
                else
                {
                    $tmpResultObject.Warning = 1
                }                    
                [void]$resultsObject.Add($tmpResultObject)  
            }
        }                  
    }
    End
    {
        switch ($OutputType)
        {
            'LeutekObject'
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


#region main log logic
# temp results object and corresponding property list
[array]$propertyList = 'Name'
$propertyList += 'CheckType'
$propertyList += 'State'
$propertyList += 'StateDescription'
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
$propertyList += 'Description'
$propertyList += 'NodeType'
$propertyList += 'RunOnSystemList'

$logEntrySearchResultList = New-Object System.Collections.ArrayList

foreach ($logEntryItem in $logEntryListJSONObject.LogEntries)
{
    Write-Verbose "$("{0,-35}-> Working on: {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))"
    $timeSpanObject = $null
    $timeSpanObject = New-Object PSCustomObject | Select-Object StartTime, EndTime
    # will be set to false if we are running the script before the calculated datetime and if IgnorePreviousEntries is set to $true
    # IgnorePreviousEntries = $true means, if we are before the calculated datetime, we should not look one day, week or month back and test the last result instead
    # We simply ignore the log for now in that case
    $checkRequired = $true 
    # Tmp object to track log parse status
    $tmpLogEntryObject = New-Object PSCustomObject | Select-Object $propertyList
    $tmpLogEntryObject.Name = $logEntryItem.Name
    $tmpLogEntryObject.CheckType = 'Log'
    $tmpLogEntryObject.State = "" # Set to nothing to force string format
    $tmpLogEntryObject.StateDescription = "" # Set to nothing to force string format
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
    $tmpLogEntryObject.Description = $logEntryItem.Description
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
        $tmpLogEntryObject.State = "OK"
        $tmpLogEntryObject.StateDescription = "Probe time before log time. Nothing to do"
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
                $tmpLogEntryObject.State = "Error"
                $tmpLogEntryObject.StateDescription = "Path not found"
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
                            $tmpLogLineObject.Name = $logEntryItem.Name
                            $tmpLogLineObject.CheckType = 'Log'
                            $tmpLogLineObject.State = "" # Set to nothing to force string format
                            $tmpLogLineObject.StateDescription = "" # Set to nothing to force string format
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
                            $tmpLogLineObject.Description = $logEntryItem.Description
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
                                $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeSplit[0], 'MM-dd-yyyy HH:mm:ss', $null)
                                
                                # adding timezoneoffset $datetimeSplit[1] = "+ or -", $datetimeSplit[2] = minutes
                                $tmpLogLineObject.TimeZoneOffset = "{0}{1}" -f $datetimeSplit[1], $datetimeSplit[2]
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
                                    if ($datetimeString -match '\d{1}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}')
                                    {
                                        $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeString, 'M-dd-yyyy HH:mm:ss', $null)
                                    }
                                    elseif ($datetimeString -match '\d{2}-\d{1}-\d{4} \d{2}:\d{2}:\d{2}') 
                                    {
                                        $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeString, 'MM-d-yyyy HH:mm:ss', $null)
                                    }
                                    elseif ($datetimeString -match '\d{1}-\d{1}-\d{4} \d{2}:\d{2}:\d{2}') 
                                    {
                                        $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeString, 'M-d-yyyy HH:mm:ss', $null)
                                    }
                                    elseif ($datetimeString -match '\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}') 
                                    {
                                        $tmpLogLineObject.LogDateTime = [Datetime]::ParseExact($datetimeString, 'MM-dd-yyyy HH:mm:ss', $null)
                                    }
                                    # adding timezoneoffset $timeSplit[1] = "+ or -", $timeSplit[2] = minutes
                                    $tmpLogLineObject.TimeZoneOffset = "{0}{1}" -f $timeSplit[2], $timeSplit[3]
                                }
                            }

                            if (-NOT ($tmpLogLineObject.LogDateTime))
                            {
                                $tmpLogLineObject.State = 'Error'
                                $tmpLogLineObject.StateDescription = 'DateTime could not be extracted from log!'
                                Write-Verbose "$("{0,-35}-> DateTime could not be extracted from log: {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))"
                            }

                            # Check if the log line was written during the calculated "allowed" timeframe
                            If (($tmpLogLineObject.LogDateTime -ge $timeSpanObject.StartTime) -and ($tmpLogLineObject.LogDateTime -le $timeSpanObject.EndTime))
                            {
                                $tmpLogLineObject.State = 'OK'
                                $foundLogEntryInTimeFrame = $true
                                Write-Verbose "$("{0,-35}-> Success string found in given timeframe in line: {1} of log: {2}" -f  $($logEntryItem.Name), $($resultLine.LineNumber) ,$($logEntryItem.LogPath))"
                            }

                            # Add log entry to output object
                            [void]$logEntrySearchResultList.Add($tmpLogLineObject)                    

                        } # end foreach $parseResult

                        if (-NOT ($foundLogEntryInTimeFrame))
                        {
                            $tmpLogEntryObject.State = 'Error'
                            $tmpLogEntryObject.StateDescription = 'Success string not found in given timeframe'
                            [void]$logEntrySearchResultList.Add($tmpLogEntryObject)
                            Write-Verbose "$("{0,-35}-> Success string not found in given timeframe: {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))"
                        }

                    }
                    else 
                    {
                        # no result in log found
                        $tmpLogEntryObject.State = 'Error'
                        $tmpLogEntryObject.StateDescription = 'Success string not found in log!'
                        [void]$logEntrySearchResultList.Add($tmpLogEntryObject)
                        Write-Verbose "$("{0,-35}-> Success string not found in log! {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))"
                    } # END If ($parseResult)

                }
                else 
                {
                    $tmpLogEntryObject.State = "Error"
                    $tmpLogEntryObject.StateDescription = "Could not calculate time"
                    [void]$logEntrySearchResultList.Add($tmpLogEntryObject)
                    Write-Verbose "$("{0,-35}-> No time calculated. Not able to test logfile: {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))"
                } # END if ($timeSpanObject.StartTime)
            } # end (-NOT(Test-Path -Path $logEntryItem.LogPath))
        }
        else 
        {
            $tmpLogEntryObject.State = "OK"
            $tmpLogEntryObject.StateDescription = "Test only allowed to run on active node or specific system"
            [void]$logEntrySearchResultList.Add($tmpLogEntryObject)
            Write-Verbose "$("{0,-35}-> No time calculated. Not able to test logfile: {1}" -f  $($logEntryItem.Name), $($logEntryItem.LogPath))"                
        } # end Test-ConfigMgrActiveSiteSystemNode
        
    } # end if ($checkRequired -eq $false)
}
#endregion


#region limit outputlist for some output modes
$resultObject = New-Object System.Collections.ArrayList
# Group the results by log name to be able to look at the overall result
$logEntrySearchResultListGroups = $logEntrySearchResultList | Group-Object -Property Name
              
foreach ($groupItem in $logEntrySearchResultListGroups)
{
    # Do we have a good result?
    #$goodResults = $null
    #[array]$goodResults = $groupItem.group | Where-Object {$_.State -eq 'OK'}
    If($groupItem.group | Where-Object {$_.State -eq 'OK'})
    {
        [void]$resultObject.Add(($groupItem.group | Where-Object {$_.State -eq 'OK'}))        
    }
    else
    {
        [void]$resultObject.Add(($groupItem.group | Select-Object -Last 1)) # pick the last bad result to limit the output
                       
    }
}
# Limit output to some properties
$resultObject = $resultObject | Select-Object Name, State, StateDescription, LogPath, LogDateTime, Interval, IntervalDay, Intervalweek
#endregion


#region Output
switch ($OutputMode) 
{
    "GridView" 
    {  
        # Output full list
        $logEntrySearchResultList | Out-GridView -Title 'Full list of log parse results'
    }
    "LeutekJSON" 
    {
        $resultObject | ConvertTo-CustomMonitoringObject -OutputType LeutekObject | ConvertTo-Json -Depth 2
    }
    "LeutekJSONCompressed"
    {
        $resultObject | ConvertTo-CustomMonitoringObject -OutputType LeutekObject | ConvertTo-Json -Depth 2 -Compress
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
        if($resultObject.Where({$_.State -ine 'OK'}))
        {
            $MailSubject = 'FAILED: {0} state from: {1}' -f $subjectTypeName, $systemName
            $paramsplatting.add("MailSubject", $MailSubject)

            Send-CustomMonitoringMail @paramsplatting -HighPrio            
        }
        else 
        {
            $MailSubject = 'OK: {0} state from: {1}' -f $subjectTypeName, $systemName
            $paramsplatting.add("MailSubject", $MailSubject)

            Send-CustomMonitoringMail @paramsplatting
        }
    }
    "PSObject"
    {
        $resultObject   
    }
    "PRTGString"
    {
        $badResults = $resultObject.Where({$_.State -ine 'OK'})
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
        $resultObject | ConvertTo-CustomMonitoringObject -OutputType PrtgObject | ConvertTo-Json -Depth 3
    }
}
#endregion 
