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
    Example script to set the Autopilot group tag for a device based on its serial number.
    
.DESCRIPTION
    Example script to set the Autopilot group tag for a device based on its serial number.
    Can be used in PowerShell or Azure Automation Runbook
    Source: https://github.com/jonasatgit/scriptrepo
   
    Set the Autopilot group tag for a device based on its serial number

    The script requires the system managed identity of the Intune Automation Account
    to be active. The managed identity also needs to have the correct permissions set.
    In this case the high privilege permission DeviceManagementServiceConfig.ReadWrite.All is required.
    Further security considerations should be taken into account when using high privilege permissions.

    # IMPORTANT: This script currently does not contain any error handling or logging mechanisms

.PARAMETER SerialNumber
    The serial number of the device.

.PARAMETER OperationModel
    The operation model of the device.

.PARAMETER Purpose
    The purpose of the device.

.PARAMETER BusinessUnit
    The business unit the device belongs to.

.PARAMETER DeploymentMode
    The deployment mode of the device.

.PARAMETER BundleID
    The bundle ID associated with the device.
    
.PARAMETER OrderID
    The order ID associated with the device.
#>

param
(
    [Parameter(Mandatory = $true)]
    [string]$SerialNumber,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("ONE")]
    [string]$OperationModel,

    [Parameter(Mandatory = $true)]
    [ValidateSet("FDN")]
    [string]$Purpose,

    [Parameter(Mandatory = $true)]
    [ValidateSet("ABC","DEF","GHI")]
    [string]$BusinessUnit,

    [Parameter(Mandatory = $true)]
    [ValidateSet("SU","MU")]
    [string]$DeploymentMode,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Bundle001")]
    [string]$BundleID,

    [Parameter(Mandatory = $true)]
    [ValidateSet("12345")]
    [string]$OrderID
)

# We will construct the group tag string based on the provided parameters
# Each parameter has a validate set, to make sure only valid values are used when constructing the group tag
# Those values could also be stored as separate variables in an Automation Account to make them easier to update and manage without modifying the script directly.
$groupTag = "$OperationModel,$Purpose,$BusinessUnit,$DeploymentMode,$BundleID,$OrderID"

# Reading the valid BusinessUnit list from the parameter attributes used by ValidateSet
# This is just a way to dynamically retrieve the valid values for the BusinessUnit parameter from its ValidateSet attribute
# This allows us to use the list of valid BusinessUnit values later in the script for validation purposes and not create a second hardcoded list.
$validBusinessUnitList = $MyInvocation.MyCommand.Parameters['BusinessUnit'].Attributes | 
    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
        Select-Object -ExpandProperty validValues

# Connect to Microsoft Graph with the current managed identity
Connect-MgGraph -identity

# We will filter the Autopilot devices by the provided serial number
# The Intune/Autopilot backend only supports filtering by serial number using the 'contains' function
# To ensure we have the correct device and not a partial match and possibly multiple results, we will add an additional check after retrieving the devices.
$uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$top=10&`$filter=contains(serialNumber,'$SerialNumber')"
$graphDevice = Invoke-MgGraphRequest -Method Get -Uri $uri

# This is the second check to ensure we have the correct device by matching the exact serial number and not relying solely on the 'contains' filter
$deviceObj = $graphDevice.value | Where-Object { $_.serialNumber -ieq $SerialNumber } 

# We will split the existing group tag string into its individual components for further validation
$groupTagMandantString = $deviceObj.groupTag -split ','

# We will now check if the existing group tag is either empty or has a valid BusinessUnit component before updating it.
# Meaning the group tag will be updated if it is currently empty or if the existing BusinessUnit component has a known valid value.
# If the condition is met, we will proceed to update the group tag with the new values.
if (([string]::IsNullOrEmpty($deviceObj.groupTag)) -or ($validBusinessUnitList -icontains $groupTagMandantString[2]))
{
    # We only need to provide the updated group tag in the request body
    $body = @{
        "groupTag" = "$groupTag"
    } 

    # Sending the body with the updated group tag to the updateDeviceProperties endpoint of the Intune Autopilot service
    $updateDevicePropertiesUri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($deviceObj.id)/updateDeviceProperties"
    Invoke-MgGraphRequest -Method Post -Uri $updateDevicePropertiesUri -Body $body -ContentType "application/json"
}

