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





#******************************************************************#
#region                   Main script
#******************************************************************#

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