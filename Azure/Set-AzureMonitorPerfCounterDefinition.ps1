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
    Script to update an existing Azure Monitor performance counter data collection rule
 
.DESCRIPTION
    Set the variables to your needs and add all performance counters you want to collect to the $listOfPerformanceCounters array.
    The last command will update the data collection rule with the new performance counters and will overwrite the existing performance counters.
    Performance counter names can be retrieved via the following script: https://github.com/jonasatgit/scriptrepo/blob/master/General/Get-PerfCounterList.ps1
    
.EXAMPLE
    .\Set-AzureMonitorPerfCounterDefinition.ps1
    This will update the existing data collection rule with the new performance counters.
.LINK
    https://guithub.com/jonasatgit/scriptrepo
    
#>
$resourceGroupName = 'AZ0000016' # Replace with your resource group name where the data collection rule is located
$dataCollectionRuleName = 'Windows-Server-Perf-DataCollector' # Replace with the name of the data collection rule name
$samplerateInSeconds = 900 # Replace with the sample rate in seconds. Samplerate is the frequency at which the data is collected. The default value is 300 seconds (5 minutes).

# List of performance counters to add to the data collection rule
$listOfPerformanceCounters = @(
    '\Processor Information(_Total)\% Processor Time',
    '\LogicalDisk\Avg. Disk sec/Read',
    '\LogicalDisk\Avg. Disk sec/Write',
    '\LogicalDisk\Current Disk Queue Length', 
    '\LogicalDisk\Disk Reads/sec',
    '\LogicalDisk\Disk Transfers/sec', 
    '\LogicalDisk\Disk Writes/sec', 
    '\Memory\% Committed Bytes In Use', 
    '\Memory\Available Mbytes',
    '\Memory\Page Reads/sec',
    '\Memory\Page Writes/sec',
    '\Network Adapter\Bytes Received/sec',
    '\Network Adapter\Bytes Sent/sec',
    '\Network Interface\Bytes Total/sec',
    'SQLServer:Access Methods\Full Scans/sec',
    'SQLServer:Access Methods\Index Searches/sec',
    'SQLServer:Access Methods\Table Lock Escalations/sec',
    'SQLServer:Buffer Manager\Free pages',
    'SQLServer:Buffer Manager\Lazy writes/sec',
    'SQLServer:Buffer Manager\Page life expectancy',
    'SQLServer:Buffer Manager\Stolen pages',
    'SQLServer:Buffer Manager\Target pages',
    'SQLServer:Buffer Manager\Total pages',
    'SQLServer:Databases(*)\Log Growths',
    'SQLServer:Databases(*)\Log Shrinks',
    'SQLServer:Locks(*)\Number of Deadlocks/sec',
    'SQLServer:Memory Manager\Memory Grants Outstanding',
    'SQLServer:Memory Manager\Memory Grants Pending',
    'SQLServer:Memory Manager\Target Server Memory (KB)',
    'SQLServer:Memory Manager\Total Server Memory (KB)',
    'SQLServer:Plan Cache(Object Plans)\Cache Object Counts',
    'SQLServer:Plan Cache(SQL Plans)\Cache Object Counts',
    'SQLServer:Plan Cache(Object Plans)\Cache Pages',
    'SQLServer:Plan Cache(SQL Plans)\Cache Pages',
    'SQLServer:SQL Statistics\Batch Requests/sec',
    'SQLServer:SQL Statistics\SQL Compilations/sec',
    'SQLServer:SQL Statistics\SQL Re-Compilations/sec',
    'SQLServer:Wait Statistics(*)\Memory grant queue waits',
    'SQLServer:Wait Statistics(*)\Network IO waits',
    'SQLServer:Wait Statistics(*)\Page latch waits',
    'SQLServer:Wait Statistics(*)\Wait for the worker',
    'SMS Inbox(*)\File Current Count',
    'SMS Outbox(*)\File Current Count',
    'SMS AD Group Discovery\DDRs generated/minute',
    'SMS AD System Discovery\DDRs generated/minute',
    'SMS Discovery Data Manager\User DDRs Processed/minute',
    'SMS Inventory Data Loader\MIFs Processed/minute',
    'SMS Software Inventory Processor\SINVs Processed/minute',
    'SMS Software Metering Processor\SWM Usage Records Processed/minute',
    'SMS State System\Message Records Processed/min',
    'SMS Status Messages(*)\Processed/sec',
    'Web Service(*)\Bytes Sent/sec',	
    'Web Service(*)\Bytes Received/sec'
)


# Install the required modules and connect to Azure
if (Get-Module -ListAvailable -Name Az.Accounts -ErrorAction SilentlyContinue) {
    Write-Host "Az.Accounts module is already installed" -ForegroundColor Green
} else {
    Write-Host "Installing Az.Accounts module" -ForegroundColor Green
    Install-Module -Name Az.Accounts -Force -AllowClobber -Scope CurrentUser -Repository PSGallery -ErrorAction Stop
}

if (Get-Module -ListAvailable -Name Az.Monitor -ErrorAction SilentlyContinue) {
    Write-Host "Az.Monitor module is already installed" -ForegroundColor Green
} else {
    Write-Host "Installing Az.Monitor module" -ForegroundColor Green
    Install-Module -Name Az.Monitor -Force -AllowClobber -Scope CurrentUser -Repository PSGallery -ErrorAction Stop
}

# Connect to Azure
$azContext = Get-AzContext -ErrorAction SilentlyContinue
If ($azContext) { 
    Write-Host "You are already connected to Azure with: $($azContext.Account.Id)" -ForegroundColor Green
} else {
    Write-Host "Connecting to Azure" -ForegroundColor Green
    Connect-AzAccount -ErrorAction Stop
}

# making sure all start with "\"
$listOfPerformanceCounters = $listOfPerformanceCounters -replace '^(?!\\)', '\'

# add all counters with equal samplerate to the same array and not idividual arrays
Write-Host "Create perf counter object" -ForegroundColor Green
$counterObject = New-AzPerfCounterDataSourceObject -CounterSpecifier $listOfPerformanceCounters -Name CoreCounters -SamplingFrequencyInSecond $samplerateInSeconds -Stream Microsoft-Perf

# get the current data collection rule
Write-Host "Get data collection rule" -ForegroundColor Green
$azureMonitorDataCollectionRule = Get-AzDataCollectionRule -Name $dataCollectionRuleName -ResourceGroupName $resourceGroupName

# update the data collection rule with the new counter object
Write-Host "Update data collection rule" -ForegroundColor Green
Update-AzDataCollectionRule -InputObject $azureMonitorDataCollectionRule -DataSourcePerformanceCounter $counterObject
