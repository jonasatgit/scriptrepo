 #region variables
 $graphApiVersion = "beta"  
 $listOfRequiredModules = [ordered]@{
        'Microsoft.Graph.Groups' = '1.27.0'
    }  
    
$listOfRequiredScopes = (
            'Directory.ReadWrite.All'        
            )  
#endregion variables  
#region Import nuget before anyting else
[version]$minimumVersion = '2.8.5.201'
$nuget = Get-PackageProvider -ErrorAction Ignore | Where-Object {$_.Name -ieq 'nuget'} 
# not using -name parameter due to autoinstall question
if (-Not($nuget))
{    
    # Changed to MSI installer as the old way could not be enforced and needs to be approved by the user
    # Install-PackageProvider -Name NuGet -MinimumVersion $minimumVersion -Force    
    $null = Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies -MinimumVersion $minimumVersion -Force
}    
# Install and or import modules 
$listOfInstalledModules = Get-InstalledModule -ErrorAction SilentlyContinue
foreach ($module in $listOfRequiredModules.GetEnumerator())
{
    if (-NOT($listOfInstalledModules | Where-Object {$_.Name -ieq $module.Name}))        
    {                
          
        if (-NOT([string]::IsNullOrEmpty($module.Value)))        
        {            
            Install-Module $module.Name -Force -RequiredVersion $module.Value        
        }        
        else
        {            
            Install-Module $module.Name -Force        
        }                   
    }     
}
#endregion Import modules    

#region connect
Connect-MgGraph -Scopes $listOfRequiredScopes


#endregion    

#region create rollout groups
$groupPrefix = 'IN-D-Rollout'
$groupCount = 4
$allDevicesGroupName = 'IN-D-AllDevices'

# get all devices group
$allDevicesGroup = Get-MgGroup -Filter "displayName eq '$allDevicesGroupName'"

# Create $groupCount rollout groups starting with $groupPrefix
# store avery new group in an arraylist
$rolloutGroups = New-Object System.Collections.Generic.List[object]
for ($i = 1; $i -le $groupCount; $i++)
{
    # $i needs to be in the format 001, 002, 003, etc.
    $groupSuffix = "{0:D3}" -f $i
    $groupName = '{0}-{1}' -f $groupPrefix, $groupSuffix
    $groupDescription = 'Rollout group {0}' -f $groupSuffix
    $group = New-MgGroup -DisplayName $groupName -Description $groupDescription -MailEnabled $false -MailNickname $groupName -SecurityEnabled $true
    $rolloutGroups.Add($group)
    Write-Host "Created group $groupName"
}

# create a new filter rule for each group in the arraylist
# The filter needs to include the all devices group but exclude all the other rollout groups



