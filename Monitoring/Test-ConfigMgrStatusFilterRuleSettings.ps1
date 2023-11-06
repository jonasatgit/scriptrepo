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
   Script to test the current ConfigMgr status filter rule settings
   Designed to run as a ConfigMgr config item on a primary site server

   Soure: https://github.com/jonasatgit/scriptrepo
    
.DESCRIPTION

   Will use hashtable: $ExpectedComponentConfiguration to test the current ConfigMgr component summarizer settings
   
   Use parameter -ExportCurrentConfig to get the current config and copy it in the line below "$ExpectedComponentConfiguration = @{"
   to replace the values in the script  

#>
param 
(
    [switch]$ExportCurrentConfig
)


$ExpectedRuleConfiguration = @'
[
    {
        "PropertyListName":  "Status Filter Rule: Detect when the status of a server component changes to Critical.",
        "Values":  [
                       "Actions=18",
                       "Actions Mask=2",
                       "Stop Evaluating=0",
                       "Module Name=SMS Server",
                       "Component=SMS_COMPONENT_STATUS_SUMMARIZER",
                       "Code=4609"
                   ]
    },
    {
        "PropertyListName":  "Status Filter Rule: Detect when the status of a server component changes to Warning.",
        "Values":  [
                       "Actions=18",
                       "Actions Mask=2",
                       "Stop Evaluating=0",
                       "Module Name=SMS Server",
                       "Component=SMS_COMPONENT_STATUS_SUMMARIZER",
                       "Code=4610"
                   ]
    },
    {
        "PropertyListName":  "Status Filter Rule: Detect when the status of a site system\u0027s storage object changes to Critical because it could not be accessed.",
        "Values":  [
                       "Actions=18",
                       "Actions Mask=2",
                       "Stop Evaluating=0",
                       "Module Name=SMS Server",
                       "Component=SMS_SITE_SYSTEM_STATUS_SUMMARIZER",
                       "Code=4700"
                   ]
    },
    {
        "PropertyListName":  "Status Filter Rule: Detect when the status of a site system\u0027s storage object changes to Critical due to low free space.",
        "Values":  [
                       "Actions=18",
                       "Actions Mask=2",
                       "Stop Evaluating=0",
                       "Module Name=SMS Server",
                       "Component=SMS_SITE_SYSTEM_STATUS_SUMMARIZER",
                       "Code=4711"
                   ]
    },
    {
        "PropertyListName":  "Status Filter Rule: Detect when the status of a site system\u0027s storage object changes to Warning due to low free space.",
        "Values":  [
                       "Actions=18",
                       "Actions Mask=2",
                       "Stop Evaluating=0",
                       "Module Name=SMS Server",
                       "Component=SMS_SITE_SYSTEM_STATUS_SUMMARIZER",
                       "Code=4710"
                   ]
    },
    {
        "PropertyListName":  "Status Filter Rule: Detect when the status of the site database changes to Critical because it could not be accessed.",
        "Values":  [
                       "Actions=18",
                       "Actions Mask=2",
                       "Stop Evaluating=0",
                       "Module Name=SMS Server",
                       "Component=SMS_SITE_SYSTEM_STATUS_SUMMARIZER",
                       "Code=4703"
                   ]
    },
    {
        "PropertyListName":  "Status Filter Rule: Detect when the status of the site database changes to Critical due to low free space.",
        "Values":  [
                       "Actions=18",
                       "Actions Mask=2",
                       "Stop Evaluating=0",
                       "Module Name=SMS Server",
                       "Component=SMS_SITE_SYSTEM_STATUS_SUMMARIZER",
                       "Code=4714"
                   ]
    },
    {
        "PropertyListName":  "Status Filter Rule: Detect when the status of the site database changes to Warning due to low free space.",
        "Values":  [
                       "Actions=18",
                       "Actions Mask=2",
                       "Stop Evaluating=0",
                       "Module Name=SMS Server",
                       "Component=SMS_SITE_SYSTEM_STATUS_SUMMARIZER",
                       "Code=4713"
                   ]
    },
    {
        "PropertyListName":  "Status Filter Rule: Detect when the status of the transaction log for the site database changes to Critical because it could not be accessed.",
        "Values":  [
                       "Actions=18",
                       "Actions Mask=2",
                       "Stop Evaluating=0",
                       "Module Name=SMS Server",
                       "Component=SMS_SITE_SYSTEM_STATUS_SUMMARIZER",
                       "Code=4706"
                   ]
    },
    {
        "PropertyListName":  "Status Filter Rule: Detect when the status of the transaction log for the site database changes to Critical due to low free space.",
        "Values":  [
                       "Actions=18",
                       "Actions Mask=2",
                       "Stop Evaluating=0",
                       "Module Name=SMS Server",
                       "Component=SMS_SITE_SYSTEM_STATUS_SUMMARIZER",
                       "Code=4717"
                   ]
    },
    {
        "PropertyListName":  "Status Filter Rule: Detect when the status of the transaction log for the site database changes to Warning due to low free space.",
        "Values":  [
                       "Actions=18",
                       "Actions Mask=2",
                       "Stop Evaluating=0",
                       "Module Name=SMS Server",
                       "Component=SMS_SITE_SYSTEM_STATUS_SUMMARIZER",
                       "Code=4716"
                   ]
    },
    {
        "PropertyListName":  "Status Filter Rule: Write all other messages to the site database and specify the period after which the user can delete the messages.",
        "Values":  [
                       "Actions=1",
                       "Actions Mask=1",
                       "Stop Evaluating=0",
                       "Days To Keep=30"
                   ]
    },
    {
        "PropertyListName":  "Status Filter Rule: Write audit messages to the site database and and specify the period after which the user can delete the messages.",
        "Values":  [
                       "Actions=1",
                       "Actions Mask=1",
                       "Stop Evaluating=0",
                       "Days To Keep=180",
                       "Message Type=768"
                   ]
    }
]
'@

$ExpectedRuleConfigurationObject = $ExpectedRuleConfiguration | ConvertFrom-Json

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

$diffList = new-object System.Collections.ArrayList

$paramSplat = @{
    CimSession = $cimSession
    Namespace = "root\sms\site_$siteCode"
    Query = "SELECT * FROM SMS_SCI_SCPropertyList WHERE SiteCode='$($siteCode)' AND FileType=2 AND ItemType ='SMS_STATUS_MANAGER' AND PropertyListName LIKE 'Status Filter Rule: %'"
}

$statusFilterRules = Get-CimInstance @paramSplat -ErrorAction SilentlyContinue
if ($statusFilterRules)
{

    $statusFilterRulesJSON = $statusFilterRules | Select-Object PropertyListName, Values | ConvertTo-Json

    if ($ExportCurrentConfig)
    {
        # Just export current config to be used in this script
        $statusFilterRules | Select-Object PropertyListName, Values | ConvertTo-Json
    }
    else
    {
        #$statusFilterRulesObject = $statusFilterRules | Select-Object PropertyListName, Values

        
        foreach($configItem in $ExpectedRuleConfigurationObject)
        {
            $foundItem = $statusFilterRules.Where({$_.PropertyListName -ieq $configItem.PropertyListName})  
            if ($foundItem)
            {
                $compareResult = Compare-Object -ReferenceObject $foundItem.values -DifferenceObject $configItem.values | Where-Object {$_.SideIndicator -ieq '=>'}
                if ($compareResult)
                {
                    foreach($result in $compareResult)
                    {                    
                        [void]$diffList.Add("Wrong setting. ExpectedValue: `"$($result.InputObject)`" of `"$($configItem.PropertyListName)`"")
                    }
                }
            }
            else
            {
                [void]$diffList.Add("NOT FOUND IN CONFIGMGR: `"$($configItem.PropertyListName)`"")    
            }    
        }

        # Test the other way around
        foreach($configItem in $statusFilterRules)
        {
            $foundItem = $ExpectedRuleConfigurationObject.Where({$_.PropertyListName -ieq $configItem.PropertyListName})  
            if (-NOT ($foundItem))
            {
                [void]$diffList.Add("NOT FOUND IN SCRIPT DEFINITION: `"$($configItem.PropertyListName)`"")
            }
        }
    }    
}
else 
{
    Write-Warning 'Not able to get wmi class SMS_SCI_SCPropertyList'
    Exit 1
}
$cimSession | Remove-CimSession

if (-NOT ($ExportCurrentConfig))
{
    if ($diffList)
    {
        $diffList
    }
    else
    {
        Write-Output 'Compliant'
    }
}