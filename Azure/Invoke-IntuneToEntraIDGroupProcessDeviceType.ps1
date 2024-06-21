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

<#
.Synopsis
    Example script to add Intune devices to Entra ID groups
    
.DESCRIPTION
    Example script to add Intune devices to Entra ID groups
    Can be used in PowerShell or Azure Automation Runbook
    Source: https://github.com/jonasatgit/scriptrepo
   
     Create Entra ID Groups based on device type
#>

# add type to uncompress file
try 
{
    $null = Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction Stop
}
catch [System.Exception] 
{
    Write-CMTraceLog -Message "An error occurred while loading System.IO.Compression.FileSystem assembly." -Severity Error
    Write-CMTraceLog -Message "Error message: $($_)"
    Exit 0
}

# Are we running in Azure Automation?
if (Get-Command -Name Get-AutomationVariable -ErrorAction SilentlyContinue)
{
    # Script running in Azure Automation
    # Will use managed identity with Entra ID application permissions already set up
    Connect-AzAccount -Identity
    $token = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com"
    $secureString = ConvertTo-SecureString -String $token.Token -AsPlainText
    Connect-MgGraph -AccessToken $secureString

    Get-MgContext
}
else 
{
    # Install module Microsoft.Graph.Authentication and Microsoft.Graph.Groups
    Install-Module -Name Microsoft.Graph.Authentication, Microsoft.Graph.Groups -Force -AllowClobber -Scope CurrentUser

    # import modules
    Import-Module Microsoft.Graph.Authentication
    Import-Module Microsoft.Graph.Groups

    # Authenticate against Microsoft Graph API
    Connect-MgGraph -scopes "DeviceManagementManagedDevices.Read.All", "Device.ReadWrite.All", "Group.Read.All", "GroupMember.ReadWrite.All"
}

# Invoke Intune Report Export
$reportHash = [ordered]@{
    "reportName" = "DevicesWithInventory"
    "format" = "csv"
    "localizationType" = "localizedValuesAsAdditionalColumn"
    "select" = ("DeviceId", "ReferenceId", "DeviceName", "Manufacturer", "Model")
}

$requestBody = $reportHash | ConvertTo-Json
$reportJob = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs" -Body $requestBody -ContentType "application/json"

# Check the status of the export job via attribute status until it is completed
do 
{
    start-sleep -Seconds 5
    $reportJob = Invoke-MgGraphRequest -Method Get -Uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs/$($reportJob.Id)"
} 
until ($reportJob.status -ieq "completed")


# download the report as zip to %temp% from the URL provided in the response
$outFileFullName = '{0}\DevicesWithInventory.zip' -f $env:temp
Invoke-WebRequest -Uri $reportJob.url -OutFile $outFileFullName

if (Test-Path $outFileFullName)
{
    Write-Output "Report downloaded to $outFileFullName"
}
else
{
    Write-Error "Failed to download report. Error: $($_)"
    Exit 0
}

try 
{
    $outCSVFileFullName = '{0}\DevicesWithInventory.csv' -f $env:temp
    $reportZipFile = [System.IO.Compression.ZipFile]::OpenRead($outFileFullName)
    $reportZipFile.Entries | Where-Object {$_.Name -ilike '*.csv'} | ForEach-Object {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, $outCSVFileFullName, $true)
    }
    $reportZipFile.Dispose()  
}
catch 
{
    Write-Host "CSV could not been extracted. Error: $($_)"
    Exit 0
}


# test if csv file exists
if (Test-Path $outCSVFileFullName)
{
    Write-Output "Report extracted to $outCSVFileFullName"
}
else
{
    Write-Error "Failed to extract report"
    Exit 0
}


$modelToGroupHash = @{
    'Virtual Machine' = 'IN-D-INV-VM'
    'HP EliteBook 840 G3' = 'IN-D-INV-HP840G3'
    'HP EliteBook 840 G4' = 'IN-D-INV-HP840G4'
    'HP EliteBook 840 G5' = 'IN-D-INV-HP840G5'
    'HP EliteBook 840 G6' = 'IN-D-INV-HP840G6'
    'HP EliteBook 840 G7' = 'IN-D-INV-HP840G7'
    'HP EliteBook 850 G3' = 'IN-D-INV-HP850G3'
    'HP EliteBook 850 G4' = 'IN-D-INV-HP850G4'
    'HP EliteBook 850 G5' = 'IN-D-INV-HP850G5'
    'HP EliteBook 850 G6' = 'IN-D-INV-HP850G6'
    'HP EliteBook 850 G7' = 'IN-D-INV-HP850G7'
    'HP EliteBook 830 G5' = 'IN-D-INV-HP830G5'
    'HP EliteBook 830 G6' = 'IN-D-INV-HP830G6'
}


# check delimiter. Can be ; or , depending on who created the file. Either Intune Download or test with Excel for examle
$csvHeader = get-content $outCSVFileFullName -TotalCount 1 
if ($csvHeader -imatch '(;.*;)')
{
    $csvDelimiter = ';'
}
elseif ($csvHeader -imatch '(,.*,)') 
{
    $csvDelimiter = ','
}
else
{
    Write-Output "No delimiter found in CSV file"
    Exit 0
}

# import csv file
$csvData = Import-csv -Path $outCSVFileFullName -Delimiter $csvDelimiter

# loop through csv data
foreach($item in $csvData)
{

    # we need to find the device first to get the Entra ID object ID. We cannot add the device with just the "Azure AD Device ID" aka "deviceID"
    $deviceURI = 'https://graph.microsoft.com/v1.0/devices?$filter=deviceID eq ''{0}''&$select=id,deviceId,displayName' -f ($item.'Azure AD Device ID')
    $device = Invoke-MgGraphRequest -Method GET -Uri $deviceURI

    if ($device.value)
    {
        $groupName = $modelToGroupHash[($item.model)]

        [array]$groups = Get-mggroup -Filter "displayName eq '$groupName'" 
        if(-NOT ($groups))
        {
            Write-Output "Group $groupName not found. Will skip device. Group should be created before running the script"
            <#
            Write-Output "Group $groupName not found. Will create"
            # Should be done manually before running the script
            # create new entra id group
            $description = "This is a new group for Intune devices"
            $newGroup = New-MgGroup -DisplayName $groupName -Description $description -MailEnabled:$false -MailNickname $groupName -SecurityEnabled:$true

            New-MgGroupMember -GroupId $newGroup.id -DirectoryObjectId $device.value.id
            #>
        }
        else
        {
            foreach($group in $groups)
            {
                Write-Output "Group $groupName found. Add device"
                New-MgGroupMember -GroupId $group.id -DirectoryObjectId $device.value.id
            }        
        }
    }
    else 
    {
        Write-Output "No device with deviceID: `"$($item.'Azure AD Device ID')`" found in Entra ID"
    }
}


