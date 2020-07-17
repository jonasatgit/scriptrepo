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
   This Script will check and or remediate Software Inventory Profile Settings for ProfileID {58E2FE09-07BB-4adb-8A93-E49C5BF2301F} and is design to run as a ConfigMgr configuration item
.DESCRIPTION
   This Script will check and or remediate Software Inventory Profile Settings for ProfileID {58E2FE09-07BB-4adb-8A93-E49C5BF2301F} and is design to run as a ConfigMgr configuration item
   Use the same script as the detection and as the remediation script and just change the variable $Remediate accordingly
.EXAMPLE
   $Remediate = $false => The script will just check the settings, but will not set them
   $Remediate = $true => The script will set the custom profile settings
#>
#region variables
[bool]$Remediate = $false
#endregion

#region CUSTOM Settings Profile {58E2FE09-07BB-4adb-8A93-E49C5BF2301F} for file system query task - actual filesystem crawl for SINV/FILECOLL
# Custom settings
[hashtable]$SINVCUSTOMProfileSettings = [ordered]@{
    PolicyID = "CustomThrottlingProfile"; # DO NOT CHANGE
    PolicyVersion = 1; # DO NOT CHANGE
    PolicyRuleID = 1; # DO NOT CHANGE
    PolicySource = "Local"; # DO NOT CHANGE
    ProfileID="{58E2FE09-07BB-4adb-8A93-E49C5BF2301F}"; # DO NOT CHANGE
    BatchSize = 100;
    ControlUsage=$true;
    OnAC_PercentageOfTimeoutToWait = 10;
    OnAC_EvaluationPeriodLengthSec = 20;
    OnAC_IdlePeriodLengthSec = 30;
    OnAC_MinIdleDiskPercentage = 30;
    OnAC_ConsiderUserInputAsActivity = $false;
    OnBattery_BehaviorType=1; # DO NOT CHANGE
    OnLowBattery_BehaviorType =0;# DO NOT CHANGE
    }
#endregion


#region pre-work

# convert hastable to custom object
$SINVCUSTOMProfileSettingsCustomObject = New-Object psobject -Property $SINVCUSTOMProfileSettings

# get sq inv profiles
$SINVProfilesActualConfig = Get-WmiObject -Namespace "ROOT\ccm\Policy\Machine\RequestedConfig" -query "select * from CCM_Service_ResourceProfileInformation where ProfileID = '{58E2FE09-07BB-4adb-8A93-E49C5BF2301F}'" 

#endregion


#region START Compliance Checks
if(!$Remediate)
{
    if($SINVProfilesActualConfig)
    {
        #Check if custom settings are set
        [bool]$SettingsIdentical = $true
        $SINVCUSTOMProfileSettingsCustomObject.psobject.Properties | ForEach-Object {

            if($SINVFILECOLLProfile.($_.name) -ne $_.value)
            {
                $SettingsIdentical = $false
            }
        }
        return $SettingsIdentical
    }
    else
    {
        $false # wmi instance does not exist
    }
}
# END Compliance Checks
#endregion


#region START Remediation
if($Remediate)
{
    # SET CUSTOM SETTINGS
    if($SINVProfilesActualConfig)
    {
        $null = Set-WmiInstance -InputObject $SINVProfilesActualConfig -Arguments $SINVCUSTOMProfileSettings
    }
    else
    {
        $CCM_Service_ResourceProfileInformation = Get-WmiObject -Namespace "ROOT\ccm\Policy\Machine\RequestedConfig" -Class "CCM_Service_ResourceProfileInformation" -list
        $null = Set-WmiInstance -InputObject $CCM_Service_ResourceProfileInformation -Arguments $SINVCUSTOMProfileSettings    
    }
}
# END Remediation
#endregion

