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
    Sample script to "monitor" and "wait" for the Enrollment ID and Device Join event to be found in the Event Viewer when using a Bulk Enrollment provisioning package.

.DESCRIPTION
    This script will monitor the Event Viewer for the Enrollment ID and Device Join event when using a Bulk Enrollment provisioning package. 
    The script will wait for the Enrollment ID and Device Join event to be found in the Event Viewer. 
    The script will exit if the Enrollment ID and Device Join event is not found within the specified time.
    The script is intended to be used in a script that applies a Bulk Enrollment provisioning package or as a standalone script run after 
    the Bulk Enrollment provisioning package has been applied.
    Example: Install-ProvisioningPackage -PackagePath "C:\temp\EntraIDJoinPackage.ppkg" -ForceInstall -QuietInstall -LogsDirectoryPath "C:\Temp"

.PARAMETER WaitTimeoutSeconds
    The number of seconds to wait for the Enrollment ID and Device Join event to be found in the Event Viewer. Default is 20 seconds.

.PARAMETER ProvisioningPackageName
    The name of the provisioning package that is being applied. Default is 'EntraIDJoinPackage'. Can also contain .ppkg extension.

.EXAMPLE
    .\Test-BulkEnrollmentState.ps1 -WaitTimeoutSeconds 30 -ProvisioningPackageName 'EntraIDJoinPackage.ppkg'
    This example will wait for 30 seconds for the Enrollment ID and Device Join event to be found in the Event Viewer for the 'EntraIDJoinPackage.ppkg' provisioning package.

.LINK 
    https://github.com/jonasatgit/scriptrepo

#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    $WaitTimeoutSeconds = 20,

    [Parameter(Mandatory = $false)]
    $ProvisioningPackageName = 'EntraIDJoinPackage'
)


$stopWatch = New-Object System.Diagnostics.Stopwatch
$stopWatch.Start()

$xmlQuery = @'
<QueryList>
    <Query Id="0" Path="Microsoft-Windows-Provisioning-Diagnostics-Provider/Admin">
    <Select Path="Microsoft-Windows-Provisioning-Diagnostics-Provider/Admin">*[System[(EventID=20)]]</Select>
    </Query>
</QueryList>
'@

$paramSplatting = @{
    FilterXml = $xmlQuery 
    MaxEvents = 50
    ErrorAction = 'SilentlyContinue'
}

$enrollmentID = $null
do
{
    [array]$eventsList = Get-WinEvent @paramSplatting
    foreach ($event in $eventsList) 
    {
        if ($event.Message -imatch $provisioningPackageName)
        {
            # string looks like: Applying package 'ProvisioningPackageName.ppkg' ID: {3f1537c3-0cb4-429d-b027-ee07c7f13450}.
            $enrollmentID = $event.Message -replace ".*ID: {(.*)}.*",'$1'
            $enrollmentID = "{$($enrollmentID)}"
        }
    }

    if (-NOT ($enrollmentID))
    {
        Write-Output "Waiting 5 seconds for $($provisioningPackageName) Enrollment ID to be found..."
        Start-Sleep -Seconds 5
    }

}
until(($enrollmentID) -or ($stopWatch.Elapsed.TotalSeconds -ge $waitTimeoutSeconds))

if ($stopWatch.Elapsed.TotalSeconds -ge $waitTimeoutSeconds)
{
    Write-Output "Timeout of $waitTimeoutSeconds seconds reached. Exiting script."
    break
}

if ($enrollmentID)
{
    Write-Output "Enrollment ID found: $enrollmentID"
}
else 
{
    Write-Output "Enrollment ID NOT found."
    break
}

# lets now also check if we have the AAD/Entra ID event that the device has successfully joined
# aad event
$xmlQueryAADEvent = @'
<QueryList>
    <Query Id="0" Path="Microsoft-Windows-User Device Registration/Admin">
    <Select Path="Microsoft-Windows-User Device Registration/Admin">*[System[(EventID=104)]]</Select>
    </Query>
</QueryList>
'@

$paramSplattingAADEvent = @{
    FilterXml = $xmlQueryAADEvent
    MaxEvents = 50
    ErrorAction = 'SilentlyContinue'
}

$stopWatch.Restart()
$deviceAADJoinEvent = $null
do
{
    [array]$eventsListAAD = Get-WinEvent @paramSplattingAADEvent
    foreach ($event in $eventsListAAD) 
    {
        # Message will contain the thumbprint and certificate and the upn of the enrollment account
        if ($event.Message -imatch 'Thumbprint.*upn')
        {
            $deviceAADJoinEvent = $event.Message
        }
        elseif ($event.Message -imatch 'Conflicting object') 
        {
            Write-Output "INFO: There is a device already found in Entra ID. Device will still be enrolled."
        }
    }

    if (-NOT ($deviceAADJoinEvent))
    {
        Write-Output "Waiting 5 seconds for DeviceAADJoin event to be found..."
        Start-Sleep -Seconds 5
    }
}
until(($deviceAADJoinEvent) -or ($stopWatch.Elapsed.TotalSeconds -ge $waitTimeoutSeconds))

if ($stopWatch.Elapsed.TotalSeconds -ge $waitTimeoutSeconds)
{
    Write-Output "Timeout of $waitTimeoutSeconds seconds reached. Exiting script."
    break
}

if ($deviceAADJoinEvent)
{
    Write-Output "Device has successfully joined Entra ID."
}
else 
{
    Write-Output "Device Join message not found. Join might have failed. Exiting script."
    break
}