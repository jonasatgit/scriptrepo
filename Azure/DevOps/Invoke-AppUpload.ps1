<#
.SYNOPSIS
Script to upload Intune Win32 applications to Intune using Microsoft Graph API.

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

Most Functions are taken from:
https://github.com/microsoft/mggraph-intune-samples/blob/main/LOB_Application/Win32_Application_Add.ps1

.PARAMETER AppFolderName
    The name of the folder containing the applications to upload.

.PARAMETER TemplateFolderName
    The name of the folder containing the application templates. Mainly the AppDeploymentToolkit.

.PARAMETER AppsToProcessFile
    The path to the file containing the list of applications to process.

.PARAMETER AppStorageAccountName
    The name of the storage account where the application content is stored.

.PARAMETER TestStorageAccountFolder
    Switch to test the storage account folder existance. (Important: Will also create the folder if it does not exist)

.PARAMETER BlockSizeMB
    The block size in MB to use for uploading the IntuneWin files. Default is 100 MB.

#>
[CmdletBinding()]
param
(
    [string]$AppFolderName,
    [string]$TemplateFolderName,
    [string]$AppsToProcessFile,
    [string]$AppStorageAccountName,
    [switch]$TestStorageAccountFolder,
    [UInt64]$BlockSizeMB = 100,
    [Switch]$CreateAssignments
)


# To be able to unpack the intunewin file
$null = Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction Stop


<#
.SYNOPSIS
    Function to create a new Intune Win32 app assignment.

.DESCRIPTION
    This function creates a new Intune Win32 app assignment with the specified parameters.
    It constructs the assignment JSON and sends it to the Microsoft Graph API to create the assignment.

.PARAMETER AppID
    The ID of the app to assign.

.PARAMETER TargetType
    The type of target for the assignment. Valid values are "Group", "AllDevices", or "AllUsers".

.PARAMETER AssigmentType
    The type of assignment. Valid values are "Include" or "Exclude". Default is "Include".

.PARAMETER EntraIDGroupID
    The Entra ID group ID to assign the app to. Required if TargetType is "Group".

.PARAMETER Intent
    The intent of the assignment. Valid values are "Available", "Required", or "Uninstall". Default is "Available".

.PARAMETER Notification
    The notification setting for the assignment. Valid values are "showAll", "showReboot", or "hideAll". Default is "showAll".

.PARAMETER DeliveryOptimizationPriority
    The delivery optimization priority for the assignment. Valid values are "foreground" or "notConfigured". Default is "notConfigured".

.PARAMETER StartDateTime
    The start date and time for the assignment. Optional.

.PARAMETER DeadlineDateTime
    The deadline date and time for the assignment. Optional.

.PARAMETER UseLocalTime
    Specifies whether to use local time for the assignment. Default is $true.

.PARAMETER UseRestartGracePeriod
    Specifies whether to use a restart grace period for the assignment. Default is $false.

.PARAMETER CountdownDisplayBeforeRestartInMinutes
    The countdown display time before restart in minutes. Default is 15 minutes.

.PARAMETER GracePeriodInMinutes
    The grace period in minutes for the assignment. Default is 1440 minutes (24 hours).

.PARAMETER RestartNotificationSnoozeDurationInMinutes
    The snooze duration for restart notifications in minutes. Default is 240 minutes (4 hours).

.PARAMETER AssignmentFilterId
    The ID of the assignment filter to use. Optional.

.PARAMETER AssignmentFilterType
    The type of assignment filter to use. Valid values are "none", "include", or "exclude". Default is "none".

.EXAMPLE
    New-IntuneWin32AppAssignment -AppID "12345678-1234-1234-1234-123456789012" -TargetType "Group" -EntraIDGroupID "87654321-4321-4321-4321-210987654321" -Intent "Required" -Notification "showAll" -DeliveryOptimizationPriority "foreground" -StartDateTime (Get-Date) -DeadlineDateTime (Get-Date).AddDays(7) -UseLocalTime $true -UseRestartGracePeriod $true -CountdownDisplayBeforeRestartInMinutes 15 -GracePeriodInMinutes 1440 -RestartNotificationSnoozeDurationInMinutes 240
#>
Function New-IntuneWin32AppAssignment
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory=$true)]
        [string]$AppID,

        [Parameter(Mandatory=$true)]
        [ValidateSet("Group","AllDevices","AllUsers")]
        [string]$TargetType,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Include","Exclude")]
        [string]$AssigmentType = "Include",

        [Parameter(Mandatory=$false)]
        [string]$EntraIDGroupID,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Available","Required","Uninstall")]
        [String]$Intent, # https://learn.microsoft.com/en-us/graph/api/intune-apps-mobileappassignment-create?view=graph-rest-beta#request-body

        [Parameter(Mandatory=$false)]
        [validateset("showAll","showReboot","hideAll")]
        [string]$Notification = "showAll",

        [Parameter(Mandatory=$false)]
        [ValidateSet("foreground","notConfigured")]
        [string]$DeliveryOptimizationPriority = "notConfigured",

        [Parameter(Mandatory=$false)]
        [datetime]$StartDateTime,

        [Parameter(Mandatory=$false)]
        [datetime]$DeadlineDateTime,

        [Parameter(Mandatory=$false)]
        [bool]$UseLocalTime = $true,

        [Parameter(Mandatory=$false)]
        [Switch]$UseRestartGracePeriod,

        [Parameter(Mandatory=$false)]
        [int]$CountdownDisplayBeforeRestartInMinutes = 15,

        [Parameter(Mandatory=$false)]
        [int]$GracePeriodInMinutes = 1440,

        [Parameter(Mandatory=$false)]
        [int]$RestartNotificationSnoozeDurationInMinutes = 240,

        [Parameter(Mandatory=$false)]
        [string]$AssignmentFilterId,

        [Parameter(Mandatory=$false)]
        [ValidateSet("none","include","exclude")]
        [string]$AssignmentFilterType = "none"

    )

    <# Example assignment JSON
        "mobileAppAssignments":
            [
                {
                "@odata.type": "#microsoft.graph.mobileAppAssignment",
                "intent": "Required",
                "settings":
                    {
                    "@odata.type": "#microsoft.graph.win32LobAppAssignmentSettings",
                    "deliveryOptimizationPriority": "foreground",
                    "installTimeSettings":
                        {
                        "@odata.type": "#microsoft.graph.mobileAppInstallTimeSettings",
                        "deadlineDateTime": "2025-12-06T08:00:00.000Z",
                        "startDateTime": "2025-12-01T00:00:00.000Z",
                        "useLocalTime": true
                        },
                    "notifications": "showReboot",
                    "restartSettings":
                        {
                        "@odata.type": "#microsoft.graph.win32LobAppRestartSettings",
                        "countdownDisplayBeforeRestartInMinutes": 15,
                        "gracePeriodInMinutes": 1440,
                        "restartNotificationSnoozeDurationInMinutes": 240
                        }
                    },
                "target":
                    {
                    "@odata.type": "#microsoft.graph.groupAssignmentTarget",
                    "deviceAndAppManagementAssignmentFilterId": "cf4e962e-c789-4efa-9208-ae1a60cd1db7",
                    "deviceAndAppManagementAssignmentFilterType": "include",
                    "groupId": "4d784caf-e371-4657-b541-835f5c7420cc"
                    }
                }
            ]
        }
    #>

    #create base structrure for assignment
    $assignment = [ordered]@{}
    $assignment['@odata.type'] = "#microsoft.graph.mobileAppAssignment"
    $assignment['intent'] = $Intent

    # Adding settings to the assignment like install time, notifications, delivery optimization priority, restart settings
    $settings = [ordered]@{}
    $settings['@odata.type'] = "#microsoft.graph.win32LobAppAssignmentSettings"

    $installTimeSettings = [ordered]@{}
    if ($StartDateTime)
    {
        $installTimeSettings['startDateTime'] = $StartDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $installTimeSettings['useLocalTime'] = $UseLocalTime
    }

    if ($DeadlineDateTime)
    {
        $installTimeSettings['deadlineDateTime'] = $DeadlineDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    $settings['installTimeSettings'] = $installTimeSettings

    $settings['notifications'] = $Notification
    $settings['deliveryOptimizationPriority'] = $DeliveryOptimizationPriority

    if($UseRestartGracePeriod)
    {
        $restartSettings = [ordered]@{}
        $restartSettings['@odata.type'] = "#microsoft.graph.win32LobAppRestartSettings"
        $restartSettings['countdownDisplayBeforeRestartInMinutes'] = $CountdownDisplayBeforeRestartInMinutes
        $restartSettings['gracePeriodInMinutes'] = $GracePeriodInMinutes
        $restartSettings['restartNotificationSnoozeDurationInMinutes'] = $RestartNotificationSnoozeDurationInMinutes

        $settings['restartSettings'] = $restartSettings
    }

    $assignment['settings'] = $settings

    # Adding target to the assignment, which can be a group, all devices or all users and a filter or not
    $target = [ordered]@{}

    switch ($TargetType)
    {
        "Group" 
        {
            $target['@odata.type'] = "#microsoft.graph.groupAssignmentTarget"
            if ($AssignmentFilterId)
            {
                $target['deviceAndAppManagementAssignmentFilterId'] = $AssignmentFilterId
                $target['deviceAndAppManagementAssignmentFilterType'] = $AssignmentFilterType
            }
            $target['groupId'] = $EntraIDGroupID
        }
        "AllDevices" 
        {
            $target['@odata.type'] = "#microsoft.graph.allDevicesAssignmentTarget"
        }
        "AllUsers" 
        {
            $target['@odata.type'] = "#microsoft.graph.allLicensedUsersAssignmentTarget"
        }
    }

    $assignment['target'] = $target

    # Will use Invoke-MgGraphRequest to create the assignment with the constructed hashtable from before
    # https://learn.microsoft.com/en-us/graph/api/intune-apps-mobileappassignment-create?view=graph-rest-beta

    Write-Host "Will try to create assignment for app $AppID as $TargetType"
    $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($AppID)/assignments"
    $result = Invoke-MgGraphRequest -Uri $uri -Method Post -Body ($assignment | ConvertTo-Json -Depth 10) -ContentType "application/json" -ErrorAction Stop           
    
    return $result

}

<#
.SYNOPSIS
    Function to get an Entra ID group by its display name.

.DESCRIPTION
    This function retrieves an Entra ID group by its display name using the Microsoft Graph API.
    It returns the group details if found, or a message indicating no group was found.

.PARAMETER GroupDisplayName
    The display name of the group to search for.

.EXAMPLE
    Get-EntraIDGroupByDisplayName -GroupDisplayName "MyGroup"

    This will search for a group with the display name "MyGroup" and return its details if found.
#>
Function Get-EntraIDGroupByDisplayName
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory=$true)]
        [string]$GroupDisplayName
    )

    Write-Host "Will search for group displayName `"$GroupDisplayName`""
    $uri = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$GroupDisplayName'"
    [array]$groupResult = Invoke-MgGraphRequest -Uri $uri -Method Get -ErrorAction Stop -OutputType PSObject       

    if ($groupResult.value.count -eq 0)
    {
        Write-Host "No group found with displayName `"$GroupDisplayName`""
    }
    elseif ($groupResult.value.count -gt 1) 
    {
        Write-Host "Multiple groups found with displayName `"$GroupDisplayName`""
    }
    elseif ($groupResult.value.count -eq 1) 
    {
        Write-Host "Group found with displayName `"$GroupDisplayName`""
    }

    return $groupResult
}



<#
.SYNOPSIS
    Function to copy data from or to a storage account using azcopy and managed identity.

.DESCRIPTION
    The function will copy data from or to a storage account using azcopy and managed identity.
    The function will download azcopy if it is not present in the temp directory.
    The function will return 'Success' if the copy was successful, otherwise it will return the error message.

.PARAMETER Source
    The source path to copy from.

.PARAMETER Destination
    The destination path to copy to.

.PARAMETER TempDirectory
    The temporary directory to store azcopy.exe.

.EXAMPLE
    Download data from a storage account to a local folder:
    Copy-DataFromOrToStorageAccount -Source "https://mystorageaccount.blob.core.windows.net/mycontainer" -Destination "C:\MyAppFolder" -TempDirectory "C:\Temp"

.EXAMPLE
    Upload data from a local folder to a storage account:
    Copy-DataFromOrToStorageAccount -Source "C:\MyAppFolder" -Destination "https://mystorageaccount.blob.core.windows.net/mycontainer" -TempDirectory "C:\Temp"
#>
function Copy-DataFromOrToStorageAccount 
{
    param 
    (
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Destination,
        [Parameter(Mandatory = $true)]
        [string]$TempDirectory # to store azcopy.exe
    )

    try 
    {
        # we can now download the actual app content into the app folder from the storage account
        # For that we need azcopy.exe
        $azcopyPath = Get-ChildItem "$tempDirectory\azcopy_windows*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if($azcopyPath)
        {
            $azcopyExe = Join-Path $azcopyPath.FullName "azcopy.exe"
        }
        else 
        {
            # fake path to be able to validate its existence and not fail with test-path missing parameter error later in the script
            $azcopyExe = Join-Path $tempDirectory "azcopy.exe"
        }

        # Download azcopy if not already present
        if (-NOT (Test-Path -Path $azcopyExe)) 
        {
            Write-Host "Downloading azcopy tool..."
            Invoke-WebRequest -Uri https://aka.ms/downloadazcopy-v10-windows -OutFile "$tempDirectory\azcopy.zip" -UseBasicParsing
            Expand-Archive "$tempDirectory\azcopy.zip" -DestinationPath $tempDirectory
            $azcopyPath = Get-ChildItem "$tempDirectory\azcopy_windows*" | Select-Object -First 1
            $azcopyExe = Join-Path $azcopyPath.FullName "azcopy.exe"
        }
        else 
        {
            Write-host "Azcopy tool already present. No need to download"
        }

        Write-Host "Login azcopy tool with managed identity..."
        $loginReturn = & $azcopyExe login --identity
        
        # Download all blobs from the container
        Write-Host "Starting azcopy from `"$Source`" to `"$Destination`"..."
        $output = & $azcopyExe copy $Source $Destination --recursive=true --log-level=INFO 2>&1
        if ($LASTEXITCODE -ne 0) 
        {
            $errorMessage = "AzCopy failed with exit code $LASTEXITCODE"
            Write-Warning "AzCopy failed. Output:"
            $output | ForEach-Object { Write-Warning "$_" }
                                    
            if ($output -match "403") 
            {
                Write-Warning "403 Forbidden detected. Check if the managed identity has the correct permissions and storage account network settings."
            }
            return $false
        }            
    }
    catch 
    {
        Write-Warning "AzCopy failed with error: $_"
        return $false
    }

    Write-Host "AzCopy completed successfully."
    return $true
}


#region New-IntuneWinFile
<#
.SYNOPSIS
    Function to create an IntuneWin file from a folder.

.DESCRIPTION
    The function will create an IntuneWin file from a folder using the IntuneWinAppUtil.exe tool.
    The function will download the tool if it is not present in the output folder.
    The function will return the path to the created IntuneWin file.

.PARAMETER AppOutFolder
    The output folder where the IntuneWin file will be saved.

.PARAMETER AppFolder
    The folder containing the application files.

.PARAMETER AppSetupFile
    The setup file for the application.

.PARAMETER AppName
    The name of the application.

.PARAMETER Win32ContentPrepToolUri
    The URI to download the IntuneWinAppUtil.exe tool.

.EXAMPLE
    New-IntuneWinFile -AppOutFolder "C:\IntuneApps\IntuneWinFiles" -AppFolder "C:\IntuneApps\7-Zip-20241217" -AppSetupFile "7z2104-x64.exe" -AppName "7-Zip" -Win32ContentPrepToolUri "https://..."
#>
Function New-IntuneWinFile
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $true)]
        [string]$AppOutFolder,
        [Parameter(Mandatory = $true)]
        [string]$AppFolder,
        [Parameter(Mandatory = $true)]
        [string]$AppSetupFile,
        [Parameter(Mandatory = $true)]
        [string]$ToolsPath,
        [Parameter(Mandatory = $false)]
        [string]$Win32ContentPrepToolUri = 'https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe'        
    )

    process 
    {
        # Lets check if the tools folder exists
        $toolsFolder = '{0}\Tools' -f $ToolsPath
        if (-NOT (Test-Path $toolsFolder))
        {
            New-Item -ItemType Directory -Path $toolsFolder -Force | Out-Null
        }

        # Lets check if the IntuneWinAppUtil.exe is present
        $contentPrepToolFullName = '{0}\IntuneWinAppUtil.exe' -f $toolsFolder
        if (Test-Path $contentPrepToolFullName)
        {
            Write-Host "IntuneWinAppUtil.exe already present. No need to download" 
        }
        else 
        {    
            try 
            {
                Invoke-WebRequest -UseBasicParsing -Method Get -Uri $Win32ContentPrepToolUri -OutFile $contentPrepToolFullName -ErrorAction SilentlyContinue

                if (-not (Test-Path $contentPrepToolFullName))
                {
                    Write-Host "IntuneWinAppUtil.exe download failed" 
                }
            }
            catch 
            {
                Write-Warning "IntuneWinAppUtil.exe download failed" 
                Write-Host "$($_)" 
                Write-Host "You can also download the tool to: `"$AppOutFolder\Tools`" manually" 
                Write-Host "From: `"$Win32ContentPrepToolUri`"" 
                Write-Host "End of script"
                Exit 1
            }
        }
      
        # Making sure the output folder exists
        if (-NOT (Test-Path $AppOutFolder))
        {
            New-Item -ItemType Directory -Path $AppOutFolder -Force | Out-Null   
        }

        try 
        {
            #Write-CMTraceLog -Message "Will run IntuneWinAppUtil.exe to pack content. Might take a while depending on content size"
            Write-Host "Will run IntuneWinAppUtil.exe to pack content. Might take a while depending on content size" -ForegroundColor Green
            $arguments = @(
                '-s'
                "`"$AppSetupFile`""
                '-c'
                "`"$AppFolder`""
                '-o'
                "`"$AppOutFolder`""
                '-q'
            )

            $ProcessStartInfo = New-Object System.Diagnostics.ProcessStartInfo
            $ProcessStartInfo.FileName = $contentPrepToolFullName
            $ProcessStartInfo.RedirectStandardError = $true
            $ProcessStartInfo.RedirectStandardOutput = $true
            $ProcessStartInfo.UseShellExecute = $false
            $ProcessStartInfo.Arguments = $arguments
            $startProcess = New-Object System.Diagnostics.Process
            $startProcess.StartInfo = $ProcessStartInfo
            $startProcess.Start() | Out-Null
            $startProcess.WaitForExit()
            $stdout = $startProcess.StandardOutput.ReadToEnd()
            $stderr = $startProcess.StandardError.ReadToEnd()

            $intunewinLogName = '{0}\Intunewin.log' -f $AppOutFolder
            If($stdout -imatch 'File (?<filepath>.*) has been generated successfully')
            {
                #Write-CMTraceLog -Message "File created successfully"
                Write-Host "File created successfully" -ForegroundColor Green
                $intuneWinFullName = $Matches.filepath -replace "'" -replace '"'
            }
            else 
            {
                Write-Host "IntuneWinAppUtil failed to create the intunewin file." -ForegroundColor Red
            } 
            $stdout | Out-File -FilePath $intunewinLogName -Force -Encoding unicode -ErrorAction SilentlyContinue
            $stderr | Out-File -FilePath $intunewinLogName -Append -Encoding unicode -ErrorAction SilentlyContinue

        }
        catch 
        {
            Write-Host "IntuneWinAppUtil failed to create the intunewin file." -ForegroundColor Red
            Write-Host "$($_)" -ForegroundColor Red
            Get-Content $intunewinLogName | ForEach-Object { Write-Warning $_ }
            return $null
        }

        Get-Content $intunewinLogName | ForEach-Object { Write-Host $_ }

        #Write-Host "More details can be found in the log here: `"$($intunewinLogName)`"" -ForegroundColor Yellow

        return $intuneWinFullName
    }

}
#endregion


#region Wait-ForGraphRequestCompletion 
function Wait-ForGraphRequestCompletion 
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$Uri,
        [Parameter()]
        [string]$Stage      
    )

    if ($Stage )
    {
        # We need to test for a specific stage
        $successString = '{0}Success' -f $Stage    
    }
    else 
    {
        $successString = 'Success'
    }
    
    do {
        $GraphRequest = Invoke-MgGraphRequest -Uri $Uri -Method "GET"

        $uploadState = ([regex]::match($GraphRequest.uploadState, '(pending|failed|timedout|success)',1)).value
        $operation = ([regex]::match($GraphRequest.uploadState, '(.+?)(?=pending|failed|timedout|success)',1)).value

        switch ($uploadState) 
        {
            "Pending" 
            {
                Write-Host "Intune service request for operation '$($operation)' is in pending state, sleeping for 10 seconds"
                Start-Sleep -Seconds 10
            }
            "Failed" 
            {
                Write-Warning "Intune service request for operation '$($operation)' failed" 
                return $GraphRequest
            }
            "TimedOut" 
            {
                Write-Warning "Intune service request for operation '$($operation)' timed out" 
                return $GraphRequest
            }
        }
    }
    until ($GraphRequest.uploadState -imatch $successString)
    Write-Host "Intune service request for operation '$($operation)' was successful with uploadState: $($GraphRequest.uploadState)"

    return $GraphRequest
}
#endregion



#region Intune PowerShell sample functions
#
# https://github.com/microsoft/mggraph-intune-samples/blob/main/LOB_Application/Win32_Application_Add.ps1
#
#***************************************************************************************************************#
#***************************************************************************************************************#
#***************************************************************************************************************#

<#
.SYNOPSIS
Creates a new file system rule.

.DESCRIPTION
This function creates a new file system rule that you can use to specify a detection or requirement for a Win32 app.

.PARAMETER ruleType
The type of rule. Valid values are 'detection' or 'requirement'.

.PARAMETER path
The path to the file or folder.

.PARAMETER fileOrFolderName
The name of the file or folder.

.PARAMETER check32BitOn64System
Specifies whether to check for 32-bit on a 64-bit system.

.PARAMETER operationType
The value type returned by the script. Valid values are 'notConfigured', 'exists', 'modifiedDate', 'createdDate', 'version', 'sizeInMB', 'doesNotExist', 'sizeInBytes', 'appVersion'.

.PARAMETER operator
The operator for the detection script output comparison. Valid values are 'notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual'.

.PARAMETER comparisonValue
The value to compare the script output to.

.EXAMPLE
# Creates a new file system rule for a Win32 app.
New-FileSystemRule -ruleType detection -path 'C:\Program Files\Microsoft VS Code' -fileOrFolderName 'code.exe' -check32BitOn64System $false -operationType exists -operator notConfigured -comparisonValue $null
#>
function New-FileSystemRule() {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateSet("detection", "requirement")]
        [string]$ruleType,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$path,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$fileOrFolderName,
    
        [parameter(Mandatory = $true)]
        [bool]$check32BitOn64System,
    
        [parameter(Mandatory = $false)]
        [ValidateSet("notConfigured", "exists", "modifiedDate", "createdDate", "version", "sizeInMB", "doesNotExist", "sizeInBytes", "appVersion")]
        [string]$operationType,

        [parameter(Mandatory = $false)]
        [ValidateSet("notConfigured", "equal", "notEqual", "greaterThan", "greaterThanOrEqual", "lessThan", "lessThanOrEqual")]
        [string]$operator = "notConfigured",

        [parameter(Mandatory = $false)]
        $comparisonValue
    )

    $Rule = @{}

    if ($null -ne $comparisonValue -and $comparisonValue -ne "") {
        $Rule.comparisonValue = $comparisonValue
    }
    else {
        $Rule.comparisonValue = $null
    }

    $Rule."@odata.type" = "#microsoft.graph.win32LobAppFileSystemRule" 
    $Rule.ruleType = $ruleType
    $Rule.path = $path
    $Rule.fileOrFolderName = $fileOrFolderName
    $Rule.check32BitOn64System = $check32BitOn64System
    $Rule.operationType = $operationType
    $Rule.operator = $operator

    return $Rule
}

<#
.SYNOPSIS
Creates a new product code rule.

.DESCRIPTION
This function creates a new product code rule that you can use to specify a detection or requirement for a Win32 app.

.PARAMETER ruleType
The type of rule. Valid values are 'detection' or 'requirement'.

.PARAMETER productCode
The product code.

.PARAMETER productVersionOperator
The operator for the detection script output comparison. Valid values are 'notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual'.

.PARAMETER productVersion
The value to compare the script output to.

.EXAMPLE
# Creates a new product code rule for a Win32 app.
New-ProductCodeRule -ruleType detection -productCode "{3248F0A8-6813-4B6F-8C3A-4B6C4F512345}" -productVersionOperator equal -productVersion "130.0"
#>
function New-ProductCodeRule {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateSet('detection', 'requirement')]
        [string]$ruleType,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$productCode,

        [parameter(Mandatory = $true)]
        [ValidateSet('notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual')]
        [string]$productVersionOperator,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$productVersion
    )

    $Rule = @{}
    $Rule."@odata.type" = "#microsoft.graph.win32LobAppProductCodeRule"
    $Rule.ruleType = $ruleType
    $Rule.productCode = $productCode
    $Rule.productVersionOperator = $productVersionOperator
    $Rule.productVersion = $productVersion

    return $Rule
}

<#
.SYNOPSIS
Creates a new registry rule.

.DESCRIPTION
This function creates a new registry rule that you can use to specify a detection or requirement for a Win32 app.

.PARAMETER ruleType
The type of rule. Valid values are 'detection' or 'requirement'.

.PARAMETER keyPath
The registry key path.

.PARAMETER valueName
The registry value name.

.PARAMETER operationType
The operation data type (data type returned by the script). Valid values are 'notConfigured', 'exists', 'doesNotExist', 'string', 'integer', 'float', 'version'.

.PARAMETER operator
The operator for the detection script output comparison. Valid values are 'notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual'.

.PARAMETER comparisonValue
The value to compare the script output to.

.EXAMPLE
# Creates a new registry rule for a Win32 app.
New-RegistryRule -ruleType detection -keyPath "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\xyz" -valueName "DisplayName" -operationType string -operator equal -comparisonValue "VSCode"
#>
function New-RegistryRule {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateSet('detection', 'requirement')]
        [string]$ruleType,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$keyPath,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$valueName,

        [parameter(Mandatory = $true)]
        [ValidateSet('notConfigured', 'exists', 'doesNotExist', 'string', 'integer', 'float', 'version')]
        [string]$operationType,

        [parameter(Mandatory = $true)]
        [ValidateSet('notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual')]
        [string]$operator,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$comparisonValue
    )

    $Rule = @{}
    $Rule."@odata.type" = "#microsoft.graph.win32LobAppRegistryRule"
    $Rule.ruleType = $ruleType
    $Rule.keyPath = $keyPath
    $Rule.valueName = $valueName
    $Rule.operationType = $operationType
    $Rule.operator = $operator
    $Rule.comparisonValue = $comparisonValue

    return $Rule
}

<#
.SYNOPSIS
Creates a new script detection rule.

.DESCRIPTION
This function creates a new script detection rule that you can use to specify a detection for a Win32 app.

.PARAMETER ScriptFile
The path to the script file.

.PARAMETER EnforceSignatureCheck
Specifies whether to enforce signature check.

.PARAMETER RunAs32Bit
Specifies whether to run the script as 32-bit.

.EXAMPLE
# Creates a new script detection rule for a Win32 app.
New-ScriptDetectionRule -ScriptFile "E:\VSCodeDetection.ps1" -EnforceSignatureCheck $false -RunAs32Bit $false

.NOTES
This function only creates a script detection rule. To create a script requirement rule, use the New-ScriptRequirementRule function.
#>
function New-ScriptDetectionRule{
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptFile,

        [parameter(Mandatory = $true)]
        [bool]$EnforceSignatureCheck,

        [parameter(Mandatory = $true)]
        [bool]$RunAs32Bit

    )
    if (!(Test-Path "$ScriptFile")) {
        Write-Host "Could not find file '$ScriptFile'..." -ForegroundColor Red
        Write-Host "Script can't continue..." -ForegroundColor Red
        break
    }
        
    $ScriptContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$ScriptFile"))
        
    $Rule = @{}
    $Rule."@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptRule"
    $Rule.ruleType = "detection"
    $Rule.enforceSignatureCheck = $EnforceSignatureCheck
    $Rule.runAs32Bit = $RunAs32Bit
    $Rule.scriptContent = "$ScriptContent"
    $Rule.operationType = "notConfigured"
    $Rule.operator = "notConfigured"

    return $Rule
}

<#
.SYNOPSIS
Creates a new script requirement rule.

.DESCRIPTION
This function creates a new script requirement rule that you can use to specify a requirement for a Win32 app.

.PARAMETER ScriptFile
The path to the script file.

.PARAMETER DisplayName
The display name of the rule.

.PARAMETER EnforceSignatureCheck
Specifies whether to enforce signature check.

.PARAMETER RunAs32Bit
Specifies whether to run the script as 32-bit.

.PARAMETER RunAsAccount
The account to run the script as. Valid values are 'system' or 'user'.

.PARAMETER OperationType
The operation data type (data type returned by the script). Valid values are 'notConfigured', 'string', 'dateTime', 'integer', 'float', 'version', 'boolean'.

.PARAMETER Operator
The operator for the detection script output comparison. Valid values are 'notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual'.

.PARAMETER ComparisonValue
The value to compare the script output to.

.EXAMPLE
# Creates a new script requirement rule for a Win32 app.
New-ScriptRequirementRule -ScriptFile "E:\VSCodeRequirement.ps1" -DisplayName "VS Code Requirement" -EnforceSignatureCheck $false -RunAs32Bit $false -RunAsAccount "system" -OperationType "integer" -Operator "equal" -ComparisonValue "0"

.NOTES
This function only creates a script requirement rule. To create a script detection rule, use the New-ScriptDetectionRule function.
#>
function New-ScriptRequirementRule {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptFile,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [parameter(Mandatory = $true)]
        [bool]$EnforceSignatureCheck,

        [parameter(Mandatory = $true)]
        [bool]$RunAs32Bit,

        #Valid values are 'system' or 'user'
        [parameter(Mandatory = $true)]
        [ValidateSet('system', 'user')]
        [string]$RunAsAccount,

        [parameter(Mandatory = $true)]
        [ValidateSet('notConfigured', 'string', 'dateTime', 'integer', 'float', 'version', 'boolean')]
        [string]$OperationType,

        [parameter(Mandatory = $true)]
        [ValidateSet('notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual')]
        [string]$Operator,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComparisonValue
    )

    if (!(Test-Path "$ScriptFile")) {
        Write-Host "Could not find file '$ScriptFile'..." -ForegroundColor Red
        Write-Host "Script can't continue..." -ForegroundColor Red
        break
    }

    $ScriptContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$ScriptFile"))
        
    $Rule = @{}
    $Rule."@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptRule"
    $Rule.displayName = $DisplayName
    $Rule.ruleType = "requirement"
    $Rule.enforceSignatureCheck = $EnforceSignatureCheck
    $Rule.runAs32Bit = $RunAs32Bit
    $Rule.scriptContent = "$ScriptContent"
    $Rule.operationType = $OperationType
    $Rule.operator = $Operator
    $Rule.comparisonValue = $ComparisonValue
    $Rule.runAsAccount = $RunAsAccount

    return $Rule
}

<#
.SYNOPSIS
Creates a new return code object.

.DESCRIPTION
This function creates a new return code object that you can use to specify the return codes for a Win32 app.

.PARAMETER returnCode
The return code value.

.PARAMETER type
The type of return code. Valid values are 'success', 'softReboot', 'hardReboot

.EXAMPLE
# Creates a new return code object with a return code of 0 and a type of 'success'
New-ReturnCode -returnCode 0 -type 'success'
#>
function New-ReturnCode() {
    param
    (
        [parameter(Mandatory = $true)]
        [int]$returnCode,
        [parameter(Mandatory = $true)]
        [ValidateSet('success', 'softReboot', 'hardReboot', 'retry')]
        $type
    )

    @{"returnCode" = $returnCode; "type" = "$type" }
}


####################################################
# Function to construct the JSON body for a Win32 app
function GetWin32AppBody() {
    param
    (
        [parameter(Mandatory = $true, ParameterSetName = "MSI", Position = 1)]
        [Switch]$MSI,
    
        [parameter(Mandatory = $true, ParameterSetName = "EXE", Position = 1)]
        [Switch]$EXE,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$displayName,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$publisher,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$description,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$filename,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupFileName,
    
        [parameter(Mandatory = $true)]
        [ValidateSet('system', 'user')]
        [string]$RunAsAccount,

        [parameter(Mandatory = $true)]
        [ValidateSet('basedOnReturnCode', 'allow', 'suppress', 'force')]
        [string]$DeviceRestartBehavior,

        [parameter(Mandatory = $false)]
        [string]$Version,
    
        [parameter(Mandatory = $true, ParameterSetName = "EXE")]
        [ValidateNotNullOrEmpty()]
        $installCommandLine,
    
        [parameter(Mandatory = $true, ParameterSetName = "EXE")]
        [ValidateNotNullOrEmpty()]
        $uninstallCommandLine,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiPackageType,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiProductCode,
    
        [parameter(Mandatory = $false, ParameterSetName = "MSI")]
        $MsiProductName,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiProductVersion,
    
        [parameter(Mandatory = $false, ParameterSetName = "MSI")]
        $MsiPublisher,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiRequiresReboot,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiUpgradeCode,

        [parameter(Mandatory = $false)]
        [Bool]$AllowAvailableUninstall
    )
    
    if ($MSI) {
        $body = @{ "@odata.type" = "#microsoft.graph.win32LobApp" }
        $body.allowAvailableUninstall = $AllowAvailableUninstall
        $body.applicableArchitectures = "x64,x86"
        $body.description = $description
        $body.developer = ""
        $body.displayName = $displayName
        $body.displayVersion = $Version
        $body.fileName = $filename
        $body.installCommandLine = "msiexec /i `"$SetupFileName`""
        $body.installExperience = @{
            "runAsAccount"          = "$RunAsAccount"
            "deviceRestartBehavior" = $DeviceRestartBehavior 
        }
        $body.informationUrl = $null
        $body.isFeatured = $false
        $body.minimumSupportedOperatingSystem = @{"v10_1607" = $true }
        $body.msiInformation = @{
            "packageType"    = "$MsiPackageType"
            "productCode"    = "$MsiProductCode"
            "productName"    = "$MsiProductName"
            "productVersion" = "$MsiProductVersion"
            "publisher"      = "$MsiPublisher"
            "requiresReboot" = "$MsiRequiresReboot"
            "upgradeCode"    = "$MsiUpgradeCode"
            "@odata.type"    = "#microsoft.graph.win32LobAppMsiInformation"
        }
        $body.notes = ""
        $body.owner = ""
        $body.privacyInformationUrl = $null
        $body.publisher = $publisher
        $body.runAs32bit = $false
        $body.setupFilePath = $SetupFileName
        $body.uninstallCommandLine = "msiexec /x `"$MsiProductCode`""
    }
    elseif ($EXE) {
        $body = @{ "@odata.type" = "#microsoft.graph.win32LobApp" }
        $body.description = $description
        $body.developer = ""
        $body.displayName = $displayName
        $body.displayVersion = $Version
        $body.fileName = $filename
        $body.installCommandLine = $installCommandLine
        $body.installExperience = @{
            "runAsAccount"          = $RunAsAccount
            "deviceRestartBehavior" = $DeviceRestartBehavior 
        }
        $body.informationUrl = $null
        $body.isFeatured = $false
        $body.minimumSupportedOperatingSystem = @{"v10_1607" = $true }
        $body.msiInformation = $null
        $body.notes = ""
        $body.owner = ""
        $body.privacyInformationUrl = $null
        $body.publisher = $publisher
        $body.runAs32bit = $false
        $body.setupFilePath = $SetupFileName
        $body.uninstallCommandLine = $uninstallCommandLine
    }

    $body
}

####################################################
# Function to get the default return codes    
function Get-DefaultReturnCodes() {
    @{"returnCode" = 0; "type" = "success" }, `
    @{"returnCode" = 1707; "type" = "success" }, `
    @{"returnCode" = 3010; "type" = "softReboot" }, `
    @{"returnCode" = 1641; "type" = "hardReboot" }, `
    @{"returnCode" = 1618; "type" = "retry" }
    
}

#endregion Intune PowerShell sample functions
#
# https://github.com/microsoft/mggraph-intune-samples/blob/main/LOB_Application/Win32_Application_Add.ps1
#
#***************************************************************************************************************#
#***************************************************************************************************************#
#***************************************************************************************************************#

# init variables
if ($env:BUILD_BUILDID) 
{
    Write-Host "Running inside Azure DevOps pipeline" -ForegroundColor Cyan
    # Root directory for all pipeline-related files on the agent
    $workspaceDirectory = $env:PIPELINE_WORKSPACE
    # Equivalent to $env:AGENT_BUILDDIRECTORY
    # Example: C:\agent\_work\1

    # Directory where the source code is checked out
    $sourceDirectory = $env:BUILD_SOURCESDIRECTORY
    # Also known as Build.Repository.LocalPath or System.DefaultWorkingDirectory
    # Example: C:\agent\_work\1\s

    # Directory for placing compiled binaries or build outputs
    $binariesDirectory = $env:BUILD_BINARIESDIRECTORY
    # Recommended location for build outputs
    # Example: C:\agent\_work\1\b

    # Directory used to stage artifacts before publishing
    $artifactStagingDirectory = $env:BUILD_ARTIFACTSTAGINGDIRECTORY
    # Also accessible via $env:BUILD_STAGINGDIRECTORY
    # Example: C:\agent\_work\1\a

    # Temporary directory for the agent, cleaned up after the job
    $tempDirectory = $env:AGENT_TEMPDIRECTORY
    # Example: C:\agent\_work\_temp
} 
else 
{
    Write-Host "Running locally (e.g., in VS Code) using `"$env:TEMP`" for all paths" -ForegroundColor Cyan
    $workspaceDirectory = $env:TEMP

    $sourceDirectory = $PSCommandPath | Split-Path -Parent | Split-Path -Parent 

    $binariesDirectory = $env:TEMP

    $artifactStagingDirectory = $env:TEMP

    $tempDirectory = $env:TEMP

}

Write-Host "Working in directory: `"$sourceDirectory`"" -ForegroundColor Cyan
Write-Host "Storage Account Name: $AppStorageAccountName" -ForegroundColor Cyan


# load application metadata created by the Test-AppMetadata script
$fileInPath = '{0}\AppsToProcess.xml' -f $artifactStagingDirectory

[array]$appMetadata = Import-Clixml -Path $fileInPath -ErrorAction "Stop"

# process each application
#Write-Host "##[section]Starting upload of $($appMetadata.Count) apps"
foreach($app in $appMetadata)
{
    # $app.'StorageAccountFolderName' does contain the appname, version etc. and makes more sense to show in the log as just the name
    Write-Host "Processing application: $($app.'StorageAccountFolderName')"
    
    # skip apps with missing or wrong data
    if ($app.DataMissingOrWrong -eq $true) 
    {
        Write-Warning "Skipping application due to missing or wrong data in metadata."
        continue
    }

    # Write app metadata for debugging to DevOps log
    #Write-Host "App metadata:"
    #$app | ConvertTo-Json -Depth 10

    # create temp app folder in the binaries directory
    $tmpAppFolderPath = '{0}\{1}' -f $binariesDirectory, $app.'StorageAccountFolderName'
    if (-not (Test-Path -Path $tmpAppFolderPath)) 
    {
        New-Item -Path $tmpAppFolderPath -ItemType Directory -ErrorAction "Stop" | Out-Null
        Write-Host "Created folder: $tmpAppFolderPath"
    }
    else 
    {
        Write-Host "Folder already exists: $tmpAppFolderPath"
        # remove its content
        Get-ChildItem -Path $tmpAppFolderPath -Recurse | Remove-Item -Force -Recurse -ErrorAction "Stop"
        Write-Host "Cleared content of folder: $tmpAppFolderPath"
    }

    # build paths for Intune app icon
    $appIconPath = '{0}\IntuneData\Icon.png' -f $tmpAppFolderPath

    # download of complete app package from storage account
    # upload the app folder to the storage account
    $ContainerName = $app.StorageAccountFolderName
    $source = "https://$AppStorageAccountName.blob.core.windows.net/$ContainerName*"
    $destination = $binariesDirectory

    $result = Copy-DataFromOrToStorageAccount -Source $source -Destination $destination -TempDirectory $tempDirectory
    if ($result -ne $true) 
    {
        Write-Warning "Download of app $($app.'StorageAccountFolderName') failed."
        Exit 1
    }


    # create intunewin file
    write-host "Creating IntuneWin file..."

    $paramSplatting = @{
        AppOutFolder = "$tmpAppFolderPath\IntuneData"
        AppFolder    = "$tmpAppFolderPath\App"
        AppSetupFile = $app.IntuneMetadata.InstallData.SetupFile
        ToolsPath    = $tempDirectory
    }

    Write-Host "Parameters for New-IntuneWinFile:"
    $paramSplatting.GetEnumerator() | ForEach-Object { Write-Host "  $($_.Key): $($_.Value)" }

    $intunewinFileFullName = New-IntuneWinFile @paramSplatting

    # We need to extract encryption info from the detection.xml file compressed inside the intunewin file
    $IntuneWin32AppFile = [System.IO.Compression.ZipFile]::OpenRead($intunewinFileFullName)
    $DetectionXmlEntry = $IntuneWin32AppFile.Entries | Where-Object { $_.Name -ieq 'Detection.xml' }
    if ($DetectionXmlEntry) 
    {
        $DetectionXmlStream = $DetectionXmlEntry.Open()
        $StreamReader = New-Object System.IO.StreamReader($DetectionXmlStream)
        $DetectionXmlContent = $StreamReader.ReadToEnd()
        $StreamReader.Close()
        $DetectionXmlStream.Dispose()
        [xml]$detectionXML = $DetectionXmlContent
    }
    else 
    {
        Write-Warning "Detection.xml not found in intunewin file. Will skip app"
        Continue
    }
    # We also need data about the IntunePackage.intunewin file also compressed inside the outer intunewin file
    $IntunePackageIntuneWinMetadata = $IntuneWin32AppFile.Entries | Where-Object {$_.Name -ieq 'IntunePackage.intunewin'}

    # we need to construct the content metadata json file to be able to upload the intunewin file to Intune
    $Win32AppFileBody = [ordered]@{
            "@odata.type" = "#microsoft.graph.mobileAppContentFile"
            "name" = "IntunePackage.intunewin" # from analysis this name is different than the name in the app json
            "size" = [int64]$detectionXML.ApplicationInfo.UnencryptedContentSize 
            "sizeEncrypted" = $IntunePackageIntuneWinMetadata.Length
            "manifest" = $null
            "isDependency" = $false
        }     


    # Step 1: Create intune app body
    write-host "Creating Intune App JSON body..."
    $paramSplatting = @{
        EXE                  = $true
        displayName          = $app.FolderName
        publisher            = $app.'ADT-AppVendor'
        description          = 'Created via DevOps'
        filename             = ($intunewinFileFullName | Split-Path -Leaf)
        SetupFileName        = $app.IntuneMetadata.InstallData.SetupFile
        RunAsAccount         = $app.IntuneMetadata.InstallData.InstallExperience
        DeviceRestartBehavior= $app.IntuneMetadata.InstallData.DeviceRestartBehavior
        Version              = $app.'ADT-AppVersion'
        installCommandLine   = $app.IntuneMetadata.InstallData.InstallCommand
        uninstallCommandLine = $app.IntuneMetadata.InstallData.UninstallCommand
        AllowAvailableUninstall = If($app.IntuneMetadata.InstallData.AllowAvailableUninstall -ieq 'true' -or $app.IntuneMetadata.InstallData.AllowAvailableUninstall -eq $true) { $true } else { $false }
    }

    #Write-host ($paramSplatting | out-string)

    $intuneAppBody = GetWin32AppBody @paramSplatting

    # Adding default return codes
    $returnCodes = Get-DefaultReturnCodes
    $intuneAppBody.Add("returnCodes", @($returnCodes))


    $Rules = @()
    # add detection rules
    # Example detection rule: check if chrome.exe exists in the default installation path
    <#
    $paramSplatting = @{
        ruleType                = "detection"
        operator                = "notConfigured"
        check32BitOn64System    = $false
        operationType           = "exists"
        comparisonValue         = $null
        fileOrFolderName        = "chrome.exe"
        path                    = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
    }
    $Rules += New-FileSystemRule @paramSplatting
    #>

    #$Rules += New-ScriptRequirementRule -ScriptFile "E:\VSCodeRequirement.ps1" -DisplayName "VS Code Requirement" -EnforceSignatureCheck $false -RunAs32Bit $false -RunAsAccount "system" -OperationType "integer" -Operator "equal" -ComparisonValue "0"
    #$Rules += New-ScriptDetectionRule -ScriptFile "E:\VSCodeDetection.ps1" -EnforceSignatureCheck $false -RunAs32Bit $false 
    #$Rules += New-RegistryRule -ruleType detection -keyPath "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\xyz" -valueName "DisplayName" -operationType string -operator equal -comparisonValue "VSCode"

    # Custom detection rule based on registry key from the app metadata
    $regPath = $app.'RegistryBrandingPath' -replace ':', ''
    $Rules += New-RegistryRule -ruleType detection -keyPath $regPath -valueName "Installed" -operationType integer -operator equal -comparisonValue "1"

    # Adding "rules" to the intune app body
    $intuneAppBody.Add("rules", @($Rules))

    # Save the JSON body to a file for reference
    $jsonBodyFilePath = '{0}\IntuneData\IntuneAppBody.json' -f $tmpAppFolderPath
    $intuneAppBody | ConvertTo-Json -Depth 100 | Out-File -FilePath $jsonBodyFilePath -Encoding utf8 -Force
    Write-Host "Saved Intune App JSON body to: $jsonBodyFilePath"

    try 
    {
        Copy-DataFromOrToStorageAccount -Source $jsonBodyFilePath -Destination "https://$AppStorageAccountName.blob.core.windows.net/$ContainerName/IntuneData/IntuneAppBody.json" -TempDirectory $tempDirectory
    }
    catch 
    {
        Write-Warning "Failed to upload Intune App JSON body to storage account: $_"
    }

    # STEP 2: Create the Intune app via Graph API
    write-host "Creating Intune App via Graph API..."
    $paramSplatting = @{
            Method = 'POST'
            Uri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
            Body = ($intuneAppBody | ConvertTo-Json -Depth 100)
            ContentType = "application/json; charset=utf-8"
        }


    Connect-MgGraph -Identity

    $win32MobileAppRequest = Invoke-MgGraphRequest @paramSplatting

    if ($Win32MobileAppRequest.'@odata.type' -notlike "#microsoft.graph.win32LobApp") 
    {
        Write-Warning "Failed to create Win32 app using constructed body"
        Write-Warning "Will skip uploading full app package"
        continue
    }


    Write-Host "Request content version for Intune app"
    $paramSplatting = @{
        Method = 'POST'
        Uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($Win32MobileAppRequest.id)/microsoft.graph.win32LobApp/contentVersions"
        Body = "{}"
    }

    $Win32MobileAppContentVersionRequest = Invoke-MgGraphRequest @paramSplatting
    if ([string]::IsNullOrEmpty($Win32MobileAppContentVersionRequest.id)) 
    {
        Write-Warning "Failed to create contentVersions resource for Win32 app. Will skip uploading full app package" 
        Continue
    }


    Write-Host "Sending content metadata to Intune"
    $paramSplatting = @{
        Method = 'POST'
        Uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($Win32MobileAppRequest.id)/microsoft.graph.win32LobApp/contentVersions/$($Win32MobileAppContentVersionRequest.id)/files"
        Body = $Win32AppFileBody | ConvertTo-Json
        ContentType = "application/json"
    }    

    $Win32MobileAppFileContentRequest = Invoke-MgGraphRequest @paramSplatting
    if ([string]::IsNullOrEmpty($Win32MobileAppFileContentRequest.id)) 
    {
        Write-Warning "Metadata upload failed. Skipping uploading full app package"
        Continue
    }
    else 
    {
        # Wait for the Win32 app file content URI to be created
        Write-Host "Waiting for Intune service to process contentVersions/files request and to get the file URI with SAS token"
        $Win32MobileAppFilesUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($Win32MobileAppRequest.id)/microsoft.graph.win32LobApp/contentVersions/$($Win32MobileAppContentVersionRequest.id)/files/$($Win32MobileAppFileContentRequest.id)"
        $ContentVersionsFiles = Wait-ForGraphRequestCompletion -Uri $Win32MobileAppFilesUri -Stage 'azureStorageUriRequest'
    }


    $IntunePackageIntuneWinMetadataStream = $IntunePackageIntuneWinMetadata.Open()
    Write-Host "Trying to upload file to Intune Azure Storage. File: $($IntunePackageFullName)"
    #$ChunkSizeInBytes = 1024l * 1024l * 6l;
    #[UInt64]$BlockSizeMB = 100 # To support files larger than 8 GB we need to use UInt64
    [UInt64]$chunkSizeInBytes = (1024 * 1024 * $blockSizeMB)
    $FileSize = $IntunePackageIntuneWinMetadata.Length
    $ChunkCount = [System.Math]::Ceiling($FileSize / $ChunkSizeInBytes)
    $BinaryReader = New-Object -TypeName System.IO.BinaryReader($IntunePackageIntuneWinMetadataStream)

    $ChunkIDs = @()
    $SASRenewalTimer = [System.Diagnostics.Stopwatch]::StartNew()
    try 
    {
        for ($Chunk = 0; $Chunk -lt $ChunkCount; $Chunk++) 
        {
            $ChunkID = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Chunk.ToString("0000")))
            $ChunkIDs += $ChunkID
            $Start = $Chunk * $ChunkSizeInBytes
            $Length = [System.Math]::Min($ChunkSizeInBytes, $FileSize - $Start)
            $Bytes = $BinaryReader.ReadBytes($Length)

            # Increment chunk to get the current chunk
            $CurrentChunk = $Chunk + 1
            
            <#
            # Test of renewal process
            if ($Chunk -eq 2)
            {
                Write-Host "Sleeping"
                Start-Sleep -Milliseconds 450000
            }
            #>

            # if we need to renew the SAS token if it is older than 7 minutes
            if ($currentChunk -lt $ChunkCount -and $SASRenewalTimer.ElapsedMilliseconds -ge 450000)
            {
                Write-Host "Renewing SAS token for Azure Storage blob"
                $SASRenewalUri = '{0}/renewUpload' -f $Win32MobileAppFilesUri

                $paramSplatting = @{
                    Method = 'POST'
                    Uri = $SASRenewalUri
                    Body = ''
                    ContentType = "application/json"
                }
        
                try 
                {
                    $Win32MobileAppFileContentRequest = Invoke-MgGraphRequest @paramSplatting
                }
                catch 
                {
                    Write-Warning "$($_)"
                    $chunkFailed = $true
                }
                
                # Wait for the Win32 app file content renewal request
                Write-Host "Waiting for Intune service to process SAS token renewal request"
                $ContentVersionsFiles = Wait-ForGraphRequestCompletion -Uri $Win32MobileAppFilesUri -Stage 'AzureStorageUriRenewal'
                $SASRenewalTimer.Restart()
                # renewal done
            }
            
            $Uri = "$($ContentVersionsFiles.azureStorageUri)&comp=block&blockid=$($ChunkID)"
            $ISOEncoding = [System.Text.Encoding]::GetEncoding("iso-8859-1")
            $EncodedBytes = $ISOEncoding.GetString($Bytes)

            # We need to set the content type to "text/plain; charset=iso-8859-1" for the upload to work
            $Headers = @{
                "content-type" = "text/plain; charset=iso-8859-1"
                "x-ms-blob-type" = "BlockBlob"
            }
        
            Write-Host "Uploading chunk $CurrentChunk of $ChunkCount to Azure Storage blob. Percent complete: $([math]::Round(($CurrentChunk / $ChunkCount*100),2))%"
            $WebResponse = Invoke-WebRequest $Uri -Method "Put" -Headers $Headers -Body $EncodedBytes -ErrorAction Stop -UseBasicParsing
        }                    
    }
    catch 
    {
        Write-Warning "$($_)" 
        Write-Host "Delete app in Intune and retry again. Will skip to the next one..."
        if ($IntunePackageIntuneWinMetadataStream) { $IntunePackageIntuneWinMetadataStream.Dispose() }
        if ($IntuneWin32AppFile) { $IntuneWin32AppFile.Dispose() }
        continue
    }

    Write-Host "Uploaded all chunks to Azure Storage blob"
    $SASRenewalTimer.Stop()        
    $BinaryReader.Close()
    
    # STEP 9: We need to finalize the upload by sending the blocklist to Azure Storage
    Write-Host "Will finalize the upload with the blocklist of uploaded blocks"
    $Uri = "$($ContentVersionsFiles.azureStorageUri)&comp=blocklist"
    $XML = '<?xml version="1.0" encoding="utf-8"?><BlockList>'
    foreach ($Chunk in $ChunkIDs) 
    {
        $XML += "<Latest>$($Chunk)</Latest>"
    }
    $XML += '</BlockList>'

    $Headers = @{
        "Content-Type" = "application/xml"
    }

    try 
    {
        $WebResponse = Invoke-RestMethod -Uri $Uri -Method "Put" -Body $XML -Headers $Headers -ErrorAction Stop 
    }
    catch 
    {
        Write-Warning "Failed to finalize Azure Storage blob upload. Error message: $($_.Exception.Message)"
        Write-Host "Delete app in Intune and retry again. Will skip to the next one..."
        if ($IntunePackageIntuneWinMetadataStream) { $IntunePackageIntuneWinMetadataStream.Dispose() }
        if ($IntuneWin32AppFile) { $IntuneWin32AppFile.Dispose() }
        continue
    }

    if ($IntunePackageIntuneWinMetadataStream) { $IntunePackageIntuneWinMetadataStream.Dispose() }
    if ($IntuneWin32AppFile) { $IntuneWin32AppFile.Dispose() }

    try 
    {
        # STEP 10: We need to commit the file we just uploaded by sending the encryption info to Intune using the content version files URI
        # Commit the file with the encryption info by building the JSON object with data from the Detection.xml file
        $IntuneWinEncryptionInfo = [ordered]@{
            "encryptionKey" = $detectionXML.ApplicationInfo.EncryptionInfo.EncryptionKey
            "macKey" = $detectionXML.ApplicationInfo.EncryptionInfo.macKey
            "initializationVector" = $detectionXML.ApplicationInfo.EncryptionInfo.initializationVector
            "mac" = $detectionXML.ApplicationInfo.EncryptionInfo.mac
            "profileIdentifier" = "ProfileVersion1"
            "fileDigest" = $detectionXML.ApplicationInfo.EncryptionInfo.fileDigest
            "fileDigestAlgorithm" = $detectionXML.ApplicationInfo.EncryptionInfo.fileDigestAlgorithm
        }
        $IntuneWinFileEncryptionInfo = @{
            "fileEncryptionInfo" = $IntuneWinEncryptionInfo
        }

        # We need to commit the file
        $uri = '{0}/commit' -f $Win32MobileAppFilesUri
        
        $paramSplatting = @{
            "Method" = 'POST'
            "Uri" = $uri
            "Body" = ($IntuneWinFileEncryptionInfo | ConvertTo-Json)
            "ContentType" = "application/json"
        }

        Write-Host "Committing the file we just uploaded"

        $Win32MobileAppFileContentCommitRequest = Invoke-MgGraphRequest @paramSplatting -Headers $headers -ErrorAction Stop
        Write-Host "Waiting for Intune service to process file commit request"
        $Win32MobileAppFileContentCommitRequestResult = Wait-ForGraphRequestCompletion -Uri $Win32MobileAppFilesUri

        # STEP 11: We need to set the commited content version to the app in order to bind the file to the app
        # set commited content version
        $Win32AppFileCommitBody = [ordered]@{
            "@odata.type" = "#microsoft.graph.win32LobApp"
            "committedContentVersion" = $Win32MobileAppContentVersionRequest.id
        }

        $paramSplatting = @{
            "Method" = 'PATCH'
            "Uri" = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($Win32MobileAppRequest.id)"
            "Body" = ($Win32AppFileCommitBody | ConvertTo-Json)
            "ContentType" = "application/json"
        }
        Write-Host "Setting the commited content version to the app and basically binding the file to the app"

        Invoke-MgGraphRequest @paramSplatting -ErrorAction Stop
    }
    catch 
    {
        Write-Warning "Error message: $($_.Exception.Message)"
        Write-Host "Delete app in Intune and retry again. Will skip to the next one..."
        continue
    }


    # we will now upload the icon file to the app in case we have one
    if ($app.AppIconFound -eq $true -or $app.AppIconFound -ieq 'true')
    {
        if (Test-Path -Path $appIconPath) 
        {
            Write-Host "Uploading app icon to Intune app"
            try 
            {
                $appIconEncodedBase64String = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($appIconPath))

                $largeIconBody = [ordered]@{
                    "@odata.type" = '#microsoft.graph.win32LobApp'
                    "largeIcon" = [ordered]@{
                        "type" = "image/png"
                        "value" = "$($appIconEncodedBase64String)"
                        }
                    }        
        
                $paramSplatting = @{
                    "Method" = 'PATCH'
                    "Uri" = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($Win32MobileAppRequest.id)"
                    "Body" = ($largeIconBody | ConvertTo-Json) 
                    "ContentType" = "application/json"
                }
                Invoke-MgGraphRequest @paramSplatting -ErrorAction Stop 
            }
            catch 
            {
                Write-Warning "Icon upload failed $($_)" 
                Write-Warning "Will be ignored. App will have no icon"
                continue
            }      
        }
        else 
        {
            Write-Warning "Icon file not found at path: $appIconPath"
            Write-Warning "Will be ignored. App will have no icon"
        }    
    }  


    Write-Host "Successfully created Intune Win32 app: $($app.FolderName) with ID: $($Win32MobileAppRequest.id)"


    if ($CreateAssignments)
    {
        foreach ($assignmentDefinition in $app.IntuneMetadata.Assignments)
        {
            # add logic here to skip if group not found or multiple groups found

            If ($assignmentDefinition.GroupName -ieq 'AllDevices') 
            { 
                $targetType = 'AllDevices'
            } 
            elseif ($assignmentDefinition.GroupName -ieq 'AllUsers')  
            { 
                $targetType = 'AllUsers'
            }
            else
            {
                $targetType = 'Group'
            }


            $assignParamSplatting = @{
                AppID = $Win32MobileAppRequest.id
                TargetType = $targetType
                AssigmentType = 'Include'
                Intent = $assignmentDefinition.Intent
                Notification = $assignmentDefinition.Notification
                DeliveryOptimizationPriority = $assignmentDefinition.DeliveryOptimizationPriority
                UseLocalTime = If($assignmentDefinition.UseLocalTime -ieq 'true' -or $assignmentDefinition.UseLocalTime -eq $true) { $true } else { $false }
            }

            if($targetType -eq 'Group')
            {
                $assignParamSplatting.Add('EntraIDGroupID', $assignmentDefinition.GroupId)
            }
            
            if(-NOT ([string]::IsNullOrEmpty($assignmentDefinition.AvailableTime)))
            {
                $assignParamSplatting.Add('StartDateTime', [DateTime]::Parse($assignmentDefinition.AvailableTime))
            }

            if(-NOT ([string]::IsNullOrEmpty($assignmentDefinition.DeadlineTime)))
            {
                $assignParamSplatting.Add('DeadlineDateTime', [DateTime]::Parse($assignmentDefinition.DeadlineTime))
            }

            New-IntuneWin32AppAssignment @assignParamSplatting

        }
    }

}


Write-Host "Script completed."