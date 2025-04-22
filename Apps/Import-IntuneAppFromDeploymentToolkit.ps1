#requires -module Microsoft.Graph.Devices.CorporateManagement
#requires -module Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Import an Intune app from a deployment toolkit script.

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

    This script will import an Intune app from a deployment toolkit script.
    The script will read the $adtSession and $IntuneAppMetadata hashtables from the script file.
    The script will then create an IntuneWin file from the folder specified in the $IntuneAppMetadata hashtable.
    The script will then upload the IntuneWin file to Intune and create the app in Intune.

    $adtSession is the default hashtable in the Invoke-AppDeployToolkit.ps1 script.
    $IntuneAppMetadata is a custom hashtable that is added to the script file to add relevant data for Intune.
    Example of $IntuneAppMetadata hashtable:
    
    $IntuneAppMetadata = @{
        # If IntuneInstallCommand has no value the import script default install command will be used. This is not the App install 
        # command but the command to run AppDeploymentToolkit 
        IntuneInstallCommand = "powershell.exe -ExecutionPolicy Bypass -file .\Invoke-ServiceUI.ps1 -DeploymentType 'Install' -AllowRebootPassThru"
        
        # If IntuneUninstallCommand has no value the import script default uninstall command will be used. This is not the App 
        # uninstall command but the command to run AppDeploymentToolkit 
        IntuneUninstallCommand = "powershell.exe -ExecutionPolicy Bypass -file .\Invoke-ServiceUI.ps1 -DeploymentType 'Uninstall' -AllowRebootPassThru"
        
        # Set AllowAvailableUninstal to either true or false to allow available uninstalls in Intune
        AllowAvailableUninstall = $True
        
        # Set one or more app categories for Company Portal filtering
        IntuneAppCategory = ('A','B','C')
        
        # If InstallAssignmentEntraIDGroupName has a value, the import script will assign the app to this group
        InstallAssignmentEntraIDGroupName = "IN-App1-Install"
        
        # Install assignment intent can either be availabe or required
        InstallAssignmentIntent = "Required"
        
        # InstallAssignmentStartDate can have a specific date in the format of "yyyy-MM-dd hh:mm" or now value. 
        # No value means the import script will use the runtime of the script as startdatetime. 
        InstallAssignmentStartDate = "2023-11-30 14:00"	

        # Description of the app in Intune. This is the description that will be shown in the Company Portal
        IntuneAppDescription = "This is a test app for Intune"

        # Either System or User. This is the account that will be used to run the app via Intune.
        IntuneRunAsAccount = "System"
    }


.PARAMETER AppBasePath
    The base path where the deployment toolkit scripts are located.

.PARAMETER AppOutFolder
    The output folder where the IntuneWin files will be saved.

.PARAMETER Win32ContentPrepToolUri
    The URI to download the IntuneWinAppUtil.exe tool.

#>

param
(
    [Parameter(Mandatory=$false)]
    [string]$AppBasePath = "C:\IntuneApps",
    [Parameter(Mandatory = $false)]
    [string]$AppOutFolder = "C:\IntuneApps\IntuneWinFiles",
    [Parameter(Mandatory = $false)]
    [Switch]$RemoveIntuneWinFileAfterUpload,
    [Parameter(Mandatory = $false)]
    [string]$Win32ContentPrepToolUri = 'https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe',
    [Parameter(Mandatory = $false)]
    [string]$ClientID, 
    [Parameter(Mandatory = $false)]
    [string]$TenantID 
)


#region Function Get-HashtablesFromScript
<#
.SYNOPSIS
    Function to read the hashtable data from an Invoke-AppDeployToolkit.ps1 script.

.DESCRIPTION
    The script will read the $adtSession and $IntuneAppMetadata hashtables from the script file.
    $adtSession is a default hashtable in the Invoke-AppDeployToolkit.ps1 script.
    $IntuneAppMetadata is a custom hashtable that is added to the script file to add relevant data for Intune.

.PARAMETER FilePath
    The path to the Invoke-AppDeployToolkit.ps1 script file.

.EXAMPLE
    Get-HashtablesFromScript -FilePath "C:\IntuneApps\7-Zip-20241217\Invoke-AppDeployToolkit.ps1"

    This example will read the $adtSession and $IntuneAppMetadata hashtables from the Invoke-AppDeployToolkit.ps1 script file.
#>
function Get-HashtablesFromScript 
{
    param 
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$FilePath
    )

    process 
    {
        # Read the content of the file
        $fileContent = Get-Content -Path $FilePath -Raw

        # Extract the first hashtable called $adtSession
        $adtSessionPattern = '(?s)\$adtSession\s*=\s*@\{.*?\}'
        $adtSessionMatch = [regex]::Match($fileContent, $adtSessionPattern)
        if ($adtSessionMatch.Success) 
        {
            # we will now have the content of the hashtable in $adtSessionContent 
            # and will use Invoke-Expression to convert it to an actual hashtable we can use in this script
            $adtSessionContent = $adtSessionMatch.Value
            Invoke-Expression -Command $adtSessionContent -OutVariable adtSession
        } 
        else 
        {
            Write-Error "Failed to extract `$adtSession hashtable."
            return
        }

        if ($null -eq $adtSession) 
        {
            Write-Error "Failed to extract `$adtSession hashtable."
            return
        }

        # Extract the second hashtable called $IntuneAppMetadata
        $intuneAppMetadataPattern = '(?s)\$IntuneAppMetadata\s*=\s*@\{.*?\}'
        $intuneAppMetadataMatch = [regex]::Match($fileContent, $intuneAppMetadataPattern)
        if ($intuneAppMetadataMatch.Success) 
        {
            # we will now have the content of the hashtable in $IntuneAppMetadata
            # and will use Invoke-Expression to convert it to an actual hashtable we can use in this script
            $intuneAppMetadataContent = $intuneAppMetadataMatch.Value
            Invoke-Expression -Command $intuneAppMetadataContent -OutVariable intuneAppMetadata
        } 
        else 
        {
            Write-Error "Failed to extract `$IntuneAppMetadata hashtable."
            return
        }

        if ($null -eq $intuneAppMetadata) 
        {
            Write-Error "Failed to extract `$IntuneAppMetadata hashtable."
            return
        }

        # Combine the hashtables into a single PSCustomObject
        $combinedObject = [PSCustomObject][ordered]@{
            # Add id to the object to be able to identify it later
            ID = (New-Guid).Guid
            FilePath = $FilePath
        } 

        # Add properties from $adtSession to $combinedObject
        foreach ($key in $adtSession.Keys) 
        {
            if ($key -ieq 'DeployAppScriptFriendlyName')
            {
                # Skip this key as it is not needed in the combined object and will only contain the name of this function
            }
            else 
            {
                $combinedObject | Add-Member -MemberType NoteProperty -Name "ADT-$($key)" -Value $adtSession[$key]
            }
        }

        # Add properties from $intuneAppMetadata to $combinedObject
        foreach ($key in $intuneAppMetadata.Keys) 
        {
            $combinedObject | Add-Member -MemberType NoteProperty -Name "IN-$($key)" -Value $intuneAppMetadata[$key]
        }


        return $combinedObject
    }
}
#endregion

#region New-IntuneWinFile
<#
.SYNOPSIS
    Function to create an IntuneWin file from a folder.

.DESCRIPTION
    The function will create an IntuneWin file from a folder using the IntuneWinAppUtil.exe tool.
    The function will download the tool if it is not present in the output folder.
    The function will return the path to the created IntuneWin file.

.PARAMETER AppOutFolder
    The output folder where the IntuneWin file will be saved.

.PARAMETER AppFolder
    The folder containing the application files.

.PARAMETER AppSetupFile
    The setup file for the application.

.PARAMETER AppName
    The name of the application.

.PARAMETER Win32ContentPrepToolUri
    The URI to download the IntuneWinAppUtil.exe tool.

.EXAMPLE
    New-IntuneWinFile -AppOutFolder "C:\IntuneApps\IntuneWinFiles" -AppFolder "C:\IntuneApps\7-Zip-20241217" -AppSetupFile "7z2104-x64.exe" -AppName "7-Zip" -Win32ContentPrepToolUri "https://..."
#>
Function New-IntuneWinFile
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $true)]
        [string]$AppOutFolder,
        [Parameter(Mandatory = $true)]
        [string]$AppFolder,
        [Parameter(Mandatory = $true)]
        [string]$AppSetupFile,
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $true)]
        [string]$Win32ContentPrepToolUri        
    )

    process 
    {
        # Lets check if the tools folder exists
        $toolsFolder = '{0}\Tools' -f $AppOutFolder
        if (-NOT (Test-Path $toolsFolder))
        {
            New-Item -ItemType Directory -Path $toolsFolder -Force | Out-Null
        }

        # Lets check if the IntuneWinAppUtil.exe is present
        $contentPrepToolFullName = '{0}\IntuneWinAppUtil.exe' -f $toolsFolder
        if (Test-Path $contentPrepToolFullName)
        {
            #Write-CMTraceLog -Message "IntuneWinAppUtil.exe already present. No need to download"
            Write-Host "IntuneWinAppUtil.exe already present. No need to download" -ForegroundColor Green
        }
        else 
        {    
            try 
            {
                #Write-CMTraceLog -Message "Will try to download IntuneWinAppUtil.exe"
                Invoke-WebRequest -UseBasicParsing -Method Get -Uri $Win32ContentPrepToolUri -OutFile $contentPrepToolFullName -ErrorAction SilentlyContinue

                if (-not (Test-Path $contentPrepToolFullName))
                {
                    #Write-CMTraceLog -Message "IntuneWinAppUtil.exe download failed" -Severity Error
                    Write-Host "IntuneWinAppUtil.exe download failed" -ForegroundColor Red
                }
            }
            catch 
            {
                #Write-CMTraceLog -Message "IntuneWinAppUtil.exe download failed" -Severity Error
                #Write-CMTraceLog -Message "$($_)"
                #Write-CMTraceLog -Message "You can also download the tool to: `"$ExportFolderTools`" manually"
                #Write-CMTraceLog -Message "From: `"$Win32ContentPrepToolUri`""
                #Write-CMTraceLog -Message "End of script"
                Write-Host "IntuneWinAppUtil.exe download failed" -ForegroundColor Red
                Write-Host "$($_)" -ForegroundColor Red
                Write-Host "You can also download the tool to: `"$AppOutFolder\Tools`" manually" -ForegroundColor Yellow
                Write-Host "From: `"$Win32ContentPrepToolUri`"" -ForegroundColor Yellow
                Write-Host "End of script" -ForegroundColor Yellow
                Exit 1
            }
        }
      
        # Making sure the output folder exists
        if (-NOT (Test-Path $AppOutFolder))
        {
            New-Item -ItemType Directory -Path $AppOutFolder -Force | Out-Null   
        }

        try 
        {
            #Write-CMTraceLog -Message "Will run IntuneWinAppUtil.exe to pack content. Might take a while depending on content size"
            Write-Host "Will run IntuneWinAppUtil.exe to pack content. Might take a while depending on content size" -ForegroundColor Green
            $arguments = @(
                '-s'
                "`"$AppSetupFile`""
                '-c'
                "`"$AppFolder`""
                '-o'
                "`"$AppOutFolder`""
                '-q'
            )

            $ProcessStartInfo = New-Object System.Diagnostics.ProcessStartInfo
            $ProcessStartInfo.FileName = $contentPrepToolFullName
            $ProcessStartInfo.RedirectStandardError = $true
            $ProcessStartInfo.RedirectStandardOutput = $true
            $ProcessStartInfo.UseShellExecute = $false
            $ProcessStartInfo.Arguments = $arguments
            $startProcess = New-Object System.Diagnostics.Process
            $startProcess.StartInfo = $ProcessStartInfo
            $startProcess.Start() | Out-Null
            $startProcess.WaitForExit()
            $stdout = $startProcess.StandardOutput.ReadToEnd()
            $stderr = $startProcess.StandardError.ReadToEnd()

            $intunewinLogName = '{0}\{1}.log' -f $AppOutFolder, $AppName
            If($stdout -imatch 'File (?<filepath>.*) has been generated successfully')
            {
                #Write-CMTraceLog -Message "File created successfully"
                Write-Host "File created successfully" -ForegroundColor Green
                $intuneWinFullName = $Matches.filepath -replace "'" -replace '"'
                
                <#
                $newName = '{0}.intunewin' -f $AppName
                $intuneWinFullNameFinal = '{0}\{1}' -f ($intuneWinFullName | Split-Path -Parent), $newName
                
                # Remove the file if it already exists from a previous run
                if (Test-Path $intuneWinFullNameFinal)
                {
                    Remove-Item -Path $intuneWinFullNameFinal -Force
                }

                Rename-Item -Path $intuneWinFullName -NewName $newName -Force
                #>
            }
            else 
            {
                #Write-CMTraceLog -Message "IntuneWinAppUtil failed to create the intunewin file." -Severity Error 
                Write-Host "IntuneWinAppUtil failed to create the intunewin file." -ForegroundColor Red
            } 
            $stdout | Out-File -FilePath $intunewinLogName -Force -Encoding unicode -ErrorAction SilentlyContinue
            $stderr | Out-File -FilePath $intunewinLogName -Append -Encoding unicode -ErrorAction SilentlyContinue

        }
        catch 
        {
            #Write-CMTraceLog -Message "IntuneWinAppUtil failed to create the intunewin file." -Severity Error 
            #Write-CMTraceLog -Message "$($_)"#
            Write-Host "IntuneWinAppUtil failed to create the intunewin file." -ForegroundColor Red
            Write-Host "$($_)" -ForegroundColor Red
            return $null
        }
        #Write-CMTraceLog -Message "More details can be found in the log here: `"$($intunewinLogName)`""
        Write-Host "More details can be found in the log here: `"$($intunewinLogName)`"" -ForegroundColor Yellow

        return $intuneWinFullName
    }

}
#endregion


#region Test-ProbableFileEncoding
<#
.SYNOPSIS
    Test the probable encoding of a file.

.DESCRIPTION
    The function reads the first few bytes of a file to determine the probable encoding of the file.

.PARAMETER FilePath
    The path to the file to test.

.EXAMPLE
    Test-ProbableFileEncoding -FilePath "C:\Temp\file.txt"

    This example will test the probable encoding of the file located at "C:\Temp\file.txt".

.OUTPUTS
    The function returns the probable encoding of the file.
    Either 'UTF-8', 'UTF-8-BOM', 'UTF-16 LE BOM', 'UTF-16 BE BOM', or 'Unknown'.
#>
function Test-ProbableFileEncoding
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    process 
    {
        $fileContentBytes = [System.IO.File]::ReadAllBytes($FilePath)
        $detectedEncoding = 'Unknown'

        # Check for UTF-8 BOM
        if ($fileContentBytes.Length -ge 3 -and $fileContentBytes[0] -eq 0xEF -and $fileContentBytes[1] -eq 0xBB -and $fileContentBytes[2] -eq 0xBF) 
        {
            $detectedEncoding = 'UTF-8-BOM'
        }
        # Check for UTF-16 Little Endian BOM
        elseif ($fileContentBytes.Length -ge 2 -and $fileContentBytes[0] -eq 0xFF -and $fileContentBytes[1] -eq 0xFE) 
        {
            $detectedEncoding = 'UTF-16 LE BOM'
        }
        # Check for UTF-16 Big Endian BOM
        elseif ($fileContentBytes.Length -ge 2 -and $fileContentBytes[0] -eq 0xFE -and $fileContentBytes[1] -eq 0xFF) 
        {
            $detectedEncoding = 'UTF-16 BE BOM'
        }              
        else 
        {
            try 
            {
                [System.Text.Encoding]::UTF8.GetString($fileContentBytes) | Out-Null
                $detectedEncoding = 'UTF-8'
            }
            catch{}
        }
        return $detectedEncoding
    }
}
#endregion

#region New-AppIconContent
function New-AppIconContent
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$IconPath
    )

    process 
    {
        # Check if the icon file exists
        if (-not (Test-Path $IconPath)) 
        {
            Write-Error "Icon file not found: $IconPath"
            return $null
        }

        # Read the icon file and convert it to a Base64 string
        $iconBytes = [System.IO.File]::ReadAllBytes($IconPath)
        $iconBase64 = [System.Convert]::ToBase64String($iconBytes)

        # Create the icon content object
        $iconContent = @{
            "@odata.type" = '#microsoft.graph.win32LobApp'
            "largeIcon" = @{ 
                "type" = "image/png"
                "value" = $iconBase64
            }
        }

        return $iconContent
    }
}
#endregion New-AppIconContent

#region Intune PowerShell sample functions
#
# https://github.com/microsoft/mggraph-intune-samples/blob/main/LOB_Application/Win32_Application_Add.ps1
#
#***************************************************************************************************************#
#***************************************************************************************************************#
#***************************************************************************************************************#


<#
.SYNOPSIS
Uploads a Win32 app to Intune.

.DESCRIPTION
This function uploads a Win32 app to Intune. The script extracts the detection.xml file from the .intunewin file and uses the information to create the app in Intune. The script then uploads the .intunewin file to Azure Storage and commits the file to the service.

.PARAMETER SourceFile
The path to the .intunewin file.

.PARAMETER displayName
The display name of the app. If not specified, the script uses the Name from the detection.xml file.

.PARAMETER version
The version of the app.

.PARAMETER publisher
The publisher of the app.

.PARAMETER description
The description of the app.

.PARAMETER Rules
An array of rules to apply to the app. You can use the New-FileSystemRule, New-ProductCodeRule, New-RegistryRule, New-ScriptDetectionRule, and New-ScriptRequirementRule functions to create the rules.

.PARAMETER returnCodes
An array of return codes to apply to the app. You can use the Get-DefaultReturnCodes and New-ReturnCode functions to create the return codes.

.PARAMETER installCommandLine
The command line to install the app. Required for EXE files.

.PARAMETER uninstallCommandLine
The command line to uninstall the app. Required for EXE files.

.PARAMETER RunAsAccount
The account to run the app as. Valid values are 'system' or 'user'.

.PARAMETER DeviceRestartBehavior
The device restart behavior for the app. Valid values are 'basedOnReturnCode', 'allow', 'suppress', 'force'.

.PARAMETER IconPath
The path to the icon file for the app. The icon file must be in PNG format.

.EXAMPLE
# Uploads a .exe Win32 app to Intune using the default return codes and a file system rule.
$returnCodes = Get-DefaultReturnCodes
$Rules = @()
$Rules += New-FileSystemRule -ruleType detection -check32BitOn64System $false -operationType exists -operator notConfigured -comparisonValue $null -fileOrFolderName "code.exe" -path 'C:\Program Files\Microsoft VS Code'
Invoke-Win32AppUpload -SourceFile "C:\IntuneApps\vscode\VSCodeSetup-x64-1.93.1.intunewin" -displayName "VS Code" -publisher "Microsoft" -description "VS Code" -Rules $Rules -returnCodes $returnCodes -installCommandLine "VSCodeSetup-x64-1.93.1.exe /VERYSILENT /MERGETASKS=!runcode" -uninstallCommandLine "C:\Program Files\Microsoft VS Code\unins000.exe /VERYSILENT" -DeviceRestartBehavior "basedOnReturnCode" -RunAsAccount "system" 

.EXAMPLE
# Uploads a .msi Win32 app to Intune using the default return codes and a product code rule.
$returnCodes = Get-DefaultReturnCodes
$Rules = @()
$Rules += New-FileSystemRule -ruleType detection -operator notConfigured -check32BitOn64System $false -operationType exists -comparisonValue $null -fileOrFolderName "firefox.exe" -path 'C:\Program Files\Mozilla Firefox\firefox.exe'
$Rules += New-ProductCodeRule -ruleType detection -productCode "{3248F0A8-6813-4B6F-8C3A-4B6C4F512345}" -productVersionOperator equal -productVersion "130.0"
Invoke-Win32AppUpload -SourceFile "C:\IntuneApps\Firefox\Firefox_Setup_130.0.intunewin" -displayName "Firefox" -publisher "Mozilla" -returnCodes $returnCodes -description "Firefox browser" -Rules $Rules -RunAsAccount "system" -DeviceRestartBehavior "suppress" 

.EXAMPLE
# Uploads a Win32 app to Intune using the default return codes, a script detection rule, a script requirement rule, and a registry rule, and a registry rule.
$returnCodes = Get-DefaultReturnCodes
$Rules = @()
$Rules += New-ScriptRequirementRule -ScriptFile "E:\VSCodeRequirement.ps1" -DisplayName "VS Code Requirement" -EnforceSignatureCheck $false -RunAs32Bit $false -RunAsAccount "system" -OperationType "integer" -Operator "equal" -ComparisonValue "0"
$Rules += New-ScriptDetectionRule -ScriptFile "E:\VSCodeDetection.ps1" -EnforceSignatureCheck $false -RunAs32Bit $false 
$Rules += New-RegistryRule -ruleType detection -keyPath "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\xyz" -valueName "DisplayName" -operationType string -operator equal -comparisonValue "VSCode"
Invoke-Win32AppUpload -displayName "VS Code" -SourceFile "C:\IntuneApps\vscode\VSCodeSetup-x64-1.93.1.intunewin" -publisher "Microsoft" -description "VS Code (script detection)" -RunAsAccount "system" -Rules $Rules -returnCodes $returnCodes -InstallCommandLine "VSCodeSetup-x64-1.93.1.exe /VERYSILENT /MERGETASKS=!runcode" -UninstallCommandLine "C:\Program Files\Microsoft VS Code\unins000.exe /VERYSILENT" -DeviceRestartBehavior "basedOnReturnCode"
#>
function Invoke-Win32AppUpload {
    [cmdletbinding()]
    param
    (
        [parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceFile,

        [parameter(Mandatory = $false, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$displayName,

        [parameter(Mandatory = $true, Position = 3)]
        [ValidateNotNullOrEmpty()]
        [string]$publisher,

        [parameter(Mandatory = $true, Position = 4)]
        [ValidateNotNullOrEmpty()]
        [string]$description,

        [parameter(Mandatory = $false, Position = 5)]
        [string]$version,

        [parameter(Mandatory = $true, Position = 6)]
        [ValidateNotNullOrEmpty()]
        $Rules,

        [parameter(Mandatory = $true, Position = 7)]
        [ValidateNotNullOrEmpty()]
        $returnCodes,

        [parameter(Mandatory = $false, Position = 8)]
        [string]$installCommandLine,

        [parameter(Mandatory = $false, Position = 9)]
        [string]$uninstallCommandLine,

        [parameter(Mandatory = $false, Position = 10)]
        [ValidateSet('system', 'user')]
        [string]$RunAsAccount,

        [parameter(Mandatory = $true, Position = 11)]
        [ValidateSet('basedOnReturnCode', 'allow', 'suppress', 'force')]
        [string]$DeviceRestartBehavior,

        [parameter(Mandatory = $false, Position = 12)]
        [string]$IconPath,

        [parameter(Mandatory = $false, Position = 13)]
        [switch]$AllowAvailableUninstall

    )
    try	{

        if ($null -eq $AllowAvailableUninstall) {
            $AllowAvailableUninstall = $false
        }

        # Check if the source file exists
        Write-Host "Testing if SourceFile '$SourceFile' Path is valid..." -ForegroundColor Yellow
        Test-SourceFile "$SourceFile"

        Write-Host "Creating JSON data to pass to the service..." -ForegroundColor Yellow

        # Extract the detection.xml file from the .intunewin file
        $DetectionXML = Get-IntuneWinXML -SourceFile "$SourceFile" -fileName "detection.xml" -removeitem $true

        # If displayName input don't use Name from detection.xml file
        if ($displayName) { $DisplayName = $displayName }
        else { $DisplayName = $DetectionXML.ApplicationInfo.Name }
         
        $FileName = $DetectionXML.ApplicationInfo.FileName
 
        $SetupFileName = $DetectionXML.ApplicationInfo.SetupFile
 
        # Check if the file is an MSI or EXE
        $Ext = [System.IO.Path]::GetExtension($SetupFileName)

        if ((($Ext).contains("msi") -or ($Ext).contains("Msi")) -and (!$installCommandLine -or !$uninstallCommandLine)) {
            # MSI
            $MsiExecutionContext = $DetectionXML.ApplicationInfo.MsiInfo.MsiExecutionContext
            $MsiPackageType = "DualPurpose"

            if ($MsiExecutionContext -eq "System") { $MsiPackageType = "PerMachine" }
            elseif ($MsiExecutionContext -eq "User") { $MsiPackageType = "PerUser" }
 
            $MsiProductCode = $DetectionXML.ApplicationInfo.MsiInfo.MsiProductCode
            $MsiProductVersion = $DetectionXML.ApplicationInfo.MsiInfo.MsiProductVersion
            $MsiPublisher = $DetectionXML.ApplicationInfo.MsiInfo.MsiPublisher
            $MsiRequiresReboot = $DetectionXML.ApplicationInfo.MsiInfo.MsiRequiresReboot
            $MsiUpgradeCode = $DetectionXML.ApplicationInfo.MsiInfo.MsiUpgradeCode
            
            if ($MsiRequiresReboot -eq "false") { $MsiRequiresReboot = $false }
            elseif ($MsiRequiresReboot -eq "true") { $MsiRequiresReboot = $true }
 
            $mobileAppBody = GetWin32AppBody `
                -AllowAvailableUninstall $AllowAvailableUninstall `
                -MSI `
                -displayName "$DisplayName" `
                -Version $version `
                -publisher "$publisher" `
                -description $description `
                -filename $FileName `
                -SetupFileName "$SetupFileName" `
                -RunAsAccount "$RunAsAccount" `
                -MsiPackageType $MsiPackageType `
                -MsiProductCode $MsiProductCode `
                -MsiProductName $displayName `
                -MsiProductVersion $MsiProductVersion `
                -MsiPublisher $MsiPublisher `
                -MsiRequiresReboot $MsiRequiresReboot `
                -MsiUpgradeCode $MsiUpgradeCode `
                -DeviceRestartBehavior "$DeviceRestartBehavior"
        }
        else {
            $mobileAppBody = GetWin32AppBody `
                -AllowAvailableUninstall $AllowAvailableUninstall `
                -EXE -displayName "$DisplayName" `
                -Version $version `
                -publisher "$publisher" `
                -description $description `
                -filename $FileName `
                -SetupFileName "$SetupFileName" `
                -RunAsAccount $RunAsAccount `
                -DeviceRestartBehavior "$DeviceRestartBehavior" `
                -installCommandLine $installCommandLine `
                -uninstallCommandLine $uninstallCommandLine
        }

        # Add the rules and return codes to the JSON body
        if ($Rules) {
            $mobileAppBody.Add("rules", @($Rules))
        }
 
        if ($returnCodes) {
            $mobileAppBody.Add("returnCodes", @($returnCodes))
        }
        else {
            Write-Warning "Intunewin file requires ReturnCodes to be specified"
            Write-Warning "If you want to use the default ReturnCode run 'Get-DefaultReturnCodes'"
            break
        }

        ($mobileAppBody | ConvertTo-Json)

        # Create the application in Intune and get the application ID
        Write-Host "Creating application in Intune..." -ForegroundColor Yellow
        #$MobileApp = New-MgDeviceAppManagementMobileApp -BodyParameter ($mobileAppBody | ConvertTo-Json)
        $MobileApp = New-MgDeviceAppManagementMobileApp -BodyParameter $mobileAppBody
        $mobileAppId = $MobileApp.id

        # Create a new content version for the application
        Write-Host "Creating Content Version in the service for the application..." -ForegroundColor Yellow
        $ContentVersion = New-MgDeviceAppManagementMobileAppAsWin32LobAppContentVersion -MobileAppId $mobileAppId -BodyParameter @{}

        # Extract the encryption information from the .intunewin file
        Write-Host "Retrieving encryption information from .intunewin file." -ForegroundColor Yellow
        $encryptionInfo = @{}
        $encryptionInfo.encryptionKey = $DetectionXML.ApplicationInfo.EncryptionInfo.EncryptionKey
        $encryptionInfo.macKey = $DetectionXML.ApplicationInfo.EncryptionInfo.macKey
        $encryptionInfo.initializationVector = $DetectionXML.ApplicationInfo.EncryptionInfo.initializationVector
        $encryptionInfo.mac = $DetectionXML.ApplicationInfo.EncryptionInfo.mac
        $encryptionInfo.profileIdentifier = "ProfileVersion1"
        $encryptionInfo.fileDigest = $DetectionXML.ApplicationInfo.EncryptionInfo.fileDigest
        $encryptionInfo.fileDigestAlgorithm = $DetectionXML.ApplicationInfo.EncryptionInfo.fileDigestAlgorithm

        $fileEncryptionInfo = @{}
        $fileEncryptionInfo.fileEncryptionInfo = $encryptionInfo

        # Extracting encrypted file
        $IntuneWinFile = Get-IntuneWinFile "$SourceFile" -fileName "$FileName"
        [int64]$Size = $DetectionXML.ApplicationInfo.UnencryptedContentSize
        $EncrySize = (Get-Item "$IntuneWinFile").Length

        # Create a new file entry in Azure for the upload
        $ContentVersionId = $ContentVersion.Id
        $fileBody = Get-AppFileBody -name "$FileName" -size $Size -sizeEncrypted $EncrySize
        $fileBody = $fileBody | ConvertTo-Json 

        # Create a new file entry in Azure for the upload and get the file ID
        Write-Host "Creating a new file entry in Azure for the upload..." -ForegroundColor Yellow
        $ContentVersionFile = New-MgDeviceAppManagementMobileAppAsWin32LobAppContentVersionFile -MobileAppId $mobileAppId -MobileAppContentId $ContentVersionId -BodyParameter $fileBody
        $ContentVersionFileId = $ContentVersionFile.id
        
        # Get the file URI for the upload
        $fileUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$mobileAppId/microsoft.graph.win32LobApp/contentVersions/$contentVersionId/files/$contentVersionFileId"

        # Upload the file to Azure Storage
        Write-Host "Uploading the file to Azure Storage..." -ForegroundColor Yellow
        $file = WaitForFileProcessing $fileUri "AzureStorageUriRequest"
        [UInt32]$BlockSizeMB = 1
        UploadFileToAzureStorage $file.azureStorageUri $IntuneWinFile $BlockSizeMB

        # Commit the file to the service
        $params = $fileEncryptionInfo | ConvertTo-Json
        Write-Host "Committing the file to the service..." -ForegroundColor Yellow
        #Wait 5 seconds before committing the file
        Start-Sleep -Seconds 5

        # Commit the file to the service
        Invoke-MgCommitDeviceAppManagementMobileAppMicrosoftGraphWin32LobAppContentVersionFile -MobileAppId $mobileAppId -MobileAppContentId $ContentVersionId -MobileAppContentFileId $ContentVersionFileId -BodyParameter $params

        # Wait for the file to be processed
        Write-Host "Waiting for the file to be processed..." -ForegroundColor Yellow
        $file = WaitForFileProcessing $fileUri "CommitFile"

        $params = @{
            "@odata.type"           = "#microsoft.graph.win32LobApp"
            "committedContentVersion" = "1"
        }

        $params = $params | ConvertTo-Json

        # Update the application with the new content version
        Write-Host "Updating the application with the new content version..." -ForegroundColor Yellow
        # The cmdlet resulted in: "Cannot convert the literal '1' to the expected type 'Edm.String'.
        # Wil use invoke-mgraphrequest instead
        #Update-MgDeviceAppManagementMobileApp -MobileAppId $mobileAppId -BodyParameter $params

        $paramSplatting = @{
            "Method" = 'PATCH'
            "Uri" = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($mobileAppId)"
            "Body" = $params
            "ContentType" = "application/json"
        }
        Invoke-MgGraphRequest @paramSplatting

        # Update the application with the correct display version
        $params = @{
            "@odata.type"   = "#microsoft.graph.win32LobApp"
            "displayVersion"  = "$($version)"
        }

        $params = $params | ConvertTo-Json 
        
        $paramSplatting = @{
            "Method" = 'PATCH'
            "Uri" = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($mobileAppId)"
            "Body" = $params
            "ContentType" = "application/json"
        }
        Invoke-MgGraphRequest @paramSplatting
        
        # Update the application with the correct display version
        Write-Host "Updating the application with the correct display version..." -ForegroundColor Yellow
        #Update-MgDeviceAppManagementMobileApp -MobileAppId $mobileAppId -BodyParameter $params    

        if (-NOT ([string]::IsNullOrEmpty($IconPath))) {

            $params = New-AppIconContent -IconPath $IconPath
            $params = $params | ConvertTo-Json
            # Update the application with an icon
            Write-Host "Updating the application with an icon..." -ForegroundColor Yellow
            #Update-MgDeviceAppManagementMobileApp -MobileAppId $mobileAppId -BodyParameter $params  

            $paramSplatting = @{
                "Method" = 'PATCH'
                "Uri" = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($mobileAppId)"
                "Body" = $params
                "ContentType" = "application/json"
            }
            Invoke-MgGraphRequest @paramSplatting

        }

        # Return the application ID
        #Write-Host "Application created successfully." -ForegroundColor Green
        #Write-Host "Application Details:"

        return (Get-MgDeviceAppManagementMobileApp -MobileAppId $mobileAppId)
    }
    catch {
        Write-Host -ForegroundColor Red "Aborting with exception: $($_.Exception.ToString())"
       
        # In the event that the creation of the app record in Intune succeeded, but processing/file upload failed, you can remove the comment block around the code below to delete the app record.
        # This will allow you to re-run the script without having to manually delete the incomplete app record.
        # Note: This will only work if the app record was successfully created in Intune.

        
        if ($mobileAppId) {
            Write-Host "Removing the incomplete application record from Intune..." -ForegroundColor Yellow
            Remove-MgDeviceAppManagementMobileApp -MobileAppId $mobileAppId
        }
        
        break
    }
}

<#
.SYNOPSIS
Creates a new file system rule.

.DESCRIPTION
This function creates a new file system rule that you can use to specify a detection or requirement for a Win32 app.

.PARAMETER ruleType
The type of rule. Valid values are 'detection' or 'requirement'.

.PARAMETER path
The path to the file or folder.

.PARAMETER fileOrFolderName
The name of the file or folder.

.PARAMETER check32BitOn64System
Specifies whether to check for 32-bit on a 64-bit system.

.PARAMETER operationType
The value type returned by the script. Valid values are 'notConfigured', 'exists', 'modifiedDate', 'createdDate', 'version', 'sizeInMB', 'doesNotExist', 'sizeInBytes', 'appVersion'.

.PARAMETER operator
The operator for the detection script output comparison. Valid values are 'notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual'.

.PARAMETER comparisonValue
The value to compare the script output to.

.EXAMPLE
# Creates a new file system rule for a Win32 app.
New-FileSystemRule -ruleType detection -path 'C:\Program Files\Microsoft VS Code' -fileOrFolderName 'code.exe' -check32BitOn64System $false -operationType exists -operator notConfigured -comparisonValue $null
#>
function New-FileSystemRule() {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateSet("detection", "requirement")]
        [string]$ruleType,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$path,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$fileOrFolderName,
    
        [parameter(Mandatory = $true)]
        [bool]$check32BitOn64System,
    
        [parameter(Mandatory = $false)]
        [ValidateSet("notConfigured", "exists", "modifiedDate", "createdDate", "version", "sizeInMB", "doesNotExist", "sizeInBytes", "appVersion")]
        [string]$operationType,

        [parameter(Mandatory = $false)]
        [ValidateSet("notConfigured", "equal", "notEqual", "greaterThan", "greaterThanOrEqual", "lessThan", "lessThanOrEqual")]
        [string]$operator = "notConfigured",

        [parameter(Mandatory = $false)]
        $comparisonValue
    )

    $Rule = @{}

    if ($null -ne $comparisonValue -and $comparisonValue -ne "") {
        $Rule.comparisonValue = $comparisonValue
    }
    else {
        $Rule.comparisonValue = $null
    }

    $Rule."@odata.type" = "#microsoft.graph.win32LobAppFileSystemRule" 
    $Rule.ruleType = $ruleType
    $Rule.path = $path
    $Rule.fileOrFolderName = $fileOrFolderName
    $Rule.check32BitOn64System = $check32BitOn64System
    $Rule.operationType = $operationType
    $Rule.operator = $operator

    return $Rule
}

<#
.SYNOPSIS
Creates a new product code rule.

.DESCRIPTION
This function creates a new product code rule that you can use to specify a detection or requirement for a Win32 app.

.PARAMETER ruleType
The type of rule. Valid values are 'detection' or 'requirement'.

.PARAMETER productCode
The product code.

.PARAMETER productVersionOperator
The operator for the detection script output comparison. Valid values are 'notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual'.

.PARAMETER productVersion
The value to compare the script output to.

.EXAMPLE
# Creates a new product code rule for a Win32 app.
New-ProductCodeRule -ruleType detection -productCode "{3248F0A8-6813-4B6F-8C3A-4B6C4F512345}" -productVersionOperator equal -productVersion "130.0"
#>
function New-ProductCodeRule {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateSet('detection', 'requirement')]
        [string]$ruleType,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$productCode,

        [parameter(Mandatory = $true)]
        [ValidateSet('notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual')]
        [string]$productVersionOperator,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$productVersion
    )

    $Rule = @{}
    $Rule."@odata.type" = "#microsoft.graph.win32LobAppProductCodeRule"
    $Rule.ruleType = $ruleType
    $Rule.productCode = $productCode
    $Rule.productVersionOperator = $productVersionOperator
    $Rule.productVersion = $productVersion

    return $Rule
}

<#
.SYNOPSIS
Creates a new registry rule.

.DESCRIPTION
This function creates a new registry rule that you can use to specify a detection or requirement for a Win32 app.

.PARAMETER ruleType
The type of rule. Valid values are 'detection' or 'requirement'.

.PARAMETER keyPath
The registry key path.

.PARAMETER valueName
The registry value name.

.PARAMETER operationType
The operation data type (data type returned by the script). Valid values are 'notConfigured', 'exists', 'doesNotExist', 'string', 'integer', 'float', 'version'.

.PARAMETER operator
The operator for the detection script output comparison. Valid values are 'notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual'.

.PARAMETER comparisonValue
The value to compare the script output to.

.EXAMPLE
# Creates a new registry rule for a Win32 app.
New-RegistryRule -ruleType detection -keyPath "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\xyz" -valueName "DisplayName" -operationType string -operator equal -comparisonValue "VSCode"
#>
function New-RegistryRule {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateSet('detection', 'requirement')]
        [string]$ruleType,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$keyPath,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$valueName,

        [parameter(Mandatory = $true)]
        [ValidateSet('notConfigured', 'exists', 'doesNotExist', 'string', 'integer', 'float', 'version')]
        [string]$operationType,

        [parameter(Mandatory = $true)]
        [ValidateSet('notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual')]
        [string]$operator,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$comparisonValue
    )

    $Rule = @{}
    $Rule."@odata.type" = "#microsoft.graph.win32LobAppRegistryRule"
    $Rule.ruleType = $ruleType
    $Rule.keyPath = $keyPath
    $Rule.valueName = $valueName
    $Rule.operationType = $operationType
    $Rule.operator = $operator
    $Rule.comparisonValue = $comparisonValue

    return $Rule
}

<#
.SYNOPSIS
Creates a new script detection rule.

.DESCRIPTION
This function creates a new script detection rule that you can use to specify a detection for a Win32 app.

.PARAMETER ScriptFile
The path to the script file.

.PARAMETER EnforceSignatureCheck
Specifies whether to enforce signature check.

.PARAMETER RunAs32Bit
Specifies whether to run the script as 32-bit.

.EXAMPLE
# Creates a new script detection rule for a Win32 app.
New-ScriptDetectionRule -ScriptFile "E:\VSCodeDetection.ps1" -EnforceSignatureCheck $false -RunAs32Bit $false

.NOTES
This function only creates a script detection rule. To create a script requirement rule, use the New-ScriptRequirementRule function.
#>
function New-ScriptDetectionRule{
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptFile,

        [parameter(Mandatory = $true)]
        [bool]$EnforceSignatureCheck,

        [parameter(Mandatory = $true)]
        [bool]$RunAs32Bit

    )
    if (!(Test-Path "$ScriptFile")) {
        Write-Host "Could not find file '$ScriptFile'..." -ForegroundColor Red
        Write-Host "Script can't continue..." -ForegroundColor Red
        break
    }
        
    $ScriptContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$ScriptFile"))
        
    $Rule = @{}
    $Rule."@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptRule"
    $Rule.ruleType = "detection"
    $Rule.enforceSignatureCheck = $EnforceSignatureCheck
    $Rule.runAs32Bit = $RunAs32Bit
    $Rule.scriptContent = "$ScriptContent"
    $Rule.operationType = "notConfigured"
    $Rule.operator = "notConfigured"

    return $Rule
}

<#
.SYNOPSIS
Creates a new script requirement rule.

.DESCRIPTION
This function creates a new script requirement rule that you can use to specify a requirement for a Win32 app.

.PARAMETER ScriptFile
The path to the script file.

.PARAMETER DisplayName
The display name of the rule.

.PARAMETER EnforceSignatureCheck
Specifies whether to enforce signature check.

.PARAMETER RunAs32Bit
Specifies whether to run the script as 32-bit.

.PARAMETER RunAsAccount
The account to run the script as. Valid values are 'system' or 'user'.

.PARAMETER OperationType
The operation data type (data type returned by the script). Valid values are 'notConfigured', 'string', 'dateTime', 'integer', 'float', 'version', 'boolean'.

.PARAMETER Operator
The operator for the detection script output comparison. Valid values are 'notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual'.

.PARAMETER ComparisonValue
The value to compare the script output to.

.EXAMPLE
# Creates a new script requirement rule for a Win32 app.
New-ScriptRequirementRule -ScriptFile "E:\VSCodeRequirement.ps1" -DisplayName "VS Code Requirement" -EnforceSignatureCheck $false -RunAs32Bit $false -RunAsAccount "system" -OperationType "integer" -Operator "equal" -ComparisonValue "0"

.NOTES
This function only creates a script requirement rule. To create a script detection rule, use the New-ScriptDetectionRule function.
#>
function New-ScriptRequirementRule {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptFile,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [parameter(Mandatory = $true)]
        [bool]$EnforceSignatureCheck,

        [parameter(Mandatory = $true)]
        [bool]$RunAs32Bit,

        #Valid values are 'system' or 'user'
        [parameter(Mandatory = $true)]
        [ValidateSet('system', 'user')]
        [string]$RunAsAccount,

        [parameter(Mandatory = $true)]
        [ValidateSet('notConfigured', 'string', 'dateTime', 'integer', 'float', 'version', 'boolean')]
        [string]$OperationType,

        [parameter(Mandatory = $true)]
        [ValidateSet('notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual')]
        [string]$Operator,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComparisonValue
    )

    if (!(Test-Path "$ScriptFile")) {
        Write-Host "Could not find file '$ScriptFile'..." -ForegroundColor Red
        Write-Host "Script can't continue..." -ForegroundColor Red
        break
    }

    $ScriptContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$ScriptFile"))
        
    $Rule = @{}
    $Rule."@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptRule"
    $Rule.displayName = $DisplayName
    $Rule.ruleType = "requirement"
    $Rule.enforceSignatureCheck = $EnforceSignatureCheck
    $Rule.runAs32Bit = $RunAs32Bit
    $Rule.scriptContent = "$ScriptContent"
    $Rule.operationType = $OperationType
    $Rule.operator = $Operator
    $Rule.comparisonValue = $ComparisonValue
    $Rule.runAsAccount = $RunAsAccount

    return $Rule
}

<#
.SYNOPSIS
Creates a new return code object.

.DESCRIPTION
This function creates a new return code object that you can use to specify the return codes for a Win32 app.

.PARAMETER returnCode
The return code value.

.PARAMETER type
The type of return code. Valid values are 'success', 'softReboot', 'hardReboot

.EXAMPLE
# Creates a new return code object with a return code of 0 and a type of 'success'
New-ReturnCode -returnCode 0 -type 'success'
#>
function New-ReturnCode() {
    param
    (
        [parameter(Mandatory = $true)]
        [int]$returnCode,
        [parameter(Mandatory = $true)]
        [ValidateSet('success', 'softReboot', 'hardReboot', 'retry')]
        $type
    )

    @{"returnCode" = $returnCode; "type" = "$type" }
}

####################################################
# Function to wait for file processing to complete by polling the file upload state
<#
.SYNOPSIS
Waits for the file processing to complete by polling the file upload state.

.DESCRIPTION
This function waits for the file processing to complete by polling the file upload state. 
The function will check the file upload state every second for a maximum of 60 seconds.

.PARAMETER fileUri
The URI of the file to check.

.PARAMETER stage
The stage of the file processing to check.
#>
function WaitForFileProcessing {
    param(
        [parameter(Mandatory = $true)]
        [string]$fileUri,

        [parameter(Mandatory = $true)]
        [string]$stage
    )

    $attempts = 60
    $waitTimeInSeconds = 1
    $successState = "$($stage)Success"
    $pendingState = "$($stage)Pending"

    $file = $null
    while ($attempts -gt 0) {
        $file = Invoke-MgGraphRequest -Method GET -Uri $fileUri
        if ($file.uploadState -eq $successState) {
            break
        }
        elseif ($file.uploadState -ne $pendingState) {
            throw "File upload state is not success: $($file.uploadState)"
        }

        Start-Sleep $waitTimeInSeconds
        $attempts--
    }

    if ($null -eq $file) {
        throw "File request did not complete in the allotted time."
    }

    $file
}

####################################################
# Function to upload a file to Azure Storage using the SAS URI
<#
.SYNOPSIS
Uploads a file to Azure Storage using the SAS URI.

.DESCRIPTION
This function uploads a file to Azure Storage using the SAS URI. The function will upload the file in chunks of the specified size.

.PARAMETER sasUri
The SAS URI for the Azure Storage account.

.PARAMETER filepath
The path to the file to upload.

.PARAMETER blockSizeMB
The size of the block in MiB.
#>
function UploadFileToAzureStorage {
    param(
        [parameter(Mandatory = $true)]
        [string]$sasUri,

        [parameter(Mandatory = $true)]
        [string]$filepath,

        [parameter(Mandatory = $true)]
        [int]$blockSizeMB
    )

    # Chunk size in MiB
    $chunkSizeInBytes = (1024 * 1024 * $blockSizeMB)  

    # Read the whole file and find the total chunks.
    #[byte[]]$bytes = Get-Content $filepath -Encoding byte;
    # Using ReadAllBytes method as the Get-Content used alot of memory on the machine
    $fileStream = [System.IO.File]::OpenRead($filepath)
    $chunks = [Math]::Ceiling($fileStream.Length / $chunkSizeInBytes)

    # Upload each chunk.
    $ids = @()
    $cc = 1
    $chunk = 0
    while ($fileStream.Position -lt $fileStream.Length) {
        $id = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($chunk.ToString("0000")))
        $ids += $id

        $size = [Math]::Min($chunkSizeInBytes, $fileStream.Length - $fileStream.Position)
        $body = New-Object byte[] $size
        $fileStream.Read($body, 0, $size) > $null
        $totalBytes += $size

        Write-Progress -Activity "Uploading File to Azure Storage" -Status "Uploading chunk $cc of $chunks" -PercentComplete ($cc / $chunks * 100)
        $cc++

        UploadAzureStorageChunk $sasUri $id $body | Out-Null
        $chunk++
    }

    $fileStream.Close()
    Write-Progress -Completed -Activity "Uploading File to Azure Storage"

    # Finalize the upload.
    FinalizeAzureStorageUpload $sasUri $ids | Out-Null
}

####################################################
# Function to upload a chunk to Azure Storage
<#
.SYNOPSIS
Uploads a chunk to Azure Storage.

.DESCRIPTION
This function uploads a chunk to Azure Storage.

.PARAMETER sasUri
The SAS URI for the Azure Storage account.

.PARAMETER id
The block ID.

.PARAMETER body
The body of the request.
#>
function UploadAzureStorageChunk {
    param(
        [parameter(Mandatory = $true)]
        [string]$sasUri,

        [parameter(Mandatory = $true)]
        [string]$id,

        [parameter(Mandatory = $true)]
        [byte[]]$body
    )

    $uri = "$sasUri&comp=block&blockid=$id"
    $request = "PUT $uri"

    $headers = @{
        "x-ms-blob-type" = "BlockBlob"
        "Content-Type"   = "application/octet-stream"
    }

    try {
        Invoke-WebRequest -Headers $headers $uri -Method Put -Body $body | Out-Null
    }
    catch {
        Write-Host -ForegroundColor Red $request
        Write-Host -ForegroundColor Red $_.Exception.Message
        throw
    }
}

####################################################
# Function to finalize the Azure Storage upload
<#
.SYNOPSIS
Finalizes the Azure Storage upload.

.DESCRIPTION
This function finalizes the Azure Storage upload.

.PARAMETER sasUri
The SAS URI for the Azure Storage account.

.PARAMETER ids
The block IDs.
#>
function FinalizeAzureStorageUpload {
    param(
        [parameter(Mandatory = $true)]
        [string]$sasUri,

        [parameter(Mandatory = $true)]
        [string[]]$ids
    )
    $uri = "$sasUri&comp=blocklist"
    $request = "PUT $uri"

    $xml = '<?xml version="1.0" encoding="utf-8"?><BlockList>'
    foreach ($id in $ids) {
        $xml += "<Latest>$id</Latest>"
    }
    $xml += '</BlockList>'

    if ($logRequestUris) { Write-Host $request; }
    if ($logContent) { Write-Host -ForegroundColor Gray $xml; }

    $headers = @{
        "Content-Type" = "text/plain"
    }

    try {
        Invoke-WebRequest $uri -Method Put -Body $xml -Headers $headers
    }
    catch {
        Write-Host -ForegroundColor Red $request
        Write-Host -ForegroundColor Red $_.Exception.Message
        throw
    }
}

####################################################
# Function to construct the JSON body for a Win32 app
function GetWin32AppBody() {
    param
    (
        [parameter(Mandatory = $true, ParameterSetName = "MSI", Position = 1)]
        [Switch]$MSI,
    
        [parameter(Mandatory = $true, ParameterSetName = "EXE", Position = 1)]
        [Switch]$EXE,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$displayName,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$publisher,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$description,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$filename,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupFileName,
    
        [parameter(Mandatory = $true)]
        [ValidateSet('system', 'user')]
        [string]$RunAsAccount,

        [parameter(Mandatory = $true)]
        [ValidateSet('basedOnReturnCode', 'allow', 'suppress', 'force')]
        [string]$DeviceRestartBehavior,

        [parameter(Mandatory = $false)]
        [string]$Version,
    
        [parameter(Mandatory = $true, ParameterSetName = "EXE")]
        [ValidateNotNullOrEmpty()]
        $installCommandLine,
    
        [parameter(Mandatory = $true, ParameterSetName = "EXE")]
        [ValidateNotNullOrEmpty()]
        $uninstallCommandLine,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiPackageType,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiProductCode,
    
        [parameter(Mandatory = $false, ParameterSetName = "MSI")]
        $MsiProductName,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiProductVersion,
    
        [parameter(Mandatory = $false, ParameterSetName = "MSI")]
        $MsiPublisher,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiRequiresReboot,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiUpgradeCode,

        [parameter(Mandatory = $false)]
        [Bool]$AllowAvailableUninstall
    )
    
    if ($MSI) {
        $body = @{ "@odata.type" = "#microsoft.graph.win32LobApp" }
        $body.allowAvailableUninstall = $AllowAvailableUninstall
        $body.applicableArchitectures = "x64,x86"
        $body.description = $description
        $body.developer = ""
        $body.displayName = $displayName
        $body.displayVersion = $Version
        $body.fileName = $filename
        $body.installCommandLine = "msiexec /i `"$SetupFileName`""
        $body.installExperience = @{
            "runAsAccount"          = "$RunAsAccount"
            "deviceRestartBehavior" = $DeviceRestartBehavior 
        }
        $body.informationUrl = $null
        $body.isFeatured = $false
        $body.minimumSupportedOperatingSystem = @{"v10_1607" = $true }
        $body.msiInformation = @{
            "packageType"    = "$MsiPackageType"
            "productCode"    = "$MsiProductCode"
            "productName"    = "$MsiProductName"
            "productVersion" = "$MsiProductVersion"
            "publisher"      = "$MsiPublisher"
            "requiresReboot" = "$MsiRequiresReboot"
            "upgradeCode"    = "$MsiUpgradeCode"
            "@odata.type"    = "#microsoft.graph.win32LobAppMsiInformation"
        }
        $body.notes = ""
        $body.owner = ""
        $body.privacyInformationUrl = $null
        $body.publisher = $publisher
        $body.runAs32bit = $false
        $body.setupFilePath = $SetupFileName
        $body.uninstallCommandLine = "msiexec /x `"$MsiProductCode`""
    }
    elseif ($EXE) {
        $body = @{ "@odata.type" = "#microsoft.graph.win32LobApp" }
        $body.description = $description
        $body.developer = ""
        $body.displayName = $displayName
        $body.displayVersion = $Version
        $body.fileName = $filename
        $body.installCommandLine = $installCommandLine
        $body.installExperience = @{
            "runAsAccount"          = $RunAsAccount
            "deviceRestartBehavior" = $DeviceRestartBehavior 
        }
        $body.informationUrl = $null
        $body.isFeatured = $false
        $body.minimumSupportedOperatingSystem = @{"v10_1607" = $true }
        $body.msiInformation = $null
        $body.notes = ""
        $body.owner = ""
        $body.privacyInformationUrl = $null
        $body.publisher = $publisher
        $body.runAs32bit = $false
        $body.setupFilePath = $SetupFileName
        $body.uninstallCommandLine = $uninstallCommandLine
    }

    $body
}

####################################################
# Function to test if the source file exists
Function Test-SourceFile {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $SourceFile
    )
    try {
    
        if (!(test-path "$SourceFile")) {
            Write-Host
            Write-Host "Source File '$sourceFile' doesn't exist..." -ForegroundColor Red
            throw
        }
    }
    
    catch {
        Write-Host -ForegroundColor Red $_.Exception.Message
        Write-Host
        break
    }
}

####################################################
# Function to get the default return codes    
function Get-DefaultReturnCodes() {
    @{"returnCode" = 0; "type" = "success" }, `
    @{"returnCode" = 1707; "type" = "success" }, `
    @{"returnCode" = 3010; "type" = "softReboot" }, `
    @{"returnCode" = 1641; "type" = "hardReboot" }, `
    @{"returnCode" = 1618; "type" = "retry" }
    
}

####################################################
# Function to extract the IntuneWin XML file from the .intunewin file
Function Get-IntuneWinXML() {
    param
    (
        [Parameter(Mandatory = $true)]
        $SourceFile,
    
        [Parameter(Mandatory = $true)]
        $fileName,
    
        [Parameter(Mandatory = $false)]
        [bool]$removeitem = $true
    )
    
    Test-SourceFile "$SourceFile"
    
    $Directory = [System.IO.Path]::GetDirectoryName("$SourceFile")
    
    Add-Type -Assembly System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead("$SourceFile")
    
    $zip.Entries | Where-Object { $_.Name -like "$filename" } | ForEach-Object {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "$Directory\$filename", $true)
    }
    
    $zip.Dispose()
    
    [xml]$IntuneWinXML = Get-Content "$Directory\$filename"
    
    return $IntuneWinXML
    
    if ($removeitem -eq $true) { remove-item "$Directory\$filename" }
}

####################################################
# Function to extract the IntuneWin file from the .intunewin file
Function Get-IntuneWinFile() {
    param
    (
        [Parameter(Mandatory = $true)]
        $SourceFile,
    
        [Parameter(Mandatory = $true)]
        $fileName,
    
        [Parameter(Mandatory = $false)]
        [string]$Folder = "win32"
    )
    
    $Directory = [System.IO.Path]::GetDirectoryName("$SourceFile")
    
    if (!(Test-Path "$Directory\$folder")) {
        $null = New-Item -ItemType Directory -Path "$Directory" -Name "$folder" -Force
    }
    
    Add-Type -Assembly System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead(("$SourceFile"))
    $zip.Entries | Where-Object { $_.Name -like "$filename" } | ForEach-Object {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "$Directory\$folder\$filename", $true)
    }
    
    $zip.Dispose()
    
    return "$Directory\$folder\$filename"
    
    if ($removeitem -eq $true) { remove-item "$Directory\$filename" }
}

####################################################
# Function to create a new app file body containing the file and encryption information
function Get-AppFileBody{
    param(
        [parameter(Mandatory = $true)]
        [string]$name,

        [parameter(Mandatory = $true)]
        [int64]$size,

        [parameter(Mandatory = $true)]
        [int64]$sizeEncrypted,

        [parameter(Mandatory = $false)]
        [string]$manifest
    )
    $body = @{ "@odata.type" = "#microsoft.graph.mobileAppContentFile" }
    $body.name = $name
    $body.size = $size
    $body.sizeEncrypted = $sizeEncrypted
    $body.manifest = if([string]::IsNullOrEmpty($manifest)) { $null } else { $manifest }
    $body.isDependency = $false
        
    $body
}



#***************************************************************************************************************#
#***************************************************************************************************************#
#***************************************************************************************************************#
#endregion

#******************************************************************#
#region                   Main script
#******************************************************************#
$arrayOfDisplayedProperties = @(
    'ADT-AppName',
    'ADT-AppVendor',
    'ADT-AppVersion',
    'ADT-InstallTitle',
    'ADT-InstallName',
    'ADT-AppLang',	
    'IN-IntuneInstallCommand',
    'IN-IntuneUninstallCommand',
    'IN-AllowAvailableUninstall',
    'IN-IntuneAppCategory',
    'IN-InstallAssignmentEntraIDGroupName',
    'IN-InstallAssignmentIntent',
    'IN-InstallAssignmentStartDate',
    'IN-IntuneAppDescription',
    'IN-IntuneRunAsAccount',
    'FilePath',
    'ID'
)

# Lets get all the Invoke-AppDeployToolkit.ps1 files in the AppBasePath to extract the hashtable data from them
$fileList = Get-ChildItem -Path $AppBasePath -Depth 1 -File -Filter "Invoke-AppDeployToolkit.ps1"

# Read the hashtable data from the script files to be able to select which apps to import.
# The data will be displayed in an Out-GridView for selection.
[array]$appList = $fileList.FullName | Get-HashtablesFromScript

$selectionTitle = "Intune App Import Tool. Select apps to import."
[array]$selectedApps = $appList | Select-Object -Property $arrayOfDisplayedProperties | Out-GridView -Title $selectionTitle -OutputMode Multiple

if ($null -eq $selectedApps)
{
    Write-Host "No apps selected for import." -ForegroundColor Yellow
    return
}
else 
{
    # We need to authenticate first
    if (-NOT ([string]::IsNullOrEmpty($ClientID)) -and -NOT ([string]::IsNullOrEmpty($TenantID)))
    {
        Write-Host "Authenticating to Microsoft Graph with ClientID `"$ClientID`"" -ForegroundColor Green
        $authParams = @{
            ClientId     = $ClientID
            TenantId     = $TenantID
        }

        Connect-MgGraph @authParams -ErrorAction Stop
    }
    else 
    {
        Connect-MgGraph # using the default authentication method
    }     
    
    # Do for each selected app
    foreach ($selectedApp in $selectedApps)
    {
        Write-Host "Importing app $($selectedApp.'ADT-AppName') version $($selectedApp.'ADT-AppVersion')..." -ForegroundColor Green

        # Lets do some basic checks
        # Check if the app has a Detection.ps1 file in its folder
        $detectionScriptPath = '{0}\Detection.ps1' -f ($selectedApp.FilePath | Split-Path -Parent)
        if (-not (Test-Path -Path $detectionScriptPath))
        {
            Write-Warning "No Detection.ps1 file found in $($selectedApp.FilePath)."
            Write-Warning "Will skip import of this app."
            continue
        }
        else 
        {
            $testResult = Test-ProbableFileEncoding -FilePath $detectionScriptPath
            if ($testResult -ine 'UTF-8-BOM')
            {
                Write-Warning "The Detection.ps1 file is saved with `"$($testResult)`" encoding. Intune requires UTF-8-BOM encoding. You can use Notepad++ and save it with UTF-8-BOM encoding"
                Write-Warning "Will skip import of this app."
                #Continue
            }
            else 
            {
                Write-Host "Will use `"$($detectionScriptPath)`" for detection logic." -ForegroundColor Green
            }
        }

        # Check if the script has a Requirements.ps1 file in its folder
        $requirementsScriptPath = '{0}\Requirements.ps1' -f ($selectedApp.FilePath | Split-Path -Parent)
        if (-not (Test-Path -Path $requirementsScriptPath))
        {
            Write-Warning "No Requirements.ps1 file found in $($selectedApp.FilePath). Will use default requirements for this app."
        }
        else 
        {
            $testResult = Test-ProbableFileEncoding -FilePath $requirementsScriptPath
            if ($testResult -ine 'UTF-8-BOM')
            {
                Write-Warning "The Requirements.ps1 file is saved with `"$($testResult)`" encoding. Intune requires UTF-8-BOM encoding. Use Notepad++ and save it with UTF-8-BOM encoding"
                Write-Warning "Will skip import of this app." 
                Continue
            }
            else 
            {
                Write-Host "Will use `"$($requirementsScriptPath)`" for requirements logic." -ForegroundColor Green
            }
        }

        # Check if the script has an Icon.png file in its folder
        $iconPath = '{0}\Icon.png' -f ($selectedApp.FilePath | Split-Path -Parent)
        if (-not (Test-Path -Path $iconPath))
        {
            Write-Warning "No Icon.png file found in $($selectedApp.FilePath)."
            $iconDetected = $false
        }
        else 
        {
            $iconDetected = $true
        }

        # Step 1: Create the Intunwin file
        $paramSplatting = @{
            AppOutFolder = $AppOutFolder
            AppFolder = $selectedApp.FilePath | Split-Path -Parent
            AppSetupFile = $selectedApp.FilePath | Split-Path -Leaf
            AppName = $selectedApp.'ADT-AppName'
            Win32ContentPrepToolUri = $Win32ContentPrepToolUri
        }

        $filePath = New-IntuneWinFile @paramSplatting
        if ($null -eq $filePath)
        {
            Write-Host "Failed to create the IntuneWin file for $($selectedApp.'ADT-AppName'). Skipping import of this app." -ForegroundColor Red
            continue
        }

        $Rules = @()
        #$Rules += New-ScriptRequirementRule -ScriptFile "E:\VSCodeRequirement.ps1" -DisplayName "VS Code Requirement" -EnforceSignatureCheck $false -RunAs32Bit $false -RunAsAccount "system" -OperationType "integer" -Operator "equal" -ComparisonValue "0"
        $Rules += New-ScriptDetectionRule -ScriptFile $detectionScriptPath -EnforceSignatureCheck $false -RunAs32Bit $false 
        #$Rules += New-RegistryRule -ruleType detection -keyPath "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\xyz" -valueName "DisplayName" -operationType string -operator equal -comparisonValue "VSCode"

        # Validate input parameters
        if ([string]::IsNullOrEmpty($selectedApp.'IN-IntuneAppDescription'))
        {
            $selectedApp.'IN-IntuneAppDescription' = 'App imported from AppDeployToolkit'
            Write-Host "Will use `"$($selectedApp.'IN-IntuneAppDescription')`" as description" -ForegroundColor Green
        }
        
        if ([string]::IsNullOrEmpty($selectedApp.'IN-IntuneRunAsAccount'))
        {
            $selectedApp.'IN-IntuneRunAsAccount' = "system"
            Write-Host "Will use `"$($selectedApp.'IN-IntuneRunAsAccount')`" as RunAsAccount" -ForegroundColor Green
        }
        
        if ($selectedApp.'IN-IntuneRunAsAccount' -inotin ("system","user"))
        {
            Write-Host "Invalid RunAsAccount provided. Has to be system or user. Fallback to: `"system`"" -ForegroundColor Green
            $selectedApp.'IN-IntuneRunAsAccount' = "system"
        }

        if ($null -eq $selectedApp.'IN-AllowAvailableUninstall')
        {
            $selectedApp.'IN-AllowAvailableUninstall' = $false
            Write-Host "Will use `"$($selectedApp.'IN-AllowAvailableUninstall')`" as AllowAvailableUninstall" -ForegroundColor Green
        }


        $appParamSplatting = @{
            DisplayName = $selectedApp.'ADT-AppName'
            SourceFile = $filePath
            Publisher = $selectedApp.'ADT-AppVendor'
            Description = $selectedApp.'IN-IntuneAppDescription'
            RunAsAccount = $selectedApp.'IN-IntuneRunAsAccount'
            DeviceRestartBehavior = "basedOnReturnCode"
            InstallCommandLine = $selectedApp.'IN-IntuneInstallCommand'
            UninstallCommandLine = $selectedApp.'IN-IntuneUninstallCommand'
            Version = $selectedApp.'ADT-AppVersion'
            #Owner = ""
            IconPath = $null
            Rules = $Rules
            AllowAvailableUninstall = $selectedApp.'IN-AllowAvailableUninstall'
            ReturnCodes = Get-DefaultReturnCodes
        }

        if ($iconDetected)
        {
            $appParamSplatting.IconPath = $iconPath
        }
    
        $uploadedApp = $null
        $uploadedApp = Invoke-Win32AppUpload @appParamSplatting

        #Always remove the detection.xml file after upload
        Remove-Item -Path "$($filePath | Split-Path -Parent)\Detection.xml" -Force

        if ($RemoveIntuneWinFileAfterUpload)
        {
            Remove-Item -Path $filePath -Force            
        }

        if (-NOT ([string]::IsNullOrEmpty($uploadedApp.Id)))
        {
            Write-Host "App $($selectedApp.'ADT-AppName') uploaded successfully. App ID: $($uploadedApp.Id)" -ForegroundColor Green
        }
        else 
        {
            Write-Host "Failed to upload app $($selectedApp.'ADT-AppName')." -ForegroundColor Red
            continue
        }

        try 
        {
            if (-NOT ([string]::IsNullOrEmpty($selectedApp.'IN-InstallAssignmentEntraIDGroupName')))
            {
                Write-Host "Will search for group displayName `"$($selectedApp.'IN-InstallAssignmentEntraIDGroupName')`"" -ForegroundColor Green

                if ([string]::IsNullOrEmpty($selectedApp.'IN-InstallAssignmentIntent'))
                {
                    Write-Host "No InstallAssignmentIntent provided. Will use: `"Available`")`"" -ForegroundColor Green
                    $selectedApp.'IN-InstallAssignmentIntent' = "Available"
                }
                # nstallAssignmentIntent has to be required or available
                if ($selectedApp.'IN-InstallAssignmentIntent' -inotin ("Available","Required"))
                {
                    Write-Host "Invalid InstallAssignmentIntent provided. Has to be Available or Required. Fallback to: `"Available`"" -ForegroundColor Green
                    $selectedApp.'IN-InstallAssignmentIntent' = "Available"
                }

                if (-NOT ([string]::IsNullOrEmpty($selectedApp.'IN-InstallAssignmentStartDate')))
                {
                    Write-Host "Will use `"$($selectedApp.'IN-InstallAssignmentStartDate')`" as start date" -ForegroundColor Green
                    $selectedApp.'IN-InstallAssignmentStartDate' = (Get-Date $selectedApp.'IN-InstallAssignmentStartDate').ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
                else 
                {
                    Write-Host "No InstallAssignmentStartDate provided. Will use: `"$((Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ"))`"" -ForegroundColor Green
                    $selectedApp.'IN-InstallAssignmentStartDate' = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                }

                $startTimeHash = $null
                if ($selectedApp.'IN-InstallAssignmentIntent' -ieq "Required")
                {
                    $startTimeHash = @{
                        startDateTime = $selectedApp.'IN-InstallAssignmentStartDate'
                        useLocalTime = $true
                        deadlineDateTime = $selectedApp.'IN-InstallAssignmentStartDate'   
                    }
                }
                else 
                {
                    $startTimeHash = @{
                        startDateTime = $selectedApp.'IN-InstallAssignmentStartDate'
                    }
                }
            }
            else 
            {
                Write-Host "No Entra ID group name provided. Will skip deployment" -ForegroundColor Yellow
                continue
            }
      

            Write-Host "Will search for group displayName `"$($selectedApp.'IN-InstallAssignmentEntraIDGroupName')`"" -ForegroundColor Green
            #$group = Get-MgGroup -Filter "displayName eq '$($item.GroupName)'"
            $uri = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$($selectedApp.'IN-InstallAssignmentEntraIDGroupName')'"
            $groupResult = Invoke-MgGraphRequest -Uri $uri -Method Get -ErrorAction Stop -OutputType PSObject       
        }
        catch 
        {
            Write-Host "Failed to get group `"$($selectedApp.'IN-InstallAssignmentEntraIDGroupName')`". Skipping group" -ForegroundColor Yellow
            Write-Host "$($_)" -ForegroundColor Red
            continue
        }
    
        if ($groupResult.value.count -eq 0)
        {
            Write-Host "No group found with displayName `"$($selectedApp.'IN-InstallAssignmentEntraIDGroupName')`". Skipping group" -ForegroundColor Yellow
            continue
        }
        elseif ($groupResult.value.count -gt 1) 
        {
            Write-Host "Multiple groups found with displayName `"$($selectedApp.'IN-InstallAssignmentEntraIDGroupName')`". Group needs to be unique. Skipping group" -ForegroundColor Yellow
            continue
        }
        elseif ($groupResult.value.count -eq 1) 
        {
            Write-Host "Group found with displayName `"$($selectedApp.'IN-InstallAssignmentEntraIDGroupName')`". Will use this group for assignment" -ForegroundColor Green
        }

        $assignmentSettings = @{
            source = "direct"
            settings = @{
                "@odata.type" = "#microsoft.graph.win32LobAppAssignmentSettings"
                installTimeSettings = $startTimeHash

                <#
                "installTimeSettings": {
                    "startDateTime": "2024-12-31T06:20:00Z",
                    "useLocalTime": true,
                    "deadlineDateTime": null,   
                #>

                autoUpdateSettings = $null
                deliveryOptimizationPriority = "foreground"
                notifications = "showAll"
                restartSettings = $null
            }
            target = @{
                deviceAndAppManagementAssignmentFilterId = $null
                "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                deviceAndAppManagementAssignmentFilterType = "none"
                groupId = $groupResult.value.id
            }
            intent = $selectedApp.'IN-InstallAssignmentIntent'
        }

        try 
        {
            Write-Host "Will try to assign App as `"$($selectedApp.'IN-InstallAssignmentIntent')`" to group `"$($selectedApp.'IN-InstallAssignmentEntraIDGroupName')`"" -ForegroundColor Green
            $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($uploadedApp.Id)/assignments"
            $result = Invoke-MgGraphRequest -Uri $uri -Method Post -Body ($assignmentSettings | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop           
        }
        catch 
        {
            write-host "Failed to assign app to group" -ForegroundColor Yellow
            Write-Host "$($_)" -ForegroundColor Red
            continue
        }
    }
}
#endregion

