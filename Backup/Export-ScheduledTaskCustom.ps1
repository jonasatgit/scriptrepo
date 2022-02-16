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

#
# Basic script to export Scheduled Tasks
# The script will also create an import script. That makes it easy to export the tasks from one system and import them on another system
# Source: https://github.com/jonasatgit/scriptrepo
#

#region Export-ScheduledTasksCustom 
Function Export-ScheduledTasksCustom 
{
    param
    (
        [string]$BackupFolder,
        [string]$TaskPathRoot,
        [string]$RecoveryScriptFileName
    )

$ImportScript = @'
function Import-ScheduledTasksCustom {
  [CmdletBinding()]
  param
  (
      [parameter(Mandatory=$True,ValueFromPipeline=$true)]
      $TaskXMFile
  )
 
  begin {
      
  }
 
  process {
 
    write-host "Beginning process loop"
 
    foreach ($TaskXML in $TaskXMFile) {
      
      if ($pscmdlet.ShouldProcess($computer)) {
        
            $InfofilePath = "$($TaskXML.DirectoryName)\$($TaskXML.BaseName)_Infofile.txt"
            $InfofilePath
            if(Test-Path -Path $InfofilePath){
                $Task = Get-Content $TaskXML.FullName | Out-String
                $TaskName = $TaskXML.BaseName
                $TaskPath = (Get-Content $InfofilePath).Replace('TaskPath:','')

                Register-ScheduledTask -Xml $Task -TaskName $TaskName -TaskPath $TaskPath -Force

             }else{
             
                Write-Host "infofile not found"
             }

      }
    }
  }
} 
 

$scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

dir "$scriptPath\ScheduledTasks" -Filter '*.xml' | Import-ScheduledTasksCustom
'@
    

    $ImportScript | Out-File -FilePath "$BackupFolder\$RecoveryScriptFileName" -Force
    $BackupFolder = "$BackupFolder\ScheduledTasks"
    $Tasks = Get-ScheduledTask | Where-Object {$_.Taskpath -like "*$TaskPathRoot*"} 
    
    $Tasks | ForEach-Object {

        Write-Host "Backup of scheduled task: $($_.TaskName)"
        
        New-Item -ItemType directory -Path "$BackupFolder" -Force | Out-Null

        $filePath = "$BackupFolder\$($_.TaskName).xml"

        "TaskPath:$($_.Taskpath)" | Out-File "$BackupFolder\$($_.TaskName)_Infofile.txt"
    
        Export-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath | out-file -FilePath $filePath -Force
       
    }
}
#endregion


Export-ScheduledTasksCustom -BackupFolder "C:\ScheduledTaskBackups" -TaskPathRoot "\Microsoft\Configuration Manager" -RecoveryScriptFileName "Import-CustomScheduledTasks.ps1"