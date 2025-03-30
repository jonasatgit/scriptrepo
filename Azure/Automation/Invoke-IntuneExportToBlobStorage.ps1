<# 
.SYNOPSIS
    Script to export data from Intune and upload it to a Storage Account.

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

    This script will export data from Intune using Microsoft Graph API and upload it to an Azure Storage Account.
    The script will create a new container in the storage account if it does not exist.
    The script will use the Managed Identity to connect to Microsoft Graph and Azure Storage if it is run in an Azure Automation environment.
    The following permissions are required:
    - Microsoft Graph: DeviceManagementManagedDevices.Read.All
    - Azure Storage: Storage Blob Data Contributor

    The script is a sample and should be modified to fit your needs.

.PARAMETER StorageAccountName
    The name of the Azure Storage account where the file will be uploaded. Default is 'intunefiles0123'.

.PARAMETER ContainerName
    The name of the Azure Storage container where the file will be uploaded. Default is 'intuneexport'.

#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName = 'intunefiles',

    [Parameter(Mandatory = $false)]
    [string]$ContainerName = 'intuneexport'
)

# Making sure the storage account name and container name are lowercase
$storageAccountName = $storageAccountName.ToLower()
$containerName = $containerName.ToLower()

# Check if we are in an Azure Automation environment
# If we are, we will use the Managed Identity to connect to Microsoft Graph and Azure Storage
[bool]$inAzureAutomationEnvironment = if (Get-Command -Name Get-AutomationVariable -ErrorAction SilentlyContinue){$true}else{$false}
if ($inAzureAutomationEnvironment)
{
    Connect-MgGraph -Identity
    Connect-AzAccount -Identity
}
else
{
    Install-Module Az.Accounts
    Install-Module Az.Storage

    Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All"
    Connect-AzAccount
}

# Getting data from Intune using Microsoft Graph API
$devicesUri = 'https://graph.microsoft.com/beta/deviceManagement/managedDevices?$select=id,azureADDeviceId,deviceName,complianceState'
$deviceResult = Invoke-MgGraphRequest -Uri $devicesUri -Method Get -OutputType Json
# Using output type json to be able to convert the result to a JSON object with a depth of 10 and not just 1
$deviceResultObject = $deviceResult | ConvertFrom-Json -Depth 10

# Export the result to a temp CSV file. We will delete it later
$csvFullName = "{0}\Devices.csv" -f $env:TEMP
$deviceResultObject.value | Export-Csv -Path $csvFullName -NoTypeInformation -Force -Encoding UTF8

# Create a new storage account context using the storage account name and the connected account
# The context will contain metadata about the storage account and is requiored for most operations
$storageAccountContext = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount

# We will use the storage account context to create a new container in the storage account if it does not exist
$container = $null
$container = Get-AzStorageContainer -Context $storageAccountContext -Name $containerName 
if ($null -eq $container) 
{
    Write-Host "Creating container: $containerName"
    $container = New-AzStorageContainer -Context $storageAccountContext -Name $containerName -ErrorAction Stop
}
else 
{
    Write-Host "Container already exists: $containerName"
}

# Create hash table with parameters for the Set-AzStorageBlobContent cmdlet
# The hash table will be used to pass the parameters to the cmdlet
$paramPlatting = @{
    Container = $containerName
    File = $csvFullName # Path to the file to be uploaded
    Context = $storageAccountContext
    Blob = ($csvFullName | Split-Path -Leaf) # Name of the file to be uploaded
    StandardBlobTier = 'Hot'
}

# Role "Storage Blob Data Contributor" is needed to upload files to the container
Set-AzStorageBlobContent @paramPlatting

# Delete the temp file
Remove-Item -Path $csvFullName -Force -ErrorAction SilentlyContinue




















$files = Get-ChildItem -Path "C:\Test"

$groupedFiles = $files | Group-Object -Property Length

foreach ($file in $groupedFiles)
{
    if ($file.Count -gt 1)
    {
        $objectsToRemove = $file.Group | Sort-Object -Property CreationTime -Descending | Select-Object -Skip 1
        #$objectsToRemove | remove-item -Force 
    }
}





$settingToChange = 'device_vendor_msft_policy_config_deliveryoptimization_doabsolutemaxcachesize'
$newValue = 5

$uriGet = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('02a56716-dd75-4d31-9424-77f0bab4ab74')?`$expand=settings"

$response = Invoke-MgGraphRequest -Uri $uriGet -Method Get -OutputType Json

$responseObject = $response | ConvertFrom-Json -Depth 10

foreach ($setting in $responseObject.settings)
{
    if ($setting.settingInstance.settingDefinitionId -eq $settingToChange)
    {
        $setting.settingInstance.simpleSettingValue.value = $newValue
    }   
}

$jsonString = $responseObject | Select-Object name, platforms, technologies, settings | ConvertTo-Json -Depth 10 

$uriPut = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('02a56716-dd75-4d31-9424-77f0bab4ab74')"

$responsePut = Invoke-MgGraphRequest -Uri $uriPut -Method Put -Body $jsonString






















