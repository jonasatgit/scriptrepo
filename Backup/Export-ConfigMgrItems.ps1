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
    
.EXAMPLE
    Export-ConfigMgrItems.ps1
#>

# Site configuration
[string]$global:SiteCode = "P02" # Site code 
[string]$global:ProviderMachineName = "CM02.contoso.local" # SMS Provider machine name
[string]$global:ExportRootFolder = 'E:\EXPORT' 
[int]$MaxExportFolderAgeInDays = 10
[int]$MinExportFoldersToKeep = 2
# In case we only have older folders and would therefore delete them
# $MinExportFoldersToKeep will make sure we will keep at least some of them and not end up with nothing

# Do not change
$global:Spacer = '-'
$Global:LogFilePath = $Global:LogFilePath = '{0}\{1}.log' -f $PSScriptRoot ,($MyInvocation.MyCommand -replace '.ps1')
$global:FullExportFolderName = '{0}\{1}' -f $ExportRootFolder, (Get-date -Format 'yyyyMMdd-hhmm')
$global:ExitWithError = $false

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
            Write-CMTraceLog -Message "Will delete: $($item.FullName) since it is $($timeSpan.TotalDays) days old"
            try
            {
                Remove-Item $item.FullName -Recurse -Force -ErrorAction Stop
            }
            Catch
            {
                Write-CMTraceLog -Message "Not able to delete: $($item.FullName)" -Severity Error
                Write-CMTraceLog -Message "$($_)" -Severity Error
                $global:ExitWithError = $true   
            }
        }
    }
}
#endregion


#region function Sanitize-Path
<#
.SYNOPSIS
    Function to replace invalid characters with underscore to be able to export data in folders
#>
function Sanitize-Path
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

#region function Sanitize-FileName
<#
.SYNOPSIS
    Function to replace invalid characters with underscore to be able to export data in folders
#>
function Sanitize-FileName
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
        $SiteServer = $global:ProviderMachineName, 
        $SiteCode = $global:SiteCode, 
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
                    $itemExportRootFolder = '{0}\CI' -f $global:FullExportFolderName
                    $itemModelName = $item.ModelName
                    $itemFileExtension = '.cab'
                    $itemFileName = (Sanitize-FileName -FileName ($item.LocalizedDisplayName))
                }
            }
            'SMS_ConfigurationBaselineInfo'
            {
                # We need a folder to store baselines in
                $itemExportRootFolder = '{0}\Baseline' -f $global:FullExportFolderName
                $itemModelName = $item.ModelName
                $itemFileExtension = '.cab'
                $itemFileName = (Sanitize-FileName -FileName ($item.LocalizedDisplayName))
            }
            'SMS_TaskSequencePackage'
            {
                # We need a folder to store TaskSequences in
                $itemExportRootFolder = '{0}\TS' -f $global:FullExportFolderName
                $itemModelName = $item.PackageID
                $itemFileExtension = '.zip'
                $itemFileName = (Sanitize-FileName -FileName ($item.Name))
            }
            'SMS_AntimalwareSettings'
            {
                # We need a folder to store AntimalwarePolicies in
                $itemExportRootFolder = '{0}\AntimalwarePolicy' -f $global:FullExportFolderName
                $itemModelName = $item.SettingsID
                $itemFileExtension = '.xml'
                $itemFileName = (Sanitize-FileName -FileName ($item.Name))       
                $skipConfigMgrFolderSearch = $true     
            }
            'SMS_Scripts'
            {
                # We need a folder to store AntimalwarePolicies in
                $itemExportRootFolder = '{0}\Scripts' -f $global:FullExportFolderName
                $itemModelName = $item.ScriptGuid
                $itemFileExtension = '.ps1'
                # we will also export the whole script definition as json, just in case
                $itemFileName = (Sanitize-FileName -FileName ($item.ScriptName))        
                $skipConfigMgrFolderSearch = $true        
            
            }
            'SMS_ClientSettings'
            {
                # We need a folder to store AntimalwarePolicies in
                $itemExportRootFolder = '{0}\ClientSettings' -f $global:FullExportFolderName
                $itemModelName = $item.Name
                $itemFileExtension = '.txt'
                # we will also export the whole script definition as json, just in case
                $itemFileName = (Sanitize-FileName -FileName ($item.Name))       
                $skipConfigMgrFolderSearch = $true                 
            }
            'SMS_ConfigurationPolicy'
            {
                if ($item.CategoryInstance_UniqueIDs -imatch 'SMS_BitlockerManagementSettings')
                {
                    $itemExportRootFolder = '{0}\BitlockerPolicies' -f $global:FullExportFolderName
                    $itemModelName = $item.LocalizedDisplayName
                    $itemFileExtension = '.xml'
                    $itemFileName = (Sanitize-FileName -FileName ($item.LocalizedDisplayName))
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
        $itemExportFolder = Sanitize-Path -Path $itemExportFolder

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
            ($global:Spacer * 50) | Out-File -FilePath $inventoryFile -Append

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
                        $tsRefData = Get-CimInstance -ComputerName $global:ProviderMachineName -Namespace "root\sms\site_$global:SiteCode" -Query $wmiQuery -ErrorAction SilentlyContinue
                        if ($tsRefData)
                        {
                            $tsRefData | Export-Clixml -Path $tsReferenceFileName
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
                            $inventoryReport = Get-CimInstance -ComputerName $global:ProviderMachineName -Namespace "root\sms\site_$global:SiteCode" -Query $wmiQuery -ErrorAction SilentlyContinue
                            if ($inventoryReport)
                            {
                                # load lazy properties
                                $inventoryReport = $inventoryReport | Get-CimInstance
                                $inventoryReport | Export-Clixml -Depth 100 -Path $inventoryFileName
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
                 Write-CMTraceLog -Message "Error exporting: $($itemFullName)" -Severity Error
                 Write-CMTraceLog -Message "$($_)" -Severity Error
                 $global:ExitWithError = $true
            }
        }
    }
    End{}
}
#endregion 

#region load ConfigMgr modules
$stoptWatch = New-Object System.Diagnostics.Stopwatch
$stoptWatch.Start()

Rollover-Logfile -Logfile $Global:LogFilePath -MaxFileSizeKB 2048

Write-CMTraceLog -Message '   '
Write-CMTraceLog -Message 'Start of script'

# Lets cleanup first
Remove-OldExportFolders -RootPath $global:ExportRootFolder -MaxExportFolderAgeInDays $MaxExportFolderAgeInDays -MinExportFoldersToKeep $MinExportFoldersToKeep

Write-CMTraceLog -Message 'Will load ConfigurationManager.psd1'
# Lets make sure we have the ConfigMgr modules
if (-NOT (Test-Path "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"))
{
    Write-CMTraceLog -Message 'ConfigurationManager.psd1 not found. Stopping script' -Severity Error
    Exit 1   
}


# Validate path and create if not there yet
if (-not (Test-Path $global:FullExportFolderName)) 
{
    New-Item -ItemType Directory -Path $FullExportFolderName -Force | Out-Null
}

Write-CMTraceLog -Message "Export will be made to folder: $($global:FullExportFolderName)"

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
Get-CMConfigurationItem -Fast | Export-CMItemCustomFunction

Get-CMBaseline -Fast | Export-CMItemCustomFunction

Get-CMTaskSequence -Fast | Export-CMItemCustomFunction

Get-CMAntimalwarePolicy | Export-CMItemCustomFunction

Get-CMScript -WarningAction Ignore | Export-CMItemCustomFunction

Get-CMClientSetting | Export-CMItemCustomFunction

Get-CMConfigurationPolicy -Fast | Export-CMItemCustomFunction


$stoptWatch.Stop()
$scriptDurationString = "Script runtime: {0}h:{1}m:{2}s" -f $stoptWatch.Elapsed.Hours, $stoptWatch.Elapsed.Minutes, $stoptWatch.Elapsed.Seconds
Write-CMTraceLog -Message $scriptDurationString

if ($global:ExitWithError)
{

    Write-CMTraceLog -Message 'Script ended with errors' -Severity Warning
}
else
{
    Write-CMTraceLog -Message 'Script ended successfull'
}
#endregion
