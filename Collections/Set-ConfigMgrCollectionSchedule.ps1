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
.Synopsis
    Script to set incremental update collections to refresh every hour with an offset of 5 minutes each.

.DESCRIPTION
    Script to set incremental update collections to refresh every hour with an offset of 5 minutes each.
    The script will output a list of collections first, so that an admin can choose which collections he whants to change. 

.EXAMPLE
    .\Set-ConfigMgrCollectionSchedule.ps1

.EXAMPLE
    .\Set-ConfigMgrCollectionSchedule.ps1 -SiteCode 'P01' -ProviderMachineName 'server1.contoso.local'

.PARAMETER SiteCode
    SiteCode of ConfigMgr Site

.PARAMETER ProviderMachineName
    Name of SMS Provider server
    
.LINK
    https://github.com/jonasatgit/scriptrepo 
#>

[CmdletBinding()]
param 
(
    [Parameter(Mandatory=$true)]
    [string]$SiteCode,
    [Parameter(Mandatory=$true)]
    [string]$ProviderMachineName
)

# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Do not change anything below this line

# Import the ConfigurationManager.psd1 module 
if(-NOT (Get-Module ConfigurationManager)) 
{
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if(-NOT (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) 
{
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams


$fullCollectionList = Get-CMCollection

$collections = $fullCollectionList | Select-Object CollectionID, Name, RefreshType, MemberCount | Where-Object {($_.RefreshType -eq 4 -or $_.RefreshType -eq 6 )-and $_.CollectionID -NotLike "SMS*"}

[array]$resultList = $collections | Sort-Object -Property MemberCount | Out-GridView -Title 'Select Collection/s' -OutputMode Multiple

$i = 0
foreach ($item in $resultList)
{
    $startTime = (Get-Date '2022-12-01 01:00').AddMinutes($i)
    $schedule = New-CMSchedule -Start $startTime -RecurInterval Hours -RecurCount 1  
    Write-Host "Will set collection: $($item.Name)" 

    Set-CMCollection -CollectionId $item.CollectionID -RefreshType Periodic -RefreshSchedule $schedule

    $i = $i+5
} 
