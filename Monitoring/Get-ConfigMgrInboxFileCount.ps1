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
    The script reads from an in script hashtable called "$referenceData" to validate a list of specific performance counter
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

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1 -OutputMode GridView

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1 -OutputMode JSON

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1 -OutputMode JSONCompressed

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1 -OutputMode HTMLMail

.INPUTS
   None

.OUTPUTS
   Either GridView, JSON formatted or JSON compressed.

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
    [bool]$CacheState = $false,
    [Parameter(Mandatory=$false)]
    [string]$CachePath,
    [Parameter(Mandatory=$false)]
    [ValidateRange(0,60)]
    [int]$OutputTestData=1
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
# Usinh here string and embedded JSON to not have an external dependency
# Could also easily be moved outside the script and stored next to it as JSON
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
                "CounterName": "schedule.box>outboxes>LAN",
                "MaxValue": 500,
                "SkipCheck": true
            } 
    ]
}
'@

$referenceDataObject = $referenceDataJSON | ConvertFrom-Json
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
if ($OutputTestData)
{
    # create dummy entries using the $referenceDataObject
    $inboxCounterList = $referenceDataObject.SMSInboxPerfData | ForEach-Object {
        $tmpObj = New-Object psobject | Select-Object Name, FileCurrentCount
        $tmpObj.Name = $_.CounterName
        $tmpObj.FileCurrentCount = (Get-Random -Minimum ($_.MaxValue+10) -Maximum 5000)
        $tmpObj
    }

    $inboxCounterList = $inboxCounterList | Get-Random -Count $OutputTestData
}
else
{
    $inboxCounterList = Get-WmiObject Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox | Select-Object Name, FileCurrentCount -ErrorAction SilentlyContinue
} 
        
if ($inboxCounterList)
{
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
                #Object is set to be skipped
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
    $tmpObj = New-Object psobject | Select-Object $propertyList
    $tmpObj.CheckType = 'Inbox'
    $tmpObj.Name = '{0}:{1}:{2}' -f $tmpObj.CheckType, $systemName, 'Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox'
    $tmpObj.SystemName = $systemName
    $tmpObj.Status = 'Warning'
    $tmpObj.SiteCode = ""
    $tmpObj.Description = 'Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox could not be read'
    $tmpObj.PossibleActions = 'Check locally or debug script'
    [void]$resultObject.Add($tmpObj) 
} 

#endregion


# Adding overall script state to list
[void]$resultObject.Add($tmpScriptStateObj)
#endregion

#region cache state
# In case we need to know witch components are already in error state
if ($CacheState)
{
    # Get cache file
    $cacheFileName = '{0}\CACHE_{1}.json' -f $CachePath, ($MyInvocation.MyCommand)
    if (Test-Path $cacheFileName)
    {
        # Found a file lets load it
        $cacheFileObject = Get-Content -Path $cacheFileName | ConvertFrom-Json

        foreach ($cacheItem in $cacheFileObject)
        {
            if(-NOT($resultObject.Where({$_.Name -eq $cacheItem.Name})))
            {
                # Item not in the list of active errors anymore
                # Lets copy the item and change the state to OK
                $cacheItem.Status = 'Ok'
                $cacheItem.Description = ""
                [void]$resultObject.add($cacheItem)
            }
        }
    }

    # Lets output the current state for future runtimes 
    # BUT only error states
    $resultObject | Where-Object {$_.Status -ine 'Ok'} | ConvertTo-Json | Out-File -FilePath $cacheFileName -Encoding utf8 -Force
    
}
#endregion


#region Output
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
        $resultObject | ConvertTo-CustomMonitoringObject -OutputType PrtgObject | ConvertTo-Json -Depth 3
    }
}
#endregion
