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

$siteCode = 'P02'
$providerServer = 'CM02.contoso.local'

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
    Write-Host "work on parent: $($parent.tag.Name)"
    foreach($subMember in ($sub | Sort-Object -Property Name))
    {
        Write-Host "work on sub: $($subMember.Name)"
        [void]$parent.Items.Add(($collectionItems[($subMember.CollectionID)]))

        $subMembers = $collectionList.where({$_.LimitToCollectionID -eq $subMember.CollectionID}) | Sort-Object -Property Name

        if ($subMembers)
        {
            Get-Submember -parent ($collectionItems[($subMember.CollectionID)]) -sub $subMembers
        }
    
    }
}


$cimSessionOptions = New-CimSessionOption -Protocol Dcom
$cimSession = New-CimSession -ComputerName $providerServer -SessionOption $cimSessionOptions

[array]$global:collectionList = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "Select * from SMS_Collection"

[array]$clientSettings = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "SELECT ClientSettingsID, CollectionID FROM SMS_ClientSettingsAssignment"

$clientSettingsHashTable = @{}
$clientSettings | Group-Object -Property CollectionID | ForEach-Object {
    [void]$clientSettingsHashTable.add($_.Name, $_.Count)
}


[array]$global:collectionDeployments = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "SELECT SoftwareName, DeploymentID, CollectionID FROM SMS_DeploymentSummary"

$collectionDeploymentsHashTable = @{}
$collectionDeployments | Group-Object -Property CollectionID | ForEach-Object {
    [void]$collectionDeploymentsHashTable.add($_.Name, $_.Count)
}

$propertyList = ('CollectionID',
    'CollectionRefreshType',
    'ClientSettingsCount',
    'DeploymentCount',
    'CollectionVariablesCount',
    'IncludeExcludeCollectionsCount',
    'MemberCount',
    'ServiceWindowsCount',
    'UseCluster'
    )


# Load the required assemblies
Add-Type -AssemblyName PresentationFramework

# Create the window and set properties
$window = New-Object System.Windows.Window
$window.Title = "Collection TreeView"

# Create the main grid and set properties
$mainGrid = New-Object System.Windows.Controls.Grid
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))

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

# Create the data grid and set properties
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
        'DeploymentCount' {
                            $propsList = $global:collectionDeployments.where({$_.CollectionID -eq $global:selectedCollection.CollectionID}) | Select-Object SoftwareName | Sort-Object SoftwareName
                            $properties = $propsList | ForEach-Object {
                                [PSCustomObject]@{
                                        Deployments = $_.SoftwareName
                                    }
                                }
                          }
    
    }

    if ($selectedItem -ne $null) {
        # TODO: Update this code to display the desired data in the second data grid based on the selected item in the first data grid
        # Example:
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


# Create tree view items and put them in a hashtable for easy access
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

    $item = New-Object System.Windows.Controls.TreeViewItem
    $item.Header = $collection.Name
    $item.Tag = $collection

    [void]$collectionItems.add($collection.CollectionID, $item)
  
}


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
$window.ShowDialog()
