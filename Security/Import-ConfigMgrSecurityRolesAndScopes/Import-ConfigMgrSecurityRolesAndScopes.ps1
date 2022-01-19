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
    Script to import ConfigMgr security roles and configure administrative users
.DESCRIPTION
    Script to import ConfigMgr security roles and configure administrative users. Data based in a JSON definition file.
    JSON EXAMPLE:

    {"ConfigMgrRoleDefinition":{
        "AdministrativeUserList":
        [
        {
            "AdministrativeUser": "MEM_ADMIN",
            "DescriptiveName": "MEM Admin", 
            "CollectionList": [
                                "All Systems",
                                "All Users and User Groups"
                            ],
            "RoleList":       [
                                "Full Administrator"
                            ],
            "ScopeList":      [
                                "All"
                            ]
        }
        ]
        }
    }
.EXAMPLE
    .\Import-ConfigMgrSecurityRolesAndScopes.ps1
.EXAMPLE
    .\Import-ConfigMgrSecurityRolesAndScopes.ps1 -SiteCode "P01" -ProviderMachineName "server1.contoso.local" -Domain "CONTOSO\"
.PARAMETER SiteCode
    ConfigMgr SiteCode
.PARAMETER ProviderMachineName
    Name of the SMS Provider. Will use local system if nothing has been set.
.PARAMETER Domain
    Domain of administrative user with "\" at the end.
    Like "CONTOSO\" if the domain is contoso.local for example
    Should be part of the config file, but is a parameter at the moment. 
#>
param
(
    [Parameter(Mandatory=$false)]
    [string]$ProviderMachineName = $env:COMPUTERNAME,
    [Parameter(Mandatory=$true)]
    [string]$SiteCode,
    [Parameter(Mandatory=$true)]   
    [string]$Domain
)


$sourcefolder = $PSCommandPath | Split-Path -Parent

# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

[array]$listOfRoleFiles = Get-ChildItem -Path $sourcefolder -Filter "*.xml"


$roleDefinitionFileObject = Get-ChildItem (Split-Path -path $PSCommandPath) -Filter '*.json' | Select-Object Name, Length, LastWriteTime, FullName | Out-GridView -Title 'Choose a JSON configfile' -OutputMode Single
if (-NOT ($roleDefinitionFileObject))
{
    Write-Host 'Nothing selected. Stop.' -ForegroundColor Green
}
else
{
    $roleDefinitionFile = (Get-Content -Path ($roleDefinitionFileObject.FullName) -ErrorAction Stop) -join "`n" | ConvertFrom-Json -ErrorAction Stop
    if($roleDefinitionFile)
    {

        [array]$selectedAdministrativeUser = $roleDefinitionFile.ConfigMgrRoleDefinition.AdministrativeUserList | Out-GridView -Title 'Select administrative user' -OutputMode Multiple
        if(-NOT $selectedAdministrativeUser)
        {
            Write-Host "Nothing selected" -ForegroundColor Green
            break
        }


        $currentLocation = Get-Location
        # Set the current location to be the site code.
        Set-Location "$($SiteCode):\" @initParams

        # get all built-in roles, all scopes and all Users first
        Write-host "$(get-date -Format u) Getting AdministrativeUser, Custom Scopes and Roles from SCCM..." -ForegroundColor Green
        [array]$existingAdministrativeUsers = Get-CMAdministrativeUser
        [array]$existingRoles = Get-CMSecurityRole | Select-Object RoleName
        # create simple array
        $existingRoleList = @()
        $existingRoles.RoleName | ForEach-Object {
            $existingRoleList += $_
        }

        [array]$existingScopes = Get-CMSecurityScope | Select-Object CategoryName
        # create simple array
        $existingScopeList = @()
        $existingScopes.CategoryName | ForEach-Object {
            $existingScopeList += $_
        }

        $adSearchObject = New-Object DirectoryServices.DirectorySearcher # to be able to search for AD groups or users
        foreach($administrativeUser in $selectedAdministrativeUser)
        {

            $allChecksPassed = $true

            $adUserOrGroup = $administrativeUser.AdministrativeUser
            Write-host "$(get-date -Format u) `"$adUserOrGroup`"..." -ForegroundColor Cyan

            $domainAndUser = "{0}{1}" -f $Domain, $adUserOrGroup
            if ($existingAdministrativeUsers.where({$_.LogonName -eq "$domainAndUser"}))
            {
                Write-host "$(get-date -Format u)         User or Group: `"$adUserOrGroup`" exists in SCCM already. Delete first." -ForegroundColor Yellow
                $allChecksPassed = $false            
            }

            
            # validate group in AD
            $adSearchObject.Filter = "(&(|(objectCategory=group)(objectCategory=user))(|(sAMAccountName=$adUserOrGroup*)(name=$adUserOrGroup*)))"
            if (-NOT ($adSearchObject.FindOne()))
            {
                Write-host "$(get-date -Format u)         User or Group NOT found in AD: `"$adUserOrGroup`"" -ForegroundColor Yellow
                $allChecksPassed = $false  
            }
            else
            {
                Write-host "$(get-date -Format u)         User or Group found in AD: `"$adUserOrGroup`"" -ForegroundColor Green
            }


            Write-host "$(get-date -Format u)     Working on scope list: " -ForegroundColor Green
            ####### create scope in case not already there
            foreach($scope in $administrativeUser.ScopeList)
            {
                if ($existingScopeList.Contains($scope))
                {
                    Write-host "$(get-date -Format u)         Scope found: `"$scope`"" -ForegroundColor Green
                }
                else
                {
                    Write-host "$(get-date -Format u)         Scope NOT found: `"$scope`" Will create scope!" -ForegroundColor Green
                    $null = New-CMSecurityScope -Name $scope
                    $existingScopeList += $scope # add scope to existing scopes list
                }
            }
            #######
            
            <#
            ## Maybe automate to set scope for existing   

            # Get folder by NodeID
            $folderObject = Get-WmiObject -Namespace "root\sms\site_$SiteCode" -query "SELECT * FROM SMS_ObjectContainerNode CN WHERE CN.ContainerNodeID = '$ContainerNodeID'"
            
            # Get folder by collectionID
            $folderObject = Get-WmiObject -Namespace "root\sms\site_$SiteCode" -query "SELECT * FROM SMS_ObjectContainerItem OCI inner join SMS_ObjectContainerNode CN on CN.ContainerNodeID = OCI.ContainerNodeID WHERE OCI.instancekey = '$CollectionID'"

            # use "ParentContainerNodeID = 16777423" to get to the root folder

            #>

            Write-host "$(get-date -Format u)     Working on role list: " -ForegroundColor Green
            ####### Import security roles
            foreach($role in $administrativeUser.RoleList)
            {

                if ($existingRoleList.Contains($role))
                {
                    Write-host "$(get-date -Format u)         Role found: `"$role`"" -ForegroundColor Green
                }
                else
                {
                    $roleXMlItem = $listOfRoleFiles.Where({$_.Name -eq "$role.xml"})
                    if($roleXMlItem)
                    {
                        Write-host "$(get-date -Format u)         Role NOT found: `"$role`" Will import role!" -ForegroundColor Green
                        Write-host "$(get-date -Format u)         Role import of: $($roleXMlItem.FullName)" -ForegroundColor Green
                        Import-CMSecurityRole -Overwrite $true -XmlFileName $roleXMlItem.FullName     
                        $existingRoleList += $role            
                    }
                    else
                    {
                        Write-host "$(get-date -Format u)         No rolefile found! STOP" -ForegroundColor Yellow
                        $allChecksPassed = $false  
                    }
                }

            }
            #######

            ####### Check collection
            Write-host "$(get-date -Format u)     Working on collection list: " -ForegroundColor Green
            foreach($collection in $administrativeUser.CollectionList)
            {
                if(Get-CMCollection -Name $collection)
                {
                    Write-host "$(get-date -Format u)         Collection found: `"$($collection)`"" -ForegroundColor Green
                }
                else
                {
                    Write-host "$(get-date -Format u)         Collection not found! `"$($collection)`" STOP" -ForegroundColor Yellow
                    $allChecksPassed = $false  
                }
            }
            #######

            ####### Create administrative user
            if ($allChecksPassed)
            {
                Write-host "$(get-date -Format u)     Add new administraive user: `"$($administrativeUser.AdministrativeUser)`"" -ForegroundColor Green
                $newUser = $null
                $newUser = New-CMAdministrativeUser -Name "$($Domain)$($administrativeUser.AdministrativeUser)" -CollectionName ($administrativeUser.CollectionList) -RoleName ($administrativeUser.RoleList) -SecurityScopeName ($administrativeUser.ScopeList)
                if ($newUser)
                {
                    Write-host "$(get-date -Format u)     User added: `"$($newUser.LogonName)`"" -ForegroundColor Green
                }
            }
            else
            {
                Write-host "$(get-date -Format u)     User`"$($Domain)$($administrativeUser.AdministrativeUser)`" cannot be added. Fix above issues first." -ForegroundColor Yellow            
            }
            #######
        
        }
        $adSearchObject = $null
        Set-Location ($currentLocation.Path)

    }

    Write-host "$(get-date -Format u)     Don't forget to set the correct scopes on already existing items such as: Distribution Points and the Site itself" -ForegroundColor Cyan
    Write-host "$(get-date -Format u)     Each folder a Collection or App etc is part of" -ForegroundColor Cyan
    Write-host "$(get-date -Format u)     Distribution Points" -ForegroundColor Cyan
    Write-host "$(get-date -Format u)     The Site itself" -ForegroundColor Cyan

}


