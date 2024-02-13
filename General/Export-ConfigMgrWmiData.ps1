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

# To run the script as a ConfigMgr script, use the second param block to avoid issues with parameters

# Test script to search in WMI

#region param block to us the script in standalone mode
<#
[CmdletBinding()]
param
(
    [string]$searchString = 'd740f314-c3b7-44a8-bf18-2a38b7bf7e0d',
    [array]$WMINamespaces = ('root\ccm','ROOT\Microsoft\PolicyPlatform\Documents\Local'),
    [bool]$OutputInfo = $true
)
#>
#endregion

#region param block just for the ConfigMgr scripts feature
[string]$searchString = "d740f314-c3b7-44a8-bf18-2a38b7bf7e0d"
[array]$WMINamespaces = ('root\ccm','ROOT\Microsoft\PolicyPlatform\Documents\Local')
[bool]$OutputInfo = $true
#endregion



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
$exportFileName = '{0}\CcmWmiExport-{1}.txt' -f $logPath, $datetimeString
$global:dataList = [System.Collections.Generic.List[pscustomobject]]::new()
$global:namespaceList = [System.Collections.Generic.List[string]]::new()
$outInfo = [System.Collections.Generic.List[pscustomobject]]::new()

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
            if ($newString -imatch [regex]::Escape('root\ccm\EndpointProtection'))
            {
                continue
            }

            if ($newString -imatch [regex]::Escape('root\ccm\RebootManagement'))
            {
                continue
            }

            if ($newString -imatch [regex]::Escape('root\ccm\Messaging'))
            {
                continue
            }

            if ($newString -imatch [regex]::Escape('root\ccm\Events'))
            {
                continue
            }

            if ($newString -imatch [regex]::Escape('root\ccm\Evaltest'))
            {
                continue
            }

            if ($newString -imatch [regex]::Escape('root\ccm\Network'))
            {
                continue
            }

            if ($newString -imatch [regex]::Escape('root\ccm\InvAgt'))
            {
                continue
            }
        
            $global:namespaceList.Add($newString)
            if($OutputInfo){Write-Host "Namespace found: $newString"}

            Get-WMINameSpaces -NameSpace $newString
        }

    }

    if ($global:namespaceList.Contains($NameSpace))
    {
        # skip
    }
    else
    {
        $global:namespaceList.Add($NameSpace)
        if($OutputInfo){Write-Host "Namespace found: $NameSpace"}    
    }
}
#endregion

# We need all namespaces first
if($OutputInfo){Write-Host "Getting list of namespaces:" -ForegroundColor Cyan}
foreach($item in $WMINamespaces)
{
    Get-WMINameSpaces -NameSpace $item
    #Get-CustomWMIClasses -rootNamespace $item
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
    # lets skip some classes
    if ($WMIClass.ClassName -imatch '^CIM')
    {
        continue
    }

    if ($WMIClass.ClassName -imatch 'Synclet')
    {
        continue
    }

    if ($WMIClass.ClassName -imatch [regex]::Escape('_Setting'))
    {
        continue
    }

    if ($WMIClass.ClassName -imatch [regex]::Escape('CCM_UserLogonEvents'))
    {
        continue
    }

    if ($WMIClass.ClassName -imatch [regex]::Escape('CCM_VpnConnection'))
    {
        continue
    }    

    
    if ($WMIClass.ClassName -imatch [regex]::Escape('MDM_WindowsLicensing'))
    {
        continue
    } 

    if ($WMIClass.ClassName -imatch [regex]::Escape('Recently'))
    {
        continue
    } 

    $outString = '{0} - {1}' -f $WMIClass.namespace, $WMIClass.ClassName
    if($OutputInfo){Write-host $outString}

    try
    {
        Get-WmiObject -Namespace ($WMIClass.Namespace) -Class ($WMIClass.ClassName) -ErrorAction Stop | ForEach-Object {
            
            # export data if string was found in data
            if ($_ | select-string -pattern $searchString)
            {
                if($OutputInfo){Write-Host "Data found in: `"$($WMIClass.Name)`"" -ForegroundColor Cyan}
                $outInfo.Add($WMIClass)
                $_ | Out-File $exportFileName -Append
                '---------------------------------------------------------------------------------------------' | Out-File $exportFileName -Append
            }
            
        }
    }catch{}

    try
    {
        if ($WMIClass.ClassName -imatch $searchString)
        {
            if($OutputInfo){Write-Host "Data found in: `"$($WMIClass.Name)`"" -ForegroundColor Cyan}
            $outInfo.Add($WMIClass)
            Get-WmiObject -Namespace ($WMIClass.Namespace) -Class ($WMIClass.ClassName) -ErrorAction Stop | Out-File $exportFileName -Append
            '---------------------------------------------------------------------------------------------' | Out-File $exportFileName -Append
        }
    }catch{}

}


if (Test-Path $exportFileName)
{
    $fileContent = Get-Content $exportFileName

    $outInfo | Out-File $exportFileName -Force
    '---------------------------------------------------------------------------------------------' | Out-File $exportFileName -Append
    $fileContent | Out-File $exportFileName -Append

    if($OutputInfo)
    {
        Write-Host "Found the string: `"$($searchString)`" in the following classes:" -ForegroundColor Cyan
        $outInfo
    }

    Write-Output "Data found"
}
else
{
    Write-Output "No data found"
}
    
