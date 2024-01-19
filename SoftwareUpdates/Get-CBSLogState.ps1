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
    Script to search for string: "Mark store corruption flag because of package" in all CBS.log files.
    
.DESCRIPTION
    Script to search for string: "Mark store corruption flag because of package" in all CBS.log files.
    The script will also unpack each CAB file if enough space is free and will also look into those files. 

    Source: https://github.com/jonasatgit/scriptrepo

.EXAMPLE
    Get-CBSLogState.ps1

.EXAMPLE
    Get-CBSLogState.ps1 -Verbose

.INPUTS
   None

.OUTPUTS
   Array of strings

.LINK
    https://github.com/jonasatgit/scriptrepo
#>
[CmdletBinding()]
param()

Write-Verbose 'Start of script'
$tempExtractionFolderPath = "$($env:SystemRoot)\Temp"
$cbsLogsList = Get-ChildItem -Path "$($env:SystemRoot)\Logs\CBS"

$searchString = '(Mark store corruption flag because of package)|(Installation fails with store corruption)|(CBS Failed to bulk stage deployment manifest)|(0x800f0831)|(0x80073701)|(ERROR_SXS_ASSEMBLY_MISSING)|(CBS_E_STORE_CORRUPTION)'
Write-Verbose "Searchstring: `"$($searchString)`""
$resultStringList = New-Object System.Collections.ArrayList
$extractionFolderName = 'CAB-{0}' -f (Get-Date -Format 'yyyyMMdd-hhmm')
$tempExtractionFolder = '{0}\{1}' -f $tempExtractionFolderPath, $extractionFolderName
foreach ($cbsLogFile in $cbsLogsList)
{
    Write-Verbose "Working on file: `"$($cbsLogFile.Name)`""
    if (-NOT ($resultStringList))
    {
        # Work through the files until we find a corrupt package
        # First we might need to unpack a cab file
        if ($cbsLogFile.Extension -eq '.cab')
        {
            # We need to unpack the cab first and also make sure we are not filling up volume C:
            # Assuming compression ratio is quite good and the actual file size is just 2% of the original file
            # Means: (filesize in bytes / 2(%)) * 100 (%)
            $approxRequiredSpace = ($cbsLogFile.Length / 2) * 100
            # Also adding 512MB just to make sure we are not filling up the volume
            $approxRequiredSpace = $approxRequiredSpace + 512MB
            
            $driveLetter = ($($env:SystemRoot) | Split-Path)  -replace '\\'
            $osDrive = Get-WmiObject -Query "SELECT * FROM Win32_Volume WHERE DriveLetter = '$($driveLetter)'" -ErrorAction Stop
            if ($osDrive.FreeSpace -gt $approxRequiredSpace)
            {                    
                if (-NOT(Test-Path $tempExtractionFolder))
                {
                    $null = New-Item -Path $tempExtractionFolderPath -Name $extractionFolderName -ItemType Directory -Force
                }

                if (Test-path "$($env:SystemRoot)\System32\expand.exe")     
                {
                    Write-Verbose "Will unpack: `"$($cbsLogFile.Name)`" to: `"$($tempExtractionFolder)`""
                    try 
                    {
                        $argumentList = '{0} -F:* {1}' -f ($cbsLogFile.FullName), $tempExtractionFolder
                        Start-Process -FilePath "$($env:SystemRoot)\System32\expand.exe" -ArgumentList $argumentList -WindowStyle Hidden -Wait -ErrorAction Stop
                    }
                    catch 
                    { 
                        $resultString = "Start-Process $($env:SystemRoot)\System32\expand.exe failed"
                        [void]$resultStringList.Add($resultString)
                    }

                    $Matches = $null
                    # Filename extension will still be CAB, but since it is a txt file after using expand.exe, select-String will be able to read it. 
                    # So, no need to rename the files to name.log
                    $itemsToParse = Get-ChildItem -Path $tempExtractionFolder
                }
                else 
                {
                    $resultString = "Path not found: $($env:SystemRoot)\System32\expand.exe"
                    [void]$resultStringList.Add($resultString)
                }
            }
            else 
            {
                $resultString = "Not able to proceed. Too little space on $($driveLetter) left"
                [void]$resultStringList.Add($resultString)
            }  
        }
        else
        {
            # Nothing to unpack. Just a regular CBS.log file
            $itemsToParse = $cbsLogFile
        }

        # Start string search  
        Write-Verbose "Looking for strings in file..."
        [array]$searchResult = $itemsToParse | Select-String -Pattern $searchString
        if ($searchResult)
        {
            foreach($result in $searchResult)
            {
                $Matches = $null
                if ($result.Line -imatch '(?<ArticleID>KB\d+)') # looking for KB number
                {
                    $resultString = 'Missing: {0} File: {1}' -f $Matches.ArticleID, ($result.Filename)
                    [void]$resultStringList.Add($resultString)
                }
                elseif ($result.Line -imatch '(Installation fails with store corruption)') # looking for specific string
                {
                    $resultString = 'CBS store needs to be rebuild, because installation fails with store corruption'
                    [void]$resultStringList.Add($resultString)
                }
                elseif ($result.Line -imatch '(0x800f0831)') # looking for specific error code
                {
                    $resultString = 'CBS store needs to be rebuild, because of error 0x800f0831'
                    [void]$resultStringList.Add($resultString)
                }
                elseif ($result.Line -imatch '(0x80073701)') # looking for specific error code
                {
                    $resultString = 'CBS store needs to be rebuild, because of error 0x80073701'
                    [void]$resultStringList.Add($resultString)
                }
                else
                {
                    $resultString = 'CBS store needs to be rebuild' # All other problems
                    [void]$resultStringList.Add($resultString)
                }
            }
        }

        # lets cleanup the temp folder and make space for the next cab file
        if (Test-Path $tempExtractionFolder)
        {
            Get-ChildItem -Path $tempExtractionFolder | Remove-Item -Force -ErrorAction SilentlyContinue
        }

    }
}

# Let's cleanup
if (Test-Path $tempExtractionFolder)
{
    $null = Remove-Item -Path $tempExtractionFolder -Recurse -Force -ErrorAction SilentlyContinue
}

if (-NOT($resultStringList))
{
    $resultString = 'Search strings not found. CBS store might be okay'   
    [void]$resultStringList.Add($resultString)
}

$resultStringList | Select-Object -Unique			  
Write-Verbose 'End of script'
