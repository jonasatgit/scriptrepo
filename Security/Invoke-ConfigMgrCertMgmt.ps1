<#
.Synopsis
    Script to enroll a certificate for ConfigMgr in the custom store "ConfigMgr" in the local machine certificate store.
    
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

    Script to enroll a certificate for ConfigMgr in the custom store "ConfigMgr" in the local machine certificate store.
    The script checks if the custom store exists, if not it creates it. 
    Then it checks if there are any certificates in the store. If there are no certificates, it requests a new certificate using the specified template. 
    If there are certificates, it checks if any of them are expired or will expire within 90 days. 
    If so, it requests a new certificate. If the certificate is valid, it does nothing.
    The script also logs events to the Windows Event Log for each action taken.
    Possible event types and IDs are:
    - StartScript (1000)
    - CreateStore (1001)
    - RequestCertificate (1002)
    - CertificateExpired (1003)
    - NoActionNeeded (1004)
    - Error (1005)
    - EndScript (1006)

    The script can be run with the following parameters:

.PARAMETER TemplateSeachString
    The template name to search for. The default value is "Workstation Authentication v2".
    This parameter is used to find the certificate template to use for the certificate request.

.PARAMETER MaxExpirationDays
    The maximum number of days before expiration to check for. The default value is 90 days.
    This parameter is used to determine if a certificate is expired or will expire soon.

.PARAMETER CertificateEnrollmentUrl
    The URL for the certificate enrollment service. If not specified, the script will use the default enrollment service.
    This parameter is used to specify a custom enrollment service if needed.

#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $false)]
    [string]$TemplateSeachString = "Workstation Authentication v2",

    [Parameter(Mandatory = $false)]
    [int]$MaxExpirationDays = 90,

    [Parameter(Mandatory = $false)]
    [string]$CertificateEnrollmentUrl
)


#region Function New-ConfigMgrCertificateEvent
Function New-ConfigMgrCertificateEvent
{
    param
    (

        [Parameter(Mandatory = $True)]
        [ValidateSet("StartScript", "EndScript", "CreateStore", "RequestCertificate", "CertificateExpired", "NoActionNeeded", "Error")]
        [string]$EventType,

        [Parameter(Mandatory = $false)]
        [string]$EventMessage = "No message provided",

        [Parameter(Mandatory = $false)]
        [string]$EventLog = "Application",

        [Parameter(Mandatory = $false)]
        [string]$EventSource = "ConfigMgrCertMgmt"
    )

    Switch ($EventType)
    {
        "StartScript" 
        {
            $eventID = 1000
            $entryType = "Information"
        }
        "CreateStore" 
        {
            $eventID = 1001
            $entryType = "Information"
        }
        "RequestCertificate" 
        {
            $eventID = 1002
            $entryType = "Information"
        }
        "CertificateExpired" 
        {
            $eventID = 1003
            $entryType = "Warning"
        }
        "NoActionNeeded" 
        {
            $eventID = 1004
            $entryType = "Information"
        }
        "Error" 
        {
            $eventID = 1005
            $entryType = "Error"
        }
        "EndScript"
        {
            $eventID = 1006
            $entryType = "Information"
        }
    }

    # validate if eventsource exists
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) 
    {
        [System.Diagnostics.EventLog]::CreateEventSource($EventSource, $EventLog)
    }
    
    Write-EventLog -LogName $EventLog -Source $EventSource -EventID $eventID -EntryType $entryType -Message $EventMessage

}
#endregion

#region New-ConfigMgrCertificateRequest
Function New-ConfigMgrCertificateRequest
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$TemplateSeachString,

        [Parameter(Mandatory = $false)]
        [string]$CertificateEnrollmentUrl
    )

    $templateSeachStringWithoutSpaces = $TemplateSeachString -replace '\s'
    
    try 
    {
        if ([string]::IsNullOrEmpty($CertificateEnrollmentUrl))
        {
            $paramsplatting = @{
                Template = $templateSeachStringWithoutSpaces
                CertStoreLocation = "Cert:\LocalMachine\My"
                ErrorAction = "Stop"
            }
        }
        else 
        {
            $paramsplatting = @{
                Template = $templateSeachStringWithoutSpaces
                CertStoreLocation = "Cert:\LocalMachine\My"
                Url = $CertificateEnrollmentUrl
                ErrorAction = "Stop"
            }           
        }

        $newCertificate = Get-Certificate @paramsplatting

        $personalStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
        $personalStore.Open("ReadWrite")

        $newCertificateObj = $personalStore.Certificates | Where-Object{ ($_.Thumbprint -eq $newCertificate.Certificate.Thumbprint)}

        $customStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("ConfigMgr", "LocalMachine")
        $customStore.Open("ReadWrite")
 
        # Add the certificate to the custom store
        $customStore.Add($newCertificateObj)
 
        # Remove the certificate from the "Personal" store
        $personalStore.Remove($newCertificateObj)
 
        # Close the custom store
        $customStore.Close()
        $personalStore.Close()

    }
    catch 
    {
        New-ConfigMgrCertificateEvent -EventType "Error" -EventMessage "Error requesting certificate: $_"
    }   
}
#endregion


#region Main script logic
New-ConfigMgrCertificateEvent -EventType "StartScript" -EventMessage "Script stated"

# We need a custom store for ConfigMgr certificates 
if (-not (Test-path Cert:\LocalMachine\ConfigMgr))
{ 
    $Null = New-Item -Path Cert:\LocalMachine -Name "ConfigMgr" -ItemType Directory
    New-ConfigMgrCertificateEvent -EventType "CreateStore" -EventMessage "Custom store ConfigMgr created"
}

# Get existing certificates in the custom store if any 
[array]$certificates = Get-ChildItem Cert:\LocalMachine\ConfigMgr

$needToRequestNewCert = $true
if ($certificates.count -eq 0)
{
    $needToRequestNewCert = $true
}
else 
{
    foreach ($certificate in $certificates)
    {
        # check expiration date
        $expirationDate = $certificate.NotAfter
        $currentDate = Get-Date

        if ($expirationDate -lt ($currentDate.AddDays($MaxExpirationDays)))
        {
            # request new cert
            $certExpireDateTime = $expirationDate.ToString("yyyy-MM-dd HH:mm:ss")
            New-ConfigMgrCertificateEvent -EventType "CertificateExpired" -EventMessage "Certificate will or is expired: $certExpireDateTime"
        }
        else 
        {
            New-ConfigMgrCertificateEvent -EventType "NoActionNeeded" -EventMessage "Certificate is valid, no action needed"
            $needToRequestNewCert = $false
        }
    }
}

if($needToRequestNewCert -eq $true)
{
    # request new cert
    New-ConfigMgrCertificateEvent -EventType "RequestCertificate" -EventMessage "Requesting new certificate"
    New-ConfigMgrCertificateRequest -TemplateSeachString $TemplateSeachString -CertificateEnrollmentUrl $CertificateEnrollmentUrl
}

New-ConfigMgrCertificateEvent -EventType EndScript -EventMessage "Script finished"
#endregion

