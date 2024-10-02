<#
.SYNOPSIS
Script to analyze a Windows client for WSUS related issues

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

.PARAMETER MinDriveSpaceInPercent
Minimum percentage of free space on drive C. Default is 10%

.PARAMETER MaxMissedRebootDays
Maximum days since last reboot. Default is 40 days

.PARAMETER MaxDelayAfterRebootInMinutes
Maximum minutes since last reboot. Default is 5 minutes

.PARAMETER AllowUpdateInstallation
Allow installation of updates. Default is $false
NOTE: Not yet fully implemented

.PARAMETER ListOfOSVersions
List of OS versions to check against. Default is $null

.PARAMETER maxSecurityUpdateInstallAge
Maximum days since last security update. Default is 30 days

.PARAMETER OutMode
Output mode. Default is GridView. Possible values are GridView, JSONCompressed, JSON, Object
#>

#region PARAM DEFINITION
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [int]$MinDriveSpaceInPercent = 10,
    [Parameter(Mandatory=$false)]
    [int]$MaxMissedRebootDays = 40,
    [Parameter(Mandatory=$false)]
    [int]$MaxDelayAfterRebootInMinutes = 5,
    [Parameter(Mandatory=$false)]
    [bool]$AllowUpdateInstallation = $false,
    [Parameter(Mandatory=$false)]
    [version[]]$ListOfOSVersions, # Example: @('10.0.19041.1023', '10.0.19042.1023')
    [Parameter(Mandatory=$false)]
    [int]$maxSecurityUpdateInstallAge = 30,
    [ValidateSet('GridView','JSONCompressed','JSON','Object')]
    [string]$OutMode = 'JSONCompressed'
)
#endregion


#region function Test-PendingReboot
function Test-PendingReboot
{
    $rebootTypes = New-Object System.Collections.ArrayList
    if(Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue) { [void]$rebootTypes.Add("CBSRebootPending") }
    if(Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue) { [void]$rebootTypes.Add("UpdateRebootRequired") }
    if(Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting" -ErrorAction SilentlyContinue) { [void]$rebootTypes.Add("UpdatePostReboot") }
    if(Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress" -ErrorAction SilentlyContinue) { [void]$rebootTypes.Add("CBSinProgress") }
    if(Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending" -ErrorAction SilentlyContinue) { [void]$rebootTypes.Add("CBSPackagePending") }
    # too many false positives with PendigFileRenameOperations
    #if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue) { [void]$rebootTypes.Add("FileRename") }
    <# 
        Testing CCM_SoftwareUpdate should be obsolete since we're testing the client already, but it might help to understand were a reboot is coming from
        8   ciJobStatePendingSoftReboot
        9   ciJobStatePendingHardReboot
        10  ciJobStateWaitReboot
    #>
    $wqlQuery = 'select * from CCM_SoftwareUpdate where (EvaluationState = 8) or (EvaluationState = 9) or (EvaluationState = 10)'
    if (Get-CimInstance -Namespace 'root/ccm/ClientSDK' -Query $wqlQuery -ErrorAction SilentlyContinue)
    {
        [void]$rebootTypes.Add("ConfigMgrUpdates")   
    }
    try
    {
        $rebootStatus = Invoke-CimMethod -Namespace root\ccm\clientsdk -ClassName CCM_ClientUtilities -MethodName DetermineIfRebootPending -ErrorAction SilentlyContinue
        if(($rebootStatus) -and ($rebootStatus.RebootPending -or $rebootStatus.IsHardRebootPending))
        {
            [void]$rebootTypes.Add("ConfigMgrClient")
        }
    }catch{}
    if ($rebootTypes)
    {
        return $rebootTypes -join ','
    }
    else
    {
        return $false
    }
}
#endregion

#region MAIN Script
# Properties for custom object
[array]$propertyList = ('CheckTime','DeviceName','Step','Name','State','RelatedInfo')

# List fo compliance states and corresponding actions seperated by pipe sign
$complianceStateHash = @{
    '0'='ciNotInstalled|Install'; # Original Name is NotPresent. Changed that to NotInstalled
    '1'='ciInstalled|NoAction'; # Original Name is Present. Changed that to Installed
    '2'='ciPresenceUnknownOrNotApplicable|RunEvaluation';
    '3'='ciEvaluationError|NoAction';
    '4'='ciNotEvaluated|RunEvaluation';
    '5'='ciNotUpdated|Install';
    '6'='ciNotConfigured|RunEvaluation';
}

# List fo evaluation states and corresponding actions seperated by pipe sign
$evaluationStateHash =@{
    '0'='ciJobStateNone|Install';
    '1'='ciJobStateAvailable|Install';
    '2'='ciJobStateSubmitted|Install';   
    '3'='ciJobStateDetecting|Wait';   
    '4'='ciJobStatePreDownload|Wait';   
    '5'='ciJobStateDownloading|Wait';   
    '6'='ciJobStateWaitInstall|Install';   
    '7'='ciJobStateInstalling|Install';   
    '8'='ciJobStatePendingSoftReboot|Reboot';   
    '9'='ciJobStatePendingHardReboot|Reboot';   
    '10'='ciJobStateWaitReboot|Reboot';   
    '11'='ciJobStateVerifying|Wait';   
    '12'='ciJobStateInstallComplete|NoAction';   
    '13'='ciJobStateError|Reboot';   
    '14'='ciJobStateWaitServiceWindow|Install';   
    '15'='ciJobStateWaitUserLogon|Reboot';   
    '16'='ciJobStateWaitUserLogoff|Reboot';   
    '17'='ciJobStateWaitJobUserLogon|Reboot';   
    '18'='ciJobStateWaitUserReconnect|Reboot';   
    '19'='ciJobStatePendingUserLogoff|Reboot';   
    '20'='ciJobStatePendingUpdate|Reboot';   
    '21'='ciJobStateWaitingRetry|Install';   
    '22'='ciJobStateWaitPresModeOff|Reboot';   
    '23'='ciJobStateWaitForOrchestration|Install'
}

# Overall state object
$outObj = New-Object System.Collections.ArrayList
$stepCounter = 0
Write-Verbose "Starting patch tests"

#region Test if drive C has more than 10% free space
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Check disk space'
try
{
    $volumeInfo = Get-Volume -DriveLetter C
    $driveFreeSpaceInPercent = ($volumeInfo.SizeRemaining) / ($volumeInfo.Size) * 100
    if ($driveFreeSpaceInPercent -lt $MinDriveSpaceInPercent)
    {  
        $stateObject.State = 'Failed'
        $stateObject.RelatedInfo = 'Remaining disk space less than {0}% Drive:{1} Size:{2}GB SizeRemaining:{3}GB' -f $MinDriveSpaceInPercent, $volumeInfo.driveletter, [math]::Round(($volumeInfo.size / 1gb)), [math]::Round(($volumeInfo.sizeremaining / 1gb))
    }
    else
    {
        $stateObject.State = 'Ok'
        $stateObject.RelatedInfo = 'Drive:{0} Size:{1}GB SizeRemaining:{2}GB' -f $volumeInfo.driveletter, [math]::Round(($volumeInfo.size / 1gb)), [math]::Round(($volumeInfo.sizeremaining / 1gb))
        #Write-Verbose 'Remaining disk space ok'
    }
}
catch
{
    $stateObject.State = 'Error'
    $stateObject.RelatedInfo = 'Error: Failed to get free disk space. {0}' -f ($Error[0].Exception | Select-Object *)
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
#endregion


#region Test reboot time
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Check for last reboot time'
try
{
    $win32OperatingSystem = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
    # ConvertToDateTime method not evailable on all OS versions. Will use ParseExact instead
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
            if ($lastBootUpTimeSpan.TotalMinutes -le $MaxDelayAfterRebootInMinutes)
            {
                $stateObject.State = 'Failed'
                $stateObject.RelatedInfo = 'Last reboot was {0} minutes ago. We should wait until we start further actions' -f [math]::Round($lastBootUpTimeSpan.TotalMinutes)
            }
            else
            {
                $stateObject.State = 'Ok'
                $stateObject.RelatedInfo = 'Last reboot was {0} days ago' -f [math]::Round($lastBootUpTimeSpan.TotalDays)
            }
        }
    }
    else
    {
        $stateObject.State = 'Error'
        $stateObject.RelatedInfo = 'Not able to get last reboot datetime'
    }
}
catch
{
    $stateObject.State = 'Error'
    $stateObject.RelatedInfo = 'Not able to get reboot state from computer. {0}' -f ($Error[0].Exception | Select-Object *)
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
#endregion


#region Test if latest build version
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Check OS version'
try
{
    $win32OperatingSystem = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
    $updatedBuildRevision = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR -ErrorAction SilentlyContinue).UBR
    if ($win32OperatingSystem -and $updatedBuildRevision)
    {
        $fullVersionNumber = '{0}.{1}' -f $win32OperatingSystem.Version, $updatedBuildRevision
        $latestVersionFound = $false
        if ($null -ne $ListOfOSVersions)
        {
            foreach ($version in $ListOfOSVersions)
            {
                if ($fullVersionNumber -eq $version)
                {
                    $latestVersionFound = $true
                }
            }
            if ($latestVersionFound)
            {
                $stateObject.State = 'Ok'
                $stateObject.RelatedInfo = 'OS version has expected value. Version {0}' -f $fullVersionNumber
            }
            else
            {
                $stateObject.State = 'Failed'
                $stateObject.RelatedInfo = 'OS version not expected value. Version {0}' -f $fullVersionNumber
            }
        }
        else
        {
            $stateObject.State = 'Ok'
            $stateObject.RelatedInfo = 'No OS version validation. Version: {0}' -f $fullVersionNumber
        }
    }
    else
    {
        $stateObject.State = 'Error'
        $stateObject.RelatedInfo = 'Not able to get OS version'
    }
}
catch
{
    $stateObject.State = 'Error'
    $stateObject.RelatedInfo = 'Not able to get OS version. {0}' -f ($Error[0].Exception | Select-Object *)
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
#endregion


#region Check for running client service
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Check for running client service'
$serviceObj = Get-Service -Name CcmExec -ErrorAction SilentlyContinue
if ($serviceObj)
{
    # Set to okay first and
    if ($serviceObj.Status -ine 'Running')
    {
        $stateObject.State = 'Failed'
        $stateObject.RelatedInfo = 'CcmExec service not running'
    }
    elseif ($serviceObj.StartType -inotlike 'automatic*')
    {
        $stateObject.State = 'Failed'
        $stateObject.RelatedInfo = 'CcmExec service wrong startype'
    }
    else
    {
        $stateObject.State = 'OK'
        $stateObject.RelatedInfo = 'CcmExec service running and correct start type set'
    }
}
else
{
    $stateObject.State = 'Failed'
    $stateObject.RelatedInfo = 'CcmExec service not found'
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
#endregion


#region Test for pending reboot
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Check for pending reboot'
try
{
    $pendingRebootState = Test-PendingReboot
    if ($pendingRebootState)
    {
        $stateObject.State = 'Failed'
        $stateObject.RelatedInfo = 'Pending reboot detected from component: {0}' -f $pendingRebootState
    }
    else
    {
        $stateObject.State = 'Ok'
        $stateObject.RelatedInfo = 'No pending reboot detected'
        #Write-Verbose "No pending reboot"
    }
}
catch
{
    $stateObject.State = 'Error'
    $stateObject.RelatedInfo = 'Error: Failed to get reboot state. {0}' -f ($Error[0].Exception | Select-Object *)
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
#endregion


#region Check WSUS URL. It might not be one of the known WSUS servers set
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Check WSUS URL'
$WSUSURL = $null
# read wsus url from WUAHandler class set via location request
$UpdateSource = Get-WmiObject -Namespace 'ROOT\ccm\SoftwareUpdates\WUAHandler' -Class CCM_UpdateSource -ErrorAction SilentlyContinue
if ($UpdateSource)
{
    $matches = $null
    if($UpdateSource.ContentLocation -imatch '(http|https)(://)(?<WSUSURL>[a-zA-Z0-9\.-]*)(:|/)')
    {
        $WSUSURL = $UpdateSource.ContentLocation
    }
    else
    {
        $stateObject.State = 'Failed'
        $stateObject.RelatedInfo = 'WSUS URL does not match with detection pattern: {0}' -f $UpdateSource.ContentLocation
    } 
}
else
{
    $stateObject.State = 'Failed'
    $stateObject.RelatedInfo = 'WSUS URL could not be determined'   
}
if ($WSUSURL)
{
    $pattern = '(http|https)://([^:/]+):(\d+)'
    $Matches = $null
    $null = $WSUSURL -imatch $pattern
    $WSUSFqdn = $Matches[2]
    $WSUSPort = $Matches[3]
    # we also need to test the WSUS server on different ports depending on the WSUS server configuration
    $portMapping = @{
        '8531' = @(8531, 8530)
        '8530' = @(8530)
        '443'  = @(443, 80)
        '80'   = @(80)
    }
    $stateObject.State = 'OK'
    # Loop through the ports to check
    $portString = $null
    if ($portMapping[$WSUSPort])
    {
        foreach ($port in $portMapping[$WSUSPort])
        {
            if (Test-NetConnection -ComputerName $WSUSFqdn -Port $port -InformationLevel Quiet -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
            {
                $portString += '{0}-OK;' -f $port     
            }
            else
            {
                $portString += '{0}-Failed;' -f $port
                $stateObject.State = 'Failed'
            }
        }
    }
    else
    {
        if (Test-NetConnection -ComputerName $WSUSFqdn -Port $WSUSPort -InformationLevel Quiet -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
        {
            $portString += '{0}-OK;' -f $WSUSPort  
        }
        else
        {
            $portString += '{0}-Failed;' -f $WSUSPort
            $stateObject.State = 'Failed'
        }
    }
    $stateObject.RelatedInfo = 'WSUS server: {0} port {1}' -f $WSUSFqdn, $portString
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
#endregion


#region Check system proxy config
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Check system proxy config'
# "NT SYSTEM" internet proxy settings
$path = "HKEY_USERS\S-1-5-18\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
# check proxy entry
$proxyServerObj = Get-ItemProperty -Path Registry::$path -Name ProxyServer -ErrorAction SilentlyContinue
if ($proxyServerObj)
{
    $proxyString = $proxyServerObj.ProxyServer   
}

$proxyEnableObj = Get-ItemProperty -Path Registry::$path -Name ProxyEnable -ErrorAction SilentlyContinue
if ($proxyEnableObj)
{
    if ($proxyEnableObj.ProxyEnable -eq 1)
    {
        # proxy is enabled in system context. We need to check the bypass list
        $proxyOverrideObj = Get-ItemProperty -Path Registry::$path -Name ProxyOverride -ErrorAction SilentlyContinue
        if ($proxyOverrideObj)
        {
            if ($WSUSFqdn)
            {
                # Check if WSUS server is in the overwrite list
                ######### NOTE: Also check the domain of the WSUS server
                if (-NOT ($proxyOverrideObj.ProxyOverride -imatch $WSUSFqdn))
                {
                    $stateObject.State = 'Failed'
                    $stateObject.RelatedInfo = 'System proxy enabled but WSUS server not in overwrite list {0}' -f $proxyString
                }
                else
                {
                    $stateObject.State = 'Ok'
                    $stateObject.RelatedInfo = 'System proxy enabled AND WSUS server IN overwrite list {0}' -f $proxyString
                }
            }
            else
            {
                $stateObject.State = 'Failed'
                $stateObject.RelatedInfo = 'System proxy enabled but WSUS server could not be detected. Not able to check overwrite list {0}' -f $proxyString         
            }
        }
        else
        {
            $stateObject.State = 'Failed'
            $stateObject.RelatedInfo = 'System proxy enabled but WSUS server not in overwrite list {0}' -f $proxyString
        }
    }
    else
    {
        $stateObject.State = 'Ok'
        if(-NOT ([string]::IsNullOrEmpty($proxyString)))
        {
            $stateObject.RelatedInfo = 'System proxy not enabled. But set: {0}' -f $proxyString
        }
        else
        {
            $stateObject.RelatedInfo = 'System proxy not enabled'
        }
    }
}
else
{
    $stateObject.State = 'Ok'
    if($proxyString)
    {
        $stateObject.RelatedInfo = 'System proxy not enabled. But set: {0}' -f $proxyString
    }
    else
    {
        $stateObject.RelatedInfo = 'System proxy not enabled'
    }
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
<#
# Example with wrong path:
function Set-Proxy($proxy, $bypassUrls){
    $proxyBytes = [system.Text.Encoding]::ASCII.GetBytes($proxy)
    $bypassBytes = [system.Text.Encoding]::ASCII.GetBytes($bypassUrls)
    $defaultConnectionSettings = [byte[]]@(@(70,0,0,0,0,0,0,0,11,0,0,0,$proxyBytes.Length,0,0,0)+$proxyBytes+@($bypassBytes.Length,0,0,0)+$bypassBytes+ @(1..36 | % {0}))
    $registryPath = Registry::"HKEY_USERS\S-1-5-18\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Set-ItemProperty -Path $registryPath -Name ProxyServer -Value $proxy
    Set-ItemProperty -Path $registryPath -Name ProxyEnable -Value 1
    Set-ItemProperty -Path $registryPath -Name ProxyOverride -Value $bypassUrls
    Set-ItemProperty -Path "$registryPath\Connections" -Name DefaultConnectionSettings -Value $defaultConnectionSettings
    netsh winhttp set proxy $proxy bypass-list=$bypassUrls
}
Set-Proxy "someproxy:1234" "*.example.com;<local>"
#>
#endregion


#region check local proxy setting
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Check local proxy config'
try
{
    $netshResult = netsh winhttp show proxy
}Catch{}
if ($netshResult)
{
    $settingFound = $false
    if ($netshResult -imatch 'Direct Access')
    {
        $settingFound = $true
        $stateObject.State = 'Ok'
        $stateObject.RelatedInfo = 'Direct Access. No winhttp proxy set'
    }
    elseif ($netshResult -imatch 'Proxy Server\(s\)')
    {
        $settingFound = $true
        # Proxy set. We also need to check the bypass list
        try
        {
            # Extracting bypass list for future actions. A simple match would also work, but this way we are be able to set the list if required
            $matchResult = [regex]::Matches($netshResult,'(Bypass List)\s+:\s+(?<bypasslist>.*)',[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $bypassListResult = $matchResult.Groups.Where({$_.Name -eq 'bypasslist'})
        }catch{}
        if ($bypassListResult)
        {
            if ($WSUSFqdn)
            {
                # Lets create a list of possible proxy bypass urls based on given WSUS server
                # web.test.contoso.local will be split into the following possible bypass urls:
                # web.test.contoso.local or *.test.contoso.local, or *.contoso.local
                $possibleProxyOverwrites = New-Object System.Collections.ArrayList
                [array]$splitUrlList = $WSUSFqdn -split '\.'
                for ($i = $splitUrlList.count-2; $i -ge 1; $i--)
                {
                    $URLString = '\*.{0}' -f ($splitUrlList[$i..($splitUrlList.count-1)] -join '.')
                    [void]$possibleProxyOverwrites.Add($URLString)
                }
                [void]$possibleProxyOverwrites.Add($WSUSFqdn)                
                $urlInBypassList = $false
                foreach ($URL in $possibleProxyOverwrites)
                {
                    if ($bypassListResult.value -imatch $URL)
                    {
                        $urlInBypassList = $true               
                    }
                }
                if ($urlInBypassList)
                {
                    $stateObject.State = 'Ok'
                    $stateObject.RelatedInfo = 'Winhttp proxy set with correct bypass list'
                }
                else
                {
                    $stateObject.State = 'Failed'
                    $stateObject.RelatedInfo = 'Winhttp proxy set but bypass list not correct'
                }
            }
            else
            {
                $stateObject.State = 'Failed'
                $stateObject.RelatedInfo = 'Winhttp proxy set but script failed to test bypass list'
            }
        }
        else
        {
            $stateObject.State = 'Failed'
            $stateObject.RelatedInfo = 'Winhttp proxy set but bypass list could not been determined'
        }
    }
    if (-NOT ($settingFound))
    {
        $stateObject.State = 'Failed'
        $stateObject.RelatedInfo = $netshResult # might be an issue with running netsh
    }
}
else
{
    $stateObject.State = 'Failed'
    $stateObject.RelatedInfo = 'netsh winhttp show proxy did not return anything' # Highly unlikly
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
#endregion


#region Test for WSUS scan error
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Check for WSUS scan error'
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
    $stateObject.RelatedInfo = 'No ScanState information found. {0}' -f ($Error[0].Exception | Select-Object *)
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
#endregion


#region check if any update is in failed state
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Check last security update install time'
try
{
    $installTime = Get-hotfix -ErrorAction Stop | Where-Object {$_.Description -ieq 'Security Update'} | Sort-Object -Property InstalledOn -Descending | Select-Object -First 1
    if ($installTime)
    {
        $dateDiff = New-TimeSpan -Start $installTime.InstalledOn -End (Get-Date)
        if ($dateDiff.TotalDays -gt $maxSecurityUpdateInstallAge)
        {
            $stateObject.State = 'Failed'
            $stateObject.RelatedInfo = 'Last security update installed {0} days ago. Max allowed days: {1}' -f [Math]::Round($dateDiff.TotalDays), $maxSecurityUpdateInstallAge
        }
        else
        {
            $stateObject.State = 'Ok'
            $stateObject.RelatedInfo = 'Last security update installed {0} days ago. Max allowed days: {1}' -f [Math]::Round($dateDiff.TotalDays), $maxSecurityUpdateInstallAge
        }
    }
    else
    {
        $stateObject.State = 'Failed'
        $stateObject.RelatedInfo = 'No security update found'
    }
}
catch
{
    $stateObject.State = 'Failed'
    $stateObject.RelatedInfo = $_.Exception.Message
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
#endregion


#region Test for updates
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Check for updates to install'
try
{
    [array]$listOfUpdates = Get-CimInstance -Namespace 'ROOT\ccm\ClientSDK' -ClassName CCM_SoftwareUpdate -ErrorAction Stop | Where-Object {$_.Name -NotLike "*Definition*" -and $_.Name -NotLike "*Defender*"}
    if ($listOfUpdates)
    {
        $stateObject.State = 'Ok'
        $stateObject.RelatedInfo = 'Found {0} updates available to be installed' -f $listOfUpdates.Count
    } 
    else
    {
        # if OS as latest version, no updates might be expected
        if ($outObj.Where({$_.Name -eq 'Check OS version' -and $_.State -eq 'Ok'}))
        {
            $stateObject.State = 'OK'
            $stateObject.RelatedInfo = 'No updates found. This might be expected. OS version: {0}' -f $fullVersionNumber
        }
        elseif ($outObj.Where({$_.Name -eq 'Check last security update install time' -and $_.State -eq 'Ok'}))
        {
            $stateObject.State = 'Ok'
            $stateObject.RelatedInfo = 'No updates found. This might be expected. OS version: {0}' -f $fullVersionNumber
        }
        else        
        {
            $stateObject.State = 'Failed'
            $stateObject.RelatedInfo = 'No updates found. OS version not latest. We might need to re-evaluate updates'
        }
    }
}
catch
{
    $stateObject.State = 'Error'
    $stateObject.RelatedInfo = 'Not able to get update list. {0}' -f ($Error[0].Exception | Select-Object *)
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
#endregion


#region check if any update is in failed state
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Check update state'
if ($listOfUpdates.Count -eq 0)
{
    $stateObject.State = 'Ok'
    $stateObject.RelatedInfo = 'No updates found. Cannot validate update state'
}
else
{
    $complianceStateNameVar =  @{label="ComplianceStateName";expression={$complianceStateHash[($_.ComplianceState).ToString()]}}
    $evaluationStateNameVar = @{label="EvaluationStateName";expression={$evaluationStateHash[($_.EvaluationState).ToString()]}}
    $listOfUpdatesWithStateNames = $listOfUpdates | Select-Object Name, ContentSize, ErrorCode, ExclusiveUpdate, $complianceStateNameVar, $evaluationStateNameVar
    $stateObject.State = if ($listOfUpdatesWithStateNames.EvaluationStateName -like '*error*'){'Failed'}else{'Ok'}
    $stateObject.State = 'Failed'
    $stateObject.RelatedInfo = $listOfUpdatesWithStateNames
    # we might need to have some logic here to further check each update or act on any detected state
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
#endregion


#region Define update install order
<#
    Updated should be installed in the following order to prevent issues during installation:
    Servicing Stack Update, OS cumulative update, .Net cumulative update, other updates
    Example order:
        '2021-08 Servicing Stack Update for Windows Server 2019 for x64-based Systems (KB5005112)' -match '\d{4}-\d{2} Servicing Stack Update'
        '2023-01 Cumulative Update for Windows Server 2019 for x64-based Systems (KB5022286)' -match '\d{4}-\d{2} Cumulative Update for Windows'
        '2022-12 Cumulative Update for .NET Framework 3.5, 4.7.2 and 4.8 for Windows Server 2019 for x64 (KB5021085)' -match '\d{4}-\d{2} Cumulative Update for \.NET'
        '2021-03 .NET Core 2.1.26 Security Update for x64 Server'
#>
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Define update install order'
if ($listOfUpdates.Count -eq 0)
{
    $stateObject.State = 'Ok'
   $stateObject.RelatedInfo = 'No updates found. Cannot define install order'  
}
else
{
    # will define update install order to prevent any installation errors
    $sortedListOfUpdates = New-Object System.Collections.ArrayList
    $firstUpdate = $listOfUpdates.Where({$_.Name -match '\d{4}-\d{2} Servicing Stack Update'})
    if ($firstUpdate){[void]$sortedListOfUpdates.Add($firstUpdate)}
    $secondUpdate = $listOfUpdates.Where({$_.Name -match '\d{4}-\d{2} (Cumulative Update for Windows)|(security monthly quality rollup)'})
    if ($secondUpdate){[void]$sortedListOfUpdates.Add($secondUpdate)}
    $thirdUpdate = $listOfUpdates.Where({$_.Name -match '\d{4}-\d{2} Cumulative Update for \.NET'})
    if ($thirdUpdate){[void]$sortedListOfUpdates.Add($thirdUpdate)}
    # Adding rest of updates to install list
    foreach ($update in $listOfUpdates)
    {
        if (-NOT($update.Name -in $sortedListOfUpdates.Name))
        {
            [void]$sortedListOfUpdates.Add($update)
        }
    }
    $stateObject.State = 'OK'
    $stateObject.RelatedInfo = ($sortedListOfUpdates | ForEach-Object {$_.Name})
}
if ($SendLog){ } # Nothing yet
[void]$outObj.Add($stateObject)
$stepCounter++
#endregion


#region Final check before installation
$stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
$stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
$stateObject.DeviceName = $env:COMPUTERNAME
$stateObject.Step = $stepCounter
$stateObject.Name = 'Final check before installation'
if ($outObj.where({$_.State -ine 'OK'}))
{
    $stateObject.State = 'Failed'
    $stateObject.RelatedInfo = 'Not able to run install yet, since we have at least one check in failed or error state'
    if ($SendLog){ } # Nothing yet
    [void]$outObj.Add($stateObject)
    $stepCounter++
}
else
{
    if ($AllowUpdateInstallation)
    {
        $stateObject.State = 'OK'
        $stateObject.RelatedInfo = 'Allowed to start update installation'
        [void]$outObj.Add($stateObject)
        #$stepCounter++
        #region update installation
        $secondStepCounter = 1
        foreach ($update in $sortedListOfUpdates)
        {
            $stateObject = New-Object pscustomobject | Select-Object -Property $propertyList
            $stateObject.CheckTime = Get-Date -Format 'yyyy-MM-dd hh:mm:ss'
            $stateObject.DeviceName = $env:COMPUTERNAME
            $stateObject.Step = "{0}.{1}" -f $stepCounter, $secondStepCounter
            $stateObject.Name = 'Install Update'
            $stateObject.RelatedInfo = $update.Name
            if ($SendLog){ } # Nothing yet        
            [void]$outObj.Add($stateObject)
            $secondStepCounter++
            # install
            # wait for update
            # honor timeout
            # restart after max one hour to have the same function as in the old script
            <#
                MaxExecutionTime
                EvaluationState
                ErrorCode
                ExclusiveUpdate
            #>
        }
        #endregion
    }
    else
    {
        $stateObject.State = 'OK'
        $stateObject.RelatedInfo = 'NOT allowed to start update installation yet'
        if ($SendLog){ } # Nothing yet
        [void]$outObj.Add($stateObject)
        $stepCounter++
    }
}
#endregion

# Output the result
Switch($OutMode)
{
    'JSON' { $outObj | ConvertTo-Json -Depth 10}
    'JSONCompressed' { $outObj | ConvertTo-Json -Depth 10 -Compress }
    'GridView' { $outObj | Out-GridView -Title 'List of check states' }
    'Object' { $outObj}
}