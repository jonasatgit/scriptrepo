<#

.SYNOPSIS
PSAppDeployToolkit - This script performs the installation or uninstallation of an application(s).

.DESCRIPTION
- The script is provided as a template to perform an install, uninstall, or repair of an application(s).
- The script either performs an "Install", "Uninstall", or "Repair" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

The script imports the PSAppDeployToolkit module which contains the logic and functions required to install or uninstall an application.

.PARAMETER DeploymentType
The type of deployment to perform.

.PARAMETER DeployMode
Specifies whether the installation should be run in Interactive (shows dialogs), Silent (no dialogs), NonInteractive (dialogs without prompts) mode, or Auto (shows dialogs if a user is logged on, device is not in the OOBE, and there's no running apps to close).

Silent mode is automatically set if it is detected that the process is not user interactive, no users are logged on, the device is in Autopilot mode, or there's specified processes to close that are currently running.

.PARAMETER SuppressRebootPassThru
Suppresses the 3010 return code (requires restart) from being passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode
Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging
Disables logging to file for the script.

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeployMode Silent

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent

.INPUTS
None. You cannot pipe objects to this script.

.OUTPUTS
None. This script does not generate any output.

.NOTES
Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Invoke-AppDeployToolkit.ps1, and Invoke-AppDeployToolkit.exe
- 69000 - 69999: Recommended for user customized exit codes in Invoke-AppDeployToolkit.ps1
- 70000 - 79999: Recommended for user customized exit codes in PSAppDeployToolkit.Extensions module.

.LINK
https://psappdeploytoolkit.com

#>

[CmdletBinding()]
param
(
    # Default is 'Install'.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType,

    # Default is 'Auto'. Don't hard-code this unless required.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)


##================================================
## MARK: Variables
##================================================

# Zero-Config MSI support is provided when "AppName" is null or empty.
# By setting the "AppName" property, Zero-Config MSI will be disabled.
$adtSession = @{
    # App variables.
    AppVendor = 'IT'
    AppName = 'ConfigMgr PerfCounterFix'
    AppVersion = '1.0.0'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @()  # Example: @('excel', @{ Name = 'winword'; Description = 'Microsoft Word' })
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-04-30'
    AppScriptAuthor = '<author name>'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = ''
    InstallTitle = ''

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

# Package-specific configuration. Centralizes file names and target paths so they
# only need to be maintained here. The {InstallDir} placeholder is replaced at
# runtime with the ConfigMgr "Installation Directory" read from the registry.
$packageConfig = @{
    SmsIdentificationKey = 'HKEY_LOCAL_MACHINE\Software\Microsoft\SMS\Identification'
    SmsIdentificationValue = 'Installation Directory'

    # Files to deploy. Each entry:
    #   SourceName      - file name inside the package's Files folder.
    #   DestinationPath - target path template; {InstallDir} is replaced at runtime.
    Files = @(
        @{
            SourceName      = 'File1.dll'
            DestinationPath = '{InstallDir}\bin\x64'
        }
        @{
            SourceName      = 'File2.dll'
            DestinationPath = '{InstallDir}\bin\x64\en-US'
        }
    )

    # Folders that should be removed on uninstall, but only if they are empty
    # after our files have been removed (other processes may add files there).
    FoldersToRemoveIfEmpty = @(
        '{InstallDir}\bin\x64\en-US'
    )
}

function Install-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    
    ## <Perform Pre-Installation tasks here>


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType


    ## <Perform Installation tasks here>

    ## Read ConfigMgr Installation Directory from registry.
    $smsInstallDir = Get-ADTRegistryKey -Key $packageConfig.SmsIdentificationKey -Name $packageConfig.SmsIdentificationValue
    if ([string]::IsNullOrWhiteSpace($smsInstallDir))
    {
        throw "Unable to read '$($packageConfig.SmsIdentificationValue)' value from [$($packageConfig.SmsIdentificationKey)]. Is ConfigMgr installed on this system?"
    }
    Write-ADTLogEntry -Message "ConfigMgr Installation Directory: [$smsInstallDir]"

    ## Process each file defined in $packageConfig.Files.
    foreach ($file in $packageConfig.Files)
    {
        $destinationFolder = $file.DestinationPath.Replace('{InstallDir}', $smsInstallDir)
        $sourceFile = Join-Path -Path $adtSession.DirFiles -ChildPath $file.SourceName

        ## Ensure destination folder exists.
        if (-not (Test-Path -LiteralPath $destinationFolder -PathType Container))
        {
            Write-ADTLogEntry -Message "Creating folder [$destinationFolder]."
            New-ADTFolder -Path $destinationFolder
        }

        ## Copy file to destination.
        Write-ADTLogEntry -Message "Copying [$sourceFile] to [$destinationFolder]."
        Copy-ADTFile -Path $sourceFile -Destination $destinationFolder
    }


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Installation tasks here>

}

function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"



    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType



    ## <Perform Uninstallation tasks here>

    ## Read ConfigMgr Installation Directory from registry. Tolerant: if the
    ## key/value is missing we just skip file removal instead of failing.
    $smsInstallDir = $null
    try
    {
        $smsInstallDir = Get-ADTRegistryKey -Key $packageConfig.SmsIdentificationKey -Name $packageConfig.SmsIdentificationValue
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to read registry [$($packageConfig.SmsIdentificationKey)\$($packageConfig.SmsIdentificationValue)]: $($_.Exception.Message)" -Severity 2
    }

    if ([string]::IsNullOrWhiteSpace($smsInstallDir))
    {
        Write-ADTLogEntry -Message "Unable to read '$($packageConfig.SmsIdentificationValue)' value from [$($packageConfig.SmsIdentificationKey)]. Skipping file removal." -Severity 2
    }
    else
    {
        Write-ADTLogEntry -Message "ConfigMgr Installation Directory: [$smsInstallDir]"

        ## Remove each file defined in $packageConfig.Files.
        foreach ($file in $packageConfig.Files)
        {
            $destinationFolder = $file.DestinationPath.Replace('{InstallDir}', $smsInstallDir)
            $targetFile = Join-Path -Path $destinationFolder -ChildPath $file.SourceName

            if (Test-Path -LiteralPath $targetFile -PathType Leaf)
            {
                Write-ADTLogEntry -Message "Removing [$targetFile]."
                Remove-ADTFile -LiteralPath $targetFile
            }
            else
            {
                Write-ADTLogEntry -Message "File [$targetFile] does not exist. Skipping."
            }
        }

        ## Remove folders only if they are empty after our file removals.
        foreach ($folderTemplate in $packageConfig.FoldersToRemoveIfEmpty)
        {
            $folderPath = $folderTemplate.Replace('{InstallDir}', $smsInstallDir)

            if (-not (Test-Path -LiteralPath $folderPath -PathType Container))
            {
                continue
            }

            [array]$remainingItems = @(Get-ChildItem -LiteralPath $folderPath -Force -ErrorAction SilentlyContinue)
            if ($remainingItems.Count -eq 0)
            {
                Write-ADTLogEntry -Message "Folder [$folderPath] is empty. Removing it."
                Remove-ADTFolder -Path $folderPath
            }
            else
            {
                Write-ADTLogEntry -Message "Folder [$folderPath] is not empty ($($remainingItems.Count) item(s) remaining). Keeping it." -Severity 2
            }
        }
    }


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Uninstallation tasks here>
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"



    ## <Perform Pre-Repair tasks here>


    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType



    ## <Perform Repair tasks here>


    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Repair tasks here>
}


##================================================
## MARK: Initialization
##================================================

# Set strict error handling across entire operation.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# Import the module and instantiate a new session.
try
{
    # Import the module locally if available, otherwise try to find it from PSModulePath.
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf)
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }

    # Open a new deployment session, replacing $adtSession with a DeploymentSession.
    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}


##================================================
## MARK: Invocation
##================================================

# Commence the actual deployment operation.
try
{
    # Import any found extensions before proceeding with the deployment.
    Get-ChildItem -LiteralPath $PSScriptRoot -Directory | & {
        process
        {
            if ($_.Name -match 'PSAppDeployToolkit\..+$')
            {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
                Import-Module -Name $_.FullName -Force
            }
        }
    }

    # Invoke the deployment and close out the session.
    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    # An unhandled error has been caught.
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3

    ## Error details hidden from the user by default. Show a simple dialog with full stack trace:
    # Show-ADTDialogBox -Text $mainErrorMessage -Icon Stop -NoWait

    ## Or, a themed dialog with basic error message:
    # Show-ADTInstallationPrompt -Message "$($adtSession.DeploymentType) failed at line $($_.InvocationInfo.ScriptLineNumber), char $($_.InvocationInfo.OffsetInLine):`n$($_.InvocationInfo.Line.Trim())`n`nMessage:`n$($_.Exception.Message)" -ButtonRightText OK -Icon Error -NoWait

    Close-ADTSession -ExitCode 60001
}

