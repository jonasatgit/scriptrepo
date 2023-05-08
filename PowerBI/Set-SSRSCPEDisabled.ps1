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

# Script to disable Customer Feedback in SQL Server Reporting Services
# Will also restart the service

$path = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\SSRS\CPE"
$ItemToChange_1 = 'CustomerFeedback'
$ItemToChange_2 = 'EnableErrorReporting'

if(-not(Test-Path $path))
{
    Write-Host "Path `"$path`" does not exist. Cannot disable Customer Feedback" -ForegroundColor Red
}
else
{
    New-ItemProperty -Path $path -Name $ItemToChange_1 -Value 0 -PropertyType DWORD -Force
    New-ItemProperty -Path $path -Name $ItemToChange_2 -Value 0 -PropertyType DWORD -Force
    Write-Host "Customer Feedback has been disabled!" -ForegroundColor Green

    Restart-Service SQLServerReportingServices -Force
    Write-Host "SQLServerReportingServices has been restarted!" -ForegroundColor Green
} 
