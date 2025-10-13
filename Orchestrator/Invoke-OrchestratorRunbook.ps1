<#
.Synopsis
    Script to invoke a System Center Orchestrator 2022 or higher runbook from a ConfigMgr task sequence using a REST API call with credentials from task sequence variables
    
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
    The script will try to get the credentials from task sequence variables.
    The task sequence variables must be set before the script is run and the names can be defined via the parameters UserVariableName and PwdVariableName of this script.
    The main reason to read task sequence variables is to avoid storing sensitive information in the script and to avoid accidental exposure of sensitive information in any log file.
    The script can also be run in test mode where the script will prompt for credentials.
    The script will then try to get the runbook ID from the Orchestrator web service. If the runbook ID could not be determined, the script will stop.
    The script will then create a runbook job and wait for the runbook to complete. If the runbook does not complete within the specified time, the script will stop.

    The script will return an exit code of 1 if the runbook job failed or if the runbook ends with a warning.
    Warning typically means that the runbook started but did not fully complete.

    Permission requirements:
    The user used in the script must have read and publish permissions on the runbook.
    Publish permission can be found in the permissions tab under advanced in the Runbook Designer.

    NOTE:
    Script output will always be written to the smsts.log file. (By default no sensitive information will be written to the smsts.log file)
    If you need to have the PowerShell run command with all parameters in the smsts.log, set the task sequence variable OSDLogPowerShellParameters to true.
    https://learn.microsoft.com/en-us/mem/configmgr/osd/understand/task-sequence-variables#OSDLogPowerShellParameters
    

.PARAMETER ScorchURI
    System Center Orchestrator web API service URI e.g. 'https://scorch.contoso.local:8181'

.PARAMETER MaxJobRuntimeSec
    The maximum time in seconds the script will wait for the runbook to complete. Default is 30 seconds
    In case of error 500 internal server error, the script will wait up to 2 times the MaxJobRuntimeSec time.

.PARAMETER UserVariableName
    The name of the task sequence variable that contains the username.
    Default is 'Variable1'. Adjust this parameter if you want to use a different task sequence variable name.

.PARAMETER PwdVariableName
    The name of the task sequence variable that contains the password.
    Default is 'Variable2'. Adjust this parameter if you want to use a different task sequence variable name.

.PARAMETER RunbookName
    The name of the runbook to start.

.PARAMETER RunbookParams
    A hashtable with input runbook parameters. Leave empty if no parameters are needed.
    Example: @{'Parameter 1'='Some text';'Parameter 2'='Some other text'}

.PARAMETER RunbookOutParamsList
    An array of runbook output parameters to return. If no output parameters are needed, leave empty.
    Example: @('Parameter 1', 'Parameter 2')
    Output parameters must be defined in the runbook first and can be used to return values from the runbook.
    - Go to the runbook designer and open the runbook. 
    - Right click on the runbook and select "Properties"
    - Go to "Returned data" and add a new output parameter
    - Add a "return data" activity to the runbook and set the output parameter name to the name of the output parameter defined in the runbook properties
    Use the same name in the RunbookOutParamsList parameter to get the output parameter value from the runbook.

.PARAMETER RunbookOutParamType
    The type of the runbook output parameters to return.
    Default is 'Object'. Possible values are 'Hashtable', 'JSON' and 'Object'.
    - Hashtable: Returns the output parameters as a hashtable
    - JSON: Returns the output parameters as a JSON string
    - Object: Returns the output parameters as a PowerShell object

.PARAMETER TaskSequenceMode
    A switch to enable ConfigMgr task sequence mode.
    That means that the script will read the credentials from task sequence variables.
    If not set, the script will prompt for credentials.

.PARAMETER UserName
    If not specified, the script will prompt for a username.
    If set, the script will use the given username to prompt for the password.

.PARAMETER OutputAllOutParameters
    A switch to enable the output of all runbook output parameters.
    If set, the script will return all output parameters defined in the runbook
    and not just the ones defined in the RunbookOutParamsList parameter.
    The RunbookOutParamsList parameter will be ignored if this switch is set.

.EXAMPLE
    Run a runbook without runbook parameters
    .\Invoke-OrchestratorRunbook.ps1 -ScorchURI 'https://orch.contoso.local:8181' -RunbookName 'New Runbook 02'

.EXAMPLE
    Run a runbook with runbook parameters
    .\Invoke-OrchestratorRunbook.ps1 -ScorchURI 'https://orch.contoso.local:8181' -RunbookName 'New Runbook 02' -RunbookParams @{'Parameter 1'='Some text';'Parameter 2'='Some other text'}

.EXAMPLE
    Run a runbook with runbook parameters and a given username
    .\Invoke-OrchestratorRunbook.ps1 -ScorchURI 'https://orch.contoso.local:8181' -RunbookName 'New Runbook 02' -RunbookParams @{'Parameter 1'='Some text';'Parameter 2'='Some other text'} -UserName 'contoso\sctest'

.EXAMPLE
    Run a runbook in ConfigMgr task sequence mode with runbook parameters via the "Run PowerShell Script" step.
    Copy the below example into the parameters field of the "Run PowerShell Script" step and adjust the parameters to fit your environment.    
    -ScorchURI 'https://orch.contoso.local:8181' -RunbookName 'New Runbook 02' -RunbookParams @{'Parameter 1'='Some text';'Parameter 2'='Some other text'} -TaskSequenceMode -UserVariableName 'TS-Variable1' -PwdVariableName 'TS-Variable2'

.EXAMPLE
    Run a runbook in ConfigMgr task sequence mode with runbook parameters passed via task sequence variables via the "Run PowerShell Script" step.
    Copy the below example into the parameters field of the "Run PowerShell Script" step and adjust the parameters to fit your environment.    
    -ScorchURI '%TS-ScorchURI%' -RunbookName '%TS-RunbookName%' -RunbookParams @{'Parameter 1'='%TS-RunbookParam1%';'Parameter 2'='%TS-RunbookParam1%'} -TaskSequenceMode -UserVariableName 'TS-Variable1' -PwdVariableName 'TS-Variable2'

.EXAMPLE
    Run a runbook in ConfigMgr task sequence mode with runbook output parameters via the "Run PowerShell Script" step.
    Copy the below example into the parameters field of the "Run PowerShell Script" step and adjust the parameters to fit your environment.    
    -ScorchURI 'https://orch.contoso.local:8181' -RunbookName 'New Runbook 02' -RunbookOutParamsList @('Parameter 1', 'Parameter 2') -TaskSequenceMode -UserVariableName 'TS-Variable1' -PwdVariableName 'TS-Variable2'

.LINK
    https://github.com/jonasatgit/scriptrepo

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    # System Center Orchestrator web API service URI e.g. 'https://scorch.contoso.local:8181'
    [string]$ScorchURI, 
    
    [Parameter(Mandatory = $false)]
    # 10 second to 30 minutes
    [ValidateRange(10, 1800)] 
    [int]$MaxJobRuntimeSec = 30,

    [Parameter(Mandatory = $false)]
    # The name of the task sequence variable that contains the username. Default is 'Variable1'. Adjust this parameter if you want to use a different task sequence variable name.
    [string]$UserVariableName = "Variable1",

    [Parameter(Mandatory = $false)]
    # The name of the task sequence variable that contains the password. Default is 'Variable2'. Adjust this parameter if you want to use a different task sequence variable name.
    [string]$PwdVariableName = "Variable2",

    [Parameter(Mandatory = $true)]
    # The name of the runbook to start. The name must be unique in the Orchestrator web service
    [string]$RunbookName, 

    [Parameter(Mandatory = $false)]
    # A hashtable with input runbook parameters. Leave empty if no parameters are needed. Example: @{'Parameter 1'='Some text';'Parameter 2'='Some other text'}
    [hashtable]$RunbookParams, 

    [Parameter(Mandatory = $false)]
    # An array of runbook output parameters to return. If no output parameters are needed, leave empty. Example: @('Parameter 1', 'Parameter 2')
    [array]$RunbookOutParamsList, 

    [Parameter(Mandatory = $false)]
    # A switch to enable the output of all runbook output parameters. If set, the script will return all output parameters defined in the runbook
    # and not just the ones defined in the RunbookOutParamsList parameter. The RunbookOutParamsList parameter will be ignored if this switch is set.
    [Switch]$OutputAllOutParameters,

    [Parameter(Mandatory = $false)]
    # The type of the runbook output parameters to return. Default is 'Object'. Possible values are 'Hashtable', 'JSON' and 'Object'.
    [ValidateSet("Hashtable", "JSON", "Object")]
    [string]$RunbookOutParamType = 'Object',

    [Parameter(Mandatory = $false)]
    # A switch to read the credentials from task sequence variables. If not set, the script will prompt for credentials.
    [switch]$TaskSequenceMode, 
    
    [Parameter(Mandatory = $false)]
    # If not specified, the script will prompt for a username
    [string]$UserName
)



#region Function Get-CredentialFromTaskSequenceVariables
Function Get-CredentialFromTaskSequenceVariables
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$UserVariableName,

        [Parameter(Mandatory = $true)]
        [string]$PwdVariableName
    )

    # Create an instance of the TSEnvironment COM object
    $tsEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
    # Read the task sequence variables
    $username = $tsEnv.Value("$UserVariableName")
    $password = $tsEnv.Value("$PwdVariableName")

    # Convert the password to a secure string
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force

    # Create a PSCredential object
    return New-Object System.Management.Automation.PSCredential ($username, $securePassword)
}
#endregion

#region Function Get-OrchestratorRunbookByName
<#
.SYNOPSIS
    Function to get a runbook by name from the Orchestrator web service.

.DESCRIPTION
    Function to get a runbook by name from the Orchestrator web service.
    The function will return the runbook object if found, otherwise it will return nothing.

    IMPORTANT:
    The runbook name must be unique in the Orchestrator web service.
    Otherwise the function will return all runbooks with the given name.
    Save the output of the function to a variable and check the count of the returned runbooks.
    Example: [array]$listOfRunbooks = Get-OrchestratorRunbookByName -ScorchURI '<URL>' -RunbookName 'TestRunbook' -credential $credential

    The function requires a valid credential to access the Orchestrator web service.

    Use Get-Credential to get a valid credential object.
    Or use Get-CredentialFromTaskSequenceVariables to get a credential object from a running task sequence.

    Example return object:
    Id               : 88fcc67a-2898-49b6-8761-d6aafbec798f
    FolderId         : 1f12e102-0011-4dc6-b016-6cd228228fa9
    Name             : TestRunbook
    Description      : 
    CreationTime     : 2025-06-16T15:25:31.64+02:00
    CreatedBy        : 
    LastModifiedTime : 2025-06-16T16:50:26+02:00
    LastModifiedBy   : S-1-5-21-558107984-3242759386-571497543-500
    IsMonitor        : False
    Path             : \TestRunBooks\TestRunbook
    CheckedOutBy     : 
    CheckedOutTime   : 
    Authorizations   : {}
#>
Function Get-OrchestratorRunbookByName
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ScorchURI,
        [Parameter(Mandatory = $true)]
        [string]$RunbookName,
        [Parameter(Mandatory = $true)]
        [PSCredential]$credential
    )

    $parmSplat = @{
        Uri = '{0}/api/Runbooks?$filter=name eq ''{1}''' -f $ScorchURI, $RunbookName
        Method = 'Get'
        Credential = $credential
        ErrorAction = 'Stop'
    }
    $runbooksList = Invoke-RestMethod @parmSplat    
    return $runbooksList.value
}
#endregion

#region Function Invoke-OrchestratorRunbookJob
<#
.SYNOPSIS
    Function to invoke a runbook job in the Orchestrator web service.

.DESCRIPTION
    Function to invoke a runbook job in the Orchestrator web service.

    The function will create a runbook job with the given runbook ID and parameters in case the runbook needs parameters to start.

#>
Function Invoke-OrchestratorRunbookJob
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ScorchURI,

        [Parameter(Mandatory = $true)]
        [string]$RunbookID,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [hashtable]$RunbookParams
    )

    $body = [ordered]@{
        RunbookId = $runbookID
        CreatedBy = $null
        Parameters = $null
    }
    
    if($RunbookParams)
    {
        Write-Host "$($RunbookParams.Keys.count) runbook parameter/s passed to script"
        $longestValue = $RunbookParams.Values | Sort-Object { $_.Length } -Descending | Select-Object Length -First 1
        Write-Host "Largest parameter value has $($longestValue.Length) characters"
        # Will convert parameter hashtable to an array of hashtables
        # This is just to save some space and chars when dealing with the script parameters
        # Each hashtable will only contain one name and value pair
        Write-Host "Adding runbook parameters to runbook job"
        $body.Parameters = @()
        foreach ($key in $RunbookParams.Keys)
        {
            $body.Parameters += @{'Name' = $key; 'Value' = $RunbookParams[$key]}
        }
    }

    $invokeRunbookParamSplat = @{
        Uri = '{0}/api/Jobs' -f $ScorchURI
        Body = ($body | ConvertTo-Json -Depth 10)
        Method = 'Post'
        ContentType = 'application/json'
        Credential = $credential
        ErrorAction = 'Stop'
    }

    $runbookJobResult = Invoke-RestMethod @invokeRunbookParamSplat

    return $runbookJobResult
}
#endregion

#region Function Get-OrchestratorRunbookJobStatus
Function Get-OrchestratorRunbookJobStatus
{
    [CmdletBinding()]
    param
    (
        [string]$ScorchURI,
        [string]$JobID,
        [PSCredential]$Credential,
        [int]$MaxJobRuntimeSec = 30,
        [switch]$WaitForCompletion
    )

    $outObject = [PSCustomObject]@{
        JobID = $JobID
        Status = 'Unknown'
        RunbookInstanceStatus = 'Unknown'
        RunbookInstanceID = $null
    }

    Write-Host "Getting status of runbook job with ID: $jobID"
    $stoptWatch = New-Object System.Diagnostics.Stopwatch
    $stoptWatch.Start()
    do
    {
        Start-Sleep -Seconds 2
        $runbookJobParamSplat = @{
            Uri = '{0}/api/Jobs/{1}?&$expand=RunbookInstances' -f $ScorchURI, $jobID
            Method = 'Get' 
            ContentType = 'application/json'
            Credential = $Credential
            ErrorAction = 'Stop'
        }
        $runbookJobResult = Invoke-RestMethod @runbookJobParamSplat

        $jobsStateString = 'Runbook job: {0} in state: {1}' -f $runbookJobResult.Id, $runbookJobResult.Status
        Write-host $jobsStateString
        
        if ($stoptWatch.Elapsed.TotalSeconds -ge $MaxJobRuntimeSec)
        {
            Write-Host ('Script waited for completion for {0} seconds. Timeout reached! Will no longer wait for job result.' -f [math]::Round($stoptWatch.Elapsed.TotalSeconds))
        }
    }
    until (($runbookJobResult.Status -imatch 'Completed') -or ($stoptWatch.Elapsed.TotalSeconds -ge $MaxJobRuntimeSec) -or -not $WaitForCompletion)
    $stoptWatch.stop()

    # Save the status to the output object
    $outObject.Status = $runbookJobResult.Status
    $outObject.RunbookInstanceStatus = $runbookJobResult.RunbookInstances.Status
    $outObject.RunbookInstanceID = $runbookJobResult.RunbookInstances.Id

    # The runbook job has completed, but we need to check the status of the runbook instance to determine if the runbook was successful
    if ($outObject.RunbookInstanceStatus -inotmatch 'Success')
    {
        Write-Host "Runbook completed with status: $($outObject.RunbookInstanceStatus)"
        If ($outObject.RunbookInstanceStatus -imatch 'warning')
        {
            Write-Host 'The runbook started successfully but did not fully complete'
            Write-Host 'Warning could also mean that a parameter was missing for the initialization of the runbook'
        }
    }
    else 
    {
        Write-Host "Runbook: `"$($RunbookName)`" completed successfully"
    }
    # Return the output object with job ID and status
    return $outObject 
}
#endregion

#region Function Get-OrchestratorRunbookOutputParameters
Function Get-OrchestratorRunbookOutputParameters
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ScorchURI,

        [Parameter(Mandatory = $true)]
        [string]$runbookInstanceID,

        [Parameter(Mandatory = $true)]
        [PSCredential]$credential,

        [Parameter(Mandatory = $false)]
        [array]$RunbookOutParamsList,

        [Parameter(Mandatory = $false)]
        # The type of the runbook output parameters to return. Default is 'Object'. Possible values are 'Hashtable', 'JSON' and 'Object'.
        [ValidateSet("Hashtable", "JSON", "Object")]
        [string]$RunbookOutParamType = 'Object'
    )

    $runbookInstanceParamSplat = @{
        Uri = '{0}/api/RunbookInstances/{1}?&$expand=RunBookInstanceParameters' -f $ScorchURI, $runbookInstanceID
        Method = 'Get' 
        ContentType = 'application/json'
        Credential = $credential
        ErrorAction = 'Stop'
    }

    Write-Host "Will get runbook instance parameters for runbook instance ID: $runbookInstanceID"
    $runbookInstance = Invoke-RestMethod @runbookInstanceParamSplat

    $runbookOutParams = @{}
    Write-Host "Getting runbook out parameter values"
    # Lets get the out parameters from the runbook instance of type 'Out'
    foreach ($runbookInstanceParameter in ($runbookInstance.RunbookInstanceParameters | Where-Object -Property Direction -eq 'Out'))
    {
        # Either output all out parameters or only the ones defined in the RunbookOutParamsList
        if($null -eq $RunbookOutParamsList)
        {
            $runbookOutParams[$runbookInstanceParameter.Name] = $runbookInstanceParameter.Value
        }
        else 
        {
            if ($RunbookOutParamsList -contains $runbookInstanceParameter.Name)
            {
                $runbookOutParams[$runbookInstanceParameter.Name] = $runbookInstanceParameter.Value
            }  
        }      
    }
    Write-Host "Found $($runbookOutParams.Keys.count) runbook output parameter/s."

    # Lets check if we have found all required parameters
    if($RunbookOutParamsList)
    {
        foreach ($runbookOutParam in $RunbookOutParamsList)
        {
            if ($runbookOutParam -notin $runbookOutParams.Keys)
            {
                $runbookOutParams[$runbookOutParam] = 'ERROR: Out parameter not found in job result'
            }
        }
    }

    # Define the output type of the runbook output parameters
    Write-Host "Will return runbook output parameters as: $RunbookOutParamType"
    switch ($RunbookOutParamType)
    {
        'Hashtable' 
        {
            return $runbookOutParams
        }
        'JSON' 
        {
            return $runbookOutParams | ConvertTo-Json
        }
        'Object' 
        {
            return [pscustomobject]$runbookOutParams
        }
        Default 
        {
            return $runbookOutParams
        }
    }  
}
#endregion



#region MAIN SCRIPT EXECUTION
#region Get Credentils
if (-NOT $TaskSequenceMode)
{
    Write-Host "Running in manual mode. Will prompt for credentials."
    Write-host "Add parameter -TaskSequenceMode if the script needs to run in a ConfigMgr task sequence"
    if ([string]::IsNullOrEmpty($UserName))
    {
        $credential = Get-Credential -Message 'Please enter credentials to start a runbook'
    }
    else 
    {
        $credential = Get-Credential -Message 'Please enter the password to start a runbook' -UserName $UserName
    }
}
else 
{
    try 
    {
        Write-Host "Will try to get credentials from task sequence variables: $UserVariableName and $PwdVariableName"
        $credential = Get-CredentialFromTaskSequenceVariables -UserVariableName $UserVariableName -PwdVariableName $PwdVariableName
        Write-Host "Credentials successfully retrieved from task sequence variables"
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
    [array]$runbooksList = Get-OrchestratorRunbookByName -ScorchURI $ScorchURI -RunbookName $RunbookName -credential $credential
    Write-Host "Runbook list returned with $($runbooksList.count) runbooks"
}
catch 
{
    Write-Host $_
    Exit 1 # to let a task sequence step fail
}

if ($runbooksList.count -eq 0)
{
    Write-Host "No runbook found with name: `"$($RunbookName)`""
    Write-Host "Either the runbook does not exist or the user does not have read permissions. Will stop script."
    Exit 1 # to let a task sequence step fail
}
else 
{
    Write-Host "Will test if we have just one runbook with the name: `"$($RunbookName)`""
    Write-Host "Found $($runbooksList.count) runbooks with the name: `"$($RunbookName)`""
    if ($runbooksList.count -eq 0)
    {
        Write-Host "No runbook found with name: `"$($RunbookName)`"."
        Write-Host "Either the runbook does not exist or the user does not have read permissions. Will stop script."
        Exit 1 # to let a task sequence step fail
    }    
    elseif($runbooksList.count -gt 1)
    {
        Write-Host "Found $($runbooksList.count) runbooks with same name. The name must be unique. Will stop script." 
        Exit 1 # to let a task sequence step fail
    }
    else 
    {
        $runbookID = $runbooksList.ID
        Write-Host "Found runbook: `"$($RunbookName)`" with ID: `"$($runbookID)`""
    }
}
#endregion


#region create runbook job
try 
{
    Write-Host "Will create runbook job"

    if($RunbookParams)
    {
        $runbookJob = Invoke-OrchestratorRunbookJob -ScorchURI $ScorchURI -RunbookID $runbookID -Credential $credential -RunbookParams $RunbookParams
    }
    else 
    {
        $runbookJob = Invoke-OrchestratorRunbookJob -ScorchURI $ScorchURI -RunbookID $runbookID -Credential $credential
    }    

    Write-Host "Runbook job created with ID: $($runbookJob.Id)"
}
catch 
{
    Write-Host "Creation of runbook job failed"
    Write-Host $_
    if ($_ -imatch '\(400\) Bad Request')
    {
        Write-Host "Error 400 bad request typically has one of the following reasons:"
        Write-Host "Runbook parameter names don't match the runbook parameter names in the runbook"
        Write-Host "`"`Publish`" permission on the runbook for the user used in this script is missing"
        Write-Host "Runbook is checked out in the Runbook Designer"
    }
    Exit 1 # to let a task sequence step fail
}
Write-Host "Runbook job created"
#endregion


#region Wait for the runbook resul
Write-Host "Waiting for runbook job result"
# start timer and loop until the runbook job is completed or the maximum wait time is reached

$timeoutTimer = [System.Diagnostics.Stopwatch]::StartNew()
$timeoutValue = 2 * $MaxJobRuntimeSec # Give some extra time to get the runbook job result
Write-Host "Will wait up to $timeoutValue seconds for runbook job to complete in case of error 500 internal server error"
Write-Host "Maximum runbook job runtime is set to $MaxJobRuntimeSec seconds"
do 
{
    try 
    {
        Write-Host "Will get runbook job status after 5 seconds"
        Start-Sleep -Seconds 5 # Give the orchestrator web service some time to start the runbook job
        $runbookJobResult = Get-OrchestratorRunbookJobStatus -ScorchURI $ScorchURI -JobID $runbookJob.Id -Credential $credential -MaxJobRuntimeSec $MaxJobRuntimeSec -WaitForCompletion

        if ($runbookJobResult.RunbookInstanceStatus -inotmatch 'Success')
        {
            exit 1 # to let a task sequence step fail
        }
    }
    catch 
    {
        if ($_ -imatch '\(500\) Internal Server Error')
        {
            Write-Host "Error 500 internal server error. Might be a temporary issue due to SQL lock state. Will try again in 5 seconds"
            Start-Sleep -Seconds 5
            # we will just try again and not fail the script
        }
        else 
        {
            Write-Host "Runbook job failed"
            Write-Host $_
            Exit 1 # to let a task sequence step fail
        }
    }
} 
until 
(
    ($runbookJobResult.RunbookInstanceStatus -imatch 'Success') -or  ($timeoutTimer.Elapsed.TotalSeconds -ge $timeoutValue)
)
$timeoutTimer.Stop()
#endregion

# region Get runbook output parameters
$runbookInstanceID = $runbookJobResult.RunbookInstanceID
if ($OutputAllOutParameters)
{
    $runbookoutParams = Get-OrchestratorRunbookOutputParameters -ScorchURI $ScorchURI -runbookInstanceID $runbookInstanceID -credential $credential
    return $runbookoutParams
}
elseif ($RunbookOutParamsList.count -gt 0)
{
    Write-Host "Will try to get runbook output parameters"
    try 
    {
        $runbookoutParams = Get-OrchestratorRunbookOutputParameters -ScorchURI $ScorchURI -runbookInstanceID $runbookInstanceID -credential $credential -RunbookOutParamsList $RunbookOutParamsList -RunbookOutParamType $RunbookOutParamType
        return $runbookoutParams
    }
    catch 
    {
        Write-Host "Could not get runbook instance parameters"
        Write-Host $_
        Exit 1 # to let a task sequence step fail
    }
}
else 
{
    Write-Host "No runbook output parameters requested"
}
#endregion

Write-Host "End of script"
