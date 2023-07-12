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

# Simple script to display the ConfigMgr collections in a tree view
# Change the $siteCode and $providerServer variables to match your environment
[CmdletBinding()]
param
(
    $siteCode = 'P02',
    $providerServer = 'CM02.contoso.local'
)


<#
.Synopsis
   Get-Submember
.DESCRIPTION
   Get-Submember
.EXAMPLE
   Get-Submember -parent
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Get-Submember
{
    param
    (
        [System.Windows.Controls.TreeViewItem]$parent,
        $sub
    )
    Write-Verbose "work on parent: $($parent.tag.Name)"
    foreach($subMember in ($sub | Sort-Object -Property Name))
    {
        Write-Verbose "work on sub: $($subMember.Name)"
        [void]$parent.Items.Add(($collectionItems[($subMember.CollectionID)]))

        $subMembers = $collectionList.where({$_.LimitToCollectionID -eq $subMember.CollectionID}) | Sort-Object -Property Name

        if ($subMembers)
        {
            Get-Submember -parent ($collectionItems[($subMember.CollectionID)]) -sub $subMembers
        }
    
    }
}

Write-Verbose "New DCOM connection to $($providerServer)"
$cimSessionOptions = New-CimSessionOption -Protocol Dcom
$cimSession = New-CimSession -ComputerName $providerServer -SessionOption $cimSessionOptions

Write-Verbose "Get all collections"
$collectionHashTable = @{}
[array]$global:collectionList = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "Select * from SMS_Collection"
$global:collectionList | ForEach-Object {
    $collectionHashTable.add($_.CollectionID, $_.Name)
}

Write-Verbose "Get all client settings deployments"
[array]$clientSettings = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "SELECT ClientSettingsID, CollectionID FROM SMS_ClientSettingsAssignment"
$clientSettingsHashTable = @{}
$clientSettings | Group-Object -Property CollectionID | ForEach-Object {
    [void]$clientSettingsHashTable.add($_.Name, $_.Count)
}

Write-Verbose "Get all deployments"
[array]$global:collectionDeployments = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "SELECT SoftwareName, DeploymentID, CollectionID FROM SMS_DeploymentSummary"
$collectionDeploymentsHashTable = @{}
$collectionDeployments | Group-Object -Property CollectionID | ForEach-Object {
    [void]$collectionDeploymentsHashTable.add($_.Name, $_.Count)
}

Write-Verbose "Get all included or excluded collections"
# Get all include collection rules
$includeCollectionHashTable = @{}
$query = "Select * from SMS_CollectionDependencies where RelationshipType = 2"
$includeCollectionList = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query $query
$includeCollectionListClean = $includeCollectionList | ForEach-Object {

            [PSCustomObject]@{
                DependentCollectionID = $_.DependentCollectionID
                SourceCollectionID = $_.SourceCollectionID
                SourceCollectionName = $collectionHashTable[($_.SourceCollectionID)] 
            }

}

$includeCollectionListClean | Group-Object -Property DependentCollectionID | ForEach-Object {
    
    [void]$includeCollectionHashTable.Add($_.Name, $_.Group)
}

# Get all exclude collection rules
$excludeCollectionHashTable = @{}
$query = "Select * from SMS_CollectionDependencies where RelationshipType = 3"
$excludeCollectionList = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query $query
$excludeCollectionListClean = $excludeCollectionList | ForEach-Object {

            [PSCustomObject]@{
                DependentCollectionID = $_.DependentCollectionID
                SourceCollectionID = $_.SourceCollectionID
                SourceCollectionName = $collectionHashTable[($_.SourceCollectionID)] 
            }

}

$excludeCollectionListClean | Group-Object -Property DependentCollectionID | ForEach-Object {

    [void]$excludeCollectionHashTable.Add($_.Name, $_.Group)
}



$propertyList = ('CollectionID',
    'CollectionRefreshType',
    'ClientSettingsCount',
    'DeploymentCount',
    'CollectionVariablesCount',
    #'IncludeExcludeCollectionsCount',
    'IncludeCollectionsCount',
    'ExcludeCollectionsCount',
    'MemberCount',
    'ServiceWindowsCount',
    'PowerConfigsCount',
    'UseCluster',
    'ObjectPath'
    )


# Load the required assemblies
Add-Type -AssemblyName PresentationFramework

# Create the window and set properties
$window = New-Object System.Windows.Window
$window.Title = "Collection TreeView of $($global:collectionList.count) collections"

# Create the main grid and set properties
$mainGrid = New-Object System.Windows.Controls.Grid
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(400)
$mainGrid.ColumnDefinitions[2].Width = [System.Windows.GridLength]::new(400)


# Create the TreeView and set properties
$treeView = New-Object System.Windows.Controls.TreeView
$treeView.Add_SelectedItemChanged({
    param($sender, $e)

    # Update the data grid with the selected item data
    $selectedItem = $e.NewValue
    $global:selectedCollection = $selectedItem.Tag
    if ($selectedItem -ne $null) {
        $properties = $selectedItem.Tag | Select-Object -Property $propertyList | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        $dataGrid.ItemsSource = $properties | ForEach-Object {
            [PSCustomObject]@{
                Property = $_
                Value = $selectedItem.Tag.$_
            }
        }
    } else {
        $dataGrid.ItemsSource = $null
    }
})
[System.Windows.Controls.Grid]::SetColumn($treeView, 0)


Write-Verbose "Create the data grid and set properties"
$dataGrid = New-Object System.Windows.Controls.DataGrid
$dataGrid.IsReadOnly = $true
$dataGrid.HeadersVisibility = "All"
$dataGrid.AutoGenerateColumns = $true
$dataGrid.Add_SelectionChanged({
    param($sender, $e)

    # Update the second data grid with the selected item data
    $selectedItem = $e.AddedItems[0]

    Switch($selectedItem.Property)
    {
        'DeploymentCount' 
        {
            [array]$properties = $global:collectionDeployments.where({$_.CollectionID -eq $global:selectedCollection.CollectionID}) | Select-Object SoftwareName | Sort-Object SoftwareName
        }
        'IncludeCollectionsCount' 
        {
            [array]$properties = $global:selectedCollection.IncludeCollections | Select-Object SourceCollectionID, SourceCollectionName | Sort-Object SourceCollectionName
        }
        'ExcludeCollectionsCount' 
        {
            [array]$properties = $global:selectedCollection.ExcludeCollections | Select-Object SourceCollectionID, SourceCollectionName | Sort-Object SourceCollectionName
        }
    }

    if ($selectedItem -ne $null) {
        $dataGrid1.ItemsSource = $properties
    } else {
        $dataGrid1.ItemsSource = $null
    }
})
[System.Windows.Controls.Grid]::SetColumn($dataGrid, 1)

$dataGrid1 = New-Object System.Windows.Controls.DataGrid
$dataGrid1.IsReadOnly = $true
$dataGrid1.HeadersVisibility = "All"
$dataGrid1.AutoGenerateColumns = $true
[System.Windows.Controls.Grid]::SetColumn($dataGrid1, 2)


# Add the TreeView and data grid to the main grid
[void]$mainGrid.Children.Add($treeView)
[void]$mainGrid.Children.Add($dataGrid)
[void]$mainGrid.Children.Add($dataGrid1)


Write-Verbose "Create treeview items hashtable and add additional info to collections"
$global:collectionItems = @{}
foreach($collection in $collectionList | Sort-Object -Property Name)
{
    $clientSettingsCount = $clientSettingsHashTable[($collection.CollectionID)]
    if(-NOT($clientSettingsCount))
    {
        $clientSettingsCount = 0
    }
    $collection | Add-Member -MemberType NoteProperty -Name ClientSettingsCount -Value $clientSettingsCount


    $collectionDeploymentCount = $collectionDeploymentsHashTable[($collection.CollectionID)]
    if(-NOT($collectionDeploymentCount))
    {
        $collectionDeploymentCount = 0
    }
    $collection | Add-Member -MemberType NoteProperty -Name DeploymentCount -Value $collectionDeploymentCount


    Switch($collection.RefreshType)
    {
        1 {$collectionRefreshType = 'None'}
        2 {$collectionRefreshType = 'Scheduled'}
        4 {$collectionRefreshType = 'Incremental'}
        6 {$collectionRefreshType = 'Both'}
    }
    $collection | Add-Member -MemberType NoteProperty -Name CollectionRefreshType -Value $collectionRefreshType

    $collection | Add-Member -MemberType NoteProperty -Name IncludeCollections -Value  $includeCollectionHashTable[($collection.CollectionID)]
    $collection | Add-Member -MemberType NoteProperty -Name IncludeCollectionsCount -Value  $collection.IncludeCollections.count
    $collection | Add-Member -MemberType NoteProperty -Name ExcludeCollections -Value  $excludeCollectionHashTable[($collection.CollectionID)]
    $collection | Add-Member -MemberType NoteProperty -Name ExcludeCollectionsCount -Value  $collection.ExcludeCollections.count

    $item = New-Object System.Windows.Controls.TreeViewItem
    $item.Header = $collection.Name
    $item.Tag = $collection

    [void]$collectionItems.add($collection.CollectionID, $item)
  
}

Write-Verbose "Add each collection item to treeview"
foreach($collection in $collectionList.where({[string]::IsNullOrEmpty($_.LimitToCollectionID)}) | Sort-Object -Property Name)
{

    $item = New-Object System.Windows.Controls.TreeViewItem
    $item.Header = $collection.Name
    $item.Tag = $collection

    # Lets now find sub-members
    $subMembers = $collectionList.where({$_.LimitToCollectionID -eq $collection.CollectionID}) | Sort-Object -Property Name

    if ($subMembers)
    {
        Get-Submember -parent $item -sub $subMembers
    }
    [void]$treeView.Items.Add($item)

}


# Add the main grid to the window
$window.Content = $mainGrid

# Show the window
$window.ShowDialog() | Out-Null
Write-Verbose "Done"