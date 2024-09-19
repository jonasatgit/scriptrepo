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

# Test script to get the log data from the Intune Management Extension log file
# The script will parse the log file and extract the JSON data from the log entries
# The script will then create a custom object for each JSON entry and add it to an array
# Like: Get-IMELogData.ps1 but way simpler

$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"

$Pattern = 'Get policies'
$out = Get-ChildItem $LogPath -Filter IntuneManagementExtension*.log | Select-String -Pattern $Pattern 
$outlines = [System.Collections.Generic.List[string]]::new()
$out.Line | ForEach-Object {

    $line = $_ -replace [regex]::Escape('<![LOG[Get policies = ')
    $line = $line -replace 'LOG]!>.*' -replace '.$'
    $outlines.Add($line)
}

[array]$uniqueLines = $outlines | Select-Object -Unique

Write-Host "Found $($outlines.count) policy entries" -ForegroundColor Cyan
Write-Host "Found $($uniqueLines.count) unique policy entrie/s" -ForegroundColor Cyan

$outObj = $uniqueLines[0] | ConvertFrom-Json 
$outObj | Out-GridView -Title 'App Policy'