<#
.SYNOPSIS
    Script to fix an issue with the NCSI internet connectivity service by installing a scheduled task that runs on NCSI events.
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
    [Switch]$Install,
    [Switch]$Uninstall
)

#region Start-NCSICheck DO NOT DELETE THIS LINE
<#
.SYNOPSIS
    Script to fix an issue with the NCSI internet connectivity service
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
Function Start-NCSICheck
{
    [CmdletBinding()]
    param
    (
        [int]$ScriptDelayInHours = 1
    )

    #region Function New-CustomEventMessage
    Function New-CustomEventMessage
    {
        param
        (
            [Parameter(Mandatory = $True)]
            [ValidateSet("StartScript", "EndScript", "InternetDetected", "FixStartedAlready", "StartFix", "Error")]
            [string]$EventType,
            [Parameter(Mandatory = $false)]
            [string]$EventMessage = "No message provided",
            [Parameter(Mandatory = $false)]
            [string]$EventLog = "Application",
            [Parameter(Mandatory = $false)]
            [string]$EventSource = "NCSICheckScript"
        )
        Switch ($EventType)
        {
            "StartScript"
            {
                $eventID = 1000
                $entryType = "Information"
            }
            "InternetDetected"
            {
                $eventID = 1001
                $entryType = "Information"
            }
            "FixStartedAlready"
            {
                $eventID = 1002
                $entryType = "Warning"
            }
            "StartFix"
            {
                $eventID = 1003
                $entryType = "Information"
            }
            "Error"
            {
                $eventID = 1004
                $entryType = "Error"
            }
            "EndScript"
            {
                $eventID = 1005
                $entryType = "Information"
            }
        }
        # validate if eventsource exists
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource))
        {
            [System.Diagnostics.EventLog]::CreateEventSource($EventSource, $EventLog)
        }
        Write-EventLog -LogName $EventLog -Source $EventSource -EventID $eventID -EntryType $entryType -Message $EventMessage
    }
    #endregion


    $scriptStartTime = Get-Date
    New-CustomEventMessage -EventType StartScript -EventMessage "Start of script"

    # eventlog filter for NCSI event
    $filterHashtableNCSI = @{
        LogName = 'Microsoft-Windows-NCSI/Operational'
        ID = 4042
    }

    # get NCSI event to be able to check the NCSI state
    $eventObj = Get-WinEvent -FilterHashtable $filterHashtableNCSI -MaxEvents 1

    # Internet and local are okay
    if ($eventObj.Message -imatch '(V4 Capability:) (Internet|Local)')
    {
        New-CustomEventMessage -EventType InternetDetected -EventMessage "NCSI detected Internet or Local connectivity. All good. Nothing to do."
    }
    else
    {
        New-CustomEventMessage -EventType Error -EventMessage "Wrong NCSI state detected! Will wait for 5 seconds and test again, to avoid false positives. $($eventObj.Message | Out-String)"   

        Start-Sleep -Seconds 5

        # Get event again to re-check NCSI state
        $eventObj = Get-WinEvent -FilterHashtable $filterHashtableNCSI -MaxEvents 1
    
        if ($eventObj.Message -imatch '(V4 Capability:) (Internet|Local)')
        {
            New-CustomEventMessage -EventType InternetDetected -EventMessage "NCSI detected Internet or Local connectivity. All good. Nothing to do."
        }
        else
        {

            # lets check if the script ran before by checking the custom event messages
            $filterHashtableScript = @{
                LogName = 'Application'
                ID = 1003 # 1003 -> FixStarted
                StartTime = ($scriptStartTime.AddHours(-$ScriptDelayInHours))
                ProviderName = 'NCSICheckScript'
            }

            [array]$eventScript = Get-WinEvent -FilterHashtable $filterHashtableScript -ErrorAction SilentlyContinue
            if ($eventScript.count -gt 0)
            {
                New-CustomEventMessage -EventType FixStartedAlready -EventMessage "The script started the fix before and should not run for $ScriptDelayInHours hour/s"        
            }
            else
            {
                # Will try to fix the state
                $wmiServices = Get-CimInstance -query "Select * from win32_process where name = 'svchost.exe'" -ErrorAction SilentlyContinue
                $wmiNlaSvc = $wmiServices | Where-Object {$_.CommandLine -like '*NlaSvc'}
                if ($wmiNlaSvc)
                {
                    New-CustomEventMessage -EventType StartFix -EventMessage "Found NlaSvc service process to kill. ID: $($wmiNlaSvc.ProcessId) Command: $($wmiNlaSvc.CommandLine)"
                    Stop-Process -Id $wmiNlaSvc.ProcessId -Force   

                    # Waiting before checking events again
                    Start-Sleep -Seconds 5
                    $eventObj = Get-WinEvent -FilterHashtable $filterHashtableNCSI -MaxEvents 1

                    # Internet and local are okay
                    if ($eventObj.Message -imatch '(V4 Capability:) (Internet|Local)')
                    {
                        New-CustomEventMessage -EventType InternetDetected -EventMessage "NCSI detected Internet or Local connectivity. All good. Nothing to do."
                    }
                    else
                    {
                        New-CustomEventMessage -EventType Error -EventMessage "NlaSvc service process kill did not fix the issue"
                    }
                }
                else
                {
                    New-CustomEventMessage -EventType Error -EventMessage "NlaSvc service process not found!! Not able to start fix"
                }
            }
        }
    }

    New-CustomEventMessage -EventType EndScript -EventMessage "End of script"
}
#endregion Start-NCSICheck DO NOT DELETE THIS LINE


<#
.SYNOPSIS
    Function to create a scheduled task that runs the NCSI check script on NCSI events.

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

.PARAMETER TaskName
    Name of the scheduled task to create. Default is "Invoke-NCSITest". 

.PARAMETER TaskPath
    Path of the scheduled task to create. Default is "\CUSTOM".

#>
function New-NCSITestTask
{
    param
    (
        [String]$TaskName = "Invoke-NCSITest",
        [String]$TaskPath = "\CUSTOM"
    )

$scheduledTaskXML = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-NCSI/Operational"&gt;&lt;Select Path="Microsoft-Windows-NCSI/Operational"&gt;*[System[Provider[@Name='Microsoft-Windows-NCSI'] and EventID=4042]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -File "C:\Install\NCSITest\Invoke-NCSITest.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
'@


    $null = Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Xml $scheduledTaskXML
}

<#
.SYNOPSIS
    Function to export the NCSI check script to a specified location.

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

.PARAMETER ScriptPath
    Path where the script should be exported. Default is "C:\Install\NCSITest".

.PARAMETER ScriptName
    Name of the script file. Default is "Invoke-NCSITest.ps1".

#>
Function Export-NCSIScript
{
    [CmdletBinding()]
    param
    (
        [string]$ScriptPath = "C:\Install\NCSITest",
        [string]$ScriptName = "Invoke-NCSITest.ps1"
    )

    if (-NOT (Test-Path $ScriptPath))
    {
        $null = New-Item -ItemType Directory -Path $ScriptPath -Force
    }
    
    $scriptFullPath = '{0}\{1}' -f $ScriptPath, $ScriptName
    $pattern = '(?s)(?m)(#region Start-NCSICheck.*?#endregion Start-NCSICheck)'
    $content = Get-Content -Raw -Path $PSCommandPath
    $matches = [regex]::Matches($content, $pattern)
    
    $functionText = $matches.Groups[1].Value

    $functionText | Out-File -FilePath $scriptFullPath -Force

    "           " | Out-File -FilePath $scriptFullPath -Append

    "Start-NCSICheck" | Out-File -FilePath $scriptFullPath -Append

}

#region MAIN LOGIC

if ($Install)
{

    Export-NCSIScript

    New-NCSITestTask

}


if ($Uninstall)
{
    # get scheduled task and unregister if exists
    $task = Get-ScheduledTask -TaskName "Invoke-NCSITest" -ErrorAction SilentlyContinue
    if ($task)
    {
        $null = $task | Unregister-ScheduledTask -Confirm:$false
    }

    # remove script files
    $scriptPath = "C:\Install\NCSITest\Invoke-NCSITest.ps1"
    if (Test-Path $scriptPath)
    {
        Remove-Item -Path $scriptPath -Force
    }

    # also remove the folder if empty
    $scriptFolder = "C:\Install\NCSITest"
    if (Test-Path $scriptFolder)
    {
        $files = Get-ChildItem -Path $scriptFolder
        if ($files.count -eq 0)
        {
            Remove-Item -Path $scriptFolder -Force
        }
    }
}

#endregion MAIN LOGIC