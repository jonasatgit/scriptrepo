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

<#
.SYNOPSIS
    This script will read all wmi classes from a given wmi namespace list and tries to find a string in the data. 
    The data will be exported to a log file in the ConfigMgr client log directory.

.DESCRIPTION
    This script will read all wmi classes from a given wmi namespace list and tries to find a string in the data. 
    The data will be exported to a log file in the ConfigMgr client log directory. 
    The logfile can then be collected by ConfigMgr and the data can be analyzed in a text editor.
    You can use the "Collect Client Logs" feature in the ConfigMgr console to collect the log file.
    All data is stored in JSON format to be able to expand all object properties in a fast and reliable way.
    The logfile contains the class names at the top of the file to be able to see which classes were found.
    Each entry in the logfile is separated by a line of dashes.
    Use the search function of a text editor to find the string in the file and therefore the class where the string was found.
    The script does not have any parameters and is designed to be run from the ConfigMgr scripts feature.
    Buit it can also be run from the command line. 

    Parameters are stored in variables in the script, but a simple param() block can expose them to outside of the script.
    
    $SearchString
    The string to search for in the WMI data
    
    $WMINamespaces
    The list of WMI namespaces to search in. The script will resursively search all namespaces
    
    $OutputInfo
    If set to $true, the script will output information to the console
    
    CiVersionTimedOutSearch
    If set to $true, the script will search for the latest CIAgent*.log file and extract the CI ID from the VersionInfoTimedOut error message. 
    The CI_ID (shortened) will be used as the search string and will overwrite the $searchString variable. But only if the error message was found.

.LINK
    https://github.com/jonasatgit/scriptrepo    
#>

#region param block without the param() string to avoid problems with the ConfigMgr scripts feature
[string]$searchString = "f3bbbcff-67e7-402a-b952-9860e9b04cf7"
[array]$WMINamespaces = ('root\ccm','ROOT\Microsoft\PolicyPlatform\Documents\Local')
[bool]$OutputInfo = $true
[bool]$CiVersionTimedOutSearch = $true
#endregion

#region excluded classes and namespaces
[array]$excludedClassNames = @('CIM_','Synclet','_Setting','CCM_UserLogonEvents','CCM_VpnConnection','MDM_WindowsLicensing','Recently','C00000000_0000_0000_0000_000000000001')
[array]$global:ExcludedWMINamespaces = ('root\ccm\EndpointProtection','root\ccm\RebootManagement','root\ccm\Messaging','root\ccm\Events','root\ccm\Evaltest','root\ccm\Network','root\ccm\InvAgt')
#endregion


# Get the ConfigMgr client log path from the registry   
try
{
    # Define the registry path for the ConfigMgr client
    $registryPath = "HKLM:\SOFTWARE\Microsoft\CCM\Logging\@Global"

    # Get the ConfigMgr client log path from the registry
    $logPath = Get-ItemPropertyValue -Path $registryPath -Name "LogDirectory"
}catch
{
    Write-Output "ConfigMgr client log path not found $($_)"
    Exit 0
}

if (-NOT ($logPath))
{
    Write-Output "ConfigMgr client log path not found"
    Exit 0   
}


$datetimeString = get-date -Format "yyyyMMddHHmmss"
# needs to be log and not txt to be able to let ConfigMgr collect the file
$exportFileName = '{0}\_WmiExport-{1}.log' -f $logPath, $datetimeString 
$global:dataList = [System.Collections.Generic.List[pscustomobject]]::new()
$global:namespaceList = [System.Collections.Generic.List[string]]::new()
$outInfo = [System.Collections.Generic.List[pscustomobject]]::new()
$spacer = '---------------------------------------------------------------------------------------------'

#region function Get-CustomWMIClasses
function Get-CustomWMIClasses
{
    param
    (
        $rootNamespace
    )

    $classList = Get-WmiObject -Namespace $rootNamespace -List
    foreach ($class in $classList)
    {
        if (($class.Name -imatch '^__') -or (($class.Name -imatch '^MSFT')))
        {
            # skip system and Microsoft classes
        }
        else
        {
            $global:dataList.Add([pscustomobject]@{
                Namespace = $rootNamespace
                ClassName = $class.Name
            })
        }    
    }       
}
#endregion


#region function Get-WMINameSpaces
function Get-WMINameSpaces
{
    param
    (
        $NameSpace
    )

    $namespaces = Get-WmiObject -Namespace $NameSpace -Class __Namespace -ErrorAction SilentlyContinue | Select-Object -Property Name
    if ($namespaces)
    {
        foreach($item in $namespaces)
        {

            $newString = '{0}\{1}' -f $NameSpace, $item.Name

            # lets skip some namespaces
            $needToSkip = $false
            foreach ($excluded in $global:ExcludedWMINamespaces)
            {
                if ($newString -imatch [regex]::Escape($excluded))
                {
                    if($OutputInfo){Write-host "Skipping namespace: `"$($newString)`"" -ForegroundColor Yellow}
                    $needToSkip = $true
                }
            }
            if ($needToSkip){continue}
        
            $global:namespaceList.Add($newString)
            if($OutputInfo){Write-Host "Namespace found: $newString"}

            Get-WMINameSpaces -NameSpace $newString
        }

    }

    if (-NOT ($global:namespaceList.Contains($NameSpace)))
    {
        $global:namespaceList.Add($NameSpace)
        if($OutputInfo){Write-Host "Namespace found: $NameSpace"}    
    }
}
#endregion

#region search for ci version timed out
if ($CiVersionTimedOutSearch)
{
    if($OutputInfo){Write-Host "Parse CiaAgent.log files for VersionInfoTimedOut error.." -ForegroundColor Cyan}
    # Example: 
    #CIAgentJob({2535BA43-2097-45F0-A088-8D46ECE9DC5E}): CAgentJob::VersionInfoTimedOut for ModelName ScopeId_F39845A1-F303-4D3A-A303-6ECC327447D1/Application_7d1b5b09-123d-46d8-b4db-9217ce42de4f, version 12 not available.
    [array]$SelectStringResult = Get-ChildItem -Path $logPath -Filter "CIAgent*.log" | Sort-Object -Property LastWriteTime -Descending | Select-string -Pattern "CAgentJob::VersionInfoTimedOut"
    if($SelectStringResult)
    {
        $Matches = $null
        $null = $SelectStringResult[0].Line -match "VersionInfoTimedOut for ModelName (?<ModelName>.*?), version (?<Version>\d+)"

        # will overwrite searchString variable
        if($OutputInfo){Write-Host "Found VersionInfoTimedOut error for CI $($Matches['ModelName'])" -ForegroundColor Cyan}
        $searchString = $Matches['ModelName'] -replace "ScopeId_.*?/.*?_",""
        if($OutputInfo){Write-Host "Extracted searchstring is: $($searchString)" -ForegroundColor Cyan}
        #$Matches['Version'] # not used at the moment
    }
    else
    {
        if($OutputInfo){Write-Host "No VersionInfoTimedOut error found" -ForegroundColor Yellow}
        if($OutputInfo){Write-Host "Will use existing searchstring: $($searchString)" -ForegroundColor Yellow}
    }
}
#endregion

# We need all namespaces first
if($OutputInfo){Write-Host "Getting list of namespaces:" -ForegroundColor Cyan}
foreach($item in $WMINamespaces)
{
    Get-WMINameSpaces -NameSpace $item
}

# With all namespaces we can get a list of all classes per namespace
if($OutputInfo){Write-Host "Getting list of classes:" -ForegroundColor Cyan}
foreach($namespace in $global:namespaceList)
{
    if($OutputInfo){Write-Host "Getting classes for: $namespace"}
    Get-CustomWMIClasses -rootNamespace $namespace
}

# Lets now look for the data in each wmi class
if($OutputInfo){Write-Host "Search for string: `"$($searchString)`" in WMI classes" -ForegroundColor Cyan}
foreach ($WMIClass in $global:dataList)
{
    $needToSkip = $false
    # lets skip some classes
    foreach ($excluded in $excludedClassNames)
    {
        if ($WMIClass.ClassName -imatch [regex]::Escape($excluded))
        {
            if($OutputInfo){Write-host "Skipping class: `"$($WMIClass.ClassName)`"" -ForegroundColor Yellow}
            $needToSkip = $true
        }
    }
    if ($needToSkip){continue}

    $outString = '{0} - {1}' -f $WMIClass.namespace, $WMIClass.ClassName
    if($OutputInfo){Write-host $outString}

    try
    {
        [array]$wmiResult = Get-CimInstance -Namespace ($WMIClass.Namespace) -ClassName ($WMIClass.ClassName) -ErrorAction Stop 
            
        # export data if string was found in data
        foreach ($item in $wmiResult)
        {
            # we might need to get lazy properties
            $itemLoaded = $null
            $itemLoaded = Try{$item | Get-CimInstance -ErrorAction SilentlyContinue}catch{}
            # json makes the string search easier and gives a completely expanded object
            if (-NOT ($itemLoaded)){$itemLoaded = $item}
            $wmiJsonString = $itemLoaded | ConvertTo-Json -Depth 100
            if ($wmiJsonString -imatch $searchString)
            {
                if($OutputInfo){Write-Host "String: `"$($searchString)`" found in: `"$($WMIClass.ClassName)`"" -ForegroundColor Cyan}
                $outInfo.Add($WMIClass)
                $wmiJsonString | Out-File $exportFileName -Append
                $spacer | Out-File $exportFileName -Append
            }
        }           
    }
    catch
    {
        $errorString = 'Error in class: {0}\{1} -> {2}' -f $WMIClass.Namespace, $WMIClass.ClassName, $_
        if($OutputInfo){Write-Host $errorString -ForegroundColor Yellow}
    }

    # The class itself could contain the string
    if ($WMIClass.ClassName -imatch $searchString)
    {
        $wmiJsonString = $WMIClass | ConvertTo-Json -Depth 100
        if($OutputInfo){Write-Host "String: `"$($searchString)`" found in: `"$($WMIClass.ClassName)`"" -ForegroundColor Cyan}
        $outInfo.Add($WMIClass)
        $wmiJsonString | Out-File $exportFileName -Append
        $spacer | Out-File $exportFileName -Append
    }
}


if (Test-Path $exportFileName)
{
    # read all data to be able to put the names of the classes at the top of the file
    $fileContent = Get-Content $exportFileName
    $outInfo | Out-File $exportFileName -Force # clear the file via force parameter
    $spacer | Out-File $exportFileName -Append
    $fileContent | Out-File $exportFileName -Append

    if($OutputInfo)
    {
        Write-Host "Logfile: $($exportFileName)" -ForegroundColor Cyan
        Write-Host "Found the string: `"$($searchString)`" in the following classes:" -ForegroundColor Cyan
        $outInfo
    }

    Write-Output "Data found"
}
else
{
    Write-Output "No data found"
}
    
