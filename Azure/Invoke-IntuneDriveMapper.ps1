<#
.SYNOPSIS
    This script maps network drives using a scheduled task.

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
    #
    #************************************************************************************************************

    This script maps network drives using a scheduled task.
    It creates a PowerShell script that contains the function to map the drives and then registers a scheduled task to run that script at user logon.

    Add drives between "ADD DRIVES HERE"

.PARAMETER RemoveExistingDrives
    If set, existing drives with the same drive letter or path will be removed before mapping the new drives.

#>

[CmdletBinding()]
param
(
    [switch]$RemoveExistingDrives
)  


# START: DO NOT CHANGE THIS LINE
#region Function Add-NewNetworkDrives
Function Add-NewNetworkDrives
{
    # ADD DRIVES HERE
    $arrayOfdrives = @(
        [pscustomobject]@{ Path = "\\192.168.178.211\testshare$"; DriveLetter = "Z"; Label = "SharedDocs" },
        [pscustomobject]@{ Path = "\\192.168.178.211\testshare2$"; DriveLetter = "P"; Label = "Media" },
        [pscustomobject]@{ Path = "\\192.168.178.211\testsharedummy$"; DriveLetter = "Q"; Label = "Backups" }
    )
    # ADD DRIVES HERE

    # We only support unc path here
    [array]$existingDrives = Get-PSDrive | Where-Object { $_.Provider.Name -eq "FileSystem" -and $_.Root -notin ('C:\','D:\') }

    foreach ($drive in $arrayOfdrives)
    {
        try
        {    
            $mapDrive = $false
            # Lets check if the unc path or drive letter is in use already
            if($existingDrives.Where({$_.Name -eq $drive.DriveLetter -and $_.DisplayRoot -eq $drive.Path}))
            {
                Write-Verbose "Drive letter: $($drive.DriveLetter) and path: $($drive.Path) are already mapped correctly."
                $mapDrive = $false
            }
            else
            {
                if ($existingDrives.Where({$_.Name -eq $drive.DriveLetter -or $_.DisplayRoot -eq $drive.Path}))
                {
                    if ($RemoveExistingDrives)
                    {
                        Write-Verbose "Drive letter: $($drive.DriveLetter) or path: $($drive.Path) is already mapped. Removing it first"
                        $existingDrives | Where-Object { $_.Name -eq $drive.DriveLetter -or $_.DisplayRoot -eq $drive.Path } | Remove-PSDrive -Force -ErrorAction Stop
                        # Wait for the drive to be removed. Otherwise we cannot set the label properly
                        Write-Verbose "Waiting for the drive to be removed"
                        Start-Sleep -Seconds 4
                        $mapDrive = $true
                    }
                    else
                    {
                        Write-Verbose "Drive letter: $($drive.DriveLetter) or path: $($drive.Path) is already mapped. Not removing it"
                        $mapDrive = $false
                    }      
                }
                else
                {
                    Write-Verbose "No drive mapped yet with drive letter: $($drive.DriveLetter) or drive path: $($drive.Path)"
                    $mapDrive = $true
                }
            }

            # Check if the path is reachable

            if ($mapDrive)
            {
                # Setting to empty string in case we have no value to avoid an error later on
                if ($null -eq $drive.Label)
                {
                    $drive.Label = ''
                }

                $paramSplatting = @{
                    PSProvider = 'FileSystem'
                    Name = $drive.DriveLetter                
                    Root = $drive.Path
                    Description = $drive.Label
                    Persist = $true
                    Scope = 'Global'
                    ErrorAction = 'Stop'
                }

                $null = New-PSDrive @paramSplatting
               
                # Set the drive label since New-PSDrive does not set it correctly
                $shell = New-Object -ComObject Shell.Application
                $driveObj = $shell.Namespace(17).ParseName("$($drive.DriveLetter):")
                $driveObj.Name = "$($drive.Label)"
            }
        }
        catch
        {
            Write-Error "Error mapping drive $($drive.DriveLetter):"
            Write-Error $_.Exception
        }
        finally
        {
            # Cleanup
            if ($null -ne $driveObj)
            {
                $null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($driveObj)
            }
            if ($null -ne $shell)
            {
                $null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell)
            }
        }
    }
}
#endregion Function Add-NewNetworkDrives
# END: DO NOT CHANGE THIS LINE



# The following lines are used to hide the PowerShell window when the map network drive script is started via Sheduled Task
$vbsScriptToHidePoshWindow = @'
Dim shell,command
command = "powershell.exe -nologo -ExecutionPolicy Bypass -NoProfile -File " & Chr(34) & "{0}" & Chr(34) & ""
Set shell = CreateObject("WScript.Shell")
shell.Run command,0
'@


# Prepare content we use as another script to map drives
$scriptSelfContent = Get-Content $MyInvocation.MyCommand.Path -Raw
# The -Raw parameter reads the entire file as a single string, preserving line breaks and formatting
# Construct the regex pattern to match the content between the start and end markers
$startString = [regex]::Escape('# START: DO NOT CHANGE THIS LINE')
$endString = [regex]::Escape('# END: DO NOT CHANGE THIS LINE')
$pattern = "($startString)(.*?)($endString)"

# Use the regex to extract the content between the markers
$matchResult = [regex]::Match($scriptSelfContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

# Check if the match was successful
$newScriptContent = $matchResult.Value
if (-NOT ($newScriptContent -imatch 'Function Add-NewNetworkDrives'))
{
    Write-Error 'Function Add-NewNetworkDrives not found in the script content'
    return
}

# prepre task to map drives
$taskGUID = (New-Guid).Guid

$outFileFullName = '{0}\MapDrives-{1}.ps1' -f $env:ProgramData, $taskGUID
$taskName = 'MapDrives-{0}' -f $taskGUID

$taskDescription = 'Map network drives'
$outScriptContent = $null

try
{                  
    $outScriptContent = $newScriptContent
    # Add the function call to the end of the script
    $outScriptContent += "`n"
    $outScriptContent += "`nAdd-NewNetworkDrives"
    $outScriptContent += "`n"
    # Write the content to the output file
    $outScriptContent | Set-Content -Encoding utf8 -Path $outFileFullName -Force

    # Adding the PowerShell script to the VBS script
    $vbsOutputString = $null
    $vbsOutputString = $vbsScriptToHidePoshWindow -f $outFileFullName
    $vbsOutputString | Set-Content -Encoding unicode -Path ($outFileFullName -replace 'ps1', 'vbs') -Force

    # store path of powershell.exe in variable
    #$poshPath = (Get-Command powershell.exe).Source

    $taskTrigger = New-ScheduledTaskTrigger -AtLogOn

    # Set for all users
    $taskPrincipal = New-ScheduledTaskPrincipal -GroupId "S-1-5-32-545" #-Id "Author"
       
    $taskAction = New-ScheduledTaskAction -Execute "C:\Windows\System32\wscript.exe" -Argument ($outFileFullName -replace 'ps1', 'vbs')
    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    $paramSplatting = @{
        TaskName = $taskName
        Trigger = $taskTrigger
        Action = $taskAction
        Principal = $taskPrincipal
        Settings = $taskSettings
        Description = $taskDescription
        Force = $true
    }

    $null = Register-ScheduledTask @paramSplatting
   
    Start-ScheduledTask -TaskName $taskName -ErrorAction Ignore
   
    Write-Verbose "Drive map task created successfully"
}
catch
{
    Write-Verbose "Error: $($_)"        
    Write-Verbose "Drive map task failed: $($_.Exception.Message)"
}  
           