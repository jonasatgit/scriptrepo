<#
.SYNOPSIS
    Tests and optionally resumes BitLocker protection on the operating system volume.

.DESCRIPTION
    Designed for use as a Microsoft Configuration Manager configuration item. The default
    output is "Compliant" when the operating system volume is fully encrypted and protected.
    Otherwise, the script returns a compact diagnostic value suitable for a CI current value.

    Diagnostic output includes the remaining suspension reboot count, recent suspend/resume
    events, resume failures, key protector types, and TPM state. The event log can usually show
    when suspension occurred, but Windows does not always record which application or command
    initiated a generic suspension.

    Remediation is deliberately limited to resuming protectors on a fully encrypted, suspended
    operating system volume that still has at least one key protector. It does not start
    encryption or create protectors.

.PARAMETER Remediate
    Attempts to resume BitLocker when the operating system volume is fully encrypted,
    protection is off, and at least one key protector exists. Keep the default value false
    for the ConfigMgr discovery script. Set the default value to true in the copy used as
    the ConfigMgr remediation script.

.PARAMETER OutputType
    ComplianceState returns "Compliant" or a compact noncompliance description.
    Object returns a PowerShell object. Json returns the same diagnostic data as JSON.

.PARAMETER EventLookbackDays
    Number of days of BitLocker events to inspect. The default is 30.

.PARAMETER MaxDiagnosticEvents
    Maximum number of recent warning/error and resume-failure events included in detailed
    output. The default is 20.

.EXAMPLE
    .\Test-BitLockerProtection.ps1

    Returns a ConfigMgr-friendly compliance value. Configure the CI compliance rule as:
    returned value must equal the string "Compliant".

.EXAMPLE
    .\Test-BitLockerProtection.ps1 -OutputType Json

    Returns detailed diagnostic evidence as JSON.

.EXAMPLE
    .\Test-BitLockerProtection.ps1 -Remediate $true

    Safely attempts to resume a fully encrypted, suspended operating system volume.

.NOTES
    ConfigMgr configuration item:
    - Discovery script: paste the script unchanged, select String as the data type, and
      configure the compliance rule as Equals "Compliant".
    - Remediation script: paste a second copy and change the Remediate parameter default
      below from $false to $true.
    - Run the scripts in the 64-bit PowerShell host on 64-bit clients.

.LINK
    https://learn.microsoft.com/windows/win32/secprov/getsuspendcount-win32-encryptablevolume

.LINK
    https://learn.microsoft.com/troubleshoot/windows-client/windows-security/bitlocker-issues-troubleshooting
#>

[CmdletBinding(SupportsShouldProcess)]
param
(
    [Parameter(Mandatory=$false)]
    [bool]$Remediate = $false,

    [Parameter(Mandatory=$false)]
    [ValidateSet('ComplianceState', 'Object', 'Json')]
    [string]$OutputType = 'ComplianceState',

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 365)]
    [int]$EventLookbackDays = 30,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 100)]
    [int]$MaxDiagnosticEvents = 20
)

$ErrorActionPreference = 'Stop'
$bitLockerNamespace = 'Root\CIMV2\Security\MicrosoftVolumeEncryption'
$tpmNamespace = 'Root\CIMV2\Security\MicrosoftTpm'
$mountPoint = $env:SystemDrive.TrimEnd('\')

$protectionStatusNames = @{
    0 = 'Off'
    1 = 'On'
    2 = 'Unknown'
}

$conversionStatusNames = @{
    0 = 'FullyDecrypted'
    1 = 'FullyEncrypted'
    2 = 'EncryptionInProgress'
    3 = 'DecryptionInProgress'
    4 = 'EncryptionPaused'
    5 = 'DecryptionPaused'
}

$keyProtectorTypeNames = @{
    0  = 'Unknown'
    1  = 'Tpm'
    2  = 'ExternalKey'
    3  = 'RecoveryPassword'
    4  = 'TpmAndPin'
    5  = 'TpmAndStartupKey'
    6  = 'TpmAndPinAndStartupKey'
    7  = 'PublicKey'
    8  = 'Passphrase'
    9  = 'TpmCertificate'
    10 = 'Cng'
}

function Get-MappedValue
{
    param
    (
        [Parameter(Mandatory=$true)]
        [hashtable]$Map,

        [Parameter(Mandatory=$true)]
        [int]$Value
    )

    if ($Map.ContainsKey($Value))
    {
        return $Map[$Value]
    }

    return 'Unknown ({0})' -f $Value
}

function Get-BitLockerEvents
{
    param
    (
        [Parameter(Mandatory=$true)]
        [datetime]$StartTime,

        [Parameter(Mandatory=$true)]
        [int]$MaximumEvents
    )

    $logNames = @(
        'Microsoft-Windows-BitLocker-API/Management',
        'Microsoft-Windows-BitLocker-API/Operational'
    )
    $events = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($logName in $logNames)
    {
        try
        {
            $log = Get-WinEvent -ListLog $logName -ErrorAction Stop
            if (-not $log.IsEnabled)
            {
                $errors.Add("Event log is disabled: $logName")
                continue
            }

            $logEvents = Get-WinEvent -FilterHashtable @{
                LogName = $logName
                StartTime = $StartTime
            } -ErrorAction Stop

            foreach ($event in $logEvents)
            {
                $events.Add($event)
            }
        }
        catch [System.Exception]
        {
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*')
            {
                continue
            }

            $errors.Add("Unable to read $logName. $($_.Exception.Message)")
        }
    }

    $orderedEvents = @($events | Sort-Object TimeCreated -Descending)
    $failureEventIds = @(819, 820, 821, 822, 842, 844, 865, 904, 905)
    $diagnosticEvents = @(
        $orderedEvents |
            Where-Object { $_.Level -in @(1, 2, 3) -or $_.Id -in $failureEventIds } |
            Select-Object -First $MaximumEvents |
            ForEach-Object {
                [pscustomobject]@{
                    TimeCreated = $_.TimeCreated
                    Id = $_.Id
                    Level = $_.LevelDisplayName
                    LogName = $_.LogName
                    Message = (($_.Message -replace '\s+', ' ').Trim())
                }
            }
    )

    return [pscustomobject]@{
        LastSuspend = @(
            $orderedEvents |
                Where-Object { $_.Id -in @(773, 843) } |
                Select-Object -First 1 |
                ForEach-Object {
                    [pscustomobject]@{
                        TimeCreated = $_.TimeCreated
                        Id = $_.Id
                        LogName = $_.LogName
                        InitiatedFrom = if ($_.Id -eq 843) { 'WindowsRecoveryEnvironment' } else { 'BitLockerApi-UnspecifiedCaller' }
                        UserId = if ($_.UserId) { $_.UserId.Value } else { $null }
                        ProcessId = $_.ProcessId
                        Message = (($_.Message -replace '\s+', ' ').Trim())
                    }
                }
        ) | Select-Object -First 1
        LastResume = @(
            $orderedEvents |
                Where-Object { $_.Id -eq 774 } |
                Select-Object -First 1 |
                ForEach-Object {
                    [pscustomobject]@{
                        TimeCreated = $_.TimeCreated
                        Id = $_.Id
                        LogName = $_.LogName
                        UserId = if ($_.UserId) { $_.UserId.Value } else { $null }
                        ProcessId = $_.ProcessId
                        Message = (($_.Message -replace '\s+', ' ').Trim())
                    }
                }
        ) | Select-Object -First 1
        ResumeFailures = @(
            $orderedEvents |
                Where-Object { $_.Id -in $failureEventIds } |
                Select-Object -First $MaximumEvents |
                ForEach-Object {
                    [pscustomobject]@{
                        TimeCreated = $_.TimeCreated
                        Id = $_.Id
                        Level = $_.LevelDisplayName
                        Message = (($_.Message -replace '\s+', ' ').Trim())
                    }
                }
        )
        DiagnosticEvents = $diagnosticEvents
        CollectionErrors = @($errors)
    }
}

function Get-KeyProtectorTypes
{
    param
    (
        [Parameter(Mandatory=$true)]
        [Microsoft.Management.Infrastructure.CimInstance]$Volume
    )

    $protectorsResult = Invoke-CimMethod -InputObject $Volume -MethodName GetKeyProtectors -Arguments @{
        KeyProtectorType = [uint32]0
    }
    if ($protectorsResult.ReturnValue -ne 0)
    {
        throw 'GetKeyProtectors failed with error 0x{0:X8}.' -f $protectorsResult.ReturnValue
    }

    $protectorTypes = [System.Collections.Generic.List[string]]::new()
    foreach ($protectorId in @($protectorsResult.VolumeKeyProtectorID))
    {
        $typeResult = Invoke-CimMethod -InputObject $Volume -MethodName GetKeyProtectorType -Arguments @{
            VolumeKeyProtectorID = $protectorId
        }
        if ($typeResult.ReturnValue -ne 0)
        {
            throw 'GetKeyProtectorType failed for protector {0} with error 0x{1:X8}.' -f $protectorId, $typeResult.ReturnValue
        }

        $protectorTypes.Add((Get-MappedValue -Map $keyProtectorTypeNames -Value $typeResult.KeyProtectorType))
    }

    return @($protectorTypes)
}

$collectionErrors = [System.Collections.Generic.List[string]]::new()
$likelyReasons = [System.Collections.Generic.List[string]]::new()
$remediationResult = 'NotRequested'

try
{
    $escapedMountPoint = $mountPoint.Replace('\', '\\').Replace("'", "''")
    $volume = Get-CimInstance -Namespace $bitLockerNamespace -ClassName Win32_EncryptableVolume -Filter "DriveLetter = '$escapedMountPoint'"
    if (-not $volume)
    {
        throw "The BitLocker WMI provider did not return the operating system volume $mountPoint."
    }

    $protectionResult = Invoke-CimMethod -InputObject $volume -MethodName GetProtectionStatus
    if ($protectionResult.ReturnValue -ne 0)
    {
        throw 'GetProtectionStatus failed with error 0x{0:X8}.' -f $protectionResult.ReturnValue
    }

    $conversionResult = Invoke-CimMethod -InputObject $volume -MethodName GetConversionStatus -Arguments @{
        PrecisionFactor = [uint32]0
    }
    if ($conversionResult.ReturnValue -ne 0)
    {
        throw 'GetConversionStatus failed with error 0x{0:X8}.' -f $conversionResult.ReturnValue
    }

    $protectionStatus = [int]$protectionResult.ProtectionStatus
    $conversionStatus = [int]$conversionResult.ConversionStatus
    $keyProtectorTypes = @(Get-KeyProtectorTypes -Volume $volume)
    $remainingReboots = $null
    $originalPlannedReboots = $null

    if ($protectionStatus -eq 0 -and $conversionStatus -eq 1)
    {
        try
        {
            $suspendResult = Invoke-CimMethod -InputObject $volume -MethodName GetSuspendCount
            if ($suspendResult.ReturnValue -eq 0)
            {
                $remainingReboots = [int]$suspendResult.SuspendCount
            }
            else
            {
                $collectionErrors.Add('GetSuspendCount returned error 0x{0:X8}.' -f $suspendResult.ReturnValue)
            }
        }
        catch [System.Exception]
        {
            $collectionErrors.Add("Unable to read the suspension reboot count. $($_.Exception.Message)")
        }
    }

    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
    $lastBootTime = $operatingSystem.LastBootUpTime

    $tpm = $null
    try
    {
        if (Get-Command -Name Get-Tpm -ErrorAction SilentlyContinue)
        {
            $tpmState = Get-Tpm
            $tpm = [pscustomobject]@{
                Present = [bool]$tpmState.TpmPresent
                Ready = [bool]$tpmState.TpmReady
                Enabled = [bool]$tpmState.TpmEnabled
                Activated = [bool]$tpmState.TpmActivated
                Owned = [bool]$tpmState.TpmOwned
                LockedOut = [bool]$tpmState.LockedOut
                ManufacturerVersion = $tpmState.ManufacturerVersion
            }
        }
        else
        {
            $tpmState = Get-CimInstance -Namespace $tpmNamespace -ClassName Win32_Tpm |
                Select-Object -First 1
            if ($tpmState)
            {
                $tpm = [pscustomobject]@{
                    Present = $true
                    Ready = $null
                    Enabled = [bool]$tpmState.IsEnabled_InitialValue
                    Activated = [bool]$tpmState.IsActivated_InitialValue
                    Owned = [bool]$tpmState.IsOwned_InitialValue
                    LockedOut = $null
                    ManufacturerVersion = $tpmState.ManufacturerVersion
                }
            }
        }
    }
    catch [System.Exception]
    {
        $collectionErrors.Add("Unable to query TPM state. $($_.Exception.Message)")
    }

    $eventEvidence = Get-BitLockerEvents -StartTime (Get-Date).AddDays(-$EventLookbackDays) -MaximumEvents $MaxDiagnosticEvents
    foreach ($eventError in $eventEvidence.CollectionErrors)
    {
        $collectionErrors.Add($eventError)
    }

    if ($null -ne $remainingReboots)
    {
        if ($remainingReboots -eq 0)
        {
            $originalPlannedReboots = 0
        }
        elseif ($eventEvidence.LastSuspend -and $eventEvidence.LastSuspend.TimeCreated -ge $lastBootTime)
        {
            $originalPlannedReboots = $remainingReboots
        }
    }

    if ($conversionStatus -eq 0)
    {
        $likelyReasons.Add('The OS volume is fully decrypted; this is not a suspended BitLocker state.')
    }
    elseif ($conversionStatus -ne 1)
    {
        $likelyReasons.Add("The OS volume conversion state is $(Get-MappedValue -Map $conversionStatusNames -Value $conversionStatus).")
    }
    elseif ($protectionStatus -eq 0)
    {
        if ($null -eq $remainingReboots)
        {
            $likelyReasons.Add('The OS volume is fully encrypted with protection off, but the remaining reboot count could not be read.')
        }
        elseif ($remainingReboots -eq 0)
        {
            $likelyReasons.Add('BitLocker was suspended indefinitely; manual resume is required.')
        }
        else
        {
            $likelyReasons.Add("BitLocker is still within its planned suspension window; $remainingReboots reboot(s) remain.")
        }

        if ($keyProtectorTypes.Count -eq 0)
        {
            $likelyReasons.Add('No key protectors exist on the OS volume, so protection cannot be resumed safely.')
        }
    }
    elseif ($protectionStatus -eq 2)
    {
        $likelyReasons.Add('Windows could not determine the BitLocker protection status.')
    }

    if ($tpm)
    {
        if (-not $tpm.Present)
        {
            $likelyReasons.Add('No TPM is present.')
        }
        if ($null -ne $tpm.Ready -and -not $tpm.Ready)
        {
            $likelyReasons.Add('The TPM is not ready.')
        }
        if (-not $tpm.Enabled)
        {
            $likelyReasons.Add('The TPM is not enabled.')
        }
        if (-not $tpm.Activated)
        {
            $likelyReasons.Add('The TPM is not activated.')
        }
        if ($tpm.LockedOut)
        {
            $likelyReasons.Add('The TPM is locked out.')
        }
    }

    foreach ($failure in @($eventEvidence.ResumeFailures))
    {
        if (-not $eventEvidence.LastSuspend -or $failure.TimeCreated -ge $eventEvidence.LastSuspend.TimeCreated)
        {
            $likelyReasons.Add("Resume failure event $($failure.Id) at $($failure.TimeCreated.ToString('s')): $($failure.Message)")
        }
    }

    if ($Remediate)
    {
        if ($protectionStatus -eq 1)
        {
            $remediationResult = 'AlreadyProtected'
        }
        elseif ($conversionStatus -ne 1)
        {
            $remediationResult = 'SkippedNotFullyEncrypted'
        }
        elseif ($keyProtectorTypes.Count -eq 0)
        {
            $remediationResult = 'SkippedNoKeyProtectors'
        }
        elseif ($PSCmdlet.ShouldProcess($mountPoint, 'Resume BitLocker protection'))
        {
            $resumeResult = Invoke-CimMethod -InputObject $volume -MethodName EnableKeyProtectors
            if ($resumeResult.ReturnValue -ne 0)
            {
                throw 'EnableKeyProtectors failed with error 0x{0:X8}.' -f $resumeResult.ReturnValue
            }

            $protectionResult = Invoke-CimMethod -InputObject $volume -MethodName GetProtectionStatus
            if ($protectionResult.ReturnValue -ne 0)
            {
                throw 'Post-remediation GetProtectionStatus failed with error 0x{0:X8}.' -f $protectionResult.ReturnValue
            }

            $protectionStatus = [int]$protectionResult.ProtectionStatus
            if ($protectionStatus -ne 1)
            {
                throw 'BitLocker resume returned success, but protection status is still {0}.' -f (
                    Get-MappedValue -Map $protectionStatusNames -Value $protectionStatus
                )
            }

            $remediationResult = 'ProtectionResumed'
            $likelyReasons.Clear()
        }
    }

    $isCompliant = $protectionStatus -eq 1 -and $conversionStatus -eq 1
    $result = [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        CheckedAt = Get-Date
        MountPoint = $mountPoint
        IsCompliant = $isCompliant
        LastBootTime = $lastBootTime
        ProtectionStatus = Get-MappedValue -Map $protectionStatusNames -Value $protectionStatus
        ConversionStatus = Get-MappedValue -Map $conversionStatusNames -Value $conversionStatus
        EncryptionPercentage = [int]$conversionResult.EncryptionPercentage
        RemainingSuspensionReboots = $remainingReboots
        OriginalPlannedReboots = $originalPlannedReboots
        KeyProtectorTypes = $keyProtectorTypes
        Tpm = $tpm
        LastSuspendEvent = $eventEvidence.LastSuspend
        LastResumeEvent = $eventEvidence.LastResume
        ResumeFailureEvents = @($eventEvidence.ResumeFailures)
        RecentDiagnosticEvents = @($eventEvidence.DiagnosticEvents)
        LikelyReasons = @($likelyReasons | Select-Object -Unique)
        CollectionErrors = @($collectionErrors)
        RemediationResult = $remediationResult
    }
}
catch [System.Exception]
{
    $result = [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        CheckedAt = Get-Date
        MountPoint = $mountPoint
        IsCompliant = $false
        LastBootTime = $null
        ProtectionStatus = 'Error'
        ConversionStatus = 'Error'
        EncryptionPercentage = $null
        RemainingSuspensionReboots = $null
        OriginalPlannedReboots = $null
        KeyProtectorTypes = @()
        Tpm = $null
        LastSuspendEvent = $null
        LastResumeEvent = $null
        ResumeFailureEvents = @()
        RecentDiagnosticEvents = @()
        LikelyReasons = @('BitLocker state collection or remediation failed.')
        CollectionErrors = @($_.Exception.Message)
        RemediationResult = 'Failed'
    }
}

switch ($OutputType)
{
    'ComplianceState'
    {
        if ($result.IsCompliant)
        {
            Write-Output 'Compliant'
        }
        else
        {
            $details = [System.Collections.Generic.List[string]]::new()
            $details.Add("Protection=$($result.ProtectionStatus)")
            $details.Add("Conversion=$($result.ConversionStatus)")
            if ($null -ne $result.RemainingSuspensionReboots)
            {
                $details.Add("RemainingReboots=$($result.RemainingSuspensionReboots)")
            }
            if ($null -ne $result.OriginalPlannedReboots)
            {
                $details.Add("OriginalPlannedReboots=$($result.OriginalPlannedReboots)")
            }
            if ($result.LastSuspendEvent)
            {
                $details.Add("Suspended=$($result.LastSuspendEvent.TimeCreated.ToString('s'))")
                $details.Add("SuspendSource=$($result.LastSuspendEvent.InitiatedFrom)")
            }
            if ($result.LikelyReasons.Count -gt 0)
            {
                $details.Add("Reason=$($result.LikelyReasons -join ' | ')")
            }
            if ($result.CollectionErrors.Count -gt 0)
            {
                $details.Add("Errors=$($result.CollectionErrors -join ' | ')")
            }

            Write-Output ('NonCompliant;{0}' -f ($details -join ';'))
        }
    }
    'Object'
    {
        Write-Output $result
    }
    'Json'
    {
        Write-Output ($result | ConvertTo-Json -Depth 6 -Compress)
    }
}
