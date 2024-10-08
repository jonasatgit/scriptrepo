
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

.PARAMETER DetectionReturnValue
    A dummy parameter to catch any return value coming from the ConfigMgr detection script.
    Could be used to pass a value from the detection script to the remediation script, but is not used in this script to keep the script consistent.

.PARAMETER FolderPath
    The path to the ConfigMgr client log folder. If not specified, the script will get the log folder path from the registry automatically.
    The auto-detected path is coming from: HKLM:\SOFTWARE\Microsoft\CCM\Logging\@Global\LogDirectory
    Typically the log folder path should be detected automatically, since it can vary. Specifically on Management Points.

.PARAMETER DaysToKeep
    The number of days to keep log files. Log files older than this number of days will be deleted.
    Default is 30 days.

.PARAMETER Remediate
    If this parameter is set to $true, the script will delete the log files. 
    If set to $false, the script will only output the number of log files that would be deleted.

.PARAMETER FileNamesToExclude
    An array of file names to exclude from the deletion process. "*" as wildcard is supported.
    Cannot be used with FileNamesToInclude together.

.PARAMETER FileNamesToInclude
    An array of file names to include in the deletion process. "*" as wildcard is supported.
    Cannot be used with FileNamesToExclude together.

.EXAMPLE
    Remove-ConfigMgrClientLogs.ps1 -FolderPath "C:\Windows\CCM\Logs" -DaysToKeep 7

    This example will only show how many log files are older than 7 days from the specified folder.

.EXAMPLE
    Remove-ConfigMgrClientLogs.ps1 -FolderPath "C:\Windows\CCM\Logs" -DaysToKeep 7 -Remediate $true

    This example will delete log files older than 7 days from the specified folder.

.EXAMPLE
    Remove-ConfigMgrClientLogs.ps1 -FolderPath "C:\Windows\CCM\Logs" -DaysToKeep 7 -FileNamesToInclude "*SCNotify*.log"

    This example will delete log files older than 7 days from the specified folder that match the file name "*SCNotify*.log".
#>
[CmdletBinding()]
param
(
    # The first parameter is to just catch any return value from the detection script in ConfigMgr and does not have any real use.
    [Parameter(Mandatory=$false,Position=0)]
    [string]$DetectionReturnValue,
    
    [Parameter(Mandatory=$false,Position=1)]
    [string]$FolderPath,
    
    [Parameter(Mandatory=$false,Position=2)]
    [int]$DaysToKeep = 30,
    
    [Parameter(Mandatory=$false,Position=3)]
    [bool]$Remediate = $false,
    
    [Parameter(Mandatory=$false,Position=4)]
    [string[]]$FileNamesToExclude = @(),
    
    [Parameter(Mandatory=$false,Position=5)]
    [string[]]$FileNamesToInclude = @("*WmiExport*.log","*SCNotify*.log","*SCToastNotification*.log")
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
        break
    }

    return $logPath
}
#endregion

#region Main
if ($FileNamesToExclude -and $FileNamesToInclude)
{
    Write-Output "You can only specify either LogNamesToExclude or LogNamesToInclude, not both"
    break
}


# Get the log folder path
if(-not $FolderPath)
{
    $FolderPath = Get-ConfigMgrClientLogPath
}


# Making sure we use the ConfiMgr path
if ($FolderPath -inotmatch 'ccm\\logs')
{
    Write-Output "CCM logpath variable does not match with *ccm\logs -> $($FolderPath)" 
    break
}

# Main detection and remediation logic
$today = Get-Date
if ($FolderPath)
{
    [array]$filesToDelete = Get-ChildItem -Path $folderPath

    # Include some files
    if ($FileNamesToInclude)
    {
        $filesToDelete = $filesToDelete | ForEach-Object {

            foreach ($FileName in $FileNamesToInclude)
            {
                if ($_.Name -ilike $FileName)
                {
                    $_
                }
            }
        }
    }

    # Exclude some files
    if ($FileNamesToExclude)
    {
        $filesToDelete = $filesToDelete | ForEach-Object {
            
            $foundItem = $false
            foreach ($FileName in $FileNamesToExclude)
            {
                if ($_.Name -ilike $FileName)
                {
                    $foundItem = $true
                }
            }

            if (-not $foundItem)
            {
                $_
            }
        }
    }

    # Now lets filter out the files that are older than the specified number of days
    $filesToDelete = $filesToDelete | Where-Object {$_.LastWriteTime -le ($today.AddDays(-$daysToKeep))}

    # Either delete or output the number of files
    if ($Remediate)
    {
        if ($filesToDelete.count -gt 0)
        {
            foreach($file in $filesToDelete)
            {
                Remove-Item -Path $file.FullName -Force
            }
        }
    }
    else
    {
        Write-Output ($filesToDelete.count)
    }
}
else
{
    Write-Output "No ConfigMgr log folder path found"
}
#endregion