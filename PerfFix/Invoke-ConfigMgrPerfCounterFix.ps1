<#
.SYNOPSIS
    Deploys (or removes) the loadperf.dll performance counter fix files into the
    ConfigMgr site server's bin\x64 directory.

.DESCRIPTION
    Intended to run on a ConfigMgr site server (not on the ConfigMgr client).
    Reads the site server's "Installation Directory" REG_SZ value from
    HKLM\Software\Microsoft\SMS\Identification and copies:
        Files\loadperf.dll        -> <InstallDir>\bin\x64\loadperf.dll
        Files\loadperf.dll.mui    -> <InstallDir>\bin\x64\en-US\loadperf.dll.mui

    On uninstall the two files are removed and the en-US folder is deleted only
    if it is empty after our file removal (other processes may have placed files
    there which must not be touched).

    Must be run elevated on the site server.

.PARAMETER Action
    Install (default) or Uninstall.

.EXAMPLE
    .\Invoke-ConfigMgrPerfCounterFix.ps1
    .\Invoke-ConfigMgrPerfCounterFix.ps1 -Action Uninstall

.NOTES
    Author : IT
    Version: 1.0.0
    Date   : 2026-04-30

    Exit codes:
        0   Success
        1   ConfigMgr Installation Directory could not be determined (install only)
        2   Source file missing in package (install only)
        3   Unexpected error
#>
[CmdletBinding()]
param
(
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action = 'Install'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration - change file names / destinations here only.
# {InstallDir} is replaced at runtime with the SMS Installation Directory.
# ---------------------------------------------------------------------------
$config = @{
    SmsRegistryKey   = 'HKLM:\Software\Microsoft\SMS\Identification'
    SmsRegistryValue = 'Installation Directory'

    Files = @(
        @{ SourceName = 'loadperf.dll';     DestinationPath = '{InstallDir}\bin\x64' }
        @{ SourceName = 'loadperf.dll.mui'; DestinationPath = '{InstallDir}\bin\x64\en-US' }
    )

    FoldersToRemoveIfEmpty = @(
        '{InstallDir}\bin\x64\en-US'
    )

    LogFile = Join-Path -Path $env:WinDir -ChildPath 'Temp\ConfigMgrPerfCounterFix.log'
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-LogEntry
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Severity = 'Info'
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Severity.ToUpper(), $Message

    try
    {
        $logDir = Split-Path -Path $config.LogFile -Parent
        if (-not (Test-Path -LiteralPath $logDir -PathType Container))
        {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        Add-Content -LiteralPath $config.LogFile -Value $line -ErrorAction SilentlyContinue
    }
    catch
    {
        # Logging must never break the script - swallow any I/O errors silently.
        $null = $_
    }

    switch ($Severity)
    {
        'Warning' { Write-Warning -Message $Message }
        'Error'   { Write-Error   -Message $Message -ErrorAction Continue }
        default   { Write-Verbose -Message $line }
    }
}

function Get-SmsInstallDirectory
{
    [CmdletBinding()]
    param ()

    if (-not (Test-Path -LiteralPath $config.SmsRegistryKey))
    {
        return $null
    }

    $prop = Get-ItemProperty -LiteralPath $config.SmsRegistryKey -Name $config.SmsRegistryValue -ErrorAction SilentlyContinue
    if ($null -eq $prop)
    {
        return $null
    }

    $value = $prop.$($config.SmsRegistryValue)
    if ([string]::IsNullOrWhiteSpace($value))
    {
        return $null
    }

    return $value.TrimEnd('\')
}

function Resolve-DestinationPath
{
    param
    (
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][string]$InstallDir
    )
    return $Template.Replace('{InstallDir}', $InstallDir)
}

function Invoke-Install
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)][string]$InstallDir,
        [Parameter(Mandatory)][string]$SourceRoot
    )

    foreach ($file in $config.Files)
    {
        $sourceFile = Join-Path -Path $SourceRoot -ChildPath $file.SourceName
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf))
        {
            Write-LogEntry -Message "Source file not found: [$sourceFile]." -Severity Error
            exit 2
        }

        $destFolder = Resolve-DestinationPath -Template $file.DestinationPath -InstallDir $InstallDir
        if (-not (Test-Path -LiteralPath $destFolder -PathType Container))
        {
            Write-LogEntry -Message "Creating folder [$destFolder]."
            New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
        }

        $destFile = Join-Path -Path $destFolder -ChildPath $file.SourceName
        Write-LogEntry -Message "Copying [$sourceFile] -> [$destFile]."
        Copy-Item -LiteralPath $sourceFile -Destination $destFile -Force
    }
}

function Invoke-Uninstall
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)][string]$InstallDir
    )

    foreach ($file in $config.Files)
    {
        $destFolder = Resolve-DestinationPath -Template $file.DestinationPath -InstallDir $InstallDir
        $targetFile = Join-Path -Path $destFolder -ChildPath $file.SourceName

        if (Test-Path -LiteralPath $targetFile -PathType Leaf)
        {
            Write-LogEntry -Message "Removing [$targetFile]."
            Remove-Item -LiteralPath $targetFile -Force
        }
        else
        {
            Write-LogEntry -Message "File [$targetFile] does not exist. Skipping."
        }
    }

    foreach ($template in $config.FoldersToRemoveIfEmpty)
    {
        $folderPath = Resolve-DestinationPath -Template $template -InstallDir $InstallDir
        if (-not (Test-Path -LiteralPath $folderPath -PathType Container))
        {
            continue
        }

        [array]$remaining = @(Get-ChildItem -LiteralPath $folderPath -Force -ErrorAction SilentlyContinue)
        if ($remaining.Count -eq 0)
        {
            Write-LogEntry -Message "Folder [$folderPath] is empty. Removing it."
            Remove-Item -LiteralPath $folderPath -Force
        }
        else
        {
            Write-LogEntry -Message "Folder [$folderPath] is not empty ($($remaining.Count) item(s) remaining). Keeping it." -Severity Warning
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try
{
    Write-LogEntry -Message "===== Action: $Action ====="

    $installDir = Get-SmsInstallDirectory
    if ([string]::IsNullOrWhiteSpace($installDir))
    {
        $msg = "Unable to read '$($config.SmsRegistryValue)' from [$($config.SmsRegistryKey)]. Is this a ConfigMgr site server?"
        if ($Action -eq 'Install')
        {
            Write-LogEntry -Message $msg -Severity Error
            exit 1
        }
        else
        {
            Write-LogEntry -Message "$msg Skipping uninstall." -Severity Warning
            exit 0
        }
    }

    Write-LogEntry -Message "ConfigMgr Installation Directory: [$installDir]"

    # Source files for install must sit in a "Files" subfolder next to this script
    # (matching the typical ConfigMgr application package layout). If that folder
    # doesn't exist, fall back to the script directory.
    $sourceRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Files'
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container))
    {
        $sourceRoot = $PSScriptRoot
    }

    switch ($Action)
    {
        'Install'   { Invoke-Install   -InstallDir $installDir -SourceRoot $sourceRoot }
        'Uninstall' { Invoke-Uninstall -InstallDir $installDir }
    }

    Write-LogEntry -Message "$Action completed successfully."
    exit 0
}
catch
{
    Write-LogEntry -Message "Unhandled error: $($_.Exception.Message)" -Severity Error
    Write-LogEntry -Message $_.ScriptStackTrace -Severity Error
    exit 3
}
