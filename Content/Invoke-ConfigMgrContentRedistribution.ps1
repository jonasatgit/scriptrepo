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
<#
.SYNOPSIS
    Script to redistribute ConfigMgr content
.DESCRIPTION
    Script to redistribute ConfigMgr content
.PARAMETER SiteCode
    The site code of the ConfigMgr site
.PARAMETER ProviderServer
    The ConfigMgr provider server
#>
 
[CmdletBinding()]
param(
    [string]$SiteCode = 'P02',
    [string]$ProviderServer = 'CM02.contoso.local'
)
#region hash tables
# Possible package status states: https://learn.microsoft.com/en-us/mem/configmgr/develop/reference/core/servers/configure/sms_packagestatusdistpointssummarizer-server-wmi-class
$stateHashTable = @{
    0 = 'INSTALLED'
    1 = 'INSTALL_PENDING'
    2 = 'INSTALL_RETRYING'
    3 = 'INSTALL_FAILED'
    4 = 'REMOVAL_PENDING'
    5 = 'REMOVAL_RETRYING'
    6 = 'REMOVAL_FAILED'
    7 = 'CONTENT_UPDATING'
    8 = 'CONTENT_MONITORING'
}
# Possible types: https://learn.microsoft.com/en-us/mem/configmgr/develop/reference/core/servers/configure/sms_packagestatusdistpointssummarizer-server-wmi-class
$pkgTypeHashTable = @{
    0 = 'PKG_TYPE_REGULAR'
    3 = 'PKG_TYPE_DRIVER'
    4 = 'PKG_TYPE_TASK_SEQUENCE'
    5 = 'PKG_TYPE_SWUPDATES'
    6 = 'PKG_TYPE_DEVICE_SETTING'
    7 = 'PKG_TYPE_VIRTUAL_APP'
    8 = 'PKG_CONTENT_PACKAGE'
    257 = 'PKG_TYPE_IMAGE'
    258 = 'PKG_TYPE_BOOTIMAGE'
    259 = 'PKG_TYPE_OSINSTALLIMAGE'
}
 
# Possible message states
$messageStateHash = @{
    1 = 'SUCCESS'
    2 = 'PENDING'
    3 = 'ERRORMaybe'
}
#endregion
#region get dps
$query = "SELECT NALPath FROM SMS_SCI_SysResUse WHERE RoleName = 'SMS Distribution Point'"
[array]$DPList = Get-WmiObject -ComputerName $ProviderServer -Namespace "Root\SMS\Site_$SiteCode" -Query $query
$ServerName = @{label="ServerName";expression={$_.NALPath -replace '\["Display=\\' -replace '\\' -replace '"].*'}}
$dpSiteCode = @{label="SiteCode"; expression={$_.NALPath -replace '.*("SMS_SITE=.*").*', '$1' -replace '"' -replace 'SMS_SITE='}}
[array]$DPListWithName = $DPList | Select-Object $ServerName, $dpSiteCode -Unique
$dpSelection = $null
if ($DPListWithName)
{
    [array]$dpSelection = $DPListWithName | Sort-Object ServerName | Out-GridView -Title 'Please select one or multiple Distribution Points' -OutputMode Multiple  
}
else
{
    Write-Host 'No DPs found' -ForegroundColor Green
}
#endregion
#region redistribute content
if ($dpSelection)
{
    $dpContentList = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach($dp in $dpSelection)
    {
        Write-Host "Getting list of assigned content for DP: `"$($dp.ServerName)`"" -ForegroundColor Green
        $query = "select PackageID, Status, PackageType from SMS_DistributionPoint where ServerNALPath like '%$($dp.ServerName)%'"
        [array]$contentAssignedToDP = Get-WmiObject -ComputerName $ProviderServer -Namespace "Root\SMS\Site_$SiteCode" -Query $query
        Write-Host "Getting list of contentent from status summarizer for DP: `"$($dp.ServerName)`"" -ForegroundColor Green
        $query = "select PackageID, State from SMS_PackageStatusDistPointsSummarizer where ServerNALPath like '%$($dp.ServerName)%'"
        [array]$contentFromStatusSummarizer = Get-WmiObject -ComputerName $ProviderServer -Namespace "Root\SMS\Site_$SiteCode" -Query $query
        # create hashtable to be able to lookup fast
        $dpContentStatusSummarizerHash = @{}
        foreach($item in $contentFromStatusSummarizer)
        {
            if (-NOT $dpContentStatusSummarizerHash.ContainsKey($item.PackageID))
            {            
                $dpContentStatusSummarizerHash[$item.PackageID] = if($stateHashTable.[int]($item.State)){$stateHashTable.[int]($item.State)}else{'UNKNOWN'}
            }
        }
 
        Write-Host "Getting list of content status messages for DP: `"$($dp.ServerName)`"" -ForegroundColor Green
        $query = "SELECT DPName, PackageID, MessageState FROM SMS_DPStatusDetails WHERE DPName = '$($dpServername)' and PackageID <> ''"
        [array]$dpContentMessageStatusDetails = Get-WmiObject -ComputerName $ProviderServer -Namespace "Root\SMS\Site_$SiteCode" -Query $query
        # create hashtable to be able to lookup fast
        $dpContentStateMessageHash = @{}
        foreach($item in $dpContentMessageStatusDetails)
        {
            if (-NOT $dpContentStateMessageHash.ContainsKey($item.PackageID))
            {            
                $dpContentStateMessageHash[$item.PackageID] = if($messageStateHash[[int]$item.MessageState]){$messageStateHash[[int]$item.MessageState]}else{'UNKNOWN'}
            }
        }
 
        Write-Host "Getting overall DP status for DP: `"$($dp.ServerName)`"" -ForegroundColor Green
        $query = "SELECT * FROM SMS_DPStatusInfo Where Name = '$($dpServername)'"
        [array]$smsDPStatusInfo = Get-WmiObject -ComputerName $ProviderServer -Namespace "Root\SMS\Site_$SiteCode" -Query $query
 
        if($contentAssignedToDP.count -gt 0)
        {
            foreach($content in $contentAssignedToDP)
            {
              
                # DP status message state
                if($dpContentStateMessageHash[$content.PackageID])
                {
                    $DPPackageStatusMessageState = $dpContentStateMessageHash[$content.PackageID]      
                }
                else
                {
                    $DPPackageStatusMessageState = 'UNKNOWN'
                }
                
                # Summarizer state
                if($dpContentStatusSummarizerHash[$content.PackageID])
                {
                    $summarizerState = $dpContentStatusSummarizerHash[$content.PackageID]      
                }
                else
                {
                    $summarizerState = 'UNKNOWN'
                }
               
                # Get DP Status Info. This is the class that results in the pie diagram for each DP in the configMgr console
                if(($smsDPStatusInfo.NumberErrors -eq 0) -and ($smsDPStatusInfo.NumberInProgress -eq 0) -and ($smsDPStatusInfo.NumberUnknown -eq 0))
                {
                    $DPStatusInfoState = 'SUCCESS'
                }
                else
                {
                    $DPStatusInfoState = 'WARNING'   
                }
                            
                         
                # create temp object  
                $tmpObj = [pscustomobject][ordered]@{
                    Servername = $dp.ServerName
                    PackageID= $content.PackageID
                    Type = $pkgTypeHashTable.[int]($content.PackageType)
                    AssignedToDPState = $stateHashTable.[int]($content.Status)
                    SendToDPState = $summarizerState
                    SuccessMessageFromDPState = $DPPackageStatusMessageState
                    DPStatusInfoState = $DPStatusInfoState
                    OverallState = 'SUCCESS'
                }
              
                # add overall state to list
                if($tmpObj.AssignedToDPState -ine 'Installed')
                {
                    $tmpObj.OverallState = 'FAILED'
                }
 
                if($tmpObj.SendToDPState -ine 'Installed')
                {
                    $tmpObj.OverallState = 'FAILED'
                }              
                
                if($tmpObj.SuccessMessageFromDPState -ine 'Success')
                {
                    $tmpObj.OverallState = 'FAILED'
                }
               
                # If the main DP state is okay, we can assume that all content has been transferred but some states are not correct yet
                # That should also be fixed with a re-distribution, but is not a huge problem
                if(($tmpObj.DPStatusInfoState -ieq 'SUCCESS') -and ($tmpObj.OverallState -ieq 'FAILED'))
                {
                    $tmpObj.OverallState = 'WARNING'
                }
                elseif($tmpObj.DPStatusInfoState -ine 'SUCCESS')
                {
                    $tmpObj.OverallState = 'FAILED'
                }           
 
                # add item to list
                $dpContentList.add($tmpObj)             
            
            }     
        }
    }
    $title = 'Select packages for redistribution from a list of {0} packages. Current content jobs: {1}' -f $dpContentList.count, ($dpContentList | Where-Object {$_.OverallState -iin ('FAILED','WARNING')}).count
    [array]$selection = $dpContentList | Sort-Object ServerName, OverallState, PackageID | Out-GridView -Title $title -OutputMode Multiple
    # Lets re-distribute if we have a selection
    if ($selection)
    {
        foreach($package in $selection)
        {
            $query = "select * from SMS_DistributionPoint where PackageID='$($package.PackageID)' and ServerNALPath like '%$($package.ServerName)%'"
            $contentOnDP = Get-WmiObject -ComputerName $ProviderServer -Namespace "Root\SMS\Site_$SiteCode" -Query $query
            $contentOnDP.RefreshNow = $true
            Write-Host "Will refresh content with ID $($package.PackageID) on $($package.ServerName)..." -ForegroundColor Green
            $null = $contentOnDP.Put()
        }
    }      
    else
    {
        Write-Host 'No content selected' -ForegroundColor Green
    }  
}
else
{
    Write-Host 'No DP selected' -ForegroundColor Green
}
Write-Host 'End of script' -ForegroundColor Green
#endregion