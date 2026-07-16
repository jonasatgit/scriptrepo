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
    Adds a ConfigMgr security scope to one or more ConfigMgr items of a chosen object type.

.DESCRIPTION
    Adds an existing ConfigMgr security scope to ConfigMgr objects such as applications, packages,
    task sequences, etc. The object type is selected via the -ObjectType parameter, which lists only
    object types that are secured by security scopes. The script internally maps the chosen object
    type to the correct Get-CM* cmdlet, retrieves the matching objects by name (wildcards supported)
    and pipes them to Add-CMObjectSecurityScope.

    Only object types that are secured by security scopes are supported. Some ConfigMgr objects are
    NOT secured by security scopes and are therefore intentionally excluded, for example:
      - Collections (device and user) - these are a separate RBAC pillar and act as a scoping
        mechanism themselves; they are secured by collection-based limiting, not security scopes.
      - Device drivers - individual drivers are not scope-secured (driver PACKAGES are).
      - Default client settings - only CUSTOM client settings are scope-secured.
    See: https://learn.microsoft.com/intune/configmgr/core/understand/fundamentals-of-role-based-administration

    The script does not create new security scopes. The scope specified via -ScopeName must already
    exist in the ConfigMgr site.

    The script supports -WhatIf and -Confirm.

.EXAMPLE
    .\Add-CMScopeToConfigMgrItem.ps1 -SiteCode 'P01' -ProviderMachineName 'server1.contoso.local' -ObjectType Application -ItemName 'Central*' -ScopeName 'ScopeName'

    Adds the security scope 'ScopeName' to every application whose name starts with 'Central'.

.EXAMPLE
    .\Add-CMScopeToConfigMgrItem.ps1 -SiteCode 'P01' -ProviderMachineName 'server1.contoso.local' -ObjectType Package -ItemName 'Runtime *' -ScopeName 'AppAdmins' -WhatIf

    Shows which packages would receive the 'AppAdmins' scope without changing anything.

.EXAMPLE
    .\Add-CMScopeToConfigMgrItem.ps1 -SiteCode 'P01' -ProviderMachineName 'server1.contoso.local' -ObjectType TaskSequence -ScopeName 'OSD'

    Adds the 'OSD' security scope to every task sequence in the site (no -ItemName means all objects).

.EXAMPLE
    .\Add-CMScopeToConfigMgrItem.ps1 -SiteCode 'P01' -ProviderMachineName 'server1.contoso.local' -ObjectType Application,Package,TaskSequence -ScopeName 'OSD'

    Adds the 'OSD' security scope to all applications, packages and task sequences (multiple object types).

.EXAMPLE
    .\Add-CMScopeToConfigMgrItem.ps1 -SiteCode 'P01' -ProviderMachineName 'server1.contoso.local' -ScopeName 'OSD'

    No -ObjectType is specified, so a grid view opens. Select one or more object types and click OK;
    the script then processes each selected type.

.PARAMETER SiteCode
    SiteCode of the ConfigMgr site.

.PARAMETER ProviderMachineName
    Name of the SMS Provider server.

.PARAMETER ObjectType
    One or more ConfigMgr object types to add the security scope to. Only object types that are
    secured by security scopes are listed. Objects that are not scope-secured (e.g. collections,
    device drivers, default client settings) are intentionally not available. You can pass multiple
    types (comma separated). If omitted, a grid view is shown to select one or more types.

.PARAMETER ItemName
    Name of the ConfigMgr object(s) to update. Wildcards are supported by most of the underlying
    Get-CM* cmdlets (e.g. 'Central*'). If omitted, all objects of the selected type are processed.

.PARAMETER ScopeName
    Name of the ConfigMgr security scope to add. The scope must already exist.

.LINK
    https://github.com/jonasatgit/scriptrepo
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param
(
    [Parameter(Mandatory = $true, HelpMessage = "SiteCode of the ConfigMgr site.")]
    [string]$SiteCode,

    [Parameter(Mandatory = $true, HelpMessage = "Name of the SMS Provider server.")]
    [string]$ProviderMachineName,

    [Parameter(Mandatory = $false, HelpMessage = "One or more ConfigMgr object types to add the security scope to. If omitted, a grid view is shown to pick from.")]
    [ValidateSet(
        'Application',
        'ApplicationGroup',
        'Package',
        'DriverPackage',
        'OperatingSystemImage',
        'OperatingSystemInstaller',
        'BootImage',
        'TaskSequence',
        'ConfigurationItem',
        'ConfigurationBaseline',
        'SoftwareUpdateGroup',
        'SoftwareUpdateDeploymentPackage',
        'Query',
        'Script',
        'Site',
        'GlobalCondition',
        'BoundaryGroup',
        'DistributionPoint',
        'DistributionPointGroup',
        'AntimalwarePolicy',
        'ClientSetting'
    )]
    [string[]]$ObjectType,

    [Parameter(Mandatory = $false, HelpMessage = "Name of the ConfigMgr object(s). If omitted, all objects of the type are processed. Wildcards supported.")]
    [string]$ItemName,

    [Parameter(Mandatory = $true, HelpMessage = "Name of the ConfigMgr security scope to add.")]
    [string]$ScopeName
)

# Mapping of object type to the Get-CM* cmdlet used to retrieve the object(s), together with
# the name of the parameter that takes the object name. Most cmdlets use '-Name', but some
# differ (e.g. Get-CMScript uses '-ScriptName'; Get-CMDistributionPoint uses
# '-SiteSystemServerName'). Only object types that are secured by security scopes
# (per the ConfigMgr RBAC fundamentals) are included here.
$objectTypeConfig = [ordered]@{
    'Application'                     = @{ Cmdlet = 'Get-CMApplication';                     NameParameter = 'Name' }
    'ApplicationGroup'                = @{ Cmdlet = 'Get-CMApplicationGroup';                NameParameter = 'Name' }
    'Package'                         = @{ Cmdlet = 'Get-CMPackage';                         NameParameter = 'Name' }
    'DriverPackage'                   = @{ Cmdlet = 'Get-CMDriverPackage';                   NameParameter = 'Name' }
    'OperatingSystemImage'            = @{ Cmdlet = 'Get-CMOperatingSystemImage';            NameParameter = 'Name' }
    'OperatingSystemInstaller'        = @{ Cmdlet = 'Get-CMOperatingSystemInstaller';        NameParameter = 'Name' }
    'BootImage'                       = @{ Cmdlet = 'Get-CMBootImage';                       NameParameter = 'Name' }
    'TaskSequence'                    = @{ Cmdlet = 'Get-CMTaskSequence';                    NameParameter = 'Name' }
    'ConfigurationItem'               = @{ Cmdlet = 'Get-CMConfigurationItem';               NameParameter = 'Name' }
    'ConfigurationBaseline'           = @{ Cmdlet = 'Get-CMBaseline';                        NameParameter = 'Name' }
    'SoftwareUpdateGroup'             = @{ Cmdlet = 'Get-CMSoftwareUpdateGroup';             NameParameter = 'Name' }
    'SoftwareUpdateDeploymentPackage' = @{ Cmdlet = 'Get-CMSoftwareUpdateDeploymentPackage'; NameParameter = 'Name' }
    'Query'                           = @{ Cmdlet = 'Get-CMQuery';                           NameParameter = 'Name' }
    'Script'                          = @{ Cmdlet = 'Get-CMScript';                          NameParameter = 'ScriptName' }
    'Site'                            = @{ Cmdlet = 'Get-CMSite';                            NameParameter = 'Name' }
    'GlobalCondition'                 = @{ Cmdlet = 'Get-CMGlobalCondition';                 NameParameter = 'Name' }
    'BoundaryGroup'                   = @{ Cmdlet = 'Get-CMBoundaryGroup';                   NameParameter = 'Name' }
    'DistributionPoint'               = @{ Cmdlet = 'Get-CMDistributionPoint';               NameParameter = 'SiteSystemServerName' }
    'DistributionPointGroup'          = @{ Cmdlet = 'Get-CMDistributionPointGroup';          NameParameter = 'Name' }
    'AntimalwarePolicy'               = @{ Cmdlet = 'Get-CMAntimalwarePolicy';               NameParameter = 'Name' }
    'ClientSetting'                   = @{ Cmdlet = 'Get-CMClientSetting';                   NameParameter = 'Name' }
}

# If no object type was specified, show a grid view so the user can pick one or more types.
# Object types can also be passed directly (one or multiple) via the -ObjectType parameter.
if (-not $ObjectType)
{
    # Out-GridView is only available in interactive sessions and is not present in PowerShell 7+
    # unless the Microsoft.PowerShell.GraphicalTools module is installed. Fail with a clear message
    # so the script can still be used in non-interactive / automation contexts.
    if (-not (Get-Command -Name 'Out-GridView' -ErrorAction SilentlyContinue))
    {
        throw "No -ObjectType was specified and Out-GridView is not available in this session. Specify one or more object types via -ObjectType instead."
    }

    $ObjectType = $objectTypeConfig.Keys | Out-GridView -Title 'Select one or more ConfigMgr object types to add the scope to' -OutputMode Multiple
    if (-not $ObjectType)
    {
        Write-Warning 'No object type selected. Nothing to do.'
        return
    }
}

# Import the ConfigurationManager.psd1 module
if ($null -eq (Get-Module ConfigurationManager))
{
    if ([string]::IsNullOrEmpty($ENV:SMS_ADMIN_UI_PATH))
    {
        throw "Environment variable SMS_ADMIN_UI_PATH is not set. Run this script from a machine with the ConfigMgr console installed."
    }

    $configMgrModulePath = Join-Path -Path (Split-Path -Path $ENV:SMS_ADMIN_UI_PATH -Parent) -ChildPath 'ConfigurationManager.psd1'
    if (-not (Test-Path -Path $configMgrModulePath))
    {
        throw "ConfigurationManager module not found at '$configMgrModulePath'. Ensure the ConfigMgr console is installed."
    }

    Import-Module $configMgrModulePath -ErrorAction Stop
}

# Connect to the site's drive if it is not already present
if ($null -eq (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue))
{
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName -ErrorAction Stop | Out-Null
}

# Remember the current location and switch to the site drive
$originalLocation = Get-Location
Set-Location "$($SiteCode):\" -ErrorAction Stop

try
{
    # Validate that the scope cmdlet is available in this session
    if (-not (Get-Command -Name 'Add-CMObjectSecurityScope' -ErrorAction SilentlyContinue))
    {
        throw "Cmdlet 'Add-CMObjectSecurityScope' is not available in this session."
    }

    # Validate that the security scope exists before touching any objects. Use -ErrorAction Stop
    # so a provider error is surfaced instead of being confused with a non-existent scope.
    try
    {
        $scope = Get-CMSecurityScope -Name $ScopeName -ErrorAction Stop
    }
    catch
    {
        throw "Failed to query security scope '$ScopeName': $($_.Exception.Message)"
    }

    if ($null -eq $scope)
    {
        throw "Security scope '$ScopeName' does not exist. Create it first or specify an existing scope."
    }

    # Track the outcome across all object types so automation callers get an honest result.
    $successCount = 0
    $failureCount = 0

    # Process each selected object type
    foreach ($type in $ObjectType)
    {
        $getCmdletName = $objectTypeConfig[$type].Cmdlet
        $nameParameter = $objectTypeConfig[$type].NameParameter

        # Validate that the Get cmdlet is available in this session
        $getCommandInfo = Get-Command -Name $getCmdletName -ErrorAction SilentlyContinue
        if ($null -eq $getCommandInfo)
        {
            Write-Warning "Cmdlet '$getCmdletName' for object type '$type' is not available. Skipping."
            continue
        }

        # Build the parameters for the Get-CM* cmdlet. The name parameter differs per cmdlet and
        # comes from the object type configuration above. If no item name was provided, omit the
        # name parameter entirely so the cmdlet returns all objects of that type. Many ConfigMgr
        # Get cmdlets also support the -Fast parameter, which skips retrieving lazy (expensive)
        # properties and greatly speeds up retrieval. Only add it when the cmdlet supports it.
        # -ErrorAction Stop ensures a provider/query failure is caught instead of silently
        # returning nothing and being reported as "no objects found".
        $getParams = @{ ErrorAction = 'Stop' }
        if (-not [string]::IsNullOrEmpty($ItemName))
        {
            $getParams[$nameParameter] = $ItemName
        }
        if ($getCommandInfo.Parameters.ContainsKey('Fast'))
        {
            $getParams['Fast'] = $true
            Write-Verbose "Cmdlet $getCmdletName supports -Fast; using it to speed up retrieval."
        }

        $itemFilterText = if ([string]::IsNullOrEmpty($ItemName)) { 'all' } else { "'$ItemName'" }

        Write-Verbose "Retrieving $type object(s) (filter: $itemFilterText) using $getCmdletName."
        try
        {
            $items = @(& $getCmdletName @getParams)
        }
        catch
        {
            Write-Warning "Failed to retrieve $type object(s) (filter: $itemFilterText): $($_.Exception.Message)"
            continue
        }

        # Default client settings are not scope-secured (only CUSTOM client settings are). The
        # default client settings object always has priority 10000, so filter it out.
        if ($type -eq 'ClientSetting')
        {
            $items = @($items | Where-Object { $_.Priority -ne 10000 })
        }

        if ($items.Count -eq 0)
        {
            Write-Warning "No $type object(s) found (filter: $itemFilterText)."
            continue
        }

        Write-Host "Found $($items.Count) $type object(s) (filter: $itemFilterText). Adding scope '$ScopeName'..." -ForegroundColor Green

        foreach ($item in $items)
        {
            # Try to get a friendly display name (property varies by object type)
            $displayName = $item.LocalizedDisplayName
            if ([string]::IsNullOrEmpty($displayName)) { $displayName = $item.Name }
            if ([string]::IsNullOrEmpty($displayName)) { $displayName = $item.NetworkOSPath }
            if ([string]::IsNullOrEmpty($displayName)) { $displayName = $item.ScriptName }
            if ([string]::IsNullOrEmpty($displayName)) { $displayName = $item.SiteName }
            if ([string]::IsNullOrEmpty($displayName)) { $displayName = $item.ToString() }

            Write-Verbose "Processing $($type): $($displayName)"

            if ($PSCmdlet.ShouldProcess("$type '$displayName'", "Add security scope '$ScopeName'"))
            {
                try
                {
                    $item | Add-CMObjectSecurityScope -Scope $scope -ErrorAction Stop | Out-Null
                    Write-Host "  [OK]   $displayName" -ForegroundColor Green
                    $successCount++
                }
                catch
                {
                    Write-Host "  [FAIL] $displayName" -ForegroundColor Red
                    Write-Verbose "  [FAIL] $displayName : $($_.Exception.Message)"
                    $failureCount++
                }
            }
        }
    }

    Write-Host "Done. $successCount succeeded, $failureCount failed." -ForegroundColor Cyan
    if ($failureCount -gt 0)
    {
        Write-Error "$failureCount of $($successCount + $failureCount) scope assignment(s) failed. Re-run with -Verbose for details."
    }
}
finally
{
    # Restore original location so we don't leave the caller on the CMSite drive
    Set-Location $originalLocation
}

 