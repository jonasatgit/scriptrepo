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
# Source: https://github.com/jonasatgit/scriptrepo/blob/master/General/Get-CMPolicyViaBits.ps1
#
# Description
# -----------
# Downloads one or more Configuration Manager policy bodies (or any other URLs originally
# served to a CM client) via BITS in the LOCAL SYSTEM context, mirroring how the CM client
# itself fetches policy. Useful to:
#   * Reproduce / troubleshoot CM policy or content download issues from a Management Point
#     or Distribution Point (HTTP or HTTPS / E-HTTP with client certificate).
#   * Replay BITS jobs that were captured by BITS-MonitorWithLog.ps1 (it consumes the JSON
#     log file directly via -JobsJsonPath and lets you pick one or more jobs to re-run).
#   * Bulk-clean previously created test BITS jobs with -CleanupJobs.
#
# How it works
# ------------
#   1. When started in the user context, the script prepares the destination folder and
#      builds a batch manifest (Url -> LocalFile pairs) either from a single -PolicyUrl or
#      from the selected entries of a -JobsJsonPath file.
#   2. It then re-launches itself as NT AUTHORITY\SYSTEM through a one-shot scheduled task
#      (-RunAsSystem). This matches the security context of the real CM client and is
#      required for client-certificate based HTTPS (E-HTTP).
#   3. In SYSTEM context the script creates the BITS transfer(s), waits for them, and
#      writes a transcript to <Destination>\_Script.log.
#
# Parameter sets
# --------------
#   Download : -PolicyUrl <url>                    Single URL download.
#   FromJson : -JobsJsonPath <file>                Pick jobs from a BITS-MonitorWithLog JSON.
#   Cleanup  : -CleanupJobs                        Remove all CMPolicyTest_* BITS jobs.
#   Batch    : (internal, used by the SYSTEM relaunch via -BatchFile)
#
# Common parameters
# -----------------
#   -Destination  Output folder (created if missing). Also receives _Script.log.
#   -UseHttps     Force HTTPS (port 443). Requires a client cert in LocalMachine\SMS or My.
#
# Examples
# --------
#   # Single policy URL over HTTP
#   .\Get-CMPolicyViaBits.ps1 -PolicyUrl 'http://MP01.contoso.com/SMS_MP/.sms_pol?{GUID}.5_00'
#
#   # Same URL over HTTPS / E-HTTP using the client certificate
#   .\Get-CMPolicyViaBits.ps1 -PolicyUrl 'http://MP01.contoso.com/SMS_MP/.sms_pol?{GUID}.5_00' -UseHttps
#
#   # Replay one or more jobs captured by BITS-MonitorWithLog.ps1
#   .\Get-CMPolicyViaBits.ps1 -JobsJsonPath 'C:\Temp\BITS-Monitor-Log.json'
#
#   # Remove leftover test jobs
#   .\Get-CMPolicyViaBits.ps1 -CleanupJobs
#
# Requirements
# ------------
#   * Run from an elevated PowerShell session (the script self-elevates to SYSTEM via
#     a scheduled task, but registering that task requires admin rights).
#   * BITS service running.
#   * For -UseHttps: a valid CM client certificate in LocalMachine\SMS or LocalMachine\My.
#************************************************************************************************************



[CmdletBinding(DefaultParameterSetName='Download')]
param(
    [Parameter(Mandatory, ParameterSetName='Download')]
    [string]$PolicyUrl,                       # e.g. http://MP01.contoso.com/SMS_MP/.sms_pol?{GUID}.5_00

    [Parameter(Mandatory, ParameterSetName='FromJson')]
    [string]$JobsJsonPath,                    # path to a JSON file with one or more BITS job objects

    [string]$Destination = "C:\Temp\PolicyTest",   # output folder (also holds _Script.log)
    [switch]$UseHttps,                        # force E-HTTP (port 443, requires client cert)

    [ValidateSet('Foreground','High','Normal','Low')]
    [string]$Priority = 'Foreground',         # BITS priority for the created job(s)

    [Parameter(Mandatory, ParameterSetName='Cleanup')]
    [switch]$CleanupJobs,                     # remove all 'CMPolicyTest_*' BITS jobs (runs as SYSTEM)

    [string]$JobName,                         # internal: BITS DisplayName carried into SYSTEM context
    [Parameter(Mandatory, ParameterSetName='Batch')]
    [string]$BatchFile,                       # internal: path to a JSON file of {Url, LocalFile} pairs
    [switch]$RunAsSystem                      # internal: set when relaunched as SYSTEM
)

$ErrorActionPreference = 'Stop'
$ScriptStart = Get-Date
Write-Host ("Script start : {0}" -f $ScriptStart.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor Green

function Resolve-FileNameFromUrl {
    param([string]$Url)
    $leaf = ([uri]$Url).Segments[-1]
    $leaf = [System.Uri]::UnescapeDataString($leaf)
    # Sanitize for Windows file system
    $leaf = ($leaf -replace '[\\/:*?"<>|]', '_').TrimStart('.')
    if (-not $leaf) { $leaf = "file_$([Guid]::NewGuid().ToString('N'))" }
    return "$leaf.bin"
}

# ---------- USER-CONTEXT (not RunAsSystem): prepare and dispatch ----------
if (-not $RunAsSystem) {
    if (-not $CleanupJobs) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        $Destination  = (Resolve-Path $Destination).Path
        $jobTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $jobName      = "CMPolicyTest_$jobTimestamp"

        if ($PSCmdlet.ParameterSetName -eq 'FromJson') {
            if (-not (Test-Path $JobsJsonPath)) {
                throw "JSON file not found: $JobsJsonPath"
            }
            $jsonRaw = Get-Content $JobsJsonPath -Raw | ConvertFrom-Json

            # Accept three shapes: single object, array of objects, or dictionary keyed by JobId
            if ($jsonRaw -is [System.Collections.IEnumerable] -and -not ($jsonRaw -is [string])) {
                $jobs = @($jsonRaw)
            }
            elseif ($jsonRaw.PSObject.Properties.Name -contains 'JobId') {
                $jobs = @($jsonRaw)
            }
            else {
                # Dictionary form: { "<guid>": { ...job... }, ... }
                $jobs = @($jsonRaw.PSObject.Properties | ForEach-Object { $_.Value })
            }
            Write-Host "Loaded $($jobs.Count) job(s) from $JobsJsonPath" -ForegroundColor Green

            # Filter out upload jobs (BITS uploads aren't replayable as downloads)
            $beforeCount = $jobs.Count
            $jobs = @($jobs | Where-Object { $_.DisplayName -notmatch '(?i)upload' -and $_.TransferType -ne 'Upload' })
            $skippedUploads = $beforeCount - $jobs.Count
            if ($skippedUploads -gt 0) {
                Write-Host "Filtered out $skippedUploads upload job(s)." -ForegroundColor Yellow
            }

            # Show selection UI (multi-select)
            $choices = $jobs |
                Select-Object JobId, DisplayName, JobState, FilesTotal, BytesTotalMB, CreationTime |
                Out-GridView -Title 'Pick one or more BITS jobs to replay (Ctrl/Shift-click)' -OutputMode Multiple

            if (-not $choices -or $choices.Count -eq 0) {
                # Fallback to numbered text menu
                Write-Host "Out-GridView returned nothing. Pick job(s) (comma-separated indexes):" -ForegroundColor Yellow
                for ($i = 0; $i -lt $jobs.Count; $i++) {
                    Write-Host (" [{0}] {1}  files={2}  state={3}  {4}" -f $i, $jobs[$i].JobId, $jobs[$i].FilesTotal, $jobs[$i].JobState, $jobs[$i].DisplayName)
                }
                $raw = Read-Host "Indexes"
                $idxList = $raw -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
                if (-not $idxList -or ($idxList | Where-Object { $_ -ge $jobs.Count })) { throw "Invalid selection." }
                $pickedJobs = $idxList | ForEach-Object { $jobs[$_] }
            } else {
                $pickedIds  = $choices | ForEach-Object { $_.JobId }
                $pickedJobs = $jobs | Where-Object { $pickedIds -contains $_.JobId }
            }
            Write-Host "Selected $($pickedJobs.Count) job(s):" -ForegroundColor Green
            $pickedJobs | ForEach-Object { Write-Host "  - $($_.JobId)  $($_.DisplayName)  files=$($_.FileList.Count)" }

            # Build the multi-job manifest: array of { JobName, Pairs:[{Url,LocalFile},...] }
            $usedNames = @{}
            $multi = foreach ($picked in $pickedJobs) {
                $pairs = foreach ($f in $picked.FileList) {
                    $url = $f.RemoteName
                    if ($UseHttps) { $url = $url -replace '^http://','https://' -replace '(https://[^/:]+):80(/|$)','$1$2' }
                    if ($f.LocalName) {
                        $name = Split-Path -Path $f.LocalName -Leaf
                    } else {
                        $name = Resolve-FileNameFromUrl $url
                    }
                    $name = ($name -replace '[\\/:*?"<>|]', '_')
                    $base = $name; $n = 1
                    while ($usedNames.ContainsKey($name)) {
                        if ($base -match '^(.*?)(\.[^.]+)$') { $name = "$($Matches[1])_$n$($Matches[2])" }
                        else                                  { $name = "${base}_$n" }
                        $n++
                    }
                    $usedNames[$name] = $true
                    [pscustomobject]@{ Url = $url; LocalFile = (Join-Path $Destination $name) }
                }
                [pscustomobject]@{
                    JobName    = "CMPolicyTest_${jobTimestamp}_$($picked.JobId.Substring(0,8))"
                    SourceId   = $picked.JobId
                    SourceName = $picked.DisplayName
                    Pairs      = @($pairs)
                }
            }

            $BatchFile = Join-Path $Destination "_batch_$jobTimestamp.json"
            ConvertTo-Json -InputObject ([object[]]$multi) -Depth 6 | Set-Content -Path $BatchFile -Encoding UTF8
            Write-Host "Wrote batch manifest: $BatchFile  ($($multi.Count) job(s), $(($multi.Pairs | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum) file(s) total)" -ForegroundColor Green
        }
        else {
            # Single-URL flow
            if ($UseHttps) {
                $PolicyUrl = $PolicyUrl -replace '^http://','https://' -replace '(https://[^/:]+):80(/|$)','$1$2'
            }
            $name    = Resolve-FileNameFromUrl $PolicyUrl
            $outFile = Join-Path $Destination $name
        }
    }

    # Relaunch this script under NT AUTHORITY\SYSTEM via a one-shot scheduled task
    $taskName = "BITS_PolicyTest_$(Get-Random)"
    $psExe    = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $argLine  = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -RunAsSystem"
    if ($CleanupJobs) {
        $argLine += " -CleanupJobs"
    } elseif ($BatchFile) {
        $argLine += " -BatchFile `"$BatchFile`" -Destination `"$Destination`" -JobName `"$jobName`" -Priority $Priority"
        if ($UseHttps) { $argLine += " -UseHttps" }
    } else {
        $argLine += " -PolicyUrl `"$PolicyUrl`" -Destination `"$Destination`" -JobName `"$jobName`" -Priority $Priority"
        if ($UseHttps) { $argLine += " -UseHttps" }
    }

    $action    = New-ScheduledTaskAction -Execute $psExe -Argument $argLine
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Host "Started SYSTEM task '$taskName'. Waiting for completion..." -ForegroundColor Green
    do { Start-Sleep 2 } while ((Get-ScheduledTask -TaskName $taskName).State -ne 'Ready')
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    if ($CleanupJobs) {
        $stale = Get-ScheduledTask -TaskName 'BITS_PolicyTest_*' -ErrorAction SilentlyContinue
        foreach ($t in $stale) {
            Write-Host " Removing stale task: $($t.TaskName)"
            Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false
        }
        Write-Host "Done. Cleanup performed." -ForegroundColor Green
    }
    else { Write-Host "Done. Output folder: $Destination" -ForegroundColor Green }

    $ScriptEnd = Get-Date
    $tot = $ScriptEnd - $ScriptStart

    # ---- Final statistics (console + log) ----
    if (-not $CleanupJobs) {
        $downloaded = Get-ChildItem -LiteralPath $Destination -File -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -ne '_Script.log' -and $_.Name -notlike '_batch_*.json' -and $_.Name -notlike '*-unpacked.*' }
        $totalSize = ($downloaded | Measure-Object -Property Length -Sum).Sum
        if (-not $totalSize) { $totalSize = 0 }
        $totalMb   = [math]::Round($totalSize / 1MB, 2)

        # Use SYSTEM-recorded download-only time when present (excludes post-processing/unpack)
        $runtimeFile = Join-Path $Destination '_runtime.txt'
        if (Test-Path -LiteralPath $runtimeFile) {
            try {
                $secs = [double](Get-Content -LiteralPath $runtimeFile -Raw -ErrorAction Stop).Trim()
                $dlSpan = [TimeSpan]::FromSeconds($secs)
                Remove-Item -LiteralPath $runtimeFile -Force -ErrorAction SilentlyContinue
            } catch { $dlSpan = $tot }
        } else { $dlSpan = $tot }

        $stats = @(
            ''
            '==================== STATISTICS ===================='
            ("Files downloaded : {0}" -f $downloaded.Count)
            ("Total size       : {0} MB ({1:N0} bytes)" -f $totalMb, $totalSize)
            ("Download time    : {0:hh\:mm\:ss\.fff}  ({1:N3} s)" -f $dlSpan, $dlSpan.TotalSeconds)
            ("Total runtime    : {0:hh\:mm\:ss\.fff}  ({1:N3} s)  (incl. post-processing)" -f $tot, $tot.TotalSeconds)
            '===================================================='
        )
        $stats | ForEach-Object { Write-Host $_ -ForegroundColor Green }

        $logPath = Join-Path $Destination '_Script.log'
        try { Add-Content -LiteralPath $logPath -Value $stats -ErrorAction SilentlyContinue } catch {}
    } else {
        Write-Host ("Script end   : {0}" -f $ScriptEnd.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor Green
        Write-Host ("Script total : {0:hh\:mm\:ss\.fff}  ({1:N3} s)" -f $tot, $tot.TotalSeconds) -ForegroundColor Green
    }
    return
}

# ====================== From here on we are NT AUTHORITY\SYSTEM ======================

if ($CleanupJobs) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Start-Transcript -Path (Join-Path $Destination '_Script.log') -Append | Out-Null
    Write-Host "Identity: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor Green
    Write-Host "Cleaning up 'CMPolicyTest_*' / 'CM Policy Test*' BITS jobs..." -ForegroundColor Green
    $jobs = Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'CMPolicyTest_*' -or $_.DisplayName -like 'CM Policy Test*' }
    if (-not $jobs) {
        Write-Host "No matching jobs." -ForegroundColor Yellow
    } else {
        foreach ($j in $jobs) {
            Write-Host (" Removing {0}  state={1}  owner={2}" -f $j.JobId, $j.JobState, $j.OwnerAccount)
            Remove-BitsTransfer -BitsJob $j -ErrorAction Continue
        }
        Write-Host ("Removed {0} job(s)." -f $jobs.Count) -ForegroundColor Green
    }
    Stop-Transcript | Out-Null
    return
}

Start-Transcript -Path (Join-Path $Destination '_Script.log') -Append | Out-Null
Write-Host "Identity: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor Green
Write-Host "Mode    : $(if ($UseHttps) { 'HTTPS + client cert' } else { 'HTTP anonymous' })   Priority: $Priority" -ForegroundColor Green
$jobStart = Get-Date
Write-Host "Started : $($jobStart.ToString('yyyy-MM-dd HH:mm:ss.fff'))" -ForegroundColor Green

# Resolve client cert once (HTTPS only)
$clientCert = $null
$physStoreName = $null
if ($UseHttps) {
    foreach ($store in @('Cert:\LocalMachine\SMS', 'Cert:\LocalMachine\My')) {
        $found = Get-ChildItem $store -ErrorAction SilentlyContinue |
            Where-Object {
                $_.HasPrivateKey -and
                $_.NotAfter -gt (Get-Date) -and
                ($_.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.2')
            } | Sort-Object NotAfter -Descending
        if ($found) { $clientCert = $found | Select-Object -First 1; $foundStore = $store; break }
    }
    if (-not $clientCert) {
        Write-Error "No client auth cert with private key found in LocalMachine\SMS or LocalMachine\My - cannot do HTTPS."
        Stop-Transcript | Out-Null; return
    }
    $physStoreName = if ($foundStore -like '*\SMS') { 'SMS' } else { 'MY' }
    Write-Host "ClientCert: $($clientCert.Subject)" -ForegroundColor Green
    Write-Host "  Issuer  : $($clientCert.Issuer)" -ForegroundColor Green
    Write-Host "  Store   : $foundStore" -ForegroundColor Green
    Write-Host "  Thumb   : $($clientCert.Thumbprint)" -ForegroundColor Green
}

# Helper: run one BITS job for a set of pairs, return a stats object
function Invoke-OneBitsJob {
    param(
        [string]$Name,
        [object[]]$Pairs,
        [bool]$Https,
        [object]$Cert,
        [string]$CertStore,
        [string]$Priority = 'Foreground'
    )
    $bitsadmin = "$env:WINDIR\System32\bitsadmin.exe"
    foreach ($p in $Pairs) { if (Test-Path $p.LocalFile) { Remove-Item $p.LocalFile -Force } }

    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Green
    Write-Host "Job: $Name   Files: $($Pairs.Count)   Mode: $(if ($Https) {'HTTPS+cert'} else {'HTTP'})   Priority: $Priority" -ForegroundColor Green
    Write-Host "==============================================================" -ForegroundColor Green
    $start = Get-Date

    $bytes = 0; $state = 'UNKNOWN'; $info = ''

    if (-not $Https) {
        $sources = @($Pairs | ForEach-Object { $_.Url })
        $dests   = @($Pairs | ForEach-Object { $_.LocalFile })
        $job = Start-BitsTransfer -Source $sources -Destination $dests -TransferType Download `
                -Priority $Priority -DisplayName $Name -Asynchronous
        while ($job.JobState -in 'Connecting','Transferring','Queued','TransientError') {
            Start-Sleep -Milliseconds 500
            $job = Get-BitsTransfer -JobId $job.JobId
        }
        $bytes = [int64]$job.BytesTransferred
        if ($job.JobState -eq 'Transferred') {
            Complete-BitsTransfer -BitsJob $job
            $state = 'TRANSFERRED'
        } else {
            Write-Host "FAILED: $($job.JobState) - $($job.ErrorDescription)" -ForegroundColor Red
            $state = $job.JobState.ToString().ToUpper()
            Remove-BitsTransfer -BitsJob $job
        }
    } else {
        Write-Host "--- bitsadmin /create ---"
        & $bitsadmin /create /download $Name | Out-Host
        foreach ($p in $Pairs) {
            & $bitsadmin /addfile $Name $p.Url $p.LocalFile | Out-Host
        }
        & $bitsadmin /setpriority $Name $Priority.ToUpper() | Out-Host
        & $bitsadmin /setclientcertificatebyid $Name 2 $CertStore $Cert.Thumbprint | Out-Host
        & $bitsadmin /resume $Name | Out-Host

        $deadline = (Get-Date).AddMinutes(10)
        do {
            Start-Sleep -Milliseconds 500
            $info  = & $bitsadmin /info $Name /verbose 2>&1 | Out-String
            $m     = [regex]::Match($info, '(?i)\bSTATE:\s*(\S+)')
            $state = if ($m.Success) { $m.Groups[1].Value.ToUpper() } else { 'UNKNOWN' }
        } while ($state -in 'QUEUED','CONNECTING','TRANSFERRING','TRANSIENT_ERROR' -and (Get-Date) -lt $deadline)

        $mb = [regex]::Match($info, '(?i)\bBYTES:\s*(\d+)\s*/')
        if ($mb.Success) { $bytes = [int64]$mb.Groups[1].Value }

        $color = if ($state -eq 'TRANSFERRED') { 'Green' } else { 'Red' }
        Write-Host "Final state: $state" -ForegroundColor $color
        if ($state -eq 'TRANSFERRED') {
            & $bitsadmin /complete $Name | Out-Host
        } else {
            Write-Host "--- bitsadmin /info (failure detail) ---"
            Write-Host $info
            & $bitsadmin /cancel $Name | Out-Host
        }
    }

    $end = Get-Date
    [pscustomobject]@{
        JobName  = $Name
        Files    = $Pairs.Count
        Bytes    = $bytes
        State    = $state
        Start    = $start
        End      = $end
        Elapsed  = ($end - $start)
    }
}

# Build the work list
$workList = @()
if ($BatchFile) {
    if (-not (Test-Path $BatchFile)) { Write-Error "Batch file not found: $BatchFile"; Stop-Transcript|Out-Null; return }
    $manifest = Get-Content $BatchFile -Raw | ConvertFrom-Json
    if ($manifest -isnot [System.Collections.IEnumerable] -or $manifest -is [string]) { $manifest = @($manifest) }

    # Multi-job manifest: items have JobName + Pairs.  Legacy single-batch: items have Url + LocalFile.
    if ($manifest[0].PSObject.Properties.Name -contains 'Pairs') {
        $workList = @($manifest | ForEach-Object {
            [pscustomobject]@{ JobName = $_.JobName; Pairs = @($_.Pairs) }
        })
    } else {
        $workList = @([pscustomobject]@{ JobName = $JobName; Pairs = @($manifest) })
    }
    Write-Host "Batch  : $BatchFile  ($($workList.Count) BITS job(s), $(($workList.Pairs | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum) file(s) total)" -ForegroundColor Green
} else {
    $pairs = ,([pscustomobject]@{ Url = $PolicyUrl; LocalFile = (Join-Path $Destination (Resolve-FileNameFromUrl $PolicyUrl)) })
    $workList = @([pscustomobject]@{ JobName = $JobName; Pairs = $pairs })
    Write-Host "URL    : $PolicyUrl" -ForegroundColor Green
    Write-Host "Output : $($pairs[0].LocalFile)" -ForegroundColor Green
}

# Execute and collect stats
$results = foreach ($w in $workList) {
    Invoke-OneBitsJob -Name $w.JobName -Pairs $w.Pairs -Https:$UseHttps -Cert $clientCert -CertStore $physStoreName -Priority $Priority
}

$jobEnd  = Get-Date
$elapsed = $jobEnd - $jobStart

# Persist pure download time so the user-side dispatcher can show it (excluding post-processing)
try {
    Set-Content -LiteralPath (Join-Path $Destination '_runtime.txt') `
                -Value ([string]$elapsed.TotalSeconds) -Encoding ASCII -ErrorAction SilentlyContinue
} catch {}

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " SUMMARY" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
$results |
    Select-Object @{n='JobName';e={$_.JobName}},
                  @{n='State';e={$_.State}},
                  @{n='Files';e={$_.Files}},
                  @{n='Bytes';e={$_.Bytes}},
                  @{n='Start';e={$_.Start.ToString('HH:mm:ss.fff')}},
                  @{n='End';e={$_.End.ToString('HH:mm:ss.fff')}},
                  @{n='Elapsed';e={('{0:hh\:mm\:ss\.fff}' -f $_.Elapsed)}},
                  @{n='Sec';e={[math]::Round($_.Elapsed.TotalSeconds,3)}} |
    Format-Table -AutoSize | Out-Host

$totalBytes = ($results | Measure-Object Bytes -Sum).Sum
$okCount    = ($results | Where-Object State -eq 'TRANSFERRED').Count
$sumColor   = if ($okCount -eq $results.Count) { 'Green' } else { 'Yellow' }
Write-Host ("Totals : {0}/{1} job(s) OK   {2} file(s)   {3:N0} bytes" -f `
    $okCount, $results.Count, ($results | Measure-Object Files -Sum).Sum, $totalBytes) -ForegroundColor $sumColor
Write-Host ("Finished: {0}" -f $jobEnd.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor Green
Write-Host ("Overall : {0:hh\:mm\:ss\.fff}  ({1:N3} s)" -f $elapsed, $elapsed.TotalSeconds) -ForegroundColor Green
$ScriptEnd = Get-Date
$tot       = $ScriptEnd - $ScriptStart
Write-Host ("Script start : {0}" -f $ScriptStart.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor Green
Write-Host ("Script end   : {0}" -f $ScriptEnd.ToString('yyyy-MM-dd HH:mm:ss.fff')) -ForegroundColor Green
Write-Host ("Script total : {0:hh\:mm\:ss\.fff}  ({1:N3} s)" -f $tot, $tot.TotalSeconds) -ForegroundColor Green

# --- Post-processing: rename downloaded files to .xml when content is XML --------------
Write-Host ""
Write-Host "Post-processing: sniffing downloaded files for XML content..." -ForegroundColor Green
$allFiles = $workList | ForEach-Object { $_.Pairs } | ForEach-Object { $_.LocalFile } | Sort-Object -Unique
$renamed = 0; $skipped = 0; $missing = 0; $errors = 0
foreach ($f in $allFiles) {
    try {
        if (-not (Test-Path -LiteralPath $f -ErrorAction SilentlyContinue)) { $missing++; continue }
        # Read up to 1024 bytes and decode using BOM if present, else UTF-8
        $buf = $null; $read = 0
        try {
            $stream = [System.IO.File]::Open($f, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try {
                $buf  = New-Object byte[] 1024
                $read = $stream.Read($buf, 0, $buf.Length)
            } finally { $stream.Dispose() }
        } catch {
            Write-Host ("  SKIP (read failed): {0} - {1}" -f (Split-Path $f -Leaf), $_.Exception.Message)
            $errors++; continue
        }
        if ($read -le 0) { $skipped++; continue }

        $enc = [System.Text.Encoding]::UTF8
        $off = 0
        if     ($read -ge 3 -and $buf[0] -eq 0xEF -and $buf[1] -eq 0xBB -and $buf[2] -eq 0xBF)            { $enc = [System.Text.Encoding]::UTF8;    $off = 3 }
        elseif ($read -ge 2 -and $buf[0] -eq 0xFF -and $buf[1] -eq 0xFE)                                  { $enc = [System.Text.Encoding]::Unicode; $off = 2 }   # UTF-16 LE
        elseif ($read -ge 2 -and $buf[0] -eq 0xFE -and $buf[1] -eq 0xFF)                                  { $enc = [System.Text.Encoding]::BigEndianUnicode; $off = 2 }
        elseif ($read -ge 4 -and $buf[0] -eq 0x3C -and $buf[1] -eq 0x00 -and $buf[2] -eq 0x3F -and $buf[3] -eq 0x00) { $enc = [System.Text.Encoding]::Unicode; $off = 0 }   # UTF-16 LE no BOM

        $text  = $enc.GetString($buf, $off, $read - $off).TrimStart(' ', "`r", "`n", "`t")
        $isXml = $text.StartsWith('<?xml', [StringComparison]::OrdinalIgnoreCase) -or
                 ($text.StartsWith('<') -and $text -match '^<[A-Za-z_!?][^>]*>')
        if (-not $isXml) { $skipped++; continue }

        $dir   = Split-Path -Path $f -Parent
        $base  = [IO.Path]::GetFileNameWithoutExtension($f)
        $newP  = Join-Path $dir "$base.xml"
        if ($newP -ieq $f) { $skipped++; continue }   # already .xml
        if (Test-Path -LiteralPath $newP -ErrorAction SilentlyContinue) { Remove-Item -LiteralPath $newP -Force -ErrorAction SilentlyContinue }
        try {
            [System.IO.File]::Move($f, $newP)
            Write-Host ("  XML : {0}  ->  {1}" -f (Split-Path $f -Leaf), (Split-Path $newP -Leaf)) -ForegroundColor Green
            $renamed++
        } catch {
            Write-Host ("  ERR (rename): {0} - {1}" -f (Split-Path $f -Leaf), $_.Exception.Message)
            $errors++
        }
    } catch {
        Write-Host ("  ERR : {0} - {1}" -f (Split-Path $f -Leaf), $_.Exception.Message)
        $errors++
    }
}
Write-Host ("Post-processing: renamed={0}  kept={1}  missing={2}  errors={3}" -f $renamed, $skipped, $missing, $errors) -ForegroundColor Green

# --- Decompress zlib-packed policy bodies -> *-unpacked.xml ---
function Expand-CMZlib {
    param([Parameter(Mandatory)][string]$HexBlob)
    $hex = ($HexBlob -replace '[\s\r\n]','')
    if ($hex.Length -lt 12 -or ($hex.Length % 2)) { throw "Invalid hex blob length: $($hex.Length)" }
    $raw = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $raw.Length; $i++) { $raw[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
    # Strip 2-byte zlib header + trailing 4-byte Adler32 -> raw DEFLATE
    $deflate = New-Object byte[] ($raw.Length - 6)
    [Array]::Copy($raw, 2, $deflate, 0, $deflate.Length)
    $in  = New-Object System.IO.MemoryStream(,$deflate)
    $out = New-Object System.IO.MemoryStream
    $ds  = New-Object System.IO.Compression.DeflateStream($in, [System.IO.Compression.CompressionMode]::Decompress)
    try { $ds.CopyTo($out) } finally { $ds.Dispose(); $in.Dispose() }
    return ,$out.ToArray()
}

Write-Host ""
Write-Host "Post-processing: decompressing zlib policy bodies..." -ForegroundColor Green
$unpacked = 0; $unpackErr = 0
$xmlFiles = Get-ChildItem -LiteralPath $Destination -File -Filter *.xml -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '*-unpacked.xml' }
foreach ($xf in $xmlFiles) {
    try {
        # Load the XML using BOM-aware decoding
        $xml = $null
        try { $xml = [xml](Get-Content -LiteralPath $xf.FullName -Raw -ErrorAction Stop) } catch { $xml = $null }
        if (-not $xml) { continue }

        # Find any element with Compression="zlib"
        $nodes = $xml.SelectNodes("//*[@Compression='zlib']")
        if (-not $nodes -or $nodes.Count -eq 0) { continue }

        foreach ($n in $nodes) {
            $hex = $n.InnerText
            if ([string]::IsNullOrWhiteSpace($hex)) { continue }
            try {
                $bytes = Expand-CMZlib -HexBlob $hex
                # Decode: try UTF-16 LE BOM, then UTF-16 LE no-BOM, then UTF-8
                $text = $null
                if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                    $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
                } elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                    $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
                } elseif ($bytes.Length -ge 4 -and $bytes[0] -eq 0x3C -and $bytes[1] -eq 0x00) {
                    $text = [System.Text.Encoding]::Unicode.GetString($bytes)
                } else {
                    $text = [System.Text.Encoding]::Unicode.GetString($bytes)
                    if ($text -notmatch '<') { $text = [System.Text.Encoding]::UTF8.GetString($bytes) }
                }

                $outName = "{0}-unpacked.xml" -f [IO.Path]::GetFileNameWithoutExtension($xf.Name)
                $outPath = Join-Path $xf.DirectoryName $outName
                Set-Content -LiteralPath $outPath -Value $text -Encoding UTF8
                Write-Host ("  UNPACK: {0}  ->  {1}  ({2:N0} bytes)" -f $xf.Name, $outName, $bytes.Length) -ForegroundColor Green
                $unpacked++
                break   # one unpack per file
            } catch {
                Write-Host ("  ERR (unpack): {0} - {1}" -f $xf.Name, $_.Exception.Message)
                $unpackErr++
            }
        }
    } catch {
        Write-Host ("  ERR (xml): {0} - {1}" -f $xf.Name, $_.Exception.Message)
        $unpackErr++
    }
}
Write-Host ("Post-processing: unpacked={0}  errors={1}" -f $unpacked, $unpackErr) -ForegroundColor Green

# --- Decompress raw zlib binary files (e.g. CM .zip CIs that are actually zlib streams) ---
Write-Host ""
Write-Host "Post-processing: decompressing raw zlib binary files..." -ForegroundColor Green
$binUnpacked = 0; $binErr = 0
$candidates = Get-ChildItem -LiteralPath $Destination -File -ErrorAction SilentlyContinue |
              Where-Object {
                  $_.Name -ne '_Script.log' -and
                  $_.Name -notlike '_batch_*.json' -and
                  $_.Name -notlike '*-unpacked.xml' -and
                  $_.Length -ge 6
              }
foreach ($cf in $candidates) {
    try {
        $fs = [System.IO.File]::Open($cf.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $hdr = New-Object byte[] 2
            [void]$fs.Read($hdr, 0, 2)
        } finally { $fs.Dispose() }

        # zlib magic: 0x78 (CMF) followed by one of 01/5E/9C/DA (FLG)
        if ($hdr[0] -ne 0x78) { continue }
        if ($hdr[1] -notin 0x01,0x5E,0x9C,0xDA) { continue }

        $raw = [System.IO.File]::ReadAllBytes($cf.FullName)
        if ($raw.Length -lt 6) { continue }
        $deflate = New-Object byte[] ($raw.Length - 6)
        [Array]::Copy($raw, 2, $deflate, 0, $deflate.Length)
        $in  = New-Object System.IO.MemoryStream(,$deflate)
        $out = New-Object System.IO.MemoryStream
        $ds  = New-Object System.IO.Compression.DeflateStream($in, [System.IO.Compression.CompressionMode]::Decompress)
        try { $ds.CopyTo($out) } finally { $ds.Dispose(); $in.Dispose() }
        $bytes = $out.ToArray()
        if ($bytes.Length -eq 0) { continue }

        # Decide output extension by sniffing decompressed content
        $isXml = $false
        $sample = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                      [System.Text.Encoding]::Unicode.GetString($bytes, 2, [Math]::Min(256, $bytes.Length - 2))
                  } elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                      [System.Text.Encoding]::UTF8.GetString($bytes, 3, [Math]::Min(256, $bytes.Length - 3))
                  } elseif ($bytes.Length -ge 4 -and $bytes[0] -eq 0x3C -and $bytes[1] -eq 0x00) {
                      [System.Text.Encoding]::Unicode.GetString($bytes, 0, [Math]::Min(512, $bytes.Length))
                  } else {
                      [System.Text.Encoding]::UTF8.GetString($bytes, 0, [Math]::Min(256, $bytes.Length))
                  }
        $sample = $sample.TrimStart(' ',"`r","`n","`t",[char]0xFEFF)
        if ($sample.StartsWith('<?xml',[StringComparison]::OrdinalIgnoreCase) -or
            ($sample.StartsWith('<') -and $sample -match '^<[A-Za-z_!?][^>]*>')) { $isXml = $true }

        $base    = [IO.Path]::GetFileNameWithoutExtension($cf.Name)
        $ext     = if ($isXml) { '-unpacked.xml' } else { '-unpacked.bin' }
        $outPath = Join-Path $cf.DirectoryName ("$base$ext")
        [System.IO.File]::WriteAllBytes($outPath, $bytes)
        Write-Host ("  UNZIP : {0}  ->  {1}  ({2:N0} bytes)" -f $cf.Name, (Split-Path $outPath -Leaf), $bytes.Length) -ForegroundColor Green
        $binUnpacked++
    } catch {
        Write-Host ("  ERR (unzip): {0} - {1}" -f $cf.Name, $_.Exception.Message)
        $binErr++
    }
}
Write-Host ("Post-processing: zlib binaries unpacked={0}  errors={1}" -f $binUnpacked, $binErr) -ForegroundColor Green

# --- Total size of downloaded files (exclude _Script.log, _batch_*.json, *-unpacked.*) ---
$downloaded = Get-ChildItem -LiteralPath $Destination -File -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -ne '_Script.log' -and $_.Name -notlike '_batch_*.json' -and $_.Name -notlike '*-unpacked.*' }
$totalSize = ($downloaded | Measure-Object -Property Length -Sum).Sum
if (-not $totalSize) { $totalSize = 0 }
Write-Host ("Total downloaded: {0} file(s)   {1:N0} bytes   {2:N2} MB" -f `
    $downloaded.Count, $totalSize, ($totalSize / 1MB)) -ForegroundColor Green

# --- Build "Final" folder: unpacked files + originals that were not packed ---
Write-Host ""
Write-Host "Post-processing: assembling 'Final' folder..." -ForegroundColor Green
$finalDir = Join-Path $Destination 'Final'
New-Item -ItemType Directory -Force -Path $finalDir | Out-Null

$allInDest = Get-ChildItem -LiteralPath $Destination -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -ne '_Script.log' -and $_.Name -ne '_runtime.txt' -and $_.Name -notlike '_batch_*.json' }

# Collect base names (without -unpacked suffix) of every file that produced an unpacked output
$unpackedBases = @{}
foreach ($u in $allInDest | Where-Object { $_.Name -like '*-unpacked.*' }) {
    $n = $u.Name
    # Strip "-unpacked<ext>" to get the source base name
    $base = $n -replace '-unpacked\.[^.]+$',''
    $unpackedBases[$base] = $true
}

$copiedUnpacked = 0; $copiedOriginal = 0
foreach ($f in $allInDest) {
    if ($f.Name -like '*-unpacked.*') {
        # Copy the unpacked file as-is
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $finalDir $f.Name) -Force
        $copiedUnpacked++
    }
    else {
        # Skip originals that have an unpacked counterpart
        $thisBase = [IO.Path]::GetFileNameWithoutExtension($f.Name)
        if ($unpackedBases.ContainsKey($thisBase)) { continue }
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $finalDir $f.Name) -Force
        $copiedOriginal++
    }
}
Write-Host ("Final folder: {0}  (unpacked copied={1}, originals copied={2})" -f $finalDir, $copiedUnpacked, $copiedOriginal) -ForegroundColor Green

Stop-Transcript | Out-Null
