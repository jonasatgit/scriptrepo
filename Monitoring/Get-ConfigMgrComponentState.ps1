<#
.Synopsis
    Script to monitor ConfigMgr component, site system and alert states
    
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
    #************************************************************************************************************

    Script to monitor ConfigMgr component, site system and alert states based on the following WMI classes:
    SMS_ComponentSummarizer
    SMS_SiteSystemSummarizer
    SMS_Alert
    SMS_EPAlert
    SMS_CHAlert    
    
    The script will always return zero errors when running on a passive ConfigMgr Site Server.

    Source: https://github.com/jonasatgit/scriptrepo

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

.PARAMETER PrtgLookupFileName
    Name of a PRTG value lookup file. 

.PARAMETER WriteLog
    Switch parameter If set, the script will write a log. Helpful during testing.  

.PARAMETER LogPath
    Path of the log file if parameter -WriteLog $true. The script will create the logfile next to the script if no path specified.

.PARAMETER DontOutputScriptstate
    If set the script will NOT output its overall state as an extra object. Otherwise the script will output its state. 

.PARAMETER TestMode
    If set, the script will use the value of parameter -OutputTestData to output dummy data objects

.PARAMETER OutputTestData
    Number of dummy test data objects. Helpful to test a monitoring solution without any actual ConfigMgr errors.

.PARAMETER ExcludeComponentsList
    List of ConfigMgr components to exclude from monitoring. Should be the component name and only used temporary.

.PARAMETER ExcludeSiteSystemsList
    List of ConfigMgr site systems to exclude from monitoring. Should be the FQDN of the site system. Use only temporary in case a system is down for maintenance.

.PARAMETER $ExcludeAlertIDsList
    List of ConfigMgr alerts to exclude from monitoring. Should be the "Alert ID" which can be shown in ConfigMgr console under "Active Alerts".
    Use only temporary in case an alert is known and not relevant for a time being.

.PARAMETER IgnoreGeneralAlerts
    Switch parameter. If set the script will ignore all general ConfigMgr alerts.

.PARAMETER IgnoreEPAlerts
    Switch parameter. If set the script will ignore all Endpoint Protection related ConfigMgr alerts.

.PARAMETER IgnoreCHAlerts
    Switch parameter. If set the script will ignore all Client Health related ConfigMgr alerts.

.EXAMPLE
    Get-ConfigMgrComponentState.ps1

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -OutputMode GridView

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -OutputMode GridView -OutputTestData 20

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -OutputMode MonAgentJSON

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -OutputMode HTMLMail

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -WriteLog

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -WriteLog -LogPath "C:\Temp"

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -ExcludeComponentsList 'SMS_LAN_SENDER','SMS_WSUS_CONTROL_MANAGER'

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -ExcludeSiteSystemsList 'CM00.contoso.local', 'CM01.contoso.local'

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -$ExcludeAlertIDsList 10, 20

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
    [ValidateSet("JSON","GridView", "MonAgentJSON", "MonAgentJSONCompressed","HTMLMail","PSObject","PrtgString","PrtgJSON")]
    [String]$OutputMode = "PSObject",
    [Parameter(Mandatory=$false)]
    [String]$MailInfotext = 'Status about monitored ConfigMgr components. This email is sent every day!',
    [Parameter(Mandatory=$false)]
    [switch]$NoCacheState,
    [Parameter(Mandatory=$false)]
    [string]$CachePath,
    [Parameter(Mandatory=$false)]
    [string]$PrtgLookupFileName,
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
    [string[]]$ExcludeComponentsList = @("SMS_DISTRIBUTION_MANAGER","SMS_PACKAGE_TRANSFER_MANAGER"),
    [Parameter(Mandatory=$false)]
    [string[]]$ExcludeSiteSystemsList = @(),
    [Parameter(Mandatory=$false)]
    [int[]]$ExcludeAlertIDsList = @(),
    [Parameter(Mandatory=$false)]
    [switch]$IgnoreGeneralAlerts,
    [Parameter(Mandatory=$false)]
    [switch]$IgnoreEPAlerts,
    [Parameter(Mandatory=$false)]
    [switch]$IgnoreCHAlerts
)


#region admin check 
# Ensure that the Script is running with elevated permissions
if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Warning 'The script needs admin rights to run. Start PowerShell with administrative rights and run the script again'
    return 
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
                        #[string]$shortDescription = $InputObject.Description -replace "\'", "" -replace '>','_' # Remove some chars like quotation marks or >
                        [string]$shortDescription = $InputObject.Name
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

#region Get system fqdn
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

#region Base param definition
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

#region main checks
$resultObject = New-Object System.Collections.ArrayList
if ($TestMode)
{
    if($WriteLog){Write-CMTraceLog -Message "Will create $OutputTestData test alarms" -Component ($MyInvocation.MyCommand)}
    # create dummy entries
    for ($i = 1; $i -le $OutputTestData; $i++)
    { 
        $tmpObj = New-Object psobject | Select-Object $propertyList
        $tmpObj.CheckType = 'DummyData'
        $tmpObj.Name = 'DummyData:{0}:Dummy{1}' -f $systemName, $i.ToString('00')
        $tmpObj.SystemName = $systemName
        $tmpObj.Status = 'Error'
        $tmpObj.SiteCode = "P01"
        $tmpObj.Description = "This is just a dummy entry"
        $tmpObj.PossibleActions = 'Check ConfigMgr console. Also, check the logfile of the corresponding component'
        [void]$resultObject.Add($tmpObj) 
    }
}
else
{

    #region Checks
    switch (Test-ConfigMgrActiveSiteSystemNode -SiteSystemFQDN $systemName)
    {
        1 ## ACTIVE NODE FOUND. Run checks
        {
            if($WriteLog){Write-CMTraceLog -Message "Active node found. Run checks" -Component ($MyInvocation.MyCommand)}
            #region Get provider location and site code
            try 
            {
                $ProviderInfo = $null
                $ProviderInfo = Get-WmiObject -Namespace "root\sms" -query "select SiteCode, Machine from SMS_ProviderLocation where ProviderForLocalSite = True" -ErrorAction Stop
                $ProviderInfo = $ProviderInfo | Select-Object SiteCode, Machine -First 1            
            }
            catch 
            {
                $tmpScriptStateObj.Status = 'Error'
                $tmpScriptStateObj.Description = "$($error[0].Exception)"
            }

            if (-NOT ($ProviderInfo))
            {
                $tmpScriptStateObj.Status = 'Error'
                $tmpScriptStateObj.Description = "Provider location could not be determined"
            }
            else
            {
            #endregion
                #region SMS_ComponentSummarizer
                # Trying to read SMS_ComponentSummarizer to extract component state
                try 
                {
                    $wqlQuery = "SELECT * FROM SMS_ComponentSummarizer WHERE TallyInterval='0001128000100008'"
                    [array]$listFromComponentSummarizer = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wqlQuery -ErrorAction Stop
                    if ($listFromComponentSummarizer.Count -eq 0)
                    {
                        $tmpScriptStateObj.Status = 'Error'
                        $tmpScriptStateObj.Description = "User running the script might not have enough rights to read class SMS_ComponentSummarizer"
                    }
                    else 
                    {
                        #ComponentType like 'Monitored%' and Status <> 0
                        #Status: 0=OK, 1=Warning, 2=Error 
                        foreach ($componentState in ($listFromComponentSummarizer | Where-Object {($_.Status -ne 0)}))
                        {

                            # We might need to exclude some components from monitoring
                            if ($ExcludeComponentsList -icontains $componentState.ComponentName)
                            {
                                if($WriteLog){Write-CMTraceLog -Message "Will skip component with name: $($componentState.ComponentName)" -Component ($MyInvocation.MyCommand)}
                                continue
                            }

                            # Build the object for the result list
                            $tmpObj = New-Object psobject | Select-Object $propertyList
                            $tmpObj.CheckType = 'ComponentState'
                            $tmpObj.Name = '{0}:{1}:{2}:{3}' -f $tmpObj.CheckType, $componentState.MachineName, $componentState.ComponentName, $componentState.SiteCode
                            $tmpObj.SystemName = $componentState.MachineName
                            $tmpObj.Status = if($componentState.Status -eq 1){'Warning'}elseif ($componentState.Status -eq 2){'Error'}
                            $tmpObj.SiteCode = $componentState.SiteCode
                            $tmpObj.Description = ""
                            $tmpObj.PossibleActions = 'ConfigMgr console: "\Monitoring\Overview\System Status\Component Status". Also, check the logfile of the corresponding component'
                            [void]$resultObject.Add($tmpObj) 
                        }
                    }
                }
                catch 
                {
                    $tmpScriptStateObj.Status = 'Error'
                    $tmpScriptStateObj.Description = "$($error[0].Exception)"
                }
                #endregion


                #region SMS_SiteSystemSummarizer
                # Trying to read SMS_SiteSystemSummarizer to extract site system state
                try 
                {
                    $wqlQuery = "SELECT * FROM SMS_SiteSystemSummarizer"
                    [array]$listFromSiteSystemSummarizer = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wqlQuery -ErrorAction Stop
                    if ($listFromSiteSystemSummarizer.Count -eq 0)
                    {
                        $tmpScriptStateObj.Status = 'Error'
                        $tmpScriptStateObj.Description = "User running the script might not have enough rights to read class SMS_SiteSystemSummarizer"
                    }
                    else 
                    {
                        foreach ($siteSystemState in ($listFromSiteSystemSummarizer | Where-Object {$_.Status -ne 0}))
                        {
                            # Extract systemname from string looking like this: ["Display=\\SEC01.contoso.local\"]MSWNET:["SMS_SITE=S01"]\\SEC01.contoso.local\
                            $siteSystemName = $null
                            $siteSystemName = [regex]::match($siteSystemState.SiteSystem, '(\\\\.+\\\"\])')
                            if (-NOT($siteSystemName))
                            {
                                $siteSystemName = 'Name could not be determined'
                            }
                            else 
                            {
                                $siteSystemName = $siteSystemName -replace '\\', '' -replace '\"', '' -replace '\]', ''   
                            }

                            # we might need to exclude some site systems from monitoring
                            if ($ExcludeSiteSystemsList -icontains $siteSystemName)
                            {
                                if($WriteLog){Write-CMTraceLog -Message "Will skip site system with name: $($siteSystemName)" -Component ($MyInvocation.MyCommand)}
                                continue
                            }

                            # Build the object for the result list
                            $tmpObj = New-Object psobject | Select-Object $propertyList
                            $tmpObj.CheckType = 'SiteSystemState'
                            $tmpObj.Name = '{0}:{1}:{2}:{3}' -f $tmpObj.CheckType, $systemName, $siteSystemState.Role, $siteSystemState.SiteCode
                            $tmpObj.SystemName = $siteSystemName
                            $tmpObj.Status = if($siteSystemState.Status -eq 1){'Warning'}elseif ($siteSystemState.Status -eq 2){'Error'}
                            $tmpObj.SiteCode = $siteSystemState.SiteCode
                            $tmpObj.Description = ""
                            $tmpObj.PossibleActions = 'ConfigMgr console: "\Monitoring\Overview\System Status\Site Status". Also, check the logfile of the corresponding component'
                            [void]$resultObject.Add($tmpObj) 
                        }
                    }
                }
                catch 
                {
                    $tmpScriptStateObj.Status = 'Error'
                    $tmpScriptStateObj.Description = "$($error[0].Exception)"
                }
                #endregion


                #region SMS_Alert
                # Trying to read SMS_Alert to extract alert state
                If ($IgnoreGeneralAlerts)
                {
                    if($WriteLog){Write-CMTraceLog -Message "Will ignore all general ConfigMgr alerts" -Component ($MyInvocation.MyCommand)}
                }
                else 
                {
                    if($WriteLog){Write-CMTraceLog -Message "Will check general ConfigMgr alerts" -Component ($MyInvocation.MyCommand)} 
                
                    try 
                    {
                        $wqlQuery = "select * from SMS_Alert"
                        [array]$listFromSMSAlert = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wqlQuery -ErrorAction Stop
                        <#
                            AlertState
                            0  Active
                            1  Postponed
                            2  Canceled
                            3  Unknown
                            4  Disabled
                            5  Never Triggered
                            
                            Severity
                            1  Error
                            2  Warning
                            3  Informational
                        #>
                        if ($listFromSMSAlert.Count -eq 0)
                        {
                            $tmpScriptStateObj.Status = 'Error'
                            $tmpScriptStateObj.Description = "User running the script might not have enough rights to read class SMS_Alert"
                        }
                        else 
                        {
                            foreach ($alertState in ($listFromSMSAlert | Where-Object {($_.AlertState -eq 0) -and ($_.IsIgnored -eq 0)}))
                            {

                                # we might need to exclude some alerts from monitoring
                                if ($ExcludeAlertIDsList -contains $alertState.ID)
                                {
                                    if($WriteLog){Write-CMTraceLog -Message "Will skip alert with ID: $($alertState.ID)" -Component ($MyInvocation.MyCommand)}
                                    continue
                                }

                                if($alertState.SourceSiteCode)
                                {
                                    $sourceSiteCode = $alertState.SourceSiteCode
                                }
                                else
                                {
                                    $sourceSiteCode = $($ProviderInfo.SiteCode)
                                }

                                
                                # Trying to find a unique name for the alert, since multiple duplicate entries are possible
                                if (($alertState.Name -ieq '$RuleFailureAlertName') -or ($alertState.Name -ieq 'Rule Failure Alert'))
                                {
                                    if($alertState.InstanceNameParam1)
                                    {
                                        $alertName = $alertState.InstanceNameParam1
                                    }
                                    else
                                    {
                                        $alertName = 'Rule Failure Alert'
                                    }
                                }
                                else 
                                {
                                    $alertName = $alertState.Name
                                }

                                $tmpObj = New-Object psobject | Select-Object $propertyList
                                $tmpObj.CheckType = 'AlertState'
                                $tmpObj.Name = '{0}:{1}:{2}:{3}:ID{4}' -f $tmpObj.CheckType, $systemName, $alertName, $sourceSiteCode, $alertState.ID
                                $tmpObj.SystemName = $systemName
                                $tmpObj.Status = if($alertState.Severity -eq 1){'Error'}elseif($alertState.Severity -eq 2){'Warning'}elseif($alertState.Severity -eq 3){'Informational'}
                                $tmpObj.SiteCode = $alertState.SourceSiteCode
                                $tmpObj.Description = ""
                                $tmpObj.PossibleActions = 'ConfigMgr console: "\Monitoring\Overview\Alerts\Active Alerts". Also, check the logfile of the corresponding component'
                                [void]$resultObject.Add($tmpObj) 
                            }
                        }
                    }
                    catch 
                    {
                        $tmpScriptStateObj.Status = 'Error'
                        $tmpScriptStateObj.Description = "$($error[0].Exception)"
                    }
                }
                #endregion


                #region SMS_EPAlert
                # Trying to read SMS_EPAlert to extract alert state
                if ($IgnoreEPAlerts)
                {
                    if($WriteLog){Write-CMTraceLog -Message "Will ignore all Endpoint Protection related ConfigMgr alerts" -Component ($MyInvocation.MyCommand)}
                }
                else
                {
                    if($WriteLog){Write-CMTraceLog -Message "Will check Endpoint Protection related ConfigMgr alerts" -Component ($MyInvocation.MyCommand)} 

                    try 
                    {
                        $wqlQuery = "select * from SMS_EPAlert where AlertState = 0 and IsIgnored = 0"
                        [array]$listFromSMSEPAlert = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wqlQuery -ErrorAction Stop
                        #$listFromSMSAlert | ogv
                        <#
                            AlertState
                            0  Active
                            1  Postponed
                            2  Canceled
                            3  Unknown
                            4  Disabled
                            5  Never Triggered
                            
                            Severity
                            1  Error
                            2  Warning
                            3  Informational
                        
                        #>
                        foreach ($alertState in $listFromSMSEPAlert)
                        {
                            # we might need to exclude some alerts from monitoring
                            if ($ExcludeAlertIDsList -contains $alertState.ID)
                            {
                                if($WriteLog){Write-CMTraceLog -Message "Will skip alert with ID: $($alertState.ID)" -Component ($MyInvocation.MyCommand)}
                                continue
                            }     

                            if($alertState.SourceSiteCode)
                            {
                                $sourceSiteCode = $alertState.SourceSiteCode
                            }
                            else
                            {
                                $sourceSiteCode = $($ProviderInfo.SiteCode)
                            }

                            $tmpObj = New-Object psobject | Select-Object $propertyList
                            $tmpObj.CheckType = 'EPAlertState'
                            $tmpObj.Name = '{0}:{1}:{2}:{3}:ID{4}' -f $tmpObj.CheckType, $systemName, $alertState.Name, $sourceSiteCode, $alertState.ID
                            $tmpObj.SystemName = $systemName
                            $tmpObj.Status = if($alertState.Severity -eq 1){'Error'}elseif($alertState.Severity -eq 2){'Warning'}elseif($alertState.Severity -eq 3){'Informational'}
                            $tmpObj.SiteCode = $alertState.SourceSiteCode
                            $tmpObj.Description = ""
                            $tmpObj.PossibleActions = 'ConfigMgr console: "\Monitoring\Overview\Alerts\Active Alerts". Also, check the logfile of the corresponding component'
                            [void]$resultObject.Add($tmpObj) 
                        }
                    }
                    catch 
                    {
                        $tmpScriptStateObj.Status = 'Error'
                        $tmpScriptStateObj.Description = "$($error[0].Exception)"
                    }
                }
                #endregion


                #region SMS_CHAlert
                # Trying to read SMS_CHAlert to extract alert state
                if ($IgnoreCHAlerts)
                {
                    if($WriteLog){Write-CMTraceLog -Message "Will ignore all Client Health related ConfigMgr alerts" -Component ($MyInvocation.MyCommand)}
                }
                else
                {
                    try 
                    {
                        $wqlQuery = "select * from SMS_CHAlert where AlertState = 0 and IsIgnored = 0"
                        [array]$listFromSMSCHAlert = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wqlQuery -ErrorAction Stop
                        #$listFromSMSAlert | ogv
                        <#
                            AlertState
                            0  Active
                            1  Postponed
                            2  Canceled
                            3  Unknown
                            4  Disabled
                            5  Never Triggered
                            
                            Severity
                            1  Error
                            2  Warning
                            3  Informational
                        
                        #>
                        foreach ($alertState in $listFromSMSCHAlert)
                        {

                            # we might need to exclude some alerts from monitoring
                            if ($ExcludeAlertIDsList -contains $alertState.ID)
                            {
                                if($WriteLog){Write-CMTraceLog -Message "Will skip alert with ID: $($alertState.ID)" -Component ($MyInvocation.MyCommand)}
                                continue
                            }

                            if($alertState.SourceSiteCode)
                            {
                                $sourceSiteCode = $alertState.SourceSiteCode
                            }
                            else
                            {
                                $sourceSiteCode = $($ProviderInfo.SiteCode)
                            }
                            $tmpObj = New-Object psobject | Select-Object $propertyList
                            $tmpObj.CheckType = 'CHAlertState'
                            $tmpObj.Name = '{0}:{1}:{2}:{3}:ID{4}' -f $tmpObj.CheckType, $systemName, $alertState.Name, $sourceSiteCode, $alertState.ID
                            $tmpObj.SystemName = $systemName
                            $tmpObj.Status = if($alertState.Severity -eq 1){'Error'}elseif($alertState.Severity -eq 2){'Warning'}elseif($alertState.Severity -eq 3){'Informational'}
                            $tmpObj.SiteCode = $alertState.SourceSiteCode
                            $tmpObj.Description = ""
                            $tmpObj.PossibleActions = 'ConfigMgr console: "\Monitoring\Overview\Alerts\Active Alerts". Also, check the logfile of the corresponding component'
                            [void]$resultObject.Add($tmpObj) 
                        }
                    }
                    catch 
                    {
                        $tmpScriptStateObj.Status = 'Error'
                        $tmpScriptStateObj.Description = "$($error[0].Exception)"
                    }
                }
                #endregion
            } # END If (-NOT ($ProviderInfo))
        } # END Active NODE
        
        0 ## PASSIVE NODE FOUND. Nothing to do.
        {
            if($WriteLog){Write-CMTraceLog -Message "Passive node found. No checks will run" -Component ($MyInvocation.MyCommand)}
            $tmpScriptStateObj.Description = "Passive node found. No checks will run."
        }

        Default ## NO STATE FOUND
        {
            if($WriteLog){Write-CMTraceLog -Message "Error: No ConfigMgr Site System found" -Component ($MyInvocation.MyCommand)}
            $tmpScriptStateObj.Status = 'Error'
            $tmpScriptStateObj.Description = "Error: No ConfigMgr Site System found"
        }
    }
}

# Adding overall script state to list
if (-Not ($DontOutputScriptstate))
{
    [void]$resultObject.Add($tmpScriptStateObj)
}
#endregion

#region cache state
# In case we need to know wich components are already in error state
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

#region Output
if($WriteLog){Write-CMTraceLog -Message "Created $($resultObject.Count) alert items" -Component ($MyInvocation.MyCommand)}
switch ($OutputMode) 
{
    "GridView" 
    {  
        $resultObject | Out-GridView -Title 'List of states'
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
            $resultString = '{0}:ConfigMgr Components in failure state' -f $badResults.count
            Write-Output $resultString
        }
        else
        {
            Write-Output "0:No active ConfigMgr component alerts"
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