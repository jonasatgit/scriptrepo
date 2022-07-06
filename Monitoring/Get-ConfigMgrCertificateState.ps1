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
    Version: 2022-04-11
    
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
    Get-ConfigMgrCertificateState.ps1 -GridViewOutput

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -TemplateSearchString '*Custom*ConfigMgr*Certificate*' -MinValidDays 30

.INPUTS
   None

.OUTPUTS
   Compressed JSON string 
    
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [Switch]$GridViewOutput,
    [Parameter(Mandatory=$false)]
    [string]$TemplateSearchString = '*ConfigMgr*Certificate*',
    [Parameter(Mandatory=$false)]
    [int]$MinValidDays = 30
)

#Ensure that the Script is running with elevated permissions
if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Warning 'The script needs admin rights to run. Start PowerShell with administrative rights and run the script again'
    return 
}

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

$resultsObject = New-Object System.Collections.ArrayList
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
                    $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
                    $tmpResultObject.Name = $systemName
                    $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
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
            $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
            $tmpResultObject.Name = $systemName
            $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
            $tmpResultObject.Status = 1
            $tmpResultObject.ShortDescription = 'Warning: No DP or Boot certificate found!'
            $tmpResultObject.Debug = ''
            [void]$resultsObject.Add($tmpResultObject)
            $badResult = $true        
        }   
    }
    else
    {
        $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
        $tmpResultObject.Name = $systemName
        $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
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
                $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
                $tmpResultObject.Name = $systemName
                $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
                $tmpResultObject.Status = 1
                $tmpResultObject.ShortDescription = 'Warning: Certificate is about to expire in {0} days! Thumbprint:{1}' -f $expireDays, ($certificate.Thumbprint)
                $tmpResultObject.Debug = ''
                [void]$resultsObject.Add($tmpResultObject)
                $badResult = $true
                $configMgrCertificateFound = $true         
            }
        
        }
    }
    else
    {
        $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
        $tmpResultObject.Name = $systemName
        $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
        $tmpResultObject.Status = 1
        $tmpResultObject.ShortDescription = 'Warning: No ConfigMgr Certificate found on system!'
        $tmpResultObject.Debug = ''
        [void]$resultsObject.Add($tmpResultObject)
        $badResult = $true   
    }
}


# used as a temp object for JSON output
$outObject = New-Object psobject | Select-Object InterfaceVersion, Results
$outObject.InterfaceVersion = 1
if ($badResult)
{
    $outObject.Results = $resultsObject
}
else
{
    $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
    $tmpResultObject.Name = $systemName
    $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
    $tmpResultObject.Status = 0
    $tmpResultObject.ShortDescription = 'ok'
    $tmpResultObject.Debug = ''
    [void]$resultsObject.Add($tmpResultObject)
    $outObject.Results = $resultsObject
}


if ($GridViewOutput)
{
    $outObject.Results | Out-GridView
}
else
{
    $outObject | ConvertTo-Json -Compress
}  
