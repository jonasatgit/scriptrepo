
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

[CmdletBinding()]
param 
(
    [Parameter(Mandatory = $false)]
    [string]$MDMDiagReportXmlPath
)


Function Get-IntunePolicyDataFromXML
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $false)]
        [string]$MDMDiagReportXmlPath
    )

    # If no path is provided, generate a new report
    if ([string]::IsNullOrEmpty($MDMDiagReportXmlPath)) 
    {
        $MDMDiagFolder = "$env:PUBLIC\Documents\MDMDiagnostics\$(Get-date -Format 'yyyy-MM-dd_HH-mm-ss')"

        if (-NOT (Test-Path -Path $MDMDiagFolder)) 
        {
            New-Item -Path $MDMDiagFolder -ItemType Directory | Out-Null
        }

        $MDMDiagReportXmlPath = '{0}\MDMDiagReport.xml' -f $MDMDiagFolder

        Start-Process MdmDiagnosticsTool.exe -Wait -ArgumentList "-out `"$MDMDiagFolder`"" -NoNewWindow -ErrorAction Stop

        [xml]$xmlFile = Get-Content -Path $MDMDiagReportXmlPath -Raw -ErrorAction Stop
    }
    else 
    {
        if (-Not (Test-Path -Path $MDMDiagReportXmlPath)) 
        {
            Write-Error "The specified MDM Diagnostics Report XML file does not exist: `"$MDMDiagReportXmlPath`""
            return
        }
        
        [xml]$xmlFile = Get-Content -Path $MDMDiagReportXmlPath -Raw -ErrorAction Stop
    }

    $outObj = [pscustomobject]@{
        XMlFileData = $xmlFile
        FileFullName = $MDMDiagReportXmlPath
    }
    return $outObj
}
#endregion


#region Get-IntunePolicySystemInfo
# Extract system information from the MDM Diagnostics Report
Function Get-IntunePolicySystemInfo
{
    [CmdletBinding()]
    param 
    (
        [string]$HtmlReportPath
    )

    $htmlFile = Get-Content -Path $HtmlReportPath -Raw -ErrorAction SilentlyContinue

    # Extract only the DeviceInfoTable content
    $tablePattern = '<table[^>]*id="DeviceInfoTable"[^>]*>(.*?)<\/table>'
    $tableMatch = [regex]::Match($htmlFile, $tablePattern, 'Singleline')

    if ($tableMatch.Success) 
    {
        $tableContent = $tableMatch.Groups[1].Value

        # Extract label-value pairs
        $rowPattern = '<td[^>]*>(.*?)<\/td>\s*<td[^>]*>(.*?)<\/td>'
        $properties = [ordered]@{}

        [regex]::Matches($tableContent, $rowPattern) | ForEach-Object {
            $label = ($_.Groups[1].Value -replace '<.*?>', '').Trim()
            $value = ($_.Groups[2].Value -replace '<.*?>', '').Trim()

            # Normalize label to a valid property name
            $propertyName = ($label -replace '[^a-zA-Z0-9]', '') -replace '^(.+)$', { $_.Groups[1].Value }
            $properties[$propertyName] = $value
        }

        <#
        # Create a single object with all properties
        $SystemInfo = [PSCustomObject]$properties

        # make sure windows 10 and 11 are correctly identified
        # Everything below build number 19045 is Windows 10, everything above is Windows 11
        if ($SystemInfo.OSBuild -gt 10.0.19045) 
        {
            $SystemInfo.Edition = $SystemInfo.Edition -replace 'Windows 10', 'Windows 11'
        }

        # lets remove the word unknown from the systemtype if it is present
        $SystemInfo.SystemType = ($SystemInfo.SystemType -replace 'Unknown', '').TrimStart()

        # lets add an identifier to be able to distinguish between the different system info objects
        $SystemInfo | Add-Member -MemberType NoteProperty -Name 'PolicyScope' -Value 'DeviceInfo'
        #>

    } 
    else 
    {
        Write-Host "DeviceInfoTable in file `"$HtmlReportPath`" not found."
        return $null
    }
    #return $SystemInfo

    # lets do the same for the "ConnectionInfoTable" and add those properties to the SystemInfo object
    # Extract only the ConnectionInfoTable content
    $tablePattern = '<table[^>]*id="ConnectionInfoTable"[^>]*>(.*?)<\/table>'
    $tableMatch = [regex]::Match($htmlFile, $tablePattern, 'Singleline')

    if ($tableMatch.Success) 
    {
        $tableContent = $tableMatch.Groups[1].Value

        # Extract label-value pairs
        $rowPattern = '<td[^>]*>(.*?)<\/td>\s*<td[^>]*>(.*?)<\/td>'

        [regex]::Matches($tableContent, $rowPattern) | ForEach-Object {
            $label = ($_.Groups[1].Value -replace '<.*?>', '').Trim()
            $value = ($_.Groups[2].Value -replace '<.*?>', '').Trim()

            # Normalize label to a valid property name
            $propertyName = ($label -replace '[^a-zA-Z0-9]', '') -replace '^(.+)$', { $_.Groups[1].Value }
            $properties[$propertyName] = $value
        }
    }
    else 
    {
        Write-Host "ConnectionInfoTable in file `"$HtmlReportPath`" not found."
        #return $null
    }

    # Create a single object with all properties
    $SystemInfo = [PSCustomObject]$properties

    # make sure windows 10 and 11 are correctly identified
    # Everything below build number 19045 is Windows 10, everything above is Windows 11
    if ($SystemInfo.OSBuild -gt 10.0.19045) 
    {
        $SystemInfo.Edition = $SystemInfo.Edition -replace 'Windows 10', 'Windows 11'
    }

    # lets remove the word unknown from the systemtype if it is present
    $SystemInfo.SystemType = ($SystemInfo.SystemType -replace 'Unknown', '').TrimStart()

    # lets add an identifier to be able to distinguish between the different system info objects
    $SystemInfo | Add-Member -MemberType NoteProperty -Name 'PolicyScope' -Value 'DeviceInfo'
   
    # If the SystemInfo object is empty, return null
    if ($SystemInfo.PSObject.Properties.Count -eq 0) 
    {
        Write-Host "No system information found in file `"$HtmlReportPath`"."
        return $null
    }

    return $SystemInfo

}
#endregion


#region Function Get-IntuneDeviceAndUserPolicies
Function Get-IntuneDeviceAndUserPolicies
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $true)]
        $MDMData
    )

    $outObj = [System.Collections.Generic.List[pscustomobject]]::new()
    # Iterate through each ConfigSource item in the XML
    foreach ($item in $MDMData.MDMEnterpriseDiagnosticsReport.PolicyManager.ConfigSource)
    {
        $enrollmentID = $item.EnrollmentId
        
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
                                EnrollmentProvider = $script:enrollmentProviderIDs[$enrollmentID]
                                PolicyScope  =  $PolicyScopeName
                                PolicyScopeDisplay = if ($PolicyScopeName -eq 'Device') { $env:COMPUTERNAME } else { $userInfoHash[$PolicyScopeName] }
                                PolicyAreaName = $area.PolicyAreaName
                                SettingsCount = $propertyList.Count
                                Settings = $null
                            }

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
                # Add the tmpObj to the $outObj
                $outObj.Add($tmpObj)
            }
        }
    }

    return $outObj
}
#endregion

#region Get-IntuneWin32AppPolicies
function Get-IntuneWin32AppPolicies
{
    [CmdletBinding()]
    param 
    ()

    $Path = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload*.log"

    # Getting all AppWorkload and sorting them by LastWriteTime
    # This will make sure we have the latest entries at the first position in our array
    $logFiles = Get-ChildItem -Path $Path | Sort-Object -Property LastWriteTime -Descending

    $pattern = '<!\[LOG\[Get policies = \[\{(.*)\]LOG\]!>'

    # Get all policies with regex pattern filter
    $lines = $logFiles | Select-String -Pattern $pattern

    Foreach ($line in $lines[0])
    {
        # We need to add the chars "[{" to the beginning of the line to make it a valid JSON array 
        # since we made the not part of the regex pattern to only match policies with at least one app
        [array]$appList += "[{$($line.Matches.Groups[1].Value)" | ConvertFrom-Json -Depth 20
    }

    return ($appList | Sort-Object -Property Name)
}
#endregion


#region Get-LocalUserInfo
function Get-LocalUserInfo 
{
    $userHashTable = @{}

    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' |
    ForEach-Object {
        $sid = $_.PSChildName
        try 
        {
            $profilePath = (Get-ItemProperty $_.PSPath).ProfileImagePath
            $username = Split-Path -Leaf $profilePath
            $userHashTable[$sid] = $username
        } catch {
            $userHashTable[$sid] = 'Unknown'
        }
    }

    return $userHashTable
}
#endregion



#region Get-IntuneResourcePolicies
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
#endregion

#region Convert-FileTimeToDateTime 
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
#endregion

#region Get-IntuneMSIPolicies
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
#endregion

#region Get-IntunePolicyCurrentData
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
#edregion

#region Get-IntunePolicyMetadata
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
#endregion

#region Get-EnrollmentIDData
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
#endregion

#region Get-EnrollmentProviderIDs
function Get-EnrollmentProviderIDs
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $true)]
        $MDMData
    )
    
    $enrollmentHashTable = @{}
    foreach($enrollment in $MDMData.MDMEnterpriseDiagnosticsReport.Enrollments.Enrollment)
    {
        $providerID = $enrollment.ProviderID
        if ($enrollment.EnrollmentId -match '[a-fA-F0-9\-]{36}')
        {
            If([string]::IsNullOrEmpty($enrollment.ProviderID))
            {
                $providerID = 'Local'
            }
            elseif ($enrollment.ProviderID -eq 'MS DM Server')
            {
                $providerID = 'Intune'
            }
            $enrollmentHashTable[$enrollment.EnrollmentId] = $providerID
        }
        else 
        {
            # If the EnrollmentId is not in the expected format, skip it
            continue
        }
    }

    return $enrollmentHashTable
}
#endregion

#region Invoke-EscapeHtmlText
function Invoke-EscapeHtmlText 
{
    param ([string]$Text)
    return $Text -replace '&', '&amp;' `
                   -replace '<', '&lt;' `
                   -replace '>', '&gt;' `
                   -replace '"', '&quot;' `
                   -replace "'", '&#39;'
}
#endregion

#region Get-DeviceAndUserHTMLTables
Function Get-DeviceAndUserHTMLTables
{
    param
    (
        [Parameter(Mandatory = $true)]
        [array]$GroupedPolicies
    )

    $htmlBody = ""
    $selection = $GroupedPolicies.Where({($_.Name -eq 'Device') -or ($_.Name -match 'S-\d+(-\d+)+')})
    $deviceSelection = $GroupedPolicies.Where({ $_.Name -eq 'Device' })
    $userSelection = $GroupedPolicies.Where({ $_.Name -match 'S-\d+(-\d+)+' })
    foreach ($group in $selection) 
    {
        <#
        if (($group.Name -ne 'Device') -and ($group.Name -notmatch 'S-\d+(-\d+)+')) 
        {
            # Skip groups that are not 'Device' or do not match the SID pattern
            # We will add them later
            continue
        }
            #>

        if ($group.Name -eq 'Device') 
        { 
            $statString = "TotalPolicyAreas: {0}<br>TotalSettings: {1}" -f $deviceSelection.group.count, $deviceSelection.group.Settings.count

            if ([string]::IsNullOrEmpty($group.group[0].PolicyScopeDisplay)) 
            {
                $areaTitleString = '💻 Device: Unknown'
            }
            else 
            {
                $areaTitleString = '💻 Device: {0}' -f $group.group[0].PolicyScopeDisplay
            }
        } 
        else 
        { 
            $statString = "TotalPolicyAreas: {0}<br>TotalSettings: {1}" -f $userSelection.group.count, $userSelection.group.Settings.count

            if ([string]::IsNullOrEmpty($group.group[0].PolicyScopeDisplay)) 
            {
                $areaTitleString = '👤 {0}: Unknown'
            }
            else 
            {
                $areaTitleString = '👤 {0}: {1}' -f $group.Name, $group.group[0].PolicyScopeDisplay
            }
        }
        
        $htmlBody += "<div class='group-container'>"
        $htmlBody += "<h2>PolicyScope: <span class='policy-area-title'>$areaTitleString</span></h2>"
        $htmlBody += "<p Style='font-size: 13px;'>$statString</p>"
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
            $htmlBody += "<table style='margin-bottom: 10px; width: 100%; border-collapse: collapse; table-layout: fixed;'>"
            $htmlBody += "<tr><td style='font-weight: bold; width: 400px;'>EnrollmentId</td><td>$($policy.EnrollmentId) ➡️ $($policy.EnrollmentProvider)</td><td style='width: 200px;'></td></tr>"
            $htmlBody += "<tr style='border-top: 3px solid #ddd;'><th class='setting-col'>Setting 🛠️</th><th>Value</th><th style='width: 200px;'>WinningProvider</th></tr>"

            foreach ($settings in $policy.Settings) 
            {
                $global:Test1 = $settings
                $settingspath = 'Path or DLL of the setting: "{0}"' -f $settings.Metadata

                if ($settings.WinningProvider -eq 'Not set' -or [string]::IsNullOrEmpty($settings.WinningProvider)) 
                {
                    $winningProviderString = $policy.EnrollmentProvider
                } 
                else 
                {
                    $tmpValue = $script:enrollmentProviderIDs[$settings.WinningProvider]
                    if ($tmpValue) 
                    {
                        $winningProviderString = $tmpValue
                    }
                    else 
                    {
                        $winningProviderString = $settings.WinningProvider
                    }
                }

                if ($winningProviderString.Trim() -ne $policy.EnrollmentProvider.Trim()) 
                {
                    $winningProviderString = "ℹ️ $winningProviderString"
                } 

                #$value = Format-StringToXml -XmlString $settings.Value
                $value = Invoke-EscapeHtmlText -Text ($settings.Value)
                $htmlBody += "<tr><td class='setting-col'>$($settings.Name)</td><td title='$($settingspath)'>$value</td><td style='width: 200px;'>$winningProviderString</td></tr>"
            }

            $htmlBody += "</table>"
            #$htmlBody += "</div>"  # Close settings-container div
            $i++
        }
        $htmlBody += "</div>"  # Close collapsible-content
        $htmlBody += "</div>"  # Close group-container
    }

    return $htmlBody
}
#endregion

#region Get-EnterpriseApplicationHTMLTables
function Get-EnterpriseApplicationHTMLTables 
{
    param
    (
        [Parameter(Mandatory = $true)]
        [array]$GroupedPolicies
    )

    $htmlBody = ""

    $enterpriseAppGroup = $GroupedPolicies.Where({ $_.Name -eq 'EnterpriseDesktopAppManagement' })

    $areaTitleString = '📦 EnterpriseDesktopAppManagement'

    $htmlBody += "<div class='group-container'>"
    $htmlBody += "<h2>PolicyScope: <span class='policy-area-title'>$areaTitleString</span></h2>"
    $htmlBody += "<button class='toggle-button' onclick='toggleContent(this)'>Hide Details</button>"
    $htmlBody += "<div class='collapsible-content'>"

    foreach ($app in $enterpriseAppGroup.Group)
    {
        $possibleAppName = ($app.CurrentDownloadUrl | Split-Path -Leaf)

        $htmlBody += "<h2 class='policy-area-title'>App: $($possibleAppName)</h2>"
        $htmlBody += "<table style='margin-bottom: 10px; width: 100%; border-collapse: collapse;'>"

        # Let's exclude some properties that are not relevant for the report
        $excludedProperties = @('ActionType', 'AssignmentType', 'BITSJobId', 'JobStatusReport', 'PolicyScope', 'ServerAccountID', 'PackageId')

        foreach ($property in ($app.PSObject.Properties | Sort-Object -Property Name))
        {
            if ($property.Name -in $excludedProperties) 
            {
                continue
            }

            $value = Invoke-EscapeHtmlText -Text ($property.Value)
            $htmlBody += "<tr><td style='font-weight: bold; width: 400px;'>$($property.Name)</td><td>$value</td></tr>"
        }
        
        $htmlBody += "</table>"
        $htmlBody += "<br>"
    }
    $htmlBody += "</div>"  # Close collapsible-content
    $htmlBody += "</div>"  # Close group-container
    return $htmlBody
}
#endregion

#region Get-ResourceHTMLTables
Function Get-ResourceHTMLTables
{
    param
    (
        [Parameter(Mandatory = $true)]
        [array]$GroupedPolicies
    )

    $userInfoHash = Get-LocalUserInfo

    $resourcePolicies = $GroupedPolicies.Where({ $_.Name -eq 'Resource' }) 
    $groupedResources = $resourcePolicies.group | Group-Object -Property EnrollmentId, ResourceTarget
    
    $areaTitleString = '🌐 Resource Policies'

    $htmlBody = ""
    $htmlBody += "<div class='group-container'>"
    $htmlBody += "<h2>PolicyScope: <span class='policy-area-title'>$areaTitleString</span></h2>"
    $htmlBody += "<p Style='font-size: 13px;'>TotalResources: {0}</p>" -f $groupedResources.group.Count
    $htmlBody += "<button class='toggle-button' onclick='toggleContent(this)'>Hide Details</button>"
    $htmlBody += "<div class='collapsible-content'>"

    foreach ($resourceEntry in $groupedResources) 
    {
        # Split the EnrollmentId and ResourceTarget from a single string
        # The format is "EnrollmentId, ResourceTarget"
        $tmpSplitVar = $resourceEntry.Name -split ','

        $resourceTargetString = if($tmpSplitVar[1].ToString().Trim() -ieq 'Device') 
        { 

            '💻 Device - {0}' -f $env:COMPUTERNAME
        } 
        else 
        { 
            $userName = $userInfoHash[$tmpSplitVar[1].ToString().Trim()]
            if ([string]::IsNullOrEmpty($userName))
            {
                '👤 {0} - Unknown' -f ($tmpSplitVar[1].ToString().Trim())
            }
            else
            {
                '👤 {0} - {1}' -f ($tmpSplitVar[1].ToString().Trim()), $userName
            }
        }

        $enrollmentIdString = '{0} ➡️ {1}' -f ($tmpSplitVar[0].ToString().Trim()), $resourceEntry.Group[0].ProviderID

        $htmlBody += "<table style='margin-bottom: 10px; width: 100%; border-collapse: collapse;'>"
        $htmlBody += "<tr><td style='font-weight: bold; width: 400px;'>EnrollmentId</td><td  style='font-weight: bold;'>$($enrollmentIdString)</td></tr>"
        $htmlBody += "<tr><td style='font-weight: bold; width: 400px;'>ResourceTarget</td><td  style='font-weight: bold;'>$($resourceTargetString)</td></tr>"

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
    return $htmlBody
}
#enregion


#region Get-IntuneWin32AppTables
Function Get-IntuneWin32AppTables
{
    $win32Apps = Get-IntuneWin32AppPolicies

    $htmlBody = ""

    $areaTitleString = '🪟 Win32App Policies'

    $htmlBody = ""
    $htmlBody += "<div class='group-container'>"
    $htmlBody += "<h2>PolicyScope: <span class='policy-area-title'>$areaTitleString</span></h2>"
    $htmlBody += "<button class='toggle-button' onclick='toggleContent(this)'>Hide Details</button>"
    $htmlBody += "<div class='collapsible-content'>"

    $excludedProperties = @('DetectionRule', 'ExtendedRequirementRules', 'BITSJobId', 'JobStatusReport', 'PolicyScope', 'ServerAccountID', 'PackageId')

    foreach ($app in $win32Apps) {
        $htmlBody += "<h2 class='policy-area-title'>Win32App: $($app.Name)</h2>"
        $htmlBody += "<table>"
        foreach ($property in ($app.PSObject.Properties | Sort-Object -Property Name | Where-Object { $_.Name -notin $excludedProperties })) 
        {
            # Escape HTML characters in the property value
            
            $htmlBody += "<tr><td style='font-weight: bold; width: 300px;'>$($property.Name)</td><td>$($property.Value)</td></tr>"
        }
        $htmlBody += "</table>"
        $htmlBody += "<br>"
    }
    return $htmlBody
    $htmlBody += "</div>"  # Close collapsible-content
    $htmlBody += "</div>"  # Close group-container
}
#endregion

#region Get-DeviceInfoHTMLTables
Function Get-DeviceInfoHTMLTables
{
    param(
        [Parameter(Mandatory = $true)]
        [array]$GroupedPolicies
    )

    $htmlBody = ""

    $deviceInfoData = $GroupedPolicies.Where({ $_.Name -eq 'DeviceInfo' }) 

    $areaTitleString = 'ℹ️ Device Info'

    $htmlBody = ""
    $htmlBody += "<div class='group-container'>"
    $htmlBody += "<h2><span class='policy-area-title'>$areaTitleString</span></h2>"
    $htmlBody += "<button class='toggle-button' onclick='toggleContent(this)'>Hide Details</button>"
    $htmlBody += "<div class='collapsible-content'>"

    $deviceInfoObject = $deviceInfoData.group | Select-Object -Property `
        'PolicyScope',
        'Lastsync',
        'PCName',
        'Edition',
        'OSBuild',
        'Processor',
        'InstalledRAM',
        'SystemType',
        'Organization',
        'ActiveAccount',
        'ActiveSID',
        'Managedby',
        'Managementserveraddress',
        'ExchangeID',
        'UserToken'

    foreach ($device in $deviceInfoObject) 
    {
        $htmlBody += "<h2 class='policy-area-title'>Device: $($device.PCName)</h2>"
        $htmlBody += "<table>"
        foreach ($property in ($device.PSObject.Properties)) 
        {
            #skip properties that are not relevant for the report
            if ($property.Name -in @('PolicyScope', 'PCName')) 
            {
                continue
            }
            $htmlBody += "<tr><td style='font-weight: bold; width: 300px;'>$($property.Name)</td><td>$($property.Value)</td></tr>"
        }
        $htmlBody += "</table>"
        $htmlBody += "<br>"
    }

    $htmlBody += "</div>"  # Close collapsible-content
    $htmlBody += "</div>"  # Close group-container
    return $htmlBody
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
        h1 { font-size: 24px; color: #2E6DA4; }
        h2 { font-size: 18px; color: #444; margin-top: 10px; }

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
            font-size: 13px; 
        }

        th, td {
            border: 1px solid #ddd;
            padding: 8px;
            word-wrap: break-word;
            text-align: left;
            font-size: 13px; 
        }

        th.setting-col, td.setting-col { width: 150px; }
        th { background-color: #f2f2f2; text-align: left; }
        tr:nth-child(even) { background-color: #f9f9f9; }

        th.resource-col, td.resource-col { width: 100px; }
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

    $htmlBody += Get-DeviceInfoHTMLTables -GroupedPolicies $grouped

    $htmlBody += Get-DeviceAndUserHTMLTables -GroupedPolicies $grouped

    $htmlBody += Get-EnterpriseApplicationHTMLTables -GroupedPolicies $grouped

    $htmlBody += Get-ResourceHTMLTables -GroupedPolicies $grouped

    $htmlBody += Get-IntuneWin32AppTables

    $fullHtml = $htmlHeader + $htmlBody + $htmlFooter

    Set-Content -Path $OutputPath -Value $fullHtml -Encoding UTF8
}
#endregion


#region Format-StringToXml
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
#endregion



#region MAIN SCRIPT EXECUTION
#$userInfoHash = Get-LocalUserInfo
#$script:enrollmentProviderIDs = Get-EnrollmentProviderIDs -MDMData $xmlFile

$MDMDiagReportXml = Get-IntunePolicyDataFromXML -MDMDiagReportXmlPath $MDMDiagReportXmlPath
$MDMDiagReportHTMLPath = $MDMDiagReportXml.FileFullName -replace '.xml', '.html'

# Initialize a list to hold all Intune policies
$IntunePolicyList = [System.Collections.Generic.List[pscustomobject]]::new()

Get-IntunePolicySystemInfo -HtmlReportPath $MDMDiagReportHTMLPath | ForEach-Object {
    $IntunePolicyList.Add($_)
}

Get-IntuneDeviceAndUserPolicies -MDMData $MDMDiagReportXml.XMlFileData | ForEach-Object {
    $IntunePolicyList.Add($_)
}

Get-IntuneMSIPolicies -MDMData $MDMDiagReportXml.XMlFileData | ForEach-Object {
    $IntunePolicyList.Add($_)
}

Get-IntuneResourcePolicies -MDMData $MDMDiagReportXml.XMlFileData | ForEach-Object {
    $IntunePolicyList.Add($_)
}

# Convert the policies to HTML and save to the specified output path
Convert-IntunePoliciesToHtml -OutputPath "C:\Users\Public\Documents\IntunePolicyReport.html" -Policies $IntunePolicyList -Title "Intune Policy Report"

# Open the generated HTML report in Microsoft Edge
Start-Process "msedge.exe" -ArgumentList "C:\Users\Public\Documents\IntunePolicyReport.html"







