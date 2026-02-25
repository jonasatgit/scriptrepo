<#
.Synopsis
    Script to create custom WMI classes and store Secure Boot status and event count data in it.
    
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

    This script will create two custom WMI classes and store Secure Boot status and event count data in it. 
    The script can be used to easily collect this data for inventory purposes with tools like Microsoft Endpoint Configuration Manager (ConfigMgr/SCCM) or Microsoft Intune. 
    The script can be run on demand, scheduled as a task or deployed with ConfigMgr or Intune. 
    The script will check if the custom WMI classes already exist and if so, it will clear the existing data to make room for new data. 
    If the classes do not exist, they will be created automatically.

.PARAMETER WMISecureBootStatusClassName
    Name of the custom WMI class to store Secure Boot status data. 

.PARAMETER WMISecureBootEventsClassName
    Name of the custom WMI class to store Secure Boot event count data. 

.PARAMETER WMIRootPath
    Root WMI namespace path to store the custom WMI classes in. Default is "root\cimv2".

.PARAMETER DeleteCustomWMIClasses
    If set, the script will delete the custom WMI classes specified in the parameters and exit. This can be used to clean up the custom WMI classes if they are no longer needed.
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true,HelpMessage = "Name of the custom WMI class to store Secure Boot status data.")]
    [string]$WMISecureBootStatusClassName,

    [Parameter(Mandatory=$true,HelpMessage = "Name of the custom WMI class to store Secure Boot event count data.")]
    [string]$WMISecureBootEventsClassName,

    [Parameter(Mandatory=$false,HelpMessage = "Root WMI namespace path to store the custom WMI classes in. Default is 'root\cimv2'.")]
    [string]$WMIRootPath = "root\cimv2",

    [Parameter(Mandatory=$false,HelpMessage = "If set, the script will delete the custom WMI classes specified in the parameters and exit.")]
    [switch]$DeleteCustomWMIClasses
)


#region Test-WMINamespace
<#
.Synopsis
    Test-WMINamespace will validate if a WMI namespace path exists
.DESCRIPTION
    Test-WMINamespace will validate if a WMI namespace path exists
.EXAMPLE
    Test-WMINamespace -WMIRootPath "root\cimv2"
#>
function Test-WMINamespace
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,HelpMessage = "Provide a WMI namespace path to check its existens. Do not use root use root\cimv2 or any other path instead")]
        [string]$WMIRootPath
    )    

    $WMIRootPathSplit = Split-Path $WMIRootPath
    $WMINamespaceName = Split-Path $WMIRootPath -Leaf

    if(-not $WMIRootPathSplit)
    {
        # do not use root
        return $false
    }
    
    if(Get-WmiObject -Namespace $WMIRootPathSplit -Query "select * from __Namespace where Name = '$($WMINamespaceName)'" -ErrorAction SilentlyContinue)
    {
        return $true
    }
    else
    {
        return $false
    }
}
#endregion


#region New-SecureBootEventsWmiClass
<#
.Synopsis
    New-SecureBootEventsWmiClass will create a new custom WMI class to store offline update scan data in it (Properties are automatically added)
.DESCRIPTION
    New-SecureBootEventsWmiClass will create a new custom WMI class to store offline update scan data in it (Properties are automatically added)
.EXAMPLE
    New-SecureBootEventsWmiClass -ClassName 'MyCustomClass' # will create class in root\comv2 
.EXAMPLE
    New-SecureBootEventsWmiClass -RootPath 'root\MyCustomNamespace' -ClassName 'MyCustomClass' # will create class in root\MyCustomNamespace
#>
function New-SecureBootEventsWmiClass
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
    
    $newWMIClass.Properties.Add("EventID", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["EventID"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["EventID"].Qualifiers.Add("Description", "ID of the event")

    $newWMIClass.Properties.Add("EventCount", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["EventCount"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["EventCount"].Qualifiers.Add("Description", "Count of events with the same event ID")

    $newWMIClass.Properties.Add("EventLatest", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["EventLatest"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["EventLatest"].Qualifiers.Add("Description", "Identifies the latest event with the same event ID")

    [void]$newWMIClass.Put()

    return (Get-WmiObject -Namespace $RootPath -Class $ClassName -List)

}
#endregion


#region New-SecureBootStatusWmiClass
<#
.Synopsis
    New-SecureBootStatusWmiClass will create a new custom WMI class to store offline update scan data in it (Properties are automatically added)
.DESCRIPTION
    New-SecureBootStatusWmiClass will create a new custom WMI class to store offline update scan data in it (Properties are automatically added)
.EXAMPLE
    New-SecureBootStatusWmiClass -ClassName 'MyCustomClass' # will create class in root\comv2 
.EXAMPLE
    New-SecureBootStatusWmiClass -RootPath 'root\MyCustomNamespace' -ClassName 'MyCustomClass' # will create class in root\MyCustomNamespace
#>
function New-SecureBootStatusWmiClass
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
    
    $newWMIClass.Properties.Add("SecureBootStatus", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["SecureBootStatus"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["SecureBootStatus"].Qualifiers.Add("Description", "Secure Boot status of the system.")

    $newWMIClass.Properties.Add("UEFICA2023Status", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["UEFICA2023Status"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["UEFICA2023Status"].Qualifiers.Add("Description", "Windows UEFI CA 2023 Status from registry key HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing\UEFICA2023Status")

    $newWMIClass.Properties.Add("UEFICA2023Error", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["UEFICA2023Error"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["UEFICA2023Error"].Qualifiers.Add("Description", "UEFI CA 2023 Error from registry key HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing\UEFICA2023Error")

    $newWMIClass.Properties.Add("UEFICA2023ErrorEvent", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["UEFICA2023ErrorEvent"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["UEFICA2023ErrorEvent"].Qualifiers.Add("Description", "UEFI CA 2023 Error Event from registry key HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing\UEFICA2023ErrorEvent")

    $newWMIClass.Properties.Add("BucketID", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["BucketID"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["BucketID"].Qualifiers.Add("Description", "Bucket ID of the event if it exists. This is used for known issues with a published bucket ID in the event description. If no bucket ID is found, this property will be empty.")

    $newWMIClass.Properties.Add("ConfidenceLevel", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["ConfidenceLevel"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["ConfidenceLevel"].Qualifiers.Add("Description", "Confidence level of the event if it exists. This is used for known issues with a published confidence level in the event description. If no confidence level is found, this property will be empty.")     
    
    [void]$newWMIClass.Put()

    return (Get-WmiObject -Namespace $RootPath -Class $ClassName -List)

}
#endregion



#region MAIN SCRIPT LOGIC

# 1. Check if WMI namespace exists, if not exit with error code
if(-not (Test-WMINamespace -WMIRootPath $WMIRootPath))
{
    exit -1    
}


# If the delete switch is set, delete the custom WMI classes and exit
if($DeleteCustomWMIClasses)
{
    Get-WmiObject -Namespace $WMIRootPath -Class $WMISecureBootStatusClassName -List -ErrorAction SilentlyContinue | Remove-WmiObject -ErrorAction SilentlyContinue
    Get-WmiObject -Namespace $WMIRootPath -Class $WMISecureBootEventsClassName -List -ErrorAction SilentlyContinue | Remove-WmiObject -ErrorAction SilentlyContinue
    return
}


# Clear class to make room for new entries or create new if not exists
$customWMIClass = Get-WmiObject -Namespace $WMIRootPath -Class $WMISecureBootStatusClassName -List -ErrorAction SilentlyContinue
if($customWMIClass)
{
    Get-WmiObject -Namespace $WMIRootPath -Class $WMISecureBootStatusClassName | Remove-WmiObject
}
else
{
    $null = New-SecureBootStatusWmiClass -RootPath $WMIRootPath -ClassName $WMISecureBootStatusClassName #-ErrorAction SilentlyContinue
}

# Additional classes for events
$customWMIClass = Get-WmiObject -Namespace $WMIRootPath -Class $WMISecureBootEventsClassName -List -ErrorAction SilentlyContinue
if($customWMIClass)
{
    Get-WmiObject -Namespace $WMIRootPath -Class $WMISecureBootEventsClassName | Remove-WmiObject
}
else
{
    $null = New-SecureBootEventsWmiClass -RootPath $WMIRootPath -ClassName $WMISecureBootEventsClassName #-ErrorAction SilentlyContinue
}


# Gather secure boot status and event data
$secureBootEnabled = $null
$uefica2023Status = "unknown"
$uefica2023Error = "unknown"
$uefica2023ErrorEvent = "unknown"
$bucketID = "unknown"
$confidenceLevel = "unknown"

try 
{
    $secureBootEnabled = Confirm-SecureBootUEFI -ErrorAction Stop
} 
catch 
{
    # Try registry fallback
    try 
    {
        $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -Name UEFISecureBootEnabled -ErrorAction Stop
        $secureBootEnabled = [bool]$regValue.UEFISecureBootEnabled
    } 
    catch{}
}


# UEFICA2023Status
try 
{
    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing" -Name UEFICA2023Status -ErrorAction Stop
    $uefica2023Status = $regValue.UEFICA2023Status
} 
catch{}

# UEFICA2023Error
try
{
    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing" -Name UEFICA2023Error -ErrorAction Stop
    $uefica2023Error = $regValue.UEFICA2023Error
} 
catch{}

# UEFICA2023ErrorEvent
try 
{
    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing" -Name UEFICA2023ErrorEvent -ErrorAction Stop
    $uefica2023ErrorEvent = $regValue.UEFICA2023ErrorEvent
} 
catch{}


# Get latest Secure Boot events (1801 and 1808) to extract bucket ID and confidence level if available. 
$allEventIds = @(1801, 1808)
[array]$eventsList = @(Get-WinEvent -FilterHashtable @{LogName='System'; ID=$allEventIds} -MaxEvents 20 -ErrorAction SilentlyContinue)

if ($eventsList.Count -eq 0) 
{
    $bucketID = "No Secure Boot events (1801/1808) found in System log"
}
else 
{
   $latestEvent = $eventsList | Sort-Object TimeCreated -Descending | Select-Object -First 1
        # 17. BucketID - Extracted from Event 1801/1808
    if ($null -ne $latestEvent -and $null -ne $latestEvent.Message) 
    {
        if ($latestEvent.Message -match 'BucketId:\s*(.+)') 
        {
            $bucketId = $matches[1].Trim()
        } 
        else 
        {
            $bucketId = "BucketId not found in event message"
        }
    }

    # 18. Confidence - Extracted from Event 1801/1808
    if ($null -ne $latestEvent -and $null -ne $latestEvent.Message) 
    {
        if ($latestEvent.Message -match 'BucketConfidenceLevel:\s*(.+)') 
        {
            $confidenceLevel = $matches[1].Trim()            
        } 
        else 
        {
            $confidenceLevel = "Confidence level not found in event message"
        }
    }
}

# Write data to WMI class
$classEntry = @{KeyName="SecureBootStatus";
    SecureBootStatus = if($null -eq $secureBootEnabled){'Unknown'}else{if($secureBootEnabled) { "Enabled" } else { "Disabled" }}  #if($secureBootEnabled) { "Enabled" } else { "Disabled" }  else { "Unknown" };
    UEFICA2023Status = $uefica2023Status;
    UEFICA2023Error = $uefica2023Error;
    UEFICA2023ErrorEvent = $uefica2023ErrorEvent;
    BucketID = $bucketID;
    ConfidenceLevel = $confidenceLevel
}
Set-WmiInstance -Path "\\.\$($WMIRootPath):$($WMISecureBootStatusClassName)" -Arguments $classEntry | Out-Null


# Get Secure Boot events from the System event log and write event count data to WMI class. 
# This can be used to track if there are any new events related to Secure Boot that might indicate a change in status or a known issue. 
# The script will look for specific event IDs related to Secure Boot and count the number of occurrences of each event ID. 
# It will also identify the latest event for each event ID to help with troubleshooting and monitoring.
$allEventIds = @(1032, 1033, 1034, 1036, 1037, 1043, 1044, 1045, 1795, 1796, 1797, 1798, 1799, 1800, 1801, 1802, 1803, 1808)

[array]$eventList = @(Get-WinEvent -FilterHashtable @{LogName='System'; ID=$allEventIds} -MaxEvents 100 -ErrorAction Stop)

if ($eventList.count -eq 0)
{
    $classEntry = @{KeyName="SecureBootEvent_0";
        EventID = 0;
        EventCount = 0;
        EventLatest = 0
    }
    Set-WmiInstance -Path "\\.\$($WMIRootPath):$($WMISecureBootEventsClassName)" -Arguments $classEntry | Out-Null
}
else 
{
    $eventList | Group-Object -Property Id | Select-Object Name, Count | ForEach-Object {

        $latestEvent = $eventList | Select-Object -First 1

        $classEntry = @{KeyName="SecureBootEvent_$($_.Name)";
            EventID = $_.Name;
            EventCount = $_.Count;
            EventLatest = if($latestEvent.Id -eq $_.Name) { 1 } else { 0 }
        }
        Set-WmiInstance -Path "\\.\$($WMIRootPath):$($WMISecureBootEventsClassName)" -Arguments $classEntry | Out-Null
    }
}

Write-Output "Script done"
#endregion
