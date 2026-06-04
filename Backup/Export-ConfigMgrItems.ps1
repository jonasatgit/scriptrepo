<#
.Synopsis
    Script to export certain ConfigMgr items
 
.DESCRIPTION
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
    
    Script to export certain ConfigMgr items into a folder structure.
    The script will create a folder structure based on the current date and time and item-type.
    The script will export the following items:
    - Collections
    - Configuration Items
    - Configuration Baselines
    - Task Sequences
    - Antimalware Policies
    - Scripts
    - Client Settings
    - Configuration Policies
    - Automatic Deployment Rules
    - CD.Latest folder content to a wim file

    Use parameters to select which items to export or export all items with parameter -ExportAllItemTypes.
    
    The script will use the default export functions from the ConfigMgr PowerShell module if available.
    In case an item does not have a default export function, the script will use a custom export function and export data via Export-CliXml.
    All XML files can be imported again with Import-CliXml. That preserves the data structure and types and schould make restore of items easy.

    NOTE: There is no import function available in this script at this time.

    The following additional files might be created per item:
    <itemname>.metadata.xml     -> The item metadata, such as the item name, item type, item ID, and other information.
    <itemname>.deployments.xml  -> The deployments of the item, if available.
    <itemname>.hinvclasses.xml  -> The hardware inventory classes of the item, if available.
    <itemname>.references.xml   -> The references of the item, if available. Such as packages for task sequences for example.

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
    The minimum amount of export folders to keep. Default is 10
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

.PARAMETER ExportAutomaticDeploymentRules
    Export automatic deployment rules (ADRs)

.PARAMETER ExportCDLatest
    Export the latest version of the content of the CD.Latest folder to be able to restore ConfigMgr.
    The CD.Latest folder will be captured into a wim file and stored in the export folder.
    Next to the wim file, a text file will be created with instructions on how to mount and use the wim file.
    The wim file will be named "<ConfigMgr version>_cd.latest.wim".
    The CD.Latest folder will be captured when the versionnumber of ConfigMgr changes and not every time the script is run.

.PARAMETER BackupConfigMgrUserDatabases
    Backup the ConfigMgr user databases. This will create a backup of the ConfigMgr user databases in the export folder.
    The backup will be created using the SQL Server Management Objects (SMO) and will create a backup file for each database.

.PARAMETER BackupWSUSUSusdb
    Backup the WSUS database. This will create a backup of the WSUS database in the export folder.
    The backup will be created using the SQL Server Management Objects (SMO) and will create a backup file for the WSUS database.
    The backup will be created only if the WSUS database is NOT hosted on the same SQL Server as the ConfigMgr databases and already exported.

.PARAMETER ImportAutomaticDeploymentRules
    Import Automatic Deployment Rules from previously exported *.xml files in -ImportFolder.
    Reads each Export-CliXml file, resolves the embedded product / classification GUIDs against
    the current site (SMS_UpdateCategoryInstance via WMI) and recreates the ADR via the
    documented New-CMSoftwareUpdateAutoDeploymentRule cmdlet.

.PARAMETER ImportFolder
    Folder containing the exported ADR *.xml files. Searched recursively. Metadata side files
    produced by the exporter (*.metadata.xml, *.deployments.xml, *.hinvclasses.xml, *.references.xml)
    are automatically ignored.

.PARAMETER ForcedImport
    Update an ADR that already exists with the same Name instead of skipping it. Without this
    switch, existing ADRs are left untouched and a warning is logged.

.EXAMPLE
    Export-ConfigMgrItems.ps1
#>

param
(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$SiteCode,

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [String]$ProviderMachineName = $env:COMPUTERNAME,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$ExportRootFolder,

    [int]$MaxExportFolderAgeInDays = 10,
    [int]$MinExportFoldersToKeep = 10,
    [Switch]$ExportAllItemTypes,
    [Switch]$ExportCollections,
    [Switch]$ExportConfigurationItems,
    [Switch]$ExportConfigurationBaselines,
    [Switch]$ExportTaskSequences,
    [Switch]$ExportAntimalwarePolicies,
    [Switch]$ExportScripts,
    [Switch]$ExportClientSettings,
    [Switch]$ExportConfigurationPolicies,
    [Switch]$ExportAutomaticDeploymentRules,
    [switch]$ExportCDLatest,
    [switch]$BackupConfigMgrUserDatabases,
    [switch]$BackupWSUSUSusdb,

    # ---- ADR import parameters --------------------------------------------------
    # Import Automatic Deployment Rules from previously exported *.xml files
    # (created by this script via Export-CliXml of SMS_AutoDeployment objects).
    [Switch]$ImportAutomaticDeploymentRules,

    # Folder containing the exported ADR *.xml files. The folder is searched
    # recursively. Only files containing a serialized SMS_AutoDeployment object
    # are processed.
    [String]$ImportFolder,

    # If specified, an already existing ADR with the same Name will be updated
    # in-place via Set-CMAutoDeploymentRule / Set-CMAutoDeploymentRuleDeployment.
    # If not specified, existing ADRs are skipped and a warning is written.
    [Switch]$ForcedImport
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
$script:FullExportFolderName = '{0}\{1}' -f $ExportRootFolder, (Get-date -Format 'yyyyMMdd-HHmm')
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
                StartTime = $schedule.StartTime.ToString("yyyyMMddHHmmss.000000+***")
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
                    Starttime = $Window.Starttime #.ToString("yyyyMMddHHmmss.000000+***")
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
            'SMS_AutoDeployment'
            {
                # We need a folder to store Automatic Deployment Rules in
                $itemExportRootFolder = '{0}\AutomaticDeploymentRules' -f $script:FullExportFolderName
                $itemModelName = $item.AutoDeploymentID
                $itemFileExtension = '.xml'
                $itemFileName = (Get-SanitizedFileName -FileName ($item.Name))
                $skipConfigMgrFolderSearch = $true
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

            # If the file already exists, we will append a timestamp to the filename
            # This can happen if you have multiple items with the same name
            if (Test-Path $itemFullName)
            {
                $itemExtension = [system.IO.Path]::GetExtension($itemFullName)
                $itemFileName = [system.IO.Path]::GetFileNameWithoutExtension($itemFullName)
                $itemDirectory = [system.IO.Path]::GetDirectoryName($itemFullName)
                $itemFullName = '{0}\{1}{2}{3}' -f $itemDirectory, $itemFileName, (get-date -f 'HHmmss'), $itemExtension
            }

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
                    'SMS_AutoDeployment'
                    {
                        Write-CMTraceLog -Message "Will export Automatic Deployment Rule: $($itemFullName)"
                        $item | Export-Clixml -Depth 100 -Path $itemFullName
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


#region function Get-CMUpdateCategoryNameFromGuid
<#
.SYNOPSIS
    Resolves a ConfigMgr update category GUID (Product or UpdateClassification)
    to its LocalizedCategoryInstanceName via the SMS provider.

.DESCRIPTION
    The exported UpdateRuleXML stores _Product and _UpdateClassification match
    rules as e.g. "'Product:5f4177e2-ad09-4066-9050-b7466ad5b078'" or
    "'UpdateClassification:e6cf1350-c01b-414d-a61f-263d14d133b4'".
    These IDs cannot be passed to New-CMAutoDeploymentRule directly; the cmdlet
    expects display names like 'Office 2019' or 'Security Updates'.
    This helper queries SMS_UpdateCategoryInstance (which is the WMI class
    behind Get-CMSoftwareUpdateCategory) and returns the human readable name.

.PARAMETER CategoryIdString
    The raw MatchRule string (with surrounding single quotes optional), e.g.
    "'Product:5f4177e2-ad09-4066-9050-b7466ad5b078'".

.PARAMETER CategoryCache
    Optional hashtable used to cache lookups across many calls.
#>
function Get-CMUpdateCategoryNameFromGuid
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$CategoryIdString,

        [Parameter(Mandatory = $false)]
        [hashtable]$CategoryCache
    )

    # Strip surrounding quotes the exporter may have left in place
    $cleanId = $CategoryIdString.Trim().Trim("'").Trim('"')

    if ($CategoryCache -and $CategoryCache.ContainsKey($cleanId))
    {
        return $CategoryCache[$cleanId]
    }

    # The CategoryInstance_UniqueID stored in WMI matches the value 1:1
    # (e.g. "Product:5f4177e2-..." or "UpdateClassification:e6cf1350-...").
    # Escape single quotes for the WQL string just in case.
    $wqlId = $cleanId -replace "'", "''"
    $wmiQuery = "SELECT LocalizedCategoryInstanceName, CategoryTypeName FROM SMS_UpdateCategoryInstance WHERE CategoryInstance_UniqueID = '$wqlId'"

    try
    {
        $result = Invoke-CMWmiQuery -Query $wmiQuery -Option Fast -ErrorAction Stop | Select-Object -First 1
    }
    catch
    {
        Write-CMTraceLog -Message "WMI lookup failed for category '$cleanId': $_" -Severity Warning
        $result = $null
    }

    if (-not $result)
    {
        Write-CMTraceLog -Message "Could not resolve update category '$cleanId' to a name. The ID will be skipped." -Severity Warning
        if ($CategoryCache) { $CategoryCache[$cleanId] = $null }
        return $null
    }

    $name = $result.LocalizedCategoryInstanceName
    if ($CategoryCache) { $CategoryCache[$cleanId] = $name }
    return $name
}
#endregion


#region function Convert-CMLocaleToLanguageName
<#
.SYNOPSIS
    Converts a "Locale:<lcid>" string from the exported ContentTemplate XML
    into a language display name accepted by New-CMAutoDeploymentRule.

.DESCRIPTION
    The exported ContentTemplate uses entries like "Locale:9" (English),
    "Locale:7" (German) or "Locale:0" (language neutral). The
    -Language parameter of New-CMAutoDeploymentRule expects English language
    display names like 'English' or 'German'. This helper performs the
    conversion via [System.Globalization.CultureInfo].

    Locale:0 is mapped to 'Language Independent' which is the string used by
    the SCCM console for language-neutral updates.
#>
function Convert-CMLocaleToLanguageName
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$LocaleString
    )

    if ($LocaleString -inotmatch '^Locale:(\d+)$')
    {
        Write-CMTraceLog -Message "Unexpected locale string format '$LocaleString'. Skipping." -Severity Warning
        return $null
    }

    [int]$lcid = $Matches[1]

    if ($lcid -eq 0)
    {
        return 'Language Independent'
    }

    # The ConfigMgr console exposes most languages as a single neutral entry
    # (e.g. 'English' for any English region, 'German' for any German region),
    # but a few languages with multiple scripts/regions are listed with their
    # parenthesised qualifier (e.g. 'Chinese (Simplified, PRC)',
    # 'Chinese (Traditional, Taiwan)', 'Portuguese (Brazil)',
    # 'Portuguese (Portugal)', 'Serbian (Latin)', 'Serbian (Cyrillic)').
    # The safest way to handle both cases is to walk up to the neutral parent
    # culture and take its EnglishName, falling back to a static map for the
    # ambiguous specific cultures.

    # Static overrides for LCIDs where the SCCM console uses the specific
    # (parenthesised) name rather than the neutral parent.
    $specificLanguageMap = @{
        2052 = 'Chinese (Simplified, PRC)'        # zh-CN
        1028 = 'Chinese (Traditional, Taiwan)'    # zh-TW
        3076 = 'Chinese (Traditional, Hong Kong)' # zh-HK
        5124 = 'Chinese (Traditional, Macao)'     # zh-MO
        4100 = 'Chinese (Simplified, Singapore)'  # zh-SG
        1046 = 'Portuguese (Brazil)'              # pt-BR
        2070 = 'Portuguese (Portugal)'            # pt-PT
        2074 = 'Serbian (Latin)'                  # sr-Latn-*
        3098 = 'Serbian (Cyrillic)'               # sr-Cyrl-*
    }
    if ($specificLanguageMap.ContainsKey($lcid))
    {
        return $specificLanguageMap[$lcid]
    }

    try
    {
        $ci = [System.Globalization.CultureInfo]::GetCultureInfo($lcid)
        # Walk up to a neutral culture (drops the "(United States)" region suffix)
        $neutral = if ($ci.IsNeutralCulture) { $ci } else { $ci.Parent }
        if ($null -eq $neutral -or $neutral.LCID -eq 127) # invariant culture
        {
            $neutral = $ci
        }
        return $neutral.EnglishName.Trim()
    }
    catch
    {
        Write-CMTraceLog -Message "Could not convert LCID '$lcid' to a language name: $_" -Severity Warning
        return $null
    }
}
#endregion


#region function ConvertFrom-CMDurationUnit
<#
.SYNOPSIS
    Maps the DeploymentTemplate xml "Days|Weeks|Months|Hours" string to the
    Microsoft.ConfigurationManagement TimeUnitType enum value accepted by the
    -DeadlineTimeUnit / -AvailableTimeUnit / -AlertTimeUnit parameters.
#>
function ConvertFrom-CMDurationUnit
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Unit
    )

    switch ($Unit)
    {
        'Hours'  { 'Hours' ; break }
        'Days'   { 'Days'  ; break }
        'Weeks'  { 'Weeks' ; break }
        'Months' { 'Months'; break }
        default
        {
            Write-CMTraceLog -Message "Unknown duration unit '$Unit'. Defaulting to 'Days'." -Severity Warning
            'Days'
        }
    }
}
#endregion


#region function ConvertFrom-CMDateRevisedString
<#
.SYNOPSIS
    Best-effort conversion of the "DateRevised" MatchRule (e.g. "0:2:0:0") into
    the DateReleasedOrRevisedType enum value used by
    New-CMSoftwareUpdateAutoDeploymentRule.

.DESCRIPTION
    The internal representation in UpdateRuleXML is
        "<type>:<value>:<unit>:<flag>"
    where:
        type  0 = DateReleased, 1 = DateRevised
        unit  0 = Hours, 1 = Days, 2 = Weeks, 3 = Months, 4 = Years

    The supported cmdlet enum values (DateReleasedOrRevisedType) are:
        Any, LastHour, Last1Hour, Last2Hours, Last3Hours, Last4Hours,
        Last8Hours, Last12Hours, Last16Hours, Last20Hours,
        LastDay, Last1Day, Last2Days, Last3Days, Last4Days, Last5Days,
        Last6Days, Last7Days, Last14Days, Last21Days, Last28Days,
        LastMonth, Last1Month, Last2Months, Last3Months, Last4Months,
        Last5Months, Last6Months, Last7Months, Last8Months, Last9Months,
        Last10Months, Last11Months, Last12Months, LastYear, Last1Year

    Anything that cannot be mapped is returned as 'Any' with a warning so that
    ADR creation can continue.
#>
function ConvertFrom-CMDateRevisedString
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$RawValue
    )

    if ([string]::IsNullOrWhiteSpace($RawValue) -or $RawValue -eq '0:0:0:0')
    {
        return 'Any'
    }

    $parts = $RawValue -split ':'
    if ($parts.Count -lt 3)
    {
        Write-CMTraceLog -Message "Unparseable DateRevised value '$RawValue'. Falling back to 'Any'." -Severity Warning
        return 'Any'
    }

    [int]$value = 0
    [int]$unit  = 0
    [void][int]::TryParse($parts[1], [ref]$value)
    [void][int]::TryParse($parts[2], [ref]$unit)

    $key = '{0}|{1}' -f $value, $unit
    switch ($key)
    {
        # Hours (unit 0)
        '1|0'  { return 'Last1Hour' }
        '2|0'  { return 'Last2Hours' }
        '3|0'  { return 'Last3Hours' }
        '4|0'  { return 'Last4Hours' }
        '8|0'  { return 'Last8Hours' }
        '12|0' { return 'Last12Hours' }
        '16|0' { return 'Last16Hours' }
        '20|0' { return 'Last20Hours' }
        '24|0' { return 'Last1Day' }   # 24 hours has no direct enum value, map to Last1Day
        # Days (unit 1)
        '1|1'  { return 'Last1Day' }
        '2|1'  { return 'Last2Days' }
        '3|1'  { return 'Last3Days' }
        '4|1'  { return 'Last4Days' }
        '5|1'  { return 'Last5Days' }
        '6|1'  { return 'Last6Days' }
        '7|1'  { return 'Last7Days' }
        '14|1' { return 'Last14Days' }
        '21|1' { return 'Last21Days' }
        '28|1' { return 'Last28Days' }
        '30|1' { return 'Last1Month' } # 30 days has no direct enum value, map to Last1Month
        # Weeks (unit 2)
        '1|2'  { return 'Last7Days' }
        '2|2'  { return 'Last14Days' }
        '3|2'  { return 'Last21Days' }
        '4|2'  { return 'Last28Days' }
        # Months (unit 3)
        '1|3'  { return 'Last1Month' }
        '2|3'  { return 'Last2Months' }
        '3|3'  { return 'Last3Months' }
        '4|3'  { return 'Last4Months' }
        '5|3'  { return 'Last5Months' }
        '6|3'  { return 'Last6Months' }
        '7|3'  { return 'Last7Months' }
        '8|3'  { return 'Last8Months' }
        '9|3'  { return 'Last9Months' }
        '10|3' { return 'Last10Months' }
        '11|3' { return 'Last11Months' }
        '12|3' { return 'Last12Months' }
        # Years (unit 4)
        '1|4'  { return 'Last1Year' }
        default
        {
            Write-CMTraceLog -Message "DateRevised '$RawValue' (value=$value unit=$unit) has no direct enum mapping. Falling back to 'Any'." -Severity Warning
            return 'Any'
        }
    }
}
#endregion


#region function Import-CMAutoDeploymentRuleFromXml
<#
.SYNOPSIS
    Creates (or updates) a ConfigMgr Automatic Deployment Rule from an XML
    file previously produced by Export-CMItemCustomFunction.

.DESCRIPTION
    The exported XML is an Export-CliXml dump of an SMS_AutoDeployment object.
    Most of the rule's settings live in four embedded XML strings:
        - AutoDeploymentProperties  (rule level: enable, scope, alerts, ...)
        - ContentTemplate           (deployment package, locales, sources)
        - DeploymentTemplate        (deployment object: schedule, UX, alerts)
        - UpdateRuleXML             (filter: products, classifications, ...)
    Plus a couple of top level scalar properties (Name, CollectionID,
    Schedule, ...).

    This function parses those payloads, resolves Product and
    UpdateClassification GUIDs to display names via WMI, resolves the
    deployment package by PackageID and creates the ADR using the official
    New-CMAutoDeploymentRule cmdlet. Existing ADRs (matched by Name) are
    skipped unless -Force is supplied, in which case Set-CMAutoDeploymentRule
    and Set-CMAutoDeploymentRuleDeployment are used to update the rule
    in-place.

.PARAMETER Path
    Full path to the exported ADR XML file.

.PARAMETER Force
    Update an existing ADR with the same Name instead of skipping it.
#>
function Import-CMAutoDeploymentRuleFromXml
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [hashtable]$CategoryCache = @{}
    )

    Begin {}
    Process
    {
        try
        {
            if (-not (Test-Path -LiteralPath $Path))
            {
                Write-CMTraceLog -Message "ADR XML not found: $Path" -Severity Error
                $script:ExitWithError = $true
                return
            }

            Write-CMTraceLog -Message "Reading ADR XML: $Path"
            $adr = Import-Clixml -LiteralPath $Path

            # Sanity check: this is an SMS_AutoDeployment dump
            if (-not $adr.PSObject.Properties['AutoDeploymentProperties'] -or `
                -not $adr.PSObject.Properties['ContentTemplate'] -or `
                -not $adr.PSObject.Properties['DeploymentTemplate'] -or `
                -not $adr.PSObject.Properties['UpdateRuleXML'])
            {
                Write-CMTraceLog -Message "File '$Path' does not look like an exported ADR (missing expected XML properties). Skipping." -Severity Warning
                return
            }

            # Reject empty / whitespace embedded payloads up front so the [xml] cast
            # below doesn't throw a generic / non-actionable parse error.
            foreach ($payloadProp in @('AutoDeploymentProperties','ContentTemplate','DeploymentTemplate','UpdateRuleXML'))
            {
                if ([string]::IsNullOrWhiteSpace([string]$adr.$payloadProp))
                {
                    Write-CMTraceLog -Message "File '$Path' has an empty '$payloadProp' payload. Cannot import this ADR." -Severity Error
                    $script:ExitWithError = $true
                    return
                }
            }

            # ---------- parse the four embedded XML payloads ----------
            try
            {
                [xml]$autoXml       = $adr.AutoDeploymentProperties
                [xml]$contentXml    = $adr.ContentTemplate
                [xml]$deploymentXml = $adr.DeploymentTemplate
                [xml]$updateRuleXml = $adr.UpdateRuleXML
            }
            catch
            {
                Write-CMTraceLog -Message "File '$Path' contains malformed XML in one of the embedded payloads: $($_.Exception.Message)" -Severity Error
                $script:ExitWithError = $true
                return
            }

            $autoRule   = $autoXml.AutoDeploymentRule
            $contentDef = $contentXml.ContentActionXML
            $deployDef  = $deploymentXml.DeploymentCreationActionXML
            $ruleItems  = $updateRuleXml.UpdateXML.UpdateXMLDescriptionItems.UpdateXMLDescriptionItem

            if (-not $autoRule -or -not $contentDef -or -not $deployDef)
            {
                Write-CMTraceLog -Message "File '$Path' is missing required XML root nodes (AutoDeploymentRule/ContentActionXML/DeploymentCreationActionXML). Cannot import." -Severity Error
                $script:ExitWithError = $true
                return
            }

            $adrName = if ($adr.Name) { $adr.Name } else { $autoRule.DeploymentName }
            if ([string]::IsNullOrWhiteSpace($adrName))
            {
                Write-CMTraceLog -Message "Could not determine ADR name from $Path. Skipping." -Severity Error
                $script:ExitWithError = $true
                return
            }
            Write-CMTraceLog -Message "Processing ADR '$adrName'"

            # ---------- check for existing ADR ----------
            $existing = Get-CMSoftwareUpdateAutoDeploymentRule -Fast -WarningAction SilentlyContinue -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $adrName } |
                Select-Object -First 1
            if ($existing -and -not $Force)
            {
                Write-CMTraceLog -Message "ADR '$adrName' already exists. Use -ForcedImport to update. Skipping." -Severity Warning
                return
            }

            # ---------- collection ----------
            $collectionId = $adr.CollectionID
            if ([string]::IsNullOrWhiteSpace($collectionId))
            {
                $collectionId = $deployDef.CollectionId
            }
            if ([string]::IsNullOrWhiteSpace($collectionId))
            {
                Write-CMTraceLog -Message "ADR '$adrName' has no CollectionID. Skipping." -Severity Error
                $script:ExitWithError = $true
                return
            }
            $collection = Get-CMCollection -Id $collectionId -ErrorAction SilentlyContinue
            if (-not $collection)
            {
                Write-CMTraceLog -Message "Target collection '$collectionId' for ADR '$adrName' does not exist. Skipping." -Severity Error
                $script:ExitWithError = $true
                return
            }

            # ---------- deployment package ----------
            $packageId        = $contentDef.PackageID
            $deploymentPackage = $null
            $noDeploymentPackage = $false
            if ([string]::IsNullOrWhiteSpace($packageId))
            {
                $noDeploymentPackage = $true
                Write-CMTraceLog -Message "ADR '$adrName' has no deployment package (download-only mode)."
            }
            else
            {
                $deploymentPackage = Get-CMSoftwareUpdateDeploymentPackage -Id $packageId -ErrorAction SilentlyContinue
                if (-not $deploymentPackage)
                {
                    Write-CMTraceLog -Message "Deployment package '$packageId' for ADR '$adrName' does not exist. Skipping ADR." -Severity Error
                    $script:ExitWithError = $true
                    return
                }
            }

            # ---------- languages ----------
            $languages = @()
            if ($contentDef.ContentLocales -and $contentDef.ContentLocales.Locale)
            {
                foreach ($loc in @($contentDef.ContentLocales.Locale))
                {
                    $lang = Convert-CMLocaleToLanguageName -LocaleString $loc
                    if ($lang) { $languages += $lang }
                }
            }

            # ---------- product / classification / title / superseded / article / date / required / deployed ----------
            $products        = @()
            $classifications = @()
            $titleIncludes   = @()
            $titleExcludes   = @()
            $superseded      = $null
            $articleId       = $null
            $dateRevised     = 'Any'
            $required        = $null
            $isDeployed      = $null
            $sourceHadProductRule        = $false
            $sourceHadClassificationRule = $false

            foreach ($item in @($ruleItems))
            {
                switch ($item.PropertyName)
                {
                    '_Product'
                    {
                        foreach ($raw in @($item.MatchRules.string))
                        {
                            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
                            $sourceHadProductRule = $true
                            $name = Get-CMUpdateCategoryNameFromGuid -CategoryIdString $raw -CategoryCache $CategoryCache
                            if ($name) { $products += $name }
                        }
                    }
                    '_UpdateClassification'
                    {
                        foreach ($raw in @($item.MatchRules.string))
                        {
                            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
                            $sourceHadClassificationRule = $true
                            $name = Get-CMUpdateCategoryNameFromGuid -CategoryIdString $raw -CategoryCache $CategoryCache
                            if ($name) { $classifications += $name }
                        }
                    }
                    'LocalizedDisplayName'
                    {
                        foreach ($raw in @($item.MatchRules.string))
                        {
                            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
                            if ($raw.StartsWith('-'))
                            {
                                $titleExcludes += $raw.Substring(1)
                            }
                            else
                            {
                                $titleIncludes += $raw
                            }
                        }
                    }
                    'IsSuperseded'
                    {
                        # MatchRules.string may be a string or a string[] when serialized;
                        # take the first value for boolean criteria.
                        $rawVal = @($item.MatchRules.string) | Select-Object -First 1
                        if (-not [string]::IsNullOrWhiteSpace($rawVal))
                        {
                            $superseded = ($rawVal -ieq 'true')
                        }
                    }
                    'IsDeployed'
                    {
                        $rawVal = @($item.MatchRules.string) | Select-Object -First 1
                        if (-not [string]::IsNullOrWhiteSpace($rawVal))
                        {
                            $isDeployed = ($rawVal -ieq 'true')
                        }
                    }
                    'ArticleID'
                    {
                        # Cmdlet accepts a String[] so we keep all distinct values.
                        $articleIdList = @($item.MatchRules.string) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                        if ($articleIdList) { $articleId = $articleIdList }
                    }
                    'NumMissing'
                    {
                        # MatchRule is a criterion string such as ">=1" — the
                        # cmdlet's -Required parameter is String[] of criteria,
                        # so we forward the raw string verbatim.
                        $rawVal = @($item.MatchRules.string) | Select-Object -First 1
                        if (-not [string]::IsNullOrWhiteSpace($rawVal))
                        {
                            $required = $rawVal
                        }
                    }
                    'DateRevised'
                    {
                        $rawVal = @($item.MatchRules.string) | Select-Object -First 1
                        $dateRevised = ConvertFrom-CMDateRevisedString -RawValue $rawVal
                    }
                    default
                    {
                        Write-CMTraceLog -Message "ADR '$adrName' has an UpdateRuleXML PropertyName '$($item.PropertyName)' that is not handled by the importer. The criterion will be skipped." -Severity Information
                    }
                }
            }

            # ---------- run schedule ----------
            # Three modes: ManuallyRun, RunTheRuleAfterAnySoftwareUpdatePointSynchronization, RunTheRuleOnSchedule
            $runType   = 'DoNotRunThisRuleAutomatically'
            $scheduleObject = $null
            if ($autoRule.AlignWithSyncSchedule -ieq 'true')
            {
                $runType = 'RunTheRuleAfterAnySoftwareUpdatePointSynchronization'
            }
            elseif (-not [string]::IsNullOrWhiteSpace($adr.Schedule))
            {
                try
                {
                    $scheduleObject = Convert-CMSchedule -ScheduleString $adr.Schedule -ErrorAction Stop
                    $runType = 'RunTheRuleOnSchedule'
                }
                catch
                {
                    Write-CMTraceLog -Message "Could not convert schedule '$($adr.Schedule)' for ADR '$adrName': $_. Falling back to manual run." -Severity Warning
                    $runType = 'DoNotRunThisRuleAutomatically'
                }
            }

            # ---------- user notification ----------
            $userNotification = switch ($deployDef.UserNotificationOption)
            {
                'HideAll'                  { 'HideAll' ; break }
                'ShowSoftwareCenterOnly'   { 'DisplaySoftwareCenterOnly' ; break }
                'DisplaySoftwareCenterOnly'{ 'DisplaySoftwareCenterOnly' ; break }
                'DisplayAll'               { 'DisplayAll' ; break }
                default                    { 'DisplaySoftwareCenterOnly' }
            }

            # ---------- verbose / state message level ----------
            # ConfigMgr state-message verbosity codes: 1=OnlyError, 5=OnlySuccessAndError, 10=All
            $verboseLevel = switch ([string]$deployDef.StateMessageVerbosity)
            {
                '1'  { 'OnlyErrorMessages' ; break }
                '5'  { 'OnlySuccessAndErrorMessages' ; break }
                '10' { 'AllMessages' ; break }
                default { 'AllMessages' }
            }

            # ---------- pre-flight: ensure category resolution didn't silently
            # ----------            empty out the source's filter set
            if ($sourceHadProductRule -and $products.Count -eq 0)
            {
                Write-CMTraceLog -Message "ADR '$adrName' had product filter(s) in the source but none could be resolved against this site's update categories. Aborting import to avoid creating an over-broad ADR." -Severity Error
                $script:ExitWithError = $true
                return
            }
            if ($sourceHadClassificationRule -and $classifications.Count -eq 0)
            {
                Write-CMTraceLog -Message "ADR '$adrName' had update classification filter(s) in the source but none could be resolved against this site's update categories. Aborting import to avoid creating an over-broad ADR." -Severity Error
                $script:ExitWithError = $true
                return
            }

            # ---------- content source flags ----------
            # The exported ContentTemplate.ContentSources can list Internet, WSUS
            # and UNC. Only the Internet source maps to a documented New-CMSU…ADR
            # parameter (-DownloadFromInternet). 'WSUS' is the standard
            # SUP-served path and needs no special flag. The -DownloadFromMicrosoftUpdate
            # parameter is a *fallback-to-cloud* option that is NOT represented by
            # a WSUS source entry and must not be derived from one. UNC sources
            # cannot be set via the cmdlet either; we warn the operator if one is
            # present.
            $downloadFromInternet = $false
            $hasUncSource         = $false
            if ($contentDef.ContentSources -and $contentDef.ContentSources.Source)
            {
                foreach ($src in @($contentDef.ContentSources.Source))
                {
                    switch ($src.Name)
                    {
                        'Internet' { $downloadFromInternet = $true }
                        'UNC'      { $hasUncSource = $true }
                    }
                }
            }
            if ($hasUncSource)
            {
                Write-CMTraceLog -Message "ADR '$adrName' has a UNC content source which cannot be re-applied via the official cmdlet. Re-add it manually in the console after import." -Severity Warning
            }

            # IsDeployed criterion cannot be re-applied via the official cmdlet
            if ($null -ne $isDeployed)
            {
                Write-CMTraceLog -Message "ADR '$adrName' has an 'IsDeployed' filter (value=$isDeployed) that cannot be set via the official cmdlet. Re-add it manually in the console after import." -Severity Warning
            }

            # ---------- helper to translate Checked/Unchecked/true/false to bool ----------
            $toBool = {
                param($v)
                if ($null -eq $v) { return $false }
                $s = [string]$v
                return ($s -ieq 'true' -or $s -ieq 'checked')
            }

            # ---------- build splat for New-CMSoftwareUpdateAutoDeploymentRule ----------
            # The shorter New-CMAutoDeploymentRule is an undocumented alias of the
            # canonical New-CMSoftwareUpdateAutoDeploymentRule and we use the
            # canonical form (same for Set-/Get-).
            $newAdrParams = @{
                Name                                 = $adrName
                Collection                           = $collection
                AddToExistingSoftwareUpdateGroup     = ($autoRule.UseSameDeployment -ieq 'true')
                EnabledAfterCreate                   = ($autoRule.EnableAfterCreate -ieq 'true')
                NoInstallOnRemote                    = -not ($deployDef.UseRemoteDP -ieq 'true')
                NoInstallOnUnprotected               = -not ($deployDef.UseUnprotectedDP -ieq 'true')
                UseBranchCache                       = (& $toBool $deployDef.UseBranchCache)
                AllowRestart                         = (& $toBool $deployDef.AllowRestart)
                AllowSoftwareInstallationOutsideMaintenanceWindow = (& $toBool $deployDef.AllowInstallOutSW)
                AllowUseMeteredNetwork               = (& $toBool $deployDef.AllowUseMeteredNetwork)
                SendWakeupPacket                     = (& $toBool $deployDef.EnableWakeOnLan)
                UseUtc                               = (& $toBool $deployDef.Utc)
                # Note: docs spell these without the trailing 's' on
                # New-/Set-CMSoftwareUpdateAutoDeploymentRule.
                DisableOperationManager              = (& $toBool $deployDef.DisableMomAlert)
                GenerateOperationManagerAlert        = (& $toBool $deployDef.GenerateMomAlert)
                RequirePostRebootFullScan            = (& $toBool $deployDef.RequirePostRebootFullScan)
                SoftDeadlineEnabled                  = (& $toBool $deployDef.SoftDeadlineEnabled)
                UserNotification                     = $userNotification
                VerboseLevel                         = $verboseLevel
                RunType                              = $runType
                DateReleasedOrRevised                = $dateRevised
                DownloadFromInternet                 = $downloadFromInternet
                # NOTE: -DownloadFromMicrosoftUpdate (cloud fallback) is deliberately
                # NOT derived from the 'WSUS' content source. WSUS is the standard
                # SUP-served path and does NOT imply cloud fallback. Leave the flag
                # off and let the cmdlet apply its safe default (False).
            }

            if ($adr.Description) { $newAdrParams.Description = $adr.Description }
            if ($null -ne $superseded) { $newAdrParams.Superseded = $superseded }
            # -Required is a String[] of criteria expressions (e.g. ">=1"), NOT
            # a Boolean. Pass the raw value forward as an array.
            if (-not [string]::IsNullOrWhiteSpace([string]$required)) { $newAdrParams.Required = @([string]$required) }
            if ($products.Count -gt 0) { $newAdrParams.Product = @($products | Sort-Object -Unique) }
            if ($classifications.Count -gt 0) { $newAdrParams.UpdateClassification = @($classifications | Sort-Object -Unique) }
            if ($languages.Count -gt 0) { $newAdrParams.Language = @($languages | Sort-Object -Unique) }
            if ($articleId) { $newAdrParams.ArticleId = @($articleId) }
            # -Title takes a String[] so pass the array unjoined.
            if ($titleIncludes.Count -gt 0) { $newAdrParams.Title = @($titleIncludes | Sort-Object -Unique) }
            # New-CMSoftwareUpdateAutoDeploymentRule has no -TitleExclude / exclusion parameter.
            # Title exclusions defined in the source ADR cannot be re-applied via the cmdlet
            # and have to be added manually in the SCCM console after import. Warn the operator.
            if ($titleExcludes.Count -gt 0)
            {
                Write-CMTraceLog -Message "ADR '$adrName' has title EXCLUSIONS [$($titleExcludes -join ', ')] that cannot be set via the official cmdlet. Re-add them manually in the console after import." -Severity Warning
            }
            if ($scheduleObject) { $newAdrParams.Schedule = $scheduleObject }
            if ($deploymentPackage)
            {
                $newAdrParams.DeploymentPackage = $deploymentPackage
            }
            elseif ($noDeploymentPackage)
            {
                # The cmdlet does not have a -NoDeploymentPackage switch; the
                # documented way to create a "no package" / download-only ADR is to
                # set -DeploymentPackage $null.
                $newAdrParams.DeploymentPackage = $null
            }

            # Deployment timing (deadline / available)
            $deadline = [int]$deployDef.Duration
            $available = [int]$deployDef.AvailableDeltaDuration
            if ($deadline -le 0)
            {
                $newAdrParams.DeadlineImmediately = $true
            }
            else
            {
                # Explicit $false so an update can flip a previously immediate
                # ADR back to a delayed deadline.
                $newAdrParams.DeadlineImmediately = $false
                $newAdrParams.DeadlineTime     = $deadline
                $newAdrParams.DeadlineTimeUnit = ConvertFrom-CMDurationUnit -Unit $deployDef.DurationUnits
            }
            if ($available -le 0)
            {
                $newAdrParams.AvailableImmediately = $true
            }
            else
            {
                # Explicit $false – same reasoning as DeadlineImmediately.
                $newAdrParams.AvailableImmediately = $false
                $newAdrParams.AvailableTime     = $available
                $newAdrParams.AvailableTimeUnit = ConvertFrom-CMDurationUnit -Unit $deployDef.AvailableDeltaDurationUnits
            }

            # Alert (failure threshold)
            if ((& $toBool $deployDef.EnableAlert))
            {
                $newAdrParams.AlertTime     = [int]$deployDef.AlertDuration
                $newAdrParams.AlertTimeUnit = ConvertFrom-CMDurationUnit -Unit $deployDef.AlertDurationUnits
            }

            # Suppress restart flags — always assign so the update path can clear them
            # back to $false (a conditional assignment would silently leave a previously
            # set $true value in place on an existing ADR).
            $newAdrParams.SuppressRestartServer      = ($deployDef.SuppressServers      -ieq 'Checked')
            $newAdrParams.SuppressRestartWorkstation = ($deployDef.SuppressWorkstations -ieq 'Checked')

            # ---------- create or update ----------
            if ($existing -and $ForcedImport)
            {
                Write-CMTraceLog -Message "Updating existing ADR '$adrName' (ForcedImport)."

                # Set-CMSoftwareUpdateAutoDeploymentRule supports almost the same
                # param set as New-CMSoftwareUpdateAutoDeploymentRule but the rule
                # itself must be passed via -InputObject. We rebuild the splat
                # without -Name/-Collection (collection changes belong to the
                # deployment cmdlet) and without parameters whose names differ
                # between the rule and deployment cmdlets.
                $setRuleParams = @{}
                $ruleScopedKeys = @(
                    'AddToExistingSoftwareUpdateGroup','EnabledAfterCreate','RunType',
                    'DateReleasedOrRevised','Description','Superseded','Required',
                    'Product','UpdateClassification','Language','ArticleId',
                    'Title','Schedule',
                    'DeploymentPackage',
                    'DownloadFromInternet',
                    'DisableOperationManager','GenerateOperationManagerAlert'
                )
                foreach ($k in $ruleScopedKeys)
                {
                    if ($newAdrParams.ContainsKey($k)) { $setRuleParams[$k] = $newAdrParams[$k] }
                }
                Set-CMSoftwareUpdateAutoDeploymentRule -InputObject $existing @setRuleParams -ErrorAction Stop

                # The deployment object lives behind a separate cmdlet
                # (Set-CMAutoDeploymentRuleDeployment), which is identified via
                # -InputObject from Get-CMAutoDeploymentRuleDeployment. The
                # deployment cmdlet uses the plural "DisableOperationsManager"
                # variant so we translate the key on the way in.
                $setDeployParams = @{}
                $deployScopedKeys = @(
                    'NoInstallOnRemote','NoInstallOnUnprotected','UseBranchCache',
                    'AllowRestart','AllowSoftwareInstallationOutsideMaintenanceWindow',
                    'AllowUseMeteredNetwork','SendWakeupPacket','UseUtc',
                    'RequirePostRebootFullScan','SoftDeadlineEnabled',
                    'UserNotification','VerboseLevel',
                    'DeadlineImmediately','DeadlineTime','DeadlineTimeUnit',
                    'AvailableImmediately','AvailableTime','AvailableTimeUnit',
                    'AlertTime','AlertTimeUnit',
                    'SuppressRestartServer','SuppressRestartWorkstation'
                )
                foreach ($k in $deployScopedKeys)
                {
                    if ($newAdrParams.ContainsKey($k)) { $setDeployParams[$k] = $newAdrParams[$k] }
                }
                # Map the rule-side parameter name to the deployment-side spelling
                if ($newAdrParams.ContainsKey('DisableOperationManager'))
                {
                    $setDeployParams.DisableOperationsManager = $newAdrParams['DisableOperationManager']
                }
                if ($newAdrParams.ContainsKey('GenerateOperationManagerAlert'))
                {
                    $setDeployParams.GenerateOperationsManagerAlert = $newAdrParams['GenerateOperationManagerAlert']
                }

                if ($setDeployParams.Count -gt 0)
                {
                    $existingDeployments = Get-CMAutoDeploymentRuleDeployment -Name $adrName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    if (-not $existingDeployments)
                    {
                        Write-CMTraceLog -Message "ADR '$adrName' has no existing deployment objects. Deployment properties not updated." -Severity Warning
                    }
                    else
                    {
                        # The exported file represents ONE deployment (the one bound
                        # to $collectionId). If the target ADR has multiple
                        # deployments (extra collections added later), only update
                        # the one whose target collection matches – applying the
                        # imported template to all of them would silently overwrite
                        # unrelated deployment settings.
                        $allDeployments = @($existingDeployments)
                        $matchingDeployments = @(
                            $allDeployments | Where-Object {
                                $_.CollectionID -eq $collectionId -or
                                $_.TargetCollectionID -eq $collectionId -or
                                $_.AssignedCollectionID -eq $collectionId
                            }
                        )
                        if ($matchingDeployments.Count -eq 0)
                        {
                            # Fallback: target ADR has deployments but none match
                            # the imported CollectionID. Only update if there's
                            # exactly one deployment overall (unambiguous).
                            if ($allDeployments.Count -eq 1)
                            {
                                $matchingDeployments = $allDeployments
                                Write-CMTraceLog -Message "ADR '$adrName': could not match imported CollectionID '$collectionId' to existing deployment; updating the single existing deployment." -Severity Warning
                            }
                            else
                            {
                                Write-CMTraceLog -Message "ADR '$adrName' has $($allDeployments.Count) deployments but none match the imported CollectionID '$collectionId'. Deployment properties not updated to avoid clobbering unrelated deployments." -Severity Warning
                            }
                        }
                        if ($allDeployments.Count -gt 1)
                        {
                            Write-CMTraceLog -Message "ADR '$adrName' has $($allDeployments.Count) deployments in the target site but the export contains only one. Only the deployment for CollectionID '$collectionId' will be updated; other deployments must be maintained manually." -Severity Warning
                        }
                        foreach ($dep in $matchingDeployments)
                        {
                            Set-CMAutoDeploymentRuleDeployment -InputObject $dep @setDeployParams -ErrorAction Stop
                        }
                    }
                }

                Write-CMTraceLog -Message "ADR '$adrName' updated."
            }
            else
            {
                Write-CMTraceLog -Message "Creating ADR '$adrName' via New-CMSoftwareUpdateAutoDeploymentRule."
                $null = New-CMSoftwareUpdateAutoDeploymentRule @newAdrParams -ErrorAction Stop
                Write-CMTraceLog -Message "ADR '$adrName' created."
            }

            # ---------- align current enabled state with source export ----------
            # AutoDeploymentEnabled is the *current* runtime state, distinct from
            # EnableAfterCreate which only applies at creation time. After create
            # or update, toggle the rule to match what was exported.
            if ($adr.PSObject.Properties['AutoDeploymentEnabled'])
            {
                try
                {
                    $current = Get-CMSoftwareUpdateAutoDeploymentRule -Fast -WarningAction SilentlyContinue -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -eq $adrName } |
                        Select-Object -First 1
                    if ($current)
                    {
                        if ($adr.AutoDeploymentEnabled -and -not $current.AutoDeploymentEnabled)
                        {
                            Write-CMTraceLog -Message "Enabling ADR '$adrName' to match source state."
                            Enable-CMSoftwareUpdateAutoDeploymentRule -InputObject $current -ErrorAction Stop
                        }
                        elseif (-not $adr.AutoDeploymentEnabled -and $current.AutoDeploymentEnabled)
                        {
                            Write-CMTraceLog -Message "Disabling ADR '$adrName' to match source state."
                            Disable-CMSoftwareUpdateAutoDeploymentRule -InputObject $current -ErrorAction Stop
                        }
                    }
                }
                catch
                {
                    Write-CMTraceLog -Message "Could not synchronize enabled state for ADR '$adrName': $_" -Severity Warning
                }
            }
        }
        catch
        {
            Write-CMTraceLog -Message "Error importing ADR from '$Path'. Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Error
            Write-CMTraceLog -Message "$_" -Severity Error
            $script:ExitWithError = $true
        }
    }
    End {}
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
        Write-CMTraceLog -Message "Failed to read `"$($RegKeyPath)`" - `"$($RegKeyValue)`" on remote machine: `"$($ComputerName)`". Line: $($_.InvocationInfo.ScriptLineNumber)" -Severity Warning
        Write-CMTraceLog -Message "$($_)" -Severity Warning
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


#region Function Get-SQLPermissionsAndLogins
<#
.Synopsis
    Get-SQLPermissionsAndLogins
.DESCRIPTION
    Get-SQLPermissionsAndLogins
.EXAMPLE
    Get-SQLPermissionsAndLogins -SQLServerName [SQL server fqdn\instance name]
.EXAMPLE
    Get-SQLPermissionsAndLogins -SQLServerName 'sql1.contoso.local'
.EXAMPLE
    Get-SQLPermissionsAndLogins -SQLServerName 'sql2.contoso.local\instance2'
.PARAMETER $SQLServerName
    FQDN of SQL Server with instancename in case of a named instance
#>
function Get-SQLPermissionsAndLogins
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$SQLServerName
    )

    $commandName = $MyInvocation.MyCommand.Name
    Write-CMTraceLog -Message "Export SQL permissions and logins" 
    $connectionString = "Server=$SQLServerName;Database=msdb;Integrated Security=True"
    Write-Verbose "$commandName`: Connecting to SQL: `"$connectionString`""
    
    $SqlQuery = @'
    USE msdb
    SELECT pr.principal_id, pr.name, pr.type_desc,   
    pe.state_desc, pe.permission_name   
    FROM sys.server_principals AS pr   
    JOIN sys.server_permissions AS pe   
    ON pe.grantee_principal_id = pr.principal_id;
'@

    try 
    {
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = $connectionString
        $SqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $SqlCmd.Connection = $SqlConnection
        $SqlCmd.CommandText = $SqlQuery
        $SqlAdapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter
        Write-Verbose "$commandName`: Running Query: `"$SqlQuery`""
        $SqlAdapter.SelectCommand = $SqlCmd
        $ds = New-Object -TypeName System.Data.DataSet
        $SqlAdapter.Fill($ds) | Out-Null
        $SqlCmd.Dispose()
    }
    catch 
    {
        Write-CMTraceLog -Severity Error -Message "Connection to SQL server failed" 
        Write-CMTraceLog -Severity Error -Message "$($Error[0].Exception)" 
        Exit 1   
    }

    if ($SqlConnection)
    {
        if($SqlConnection.state -ieq 'Open')
        {
            Write-CMTraceLog -Message "Will close SQL connection" 
            $SqlConnection.Close()
        }
    }

    return $ds.tables[0]
}
#endregion


#region Function Start-SQLDatabaseBackup
<#
.Synopsis
    Start-SQLDatabaseBackup
.DESCRIPTION
    Will backup a database or multiple database files
.EXAMPLE
    Start-SQLDatabaseBackup -SQLServerName [SQL server fqdn\instance name]
.EXAMPLE
    Start-SQLDatabaseBackup -SQLServerName 'sql1.contoso.local'
.EXAMPLE
    Start-SQLDatabaseBackup -SQLServerName 'sql2.contoso.local\instance2'
.EXAMPLE
    Start-SQLDatabaseBackup -SQLServerName 'sql1.contoso.local' -BackupFolder 'F:\backup' -SQLDBNameList ('AllUserDatabases')
.PARAMETER SQLServerName
    FQDN of SQL Server with instancename in case of a named instance
.PARAMETER BackupFolder
    Folder to save the backups to. UNC or local. The function will create a sub-folder called 'SQLBackup'
.PARAMETER SQLDBNameList
    Array of database names. Can also contain "AllDatabases" or "AllUserDatabases" to backup everything or just all user databases
#>
Function Start-SQLDatabaseBackup
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory=$true)]
        [string]$SQLServerName,
        [Parameter(Mandatory=$true)]
        [string]$BackupFolder,
        [parameter(Mandatory=$false)]
        [string[]]$SQLDBNameList=('AllUserDatabases')
    )

    # We might need to create a folder
    $sqlBackupFolder = '{0}\SQLBackup' -f $BackupFolder
    try
    {
        # making sure we have a valid backup folder
        if(-NOT(Test-Path $sqlBackupFolder))
        {
            $null = [system.io.directory]::CreateDirectory("$sqlBackupFolder")
        }
    }
    catch
    {
        Write-CMTraceLog -Severity Error -Message "ERROR: Folder could not be created `"$sitebackupPath`"" 
        Write-CMTraceLog -Severity Error -Message "$($Error[0].exception)"  
        Exit 1
    }

    Write-CMTraceLog -Message "Will connect to: $SQLServerName" 
    try 
    {
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = "Integrated Security=SSPI;Persist Security Info=False;Initial Catalog=msdb;Data Source=$SQLServerName;Connection Timeout=20"
        $SqlConnection.Open()
    }
    catch 
    {
        Write-CMTraceLog -Severity Error -Message "Connection to SQL server failed" 
        Exit 1
    }   

    
    # query for all user databases
    if ($SQLDBNameList -icontains 'AllUserDatabases')
    {
        $dbBackupString = 'AllUserDatabases'
        $userDBQuery = "USE Master SELECT name, database_id, create_date FROM sys.databases Where name not in ('master','tempdb','model','msdb');"
    }

    # Query for all DBs. If both AllUserDatabases and AllDatabases passed via parameter, AllDatabases will overwrite the query
    if ($SQLDBNameList -icontains 'AllDatabases')
    {
        $dbBackupString = 'AllDatabases'
        $userDBQuery = "USE Master SELECT name, database_id, create_date FROM sys.databases Where name not in ('tempdb');"
    }

    if (($SQLDBNameList -icontains 'AllUserDatabases') -or ($SQLDBNameList -icontains 'AllDatabases'))
    {
        Write-CMTraceLog -Message "Getting list of databases from SQL because of `"$($dbBackupString)`" setting" 
        try 
        {
            # Get all user databases
            $SqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
            $SqlCmd.Connection = $SqlConnection
            $SqlCmd.CommandText = $userDBQuery
            $SqlAdapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter
            Write-Verbose "$commandName`: Running Query: `"$userDBQuery`""
            $SqlAdapter.SelectCommand = $SqlCmd
            $ds = New-Object -TypeName System.Data.DataSet
            $SqlAdapter.Fill($ds) | Out-Null
            $SqlCmd.Dispose()
            
            $listOfUserDBs = $ds.tables[0]         
        }
        catch 
        {
            Write-CMTraceLog -Severity Error -Message "Connection to SQL server failed" 
            Write-CMTraceLog -Severity Error -Message "$($Error[0].Exception)" 
            Exit 1           
        }
    }

    # If we have a list of DBs. Use them instead of a provided list from parameter $SQLDBNameList
    if ($listOfUserDBs)
    {
        $SQLDBNameList = $listOfUserDBs.Name
    }

    [string]$backupDatetime = get-date -f 'yyyyMMdd_HHmmss' # Will be added to the backup file name
    foreach ($dbName in $SQLDBNameList)
    {
        Write-CMTraceLog -Message "Will try to backup database: $dbName" 
        try 
        {
            # Backup variable definition
            [string]$backupFileFullName = '{0}\{1}_backup_{2}.bak' -f $sqlBackupFolder, $dbName, $backupDatetime
            [string]$backupName = '{0}-Full Database Backup' -f $dbName
            $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
            $SqlCmd.CommandText = "BACKUP DATABASE [$dbName] TO  DISK = N'$backupFileFullName' WITH NOFORMAT, NOINIT,  NAME = N'$backupName', SKIP, NOREWIND, NOUNLOAD, COMPRESSION, STATS = 10"
            $SqlCmd.Connection = $SqlConnection
            $SqlCmd.CommandTimeout = 0 
            $null = $SqlCmd.ExecuteScalar()
        }
        catch 
        {
            Write-CMTraceLog -Severity Error -Message "DB backup failed" 
            if ($Error[0].Exception -match '(Access is denied)|(error 5)')
            {
                Write-CMTraceLog -Severity Error -Message "Access is denied" 
                Write-CMTraceLog -Severity Error -Message "SQL service account might not have write access to: $BackupFolder" 
            }
            else 
            {
                Write-CMTraceLog -Severity Error -Message "Database backup failed" 
                Write-CMTraceLog -Severity Error -Message "$($Error[0].Exception)" 
            }
            Exit 1      
        }
    }

    if ($SqlConnection)
    {
        if($SqlConnection.state -ieq 'Open')
        {
            Write-CMTraceLog -Message "Will close SQL connection" 
            $SqlConnection.Close()
        }
    }

}
#endregion

#region Get-SQLVersionInfo
<#
.Synopsis
    Get-SQLVersionInfo
.DESCRIPTION
    Get-SQLVersionInfo
.EXAMPLE
    Get-SQLVersionInfo -SQLServerName [SQL server fqdn\instance name]
.EXAMPLE
    Get-SQLVersionInfo -SQLServerName 'sql1.contoso.local'
.EXAMPLE
    Get-SQLVersionInfo -SQLServerName 'sql2.contoso.local\instance2'
.PARAMETER SQLServerName
    FQDN of SQL Server with instancename in case of a named instance
#>
Function Get-SQLVersionInfo
{
    param
    (
        [string]$SQLServerName
    )

    $commandName = $MyInvocation.MyCommand.Name
    Write-CMTraceLog -Message "Get SQL version info" 
    $connectionString = "Server=$SQLServerName;Database=msdb;Integrated Security=True"
    Write-Verbose "$commandName`: Connecting to SQL: `"$connectionString`""
    
    $SqlQuery = 'USE msdb;SELECT @@Version as [SQLVersion]'

    try 
    {
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = $connectionString
        $SqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $SqlCmd.Connection = $SqlConnection
        $SqlCmd.CommandText = $SqlQuery
        $SqlAdapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter
        Write-Verbose "$commandName`: Running Query: `"$SqlQuery`""
        $SqlAdapter.SelectCommand = $SqlCmd
        $ds = New-Object -TypeName System.Data.DataSet
        $SqlAdapter.Fill($ds) | Out-Null
        $SqlCmd.Dispose()
    }
    catch 
    {
        Write-CMTraceLog -Severity Error -Message "Connection to SQL server failed" 
        Write-CMTraceLog -Severity Error -Message "$($Error[0].Exception)" 
        Exit 1   
    }
    return $ds.tables[0]
}
#endregion




# Check if none of the switch parameters are set
if (-not ($ExportAllItemTypes -or $ExportCollections -or $ExportConfigurationItems -or $ExportConfigurationBaselines -or $ExportTaskSequences -or $ExportAntimalwarePolicies -or $ExportScripts -or $ExportClientSettings -or $ExportConfigurationPolicies -or $ExportAutomaticDeploymentRules -or $ExportCDLatest -or $ImportAutomaticDeploymentRules)) 
{
    Write-CMTraceLog -Message "No export type selected. Please use one of the following parameters: -ExportAllItemTypes, -ExportCollections, -ExportConfigurationItems, -ExportConfigurationBaselines, -ExportTaskSequences, -ExportAntimalwarePolicies, -ExportScripts, -ExportClientSettings, -ExportConfigurationPolicies, -ExportAutomaticDeploymentRules, -ExportCDLatest, -ImportAutomaticDeploymentRules" -Severity Warning
    Exit 1 
}

# Validate import parameter combination early
if ($ImportAutomaticDeploymentRules)
{
    if ([string]::IsNullOrWhiteSpace($ImportFolder))
    {
        Write-CMTraceLog -Message "-ImportAutomaticDeploymentRules requires -ImportFolder to point at a folder with the exported ADR XML files." -Severity Error
        Exit 1
    }
    if (-not (Test-Path -LiteralPath $ImportFolder))
    {
        Write-CMTraceLog -Message "Import folder '$ImportFolder' does not exist." -Severity Error
        Exit 1
    }
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
    Write-CMTraceLog -Message "---------------------------------"
    Write-CMTraceLog -Message " -> Getting general site information..."
    Write-CMTraceLog -Message "---------------------------------"
    $SiteData = Get-ConfigMgrSiteInfo -ProviderMachineName $ProviderMachineName -SiteCode $SiteCode

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

    # Export automatic deployment rules
    if ($ExportAutomaticDeploymentRules -or $ExportAllItemTypes)
    {
        Write-CMTraceLog -Message "---------------------------------"
        Write-CMTraceLog -Message " -> Will export automatic deployment rules..."
        Write-CMTraceLog -Message "---------------------------------"
        # No -Fast so the lazy XML properties of the SMS_AutoDeployment object are loaded
        Get-CMAutoDeploymentRule | Export-CMItemCustomFunction
    }

    # Import automatic deployment rules
    if ($ImportAutomaticDeploymentRules)
    {
        Write-CMTraceLog -Message "---------------------------------"
        Write-CMTraceLog -Message " -> Will import automatic deployment rules from: $ImportFolder"
        Write-CMTraceLog -Message "---------------------------------"

        # Collect candidate XML files. We accept any *.xml that is not one of the
        # metadata side files produced by the exporter.
        $adrXmlFiles = Get-ChildItem -Path $ImportFolder -Filter '*.xml' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -notlike '*.metadata.xml' -and
                $_.Name -notlike '*.deployments.xml' -and
                $_.Name -notlike '*.hinvclasses.xml' -and
                $_.Name -notlike '*.references.xml'
            }

        if (-not $adrXmlFiles -or $adrXmlFiles.Count -eq 0)
        {
            Write-CMTraceLog -Message "No ADR XML files found in '$ImportFolder'." -Severity Warning
        }
        else
        {
            Write-CMTraceLog -Message "Found $($adrXmlFiles.Count) candidate ADR XML file(s)."
            # Shared cache so the same product/classification GUID is only looked up once
            $script:AdrCategoryCache = @{}
            # Push the current location so each import call can freely Set-Location
            # to the SiteCode PSDrive without stranding the caller there afterwards.
            Push-Location
            try
            {
                foreach ($adrFile in $adrXmlFiles)
                {
                    Import-CMAutoDeploymentRuleFromXml -Path $adrFile.FullName -Force:$ForcedImport -CategoryCache $script:AdrCategoryCache
                }
            }
            finally
            {
                Pop-Location
            }
        }
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

    if ($BackupConfigMgrUserDatabases)
    {
        Start-SQLDatabaseBackup -SQLServerName $SiteData.SQLServerName -BackupFolder $script:FullExportFolderName

        $sqlInfoFile = '{0}\SQLBackup\SQL-Versioninfo.txt' -f $script:FullExportFolderName
        (Get-SQLVersionInfo -SQLServerName $SiteData.SQLServerName).ItemArray | Out-File $sqlInfoFile -Force
    }

    if ($BackupWSUSUSusdb)
    {
        # We dont want to backup the database twice in case it runs on the same SQL Server as the ConfigMgr db
        # In case we need to compare netbios name and DB we need to extract that from something like this: CM02.contoso.local
        $sqlServerNetbiosOnly = $siteInfo.SQLServerName -replace '\..*'
        [bool]$supDBRunsOnSameSQLServer = $false

        if ($siteInfo.SQLInstance -eq "Default")
        {
            # we just need to check the servername
            if ($siteInfo.SUPList.DBServerName -imatch $siteInfo.SQLServerName) 
            {
                $supDBRunsOnSameSQLServer = $true
            }
            elseif ($siteInfo.SUPList.DBServerName -imatch $sqlServerNetbiosOnly)
            {
                $supDBRunsOnSameSQLServer = $true
            }
        }
        else
        {
            # we also need to check the instancename, could be different
            if (($siteInfo.SUPList.DBServerName -imatch $siteInfo.SQLServerName) -and ($siteInfo.SUPList.DBServerName -imatch $siteInfo.SQLInstance)) 
            {
                $supDBRunsOnSameSQLServer = $true
            }
            elseif (($siteInfo.SUPList.DBServerName -imatch $sqlServerNetbiosOnly) -and ($siteInfo.SUPList.DBServerName -imatch $siteInfo.SQLInstance))
            {
                $supDBRunsOnSameSQLServer = $true
            }
        }

        if ($supDBRunsOnSameSQLServer)
        {
            if ($BackupConfigMgrUserDatabases)
            {
                Write-CMTraceLog -Message "WSUS runs on the same SQL instance and SQL backup was made already. Will not backup SUSDB again" -Severity Warning
            }
            else 
            {
                Write-CMTraceLog -Message "WSUS runs on the SQL instance. ConfigMgr DB backup not active. Will start backup of SUSDB."
                Start-SQLDatabaseBackup -SQLServerName $SiteData.SQLServerName -BackupFolder $script:FullExportFolderName -SQLDBNameList @('SUSDB')
            }
        }
        else 
        {
            Write-CMTraceLog -Message "WSUS has its own machine. Will start backup of SUSDB."
            Start-SQLDatabaseBackup -SQLServerName ($siteInfo.SUPList.DBServerName) -BackupFolder $script:FullExportFolderName -SQLDBNameList @('SUSDB')
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

# Log the parameters that were used to start the script. Helps to replicate a run or troubleshoot errors later.
Write-CMTraceLog -Message "---------------------------------"
Write-CMTraceLog -Message " -> Script was started with the following parameters:"
Write-CMTraceLog -Message "---------------------------------"
if ($PSBoundParameters.Count -gt 0)
{
    foreach ($paramName in ($PSBoundParameters.Keys | Sort-Object))
    {
        $paramValue = $PSBoundParameters[$paramName]
        if ($paramValue -is [switch])
        {
            $paramValue = $paramValue.IsPresent
        }
        Write-CMTraceLog -Message ("    -{0} = {1}" -f $paramName, $paramValue)
    }
}
else
{
    Write-CMTraceLog -Message "    No parameters were passed to the script."
}

# Log the script runtime
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