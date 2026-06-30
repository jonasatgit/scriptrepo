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
   | v0.8    | WQL query view: pretty-printed/wrapped text, rule selector, Copy + Open-in-window buttons.    |
   | v0.9    | Replaced WQL rule drop-down with a ListBox above the query text for faster rule browsing.     |
   | v0.10   | Added MembershipRules property (query + include + exclude in one list, auto-selected on click).|
   | v0.11   | Removed slow upfront query-rule pre-load; rules are now lazy-loaded the first time a collection is selected.  |
   | v1.0    | First stable release. Renamed event-handler params off the automatic 'sender' variable.                        |
   | v1.1    | Membership pane is now a Type / ID / Name table instead of a flat list. ID populated for include/exclude only.|
   | v1.2    | Middle property grid now uses two explicit columns - removes the trailing empty column.                       |
   | v1.3    | Maintenance windows dot/legend changed from DarkCyan to Goldenrod for better contrast against Deployments.    |
   | v1.4    | Membership-row click now marks the current collection blue and the include/exclude source collection red.   |
   | v1.5    | Moved the GitHub link out of the window title into a clickable hyperlink in the bottom-right legend bar.       |
   | v1.6    | Added SaddleBrown dot + UsedAsIncludeExcludeCount property: collections used as include/exclude source by others.|
   | v1.7    | Added 'Show all dep. lines' and 'Show selected dep. lines' buttons that overlay include/exclude curves on the tree.|

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

$version = 'v1.7'

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
    # except 'Maintenance windows' which uses Goldenrod so it stays visually
    # distinct from both 'Client settings' (Violet) and 'Deployments' (Green).
    $dotDefinitions = @(
        @{ Test = ($collection.DeploymentCount -gt 0)                                              ; Color = 'Green'       ; Tip = "Deployments: $($collection.DeploymentCount)" }
        @{ Test = ($collection.AdminCount -gt 0)                                                   ; Color = 'Red'         ; Tip = "Admin permissions: $($collection.AdminCount)" }
        @{ Test = ($collection.CollectionRefreshType -in @('Incremental','Both'))                  ; Color = 'Blue'        ; Tip = "Incremental updates ($($collection.CollectionRefreshType))" }
        @{ Test = ((($collection.IncludeCollectionsCount) + ($collection.ExcludeCollectionsCount)) -gt 0) ; Color = 'Coral'       ; Tip = "Include: $($collection.IncludeCollectionsCount) / Exclude: $($collection.ExcludeCollectionsCount)" }
        @{ Test = ($collection.UsedAsIncludeExcludeCount -gt 0)                                    ; Color = 'SaddleBrown' ; Tip = "Used as include/exclude source by $($collection.UsedAsIncludeExcludeCount) collection(s)" }
        @{ Test = ($collection.ClientSettingsCount -gt 0)                                          ; Color = 'Violet'      ; Tip = "Client setting deployments: $($collection.ClientSettingsCount)" }
        @{ Test = ($collection.ServiceWindowsCount -gt 0)                                          ; Color = 'Goldenrod'   ; Tip = "Maintenance windows: $($collection.ServiceWindowsCount)" }
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

#region Format-WqlQuery
<#
.Synopsis
   Format-WqlQuery
.DESCRIPTION
   Lightly pretty-prints a WQL/SQL query by collapsing whitespace, putting major
   keywords (SELECT, FROM, WHERE, JOIN, ORDER BY, ...) on their own line and
   indenting AND/OR continuations. Casing of the original keywords is preserved.
#>
function Format-WqlQuery
{
    param
    (
        [string]$query
    )

    if ([string]::IsNullOrWhiteSpace($query)) { return $query }

    # Collapse any run of whitespace into single spaces first.
    $q = ($query -replace '\s+', ' ').Trim()

    # Major keywords that should start a new line. Order matters: more specific
    # multi-word variants must come before their single-word prefixes so the
    # regex alternation matches the longest one first.
    $mainKeywords = @(
        'SELECT','FROM','WHERE',
        'GROUP\s+BY','ORDER\s+BY','HAVING',
        'UNION\s+ALL','UNION',
        'INNER\s+JOIN',
        'LEFT\s+OUTER\s+JOIN','LEFT\s+JOIN',
        'RIGHT\s+OUTER\s+JOIN','RIGHT\s+JOIN',
        'FULL\s+OUTER\s+JOIN','FULL\s+JOIN',
        'JOIN'
    )
    $pattern = '(?i)\s*\b(' + ($mainKeywords -join '|') + ')\b\s*'
    $q = [regex]::Replace($q, $pattern, { "`n" + (($args[0].Groups[1].Value) -replace '\s+', ' ') + ' ' })

    # Put AND / OR on their own line, indented under the WHERE/ON clause.
    $q = [regex]::Replace($q, '(?i)\s+\b(AND|OR)\b\s+', { "`n    " + $args[0].Groups[1].Value + ' ' })

    return $q.Trim()
}
#endregion

#region Show-WqlQueryWindow
<#
.Synopsis
   Show-WqlQueryWindow
.DESCRIPTION
   Opens a resizable WPF window showing a WQL/SQL query in a large word-wrapping,
   monospaced read-only text box plus Copy and Close buttons.
#>
function Show-WqlQueryWindow
{
    param
    (
        [string]$title,
        [string]$query
    )

    $w = New-Object System.Windows.Window
    $w.Title  = "WQL Query - $title"
    $w.Width  = 900
    $w.Height = 600

    $g = New-Object System.Windows.Controls.Grid
    $g.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
    $g.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
    $g.RowDefinitions[0].Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $g.RowDefinitions[1].Height = [System.Windows.GridLength]::Auto

    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = $query
    $tb.IsReadOnly = $true
    $tb.AcceptsReturn = $true
    $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $tb.VerticalScrollBarVisibility   = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $tb.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
    $tb.FontSize = 12
    $tb.Margin = '10,10,10,0'
    [System.Windows.Controls.Grid]::SetRow($tb, 0)
    [void]$g.Children.Add($tb)

    $bp = New-Object System.Windows.Controls.StackPanel
    $bp.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $bp.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $bp.Margin = '10'
    [System.Windows.Controls.Grid]::SetRow($bp, 1)

    $copy = New-Object System.Windows.Controls.Button
    $copy.Content = 'Copy to clipboard'
    $copy.Padding = '10,4'
    $copy.Margin  = '0,0,8,0'
    $copy.Add_Click({ [System.Windows.Clipboard]::SetText($tb.Text) }.GetNewClosure())
    [void]$bp.Children.Add($copy)

    $close = New-Object System.Windows.Controls.Button
    $close.Content = 'Close'
    $close.Padding = '10,4'
    $close.Add_Click({ $w.Close() }.GetNewClosure())
    [void]$bp.Children.Add($close)

    [void]$g.Children.Add($bp)

    $w.Content = $g
    [void]$w.ShowDialog()
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


# Build a reverse lookup: for each collection, which other collections use it
# as the source of an include or exclude rule. Keyed by SourceCollectionID,
# value is an array of [PSCustomObject]@{ Type; CollectionID; CollectionName }.
$usedAsSourceHashTable = @{}
foreach($dep in $includeCollectionListClean)
{
    if (-not $usedAsSourceHashTable.ContainsKey($dep.SourceCollectionID))
    {
        $usedAsSourceHashTable[$dep.SourceCollectionID] = New-Object System.Collections.Generic.List[object]
    }
    $usedAsSourceHashTable[$dep.SourceCollectionID].Add([PSCustomObject]@{
        Type           = 'Include'
        CollectionID   = $dep.DependentCollectionID
        CollectionName = $collectionHashTable[$dep.DependentCollectionID]
    })
}
foreach($dep in $excludeCollectionListClean)
{
    if (-not $usedAsSourceHashTable.ContainsKey($dep.SourceCollectionID))
    {
        $usedAsSourceHashTable[$dep.SourceCollectionID] = New-Object System.Collections.Generic.List[object]
    }
    $usedAsSourceHashTable[$dep.SourceCollectionID].Add([PSCustomObject]@{
        Type           = 'Exclude'
        CollectionID   = $dep.DependentCollectionID
        CollectionName = $collectionHashTable[$dep.DependentCollectionID]
    })
}


# Cache for collection query rules. CollectionRules is a lazy WMI property and
# fetching it for every collection at startup is too slow on big environments.
# Instead, populate this hashtable on-demand the first time the user selects a
# collection (see the TreeView SelectedItemChanged handler below).
$queryRulesHashTable = @{}


$propertyList = ('MembershipRules',
    'CollectionID',
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
    'UsedAsIncludeExcludeCount',
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
$window.Title = "$($version) TreeView of $($global:collectionList.count) collections"
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


# v1.7: Buttons to overlay include/exclude dependency lines on the TreeView.
# Defined here so they exist before being added to the toolbar StackPanel below.
# Click handlers are wired further down, after the TreeView and overlay canvas
# have been created.
$showAllDepsButton = New-Object System.Windows.Controls.Button
$showAllDepsButton.Margin  = '10,10,2,10'
$showAllDepsButton.Padding = '8,0'
$showAllDepsButton.Height  = 22
$showAllDepsButton.Content = 'Show all dep. lines'

$showSelDepsButton = New-Object System.Windows.Controls.Button
$showSelDepsButton.Margin  = '2,10,10,10'
$showSelDepsButton.Padding = '8,0'
$showSelDepsButton.Height  = 22
$showSelDepsButton.Content = 'Show selected dep. lines'


# Add the CheckBoxes to the StackPanel
#[void]$stackPanel.Children.Add($checkBox)
#[void]$stackPanel.Children.Add($checkBox2)
#[void]$stackPanel.Children.Add($checkBox3)
#[void]$stackPanel.Children.Add($checkBox4)
[void]$stackPanel.Children.Add($comboBox)
[void]$stackPanel.Children.Add($textBox)
[void]$stackPanel.Children.Add($button)
[void]$stackPanel.Children.Add($showAllDepsButton)
[void]$stackPanel.Children.Add($showSelDepsButton)

# Build a legend bar at the bottom so the user knows what each dot color next to a collection name means.
# A Border is used as the actual Grid child so it can stretch and paint the full row width;
# inside the border a DockPanel holds the legend entries on the left and a
# clickable GitHub link in the bottom-right corner.
$legendBorder = New-Object System.Windows.Controls.Border
$legendBorder.Background = [System.Windows.Media.Brushes]::WhiteSmoke
$legendBorder.BorderBrush = [System.Windows.Media.Brushes]::LightGray
$legendBorder.BorderThickness = '0,1,0,0'
[System.Windows.Controls.Grid]::SetRow($legendBorder, 2)
[System.Windows.Controls.Grid]::SetColumn($legendBorder, 0)
[System.Windows.Controls.Grid]::SetColumnSpan($legendBorder, 5)

$legendDock = New-Object System.Windows.Controls.DockPanel
$legendDock.LastChildFill = $false
$legendBorder.Child = $legendDock

$legendPanel = New-Object System.Windows.Controls.StackPanel
$legendPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
$legendPanel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
$legendPanel.Margin = '10,0,10,0'
[System.Windows.Controls.DockPanel]::SetDock($legendPanel, [System.Windows.Controls.Dock]::Left)
[void]$legendDock.Children.Add($legendPanel)

$legendHeader = New-Object System.Windows.Controls.TextBlock
$legendHeader.Text = 'Legend:'
$legendHeader.FontWeight = [System.Windows.FontWeights]::Bold
$legendHeader.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
[void]$legendPanel.Children.Add($legendHeader)

$legendDefinitions = @(
    @{ Color = 'Green'    ; Label = 'Deployments' }
    @{ Color = 'Red'      ; Label = 'Permissions' }
    @{ Color = 'Blue'     ; Label = 'Incremental updates' }
    @{ Color = 'Coral'    ; Label = 'Include/Exclude rules' }
    @{ Color = 'SaddleBrown'; Label = 'Used as include/exclude' }
    @{ Color = 'Violet'   ; Label = 'Client settings' }
    @{ Color = 'Goldenrod'; Label = 'Maintenance windows' }
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

# Clickable GitHub link in the bottom-right corner of the legend bar.
$repoUrl = 'https://github.com/jonasatgit/scriptrepo/tree/master/Collections'
$linkTextBlock = New-Object System.Windows.Controls.TextBlock
$linkTextBlock.VerticalAlignment   = [System.Windows.VerticalAlignment]::Center
$linkTextBlock.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
$linkTextBlock.Margin              = '10,0,12,0'
[System.Windows.Controls.DockPanel]::SetDock($linkTextBlock, [System.Windows.Controls.Dock]::Right)

$hyperlink = New-Object System.Windows.Documents.Hyperlink
$hyperlink.NavigateUri = [Uri]$repoUrl
$hyperlink.ToolTip     = $repoUrl
[void]$hyperlink.Inlines.Add($repoUrl)
$hyperlink.Add_RequestNavigate({
    Start-Process $_.Uri.AbsoluteUri
    $_.Handled = $true
}.GetNewClosure())
[void]$linkTextBlock.Inlines.Add($hyperlink)

[void]$legendDock.Children.Add($linkTextBlock)


# Create the TreeView and set properties
$treeView = New-Object System.Windows.Controls.TreeView
$treeView.Add_SelectedItemChanged({
    param($src, $e)

    # Update the data grid with the selected item data
    $selectedItem = $e.NewValue
    $global:selectedCollection = $selectedItem.Tag

    # Reset any previous red/blue highlight from the last membership-row click
    # so a fresh tree selection starts on a clean slate. The membership-row
    # selection handler will re-apply the blue marker for this collection.
    if ($global:collectionItems)
    {
        foreach($tvi in $global:collectionItems.Values)
        {
            $tvi.Foreground = [System.Windows.Media.Brushes]::Black
        }
    }

    if ($selectedItem -ne $null) {

        # Lazy load the query rules for the selected collection (once per
        # collection) so the script's initial startup is fast.
        $coll = $selectedItem.Tag
        if (-not $queryRulesHashTable.ContainsKey($coll.CollectionID))
        {
            try
            {
                $collWithRules = $coll | Get-CimInstance -ErrorAction Stop
                $rules = @($collWithRules.CollectionRules | Where-Object { $_.QueryExpression -ne $null })
                $queryRulesHashTable[$coll.CollectionID] = $rules
            }
            catch
            {
                # Cache empty array so we don't retry every click on failure.
                $queryRulesHashTable[$coll.CollectionID] = @()
            }

            # Now that we have the real count, refresh the property values on
            # the collection object so the data grid displays accurate numbers.
            $queryRulesCount = $queryRulesHashTable[$coll.CollectionID].Count
            $coll.QueryRules      = $queryRulesCount
            $coll.MembershipRules = $queryRulesCount + [int]$coll.IncludeCollectionsCount + [int]$coll.ExcludeCollectionsCount
        }

        $properties = $selectedItem.Tag | Select-Object -Property $propertyList | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        $rows = $properties | ForEach-Object {
            [PSCustomObject]@{
                Property = $_
                Value = $selectedItem.Tag.$_
            }
        }
        $dataGrid.ItemsSource = $rows

        # Auto-select the MembershipRules row so the user immediately sees the
        # combined list of query rules + include/exclude collections.
        $membershipRow = $rows | Where-Object { $_.Property -eq 'MembershipRules' } | Select-Object -First 1
        if ($membershipRow)
        {
            $dataGrid.SelectedItem = $membershipRow
        }
    } else {
        $dataGrid.ItemsSource = $null
    }
})
[System.Windows.Controls.Grid]::SetColumn($treeView, 0)
[System.Windows.Controls.Grid]::SetRow($treeView, 1)


# v1.7: Transparent overlay canvas placed in the same Grid cell as the TreeView.
# IsHitTestVisible=$false makes mouse clicks pass straight through to the
# TreeView underneath so selection, query loading and all existing handlers
# keep working unchanged. ClipToBounds keeps off-screen line segments hidden.
$depCanvas = New-Object System.Windows.Controls.Canvas
$depCanvas.IsHitTestVisible = $false
$depCanvas.Background       = [System.Windows.Media.Brushes]::Transparent
$depCanvas.ClipToBounds     = $true
[System.Windows.Controls.Grid]::SetColumn($depCanvas, 0)
[System.Windows.Controls.Grid]::SetRow($depCanvas, 1)


# Recursively expand every TreeViewItem so all rows referenced by an
# include/exclude pair are guaranteed to be laid out and visible.
function Expand-AllTreeViewItems
{
    param($items)
    foreach($item in $items)
    {
        $item.IsExpanded = $true
        if ($item.Items.Count -gt 0)
        {
            Expand-AllTreeViewItems -items $item.Items
        }
    }
}


# Draw a set of include/exclude dependency pairs as curved arrows on $depCanvas.
# Each $pair must expose SourceCollectionID, DependentCollectionID and Type
# ('Include' or 'Exclude'). The canvas is cleared first.
function Show-CollectionDependencyLines
{
    param($pairs)

    $depCanvas.Children.Clear()
    if (-not $pairs) { return }

    foreach($pair in $pairs)
    {
        $srcItem = $global:collectionItems[$pair.SourceCollectionID]
        $dstItem = $global:collectionItems[$pair.DependentCollectionID]
        if (-not $srcItem -or -not $dstItem) { continue }

        # Use the visual header (the StackPanel built by New-CollectionHeader)
        # when available so coordinates line up with the actual collection name.
        $srcEl = if ($srcItem.Header -is [System.Windows.UIElement]) { $srcItem.Header } else { $srcItem }
        $dstEl = if ($dstItem.Header -is [System.Windows.UIElement]) { $dstItem.Header } else { $dstItem }

        try
        {
            $srcP = $srcEl.TranslatePoint([System.Windows.Point]::new(0, 0), $depCanvas)
            $dstP = $dstEl.TranslatePoint([System.Windows.Point]::new(0, 0), $depCanvas)
        }
        catch
        {
            continue
        }

        $srcH = if ($srcEl.ActualHeight -gt 0) { $srcEl.ActualHeight } else { 18 }
        $dstH = if ($dstEl.ActualHeight -gt 0) { $dstEl.ActualHeight } else { 18 }
        $srcW = $srcEl.ActualWidth
        $dstW = $dstEl.ActualWidth

        $srcY     = $srcP.Y + ($srcH / 2)
        $dstY     = $dstP.Y + ($dstH / 2)
        $srcEdgeX = $srcP.X + $srcW + 4
        $dstEdgeX = $dstP.X + $dstW + 4

        # Right-side gutter where both Bezier control points sit so the curve
        # sweeps out into empty space to the right of the names.
        $gutter = [Math]::Max($srcEdgeX, $dstEdgeX) + 30
        if ($depCanvas.ActualWidth -gt 0 -and $gutter -gt ($depCanvas.ActualWidth - 10))
        {
            $gutter = $depCanvas.ActualWidth - 10
        }

        $figure = New-Object System.Windows.Media.PathFigure
        $figure.StartPoint = [System.Windows.Point]::new($srcEdgeX, $srcY)
        $figure.IsClosed   = $false
        $bz = New-Object System.Windows.Media.BezierSegment
        $bz.Point1 = [System.Windows.Point]::new($gutter, $srcY)
        $bz.Point2 = [System.Windows.Point]::new($gutter, $dstY)
        $bz.Point3 = [System.Windows.Point]::new($dstEdgeX, $dstY)
        [void]$figure.Segments.Add($bz)
        $geo = New-Object System.Windows.Media.PathGeometry
        [void]$geo.Figures.Add($figure)

        $path = New-Object System.Windows.Shapes.Path
        $path.Data            = $geo
        $path.StrokeThickness = 1.5
        if ($pair.Type -eq 'Include')
        {
            $path.Stroke = [System.Windows.Media.Brushes]::Green
        }
        else
        {
            $path.Stroke          = [System.Windows.Media.Brushes]::Red
            $path.StrokeDashArray = New-Object System.Windows.Media.DoubleCollection(@(4.0, 3.0))
        }
        [void]$depCanvas.Children.Add($path)

        # Arrow head pointing at the dependent collection row.
        $arrow = New-Object System.Windows.Shapes.Polygon
        $arrow.Points = New-Object System.Windows.Media.PointCollection
        [void]$arrow.Points.Add([System.Windows.Point]::new($dstEdgeX,     $dstY))
        [void]$arrow.Points.Add([System.Windows.Point]::new($dstEdgeX - 8, $dstY - 4))
        [void]$arrow.Points.Add([System.Windows.Point]::new($dstEdgeX - 8, $dstY + 4))
        $arrow.Fill = $path.Stroke
        [void]$depCanvas.Children.Add($arrow)
    }
}


# 'Show all dep. lines': expand the whole tree, then draw every include and
# exclude relationship in the environment.
$showAllDepsButton.Add_Click({
    Expand-AllTreeViewItems -items $treeView.Items

    $allPairs = New-Object System.Collections.Generic.List[object]
    foreach($p in $includeCollectionListClean)
    {
        $allPairs.Add([PSCustomObject]@{
            SourceCollectionID    = $p.SourceCollectionID
            DependentCollectionID = $p.DependentCollectionID
            Type                  = 'Include'
        })
    }
    foreach($p in $excludeCollectionListClean)
    {
        $allPairs.Add([PSCustomObject]@{
            SourceCollectionID    = $p.SourceCollectionID
            DependentCollectionID = $p.DependentCollectionID
            Type                  = 'Exclude'
        })
    }

    # Defer drawing until the layout pass triggered by the expansion is done,
    # otherwise TranslatePoint returns stale coordinates.
    [void]$window.Dispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [Action]{ Show-CollectionDependencyLines -pairs $allPairs })
})


# 'Show selected dep. lines': only draw include/exclude lines that touch the
# currently selected collection (as source OR dependent).
$showSelDepsButton.Add_Click({
    if (-not $global:selectedCollection)
    {
        $depCanvas.Children.Clear()
        return
    }
    $cid = $global:selectedCollection.CollectionID

    Expand-AllTreeViewItems -items $treeView.Items

    $pairs = New-Object System.Collections.Generic.List[object]
    foreach($p in $includeCollectionListClean)
    {
        if ($p.SourceCollectionID -eq $cid -or $p.DependentCollectionID -eq $cid)
        {
            $pairs.Add([PSCustomObject]@{
                SourceCollectionID    = $p.SourceCollectionID
                DependentCollectionID = $p.DependentCollectionID
                Type                  = 'Include'
            })
        }
    }
    foreach($p in $excludeCollectionListClean)
    {
        if ($p.SourceCollectionID -eq $cid -or $p.DependentCollectionID -eq $cid)
        {
            $pairs.Add([PSCustomObject]@{
                SourceCollectionID    = $p.SourceCollectionID
                DependentCollectionID = $p.DependentCollectionID
                Type                  = 'Exclude'
            })
        }
    }

    [void]$window.Dispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [Action]{ Show-CollectionDependencyLines -pairs $pairs })
})


# Whenever any TreeViewItem is collapsed, clear the overlay so we never have
# lines pointing to rows that are no longer visible.
$treeView.AddHandler(
    [System.Windows.Controls.TreeViewItem]::CollapsedEvent,
    [System.Windows.RoutedEventHandler]{ $depCanvas.Children.Clear() })


Write-Verbose "Create the data grid and set properties"
$dataGrid = New-Object System.Windows.Controls.DataGrid
$dataGrid.IsReadOnly = $true
$dataGrid.HeadersVisibility = 'Column'
$dataGrid.AutoGenerateColumns = $false
$dataGrid.CanUserAddRows    = $false
$dataGrid.CanUserDeleteRows = $false

# Two explicit columns - Property (sized to header) and Value (fills the rest).
# Using explicit columns instead of auto-generation removes the trailing empty
# space that previously looked like a third blank column.
$col = New-Object System.Windows.Controls.DataGridTextColumn
$col.Header  = 'Property'
$col.Binding = New-Object System.Windows.Data.Binding('Property')
$col.Width   = [System.Windows.Controls.DataGridLength]::SizeToCells
[void]$dataGrid.Columns.Add($col)

$col = New-Object System.Windows.Controls.DataGridTextColumn
$col.Header  = 'Value'
$col.Binding = New-Object System.Windows.Data.Binding('Value')
$col.Width   = New-Object System.Windows.Controls.DataGridLength(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
[void]$dataGrid.Columns.Add($col)

$dataGrid.Add_SelectionChanged({
    param($src, $e)

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
        'UsedAsIncludeExcludeCount'
        {
            [array]$properties = $global:selectedCollection.UsedAsIncludeExclude | Sort-Object Type, CollectionName
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
            $rules = @($queryRulesHashTable[$global:selectedCollection.CollectionID])
            if (-not $rules) { $rules = @() }

            $queryTextBox.Text = ''
            if ($rules.Count -gt 0)
            {
                [array]$gridRows = $rules | ForEach-Object {
                    [PSCustomObject]@{
                        Type = 'Query'
                        ID   = ''
                        Name = $_.RuleName
                        Wql  = (Format-WqlQuery -query $_.QueryExpression)
                    }
                }
                $queryRuleList.ItemsSource = $gridRows
                $queryRuleList.SelectedIndex = 0
            }
            else
            {
                $queryRuleList.ItemsSource = @()
                $queryTextBox.Text = '-- No query rules set --'
            }
        }
        'MembershipRules'
        {
            # Combined list of query rules + include collections + exclude collections.
            $rules = @($queryRulesHashTable[$global:selectedCollection.CollectionID])
            if (-not $rules) { $rules = @() }

            $queryTextBox.Text = ''

            $gridRows = [System.Collections.Generic.List[object]]::new()

            foreach($rule in $rules)
            {
                $gridRows.Add([PSCustomObject]@{
                    Type = 'Query'
                    ID   = ''
                    Name = $rule.RuleName
                    Wql  = (Format-WqlQuery -query $rule.QueryExpression)
                })
            }

            if ([int]$global:selectedCollection.IncludeCollectionsCount -gt 0)
            {
                foreach($inc in @($global:selectedCollection.IncludeCollections))
                {
                    if (-not $inc) { continue }
                    $gridRows.Add([PSCustomObject]@{
                        Type = 'Include'
                        ID   = $inc.SourceCollectionID
                        Name = $inc.SourceCollectionName
                        Wql  = $null
                    })
                }
            }

            if ([int]$global:selectedCollection.ExcludeCollectionsCount -gt 0)
            {
                foreach($exc in @($global:selectedCollection.ExcludeCollections))
                {
                    if (-not $exc) { continue }
                    $gridRows.Add([PSCustomObject]@{
                        Type = 'Exclude'
                        ID   = $exc.SourceCollectionID
                        Name = $exc.SourceCollectionName
                        Wql  = $null
                    })
                }
            }

            $queryRuleList.ItemsSource = $gridRows

            if ($gridRows.Count -gt 0)
            {
                $queryRuleList.SelectedIndex = 0
            }
            else
            {
                $queryTextBox.Text = '-- No membership rules set --'
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

    # Swap between the regular details grid and the dedicated WQL query view.
    if ($selectedItem -and ($selectedItem.Property -eq 'QueryRules' -or $selectedItem.Property -eq 'MembershipRules'))
    {
        $dataGrid1.Visibility      = [System.Windows.Visibility]::Collapsed
        $queryViewPanel.Visibility = [System.Windows.Visibility]::Visible
    }
    else
    {
        $dataGrid1.Visibility      = [System.Windows.Visibility]::Visible
        $queryViewPanel.Visibility = [System.Windows.Visibility]::Collapsed
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

# WQL query view panel: shown in column 4 instead of $dataGrid1 when the user
# clicks the 'QueryRules' row in the middle properties grid.
# Layout:
#   row 0 - ListBox with the rule names (click one to view its query below)
#   row 1 - toolbar with Copy / Open-in-window buttons
#   row 2 - read-only, word-wrapping TextBox showing the pretty-printed query
$queryViewPanel = New-Object System.Windows.Controls.Grid
$queryViewPanel.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$queryViewPanel.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$queryViewPanel.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$queryViewPanel.RowDefinitions[0].Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
$queryViewPanel.RowDefinitions[1].Height = [System.Windows.GridLength]::Auto
$queryViewPanel.RowDefinitions[2].Height = [System.Windows.GridLength]::new(2, [System.Windows.GridUnitType]::Star)
$queryViewPanel.Visibility = [System.Windows.Visibility]::Collapsed
[System.Windows.Controls.Grid]::SetColumn($queryViewPanel, 4)
[System.Windows.Controls.Grid]::SetRow($queryViewPanel, 1)

# Row 0: table of membership entries (query rules + include + exclude collections)
# A DataGrid with three columns - Type / ID / Name - replaces the older flat
# ListBox. The 'Wql' property on each row holds the formatted query text and is
# read by the selection handler; it is intentionally not added as a visible
# column.
$queryRuleList = New-Object System.Windows.Controls.DataGrid
$queryRuleList.Margin = '4,4,4,2'
$queryRuleList.AutoGenerateColumns = $false
$queryRuleList.IsReadOnly           = $true
$queryRuleList.HeadersVisibility    = 'Column'
$queryRuleList.SelectionMode        = 'Single'
$queryRuleList.SelectionUnit        = 'FullRow'
$queryRuleList.CanUserAddRows       = $false
$queryRuleList.CanUserDeleteRows    = $false

$col = New-Object System.Windows.Controls.DataGridTextColumn
$col.Header = 'Type'
$col.Binding = New-Object System.Windows.Data.Binding('Type')
$col.Width   = [System.Windows.Controls.DataGridLength]::SizeToCells
[void]$queryRuleList.Columns.Add($col)

$col = New-Object System.Windows.Controls.DataGridTextColumn
$col.Header = 'ID'
$col.Binding = New-Object System.Windows.Data.Binding('ID')
$col.Width   = [System.Windows.Controls.DataGridLength]::SizeToCells
[void]$queryRuleList.Columns.Add($col)

$col = New-Object System.Windows.Controls.DataGridTextColumn
$col.Header = 'Name'
$col.Binding = New-Object System.Windows.Data.Binding('Name')
$col.Width   = New-Object System.Windows.Controls.DataGridLength(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
[void]$queryRuleList.Columns.Add($col)

$queryRuleList.Add_SelectionChanged({
    if ($queryRuleList.SelectedItem)
    {
        if ($queryRuleList.SelectedItem.Wql)
        {
            $queryTextBox.Text = [string]$queryRuleList.SelectedItem.Wql
        }
        else
        {
            # Include / exclude entries have no WQL - clear the text box.
            $queryTextBox.Text = ''
        }

        # Highlight the related collections in the treeview to make include /
        # exclude dependencies easy to spot:
        #   - Blue: the currently selected collection
        #   - Red : the source collection of the selected include / exclude row
        if ($global:collectionItems)
        {
            foreach($tvi in $global:collectionItems.Values)
            {
                $tvi.Foreground = [System.Windows.Media.Brushes]::Black
            }

            if ($global:selectedCollection -and $global:collectionItems.ContainsKey($global:selectedCollection.CollectionID))
            {
                $global:collectionItems[$global:selectedCollection.CollectionID].Foreground = [System.Windows.Media.Brushes]::Blue
            }

            $row = $queryRuleList.SelectedItem
            if ($row -and ($row.Type -eq 'Include' -or $row.Type -eq 'Exclude') -and $row.ID)
            {
                $srcId = [string]$row.ID
                if ($global:collectionItems.ContainsKey($srcId))
                {
                    $global:collectionItems[$srcId].Foreground = [System.Windows.Media.Brushes]::Red
                }
            }
        }
    }
})
[System.Windows.Controls.Grid]::SetRow($queryRuleList, 0)
[void]$queryViewPanel.Children.Add($queryRuleList)

# Row 1: toolbar with Copy / Open-in-window buttons
$queryToolbar = New-Object System.Windows.Controls.StackPanel
$queryToolbar.Orientation = [System.Windows.Controls.Orientation]::Horizontal
$queryToolbar.Margin = '4,2,4,2'
[System.Windows.Controls.Grid]::SetRow($queryToolbar, 1)

$queryCopyButton = New-Object System.Windows.Controls.Button
$queryCopyButton.Content = 'Copy'
$queryCopyButton.Padding = '8,2'
$queryCopyButton.Margin  = '0,0,4,0'
$queryCopyButton.ToolTip = 'Copy the query to the clipboard'
$queryCopyButton.Add_Click({
    if (-not [string]::IsNullOrEmpty($queryTextBox.Text))
    {
        [System.Windows.Clipboard]::SetText($queryTextBox.Text)
    }
})
[void]$queryToolbar.Children.Add($queryCopyButton)

$queryOpenButton = New-Object System.Windows.Controls.Button
$queryOpenButton.Content = 'Open in window'
$queryOpenButton.Padding = '8,2'
$queryOpenButton.ToolTip = 'Show the query in a bigger, resizable window'
$queryOpenButton.Add_Click({
    if (-not [string]::IsNullOrEmpty($queryTextBox.Text))
    {
        $popupTitle = if ($queryRuleList.SelectedItem) { [string]$queryRuleList.SelectedItem.Name } else { 'WQL Query' }
        Show-WqlQueryWindow -title $popupTitle -query $queryTextBox.Text
    }
})
[void]$queryToolbar.Children.Add($queryOpenButton)

[void]$queryViewPanel.Children.Add($queryToolbar)

# Row 2: the query text
$queryTextBox = New-Object System.Windows.Controls.TextBox
$queryTextBox.IsReadOnly = $true
$queryTextBox.AcceptsReturn = $true
$queryTextBox.TextWrapping = [System.Windows.TextWrapping]::Wrap
$queryTextBox.VerticalScrollBarVisibility   = [System.Windows.Controls.ScrollBarVisibility]::Auto
$queryTextBox.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
$queryTextBox.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
$queryTextBox.FontSize = 12
$queryTextBox.Margin = '4,2,4,4'
[System.Windows.Controls.Grid]::SetRow($queryTextBox, 2)
[void]$queryViewPanel.Children.Add($queryTextBox)


# Add the TreeView and data grid and checkbox to the main grid
#[void]$mainGrid.Children.Add($checkBox)
[void]$mainGrid.Children.Add($stackPanel)
[void]$mainGrid.Children.Add($treeView)
[void]$mainGrid.Children.Add($depCanvas)
[void]$mainGrid.Children.Add($dataGrid)
[void]$mainGrid.Children.Add($dataGrid1)
[void]$mainGrid.Children.Add($queryViewPanel)
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

    # Reverse dependency: collections that use THIS collection as the source of
    # one of their include or exclude rules.
    $usedAsSource = $usedAsSourceHashTable[$collection.CollectionID]
    $collection | Add-Member -MemberType NoteProperty -Name UsedAsIncludeExclude      -Value $usedAsSource
    $collection | Add-Member -MemberType NoteProperty -Name UsedAsIncludeExcludeCount -Value ([int]$usedAsSource.Count)

    $collection | Add-Member -MemberType NoteProperty -Name Admins -value $adminHashTable[($collection.CollectionID)] 
    $collection | Add-Member -MemberType NoteProperty -Name AdminCount -Value $collection.Admins.Count

    # Query rules are loaded on demand. We initialise the count to '?' so the
    # property grid shows a clear placeholder. The treeview SelectedItemChanged
    # handler will replace it with the real count the first time the user picks
    # this collection.
    $collection | Add-Member -MemberType NoteProperty -Name QueryRules -Value '?'

    # MembershipRules holds at minimum the include + exclude collection counts;
    # the query-rule count is added once it is loaded on demand.
    $membershipCount = [int]$collection.IncludeCollectionsCount + [int]$collection.ExcludeCollectionsCount
    $collection | Add-Member -MemberType NoteProperty -Name MembershipRules -Value "$($membershipCount) + ?"


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