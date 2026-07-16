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