#************************************************************************************************************
# Disclaimer
# This sample script is not supported under any Microsoft standard support program or service. This sample
# script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties
# including, without limitation, any implied warranties of merchantability or of fitness for a particular
# purpose. The entire risk arising out of the use or performance of this sample script and documentation
# remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation,
# production, or delivery of this script be liable for any damages whatsoever (including, without limitation,
# damages for loss of business profits, business interruption, loss of business information, or other
# pecuniary loss) arising out of the use of or inability to use this sample script or documentation, even
# if Microsoft has been advised of the possibility of such damages.
#************************************************************************************************************

<#
.Synopsis
   Script to test the current ConfigMgr component summarizer settings
   Designed to run as a ConfigMgr config item on a primary site server

   Soure: https://github.com/jonasatgit/scriptrepo
    
.DESCRIPTION

   Will use hashtable: $ExpectedComponentConfiguration to test the current ConfigMgr component summarizer settings
   
   Use parameter -ExportCurrentConfig to get the current config and copy it in the line below "$ExpectedComponentConfiguration = @{"
   to replace the values in the script

   Meaning: 
   IW=2000 means, if the component receives 2000 (I)nformational messages, the component goes into (W)arning state.
   IE=5000 means, if the component receives 5000 (I)nformational messages, the component goes into (E)rror state. 
   WW=10   means, if the component receives 10 (W)arning messages, the component goes into (W)arning state. 
   WE=50   means, if the component receives 50 (W)arning messages, the component goes into (E)rror state. 
   EW=1    means, if the component receives 1 (E)rror message, the component goes into (W)arning state.
   EE=5    means, if the component receives 5 (E)rror messages, the component goes into (E)rror state. 

#>
param 
(
    [switch]$ExportCurrentConfig
)


$ExpectedComponentConfiguration = @{
'SMS_AD_SECURITY_GROUP_DISCOVERY_AGENT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_AD_SYSTEM_DISCOVERY_AGENT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_AD_USER_DISCOVERY_AGENT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_AI_KB_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_ASYNC_RAS_SENDER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_BOOTSTRAP' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_BUSINESS_APP_PROCESS_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_CERTIFICATE_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_CERTIFICATE_REGISTRATION_POINT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_CLIENT_HEALTH' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_CLIENT_CONFIG_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_CLIENT_INSTALL_DATA_MGR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_COLLECTION_EVALUATOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_COMPONENT_MONITOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_CLOUD_SERVICES_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_COMPONENT_STATUS_SUMMARIZER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_DATABASE_NOTIFICATION_MONITOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'DATA_WAREHOUSE_SERVICE_POINT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_DESPOOLER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_MP_DEVICE_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_DISCOVERY_DATA_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_DISTRIBUTION_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_ENDPOINT_PROTECTION_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_ENDPOINT_PROTECTION_CONTROL_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_EXCHANGE_CONNECTOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_EXECUTIVE' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_FALLBACK_STATUS_POINT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_HIERARCHY_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_INBOX_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_INBOX_MONITOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_INVENTORY_DATA_LOADER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_INVENTORY_PROCESSOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_ISDN_RAS_SENDER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_LAN_SENDER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_MP_CONTROL_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_MP_FILE_DISPATCH_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_NETWORK_DISCOVERY' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_OBJECT_REPLICATION_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_RULE_ENGINE' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_OFFER_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_OFFER_STATUS_SUMMARIZER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_OUTBOX_MONITOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_POLICY_PROVIDER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_PXE_CONTROL_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_PXE_SERVICE_POINT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_MULTICAST_SERVICE_POINT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_REPLICATION_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SCHEDULER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SITE_BACKUP' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SITE_COMPONENT_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SITE_CONTROL_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SITE_SQL_BACKUP' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SITE_SYSTEM_STATUS_SUMMARIZER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SITE_VSS_WRITER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'AI_UPDATE_SERVICE_POINT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SNA_RAS_SENDER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SOFTWARE_INVENTORY_PROCESSOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SOFTWARE_METERING_PROCESSOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_STATE_MIGRATION_POINT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_STATE_SYSTEM' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_STATUS_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SYSTEM_HEALTH_VALIDATOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_WAKEONLAN_COMMUNICATION_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_WAKEONLAN_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_WINNT_SERVER_DISCOVERY_AGENT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_WSUS_CONFIGURATION_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_WSUS_CONTROL_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_WSUS_SYNC_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_X25_RAS_SENDER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SRS_REPORTING_POINT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_REPLICATION_CONFIGURATION_MONITOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_OFFLINE_SERVICING_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_AWEBSVC_CONTROL_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_PORTALWEB_CONTROL_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_PACKAGE_TRANSFER_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_ENROLL_SERVER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_EN_ADSERVICE_MONITOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_ENROLL_WEB' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_MIGRATION_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_AD_FOREST_DISCOVERY_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_ALERT_NOTIFICATION' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_NOTIFICATION_SERVER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_NOTIFICATION_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_LICENSE_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_DMP_UPLOADER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_DMP_DOWNLOADER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_CLOUD_PROXYCONNECTOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_CLOUD_USERSYNC' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_OUTGOING_CONTENT_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_DM_ENROLLMENTSERVICE' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_PROVIDERS' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'CONFIGURATION_MANAGER_UPDATE' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_FAILOVER_MANAGER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_REST_PROVIDER' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_AZUREAD_DISCOVERY_AGENT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_SERVICE_CONNECTOR' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_MESSAGE_PROCESSING_ENGINE' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
'SMS_ISVUPDATES_SYNCAGENT' = 'IW=2000,IE=5000,WW=10,WE=50,EW=1,EE=5'
}


$cimSessionOption = New-CimSessionOption -Protocol Dcom

$cimSession = New-CimSession -ComputerName $env:COMPUTERNAME -SessionOption $cimSessionOption

$paramSplat = @{
    CimSession = $cimSession
    Namespace = "root\sms"
    Query = "SELECT * FROM SMS_ProviderLocation where ProviderForLocalSite = True"
}

[array]$ProviderLocation = Get-CimInstance @paramSplat -ErrorAction SilentlyContinue

if ($ProviderLocation)
{

    $localProvider = $ProviderLocation -match $env:COMPUTERNAME

    if ($localProvider)
    {
        # Use the locally installed SMS provider
        $siteCode = $localProvider.SiteCode
        $smsProviderServer = $localProvider.Machine        
    }
    else
    {
        # Use the first SMS provider in the list
        $siteCode = $ProviderLocation[0].SiteCode
        $smsProviderServer = $ProviderLocation[0].Machine
    }

    $cimSession | Remove-CimSession

    $cimSession = New-CimSession -ComputerName $smsProviderServer -SessionOption $cimSessionOption
}
else
{
    Write-Warning 'Not able to detect SMS provider server'
    Exit 1
}

$outList = new-object System.Collections.ArrayList

$paramSplat = @{
    CimSession = $cimSession
    Namespace = "root\sms\site_$siteCode"
    Query = "SELECT * FROM SMS_SCI_Component WHERE SiteCode='$($siteCode)' AND FileType=2 AND ComponentName IN ('SMS_COMPONENT_STATUS_SUMMARIZER')"
}

$sciComponent = Get-CimInstance @paramSplat -ErrorAction SilentlyContinue
if ($sciComponent)
{
    $componentThresholds = $sciComponent.PropLists.Where({$_.PropertyListName -eq 'Component Thresholds'})
      
    foreach($thresholdItem in $componentThresholds.Values)
    {
        [array]$thresholdItemSplit = $thresholdItem -split ',IW'
        $thresholdItemSplit[0] = $thresholdItemSplit[0] -ireplace 'C='
        $thresholdItemSplit[1] = 'IW{0}' -f $thresholdItemSplit[1]

        if ($ExportCurrentConfig)
        {
            # Just export current config to be used in this script
            Write-Host "'$($thresholdItemSplit[0])' = '$($thresholdItemSplit[1])'"
        }
        else
        {
            # Normal compliance check
            if (-NOT ($ExpectedComponentConfiguration[($thresholdItemSplit[0])]))
            {
                $outString = '{0} does not exist in definition hashtable in script' -f $thresholdItemSplit[0]
                [void]$outList.Add($outString)
            }
            else
            {
                If (-NOT ($ExpectedComponentConfiguration[($thresholdItemSplit[0])] -ieq $thresholdItemSplit[1]))
                {
                    $outString = '{0} ExpectedValue: {1} CurrentValue {2}' -f $thresholdItemSplit[0], ($ExpectedComponentConfiguration[($thresholdItemSplit[0])]), $thresholdItemSplit[1]
                    [void]$outList.Add($outString)
                }
            }
        }
    }
    
}
else 
{
    Write-Warning 'Not able to get wmi class SMS_SCI_Component'
    Exit 1
}
$cimSession | Remove-CimSession

if ($outList)
{
    $outList
}
else
{
    Write-Output 'Compliant'
}