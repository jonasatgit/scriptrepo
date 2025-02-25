#requires -module Microsoft.Graph.Authentication
#requires -module Microsoft.Graph.Groups

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

    The script requires the system managed identity of the Intune Automation Account
    to be active. The managed identity also needs to have the correct permissions set.
    Run the script with the parameter: -ShowPermissionsScript
    To output an example script to set the required permissions.   

#>

param(
    #[string]$SubscriptionId = '1dab7506-e24e-485a-9a56-442b1d89fd07',
    #[string]$storageAccountName = 'intuneautomation345346',
    #[string]$storageAccountContainerName = 'intunedata',
    #[array]$requiredModules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Groups', 'Az.Accounts', 'Az.Storage'),
    [Switch]$ShowPermissionsScript,
    [String]$ClientID,
    [String]$TenantID
)


#region Function Get-IntuneReportData
<#
.SYNOPSIS
    Function to get Intune report data
.DESCRIPTION
    This function will create a report job in Intune and download the report as zip.
    The zip file will be extracted and the CSV file will be imported and returned as an array of objects.

    Possible reports and values can be found here: 
    https://learn.microsoft.com/en-us/mem/intune/fundamentals/reports-export-graph-available-reports

.PARAMETER RequestBodyJSON
    The JSON request body to be sent to Intune
    Consult the documentation for possible values
#>
Function Get-IntuneReportData
{
    param
    (
        [string]$RequestBodyJSON
    )

    try 
    {   
        $reportName = $RequestBodyJSON | ConvertFrom-Json | Select-Object -ExpandProperty reportName
        $outFileFullName = '{0}\{1}.zip' -f $env:temp, $reportName
        Write-Host "Downloading report $reportName to $outFileFullName"
        $reportJob = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs" -Body $RequestBodyJSON -ContentType "application/json"
        # Check the status of the export job via attribute status until it is completed
        do 
        {
            start-sleep -Seconds 5
            $reportJob = Invoke-MgGraphRequest -Method Get -Uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs/$($reportJob.Id)"
            Write-Host "Report job status: $($reportJob.status)"
        } 
        until ($reportJob.status -ieq "completed")
        
        # download the report as zip to %temp% from the URL provided in the response
        Invoke-WebRequest -Uri $reportJob.url -OutFile $outFileFullName

        if (Test-Path $outFileFullName)
        {
            Write-Host "Report downloaded to $outFileFullName"
        }
        else
        {
            Write-Error "Failed to download report. Error: $($_)"
            Return $null
        }
    }
    catch 
    {
        Write-Error "Failed to download report. Error: $($_)"
        Return $null
    }
    
    try 
    {
        $outCSVFileFullName = '{0}\{1}.csv' -f $env:temp, $reportName
        $reportZipFile = [System.IO.Compression.ZipFile]::OpenRead($outFileFullName)
        $reportZipFile.Entries | Where-Object {$_.Name -ilike '*.csv'} | ForEach-Object {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, $outCSVFileFullName, $true)
        }
        $reportZipFile.Dispose()  
    }
    catch 
    {
        Write-Host "CSV could not been extracted. Error: $($_)"
        Return $null
    }
    
    
    # test if csv file exists
    if (Test-Path $outCSVFileFullName)
    {
        Write-Host "Report extracted to $outCSVFileFullName"
    }
    else
    {
        Write-Error "Report file missing: $outCSVFileFullName"
        Return $null
    }

    # check delimiter. Can be ; or , depending on who created the file. Either Intune Download or test with Excel for examle
    # Just making sure we have the right delimiter
    $csvHeader = Get-Content -Path $outCSVFileFullName -TotalCount 1 
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
        Write-Host "No delimiter found in CSV file"
        Return $null
    }

    # Import CSV file
    $csvData = Import-Csv -Path $outCSVFileFullName -Delimiter $csvDelimiter
    # Remove the CSV file
    Remove-Item -Path $outCSVFileFullName -Force
    # Remove the ZIP file
    Remove-Item -Path $outFileFullName -Force
    # Return the CSV data
    Return $csvData
}
#endregion

#region PermissionsScript for managed identity
$permissionsScript = @'
# RUN THE FOLLOWING SCRIPT TO ASSIGN MANAGED IDENTITY PERMISSIONS

# REPLACE WITH THE ACTUAL VALUES
$managedIdentityId = "<Managed-Identity-Object-ID>" 
#$resourceGroupName = "<Resource-Group-Name>"
#$storageAccountName = "<Storage-Account-Name>"
 
Install-Module Microsoft.Graph -Scope CurrentUser # if not done alreaddy 
 
# Permissions required to set permissions for the managed identity 
Connect-MgGraph -Scopes "Application.Read.All", "AppRoleAssignment.ReadWrite.All", "RoleManagement.ReadWrite.Directory"
 
# Permissions to read devices in Intune, read Entra ID groups and add devices to groups 
$permissions = ("DeviceManagementManagedDevices.Read.All", "Device.ReadWrite.All", "Group.Read.All", "GroupMember.ReadWrite.All") 
 
# Role Assignment 
$msgraph = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'" 
foreach($permission in $permissions) 
{ 
    $role = $Msgraph.AppRoles| Where-Object {$_.Value -eq $permission}  
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentityId -PrincipalId $managedIdentityId -ResourceId $msgraph.Id -AppRoleId $role.Id 
}

# Assign permissions for Storage Account Access
#$storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
#New-AzRoleAssignment -ObjectId $managedIdentityId -RoleDefinitionName "Storage Blob Data Contributor" -Scope $storageAccount.Id

'@

if ($ShowPermissionsScript)
{
    Write-host $permissionsScript -ForegroundColor Green
    Write-host "Script copied to clipboard" -ForegroundColor Yellow
    $permissionsScript | clip
    break
}
#endregion

#region jsonDefinition
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
    "filter": "(Platform eq 'Windows')",
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
        "Microsoft.Microsoft3DViewer": {
        "GroupName": "IN-D-INV-Microsoft3DViewer",
        "GroupId": "165abfb0-65a1-49b1-9ac8-680e0686adde"
      },
      "Notepad++*": {
        "GroupName": "IN-D-INV-Notepad++",
        "GroupId": "e5ad46d8-bf94-4be6-ba2d-86eb388c269a"
      },
      "7-Zip*": {
        "GroupName": "IN-D-INV-7-Zip",
        "GroupId": "b4befe4a-1608-47c9-81a3-ef796f745f47"
      }
    }
  }
}
"@
$objectFromJsonDefinition = $jsonDefinition | ConvertFrom-Json
#endregion

#region deviceReportDefinition
# Used to get all devices and their Entra ID object ID
$deviceReportDefinition = @"
{
    "reportName": "DevicesWithInventory",
    "format": "csv",
    "localizationType": "localizedValuesAsAdditionalColumn",
    "select": [
      "DeviceId",
      "ReferenceId",
      "DeviceName",
      "Manufacturer",
      "Model"
    ]
}
"@
#endregion

#region MAIN SCRIPT START
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
#endregion

#region authentication
# Are we running in Azure Automation?
if (Get-Command -Name Get-AutomationVariable -ErrorAction SilentlyContinue)
{
    # Script running in Azure Automation
    Connect-MgGraph -Identity

    #Get-MgContext
}
else 
{
    # This part is only needed when running the script locally without Azure Automation
    # Check if all required modules are installed and load them if not    
    Connect-MgGraph -ClientId $ClientID -TenantId $TenantID
    #Connect-MgGraph
}
#endregion

#region get device report to be able to match deviceID to Entra ID object ID
[array]$ListOfDevices = Get-IntuneReportData -RequestBodyJSON $deviceReportDefinition
if ($null -eq $ListOfDevices)
{
    Write-Host "No devices found"
    break
}
else 
{
    # Create hashtable with deviceid as key and Entra ID object ID as value
    $deviceLookupTable = @{}
    foreach($deviceObj in $ListOfDevices)
    {
        $deviceLookupTable[($deviceObj.'Device ID')] = ($deviceObj.'Azure AD Device ID')
    }
}
#endregion

#region get device software report
$deviceChangeList = [System.Collections.Generic.List[System.Object]]::new()
[array]$devicesData = Get-IntuneReportData -RequestBodyJSON ($objectFromJsonDefinition.ReportData | ConvertTo-Json -Depth 10)
if ($null -eq $devicesData)
{
    Write-Host "No data found for report: $($objectFromJsonDefinition.ReportData.reportName)"
    break
}
else 
{
    # What is the matching attribute from the report data to the matching table?
    $matchingAttribute = $objectFromJsonDefinition.MatchingData.MatchingAttribute   
    foreach($item in $devicesData)
    {
        $tmpObject = $null
        $groupID = $null
        $groupName = $null
        $objectFromJsonDefinition.MatchingData.MatchingTable.PSObject.Properties | ForEach-Object {
            # We will check each entry from the exported report data against the matching table
            if($item.$matchingAttribute -ilike $_.Name)
            {
                $groupID = $_.Value.GroupId
                $groupName = $_.Value.GroupName

                $tmpObject = [PSCustomObject]@{
                    IntuneDeviceID = $item.DeviceId
                    EntraIDDeviceID = $null
                    EntraIDObjectID = $null
                    DeviceName = $item.DeviceName
                    GroupName = $groupName
                    GroupID = $groupID
                }
            }
        }  
    
        if ($null -eq $groupID)
        {
            #Write-Host "Continue to next item. Since we have no groupID and therefore no matching entry in the matching table"
            continue 
        }
        else 
        {
            $deviceChangeList.Add($tmpObject)
        }
    }
    
    # Lets make the entries unique
    # Multiple entries per device can happen, in case we have multiple versions of an app installed
    [array]$deviceChangeListUnique = $deviceChangeList | Select-Object -Property IntuneDeviceID, EntraIDDeviceID, EntraIDObjectID, DeviceName, GroupName, GroupID -Unique
    Write-Host "Found $($deviceChangeList.Count) devices in total to be added to groups"
    Write-Host "Found $($deviceChangeListUnique.Count) unique device and group entries to be added to groups"
}
#endregion

#region get Entra ID object ID for each device
# Lets get the Entra ID object ID for each device or skip the device
if ($deviceChangeListUnique)
{
    # We will now add the EntraID device id from our lookup table
    foreach ($item in $deviceChangeListUnique)
    {
        Write-Host "Looking up deviceID: `"$($item.IntuneDeviceID)`" in lookup table"
        $item.EntraIDDeviceID = $deviceLookupTable[$item.IntuneDeviceID]
        if ($null -eq $item.EntraIDDeviceID)
        {
            Write-Host "No device with deviceID: `"$($item.IntuneDeviceID)`" found in Intune device data export"
            continue
        }
    }

    # now getting the Entra ID object ID for each device
    # We will limit the amount of requests to the Graph API by using a lookup table
    # And by requesting the device object ID for each device in the list only once even if we have one device multiple times in the list
    # We will also skip devices that are not found in Entra ID
    $entraIDObjectIDLookupTable = @{}
    foreach ($entraIDDeviceID in ($deviceChangeListUnique.EntraIDDeviceID | Select-Object -Unique))
    {
        $deviceURI = 'https://graph.microsoft.com/v1.0/devices?$filter=deviceID eq ''{0}''&$select=id,deviceId,displayName' -f ($entraIDDeviceID)
        $deviceResult = Invoke-MgGraphRequest -Method GET -Uri $deviceURI
        if ($null -eq $deviceResult.value)
        {
            Write-Host "No device with deviceID: `"$($entraIDDeviceID)`" found in Entra ID"
            continue
        }
        else 
        {
            $entraIDObjectIDLookupTable[$entraIDDeviceID] = $deviceResult.value.id
        }
    }

    # Now we can loop through the list of devices and add the Entra ID object ID
    foreach ($item in $deviceChangeListUnique)
    {
        $item.EntraIDObjectID = $entraIDObjectIDLookupTable[$item.EntraIDDeviceID]
        if ($null -eq $item.EntraIDObjectID)
        {
            Write-Host "No device with deviceID: `"$($item.EntraIDDeviceID)`" found in Entra ID"
        }
    }

    # We should now have a list of devices with Entra ID object ID like this:
    <#
        IntuneDeviceID  : 223e367c-d550-4706-81f1-93e9a163b664
        EntraIDDeviceID : 93605da0-fad8-460c-923b-16d4c2ef4dbb
        EntraIDObjectID : 2c12b8d5-5499-435d-8be0-a3e493ef1ea7
        DeviceName      : DESKTOP-4JF0U73
        GroupName       : IN-D-INV-Notepad++
        GroupID         : e5ad46d8-bf94-4be6-ba2d-86eb388c269a
    #>

    # Get all group members and create a list of items to be removed first
    # Start by getting all group members for each group but only once
    # The list can contain each group multiple times, so we will use a hashtable to store the group members
    $groupMembersHashtable = @{}
    foreach ($groupID in ($deviceChangeListUnique.GroupID | Select-Object -Unique))
    {
        $groupMembersHashtable[$groupID] = Get-MgGroupMember -GroupId $groupID -All

        if ($null -eq $groupMembersHashtable[$groupID])
        {
            Write-Host "No group members found for group: `"$($groupID)`""
            continue
        }
        else 
        {
            # Remove any members that are not part of the Intune export data
            [array]$definedGroupMembers = $deviceChangeListUnique | Where-Object {$_.GroupID -eq $groupID}
            foreach ($member in $groupMembersHashtable[$groupID])
            {
                if ($member.id -inotin $definedGroupMembers.EntraIDObjectID)
                {
                    Write-Host "Device `"$($member.id)`" is not part of the Intune export data and needs to be removed from the group"
                    Remove-MgGroupMemberByRef -GroupId $groupID -DirectoryObjectId $member.id
                }
            }   
        }
    }

    # Lets now add new members to the group in case they are not already in the group
    foreach ($item in $deviceChangeListWithEntraID)
    {
        if ([string]::IsNullOrEmpty($item.EntraIDObjectID))
        {
            Write-Host "No Entra ID object ID found for device: `"$($item.DeviceName)`" Need to skip device"
            continue
        }

        # Check if the device is already a member of the group
        if ($item.EntraIDObjectID -in $groupMembersHashtable[$item.GroupID].id)
        {
            Write-Host "Device `"$($item.DeviceName)`" is already a member of group `"$($item.GroupName)`". Skipping."
            continue
        }
        else 
        {
            Write-Host "Adding device `"$($item.DeviceName)`" to group `"$($item.GroupName)`""
            #New-MgGroupMember -GroupId "$($groupID)" -DirectoryObjectId "$($device.value.id)" -Debug

            $membersHashTable = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/devices/$($item.EntraIDObjectID)"
            }

            $groupUri = "https://graph.microsoft.com/v1.0/groups/$($item.GroupID)/members/`$ref"
            Invoke-MgGraphRequest -Method POST -Uri $groupUri -Body ($membersHashTable | ConvertTo-Json)
        }
    }
}
#endregion
