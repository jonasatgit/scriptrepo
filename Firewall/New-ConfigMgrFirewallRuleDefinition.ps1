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
# Source: https://github.com/jonasatgit/scriptrepo

<#
.SYNOPSIS
Script to create Windows Firewall Rules based in a JSON definition file for ConfigMgr environments

.DESCRIPTION
Script to create Windows Firewall Rules based in a JSON definition file for ConfigMgr environments.
The script can export ConfigMgr environment information with parameter "ExportConfigMgrSystemRoleInformation"
and will merge the exported data with data from its default config file "Default-FirewallConfig.json".
The file can then be used to either show the required rules and PowerShell commands, set the rules locally or 
add the rules to an existing group policy object. 
It has six main operational modes via parameters:
    #1 Export ConfigMgr site and hierarchy information and create a new JSON file
        (-Export ConfigMgrSystemRoleInformation)
    #2 Show exported or example configuration from JSON file
        (-ShowConfig)
    #3 Show PowerShell commands to set firewall rules 
        (-ShowCommands) <-- Default parameter if started without parameters
    #4 Show PowerShell commands to import firewall rules into a group policy 
        (-ShowGPOCommands)
    #5 Add firewall rules locally 
        (-AddRulesLocally)
    #6 Add firewall rules to group policy 
        (-AddRulesToGPO)

.INPUTS
JSON file can be selected via grid view prompt

.OUTPUTS
Grid view

.EXAMPLE
.\New-ConfigMgrFirewallRuleDefinition.ps1 -ExportConfigMgrSystemRoleInformation -ProviderMachineName cm02.contoso.local -SiteCode P02

.EXAMPLE
.\New-ConfigMgrFirewallRuleDefinition.ps1 -ShowCommands -MergeSimilarRules

.EXAMPLE
.\New-ConfigMgrFirewallRuleDefinition.ps1

.PARAMETER DestinationSystemFQDN
Optional: Can be used to generate rules for a specific system. Fqdn format: name.domain.suffix 
If not used, a grid view will open from which a system can be chosen

.PARAMETER DefinitionFilePath
Optional: Path to a JSON definition file. 
If not used, a grid view will open from which a file can be chosen

.PARAMETER GroupSuffix
Optional: Suffix to a firewall group. The group name is part of the JSON definition file

.PARAMETER UseAnyAsLocalAddress
Optional: Will set the local address to ANY instead of the actual local IP address of a system
Helpful if a firewall GPO should work for multiple systems instead of just for one with a specific IP address 

.PARAMETER ValidRulesOnly
Optional: Will only show rules with status OK

.PARAMETER MergeSimilarRules
Optional: Will merge similar rules based on direction, protocol, port and program

.PARAMETER IPType
Optional: Can be used the either export IPv4, IPv6 or both types of IP addresses

.PARAMETER ShowConfig
Optional: Will only show the contents of a JSON definition file and not rules for a specific system

.PARAMETER ShowCommands
Optional: Will output rules and PowerShell commands for a selected target system in a grid view. 
The PowerShell commands can be copied

.PARAMETER ShowGPOCommands
Optional: The same as with "ShowCommands" but with the parameters to import the rules into a GPO
Requires: "DomainName" and "GPOName" to be set. (GPO must exist)

.PARAMETER AddRulesLocally
Optional: Will set selected rules locally

.PARAMETER AddRulesToGPO
Optional: Wll add rules to a GPO

.PARAMETER DomainName
Optional: Name of a domain a GPO exists in 

.PARAMETER GPOName
Optional: Name of a GPO which exists in a domain

.PARAMETER ExportConfigMgrSystemRoleInformation
Optional: Will export ConfigMgr environment information into a new JSON configuration file
Requires: "ProviderMachineName" and "SiteCode"

.PARAMETER ProviderMachineName
Optional: ConfigMgr SMS Provider machine name to be able to export data from ConfigMgr

.PARAMETER SiteCode
Optional: Site code of ConfigMgr site

.PARAMETER CreateOutboundRuleForeachInboundRule
Optional: To create outbound rule for each calculated inbound rule. Not quite tested and more experimental

.PARAMETER ExportToCsv
Optional: Switch that enables CSV export of the rules selected in the grid view.
If -CsvExportPath is also provided, that path is used. Otherwise a CSV file is created automatically in the
script folder using the loaded JSON definition file name plus a datetime suffix (same naming scheme used by
-ExportConfigMgrSystemRoleInformation).

.PARAMETER CsvExportPath
Optional: Full path to a .csv file. If set, the rules selected in the grid view are exported to this CSV file
(implies -ExportToCsv, so the switch is not required when an explicit path is given).
The file uses ";" as the delimiter (so the comma-separated IP-address lists are kept in one cell) and includes a
leading "sep=;" hint so Excel detects the delimiter automatically on any locale.

.LINK
https://github.com/jonasatgit/scriptrepo

#>

[CmdletBinding(DefaultParametersetName='ShowCommands')]
param
(
    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$false)]
    [parameter(ParameterSetName = 'AddRulesLocally',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowCommands',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowConfig',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [string]$DefinitionFilePath,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$false)]
    [parameter(ParameterSetName = 'AddRulesLocally',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowCommands',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [string[]]$DestinationSystemFQDN,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$false)]
    [parameter(ParameterSetName = 'AddRulesLocally',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowCommands',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [string]$GroupSuffix,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$false)]
    [parameter(ParameterSetName = 'AddRulesLocally',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowCommands',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [switch]$UseAnyAsLocalAddress,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$false)]
    [parameter(ParameterSetName = 'AddRulesLocally',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowCommands',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [switch]$ValidRulesOnly,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$false)]
    [parameter(ParameterSetName = 'AddRulesLocally',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowCommands',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [switch]$MergeSimilarRules,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$false)]
    [parameter(ParameterSetName = 'AddRulesLocally',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowCommands',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [switch]$CreateOutboundRuleForeachInboundRule,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$false)]
    [parameter(ParameterSetName = 'AddRulesLocally',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowCommands',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [ValidateSet("IPv4","IPv6","All")]
    [string]$IPType = "IPv4",

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$false)]
    [parameter(ParameterSetName = 'AddRulesLocally',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowCommands',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$false)]
    [switch]$ExportToCsv,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$false)]
    [parameter(ParameterSetName = 'AddRulesLocally',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowCommands',Mandatory=$false)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$false)]
    [string]$CsvExportPath,

    [parameter(ParameterSetName = 'ShowConfig',Mandatory=$true)]
    [switch]$ShowConfig,

    [parameter(ParameterSetName = 'ShowCommands',Mandatory=$false)]
    [switch]$ShowCommands,

    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [switch]$ShowGPOCommands,

    [parameter(ParameterSetName = 'AddRulesLocally',Mandatory=$true)]
    [switch]$AddRulesLocally,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$true)]
    [switch]$AddRulesToGPO,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$true)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [string]$DomainName,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$true)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [string]$GPOName,

    [parameter(ParameterSetName = 'ExportConfigMgrSystemRoleInformation',Mandatory=$true)]
    [switch]$ExportConfigMgrSystemRoleInformation,

    [parameter(ParameterSetName = 'ExportConfigMgrSystemRoleInformation',Mandatory=$true)]
    [string]$ProviderMachineName,

    [parameter(ParameterSetName = 'ExportConfigMgrSystemRoleInformation',Mandatory=$true)]
    [string]$SiteCode
)


<#
.SYNOPSIS
    Simple function to compare two arrays
#>
function Compare-TwoArrays 
{
    param
    (
        [parameter(Mandatory=$true)]
        [array]$ArrayReference,
        [parameter(Mandatory=$true)]
        [array]$ArrayDifference
    )

    foreach ($item in $ArrayDifference)
    {
        if ($ArrayReference -contains $item)
        {
            return $true
        }
    }
    return $false
}


<#
.SYNOPSIS
    Function to export ConfigMgr site server information into a JSON file
#>
Function Export-SystemRoleInformation
{
    param
    (
        [parameter(Mandatory=$true)]
        [string]$ProviderMachineName,
        [parameter(Mandatory=$true)]
        [string]$SiteCode,
        [parameter(Mandatory=$true)]
        [string]$OutputFilePath,
        [parameter(Mandatory=$false)]
        [string]$DefaultConfigFile = '{0}\Default-FirewallRuleConfig.json' -f $PSScriptRoot,
        [parameter(Mandatory=$false)]
        [ValidateSet("IPv4","IPv6","All")]
        [string]$IPType = "IPv4"
    )
  
    
    if (-NOT (Test-Path $DefaultConfigFile))
    {
        Write-host "$(Get-date -Format u): Default Firewall config file not found. Output will only contain some example rules: `"$($DefaultConfigFile)`"" -ForegroundColor Yellow
    }
    else
    {
        $defaultDefinition = Get-Content $DefaultConfigFile | ConvertFrom-Json
    }

    $siteSystems = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -Query "SELECT * FROM SMS_SCI_SysResUse WHERE NALType = 'Windows NT Server'" -ErrorAction Stop
    if (-not ($siteSystems))
    {
        Write-host "$(Get-date -Format u): No site systems found" -ForegroundColor Yellow
        exit
    }

    # getting sitecode and parent to have hierarchy information
    $siteCodeHash = @{}
    $siteCodeInfo = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -ClassName SMS_SCI_SiteDefinition -ErrorAction Stop
    $siteCodeInfo | ForEach-Object {   
        if ([string]::IsNullOrEmpty($_.ParentSiteCode))
        {
            $siteCodeHash.Add($_.SiteCode,$_.SiteCode)
        }
        else
        {
            $siteCodeHash.Add($_.SiteCode,$_.ParentSiteCode)
        }
    }

    Function Get-IPAddressFromName
    {
        param
        (
            [string]$SystemName,
            [ValidateSet("IPv4","IPv6","All")]
            [string]$Type = "IPv4"
        )
        
        $LocalSystemIPAddressList = @()
        $dnsObject = Resolve-DnsName -Name $systemName -ErrorAction SilentlyContinue
        if ($dnsObject)
        {
            switch ($Type) 
            {
                "All" {$LocalSystemIPAddressList += ($dnsObject).IPAddress}
                "IPv4" {$LocalSystemIPAddressList += ($dnsObject | Where-Object {$_.Type -eq 'A'}).IPAddress}
                "IPv6" {$LocalSystemIPAddressList += ($dnsObject | Where-Object {$_.Type -eq 'AAAA'}).IPAddress}
            }
            return $LocalSystemIPAddressList
        }
    }

    # Get a list of all site servers and their sitecodes 
    $siteCodeHashTable = @{}
    $sqlRoleHashTable = @{}
    $siteServerTypes = $siteSystems | Where-Object {$_.Type -in (1,2,4) -and $_.RoleName -eq 'SMS Site Server'}
    $siteServerTypes | ForEach-Object {
    
        switch ($_.Type)
        {
            1 
            {
                $siteHashValue = 'SecondarySite'
                $sqlHashValue = 'SECSQLServerRole'
            }
            
            2 
            {
                $siteHashValue = 'PrimarySite'
                $sqlHashValue = 'PRISQLServerRole'
            }
            
            4 
            {
                $siteHashValue = 'CentralAdministrationSite'
                $sqlHashValue = 'CASSQLServerRole'
            }
            #8 {'NotCoLocatedWithSiteServer'}
        }

        $siteCodeHashTable.Add($_.SiteCode, $siteHashValue)
        $sqlRoleHashTable.Add($_.SiteCode, $sqlHashValue)
    }
    
    
    $outObject = New-Object System.Collections.ArrayList
    foreach ($system in $siteSystems)
    {
        switch ($system.RoleName)
        {
            'SMS SQL Server' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = $sqlRoleHashTable[$system.SiteCode] # specific role like PRI, CAS, SEC or WSUS SQL 
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)

                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'SQLServerRole'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Site Server' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = $siteCodeHashTable[$system.SiteCode] # specific role like PRI, CAS or SEC
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)

                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'SiteServer'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)

            }
            'SMS Provider' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'SMSProvider'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Software Update Point' 
            {
                if ($siteCodeHashTable[$system.SiteCode] -eq 'CentralAdministrationSite')
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'CentralSoftwareUpdatePoint'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)                
                }

                if ($siteCodeHashTable[$system.SiteCode] -eq 'SecondarySite')
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'SecondarySoftwareUpdatePoint'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)                
                }
                else
                {             
                    $useParentWSUS = $system.Props | Where-Object {$_.PropertyName -eq 'UseParentWSUS'}
                    if ($useParentWSUS.Value -eq 1)
                    {
                        $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                        $tmpObj.Role = 'PrimarySoftwareUpdatePoint'
                        $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                        $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                        $tmpObj.SiteCode = $system.SiteCode
                        $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                        [void]$outObject.Add($tmpObj)
                    }
                }

                $supSQLServer = $system.Props | Where-Object {$_.PropertyName -eq 'DBServerName'}
                if (-NOT ([string]::IsNullOrEmpty($supSQLServer.Value2)))
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'SUPSQLServerRole'
                  
                    $systemNameFromNetworkOSPath = $system.NetworkOSPath -replace '\\\\'
                    [array]$dbServerName = $supSQLServer.Value2 -split '\\' # extract servername from server\instancename string
                    # making sure we have a FQDN
                    if ($systemNameFromNetworkOSPath -like "$($dbServerName[0])*")
                    {
                        $tmpObj.FullQualifiedDomainName = $systemNameFromNetworkOSPath
                    }
                    else 
                    {
                        if ($dbServerName[0] -notmatch '\.') # in case we don't have a FQDN, create one based on the FQDN of the initial system  
                        {
                            [array]$fqdnSplit =  $systemNameFromNetworkOSPath -split '\.' # split FQDN to easily replace hostname
                            $fqdnSplit[0] = $dbServerName[0] # replace hostname
                            $tmpObj.FullQualifiedDomainName = $fqdnSplit -join '.' # join back to FQDN
                        }   
                        else 
                        {
                            $tmpObj.FullQualifiedDomainName = $dbServerName[0] 
                        }              
                    }
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)                    
                }
                
                
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'SoftwareUpdatePoint'            
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)

                Write-host "$(Get-date -Format u): If SUSDB of: `"$($tmpObj.FullQualifiedDomainName)`" is hosted on a SQL cluster, make sure to add each cluster node to the JSON config with role `"SUPSQLServerRole`" " -ForegroundColor Yellow

            }
            'SMS Endpoint Protection Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'EndpointProtectionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Distribution Point' 
            {

                $isPXE = $system.Props | Where-Object {$_.PropertyName -eq 'IsPXE'}
                if ($isPXE.Value -eq 1)
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'DistributionPointPXE'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)                
                }

                $isPullDP = $system.Props | Where-Object {$_.PropertyName -eq 'IsPullDP'}
                if ($isPullDP.Value -eq 1)
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                    $tmpObj.Role = 'PullDistributionPoint'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                    [void]$outObject.Add($tmpObj)
    
                    $pullSources = $system.PropLists | Where-Object {$_.PropertyListName -eq 'SourceDistributionPoints'}
                    if (-NOT $pullSources)
                    {
                        Write-host "$(Get-date -Format u): No DP sources found for PullDP" -ForegroundColor Yellow
                    }
                    else
                    {
    
                        $pullSources.Values | ForEach-Object {
                                $Matches = $null
                                $retVal = $_ -match '(DISPLAY=\\\\)(.+)(\\")'
                                if ($retVal)
                                {
                                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                                    $tmpObj.Role = 'PullDistributionPointSource'
                                    $tmpObj.FullQualifiedDomainName = ($Matches[2])
                                    $tmpObj.PullDistributionPointToSource = $system.NetworkOSPath -replace '\\\\'
                                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($Matches[2]) -Type $IPType
                                    $tmpObj.SiteCode = $system.SiteCode
                                    $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                                    [void]$outObject.Add($tmpObj)
                                }
                                else
                                {
                                    Write-host "$(Get-date -Format u): No DP sources found for PullDP" -ForegroundColor Yellow
                                }
                            }
                    }
                }
    
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'DistributionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Management Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'ManagementPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS SRS Reporting Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'ReportingServicePoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Dmp Connector' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'ServiceConnectionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'Data Warehouse Service Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'DataWarehouseServicePoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Cloud Proxy Connector' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'CMGConnectionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS State Migration Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'StateMigrationPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Fallback Status Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'FallbackStatusPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            'SMS Component Server' 
            {
                # Skip role since no firewall rule diretly tied to it
            }
            'SMS Site System' 
            {
                # Skip role since no firewall rule diretly tied to it
            }
            'SMS Notification Server' 
            {
                # Skip role since no firewall rule diretly tied to it
            }
            <#
            'SMS Certificate Registration Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode, ParentSiteCode, PullDistributionPointToSource
                $tmpObj.Role = 'CertificateRegistrationPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                $tmpObj.ParentSiteCode = $siteCodeHash[$system.SiteCode]
                [void]$outObject.Add($tmpObj)
            }
            #>
            Default 
            {
                Write-host "$(Get-date -Format u): Role `"$($system.RoleName)`" not supported by the script at the moment. Create you own firewallrules and definitions in the config file if desired." -ForegroundColor Yellow
            }
    
            <# still missing
                SMS Device Management Point
                SMS Multicast Service Point
                SMS AMT Service Point
                AI Update Service Point
                SMS Enrollment Server
                SMS Enrollment Web Site            
                SMS DM Enrollment Service
            #>
    
        }
    }
    
    # group roles by system to have a by system list
    $systemsArrayList = New-Object System.Collections.ArrayList
    foreach ($itemGroup in ($outObject | Group-Object -Property FullQualifiedDomainName))
    {
        $roleList = @()
        $pullDPList = @()
        foreach ($item in $itemGroup.Group)
        {
            $roleList += $item.Role
            if (-NOT ([string]::IsNullOrEmpty($item.PullDistributionPointToSource)))
            {
                $pullDPList += $item.PullDistributionPointToSource
            }
        }
        [array]$roleList = $roleList | Select-Object -Unique
        [array]$pullDPList = $pullDPList | Select-Object -Unique
    
        $itemList = [ordered]@{
            FullQualifiedDomainName = $itemGroup.Name
            IPAddress = $itemGroup.Group[0].IPAddress -join ','
            SiteCode = $itemGroup.Group[0].SiteCode
            ParentSiteCode = $itemGroup.Group[0].ParentSiteCode
            Description = ""
            RoleList = $roleList
            PullDistributionPointToSourceList = $pullDPList
        }
      
        [void]$systemsArrayList.Add($itemList)
    }
        
    $tmpObjRuleDefinition = New-Object pscustomobject | Select-Object FirewallRuleDefinition
    $tmpObjDefinitions = New-Object pscustomobject | Select-Object SystemAndRoleList, RuleDefinition, ServiceDefinition
    
    # Example Rule Definition
    $tmpRuleArrayList = New-Object System.Collections.ArrayList
    $servicesList = @("RPC","RPCUDP","RPCServicesDynamic","HTTPS")
    $exampleRule = [ordered]@{
                RuleName = "ConfigMgr Console to SMS provider"
                Source = "ConfigMgrConsole"
                Destination = "SiteServer"
                Direction = "Inbound"
                Action = "Allow"
                Profile = "Any"
                Group = "ConfigMgr"
                Description = "Console to WMI SMS provider connection. HTTPS for AdminService"
                Services = $servicesList
            }
    [void]$tmpRuleArrayList.Add($exampleRule)
    
    $tmpServiceArrayList = New-Object System.Collections.ArrayList
    # Example Service Definition
    $exampleService = [ordered]@{
                Name = "RPC"
                Protocol = "TCP"
                Port = "RPCEPMAP"
                Program = "%systemroot%\system32\svchost.exe"
                Description = "RPC Endpoint Mapper"
            }
    [void]$tmpServiceArrayList.Add($exampleService)
    
    # Example Service Definition
    $exampleService = [ordered]@{
                Name = "HTTPS"
                Protocol = "TCP"
                Port = "443"
                Program = ""
                Description = "Https"
            }
    [void]$tmpServiceArrayList.Add($exampleService)
    
    if ($defaultDefinition)
    {
        # build object for JSON output using default config file as reference
        $tmpObjDefinitions.SystemAndRoleList = $systemsArrayList
        $tmpObjDefinitions.RuleDefinition = $defaultDefinition.FirewallRuleDefinition.RuleDefinition
        $tmpObjDefinitions.ServiceDefinition = $defaultDefinition.FirewallRuleDefinition.ServiceDefinition
        $tmpObjRuleDefinition.FirewallRuleDefinition = $tmpObjDefinitions
    }
    else
    {
        # build object for JSON output
        $tmpObjDefinitions.SystemAndRoleList = $systemsArrayList
        $tmpObjDefinitions.RuleDefinition = $tmpRuleArrayList
        $tmpObjDefinitions.ServiceDefinition = $tmpServiceArrayList
        $tmpObjRuleDefinition.FirewallRuleDefinition = $tmpObjDefinitions
    }
    
    $tmpObjRuleDefinition | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFilePath
    Write-host "$(Get-date -Format u): Data exported to: `"$OutputFilePath`"" -ForegroundColor Green
}



Function Get-IPAddressFromName
{
    param
    (
        [string]$SystemName,
        [ValidateSet("IPv4","IPv6","All")]
        [string]$Type = "IPv4"
    )
    
    $LocalSystemIPAddressList = @()
    $dnsObject = Resolve-DnsName -Name $systemName -ErrorAction SilentlyContinue
    if ($dnsObject)
    {
        switch ($Type) 
        {
            "All" {$LocalSystemIPAddressList += ($dnsObject).IPAddress}
            "IPv4" {$LocalSystemIPAddressList += ($dnsObject | Where-Object {$_.Type -eq 'A'}).IPAddress}
            "IPv6" {$LocalSystemIPAddressList += ($dnsObject | Where-Object {$_.Type -eq 'AAAA'}).IPAddress}
        }
        return $LocalSystemIPAddressList
    }
}

function Get-LocalSystemFQDN
{
    $win32Computersystem = Get-WmiObject -Class win32_computersystem -ErrorAction SilentlyContinue
    if ($win32Computersystem)
    {
        $systemName = '{0}.{1}' -f $win32Computersystem.Name, $win32Computersystem.Domain   
    }
    else
    {
        $systemName = $env:COMPUTERNAME
    }
    return $systemName
}

#region MAIN SCRIPT

if (-NOT ($ShowConfig -or $ShowCommands -or $ShowGPOCommands -or $AddRulesLocally -or $AddRulesToGPO -or $ExportConfigMgrSystemRoleInformation))
{
    $ShowCommands = $true    
}

[string]$scriptName = ($MyInvocation.MyCommand.Name) -replace '.ps1', ''
[string]$exportFileName = '{0}\{1}-Config-{2}.json' -f $PSScriptRoot, $scriptName, ((Get-Date -Format u) -replace '-|:|Z' -replace ' ', '_')

if ($ExportConfigMgrSystemRoleInformation)
{
    if (([string]::IsNullOrEmpty($ProviderMachineName)) -or ([string]::IsNullOrEmpty($SiteCode)))
    {
        Write-Host "$(Get-date -Format u): ProviderMachineName or SiteCode parameter missing" -ForegroundColor Yellow
        break
    }

    Export-SystemRoleInformation -ProviderMachineName $ProviderMachineName -SiteCode $SiteCode -OutputFilePath $exportFileName
    break
}

# getting config file 
[string]$loadedDefinitionFilePath = $null
if ($DefinitionFilePath)
{
    $DefinitionFile = Get-Content $DefinitionFilePath | ConvertFrom-Json
    $loadedDefinitionFilePath = $DefinitionFilePath
}
else 
{
    $DefinitionFileSelection = Get-ChildItem (Split-Path -path $PSCommandPath) -Filter '*.json' | Select-Object Name, Length, LastWriteTime, FullName | Out-GridView -Title 'STEP 1: Choose a JSON configfile' -OutputMode Single
    if (-NOT($DefinitionFileSelection))
    {
        exit
    }
    else 
    {
        $DefinitionFile = Get-Content $DefinitionFileSelection.FullName | ConvertFrom-Json
        $loadedDefinitionFilePath = $DefinitionFileSelection.FullName
    }
}


if ($ShowConfig)
{
    $DefinitionFile.FirewallRuleDefinition.SystemAndRoleList | Out-GridView -Title 'System-Definition'
    $DefinitionFile.FirewallRuleDefinition.RuleDefinition | Out-GridView -Title 'Firewallrule-Definition'
    $DefinitionFile.FirewallRuleDefinition.ServiceDefinition | Out-GridView -Title 'Service-Definition'
    Exit
}

# Validate if each system has a sitecode since we need one to determin which system belogs to which hierarchy
$systemsWithoutSiteCode = $DefinitionFile.FirewallRuleDefinition.SystemAndRoleList.Where({[string]::IsNullOrEmpty($_.SiteCode) -eq $true})
if ($systemsWithoutSiteCode)
{
    foreach ($system in $systemsWithoutSiteCode)
    {
        Write-Host "$(Get-date -Format u): WARNING: System $($system.FullQualifiedDomainName) has no sitecode set. Stopping script since that is a requirement" -ForegroundColor Yellow
    }
    Exit
}

# getting system if parameter is not set
if (-NOT $DestinationSystemFQDN -or $DestinationSystemFQDN.Count -eq 0)
{
    $selectResult = $DefinitionFile.FirewallRuleDefinition.SystemAndRoleList | Out-GridView -Title 'Choose one or more systems you want firewall rules for (use Ctrl/Shift to select multiple)' -OutputMode Multiple
    if ($selectResult)
    {
        [string[]]$DestinationSystemFQDN = @($selectResult.FullQualifiedDomainName)
    }
    else
    {
        Write-Host "$(Get-date -Format u): Nothing selected!" -ForegroundColor Green
        exit        
    }
}

# Create new group suffix for rule versioning
if ([string]::IsNullOrEmpty($GroupSuffix))
{
    $ruleGroupSuffix = (Get-Date -Format u) -replace '-|:|Z' -replace ' ', '_'
}
else
{
    $ruleGroupSuffix = $GroupSuffix
}

# List of rules with all the data we need to actually create a firewall rule
# Initialized OUTSIDE the per-system loop so rules for all selected systems are aggregated
$outParamObject = New-Object System.Collections.ArrayList 

# Iterate over each selected system. Rule generation logic per system is unchanged - we just repeat it for each system.
foreach ($currentSystemFQDN in $DestinationSystemFQDN)
{

Write-Host "$(Get-date -Format u): Searching rules for: `"$currentSystemFQDN`"" -ForegroundColor Green
$destinationSystemObject = $DefinitionFile.FirewallRuleDefinition.SystemAndRoleList.Where({$_.FullQualifiedDomainName -eq $currentSystemFQDN})
if ($destinationSystemObject)
{
    if ([string]::IsNullOrEmpty($destinationSystemObject.IPAddress))
    {
        Write-Host "$(Get-date -Format u): WARNING: No IPAddress in config file found. Trying to resolve name..." -ForegroundColor Yellow
        [array]$destinationSystemIPAddresses = Get-IPAddressFromName -SystemName ($destinationSystemObject.FullQualifiedDomainName) -Type $IPType
        if (-NOT ($destinationSystemIPAddresses))
        {
            Write-Host "$(Get-date -Format u): WARNING: No IPAddress found for system: `"$currentSystemFQDN`" Neither in config file nor via DNS!" -ForegroundColor Yellow
            continue           
        }
    }
    else
    {
        [array]$destinationSystemIPAddresses = $destinationSystemObject.IPAddress -split ','
        [array]$dnsLookupResult = Get-IPAddressFromName -SystemName ($destinationSystemObject.FullQualifiedDomainName) -Type $IPType
        if ($dnsLookupResult)
        {
            if (-NOT (Compare-TwoArrays -ArrayReference $destinationSystemIPAddresses -ArrayDifference $dnsLookupResult))
            {
                Write-Host "$(Get-date -Format u): WARNING: IPAddress in config file differs from DNS lookup result. Config: `"$($destinationSystemObject.IPAddress)`" DNS: `"$($dnsLookupResult -join ',')`"" -ForegroundColor Yellow
            }
        }
    }
}
else 
{
    Write-Host "$(Get-date -Format u): WARNING: System not found in configFile `"$currentSystemFQDN`"" -ForegroundColor Yellow
    continue
}

[array]$requiredRules = $DefinitionFile.FirewallRuleDefinition.RuleDefinition.Where({$_.Destination -in ($destinationSystemObject.RoleList)})
# adding ANY and Internet rules to the list
[array]$requiredRules += $DefinitionFile.FirewallRuleDefinition.RuleDefinition.Where({$_.Destination -eq 'Any' -or $_.Destination -eq 'Internet'})

Write-Verbose "$(Get-date -Format u): Found: `"$($requiredRules.count)`" possible rules for: `"$currentSystemFQDN`""

# Collectiong all the data we need for each rule
foreach ($firewallRule in $requiredRules)
{
    $status = "Used"
    $statusDescription = ''
    $IPAddressList = @()
    $SourceSystems = @()
    $remoteAddressString = ""
    $searchString = ''

    Write-Verbose "$(Get-date -Format u): Getting data for rule: $($firewallRule.RuleName)"

    # Ignoring client communication to CAS
    if (($firewallRule.RuleName -like 'ConfigMgr Client*') -and ($destinationSystemObject.RoleList -contains 'CentralAdministrationSite'))
    {
        $status = "Not used"
        $statusDescription = 'Clients to CAS not allowed'
    }

    # Making sure we look for the right role based on outbound or inbound rule
    if ($firewallRule.Direction -eq 'Inbound')
    {
        $searchString = $firewallRule.Source
    }
    else 
    {
        $searchString = $firewallRule.Destination
    }

    # Just looking for rules with actual systems as source to get the correct IP addresses. Skip an or internet
    if ($searchString -in ('Any','Internet'))
    {
        $remoteAddressString = $searchString
    }
    else 
    {
        if ($firewallRule.IgnoreSiteCode -eq 'True')
        {
            # We need to look up to a parent site and down to a child side to find the correct systems in a hierarchy
            $SourceSystems = $DefinitionFile.FirewallRuleDefinition.SystemAndRoleList.Where({$_.RoleList -eq $searchString})
        }
        elseif ($firewallRule.RuleName -like '*Pull-Distribution Point to Pull-Source*')
        {

            # PullDP to source DP is special, because this is an extra many to one relationship
            # Looking for all PullDPs in Systemlist for a specific Pull DP source
            $SourceSystems = $DefinitionFile.FirewallRuleDefinition.SystemAndRoleList.Where({$_.FullQualiFiedDomainName -in $destinationSystemObject.PullDistributionPointToSourceList})
        }
        else 
        {
            # We are looking for a role for a specific sitecode. A Distribution Point of a Primary Site for example
            $SourceSystems = $DefinitionFile.FirewallRuleDefinition.SystemAndRoleList.Where({$_.RoleList -eq $searchString -and $_.SiteCode -eq $destinationSystemObject.SiteCode})             
        }
    }

    # Trying to get all required IP addresses and validate if source and destination system are the same to skip it in that case
    if ($searchString -notin ('Any','Internet'))
    {
        if ($SourceSystems.count -eq 0)
        {
            Write-Verbose "$(Get-date -Format u): WARNING: No systems with role: `"$($searchString)`" found in configfile"
            $status = "Not used"
            $statusDescription = 'No system with specified role found'
        }
        else 
        {
            foreach ($SourceSystem in $SourceSystems)
            {
                if ([string]::IsNullOrEmpty($SourceSystem.IPAddress))
                {
                    Write-Host "$(Get-date -Format u): WARNING: No IPAddress in config file found for `"$($SourceSystem.FullQualifiedDomainName)`". Trying to resolve name..." -ForegroundColor Yellow
                    [array]$SourceSystemIPAddresses = Get-IPAddressFromName -SystemName ($SourceSystem.FullQualifiedDomainName) -Type $IPType
                    if (-NOT ($SourceSystemIPAddresses))
                    {
                        Write-Host "$(Get-date -Format u): WARNING: No IPAddress found for system: `"$($SourceSystem.FullQualifiedDomainName)`" Neither in config file nor via DNS!" -ForegroundColor Yellow
                        break           
                    }
                    else
                    {
                        $IPAddressList += $SourceSystemIPAddresses
                    }
                }
                else
                {
                    [array]$SourceSystemIPAddresses = $SourceSystem.IPAddress -split ','
                    [array]$dnsLookupResult = Get-IPAddressFromName -SystemName ($SourceSystem.FullQualifiedDomainName) -Type $IPType
                    if ($dnsLookupResult)
                    {
                        if (-NOT (Compare-TwoArrays -ArrayReference $SourceSystemIPAddresses -ArrayDifference $dnsLookupResult))
                        {
                            Write-Host "$(Get-date -Format u): WARNING: IPAddress in config file differs from DNS lookup result. Config: `"$($SourceSystem.IPAddress)`" DNS: `"$($dnsLookupResult -join ',')`"" -ForegroundColor Yellow
                        }
                    }
                    
                    $IPAddressList += $SourceSystemIPAddresses
                }
            }
        }
    }

    if ($IPAddressList)
    {
        # validate if destination system is the only system in a rule. If so, skip the rule.
        $IPAddressList = $IPAddressList | Where-Object {$_ -notin $destinationSystemIPAddresses}
        if (-NOT $IPAddressList) # if we don't have an IP at all, skip the rule
        {
            $status = "Not used"
            $statusDescription = 'Source IP equals destination IP'
            Write-Verbose "$(Get-date -Format u): WARNING: Source system is equal to destination system. That's expected if the role is installed on the destination system!"
        }
    } 

    # lets now get all the defined services and create a rule object
    foreach ($service in $firewallRule.Services)
    {
        $requiredServices = $DefinitionFile.FirewallRuleDefinition.ServiceDefinition.Where({$_.Name -eq $service})
        if (-NOT ($requiredServices))
        {
            Write-Host "$(Get-date -Format u): WARNING: Service not found in config file: `"$service`" " -ForegroundColor Yellow
            $status = "Not used"
            $statusDescription = "Service not found in config file: `"$service`""
        }

        $statusDescriptionTemp = ''
        if ($firewallRule.Description -like '*Rule not required*')
        {
            $statusDescriptionTemp = 'See rule description! {0}' -f $statusDescription
        }

        foreach ($requiredService in $requiredServices)
        {
            if ($CreateOutboundRuleForeachInboundRule -and ($firewallRule.Direction -eq 'Inbound'))
            {
                # Create two rules in that case. One in and one out with the same ssetings
                $tmpObj = New-Object pscustomobject | Select-Object Status, StatusDescription, DisplayName, Direction, LocalName, LocalAddress, RemoteAddress, Protocol, LocalPort, Profile, Action, Group, Program, Description
                $tmpObj.Status = $status
                $tmpObj.StatusDescription = If($statusDescriptionTemp){$statusDescriptionTemp}else{$statusDescription}
                $tmpObj.DisplayName = $firewallRule.RuleName
                $tmpObj.Direction = 'Inbound'
                $tmpObj.LocalName = $currentSystemFQDN
                $tmpObj.LocalAddress = if ($UseAnyAsLocalAddress){'Any'}else{$destinationSystemIPAddresses}
                $tmpObj.RemoteAddress = if ($IPAddressList){$IPAddressList | Select-Object -Unique}else{$remoteAddressString}
                $tmpObj.Protocol = $requiredService.Protocol
                $tmpObj.LocalPort = $requiredService.Port
                $tmpObj.Profile = $firewallRule.Profile
                $tmpObj.Action = $firewallRule.Action
                $tmpObj.Group = '{0}-{1}' -f $firewallRule.Group, $ruleGroupSuffix
                $tmpObj.Program = $requiredService.Program
                $tmpObj.Description = $firewallRule.Description
                [void]$outParamObject.Add($tmpObj)

                # Outbound
                $tmpObj = New-Object pscustomobject | Select-Object Status, StatusDescription, DisplayName, Direction, LocalName, LocalAddress, RemoteAddress, Protocol, LocalPort, Profile, Action, Group, Program, Description
                $tmpObj.Status = $status
                $tmpObj.StatusDescription = If($statusDescriptionTemp){$statusDescriptionTemp}else{$statusDescription}
                $tmpObj.DisplayName = $firewallRule.RuleName
                $tmpObj.Direction = 'Outbound'
                $tmpObj.LocalName = $currentSystemFQDN
                $tmpObj.LocalAddress = if ($UseAnyAsLocalAddress){'Any'}else{$destinationSystemIPAddresses}
                $tmpObj.RemoteAddress = if ($IPAddressList){$IPAddressList | Select-Object -Unique}else{$remoteAddressString}
                $tmpObj.Protocol = $requiredService.Protocol
                $tmpObj.LocalPort = $requiredService.Port
                $tmpObj.Profile = $firewallRule.Profile
                $tmpObj.Action = $firewallRule.Action
                $tmpObj.Group = '{0}-{1}' -f $firewallRule.Group, $ruleGroupSuffix
                $tmpObj.Program = $requiredService.Program
                $tmpObj.Description = $firewallRule.Description
                [void]$outParamObject.Add($tmpObj)
            }
            else
            {
                $tmpObj = New-Object pscustomobject | Select-Object Status, StatusDescription, DisplayName, Direction, LocalName, LocalAddress, RemoteAddress, Protocol, LocalPort, Profile, Action, Group, Program, Description
                $tmpObj.Status = $status
                $tmpObj.StatusDescription = If($statusDescriptionTemp){$statusDescriptionTemp}else{$statusDescription}
                $tmpObj.DisplayName = $firewallRule.RuleName
                $tmpObj.Direction = $firewallRule.Direction
                $tmpObj.LocalName = $currentSystemFQDN
                $tmpObj.LocalAddress = if ($UseAnyAsLocalAddress){'Any'}else{$destinationSystemIPAddresses}
                $tmpObj.RemoteAddress = if ($IPAddressList){$IPAddressList | Select-Object -Unique}else{$remoteAddressString}
                $tmpObj.Protocol = $requiredService.Protocol
                $tmpObj.LocalPort = $requiredService.Port
                $tmpObj.Profile = $firewallRule.Profile
                $tmpObj.Action = $firewallRule.Action
                $tmpObj.Group = '{0}-{1}' -f $firewallRule.Group, $ruleGroupSuffix
                $tmpObj.Program = $requiredService.Program
                $tmpObj.Description = $firewallRule.Description
                [void]$outParamObject.Add($tmpObj)
            }
        }
    }
}
} # end foreach ($currentSystemFQDN in $DestinationSystemFQDN)

# Show just the rules which are evaluated to be ok
$systemListForTitle = ($DestinationSystemFQDN -join ', ')
$ogvTitle = 'List of possible firewall rules based on target systems roles. Choose the rules you want to apply or show for: "{0}"' -f $systemListForTitle
if ($ValidRulesOnly)
{
    $selectedFirewallRules = $outParamObject | Where-Object {$_.Status -eq 'Used' } | Sort-Object -Property Status, Direction, DisplayName | Out-GridView -Title $ogvTitle -OutputMode Multiple
}
else 
{
    $selectedFirewallRules = $outParamObject | Sort-Object -Property Status, Direction, DisplayName -Descending | Out-GridView -Title $ogvTitle -OutputMode Multiple        
}


if ($MergeSimilarRules)
{
    # Let's merge rules with same settings to have only one rule instead of multiple rules  
    # NOTE: LocalName is included in the grouping so rules from different selected systems are never merged together.
    $mergedOutObject = New-Object System.Collections.ArrayList
    $mergedRules = $selectedFirewallRules | Where-Object {$_.Status -eq 'Used' } | Group-Object -Property LocalName, Direction, LocalAddress, Protocol, LocalPort, Profile, Action, Program
    foreach ($ruleGroup in $mergedRules)
    {
        $RemoteAddressList = @()
        foreach ($groupItem in $ruleGroup.Group)
        {
            # Adding all the IPAddresses to the rule
            $RemoteAddressList += $groupItem.RemoteAddress
        }       
        
        # Making sure we don't have any duplicates 
        [array]$RemoteAddressList = $RemoteAddressList | Select-Object -Unique 

        $tmpObj = New-Object pscustomobject | Select-Object Status, StatusDescription, DisplayName, Direction, LocalName, LocalAddress, RemoteAddress, Protocol, LocalPort, Profile, Action, Group, Program, Description
        $tmpObj.Status = $ruleGroup.Group[0].Status
        $tmpObj.StatusDescription = $ruleGroup.Group[0].StatusDescription
        $tmpObj.DisplayName = 'ConfigMgr {0} {1}' -f ($ruleGroup.Group[0].Direction), ($ruleGroup.Group[0].LocalPort) # Create new rule name
        $tmpObj.Direction = $ruleGroup.Group[0].Direction
        $tmpObj.LocalName = $ruleGroup.Group[0].LocalName
        $tmpObj.LocalAddress = $ruleGroup.Group[0].LocalAddress
        $tmpObj.RemoteAddress = if ($RemoteAddressList -contains 'Any'){'Any'}else{$RemoteAddressList}
        $tmpObj.Protocol = $ruleGroup.Group[0].Protocol
        $tmpObj.LocalPort = $ruleGroup.Group[0].LocalPort
        $tmpObj.Profile = $ruleGroup.Group[0].Profile
        $tmpObj.Action = $ruleGroup.Group[0].Action
        $tmpObj.Group = $ruleGroup.Group[0].Group
        $tmpObj.Program = $ruleGroup.Group[0].Program
        $tmpObj.Description = $ruleGroup.Group[0].Description
        [void]$mergedOutObject.Add($tmpObj)       
        
    }

    $ogvTitle = 'List of merged rules for system(s): "{0}" Select the rules you want to apply or show commands for.' -f $systemListForTitle
    $selectedFirewallRules = $mergedOutObject | Sort-Object -Property Status, Direction, DisplayName -Descending | Out-GridView -Title $ogvTitle -OutputMode Multiple        
}

# Optional CSV export of the selected rules.
# Uses ';' as the CSV delimiter so the comma-separated IP-address lists in RemoteAddress/LocalAddress/LocalPort are NOT split into separate columns by Excel.
# A leading "sep=;" hint is written so Excel auto-detects the delimiter on every locale.
# CSV export runs when either -ExportToCsv is specified OR an explicit -CsvExportPath is provided.
# If -ExportToCsv is set without -CsvExportPath, a default file is created in the script folder using the
# loaded JSON definition file name plus a datetime suffix (mirrors the naming used by -ExportConfigMgrSystemRoleInformation).
if ($ExportToCsv -and [string]::IsNullOrEmpty($CsvExportPath) -and $loadedDefinitionFilePath)
{
    $jsonBaseName = [System.IO.Path]::GetFileNameWithoutExtension($loadedDefinitionFilePath)
    $csvDateStamp = (Get-Date -Format u) -replace '-|:|Z' -replace ' ', '_'
    $CsvExportPath = '{0}\{1}-{2}.csv' -f $PSScriptRoot, $jsonBaseName, $csvDateStamp
}

if (-NOT [string]::IsNullOrEmpty($CsvExportPath))
{
    if (-NOT $selectedFirewallRules)
    {
        Write-Host "$(Get-date -Format u): WARNING: No rules selected - nothing to export to CSV" -ForegroundColor Yellow
    }
    else
    {
        try
        {
            # Make sure target directory exists
            $csvParentDir = Split-Path -Path $CsvExportPath -Parent
            if ($csvParentDir -and -NOT (Test-Path -LiteralPath $csvParentDir))
            {
                New-Item -ItemType Directory -Path $csvParentDir -Force | Out-Null
            }

            # Flatten array-valued properties (e.g. RemoteAddress, LocalAddress) into single comma-separated strings
            # so they end up inside a single quoted CSV cell.
            $csvData = foreach ($rule in $selectedFirewallRules)
            {
                [pscustomobject]@{
                    Status            = $rule.Status
                    StatusDescription = $rule.StatusDescription
                    DisplayName       = $rule.DisplayName
                    Direction         = $rule.Direction
                    LocalName         = $rule.LocalName
                    LocalAddress      = if ($rule.LocalAddress  -is [array]) { $rule.LocalAddress  -join ',' } else { $rule.LocalAddress }
                    RemoteAddress     = if ($rule.RemoteAddress -is [array]) { $rule.RemoteAddress -join ',' } else { $rule.RemoteAddress }
                    Protocol          = $rule.Protocol
                    LocalPort         = if ($rule.LocalPort     -is [array]) { $rule.LocalPort     -join ',' } else { $rule.LocalPort }
                    Profile           = $rule.Profile
                    Action            = $rule.Action
                    Group             = $rule.Group
                    Program           = $rule.Program
                    Description       = $rule.Description
                }
            }

            # Build CSV text manually so we can prepend the Excel "sep=;" hint.
            $csvLines = $csvData | ConvertTo-Csv -Delimiter ';' -NoTypeInformation
            $csvOutput = @('sep=;') + $csvLines
            Set-Content -LiteralPath $CsvExportPath -Value $csvOutput -Encoding UTF8

            Write-Host "$(Get-date -Format u): Exported $($csvData.Count) rule(s) to CSV: `"$CsvExportPath`"" -ForegroundColor Green
        }
        catch
        {
            Write-Host "$(Get-date -Format u): ERROR: Failed to export CSV to `"$CsvExportPath`": $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # CSV export was the requested action - skip the rest (command list / GPO output / local rule creation).
    return
}

# Adding GPO specific strings to list
$commandOutput = New-Object System.Collections.ArrayList
if ($ShowGPOCommands)
{
    $RuleString = '$gpoSession = Open-NetGPO -PolicyStore "{0}\{1}"' -f $DomainName, $GPOName
    [void]$commandOutput.Add($RuleString)                      
}

# Create connection to GPO in order to change settings
if ($AddRulesToGPO)
{
    $policyPath = '{0}\{1}' -f $DomainName, $GPOName
    Write-Host "$(Get-date -Format u): Connecting to GPO `"$($policyPath)`"" -ForegroundColor Green    
    $gpoSession = Open-NetGPO -PolicyStore $policyPath
    if (-NOT ($gpoSession))
    {
        Write-Host "$(Get-date -Format u): ERROR: No conection to GPO" -ForegroundColor Red
        exit
    }
}

# Prepare parameter list either for New-NetFirewallRule command or for gridview 
foreach($selectedRule in $selectedFirewallRules)
{
    if ($selectedRule.Status -eq 'Used')
    {
        $paramSplatting = $null
        $paramSplatting = [ordered]@{
            DisplayName = $selectedRule.DisplayName
            Direction = $selectedRule.Direction   
            RemoteAddress = $selectedRule.RemoteAddress
            Protocol = $selectedRule.Protocol
            LocalPort = $selectedRule.LocalPort
            Profile = $selectedRule.Profile
            Action = $selectedRule.Action
            Group = $selectedRule.Group
        }

        # Adding parameter values if required
        if (-NOT ([string]::IsNullOrEmpty($selectedRule.Description)))
        {
            $paramSplatting.add("Description", "$($selectedRule.Description)")
        }

        # Adding parameter values if required
        if (-NOT ([string]::IsNullOrEmpty($selectedRule.Program)))
        {
            $programPath = ($selectedRule.Program).Replace('\\','\')
            $paramSplatting.add("Program", "$($programPath)")
        }

        # Adding parameter values if required
        if ($selectedRule.LocalAddress -ne 'Any')
        {
            $paramSplatting.add("LocalAddress", $selectedRule.LocalAddress)
        }

        # Adding parameter values if required
        if ( $AddRulesToGPO -or $ShowGPOCommands)
        {
            $paramSplatting.add("GPOSession", $gpoSession)
        }

        # Adding parameter values if required
        if ($AddRulesLocally -or $AddRulesToGPO)
        {
            try
            {
                # Making sure we have an array of ports to be able to set the rule locally in case multiple ports are specified
                $paramSplatting.LocalPort = $paramSplatting.LocalPort -split ','

                Write-Host "$(Get-date -Format u): New-NetFirewallRule -> `"$($selectedRule.DisplayName)`"" -ForegroundColor Green
                $retval = New-NetFirewallRule @paramSplatting -ErrorAction Stop
            }
            Catch
            {
                Write-Host "$(Get-date -Format u): ERROR: Not able to create rule" -ForegroundColor Red
                Write-Host "$(Get-date -Format u): $($error[0].Exception)" -ForegroundColor Red
            }
        }
        elseif ($ShowCommands -or $ShowGPOCommands)
        {
            # Creating New-NetFirewallRule command strings out of rule objects
            $RuleString = 'New-NetFirewallRule'
            $paramSplatting.GetEnumerator() | ForEach-Object {

                If (($_.Name -eq 'RemoteAddress') -or ($_.Name -eq 'LocalAddress'))
                {
                    if(($_.Value -eq 'Any') -or ($_.Value -eq 'Internet'))
                    {
                        $RuleString = '{0} -{1} {2}' -f $RuleString, $_.Name, $_.Value
                    }
                    else
                    {
                        # Creating an array string out of IPAddresses for the cmdlet
                        $AdressList = $_.Value -join '","'
                        $AdressList = '("{0}")' -f $AdressList                        
                        $RuleString = '{0} -{1} {2}' -f $RuleString, $_.Name, $AdressList                            
                    }
                }
                elseif ($_.Name -eq 'GPOSession')
                {
                    # We need to add the GPO session variable to the string
                    $RuleString = '{0} -{1} $gpoSession' -f $RuleString, $_.Name
                }
                elseif ($_.Name -eq 'LocalPort')
                {
                    # Localport does not work as string
                    $RuleString = '{0} -{1} {2}' -f $RuleString, $_.Name, $_.Value    
                }
                else
                {
                    $RuleString = '{0} -{1} "{2}"' -f $RuleString, $_.Name, $_.Value
                }
            
            }
            [void]$commandOutput.Add($RuleString)

        }
    }
    else 
    {
        Write-Verbose "$(Get-date -Format u): WARNING: Selected rule was marked as 'Not used'. Will be skipped. `"$($selectedRule.DisplayName)`""
    }
}

# Write rules to GPO
if ($gpoSession)
{
    Write-Host "$(Get-date -Format u): Saving rules to GPO" -ForegroundColor Green
    Save-NetGPO -GPOSession $gpoSession
    # No try catch block to properly let command fail
}

# Output rule commands either with GPO parameters or not
if ($ShowCommands -or $ShowGPOCommands)
{
    if ($ShowGPOCommands)
    {
        $RuleString = 'Save-NetGPO -GPOSession $gpoSession'
        [void]$commandOutput.Add($RuleString)
    }   
    $commandOutput | Out-GridView -Title "List of commands to add firewall rules to: `"$systemListForTitle`""
}
#endregion

