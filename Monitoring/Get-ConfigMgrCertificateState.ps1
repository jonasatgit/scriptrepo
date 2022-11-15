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
    Script to monitor ConfigMgr related certificates based on a specific template name. Will also connect to SMS provider for DP certificates.
    
.DESCRIPTION
    Script to monitor ConfigMgr related certificates based on a specific template name. Will also connect to SMS provider for DP certificates.
    Source: https://github.com/jonasatgit/scriptrepo

.PARAMETER OutputMode
    Parameter to be able to output the results in a GridView, special JSON format, special JSONCompressed format,
    a simple PowerShell objekt PSObject or via HTMLMail.
    The HTMLMail mode requires the script "Send-CustomMonitoringMail.ps1" to be in the same folder.

.PARAMETER TemplateSearchString
    String to search for a certificate based on a specific template name
    Valid template names are:
        '*Custom-ConfigMgrDPCertificate*'
        '*Custom-ConfigMgrIISCertificate*'
        '*Custom-QS-ConfigMgrDPCertificate*'
        '*Custom-QS-ConfigMgrIISCertificate*'
        OR
        '*ConfigMgr*Certificate*' to include all possible values

.PARAMETER MinValidDays
    Value in days before certificate expiration

.PARAMETER CacheState
    Boolean parameter. If set to $true, the script will output its current state to a JSON file.
    The file will be stored next to the script or a path set via parameter "CachePath"
    The filename will look like this: CACHE_[name-of-script.ps1].json

.PARAMETER CachePath
    Path to store the JSON cache file. Default value is root path of script. 

.PARAMETER OutputTestData
    Number of dummy test data objects. Helpful to test a monitoring solution without any actual ConfigMgr errors.

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -OutputMode GridView

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -OutputMode JSON

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -OutputMode JSONCompressed

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -OutputMode HTMLMail

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -TemplateSearchString '*Custom*ConfigMgr*Certificate*' -MinValidDays 30

.INPUTS
   None

.OUTPUTS
   Depends in OutputMode

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
    [string]$TemplateSearchString = '*ConfigMgr*Certificate*',
    [Parameter(Mandatory=$false)]
    [int]$MinValidDays = 30,
    [Parameter(Mandatory=$false)]
    [String]$MailInfotext = 'Status about monitored certificates. This email is sent every day!',
    [Parameter(Mandatory=$false)]
    [bool]$CacheState = $false,
    [Parameter(Mandatory=$false)]
    [string]$CachePath,
    [Parameter(Mandatory=$false)]
    [ValidateRange(0,60)]
    [int]$OutputTestData
)

#region admin rights
#Ensure that the Script is running with elevated permissions
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


#region systemname
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
                        [string]$shortDescription = $InputObject.Description -replace "\'", "" # Remove some chars like quotation marks    
                    }
                    Default 
                    {
                        [string]$shortDescription = $InputObject.PossibleActions -replace "\'", "" # Remove some chars like quotation marks
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
                $tmpResultObject.Name = $InputObject.Name -replace "\'", ""
                $tmpResultObject.Epoch = 0 # NOT USED at the moment. FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
                $tmpResultObject.Status = $outState
                $tmpResultObject.ShortDescription = $shortDescription
                $tmpResultObject.Debug = ''
                [void]$resultsObject.Add($tmpResultObject)
            }
            'PrtgObject'
            {
                $tmpResultObject = New-Object psobject | Select-Object Channel, Value, Warning
                $tmpResultObject.Channel = $InputObject.Name -replace "\'", ""
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


#region main certificate logic
<#
$resultObject = New-Object System.Collections.ArrayList

[array]$propertyList  = $null
$propertyList += 'Name' # Either Alert, EPAlert, CHAlert, Component or SiteSystem
$propertyList += 'Status'
$propertyList += 'ShortDescription'
$propertyList += 'Debug'
#>

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
    # create dummy entries
    for ($i = 1; $i -le $OutputTestData; $i++)
    { 
        # create dummy thumbprint
        $dummyThrumbprint = (-join ((65..73)+(65..73)+(65..73)+(65..73)+(65..73) | Get-Random -Count 40 | ForEach-Object {[char]$_})) -replace 'G|H|I', (Get-Random -Minimum 0 -Maximum 9)

        $tmpObj = New-Object psobject | Select-Object $propertyList
        $tmpObj.CheckType = 'Certificate'
        $tmpObj.Name = '{0}:{1}:{2}' -f $tmpObj.CheckType, $systemName, $dummyThrumbprint
        $tmpObj.SystemName = $systemName
        $tmpObj.Status = 'Error'
        $tmpObj.SiteCode = ""
        $tmpObj.Description = "Certificate is about to expire in {0} days! Thumbprint:{1}" -f (Get-Random -Minimum 0 -Maximum $MinValidDays), $dummyThrumbprint
        $tmpObj.PossibleActions = 'Renew certificate or request new one'
        [void]$resultObject.Add($tmpObj) 
    }
}
else
{
    # Going the extra mile and checking DP and or BootStick certificates via SMS Provider call, but just if we are on the active site server
    # Mainly to prevent multiple alerts for one certificate coming from multiple systems
    if ((Test-ConfigMgrActiveSiteSystemNode -SiteSystemFQDN $systemName) -eq 1)
    {
        # Active node found. Let's check DP certificates via SMS Provider
        $SMSProviderLocation = Get-WmiObject -Namespace root\sms -Query "SELECT * FROM SMS_ProviderLocation WHERE ProviderForLocalSite = 1" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($SMSProviderLocation)
        {
            [array]$ConfigMgrOSDCertificates = Get-WmiObject -Namespace "root\sms\Site_$($SMSProviderLocation.SiteCode)" -ComputerName ($SMSProviderLocation.Machine) -Query 'SELECT * FROM SMS_Certificate where Type in (1,2) and IsBlocked = 0'
            if ($ConfigMgrOSDCertificates)
            {
                foreach ($OSDCertificate in $ConfigMgrOSDCertificates)
                {
                    $expireDays = (New-TimeSpan -Start (Get-Date) -End ([Management.ManagementdateTimeConverter]::ToDateTime($OSDCertificate.ValidUntil))).Days
                    if ($expireDays -le $minValidDays)
                    {
                        $tmpObj = New-Object psobject | Select-Object $propertyList
                        $tmpObj.CheckType = 'Certificate'
                        $tmpObj.Name = '{0}:{1}:{2}' -f $tmpObj.CheckType, $systemName, ($OSDCertificate.SMSID)
                        $tmpObj.SystemName = $systemName
                        $tmpObj.Status = 'Warning'
                        $tmpObj.SiteCode = ""
                        $tmpObj.Description = 'DP or Boot certificate is about to expire in {0} days! See console for Certificate GUID:{1}' -f $expireDays, ($OSDCertificate.SMSID)
                        $tmpObj.PossibleActions = 'Renew certificate or request a new one'
                        [void]$resultObject.Add($tmpObj)   
                    }
                }
            }
            else
            {
                $tmpObj = New-Object psobject | Select-Object $propertyList
                $tmpObj.CheckType = 'Certificate'
                $tmpObj.Name = '{0}:{1}:DPCertificate' -f $tmpObj.CheckType, $systemName
                $tmpObj.SystemName = $systemName
                $tmpObj.Status = 'Warning'
                $tmpObj.SiteCode = ""
                $tmpObj.Description = 'No DP or Boot certificate found!'
                $tmpObj.PossibleActions = 'Renew certificate or request a new one'
                [void]$resultObject.Add($tmpObj)      
            }   
        }
        else
        {
            $tmpObj = New-Object psobject | Select-Object $propertyList
            $tmpObj.CheckType = 'Certificate'
            $tmpObj.Name = '{0}:{1}:DPCertificate' -f $tmpObj.CheckType, $systemName
            $tmpObj.SystemName = $systemName
            $tmpObj.Status = 'Error'
            $tmpObj.SiteCode = ""
            $tmpObj.Description = 'Not able to get SMS Provider location from root\sms -> SMS_ProviderLocation'
            $tmpObj.PossibleActions = 'Validate WMI or debug script'
            [void]$resultObject.Add($tmpObj)
        }

    }

    # Looking for certificates in personal store of current system if a webserver is installed
    # Format method: https://docs.microsoft.com/en-us/dotnet/api/system.security.cryptography.asnencodeddata.format
    if (Get-Service -Name W3SVC -ErrorAction SilentlyContinue)
    {
        $configMgrCerts = Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object { 
            $_.Extensions | Where-Object{ ($_.Oid.FriendlyName -eq 'Certificate Template Information') -and ($_.Format(0) -like $templateSearchString) }
        }

        if ($configMgrCerts)
        {
            foreach ($certificate in $configMgrCerts)
            {
                $expireDays = (New-TimeSpan -Start (Get-Date) -End ($certificate.NotAfter)).Days

                if ($expireDays -le $minValidDays)
                {              
                    $tmpObj = New-Object psobject | Select-Object $propertyList
                    $tmpObj.CheckType = 'Certificate'
                    $tmpObj.Name = '{0}:{1}:{2}' -f $tmpObj.CheckType, $systemName, ($certificate.Thumbprint)
                    $tmpObj.SystemName = $systemName
                    $tmpObj.Status = 'Warning'
                    $tmpObj.SiteCode = ""
                    $tmpObj.Description = 'Certificate is about to expire in {0} days! Thumbprint:{1}' -f $expireDays, ($certificate.Thumbprint)
                    $tmpObj.PossibleActions = 'Renew certificate or request a new one'
                    [void]$resultObject.Add($tmpObj)                  
                }       
            }
        }
        else
        {
            $tmpObj = New-Object psobject | Select-Object $propertyList
            $tmpObj.CheckType = 'Certificate'
            $tmpObj.Name = '{0}:{1}:NotFound' -f $tmpObj.CheckType, $systemName, ($certificate.Thumbprint)
            $tmpObj.SystemName = $systemName
            $tmpObj.Status = 'Warning'
            $tmpObj.SiteCode = ""
            $tmpObj.Description = 'No ConfigMgr Certificate based on template string: {0} found on system!' -f $templateSearchString
            $tmpObj.PossibleActions = 'Request a new certificate'
            [void]$resultObject.Add($tmpObj)   
        }
    }
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
        $resultObject | ConvertTo-CustomMonitoringObject -OutputType PrtgObject | ConvertTo-Json -Depth 3
    }
}
#endregion
