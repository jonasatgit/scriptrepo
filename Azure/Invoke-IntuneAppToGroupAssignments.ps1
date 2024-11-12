<#
.SYNOPSIS
Script to assign Intune apps to groups

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

Script to assign Intune apps to groups from a CSV file. 
The script will only require the Microsoft.Graph.Authentication module to minimize dependencies.

The CSV file should have the following columns:
- GroupName
- AppName
- AssignmentIntent
    Possible values: available, required
    If the value is not available or required, the script will default to available

If the group or app is not found, the script will skip the assignment for that group or app
If the app is already assigned to the group, the script will skip the assignment

Example CSV file:
GroupName,AppName,AssignmentIntent
"Group1","App1","available"
"Group2","App2","required"

.PARAMETER InputCSV
Path to the CSV file with the group assignments

.PARAMETER EntraIDAppID
Optional parameter to use your own Entra ID app registration

.PARAMETER EntraIDTenantID
Optional parameter to use your own Entra ID app registration

.EXAMPLE
Invoke-IntuneAppToGroupAssignments.ps1 -InputCSV "C:\GroupList.csv"

.EXAMPLE
Invoke-IntuneAppToGroupAssignments.ps1 -InputCSV "C:\GroupList.csv" -EntraIDAppID "12345678-1234-1234-1234-123456789012" -EntraIDTenantID "12345678-1234-1234-1234-123456789012"

#>

param
(
    [Parameter(Mandatory = $true)]
    [string]$InputCSV,

    [Parameter(Mandatory=$false)]
    [string]$EntraIDAppID,

    [Parameter(Mandatory=$false)]
    [string]$EntraIDTenantID
)

#region quick check for Entra ID
if ($EntraIDAppID)
{
    # we also need the tenant id in that case
    if ([string]::IsNullOrEmpty($EntraIDTenantID))
    {
        Write-Host "Please also set parameter -EntraIDTenantID to be able to use your own Entra ID app registration" -ForegroundColor Yellow
        Break
    }
}

#region import csv
if (-NOT (Test-Path -Path $InputCSV))
{
    Write-Host "File `"$InputCSV`" not found" -ForegroundColor Red
    Break
}   

try 
{
    $groupList = Import-Csv -Path $InputCSV -Delimiter ',' -ErrorAction Stop
}
catch 
{
    Write-Host "Failed to import CSV file `"$InputCSV`"" -ForegroundColor Red
    break
}

# Check if the CSV file has the required columns
$requiredColumns = @('GroupName', 'AppName', 'AssignmentIntent')
$missingColumns = $false

foreach ($requiredColumn in $requiredColumns)
{
    if ($groupList[0].PSObject.Properties.Name -notcontains $requiredColumn)
    {
        Write-Host "Column `"$requiredColumn`" not found in CSV file `"$InputCSV`"" -ForegroundColor Red
        $missingColumns = $true
    }
}

if ($missingColumns)
{
    Write-Host "CSV file `"$InputCSV`" is missing required columns" -ForegroundColor Red
    Break
}
#endregion

#region check for required modules
# Check if the Microsoft.Graph.Authentication module is installed
$requiredModules = @('Microsoft.Graph.Authentication') #,'Microsoft.Graph.Groups')
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
        $nuget = Get-PackageProvider -ErrorAction Ignore | Where-Object {$_.Name -ieq 'nuget'} # not using -name parameter du to autoinstall question
        if (-Not($nuget))
        {   
            Write-Host "Need to install NuGet to be able to install $($requiredModule)" -ForegroundColor Green
            # Changed to MSI installer as the old way could not be enforced and needs to be approved by the user
            # Install-PackageProvider -Name NuGet -MinimumVersion $minimumVersion -Force
            $null = Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies -MinimumVersion $minimumVersion -Force
        }

        foreach ($requiredModule in $requiredModules)
        {
            if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
            {
                Write-Host "No admin permissions. Will install $($requiredModule) for current user only" -ForegroundColor Green
                
                $paramSplatting = @{
                    Name = $requiredModule
                    Force = $true
                    Scope = 'CurrentUser'
                    ErrorAction = 'Stop'
                }
                Install-Module @paramSplatting
            }
            else 
            {
                Write-Host "Admin permissions. Will install $($requiredModule) for all users" -ForegroundColor Green

                $paramSplatting = @{
                    Name = $requiredModule
                    Force = $true
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
    Write-Host "failed to install or load module" -ForegroundColor Yellow
    Write-Host "$($_)" -ForegroundColor Red
    Break
}
#endregion

#region Connect to Graph
if ([string]::IsNullOrEmpty($EntraIDAppID))
{
    Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All", "Group.Read.All"
}
else
{
    Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All", "Group.Read.All" -ClientId $EntraIDAppID -TenantId $EntraIDTenantID
}
#endregion

#region MAIN logic
foreach($item in $groupList)
{
    Write-Host "----------------------------" -ForegroundColor Green
    # Lets first look for the group
    try 
    {
        Write-Host "Will search for group displayName `"$($item.GroupName)`"" -ForegroundColor Green
        #$group = Get-MgGroup -Filter "displayName eq '$($item.GroupName)'"
        $uri = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$($item.GroupName)'"
        $group = Invoke-MgGraphRequest -Uri $uri -Method Get -ErrorAction Stop        
    }
    catch 
    {
        Write-Host "Failed to get group `"$($item.GroupName)`". Skipping group" -ForegroundColor Yellow
        Write-Host "$($_)" -ForegroundColor Red
        continue
    }

    
    if($null -eq $group.value)
    {
        Write-Host "Group `"$($item.GroupName)`" not found. Skipping group" -ForegroundColor Green
        continue
    }
    elseif ($group.Value.id.Count -gt 1) 
    {
        Write-Host "Found $($group.Value.id.Count) groups with the name `"$($item.GroupName)`". Make sure to use unique group names. Skipping group" -ForegroundColor Green
        continue
    }
    Write-Host "Group `"$($item.GroupName)`" found with ID `"$($group.Value.id)`"" -ForegroundColor Green

    # Lets now look for the app
    try 
    {
        Write-Host "Will search for app displayName `"$($item.AppName)`"" -ForegroundColor Green
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=displayName eq '$($item.AppName)'"
        $encodedUrl = [System.Uri]::EscapeUriString($uri)
        $intuneApp = Invoke-MgGraphRequest -Uri $encodedUrl -Method Get       
    }
    catch 
    {
        Write-Host "Failed to get app `"$($item.AppName)`". Skipping app" -ForegroundColor Yellow
        Write-Host "$($_)" -ForegroundColor Red
        continue
    }


    if ($null -eq $intuneApp.Value)
    {
        Write-Host "App `"$($item.AppName)`" not found. Skipping app" -ForegroundColor Yellow
        continue
    }
    elseif ($intuneApp.value.id.count -gt 1) 
    {
        Write-Host "Found $($intuneApp.value.id.count) apps with the name `"$($item.AppName)`". Make sure to use unique names. Skipping app" -ForegroundColor Yellow
        continue
    }

    Write-Host "App $($item.AppName) found with ID $($intuneApp.Value.id)" -ForegroundColor Green

    # if we haven an app, we need to check if the app is already assigned to the group
    try 
    {
        Write-Host "Will check if app `"$($item.AppName)`" is already assigned to group `"$($item.GroupName)`"" -ForegroundColor Green
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($intuneApp.Value.id)/assignments"
        $assignments = Invoke-MgGraphRequest -Uri $uri -Method Get -ErrorAction Stop    
    }
    catch 
    {
        Write-Host "Failed to get assignments for app `"$($item.AppName)`". Skipping app" -ForegroundColor Yellow
        Write-Host "$($_)" -ForegroundColor Red
        continue
    }


    if ($group.Value.id -in $assignments.value.target.groupId)
    {
        Write-Host "App `"$($item.AppName)`" is already assigned to group `"$($item.GroupName)`"" -ForegroundColor Yellow
        continue
    }
    else 
    {

        Switch($item.AssignmentIntent)
        {
            "available" 
            { 
                $assignmentIntent = "available" 
            }
            "required" 
            { 
                Write-Host "Assignment intent is `"$($item.AssignmentIntent)`" Start- and deadlineDateTime will be set to `"As soon as possible`"" -ForegroundColor Yellow
                $assignmentIntent = "required" 
            }
            Default 
            { 
                Write-Host "Unknown assignment intent `"$($item.AssignmentIntent)`". Will default to `"available`"" -ForegroundColor Yellow 
                $assignmentIntent = "available" 
            }
        }

        $assignmentSettings = @{
            source = "direct"
            settings = @{
                "@odata.type" = "#microsoft.graph.win32LobAppAssignmentSettings"
                installTimeSettings = $null

                <#
                "installTimeSettings": {
                    "startDateTime": "2024-12-31T06:20:00Z",
                    "useLocalTime": true,
                    "deadlineDateTime": null,   
                #>

                autoUpdateSettings = $null
                deliveryOptimizationPriority = "foreground"
                notifications = "showAll"
                restartSettings = $null
            }
            target = @{
                deviceAndAppManagementAssignmentFilterId = $null
                "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                deviceAndAppManagementAssignmentFilterType = "none"
                groupId = $group.Value.id
            }
            intent = $assignmentIntent
        }

        try 
        {
            Write-Host "Will try to assign App `"$($item.AppName)`" as `"$assignmentIntent`" to group `"$($item.GroupName)`"" -ForegroundColor Green
            $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($intuneApp.Value.id)/assignments"
            $result = Invoke-MgGraphRequest -Uri $uri -Method Post -Body ($assignmentSettings | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop           
        }
        catch 
        {
            write-host "Failed to assign app `"$($item.AppName)`" to group `"$($item.GroupName)`"" -ForegroundColor Yellow
            Write-Host "$($_)" -ForegroundColor Red
            continue
        }

    }
}
 Write-Host "End of script" -ForegroundColor Green
#endregion