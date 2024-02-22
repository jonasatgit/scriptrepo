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
$global:Spacer = '-'


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

        $fullFolderPath = '\{0}' -f $fullFolderPath

        return $fullFolderPath
    }
    return '\'
}

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

    Begin
    {
    }
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

                    # Configitems dont come with an object path
                    # The object path would contain the path in the ConfigMgr console
                    $paramSplatting = @{
                         ObjectUniqueID = $itemModelName
                         ObjectTypeName = $itemObjectTypeName
                    }    
                    $item.ObjectPath = Get-ConfigMgrObjectLocation @paramSplatting
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
                #Write-Host 'Type not supported. Skip item'
                # Happens typically for antimalwarepolicies, since the default policy has a different type
                return
            }
        }

        # We might need to create the folder first
        if (-not (Test-Path $itemExportRootFolder)) 
        {
            New-Item -ItemType Directory -Path $itemExportRootFolder -Force | Out-Null
        }


        # If ObjectPath has no value or just a "/" the item is at the root level
        if (([string]::IsNullOrEmpty($item.ObjectPath)) -or ($item.ObjectPath -eq '/') -or ($item.ObjectPath -eq '\'))
        {
            $itemExportFolder = $itemExportRootFolder
        }
        else
        {
            $itemExportFolder = '{0}\{1}' -f $itemExportRootFolder, $item.ObjectPath -replace '/', '\'
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

        # File names for extra info
        $metadataFileName = '{0}\{1}.metadata.xml' -f ($itemFullName | Split-Path -Parent), ([System.IO.Path]::GetFileNameWithoutExtension($itemFullName))
        $deploymentsFileName = '{0}\{1}.deployments.xml' -f ($itemFullName | Split-Path -Parent), ([System.IO.Path]::GetFileNameWithoutExtension($itemFullName))


        # Lets put the file info in a little inventory file
        $inventoryFile = '{0}\_Inventory.txt' -f $itemExportRootFolder
        "Name:   $($itemFullName | Split-Path -Leaf)" | Out-File -FilePath $inventoryFile -Append
        "Path:   $($itemFullName)" | Out-File -FilePath $inventoryFile -Append
        "ItemID:   $($itemModelName)" | Out-File -FilePath $inventoryFile -Append
        ($global:Spacer * 50) | Out-File -FilePath $inventoryFile -Append

        # Path might be too long 
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

                    # Lets also export medatdata
                    $item | Export-Clixml -Depth 100 -Path $metadataFileName
                }
                'SMS_ConfigurationBaselineInfo'
                {
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
                    Export-CMTaskSequence -TaskSequencePackageId $item.PackageID -ExportFilePath $itemFullName

                    # Lets also export medatdata
                    $item | Export-Clixml -Depth 100 -Path $metadataFileName

                    $tsDeployments = Get-CMTaskSequenceDeployment -TaskSequenceId $item.PackageID -WarningAction Ignore -ErrorAction SilentlyContinue
                    if ($tsDeployments)
                    {
                        $tsDeployments | Export-Clixml -Depth 100 -Path $deploymentsFileName 
                    }

                }
                'SMS_AntimalwareSettings'
                {
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
                'SMS_ClientSettings'
                {
                    
                    # Lets also export medatdata
                    $item | Export-Clixml -Depth 100 -Path $metadataFileName

                    $settingsDeployments = Get-CMClientSettingDeployment -Id $item.SettingsID -ErrorAction SilentlyContinue
                    if ($settingsDeployments)
                    {
                        $settingsDeployments | Export-Clixml -Depth 100 -Path $deploymentsFileName 
                    }

                    foreach($agentConfig in $item.Properties.AgentConfigurations)
                    {

                        # We need to load more data about hardware inventory classes
                        if ($agentConfig.AgentID -eq 15)
                        {

                            "Settingstype:" | Out-File -FilePath $itemFullName -Append
                            ($agentConfig.SmsProviderObjectPath -replace '\..*') | Out-File -FilePath $itemFullName -Append                   
                            $agentConfig | Out-File -FilePath $itemFullName -Append

                            $wmiQuery = "Select * from SMS_InventoryReport where InventoryReportID = '$($agentConfig.InventoryReportID)'"
                            try{$inventoryReport = Get-CimInstance -ComputerName $global:ProviderMachineName -Namespace "root\sms\site_$global:SiteCode" -Query $wmiQuery -ErrorAction Stop}catch{}
                            if ($inventoryReport)
                            {
                                # load lazy properties
                                $inventoryReport = $inventoryReport | Get-CimInstance
                                
                                foreach ($reportClass in $inventoryReport.ReportClasses)
                                {
                                    ($global:Spacer * 20) | Out-File -FilePath $itemFullName -Append
                                    "Activated report class: $($reportClass.SMSClassID)" | Out-File -FilePath $itemFullName -Append
                                    $reportClass.ReportProperties | Out-File -FilePath $itemFullName -Append
                                }

                            }
                            " " | Out-File -FilePath $itemFullName -Append
                            " " | Out-File -FilePath $itemFullName -Append
                            ($global:Spacer * 50) | Out-File -FilePath $itemFullName -Append

                        }
                        else
                        {
                            "Settingstype:" | Out-File -FilePath $itemFullName -Append
                            ($agentConfig.SmsProviderObjectPath -replace '\..*') | Out-File -FilePath $itemFullName -Append                   
                            $agentConfig | Out-File -FilePath $itemFullName -Append
                            ($global:Spacer * 50) | Out-File -FilePath $itemFullName -Append
                        }

                    }            
                
                }
                'SMS_ConfigurationPolicy'
                {
                    # Lets also export medatdata
                    $item | Export-Clixml -Depth 100 -Path $metadataFileName

                    $configDeployments = Get-CMConfigurationPolicyDeployment -SmsObjectId $item.CI_ID -ErrorAction SilentlyContinue -WarningAction Ignore
                    if ($configDeployments)
                    {
                        $configDeployments | Export-Clixml -Depth 100 -Path $deploymentsFileName 
                    }


                    Get-CMConfigurationPolicy -Id $item.CI_ID -AsXml -WarningAction Ignore | Out-File -FilePath $itemFullName -Append

                    <#
                    # need to load lazy properties
                    #$item = $item.get()
                    $itemWithLazyProperties = Get-CMConfigurationPolicy -Id $item.CI_ID -WarningAction Ignore
                    [xml]$SDMPackageXML = $itemWithLazyProperties.SDMPackageXML
                    #$SDMPackageXML | Out-File -FilePath $itemFullName -Append
                    $SDMPackageXML.Save($itemFullName)
                    #>
                    
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

Get-CMClientSetting | Export-CMItemCustomFunction

Get-CMConfigurationPolicy -Fast | Export-CMItemCustomFunction


