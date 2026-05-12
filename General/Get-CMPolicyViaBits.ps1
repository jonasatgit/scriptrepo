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
#      writes a transcript to <Destination>\bits.log.
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
#   -Destination  Output folder (created if missing). Also receives bits.log.
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

    [string]$Destination = "C:\Temp\PolicyTest",   # output folder (also holds bits.log)
    [switch]$UseHttps,                        # force E-HTTP (port 443, requires client cert)

    [Parameter(Mandatory, ParameterSetName='Cleanup')]
    [switch]$CleanupJobs,                     # remove all 'CMPolicyTest_*' BITS jobs (runs as SYSTEM)

    [string]$JobName,                         # internal: BITS DisplayName carried into SYSTEM context
    [Parameter(Mandatory, ParameterSetName='Batch')]
    [string]$BatchFile,                       # internal: path to a JSON file of {Url, LocalFile} pairs
    [switch]$RunAsSystem                      # internal: set when relaunched as SYSTEM
)

$ErrorActionPreference = 'Stop'

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
            Write-Host "Loaded $($jobs.Count) job(s) from $JobsJsonPath"

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
            Write-Host "Selected $($pickedJobs.Count) job(s):"
            $pickedJobs | ForEach-Object { Write-Host "  - $($_.JobId)  $($_.DisplayName)  files=$($_.FileList.Count)" }

            # Build the multi-job manifest: array of { JobName, Pairs:[{Url,LocalFile},...] }
            $usedNames = @{}
            $multi = foreach ($picked in $pickedJobs) {
                $pairs = foreach ($f in $picked.FileList) {
                    $url = $f.RemoteName
                    if ($UseHttps) { $url = $url -replace '^http://','https://' -replace '(https://[^/:]+):80(/|$)','$1$2' }
                    $name = Resolve-FileNameFromUrl $url
                    $base = $name; $n = 1
                    while ($usedNames.ContainsKey($name)) { $name = ($base -replace '\.bin$', "_$n.bin"); $n++ }
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
            Write-Host "Wrote batch manifest: $BatchFile  ($($multi.Count) job(s), $(($multi.Pairs | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum) file(s) total)"
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
        $argLine += " -BatchFile `"$BatchFile`" -Destination `"$Destination`" -JobName `"$jobName`""
        if ($UseHttps) { $argLine += " -UseHttps" }
    } else {
        $argLine += " -PolicyUrl `"$PolicyUrl`" -Destination `"$Destination`" -JobName `"$jobName`""
        if ($UseHttps) { $argLine += " -UseHttps" }
    }

    $action    = New-ScheduledTaskAction -Execute $psExe -Argument $argLine
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Host "Started SYSTEM task '$taskName'. Waiting for completion..."
    do { Start-Sleep 2 } while ((Get-ScheduledTask -TaskName $taskName).State -ne 'Ready')
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    if ($CleanupJobs) {
        $stale = Get-ScheduledTask -TaskName 'BITS_PolicyTest_*' -ErrorAction SilentlyContinue
        foreach ($t in $stale) {
            Write-Host " Removing stale task: $($t.TaskName)"
            Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false
        }
        Write-Host "Done. Cleanup performed."
    }
    else { Write-Host "Done. Output folder: $Destination" }
    return
}

# ====================== From here on we are NT AUTHORITY\SYSTEM ======================

if ($CleanupJobs) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Start-Transcript -Path (Join-Path $Destination 'bits.log') -Append | Out-Null
    Write-Host "Identity: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Host "Cleaning up 'CMPolicyTest_*' / 'CM Policy Test*' BITS jobs..."
    $jobs = Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'CMPolicyTest_*' -or $_.DisplayName -like 'CM Policy Test*' }
    if (-not $jobs) {
        Write-Host "No matching jobs."
    } else {
        foreach ($j in $jobs) {
            Write-Host (" Removing {0}  state={1}  owner={2}" -f $j.JobId, $j.JobState, $j.OwnerAccount)
            Remove-BitsTransfer -BitsJob $j -ErrorAction Continue
        }
        Write-Host ("Removed {0} job(s)." -f $jobs.Count)
    }
    Stop-Transcript | Out-Null
    return
}

Start-Transcript -Path (Join-Path $Destination 'bits.log') -Append | Out-Null
Write-Host "Identity: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Host "Mode    : $(if ($UseHttps) { 'HTTPS + client cert' } else { 'HTTP anonymous' })"
$jobStart = Get-Date
Write-Host "Started : $($jobStart.ToString('yyyy-MM-dd HH:mm:ss.fff'))"

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
    Write-Host "ClientCert: $($clientCert.Subject)"
    Write-Host "  Issuer  : $($clientCert.Issuer)"
    Write-Host "  Store   : $foundStore"
    Write-Host "  Thumb   : $($clientCert.Thumbprint)"
}

# Helper: run one BITS job for a set of pairs, return a stats object
function Invoke-OneBitsJob {
    param(
        [string]$Name,
        [object[]]$Pairs,
        [bool]$Https,
        [object]$Cert,
        [string]$CertStore
    )
    $bitsadmin = "$env:WINDIR\System32\bitsadmin.exe"
    foreach ($p in $Pairs) { if (Test-Path $p.LocalFile) { Remove-Item $p.LocalFile -Force } }

    Write-Host ""
    Write-Host "=============================================================="
    Write-Host "Job: $Name   Files: $($Pairs.Count)   Mode: $(if ($Https) {'HTTPS+cert'} else {'HTTP'})"
    Write-Host "=============================================================="
    $start = Get-Date

    $bytes = 0; $state = 'UNKNOWN'; $info = ''

    if (-not $Https) {
        $sources = @($Pairs | ForEach-Object { $_.Url })
        $dests   = @($Pairs | ForEach-Object { $_.LocalFile })
        $job = Start-BitsTransfer -Source $sources -Destination $dests -TransferType Download `
                -Priority Foreground -DisplayName $Name -Asynchronous
        while ($job.JobState -in 'Connecting','Transferring','Queued','TransientError') {
            Start-Sleep -Milliseconds 500
            $job = Get-BitsTransfer -JobId $job.JobId
        }
        $bytes = [int64]$job.BytesTransferred
        if ($job.JobState -eq 'Transferred') {
            Complete-BitsTransfer -BitsJob $job
            $state = 'TRANSFERRED'
        } else {
            Write-Host "FAILED: $($job.JobState) - $($job.ErrorDescription)"
            $state = $job.JobState.ToString().ToUpper()
            Remove-BitsTransfer -BitsJob $job
        }
    } else {
        Write-Host "--- bitsadmin /create ---"
        & $bitsadmin /create /download $Name | Out-Host
        foreach ($p in $Pairs) {
            & $bitsadmin /addfile $Name $p.Url $p.LocalFile | Out-Host
        }
        & $bitsadmin /setpriority $Name FOREGROUND | Out-Host
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

        Write-Host "Final state: $state"
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
    Write-Host "Batch  : $BatchFile  ($($workList.Count) BITS job(s), $(($workList.Pairs | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum) file(s) total)"
} else {
    $pairs = ,([pscustomobject]@{ Url = $PolicyUrl; LocalFile = (Join-Path $Destination (Resolve-FileNameFromUrl $PolicyUrl)) })
    $workList = @([pscustomobject]@{ JobName = $JobName; Pairs = $pairs })
    Write-Host "URL    : $PolicyUrl"
    Write-Host "Output : $($pairs[0].LocalFile)"
}

# Execute and collect stats
$results = foreach ($w in $workList) {
    Invoke-OneBitsJob -Name $w.JobName -Pairs $w.Pairs -Https:$UseHttps -Cert $clientCert -CertStore $physStoreName
}

$jobEnd  = Get-Date
$elapsed = $jobEnd - $jobStart

Write-Host ""
Write-Host "=============================================================="
Write-Host " SUMMARY"
Write-Host "=============================================================="
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
Write-Host ("Totals : {0}/{1} job(s) OK   {2} file(s)   {3:N0} bytes" -f `
    $okCount, $results.Count, ($results | Measure-Object Files -Sum).Sum, $totalBytes)
Write-Host ("Finished: {0}" -f $jobEnd.ToString('yyyy-MM-dd HH:mm:ss.fff'))
Write-Host ("Overall : {0:hh\:mm\:ss\.fff}  ({1:N3} s)" -f $elapsed, $elapsed.TotalSeconds)
Stop-Transcript | Out-Null
