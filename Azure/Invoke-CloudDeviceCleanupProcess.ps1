<#
.SYNOPSIS
Script to remove duplicate devices from Intune and EntraID

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
# 
#************************************************************************************************************
#>

param
(
    [Parameter(Mandatory=$false)]
    [int]$DaysSinceRegistration = 2,

    [Parameter(Mandatory=$false)]
    [string]$DeviceNamePrefix = "DESKTOP",

    [Parameter(Mandatory=$false)]
    [string]$EntraIDAppID,

    [Parameter(Mandatory=$false)]
    [string]$EntraIDTenantID,

    [Parameter(Mandatory=$false)]
    [switch]$RequestScopes,

    [Parameter(Mandatory=$false)]
    [string[]]$RequiredScopes = @("Device.ReadWrite.All", "DeviceManagementManagedDevices.ReadWrite.All"),

    [Parameter(Mandatory=$false)]
    [string[]]$RequiredModules = @('Microsoft.Graph.Identity.DirectoryManagement','Microsoft.Graph.Beta.DeviceManagement'),
    
    [Parameter(Mandatory=$false)]
    [string]$LogFolder
)


#region Logfile
if (-NOT($LogFolder))
{
    $Script:LogFilePath = '{0}\{1}.log' -f $PSScriptRoot ,($MyInvocation.MyCommand)
}
else 
{
    $Script:LogFilePath = '{0}\{1}.log' -f $LogFolder, ($MyInvocation.MyCommand)
}
#endregion


#region Write-CMTraceLog
<#
.Synopsis
    Write-CMTraceLog will writea logfile readable via cmtrace.exe .DESCRIPTION
    Write-CMTraceLog will writea logfile readable via cmtrace.exe (https://www.bing.com/search?q=cmtrace.exe)
.EXAMPLE
    Write-CMTraceLog -Message "file deleted" => will log to the current directory and will use the scripts name as logfile name #> 
function Write-CMTraceLog 
{
    [CmdletBinding()]
    Param
    (
        #Path to the log file
        [parameter(Mandatory=$false)]
        [String]$LogFile=$Script:LogFilePath,

        #The information to log
        [parameter(Mandatory=$false)]
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
        [ValidateSet("Console","Log","ConsoleAndLog")]
        [string]$OutputMode = $Script:LogOutputMode
    )


    # save severity in single for cmtrace severity
    [single]$cmSeverity=1
    switch ($Severity)
        {
            "Information" {$cmSeverity=1; $color = [System.ConsoleColor]::Green; break}
            "Warning" {$cmSeverity=2; $color = [System.ConsoleColor]::Yellow; break}
            "Error" {$cmSeverity=3; $color = [System.ConsoleColor]::Red; break}
        }

    If (($OutputMode -ieq "Console") -or ($OutputMode -ieq "ConsoleAndLog"))
    {
        Write-Host $Message -ForegroundColor $color
    }
    
    If (($OutputMode -ieq "Log") -or ($OutputMode -ieq "ConsoleAndLog"))
    {
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


#region check for required modules
function Get-RequiredScriptModules 
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$RequiredModules
    )

    $moduleNotFound = $false
    foreach ($requiredModule in $requiredModules)
    {
        try 
        {
            Import-Module -Name $requiredModule -ErrorAction Stop    
        }
        catch 
        {
            $moduleNotFound = $true
        }
    }

    try 
    {
        if ($moduleNotFound)
        {
            # We might need nuget to install the module
            [version]$minimumVersion = '2.8.5.201'
            $nuget = Get-PackageProvider -ErrorAction Ignore | Where-Object {$_.Name -ieq 'nuget'} 
            if (-Not($nuget))
            {   
                Write-Output "Need to install NuGet to be able to install $($requiredModule)" 
                # Changed to MSI installer as the old way could not be enforced and needs to be approved by the user
                # Install-PackageProvider -Name NuGet -MinimumVersion $minimumVersion -Force
                $null = Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies -MinimumVersion $minimumVersion -Force
            }

            foreach ($requiredModule in $RequiredModules)
            {
                if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
                {
                    Write-Output "No admin permissions. Will install $($requiredModule) for current user only" 
                    
                    $paramSplatting = @{
                        Name = $requiredModule
                        Force = $true
                        Scope = 'CurrentUser'
                        Repository = 'PSGallery'
                        ErrorAction = 'Stop'
                    }
                    Install-Module @paramSplatting
                }
                else 
                {
                    Write-Output "Admin permissions. Will install $($requiredModule) for all users" 

                    $paramSplatting = @{
                        Name = $requiredModule
                        Force = $true
                        Repository = 'PSGallery'
                        ErrorAction = 'Stop'
                    }

                    Install-Module @paramSplatting
                }   

                Import-Module $requiredModule -Force -ErrorAction Stop
            }
        }    
    }
    catch 
    {
        Write-Output "failed to install or load module" 
        Write-Output "$($_)" -ForegroundColor Red
        Break
    }
}

#region datetime conversion
# Get the current date and time
$currentDateTime = Get-Date

# Subtract the specified number of days
$targetDateTime = $currentDateTime.AddDays(-$DaysSinceRegistration)

# Convert the result to UTC
$utcDateTime = $targetDateTime.ToUniversalTime()

# Format the result in ISO 8601 format with 'Z' to indicate UTC
$iso8601DateTimeSinceRegistration = $utcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")

# Output the result
Write-Output $iso8601DateTimeSinceRegistration
#endregion


# Call the function to ensure required modules are installed
Get-RequiredScriptModules -RequiredModules $RequiredModules


#region Connect to Graph
if ([string]::IsNullOrEmpty($EntraIDAppID))
{
    # No extra parameters needed in this case
    $paramSplatting = @{}
}
else
{
    # We need to connect to graph with a specific app registration
    if ([string]::IsNullOrEmpty($EntraIDTenantID))
    {
        Write-Output "Missing paramter `"-EntraIDTenantID`" for EntraID app registration"
        Write-Output "Exiting script"
        break
    }

    $paramSplatting = @{
        ClientId = $EntraIDAppID
        TenantId = $EntraIDTenantID
    }
}

if($RequestScopes)
{
    # Add the required scopes to the parameters. This will prompt the user to consent to the scopes
    $paramSplatting.Scopes = $RequiredScopes
}

Connect-MgGraph @paramSplatting

# Lets check if the required scopes are missing
$scopeNotFound = $false
foreach($scope in $RequiredScopes)
{
    if(-not (Get-MgContext).Scopes.Contains($scope))
    {
        Write-Output "We need scope: `"$scope`" to be able to run the script"
        $scopeNotFound = $true
    }
}

if($scopeNotFound)
{
    Write-Output "Exiting script as required scopes/permissions are missing. Please add the required scopes/permissions to the app registration."
    Write-Output "Or run the script with the -RequestScopes parameter to be able to request the scopes/permissions for the app registration"
    Write-Output "Exit script"
    break
}
#endregion

$graphFilter = "registrationDateTime ge {0} and operatingsystem eq 'windows' and startswith(displayName, '{1}')" -f $iso8601DateTimeSinceRegistration, $DeviceNamePrefix
$graphProperties = "id,deviceId,displayName,deviceOwnership,managementType,trustType"

$params = @{
    Filter = $graphFilter
    Property = $graphProperties
    All = $true
    ConsistencyLevel = "eventual"
    CountVariable = 'DeviceCountVariable'
}

$enrolledDevices = Get-MgDevice @params
Write-Output "Total devices found with filter: $($global:DeviceCountVariable)"

# We now need another graph call for each enrolled device to test if we have multiple devices with the same name

foreach($device in $enrolledDevices)
{
    $deviceGraphFilter = "displayName eq '$($device.displayName)'"

    $params = @{
        Filter = $deviceGraphFilter
        Property = $graphProperties
        All = $true
        ConsistencyLevel = "eventual"
        CountVariable = 'SingleDeviceCountVariable'
    }

    $deviceRetval = Get-MgDevice @params

    if($global:SingleDeviceCountVariable -gt 1)
    {
        Write-Output "Found $($global:SingleDeviceCountVariable) with the same name: `"$($device.displayName)`". Need to remove duplicates"
        # Remove duplicates by removing any older devices. Always keep the newest device.

        $intuneProperties = "Id,deviceName,AzureAdDeviceId,LastSyncDateTime,SerialNumber,OwnerType,ManagementCertificateExpirationDate"
        [array]$intuneDevices = Get-MgBetaDeviceManagementManagedDevice -Filter "deviceName eq '$($device.displayName)'" -Property $intuneProperties
        Write-Output "Found $($intuneDevices.Count) devices in Intune with the same name: `"$($device.displayName)`""

        # Sort the devices by registrationDateTime
        [array]$sortedDevices = $deviceRetval | Sort-Object -Property registrationDateTime -Descending
        $latestDevice = $sortedDevices[0]
        # Remove the first device from the list as it is the newest device
        $sortedDevicesToRemove = $sortedDevices | Select-Object -Skip 1

        foreach($deviceToRemove in $sortedDevicesToRemove)
        {
            Write-Output "Removing device: $($deviceToRemove.Id) with name: $($deviceToRemove.displayName) from EntraID"
            # Remove the device
            #Remove-MgDevice -DeviceId $deviceToRemove.deviceId

        }

        foreach($intuneDevice in $intuneDevices)
        {
            # Logic missing to only remove older devices
            Write-Output "Removing device: $($intuneDevice.Id) with name: $($intuneDevice.deviceName) from Intune"
            #Remove-MgBetaDeviceManagementManagedDevice -DeviceId $intuneDevice.Id
        }
    }
    elseif ($global:SingleDeviceCountVariable -eq 1) 
    {
        Write-Output "All good. Found just one entry for: `"$($device.displayName)`""
    }
    else 
    {
        Write-Output "Found $($global:SingleDeviceCountVariable) with the same name: `"$($device.displayName)`""   
    }  

}

