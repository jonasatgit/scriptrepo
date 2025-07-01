<#
.SYNOPSIS
    Script to monitor registry changes under HKEY_LOCAL_MACHINE for specific sections like PolicyManager.

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

.PARAMETER MonitorSection
    Specifies the section of the registry to monitor. Default is "PolicyManager".

#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $false)]
    [ValidateSet("PolicyManager")]
    [string]$MonitorSection = "PolicyManager"


)

# Set the root path based on the MonitorSection parameter
switch ($MonitorSection) 
{
    "PolicyManager" 
    { 
        $rootPath = "SOFTWARE\\Microsoft\\PolicyManager" 
    }
    Default {}
}


# Load required assembly
Add-Type -AssemblyName System.Management

# Create a WMI query to watch for registry changes
$query = "SELECT * FROM RegistryTreeChangeEvent WHERE Hive='HKEY_LOCAL_MACHINE' AND RootPath='{0}'" -f $rootPath

# Create the event watcher
$watcher = New-Object System.Management.ManagementEventWatcher
$watcher.Query = $query
$watcher.Scope = New-Object System.Management.ManagementScope("root\default")

# Define the action to take when a change is detected
$null = Register-ObjectEvent -InputObject $watcher -EventName "EventArrived" -Action {
    Write-Host "Registry change detected under HKLM\$($rootPath -replace '\\\\','\') at $(Get-Date)"
    # Optional: Add logic here to log or handle the change
}

# Start listening
$watcher.Start()
Write-Host "Watching for registry changes under HKLM\$($rootPath -replace '\\\\','\')..."

# Keep the script running
while ($true) {
    Start-Sleep -Seconds 5
}
