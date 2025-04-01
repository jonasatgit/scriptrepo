<#
.Synopsis
    Script parse the output of Get-DeliveryOptimizationLog and show the details in a grid view
    
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
    #************************************************************************************************************

    Script to parse the output of Get-DeliveryOptimizationLog and show the details in a grid view
    Select a job and hit ok to see more details
    The script is made to help troubleshoot Delivery Optimization issues

#>

$GetDeliveryOptimizationLog = Get-DeliveryOptimizationLog

# Load some previous exported data from a different machine
#$GetDeliveryOptimizationLog = Import-Clixml -Path "C:\temp\Get-DeliveryOptimizationLog.xml"

if ($null -eq $GetDeliveryOptimizationLog)
{
    Write-Host "No Delivery Optimization logs found. Exiting."
    return
}

$searchPattern = 'Job\s(?<jobid>[0-9a-fA-F\-]+),\sDisplayName: (?<jobtype>.*)|TraceDownloadStartImpl|TraceDownloadCompletedImpl'
[array]$searchResult = $GetDeliveryOptimizationLog | select-string -Pattern $searchPattern  #| ogv


# First pass to get the job id and type
$outObject = [System.Collections.Generic.List[System.Object]]::new()
$jobHashTable = @{}
$i = 1
foreach ($line in $searchResult)
{
    Write-Progress -Activity "Processing" -Status "Processing line $i of $($searchResult.Count)" -PercentComplete (($i / $searchResult.Count) * 100)
    $i++
    # match again to work with groups easier
    $matches = $null
    if ($line.Line -imatch 'Job\s(?<jobid>[0-9a-fA-F\-]+),\sDisplayName: (?<jobtype>.*)')
    {
        $jobID = $matches.jobid
        $jobType = $matches.jobtype
        $downloadStart = $null

        # Prevent duplicates in the hashtable
        if ($jobHashTable.ContainsKey($jobID))
        {
            continue
        }

        $tempObj = [PSCustomObject][ordered]@{
            JobId = $jobID
            JobType = $jobType
            DownloadStartUTC = $null
            DownloadSec = $null
            SessionSec = $null
            DownloadUrl = $null
            CacheHost = $null
            DownloadActions = $null
            Background = $null
            Mode = $null
            DownloadModeSrc = $null
            IsVpn = $null
            FileMB = $null
            ReqMB = $null
            CdnMB = $null
            MccMB = $null
            RledbatMB = $null
            LanMB = $null
            LinkLocalMB = $null
            GroupMB = $null
            InetMB = $null
            LcacheMB = $null
            ConnCdn = $null
            ConnMcc = $null
            ConnLan = $null
            ConnLinkLocal = $null
            ConnGroup = $null
            ConnInet = $null
            DownMbits = $null
            UpMbits = $null
        }

        # Lets get the download start and download completed lines for this job id
        $startSearchPattern = ".*(TraceDownloadStartImpl).*($jobID).*"
        [array]$returnValueStart = $searchResult.Line | select-string -Pattern $startSearchPattern

        # replace everything except the datetime
        if ($returnValueStart.Count -ge 1)
        {
            $downloadStart = $returnValueStart[0].Matches.Value -replace '^(?<lookup>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z).*', '${lookup}'
            $tempObj.DownloadStartUTC = Get-Date($downloadStart) -format 'yyyy-MM-dd HH:mm:ss'
            $tempObj.DownloadUrl = $returnValueStart[0].Matches.Value -replace '.*(?<lookup>https?://[^\s,]+).*', '${lookup}'
            $tempObj.CacheHost = $returnValueStart[0].Matches.Value -replace '.*cacheHost = (?<lookup>.*?), localFile.*', '${lookup}' -replace 'GP:'
            $tempObj.Background = $returnValueStart[0].Matches.Value -replace '.*background\? (?<lookup>.*?),.*', '${lookup}'
            $tempObj.Mode = $returnValueStart[0].Matches.Value -replace '.*downloadMode = (?<lookup>.*?),.*', '${lookup}'
            $tempObj.DownloadModeSrc = $returnValueStart[0].Matches.Value -replace '.*downloadModeSrc = (?<lookup>.*?),.*', '${lookup}'
            $tempObj.IsVpn = $returnValueStart[0].Matches.Value -replace '.*isVpn = (?<lookup>.*?),.*', '${lookup}'
        }

        $endSearchPattern = ".*(TraceDownloadCompletedImpl).*($jobID).*"
        [array]$returnValueEnd = $searchResult.Line | select-string -Pattern $endSearchPattern

        # replace everything except the datetime
        if ($returnValueEnd.Count -ge 1)
        {
            # We need the download completed time from the last item of the array in case we have multiple entries
            # Multiple entries are possible if the job is retried for some reason or if the jobs paused and resumed
            $downloadCompleted = $returnValueEnd[-1].Matches.Value -replace '^(?<lookup>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z).*', '${lookup}'
            #$tempObj.DownloadCompleted = $downloadCompleted
            $tempObj.DownloadActions = $returnValueEnd.Count

            $fileData = $returnValueEnd[-1].Matches.Value -replace '.*bytes: (?<lookup>\[.*?\]),.*', '${lookup}'
            $tempObj.FileMB = "{0:N2}" -f [math]::round(($fileData -replace '\[File:\s(?<lookup>\d+),.*', '${lookup}') / 1MB,2)
            $tempObj.ReqMB = "{0:N2}" -f [math]::round(($fileData -replace '.*req: (?<lookup>\d+),.*', '${lookup}') / 1MB,2)
            $tempObj.CdnMB = "{0:N2}" -f [math]::round(($fileData -replace '.*CDN: (?<lookup>\d+),.*', '${lookup}') / 1MB,2)
            $tempObj.MccMB = "{0:N2}" -f [math]::round(($fileData -replace '.*DOINC: (?<lookup>\d+),.*', '${lookup}') / 1MB,2)
            $tempObj.RledbatMB = "{0:N2}" -f [math]::round(($fileData -replace '.*rledbat: (?<lookup>\d+),.*', '${lookup}') / 1MB,2)
            $tempObj.LanMB = "{0:N2}" -f [math]::round(($fileData -replace '.*LAN: (?<lookup>\d+),.*', '${lookup}') / 1MB,2)
            $tempObj.LinkLocalMB = "{0:N2}" -f [math]::round(($fileData -replace '.*LinkLocal: (?<lookup>\d+),.*', '${lookup}') / 1MB,2)
            $tempObj.GroupMB = "{0:N2}" -f [math]::round(($fileData -replace '.*Group: (?<lookup>\d+),.*', '${lookup}') / 1MB,2)
            $tempObj.InetMB = "{0:N2}" -f [math]::round(($fileData -replace '.*inet: (?<lookup>\d+),.*', '${lookup}') / 1MB,2)
            $tempObj.LcacheMB = "{0:N2}" -f [math]::round(($fileData -replace '.*lcache: (?<lookup>\d+),.*', '${lookup}') / 1MB,2)

            $connectionData = $returnValueEnd[-1].Matches.Value -replace '.*conns: (?<lookup>\[.*?\]),.*', '${lookup}'
            $tempObj.ConnCdn = $connectionData -replace '.*CDN: (?<lookup>\d+),.*', '${lookup}'
            $tempObj.ConnMcc = $connectionData -replace '.*DOINC: (?<lookup>\d+),.*', '${lookup}'
            $tempObj.ConnLan = $connectionData -replace '.*LAN: (?<lookup>\d+),.*', '${lookup}'
            $tempObj.ConnLinkLocal = $connectionData -replace '.*LinkLocal: (?<lookup>\d+),.*', '${lookup}'
            $tempObj.ConnGroup = $connectionData -replace '.*Group: (?<lookup>\d+),.*', '${lookup}'

            $tempObj.DownMbits = "{0:N2}" -f [math]::round(($returnValueEnd[-1].Matches.Value -replace '.*downBps: (?<lookup>\d+),.*', '${lookup}') / 1000000,2)
            $tempObj.UpMbits = "{0:N2}" -f [math]::round(($returnValueEnd[-1].Matches.Value -replace '.*upBps: (?<lookup>\d+),.*', '${lookup}') / 1000000,2)
            $tempObj.DownloadSec = "{0:N2}" -f [math]::round(($returnValueEnd[-1].Matches.Value -replace '.*timeMs: (?<lookup>\d+),.*', '${lookup}') / 1000,2)
            $tempObj.SessionSec = "{0:N2}" -f [math]::round(($returnValueEnd[-1].Matches.Value -replace '.*sessionTimeMs: (?<lookup>\d+),.*', '${lookup}') / 1000,2)

        }

        $outObject.Add($tempObj)
        # Hashtable to avoid duplicate entries
        $jobHashTable.Add($matches.jobid, $matches.jobtype)
    }

}
Write-Progress -Activity "Processing" -Completed -Status "Processing line $i of $($searchResult.Count)" -PercentComplete (($i / $searchResult.Count) * 100)

# output the data to a grid view
$ogvTitle = 'Delivery Optimization Jobs - Select a job and hit ok to see more details'
Do
{
    $selectedItem = $outObject | Out-GridView -Title $ogvTitle -OutputMode Single

    if ($selectedItem)
    {
        # Create calculated values
        $dateTime = @{Label="DateTime";Expression={Get-Date($_.Line -replace '^(?<lookup>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z).*', '${lookup}') -Format 'yyyy-MM-dd HH:mm:ss'}}
        # Just the jobID
        $jobIdFilter = @{Label="JobId";Expression={$selectedItem.JobId}}
        # Everything except the datetime at the start of the line
        $lineString = @{Label="LogText";Expression={$_.Line -replace '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z(?<lookup>.*)', '${lookup}'}}

        # Passthru to wait for user input and then rerun the selection
        $null = $GetDeliveryOptimizationLog | 
            select-string -Pattern $selectedItem.JobId | 
                Select-Object -Property $dateTime, $jobIdFilter, $lineString | 
                    Out-GridView -Title 'Delivery Optimization Job Details' -PassThru 
    }
}
While ($selectedItem)


