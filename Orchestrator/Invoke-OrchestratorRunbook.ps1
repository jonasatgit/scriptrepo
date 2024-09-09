<#
.Synopsis
    Script to invoke a System Center Orchestrator 2022 runbook from a ConfigMgr task sequence using a REST API call with credentials from task sequence variables
    
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

    Script to invoke a System Center Orchestrator 2022 runbook from a ConfigMgr task sequence using a REST API call with credentials.    
    The script will try to get the credentials from task sequence variables. If the credentials could not be determined, the script will prompt for credentials.
    The script will then try to get the runbook ID from the Orchestrator web service. If the runbook ID could not be determined, the script will stop.
    The script will then create a runbook job and wait for the runbook to complete. If the runbook does not complete within the specified time, the script will stop.

    The script will return an exit code of 1 if the runbook job failed or if the runbook ends with a warning.
    Warning typically means that the runbook started but did not fully complete.

    Permission requirements:
    The user used in the script must have read adn publish permissions on the runbook.
    Publish permission can be found in the permissions tab under advanced in the Runbook Designer.

    NOTE:
    Script output will always be written to the smsts.log file. (By default no sensitive information will be written to the smsts.log file)
    If you need to have the PowerShell run command with all parameters in the smsts.log, set the task sequence variable OSDLogPowerShellParameters to true.
    https://learn.microsoft.com/en-us/mem/configmgr/osd/understand/task-sequence-variables#OSDLogPowerShellParameters
    

.PARAMETER ScorchURI
    System Center Orchestrator web API service URI e.g. 'https://scorch.contoso.local:8181'

.PARAMETER MaxJobRuntimeSec
    The maximum time in seconds the script will wait for the runbook to complete. Default is 30 seconds

.PARAMETER UserVariableName
    The name of the task sequence variable that contains the username.

.PARAMETER PwdVariableName
    The name of the task sequence variable that contains the password.

.PARAMETER RunbookName
    The name of the runbook to start.

.PARAMETER RunbookParams
    A hashtable with the runbook parameters. 
    Example: @{'Parameter 1'='Some text';'Parameter 2'='Some other text'}

.PARAMETER TestMode
    A switch to enable test mode.
    In test mode the script will prompt for credentials.
    In production mode the script will try to get the credentials from task sequence variables.

.PARAMETER TestModeUserName
    The username to use in test mode. If not specified, the script will prompt for username.
    Example: 'contoso\svc-scorch-user'

.EXAMPLE
    Run a runbook in testmode with runbook parameters
    .\Invoke-OrchestratorRunbook.ps1 -ScorchURI 'https://orch.contoso.local:8181' -MaxJobRuntimeSec 10 -RunbookName 'New Runbook 02' -RunbookParams @{'Parameter 1'='Some text';'Parameter 2'='Some other text'} -TestMode

.EXAMPLE
    Run a runbook in testmode with runbook parameters and a given username
    .\Invoke-OrchestratorRunbook.ps1 -ScorchURI 'https://orch.contoso.local:8181' -MaxJobRuntimeSec 10 -RunbookName 'New Runbook 02' -RunbookParams @{'Parameter 1'='Some text';'Parameter 2'='Some other text'} -TestMode -TestModeUserName 'contoso\sctest'

.EXAMPLE
    Run a runbook in ConfigMgr task sequence mode with runbook parameters
    .\Invoke-OrchestratorRunbook.ps1 -ScorchURI 'https://orch.contoso.local:8181' -MaxJobRuntimeSec 10 -UserVariableName 'Variable1' -PwdVariableName 'Variable2' -RunbookName 'New Runbook 02' -RunbookParams @{'Parameter 1'='Some text';'Parameter 2'='Some other text'}

.LINK
    https://github.com/jonasatgit/scriptrepo

#>

[CmdletBinding()]
param(
    [string]$ScorchURI, # System Center Orchestrator web API service URI e.g. 'https://scorch.contoso.local:8181',
    [int]$MaxJobRuntimeSec = 30,
    [string]$UserVariableName = "Variable1",
    [string]$PwdVariableName = "Variable2",
    [string]$RunbookName,
    [hashtable]$RunbookParams,
    [switch]$TestMode,
    [string]$TestModeUserName
)

#region Get Credentils
if ($TestMode)
{
    if ([string]::IsNullOrEmpty($TestModeUserName))
    {
        $credential = Get-Credential -Message 'Please enter credentials to start a runbook'
    }
    else 
    {
        $credential = Get-Credential -Message 'Please enter the password to start a runbook' -UserName $TestModeUserName
    }
}
else 
{
    try 
    {
        # Create an instance of the TSEnvironment COM object
        $tsEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment

        # Read the task sequence variables
        $username = $tsEnv.Value("$userVariableName")
        $password = $tsEnv.Value("$pwdVariableName")

        # Convert the password to a secure string
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force

        # Create a PSCredential object
        $credential = New-Object System.Management.Automation.PSCredential ($username, $securePassword)
        Write-host "Credential read from task sequence variables"
    }
    catch 
    {
        Write-host "Credential could not been determined"
        Write-host $_
        Exit 1 # to let a task sequence step fail
    }
}
#endregion


#region getting runbook id
Write-Host "Will try to get RunbookID for runbook: `"$($RunbookName)`""
try 
{
    $parmSplat = @{
        Uri = '{0}/api/Runbooks?$filter=name eq ''{1}''' -f $OrchURI, $RunbookName
        Method = 'Get'
        Credential = $credential
        ErrorAction = 'Stop'
    }
    $runbooksList = Invoke-RestMethod @parmSplat    
}
catch 
{
    Write-Host $_
    Exit 1 # to let a task sequence step fail
}

if ($null -eq $runbooksList.value)
{
    Write-Host "No runbook found with name: `"$($RunbookName)`""
    Write-Host "Either the runbook does not exist or the user does not have read permissions. Will stop script."
    Exit 1 # to let a task sequence step fail
}
else 
{
    Write-Host "Will test if we have just one runbook with the name: `"$($RunbookName)`""
    Write-Host "Found $($runbooksList.value.count) runbooks with the name: `"$($RunbookName)`""
    if ($runbooksList.value.count -eq 0)
    {
        Write-Host "No runbook found with name: `"$($RunbookName)`"."
        Write-Host "Either the runbook does not exist or the user does not have read permissions. Will stop script."
        Exit 1 # to let a task sequence step fail
    }    
    elseif($runbooksList.value.count -gt 1)
    {
        Write-Host "Found $($runbooksList.value.count) runbooks with same name. The name must be unique. Will stop script." 
        Exit 1 # to let a task sequence step fail
    }
    else 
    {
        $runbookID = $runbooksList.value.ID
        Write-Host "Found runbook: `"$($RunbookName)`" with ID: `"$($runbookID)`""
    }
}
#endregion


# region create runbook job
try 
{
    Write-Host "Will create JSON body for runbook job"
    $body = [ordered]@{
        RunbookId = $runbookID
        CreatedBy = $null
        Parameters = $null
    }
    
    if($RunbookParams)
    {
        Write-Host "$($RunbookParams.Keys.count) runbook parameters passed to script"
        $longestValue = $RunbookParams.Values | Sort-Object { $_.Length } -Descending | Select-Object Length -First 1
        Write-Host "Largest parameter value has $($longestValue.Length) characters"
        # Will convert parameter hashtable to an array of hashtables
        # This is just to save some space and chars when dealing with the script parameters
        # Each hashtable will only contain one name and value pair
        $body.Parameters = @()
        foreach ($key in $RunbookParams.Keys)
        {
            $body.Parameters += @{'Name' = $key; 'Value' = $RunbookParams[$key]}
        }
    }

    Write-Host "Will create runbook job and post json definition"
    $invokeRunbookParamSplat = @{
        Uri = '{0}/api/Jobs' -f $OrchURI
        Body = ($body | ConvertTo-Json -Depth 10)
        Method = 'Post'
        ContentType = 'application/json'
        Credential = $credential
        ErrorAction = 'Stop'
    }
    $runbookJob = Invoke-RestMethod @invokeRunbookParamSplat
}
catch 
{
    Write-Host "Creation of runbook job failed"
    Write-Host $_
    if ($_ -imatch '\(400\) Bad Request')
    {
        Write-Host "Bad Request typically translates to a problem with runbook parameters"
        Write-Host "Please check the runbook parameter names passed to the script and the ones of the runbook"
        Write-Host "It might also be a missing `"`Publish`" permission on the runbook for the user used in this script"
    }
    Exit 1 # to let a task sequence step fail
}
Write-Host "Runbook job created"

#region Wait for the runbook result
Write-Host "Waiting for runbook job result"
$stoptWatch = New-Object System.Diagnostics.Stopwatch
$stoptWatch.Start()
try 
{
    do
    {
        Start-Sleep -Seconds 2
        $runbookJobParamSplat = @{
            Uri = '{0}/api/Jobs/{1}?&$expand=RunbookInstances' -f $OrchURI, $runbookJob.Id
            Method = 'Get' 
            ContentType = 'application/json'
            Credential = $credential
            ErrorAction = 'Stop'
        }
        $runbookJobResult = Invoke-RestMethod @runbookJobParamSplat

        $jobsStateString = 'Runbook job: {0} in state: {1}' -f $runbookJobResult.Id, $runbookJobResult.Status
        Write-host $jobsStateString
        
        if ($stoptWatch.Elapsed.TotalSeconds -ge $MaxJobRuntimeSec)
        {
            Write-Host ('Script waited for completion for {0} seconds. Timeout reached! Will end script' -f [math]::Round($stoptWatch.Elapsed.TotalSeconds))
        }
    }
    until (($runbookJobResult.Status -imatch 'Completed') -or ($stoptWatch.Elapsed.TotalSeconds -ge $MaxJobRuntimeSec))
    $stoptWatch.stop()

    # The runbook job has completed, but we need to check the status of the runbook instance to determine if the runbook was successful
    if ($runbookJobResult.RunbookInstances.Status -inotmatch 'Success')
    {
        Write-Host "Runbook completed with status: $($runbookJobResult.RunbookInstances.Status)"
        Exit 1 # to let a task sequence step fail
    }
    else 
    {
        Write-Host "Runbook: `"$($RunbookName)`" completed successfully"
    }
}
catch 
{
    Write-Host "Runbook job failed"
    Write-Host $_
    Exit 1 # to let a task sequence step fail
}
#endregion