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
    This script adds a ConfigMgr security scope to a folder and all its subfolders.

.DESCRIPTION
    This script adds a ConfigMgr security scope to a folder and all its subfolders. It uses the Get-CMFolder cmdlet to retrieve the folder and its subfolders, and then uses the Add-CMObjectSecurityScope cmdlet to add the specified security scope to each folder.

.PARAMETER SiteCode
    Specify the ConfigMgr site code.

.PARAMETER ProviderMachineName
    Specify the ConfigMgr provider machine name.

.PARAMETER CMScopeName
    Specify the ConfigMgr security scope name.

.PARAMETER FolderPath
    Specify the folder path. Like: DeviceCollection\Servers or DeviceCollection\Servers\Patch or UserCollection\Sales

.EXAMPLE
    .\Add-CMScopeToFolderTree.ps1 -SiteCode "ABC" -ProviderMachineName "CM01" -CMScopeName "SalesScope" -FolderPath "DeviceCollection\Servers"

    This command adds the security scope "SalesScope" to the folder "DeviceCollection\Servers" and all its subfolders in the ConfigMgr site with site code "ABC" on the provider machine "CM01".    
#>
[CmdletBinding()]
param
(
    [Parameter(HelpMessage = "Specify the ConfigMgr site code.")]
    [string]$SiteCode,
    [Parameter(HelpMessage = "Specify the ConfigMgr provider machine name.")]
    [string]$ProviderMachineName,
    [Parameter(HelpMessage = "Specify the ConfigMgr security scope name.")]
    [string]$CMScopeName,
    [Parameter(HelpMessage = "Specify the folder path. Like: DeviceCollection\Servers or DeviceCollection\Servers\Patch or UserCollection\Sales")]
    [string]$FolderPath
)

# Import the ConfigurationManager.psd1 module 
if($null -eq (Get-Module ConfigurationManager)) 
{
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" 
}

# Connect to the site's drive if it is not already present
if($null -eq (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) 
{
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName
}

# Set the current location to be the site code.
$originalLocation = Get-Location
Set-Location "$($SiteCode):\" 


function Get-CMFolderDescendants {
    param(
        [string]$SiteCode,
        [string]$ProviderMachineName,
        [int]$ContainerNodeID,
        [string]$CurrentPath
    )

    $Children = Get-CimInstance `
        -ComputerName $ProviderMachineName `
        -Namespace "root\sms\site_$SiteCode" `
        -ClassName SMS_ObjectContainerNode `
        -Filter "ParentContainerNodeID = $ContainerNodeID"

    foreach ($Child in $Children) {

        $ChildPath = "$CurrentPath\$($Child.Name)"

        Write-Host $ChildPath

        $Child | Add-Member -NotePropertyName FullPath `
                            -NotePropertyValue $ChildPath `
                            -Force

        $Child

        Get-CMFolderDescendants `
            -SiteCode $SiteCode `
            -ProviderMachineName $ProviderMachineName `
            -ContainerNodeID $Child.ContainerNodeID `
            -CurrentPath $ChildPath
    }
}


$RootFolder = Get-CMFolder -FolderPath $FolderPath

# stop stript if the folder does not exist
if ($null -eq $RootFolder) 
{
    Write-Host "Folder path: $FolderPath does not exist. Please check the folder path and try again."
    exit
}

$RootFolder | Add-Member -NotePropertyName FullPath -NotePropertyValue $RootFolder.Name -Force

Write-Host "-------Start----------"
Write-Host $RootFolder.Name
$Folders = @($RootFolder)

$Folders += Get-CMFolderDescendants `
    -SiteCode $SiteCode `
    -ProviderMachineName $ProviderMachineName `
    -ContainerNodeID $RootFolder.ContainerNodeID `
    -CurrentPath $RootFolder.Name


Write-Host "-----------------"
foreach ($Folder in $Folders) 
{
    $folderObject = Get-CMFolder -Guid $Folder.FolderGuid
    Write-Host "Setting scope: `"$CMScopeName`" on folder: `"$($Folder.FullPath)`""
    Add-CMObjectSecurityScope `
        -InputObject $folderObject `
        -Name $CMScopeName
}
Write-Host "-------End----------"
Set-Location $originalLocation