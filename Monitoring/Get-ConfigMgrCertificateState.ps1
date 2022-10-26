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

.PARAMETER GridViewOutput
    Switch parameter to be able to output the results in a GridView instead of compressed JSON

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
   Either GridView, JSON formatted or JSON compressed.

.LINK
    https://github.com/jonasatgit/scriptrepo  
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [ValidateSet("GridView", "JSON", "JSONCompressed","HTMLMail")]
    [String]$OutputMode = "GridView",
    [Parameter(Mandatory=$false)]
    [string]$TemplateSearchString = '*ConfigMgr*Certificate*',
    [Parameter(Mandatory=$false)]
    [int]$MinValidDays = 30
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


#region main certificate logic
$resultsObject = New-Object System.Collections.ArrayList

[array]$propertyList  = $null
$propertyList += 'Name' # Either Alert, EPAlert, CHAlert, Component or SiteSystem
$propertyList += 'Status'
$propertyList += 'ShortDescription'
$propertyList += 'Debug'

[bool]$badResult = $false

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
                    $tmpResultObject = New-Object psobject | Select-Object $propertyList
                    $tmpResultObject.Name = $systemName
                    $tmpResultObject.Status = 1
                    $tmpResultObject.ShortDescription = 'Warning: DP or Boot certificate is about to expire in {0} days! See console for Certificate GUID:{1}' -f $expireDays, ($OSDCertificate.SMSID)
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
            $tmpResultObject.Status = 1
            $tmpResultObject.ShortDescription = 'Warning: No DP or Boot certificate found!'
            $tmpResultObject.Debug = ''
            [void]$resultsObject.Add($tmpResultObject)
            $badResult = $true        
        }   
    }
    else
    {
        $tmpResultObject = New-Object psobject | Select-Object $propertyList
        $tmpResultObject.Name = $systemName
        $tmpResultObject.Status = 1
        $tmpResultObject.ShortDescription = 'Warning: Not able to get SMS Provider location from root\sms -> SMS_ProviderLocation'
        $tmpResultObject.Debug = ''
        [void]$resultsObject.Add($tmpResultObject)
        $badResult = $true
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
                $tmpResultObject = New-Object psobject | Select-Object $propertyList
                $tmpResultObject.Name = $systemName
                $tmpResultObject.Status = 1
                $tmpResultObject.ShortDescription = 'Warning: Certificate is about to expire in {0} days! Thumbprint:{1}' -f $expireDays, ($certificate.Thumbprint)
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
        $tmpResultObject.Status = 1
        $tmpResultObject.ShortDescription = 'Warning: No ConfigMgr Certificate found on system!'
        $tmpResultObject.Debug = ''
        [void]$resultsObject.Add($tmpResultObject)
        $badResult = $true   
    }
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
        $resultsObject | ConvertTo-CustomMonitoringObject -InputType ConfigMgrCertificateState -SystemName $systemName | ConvertTo-Json
    }
    "JSONCompressed"
    {
        $resultsObject | ConvertTo-CustomMonitoringObject -InputType ConfigMgrCertificateState -SystemName $systemName | ConvertTo-Json -Compress
    }
    "HTMLMail"
    {      
        # Reference email script
        .$PSScriptRoot\Send-CustomMonitoringMail.ps1

        # If there are bad results, lets change the subject of the mail
        if($resultsObject.Where({$_.Status -ne 0}))
        {
            $mailSubjectResultString = 'OK'
        }
        else
        {
            $mailSubjectResultString = 'Failed'
        }

        $MailSubject = '{0}: Certificate state from: {1}' -f $mailSubjectResultString, $systemName
        $MailInfotext = '{0}<br>{1}' -f $systemName, $MailInfotext

        Send-CustomMonitoringMail -MailMessageObject $outObj -MailSubject $MailSubject -MailInfotext $MailInfotext -HTMLFileOnly -LogActions

    }
}
#endregion
