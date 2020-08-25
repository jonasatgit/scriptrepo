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
   This Script will check and or delete the custom policy set via Set-SINVThrottlingPolicy.ps1 and is design to run as a ConfigMgr configuration item
.DESCRIPTION
   This Script will check and or delete the custom policy set via Set-SINVThrottlingPolicy.ps1 and is design to run as a ConfigMgr configuration item
   Use the same script as the detection and as the remediation script and just change the variable $Remediate accordingly
   Source: https://github.com/jonasatgit/scriptrepo/tree/master/SINV
.EXAMPLE
   $Remediate = $false => The script will just check the existence of the custom policy
   $Remediate = $true => The script will check and delete the custom policy, wich sets the settings back to the default state 
#>

$Remediate = $false

# get sq inv profiles
$SINVProfilesActualConfig = Get-WmiObject -Namespace "ROOT\ccm\Policy\Machine\RequestedConfig" -query "select * from CCM_Service_ResourceProfileInformation where ProfileID = '{58E2FE09-07BB-4adb-8A93-E49C5BF2301F}' and PolicyID = 'CustomThrottlingProfile'" 
if($SINVProfilesActualConfig)
{
    if($Remediate)
    {
        $SINVProfilesActualConfig | Remove-WmiObject
    }
    else
    {
        return $false # wmi entry does exist, hence compliacne item is uncompliant and remediation might be needed
    }
}
else
{
    return $true # no wmi entry, hence compliance item is compliant
}


