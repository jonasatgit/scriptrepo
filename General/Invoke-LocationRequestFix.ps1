
<#
.Synopsis
  Script to fix stale Location Requests in ConfigMgr.

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

    This script will find and fix stale Location Requests in ConfigMgr.

    Can be used to remote export:
    $exportPath = "C:\temp"

    Get-CimInstance -Namespace ROOT\ccm\CMBITSManager -ClassName CCM_BITSManager_Job | Export-Clixml -Path "$($exportPath)\CCM_BITSManager_Job.xml"
    Get-CimInstance -Namespace ROOT\ccm\CMBITSManager -ClassName CCM_BITSManager_JobItem | Export-Clixml -Path "$($exportPath)\CCM_BITSManager_JobItem.xml"
    Get-CimInstance -Namespace ROOT\ccm\ContentTransferManager -ClassName CCM_CTM_JobStateEx4 | Export-Clixml -Path "$($exportPath)\CCM_CTM_JobStateEx4.xml"
    Get-CimInstance -Namespace ROOT\ccm\LocationServices -ClassName LocationRequestEx | Export-Clixml -Path "$($exportPath)\LocationRequestEx.xml"

#>

$CCMBITSManagerJobs = Get-CimInstance -Namespace "ROOT\ccm\CMBITSManager" -Query "Select * from CCM_BITSManager_Job" -ErrorAction SilentlyContinue
$CCMBITSManagerJobItems = Get-CimInstance -Namespace "ROOT\ccm\CMBITSManager" -Query "Select * from CCM_BITSManager_JobItem" -ErrorAction SilentlyContinue
$CCMCTMJobStates = Get-CimInstance -Namespace "ROOT\ccm\ContentTransferManager" -Query "Select * from CCM_CTM_JobStateEx4" -ErrorAction SilentlyContinue
$LocationRequests = Get-CimInstance -Namespace "ROOT\ccm\LocationServices" -Query "Select * from LocationRequestEx" -ErrorAction SilentlyContinue


$contentIDs = [System.Collections.Generic.List[pscustomobject]]::new()
# Cleanup BITS Manager Jobs and Job Items related to Defender updates
foreach ($BITSManagerJob in $CCMBITSManagerJobs)
{
    if([regex]::Matches($BITSManagerJob.DownloadManifest, '(?<=Source=")(AM_.*\.exe)|(MpSigStub.exe)'))
    {
        #Write-Host "Found Defender File"
        $contentIDs.Add($BITSManagerJob.ContentID)
        $BITSManagerJob | Remove-CimInstance -ErrorAction SilentlyContinue
    } 
}

# Cleanup BITS Manager Jobs and Job Items related to Defender updates
foreach ($BITSManagerJobItem in $CCMBITSManagerJobItems)
{
    if([regex]::Matches($BITSManagerJobItem.DownloadManifest, '(?<=Source=")(AM_.*\.exe)|(MpSigStub.exe)'))
    {
        #Write-Host "Found Defender File"
        $BITSManagerJobItem | Remove-CimInstance -ErrorAction SilentlyContinue
    } 
}

# Cleanup CTM Job States related to Defender updates
foreach ($CTMJobState in $CCMCTMJobStates)
{
    if([regex]::Matches($CTMJobState.DTSManifest, '(?<=Source=")(AM_.*\.exe)|(MpSigStub.exe)'))
    {
        #Write-Host "Found Defender File"
        $contentIDs.Add($CTMJobState.ContentID)
        $CTMJobState | Remove-CimInstance -ErrorAction SilentlyContinue
    } 
}

# Cleanup Location Requests related to Defender updates
foreach ($LocationRequest in $LocationRequests)
{
    foreach ($contentID in $contentIDs)
    {
        if ($LocationRequest.ContentID -eq $contentID)
        {
            #Write-Host "Found Location Request for ContentID: $($LocationRequest.ContentID). Removing..."
            $LocationRequest | Remove-CimInstance -ErrorAction SilentlyContinue
        }
    }
}

Restart-Service -Name ccmexec -Force -ErrorAction SilentlyContinue