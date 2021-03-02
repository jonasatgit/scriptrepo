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
# Source: https://github.com/jonasatgit/scriptrepo

<#
.Synopsis
    Script to visualize the last ConfigMgr collection evaluations in a GridView

.DESCRIPTION
    Version: 20210302

    Script to visualize the last ConfigMgr collection evaluations in a GridView by parsing the colleval.log and colleval.lo_ files.
    Run the script on a ConfigMgr Primary Site Server or provide a valid path to the mentioned files via parameter -CollEvalLogPath

    The script will parse the following lines:
    Start to process graph with 7 collections in [Primary Evaluator] thread
    or
    Start to process graph with 1 collections in [Auxiliary Evaluator] thread
    or
    Start to process graph with 1 collections in [Express Evaluator] thread
    or
    Start to process graph with 1 collections in [Single Evaluator] thread
    or
    Process graph with these collections [SMS00001]
    or
    Process graph with these collections [SMS00001, SMS0003,SMS0004]
    or
    Results refreshed for collection P11002BB, 0 entries changed   
    or
    Waiting for async query to complete, have waited 1234 seconds already.
    or 
    EvaluateCollectionThread thread ends

    EvalTypes:
    Scheduled    - Scheduled refresh
    Incremental  - Incremental refresh
    ManualTree   - Manual collection update on a limiting collection
    ManualSingle - Manual collection update on a single collection

.EXAMPLE
    .\Get-ConfigMgrCollectionEvalTimes.ps1
.EXAMPLE
    .\Get-ConfigMgrCollectionEvalTimes.ps1 -CollEvalLogPath "F:\Program Files\Microsoft Configuration Manager\Logs"
.PARAMETER CollEvalLogPath
    Path to one or multiple colleval.log files. Will use SMS_LOG_PATH if nothing has been set.
.PARAMETER ProviderMachineName
    Name of the SMS Provider. Will use local system if nothing has been set.
#>
param
(
    [Parameter(Mandatory=$false)]
    [string]$CollEvalLogPath = "$env:SMS_LOG_PATH",
    [Parameter(Mandatory=$false)]
    [string]$ProviderMachineName = $env:COMPUTERNAME
)

$collEvalSearchString = "(Start to process graph with (\d*) collections in \[(Primary|Auxiliary|Express|Single) Evaluator\])|Process graph with these collections \[.{8}(,|\])|Results refreshed for collection .*\d* entries changed|(Waiting for async query)|(EvaluateCollectionThread thread ends)"

# parsing log file/s
$fullEvalList = Get-ChildItem -Path "$CollEvalLogPath\colleval*" | Sort-Object -Property LastWriteTime | Select-String -Pattern $collEvalSearchString


# getting collection list
$cimSession = New-CimSession -ComputerName $ProviderMachineName
try
{
    $siteCode = Get-CimInstance -CimSession $cimSession -Namespace root\sms  -Query "Select * From SMS_ProviderLocation Where ProviderForLocalSite=1" -ErrorAction Stop | Select-Object -ExpandProperty SiteCode -First 1
}
catch 
{
    Write-Warning 'Could not query Sitecode informations. Please enter SiteCode manually:'
    $siteCode = Read-Host -Prompt 'Please enter SiteCode'
}

$listOfCollections = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "select CollectionID, Name, Membercount from sms_collection"
$cimSession | Remove-CimSession
if(-NOT ($listOfCollections))
{
    Write-Warning 'Could not get collection info from WMI, will proceed without collection names.'
}


$timeZoneOffset = $null
$changeCount = 0

$objLoglineByThread = new-object System.Collections.ArrayList
# group by thread ID to get the right entries together
foreach ($logLine in $fullEvalList.Line)
{
    # using property-bag for temp object
    $logLineObject = New-Object psobject | Select-Object Step, EvalType, CollectionCount, ChangeCount ,CollectionID, CollectionName, DateTime, StartTime, EndTime, Thread
    $matches = $null
    
    $null = $logLine -match "(?<datetime>\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}.\d*(\+|\-)\d*).*(?<thread>thread=\d*)"
    $logLineObject.Thread = (($Matches.thread) -replace "(thread=)", "")
    
    # removing timezone offset plus or minus 480 for example: '02-22-2021 03:19:10.431+480'
    $datetimeSplit = ($Matches.datetime) -split '(\+|\-)\d*$'
    $logLineObject.DateTime = [Datetime]::ParseExact($datetimeSplit[0], 'MM-dd-yyyy HH:mm:ss.fff', $null)
    
    if (-NOT($timeZoneOffset))
    {
        $null = $matches.datetime -match '(\+|\-)\d*$'
        $timeZoneOffset = $matches[0]
    }
    $matches = $null

    switch -Regex ($logLine) 
    {
        #EXAMPLE: Start to process graph with 7 collections in [Primary Evaluator] thread
        "(Start to process graph with).*(?<CollectionCount> \d* ).*(?<action>(Primary|Auxiliary|Express|Single))"
        {
            $logLineObject.step  = 1
            $logLineObject.CollectionCount = ($Matches.collectioncount).Trim()
            $logLineObject.StartTime = ($logLineObject.DateTime).ToString('yyyy-MM-dd HH:mm:ss') 
            
            switch (($Matches.action).Trim())
            {
                'Primary' 
                {
                    $logLineObject.EvalType = "Scheduled"
                }
                'Auxiliary'
                {
                    $logLineObject.EvalType = "ManualTree"            
                }
                'Express'
                {
                    $logLineObject.EvalType = "Incremental"
                }
                'Single'
                {
                    $logLineObject.EvalType = "ManualSingle"
                }
                Default
                {
                    $logLineObject.EvalType = "Unknown"
                }
            }
            $matches = $null
        }
        #EXAMPLE: Process graph with these collections [SMS00001, SMS0003,SMS0004]
        "(Process graph with these collections )(?<collection>\[.{8}(,|\]))"
        {
            $logLineObject.step  = 2
            $logLineObject.CollectionID = ($Matches.collection) -Replace "(\[|\]|,)", ""

            if ($listOfCollections)
            {
                $collectionObject = $listOfCollections.Where({$_.CollectionID -eq ($logLineObject.CollectionID)})
                if ($collectionObject)
                {
                    $logLineObject.CollectionName = $collectionObject.Name
                }
                else
                {
                    $logLineObject.CollectionName = 'NOT FOUND'
                }
            }
            else
            {
                $logLineObject.CollectionName = 'NOT FOUND'
            }
            $Matches = $null
        }
        #EXAMPLE: Results refreshed for collection P11002BB, 0 entries changed
        "(Results refreshed for collection).*, (?<ChangeCount>\d*)"
        {
            $logLineObject.step  = 3
            $logLineObject.ChangeCount = $matches.ChangeCount
            $matches = $null
        }
        #EXAMPLE: EvaluateCollectionThread thread ends
        "(EvaluateCollectionThread thread ends)"
        {
            $logLineObject.step  = 4
            $logLineObject.EndTime = ($logLineObject.DateTime).ToString('yyyy-MM-dd HH:mm:ss') 
            $Matches = $null
        }
        #EXAMPLE: Waiting for async query to complete, have waited 1234 seconds already.
        "Waiting for async query"
        {
            Write-Warning "CollEval in bad state. Long running collection found. Filter colleval logs for thread ID: `"$($logLineObject.Thread)`""
        }
    }

    
    if($logLineObject.step -eq 3 -and $logLineObject.ChangeCount -eq 0)
    {
        # skip step 3 if nothing has changed to limit the amount of lines we need to work with 
    }
    else
    {
        [void]$objLoglineByThread.Add($logLineObject)
    }
}

# Bringing all threads in order by thread ID, datetime and step. That way we can easily combine entries to one entry 
$objLoglineByThreadSorted = $objLoglineByThread | Sort-Object -Property Thread, Datetime, Step  #| ogv

$outObj = New-Object System.Collections.ArrayList
$tmpObj = New-Object psobject | Select-Object EvalType, CollectionCount, RunTimeInSeconds, ChangeCount ,CollectionID, CollectionName, StartTime, EndTime ,Thread, Notes
$changeCount = 0
foreach ($logLineWithThreadID in $objLoglineByThreadSorted)
{
    $lastLine = $false

    switch ($logLineWithThreadID.step) 
    {
        1 # Start
        {
            $tmpObj.EvalType = $logLineWithThreadID.EvalType
            $tmpObj.CollectionCount = $logLineWithThreadID.CollectionCount
            # always setting thread in case we don't have all steps
            $tmpObj.Thread = $logLineWithThreadID.Thread
            $tmpObj.StartTime = $logLineWithThreadID.StartTime
            # save starttime to calculate runtime
            $startDateTime = $logLineWithThreadID.DateTime
        }
        
        2 # Graph info
        {
            $tmpObj.CollectionID = $logLineWithThreadID.CollectionID
            $tmpObj.CollectionName = $logLineWithThreadID.CollectionName
            # always setting thread in case we don't have all steps
            $tmpObj.Thread = $logLineWithThreadID.Thread
        }

        3 # Refreshed Collections
        {
            $changeCount = $changeCount + $logLineWithThreadID.ChangeCount
            # always setting thread in case we don't have all steps
            $tmpObj.Thread = $logLineWithThreadID.Thread
        }

        4 # End
        {
            $lastLine = $true
            $tmpObj.EndTime = $logLineWithThreadID.Endtime
            # calculate total eval cycle runtime inf start and end exists 
            if($startDateTime)
            {
                $runTime = New-TimeSpan -Start (get-date($startDateTime)) -End (get-date($logLineWithThreadID.DateTime))
                $tmpObj.RunTimeInSeconds = $runTime.TotalSeconds
            }
            # always setting thread in case we don't have all steps
            $tmpObj.Thread = $logLineWithThreadID.Thread
        }
    }

    if ($lastLine)
    {
        $startDateTime = $null
        $tmpObj.ChangeCount = $changeCount

        if (-NOT ($tmpObj.EvalType -and $tmpObj.CollectionID -and $tmpObj.EndTime))
        {
            $tmpObj.Notes = "Missing info. Logfile might be truncated"    
        }
        [void]$outObj.Add($tmpObj)

        # re-create tmpobject and changecount since we reached the end of the eval cycle and we need another object for the next one
        $changeCount = 0
        $tmpObj = New-Object psobject | Select-Object EvalType, CollectionCount, RunTimeInSeconds, ChangeCount ,CollectionID, CollectionName, StartTime, EndTime ,Thread, Notes
    }

}

# creating statistics
$runtimeLast24h = 0
$outObj | Where-Object {$_.EndTime -ge (get-date).AddHours(-24)} | ForEach-Object {

    $runtimeLast24h = $runtimeLast24h + $_.RunTimeInSeconds
} 
$runtimeLast24h = $runtimeLast24h / 60 # convert to minutes

$longestSingleRuntime = $outObj | Sort-Object -Property RunTimeInSeconds -Descending | Select-Object -First 1
$longestSingleRuntimeMinutes = [System.Math]::Round($longestSingleRuntime.RunTimeInSeconds / 60)

# output data
$ogvTitle = "Collection Eval Times     -- Total runtime in last 24h: $([System.Math]::Round($runtimeLast24h)) minutes, longest single runtime: $($longestSingleRuntimeMinutes) minutes (thread: $($longestSingleRuntime.Thread)) TimezoneOffset: $($timezoneOffset) minutes --"
$outObj | Sort-Object -Property EndTime -Descending | Out-GridView -Title $ogvTitle

