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
.Synopsis
    The script will import ConfigMgr Applications into an ConfigMgr environment by reading the neccesary data out of the PSAppDeploymentToolKit "Deploy-Application.ps1" file.
.DESCRIPTION
    The script will import ConfigMgr Applications into an ConfigMgr environment by reading the neccesary data out of the PSAppDeploymentToolKit "Deploy-Application.ps1" file.
    The import process is done in the following order:
    1.  Read XML configfile which needs to be next to the script and which needs to have the exact same name plus '.xml' as an extension.
        If the script cannot find such file, it will output an exmample to the console, which can be used as the template
    2.  The script will then enumerate each "Deploy-Application.ps1" file using the "appRootFolder" path from the XML configfile and will show the list of files in a GridView
        Unless the parameter "AppRootFolderPath" was set. Then the path from the XML config file will be ignored and the parameter value will be used.
    3.  You then select one or more files to be analyzed and to be imported in SCCM
    4.  The script will read the following variables from each selected "Deploy-Application.ps1" file and will validate each variable value based on it's usecase:
        [string]$appVendor = 'Adobe'
        [string]$appName = 'Adobe Reader'
        [string]$appVersion = '20.0'
        [string]$appRevision = '20200313'
        [string]$appArch = 'x64'
        [string]$appLang = 'DE'
        [int]$cmAppMaxAllowedRuntime= 15
        [int]$cmAppEstimatedInstallTime = 5
        [string]$appFileToCheck = 'C:\Program Files\Adobe Reader\Reader.exe'
        [string]$appScriptVersion = '3.6.9'
        [string]$appScriptDate = '13/03/2020'
        [string]$appScriptAuthor = 'Max Mustermann'

        Variables like "$regAppName" will be resolved to show the real value.
        Each variable value will be shown in another gridview where the first column shows the validation result. Either "Passed" or "Failed".
        More details about each validaten result can be found in a logfile next to the script. 
        The script will also try to find a file called "icon" with one of the following extension "jpeg", "jpg", "ico" or "png" in the same folder the "Deploy-Application.ps1" 
        file was found and will use the file as the icon for the ConfigMgr application. 
        
        IMPORTANT: Validation fails if no "icon" file was found. Unless the parameter "IgnoreIconFileValidation" was set to ignore any missing files.
        IMPORTANT: You cannot import applications where the validation failed. 

    5.  If one or more applications have been selected in the GridView, the script will try to get the ConfigMgr SiteCode, will load the ConfigurationManager CmdLets and will
        change directory to the ConfigMgr drive.
    6.  If $UseIncrementalCollectionUpdates is set to true (which is the default) the count of all collections set to incremental will be checked and a warning will be shown 
        if there are more than 200.
    7.  The script will then check the value of "cmCollectionFolder" and "cmApplicationFolder" from the XML config file for existence
    8.  If the value of "useCollectionVariables" from the XML config file is set to true, the script will get as many unused collection variables as selected applications
    9.  The script will then check each application name and each install and uninstall collection name for existence and might skip an app, if either one of these exist already
    10. If the application name was not found, the application will be created
            a. A script deploymenttype for that application will be created
            b. The revision history will be deleted
            c. The app wil be distributed to either all Distribution Points or the list provided in the XML config file (no DP groups implemented yet)
            d. The app will then be moved to the folder configured via "cmApplicationFolder" in the XML config file
            e. A new collection will be created and if $UseIncrementalCollectionUpdates is set to true the refreshtype will be set to incremental. (No other schedule will be set)
            f. The collection will then be moved to the folder configured via "cmCollectionFolder" in the XML config file
            g. A collection query based on AD groups will be added
            h. If the value of "useCollectionVariables" from the XML config file is set to true, a collection variable containing the app name will be added
            i. The application will be deployed as available to the collection
          

.EXAMPLE
    .\Import-CMAppFromDeployToolkit.ps1
    Will only use input from the XML config file
.EXAMPLE
    .\Import-CMAppFromDeployToolkit.ps1 -AppRootFolderPath "\\server.domain.local\Source$\Apps"
    Will ignore the path from the XML config file and will use the path passed to the script
.EXAMPLE
    .\Import-CMAppFromDeployToolkit.ps1 -IgnoreIconFileValidation
    Will ignore a missing icon file as a validation error. Good for testing.
.PARAMETER AppRootFolderPath
    Alternative method of passing a path to the application root folder other than using the XML config file
.PARAMETER IgnoreIconFileValidation
    Validation fails if no "icon" file was found. Unless the parameter "IgnoreIconFileValidation" was set to ignore any missing files.
#>
param
(
    [Parameter(Mandatory=$false)]
    [string]$AppRootFolderPath,
    [Parameter(Mandatory=$false)]
    [switch]$IgnoreIconFileValidation
)

#region variable declaration
[string]$ScriptVersion = "20221123"
#endregion

#region fixed variables
[object]$startLocation = Get-Location
[string]$global:scriptName = $MyInvocation.MyCommand
[string]$global:logFile = "$($PSScriptRoot)\$($global:scriptName).Log"
[string]$xmlConfigFile = "$($PSScriptRoot)\$($global:scriptName).xml"
#endregion

#region Helper Functions
<#
.Synopsis
   Will output an example config file to the console
.EXAMPLE
   Show-ConfigFile
#>
function Show-ConfigFile
{
$configFile = @'
<?xml version="1.0" encoding="UTF-8" ?>

<configItems>
    <!-- UNC path to the root folder where all applications are stored. Only the first sub-folder will be used to look for the Deploy-Application.ps1 file  -->
    <appRootFolder>\\server.domain.local\sources$\AppsTest</appRootFolder>

    <!-- Path to the ConfigMgr folder where Collections should be placed  -->
    <cmCollectionFolder>\DeviceCollection\Softwaredeployment</cmCollectionFolder>

    <!-- Path to the ConfigMgr folder the Applications should be placed  -->
    <cmApplicationFolder>\Application\NewApps</cmApplicationFolder>

    <!-- Limiting CollectionID for each new Collection  -->
    <cmLimitingCollectionID>SMS00001</cmLimitingCollectionID>

    <!-- List of domains to be used as prefix for AD groups in collection queries-->
    <adGroupDomainList>
        <adGroupDomain>domain1</adGroupDomain>
        <adGroupDomain>domain2</adGroupDomain>
        <adGroupDomain>domain3</adGroupDomain>
    </adGroupDomainList>

    <!-- Prefix for Active Directory Groups. Will be used as Collection-Query IMPORTANT: adGroupDomainList will be added like this: "DOMAIN1\\APP-C-"-->
    <adGroupPrefix>APP-C-</adGroupPrefix>

    <!-- Prefix of the [string]$installRegistryPath variable of each Deploy-Application.ps1 file, for validation purposes -->
    <!-- HKLM: is the only supported HIVE at the momment -->
    <defaultRegistryPrefixInstalled>HKLM:\Software\_Custom\Installed\</defaultRegistryPrefixInstalled>

    <!-- Prefix of the [string]$uninstallRegistryPath variable of each Deploy-Application.ps1 file, for validation purposes -->
    <!-- HKLM: is the only supported HIVE at the momment -->
    <defaultRegistryPrefixUninstalled>HKLM:\Software\_Custom\Uninstalled\</defaultRegistryPrefixUninstalled>

    <!-- Either true or false. If true a simple script will be added as the detection logic. If false the built-in detection logic File and Registry will be used -->
    <useScriptDetectionLogic>false</useScriptDetectionLogic>

    <!-- Defines the default value of the maximum runtime of an application if the variable [int]$cmAppMaxAllowedRuntime is not present in the Deploy-Application.ps1 file-->
    <cmAppMaxAllowedRuntimeDefaultValueInMinutes>30</cmAppMaxAllowedRuntimeDefaultValueInMinutes>
    <!-- Defines the default value of the maximum runtime of an application if the varibale $cmAppEstimatedInstallTime is not present in the Deploy-Application.ps1 file-->
    <cmAppEstimatedInstallTimeDefaultValue>15</cmAppEstimatedInstallTimeDefaultValue>

    <!-- Collection variable prefix for task sequence dynamic app install step (the script is able to generate a maximum of 9999 variables like APPVAR9999 -->
    <dynamicAppVariableBaseName>APPVAR</dynamicAppVariableBaseName>

    <!-- Either true to use collection variables, or no to not use them. -->
    <useCollectionVariables>true</useCollectionVariables>

    <!-- FQDN of the ConfigMgr SMS provider server -->
    <ProviderMachineName>server.domain.local</ProviderMachineName>

    <!-- Default app installation command -->
    <appDefaultInstallCommand>powershell.exe -ExecutionPolicy Bypass -file .\Deploy-Application.ps1</appDefaultInstallCommand>

    <!-- Default app uninstallation command -->
    <appDefaultUninstallCommand>powershell.exe -ExecutionPolicy Bypass -file .\Deploy-Application.ps1 -DeploymentType Uninstall</appDefaultUninstallCommand>

    <!-- List of Distribution Points each app should be distributed to. Either "<DP>All</DP>" for all available DPs, or "<DP>server01.domain.local</DP>" and as many entries as needed. -->
    <cmDistributionPointList>

        <DP>All</DP>

    </cmDistributionPointList>

</configItems>
'@
        Write-Host $configFile -ForegroundColor Cyan

}
#endregion

#region
<#
.Synopsis
    Will try to open a logfile with cmtrace .DESCRIPTION
   Will try to open a logfile with cmtrace .EXAMPLE
   Open-LogWithCmTrace -$FilePath 'C:\Temp\outfile.log'
#>
Function Open-LogWithCmTrace
{
    param
    (
        [string]$FilePath
    )

    if (Test-Path $FilePath)
    {

        $regItem = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\CCM -Name TempDir -ErrorAction SilentlyContinue
        if ($regItem)
        {
            $cmTracePath = '{0}\CMTrace.exe' -f ($regItem.TempDir | Split-Path -Parent)
            &$cmTracePath $FilePath
        }
        else
        {
            Write-CMTraceLog -Message "Not able to find CMTrace.exe on this machine. Not able to open log" -Type Warning -OutputType LogOnly
        }
    }
    else
    {
        Write-CMTraceLog -Message "Logfile not found: $($FilePath)" -Type Warning -OutputType LogOnly
    }
}
#endregion


#region get-cmsitecode
<#
.Synopsis
    Will get the providers SiteCode located on the ProviderMachineName
.EXAMPLE
    Get-CMSiteCode -ProviderMachineName "server.doamin.local"
#>
function Get-CMSiteCode
{
    param
    (
        $ProviderMachineName
    )

    try 
    {
        $providerLocation = Get-CimInstance -ComputerName $ProviderMachineName -Namespace 'ROOT\SMS' -Query 'select * from SMS_ProviderLocation where ProviderForLocalSite = True' -ErrorAction SilentlyContinue
    }
    catch{}

    if($providerLocation)
    {
        return $providerLocation.SiteCode
    }
    else 
    {
        return $false    
    }
}
#endregion

#region Get-CMIncrementalCollectionRefreshCount
<#
.Synopsis
   Will return the number of collections with activated incremental update. 
.EXAMPLE
   Get-CMIncrementalCollectionRefreshCount -SiteCode 'P01' -ProviderMachineName "server.doamin.local"
#>
function Get-CMIncrementalCollectionRefreshCount
{
    param
    (
        [string]$SiteCode = "P01",
        [string]$ProviderMachineName=$env:Computername    
    )
    try
    {
        <#
        RefreshType
        1 = none
        2 = schedule
        4 = incremental
        6 = both
        #>
        [array]$collections = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -Query "select CollectionID from SMS_Collection Where refreshtype in (4,6)" -ErrorAction SilentlyContinue
    }
    catch{}
    if($collections)
    {
        return $collections.Count
    }
    else
    {
        return 0
    }
}
#endregion


#region Test-CMFolderPath
<#
.Synopsis
   Will test if a ConfigMgr folder path exists or not and currently only supports "DeviceCollection" and "Application" folder types. 
.EXAMPLE
   Test-CMFolderPath -SiteCode 'P01' -ProviderMachineName "server.doamin.local" -FolderPath "\DeviceCollection\Softwaredeployment\TestCollections"
.EXAMPLE
   Test-CMFolderPath -SiteCode 'P01' -ProviderMachineName "server.doamin.local" -FolderPath "DeviceCollection\Softwaredeployment\TestCollections"
.EXAMPLE
   Test-CMFolderPath -SiteCode 'P01' -ProviderMachineName "server.doamin.local" -FolderPath "\Application\NewApps"

#>
function Test-CMFolderPath
{
    param
    (
        [string]$SiteCode = "P01",
        [string]$ProviderMachineName=$env:Computername,
        [string]$FolderPath
    )

    $folderArray = $FolderPath -split '\\'
    $i = 0
    if($folderArray[0] -eq '')
    {
        $collectionType = $folderArray[1]
        $i = 2
    }
    else
    {
        $collectionType = $folderArray[0]
        $i = 1
    }
    

    Switch($collectionType)
    {
        'DeviceCollection' {$ObjectTypeName = 'SMS_Collection_Device'} 
        'Application' {$ObjectTypeName = 'SMS_ApplicationLatest'}
        <# not needed right now
        'DeviceCollection' {$ObjectTypeName = 'SMS_BootImagePackage'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_Collection_User'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_ConfigurationBaselineInfo'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_ConfigurationItemLatest'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_ImagePackage'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_Package'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_Query'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_TaskSequencePackage'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_Advertisement'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_Report'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_MeteredProductRule'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_ConfigurationItem'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_OperatingSystemInstallPackage'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_StateMigration'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_DeviceSettingPackage'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_DriverPackage'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_Driver'} 
        'DeviceCollection' {$ObjectTypeName = 'SMS_SoftwareUpdate'}
        #>

       Default {$ObjectTypeName = 'Unknown'}
    }

    if(-NOT ($ObjectTypeName -eq'Unknown'))
    {
        
        $ParentContainerNodeID = 0
        $validFolder = $true
        # Iterate through folder structure to check each folder
        $folderArray | Select-Object -Skip $i | ForEach-Object {
       
            try
            {
                $wqlQuery = "Select * from SMS_ObjectContainerNode where ObjectTypeName = '$($ObjectTypeName)' and Name = '$($_)' and ParentContainerNodeID = $ParentContainerNodeID"
                $cmFolderObject = Get-CimInstance -Namespace "root\sms\site_$SiteCode" -ComputerName $ProviderMachineName -Query $wqlQuery -ErrorAction Stop
                if($cmFolderObject)
                {
                    # setting new ContainerNodeID for the next sub-folder
                    $ParentContainerNodeID = $cmFolderObject.ContainerNodeID  
                }
                else
                {
                    # folder not found
                    $validFolder = $false
                    return $false
                }
                
            }
            catch
            {
                Write-Verbose "$($error[0].exception)"
                $validFolder = $false
                return $false
            }
        }
    }
    else
    {
        return $false
    }
    if($validFolder){return $true}
}
#endregion


#region Get-CMNextAvailableCollectionVariableNames
<#
.Synopsis
    Will get the next available colelction variable name based on the parameter values. Will max generate 9999 possible variables. 
.EXAMPLE
    Get-CMNextAvailableCollectionVariableNames -SiteCode "P01" -ProviderMachineName "server.doamin.local" -dynamicAppVariableBaseName "APPVAR" -cmCollectionVariableStartSuffix 3 -variableCount 5
.PARAMETER SiteCode
    ConfigMgr SiteCode
.PARAMETER ProviderMachineName
    The name of the ConfigMgr SMS provider server
.PARAMETER dynamicAppVariableBaseName
    The prefix of each variable. Like APPVAR or VAR or something like that
.PARAMETER cmCollectionVariableStartSuffix
    The number of vaiable names to skip. If set to 3 for example, the next possible variable will be APPVAR0004
.PARAMETER variableCount
    Number of variables to be returned
#>
function Get-CMNextAvailableCollectionVariableNames
{
    param
    (
        [string]$SiteCode = "P01",
        [string]$ProviderMachineName=$env:Computername,
        [string]$dynamicAppVariableBaseName='APPVAR',
        [int]$cmCollectionVariableStartSuffix = 3,
        [int]$variableCount = 5
    )

    try
    {
        $availableVariableNames = @()
        $cmCollectionIDList = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -Query "SELECT CollectionID FROM SMS_Collection WHERE CollectionVariablesCount != 0" | Select-Object -ExpandProperty CollectionID
        
        if($cmCollectionIDList)
        {
            $cmCollectionIDString = "'$($cmCollectionIDList -join "','")'" # generating a list like this: 'P1100229','P110022D','P110022E','P110022F','P11002D0' from an array

            [array]$cmCollectionSettings = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -Query "SELECT * FROM SMS_CollectionSettings WHERE CollectionID in ($cmCollectionIDString)"
            
            if($cmCollectionSettings)
            {
                $cmCollectionSettings = $cmCollectionSettings | Get-CimInstance -ComputerName $ProviderMachineName # loading lazy properties
                # getting list of all available collection variable names
    
                [array]$cmCollectionVariablesInUse = $cmCollectionSettings.CollectionVariables.Name | Where-Object {$_ -like "$dynamicAppVariableBaseName*"}
                
                if($cmCollectionVariablesInUse)
                {
                    # looking for the next available variablename
                    $i=$cmCollectionVariableStartSuffix
                    do
                    {
                        $newVariableName = "{0}{1}" -f $dynamicAppVariableBaseName, ($i.ToString('0000'))
                        if(-NOT($cmCollectionVariablesInUse.Contains("$newVariableName")))
                        {
                            $availableVariableNames += $newVariableName
                        }
                        $i++  
                    }
                    until ($availableVariableNames.Count -eq $variableCount)
                
                
                }
                else
                {
                    # looks like no collection has a variable
                    # define new ones            
                    for ($i=$cmCollectionVariableStartSuffix; $i -lt ($variableCount+$cmCollectionVariableStartSuffix); $i++)
                    { 
                        $newVariableName = "{0}{1}" -f $dynamicAppVariableBaseName, ($i.ToString('0000')) 
                        $availableVariableNames += $newVariableName  
                    }
                } # end  if($cmCollectionVariablesInUse)
            }
            else
            {
                # looks like no collection has a variable
                # define new ones            
                for ($i=$cmCollectionVariableStartSuffix; $i -lt ($variableCount+$cmCollectionVariableStartSuffix); $i++)
                { 
                    $newVariableName = "{0}{1}" -f $dynamicAppVariableBaseName, ($i.ToString('0000')) 
                    $availableVariableNames += $newVariableName  
                }
            } # end if($cmCollectionSettings)
        }
        else
        {
            # looks like no collection has a variable
            # define new ones            
            for ($i=$cmCollectionVariableStartSuffix; $i -lt ($variableCount+$cmCollectionVariableStartSuffix); $i++)
            { 
                $newVariableName = "{0}{1}" -f $dynamicAppVariableBaseName, ($i.ToString('0000')) 
                $availableVariableNames += $newVariableName  
            }
        } # end if($cmCollectionIDList)
    }
    Catch
    {
        return $false
    }
    
    return $availableVariableNames
}
#endregion

#region Write Logfiles in CMTrace Compatible Format
<#
.Synopsis
    Will write cmtrace readable log files. Can either just write to the console, just to the logfile or write to both. 
.EXAMPLE
    Write-CMTraceLog -Message "Starting script" -Path "C:\temp\logfile.log"
.EXAMPLE
    Write-CMTraceLog -Message "Starting script" -Path "C:\temp\logfile.log" -OutputType ConsoleOnly
.EXAMPLE
    Write-CMTraceLog -Message "Script has failed" -Path "C:\temp\logfile.log" -Type Error
.PARAMETER Message
    Text to be logged
.PARAMETER Type
    The type of message to be logged. Either Info, Warning or Error
.PARAMETER Path
    Path to the logfile
.PARAMETER Component
    The name of the component logging the message
.PARAMETER OutputType
    Either "LogOnly", "ConsoleOnly" or "LogAndConsole" to write the message to the console, the log or both
.PARAMETER FilesizeMB
    Maximum filesize for the log, befor a new logfile will be created
#>
Function Write-CMTraceLog
{
        [CmdletBinding()]
        Param
        (
            [Parameter(HelpMessage="Please enter a Message to Display", Mandatory=$true)]
            [string]$Message,
            [ValidateSet("Info", "Warning", "Error")]
            [string]$Type = "Info",
            [Parameter(HelpMessage="Please enter a valid Log-Path")]
            [string]$Path = $global:logFile,
            [string]$Component = $global:scriptName,
            [ValidateSet("LogOnly", "ConsoleOnly", "LogAndConsole")]
            [string]$OutputType = "LogAndConsole",
            [uInt32]$FilesizeMB = 5
        )

        $tmpLocation = (Get-Location).Path
        Set-Location 'C:'
        Switch($Type)
        {
            "Info"    {$severity = 1;$color = [ConsoleColor]::Green;  break}
            "Warning" {$severity = 2;$color = [ConsoleColor]::Yellow; break}
            "Error"   {$severity = 3;$color = [ConsoleColor]::Red}
        }

        $LogTime = (Get-Date -Format HH:mm:ss.fff).ToString()
        $LogDate = (Get-Date -Format MM-dd-yyyy).ToString()
        $LogTimeZoneBias = [System.TimeZone]::CurrentTimeZone.GetUtcOffset([datetime]::Now).TotalMinutes
        $LogTimePlusBias = "{0}{1}" -f $LogTime,$LogTimeZoneBias
        $output = "<![LOG[$Message]LOG]!>" + "<time=`"$LogTimePlusBias`" "+ "date=`"$LogDate`" " + "component=`"$Component`" " + "context=`"`" " +"type=`"$severity`" " + "thread=`"$PID`" " + "file=`"$(Split-Path $PSCommandPath -Leaf)`">"
        $consoleOutput = "{0} - {1} : {2}" -f (Get-Date -Format "MM.dd.yyyy HH:mm:ss"), $Type.ToUpper(),$Message
        
        If(($OutputType -eq "ConsoleOnly") -or ($OutputType -eq "LogAndConsole"))
        {
            Write-Host $ConsoleOutPut -ForegroundColor $color
        }
        
        If(($OutputType -eq "LogOnly") -or ($OutputType -eq "LogAndConsole"))
        {
            If(Test-Path $Path)
            {
                If((Get-Item -Path $Path).Length -ge $FilesizeMB * 2MB)
                {
                    $newName = $Path -replace ".log" , "_$(Get-date -Format "yyyy_MM_dd").log"
                    If(Test-Path $newName)
                    {
                        Remove-Item -Path $newName
                    }
                    Rename-Item -Path $Path -NewName $newName 
                }
            }
            $output | Out-File  -FilePath $Path -Encoding utf8 -Append -NoClobber
        }
        Set-Location $tmpLocation
}
#endregion

#region Write Logfiles in CMTrace Compatible Format
<#
.Synopsis
    Will write cmtrace readable log files. Can either just write to the console, just to the logfile or write to both. 
.EXAMPLE
    Write-CMTraceLog -Message "Starting script" -Path "C:\temp\logfile.log"
.EXAMPLE
    Write-CMTraceLog -Message "Starting script" -Path "C:\temp\logfile.log" -OutputType ConsoleOnly
.EXAMPLE
    Write-CMTraceLog -Message "Script has failed" -Path "C:\temp\logfile.log" -Type Error
.PARAMETER Message
    Text to be logged
#>
#region Exit-ScriptExecution
Function Exit-ScriptExecution
{
    param($startLocation)
    $startLocation | Set-Location 
    Write-CMTraceLog -Message 'Script end!' 
    Write-CMTraceLog -Message ' ' -OutputType LogOnly
    Write-CMTraceLog -Message ' ' -OutputType LogOnly
    exit
}
#endregion 


#region Main Script
if($startLocation.Provider.Name -ne 'FileSystem')
{
    # just in case we are still on the ConfigMgr drive and not locally 
    Set-Location $PSScriptRoot
}


#region check admin rights
If(-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{

    Write-Warning "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!"
    exit
}
#endregion



Write-CMTraceLog -Message "Starting script $($global:scriptName). Version: $ScriptVersion"


if($IgnoreIconFileValidation)
{
    Write-CMTraceLog -Message "IgnoreIconFileValidation is set. Will ignore missing icon files in validation process." -Type Warning
}

Write-CMTraceLog -Message "Loading configFile..."
if(-NOT(Test-Path "$xmlConfigFile"))
{
    Show-ConfigFile
    Write-CMTraceLog -Message "configFile `"$xmlConfigFile`" not found!" -Type Error
    Write-CMTraceLog -Message "Create a configfile called: `"$xmlConfigFile`" like the example above!"
    Exit-ScriptExecution -startLocation $startLocation
}


try
{
    [xml]$xmlConfigFileContent = Get-Content -LiteralPath $xmlConfigFile -Encoding UTF8 -ErrorAction SilentlyContinue

    # ignore path from XML file if passed as variable
    if($AppRootFolderPath)
    {
        [string]$appRootFolder = $AppRootFolderPath
        Write-CMTraceLog -Message "Path was passed as parameter. Using: `"$AppRootFolderPath`""
    }
    else
    {
        [string]$appRootFolder = $xmlConfigFileContent.configItems.appRootFolder
    }
    [string]$cmCollectionFolder = $xmlConfigFileContent.configItems.cmCollectionFolder
    [string]$cmApplicationFolder = $xmlConfigFileContent.configItems.cmApplicationFolder
    [string]$cmLimitingCollectionID = $xmlConfigFileContent.configItems.cmLimitingCollectionID
    [array]$adGroupDomainList = $xmlConfigFileContent.configItems.adGroupDomainList.adGroupDomain
    [string]$adGroupPrefix = $xmlConfigFileContent.configItems.adGroupPrefix
    [string]$defaultRegistryPrefixInstalled = $xmlConfigFileContent.configItems.defaultRegistryPrefixInstalled
    [string]$defaultRegistryPrefixUninstalled = $xmlConfigFileContent.configItems.defaultRegistryPrefixUninstalled
    [string]$useScriptDetectionLogic = $xmlConfigFileContent.configItems.useScriptDetectionLogic
    [int]$cmAppMaxAllowedRuntimeDefaultValueInMinutes = ($xmlConfigFileContent.configItems.cmAppMaxAllowedRuntimeDefaultValueInMinutes).Replace('"','')
    [int]$cmAppEstimatedInstallTimeDefaultValue = ($xmlConfigFileContent.configItems.cmAppEstimatedInstallTimeDefaultValue).Replace('"','')
    [string]$dynamicAppVariableBaseName = $xmlConfigFileContent.configItems.dynamicAppVariableBaseName
    [string]$ProviderMachineName = $xmlConfigFileContent.configItems.ProviderMachineName
    [string]$appDefaultInstallCommand = $xmlConfigFileContent.configItems.appDefaultInstallCommand
    [string]$appDefaultUninstallCommand = $xmlConfigFileContent.configItems.appDefaultUninstallCommand
    [array]$cmDistributionPointList = $xmlConfigFileContent.configItems.cmDistributionPointList.DP
    [string]$useCollectionVariables = $xmlConfigFileContent.configItems.useCollectionVariables
    [string]$UseIncrementalCollectionUpdates = $xmlConfigFileContent.configItems.useIncrementalCollectionUpdates
}
catch
{
    Show-ConfigFile
    Write-CMTraceLog -Message "Error loading configFile `"$xmlConfigFile`"" -Type Error
    Write-CMTraceLog -Message "Validate configfile entries as shown above."
    Write-CMTraceLog -Message "$($error[0].Exception)" -Type Error
    Exit-ScriptExecution -startLocation $startLocation
}
Write-CMTraceLog -Message "configFile loaded!"


if(-NOT([System.IO.Directory]::Exists("$appRootFolder"))) # using [System.IO.Directory] instead og Test-Path due to network share test problems
{
    Write-CMTraceLog -Message "Path `"$appRootFolder`" not found!" -Type Error
    Exit-ScriptExecution -startLocation $startLocation
}


Write-CMTraceLog -Message "Enumerating `"Deploy-Application.ps1`" files from `"$appRootFolder`""
#region getting list of all Deploy-Application.ps1 files available
[array]$appDeploymentFiles = Get-ChildItem -LiteralPath $appRootFolder -Recurse -Depth 1 -Filter 'Deploy-Application.ps1' -File # File Parameter not working with network path
#$appDeploymentFiles = ,$appDeploymentFiles # converting to array if just one file was found to get count method

Write-CMTraceLog -Message "Found $($appDeploymentFiles.Count) files in `"$appRootFolder`""

[array]$selectedappDeploymentFiles = $appDeploymentFiles | 
                Select-Object Name, @{Label='LastWriteTime'; Expression={(get-date($_.LastWriteTime) -format u)}} ,DirectoryName, FullName | 
                Sort-Object LastWriteTime -Descending | 
                Out-GridView -Title 'Choose one or multiple apps to validate or import!' -OutputMode Multiple

if($selectedappDeploymentFiles)
{
    #Write-CMTraceLog -Message "$(($selectedappDeploymentFiles | Measure-Object).Count) files selected" # count method not available if just one entry
    Write-CMTraceLog -Message "$($selectedappDeploymentFiles.Count) files selected" # count method not available if just one entry
    $i = 0
    $appInfoObj = New-Object System.Collections.ArrayList
    [bool]$validationFailedGlobal = $false
    Write-CMTraceLog -Message "Starting validation"
    foreach ($selectedFile in $selectedappDeploymentFiles)
    {
        [bool]$validationFailed = $false
        $i++
        Write-Progress -Activity 'Reading config data...' -Status "Working on: $i of $($selectedappDeploymentFiles.count) files" -PercentComplete (100/$selectedappDeploymentFiles.count*$i)
        $tmpAppObj = New-Object pscustomobject
        $tmpAppObj | add-member -name 'Validation' -type NoteProperty -Value "Unknown"
        Write-CMTraceLog -Message " " -OutputType LogOnly
        Write-CMTraceLog -Message "Working on: `"$($selectedFile.FullName | Split-Path | Split-Path -Leaf)`"" -OutputType LogOnly
        Write-CMTraceLog -Message "`"$($selectedFile.FullName)`"" -OutputType LogOnly
        # Switch -File $selectedFile.FullName -Regex # too slow and wrong encoding, using get-content and param -TotalCount instead
        # Also limiting the content we work with to just the variable declaration section. Oterwiese we might read the variable value from a wrong script part
        
        $variableSectionStart = select-string -Pattern "\* APP VARIABLE DECLARATION" -LiteralPath $selectedFile.FullName
        $variableSectionEnd = select-string -Pattern "\* END APP VARIABLE DECLARATION" -LiteralPath $selectedFile.FullName

        if ($variableSectionStart -and $variableSectionEnd)
        {

            $fileData = get-content -LiteralPath $selectedFile.FullName -TotalCount ($variableSectionEnd.LineNumber) | Select-Object -Skip ($variableSectionStart.LineNumber -1)
            Switch -Regex ($fileData)
            {
                '\$appVendor = ''(?<appVendor>.*?)''' 
                {
                    $appVendor = $Matches.appVendor
                    $Matches = $null
                }
                '\$appName = ''(?<appName>.*?)''' 
                {
                    $appName = $Matches.appName
                    $Matches = $null
                }
                '\$appVersion = ''(?<appVersion>.*?)''' 
                {
                    $appVersion = $Matches.appVersion
                    $Matches = $null
                }
                '\$appArch = ''(?<appArch>.*?)''' 
                {
                    $appArch = $Matches.appArch
                    $Matches = $null
                }
                '\$appLang = ''(?<appLang>.*?)''' 
                {
                    $appLang = $Matches.appLang
                    $Matches = $null
                }
                '\$appRevision = ''(?<appRevision>.*?)''' 
                {
                    $appRevision = $Matches.appRevision
                    $Matches = $null
                }
                '\$appFilePathToCheck = ''(?<appFilePathToCheck>.*?)''' 
                {
                    $appFileToCheck = $Matches.appFilePathToCheck
                    $Matches = $null
                }            
                '\$appScriptVersion = ''(?<appScriptVersion>.*?)''' 
                {
                    $appScriptVersion = $Matches.appScriptVersion
                    $Matches = $null
                }
                '\$appScriptDate = ''(?<appScriptDate>.*?)''' 
                {
                    $appScriptDate = $Matches.appScriptDate
                    $Matches = $null
                }
                '\$appScriptAuthor = ''(?<appScriptAuthor>.*?)''' 
                {
                    $appScriptAuthor = $Matches.appScriptAuthor
                    $Matches = $null
                }
                '\$cmAppMaxAllowedRuntime = (?<cmAppMaxAllowedRuntime>[\d]+)' 
                {
                    $cmAppMaxAllowedRuntime= $Matches.cmAppMaxAllowedRuntime
                    $Matches = $null
                }
                '\$cmAppEstimatedInstallTime = (?<cmAppEstimatedInstallTime>[\d]+)' 
                {
                    $cmAppEstimatedInstallTime = $Matches.cmAppEstimatedInstallTime
                    $Matches = $null
                }
                '\$cmAllowUserInteraction = ''(?<cmAllowUserInteraction>true|false)'''
                {
                    $cmAllowUserInteraction = $Matches.cmAllowUserInteraction
                    $Matches = $null
                }
                '\$cmAppDescription = ''(?<cmAppDescription>.*?)''' 
                {
                    $cmAppDescription = $Matches.cmAppDescription
                    $Matches = $null
                }
                
            } # end switch
        } # end if ($variableSectionStart -and $variableSectionEnd)

        #region validation of passed variables. Checking every variable as thoroughly as possible to avoid problems during app creation

        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: appVendor" -OutputType LogOnly
        if(-NOT($appVendor))
        {
            $appVendor= ''
            $validationFailed = $true
            Write-CMTraceLog -Message "      appVendor missing" -OutputType LogOnly -Type Warning
        }
        else 
        {
            # whitespace detection
            if ($appVendor -match '^\s|\s$')
            {
                $validationFailed = $true
                Write-CMTraceLog -Message "      appVendor contains whitespaces at the beginning or end" -OutputType LogOnly -Type Warning
            }
        }        
        $tmpAppObj | add-member -name 'appVendor' -type NoteProperty -Value $appVendor
        #endregion------------------------------------------
       
        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: appName" -OutputType LogOnly
        if(-NOT($appName))
        {
            $appName= ''
            $validationFailed = $true
            Write-CMTraceLog -Message "      appName missing" -OutputType LogOnly -Type Warning
        }
        else 
        {
            # whitespace detection
            if ($appName -match '^\s|\s$')
            {
                $validationFailed = $true
                Write-CMTraceLog -Message "      appName contains whitespaces at the beginning or end" -OutputType LogOnly -Type Warning
            }
        }
        $tmpAppObj | add-member -name 'appName' -type NoteProperty -Value $appName
        #endregion------------------------------------------

        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: appVersion" -OutputType LogOnly
        if(-NOT($appVersion))
        {
            $appVersion= ''
            $validationFailed = $true
             Write-CMTraceLog -Message "      appVersion missing" -OutputType LogOnly -Type Warning
        }
        else 
        {
            # whitespace detection
            if ($appVersion -match '^\s|\s$')
            {
                $validationFailed = $true
                Write-CMTraceLog -Message "      appVersion contains whitespaces at the beginning or end" -OutputType LogOnly -Type Warning
            }
        }         
        $tmpAppObj | add-member -name 'appVersion' -type NoteProperty -Value $appVersion
        #endregion------------------------------------------

        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: appArch" -OutputType LogOnly
        if(-NOT($appArch))
        {
            $appArch= ''
            $validationFailed = $true
            Write-CMTraceLog -Message "      appArch missing" -Type Warning -OutputType LogOnly 
        }
        else 
        {
            if(-NOT ($appArch -match 'x86|x64|x86_x64'))
            {
                $validationFailed = $true
                Write-CMTraceLog -Message "      appArch not one of: x86, x64, x86_x64" -Type Warning -OutputType LogOnly             
            }

            # whitespace detection
            if ($appArch -match '^\s|\s$')
            {
                $validationFailed = $true
                Write-CMTraceLog -Message "      appArch contains whitespaces at the beginning or end" -OutputType LogOnly -Type Warning
            } 

        }
        $tmpAppObj | add-member -name 'appArch' -type NoteProperty -Value $appArch
        #endregion------------------------------------------ 

        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: appLang" -OutputType LogOnly
        if(-NOT($appLang))
        {
            $appLang= ''
            $validationFailed = $true
            Write-CMTraceLog -Message "      appLang missing" -Type Warning -OutputType LogOnly 
        }
        else
        {
            $appLang = $appLang.ToUpper()
            # whitespace detection
            if ($appLang -match '^\s|\s$')
            {
                $validationFailed = $true
                Write-CMTraceLog -Message "      appLang contains whitespaces at the beginning or end" -OutputType LogOnly -Type Warning
            }
        }        
        $tmpAppObj | add-member -name 'appLang' -type NoteProperty -Value $appLang
        #endregion------------------------------------------ 
  
        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: appRevision" -OutputType LogOnly
        if(-NOT($appRevision))
        {
            $appRevision= ''
            $validationFailed = $true
            Write-CMTraceLog -Message "      appRevision missing" -Type Warning -OutputType LogOnly 
        }
        else
        {
            # whitespace detection
            if ($appRevision -match '^\s|\s$')
            {
                $validationFailed = $true
                Write-CMTraceLog -Message "      appRevision contains whitespaces at the beginning or end" -OutputType LogOnly -Type Warning
            }

            # format detection
            if (-NOT ($appRevision -match '\d{8}'))
            {
                $validationFailed = $true
                Write-CMTraceLog -Message "      appRevision not in the following format yyyyMMdd" -OutputType LogOnly -Type Warning
            }

        }          
        $tmpAppObj | add-member -name 'appRevision' -type NoteProperty -Value $appRevision
        #endregion------------------------------------------  
 
        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: appFileToCheck" -OutputType LogOnly
        if(-NOT($appFileToCheck))
        {
            $appFileToCheck= ''
            $validationFailed = $true
            Write-CMTraceLog -Message "      appFileToCheck missing" -Type Warning -OutputType LogOnly
        }
        else
        {
            # whitespace detection
            if ($appFileToCheck -match '^\s|\s$')
            {
                $validationFailed = $true
                Write-CMTraceLog -Message "      appFileToCheck contains whitespaces at the beginning or end" -OutputType LogOnly -Type Warning
            }
        }         
        $tmpAppObj | add-member -name 'appFileToCheck' -type NoteProperty -Value $appFileToCheck
        #endregion------------------------------------------ 
        
 
        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: appScriptVersion" -OutputType LogOnly
        if(-NOT($appScriptVersion))
        {
            $appScriptVersion= ''
            $validationFailed = $true
            Write-CMTraceLog -Message "      appScriptVersion missing" -Type Warning -OutputType LogOnly
        }
        $tmpAppObj | add-member -name 'appScriptVersion' -type NoteProperty -Value $appScriptVersion
        #endregion------------------------------------------ 
 
        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: appScriptDate" -OutputType LogOnly
        if(-NOT($appScriptDate))
        {
            $appScriptDate= ''
            $validationFailed = $true
            Write-CMTraceLog -Message "      appScriptDate missing" -Type Warning -OutputType LogOnly
        }
        $tmpAppObj | add-member -name 'appScriptDate' -type NoteProperty -Value $appScriptDate
        #endregion------------------------------------------ 

        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: appScriptAuthor" -OutputType LogOnly
        if(-NOT($appScriptAuthor))
        {
            $appScriptAuthor= ''
            $validationFailed = $true
            Write-CMTraceLog -Message "      appScriptAuthor missing" -Type Warning -OutputType LogOnly
        }
        $tmpAppObj | add-member -name 'appScriptAuthor' -type NoteProperty -Value $appScriptAuthor
        #endregion------------------------------------------

        #region---------------------------------------------
        $InstallRegistryPath = '{0}{1}' -f $defaultRegistryPrefixInstalled, $tmpAppObj.appName
        $tmpAppObj | add-member -name 'InstallRegistryPath' -type NoteProperty -Value $InstallRegistryPath
        #endregion------------------------------------------ 

        #region---------------------------------------------
        $UninstallRegistryPath = '{0}{1}' -f $defaultRegistryPrefixUninstalled, $tmpAppObj.appName
        $tmpAppObj | add-member -name 'UninstallRegistryPath' -type NoteProperty -Value $UninstallRegistryPath
        #endregion------------------------------------------ 


        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: cmAppMaxAllowedRuntime" -OutputType LogOnly
        if(-NOT($cmAppMaxAllowedRuntime))
        {
            Write-CMTraceLog -Message "      cmAppMaxAllowedRuntime not set, using default value of: $cmAppMaxAllowedRuntimeDefaultValueInMinutes minutes" -Type Warning -OutputType LogOnly
            $cmAppMaxAllowedRuntime = $cmAppMaxAllowedRuntimeDefaultValueInMinutes # set default value if nothing was set before
        }
        else
        {
            if($cmAppMaxAllowedRuntime-lt 15)
            {
                $validationFailed = $true
                Write-CMTraceLog -Message "      cmAppMaxAllowedRuntimecannot be less then 15!" -Type Warning -OutputType LogOnly
            }
        }
        $tmpAppObj | add-member -name 'cmAppMaxAllowedRuntime' -type NoteProperty -Value $cmAppMaxAllowedRuntime
        #endregion------------------------------------------

        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: cmAppEstimatedInstallTime" -OutputType LogOnly
        if(-NOT($cmAppEstimatedInstallTime))
        {
            Write-CMTraceLog -Message "      cmAppEstimatedInstallTime not set, using default value of: $cmAppEstimatedInstallTimeDefaultValue minutes" -Type Warning -OutputType LogOnly
            $cmAppEstimatedInstallTime = $cmAppEstimatedInstallTimeDefaultValue # set default value if nothing was set before
        }
        $tmpAppObj | add-member -name 'cmAppEstimatedInstallTime' -type NoteProperty -Value $cmAppEstimatedInstallTime
        #endregion------------------------------------------

        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: cmAllowUserInteraction" -OutputType LogOnly
        if(-NOT($cmAllowUserInteraction))
        {
            $validationFailed = $true
            Write-CMTraceLog -Message "      cmAllowUserInteraction missing" -Type Warning -OutputType LogOnly
            # not setting to failed since description is optional
        }
        $tmpAppObj | add-member -name 'cmAllowUserInteraction' -type NoteProperty -Value $cmAllowUserInteraction  
        #endregion------------------------------------------
        
        #region---------------------------------------------
        Write-CMTraceLog -Message "      Validate: cmAppDescription" -OutputType LogOnly
        if(-NOT($cmAppDescription))
        {
            Write-CMTraceLog -Message "      cmAppDescription missing" -Type Warning -OutputType LogOnly
            # not setting to failed since description is optional
        }
        $tmpAppObj | add-member -name 'cmAppDescription' -type NoteProperty -Value $cmAppDescription
        #endregion------------------------------------------
        
        #region adding additional properties
        $tmpAppObj | add-member -name 'FileFullName' -type NoteProperty -Value $selectedFile.FullName
        $tmpAppObj | add-member -name 'CMAppNameInSoftwareCenter' -type NoteProperty -Value "$appName $appArch $appLang"
        $tmpAppObj | add-member -name 'CMAppNameInConsole' -type NoteProperty -Value "$appVendor $appName $appArch $appLang $appRevision"
        $tmpAppObj | add-member -name 'CMCollectionName_Install' -type NoteProperty -Value "$appVendor $appName $appArch $appLang $appRevision Install"
        $tmpAppObj | add-member -name 'CMCollectionName_Uninstall' -type NoteProperty -Value "$appVendor $appName $appArch $appLang $appRevision Uninstall"

        # in case we don't have a domain in the config file, add the current user domain 
        if ($adGroupDomainList.count -eq 0)
        {
            $cmWQLQueryADGroupName = "(`"{0}\\{1}`")" -f ($env:USERDOMAIN.ToUpper()), "$($adGroupPrefix)$($appVendor.Replace(' ','-'))-$($appName.Replace(' ','-'))" # like: "DOMAIN\\APP-C-Ghisler-Total-Commander"
        }
        else 
        {   
            # add one entry for each domain in the list
            $tmpADGroupArray = @()
            foreach($ADGroupOfList in $adGroupDomainList)
            {
                $tmpADGroupArray += "{0}\\{1}" -f ($ADGroupOfList.ToUpper()), "$($adGroupPrefix)$($appVendor.Replace(' ','-'))-$($appName.Replace(' ','-'))" # like: "DOMAIN\\APP-C-Ghisler-Total-Commander"
            }

            # joining the string and adding brackets for the WQL query
            $fullADGroupString = $tmpADGroupArray -join '","' # adding comma and quatation marks
            $cmWQLQueryADGroupName = "(`"{0}`")" -f $fullADGroupString
        }
        
        $tmpAppObj | add-member -name 'WQLQueryAdGroupName' -type NoteProperty -Value $cmWQLQueryADGroupName
        $tmpAppObj | add-member -name 'CMAppContentSourcePath' -type NoteProperty -Value ($selectedFile.FullName | Split-Path)

        # looking for icon file...
        [array]$iconfile = Get-ChildItem "$(($selectedFile.FullName | Split-Path))" -Filter 'icon.*' -ErrorAction SilentlyContinue | Where-Object {$_.Extension -in ('.jpeg','.jpg','.ico','.png')} 
        if($iconfile)
        {
            $tmpAppObj | add-member -name 'cmAppIconFile' -type NoteProperty -Value ($iconfile[0].FullName)    
        }
        else
        {
            $tmpAppObj | add-member -name 'cmAppIconFile' -type NoteProperty -Value ""
            Write-CMTraceLog -Message "      cmAppIconFile could not be set, no file with name `"icon.[jpeg,jpg,ico,png]`" found" -Type Warning -OutputType LogOnly
            if(-NOT($IgnoreIconFileValidation))
            {
                $validationFailed = $true
            }
        }

        $extensionPath = '{0}\AppDeployToolkit\AppDeployToolkitExtensions.ps1' -f ($selectedFile.FullName | Split-Path -Parent)
        if (-NOT(Test-Path $extensionPath))
        {
            $validationFailed = $true
            Write-CMTraceLog -Message "      Script missing: .\AppDeployToolkit\AppDeployToolkitExtensions.ps1" -Type Error -OutputType LogOnly
        }
        else 
        {
            # Do we have the custom registry string in the AppDeployToolkitExtensions.ps1? If not, the app might not work as expected
            if (-NOT (Select-String -Pattern ([regex]::Escape($defaultRegistryPrefixInstalled) -replace 'HKLM:','') -LiteralPath $extensionPath))
            {
                Write-CMTraceLog -Message "      Missing custom registry entries in: .\AppDeployToolkit\AppDeployToolkitExtensions.ps1" -Type Warning -OutputType LogOnly
                $validationFailed = $true
            }
        }

        if($validationFailed)
        {
            $tmpAppObj.Validation = "Failed - open log"
            $validationFailedGlobal = $true # will be set to true if one app fails the tests
            Write-CMTraceLog -Message "      Validation failed!" -Type Error -OutputType LogOnly
        }
        else 
        {
            $tmpAppObj.Validation = "Passed"
            Write-CMTraceLog -Message "      Validation passed!" -OutputType LogOnly
        }
        
        #endregion ----------------------------------------

        #region reset variables to avoid any wrong entries due to missing regex matches from above
        $cmAppMaxAllowedRuntime= $null
        $cmAppEstimatedInstallTime = $null
        $installRegistryPath = $null
        $appScriptAuthor = $null
        $appScriptDate = $null
        $appScriptVersion = $null
        $appFileToCheck = $null
        $appRevision = $null
        $appLang = $null
        $appArch = $null
        $appVersion = $null
        $appName = $null
        $appVendor = $null
        $cmAppDescription = $null
        $cmAllowUserInteraction = $null
        #endregion ----------------------------------------

        # add temp object to arraylist
        [void]$appInfoObj.add($tmpAppObj)

        
    } # end ForEach-Object
    Write-CMTraceLog -Message "Validation done!"

    if($validationFailedGlobal)
    {
        $gridViewTitle = "ERRORS happend! See log for more details. Please validate application properties and click okay to import the selected apps!"
        Open-LogWithCmTrace -FilePath $global:logFile
    }
    else 
    {
        $gridViewTitle = "Please validate application properties and click okay to import the selected apps!"       
    }

    <#
        # getting list of object properties if needed
        $propertyNames = $appInfoObj | Get-Member | Where-Object {$_.MemberType -eq 'NoteProperty'} | Select-Object Name
        $propertyNames.name -join ','
    #>

    # The order in which the properties are shown in the Grid-View
    $propertyOrder = ("Validation",
        "appVendor",
        "appName",
        "appVersion",
        "appArch",        
        "appLang",        
        "appRevision",
        "appFileToCheck",
        "appScriptAuthor",
        "appScriptDate",
        "appScriptVersion",
        "cmAppEstimatedInstallTime",
        "cmAppMaxAllowedRuntime",
        "cmAllowUserInteraction",
        "CMAppNameInConsole",
        "CMAppNameInSoftwareCenter",
        "CMCollectionName_Install",
        "CMCollectionName_Uninstall",        
        "FileFullName",     
        "CMAppContentSourcePath",        
        "cmAppIconFile",
        "InstallRegistryPath",
        "UninstallRegistryPath",
        "WQLQueryAdGroupName",
        "cmAppDescription"
    )

    [array]$selectedAppsToImport = $appInfoObj | Select-Object -Property $propertyOrder | Out-GridView -Title $gridViewTitle -OutputMode Multiple
    #endregion getting list of all Deploy-Application.ps1 files available
    
    #region import apps
    if($selectedAppsToImport)
    {
        Write-CMTraceLog -Message "$($selectedAppsToImport.Count) apps selected for import" # count not available if just one result
        
        #region connect to ConfigMgr site
        $SiteCode = Get-CMSiteCode -ProviderMachineName $ProviderMachineName
        if(-NOT ($SiteCode))
        {
            Write-CMTraceLog -Message "Could not get SiteCode" -Type Error
            Exit-ScriptExecution -startLocation $startLocation
        }
        # Customizations
        $initParams = @{}
        #$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
        #$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

        # Do not change anything below this line

        # Import the ConfigurationManager.psd1 module
        Write-CMTraceLog -Message "Loading ConfigMgr Cmdlets"
        if(-NOT (Get-Module ConfigurationManager)) 
        {
            Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams
        }
        if(-NOT (Get-Module ConfigurationManager))
        {
            Write-CMTraceLog -Message "ConfigurationManager module not loaded" -Type Error
            Exit-ScriptExecution -startLocation $startLocation
        }

        # Connect to the site's drive if it is not already present
        if(-NOT (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) 
        {
            New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
        }

        
        # Set the current location to be the site code.
        Write-CMTraceLog -Message "Setting location to the following sitecode: $($SiteCode):\"
        try
        {
            Set-Location "$($SiteCode):\" @initParams
        }
        catch
        {
            Write-CMTraceLog -Message "Could not set SiteCode" -Type Error
            Exit-ScriptExecution -startLocation $startLocation
        }
        #endregion

        #region check sccm folders
        if(-NOT(Test-CMFolderPath -SiteCode $SiteCode -ProviderMachineName $ProviderMachineName -FolderPath $cmCollectionFolder))
        {
            Write-CMTraceLog -Message "CM folder does not exist or connection not possible: `"$cmCollectionFolder`"" -Type Error
            Exit-ScriptExecution -startLocation $startLocation            
        }

        if(-NOT(Test-CMFolderPath -SiteCode $SiteCode -ProviderMachineName $ProviderMachineName -FolderPath $cmApplicationFolder))
        {
            Write-CMTraceLog -Message "CM folder does not exist or connection not possible: `"$cmApplicationFolder`"" -Type Error
            Exit-ScriptExecution -startLocation $startLocation            
        }
        #endregion

        #region check current incremental collection count
        if($UseIncrementalCollectionUpdates -ieq 'true')
        {
            switch (Get-CMIncrementalCollectionRefreshCount -SiteCode $SiteCode -ProviderMachineName $ProviderMachineName)
            {
                0 
                {
                    Write-CMTraceLog -Message "Could not detect incremental collection count. Please check your collections and stick to the best practices." -Type Warning
                    Write-CMTraceLog -Message "https://docs.microsoft.com/en-us/mem/configmgr/core/clients/manage/collections/best-practices-for-collections" -Type Warning
                } 

                
                {$_ -gt 200} 
                {
                    Write-CMTraceLog -Message "Too many collections set for incremental update. Schould be max 200 is: $_" -Type Warning
                    Write-CMTraceLog -Message "https://docs.microsoft.com/en-us/mem/configmgr/core/clients/manage/collections/best-practices-for-collections" -Type Warning
                }
            }

        }
        #endregion

        #region getting next availabe collection variables
        if($useCollectionVariables -ieq 'true')
        {

            $paramSplatting = @{
                SiteCode = $SiteCode
                ProviderMachineName = $ProviderMachineName
                cmCollectionVariableStartSuffix = 3
                dynamicAppVariableBaseName = $dynamicAppVariableBaseName 
                variableCount = ($selectedAppsToImport.Count)
            }
            [array]$availableCollectionVariables = Get-CMNextAvailableCollectionVariableNames @paramSplatting
              
                                                                                     
            if($availableCollectionVariables)
            {
                Write-CMTraceLog -Message "Generated $($availableCollectionVariables.Count) collection variable/s starting with `"$($dynamicAppVariableBaseName)`" which are not yet in use"
            }
            else
            {
                Write-CMTraceLog -Message "   Error could not get collection variables" -Type Error
                Exit-ScriptExecution -startLocation $startLocation
            }
        }
        #endregion
        
        #region actually importing stuff
        $collectionVariableCounter = 0
        foreach($appItem in $selectedAppsToImport)
        {
            if($appItem.Validation -eq 'Passed')
            {
                Write-CMTraceLog -Message "Starting import process for: `"$($appItem.CMAppNameInConsole)`"..."

                # check if app exists
                if(Get-CMApplication -Fast -Name ($appItem.CMAppNameInConsole))
                {
                    Write-CMTraceLog -Message "   App: `"$($appItem.CMAppNameInConsole)`" already exists. Skipping!" -Type Warning
                    Continue # with look   
                }

                
                # check if install collection exists
                if(Get-CMCollection -Name ($appItem.CMCollectionName_Install))
                {
                    Write-CMTraceLog -Message "   Collection: `"$($appItem.CMCollectionName_Install)`" already exists. Skipping!" -Type Warning
                    Continue # with look 
                }

                # check if install collection exists
                if(Get-CMCollection -Name ($appItem.CMCollectionName_Uninstall))
                {
                    Write-CMTraceLog -Message "   Collection: `"$($appItem.CMCollectionName_Uninstall)`" already exists. Skipping!" -Type Warning
                    Continue # with look 
                }

                # create app
                try
                {
                    Write-CMTraceLog -Message "   Creating app: $($appItem.CMAppNameInConsole)"
                    #-IconLocationFile
                    $paramSplatting = [ordered]@{
                        Name = ($appItem.CMAppNameInConsole)
                        LocalizedName = ($appItem.CMAppNameInSoftwareCenter)
                        Description = "Packaged by: $($appItem.appScriptAuthor) Imported via: $($global:scriptName). Any changes should be made in a new app and imported again to avoid inconsistencies."
                        Publisher = ($appItem.appVendor)
                        SoftwareVersion = ($appItem.appVersion)
                        ReleaseDate = (get-date)
                        AutoInstall = $true
                    }

                    if(-NOT($appItem.CMAppIconFile -eq ""))
                    {
                        $paramSplatting.add("IconLocationFile", "$($appItem.cmAppIconFile)")
                    }


                    $null = New-CMApplication @paramSplatting
                }
                catch
                {
                    Write-CMTraceLog -Message "   Error creating app" -Type Error
                    Write-CMTraceLog -Message "   $($error[0].Exception)" -Type Error
                    Continue
                }
                
                # create deploymentype
                try
                {
                    Write-CMTraceLog -Message "   Creating deploymenttype"
                    [string]$cmDeploymentTypeName = "$($appItem.CMAppNameInConsole) Install"

                    # Create detection logic either as built-in fucntions or use a PowerShell script
                    if ($useScriptDetectionLogic -ieq 'false')
                    {
                        # Create detection clause for file existence
                        $paramSplatting = [ordered]@{
                            Path = ($appItem.appFileToCheck | Split-Path -Parent)
                            FileName = ($appItem.appFileToCheck | Split-Path -Leaf)
                        }
                        if ($appItem.appFileToCheck -imatch 'Program Files \(x86\)')
                        {
                            $detectionClauseFile = New-CMDetectionClauseFile @paramSplatting -Existence -Is64Bit
                        }
                        else 
                        {
                            $detectionClauseFile = New-CMDetectionClauseFile @paramSplatting -Existence 
                        }
                        $detectionClauseFileLogicalName = $detectionClauseFile.Setting.LogicalName

                        # Create detection clause for registry path existence
                        $paramSplatting = [ordered]@{
                            Hive = "LocalMachine"
                            KeyName = ($appItem.InstallRegistryPath -replace 'HKLM\:\\','')
                        }
                        $detectionClauseRegistry = New-CMDetectionClauseRegistryKey @paramSplatting -Existence
                        $detectionClauseRegistryLogicalName = $detectionClauseRegistry.Setting.LogicalName

                        $paramSplatting = [ordered]@{
                            DeploymentTypeName = $cmDeploymentTypeName
                            InstallCommand = $appDefaultInstallCommand
                            ApplicationName = ($appItem.CMAppNameInConsole)
                            ContentLocation = ($appitem.CMAppContentSourcePath)
                            UninstallCommand = $appDefaultUninstallCommand
                            MaximumRuntimeMins = ($appitem.cmAppMaxAllowedRuntime)
                            EstimatedRuntimeMins = ($appitem.cmAppEstimatedInstallTime)
                            InstallationBehaviorType = "InstallForSystem"
                            LogonRequirementType =  "WhereOrNotUserLoggedOn"
                            UserInteractionMode = "Normal"
                            AddDetectionClause = $detectionClauseFile, $detectionClauseRegistry
                            #GroupDetectionClauses = $detectionClauseFileLogicalName, $detectionClauseRegistryLogicalName # Grouping of detection not required at the moment
                            DetectionClauseConnector = @{LogicalName=$detectionClauseFileLogicalName;Connector='and'}
                        }
                    }
                    else 
                    {
                        [string]$cmScriptText = "if((Test-Path '$($appItem.InstallRegistryPath)') -and (Test-Path '$($appItem.appFileToCheck)')) {Write-Host 'Installed'}"

                        $paramSplatting = [ordered]@{
                            DeploymentTypeName = $cmDeploymentTypeName
                            InstallCommand = $appDefaultInstallCommand
                            ApplicationName = ($appItem.CMAppNameInConsole)
                            ContentLocation = ($appitem.CMAppContentSourcePath)
                            UninstallCommand = $appDefaultUninstallCommand
                            MaximumRuntimeMins = ($appitem.cmAppMaxAllowedRuntime)
                            EstimatedRuntimeMins = ($appitem.cmAppEstimatedInstallTime)
                            InstallationBehaviorType = "InstallForSystem"
                            LogonRequirementType =  "WhereOrNotUserLoggedOn"
                            UserInteractionMode = "Normal"
                            ScriptLanguage = "PowerShell"
                            ScriptText = $cmScriptText
                        }
                    }

                    # Add parameter if user iteraction should be allowed
                    if ($cmAllowUserInteraction -ieq 'true')
                    {
                        $paramSplatting.add("RequireUserInteraction", $true)
                    }

                    $null = Add-CMScriptDeploymentType @paramSplatting -EnableBranchCache
                }
                catch
                {
                    Write-CMTraceLog -Message "   Error creating deploymenttype" -Type Error
                    Write-CMTraceLog -Message "   $($error[0].Exception)" -Type Error
                    Continue
                }
                #>
                

                # remove revision histroy
                Write-CMTraceLog -Message "   Removing ApplicationRevisionHistory"
                try
                {
                    $newAppObject = Get-CMApplication -Fast -Name ($appItem.CMAppNameInConsole)
                    Get-CMApplication -Fast -Name ($appItem.CMAppNameInConsole) | Get-CMApplicationRevisionHistory | Where-Object {$_.IsLatest -eq $false} | Remove-CMApplicationRevisionHistory -Force
                }
                Catch
                {
                    Write-CMTraceLog -Message "   Error: Removing ApplicationRevisionHistory failed!" -Type Error
                    Write-CMTraceLog -Message "   $($error[0].Exception)" -Type Error   
                    Continue                 
                }

                # (move app)

                # distribute app
                Write-CMTraceLog -Message "   Distribute App to DPs"
                try
                {
                    if($cmDistributionPointList -contains 'All')
                    {
                        # get list of DPs
                        $cmCurrentDPs = Get-CMDistributionPoint | Select-Object NetworkOSPath -ExpandProperty NetworkOSPath
                        $cmDistributionPointList = $cmCurrentDPs.Replace('\\','')
                    }

                    foreach($cmDP in $cmDistributionPointList)
                    {
                        $newAppObject | Start-CMContentDistribution -DistributionPointName $cmDP
                    }

                }
                catch
                {
                    Write-CMTraceLog -Message "   Error: Distribute App to DPs failed! Will proceed with process..." -Type Error
                    Write-CMTraceLog -Message "   $($error[0].Exception)" -Type Error 
                }

                Write-CMTraceLog -Message "   Move Application to `"$cmApplicationFolder`""
                try
                {
                    $null = $newAppObject | Move-CMObject -FolderPath $cmApplicationFolder
                }
                catch
                {
                    Write-CMTraceLog -Message "   Error: Move Application failed!" -Type Error
                    Write-CMTraceLog -Message "   $($error[0].Exception)" -Type Error   
                    Continue                      
                }

                # create collection and move
                Write-CMTraceLog -Message "   Create Collection `"$($appItem.CMCollectionName_Install)`""
                try
                {
                    $cmCollectionFolderPath = "{0}:{1}" -f $SiteCode, $cmCollectionFolder
                    
                    $paramSplatting = [ordered]@{
                        CollectionType = "Device"
                        LimitingCollectionId = $cmLimitingCollectionID
                        Name = ($appItem.CMCollectionName_Install)
                    }

                    if($UseIncrementalCollectionUpdates -ieq 'true')
                    {
                        $paramSplatting.add("RefreshType", "Continuous")
                    }
                    else
                    {
                        # Periodic - will set the default 7 day schedule
                        # None - will completely deactivate the schedule
                        $paramSplatting.add("RefreshType", "Periodic")
                    }

                    $newCollectionObject = New-CMCollection @paramSplatting

                }
                Catch
                {
                    Write-CMTraceLog -Message "   Error: Create Collection failed!" -Type Error
                    Write-CMTraceLog -Message "   $($error[0].Exception)" -Type Error   
                    Continue                 
                }

                Write-CMTraceLog -Message "   Move Collection to `"$cmCollectionFolderPath`""
                try
                {
                    $paramSplatting = [ordered]@{
                        FolderPath = "$cmCollectionFolderPath"
                        ObjectId = ($newCollectionObject.CollectionID)
                    }
                    $null = Move-CMObject @paramSplatting
                }
                catch
                {
                    Write-CMTraceLog -Message "   Error: Move Collection failed!" -Type Error
                    Write-CMTraceLog -Message "   $($error[0].Exception)" -Type Error   
                    Continue                      
                }

                # create AD group query rule
                Write-CMTraceLog -Message "   Create Collection query rule"
                try
                {
                    $cmWQLQueryADGroupName = ($appItem.WQLQueryAdGroupName)
                    $cmWQLQuery = ("select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.SystemGroupName in {0}" -f $cmWQLQueryADGroupName)
                    
                    $paramSplatting = [ordered]@{
                        CollectionId = ($newCollectionObject.CollectionID)
                        QueryExpression = $cmWQLQuery
                        RuleName = ('AD Group {0} {1}' -f ($appItem.appVendor), ($appItem.appName))
                    }

                    $null = Add-CMDeviceCollectionQueryMembershipRule @paramSplatting
                }
                catch
                {
                    Write-CMTraceLog -Message "   Error: Create Collection query rule!" -Type Error
                    Write-CMTraceLog -Message "   $($error[0].Exception)" -Type Error   
                    Continue 
                }


                # add task sequence variable to collection
                if($useCollectionVariables -ieq 'true')
                {
                    try
                    {
                        $cmCollVariableName = $availableCollectionVariables[$collectionVariableCounter] # pick variable from array
                        $collectionVariableCounter++

                        Write-CMTraceLog -Message "   Create Collection variable `"$cmCollVariableName`""
                        
                        $paramSplatting = [ordered]@{
                            VariableName = $cmCollVariableName
                            CollectionName = ($newCollectionObject.Name)
                            Value = ($appItem.CMAppNameInConsole)
                        }                         
                        
                        $null = New-CMDeviceCollectionVariable @paramSplatting
                            
                    }
                    catch
                    {
                        Write-CMTraceLog -Message "   Error: Create Collection variable failed!" -Type Error
                        Write-CMTraceLog -Message "   $($error[0].Exception)" -Type Error   
                        Continue 
                    }
                }
                

                # create deployment
                Write-CMTraceLog -Message "   Create deployment"
                try
                {
                    $paramSplatting = [ordered]@{
                        CollectionName = ($newCollectionObject.Name)
                        Name = ($appItem.CMAppNameInConsole)
                        ApprovalRequired = $False
                        DeployAction = "Install"
                        DeployPurpose = "Available"
                        TimeBaseOn = "LocalTime"
                    }
                    $null = New-CMApplicationDeployment @paramSplatting
                }
                catch
                {
                    Write-CMTraceLog -Message "   Error: Create deployment failed!" -Type Error
                    Write-CMTraceLog -Message "   $($error[0].Exception)" -Type Error   
                    Continue 
                }

            }
            else 
            {
                Write-CMTraceLog -Message "Skipping app: `"$($appItem.CMAppNameInConsole)`" because of validation errors! See log for details." -Type Warning
            }
        } # end of: foreach($appItem in $selectedAppsToImport)
        #endregion
    }
    else # of if($selectedAppsToImport)
    {
        Write-CMTraceLog -Message 'Nothing selected'  
    }
    #endregion import apps
}
else # of if($selectedappDeploymentFiles) 
{
    Write-CMTraceLog -Message 'Nothing selected'    
}
<#
# for testing only
    Get-CMCollection | Where-Object {$_.Name -match '\d{8} Install'} | Remove-CMCollection
    Get-CMApplication -Fast | Where-Object {$_.LocalizedDisplayName  -match '\d{8}'} | Remove-CMApplication -Force
#>

Exit-ScriptExecution -startLocation $startLocation
#endregion Main Script