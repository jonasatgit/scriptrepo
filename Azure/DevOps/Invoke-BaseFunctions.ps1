<#
.SYNOPSIS
Script with base functions used by other scripts.

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

The solution is also inspired by: https://msendpointmgr.com/intune-app-factory
#>


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
            #'CompanyName' = ''
            #'RegistryBrandingPath' = ''
            #'AppFullName' = ''
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

        # Do we have a requirement script?
        $pathToRequirementScript = '{0}\Requirement.ps1' -f ($FilePath | Split-Path -Parent)
        if (Test-Path $pathToRequirementScript)
        {
            $outObj.'IntuneRequirementScriptFound' = $true

            # Lets also check if we have a requiremet script defintion in the Intune metadata
            if ($outObj.IntuneMetadata.DetectionAndRequirementRules | Where-Object { $_.Type -eq 'Script' -and $_.RuleType -eq 'requirement' } )
            {
                # all good
            }
            else 
            {
                $outObj.DataMissingOrWrong = $true
                $outObj.CheckResults.Add('RequirementScriptInMetadata', "Requirement script found in app folder but no corresponding definition found in IntuneAppMetadata.json file.")
            }
        }

        # Do we have a detection script?
        $pathToDetectionScript = '{0}\Detection.ps1' -f ($FilePath | Split-Path -Parent)
        if (Test-Path $pathToDetectionScript)
        {
            $outObj.'IntuneDetectionScriptFound' = $true

            # Lets also check if we have a detection script defintion in the Intune metadata
            if ($outObj.IntuneMetadata.DetectionAndRequirementRules | Where-Object { $_.Type -eq 'Script' -and $_.RuleType -eq 'detection' } )
            {
                # all good
            }
            else 
            {
                $outObj.DataMissingOrWrong = $true
                $outObj.CheckResults.Add('DetectionScriptInMetadata', "Detection script found in app folder but no corresponding definition found in IntuneAppMetadata.json file.")
            }
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

            if ([string]::isNullOrEmpty($outObj.IntuneMetadata.InstallData.MaxRunTimeInMinutes))
            {
                $outObj.DataMissingOrWrong = $true
                $outObj.CheckResults.Add('MaxRunTimeInMinutes', "MaxRunTimeInMinutes is missing in IntuneMetadata")
            }
            else 
            {
                # must be an integer value greater than zero
                if (-not [int]::TryParse($outObj.IntuneMetadata.InstallData.MaxRunTimeInMinutes, [ref]$null) -or [int]$outObj.IntuneMetadata.InstallData.MaxRunTimeInMinutes -le 0)
                {
                    $outObj.DataMissingOrWrong = $true
                    $outObj.CheckResults.Add('MaxRunTimeInMinutesValue', "MaxRunTimeInMinutes has an invalid value in IntuneMetadata. It must be an integer greater than zero.")
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

            # lets make sure we have at least one detection rule defined
            if (-Not ($outObj.IntuneMetadata.DetectionAndRequirementRules | where-object { $_.RuleType -ieq 'detection' }))
            {
                $outObj.DataMissingOrWrong = $true
                $outObj.CheckResults.Add('NoDetectionRules', "No detection rules defined in IntuneMetadata")
            }

        }
        else 
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('InstallData', "InstallData section is missing in IntuneMetadata")
        }

        # lets validate the detection rules for duplicates in case of script detection rules
        [array]$detectionItems = $outObj.IntuneMetadata.DetectionAndRequirementRules | Where-Object { $_.RuleType -ieq 'detection' } 
        if ($detectionItems.Type.Count -gt 1 -and $detectionItems.Type -contains 'Script') 
        {
            $outObj.DataMissingOrWrong = $true
            $outObj.CheckResults.Add('MultipleDetectionRulesWithScript', "Multiple detection rules found in IntuneMetadata including a script rule. Intune does not support multiple detection rules when a script rule is used at the moment.")
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

<#
.SYNOPSIS
    Function to test if the storage account folder for the app exists, and create it if it does not exist.
.DESCRIPTION
    The function will test if the storage account folder for the app exists, and create it if it does not exist.
    The function will return the app info object with the StorageAccountFolderState property set to 'Exists', 'Missing', or 'ErrorCreating'.
.PARAMETER AppInfo
    The app info object.
.PARAMETER AppStorageAccountName
    The name of the storage account.
.PARAMETER CreateIfNotExists
    Switch to create the storage account folder if it does not exist.
.PARAMETER TempDirectory
    The temporary directory to store azcopy.exe.
.EXAMPLE
    Test-StorageAccountFolder -AppInfo $appInfo -AppStorageAccountName "mystorageaccount" -CreateIfNotExists -TempDirectory "C:\Temp"
    This example will test if the storage account folder for the app exists, and create it if it does not exist.
#>
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
#endregion

#region Function Copy-DataFromOrToStorageAccount
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
#endregion


#region Function Get-BlobHashData
<#
.SYNOPSIS
    Function to get blob hash data from a storage account container.   
.DESCRIPTION
    The function will get the blob hash data from a storage account container.
    The function will return a custom object with the blob name and blob hash in base64 format.
.PARAMETER ContainerName
    The name of the storage account container.
.PARAMETER StorageAccountName
    The name of the storage account.
.EXAMPLE
    Get-BlobHashData -ContainerName "mycontainer" -StorageAccountName "mystorageaccount"
    This example will get the blob hash data from the specified container and storage account.
#>
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

    if ($null -ne $comparisonValue -and $comparisonValue -ne "") 
    {
        $Rule.comparisonValue = $comparisonValue
    }
    else 
    {
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

        [parameter(Mandatory = $false)]
        [string]$productVersion
    )

    $Rule = @{}
    $Rule."@odata.type" = "#microsoft.graph.win32LobAppProductCodeRule"
    $Rule.ruleType = $ruleType
    $Rule.productCode = $productCode
    $Rule.productVersionOperator = $productVersionOperator
    
    if ($null -ne $productVersion -and $productVersion -ne "") 
    {
        $Rule.productVersion = $productVersion
    }
    else 
    {
        $Rule.productVersion = $null
    }

    return $Rule
}

<#
.SYNOPSIS
Creates a new registry rule.
IMPORTANT: This function has been altered from the original sample

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

        [parameter(Mandatory = $true, HelpMessage = "The operation data check type (data type returned from the registry entry).")]
        [ValidateSet('notConfigured','exists', 'doesNotExist', 'string', 'integer', 'version')]
        [string]$operationType,

        [parameter(Mandatory = $true)]
        [ValidateSet('notConfigured','equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual')]
        [string]$operator,

        [parameter(Mandatory = $false)]
        [string]$comparisonValue,

        [parameter(Mandatory = $true)]
        [bool]$check32BitOn64System
    )

    $Rule = @{}   
    $Rule."@odata.type" = "#microsoft.graph.win32LobAppRegistryRule"

    if ($null -ne $comparisonValue -and $comparisonValue -ne "") 
    {
        $Rule.comparisonValue = $comparisonValue
    }
    else 
    {
        $Rule.comparisonValue = $null
    }

    $Rule.ruleType = $ruleType
    $Rule.keyPath = $keyPath
    $Rule.valueName = $valueName
    $Rule.operationType = $operationType
    $Rule.operator = $operator
    $Rule.comparisonValue = $comparisonValue
    $Rule.check32BitOn64System = $check32BitOn64System

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

    if (-Not (Test-Path "$ScriptFile")) 
    {
        Write-Warning "Could not find file '$ScriptFile'..." 
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
        [ValidateSet('string', 'dateTime', 'integer', 'float', 'version', 'boolean')]
        [string]$OperationType,

        [parameter(Mandatory = $true)]
        [ValidateSet('equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual')]
        [string]$Operator,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComparisonValue
    )

    if (-Not (Test-Path "$ScriptFile")) 
    {
        Write-Warning "Could not find file '$ScriptFile'..." 
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
        [Bool]$AllowAvailableUninstall,

        [parameter(Mandatory = $false, ParameterSetName = "EXE")]
        [int]$MaxRunTimeInMinutes = 60
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
            "maxRunTimeInMinutes"   = $MaxRunTimeInMinutes
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

#region Get-EntraIDGroupByDisplayName
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
#endregion

#region New-IntuneWin32AppAssignment
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
        if ($Intent -ieq "Available")
        {
            # use local time cannot be set when intent is Available
            $installTimeSettings['useLocalTime'] = $false
        }
        else 
        {
            $installTimeSettings['useLocalTime'] = $UseLocalTime
        }
        
    }

    if ($DeadlineDateTime)
    {
        if ($Intent -ieq "Available")
        {
            # Deadline cannot be set when intent is Available
            $installTimeSettings['deadlineDateTime'] = $null
        }
        else 
        {
            $installTimeSettings['deadlineDateTime'] = $DeadlineDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }        
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
#endregion

#region Test-IfAppExistsInIntune
<#
.SYNOPSIS
    Function to test if an app exists in Intune by its display name.
.DESCRIPTION
    This function checks if an app with the specified display name already exists in Intune using the Microsoft Graph API.
    If the app exists, it updates the AppInfo object to indicate that data is missing or wrong and adds a check result.
.PARAMETER AppInfo
    An object containing information about the app, including the FolderName property which is used as the
    display name to check in Intune.
.EXAMPLE
    Test-IfAppExistsInIntune -AppInfo $appInfo
    This will check if an app with the display name specified in $appInfo.FolderName exists in Intune.
#>
Function Test-IfAppExistsInIntune
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [object]$AppInfo
    )

    Begin
    {
        # making sure we are connected to Microsoft Graph by getting the graph context
        if($null -eq (Get-MgContext))
        {
            try
            {
                Write-Host "Not connected to Microsoft Graph. Trying to connect using existing session..."
                $null = Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
                Write-Host "Connected to Microsoft Graph."
            }
            catch 
            {
                Write-Host "Microsoft Graph connection failed."
                Write-Host "Error details: $($_)"
                exit 1
            }
        }
    }
    Process
    {
        $AppDisplayName = $AppInfo.FolderName

        Write-Host "Will check if app with displayName `"$AppDisplayName`" already exists in Intune"
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=displayName eq '$AppDisplayName'&`$select=id,displayName"
        [array]$appResult = Invoke-MgGraphRequest -Uri $uri -Method Get -ErrorAction Stop -OutputType PSObject       

        if ($appResult.value.count -eq 0)
        {
            # app does not exist
            Write-Host "No app found in Intune with displayName `"$AppDisplayName`""
        }
        elseif ($appResult.value.count -ge 1) 
        {
            $AppInfo.DataMissingOrWrong = $true
            $AppInfo.CheckResults.Add("AppExistance", "Application already exists in Intune")
        }
        return $AppInfo
    }
    End
    {        
    }
}
#endregion