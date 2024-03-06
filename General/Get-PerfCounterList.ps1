
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
.SYNOPSIS
    Script to list all available performance counters on a system
.DESCRIPTION
    This script will list all available performance counters on a system
    The output will be displayed in a gridview and varies depending on the system and installed software and roles
    Admin permissions are required to run this script
.LINK
    https://guithub.com/jonasatgit/scriptrepo
#>
$outObj = [System.Collections.Generic.List[pscustomobject]]::new()
$outObjInstances = [System.Collections.Generic.List[pscustomobject]]::new()
Write-Host "Getting list of performance counters..." -ForegroundColor Green
[array]$counterlist = Get-Counter -ListSet *
Write-Host "Found $($counterlist.count) counters. Will loop through each to get the related instances..." -ForegroundColor Green
foreach($counter in $counterlist)
{
    
    foreach($path in $counter.Paths)
    {
        $instanceCounter = 0
        $pathSuffix = $path -replace '.*\\(.*?)$', '$1'
        $searchstring = '.\\{0}' -f $pathSuffix
        foreach($instance in $counter.PathsWithInstances)
        {
            if ($instance -imatch $searchstring)
            {
                $outObjInstances.Add([pscustomobject]@{
                    CounterSetName = $counter.CounterSetName
                    Counter = $path
                    CounterInstance = $instance
                    Description = $counter.Description
                })
                $instanceCounter++
            }
        }

        $outObj.Add([pscustomobject]@{
            CounterSetName = $counter.CounterSetName
            InstanceCount = $instanceCounter
            Counter = $path
            Description = $counter.Description
            
        })

    }
}

# output and loop if a counter has been selected
do
{
    $selectedObject = $outObj  | Out-GridView -Title ('List of performance counter. Select one and click ok to see related instances. Total number: {0}' -f $outObj.count) -OutputMode Single
    if ($selectedObject)
    {
        $title = ('Instances of {0}' -f $selectedObject.counter) 
        $outObjInstances | Where-Object {($_.CounterSetName -ieq $selectedObject.CounterSetName) -and ($_.Counter -ieq $selectedObject.counter)} | Out-GridView -Title $title -OutputMode Single
    }
}
while ($selectedObject)

