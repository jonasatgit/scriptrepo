<#
.SYNOPSIS
Script to analyze ConfigMgr applications, create Intune win32 app packages and upload them to Intune.

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


This script will analyze ConfigMgr applications, create Intune win32 app packages and upload them to Intune. 

Foreword:
The script is influenced by the fantastic blog from Ben Whitmore and uses a similar logic:
https://byteben.com/bb/automatically-migrate-applications-from-configmgr-to-intune-with-the-win32app-migration-tool/
Git repository: https://github.com/byteben/Win32App-Migration-Tool
Why re-invent the wheel? I used this as a learning oppertunity to get a better understanding of the logic behind the whole migration process.
I also needed a specific and automated way to analyze ConfigMgr apps to see if a migration could be possible.

The script also contains a re-written function originally written by Paul Wetter and David O'Brian to document ConfigMgr.
I needed a slightly different approach to get the data in a way I can use for Intune. 
https://github.com/paulwetter/DocumentConfigMgrCB

The Intune upload logic comes from the Intune PowerShell samples and is slightly modified to fit the script:
https://github.com/microsoftgraph/powershell-intune-samples

Main description:
The script is devided into different actions, which can be run separately in groups or all together.
While the script was thourougly tested, it is recommended to test the script in a test environment before running it in production.
And even in production, it is recommended to run the script in a controlled manner to avoid any issues.
Make sure to properly test the script and the output of it. 

The individual script actions are:

    #1 Step1GetConfigMgrAppInfo: 
    Get information about ConfigMgr applications. Metadata for all selected apps will be exported to a folder without content.
    The script will also analyze the exported apps to mark apps with configurations not supported by the script or Intune.
    
    #2 Step2CreateIntuneWinFiles: 
    Create Intune win32 app packages exported to the export folder. 
    The script will create Intune win32 app packages from the source files of each app.
    The script will also download the Microsoft Win32 Content Prep Tool if it's not already downloaded.
    
    #3 Step3UploadAppsToIntune: 
    The script will upload selected apps to Intune.

    Actions #2 and #3 can be run together with the script mode CreateIntuneWinFilesAndUploadToIntune.

To store the individual items the script will create the following folder under the ExportFolder:
    Tools       - Contains the tools used by the script. Currently just the Microsoft Win32 Content Prep Tool.
    AppDetails  - Contains the details of the ConfigMgr applications. In JSON and XML format. JSON to be able to analyze the data in an easy way. The XML will be used by the script.
    Icons       - Contains exported icons of each ConfigMgr applications.
    Scripts     - Contains exported scripts if a ConfigMgr application is configured to use script detection types.
    Win32Apps   - Contains the exported Intune win32 app packages.

The script will create a log file in the same directory as the export and not next to the script.

Changelog:
20250619 - Fixed logic for folder detection rules.
20250604 - Fixed an Typo error by using RegKey decetion and issue with operator 'and' by detection rules, because intepred as operator 'or'.
           https://github.com/jonasatgit/scriptrepo/pull/14
           https://github.com/jonasatgit/scriptrepo/issues/13
29241217 - Fixed an issue were the detection script was always started in a 32bit process
           Added two new parameters to replace the install and uninstall command for all selected apps
           The IntunePackage.intunewin and Detection.xml file will now be deleted after the upload to save some space
20241107 - Fixed detection script encoding
           Added detection script path check
           Changed logic to determine if an app exists in Intune
           Fixed an issue with registry detection duplicates
           Added support for ConfigMgr MSI applications
           Added support for edge case with MSI applications where no MSI file is specified
20241025 - Changed the app upload logic to first connect to Graph/Intune and then show the GridView. That way the script is able to test if an app has been uploaded before.
           Added parameter to test if an app has been uploaded before. This can take some time depending on the amount of apps.
           Added additional parameters to be able to skip the consent prompt for the required Microsoft Graph API scopes/permissions to avoid problems in stricter environments.
           Added function to check if imported apps with Import-CliXML have all required properties. This is to ensure backward compatibility with older exports.
           Added export also to step3 to be able to analyze the data after the upload
           Added more errorhandling and logging to the script.
20240923 - Fixed an issue with UNC path detection in the install or uninstall command. Added path and commands to Grid-View in step2.
20240912 - Fixed an issue with the installcommand detection of ConfigMgr applications. Commands without quotes would not be detected correctly.


.PARAMETER Step1GetConfigMgrAppInfo
Get information about ConfigMgr applications.  All selected apps will be exported to a folder without content.

.PARAMETER Step2CreateIntuneWinFiles
Create Intune win32 app packages exported to the export folder.

.PARAMETER Step3UploadAppsToIntune
The script will upload selected apps to Intune.

.PARAMETER CreateIntuneWinFilesAndUploadToIntune
Run the script in CreateIntuneWinFiles and UploadAppsToIntune mode.

.PARAMETER RunAllActions
Run all actions of the script.

.PARAMETER SiteCode
The ConfigMgr site code. Required only for the first action.

.PARAMETER ProviderMachineName
The ConfigMgr SMS Provider machine name. Required only for the first action.

.PARAMETER ExportFolder
The folder where the exported content will be stored. Required for all actions.

.PARAMETER MaxAppRunTimeInMinutes
The maximum application run time in minutes. Will only be used if the deployment type has no value set.

.PARAMETER Win32ContentPrepToolUri
The URI to the Microsoft Win32 Content Prep Tool.

.PARAMETER EntraIDAppID
The AppID of the Enterprise Application in Entra ID with permission: "DeviceManagementApps.ReadWrite.All". 
Only required if the script should use a custom app instead of the default app: "Microsoft Graph Command Line Tools" AppID=14d82eec-204b-4c2f-b7e8-296a70dab67e

.PARAMETER EntraIDTenantID
The TenantID of the Enterprise Application in Entra ID.
Only required if the script should use a custom app instead of the default app.

.PARAMETER PublisherIfNoneIsSet
The publisher to use if none is set in the ConfigMgr application.
Default is "IT".

.PARAMETER DescriptionIfNoneIsSet
The description to use if none is set in the ConfigMgr application.
Default is "Imported app".

.PARAMETER OutputMode
The output mode of the script. Default is 'ConsoleAndLog'. Means that the script will output to the console and log file.
Other options are 'Console' or 'Log'.

.PARAMETER DoNotRequestScopes
If set, the script will not request the required Microsoft Graph API scopes/permissions for the script to be able to upload apps to Intune.
By default the script will request the scopes and an admin can directly consent. 
If a direct consent is not possible or already done on the Entra ID app registration, the consent prompt can be skipped with this parameter.

.PARAMETER RequiredScopes
The required Microsoft Graph API scopes/permissions for the script to be able to upload apps to Intune.
This parameter should typically not be changed. The default value is: "DeviceManagementApps.ReadWrite.All".

.PARAMETER RequiredModules
The required PowerShell modules for the script to run. Default is 'Microsoft.Graph.Authentication'. 
This parameter should typically not be changed.

.PARAMETER TestForExistingApps
If set, the script will test if an app has been uploaded before. This will be visible in the GridView just as an indicator.

.PARAMETER ReplaceInstallCommand
If set, the script will replace the install command with the provided string. This can be useful if the install command is not correct or needs to be changed for all selected apps.

.PARAMETER ReplaceUnInstallCommand
If set, the script will replace the uninstall command with the provided string. This can be useful if the uninstall command is not correct or needs to be changed for all selected apps.

.EXAMPLE
Get a Grid-View which shows all ConfigMgr applications to export metadata about them to an export folder.

Invoke-ConfigMgrAppMigrationToIntune.ps1 -Step1GetConfigMgrAppInfo -SiteCode 'P01' -ProviderMachineName 'CM01' -ExportFolder 'C:\ExportToIntune'

.EXAMPLE
Get a Grid-View of exported ConfigMgr applications and create intunewin files for them.

.\Invoke-ConfigMgrAppMigrationToIntune.ps1 -Step2CreateIntuneWinFiles -ExportFolder 'C:\ExportToIntune'

.EXAMPLE
Get a Grid-View of exported ConfigMgr applications to select and upload them to Intune.

.\Invoke-ConfigMgrAppMigrationToIntune.ps1 -Step3UploadAppsToIntune -ExportFolder 'C:\ExportToIntune'

.EXAMPLE
Get a Grid-View of exported ConfigMgr applications to select and upload them to Intune via a custom Entra ID app registration.
Entra-ID app needs to be registered in Entra ID with permission: "DeviceManagementApps.ReadWrite.All". 

.\Invoke-ConfigMgrAppMigrationToIntune.ps1 -Step3UploadAppsToIntune -ExportFolder 'C:\ExportToIntune' -EntraIDAppID '365908cc-fd28-43f7-94d2-f88a65b1ea21' -EntraIDTenantID 'contoso.onmicrosoft.com'

.EXAMPLE
Test if a win32app exists in Intune already and then get a Grid-View of exported ConfigMgr applications to select and upload them to Intune. 

.\Invoke-ConfigMgrAppMigrationToIntune.ps1 -Step3UploadAppsToIntune -ExportFolder 'C:\ExportToIntune' -TestForExistingApps

#>
[CmdletBinding(DefaultParameterSetName='Default')]
param
(
    [Parameter(Mandatory=$false, ParameterSetName='GetConfigMgrAppInfo')]
    [Switch]$Step1GetConfigMgrAppInfo,

    [Parameter(Mandatory=$false, ParameterSetName='CreateIntuneWinFiles')]
    [Switch]$Step2CreateIntuneWinFiles,

    [Parameter(Mandatory=$false, ParameterSetName='UploadAppsToIntune')]
    [Switch]$Step3UploadAppsToIntune,

    [Parameter(Mandatory=$false, ParameterSetName='CreateIntuneWinFilesAndUploadToIntune')]
    [Switch]$CreateIntuneWinFilesAndUploadToIntune,

    [Parameter(Mandatory=$false, ParameterSetName='RunAllActions')]
    [Switch]$RunAllActions,

    [Parameter(Mandatory=$true, ParameterSetName='GetConfigMgrAppInfo')]
    [Parameter(Mandatory=$true, ParameterSetName='RunAllActions')]
    [string]$Sitecode,

    [Parameter(Mandatory=$true, ParameterSetName='GetConfigMgrAppInfo')]
    [Parameter(Mandatory=$true, ParameterSetName='RunAllActions')]
    [string]$Providermachinename,

    [Parameter(Mandatory = $True)]
    [string]$ExportFolder,

    [Parameter(Mandatory = $false)]
    [int]$MaxAppRunTimeInMinutes = 60, # Maximum application run time in minutes. Will only be used if the deployment type has no value set.

    [Parameter(Mandatory = $false)]
    [string]$Win32ContentPrepToolUri = 'https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe',

    [Parameter(Mandatory=$false, ParameterSetName='UploadAppsToIntune')]
    [Parameter(Mandatory=$false, ParameterSetName='RunAllActions')]
    [string]$EntraIDAppID,

    [Parameter(Mandatory=$false, ParameterSetName='UploadAppsToIntune')]
    [Parameter(Mandatory=$false, ParameterSetName='RunAllActions')]
    [string]$EntraIDTenantID,

    [Parameter(Mandatory = $false)]
    [string]$PublisherIfNoneIsSet = 'IT',

    [Parameter(Mandatory = $false)]
    [string]$DescriptionIfNoneIsSet = 'Imported app',

    [Parameter(Mandatory = $false)]
    [ValidateSet("Console","Log","ConsoleAndLog")]
    [string]$OutputMode = 'ConsoleAndLog',

    [Parameter(Mandatory=$false)]
    [switch]$DoNotRequestScopes,

    [Parameter(Mandatory=$false)]
    [string[]]$RequiredScopes = @("DeviceManagementApps.ReadWrite.All"),

    [Parameter(Mandatory=$false)]
    [string[]]$RequiredModules = @('Microsoft.Graph.Authentication'),

    [Parameter(Mandatory=$false)]
    [switch]$TestForExistingApps,

    [Parameter(Mandatory=$false)]
    [String]$ReplaceInstallCommand = '',

    [Parameter(Mandatory=$false)]
    [String]$ReplaceUnInstallCommand = ''
)

$scriptVersion = '20241217'
$script:LogOutputMode = $OutputMode
#$script:LogFilePath = '{0}\{1}.log' -f $PSScriptRoot ,($MyInvocation.MyCommand -replace '.ps1') # Next to the script
$script:LogFilePath = '{0}\{1}.log' -f $ExportFolder ,($MyInvocation.MyCommand -replace '.ps1') # Next to the exported data. Might make more sense.

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
    Write-Warning 'The script does not run with admin privileges. In that case the script needs write access to the export folder' 
    #Read-Host -Prompt "Press any key to exit"
    #Exit 0 
}
#endregion

#region before doing anything lets check if a run modes was picked
if (-NOT ($Step1GetConfigMgrAppInfo -or $Step2CreateIntuneWinFiles -or $Step3UploadAppsToIntune -or $CreateIntuneWinFilesAndUploadToIntune -or $RunAllActions))
{
    Get-Help $($MyInvocation.MyCommand.Definition)
    break
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
        [string]$OutputMode = $script:LogOutputMode
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


#region Get-EnhancedDetectionData
<#
.SYNOPSIS
    Function to get the enhanced detection data from the ConfigMgr application detection method XML

.DESCRIPTION
    This function is a re-written version of the function Get-FilterEDM from the script DocumentConfigMgrCB.ps1 by Paul Wetter.
    Source: https://github.com/paulwetter/DocumentConfigMgrCB
    I needed a slightly different approach to get the data in a way I can use for Intune.

    The function will get the enhanced detection data from the ConfigMgr application detection method XML. 
    The function will return a list of all settings and rules for each app.
    The outobject will contain a flat list and a list with all settings and rules with group information.
    Since the script runs through all rules, the function will be called recursively and will analyze each rule.
    Parameter rulexpression will be changed with each internal call to the function to get all rules recursively.

.PARAMETER EnhancedDetectionMethods
    The full enhanced detection method XML coming from an ConfigMgr application deployment type object.

.PARAMETER RuleExpression
    The rule expression to analyze. Which is a part of the enhanced detection method XML.
#>
function Get-EnhancedDetectionData{
    [CmdletBinding()]
    param
    (
        # We need the full enhanced detection method XML to be able to search for the correct setting per each rule
        # they are stored seperately in "Settings" and "Rule". Each Rule has a corresponding Setting
        [xml]$EnhancedDetectionMethods, 
        # The rule we currently work on
        $RuleExpression
    ) 

    #region lookup hashtables
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

    # create new object to hold result data.
    # will add all recursive gathered data to this object as well
    $resultList = New-Object psobject
    # The flat list will contain each detection without the group info
    $flatResultList = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach($operand in $RuleExpression)
    {
        # only "and" and "or" are of interest, because they are used for operand groups
        # All other operators are used for settings. Like file size EQUALS 12 
        If ($operand.Operator -ieq 'and') 
        {
            if ($resultList."And") # means there is an entry already
            {
                # if we have multiple "and" operators we need to add a number to be able to add them to the object
                $andCounter++
                $resultList | Add-Member -MemberType NoteProperty -Name "And-$($andCounter)" -Value @()
            }
            else 
            {
                $resultList | Add-Member -MemberType NoteProperty -Name "And" -Value @() -ErrorAction stop
            }         

            # Add from mstraessner - https://github.com/mstraessner - 04.06.2025 - Line 568 - 573
			# we need to add an info about the OR operator seperatly, because it is not supported by Intune at the moment
            $tmpObj = [PSCustomObject]@{
                RulesWithOr = $false
            }
            $flatResultList.Add($tmpObj)
            
            # Lets get all sub-operands for this operator
            $resultObj = Get-EnhancedDetectionData -EnhancedDetectionMethods $EnhancedDetectionMethods -RuleExpression $operand.Operands.Expression
            foreach ($item in $resultObj.ConfigMgrList)
            {
                if ($andCounter -gt 0)
                {
                    $resultList."And-$($andCounter)" += $item 
                }
                else 
                {
                    $resultList."And" += $item 
                }
            }  
            
            # lets also add the data to the flat list
            foreach ($item in $resultObj.FlatList)
            {
                $flatResultList.Add($item)
            }

        }
        elseif ($operand.Operator -ieq 'or') 
        {
            if ($resultList."Or") # means there is an entry already
            {
                # if we have multiple "and" operators we need to add a number to be able to add them to the object
                $orCounter++
                $resultList | Add-Member -MemberType NoteProperty -Name "Or-$($orCounter)" -Value @()
            }
            else 
            {
                $resultList | Add-Member -MemberType NoteProperty -Name "Or" -Value @()
            }

            # we need to add an info about the OR operator seperatly, because it is not supported by Intune at the moment
            $tmpObj = [PSCustomObject]@{
                RulesWithOr = $true
            }
            $flatResultList.Add($tmpObj)

            # Lets get all sub-operands for this operator
            $resultObj = Get-EnhancedDetectionData -EnhancedDetectionMethods $EnhancedDetectionMethods -RuleExpression $operand.Operands.Expression
            foreach ($item in $resultObj.ConfigMgrList)
            {
                if ($orCounter -gt 0)
                {
                    $resultList."Or-$($orCounter)" += $item 

                }
                else 
                {
                    $resultList."Or" += $item 
                }
            }

            # lets also add the data to the flat list
            foreach ($item in $resultObj.FlatList)
            {
                $flatResultList.Add($item)
            }

        }
        else 
        {
            # This if clause limits the settings sections in our custom object
            if ($resultList.PSObject.Properties.Name -inotcontains 'Settings') 
            {
                $resultList | Add-Member -MemberType NoteProperty -Name 'Settings' -Value @()
            }

            $SettingLogicalName = $operand.Operands.SettingReference.SettingLogicalName
            Write-Verbose $SettingLogicalName
            Switch ($operand.Operands.SettingReference.SettingSourceType) 
            {                
                'Registry'
                {
                    $RegSetting = $EnhancedDetectionMethods.EnhancedDetectionMethod.Settings.SimpleSetting | Where-Object { $_.LogicalName -eq "$SettingLogicalName" }      
                    $intuneOperator = $null
                    $intuneOperator = $registryValueRuleExpressionOperatorMapping[$operand.Operator]

                    $tmpObj = [PSCustomObject]@{
                        DetectionType = 'RegSetting'
                        DetectionTypeIntune = 'AppDetectionRuleRegistry'
                        RegHive     = $RegSetting.RegistryDiscoverySource.Hive
                        RegKey      = $RegSetting.RegistryDiscoverySource.Key
                        RegValue    = $RegSetting.RegistryDiscoverySource.ValueName
                        Is32BitOn64BitSystem    = if($RegSetting.RegistryDiscoverySource.Is64Bit -ieq 'false'){$true}else{$false}
                        RegMethod   = $operand.Operands.SettingReference.Method
                        RegData     = $operand.Operands.ConstantValue.Value
                        RegDataList = $operand.Operands.ConstantValueList.ConstantValue.Value
                        RegDataType = $operand.Operands.SettingReference.DataType
                        Operator = $operand.Operator
                        OperatorIntune = if([string]::IsNullOrEmpty($intuneOperator)){'NotSupported'}else{$intuneOperator}
                    }
                    $resultList.Settings += $tmpObj
                    $flatResultList.Add($tmpObj)
                }
                'File' 
                {
                    $FileSetting = $EnhancedDetectionMethods.EnhancedDetectionMethod.Settings.File | Where-Object { $_.LogicalName -eq "$SettingLogicalName" }
                    $intuneOperator = $null
                    $intuneOperator = $fileFolderRuleExpressionOperatorMapping[$operand.Operator]

                    $tmpObj = [PSCustomObject]@{
                        DetectionType = 'FileSetting'
                        DetectionTypeIntune = 'AppDetectionRuleFileOrFolder'
                        ParentFolder             = $FileSetting.Path
                        FileName                 = $FileSetting.Filter
                        Is32BitOn64BitSystem     = if($FileSetting.Is64Bit -ieq 'false'){$true}else{$false}
                        Operator                 = $operand.Operator
                        OperatorIntune = if([string]::IsNullOrEmpty($intuneOperator)){'NotSupported'}else{$intuneOperator}
                        FileMethod               = $operand.Operands.SettingReference.Method
                        FileValueList            = $operand.Operands.ConstantValueList.ConstantValue.Value
                        FileValue                = $operand.Operands.ConstantValue.Value
                        FilePropertyName         = $operand.Operands.SettingReference.PropertyPath
                        FilePropertyNameDataType = $operand.Operands.SettingReference.DataType
                    }
                    $resultList.Settings += $tmpObj
                    $flatResultList.Add($tmpObj)
                }
                'Folder' 
                {
                    $FolderSetting = $EnhancedDetectionMethods.EnhancedDetectionMethod.Settings.Folder | Where-Object { $_.LogicalName -eq "$SettingLogicalName" }
                    $intuneOperator = $null
                    $intuneOperator = $fileFolderRuleExpressionOperatorMapping[$operand.Operator]

                    $tmpObj = [PSCustomObject]@{
                        DetectionType = 'FolderSetting'
                        DetectionTypeIntune = 'AppDetectionRuleFileOrFolder'
                        ParentFolder               = $FolderSetting.Path
                        FolderName                 = $FolderSetting.Filter
                        Is32BitOn64BitSystem                = if($FolderSetting.Is64Bit -ieq 'false'){$true}else{$false}
                        Operator             = $operand.Operator
                        OperatorIntune = if([string]::IsNullOrEmpty($intuneOperator)){'NotSupported'}else{$intuneOperator}
                        FolderMethod               = $operand.Operands.SettingReference.Method
                        FolderValueList            = $operand.Operands.ConstantValueList.ConstantValue.Value
                        FolderValue                = $operand.Operands.ConstantValue.Value
                        FolderPropertyName         = $operand.Operands.SettingReference.PropertyPath
                        FolderPropertyNameDataType = $operand.Operands.SettingReference.DataType
                    }
                    $resultList.Settings += $tmpObj
                    $flatResultList.Add($tmpObj)
                }
                'MSI' 
                {
                    $MSIDetectionMethod = $null
                    $MSISetting = $EnhancedDetectionMethods.EnhancedDetectionMethod.Settings.MSI | Where-Object { $_.LogicalName -eq "$SettingLogicalName" }
                    if ($operand.Operands.SettingReference.DataType -ieq 'Int64') 
                    {
                        # Exists detection
                        $MSIDetectionMethod = 'MSI exists'
                    }
                    elseif ($operand.Operands.SettingReference.DataType -ieq 'Version') 
                    {
                        # Exists plus is a specific version of MSI
                        $MSIDetectionMethod = 'MSI exists and specific version'
                    }
                    Else 
                    {
                        # "Unknown MSI Configuration for product code."
                        $MSIDetectionMethod = 'Unknown'
                    }

                    $intuneOperator = $null
                    $intuneOperator = $windowsInstallerRuleExpressionOperatorMapping[$operand.Operator]

                    $tmpObj = [PSCustomObject]@{
                        DetectionType = 'MsiSetting'
                        DetectionTypeIntune = 'AppDetectionRuleMSI'
                        MSIProductCode  = $MSISetting.ProductCode
                        MSIDataType     = $operand.Operands.SettingReference.DataType
                        MSIMethod       = $operand.Operands.SettingReference.Method
                        MSIDetectionMethod = $MSIDetectionMethod
                        MSIDataValue    = $operand.Operands.ConstantValue.Value
                        MSIPropertyName = $operand.Operands.SettingReference.PropertyPath
                        Operator     = $operand.Operator
                        OperatorIntune = if([string]::IsNullOrEmpty($intuneOperator)){'NotSupported'}else{$intuneOperator}
                    }
                    $resultList.Settings += $tmpObj
                    $flatResultList.Add($tmpObj)
                }
            }
        }
    }

    $outObj = [pscustomobject]@{
        FlatList = $flatResultList
        ConfigMgrList = $resultList
    }

    return $outObj 
}
#endregion


#region Wait-ForGraphRequestCompletion 
function Wait-ForGraphRequestCompletion 
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$Uri,
        [Parameter()]
        [string]$Stage      
    )

    if ($Stage )
    {
        # We need to test for a specific stage
        $successString = '{0}Success' -f $Stage    
    }
    else 
    {
        $successString = 'Success'
    }
    
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
    until ($GraphRequest.uploadState -imatch $successString)
    Write-CMTraceLog -Message "Intune service request for operation '$($operation)' was successful with uploadState: $($GraphRequest.uploadState)"

    return $GraphRequest
}
#endregion

#region function Out-DataFile
<#
    Function to replace app data in existing app files
#>
function Out-DataFile
{
    param
    (
        $FilePath,
        $OutObject
    )

    $appOutObj = [System.Collections.Generic.List[pscustomobject]]::new()
    # we need to add the apps we want to replace to our new $appOutObj variable
    foreach ($appItem in $OutObject)
    {
        $appOutObj.Add($appItem)      
    }

    $fileExtension = [System.IO.Path]::GetExtension($FilePath)

    if (Test-Path $FilePath)
    {
        Write-CMTraceLog -Message "File exists: `"$($FilePath)`" will replace selected apps" -Severity Warning
        Write-CMTraceLog -Message "Import data from file"
        # import
        Switch($fileExtension)
        {
            '.xml'
            {
                [array]$importedAppsList = Import-Clixml $FilePath -ErrorAction Stop 
            }
            '.json'
            {
                [array]$importedAppsList = Get-Content $FilePath -ErrorAction Stop | ConvertFrom-Json
            }
            '.csv'
            {
                [array]$importedAppsList = Import-Csv $FilePath -ErrorAction Stop 
            }
        }

        # lets now replace the apps which were selected for export. Maybe all, maybe just one
        foreach ($appItem in $importedAppsList)
        {
            # outobject contains selected apps which should be exported and replaced
            # $appItem is an app which exists in the exported file already
            # But if the app is not in the selection, we can safely add it to our out object
            # All other selected apps coming from the file will be ignored, because they are already part of our new out object
            if ($appItem.LogicalName -inotin $OutObject.LogicalName)
            {
                $appOutObj.Add($appItem)      
            }
        }
    }

    # Export either replaced data or the normal out data
    Switch($fileExtension)
    {
        '.xml'
        {
            Write-CMTraceLog -Message "Export all apps to: `"$($FilePath)`" to be able to work with them later in this script even on other devices"
            $appOutObj| Export-Clixml -Path $FilePath -Depth 100
        }
        '.json'
        {
            Write-CMTraceLog -Message "Export all apps to: `"$($FilePath)`" for easy reading in a text editor"    
            $appOutObj | ConvertTo-Json -Depth 100 | Out-File -FilePath $FilePath -Encoding unicode
        }
        '.csv'
        {
            Write-CMTraceLog -Message "Export all apps to: `"$($FilePath)`" to be able to analyze them in Excel"
            $appOutObj| Select-Object -Property * -ExcludeProperty DeploymentTypes, IconId, IconPath | Export-Csv $FilePath -NoTypeInformation
        }
    }
}
#endregion 

#region check for required modules and install them if not available
<#
.SYNOPSIS
    Function to check for required modules and install them if not available

.PARAMETER RequiredModules
    List of modules which are required for the script to run. The modules will be installed if not available.

.EXAMPLE
    Get-RequiredScriptModules -RequiredModules @("Device.ReadWrite.All", "DeviceManagementManagedDevices.ReadWrite.All")
#>
function Get-RequiredScriptModules 
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$RequiredModules
    )

    $moduleNotFound = $false
    foreach ($requiredModule in $requiredModules)
    {
        try 
        {
            Import-Module -Name $requiredModule -ErrorAction Stop    
        }
        catch 
        {
            $moduleNotFound = $true
        }
    }

    try 
    {
        if ($moduleNotFound)
        {
            # We might need nuget to install the module
            [version]$minimumVersion = '2.8.5.201'
            $nuget = Get-PackageProvider -ErrorAction Ignore | Where-Object {$_.Name -ieq 'nuget'} 
            if (-Not($nuget))
            {   
                Write-CMTraceLog -Message "Need to install NuGet to be able to install `"$($requiredModule)`"" 
                # Changed to MSI installer as the old way could not be enforced and needs to be approved by the user
                # Install-PackageProvider -Name NuGet -MinimumVersion $minimumVersion -Force
                $null = Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies -MinimumVersion $minimumVersion -Force
            }

            foreach ($requiredModule in $RequiredModules)
            {
                if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
                {
                    Write-CMTraceLog -Message "No admin permissions. Will install `"$($requiredModule)`" for current user only" 
                    
                    $paramSplatting = @{
                        Name = $requiredModule
                        Force = $true
                        Scope = 'CurrentUser'
                        Repository = 'PSGallery'
                        ErrorAction = 'Stop'
                    }
                    Install-Module @paramSplatting
                }
                else 
                {
                    Write-CMTraceLog -Message "Admin permissions. Will install `"$($requiredModule)`" for all users" 

                    $paramSplatting = @{
                        Name = $requiredModule
                        Force = $true
                        Repository = 'PSGallery'
                        ErrorAction = 'Stop'
                    }

                    Install-Module @paramSplatting
                }   

                Import-Module $requiredModule -Force -ErrorAction Stop
            }
        }    
    }
    catch 
    {
        Write-CMTraceLog -Message "Failed to install or load module" -Severity Error
        Write-CMTraceLog -Message "$($_)" -Severity Error
        Exit 1
    }
}
#endregion

#region Test-Win32LobAppExistence
function Test-Win32LobAppExistence
{
    param
    (
        [string]$AppName
    )

    Write-CMTraceLog -Message "Start searching for Win32 app: `"$($AppName)`" in Intune"
    $filterString = "`$filter=(isof('microsoft.graph.win32LobApp') and not(isof('microsoft.graph.win32CatalogApp')))"
    $searchString = '$search="{0}"' -f [System.Uri]::EscapeDataString($AppName)
    $selectString = '$select=id,displayName'
    $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?{0}&{1}&{2}" -f $filterString,$searchString,$selectString
    Write-CMTraceLog -Message "URI: `"$($uri)`"" -OutputMode Log
    #$encodedUrl = [System.Uri]::EscapeUriString($uri)

    try 
    {
        $appRetval = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop    
    }
    catch 
    {
        Write-CMTraceLog -Message "Not able to get Win32 apps from Intune" -Severity Warning
        Write-CMTraceLog -Message "$($_)" -Severity Warning
        Write-CMTraceLog -Message "Will continue with script"
        return $false
    }

    # Graph search can result in multiple apps containing the search string. We need to check if the app we are looking for is in the result
    foreach($app in $appRetval.value)
    {
        Write-CMTraceLog -Message "Found win32app: `"$($app.displayName)`" in Intune"
        if ($app.displayName -ieq $AppName)
        {
            Write-CMTraceLog -Message "Name matches: `"$($AppName)`""
            return $true
        }
    }
    return $false
}
#endregion

#region Get-AllWin32AppNamesFromIntune
function Get-AllWin32AppNamesFromIntune
{
    try 
    {
        Write-CMTraceLog -Message "Trying to get all win32app names from Intune"
        $uri= "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=((isof(%27microsoft.graph.win32LobApp%27)%20and%20not(isof(%27microsoft.graph.win32CatalogApp%27))))%20and%20(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&`$orderby=displayName%20asc&`$select=id,displayName"
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        $allApps = @()
        $allApps += $response.value
        
        while ($null -ne $response.'@odata.nextLink')
        {
            $response = Invoke-MgGraphRequest -Method GET -Uri $response.'@odata.nextLink' -ErrorAction Stop
            $allApps += $response.value
        }
    }
    catch 
    {
        Write-CMTraceLog -Message "Not able to get Win32 apps from Intune" -Severity Warning
        Write-CMTraceLog -Message "$($_)" -Severity Warning
        Write-CMTraceLog -Message "Will continue with script"
        return $false
    }
    return $allApps
}
#endregion

#region Test-ObjectProperties
<#
.SYNOPSIS
    Function to ensure that all properties of an object exist with default values
    This is for backward compatibility with older scripts which might not have all properties in the object
#>
function Test-ObjectProperties 
{
    param 
    (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [PSCustomObject]$InputObject
    )
    
    begin 
    {
        # Define the correct order of properties with default values
        $propertyOrder = [ordered]@{
            "AppImportToIntunePossible" = "No"
            "AllChecksPassed" = "No"
            "IntunewinFileExists" = "No"
            "Uploaded" = "No"
            "ExistsInIntune" = "Unknown"
            "LogicalName" = $null
            "Name" = $null
            "NameSanitized" = $null
            "CIVersion" = $null
            "SoftwareVersion" = $null
            "CI_ID" = $null
            "CI_UniqueID" = $null
            "DeploymentTypesTotal" = $null
            "IsDeployed" = $null
            "IsSuperseded" = $null
            "IsSuperseding" = $null
            "Description" = $null
            "Tags" = $null
            "Publisher" = $null
            "ReleaseDate" = $null
            "InfoUrl" = $null
            "IconId" = $null
            "InstallContent" = $null
            "InstallCommandLine" = $null
            "IntuneWinAppUtilSetupFile" = $null
            "UninstallCommandLine" = $null
            "IconPath" = $null
            "IntunewinFilePath" = $null
            "DeploymentTypes" = $null
            "CheckTotalDeploymentTypes" = "Unknown"
            "CheckIsSuperseded" = "Unknown"
            "CheckIsSuperseding" = "Unknown"
            "CheckTags" = "Unknown"
            "CheckTechnology" = "Unknown"
            "CheckLogonRequired" = "Unknown"
            "CheckAllowUserInteraction" = "Unknown"
            "CheckProgramVisibility" = "Unknown"
            "CheckSetupFile" = "Unknown"
            "CheckUnInstallSetting" = "Unknown"
            "CheckNoUninstallCommand" = "Unknown"
            "CheckRepairCommand" = "Unknown"
            "CheckRepairFolder" = "Unknown"
            "CheckSourcePath" = "Unknown"
            "CheckSourceUpdateProductCode" = "Unknown"
            "CheckRebootBehavior" = "Unknown"
            "CheckHasDependency" = "Unknown"
            "CheckExeToCloseBeforeExecution" = "Unknown"
            "CheckCustomReturnCodes" = "Unknown"
            "CheckRequirements" = "Unknown"
            "CheckRulesWithGroups" = "Unknown"
            "CheckRulesWithOr" = "Unknown"
            "CheckUnsupportedOperators" = "Unknown"
        }
    }
    process 
    {
        $obj = $InputObject

        # Convert the object to a hashtable
        $objHash = @{}
        foreach ($prop in $obj.PSObject.Properties) {
            $objHash[$prop.Name] = $prop.Value
        }

        # Ensure all properties in the list exist with default values
        foreach ($prop in $propertyOrder.Keys) {
            if (-not $objHash.ContainsKey($prop)) {
                $objHash[$prop] = $propertyOrder[$prop]  # Add the property with its default value
            }
        }

        # Create a new ordered custom object
        $orderedObj = [PSCustomObject]@{}
        foreach ($prop in $propertyOrder.Keys) {
            $orderedObj | Add-Member -MemberType NoteProperty -Name $prop -Value $objHash[$prop]
        }

        # Output the ordered object
        $orderedObj
    }
}
#endregion

#region
function Get-MsiMetadata 
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$MsiPath,
        [array]$desiredProperties = @('ALLUSERS', 'ProductVersion', 'ProductLanguage', 'Manufacturer', 'ProductCode', 'UpgradeCode', 'ProductName')
    )
    # Written by GitHub Copilot with some manual adjustments
    $installer = $null
    $database = $null
    $view = $null
    $record = $null

    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $installer, @($MsiPath, 0))

        $query = "SELECT * FROM Property"
        $view = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, ($query))
        [void]$view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null)

        $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
        $properties = @{}       

        while ($null -ne $record) 
        {
            $property = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 1)
            $value = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 2)

            if ($property -in $desiredProperties) {
                $properties[$property] = $value
            }

            $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
        }

        [void]$view.GetType().InvokeMember("Close", "InvokeMethod", $null, $view, $null)
    } finally {
        if ($null -ne $record) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($record) | Out-Null }
        if ($null -ne $view) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($view) | Out-Null }
        if ($null -ne $database) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($database) | Out-Null }
        if ($null -ne $installer) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer) | Out-Null }
    }

    return $properties
}
#endregion

## MAIN SCRIPT

#region folder creation if not done already
# Validate path and create if not there yet
Write-Host "Start of script" -ForegroundColor Green
try 
{
    if (-not (Test-Path $ExportFolder)) 
    {
        Write-Host "Export folder: `"$($ExportFolder)`" does not exist. Will be created..." -ForegroundColor Green # logfile not ready yet
        New-Item -ItemType Directory -Path $ExportFolder -Force | Out-Null
    }

    # We also need some folders to store the exported data
    #$ExportFolderContent = '{0}\Content' -f $ExportFolder
    $ExportFolderTools = '{0}\Tools' -f $ExportFolder
    $ExportFolderAppDetails = '{0}\AppDetails' -f $ExportFolder
    $ExportFolderIcons = '{0}\Icons' -f $ExportFolder
    $ExportFolderScripts = '{0}\Scripts' -f $ExportFolder
    $ExportFolderWin32Apps = '{0}\Win32Apps' -f $ExportFolder

    foreach ($folder in ($ExportFolderTools, $ExportFolderAppDetails, $ExportFolderIcons, $ExportFolderScripts, $ExportFolderWin32Apps))
    {
        if (-not (Test-Path $folder))
        {
            Write-Host "Will create export folder: `"$($folder)`"" -ForegroundColor Green
            New-Item -ItemType Directory -Path $folder -Force | Out-Null   
        }
        else 
        {
            Write-Host "Folder: `"$($folder)`" does exist" -ForegroundColor Green
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

Invoke-LogfileRollover -Logfile $script:LogFilePath -MaxFileSizeKB 2048

Write-CMTraceLog -Message '   '
Write-CMTraceLog -Message 'Start of main script'
Write-CMTraceLog -Message "Scriptversion: $($scriptVersion)"
Write-CMTraceLog -Message "Export will be made to folder: $($ExportFolder)"
#endregion

#region Get the ConfigMgr apps
if ($Step1GetConfigMgrAppInfo -or $RunAllActions)
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
        $appCounter = 0
        foreach ($app in $selectedApps)
        {
            $appCounter++
            Write-Progress -Activity "Analyze ConfigMgr apps" -status "Analyze app: $appCounter of $($selectedApps.count) - `"$($app.LocalizedDisplayName)`"" -percentComplete ($appCounter / $selectedApps.count*100)
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


            Write-CMTraceLog -Message "Getting info of App: $($appXmlContent.AppMgmtDigest.Application.title.'#text')" -OutputMode Log
            $tmpApp = [PSCustomObject]@{
                AppImportToIntunePossible = "Yes"
                AllChecksPassed = 'Yes'
                IntunewinFileExists = 'No'
                Uploaded = 'No'
                ExistsInIntune = 'Unknown'
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
                InstallContent = $null
                InstallCommandLine = $null
                IntuneWinAppUtilSetupFile = $null
                UninstallCommandLine = $null
                IconPath = $IconPath
                IntunewinFilePath = $null
                DeploymentTypes = $null
                CheckTotalDeploymentTypes = "OK"
                CheckIsSuperseded = "OK"
                CheckIsSuperseding = "OK"
                CheckTags = "OK"
                CheckTechnology = "OK"
                CheckLogonRequired = "OK"
                CheckAllowUserInteraction = "OK"
                CheckProgramVisibility = "OK"
                CheckSetupFile = "OK"
                CheckUnInstallSetting = "OK" 
                CheckNoUninstallCommand = "OK"
                CheckRepairCommand = "OK"
                CheckRepairFolder = "OK"
                CheckSourcePath = "OK"
                CheckSourceUpdateProductCode = "OK"
                CheckRebootBehavior = "OK"
                CheckHasDependency = "OK"
                CheckExeToCloseBeforeExecution = "OK"
                CheckCustomReturnCodes = "OK"
                CheckRequirements = "OK"
                CheckRulesWithGroups = "OK"
                CheckRulesWithOr = "OK"
                CheckUnsupportedOperators = "OK"   

            }

            Write-CMTraceLog -Message "Getting deploymenttype info for app" -OutputMode Log
            $appDeploymenTypesList = [System.Collections.Generic.List[pscustomobject]]::new()
            if ($fullApp.NumberOfDeploymentTypes -ge 1)
            {
                foreach ($deploymentType in $appXmlContent.AppMgmtDigest.DeploymentType) 
                {
                    $noContentButShare = $false
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

                    # Check for executables that must be closed
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

                    # 20241217 added parameters for Install and Uninstall command line replacement and moved UNC path detection to here
                    # In case we do not have a content path and instead the install or uninstall points to a share, correct that
                    $installStringToRemove = $null
                    $Matches = $null
                    # Matches a UNC path with spaces encapsulated in single or double quotes or UNC path without spaces. Can be at the beginning of the string or after a space
                    if($deploymentType.Installer.CustomData.InstallCommandLine -match "(\\\\[^ ]*)|[`"\'](\\\\[^`"\']*)[`"\']")
                    {
                        $noContentButShare = $true
                        try
                        { 
                            $installLocation = ($Matches[0] -replace "[`"']") | Split-Path -Parent 
                            $installStringToRemove = '{0}\\' -f ([regex]::Escape($installLocation))
                        }catch{} 
                    }

                    $unInstallStringToRemove = $null
                    $Matches = $null
                    # Matches a UNC path with spaces encapsulated in single or double quotes or UNC path without spaces. Can be at the beginning of the string or after a space
                    if($deploymentType.Installer.CustomData.UninstallCommandLine -match "(\\\\[^ ]*)|[`"\'](\\\\[^`"\']*)[`"\']")
                    {
                        $noContentButShare = $true
                        try
                        { 
                            $uninstallLocation = ($Matches[0] -replace "[`"']") | Split-Path -Parent 
                            $unInstallStringToRemove = '{0}\\' -f ([regex]::Escape($uninstallLocation))
                        }catch{} 
                    }                    

                    # Replace string if needed
                    if (-NOT ([string]::IsNullOrEmpty($ReplaceInstallCommand)))
                    {
                        $dtInstallCommandLine = $ReplaceInstallCommand
                    }
                    else 
                    {
                        # Replace will only happen if the script detected a UNC path in the install cmd
                        $dtInstallCommandLine = $deploymentType.Installer.CustomData.InstallCommandLine -replace $installStringToRemove
                    }

                    # Replace string if needed
                    if (-NOT ([string]::IsNullOrEmpty($ReplaceUninstallCommand)))
                    {
                        $dtUnInstallCommandLine = $ReplaceUninstallCommand
                    }
                    else 
                    {
                        # Replace will only happen if the script detected a UNC path in the uninstall cmd
                        $dtUnInstallCommandLine = $deploymentType.Installer.CustomData.UninstallCommandLine -replace $unInstallStringToRemove
                    }                    

                    # Extract file info for win32apputil -s parameter
                    $Matches = $null
                    if ($dtInstallCommandLine -match "powershell" -and $dtInstallCommandLine -match "\.ps1") 
                    {
                        $null = $dtInstallCommandLine -match "(?:.*[\\|\s|`"|'])?(.*\.ps1)"
                        $intuneWinAppUtilSetupFile = $Matches[1]
                        $Matches = $null
                    }
                    elseif ($dtInstallCommandLine -match "\.exe" -and $dtInstallCommandLine -notmatch "msiexec\.exe" -and $dtInstallCommandLine -notmatch "cscript\.exe" -and $dtInstallCommandLine -notmatch "wscript\.exe")
                    {
                        $null = $dtInstallCommandLine -match "(?:.*[\\|\s|`"|'])?(.*\.exe)"
                        $intuneWinAppUtilSetupFile = $Matches[1]
                        $Matches = $null
                    }
                    elseif ($dtInstallCommandLine -match "\.msi") 
                    {
                        $null = $dtInstallCommandLine -match "(?:.*[\\|\s|`"|'])?(.*\.msi)"
                        $intuneWinAppUtilSetupFile = $Matches[1]
                        $Matches = $null
                    }
                    elseif ($dtInstallCommandLine -match "\.vbs") 
                    {
                        $null = $dtInstallCommandLine -match "(?:.*[\\|\s|`"|'])?(.*\.vbs)"
                        $intuneWinAppUtilSetupFile = $Matches[1]
                        $Matches = $null
                    }
                    elseif ($dtInstallCommandLine -match "\.cmd") 
                    {
                        $null = $dtInstallCommandLine -match "(?:.*[\\|\s|`"|'])?(.*\.cmd)"
                        $intuneWinAppUtilSetupFile = $Matches[1]
                        $Matches = $null
                    }
                    elseif ($dtInstallCommandLine -match "\.bat") 
                    {
                        $null = $dtInstallCommandLine -match "(?:.*[\\|\s|`"|'])?(.*\.bat)"
                        $intuneWinAppUtilSetupFile = $Matches[1]
                        $Matches = $null
                    }
                    else 
                    {
                        $intuneWinAppUtilSetupFile = $null
                        #Write-CMTraceLog -Message "IntuneWinAppUtilSetupFile could not been determined. App cannot be imported into Intune." -Severity Error
                        #$tmpApp.AppImportToIntunePossible = 'No'
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
                        UninstallCommandLine = $dtUnInstallCommandLine
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
                        ExecutionContext = $null
                        ProductCode = $null
                        PackageCode = $null
                        PatchCodes = $null
                        RulesWithGroups = $false
                        RulesWithOr = $false                          
                        Rules = $null
                        RulesFlat = $null
                        MSIFileMetadata = $null
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
                                # 20241217 fixed the always true issue
                                if ($deploymentType.Installer.DetectAction.Args.Arg[3].'#text' -ieq 'true')
                                {
                                    $runAs32BitOn64BitSystem = $true
                                }
                                else 
                                {
                                    $runAs32BitOn64BitSystem = $false
                                }
                            }

                            $scriptFilePath = '{0}\{1}.{2}' -f $ExportFolderScripts, $deploymentType.LogicalName, $dmScriptSuffix
                            # PowerShell 5.1 compatibility and correct format for Intune
                            try 
                            {
                                $utf8Bom = [System.Text.Encoding]::UTF8.GetPreamble() + [System.Text.Encoding]::UTF8.GetBytes($deploymentType.Installer.DetectAction.Args.Arg[2].'#text')
                                [System.IO.File]::WriteAllBytes($scriptFilePath, $utf8Bom)    
                            }
                            catch 
                            {
                                write-CMTraceLog -Message "Failed to write detection script file" -Severity Error
                                write-CMTraceLog -Message "$($_)" -Severity Error
                            }

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
                            $tmpDetectionItem.ExecutionContext = ($deploymentType.Installer.DetectAction.Args.arg | Where-Object {$_.Name -ieq 'ExecutionContext'}).'#text'
                            $tmpDetectionItem.ProductCode = ($deploymentType.Installer.DetectAction.Args.arg | Where-Object {$_.Name -ieq 'ProductCode'}).'#text'
                            $tmpDetectionItem.PackageCode = ($deploymentType.Installer.DetectAction.Args.arg | Where-Object {$_.Name -ieq 'PackageCode'}).'#text'
                            $tmpDetectionItem.PatchCodes = ($deploymentType.Installer.DetectAction.Args.arg | Where-Object {$_.Name -ieq 'PatchCodes'}).'#text'

                            # We need more data from the file itself
                            $fileFullName = '{0}\{1}' -f $installLocation, $intuneWinAppUtilSetupFile
                            if (Test-Path $fileFullName)
                            {
                                $tmpDetectionItem.MSIFileMetadata = Get-MsiMetadata -MsiPath $fileFullName
                            }
                            else 
                            {
                                Write-CMTraceLog -Message "MSI file could not been found: `"$($fileFullName)`" App cannot be imported into Intune." -Severity Error
                                $tmpApp.AppImportToIntunePossible = 'No'
                            }
                        }
                        'Local'
                        {
                            $tmpDetectionItem.Type = 'Enhanced'
                            [xml]$edmData = $deploymentType.Installer.DetectAction.args.arg[1].'#text'
                            
                            $tmpRulesObject = Get-EnhancedDetectionData -EnhancedDetectionMethods $edmData -RuleExpression $edmData.EnhancedDetectionMethod.Rule.Expression
                            $tmpDetectionItem.Rules = $tmpRulesObject.ConfigMgrList
                            $tmpDetectionItem.RulesFlat = $tmpRulesObject.FlatList
                            $tmpDetectionItem.RulesWithGroups = $deploymentType.Installer.DetectAction.args.arg[1].'#text' -imatch ([regex]::Escape('<Expression IsGroup="true">'))
                            # # comment out from mstraessner - https://github.com/mstraessner - 04.06.2025
                            #$tmpDetectionItem.RulesWithOr = $tmpDetectionItem.RulesFlat.RulesWithOR

                            $tmpRulesWithOr = $null
                            $tmpRulesWithOr = $tmpDetectionItem.RulesFlat | Where-Object {$_.RulesWithOR -eq $true}
                            if ($tmpRulesWithOr)
                            {
                                $tmpDetectionItem.RulesWithOr = $true
                                # Lets remove the RulesWithOr sub object
                                $tmpDetectionItem.RulesFlat = $tmpDetectionItem.RulesFlat | Where-Object {$_.RulesWithOr -eq $null}
                            }
                            # Add from mstraessner - https://github.com/mstraessner - 04.06.2025 - Line 1773 - 1777
                            # Comment out line 1763, because $tmpDetectionItem.RulesFlat.RulesWithOR is an arry; We tested this script all day and searched for all issues, because our application, which uses two conditions with an AND operation, was interpreted as an OR operation.
                            else
                            {
                                $tmpDetectionItem.RulesWithOr = $false
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
            # The next duplicate fields are just to make them easier visible in the GridView and not used for anything else
            $tmpApp.InstallContent = $appDeploymenTypesList[0].InstallContent
            $tmpApp.InstallCommandLine = $appDeploymenTypesList[0].InstallCommandLine
            $tmpApp.IntuneWinAppUtilSetupFile = $appDeploymenTypesList[0].IntuneWinAppUtilSetupFile
            $tmpApp.UninstallCommandLine = $appDeploymenTypesList[0].UninstallCommandLine

            # Lets now check Intune compatability
            # DeploymentTypesTotal
            if ($tmpApp.DeploymentTypesTotal -gt 1)
            {
                $tmpApp.CheckTotalDeploymentTypes = "NO IMPORT: App has more than one deployment type. This is not supported by Intune. And the script currently does not support the creation of multiple apps, one for each deployment type. Copy the app and remove all deployment types except one. Then run the script again."
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
            if($tmpApp.deploymentTypes[0].Technology -inotmatch '(Script|MSI)')
            {
                $tmpApp.CheckTechnology = "NO IMPORT: App technology: `"$($tmpApp.deploymentTypes[0].Technology)`" The app cannot be created. Only 'script' and 'MSI' are supported as technology by the script at the moment."
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

            if([string]::IsNullOrEmpty($tmpApp.deploymentTypes[0].IntuneWinAppUtilSetupFile))
            {
                $tmpApp.CheckSetupFile = "NO IMPORT: IntuneWinSetup file could not been determined. App cannot be imported into Intune."
                $tmpApp.AllChecksPassed = 'No'
                $tmpApp.AppImportToIntunePossible = 'No'
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
                $tmpApp.CheckNoUninstallCommand = "NO IMPORT: The uninstall command is missing. Intune requires an uninstall command. The app cannot be created."
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

            if ($noContentButShare)
            {
                $tmpApp.CheckSourcePath = "NOTE: DeploymentType has no content path. Instead the un- or install command contains an UNC path. That path is used for the content creation"   
            }

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

            # Check for unsupported operators
            [array]$unsupportedOperators = $tmpApp.deploymentTypes[0].DetectionRules.RulesFlat | Where-Object {$_.OperatorIntune -ieq 'NotSupported'}
            if ($unsupportedOperators.Count -gt 0)
            {
                $tmpApp.CheckUnsupportedOperators = "FAILED: The app has detection rules with unsupported operators. The app can still be created without the detection rules with unsupported operators. Consider the use of a detection script with the same check logic instead."
                $tmpApp.AllChecksPassed = 'No'
            }


            $appfileFullName = '{0}\{1}.xml' -f $ExportFolderAppDetails, $tmpApp.LogicalName
            Write-CMTraceLog -Message "Export app to: `"$($appfileFullName)`" to be able to work with them later in PowerShell" -OutputMode Log
            $tmpApp | Export-Clixml -Path $appfileFullName -Depth 100

            $appfileFullName = '{0}\{1}.json' -f $ExportFolderAppDetails, $tmpApp.LogicalName
            write-CMTraceLog -Message "Export app to: `"$($appfileFullName)`" for easy reading in a text editor" -OutputMode Log
            $tmpApp | ConvertTo-Json -Depth 100 | Out-File -FilePath $appfileFullName -Encoding unicode
            
            $appOutObj.Add($tmpApp)

        }
    }
    Write-Progress -Completed -Activity "Analyze ConfigMgr apps"
    if ($appOutObj.Count -gt 0)
    {

        $appfileFullName = '{0}\AllAps.xml' -f $ExportFolderAppDetails
        Out-DataFile -FilePath $appfileFullName -OutObject $appOutObj

        $appfileFullName = '{0}\AllAps.json' -f $ExportFolderAppDetails
        Out-DataFile -FilePath $appfileFullName -OutObject $appOutObj

        $appfileFullName = '{0}\AllAps.csv' -f $ExportFolderAppDetails
        Out-DataFile -FilePath $appfileFullName -OutObject $appOutObj

    }
    else 
    {
        Write-CMTraceLog -Message "Nothing selected."
    }
}
#endregion


#region Win32AppCreation 
if ($Step2CreateIntuneWinFiles -or $CreateIntuneWinFilesAndUploadToIntune -or $RunAllActions)
{

    Write-CMTraceLog -Message "Start creating Win32AppContent files for Intune"
    if (-not (Test-Path "$($ExportFolder)\AppDetails\AllAps.xml"))
    {
        Write-CMTraceLog -Message "File not found: `"$($ExportFolder)\AppDetails\AllAps.xml`". Run the script with the GetConfigMgrAppInfo or GetConfigMgrAppInfoAndAnalyze switch" -Severity Error
        Write-CMTraceLog -Message "End of script"
        break
    }

    [array]$appInObj = Import-Clixml -Path "$($ExportFolder)\AppDetails\AllAps.xml" | Test-ObjectProperties
    if ($appInObj.count -eq 0)
    {
        Write-CMTraceLog -Message "File: `"$("$($ExportFolder)\AppDetails\AllAps.xml")`" does not contain any app data." -Severity Warning
        Write-CMTraceLog -Message "Re-run the script with parameter: `"-Step1GetConfigMgrAppInfo`" first." -Severity Warning
        Write-CMTraceLog -Message "End of script"
        break
    }

    Write-CMTraceLog -Message "Open Out-GridView for app selection"
    $ogvTitle = "Select the apps you want to create content for"
    [array]$selectedAppsLimited = $appInObj | Select-Object -Property * -ExcludeProperty CIUniqueID, DeploymentTypes, IconId, IconPath | Out-GridView -OutputMode Multiple -Title $ogvTitle
    if ($selectedAppsLimited.count -eq 0)
    {
        Write-CMTraceLog -Message "Nothing selected. Will end script!"
        break
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
            Write-CMTraceLog -Message "You can also download the tool to: `"$ExportFolderTools`" manually"
            Write-cmTraceLog -Message "From: `"$Win32ContentPrepToolUri`""
            Write-CMTraceLog -Message "End of script"
            break
        }
    }
    # download of the IntuneWinAppUtil.exe is done
    $appCounter = 0
    # we now need the full list of properties, hence the where clause
    [array]$selectedAppList = $appInObj.Where({$_.CI_ID -in $selectedAppsLimited.CI_ID})
    #foreach($configMgrApp in $selectedAppList)
    #{
    foreach($configMgrApp in $appInObj)
    {
        if ($configMgrApp.CI_ID -notin $selectedAppsLimited.CI_ID)
        {
            # we simply skip all the apps that a user did not select
            # This way we can use the original list and do not need to create a new one, which makes the export afterwards easier
            continue
        }

        $appCounter++
        Write-Progress -Activity "Create intunewin file for ConfigMgr apps" -status "Working on app: $appCounter of $($selectedAppList.count) `"$($configMgrApp.Name)`"" -percentComplete ($appCounter / $selectedAppList.count*100)
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
            Write-CMTraceLog -Message "Will run IntuneWinAppUtil.exe to pack content. Might take a while depending on content size"
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
                Write-CMTraceLog -Message "File created successfully"
                $intuneWinFullName = $Matches.filepath -replace "'" -replace '"'
                $newName = '{0}.intunewin' -f $configMgrApp.DeploymentTypes[0].LogicalName
                $intuneWinFullNameFinal = '{0}\{1}' -f ($intuneWinFullName | Split-Path -Parent), $newName
                
                if (Test-Path $intuneWinFullNameFinal)
                {
                    Remove-Item -Path $intuneWinFullNameFinal -Force
                }

                Rename-Item -Path $intuneWinFullName -NewName $newName -Force
                $configMgrApp.IntunewinFileExists = 'Yes'
                $configMgrApp.IntunewinFilePath = $intuneWinFullNameFinal
            }
            else 
            {
                Write-CMTraceLog -Message "IntuneWinAppUtil failed to create the intunewin file." -Severity Error 
            } 
            $stdout | Out-File -FilePath $intunewinLogName -Force -Encoding unicode -ErrorAction SilentlyContinue
            $stderr | Out-File -FilePath $intunewinLogName -Append -Encoding unicode -ErrorAction SilentlyContinue

        }
        catch 
        {
            Write-CMTraceLog -Message "IntuneWinAppUtil failed to create the intunewin file." -Severity Error 
            Write-CMTraceLog -Message "$($_)"
        }
        Write-CMTraceLog -Message "More details can be found in the log here: `"$($intunewinLogName)`""
    }
    Write-Progress -Completed -Activity "Create intunewin file for ConfigMgr apps"

    # We need to write the status back to the files
    # Export the full list of apps. This will overwrite the existing files
    # In step one this is not desired to be able to get "fresh" data out of ConfigMgr
    $appfileFullName = '{0}\AllAps.xml' -f $ExportFolderAppDetails
    Out-DataFile -FilePath $appfileFullName -OutObject $appInObj 

    $appfileFullName = '{0}\AllAps.json' -f $ExportFolderAppDetails
    Out-DataFile -FilePath $appfileFullName -OutObject $appInObj

    $appfileFullName = '{0}\AllAps.csv' -f $ExportFolderAppDetails
    Out-DataFile -FilePath $appfileFullName -OutObject $appInObj
}
#endregion

#region UploadToIntune
if ($Step3UploadAppsToIntune -or $CreateIntuneWinFilesAndUploadToIntune -or $RunAllActions)
{
    Write-CMTraceLog -Message "Install required modules and start app upload to Intune for selected apps"
    Get-RequiredScriptModules -RequiredModules $RequiredModules
    
    if ([string]::IsNullOrEmpty($EntraIDAppID))
    {
        # No extra parameters needed in this case
        $paramSplatting = @{}
    }
    else
    {
        # We need to connect to graph with a specific app registration
        if ([string]::IsNullOrEmpty($EntraIDTenantID))
        {
            Write-CMTraceLog -Message "Missing paramter `"-EntraIDTenantID`" for EntraID app registration" -Severity Warning
            Write-CMTraceLog -Message "Exit script"
            Exit 1
        }
    
        $paramSplatting = @{
            ClientId = $EntraIDAppID
            TenantId = $EntraIDTenantID
        }
    }
    
    if(-NOT ($DoNotRequestScopes))
    {
        # Add the required scopes to the parameter list. This will prompt the user to consent to the scopes
        $paramSplatting.Scopes = $RequiredScopes
    }
    
    # Connect to Graph
    try 
    {
        Connect-MgGraph @paramSplatting -ErrorAction Stop    
    }
    catch 
    {
        Write-CMTraceLog -Message "An error occurred while connecting to Graph" -Severity Error
        Write-CMTraceLog -Message "$($_)" -Severity Error
        Exit 1
    }
    
    
    # Lets check if the required scopes are missing
    $scopeNotFound = $false
    foreach($scope in $RequiredScopes)
    {
        if(-not (Get-MgContext).Scopes.Contains($scope))
        {
            Write-CMTraceLog -Message "We need scope/permission: `"$scope`" to be able to run the script" -Severity Warning
            $scopeNotFound = $true
        }
    }
    
    if($scopeNotFound)
    {
        Write-CMTraceLog -Message "Exiting script as required scopes/permissions are missing. Please add the required scopes/permissions to the app registration."
        if($DoNotRequestScopes){Write-CMTraceLog -Message "Or run the script without the -DoNotRequestScopes parameter to be able to request the scopes/permissions for the app registration automatically."}
        Write-CMTraceLog -Message "Exit script"
        Exit 1
    }
    #endregion    
    

    # We need to extract some files later in the script
    try 
    {
        $null = Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction Stop
    }
    catch [System.Exception] 
    {
        Write-CMTraceLog -Message "An error occurred while loading System.IO.Compression.FileSystem assembly." -Severity Error
        Write-CMTraceLog -Message "Error message: $($_)"
        Exit 1
    }

    # Load apps from file
    if (-not (Test-Path "$($ExportFolder)\AppDetails\AllAps.xml"))
    {
        Write-CMTraceLog -Message "File not found: `"$($ExportFolder)\AppDetails\AllAps.xml`". Run the script with the GetConfigMgrAppInfo or GetConfigMgrAppInfoAndAnalyze switch" -Severity Error
        Write-CMTraceLog -Message "End of script"
        Exit 1
    }


    [array]$appInObj = Import-Clixml -Path "$($ExportFolder)\AppDetails\AllAps.xml" | Test-ObjectProperties
    if ($appInObj.count -eq 0)
    {
        Write-CMTraceLog -Message "File: `"$("$($ExportFolder)\AppDetails\AllAps.xml")`" does not contain any app data." -Severity Warning
        Write-CMTraceLog -Message "Re-run the script with parameter: `"-Step1GetConfigMgrAppInfo`" first." -Severity Warning
        Write-CMTraceLog -Message "End of script"
        Exit 0
    }

    # Lets check if the apps already exist in Intune if the parameter is set
    if ($TestForExistingApps)
    {
        Write-CMTraceLog -Message "TestForExistingApps is set. Will test for existing apps in Intune by name"
        $allExistingWin32Apps = Get-AllWin32AppNamesFromIntune
        Write-CMTraceLog -Message "Total win32 apps found in Intune: $($allExistingWin32Apps.Count)"
        foreach($configMgrApp in $appInObj)
        {
            if($configMgrApp.NameSanitized -iin $allExistingWin32Apps.DisplayName)
            {
                $configMgrApp.ExistsInIntune = 'Yes'   
            }
            else 
            {
                $configMgrApp.ExistsInIntune = 'No' 
            }
        }
    }
    # end of checking for existing apps

    Write-CMTraceLog -Message "Open Out-GridView for app selection"
    $ogvTitle = "Select the apps you want to upload to Intune"
    # The GridView will only show the needed properties to limit the amount of data shown
    [array]$selectedAppsLimited = $appInObj | Select-Object -Property * -ExcludeProperty CIUniqueID, DeploymentTypes, IconId, IconPath | Out-GridView -OutputMode Multiple -Title $ogvTitle
    if ($selectedAppsLimited.count -eq 0)
    {
        if ($TestForExistingApps)
        {
            Write-CMTraceLog -Message "Nothing selected, but `"TestForExistingApps`" is set. Will export data into files again and end script!"
            # We need to write the status back to the files
            # Export the full list of apps. This will overwrite the existing files
            # In step one this is not desired to be able to get "fresh" data out of ConfigMgr
            $appfileFullName = '{0}\AllAps.xml' -f $ExportFolderAppDetails
            Out-DataFile -FilePath $appfileFullName -OutObject $appInObj 

            $appfileFullName = '{0}\AllAps.json' -f $ExportFolderAppDetails
            Out-DataFile -FilePath $appfileFullName -OutObject $appInObj

            $appfileFullName = '{0}\AllAps.csv' -f $ExportFolderAppDetails
            Out-DataFile -FilePath $appfileFullName -OutObject $appInObj
        }
        else 
        {
            Write-CMTraceLog -Message "Nothing selected. Will end script!"
        }

        Exit 0
    }

    Write-CMTraceLog -Message "Total apps to upload to Intune: $($selectedAppsLimited.count)"   

    # Get the list of existing apps
    $appCounter = 0 
    # we now need the full list of properties, hence the where clause
    [array]$selectedAppList = $appInObj.Where({$_.CI_ID -in $selectedAppsLimited.CI_ID})
    #foreach($configMgrApp in $selectedAppList)
    #{
    foreach($configMgrApp in $appInObj)
    {
        if ($configMgrApp.CI_ID -notin $selectedAppsLimited.CI_ID)
        {
            # We simply skip all the apps that a user did not select
            # This way we can use the original list and do not need to create a new one, which makes the export afterwards easier
            continue
        }

        $appCounter++
        Write-Progress -Id 0 -Activity "Upload apps to Intune" -status "Working on app: $appCounter of $($selectedAppList.count) `"$($configMgrApp.Name)`"" -percentComplete ($appCounter / $selectedAppList.count*100)
        if ($configMgrApp.AppImportToIntunePossible -ine 'Yes')
        {
            Write-CMTraceLog -Message "App: `"$($configMgrApp.NameSanitized)`" cannot be imported into Intune. Will be skipped." -Severity Warning
            Continue
        }

        # Lets check if the file exists. Important if the export folder has been copied
        if ($configMgrApp.IntunewinFileExists -ieq 'Yes')
        {
            # lets make sure we have the right export folder
            # The path could have changed since last time the script ran
            if ($configMgrApp.IntunewinFilePath -inotmatch [regex]::Escape($ExportFolderWin32Apps))
            {
                Write-CMTraceLog -Message 'Intunewin file path does not match with export folder. Folder might be moved since file creation. Path will be replaced with current path.' -Severity Warning
                $configMgrApp.IntunewinFilePath = $configMgrApp.IntunewinFilePath -replace '^.*?Win32Apps', $ExportFolderWin32Apps     
            }

            # Lets now check if the file is there or not
            if (-Not (Test-Path $configMgrApp.IntunewinFilePath))
            {
                Write-CMTraceLog -Message 'IntunewinFile missing. App cannot be imported into Intune. Will be skipped.' -Severity Warning
                Write-CMTraceLog -Message "Expected file not found: `"$($configMgrApp.IntunewinFilePath)`"" -Severity Warning
                Continue               
            }
        }
        else 
        {
            Write-CMTraceLog -Message 'Intunewin file not yet created for app. App cannot be imported into Intune. Will be skipped.' -Severity Warning
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
            if ($configMgrApp.IconPath -inotmatch [regex]::Escape($ExportFolderIcons))
            {
                Write-CMTraceLog -Message 'Icon file path does not match with export folder. Folder might be moved since file creation. Path will be replaced with current path.' -Severity Warning
                $configMgrApp.IconPath = $configMgrApp.IconPath -replace '^.*?Icons', $ExportFolderIcons    
            }

            if (Test-Path $configMgrApp.IconPath)
            {
                Write-CMTraceLog -Message "Converting icon to base64 string for: `"$($configMgrApp.Name)`""
                try 
                {
                    $appIconEncodedBase64String = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$($configMgrApp.IconPath)"))    
                }
                catch 
                {
                    Write-CMTraceLog -Message "Icon conversion to base 64 string failed. $($_)" -Severity Warning
                    Write-CMTraceLog -Message "Error will be ignored." -Severity Warning
                }
            }
            else 
            {
                Write-CMTraceLog -Message "Icon file not found. Will skip icon upload." -Severity Warning
            }
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

        try 
        {
            # We need to extract the content of the intunewin file to get file information, metadata and the file we need to upload
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
            # remove the file as we do not need it anymore
            $intuneWinDetectionXMLFullName | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        catch 
        {
            Write-CMTraceLog -Message "An error occurred while extracting the intunewin file. $($_)" -Severity Error
            Write-CMTraceLog -Message "$($_)" -Severity Error
            Write-CMTraceLog -Message "Will skip the app: `"$($configMgrApp.Name)`""
            Continue
        }

        # Lets create the app hash table
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
                    # Lets check the path to the detection script
                    if ($appDetectionRule.ScriptFilePath -inotmatch [regex]::Escape($ExportFolderScripts))
                    {
                        Write-CMTraceLog -Message 'Script file path does not match with export folder. Folder might be moved since file creation. Path will be replaced with current path.' -Severity Warning
                        $appDetectionRule.ScriptFilePath = $appDetectionRule.ScriptFilePath -replace '^.*?Scripts', $ExportFolderScripts    
                    }

                    # Lets check if the file exists
                    if (-Not (Test-Path $appDetectionRule.ScriptFilePath))
                    {
                        Write-CMTraceLog -Message 'Script file missing. Detection rule cannot be created' -Severity Warning
                        Write-CMTraceLog -Message "Expected file not found: `"$($appDetectionRule.ScriptFilePath)`"" -Severity Warning            
                    }

                    try 
                    {
                        $ScriptContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path "$($appDetectionRule.ScriptFilePath)" -Raw -Encoding UTF8 -ErrorAction Stop)))    
                    }
                    catch 
                    {
                        Write-CMTraceLog -Message "Script conversion to base 64 string failed. $($_)" -Severity Warning
                        Write-CMTraceLog -Message 'Detection rule cannot be created' -Severity Warning
                    }
                    

                    # script detection rule
                    $DetectionRule = [ordered]@{
                        "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptDetection"
                        "enforceSignatureCheck" = $false # Note: could or should be a parameter of the script or we check for a signature block in the script
                        "runAs32Bit" = $appDetectionRule.RunAs32BitOn64BitSystem
                        "scriptContent" = $ScriptContent
                    }
                    $detectionRulesListToAdd.Add($DetectionRule)
                }
                'MSI'
                {
                    $DetectionRule = [ordered]@{
                        "@odata.type" = "#microsoft.graph.win32LobAppProductCodeDetection"
                        "productCode" = $appDetectionRule.ProductCode
                        "productVersionOperator" = "notConfigured"
                        "productVersion" = $null
                    }
                    $detectionRulesListToAdd.Add($DetectionRule)

                    # We also need to add MSI information to the app body
                    if (-NOT ($detectionXML.ApplicationInfo.MsiInfo))
                    {
                        Write-CMTraceLog -Message "MSI information not found in detection.xml. Will skip application" -Severity Warning
                        $appHashTable.msiInformation = $null
                        break # We need to break out of the loop and continue with the next app                 
                    }
                    else 
                    {
                        if ($detectionXML.ApplicationInfo.MsiInfo.MsiExecutionContext -ieq 'System')
                        {
                            $msipackageType = 'perMachine'
                        }
                        else 
                        {
                            $msipackageType = 'perUser'
                        }
                        
                        $appHashTable.msiInformation = @{
                            "productCode" = $detectionXML.ApplicationInfo.MsiInfo.MsiProductCode
                            "productVersion" = $detectionXML.ApplicationInfo.MsiInfo.MsiProductVersion
                            "upgradeCode" = $detectionXML.ApplicationInfo.MsiInfo.MsiUpgradeCode
                            "requiresReboot" = $detectionXML.ApplicationInfo.MsiInfo.MsiRequiresReboot
                            "packageType" = $msipackageType
                            "productName" = $appDetectionRule.MSIFileMetadata.ProductName
                            "publisher" = $detectionXML.ApplicationInfo.MsiInfo.MsiPublisher
                        }
                    }
                }
                'Enhanced'
                {                
                    # We need to build the detection rule from the EDM data
                    foreach ($flatRule in $appDetectionRule.RulesFlat)
                    {

                        if ($flatRule.OperatorIntune -ieq 'NotSupported')
                        {
                            Write-CMTraceLog -Message "Rule operator not supported in Intune for: `"$($flatRule.DetectionType)`". Need to skip rule" -Severity Warning
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
                                if ($flatRule.RegDataType -ieq 'String')
                                {
                                    $DetectionType = "string"
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
                                elseif ($flatRule.RegDataType -imatch '(Int64|int32)') 
                                {
                                    $DetectionType = "integer"
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
                                elseif ($flatRule.RegDataType -ieq 'Version') 
                                {
                                    $DetectionType = "version"
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
                            'FolderSetting'
                            {

                                if ($flatRule.FolderMethod -ieq 'Count')
                                {
                                    $DetectionRule = [ordered]@{
                                        "@odata.type" = "#microsoft.graph.win32LobAppFileSystemDetection"
                                        "operator" = "notConfigured"
                                        "detectionValue" = $null
                                        "path" = $flatRule.ParentFolder
                                        "fileOrFolderName" = $flatRule.FolderName
                                        "check32BitOn64System" = $flatRule.Is32BitOn64BitSystem
                                        "detectionType" = 'exists' # "doesNotExist" is not possible in ConfigMgr
                                    }
                                    $detectionRulesListToAdd.Add($DetectionRule)
                                }
                                elseif ($flatRule.FolderPropertyName -ieq 'DateModified')
                                {
                                    $DateValueString = $flatRule.FolderValue -replace 'Z', '.000Z' # '2021-06-01T00:00:00Z' -> '2021-06-01T00:00:00.000Z'
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
                                        "fileOrFolderName" = $flatRule.FolderName
                                        "check32BitOn64System" = $flatRule.Is32BitOn64BitSystem
                                        "detectionType" = "modifiedDate"
                                    }
                                    $detectionRulesListToAdd.Add($DetectionRule)
                                }
                                elseif ($flatRule.FolderPropertyName -ieq 'DateCreated')
                                {
                                    $DateValueString = $flatRule.FolderValue -replace 'Z', '.000Z' # '2021-06-01T00:00:00Z' -> '2021-06-01T00:00:00.000Z'
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
                                        "fileOrFolderName" = $flatRule.FolderName
                                        "check32BitOn64System" = $flatRule.Is32BitOn64BitSystem
                                        "detectionType" = "createdDate"
                                    }
                                    $detectionRulesListToAdd.Add($DetectionRule)
                                }
                                else 
                                {
                                    Write-CMTraceLog -Message "FolderPropertyName $($flatRule.FolderPropertyName) is not supported. Skipping rule." -Severity Warning
                                    Write-CMTraceLog -Message "Folder: $($flatRule.ParentFolder)"
                                    Write-CMTraceLog -Message "FolderName: $($flatRule.FolderName)"
                                    Write-CMTraceLog -Message "Value: $($flatRule.FolderValue)"
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


        $appfileFullName = '{0}\{1}-Intune.json' -f $ExportFolderAppDetails, $configMgrApp.LogicalName
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
            Write-CMTraceLog -Message "App JSON exported for analysis to: `"$appfileFullName`"" -Severity Warning
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
            $ContentVersionsFiles = Wait-ForGraphRequestCompletion -Uri $Win32MobileAppFilesUri -Stage 'azureStorageUriRequest'
        }

        Write-CMTraceLog -Message "Trying to upload file to Intune Azure Storage. File: $($IntunePackageFullName)"
        $ChunkSizeInBytes = 1024l * 1024l * 6l;
        $FileSize = (Get-Item -Path $IntunePackageFullName).Length
        $ChunkCount = [System.Math]::Ceiling($FileSize / $ChunkSizeInBytes)
        $BinaryReader = New-Object -TypeName System.IO.BinaryReader([System.IO.File]::Open($IntunePackageFullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite))
        $Position = $BinaryReader.BaseStream.Seek(0, [System.IO.SeekOrigin]::Begin)

        $ChunkIDs = @()
        $SASRenewalTimer = [System.Diagnostics.Stopwatch]::StartNew()
        try 
        {
            for ($Chunk = 0; $Chunk -lt $ChunkCount; $Chunk++) 
            {
                $ChunkID = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Chunk.ToString("0000")))
                $ChunkIDs += $ChunkID
                $Start = $Chunk * $ChunkSizeInBytes
                $Length = [System.Math]::Min($ChunkSizeInBytes, $FileSize - $Start)
                $Bytes = $BinaryReader.ReadBytes($Length)

                # Increment chunk to get the current chunk
                $CurrentChunk = $Chunk + 1
                
                <#
                # Test of renewal process
                if ($Chunk -eq 2)
                {
                    Write-CMTraceLog -Message "Sleeping"
                    Start-Sleep -Milliseconds 450000
                }
                #>

                # if we need to renew the SAS token if it is older than 7 minutes
                if ($currentChunk -lt $ChunkCount -and $SASRenewalTimer.ElapsedMilliseconds -ge 450000)
                {
                    Write-CMTraceLog -Message "Renewing SAS token for Azure Storage blob"
                    $SASRenewalUri = '{0}/renewUpload' -f $Win32MobileAppFilesUri

                    $paramSplatting = @{
                        Method = 'POST'
                        Uri = $SASRenewalUri
                        Body = ''
                        ContentType = "application/json"
                    }
            
                    try 
                    {
                        $Win32MobileAppFileContentRequest = Invoke-MgGraphRequest @paramSplatting
                    }
                    catch 
                    {
                        Write-CMTraceLog -Message "$($_)" -Severity Error
                        $chunkFailed = $true
                    }
                    
                    # Wait for the Win32 app file content renewal request
                    Write-CMTraceLog -Message "Waiting for Intune service to process SAS token renewal request"
                    $ContentVersionsFiles = Wait-ForGraphRequestCompletion -Uri $Win32MobileAppFilesUri -Stage 'AzureStorageUriRenewal'
                    $SASRenewalTimer.Restart()
                    # renewal done
                }
                
                $Uri = "$($ContentVersionsFiles.azureStorageUri)&comp=block&blockid=$($ChunkID)"
                $ISOEncoding = [System.Text.Encoding]::GetEncoding("iso-8859-1")
                $EncodedBytes = $ISOEncoding.GetString($Bytes)

                # We need to set the content type to "text/plain; charset=iso-8859-1" for the upload to work
                $Headers = @{
                    "content-type" = "text/plain; charset=iso-8859-1"
                    "x-ms-blob-type" = "BlockBlob"
                }
            
                Write-Progress -Id 1 -ParentId 0 -Activity "Uploading File to Azure Storage" -status "Uploading chunk $CurrentChunk of $ChunkCount" -percentComplete ($CurrentChunk / $ChunkCount*100)
                $WebResponse = Invoke-WebRequest $Uri -Method "Put" -Headers $Headers -Body $EncodedBytes -ErrorAction Stop -UseBasicParsing
            }                    
        }
        catch 
        {
            Write-CMTraceLog -Message "$($_)" -Severity Error
            Write-CMTraceLog -Message "Delete app in Intune and retry again. Will skip to the next one..." -Severity Warning
            continue
        }

        Write-Progress -Id 1 -ParentId 0 -Completed -Activity "Uploading File to Azure Storage"
        Write-CMTraceLog -Message "Uploaded all chunks to Azure Storage blob"
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
            Write-CMTraceLog "Delete app in Intune and retry again. Will skip to the next one..." -Severity Warning
            continue
        }
    
        try 
        {

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
            $uri = '{0}/commit' -f $Win32MobileAppFilesUri
            
            $paramSplatting = @{
                "Method" = 'POST'
                "Uri" = $uri
                "Body" = ($IntuneWinFileEncryptionInfo | ConvertTo-Json)
                "ContentType" = "application/json"
            }

            Write-CMTraceLog -Message "Committing the file we just uploaded"
            Write-CMTraceLog -Message "Command $($paramSplatting['Method']) to: $($paramSplatting['Uri'])" 
            $Win32MobileAppFileContentCommitRequest = Invoke-MgGraphRequest @paramSplatting -Headers $headers -ErrorAction Stop
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
            }
            Write-CMTraceLog -Message "Setting the commited content version to the app and basically binding the file to the app"
            Write-CMTraceLog -Message "Command $($paramSplatting['Method']) to: $($paramSplatting['Uri'])"
            Invoke-MgGraphRequest @paramSplatting -ErrorAction Stop

        
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
                }
                Write-CMTraceLog -Message "Command $($paramSplatting['Method']) to: $($paramSplatting['Uri'])"
                Invoke-MgGraphRequest @paramSplatting -ErrorAction Stop
            }          
        }
        catch 
        {
            Write-CMTraceLog "Error message: $($_.Exception.Message)" -Severity Error
            Write-CMTraceLog "Delete app in Intune and retry again. Will skip to the next one..." -Severity Warning
            continue
        }
        $configMgrApp.Uploaded = 'Yes'
        # remove $IntunePackageFullName because we do not need it anymore
        $IntunePackageFullName | Remove-Item -Force -ErrorAction SilentlyContinue
    }   
    Write-Progress -Id 0 -Completed -Activity "Upload apps to Intune"    

    # We need to write the status back to the files
    # Export the full list of apps. This will overwrite the existing files
    # In step one this is not desired to be able to get "fresh" data out of ConfigMgr
    $appfileFullName = '{0}\AllAps.xml' -f $ExportFolderAppDetails
    Out-DataFile -FilePath $appfileFullName -OutObject $appInObj 

    $appfileFullName = '{0}\AllAps.json' -f $ExportFolderAppDetails
    Out-DataFile -FilePath $appfileFullName -OutObject $appInObj

    $appfileFullName = '{0}\AllAps.csv' -f $ExportFolderAppDetails
    Out-DataFile -FilePath $appfileFullName -OutObject $appInObj

}

Write-CMTraceLog -Message "End of script"
Write-CMTraceLog -Message "Runtime: $([math]::Round($stoptWatch.Elapsed.TotalMinutes)) minutes and $([math]::Round($stoptWatch.Elapsed.Seconds)) seconds"
$stoptWatch.Stop()



