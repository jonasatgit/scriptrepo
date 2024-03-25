
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

$Title = @"

This is an example script to show how to create a console menu with PowerShell.

****** Select a script to run ******

"@

# base object with some test data to generate the console menu
$mainObject = @(
    [ordered]@{
        Category = "Intune"
        Name = "Get-IntuneState.ps1"
        Url = "https://test.test.test.test"
        Author = "Me"
        Elevation = $true
        Description = "Simple state script"
        Test = 'test'
        Test2 = '23423434'
    }
    [ordered]@{
        Category = "Intune"
        Name = "Get-Win32AppsOrder.ps1----------"
        Url = "https://test.test.test.test"
        Author = "Me"
        Elevation = $true
        Description = "`u{2699} Reads the IntuneManagementExtension.log and returns a ordered list of the Win32Apps"
        Test = 'test'
        Test2 = '23423434'
    }
    [ordered]@{
        Category = "CoMgmt"
        Name = "Get-CoMgmtWL.ps1"
        Url = "https://test.test.test.test"
        Author = "Me"
        Elevation = $false
        Description = "`u{1F195} Returns if CoManagement is enabled and how the workloads are configured"
        Test = 'test'
        Test2 = '23423434'
    }
    [ordered]@{
        Category = "Autopilot"
        Name = "Get-AutopilotAndESPProgress.ps1"
        Url = "https://test.test.test.test"
        Author = "Someone else"
        Elevation = $true
        Description = "Script to view the Autopilot and ESP Progress"
        Test = 'test'
        Test2 = '23423434'
    }
)


#region Split-LongString 
function Split-LongString 
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$String,
        [Parameter(Mandatory = $true)]
        [int]$ChunkSize
    )
    $regex = "(.{1,$ChunkSize})(?:\s|$)"
    $splitStrings = [regex]::Matches($string, $regex) | ForEach-Object { $_.Groups[1].Value }
    $splitStrings
}
#endregion


#region New-ConsoleMenu
<#
.SYNOPSIS
    Creates a console menu with the given title and options

.DESCRIPTION
    Creates a console menu with the given title and options. The options are displayed in a table format with the given properties
    as columns. The properties are selected from the first object in the options array. The properties can be excluded via the
    -ExcludeProperties parameter. The maximum length the last property can be limited via the -MaxStringLength parameter. 
    If the console window is not wide enough to display the menu, a warning is shown and the script stops. If the -StopIfWrongWidth 
    switch is not used, the menu is displayed anyway but might be shown incorrectly.

.PARAMETER Title
    The title of the console menu. It is displayed at the top of the menu. The title can be multiline by using a here-string.

.PARAMETER Options
    An array of objects to display in the console menu

.PARAMETER MaxStringLength
    The maximum length the last property in the console menu. If the property is longer than the given length, it is split into
    multiple lines. Default is 0 which means no limit.

.PARAMETER ExcludeProperties
    An array of properties to exclude from the console menu. Default is $null.

.PARAMETER AddDevideLines
    If this switch is used, a devide line is added after each item in the console menu. Default is $false.

.PARAMETER StopIfWrongWidth
    If this switch is used, the script stops if the console window is not wide enough to display the menu. Default is $false.

.EXAMPLE
    New-ConsoleMenu -Title "Select a script to run" -Options $mainObject -ExcludeProperties 'Test', 'Test2', 'Url' -StopIfWrongWidth -maxStringLength 50

.LINK
    https://jonasatgit.github.io/scriptrepo/General/New-ConsoleMenu.ps1
#>
Function New-ConsoleMenu
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [array]$Options,
        [Parameter(Mandatory = $false)]
        [int]$MaxStringLength = 0,
        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeProperties,
        [Parameter(Mandatory = $false)]
        [switch]$AddDevideLines,
        [Parameter(Mandatory = $false)]
        [switch]$StopIfWrongWidth
    )


    # exclude properties from output if they are in the $ExcludeProperties array and store the result in $selectedProperties
    if ($ExcludeProperties)
    {
        [array]$selectedProperties = $Options[0].Keys | ForEach-Object {
            if ($ExcludeProperties -notcontains $_) {
                $_
            }
        }
    }
    else
    {
        # Nothing to exclude
        [array]$selectedProperties = $Options[0].Keys
    }

    # Calculate the maximum length of each value and key in case the key is longer than the value
    $lengths = @{}
    foreach ($item in $Options) {
        foreach ($property in $item.Keys) {
            if ($selectedProperties -icontains $property)
            {
                $valueLength = $item[$property].ToString().Length
                $keyLength = $property.ToString().Length
                # if key name is longer than value, use key length as value length
                if ($keyLength -gt $valueLength) {
                    $valueLength = $keyLength
                }
                if ($lengths.ContainsKey($property)) {
                    if ($valueLength -gt $lengths[$property]) {
                        $lengths[$property] = $valueLength
                    }
                } else {
                    $lengths.Add($property, $valueLength)
                }
            }
        }
    }

    # if $MaxStringLength is set, we need to limit the maximum length of each string in $lengths
    if ($MaxStringLength -gt 0)
    {
        foreach ($property in $selectedProperties)
        {
            if ($lengths[$property] -gt $MaxStringLength)
            {
                $lengths[$property] = $MaxStringLength
            }
        }
    }

    # Calculcate the maximum width using all selected properties
    $maxWidth = ($lengths.Values | Measure-Object -Sum).Sum

    # Lets check the lenght of the title
    $maxTitleLength = (($Title -split "\r?\n") | ForEach-Object {$_.ToString().Length} | Measure-Object -Sum).Sum
    
    if ($maxTitleLength -gt $maxWidth)
    {
        $maxWidth = $maxTitleLength
    }

    # Add some extra space for each added table character
    # for the outer characters plus a space
    $maxWidth = $maxWidth + 3 
    # 1 + for the "Nr" header and one for each selected property times three because of two spaces and one extra character
    $maxWidth = $maxWidth + (1 + $selectedProperties.count) * 3 

    # create the menu with the $consoleMenu array
    $consoleMenu = @()
    $consoleMenu += "$([char]0x2554)"+"$([Char]0x2550)"*$maxWidth+"$([char]0x2557)"

    foreach ($titlePart in ($Title -split "\r?\n"))
    {
        $consoleMenu += "$([Char]0x2551)"+" "*[Math]::Floor(($maxWidth-($titlePart.Length+2))/2)+$titlePart+" "*[Math]::Ceiling(($maxWidth-($titlePart.Length+2))/2+2)+"$([Char]0x2551)"    
    }
    $consoleMenu += "$([Char]0x2560)"+"$([Char]0x2550)"*$maxWidth+"$([Char]0x2563)"
    # now add the header using just the properties from $selectedProperties
    $header = "$([Char]0x2551)"+" Nr"+" "*(3)+"$([Char]0x2551)"

    foreach ($property in $selectedProperties) 
    {
        $header += " "+$property+" "*($lengths[$property]-($property.Length-1))+"$([Char]0x2551)"
    }

    # if the header is shorter than the max width, we need to add some spaces to the end
    if ($header.Length -lt $maxWidth)
    {
        # we need to replace the last character with a space and then add the last character with spaces until we reach max width
        $header = $header.Substring(0, $header.Length-1) + " " + " "*($maxWidth-$header.Length+1) + "$([Char]0x2551)"
    }

    $consoleMenu += $header
    $consoleMenu += "$([Char]0x2560)"+"$([Char]0x2550)"*$maxWidth+"$([Char]0x2563)"
    # now add the items
    $i = 0
    foreach ($item in $Options) 
    {
        $i++
        $line = "$([Char]0x2551)"+" "+"$i"+" "*(5-$i.ToString().Length)+"$([Char]0x2551)"
        $lineEmpty = "$([Char]0x2551)"+"      "+"$([Char]0x2551)"
        $stringAdded = $false
        foreach ($property in $selectedProperties) 
        {
            
            if ($MaxStringLength -gt 0 -and ($item.$property).Length -gt $MaxStringLength)
            {
                [array]$strList = Split-LongString -String $item.$property -ChunkSize $MaxStringLength
                $rowCounter = 0              
                foreach ($string in $strList)
                {
                    # we need a complete new row for the next string, so we close this one and add it to the $consoleMenu array
                    if ($rowCounter -eq 0)
                    {
                        $line += " "+($string.ToString())+" "*($lengths.$property-(($string.ToString()).Length-1))+"$([Char]0x2551)"
                        if ($line.Length -lt $maxWidth)
                        {
                            # we need to replace the last character with a space and then add the last character with spaces until we reach max width
                            $line = $line.Substring(0, $line.Length-1) + " " + " "*($maxWidth-$line.Length+1) + "$([Char]0x2551)"
                        }
                        $consoleMenu += $line
                        $stringAdded = $true
                    }
                    else 
                    {
                        # This is a new row with nothing bu the remaining string
                        $lineEmpty += " "+($string.ToString())+" "*($lengths.$property-(($string.ToString()).Length-1))+"$([Char]0x2551)"
                        if ($lineEmpty.Length -lt $maxWidth)
                        {
                            # we need to replace the last character with a space and then add the last character with spaces until we reach max width
                            $lineEmpty = $lineEmpty.Substring(0, $lineEmpty.Length-1) + " " + " "*($maxWidth-$lineEmpty.Length+1) + "$([Char]0x2551)"
                        }
                        $consoleMenu += $lineEmpty
                        $stringAdded = $true
                    }
                    $rowCounter++
                }

                # We can add some devide lines if we want
                if ($AddDevideLines)
                {
                    if ($i -lt $Options.Count)
                    {
                        $consoleMenu += "$([Char]0x255F)" +"$([char]0x2500)"*$maxWidth+"$([Char]0x2562)"
                    }
                }

            }
            else
            {
                $line += " "+($item.$property.ToString())+" "*($lengths.$property-(($item.$property.ToString()).Length-1))+"$([Char]0x2551)"
                $lineEmpty += "  "+" "*($lengths.$property)+"$([Char]0x2551)"
            }
        }

        # if the string was not added, we add it here this is typically the case if the string is not longer than $MaxStringLength
        if (-not $stringAdded)
        {
            # if the line is shorter than the max width, we need to add some spaces to the end
            if ($line.Length -lt $maxWidth)
            {
                # we need to replace the last character with a space and then add the last character with spaces until we reach max width
                $line = $line.Substring(0, $line.Length-1) + " " + " "*($maxWidth-$line.Length+1) + "$([Char]0x2551)"
            }
            $consoleMenu += $line

            if ($AddDevideLines)
            {
                if ($i -lt $Options.Count)
                {
                    $consoleMenu += "$([Char]0x255F)" +"$([char]0x2500)"*$maxWidth+"$([Char]0x2562)"
                }
            }
        }
    }
    $consoleMenu += "$([char]0x255a)"+"$([Char]0x2550)"*$maxWidth+"$([char]0x255D)"
    $consoleMenu += " "
  
    # test if the console window is wide enough to display the menu
    if (($Host.UI.RawUI.WindowSize.Width -lt $maxWidth) -or ($Host.UI.RawUI.BufferSize.Width -lt $maxWidth)) 
    {
        if ($StopIfWrongWidth)
        {
            Write-Warning "Change your console window size to at least $maxWidth characters width and re-run the script"
            Write-Warning "Or exclude some properties via '-ExcludeProperties' parameter of 'New-ConsoleMenu' cmdlet in the script"    
            break
        }
        else 
        {
            $consoleMenu
            Write-Warning "Change your console window size to at least $maxWidth characters width and re-run the script"
            Write-Warning "Or exclude some properties via '-ExcludeProperties' parameter of 'New-ConsoleMenu' cmdlet in the script"
        }
    }
    else 
    {
        $consoleMenu
    }
}
#endregion


$selection = -1
$cleared = $false
do
{
    #New-ConsoleMenu -Title $Title -Options $mainObject -MaxStringLength 50 -ExcludeProperties 'Test', 'Test2', 'Url' 
    New-ConsoleMenu -Title $Title -Options $mainObject -ExcludeProperties 'Test', 'Test2', 'Url' -StopIfWrongWidth
    
    if ($cleared)
    {
        Write-Host "`"$($selection)`" is invalid. Use any of the shown numbers or type `"Q`" to quit" -ForegroundColor Yellow
    }

    Write-Host 'Please type the number of the script you want to run or type "Q" to quit' -ForegroundColor Green -NoNewline
    $selection = Read-Host ' '
    #$selection = 'Q'
    # test if the selection is q to quit
    if ($selection -imatch 'q')
    {
        break
    }

    # test if the selection is a number
    # test if selection is between 1 and the number of options
    if ($selection -match '^\d+$' -and $selection -ge 1 -and $selection -le $mainObject.Count) 
    {
        Clear-Host
        $scriptTitle = $mainObject[$selection-1].Name
        $scriptUri = $mainObject[$selection-1].Url
        Write-host "You selected: `"$scriptTitle`"" -ForegroundColor Green
        Write-host "URL: `"$scriptUri`"" -ForegroundColor Green
    } 
    else 
    {
        Clear-Host
        $cleared = $true
    }
    
}
until ($selection -match '^\d+$' -and $selection -ge 1 -and $selection -le $mainObject.Count)
