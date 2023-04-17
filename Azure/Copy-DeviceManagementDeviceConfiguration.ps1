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

# This is an example on how to copy and change an Intune device configuration profile uning Microsoft Graph PowerShell

# List of required modules to be installed and loaded
$listOfRequiredModules = ('PowerShellGet','Microsoft.Graph.Authentication','Microsoft.Graph.DeviceManagement','Microsoft.Graph.Beta.DeviceManagement')

#region Install and or import modules
#Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
foreach ($module in $listOfRequiredModules)
{
    if (-NOT(Get-InstalledModule $module -ErrorAction SilentlyContinue))
    {
        Write-Host "Module $module not found. Will be installed!" -ForegroundColor Green
        Install-Module -Name $module -Force -AllowClobber
    }

    if (-NOT(Get-Module $module))
    {
        Write-Host "Module $module not imported yet. Will be imported!" -ForegroundColor Green
        Import-Module -Name $module -Force
    }
}
#endregion


break
# Connect to graph with scope "DeviceManagementConfiguration.ReadWrite.All"
Connect-MgGraph -Scopes 'DeviceManagementConfiguration.ReadWrite.All'

# Output of current context. Logged on user, scopes and token credential type for example
# Just an example, not required for the script logic
# Might help to identify test or production environments
Get-MgContext

# Get a list of all configuration profiles but limited to the id and displayname
Get-MgDeviceManagementDeviceConfiguration -All -Property Id, displayName -Debug
#Get-MgBetaDeviceManagementDeviceConfiguration -All -Property Id, displayName -Debug # requires Microsoft.Graph.Beta.DeviceManagement module

# Get a specific configuration profile
$configProfile = Get-MgDeviceManagementDeviceConfiguration -DeviceConfigurationId '{b618da5e-0d06-4f92-b957-0c282c185a3d}'

# Get a list of available properties and types
$configProfile | Get-Member

# Get the full list of properties and values
$configProfile | Format-List *

# Change a value of a custom OMA URI setting
$configProfile.AdditionalProperties.omaSettings[0].value = 1

# Create a copy of the configuration profile with a new name and the previously changed setting
New-MgDeviceManagementDeviceConfiguration -DisplayName 'TEST Configuration Policy 01' -AdditionalProperties $configProfile.AdditionalProperties

# Sign out
Disconnect-MgGraph