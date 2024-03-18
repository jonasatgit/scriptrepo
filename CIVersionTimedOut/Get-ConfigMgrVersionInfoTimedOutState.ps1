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


function Get-ConfigMgrClientLogPath
{

    # Get the ConfigMgr client log path from the registry   
    try
    {
        # Define the registry path for the ConfigMgr client
        $registryPath = "HKLM:\SOFTWARE\Microsoft\CCM\Logging\@Global"

        # Get the ConfigMgr client log path from the registry
        $logPath = Get-ItemPropertyValue -Path $registryPath -Name "LogDirectory"
    }catch
    {
        Write-Output "ConfigMgr client log path not found $($_)"
        Exit 1
    }

    return $logPath
}


$logPath = Get-ConfigMgrClientLogPath

$outObj = [System.Collections.Generic.List[string]]::new()
[array]$SelectStringResult = Get-ChildItem -Path $logPath -Filter "CIAgent*.log" | Sort-Object -Property LastWriteTime -Descending | Select-string -Pattern "CAgentJob::VersionInfoTimedOut"
if($SelectStringResult)
{
    foreach ($item in $SelectStringResult)
    {
        $Matches = $null
        $null = $item.Line -imatch "VersionInfoTimedOut for ModelName (?<ModelName>.*?), version (?<Version>\d+)"    
        $outString = '{0}/{1}' -f ($Matches['ModelName'] -replace "ScopeId_.*?/"), ($Matches['Version'])
        $outObj.Add($outString)
    }
    Write-Output ($outObj | Select-Object -Unique)
}
else
{
    Write-Output "No VersionInfoTimedOut error found"
}
