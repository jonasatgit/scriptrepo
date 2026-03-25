<#
.SYNOPSIS
Script to create Intune Win32 application packages and upload them to a storage account.

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

.PARAMETER FileShareUrl
    The URL of the Azure File Share folder to copy from (e.g., https://mystorageaccount.file.core.windows.net/myshare/myfolder).

.PARAMETER LocalDownloadPath
    The local path where the content from the storage account should be downloaded to be able to test the application installation from the local path. (e.g., C:\Temp\AppTestDownload)

#>
[CmdletBinding()]
param
(
    [string]$AppFolderName,
    [string]$TemplateFolderName,
    [string]$AppsToProcessFile,
    [string]$AppStorageAccountName,
    [switch]$TestStorageAccountFolder,
    [string]$FileShareUrl,
    [string]$LocalDownloadPath='C:\Temp\AppTestDownload',
    $CopyAppsFromFileShare
)


#region MAIN SCRIPT

# load base functions
. "$PSScriptRoot\Invoke-BaseFunctions.ps1"


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

if (-Not (Test-Path -Path $fileInPath)) 
{
    Write-Error "Apps to process file not found at path: `"$fileInPath`""
    Exit 1
}

[array]$appMetadata = Import-Clixml -Path $fileInPath -ErrorAction "Stop"

# process each application
#Write-Host "##[section]Starting upload of $($appMetadata.Count) apps"
write-host "Found $($appMetadata.Count) apps to process."

#break
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

    <#
        Lets create subfolders
        Example of the folder structure:
    
        - Will contain the AppDeployToolkit files and the app installation files intended for installation
        ..\Adobe_AdobeReader_2021.007.20099_Rev01\App

        - Will contain the IntuneAppMetadata.json and Icon.png and any other Intune related data not required 
        in the app package intended for installation
        ..\Adobe_AdobeReader_2021.007.20099_Rev01\IntuneData
    #>
    $subFolders = @('App', 'IntuneData')
    foreach ($subFolder in $subFolders) 
    {
        $fullSubFolderPath = Join-Path -Path $tmpAppFolderPath -ChildPath $subFolder
        if (-not (Test-Path -Path $fullSubFolderPath)) 
        {
            New-Item -Path $fullSubFolderPath -ItemType Directory -ErrorAction "Stop" | Out-Null
            Write-Host "Created subfolder: $fullSubFolderPath"
        }
    }

    # copy AppDeployToolkit template into the app folder
    $templateSourcePath = '{0}\{1}\AppDeployToolkit' -f $sourceDirectory, $TemplateFolderName
    Copy-Item -Path $templateSourcePath\* -Destination "$tmpAppFolderPath\App" -Recurse -ErrorAction "Stop"
    Write-Host "Copied files from $templateSourcePath to $tmpAppFolderPath"

    # copy all files into the correct app folder
    $appSourcePath = '{0}\{1}\{2}' -f $sourceDirectory, $AppFolderName, $app.FolderName

    # Copy specific files into correct locations
    if(Test-Path -Path "$appSourcePath\Invoke-AppDeployToolkit.ps1")
    {
        Copy-Item -Path "$appSourcePath\Invoke-AppDeployToolkit.ps1" -Destination "$tmpAppFolderPath\App" -Force -ErrorAction Stop
    }
    else 
    {
        Write-Error "Invoke-AppDeployToolkit.ps1 not found in folder `"$appSourcePath`" for app $($app.FolderName)"
        Exit 1
    }

    if(Test-Path -Path "$appSourcePath\IntuneAppMetadata.json")
    {
        Copy-Item -Path "$appSourcePath\IntuneAppMetadata.json" -Destination "$tmpAppFolderPath\IntuneData" -Recurse -Force -ErrorAction Stop
    }
    else 
    {
        Write-Error "IntuneAppMetadata.json not found for app $($app.FolderName)"
        Exit 1
    }

    if(Test-Path -Path "$appSourcePath\Icon.png")
    {
        Copy-Item -Path "$appSourcePath\Icon.png" -Destination "$tmpAppFolderPath\IntuneData" -Recurse -Force -ErrorAction Stop
    }

    If (Test-Path -Path "$appSourcePath\detection.ps1")
    {
        Copy-Item -Path "$appSourcePath\detection.ps1" -Destination "$tmpAppFolderPath\IntuneData" -Recurse -Force -ErrorAction Stop
    }

    if (Test-Path -Path "$appSourcePath\requirement.ps1")
    {
        Copy-Item -Path "$appSourcePath\requirement.ps1" -Destination "$tmpAppFolderPath\IntuneData" -Recurse -Force -ErrorAction Stop
    }

    Write-Host "Copied files from $appSourcePath to $tmpAppFolderPath"

    # upload the app folder to the storage account
    $ContainerName = $app.StorageAccountFolderName
    $source = "$tmpAppFolderPath/*"
    $destination = "https://$AppStorageAccountName.blob.core.windows.net/$ContainerName"

    $result = Copy-DataFromOrToStorageAccount -Source $source -Destination $destination -TempDirectory $tempDirectory
    if ($result -ne $true) 
    {
        Write-Warning "Upload of app $($app.'StorageAccountFolderName') failed."
        Exit 1
    }

    # create app complete file to indicate that the app upload is complete
    $appCompleteFilePath = Join-Path -Path $tmpAppFolderPath -ChildPath "AppState.json"

    # create custom app state object with contentuploadtime and appuploadtime and write to json file
    $appStateTmpObject = [PSCustomObject]@{
        ContentUploadTimeUTC = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
        ContentHash     = $null
        IntuneAppUploadTimeUTC = $null
    }
    # create json state file to be uploaded
    $appStateTmpObject | ConvertTo-Json | Out-File -FilePath $appCompleteFilePath -Encoding utf8 -Force -ErrorAction "Stop"

    # upload the app complete file
    $source = $appCompleteFilePath
    $destination = "https://$AppStorageAccountName.blob.core.windows.net/$ContainerName/IntuneData/AppState.json"

    $result = Copy-DataFromOrToStorageAccount -Source $source -Destination $destination -TempDirectory $tempDirectory
    if ($result -ne $true) 
    {
        Write-Warning 'Copy AppState.json failed.'
        Exit 1
    }

    if(($CopyAppsFromFileShare -eq $true) -or ($CopyAppsFromFileShare -ieq 'true'))
    {
        # copy content from file share to blob storage if FileShareUrl parameter is provided
        if (-NOT ([string]::IsNullOrEmpty($FileShareUrl)))
        {
            Write-Host "Copying content from file share to blob storage as FileShareUrl parameter is provided..."
            $source = '{0}/Upload/{1}/*' -f $FileShareUrl, $app.FolderName 
            $destination = "https://$AppStorageAccountName.blob.core.windows.net/$ContainerName/App/Files"

            $result = Copy-DataFromOrToStorageAccount -Source $source -Destination $destination -TempDirectory $tempDirectory
            if ($result -ne $true) 
            {
                Write-Error "Failed to copy content from file share `"$source`" to storage account `"$destination`"."
                Exit 1
            }

            # create a file called "$app.FolderName".txt which contains azcopy command to login and copy the whole app from the storage account
            $destinationDownloadPath = Join-Path -Path $LocalDownloadPath -ChildPath "$($app.FolderName)"
            $contentSource = "https://$AppStorageAccountName.blob.core.windows.net/$ContainerName/*"

            # first create temp path to store the txt file in
            $tempTxtPath = Join-Path -Path $tempDirectory -ChildPath (Get-Date -Format 'yyyyMMddHHmmss')
            if (-not (Test-Path -Path $tempTxtPath)) 
            {
                New-Item -Path $tempTxtPath -ItemType Directory -ErrorAction "Stop" | Out-Null
                Write-Host "Created temporary folder for azcopy command file: $tempTxtPath"
            }

            # create a file called uploaded.txt in the file share to indicate that the content has been uploaded to blob storage and can be deleted from the file share
            $uploadedFilePath = '{0}/Upload/{1}/_Uploaded.txt' -f $FileShareUrl, $app.FolderName
            $source = "$tempTxtPath\_Uploaded.txt"
            "$(Get-Date -Format 'yyyyMMdd-HH:mm:ss') Content uploaded to blob storage, file share content can be deleted." | Out-File -FilePath $source -Encoding utf8 -Force -ErrorAction "Stop"
            # upload the file to the share into the upload folder
            $destination = $uploadedFilePath
            $result = Copy-DataFromOrToStorageAccount -Source $source -Destination $destination -TempDirectory $tempDirectory
            if ($result -ne $true) 
            {
                Write-Error "Failed to copy uploaded.txt file from `"$source`" to file share `"$destination`"."
                Exit 1
            }

            # create the txt file with the azcopy command to download the content from the storage account to a local path for testing purposes
            $tempTxtFile = '{0}\{1}.txt' -f $tempTxtPath, $app.FolderName
            
            # then output the azcopy login command to the txt file
            'azcopy login' | Out-File -FilePath $tempTxtFile -Encoding utf8 -Force -ErrorAction "Stop"
            # then output the azcopy copy command to the txt file
            $azCopyCommand = "azcopy copy `"$contentSource`" `"$destinationDownloadPath`" --recursive"
            $azCopyCommand | Out-File -FilePath $tempTxtFile -Encoding utf8 -Append -ErrorAction "Stop"

            Write-Host "Generated azcopy command to download the app content from the storage account to local path: $tempTxtFile"

            # we now need to copy the file to the share into the download folder
            $source = $tempTxtFile
            $destination = '{0}/Download/{1}.txt' -f $FileShareUrl, $app.FolderName
            $result = Copy-DataFromOrToStorageAccount -Source $source -Destination $destination -TempDirectory $tempDirectory
            if ($result -ne $true)
            {
                Write-Error "Failed to copy azcopy command file from `"$source`" to file share `"$destination`"."
                Exit 1
            }

            # remove temp azcopy command file
            if (Test-Path -Path $tempTxtPath)
            {
                Remove-Item -Path $tempTxtPath -Recurse -Force -ErrorAction "Stop"
                Write-Host "Removed temporary folder for azcopy command file: $tempTxtPath"
            }

        }
        else 
        {
            Write-Warning "FileShareUrl parameter not provided. Skipping copy of content from file share to blob storage."
        }
    }
    else 
    {
        Write-Host "Skipping copy of content from file share to blob storage as CopyAppsFromFileShare switch is not set."
    }

    # remove temp app folder
    if (Test-Path -Path $tmpAppFolderPath)
    {
        Remove-Item -Path $tmpAppFolderPath -Recurse -Force -ErrorAction "Stop"
        Write-Host "Removed temporary folder: $tmpAppFolderPath"
    }
    
}

Write-Host "Script completed."
#endregion