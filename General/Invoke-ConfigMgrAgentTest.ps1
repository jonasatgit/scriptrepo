<#
.Synopsis
    Script to test the Configuration Manager Agent on a client machine
    
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

#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [int]$SystemUptimeThresholdInMinutes = 15
)

$script:outObject = [System.Collections.Generic.List[PSCustomObject]]::new()

#region Class TestResult
Class TestResult 
{
    [string]$TestName
    [string]$Status
    [string]$Message

    TestResult ([string]$testName, [string]$status, [string]$message) 
    {
        $this.TestName = $testName
        $this.Status = $status
        $this.Message = $message
    }
}
#endregion

#region Function Test-ConfigMgrAgentService
Function Test-ConfigMgrAgentService
{
    [CmdletBinding()]
    param()

    if (Get-Service -Name ccmexec -ErrorAction SilentlyContinue) 
    {
        $configMgrService = Get-Service -Name ccmexec

        # we also need to check if the system was just started, because in that case the service may be not yet started
        if ($configMgrService.Status -ieq 'Running') 
        {
            $outObject.Add([TestResult]::new("ServiceCheck","Pass","The Configuration Manager Agent Service (ccmexec) is running."))
            return     
        }
        else 
        {
            $outObject.Add([TestResult]::new("ServiceCheck","Fail","The Configuration Manager Agent Service (ccmexec) is not running. Current status: $($configMgrService.Status)."))        
            return   
        }
    }
    else 
    {
        $outObject.Add([TestResult]::new("ServiceCheck","Fail","The Configuration Manager Agent Service (ccmexec) is not installed on this machine."))
        return
    }
}
#endregion


function Test-ConfigMgrLogTimestamp
{
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline=$true)]
        [string]$logName,
        [int]$LogCheckFailThresholdInMinutes = 300
    )

    process
    {
        $logPath = '{0}\{1}' -f (Get-ConfigMgrLogsPath), $logName

        if (Test-Path -Path $logPath) 
        {
            # get the last line of the log file
            $lastLine = Get-Content -Path $logPath -Tail 1
            # date and time are in the following format in the log and need to be parsed accordingly
            # time="03:28:26.554+480" date="11-17-2025"

            try 
            {
                if ($lastLine -match 'time="(?<time>\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{3})"\s+date="(?<date>\d{2}-\d{2}-\d{4})"') 
                {
                    $timeString = $matches['time']
                    $dateString = $matches['date']

                    $dateTimeString = '{0} {1}' -f $dateString, $timeString.Substring(0,8)
                    $logDateTime = [datetime]::ParseExact($dateTimeString, 'MM-dd-yyyy HH:mm:ss', $null)

                    $timeDifference = (Get-Date) - $logDateTime
                    if ($timeDifference.TotalMinutes -le $LogCheckFailThresholdInMinutes) 
                    {
                        $outObject.Add([TestResult]::new("LogCheck","Pass","The log file '$logName' was updated recently at $logDateTime."))
                    }
                    else 
                    {
                        $outObject.Add([TestResult]::new("LogCheck","Fail","The log file '$logName' was last updated at $logDateTime, which is more than $LogCheckFailThresholdInMinutes minutes ago."))
                    }
                }
                else 
                {
                    $outObject.Add([TestResult]::new("LogCheck","Fail","Could not parse the timestamp from the last line of the log file '$logName'."))
                }
            }
            catch 
            {
                # covnersion failed. Lets use the last write time of the file instead
                $lastWriteTime = (Get-Item -Path $logPath).LastWriteTime
                $timeDifference = (Get-Date) - $lastWriteTime
                if ($timeDifference.TotalMinutes -le $LogCheckFailThresholdInMinutes)
                {
                    $outObject.Add([TestResult]::new("LogCheck","Pass","The log file '$logName' was updated recently at $lastWriteTime. Reading from the file direcly failed, but the last write time indicates recent activity."))
                }
                else 
                {
                    $outObject.Add([TestResult]::new("LogCheck","Fail","The log file '$logName' was last updated at $lastWriteTime, which is more than $LogCheckFailThresholdInMinutes minutes ago. Reading from the file direcly failed, thats why we are using the last write time."))
                }
            }
        }
        else 
        {
            $outObject.Add([TestResult]::new("LogCheck","Fail","File not found: $logPath"))
        }
    }
}


#region Function Get-ConfigMgrLogsPath
Function Get-ConfigMgrLogsPath
{
    [CmdletBinding()]
    param()

    $registryPath = 'HKLM:\SOFTWARE\Microsoft\CCM\Logging\@Global'
    $logPath = (Get-ItemProperty -Path $registryPath -Name 'LogDirectory' -ErrorAction SilentlyContinue).LogDirectory
    if ($logPath) 
    {
        return $logPath
    }
    else 
    {
        return "$env:windir\CCM\Logs"
    }
}
#endregion


#region Function Get-SystemUptimeInMinutes
Function Get-SystemUptimeInMinutes
{
    [CmdletBinding()]
    param()

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $lastBootUpTime = $os.LastBootUpTime
    $uptime = (Get-Date) - $lastBootUpTime
    return $uptime.totalminutes
}
#endregion


# MAIN FUNCTION

if ((Get-SystemUptimeInMinutes) -lt $SystemUptimeThresholdInMinutes)
{
    $outObject.Add([TestResult]::new("General","Warning","The system was started less than $SystemUptimeThresholdInMinutes minutes ago"))
    exit 0
}


Test-ConfigMgrAgentService
'PolicyAgent.log' | Test-ConfigMgrLogTimestamp -LogCheckFailThresholdInMinutes 20


$script:outObject #| Where-Object { $_.Status -in @("Fail") } 


if($script:outObject | Where-Object { $_.Status -in @("Fail") })
{
    exit 1
}
else
{
    exit 0
}
          