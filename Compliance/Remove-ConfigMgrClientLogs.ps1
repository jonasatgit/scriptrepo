
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
    Script to delete old log files from ConfigMgr client log folder

.DESCRIPTION
    This script will delete old log files from the ConfigMgr client log folder. 
    The script will get the log folder path from the registry and delete log files older than a specified number of days.
    It is designed to be run as a ConfigMgr configuration item within a baseline to keep the ConfigMgr client log folder clean.

.PARAMETER FolderPath
    The path to the ConfigMgr client log folder. If not specified, the script will get the log folder path from the registry.

.PARAMETER DaysToKeep
    The number of days to keep log files. Log files older than this number of days will be deleted.
    Default is 30 days.

.PARAMETER Remediate
    If this parameter is set to $true, the script will delete the log files. 
    If set to $false, the script will only output the number of log files that would be deleted.

.EXAMPLE
    Remove-ConfigMgrClientLogs.ps1 -FolderPath "C:\Windows\CCM\Logs" -DaysToKeep 7

    This example will only show how many log files are older than 7 days from the specified folder.

.EXAMPLE
    Remove-ConfigMgrClientLogs.ps1 -FolderPath "C:\Windows\CCM\Logs" -DaysToKeep 7 -Remediate $true

    This example will delete log files older than 7 days from the specified folder.
#>
[CmdletBinding()]
param
(
    [string]$FolderPath,
    [int]$DaysToKeep = 30,
    [bool]$Remediate = $false
)


#region Get-ConfigMgrClientLogPath
function Get-ConfigMgrClientLogPath
{

    # Get the ConfigMgr client log path from the registry   
    try
    {
        # Define the registry path for the ConfigMgr client
        $registryPath = "HKLM:\SOFTWARE\Microsoft\CCM\Logging\@Global"

        # Get the ConfigMgr client log path from the registry
        $logPath = Get-ItemPropertyValue -Path $registryPath -Name "LogDirectory"
    }catch
    {
        Write-Output "ConfigMgr client log path not found $($_)"
        Exit 1
    }

    return $logPath
}
#endregion

#region Main
if(-not $FolderPath)
{
    $FolderPath = Get-ConfigMgrClientLogPath
}

$today = Get-Date
[array]$filesToDelete = Get-ChildItem -Path $folderPath | Where-Object {$_.LastWriteTime -lt ($today.AddDays(-$daysToKeep))}

if ($Remediate)
{
    $filesToDelete | Remove-Item -Force
}
else
{
    Write-Output ($filesToDelete.count)
}

#endregion