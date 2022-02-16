<#
.Synopsis
   Will create a string of installed features from one system to install the same features on another system
.DESCRIPTION
   Will create a string of installed features from one system to install the same features on another system
   Like: 
   "Install-WindowsFeature -Name UpdateServices-API,UpdateServices-UI"
   "Install-WindowsFeature -Name NET-Framework-Features,NET-Framework-Core,NET-Framework-45-Features,NET-Framework-45-Core -Source [PATH TO SXS FEATURESOURCE]"
.EXAMPLE
   Get-InstalledWindowsFeatureAsInstallString
#>
#region Get-InstalledWindowsFeatureAsInstallString
function Get-InstalledWindowsFeatureAsInstallString
{

    $InstallString = "Install-WindowsFeature -Name"
    $i = 0
    $addSourcePathToList = $false
    (Get-WindowsFeature | Where-Object installed | Select-Object Name).Foreach({ 
    
        if ($_.Name -eq 'NET-Framework-Core')
        {
            $addSourcePathToList = $true
        }

        if ($i -eq 0)
        {
            $InstallString = '{0} {1}'-f $InstallString, $_.Name
        }
        else
        {
            $InstallString = '{0},{1}'-f $InstallString, $_.Name
        }
        $i++

    })

    if ($addSourcePathToList)
    {
        $InstallString = '{0} -Source {1}' -f $InstallString, "[PATH TO SXS FEATURESOURCE]"
        return $InstallString
    }
    else
    {
        return $InstallString
    }

}
#endregion

Get-InstalledWindowsFeatureAsInstallString 
