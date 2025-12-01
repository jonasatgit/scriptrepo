<#
.SYNOPSIS
Script to analyze apps

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

.PARAMETER FailIfDataMissingOrWrong
    To indicate if the script should fail if data is missing or wrong in the app metadata.
#>


[CmdletBinding()]
param
(
    [string]$AppFolderName,
    [string]$TemplateFolderName,
    [string]$AppsToProcessFile,
    [string]$AppStorageAccountName,
    [switch]$TestStorageAccountFolder,
    $FailIfDataMissingOrWrong
)


#region Function Get-HashtablesFromScript
<#
.SYNOPSIS
    Function to read the hashtable data from an Invoke-AppDeployToolkit.ps1 or Deploy-Application.ps1 script.

.DESCRIPTION
    The function will read data from an Invoke-AppDeployToolkit.ps1 or Deploy-Application.ps1 script
    and return a custom object with all the properties we need to create the Intune app.    

.PARAMETER FilePath
    The path to the Invoke-AppDeployToolkit.ps1 script file.

.EXAMPLE
    Get-HashtablesFromScript -File (Get-Item -Path "C:\IntuneApps\7-Zip-20241217\Invoke-AppDeployToolkit.ps1")

    This example will read from ADT script files.
#>
function Get-HashtablesFromScript
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [object]$File
    )

    process 
    {
        Write-Host "Processing app: $($File.DirectoryName | Split-Path -Leaf)" 

        $FilePath = $File.FullName
        # detect the version of the script
        $version = ''
        $scriptName = $FilePath | Split-Path -Leaf
        switch ($scriptName) 
        {
            "Invoke-AppDeployToolkit.ps1" { $version = 'v4' }
            "Deploy-Application.ps1" { $version = 'v3' }
        }    
        
        # Create the output object with all properties we want to extract
        $outObj = [PSCustomObject][ordered]@{
            'DataMissingOrWrong' = $false # Will be set to true if we have all what we need to create the Intune app
            #'FilePath' = $FilePath
            'FolderName' = ($FilePath | Split-Path -Parent | Split-Path -Leaf)
            'ADT-Version' = $version
            'ADT-AppName' = ''            
            'ADT-AppVendor' = ''            
            'ADT-AppVersion' = ''
            'ADT-AppArch' = ''
            'ADT-AppLang' = ''
            'ADT-AppRevision' = ''
            'ADT-AppSuccessExitCodes' = @(0) # set default values
            'ADT-AppRebootExitCodes' = @(1641, 3010) # set default values
            'ADT-AppProcessesToClose' = @()
            'ADT-AppScriptVersion' = ''
            'ADT-DeployAppScriptVersion' = ''
            'ADT-AppScriptDate' = ''
            'ADT-AppScriptAuthor' = ''
            'ADT-InstallName' = ''
            'ADT-InstallTitle' = ''
            'CompanyName' = ''
            'RegistryBrandingPath' = ''
            'AppFullName' = ''
            'AppIconFound' = $false
            'StorageAccountFolderName' =  ($FilePath | Split-Path -Parent | Split-Path -Leaf).ToLower() -replace '\.', '-' -replace '_', '-'
            'StorageAccountFolderState' = 'Unknown' 
            'IntuneMetadata' = $null # Will be set to the content of the IntuneAppMetadata.json file if found
            'IntuneMetadataFound' = $false # Will be set to true if we find the IntuneAppMetadata script
            'IntuneDetectionScriptFound' = $false # Will be set to true if we find a detection script in the ADT script
            'IntuneRequirementScriptFound' = $false # Will be set to true if we find a requirement script in the ADT script
            'CheckResults' = @{} # Will contain any issues found during the checks
            ID = (New-Guid).Guid # Add ID to the object to be able to identify it later
        } 

        # build the $propertyList by enumerating the properties of $outObj and exluding some we dont need. 
        # We also need to remove the prefix 'adt-' to match the property names in the $adtSession hashtable
        # The ADT prefix is just for the admin to know where the property comes from
        # That way we only need to build the property list once when creating the $outObj
        $adtPropertyList = $outObj.PSObject.Properties | 
                                Where-Object { $_.Name -notin @('ID', 'FilePath','ADT-Version', 'DataMissingOrWrong','AppIconFound','StorageAccountFolderState','StorageAccountFolderName') } | 
                                    Where-Object { $_.Name -notmatch '^Intune' } |
                                        ForEach-Object { $_.Name -replace '^ADT-', '' } # remove the ADT- prefix. The prefix is just for the admin to know where the property comes from

        # Read the content of the file
        $fileContent = Get-Content -Path $FilePath -Raw

        # Actions for version 4
        if ($version -eq 'v4')
        {
            # Extract the first hashtable called $adtSession
            # We will use the string to run Invoke-Expression to convert it to a hashtable and extract the values we need
            # We need "DeployAppScriptVersion" come after any other hashtables for the regex to work
            # Because the last } will be the one that closes the $adtSession hashtable and cannot close before
            $adtSessionPattern = '(?s)\$adtSession\s*=\s*@\{.*?DeployAppScriptVersion.*?\}'
            $adtSessionMatch = $null
            $adtSessionMatch = [regex]::Match($fileContent, $adtSessionPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($adtSessionMatch.Success) 
            {
                # we will now have the content of the hashtable in $adtSessionContent 
                # and will use Invoke-Expression to convert it to an actual hashtable we can use in this script
                $adtSessionContent = $adtSessionMatch.Value

                Invoke-Expression -Command $adtSessionContent -OutVariable adtSession

                # Add values to $outObj from $adtSession
                foreach ($property in $adtPropertyList)
                {
                    if ($adtSession.ContainsKey($property))
                    {
                        $outObj."ADT-$property" = $adtSession[$property]
                    }
                }
            } 
            else 
            {
                Write-Error "Failed to extract `$adtSession hashtable."
                return
            }

            if ($null -eq $adtSessionContent) 
            {
                Write-Error "Failed to extract `$adtSession hashtable."
                return
            }

            # Extract the second hashtable called $customSessionData
            # We will use the string to run Invoke-Expression to convert it to a hashtable and extract the values we need
            # We need "DeployAppScriptVersion" come after any other hashtables for the regex to work
            # Because the last } will be the one that closes the $adtSession hashtable and cannot close before
            $customSessionPattern = '(?s)\$customSessionData\s*=\s*@\{.*?## DO NOT REMOVE THIS COMMENT - Custom Session Data Marker.*?\}'
            $customSessionMatch = $null
            $customSessionMatch = [regex]::Match($fileContent, $customSessionPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($customSessionMatch.Success) 
            {
                # we will now have the content of the hashtable in $customSessionData
                # and will use Invoke-Expression to convert it to an actual hashtable we can use in this script
                $customSessionContent = $customSessionMatch.Value

                Invoke-Expression -Command $customSessionContent -OutVariable customSessionData 

                # Add values to $outObj from $customSessionData
                foreach ($property in $adtPropertyList)
                {
                    if ($customSessionData.ContainsKey($property))
                    {
                        $outObj.$property = $customSessionData[$property]
                    }
                }
            } 
            else 
            {
                Write-Error "Failed to extract `$customSessionData hashtable."
                return
            }

            if ($null -eq $customSessionContent) 
            {
                Write-Error "Failed to extract `$customSessionData hashtable."
                return
            }



        }
        elseif ($version -eq 'v3') 
        {
            foreach ($property in $adtPropertyList) 
            {
                # Extraction of individual properties using regex. Since in v3 we dont have a single hashtable
                $adtSessionMatch = $null
                $adtSessionPattern = "`$?$property\s*=\s*(?<string>.*)(['`"]?)"
                $adtSessionMatch = [regex]::Match(($fileContent -replace '\[Version\]'), $adtSessionPattern,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if ($adtSessionMatch.Success) 
                {
                    #Write-host '--------'
                    #Write-Host (($adtSessionMatch.Groups['string'].Value) -replace "['`"]")
                    $outObj."ADT-$property" = ($adtSessionMatch.Groups['string'].Value) -replace "['`"]"
                }
            }              
        }
        else 
        {
            Write-Error "Unsupported script version. Only Invoke-AppDeployToolkit.ps1 (v4) and Deploy-Application.ps1 (v3) are supported."
            return
        }

        
        # Lets now load the data from the IntuneAppMetadata.json file if it exists
        # That file is always the same not matter what version of ADT we use
        # The file must be in the same folder as the ADT script file
        $filePathIntuneAppMetadata = '{0}\IntuneAppMetadata.json' -f ($FilePath | Split-Path -Parent)
 
        if (Test-Path $filePathIntuneAppMetadata)
        {
            $outObj.'IntuneMetadata' = Get-Content -Path $filePathIntuneAppMetadata | ConvertFrom-Json
            $outObj.'IntuneMetadataFound' = $true
        } 
        else 
        {
            Write-Warning "Failed to find IntuneAppMetadata script file: $filePathIntuneAppMetadata"
            $outObj.'IntuneMetadataFound' = $true
        }    


        # we will now check if we have some basic data we need to create the Intune app
        # AppVendor, AppName, AppVersion, AppRevision
        if([string]::isNullOrEmpty($outObj.'ADT-AppName'))
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('AppName', "AppName is missing in file: $($FilePath | Split-Path -leaf)")
        }

        if([string]::isNullOrEmpty($outObj.'ADT-AppVersion'))
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('AppVersion', "AppVersion is missing in file: $($FilePath | Split-Path -leaf)")            
        }

        if([string]::isNullOrEmpty($outObj.'ADT-AppArch'))
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('AppArch', "AppArch is missing in file: $($FilePath | Split-Path -leaf)")            
        }

        if([string]::isNullOrEmpty($outObj.'ADT-AppVendor'))
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('AppVendor', "AppVendor is missing in file: $($FilePath | Split-Path -leaf)")
        }

        if([string]::isNullOrEmpty($outObj.'ADT-AppRevision'))
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('AppRevision', "AppRevision is missing in file: $($FilePath | Split-Path -leaf)")
        }

        if([string]::isNullOrEmpty($outObj.'ADT-InstallName'))
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('InstallName', "InstallName is missing in file: $($FilePath | Split-Path -leaf)")
        }

        if([string]::isNullOrEmpty($outObj.'ADT-InstallTitle'))
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('InstallTitle', "InstallTitle is missing in file: $($FilePath | Split-Path -leaf)")
        }

        if([string]::isNullOrEmpty($outObj.'CompanyName'))
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('CompanyName', "CompanyName is missing in file: $($FilePath | Split-Path -leaf)")
        }

        if([string]::isNullOrEmpty($outObj.'RegistryBrandingPath'))
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('RegistryBrandingPath', "RegistryBrandingPath is missing in file: $($FilePath | Split-Path -leaf)")
        }

        if([string]::isNullOrEmpty($outObj.'AppFullName'))
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('AppFullName', "AppFullName is missing in file: $($FilePath | Split-Path -leaf)")
        }

        # Do we have a requirement script?
        $pathToRequirementScript = '{0}\requirement.ps1' -f ($FilePath | Split-Path -Parent)
        if (Test-Path $pathToRequirementScript)
        {
            $outObj.'IntuneRequirementScriptFound' = $true
        }

        # Do we have a detection script?
        $pathToDetectionScript = '{0}\detection.ps1' -f ($FilePath | Split-Path -Parent)
        if (Test-Path $pathToDetectionScript)
        {
            $outObj.'IntuneDetectionScriptFound' = $true
        }

        # Do we have the install and uninstall commands in the Intune metadata?
        # We dont check if they are valid commands, just that they are not empty
        # we will also check if we have related data in the InstallData section
        if ($null -ne $outObj.IntuneMetadata.InstallData)
        {
            if ([string]::isNullOrEmpty($outObj.IntuneMetadata.InstallData.InstallCommand))
            {
                $outObj.DataMissingOrWrong = $true
                $outObj.CheckResults.Add('InstallCommand', "InstallCommand is missing in IntuneMetadata")
            }

            if([string]::isNullOrEmpty($outObj.IntuneMetadata.InstallData.UninstallCommand))
            {
                $outObj.DataMissingOrWrong = $true
                $outObj.CheckResults.Add('UninstallCommand', "UninstallCommand is missing in IntuneMetadata")
            }

            if ([string]::isNullOrEmpty($outObj.IntuneMetadata.InstallData.SetupFIle))
            {
                $outObj.DataMissingOrWrong = $true
                $outObj.CheckResults.Add('SetupFIle', "SetupFIle is missing in IntuneMetadata")
            }
            else 
            {
                if($outObj.IntuneMetadata.InstallData.InstallCommand -notmatch [regex]::Escape($outObj.IntuneMetadata.InstallData.SetupFIle))
                {
                    $outObj.DataMissingOrWrong = $true
                    $outObj.CheckResults.Add('SetupFIleInInstallCommand', "SetupFIle is not referenced in InstallCommand in IntuneMetadata")
                }
            }

            if ([string]::isNullOrEmpty($outObj.IntuneMetadata.InstallData.InstallExperience))
            {
                $outObj.DataMissingOrWrong = $true
                $outObj.CheckResults.Add('InstallExperience', "InstallExperience is missing in IntuneMetadata")
            }
            else 
            {
                # the value must be one of: system, user
                if ($outObj.IntuneMetadata.InstallData.InstallExperience -notin @('system', 'user'))
                {
                    $outObj.DataMissingOrWrong = $true
                    $outObj.CheckResults.Add('InstallExperienceValue', "InstallExperience has an invalid value in IntuneMetadata. Valid values are: system, user")
                }
            }

            if ([string]::isNullOrEmpty($outObj.IntuneMetadata.InstallData.DeviceRestartBehavior))
            {
                $outObj.DataMissingOrWrong = $true
                $outObj.CheckResults.Add('DeviceRestartBehavior', "DeviceRestartBehavior is missing in IntuneMetadata")
            }
            else 
            {
                # the value must be one of: noRestart, basedOnReturnCode, forceRestart
                if ($outObj.IntuneMetadata.InstallData.DeviceRestartBehavior -notin @('noRestart', 'basedOnReturnCode', 'forceRestart'))
                {
                    $outObj.DataMissingOrWrong = $true
                    $outObj.CheckResults.Add('DeviceRestartBehaviorValue', "DeviceRestartBehavior has an invalid value in IntuneMetadata. Valid values are: noRestart, basedOnReturnCode, forceRestart")
                }
            }

            # AllowAvailableUninstall must be true or false
            if ([string]::isNullOrEmpty($outObj.IntuneMetadata.InstallData.AllowAvailableUninstall))
            {
                $outObj.DataMissingOrWrong = $true
                $outObj.CheckResults.Add('AllowAvailableUninstall', "AllowAvailableUninstall is missing in IntuneMetadata")
            }
            else 
            {
                if ($outObj.IntuneMetadata.InstallData.AllowAvailableUninstall -notin @('true', 'false'))
                {
                    $outObj.DataMissingOrWrong = $true
                    $outObj.CheckResults.Add('AllowAvailableUninstallValue', "AllowAvailableUninstall has an invalid value in IntuneMetadata. Valid values are: true, false")
                }
            }
        }
        else 
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('InstallData', "InstallData section is missing in IntuneMetadata")
        }

        # lets check if we have an icon file in the app folder
        $pathToIconFile = '{0}\icon.png' -f ($FilePath | Split-Path -Parent)
        if (Test-Path $pathToIconFile)
        {
            $outObj.'AppIconFound' = $true
        }
        else 
        {
            # need to determine if a mising icon is a problem or not
            #$outObj.'DataMissingOrWrong' = $true
        }

        return $outObj
    }
        
}
#endregion

#region Test-StorageAccountFolder
function Test-StorageAccountFolder
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [object]$AppInfo,
        [Parameter(Mandatory=$true)]
        [string]$AppStorageAccountName,
        [Parameter(Mandatory=$false)]
        [Switch]$CreateIfNotExists,
        [Parameter(Mandatory=$false)]
        [String]$TempDirectory = [System.IO.Path]::GetTempPath()
    )

    # process pipeline
    Begin
    {
        $null = Connect-AzAccount -Identity
        $storageContext = New-AzStorageContext -StorageAccountName $AppStorageAccountName -UseConnectedAccount -ErrorAction "Stop"
    }
    process 
    {
        $storageContainerName = $AppInfo.StorageAccountFolderName.ToLower()
        $container = Get-AzStorageContainer -Context $storageContext -Name $storageContainerName -ErrorAction SilentlyContinue
        if (-not $container) 
        {
            Write-Host "Storage container not found: $storageContainerName"
            $AppInfo.StorageAccountFolderState = 'Missing'
            if ($CreateIfNotExists) 
            {
                try 
                {
                    Write-Host "Creating storage container: $storageContainerName"
                    $null = New-AzStorageContainer -Context $storageContext -Name $storageContainerName -ErrorAction "Stop"
                    $AppInfo.StorageAccountFolderState = 'Exists'             
                }
                catch 
                {
                    Write-Warning "Failed to create storage container: $storageContainerName. Error: $($_.Exception.Message)"

                    if (($_ | Out-String) -match '403.*authorized') 
                    {
                        Write-Warning "403 Forbidden detected. Check if the managed identity has the correct permissions and storage account network settings."
                        Exit 1
                    }

                    Write-Warning "Full error: $($_ | Out-String)"

                    $AppInfo.StorageAccountFolderState = 'ErrorCreating'
                    $AppInfo.DataMissingOrWrong = $true
                    $AppInfo.CheckResults.Add("StorageContainerCreation", "Failed to create storage container: `"$($_)`"")
                }
            }
        }
        else 
        {
            $AppInfo.'StorageAccountFolderState' = 'Exists'
        }

        if ($CreateIfNotExists)
        {
            #--- Create & upload README.txt to App/Files (overwrite if it exists) ---
            try 
            {
                $readmeText = 'Place app files here'
                $blobName = 'App/Files/README.txt'   # two virtual folders: App -> Files

                # Create a temporary local file for upload
                $tempFile = [System.IO.Path]::Combine($TempDirectory, [System.IO.Path]::GetRandomFileName())
                Set-Content -Path $tempFile -Value $readmeText -Encoding UTF8

                # Upload and overwrite if it already exists (-Force)
                $paramSplatting = @{
                    File       = $tempFile
                    Container  = $storageContainerName
                    Blob       = $blobName
                    Context    = $storageContext
                    Properties = @{ ContentType = 'text/plain; charset=utf-8' }
                    Force      = $true
                    ErrorAction= 'Stop'
                }

                $null = Set-AzStorageBlobContent @paramSplatting

                # Cleanup local temp
                Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue

                Write-Host "README.txt uploaded to container '$storageContainerName' at '$blobName' (overwritten if existed)."
            }
            catch 
            {
                Write-Warning "Failed to upload README.txt to $storageContainerName/App/Files. Error: $($_.Exception.Message)"
                # not critical, so we just log it
            }
        }

        return $AppInfo
    }
    End
    {
    }
}


#******************************************************************#
#region                   Main script
#******************************************************************#

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

$appBasePath = '{0}\{1}' -f $sourceDirectory, $appFolderName
if (-Not (Test-Path -Path $appBasePath)) 
{
    Write-Error "App base path does not exist: $appBasePath"
    return
}


# load all app files possible
[array]$adtAppFileList = Get-ChildItem -Path $AppBasePath -Depth 1 -File | Where-Object {
    $_.Name -in @("Invoke-AppDeployToolkit.ps1", "Deploy-Application.ps1")
}

# load apps to process from csv file if it exists
[array]$appsToProcess = @()
$appsToProcessPath = '{0}\{1}' -f $sourceDirectory, $appsToProcessFile
if (Test-Path -Path $appsToProcessPath) 
{    
    $firstLine = Get-Content -Path $appsToProcessPath -TotalCount 1
    if ($firstLine -notmatch '\bAppFolderName\b') 
    {
        Write-Error "Header 'AppFolderName' is not present in the CSV."
        break
    }

    # Copy apps to process file to artifact staging directory. This will help to be able to analyze what apps were processed later
    Copy-Item -Path $appsToProcessPath -Destination $artifactStagingDirectory -Force -ErrorAction SilentlyContinue

    # Import the CSV file
    $appsToProcess = Import-Csv -Path $appsToProcessPath -ErrorAction Stop
    Write-Host "Loaded $($appsToProcess.Count) apps to process from file: $appsToProcessFile" 
} 
else 
{
    Write-Warning "Apps to process file not found. Will work with all apps."
}

if ($appsToProcess.AppFolderName.Count -gt 0) 
{
    # we have the folder names in $appsToProcess.AppFolderName
    # We now need to filter $adtAppFileList to only include those apps
    [array]$fileListToProcess = $adtAppFileList | Where-Object {
        $appFolderName = $_.DirectoryName | Split-Path -Leaf
        $appFolderName -in $appsToProcess.AppFolderName
    }
}
else 
{
    # add all apps
    [array]$fileListToProcess = $adtAppFileList
}


Write-Host "Working with $($fileListToProcess.Count) ADT script files"
if($fileListToProcess.Count -eq 0) 
{
    Write-Error "No ADT script files found in path"
    break
}

# Read the hashtable data from the script files to be able to select which apps to import.
# the result of the function is an array of custom objects with all the data we need
[array]$appList = $fileListToProcess | Get-HashtablesFromScript

if ($TestStorageAccountFolder)
{
    $appList = $appList | Test-StorageAccountFolder -AppStorageAccountName $AppStorageAccountName -CreateIfNotExists
}

# Save the app list to an xml file for later steps in the pipeline
$fileOutPath = '{0}\AppsToProcess.xml' -f $artifactStagingDirectory
$appList | Export-Clixml -Path $fileOutPath -Force

# we will also save the data as json for easier consumption and readability
$appList | ConvertTo-Json -Depth 10 | Out-File -FilePath ($fileOutPath -replace 'xml$', 'json') -Encoding utf8 -Force
Write-Host "App metadata for $($appList.Count) apps saved to xml and json"


# Check if any app has DataMissingOrWrong = $true
[array]$appsWithIssues = $appList | Where-Object { $_.DataMissingOrWrong -eq $true }
if ($appsWithIssues.Count -gt 0) 
{
    foreach ($appEntry in $appsWithIssues) 
    {
        Write-Host "------------------------------"
        Write-Host "App check results for: $($appEntry.FolderName)"
        foreach ($issue in $appEntry.CheckResults.GetEnumerator()) 
        {
            Write-Warning " - $($issue.Key): $($issue.Value)" 
        }
    } 
}
else 
{
    Write-Host "All apps have valid data."
}

# Fail the script if any app has DataMissingOrWrong = $true and the FailIfDataMissingOrWrong parameter is set
# might be bboolean or string 'true'
if (($FailIfDataMissingOrWrong -eq $true) -or ($FailIfDataMissingOrWrong -ieq 'true') -and $appsWithIssues.Count -gt 0)
{
    Write-Error "One or more apps have missing or wrong data."
    Exit 1
}
else 
{
    if ($appsWithIssues.Count -gt 0) 
    {
        Write-Warning "One or more apps have missing or wrong data."
        Write-Warning "FailIfDataMissingOrWrong is not set. Script will not fail with error."
    }    
}

# Show data in DevOps pipeline log
#Import-Clixml -Path $fileOutPath | ConvertTo-Json -Depth 10

<#
# Handle next stage execution or not if no applications are allowed to be processed
if ($PipelineAllowed -eq $false) {
    # Don't allow pipeline to continue
    Write-Output -InputObject "Required files are missing, aborting pipeline"
    Write-Output -InputObject "##vso[task.setvariable variable=shouldrun;isOutput=true]false"
}
else {
    # Allow pipeline to continue
    Write-Output -InputObject "Required files are present, pipeline can continue"
    Write-Output -InputObject "##vso[task.setvariable variable=shouldrun;isOutput=true]true"
}
#>



#******************************************************************#
#endregion