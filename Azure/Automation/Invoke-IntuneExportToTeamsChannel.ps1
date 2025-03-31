<# 
.SYNOPSIS
    Script to export data from Intune and upload it to a Microsoft Teams channel using Microsoft Graph API.

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

    The script exports data from Intune and uploads it to a Microsoft Teams channel using Microsoft Graph API.
    The script uses the Microsoft Graph API to connect to Intune and retrieve data about managed devices.
    The data is then converted to CSV format and uploaded to a Microsoft Teams channel.
    The script uses the Microsoft Graph API to create an upload session for the file and upload it in chunks.
    The script is intended as a sample and should be modified to fit your needs.

    It can also be used in Azure Automation with a Managed Identity to connect to Microsoft Graph and Teams.

    The script requires the following permissions:
    - Team.ReadBasic.All: Read the names and descriptions of all teams in the organization.
    - DeviceManagementManagedDevices.Read.All: Read all managed devices in Intune.
    - Files.ReadWrite.All: Read and write all files in all site collections (Delegated permission).
    - Sites.ReadWrite.All: Read and write items in all site collections (Application permission). (Required for Azure Automation)

    We need to create an upload session to upload the file in chunks. The upload session will return a URL to which we can upload the file in chunks.
    For the upload session, we need to specify the conflict behavior. The conflict behavior can be set to "fail" (default), "replace", or "rename".
    We also need to construct headers for the upload request. The headers must include the Content-Length and range information about the chunks we are uploading.
    The script will upload the file in chunks of 320 KiB. The chunk size must be a multiple of 320 KiB.
    See: https://learn.microsoft.com/en-us/graph/api/driveitem-createuploadsession

.PARAMETER TeamName
    The name of the Microsoft Teams team to which the file will be uploaded. Default is 'Contoso'.

.PARAMETER TeamsChannelName
    The name of the Microsoft Teams channel where the file will be uploaded. Default is 'TestChannel'.

#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$TeamName = 'Contoso',

    [Parameter(Mandatory = $false)]
    [string]$TeamsChannelName = 'TestChannel'
)



# Connect to Microsoft Graph with the required permissions
# Team.ReadBasic.All: Read the names and descriptions of all teams in the organization.
# DeviceManagementManagedDevices.Read.All: Read all managed devices in Intune.
# Files.ReadWrite.All: Read and write all files in all site collections (Delegated permission).
# Sites.ReadWrite.All: Read and write items in all site collections (Application permission).
# Check if we are in an Azure Automation environment
# If we are, we will use the Managed Identity to connect to Microsoft Graph and Azure Storage
[bool]$inAzureAutomationEnvironment = if (Get-Command -Name Get-AutomationVariable -ErrorAction SilentlyContinue){$true}else{$false}
if ($inAzureAutomationEnvironment)
{
    Connect-MgGraph -Identity
    Connect-AzAccount -Identity
}
else
{
    Install-Module Microsoft.Graph.Authentication -Force -AllowClobber -Scope CurrentUser

    Connect-MgGraph -Scopes "Team.ReadBasic.All", "DeviceManagementManagedDevices.Read.All", "Files.ReadWrite.All", "Sites.ReadWrite.All" 
}

# IMPORTANT: The following code can only export 1000 items at a time.
# If you have more than 1000 items, you will need to use pagination to get all items.
# For more information on pagination, see the following link:
# https://learn.microsoft.com/en-us/graph/paging
$intuneDevicesUri = 'https://graph.microsoft.com/beta/deviceManagement/managedDevices?$select=id,azureADDeviceId,deviceName,complianceState'
$intuneResult = Invoke-MgGraphRequest -Uri $intuneDevicesUri -Method Get -OutputType Json -
# Using output type json to be able to convert the result to a JSON object with a depth of 10 and not just 1
$intuneResultObject = $intuneResult | ConvertFrom-Json -Depth 10

# Convert the result to a CSV string array. Because we want to upload the data as a CSV file to the Teams channel
# Export-csv would also work with: $fileBytes = [System.IO.File]::ReadAllBytes($csvFullName)
# But this step makes the export obsolete and we don't need to create a file on the disk.
$stringArray = $intuneResultObject.value | ConvertTo-Csv -NoTypeInformation

$fileBytes = $null
foreach ($string in $stringArray) 
{
    # We need to add a new line to the end of each string in the array
    $string = $string + "`r`n"
    # We need to convert the string to a byte array to be able to upload it to the Teams channel
    # We will set the encoding to UTF8
    $fileBytes += [System.Text.Encoding]::UTF8.GetBytes($string)
}

Write-Host "Found $($intuneResultObject.value.Count) devices for export" -ForegroundColor Green

# Name of the file we will create in the Teams channel
$newFileName = 'Devices-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss')

# Get Microsoft Teams team ID
$teamsSearchUri = "https://graph.microsoft.com/beta/teams?`$filter=displayName eq '$($teamName)'&`$select=id,displayName"

# Get the team ID from the search result
$teamsSearchResult = Invoke-MgGraphrequest -Uri $teamsSearchUri -Method Get -OutputType json
# Using output type json to be able to convert the result to a JSON object with a depth of 10 and not just 1
$teamsSearchResultObject = $teamsSearchResult | ConvertFrom-Json -Depth 10
# Extract the team ID from the search result
$teamId = $teamsSearchResultObject.value[0].id

# Get Microsoft Teams drive ID
$drivesUri = "https://graph.microsoft.com/beta/groups/$teamId/drives"
$drivesResult = Invoke-MgGraphrequest -Uri $drivesUri -Method Get -OutputType json
# Using output type json to be able to convert the result to a JSON object with a depth of 10 and not just 1
$drivesResultObject = $drivesResult | ConvertFrom-Json -Depth 10
# Extract the drive ID from the search result
$driveId = $drivesResultObject.value[0].id


# We will now create an upload session for the file to be uploaded
#
# Documentation: 
# https://learn.microsoft.com/en-us/graph/api/driveitem-createuploadsession
#
#
$createUploadSessionUri = '{0}/{1}/root:/{2}/{3}:/createUploadSession' -f $drivesUri, $driveId, $teamsChannelName, $newFileName
# Example uri:
# https://graph.microsoft.com/beta/groups/<GroupID>/drives/<DriveID>/root:/<FolderName>/<FileName>:/createUploadSession


# Create a body for the upload session request to instruct the upload session to replace the file if it already exists
# Possible values for conflictBehavior are: "fail" (default), "replace", "rename"
$body = @{
    '@microsoft.graph.conflictBehavior' = 'replace'
    name = $newFileName
}

# Create the upload session via parameter splatting
# The upload session will return a URL to which we can upload the file in Chunks if needed
$paramPlatting = @{
    Uri = $createUploadSessionUri
    Method = 'POST'
    ContentType = 'application/json'
    Body = ($body | ConvertTo-Json) # Body must be a JSON object
    OutputType = 'Json' # The result will be a JSON object
    
}

$uploadSessionReturn = Invoke-MgGraphrequest @paramPlatting
# Using output type json to be able to convert the result to a JSON object with a depth of 10 and not just 1
$uploadSessionReturnObject = $uploadSessionReturn | ConvertFrom-Json -Depth 10
# $uploadSessionUri will contain the URL to which we can upload the file
$uploadSessionUri = $uploadSessionReturnObject.uploadUrl


# Max chunk size must be a multiple of 320 KiB. See documentation for more details.
# Documentation: 
# https://learn.microsoft.com/en-us/graph/api/driveitem-createuploadsession
[int]$maxChunkSize = 320 * 1024  

# Read all bytes from the file to be uploaded
#$fileBytes = [System.IO.File]::ReadAllBytes($csvFullName)
# Lets delete the file after we read it, since we don't need it anymore
#Remove-Item -Path $csvFullName -Force -ErrorAction SilentlyContinue

# Calculate the number of chunks we needed to upload the file
$chunkCount = [System.Math]::Ceiling($fileBytes.Length / $maxChunkSize)

$resultArray = @()
# Loop through each Chunk and upload it
# The loop will run from chunk 0 to the total number of chunks - 1.
foreach ($Chunk in 0..($chunkCount - 1))
{
    # Calculate the start and end byte for the Chunk
    $startByte = $Chunk * $maxChunkSize
    $endByte = [System.Math]::Min($startByte + $maxChunkSize - 1, $fileBytes.Length - 1)

    # Create the content range header for the Chunk. Requested by the API
    # The content range must be in the format: bytes {start}-{end}/{total} of the current upload
    $contentRange = 'bytes {0}-{1}/{2}' -f $startByte, $endByte, $fileBytes.Length

    # Create the headers for the upload request. Requested by the API
    # The Content-Length header specifies the size of the current request.
    # The Content-Range header indicates the range of bytes in the overall file that this request represents.
    # The total length of the file is known before you can upload the first fragment of the file.
    $currentLength = $endByte - $startByte + 1

    $headers = @{
        'Content-Length' = $currentLength
        'Content-Range' = $contentRange
        'Content-Type' = 'application/octet-stream'
    }

    Write-Verbose $headers

    # Create the body for the upload request. The body must be a byte array of the size of the current Chunk
    $bodyData = [byte[]]::new($currentLength)
    # Copy the bytes from the file to the body array. The start byte is the offset in the file where the Chunk starts
    # The current length is the size of the Chunk to be uploaded
    # The Array.Copy method copies a range of elements from one array to another.
    # The first parameter is the source array, the second parameter is the start index in the source array,
    # the third parameter is the destination array, the fourth parameter is the start index in the destination array,
    # and the fifth parameter is the number of elements to copy.
    [Array]::Copy($fileBytes, $startByte, $bodyData, 0, $currentLength)

    # Upload the Chunk to the upload session URL
    Write-host "Uploading chunk $($Chunk + 1) of $chunkCount Size: $currentLength bytes" -ForegroundColor Green
    $resultArray += Invoke-WebRequest -Uri $uploadSessionUri -Method Put -Headers $headers -Body $BodyData -UseBasicParsing
}

