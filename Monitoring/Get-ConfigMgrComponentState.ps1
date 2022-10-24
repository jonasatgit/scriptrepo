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
    Script to monitor ConfigMgr component, site system and alert states
    
.DESCRIPTION
    Script to monitor ConfigMgr component, site system and alert states based on the following WMI classes:
    SMS_ComponentSummarizer
    SMS_SiteSystemSummarizer
    SMS_Alert
    SMS_EPAlert
    SMS_CHAlert    
    
    The script will always return zero errors when running on a passive ConfigMgr Site Server.

    Source: https://github.com/jonasatgit/scriptrepo

.PARAMETER GridViewOutput
    Switch parameter to be able to output the results in a GridView instead of compressed JSON

.EXAMPLE
    Get-ConfigMgrComponentState.ps1

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -OutputMode GridView

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -OutputMode JSON

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -OutputMode JSONCompressed

.INPUTS
   None

.OUTPUTS
   Either GridView, JSON formatted or JSON compressed. JSON compressed is the default mode
    
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [ValidateSet("GridView", "JSON", "JSONCompressed")]
    [String]$OutputMode = "JSONCompressed"
)


#region admin check 
# Ensure that the Script is running with elevated permissions
if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Warning 'The script needs admin rights to run. Start PowerShell with administrative rights and run the script again'
    return 
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
        [object]$InputObject
    )

    Begin
    {
        $resultsObject = New-Object System.Collections.ArrayList
        $outObject = New-Object psobject | Select-Object InterfaceVersion, Results
        $outObject.InterfaceVersion = 1    
    }
    Process
    {
        switch ($InputObject.Status) 
        {
            'Ok' {$outState = 0}
            'Warning' {$outState = 1}
            'Error' {$outState = 2}
            Default {$outState = 3}
        }

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

        $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
        $tmpResultObject.Name = $InputObject.SystemName
        $tmpResultObject.Epoch = 0 # NOT USED at the moment. FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
        $tmpResultObject.Status = $outState
        $tmpResultObject.ShortDescription = $shortDescription
        $tmpResultObject.Debug = ''
        [void]$resultsObject.Add($tmpResultObject)
           
    }
    End
    {
        $outObject.Results = $resultsObject
        $outObject
    }

}
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
$outObj = New-Object System.Collections.ArrayList
[array]$propertyList  = $null
$propertyList += 'CheckType' # Either Alert, EPAlert, CHAlert, Component or SiteSystem
$propertyList += 'Name'
$propertyList += 'SystemName'
$propertyList += 'SiteCode'
$propertyList += 'Status'
$propertyList += 'Description'
$propertyList += 'PossibleActions'
#endregion

#region Checks
switch (Test-ConfigMgrActiveSiteSystemNode -SiteSystemFQDN $systemName)
{
    1 ## ACTIVE NODE FOUND. Run checks
    {
        
        #region Get provider location and site code
        try 
        {
            $ProviderInfo = $null
            $ProviderInfo = Get-WmiObject -Namespace "root\sms" -query "select SiteCode, Machine from SMS_ProviderLocation where ProviderForLocalSite = True" -ErrorAction Stop
            $ProviderInfo = $ProviderInfo | Select-Object SiteCode, Machine -First 1            
        }
        catch 
        {
            $tmpObj = New-Object psobject | Select-Object $propertyList
            $tmpObj.CheckType = 'ProviderLocation'
            $tmpObj.Status = 'Error'
            $tmpObj.Description = "$($error[0].Exception)"
            [void]$outObj.Add($tmpObj)
        }

        if (-NOT ($ProviderInfo))
        {
            $tmpObj = New-Object psobject | Select-Object $propertyList
            $tmpObj.CheckType = 'ProviderLocation'
            $tmpObj.Status = 'Error'
            $tmpObj.Description = "Provider location could not be determined"
            [void]$outObj.Add($tmpObj)
        }
        else
        {
        #endregion


            #region SMS_ComponentSummarizer
            # Trying to read SMS_ComponentSummarizer to extract component state
            try 
            {
                $wqlQuery = "SELECT * FROM SMS_ComponentSummarizer WHERE TallyInterval='0001128000100008' and ComponentType like 'Monitored%' and Status <> 0"
                [array]$listFromComponentSummarizer = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wqlQuery -ErrorAction Stop
                
                #Status: 0=OK, 1=Warning, 2=Error 
                foreach ($componentState in $listFromComponentSummarizer)
                {
                    $tmpObj = New-Object psobject | Select-Object $propertyList
                    $tmpObj.CheckType = 'ComponentState'
                    $tmpObj.Name = $componentState.ComponentName
                    $tmpObj.SystemName = $componentState.MachineName
                    $tmpObj.Status = if($componentState.Status -eq 1){'Warning'}elseif ($componentState.Status -eq 2){'Error'}
                    $tmpObj.SiteCode = $componentState.SiteCode
                    $tmpObj.Description = ""
                    $tmpObj.PossibleActions = 'Open the ConfigMgr console and go to: "\Monitoring\Overview\System Status\Component Status". Also, check the logfile of the corresponding component'
                    [void]$outObj.Add($tmpObj) 
                }
            }
            catch 
            {
                $tmpObj = New-Object psobject | Select-Object $propertyList
                $tmpObj.CheckType = 'ComponentState'
                $tmpObj.Status = 'Error'
                $tmpObj.Description = "$($error[0].Exception)"
                [void]$outObj.Add($tmpObj)
            }
            #endregion


            #region SMS_SiteSystemSummarizer
            # Trying to read SMS_SiteSystemSummarizer to extract site system state
            try 
            {
                $wqlQuery = "SELECT * FROM SMS_SiteSystemSummarizer where Status <> 0"
                [array]$listFromSiteSystemSummarizer = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wqlQuery -ErrorAction Stop

                foreach ($siteSystemState in $listFromSiteSystemSummarizer)
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

                    $tmpObj = New-Object psobject | Select-Object $propertyList
                    $tmpObj.CheckType = 'SiteSystemState'
                    $tmpObj.Name = $siteSystemState.Role
                    $tmpObj.SystemName = $siteSystemName
                    $tmpObj.Status = if($siteSystemState.Status -eq 1){'Warning'}elseif ($siteSystemState.Status -eq 2){'Error'}
                    $tmpObj.SiteCode = $siteSystemState.SiteCode
                    $tmpObj.Description = ""
                    $tmpObj.PossibleActions = 'Open the ConfigMgr console and go to: "\Monitoring\Overview\System Status\Site Status". Also, check the logfile of the corresponding component'
                    [void]$outObj.Add($tmpObj) 
                }


            }
            catch 
            {
                $tmpObj = New-Object psobject | Select-Object $propertyList
                $tmpObj.CheckType = 'SiteSystemState'
                $tmpObj.Status = 'Error'
                $tmpObj.Description = "$($error[0].Exception)"
                [void]$outObj.Add($tmpObj)
            }
            #endregion


            #region SMS_Alert
            # Trying to read SMS_Alert to extract alert state
            try 
            {
                $wqlQuery = "select * from SMS_Alert where AlertState = 0 and IsIgnored = 0"
                [array]$listFromSMSAlert = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wqlQuery -ErrorAction Stop
                #$listFromSMSAlert | ogv
                <#
                    AlertState
                    0	Active
                    1	Postponed
                    2	Canceled
                    3	Unknown
                    4	Disabled
                    5	Never Triggered
                    
                    Severity
                    1	Error
                    2	Warning
                    3	Informational
                
                #>
                foreach ($alertState in $listFromSMSAlert)
                {
                    $tmpObj = New-Object psobject | Select-Object $propertyList
                    $tmpObj.CheckType = 'AlertState'
                    $tmpObj.Name = $alertState.Name
                    $tmpObj.SystemName = $systemName
                    $tmpObj.Status = if($alertState.Severity -eq 1){'Error'}elseif($alertState.Severity -eq 2){'Warning'}elseif($alertState.Severity -eq 3){'Informational'}
                    $tmpObj.SiteCode = $alertState.SourceSiteCode
                    $tmpObj.Description = ""
                    $tmpObj.PossibleActions = 'Open the ConfigMgr console and go to: "\Monitoring\Overview\Alerts\Active Alerts". Also, check the logfile of the corresponding component'
                    [void]$outObj.Add($tmpObj) 
                }
            }
            catch 
            {
                $tmpObj = New-Object psobject | Select-Object $propertyList
                $tmpObj.CheckType = 'AlertState'
                $tmpObj.Status = 'Error'
                $tmpObj.Description = "$($error[0].Exception)"
                [void]$outObj.Add($tmpObj)
            }
            #endregion


            #region SMS_EPAlert
            # Trying to read SMS_EPAlert to extract alert state
            try 
            {
                $wqlQuery = "select * from SMS_EPAlert where AlertState = 0 and IsIgnored = 0"
                [array]$listFromSMSEPAlert = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wqlQuery -ErrorAction Stop
                #$listFromSMSAlert | ogv
                <#
                    AlertState
                    0	Active
                    1	Postponed
                    2	Canceled
                    3	Unknown
                    4	Disabled
                    5	Never Triggered
                    
                    Severity
                    1	Error
                    2	Warning
                    3	Informational
                
                #>
                foreach ($alertState in $listFromSMSEPAlert)
                {
                    $tmpObj = New-Object psobject | Select-Object $propertyList
                    $tmpObj.CheckType = 'EPAlertState'
                    $tmpObj.Name = $alertState.Name
                    $tmpObj.SystemName = $systemName
                    $tmpObj.Status = if($alertState.Severity -eq 1){'Error'}elseif($alertState.Severity -eq 2){'Warning'}elseif($alertState.Severity -eq 3){'Informational'}
                    $tmpObj.SiteCode = $alertState.SourceSiteCode
                    $tmpObj.Description = ""
                    $tmpObj.PossibleActions = 'Open the ConfigMgr console and go to: "\Monitoring\Overview\Alerts\Active Alerts". Also, check the logfile of the corresponding component'
                    [void]$outObj.Add($tmpObj) 
                }
            }
            catch 
            {
                $tmpObj = New-Object psobject | Select-Object $propertyList
                $tmpObj.CheckType = 'EPAlertState'
                $tmpObj.Status = 'Error'
                $tmpObj.Description = "$($error[0].Exception)"
                [void]$outObj.Add($tmpObj)
            }
            #endregion


            #region SMS_CHAlert
            # Trying to read SMS_CHAlert to extract alert state
            try 
            {
                $wqlQuery = "select * from SMS_CHAlert where AlertState = 0 and IsIgnored = 0"
                [array]$listFromSMSCHAlert = Get-WmiObject -ComputerName ($ProviderInfo.Machine) -Namespace "root\sms\site_$($ProviderInfo.SiteCode)" -Query $wqlQuery -ErrorAction Stop
                #$listFromSMSAlert | ogv
                <#
                    AlertState
                    0	Active
                    1	Postponed
                    2	Canceled
                    3	Unknown
                    4	Disabled
                    5	Never Triggered
                    
                    Severity
                    1	Error
                    2	Warning
                    3	Informational
                
                #>
                foreach ($alertState in $listFromSMSCHAlert)
                {
                    $tmpObj = New-Object psobject | Select-Object $propertyList
                    $tmpObj.CheckType = 'CHAlertState'
                    $tmpObj.Name = $alertState.Name
                    $tmpObj.SystemName = $systemName
                    $tmpObj.Status = if($alertState.Severity -eq 1){'Error'}elseif($alertState.Severity -eq 2){'Warning'}elseif($alertState.Severity -eq 3){'Informational'}
                    $tmpObj.SiteCode = $alertState.SourceSiteCode
                    $tmpObj.Description = ""
                    $tmpObj.PossibleActions = 'Open the ConfigMgr console and go to: "\Monitoring\Overview\Alerts\Active Alerts". Also, check the logfile of the corresponding component'
                    [void]$outObj.Add($tmpObj) 
                }
            }
            catch 
            {
                $tmpObj = New-Object psobject | Select-Object $propertyList
                $tmpObj.CheckType = 'CHAlertState'
                $tmpObj.Status = 'Error'
                $tmpObj.Description = "$($error[0].Exception)"
                [void]$outObj.Add($tmpObj)
            }
            #endregion
        } # END If (-NOT ($ProviderInfo))
    } # END Active NODE
    
    0 ## PASSIVE NODE FOUND. Nothing to do.
    {
        $tmpObj = New-Object psobject | Select-Object $propertyList
        $tmpObj.CheckType = 'Script'
        $tmpObj.Status = 'Ok'
        $tmpObj.Description = "Passive node found. No checks will run."
        [void]$outObj.Add($tmpObj)     
    }

    Default ## NO STATE FOUND
    {
        $tmpObj = New-Object psobject | Select-Object $propertyList
        $tmpObj.CheckType = 'Script'
        $tmpObj.Status = 'Error'
        $tmpObj.Description = "Error: No ConfigMgr Site System found"
        [void]$outObj.Add($tmpObj) 
        # No state found. Either no ConfigMgr Site System or script error
    }
}

if ($outObj.Count -eq 0)
{
    $tmpObj = New-Object psobject | Select-Object $propertyList
    $tmpObj.CheckType = 'Script'
    $tmpObj.Status = 'Ok'
    $tmpObj.Description = "No errors found!"
    [void]$outObj.Add($tmpObj) 
}


#endregion

#region Output
switch ($OutputMode) 
{
    "GridView" 
    {  
        $outObj | Out-GridView -Title 'List of states'
    }
    "JSON" 
    {
        $outObj | ConvertTo-CustomMonitoringObject | ConvertTo-Json
    }
    "JSONCompressed"
    {
        $outObj | ConvertTo-CustomMonitoringObject | ConvertTo-Json -Compress
    }
}
#endregion
