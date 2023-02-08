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
#
# 20230208: Fixed an issue with the output data in case on collection was selected multiple times
# 20221221: Changed UniqueEntries, changed some info lines, change SQL database info function
# 20210327: Changed user info part to be more accurate
# 20210312: Changed script to not use switch -regex since that is really slow compared to select-string
# 20210316: Added user info for manual trigger

<#
.Synopsis
    Slightly overdeveloped script to visualize the last ConfigMgr collection evaluations in a GridView based on the colleval.log

.DESCRIPTION
    Version: 20230208

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
.PARAMETER IgnoreCollectionInfo
    Switch to prevent the script from connecting to the SMS Provider and to ignore the Collection names. The output will only contain the CollectionID. 
    Helpful if the logs are copied to a machine without connection to the SMS Provider.
.PARAMETER ForceDCOMConnection
    Sitch to force the script to use DCOM/WMI instead of PSRemoting. Useful if only WMI is available.
.PARAMETER AddUserData
    Switch to add user data for manual collection updates. The script will try to connect to SQL to get data about who updated a collection.
.PARAMETER SQLServerAndInstanceName
    SQL server FQDN and instance name if the SQL server has been installed using a named instance.
    If the server does not use a named instance, just use the SQL server FQDN. 
    Example: -SQLServerAndInstanceName "cm01.contoso.local"
    Example: -SQLServerAndInstanceName "cm01.contoso.local\inst01"
    Example: -SQLServerAndInstanceName "cm01.contoso.local\inst01,1433"
.PARAMETER ConfigMgrDBName
    Name of the ConfigMgr DB. Like "CM_P01" for example. 
.PARAMETER ForceUniqueEntries
    Switch parameter to force the script to select unique log entries. Can be helpful if multiple colleval.log files have been copied with overlapping entries
    and parameter -CollEvalLogPath was used. 
#>
param
(
    [Parameter(Mandatory=$false)]
    [string]$CollEvalLogPath = "$env:SMS_LOG_PATH",
    [Parameter(Mandatory=$false)]
    [string]$ProviderMachineName = $env:COMPUTERNAME,
    [Parameter(Mandatory=$false)]
    [switch]$IgnoreCollectionInfo,
    [Parameter(Mandatory=$false)]
    [switch]$ForceDCOMConnection,
    [Parameter(Mandatory=$false)]
    [switch]$AddUserData,
    [Parameter(Mandatory=$false)]
    [string]$SQLServerAndInstanceName,
    [Parameter(Mandatory=$false)]
    [string]$ConfigMgrDBName,
    [Parameter(Mandatory=$false)]
    [switch]$ForceUniqueEntries
)

#region Function Get-ExtendedCollectionInfoFromDB
<#
.Synopsis
   Get-ExtendedCollectionInfoFromDB
.DESCRIPTION
   Get-ExtendedCollectionInfoFromDB
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Get-ExtendedCollectionInfoFromDB
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$SQLServerName,
        [Parameter(Mandatory=$true)]
        [string]$DBName
    )


    $connectionString = "Server=$SQLServerName;Database=$DBName;Integrated Security=True"
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Connecting to SQL: `"$connectionString`"" -ForegroundColor Green
    
    $SqlQuery = @'
        SELECT top 1000 SM.RecordID
            ,SM.Time
            ,SM.MachineName
            ,SM.Component
            ,SMA.AttributeValue
                        ,[Action] = Case 
                            when SM.MessageID = '30015' then 'Create'
                            when SM.MessageID = '30016' then 'Change'
                            when SM.MessageID = '30104' then 'Update'
                            End
        FROM v_StatusMessage AS SM with(nolock)
        INNER JOIN v_StatMsgAttributes AS SMA with(nolock) ON SMA.RecordID = SM.RecordID 
        WHERE SM.time >= DATEADD(day,-1,GETDATE())
        and SM.MessageID in ('30015','30016','30104')
'@


    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $connectionString
    $SqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandText = $SqlQuery
    $SqlAdapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter
    Write-Verbose "$commandName`: Running Query: `"$SqlQuery`""
    $SqlAdapter.SelectCommand = $SqlCmd
    $ds = New-Object -TypeName System.Data.DataSet
    $SqlAdapter.Fill($ds) | Out-Null
    $SqlCmd.Dispose()
  
    return $ds.tables[0]
}
#endregion


#region WMI connection
# we need a connection a a WMI SMS provider if we want to add collection infos
if (-NOT ($IgnoreCollectionInfo))
{
    # setting cim session options
    if ($ForceDCOMConnection)
    {
        Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Connect to `"$ProviderMachineName`" using DCOM" -ForegroundColor Green
        $cimSessionOption = New-CimSessionOption -Protocol Dcom
        $cimSession = New-CimSession -ComputerName $ProviderMachineName -SessionOption $cimSessionOption
    }
    else 
    {
        Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Connect to `"$ProviderMachineName`" using PSRemoting" -ForegroundColor Green
        Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - If PSRemoting takes long or does not work at all, try using the `"-ForceDCOMConnection`" parameter" -ForegroundColor Yellow
        $cimSession = New-CimSession -ComputerName $ProviderMachineName  
    }

    # getting sitecode
    try
    {
        $siteCode = Get-CimInstance -CimSession $cimSession -Namespace root\sms -Query 'Select SiteCode From SMS_ProviderLocation Where ProviderForLocalSite=1' -ErrorAction Stop | Select-Object -ExpandProperty SiteCode -First 1
    }
    catch 
    {
        Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Could not query Sitecode information. Please enter SiteCode manually:" -ForegroundColor Yellow
        $siteCode = Read-Host -Prompt 'Please enter SiteCode'
    }

    # getting ConfigMgr collection list
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Getting CollectionName and MemberCount from WMI" -ForegroundColor Green
    [array]$listOfCollections = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "select CollectionID, Name, Membercount from sms_collection"

    if(-NOT ($listOfCollections))
    {
        Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Could not get collection info from WMI, will proceed without collection names." -ForegroundColor Yellow
    }
    else 
    {
        Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - $($listOfCollections.Count) collections found!" -ForegroundColor Green
        # adding items to hashtable for faster lookup. Helpful if we are dealing with >=2000 collections
        $hashOfCollections = @{}
        foreach ($wmiCollection in $listOfCollections) 
        {
            $tmpCollInfo = "{0};{1}" -f $wmiCollection.Name, $wmiCollection.Membercount
            $hashOfCollections.Add($wmiCollection.CollectionID, $tmpCollInfo)
        }  
    }
}
#endregion


#region trying to get SQL Server Info
if ($AddUserData)
{
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Keep in mind that it might not be possible to match each user to the right collection update," -ForegroundColor Yellow
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - due to timing differences between logfile and database actions!" -ForegroundColor Yellow

    if ($SQLServerAndInstanceName -and $ConfigMgrDBName)
    {
        Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Using SQL server: `"$SQLServerAndInstanceName`" DB: `"$ConfigMgrDBName`"" -ForegroundColor Green
    }
    else
    {
        # just on case someone used -IgnoreCollectionInfo and -AddUserData together
        if (-NOT ($cimSession))
        {
            Write-Host 'sdfdsf'
            # setting cim session options
            if ($ForceDCOMConnection)
            {
                Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Connect to `"$ProviderMachineName`" using DCOM" -ForegroundColor Green
                $cimSessionOption = New-CimSessionOption -Protocol Dcom
                $cimSession = New-CimSession -ComputerName $ProviderMachineName -SessionOption $cimSessionOption
            }
            else 
            {
                Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Connect to `"$ProviderMachineName`" using PSRemoting" -ForegroundColor Green
                Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - If PSRemoting takes long or does not work at all, try using the `"-ForceDCOMConnection`" parameter" -ForegroundColor Yellow
                $cimSession = New-CimSession -ComputerName $ProviderMachineName  
            }        
        } #end "if (-NOT ($cimSession))"

        if (-NOT ($siteCode))
        {
            # getting sitecode
            try
            {
                $siteCode = Get-CimInstance -CimSession $cimSession -Namespace root\sms -Query 'Select SiteCode From SMS_ProviderLocation Where ProviderForLocalSite=1' -ErrorAction Stop | Select-Object -ExpandProperty SiteCode -First 1
            }
            catch 
            {
                Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Could not query Sitecode information. Please enter SiteCode manually:" -ForegroundColor Yellow
                $siteCode = Read-Host -Prompt 'Please enter SiteCode'
            }
        } #end if (-NOT ($siteCode))


        $query = "select * from SMS_SCI_SysResUse where RoleName ='SMS SQL Server' and SiteCode = '$($siteCode)'"
        [array]$ConfigMgrSQLServerList = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -query $query
        # taking the first server in case a clustered resource is used
        $ConfigMgrSQLServerProperties = $ConfigMgrSQLServerList[0].PropLists | Where-Object {$_.PropertyListName -eq 'Databases'}
        # something like: "SMS Database, server FQDN, db name"
        [array]$ConfigMgrSQLServer = $ConfigMgrSQLServerProperties.values -split ','

        # we might need to split DBname from instancename
        if ($ConfigMgrSQLServer[2] -match '\\') 
        {
            $tmpSQLList = $ConfigMgrSQLServer[2] -split '\\'

            $SQLServerAndInstanceName = "{0}\{1}" -f $ConfigMgrSQLServer[1].Trim(), $tmpSQLList[0].Trim()
            $ConfigMgrDBName = $tmpSQLList[1].Trim()   
        }
        else
        {
            $SQLServerAndInstanceName = $ConfigMgrSQLServer[1].Trim()
            $ConfigMgrDBName = $ConfigMgrSQLServer[2].Trim()      
        }

        if ($SQLServerAndInstanceName -and $ConfigMgrDBName)
        {
            Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Using SQL server: `"$SQLServerAndInstanceName`" DB: `"$ConfigMgrDBName`"" -ForegroundColor Green
        }
        else
        {
            Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - SQL Server and DB name not detected." -ForegroundColor Yellow
            Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Please use parameters: `"-SQLServerAndInstanceName`" and `"-ConfigMgrDBName`" or switch `"-IgnoreUserData`"" -ForegroundColor Yellow
            $cimSession | Remove-CimSession -ErrorAction SilentlyContinue
            break 
        }
    }
      
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Getting manual refresh user data for last 24h from DB" -ForegroundColor Yellow

    $manualRefreshUserData = Get-ExtendedCollectionInfoFromDB -SQLServerName ($SQLServerAndInstanceName) -DBName ($ConfigMgrDBName)
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - $($manualRefreshUserData.Count) entries for manual refreshes found" -ForegroundColor Green

    $manualRefreshUserDataArraylist = New-Object System.Collections.ArrayList

    $manualRefreshUserData | Group-Object -Property RecordID | ForEach-Object {
        $tmpUserObject = New-Object psobject | Select-Object DateTime, CollectionID, User, Component, MachineName, Action
        If ($_.Count -ne 2)
        {
            #Write-Host "StatusMessageRecordID `"$($_.Name)`" has more than 2 entries. Skipping" -ForegroundColor Yellow
        }
        else
        {
            foreach ($StatusMessageGroupItem in $_.Group)
            {
                $tmpUserObject.DateTime = ($StatusMessageGroupItem.Time).ToString('yyyy-MM-dd HH:mm:ss') 
                $tmpUserObject.Component = $StatusMessageGroupItem.Component
                $tmpUserObject.MachineName = $StatusMessageGroupItem.MachineName
                $tmpUserObject.Action = $StatusMessageGroupItem.Action
                if ($StatusMessageGroupItem.AttributeValue -match '\\')
                {
                    $tmpUserObject.User = $StatusMessageGroupItem.AttributeValue
                }
                else
                {
                    $tmpUserObject.CollectionID = $StatusMessageGroupItem.AttributeValue
                }
            }
            
            [void]$manualRefreshUserDataArraylist.Add($tmpUserObject)
        }
    }
}
if ($cimSession)
{
    $cimSession | Remove-CimSession -ErrorAction SilentlyContinue
}
#endregion


#region parsing lofiles
$collEvalSearchString = "(Start to process graph with).*(?<CollectionsInQueue> \d* ).*(?<Action>(Primary|Auxiliary|Express|Single))|(Process graph with these collections )(?<CollSingle>\[.{8}\])|(Process graph with these collections )(?<CollMulti>\[(.{8}, )+(.{8}])*)|(Results refreshed for collection )(?<ChangedColl>\w(\d|\w{7})), (?<ChangeCount>\d*)|(?<Async>Waiting for async query)|(?<End>EvaluateCollectionThread thread ends)"

# parsing log file/s
[array]$listOfLogFiles = Get-ChildItem -Path "$($CollEvalLogPath)\colleval*" | Sort-Object -Property LastWriteTime
Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - $($listOfLogFiles.Count) colleval logs found" -ForegroundColor Green
if ($listOfLogFiles.Count -gt 2)
{
    if (-NOT ($ForceUniqueEntries))
    {
        Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - In case you see blank lines in the GridView output, try using the -ForceUniqueEntries parameter!" -ForegroundColor Yellow
    }
}
Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Parsing logfiles" -ForegroundColor Green
$fullEvalListTmp = $listOfLogFiles | Select-String -Pattern $collEvalSearchString
Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - $($fullEvalListTmp.Count) log entries found" -ForegroundColor Green

if ($ForceUniqueEntries)
{
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Selecting unique log entries, in case we have duplicates due to copied files..." -ForegroundColor Green
    # run select-string again, but only on unique lines
    $fullEvalList = $fullEvalListTmp.line | Select-Object -Unique | Select-String -Pattern $collEvalSearchString
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - $($fullEvalList.Count) UNIQUE log entries found" -ForegroundColor Green
}
else 
{
    $fullEvalList = $fullEvalListTmp
}

Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Extracting coll eval information from log entries" -ForegroundColor Green
$objLoglineByThread = new-object System.Collections.ArrayList
$matchGroupCounter = 0 # used to detect a problem with select-string and named captures as used with $collEvalSearchString, where the names are missing
foreach ($collEvalItem in $fullEvalList)
{

    $logLineObject = New-Object psobject | Select-Object Step, EvalType, CollectionsInQueue, ChangedColl, CollectionsInQueueKnown, ChangeCount ,CollectionID, CollectionName, DateTime, StartTime, EndTime, TimeZoneOffset, Thread

    # extracting datetime and thread ID
    $matches = $null # resetting matches
    
    $null = $collEvalItem.Line -match "(?<datetime>\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}.\d*(\+|\-)\d*).*(?<thread>thread=\d*)"
    $logLineObject.Thread = (($Matches.thread) -replace "(thread=)", "")
    
    # splitting at timezone offset -> plus or minus 480 for example: '02-22-2021 03:19:10.431+480'
    $datetimeSplit = ($Matches.datetime) -split '(\+|\-)(\d*$)'
    $logLineObject.DateTime = [Datetime]::ParseExact($datetimeSplit[0], 'MM-dd-yyyy HH:mm:ss.fff', $null)
    
    # adding timezoneoffset $datetimeSplit[1] = "+ or -", $datetimeSplit[2] = minutes
    $logLineObject.TimeZoneOffset = "{0}{1}" -f $datetimeSplit[1], $datetimeSplit[2]


    foreach ($groupItem in $collEvalItem.Matches.Groups.where{($_.Length -ne 0 -and $_.Name -ne 0)})
    {
        $matchGroupCounter++
        switch ($groupItem.Name)
        {
            'Action'
            {
                $logLineObject.Step = 1
                $logLineObject.StartTime = ($logLineObject.DateTime).ToString('yyyy-MM-dd HH:mm:ss') 
                
                switch (($groupItem.Value).Trim())
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
            }
            'CollectionsInQueue'
            {
                $logLineObject.Step = 1
                $logLineObject.CollectionsInQueue = ($groupItem.Value).Trim()
            }
            'CollSingle' 
            {
                $logLineObject.Step = 2
                $logLineObject.CollectionID = ($groupItem.Value) -Replace "(\[|\]|,)", ""
                $logLineObject.CollectionsInQueueKnown = 1
            }
            'CollMulti'
            {
                $logLineObject.Step = 2
                $collGraphList = $groupItem.Value -split ','
                $logLineObject.CollectionID = $collGraphList[0] -Replace "(\[|\]|,)", ""
                $logLineObject.CollectionsInQueueKnown = $collGraphList
            }
            'ChangeCount'
            {
                $logLineObject.Step = 3
                $logLineObject.ChangeCount = $groupItem.Value
            }
            'ChangedColl'
            {
                $logLineObject.Step = 3
                $logLineObject.ChangedColl = $groupItem.Value
            }
            'End'
            {
                $logLineObject.Step = 4
                $logLineObject.EndTime = ($logLineObject.DateTime).ToString('yyyy-MM-dd HH:mm:ss') 
            }
            'Async'
            {
                Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - CollEval in bad state. Long running collection found. Filter colleval logs for thread ID: `"$($logLineObject.Thread)`"" -ForegroundColor Red
            }
            Default {}
        }
        
    }
    [void]$objLoglineByThread.Add($logLineObject)
}

if ($matchGroupCounter -eq 0)
{
    Write-Host "The Select-String cmdlet is not proper handling named matches. You might need to update .Net to fix that." -ForegroundColor Red
    break
}
#endregion


#region merging logentries to have just one entry per action
Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Merging log entries to just one entry per action" -ForegroundColor Green
# Bringing all threads in order by thread ID, datetime and step. That way we can easily combine entries to one entry 
$objLoglineByThreadSorted = $objLoglineByThread | Sort-Object -Property Thread, Datetime, Step  #| ogv

[array]$propertyList  = $null
$propertyList += 'EvalType'
$propertyList += 'CollectionsInQueue'
$propertyList += 'CollectionsInQueueKnown'
$propertyList += 'CollectionsRefreshed'
$propertyList += 'RunTimeInSeconds'
$propertyList += 'ChangeCount'
$propertyList += 'MemberCount'
$propertyList += 'FirstCollectionID'
$propertyList += 'FirstCollectionName'
$propertyList += 'StartTime'
$propertyList += 'EndTime'
$propertyList += 'TimeZoneOffset'
$propertyList += 'Thread'
$propertyList += 'User'
$propertyList += 'Component'
$propertyList += 'Machine'
$propertyList += 'Notes'


$outObj = New-Object System.Collections.ArrayList
$tmpObj = New-Object psobject | Select-Object $propertyList
$changeCount = 0
$refreshCount = 0
foreach ($logLineWithThreadID in $objLoglineByThreadSorted)
{
    $lastLine = $false

    switch ($logLineWithThreadID.step) 
    {
        1 # Start
        {
            $tmpObj.EvalType = $logLineWithThreadID.EvalType
            $tmpObj.CollectionsInQueue = $logLineWithThreadID.CollectionsInQueue
            # always setting thread in case we don't have all steps
            $tmpObj.Thread = $logLineWithThreadID.Thread
            $tmpObj.StartTime = $logLineWithThreadID.StartTime
            # save starttime to calculate runtime
            $startDateTime = $logLineWithThreadID.DateTime
        }
        
        2 # Graph info
        {
            $tmpObj.FirstCollectionID = $logLineWithThreadID.CollectionID
            $tmpObj.FirstCollectionName = $logLineWithThreadID.CollectionName
            $tmpObj.CollectionsInQueueKnown = $logLineWithThreadID.CollectionsInQueueKnown.Count
            # always setting thread in case we don't have all steps
            $tmpObj.Thread = $logLineWithThreadID.Thread

            # adding collection name to object
            if ($hashOfCollections)
            {
                $collectionNameString = $hashOfCollections[($logLineWithThreadID.CollectionID)]
                if ($collectionNameString)
                {
                    [array]$collectionNameAndMemberCount = $collectionNameString -split ';'
                    $tmpObj.FirstCollectionName = $collectionNameAndMemberCount[0]
                    $tmpObj.Membercount = $collectionNameAndMemberCount[1]
                }
                else
                {
                    $tmpObj.FirstCollectionName = 'NOT FOUND'
                }
            }
            else
            {
                $tmpObj.FirstCollectionName = 'NOT FOUND'
            }
        }

        3 # Refreshed Collections
        {
            $changeCount = $changeCount + $logLineWithThreadID.ChangeCount
            # counting actually refreshed collections
            $refreshCount++
            # always setting thread in case we don't have all steps
            $tmpObj.Thread = $logLineWithThreadID.Thread
        }

        4 # End
        {
            $lastLine = $true
            $tmpObj.EndTime = $logLineWithThreadID.Endtime
            $tmpObj.TimeZoneOffset = $logLineWithThreadID.TimeZoneOffset
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
        $tmpObj.CollectionsRefreshed = $refreshCount

        if (-NOT ($tmpObj.EvalType -and $tmpObj.FirstCollectionID -and $tmpObj.EndTime))
        {
            $tmpObj.Notes = "Missing info. Logfile might be truncated"    
        }
        [void]$outObj.Add($tmpObj)

        # re-create tmpobject and changecount since we reached the end of the eval cycle and we need another object for the next one
        $changeCount = 0
        $refreshCount = 0
        $tmpObj = New-Object psobject | Select-Object $propertyList
    }

}
#endregion


#region adding some additional info
if ($manualRefreshUserDataArraylist)
{ 
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Trying to match user data to collection eval information" -ForegroundColor Green
}
# adding some additional info
foreach ($outObjItem in $outObj)
{
      
    if ($outObjItem.CollectionsInQueue -ne $outObjItem.CollectionsInQueueKnown)
    {
        $outObjItem.Notes = "CollectionsInQueueKnown might be truncated in the log due to too many collections in graph"
    }

    if ($outObjItem.CollectionsRefreshed -gt $outObjItem.CollectionsInQueue)
    {
        $outObjItem.Notes = "Collections might be cloned from a previous eval graph, hence the CollectionsRefreshed count"
    }
    
    if ($manualRefreshUserDataArraylist)
    {    
        if ($outObjItem.EvalType -in ("ManualTree","ManualSingle"))
        {
            # actual datetime in DB needs timezoneoffset to be added
            # looking for entries +/- 5 minutes, since DB entries are not always happening at the same time as the evaluation
            $dbDateTimeTmpStart =  get-date((get-date($outObjItem.StartTime)).AddMinutes(($outObjItem.TimezoneOffset)-5))
            $dbDateTimeTmpEnd =  get-date((get-date($outObjItem.StartTime)).AddMinutes(($outObjItem.TimezoneOffset))+5)
            
            $tmpCollectionID = $outObjItem.FirstCollectionID

            # trying to find the right entry
            [array]$manualEntriesPerCollectionID = $manualRefreshUserDataArraylist.Where({($_.CollectionID -eq "$tmpCollectionID") -and (((Get-Date($_.DateTime)) -ge $dbDateTimeTmpStart) -and ((Get-Date($_.DateTime)) -le $dbDateTimeTmpEnd))})

            switch ($manualEntriesPerCollectionID.Count)
            {
                0 
                {
                    $outObjItem.Notes = 'No userinfo found'    
                }
                
                1 
                {
                    # found a matching entry based on collectionID and timerange
                    $outObjItem.User = $manualEntriesPerCollectionID[0].User
                    $outObjItem.Component = $manualEntriesPerCollectionID[0].Component
                    $outObjItem.Machine = $manualEntriesPerCollectionID[0].MachineName             
                }
                
                {$_ -gt 1} 
                {
                    # found multiple entries, need to find the right one based on time
                    # check if user is the same for all entries and pick the first one
                    [array]$userCount = $manualEntriesPerCollectionID | Select-Object -Property User -Unique
                    if ($userCount.Count -eq 1)
                    {
                        $outObjItem.User = $manualEntriesPerCollectionID[0].User
                        $outObjItem.Component = $manualEntriesPerCollectionID[0].Component
                        $outObjItem.Machine = $manualEntriesPerCollectionID[0].MachineName                         
                    }
                    else
                    {
                        $outObjItem.User = $manualEntriesPerCollectionID[0].User
                        $outObjItem.Component = $manualEntriesPerCollectionID[0].Component
                        $outObjItem.Machine = $manualEntriesPerCollectionID[0].MachineName
                        $outObjItem.Notes = 'Multiple user entries found. Picking first entry.'                      
                    }
                    
                }
            } # end switch

        }
        else
        {
            # seems to be a scheduled- or incremental refresh 
        }
    }
}             
#endregion  


#region creating statistics
$runtimeLast24h = 0
$outObj | Where-Object {$_.EndTime -ge (get-date).AddHours(-24)} | ForEach-Object {

    $runtimeLast24h = $runtimeLast24h + $_.RunTimeInSeconds
} 
$runtimeLast24h = $runtimeLast24h / 60 # convert to minutes

$longestSingleRuntime = $outObj | Sort-Object -Property RunTimeInSeconds -Descending | Select-Object -First 1
$longestSingleRuntimeMinutes = [System.Math]::Round($longestSingleRuntime.RunTimeInSeconds / 60)
#endregion


#region output data
Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Output data..." -ForegroundColor Green

if ($manualRefreshUserDataArraylist)
{
    $ogvTitle = 'User data list as a reference to the collection eval times list.'   
    $manualRefreshUserDataArraylist | Sort-Object DateTime -Descending | Out-GridView -Title $ogvTitle
}

# looping the output to be able to pick multiple collections
do
{
    $ogvTitle = "Collection Eval Times     -- Total runtime in last 24h: $([System.Math]::Round($runtimeLast24h)) minutes, longest single runtime: $($longestSingleRuntimeMinutes) minutes (thread: $($longestSingleRuntime.Thread)) --"
    $outObjSelected = $outObj | Sort-Object -Property EndTime -Descending | Out-GridView -Title $ogvTitle -OutputMode Single
    if ($outObjSelected)
    {
        $refreschedCollections = $objLoglineByThread.Where({$_.Step -eq 3 -and $_.Thread -eq $outObjSelected.Thread})

        # adding collection name and membercount to object
        foreach ($refreshedItem in $refreschedCollections)    
        {
            if ($hashOfCollections)
            {
                $collectionNameString = $hashOfCollections[($refreshedItem.ChangedColl)]
                if ($collectionNameString)
                {
                    if ([String]::IsNullOrEmpty($refreshedItem.Membercount))
                    {                    
                        [array]$collectionNameAndMemberCount = $collectionNameString -split ';'
                        $refreshedItem.CollectionName = $collectionNameAndMemberCount[0]
                        $refreshedItem | Add-Member NoteProperty "Membercount" -Value $collectionNameAndMemberCount[1]
                    }
                }
                else
                {
                    $refreshedItem.CollectionName = 'NOT FOUND'
                }
            }
            else 
            {
                $refreshedItem.CollectionName = 'NOT FOUND'
            }
        }
        Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Output data..." -ForegroundColor Green
        $ogvTitle2 = "Actually refreshed collections with refreshtype: {0}  - First collection in graph: {1}" -f $outObjSelected.EvalType,  $outObjSelected.FirstCollectionID
        $null = $refreschedCollections | Select-Object -Property ChangedColl, CollectionName ,ChangeCount, MemberCount, DateTime, Thread | Out-GridView -Title $ogvTitle2 -OutputMode Multiple
    }
}
while ($outObjSelected) 
Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - END" -ForegroundColor Green
#endregion 