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
   This Script will check and or remediate Software Inventory Profile Settings for ProfileID {58E2FE09-07BB-4adb-8A93-E49C5BF2301F}
.DESCRIPTION
   This Script will check and or remediate Software Inventory Profile Settings for ProfileID {58E2FE09-07BB-4adb-8A93-E49C5BF2301F}
   Use the same script as the detection and as the remediation script and just change the variable $Remediate accordingly
.EXAMPLE
   $CheckCustomSettings = $true => The script will check if custom settings are set as defined via Hashtable $SINVCUSTOMProfileSettings
   $CheckCustomSettings = $false => The script will check if default settings are set as defined via Hashtable $SINVDefaultProfileSettings
.EXAMPLE
   $Remediate = $false => The script will not set any setting
   $Remediate = $true => The script will either set the deafult or custom values depending if $CheckCustomSettings is set to true or false 
#>
#region variables
[bool]$CheckCustomSettings = $true
[bool]$Remediate = $false
#endregion

#region CUSTOM Settings Profile {58E2FE09-07BB-4adb-8A93-E49C5BF2301F} for file system query task - actual filesystem crawl for SINV/FILECOLL
# Custom settings
[hashtable]$SINVCUSTOMProfileSettings = [ordered]@{
    BatchSize = 100;
    OnAC_PercentageOfTimeoutToWait = 10;
    OnAC_EvaluationPeriodLengthSec = 20;
    OnAC_IdlePeriodLengthSec = 30;
    OnAC_MinIdleDiskPercentage = 30;
    OnAC_ConsiderUserInputAsActivity = $false;
    }
#endregion


#region Default Settings [DO NOT CHANGE] Profile {58E2FE09-07BB-4adb-8A93-E49C5BF2301F} for file system query task - actual filesystem crawl for SINV/FILECOLL
# Default Settings:
[hashtable]$SINVDefaultProfileSettings = [ordered]@{
    ControlUsage = $true;
    BatchSize = 100;
    OnAC_PercentageOfTimeoutToWait = 50;
    OnAC_EvaluationPeriodLengthSec = 60;
    OnAC_IdlePeriodLengthSec = 120;
    OnAC_MinIdleDiskPercentage = 30;
    OnAC_ConsiderUserInputAsActivity = $true;
    OnBattery_BehaviorType = 1;
    OnLowBattery_BehaviorType = 0;
    }
#endregion


#region pre-work
# get sq inv profiles
$SINVProfiles = Get-WmiObject -Namespace "ROOT\ccm\Policy\DefaultMachine\RequestedConfig" -class "CCM_Service_ResourceProfileInformation"
# filter for file system query task profile
$SINVFILECOLLProfile =  $SINVProfiles.where({$_.ProfileID -eq '{58E2FE09-07BB-4adb-8A93-E49C5BF2301F}'})
# convert hastable to custom object
$SINVDefaultProfileSettingsCustomObject = New-Object psobject -Property $SINVDefaultProfileSettings
$SINVCUSTOMProfileSettingsCustomObject = New-Object psobject -Property $SINVCUSTOMProfileSettings
#endregion


#region START Compliance Checks
if(!$Remediate)
{
    if($CheckCustomSettings)
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
        #Check if default settings are set
        [bool]$SettingsIdentical = $true
        $SINVDefaultProfileSettingsCustomObject.psobject.Properties | ForEach-Object {

            if($SINVFILECOLLProfile.($_.name) -ne $_.value)
            {
                $SettingsIdentical = $false
            }
        }
        return $SettingsIdentical
    }
}
# END Compliance Checks
#endregion


#region START Remediation
if($Remediate)
{
    if($CheckCustomSettings)
    {
        # SET CUSTOM SETTINGS
        $SINVFILECOLLProfile | Set-WmiInstance -Arguments $SINVCUSTOMProfileSettings | Out-Null
    }
    else
    {
        # SET DEFAULT SETTINGS
        $SINVFILECOLLProfile | Set-WmiInstance -Arguments $SINVDefaultProfileSettings | Out-Null
    }
}
# END Remediation
#endregion
