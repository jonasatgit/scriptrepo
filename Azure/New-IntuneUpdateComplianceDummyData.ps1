$subscriptionID = '111111'
$resourceGroupName = 'az0000011'
$workspaceName = 'CentralLogs'


<#
.SYNOPSIS
    Get Log Reference Data from CSV file
.DESCRIPTION
    This function will read a CSV file and convert it to a JSON object that can be used to create a Log Analytics table.
    IMPORTANT: The filename will be used as the table name.
    Data coming from:
        https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/ucclient
        https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/ucclientreadinessstatus
        https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/ucclientupdatestatus
.EXAMPLE
    Get-LogReferenceDataFromCSV -csvPath .\UCClient.csv
#>
function Get-LogReferenceDataFromCSV
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$csvPath
    )

    $properties = @()
    $csv = Get-Content $csvPath | ConvertFrom-Csv -Delimiter ';'
    $tableName = $csvPath | Split-Path -Leaf | Split-Path -LeafBase

    foreach ($line in $csv) 
    {
        if ($line.Column.StartsWith('_')) { continue } # skip columns starting with _ (internal columns)
        if ($line.Column -eq 'AzureADTenantId') { continue } # skip column (reserved name)
        if ($line.Column -eq 'SourceSystem') { continue } # skip column (reserved name)
        if ($line.Column -eq 'TenantId') { continue } # skip column (reserved name)
        if ($line.Column -eq 'Type') { continue } # skip column (reserved name)

        $properties += [pscustomobject]@{
            name = $line.Column
            type = $line.Type
        }
    }

    $body = [pscustomobject]@{
        properties = @{
            schema = @{
                name = '{0}_CL' -f $tableName
                columns = $properties
            }
        }
    }

    return ($body | convertto-json -Depth 100)

}



function Get-DummyData
{
    param 
    (
        $Type
    )

    switch ($type) 
    {
        'AzureADDeviceId' {return (New-Guid).Guid}
        'AzureADTenantId' {return (New-Guid).Guid}
        'City' {
            return Get-Random ('Hamburg','Berlin','Munich','Frankfurt','Stuttgart','Dusseldorf','Cologne','Dortmund','Essen','Leipzig','Dresden','Hannover','Nuremberg','Duisburg','Bochum','Wuppertal','Bielefeld')
        }
        'Country' {
            return Get-Random ('DE','UK','FR','IT','ES','NL','BE','AT','CH','DK','SE','NO','FI','PL','CZ','HU','RO','BG','GR','PT','IE','LT','LV','EE','HR','SI','SK','LU','MT','CY')
        }
        'DeviceFamily' {
            return Get-Random ('Windows.Desktop','Windows.Mobile','Windows.Team','Windows.Holographic','Windows.Xbox','Windows.IoT','Windows.Server')    
        }
        'DeviceFormFactor' {
            return Get-Random ('Desktop','Laptop','Tablet','Phone','Hub','IoT','Virtual','Server')
        }
        'DeviceManufacturer' {
            return Get-Random ('Microsoft','Dell','HP','Lenovo','Acer','Asus','Toshiba','Samsung','Sony','Panasonic','Fujitsu','LG','Medion','MSI','Razer','Alienware','Intel')
        }
        'DeviceModel' {
            return Get-Random -Minimum 1000 -Maximum 9999
        }
        'DeviceName' {
            return 'PC-{0}' -f (Get-Random -Minimum 10000 -Maximum 999999)
        }
        'GlobalDeviceId' {
            return 'g_{0}' -f (New-Guid).Guid -replace '-'
        }
        'IsVirtual' {
            return Get-Random ($true,$false)
        }
        'LastCensusScanTime' {
            return (Get-Date).AddDays(-1)
        }
        'LastWUScanTime' {
            return (Get-Date).AddDays(-1)
        }
        'OSArchitecture' {
            return Get-Random ('x86','x64','ARM','ARM64')
        }
        'OSBuild' {
            <#
                The currently-installed Windows 10 Build in the format 'Major'.'Revision'. 'Major' corresponds to which Feature Update the device is on, 
                whereas 'Revision' corresponds to which quality update the device is on. Mappings between Feature release and Major, 
                as well as Revision and KBs, are available aka.ms/win10releaseinfo.
            #>
            return 
        }
        Default {}
    }
    
}


$tableParams = @'
{
    "properties": {
        "schema": {
            "name": "UCClient_CL",
            "columns": [
                {
                    "name": "TimeGenerated",
                    "type": "DateTime"
                }, 
                {
                    "name": "AzureADDeviceId",
                    "type": "String"
                }, 
                {
                    "name": "AzureADTenantId",
                    "type": "String"
                }, 
                {
                    "name": "City",
                    "type": "String"
                }, 
                {
                    "name": "Country",
                    "type": "String"
                }, 
                {
                    "name": "DeviceFamily",
                    "type": "String"
                }, 
                {
                    "name": "DeviceFormFactor",
                    "type": "String"
                }, 
                {
                    "name": "DeviceManufacturer",
                    "type": "String"
                }, 
                {
                    "name": "DeviceModel",
                    "type": "String"
                }, 
                {
                    "name": "DeviceName",
                    "type": "String"
                }, 
                {
                    "name": "GlobalDeviceId",
                    "type": "String"
                }, 
                {
                    "name": "IsVirtual",
                    "type": "Bool"
                }, 
                {
                    "name": "LastCensusScanTime",
                    "type": "DateTime"
                }, 
                {
                    "name": "LastWUScanTime",
                    "type": "DateTime"
                }, 
                {
                    "name": "OSArchitecture",
                    "type": "String"
                }, 
                {
                    "name": "OSBuild",
                    "type": "String"
                }, 
                {
                    "name": "OSBuildNumber",
                    "type": "Int"
                }, 
                {
                    "name": "OSEdition",
                    "type": "String"
                }, 
                {
                    "name": "OSFeatureUpdateComplianceStatus",
                    "type": "String"
                }, 
                {
                    "name": "OSFeatureUpdateEOSTime",
                    "type": "DateTime"
                }, 
                {
                    "name": "OSFeatureUpdateReleaseTime",
                    "type": "DateTime"
                }, 
                {
                    "name": "OSFeatureUpdateStatus",
                    "type": "String"
                }, 
                {
                    "name": "OSQualityUpdateComplianceStatus",
                    "type": "String"
                }, 
                {
                    "name": "OSQualityUpdateReleaseTime",
                    "type": "DateTime"
                }, 
                {
                    "name": "OSQualityUpdateStatus",
                    "type": "String"
                }, 
                {
                    "name": "OSRevisionNumber",
                    "type": "Int"
                }, 
                {
                    "name": "OSSecurityUpdateComplianceStatus",
                    "type": "String"
                }, 
                {
                    "name": "OSSecurityUpdateStatus",
                    "type": "String"
                }, 
                {
                    "name": "OSServicingChannel",
                    "type": "String"
                }, 
                {
                    "name": "OSVersion",
                    "type": "String"
                }, 
                {
                    "name": "PrimaryDiskFreeCapacityMb",
                    "type": "Int"
                }, 
                {
                    "name": "SCCMClientId",
                    "type": "String"
                }, 
                {
                    "name": "UpdateConnectivityLevel",
                    "type": "String"
                }, 
                {
                    "name": "WUAutomaticUpdates",
                    "type": "Int"
                }, 
                {
                    "name": "WUDeadlineNoAutoRestart",
                    "type": "Int"
                }, 
                {
                    "name": "WUDODownloadMode",
                    "type": "String"
                }, 
                {
                    "name": "WUFeatureDeadlineDays",
                    "type": "Int"
                }, 
                {
                    "name": "WUFeatureDeferralDays",
                    "type": "Int"
                }, 
                {
                    "name": "WUFeatureGracePeriodDays",
                    "type": "Int"
                }, 
                {
                    "name": "WUFeaturePauseEndTime",
                    "type": "DateTime"
                }, 
                {
                    "name": "WUFeaturePauseStartTime",
                    "type": "DateTime"
                }, 
                {
                    "name": "WUFeaturePauseState",
                    "type": "String"
                }, 
                {
                    "name": "WUNotificationLevel",
                    "type": "Int"
                }, 
                {
                    "name": "WUPauseUXDisabled",
                    "type": "Int"
                }, 
                {
                    "name": "WUQualityDeadlineDays",
                    "type": "Int"
                }, 
                {
                    "name": "WUQualityDeferralDays",
                    "type": "Int"
                }, 
                {
                    "name": "WUQualityGracePeriodDays",
                    "type": "Int"
                }, 
                {
                    "name": "WUQualityPauseEndTime",
                    "type": "DateTime"
                }, 
                {
                    "name": "WUQualityPauseStartTime",
                    "type": "DateTime"
                }, 
                {
                    "name": "WUQualityPauseState",
                    "type": "String"
                }, 
                {
                    "name": "WURestartNotification",
                    "type": "Int"
                }, 
                {
                    "name": "WUServiceURLConfigured",
                    "type": "String"
                }, 
                {
                    "name": "WUUXDisabled",
                    "type": "Int"
                }	
            ]
        }
    }
}
'@

$tableParamObject = ConvertFrom-Json $tableParams

$tableName = $tableParamObject.properties.schema.name

$path = '/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}/tables/{3}?api-version=2021-12-01-preview' -f $subscriptionID, $resourceGroupName, $workspaceName, $tableName
Invoke-AzRestMethod -Path $path -Method PUT -payload $tableParams

$tableParams = @'
{
    "properties": {
      "schema": {
        "name": "UCClientReadinessStatus_CL",
        "columns": [
          {
            "name": "AzureADDeviceId",
            "type": "string"
          },
          {
            "name": "DeviceName",
            "type": "string"
          },
          {
            "name": "GlobalDeviceId",
            "type": "string"
          },
          {
            "name": "OSBuild",
            "type": "string"
          },
          {
            "name": "OSName",
            "type": "string"
          },
          {
            "name": "OSVersion",
            "type": "string"
          },
          {
            "name": "ReadinessExpiryTime",
            "type": "datetime"
          },
          {
            "name": "ReadinessReason",
            "type": "string"
          },
          {
            "name": "ReadinessScanTime",
            "type": "datetime"
          },
          {
            "name": "ReadinessStatus",
            "type": "string"
          },
          {
            "name": "SCCMClientId",
            "type": "string"
          },
          {
            "name": "SetupReadinessExpiryTime",
            "type": "datetime"
          },
          {
            "name": "SetupReadinessReason",
            "type": "string"
          },
          {
            "name": "SetupReadinessStatus",
            "type": "string"
          },
          {
            "name": "SetupReadinessTime",
            "type": "datetime"
          },
          {
            "name": "TargetOSBuild",
            "type": "string"
          },
          {
            "name": "TargetOSName",
            "type": "string"
          },
          {
            "name": "TargetOSVersion",
            "type": "string"
          },
          {
            "name": "TimeGenerated",
            "type": "datetime"
          }
        ]
      }
    }
}
'@

$tableParamObject = ConvertFrom-Json $tableParams

$tableName = $tableParamObject.properties.schema.name

$path = '/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}/tables/{3}?api-version=2021-12-01-preview' -f $subscriptionID, $resourceGroupName, $workspaceName, $tableName
Invoke-AzRestMethod -Path $path -Method PUT -payload $tableParams

$tableParams = @'
{
    "properties": {
      "schema": {
        "name": "UCClientUpdateStatus_CL",
        "columns": [
          {
            "name": "AzureADDeviceId",
            "type": "string"
          },
          {
            "name": "CatalogId",
            "type": "string"
          },
          {
            "name": "ClientState",
            "type": "string"
          },
          {
            "name": "ClientSubstate",
            "type": "string"
          },
          {
            "name": "ClientSubstateRank",
            "type": "int"
          },
          {
            "name": "ClientSubstateTime",
            "type": "datetime"
          },
          {
            "name": "DeploymentId",
            "type": "string"
          },
          {
            "name": "DeviceName",
            "type": "string"
          },
          {
            "name": "EventData",
            "type": "string"
          },
          {
            "name": "FurthestClientSubstate",
            "type": "string"
          },
          {
            "name": "FurthestClientSubstateRank",
            "type": "int"
          },
          {
            "name": "GlobalDeviceId",
            "type": "string"
          },
          {
            "name": "IsUpdateHealthy",
            "type": "bool"
          },
          {
            "name": "OfferReceivedTime",
            "type": "datetime"
          },
          {
            "name": "RestartRequiredTime",
            "type": "datetime"
          },
          {
            "name": "SCCMClientId",
            "type": "string"
          },
          {
            "name": "TargetBuild",
            "type": "string"
          },
          {
            "name": "TargetBuildNumber",
            "type": "int"
          },
          {
            "name": "TargetKBNumber",
            "type": "string"
          },
          {
            "name": "TargetRevisionNumber",
            "type": "int"
          },
          {
            "name": "TargetVersion",
            "type": "string"
          },
          {
            "name": "TimeGenerated",
            "type": "datetime"
          },
          {
            "name": "UpdateCategory",
            "type": "string"
          },
          {
            "name": "UpdateClassification",
            "type": "string"
          },
          {
            "name": "UpdateConnectivityLevel",
            "type": "string"
          },
          {
            "name": "UpdateDisplayName",
            "type": "string"
          },
          {
            "name": "UpdateHealthGroupL1",
            "type": "string"
          },
          {
            "name": "UpdateHealthGroupL2",
            "type": "string"
          },
          {
            "name": "UpdateHealthGroupL3",
            "type": "string"
          },
          {
            "name": "UpdateHealthGroupRankL1",
            "type": "int"
          },
          {
            "name": "UpdateHealthGroupRankL2",
            "type": "int"
          },
          {
            "name": "UpdateHealthGroupRankL3",
            "type": "int"
          },
          {
            "name": "UpdateId",
            "type": "string"
          },
          {
            "name": "UpdateInstalledTime",
            "type": "datetime"
          },
          {
            "name": "UpdateManufacturer",
            "type": "string"
          },
          {
            "name": "UpdateReleaseTime",
            "type": "datetime"
          },
          {
            "name": "UpdateSource",
            "type": "string"
          }
        ]
      }
    }
}
'@

$tableParamObject = ConvertFrom-Json $tableParams

$tableName = $tableParamObject.properties.schema.name

$path = '/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}/tables/{3}?api-version=2021-12-01-preview' -f $subscriptionID, $resourceGroupName, $workspaceName, $tableName
Invoke-AzRestMethod -Path $path -Method PUT -payload $tableParams


$tableParams = @'
{
    "properties": {
      "schema": {
        "name": "UCDeviceAlert_CL",
        "columns": [
          {
            "name": "AlertClassification",
            "type": "string"
          },
          {
            "name": "AlertData",
            "type": "string"
          },
          {
            "name": "AlertId",
            "type": "string"
          },
          {
            "name": "AlertRank",
            "type": "int"
          },
          {
            "name": "AlertStatus",
            "type": "string"
          },
          {
            "name": "AlertSubtype",
            "type": "string"
          },
          {
            "name": "AlertType",
            "type": "string"
          },
          {
            "name": "AzureADDeviceId",
            "type": "string"
          },
          {
            "name": "Description",
            "type": "string"
          },
          {
            "name": "DeviceName",
            "type": "string"
          },
          {
            "name": "ErrorCode",
            "type": "string"
          },
          {
            "name": "ErrorSymName",
            "type": "string"
          },
          {
            "name": "GlobalDeviceId",
            "type": "string"
          },
          {
            "name": "Recommendation",
            "type": "string"
          },
          {
            "name": "ResolvedTime",
            "type": "datetime"
          },
          {
            "name": "SCCMClientId",
            "type": "string"
          },
          {
            "name": "StartTime",
            "type": "datetime"
          },
          {
            "name": "TimeGenerated",
            "type": "datetime"
          },
          {
            "name": "URL",
            "type": "string"
          }
        ]
      }
    }
}
'@

$tableParamObject = ConvertFrom-Json $tableParams

$tableName = $tableParamObject.properties.schema.name

$path = '/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}/tables/{3}?api-version=2021-12-01-preview' -f $subscriptionID, $resourceGroupName, $workspaceName, $tableName
Invoke-AzRestMethod -Path $path -Method PUT -payload $tableParams

$tableParams = @'
{
    "properties": {
      "schema": {
        "name": "UCDOAggregatedStatus_CL",
        "columns": [
          {
            "name": "AzureADDeviceId",
            "type": "string"
          },
          {
            "name": "BWOptPercent28Days",
            "type": "real"
          },
          {
            "name": "BytesFromCache",
            "type": "long"
          },
          {
            "name": "BytesFromCDN",
            "type": "long"
          },
          {
            "name": "BytesFromGroupPeers",
            "type": "long"
          },
          {
            "name": "BytesFromIntPeers",
            "type": "long"
          },
          {
            "name": "BytesFromPeers",
            "type": "long"
          },
          {
            "name": "ContentType",
            "type": "string"
          },
          {
            "name": "DeviceCount",
            "type": "long"
          },
          {
            "name": "TimeGenerated",
            "type": "datetime"
          }
        ]
      }
    }
  }
'@

$tableParamObject = ConvertFrom-Json $tableParams

$tableName = $tableParamObject.properties.schema.name

$path = '/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}/tables/{3}?api-version=2021-12-01-preview' -f $subscriptionID, $resourceGroupName, $workspaceName, $tableName
Invoke-AzRestMethod -Path $path -Method PUT -payload $tableParams

$tableParams = @'
{
    "properties": {
      "schema": {
        "name": "UCDOStatus_CL",
        "columns": [
          {
            "name": "AzureADDeviceId",
            "type": "string"
          },
          {
            "name": "BWOptPercent28Days",
            "type": "real"
          },
          {
            "name": "BWOptPercent7Days",
            "type": "real"
          },
          {
            "name": "BytesFromCache",
            "type": "long"
          },
          {
            "name": "BytesFromCDN",
            "type": "long"
          },
          {
            "name": "BytesFromGroupPeers",
            "type": "long"
          },
          {
            "name": "BytesFromIntPeers",
            "type": "long"
          },
          {
            "name": "BytesFromPeers",
            "type": "long"
          },
          {
            "name": "City",
            "type": "string"
          },
          {
            "name": "ContentDownloadMode",
            "type": "int"
          },
          {
            "name": "ContentType",
            "type": "string"
          },
          {
            "name": "Country",
            "type": "string"
          },
          {
            "name": "DeviceName",
            "type": "string"
          },
          {
            "name": "DOStatusDescription",
            "type": "string"
          },
          {
            "name": "DownloadMode",
            "type": "string"
          },
          {
            "name": "DownloadModeSrc",
            "type": "string"
          },
          {
            "name": "GlobalDeviceId",
            "type": "string"
          },
          {
            "name": "GroupID",
            "type": "string"
          },
          {
            "name": "ISP",
            "type": "string"
          },
          {
            "name": "LastCensusSeenTime",
            "type": "datetime"
          },
          {
            "name": "NoPeersCount",
            "type": "long"
          },
          {
            "name": "OSVersion",
            "type": "string"
          },
          {
            "name": "PeerEligibleTransfers",
            "type": "long"
          },
          {
            "name": "PeeringStatus",
            "type": "string"
          },
          {
            "name": "PeersCannotConnectCount",
            "type": "long"
          },
          {
            "name": "PeersSuccessCount",
            "type": "long"
          },
          {
            "name": "PeersUnknownCount",
            "type": "long"
          },
          {
            "name": "TimeGenerated",
            "type": "datetime"
          },
          {
            "name": "TotalTimeForDownload",
            "type": "string"
          },
          {
            "name": "TotalTransfers",
            "type": "long"
          }
        ]
      }
    }
  }
'@

$tableParamObject = ConvertFrom-Json $tableParams

$tableName = $tableParamObject.properties.schema.name

$path = '/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}/tables/{3}?api-version=2021-12-01-preview' -f $subscriptionID, $resourceGroupName, $workspaceName, $tableName
Invoke-AzRestMethod -Path $path -Method PUT -payload $tableParams

$tableParams = @'
{
    "properties": {
      "schema": {
        "name": "UCServiceUpdateStatus_CL",
        "columns": [
          {
            "name": "AzureADDeviceId",
            "type": "string"
          },
          {
            "name": "CatalogId",
            "type": "string"
          },
          {
            "name": "DeploymentApprovedTime",
            "type": "datetime"
          },
          {
            "name": "DeploymentId",
            "type": "string"
          },
          {
            "name": "DeploymentIsExpedited",
            "type": "bool"
          },
          {
            "name": "DeploymentName",
            "type": "string"
          },
          {
            "name": "DeploymentRevokeTime",
            "type": "datetime"
          },
          {
            "name": "GlobalDeviceId",
            "type": "string"
          },
          {
            "name": "OfferReadyTime",
            "type": "datetime"
          },
          {
            "name": "PolicyCreatedTime",
            "type": "datetime"
          },
          {
            "name": "PolicyId",
            "type": "string"
          },
          {
            "name": "PolicyName",
            "type": "string"
          },
          {
            "name": "ProjectedOfferReadyTime",
            "type": "datetime"
          },
          {
            "name": "ServiceState",
            "type": "string"
          },
          {
            "name": "ServiceSubstate",
            "type": "string"
          },
          {
            "name": "ServiceSubstateRank",
            "type": "int"
          },
          {
            "name": "ServiceSubstateTime",
            "type": "datetime"
          },
          {
            "name": "TargetBuild",
            "type": "string"
          },
          {
            "name": "TargetVersion",
            "type": "string"
          },
          {
            "name": "TimeGenerated",
            "type": "datetime"
          },
          {
            "name": "UdpateIsSystemManifest",
            "type": "bool"
          },
          {
            "name": "UpdateCategory",
            "type": "string"
          },
          {
            "name": "UpdateClassification",
            "type": "string"
          },
          {
            "name": "UpdateDisplayName",
            "type": "string"
          },
          {
            "name": "UpdateId",
            "type": "string"
          },
          {
            "name": "UpdateManufacturer",
            "type": "string"
          },
          {
            "name": "UpdateProvider",
            "type": "string"
          },
          {
            "name": "UpdateRecommendedTime",
            "type": "datetime"
          },
          {
            "name": "UpdateReleaseTime",
            "type": "datetime"
          },
          {
            "name": "UpdateVersion",
            "type": "string"
          },
          {
            "name": "UpdateVersionTime",
            "type": "datetime"
          }
        ]
      }
    }
  }
'@

$tableParamObject = ConvertFrom-Json $tableParams

$tableName = $tableParamObject.properties.schema.name

$path = '/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}/tables/{3}?api-version=2021-12-01-preview' -f $subscriptionID, $resourceGroupName, $workspaceName, $tableName
Invoke-AzRestMethod -Path $path -Method PUT -payload $tableParams

$tableParams = @'
{
    "properties": {
      "schema": {
        "name": "UCUpdateAlert_CL",
        "columns": [
          {
            "name": "AlertClassification",
            "type": "string"
          },
          {
            "name": "AlertData",
            "type": "string"
          },
          {
            "name": "AlertId",
            "type": "string"
          },
          {
            "name": "AlertRank",
            "type": "int"
          },
          {
            "name": "AlertStatus",
            "type": "string"
          },
          {
            "name": "AlertSubtype",
            "type": "string"
          },
          {
            "name": "AlertType",
            "type": "string"
          },
          {
            "name": "AzureADDeviceId",
            "type": "string"
          },
          {
            "name": "CatalogId",
            "type": "string"
          },
          {
            "name": "ClientSubstate",
            "type": "string"
          },
          {
            "name": "ClientSubstateRank",
            "type": "int"
          },
          {
            "name": "DeploymentId",
            "type": "string"
          },
          {
            "name": "Description",
            "type": "string"
          },
          {
            "name": "DeviceName",
            "type": "string"
          },
          {
            "name": "ErrorCode",
            "type": "string"
          },
          {
            "name": "ErrorSymName",
            "type": "string"
          },
          {
            "name": "GlobalDeviceId",
            "type": "string"
          },
          {
            "name": "Recommendation",
            "type": "string"
          },
          {
            "name": "ResolvedTime",
            "type": "datetime"
          },
          {
            "name": "SCCMClientId",
            "type": "string"
          },
          {
            "name": "ServiceSubstate",
            "type": "string"
          },
          {
            "name": "ServiceSubstateRank",
            "type": "int"
          },
          {
            "name": "StartTime",
            "type": "datetime"
          },
          {
            "name": "TargetBuild",
            "type": "string"
          },
          {
            "name": "TargetVersion",
            "type": "string"
          },
          {
            "name": "TimeGenerated",
            "type": "datetime"
          },
          {
            "name": "UpdateCategory",
            "type": "string"
          },
          {
            "name": "UpdateClassification",
            "type": "string"
          },
          {
            "name": "UpdateId",
            "type": "string"
          },
          {
            "name": "URL",
            "type": "string"
          }
        ]
      }
    }
  }
'@

$tableParamObject = ConvertFrom-Json $tableParams

$tableName = $tableParamObject.properties.schema.name

$path = '/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}/tables/{3}?api-version=2021-12-01-preview' -f $subscriptionID, $resourceGroupName, $workspaceName, $tableName
Invoke-AzRestMethod -Path $path -Method PUT -payload $tableParams

