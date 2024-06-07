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
.SYNOPSIS
Script to analyze ConfigMgr applications, create Intune win32 app packages and upload them to Intune.

.DESCRIPTION
This script will analyze ConfigMgr applications, create Intune win32 app packages and upload them to Intune. 
The script is devided into different actions, which can be run separately in groups or all together.
The individual actions are:

    #1 GetConfigMgrAppInfo: 
    Get information about ConfigMgr applications.  All selected apps will be exported to a folder without content.
    The script will also analyze the exported apps to mark apps with configurations not supported by the script or Intune.
    
    #2 CreateIntuneWinFiles: 
    Create Intune win32 app packages exported to the export folder. 
    The script will create Intune win32 app packages from the source files of each app.
    The script will also download the Microsoft Win32 Content Prep Tool if it's not already downloaded.
    
    #3 UploadAppsToIntune: 
    The script will upload selected apps to Intune.

    Actions #2 and #3 can be run together with the script mode CreateIntuneWinFilesAndUploadToIntune.

To store the individual items the script will create the following folder under the ExportFolder:
    Content     - Contains the content of the ConfigMgr applications. Not used at the moment.
    Tools       - Contains the tools used by the script. Currently just the Microsoft Win32 Content Prep Tool.
    AppDetails  - Contains the details of the ConfigMgr applications. In JSON and XML format. JSON to be able to analyze the data in an easy way. The XML will be used by the script.
    Icons       - Contains exported icons of each ConfigMgr applications.
    Scripts     - Contains exported scripts if a ConfigMgr application is configured to use script detection types.
    Win32Apps   - Contains the exported Intune win32 app packages.

The script will create a log file in the same directory as the script file.

AppDetectionRuleMSI not yet implemented

.PARAMETER SiteCode
The ConfigMgr site code.

.PARAMETER ProviderMachineName
The ConfigMgr SMS Provider machine name.

.PARAMETER ExportFolder
The folder where the exported content will be stored.

.PARAMETER MaxAppRunTimeInMinutes
The maximum application run time in minutes. Will only be used if the deployment type has no value set.

.PARAMETER Win32ContentPrepToolUri
The URI to the Microsoft Win32 Content Prep Tool.

.PARAMETER ScriptMode
The script mode to run

.PARAMETER EntraIDAppID
The AppID of the Enterprise Application in Azure AD. 
Only required if the script should use a custom app instead of the default app: "Microsoft Graph Command Line Tools" AppID=14d82eec-204b-4c2f-b7e8-296a70dab67e

.PARAMETER EntraIDTenantID
The TenantID of the Enterprise Application in Azure AD.
Only required if the script should use a custom app instead of the default app.

.PARAMETER PublisherIfNoneIsSet
The publisher to use if none is set in the ConfigMgr application.
Default is "IT".

.PARAMETER DescriptionIfNoneIsSet
The description to use if none is set in the ConfigMgr application.
Default is "Imported app".



#>
param
(
    # Parameter help description
    [Parameter(Mandatory = $false)]
    [string]$SiteCode = "P02", # Site code
    [Parameter(Mandatory = $false)] 
    [string]$ProviderMachineName = "CM02.contoso.local", # SMS Provider machine name
    [Parameter(Mandatory = $false)]
    [string]$ExportFolder = 'C:\ExportToIntune',
    [Parameter(Mandatory = $false)]
    [int]$MaxAppRunTimeInMinutes = 60, # Maximum application run time in minutes. Will only be used if the deployment type has no value set.
    [Parameter(Mandatory = $false)]
    [string]$Win32ContentPrepToolUri = 'https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe',
    #[string]$AzCopyUri = "https://aka.ms/downloadazcopy-v10-windows",
    [Parameter(Mandatory = $false)]
    [ValidateSet("GetConfigMgrAppInfo", "CreateIntuneWinFiles", "UploadAppsToIntune", "CreateIntuneWinFilesAndUploadToIntune", "RunAllActions")]
    [string]$ScriptMode,
    [Parameter(Mandatory = $false)]
    [string]$EntraIDAppID,
    [Parameter(Mandatory = $false)]
    [string]$EntraIDTenantID,
    [Parameter(Mandatory = $false)]
    [string]$PublisherIfNoneIsSet = 'IT',
    [Parameter(Mandatory = $false)]
    [string]$DescriptionIfNoneIsSet = 'Imported app',
    [Parameter(Mandatory = $false)]
    [ValidateSet("Console","Log","ConsoleAndLog")]
    [string]$OutputMode = 'ConsoleAndLog'
)


$global:LogOutputMode = $OutputMode
#$Global:LogFilePath = '{0}\{1}.log' -f $PSScriptRoot ,($MyInvocation.MyCommand -replace '.ps1') # Next to the script
$Global:LogFilePath = '{0}\{1}.log' -f $ExportFolder ,($MyInvocation.MyCommand -replace '.ps1') # Next to the exported data. Might make more sense.

# Array of displayed properties for the ConfigMgr applications shown in a GridView
$arrayOfDisplayedProperties = @(
    'LocalizedDisplayName',
    'CIVersion',
    'HasContent',
    'IsDeployed',
    'IsSuperseded',	
    'IsSuperseding',
    'NumberOfDeploymentTypes',
    'NumberOfApplicationGroups',
    'NumberOfDependentDTs',	
    'NumberOfDependentTS',
    'CreatedBy',
    'DateCreated',	
    'DateLastModified',
    'CI_ID',
    'CI_UniqueID'
)

#region admin rights
#Ensure that the Script is running with elevated permissions
if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    # Not really required if we have write access to the export folder
    #Write-Warning 'The process needs admin rights to run. Please re-run the process with admin rights.' 
    #Read-Host -Prompt "Press any key to exit"
    #Exit 0 
}
#endregion


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
        [String]$LogFile=$Global:LogFilePath,

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
        [string]$OutputMode = $global:LogOutputMode
    )

    if ([string]::IsNullOrEmpty($OutputMode))
    {
        $OutputMode = 'Log'
    }

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
    
#region Rollover-Logfile
<# 
.Synopsis
    Function Rollover-Logfile

.DESCRIPTION
    Will rename a logfile from ".log" to ".lo_". 
    Old ".lo_" files will be deleted

.PARAMETER MaxFileSizeKB
    Maximum file size in KB in order to determine if a logfile needs to be rolled over or not.
    Default value is 1024 KB.

.EXAMPLE
    Rollover-Logfile -Logfile "C:\Windows\Temp\logfile.log" -MaxFileSizeKB 2048
#>
Function Rollover-Logfile
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

#region function Get-SanitizedString
<#
.SYNOPSIS
    Function to replace invalid characters
#>
function Get-SanitizedString
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [string]$String
    )

    # Get invalid path characters
    $invalidChars = [IO.Path]::GetInvalidPathChars() -join ''

    # Escape special regex characters
    $invalidChars = [Regex]::Escape($invalidChars)

    # Replace invalid characters with underscore
    $String = $String -replace "[$invalidChars]", '_'

    # Replace invalid characters with underscore
    #$String = $String -replace "( )|(\+)|(\&)", '_'

    # Replace invalid characters with underscore
    return ($String -replace '[\[\\/:*?"<>|\]]', '_' -replace ',')
}
#endregion



#region Get-FilterEDM (Enhanced Detection Method)
<#
.SYNOPSIS
    Base structure coming from: https://github.com/paulwetter/DocumentConfigMgrCB
    Slighlty altered to get the data required for Intune Win32 app creation process.
#>
Function Get-FilterEDM {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [xml]
        $EnhancedDetectionMethods,
        [Parameter(Mandatory = $true)]
        $RuleExpression,
        [Parameter(Mandatory = $false)]
        $DMSummary = (New-Object PSObject),
        [Parameter(Mandatory = $false)]
        [Switch]$FlatDetectionList
    )

    #region Required operator hashtables

    <#
    Type:	RegistryValueRuleExpressionOperator ConfigMgr
    Accepted values:	Equals, NotEquals, GreaterThan, LessThan, Between, GreaterEquals, LessEquals, OneOf, NoneOf, BeginsWith, NotBeginsWith, EndsWith, NotEndsWith, Contains, NotContains

    Type:	RegistryValueRuleExpressionOperator Intune
    Accepted values:	"equal", "notEqual", "greaterThanOrEqual", "greaterThan", "lessThanOrEqual", "lessThan"


    Type:	FileFolderRuleExpressionOperator of ConfigMgr
    Accepted values:	Equals, NotEquals, GreaterThan, LessThan, Between, GreaterEquals, LessEquals, OneOf, NoneOf

    Type:	FileFolderRuleExpressionOperator of Intune
    Accepted values:	"equal", "notEqual", "greaterThanOrEqual", "greaterThan", "lessThanOrEqual", "lessThan"


    Type:	WindowsInstallerRuleExpressionOperator of ConfigMgr
    Accepted values:	Equals, NotEquals, GreaterThan, LessThan, GreaterEquals, LessEquals

    Type:	WindowsInstallerRuleExpressionOperator of Intune
    Accepted values:	"notConfigured", "equal", "notEqual", "greaterThanOrEqual", "greaterThan", "lessThanOrEqual", "lessThan"

    Create code with GitHub Copilot:
    Create three hashtables to match possible ConfigMgr operators to their equivalant in Intune. 
    If there is no matching operator in Intune, set the Intune value to "NotSupported".

    #>

    $registryValueRuleExpressionOperatorMapping = @{
        "Equals" = "equal"
        "NotEquals" = "notEqual"
        "GreaterThan" = "greaterThan"
        "LessThan" = "lessThan"
        "Between" = "NotSupported"
        "GreaterEquals" = "greaterThanOrEqual"
        "LessEquals" = "lessThanOrEqual"
        "OneOf" = "NotSupported"
        "NoneOf" = "NotSupported"
        "BeginsWith" = "NotSupported"
        "NotBeginsWith" = "NotSupported"
        "EndsWith" = "NotSupported"
        "NotEndsWith" = "NotSupported"
        "Contains" = "NotSupported"
        "NotContains" = "NotSupported"
    }

    $fileFolderRuleExpressionOperatorMapping = @{
        "Equals" = "equal"
        "NotEquals" = "notEqual"
        "GreaterThan" = "greaterThan"
        "LessThan" = "lessThan"
        "Between" = "NotSupported"
        "GreaterEquals" = "greaterThanOrEqual"
        "LessEquals" = "lessThanOrEqual"
        "OneOf" = "NotSupported"
        "NoneOf" = "NotSupported"
    }

    $windowsInstallerRuleExpressionOperatorMapping = @{
        "Equals" = "equal"
        "NotEquals" = "notEqual"
        "GreaterThan" = "greaterThan"
        "LessThan" = "lessThan"
        "GreaterEquals" = "greaterThanOrEqual"
        "LessEquals" = "lessThanOrEqual"
    }
    #endregion


    $flatResultList = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($Expression in $RuleExpression) {
        If ($Expression.Operator -eq 'And') {
            Write-Verbose "adding an And"
            if ($DMSummary.PSObject.Properties.Name -notcontains 'And') {
                Add-Member -InputObject $DMSummary -NotePropertyName 'And' -NotePropertyValue @()
            }

            if ($FlatDetectionList)
            {
                [array]$TheseDetails = Get-FilterEDM -EnhancedDetectionMethods $EnhancedDetectionMethods -RuleExpression $Expression.Operands.Expression -FlatDetectionList
                $TheseDetails | ForEach-Object {$flatResultList.Add($_)}
            }
            else 
            {
                $TheseDetails = Get-FilterEDM -EnhancedDetectionMethods $EnhancedDetectionMethods -RuleExpression $Expression.Operands.Expression
                foreach ($key in $TheseDetails.PSObject.Properties.Name) {
                    $DMSummary.And += New-Object PSObject -Property @{$key = $($TheseDetails.$key) }
                }
            }
        }
        ElseIf ($Expression.Operator -eq 'Or') {
            Write-Verbose "adding an Or"
            if ($DMSummary.PSObject.Properties.Name -notcontains 'Or') {
                Add-Member -InputObject $DMSummary -NotePropertyName 'Or' -NotePropertyValue @()
            }        

            if ($FlatDetectionList)
            {
                $tmpObj = [PSCustomObject]@{
                    RulesWithOr = $true
                }
                $flatResultList.Add($tmpObj)

                [array]$TheseDetails = Get-FilterEDM -EnhancedDetectionMethods $EnhancedDetectionMethods -RuleExpression $Expression.Operands.Expression -FlatDetectionList
                $TheseDetails | ForEach-Object {$flatResultList.Add($_)}
            }
            else 
            {
                $TheseDetails = Get-FilterEDM -EnhancedDetectionMethods $EnhancedDetectionMethods -RuleExpression $Expression.Operands.Expression
                foreach ($key in $TheseDetails.PSObject.Properties.Name) {
                    $DMSummary.Or += New-Object PSObject -Property @{$key = $($TheseDetails.$key) }
                }
            }
        }
        Else {
            if ($DMSummary.PSObject.Properties.Name -notcontains 'Settings') {
                Add-Member -InputObject $DMSummary -NotePropertyName 'Settings' -NotePropertyValue @()
            }
            $SettingLogicalName = $Expression.Operands.SettingReference.SettingLogicalName
            Switch ($Expression.Operands.SettingReference.SettingSourceType) {
                'Registry' {
                    Write-Verbose "registry Setting"
                    $RegSetting = $EnhancedDetectionMethods.EnhancedDetectionMethod.Settings.SimpleSetting | Where-Object { $_.LogicalName -eq "$SettingLogicalName" }      
                    #$tmpObj = New-Object PSObject -Property @{
                        #'RegSetting' = [PSCustomObject]@{
                        $intuneOperator = $null
                        $intuneOperator = $registryValueRuleExpressionOperatorMapping[$Expression.Operator]

                        $tmpObj = [PSCustomObject]@{
                            DetectionType = 'RegSetting'
                            DetectionTypeIntune = 'AppDetectionRuleRegistry'
                            RegHive     = $RegSetting.RegistryDiscoverySource.Hive
                            RegKey      = $RegSetting.RegistryDiscoverySource.Key
                            RegValue    = $RegSetting.RegistryDiscoverySource.ValueName
                            Is32BitOn64BitSystem    = if($RegSetting.RegistryDiscoverySource.Is64Bit -ieq 'false'){$true}else{$false}
                            RegMethod   = $Expression.Operands.SettingReference.Method
                            RegData     = $Expression.Operands.ConstantValue.Value
                            RegDataList = $Expression.Operands.ConstantValueList.ConstantValue.Value
                            RegDataType = $Expression.Operands.SettingReference.DataType
                            Operator = $Expression.Operator
                            OperatorIntune = if([string]::IsNullOrEmpty($intuneOperator)){'NotSupported'}else{$intuneOperator}
                        }

                    #}
                    $DMSummary.Settings += $tmpObj
                    $flatResultList.Add($tmpObj)
                }
                'File' {
                    $FileSetting = $EnhancedDetectionMethods.EnhancedDetectionMethod.Settings.File | Where-Object { $_.LogicalName -eq "$SettingLogicalName" }
                    #$tmpObj = @{'FileSetting' = [PSCustomObject]@{

                        $intuneOperator = $null
                        $intuneOperator = $fileFolderRuleExpressionOperatorMapping[$Expression.Operator]

                        $tmpObj = [PSCustomObject]@{
                            DetectionType = 'FileSetting'
                            DetectionTypeIntune = 'AppDetectionRuleFileOrFolder'
                            ParentFolder             = $FileSetting.Path
                            FileName                 = $FileSetting.Filter
                            Is32BitOn64BitSystem                = if($FileSetting.Is64Bit -ieq 'false'){$true}else{$false}
                            Operator             = $Expression.Operator
                            OperatorIntune = if([string]::IsNullOrEmpty($intuneOperator)){'NotSupported'}else{$intuneOperator}
                            FileMethod               = $Expression.Operands.SettingReference.Method
                            FileValueList            = $Expression.Operands.ConstantValueList.ConstantValue.Value
                            FileValue                = $Expression.Operands.ConstantValue.Value
                            FilePropertyName         = $Expression.Operands.SettingReference.PropertyPath
                            FilePropertyNameDataType = $Expression.Operands.SettingReference.DataType
                        }

                    #}
                    $DMSummary.Settings += $tmpObj
                    $flatResultList.Add($tmpObj)
                }
                'Folder' {
                    $FolderSetting = $EnhancedDetectionMethods.EnhancedDetectionMethod.Settings.Folder | Where-Object { $_.LogicalName -eq "$SettingLogicalName" }
                    #$tmpObj = @{'FolderSetting' = [PSCustomObject]@{
                        $intuneOperator = $null
                        $intuneOperator = $fileFolderRuleExpressionOperatorMapping[$Expression.Operator]

                        $tmpObj = [PSCustomObject]@{
                            DetectionType = 'FolderSetting'
                            DetectionTypeIntune = 'AppDetectionRuleFileOrFolder'
                            ParentFolder               = $FolderSetting.Path
                            FolderName                 = $FolderSetting.Filter
                            Is32BitOn64BitSystem                = if($FolderSetting.Is64Bit -ieq 'false'){$true}else{$false}
                            Operator             = $Expression.Operator
                            OperatorIntune = if([string]::IsNullOrEmpty($intuneOperator)){'NotSupported'}else{$intuneOperator}
                            FolderMethod               = $Expression.Operands.SettingReference.Method
                            FolderValueList            = $Expression.Operands.ConstantValueList.ConstantValue.Value
                            FolderValue                = $Expression.Operands.ConstantValue.Value
                            FolderPropertyName         = $Expression.Operands.SettingReference.PropertyPath
                            FolderPropertyNameDataType = $Expression.Operands.SettingReference.DataType
                        }
                    #}
                    $DMSummary.Settings += $tmpObj
                    $flatResultList.Add($tmpObj)
                }
                'MSI' {
                    $MSISetting = $EnhancedDetectionMethods.EnhancedDetectionMethod.Settings.MSI | Where-Object { $_.LogicalName -eq "$SettingLogicalName" }
                    if ($Expression.Operands.SettingReference.DataType -eq 'Int64') {
                        #Existensile detection
                        Write-Verbose "MSI Exists on System"
                        #$MSIDetection = "MSI Exists on System"
                    }
                    elseif ($Expression.Operands.SettingReference.DataType -eq 'Version') {
                        #Exists plus is a specific version of MSI
                        Write-Verbose "MSI Version is..."
                        #$MSIOperator = "The MSI $MSIDataType is $(Convert-EdmOperator $Expression.Operator) [$MSIVersion]."
                    }
                    Else {
                        Write-Verbose "Unknown MSI Configuration for product code."
                    }
                    #$tmpObj = @{'MsiSetting' = [PSCustomObject]@{
                        $intuneOperator = $null
                        $intuneOperator = $windowsInstallerRuleExpressionOperatorMapping[$Expression.Operator]

                        $tmpObj = [PSCustomObject]@{
                            DetectionType = 'MsiSetting'
                            DetectionTypeIntune = 'AppDetectionRuleMSI'
                            MSIProductCode  = $MSISetting.ProductCode
                            MSIDataType     = $Expression.Operands.SettingReference.DataType
                            MSIMethod       = $Expression.Operands.SettingReference.Method
                            MSIDataValue    = $Expression.Operands.ConstantValue.Value
                            MSIPropertyName = $Expression.Operands.SettingReference.PropertyPath
                            Operator     = $Expression.Operator
                            OperatorIntune = if([string]::IsNullOrEmpty($intuneOperator)){'NotSupported'}else{$intuneOperator}
                        }
                    #}
                    $DMSummary.Settings += $tmpObj
                    $flatResultList.Add($tmpObj)
                }
            }
        }
    }

    if ($FlatDetectionList)
    {
        return $flatResultList
    }
    else 
    {
        return $DMSummary
    }
    
}
#endregion

#region Wait-ForGraphRequestCompletion 
function Wait-ForGraphRequestCompletion 
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$Uri
    )
    do {
        $GraphRequest = Invoke-MgGraphRequest -Uri $Uri -Method "GET"

        $uploadState = ([regex]::match($GraphRequest.uploadState, '(pending|failed|timedout|success)',1)).value
        $operation = ([regex]::match($GraphRequest.uploadState, '(.+?)(?=pending|failed|timedout|success)',1)).value

        switch ($uploadState) 
        {
            "Pending" 
            {
                Write-CMTraceLog -Message "Intune service request for operation '$($operation)' is in pending state, sleeping for 10 seconds"
                Start-Sleep -Seconds 10
            }
            "Failed" 
            {
                Write-CMTraceLog -Message "Intune service request for operation '$($operation)' failed" -Severity Error
                return $GraphRequest
            }
            "TimedOut" 
            {
                Write-CMTraceLog -Message "Intune service request for operation '$($operation)' timed out" -Severity Error
                return $GraphRequest
            }
        }
    }
    until ($uploadState -ilike "Success")
    Write-CMTraceLog -Message "Intune service request for operation '$($operation)' was successful with uploadState: $($GraphRequest.uploadState)"

    return $GraphRequest
}
#endregion


#regoon folder creation if not done already
# Validate path and create if not there yet
try 
{
    if (-not (Test-Path $ExportFolder)) 
    {
        Write-Host "Export folder: `"$($ExportFolder)`" does not exist. Will be created..." # logfile not ready yet
        New-Item -ItemType Directory -Path $ExportFolder -Force | Out-Null
    }

    # We also need some folders to store the exported data
    $ExportFolderContent = '{0}\Content' -f $ExportFolder
    $ExportFolderTools = '{0}\Tools' -f $ExportFolder
    $ExportFolderAppDetails = '{0}\AppDetails' -f $ExportFolder
    $ExportFolderIcons = '{0}\Icons' -f $ExportFolder
    $ExportFolderScripts = '{0}\Scripts' -f $ExportFolder
    $ExportFolderWin32Apps = '{0}\Win32Apps' -f $ExportFolder

    foreach ($folder in ($ExportFolderContent, $ExportFolderTools, $ExportFolderAppDetails, $ExportFolderIcons, $ExportFolderScripts, $ExportFolderWin32Apps))
    {
        if (-not (Test-Path $folder))
        {
            Write-Host "Will create export folder: `"$($folder)`""
            New-Item -ItemType Directory -Path $folder -Force | Out-Null   
        }
        else 
        {
            Write-Host "Folder: `"$($folder)`" does exist"
        }
    }
}
catch 
{
    Write-Host $_
    Exit 1
}
#endregion

#region initialize log
$stoptWatch = New-Object System.Diagnostics.Stopwatch
$stoptWatch.Start()

Rollover-Logfile -Logfile $Global:LogFilePath -MaxFileSizeKB 2048

Write-CMTraceLog -Message '   '
Write-CMTraceLog -Message 'Start of script'
Write-CMTraceLog -Message "Export will be made to folder: $($ExportFolder)"
#endregion

#region show script run options if none was passed
if ([string]::IsNullOrEmpty($ScriptMode))
{
    Write-CMTraceLog -Message "Parameter ScriptMode not specified. Will show GridView with script run options"
    $scriptModeSelectionHash = [ordered]@{
        "GetConfigMgrAppInfo" = "Step 1: Get information about ConfigMgr applications. All selected apps will be exported to a folder without content. Basis for all other actions."
        "CreateIntuneWinFiles" = "Step 2: The script will create Intune win32 app packages from the source files of each selected app. Step 1 must have been run before this step."
        "UploadAppsToIntune" = "Step 3: The script will upload created Intune win32 app packages to Intune to create an app. Step 1 and 2 must have been run before this step."
        "CreateIntuneWinFilesAndUploadToIntune" = "Run step 2 and step 3 after each other"
        "RunAllActions" = "Run steps 1 to 3. Each step will pause and give you an option to select apps for the running step."
    }

    $scriptModeSelection = $scriptModeSelectionHash | Out-GridView -Title 'Please select a script action' -OutputMode Single
    if ($scriptModeSelection.Name)
    {
        $ScriptMode =  $scriptModeSelection.Name  
    }
    
}
#endregion

#region Get the ConfigMgr apps
if ($scriptMode -in ('GetConfigMgrAppInfo','RunAllActions'))
{

    Write-CMTraceLog -Message "Will get list of ConfigMgr apps"

    $selectedApps = $null
    $appOutObj = [System.Collections.Generic.List[pscustomobject]]::new()
    #region get ConfigMgrApps and show them in a grudview

    $cimSessionOptions = New-CimSessionOption -Protocol Dcom # could also be WSMAN, but with ConfigMgr DCOM should always work
    $cimSession = New-CimSession -ComputerName $ProviderMachineName -SessionOption $cimSessionOptions

    try 
    {
        [array]$allApps = Get-ciminstance -CimSession $cimSession -Namespace "Root\SMS\Site_$($SiteCode)" -Query "SELECT $($arrayOfDisplayedProperties -join ',') FROM SMS_Application WHERE IsLatest = 'True'" -ErrorAction Stop
        if ($null -eq $allApps)
        {
            Write-CMTraceLog -Message "No applications found in ConfigMgr. Check permissions." -Severity Warning
            Exit 1
        }
        else 
        {
            Write-CMTraceLog -Message "Open Out-GridView for app selection"
            $ogvTitle = "Select the apps you want to export to Intune"
            [array]$selectedApps = $allApps | Select-Object -Property $arrayOfDisplayedProperties | Out-GridView -OutputMode Multiple -Title $ogvTitle
        }
        
    }
    catch 
    {
        Write-CMTraceLog -Message "Could not connect to ConfigMgr SMSProvider" -Severity Error
        Write-CMTraceLog -Message "$($_)"
        Exit 1
    }


    Write-CMTraceLog -Message "Total selected apps: $(($selectedApps).count)"
    #Lets now get some info about the app
    if ($selectedApps)
    {
        Write-CMTraceLog -Message "$($selectedApps.count) apps selected"
        foreach ($app in $selectedApps)
        {
            $appWithoutLazyProperties = Get-CimInstance -CimSession $cimSession -Namespace "Root\SMS\Site_$($SiteCode)" -Query "SELECT * FROM SMS_Application WHERE CI_ID = '$($app.CI_ID)'"
            $fullApp = $appWithoutLazyProperties | Get-CimInstance -CimSession $cimSession
            
            [xml]$appXmlContent = $fullApp.SDMPackageXML

            if (-not ($null -eq $appXmlContent.AppMgmtDigest.Resources.Icon.Id) ) 
            {
                $IconPath = '{0}\{1}.png' -f $ExportFolderIcons, $appXmlContent.AppMgmtDigest.Resources.Icon.Id
            
                try 
                {
                    $icon = [Convert]::FromBase64String($appXmlContent.AppMgmtDigest.Resources.Icon.Data)
                    [System.IO.File]::WriteAllBytes($IconPath, $icon)                
                }
                catch 
                {
                    Write-CMTraceLog -Message "Icon Export failed" -Severity Error
                    Write-CMTraceLog -Message "$($_)" 
                }
            }

            # We might need to set a generic publisher
            if ([string]::IsNullOrEmpty($appXmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Publisher))
            {
                $appPublisher = $PublisherIfNoneIsSet
            }
            else 
            {
                $appPublisher = $appXmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Publisher
            }

            # We might need to set a generic description
            if ([string]::IsNullOrEmpty($appXmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Description))
            {
                $appDescription = $DescriptionIfNoneIsSet
            }
            else 
            {
                $appDescription = $appXmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Description
            }


            Write-CMTraceLog -Message "Getting info of App: $($appXmlContent.AppMgmtDigest.Application.title.'#text')"
            $tmpApp = [PSCustomObject]@{
                AppImportToIntunePossible = "Yes"
                AllChecksPassed = 'Yes'
                LogicalName = $appXmlContent.AppMgmtDigest.Application.LogicalName
                Name = $appXmlContent.AppMgmtDigest.Application.title.'#text'
                NameSanitized = Get-SanitizedString -String ($appXmlContent.AppMgmtDigest.Application.title.'#text')
                CIVersion = $fullApp.CIVersion
                SoftwareVersion = $fullApp.SoftwareVersion
                CI_ID = $fullApp.CI_ID
                CI_UniqueID = $fullApp.CI_UniqueID
                DeploymentTypesTotal = $fullApp.NumberOfDeploymentTypes
                IsDeployed = $fullApp.IsDeployed
                IsSuperseded = $fullApp.IsSuperseded
                IsSuperseding = $fullApp.IsSuperseding
                Description = $appDescription
                Tags = $appXmlContent.AppMgmtDigest.Application.DisplayInfo.Tags.Tag
                Publisher = $appPublisher
                ReleaseDate = $appXmlContent.AppMgmtDigest.Application.DisplayInfo.Info.ReleaseDate
                InfoUrl = $appXmlContent.AppMgmtDigest.Application.DisplayInfo.Info.InfoUrl
                IconId = $appXmlContent.AppMgmtDigest.Resources.Icon.Id
                IconPath = $IconPath
                DeploymentTypes = $null
                CheckTotalDeploymentTypes = "OK"
                CheckIsSuperseded = "OK"
                CheckIsSuperseding = "OK"
                CheckTags = "OK"
                CheckTechnology = "OK"
                CheckLogonRequired = "OK"
                CheckAllowUserInteraction = "OK"
                CheckProgramVisibility = "OK"
                CheckUnInstallSetting = "OK" #":  "SameAsInstall",
                CheckNoUninstallCommand = "OK"
                CheckRepairCommand = "OK"
                CheckRepairFolder = "OK"
                CheckSourceUpdateProductCode = "OK"
                CheckRebootBehavior = "OK"
                CheckHasDependency = "OK"
                CheckExeToCloseBeforeExecution = "OK"
                CheckCustomReturnCodes = "OK"
                CheckRequirements = "OK"
                CheckRulesWithGroups = "OK"
                CheckRulesWithOr = "OK"                
                
            }

            Write-CMTraceLog -Message "Getting deploymenttype info for app"
            $appDeploymenTypesList = [System.Collections.Generic.List[pscustomobject]]::new()
            if ($fullApp.NumberOfDeploymentTypes -ge 1)
            {
                foreach ($deploymentType in $appXmlContent.AppMgmtDigest.DeploymentType) 
                {
                    if ($deploymentType.Installer.Contents.Content.Location.Count -gt 1) 
                    {
                        $installLocation = $deploymentType.Installer.Contents.Content.Location[0] -replace '\\$'
                        $uninstallLocation = $deploymentType.Installer.Contents.Content.Location[1] -replace '\\$'
                    }
                    else 
                    {
                        $installLocation = $deploymentType.Installer.Contents.Content.Location -replace '\\$'
                        $uninstallLocation = $deploymentType.Installer.Contents.Content.Location -replace '\\$'
                    }
                
                    # counting different XML node types with this method
                    $requirementsCount = 0
                    $deploymentType.Requirements.Rule | ForEach-Object {$requirementsCount++}

                    # Check for dependencies
                    if ([string]::IsNullOrEmpty($deploymentType.Dependencies.DeploymentTypeRule.DeploymentTypeExpression.Operands.DeploymentTypeIntentExpression.DeploymentTypeApplicationReference))
                    {
                        $hasDependency = $false    
                    }
                    else 
                    {
                        $hasDependency = $true
                    }

                    # Check for executales that must be closed
                    $appDeploymenTypesExeList = [System.Collections.Generic.List[pscustomobject]]::new()
                    If([string]::IsNullOrEmpty($deploymentType.Installer.CustomData.InstallProcessDetection))
                    {
                        # no executables set for deploymentype
                    }
                    else 
                    {
                        foreach ($exe in $deploymentType.Installer.CustomData.InstallProcessDetection.ProcessList.ProcessInformation)
                        {
                            $tmpExeItem = [PSCustomObject]@{
                                Name = $exe.Name
                                DisplayName = $exe.DisplayInfo.info.DisplayName
                            }
                            $appDeploymenTypesExeList.Add($tmpExeItem)
                        }
                    }

                    # Add ExitCodes
                    $appDeploymenTypesCustomExitCodeList = [System.Collections.Generic.List[pscustomobject]]::new()
                    foreach ($exitCode in $deploymentType.Installer.CustomData.ExitCodes.ExitCode) 
                    {
                        if ($exitCode.Code -notin (0,1707,3010,1641,1618)) # Those codes are also set in Intune by default
                        {
                            $tmpExeItem = [PSCustomObject]@{
                                Code = $exitCode.Code
                                Class = $exitCode.Class
                            }
                            $appDeploymenTypesCustomExitCodeList.Add($tmpExeItem)
                        }                    
                    }

                    #Logon required
                    switch (($deploymentType.Installer.InstallAction.args.arg | Where-Object {$_.Name -eq 'RequiresLogOn'}).'#text') 
                    {
                        'True' { $LogonRequired = 'Only when a user is logged on' }
                        'False' { $LogonRequired = 'Only when no user is logged on' }
                        $null { $LogonRequired = 'Whether or not a user is logged on' }
                        default { $LogonRequired = 'Whether or not a user is logged on' }
                    }

                    #Extract file info for win32apputil -s parameter
                    # Search the Install Command line for other the installer type
                    $dtInstallCommandLine = $deploymentType.Installer.CustomData.InstallCommandLine
                    $Matches = $null
                    if ($dtInstallCommandLine -match "powershell" -and $dtInstallCommandLine -match "\.ps1") 
                    {
                        $null = $dtInstallCommandLine -match '[\s"\\]([^"\\]*\.(ps1))'
                        $intuneWinAppUtilSetupFile = $Matches[1]
                        $Matches = $null
                    }
                    elseif ($dtInstallCommandLine -match "\.exe" -and $dtInstallCommandLine -notmatch "msiexec" -and $dtInstallCommandLine -notmatch "cscript" -and $dtInstallCommandLine -notmatch "wscript") 
                    {
                        $null = $dtInstallCommandLine -match '[\s"\\]([^"\\]*\.(exe))'
                        $intuneWinAppUtilSetupFile = $Matches[1]
                        $Matches = $null
                    }
                    elseif ($dtInstallCommandLine -match "\.msi") 
                    {
                        $null = $dtInstallCommandLine -match '[\s"\\]([^"\\]*\.(msi))'
                        $intuneWinAppUtilSetupFile = $Matches[1]
                        $Matches = $null
                    }
                    elseif ($dtInstallCommandLine -match "\.vbs") 
                    {
                        $null = $dtInstallCommandLine -match '[\s"\\]([^"\\]*\.(vbs))'
                        $intuneWinAppUtilSetupFile = $Matches[1]
                        $Matches = $null
                    }
                    elseif ($dtInstallCommandLine -match "\.cmd") 
                    {
                        $null = $dtInstallCommandLine -match '[\s"\\]([^"\\]*\.(cmd))'
                        $intuneWinAppUtilSetupFile = $Matches[1]
                        $Matches = $null
                    }
                    elseif ($dtInstallCommandLine -match "\.bat") 
                    {
                        $null = $dtInstallCommandLine -match '[\s"\\]([^"\\]*\.(bat))'
                        $intuneWinAppUtilSetupFile = $Matches[1]
                        $Matches = $null
                    }
                    else 
                    {
                        $intuneWinAppUtilSetupFile = $null
                        Write-CMTraceLog -Message "IntuneWinAppUtilSetupFile could not been determined. App cannot be imported into Intune." -Severity Error
                    }  
                    
                    
                $rebootBehaviorConversionHash = @{
                    "BasedOnExitCode" = "basedOnReturnCode" # IntuneName: Determine behavior based on return codes
                    "NoAction" = 'suppress' # IntuneName: No specific action
                    "ProgramReboot" = "allow" # IntuneName:App install may force a device restart
                    "ForceReboot" = 'force' # IntuneName: Intune will force a mandatory device restart
                }

                    $tmpAppDeploymentType = [PSCustomObject]@{
                        LogicalName = $deploymentType.LogicalName
                        Name = $deploymentType.Title.InnerText
                        NameSanitized = Get-SanitizedString -String ($deploymentType.Title.InnerText)
                        Technology = $deploymentType.Installer.Technology
                        ExecutionContext = ($deploymentType.Installer.InstallAction.args.arg | Where-Object {$_.Name -eq 'ExecutionContext'}).'#text' # No Intune support for any
                        LogonRequired = $LogonRequired # No Intune support
                        AllowUserInteraction = if (($deploymentType.Installer.InstallAction.args.arg | Where-Object {$_.Name -eq 'RequiresUserInteraction'}).'#text' -ieq 'true'){$true}else{$false} # No Intune support for true
                        ProgramVisibility = ($deploymentType.Installer.InstallAction.args.arg | Where-Object {$_.Name -eq 'UserInteractionMode'}).'#text'
                        InstallContent = $installLocation
                        InstallCommandLine = $dtInstallCommandLine
                        IntuneWinAppUtilSetupFile = $intuneWinAppUtilSetupFile
                        UnInstallSetting = $deploymentType.Installer.CustomData.UnInstallSetting
                        UninstallContent = $uninstallLocation # No Intune support
                        UninstallCommandLine = $deploymentType.Installer.CustomData.UninstallCommandLine
                        RepairCommand = $deploymentType.Installer.CustomData.RepairCommandLine # No Intune support
                        RepairFolder = $deploymentType.Installer.CustomData.RepairFolder # No Intune support
                        RunAs32Bit = ($deploymentType.Installer.InstallAction.Args.arg | Where-Object {$_.name -eq 'RunAs32Bit'}).'#text' # No Intune support
                        SourceUpdateProductCode = $deploymentType.Installer.CustomData.SourceUpdateProductCode # No Intune support
                        RebootBehavior = ($deploymentType.Installer.InstallAction.args.arg | Where-Object {$_.Name -eq 'PostInstallBehavior'}).'#text'
                        RebootBehaviorIntune = $rebootBehaviorConversionHash[(($deploymentType.Installer.InstallAction.args.arg | Where-Object {$_.Name -eq 'PostInstallBehavior'}).'#text')]
                        ExecuteTime = $deploymentType.Installer.CustomData.ExecuteTime
                        MaxExecuteTime = $deploymentType.Installer.CustomData.MaxExecuteTime
                        RequirementsCount = $requirementsCount
                        HasDependency = $hasDependency
                        ExeToCloseBeforeExecution = $appDeploymenTypesExeList # No Intune support
                        CustomReturnCodes = $appDeploymenTypesCustomExitCodeList
                        Requirements = $null
                        DetectionRules = $null

                    }

                    # In case we do not have a content path and instead the install or uninstall points to a share, correct that
                    if($tmpAppDeploymentType.InstallCommandLine -match '(\\\\[^ ]*)')
                    {
                        $tmpAppDeploymentType.InstallContent = ($tmpAppDeploymentType.InstallCommandLine -split ' ', 2)[0] | Split-Path -Parent   
                        $tmpAppDeploymentType.InstallCommandLine = $tmpAppDeploymentType.InstallCommandLine -replace ([regex]::Escape($tmpAppDeploymentType.InstallContent)) -replace '^\\'
                    }

                    if($tmpAppDeploymentType.UninstallCommandLine -match '(\\\\[^ ]*)')
                    {
                        $tmpAppDeploymentType.UninstallContent = ($tmpAppDeploymentType.UninstallCommandLine -split ' ', 2)[0] | Split-Path -Parent
                        $tmpAppDeploymentType.UninstallCommandLine = $tmpAppDeploymentType.UninstallCommandLine -replace ([regex]::Escape($tmpAppDeploymentType.UninstallContent)) -replace '^\\'
                    }

                    # getting requirements
                    if ($requirementsCount -gt 0)
                    {
                        #Write-CMTraceLog -Message "The script does only support the operating system requirement. Any other requirements need to be set manually in Intune!" -Severity Warning

                        $RequirementRulesList = [System.Collections.Generic.List[pscustomobject]]::new()
                        foreach ($reqRule in $deploymentType.Requirements.Rule)
                        {

                            If (!([string]::IsNullOrEmpty($reqRule.OperatingSystemExpression))) 
                            {
                                $Operator = $deploymentType.Requirements.Rule.OperatingSystemExpression.Operator
                                [array]$OSes = $deploymentType.Requirements.Rule.OperatingSystemExpression.Operands.RuleExpression.RuleId
                                $RequirementRulesList.Add([pscustomobject]@{
                                    Type = 'OperatingSystem'
                                    Operator = $Operator
                                    OSes = $OSes  
                                    Text = $reqRule.Annotation.DisplayName.Text
                                })                                
                            }
                            else
                            {
                                $RequirementRulesList.Add([pscustomobject]@{
                                    Type = 'NotImplemented'
                                    Operator = $null
                                    OSes = $null
                                    Text = $reqRule.Annotation.DisplayName.Text
                                }) 
                            }
                        }
                        $tmpAppDeploymentType.Requirements = $RequirementRulesList

                    }

                    $appDeploymenTypeDetectionList = [System.Collections.Generic.List[pscustomobject]]::new()
                    
                    $tmpDetectionItem = [PSCustomObject]@{
                        Type = $null
                        TypeIntune = $null
                        ScriptType = $null
                        ScriptFilePath = $null
                        RunAs32BitOn64BitSystem = $null
                        RulesWithGroups = $false
                        RulesWithOr = $false                          
                        Rules = $null
                        RulesFlat = $null
                

                    }

                    # Each deployment type has its own detection. Lets get those
                    Switch ($deploymentType.Installer.DetectAction.Provider)
                    {
                        'Script' 
                        {

                            <#
                            $deploymentType.Installer.DetectAction.Args
                            Name             Type    #text
                            ----             ----    -----
                            ExecutionContext String  System
                            ScriptType       Int32   0
                            ScriptBody       String  if((Test-Path 'HKLM:\SOFTWARE\_Custom\Installed\Notepad++') {Write-Host 'Installed'}
                            RunAs32Bit       Boolean true
                            
                            #>

                            Switch ($deploymentType.Installer.DetectAction.Args.Arg[1].'#text') 
                            {
                                0 { $dmScriptType = 'Powershell'; $dmScriptSuffix = 'ps1' }
                                1 { $dmScriptType = 'VBScript'; $dmScriptSuffix = 'vbs'  }
                                2 { $dmScriptType = 'JScript'; $dmScriptSuffix = 'js'  }
                            }

                            if ([string]::IsNullOrEmpty($deploymentType.Installer.DetectAction.Args.Arg[3].'#text'))
                            {
                                $runAs32BitOn64BitSystem = $false   
                            }
                            else 
                            {
                                $runAs32BitOn64BitSystem = $true
                            }

                            $scriptFilePath = '{0}\{1}.{2}' -f $ExportFolderScripts, $deploymentType.LogicalName, $dmScriptSuffix
                            $deploymentType.Installer.DetectAction.Args.Arg[2].'#text' | Out-File $scriptFilePath -Force -Encoding unicode

                            $tmpDetectionItem.Type = 'Script'
                            $tmpDetectionItem.TypeIntune = 'AppDetectionRuleScript'
                            $tmpDetectionItem.ScriptType = $dmScriptType
                            $tmpDetectionItem.ScriptFilePath = $scriptFilePath #-replace [regex]::Escape($ExportFolder) # Keep the entry relative
                            $tmpDetectionItem.RunAs32BitOn64BitSystem = $runAs32BitOn64BitSystem


                        }
                        'MSI' 
                        {

                            $tmpDetectionItem.Type = 'MSI'
                            $tmpDetectionItem.TypeIntune = 'AppDetectionRuleMSI'
                            # Code missind to get MSI detection rules

                        }
                        'Local' 
                        {

                            $tmpDetectionItem.Type = 'Enhanced'

                            [xml]$edmData = $deploymentType.Installer.DetectAction.args.arg[1].'#text'
                            $tmpDetectionItem.Rules = Get-FilterEDM -EnhancedDetectionMethods $edmData -RuleExpression $edmData.EnhancedDetectionMethod.Rule.Expression
                            $tmpDetectionItem.RulesFlat = Get-FilterEDM -EnhancedDetectionMethods $edmData -RuleExpression $edmData.EnhancedDetectionMethod.Rule.Expression -FlatDetectionList
                            $tmpDetectionItem.RulesWithGroups = $deploymentType.Installer.DetectAction.args.arg[1].'#text' -imatch ([regex]::Escape('<Expression IsGroup="true">'))
                            $tmpDetectionItem.RulesWithOr = $tmpDetectionItem.RulesFlat.RulesWithOR

                            $tmpRulesWithOr = $null
                            $tmpRulesWithOr = $tmpDetectionItem.RulesFlat | Where-Object {$_.RulesWithOR -eq $true}
                            if ($tmpRulesWithOr)
                            {
                                $tmpDetectionItem.RulesWithOr = $true
                                # Lets remove the RulesWithOr sub object
                                $tmpDetectionItem.RulesFlat = $tmpDetectionItem.RulesFlat | Where-Object {$_.RulesWithOr -eq $null}
                            }

                        }
                        Default
                        {
                            $tmpDetectionItem = [PSCustomObject]@{
                                Type = 'Unknown'

                            }                        
                        }
                    }                    

                    $appDeploymenTypeDetectionList.add($tmpDetectionItem)
                    $tmpAppDeploymentType.DetectionRules = $appDeploymenTypeDetectionList
                    $appDeploymenTypesList.add($tmpAppDeploymentType)
                }
            }

            $tmpApp.DeploymentTypes = $appDeploymenTypesList


            # Lets now check Intune compatability
            # DeploymentTypesTotal
            if ($tmpApp.DeploymentTypesTotal -gt 1)
            {
                $tmpApp.CheckTotalDeploymentTypes = "FAILED: App has more than one deployment type. This is not supported by Intune. And the script currently does not support the creation of multiple apps, one for each deployment type. Copy the app and remove all deployment types except one. Then run the script again."
                $tmpApp.AppImportToIntunePossible = 'No'
                $tmpApp.AllChecksPassed = 'No'
            }

            # IsSuperseded
            if ($tmpApp.IsSuperseded -ieq 'True')
            {
                $tmpApp.CheckIsSuperseded = "FAILED: App is superseded. While Intune supports supersedence the script does not support supersedence right now. The app can still be created but the setting is ignored."
                $tmpApp.AllChecksPassed = 'No'
            }

            # IsSuperseding
            if ($tmpApp.IsSuperseding -ieq 'True')
            {
                $tmpApp.CheckIsSuperseding = "FAILED: App is superseding. While Intune supports supersedence the script does not support supersedence right now. The app can still be created but the setting is ignored."
                $tmpApp.AllChecksPassed = 'No'
            }

            # Tags
            if($tmpApp.Tags)
            {
                $tmpApp.CheckTags = "FAILED: Tags are not supported by the script right now. The app can still be created but the setting is ignored."
                $tmpApp.AllChecksPassed = 'No'
            }

            # Technology
            if($tmpApp.deploymentTypes[0].Technology -ne 'script')
            {
                $tmpApp.CheckTechnology = "FAILED: App technology: `"$($tmpApp.deploymentTypes[0].Technology)`" The app cannot be created. Only 'script' is supported as technology by the script at the moment."
                $tmpApp.AppImportToIntunePossible = 'No'
                $tmpApp.AllChecksPassed = 'No'
            }

            # LogonRequired
            if($tmpApp.deploymentTypes[0].LogonRequired -ine 'Whether or not a user is logged on')
            {
                $tmpApp.CheckLogonRequired = "FAILED: LogonRequired. `"$($tmpApp.deploymentTypes[0].LogonRequired)`" Intune does not support a LogonRequired setting. The only supported method would be: 'Whether or not a user is logged on'. The app can still be created but the setting is ignored."
                $tmpApp.AllChecksPassed = 'No'
            }

            # AllowUserInteraction
            if($tmpApp.deploymentTypes[0].AllowUserInteraction -ne $false)
            {
                $tmpApp.CheckAllowUserInteraction = "FAILED: There is no Intune option to AllowUserInteraction. The app can still be created but the setting is ignored. Consider the use of ServceUI.exe or similar method to allow user interaction."
                $tmpApp.AllChecksPassed = 'No'
            }

            # ProgramVisibility
            if (-Not ([string]::IsNullOrEmpty($tmpApp.deploymentTypes[0].ProgramVisibility)))
            {
                if($tmpApp.deploymentTypes[0].ProgramVisibility -inotmatch '(Normal|Hidden)')
                {
                    # "ProgramVisibility":  "Normal", "Hidden", "System", "SystemHidden"
                    $tmpApp.CheckProgramVisibility = "FAILED: ProgramVisibility: `"$($tmpApp.deploymentTypes[0].ProgramVisibility)`" There is no Intune option for ProgramVisibility and will always run apps hidden. The app can still be created but the setting is ignored."
                    $tmpApp.AllChecksPassed = 'No'
                }
            }

            # UnInstallSetting
            if($tmpApp.deploymentTypes[0].UnInstallSetting -ine "SameAsInstall")
            {
                $tmpApp.CheckUnInstallSetting = "FAILED: The uninstall content is not the same as the install content. Intune does not support different install and uninstall contens. The app can still be created but the setting is ignored."
                $tmpApp.AllChecksPassed = 'No'
            }

            # NoUninstallCommand
            if([string]::IsNullOrEmpty($tmpApp.deploymentTypes[0].UninstallCommandLine))
            {
                $tmpApp.CheckNoUninstallCommand = "FAILED: The uninstall command is missing. Intune requires an uninstall command. The app cannot be created."
                $tmpApp.AppImportToIntunePossible = 'No'
                $tmpApp.AllChecksPassed = 'No'
            }

            # RepairCommand
            if(-Not ([string]::IsNullOrEmpty($tmpApp.deploymentTypes[0].RepairCommand)))
            {
                $tmpApp.CheckRepairCommand = "FAILED: There is no Intune option for RepairCommand. The app can still be created but the setting is ignored."
                $tmpApp.AllChecksPassed = 'No'
            }

            # RepairFolder
            if (-Not ([string]::IsNullOrEmpty($tmpApp.deploymentTypes[0].SourceUpdateProductCode)))
            {
                $tmpApp.CheckSourceUpdateProductCode = "FAILED: There is no Intune option for SourceUpdateProductCode. The app can still be created but the setting is ignored."
                $tmpApp.AllChecksPassed = 'No'
            }

            # RebootBehavior
            <#
            if(-Not ([string]::IsNullOrEmpty($tmpApp.RebootBehavior)))
            {
                # "RebootBehavior":  "NoAction", "Always", "Promt", "AutoClose", "AutoCloseAndReboot", "Custom", "NotSupported"
                # Device restart behavior. Possible values are: basedOnReturnCode, allow, suppress, force.
                $tmpApp.CheckRebootBehavior = "There is no Intune option for RebootBehavior. The app can still be created but the setting is ignored."
            }
            #>

            # HasDependency
            if($tmpApp.HasDependency -eq $true)
            {
                $tmpApp.CheckHasDependency = "FAILED: App has dependencies. While Intune supports dependencies, the script does not support it yet. The app can still be created but the setting is ignored."
                $tmpApp.AllChecksPassed = 'No'
            }

            # ExeToCloseBeforeExecution
            if($tmpApp.deploymentTypes[0].ExeToCloseBeforeExecution)
            {
                $tmpApp.CheckExeToCloseBeforeExecution = "FAILED: Intune does not support to close processes before running the installation. The app can still be created but the setting is ignored."
                $tmpApp.AllChecksPassed = 'No'
            }

            # CustomReturnCodes
            if($tmpApp.deploymentTypes[0].CustomReturnCodes)
            {
                $tmpApp.CheckCustomReturnCodes = "FAILED: The app has custom return codes set. The script does not support the creation of custom return codes yet. The app can still be created but the setting is ignored."
                $tmpApp.AllChecksPassed = 'No'
            }

            # Requirements
            if($tmpApp.deploymentTypes[0].Requirements)
            {
                $tmpApp.CheckRequirements = "FAILED: The app has requirements set. Currently the script will only set the minimum required requirements in Intune and cannot convert ConfigMgr requirements. The app can still be created but the setting is ignored."
                $tmpApp.AllChecksPassed = 'No'
            }

            # RulesWithGroups
            if($tmpApp.deploymentTypes[0].DetectionRules.RulesWithGroups)
            {
                $tmpApp.CheckRulesWithGroups = "FAILED: The app has detection rules with groups. Intune does not support grouping, but the app can still be created with a flat list of detection rules. Consider the use of a detection script with the same check logic instead."
                $tmpApp.AllChecksPassed = 'No'
            }

            # RulesWithOr
            if($tmpApp.deploymentTypes[0].DetectionRules.RulesWithOr)
            {
                $tmpApp.CheckRulesWithOr = "FAILED: The app has detection rules with the OR operator. Intune does not support the or operator for detection rules, but the app can still be created with a flat list of detection rules. Consider the use of a detection script with the same check logic instead."
                $tmpApp.AllChecksPassed = 'No'
            }



            $appfileFullName = '{0}\{1}.xml' -f $ExportFolderAppDetails, $tmpApp.LogicalName
            Write-CMTraceLog -Message "Export app to: `"$($appfileFullName)`" to be able to work with them later in PowerShell"
            $tmpApp | Export-Clixml -Path $appfileFullName -Depth 100

            $appfileFullName = '{0}\{1}.json' -f $ExportFolderAppDetails, $tmpApp.LogicalName
            write-CMTraceLog -Message "Export app to: `"$($appfileFullName)`" for easy reading in a text editor"
            $tmpApp | ConvertTo-Json -Depth 100 | Out-File -FilePath $appfileFullName -Encoding unicode
            
            $appOutObj.Add($tmpApp)

        }
    }

    # Show one app in json format as a result
    #$appOutObj[0] | ConvertTo-Json -Depth 20
    Write-CMTraceLog -Message "Export $($appOutObj.Count) app/s to different formats"
        
    $appfileFullName = '{0}\AllAps.xml' -f $ExportFolderAppDetails
    Write-CMTraceLog -Message "Export all apps to: `"$($appfileFullName)`" to be able to work with them later in this script even on other devices"
    $appOutObj | Export-Clixml -Path $appfileFullName -Depth 100

    $appfileFullName = '{0}\AllAps.json' -f $ExportFolderAppDetails
    Write-CMTraceLog -Message "Export all apps to: `"$($appfileFullName)`" for easy reading in a text editor"    
    $appOutObj | ConvertTo-Json -Depth 100 | Out-File -FilePath $appfileFullName -Encoding unicode

    $appfileFullName = '{0}\AllAps.csv' -f $ExportFolderAppDetails
    Write-CMTraceLog -Message "Export all apps to: `"$($appfileFullName)`" to be able to analyze them in Excel"
    $appOutObj | Select-Object -Property * -ExcludeProperty DeploymentTypes, IconId, IconPath | Export-Csv $appfileFullName -NoTypeInformation
}
#endregion


#region Win32AppCreation 
if ($scriptMode -in ('CreateIntuneWinFiles','CreateIntuneWinFilesAndUploadToIntune','RunAllActions'))
{

    Write-CMTraceLog -Message "Start creating Win32AppContent files for Intune"
    if (-not (Test-Path "$($ExportFolder)\AppDetails\AllAps.xml"))
    {
        Write-CMTraceLog -Message "File not found: `"$($ExportFolder)\AppDetails\AllAps.xml`". Run the script with the GetConfigMgrAppInfo or GetConfigMgrAppInfoAndAnalyze switch" -Severity Error
        Exit 1
    }

    [array]$appInObj = Import-Clixml -Path "$($ExportFolder)\AppDetails\AllAps.xml"
    Write-CMTraceLog -Message "Open Out-GridView for app selection"
    $ogvTitle = "Select the apps you want to create content for"
    [array]$selectedAppsLimited = $appInObj | Select-Object -Property * -ExcludeProperty CIUniqueID, DeploymentTypes, IconId, IconPath | Out-GridView -OutputMode Multiple -Title $ogvTitle
    if ($selectedAppsLimited.count -eq 0)
    {
        Write-CMTraceLog -Message "Nothing selected. Will end script!"
        Exit
    }

    Write-CMTraceLog -Message "Total apps to create content for: $($selectedAppsLimited.count)"


    # Lets check if the IntuneWinAppUtil.exe is present
    $contentPrepToolFullName = '{0}\IntuneWinAppUtil.exe' -f $ExportFolderTools
    if (Test-Path $contentPrepToolFullName)
    {
        Write-CMTraceLog -Message "IntuneWinAppUtil.exe already present. No need to download"
    }
    else 
    {    
        try 
        {
            Write-CMTraceLog -Message "Will try to download IntuneWinAppUtil.exe"
            Invoke-WebRequest -UseBasicParsing -Method Get -Uri $Win32ContentPrepToolUri -OutFile $contentPrepToolFullName -ErrorAction SilentlyContinue

            if (-not (Test-Path $contentPrepToolFullName))
            {
                Write-CMTraceLog -Message "IntuneWinAppUtil.exe download failed" -Severity Error
            }
        }
        catch 
        {
            Write-CMTraceLog -Message "IntuneWinAppUtil.exe download failed" -Severity Error
            Write-CMTraceLog -Message "$($_)"
            Write-CMTraceLog -Message "You can also download the tool to: `"$ExportFolderTools`" manully"
            Write-cmTraceLog -Message "From: `"$Win32ContentPrepToolUri`""
            Exit 1
        }
    }
    # download of the IntuneWinAppUtil.exe is done

    foreach($configMgrApp in $appInObj.Where({$_.CI_ID -in $selectedAppsLimited.CI_ID}))
    {
        if ($configMgrApp.AppImportToIntunePossible -ine 'Yes')
        {
            Write-CMTraceLog -Message 'App cannot be imported into Intune. Will be skipped.' -Severity Warning
            Continue
        }

        $intuneWinAppUtilCommand = $configMgrApp.DeploymentTypes[0].IntuneWinAppUtilSetupFile
        $intuneWinAppUtilContentFolder = $configMgrApp.DeploymentTypes[0].InstallContent
        $intuneWinAppUtilOutputFolder = '{0}\{1}' -f $ExportFolderWin32Apps, $configMgrApp.LogicalName

        if (-NOT (Test-Path $intuneWinAppUtilOutputFolder))
        {
            New-Item -ItemType Directory -Path $intuneWinAppUtilOutputFolder -Force | Out-Null   
        }

        try 
        {
            $arguments = @(
                '-s'
                "`"$intuneWinAppUtilCommand`""
                '-c'
                "`"$intuneWinAppUtilContentFolder`""
                '-o'
                "`"$intuneWinAppUtilOutputFolder`""
                '-q'
            )

            $ProcessStartInfo = New-Object System.Diagnostics.ProcessStartInfo
            $ProcessStartInfo.FileName = $contentPrepToolFullName
            $ProcessStartInfo.RedirectStandardError = $true
            $ProcessStartInfo.RedirectStandardOutput = $true
            $ProcessStartInfo.UseShellExecute = $false
            $ProcessStartInfo.Arguments = $arguments
            $startProcess = New-Object System.Diagnostics.Process
            $startProcess.StartInfo = $ProcessStartInfo
            $startProcess.Start() | Out-Null
            $startProcess.WaitForExit()
            $stdout = $startProcess.StandardOutput.ReadToEnd()
            $stderr = $startProcess.StandardError.ReadToEnd()

            $intunewinLogName = '{0}\{1}.log' -f $intuneWinAppUtilOutputFolder, ($configMgrApp.DeploymentTypes[0].LogicalName)
            If($stdout -imatch 'File (?<filepath>.*) has been generated successfully')
            {
                $intuneWinFullName = $Matches.filepath -replace "'" -replace '"'
                $newName = '{0}.intunewin' -f $configMgrApp.DeploymentTypes[0].LogicalName
                $intuneWinFullNameFinal = '{0}\{1}' -f ($intuneWinFullName | Split-Path -Parent), $newName
                
                if (Test-Path $intuneWinFullNameFinal)
                {
                    Remove-Item -Path $intuneWinFullNameFinal -Force
                }

                Rename-Item -Path $intuneWinFullName -NewName $newName -Force
            }
            else 
            {
                Write-CMTraceLog -Message "IntuneWinAppUtil failed to create the intunewin file." -Severity Error 
                Write-CMTraceLog -Message "More details can be found in the log here: `"$($intunewinLogName)`""
            } 

            $stdout | Out-File -FilePath $intunewinLogName -Force -Encoding unicode -ErrorAction SilentlyContinue
            $stderr | Out-File -FilePath $intunewinLogName -Append -Encoding unicode -ErrorAction SilentlyContinue

        }
        catch 
        {
            Write-CMTraceLog -Message "IntuneWinAppUtil failed to create the intunewin file." -Severity Error 
            Write-CMTraceLog -Message "More details can be found in the log here: `"$($intunewinLogName)`""
            Write-CMTraceLog -Message "$($_)"
        }
    }
}
#endregion

#region UploadToIntune
if ($scriptMode -in ('CreateIntuneWinFilesAndUploadToIntune','UploadAppsToIntune','RunAllActions'))
{
    Write-CMTraceLog -Message "Start app upload to Intune"


    # we need to extract some files
    try 
    {
        $null = Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction Stop
    }
    catch [System.Exception] 
    {
        Write-CMTraceLog -Message "An error occurred while loading System.IO.Compression.FileSystem assembly." -Severity Error
        Write-CMTraceLog -Message "Error message: $($_)"
        Exit 0
    }

    # Load apps from file
    if (-not (Test-Path "$($ExportFolder)\AppDetails\AllAps.xml"))
    {
        Write-CMTraceLog -Message "File not found: `"$($ExportFolder)\AppDetails\AllAps.xml`". Run the script with the GetConfigMgrAppInfo or GetConfigMgrAppInfoAndAnalyze switch" -Severity Error
        Exit 1
    }


    [array]$appInObj = Import-Clixml -Path "$($ExportFolder)\AppDetails\AllAps.xml"
    Write-CMTraceLog -Message "Open Out-GridView for app selection"
    $ogvTitle = "Select the apps you want to upload to Intune"
    [array]$selectedAppsLimited = $appInObj | Select-Object -Property * -ExcludeProperty CIUniqueID, DeploymentTypes, IconId, IconPath | Out-GridView -OutputMode Multiple -Title $ogvTitle
    if ($selectedAppsLimited.count -eq 0)
    {
        Write-CMTraceLog -Message "Nothing selected. Will end script!"
        Exit
    }

    Write-CMTraceLog -Message "Total apps to upload to Intune: $($selectedAppsLimited.count)"   

    # Check if the Microsoft.Graph.Authentication module is installed
    $requiredModule = 'Microsoft.Graph.Authentication'
    $moduleNotFound = $false
    try 
    {
        Import-Module -Name $requiredModule -ErrorAction Stop    
    }
    catch 
    {
        $moduleNotFound = $true
    }
    
    try 
    {
        if ($moduleNotFound)
        {
            # We might need nuget to install the module
            [version]$minimumVersion = '2.8.5.201'
            $nuget = Get-PackageProvider -ErrorAction Ignore | Where-Object {$_.Name -ieq 'nuget'} # not using -name parameter du to autoinstall question
            if (-Not($nuget))
            {   
                Write-CMTraceLog -Message "Need to install NuGet to be able to install $($requiredModule)"
                # Changed to MSI installer as the old way could not be enforced and needs to be approved by the user
                # Install-PackageProvider -Name NuGet -MinimumVersion $minimumVersion -Force
                $null = Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies -MinimumVersion $minimumVersion -Force
            }
    
            if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
            {
                Write-CMTraceLog -Message "No admin permissions. Will install $($requiredModule) for current user only"
                Install-Module $requiredModule -Force -Scope CurrentUser -ErrorAction Stop
            }
            else 
            {
                Write-CMTraceLog -Message "Admin permissions. Will install $($requiredModule) for all users"
                Install-Module $requiredModule -Force -ErrorAction Stop
            }       
    
            Import-Module $requiredModule -Force -ErrorAction Stop
        }    
    }
    catch 
    {
        Write-CMTraceLog -Message "failed to install or load module" -Severity Error
        Write-CMTraceLog -Message "$($_)"
    }

    # Connect to Graph
    Write-CMTraceLog -Message "Connecting to Graph"
    if ([string]::IsNullOrEmpty($EntraIDAppID))
    {
        Connect-MgGraph -Scopes 'DeviceManagementApps.ReadWrite.All' 
    }
    else
    {
        Connect-MgGraph -Scopes 'DeviceManagementApps.ReadWrite.All' -ClientId $EntraIDAppID -TenantId $EntraIDTenantID
    }
    
    $mgContext = Get-MgContext
    if (-NOT ($mgContext.Scopes -icontains 'DeviceManagementApps.ReadWrite.All'))
    {
        Write-Host "Not able to connect to Graph with the needed permissions: DeviceManagementApps.ReadWrite.All" -ForegroundColor Red
        Write-CMTraceLog -Message "Not able to connect to Graph with the needed permissions: DeviceManagementApps.ReadWrite.All" -Severity Error
        Exit 0
    }

    # Get the list of existing apps
    foreach($configMgrApp in $appInObj.Where({$_.CI_ID -in $selectedAppsLimited.CI_ID}))
    {

        if ($configMgrApp.AppImportToIntunePossible -ine 'Yes')
        {
            Write-CMTraceLog -Message 'App cannot be imported into Intune. Will be skipped.' -Severity Warning
            Continue
        }

        # we need the icon converted to base64
        if ([string]::IsNullOrEmpty($configMgrApp.IconPath))
        {
            Write-CMTraceLog -Message "No icon found for: `"$($configMgrApp.Name)`"" -Severity Warning
            $appIconEncodedBase64String = $null
        }
        else 
        {
            Write-CMTraceLog -Message "Converting icon to base64 for: `"$($configMgrApp.Name)`""
            $appIconEncodedBase64String = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$($configMgrApp.IconPath)"))
        }

        Write-CMTraceLog -Message "Creating Win32App object for: `"$($configMgrApp.Name)`""

        # getting reboot behavior
        if ([string]::IsNullOrEmpty($configMgrApp.DeploymentTypes[0].RebootBehaviorIntune))
        {
            $appRebootBehavior = 'basedOnReturnCode'
        }
        else 
        {
            $appRebootBehavior = $configMgrApp.DeploymentTypes[0].RebootBehaviorIntune
        }

        $appHashTable = [ordered]@{
            "@odata.type" = "#microsoft.graph.win32LobApp"
            "applicableArchitectures" = "x86,x64"
            "allowAvailableUninstall" = $false
            "description" = $configMgrApp.Description
            "developer" = ""
            "displayName" = $configMgrApp.NameSanitized
            "displayVersion" = $configMgrApp.SoftwareVersion
            "fileName" = "$('{0}.intunewin' -f $configMgrApp.DeploymentTypes[0].LogicalName)" #"fileName" = "Test.intunewin"
            "installCommandLine" = $configMgrApp.DeploymentTypes[0].InstallCommandLine #-replace '\\', '\\'
            "setupFilePath" = $configMgrApp.DeploymentTypes[0].IntuneWinAppUtilSetupFile
            "uninstallCommandLine" = $configMgrApp.DeploymentTypes[0].UninstallCommandLine #-replace '\\', '\\'
            "installExperience" = @{
                "deviceRestartBehavior" = $appRebootBehavior
                "maxRunTimeInMinutes" = if([string]::IsNullOrEmpty($configMgrApp.DeploymentTypes[0].MaxExecuteTime)) {$MaxAppRunTimeInMinutes} else {$configMgrApp.DeploymentTypes[0].MaxExecuteTime}
                "runAsAccount" = if($configMgrApp.DeploymentTypes[0].ExecutionContext -ieq 'Any'){'System'}else{$configMgrApp.DeploymentTypes[0].ExecutionContext} # System, User
            }
            "informationUrl" = $null #"https://info.contoso.local"
            "isFeatured" = $false
            "roleScopeTagIds" = @("0")
            "notes" = "Via script imported from ConfigMgr"
            "msiInformation" = $null
            "owner" = "Contoso IT"
            "privacyInformationUrl" = $null #"https://privacy.contoso.local"
            "publisher" = $configMgrApp.Publisher
            "returnCodes" = @(
                @{
                    "returnCode" = 0
                    "type" = "success"
                },
                @{
                    "returnCode" = 1707
                    "type" = "success"
                },
                @{
                    "returnCode" = 3010
                    "type" = "softReboot"
                },
                @{
                    "returnCode" = 1641
                    "type" = "hardReboot"
                },
                @{
                    "returnCode" = 1618
                    "type" = "retry"
                }
            )
            "requirementRule" = $null
            "detectionRules" = $null
            <#
            "rules" = @(
                @{
                    "@odata.type" = "#microsoft.graph.win32LobAppFileSystemRule"
                    "ruleType" = "detection"
                    "operator" = "notConfigured"
                    "check32BitOn64System" = $true
                    "operationType" = "exists"
                    "comparisonValue" = $null
                    "fileOrFolderName" = "notepad++.exe"
                    "path" = "C:\Program Files\Notepad++"
                },
                @{
                    "@odata.type" = "#microsoft.graph.win32LobAppProductCodeRule"
                    "productVersionOperator" = "notConfigured"
                    "productCode" = "{6493fd4c-9bcb-45ee-b16d-321039fb0cec}"
                    "productVersion" = $null
                }
            )
            #>
        }

        Write-CMTraceLog -Message "Creating app detection rules for: `"$($configMgrApp.Name)`""
        # we need to create a rule object for each detection Rule
        $detectionRulesListToAdd = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach($appDetectionRule in $configMgrApp.DeploymentTypes[0].DetectionRules)
        {
            switch($appDetectionRule.Type)
            {
                'Script' 
                {
                    $ScriptContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path "$($appDetectionRule.ScriptFilePath)" -Raw -Encoding UTF8)))

                    # script detection rule
                    $DetectionRule = [ordered]@{
                        "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptDetection"
                        "enforceSignatureCheck" = $false # Note: could or should be a parameter of the script or we check for a signature block in the script
                        "runAs32Bit" = $appDetectionRule.RunAs32BitOn64BitSystem
                        "scriptContent" = $ScriptContent
                    }
                    $detectionRulesListToAdd.Add($DetectionRule)
                }
                'Enhanced' 
                {
                    # We need to build the detection rule from the EDM data
                    foreach ($flatRule in $appDetectionRule.RulesFlat)
                    {

                        if ($flatRule.OperatorIntune -ieq 'NotSupported')
                        {
                            Write-CMTraceLog -Message "Rule operator not supported in Intune for: `"$($flatRule.DetectionType)`". Need to skip rule"
                            continue
                        }

                        Switch($flatRule.DetectionType)
                        {
                            'RegSetting' 
                            {

                                # Existence needs to be handled differently
                                if ($flatRule.RegDataType -ieq 'Boolean')
                                {
                                    if ($flatRule.RegData -ieq 'true')
                                    {
                                        $DetectionType = "exists"
                                    }
                                    else 
                                    {
                                        $DetectionType = "doesNotExist"
                                    }

                                    # "Existence" 
                                    $DetectionRule = [ordered]@{
                                        "@odata.type" = "#microsoft.graph.win32LobAppRegistryDetection"
                                        "operator" = "notConfigured"
                                        "detectionValue" = $null
                                        "check32BitOn64System" = $flatRule.Is32BitOn64BitSystem
                                        "keyPath" = '{0}\{1}' -f $flatRule.RegHive, $flatRule.RegKey
                                        "valueName" = $flatRule.RegValue
                                        "detectionType" = $DetectionType
                                    }
                                    $detectionRulesListToAdd.Add($DetectionRule)
                                }

                                # Other types
                                if ($flatRule.RegDataType -ieq 'String)')
                                {
                                    $DetectionType = "string"
                                }
                                elseif ($flatRule.RegDataType -imatch '(Int64|int32)') 
                                {
                                    $DetectionType = "integer"
                                }
                                elseif ($flatRule.RegDataType -ieq 'Version') 
                                {
                                    $DetectionType = "version"
                                }

                                $DetectionRule = [ordered]@{
                                    "@odata.type" = "#microsoft.graph.win32LobAppRegistryDetection"
                                    "operator" = $flatRule.OperatorIntune
                                    "detectionValue" = $flatRule.RegData
                                    "check32BitOn64System" = $flatRule.Is32BitOn64BitSystem
                                    "keyPath" = '{0}\{1}' -f $flatRule.RegHive, $flatRule.RegKey
                                    "valueName" = $flatRule.RegValue
                                    "detectionType" = $DetectionType
                                }
                                $detectionRulesListToAdd.Add($DetectionRule)
                            }
                            'FileSetting'
                            {

                                if ($flatRule.FileMethod -ieq 'Count')
                                {
                                    $DetectionRule = [ordered]@{
                                        "@odata.type" = "#microsoft.graph.win32LobAppFileSystemDetection"
                                        "operator" = "notConfigured"
                                        "detectionValue" = $null
                                        "path" = $flatRule.ParentFolder
                                        "fileOrFolderName" = $flatRule.FileName
                                        "check32BitOn64System" = $flatRule.Is32BitOn64BitSystem
                                        "detectionType" = 'exists' # "doesNotExist" is not possible in ConfigMgr
                                    }
                                    $detectionRulesListToAdd.Add($DetectionRule)
                                }
                                elseif ($flatRule.FilePropertyName -ieq 'Size') 
                                {
                                    $DetectionRule = [ordered]@{
                                        "@odata.type" = "#microsoft.graph.win32LobAppFileSystemDetection"
                                        "operator" = $flatRule.OperatorIntune
                                        "detectionValue" = ($flatRule.FileValue / 1MB).ToString() -replace ',', '.' # Has to be MB as a positive integer or 0.
                                        "path" = $flatRule.ParentFolder
                                        "fileOrFolderName" = $flatRule.FileName
                                        "check32BitOn64System" = $flatRule.Is32BitOn64BitSystem
                                        "detectionType" = "sizeInMB"
                                    }
                                    $detectionRulesListToAdd.Add($DetectionRule)
                                }
                                elseif ($flatRule.FilePropertyName -ieq 'DateModified')
                                {
                                    $DateValueString = $flatRule.FileValue -replace 'Z', '.000Z' # '2021-06-01T00:00:00Z' -> '2021-06-01T00:00:00.000Z'
                                    # needs to match this pattern '2021-06-01T00:00:00.000Z'
                                    If(-NOT ($DateValueString -match '(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)'))
                                    {
                                        Write-CMTraceLog -Message "Date value for DateModified is not in the correct format. Skipping rule." -Severity Warning
                                        Write-CMTraceLog -Message "Value: $DateValueString"
                                        Write-CMTraceLog -Message "Expected format: '2021-06-01T00:00:00.000Z'"
                                        Write-CMTraceLog -Message "Folder: $($flatRule.ParentFolder)"
                                        continue
                                    }

                                    $DetectionRule = [ordered]@{
                                        "@odata.type" = "#microsoft.graph.win32LobAppFileSystemDetection"
                                        "operator" = $flatRule.OperatorIntune
                                        "detectionValue" = $DateValueString
                                        "path" = $flatRule.ParentFolder
                                        "fileOrFolderName" = $flatRule.FileName
                                        "check32BitOn64System" = $flatRule.Is32BitOn64BitSystem
                                        "detectionType" = "modifiedDate"
                                    }
                                    $detectionRulesListToAdd.Add($DetectionRule)
                                }
                                elseif ($flatRule.FilePropertyName -ieq 'DateCreated')
                                {
                                    $DateValueString = $flatRule.FileValue -replace 'Z', '.000Z' # '2021-06-01T00:00:00Z' -> '2021-06-01T00:00:00.000Z'
                                    # needs to match this pattern '2021-06-01T00:00:00.000Z'
                                    If(-NOT ($DateValueString -match '(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)'))
                                    {
                                        Write-CMTraceLog -Message "Date value for DateCreated is not in the correct format. Skipping rule." -Severity Warning
                                        Write-CMTraceLog -Message "Value: $DateValueString"
                                        Write-CMTraceLog -Message "Expected format: '2021-06-01T00:00:00.000Z'"
                                        Write-CMTraceLog -Message "Folder: $($flatRule.ParentFolder)"
                                        continue
                                    }

                                    $DetectionRule = [ordered]@{
                                        "@odata.type" = "#microsoft.graph.win32LobAppFileSystemDetection"
                                        "operator" = $flatRule.OperatorIntune
                                        "detectionValue" = $DateValueString
                                        "path" = $flatRule.ParentFolder
                                        "fileOrFolderName" = $flatRule.FileName
                                        "check32BitOn64System" = $flatRule.Is32BitOn64BitSystem
                                        "detectionType" = "createdDate"
                                    }
                                    $detectionRulesListToAdd.Add($DetectionRule)
                                }
                                elseif ($flatRule.FilePropertyName -ieq 'Version')
                                {
                                    $DetectionRule = [ordered]@{
                                        "@odata.type" = "#microsoft.graph.win32LobAppFileSystemDetection"
                                        "operator" = $flatRule.OperatorIntune
                                        "detectionValue" = $flatRule.FileValue
                                        "path" = $flatRule.ParentFolder
                                        "fileOrFolderName" = $flatRule.FileName
                                        "check32BitOn64System" = $flatRule.Is32BitOn64BitSystem
                                        "detectionType" = "version"
                                    }
                                    $detectionRulesListToAdd.Add($DetectionRule)
                                }
                                else 
                                {
                                    Write-CMTraceLog -Message "FilePropertyName $($flatRule.FilePropertyName) is not supported. Skipping rule." -Severity Warning
                                    Write-CMTraceLog -Message "Folder: $($flatRule.ParentFolder)"
                                    Write-CMTraceLog -Message "File: $($flatRule.FileName)"
                                    Write-CMTraceLog -Message "Value: $($flatRule.FileValue)"
                                    continue
                                }
                            }
                            'MsiSetting'
                            {
                                if ($flatRule.MSIMethod -ieq "Count")
                                {
                                    $DetectionRule = [ordered]@{
                                        "@odata.type" = "#microsoft.graph.win32LobAppProductCodeDetection"
                                        "productCode" = $flatRule.MSIProductCode
                                        "productVersionOperator" = 'notConfigured'
                                        "productVersion" = $null
                                    }
                                    $detectionRulesListToAdd.Add($DetectionRule)

                                }
                                else
                                {
                                    $DetectionRule = [ordered]@{
                                        "@odata.type" = "#microsoft.graph.win32LobAppProductCodeDetection"
                                        "productCode" = $flatRule.MSIProductCode
                                        "productVersionOperator" = $flatRule.OperatorIntune
                                        "productVersion" = $flatRule.MSIPropertyName
                                    }
                                    $detectionRulesListToAdd.Add($DetectionRule)
                                }
                            }
                        }
                    }
                }
            }
        }
        $appHashTable.detectionRules = $detectionRulesListToAdd

        Write-CMTraceLog -Message "Creating basic app requirement rule to run on x86 and x64 systems with a minimum Windows 10 version of 1607"
        $requirementRule = [ordered]@{
            "applicableArchitectures" = 'All'
            "minimumSupportedWindowsRelease" = '1607'
        }

        $appHashTable.requirementRule = $requirementRule


        $appfileFullName = '{0}\{1}-Intune.json' -f $ExportFolderAppDetails, $tmpApp.LogicalName
        Write-CMTraceLog -Message "Writing Intune app details to file: `"$($appfileFullName)`""
        ($appHashTable | ConvertTo-Json -Depth 100) | Out-File -FilePath $appfileFullName -Encoding unicode

        $paramSplatting = @{
            Method = 'POST'
            Uri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
            Body = ($appHashTable | ConvertTo-Json -Depth 100)
            ContentType = "application/json; charset=utf-8"
            #verbose = $true
        }

        Write-CMTraceLog -Message "Creating Win32 app in Intune"
        Write-CMTraceLog -Message "Command $($paramSplatting['Method']) to: $($paramSplatting['Uri'])"
        $win32MobileAppRequest = Invoke-MgGraphRequest @paramSplatting
        if ($Win32MobileAppRequest.'@odata.type' -notlike "#microsoft.graph.win32LobApp") {
            Write-CMTraceLog -Message "Failed to create Win32 app using constructed body" -Severity Error 
            Write-CMTraceLog -Message "App JSON exported for analysis to: `"$appfileFullName`""
            continue
        }

        Write-CMTraceLog -Message "Request content version for Intune app"
        $paramSplatting = @{
            Method = 'POST'
            Uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($Win32MobileAppRequest.id)/microsoft.graph.win32LobApp/contentVersions"
            Body = "{}"
            #verbose = $true
        }
        Write-CMTraceLog -Message "Command $($paramSplatting['Method']) to: $($paramSplatting['Uri'])"

        $Win32MobileAppContentVersionRequest = Invoke-MgGraphRequest @paramSplatting
        if ([string]::IsNullOrEmpty($Win32MobileAppContentVersionRequest.id)) {
            Write-CMTraceLog -Message "Failed to create contentVersions resource for Win32 app" -Severity Error
            Continue
        }

        # Write the data to the app object
        $intuneWinFullName = '{0}\{1}\{2}.intunewin' -f $ExportFolderWin32Apps, $configMgrApp.LogicalName, $configMgrApp.DeploymentTypes[0].LogicalName
        Write-CMTraceLog -Message "Getting the contents of: `"$($intuneWinFullName)`""
        $intuneWinDetectionXMLFullName = '{0}\{1}\{2}.detection.xml' -f $ExportFolderWin32Apps, $configMgrApp.LogicalName ,$configMgrApp.DeploymentTypes[0].LogicalName
        $IntuneWin32AppFile = [System.IO.Compression.ZipFile]::OpenRead($intuneWinFullName)
        Write-CMTraceLog -Message "Extracting Detection.xml to read size and encryption data."
        $IntuneWin32AppFile.Entries | Where-Object {$_.Name -ieq 'Detection.xml'} | ForEach-Object {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, $intuneWinDetectionXMLFullName, $true)
        }

        Write-CMTraceLog -Message "Extracting IntunePackage.intunewin. That file will be uploaded to Intune."
        $IntunePackageFullName = '{0}\{1}\IntunePackage.intunewin' -f $ExportFolderWin32Apps, $configMgrApp.LogicalName
        $IntuneWin32AppFile.Entries | Where-Object {$_.Name -ieq 'IntunePackage.intunewin'} | ForEach-Object {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, $IntunePackageFullName, $true)
        }

        $IntunePackageIntuneWinMetadata = $IntuneWin32AppFile.Entries | Where-Object {$_.Name -ieq 'IntunePackage.intunewin'}
        # Close the file   
        $IntuneWin32AppFile.Dispose()

        [xml]$detectionXML = Get-content -Path $intuneWinDetectionXMLFullName
        $Win32AppFileBody = [ordered]@{
            "@odata.type" = "#microsoft.graph.mobileAppContentFile"
            "name" = "IntunePackage.intunewin" # from analysis this name is different than the name in the app json
            "size" = [int64]$detectionXML.ApplicationInfo.UnencryptedContentSize 
            "sizeEncrypted" = $IntunePackageIntuneWinMetadata.Length
            "manifest" = $null
            "isDependency" = $false
        }     
        
        #Write-CMTraceLog -Message ($Win32AppFileBody | ConvertTo-Json)
        Write-CMTraceLog -Message "Sending content metadata to Intune"
        $paramSplatting = @{
            Method = 'POST'
            Uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($Win32MobileAppRequest.id)/microsoft.graph.win32LobApp/contentVersions/$($Win32MobileAppContentVersionRequest.id)/files"
            Body = $Win32AppFileBody | ConvertTo-Json
            ContentType = "application/json"
        }
        Write-CMTraceLog -Message "Command $($paramSplatting['Method']) to: $($paramSplatting['Uri'])"

        $Win32MobileAppFileContentRequest = Invoke-MgGraphRequest @paramSplatting
        if ([string]::IsNullOrEmpty($Win32MobileAppFileContentRequest.id)) {
            Write-CMTraceLog -Message "Metadata send failed" -Severity Error
        }
        else 
        {
            # Wait for the Win32 app file content URI to be created
            Write-CMTraceLog -Message "Waiting for Intune service to process contentVersions/files request and to get the file URI with SAS token"
            $Win32MobileAppFilesUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($Win32MobileAppRequest.id)/microsoft.graph.win32LobApp/contentVersions/$($Win32MobileAppContentVersionRequest.id)/files/$($Win32MobileAppFileContentRequest.id)"
            $ContentVersionsFiles = Wait-ForGraphRequestCompletion -Uri $Win32MobileAppFilesUri
        }

        Write-CMTraceLog -Message "Trying to upload the file to Intune: $($IntunePackageFullName)"
        $ChunkSizeInBytes = 1024l * 1024l * 6l;
        $SASRenewalTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $FileSize = (Get-Item -Path $IntunePackageFullName).Length
        $ChunkCount = [System.Math]::Ceiling($FileSize / $ChunkSizeInBytes)
        $BinaryReader = New-Object -TypeName System.IO.BinaryReader([System.IO.File]::Open($IntunePackageFullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite))
        $Position = $BinaryReader.BaseStream.Seek(0, [System.IO.SeekOrigin]::Begin)

        $ChunkIDs = @()
        for ($Chunk = 0; $Chunk -lt $ChunkCount; $Chunk++) 
        {
            $ChunkID = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Chunk.ToString("0000")))
            $ChunkIDs += $ChunkID
            $Start = $Chunk * $ChunkSizeInBytes
            $Length = [System.Math]::Min($ChunkSizeInBytes, $FileSize - $Start)
            $Bytes = $BinaryReader.ReadBytes($Length)

            # Increment chunk to get the current chunk
            $CurrentChunk = $Chunk + 1
            Write-Progress -Activity "Uploading File to Azure Storage" -status "Uploading chunk $CurrentChunk of $ChunkCount" -percentComplete ($CurrentChunk / $ChunkCount*100)
            # if we need to renew the SAS token
            if ($SASRenewalTimer.Elapsed.TotalMinutes -gt 5) 
            {
                Write-CMTraceLog -Message "Renewing SAS token for Azure Storage blob"
                $SASRenewalUri = '{0}/renewUpload' -f $Win32MobileAppFilesUri

                $paramSplatting = @{
                    Method = 'POST'
                    Uri = $SASRenewalUri
                    ContentType = "application/json"
                }
        
                $Win32MobileAppFileContentRequest = Invoke-MgGraphRequest @paramSplatting -Verbose

                if ([string]::IsNullOrEmpty($Win32MobileAppFileContentRequest.id)) 
                {
                    Write-CMTraceLog -Message "Failed to renew SAS token for Azure Storage blob" -Severity Error
                }
                else 
                {
                    # Wait for the Win32 app file content renewal request
                    Write-Host -Message "Waiting for Intune service to process SAS token renewal request"
                    $Win32MobileAppFilesUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($Win32MobileAppRequest.id)/microsoft.graph.win32LobApp/contentVersions/$($Win32MobileAppContentVersionRequest.id)/files/$($Win32MobileAppFileContentRequest.id)"
                    $ContentVersionsFiles = Wait-ForGraphRequestCompletion -Uri $Win32MobileAppFilesUri
                }
                $SASRenewalTimer.Restart()
            }
            # renewal done

            
            $Uri = "$($ContentVersionsFiles.azureStorageUri)&comp=block&blockid=$($ChunkID)"
            $ISOEncoding = [System.Text.Encoding]::GetEncoding("iso-8859-1")
            $EncodedBytes = $ISOEncoding.GetString($Bytes)

            # We need to set the content type to "text/plain; charset=iso-8859-1" for the upload to work
            $Headers = @{
                "content-type" = "text/plain; charset=iso-8859-1"
                "x-ms-blob-type" = "BlockBlob"
            }
        
            try	
            {
                $WebResponse = Invoke-WebRequest $Uri -Method "Put" -Headers $Headers -Body $EncodedBytes -ErrorAction Stop -UseBasicParsing
            }
            catch 
            {
                Write-CMTraceLog -Message "Failed to upload chunk to Azure Storage blob. Error message: $($_.Exception.Message)" -Severity Error
            } 
        }
        Write-Progress -Completed -Activity "Uploading File to Azure Storage"
        $SASRenewalTimer.Stop()        
        $BinaryReader.Close()
     
        # Finalize the upload with the blocklist
        Write-CMTraceLog -Message "Will finalize the upload with the blocklist of uploaded blocks"
        $Uri = "$($ContentVersionsFiles.azureStorageUri)&comp=blocklist"
        $XML = '<?xml version="1.0" encoding="utf-8"?><BlockList>'
        foreach ($Chunk in $ChunkIDs) {
            $XML += "<Latest>$($Chunk)</Latest>"
        }
        $XML += '</BlockList>'

        $Headers = @{
            "Content-Type" = "application/xml"
        }
    
        try 
        {
            $WebResponse = Invoke-RestMethod -Uri $Uri -Method "Put" -Body $XML -Headers $Headers -ErrorAction Stop 
        }
        catch 
        {
            Write-CMTraceLog -Message "Failed to finalize Azure Storage blob upload. Error message: $($_.Exception.Message)" -Severity Error
        }
    
        # Commit the file with the encryption info by building the JSON object with data from the Detection.xml file
        $IntuneWinEncryptionInfo = [ordered]@{
            "encryptionKey" = $detectionXML.ApplicationInfo.EncryptionInfo.EncryptionKey
            "macKey" = $detectionXML.ApplicationInfo.EncryptionInfo.macKey
            "initializationVector" = $detectionXML.ApplicationInfo.EncryptionInfo.initializationVector
            "mac" = $detectionXML.ApplicationInfo.EncryptionInfo.mac
            "profileIdentifier" = "ProfileVersion1"
            "fileDigest" = $detectionXML.ApplicationInfo.EncryptionInfo.fileDigest
            "fileDigestAlgorithm" = $detectionXML.ApplicationInfo.EncryptionInfo.fileDigestAlgorithm
        }
        $IntuneWinFileEncryptionInfo = @{
            "fileEncryptionInfo" = $IntuneWinEncryptionInfo
        }

        # We need to commit the file
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($Win32MobileAppRequest.id)/microsoft.graph.win32LobApp/contentVersions/$($Win32MobileAppContentVersionRequest.id)/files/$($Win32MobileAppFileContentRequest.id)/commit"
        
        $paramSplatting = @{
            "Method" = 'POST'
            "Uri" = $uri
            "Body" = ($IntuneWinFileEncryptionInfo | ConvertTo-Json)
            "ContentType" = "application/json"
            #"verbose" = $true
        }

        Write-CMTraceLog -Message "Committing the file we just uploaded"
        Write-CMTraceLog -Message "Command $($paramSplatting['Method']) to: $($paramSplatting['Uri'])" 
        $Win32MobileAppFileContentCommitRequest = Invoke-MgGraphRequest @paramSplatting -Headers $headers
        Write-CMTraceLog -Message "Waiting for Intune service to process file commit request"
        $Win32MobileAppFileContentCommitRequestResult = Wait-ForGraphRequestCompletion -Uri $Win32MobileAppFilesUri

        # set commited content version
        $Win32AppFileCommitBody = [ordered]@{
            "@odata.type" = "#microsoft.graph.win32LobApp"
            "committedContentVersion" = $Win32MobileAppContentVersionRequest.id
        }

        $paramSplatting = @{
            "Method" = 'PATCH'
            "Uri" = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($Win32MobileAppRequest.id)"
            "Body" = ($Win32AppFileCommitBody | ConvertTo-Json)
            "ContentType" = "application/json"
            #"verbose" = $true
        }
        Write-CMTraceLog -Message "Setting the commited content version to the app and basically binding the file to the app"
        Write-CMTraceLog -Message "Command $($paramSplatting['Method']) to: $($paramSplatting['Uri'])"
        Invoke-MgGraphRequest @paramSplatting

    
        # if we have an icon we need to upload it
        if ($appIconEncodedBase64String)
        {
            Write-CMTraceLog -Message "Uploading icon to the new app"
            $largeIconBody = [ordered]@{
                "@odata.type" = '#microsoft.graph.win32LobApp'
                "largeIcon" = [ordered]@{
                    "type" = "image/png"
                    "value" = "$($appIconEncodedBase64String)"
                    }
                }
    
    
            $paramSplatting = @{
                "Method" = 'PATCH'
                "Uri" = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($Win32MobileAppRequest.id)"
                "Body" = ($largeIconBody | ConvertTo-Json) 
                "ContentType" = "application/json"
                #"verbose" = $true
            }
            Write-CMTraceLog -Message "Command $($paramSplatting['Method']) to: $($paramSplatting['Uri'])"
            Invoke-MgGraphRequest @paramSplatting
        }
    }      
}

Write-CMTraceLog -Message "End of script"
Write-CMTraceLog -Message "Runtime: $($stoptWatch.Elapsed.TotalMinutes) minutes"
$stoptWatch.Stop()



