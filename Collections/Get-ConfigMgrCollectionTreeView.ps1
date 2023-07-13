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
   Get-ConfigMgrCollectionTreeView will show all ConfigMgr collections in a treeview
.DESCRIPTION
   Get-ConfigMgrCollectionTreeView will show all ConfigMgr collections in a treeview
   The code was written ~40% by Bing/GPT, GitHub CoPilot and ~60% by a human
.EXAMPLE
   Get-ConfigMgrCollectionTreeView.ps1 -siteCode 'P01' -providerServer 'CM01.contoso.local'
.EXAMPLE
   Another example of how to use this cmdlet
#>

[CmdletBinding()]
param
(
    $siteCode = 'P02',
    $providerServer = 'CM02.contoso.local'
)

$version = 'v0.2'

#region Get-TreeViewSubmember
<#
.Synopsis
   Get-TreeViewSubmember
.DESCRIPTION
   Get-TreeViewSubmember
.EXAMPLE
   Get-TreeViewSubmember -parent [System.Windows.Controls.TreeViewItem] -sub [items of [System.Windows.Controls.TreeViewItem]]
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Get-TreeViewSubmember
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
            Get-TreeViewSubmember -parent ($collectionItems[($subMember.CollectionID)]) -sub $subMembers
        }
    
    }
}
#endregion

#region Set-TreeViewItemColor
<#
.Synopsis
   Set-TreeViewItemColor
.DESCRIPTION
   Set-TreeViewItemColor
.EXAMPLE
   Set-TreeViewItemColor -items [System.Windows.Controls.TreeViewItem] -color [Red, Green, Black]
#>
Function Set-TreeViewItemColor
{
    param
    (
        [System.Windows.Controls.TreeViewItem]$treeviewItem,
        [ValidateSet("Red", "Green","Black")]
        [string]$color,
        [ValidateSet("Deployments", "Permissions","Reset")]
        [string]$type
    )

    switch ($type)
    {
        'Deployments' 
        {
            if ($treeviewItem.tag.DeploymentCount -gt 0)
            {
                $treeviewItem.Foreground = [System.Windows.Media.Brushes]::$color
            }
        }

        'Permissions' 
        {
            if ($treeviewItem.tag.AdminCount -gt 0)
            {
                $treeviewItem.Foreground = [System.Windows.Media.Brushes]::$color
            }
        }
        'Reset'
        {
            $treeviewItem.Foreground = [System.Windows.Media.Brushes]::Black
        }
    }

    # Load items recursive
    foreach($item in $treeviewItem.Items)
    {
        Set-TreeViewItemColor -treeviewItem $item -color $color -type $type     
    }

}
#endregion


#region Set-TreeViewItemColor
<#
.Synopsis
   Set-TreeViewItemColor
.DESCRIPTION
   Set-TreeViewItemColor
.EXAMPLE
   Set-TreeViewItemColor -items [System.Windows.Controls.TreeViewItem] -color [Red, Green, Black]
#>
Function Set-TreeViewItemColor2
{
    param
    (
        [System.Windows.Controls.TreeViewItem]$treeviewItem,
        #[ValidateSet("Red", "Green","Black")]
        [string]$color= 'Red',
        [ValidateSet("Reset","Toggle deployments", "Toggle permissions","Toggle incremental updates","Toggle include or exclude","Toggle client settings","Toggle maintenance windows")]
        [string]$type
    )

    switch ($type)
    {
        "Toggle deployments"
        {
            if ($treeviewItem.tag.DeploymentCount -gt 0)
            {
                $color = 'Green'
                $treeviewItem.Foreground = [System.Windows.Media.Brushes]::$color
            }
        }
        "Toggle permissions" 
        {
            if ($treeviewItem.tag.AdminCount -gt 0)
            {
                $color = 'Red'
                $treeviewItem.Foreground = [System.Windows.Media.Brushes]::$color
            }
        }
        "Toggle incremental updates"
        {
            if ($treeviewItem.tag.CollectionRefreshType -in ('Incremental','Both'))
            {
                $color = 'Blue'
                $treeviewItem.Foreground = [System.Windows.Media.Brushes]::$color
            }        
        }
        "Toggle include or exclude"
        {
            if ($treeviewItem.tag.IncludeExcludeCollectionsCount -gt 0)
            {
                $color = 'Coral'
                $treeviewItem.Foreground = [System.Windows.Media.Brushes]::$color
            }            
        }
        "Toggle client settings"
        {
            if ($treeviewItem.tag.ClientSettingsCount -gt 0)
            {
                $color = 'Violet'
                $treeviewItem.Foreground = [System.Windows.Media.Brushes]::$color
            }          
        }
        "Toggle maintenance windows"
        {
            if ($treeviewItem.tag.ServiceWindowsCount -gt 0)
            {
                $color = 'Violet'
                $treeviewItem.Foreground = [System.Windows.Media.Brushes]::$color
            }          
        }
        'Reset'
        {
            $color = 'Black'
            $treeviewItem.Foreground = [System.Windows.Media.Brushes]::$color
        }
    }

    # Load items recursive
    foreach($item in $treeviewItem.Items)
    {
        Set-TreeViewItemColor2 -treeviewItem $item -type $type     
    }

}
#endregion


function Get-ConfigMgrCollectionSettings
{
    param
    (
        $cimsession,
        $siteCode,
        $collectionID
    )

    $collectionSettings = Get-CimInstance -CimSession $cimsession -Namespace "root\sms\site_$siteCode" -Query "Select * from SMS_CollectionSettings where CollectionID = '$($collectionID)'"
    if ($collectionSettings)
    {
        # load lazy properties
        $collectionSettings = $collectionSettings | Get-CimInstance
        return $collectionSettings
    }
}



Write-Verbose "New DCOM connection to $($providerServer)"
try
{
    $cimSessionOptions = New-CimSessionOption -Protocol Dcom
    $cimSession = New-CimSession -ComputerName $providerServer -SessionOption $cimSessionOptions -ErrorAction Stop
}
catch
{
    $_
    Write-Host "Was trying to connect to: $($providerServer) via DCOM" -ForegroundColor Yellow
    Write-Host "Need to stop script due to error" -ForegroundColor Yellow
    Exit
}

Write-Verbose "Get all collections"
$collectionHashTable = @{}
[array]$global:collectionList = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "Select * from SMS_Collection"
$global:collectionList | ForEach-Object {
    $collectionHashTable.add($_.CollectionID, $_.Name)
}

Write-Verbose "Get all client settings deployments"
$clientSettingsHashTable = @{}
[array]$clientSettings = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "SELECT ClientSettingsID, CollectionID FROM SMS_ClientSettingsAssignment"
$clientSettings | Group-Object -Property CollectionID | ForEach-Object {
    [void]$clientSettingsHashTable.add($_.Name, $_.Count)
}

Write-Verbose "Get all deployments"
$collectionDeploymentsHashTable = @{}
[array]$global:collectionDeployments = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "SELECT SoftwareName, DeploymentID, CollectionID FROM SMS_DeploymentSummary"
$collectionDeployments | Group-Object -Property CollectionID | ForEach-Object {
    [void]$collectionDeploymentsHashTable.add($_.Name, $_.Count)
}


Write-Verbose "Get all ConfigMgr admins"
[array]$adminList = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "Select * from SMS_Admin"

# Load lazy properties to be able to access permissions
$adminList = $adminList | ForEach-Object {$_ | Get-CimInstance}

$adminPermissionList = $adminList | ForEach-Object {

    $logonName = $_.LogonName

    foreach($permission in ($_.Permissions | Where-Object {$_.CategoryTypeID -eq 1} | Select-Object -Property CategoryID))
    {
        [PSCustomObject]@{
            LogonName = $logonName
            CollectionPermissions = $permission.CategoryID
        }
    }

}

# Lets remove duplicates from different roles
$adminPermissionList = $adminPermissionList | Sort-Object -Property LogonName, CollectionPermissions -Unique

# Group permissions based on collectionID
$adminHashTable = @{}
$adminPermissionListGrouped = $adminPermissionList | Group-Object -Property CollectionPermissions
foreach($groupItem in $adminPermissionListGrouped)
{
    $adminHashTable.add($groupItem.Name, [array]($groupItem.Group.LogonName))
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
    'AdminCount',
    'QueryRules',
    #'Admins',
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
$window.Title = "$($version) TreeView of $($global:collectionList.count) collections         --> https://github.com/jonasatgit/scriptrepo/tree/master/Collections <--"

# Create the main grid and set properties
$mainGrid = New-Object System.Windows.Controls.Grid
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(400)
$mainGrid.ColumnDefinitions[2].Width = [System.Windows.GridLength]::new(400)

$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
#$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions[0].Height = [System.Windows.GridLength]::new(45)
$mainGrid.RowDefinitions[1].Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
#$mainGrid.RowDefinitions[1].Height = [System.Windows.GridLength]::new(40)
#$mainGrid.RowDefinitions[2].Height = [System.Windows.GridLength]::new(40)


# Create a StackPanel and set properties
$stackPanel = New-Object System.Windows.Controls.StackPanel
$stackPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal

# Create the CheckBox and set properties
$checkBox = New-Object System.Windows.Controls.CheckBox
$checkBox.Content = "Toggle Deployed"
$checkBox.Margin = "10,10,10,10"
[System.Windows.Controls.Grid]::SetRow($checkBox, 0)


# Add Checked event handler
$checkBox.Add_Checked({
    $checkBox2.IsChecked =$false
    foreach($item in $treeView.Items)
    {
        Set-TreeViewItemColor -treeviewItem $item -color Green -type Deployments
    }
})

# Add Unchecked event handler
$checkBox.Add_Unchecked({
    foreach($item in $treeView.Items)
    {
        Set-TreeViewItemColor -treeviewItem $item -color Black -type Reset
    }

})

# Create the second CheckBox and set properties
$checkBox2 = New-Object System.Windows.Controls.CheckBox
$checkBox2.Content = "Toggle Permissions"
$checkBox2.Margin = "10,10,10,10"

# Add Checked event handler
$checkBox2.Add_Checked({
    $checkBox.IsChecked = $false
    foreach($item in $treeView.Items)
    {
        Set-TreeViewItemColor -treeviewItem $item -color Red -type Permissions
    }
})

# Add Unchecked event handler
$checkBox2.Add_Unchecked({
    foreach($item in $treeView.Items)
    {
        Set-TreeViewItemColor -treeviewItem $item -color Black -type Reset
    }
})


# Create the second CheckBox and set properties
$checkBox3 = New-Object System.Windows.Controls.CheckBox
$checkBox3.Content = "Toggle Permissions"
$checkBox3.Margin = "10,10,10,10"

# Add Checked event handler
$checkBox3.Add_Checked({
    
})

# Add Unchecked event handler
$checkBox3.Add_Unchecked({
    
})

# Create the second CheckBox and set properties
$checkBox4 = New-Object System.Windows.Controls.CheckBox
$checkBox4.Content = "Toggle Permissions"
$checkBox4.Margin = "10,10,10,10"

# Add Checked event handler
$checkBox4.Add_Checked({
    
})

# Add Unchecked event handler
$checkBox4.Add_Unchecked({
    
})

$comboBox = New-Object System.Windows.Controls.ComboBox
$comboBox.Margin = "10,10,10,10"
$comboBox.Width = 200
$comboBox.Height = 22
[void]$comboBox.Items.Add("Toggle deployments")
[void]$comboBox.Items.Add("Toggle permissions")
[void]$comboBox.Items.Add("Toggle incremental updates")
[void]$comboBox.Items.Add("Toggle include or exclude")
[void]$comboBox.Items.Add("Toggle client settings")
[void]$comboBox.Items.Add("Toggle maintenance windows")
[void]$comboBox.Items.Add("Reset")

$comboBox.Add_SelectionChanged({
    # Get the selected item from the ComboBox
    #$selectedItem = $comboBox.SelectedItem
    #Write-Host $comboBox.SelectedItem

    foreach($item in $treeView.Items)
    {
        Set-TreeViewItemColor2 -treeviewItem $item -type Reset
    }

    foreach($item in $treeView.Items)
    {
        Set-TreeViewItemColor2 -treeviewItem $item -type $comboBox.SelectedItem
    }
})


# Add the CheckBoxes to the StackPanel
#[void]$stackPanel.Children.Add($checkBox)
#[void]$stackPanel.Children.Add($checkBox2)
#[void]$stackPanel.Children.Add($checkBox3)
#[void]$stackPanel.Children.Add($checkBox4)
[void]$stackPanel.Children.Add($comboBox)


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
[System.Windows.Controls.Grid]::SetRow($treeView, 1)


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
        'AdminCount' 
        {
            [array]$properties = $global:selectedCollection.Admins | ForEach-Object {
                    [PSCustomObject]@{
                    LogonName = $_
                    }

            }
        }
        'QueryRules'
        {
            $global:selectedCollection = $global:selectedCollection | Get-CimInstance 
            [array]$properties = $global:selectedCollection.CollectionRules | Where-Object {$_.QueryExpression -ne $null} | ForEach-Object {
                    [PSCustomObject]@{
                    RuleName = $_.RuleName
                    Query = $_.QueryExpression
                    }
            
            }
        }
        'ServiceWindowsCount'
        {
            if ($global:selectedCollection.ServiceWindowsCount -gt 0)
            {
                $CollectionSettings = Get-ConfigMgrCollectionSettings -cimsession $cimSession -siteCode $siteCode -collectionID ($global:selectedCollection.CollectionID)
                if ($CollectionSettings)
                {
                    [array]$properties = $CollectionSettings.ServiceWindows | ForEach-Object {

                        Switch($_.ServiceWindowType)
                        {
                            1{$ServiceWindowType = 'All deployments'}
                            4{$ServiceWindowType = 'Updates'}
                            5{$ServiceWindowType = 'Task sequences'}
                            Default{$ServiceWindowType = 'Unknown'}                        
                        }
                            
                        [PSCustomObject]@{
                            ServiceWindowType = $ServiceWindowType
                            Description = $_.Description
                            Name = $_.Name
                        }
                    } 
                
                }
            }
        }
        'CollectionVariablesCount'
        {
            if ($global:selectedCollection.CollectionVariablesCount -gt 0)
            {
                $CollectionSettings = Get-ConfigMgrCollectionSettings -cimsession $cimSession -siteCode $siteCode -collectionID ($global:selectedCollection.CollectionID)
                if ($CollectionSettings)
                {
                    [array]$properties = $CollectionSettings.CollectionVariables | ForEach-Object {
                        [PSCustomObject]@{
                        Name = $_.Name
                        IsMasked = $_.IsMasked
                        Value = $_.Value
                        }
                    } 
                
                }
            }              
        }
    }

    if ($selectedItem -ne $null) {
        $dataGrid1.ItemsSource = $properties
    } else {
        $dataGrid1.ItemsSource = $null
    }
})
[System.Windows.Controls.Grid]::SetColumn($dataGrid, 1)
[System.Windows.Controls.Grid]::SetRow($dataGrid, 1)

$dataGrid1 = New-Object System.Windows.Controls.DataGrid
$dataGrid1.IsReadOnly = $true
$dataGrid1.HeadersVisibility = "All"
$dataGrid1.AutoGenerateColumns = $true
[System.Windows.Controls.Grid]::SetColumn($dataGrid1, 2)
[System.Windows.Controls.Grid]::SetRow($dataGrid1, 1)


# Add the TreeView and data grid and checkbox to the main grid
#[void]$mainGrid.Children.Add($checkBox)
[void]$mainGrid.Children.Add($stackPanel)
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

    $collection | Add-Member -MemberType NoteProperty -Name Admins -value $adminHashTable[($collection.CollectionID)] 
    $collection | Add-Member -MemberType NoteProperty -Name AdminCount -Value $collection.Admins.Count

    $collection | Add-Member -MemberType NoteProperty -Name QueryRules -Value 'Click to load'


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
        Get-TreeViewSubmember -parent $item -sub $subMembers
    }
    [void]$treeView.Items.Add($item)

}


# Add the main grid to the window
$window.Content = $mainGrid

# Show the window
$window.ShowDialog() | Out-Null
if($cimSession)
{
    $cimSession | Remove-CimSession
}

Write-Verbose "Done"