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
    Script to monitor ConfigMgr related certificates based on a specific template name
    Version: 2022-04-06
    
.DESCRIPTION
    Script to monitor ConfigMgr related certificates based on a specific template name
    Source: https://github.com/jonasatgit/scriptrepo

.PARAMETER GridViewOutput
    Switch parameter to be able to output the results in a GridView instead of compressed JSON

.PARAMETER TemplateSearchString
    String to search for a certificate based on a specific template name
    Valid template names are:
        '*Custom-ConfigMgrDPCertificate*'
        '*Custom-ConfigMgrIISCertificate*'
        '*Custom-Test-ConfigMgrDPCertificate*'
        '*Custom-Test-ConfigMgrIISCertificate*'
        OR
        '*Custom*ConfigMgr*Certificate*' to include all possible values

.PARAMETER MinValidDays
    Value in days before certificate expiration

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -GridViewOutput

.EXAMPLE
    Get-ConfigMgrCertificateState.ps1 -TemplateSearchString '*Custom*ConfigMgr*Certificate*' -MinValidDays 60

.INPUTS
   None

.OUTPUTS
   Compressed JSON string or grid view
    
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [Switch]$GridViewOutput,
    [Parameter(Mandatory=$false)]
    [string]$TemplateSearchString = '*Custom*ConfigMgr*Certificate*',
    [Parameter(Mandatory=$false)]
    [int]$MinValidDays = 30
)

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

# Format method: https://docs.microsoft.com/en-us/dotnet/api/system.security.cryptography.asnencodeddata.format
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
