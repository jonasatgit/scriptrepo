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
    Script to export certain ConfigMgr items
 
.DESCRIPTION
    Script to export certain ConfigMgr items

.PARAMETER SiteCode
    The site code of the ConfigMgr site

.PARAMETER ProviderMachineName
    The machine name of the SMS Provider

.PARAMETER ExportRootFolder
    The root folder where the items will be exported to

.PARAMETER MaxExportFolderAgeInDays
    The maximum age of the export folders in days. Default is 10 days
    Brefore the script will delete the folders older than this value

.PARAMETER MinExportFoldersToKeep
    The minimum amount of export folders to keep. Default is 2
    The script will keep at least this amount of folders to avoid being left with nothing

.PARAMETER ExportAllItemTypes
    Export all item types

.PARAMETER ExportCollections
    Export collections

.PARAMETER ExportConfigurationItems
    Export configuration items

.PARAMETER ExportConfigurationBaselines
    Export configuration baselines

.PARAMETER ExportTaskSequences
    Export task sequences

.PARAMETER ExportAntimalwarePolicies
    Export antimalware policies

.PARAMETER ExportScripts
    Export scripts

.PARAMETER ExportClientSettings
    Export client settings

.PARAMETER ExportConfigurationPolicies
    Export configuration policies

.PARAMETER ExportCDLatest
    Export the latest version of the content of the CD.Latest folder to be able to restore ConfigMgr
    
.EXAMPLE
    Export-ConfigMgrItems.ps1
#>

param
(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$SiteCode,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$ProviderMachineName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$ExportRootFolder,
    
    [int]$MaxExportFolderAgeInDays = 30,
    [int]$MinExportFoldersToKeep = 30,
    [Switch]$ExportAllItemTypes,
    [Switch]$ExportCollections,
    [Switch]$ExportConfigurationItems,
    [Switch]$ExportConfigurationBaselines,
    [Switch]$ExportTaskSequences,
    [Switch]$ExportAntimalwarePolicies,
    [Switch]$ExportScripts,
    [Switch]$ExportClientSettings,
    [Switch]$ExportConfigurationPolicies,
    [switch]$ExportCDLatest
)



# Site configuration
[string]$script:SiteCode = $SiteCode # Site code 
[string]$script:ProviderMachineName = $ProviderMachineName # SMS Provider machine name
[string]$script:ExportRootFolder = $ExportRootFolder

# In case we only have older folders and would therefore delete them
# $MinExportFoldersToKeep will make sure we will keep at least some of them and not end up with nothing

# Do not change
$script:Spacer = '-'
$script:LogFilePath = '{0}\{1}.log' -f $PSScriptRoot ,($MyInvocation.MyCommand -replace '.ps1')
$script:FullExportFolderName = '{0}\{1}' -f $ExportRootFolder, (Get-date -Format 'yyyyMMdd-hhmm')
$script:ExitWithError = $false

#region Write-CMTraceLog
<#
.Synopsis
    Write-CMTraceLog will writea logfile readable via cmtrace.exe .DESCRIPTION
    Write-CMTraceLog will writea logfile readable via cmtrace.exe (https://www.bing.com/search?q=cmtrace.exe)
.EXAMPLE
    Write-CMTraceLog -Message "file deleted" => will log to the current directory and will use the scripts name as logfile name #> 
function Write-CMTraceLog 
{
    [CmdletBinding()]
    Param
    (
        #Path to the log file
        [parameter(Mandatory=$false)]
        [String]$LogFile=$script:LogFilePath,

        #The information to log
        [parameter(Mandatory=$true)]
        [String]$Message,

        #The source of the error
        [parameter(Mandatory=$false)]
        [String]$Component=(Split-Path $PSCommandPath -Leaf),

        #severity (1 - Information, 2- Warning, 3 - Error) for better reading purposes this variable as string
        [parameter(Mandatory=$false)]
        [ValidateSet("Information","Warning","Error")]
        [String]$Severity="Information",

        # write to console only
        [Parameter(Mandatory=$false)]
        [ValidateSet("Console","Log","ConsoleAndLog")]
        [string]$OutputMode = 'Log'
    )


    # save severity in single for cmtrace severity
    [single]$cmSeverity=1
    switch ($Severity)
        {
            "Information" {$cmSeverity=1; $color = [System.ConsoleColor]::Green; break}
            "Warning" {$cmSeverity=2; $color = [System.ConsoleColor]::Yellow; break}
            "Error" {$cmSeverity=3; $color = [System.ConsoleColor]::Red; break}
        }

    If (($OutputMode -ieq "Console") -or ($OutputMode -ieq "ConsoleAndLog"))
    {
        Write-Host $Message -ForegroundColor $color
    }
    
    If (($OutputMode -ieq "Log") -or ($OutputMode -ieq "ConsoleAndLog"))
    {
        #Obtain UTC offset
        $DateTime = New-Object -ComObject WbemScripting.SWbemDateTime
        $DateTime.SetVarDate($(Get-Date))
        $UtcValue = $DateTime.Value
        $UtcOffset = $UtcValue.Substring(21, $UtcValue.Length - 21)

        #Create the line to be logged
        $LogLine =  "<![LOG[$Message]LOG]!>" +`
                    "<time=`"$(Get-Date -Format HH:mm:ss.mmmm)$($UtcOffset)`" " +`
                    "date=`"$(Get-Date -Format M-d-yyyy)`" " +`
                    "component=`"$Component`" " +`
                    "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
                    "type=`"$cmSeverity`" " +`
                    "thread=`"$PID`" " +`
                    "file=`"`">"

        #Write the line to the passed log file
        $LogLine | Out-File -Append -Encoding UTF8 -FilePath $LogFile
    }
}
#endregion


#region Invoke-LogfileRollover
<# 
.Synopsis
    Function Invoke-LogfileRollover

.DESCRIPTION
    Will rename a logfile from ".log" to ".lo_". 
    Old ".lo_" files will be deleted

.PARAMETER MaxFileSizeKB
    Maximum file size in KB in order to determine if a logfile needs to be rolled over or not.
    Default value is 1024 KB.

.EXAMPLE
    Invoke-LogfileRollover -Logfile "C:\Windows\Temp\logfile.log" -MaxFileSizeKB 2048
#>
Function Invoke-LogfileRollover
{
#Validate path and write log or eventlog
[CmdletBinding()]
Param(
      #Path to test
      [parameter(Mandatory=$True)]
      [string]$Logfile,
      
      #max Size in KB
      [parameter(Mandatory=$False)]
      [int]$MaxFileSizeKB = 1024
    )

    if (Test-Path $Logfile)
    {
        $getLogfile = Get-Item $Logfile
        if ($getLogfile.PSIsContainer)
        {
            # Just a folder. Skip actions
        }
        else 
        {
            $logfileSize = $getLogfile.Length/1024
            $newName = "{0}.lo_" -f $getLogfile.BaseName
            $newLogFile = "{0}\{1}" -f ($getLogfile.FullName | Split-Path -Parent), $newName

            if ($logfileSize -gt $MaxFileSizeKB)
            {
                if(Test-Path $newLogFile)
                {
                    #need to delete old file first
                    Remove-Item -Path $newLogFile -Force -ErrorAction SilentlyContinue
                }
                Rename-Item -Path ($getLogfile.FullName) -NewName $newName -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
#endregion


#region function Remove-OldExportFolders
<#
.SYNOPSIS
    Function to replace delete old export folders
#>
function Remove-OldExportFolders
{
    param
    (
        [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [int]$MaxExportFolderAgeInDays,
        [parameter(Mandatory=$true)]
        [int]$MinExportFoldersToKeep
    )

    $folderObj = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($item in (Get-ChildItem $RootPath))
    {
        # We need to make sure to only get folders with the name we defined. 
        # Which is the creationdate in the format of yyyyMMdd-HHmm
        if (($item.PSIsContainer) -and ($item.Name -match '^\d{8}-\d{4}$'))
        {
            $folderObj.add($item)
        }
    }

    # Sort decending and skip the newest folders we need to keep based on $MinExportFoldersToKeep
    $folderObjSorted = $folderObj | Sort-Object -Property Name -Descending | Select-Object -Skip $MinExportFoldersToKeep
    foreach ($item in $folderObjSorted)
    {
    
        $date = [DateTime]::ParseExact($item.Name, "yyyyMMdd-HHmm", $null)
        $timeSpan = New-TimeSpan -Start $date -End (Get-Date)
        if ($timeSpan.TotalDays -gt $MaxExportFolderAgeInDays)
        {
            Write-CMTraceLog -Message "Will delete: $($item.FullName) since it is $([math]::Round($timeSpan.TotalDays)) days old"
            try
            {
                Remove-Item $item.FullName -Recurse -Force -ErrorAction Stop
            }
            Catch
            {
                Write-CMTraceLog -Message "Not able to delete: $($item.FullName) Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Error
                Write-CMTraceLog -Message "$($_)" -Severity Error
                $script:ExitWithError = $true   
            }
        }
    }
}
#endregion


#region function Get-SanitizedPath
<#
.SYNOPSIS
    Function to replace invalid characters with underscore to be able to export data in folders
#>
function Get-SanitizedPath
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    # Get invalid path characters
    $invalidChars = [IO.Path]::GetInvalidPathChars() -join ''

    # Escape special regex characters
    $invalidChars = [Regex]::Escape($invalidChars)

    # Replace invalid characters with underscore
    return ($Path -replace "[$invalidChars]", '_')
}
#endregion


#region function Get-SanitizedFileName
<#
.SYNOPSIS
    Function to replace invalid characters with underscore to be able to export data in folders
#>
function Get-SanitizedFileName
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [string]$FileName
    )

    # Replace invalid characters with underscore
    return ($FileName -replace '[\[\\/:*?"<>|\]]', '_' -replace ',')
}
#endregion


#region Function Get-ConfigMgrObjectLocation
<#
.SYNOPSIS
    This function retrieves the full folder path of a Configuration Manager object.

.DESCRIPTION
    The function uses the 'SMS_ObjectContainerItem' and 'SMS_ObjectContainerNode' WMI classes to find the object and its associated folder path.
    It starts from the object's immediate container node and traverses up the tree until it reaches the root level, constructing the full folder path along the way.

.PARAMETER SiteServer
    The name of the site server. Defaults to the name of the current computer.

.PARAMETER SiteCode
    The site code. Defaults to 'P02'.

.PARAMETER ObjectUniqueID
    The unique ID of the object.

.PARAMETER ObjectTypeName
    The type of the object. See documentation of SMS_ObjectContainerItem for the different types.

.EXAMPLE
    Get-ConfigMgrObjectLocation -SiteServer "smsprovider.conto.local" -SiteCode "P02" -ObjectUniqueID "ScopeId_CD62B756-B593-4D99-98DE-0CA5DAFCF42C/Application_64aa7af8-5730-44bf-8626-fdb29bf84955" -ObjectTypeName "SMS_ConfigurationItemLatest"

#>
Function Get-ConfigMgrObjectLocation
{
    param
    (
        $SiteServer = $script:ProviderMachineName, 
        $SiteCode = $script:SiteCode, 
        $ObjectUniqueID, 
        $ObjectTypeName 
    )

    $fullFolderPath = ""
    $wmiQuery = "SELECT ocn.* FROM SMS_ObjectContainerNode AS ocn JOIN SMS_ObjectContainerItem AS oci ON ocn.ContainerNodeID=oci.ContainerNodeID WHERE oci.InstanceKey='{0}' and oci.ObjectTypeName ='{1}'" -f $ObjectUniqueID, $ObjectTypeName
    [array]$containerNode = Get-WmiObject -Namespace "root/SMS/site_$($SiteCode)" -ComputerName $SiteServer -Query $wmiQuery
    if ($containerNode)
    {
        if ($containerNode.count -gt 1)
        {
            Write-CMTraceLog -Message "Unusual amount of folder nodes found: $($containerNodes.count) for object `"$($ObjectUniqueID)`"" -Severity Warning
        }
        $fullFolderPath = $containerNode.Name

        $parentContainerNodeID = $containerNode.ParentContainerNodeID
        While ($parentContainerNodeID -ne 0)
        {
            # Lets get the parent folder until we are at the root level
            $ParentContainerNode = Get-WmiObject -Namespace root/SMS/site_$($SiteCode) -ComputerName $SiteServer -Query "SELECT * FROM SMS_ObjectContainerNode WHERE ContainerNodeID = '$parentContainerNodeID'"
            $fullFolderPath = '{0}\{1}' -f $ParentContainerNode.Name, $fullFolderPath
            $parentContainerNodeID = $ParentContainerNode.ParentContainerNodeID
        }

        $fullFolderPath = '\{0}' -f $fullFolderPath

        return $fullFolderPath
    }
    return '\'
}
#endregion


#region function New-CMCollectionListCustom
function New-CMCollectionListCustom
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [object[]]$cmItems
    )
    Begin
    {
        $out = [System.Collections.Generic.List[pscustomobject]]::new()
        
        # Data from SQL table dbo.RBAC_SecuredObjectTypes
        $deploymentTypeHash = @{
            2 = "SMS_Package"
            7 = "SMS_TaskSequence"
            9 = "SMS_MeteredProductRule"
            11 = "SMS_Baseline"
            14 = "SMS_OperatingSystemInstallPackage"
            20 = "SMS_TaskSequencePackage"
            21 = "SMS_DeviceSettingPackage"
            22 = "SMS_DeviceSettingItem"
            23 = "SMS_DriverPackage"
            24 = "SMS_SoftwareUpdatesPackage"
            25 = "SMS_Driver"
            31 = "SMS_Application"
            34 = "SMS_AuthorizationList"
            36 = "SMS_DeviceEnrollmentProfile"
            37 = "SMS_SoftwareUpdate"
            38 = "SMS_ClientSettings"
            47 = "SMS_AntimalwareSettings"
            48 = "SMS_ConfigurationPolicy"
            49 = "SMS_FirewallSettings"
            52 = "SMS_UserStateManagementSettings"
            53 = "SMS_FirewallPolicy"
            56 = "SMS_WirelessProfileSettings"
            57 = "SMS_VpnConnectionSettings"
            58 = "SMS_ClientAuthCertificateSettings"
            59 = "SMS_RemoteConnectionSettings"
            60 = "SMS_TrustedRootCertificateSettings"
            61 = "SMS_CommunicationsProvisioningSettings"
            62 = "SMS_AppRestrictionSettings"
            64 = "SMS_CompliancePolicySettings"
            65 = "SMS_PfxCertificateSettings"
            67 = "SMS_AllowOrDenyAppsSetting"
            69 = "SMS_CustomConfigurationSettings"
            70 = "SMS_TermsAndConditionsSettings"
            71 = "SMS_EditionUpgradeSettings"
            73 = "MDM_GenericAppConfiguration"
            78 = "SMS_PassportForWorkProfileSettings"
            80 = "SMS_AdvancedThreatProtectionSettings"
            81 = "SMS_DeviceThreatProtectionSettings"
            82 = "SMS_WSfBConfigurationData"
            86 = "SMS_ComplianceNotificationSettings"
            87 = "SMS_WindowsDefenderAntimalwareSettings"
            88 = "SMS_FirewallComplianceSettings"
            89 = "SMS_UacComplianceSettings"
            200 = "SMS_CIAssignment"
            201 = "SMS_Advertisement"
            202 = "SMS_ClientSettingsAssignment"
            207 = "SMS_PolicyProperty"
            209 = "SMS_MDMCorpOwnedDevices"
            210 = "SMS_MDMCorpEnrollmentProfiles"
            211 = "SMS_WindowsDefenderApplicationGuard"
            212 = "SMS_DeviceGuardSettings"
            213 = "SMS_Scripts"
            214 = "SMS_WindowsUpdateForBusinessConfigurationSettings"
            215 = "SMS_ActionAccountResult"
            216 = "SMS_ManagementInsights"
            217 = "SMS_CoManagementSettings"
            218 = "SMS_ExploitGuardSettings"
            219 = "SMS_PhasedDeployment"
            220 = "SMS_EdgeBrowserSettings"
            222 = "SMS_M365ASettings"
            223 = "SMS_OneDriveKnownFolderMigrationSettings"
            224 = "SMS_ApplicationGroup"
            225 = "SMS_BitlockerManagementSettings"
            227 = "SMS_MachineOrchestrationGroup"
            228 = "SMS_AntiMalwareSettingsPolicy"
        }

        $deploymentIntentHash = @{
            0 = "Required"
            1 = "Unknown"
            2 = "Available"
            3 = "Unknown"
        }

        $collectionTypeHash = @{
            0 = "Other"
            1 = "User"
            2 = "Device"
        }

    }
    Process
    {
        $item = $_ # $_ coming from pipeline

        Write-CMTraceLog -Message "Working on collection: `"$($item.Name)`""

        # Lets find the collection folder
        $paramSplatting = @{
            ObjectUniqueID = $item.CollectionID
            ObjectTypeName = 'SMS_Collection_{0}' -f $collectionTypeHash[[int]($item.CollectionType)]
        }    
        
        $resolvedItemPath = Get-ConfigMgrObjectLocation @paramSplatting

        # Lets get the refresh type
        if ($item.RefreshType -eq 0) 
        {
            $refreshType = 'None'
        } 
        elseif ($item.RefreshType -eq 1) 
        {
            $refreshType = 'None' # = manual, which basically means none
        } 
        elseif ($item.RefreshType -band 4 -and $item.RefreshType -band 2) 
        {
            $refreshType = 'Both'
        }        
        elseif ($item.RefreshType -band 4) 
        {
            $refreshType = 'Continuous'
        } 
        elseif ($item.RefreshType -band 2) 
        {
            $refreshType = 'Periodic'
        }  
        else 
        {
            $refreshType = 'Unknown'
        }


        $collItem = [pscustomobject]@{
            SmsProviderObjectPath = 'SMS_Collection'
            CollectionType = $collectionTypeHash[[int]($item.CollectionType)]
            CollectionID = $item.CollectionID
            CollectionName = $item.Name
            LimitToCollectionID = $item.LimitToCollectionID
            LimitToCollectionName = $item.LimitToCollectionName
            IsBuiltIn = $item.IsBuiltIn
            ObjectPath = $resolvedItemPath
            CollectionRules = $null
            RefreshType = $refreshType
            RefreshSchedule = $null
            RefreshScheduleString = $item.RefreshSchedule | Convert-CMSchedule # Will result in schedule string which can be used to create the shedule easily
            CollectionVariables = $null
            MaintenanceWindows = $null
            Deployments = $null

        }

        # Lets get the collection rules
        $rulesList = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($rule in $item.CollectionRules)
        {
            switch ($rule.ObjectClass) 
            {
                "SMS_CollectionRuleDirect" 
                {
                    $rulesList.Add([pscustomobject]@{
                        Type = "DirectRule"
                        RuleName = $rule.RuleName
                        ResourceID = $rule.ResourceID
                    })
                }
                "SMS_CollectionRuleQuery" 
                {
                    $rulesList.Add([pscustomobject]@{
                        Type = "QueryRule"
                        RuleName = $rule.RuleName
                        QueryID = $rule.QueryID
                        QueryExpression = $rule.QueryExpression
                    })
                }
                "SMS_CollectionRuleIncludeCollection" 
                {
                    $rulesList.Add([pscustomobject]@{
                        Type = "IncludeRule"
                        RuleName = $rule.RuleName
                        IncludeCollectionID = $rule.IncludeCollectionID
                    })
                }
                "SMS_CollectionRuleExcludeCollection" 
                {
                    $rulesList.Add([pscustomobject]@{
                        Type = "ExcludeRule"
                        RuleName = $rule.RuleName
                        ExcludeCollectionID = $rule.ExcludeCollectionID
                    })
                }
                Default 
                {
                    $rulesList.Add([pscustomobject]@{
                        Type = "UnknownRule"
                        RuleName = $rule.RuleName
                    })
                }
            }
        }

        $collItem.CollectionRules = $rulesList

        # Lets get the refresh schedule
        $refreshScheduleList = [System.Collections.Generic.List[PSCustomObject]]::new()
        $i = 0
        Foreach($schedule in $item.RefreshSchedule) 
        {
            $i++
            $refreshScheduleList.Add([PSCustomObject]@{
                Name = "Schedule $i"
                Type = ($schedule.OverridingObjectClass -replace "SMS_ST_", "")
                Day = $schedule.Day
                DayDuration = $schedule.DayDuration
                DaySpan = $schedule.DaySpan
                HourDuration = $schedule.HourDuration
                HourSpan = $schedule.HourSpan
                IsGMT = $schedule.IsGMT
                MinuteDuration = $schedule.MinuteDuration
                MinuteSpan = $schedule.MinuteSpan
                MonthDay = $schedule.MonthDay
                StartTime = $schedule.StartTime.ToString("yyyymmddHHMMss.000000+***")
                ForNumberOfWeeks = $schedule.ForNumberOfWeeks
                WeekOrder = $schedule.WeekOrder
                ForNumberOfMonths = $schedule.ForNumberOfMonths
            })   
        }

        $collItem.RefreshSchedule = $refreshScheduleList

        if (($item.CollectionVariablesCount -gt 0) -or ($item.MaintenanceWindowsCount -gt 0))
        {
            Write-CMTraceLog -Message "Collection has variables or maintenance windows, need to load lazy properties"
            $wmiQuery = "Select * from SMS_CollectionSettings where CollectionID = '$($item.CollectionID)'"
            $collectionSettings = Get-WMIObject -NameSpace "root\sms\site_$($script:SiteCode)" -Query $wmiQuery -ComputerName $script:ProviderMachineName
            if ($collectionSettings)
            {
                $collectionSettings.Get()
            }
        }


        # Lets add the collection variables
        if ($item.CollectionVariablesCount -gt 0) 
        {
            $CollectionVariables = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Variable in $collectionSettings.CollectionVariables) 
            {
                $CollectionVariables.Add([PSCustomObject]@{
                    Name = $Variable.Name
                    Value = $Variable.Value
                    IsMasked = $Variable.IsMasked
                })
            }            
        }
        
        $collItem.CollectionVariables = $CollectionVariables

        # Lets add maintenance windows
        if ($item.ServiceWindowsCount -gt 0) 
        {
            $MaintenanceWindows = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Window in $collectionSettings.ServiceWindows) 
            {
                $MaintenanceWindows.Add([PSCustomObject]@{
                    Name = $Window.Name
                    Description = $Window.Description
                    IsEnabled = $Window.IsEnabled
                    IsGMT = $Window.IsGMT
                    Starttime = $Window.Starttime #.ToString("yyyymmddHHMMss.000000+***")
                    ServiceWindowType = $Window.ServiceWindowType
                    ServiceWindowSchedules = $Window.ServiceWindowSchedules
                    RecurrenceType = $Window.RecurrenceType
                    Duration = $Window.Duration
                    
                })
            }            
        }

        $collItem.MaintenanceWindows = $MaintenanceWindows

        # Lets check if we have deployments
        $wmiQuery = "Select deploymentID, DeploymentName, TargetName, DeploymentIntent, DeploymentType, TargetSubName from SMS_DeploymentInfo where CollectionID='$($item.CollectionID)'"
        try 
        {
            Write-CMTraceLog -Message "Loading collection deployments"
            [array]$deployments = Get-WMIObject -NameSpace "root\sms\site_$($script:SiteCode)" -Query $wmiQuery -ComputerName $script:ProviderMachineName -ErrorAction Stop
        }
        catch 
        {
            Write-CMTraceLog -Message "Error exporting getting collection deployments. Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Error
            Write-CMTraceLog -Message "$($_)" -Severity Error
            $script:ExitWithError = $true
        }

        # Lets add the deployments
        if ($deployments.count -gt 0)
        {
            Write-CMTraceLog -Message "Collection has deployments"
            $deploymentsList = [System.Collections.Generic.List[PSCustomObject]]::new()
    
            # First just all deployments except updates
            foreach ($deployment in ($deployments.Where({$_.DeploymentType -ne 37})))
            {
                $deploymentsList.Add([pscustomobject]@{
                    DeploymentID = $deployment.DeploymentID
                    DeploymentName = $deployment.DeploymentName
                    TargetName = $deployment.TargetName
                    DeploymentIntent = If ($null -eq ($deploymentIntentHash[[int]($deployment.DeploymentIntent)])){'Unknown'}else{($deploymentIntentHash[[int]($deployment.DeploymentIntent)])}
                    DeploymentType = If ($null -eq ($deploymentTypeHash[[int]($deployment.DeploymentType)])){'Unknown'}else{($deploymentTypeHash[[int]($deployment.DeploymentType)])}
                    ActionName = $deployment.TargetSubName
                })
            }
        
            # Now all updates but just the update group or individual deployed update deploymentname, to limit the output
            foreach ($deployment in ($deployments.Where({$_.DeploymentType -eq 37}) | Select-Object deploymentID, DeploymentName, DeploymentIntent, DeploymentType, TargetSubName -Unique)) 
            {
                $deploymentsList.Add([pscustomobject]@{
                    DeploymentID = $deployment.DeploymentID
                    DeploymentName = $deployment.DeploymentName
                    TargetName = $null
                    DeploymentIntent = If ($null -eq ($deploymentIntentHash[[int]($deployment.DeploymentIntent)])){'Unknown'}else{($deploymentIntentHash[[int]($deployment.DeploymentIntent)])}
                    DeploymentType = If ($null -eq ($deploymentTypeHash[[int]($deployment.DeploymentType)])){'Unknown'}else{($deploymentTypeHash[[int]($deployment.DeploymentType)])}
                    ActionName = $deployment.TargetSubName
                })
            }

            $collItem.Deployments = $deploymentsList
        }
        else
        {
            Write-CMTraceLog -Message "Collection has no deployments"
        }
        
        $out.Add($collItem)
    }
    End
    {
        $out
    }
}
#endregion


#region function Export-CMItemCustomFunction
<#
.SYNOPSIS
    Function to export certain configmgr items
#>
function Export-CMItemCustomFunction
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [object[]]$cmItems
    )

    Begin{}
    Process
    {
        $item = $_ # $_ coming from pipeline
        $itemObjectTypeName = $item.SmsProviderObjectPath -replace '\..*'
        $skipConfigMgrFolderSearch = $false # some items don't support folder. So, no need to look for one

        # We might need to read data from different properties
        switch ($itemObjectTypeName)
        {
            'SMS_ConfigurationItemLatest'
            {
                if ($item.LocalizedDisplayName -ieq 'Built-In')
                {
                    # Skip build-in CIs
                    return
                }
                else 
                {              
                    # We need a folder to store CIs in
                    $itemExportRootFolder = '{0}\CI' -f $script:FullExportFolderName
                    $itemModelName = $item.ModelName
                    $itemFileExtension = '.cab'
                    $itemFileName = (Get-SanitizedFileName -FileName ($item.LocalizedDisplayName))
                }
            }
            'SMS_ConfigurationBaselineInfo'
            {
                # We need a folder to store baselines in
                $itemExportRootFolder = '{0}\Baseline' -f $script:FullExportFolderName
                $itemModelName = $item.ModelName
                $itemFileExtension = '.cab'
                $itemFileName = (Get-SanitizedFileName -FileName ($item.LocalizedDisplayName))
            }
            'SMS_TaskSequencePackage'
            {
                # We need a folder to store TaskSequences in
                $itemExportRootFolder = '{0}\TS' -f $script:FullExportFolderName
                $itemModelName = $item.PackageID
                $itemFileExtension = '.zip'
                $itemFileName = (Get-SanitizedFileName -FileName ($item.Name))
            }
            'SMS_AntimalwareSettings'
            {
                # We need a folder to store AntimalwarePolicies in
                $itemExportRootFolder = '{0}\AntimalwarePolicy' -f $script:FullExportFolderName
                $itemModelName = $item.SettingsID
                $itemFileExtension = '.xml'
                $itemFileName = (Get-SanitizedFileName -FileName ($item.Name))       
                $skipConfigMgrFolderSearch = $true     
            }
            'SMS_Scripts'
            {
                # We need a folder to store AntimalwarePolicies in
                $itemExportRootFolder = '{0}\Scripts' -f $script:FullExportFolderName
                $itemModelName = $item.ScriptGuid
                $itemFileExtension = '.ps1'
                # we will also export the whole script definition as json, just in case
                $itemFileName = (Get-SanitizedFileName -FileName ($item.ScriptName))        
                $skipConfigMgrFolderSearch = $true        
            
            }
            'SMS_ClientSettings'
            {
                # We need a folder to store AntimalwarePolicies in
                $itemExportRootFolder = '{0}\ClientSettings' -f $script:FullExportFolderName
                $itemModelName = $item.Name
                $itemFileExtension = '.txt'
                # we will also export the whole script definition as json, just in case
                $itemFileName = (Get-SanitizedFileName -FileName ($item.Name))       
                $skipConfigMgrFolderSearch = $true                 
            }
            'SMS_ConfigurationPolicy'
            {
                if ($item.CategoryInstance_UniqueIDs -imatch 'SMS_BitlockerManagementSettings')
                {
                    $itemExportRootFolder = '{0}\BitlockerPolicies' -f $script:FullExportFolderName
                    $itemModelName = $item.LocalizedDisplayName
                    $itemFileExtension = '.xml'
                    $itemFileName = (Get-SanitizedFileName -FileName ($item.LocalizedDisplayName))
                    $skipConfigMgrFolderSearch = $true 
                }
                else
                {
                    # skip all other configuration polices
                    return
                }          
            
            }
            Default 
            {
                # Happens typically for antimalwarepolicies, since the default policy has a different type
                return
            }
        }

        # We might need to create the folder first
        if (-not (Test-Path $itemExportRootFolder)) 
        {
            New-Item -ItemType Directory -Path $itemExportRootFolder -Force | Out-Null
        }

        # $item.ObjectPath is not reliable enough. It sometimes has no value, but the item is in a sub-folder and sometimes it is missing completly.
        # That's why we always rely on the Get-ConfigMgrObjectLocation function
        $paramSplatting = @{
            ObjectUniqueID = $itemModelName
            ObjectTypeName = $itemObjectTypeName
        }    
        
        # Not all items support folder. Lets skip the search in that case
        if ($skipConfigMgrFolderSearch)
        {
            $resolvedItemPath = '\'
        }
        else
        {
            $resolvedItemPath = Get-ConfigMgrObjectLocation @paramSplatting
        }
                
        if ($resolvedItemPath -eq '\')
        {
            $itemExportFolder = $itemExportRootFolder    
        }
        else
        {
            $itemExportFolder = '{0}{1}' -f $itemExportRootFolder, $resolvedItemPath
            $itemExportFolder = $itemExportFolder -replace '\\{2}', '\' # making sure we don't have \\ in the path.            
        }

        # Removing illegal characters from folder path
        $itemExportFolder = Get-SanitizedPath -Path $itemExportFolder

        # Lets make sure the folder is there
        if (-not (Test-Path $itemExportFolder)) 
        {
            New-Item -ItemType Directory -Path $itemExportFolder -Force | Out-Null
        }


        # Now lets build the full file name to be exported
        $itemFullName = '{0}\{1}{2}' -f $itemExportFolder, $itemFileName, $itemFileExtension


        # Path might be too long 
        if ($itemFullName.Length -ge 254)
        {
            Write-CMTraceLog -Message "Path too long for item: $($itemFullName). Will try to store item in root folder" -Severity Warning
            # Now lets correct the fullname to the root folder
            $itemFullName = '{0}\{1}{2}' -f $itemExportRootFolder, $itemFileName, $itemFileExtension
        }

        # Lets check if its still too long and then skip the item
        if ($itemFullName.Length -ge 254)
        {
            Write-CMTraceLog -Message "Path still too long for item: $($itemFullName). We need to skip the item" -Severity Warning
        }
        else
        {

            # File names for extra info
            $metadataFileName = '{0}\{1}.metadata.xml' -f ($itemFullName | Split-Path -Parent), ([System.IO.Path]::GetFileNameWithoutExtension($itemFullName))
            $deploymentsFileName = '{0}\{1}.deployments.xml' -f ($itemFullName | Split-Path -Parent), ([System.IO.Path]::GetFileNameWithoutExtension($itemFullName))
            $inventoryFileName = '{0}\{1}.hinvclasses.xml' -f ($itemFullName | Split-Path -Parent), ([System.IO.Path]::GetFileNameWithoutExtension($itemFullName))
            $tsReferenceFileName = '{0}\{1}.references.xml' -f ($itemFullName | Split-Path -Parent), ([System.IO.Path]::GetFileNameWithoutExtension($itemFullName))

            # Lets put the file info in a little inventory file
            $inventoryFile = '{0}\_Inventory.txt' -f $itemExportRootFolder
            "Name:   $($itemFullName | Split-Path -Leaf)" | Out-File -FilePath $inventoryFile -Append
            "Path:   $($itemFullName)" | Out-File -FilePath $inventoryFile -Append
            "ItemID:   $($itemModelName)" | Out-File -FilePath $inventoryFile -Append
            ($script:Spacer * 50) | Out-File -FilePath $inventoryFile -Append

            try
            {
                switch ($itemObjectTypeName)
                {
                    'SMS_ConfigurationItemLatest'
                    {
                        Write-CMTraceLog -Message "Will export CI: $($itemFullName)"
                        Export-CMConfigurationItem -Id $item.CI_ID -Path $itemFullName

                        # Lets also export medatdata
                        $item | Export-Clixml -Depth 100 -Path $metadataFileName
                    }
                    'SMS_ConfigurationBaselineInfo'
                    {
                        Write-CMTraceLog -Message "Will export Baseline: $($itemFullName)"
                        Export-CMBaseline -Id $item.CI_ID -Path $itemFullName

                        # Lets also export some metadata and the deployments
                        $item | Export-Clixml -Depth 100 -Path $metadataFileName

                        if ($item.IsAssigned)
                        {
                            $baselineDeployments = Get-CMBaselineDeployment -Fast -SmsObjectId $item.CI_ID -ErrorAction SilentlyContinue
                            if ($baselineDeployments)
                            {
                                $baselineDeployments | Export-Clixml -Depth 100 -Path $deploymentsFileName
                            }
                        }

                    }
                    'SMS_TaskSequencePackage'
                    {
                        Write-CMTraceLog -Message "Will export Tasksequence: $($itemFullName)"
                        Export-CMTaskSequence -TaskSequencePackageId $item.PackageID -ExportFilePath $itemFullName

                        # Lets also export medatdata
                        $item | Export-Clixml -Depth 100 -Path $metadataFileName

                        $tsDeployments = Get-CMTaskSequenceDeployment -TaskSequenceId $item.PackageID -WarningAction Ignore -ErrorAction SilentlyContinue
                        if ($tsDeployments)
                        {
                            $tsDeployments | Export-Clixml -Depth 100 -Path $deploymentsFileName 
                        }

                        # Lets export the TS refenrence data as well
                        $wmiQuery = "Select * from SMS_TaskSequencePackageReference_Flat where PackageID = '$($item.PackageID)'"
                        #$tsRefData = Get-CimInstance -ComputerName $script:ProviderMachineName -Namespace "root\sms\site_$script:SiteCode" -Query $wmiQuery -ErrorAction SilentlyContinue
                        
                        try
                        {
                            $tsRefData = Invoke-CMWmiQuery -Query $wmiQuery -ErrorAction Stop
                            if ($tsRefData)
                            {
                                $tsRefData | Export-Clixml -Path $tsReferenceFileName
                            }
                        }
                        catch
                        {
                            Write-CMTraceLog -Message "Export of TS references failed. Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Warning
                            Write-CMTraceLog -Message "$_" -Severity Warning
                        }

                    }
                    'SMS_AntimalwareSettings'
                    {
                        Write-CMTraceLog -Message "Will export AntimalwareSettings: $($itemFullName)"
                        Export-CMAntimalwarePolicy -id $item.SettingsID -Path $itemFullName

                        $settingsDeployments = Get-CMClientSettingDeployment -Id $item.SettingsID -ErrorAction SilentlyContinue
                        if ($settingsDeployments)
                        {
                            $settingsDeployments | Export-Clixml -Depth 100 -Path $deploymentsFileName 
                        }


                    }
                    'SMS_Scripts'
                    {
                        # we need to filter out the default CMPivot script
                        if($item.ScriptName -ine 'CMPivot')
                        {
                            Write-CMTraceLog -Message "Will export Script: $($itemFullName)"
                            $ScriptContent = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($item.Script))
                        
                            $ScriptContent | Out-File -Encoding unicode -FilePath $itemFullName

                            $item | Export-Clixml -Depth 100 -Path ($itemFullName -replace 'ps1', 'xml')

                        }
                        
                    }
                    'SMS_ClientSettings'
                    {
                        Write-CMTraceLog -Message "Will export Client Setting: $($itemFullName)"
                    
                        # Lets also export medatdata
                        $item | Export-Clixml -Depth 100 -Path $metadataFileName

                        $settingsDeployments = Get-CMClientSettingDeployment -Id $item.SettingsID -ErrorAction SilentlyContinue
                        if ($settingsDeployments)
                        {
                            $settingsDeployments | Export-Clixml -Depth 100 -Path $deploymentsFileName 
                        }

                        # Lets test if we have hardware inventory data and export that too
                        $hinvDataItem = $item.Properties.AgentConfigurations | Where-Object -Property AgentID -EQ 15
                        if ($hinvDataItem)
                        {
                            $wmiQuery = "Select * from SMS_InventoryReport where InventoryReportID = '$($hinvDataItem.InventoryReportID)'"
                            #$inventoryReport = Get-CimInstance -ComputerName $script:ProviderMachineName -Namespace "root\sms\site_$script:SiteCode" -Query $wmiQuery -ErrorAction SilentlyContinue

                            try
			                {
                                $inventoryReport = Invoke-CMWmiQuery -Query $wmiQuery -Option Fast -ErrorAction Stop 
                                if ($inventoryReport)
                                {
                                    # load lazy properties
                                    #$inventoryReport = $inventoryReport | Get-CimInstance
                                    $inventoryReport.Get() # -Option lazy does not seem to work properly, hence the get()
                                    $inventoryReport | Export-Clixml -Depth 100 -Path $inventoryFileName
                                }
                            }
                            catch
                            {
                                Write-CMTraceLog -Message "Export of HINV data failed. Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Warning
                                Write-CMTraceLog -Message "$_" -Severity Warning
                            }                            

                        }
                
                    }
                    'SMS_ConfigurationPolicy'
                    {
                        Write-CMTraceLog -Message "Will export ConfigurationPolicy: $($itemFullName)"
                        # Lets also export medatdata
                        $item | Export-Clixml -Depth 100 -Path $metadataFileName

                        $configDeployments = Get-CMConfigurationPolicyDeployment -SmsObjectId $item.CI_ID -ErrorAction SilentlyContinue -WarningAction Ignore
                        if ($configDeployments)
                        {
                            $configDeployments | Export-Clixml -Depth 100 -Path $deploymentsFileName 
                        }

                        Get-CMConfigurationPolicy -Id $item.CI_ID -AsXml -WarningAction Ignore | Out-File -FilePath $itemFullName -Append
                    
                    }
                    Default {}
                }
            }
            catch
            {
                 Write-CMTraceLog -Message "Error exporting: $($itemFullName). Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Error
                 Write-CMTraceLog -Message "$($_)" -Severity Error
                 $script:ExitWithError = $true
            }
        }
    }
    End{}
}
#endregion 


#region Compress-FolderOnRemoteMachine
Function Compress-FolderOnRemoteMachine
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$RemoteComputerName,

        [Parameter(Mandatory = $true)]
        [string]$FolderToZip,

        [Parameter(Mandatory = $true)]
        [string]$ZipFileName,

        [Parameter(Mandatory = $false)]
        [string]$ZipFolder # will be a temp folder on the same drive of the folder to compress
    )

    # Script block to run on the remote machine
    $scriptBlock = {
        param (
            [string]$FolderToZip,
            [string]$ZipFileName,
            [string]$ZipFolder
        )

        if ([string]::IsNullOrEmpty($ZipFolder))
        {
            $Matches = $null
            if ($FolderToZip -imatch '^[A-Za-z]:\\')
            {
                $ZipFolder = '{0}Temp' -f $Matches[0]       
            }          
        }

        if (-Not ($ZipFolder -imatch '^[A-Za-z]:\\(?:[^\\\/:*?"<>|\r\n]+\\)*[^\\\/:*?"<>|\r\n]*$'))
        {
            Write-Error 'Failed to get valid local path to store zip file'
        }

        # Ensure the destination directory exists
        if (-not (Test-Path -Path $ZipFolder))
        {
            $null = New-Item -ItemType Directory -Path $ZipFolder -Force
        }

        # Making sure we have the correct path
        if ($ZipFolder -imatch '\\$')
        {
            $ZipFolder = $ZipFolder -replace '\\$'
        }

        # File full name to store the zip file
        $zipFileFullName = '{0}\{1}' -f $ZipFolder, $ZipFileName

        # Create the zip file
        $null = Compress-Archive -Path $FolderToZip -DestinationPath $zipFileFullName -Force -ErrorAction Stop

        if (-NOT (Test-Path $zipFileFullName))
        {
            Write-Error "Compressed file not found: $($zipFileFullName)"
        }

        return $zipFileFullName
    }

    # Invoke the script block on the remote machine
    $result = Invoke-Command -ComputerName $remoteComputerName -ScriptBlock $scriptBlock -ArgumentList $FolderToZip, $ZipFileName, $ZipFolder -ErrorAction Stop -ErrorVariable errorvar

    # Check for errors
    if ($errorvar)
    {
        return $errorvar
    }

    return $result
}
#endregion


#region Start-RoboCopy
Function Start-RoboCopy
{
    [CmdletBinding()]
    Param
    (
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$Source,
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string]$Destination,
        [parameter(Mandatory=$False,ValueFromPipeline=$false)]
        [string]$FileNames, # File(s) to copy  (names/wildcards: default is "*.*").
        [parameter(Mandatory=$False,ValueFromPipeline=$false)]
        [string]$CommonRobocopyParams='/NP /R:10 /W:10 /Z /E',
        [parameter(Mandatory=$True,ValueFromPipeline=$false)]
        [string] $RobocopyLogPath,
        [parameter(Mandatory=$False,ValueFromPipeline=$false)]
        [string]$IPG = 0
        # IPG will effect the overall runtime of the script
    )

    # /MIR :: MIRror a directory tree (equivalent to /E plus /PURGE)
    # /NP :: No Progress - don't display percentage copied.
    # /NDL :: No Directory List - don't log directory names.
    # /NC :: No Class - don't log file classes.
    # /BYTES :: Print sizes as bytes.
    # /NJH :: No Job Header.
    # /NJS :: No Job Summary.
    # /R:10 :: 10 retries
    # /W:10 :: 10 seconds waittime between retries
    # example CommonRobocopyParams = '/MIR /NP /NDL /NC /BYTES /NJH /NJS'

    if ([string]::IsNullOrEmpty($FileNames))
    {
        $ArgumentList = '"{0}" "{1}" /LOG:"{2}" /ipg:{3} {4}' -f $Source, $Destination, $RobocopyLogPath, $IPG, $CommonRobocopyParams
    }
    else
    {
        $ArgumentList = '"{0}" "{1}" "{2}" /LOG:"{3}" /ipg:{4} {5}' -f $Source, $Destination, $FileNames, $RobocopyLogPath, $IPG, $CommonRobocopyParams
    }

    #Check if robocopy is accessible      
    Write-CMTraceLog -Message "Start RoboCopy with the following parameters: `"$ArgumentList`""
    $roboCopyPath = "C:\windows\system32\robocopy.exe"
    if(-NOT(Test-Path $roboCopyPath))
    {
        Write-CMTraceLog -Message "Robocopy not found: `"$roboCopyPath`"" -Severity Error
        Exit 1
    }

    try
    {
        $Robocopy = Start-Process -FilePath $roboCopyPath -ArgumentList $ArgumentList -Verbose -PassThru -Wait -WindowStyle Hidden -ErrorAction Stop
    }
    Catch
    {
        Write-CMTraceLog -Message "RoboCopy failed. Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Error
        Write-CMTraceLog -Message "$($_)" -Severity Error
        Exit 1  
    }

    try
    {
        $roboCopyResult = Get-Content $RobocopyLogPath -last 13 -ErrorAction Stop
        # german and english output parser
        $regexResultDirectories = [regex]::Matches($roboCopyResult,'(Dirs|Verzeich\.*)(\s*:\s*)(?<DirsTotal>\d+)\s*(?<DirsCopied>\d+)\s*(?<DirsSkipped>\d+)\s*(?<DirsMismatch>\d+)\s*(?<DirsFailed>\d+)\s*(?<DirsExtras>\d+)\s*' )
        $regexResultFiles = [regex]::Matches($roboCopyResult,'(Files|Dateien)(\s*:\s*)(?<FilesTotal>\d+)\s*(?<FilesCopied>\d+)\s*(?<FilesSkipped>\d+)\s*(?<FilesMismatch>\d+)\s*(?<FilesFailed>\d+)\s*(?<FilesExtras>\d+)\s*' )
        $bolFound = $false

        if ((-NOT([string]::IsNullOrEmpty($regexResultDirectories.value))) -and (-NOT([string]::IsNullOrEmpty($regexResultFiles.value))))
        {
            $bolFound = $true
        }

        $roboCopyResultObject = [pscustomobject]@{
                ResultFoundInLog = $bolFound
                dirsTotal = $regexResultDirectories.Groups.Where({$_.Name -eq 'DirsTotal'}).Value
                dirsCopied = $regexResultDirectories.Groups.Where({$_.Name -eq 'DirsCopied'}).Value
                dirsSkipped = $regexResultDirectories.Groups.Where({$_.Name -eq 'DirsSkipped'}).Value
                dirsMismatch = $regexResultDirectories.Groups.Where({$_.Name -eq 'DirsMismatch'}).Value
                dirsFAILED = $regexResultDirectories.Groups.Where({$_.Name -eq 'DirsFailed'}).Value
                dirsExtras = $regexResultDirectories.Groups.Where({$_.Name -eq 'DirsExtras'}).Value
                filesTotal = $regexResultFiles.Groups.Where({$_.Name -eq 'FilesTotal'}).Value
                filesCopied = $regexResultFiles.Groups.Where({$_.Name -eq 'FilesCopied'}).Value
                filesSkipped = $regexResultFiles.Groups.Where({$_.Name -eq 'FilesSkipped'}).Value
                filesMismatch = $regexResultFiles.Groups.Where({$_.Name -eq 'FilesMismatch'}).Value
                filesFAILED = $regexResultFiles.Groups.Where({$_.Name -eq 'FilesFailed'}).Value
                filesExtras = $regexResultFiles.Groups.Where({$_.Name -eq 'FilesExtras'}).Value
        }
    }
    Catch
    {
        Write-CMTraceLog -Message "Not able to check robocopy log $($_). Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Error
        Write-CMTraceLog -Message "$_" -Severity Error	
        Write-CMTraceLog -Message "Stopping script!" -Severity Warning
        Exit 1
    }

    Write-CMTraceLog -Message "RoboCopy result..."
    Write-CMTraceLog -Message "$roboCopyResultObject"
    if($roboCopyResultObject.ResultFoundInLog -eq $true -and $roboCopyResultObject.FilesFAILED -eq 0 -and $roboCopyResultObject.DirsFAILED -eq 0)
    {   
        Write-CMTraceLog -Message "Copy process successful. Logfile: `"$RobocopyLogPath`""
    }
    else
    {
        Write-CMTraceLog -Message "Copy process failed. Logfile: `"$RobocopyLogPath`"" -Severity Error	
        Write-CMTraceLog -Message "Stopping script!" -Severity Warning
        Exit 1
    }
}
#endregion


#region Get-ConfigMgrSiteInfo
function Get-ConfigMgrSiteInfo
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$ProviderMachineName,
        [Parameter(Mandatory=$true)]
        [string]$SiteCode
    )

    $outObject = [pscustomobject][ordered]@{
        SiteCode = $null
        ParentSiteCode = $null
        InstallDirectory = $null
        SiteDefaultShare = $null
        SiteName = $null
        SiteServerDomain = $null
        SiteServerName = $null
        SiteServerHAList = $null
        SiteServerPlatform = $null
        SiteType = $null
        SQLDatabaseName = $null
        SQLServerName = $null
        SQLDatabase = $null
        SQLInstance = $null
        SQLDatabaseFile = $null
        SQLDatabaseLogFile = $null
        SQLServerSSBCertificateThumbprint = $null
        SQLSSBPort = $null # was 'SSBPort'
        SQLServicePort = $null
        LocaleID = $null
        FullVersion = $null
        FullVersionUpdated = $null
        FullVersionUpdatedName = $null
        CloudConnector = $null
        CloudConnectorServer = $null
        CloudConnectorOfflineMode = $null
        SMSProvider = $null
        BackupPath = $null
        BackupEnabled = $null
        ConsoleInstalled = $null
        InConsoleUpdates = $null
        SUPList = $null
        SSRSList = $null
    }

    # Setting the output object with as much data as possible
    $outObject.SiteCode = $SiteCode
    $outObject.SMSProvider = $ProviderMachineName
    $outObject.CloudConnector = 0 # setting service connection point to not installed. Will change later if detected as installed
    $outObject.ConsoleInstalled = 0 # same as with cloud connector  
        
    try 
    {
        #$siteDefinition = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -query "SELECT * FROM SMS_SCI_SiteDefinition WHERE FileType=2 AND ItemName='Site Definition' AND ItemType='Site Definition' AND SiteCode='$($SiteCode)'" -ErrorAction Stop    
        $siteDefinition = Invoke-CMWmiQuery -Query "SELECT * FROM SMS_SCI_SiteDefinition WHERE FileType=2 AND ItemName='Site Definition' AND ItemType='Site Definition' AND SiteCode='$($SiteCode)'" -Option Fast -ErrorAction Stop
    }
    catch 
    {
        Write-CMTraceLog -Message "Failed to get site definition. Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Error
        Write-CMTraceLog -Message "$($_)" -Severity Error
        Exit 1
    }
    
    if ($siteDefinition)
    {
        $outObject.ParentSiteCode = $siteDefinition.ParentSiteCode
        $outObject.InstallDirectory = $siteDefinition.InstallDirectory
        $outObject.SiteName = $siteDefinition.SiteName
        $outObject.SiteServerDomain = $siteDefinition.SiteServerDomain
        $outObject.SiteServerName = $siteDefinition.SiteServerName
        $outObject.SiteServerPlatform = $siteDefinition.SiteServerPlatform
        $outObject.SiteType = $siteDefinition.SiteType
        $outObject.SQLDatabaseName = $siteDefinition.SQLDatabaseName
        $outObject.SQLServerName = $siteDefinition.SQLServerName

        # Extract DB Info
        $sqlDBInfo = $outObject.SQLDatabaseName -split '\\'
        if ($sqlDBInfo.Count -eq 2)
        {
            $outObject.SQLDatabase = $sqlDBInfo[1]
            $outObject.SQLInstance = $sqlDBInfo[0]
        }
        else
        {
            $outObject.SQLDatabase = $sqlDBInfo
            $outObject.SQLInstance = "Default"
        }

        # Adding filenames
        $outObject.SQLDatabaseFile = "{0}.mdf" -f $outObject.SQLDataBase
        $outObject.SQLDatabaseLogFile = "{0}_log.ldf" -f $outObject.SQLDataBase
        # Adding SQL Port info
        $outObject.SQlServicePort = ($siteDefinition.props | Where-Object {$_.PropertyName -eq 'SQlServicePort'} | Select-Object -ExpandProperty Value)
        $outObject.SQLSSBPort = ($siteDefinition.props | Where-Object {$_.PropertyName -eq 'SSBPort'} | Select-Object -ExpandProperty Value)
        # Adding language and version
        $outObject.LocaleID = ($siteDefinition.props | Where-Object {$_.PropertyName -eq 'LocaleID'} | Select-Object -ExpandProperty Value)
        $outObject.FullVersion = ($siteDefinition.props | Where-Object {$_.PropertyName -eq 'Full Version'} | Select-Object -ExpandProperty Value1)

        # get list of role servers
        try 
        {
            #$SysResUse = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -query "select * from SMS_SCI_SysResUse where SiteCode = '$($SiteCode)'" -ErrorAction Stop | Select-Object NetworkOsPath, RoleName, PropLists, Props   
            $SysResUse = Invoke-CMWmiQuery -Query "select * from SMS_SCI_SysResUse where SiteCode = '$($SiteCode)'"  -Option Fast -ErrorAction Stop | Select-Object NetworkOsPath, RoleName, PropLists, Props
        }
        catch 
        {
            Write-CMTraceLog -Message "Failed to get role servers. Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Error
            Write-CMTraceLog -Message "$($_)" -Severity Error
            Exit 1
        }
        
        if ($SysResUse)
        {
            $outSupListObj = New-Object System.Collections.ArrayList
            # Iterate through each SUP
            $supList = ($SysResUse | Where-Object {$_.RoleName -eq 'SMS Software Update Point'}) 
            foreach ($sup in $supList)
            {
                $tmpSupObj = [pscustomobject]@{
                    SUPName = $sup.NetworkOsPath -replace '\\\\',''
                    UseProxy = $sup.props | Where-Object {$_.PropertyName -eq 'UseProxy'} | Select-Object -ExpandProperty Value
                    ProxyName = $sup.props | Where-Object {$_.PropertyName -eq 'ProxyName'} | Select-Object -ExpandProperty Value
                    ProxyServerPort = $sup.props | Where-Object {$_.PropertyName -eq 'ProxyServerPort'} | Select-Object -ExpandProperty Value
                    AnonymousProxyAccess = $sup.props | Where-Object {$_.PropertyName -eq 'AnonymousProxyAccess'} | Select-Object -ExpandProperty Value
                    UserName = $sup.props | Where-Object {$_.PropertyName -eq 'UserName'} | Select-Object -ExpandProperty Value
                    UseProxyForADR = $sup.props | Where-Object {$_.PropertyName -eq 'UseProxyForADR'} | Select-Object -ExpandProperty Value
                    IsIntranet = $sup.props | Where-Object {$_.PropertyName -eq 'IsIntranet'} | Select-Object -ExpandProperty Value
                    Enabled = $sup.props | Where-Object {$_.PropertyName -eq 'Enabled'} | Select-Object -ExpandProperty Value
                    DBServerName = $sup.props | Where-Object {$_.PropertyName -eq 'DBServerName'} | Select-Object -ExpandProperty Value2
                    WSUSIISPort = $sup.props | Where-Object {$_.PropertyName -eq 'WSUSIISPort'} | Select-Object -ExpandProperty Value
                    WSUSIISSSLPort = $sup.props | Where-Object {$_.PropertyName -eq 'WSUSIISSSLPort'} | Select-Object -ExpandProperty Value
                    SSLWSUS = $sup.props | Where-Object {$_.PropertyName -eq 'SSLWSUS'} | Select-Object -ExpandProperty Value
                    UseParentWSUS = $sup.props | Where-Object {$_.PropertyName -eq 'UseParentWSUS'} | Select-Object -ExpandProperty Value
                    WSUSAccessAccount = $sup.props | Where-Object {$_.PropertyName -eq 'WSUSAccessAccount'} | Select-Object -ExpandProperty Value
                    AllowProxyTraffic = $sup.props | Where-Object {$_.PropertyName -eq 'AllowProxyTraffic'} | Select-Object -ExpandProperty Value
                }
                [void]$outSupListObj.add($tmpSupObj)

            }
            $outObject.SUPList = $outSupListObj

            $outSSRSListObj = New-Object System.Collections.ArrayList
            # Iterate through each SSRS
            $ssrsList = ($SysResUse | Where-Object {$_.RoleName -eq 'SMS SRS Reporting Point'})
            foreach ($ssrs in $ssrsList)
            {
                $tmpSSRSObj = [pscustomobject]@{
                    SSRSName = $ssrs.NetworkOsPath -replace '\\\\',''
                    DatabaseServerName = $ssrs.props | Where-Object {$_.PropertyName -eq 'DatabaseServerName'} | Select-Object -ExpandProperty Value2
                    ReportServerInstance = $ssrs.props | Where-Object {$_.PropertyName -eq 'ReportServerInstance'} | Select-Object -ExpandProperty Value2
                    ReportManagerUri = $ssrs.props | Where-Object {$_.PropertyName -eq 'ReportManagerUri'} | Select-Object -ExpandProperty Value2
                    ReportServerUri = $ssrs.props | Where-Object {$_.PropertyName -eq 'ReportServerUri'} | Select-Object -ExpandProperty Value2
                    RootFolder = $ssrs.props | Where-Object {$_.PropertyName -eq 'RootFolder'} | Select-Object -ExpandProperty Value2
                    Username = $ssrs.props | Where-Object {$_.PropertyName -eq 'Username'} | Select-Object -ExpandProperty Value2
                    Version = $ssrs.props | Where-Object {$_.PropertyName -eq 'Version'} | Select-Object -ExpandProperty Value2
                }
                [void]$outSSRSListObj.add($tmpSSRSObj)                    
            }
            $outObject.SSRSList = $outSSRSListObj


            $CloudConnectorServer = ($SysResUse | Where-Object {$_.RoleName -eq 'SMS Dmp Connector'})
            if ($CloudConnectorServer)
            {
                $outObject.CloudConnector = 1
                $outObject.CloudConnectorServer = ($CloudConnectorServer.NetworkOsPath -replace '\\\\','') 
                $outObject.CloudConnectorOfflineMode = (($CloudConnectorServer.Props | Where-Object {$_.PropertyName -eq 'OfflineMode'}).value)
            }               
        }

        try 
        {
            $query = "SELECT Enabled, DeviceName FROM SMS_SCI_SQLTask WHERE FileType=2 AND ItemName='Backup SMS Site Server' AND ItemType='SQL Task' AND SiteCode='$($SiteCode)'"
            #$backupInfo = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$($SiteCode)" -query $query -ErrorAction Stop    
            $backupInfo = Invoke-CMWmiQuery -Query $query -Option Fast -ErrorAction Stop
        }
        catch 
        {
            write-CMTraceLog -Message "Failed to get backup info. Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Error
            write-CMTraceLog -Message "$($_)" -Severity Error
            Exit 1
        }
        
        if ($backupInfo)
        {
            $outObject.BackupEnabled = $backupInfo.Enabled
            $outObject.BackupPath = $backupInfo.DeviceName
        }
        else
        {
            $outObject.BackupEnabled = 'Unknown'
        }
      
        try 
        {
            # Is console installed on site server?
            # will use WMI/CIM method to avoid any issues with remote registry access
            $regKeyPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\ConfigMgr10\AdminUI"
            $regKeyValue = "AdminUILog"
            if (Get-RegistryValueFromRemoteMachine -ComputerName $siteDefinition.SiteServerName -RegKeyPath $regKeyPath -RegKeyValue $regKeyValue -Method GetStringValue) 
            {
                $outObject.ConsoleInstalled = 1
            }         
        }
        catch 
        {
            # We will ignore any errors. The console can be installed at any time. That info is not that important. 
        }

    }

    # Getting site update information
    try 
    {
        $query = 'SELECT Name, PackageGuid, DateReleased, DateCreated, Description, FullVersion, ClientVersion, State FROM SMS_CM_UpdatePackages WHERE UpdateType != 3'
        #[array]$configMgrUpdates = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -Query $query -ErrorAction stop        
        [array]$configMgrUpdates = Invoke-CMWmiQuery -Query $query -Option Fast -ErrorAction stop
    }
    catch 
    {
        Write-CMTraceLog "Failed to get ConfigMgr updates. Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Error
        Write-CMTraceLog "$($_)" -Severity Error
        Exit 1
    }

    if($configMgrUpdates)
    {       
        #https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/setup-migrate-backup-recovery/understand-troubleshoot-updates-servicing#complete-list-of-state-codes
        $stateNames = @{
            0x0 = "UNKNOWN"
            0x2 = "ENABLED"
            262145 = "DOWNLOAD_IN_PROGRESS"
            262146 = "DOWNLOAD_SUCCESS"
            327679 = "DOWNLOAD_FAILED"
            327681 = "APPLICABILITY_CHECKING"
            327682 = "APPLICABILITY_SUCCESS"
            393213 = "APPLICABILITY_HIDE"
            393214 = "APPLICABILITY_NA"
            393215 = "APPLICABILITY_FAILED"
            65537 = "CONTENT_REPLICATING"
            65538 = "CONTENT_REPLICATION_SUCCESS"
            131071 = "CONTENT_REPLICATION_FAILED"
            131073 = "PREREQ_IN_PROGRESS"
            131074 = "PREREQ_SUCCESS"
            131075 = "PREREQ_WARNING"
            196607 = "PREREQ_ERROR"
            196609 = "INSTALL_IN_PROGRESS"
            196610 = "INSTALL_WAITING_SERVICE_WINDOW"
            196611 = "INSTALL_WAITING_PARENT"
            196612 = "INSTALL_SUCCESS"
            196613 = "INSTALL_PENDING_REBOOT"
            262143 = "INSTALL_FAILED"
            196614 = "INSTALL_CMU_VALIDATING"
            196615 = "INSTALL_CMU_STOPPED"
            196616 = "INSTALL_CMU_INSTALLFILES"
            196617 = "INSTALL_CMU_STARTED"
            196618 = "INSTALL_CMU_SUCCESS"
            196619 = "INSTALL_WAITING_CMU"
            262142 = "INSTALL_CMU_FAILED"
            196620 = "INSTALL_INSTALLFILES"
            196621 = "INSTALL_UPGRADESITECTRLIMAGE"
            196622 = "INSTALL_CONFIGURESERVICEBROKER"
            196623 = "INSTALL_INSTALLSYSTEM"
            196624 = "INSTALL_CONSOLE"
            196625 = "INSTALL_INSTALLBASESERVICES"
            196626 = "INSTALL_UPDATE_SITES"
            196627 = "INSTALL_SSB_ACTIVATION_ON"
            196628 = "INSTALL_UPGRADEDATABASE"
            196629 = "INSTALL_UPDATEADMINCONSOLE"
        }

        # Convert WMI datetime to normal date format

        $inConsoleUpdates = $configMgrUpdates | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                PackageGuid = $_.PackageGuid
                DateReleased = (get-date($_.DateReleased) -Format "yyyy-MM-dd HH:mm:ss")
                DateCreated = (get-date($_.DateCreated) -Format "yyyy-MM-dd HH:mm:ss")
                Description = $_.Description
                FullVersion = $_.FullVersion
                ClientVersion = $_.ClientVersion
                State = if ($stateNames.ContainsKey($_.State)) { $stateNames[$_.State] } else { "UNKNOWN STATE: $($_.State)" }
                }
        }

        $outObject.InConsoleUpdates = $inConsoleUpdates | Sort-Object -Property FullVersion -Descending

        # get the latest update fullversion for updates in state 196612
        $outObject.FullVersionUpdated = ($outObject.InConsoleUpdates | Where-Object { $_.State -eq "INSTALL_SUCCESS" } | Select-Object -First 1).FullVersion
        $outObject.FullVersionUpdatedName = ($outObject.InConsoleUpdates | Where-Object { $_.State -eq "INSTALL_SUCCESS" } | Select-Object -First 1).Name

        # Getting list of all HA site servers in case HA is used
        #$outObject.SiteServerHAList = Get-RegistryValueFromRemoteMachine -ComputerName $siteDefinition.SiteServerName -RegKeyPath 'HKLM:\SOFTWARE\Microsoft\SMS\Identification' -RegKeyValue 'Site Servers' -Method GetStringValue

        try
        {
            # Getting list of all HA site servers in case HA is used
            $haQuery = "SELECT * FROM SMS_HA_SiteServerTopLevelMonitoring WHERE SiteCode='{0}'" -f $SiteCode
            #$cimHAResult = Get-CimInstance -Namespace "Root\sms\site_$siteCode" -ComputerName $Provider -Query $haQuery 
            $cimHAResult = Invoke-CMWmiQuery -Query $haQuery -Option Fast -ErrorAction Stop

            $siteQuery = "SELECT * FROM SMS_Site WHERE SiteCode='{0}'" -f $SiteCode
            #$cimSiteResult = Get-CimInstance -Namespace "Root\sms\site_$siteCode" -ComputerName $Provider -Query $siteQuery
            $cimSiteResult = Invoke-CMWmiQuery -Query $siteQuery -Option Fast -ErrorAction Stop
        
            $passiveSiteServer = $null
            $passiveSiteServer = $cimHAResult | Select-Object -Property SiteServerName -Unique | Where-Object -Property SiteServerName -NE $cimSiteResult.ServerName | Select-Object -ExpandProperty SiteServerName
        
            $outObject.SiteServerHAList = [pscustomobject]@{
                                SiteServerActive = $cimSiteResult.ServerName
                                SiteServerPassive = $passiveSiteServer
                            }

            # Setting default share based on active site server
            $outObject.SiteDefaultShare = '\\{0}\SMS_{1}' -f $cimSiteResult.ServerName, $SiteCode
        }
        catch
        {
            Write-CMTraceLog -Message "Export of SiteServerHAList failed. Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Warning
            Write-CMTraceLog -Message "$_" -Severity Warning            
        }
    }
    else
    {
        return $false
    }

    return $outObject
}
#endregion


#region Get-RegistryValueFromRemoteMachine
function Get-RegistryValueFromRemoteMachine 
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [string]$RegKeyPath,

        [Parameter(Mandatory = $true)]
        [string]$RegKeyValue,

        [Parameter(Mandatory = $true)]
        [ValidateSet("GetStringValue", "GetDWORDValue", "GetQWORDValue")]
        [string]$Method
    )

    try {
        # Determine the registry hive
        if ($RegKeyPath -ilike "HKLM*") {
            $hDefKey = [UInt32]::Parse("2147483650") # HKEY_LOCAL_MACHINE
            $RegKeyPath = $RegKeyPath -replace "^HKLM\\", ""
        } elseif ($RegKeyPath -ilike "HKCU*") {
            $hDefKey = [UInt32]::Parse("2147483649") # HKEY_CURRENT_USER
            $RegKeyPath = $RegKeyPath -replace "^HKCU\\", ""
        } else {
            throw "Unsupported registry hive. Only HKLM and HKCU are supported."
        }

        $methodParams = @{
            hDefKey = $hDefKey
            sSubKeyName = $RegKeyPath
            sValueName = $RegKeyValue
        }

        # Invoke the specified method
        $result = Invoke-CimMethod -ComputerName $ComputerName -Namespace "root\default" -ClassName StdRegProv -MethodName $Method -Arguments $methodParams -ErrorAction SilentlyContinue

        # Return the appropriate value based on the method
        switch ($Method) {
            "GetStringValue" { return $result.sValue }
            "GetDWORDValue" { return $result.uValue }
            "GetQWORDValue" { return $result.uValue }
        }

        return $null
    }
    catch {
        Write-CMTraceLog -Message "Failed to read `"$($RegKeyPath)`" - `"$($RegKeyValue)`" on remote machine: `"$($ComputerName)`". Line: $($_.InvocationInfo.ScriptLineNumber)" -Type Warning
        Write-CMTraceLog -Message "$($_)" -Type Warning
        return $null
    }
}
#endregion


#region Export-SystemRoleInformation
<#
.SYNOPSIS
    Function to export MECM site server information into a JSON file
#>
Function Export-SystemRoleInformation
{
    param
    (
        [parameter(Mandatory=$true)]
        [string]$ProviderMachineName,
        [parameter(Mandatory=$true)]
        [string]$SiteCode,
        [parameter(Mandatory=$true)]
        [string]$OutputFilePath,
        [parameter(Mandatory=$false)]
        [ValidateSet("IPv4","IPv6","All")]
        [string]$IPType = "IPv4"
    )
  
    try
    {
        #$siteSystems = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -Query "SELECT * FROM SMS_SCI_SysResUse WHERE NALType = 'Windows NT Server'" -ErrorAction Stop
        $siteSystems = Invoke-CMWmiQuery -Query "SELECT * FROM SMS_SCI_SysResUse WHERE NALType = 'Windows NT Server'" -Option Fast -ErrorAction Stop
        # getting sitecode and parent to have hierarchy information
        $siteCodeHash = @{}
        #$siteCodeInfo = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -ClassName SMS_SCI_SiteDefinition -ErrorAction Stop
        $siteCodeInfo = Invoke-CMWmiQuery -Query "SELECT * FROM SMS_SCI_SiteDefinition" -Option Fast -ErrorAction Stop
    }
    Catch
    {
        Write-CMTraceLog -Message "Could not get site info. Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Error
        Write-CMTraceLog -Message "$_" -Severity Error
        Exit 1
    }

    $siteCodeInfo | ForEach-Object {   
        if ([string]::IsNullOrEmpty($_.ParentSiteCode))
        {
            $siteCodeHash.Add($_.SiteCode,$_.SiteCode)
        }
        else
        {
            $siteCodeHash.Add($_.SiteCode,$_.ParentSiteCode)
        }
    }

    Function Get-IPAddressFromName
    {
        param
        (
            [string]$SystemName,
            [ValidateSet("IPv4","IPv6","All")]
            [string]$Type = "IPv4"
        )
        
        $LocalSystemIPAddressList = @()
        $dnsObject = Resolve-DnsName -Name $systemName -ErrorAction SilentlyContinue
        if ($dnsObject)
        {
            switch ($Type) 
            {
                "All" {$LocalSystemIPAddressList += ($dnsObject).IPAddress}
                "IPv4" {$LocalSystemIPAddressList += ($dnsObject | Where-Object {$_.Type -eq 'A'}).IPAddress}
                "IPv6" {$LocalSystemIPAddressList += ($dnsObject | Where-Object {$_.Type -eq 'AAAA'}).IPAddress}
            }
            return $LocalSystemIPAddressList
        }
    }

    # Get a list of all site servers and their sitecodes 
    $siteCodeHashTable = @{}
    $sqlRoleHashTable = @{}
    $siteServerTypes = $siteSystems | Where-Object {$_.Type -in (1,2,4) -and $_.RoleName -eq 'SMS Site Server'}
    $siteServerTypes | ForEach-Object {
    
        switch ($_.Type)
        {
            1 
            {
                $siteHashValue = 'SecondarySite'
                $sqlHashValue = 'SECSQLServerRole'
            }
            
            2 
            {
                $siteHashValue = 'PrimarySite'
                $sqlHashValue = 'PRISQLServerRole'
            }
            
            4 
            {
                $siteHashValue = 'CentralAdministrationSite'
                $sqlHashValue = 'CASSQLServerRole'
            }
            #8 {'NotCoLocatedWithSiteServer'}
        }

        $siteCodeHashTable.Add($_.SiteCode, $siteHashValue)
        $sqlRoleHashTable.Add($_.SiteCode, $sqlHashValue)
    }
    
    
    $outObject = New-Object System.Collections.ArrayList
    foreach ($system in $siteSystems)
    {
        switch ($system.RoleName)
        {
            'SMS SQL Server' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = $sqlRoleHashTable[$system.SiteCode] # specific role like PRI, CAS, SEC or WSUS SQL 
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)

                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'SQLServerRole'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Site Server' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = $siteCodeHashTable[$system.SiteCode] # specific role like PRI, CAS or SEC
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)

                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'SiteServer'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)

            }
            'SMS Provider' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'SMSProvider'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Software Update Point' 
            {
                if ($siteCodeHashTable[$system.SiteCode] -eq 'CentralAdministrationSite')
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'CentralSoftwareUpdatePoint'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)                
                }

                if ($siteCodeHashTable[$system.SiteCode] -eq 'SecondarySite')
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'SecondarySoftwareUpdatePoint'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)                
                }
                else
                {             
                    $useParentWSUS = $system.Props | Where-Object {$_.PropertyName -eq 'UseParentWSUS'}
                    if ($useParentWSUS.Value -eq 1)
                    {
                        $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                        $tmpObj.Role = 'PrimarySoftwareUpdatePoint'
                        $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                        $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                        $tmpObj.SiteCode = $system.SiteCode
                        $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                        [void]$outObject.Add($tmpObj)
                    }
                }

                $supSQLServer = $system.Props | Where-Object {$_.PropertyName -eq 'DBServerName'}
                if (-NOT ([string]::IsNullOrEmpty($supSQLServer.Value2)))
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'SUPSQLServerRole'
                  
                    $systemNameFromNetworkOSPath = $system.NetworkOSPath -replace '\\\\'
                    [array]$dbServerName = $supSQLServer.Value2 -split '\\' # extract servername from server\instancename string
                    # making sure we have a FQDN
                    if ($systemNameFromNetworkOSPath -like "$($dbServerName[0])*")
                    {
                        $tmpObj.FullQualifiedDomainName = $systemNameFromNetworkOSPath
                    }
                    else 
                    {
                        if ($dbServerName[0] -notmatch '\.') # in case we don't have a FQDN, create one based on the FQDN of the initial system  
                        {
                            [array]$fqdnSplit =  $systemNameFromNetworkOSPath -split '\.' # split FQDN to easily replace hostname
                            $fqdnSplit[0] = $dbServerName[0] # replace hostname
                            $tmpObj.FullQualifiedDomainName = $fqdnSplit -join '.' # join back to FQDN
                        }   
                        else 
                        {
                            $tmpObj.FullQualifiedDomainName = $dbServerName[0] 
                        }              
                    }
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)                    
                }
                
                
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'SoftwareUpdatePoint'            
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)

            }
            'SMS Endpoint Protection Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'EndpointProtectionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Distribution Point' 
            {

                $isPXE = $system.Props | Where-Object {$_.PropertyName -eq 'IsPXE'}
                if ($isPXE.Value -eq 1)
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'DistributionPointPXE'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)                
                }

                $isPullDP = $system.Props | Where-Object {$_.PropertyName -eq 'IsPullDP'}
                if ($isPullDP.Value -eq 1)
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'PullDistributionPoint'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)
    
                    $pullSources = $system.PropLists | Where-Object {$_.PropertyListName -eq 'SourceDistributionPoints'}
                    if (-NOT $pullSources)
                    {
                        #Write-host "$(Get-date -Format u): No DP sources found for PullDP" -ForegroundColor Yellow
                    }
                    else
                    {
    
                        $pullSources.Values | ForEach-Object {
                                $Matches = $null
                                $retVal = $_ -match '(DISPLAY=\\\\)(.+)(\\")'
                                if ($retVal)
                                {
                                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                                    $tmpObj.Role = 'PullDistributionPointSource'
                                    $tmpObj.FullQualifiedDomainName = ($Matches[2])
                                    $tmpObj.PullDistributionPointToSource = $system.NetworkOSPath -replace '\\\\'
                                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($Matches[2]) -Type $IPType
                                    $tmpObj.SiteCode = $system.SiteCode
                                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                                    [void]$outObject.Add($tmpObj)
                                }
                                else
                                {
                                    #Write-host "$(Get-date -Format u): No DP sources found for PullDP" -ForegroundColor Yellow
                                }
                            }
                    }
                }
    
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'DistributionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Management Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'ManagementPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS SRS Reporting Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'ReportingServicePoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Dmp Connector' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'ServiceConnectionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'Data Warehouse Service Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'DataWarehouseServicePoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Cloud Proxy Connector' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'CMGConnectionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS State Migration Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'StateMigrationPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Fallback Status Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'FallbackStatusPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Component Server' 
            {
                # Skip role since no firewall rule diretly tied to it
            }
            'SMS Site System' 
            {
                # Skip role since no firewall rule diretly tied to it
            }
            'SMS Notification Server' 
            {
                # Skip role since no firewall rule diretly tied to it
            }
            <#
            'SMS Certificate Registration Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'CertificateRegistrationPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            #>
            Default 
            {
                #Write-host "$(Get-date -Format u): Role `"$($system.RoleName)`" not supported by the script at the moment. Create you own firewallrules and definitions in the config file if desired." -ForegroundColor Yellow
            }
    
            <# still missing
                SMS Device Management Point
                SMS Multicast Service Point
                SMS AMT Service Point
                AI Update Service Point
                SMS Enrollment Server
                SMS Enrollment Web Site            
                SMS DM Enrollment Service
            #>
    
        }
    }
    
    # group roles by system to have a by system list
    $systemsArrayList = New-Object System.Collections.ArrayList
    foreach ($itemGroup in ($outObject | Group-Object -Property FullQualifiedDomainName))
    {
        $roleList = @()
        $pullDPList = @()
        foreach ($item in $itemGroup.Group)
        {
            $roleList += $item.Role
            if (-NOT ([string]::IsNullOrEmpty($item.PullDistributionPointToSource)))
            {
                $pullDPList += $item.PullDistributionPointToSource
            }
        }
        [array]$roleList = $roleList | Select-Object -Unique
        [array]$pullDPList = $pullDPList | Select-Object -Unique
    
        $itemList = [ordered]@{
            FullQualifiedDomainName = $itemGroup.Name
            IPAddress = $itemGroup.Group[0].IPAddress -join ','
            SiteCode = $itemGroup.Group[0].SiteCode
            ParentSiteCode = $itemGroup.Group[0].ParentSiteCode
            Description = ""
            RoleList = $roleList
            PullDistributionPointToSourceList = $pullDPList
        }
      
        [void]$systemsArrayList.Add($itemList)
    }

    $outFileFullName = '{0}\Backup-SiteSystemRoleList.json' -f $OutputFilePath
        
    [PSCustomObject]@{
        SystemAndRoleList = $systemsArrayList
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath $outFileFullName -Force
}
#endregion

#region New-WimFileFromFolder
function New-WimFileFromFolder
{
    param 
    (
        [string]$SourceFolder,
        [string]$OutputFileFullName,
        [String]$ImageName,
        [String]$DismScratchDir,
        [String]$LogFileFullName
    )

    # Run the DISM command to capture the folder into a WIM file with
    $argumentList = '/Capture-Image /ImageFile:"{0}" /CaptureDir:"{1}" /Name:"{2}" /LogPath:"{3}" /ScratchDir:"{4}"' 
    $argumentList = $argumentList -f $OutputFileFullName, $SourceFolder, $ImageName, $LogFileFullName, $DismScratchDir
    Write-CMTraceLog -Message "Will run DISM with the following arguments:"
    Write-CMTraceLog -Message "$($argumentList)"

    $processRetVal = Start-Process dism.exe -ArgumentList $argumentList -Wait -PassThru -NoNewWindow
    
    if ($processRetVal.ExitCode -ne 0) 
    {
        Write-CMTraceLog -Message "Error during dism command. Check the logfile at: $($LogFileFullName)" -Severity Error
        $script:ExitWithError = $true
    }    
}
#endregion


# Check if none of the switch parameters are set
if (-not ($ExportAllItemTypes -or $ExportCollections -or $ExportConfigurationItems -or $ExportConfigurationBaselines -or $ExportTaskSequences -or $ExportAntimalwarePolicies -or $ExportScripts -or $ExportClientSettings -or $ExportConfigurationPolicies -or $ExportCDLatest)) 
{
    Write-CMTraceLog -Message "No export type selected. Please use one of the following parameters: -ExportAllItemTypes, -ExportCollections, -ExportConfigurationItems, -ExportConfigurationBaselines, -ExportTaskSequences, -ExportAntimalwarePolicies, -ExportScripts, -ExportClientSettings, -ExportConfigurationPolicies, -ExportCDLatest" -Severity Warning
    Exit 1 
}

$stoptWatch = New-Object System.Diagnostics.Stopwatch
$stoptWatch.Start()

Invoke-LogfileRollover -Logfile $script:LogFilePath -MaxFileSizeKB 2048

Write-CMTraceLog -Message '   '
Write-CMTraceLog -Message 'Start of script'

# Lets cleanup first
Remove-OldExportFolders -RootPath $script:ExportRootFolder -MaxExportFolderAgeInDays $MaxExportFolderAgeInDays -MinExportFoldersToKeep $MinExportFoldersToKeep

#region load ConfigMgr modules
Write-CMTraceLog -Message 'Will load ConfigurationManager.psd1'
# Lets make sure we have the ConfigMgr modules
if (-NOT (Test-Path "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"))
{
    Write-CMTraceLog -Message 'ConfigurationManager.psd1 not found. Stopping script' -Severity Error
    Exit 1   
}

# Validate path and create if not there yet
if (-not (Test-Path $script:FullExportFolderName)) 
{
    New-Item -ItemType Directory -Path $FullExportFolderName -Force | Out-Null
}
Write-CMTraceLog -Message "Export will be made to folder: $($script:FullExportFolderName)"

# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Do not change anything below this line

# Import the ConfigurationManager.psd1 module 
if(-NOT (Get-Module ConfigurationManager)) 
{
    
    try
    {
        Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams
    }
    Catch
    {
        Write-CMTraceLog -Message "Not able to load ConfigurationManager.psd1 $($_)" -Severity Error
        Exit 1
    }
}

# Connect to the site's drive if it is not already present
if(-NOT (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue))
{
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams
#endregion


#region Main script

# helptext for wim file actions for CD.Latest folder
$mountInfo = @"
    -----------------
    Step 1: 
    Create a folder to mount the wim file to
    Like: C:\MountFolder
    -----------------
    Step 2: 
    Mount the wim file like this:
    dism.exe /Mount-Wim /WimFile:"{0}" /Index:1 /MountDir:"<Path to mount folder>"
    -----------------
    Step 3: 
    Start the recovery process
    -----------------
    Step 4:
    Unmount the file like this:
    dism.exe /Unmount-Wim /MountDir:"<Path to mount folder>" /Discard
    -----------------
"@



try
{
    # Export configuration items
    if ($ExportConfigurationItems -or $ExportAllItemTypes)
    {
        Write-CMTraceLog -Message "---------------------------------"
        Write-CMTraceLog -Message " -> Will export configuration items..."
        Write-CMTraceLog -Message "---------------------------------"
        Get-CMConfigurationItem -Fast | Export-CMItemCustomFunction
    }

    # Export configuration baselines
    if ($ExportBaselines -or $ExportAllItemTypes)
    {
        Write-CMTraceLog -Message "---------------------------------"
        Write-CMTraceLog -Message " -> Will export baselines..."
        Write-CMTraceLog -Message "---------------------------------"
        Get-CMBaseline -Fast | Export-CMItemCustomFunction
    }
    
    # Export task sequences
    if ($ExportTaskSequences -or $ExportAllItemTypes)
    {
        Write-CMTraceLog -Message "---------------------------------"
        Write-CMTraceLog -Message " -> Will export task sequences..."
        Write-CMTraceLog -Message "---------------------------------"
        Get-CMTaskSequence -Fast | Export-CMItemCustomFunction
    }

    # Export antimalware policies
    if ($ExportAntimalwarePolicies -or $ExportAllItemTypes)
    {
        Write-CMTraceLog -Message "---------------------------------"
        Write-CMTraceLog -Message " -> Will export AntimalwarePolicies..."
        Write-CMTraceLog -Message "---------------------------------"
        Get-CMAntimalwarePolicy | Export-CMItemCustomFunction
    }

    # Export scripts
    if ($ExportScripts -or $ExportAllItemTypes)
    {
        Write-CMTraceLog -Message "---------------------------------"
        Write-CMTraceLog -Message " -> Will export scripts..."
        Write-CMTraceLog -Message "---------------------------------"
        Get-CMScript -WarningAction Ignore | Export-CMItemCustomFunction
    }

    # Export client settings
    if ($ExportClientSettings -or $ExportAllItemTypes)
    {
        Write-CMTraceLog -Message "---------------------------------"
        Write-CMTraceLog -Message " -> Will export client settings..."
        Write-CMTraceLog -Message "---------------------------------"
        Get-CMClientSetting | Export-CMItemCustomFunction
    }

    # Export configuration policies
    if ($ExportConfigurationPolicies -or $ExportAllItemTypes)
    {
        Write-CMTraceLog -Message "---------------------------------"
        Write-CMTraceLog -Message " -> Will export configurations..."
        Write-CMTraceLog -Message "---------------------------------"
        Get-CMConfigurationPolicy -Fast | Export-CMItemCustomFunction
    }
    
    # Export collections
    if ($ExportCollections -or $ExportAllItemTypes)
    {
        Write-CMTraceLog -Message "---------------------------------"
        Write-CMTraceLog -Message " -> Will export collections..."
        Write-CMTraceLog -Message "---------------------------------"
        # Lets export collections into one file
        $itemExportRootFolder = '{0}\Collections' -f $script:FullExportFolderName
        $itemFullName  = '{0}\CollectionList.xml' -f $itemExportRootFolder

        # We might need to create the folder first
        if (-not (Test-Path $itemExportRootFolder)) 
        {
            New-Item -ItemType Directory -Path $itemExportRootFolder -Force | Out-Null
        }

        # Collections can be used in a script with Import-Clixml to get the same object as generated by this script
        [array]$CollectionList = Get-CMCollection | New-CMCollectionListCustom 
        $CollectionList | Export-Clixml -Depth 20 -Path $itemFullName -Force
        Write-CMTraceLog -Message "Collections exported to: $($itemFullName)"
        $CollectionList | ConvertTo-Json -Depth 20 | Out-File -FilePath ($itemFullName -replace 'xml', 'json') -Force
        Write-CMTraceLog -Message "Collections exported to: $(($itemFullName -replace 'xml', 'json'))"  
    }

    # Export CD.Latest folder and metadata
    if ($ExportCDLatest -or $ExportAllItemTypes)
    {
        Write-CMTraceLog -Message "---------------------------------"
        Write-CMTraceLog -Message " -> Will export site info and CD.latest folder..."
        Write-CMTraceLog -Message "---------------------------------"

        $proccedWithAction = $true
        Write-CMTraceLog -Message "Start export of general site data"
        $SiteData = Get-ConfigMgrSiteInfo -ProviderMachineName $ProviderMachineName -SiteCode $SiteCode

        # Export of general site data
        $SiteData | ConvertTo-Json -Depth 10 | Out-File -FilePath "$($script:FullExportFolderName)\Backup-SiteData.json" -Force
        
        # Export of role and system information
        Write-CMTraceLog -Message "Start export of site system role information"
        Export-SystemRoleInformation -ProviderMachineName $ProviderMachineName -SiteCode $SiteCode -OutputFilePath $script:FullExportFolderName

        # We will save the cd.latest folder with the latest versionnumber
        $cdLatestFileName = '{0}_cd.latest.wim' -f $siteData.FullVersionUpdated
        $cdLatestFileFullName = '{0}\{1}' -f $script:ExportRootFolder, $cdLatestFileName
        $cdLatestRobocopyLogFileFullName = $cdLatestFileFullName -replace '.wim$', '-robocopy.log'
        $cdLatestDismLogFileFullName = $cdLatestFileFullName -replace '.wim$', '-dism.log'
        $cdLatestReadmeFileFullName = $cdLatestFileFullName -replace '.wim$', '-readme.log'

        # Adding filepath to wim info file
        $mountInfo = $mountInfo -f $cdLatestFileFullName
        if (-Not (Test-Path $cdLatestReadmeFileFullName))
        {
            $mountInfo | Out-File -FilePath $cdLatestReadmeFileFullName -Force
        }

        #Set-Location "C:\" # to avoid any errors sice we would normally have the ConfigMgr drive at this point
        Set-Location "C:\"
        
        if (Test-Path $cdLatestFileFullName)
        {
            $proccedWithAction = $false
            Write-CMTraceLog -Message "CD.Latest folder for current version already backed up to:"
            Write-CMTraceLog -Message "$($cdLatestFileFullName)"
            Write-CMTraceLog -Message "Will not backup CD.Latest folder again"
        }
        else 
        {
            Write-CMTraceLog -Message "Will backup CD.Latest folder to: $($cdLatestFileFullName)"
            # Lets make sure we can reach the default share to copy the cd.latest folder
            if (Test-Path $SiteData.SiteDefaultShare)
            {
                Write-CMTraceLog -Message "Default share can be reached: $($SiteData.SiteDefaultShare)"   
            }
            else 
            {
                Write-CMTraceLog -Message "Default share cannot be reached: $($SiteData.SiteDefaultShare)" -Severity Error
                $script:ExitWithError = $true
                $proccedWithAction = $false
            }
        }


        if ($proccedWithAction)
        {
            $remoteFolderName = '{0}\cd.latest' -f $SiteData.SiteDefaultShare

            # We need a temp folder to copy the cd.latest folder. Ideally in the root of the drive of $script:ExportRootFolder to avoid long path names
            $configMgrBkpTMPFolder = '{0}ConfigMgrBkpTMP' -f ([System.IO.Path]::GetPathRoot($Script:ExportRootFolder))
            
            # Delete the temp folder if it exists already from a previous run
            if (Test-Path $configMgrBkpTMPFolder )
            {
                Write-CMTraceLog -Message "Deleting existing temp folder: $($configMgrBkpTMPFolder)"
                $null = Remove-Item -Path $configMgrBkpTMPFolder -Recurse -Force
            }

            # A folder for the cd.latest files locally to be able to capture them into a wim file
            # The wim file should speed up copy time and does not need to be extracted
            $configMgrBkpTMPFolderCdLatest = '{0}\cd.Latest' -f $configMgrBkpTMPFolder
            # A second folder for dism as scratch directory
            $configMgrBkpTMPFolderDismTmp = '{0}\dismTmp' -f $configMgrBkpTMPFolder

            # Create the temp folder
            Write-CMTraceLog -Message "Creating temp folder and sub-folders: $($configMgrBkpTMPFolder)"
            $null = New-Item -ItemType Directory -Path $configMgrBkpTMPFolder -Force
            $null = New-Item -ItemType Directory -Path $configMgrBkpTMPFolderCdLatest -Force
            $null = New-Item -ItemType Directory -Path $configMgrBkpTMPFolderDismTmp -Force

            # we will now robocopy the cd.latest folder to the temp folder
            Write-CMTraceLog -Message "Copying cd.latest folder to temp folder: $($configMgrBkpTMPFolder)"
            Start-RoboCopy -Source $remoteFolderName -Destination $configMgrBkpTMPFolderCdLatest -RobocopyLogPath $cdLatestRobocopyLogFileFullName
            # In case the robocopy failed, the script will exit with an error

            $paramSplatting = @{
                SourceFolder = $configMgrBkpTMPFolderCdLatest
                OutputFileFullName = $cdLatestFileFullName
                ImageName = ($cdLatestFileName -replace '\.wim')
                DismScratchDir = $configMgrBkpTMPFolderDismTmp
                LogFileFullName = $cdLatestDismLogFileFullName
            }

            Write-CMTraceLog -Message "Cretie wim file from CD.latest folder"
            New-WimFileFromFolder @paramSplatting

            if (Test-Path $configMgrBkpTMPFolder )
            {
                Write-CMTraceLog -Message "Remove temp folder: $($configMgrBkpTMPFolder)"
                $null = Remove-Item -Path $configMgrBkpTMPFolder -Recurse -Force
            }

        }
    }
}
catch
{
    Write-CMTraceLog -Message "Error during export. Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Error
    Write-CMTraceLog -Message "$($_)" -Severity Error
    $script:ExitWithError = $true
}


$stoptWatch.Stop()
$scriptDurationString = "Script runtime: {0}h:{1}m:{2}s" -f $stoptWatch.Elapsed.Hours, $stoptWatch.Elapsed.Minutes, $stoptWatch.Elapsed.Seconds
Write-CMTraceLog -Message $scriptDurationString

if ($script:ExitWithError)
{
    Write-CMTraceLog -Message 'Script ended with errors' -Severity Warning
}
else
{
    Write-CMTraceLog -Message 'Script ended successfull'
}
#endregion