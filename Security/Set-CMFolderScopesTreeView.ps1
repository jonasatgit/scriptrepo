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
    WPF tree-view tool to add or remove ConfigMgr security scopes on console folders (and their subfolders).

.DESCRIPTION
    Shows a WPF window with three panes, modeled on Get-ConfigMgrCollectionTreeView.ps1:

      - Left   : a tree view of every ConfigMgr console folder, grouped under a root node per folder
                 type (DeviceCollection, UserCollection, Application, Package, TaskSequence, ...).
      - Middle : a list of all security scopes in the site, each with a check box that reflects whether
                 the scope is currently set on the selected folder.
      - Right  : the list of pending changes. Unchecking a currently set scope queues a "Remove <name>";
                 checking a not-set scope queues an "Add <name>".

    Below the pending list are two buttons:
      - "Set for this folder only"      : applies the pending add/remove changes to the selected folder.
      - "Set for this and sub-folders"  : applies them to the selected folder AND every folder below it.

    The buttons only add or remove the scopes listed as pending changes. They do NOT replace the full
    scope set of a folder, so scopes that were not touched stay exactly as they are (no inheritance-style
    overwrite).

    Folders are read from the SMS_ObjectContainerNode WMI class. Scopes are read/changed via the
    Get-CMObjectSecurityScope / Add-CMObjectSecurityScope / Remove-CMObjectSecurityScope cmdlets against
    the folder object returned by Get-CMFolder.

    Note: a securable object must always keep at least one security scope. Removing the last remaining
    scope of a folder will fail; the script reports this per folder and continues.

.PARAMETER SiteCode
    ConfigMgr site code. Auto-detected from the local SMS provider if omitted.

.PARAMETER ProviderMachineName
    SMS Provider machine name. Auto-detected from the local SMS provider if omitted.

.EXAMPLE
    .\Set-CMFolderScopesTreeView.ps1

    Auto-detects the site code and provider from the local machine and opens the UI.

.EXAMPLE
    .\Set-CMFolderScopesTreeView.ps1 -SiteCode 'P01' -ProviderMachineName 'CM01.contoso.local'

    Opens the UI against the specified site and provider.

.LINK
    https://github.com/jonasatgit/scriptrepo
#>
[CmdletBinding()]
param
(
    [string]$SiteCode,
    [string]$ProviderMachineName
)

$version = 'v1.0'


# -------------------------------------------------------------------------------------------------
# Auto-detect SiteCode / ProviderMachineName from the local SMS provider if not passed in.
# -------------------------------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($ProviderMachineName) -or [string]::IsNullOrWhiteSpace($SiteCode))
{
    Write-Host "Auto-detecting SMS provider from local WMI (root\SMS -> SMS_ProviderLocation)" -ForegroundColor Green
    try
    {
        $providerLocation = Get-CimInstance -Namespace 'root\SMS' -Query 'SELECT * FROM SMS_ProviderLocation WHERE ProviderForLocalSite = 1' -ErrorAction Stop | Select-Object -First 1
    }
    catch
    {
        Write-Host "Could not query SMS_ProviderLocation from root\SMS on the local machine: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Pass -SiteCode and -ProviderMachineName explicitly." -ForegroundColor Yellow
        return
    }

    if (-not $providerLocation)
    {
        Write-Host "SMS_ProviderLocation returned no entries. Pass -SiteCode and -ProviderMachineName explicitly." -ForegroundColor Yellow
        return
    }

    if ([string]::IsNullOrWhiteSpace($ProviderMachineName)) { $ProviderMachineName = $providerLocation.Machine }
    if ([string]::IsNullOrWhiteSpace($SiteCode))            { $SiteCode            = $providerLocation.SiteCode }

    Write-Host "Using ProviderMachineName='$ProviderMachineName' and SiteCode='$SiteCode'" -ForegroundColor Green
}


# -------------------------------------------------------------------------------------------------
# Import the ConfigurationManager module and connect the site drive (needed for the Get/Add/Remove
# -CMObjectSecurityScope and Get-CMFolder cmdlets).
# -------------------------------------------------------------------------------------------------
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

if ($null -eq (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue))
{
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName -ErrorAction Stop | Out-Null
}

$originalLocation = Get-Location
Set-Location "$($SiteCode):\" -ErrorAction Stop


# -------------------------------------------------------------------------------------------------
# Load all folders and all security scopes.
# -------------------------------------------------------------------------------------------------
Write-Host "Reading all console folders (SMS_ObjectContainerNode)..." -ForegroundColor Green
try
{
    [array]$allFolders = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -ClassName SMS_ObjectContainerNode -ErrorAction Stop
}
catch
{
    Set-Location $originalLocation
    throw "Failed to read folders from the SMS provider '$ProviderMachineName': $($_.Exception.Message)"
}

Write-Host "Reading all security scopes..." -ForegroundColor Green
try
{
    $script:allScopeNames = @(
        Get-CMSecurityScope -ErrorAction Stop |
            ForEach-Object { if ($_.CategoryName) { $_.CategoryName } elseif ($_.Name) { $_.Name } else { [string]$_ } } |
            Sort-Object -Unique
    )
}
catch
{
    Set-Location $originalLocation
    throw "Failed to read security scopes: $($_.Exception.Message)"
}

if ($script:allScopeNames.Count -eq 0)
{
    Write-Warning "No security scopes were returned. There is nothing to assign."
}


# -------------------------------------------------------------------------------------------------
# Build fast lookup tables: folder-by-ID and children-by-parent.
# -------------------------------------------------------------------------------------------------
$script:folderById       = @{}
$script:childrenByParent = @{}
foreach ($folder in $allFolders)
{
    $script:folderById[[int]$folder.ContainerNodeID] = $folder
}
foreach ($group in ($allFolders | Group-Object -Property ParentContainerNodeID))
{
    $script:childrenByParent[[int]$group.Name] = @($group.Group | Sort-Object -Property Name)
}


# -------------------------------------------------------------------------------------------------
# Script-scoped UI state.
# -------------------------------------------------------------------------------------------------
$script:selectedFolder    = $null                 # tag of the currently selected folder (or $null)
$script:currentScopeNames = @()                    # scope names currently set on the selected folder
$script:pending           = [ordered]@{}           # scope name -> 'Add' | 'Remove'


# -------------------------------------------------------------------------------------------------
# Helper functions.
# -------------------------------------------------------------------------------------------------

# Returns a friendly folder-type name derived from the folder's own ObjectTypeName property
# (the undocumented SMS_ObjectContainerNode.ObjectTypeName, e.g. 'SMS_Package') with the leading
# 'SMS_' prefix and any trailing 'Latest' removed. Falls back to the numeric ObjectType if missing.
function Get-FolderTypeName
{
    param([string]$ObjectTypeName, [int]$ObjectType)
    if (-not [string]::IsNullOrWhiteSpace($ObjectTypeName))
    {
        return (($ObjectTypeName -replace '^SMS_', '') -replace 'Latest$', '')
    }
    return "ObjectType $ObjectType"
}

# Normalizes a scope object (from Get-CMSecurityScope / Get-CMObjectSecurityScope) to its name string.
function Get-ScopeName
{
    param($scopeObject)
    if     ($scopeObject.CategoryName) { return $scopeObject.CategoryName }
    elseif ($scopeObject.Name)         { return $scopeObject.Name }
    else                               { return [string]$scopeObject }
}

# Reads the security scopes currently assigned to a folder (by folder GUID).
function Get-FolderCurrentScopeName
{
    param($folderTag)
    try
    {
        $folderObject = Get-CMFolder -Guid $folderTag.FolderGuid -ErrorAction Stop
        $scopes       = Get-CMObjectSecurityScope -InputObject $folderObject -ErrorAction Stop
        return @($scopes | ForEach-Object { Get-ScopeName -scopeObject $_ })
    }
    catch
    {
        Write-Log -Message "Failed to read scopes for folder '$($folderTag.FullPath)': $($_.Exception.Message)" -Level Warning
        return @()
    }
}

# Returns all descendant folder tags below the given container node ID.
function Get-DescendantFolderTag
{
    param([int]$ContainerNodeID)

    $result = New-Object System.Collections.Generic.List[object]
    $stack  = New-Object System.Collections.Generic.Stack[int]
    $stack.Push($ContainerNodeID)
    while ($stack.Count -gt 0)
    {
        $currentId = $stack.Pop()
        $children  = $script:childrenByParent[$currentId]
        if ($children)
        {
            foreach ($child in $children)
            {
                $childTag = $script:tagByContainerId[[int]$child.ContainerNodeID]
                if ($childTag) { [void]$result.Add($childTag) }
                $stack.Push([int]$child.ContainerNodeID)
            }
        }
    }
    return $result
}

# Applies the currently pending Add/Remove changes to each of the supplied folder tags.
function Invoke-ScopeChange
{
    param([object[]]$folderTags)

    $pendingSnapshot = @($script:pending.GetEnumerator() | ForEach-Object { [PSCustomObject]@{ Name = $_.Key; Action = $_.Value } })
    if ($pendingSnapshot.Count -eq 0) { return }

    foreach ($folderTag in $folderTags)
    {
        $folderObject = $null
        try
        {
            $folderObject = Get-CMFolder -Guid $folderTag.FolderGuid -ErrorAction Stop
        }
        catch
        {
            Write-Log -Message "[$($folderTag.FullPath)] could not be opened: $($_.Exception.Message)" -Level Error
            continue
        }

        foreach ($change in $pendingSnapshot)
        {
            try
            {
                if ($change.Action -eq 'Add')
                {
                    $folderObject | Add-CMObjectSecurityScope -Name $change.Name -ErrorAction Stop -Confirm:$false | Out-Null
                    Write-Log -Message "[$($folderTag.FullPath)] added '$($change.Name)'" -Level Success
                }
                else
                {
                    $folderObject | Remove-CMObjectSecurityScope -Name $change.Name -Force -ErrorAction Stop -Confirm:$false | Out-Null
                    Write-Log -Message "[$($folderTag.FullPath)] removed '$($change.Name)'" -Level Success
                }
            }
            catch
            {
                Write-Log -Message "[$($folderTag.FullPath)] $($change.Action) '$($change.Name)' failed: $($_.Exception.Message)" -Level Error
            }
        }
    }
}


# -------------------------------------------------------------------------------------------------
# Build the WPF window.
# -------------------------------------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework

# Wraps a control in a Border with a uniform look so every pane box matches.
function New-BorderedBox
{
    param($child)
    $border = New-Object System.Windows.Controls.Border
    $border.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xAB, 0xAD, 0xB3))
    $border.BorderThickness = New-Object System.Windows.Thickness(1)
    $border.Child = $child
    return $border
}

$window = New-Object System.Windows.Window
$window.Title  = "$version - Set ConfigMgr folder security scopes"
$window.Width  = 1300
$window.Height = 800

# Column layout: [0]=TreeView [1]=Splitter [2]=Scopes [3]=Splitter [4]=Pending changes
$mainGrid = New-Object System.Windows.Controls.Grid
$mainGrid.Margin = '6'
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$mainGrid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(3, [System.Windows.GridUnitType]::Star)
$mainGrid.ColumnDefinitions[0].MinWidth = 200
$mainGrid.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(5)
$mainGrid.ColumnDefinitions[2].Width = [System.Windows.GridLength]::new(2, [System.Windows.GridUnitType]::Star)
$mainGrid.ColumnDefinitions[2].MinWidth = 180
$mainGrid.ColumnDefinitions[3].Width = [System.Windows.GridLength]::new(5)
$mainGrid.ColumnDefinitions[4].Width = [System.Windows.GridLength]::new(2, [System.Windows.GridUnitType]::Star)
$mainGrid.ColumnDefinitions[4].MinWidth = 180

$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions[0].Height = [System.Windows.GridLength]::Auto                                        # column headers
$mainGrid.RowDefinitions[1].Height = [System.Windows.GridLength]::new(3, [System.Windows.GridUnitType]::Star) # content boxes (3/4)
$mainGrid.RowDefinitions[2].Height = [System.Windows.GridLength]::Auto                                        # log header
$mainGrid.RowDefinitions[3].Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) # activity log (1/4)

# ---- Column headers (row 0) ----
$treeHeader = New-Object System.Windows.Controls.TextBlock
$treeHeader.Text = 'Folders'
$treeHeader.FontWeight = [System.Windows.FontWeights]::Bold
$treeHeader.Margin = '2,0,2,4'
[System.Windows.Controls.Grid]::SetColumn($treeHeader, 0)
[System.Windows.Controls.Grid]::SetRow($treeHeader, 0)
[void]$mainGrid.Children.Add($treeHeader)

$scopeHeader = New-Object System.Windows.Controls.TextBlock
$scopeHeader.FontWeight = [System.Windows.FontWeights]::Bold
$scopeHeader.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
$scopeHeader.Margin = '2,0,2,4'
$scopeHeader.Text = 'Scopes (select a folder)'
[System.Windows.Controls.Grid]::SetColumn($scopeHeader, 2)
[System.Windows.Controls.Grid]::SetRow($scopeHeader, 0)
[void]$mainGrid.Children.Add($scopeHeader)

$pendingHeader = New-Object System.Windows.Controls.TextBlock
$pendingHeader.Text = 'Pending changes'
$pendingHeader.FontWeight = [System.Windows.FontWeights]::Bold
$pendingHeader.Margin = '2,0,2,4'
[System.Windows.Controls.Grid]::SetColumn($pendingHeader, 4)
[System.Windows.Controls.Grid]::SetRow($pendingHeader, 0)
[void]$mainGrid.Children.Add($pendingHeader)

# ---- TreeView (column 0, row 1) ----
$treeView = New-Object System.Windows.Controls.TreeView
$treeView.BorderThickness = New-Object System.Windows.Thickness(0)
$treeBorder = New-BorderedBox -child $treeView
[System.Windows.Controls.Grid]::SetColumn($treeBorder, 0)
[System.Windows.Controls.Grid]::SetRow($treeBorder, 1)
[void]$mainGrid.Children.Add($treeBorder)

# ---- Scope check-box list (column 2, row 1) ----
$scopeScroller = New-Object System.Windows.Controls.ScrollViewer
$scopeScroller.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
$scopeScroller.BorderThickness = New-Object System.Windows.Thickness(0)
$scopePanel = New-Object System.Windows.Controls.StackPanel
$scopePanel.Margin = '2'
$scopeScroller.Content = $scopePanel
$scopeBorder = New-BorderedBox -child $scopeScroller
[System.Windows.Controls.Grid]::SetColumn($scopeBorder, 2)
[System.Windows.Controls.Grid]::SetRow($scopeBorder, 1)
[void]$mainGrid.Children.Add($scopeBorder)

# ---- Pending list + buttons (column 4, row 1) ----
$rightGrid = New-Object System.Windows.Controls.Grid
$rightGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$rightGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$rightGrid.RowDefinitions[0].Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
$rightGrid.RowDefinitions[1].Height = [System.Windows.GridLength]::Auto
[System.Windows.Controls.Grid]::SetColumn($rightGrid, 4)
[System.Windows.Controls.Grid]::SetRow($rightGrid, 1)
[void]$mainGrid.Children.Add($rightGrid)

$pendingList = New-Object System.Windows.Controls.ListBox
$pendingList.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
$pendingList.BorderThickness = New-Object System.Windows.Thickness(0)
$pendingBorder = New-BorderedBox -child $pendingList
[System.Windows.Controls.Grid]::SetRow($pendingBorder, 0)
[void]$rightGrid.Children.Add($pendingBorder)

$buttonPanel = New-Object System.Windows.Controls.StackPanel
$buttonPanel.Margin = '0,6,0,0'
[System.Windows.Controls.Grid]::SetRow($buttonPanel, 1)
[void]$rightGrid.Children.Add($buttonPanel)

$btnThisOnly = New-Object System.Windows.Controls.Button
$btnThisOnly.Content = 'Set for this folder only'
$btnThisOnly.Padding = '8,6'
$btnThisOnly.Margin  = '0,0,0,6'
$btnThisOnly.IsEnabled = $false
[void]$buttonPanel.Children.Add($btnThisOnly)

$btnThisAndSub = New-Object System.Windows.Controls.Button
$btnThisAndSub.Content = 'Set for this and sub-folders'
$btnThisAndSub.Padding = '8,6'
$btnThisAndSub.IsEnabled = $false
[void]$buttonPanel.Children.Add($btnThisAndSub)

# ---- Grid splitters ----
$splitter1 = New-Object System.Windows.Controls.GridSplitter
$splitter1.Width = 5
$splitter1.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$splitter1.VerticalAlignment   = [System.Windows.VerticalAlignment]::Stretch
$splitter1.Background = [System.Windows.Media.Brushes]::LightGray
$splitter1.ShowsPreview = $false
$splitter1.ResizeBehavior  = [System.Windows.Controls.GridResizeBehavior]::PreviousAndNext
$splitter1.ResizeDirection = [System.Windows.Controls.GridResizeDirection]::Columns
[System.Windows.Controls.Grid]::SetColumn($splitter1, 1)
[System.Windows.Controls.Grid]::SetRow($splitter1, 1)
[void]$mainGrid.Children.Add($splitter1)

$splitter2 = New-Object System.Windows.Controls.GridSplitter
$splitter2.Width = 5
$splitter2.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$splitter2.VerticalAlignment   = [System.Windows.VerticalAlignment]::Stretch
$splitter2.Background = [System.Windows.Media.Brushes]::LightGray
$splitter2.ShowsPreview = $false
$splitter2.ResizeBehavior  = [System.Windows.Controls.GridResizeBehavior]::PreviousAndNext
$splitter2.ResizeDirection = [System.Windows.Controls.GridResizeDirection]::Columns
[System.Windows.Controls.Grid]::SetColumn($splitter2, 3)
[System.Windows.Controls.Grid]::SetRow($splitter2, 1)
[void]$mainGrid.Children.Add($splitter2)

# ---- Activity log info bar (header in row 2, log box in row 3, spanning all columns) ----
$logHeader = New-Object System.Windows.Controls.TextBlock
$logHeader.Text = 'Activity log'
$logHeader.FontWeight = [System.Windows.FontWeights]::Bold
$logHeader.Margin = '2,8,2,4'
[System.Windows.Controls.Grid]::SetColumn($logHeader, 0)
[System.Windows.Controls.Grid]::SetColumnSpan($logHeader, 5)
[System.Windows.Controls.Grid]::SetRow($logHeader, 2)
[void]$mainGrid.Children.Add($logHeader)

$logBox = New-Object System.Windows.Controls.ListBox
$logBox.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
$logBox.FontSize = 13
$logBox.BorderThickness = New-Object System.Windows.Thickness(0)
$logBox.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Stretch
$logBorder = New-BorderedBox -child $logBox
[System.Windows.Controls.Grid]::SetColumn($logBorder, 0)
[System.Windows.Controls.Grid]::SetColumnSpan($logBorder, 5)
[System.Windows.Controls.Grid]::SetRow($logBorder, 3)
[void]$mainGrid.Children.Add($logBorder)


# -------------------------------------------------------------------------------------------------
# UI update helpers (defined after the controls exist so they can reference them).
# -------------------------------------------------------------------------------------------------

# Appends a colored, timestamped line to the bottom activity-log box (and the console).
function Write-Log
{
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $stamp = (Get-Date).ToString('HH:mm:ss')
    $item  = New-Object System.Windows.Controls.ListBoxItem
    $item.Content = "$stamp  $Message"
    switch ($Level)
    {
        'Success' { $item.Foreground = [System.Windows.Media.Brushes]::Green;      Write-Host $Message -ForegroundColor Green }
        'Warning' { $item.Foreground = [System.Windows.Media.Brushes]::DarkOrange; Write-Host $Message -ForegroundColor Yellow }
        'Error'   { $item.Foreground = [System.Windows.Media.Brushes]::Red;        Write-Host $Message -ForegroundColor Red }
        default   { $item.Foreground = [System.Windows.Media.Brushes]::Black;      Write-Host $Message }
    }
    [void]$logBox.Items.Add($item)
    $logBox.ScrollIntoView($item)

    # We are on the UI thread inside a loop, so WPF would not repaint until the handler returns.
    # Flush the dispatcher queue (Render + higher) so each log entry shows up immediately.
    $logBox.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
}

# Rebuilds the pending-changes list box and enables/disables the action buttons.
function Update-PendingList
{
    $pendingList.Items.Clear()
    foreach ($entry in $script:pending.GetEnumerator())
    {
        [void]$pendingList.Items.Add(('{0,-7}{1}' -f $entry.Value, $entry.Key))
    }
    $hasPending = ($script:pending.Count -gt 0) -and ($null -ne $script:selectedFolder)
    $btnThisOnly.IsEnabled   = $hasPending
    $btnThisAndSub.IsEnabled = $hasPending
}

# Handler shared by every scope check box. The single argument is the CheckBox that raised the event.
$script:scopeCheckHandler = {
    param($senderObject)

    $scopeName = $senderObject.Tag.Name
    $wasSet    = [bool]$senderObject.Tag.IsSet
    $isChecked = [bool]$senderObject.IsChecked

    if ($isChecked -and -not $wasSet)
    {
        $script:pending[$scopeName] = 'Add'
    }
    elseif (-not $isChecked -and $wasSet)
    {
        $script:pending[$scopeName] = 'Remove'
    }
    else
    {
        # Back to the folder's original state for this scope -> drop any pending change.
        if ($script:pending.Contains($scopeName)) { $script:pending.Remove($scopeName) }
    }

    Update-PendingList
}

# Rebuilds the middle scope check-box list for the currently selected folder.
function Update-ScopePanel
{
    $scopePanel.Children.Clear()
    if ($null -eq $script:selectedFolder)
    {
        $scopeHeader.Text = 'Scopes (select a folder)'
        return
    }

    $scopeHeader.Text = "Scopes for: $($script:selectedFolder.FullPath)"

    if ($script:allScopeNames.Count -eq 0)
    {
        $emptyText = New-Object System.Windows.Controls.TextBlock
        $emptyText.Text = 'No security scopes exist in this site.'
        $emptyText.Margin = '4'
        [void]$scopePanel.Children.Add($emptyText)
        return
    }

    foreach ($scopeName in $script:allScopeNames)
    {
        $checkBox = New-Object System.Windows.Controls.CheckBox
        $checkBox.Content = $scopeName
        $checkBox.Margin  = '4,3,4,3'
        $isSet = @($script:currentScopeNames) -contains $scopeName
        $checkBox.IsChecked = $isSet
        $checkBox.Tag = [PSCustomObject]@{ Name = $scopeName; IsSet = $isSet }
        $checkBox.Add_Click($script:scopeCheckHandler)
        [void]$scopePanel.Children.Add($checkBox)
    }
}

# Reloads the selected folder's scopes from the site, clears pending changes and refreshes the panes.
function Reset-SelectedFolderState
{
    if ($null -eq $script:selectedFolder)
    {
        $script:currentScopeNames = @()
        $script:pending = [ordered]@{}
        Update-ScopePanel
        Update-PendingList
        return
    }

    $script:currentScopeNames = Get-FolderCurrentScopeName -folderTag $script:selectedFolder
    $script:pending = [ordered]@{}
    Update-ScopePanel
    Update-PendingList
}


# -------------------------------------------------------------------------------------------------
# Tree selection handler.
# -------------------------------------------------------------------------------------------------
$treeView.Add_SelectedItemChanged({
    param($src, $e)

    $tag = if ($null -ne $e.NewValue) { $e.NewValue.Tag } else { $null }

    if ($null -eq $tag)
    {
        # A type-root node (or nothing) is selected - there is no folder to edit.
        $script:selectedFolder    = $null
        $script:currentScopeNames = @()
        $script:pending           = [ordered]@{}
        Update-ScopePanel
        Update-PendingList
        return
    }

    $script:selectedFolder = $tag
    $script:pending        = [ordered]@{}

    # Show a tiny hourglass next to the folder name in the tree while the scopes are read.
    # Flush the render queue so it actually paints before the (blocking) provider call.
    $selectedItem = $e.NewValue
    $hourglass    = [char]0x23F3
    $selectedItem.Header = "$($tag.Name)  $hourglass"
    $treeView.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Render)

    # Always read the folder's scopes fresh from the site so the display is accurate.
    $script:currentScopeNames = Get-FolderCurrentScopeName -folderTag $tag

    # Remove the hourglass again now that the scopes are loaded.
    $selectedItem.Header = $tag.Name

    Update-ScopePanel
    Update-PendingList
})


# -------------------------------------------------------------------------------------------------
# Button handlers.
# -------------------------------------------------------------------------------------------------
$btnThisOnly.Add_Click({
    if ($null -eq $script:selectedFolder -or $script:pending.Count -eq 0) { return }

    $confirm = [System.Windows.MessageBox]::Show(
        "Apply $($script:pending.Count) change(s) to the folder:`n$($script:selectedFolder.FullPath)?",
        'Confirm scope changes',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question)
    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Invoke-ScopeChange -folderTags @($script:selectedFolder)
    Reset-SelectedFolderState
})

$btnThisAndSub.Add_Click({
    if ($null -eq $script:selectedFolder -or $script:pending.Count -eq 0) { return }

    $targets = New-Object System.Collections.Generic.List[object]
    [void]$targets.Add($script:selectedFolder)
    foreach ($descendant in (Get-DescendantFolderTag -ContainerNodeID ([int]$script:selectedFolder.ContainerNodeID)))
    {
        [void]$targets.Add($descendant)
    }

    $confirm = [System.Windows.MessageBox]::Show(
        "Apply $($script:pending.Count) change(s) to $($targets.Count) folder(s) (this folder and all sub-folders)?`n`nRoot: $($script:selectedFolder.FullPath)",
        'Confirm scope changes',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Invoke-ScopeChange -folderTags $targets
    Reset-SelectedFolderState
})


# -------------------------------------------------------------------------------------------------
# Build the folder tree. One root node per folder type, folders nested underneath.
# -------------------------------------------------------------------------------------------------

# ContainerNodeID -> the folder tag object we store on each TreeViewItem (used for descendant lookup).
$script:tagByContainerId = @{}

# Recursively creates a TreeViewItem for a folder and all of its children.
function New-FolderTreeItem
{
    param($folder, [string]$parentPath)

    $fullPath = "$parentPath\$($folder.Name)"

    $tag = [PSCustomObject]@{
        ContainerNodeID = [int]$folder.ContainerNodeID
        FolderGuid      = $folder.FolderGuid
        ObjectType      = [int]$folder.ObjectType
        Name            = $folder.Name
        FullPath        = $fullPath
    }
    $script:tagByContainerId[$tag.ContainerNodeID] = $tag

    $item = New-Object System.Windows.Controls.TreeViewItem
    $item.Header = $folder.Name
    $item.Tag    = $tag

    $children = $script:childrenByParent[[int]$folder.ContainerNodeID]
    if ($children)
    {
        foreach ($child in $children)
        {
            [void]$item.Items.Add((New-FolderTreeItem -folder $child -parentPath $fullPath))
        }
    }

    return $item
}

# Group folders by type and create a root node per type that actually has folders. The friendly
# type name comes from each folder's own ObjectTypeName property (with the 'SMS_' prefix stripped).
$foldersByType = $allFolders | Group-Object -Property ObjectType
$rootDefinitions = foreach ($group in $foldersByType)
{
    $sampleFolder = $group.Group | Select-Object -First 1
    [PSCustomObject]@{
        ObjectType = [int]$group.Name
        TypeName   = Get-FolderTypeName -ObjectTypeName $sampleFolder.ObjectTypeName -ObjectType ([int]$group.Name)
    }
}

foreach ($rootDef in ($rootDefinitions | Sort-Object -Property TypeName))
{
    $rootItem = New-Object System.Windows.Controls.TreeViewItem
    $rootHeader = New-Object System.Windows.Controls.TextBlock
    $rootHeader.Text = $rootDef.TypeName
    $rootHeader.FontWeight = [System.Windows.FontWeights]::Bold
    $rootItem.Header = $rootHeader
    $rootItem.Tag    = $null   # root nodes are not editable folders

    # Top-level folders of this type have ParentContainerNodeID = 0.
    $topLevel = $allFolders |
        Where-Object { [int]$_.ObjectType -eq $rootDef.ObjectType -and [int]$_.ParentContainerNodeID -eq 0 } |
        Sort-Object -Property Name

    foreach ($folder in $topLevel)
    {
        [void]$rootItem.Items.Add((New-FolderTreeItem -folder $folder -parentPath $rootDef.TypeName))
    }

    [void]$treeView.Items.Add($rootItem)
}


# -------------------------------------------------------------------------------------------------
# Show the window.
# -------------------------------------------------------------------------------------------------
$window.Content = $mainGrid
$window.ShowDialog() | Out-Null

Set-Location $originalLocation
Write-Host "Done." -ForegroundColor Green
