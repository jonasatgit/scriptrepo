
$mainObject = [ordered]@{
    'Get-Win32AppsOrder.ps1' = @{
        category = "Intune"
        url = "https://test.test.test.test"
        description = "Reads the IntuneManagementExtension.log and returns a ordered list of the Win32Apps" 
    }
    'Get-CoMgmtWL.ps1' = @{
        category = "CoMgmt"
        url = "https://test.test.test.test"
        description = "Returns if CoManagement is enabled and how the workloads are configured"
    }
    'Get-AutopilotAndESPProgress.ps1' = @{
        category = "Autopilot"
        url = "https://test.test.test.test"
        description = "Script to view the Autopilot and ESP Progress"
    }
}


Function New-ConsoleMenu
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    $maxNameLengh = $Options.GetEnumerator() | ForEach-Object {$_.Name.Length} | Sort-Object -Descending | Select-Object -First 1
    $maxCategoryLengh = $Options.GetEnumerator() | ForEach-Object {$_.Value.category.Length} | Sort-Object -Descending | Select-Object -First 1
    $maxDescriptionLengh = $Options.GetEnumerator() | ForEach-Object {$_.Value.description.Length} | Sort-Object -Descending | Select-Object -First 1

    $maxwidth = $maxNameLengh + $maxCategoryLengh + $maxDescriptionLengh + 18

    $consoleMenu = @()
    # first menu line
    $consoleMenu += "$([char]0x2554)"+"$([Char]0x2550)"*$maxwidth+"$([char]0x2557)"
    # title
    $consoleMenu += "$([Char]0x2551)"+" "*[Math]::Floor(($maxwidth-$title.Length)/2)+$Title+" "*[Math]::Ceiling(($maxwidth-$title.Length)/2)+"$([Char]0x2551)"
    # separator
    $consoleMenu += "$([Char]0x255F)" +"$([char]0x2500)"*$maxwidth+"$([Char]0x2562)"
    # menu titles: Category, Name, Description
    $consoleMenu += "$([Char]0x2551)"+" "+"Nr"+" "*(3)+"$([Char]0x2551)"+" "+"Category"+" "*($maxCategoryLengh-5)+"$([Char]0x2551)"+" "*2+"Name"+" "*($maxNameLengh-3)+"$([Char]0x2551)"+" "+"Description"+" "*($maxDescriptionLengh-10)+"$([Char]0x2551)"
    # seperator
    $consoleMenu += "$([Char]0x2560)"+"$([Char]0x2550)"*$maxwidth+"$([Char]0x2563)"
    # menu items
    $i = 0
    foreach ($option in $options.GetEnumerator()) {
        $i++
        $consoleMenu += "$([Char]0x2551)"+" "+"$i"+" "*(5-$i.ToString().Length)+"$([Char]0x2551)"+" "+$option.Value.category+" "*(($maxCategoryLengh-$option.Value.category.Length)+3)+"$([Char]0x2551)"+" "*2+$option.Name+" "*(($maxNameLengh-$option.Name.Length)+1)+"$([Char]0x2551)"+" "+$option.Value.description+" "*(($maxDescriptionLengh-$option.Value.description.Length)+1)+"$([Char]0x2551)"
    }
    $consoleMenu += "$([char]0x255a)"+"$([Char]0x2550)"*$maxwidth+"$([char]0x255D)"
    $consoleMenu += " "
    $consoleMenu
}
#endregion

New-ConsoleMenu -Title "Select a script to run" -Options $mainObject

$selection = Read-Host "Select a script by number"
# test if the selection is a number
# test if selection is between 1 and the number of options
if ($selection -match '^\d+$' -and $selection -ge 1 -and $selection -le $options.Count) 
{
    $scriptTitle = $mainObject.Keys[$selection-1]
    $scriptUri = $mainObject[$selection-1].url
    Write-host "You selected: `"$scriptTitle`"" -ForegroundColor Green
    Write-host "URL: `"$scriptUri`"" -ForegroundColor Green
} 
else 
{
    Write-Host "Invalid selection"
}

