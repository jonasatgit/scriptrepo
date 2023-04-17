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
.Synopsis
   Script to wait for hybrid join and correct certificate state
.DESCRIPTION
  This script can wait for the hybrid join state if $runHybridJoinCheck is set to true.
  This is to prevent the Enrollment Status Page from skipping the hybrid join process (in case it takes longer than the ESP runtime)
  and to provide an end user with a seamless login experience.

  It can also wait for the correct NDES certificate if $runCertificateCheck is set to true.
  This is to prevent the system from having a certificate with the wrong subject name.
  A wrong subject name can happen, if the hybrid join device rename happens after the NDES certificate enrollment.

  How to use:
  - Adjust the parameters to your needs
  - Prep the script with the Intune prep tool. More can be found here: https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-prepare
  - Create a Win32 App in Intune and uploda the intunewin file
  - Use the following install and uninstall commands:
    Install command: Powershell.exe -NoProfile -ExecutionPolicy ByPass -File .\Test-HybridJoinState.ps1
    Uninstall command: Powershell.exe -NoProfile -ExecutionPolicy ByPass -File .\Test-HybridJoinState.ps1
    The uninstall should never run, since the apps purpose is to only run once during Autopilot Hybrid Join. Hence the same command. 
  - Use the logfile as detection method like this:
    Path: C:\Windows\Logs
    File or folder: HAADJState.log
    Detection method: File or folder exists
    Associate with a 32-bit app on 64-bit clients: No
  - Add the new app to your Autopilot Hybrid Join Enrollment Status page as required app
  - The the Autopilot process
.EXAMPLE
   Test-HybridJoinState.ps1
#>

#region Params
[CmdletBinding()]
param (
    [Parameter()]
    [bool]$RunHybridJoinCheck = $true, # The script will wait for the Hybrid Join process if set to $true
    [Parameter()]
    [bool]$RunCertificateCheck = $true, # The script will wait for the correct certificate if set to $true
    [Parameter()]
    [int]$MaxScriptRuntimeInMinutes = 0, # Zero means no limit. If the script run longer than the value defined, the script will exit with an error
    [Parameter()]
    $TemplateID = "1.3.6.1.4.1..........", # Certificate template ID in case the name cannot be resolved
    [Parameter()]
    $TemplateName = "Client_Auth_Intune", # Template name
    [Parameter()]
    $SubjectNames = @("CN=CL","CN=DESKTOP"), # Expected subject names
    [Parameter()]
    $LogFile = '{0}\Logs\HAADJState.log' -f $env:windir
)
#endregion

#region Start script
"$(get-date -f u) Script started" | Out-File -FilePath $logFile -Append -Force
# To set the limit to its maximum if the $maxScriptRuntimeInMinutes was set to zero
if ($maxScriptRuntimeInMinutes -eq 0){$maxScriptRuntimeInMinutes = [int]::MaxValue}
$stopWatch = New-Object System.Diagnostics.Stopwatch
$stopWatch.Start()
#endregion


#region Test-NDESCertificate 
function Test-NDESCertificate 
{
  [CmdletBinding()]
  param
  (
    $TemplateID,
    $TemplateName
  )

  $certificateFromTemplate = $null
  [array]$Certificates = Get-ChildItem -Path "Cert:\LocalMachine\My" 
  "$(get-date -f u) Found $($Certificates.Count) certificates" | Out-File -FilePath $logFile -Append -Force
  foreach ($Certificate in $Certificates) 
  {
    "$(get-date -f u) Checking certificate: $($Certificate.Thumbprint)..." | Out-File -FilePath $logFile -Append -Force
    # ID 1.3.6.1.4.1.311.21.7 matches 'Certificate Template Information' 
    # Using ID to be language-independent
    $CertificateTemplateInformation = $Certificate.Extensions | Where-Object {$_.OID.Value -eq '1.3.6.1.4.1.311.21.7'} 
    if ($CertificateTemplateInformation) 
    {
        if (($CertificateTemplateInformation).Format(0) -match $TemplateID) 
        {
          $certificateFromTemplate = $Certificate
          "$(get-date -f u) Certificate matches templateID" | Out-File -FilePath $logFile -Append -Force
        }
        elseif (($CertificateTemplateInformation).Format(0) -match $TemplateName) 
        {
          $certificateFromTemplate = $Certificate
          "$(get-date -f u) Certificate matches template name" | Out-File -FilePath $logFile -Append -Force
        }
        else 
        {
          "$(get-date -f u) Certificate does not match template ID or template name" | Out-File -FilePath $logFile -Append -Force
        }                
    }
    else
    {
      "$(get-date -f u) ERROR: No Certificate Template Information found" | Out-File -FilePath $logFile -Append -Force
    }
  }
  return $certificateFromTemplate
}
#endregion


#region Detect Hybrid Join State
if ($runHybridJoinCheck)
{
  "$(get-date -f u) The script is set to wait for the Hybrid Join state..." | Out-File -FilePath $logFile -Append -Force

$xmlQuery = @'
<QueryList>
  <Query Id="0" Path="Microsoft-Windows-User Device Registration/Admin">
    <Select Path="Microsoft-Windows-User Device Registration/Admin">*[System[(EventID=306)]]</Select>
  </Query>
</QueryList>
'@

  # Let's wait for event "Automatic registration Succeeded" with event id 306 in "Microsoft-Windows-User Device Registration/Admin"
  # Skip to wait if the event happened already
  if (-NOT(Get-WinEvent -FilterXML $xmlQuery -ErrorAction SilentlyContinue))
  {
      "$(get-date -f u) First check! Event not found. Need to wait..." | Out-File -FilePath $logFile -Append -Force
      do
      {
          "$(get-date -f u) Event not found. Will trigger task: Automatic-Device-Join" | Out-File -FilePath $logFile -Append -Force
          # Let's trigger the device join task to further speed up the overall process
          Get-ScheduledTask -TaskName 'Automatic-Device-Join' -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
          Start-Sleep -Seconds 90
      }
      until((Get-WinEvent -FilterXML $xmlQuery) -or ($stopWatch.Elapsed.TotalMinutes -ge $maxScriptRuntimeInMinutes))
  }
  "$(get-date -f u) Event found. All good!" | Out-File -FilePath $logFile -Append -Force
}
else 
{
  "$(get-date -f u) The script is set to skip the Hybrid Join state check!" | Out-File -FilePath $logFile -Append -Force
}
#endregion

#region Check for correct certificate Looking for a cert from a specific template
if ($runCertificateCheck)
{
  "$(get-date -f u) The script is set to check for the correct certificate..." | Out-File -FilePath $logFile -Append -Force
  "$(get-date -f u) Start certificate checks..." | Out-File -FilePath $logFile -Append -Force
  [bool]$allGood = $false
  "$(get-date -f u) Looking for certicates from specific template" | Out-File -FilePath $logFile -Append -Force
  $certificateFromTemplate = Test-NDESCertificate -TemplateID $TemplateID -TemplateName $TemplateName
  do
  {
    "$(get-date -f u) Test certificate" | Out-File -FilePath $logFile -Append -Force
    if ($certificateFromTemplate)
    {
      if ($certificateFromTemplate.Subject -match ($SubjectNames -join "|"))
      {
        "$(get-date -f u) Certificate comes from correct template and has the correct name! Stopping script!" | Out-File -FilePath $logFile -Append -Force
        $allGood = $true
      }
      else 
      {
        "$(get-date -f u) Certificate comes from correct template but name is not correct! Will delete certificate" | Out-File -FilePath $logFile -Append -Force
        Remove-Item -Path $certificateFromTemplate.PSPath -Force
        Get-ScheduledTask -TaskName "PushLaunch" | Start-ScheduledTask
        Start-Sleep -Seconds 20
        $certificateFromTemplate = Test-NDESCertificate -TemplateID $TemplateID -TemplateName $TemplateName
      }
    }
    else 
    {
      "$(get-date -f u) No certificate found. Will trigger PushLaunch task to request one." | Out-File -FilePath $logFile -Append -Force
      Get-ScheduledTask -TaskName "PushLaunch" | Start-ScheduledTask
      Start-Sleep -Seconds 20
      $certificateFromTemplate = Test-NDESCertificate -TemplateID $TemplateID -TemplateName $TemplateName
    }
  }
  Until (($allGood) -or ($stopWatch.Elapsed.TotalMinutes -ge $maxScriptRuntimeInMinutes))
  $stopWatch.Stop()
  "$(get-date -f u) End of script!" | Out-File -FilePath $logFile -Append -Force
}
else 
{
  "$(get-date -f u) The script is set to skip the certificate check!" | Out-File -FilePath $logFile -Append -Force
}
#endregion