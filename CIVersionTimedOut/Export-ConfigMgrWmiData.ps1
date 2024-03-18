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
[string]$searchString = "d740f314-c3b7-44a8-bf18-2a38b7bf7e0d"
[array]$WMINamespaces = ('root\ccm','ROOT\Microsoft\PolicyPlatform\Documents\Local')
[bool]$OutputInfo = $true
[bool]$CiVersionTimedOutSearch = $true
[bool]$StateMessageSearch = $false
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
$outInfo = [System.Collections.Generic.List[string]]::new()
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
    $outObj = [System.Collections.Generic.List[string]]::new()
    if($OutputInfo){Write-Host "Parse CIAgent.log files for VersionInfoTimedOut error.." -ForegroundColor Cyan}
    # Example: 
    #CIAgentJob({2535BA43-2097-45F0-A088-8D46ECE9DC5E}): CAgentJob::VersionInfoTimedOut for ModelName ScopeId_F39845A1-F303-4D3A-A303-6ECC327447D1/Application_7d1b5b09-123d-46d8-b4db-9217ce42de4f, version 12 not available.
    [array]$SelectStringResult = Get-ChildItem -Path $logPath -Filter "CIAgent*.log" | Sort-Object -Property LastWriteTime -Descending | Select-string -Pattern "CAgentJob::VersionInfoTimedOut"
    if($SelectStringResult)
    {
        
        foreach ($item in $SelectStringResult)
        {
            $Matches = $null
            $null = $item.Line -imatch "VersionInfoTimedOut for ModelName (?<ModelName>.*?), version (?<Version>\d+)"    
            $outString = '{0}/{1}' -f ($Matches['ModelName'] -replace "ScopeId_.*?/",""), ($Matches['Version'])
            "Found version timedout error for: $($outString)" | Out-File $exportFileName -Append
            if($OutputInfo){Write-Host "Found version timedout error for: $($outString)" -ForegroundColor Yellow}

            $outString = ($Matches['ModelName'] -replace "ScopeId_.*?/.*?_","")
            
            $outObj.Add($outString)
        }
              
        
        if ([string]::IsNullOrEmpty($searchString))
        {
            $searchString = (($outObj | Select-Object -Unique) -join '|').tostring()     
        }
        else
        {
            $searchString = '{0}|{1}' -f $searchString, (($outObj | Select-Object -Unique) -join '|').tostring()
        }

        if($OutputInfo){Write-Host "Current search string is:" -ForegroundColor Cyan}
        if($OutputInfo){Write-Host $searchString -ForegroundColor Cyan}
             
      }  
    else
    {
        if($OutputInfo){Write-Host "No VersionInfoTimedOut error found" -ForegroundColor Yellow}
        if($OutputInfo){Write-Host "Will use existing searchstring: $($searchString)" -ForegroundColor Yellow}
    }
}
#endregion



#region State Message Search
if ($StateMessageSearch)
{
    if($OutputInfo){Write-Host "Parse StateMessages for error -2016410860 and -2016411012" -ForegroundColor Cyan}
    # Lets check if we can find the CI version timed out error in state messages
    $appStateMessages = Get-WmiObject -Namespace ROOT\ccm\StateMsg -Query "select * from CCM_StateMsg where TopicID like 'ScopeId%'"

    $errorCounter = 0
    foreach($stateMessage in $appStateMessages)
    {
        # Convert to json to be able to parse easily
        # Remove all property definitions and just add the classname back
        $CimClassName = @{label="CimClassName";expression={$_.CimClass.CimClassName}}
        $wmiJsonString = $stateMessage | Select-Object -Property $CimClassName, * -ExcludeProperty CimClass, CimSystemProperties, CimInstanceProperties | ConvertTo-Json -Depth 100
    
        # From this: ScopeId_0C192617-7E7D-422B-979B-31FF58D765E6/Application_c0970840-2ef5-43be-b662-acffa796c2ae/44
        # To thi: c0970840-2ef5-43be-b662-acffa796c2ae
        $ciID = $stateMessage.TopicID -replace "ScopeId_.*?/.*?_","" -replace '/\d*'
        # -2016410860 and -2016411012 = CIVersionInfoTimedOut
        if ($wmiJsonString -imatch '2016410860|2016411012')
        {
            $errorCounter++
            if ([string]::IsNullOrEmpty($searchString))
            {
                $searchString = $ciID             
            }
            else
            {
                $searchString = '{0}|{1}' -f $searchString, $ciID
            }
        }

        if ($OutputInfo){Write-Host "Found $errorCounter state messages with VersionInfoTimedOut error" -ForegroundColor Cyan}

    }
}
#endregion

# lets output the searchstring into the log file
"SearchString:" | Out-File $exportFileName -Append
$searchString | Out-File $exportFileName -Append
$spacer | Out-File $exportFileName -Append

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

            # Remove all property definitions and just add the classname and namesapce back
            # We also exclude the app icon property, policy rules and policy apps
            $CimClassName = @{label="CimClassName";expression={$_.CimClass.CimClassName}}
            $CimNamespace = @{label="CimNamespace";expression={$_.CimSystemProperties.Namespace}}
            $wmiJsonString = $itemLoaded | Select-Object -Property $CimClassName, $CimNamespace, * -ExcludeProperty CimClass, CimSystemProperties, CimInstanceProperties, Icon | ConvertTo-Json -Depth 100
            if ($wmiJsonString -imatch $searchString)
            {
                if($OutputInfo){Write-Host "String: `"$($searchString)`" found in: `"$($WMIClass.ClassName)`"" -ForegroundColor Cyan}
                $outInfo.Add($WMIClass.ClassName)
                $wmiJsonStringShort = $itemLoaded | Select-Object -Property $CimClassName, $CimNamespace, * -ExcludeProperty CimClass, CimSystemProperties, CimInstanceProperties, Icon | ConvertTo-Json -Depth 3
                $wmiJsonStringShort | Out-File $exportFileName -Append
                $spacer | Out-File $exportFileName -Append
            }
        }           
    }
    catch
    {
        $errorString = 'Error in class: {0}\{1} -> {2}' -f $WMIClass.Namespace, $WMIClass.ClassName, $_
        if($OutputInfo){Write-Host $errorString -ForegroundColor Yellow}
    }

}


if (Test-Path $exportFileName)
{
    # read all data to be able to put the names of the classes at the top of the file
    $fileContent = Get-Content $exportFileName
    $outInfo | Select-Object -Unique | Out-File $exportFileName -Force # clear the file via force parameter
    $spacer | Out-File $exportFileName -Append
    $fileContent | Out-File $exportFileName -Append

    if($OutputInfo)
    {
        Write-Host "Logfile: $($exportFileName)" -ForegroundColor Cyan
        Write-Host "Found the string: `"$($searchString)`" in the following classes:" -ForegroundColor Cyan
        $outInfo | Select-Object -Unique
    }

    Write-Output "Data found"
}
else
{
    Write-Output "No data found"
}
    
