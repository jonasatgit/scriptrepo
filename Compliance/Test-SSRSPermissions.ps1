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
.SYNOPSIS
    Script to test if SQL Server Report Server has read permissions on HKU\[SID]\Software\Microsoft\Avalon.Graphics

.DESCRIPTION
    If SQL Server Reporting Services cannot render Excel files, it might be because of missing registry permissions
    This script will check the permissions and output its state.
    It is meant to run as a ConfigMgr config item within a baseline

    Use the following command as a detection method in the config item to detect a ConfigMgr Reporting Service Point
    Get-ItemProperty 'Registry::HKLM\SOFTWARE\Microsoft\SMS\SRSRP' -Name 'SRSInitializeState' -ErrorAction SilentlyContinue

    The script does not work with the PowerBI Report Server

.LINK
    https://guithub.com/jonasatgit/scriptrepo
#>


try
{
    $serviceName = 'SQLServerReportingServices'
    $service = Get-WmiObject -Query "Select * from Win32_Service where Name='$serviceName'"
    if ($service.StartName)
    {
        $accountObj = New-Object System.Security.Principal.NTAccount($service.StartName)
        $serviceAccountSID = $accountObj.Translate([System.Security.Principal.SecurityIdentifier]).Value
    }

    $regPath = 'Registry::HKU\{0}\Software\Microsoft\Avalon.Graphics' -f $serviceAccountSID

    if (Test-Path $regString)
    {
        $regAcl = Get-Acl -Path $regPath
        $regPermissions = $regAcl.Access | Where-Object -Property IdentityReference -EQ 'Everyone'
        if ($regPermissions)
        {
            if ($regPermissions.AccessControlType -ieq 'Allow' -and $regPermissions.RegistryRights -ieq 'ReadKey')
            {
                Write-Output 'Compliant'
            }
            else
            {
                Write-Output "Wrong permissions for Everyone on `"$regPath`". AccessControlType: $($regPermissions.AccessControlType) RegistryRights: $($regPermissions.RegistryRights)"
            }
        }
        else
        {
            Write-Output "Everyone does not have read permission on `"$regPath`""  
        }

    }
    else
    {
        Write-Output "Path not found: `"$regPath`""
    }
}
catch
{
    Write-Output "Error: $($_)"
}