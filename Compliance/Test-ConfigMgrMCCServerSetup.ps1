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
    Test-ConfigMgrMCCServerSetup is designed to test the setup of a ConfigMgr integrated Microsoft Connected Cache server

.DESCRIPTION
    Test-ConfigMgrMCCServerSetup is designed to test the setup of a ConfigMgr integrated Microsoft Connected Cache server
    The script will check the last mcc install exitcode
    It will test for the content path
    It will test for the auto generated test file
    It will do a download test and will test for a downloaded gif file
    It is meant to run as a ConfigMgr compliance config item

.EXAMPLE
   Test-ConfigMgrMCCServerSetup.ps1

.LINK
    https://github.com/jonasatgit/scriptrepo

#>
[CmdletBinding()]
param
(
    [string]$mccRegPath = 'HKLM:\SOFTWARE\Microsoft\Delivery Optimization In-Network Cache',
    [string]$mccContentFolderName = 'DOINC-E77D08D0-5FEA-4315-8C95-10D359D59294',
    [string]$autoTestFile = "download.windowsupdate.com\mscomtest\cedtest\r20.gif.full",
    [string]$manualTestFile = "download.windowsupdate.com\mscomtest\wuidt.gif.full"
)

# Get PrimaryDrivesInput to determine mcc drive
$RegKeyPrimaryDrivesInput = Get-ItemProperty -Path $mccRegPath -Name 'PrimaryDrivesInput' -ErrorAction SilentlyContinue
if (-NOT $RegKeyPrimaryDrivesInput)
{
    Write-Output "Uncompliant. PrimaryDrivesInput not found in registry: $($mccRegPath)"
    return
}

# Get mcc install exit code to test for error
$RegKeyInvocationExitCode = Get-ItemProperty -Path $mccRegPath -Name 'InvocationExitCode' -ErrorAction SilentlyContinue
if (-NOT $RegKeyInvocationExitCode)
{
    Write-Output "Uncompliant. InvocationExitCode not found in registry: $($mccRegPath)"
    return
}

# Fail if install not successful
if ($RegKeyInvocationExitCode.InvocationExitCode -ne 0)
{
    Write-Output "Uncompliant. MCC install failed with exitcode $($RegKeyInvocationExitCode.InvocationExitCode)"
    return
}

# Build mcc content folder paths 
$mccContentFolder = '{0}:\{1}' -f ($RegKeyPrimaryDrivesInput.PrimaryDrivesInput), $mccContentFolderName
$autoTestFileFullPath = '{0}\{1}' -f $mccContentFolder, $autoTestFile
$manualTestFileFullPath = '{0}\{1}' -f $mccContentFolder, $manualTestFile

# Test content folder path
if (-NOT (Test-Path $mccContentFolder))
{
    Write-Output "Uncompliant. MCC content path does not exist: $mccContentFolder"
    return    
}

# Test auto generated test file
if (-NOT (Test-Path $autoTestFileFullPath))
{
    Write-Output "Uncompliant. MCC auto test file content path does not exist: $autoTestFileFullPath"
    return    
}


# Run mcc test against local server
$localSystemFQDN = [System.Net.Dns]::GetHostByName(($env:computerName)).HostName
# https://learn.microsoft.com/en-us/mem/configmgr/core/servers/deploy/configure/troubleshoot-microsoft-connected-cache#verify-on-the-server
try
{
    $mccTestResult = $Null
    $mccTestResult = Invoke-WebRequest -URI "http://$($localSystemFQDN)/mscomtest/wuidt.gif" -Headers @{"Host"="b1.download.windowsupdate.com"} -UseBasicParsing -ErrorAction SilentlyContinue
}
catch
{
    # The webrequest might also fail if a user proxy is set for the user running the script
    Write-Output "Uncompliant. MCC test did not succeed. $(($Error[0].Exception).Message)"
    return
}

# Only 200 is good
if ($mccTestResult.StatusCode -ne 200)
{
    Write-Output "Uncompliant. MCC test did not succeed"
    return    
}

# Test manual generated test file coming from the webrequest above
if (-NOT (Test-Path $manualTestFileFullPath))
{
    Write-Output "Uncompliant. MCC auto test file content path does not exist: $manualTestFileFullPath"
    return    
}

# Will only be compliant if all above checks succeed
Write-Output "Compliant"
