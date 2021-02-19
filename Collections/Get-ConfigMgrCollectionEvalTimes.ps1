<#
.Synopsis
    Script to visualize the last ConfigMgr collection evaluations in a GridView

.DESCRIPTION
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
    Path to one or multiple colleval.log files
#>
param
(
    [Parameter(Mandatory=$false)]
    $CollEvalLogPath = $env:SMS_LOG_PATH
)

$collEvalSearchString = "(Start to process graph with (\d*) collections in \[(Primary|Auxiliary|Express|Single) Evaluator\])|Process graph with these collections \[.{8}(,|\])|Results refreshed for collection .*\d* entries changed|(EvaluateCollectionThread thread ends)"

$fullEvalList = Get-ChildItem -Path "$CollEvalLogPath\colleval*" | Sort-Object -Property LastWriteTime | Select-String -Pattern $collEvalSearchString

$outObj = New-Object System.Collections.ArrayList

# using property-bag for temp object
$tmpObj = New-Object psobject | Select-Object EvalType, CollectionCount, RunTimeInSeconds, ChangeCount ,RootCollection, EndTime, DifferenceToLastRun ,Thread

$firstStartFound = $false
$lastEndTime = $null
$changeCount = 0
$i = 0
foreach ($logLine in $fullEvalList.Line)
{
    $lastLine = $false

    switch -Regex ($logLine) 
    {
        "(Start to process graph with).*(?<CollectionCount> \d* ).*(?<action>(Primary|Auxiliary|Express|Single)).*(?<datetime>\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}.\d*).*(?<thread>thread=\d*)"
        {
            # we need to start with the first starting entry of the log (Start to process graph with) and not with any other
            # we could simply group by thread ID, but thread IDs are re-used and not unique in the log, so we need to parse each line
            $firstStartFound = $true

            $step1Thread = ($Matches.thread) -replace "(thread=)", ""
            $tmpObj.Thread = $step1Thread
            $tmpObj.CollectionCount = ($Matches.collectioncount).Trim()
            
            $startDateTime = ($Matches.datetime)

            switch (($Matches.action).Trim())
            {
                'Primary' 
                {
                    $tmpObj.EvalType = "Scheduled"
                }
                'Auxiliary'
                {
                    $tmpObj.EvalType = "ManualTree"            
                }
                'Express'
                {
                    $tmpObj.EvalType = "Incremental"
                }
                'Single'
                {
                    $tmpObj.EvalType = "ManualSingle"
                }
                Default
                {
                    $tmpObj.EvalType = "Unknown"
                }
            }
            
            # calculate time difference in minutes between last evaluation cycle and now
            if ($lastEndTime)
            {
                $differenceTime = New-TimeSpan -Start (get-date($lastEndTime)) -End (get-date($startDateTime))
                $tmpObj.DifferenceToLastRun = [System.Math]::Round($differenceTime.TotalMinutes)
            }


            $Matches = $null
        }
        "(Process graph with these collections )(?<collection>\[.{8}(,|\])).*(?<datetime>\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}.\d*).*(?<thread>thread=\d*)"
        {
            if ($firstStartFound)
            {
                #$matches
                $step2Thread = ($Matches.thread) -replace "(thread=)", ""
                #$step2Thread
                $tmpObj.RootCollection = ($Matches.collection) -Replace "(\[|\]|,)", ""
                $Matches = $null
            }
        }
        "(Results refreshed for collection).*, (?<ChangeCount>\d*)"
        {
            if ($firstStartFound)
            { 
                $changeCount = $changeCount + $matches.ChangeCount
                $matches = $null
            }  
        }
        "(EvaluateCollectionThread thread ends).*(?<datetime>\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}.\d*).*(?<thread>thread=\d*)"
        {
            if ($firstStartFound)
            {
                $step3Thread = ($Matches.thread) -replace "(thread=)", ""
                $tmpObj.EndTime = ($Matches.datetime)

                $runTime = New-TimeSpan -Start (get-date($startDateTime)) -End (get-date(($Matches.datetime)))
                $tmpObj.RunTimeInSeconds = $runTime.TotalSeconds

                $lastLine = $true
                $Matches = $null
            }
        }
        Default {}
    }
    
    if ($lastLine)
    {
        [void]$outObj.Add($tmpObj)

        $lastEndTime = $tmpObj.EndTime
        $tmpObj.ChangeCount = $changeCount

        # re-create tmpobject and changecount since we reached the end of the eval cycle and we need another object for the next one
        $changeCount = 0
        $tmpObj = New-Object psobject | Select-Object EvalType, CollectionCount, RunTimeInSeconds, ChangeCount ,RootCollection, EndTime, DifferenceToLastRun ,Thread
    }
    $i++ # just for testing
   
 }   
 $outObj | Out-GridView -Title 'Collection Eval Times'
