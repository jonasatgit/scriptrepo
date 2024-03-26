
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
    This script, Test-WSUSClientReadyness.ps1, checks the readiness of a client machine for Windows Server Update Services (WSUS).

.DESCRIPTION
    The script performs several checks to ensure the client machine is ready for WSUS. These checks include:

    - Disk space on the C drive
    - Last reboot time
    - WSUS scan errors
    - WSUS service status
    - WSUS server URL
    - WSUS signing certificate

.PARAMETER MinDriveSpaceInGB
    The minimum required free space on the C drive in GB. Default is 10GB.

.PARAMETER MaxMissedRebootDays
    The maximum number of days the system can go without a reboot. If the last reboot time exceeds this number, a warning is flagged. Default is 32 days.

.PARAMETER ListOfPossibleWSUSServers
    A list of possible WSUS servers. If the WSUS server URL does not match one of these, a warning is flagged. Default is ('CM02.CONTOSO.LOCAL').

.PARAMETER WSUSSigningCertificateThumbprint
    The thumbprint of the WSUS signing certificate. If the certificate is not found in the TrustedPublisher store, a warning is flagged. 
    Default is "0ec7bd9835ec7d388db83b2a45a876cd5b99a6f8".

.PARAMETER OutType
    The output type. Options are 'ComplianceState', 'Object', or 'Table'. Default is 'ComplianceState'.

.EXAMPLE
    .\Test-WSUSClientReadyness.ps1 -MinDriveSpaceInGB 20 -MaxMissedRebootDays 30 -ListOfPossibleWSUSServers 'server1','server2' -WSUSSigningCertificateThumbprint 'abc123'

    This example runs the script with custom parameters. It sets the minimum required free space on the C drive to 20GB, the maximum number of days without a reboot to 30, 
    the list of possible WSUS servers to 'server1' and 'server2', and the WSUS signing certificate thumbprint to 'abc123'.
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [int]$MinDriveSpaceInGB = 10,
    [Parameter(Mandatory=$false)]
    [int]$MaxMissedRebootDays = 32,
    [Parameter(Mandatory=$false)]
    [string[]]$ListOfPossibleWSUSServers = ('CM02.CONTOSO.LOCAL'),
    [Parameter(Mandatory=$false)]
    [string]$WSUSSigningCertificateThumbprint = "0ec7bd9835ec7d388db83b2a45a876cd5b99a6f8",
    [Parameter(Mandatory=$false)]
    [ValidateSet('ComplianceState','Object','Table')]
    [string]$OutType = 'ComplianceState'
)

#region variables
$outObj = [System.Collections.Generic.List[pscustomobject]]::new()
$stepCounter = 0
#endregion


#region Test if drive C has enough free space
$stepCounter++
$stateObject = [pscustomobject]@{
    CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
    Step = $stepCounter
    Name = 'Check disk space'
    State = ''
    RelatedInfo = ''
}
# Check if drive C has enough free space
try 
{
    $volumeInfo = Get-Volume -DriveLetter C
    if (($volumeInfo.SizeRemaining / 1gb) -lt $MinDriveSpaceInGB) 
    {   
        $stateObject.State = 'Failed'
        $stateObject.RelatedInfo = 'Remaining disk space on C: is less than {0}GB Size:{2}GB SizeRemaining:{3}GB' -f $MinDriveSpaceInGB, $volumeInfo.driveletter, [math]::Round(($volumeInfo.size / 1gb)), [math]::Round(($volumeInfo.sizeremaining / 1gb))
    }
    else 
    {
        $stateObject.State = 'Ok'
        $stateObject.RelatedInfo = 'Drive C: Size:{1}GB SizeRemaining:{2}GB' -f $volumeInfo.driveletter, [math]::Round(($volumeInfo.size / 1gb)), [math]::Round(($volumeInfo.sizeremaining / 1gb))
    }
}
catch 
{
    $stateObject.State = 'Error'
    $stateObject.RelatedInfo = 'Error: Failed to get free disk space. {0}' -f ($_)
} 
$outObj.Add($stateObject)
#endregion


#region Check last reboot time
$stepCounter++
$stateObject = [pscustomobject]@{
    CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
    Step = $stepCounter
    Name = 'Check last reboot time'
    State = ''
    RelatedInfo = ''
}

try 
{
    $win32OperatingSystem = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($win32OperatingSystem)
    {
        # ConvertToDateTime method not available on all OS versions. Will use ParseExact instead
        #$lastBootUpTime = $win32OperatingSystem.ConvertToDateTime($win32OperatingSystem.LastBootUpTime)
        $tmpDateTimeSplit = ($win32OperatingSystem.LastBootUpTime) -split '\.'
        $lastBootUpTime = [Datetime]::ParseExact($tmpDateTimeSplit[0], 'yyyyMMddHHmmss', $null)
        if ($lastBootUpTime)
        {
            $lastBootUpTimeSpan = New-TimeSpan -Start ($lastBootUpTime) -End (Get-Date)
            if ($lastBootUpTimeSpan.TotalDays -gt $MaxMissedRebootDays)
            {
                $stateObject.State = 'Failed'
                $stateObject.RelatedInfo = 'Last reboot was {0} days ago' -f [math]::Round($lastBootUpTimeSpan.TotalDays)
            }
            else 
            {
                $stateObject.State = 'Ok'
                $stateObject.RelatedInfo = 'Last reboot was {0} days ago' -f [math]::Round($lastBootUpTimeSpan.TotalDays)
            }
        }
        else 
        {
            $stateObject.State = 'Error'
            $stateObject.RelatedInfo = 'Not able to get last reboot datetime'
        }
    }
    else 
    {
        $stateObject.State = 'Error'
        $stateObject.RelatedInfo = 'Not able to get last reboot datetime from WMI'
    }
}
catch 
{
    $stateObject.State = 'Error'
    $stateObject.RelatedInfo = 'Not able to get last reboot datetime. {0}' -f ($_)
}
$outObj.Add($stateObject)
#endregion


#region Test for WSUS scan error
$stepCounter++
$stateObject = [pscustomobject]@{
    CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
    Step = $stepCounter
    Name = 'Check WSUS scan error'
    State = ''
    RelatedInfo = ''
}
try 
{
    $scanState = Get-CimInstance -Namespace 'ROOT\ccm\StateMsg' -Query 'SELECT * FROM CCM_StateMsg where TopicType = 501' -ErrorAction Stop 
    if ($scanState)
    {
        if ($scanState.UserParameters.Count -gt 2)
        {
            $stateObject.State = 'Failed'
            $stateObject.RelatedInfo = 'WSUS scan error detected: {0}' -f ($scanState.UserParameters -join ',')
        }
        else 
        {
            $stateObject.State = 'Ok'
            $stateObject.RelatedInfo = 'No WSUS scan error detected'
        }
    }   
    else 
    {
        $stateObject.State = 'Error'
        $stateObject.RelatedInfo = 'WMI query was successful, but no scanstate was found. Query: "SELECT * FROM CCM_StateMsg where TopicType = 501"' 
    }
}
catch 
{
    $stateObject.State = 'Error'
    $stateObject.RelatedInfo = 'No ScanState information found. {0}' -f ($_)
}
$outObj.Add($stateObject)
#endregion


#region Test WSUS service not disabled
$stepCounter++
$stateObject = [pscustomobject]@{
    CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
    Step = $stepCounter
    Name = 'Check WSUS service status'
    State = ''
    RelatedInfo = ''
}
try 
{
    $wsusService = Get-Service -Name 'wuauserv' -ErrorAction Stop
    if ($wsusService)
    {
        # startyptype should not be disabled
        if ($wsusService.StartType -ieq 'Disabled')
        {
            $stateObject.State = 'Failed'
            $stateObject.RelatedInfo = 'WSUS service is disabled'
        }
        else 
        {
            $stateObject.State = 'Ok'
            $stateObject.RelatedInfo = 'WSUS service is enabled'
        }
    }
    else 
    {
        $stateObject.State = 'Error'
        $stateObject.RelatedInfo = 'No WSUS service found'
    }
}
catch 
{
    $stateObject.State = 'Error'
    $stateObject.RelatedInfo = 'No WSUS service found. {0}' -f ($_)
}
$outObj.Add($stateObject)
#endregion


#region Test if WSUS server URL mathes the list of possible WSUS servers
# from HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\WUServer
# and HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\WUStatusServer
$stepCounter++
$stateObject = [pscustomobject]@{
    CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
    Step = $stepCounter
    Name = 'Check WSUS server URL'
    State = ''
    RelatedInfo = ''
}

# get values from registry
$WUServerURL = ''
$WUStatusServerURL = ''
try 
{
    $WUServer = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'WUServer' -ErrorAction Stop
    $WUStatusServer = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'WUStatusServer' -ErrorAction Stop
    if ($WUServer -and $WUStatusServer)
    {
        $WUServerURL = $WUServer.WUServer -replace '(http|https)://' -replace ':.*'
        $WUStatusServerURL = $WUStatusServer.WUStatusServer -replace '(http|https)://' -replace ':.*'

        if ($WUServerURL -ieq $WUStatusServerURL)
        {

            if($ListOfPossibleWSUSServers -icontains $WUServerURL)
            {
                $stateObject.State = 'Ok'
                $stateObject.RelatedInfo = 'WSUS server URL matches the list of possible WSUS servers'
            }
            else 
            {
                $stateObject.State = 'Failed'
                $stateObject.RelatedInfo = 'WSUS server URL does not match the list of possible WSUS servers. Found: {0}' -f $WUServer.WUServer
            }
        }
        else
        {
            $stateObject.State = 'Failed'
            $stateObject.RelatedInfo = 'WSUS server and WSUS status server differ'       
        }
    }
}
catch 
{
    $stateObject.State = 'Error'
    $stateObject.RelatedInfo = 'No WSUS server URL found in registry. {0}' -f ($_)
}
$outObj.Add($stateObject)
#endregion


#region Test WSUS signing certificate
$stepCounter++
$stateObject = [pscustomobject]@{
    CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
    Step = $stepCounter
    Name = 'Check WSUS signing certificate'
    State = ''
    RelatedInfo = ''
}

$certPath = "Cert:\LocalMachine\TrustedPublisher\{0}" -f $WSUSSigningCertificateThumbprint

If (Test-Path $certPath) 
{
    $stateObject.State = 'Ok'
    $stateObject.RelatedInfo = 'WSUS signing certificate found'
} 
Else 
{
    $stateObject.State = 'Failed'
    $stateObject.RelatedInfo = 'WSUS signing certificate not found in: {0}' -f $certPath
}
$outObj.Add($stateObject)
#endregion


#region 
switch ($OutType) 
{
    'ComplianceState' 
    {  
        [array]$failedStates = $outObj.where({$_.State -ine 'OK'})
        if ($failedStates)
        {
            $outString = 'Checks failed: {0}' -f ($failedStates.Name -join ', ')
            Write-Output $outString
        }
        else 
        {
            Write-Output 'Compliant'
        }
    }
    'Table' 
    {
        $outObj | Format-Table -AutoSize    
    }
    'Object' 
    {
        $outObj
    }
}
#endregion