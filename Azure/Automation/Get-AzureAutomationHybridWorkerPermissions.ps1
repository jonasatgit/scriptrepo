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

# Azure Arc Hybrid Worker Extension RunAs Account Permissions

$userName = "CONTOSO\sctest"

$permissionsList = @(

    [pscustomobject][ordered]@{
        PermissionsPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog'
        RegistryRights = "ReadKey"
        AccessControlType = "Allow"
        IdentityReference = $userName
        IsInherited = "False"
        InheritanceFlags = "ContainerInherit"
        PropagationFlags = "None"
    },

    [pscustomobject][ordered]@{
        PermissionsPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\WinSock2\Parameters'
        RegistryRights = "FullControl"
        AccessControlType = "Allow"
        IdentityReference = $userName
        IsInherited = "False"
        InheritanceFlags = "ContainerInherit"
        PropagationFlags = "None"
    },

    [pscustomobject][ordered]@{
        PermissionsPath = 'HKLM:\SOFTWARE\Microsoft\Wbem\CIMOM'
        RegistryRights = "FullControl"
        AccessControlType = "Allow"
        IdentityReference = $userName
        IsInherited = "False"
        InheritanceFlags = "ContainerInherit"
        PropagationFlags = "None"
    },

    [pscustomobject][ordered]@{
        PermissionsPath = 'HKLM:\Software\Policies\Microsoft\SystemCertificates\Root'
        RegistryRights = "FullControl"
        AccessControlType = "Allow"
        IdentityReference = $userName
        IsInherited = "False"
        InheritanceFlags = "ContainerInherit"
        PropagationFlags = "None"
    },

    [pscustomobject][ordered]@{
        PermissionsPath = 'HKLM:\Software\Microsoft\SystemCertificates'
        RegistryRights = "FullControl"
        AccessControlType = "Allow"
        IdentityReference = $userName
        IsInherited = "False"
        InheritanceFlags = "ContainerInherit"
        PropagationFlags = "None"
    },

    [pscustomobject][ordered]@{
        PermissionsPath = 'HKLM:\Software\Microsoft\EnterpriseCertificates'
        RegistryRights = "FullControl"
        AccessControlType = "Allow"
        IdentityReference = $userName
        IsInherited = "False"
        InheritanceFlags = "ContainerInherit"
        PropagationFlags = "None"
    },

    [pscustomobject][ordered]@{
        PermissionsPath = 'HKLM:\Software\Microsoft\HybridRunbookWorkerV2'
        RegistryRights = "FullControl"
        AccessControlType = "Allow"
        IdentityReference = $userName
        IsInherited = "False"
        InheritanceFlags = "ContainerInherit"
        PropagationFlags = "None"
    },

    [pscustomobject][ordered]@{
        PermissionsPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Setup\PnpLockdownFiles'
        RegistryRights = "FullControl"
        AccessControlType = "Allow"
        IdentityReference = $userName
        IsInherited = "False"
        InheritanceFlags = "ContainerInherit"
        PropagationFlags = "None"
    },

    [pscustomobject][ordered]@{
        PermissionsPath = 'HKCU:\SOFTWARE\Policies\Microsoft\SystemCertificates\Disallowed'
        RegistryRights = "FullControl"
        AccessControlType = "Allow"
        IdentityReference = $userName
        IsInherited = "False"
        InheritanceFlags = "ContainerInherit"
        PropagationFlags = "None"
    },

    [pscustomobject][ordered]@{
        PermissionsPath = 'C:\ProgramData\AzureConnectedMachineAgent\Tokens'
        FileSystemRights = "Read, Synchronize"
        AccessControlType = "Allow"
        IdentityReference = $userName
        IsInherited = "False"
        InheritanceFlags = "ContainerInherit, ObjectInherit"
        PropagationFlags = "None"
    },

    [pscustomobject][ordered]@{
        PermissionsPath = 'C:\Packages\Plugins\Microsoft.Azure.Automation.HybridWorker.HybridWorkerForWindows'
        FileSystemRights = "Write, ReadAndExecute, Synchronize"
        AccessControlType = "Allow"
        IdentityReference = $userName
        IsInherited = "False"
        InheritanceFlags = "ContainerInherit, ObjectInherit"
        PropagationFlags = "None"
    }

)

$wrongPermissionsList = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach($item in $permissionsList)
{
    $permissions = Get-Acl -Path $item.PermissionsPath
    # getting just the one permissions etry for the specific user
    $actualUserPermissions = $permissions.Access | Where-Object {$_.IdentityReference -ieq $item.IdentityReference}
    if (-NOT ($actualUserPermissions))
    {
        $item.PermissionsPath = 'No permissions for user found for path: {0}' -f $item.PermissionsPath
        $wrongPermissionsList.Add($item)
    }
    else 
    {
        # Lets check each property as compare-object would do
        foreach($propertyName in $item.psobject.properties.Name)
        {
            # skip some properties not relevant for the check
            if(-NOT ($propertyName -iin ('PermissionsPath')))
            {
                if (-NOT ($item.$propertyName -ieq $actualUserPermissions.$propertyName))
                {
                    $item.$propertyName = 'ExpectedValue: {0} ActualValue: {1}' -f $item.$propertyName, $actualUserPermissions.$propertyName
                    $wrongPermissionsList.Add($item)
                }          
            }
        }
    }
}

if ($wrongPermissionsList.count -gt 0)
{
    $wrongPermissionsList | Format-List
}
else
{
    Write-Output 'All permissions correct'
}

