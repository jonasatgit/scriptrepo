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
    The filename will look like this: [name-of-script.ps1]_[Name of user running the script]_CACHE.json

.PARAMETER CachePath
    Path to store the JSON cache file. Default value is root path of script. 

.PARAMETER PrtgLookupFileName
    Name of a PRTG value lookup file. 

.PARAMETER WriteLog
    If true, the script will write a log. Helpful during testing. Default value is $false. 

.PARAMETER LogPath
    Path of the log file if parameter -WriteLog $true. The script will create the logfile next to the script if no path specified.

.PARAMETER OutputScriptstate
    If true, the script will output its overall state as an extra object. $true is default. 

.PARAMETER TestMode
    If true, the script will use the value of parameter -OutputTestData to output dummy data objects

.PARAMETER OutputTestData
    Number of dummy test data objects. Helpful to test a monitoring solution without any actual ConfigMgr errors.

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -OutputMode GridView

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -OutputMode GridView -OutputTestData 20

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -OutputMode MonAgentJSON

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -OutputMode HTMLMail

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -WriteLog $true

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -WriteLog $true -LogPath "C:\Temp"

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -TemplateSearchString '*Custom*ConfigMgr*Certificate*' -MinValidDays 30

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
    [string]$TemplateSearchString = '*ConfigMgr*Certificate*',
    [Parameter(Mandatory=$false)]
    [int]$MinValidDays = 30,
    [Parameter(Mandatory=$false)]
    [String]$MailInfotext = 'Status about monitored certificates. This email is sent every day!',
    [Parameter(Mandatory=$false)]
    [bool]$CacheState = $true,
    [Parameter(Mandatory=$false)]
    [string]$CachePath,
    [Parameter(Mandatory=$false)]
    [string]$PrtgLookupFileName,
    [Parameter(Mandatory=$false)]
    [bool]$WriteLog = $false,
    [Parameter(Mandatory=$false)]
    [string]$LogPath,    
    [Parameter(Mandatory=$false)]
    [bool]$OutputScriptstate = $true,
    [Parameter(Mandatory=$false)]
    [bool]$TestMode = $false,
    [Parameter(Mandatory=$false)]
    [ValidateRange(0,60)]
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
                        [string]$shortDescription = $InputObject.Description -replace "\'", "" -replace '>','_' # Remove some chars like quotation marks or >
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

#region prepare template string for "-ilike" and add * if neccesary
if (-NOT($templateSearchString -match '^\*'))
{
    $templateSearchString = '*{0}' -f $templateSearchString
}
if (-NOT($templateSearchString -match '\*$'))
{
    $templateSearchString = '{0}*' -f $templateSearchString  
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

#region main certificate logic
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

#region MAIN logic
$resultObject = New-Object System.Collections.ArrayList
if ($TestMode)
{
    if($WriteLog){Write-CMTraceLog -Message "Will create $OutputTestData test alarms" -Component ($MyInvocation.MyCommand)}
    # create dummy entries
    for ($i = 1; $i -le $OutputTestData; $i++)
    { 
        # create dummy thumbprint
        #$dummyThrumbprint = (-join ((65..73)+(65..73)+(65..73)+(65..73)+(65..73) | Get-Random -Count 40 | ForEach-Object {[char]$_})) -replace 'G|H|I', (Get-Random -Minimum 0 -Maximum 9)
        # A more consistent approach to test data instead of using get-random. Makes troubleshooting easier. 
        $dummyThrumbprint = "F0EEBAD0A0FC0FDAB00A0D0D0C0EEFE00CBCC0FA"
 
        $tmpObj = New-Object psobject | Select-Object $propertyList
        $tmpObj.CheckType = 'DummyData'
        $tmpObj.Name = 'DummyData:{0}:{1}:Dummy{2}' -f $systemName, $dummyThrumbprint, $i.ToString('00')
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
        if($WriteLog){Write-CMTraceLog -Message "Active node found. Let's check DP certificates via SMS Provider" -Component ($MyInvocation.MyCommand)}
        # Active node found. Let's check DP certificates via SMS Provider
        $SMSProviderLocation = Get-WmiObject -Namespace root\sms -Query "SELECT * FROM SMS_ProviderLocation WHERE ProviderForLocalSite = 1" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($SMSProviderLocation)
        {
            [array]$ConfigMgrOSDCertificates = Get-WmiObject -Namespace "root\sms\Site_$($SMSProviderLocation.SiteCode)" -ComputerName ($SMSProviderLocation.Machine) -Query 'SELECT * FROM SMS_Certificate where Type in (1,2) and IsBlocked = 0'
            if ($ConfigMgrOSDCertificates)
            {
                foreach ($OSDCertificate in $ConfigMgrOSDCertificates)
                {
                    if($WriteLog){Write-CMTraceLog -Message ('Checking certificate: {0}' -f ($OSDCertificate.SMSID)) -Component ($MyInvocation.MyCommand)}
                    $expireDays = (New-TimeSpan -Start (Get-Date) -End ([Management.ManagementdateTimeConverter]::ToDateTime($OSDCertificate.ValidUntil))).Days
                    if($WriteLog){Write-CMTraceLog -Message ('Certificate will expire in: {0} days' -f ($expireDays)) -Component ($MyInvocation.MyCommand)}
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
                if($WriteLog){Write-CMTraceLog -Message "No DP or Boot certificate found! Validate user rights and or ConfigMgr site config" -Severity Warning -Component ($MyInvocation.MyCommand)}
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
            $tmpScriptStateObj.Status = 'Error'
            $tmpScriptStateObj.Description = 'Not able to get SMS Provider location from root\sms -> SMS_ProviderLocation'
        }
    }
    else 
    {
        if($WriteLog){Write-CMTraceLog -Message "No active ConfigMgr node found. Will skip in console certfifcate checks" -Component ($MyInvocation.MyCommand)}
    }
 
    # Looking for certificates in personal store of current system if a webserver is installed
    # Format method: https://docs.microsoft.com/en-us/dotnet/api/system.security.cryptography.asnencodeddata.format
    if (Get-Service -Name W3SVC -ErrorAction SilentlyContinue)
    {
        if($WriteLog){Write-CMTraceLog -Message "Found IIS service. Will check IIS certificates" -Component ($MyInvocation.MyCommand)}
        # Let's look at the binding and if there is any certificate attached
        Import-Module -Name WebAdministration -ErrorAction SilentlyContinue            
        if(-NOT (Get-Module -Name WebAdministration))
        {
            if($WriteLog){Write-CMTraceLog -Message "Module WebAdministration could not be loaded. Let's try again" -Component -Severity Warning ($MyInvocation.MyCommand)}
            # it sometimes fails to load. So, let's just wait a bit and try again 
            Start-Sleep -Seconds 5
            Import-Module -Name WebAdministration -ErrorAction SilentlyContinue
        }
 
        # If still not loaded, let's stop
        if(-NOT (Get-Module -Name WebAdministration))
        {
            if($WriteLog){Write-CMTraceLog -Message "Module WebAdministration could not be loaded second try. Not able to proceed!" -Component -Severity Warning ($MyInvocation.MyCommand)}
            $tmpScriptStateObj.Status = 'Error'
            $tmpScriptStateObj.Description = 'Module WebAdministration could not be loaded'
        }
        else 
        {
            $sslWebBindingInfo = Get-WebBinding | Where-Object {$_.Protocol -ieq 'https'}
            if ($sslWebBindingInfo)
            {
                foreach ($sslBinding in $sslWebBindingInfo)
                {
                    if($sslBinding.certificateHash)
                    {
                        if($WriteLog){Write-CMTraceLog -Message ('Checking certificate for port: {0}' -f ($sslBinding.bindingInformation -replace '\*','' -replace ':','')) -Component ($MyInvocation.MyCommand)}
                        $certPath = 'Cert:\LocalMachine\{0}\{1}' -f $sslBinding.certificateStoreName, $sslBinding.certificateHash
                        if($WriteLog){Write-CMTraceLog -Message ('Checking certificate: {0}' -f ($certPath)) -Component ($MyInvocation.MyCommand)}
                        $sslCert = Get-Item $certPath -ErrorAction SilentlyContinue
                        if ($sslCert)
                        {
                            $tmpObj = New-Object psobject | Select-Object $propertyList
                            # Let's check the cert expiration date first
                            $expireDays = (New-TimeSpan -Start (Get-Date) -End ($sslCert.NotAfter)).Days
                            if ($expireDays -le $minValidDays)
                            {              
                                $tmpObj.CheckType = 'Certificate'
                                $tmpObj.Name = '{0}:{1}:{2}' -f $tmpObj.CheckType, $systemName, ($sslCert.Thumbprint)
                                $tmpObj.SystemName = $systemName
                                $tmpObj.Status = 'Warning'
                                $tmpObj.SiteCode = ""
                                $tmpObj.Description = 'Certificate is about to expire in {0} days! Thumbprint:{1}' -f $expireDays, ($sslCert.Thumbprint)
                                $tmpObj.PossibleActions = 'Renew certificate or request a new one'            
                            }
 
                            # check if it is a ConfigMgr managed certificate. Only if not, we will check the template
                            if ($sslCert.Issuer -inotlike '*sms issuing*')
                            {
                                # Let's also check if the cert is coming from the correct template
                                if (-NOT($sslCert.Extensions | Where-Object{ ($_.Oid.FriendlyName -ieq 'Certificate Template Information') -and ($_.Format(0) -ilike $templateSearchString)}))
                                {
                                    $tmpObj.CheckType = 'Certificate'
                                    $tmpObj.Name = '{0}:{1}:{2}' -f $tmpObj.CheckType, $systemName, ($sslCert.Thumbprint)
                                    $tmpObj.SystemName = $systemName
                                    $tmpObj.Status = 'Warning'
                                    $tmpObj.SiteCode = ""
                                    $tmpObj.Description = '{0} WRONG Template' -f $tmpObj.Description # Adding info to the description in case both checks are successful
                                }
                            }
                            else
                            {
                                if($WriteLog){Write-CMTraceLog -Message ('Found ConfigMgr managed certificate for E-HTTP for port: {0}. Will skip check.' -f ($sslBinding.bindingInformation -replace '\*','' -replace ':','')) -Component ($MyInvocation.MyCommand)}
                            }
 
                            
                            if (-NOT([string]::IsNullOrEmpty($tmpObj.Name)))
                            {
                                [void]$resultObject.Add($tmpObj)
                            }
                        }
                        else 
                        {
                            $tmpObj = New-Object psobject | Select-Object $propertyList
                            $tmpObj.CheckType = 'Certificate'
                            $tmpObj.Name = '{0}:{1}:{2}' -f $tmpObj.CheckType, $systemName, $certPath
                            $tmpObj.SystemName = $systemName
                            $tmpObj.Status = 'Error'
                            $tmpObj.SiteCode = ""
                            $tmpObj.Description = "IIS site certificate not found:  $($certPath)"
                            $tmpObj.PossibleActions = 'Add a new cert to IIS'                            
                            [void]$resultObject.Add($tmpObj)
                        }
                    }
                    else 
                    {
                        $tmpObj = New-Object psobject | Select-Object $propertyList
                        $tmpObj.CheckType = 'Certificate'
                        $tmpObj.Name = '{0}:{1}:Port {2}' -f $tmpObj.CheckType, $systemName, ($sslBinding.bindingInformation -replace '\*','' -replace ':','')
                        $tmpObj.SystemName = $systemName
                        $tmpObj.Status = 'Warning'
                        $tmpObj.SiteCode = ""
                        $tmpObj.Description = 'No certificate bound to port: {0}' -f ($sslBinding.bindingInformation -replace '\*','' -replace ':','')
                        $tmpObj.PossibleActions = 'Add a new cert to IIS'                            
                        [void]$resultObject.Add($tmpObj)
                    }
                }
            }
            else 
            {
                $tmpScriptStateObj.Status = 'Warning'
                $tmpScriptStateObj.Description = 'No SSL bindings found in IIS'
            }
        }
    }
    else 
    {
        #$tmpScriptStateObj.Status = 'Warning'
        #$tmpScriptStateObj.Description = 'NO IIS service found. Will NOT check IIS certificates'
        if($WriteLog){Write-CMTraceLog -Message "NO IIS service found. Will NOT check IIS certificates" -Component ($MyInvocation.MyCommand)}
    }
}
#endregion
 
 
# Adding overall script state to list
if ($OutputScriptstate)
{
    [void]$resultObject.Add($tmpScriptStateObj)
}
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
if($WriteLog){Write-CMTraceLog -Message "OutputMode: $OutputMode" -Component ($MyInvocation.MyCommand)}
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
        $resultObject | ConvertTo-CustomMonitoringObject -OutputType PrtgObject -PrtgLookupFileName $PrtgLookupFileName | ConvertTo-Json -Depth 3
    }
    "JSON"
    {
        $resultObject | ConvertTo-Json -Depth 5
    }
}
if($WriteLog){Write-CMTraceLog -Message "End of script" -Component ($MyInvocation.MyCommand)}
#endregion 

