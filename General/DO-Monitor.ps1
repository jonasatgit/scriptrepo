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
# Source: https://github.com/jonasatgit/scriptrepo
# tiny script to monitor Delivery Optimization downloads in Powershell directly
# needs to be run as an admin

while ($true) {
    Clear-Host
    Get-DeliveryOptimizationStatus | Select-Object FileId, 
            PredefinedCallerApplication, 
            FileSize, 
            TotalBytesDownloaded,
            Status,
            @{Expression={"{0:N2}" -f $((100 / $_.FileSize) * $_.TotalBytesDownloaded)+"%"};Label="Total%"} | Format-Table -AutoSize
    Start-Sleep -Seconds 2
}
