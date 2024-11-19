<#
.SYNOPSIS
Script to get VSCode extension metadata and store it in WMI

.DESCRIPTION
This script will get all VSCode extensions installed on a computer and store the metadata in a custom WMI class. 
The script will create a custom WMI class if it does not exist and clear the class if it does exist. 
The script will also delete the custom WMI class if the -Delete switch is set.

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


.PARAMETER WMIRootPath
WMI root path to store WMI class in. Default is root\cimv2

.PARAMETER WMIClassName
Custom WMI class to store script results in. Default is Custom_VSCodeExtensions

.PARAMETER Delete
Used to delete the WMi class. The script will exit after the class is deleted.

#>
[CmdletBinding()]
param
(
    # WMI root path to store WMI class in
    [Parameter(Mandatory=$false)]
    [string]$WMIRootPath = 'root\cimv2',

    # custom WMI class to store script results in
    [Parameter(Mandatory=$false)]
    [string]$WMIClassName = "Custom_VSCodeExtensions",

    # used to delete the WMi class
    [Parameter(Mandatory=$false)]
    [switch]$Delete
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
    $newWMIClass.Properties.Add("ExtensionPath", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["ExtensionPath"].Qualifiers.Add("key", $true)
    $newWMIClass.Properties["ExtensionPath"].Qualifiers.Add("read", $true)
    
    $newWMIClass.Properties.Add("UserName", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["UserName"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["UserName"].Qualifiers.Add("Description", "Extension installed for username")

    $newWMIClass.Properties.Add("ExtensionID", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["ExtensionID"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["ExtensionID"].Qualifiers.Add("Description", "ID of Extension")

    $newWMIClass.Properties.Add("ExtensionUUID", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["ExtensionUUID"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["ExtensionUUID"].Qualifiers.Add("Description", "UUID of Extension") 

    $newWMIClass.Properties.Add("ExtensionName", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["ExtensionName"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["ExtensionName"].Qualifiers.Add("Description", "Extension name")

    $newWMIClass.Properties.Add("ExtensionVersion", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["ExtensionVersion"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["ExtensionVersion"].Qualifiers.Add("Description", "Extension version")

    $newWMIClass.Properties.Add("ExtensionSource", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["ExtensionSource"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["ExtensionSource"].Qualifiers.Add("Description", "Extension installation source")

    $newWMIClass.Properties.Add("ExtensionPublisher", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["ExtensionPublisher"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["ExtensionPublisher"].Qualifiers.Add("Description", "Extension publisher name")

    $newWMIClass.Properties.Add("ExtensionPublisherID", [System.Management.CimType]::String, $false)
    $newWMIClass.Properties["ExtensionPublisherID"].Qualifiers.Add("read", $true)
    $newWMIClass.Properties["ExtensionPublisherID"].Qualifiers.Add("Description", "Extension publisher ID")
    
    [void]$newWMIClass.Put()
    return (Get-WmiObject -Namespace $RootPath -Class $ClassName -List)
}
#endregion

#region Get-VSCodeExtensionInfo
function Get-VSCodeExtensionInfo
{
    $profilestoSkip = @('.NET v4.5','.NET v4.5 Classic')
    $vsCodeExtensionDefinitionPath = ".vscode\extensions"    
    $outObject = [system.Collections.generic.list[pscustomobject]]::new()

    foreach ($item in (Get-ChildItem "C:\Users"))
    {   
        if ($item.Name -inotin $profilestoSkip)
        {
            $username = $item.FullName | Split-Path -Leaf
            $vsCodeExtensionDefinitionFile = '{0}\{1}\extensions.json' -f $item.FullName, $vsCodeExtensionDefinitionPath
            if (Test-Path $vsCodeExtensionDefinitionFile)
            {
                # Found a configuration file, lets read it            
                [array]$vsCodeExtensionDefinitionObject = Get-Content -Path $vsCodeExtensionDefinitionFile | ConvertFrom-Json

                foreach ($definition in $vsCodeExtensionDefinitionObject)
                {
                    $extensionFolderPath = '{0}\{1}\{2}\package.json' -f $item.FullName, $vsCodeExtensionDefinitionPath ,($definition.location.path | Split-Path -Leaf)
                    $extensionPackageObject = Get-Content -Path $extensionFolderPath | ConvertFrom-Json

                    $outObject.Add([pscustomobject][ordered]@{
                        UserName = $username
                        ExtensionID = $definition.identifier.id
                        ExtensionUUID = $definition.identifier.uuid
                        ExtensionName = $extensionPackageObject.displayName
                        ExtensionVersion = $definition.version
                        ExtensionSource = $definition.metadata.source
                        ExtensionPublisher = $definition.metadata.publisherDisplayName
                        ExtensionPublisherID = $definition.metadata.publisherId
                        ExtensionPath = $definition.location.path
                    })
                }    
            }        
        }
    }
    return $outObject
}
#endregion


#region MAIN SCRIPT



#region remove class if "Delete" is set
if($Delete)
{
    #Write-CMTraceLog -Message "Delete is set. Will delete: $($WMIRootPath):$($WMIClassName)" -LogFile $Logpath
    # remove custom class
    $customWMIClass = Get-WmiObject -Namespace $WMIRootPath -Class $WMIClassName -List -ErrorAction SilentlyContinue
    if($customWMIClass)
    {
        try 
        {
            $customWMIClass | Remove-WmiObject -ErrorAction Stop   
        }
        catch 
        {
            Write-Output 'Failed to delete wmi class'
            Exit -1
        }
        
    }
    #Write-CMTraceLog -Message "End script" -LogFile $Logpath
    Exit 0        
}
#endregion

#region clear class to make room for new entries or create new if not exists
try 
{
    $customWMIClass = Get-WmiObject -Namespace $WMIRootPath -Class $WMIClassName -List -ErrorAction SilentlyContinue
    if($customWMIClass)
    {
        # clear class to make room for new entries
        Get-WmiObject -Namespace $WMIRootPath -Class $WMIClassName | Remove-WmiObject
    }
    else
    {
        # create class because it's missind
        if(New-CustomWmiClass -RootPath $WMIRootPath -ClassName $WMIClassName -ErrorAction SilentlyContinue)
        {
            # class created   
        }
        else
        {
            Write-Output 'Failed to create wmi class'
            exit -1
        }
    }
    #endregion

    #region Write data to WMI
    $vsCodeExtensionInfo = Get-VSCodeExtensionInfo

    if (-NOT ($vsCodeExtensionInfo))
    {
        $classEntry = @{
            ExtensionPath = "No VSCode extensions found"
            UserName = ""
            ExtensionID = ""
            ExtensionUUID = ""
            ExtensionName = ""
            ExtensionVersion = ""
            ExtensionSource = ""
            ExtensionPublisher = ""
            ExtensionPublisherID = ""
        }
        Set-WmiInstance -Path "\\.\$($WMIRootPath):$($WMIClassName)" -Arguments $classEntry | Out-Null
    }
    else 
    {
        foreach ($item in $vsCodeExtensionInfo)
        {
            $classEntry = @{
                ExtensionPath = $item.ExtensionPath
                UserName = $item.UserName
                ExtensionID = $item.ExtensionID
                ExtensionUUID = $item.ExtensionUUID
                ExtensionName = $item.ExtensionName
                ExtensionVersion = $item.ExtensionVersion
                ExtensionSource = $item.ExtensionSource
                ExtensionPublisher = $item.ExtensionPublisher
                ExtensionPublisherID = $item.ExtensionPublisherID
            }
            Set-WmiInstance -Path "\\.\$($WMIRootPath):$($WMIClassName)" -Arguments $classEntry | Out-Null
        }
    }
}
catch 
{
    Write-Output "Failed to get VSCode extension metadata: $($_)"
    Exit -1
}
#endregion

Write-Output 'OK'

