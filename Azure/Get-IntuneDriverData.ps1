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
<#
.Synopsis
    Script to get devices and drivers from Windows Update Deployment Servive
    
.DESCRIPTION
    Script to get devices and drivers from Windows Update Deployment Servive
    Source: https://github.com/jonasatgit/scriptrepo

.PARAMETER UseProxyForModuleInstall
    Use proxy to connect to internet for module installation. If not specified, no proxy is used.

.PARAMETER ProxyAddress
    Proxy address to use with the port seperated by : (e.g. proxy.contoso.com:8080)

.PARAMETER ProxyCredential
    If proxy requires authentication, use this parameter to provide credentials get by Get-Credential.

.PARAMETER ClienID
    Entrada ClientID to use for authentication. If not specified, the script will use the default client ID of Microsoft Graph Powershell

.PARAMETER TenantID
    Entrada TenantID to use for authentication.

.EXAMPLE
    

.INPUTS
   

.OUTPUTS
    Out-GridView with all drivers and corresponding devices
    
#>

param
(
    [CmdletBinding()]
    [Parameter(Mandatory = $false)]
    [switch]$UseProxyForModuleInstall,
    [Parameter(Mandatory = $false, ParameterSetName = 'Proxy')]
    [string]$ProxyAddress,
    [Parameter(Mandatory = $false, ParameterSetName = 'Proxy')]
    [pscredential]$ProxyCredential,
    [Parameter(Mandatory = $false, ParameterSetName = 'App')]
    [string]$ClientID,
    [Parameter(Mandatory = $true, ParameterSetName = 'App')]
    [string]$TenantID
)


[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

#region variables
$graphApiVersion = "beta"

# List of modules to install
$listOfRequiredModules = [ordered]@{
    'Microsoft.Graph.Authentication' = '2.5.0' }

# Always use all possible scopes to hide actual rights from to the lab user
$listOfRequiredScopes = (
        'DeviceManagementManagedDevices.Read.All',
        'WindowsUpdates.ReadWrite.All'
        )
#endregion variables


#region Import nuget before anyting else
[version]$minimumVersion = '2.8.5.201'
$nuget = Get-PackageProvider -ErrorAction Ignore | Where-Object {$_.Name -ieq 'nuget'} # not using -name parameter du to autoinstall question
if (-Not($nuget))
{
    # Changed to MSI installer as the old way could not be enforced and needs to be approved by the user
    # Install-PackageProvider -Name NuGet -MinimumVersion $minimumVersion -Force 
    if ($UseProxyForModuleInstall)
    {
        if ($ProxyCredential)
        {
            Write-Host 'Need to install NuGet provider first with proxy and credential' -ForegroundColor Green
            $null = Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies -MinimumVersion $minimumVersion -Force -Proxy $ProxyAddress -ProxyCredential $ProxyCredential
        }
        else 
        {
            Write-Host 'Need to install NuGet provider first with proxy' -ForegroundColor Green
            $null = Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies -MinimumVersion $minimumVersion -Force -Proxy $ProxyAddress
        }                
    }
    else 
    {
        Write-Host 'Need to install NuGet provider first' -ForegroundColor Green
        $null = Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies -MinimumVersion $minimumVersion -Force
    }
}


# Install and or import modules 
$listOfInstalledModules = Get-InstalledModule -ErrorAction SilentlyContinue
foreach ($module in $listOfRequiredModules.GetEnumerator())
{   
    if (-NOT($listOfInstalledModules | Where-Object {$_.Name -ieq $module.Name}))    
    {        
        #Write-Host "Module $($module.Name) not installed yet. Will be installed"
        if (-NOT([string]::IsNullOrEmpty($module.Value)))
        {
            if ($UseProxyForModuleInstall)
            {
                if ($ProxyCredential)
                {
                    Write-Host "Need to install module $($module.Value) first with proxy and proxy credentials" -ForegroundColor Green
                    Install-Module $module.Name -Force -RequiredVersion $module.Value -Proxy $ProxyAddress -ProxyCredential $ProxyCredential
                }
                else 
                {
                    Write-Host "Need to install module $($module.Value) first with proxy" -ForegroundColor Green
                    Install-Module $module.Name -Force -RequiredVersion $module.Value -Proxy $ProxyAddress
                }                
            }
            else 
            {
                Write-Host "Need to install module $($module.Value) first" -ForegroundColor Green
                Install-Module $module.Name -Force -RequiredVersion $module.Value
            }
        }
        else 
        {
            Write-Host "Need to install module $($module.Value) first" -ForegroundColor Green
            Install-Module $module.Name -Force
        }               
    }     
}

if ($ClientID)
{
    Write-Host "Connect to MIcrosoft Graph with own client ID" -ForegroundColor Green
    Connect-MgGraph -ClientId $ClientID -TenantId $TenantID -Scopes $listOfRequiredScopes
}
else 
{
    Write-Host "Connect to MIcrosoft Graph" -ForegroundColor Green
    Connect-MgGraph -Scopes $listOfRequiredScopes
}

if (-NOT (Get-MgContext))
{
    Write-Host 'No Graph connection. Exit script' -ForegroundColor Green
    Exit 0
}
else 
{
    Write-Host 'Current Graph context:' -ForegroundColor Green
    Get-MgContext
}

# get all Intune devices, but limit output to the azureADDeviceID and the name to be able to generate hashtable for lookup
# ONLY top 999 devices are returned, so if you have more than 999 devices, you need to change the $top parameter or use paging
Write-Host "Getting azureADDeviceId and deviceName of all managed Intune devices" -ForegroundColor Green
$uri = 'https://graph.microsoft.com/{0}/deviceManagement/managedDevices?$select=azureADDeviceId,deviceName&$top=999' -f $graphApiVersion
$managedDevices = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType psobject
$deviceLookupTable = @{}
$managedDevices.value | ForEach-Object {
    $deviceLookupTable.Add($_.azureADDeviceId, $_.deviceName)
}

if (-NOT ([string]::IsNullOrEmpty($managedDevices.'@odata.nextLink')))
{
    do
    {
        $uri = $managedDevices.'@odata.nextLink'
        $managedDevices = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType psobject
        $managedDevices.value | ForEach-Object {
            $deviceLookupTable.Add($_.azureADDeviceId, $_.deviceName)
        }          
    }
    until ([string]::IsNullOrEmpty($managedDevices.'@odata.nextLink'))
}

# create empty arraylist to store output
$out = New-Object System.Collections.ArrayList

# get all deployment audiences
Write-Host "Getting updates deployment service deploymentaudiences" -ForegroundColor Green
$uri = 'https://graph.microsoft.com/{0}/admin/windows/updates/deploymentaudiences' -f $graphApiVersion
$updatesDeploymentaudiences = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject

# loop through all deployment audiences and get applicable content if any available
Write-Host "Getting applicableContent of deploymentaudiences" -ForegroundColor Green
$updatesDeploymentaudiences.value | ForEach-Object {
    $uri = 'https://graph.microsoft.com/{0}/admin/windows/updates/deploymentaudiences/{1}/applicableContent' -f $graphApiVersion, $_.id 
    $audienceID = $_.id
    $applicableContent = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject
    if($applicableContent.value)
    {
        Write-Host "Getting applicableContent of audience with ID $audienceID" -ForegroundColor Green
        foreach($item in $applicableContent.value)
        {
            $tmpObj = [PSCustomObject]@{
                AudienceID = $audienceID
                DeviceID = $item.matchedDevices.deviceId
                DeviceName = $deviceLookupTable[($item.matchedDevices.deviceId)]
                DriverDsiplayName = $item.catalogEntry.displayName
                DriverVersion = $item.catalogEntry.version
                DriverReleaseDate = $item.catalogEntry.releaseDateTime
                DriverManufacturer = $item.catalogEntry.manufacturer
                #DriverObject = $item.catalogEntry | Select-Object -ExcludeProperty '@odata.type'
            }
            [void]$out.Add($tmpObj)
        }       
    }
}

$out | Out-GridView -Title 'Driverlist'



