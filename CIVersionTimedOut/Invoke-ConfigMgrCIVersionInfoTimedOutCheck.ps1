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
    This script will search for a VersionInfoTimedOut for ModelName in all CIAgent.log files

.DESCRIPTION
    This script will search for a VersionInfoTimedOut for ModelName in all CIAgent.log files
    It will then delete certain wmi entries for the corresponding CI
    The ccmexec service needs to be restarted afterwards. Not part of the script.
    

.LINK
    https://github.com/jonasatgit/scriptrepo    
#>


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


Function Get-ConfigMgrVersionInfoTimedOutModelName
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$LogPath
    
    )
    # Example: 
    #CIAgentJob({2535BA43-2097-45F0-A088-8D46ECE9DC5E}): CAgentJob::VersionInfoTimedOut for ModelName ScopeId_F39845A1-F303-4D3A-A303-6ECC327447D1/Application_7d1b5b09-123d-46d8-b4db-9217ce42de4f, version 12 not available.
    [array]$SelectStringResult = Get-ChildItem -Path $logPath -Filter "CIAgent*.log" | Sort-Object -Property LastWriteTime -Descending | Select-string -Pattern "CAgentJob::VersionInfoTimedOut"
    if($SelectStringResult)
    {
        $Matches = $null
        $null = $SelectStringResult[0].Line -match "VersionInfoTimedOut for ModelName (?<ModelName>.*?), version (?<Version>\d+)"

        # will overwrite searchString variable
        $searchString = $Matches['ModelName'] -replace "ScopeId_.*?/.*?_",""
        if($OutputInfo){Write-Host "Extracted searchstring is: $($searchString)" -ForegroundColor Cyan}
        #$Matches['Version'] # not used at the moment

        return $searchString
    }
    else
    {
        return $null    
    }
}

$logPath = Get-ConfigMgrClientLogPath

$appModelName = Get-ConfigMgrVersionInfoTimedOutModelName -LogPath $logPath

if ($appModelName)
{
    # Lets remove orphaned entries from Root\CCM\XmlStore class XmlDocument
    $wmiQuery = 'SELECT * FROM XmlDocument WHERE text like "%{0}%"' -f $appModelName
    [array]$xmlStoreDocuments = Get-WmiObject -namespace 'Root\CCM\XmlStore' -Query $wmiQuery 

    $wmiQuery = 'SELECT * FROM CCM_CITask'
    $ciTasks = Get-WmiObject -namespace 'ROOT\ccm\CITasks' -Query $wmiQuery

    foreach ($xmlDocument in $xmlStoreDocuments)
    {
        foreach ($ciTask in $ciTasks)
        {
            if ($ciTasks.RefJobs -contains $xmlDocument.ID)
            {
                $ciTask | Remove-WmiObject 
            }
        }
    }
    
    $xmlStoreDocuments | Remove-WmiObject 
    
    # Lets remove orphaned entries from root\ccm\DataTransferService class CCM_DTS_JobItemEx

    # NOTE: We might also need to clean entries from ROOT\ccm\DataTransferService:CCM_DTS_JobEx

    $wmiQuery = 'SELECT * FROM CCM_DTS_JobItemEx WHERE SourceFile like "%{0}%"' -f $appModelName
    [array]$dtsJobs = Get-WmiObject -namespace 'root\ccm\DataTransferService' -Query $wmiQuery
    if ($dtsJobs)
    {
        foreach ($job in $dtsJobs)
        {
            $wmiQuery = 'SELECT * FROM CCM_DTS_JobEx WHERE ID = "{0}"' -f $job.JobID
            Get-WmiObject -namespace 'root\ccm\DataTransferService' -Query $wmiQuery | Remove-WmiObject
        }

        $dtsJobs | Remove-WmiObject
    }


    # Lets also remove old state message entries
    $wmiQuery = 'SELECT * FROM CCM_StateMsg WHERE TopicID like "%{0}%"' -f $appModelName
    Get-WmiObject -namespace 'root\ccm\StateMsg' -Query $wmiQuery | Remove-WmiObject                
     
    
    Write-Output 'VersionInfoTimedOut error found and cleaned'

}
else
{
    Write-Output 'VersionInfoTimedOut error NOT found in log'
}