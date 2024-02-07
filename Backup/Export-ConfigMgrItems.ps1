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
$SiteCode = "P02" # Site code 
$ProviderMachineName = "CM02.contoso.local" # SMS Provider machine name
$ExportRootFolder = 'E:\EXPORT' 

if (-NOT (Test-Path "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"))
{
    Write-Host "ConfigurationManager.psd1 not found. Stopping script"
    Exit 1   
}



$FullExportFolderName = '{0}\{1}' -f $ExportRootFolder, (Get-date -Format 'yyyyMMdd-hhmm')

# Validate path and create if not there yet
if (-not (Test-Path $FullExportFolderName)) 
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
        $SiteServer, # = $env:COMPUTERNAME,
        $SiteCode, #= 'P02',
        $ObjectUniqueID, # = $listOfConfigItems[7].ModelName, #$listOfUnusedConfigItems[1].ModelName,
        $ObjectTypeName # = $listOfConfigItems[7].SmsProviderObjectPath -replace '\..*' #$listOfUnusedConfigItems[1].SmsProviderObjectPath -replace '\..*'
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


#region Configuration Items
# We need a folder to store CIs in
$ciExportRootFolder = '{0}\CI' -f $FullExportFolderName
if (-not (Test-Path $ciExportRootFolder)) 
{
    New-Item -ItemType Directory -Path $ciExportRootFolder -Force | Out-Null
}


# Getting full list of configuration items
[array]$listOfConfigItems = Get-CMConfigurationItem -Fast

# We will export all items individually and then baselines containing related items
# That way we could restore the items to the correct folder first and the restore baselines
# Or just baselines with items attached. But the items then might not be in the correct folder

foreach ($configItem in $listOfConfigItems)
{
    $paramSplatting = @{
        SiteServer = $ProviderMachineName
        SiteCode = $SiteCode
        ObjectUniqueID = ($configItem.ModelName)
        ObjectTypeName = ($configItem.SmsProviderObjectPath -replace '\..*')
    }
    
    $fullFolderPath = Get-ConfigMgrObjectLocation @paramSplatting
    
    if ($fullFolderPath -ieq 'root')
    {
        $ciExportFolder = $ciExportRootFolder
    }
    else
    {
        $ciExportFolder = '{0}\{1}' -f $ciExportRootFolder, ($fullFolderPath -replace '^root\\')
    }

    # Removing illegal characters from folder path
    $ciExportFolder = Sanitize-Path -Path $ciExportFolder

    # Lets make sure the folder is there
    if (-not (Test-Path $ciExportFolder)) 
    {
        New-Item -ItemType Directory -Path $ciExportFolder -Force | Out-Null
    }

    $itemFullName = '{0}\{1}.cab' -f $ciExportFolder, (Sanitize-FileName -FileName ($configItem.LocalizedDisplayName))
    
    if ($itemFullName.Length -ge 254)
    {
        Write-Output "Path too long: $itemFullName"    
    }
    else
    {
        Export-CMConfigurationItem -Id $configItem.CI_ID -Path $itemFullName
    }
}
#endregion


#region Baselines
# We need a folder to store Baseliens in
$baselineExportRootFolder = '{0}\Baseline' -f $FullExportFolderName
if (-not (Test-Path $baselineExportRootFolder)) 
{
    New-Item -ItemType Directory -Path $baselineExportRootFolder -Force | Out-Null
}


# Getting full list of baselines
[array]$listOfBaseline = Get-CMBaseline -Fast

foreach ($baselineItem in $listOfBaseline)
{
    $paramSplatting = @{
        SiteServer = $ProviderMachineName
        SiteCode = $SiteCode
        ObjectUniqueID = ($baselineItem.ModelName)
        ObjectTypeName = ($baselineItem.SmsProviderObjectPath -replace '\..*')
    }
    
    $fullFolderPath = Get-ConfigMgrObjectLocation @paramSplatting
    
    if ($fullFolderPath -ieq 'root')
    {
        $baselineExportFolder = $baselineExportRootFolder
    }
    else
    {
        $baselineExportFolder = '{0}\{1}' -f $baselineExportRootFolder, ($fullFolderPath -replace '^root\\')
    }

    # Removing illegal characters from folder path
    $baselineExportFolder = Sanitize-Path -Path $baselineExportFolder

    # Lets make sure the folder is there
    if (-not (Test-Path $baselineExportFolder)) 
    {
        New-Item -ItemType Directory -Path $baselineExportFolder -Force | Out-Null
    }

    $baselineFullName = '{0}\{1}.cab' -f $baselineExportFolder, (Sanitize-FileName -FileName ($baselineItem.LocalizedDisplayName))
    
    if ($baselineFullName.Length -ge 254)
    {
        Write-Output "Path too long: $baselineFullName"    
    }
    else
    {
        Export-CMBaseline -Id $baselineItem.CI_ID -Path $baselineFullName
    }
}


#endregion