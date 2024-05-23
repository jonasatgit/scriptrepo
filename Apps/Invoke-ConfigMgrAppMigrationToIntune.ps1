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

param
(
    [string]$SiteCode = "P02", # Site code 
    [string]$ProviderMachineName = "CM02.contoso.local", # SMS Provider machine name
    [string]$ExportFolder = 'C:\ExportToIntune',
    [string]$Win32ContentPrepToolUri = 'https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe',
    [string]$AzCopyUri = "https://aka.ms/downloadazcopy-v10-windows",
    [bool]$CreateIntuneWinFiles = $true
)


$LogFilePath = '{0}\{1}.log' -f $PSScriptRoot ,($MyInvocation.MyCommand -replace '.ps1')

#region admin rights
#Ensure that the Script is running with elevated permissions
if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Warning 'The process needs admin rights to run. Please re-run the process with admin rights.' 
    Read-Host -Prompt "Press any key to exit"
    Exit 0 
}
#endregion

# we need to extract some files
try {
    $ClassImport = Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction Stop -Verbose:$false
}
catch [System.Exception] {
    Write-Warning -Message "An error occurred while loading System.IO.Compression.FileSystem assembly. Error message: $($_.Exception.Message)"; break
}

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
                Write-Host -Message "Intune service request for operation '$($operation)' is in pending state, sleeping for 10 seconds"
                Start-Sleep -Seconds 10
            }
            "Failed" 
            {
                Write-Warning -Message "Intune service request for operation '$($operation)' failed"
                return $GraphRequest
            }
            "TimedOut" 
            {
                Write-Warning -Message "Intune service request for operation '$($operation)' timed out"
                return $GraphRequest
            }
        }
    }
    until ($uploadState -ilike "Success")
    Write-Host -Message "Intune service request for operation '$($operation)' was successful with uploadState: $($GraphRequest.uploadState)"

    return $GraphRequest
}
#endregion


#region load ConfigMgrmodules
$stoptWatch = New-Object System.Diagnostics.Stopwatch
$stoptWatch.Start()

Rollover-Logfile -Logfile $Global:LogFilePath -MaxFileSizeKB 2048

Write-CMTraceLog -Message '   '
Write-CMTraceLog -Message 'Start of script'

# Validate path and create if not there yet
if (-not (Test-Path $ExportFolder)) 
{
    Write-CMTraceLog -Message "Export folder: `"$($ExportFolder)`" does not exist. Will be created..."
    New-Item -ItemType Directory -Path $ExportFolder -Force | Out-Null
}
Write-CMTraceLog -Message "Export will be made to folder: $($ExportFolder)"

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
        Write-CMTraceLog -Message "Will create export folder: `"$($folder)`""
        New-Item -ItemType Directory -Path $folder -Force | Out-Null   
    }
    else 
    {
        Write-CMTraceLog -Message "Folder: `"$($folder)`" does exit"
    }
}

# lets download the content prep tool
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
    }
}

<#
# lets download the AzCopy Tool
$azCopyFullName = '{0}\AzCopy.exe' -f $ExportFolderTools
$azCopyZipFullName = '{0}\AzCopy.zip' -f $ExportFolderTools
if (Test-Path $azCopyFullName)
{
    Write-CMTraceLog -Message "AzCopy.exe already present. No need to download"
}
else 
{    
    try 
    {
        Write-CMTraceLog -Message "Will try to download AzCopy.exe"
        Invoke-WebRequest -UseBasicParsing -Method Get -Uri $AzCopyUri -OutFile $azCopyZipFullName -ErrorAction SilentlyContinue

        if (-not (Test-Path $azCopyZipFullName))
        {
            Write-CMTraceLog -Message "AzCopy.exe download failed" -Severity Error
        }
        else 
        {
            # Lets unpack
            $azCopyZipObject = [System.IO.Compression.ZipFile]::OpenRead($azCopyZipFullName)
            $azCopyZipObject.Entries | Where-Object {$_.Name -ieq 'AzCopy.exe'} | ForEach-Object {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, $azCopyFullName, $true)
            }
            $azCopyZipObject.Dispose()

            if (-not (Test-Path $azCopyFullName))
            {
                Write-CMTraceLog -Message "AzCopy.exe unpack failed" -Severity Error
            }
                
        }
    }
    catch 
    {
        Write-CMTraceLog -Message "AzCopy.exe download failed" -Severity Error
        Write-CMTraceLog -Message "$($_)"
    }
}
#>


$GetConfigMgrApps = $true
if ($GetConfigMgrApps)
{

    Write-CMTraceLog -Message 'Will load ConfigurationManager.psd1'
    # Lets make sure we have the ConfigMgr modules
    if (-NOT (Test-Path "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"))
    {
        Write-CMTraceLog -Message 'ConfigurationManager.psd1 not found. Stopping script' -Severity Error
        Exit 1   
    }
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

    #$appQuery = 'Select * from SMS_App'
    #Get-CimInstance -Namespace "Root\SMS\Site_$($SiteCode)" -Query 

    <#
    ApplicabilityCondition	
    CategoryInstance_UniqueIDs	
    CIType_ID	
    CIVersion	
    CI_ID	
    CI_UniqueID	
    ConfigurationFlags	
    CreatedBy	
    DateCreated	
    DateLastModified	
    EffectiveDate	
    EULAAccepted	
    EULAExists	
    EULASignoffDate	
    EULASignoffUser	
    ExecutionContext	
    Featured	
    HasContent	
    IsBundle	
    IsDeployable	
    IsDeployed	
    IsDigest	
    IsEnabled	
    IsExpired	
    IsHidden	
    IsLatest	
    IsQuarantined	
    IsSuperseded	
    IsSuperseding	
    IsUserDefined	
    IsVersionCompatible	
    LastModifiedBy	
    LocalizedCategoryInstanceNames	
    LocalizedDescription	
    LocalizedDisplayName	
    LocalizedInformativeURL	
    LocalizedPropertyLocaleID	
    LogonRequirement	
    Manufacturer	
    ModelID	
    ModelName	
    NumberOfApplicationGroups	
    NumberOfDependentDTs	
    NumberOfDependentTS	
    NumberOfDeployments	
    NumberOfDeploymentTypes	
    NumberOfDevicesWithApp	
    NumberOfDevicesWithFailure	
    NumberOfSettings	
    NumberOfUsersWithApp	
    NumberOfUsersWithFailure	
    NumberOfUsersWithRequest	
    NumberOfVirtualEnvironments	
    PackageID	
    PermittedUses	
    PlatformCategoryInstance_UniqueIDs	
    PlatformType	
    PSComputerName	
    PSShowComputerName	
    SDMPackageLocalizedData	
    SDMPackageVersion	
    SDMPackageXML	
    SecuredScopeNames	
    SedoObjectVersion	
    SmsProviderObjectPath	
    SoftwareVersion	
    SourceCIVersion	
    SourceModelName	
    SourceSite	
    SummarizationTime	
    #>

    $appOutObj = [System.Collections.Generic.List[pscustomobject]]::new()
    #region get ConfigMgrApps and show them in a grudview
    $allApps = Get-CMApplication -Fast -ErrorAction SilentlyContinue
    if ($null -eq $allApps)
    {
        Write-CMTraceLog -Message "No applications found in ConfigMgr" -Severity Warning
        Exit 1
    }
    else 
    {
        Write-CMTraceLog -Message "Open Out-GridView for app selection"
        $ogvTitle = "Select the apps you want to export to Intune"
        [array]$selectedApps = $allApps | Select-Object -Property $arrayOfDisplayedProperties | Out-GridView -OutputMode Multiple -Title $ogvTitle
    }
    Write-CMTraceLog -Message "Total selected apps: $(($selectedApps).count)"
    #Lets now get some info about the app
    if ($selectedApps)
    {
        foreach ($app in $selectedApps)
        {
            $fullApp = Get-CMApplication -Id $app.CI_ID

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

            $tmpApp = [PSCustomObject]@{
                LogicalName = $appXmlContent.AppMgmtDigest.Application.LogicalName
                Name = $appXmlContent.AppMgmtDigest.Application.title.'#text'
                NameSanitized = Get-SanitizedString -String ($appXmlContent.AppMgmtDigest.Application.title.'#text')
                CIVersion = $fullApp.CIVersion
                SoftwareVersion = $fullApp.SoftwareVersion
                CI_ID = $fullApp.CI_ID
                CI_UniqueID = $fullApp.CI_UniqueID
                DeploymentTypesTotal = $fullApp.NumberOfDeploymentTypes
                IsSuperseded = $fullApp.IsSuperseded
                IsSuperseding = $fullApp.IsSuperseding
                Description = $appXmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Description
                Tags = $appXmlContent.AppMgmtDigest.Application.DisplayInfo.Tags.Tag
                Publisher = $appXmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Publisher
                ReleaseDate = $appXmlContent.AppMgmtDigest.Application.DisplayInfo.Info.ReleaseDate
                InfoUrl = $appXmlContent.AppMgmtDigest.Application.DisplayInfo.Info.InfoUrl
                IconId = $appXmlContent.AppMgmtDigest.Resources.Icon.Id
                IconPath = $IconPath
                DeploymentTypes = $null
                #IconData = $appXmlContent.AppMgmtDigest.Resources.Icon.Data
                
            }

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
                        ExecuteTime = $deploymentType.Installer.CustomData.ExecuteTime
                        MaxExecuteTime = $deploymentType.Installer.CustomData.MaxExecuteTime
                        RequirementsCount = $requirementsCount
                        HasDependency = $hasDependency
                        ExeToCloseBeforeExecution = $appDeploymenTypesExeList # No Intune support
                        CustomReturnCodes = $appDeploymenTypesCustomExitCodeList
                        Requirements = $null
                        DetectionRules = $null

                    }

                    # In case we do not have a content path and instead the install or unonstall points to a share, correct that
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
                        Write-CMTraceLog -Message "The script does only support the operating system requirement. Any other requirements need to be set manually in Intune!" -Severity Warning

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
                            ScriptBody       String  if((Test-Path 'HKLM:\SOFTWARE\Installed\Notepad++') {Write-Host 'Installed'}
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
                            $tmpDetectionItem.ScriptFilePath = $scriptFilePath
                            $tmpDetectionItem.RunAs32BitOn64BitSystem = $runAs32BitOn64BitSystem


                        }
                        'MSI' 
                        {

                            $tmpDetectionItem.Type = 'MSI'
                            $tmpDetectionItem.TypeIntune = 'AppDetectionRuleMSI'
                            # Code missind


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

            $appfileFullName = '{0}\{1}.xml' -f $ExportFolderAppDetails, $tmpApp.LogicalName
            $tmpApp | Export-Clixml -Path $appfileFullName -Depth 100

            $appfileFullName = '{0}\{1}.json' -f $ExportFolderAppDetails, $tmpApp.LogicalName
            $tmpApp | ConvertTo-Json -Depth 100 | Out-File -FilePath $appfileFullName -Encoding unicode
            
            $appOutObj.Add($tmpApp)



        }

    }
    $appOutObj[0] | ConvertTo-Json -Depth 20

    $appfileFullName = '{0}\AllAps.xml' -f $ExportFolderAppDetails
    $appOutObj | Export-Clixml -Path $appfileFullName -Depth 100

    $appfileFullName = '{0}\AllAps.json' -f $ExportFolderAppDetails
    $appOutObj | ConvertTo-Json -Depth 100 | Out-File -FilePath $appfileFullName -Encoding unicode

    # lets now build the intunewin file from the install content
    # We need to ignore the uninstall content for now, because there is no Intune support as of now
    
    #$appOutObj = Import-Clixml -Path "C:\ExportToIntune\AppDetails\AllAps.xml"

}


