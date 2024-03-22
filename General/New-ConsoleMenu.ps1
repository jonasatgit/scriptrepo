
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

$StopIfWrongWidth = $true


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
        Description = "Reads the IntuneManagementExtension.log and returns a ordered list of the Win32Apps"
        Test = 'test'
        Test2 = '23423434'
    }
    [ordered]@{
        Category = "CoMgmt"
        Name = "Get-CoMgmtWL.ps1"
        Url = "https://test.test.test.test"
        Author = "Me"
        Elevation = $false
        Description = "Returns if CoManagement is enabled and how the workloads are configured"
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
        [switch]$AddDevideLines
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
                        $consoleMenu += $line
                        $stringAdded = $true
                    }
                    else 
                    {
                        # This is a new row with nothing bu the remaining string
                        $lineEmpty += " "+($string.ToString())+" "*($lengths.$property-(($string.ToString()).Length-1))+"$([Char]0x2551)"
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
                #$consoleMenu += $line
            }
        }

        # if the string was not added, we add it here this is typically the case if the string is not longer than $MaxStringLength
        if (-not $stringAdded)
        {
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
            Write-Warning "Change your console window size to at least $maxWidth characters width"
            Write-Warning "Or exclude some properties via '-ExcludeProperties' parameter of 'New-ConsoleMenu' cmdlet in the script"    
            break
        }
        else 
        {
            $consoleMenu
            Write-Warning "Change your console window size to at least $maxWidth characters width"
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
    New-ConsoleMenu -Title $Title -Options $mainObject -ExcludeProperties 'Test', 'Test2', 'Url'
    
    if ($cleared)
    {
        Write-Host "`"$($selection)`" is invalid. Use any of the shown numbers or type `"Q`" to quit" -ForegroundColor Yellow
    }

    $selection = Read-Host 'Please type the number of the script you want to run or type "Q" to quit'
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
