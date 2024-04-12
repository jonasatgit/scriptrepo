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
    Set the variables to your needs and add all performance counters you want to collect to the $ListOfPerformanceCounters array.
    The script will install the required modules for the current user and will connect to Azure asking for credentials if not already connected.
    It will then update an existing data collection rule with the performance counters in $ListOfPerformanceCounters and 
    will "overwrite" all existing counters of the data collection rule.
    Performance counter names can be retrieved via the following script: https://github.com/jonasatgit/scriptrepo/blob/master/General/Get-PerfCounterList.ps1
    
.EXAMPLE
    .\Set-AzureMonitorPerfCounterDefinition.ps1
    This will update the existing data collection rule with performance counters listed under $ListOfPerformanceCounters
    It will ask for credentials if not already connected to Azure and will use the default resource group and data collection rule name set in the script

.EXAMPLE
    .\Set-AzureMonitorPerfCounterDefinition.ps1 -ResourceGroupName 'MyResourceGroup' -DataCollectionRuleName 'MyDataCollectionRule' -SamplerateInSeconds 300 -SQLPerfCounterInstanceName 'MSSQL$INST01'
    This will update the existing data collection rule with performance counters listed under $ListOfPerformanceCounters using the specified resource 
    group and data collection rule name as well as samplerate and SQL Server instance name

.PARAMETER ResourceGroupName
    The name of the resource group where the data collection rule is located

.PARAMETER DataCollectionRuleName
    The name of the data collection rule. Needs to be created before running this script

.PARAMETER SampleRateInSeconds
    The frequency at which the data is collected. The default value is 300 seconds (5 minutes).

.PARAMETER SQLPerfCounterInstanceName
    The name of the SQL Server instance if you want to collect SQL Server performance counters. If you do not have a SQL Server instance, leave it empty
    If SQL runs on a named instance, the instance name needs to be added to the counter name. Example: MSSQL$INST01
    Get the list of SQL counters by running this script first and copy the SQL instance name: 
    https://github.com/jonasatgit/scriptrepo/blob/master/General/Get-PerfCounterList.ps1

.LINK
https://guithub.com/jonasatgit/scriptrepo
#>
# Set the variables to your needs
[CmdletBinding()]
param 
(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName = '',
    [Parameter(Mandatory = $false)]
    [string]$DataCollectionRuleName = 'Windows-Server-Perf-DataCollector', 
    [Parameter(Mandatory = $false)]
    [int]$SampleRateInSeconds = 900,
    [Parameter(Mandatory = $false)]
    [string]$SQLPerfCounterInstanceName = ''
)
# List of performance counters to add to the data collection rule
$listOfPerformanceCounters = @(
    '\Processor Information(_Total)\% Processor Time', # OS performance counter
    '\LogicalDisk\Avg. Disk sec/Read', # OS performance counter
    '\LogicalDisk\Avg. Disk sec/Write', # OS performance counter
    '\LogicalDisk\Current Disk Queue Length', # OS performance counter
    '\LogicalDisk\Disk Reads/sec', # OS performance counter
    '\LogicalDisk\Disk Transfers/sec', # OS performance counter
    '\LogicalDisk\Disk Writes/sec', # OS performance counter
    '\Memory\% Committed Bytes In Use', # OS performance counter
    '\Memory\Available Mbytes', # OS performance counter
    '\Memory\Page Reads/sec', # OS performance counter
    '\Memory\Page Writes/sec', # OS performance counter
    '\Network Interface(*)\Bytes Received/sec', # OS performance counter
    '\Network Interface(*)\Bytes Sent/sec', # OS performance counter
    'SQLServer:Access Methods\Full Scans/sec', # SQL Server performance counter
    'SQLServer:Access Methods\Index Searches/sec', # SQL Server performance counter
    'SQLServer:Access Methods\Table Lock Escalations/sec', # SQL Server performance counter
    'SQLServer:Buffer Manager\Free pages', # SQL Server performance counter
    'SQLServer:Buffer Manager\Lazy writes/sec', # SQL Server performance counter
    'SQLServer:Buffer Manager\Page life expectancy', # SQL Server performance counter
    'SQLServer:Buffer Manager\Stolen pages', # SQL Server performance counter
    'SQLServer:Buffer Manager\Target pages', # SQL Server performance counter
    'SQLServer:Buffer Manager\Total pages', # SQL Server performance counter
    'SQLServer:Databases(*)\Log Growths', # SQL Server performance counter
    'SQLServer:Databases(*)\Log Shrinks', # SQL Server performance counter
    'SQLServer:Memory Manager\Memory Grants Outstanding', # SQL Server performance counter
    'SQLServer:Memory Manager\Memory Grants Pending', # SQL Server performance counter
    'SQLServer:Memory Manager\Target Server Memory (KB)', # SQL Server performance counter
    'SQLServer:Memory Manager\Total Server Memory (KB)', # SQL Server performance counter
    'SQLServer:Plan Cache(Object Plans)\Cache Object Counts', # SQL Server performance counter
    'SQLServer:Plan Cache(SQL Plans)\Cache Object Counts', # SQL Server performance counter
    'SQLServer:Plan Cache(Object Plans)\Cache Pages', # SQL Server performance counter
    'SQLServer:Plan Cache(SQL Plans)\Cache Pages', # SQL Server performance counter
    'SQLServer:SQL Statistics\Batch Requests/sec', # SQL Server performance counter
    'SQLServer:SQL Statistics\SQL Compilations/sec', # SQL Server performance counter
    'SQLServer:SQL Statistics\SQL Re-Compilations/sec', # SQL Server performance counter
    'SQLServer:Locks(_Total)\Number of Deadlocks/sec', # SQL Server performance counter
    'SQLServer:Wait Statistics(Waits in progress)\Lock waits', # SQL Server performance counter
    'SQLServer:Wait Statistics(Waits in progress)\Log buffer waits', # SQL Server performance counter
    'SQLServer:Wait Statistics(Waits in progress)\Log write waits', # SQL Server performance counter
    'SQLServer:Wait Statistics(Waits in progress)\Memory grant queue waits', # SQL Server performance counter
    'SQLServer:Wait Statistics(Waits in progress)\Network IO waits', # SQL Server performance counter
    'SQLServer:Wait Statistics(Waits in progress)\Non-Page latch waits', # SQL Server performance counter
    'SQLServer:Wait Statistics(Waits in progress)\Page IO latch waits', # SQL Server performance counter
    'SQLServer:Wait Statistics(Waits in progress)\Page latch waits', # SQL Server performance counter
    'SQLServer:Wait Statistics(Waits in progress)\Thread-safe memory objects waits', # SQL Server performance counter
    'SQLServer:Wait Statistics(Waits in progress)\Transaction ownership waits', # SQL Server performance counter
    'SQLServer:Wait Statistics(Waits in progress)\Wait for the worker', # SQL Server performance counter
    'SQLServer:Wait Statistics(Waits in progress)\Workspace synchronization waits', # SQL Server performance counter    
    'SMS Inbox(*)\File Current Count', # Site server performance counter
    'SMS Outbox(*)\File Current Count', # Site server and MP performance counter
    'SMS AD Group Discovery\DDRs generated/minute', # Site server performance counter
    'SMS AD System Discovery\DDRs generated/minute', # Site server performance counter
    'SMS Discovery Data Manager\User DDRs Processed/minute', # Site server performance counter
    'SMS Discovery Data Manager\Non-User DDRs Processed/minute', # Site server performance counter
    'SMS Inventory Data Loader\MIFs Processed/minute', # Site server performance counter
    'SMS Software Inventory Processor\SINVs Processed/minute', # Site server performance counter
    'SMS Software Metering Processor\SWM Usage Records Processed/minute', # Site server performance counter
    'SMS State System\Message Records Processed/min', # Site server performance counter
    'SMS Status Messages(*)\Processed/sec', # Site server performance counter
    'Web Service(*)\Bytes Sent/sec', # Web Service performance counter. Helpful to get MP, DP, SUP and Microsoft Connected Cache performance data
    'Web Service(*)\Bytes Received/sec', # Web Service performance counter. Helpful to get MP, DP, SUP and Microsoft Connected Cache performance data
    'SMS Notification Server\Total online clients' # Management Point performance counter
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

# making sure all entries start with "\"
$listOfPerformanceCounters = $listOfPerformanceCounters -replace '^(?!\\)', '\'

# if we have a SQL Server instance name, replace all SQL Server instance names with the actual instance name
if (-NOT([string]::IsNullOrEmpty($SQLPerfCounterInstanceName)))
{
    # if $SQLPerfCounterInstanceName does not end with a :, add a : to the end
    if (-NOT ($SQLPerfCounterInstanceName -imatch ':(?<!a)$'))
    {
        $SQLPerfCounterInstanceName = '\{0}:' -f $SQLPerfCounterInstanceName
    }

    # replace all SQL Server instance names with the actual instance name in case we have a SQL Server instance
    $listOfPerformanceCounters = $listOfPerformanceCounters -replace '^(\\SQLServer:)', $SQLPerfCounterInstanceName
}

# add all counters with equal samplerate to the same array and not idividual arrays
Write-Host "Create perf counter object" -ForegroundColor Green
$counterObject = New-AzPerfCounterDataSourceObject -CounterSpecifier $listOfPerformanceCounters -Name CoreCounters -SamplingFrequencyInSecond $sampleRateInSeconds -Stream Microsoft-Perf

# get the current data collection rule
Write-Host "Get data collection rule" -ForegroundColor Green
$azureMonitorDataCollectionRule = Get-AzDataCollectionRule -Name $dataCollectionRuleName -ResourceGroupName $resourceGroupName

# update the data collection rule with the new counter object
Write-Host "Update data collection rule" -ForegroundColor Green
Update-AzDataCollectionRule -InputObject $azureMonitorDataCollectionRule -DataSourcePerformanceCounter $counterObject
