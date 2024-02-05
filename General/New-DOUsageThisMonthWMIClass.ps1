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
.Synopsis
    Script to get data shown via Get-DeliveryOptimizationPerfSnapThisMonth from registry

.DESCRIPTION
    Script to get data shown via Get-DeliveryOptimizationPerfSnapThisMonth from registry
    Using StdRegProv to get data direcly via ConfigMgr hardware ivnentory does not seem to work properly
    The script can be used via ConfigMgr config item to write DeliveryOptimization Perf Data of This Month to custom WMI class
    Custom WMI class can then be inventoried via hardware inventory

.EXAMPLE
    .\New-DOUsageThisMonthWMIClass.ps1

.EXAMPLE
    .\New-DOUsageThisMonthWMIClass.ps1 -WMIClassName 'Custom_DeliveryOptimizationUsage'

.LINK
    https://github.com/jonasatgit/scriptrepo

#>
[CmdletBinding()]
param
(
    $WMIRootPath = 'root\cimv2',
    $WMIClassName = 'Custom_DeliveryOptimizationUsage'
)


#region New-CustomWmiClass
<#
.Synopsis
    New-CustomWmiClass will create a new custom WMI class to store offlien update scan data in it (Properties are automatically added)
.DESCRIPTION
    New-CustomWmiClass will create a new custom WMI class to store offlien update scan data in it (Properties are automatically added)
.EXAMPLE
    New-CustomWmiClass -ClassName 'MyCustomClass' # will create class in root\comv2 
.EXAMPLE
    New-CustomWmiClass -RootPath 'root\MyCustomNamespace' -ClassName 'MyCustomClass' # will create class in root\MyCustomNamespace
#>
function New-CustomWmiClass
{
    [CmdletBinding()]
    Param
    (
        # Root namespace to store custom namespace in. If not set root\cimv2 will be used.
        [Parameter(Mandatory=$false,HelpMessage = "Root namespace to store custom class in. If not set root\cimv2 will be used.")]
        $RootPath='root\cimv2',

        # Root namespace to store custom namespace in. If not set root\cimv2 will be used.
        [Parameter(Mandatory=$true,HelpMessage = "Name of custom WMI class.")]
        [string]$ClassName

    )
    
    $newWMIClass = New-Object System.Management.ManagementClass($RootPath, [String]::Empty, $null); 

																								   

    $newWMIClass["__CLASS"] = $ClassName 
    # cim types: https://msdn.microsoft.com/en-us/library/system.management.cimtype(v=vs.110).aspx
    $newWMIClass.Qualifiers.Add("Static", $true)
    $newWMIClass.Properties.Add("KeyName", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["KeyName"].Qualifiers.Add("key", $true)
    $newWMIClass.Properties["KeyName"].Qualifiers.Add("read", $true)

    $newWMIClass.Properties.Add("MonthStartDate", [System.Management.CimType]::DateTime, $false)
    $newWMIClass.Properties["MonthStartDate"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["MonthStartDate"].Qualifiers.Add("Description", "Delivery Optimization status start date")
    
    $newWMIClass.Properties.Add("UploadMonthlyInternetBytes", [System.Management.CimType]::UInt64, $false)
    $newWMIClass.Properties["UploadMonthlyInternetBytes"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["UploadMonthlyInternetBytes"].Qualifiers.Add("Description", "Delivery Optimization UploadMonthlyInternetBytes coming from HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage|UploadMonthlyInternetBytes")

    $newWMIClass.Properties.Add("UploadMonthlyLanBytes", [System.Management.CimType]::UInt64, $false)
    $newWMIClass.Properties["UploadMonthlyLanBytes"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["UploadMonthlyLanBytes"].Qualifiers.Add("Description", "Delivery Optimization UploadMonthlyLanBytes coming from HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage|UploadMonthlyLanBytes")

    $newWMIClass.Properties.Add("DownloadMonthlyCdnBytes", [System.Management.CimType]::UInt64, $false)
    $newWMIClass.Properties["DownloadMonthlyCdnBytes"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["DownloadMonthlyCdnBytes"].Qualifiers.Add("Description", "Delivery Optimization DownloadMonthlyCdnBytes coming from HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage|DownloadMonthlyCdnBytes")

    $newWMIClass.Properties.Add("DownloadMonthlyCacheHostBytes", [System.Management.CimType]::UInt64, $false)
    $newWMIClass.Properties["DownloadMonthlyCacheHostBytes"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["DownloadMonthlyCacheHostBytes"].Qualifiers.Add("Description", "Delivery Optimization DownloadMonthlyCacheHostBytes coming from HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage|DownloadMonthlyCacheHostBytes")

    $newWMIClass.Properties.Add("DownloadMonthlyLanBytes", [System.Management.CimType]::UInt64, $false)
    $newWMIClass.Properties["DownloadMonthlyLanBytes"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["DownloadMonthlyLanBytes"].Qualifiers.Add("Description", "Delivery Optimization DownloadMonthlyLanBytes coming from HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage|DownloadMonthlyLanBytes")

    $newWMIClass.Properties.Add("DownloadMonthlyInternetBytes", [System.Management.CimType]::UInt64, $false)
    $newWMIClass.Properties["DownloadMonthlyInternetBytes"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["DownloadMonthlyInternetBytes"].Qualifiers.Add("Description", "Delivery Optimization DownloadMonthlyInternetBytes coming from HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage|DownloadMonthlyInternetBytes")

    $newWMIClass.Properties.Add("DownloadMonthlyRateFrBps", [System.Management.CimType]::UInt64, $false)
    $newWMIClass.Properties["DownloadMonthlyRateFrBps"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["DownloadMonthlyRateFrBps"].Qualifiers.Add("Description", "Delivery Optimization DownloadMonthlyRateFrBps coming from HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage|DownloadMonthlyRateFrBps")

    $newWMIClass.Properties.Add("DownloadMonthlyRateBkBps", [System.Management.CimType]::UInt64, $false)
    $newWMIClass.Properties["DownloadMonthlyRateBkBps"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["DownloadMonthlyRateBkBps"].Qualifiers.Add("Description", "Delivery Optimization DownloadMonthlyRateBkBps coming from HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage|DownloadMonthlyRateBkBps")

    $newWMIClass.Properties.Add("MonthlyUploadRestriction", [System.Management.CimType]::UInt64, $false)
    $newWMIClass.Properties["MonthlyUploadRestriction"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["MonthlyUploadRestriction"].Qualifiers.Add("Description", "Delivery Optimization MonthlyUploadRestriction coming from HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage|MonthlyUploadRestriction")
    
    [void]$newWMIClass.Put()

    return (Get-WmiObject -Namespace $RootPath -Class $ClassName -List)

}
#endregion



if (-NOT (Get-WmiObject -Namespace $WMIRootPath -Class $WMIClassName -List))
{
    New-CustomWmiClass -RootPath $WMIRootPath -ClassName $WMIClassName | Out-Null
}


[int32]$MonthID = 0
[int64]$UploadMonthlyInternetBytes = 0
[int64]$UploadMonthlyLanBytes = 0
[int64]$DownloadMonthlyCdnBytes = 0
[int64]$DownloadMonthlyCacheHostBytes = 0
[int64]$DownloadMonthlyLanBytes = 0
[int64]$DownloadMonthlyInternetBytes = 0
[int64]$DownloadMonthlyRateFrBps = 0
[int64]$DownloadMonthlyRateBkBps = 0
[int64]$MonthlyUploadRestriction = 0


try{[int32]$MonthID = Get-ItemPropertyValue -Path "registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage" -Name 'MonthID' -ErrorAction SilentlyContinue}catch{}
try{[int64]$UploadMonthlyInternetBytes = Get-ItemPropertyValue -Path "registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage" -Name 'UploadMonthlyInternetBytes' -ErrorAction SilentlyContinue}catch{}
try{[int64]$UploadMonthlyLanBytes = Get-ItemPropertyValue -Path "registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage" -Name 'UploadMonthlyLanBytes' -ErrorAction SilentlyContinue}catch{}
try{[int64]$DownloadMonthlyCdnBytes = Get-ItemPropertyValue -Path "registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage" -Name 'DownloadMonthlyCdnBytes' -ErrorAction SilentlyContinue}catch{}
try{[int64]$DownloadMonthlyCacheHostBytes = Get-ItemPropertyValue -Path "registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage" -Name 'DownloadMonthlyCacheHostBytes' -ErrorAction SilentlyContinue}catch{}
try{[int64]$DownloadMonthlyLanBytes = Get-ItemPropertyValue -Path "registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage" -Name 'DownloadMonthlyLanBytes' -ErrorAction SilentlyContinue}catch{}
try{[int64]$DownloadMonthlyInternetBytes = Get-ItemPropertyValue -Path "registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage" -Name 'DownloadMonthlyInternetBytes' -ErrorAction SilentlyContinue}catch{}
try{[int64]$DownloadMonthlyRateFrBps = Get-ItemPropertyValue -Path "registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage" -Name 'DownloadMonthlyRateFrBps' -ErrorAction SilentlyContinue}catch{}
try{[int64]$DownloadMonthlyRateBkBps = Get-ItemPropertyValue -Path "registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage" -Name 'DownloadMonthlyRateBkBps' -ErrorAction SilentlyContinue}catch{}
try{[int64]$MonthlyUploadRestriction = Get-ItemPropertyValue -Path "registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Usage" -Name 'MonthlyUploadRestriction' -ErrorAction SilentlyContinue}catch{}


# remove class entries before writing new data
Get-WmiObject Custom_DeliveryOptimizationUsage -ErrorAction SilentlyContinue | Remove-WmiObject

# Create new class entry with latest data
$doStartDate = [Management.ManagementDateTimeConverter]::ToDmtfDateTime((Get-Date -Month $MonthID -Day 1))

# create wmi entry for failed scan
$classEntry = @{KeyName="DeliveryOptimizationUsage";
    MonthStartDate=$doStartDate
    UploadMonthlyInternetBytes = [int64]$UploadMonthlyInternetBytes
    UploadMonthlyLanBytes = [int64]$UploadMonthlyLanBytes
    DownloadMonthlyCdnBytes = [int64]$DownloadMonthlyCdnBytes
    DownloadMonthlyCacheHostBytes = [int64]$DownloadMonthlyCacheHostBytes
    DownloadMonthlyLanBytes = [int64]$DownloadMonthlyLanBytes
    DownloadMonthlyInternetBytes = [int64]$DownloadMonthlyInternetBytes
    DownloadMonthlyRateFrBps = [int64]$DownloadMonthlyRateFrBps
    DownloadMonthlyRateBkBps = [int64]$DownloadMonthlyRateBkBps
    MonthlyUploadRestriction = [int64]$MonthlyUploadRestriction

    }
Set-WmiInstance -Path "\\.\$($WMIRootPath):$($WMIClassName)" -Arguments $classEntry | Out-Null
