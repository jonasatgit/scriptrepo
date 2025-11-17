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

#>
[CmdletBinding()]
param
(
    [string]$AppFolderName,
    [string]$TemplateFolderName,
    [string]$AppsToProcessFile,
    [string]$AppStorageAccountName,
    [switch]$TestStorageAccountFolder
)


# To be able to unpack the intunewin file
$null = Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction Stop

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

function Get-BlobHashData
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$ContainerName,
        [Parameter(Mandatory=$true)]
        [string]$StorageAccountName
    )

    # process pipeline
    Begin
    {
        $null = Connect-AzAccount -Identity
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount -ErrorAction "Stop"
    }
    process 
    {
        $storageBlobs = Get-AzStorageBlob -Context $storageContext -Container $ContainerName -IncludeDeleted:$false -errorAction "Stop"

        # we need the blob name and the content hash. We then need to sort by hash and create a combined hash
        foreach ($blob in $storageBlobs) 
        {
            Write-Host '-----------'
            Write-Host $blob.Name
            try
            {
                $blobHashBase64 = [convert]::ToBase64String($blob.BlobProperties.ContentHash)
            }
            catch 
            {
                $blobHashBase64 = '0000' # happens if we have no content hash
            }

            [PSCustomObject]@{
                BlobName = $blob.Name
                BlobHashBase64 = $blobHashBase64
            }
        }
    }
}


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
        Write-Error "Invoke-AppDeployToolkit.ps1 not found for app $($app.FolderName)"
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

    # remove temp app folder
    if (Test-Path -Path $tmpAppFolderPath)
    {
        Remove-Item -Path $tmpAppFolderPath -Recurse -Force -ErrorAction "Stop"
        Write-Host "Removed temporary folder: $tmpAppFolderPath"
    }
    
}


Write-Host "Script completed."