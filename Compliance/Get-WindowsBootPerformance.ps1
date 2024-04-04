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

# Get the last boot event from the Microsoft-Windows-Diagnostics-Performance/Operational log with ID 100
$lastBootEvent = Try{Get-WinEvent -FilterHashtable @{logname="Microsoft-Windows-Diagnostics-Performance/Operational"; id=100} -MaxEvents 1 -ErrorAction SilentlyContinue}catch{}
if ($lastBootEvent)
{
    # Convert the event to XML to be able to read all properties
    [xml]$lastBootEventXML = $lastBootEvent.ToXml()
    # Create an ordered hash table to store the event data
    $outHash = [ordered]@{}
    # Loop through all data properties and add them to the hash table
    $lastBootEventXML.Event.EventData.Data | ForEach-Object {
        if ($_.'#text' -imatch '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\..*')
        {
            # Remove the milliseconds from the timestamp
            $_.'#text' = $_.'#text' -replace '\..*'
        }    
        $outHash.Add("$($_.Name)", "$($_.'#text')")
    }
    # Return the hash table
    return $outHash
}
else
{
    Write-Host 'No event data found'
}