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
# Source: https://github.com/jonasatgit/scriptrepo

<#
.Synopsis
    Script to import a set of collections based on a JSON definition file.
.DESCRIPTION
    Script to import a set of collections based on a JSON definition file.
    Can create schedules, includes and excludes, query memberships and maintenance windows.
.EXAMPLE
    .\New-ConfigMgrDefaultCollections.ps1
.EXAMPLE
    .\New-ConfigMgrDefaultCollections.ps1 -SiteCode "P01" -ProviderMachineName "server1.contoso.local"
.PARAMETER ProviderMachineName
    Name of the SMS Provider. Will use local system if nothing has been set.
.PARAMETER SiteCode
    ConfigMgr SiteCode
.PARAMETER ReCreateCollections
    Switch Parameter to delete existing collections. Helpful to re-create collections if someting is wrong with them or just for testing
.PARAMETER UpdateCollectionSettings
    NOT USED at the moment
.PARAMETER AddMaintenanceWindows
    Switch parameter to add maintenance windows. The script will ignore maintenacne windows by default to not cause any problems in production environments. 
#>
param
(
    [Parameter(Mandatory=$false)]
    [string]$ProviderMachineName = $env:COMPUTERNAME,
    [Parameter(Mandatory=$true)]
    [string]$SiteCode,
    [Parameter(Mandatory=$false)]
    [Switch]$ReCreateCollections = $false,
    [Parameter(Mandatory=$false)]
    [Switch]$UpdateCollectionSettings = $false,
    [Parameter(Mandatory=$false)]
    [Switch]$AddMaintenanceWindows
)

function Stop-CurrentScript
{
    param
    (
        $ExitCode,
        $Location = $global:LocationPath
    )

    if ($Location)
    {
        Set-Location $Location
    }

    Write-host "Script end!" -ForegroundColor Green
    Exit $ExitCode
}


$ScheduleDefinitionFileObject = Get-ChildItem (Split-Path -path $PSCommandPath) -Filter '*.json' | Select-Object Name, Length, LastWriteTime, FullName | Out-GridView -Title 'Choose a JSON configfile' -OutputMode Single
if (-NOT($ScheduleDefinitionFileObject))
{
    Stop-CurrentScript -ExitCode 0
}

# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Import the ConfigurationManager.psd1 module 
if ($null -eq (Get-Module ConfigurationManager)) 
{
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if ($null -eq (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) 
{
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Set the current location to be the site code.
$global:LocationPath = (Get-Location).Path
Set-Location "$($SiteCode):\" @initParams

# much faster then using Get-CMCollection
$existingCollections = Get-CimInstance -Namespace "root\sms\site_$SiteCode" -Query "Select Name, CollectionID, LimitToCollectionID from SMS_Collection"

try
{ 
    $definitionFile = (Get-Content -Path ($ScheduleDefinitionFileObject.FullName) -ErrorAction Stop) -join "`n" | ConvertFrom-Json -ErrorAction Stop
}
Catch
{
    Write-Host "$($Error[0].Exception)" -ForegroundColor Red
    Write-Host "------------------------------------" -ForegroundColor Red
    Write-Host "Could not load JSON definition file!" -ForegroundColor Red
    Write-Host "Open the file in VSCode and resolve any problems highlighted." -ForegroundColor Red
    Stop-CurrentScript -ExitCode 1
}

$selectObjectPropertyList = ("Exists",`
    "CollectionName",`
    "LimitingCollectionName",`
    "CollectionFolder",`
    "CollectionType",`
    "RefreshType",`
    "RefreshStartDate",`
    "RefreshStartTime",`
    "RefreshRecurInterval",`
    "RefreshRecurCount",`
    "RefreshScheduleString",`
    "WQLQuerys",`
    "IncludeCollections",`
    "ExcludeCollections",`
    "ServiceWindows",`
    "CollectionDescription",`
    "LimitToCollectionID")

[array]$selectedCollections = $definitionFile.CollectionList.Collections | ForEach-Object {
 
        $_ | Add-Member -MemberType NoteProperty -Name 'Exists' -Value 'No'
        $_ | Add-Member -MemberType NoteProperty -Name 'LimitToCollectionID' -Value ''

        $collName = $_.CollectionName
        $collExists = $null
        $collExists = $existingCollections.Where({$_.Name -eq $collName})
        # adding exist info
        if ($collExists)
        {
            $_.Exists = 'Yes'
            $_.LimitToCollectionID = $collExists.LimitToCollectionID
        }

        # adding refresh date in case none was specified
        if ($_.RefreshType -in ('Periodic','Both'))
        {
            # in case we dont have a refresh schedule string, validate every other schedule parameter and set each one to default values if empty
            if (-NOT($_.RefreshScheduleString))
            {
                if (-NOT($_.RefreshStartDate)){$_.RefreshStartDate = (get-date -Format 'yyyy-MM-dd')}
                if (-NOT($_.RefreshStartTime)){$_.RefreshStartTime = (get-date -Format 'hh:mm')}
                if (-NOT($_.RefreshRecurInterval)){$_.RefreshRecurInterval = 'Days'}
                if (-NOT($_.RefreshRecurCount)){$_.RefreshRecurCount = 7}
            }
            else 
            {
                # clear out other parameters when using RefreshScheduleString
                if ($_.RefreshStartDate -or $_.RefreshStartTime -or $_.RefreshRecurInterval -or $_.RefreshRecurCount)
                {
                    Write-Host "`"$($_.CollectionName)`" No need for other schedule parameters in JSON if RefreshScheduleString is set." -ForegroundColor Yellow
                }
                $_.RefreshStartDate = ''
                $_.RefreshStartTime = ''
                $_.RefreshRecurInterval = ''
                $_.RefreshRecurCount = ''              
            }
        }

        # output to gridview
        $_

    } | Select-Object -Property $selectObjectPropertyList | Out-GridView -Title 'Select Collections. IMPORTANT: They will be created in the selection order! Choose limiting collections before sub-collections' -OutputMode Multiple


# Working with selected collections
if ($ReCreateCollections)
{
    $collectionsToDeleteSorted = New-Object System.Collections.ArrayList
    [array]$collectionsToDelete = $selectedCollections.Where({$_.Exists -eq 'Yes' -and $_.LimitToCollectionID -notlike 'SMS*'})
    [array]$rootCollectionsToDelete = $selectedCollections.Where({$_.LimitToCollectionID -like 'SMS*'})
    
    # creating sorted list to delete from the bottom to the top
    foreach ($deleteCollection in $collectionsToDelete | Sort-Object -Property LimitToCollectionID -Descending)
    {
        [void]$collectionsToDeleteSorted.Add($deleteCollection)
    }

    # adding root collections to the end of the list
    foreach ($deleteCollection in $rootCollectionsToDelete)
    {
        [void]$collectionsToDeleteSorted.Add($deleteCollection)
    }


    foreach ($item in $collectionsToDeleteSorted)
    {
        Write-Host "Remove collection: `"$($item.CollectionName)`"" -ForegroundColor Green
        try
        {
            Get-CMCollection -Name ($item.CollectionName) | Remove-CMCollection -Force
        }
        Catch
        {
            if ($_ -like '*2147749889*')
            {
                Write-Host "Error: `"$($item.CollectionName)`" is a limiting collection. Try to delete sub-collections first by also selecting them or via manual deletion." -ForegroundColor Red
                break
            }
            else
            {
                Write-Host $_ -ForegroundColor Red
                break
            }
        }
    }
}

if (-NOT $AddMaintenanceWindows)
{
    Write-Host "Maintenance Windows will not be created. Use parameter -AddMaintenanceWindows to force Maintenance Window creation" -ForegroundColor Yellow
}

foreach($collectionItem in $selectedCollections)
{

    # check limiting collection name first
    if(-NOT (Get-CimInstance -Namespace "root\sms\site_$SiteCode" -Query "Select Name from SMS_Collection where Name = '$($collectionItem.LimitingCollectionName)'"))
    {
        Write-Host "Create Limiting collection first: `"$($collectionItem.LimitingCollectionName)`"" -ForegroundColor Red
        Write-Host "Will skip collection: `"$($collectionItem.CollectionName)`"" -ForegroundColor Yellow
        continue
    }


    if (-NOT ($ReCreateCollections))
    {
        # skip existing collections
        if ($collectionItem.Exists -eq 'Yes')
        {
            Write-Host "Skipping existing collection: `"$($collectionItem.CollectionName)`"" -ForegroundColor Yellow
            continue
        }
    }


    try
    {

        # create new collection
        $paramsplatting = @{
            CollectionType         = $collectionItem.CollectionType    
            Name                   = $collectionItem.CollectionName
            LimitingCollectionName = $collectionItem.LimitingCollectionName
            RefreshType            = $collectionItem.RefreshType
            Comment                = $collectionItem.CollectionDescription
        }

        # define collection schedule if needed
        if ($collectionItem.RefreshType -in ('Periodic','Both'))
        {
            if ($collectionItem.RefreshScheduleString)
            {
                $cmSchedule = $null
                $cmSchedule = Convert-CMSchedule -ScheduleString ($collectionItem.RefreshScheduleString)
                $paramsplatting.RefreshSchedule = $cmSchedule
            }
            else 
            {   
                # creating new schedule
                $cmScheduleStartDate = '{0} {1}' -f $collectionItem.RefreshStartDate, $collectionItem.RefreshStartTime
                $cmSchedule = $null
                $cmSchedule = New-CMSchedule -Start ($cmScheduleStartDate) -RecurInterval ($collectionItem.RefreshRecurInterval) -RecurCount ($collectionItem.RefreshRecurCount)
                $paramsplatting.RefreshSchedule = $cmSchedule
            }
        }
        
        $newCollection = New-CMCollection @paramsplatting
        Write-Host "Collection created: `"$($collectionItem.CollectionName)`"" -ForegroundColor Green

        # Add Qery rules
        foreach ($WQLQuery in $collectionItem.WQLQuerys)
        {
            $paramsplatting = @{
                InputObject = $newCollection
                RuleName  = $WQLQuery.QueryName
                QueryExpression = $WQLQuery.Query
            }  
        
            $null = Add-CMDeviceCollectionQueryMembershipRule @paramsplatting
            Write-Host "     Query rule added: `"$($WQLQuery.QueryName)`"" -ForegroundColor Green
        }

        # Add Include rules
        foreach ($includeRule in $collectionItem.IncludeCollections)
        {
            $paramsplatting = @{
                InputObject = $newCollection
                IncludeCollectionName  = $includeRule
            }  
        
            $null = Add-CMDeviceCollectionIncludeMembershipRule @paramsplatting
            Write-Host "     Include rule added: `"$includeRule`"" -ForegroundColor Green
        }


        # Add Exclude rules
        foreach ($excludeRule in $collectionItem.ExcludeCollections)
        {
            $paramsplatting = @{
                InputObject = $newCollection
                ExcludeCollectionName  = $excludeRule
            }  
        
            $null = Add-CMDeviceCollectionExcludeMembershipRule @paramsplatting
            Write-Host "     Exclude rule added: `"$excludeRule`"" -ForegroundColor Green
        }

        if ($AddMaintenanceWindows)
        {
            # Add Maintenance Windows
            foreach ($serviceWindow in $collectionItem.ServiceWindows)
            {
                # convert schedule string into schedule object
                $cmSchedule = Convert-CMSchedule -ScheduleString ($serviceWindow.ScheduleString)

                $paramsplatting = @{
                    InputObject = $newCollection
                    Name = $serviceWindow.Name
                    Schedule  = $cmSchedule
                    ApplyTo = $serviceWindow.ApplyTo
                    IsUtc = $serviceWindow.IsUTC
                }  
            
                $null = New-CMMaintenanceWindow @paramsplatting
                Write-Host "     Maintenance/Service-Window added: `"$($serviceWindow.Name)`"" -ForegroundColor Green
            }
        }
    }
    Catch
    {
        Write-host "Error creating collection: `"$($collectionItem.CollectionName)`"" -ForegroundColor Red
        Write-Host "$($error[0].Exception)" -ForegroundColor Red
    }


    if (-NOT ([string]::IsNullOrEmpty($collectionItem.CollectionFolder)))
    {
        $collectionFolderPath = "DeviceCollection\{0}" -f $collectionItem.CollectionFolder
        [array]$folderListToBeCreated = @()
        If(-NOT(Get-CMFolder -FolderPath $collectionFolderPath))
        {
            Write-Host "$($collectionFolderPath)  => FOLDER NOT FOUND. Need to create." -ForegroundColor Yellow
            $folderListToBeCreated += $collectionFolderPath
            [array]$folderList = ($collectionFolderPath -split '\\')
            if ($folderList.count -gt 2) # not just one folder under root, need to check further
            {
                $objectFound = $false
                $i = ($folderList.Count)-2 # 1 for the array-zero and one for the last item in the array
                do
                {
                    $patchToCheck = $folderList[0..$i] -join '\'
                    Write-Host "Test folder: $($patchToCheck)" -ForegroundColor Green
                    if(Get-CMFolder -FolderPath $patchToCheck)
                    {
                        $objectFound = $true
                        Write-Host "$($patchToCheck)  => FOLDER exists" -ForegroundColor Green
                    }
                    else
                    {
                        $folderListToBeCreated += $patchToCheck
                        Write-Host "$($patchToCheck)  => FOLDER NOT FOUND. Need to create." -ForegroundColor Yellow
                    }
                    $i--
            
                }
                until ($objectFound -or ($i -le 2))

                foreach ($newFolderPath in ($folderListToBeCreated | Sort-Object))
                {
                    Write-Host "$($newFolderPath)  => WILL CREATE FOLDER" -ForegroundColor Green
                    $retVal = New-CMFolder -ParentFolderPath ($newFolderPath | Split-Path -Parent) -Name ($newFolderPath | Split-Path -Leaf)    
                }
            }
            else
            {
                Write-Host "$($folderList[0])\$($folderList[1])  => WILL CREATE FOLDER" -ForegroundColor Green
                $retVal = New-CMFolder -ParentFolderPath $folderList[0] -Name $folderList[1]
            }
        }

        try 
        {
            $movePathName = '{0}:\{1}' -f $SiteCode, $collectionFolderPath
            Move-CMObject -FolderPath $movePathName -InputObject ($newCollection)    
        }
        catch 
        {
            Write-host "Error moving collection: `"$($collectionItem.CollectionName)`"" -ForegroundColor Red
            Write-Host "$($error[0].Exception)" -ForegroundColor Red 
        }
    }  

} 
Write-Host "NOTE: Re-open the ConfigMgr console to be able to see new folders." -ForegroundColor Yellow
Stop-CurrentScript -ExitCode 0

