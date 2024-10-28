<#
.SYNOPSIS
    This script sets the EnableRbacReporting property on the SMS_SCI_SysResUse object for the SMS SRS Reporting Point. 
    To either enable or disable RBAC in ConfigMgr reporting.

.DESCRIPTION
    This script sets the EnableRbacReporting property on the SMS_SCI_SysResUse object for the SMS SRS Reporting Point. 
    To either enable or disable RBAC in ConfigMgr reporting.
    Use the EnableRbacReporting parameter to set the value. 0 means RBAC is off in reporting, 1 means RBAC is on.
    On is the default value for any ConfigMgr Reporting Service Point.

    NOTE: The script is not made for more than one Reporting Service Point.
    NOTE: The script needs to be run on a server with the ConfigMgr console installed to be able to use the ConfigurationManager.psd1 module.

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
    # 
    #************************************************************************************************************

.PARAMETER EnableRbacReporting
    The EnableRbacReporting parameter is used to set the EnableRbacReporting property on the SMS_SCI_SysResUse object for the SMS SRS Reporting Point. 
    To either enable or disable RBAC in ConfigMgr reporting.
    Use the EnableRbacReporting parameter to set the value. 0 means RBAC is off in reporting, 1 means RBAC is on.
    On is the default value for any ConfigMgr Reporting Service Point.

.PARAMETER SiteCode
    The SiteCode parameter is used to specify the site code of the ConfigMgr site.

.PARAMETER ProviderMachineName
    The ProviderMachineName parameter is used to specify the machine name of the ConfigMgr SMS Provider server.

#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $false)]
    [int]$EnableRbacReporting = 0, # 0 means RBAC is off in reporting, 1 means RBAC is on
    [Parameter(Mandatory = $true)]
    [string]$SiteCode,
    [Parameter(Mandatory = $true)]
    [string]$ProviderMachineName
)

# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Do not change anything below this line

# Import the ConfigurationManager.psd1 module 
if( $null -eq (Get-Module ConfigurationManager)) 
{
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if($null -eq (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) 
{
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams

# Get reporting point object
[array]$SMSSrp = Invoke-CMWmiQuery -Query  "Select * From SMS_SCI_SysResUse Where SiteCode='$($SiteCode)' and RoleName='SMS SRS Reporting Point'"

if ($null -eq $SMSSrp)
{
    Write-Warning "SMS_SCI_SysResUse object for SMS SRS Reporting Point not found. Script ending."
    return
}

if ($SMSSrp.Count -gt 1)
{
    Write-Warning "Multiple SMS_SCI_SysResUse objects found for SMS SRS Reporting Point. Script is not made for for than one Reporting Service Point. Script ending."
    return
}

# Set the EnableRbacReporting property
Write-Host "Setting EnableRbacReporting to $EnableRbacReporting"

$SMSSrpEmbeddedProperties = $SMSSrp.EmbeddedProperties
$SMSSrpEmbeddedProperties["EnableRbacReporting"].Value2 = $EnableRbacReporting
$SMSSrp.EmbeddedProperties = $SMSSrpEmbeddedProperties
$SMSSrp.Put()

Write-Host "Script completed."