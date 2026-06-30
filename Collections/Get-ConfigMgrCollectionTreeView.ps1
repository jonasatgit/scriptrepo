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

   Version history:
   | Version | Notes                                                                                          |
   |---------|------------------------------------------------------------------------------------------------|
   | v0.1    | Initial version: basic treeview of all collections.                                            |
   | v0.2    | Added admin permissions and toggle box for highlighting collections by deployments/permissions.|
   | v0.3    | Added include/exclude collections, query rules and a second data grid for detail views.        |
   | v0.4    | Added search box and combo-box with more toggle options (incremental, client settings, MWs).   |
   | v0.5    | Added per-collection colored dot indicators for all criteria at once and a bottom legend bar.  |
   | v0.6    | Added GridSplitters between the three content boxes so the user can drag/resize the columns.   |
   | v0.7    | Fixed splitter behavior (independent column resize) and made toolbar span all columns.         |

.EXAMPLE
   Get-ConfigMgrCollectionTreeView.ps1 -siteCode 'P01' -providerServer 'CM01.contoso.local'

.EXAMPLE
   Another example of how to use this cmdlet
#>

[CmdletBinding()]
param
(
    $siteCode,
    $providerServer
)

$version = 'v0.7'

#region Get-TreeViewSubmember
<#
.Synopsis
   Get-TreeViewSubmember
.DESCRIPTION
   Get-TreeViewSubmember
.EXAMPLE
   Get-TreeViewSubmember -parent [System.Windows.Controls.TreeViewItem] -sub [items of [System.Windows.Controls.TreeViewItem]]
#>
function Get-TreeViewSubmember
{
    param
    (
        [System.Windows.Controls.TreeViewItem]$parent,
        $sub
    )
    Write-Verbose "work on parent: $($parent.tag.Name)"
    foreach($subMember in $sub)
    {
        $script:progressCounter++
        Write-Progress -Activity "Building collection tree" -Status "Processing: $($subMember.Name)" -PercentComplete ([math]::Min(($script:progressCounter / $global:collectionList.Count * 100), 100))
        Write-Verbose "work on sub: $($subMember.Name)"
        [void]$parent.Items.Add(($collectionItems[($subMember.CollectionID)]))

        $subMembers = $childrenHashTable[($subMember.CollectionID)]

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
        [ValidateSet("Reset","Search","Toggle deployments", "Toggle permissions","Toggle incremental updates","Toggle include or exclude","Toggle client settings","Toggle maintenance windows")]
        [string]$type,
        [string]$searchString
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
        'Search'
        {
            if ($treeviewItem.tag.Name -ilike "*$($searchString)*")
            {
                $color = 'Red'
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
        if (-NOT([string]::IsNullOrEmpty($searchString)))
        {
            Set-TreeViewItemColor2 -treeviewItem $item -type $type -searchString $searchString
        }
        else
        {
            Set-TreeViewItemColor2 -treeviewItem $item -type $type 
        }
    }

}
#endregion


#region New-CollectionHeader
<#
.Synopsis
   New-CollectionHeader
.DESCRIPTION
   Builds a WPF StackPanel containing the collection name followed by colored dots,
   one per criterion that applies to the collection (deployments, permissions,
   incremental updates, include/exclude rules, client settings, maintenance windows).
   Used as the Header of each TreeViewItem so the user gets a full overview at a glance.
#>
function New-CollectionHeader
{
    param
    (
        $collection
    )

    $headerPanel = New-Object System.Windows.Controls.StackPanel
    $headerPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal

    $nameBlock = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text = $collection.Name
    $nameBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [void]$headerPanel.Children.Add($nameBlock)

    # Each entry: condition that has to be true, dot color, tooltip text.
    # Colors are kept aligned with the original Set-TreeViewItemColor2 toggles,
    # except 'Maintenance windows' moved from Violet to DarkCyan so it no longer
    # collides visually with 'Client settings'.
    $dotDefinitions = @(
        @{ Test = ($collection.DeploymentCount -gt 0)                                              ; Color = 'Green'    ; Tip = "Deployments: $($collection.DeploymentCount)" }
        @{ Test = ($collection.AdminCount -gt 0)                                                   ; Color = 'Red'      ; Tip = "Admin permissions: $($collection.AdminCount)" }
        @{ Test = ($collection.CollectionRefreshType -in @('Incremental','Both'))                  ; Color = 'Blue'     ; Tip = "Incremental updates ($($collection.CollectionRefreshType))" }
        @{ Test = ((($collection.IncludeCollectionsCount) + ($collection.ExcludeCollectionsCount)) -gt 0) ; Color = 'Coral'    ; Tip = "Include: $($collection.IncludeCollectionsCount) / Exclude: $($collection.ExcludeCollectionsCount)" }
        @{ Test = ($collection.ClientSettingsCount -gt 0)                                          ; Color = 'Violet'   ; Tip = "Client setting deployments: $($collection.ClientSettingsCount)" }
        @{ Test = ($collection.ServiceWindowsCount -gt 0)                                          ; Color = 'DarkCyan' ; Tip = "Maintenance windows: $($collection.ServiceWindowsCount)" }
    )

    foreach($dot in $dotDefinitions)
    {
        if ($dot.Test)
        {
            $ellipse = New-Object System.Windows.Shapes.Ellipse
            $ellipse.Width  = 10
            $ellipse.Height = 10
            $ellipse.Margin = '6,0,0,0'
            $ellipse.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $ellipse.Fill = [System.Windows.Media.Brushes]::($dot.Color)
            $ellipse.Stroke = [System.Windows.Media.Brushes]::Black
            $ellipse.StrokeThickness = 0.5
            $ellipse.ToolTip = $dot.Tip
            [void]$headerPanel.Children.Add($ellipse)
        }
    }

    return $headerPanel
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

Write-Host "Get all collections" -ForegroundColor Green
$collectionHashTable = @{}
[array]$global:collectionList = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "Select * from SMS_Collection"
$global:collectionList | ForEach-Object {
    $collectionHashTable.add($_.CollectionID, $_.Name)
}

Write-Host "Get all client settings deployments" -ForegroundColor Green
$clientSettingsHashTable = @{}
[array]$clientSettings = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "SELECT ClientSettingsID, CollectionID FROM SMS_ClientSettingsAssignment"
$clientSettings | Group-Object -Property CollectionID | ForEach-Object {
    [void]$clientSettingsHashTable.add($_.Name, $_.Count)
}

Write-Host "Get all deployments" -ForegroundColor Green
$collectionDeploymentsHashTable = @{}
[array]$global:collectionDeployments = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "SELECT SoftwareName, DeploymentID, CollectionID FROM SMS_DeploymentSummary"
$collectionDeployments | Group-Object -Property CollectionID | ForEach-Object {
    [void]$collectionDeploymentsHashTable.add($_.Name, $_.Count)
}


Write-Host "Get all ConfigMgr admins" -ForegroundColor Green
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



Write-Host "Get all included or excluded collections" -ForegroundColor Green
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
$window.Height = 800
$window.Width = 1400

# Create the main grid and set properties
# Column layout: [0]=TreeView, [1]=Splitter, [2]=DataGrid (properties),
#                [3]=Splitter, [4]=DataGrid1 (values). The splitter columns let
#                the user drag the dividers to resize the three content boxes.
# All three content columns use Star sizing (with different initial ratios) so
# that the GridSplitter only redistributes the Star values of the two adjacent
# columns. That keeps the non-adjacent column's width unchanged when dragging.
$mainGrid = New-Object System.Windows.Controls.Grid
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(3, [System.Windows.GridUnitType]::Star)
$mainGrid.ColumnDefinitions[0].MinWidth = 150
$mainGrid.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(5)
$mainGrid.ColumnDefinitions[2].Width = [System.Windows.GridLength]::new(2, [System.Windows.GridUnitType]::Star)
$mainGrid.ColumnDefinitions[2].MinWidth = 100
$mainGrid.ColumnDefinitions[3].Width = [System.Windows.GridLength]::new(5)
$mainGrid.ColumnDefinitions[4].Width = [System.Windows.GridLength]::new(2, [System.Windows.GridUnitType]::Star)
$mainGrid.ColumnDefinitions[4].MinWidth = 100

$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions[0].Height = [System.Windows.GridLength]::new(45)
$mainGrid.RowDefinitions[1].Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
$mainGrid.RowDefinitions[2].Height = [System.Windows.GridLength]::new(40)
#$mainGrid.RowDefinitions[1].Height = [System.Windows.GridLength]::new(40)
#$mainGrid.RowDefinitions[2].Height = [System.Windows.GridLength]::new(40)


# Create a StackPanel and set properties
$stackPanel = New-Object System.Windows.Controls.StackPanel
$stackPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
$stackPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
$stackPanel.VerticalAlignment   = [System.Windows.VerticalAlignment]::Stretch
$stackPanel.Background = [System.Windows.Media.Brushes]::White
# Pin the toolbar to row 0 and span all 5 columns so its controls are not
# clipped when the user drags a column splitter to make a column narrow.
[System.Windows.Controls.Grid]::SetRow($stackPanel, 0)
[System.Windows.Controls.Grid]::SetRowSpan($stackPanel, 1)
[System.Windows.Controls.Grid]::SetColumn($stackPanel, 0)
[System.Windows.Controls.Grid]::SetColumnSpan($stackPanel, 5)

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
    foreach($item in $treeView.Items)
    {
        Set-TreeViewItemColor2 -treeviewItem $item -type Reset
    }

    foreach($item in $treeView.Items)
    {
        Set-TreeViewItemColor2 -treeviewItem $item -type $comboBox.SelectedItem
    }
})

# Textbox to be able to search a collection
$defaultTextString = "Search for collection name"
$textBox = New-Object System.Windows.Controls.TextBox
$textBox.Margin = "10,10,2,10"
$textBox.Width = 200
$textBox.Height = 22
$textBox.Text = $defaultTextString

$textBox.Add_GotFocus({
    if ($textBox.Text -eq $defaultTextString) 
    {
        $textBox.Clear()
    }
})

$textBox.Add_LostFocus({
    if ([string]::IsNullOrEmpty($textBox.Text)) 
    {
        $textBox.Text = $defaultTextString
    }
    # Lets also reset any previous color changes
    foreach($item in $treeView.Items)
    {
        Set-TreeViewItemColor2 -treeviewItem $item -type Reset
    }
})

# Button to be able to search
$button = New-Object System.Windows.Controls.Button
$button.Margin = "2,10,10,10"
$button.Width = 75
$button.Height = 22
$button.Content = "Search"

$button.Add_Click({
    # Use textbox to search for string
    if (([string]::IsNullOrEmpty($textBox.Text)) -or $textBox.Text -eq $defaultTextString)
    {
        # do nothing. Either empty or default text
    }
    else
    {
        # Reset any color first
        foreach($item in $treeView.Items)
        {
            Set-TreeViewItemColor2 -treeviewItem $item -type Reset
        }

        foreach($item in $treeView.Items)
        {
            Set-TreeViewItemColor2 -treeviewItem $item -type Search -searchString $textBox.Text
        }
    }

})


# Add the CheckBoxes to the StackPanel
#[void]$stackPanel.Children.Add($checkBox)
#[void]$stackPanel.Children.Add($checkBox2)
#[void]$stackPanel.Children.Add($checkBox3)
#[void]$stackPanel.Children.Add($checkBox4)
[void]$stackPanel.Children.Add($comboBox)
[void]$stackPanel.Children.Add($textBox)
[void]$stackPanel.Children.Add($button)

# Build a legend bar at the bottom so the user knows what each dot color next to a collection name means.
# A Border is used as the actual Grid child so it can stretch and paint the full row width;
# the inner StackPanel hosts the legend entries.
$legendBorder = New-Object System.Windows.Controls.Border
$legendBorder.Background = [System.Windows.Media.Brushes]::WhiteSmoke
$legendBorder.BorderBrush = [System.Windows.Media.Brushes]::LightGray
$legendBorder.BorderThickness = '0,1,0,0'
[System.Windows.Controls.Grid]::SetRow($legendBorder, 2)
[System.Windows.Controls.Grid]::SetColumn($legendBorder, 0)
[System.Windows.Controls.Grid]::SetColumnSpan($legendBorder, 5)

$legendPanel = New-Object System.Windows.Controls.StackPanel
$legendPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
$legendPanel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
$legendPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
$legendPanel.Margin = '10,0,10,0'
$legendBorder.Child = $legendPanel

$legendHeader = New-Object System.Windows.Controls.TextBlock
$legendHeader.Text = 'Legend:'
$legendHeader.FontWeight = [System.Windows.FontWeights]::Bold
$legendHeader.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
[void]$legendPanel.Children.Add($legendHeader)

$legendDefinitions = @(
    @{ Color = 'Green'   ; Label = 'Deployments' }
    @{ Color = 'Red'     ; Label = 'Permissions' }
    @{ Color = 'Blue'    ; Label = 'Incremental updates' }
    @{ Color = 'Coral'   ; Label = 'Include/Exclude rules' }
    @{ Color = 'Violet'  ; Label = 'Client settings' }
    @{ Color = 'DarkCyan'; Label = 'Maintenance windows' }
)

foreach($legend in $legendDefinitions)
{
    $legendEllipse = New-Object System.Windows.Shapes.Ellipse
    $legendEllipse.Width  = 10
    $legendEllipse.Height = 10
    $legendEllipse.Margin = '12,0,4,0'
    $legendEllipse.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $legendEllipse.Fill = [System.Windows.Media.Brushes]::($legend.Color)
    $legendEllipse.Stroke = [System.Windows.Media.Brushes]::Black
    $legendEllipse.StrokeThickness = 0.5
    [void]$legendPanel.Children.Add($legendEllipse)

    $legendText = New-Object System.Windows.Controls.TextBlock
    $legendText.Text = $legend.Label
    $legendText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [void]$legendPanel.Children.Add($legendText)
}


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
            if ($global:selectedCollection.CollectionRules | Where-Object {$_.QueryExpression -ne $null})
            {
                [array]$properties = $global:selectedCollection.CollectionRules | Where-Object {$_.QueryExpression -ne $null} | ForEach-Object {
                        [PSCustomObject]@{
                        RuleName = $_.RuleName
                        Query = $_.QueryExpression
                        }
            
                }
            }
            else
            {
                [array]$properties += [PSCustomObject]@{
                        RuleName = 'No query rules set'
                        Query = ''
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
[System.Windows.Controls.Grid]::SetColumn($dataGrid, 2)
[System.Windows.Controls.Grid]::SetRow($dataGrid, 1)

$dataGrid1 = New-Object System.Windows.Controls.DataGrid
$dataGrid1.IsReadOnly = $true
$dataGrid1.HeadersVisibility = "All"
$dataGrid1.AutoGenerateColumns = $true
[System.Windows.Controls.Grid]::SetColumn($dataGrid1, 4)
[System.Windows.Controls.Grid]::SetRow($dataGrid1, 1)


# Add the TreeView and data grid and checkbox to the main grid
#[void]$mainGrid.Children.Add($checkBox)
[void]$mainGrid.Children.Add($stackPanel)
[void]$mainGrid.Children.Add($treeView)
[void]$mainGrid.Children.Add($dataGrid)
[void]$mainGrid.Children.Add($dataGrid1)
[void]$mainGrid.Children.Add($legendBorder)

# GridSplitters between the three content boxes so the user can drag the dividers.
# - ResizeDirection=Columns is set explicitly so WPF cannot mistake the splitter
#   for a row splitter (the default 'Auto' can guess wrong when both alignments
#   are Stretch, which causes one splitter to appear to move the other).
# - ShowsPreview=$false makes the splitter commit immediately while dragging,
#   so there is no separate preview adorner that can render at the wrong spot.
$splitter1 = New-Object System.Windows.Controls.GridSplitter
$splitter1.Width = 5
$splitter1.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$splitter1.VerticalAlignment = [System.Windows.VerticalAlignment]::Stretch
$splitter1.Background = [System.Windows.Media.Brushes]::LightGray
$splitter1.ShowsPreview = $false
$splitter1.ResizeBehavior = [System.Windows.Controls.GridResizeBehavior]::PreviousAndNext
$splitter1.ResizeDirection = [System.Windows.Controls.GridResizeDirection]::Columns
[System.Windows.Controls.Grid]::SetColumn($splitter1, 1)
[System.Windows.Controls.Grid]::SetRow($splitter1, 1)
[System.Windows.Controls.Grid]::SetRowSpan($splitter1, 1)
[void]$mainGrid.Children.Add($splitter1)

$splitter2 = New-Object System.Windows.Controls.GridSplitter
$splitter2.Width = 5
$splitter2.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$splitter2.VerticalAlignment = [System.Windows.VerticalAlignment]::Stretch
$splitter2.Background = [System.Windows.Media.Brushes]::LightGray
$splitter2.ShowsPreview = $false
$splitter2.ResizeBehavior = [System.Windows.Controls.GridResizeBehavior]::PreviousAndNext
$splitter2.ResizeDirection = [System.Windows.Controls.GridResizeDirection]::Columns
[System.Windows.Controls.Grid]::SetColumn($splitter2, 3)
[System.Windows.Controls.Grid]::SetRow($splitter2, 1)
[System.Windows.Controls.Grid]::SetRowSpan($splitter2, 1)
[void]$mainGrid.Children.Add($splitter2)


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
    $item.Header = New-CollectionHeader -collection $collection
    $item.Tag = $collection

    [void]$collectionItems.add($collection.CollectionID, $item)
  
}

Write-Verbose "Build children lookup hashtable for fast tree building"
$childrenHashTable = @{}
$collectionList | Group-Object -Property LimitToCollectionID | ForEach-Object {
    if (-NOT([string]::IsNullOrEmpty($_.Name)))
    {
        $childrenHashTable[$_.Name] = @($_.Group | Sort-Object -Property Name)
    }
}

Write-Verbose "Add each collection item to treeview (iterative stack-based)"
$rootCollections = $collectionList.where({[string]::IsNullOrEmpty($_.LimitToCollectionID)}) | Sort-Object -Property Name

# Use a stack to avoid recursive function call overhead
$stack = [System.Collections.Generic.Stack[PSCustomObject]]::new()

foreach($collection in $rootCollections)
{
    $item = New-Object System.Windows.Controls.TreeViewItem
    $item.Header = New-CollectionHeader -collection $collection
    $item.Tag = $collection

    $subMembers = $childrenHashTable[($collection.CollectionID)]
    if ($subMembers)
    {
        $stack.Push([PSCustomObject]@{ Parent = $item; Children = $subMembers })
    }
    [void]$treeView.Items.Add($item)
}

# Process all children iteratively instead of recursively
while ($stack.Count -gt 0)
{
    $current = $stack.Pop()
    foreach ($subMember in $current.Children)
    {
        [void]$current.Parent.Items.Add(($collectionItems[($subMember.CollectionID)]))

        $grandChildren = $childrenHashTable[($subMember.CollectionID)]
        if ($grandChildren)
        {
            $stack.Push([PSCustomObject]@{ Parent = $collectionItems[($subMember.CollectionID)]; Children = $grandChildren })
        }
    }
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