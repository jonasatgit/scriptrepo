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
#************************************************************************************************************

<#
.Synopsis
    Script to monitor ConfigMgr/MECM performance counter
    
.DESCRIPTION
    The script reads from an in script JSON file called $referenceDataJSON to validate a list of specific performance counter
    The inbox perf counter refresh intervall is 15 minutes. It therefore makes no sense to validate a counter more often. 
    Get the full list of available inbox perf counter via the following command:
    
    Get-WmiObject Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox | select Name, FileCurrentCount
    
    Source: https://github.com/jonasatgit/scriptrepo

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

.PARAMETER PrtgLookupFileName
    Name of a PRTG value lookup file. 

.PARAMETER WriteLog
    If true, the script will write a log. Helpful during testing. Default value is $false. 

.PARAMETER LogPath
    Path of the log file if parameter -WriteLog $true. The script will create the logfile next to the script if no path specified.

.PARAMETER InScriptConfigFile
    Default value is $true and means the config file is part of this script. Embedded in a here-String as $referenceDataJSON.
    This can be helpful is the script should not have an external config file.
    If set to $false the script will look for a file called Get-ConfigMgrInboxFileCount.ps1.json either next to this script or in the 
    path specified vie parameter -ConfigFilePath

.PARAMETER ConfigFilePath
    Path to the configfile called Get-ConfigMgrInboxFileCount.ps1.json. JSON can be created using the content of the in script variable $referenceDataJSON

.PARAMETER OutputTestData
    Number of dummy test data objects. Helpful to test a monitoring solution without any actual ConfigMgr errors.

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1 -OutputMode GridView

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1 -OutputMode GridView -OutputTestData 20

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1 -OutputMode LeutekJSON

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1 -OutputMode HTMLMail

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1 -WriteLog $true

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1 -WriteLog $true -LogPath "C:\Temp"

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
    [Parameter(Mandatory=$false)]
    [ValidateSet("GridView", "LeutekJSON", "LeutekJSONCompressed","HTMLMail","PSObject","PrtgString","PrtgJSON")]
    [String]$OutputMode = "PSObject",
    [Parameter(Mandatory=$false)]
    [String]$MailInfotext = 'Status about monitored inbox counts. This email is sent every day!',
    [Parameter(Mandatory=$false)]
    [bool]$CacheState = $true,
    [Parameter(Mandatory=$false)]
    [string]$CachePath,
    [Parameter(Mandatory=$false)]
    [string]$PrtgLookupFileName,  
    [Parameter(Mandatory=$false)]
    [bool]$InScriptConfigFile = $true,  
    [Parameter(Mandatory=$false)]
    [string]$ConfigFilePath, 
    [Parameter(Mandatory=$false)]
    [bool]$WriteLog = $false,
    [Parameter(Mandatory=$false)]
    [string]$LogPath,
    [Parameter(Mandatory=$false)]
    [ValidateRange(1,60)]
    [int]$OutputTestData=0
)

#region admin rights
#Ensure that the Script is running with elevated permissions
if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Warning 'The script needs admin rights to run. Start PowerShell with administrative rights and run the script again'
    return 
}
#endregion


#region reference data
# Get the full list of available inbox perf counter via the following command:
# Get-WmiObject Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox | select Name, FileCurrentCount
# Using here string and embedded JSON to not have an external dependency
# Could also be moved outside the script and stored next to it as JSON via $InScriptConfigFile=$false
$referenceDataJSON = @'
{
    "SMSInboxPerfData": [
            {
                "CounterName": "hman.box>ForwardingMsg",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "schedule.box>requests",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "dataldr.box",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "sinv.box",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "despoolr.box>receive",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "replmgr.box>incoming",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "ddm.box",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "rcm.box",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "bgb.box",
                "MaxValue": 500,
                "SkipCheck": false
            },      
            {
                "CounterName": "bgb.box>bad",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "COLLEVAL.box",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "COLLEVAL.box>RETRY",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "offermgr.box>INCOMING",
                "MaxValue": 500,
                "SkipCheck": false
            },       
            {
                "CounterName": "auth>ddm.box",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "auth>ddm.box>userddrsonly",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "auth>ddm.box>regreq",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "auth>sinv.box",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "auth>dataldr.box",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "statmgr.box>statmsgs",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "swmproc.box>usage",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "distmgr.box>incoming",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "auth>statesys.box>incoming",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "polreq.box",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "auth>statesys.box>incoming>low",
                "MaxValue": 500,
                "SkipCheck": false
            },
            {
                "CounterName": "auth>statesys.box>incoming>high",
                "MaxValue": 2000,
                "SkipCheck": false
            },   
            {
                "CounterName": "OGprocess.box",
                "MaxValue": 500,
                "SkipCheck": true
            },   
            {
                "CounterName": "businessappprocess.box",
                "MaxValue": 500,
                "SkipCheck": true
            },   
            {
                "CounterName": "objmgr.box",
                "MaxValue": 500,
                "SkipCheck": true
            },   
            {
                "CounterName": "notictrl.box",
                "MaxValue": 500,
                "SkipCheck": true
            },             
            {
                "CounterName": "aikbmgr.box",
                "MaxValue": 500,
                "SkipCheck": true
            },
            {
                "CounterName": "AIKbMgr.box>RETRY",
                "MaxValue": 500,
                "SkipCheck": true
            },
            {
                "CounterName": "adsrv.box",
                "MaxValue": 500,
                "SkipCheck": true
            }, 
            {
                "CounterName": "amtproxymgr.box",
                "MaxValue": 500,
                "SkipCheck": true
            }, 
            {
                "CounterName": "schedule.box>outboxes>LAN",
                "MaxValue": 500,
                "SkipCheck": true
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
        [ValidateSet("LeutekObject", "PrtgObject")]
        [string]$OutputType,
        [Parameter(Mandatory=$false)]
        [string]$PrtgLookupFileName        
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
                <#
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
                        [string]$shortDescription = $InputObject.PossibleActions -replace "\'", "" -replace '>','_' # Remove some chars like quotation marks or >
                    }
                }
                #>

                # Needs to be name at the moment
                $shortDescription = $InputObject.Name -replace "\'", "" -replace '>','_'

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

#region main perf counter logic
$resultObject = New-Object System.Collections.ArrayList
[array]$propertyList  = $null
$propertyList += 'CheckType' # Either Alert, EPAlert, CHAlert, Component or SiteSystem
$propertyList += 'Name' # Has to be a unique check name. Something like the system fqdn and the check itself
$propertyList += 'SystemName'
$propertyList += 'SiteCode'
$propertyList += 'Status'
$propertyList += 'Description'
$propertyList += 'PossibleActions'

if (-NOT($CachePath))
{
    $CachePath = $PSScriptRoot
}
#endregion

#region Generic Script state object
# We always need a generic script state object. Especially if we have no errors
$tmpScriptStateObj = New-Object psobject | Select-Object $propertyList
$tmpScriptStateObj.Name = 'Script:{0}' -f $systemName 
$tmpScriptStateObj.SystemName = $systemName
$tmpScriptStateObj.CheckType = 'Script'
$tmpScriptStateObj.Status = 'Ok'
$tmpScriptStateObj.Description = "Overall state of script"
#endregion


#region get config data
if ($InScriptConfigFile)
{
    $referenceDataObject = $referenceDataJSON | ConvertFrom-Json
}
else 
{
    if (-NOT($ConfigFilePath))
    {
        $ConfigFilePath = $PSScriptRoot
    }
    
    $configFileFullName = '{0}\{1}.json' -f $ConfigFilePath, ($MyInvocation.MyCommand)
    if (Test-Path $configFileFullName)
    {
        $referenceDataObject = Get-Content -Path $configFileFullName | ConvertFrom-Json
    }
    else 
    {
        $tmpScriptStateObj.Status = 'Error'
        $tmpScriptStateObj.Description = ('Path not found: {}' -f $configFileFullName)
    }
}
#endregion


#region
if ($OutputTestData)
{
    if($WriteLog){Write-CMTraceLog -Message "Will create $OutputTestData test alarms" -Component ($MyInvocation.MyCommand)}
    # create dummy entries using the $referenceDataObject
    $inboxCounterList = $referenceDataObject.SMSInboxPerfData | Where-Object {$_.SkipCheck -eq $false}  | ForEach-Object {
        $tmpObj = New-Object psobject | Select-Object Name, FileCurrentCount
        $tmpObj.Name = $_.CounterName
        $tmpObj.FileCurrentCount = (Get-Random -Minimum ($_.MaxValue+10) -Maximum 5000)
        $tmpObj
    }
    # More consistent dummy data generation not using get-random
    $inboxCounterList = $inboxCounterList | Select-Object -First $OutputTestData
}
else
{
    if($WriteLog){Write-CMTraceLog -Message "Getting data from: Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox" -Component ($MyInvocation.MyCommand)}
    [array]$inboxCounterList = Get-WmiObject Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox | Select-Object Name, FileCurrentCount -ErrorAction SilentlyContinue
} 
        
if ($inboxCounterList)
{
    if($WriteLog){Write-CMTraceLog -Message "Found $($inboxCounterList.Count) items to work with" -Component ($MyInvocation.MyCommand)}
    foreach ($inboxCounter in $inboxCounterList)
    {
        # Lets see if we have a definition for the counter
        $referenceCounterObject = $referenceDataObject.SMSInboxPerfData.Where({$_.CounterName -eq $inboxCounter.Name})
        if ($referenceCounterObject)
        {
            if ($referenceCounterObject.SkipCheck -eq $false)
            {
                if ($inboxCounter.FileCurrentCount -gt $referenceCounterObject.MaxValue)
                {
                    $tmpObj = New-Object psobject | Select-Object $propertyList
                    $tmpObj.CheckType = 'Inbox'
                    $tmpObj.Name = '{0}:{1}:{2}' -f $tmpObj.CheckType, $systemName, $inboxCounter.Name
                    $tmpObj.SystemName = $systemName
                    $tmpObj.Status = 'Warning'
                    $tmpObj.SiteCode = ""
                    $tmpObj.Description = '{0} files in {1} over limit of {2}' -f $inboxCounter.FileCurrentCount, $inboxCounter.Name, $referenceCounterObject.MaxValue
                    $tmpObj.PossibleActions = 'Validate inbox in ConfigMgrInstallDirectory-Inboxes and corresponding log files in ConfigMgrInstallDirectory-Logs'
                    [void]$resultObject.Add($tmpObj) 
                }
            }
            else 
            {
                if($WriteLog){Write-CMTraceLog -Message "Counter set to be skipped: $($inboxCounter.Name)" -Component ($MyInvocation.MyCommand)}
            }
        }
        else 
        {
            $tmpObj = New-Object psobject | Select-Object $propertyList
            $tmpObj.CheckType = 'Inbox'
            $tmpObj.Name = '{0}:{1}:{2}' -f $tmpObj.CheckType, $systemName, $inboxCounter.Name
            $tmpObj.SystemName = $systemName
            $tmpObj.Status = 'Warning'
            $tmpObj.SiteCode = ""
            $tmpObj.Description = 'Local counter {0} not found in definition' -f $inboxCounter.Name
            $tmpObj.PossibleActions = 'Validate inbox in ConfigMgrInstallDirectory-Inboxes and corresponding log files in ConfigMgrInstallDirectory-Logs'
            [void]$resultObject.Add($tmpObj) 
        }
    }
}
else 
{
    if($WriteLog){Write-CMTraceLog -Message 'Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox could not be read' -Component -Severity Warning ($MyInvocation.MyCommand)}
    $tmpScriptStateObj.Status = 'Warning'
    $tmpScriptStateObj.Description = 'Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox could not be read'
    $tmpScriptStateObj.PossibleActions = 'Check locally or debug script'
} 

#endregion


# Adding overall script state to list
[void]$resultObject.Add($tmpScriptStateObj)
#endregion

#region cache state
# In case we need to know witch components are already in error state
if ($CacheState)
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


#region Output
if($WriteLog){Write-CMTraceLog -Message "Created $($resultObject.Count) alert items" -Component ($MyInvocation.MyCommand)}
switch ($OutputMode) 
{
    "GridView" 
    {  
        $resultObject | Out-GridView -Title 'List of states'
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
        if ($resultObject.Where({$_.Status -ine 'OK'}))
        {
            $MailSubject = 'FAILED: {0} from: {1}' -f $subjectTypeName, $systemName
            $paramsplatting.add("MailSubject", $MailSubject)

            Send-CustomMonitoringMail @paramsplatting -HighPrio            
        }
        else 
        {
            $MailSubject = 'OK: {0} from: {1}' -f $subjectTypeName, $systemName
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
        $badResults = $resultObject.Where({$_.Status -ine 'OK'})
        if ($badResults)
        {
            $resultString = '{0}:Number of ConfigMgr file inbox limits reached' -f $badResults.count
            Write-Output $resultString
        }
        else
        {
            Write-Output "0:ConfigMgr file inboxes are fine"
        }
    }
    "PRTGJSON"
    {
        $resultObject | ConvertTo-CustomMonitoringObject -OutputType PrtgObject -PrtgLookupFileName $PrtgLookupFileName | ConvertTo-Json -Depth 3
    }
}
if($WriteLog){Write-CMTraceLog -Message "End of script" -Component ($MyInvocation.MyCommand)}
#endregion
