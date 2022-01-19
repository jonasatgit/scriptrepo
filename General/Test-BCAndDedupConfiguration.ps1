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
   Test-BCAndDedupConfiguration.ps1
.DESCRIPTION
   The script is designed to run as a ConfigMgr configuration item within a configuration baseline.
   It will either validate all required BranchCache and Data Deduplication settings for Distribution Points or set them. 
   The behaviour can be set via parameter $remediate.
.EXAMPLE
   Test-BCAndDedupConfiguration.ps1
.EXAMPLE
   Test-BCAndDedupConfiguration.ps1 -Remediate $true
.PARAMETER Remediate
   Can either be set to $false to only validate the settings or to $true to set the required settings. 
.PARAMETER ExcludeConnectedCacheFolderFromDeDup
  The script will look for a folder called "DOINC-E77D08D0-5FEA-4315-8C95-10D359D59294" on the DeDup Volume and will exclude the folder from DeDup if set to yes (yes is the deafult)
.PARAMETER ConnectedCacheFolderName
  Name of the Microsoft Connected Cache data folder
#>

param
(
    [Parameter(Mandatory=$false)]
    [bool]$Remediate = $true,     # Set to $true in case the script should remediate all required settings
    [Parameter(Mandatory=$false)]
    [bool]$ExcludeConnectedCacheFolderFromDeDup = $true,
    [Parameter(Mandatory=$false)]
    [string]$ConnectedCacheFolderName = 'DOINC-E77D08D0-5FEA-4315-8C95-10D359D59294'

)

# Just making sure we always have the correct output
[string]$outPutString = $null

# Prevent the script from running on a Primary Site
if ((Get-Service -Name 'SMS_EXECUTIVE' -ErrorAction SilentlyContinue) -and (Get-Service -Name 'SMS_SITE_COMPONENT_MANAGER' -ErrorAction SilentlyContinue) -and ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\SMS\Identification' -Name 'Site Type' -ErrorAction SilentlyContinue).'Site Type' -ne 2))
{

    Write-Output "Site Server detected. Stopping script"
    Exit
}

# Make sure we are on a Distribution Point
$CLpath = (Get-ItemProperty -Path "HKLM:\Software\Microsoft\SMS\DP" -Name ContentLibraryPath -ErrorAction SilentlyContinue).ContentLibraryPath
if ($CLpath -notlike '*SCCMContentLib')
{
    Write-Output 'No Distribution Point role detected. Stopping Script.'
    Exit
}
else 
{
    # Prevent the script from setting anything on C:\
    if ($CLpath -like 'C:\*')
    {
        Write-Output "ContentLibrary installed on C:\. Stopping script."
        Exit
    }
}

#region Validate BrancheCache feature and settings
# Check if BracheCache feature is installed
Import-Module BranchCache
$Feature = Get-WindowsFeature -Name BranchCache
if (-NOT($Feature.Installed))
{
    if ($Remediate)
    {
        $null = Install-WindowsFeature -Name BranchCache
    }
    else 
    {
        Write-Output "BCFeatureMissing"
        # The script will end here. No need to validate further.
        Exit
    }
}

# Fix service status in case BrancheCache is not running
$Service = Get-BCStatus
if ($Service.BranchCacheIsEnabled -ne "True") 
{
    if ($Remediate) 
    {
        # Enable BrancheCache in distributed mode
        $null = Enable-BCDistributed -Force
    }
    else 
    {
        $outPutString = "BCNotEnabled"
    }
}

if ($Service.BranchCacheServiceStartType -ne "Automatic") 
{
    if ($Remediate) 
    {
        $null = Set-Service PeerDistSvc -StartupType Automatic
    }
    else 
    {
        $outPutString = "{0},{1}" -f $outPutString, "BCNotSetToAutomatic"   
    }
}
if ($Service.BranchCacheServiceStatus -ne "Running") 
{
    if ($Remediate) 
    {
        $null = Start-Service PeerDistSvc
    }
    else 
    {
        $outPutString = "{0},{1}" -f $outPutString, "BCNotStarted"   
    }
}


# Reset BrancheCache in case HASH cache is full and not cleaning up on its own
$HashCache = Get-BCHashCache -ErrorAction Stop
if ($HashCache.MaxCacheSizeAsNumberOfBytes -lt $HashCache.CurrentActiveCacheSize) 
{
    if ($Remediate) 
    {
        $null = Reset-BC -Force
    }
    else 
    {
        $outPutString = "{0},{1}" -f $outPutString, "BCHashCacheFull"    
    }
}

# Reset BrancheCache in case DATA cache is full and not cleaning up on its own
$DataCache = Get-BCDataCache -ErrorAction Stop
if ($DataCache.MaxCacheSizeAsNumberOfBytes -lt $DataCache.CurrentActiveCacheSize) 
{
    if ($Remediate) 
    {
        $null = Reset-BC -Force
    }
    else 
    {
        $outPutString = "{0},{1}" -f $outPutString, "BCDataCacheFull" 
    }
}


# Fix BrancheCache location in case BrancheCache is not installed on the same drive as the ContentLibrary
$HashCache = Get-BCHashCache -ErrorAction Stop
$DataCache = Get-BCDataCache -ErrorAction Stop
$ContentLibDrive = (Get-ItemProperty -Path "HKLM:\Software\Microsoft\SMS\DP" -Name ContentLibraryPath -ErrorAction Stop).ContentLibraryPath
$ContentLibDrive = ($ContentLibDrive).SubString(0, 3)
$HashCacheDrive = ($HashCache.CacheFileDirectoryPath).SubString(0, 3)
$DataCacheDrive = ($DataCache.CacheFileDirectoryPath).SubString(0, 3)
$HashCacheDest = "{0}{1}" -f $ContentLibDrive, "BranchCache\Publication"
$DataCacheDest = "{0}{1}" -f $ContentLibDrive, "BranchCache\RePublication"

if ($ContentLibDrive -ne $HashCacheDrive) 
{
    if ($Remediate) 
    {
        $null = New-Item -ItemType directory -Path $HashCacheDest -Force -ErrorAction Stop
        # Clear cache and restart service to ensure move works
        $null = Clear-BCCache -Force -ErrorAction Stop
        $null = Restart-Service PeerDistSvc -Force
        $null = Get-BCHashCache | Set-BCCache -MoveTo $HashCacheDest -Force -ErrorAction Stop
    }
    else 
    {
        $outPutString = "{0},{1}" -f $outPutString, "BCHashCacheWrongDrive"        
    }
}

if ($ContentLibDrive -ne $DataCacheDrive) 
{
    if ($Remediate) 
    {
        $null = New-Item -ItemType directory -Path $DataCacheDest -Force -ErrorAction Stop
        # Clear cache and restart service to ensure move works
        $null = Clear-BCCache -Force -ErrorAction Stop
        $null = Restart-Service PeerDistSvc -Force
        $null = Get-BCDataCache | Set-BCCache -MoveTo $DataCacheDest -Force -ErrorAction Stop
   }
    else 
    {
        $outPutString = "{0},{1}" -f $outPutString, "BCDataCacheWrongDrive"         
    }
}

# Fix BrancheCache settings in case cache size or TTL is not set correctly
# Setting BranchCache to 50% of data drive to ensure no problems with cache running out of space
# We should never hit the 50% mark even with large drives
[int]$BCSizePercent = 50
[int]$BCDataCacheEntryMaxAgeDays = 70

# Hash Cache
$HashCache = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\PeerDist\CacheMgr\Publication" -Name SizePercent -ErrorAction SilentlyContinue
if ($HashCache.SizePercent -ne $BCSizePercent) 
{
    if ($Remediate) 
    {
        $null = Get-BCHashCache | Set-BCCache -Percentage $BCSizePercent -Force
    }
    else 
    {
        $outPutString = "{0},{1}" -f $outPutString, "BCHashCacheWrongSize"        
    }
}

# Data Cache
$DataCache = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\PeerDist\CacheMgr\RePublication" -Name SizePercent -ErrorAction SilentlyContinue
if ($DataCache.SizePercent -ne $BCSizePercent) 
{
    if ($Remediate) 
    {
        $null = Get-BCDataCache | Set-BCCache -Percentage $BCSizePercent -Force
    }
    else 
    {
        $outPutString = "{0},{1}" -f $outPutString, "BCDataCacheWrongSize"   
    }
}

# Publication Catalog
$PupCatalog = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\PeerDist\CacheMgr\Publication" -Name DatabaseCatalogSizePercent -ErrorAction SilentlyContinue
if ($PupCatalog.DatabaseCatalogSizePercent -ne $BCSizePercent) 
{
    if ($Remediate) 
    {
        $null = New-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\PeerDist\CacheMgr\Publication" -Name DatabaseCatalogSizePercent -PropertyType DWord -Value $BCSizePercent -Force
    }
    else 
    {
        $outPutString = "{0},{1}" -f $outPutString, "BCPubCatalogWrongSize"         
    }
}

# RePublication Catalog
$RePupCatalog = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\PeerDist\CacheMgr\RePublication" -Name DatabaseCatalogSizePercent -ErrorAction SilentlyContinue
if ($RePupCatalog.DatabaseCatalogSizePercent -ne $BCSizePercent) 
{
    if ($Remediate) 
    {
        $null = New-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\PeerDist\CacheMgr\RePublication" -Name DatabaseCatalogSizePercent -PropertyType DWord -Value $BCSizePercent -Force
    }
    else
    {
        $outPutString = "{0},{1}" -f $outPutString, "BCRePubCatalogWrongSize"
    }
}

# Fix BranchCache data max age
$CacheAge = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PeerDist\Retrieval" -Name SegmentTTL -ErrorAction SilentlyContinue
if ($CacheAge.SegmentTTL -ne $BCDataCacheEntryMaxAgeDays) 
{
    if ($Remediate) 
    {
        $null = Set-BCDataCacheEntryMaxAge -TimeDays $BCDataCacheEntryMaxAgeDays -Force
    }
    else 
    {
        $outPutString = "{0},{1}" -f $outPutString, "BCDataCacheEntryMaxAgeWrong"        
    }
}

# Restart service to apply new settings
if ($Remediate) 
{
    $null = Restart-Service PeerDistSvc -Force
}
#endregion



#region Validate Data Dediplication feature and settings
#Check Dedup Feature Installed, install if missing
$DedupFeature = Get-WindowsFeature -Name FS-Data-Deduplication
if (-NOT ($DedupFeature.Installed)) 
{
    if ($Remediate) 
    {
        # Install dedup feature
        $null = Install-WindowsFeature -Name FS-Data-Deduplication
    }
    else 
    {
        $outPutString = "{0},{1}" -f $outPutString, "DeDupFeatureMissing"         
    }
}


$ContentLibDrive = (Get-ItemProperty -Path "HKLM:\Software\Microsoft\SMS\DP" -Name ContentLibraryPath -ErrorAction Stop).ContentLibraryPath
$ContentLibVolume = ($ContentLibDrive).SubString(0, 2)
# Check Dedup enabled, enable if disabled and write status to variable for future processing
$ContenLibDedupStatus = Get-DedupVolume -Volume $ContentLibVolume -ErrorAction SilentlyContinue 
if (-NOT ($ContenLibDedupStatus.Enabled))
{
    if ($Remediate) 
    {
        $null = Enable-DedupVolume $ContentLibVolume -ErrorAction Stop
    }
    else 
    {
        $outPutString = "{0},{1}" -f $outPutString, "DeDupNotEnabled"        
    }
}     
     
# Check if folders are excluded from DeDuplication
$ContenLibDedupStatus = Get-DedupVolume -Volume $ContentLibVolume -ErrorAction SilentlyContinue
$RemediateExcludes = $false
$DedupExcludeFolders = @()
$DedupExcludeFolders = $ContenLibDedupStatus.ExcludeFolder
if (-NOT $DedupExcludeFolders)
{
    $DedupExcludeFolders = @()
}

# check BranchCache folder
if (-NOT ("\BranchCache" -in $DedupExcludeFolders))
{
    $DedupExcludeFolders += "\BranchCache"
    $outPutString = "{0},{1}" -f $outPutString, "BCFolderNotExcludedFromDeDup"
    $RemediateExcludes = $true
}


if ($ExcludeConnectedCacheFolderFromDeDup)
{
    if (Test-Path "$ContentLibVolume\$ConnectedCacheFolderName")
    {
        if (-NOT ("\$ConnectedCacheFolderName" -in $DedupExcludeFolders))
        {
            $DedupExcludeFolders += "\$ConnectedCacheFolderName"
            $outPutString = "{0},{1}" -f $outPutString, "ConnectedCacheFolderNotExcludedFromDeDup"
            $RemediateExcludes = $true
        }
    }
}

if ($Remediate -and $RemediateExcludes) 
{
    $null = Set-DedupVolume $ContentLibVolume -ExcludeFolder $DedupExcludeFolders -ErrorAction Stop
    # We could also start dedup optimization. If not manually started, the job will start a few hours later and will then run every hour. 
    #$null = Start-DedupJob -Volume $ContentLibVolume -Type Optimization
}

#endregion

#region Final output
if (-NOT ($Remediate))
{
    if ($outPutString)
    {
        # Remove starting comma 
        if ($outPutString.StartsWith(','))
        {
            $outPutString = $outPutString.Substring(1,$outPutString.Length-1)
        }
        Write-Output $outPutString
        Exit    
    }
    else 
    {
        Write-Output "Compliant"
        Exit
    }
}
#endregion
