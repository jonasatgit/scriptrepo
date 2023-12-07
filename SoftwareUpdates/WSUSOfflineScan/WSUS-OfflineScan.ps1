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
    Script to run an offline update scan with the wsuscn2.cab file. Result will be stored in custom WMI class

.DESCRIPTION
    The script will create a new custom WMI class or re-use an existing one with the same name.
    It will then run an WSUS offline update scan and store the result in the WMI class.
    The class can then be inventoried using ConfigMgr Hardware Inventory. 
    Its main purpose is to find gaps in the update deployment process and to be able to identify missing updates for disabled products (disabled in WSUS)

    The scripts requires the "wsusscn2.cab" file and a "versioninfo.txt" with a date string in the following format as content: yyyyMMdd
    Both files can be created using the additional script: "Download-Wsusscn2CabFile.ps1"

.EXAMPLE
    .\WSUS-OfflineScan.ps1
.EXAMPLE
    .\WSUS-OfflineScan.ps1 -WMIClassName "Custom_OfflineUpdateScan"
.EXAMPLE
    .\WSUS-OfflineScan.ps1 -Delete
.EXAMPLE
    .\WSUS-OfflineScan.ps1 -ForceHardwareInventory
.PARAMETER WMIRootPath
    Root path under witch the custom class needs to be created
.PARAMETER WMIClassName
    Name of the custom WMI class to store offline update scan results in
.PARAMETER Logpath
    Logfile path. Default=C:\Windows\Temp
.PARAMETER Delete
    Switch parameter to delete the custom class on a system
.PARAMETER ForceHardwareInventory
    Switch parameter to force a ConfigMgr client Hardware Inventory immediately after writing data to the custom class
.LINK
    https://github.com/jonasatgit/scriptrepo
#>
[CmdletBinding()]
param
(
    # WMI root path to store WMI class in
    [Parameter(Mandatory=$false)]
    [string]$WMIRootPath = 'root\cimv2',

    # custom WMI class to store script results in
    [Parameter(Mandatory=$false)]
    [string]$WMIClassName = "Custom_OfflineUpdateScan",

    # path to store logfile in
    [Parameter(Mandatory=$false)]
    [string]$Logpath = "$env:systemroot\Temp",

    # used to delete the WMi class
    [Parameter(Mandatory=$false)]
    [switch]$Delete,
    
    # to run hardware inventory at the end of the script
    [Parameter(Mandatory=$false)]
    [switch]$ForceHardwareInventory
)

#region Write-CMTraceLog
<#
.Synopsis
    Write-CMTraceLog will writea logfile readable via cmtrace.exe
 
.DESCRIPTION
    Write-CMTraceLog will writea logfile readable via cmtrace.exe (https://www.bing.com/search?q=cmtrace.exe)
.EXAMPLE
    Write-CMTraceLog -Message "file deleted" => will log to the current directory and will use the scripts name as logfile name
#>
function Write-CMTraceLog
{
    [CmdletBinding()]
    Param
    (
        #Path to the log file
        [parameter(Mandatory=$false)]
        [String]$LogFile="$(Split-Path $PSCommandPath)\$(Split-Path $PSCommandPath -Leaf).log",

        #The information to log
        [parameter(Mandatory=$true)]
        [String]$Message,

        #The source of the error
        [parameter(Mandatory=$false)]
        [String]$Component=(Split-Path $PSCommandPath -Leaf),

        #severity (1 - Information, 2- Warning, 3 - Error) for better reading purposes this variable as string
        [parameter(Mandatory=$false)]
        [ValidateSet("Information","Warning","Error")]
        [String]$Severity="Information",

        # write to console only
        [Parameter(Mandatory=$false)]
        [switch]$ConsoleOutputOnly
    )


    # save severity in single for cmtrace severity
    [single]$cmSeverity=1
    switch ($Severity) 
        { 
            "Information" {$cmSeverity=1; $color = [System.ConsoleColor]::Green; break} 
            "Warning" {$cmSeverity=2; $color = [System.ConsoleColor]::Yellow; break} 
            "Error" {$cmSeverity=3; $color = [System.ConsoleColor]::Red; break} 
        }
 
 
    $console = $Message

    If($ConsoleOutputOnly)
    {

        Write-Host $console -ForegroundColor $color
    }
    else
    {
        Write-Host $console -ForegroundColor $color
    
        #Obtain UTC offset
        $DateTime = New-Object -ComObject WbemScripting.SWbemDateTime 
        $DateTime.SetVarDate($(Get-Date))
        $UtcValue = $DateTime.Value
        $UtcOffset = $UtcValue.Substring(21, $UtcValue.Length - 21)

        #Create the line to be logged
        $LogLine =  "<![LOG[$Message]LOG]!>" +`
                    "<time=`"$(Get-Date -Format HH:mm:ss.mmmm)$($UtcOffset)`" " +`
                    "date=`"$(Get-Date -Format M-d-yyyy)`" " +`
                    "component=`"$Component`" " +` 
                    "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
                    "type=`"$cmSeverity`" " +`
                    "thread=`"$PID`" " +`
                    "file=`"`">"

        #Write the line to the passed log file
        $LogLine | Out-File -Append -Encoding UTF8 -FilePath $LogFile
    }

}
#endregion


#region Check-WMINamespace
<#
.Synopsis
    Check-WMINamespace will validate if a WMI namespace path exists
.DESCRIPTION
    Check-WMINamespace will validate if a WMI namespace path exists
.EXAMPLE
    Check-WMINamespace -WMIRootPath "root\cimv2"
#>
function Check-WMINamespace
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


#region Rollover-Logfile
<#
.Synopsis
    Rollover-Logfile will rename the logfile with ".lo_" as prefix
.DESCRIPTION
    Rollover-Logfile will rename the logfile with ".lo_" as prefix. Default max file size is 1MB
.EXAMPLE
    Rollover-Logfile will -Logfile "C:\windows\logs\test.log"
.EXAMPLE
    Rollover-Logfile will -Logfile "C:\windows\logs\test.log" -MaxFileSizeKB 2048
#>
Function Rollover-Logfile
{
    [CmdletBinding()]
    Param
    (
        #Path to test
        [parameter(Mandatory=$true)]
        [string]$Logfile,
      
        #max Size in KB
        [parameter(Mandatory=$false)]
        [int]$MaxFileSizeKB = 1024
    )


    if(Test-Path $Logfile){
        $getLogfile = Get-Item $logFile
        $logfileSize = $getLogfile.Length/1024
        $newName = ($getLogfile.BaseName)
        $newName += ".lo_"
        $newLogFile = "$($getLogfile.Directory)\$newName"

        if($logfileSize -gt $MaxFileSizeKB){
            if(Test-Path $newLogFile){
                #need to delete old file first
                Remove-Item -Path $newLogFile -Force -ErrorAction SilentlyContinue
            }
            Rename-Item -Path $logFile -NewName $newName -Force -ErrorAction SilentlyContinue
        }
    }
}
#endregion


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
    
    $newWMIClass.Properties.Add("ScriptCabFileVersion", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["ScriptCabFileVersion"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["ScriptCabFileVersion"].Qualifiers.Add("Description", "Custom version of cabfile")

    $newWMIClass.Properties.Add("ScriptRunTimeSec", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["ScriptRunTimeSec"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["ScriptRunTimeSec"].Qualifiers.Add("Description", "Total script runtime in seconds")

    $newWMIClass.Properties.Add("ScriptStartTime", [System.Management.CimType]::DateTime, $false)
    $newWMIClass.Properties["ScriptStartTime"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["ScriptStartTime"].Qualifiers.Add("Description", "Time the script was started")

    $newWMIClass.Properties.Add("MissingUpdates", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["MissingUpdates"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["MissingUpdates"].Qualifiers.Add("Description", "Count of missing updates")

    $newWMIClass.Properties.Add("UpdateTitle", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["UpdateTitle"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["UpdateTitle"].Qualifiers.Add("Description", "Update title")

    $newWMIClass.Properties.Add("UpdateKB", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["UpdateKB"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["UpdateKB"].Qualifiers.Add("Description", "KB article ID like 123456 without KB as prefix")

    $newWMIClass.Properties.Add("UpdateRevision", [System.Management.CimType]::UInt32, $false)
    $newWMIClass.Properties["UpdateRevision"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["UpdateRevision"].Qualifiers.Add("Description", "Revision number of update")

    $newWMIClass.Properties.Add("UpdateID", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["UpdateID"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["UpdateID"].Qualifiers.Add("Description", "ID of update and SCCM CI_UniqueID")
    
    [void]$newWMIClass.Put()

    return (Get-WmiObject -Namespace $RootPath -Class $ClassName -List)

}
#endregion


#region Intialize script
$ScriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$WSUSCABfilePath = '{0}\wsusscn2.cab' -f $ScriptPath
$WSUSCABfileInfoPath = '{0}\wsusscn2-versioninfo.txt' -f $ScriptPath
$CabVersion = Get-Content -Path $WSUSCABfileInfoPath -TotalCount 1 -ErrorAction SilentlyContinue

$ScriptName = $MyInvocation.MyCommand.Name
$LogPath = '{0}\{1}.log' -f $LogPath, $ScriptName

$ScriptStopwatch = New-Object System.Diagnostics.Stopwatch
$ScriptStopwatch.Start()
$ScriptStartTime = Get-Date
$ScriptStartTimeDMTF = [Management.ManagementDateTimeConverter]::ToDmtfDateTime($ScriptStartTime)

Write-CMTraceLog -Message "Rollover Logfile if needed $Logpath" -ConsoleOutputOnly
Rollover-Logfile -Logfile $Logpath

Write-CMTraceLog -Message "Script started: $ScriptName" -LogFile $Logpath
#endregion


#region remove class if "Delete" is set
if($Delete)
{
    Write-CMTraceLog -Message "Delete is set. Will delete: $($WMIRootPath):$($WMIClassName)" -LogFile $Logpath
    # remove custom class
    $customWMIClass = Get-WmiObject -Namespace $WMIRootPath -Class $WMIClassName -List -ErrorAction SilentlyContinue
    if($customWMIClass)
    {
        $customWMIClass | Remove-WmiObject -ErrorAction SilentlyContinue
    }
    Write-CMTraceLog -Message "End script" -LogFile $Logpath
    Exit 0        
}
#endregion


#region Prereq check
Write-CMTraceLog -Message "Will check script prerequisites..." -LogFile $Logpath
if(-NOT $CabVersion -or ((Test-Path $WSUSCABfilePath) -eq $false))
{
    Write-CMTraceLog -Message "WSUS CAB file or info file not found: $($WSUSCABfileInfoPath) | $($WSUSCABfilePath)" -Severity Error -LogFile $Logpath
    Write-CMTraceLog -Message "Stopping script" -LogFile $Logpath
    exit -1 
}

if(-not (Check-WMINamespace -WMIRootPath $WMIRootPath))
{
    Write-CMTraceLog -Message "WMI Namespace not found or not valid: $($WMIRootPath)" -Severity Error -LogFile $Logpath
    Write-CMTraceLog -Message "Stopping script" -LogFile $Logpath
    exit -1    
}
Write-CMTraceLog -Message "Prerequisites okay" -LogFile $Logpath

#endregion


#region clear class to make room for new entries or create new if not exists
Write-CMTraceLog -Message "Will check custom WMI class... $($WMIRootPath):$($WMIClassName)" -LogFile $Logpath
$customWMIClass = Get-WmiObject -Namespace $WMIRootPath -Class $WMIClassName -List -ErrorAction SilentlyContinue
if($customWMIClass)
{
    Write-CMTraceLog -Message "Custom class exists and will be cleared: $($WMIRootPath):$($WMIClassName)" -LogFile $Logpath
    # clear class to make room for new entries
    Get-WmiObject -Namespace $WMIRootPath -Class $WMIClassName | Remove-WmiObject
}
else
{
    # create class because it's missind
    Write-CMTraceLog -Message "Custom class did not exist and will be created: $($WMIRootPath):$($WMIClassName)" -LogFile $Logpath
    if(New-CustomWmiClass -RootPath $WMIRootPath -ClassName $WMIClassName -ErrorAction SilentlyContinue)
    {
        Write-CMTraceLog -Message "Class created" -LogFile $Logpath
    }
    else
    {
        Write-CMTraceLog -Message "Custom class could not be created: $($WMIRootPath):$($WMIClassName)" -Severity Error -LogFile $Logpath
        Write-CMTraceLog -Message "End script" -LogFile $Logpath
        exit -1
    }
}
#endregion


#region start WSUS offline scan
Write-CMTraceLog -Message "Connect to WSUS service..." -LogFile $Logpath
try
{
    # connect to wsus service
    $UpdateSession = New-Object -comobject Microsoft.Update.Session
    $UpdateServiceManager = New-Object -comobject Microsoft.Update.ServiceManager
}
catch
{
    # create wmi entry for failed scan
    $classEntry = @{KeyName="Update000";
        ScriptCabFileVersion=$CabVersion;
        ScriptRunTimeSec=([math]::Round($ScriptStopwatch.Elapsed.TotalSeconds));
        ScriptStartTime=$ScriptStartTimeDMTF;
        MissingUpdates=999 # 999 means "unknown status"
        UpdateTitle="Not able to connect to WSUS client"
        UpdateKB=""
        }
    Set-WmiInstance -Path "\\.\$($WMIRootPath):$($WMIClassName)" -Arguments $classEntry | Out-Null
    
    Write-CMTraceLog -Message "unable to connect to WSUS Client" -Severity Error -LogFile $Logpath
    Write-CMTraceLog -Message "$($Error[0].Exception)" -Severity Error -LogFile $Logpath
    Write-CMTraceLog -Message "End script" -LogFile $Logpath
    exit -1
}


Write-CMTraceLog -Message "Add cab file and initiate scan... this step might take a while..." -LogFile $Logpath
Try
{
    # add cap file and initiate wsus scan against that file
    $UpdateService = $UpdateServiceManager.AddScanPackageService("Offline Sync Service Script", "$WSUSCABfilePath")
    $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
    $UpdateSearcher.ServerSelection = 3
    $UpdateSearcher.ServiceID = $UpdateService.ServiceID
    $SearchResult = $UpdateSearcher.Search("IsInstalled=0")
}
Catch
{
    # create wmi entry for failed scan
    $classEntry = @{KeyName="Update000";
        ScriptCabFileVersion=$CabVersion;
        ScriptRunTimeSec=([math]::Round($ScriptStopwatch.Elapsed.TotalSeconds));
        ScriptStartTime=$ScriptStartTimeDMTF;
        MissingUpdates=999
        UpdateTitle="Scan failed"
        UpdateKB=""
        }
    Set-WmiInstance -Path "\\.\$($WMIRootPath):$($WMIClassName)" -Arguments $classEntry | Out-Null

    Write-CMTraceLog -Message "unable to scan" -Severity Error -LogFile $Logpath
    Write-CMTraceLog -Message "$($Error[0].Exception)" -Severity Error -LogFile $Logpath
    Write-CMTraceLog -Message "End script" -LogFile $Logpath
    exit 1
}
#endregion


#region Write update info to WMI
$Updates = $SearchResult.Updates
$countMissingUpdates = $Updates.Count
If ($countMissingUpdates -le 0) 
{
    Write-CMTraceLog -Message "No missing updates found!" -LogFile $Logpath
    $classEntry = @{KeyName="Update000";
        ScriptCabFileVersion=$CabVersion;
        ScriptRunTimeSec=([math]::Round($ScriptStopwatch.Elapsed.TotalSeconds));
        ScriptStartTime=$ScriptStartTimeDMTF;
        MissingUpdates=0
        UpdateTitle=""
        UpdateKB=""
        }
    Set-WmiInstance -Path "\\.\$($WMIRootPath):$($WMIClassName)" -Arguments $classEntry | Out-Null

    Write-CMTraceLog -Message "Script end" -LogFile $Logpath
    Exit 0

}
else
{ 
    Write-CMTraceLog -Message "Found $($Updates.count) missing updates" -LogFile $Logpath
    $i = 0
    foreach($update in $Updates)
    {
        Write-CMTraceLog -Message "Create wmi entry for: $($update.Title)" -LogFile $Logpath
        $classEntry = @{KeyName="Update$($i.ToString("000"))";
            ScriptCabFileVersion=$CabVersion;
            ScriptRunTimeSec=([math]::Round($ScriptStopwatch.Elapsed.TotalSeconds));
            ScriptStartTime=$ScriptStartTimeDMTF;
            MissingUpdates=$countMissingUpdates
            UpdateTitle="$($update.Title)"
            UpdateKB="$($update.KBArticleIDs -join ',')"
            UpdateRevision=($update.Identity.RevisionNumber)
            UpdateID="$($update.Identity.UpdateID)"
            }
        Set-WmiInstance -Path "\\.\$($WMIRootPath):$($WMIClassName)" -Arguments $classEntry | Out-Null
        $i++
    }
}     
#endregion


#region End script and start ConfigMgr hardware inventory if activated
$ScriptStopwatch.Stop()
# Trigger ConfigMgr Client Hardware Inventory to report scan results asap 
if($ForceHardwareInventory)
{
    Write-CMTraceLog -Message "Trigger ConfigMgr Hardware Inventory" -LogFile $Logpath
    try
    {
        [void]([wmiclass]"\\.\root\ccm:SMS_Client").TriggerSchedule("{00000000-0000-0000-0000-000000000001}")
    }
    Catch
    {
    } 
}
else
{
    Write-CMTraceLog -Message "Parameter for ConfigMgr Hardware Inventory not set" -LogFile $Logpath
}
Write-CMTraceLog -Message "Script end" -LogFile $Logpath
#endregion
