
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
# Source: https://github.com/jonasatgit/scriptrepo/blob/master/General/BITS-Monitor.ps1
# tiny script to monitor BITS downloads in Powershell directly
# needs to be run as an admin

#region admin rights
#Ensure that the Script is running with elevated permissions

[int]$timeoutSeconds = 5

if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Warning 'The script needs admin rights to run. Start PowerShell with administrative rights and run the script again'
    return 
}

#endregion
while($true)
{
    # endless loop
    Clear-Host  
    $bitsJobs = Get-BitsTransfer -AllUsers 
    if (-NOT $bitsJobs) 
    {
        Write-Host "No BITS jobs found. Will try again in $timeoutSeconds seconds..."
    }
    else 
    {
        $bitsJobs | Format-Table   @{Expression={$_.JobID};Label="JobID"},
                                            @{Expression={$_.DisplayName};Label="DisplayName"},
                                            @{Expression={$_.TransferType};Label="TransferType"},
                                            @{Expression={"{0:N2}" -f $($_.BytesTotal/1024/1024)};Label="MBTotal"},
                                            @{Expression={"{0:N2}" -f $($_.BytesTransferred/1024/1024)};Label="MBTransferred"},
                                            @{Expression={"{0:N2}" -f $((100 / $_.BytesTotal) * $_.BytesTransferred)+"%"};Label="Total%"},
                                            @{Expression={$_.JobState};Label="Jobstate"},
                                            @{Expression={$_.ProxyList};Label="ProxyList"},
                                            @{Expression={$_.FileList[0].RemoteName};Label="FirstURL"}
    }
    Start-Sleep -Seconds $timeoutSeconds
}  