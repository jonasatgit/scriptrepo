 
<# 
.SYNOPSIS
    Script to get the assignment information for all the Intune objects

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

    This script will get the assignment information for all the Intune objects

#>

Install-Module Microsoft.Graph.Authentication -Force -AllowClobber

Connect-MgGraph 

$baseURI = "https://graph.microsoft.com/beta"

$endpointList = @('/deviceManagement/configurationpolicies?$select=id,name&$expand=assignments',
'/deviceAppManagement/mobileApps?$filter=isAssigned eq true&$select=id,displayName&$expand=assignments', # Only get assigned apps to limit output
#'/deviceAppManagement/mobileApps?$select=id,displayName&$expand=assignments', # Output all apps (assigned and not assigned)
'/deviceManagement/deviceConfigurations?$select=id,displayName&$expand=assignments',
'/deviceManagement/groupPolicyConfigurations?$select=id,displayName&$expand=assignments',
'/deviceManagement/compliancePolicies?$select=id,name&$expand=assignments',
'/deviceManagement/deviceCompliancePolicies?$select=id,displayName&$expand=assignments',
'/deviceManagement/deviceManagementScripts?$select=id,displayName&$expand=assignments',
'/deviceManagement/deviceHealthScripts?$select=id,displayName&$expand=assignments',
# /deviceAppManagement/managedAppPolicies
# managedAppPolicies are platform specific, so we need to query them separately
'/deviceAppManagement/windowsManagedAppProtections?$select=id,displayName&$expand=assignments',
'/deviceAppManagement/androidManagedAppProtections?$select=id,displayName&$expand=assignments'
'/deviceAppManagement/iosManagedAppProtections?$select=id,displayName&$expand=assignments',
# App configurations
'/deviceAppManagement/targetedManagedAppConfigurations?$count=true&$select=id,displayName&$expand=assignments', # count=true is required otherwise we will get nothing
'/deviceAppManagement/mobileAppConfigurations?$select=id,displayName&$expand=assignments'
)


#$endpointList = @('/deviceAppManagement/mobileApps?$select=id,displayName&$expand=assignments&$top=100')


# Getting all filters to add info to the output. Store filters in hashtable with Id as key and name as value
$filters = @{}
$filtersEndpoint = '{0}/deviceManagement/assignmentFilters' -f $baseURI
$filtersResult = Invoke-GraphRequest -Method Get -Uri $filtersEndpoint -OutputType PSObject
foreach($filter in $filtersResult.value)
{
    $filters.Add($filter.id, $filter.displayName)
}

$out = @()
foreach($endpoint in $endpointList)
{
    $endpoint = '{0}{1}' -f $baseURI, $endpoint
 
    $graphCallResult = Invoke-GraphRequest -Method Get -Uri $endpoint -OutputType PSObject
    $pattern = "^.*\/(.*?)\?.*$"
    Write-Host "Found $($graphCallResult.value.Count) objects for endpoint: `"$($endpoint -replace $pattern, '$1')`""
    $out += $graphCallResult.value     

    # Paging if required
    if (-Not([string]::IsNullOrEmpty($graphCallResult.'@odata.nextLink')))
    {
        do
        {
            $graphCallResult = Invoke-GraphRequest -Method Get -Uri $graphCallResult.'@odata.nextLink' -OutputType PSObject
            Write-Host "Found $($graphCallResult.value.Count) objects for endpoint: `"$($endpoint -replace $pattern, '$1')`""
            $out += $graphCallResult.value 
        } 
        until ($null -eq $graphCallResult.'@odata.nextLink' -or [string]::IsNullOrEmpty($graphCallResult.'@odata.nextLink'))
    }  
}

$outObject = [System.Collections.Generic.List[pscustomobject]]::new()
foreach($item in $out)
{
    $alreadyAdded = $false
    # Get the type of the object
    if (-NOT ([string]::IsNullOrEmpty($item.'@odata.type')))
    {
        $type = $item.'@odata.type' -replace "#microsoft.graph."
    }
    elseif (-NOT ([string]::IsNullOrEmpty($item.'assignments@odata.context')))
    {
        # extract type from URL via regex. Example: "https://graph.microsoft.com/beta/$metadata#deviceAppManagement/iosManagedAppProtections('T_5580159c-6e7c-43b2-a8a3-a2338e49fbe8')/assignments"
        # type = 'iosManagedAppProtections'
        $matches = $null
        $null = $item.'assignments@odata.context' -match '\/([^\/\(]+)\('
        $type = $matches[1]
    }
    else
    {
        $type = 'Unknown'
    }

    $tmpObj = [pscustomobject]@{
        Id = $item.id
        Type = $type
        Name = $item.name
        DisplayName = $item.displayName
        Intent = $null
        AssignmentCount = $item.assignments.Count
        FilterType = $null
        FilterName = $null
        AssignmentType = $null
        GroupID = $null
    }

    $i =  0
    foreach ($assignment in $item.assignments)
    {
        # Get the filter name if we have a filter
        if ([string]::IsNullOrEmpty($assignment.target.deviceAndAppManagementAssignmentFilterId))
        {
            $filterName = $null
        }
        else
        {
            $filterName = $filters[$assignment.target.deviceAndAppManagementAssignmentFilterId]
        }
        # If we have only one assignment, we can use the same object
        # We will also use the same oject if its the first assignment, to avoid creating dupicates
        if ($i -eq 0)
        {
            $tmpObj.Intent = $assignment.intent
            $tmpObj.FilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType   
            $tmpObj.FilterName = $filterName      
            $tmpObj.AssignmentType = $assignment.target.'@odata.type' -replace "#microsoft.graph."
            $tmpObj.GroupID = $assignment.target.groupId
            $outObject.Add($tmpObj)
            $alreadyAdded = $true
        }
        else
        {
            # If we have multiple assignments, we need to create a new object for each assignment
            $outObject.Add([pscustomobject]@{
                Id = $item.id
                Type = $type
                Name = $item.name
                DisplayName = $item.displayName
                Intent = $assignment.intent
                AssignmentCount = $item.assignments.Count
                FilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
                FilterName = $filterName
                AssignmentType = $assignment.target.'@odata.type' -replace "#microsoft.graph."
                GroupID = $assignment.target.groupId
            })
            $alreadyAdded
        }
        $i++
    } # end foreach assignment

    # If we have no assignments, we need to add the object
    if ($alreadyAdded -eq $false) 
    {
        $outObject.Add($tmpObj)
    }
}
$outObject | Format-Table -AutoSize 
#$out | ConvertTo-Json -Depth 10 | Out-File -FilePath "C:\temp\AssignmentInfo.json" -Force
