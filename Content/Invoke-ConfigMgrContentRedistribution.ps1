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

.PARAMETER IncludeAlreadyInstalled
    Include packages that are already installed on the DP

#>


[CmdletBinding()]
param(
    [string]$SiteCode = 'P02',
    [string]$ProviderServer = 'cm02.contoso.local',
    [switch]$IncludeAlreadyInstalled
)




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
    0 =     'PKG_TYPE_REGULAR'
    3 =     'PKG_TYPE_DRIVER'
    4 =     'PKG_TYPE_TASK_SEQUENCE'
    5 =     'PKG_TYPE_SWUPDATES'
    6 =     'PKG_TYPE_DEVICE_SETTING'
    7 =     'PKG_TYPE_VIRTUAL_APP'
    8 =     'PKG_CONTENT_PACKAGE'
    257 = 'PKG_TYPE_IMAGE'
    258    = 'PKG_TYPE_BOOTIMAGE'
    259    = 'PKG_TYPE_OSINSTALLIMAGE'
}
 

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


$FailedPackages = $null
if ($dpSelection)
{
    foreach($dp in $dpSelection)
    {
        if ($IncludeAlreadyInstalled)
        {
            $query = "select * from SMS_PackageStatusDistPointsSummarizer where state in (0,1,2,3) and ServerNALPath like '%$($dp.ServerName)%'"
        }
        else
        {
            $query = "select * from SMS_PackageStatusDistPointsSummarizer where state in (1,2,3) and ServerNALPath like '%$($dp.ServerName)%'"
        }
        
        [array]$FailedPackages += Get-WmiObject -ComputerName $ProviderServer -Namespace "Root\SMS\Site_$SiteCode" -Query $query
    }


    $selection = $null
    if ($FailedPackages)
    {
        $title = 'Select packages for redistribution from a list of {0} packages' -f $FailedPackages.count
        $type = @{label="Type";expression={$pkgTypeHashTable.[int]($_.PackageType)}}
        $ServerName = @{label="ServerName";expression={$_.ServerNALPath -replace '\["Display=\\' -replace '\\' -replace '"].*'}}
        $state = @{label="State";expression={$stateHashTable.[int]($_.State)}}
        $selection = $FailedPackages | Select-Object $ServerName, PackageID, $type, $State  | Sort-Object ServerName, PackageID | Out-GridView -Title $title -OutputMode Multiple

        if ($selection)
        {
            foreach($FailedPackage in $selection)
            {
                $query = "select * from SMS_DistributionPoint where PackageID='$($FailedPackage.PackageID)' and ServerNALPath like '%$($FailedPackage.ServerName)%'" 
                $contentOnDP = Get-WmiObject -ComputerName $ProviderServer -Namespace "Root\SMS\Site_$SiteCode" -Query $query
                $contentOnDP.RefreshNow = $true
                Write-Host "Will refresh content with ID $($FailedPackage.PackageID) on $($FailedPackage.ServerName)..." -ForegroundColor Green
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
        Write-Host 'No content in defined states found!' -ForegroundColor Green
    }

}
else
{
    Write-Host 'No DP selected' -ForegroundColor Green
}





