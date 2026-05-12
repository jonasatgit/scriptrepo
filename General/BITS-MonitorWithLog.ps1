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
# Source: https://github.com/jonasatgit/scriptrepo/blob/master/General/BITS-MonitorWithLog.ps1
#
# Monitors BITS jobs in PowerShell and persists every observed job to a JSON file.
# On each refresh cycle (default 5 seconds) the script:
#   1. Loads the existing JSON file (if any)
#   2. Gets the current BITS jobs
#   3. Adds new jobs that have not been seen before
#   4. Updates already known jobs with the latest counters / state
#   5. Calculates total runtime (FirstSeen -> LastSeen) and the approximate
#      transfer speed (BytesTransferred / runtime)
#   6. Writes the data back to the JSON file with enough depth to capture the
#      full job (including FileList)
#
# Needs to be run as an admin.
#
# Parameters:
#   -JsonPath          Path of the JSON output file
#   -TimeoutSeconds    Refresh interval in seconds (default 5)
#************************************************************************************************************

[CmdletBinding()]
param(
    [string]$JsonPath,
    [int]$TimeoutSeconds = 5
)

# Resolve default JSON path here so an empty $PSScriptRoot (e.g. when the script
# is pasted into a console) does not break Join-Path in the param block.
if ([string]::IsNullOrWhiteSpace($JsonPath))
{
    $baseDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($baseDir)) { $baseDir = $PSCommandPath | Split-Path -Parent -ErrorAction SilentlyContinue }
    if ([string]::IsNullOrWhiteSpace($baseDir)) { $baseDir = (Get-Location).Path }
    $JsonPath = Join-Path -Path $baseDir -ChildPath 'BITS-Monitor-Log.json'
}

#region admin rights
if (-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Warning 'The script needs admin rights to run. Start PowerShell with administrative rights and run the script again'
    return
}
#endregion

# (Default JSON path is resolved above, before the admin check)

Write-Host "Using JSON log file: $JsonPath"
Write-Host "Refresh interval  : $TimeoutSeconds second(s)"
Write-Host ''

# Depth used when (de)serializing the BITS jobs - FileList items add a couple of nesting levels
[int]$jsonDepth = 6

function Get-BitsLog
{
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path))
    {
        return @{}
    }

    try
    {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw))
        {
            return @{}
        }

        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        $hash = @{}
        foreach ($prop in $obj.PSObject.Properties)
        {
            $hash[$prop.Name] = $prop.Value
        }
        return $hash
    }
    catch
    {
        Write-Warning "Failed to read existing JSON log '$Path' - starting fresh. ($_)"
        return @{}
    }
}

function Save-BitsLog
{
    param(
        [hashtable]$Log,
        [string]$Path,
        [int]$Depth
    )

    try
    {
        # Convert to a PSCustomObject so ConvertTo-Json keeps the JobID keys as properties
        $obj = [PSCustomObject]$Log
        $json = $obj | ConvertTo-Json -Depth $Depth
        # Write atomically to avoid a partially written file if the script is stopped
        $tmp = "$Path.tmp"
        Set-Content -LiteralPath $tmp -Value $json -Encoding UTF8 -Force
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    }
    catch
    {
        Write-Warning "Failed to write JSON log '$Path': $_"
    }
}

function ConvertTo-ValidDateTimeString
{
    # BITS can return DateTime.MinValue (year 0001) for fields that have not been set yet
    # (e.g. TransferCompletionTime while the job is still running). Treat those as $null
    # so they do not poison the runtime calculation.
    param($Value)
    if ($null -eq $Value) { return $null }
    try
    {
        $dt = [datetime]$Value
        if ($dt -le [datetime]::MinValue.AddYears(1)) { return $null }
        return $dt.ToString('o')
    }
    catch
    {
        return $null
    }
}

function ConvertTo-UInt64Safe
{
    # BITS reports UInt64.MaxValue (18446744073709551615) for unknown sizes,
    # which does not fit in [int64]. Keep the value as [uint64] or $null.
    param($Value)
    if ($null -eq $Value) { return $null }
    try   { return [uint64]$Value }
    catch { return $null }
}

function ConvertTo-MegaBytes
{
    # Returns the value in MB rounded to 2 decimals, or $null if the input
    # is missing / equals UInt64.MaxValue (BITS "unknown size" sentinel).
    param($Value)
    if ($null -eq $Value) { return $null }
    try
    {
        $u = [uint64]$Value
        if ($u -eq [uint64]::MaxValue) { return $null }
        return [math]::Round(([double]$u / 1MB), 2)
    }
    catch { return $null }
}

function ConvertTo-SerializableFileList
{
    param($FileList)

    if (-not $FileList) { return @() }

    $result = @()
    foreach ($file in $FileList)
    {
        $result += [PSCustomObject]@{
            RemoteName         = $file.RemoteName
            LocalName          = $file.LocalName
            BytesTotal         = ConvertTo-UInt64Safe -Value $file.BytesTotal
            BytesTotalMB       = ConvertTo-MegaBytes  -Value $file.BytesTotal
            BytesTransferred   = ConvertTo-UInt64Safe -Value $file.BytesTransferred
            BytesTransferredMB = ConvertTo-MegaBytes  -Value $file.BytesTransferred
        }
    }
    return $result
}

function Format-Bytes
{
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f [int]$Bytes)
}

function Format-Duration
{
    param([double]$Seconds)
    if ($Seconds -lt 0) { $Seconds = 0 }
    return [TimeSpan]::FromSeconds([math]::Round($Seconds)).ToString()
}

while ($true)
{
    Clear-Host
    $now = Get-Date
    $log = Get-BitsLog -Path $JsonPath

    $bitsJobs = Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue

    if (-not $bitsJobs)
    {
        Write-Host "[$($now.ToString('yyyy-MM-dd HH:mm:ss'))] No active BITS jobs. JSON log entries: $($log.Keys.Count)"
    }
    else
    {
        foreach ($job in $bitsJobs)
        {
            $jobId = $job.JobId.ToString()

            if ($log.ContainsKey($jobId))
            {
                # Update existing entry - keep FirstSeen, refresh everything else
                $entry              = $log[$jobId]
                $entry.LastSeen     = $now.ToString('o')
                $entry.DisplayName  = $job.DisplayName
                $entry.Description  = $job.Description
                $entry.TransferType = "$($job.TransferType)"
                $entry.JobState     = "$($job.JobState)"
                $entry.OwnerAccount = $job.OwnerAccount
                $entry.Priority     = "$($job.Priority)"
                $entry.BytesTotal         = ConvertTo-UInt64Safe -Value $job.BytesTotal
                $entry.BytesTotalMB       = ConvertTo-MegaBytes  -Value $job.BytesTotal
                $entry.BytesTransferred   = ConvertTo-UInt64Safe -Value $job.BytesTransferred
                $entry.BytesTransferredMB = ConvertTo-MegaBytes  -Value $job.BytesTransferred
                $entry.FilesTotal       = [int]$job.FilesTotal
                $entry.FilesTransferred = [int]$job.FilesTransferred
                $entry.ErrorCondition   = "$($job.ErrorCondition)"
                $entry.HttpStatus       = $job.HttpStatus
                $entry.ProxyList        = ($job.ProxyList -join ';')
                $entry.FileList         = ConvertTo-SerializableFileList -FileList $job.FileList

                # CreationTime / ModificationTime / TransferCompletionTime from BITS itself
                $ct  = ConvertTo-ValidDateTimeString -Value $job.CreationTime
                $mt  = ConvertTo-ValidDateTimeString -Value $job.ModificationTime
                $tct = ConvertTo-ValidDateTimeString -Value $job.TransferCompletionTime
                if ($ct)  { $entry.CreationTime           = $ct }
                if ($mt)  { $entry.ModificationTime       = $mt }
                if ($tct) { $entry.TransferCompletionTime = $tct }
            }
            else
            {
                # New job - create entry
                $entry = [ordered]@{
                    JobId            = $jobId
                    FirstSeen        = $now.ToString('o')
                    LastSeen         = $now.ToString('o')
                    DisplayName      = $job.DisplayName
                    Description      = $job.Description
                    TransferType     = "$($job.TransferType)"
                    JobState         = "$($job.JobState)"
                    OwnerAccount     = $job.OwnerAccount
                    Priority         = "$($job.Priority)"
                    BytesTotal         = ConvertTo-UInt64Safe -Value $job.BytesTotal
                    BytesTotalMB       = ConvertTo-MegaBytes  -Value $job.BytesTotal
                    BytesTransferred   = ConvertTo-UInt64Safe -Value $job.BytesTransferred
                    BytesTransferredMB = ConvertTo-MegaBytes  -Value $job.BytesTransferred
                    FilesTotal       = [int]$job.FilesTotal
                    FilesTransferred = [int]$job.FilesTransferred
                    ErrorCondition   = "$($job.ErrorCondition)"
                    HttpStatus       = $job.HttpStatus
                    ProxyList        = ($job.ProxyList -join ';')
                    CreationTime         = ConvertTo-ValidDateTimeString -Value $job.CreationTime
                    ModificationTime     = ConvertTo-ValidDateTimeString -Value $job.ModificationTime
                    TransferCompletionTime = ConvertTo-ValidDateTimeString -Value $job.TransferCompletionTime
                    FileList         = ConvertTo-SerializableFileList -FileList $job.FileList
                }
                $log[$jobId] = [PSCustomObject]$entry
            }
        }
    }

    # Refresh derived field (TotalRunTimeSeconds) for every entry in the log
    foreach ($jobId in @($log.Keys))
    {
        $entry = $log[$jobId]

        try
        {
            # Prefer the BITS reported CreationTime as the start so the value also reflects
            # time before the script was first started
            $start = $null
            if ($entry.CreationTime) { $start = [datetime]$entry.CreationTime }
            elseif ($entry.FirstSeen) { $start = [datetime]$entry.FirstSeen }

            $end = $null
            if ($entry.TransferCompletionTime) { $end = [datetime]$entry.TransferCompletionTime }
            elseif ($entry.LastSeen)           { $end = [datetime]$entry.LastSeen }

            if ($start -and $end)
            {
                $duration = ($end - $start).TotalSeconds

                # If the job started and finished between two refresh cycles we can only
                # say the runtime is shorter than the refresh interval. Clamp negative or
                # tiny values to the refresh interval and flag them.
                $belowRefresh = $false
                if ($duration -lt $TimeoutSeconds)
                {
                    $duration     = $TimeoutSeconds
                    $belowRefresh = $true
                }

                $entry | Add-Member -NotePropertyName TotalRunTimeSeconds -NotePropertyValue ([math]::Round($duration, 2)) -Force
                $entry | Add-Member -NotePropertyName TotalRunTimeDisplay -NotePropertyValue $(if ($belowRefresh) { "<${TimeoutSeconds}s" } else { Format-Duration -Seconds $duration }) -Force

                # Make sure the previously stored speed fields are removed if they exist
                if ($entry.PSObject.Properties['AverageBytesPerSecond']) { $entry.PSObject.Properties.Remove('AverageBytesPerSecond') }
                if ($entry.PSObject.Properties['AverageSpeedDisplay'])   { $entry.PSObject.Properties.Remove('AverageSpeedDisplay') }
            }
        }
        catch
        {
            # Ignore individual entry calculation errors
        }
    }

    # Persist the log
    Save-BitsLog -Log $log -Path $JsonPath -Depth $jsonDepth

    # Console table (active jobs only) - same look & feel as BITS-Monitor.ps1
    if ($bitsJobs)
    {
        $bitsJobs | Format-Table   @{Expression={$_.JobID};Label="JobID"},
                                   @{Expression={$_.DisplayName};Label="DisplayName"},
                                   @{Expression={$_.TransferType};Label="TransferType"},
                                   @{Expression={"{0:N2}" -f ($_.BytesTotal/1MB)};Label="MBTotal"},
                                   @{Expression={"{0:N2}" -f ($_.BytesTransferred/1MB)};Label="MBTransferred"},
                                   @{Expression={ if ($_.BytesTotal -gt 0) { ("{0:N2}%" -f ((100 / $_.BytesTotal) * $_.BytesTransferred)) } else { 'n/a' } };Label="Total%"},
                                   @{Expression={$_.JobState};Label="Jobstate"},
                                   @{Expression={
                                        $id = $_.JobId.ToString()
                                        if ($log.ContainsKey($id) -and $log[$id].PSObject.Properties['TotalRunTimeDisplay'])
                                        {
                                            $log[$id].TotalRunTimeDisplay
                                        }
                                        elseif ($log.ContainsKey($id) -and $log[$id].PSObject.Properties['TotalRunTimeSeconds'])
                                        {
                                            Format-Duration -Seconds ([double]$log[$id].TotalRunTimeSeconds)
                                        } else { '' }
                                     };Label="RunTime"},
                                   @{Expression={$_.FileList[0].RemoteName};Label="FirstURL"}
    }

    Write-Host ("Log file        : {0}" -f $JsonPath)
    Write-Host ("Tracked jobs    : {0}" -f $log.Keys.Count)
    Write-Host ("Active BITS jobs: {0}" -f (@($bitsJobs).Count))
    Write-Host ("Next refresh in {0}s ... (Ctrl+C to stop)" -f $TimeoutSeconds)

    Start-Sleep -Seconds $TimeoutSeconds
}
