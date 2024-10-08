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

param
(
    [int]$enableRbacReporting = 0, # 0 means RBAC is off in reporting, 1 means RBAC is on
    [string]$SiteCode = "P02",
    [string]$ProviderMachineName = "CM02.contoso.local"
)

# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Do not change anything below this line

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams

$SMSSrp = Invoke-CMWmiQuery -Query  "Select * From SMS_SCI_SysResUse Where SiteCode='$($SiteCode)' and RoleName='SMS SRS Reporting Point'"

$SMSSrpEmbeddedProperties = $SMSSrp.EmbeddedProperties

$SMSSrpEmbeddedProperties["EnableRbacReporting"].Value2 = $enableRbacReporting

$SMSSrp.EmbeddedProperties = $SMSSrpEmbeddedProperties

$SMSSrp.Put()