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
$event = Get-WinEvent -FilterHashtable $filterHashtableNCSI -MaxEvents 1

# Internet and local are okay
if ($event.Message -imatch '(V4 Capability:) (Internet|Local)')
{
    New-CustomEventMessage -EventType InternetDetected -EventMessage "NCSI detected Internet or Local connectivity. All good. Nothing to do."
}
else
{
    New-CustomEventMessage -EventType Error -EventMessage "Wrong NCSI state detected! $($event.Message | Out-String)"   

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
            $event = Get-WinEvent -FilterHashtable $filterHashtableNCSI -MaxEvents 1

            # Internet and local are okay
            if ($event.Message -imatch '(V4 Capability:) (Internet|Local)')
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

New-CustomEventMessage -EventType EndScript -EventMessage "End of script"