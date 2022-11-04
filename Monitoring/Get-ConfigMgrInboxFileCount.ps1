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
    [ValidateSet("GridView", "JSON", "JSONCompressed","HTMLMail","PSObject","PRTGString")]
    [String]$OutputMode = "PSObject",
    [Parameter(Mandatory=$false)]
    [String]$MailInfotext = 'Status about monitored inbox counts. This email is sent every day!'
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

# String "MaxValue=" just for readability. Will be removed later.
$referenceData = @{}                                                                                                                                                                                                           
$referenceData.add('hman.box>ForwardingMsg','MaxValue=500')                                                                                                                                                                                         
#$referenceData.add('schedule.box>outboxes>LAN ','MaxValue=500')                                                                                                                                                                                      
$referenceData.add('schedule.box>requests','MaxValue=500')                                                                                                                                                                                         
$referenceData.add('dataldr.box','MaxValue=500')                                                                                                                                                                                                      
$referenceData.add('sinv.box','MaxValue=500')                                                                                                                                                                                                         
$referenceData.add('despoolr.box>receive','MaxValue=500')                                                                                                                                                                                             
$referenceData.add('replmgr.box>incoming','MaxValue=500')                                                                                                                                                                                             
$referenceData.add('ddm.box','MaxValue=500')                                                                                                                                                                                                          
$referenceData.add('rcm.box','MaxValue=500')                                                                                                                                                                                                          
$referenceData.add('bgb.box','MaxValue=500')                                                                                                                                                                                                          
$referenceData.add('bgb.box>bad','MaxValue=500')                                                                                                                                                                                                      
#$referenceData.add('notictrl.box','MaxValue=500')                                                                                                                                                                                                     
#$referenceData.add('AIKbMgr.box>RETRY','MaxValue=500')                                                                                                                                                                                                
$referenceData.add('COLLEVAL.box','MaxValue=500')                                                                                                                                                                                                     
#$referenceData.add('amtproxymgr.box>disc.box','MaxValue=500')                                                                                                                                                                                         
#$referenceData.add('amtproxymgr.box>om.box','MaxValue=500')                                                                                                                                                                                           
#$referenceData.add('amtproxymgr.box>wol.box','MaxValue=500')                                                                                                                                                                                          
#$referenceData.add('amtproxymgr.box>prov.box','MaxValue=500')                                                                                                                                                                                         
$referenceData.add('COLLEVAL.box>RETRY','MaxValue=500')                                                                                                                                                                                               
#$referenceData.add('amtproxymgr.box>BAD','MaxValue=500')
#$referenceData.add('amtproxymgr.box>mtn.box','MaxValue=500')                                                                                                                                                                                         
$referenceData.add('offermgr.box>INCOMING','MaxValue=500')                                                                                                                                                                                           
#$referenceData.add('amtproxymgr.box','MaxValue=500')                                                                                                                                                                                                 
#$referenceData.add('aikbmgr.box','MaxValue=500')                                                                                                                                                                                                     
$referenceData.add('auth>ddm.box','MaxValue=500')                                                                                                                                                                                                    
$referenceData.add('auth>ddm.box>userddrsonly','MaxValue=500')                                                                                                                                                                                       
$referenceData.add('auth>ddm.box>regreq','MaxValue=500')                                                                                                                                                                                             
$referenceData.add('auth>sinv.box','MaxValue=500')                                                                                                                                                                                                   
$referenceData.add('auth>dataldr.box','MaxValue=500')                                                                                                                                                                                                
$referenceData.add('statmgr.box>statmsgs','MaxValue=500')                                                                                                                                                                                            
$referenceData.add('swmproc.box>usage','MaxValue=500')                                                                                                                                                                                               
$referenceData.add('distmgr.box>incoming','MaxValue=500')                                                                                                                                                                                            
$referenceData.add('auth>statesys.box>incoming','MaxValue=500')                                                                                                                                                                                      
$referenceData.add('polreq.box','MaxValue=500')                                                                                                                                                                                                      
$referenceData.add('auth>statesys.box>incoming>low','MaxValue=500')                                                                                                                                                                                  
$referenceData.add('auth>statesys.box>incoming>high','MaxValue=2000')                                                                                                                                                                                 
#$referenceData.add('OGprocess.box','MaxValue=500')                                                                                                                                                                                                   
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
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [ValidateSet("ConfigMgrLogState", "ConfigMgrComponentState", "ConfigMgrInboxFileCount","ConfigMgrCertificateState")]
        [string]$InputType,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false)]
        [string]$SystemName

    )

    Begin
    {
        $resultsObject = New-Object System.Collections.ArrayList
        $outObject = New-Object psobject | Select-Object InterfaceVersion, Results
        $outObject.InterfaceVersion = 1    
    }
    Process
    {
        switch ($InputType)
        {
            "ConfigMgrLogState" 
            {
                # Format for ConfigMgrLogState
                if($InputObject.State -ieq 'OK')
                {
                    $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
                    $tmpResultObject.Name = $SystemName
                    $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
                    $tmpResultObject.Status = 0
                    $tmpResultObject.ShortDescription = 'OK: `"{0}`"' -f $InputObject.Name
                    $tmpResultObject.Debug = ''
                    [void]$resultsObject.Add($tmpResultObject) 
                }
                else
                {
                    $shortDescription = 'FAILED: `"{0}`" Desc:{1} Log:{2}' -f $InputObject.Name, $InputObject.StateDescription, $InputObject.LogPath
                    if ($shortDescription.Length -gt 300)
                    {
                        # ShortDescription has a 300 character limit
                        $shortDescription = $shortDescription.Substring(0, 299)    
                    }
                    # Remove some chars like quotation marks
                    $shortDescription = $shortDescription -replace "\'", ""
                   
                    
                    # Status: 0=OK, 1=Warning, 2=Critical, 3=Unknown
                    $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
                    $tmpResultObject.Name = $systemName
                    $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
                    $tmpResultObject.Status = 2
                    $tmpResultObject.ShortDescription = $shortDescription
                    $tmpResultObject.Debug = ''
                    [void]$resultsObject.Add($tmpResultObject)
                }
            } 
            "ConfigMgrComponentState" 
            {
                # Format for ConfigMgrComponentState
                # Adding infos to short description field
                [string]$shortDescription = '{0}: {1}:' -f ($InputObject.Status), ($InputObject.CheckType)
                if ($InputObject.SiteCode)
                {
                    $shortDescription = '{0} {1}:' -f $shortDescription, ($InputObject.SiteCode)    
                }

                if ($InputObject.Name)
                {
                    $shortDescription = '{0} {1}' -f $shortDescription, ($InputObject.Name)    
                }

                if ($InputObject.Description)
                {
                    $shortDescription = '{0} {1}' -f $shortDescription, ($InputObject.Description)    
                }

                if ($shortDescription.Length -gt 300)
                {
                    # ShortDescription has a 300 character limit
                    $shortDescription = $shortDescription.Substring(0, 299)    
                }
                # Remove some chars like quotation marks
                $shortDescription = $shortDescription -replace "\'", ""

                switch ($InputObject.Status) 
                {
                    'Ok' {$outState = 0}
                    'Warning' {$outState = 1}
                    'Error' {$outState = 2}
                    Default {$outState = 3}
                }

                $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
                $tmpResultObject.Name = $InputObject.SystemName
                $tmpResultObject.Epoch = 0 # NOT USED at the moment. FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
                $tmpResultObject.Status = $outState
                $tmpResultObject.ShortDescription = $shortDescription
                $tmpResultObject.Debug = ''
                [void]$resultsObject.Add($tmpResultObject)
            } 
            "ConfigMgrInboxFileCount" 
            {
                $shortDescription = $InputObject.ShortDescription
                
                if ($shortDescription.Length -gt 300)
                {
                    # ShortDescription has a 300 character limit
                    $shortDescription = $shortDescription.Substring(0, 299)    
                }
                # Remove some chars like quotation marks
                $shortDescription = $shortDescription -replace "\'", ""                

                $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
                $tmpResultObject.Name = $InputObject.Name
                $tmpResultObject.Epoch = 0 # NOT USED at the moment. FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
                $tmpResultObject.Status = $InputObject.Status
                $tmpResultObject.ShortDescription = $shortDescription
                $tmpResultObject.Debug = $InputObject.Debug
                [void]$resultsObject.Add($tmpResultObject)
            } 
            "ConfigMgrCertificateState" 
            {
                $shortDescription = $InputObject.ShortDescription
                
                if ($shortDescription.Length -gt 300)
                {
                    # ShortDescription has a 300 character limit
                    $shortDescription = $shortDescription.Substring(0, 299)    
                }
                # Remove some chars like quotation marks
                $shortDescription = $shortDescription -replace "\'", ""                

                $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
                $tmpResultObject.Name = $InputObject.Name
                $tmpResultObject.Epoch = 0 # NOT USED at the moment. FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
                $tmpResultObject.Status = $InputObject.Status
                $tmpResultObject.ShortDescription = $shortDescription
                $tmpResultObject.Debug = $InputObject.Debug
                [void]$resultsObject.Add($tmpResultObject)                
            }
        }          
    }
    End
    {
        $outObject.Results = $resultsObject
        $outObject
    }

}
#endregion


#region main perf counter logic
$resultsObject = New-Object System.Collections.ArrayList

[array]$propertyList  = $null
$propertyList += 'Name' # Either Alert, EPAlert, CHAlert, Component or SiteSystem
$propertyList += 'Status'
$propertyList += 'ShortDescription'
$propertyList += 'Debug'

[bool]$badResult = $false

$inboxCounterList = Get-WmiObject Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox | Select-Object Name, FileCurrentCount -ErrorAction SilentlyContinue
if ($inboxCounterList)
{
    
    foreach ($inboxCounter in $inboxCounterList)
    {
        $counterValue = $null
        $counterValue = $referenceData[($inboxCounter.Name)]
        if ($counterValue)
        {
            # split "MaxValue=500"
            [array]$counterMaxValue = $counterValue -split '='

            if ($inboxCounter.FileCurrentCount -gt $counterMaxValue[1])
            {
                # Temp object for results
                # Status: 0=OK, 1=Warning, 2=Critical, 3=Unknown
                $tmpResultObject = New-Object psobject | Select-Object $propertyList
                $tmpResultObject.Name = $systemName
                $tmpResultObject.Status = 1
                $tmpResultObject.ShortDescription = '{0} files in {1} over limit of {2}' -f $inboxCounter.FileCurrentCount, $inboxCounter.Name, $counterMaxValue[1]
                $tmpResultObject.Debug = ''
                [void]$resultsObject.Add($tmpResultObject)
                $badResult = $true      
            }
        }
    }

    # validate script reference data by looking for counter in actual local counter list
    $referenceData.GetEnumerator() | ForEach-Object {
        
        if ($inboxCounterList.name -notcontains $_.Key)
        {
            # Temp object for results
            # Status: 0=OK, 1=Warning, 2=Critical, 3=Unknown
            $tmpResultObject = New-Object psobject | Select-Object $propertyList
            $tmpResultObject.Name = $systemName
            $tmpResultObject.Status = 1
            $tmpResultObject.ShortDescription = 'Counter: `"{0}`" not found on machine! ' -f $_.key
            $tmpResultObject.Debug = ''
            [void]$resultsObject.Add($tmpResultObject) 
            $badResult = $true 
        }
    }
}
else 
{
    $tmpResultObject = New-Object psobject | Select-Object $propertyList
    $tmpResultObject.Name = $systemName
    $tmpResultObject.Status = 2
    $tmpResultObject.ShortDescription = 'Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox could not be read'
    $tmpResultObject.Debug = ''
    [void]$resultsObject.Add($tmpResultObject) 
    $badResult = $true 
} 
#endregion


#region prepare output
if (-NOT ($badResult))
{
    $tmpResultObject = New-Object psobject | Select-Object $propertyList
    $tmpResultObject.Name = $systemName
    $tmpResultObject.Status = 0
    $tmpResultObject.ShortDescription = 'ok'
    $tmpResultObject.Debug = ''
    [void]$resultsObject.Add($tmpResultObject)
}
#endregion


#region Output
switch ($OutputMode) 
{
    "GridView" 
    {  
        $resultsObject | Out-GridView -Title 'List of states'
    }
    "JSON" 
    {
        $resultsObject | ConvertTo-CustomMonitoringObject -InputType ConfigMgrInboxFileCount -SystemName $systemName | ConvertTo-Json
    }
    "JSONCompressed"
    {
        $resultsObject | ConvertTo-CustomMonitoringObject -InputType ConfigMgrInboxFileCount -SystemName $systemName | ConvertTo-Json -Compress
    }
    "HTMLMail"
    {      
        # Reference email script
        .$PSScriptRoot\Send-CustomMonitoringMail.ps1

        # Adding the scriptname to the subject
        $subjectTypeName = ($MyInvocation.MyCommand.Name) -replace '.ps1', ''

        $paramsplatting = @{
            MailMessageObject = $resultsObject
            MailInfotext = '{0}<br>{1}' -f $systemName, $MailInfotext
        }  
        
        # If there are bad results, lets change the subject of the mail
        if ($resultsObject.Where({$_.Status -ne 0}))
        {
            $MailSubject = 'FAILED: {0} from: {1}' -f $subjectTypeName, $systemName
            $paramsplatting.add("MailSubject", $MailSubject)

            Send-CustomMonitoringMail @$paramsplatting -HighPrio            
        }
        else 
        {
            $MailSubject = 'OK: {0} from: {1}' -f $subjectTypeName, $systemName
            $paramsplatting.add("MailSubject", $MailSubject)

            Send-CustomMonitoringMail @$paramsplatting
        }
    }
    "PSObject"
    {
        $resultsObject
    }
    "PRTGString"
    {
        $badResults = $resultsObject.Where({$_.Status -ne 0})
        if ($badResults)
        {
            $resultString = '{0}:ConfigMgr file inbox limit reached' -f $badResults.count
            Write-Output $resultString
        }
        else
        {
            Write-Output "0:No ConfigMgr file inboxes are fine"
        }
    }
}
#endregion
