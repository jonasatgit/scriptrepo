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
            Out-Log -message "The Configuration Manager Agent Service (ccmexec) is running."
            $outObject.Add([TestResult]::new("ServiceCheck","Pass","The Configuration Manager Agent Service (ccmexec) is running."))
            return     
        }
        else 
        {
            Out-Log -message "The Configuration Manager Agent Service (ccmexec) is not running. Current status: $($configMgrService.Status)."
            $outObject.Add([TestResult]::new("ServiceCheck","Fail","The Configuration Manager Agent Service (ccmexec) is not running. Current status: $($configMgrService.Status)."))        
            return   
        }
    }
    else 
    {
        Out-Log -message "The Configuration Manager Agent Service (ccmexec) is not installed on this machine."
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
        [string]$logPath,
        [int]$LogCheckFailThresholdInMinutes = 300
    )

    process
    {

        if (-not $logPath) 
        {
            $logPath = '{0}\{1}' -f (Get-ConfigMgrLogsPath), $logName
        }    
        else 
        {
            $logPath = '{0}\{1}' -f $logPath, $logName
        }    

        if (Test-Path -Path $logPath) 
        {
            Out-Log -message "Checking log file: $logPath"
            # get the last line of the log file
            $lastLine = Get-Content -Path $logPath -Tail 1
            # date and time are in the following format in the log and need to be parsed accordingly
            # time="03:28:26.554+480" date="11-17-2025"

            try 
            {
                if ($lastLine -match 'time="(?<time>\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2,3})"\s+date="(?<date>\d{2}-\d{2}-\d{4})"') 
                {
                    $timeString = $matches['time']
                    $dateString = $matches['date']

                    $dateTimeString = '{0} {1}' -f $dateString, $timeString.Substring(0,8)
                    $logDateTime = [datetime]::ParseExact($dateTimeString, 'MM-dd-yyyy HH:mm:ss', $null)

                    $timeDifference = (Get-Date) - $logDateTime
                    if ($timeDifference.TotalMinutes -le $LogCheckFailThresholdInMinutes) 
                    {
                        Out-Log -message "The log file '$logName' was updated recently at $logDateTime."
                        $outObject.Add([TestResult]::new("LogCheck","Pass","The log file '$logName' was updated recently at $logDateTime."))
                    }
                    else 
                    {
                        Out-Log -message "The log file '$logName' was last updated at $logDateTime, which is more than $LogCheckFailThresholdInMinutes minutes ago."
                        $outObject.Add([TestResult]::new("LogCheck","Fail","The log file '$logName' was last updated at $logDateTime, which is more than $LogCheckFailThresholdInMinutes minutes ago."))
                    }
                }
                else 
                {
                    Out-Log -message "Could not parse the timestamp from the last line of the log file '$logName'."
                    $outObject.Add([TestResult]::new("LogCheck","Fail","Could not parse the timestamp from the last line of the log file '$logName'."))
                }
            }
            catch 
            {
                Out-Log -message "An error occurred while parsing the timestamp from the log file '$logName': $_. Exception.Message"
                # conversion failed. Lets use the last write time of the file instead
                $lastWriteTime = (Get-Item -Path $logPath).LastWriteTime
                $timeDifference = (Get-Date) - $lastWriteTime
                if ($timeDifference.TotalMinutes -le $LogCheckFailThresholdInMinutes)
                {
                    Out-Log -message "The log file '$logName' was updated recently at $lastWriteTime. Reading from the file direcly failed, but the last write time indicates recent activity."
                    $outObject.Add([TestResult]::new("LogCheck","Pass","The log file '$logName' was updated recently at $lastWriteTime. Reading from the file direcly failed, but the last write time indicates recent activity."))
                }
                else 
                {
                    Out-Log -message "The log file '$logName' was last updated at $lastWriteTime, which is more than $LogCheckFailThresholdInMinutes minutes ago. Reading from the file direcly failed."
                    $outObject.Add([TestResult]::new("LogCheck","Fail","The log file '$logName' was last updated at $lastWriteTime, which is more than $LogCheckFailThresholdInMinutes minutes ago. Reading from the file direcly failed, thats why we are using the last write time."))
                }
            }
        }
        else 
        {
            Out-Log -message "Log file not found: $logPath"
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
    param
    ()

    try 
    {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $lastBootUpTime = $os.LastBootUpTime
        $uptime = (Get-Date) - $lastBootUpTime
        return $uptime.totalminutes       
    }
    catch 
    {
        Out-Log -message "Not able to get system uptime: $($_.Exception.Message)"
        Out-Log -message "Setting default uptime to 60 minutes."
        $outObject.Add([TestResult]::new("WMIRepositoryCheck","Fail","Not able to get system uptime: $_.Exception.Message. Setting default uptime to 60 minutes."))
        return 60 # default to 60 minutes if we cannot get the uptime
    }

}
#endregion

#region Function Out-Log
Function Out-Log
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$message,
        [string]$logFilePath = $script:logPath
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "{0} {1}" -f $timestamp, $message
    Add-Content -Path $logFilePath -Value $logMessage
}
#endregion


#region Function Invoke-WmiRepositoryCheck
Function Invoke-WmiRepositoryCheck
{
    [CmdletBinding()]
    param()

    # winmgmt /verifyrepository
    # winmgmt /salvagerepository
    try 
    {
        # Check WMI repository consistency
        $wmicheck = & winmgmt /verifyrepository 2>&1
        if ($wmicheck -imatch "Error|Fehler|Inconsistent|0x80") 
        {
            Out-Log -message "Warning: WMI check failed: $($wmicheck -join ' ')"
            $outObject.Add([TestResult]::new("WMIRepositoryCheck","Warning","WMI check failed: $($wmicheck -join ' ')"))
        }
        else 
        {
            Out-Log -message "WMI repository is consistent."
            $outObject.Add([TestResult]::new("WMIRepositoryCheck","Pass","WMI repository is consistent."))
        }       
    }
    catch 
    {
        Out-Log -message "WMI check failed with exception: $($_.Exception.Message)"
        $outObject.Add([TestResult]::new("WMIRepositoryCheck","Warning","WMI check failed with exception: $($_.Exception.Message)"))
    }
}
#endregion


# MAIN FUNCTION
$script:logPath = '{0}\{1}-{2}.log' -f (Get-ConfigMgrLogsPath), ($MyInvocation.MyCommand.Name), (Get-Date -Format 'yyyyMMdd_HHmmss')

# Will test WMI repository consistency
Invoke-WmiRepositoryCheck

# Will test system uptime
Out-Log -message "Starting Configuration Manager Agent Tests."
if ((Get-SystemUptimeInMinutes) -lt $SystemUptimeThresholdInMinutes)
{
    Out-Log -message "The system was started less than $SystemUptimeThresholdInMinutes minutes ago. Skipping tests."
    $outObject.Add([TestResult]::new("General","Warning","The system was started less than $SystemUptimeThresholdInMinutes minutes ago"))
    exit 0
}

# Will test Configuration Manager Agent Service
Test-ConfigMgrAgentService

# Will test Configuration Manager Agent Log Timestamp
'PolicyAgent.log' | Test-ConfigMgrLogTimestamp -LogCheckFailThresholdInMinutes 20


# Output results
Out-Log -message "Configuration Manager Agent Tests completed. Results:"
foreach ($result in $script:outObject)
{
    $logMessage = "Test: {0}, Status: {1}, Message: {2}" -f $result.TestName, $result.Status, $result.Message
    Out-Log -message $logMessage
    Write-Output $logMessage
}

# Determine exit code based on test results
if($script:outObject | Where-Object { $_.Status -in @("Fail") })
{
    Out-Log -message "One or more tests have failed."
    exit 1
}
else
{
    Out-Log -message "All tests have passed."
    exit 0
}
          