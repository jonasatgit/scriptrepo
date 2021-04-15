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

<#
.Synopsis
    Script to validate the hardware inventory classes of a ConfigMgr client setting.
.DESCRIPTION
    The script is intended to compare a given set of hardware inventory classes with what has been activated in any given ConfigMgr client setting.
    When used without any parameters the script will compare a known list of classes against the "Default Client Setting".
    The known list of classes is part of the script and should represent the active default classes of a ConfigMgr 2010 installation. 
    It is designed to either run within a ConfigMgr configuration item and a baseline or as a standalone script. 
    The script mode can be set via the parameter "OutputMode" and the default value is "CompareData" to be able to use the script as part of a 
    ConfigMgr configuration item.
    NOTE: Do not run the script in the PowerShell ISE since that might give strange results. 
    For more information run "Get-Help .\Compare-ClientSettingHINVClasses.ps1 -Detailed"
    Source: https://github.com/jonasatgit/scriptrepo

.PARAMETER OutputMode
    The parameter OutputMode has four possible options:
    "CompareData":
        CompareData is the default value and will output the difference between the known classes and the current active classes of a given client setting.
    "ShowData": 
        ShowData will open two GridViews. One for all possible inventory classes and one with the active classes for the selected client setting.
    "ExportAsCSV":
        Will create two csv files in the same directory as the script. 
        One for all possible inventory classes and one with the active classes for the selected client setting.
    "CreateScript":
        CreateScript will read the current active inventory classes of a given client setting and will create a new script (in the same directory)
        with the current active inventory classes as the new known classes list to be able to compare that state with a later state. 
        The script name will contain the client setting name and the date and time of creation. 
        The parameter "ClientSettingsName" of the new script will be changed to the client settings name.
        The new script can be used in a ConfigMgr configuration item directly without any extra changes to it. 
    
.PARAMETER ClientSettingsName
    The name of the client setting to be validated.
    The default value is: "Default Client Setting".
    "Heartbeat" can also be used as a client setting name, even though it is a discovery method in the ConfigMgr console. 

.PARAMETER ProviderMachineName
    Name/FQDN of the ConfigMgr SMS provider machine. 
    Default value is the local system

.PARAMETER SiteCode
    ConfigMgr sitecode.
    Will be detected automatically, but might be needed in some circumstances.

.PARAMETER ForceWSMANConnection
    Can be used to force Get-CimInstance to use WSMAn instead of DCOM for WMI queries. 

.EXAMPLE
    Compare knonw list of active inventory classes for "Default Client Setting".
    .\Compare-ClientSettingHINVClasses.ps1
    .\Compare-ClientSettingHINVClasses.ps1 -Verbose

.EXAMPLE
    Show all available inventory classes and the classes of the "Default Client Setting" in two GridViews. 
    .\Compare-ClientSettingHINVClasses.ps1 -OutputMode ShowData

.EXAMPLE
    Export available inventory classes and the classes of the "Default Client Setting" in two csv files. 
    .\Compare-ClientSettingHINVClasses.ps1 -OutputMode ExportAsCSV

.EXAMPLE

    .\Compare-ClientSettingHINVClasses.ps1 -OutputMode CreateScript -ClientSettingsName 'Contoso Custom Client Setting'
.EXAMPLE
    .\Compare-ClientSettingHINVClasses.ps1 -OutputMode ShowData -ForceWSMANConnection

.LINK 
    https://github.com/jonasatgit/scriptrepo
    
#>
#region Parameters
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [string]$ClientSettingsName = 'Default Client Setting',
    [Parameter(Mandatory=$false)]
    [string]$ProviderMachineName = $env:COMPUTERNAME,
    [Parameter(Mandatory=$false)]
    [string]$SiteCode,
    [Parameter(Mandatory=$false)]
    [switch]$ForceWSMANConnection,
    [Parameter(Mandatory=$false)]
    [ValidateSet("ShowData", "ExportAsCSV", "CreateScript","CompareData")]
    [string]$OutputMode = 'CompareData'
)
#endregion


#region Initializing
$scriptPathAndName = ($MyInvocation.InvocationName)
$scriptName = $scriptPathAndName | Split-Path -Leaf

# removing invalid filename characters and spaces from client setting name to be able to use the name as a filename
[System.IO.Path]::GetInvalidFileNameChars() | ForEach-Object {

    $ClientSettingsNameClean = $ClientSettingsName -replace "\$_",''
}
$ClientSettingsNameClean = $ClientSettingsNameClean -replace " ","-"
#endregion


#region Reference data
$referenceData = @{}
$referenceData.add("System Devices;CompatibleIDs","1")
$referenceData.add("Tape Drive;Status","1")
$referenceData.add("Add Remove Programs;DisplayName","1")
$referenceData.add("Add Remove Programs;InstallDate","1")
$referenceData.add("Add Remove Programs;ProdID","1")
$referenceData.add("Add Remove Programs;Publisher","1")
$referenceData.add("Add Remove Programs;Version","1")
$referenceData.add("Memory;Name","1")
$referenceData.add("Memory;TotalPageFileSpace","1")
$referenceData.add("Memory;TotalPhysicalMemory","1")
$referenceData.add("Tape Drive;Name","1")
$referenceData.add("Memory;TotalVirtualMemory","1")
$referenceData.add("Virtual Applications;Name","1")
$referenceData.add("Virtual Applications;PackageGUID","1")
$referenceData.add("Virtual Applications;Version","1")
$referenceData.add("Parallel Port;Availability","1")
$referenceData.add("Parallel Port;Capabilities","1")
$referenceData.add("Parallel Port;DeviceID","1")
$referenceData.add("Parallel Port;Name","1")
$referenceData.add("Parallel Port;Status","1")
$referenceData.add("Power Configurations;NonPeakPowerPlanName","1")
$referenceData.add("Virtual Applications;LastLaunchOnSystem","1")
$referenceData.add("Power Configurations;PeakPowerPlanName","1")
$referenceData.add("Tape Drive;MediaType","1")
$referenceData.add("Tape Drive;Description","1")
$referenceData.add("Virtual Application Packages;Version","1")
$referenceData.add("Virtual Application Packages;VersionGUID","1")
$referenceData.add("Browser Usage;BrowserName","1")
$referenceData.add("Browser Usage;UsagePercentage","1")
$referenceData.add("Virtual Machine Details;Name","1")
$referenceData.add("USM Folder Redirection Health;HealthStatus","1")
$referenceData.add("USM Folder Redirection Health;OfflineAccessEnabled","1")
$referenceData.add("USM Folder Redirection Health;Redirected","1")
$referenceData.add("CD-ROM;Availability","1")
$referenceData.add("Tape Drive;DeviceID","1")
$referenceData.add("CD-ROM;Caption","1")
$referenceData.add("CD-ROM;DeviceID","1")
$referenceData.add("CD-ROM;Drive","1")
$referenceData.add("CD-ROM;Manufacturer","1")
$referenceData.add("CD-ROM;MediaType","1")
$referenceData.add("CD-ROM;Name","1")
$referenceData.add("CD-ROM;SCSITargetId","1")
$referenceData.add("CD-ROM;SystemName","1")
$referenceData.add("CD-ROM;VolumeName","1")
$referenceData.add("Tape Drive;Availability","1")
$referenceData.add("CD-ROM;Description","1")
$referenceData.add("Power Configurations;PowerConfigID","1")
$referenceData.add("Power Configurations;WakeUpTimeHoursMin","1")
$referenceData.add("Office Product Info;Architecture","1")
$referenceData.add("Add Remove Programs (64);DisplayName","1")
$referenceData.add("Add Remove Programs (64);InstallDate","1")
$referenceData.add("Add Remove Programs (64);ProdID","1")
$referenceData.add("Add Remove Programs (64);Publisher","1")
$referenceData.add("Add Remove Programs (64);Version","1")
$referenceData.add("Operating System Ex;Name","1")
$referenceData.add("Operating System Ex;SKU","1")
$referenceData.add("Office365ProPlusConfigurations;AutoUpgrade","1")
$referenceData.add("Office365ProPlusConfigurations;CCMManaged","1")
$referenceData.add("CCM Recently Used Applications;SoftwarePropertiesHash","1")
$referenceData.add("Office365ProPlusConfigurations;CDNBaseUrl","1")
$referenceData.add("Office365ProPlusConfigurations;ClientCulture","1")
$referenceData.add("Office365ProPlusConfigurations;ClientFolder","1")
$referenceData.add("Office365ProPlusConfigurations;GPOChannel","1")
$referenceData.add("Office365ProPlusConfigurations;GPOOfficeMgmtCOM","1")
$referenceData.add("Office365ProPlusConfigurations;InstallationPath","1")
$referenceData.add("Office365ProPlusConfigurations;KeyName","1")
$referenceData.add("Office365ProPlusConfigurations;LastScenario","1")
$referenceData.add("Office365ProPlusConfigurations;LastScenarioResult","1")
$referenceData.add("Office365ProPlusConfigurations;OfficeMgmtCOM","1")
$referenceData.add("Office365ProPlusConfigurations;cfgUpdateChannel","1")
$referenceData.add("CCM Recently Used Applications;ProductVersion","1")
$referenceData.add("CCM Recently Used Applications;ProductName","1")
$referenceData.add("CCM Recently Used Applications;ProductLanguage","1")
$referenceData.add("Office Product Info;Channel","1")
$referenceData.add("Office Product Info;IsProPlusInstalled","1")
$referenceData.add("Office Product Info;Language","1")
$referenceData.add("Office Product Info;LicenseState","1")
$referenceData.add("Office Product Info;ProductName","1")
$referenceData.add("Office Product Info;ProductVersion","1")
$referenceData.add("CCM Recently Used Applications;AdditionalProductCodes","1")
$referenceData.add("CCM Recently Used Applications;CompanyName","1")
$referenceData.add("CCM Recently Used Applications;ExplorerFileName","1")
$referenceData.add("CCM Recently Used Applications;FileDescription","1")
$referenceData.add("CCM Recently Used Applications;FilePropertiesHash","1")
$referenceData.add("CCM Recently Used Applications;FileSize","1")
$referenceData.add("CCM Recently Used Applications;FileVersion","1")
$referenceData.add("CCM Recently Used Applications;FolderPath","1")
$referenceData.add("CCM Recently Used Applications;LastUsedTime","1")
$referenceData.add("CCM Recently Used Applications;LastUserName","1")
$referenceData.add("CCM Recently Used Applications;msiDisplayName","1")
$referenceData.add("CCM Recently Used Applications;msiPublisher","1")
$referenceData.add("CCM Recently Used Applications;msiVersion","1")
$referenceData.add("CCM Recently Used Applications;OriginalFileName","1")
$referenceData.add("CCM Recently Used Applications;ProductCode","1")
$referenceData.add("Virtual Application Packages;TotalSize","1")
$referenceData.add("Office365ProPlusConfigurations;Platform","1")
$referenceData.add("Virtual Application Packages;PackageGUID","1")
$referenceData.add("Virtual Application Packages;LaunchSize","1")
$referenceData.add("Processor;DeviceID","1")
$referenceData.add("Processor;Family","1")
$referenceData.add("Processor;Is64Bit","1")
$referenceData.add("Processor;IsHyperthreadCapable","1")
$referenceData.add("Processor;IsMobile","1")
$referenceData.add("Processor;IsTrustedExecutionCapable","1")
$referenceData.add("Processor;IsVitualizationCapable","1")
$referenceData.add("Processor;Manufacturer","1")
$referenceData.add("Processor;MaxClockSpeed","1")
$referenceData.add("Processor;DataWidth","1")
$referenceData.add("Processor;Name","1")
$referenceData.add("Processor;NumberOfCores","1")
$referenceData.add("Processor;NumberOfLogicalProcessors","1")
$referenceData.add("Processor;PCache","1")
$referenceData.add("Processor;ProcessorId","1")
$referenceData.add("Processor;ProcessorType","1")
$referenceData.add("Processor;Revision","1")
$referenceData.add("Processor;SocketDesignation","1")
$referenceData.add("Processor;Status","1")
$referenceData.add("Processor;SystemName","1")
$referenceData.add("Processor;NormSpeed","1")
$referenceData.add("Processor;Version","1")
$referenceData.add("Processor;CPUKey","1")
$referenceData.add("Processor;BrandID","1")
$referenceData.add("BIOS;SoftwareElementID","1")
$referenceData.add("BIOS;SoftwareElementState","1")
$referenceData.add("BIOS;TargetOperatingSystem","1")
$referenceData.add("BIOS;Version","1")
$referenceData.add("PhysicalDisk;BusType","1")
$referenceData.add("PhysicalDisk;FirmwareVersion","1")
$referenceData.add("PhysicalDisk;FriendlyName","1")
$referenceData.add("PhysicalDisk;HealthStatus","1")
$referenceData.add("PhysicalDisk;LogicalSectorSize","1")
$referenceData.add("Processor;CPUHash","1")
$referenceData.add("PhysicalDisk;Manufacturer","1")
$referenceData.add("PhysicalDisk;Model","1")
$referenceData.add("PhysicalDisk;ObjectId","1")
$referenceData.add("PhysicalDisk;PhysicalSectorSize","1")
$referenceData.add("PhysicalDisk;SerialNumber","1")
$referenceData.add("PhysicalDisk;Size","1")
$referenceData.add("PhysicalDisk;SpindleSpeed","1")
$referenceData.add("PhysicalDisk;UniqueId","1")
$referenceData.add("PhysicalDisk;Usage","1")
$referenceData.add("Processor;AddressWidth","1")
$referenceData.add("PhysicalDisk;MediaType","1")
$referenceData.add("Connected Device;DeviceOEMInfo","1")
$referenceData.add("Connected Device;DeviceType","1")
$referenceData.add("Connected Device;InstalledClientID","1")
$referenceData.add("Disk;PNPDeviceID","1")
$referenceData.add("Disk;SCSIBus","1")
$referenceData.add("Disk;SCSILogicalUnit","1")
$referenceData.add("Disk;SCSIPort","1")
$referenceData.add("Disk;SCSITargetId","1")
$referenceData.add("Disk;Size","1")
$referenceData.add("Disk;SystemName","1")
$referenceData.add("TPM;IsActivated_InitialValue","1")
$referenceData.add("TPM;IsEnabled_InitialValue","1")
$referenceData.add("Disk;Partitions","1")
$referenceData.add("TPM;IsOwned_InitialValue","1")
$referenceData.add("TPM;ManufacturerVersion","1")
$referenceData.add("TPM;ManufacturerVersionInfo","1")
$referenceData.add("TPM;PhysicalPresenceVersionInfo","1")
$referenceData.add("TPM;SpecVersion","1")
$referenceData.add("Firmware;SecureBoot","1")
$referenceData.add("Firmware;UEFI","1")
$referenceData.add("Virtual Application Packages;CachedLaunchSize","1")
$referenceData.add("Virtual Application Packages;CachedPercentage","1")
$referenceData.add("Virtual Application Packages;CachedSize","1")
$referenceData.add("TPM;ManufacturerId","1")
$referenceData.add("Disk;Name","1")
$referenceData.add("Disk;Model","1")
$referenceData.add("Disk;MediaType","1")
$referenceData.add("Connected Device;InstalledClientServer","1")
$referenceData.add("Connected Device;InstalledClientVersion","1")
$referenceData.add("Connected Device;LastSyncTime","1")
$referenceData.add("Connected Device;OS_AdditionalInfo","1")
$referenceData.add("Connected Device;OS_Build","1")
$referenceData.add("Connected Device;OS_Major","1")
$referenceData.add("Connected Device;OS_Minor","1")
$referenceData.add("Connected Device;OS_Platform","1")
$referenceData.add("Connected Device;ProcessorArchitecture","1")
$referenceData.add("Connected Device;ProcessorLevel","1")
$referenceData.add("Connected Device;ProcessorRevision","1")
$referenceData.add("Office Vba Rule Violation;FileCount","1")
$referenceData.add("Office Vba Rule Violation;OfficeApp","1")
$referenceData.add("Office Vba Rule Violation;RuleId","1")
$referenceData.add("Disk;Availability","1")
$referenceData.add("Disk;Caption","1")
$referenceData.add("Disk;Description","1")
$referenceData.add("Disk;DeviceID","1")
$referenceData.add("Disk;Index","1")
$referenceData.add("Disk;InterfaceType","1")
$referenceData.add("Disk;Manufacturer","1")
$referenceData.add("Virtual Application Packages;Name","1")
$referenceData.add("Office365ProPlusConfigurations;SharedComputerLicensing","1")
$referenceData.add("Office365ProPlusConfigurations;UpdateChannel","1")
$referenceData.add("Office365ProPlusConfigurations;UpdatePath","1")
$referenceData.add("Computer System;Description","1")
$referenceData.add("Computer System;Domain","1")
$referenceData.add("Computer System;DomainRole","1")
$referenceData.add("Computer System;Manufacturer","1")
$referenceData.add("Computer System;Model","1")
$referenceData.add("Computer System;Name","1")
$referenceData.add("Computer System;NumberOfProcessors","1")
$referenceData.add("Computer System;Roles","1")
$referenceData.add("Computer System;Status","1")
$referenceData.add("Computer System;CurrentTimeZone","1")
$referenceData.add("Computer System;SystemType","1")
$referenceData.add("Office Document Metric;OfficeApp","1")
$referenceData.add("Office Document Metric;TotalCloudDocs","1")
$referenceData.add("Office Document Metric;TotalLegacyDocs","1")
$referenceData.add("Office Document Metric;TotalLocalDocs","1")
$referenceData.add("Office Document Metric;TotalMacroDocs","1")
$referenceData.add("Office Document Metric;TotalNonMacroDocs","1")
$referenceData.add("Office Document Metric;TotalUncDocs","1")
$referenceData.add("Device Computer System;CellularTechnology","1")
$referenceData.add("Device Computer System;DeviceClientID","1")
$referenceData.add("Computer System;UserName","1")
$referenceData.add("Device Computer System;DeviceManufacturer","1")
$referenceData.add("Device Display;VerticalResolution","1")
$referenceData.add("Device Display;HorizontalResolution","1")
$referenceData.add("USB Controller;Availability","1")
$referenceData.add("USB Controller;Description","1")
$referenceData.add("USB Controller;DeviceID","1")
$referenceData.add("USB Controller;Name","1")
$referenceData.add("Power Capabilities;ApmPresent","1")
$referenceData.add("Power Capabilities;BatteriesAreShortTerm","1")
$referenceData.add("Power Capabilities;FullWake","1")
$referenceData.add("Power Capabilities;LidPresent","1")
$referenceData.add("Power Capabilities;MinDeviceWakeState","1")
$referenceData.add("Device Display;NumberOfColors","1")
$referenceData.add("Power Capabilities;PreferredPMProfile","1")
$referenceData.add("Power Capabilities;RtcWake","1")
$referenceData.add("Power Capabilities;SystemBatteriesPresent","1")
$referenceData.add("Power Capabilities;SystemS1","1")
$referenceData.add("Power Capabilities;SystemS2","1")
$referenceData.add("Power Capabilities;SystemS3","1")
$referenceData.add("Power Capabilities;SystemS4","1")
$referenceData.add("Power Capabilities;SystemS5","1")
$referenceData.add("Power Capabilities;UpsPresent","1")
$referenceData.add("Power Capabilities;VideoDimPresent","1")
$referenceData.add("Power Capabilities;ProcessorThrottle","1")
$referenceData.add("Device Computer System;DeviceModel","1")
$referenceData.add("Device Computer System;DMVersion","1")
$referenceData.add("Device Computer System;FirmwareVersion","1")
$referenceData.add("Office Addin;FileVersion","1")
$referenceData.add("Office Addin;FriendlyName","1")
$referenceData.add("Office Addin;FriendlyNameHash","1")
$referenceData.add("Office Addin;Id","1")
$referenceData.add("Office Addin;IdHash","1")
$referenceData.add("Office Addin;OfficeApp","1")
$referenceData.add("Office Addin;ProductName","1")
$referenceData.add("Office Addin;ProductVersion","1")
$referenceData.add("Office Addin;Type","1")
$referenceData.add("Office Addin;FileTimeStamp","1")
$referenceData.add("Office Addin;AverageLoadTimeInMilliseconds","1")
$referenceData.add("Office Addin;ErrorCount","1")
$referenceData.add("Office Addin;LoadBehavior","1")
$referenceData.add("Office Addin;LoadCount","1")
$referenceData.add("Office Addin;LoadFailCount","1")
$referenceData.add("ActiveSync Service;LastSyncTime","1")
$referenceData.add("ActiveSync Service;MajorVersion","1")
$referenceData.add("ActiveSync Service;MinorVersion","1")
$referenceData.add("Network Client;Description","1")
$referenceData.add("Network Client;Manufacturer","1")
$referenceData.add("Office Addin;CrashCount","1")
$referenceData.add("Office Addin;FileSize","1")
$referenceData.add("Office Addin;FileName","1")
$referenceData.add("Office Addin;Description","1")
$referenceData.add("Device Computer System;HardwareVersion","1")
$referenceData.add("Device Computer System;IMEI","1")
$referenceData.add("Device Computer System;IMSI","1")
$referenceData.add("Device Computer System;IsActivationLockEnabled","1")
$referenceData.add("Device Computer System;Jailbroken","1")
$referenceData.add("Device Computer System;MEID","1")
$referenceData.add("Device Computer System;OEM","1")
$referenceData.add("Device Computer System;PhoneNumber","1")
$referenceData.add("Device Computer System;PlatformType","1")
$referenceData.add("Device Computer System;ProcessorArchitecture","1")
$referenceData.add("Device Computer System;ProcessorLevel","1")
$referenceData.add("Device Computer System;ProcessorRevision","1")
$referenceData.add("Device Computer System;Product","1")
$referenceData.add("Device Computer System;ProductVersion","1")
$referenceData.add("Device Computer System;SerialNumber","1")
$referenceData.add("Device Computer System;SoftwareVersion","1")
$referenceData.add("Device Computer System;SubscriberCarrierNetwork","1")
$referenceData.add("Windows Update;UseWUServer","1")
$referenceData.add("Office Addin;Architecture","1")
$referenceData.add("Office Addin;Clsid","1")
$referenceData.add("Office Addin;CompanyName","1")
$referenceData.add("TPM Status;IsReady","1")
$referenceData.add("TPM Status;IsApplicable","1")
$referenceData.add("TPM Status;Information","1")
$referenceData.add("Office Document Solution;Type","1")
$referenceData.add("Device Password;MaxAttemptsBeforeWipe","1")
$referenceData.add("Device Password;MinComplexChars","1")
$referenceData.add("Device Password;MinLength","1")
$referenceData.add("Device Password;PasswordQuality","1")
$referenceData.add("Device Password;Type","1")
$referenceData.add("Sound Devices;Availability","1")
$referenceData.add("Sound Devices;Description","1")
$referenceData.add("Sound Devices;DeviceID","1")
$referenceData.add("Sound Devices;InstallDate","1")
$referenceData.add("Device Password;History","1")
$referenceData.add("Sound Devices;Manufacturer","1")
$referenceData.add("Sound Devices;PNPDeviceID","1")
$referenceData.add("Sound Devices;ProductName","1")
$referenceData.add("Sound Devices;Status","1")
$referenceData.add("AMT Agent;AMT","1")
$referenceData.add("AMT Agent;AMTApps","1")
$referenceData.add("AMT Agent;BiosVersion","1")
$referenceData.add("AMT Agent;BuildNumber","1")
$referenceData.add("AMT Agent;DeviceID","1")
$referenceData.add("AMT Agent;Flash","1")
$referenceData.add("Sound Devices;Name","1")
$referenceData.add("Device Password;Expiration","1")
$referenceData.add("Device Password;Enabled","1")
$referenceData.add("Device Password;AutolockTimeout","1")
$referenceData.add("Office365ProPlusConfigurations;UpdatesEnabled","1")
$referenceData.add("Office365ProPlusConfigurations;UpdateUrl","1")
$referenceData.add("Office365ProPlusConfigurations;VersionToReport","1")
$referenceData.add("Device OS Information;Language","1")
$referenceData.add("Device OS Information;Platform","1")
$referenceData.add("Device OS Information;Version","1")
$referenceData.add("SMS Advanced Client SSL Configurations;CertificateSelectionCriteria","1")
$referenceData.add("SMS Advanced Client SSL Configurations;CertificateStore","1")
$referenceData.add("SMS Advanced Client SSL Configurations;ClientAlwaysOnInternet","1")
$referenceData.add("SMS Advanced Client SSL Configurations;HttpsStateFlags","1")
$referenceData.add("SMS Advanced Client SSL Configurations;InstanceKey","1")
$referenceData.add("SMS Advanced Client SSL Configurations;InternetMPHostName","1")
$referenceData.add("SMS Advanced Client SSL Configurations;SelectFirstCertificate","1")
$referenceData.add("Power Management Insomnia Reasons;Requester","1")
$referenceData.add("Power Management Insomnia Reasons;RequesterInfo","1")
$referenceData.add("Power Management Insomnia Reasons;RequesterType","1")
$referenceData.add("Power Management Insomnia Reasons;RequestType","1")
$referenceData.add("Power Management Insomnia Reasons;Time","1")
$referenceData.add("Power Management Insomnia Reasons;UnknownRequester","1")
$referenceData.add("Windows Update Agent Version;Version","1")
$referenceData.add("Device Password;AllowRecoveryPassword","1")
$referenceData.add("AMT Agent;LegacyMode","1")
$referenceData.add("BIOS;SMBIOSBIOSVersion","1")
$referenceData.add("AMT Agent;Netstack","1")
$referenceData.add("AMT Agent;ProvisionState","1")
$referenceData.add("IDE Controller;DeviceID","1")
$referenceData.add("IDE Controller;Manufacturer","1")
$referenceData.add("IDE Controller;Name","1")
$referenceData.add("IDE Controller;Status","1")
$referenceData.add("Power Management Monthly;minutesComputerActive","1")
$referenceData.add("Power Management Monthly;minutesComputerOn","1")
$referenceData.add("Power Management Monthly;minutesComputerShutdown","1")
$referenceData.add("Power Management Monthly;minutesComputerSleep","1")
$referenceData.add("Power Management Monthly;minutesMonitorOn","1")
$referenceData.add("IDE Controller;Description","1")
$referenceData.add("Power Management Monthly;minutesTotal","1")
$referenceData.add("Office Document Solution;CompatibilityErrorCount","1")
$referenceData.add("Office Document Solution;CrashCount","1")
$referenceData.add("Office Document Solution;DocumentSolutionId","1")
$referenceData.add("Office Document Solution;ExampleFileName","1")
$referenceData.add("Office Document Solution;LoadCount","1")
$referenceData.add("Office Document Solution;LoadFailCount","1")
$referenceData.add("Office Document Solution;MacroCompileErrorCount","1")
$referenceData.add("Office Document Solution;MacroRuntimeErrorCount","1")
$referenceData.add("Office Document Solution;OfficeApp","1")
$referenceData.add("Power Management Monthly;MonthStart","1")
$referenceData.add("IDE Controller;Availability","1")
$referenceData.add("Device Client Agent version;Version","1")
$referenceData.add("Network Adapter;Status","1")
$referenceData.add("AMT Agent;RecoveryBuildNum","1")
$referenceData.add("AMT Agent;RecoveryVersion","1")
$referenceData.add("AMT Agent;Sku","1")
$referenceData.add("AMT Agent;TLSMode","1")
$referenceData.add("AMT Agent;VendorID","1")
$referenceData.add("AMT Agent;ZTCEnabled","1")
$referenceData.add("Services;DisplayName","1")
$referenceData.add("Services;Name","1")
$referenceData.add("Services;PathName","1")
$referenceData.add("Services;ServiceType","1")
$referenceData.add("Services;StartMode","1")
$referenceData.add("Services;StartName","1")
$referenceData.add("Services;Status","1")
$referenceData.add("Network Adapter;AdapterType","1")
$referenceData.add("Network Adapter;Description","1")
$referenceData.add("Network Adapter;DeviceID","1")
$referenceData.add("Network Adapter;MACAddress","1")
$referenceData.add("Network Adapter;Manufacturer","1")
$referenceData.add("Network Adapter;Name","1")
$referenceData.add("Network Adapter;ProductName","1")
$referenceData.add("Network Adapter;ServiceName","1")
$referenceData.add("AMT Agent;ProvisionMode","1")
$referenceData.add("Network Client;Name","1")
$referenceData.add("BIOS;SerialNumber","1")
$referenceData.add("BIOS;Name","1")
$referenceData.add("Office VbaSummary;IssuesNone64","1")
$referenceData.add("Office VbaSummary;Locked","1")
$referenceData.add("Office VbaSummary;NoVba","1")
$referenceData.add("Office VbaSummary;Protected","1")
$referenceData.add("Office VbaSummary;RemLimited","1")
$referenceData.add("Office VbaSummary;RemLimited64","1")
$referenceData.add("Office VbaSummary;RemSignificant","1")
$referenceData.add("Office VbaSummary;RemSignificant64","1")
$referenceData.add("Office VbaSummary;Score","1")
$referenceData.add("Office VbaSummary;IssuesNone","1")
$referenceData.add("Office VbaSummary;Score64","1")
$referenceData.add("Office VbaSummary;Validation","1")
$referenceData.add("Office VbaSummary;Validation64","1")
$referenceData.add("Server Feature;ID","1")
$referenceData.add("Server Feature;Name","1")
$referenceData.add("Server Feature;ParentID","1")
$referenceData.add("BitLocker Encryption Details;BitlockerPersistentVolumeId","1")
$referenceData.add("BitLocker Encryption Details;Compliant","1")
$referenceData.add("BitLocker Encryption Details;ConversionStatus","1")
$referenceData.add("BitLocker Encryption Details;DeviceId","1")
$referenceData.add("Office VbaSummary;Total","1")
$referenceData.add("BitLocker Encryption Details;DriveLetter","1")
$referenceData.add("Office VbaSummary;Issues64","1")
$referenceData.add("Office VbaSummary;Inaccessible","1")
$referenceData.add("Device Memory;StorageTotal","1")
$referenceData.add("MDM DevDetail;DeviceHardwareData","1")
$referenceData.add("MDM DevDetail;InstanceID","1")
$referenceData.add("MDM DevDetail;ParentID","1")
$referenceData.add("MDM DevDetail;WLANMACAddress","1")
$referenceData.add("Device WLAN;EthernetMAC","1")
$referenceData.add("Device WLAN;WiFiMAC","1")
$referenceData.add("System Boot Data;BiosDuration","1")
$referenceData.add("System Boot Data;BootDuration","1")
$referenceData.add("Office VbaSummary;Issues","1")
$referenceData.add("System Boot Data;EventLogStart","1")
$referenceData.add("System Boot Data;SystemStartTime","1")
$referenceData.add("System Boot Data;UpdateDuration","1")
$referenceData.add("System Boot Data;BootDiskMediaType","1")
$referenceData.add("System Boot Data;OSVersion","1")
$referenceData.add("Office VbaSummary;Design","1")
$referenceData.add("Office VbaSummary;Design64","1")
$referenceData.add("Office VbaSummary;DuplicateVba","1")
$referenceData.add("Office VbaSummary;HasResults","1")
$referenceData.add("Office VbaSummary;HasVba","1")
$referenceData.add("System Boot Data;GPDuration","1")
$referenceData.add("BitLocker Encryption Details;EncryptionMethod","1")
$referenceData.add("BitLocker Encryption Details;EnforcePolicyDate","1")
$referenceData.add("BitLocker Encryption Details;IsAutoUnlockEnabled","1")
$referenceData.add("Operating System;SerialNumber","1")
$referenceData.add("Operating System;SystemDirectory","1")
$referenceData.add("Operating System;TotalSwapSpaceSize","1")
$referenceData.add("Operating System;TotalVirtualMemorySize","1")
$referenceData.add("Operating System;TotalVisibleMemorySize","1")
$referenceData.add("Operating System;Version","1")
$referenceData.add("Operating System;WindowsDirectory","1")
$referenceData.add("Device Power;BacklightACTimeout","1")
$referenceData.add("Device Power;BacklightBatTimeout","1")
$referenceData.add("Operating System;RegisteredUser","1")
$referenceData.add("Device Power;BackupPercent","1")
$referenceData.add("Office Device Summary;IsProPlusInstalled","1")
$referenceData.add("Office Device Summary;IsTelemetryEnabled","1")
$referenceData.add("Virtual Machine;InstanceKey","1")
$referenceData.add("Virtual Machine;PhysicalHostName","1")
$referenceData.add("Virtual Machine;PhysicalHostNameFullyQualified","1")
$referenceData.add("Network Adapter Configuration;DefaultIPGateway","1")
$referenceData.add("Network Adapter Configuration;DHCPEnabled","1")
$referenceData.add("Network Adapter Configuration;DHCPServer","1")
$referenceData.add("Network Adapter Configuration;DNSDomain","1")
$referenceData.add("Device Power;BatteryPercent","1")
$referenceData.add("Operating System;ProductType","1")
$referenceData.add("Operating System;OSProductSuite","1")
$referenceData.add("Operating System;OSLanguage","1")
$referenceData.add("BitLocker Encryption Details;KeyProtectorTypes","1")
$referenceData.add("BitLocker Encryption Details;MbamPersistentVolumeId","1")
$referenceData.add("BitLocker Encryption Details;MbamVolumeType","1")
$referenceData.add("BitLocker Encryption Details;NoncomplianceDetectedDate","1")
$referenceData.add("BitLocker Encryption Details;ProtectionStatus","1")
$referenceData.add("BitLocker Encryption Details;ReasonsForNonCompliance","1")
$referenceData.add("Computer System Ex;Name","1")
$referenceData.add("Computer System Ex;PCSystemType","1")
$referenceData.add("Operating System;BootDevice","1")
$referenceData.add("Operating System;BuildNumber","1")
$referenceData.add("Operating System;Caption","1")
$referenceData.add("Operating System;CountryCode","1")
$referenceData.add("Operating System;CSDVersion","1")
$referenceData.add("Operating System;Description","1")
$referenceData.add("Operating System;InstallDate","1")
$referenceData.add("Operating System;LastBootUpTime","1")
$referenceData.add("Operating System;Locale","1")
$referenceData.add("Operating System;Manufacturer","1")
$referenceData.add("Operating System;Name","1")
$referenceData.add("Operating System;OperatingSystemSKU","1")
$referenceData.add("Operating System;Organization","1")
$referenceData.add("Device Memory;StorageFree","1")
$referenceData.add("Network Adapter Configuration;DNSHostName","1")
$referenceData.add("Device Memory;RemovableStorageTotal","1")
$referenceData.add("Device Memory;ProgramTotal","1")
$referenceData.add("System Console Usage;TopConsoleUser","1")
$referenceData.add("System Console Usage;TotalConsoleTime","1")
$referenceData.add("System Console Usage;TotalConsoleUsers","1")
$referenceData.add("System Console Usage;TotalSecurityLogTime","1")
$referenceData.add("Optional Feature;Caption","1")
$referenceData.add("Optional Feature;Description","1")
$referenceData.add("Optional Feature;InstallDate","1")
$referenceData.add("Optional Feature;InstallState","1")
$referenceData.add("Optional Feature;Name","1")
$referenceData.add("System Console Usage;SecurityLogStartDate","1")
$referenceData.add("Optional Feature;Status","1")
$referenceData.add("Virtual Machine (64);PhysicalHostName","1")
$referenceData.add("Virtual Machine (64);PhysicalHostNameFullyQualified","1")
$referenceData.add("Motherboard;Description","1")
$referenceData.add("Motherboard;DeviceID","1")
$referenceData.add("Motherboard;PrimaryBusType","1")
$referenceData.add("Motherboard;RevisionNumber","1")
$referenceData.add("Motherboard;SecondaryBusType","1")
$referenceData.add("Motherboard;Status","1")
$referenceData.add("Motherboard;StatusInfo","1")
$referenceData.add("Virtual Machine (64);InstanceKey","1")
$referenceData.add("Motherboard;SystemName","1")
$referenceData.add("Office Macro Error;Type","1")
$referenceData.add("Office Macro Error;ErrorCode","1")
$referenceData.add("System Devices;DeviceID","1")
$referenceData.add("System Devices;HardwareIDs","1")
$referenceData.add("System Devices;IsPnP","1")
$referenceData.add("System Devices;Name","1")
$referenceData.add("TS License Key Pack;AvailableLicenses","1")
$referenceData.add("TS License Key Pack;Description","1")
$referenceData.add("TS License Key Pack;IssuedLicenses","1")
$referenceData.add("TS License Key Pack;KeyPackId","1")
$referenceData.add("TS License Key Pack;KeyPackType","1")
$referenceData.add("Office Macro Error;LastOccurrence","1")
$referenceData.add("TS License Key Pack;ProductType","1")
$referenceData.add("TS License Key Pack;TotalLicenses","1")
$referenceData.add("Office Client Metric;CompatibilityErrorCount","1")
$referenceData.add("Office Client Metric;CrashedSessionCount","1")
$referenceData.add("Office Client Metric;MacroCompileErrorCount","1")
$referenceData.add("Office Client Metric;MacroRuntimeErrorCount","1")
$referenceData.add("Office Client Metric;OfficeApp","1")
$referenceData.add("Office Client Metric;SessionCount","1")
$referenceData.add("Office Macro Error;Count","1")
$referenceData.add("Office Macro Error;DocumentSolutionId","1")
$referenceData.add("TS License Key Pack;ProductVersion","1")
$referenceData.add("Power Management Daily;Date","1")
$referenceData.add("Power Management Daily;hr0_1","1")
$referenceData.add("Power Management Daily;hr1_2","1")
$referenceData.add("Power Settings;ACValue","1")
$referenceData.add("Power Settings;DCSettingIndex","1")
$referenceData.add("Power Settings;DCValue","1")
$referenceData.add("Power Settings;GUID","1")
$referenceData.add("Power Settings;Name","1")
$referenceData.add("Power Settings;UnitSpecifier","1")
$referenceData.add("Modem;AnswerMode","1")
$referenceData.add("Modem;DeviceID","1")
$referenceData.add("Modem;DeviceType","1")
$referenceData.add("Power Settings;ACSettingIndex","1")
$referenceData.add("Modem;Index","1")
$referenceData.add("Modem;MaxBaudRateToSerialPort","1")
$referenceData.add("Modem;Model","1")
$referenceData.add("Modem;Name","1")
$referenceData.add("Modem;Properties","1")
$referenceData.add("Modem;Status","1")
$referenceData.add("Modem;StringFormat","1")
$referenceData.add("Modem;SystemName","1")
$referenceData.add("Modem;VoiceSwitchFeature","1")
$referenceData.add("Device Memory;ProgramFree","1")
$referenceData.add("Modem;MaxBaudRateToPhone","1")
$referenceData.add("Power Management Daily;TypeOfEvent","1")
$referenceData.add("Power Management Daily;minutesTotal","1")
$referenceData.add("Power Management Daily;hr9_10","1")
$referenceData.add("Power Management Daily;hr10_11","1")
$referenceData.add("Power Management Daily;hr11_12","1")
$referenceData.add("Power Management Daily;hr12_13","1")
$referenceData.add("Power Management Daily;hr13_14","1")
$referenceData.add("Power Management Daily;hr14_15","1")
$referenceData.add("Power Management Daily;hr15_16","1")
$referenceData.add("Power Management Daily;hr16_17","1")
$referenceData.add("Power Management Daily;hr17_18","1")
$referenceData.add("Power Management Daily;hr18_19","1")
$referenceData.add("Power Management Daily;hr19_20","1")
$referenceData.add("Power Management Daily;hr2_3","1")
$referenceData.add("Power Management Daily;hr20_21","1")
$referenceData.add("Power Management Daily;hr21_22","1")
$referenceData.add("Power Management Daily;hr22_23","1")
$referenceData.add("Power Management Daily;hr23_0","1")
$referenceData.add("Power Management Daily;hr3_4","1")
$referenceData.add("Power Management Daily;hr4_5","1")
$referenceData.add("Power Management Daily;hr5_6","1")
$referenceData.add("Power Management Daily;hr6_7","1")
$referenceData.add("Power Management Daily;hr7_8","1")
$referenceData.add("Power Management Daily;hr8_9","1")
$referenceData.add("Device Memory;RemovableStorageFree","1")
$referenceData.add("Network Adapter Configuration;Index","1")
$referenceData.add("Network Adapter Configuration;IPAddress","1")
$referenceData.add("Network Adapter Configuration;IPEnabled","1")
$referenceData.add("Video Controller;Description","1")
$referenceData.add("Video Controller;DeviceID","1")
$referenceData.add("Video Controller;DriverDate","1")
$referenceData.add("Video Controller;DriverVersion","1")
$referenceData.add("Video Controller;InstalledDisplayDrivers","1")
$referenceData.add("Video Controller;Name","1")
$referenceData.add("Video Controller;NumberOfColorPlanes","1")
$referenceData.add("Video Controller;SpecificationVersion","1")
$referenceData.add("Video Controller;VideoMode","1")
$referenceData.add("Video Controller;CurrentVerticalResolution","1")
$referenceData.add("Video Controller;VideoModeDescription","1")
$referenceData.add("SMS_Windows8ApplicationUserInfo;FullName","1")
$referenceData.add("SMS_Windows8ApplicationUserInfo;InstallState","1")
$referenceData.add("SMS_Windows8ApplicationUserInfo;UserAccountName","1")
$referenceData.add("SMS_Windows8ApplicationUserInfo;UserSecurityId","1")
$referenceData.add("System Boot Summary;AverageBootFrequency","1")
$referenceData.add("System Boot Summary;LatestBiosDuration","1")
$referenceData.add("System Boot Summary;LatestBootDuration","1")
$referenceData.add("System Boot Summary;LatestCoreBootDuration","1")
$referenceData.add("System Boot Summary;LatestEventLogStart","1")
$referenceData.add("Video Controller;VideoProcessor","1")
$referenceData.add("System Boot Summary;LatestGPDuration","1")
$referenceData.add("Video Controller;CurrentScanMode","1")
$referenceData.add("Video Controller;CurrentNumberOfRows","1")
$referenceData.add("System Enclosure;SerialNumber","1")
$referenceData.add("System Enclosure;SMBIOSAssetTag","1")
$referenceData.add("System Enclosure;Tag","1")
$referenceData.add("Power Client Opt Out Settings;AdminAllowOptout","1")
$referenceData.add("Power Client Opt Out Settings;EffectiveClientOptOut","1")
$referenceData.add("Power Client Opt Out Settings;IsClientOptOut","1")
$referenceData.add("TS Issued License;ExpirationDate","1")
$referenceData.add("TS Issued License;IssueDate","1")
$referenceData.add("TS Issued License;KeyPackId","1")
$referenceData.add("Video Controller;CurrentRefreshRate","1")
$referenceData.add("TS Issued License;LicenseId","1")
$referenceData.add("TS Issued License;sHardwareId","1")
$referenceData.add("TS Issued License;sIssuedToComputer","1")
$referenceData.add("TS Issued License;sIssuedToUser","1")
$referenceData.add("Video Controller;AdapterCompatibility","1")
$referenceData.add("Video Controller;AdapterDACType","1")
$referenceData.add("Video Controller;AdapterRAM","1")
$referenceData.add("Video Controller;CurrentBitsPerPixel","1")
$referenceData.add("Video Controller;CurrentHorizontalResolution","1")
$referenceData.add("Video Controller;CurrentNumberOfColumns","1")
$referenceData.add("TS Issued License;LicenseStatus","1")
$referenceData.add("System Boot Summary;LatestUpdateDuration","1")
$referenceData.add("System Boot Summary;MaxBiosDuration","1")
$referenceData.add("System Boot Summary;MaxBootDuration","1")
$referenceData.add("Partition;Bootable","1")
$referenceData.add("Partition;BootPartition","1")
$referenceData.add("Partition;Description","1")
$referenceData.add("Partition;DeviceID","1")
$referenceData.add("Partition;Name","1")
$referenceData.add("Partition;PrimaryPartition","1")
$referenceData.add("Partition;Size","1")
$referenceData.add("Partition;SystemName","1")
$referenceData.add("Partition;Type","1")
$referenceData.add("Partition;Access","1")
$referenceData.add("USM User Profile;HealthStatus","1")
$referenceData.add("USM User Profile;RoamingConfigured","1")
$referenceData.add("USM User Profile;RoamingPath","1")
$referenceData.add("USM User Profile;RoamingPreference","1")
$referenceData.add("USM User Profile;Special","1")
$referenceData.add("USM User Profile;Status","1")
$referenceData.add("BIOS;BIOSVersion","1")
$referenceData.add("BIOS;BuildNumber","1")
$referenceData.add("BIOS;Description","1")
$referenceData.add("BIOS;Manufacturer","1")
$referenceData.add("USM User Profile;LocalPath","1")
$referenceData.add("Client Events;EventName","1")
$referenceData.add("Client Events;Count","1")
$referenceData.add("BitLocker Policy;UserExemptionDate","1")
$referenceData.add("System Boot Summary;MaxCoreBootDuration","1")
$referenceData.add("System Boot Summary;MaxEventLogStart","1")
$referenceData.add("System Boot Summary;MaxGPDuration","1")
$referenceData.add("System Boot Summary;MaxUpdateDuration","1")
$referenceData.add("System Boot Summary;MedianBiosDuration","1")
$referenceData.add("System Boot Summary;MedianBootDuration","1")
$referenceData.add("System Boot Summary;MedianCoreBootDuration","1")
$referenceData.add("System Boot Summary;MedianEventLogStart","1")
$referenceData.add("System Boot Summary;MedianGPDuration","1")
$referenceData.add("System Boot Summary;MedianUpdateDuration","1")
$referenceData.add("BitLocker Policy;EncodedComputerName","1")
$referenceData.add("BitLocker Policy;EncryptionMethod","1")
$referenceData.add("BitLocker Policy;FixedDataDriveAutoUnlock","1")
$referenceData.add("BitLocker Policy;FixedDataDriveEncryption","1")
$referenceData.add("BitLocker Policy;FixedDataDrivePassphrase","1")
$referenceData.add("BitLocker Policy;KeyName","1")
$referenceData.add("BitLocker Policy;LastConsoleUser","1")
$referenceData.add("BitLocker Policy;MBAMMachineError","1")
$referenceData.add("BitLocker Policy;MBAMPolicyEnforced","1")
$referenceData.add("BitLocker Policy;OsDriveEncryption","1")
$referenceData.add("BitLocker Policy;OsDriveProtector","1")
$referenceData.add("System Enclosure;Model","1")
$referenceData.add("System Enclosure;Manufacturer","1")
$referenceData.add("System Enclosure;ChassisTypes","1")
$referenceData.add("SMS Advanced Client State;Version","1")
$referenceData.add("SCSI Controller;Name","1")
$referenceData.add("SCSI Controller;Status","1")
$referenceData.add("PNP DEVICE DRIVER;ConfigManagerErrorCode","1")
$referenceData.add("PNP DEVICE DRIVER;DeviceID","1")
$referenceData.add("PNP DEVICE DRIVER;ErrorDescription","1")
$referenceData.add("PNP DEVICE DRIVER;LastErrorCode","1")
$referenceData.add("PNP DEVICE DRIVER;Name","1")
$referenceData.add("PNP DEVICE DRIVER;PNPDeviceID","1")
$referenceData.add("Physical Memory;BankLabel","1")
$referenceData.add("SCSI Controller;Manufacturer","1")
$referenceData.add("Physical Memory;Capacity","1")
$referenceData.add("Physical Memory;CreationClassName","1")
$referenceData.add("Physical Memory;DataWidth","1")
$referenceData.add("Physical Memory;Description","1")
$referenceData.add("Physical Memory;DeviceLocator","1")
$referenceData.add("Physical Memory;FormFactor","1")
$referenceData.add("Physical Memory;HotSwappable","1")
$referenceData.add("Physical Memory;InstallDate","1")
$referenceData.add("Physical Memory;InterleaveDataDepth","1")
$referenceData.add("Physical Memory;InterleavePosition","1")
$referenceData.add("Physical Memory;Caption","1")
$referenceData.add("SCSI Controller;Index","1")
$referenceData.add("SCSI Controller;HardwareVersion","1")
$referenceData.add("SCSI Controller;DriverName","1")
$referenceData.add("Network Adapter Configuration;IPSubnet","1")
$referenceData.add("Network Adapter Configuration;MACAddress","1")
$referenceData.add("Network Adapter Configuration;ServiceName","1")
$referenceData.add("SMS_Windows8Application;ApplicationName","1")
$referenceData.add("SMS_Windows8Application;Architecture","1")
$referenceData.add("SMS_Windows8Application;ConfigMgrManaged","1")
$referenceData.add("SMS_Windows8Application;DependencyApplicationNames","1")
$referenceData.add("SMS_Windows8Application;FamilyName","1")
$referenceData.add("SMS_Windows8Application;FullName","1")
$referenceData.add("SMS_Windows8Application;InstalledLocation","1")
$referenceData.add("SMS_Windows8Application;IsFramework","1")
$referenceData.add("SMS_Windows8Application;Publisher","1")
$referenceData.add("SMS_Windows8Application;PublisherId","1")
$referenceData.add("SMS_Windows8Application;Version","1")
$referenceData.add("System Console User;LastConsoleUse","1")
$referenceData.add("System Console User;NumberOfConsoleLogons","1")
$referenceData.add("System Console User;SystemConsoleUser","1")
$referenceData.add("System Console User;TotalUserConsoleMinutes","1")
$referenceData.add("SCSI Controller;Availability","1")
$referenceData.add("SCSI Controller;Description","1")
$referenceData.add("SCSI Controller;DeviceID","1")
$referenceData.add("Physical Memory;Manufacturer","1")
$referenceData.add("BIOS;ReleaseDate","1")
$referenceData.add("Physical Memory;MemoryType","1")
$referenceData.add("Physical Memory;Name","1")
$referenceData.add("Device Installed Applications;Version","1")
$referenceData.add("SMS_DefaultBrowser;BrowserProgId","1")
$referenceData.add("Logical Disk;Availability","1")
$referenceData.add("Logical Disk;Caption","1")
$referenceData.add("Logical Disk;Compressed","1")
$referenceData.add("Logical Disk;Description","1")
$referenceData.add("Logical Disk;DeviceID","1")
$referenceData.add("Logical Disk;DriveType","1")
$referenceData.add("Logical Disk;FileSystem","1")
$referenceData.add("Device Installed Applications;Name","1")
$referenceData.add("Logical Disk;FreeSpace","1")
$referenceData.add("Logical Disk;Purpose","1")
$referenceData.add("Logical Disk;Size","1")
$referenceData.add("Logical Disk;Status","1")
$referenceData.add("Logical Disk;StatusInfo","1")
$referenceData.add("Logical Disk;SystemName","1")
$referenceData.add("Logical Disk;VolumeName","1")
$referenceData.add("Logical Disk;VolumeSerialNumber","1")
$referenceData.add("SMS Advanced Client State;DisplayName","1")
$referenceData.add("SMS Advanced Client State;Name","1")
$referenceData.add("Logical Disk;Name","1")
$referenceData.add("Desktop Monitor;ScreenWidth","1")
$referenceData.add("Desktop Monitor;ScreenHeight","1")
$referenceData.add("Desktop Monitor;PixelsPerYLogicalInch","1")
$referenceData.add("Physical Memory;OtherIdentifyingInfo","1")
$referenceData.add("Physical Memory;PartNumber","1")
$referenceData.add("Physical Memory;PositionInRow","1")
$referenceData.add("Physical Memory;PoweredOn","1")
$referenceData.add("Physical Memory;Removable","1")
$referenceData.add("Physical Memory;Replaceable","1")
$referenceData.add("Physical Memory;SerialNumber","1")
$referenceData.add("Physical Memory;SKU","1")
$referenceData.add("Physical Memory;Speed","1")
$referenceData.add("Physical Memory;Status","1")
$referenceData.add("Physical Memory;Tag","1")
$referenceData.add("Physical Memory;TotalWidth","1")
$referenceData.add("Physical Memory;TypeDetail","1")
$referenceData.add("Physical Memory;Version","1")
$referenceData.add("Desktop Monitor;Description","1")
$referenceData.add("Desktop Monitor;DeviceID","1")
$referenceData.add("Desktop Monitor;DisplayType","1")
$referenceData.add("Desktop Monitor;MonitorManufacturer","1")
$referenceData.add("Desktop Monitor;MonitorType","1")
$referenceData.add("Desktop Monitor;Name","1")
$referenceData.add("Desktop Monitor;PixelsPerXLogicalInch","1")
$referenceData.add("Physical Memory;Model","1")
$referenceData.add("Network Client;Status","1")
Write-Verbose "$($referenceData.count) reference data entries"
#endregion


#region CIMSession settings
if (-NOT ($ForceWSMANConnection))
{
    $cimSessionOption = New-CimSessionOption -Protocol Dcom
    $cimSession = New-CimSession -ComputerName $ProviderMachineName -SessionOption $cimSessionOption
    Write-Verbose "Using DCOM for CimSession"
}
else 
{
    $cimSession = New-CimSession -ComputerName $ProviderMachineName
    Write-Verbose "Using WSMAN for CimSession"
}
#endregion


#region Get ConfigMgr sitecode
if (-NOT($siteCode))
{
    # getting sitecode
    $siteCode = Get-CimInstance -CimSession $cimSession -Namespace root\sms -Query 'Select SiteCode From SMS_ProviderLocation Where ProviderForLocalSite=1' -ErrorAction Stop | Select-Object -ExpandProperty SiteCode -First 1
}

if (-NOT($siteCode))
{
    # stopping script, no sitecode means script cannot run
    $cimSession | Remove-CimSession -ErrorAction SilentlyContinue
    exit 1
}
Write-Verbose "$($siteCode) detected sitecode"
#endregion


#region Get client settings with hardware inventory data
# getting client settings with HINV data and extracting InventoryReportID
[array]$SMSClientSettings = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "SELECT * FROM SMS_ClientSettings where Type = 1 and Name = '$($ClientSettingsName)'"

Write-Verbose "$($SMSClientSettings.count) client setting/s found"
$SMSClientSettingsWithHINVData = @{}
# Adding default entries to the list
$SMSClientSettingsWithHINVData.Add('{00000000-0000-0000-0000-000000000001}', 'Default Client Setting')
$SMSClientSettingsWithHINVData.Add('{00000000-0000-0000-0000-000000000003}', 'Heartbeat')

foreach ($clientSetting in $SMSClientSettings)
{
    # loading lazy properties to get HINV data
    $clientSetting = $clientSetting | Get-CimInstance 
    $HINVInventoryData = $clientSetting.AgentConfigurations | Where-Object {$_.AgentID -eq 15}
    if ($HINVInventoryData)
    {
        $SMSClientSettingsWithHINVData.Add($HINVInventoryData.InventoryReportID,$clientSetting.Name)
    }
}
Write-Verbose "$($SMSClientSettingsWithHINVData.count) client settings with hardware inventory settings found"


# select client setting inventory report ID
foreach($clientSettingKey in $SMSClientSettingsWithHINVData.keys)
{
    if ($SMSClientSettingsWithHINVData[$clientSettingKey] -eq $ClientSettingsName)
    {
        $clientsettingInventoryReportID = $clientSettingKey
    }
}

if (-NOT($clientsettingInventoryReportID))
{
    Write-Output "No client setting with hardware inventory data found with name: `"$ClientSettingsName`""
    exit
}
Write-Verbose "$($clientsettingInventoryReportID) selected report ID"
#endregion


#region Get all possible inventory classes for "show" or "export" mode
#$completeSMSInventoryClassesArrayList = New-Object system.collections.arraylist
[array]$SMSInventoryClasses = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "SELECT * FROM SMS_InventoryClass"

# normalize object for comparison
$SMSInventoryClassesArrayList = New-Object system.collections.arraylist
foreach ($InventoryClass in $SMSInventoryClasses)
{

    $InventoryClassExpanded = $InventoryClass | Select-Object -Property ClassName, Namespace, SMSClassID, SMSGroupName -ExpandProperty Properties
    foreach ($expandedItem in $InventoryClassExpanded)
    {
        
        $propertiesList = @('ClassName','ClassType','Namespace','SMSClassID','SMSGroupName','IsKey','PropertyName','SMSDeviceUri','Type','Units','Width' )
        $tmpObj2 = New-Object pscustomobject | Select-Object -Property $propertiesList
    
        foreach ($property in $propertiesList)
        {

            $tmpObj2."$property" = $expandedItem."$property"
        }
    
        if ($expandedItem.SMSClassID -ilike 'Microsoft*')
        {
            $tmpObj2.ClassType = 'Default'
        }
        else
        {
            $tmpObj2.ClassType = 'Custom'    
        }

        [void]$SMSInventoryClassesArrayList.Add($tmpObj2)
    }
}

Write-Verbose "$($SMSInventoryClassesArrayList.count) total HINV classes found"

# for faster searches
$SMSInventoryClassesArrayUniqueList = $SMSInventoryClassesArrayList | Select-Object -Property SMSClassID, ClassName, ClassType, Namespace, SMSGroupName -Unique

Write-Verbose "$($SMSInventoryClassesArrayUniqueList.count) unique total HINV classes"
#endregion


#region Get classes of selected client setting
[array]$SMSInventoryReports = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "SELECT * FROM SMS_InventoryReport where InventoryReportID = '$($clientsettingInventoryReportID)'"

Write-Verbose "$($SMSInventoryReports.count) class info for client setting"
$SMSInventoryReportsArrayList = New-Object system.collections.arraylist
$propertiesList = @('clientSettingsName','SMSGroupName','PropertyName','ClassType','ClassName','SMSClassID','Namespace','InventoryReportID')
foreach ($inventoryReport in $SMSInventoryReports)
{
    $inventoryReport = $inventoryReport | Get-CimInstance

    foreach ($inventoryReportClass in $inventoryReport.ReportClasses)
    {
        foreach ($PropertyName in $inventoryReportClass.ReportProperties)
        {
            
            $inventoryReportID = $inventoryReport.InventoryReportID
            $clientSettingsName = $SMSClientSettingsWithHINVData[$inventoryReportID]

            $tmpObj3 = New-Object pscustomobject | Select-Object -Property $propertiesList   
            $tmpObj3.clientSettingsName = $clientSettingsName
            $tmpObj3.InventoryReportID = $inventoryReportID
            $tmpObj3.SMSClassID = $inventoryReportClass.SMSClassID
            $tmpObj3.PropertyName = $PropertyName

            # adding additional Info to the object
            $classInfo = $SMSInventoryClassesArrayUniqueList.Where({$_.SMSClassID -eq $tmpObj3.SMSClassID})

            $tmpObj3.ClassName = $classInfo.ClassName
            $tmpObj3.Namespace = $classInfo.Namespace
            $tmpObj3.SMSGroupName = $classInfo.SMSGroupName
            

            if ($inventoryReportClass.SMSClassID -ieq 'System' -or $inventoryReportClass.SMSClassID -ieq 'MIFGroup')
            {
                $tmpObj3.ClassType = 'Default'
                #ignoring default MIF data
            }
            else
            {
                $tmpObj3.ClassType = $classInfo.ClassType
                
                [void]$SMSInventoryReportsArrayList.Add($tmpObj3)   
            }

        }    
    }
}
if ($cimSession){$cimSession | Remove-CimSession -ErrorAction SilentlyContinue}
Write-Verbose "$($SMSInventoryReportsArrayList.count) HINV items of client setting"
#endregion


#region Show data
# reducing object data to minimun to be able to compare data
$propertiesList = @('SMSGroupName','PropertyName')
$exportObj = $SMSInventoryReportsArrayList | Select-Object -Property $propertiesList

# show data
if ($OutputMode -eq "ShowData")
{
    $SMSInventoryClassesArrayList | Out-GridView -Title 'All available HINV classes'
    $SMSInventoryReportsArrayList | Out-GridView -Title "HINV Inventory Items in client setting: `"$($ClientSettingsName)`""
}
#endregion


#region Export data as csv
if ($OutputMode -eq "ExportAsCSV")
{
    $exportPathAndNameAll = "{0}\{1}-All-Available-HINV-Classes.csv" -f (Split-Path $scriptPathAndName -Parent), ($scriptName -replace ".ps1","")
    $SMSInventoryClassesArrayList | Export-Csv -Path $exportPathAndNameAll -NoTypeInformation -Delimiter ';' -Force

    $exportPathAndNamePerSetting = "{0}\{1}-{2}-HINV-Classes.csv" -f (Split-Path $scriptPathAndName -Parent), ($scriptName -replace ".ps1",""), $ClientSettingsNameClean
    $SMSInventoryReportsArrayList | Export-Csv -Path $exportPathAndNamePerSetting -NoTypeInformation -Delimiter ';' -Force
}
#endregion


#region Create new script file
# creating new script for current HINV client setting settings 
if ($OutputMode -eq "CreateScript")
{
    # create new script file first
    # name like: Compare-HINVClasses_Default-Client-Setting_20210411-1138.ps1
    $newScriptName = "{0}_{1}_{2}.ps1" -f ($scriptName -replace ".ps1",""), $ClientSettingsNameClean ,(Get-Date -Format 'yyyyMMdd-hhmm')
    $newFile = New-Item -Path (Split-Path $scriptPathAndName -Parent) -Name $newScriptName -ItemType File -Force

    # reading existing script and replacing classes for comparison
    $i = 0
    $referenceDataReplaced = $false
    foreach ($scriptLine in (Get-Content -Path $scriptPathAndName))
    {
        # replacing parameter value to be able to use the script in a ConfigMgr config item
        if ($scriptLine -match '\[string\]\$ClientSettingsName \=')
        {
            $parameterString = "{0}{1}{2}" -f '    [string]$ClientSettingsName = "', $ClientSettingsName, '",'
            $parameterString | Out-File -FilePath ($newFile.FullName) -Append -Encoding utf8
            $i++
        }
        elseif ($scriptLine -match '\$referenceData.add\(')
        {
            if (-NOT($referenceDataReplaced))
            {
                $referenceDataReplaced = $true
                # replacing data for comparison
                $exportObj | Sort-Object | ForEach-Object {
                    # output will look like this: 
                    # $referenceData.add("Processor;NumberOfLogicalProcessors","1")
                    $outputString = "{0}(`"{1};{2}`",`"1`")" -f '$referenceData.add', ($_.SMSGroupName), ($_.PropertyName)
                    $outputString | Out-File -FilePath ($newFile.FullName) -Append -Encoding utf8
                }              
            }
            $i++
        }
        else
        {
            if ($i -eq 0)
            {
                # starting file
                $scriptLine | Out-File -FilePath ($newFile.FullName) -Force -Encoding utf8
            }
            else
            {
                $scriptLine | Out-File -FilePath ($newFile.FullName) -Append -Encoding utf8
            }            
            $i++
        }
   
    } 

}
#endregion


#region Compare data for compliance checks
if ($OutputMode -eq "CompareData")
{
    # had some issues with compare-object. Using hashtables instead. 
    $compareResultArrayList = New-Object system.collections.arraylist
    $differenceData = @{}
    $exportObj | ForEach-Object {

        $outputString = "{0};{1}" -f ($_.SMSGroupName), ($_.PropertyName)
        $differenceData.Add($outputString,"1")
        # Test if the settings has been added
        if (-NOT ($referenceData[$outputString]))
        {
            $tmpObj = New-Object pscustomobject | Select-Object SMSGroupName, PropertyName, Action
            $tmpArray = $outputString -split ';'
            $tmpObj.SMSGroupName = $tmpArray[0]
            $tmpObj.PropertyName = $tmpArray[1]
            $tmpObj.Action = 'Added'
            [void]$compareResultArrayList.Add($tmpObj)
        }
    }
    
    # Test the other way around to see if any settings have been removed
    $referenceData.GetEnumerator() | ForEach-Object {
    
        if (-NOT ($differenceData[$_.Key]))
        {
            $tmpObj = New-Object pscustomobject | Select-Object SMSGroupName, PropertyName, Action
            $tmpArray = $_.Key -split ';'
            $tmpObj.SMSGroupName = $tmpArray[0]
            $tmpObj.PropertyName = $tmpArray[1]
            $tmpObj.Action = 'Removed'
            [void]$compareResultArrayList.Add($tmpObj)

        }
    }
    
    if ($compareResultArrayList)
    {
        Write-Verbose "$($compareResultArrayList.count) compare results"
        if ([Security.Principal.WindowsIdentity]::GetCurrent().Name -ieq 'NT AUTHORITY\SYSTEM')
        {
            # formatting output in case the script is running in system context, for readability in COnfigMgr config item. 
            $compareResultArrayList | Sort-Object -Property SMSGroupName | Format-Table -HideTableHeaders @{Label="TMP"; Expression={"{0};{1};{2}" -f $_.SMSGroupName, $_.PropertyName, $_.Action }}
        }
        else
        {
            $compareResultArrayList | Sort-Object -Property SMSGroupName
        }
        
    }
    else
    {
        Write-Output 'Compliant'
    }

}
#endregion