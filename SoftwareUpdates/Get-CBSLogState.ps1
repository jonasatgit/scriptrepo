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

.INPUTS
   None

.OUTPUTS
   String

.LINK
    https://github.com/jonasatgit/scriptrepo
#>
$tempExtractionFolderPath = "$($env:SystemRoot)\Temp"
$cbsLogsList = Get-ChildItem -Path "$($env:SystemRoot)\Logs\CBS"

$resultString = ''
$extractionFolderName = 'CAB-{0}' -f (Get-Date -Format 'yyyyMMdd-hhmm')
$tempExtractionFolder = '{0}\{1}' -f $tempExtractionFolderPath, $extractionFolderName
foreach ($cbsLogFile in $cbsLogsList)
{
    if (-NOT ($resultString))
    {
        # Work through the files until we find a corrupt package
        switch ($cbsLogFile.Extension) 
        {

            '.log' 
            {
                $Matches = $null
                $searchResult = $cbsLogFile | Select-String -Pattern 'Mark store corruption flag because of package'
                if ($searchResult)
                {
                    if ($searchResult.Line -match '(?<ArticleID>KB\d+)')
                    {
                        $resultString = $Matches.ArticleID
                    }
                }
            }

            '.cab' 
            {
                # We need to unpack the cab first and also make sure we are not filling up volume C:
                # Assuming compression ratio is quite good and the actual file size is just 2% of the original file
                # Means: (filesize in bytes / 2(%)) * 100 (%)
                $approxRequiredSpace = ($cbsLogFile.Length / 2) * 100
                # Also adding 512MB just to make sure we are not filling up the volume
                $approxRequiredSpace = $approxRequiredSpace + 536870912
                
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
                        try 
                        {
                            $argumentList = '{0} -F:* {1}' -f ($cbsLogFile.FullName), $tempExtractionFolder
                            Start-Process -FilePath "$($env:SystemRoot)\System32\expand.exe" -ArgumentList $argumentList -WindowStyle Hidden -Wait -ErrorAction Stop
                        }
                        catch 
                        { 
                            $resultString = "Start-Process $($env:SystemRoot)\System32\expand.exe failed"
                        }

                        $Matches = $null
                        # Filename extension will still be CAB, but since it is a txt file after using expand.exe, select-String will be able to read it. 
                        # So, no need to rename the files to name.log
                        $extractedCabFiles = Get-ChildItem -Path $tempExtractionFolder
                        $searchResult = $extractedCabFiles | Select-String -Pattern 'Mark store corruption flag because of package'
                        if ($searchResult)
                        {
                            if ($searchResult.Line -match '(?<ArticleID>KB\d+)')
                            {
                                $resultString = 'Missing: {0} File: {1}' -f $Matches.ArticleID, ($searchResult.Filename -replace '.cab', '.log')
                            }
                        }

                        $extractedCabFiles | Remove-Item -Force -ErrorAction SilentlyContinue
                    }
                    else 
                    {
                        $resultString = "Path not found: $($env:SystemRoot)\System32\expand.exe"
                    }
                }
                else 
                {
                    $resultString = "Not able to proceed. Too little space on $($driveLetter) left"
                }                
            }
        }
    }
}

# Let's cleanup
if (Test-Path $tempExtractionFolder)
{
    $null = Remove-Item -Path $tempExtractionFolder -Recurse -Force -ErrorAction SilentlyContinue
}

if (-NOT($resultString))
{
    $resultString = 'String not found: Mark store corruption flag because of package'   
}
						  


Write-Output $resultString
