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
  This script can wait for the hybrid join state if $runHybridJoinCheck is set to true.
  This is to prevent the Enrollment Status Page from skipping the hybrid join process (in case it takes longer than the ESP runtime)
  and to provide an end user with a seamless login experience.

  It can also wait for the correct NDES certificate if $runCertificateCheck is set to true.
  This is to prevent the system from having a certificate with the wrong subject name.
  A wrong subject name can happen, if the hybrid join device rename happens after the NDES certificate enrollment.

  Change the parameters to your needs. 

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
  $Certificates = Get-ChildItem -Path "Cert:\LocalMachine\My" 
  foreach ($Certificate in $Certificates) {
      $CertificateTemplateInformation = $Certificate.Extensions | Where-Object { $_.Oid.FriendlyName -match "Certificate Template Information"}
      if ($CertificateTemplateInformation) 
      {
          if (($CertificateTemplateInformation).Format(0) -match $TemplateID) 
          {
            $certificateFromTemplate = $Certificate
          }
                              
          if (($CertificateTemplateInformation).Format(0) -match $TemplateName) 
          {
            $certificateFromTemplate = $Certificate
          }                  
      }
  }
  return $certificateFromTemplate
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
        Start-Sleep -Seconds 15
        $certificateFromTemplate = Test-NDESCertificate -TemplateID $TemplateID -TemplateName $TemplateName
      }
    }
    else 
    {
      "$(get-date -f u) No certificate found. Will trigger PushLaunch task to request one." | Out-File -FilePath $logFile -Append -Force
      Get-ScheduledTask -TaskName "PushLaunch" | Start-ScheduledTask
      Start-Sleep -Seconds 15
      $certificateFromTemplate = Test-NDESCertificate -TemplateID $TemplateID -TemplateName $TemplateName
    }
  }
  Until (($allGood) -or ($stopWatch.Elapsed.TotalMinutes -ge $maxScriptRuntimeInMinutes))
  $stopWatch.Stop()
  "$(get-date -f u) End of script!" | Out-File -FilePath $logFile -Append -Force
}
#endregion