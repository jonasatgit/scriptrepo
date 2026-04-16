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


param 
(
    [string]$GroupName = "YourADGroupName",
    [bool]$LogToFile = $true,
    [string]$LogFile = "C:\Logs\Add-ComputerToADGroup.log"
)

# Add the local computer to a predefined AD group
$exitCode = 0

function Write-Log ($Message) 
{
    $entry = "{0} {1}" -f (Get-Date -Format 'yyyyMMdd-HH:mm:ss'), $Message
    if ($LogToFile) 
    {
        Add-Content -Path $LogFile -Value $entry
    } 
    else 
    {
        Write-Host $entry
    }
}

try 
{
    $computerName = "$env:COMPUTERNAME$"
    $searcher = [adsisearcher]"(&(objectClass=computer)(sAMAccountName=$computerName))"
    $computer = $searcher.FindOne()
    if (-not $computer) { throw "Computer '$env:COMPUTERNAME' not found in AD." }

    $searcher.Filter = "(&(objectClass=group)(cn=$GroupName))"
    $group = $searcher.FindOne()
    if (-not $group) { throw "Group '$GroupName' not found in AD." }

    $groupEntry = $group.GetDirectoryEntry()
    try 
    {
        $groupEntry.Add($computer.GetDirectoryEntry().Path)
        $groupEntry.CommitChanges()
        Write-Log "Added '$env:COMPUTERNAME' to group '$GroupName'."
    } 
    catch 
    {
        if ($_.Exception.InnerException.HResult -eq [int]0x80071392) 
        {
            Write-Log "'$env:COMPUTERNAME' is already a member of '$GroupName'. No action needed."
        } 
        else 
        {
            throw
        }
    }
} 
catch 
{
    Write-Log "ERROR: $_"
    $exitCode = $_.Exception.InnerException.HResult
    if (-not $exitCode) { $exitCode = 1 }
}

exit $exitCode
