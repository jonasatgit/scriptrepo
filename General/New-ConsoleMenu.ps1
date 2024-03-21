
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

$Title = "****** Select a script to run ******"


$mainObject = [ordered]@{
    'item001' = [ordered]@{
        Category = "Intune"
        Name = "Get-Win32AppsOrder.ps1----------"
        Url = "https://test.test.test.test"
        Author = "Me"
        Elevation = 'Required'
        Description = "Reads the IntuneManagementExtension.log and returns a ordered list of the Win32Apps"
        Hidden = 'url,test'
        Test = 'test'
    }
    'item002' = [ordered]@{
        Category = "CoMgmt"
        Name = "Get-CoMgmtWL.ps1"
        Url = "https://test.test.test.test"
        Author = "Me"
        Elevation = ''
        Description = "Returns if CoManagement is enabled and how the workloads are configured"
        Hidden = 'url,test'
        Test = 'test'
    }
    'item003' = [ordered]@{
        Category = "Autopilot"
        Name = "Get-AutopilotAndESPProgress.ps1"
        Url = "https://test.test.test.test"
        Author = "Someone else"
        Elevation = 'Required'
        Description = "Script to view the Autopilot and ESP Progress"
        Hidden = 'url,test'
        Test = 'test'
    }
}


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
        [System.Collections.Specialized.OrderedDictionary]$Options,
        [Parameter(Mandatory = $false)]
        [int]$MaxStringLength = 0
    )

    # getting some basic info from the first entry
    [array]$propertiesToHideFromOutput = $Options[0].Hidden -split ','
    $propertiesToHideFromOutput += 'Hidden'

    [array]$selectedProperties = $Options[0].GetEnumerator() | ForEach-Object {
        if ($propertiesToHideFromOutput -notcontains $_.Key) {
            $_.Key
        }
    }


    # calculate the maximum length of each property
    $lengths = @{}
    foreach ($item in $Options.Values) {
        foreach ($property in $item.Keys) {
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

    # Calculcate the maximum width using all selected properties
    $maxWidth = 0
    foreach ($property in $selectedProperties) {
        $maxWidth = $maxWidth + $lengths[$property]
    }

    # Add some extra space for each added table character
    $maxWidth = $maxWidth + 3 # for the outer characters plus a space "║ " and "║"
    $maxWidth = $maxWidth + (1 + $selectedProperties.count) * 3 # 1 + for the Nr header and one for each selected property times three because of two spaces and one character

    # create the menu with the $consoleMenu array
    $consoleMenu = @()
    $consoleMenu += "$([char]0x2554)"+"$([Char]0x2550)"*$maxWidth+"$([char]0x2557)"
    $consoleMenu += "$([Char]0x2551)"+" "*[Math]::Floor(($maxWidth-($Title.Length+2))/2)+$Title+" "*[Math]::Ceiling(($maxWidth-($Title.Length+2))/2+2)+"$([Char]0x2551)"
    $consoleMenu += "$([Char]0x255F)" +"$([char]0x2500)"*$maxWidth+"$([Char]0x2562)"
    # now add the header using just the properties from $selectedProperties
    $header = "$([Char]0x2551)"+" Nr"+" "*(3)+"$([Char]0x2551)"

    foreach ($property in $selectedProperties) {
        $header += " "+$property+" "*($lengths[$property]-($property.Length-1))+"$([Char]0x2551)"
    }
    $consoleMenu += $header
    $consoleMenu += "$([Char]0x2560)"+"$([Char]0x2550)"*$maxWidth+"$([Char]0x2563)"
    # now add the items
    $i = 0
    foreach ($item in $Options.GetEnumerator()) {
        $i++
        $line = "$([Char]0x2551)"+" "+"$i"+" "*(5-$i.ToString().Length)+"$([Char]0x2551)"
        foreach ($property in $selectedProperties) 
        {
            <#
            if ($MaxStringLength -gt 0 -and ($item.Value[$property]).Length -gt $MaxStringLength)
            {
                [array]$strList = Split-LongString -String $item.Value[$property] -ChunkSize $MaxStringLength
                foreach ($string in $strList)
                {
                    $line += " "+$string+" "*($lengths[$property]-($string.Length-1))+"$([Char]0x2551)"
                }
            }
            else
            {
                $line += " "+$item.Value[$property]+" "*($lengths[$property]-($item.Value[$property].Length-1))+"$([Char]0x2551)"
            }
            #>
            $line += " "+$item.Value[$property]+" "*($lengths[$property]-($item.Value[$property].Length-1))+"$([Char]0x2551)"
        }
        $consoleMenu += $line
    }
    $consoleMenu += "$([char]0x255a)"+"$([Char]0x2550)"*$maxWidth+"$([char]0x255D)"
    $consoleMenu += " "
    $consoleMenu
}
#endregion

$selection = -1
$cleared = $false
do
{

    New-ConsoleMenu -Title $Title -Options $mainObject -MaxStringLength 50
    
    if ($cleared)
    {
        Write-Host "Invalid selection. Use any of the shown numbers or type `"Q`" to quit" -ForegroundColor Yellow
    }

    $selection = Read-Host 'Please type the number of the script you want to run'
    # test if the selection is a number
    # test if selection is between 1 and the number of options
    if ($selection -imatch 'q')
    {
        exit 0
    }

    if ($selection -match '^\d+$' -and $selection -ge 1 -and $selection -le $mainObject.Count) 
    {

        else
        {
            $scriptTitle = $mainObject[$selection-1].Name
            $scriptUri = $mainObject[$selection-1].Url
            Write-host "You selected: `"$scriptTitle`"" -ForegroundColor Green
            Write-host "URL: `"$scriptUri`"" -ForegroundColor Green
        }
    } 
    else 
    {
        Clear-Host
        $cleared = $true
    }
}
until ($selection -match '^\d+$' -and $selection -ge 1 -and $selection -le $mainObject.Count)
