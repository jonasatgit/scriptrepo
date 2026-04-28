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
#
# Source: https://github.com/jonasatgit/scriptrepo

<#
.SYNOPSIS
    Reads boot performance data (Event ID 100) from the
    Microsoft-Windows-Diagnostics-Performance/Operational event log and stores
    each event as one instance in a custom WMI class.

.DESCRIPTION
    For every Event ID 100 found in the
    "Microsoft-Windows-Diagnostics-Performance/Operational" log a new instance
    is created in a custom WMI class (default: Custom_BootPerformance in
    root\cimv2). The script also captures the currently active network adapter
    (the one used by the default IPv4 route) including IP address and subnet
    mask. That information is written onto every row so the boot performance
    data can later be correlated with the network location the device is
    currently in.

    The custom WMI class is created on first run. Existing instances are
    removed and rewritten on every run so the class always reflects the
    current state of the event log.

    The script can be deployed via a ConfigMgr Configuration Item / Baseline
    or a Scheduled Task. The custom WMI class can then be inventoried via
    ConfigMgr hardware inventory.

    Note: The network information represents the *current* state at script
    run time, not the network state at boot time. Historic per-boot network
    information is not available in the event log.

.PARAMETER WMIRootPath
    The WMI namespace where the custom class will be created.
    Default: root\cimv2

.PARAMETER WMIClassName
    The name of the custom WMI class.
    Default: Custom_BootPerformance

.PARAMETER MaxEvents
    Cap on how many of the most recent Event ID 100 entries are read from the
    event log per run. Default is 1 (only the latest boot event). Use 0 to
    read all events found in the log.

.PARAMETER MaxWmiEntries
    Maximum number of instances to keep in the custom WMI class. New events
    are appended (without duplicating existing RecordIds) and the oldest
    instances (by TimeCreated) are removed until the class contains at most
    this many rows. Default is 10. Use 0 to disable trimming.

.EXAMPLE
    .\Get-LocalBootPerfData.ps1

.EXAMPLE
    .\Get-LocalBootPerfData.ps1 -WMIClassName 'Custom_BootPerformance' -MaxEvents 0 -MaxWmiEntries 100

.EXAMPLE
    .\Get-LocalBootPerfData.ps1 -RemoveClass

.LINK
    https://github.com/jonasatgit/scriptrepo
#>
[CmdletBinding()]
param
(
    [string]$WMIRootPath = 'root\cimv2',
    [string]$WMIClassName = 'Custom_BootPerformance',
    [int]$MaxEvents = 1,
    [int]$MaxWmiEntries = 1,
    [switch]$RemoveClass
)


#region New-CustomWmiClass
<#
.SYNOPSIS
    Creates the custom WMI class used to store boot performance data.
.DESCRIPTION
    Creates a new custom WMI class with all properties needed to store one
    Event ID 100 entry from the
    Microsoft-Windows-Diagnostics-Performance/Operational log together with
    the current active network adapter information.
.EXAMPLE
    New-CustomWmiClass -ClassName 'Custom_BootPerformance'
.EXAMPLE
    New-CustomWmiClass -RootPath 'root\cimv2' -ClassName 'Custom_BootPerformance'
#>
function New-CustomWmiClass
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$false,HelpMessage = "Root namespace to store custom class in. If not set root\cimv2 will be used.")]
        [string]$RootPath = 'root\cimv2',

        [Parameter(Mandatory=$true,HelpMessage = "Name of custom WMI class.")]
        [string]$ClassName
    )

    $newWMIClass = New-Object System.Management.ManagementClass($RootPath, [String]::Empty, $null)

    $newWMIClass["__CLASS"] = $ClassName
    # cim types: https://msdn.microsoft.com/en-us/library/system.management.cimtype(v=vs.110).aspx
    $newWMIClass.Qualifiers.Add("Static", $true)

    # Key / meta
    $newWMIClass.Properties.Add("KeyName", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["KeyName"].Qualifiers.Add("key", $true)
    $newWMIClass.Properties["KeyName"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["KeyName"].Qualifiers.Add("Description", "Composite key: <RecordId>_<TimeCreatedDmtf>")

    $newWMIClass.Properties.Add("RecordId", [System.Management.CimType]::UInt64, $false)
    $newWMIClass.Properties["RecordId"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["RecordId"].Qualifiers.Add("Description", "RecordId of the source event")

    $newWMIClass.Properties.Add("TimeCreated", [System.Management.CimType]::DateTime, $false)
    $newWMIClass.Properties["TimeCreated"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["TimeCreated"].Qualifiers.Add("Description", "Time the event was written to the event log")

    $newWMIClass.Properties.Add("CollectionTime", [System.Management.CimType]::DateTime, $false)
    $newWMIClass.Properties["CollectionTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["CollectionTime"].Qualifiers.Add("Description", "Time this WMI instance was created/updated by the script")

    # Boot timings (milliseconds) and times
    $newWMIClass.Properties.Add("BootStartTime", [System.Management.CimType]::DateTime, $false)
    $newWMIClass.Properties["BootStartTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootStartTime"].Qualifiers.Add("Description", "BootStartTime: time the boot started (firmware/OS loader hand-off), UTC FILETIME")

    $newWMIClass.Properties.Add("BootEndTime", [System.Management.CimType]::DateTime, $false)
    $newWMIClass.Properties["BootEndTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootEndTime"].Qualifiers.Add("Description", "BootEndTime: time boot was considered complete (PostBoot ended, system idle), UTC FILETIME")

    $newWMIClass.Properties.Add("BootTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootTime"].Qualifiers.Add("Description", "BootTime (ms): total boot time = MainPathBootTime + BootPostBootTime; end-user perceived time from power-on to idle desktop")

    $newWMIClass.Properties.Add("MainPathBootTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["MainPathBootTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["MainPathBootTime"].Qualifiers.Add("Description", "MainPathBootTime (ms): visible boot path from OS loader through to desktop being shown to the user")

    $newWMIClass.Properties.Add("BootKernelInitTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootKernelInitTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootKernelInitTime"].Qualifiers.Add("Description", "BootKernelInitTime (ms): early kernel initialization (executive, HAL, memory manager) before driver init")

    $newWMIClass.Properties.Add("BootDriverInitTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootDriverInitTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootDriverInitTime"].Qualifiers.Add("Description", "BootDriverInitTime (ms): time spent initializing boot/start drivers during kernel init")

    $newWMIClass.Properties.Add("BootPostBootTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootPostBootTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootPostBootTime"].Qualifiers.Add("Description", "BootPostBootTime (ms): time after the desktop is shown until the system is considered idle; high values usually indicate heavy startup apps")

    $newWMIClass.Properties.Add("BootImprovementDelta", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootImprovementDelta"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootImprovementDelta"].Qualifiers.Add("Description", "BootImprovementDelta (ms): magnitude of improvement vs. baseline when this boot is faster than expected")

    $newWMIClass.Properties.Add("BootDegradationDelta", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootDegradationDelta"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootDegradationDelta"].Qualifiers.Add("Description", "BootDegradationDelta (ms): magnitude of regression vs. baseline when this boot is slower than expected")

    $newWMIClass.Properties.Add("BootIsDegradation", [System.Management.CimType]::Boolean, $false)
    $newWMIClass.Properties["BootIsDegradation"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootIsDegradation"].Qualifiers.Add("Description", "BootIsDegradation: true if this boot is classified as a degradation vs. the device baseline")

    $newWMIClass.Properties.Add("BootIsStepDegradation", [System.Management.CimType]::Boolean, $false)
    $newWMIClass.Properties["BootIsStepDegradation"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootIsStepDegradation"].Qualifiers.Add("Description", "BootIsStepDegradation: true if degradation is a sudden step change (e.g. after install)")

    $newWMIClass.Properties.Add("BootIsGradualDegradation", [System.Management.CimType]::Boolean, $false)
    $newWMIClass.Properties["BootIsGradualDegradation"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootIsGradualDegradation"].Qualifiers.Add("Description", "BootIsGradualDegradation: true if degradation is a gradual trend over multiple boots")

    $newWMIClass.Properties.Add("BootIsRootCauseIdentified", [System.Management.CimType]::Boolean, $false)
    $newWMIClass.Properties["BootIsRootCauseIdentified"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootIsRootCauseIdentified"].Qualifiers.Add("Description", "BootIsRootCauseIdentified: true if diagnostics attributed the deviation to specific component(s); see *Bits fields")

    $newWMIClass.Properties.Add("BootIsRebootAfterInstall", [System.Management.CimType]::Boolean, $false)
    $newWMIClass.Properties["BootIsRebootAfterInstall"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootIsRebootAfterInstall"].Qualifiers.Add("Description", "BootIsRebootAfterInstall: true if boot followed a Windows Update / driver install requiring post-install work (causes longer boot)")

    $newWMIClass.Properties.Add("BootRootCauseStepImprovementBits", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootRootCauseStepImprovementBits"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootRootCauseStepImprovementBits"].Qualifiers.Add("Description", "BootRootCauseStepImprovementBits: opaque bitmask identifying components that caused a sudden (step) boot-time improvement")

    $newWMIClass.Properties.Add("BootRootCauseGradualImprovementBits", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootRootCauseGradualImprovementBits"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootRootCauseGradualImprovementBits"].Qualifiers.Add("Description", "BootRootCauseGradualImprovementBits: opaque bitmask of components contributing to a gradual boot-time improvement trend")

    $newWMIClass.Properties.Add("BootRootCauseStepDegradationBits", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootRootCauseStepDegradationBits"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootRootCauseStepDegradationBits"].Qualifiers.Add("Description", "BootRootCauseStepDegradationBits: opaque bitmask identifying components that caused a sudden (step) boot-time regression")

    $newWMIClass.Properties.Add("BootRootCauseGradualDegradationBits", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootRootCauseGradualDegradationBits"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootRootCauseGradualDegradationBits"].Qualifiers.Add("Description", "BootRootCauseGradualDegradationBits: opaque bitmask of components contributing to a gradual boot-time regression trend")

    # Detailed boot timings and counters (Event 100 extended fields)
    $newWMIClass.Properties.Add("BootTsVersion", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootTsVersion"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootTsVersion"].Qualifiers.Add("Description", "BootTsVersion: schema/telemetry version of the boot timing record; indicates which set of fields is present")

    $newWMIClass.Properties.Add("SystemBootInstance", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["SystemBootInstance"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["SystemBootInstance"].Qualifiers.Add("Description", "SystemBootInstance: monotonic counter of system boots since the OS was installed")

    $newWMIClass.Properties.Add("UserBootInstance", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["UserBootInstance"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["UserBootInstance"].Qualifiers.Add("Description", "UserBootInstance: monotonic counter of interactive (user-facing) boots; differs from SystemBootInstance when no user signs in")

    $newWMIClass.Properties.Add("BootDevicesInitTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootDevicesInitTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootDevicesInitTime"].Qualifiers.Add("Description", "BootDevicesInitTime (ms): time spent enumerating and initializing PnP devices during boot")

    $newWMIClass.Properties.Add("BootPrefetchInitTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootPrefetchInitTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootPrefetchInitTime"].Qualifiers.Add("Description", "BootPrefetchInitTime (ms): time spent processing the boot prefetcher (reading prefetch trace files)")

    $newWMIClass.Properties.Add("BootPrefetchBytes", [System.Management.CimType]::UInt64, $false)
    $newWMIClass.Properties["BootPrefetchBytes"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootPrefetchBytes"].Qualifiers.Add("Description", "BootPrefetchBytes: number of bytes read by the boot prefetcher")

    $newWMIClass.Properties.Add("BootAutoChkTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootAutoChkTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootAutoChkTime"].Qualifiers.Add("Description", "BootAutoChkTime (ms): time spent running autochk/chkdsk during boot (usually 0)")

    $newWMIClass.Properties.Add("BootSmssInitTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootSmssInitTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootSmssInitTime"].Qualifiers.Add("Description", "BootSmssInitTime (ms): time spent in the Session Manager (smss.exe) phase")

    $newWMIClass.Properties.Add("BootCriticalServicesInitTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootCriticalServicesInitTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootCriticalServicesInitTime"].Qualifiers.Add("Description", "BootCriticalServicesInitTime (ms): time to start critical/auto-start services that block the boot path")

    $newWMIClass.Properties.Add("BootUserProfileProcessingTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootUserProfileProcessingTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootUserProfileProcessingTime"].Qualifiers.Add("Description", "BootUserProfileProcessingTime (ms): time to load/apply the user profile (registry hive load, GP, etc.) during sign-in")

    $newWMIClass.Properties.Add("BootMachineProfileProcessingTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootMachineProfileProcessingTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootMachineProfileProcessingTime"].Qualifiers.Add("Description", "BootMachineProfileProcessingTime (ms): time to apply machine policy / machine profile components during boot")

    $newWMIClass.Properties.Add("BootExplorerInitTime", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootExplorerInitTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootExplorerInitTime"].Qualifiers.Add("Description", "BootExplorerInitTime (ms): from explorer.exe start until the shell is ready (desktop visible / responsive)")

    $newWMIClass.Properties.Add("BootNumStartupApps", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootNumStartupApps"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootNumStartupApps"].Qualifiers.Add("Description", "BootNumStartupApps: count of startup apps launched (Run keys, Startup folder, AtLogon scheduled tasks, etc.)")

    $newWMIClass.Properties.Add("OSLoaderDuration", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["OSLoaderDuration"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["OSLoaderDuration"].Qualifiers.Add("Description", "OSLoaderDuration (ms): duration in the Windows Boot Loader phase (winload.exe) before kernel init")

    $newWMIClass.Properties.Add("BootPNPInitStartTimeMS", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootPNPInitStartTimeMS"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootPNPInitStartTimeMS"].Qualifiers.Add("Description", "BootPNPInitStartTimeMS (ms): offset from boot start at which boot-time PnP initialization began")

    $newWMIClass.Properties.Add("BootPNPInitDuration", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["BootPNPInitDuration"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BootPNPInitDuration"].Qualifiers.Add("Description", "BootPNPInitDuration (ms): duration of the boot-phase PnP initialization")

    $newWMIClass.Properties.Add("OtherKernelInitDuration", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["OtherKernelInitDuration"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["OtherKernelInitDuration"].Qualifiers.Add("Description", "OtherKernelInitDuration (ms): remainder of kernel-init time not accounted for by the explicit kernel sub-phases")

    $newWMIClass.Properties.Add("SystemPNPInitStartTimeMS", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["SystemPNPInitStartTimeMS"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["SystemPNPInitStartTimeMS"].Qualifiers.Add("Description", "SystemPNPInitStartTimeMS (ms): offset at which the system-phase PnP init started (post kernel-init)")

    $newWMIClass.Properties.Add("SystemPNPInitDuration", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["SystemPNPInitDuration"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["SystemPNPInitDuration"].Qualifiers.Add("Description", "SystemPNPInitDuration (ms): duration of the system-phase PnP init")

    $newWMIClass.Properties.Add("SessionInitStartTimeMS", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["SessionInitStartTimeMS"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["SessionInitStartTimeMS"].Qualifiers.Add("Description", "SessionInitStartTimeMS (ms): offset at which session initialization (smss creating sessions) started")

    $newWMIClass.Properties.Add("Session0InitDuration", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["Session0InitDuration"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["Session0InitDuration"].Qualifiers.Add("Description", "Session0InitDuration (ms): time spent initializing Session 0 (services session)")

    $newWMIClass.Properties.Add("Session1InitDuration", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["Session1InitDuration"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["Session1InitDuration"].Qualifiers.Add("Description", "Session1InitDuration (ms): time spent initializing Session 1 (first interactive session)")

    $newWMIClass.Properties.Add("SessionInitOtherDuration", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["SessionInitOtherDuration"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["SessionInitOtherDuration"].Qualifiers.Add("Description", "SessionInitOtherDuration (ms): session-init activity not attributed to Session 0 / Session 1")

    $newWMIClass.Properties.Add("WinLogonStartTimeMS", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["WinLogonStartTimeMS"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["WinLogonStartTimeMS"].Qualifiers.Add("Description", "WinLogonStartTimeMS (ms): offset at which winlogon.exe started")

    $newWMIClass.Properties.Add("OtherLogonInitActivityDuration", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["OtherLogonInitActivityDuration"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["OtherLogonInitActivityDuration"].Qualifiers.Add("Description", "OtherLogonInitActivityDuration (ms): logon-init work other than the user-credential wait (services, GP processing, etc.)")

    $newWMIClass.Properties.Add("UserLogonWaitDuration", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["UserLogonWaitDuration"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["UserLogonWaitDuration"].Qualifiers.Add("Description", "UserLogonWaitDuration (ms): time waiting for the user to complete credential entry; depends on user behavior, often filtered out for hardware/OS comparisons")

    # Network snapshot (current state at script run time)
    $newWMIClass.Properties.Add("NetAdapterName", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["NetAdapterName"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["NetAdapterName"].Qualifiers.Add("Description", "Name of the currently active network adapter (default IPv4 route)")

    $newWMIClass.Properties.Add("NetAdapterDescription", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["NetAdapterDescription"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["NetAdapterDescription"].Qualifiers.Add("Description", "Description of the currently active network adapter")

    $newWMIClass.Properties.Add("NetAdapterMacAddress", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["NetAdapterMacAddress"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["NetAdapterMacAddress"].Qualifiers.Add("Description", "MAC address of the currently active network adapter")

    $newWMIClass.Properties.Add("IPAddress", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["IPAddress"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["IPAddress"].Qualifiers.Add("Description", "IPv4 address of the currently active network adapter")

    $newWMIClass.Properties.Add("SubnetMask", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["SubnetMask"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["SubnetMask"].Qualifiers.Add("Description", "Dotted IPv4 subnet mask of the currently active network adapter")

    $newWMIClass.Properties.Add("PrefixLength", [System.Management.CimType]::UInt8, $false)
    $newWMIClass.Properties["PrefixLength"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["PrefixLength"].Qualifiers.Add("Description", "IPv4 prefix length of the currently active network adapter")

    $newWMIClass.Properties.Add("DefaultGateway", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["DefaultGateway"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["DefaultGateway"].Qualifiers.Add("Description", "Default IPv4 gateway of the currently active network adapter")

    $newWMIClass.Properties.Add("ConnectionProfileName", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["ConnectionProfileName"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["ConnectionProfileName"].Qualifiers.Add("Description", "Network connection profile name (e.g. SSID or domain network name)")

    $newWMIClass.Properties.Add("NetworkStatus", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["NetworkStatus"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["NetworkStatus"].Qualifiers.Add("Description", "Network detection state at script run time: Connected (default route + adapter resolved), NotConnected (no default IPv4 route), Error (network cmdlets failed)")

    $newWMIClass.Properties.Add("LinkSpeed", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["LinkSpeed"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["LinkSpeed"].Qualifiers.Add("Description", "Human readable negotiated link speed of the active network adapter (e.g. '1 Gbps')")

    [void]$newWMIClass.Put()

    return (Get-WmiObject -Namespace $RootPath -Class $ClassName -List)
}
#endregion


#region Get-ActiveNetworkInfo
<#
.SYNOPSIS
    Returns information about the currently active network adapter.
.DESCRIPTION
    Determines the network adapter that owns the lowest-metric default IPv4
    route and returns adapter name, description, MAC, IPv4 address, prefix
    length, dotted subnet mask, default gateway and connection profile name.
    Returns empty strings for all values if no default route is present.
#>
function Get-ActiveNetworkInfo
{
    [CmdletBinding()]
    param()

    $result = [ordered]@{
        NetAdapterName        = ''
        NetAdapterDescription = ''
        NetAdapterMacAddress  = ''
        IPAddress             = ''
        SubnetMask            = ''
        PrefixLength          = [byte]0
        DefaultGateway        = ''
        ConnectionProfileName = ''
        NetworkStatus         = 'NotConnected'
        LinkSpeed             = ''
    }

    try
    {
        $defaultRoute = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
                            Sort-Object -Property RouteMetric, ifMetric |
                            Select-Object -First 1

        if (-not $defaultRoute)
        {
            return $result
        }

        $result.NetworkStatus = 'Connected'

        $ifIndex = $defaultRoute.ifIndex
        $adapter = Get-NetAdapter -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue
        $ipCfg   = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                        Where-Object { $_.PrefixOrigin -ne 'WellKnown' } |
                        Select-Object -First 1
        $profile = Get-NetConnectionProfile -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue |
                        Select-Object -First 1

        if ($adapter)
        {
            $result.NetAdapterName        = [string]$adapter.Name
            $result.NetAdapterDescription = [string]$adapter.InterfaceDescription
            $result.NetAdapterMacAddress  = [string]$adapter.MacAddress
            $result.LinkSpeed             = [string]$adapter.LinkSpeed
        }

        if ($ipCfg)
        {
            $prefix = [byte]$ipCfg.PrefixLength
            $result.IPAddress    = [string]$ipCfg.IPAddress
            $result.PrefixLength = $prefix

            # Convert prefix length to dotted IPv4 subnet mask
            if ($prefix -gt 0 -and $prefix -le 32)
            {
                $maskUInt32 = [uint32]([math]::Pow(2,32) - [math]::Pow(2, 32 - $prefix))
                $bytes = [BitConverter]::GetBytes($maskUInt32)
                if ([BitConverter]::IsLittleEndian) { [array]::Reverse($bytes) }
                $result.SubnetMask = ($bytes | ForEach-Object { $_.ToString() }) -join '.'
            }
        }

        $result.DefaultGateway = [string]$defaultRoute.NextHop

        if ($profile)
        {
            $result.ConnectionProfileName = [string]$profile.Name
        }
    }
    catch
    {
        Write-Verbose "Get-ActiveNetworkInfo failed: $($_.Exception.Message)"
        $result.NetworkStatus = 'Error'
    }

    return $result
}
#endregion


#region Get-BootPerfEvents
<#
.SYNOPSIS
    Returns parsed Event ID 100 entries from the boot diagnostics log.
.DESCRIPTION
    Reads Event ID 100 from
    Microsoft-Windows-Diagnostics-Performance/Operational and returns one
    PSCustomObject per event with the relevant fields parsed out.
#>
function Get-BootPerfEvents
{
    [CmdletBinding()]
    param
    (
        [int]$MaxEvents = 0
    )

    $params = @{
        LogName     = 'Microsoft-Windows-Diagnostics-Performance/Operational'
        FilterXPath = '*[System[(EventID=100)]]'
        ErrorAction = 'Stop'
    }
    if ($MaxEvents -gt 0)
    {
        $params['MaxEvents'] = $MaxEvents
    }

    try
    {
        $events = Get-WinEvent @params
    }
    catch [System.Exception]
    {
        # No events found is reported as a non-terminating error in PS5 / terminating in PS7
        if ($_.Exception.Message -match 'No events were found')
        {
            return @()
        }
        Write-Verbose "Get-WinEvent failed: $($_.Exception.Message)"
        return @()
    }

    foreach ($evt in $events)
    {
        $xml = [xml]$evt.ToXml()
        $data = @{}
        foreach ($d in $xml.Event.EventData.Data)
        {
            $data[$d.Name] = $d.'#text'
        }

        # Helpers to safely cast strings -> numeric / bool
        $toUInt32 = {
            param($v)
            $u = [uint32]0
            if ([uint32]::TryParse(("$v"), [ref]$u)) { return $u } else { return [uint32]0 }
        }
        $toUInt64 = {
            param($v)
            $u = [uint64]0
            if ([uint64]::TryParse(("$v"), [ref]$u)) { return $u } else { return [uint64]0 }
        }
        $toBool = {
            param($v)
            if ("$v" -in @('1','true','True')) { return $true } else { return $false }
        }
        $toDate = {
            param($v)
            $dt = [datetime]::MinValue
            if ([datetime]::TryParse(("$v"), [ref]$dt)) { return $dt } else { return $null }
        }

        [pscustomobject]@{
            RecordId                            = [uint64]$evt.RecordId
            TimeCreated                         = [datetime]$evt.TimeCreated
            BootStartTime                       = & $toDate   $data['BootStartTime']
            BootEndTime                         = & $toDate   $data['BootEndTime']
            BootTime                            = & $toUInt32 $data['BootTime']
            MainPathBootTime                    = & $toUInt32 $data['MainPathBootTime']
            BootKernelInitTime                  = & $toUInt32 $data['BootKernelInitTime']
            BootDriverInitTime                  = & $toUInt32 $data['BootDriverInitTime']
            BootPostBootTime                    = & $toUInt32 $data['BootPostBootTime']
            BootImprovementDelta                = & $toUInt32 $data['BootImprovementDelta']
            BootDegradationDelta                = & $toUInt32 $data['BootDegradationDelta']
            BootIsDegradation                   = & $toBool   $data['BootIsDegradation']
            BootIsStepDegradation               = & $toBool   $data['BootIsStepDegradation']
            BootIsGradualDegradation            = & $toBool   $data['BootIsGradualDegradation']
            BootIsRootCauseIdentified           = & $toBool   $data['BootIsRootCauseIdentified']
            BootIsRebootAfterInstall            = & $toBool   $data['BootIsRebootAfterInstall']
            BootRootCauseStepImprovementBits    = & $toUInt32 $data['BootRootCauseStepImprovementBits']
            BootRootCauseGradualImprovementBits = & $toUInt32 $data['BootRootCauseGradualImprovementBits']
            BootRootCauseStepDegradationBits    = & $toUInt32 $data['BootRootCauseStepDegradationBits']
            BootRootCauseGradualDegradationBits = & $toUInt32 $data['BootRootCauseGradualDegradationBits']
            BootTsVersion                       = & $toUInt32 $data['BootTsVersion']
            SystemBootInstance                  = & $toUInt32 $data['SystemBootInstance']
            UserBootInstance                    = & $toUInt32 $data['UserBootInstance']
            BootDevicesInitTime                 = & $toUInt32 $data['BootDevicesInitTime']
            BootPrefetchInitTime                = & $toUInt32 $data['BootPrefetchInitTime']
            BootPrefetchBytes                   = & $toUInt64 $data['BootPrefetchBytes']
            BootAutoChkTime                     = & $toUInt32 $data['BootAutoChkTime']
            BootSmssInitTime                    = & $toUInt32 $data['BootSmssInitTime']
            BootCriticalServicesInitTime        = & $toUInt32 $data['BootCriticalServicesInitTime']
            BootUserProfileProcessingTime       = & $toUInt32 $data['BootUserProfileProcessingTime']
            BootMachineProfileProcessingTime    = & $toUInt32 $data['BootMachineProfileProcessingTime']
            BootExplorerInitTime                = & $toUInt32 $data['BootExplorerInitTime']
            BootNumStartupApps                  = & $toUInt32 $data['BootNumStartupApps']
            OSLoaderDuration                    = & $toUInt32 $data['OSLoaderDuration']
            BootPNPInitStartTimeMS              = & $toUInt32 $data['BootPNPInitStartTimeMS']
            BootPNPInitDuration                 = & $toUInt32 $data['BootPNPInitDuration']
            OtherKernelInitDuration             = & $toUInt32 $data['OtherKernelInitDuration']
            SystemPNPInitStartTimeMS            = & $toUInt32 $data['SystemPNPInitStartTimeMS']
            SystemPNPInitDuration               = & $toUInt32 $data['SystemPNPInitDuration']
            SessionInitStartTimeMS              = & $toUInt32 $data['SessionInitStartTimeMS']
            Session0InitDuration                = & $toUInt32 $data['Session0InitDuration']
            Session1InitDuration                = & $toUInt32 $data['Session1InitDuration']
            SessionInitOtherDuration            = & $toUInt32 $data['SessionInitOtherDuration']
            WinLogonStartTimeMS                 = & $toUInt32 $data['WinLogonStartTimeMS']
            OtherLogonInitActivityDuration      = & $toUInt32 $data['OtherLogonInitActivityDuration']
            UserLogonWaitDuration               = & $toUInt32 $data['UserLogonWaitDuration']
        }
    }
}
#endregion


# Optional: remove the whole class and exit
if ($RemoveClass)
{
    $existing = Get-WmiObject -Namespace $WMIRootPath -Class $WMIClassName -List -ErrorAction SilentlyContinue
    if ($existing)
    {
        # Remove all instances first, then the class itself
        Get-WmiObject -Namespace $WMIRootPath -Class $WMIClassName -ErrorAction SilentlyContinue | Remove-WmiObject
        $existing | Remove-WmiObject
        Write-Verbose "Removed WMI class $WMIRootPath\:$WMIClassName"
    }
    else
    {
        Write-Verbose "WMI class $WMIRootPath\:$WMIClassName does not exist"
    }
    return
}

# Ensure the custom class exists
if (-not (Get-WmiObject -Namespace $WMIRootPath -Class $WMIClassName -List -ErrorAction SilentlyContinue))
{
    New-CustomWmiClass -RootPath $WMIRootPath -ClassName $WMIClassName | Out-Null
}

# Existing instances - we keep them and only append new ones (deduped by RecordId)
$existingInstances = @(Get-WmiObject -Namespace $WMIRootPath -Class $WMIClassName -ErrorAction SilentlyContinue)
$existingRecordIds = @{}
foreach ($i in $existingInstances)
{
    if ($i.RecordId) { $existingRecordIds[[string]$i.RecordId] = $true }
}

# Gather data
$net           = Get-ActiveNetworkInfo
$bootEvents    = @(Get-BootPerfEvents -MaxEvents $MaxEvents)
$collectionDmtf = [Management.ManagementDateTimeConverter]::ToDmtfDateTime((Get-Date))

if ($bootEvents.Count -eq 0)
{
    if ($existingInstances.Count -eq 0)
    {
        # Sentinel entry so HINV can still see the script ran
        $entry = @{
            KeyName                             = 'NoBootEvent'
            RecordId                            = [uint64]0
            TimeCreated                         = $collectionDmtf
            CollectionTime                      = $collectionDmtf
            BootStartTime                       = $collectionDmtf
            BootEndTime                         = $collectionDmtf
            BootTime                            = [uint32]0
            MainPathBootTime                    = [uint32]0
            BootKernelInitTime                  = [uint32]0
            BootDriverInitTime                  = [uint32]0
            BootPostBootTime                    = [uint32]0
            BootImprovementDelta                = [uint32]0
            BootDegradationDelta                = [uint32]0
            BootIsDegradation                   = $false
            BootIsStepDegradation               = $false
            BootIsGradualDegradation            = $false
            BootIsRootCauseIdentified           = $false
            BootIsRebootAfterInstall            = $false
            BootRootCauseStepImprovementBits    = [uint32]0
            BootRootCauseGradualImprovementBits = [uint32]0
            BootRootCauseStepDegradationBits    = [uint32]0
            BootRootCauseGradualDegradationBits = [uint32]0
            BootTsVersion                       = [uint32]0
            SystemBootInstance                  = [uint32]0
            UserBootInstance                    = [uint32]0
            BootDevicesInitTime                 = [uint32]0
            BootPrefetchInitTime                = [uint32]0
            BootPrefetchBytes                   = [uint64]0
            BootAutoChkTime                     = [uint32]0
            BootSmssInitTime                    = [uint32]0
            BootCriticalServicesInitTime        = [uint32]0
            BootUserProfileProcessingTime       = [uint32]0
            BootMachineProfileProcessingTime    = [uint32]0
            BootExplorerInitTime                = [uint32]0
            BootNumStartupApps                  = [uint32]0
            OSLoaderDuration                    = [uint32]0
            BootPNPInitStartTimeMS              = [uint32]0
            BootPNPInitDuration                 = [uint32]0
            OtherKernelInitDuration             = [uint32]0
            SystemPNPInitStartTimeMS            = [uint32]0
            SystemPNPInitDuration               = [uint32]0
            SessionInitStartTimeMS              = [uint32]0
            Session0InitDuration                = [uint32]0
            Session1InitDuration                = [uint32]0
            SessionInitOtherDuration            = [uint32]0
            WinLogonStartTimeMS                 = [uint32]0
            OtherLogonInitActivityDuration      = [uint32]0
            UserLogonWaitDuration               = [uint32]0
            NetAdapterName                      = $net.NetAdapterName
            NetAdapterDescription     = $net.NetAdapterDescription
            NetAdapterMacAddress      = $net.NetAdapterMacAddress
            IPAddress                 = $net.IPAddress
            SubnetMask                = $net.SubnetMask
            PrefixLength              = [byte]$net.PrefixLength
            DefaultGateway            = $net.DefaultGateway
            ConnectionProfileName     = $net.ConnectionProfileName
            NetworkStatus             = [string]$net.NetworkStatus
            LinkSpeed                 = [string]$net.LinkSpeed
        }

        Set-WmiInstance -Path "\\.\$($WMIRootPath):$($WMIClassName)" -Arguments $entry | Out-Null
    }
    return
}

foreach ($b in $bootEvents)
{
    # Skip events that are already stored in the WMI class
    if ($existingRecordIds.ContainsKey([string]$b.RecordId))
    {
        continue
    }

    $timeCreatedDmtf = [Management.ManagementDateTimeConverter]::ToDmtfDateTime($b.TimeCreated)

    if ($b.BootStartTime) { $bootStartDmtf = [Management.ManagementDateTimeConverter]::ToDmtfDateTime($b.BootStartTime) } else { $bootStartDmtf = $timeCreatedDmtf }
    if ($b.BootEndTime)   { $bootEndDmtf   = [Management.ManagementDateTimeConverter]::ToDmtfDateTime($b.BootEndTime) }   else { $bootEndDmtf   = $timeCreatedDmtf }

    $entry = @{
        KeyName                             = ('{0}_{1}' -f $b.RecordId, $timeCreatedDmtf)
        RecordId                            = [uint64]$b.RecordId
        TimeCreated                         = $timeCreatedDmtf
        CollectionTime                      = $collectionDmtf
        BootStartTime                       = $bootStartDmtf
        BootEndTime                         = $bootEndDmtf
        BootTime                            = [uint32]$b.BootTime
        MainPathBootTime                    = [uint32]$b.MainPathBootTime
        BootKernelInitTime                  = [uint32]$b.BootKernelInitTime
        BootDriverInitTime                  = [uint32]$b.BootDriverInitTime
        BootPostBootTime                    = [uint32]$b.BootPostBootTime
        BootImprovementDelta                = [uint32]$b.BootImprovementDelta
        BootDegradationDelta                = [uint32]$b.BootDegradationDelta
        BootIsDegradation                   = [bool]$b.BootIsDegradation
        BootIsStepDegradation               = [bool]$b.BootIsStepDegradation
        BootIsGradualDegradation            = [bool]$b.BootIsGradualDegradation
        BootIsRootCauseIdentified           = [bool]$b.BootIsRootCauseIdentified
        BootIsRebootAfterInstall            = [bool]$b.BootIsRebootAfterInstall
        BootRootCauseStepImprovementBits    = [uint32]$b.BootRootCauseStepImprovementBits
        BootRootCauseGradualImprovementBits = [uint32]$b.BootRootCauseGradualImprovementBits
        BootRootCauseStepDegradationBits    = [uint32]$b.BootRootCauseStepDegradationBits
        BootRootCauseGradualDegradationBits = [uint32]$b.BootRootCauseGradualDegradationBits
        BootTsVersion                       = [uint32]$b.BootTsVersion
        SystemBootInstance                  = [uint32]$b.SystemBootInstance
        UserBootInstance                    = [uint32]$b.UserBootInstance
        BootDevicesInitTime                 = [uint32]$b.BootDevicesInitTime
        BootPrefetchInitTime                = [uint32]$b.BootPrefetchInitTime
        BootPrefetchBytes                   = [uint64]$b.BootPrefetchBytes
        BootAutoChkTime                     = [uint32]$b.BootAutoChkTime
        BootSmssInitTime                    = [uint32]$b.BootSmssInitTime
        BootCriticalServicesInitTime        = [uint32]$b.BootCriticalServicesInitTime
        BootUserProfileProcessingTime       = [uint32]$b.BootUserProfileProcessingTime
        BootMachineProfileProcessingTime    = [uint32]$b.BootMachineProfileProcessingTime
        BootExplorerInitTime                = [uint32]$b.BootExplorerInitTime
        BootNumStartupApps                  = [uint32]$b.BootNumStartupApps
        OSLoaderDuration                    = [uint32]$b.OSLoaderDuration
        BootPNPInitStartTimeMS              = [uint32]$b.BootPNPInitStartTimeMS
        BootPNPInitDuration                 = [uint32]$b.BootPNPInitDuration
        OtherKernelInitDuration             = [uint32]$b.OtherKernelInitDuration
        SystemPNPInitStartTimeMS            = [uint32]$b.SystemPNPInitStartTimeMS
        SystemPNPInitDuration               = [uint32]$b.SystemPNPInitDuration
        SessionInitStartTimeMS              = [uint32]$b.SessionInitStartTimeMS
        Session0InitDuration                = [uint32]$b.Session0InitDuration
        Session1InitDuration                = [uint32]$b.Session1InitDuration
        SessionInitOtherDuration            = [uint32]$b.SessionInitOtherDuration
        WinLogonStartTimeMS                 = [uint32]$b.WinLogonStartTimeMS
        OtherLogonInitActivityDuration      = [uint32]$b.OtherLogonInitActivityDuration
        UserLogonWaitDuration               = [uint32]$b.UserLogonWaitDuration
        NetAdapterName                      = $net.NetAdapterName
        NetAdapterDescription     = $net.NetAdapterDescription
        NetAdapterMacAddress      = $net.NetAdapterMacAddress
        IPAddress                 = $net.IPAddress
        SubnetMask                = $net.SubnetMask
        PrefixLength              = [byte]$net.PrefixLength
        DefaultGateway            = $net.DefaultGateway
        ConnectionProfileName     = $net.ConnectionProfileName
        NetworkStatus             = [string]$net.NetworkStatus
        LinkSpeed                 = [string]$net.LinkSpeed
    }

    Set-WmiInstance -Path "\\.\$($WMIRootPath):$($WMIClassName)" -Arguments $entry | Out-Null
}

# Trim the class so it never exceeds $MaxWmiEntries instances. Oldest first
# (by TimeCreated, then RecordId). A 'NoBootEvent' sentinel from a previous
# run is always removed first since real data is now available.
if ($MaxWmiEntries -gt 0)
{
    $allInstances = @(Get-WmiObject -Namespace $WMIRootPath -Class $WMIClassName -ErrorAction SilentlyContinue)

    # Drop sentinel rows whenever real data is present
    $sentinels = $allInstances | Where-Object { $_.KeyName -eq 'NoBootEvent' }
    if ($sentinels) { $sentinels | Remove-WmiObject }
    $allInstances = @($allInstances | Where-Object { $_.KeyName -ne 'NoBootEvent' })

    if ($allInstances.Count -gt $MaxWmiEntries)
    {
        $toRemoveCount = $allInstances.Count - $MaxWmiEntries
        $allInstances |
            Sort-Object -Property TimeCreated, RecordId |
            Select-Object -First $toRemoveCount |
            Remove-WmiObject
    }
}
