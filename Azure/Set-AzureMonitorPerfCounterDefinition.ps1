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

    Feel free to checkout the not quite current article about the topic: https://techcommunity.microsoft.com/blog/coreinfrastructureandsecurityblog/configmgr-performance-baseline-the-easy-way/1583081
    
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
    '\Processor Information(_Total)\% Processor Time', # OS performance counter. Helpful to monitor CPU usage
    '\LogicalDisk\Avg. Disk sec/Read', # OS performance counter. Helpful to monitor disk read latency
    '\LogicalDisk\Avg. Disk sec/Write', # OS performance counter. Helpful to monitor disk write latency
    '\LogicalDisk\Current Disk Queue Length', # OS performance counter. Helpful to monitor disk queue length
    '\LogicalDisk\Disk Reads/sec', # OS performance counter. Helpful to monitor disk read throughput. Meaning: the number of read operations per second
    '\LogicalDisk\Disk Transfers/sec', # OS performance counter. Helpful to monitor disk transfer rate. Meaning: the total number of read and write operations per second
    '\LogicalDisk\Disk Writes/sec', # OS performance counter. Helpful to monitor disk write throughput. Meaning: the number of write operations per second
    '\Memory\% Committed Bytes In Use', # OS performance counter. Helpful to monitor memory usage.  Meaning: the percentage of committed memory in use
    '\Memory\Available Mbytes', # OS performance counter. Helpful to monitor available memory. Meaning: the amount of physical memory available in megabytes
    '\Memory\Page Reads/sec', # OS performance counter. Helpful to monitor page read activity. Meaning: the number of page reads per second
    '\Memory\Page Writes/sec', # OS performance counter. Helpful to monitor page write activity. Meaning: the number of page writes per second
    '\Network Interface(*)\Bytes Received/sec', # OS performance counter. Helpful to monitor network receive throughput. Meaning: the number of bytes received per second
    '\Network Interface(*)\Bytes Sent/sec', # OS performance counter. Helpful to monitor network send throughput. Meaning: the number of bytes sent per second
    'SQLServer:Access Methods\Full Scans/sec', # SQL Server performance counter. Helpful to monitor full table scans. Meaning: the number of full table scans per second
    'SQLServer:Access Methods\Index Searches/sec', # SQL Server performance counter. Helpful to monitor index search activity. Meaning: the number of index searches per second
    'SQLServer:Access Methods\Table Lock Escalations/sec', # SQL Server performance counter. Helpful to monitor table lock escalations. Meaning: the number of table lock escalations per second
    'SQLServer:Buffer Manager\Free pages', # SQL Server performance counter. Helpful to monitor free pages. Meaning: the number of free pages in the buffer pool
    'SQLServer:Buffer Manager\Lazy writes/sec', # SQL Server performance counter. Helpful to monitor lazy write activity. Meaning: the number of lazy writes per second
    'SQLServer:Buffer Manager\Page life expectancy', # SQL Server performance counter. Helpful to monitor page life expectancy. Meaning: the number of seconds a page stays in the buffer pool
    'SQLServer:Buffer Manager\Stolen pages', # SQL Server performance counter. Helpful to monitor stolen pages. Meaning: the number of pages taken from the buffer pool for other purposes
    'SQLServer:Buffer Manager\Target pages', # SQL Server performance counter. Helpful to monitor target pages. Meaning: the ideal number of pages in the buffer pool
    'SQLServer:Buffer Manager\Total pages', # SQL Server performance counter. Helpful to monitor total pages. Meaning: the total number of pages in the buffer pool
    'SQLServer:Buffer Manager\Checkpoint pages/sec', # SQL Server performance counter. Helpful to monitor checkpoint activity. Meaning: the number of checkpoint pages written per second. Might be an indicator of I/O activity and can be adjusted by setting TARGET_RECOVERY_TIME = 60
    'SQLServer:Databases(*)\Log Growths', # SQL Server performance counter. Helpful to monitor log growths. Meaning: the number of log growth events
    'SQLServer:Databases(*)\Log Shrinks', # SQL Server performance counter. Helpful to monitor log shrinks. Meaning: the number of log shrink events
    'SQLServer:Memory Manager\Memory Grants Outstanding', # SQL Server performance counter. Helpful to monitor memory grants outstanding. Meaning: the number of memory grants currently outstanding
    'SQLServer:Memory Manager\Memory Grants Pending', # SQL Server performance counter. Helpful to monitor memory grants pending. Meaning: the number of memory grants currently pending
    'SQLServer:Memory Manager\Target Server Memory (KB)', # SQL Server performance counter. Helpful to monitor target server memory. Meaning: the ideal amount of memory the server should have in KB
    'SQLServer:Memory Manager\Total Server Memory (KB)', # SQL Server performance counter. Helpful to monitor total server memory. Meaning: the total amount of memory the server is currently using in KB
    'SQLServer:Plan Cache(Object Plans)\Cache Object Counts', # SQL Server performance counter. Helpful to monitor object plan cache counts. Meaning: the number of object plans in the cache
    'SQLServer:Plan Cache(SQL Plans)\Cache Object Counts', # SQL Server performance counter. Helpful to monitor SQL plan cache counts. Meaning: the number of SQL plans in the cache
    'SQLServer:Plan Cache(Object Plans)\Cache Pages', # SQL Server performance counter. Helpful to monitor object plan cache pages. Meaning: the number of pages used by object plans in the cache
    'SQLServer:Plan Cache(SQL Plans)\Cache Pages', # SQL Server performance counter. Helpful to monitor SQL plan cache pages. Meaning: the number of pages used by SQL plans in the cache
    'SQLServer:SQL Statistics\Batch Requests/sec', # SQL Server performance counter. Helpful to monitor batch requests. Meaning: the number of batch requests per second
    'SQLServer:SQL Statistics\SQL Compilations/sec', # SQL Server performance counter. Helpful to monitor SQL compilations. Meaning: the number of SQL compilations per second
    'SQLServer:SQL Statistics\SQL Re-Compilations/sec', # SQL Server performance counter. Helpful to monitor SQL re-compilations. Meaning: the number of SQL re-compilations per second
    'SQLServer:Locks(_Total)\Number of Deadlocks/sec', # SQL Server performance counter. Helpful to monitor deadlocks. Meaning: the number of deadlocks per second
    'SQLServer:Wait Statistics(Waits in progress)\Lock waits', # SQL Server performance counter. Helpful to monitor lock waits. Meaning: the number of lock waits currently in progress
    'SQLServer:Wait Statistics(Waits in progress)\Log buffer waits', # SQL Server performance counter. Helpful to monitor log buffer waits. Meaning: the number of log buffer waits currently in progress
    'SQLServer:Wait Statistics(Waits in progress)\Log write waits', # SQL Server performance counter. Helpful to monitor log write waits. Meaning: the number of log write waits currently in progress
    'SQLServer:Wait Statistics(Waits in progress)\Memory grant queue waits', # SQL Server performance counter. Helpful to monitor memory grant queue waits. Meaning: the number of memory grant queue waits currently in progress
    'SQLServer:Wait Statistics(Waits in progress)\Network IO waits', # SQL Server performance counter. Helpful to monitor network IO waits. Meaning: the number of network IO waits currently in progress
    'SQLServer:Wait Statistics(Waits in progress)\Non-Page latch waits', # SQL Server performance counter. Helpful to monitor non-page latch waits. Meaning: the number of non-page latch waits currently in progress
    'SQLServer:Wait Statistics(Waits in progress)\Page IO latch waits', # SQL Server performance counter. Helpful to monitor page IO latch waits. Meaning: the number of page IO latch waits currently in progress
    'SQLServer:Wait Statistics(Waits in progress)\Page latch waits', # SQL Server performance counter. Helpful to monitor page latch waits. Meaning: the number of page latch waits currently in progress
    'SQLServer:Wait Statistics(Waits in progress)\Thread-safe memory objects waits', # SQL Server performance counter. Helpful to monitor thread-safe memory objects waits. Meaning: the number of thread-safe memory objects waits currently in progress
    'SQLServer:Wait Statistics(Waits in progress)\Transaction ownership waits', # SQL Server performance counter. Helpful to monitor transaction ownership waits. Meaning: the number of transaction ownership waits currently in progress
    'SQLServer:Wait Statistics(Waits in progress)\Wait for the worker', # SQL Server performance counter. Helpful to monitor wait for the worker. Meaning: the number of waits for the worker currently in progress
    'SQLServer:Wait Statistics(Waits in progress)\Workspace synchronization waits', # SQL Server performance counter. Helpful to monitor workspace synchronization waits. Meaning: the number of workspace synchronization waits currently in progress
    'SMS Inbox(*)\File Current Count', # Site server performance counter. Helpful to monitor the current count of files in the SMS Inbox.
    'SMS Outbox(*)\File Current Count', # Site server and MP performance counter. Helpful to monitor the current count of files in the SMS Outbox.
    'SMS AD Group Discovery\DDRs generated/minute', # Site server performance counter. Helpful to monitor the number of DDRs generated per minute by the AD Group Discovery.
    'SMS AD System Discovery\DDRs generated/minute', # Site server performance counter. Helpful to monitor the number of DDRs generated per minute by the AD System Discovery.
    'SMS Discovery Data Manager\User DDRs Processed/minute', # Site server performance counter. Helpful to monitor the number of user DDRs processed per minute by the SMS Discovery Data Manager.
    'SMS Discovery Data Manager\Non-User DDRs Processed/minute', # Site server performance counter. Helpful to monitor the number of non-user DDRs processed per minute by the SMS Discovery Data Manager.
    'SMS Inventory Data Loader\MIFs Processed/minute', # Site server performance counter. Helpful to monitor the number of MIFs processed per minute by the SMS Inventory Data Loader.
    'SMS Software Inventory Processor\SINVs Processed/minute', # Site server performance counter. Helpful to monitor the number of SINVs processed per minute by the SMS Software Inventory Processor.
    'SMS Software Metering Processor\SWM Usage Records Processed/minute', # Site server performance counter. Helpful to monitor the number of SWM usage records processed per minute by the SMS Software Metering Processor.
    'SMS State System\Message Records Processed/min', # Site server performance counter. Helpful to monitor the number of message records processed per minute by the SMS State System.
    'SMS Status Messages(*)\Processed/sec', # Site server performance counter. Helpful to monitor the number of status messages processed per second by the SMS Status Messages component.  
    'Web Service(*)\Bytes Sent/sec', # Web Service performance counter. Helpful to get MP, DP, SUP and Microsoft Connected Cache performance data
    'Web Service(*)\Bytes Received/sec', # Web Service performance counter. Helpful to get MP, DP, SUP and Microsoft Connected Cache performance data
    'SMS Notification Server\Total online clients', # Management Point performance counter. Helpful to monitor the total number of online clients connected to the SMS Notification Server.
    'SMS MP LocationMgr\DP Requests/second', # SMS Management Point Location Manager location requests for a DP. Helpful to monitor the number of DP requests per second.
    'SMS MP LocationMgr\MP Requests/second', # SMS Management Point Location Manager location requests for a MP. Helpful to monitor the number of MP requests per second.
    'SMS MP LocationMgr\WSUS Requests/second' # SMS Management Point Location Manager location requests for a WSUS. Helpful to monitor the number of WSUS requests per second.
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
