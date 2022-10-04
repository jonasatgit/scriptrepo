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
   This Script will check and or remediate Software Inventory Profile Settings for one of the three possible throttle profiles
   It can either run manully or as part of a ConfigMgr configuration item. Hence no parameters and instead simple variables
.DESCRIPTION
   This Script will check and or remediate Software Inventory Profile Settings for a given ProfileID and is designed to run as a ConfigMgr configuration item
   Use the same script as the detection and as the remediation script and just change the variable $Remediate accordingly

   Software Inventory can run three different tasks and each task has it own throttle profile. 
   Look for one of the following IDs in InventoryAgent.log. The ID represents the currently active throttle profile. 

   If you want to test differnt settings for one of the throttle profiles change the variable $ThrottleProfileID and the values of $SINVCUSTOMProfileSettings accordingly
   
   POSSIBLE VALUES FOR $ThrottleProfileID:
        // File system query task - actual filesystem crawl for SINV/FILECOLL
        $ThrottleProfileID = "{58E2FE09-07BB-4adb-8A93-E49C5BF2301F}"

        // File System Collection Task - processing SINV WMI instances
        $ThrottleProfileID = "{C0ED66AD-8194-49fd-9826-D0DD38AB7DAA}"

        // File Collection Task - processing FILECOLL WMI instances
        $ThrottleProfileID = "{CE22C5BA-165D-4b93-BC73-926CE1BD9279}"


   Source: https://github.com/jonasatgit/scriptrepo/tree/master/SINV
.EXAMPLE
   $Remediate = $false => The script will just check the settings, but will not set them
   $Remediate = $true => The script will set the custom profile settings
#>
#region variables
[bool]$Remediate = $false
[string]$ThrottleProfileID = "{58E2FE09-07BB-4adb-8A93-E49C5BF2301F}"
#endregion

#region CUSTOM Settings Profile 
[hashtable]$SINVCUSTOMProfileSettings = [ordered]@{
    PolicyID = "CustomThrottlingProfile"; # DO NOT CHANGE
    PolicyVersion = 1; # DO NOT CHANGE
    PolicyRuleID = 1; # DO NOT CHANGE
    PolicySource = "Local"; # DO NOT CHANGE
    ProfileID = $ThrottleProfileID; # Can be changed to either one of the above ProfileIDs depending on the throttling behaviour of ConfigMgr clients
    BatchSize = 100; # Default value=100
    ControlUsage=$true; # Default value=$true
    OnAC_PercentageOfTimeoutToWait = 50; # Default value=50, possible test value=10
    OnAC_EvaluationPeriodLengthSec = 60; # Default value=60, possible test value=20
    OnAC_IdlePeriodLengthSec = 120; # Default value=120, possible test value=30
    OnAC_MinIdleDiskPercentage = 30; # Default value=30, possible test value=30
    OnAC_ConsiderUserInputAsActivity = $true; # Default value=$true, possible test value=$false
    OnBattery_BehaviorType=1; # DO NOT CHANGE
    OnLowBattery_BehaviorType =0;# DO NOT CHANGE
    }
#endregion


#region pre-work
# Removeing BatchSize in case we are not changing the filesystem crawl profile
if ($SINVCUSTOMProfileSettings.ProfileID -ne "{58E2FE09-07BB-4adb-8A93-E49C5BF2301F}")
{
    $SINVCUSTOMProfileSettings.Remove('BatchSize')
}
# convert hastable to custom object
$SINVCUSTOMProfileSettingsCustomObject = New-Object psobject -Property $SINVCUSTOMProfileSettings

# get sq inv profiles
$ProfileID = $SINVCUSTOMProfileSettings.ProfileID
$SINVProfilesActualConfig = Get-WmiObject -Namespace "ROOT\ccm\Policy\Machine\RequestedConfig" -query "select * from CCM_Service_ResourceProfileInformation where ProfileID = '$ProfileID'"
#endregion


#region START Compliance Checks
if(!$Remediate)
{
    if($SINVProfilesActualConfig)
    {
        #Check if custom settings are set
        [bool]$SettingsIdentical = $true
        $SINVCUSTOMProfileSettingsCustomObject.psobject.Properties | ForEach-Object {

            if($SINVProfilesActualConfig.($_.name) -ne $_.value)
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

