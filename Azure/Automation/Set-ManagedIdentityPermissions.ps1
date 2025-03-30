#requires -module Microsoft.Graph.Applications

<# 
.SYNOPSIS
    Script to set the required permissions for the managed identity

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

    Script to set the required permissions for managed identity

#>

param
(
    [string]$managedIdentityName = "<Managed-Identity-Name>",
    [string[]]$appPermissionsList = ("Device.Read.All","User.ReadBasic.All","Group.Read.All")
)
# Connect to Microsoft Graph with high privileges to be able to set the required permissions
Connect-MgGraph -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All", "AppRoleAssignment.ReadWrite.All"
# Get managed identity
$managedIdentity = Get-MgServicePrincipal -Filter "displayName eq '$managedIdentityName'"
# Get Microsoft Graph service principal to be able to "copy" the required permissions from there
$graphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"  
# Set the required permissions for the managed identity
foreach ($appPermission in $appPermissionsList) 
{
    $appRole = $graphServicePrincipal.AppRoles | Where-Object { $_.Value -eq $appPermission -and $_.AllowedMemberTypes -contains "Application" } 
    $params = @{
        ServicePrincipalId = $managedIdentity.Id
        PrincipalId = $managedIdentity.Id
        ResourceId = $graphServicePrincipal.Id
        AppRoleId = $appRole.Id
    }
    New-MgServicePrincipalAppRoleAssignment @params
}