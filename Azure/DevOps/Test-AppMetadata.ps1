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
#>


[CmdletBinding()]
param
(
    [string]$AppFolderName = 'AppsV2',
    [string]$TemplateFolderName = 'TemplatesV2',
    [string]$AppsToProcessFile = 'appsToProcess.csv',
    [string]$AppStorageAccountName,
    [switch]$TestStorageAccountFolder
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
            'FilePath' = $FilePath
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
            'AppIconFound' = $false
            'StorageAccountFolderName' =  ($FilePath | Split-Path -Parent | Split-Path -Leaf).ToLower() -replace '\.', '-' -replace '_', '-'
            'StorageAccountFolderState' = 'Unknown' 
            'IntuneMetadata' = $null # Will be set to the content of the IntuneAppMetadata.json file if found
            'IntuneMetadataFound' = $false # Will be set to true if we find the IntuneAppMetadata script
            'IntuneDetectionScriptFound' = $false # Will be set to true if we find a detection script in the ADT script
            'IntuneRequirementScriptFound' = $false # Will be set to true if we find a requirement script in the ADT script
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
            $outObj.'DataMissingOrWrong' = $true
            Write-Warning "AppName is missing in file: $FilePath"
        }

        if([string]::isNullOrEmpty($outObj.'ADT-AppVersion'))
        {
            $outObj.'DataMissingOrWrong' = $true
            Write-Warning "AppVersion is missing in file: $FilePath"
        }

        if([string]::isNullOrEmpty($outObj.'ADT-AppVendor'))
        {
            $outObj.'DataMissingOrWrong' = $true
            Write-Warning "AppVendor is missing in file: $FilePath"
        }

        if([string]::isNullOrEmpty($outObj.'ADT-AppRevision'))
        {
            $outObj.'DataMissingOrWrong' = $true
            Write-Warning "AppRevision is missing in file: $FilePath"
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
                $outObj.'DataMissingOrWrong' = $true
                Write-Warning "InstallCommand is missing in IntuneMetadata"
            }

            if([string]::isNullOrEmpty($outObj.IntuneMetadata.InstallData.UninstallCommand))
            {
                $outObj.'DataMissingOrWrong' = $true
                Write-Warning "UninstallCommand is missing in IntuneMetadata"
            }

            if ([string]::isNullOrEmpty($outObj.IntuneMetadata.InstallData.SetupFIle))
            {
                $outObj.'DataMissingOrWrong' = $true
                Write-Warning "SetupFIle is missing in IntuneMetadata"
            }
            else 
            {
                if($outObj.IntuneMetadata.InstallData.InstallCommand -notmatch [regex]::Escape($outObj.IntuneMetadata.InstallData.SetupFIle))
                {
                    $outObj.'DataMissingOrWrong' = $true
                    Write-Warning "SetupFIle is not part of the InstallCommand in IntuneMetadata"
                }
            }

            if ([string]::isNullOrEmpty($outObj.IntuneMetadata.InstallData.InstallExperience))
            {
                $outObj.'DataMissingOrWrong' = $true
                Write-Warning "InstallExperience is missing in IntuneMetadata"
            }
            else 
            {
                # the value must be one of: system, user
                if ($outObj.IntuneMetadata.InstallData.InstallExperience -notin @('system', 'user'))
                {
                    $outObj.'DataMissingOrWrong' = $true
                    Write-Warning "InstallExperience has an invalid value in IntuneMetadata. Valid values are: system, user"
                }
            }

            if ([string]::isNullOrEmpty($outObj.IntuneMetadata.InstallData.DeviceRestartBehavior))
            {
                $outObj.'DataMissingOrWrong' = $true
            }
            else 
            {
                # the value must be one of: noRestart, basedOnReturnCode, forceRestart
                if ($outObj.IntuneMetadata.InstallData.DeviceRestartBehavior -notin @('noRestart', 'basedOnReturnCode', 'forceRestart'))
                {
                    $outObj.'DataMissingOrWrong' = $true
                    Write-Warning "DeviceRestartBehavior has an invalid value in IntuneMetadata. Valid values are: noRestart, basedOnReturnCode, forceRestart"
                }
            }

            # AllowAvailableUninstall must be true or false
            if ([string]::isNullOrEmpty($outObj.IntuneMetadata.InstallData.AllowAvailableUninstall))
            {
                $outObj.'DataMissingOrWrong' = $true
                Write-Warning "AllowAvailableUninstall is missing in IntuneMetadata"
            }
            else 
            {
                if ($outObj.IntuneMetadata.InstallData.AllowAvailableUninstall -notin @('true', 'false'))
                {
                    $outObj.'DataMissingOrWrong' = $true
                    Write-Warning "AllowAvailableUninstall has an invalid value in IntuneMetadata. Valid values are: true, false"
                }
            }
        }
        else 
        {
            $outObj.'DataMissingOrWrong' = $true
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
        [Switch]$CreateIfNotExists
    )

    # process pipeline
    Begin
    {
        $null = Connect-AzAccount -Identity
        $storageContext = New-AzStorageContext -StorageAccountName $AppStorageAccountName -UseConnectedAccount -ErrorAction "Stop"
    }
    process 
    {
        $storageContainerName = $AppInfo.'StorageAccountFolderName'
        $container = Get-AzStorageContainer -Context $storageContext -Name $storageContainerName -ErrorAction SilentlyContinue
        if (-not $container) 
        {
            Write-Host "Storage container not found: $storageContainerName"
            $AppInfo.'StorageAccountFolderState' = 'Missing'
            if ($CreateIfNotExists) 
            {
                try 
                {
                    Write-Host "Creating storage container: $storageContainerName"
                    $null = New-AzStorageContainer -Context $storageContext -Name $storageContainerName -ErrorAction "Stop"
                    $AppInfo.'StorageAccountFolderState' = 'Exists'             
                }
                catch 
                {
                    $AppInfo.'StorageAccountFolderState' = 'ErrorCreating'
                    Write-Warning "Failed to create storage container: `"$($storageContainerName)`""
                    Write-Warning $_
                }
            }
        }
        else 
        {
            $AppInfo.'StorageAccountFolderState' = 'Exists'
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

# load apps to process from csv file if it exists
[array]$appsToProcess = @()
$appsToProcessPath = '{0}\{1}' -f $sourceDirectory, $appsToProcessFile
if (Test-Path -Path $appsToProcessPath) 
{
    $appsToProcess = Import-Csv -Path $appsToProcessPath
    Write-Host "Loaded $($appsToProcess.Count) apps to process from file" -ForegroundColor Cyan
} 
else 
{
    Write-Warning "Apps to process file not found."
}

if ($appsToProcess.Count -eq 0) 
{
    Write-Host "No apps to process loaded from file. Will process all apps found in path." -ForegroundColor Cyan
    [array]$fileList = Get-ChildItem -Path $AppBasePath -Depth 1 -File | Where-Object {
        $_.Name -in @("Invoke-AppDeployToolkit.ps1", "Deploy-Application.ps1")
    }
}
else 
{
    # only process apps listed in the csv file. The csv file will contain the folder names of the apps to process
    [array]$fileList = @()
    foreach ($app in $appsToProcess) 
    {
        $csvAppFolder = '{0}\{1}' -f $appBasePath, $app.AppFolderName
        if (-not (Test-Path -Path $csvAppFolder)) 
        {
            Write-Warning "App folder not found: $csvAppFolder"
            continue
        }
        
        # Check for ADT script files in order of preference
        $scriptFiles = @('Invoke-AppDeployToolkit.ps1', 'Deploy-Application.ps1')
        $foundScript = $false
        
        foreach ($scriptFile in $scriptFiles) 
        {
            $adtScriptPath = '{0}\{1}' -f $csvAppFolder, $scriptFile
            if (Test-Path -Path $adtScriptPath) 
            {
                $fileList += Get-Item -Path $adtScriptPath
                $foundScript = $true
                break
            }
        }
        
        if (-not $foundScript) 
        {
            Write-Warning "No ADT script file found in folder: $appFolder"
        }
    }
}


Write-Host "Found $($fileList.Count) ADT script files"
if($fileList.Count -eq 0) 
{
    Write-Error "No ADT script files found in path"
    return
}

# Read the hashtable data from the script files to be able to select which apps to import.
# The data will be displayed in an Out-GridView for selection.
[array]$appList = $fileList | Get-HashtablesFromScript


if ($TestStorageAccountFolder)
{
    $appList = $appList | Test-StorageAccountFolder -AppStorageAccountName $AppStorageAccountName -CreateIfNotExists
}

$fileOutPath = '{0}\AppsToProcess.xml' -f $artifactStagingDirectory
$appList | Export-Clixml -Path $fileOutPath -Force

# we will also save the data as json for easier consumption in later steps
$appList | ConvertTo-Json -Depth 10 | Out-File -FilePath ($fileOutPath -replace 'xml$', 'json') -Encoding utf8 -Force

# Show data in DevOps pipeline log
Import-Clixml -Path $fileOutPath | ConvertTo-Json -Depth 10

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