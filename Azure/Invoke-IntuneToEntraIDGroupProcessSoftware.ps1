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
    Example script to add Intune devices to Entra ID groups
    
.DESCRIPTION
    Example script to add Intune devices to Entra ID groups
    Can be used in PowerShell or Azure Automation Runbook
    Source: https://github.com/jonasatgit/scriptrepo
   
    Create Entra ID Groups based on installed software

#>

param(
    [string]$SubscriptionId = '1dab7506-e24e-485a-9b55-442b1d89fd07',
    [string]$storageAccountName = 'intuneautomation345345',
    [string]$storageAccountContainerName = 'intunedata',
    [array]$requiredModules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Groups', 'Az.Accounts', 'Az.Storage')
)

<#
    The following is a definition of the JSON object that is used to define the report to be exported from Intune
    As well as the matching table to map the application names to the Entra ID group names
    Or to match any other attribute that is used to group the devices
    The object can contain any valid Intune report definition and appropiate matching table
#>
$jsonDefinition = @"
{
  "ReportData": {
    "reportName": "AppInvRawData",
    "format": "csv",
    "localizationType": "localizedValuesAsAdditionalColumn",
    "select": [
      "ApplicationId",
      "ApplicationName",
      "ApplicationPublisher",
      "ApplicationShortVersion",
      "ApplicationVersion",
      "DeviceId",
      "DeviceName",
      "OSDescription",
      "OSVersion",
      "Platform",
      "UserId",
      "EmailAddress",
      "UserName"
    ]
  },
  "MatchingData": {
    "MatchingAttribute": "ApplicationName",
    "MatchingTable": {
        "Microsoft.Microsoft3DViewer": "IN-D-INV-Microsoft3DViewer",
        "Microsoft.MicrosoftEdge.Stable": "IN-D-INV-MicrosoftEdgeStable",
        "Microsoft.MicrosoftForms": "IN-D-INV-MicrosoftForms",
        "Microsoft.MicrosoftOfficeHub": "IN-D-INV-MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection": "IN-D-INV-MicrosoftSolitaireCollection",
        "Microsoft.MicrosoftStickyNotes": "IN-D-INV-MicrosoftStickyNotes",
        "Microsoft.MixedReality.Portal": "IN-D-INV-MicrosoftMixedRealityPortal"
    }
  }
}
"@

$objectFromJsonDefinition = $jsonDefinition | ConvertFrom-Json


# used as a basis to convert Intune device IDs to Entra ID object device IDs
[string]$devicesWithInventoryFileName = 'DevicesWithInventory.csv'

# add type to uncompress file
try 
{
    $null = Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction Stop
}
catch [System.Exception] 
{
    Write-CMTraceLog -Message "An error occurred while loading System.IO.Compression.FileSystem assembly." -Severity Error
    Write-CMTraceLog -Message "Error message: $($_)"
    Exit 0
}

# Are we running in Azure Automation?
if (Get-Command -Name Get-AutomationVariable -ErrorAction SilentlyContinue)
{
    # Script running in Azure Automation
    # Will use managed identity with Entra ID application permissions already set up
    Connect-AzAccount -Identity
    $token = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com"
    $secureString = ConvertTo-SecureString -String $token.Token -AsPlainText
    Connect-MgGraph -AccessToken $secureString

    Get-MgContext
}
else 
{
    # This part is only needed when running the script locally without Azure Automation
    # Check if all required modules are installed and load them if not    
    $moduleList = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($requiredModule in $requiredModules)
    {
        if(Import-Module -Name $requiredModule -PassThru -ErrorAction SilentlyContinue)
        {
            Write-Host "$($requiredModule) loaded"
            $moduleList.Add([pscustomobject]@{Name = $requiredModule; Installed = $true; Loaded = $true})
        }
        else
        {
            write-Host "$($requiredModule) module is not installed"
            $moduleList.Add([pscustomobject]@{Name = $requiredModule; Installed = $false; Loaded = $false})
        }
    }  
    
    try 
    {
        if ($moduleList.Where({$_.Installed -eq $false}).Count -gt 0)
        {
            # We might need nuget to install the module
            [version]$minimumVersion = '2.8.5.201'
            Write-Host "Will check NuGet availability"
            $nuget = Get-PackageProvider -ErrorAction Ignore | Where-Object {$_.Name -ieq 'nuget'} # not using -name parameter du to autoinstall question
            if (-Not($nuget))
            {   
                Write-Host "Need to install NuGet to be able to install other modules"
                # Changed to MSI installer as the old way could not be enforced and needs to be approved by the user
                # Install-PackageProvider -Name NuGet -MinimumVersion $minimumVersion -Force
                $null = Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies -MinimumVersion $minimumVersion -Force
            }
    
            if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
            {
                foreach ($requiredModule in ($moduleList | Where-Object {$_.Installed -eq $false}).Name)
                {               
                    Write-Host "No admin permissions. Will install module: $($requiredModule) for current user only"
                    Install-Module $requiredModule -Force -Scope CurrentUser -ErrorAction Stop
                }
            }
            else 
            {
                foreach ($requiredModule in ($moduleList | Where-Object {$_.Installed -eq $false}).Name)
                {
                    Write-Host "Admin permissions. Will install module: $($requiredModule) for all users"
                    Install-Module $requiredModule -Force -Scope AllUsers -ErrorAction Stop 
                }                
            }       
    
            foreach ($requiredModule in ($moduleList | Where-Object {$_.Loaded -eq $false}).Name)
            {
                Write-Host "Will load module: $($requiredModule)"
                Import-Module $requiredModule -Force -ErrorAction Stop
            } 
        }    
    }
    catch 
    {
        Write-Host "failed to install or load module"
        Write-Host "$($_)"
        break
    }

    # Authenticate against Microsoft Graph API
    Connect-MgGraph -scopes "DeviceManagementManagedDevices.Read.All", "Device.ReadWrite.All", "Group.Read.All", "GroupMember.ReadWrite.All" -NoWelcome
    $mgContext = Get-MgContext
    # When enabled, Web Account Manager (WAM) will be the default interactive login experience. It will fall back to using the browser if the platform does not support WAM.
    $null = Update-AzConfig -EnableLoginByWam:$false -DefaultSubscriptionForLogin $SubscriptionId
    $azAccountContext = Connect-AzAccount 
}

# need to set the storage account context to be able to interact with the storage account
$storageAccountContext = New-AzStorageContext -StorageAccountName $storageAccountName
try 
{
    $devicesInventoryDownload = Get-AzStorageBlobContent -Container $storageAccountContainerName -Blob $devicesWithInventoryFileName -context $storageAccountContext -Destination "$($env:temp)\$devicesWithInventoryFileName" -Force  -ErrorAction Stop
}
catch 
{
    if($_.Exception.Message -imatch 'Can not find blob')
    {
        Write-Output "No blob found in storage account"
    }
    else
    {
        Write-Output "Failed to download blob. Error: $($_)"
        Exit 0
    }
}

if (-NOT (Test-Path "$($env:temp)\$devicesWithInventoryFileName"))
{
    Write-Output "No file downloaded"
    Exit 0
}

# Invoke Intune Report Export
<#
$reportHash = [ordered]@{
    "reportName" = "AppInvRawData"
    "format" = "csv"
    "localizationType" = "localizedValuesAsAdditionalColumn"
    "select" = ("ApplicationId", "ApplicationName", "ApplicationPublisher", "ApplicationShortVersion", "ApplicationVersion", "DeviceId", "DeviceName", "OSDescription", "OSVersion", "Platform", "UserId", "EmailAddress", "UserName")
}

$requestBody = $reportHash | ConvertTo-Json
#>

$requestBody = $objectFromJsonDefinition.ReportData | ConvertTo-Json -Depth 10
$reportJob = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs" -Body $requestBody -ContentType "application/json"

# Check the status of the export job via attribute status until it is completed
do 
{
    start-sleep -Seconds 5
    $reportJob = Invoke-MgGraphRequest -Method Get -Uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs/$($reportJob.Id)"
} 
until ($reportJob.status -ieq "completed")


# download the report as zip to %temp% from the URL provided in the response
$outFileFullName = '{0}\AppInvRawData.zip' -f $env:temp
Invoke-WebRequest -Uri $reportJob.url -OutFile $outFileFullName

if (Test-Path $outFileFullName)
{
    Write-Output "Report downloaded to $outFileFullName"
}
else
{
    Write-Error "Failed to download report. Error: $($_)"
    Exit 0
}

try 
{
    $outCSVFileFullName = '{0}\AppInvRawData.csv' -f $env:temp
    $reportZipFile = [System.IO.Compression.ZipFile]::OpenRead($outFileFullName)
    $reportZipFile.Entries | Where-Object {$_.Name -ilike '*.csv'} | ForEach-Object {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, $outCSVFileFullName, $true)
    }
    $reportZipFile.Dispose()  
}
catch 
{
    Write-Host "CSV could not been extracted. Error: $($_)"
    Exit 0
}


# test if csv file exists
if (Test-Path $outCSVFileFullName)
{
    Write-Output "Report extracted to $outCSVFileFullName"
}
else
{
    Write-Error "Failed to extract report"
    Exit 0
}

# create hash table for model to group mapping

# check delimiter. Can be ; or , depending on who created the file. Either Intune Download or test with Excel for examle
$csvHeader = get-content $outCSVFileFullName -TotalCount 1 
if ($csvHeader -imatch '(;.*;)')
{
    $csvDelimiter = ';'
}
elseif ($csvHeader -imatch '(,.*,)') 
{
    $csvDelimiter = ','
}
else
{
    Write-Output "No delimiter found in CSV file"
    Exit 0
}

# import csv file
$csvData = Import-csv -Path $outCSVFileFullName -Delimiter $csvDelimiter


$csvHeader = get-content "$env:temp\$devicesWithInventoryFileName" -TotalCount 1 
if ($csvHeader -imatch '(;.*;)')
{
    $csvDelimiter = ';'
}
elseif ($csvHeader -imatch '(,.*,)') 
{
    $csvDelimiter = ','
}
else
{
    Write-Output "No delimiter found in CSV file"
    Exit 0
}
$devicesData = Import-Csv -Path "$env:temp\$devicesWithInventoryFileName" -Delimiter $csvDelimiter

# get matching attribute and table from json
$matchingAttribute = $objectFromJsonDefinition.MatchingData.MatchingAttribute
# store matching table in hash table for easy lookup
$conversionHashTable = @{}
$objectFromJsonDefinition.MatchingData.MatchingTable.PSObject.Properties | ForEach-Object {
    $conversionHashTable[$_.Name] = $_.Value
}

# create device ID lookup table
$deviceLookupTable = @{}
$devicesData | ForEach-Object {
    $deviceLookupTable[$_.'Device Id'] = $_.'Azure AD Device ID'
}

# loop through csv data
foreach($item in $csvData)
{
    $groupName = $null
    $groupName = $conversionHashTable[($item.$matchingAttribute)]
    if (-NOT $groupName)
    {
        Write-Output "No group found for application: `"$($item.ApplicationName)`""
        continue
    }

    $entraIDDeviceID = $deviceLookupTable[$item.DeviceId]

    # we need to find the device first to get the Entra ID object ID. We cannot add the device with just the "Azure AD Device ID" aka "deviceID"
    $deviceURI = 'https://graph.microsoft.com/v1.0/devices?$filter=deviceID eq ''{0}''&$select=id,deviceId,displayName' -f ($entraIDDeviceID)
    $device = Invoke-MgGraphRequest -Method GET -Uri $deviceURI

    if ($device.value)
    {

        [array]$groups = Get-mggroup -Filter "displayName eq '$groupName'" 
        if(-NOT ($groups))
        {
            Write-Output "Group $groupName not found. Will skip device. Group should be created before running the script"
            <#
            Write-Output "Group $groupName not found. Will create"
            # Should be done manually before running the script
            # create new entra id group
            $description = "This is a new group for Intune devices"
            $newGroup = New-MgGroup -DisplayName $groupName -Description $description -MailEnabled:$false -MailNickname $groupName -SecurityEnabled:$true

            New-MgGroupMember -GroupId $newGroup.id -DirectoryObjectId $device.value.id
            #>
        }
        else
        {
            foreach($group in $groups)
            {
                Write-Output "Group $groupName found. Add device"
                New-MgGroupMember -GroupId $group.id -DirectoryObjectId $device.value.id
            }        
        }
    }
    else 
    {
        Write-Output "No device with deviceID: `"$($entraIDDeviceID)`" found in Entra ID"
    }
}


