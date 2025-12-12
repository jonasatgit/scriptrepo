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

    try 
    {
        if(([regex]::match($ContentVersionsFiles.uploadState, '(.+?)(?=failed|timedout)',1)).value)
        {            
            Write-Host ($ContentVersionsFiles | ConvertTo-Json -Depth 10 -ErrorAction SilentlyContinue)
            Write-Warning "Upload state indicates failure or timeout. Skipping uploading full app package"
            Continue
        }
    }
    catch 
    {
        Write-Warning "Error checking upload state: $_"
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