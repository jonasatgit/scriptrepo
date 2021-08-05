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
    Script to output ConfigMgr security roles via GridView
.DESCRIPTION
    Script to output ConfigMgr security roles via GridView to easily export the data to Excel or simply filter for all allowed permissions per role
.EXAMPLE
    .\Show-ConfigMgrSecurityRolesAndPermissions.ps1
.EXAMPLE
    .\Show-ConfigMgrSecurityRolesAndPermissions.ps1 -SiteCode "P01" -ProviderMachineName "server1.contoso.local"
.PARAMETER SiteCode
    ConfigMgr SiteCode
.PARAMETER ProviderMachineName
    Name of the SMS Provider. Will use local system if nothing has been set.
.PARAMETER ForceDCOMConnection
    Sitch to force the script to use DCOM/WMI instead of PSRemoting. Useful if only WMI is available.
#>
param
(
    [Parameter(Mandatory=$false)]
    [string]$ProviderMachineName = $env:COMPUTERNAME,
    [Parameter(Mandatory=$false)]
    [string]$SiteCode = "P01",
    [Parameter(Mandatory=$false)]   
    [switch]$ForceDCOMConnection
)

# setting cim session options
if ($ForceDCOMConnection)
{
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Connect to `"$ProviderMachineName`" using DCOM" -ForegroundColor Green
    $cimSessionOption = New-CimSessionOption -Protocol Dcom
    $cimSession = New-CimSession -ComputerName $ProviderMachineName -SessionOption $cimSessionOption
}
else 
{
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Connect to `"$ProviderMachineName`" using PSRemoting" -ForegroundColor Green
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - If PSRemoting takes long or does not work at all, try using the `"-ForceDCOMConnection`" parameter" -ForegroundColor Yellow
    $cimSession = New-CimSession -ComputerName $ProviderMachineName  
}

$cimsession = New-CimSession -ComputerName $ProviderMachineName

[array]$MECMSecurityRoles = Get-CimInstance -CimSession $cimsession -Namespace "root\sms\site_$SiteCode" -query "Select * from SMS_Role" # where IsBuiltIn = 0"
$MECMAvailablePermissions = Get-CimInstance -CimSession $cimsession -Namespace "root\sms\site_$SiteCode" -query "Select * from SMS_AvailableOperation"

Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Found: $($MECMSecurityRoles.Count) security roles" -ForegroundColor Green
[array]$selectedRoles = $MECMSecurityRoles | Out-GridView -Title 'Please select ConfigMgr seurity roles' -OutputMode Multiple

if($selectedRoles.Count -gt 0)
{
    $outObj = New-Object System.Collections.ArrayList
    foreach ($roleItem in $selectedRoles) 
    {
        Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Working on role: `"$($roleItem.RoleName)`"" -ForegroundColor Green
        # create temp object for each role 
        $MECMAvailablePermissionsTemp = $MECMAvailablePermissions | Select-Object RoleName, CopiedFrom, ObjectTypeName, OperationName, ObjectTypeID, BitFlag, IsTypeWideOperation, ObjectTypeIsPartOfRole, Allow
        
        Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Loading lazy properties" -ForegroundColor Green
        # loading lazy properties for role to get gratedoperations property
        $roleItem = $roleItem | Get-CimInstance -CimSession $cimsession

        $CopiedFrom = ($MECMSecurityRoles.Where({$_.RoleID -eq $roleItem.CopiedFromID})).RoleName

        Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Validate possible role permissions" -ForegroundColor Green
        foreach ($AvailableRolePermission in $MECMAvailablePermissionsTemp) 
        {
            $AvailableRolePermission.RoleName = $roleItem.RoleName
            $AvailableRolePermission.CopiedFrom = $CopiedFrom
            $AvailableRolePermission.ObjectTypeName = $AvailableRolePermission.ObjectTypeName.Replace('SMS_','')
            if($AvailableRolePermission.ObjectTypeID -in $roleItem.Operations.ObjectTypeID)
            {
                $AvailableRolePermission.ObjectTypeIsPartOfRole = "Yes"
                if((($roleItem.Operations | Where-Object {$_.ObjectTypeID -eq $AvailableRolePermission.ObjectTypeID}).GrantedOperations) -band $AvailableRolePermission.BitFlag)
                {
                    $AvailableRolePermission.Allow = "Yes"
                }
                else 
                {
                    #$AvailableRolePermission.Allow = "No"   
                }
            }
            else 
            {
                #$AvailableRolePermission.PermissionIsPartOfRole = "No"   
            }
            [void]$outObj.Add($AvailableRolePermission)
        }
    }
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Show data" -ForegroundColor Green
    $outObj | Select-Object RoleName, CopiedFrom, ObjectTypeIsPartOfRole, ObjectTypeName, OperationName, Allow | Sort-Object RoleName, ObjectTypeName, OperationName | Out-GridView -Title 'List of MECM security roles and permissions' 
}
else 
{
    Write-Host "$(Get-Date -Format 'yyyyMMdd hh:mm:ss') - Nothing selected. End" -ForegroundColor Green
}
