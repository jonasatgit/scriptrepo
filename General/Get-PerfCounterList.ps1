
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
# Source: https://github.com/jonasatgit/scriptrepo/blob/master/General/Get-PerfCounterList.ps1
# tiny script to output all available performance counter
# needs to be run as an admin

$outObj = [System.Collections.Generic.List[pscustomobject]]::new()
foreach($counter in (Get-Counter -ListSet *))
{
    
    foreach($path in $counter.Paths)
    {
        $outObj.Add([pscustomobject]@{
            CounterSetName = $counter.CounterSetName
            Counter = $path
            Description = $counter.Description
        })

    }

    foreach($path in $counter.PathsWithInstances)
    {
        $outObj.Add([pscustomobject]@{
            CounterSetName = $counter.CounterSetName
            Counter = $path
            Description = $counter.Description
        })
    }

}

$outObj | Sort-Object -Property CounterSetName, Counter | Out-GridView -Title ('PerfCounter Instances. Total number: {0}' -f $outObj.count) 