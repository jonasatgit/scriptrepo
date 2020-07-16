
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

# tiny script to output all available performance counter
# needs to be run as an admin

$counterList = Get-Counter -ListSet *
$outObj = $counterList | ForEach-Object {

    foreach($path in $_.Paths)
    {
        $tmpObj = New-Object -TypeName PSObject | Select-Object CounterSetName, CounterSetType, InstanceCount, Path, Description
        $tmpObj.CounterSetName = $_.CounterSetName
        $tmpObj.CounterSetType = $_.CounterSetType
        $tmpObj.InstanceCount = if($_.CounterSetType -eq 'SingleInstance'){1}else{$_.PathsWithInstances.Count}
        $tmpObj.Path = $path.Substring(1)
        $tmpObj.Description = $_.Description
        $tmpObj
        }
    
}


$selectedObjects = $outObj | Out-GridView -Title 'PerfCounter' -OutputMode Multiple


$outObj = $counterList.Where{($_.CounterSetName -in $selectedObjects.CounterSetName)} | ForEach-Object {
    
    foreach($path in $_.PathsWithInstances)
        {
            $tmpObj = New-Object -TypeName PSObject | Select-Object CounterSetName, CounterSetType, PathsWithInstances, Description
            $tmpObj.CounterSetName = $_.CounterSetName
            $tmpObj.CounterSetType = $_.CounterSetType
            $tmpObj.PathsWithInstances = $path.Substring(1)
            $tmpObj.Description = $_.Description
            $tmpObj
        }
    }

$outObj | Sort-Object -Property PathsWithInstances | Out-GridView -Title 'PerfCounter Instances' 