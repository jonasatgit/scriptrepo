<#
.SYNOPSIS
    Script to fix an issue with the NCSI internet connectivity service by installing a scheduled task that runs on NCSI events.
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
    #************************************************************************************************************
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Export', 'Import')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [string]$ArchivePath,

    [string]$Version = '2.1.0',

    [switch]$AutoInstallDotNetSdk
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$archiveFullPath = [System.IO.Path]::GetFullPath($ArchivePath)
$workRoot = Join-Path ([System.IO.Path]::GetTempPath()) "MicrosoftBuildSqlOffline-$([guid]::NewGuid())"

function Test-DotNetSdk {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        return $false
    }

    $installedSdks = @(& dotnet --list-sdks 2>$null)
    return $LASTEXITCODE -eq 0 -and $installedSdks.Count -gt 0
}

function Install-LatestDotNetSdk {
    $releaseIndexUri = 'https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json'
    $installScriptUri = 'https://dot.net/v1/dotnet-install.ps1'
    $installScriptPath = Join-Path $workRoot 'dotnet-install.ps1'
    $installDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet'

    Write-Host 'Finding the latest supported stable .NET SDK...'
    $releaseIndex = Invoke-RestMethod -Uri $releaseIndexUri -UseBasicParsing

    $supportedChannels = @(
        $releaseIndex.'releases-index' |
            Where-Object {
                $_.'support-phase' -in @('active', 'maintenance') -and
                $_.'latest-sdk' -match '^\d+\.\d+\.\d+$'
            }
    )

    if ($supportedChannels.Count -eq 0) {
        throw "No supported stable .NET SDK was found in $releaseIndexUri."
    }

    $latestSdkVersion = $supportedChannels |
        Sort-Object { [version]$_.'latest-sdk' } -Descending |
        Select-Object -First 1 -ExpandProperty 'latest-sdk'

    Write-Host "Downloading the official .NET install script..."
    Invoke-WebRequest -Uri $installScriptUri -OutFile $installScriptPath -UseBasicParsing

    Write-Host "Installing .NET SDK $latestSdkVersion for the current user..."
    & powershell.exe `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $installScriptPath `
        -Version $latestSdkVersion `
        -InstallDir $installDirectory `
        -NoPath

    if ($LASTEXITCODE -ne 0) {
        throw "The .NET SDK installer failed with exit code $LASTEXITCODE."
    }

    $env:DOTNET_ROOT = $installDirectory
    $env:PATH = "$installDirectory;$env:PATH"

    if (-not (Test-DotNetSdk)) {
        throw "The .NET SDK installation completed, but no usable SDK was found in $installDirectory."
    }

    Write-Host ".NET SDK $latestSdkVersion was installed in $installDirectory."
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    Get-ChildItem -LiteralPath $Source -Recurse -File -Force | ForEach-Object {
        $relativePath = $_.FullName.Substring($Source.Length).TrimStart('\')
        $destinationFile = Join-Path $Destination $relativePath
        $destinationDirectory = Split-Path -Parent $destinationFile

        if (-not (Test-Path -LiteralPath $destinationDirectory)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }

        Copy-Item -LiteralPath $_.FullName -Destination $destinationFile -Force
    }
}

try {
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    if ($Mode -eq 'Export') {
        if (-not (Test-DotNetSdk)) {
            if (-not $AutoInstallDotNetSdk) {
                throw 'The .NET SDK was not found. Install one or rerun with -AutoInstallDotNetSdk.'
            }

            Install-LatestDotNetSdk
        }

        $archiveDirectory = Split-Path -Parent $archiveFullPath
        if (-not (Test-Path -LiteralPath $archiveDirectory)) {
            New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
        }

        $projectDirectory = Join-Path $workRoot 'project'
        $packageDirectory = Join-Path $workRoot 'packages'
        $projectPath = Join-Path $projectDirectory 'MicrosoftBuildSqlPackageSeed.csproj'

        New-Item -ItemType Directory -Path $projectDirectory -Force | Out-Null
        New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null

        @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Build.Sql" Version="$Version" />
  </ItemGroup>
</Project>
"@ | Set-Content -LiteralPath $projectPath -Encoding UTF8

        Write-Host "Downloading Microsoft.Build.Sql/$Version and its dependencies..."
        & dotnet restore $projectPath `
            --packages $packageDirectory `
            --source 'https://api.nuget.org/v3/index.json' `
            --force `
            --no-cache

        if ($LASTEXITCODE -ne 0) {
            throw "dotnet restore failed with exit code $LASTEXITCODE."
        }

        $sdkDirectory = Join-Path $packageDirectory "microsoft.build.sql\$Version"
        if (-not (Test-Path -LiteralPath $sdkDirectory)) {
            throw "Restore completed, but Microsoft.Build.Sql/$Version was not found in the package cache."
        }

        @{
            Package        = 'Microsoft.Build.Sql'
            Version        = $Version
            CreatedUtc     = [DateTime]::UtcNow.ToString('o')
            PackageCount   = @(Get-ChildItem -LiteralPath $packageDirectory -Directory).Count
            Source         = 'https://api.nuget.org/v3/index.json'
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $workRoot 'manifest.json') -Encoding UTF8

        if (Test-Path -LiteralPath $archiveFullPath) {
            Remove-Item -LiteralPath $archiveFullPath -Force
        }

        Compress-Archive `
            -Path (Join-Path $workRoot 'packages'), (Join-Path $workRoot 'manifest.json') `
            -DestinationPath $archiveFullPath `
            -CompressionLevel Optimal

        Write-Host ''
        Write-Host 'Offline package archive created successfully:'
        Write-Host "  $archiveFullPath"
        Write-Host ''
        Write-Host 'Copy the archive and this script to the offline machine.'
        Write-Host 'Run the Import mode while signed in as the account that runs SSMS:'
        Write-Host "  .\Prepare-MicrosoftBuildSqlOffline.ps1 -Mode Import -ArchivePath `"$archiveFullPath`""
    }
    else {
        if (-not (Test-Path -LiteralPath $archiveFullPath -PathType Leaf)) {
            throw "Archive not found: $archiveFullPath"
        }

        $extractDirectory = Join-Path $workRoot 'extracted'
        Expand-Archive -LiteralPath $archiveFullPath -DestinationPath $extractDirectory -Force

        $sourcePackages = Join-Path $extractDirectory 'packages'
        $manifestPath = Join-Path $extractDirectory 'manifest.json'

        if (-not (Test-Path -LiteralPath $sourcePackages -PathType Container)) {
            throw "The archive is invalid because it does not contain a packages directory."
        }

        if (Test-Path -LiteralPath $manifestPath) {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            if ($manifest.Package -ne 'Microsoft.Build.Sql') {
                throw "The archive manifest does not identify Microsoft.Build.Sql."
            }
            $Version = [string]$manifest.Version
        }

        $sourceSdk = Join-Path $sourcePackages "microsoft.build.sql\$Version"
        if (-not (Test-Path -LiteralPath $sourceSdk -PathType Container)) {
            throw "The archive does not contain Microsoft.Build.Sql/$Version."
        }

        $globalPackages = if ($env:NUGET_PACKAGES) {
            [System.IO.Path]::GetFullPath($env:NUGET_PACKAGES)
        }
        else {
            Join-Path $env:USERPROFILE '.nuget\packages'
        }

        New-Item -ItemType Directory -Path $globalPackages -Force | Out-Null

        Write-Host "Installing packages into $globalPackages ..."
        Copy-DirectoryContents -Source $sourcePackages -Destination $globalPackages

        $installedSdk = Join-Path $globalPackages "microsoft.build.sql\$Version"
        if (-not (Test-Path -LiteralPath $installedSdk -PathType Container)) {
            throw "Microsoft.Build.Sql/$Version was not installed successfully."
        }

        Write-Host ''
        Write-Host "Microsoft.Build.Sql/$Version and its dependencies were installed successfully."
        Write-Host 'Close and reopen SSMS, then create the SQL Database Project again.'
    }
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
