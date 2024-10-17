<#
.SYNOPSIS
Script to remove duplicate devices from Intune and EntraID

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
# 
#************************************************************************************************************
#>

param
(
    [Parameter(Mandatory=$false)]
    [int]$DaysSinceRegistration = 2,
    [Parameter(Mandatory=$false)]
    [string]$DeviceNamePrefix = "DESKTOP",
    [Parameter(Mandatory=$false)]
    [string]$EntraIDAppID,
    [Parameter(Mandatory=$false)]
    [string]$EntraIDTenantID
)

#region check for required modules
function Get-RequiredScriptModules 
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$RequiredModules
    )

    $moduleNotFound = $false
    foreach ($requiredModule in $requiredModules)
    {
        try 
        {
            Import-Module -Name $requiredModule -ErrorAction Stop    
        }
        catch 
        {
            $moduleNotFound = $true
        }
    }

    try 
    {
        if ($moduleNotFound)
        {
            # We might need nuget to install the module
            [version]$minimumVersion = '2.8.5.201'
            $nuget = Get-PackageProvider -ErrorAction Ignore | Where-Object {$_.Name -ieq 'nuget'} 
            if (-Not($nuget))
            {   
                Write-Output "Need to install NuGet to be able to install $($requiredModule)" 
                # Changed to MSI installer as the old way could not be enforced and needs to be approved by the user
                # Install-PackageProvider -Name NuGet -MinimumVersion $minimumVersion -Force
                $null = Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies -MinimumVersion $minimumVersion -Force
            }

            foreach ($requiredModule in $RequiredModules)
            {
                if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
                {
                    Write-Output "No admin permissions. Will install $($requiredModule) for current user only" 
                    
                    $paramSplatting = @{
                        Name = $requiredModule
                        Force = $true
                        Scope = 'CurrentUser'
                        Repository = 'PSGallery'
                        ErrorAction = 'Stop'
                    }
                    Install-Module @paramSplatting
                }
                else 
                {
                    Write-Output "Admin permissions. Will install $($requiredModule) for all users" 

                    $paramSplatting = @{
                        Name = $requiredModule
                        Force = $true
                        Repository = 'PSGallery'
                        ErrorAction = 'Stop'
                    }

                    Install-Module @paramSplatting
                }   

                Import-Module $requiredModule -Force -ErrorAction Stop
            }
        }    
    }
    catch 
    {
        Write-Output "failed to install or load module" 
        Write-Output "$($_)" -ForegroundColor Red
        Break
    }
}

#region datetime conversion
# Get the current date and time
$currentDateTime = Get-Date

# Subtract the specified number of days
$targetDateTime = $currentDateTime.AddDays(-$DaysSinceRegistration)

# Convert the result to UTC
$utcDateTime = $targetDateTime.ToUniversalTime()

# Format the result in ISO 8601 format with 'Z' to indicate UTC
$iso8601DateTimeSinceRegistration = $utcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")

# Output the result
Write-Output $iso8601DateTimeSinceRegistration
#endregion


# Call the function to ensure required modules are installed
Get-RequiredScriptModules -RequiredModules @('Microsoft.Graph.Identity.DirectoryManagement','Microsoft.Graph.Beta.DeviceManagement') #'Microsoft.Graph.Authentication',


#region Connect to Graph
if ([string]::IsNullOrEmpty($EntraIDAppID))
{
    Connect-MgGraph -Scopes "Device.ReadWrite.All", "DeviceManagementManagedDevices.ReadWrite.All"
}
else
{
    Connect-MgGraph -Scopes "Device.ReadWrite.All", "DeviceManagementManagedDevices.ReadWrite.All" -ClientId $EntraIDAppID -TenantId $EntraIDTenantID
}
#endregion
# Connect to Graph


#$uri = "https://graph.microsoft.com/v1.0/devices?`$filter=registrationDateTime ge 2024-10-15T00:00:00Z and operatingsystem eq 'windows' and startswith(displayName, 'DESKTOP')&`$select=id,deviceId,displayName,deviceOwnership,managementType,trustType&`$count=true"

$graphFilter = "registrationDateTime ge {0} and operatingsystem eq 'windows' and startswith(displayName, '{1}')" -f $iso8601DateTimeSinceRegistration, $DeviceNamePrefix
$graphProperties = "id,deviceId,displayName,deviceOwnership,managementType,trustType"

<#
# Direct graph call method without extra module other than Microsoft.Graph.Authentication
$graphBaseUri = "https://graph.microsoft.com/v1.0/devices"
$graphUri = '{0}?$filter={1}&$select={2}&$count=true' -f $graphBaseUri, $graphFilter, $graphProperties
$retVal = Invoke-MgGraphRequest -Method Get -Uri $graphUri -Headers @{ ConsistencyLevel = "eventual"}
$graphDevices = $retVal.value
#>

$params = @{
    Filter = $graphFilter
    Property = $graphProperties
    All = $true
    ConsistencyLevel = "eventual"
    CountVariable = 'DeviceCountVariable'
}

$enrolledDevices = Get-MgDevice @params
Write-Output "Total devices found with filter: $($global:DeviceCountVariable)"

# We now need another graph call forach each enrolled device to test if we have multiple devices with the same name

foreach($device in $enrolledDevices)
{
    $deviceGraphFilter = "displayName eq '$($device.displayName)'"

    $params = @{
        Filter = $deviceGraphFilter
        Property = $graphProperties
        All = $true
        ConsistencyLevel = "eventual"
        CountVariable = 'SingleDeviceCountVariable'
    }

    $deviceRetval = Get-MgDevice @params

    if($global:SingleDeviceCountVariable -gt 1)
    {
        Write-Output "Found $($global:SingleDeviceCountVariable) with the same name: `"$($device.displayName)`". Need to remove duplicates"
        # Remove duplicates by removing any older devices. Always keep the newest device.

        $intuneProperties = "Id,deviceName,AzureAdDeviceId,LastSyncDateTime,SerialNumber,OwnerType,ManagementCertificateExpirationDate"
        [array]$intuneDevices = Get-MgBetaDeviceManagementManagedDevice -Filter "deviceName eq '$($device.displayName)'" -Property $intuneProperties
        Write-Output "Found $($intuneDevices.Count) devices in Intune with the same name: `"$($device.displayName)`""

        # Sort the devices by registrationDateTime
        $sortedDevices = $deviceRetval | Sort-Object -Property registrationDateTime -Descending

        # Remove the first device from the list as it is the newest device
        $sortedDevices = $sortedDevices | Select-Object -Skip 1

        foreach($deviceToRemove in $sortedDevices)
        {
            Write-Output "Removing device: $($deviceToRemove.Id) with name: $($deviceToRemove.displayName)"
            # Remove the device
            #Remove-MgDevice -DeviceId $deviceToRemove.deviceId
        }
    }
    elseif ($global:SingleDeviceCountVariable -eq 1) 
    {
        Write-Output "All good. Found just one entry for: `"$($device.displayName)`""
    }
    else 
    {
        Write-Output "Found $($global:SingleDeviceCountVariable) with the same name: `"$($device.displayName)`""   
    }  

}

