
<#
.Synopsis
    Script to create html report of Intune policies from MDM Diagnostics Report XML file.
 
.DESCRIPTION
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

#>

# get other resources
#Resources
function Get-IntuneResourcePolicies
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $true)]
        $MDMData
    )

    $outList = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($enrollment in $MDMData.MDMEnterpriseDiagnosticsReport.Resources.Enrollment)
    {
        $enrollmentID = $enrollment.enrollmentid

        foreach ($scope in $enrollment.Scope)
        {
            $resourceTarget = $scope.ResourceTarget
            #$scope.ChildNodes.'#Text'
            foreach ($resource in $scope.Resources.ChildNodes.'#Text')
            {
                if (($resource -match '^\d+$') -or ($resource -match '^default$'))
                {
                    continue
                }

                $outObj = [pscustomobject]@{
                    PolicyScope = 'Resource'
                    EnrollmentId = $enrollmentID
                    ProviderID = (Get-EnrollmentIDData -EnrollmentId $enrollmentID -MDMData $MDMData).ProviderID
                    ResourceTarget = $resourceTarget
                    ResourceName = $resource                    
                }
                $outList.Add($outObj)
            }
            
        }
    }
    return $outList
}


function Convert-FileTimeToDateTime 
{
    param 
    (
        [Parameter(Mandatory = $true)]
        [UInt64]$FileTime
    )

    # Convert to seconds (FILETIME is in 100-nanosecond intervals)
    $seconds = $FileTime / 10000000

    # FILETIME epoch starts at January 1, 1601 (UTC)
    $epoch = Get-Date -Date "1601-01-01 00:00:00Z" -AsUTC

    # Add the seconds to the epoch
    $datetime = $epoch.AddSeconds($seconds)

    return $datetime.ToString("yyyy-MM-dd HH:mm:ss")
}

Function Get-IntuneMSIPolicies
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $true)]
        $MDMData
    )

    $outList = [System.Collections.Generic.List[pscustomobject]]::new()
    Foreach ($user in $MDMData.MDMEnterpriseDiagnosticsReport.EnterpriseDesktopAppManagementinfo.MsiInstallations.TargetedUser)
    {
        $assignmentIdentity = if($user.UserSID -eq 'S-0-0-00-0000000000-0000000000-000000000-000'){'Device'}else{$user.UserSID}
        
        foreach ($package in $user.Package)
        {
            foreach ($packageDetail in $package.Details)
            {  
                $outObj = $null
                $propsList = $packageDetail | Get-Member | Where-Object {$_.MemberType -eq 'Property'}
                $outObj = $packageDetail | Select-Object -Property $propsList.Name
                $outObj | Add-Member NoteProperty 'AssignmentIdentity' -Value $assignmentIdentity
                $outObj | Add-Member NoteProperty 'PackageType' -Value $package.Type
                $outObj | Add-Member NoteProperty 'PolicyScope' -Value 'EnterpriseDesktopAppManagement'

                try 
                {
                    $tmpCreationTime = Convert-FileTimeToDateTime -FileTime $outObj.CreationTime   
                    $outObj.CreationTime = $tmpCreationTime
                }
                catch {}

                try 
                {
                    $tmpEnforcementStartTime = Convert-FileTimeToDateTime -FileTime $outObj.EnforcementStartTime   
                    $outObj.EnforcementStartTime = $tmpEnforcementStartTime
                }
                catch {}
                


                $outList.Add($outObj)
            }
        }      
    }

    return $outList

}


Function Get-IntunePolicyCurrentData
{
    param 
    (
        [Parameter(Mandatory = $true)]
        [string]$PolicyScope,
        [Parameter(Mandatory = $true)]
        [string]$PolicyAreaName,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName,
        [Parameter(Mandatory = $true)]
        $MDMData
    )
    
    # Define the policy scope to filter by
    [array]$global:PolicyScopeData = $MDMData.MDMEnterpriseDiagnosticsReport.PolicyManager.currentPolicies | Where-Object { $_.PolicyScope -eq $PolicyScope }

    # Search for the specific policy area and policy name
    $PolicyObj = $PolicyScopeData.CurrentPolicyValues | Where-Object { $_.PolicyAreaName -eq $PolicyAreaName} 

    # Looking for the specific policy name
    $resultObj = $PolicyObj | select-object -Property "$($PolicyName)_ProviderSet", "$($PolicyName)_WinningProvider"

    return $resultObj
}



function Get-IntunePolicyMetadata
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $true)]
        [string]$PolicyAreaName,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName,
        [Parameter(Mandatory = $true)]
        $MDMData
    )

    # PolicymetaData is a collection of metadata for each policy 
    # We are interested in the regpah or translationDllPath for the specific policy
    $policyMetaData = $MDMData.MDMEnterpriseDiagnosticsReport.PolicyManagerMeta.AreaMetadata | Where-Object { $_.PolicyAreaName -eq $PolicyAreaName }
    if (-not $policyMetaData) 
    {
        return $null
    }
    else 
    {
        $policy = $policyMetaData.PolicyMetadata | Where-Object { $_.PolicyName -eq $PolicyName } 
        if (-not $policy) 
        {
            return $null
        }
        else 
        {
            # If the policy has a RegKeyPathRedirect, return it
            if (-NOT ([string]::IsNullOrEmpty($policy.RegKeyPathRedirect))) 
            {
                return 'RegKeyPathRedirect: {0}' -f $policy.RegKeyPathRedirect
            }

            # If the policy has a translationDllPath, return it
            if(-not ([string]::IsNullOrEmpty($policy.translationDllPath)))
            {
                return 'TranslationDllPath: {0}' -f $policy.translationDllPath
            }

            # If the policy has a grouppolicyPath, return it
            if(-not ([string]::IsNullOrEmpty($policy.grouppolicyPath)))
            {
                return 'GroupPolicyPath: {0}' -f $policy.grouppolicyPath
            }   

            # precheckDllPath
            if(-not ([string]::IsNullOrEmpty($policy.precheckDllPath)))
            {
                return 'PrecheckDllPath: {0}' -f $policy.precheckDllPath
            }

            # GPBlockingRegKeyPath
            if(-not ([string]::IsNullOrEmpty($policy.GPBlockingRegKeyPath)))
            {
                return 'GPBlockingRegKeyPath: {0}' -f $policy.GPBlockingRegKeyPath
            }

            # If no metadata is found, return null
            return 'Unknown'
        }
    }
    return $null
}

function Get-EnrollmentIDData
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $true)]
        [string]$EnrollmentId,
        [Parameter(Mandatory = $true)]
        $MDMData
    )

    $enrollmentObj = $MDMData.MDMEnterpriseDiagnosticsReport.Enrollments.Enrollment | Where-Object {$_.EnrollmentId -eq $EnrollmentId} 
    # If no enrollment object is found, return null
    if (-not $enrollmentObj) 
    {
        #Write-Error "Enrollment ID '$EnrollmentId' not found."
        return $null
    }
    else
    {
        return [pscustomobject][ordered]@{
            EnrollmentId = $enrollmentObj.EnrollmentId
            EnrollmentState = $enrollmentObj.EnrollmentState
            EnrollmentType = $enrollmentObj.EnrollmentType
            CurCryptoProvider = $enrollmentObj.CurCryptoProvider
            DiscoveryServiceFullURL = $enrollmentObj.DiscoveryServiceFullURL
            DMServerCertificateThumbprint = $enrollmentObj.DMServerCertificateThumbprint
            IsFederated = $enrollmentObj.IsFederated
            ProviderID = if ($null -eq $enrollmentObj.ProviderID) 
            {
                'Local'
            }
            elseif ($enrollmentObj.ProviderID -eq 'MS DM Server') 
            {
                'Intune'
            }
            else
            {
                $enrollmentObj.ProviderID
            }

            RenewalPeriod = $enrollmentObj.RenewalPeriod
            RenewalErrorCode = $enrollmentObj.RenewalErrorCode
            RenewalROBOSupport = $enrollmentObj.RenewalROBOSupport
            RenewalStatus = $enrollmentObj.RenewalStatus
            RetryInterval = $enrollmentObj.RetryInterval
            RootCertificateThumbPrint = $enrollmentObj.RootCertificateThumbPrint
            IsRecoveryAllowed = $enrollmentObj.IsRecoveryAllowed
            DMClient = $enrollmentObj.DMClient
            Poll = $enrollmentObj.Poll
            FirstSync = $enrollmentObj.FirstSync
            UserFirstSync = $enrollmentObj.UserFirstSync
            Push = $enrollmentObj.Push
        }
    }
}


function Invoke-EscapeHtmlText 
{
    param ([string]$Text)
    return $Text -replace '&', '&amp;' `
                   -replace '<', '&lt;' `
                   -replace '>', '&gt;' `
                   -replace '"', '&quot;' `
                   -replace "'", '&#39;'
}


#region Convert-IntunePoliciesToHtml
function Convert-IntunePoliciesToHtml {
    param (
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [array]$Policies,

        [string]$Title = "Intune Policy Report"
    )

$htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>$Title</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 14px; }
        h1 { color: #2E6DA4; }
        h2 { color: #444; margin-top: 10px; }

        .toggle-button {
            background-color: #007BFF;
            color: white;
            border: none;
            padding: 5px 10px;
            margin-bottom: 10px;
            cursor: pointer;
            border-radius: 4px;
        }

        .collapsible-content {
            display: block;
            margin-top: 10px;
        }

        .group-container {
            border: 1px solid #ccc;
            background-color: #f9f9f9;
            padding: 15px;
            margin-bottom: 30px;
            border-radius: 6px;
            box-shadow: 2px 2px 5px rgba(0,0,0,0.05);
        }

        table {
            border-collapse: collapse;
            width: 100%;
            margin-bottom: 20px;
            table-layout: fixed;
            border: 3px solid #ddd;
        }

        th, td {
            border: 1px solid #ddd;
            padding: 8px;
            word-wrap: break-word;
            text-align: left;
        }

        th.setting-col, td.setting-col { width: 450px; }
        th { background-color: #f2f2f2; text-align: left; }
        tr:nth-child(even) { background-color: #f9f9f9; }

        th.resource-col, td.resource-col { width: 150px; }
        th { background-color: #f2f2f2; text-align: left; }
        tr:nth-child(even) { background-color: #f9f9f9; }

        .policy-area-title {
            color: #2E6DA4;
        }
    </style>
    <script>
        function toggleContent(button) {
            const content = button.nextElementSibling;
            const isVisible = window.getComputedStyle(content).display !== "none";

            if (isVisible) {
                content.style.display = "none";
                button.textContent = "Show Details";
            } else {
                content.style.display = "block";
                button.textContent = "Hide Details";
            }
        }


        function toggleAll() {
        const contents = document.querySelectorAll('.collapsible-content');
        const buttons = document.querySelectorAll('.toggle-button:not(#toggleAllBtn)');
        const toggleAllBtn = document.getElementById('toggleAllBtn');
        const shouldCollapse = toggleAllBtn.textContent === 'Collapse All';

        contents.forEach((content, index) => {
                content.style.display = shouldCollapse ? 'none' : 'block';
            if (buttons[index]) {
            buttons[index].textContent = shouldCollapse ? 'Show Details' : 'Hide Details';
        }
        });

        toggleAllBtn.textContent = shouldCollapse ? 'Expand All' : 'Collapse All';
        }


    </script>
</head>
<body>
    <h1>$Title ⚙️</h1>
    <p>Generated on: 📅 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    <p>This report contains detailed information about Intune policies applied to devices and users.</p>
    <button class='toggle-button' onclick='toggleAll()' id='toggleAllBtn'>Collapse All</button>
"@



    $htmlFooter = "</body></html>"
    $htmlBody = ""
 
    $grouped = $Policies | Group-Object -Property PolicyScope

    foreach ($group in $grouped) 
    {
        if (($group.Name -ne 'Device') -and ($group.Name -notmatch 'S-\d+(-\d+)+')) 
        {
            # Skip groups that are not 'Device' or do not match the SID pattern
            # We will add them later
            continue
        }

        $htmlBody += "<div class='group-container'>"
        $htmlBody += "<h2>PolicyScope: <span class='p olicy-area-title'>$(if ($group.Name -eq 'Device') { '💻 Device' } else { '👤 ' + $group.Name })</span></h2>"
        $htmlBody += "<button class='toggle-button' onclick='toggleContent(this)'>Hide Details</button>"
        $htmlBody += "<div class='collapsible-content'>"

        $i = 0
        foreach ($policy in ($group.Group | Sort-Object -Property PolicyAreaName)) 
        {
            if ($i -gt 0) 
            {
                $htmlBody += "<br><br>"
            }

            $htmlBody += "<h2 class='policy-area-title'>PolicyArea: $($policy.PolicyAreaName)</h2>"
            #$htmlBody += "<div class='settings-container'>"
            $htmlBody += "<table style='margin-bottom: 10px; width: 100%; border-collapse: collapse;'>"
            $htmlBody += "<tr><td style='font-weight: bold; width: 450px;'>EnrollmentId</td><td>$($policy.EnrollmentId) ➡️ $($policy.EnrollmentProvider)</td></tr>"
            $htmlBody += "<tr style='border-top: 3px solid #ddd;'><th class='setting-col'>Setting 🛠️</th><th>Value</th></tr>"

            foreach ($settings in $policy.Settings) 
            {
                $settingspath = 'Path or DLL of the setting: "{0}"' -f $settings.Metadata

                #$value = Format-StringToXml -XmlString $settings.Value
                $value = Invoke-EscapeHtmlText -Text ($settings.Value)
                $htmlBody += "<tr><td class='setting-col'>$($settings.Name)</td><td title='$($settingspath)'>$value</td></tr>"
            }

            $htmlBody += "</table>"
            #$htmlBody += "</div>"  # Close settings-container div
            $i++
        }
        $htmlBody += "</div>"  # Close collapsible-content
        $htmlBody += "</div>"  # Close group-container
    }

    # lets now add the enterprise desktop app management policies
    [array]$enterpriseDesktopPolicies = $Policies | Where-Object { $_.PolicyScope -eq 'EnterpriseDesktopAppManagement' }

    $htmlBody += "<div class='group-container'>"
    $htmlBody += "<h2>PolicyScope: <span class='p olicy-area-title'>📦 EnterpriseDesktopAppManagement</span></h2>"
    $htmlBody += "<button class='toggle-button' onclick='toggleContent(this)'>Hide Details</button>"
    $htmlBody += "<div class='collapsible-content'>"

    foreach ($app in $enterpriseDesktopPolicies)
    {
        $possibleAppName = ($app.CurrentDownloadUrl | Split-Path -Leaf)

        $htmlBody += "<h2 class='policy-area-title'>App: $($possibleAppName)</h2>"
        $htmlBody += "<table style='margin-bottom: 10px; width: 100%; border-collapse: collapse;'>"

        $excludedProperties = @('ActionType', 'AssignmentType', 'BITSJobId', 'JobStatusReport', 'PolicyScope', 'ServerAccountID', 'PackageId')

        foreach ($property in ($app.PSObject.Properties | Sort-Object -Property Name))
        {
            if ($property.Name -in $excludedProperties) 
            {
                continue
            }

            $value = Invoke-EscapeHtmlText -Text ($property.Value)
            $htmlBody += "<tr><td style='font-weight: bold; width: 450px;'>$($property.Name)</td><td>$value</td></tr>"
        }
        
        $htmlBody += "</table>"
        $htmlBody += "<br>"
    }
    $htmlBody += "</div>"  # Close collapsible-content
    $htmlBody += "</div>"  # Close group-container


    # lets now add the resource policies
    $groupedResources = $Policies | Where-Object { $_.PolicyScope -eq 'Resource' } | Group-Object -Property EnrollmentId, ResourceTarget

    $htmlBody += "<div class='group-container'>"
    $htmlBody += "<h2>PolicyScope: <span class='policy-area-title'>🌐 Resource Policies</span></h2>"
    $htmlBody += "<button class='toggle-button' onclick='toggleContent(this)'>Hide Details</button>"
    $htmlBody += "<div class='collapsible-content'>"

    foreach ($resourceEntry in $groupedResources) 
    {

        $tmpSplitVar = $resourceEntry.Name -split ','

        $htmlBody += "<table style='margin-bottom: 10px; width: 100%; border-collapse: collapse;'>"
        $htmlBody += "<tr><td style='font-weight: bold; width: 150px;'>EnrollmentId</td><td  style='font-weight: bold;'>$($($tmpSplitVar[0])) ➡️ $($resourceEntry.Group[0].ProviderID)</td></tr>"
        $htmlBody += "<tr><td style='font-weight: bold; width: 150px;'>ResourceTarget</td><td  style='font-weight: bold;'>$(if($tmpSplitVar[1].ToString().Trim() -ieq 'Device') { '💻 Device' } else { '👤 ' + $tmpSplitVar[1].ToString().Trim() })</td></tr>"
        
        ### Formatting wrong here: -> $htmlBody += "<tr><td class='resource-col' >     </td><td style='font-weight: bold;'>Resource</td></tr>"


        foreach ($resource in $resourceEntry.Group)  
        {
            $resourceName = Invoke-EscapeHtmlText -Text ($resource.ResourceName)
            $htmlBody += "<tr><td></td><td>$resourceName</td></tr>"
        }

        $htmlBody += "</table>"
        $htmlBody += "<br>"
    }
    $htmlBody += "</div>"  # Close collapsible-content
    $htmlBody += "</div>"  # Close group-container


    $fullHtml = $htmlHeader + $htmlBody + $htmlFooter
    Set-Content -Path $OutputPath -Value $fullHtml -Encoding UTF8
}
#enregion

function Format-StringToXml 
{
    param (
        [string]$XmlString
    )

    # Wrap in a root element to ensure valid XML
    $wrappedXml = "<root>$XmlString</root>"

    try {
        [xml]$xml = $wrappedXml
    } catch {
        Write-Host "Invalid XML format" -ForegroundColor Yellow
        return $XmlString
    }

    $formattedXml = ""

    if ($xml.root.enabled) {
        $formattedXml += "&lt;enabled/&gt;<br>"
    }

    foreach ($node in $xml.root.data) {
        $id = $node.id
        $value = $node.value
        $formattedXml += "&nbsp;&nbsp;&lt;data id='$id' value='$value'/&gt;<br>"
    }

    return "<pre>$formattedXml</pre>"
}


 

$MDMDiagFolder = "$env:PUBLIC\Documents\MDMDiagnostics\$(Get-date -Format 'yyyy-MM-dd_HH-mm-ss')"

if (-NOT (Test-Path -Path $MDMDiagFolder)) 
{
    New-Item -Path $MDMDiagFolder -ItemType Directory | Out-Null
}

$reportFullName = '{0}\MDMDiagReport.xml' -f $MDMDiagFolder

Start-Process MdmDiagnosticsTool.exe -Wait -ArgumentList "-out `"$MDMDiagFolder`"" -NoNewWindow -ErrorAction Stop

[xml]$xmlFile = Get-Content -Path $reportFullName

$IntunePolicyList = [System.Collections.Generic.List[pscustomobject]]::new()
# Iterate through each ConfigSource item in the XML
foreach ($item in $xmlFile.MDMEnterpriseDiagnosticsReport.PolicyManager.ConfigSource)
{
    $enrollmentID = $item.EnrollmentId
    $enrollmentData = Get-EnrollmentIDData -EnrollmentId $enrollmentID -MDMData $xmlFile
    
    foreach ($PolicyScope in $item.PolicyScope)
    {
        $PolicyScopeName = $PolicyScope.PolicyScope

        foreach ($area in $PolicyScope.Area)
        {
            if ($area.PolicyAreaName -ieq 'knobs')
            {
                # Skip the 'knobs' area
                continue
            }

            # Define the properties we are interested in 
            [array]$propertyList = $area | Get-Member | Where-Object {$_.MemberType -eq 'Property'} | Select-Object -Property Name | Where-Object {$_.Name -notlike '*_LastWrite' -and $_.Name -ne 'PolicyAreaName'}



            $tmpObj = [pscustomobject]@{
                            EnrollmentId = $enrollmentID
                            EnrollmentProvider = $enrollmentData.ProviderID
                            PolicyScope  =  $PolicyScopeName
                            PolicyAreaName = $area.PolicyAreaName
                            SettingsCount = $propertyList.Count
                            Settings = $null
                        }

            # Initialize the Settings hashtable
            #$settingsHash = @{}
            $settingsList = [System.Collections.Generic.List[pscustomobject]]::new()
            foreach ($property in $propertyList)
            {

                # Adding metadata for the property
                $metadataInfo = Get-IntunePolicyMetadata -MDMData $xmlFile -PolicyAreaName $area.PolicyAreaName -PolicyName $property.Name
                if ($area.PolicyAreaName -ieq 'knobs')
                {
                    $winningProvider = "Not set"
                }
                else 
                {
                    $currentPolicyInfo = Get-IntunePolicyCurrentData -PolicyScope $PolicyScopeName -PolicyAreaName $area.PolicyAreaName -PolicyName $property.Name -MDMData $xmlFile
                    if ($null -eq $currentPolicyInfo)
                    {
                        $winningProvider = "Not set"    
                    }
                    else 
                    {
                        $winningProvider = $currentPolicyInfo | Select-Object -ExpandProperty "$($property.Name)_WinningProvider"
                    }
                }
                

                $settingsList.Add([pscustomobject][ordered]@{
                    Name = $property.Name
                    Value = $area.$($property.Name)
                    WinningProvider = $winningProvider
                    Metadata = $metadataInfo
                })

            }

            $tmpObj.Settings = $settingsList
            # Add the tmpObj to the $IntunePolicyList
            $IntunePolicyList.Add($tmpObj)
        }
    }
}

Get-IntuneMSIPolicies -MDMData $xmlFile | ForEach-Object {
    $IntunePolicyList.Add($_)
}

Get-IntuneResourcePolicies -MDMData $xmlFile | ForEach-Object {
    $IntunePolicyList.Add($_)
}


# Convert the policies to HTML and save to the specified output path
Convert-IntunePoliciesToHtml -OutputPath "C:\Users\Public\Documents\IntunePolicyReport.html" -Policies $IntunePolicyList -Title "Intune Policy Report"

Start-Process "msedge.exe" -ArgumentList "C:\Users\Public\Documents\IntunePolicyReport.html"









