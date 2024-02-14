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
$global:SiteCode = "P02" # Site code 
$global:ProviderMachineName = "CM02.contoso.local" # SMS Provider machine name

$global:ExportRootFolder = 'E:\EXPORT' 



if (-NOT (Test-Path "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"))
{
    Write-Host "ConfigurationManager.psd1 not found. Stopping script"
    Exit 1   
}



$global:FullExportFolderName = '{0}\{1}' -f $ExportRootFolder, (Get-date -Format 'yyyyMMdd-hhmm')
# Validate path and create if not there yet
if (-not (Test-Path $global:FullExportFolderName)) 
{
    New-Item -ItemType Directory -Path $FullExportFolderName -Force | Out-Null
}

# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Do not change anything below this line

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams

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
    return ($FileName -replace '[\\/:*?"<>|]', '_')
}


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
Get-ConfigMgrObjectLocation
{
    param
    (
        $SiteServer = $global:SiteCode, 
        $SiteCode = $global:ProviderMachineName, 
        $ObjectUniqueID, 
        $ObjectTypeName 
    )

    $fullFolderPath = ""
    [array]$containerNode = Get-WmiObject -Namespace "root/SMS/site_$($SiteCode)" -ComputerName $SiteServer -Query "SELECT ocn.* FROM SMS_ObjectContainerNode AS ocn JOIN SMS_ObjectContainerItem AS oci ON ocn.ContainerNodeID=oci.ContainerNodeID WHERE oci.InstanceKey='$ObjectUniqueID' and oci.ObjectTypeName ='$ObjectTypeName'"
    if ($containerNode)
    {
        if ($containerNode.count -gt 1)
        {
            Write-Host "Unusual amount of folder nodes found: $($containerNodes.count)"
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

        $fullFolderPath = 'Root\{0}' -f $fullFolderPath

        return $fullFolderPath
    }
    return 'Root'
}


function Export-CMItemCustomFunction
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [object[]]$cmItems
    )

    Begin
    {
    }
    Process
    {
        $item = $_ # $_ coming from pipeline
        $itemObjectTypeName = $item.SmsProviderObjectPath -replace '\..*'

        # We might need to read data from different properties
        switch ($itemObjectTypeName)
        {
            'SMS_ConfigurationItemLatest'
            {
                # We need a folder to store CIs in
                $itemExportRootFolder = '{0}\CI' -f $global:FullExportFolderName
                if (-not (Test-Path $itemExportRootFolder)) 
                {
                    New-Item -ItemType Directory -Path $itemExportRootFolder -Force | Out-Null
                }

                $itemModelName = $item.ModelName
                $itemFileExtension = '.cab'
                $itemFileName = (Sanitize-FileName -FileName ($item.LocalizedDisplayName))
            }
            'SMS_ConfigurationBaselineInfo'
            {
                # We need a folder to store baselines in
                $itemExportRootFolder = '{0}\Baseline' -f $global:FullExportFolderName
                if (-not (Test-Path $itemExportRootFolder)) 
                {
                    New-Item -ItemType Directory -Path $itemExportRootFolder -Force | Out-Null
                }

                $itemModelName = $item.ModelName
                $itemFileExtension = '.cab'
                $itemFileName = (Sanitize-FileName -FileName ($item.LocalizedDisplayName))
            }
            'SMS_TaskSequencePackage'
            {
                # We need a folder to store TaskSequences in
                $itemExportRootFolder = '{0}\TS' -f $global:FullExportFolderName
                if (-not (Test-Path $itemExportRootFolder)) 
                {
                    New-Item -ItemType Directory -Path $itemExportRootFolder -Force | Out-Null
                }

                $itemModelName = $item.PackageID
                $itemFileExtension = '.zip'
                $itemFileName = (Sanitize-FileName -FileName ($item.Name))
            }
            'SMS_AntimalwareSettings'
            {
                # We need a folder to store AntimalwarePolicies in
                $itemExportRootFolder = '{0}\AntimalwarePolicy' -f $global:FullExportFolderName
                if (-not (Test-Path $itemExportRootFolder)) 
                {
                    New-Item -ItemType Directory -Path $itemExportRootFolder -Force | Out-Null
                }

                $itemModelName = $item.SettingsID
                $itemFileExtension = '.xml'
                $itemFileName = (Sanitize-FileName -FileName ($item.Name))            
            }
            'SMS_Scripts'
            {
                # We need a folder to store AntimalwarePolicies in
                $itemExportRootFolder = '{0}\Scripts' -f $global:FullExportFolderName
                if (-not (Test-Path $itemExportRootFolder)) 
                {
                    New-Item -ItemType Directory -Path $itemExportRootFolder -Force | Out-Null
                }

                $itemModelName = $item.ScriptGuid
                $itemFileExtension = '.ps1'
                # we will also export the whole script definition as json, just in case
                $itemFileName = (Sanitize-FileName -FileName ($item.ScriptName))                
            
            }
            Default 
            {
                #Write-Host 'Type not supported. Skip item'
                # Happens typically for antimalwarepolicies, since the default policy has a different type
                return
            }
        }

        # Lets get the ConfigMgr path
        $paramSplatting = @{
            ObjectUniqueID = $itemModelName
            ObjectTypeName = $itemObjectTypeName
        }    
        $cmConsoleFolderPath = Get-ConfigMgrObjectLocation @paramSplatting

        # Now lets map the ConfigMgr folder to a filesystem folder
        if ($cmConsoleFolderPath -ieq 'root')
        {
            $itemExportFolder = $itemExportRootFolder
        }
        else
        {
            $itemExportFolder = '{0}\{1}' -f $itemExportRootFolder, ($cmConsoleFolderPath -replace '^root\\')
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

        if ($itemFullName.Length -ge 254)
        {
            Write-Output "Path too long: $itemFullName"    
        }
        else
        {
            switch ($itemObjectTypeName)
            {
                'SMS_ConfigurationItemLatest'
                {
                    Export-CMConfigurationItem -Id $item.CI_ID -Path $itemFullName
                }
                'SMS_ConfigurationBaselineInfo'
                {
                    Export-CMBaseline -Id $item.CI_ID -Path $itemFullName
                }
                'SMS_TaskSequencePackage'
                {
                    Export-CMTaskSequence -TaskSequencePackageId $item.PackageID -ExportFilePath $itemFullName
                }
                'SMS_AntimalwareSettings'
                {
                    Export-CMAntimalwarePolicy -id $item.SettingsID -Path $itemFullName
                }
                'SMS_Scripts'
                {
                    # we need to filter out the default CMPivot script
                    if($item.ScriptName -ine 'CMPivot')
                    {
                        $ScriptContent = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($item.Script))
                        
                        $ScriptContent | Out-File -Encoding unicode -FilePath $itemFullName

                        $selectProperties = @('ApprovalState',
                                                'Approver',
                                                'Author',
                                                'Comment',
                                                'Feature',
                                                'LastUpdateTime',
                                                'ParameterGroupHash',
                                                'Parameterlist',
                                                'ParameterlistXML',
                                                'ParamsDefinition',
                                                'Script',
                                                'ScriptDescription',
                                                'ScriptGuid',
                                                'ScriptHash',
                                                'ScriptHashAlgorithm',
                                                'ScriptName',
                                                'ScriptType',
                                                'ScriptVersion',
                                                'Timeout')

                        ($item | Select-Object -Property $selectProperties | ConvertTo-Json -Depth 4) | Out-File -FilePath ($itemFullName -replace 'ps1', 'json')
                    
                    }
                        
                }
                Default {}
            }
            
        }

    }
    End
    {
    }
}



Get-CMConfigurationItem -Fast | Export-CMItemCustomFunction

Get-CMBaseline -Fast | Export-CMItemCustomFunction

Get-CMTaskSequence -Fast | Export-CMItemCustomFunction

Get-CMAntimalwarePolicy | Export-CMItemCustomFunction

Get-CMScript -WarningAction Ignore | Export-CMItemCustomFunction

