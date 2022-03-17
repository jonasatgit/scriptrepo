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
Script to create Windows Firewall Rules based in a JSON definition file

.DESCRIPTION
Lorem Ipsum

.INPUTS
Lorem Ipsum

.OUTPUTS
Lorem Ipsum

.EXAMPLE
Lorem Ipsum

.PARAMETER DestinationSystemFQDN
Lorem Ipsum

.PARAMETER DefinitionFilePath
Lorem Ipsum

.PARAMETER GroupSuffix
Lorem Ipsum

.PARAMETER UseAnyAsLocalAddress
Lorem Ipsum

.PARAMETER $ShowAllRules
Lorem Ipsum

.PARAMETER IPType
Lorem Ipsum

.PARAMETER ShowConfig
Lorem Ipsum

.PARAMETER ShowCommands
Lorem Ipsum

.PARAMETER ShowGPOCommands
Lorem Ipsum

.PARAMETER SetRulesLocally
Lorem Ipsum

.PARAMETER AddRulesToGPO
Lorem Ipsum

.PARAMETER DomainName
Lorem Ipsum

.PARAMETER GPOName
Lorem Ipsum

.PARAMETER ExportMECMSystemRoleInformation
Lorem Ipsum

.PARAMETER ProviderMachineName
Lorem Ipsum

.PARAMETER SiteCode
Lorem Ipsum

.LINK
https://github.com/jonasatgit/scriptrepo

#>

[CmdletBinding(DefaultParametersetName='Default')]
param
(

    [parameter(Mandatory=$false)]
    [string]$DefinitionFilePath,

    [parameter(Mandatory=$false)]
    [string]$DestinationSystemFQDN,

    [parameter(Mandatory=$false)]
    [string]$GroupSuffix,

    [parameter(Mandatory=$false)]
    [switch]$UseAnyAsLocalAddress,

    [parameter(Mandatory=$false)]
    [switch]$ShowAllRules,

    [parameter(Mandatory=$false)]
    [ValidateSet("IPv4","IPv6","All")]
    [string]$IPType = "IPv4",

    [parameter(ParameterSetName = 'ShowConfig',Mandatory=$true)]
    [switch]$ShowConfig,

    [parameter(ParameterSetName = 'ShowCommands',Mandatory=$true)]
    [switch]$ShowCommands,

    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [switch]$ShowGPOCommands,

    [parameter(ParameterSetName = 'SetRulesLocally',Mandatory=$true)]
    [switch]$SetRulesLocally,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$true)]
    [switch]$AddRulesToGPO,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$true)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [string]$DomainName,

    [parameter(ParameterSetName = 'AddRulesToGPO',Mandatory=$true)]
    [parameter(ParameterSetName = 'ShowGPOCommands',Mandatory=$true)]
    [string]$GPOName,

    [parameter(ParameterSetName = 'ExportMECMSystemRoleInformation',Mandatory=$true)]
    [switch]$ExportMECMSystemRoleInformation,

    [parameter(ParameterSetName = 'ExportMECMSystemRoleInformation',Mandatory=$true)]
    [string]$ProviderMachineName,

    [parameter(ParameterSetName = 'ExportMECMSystemRoleInformation',Mandatory=$true)]
    [string]$SiteCode
)

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

    $siteSystems = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -Query "SELECT * FROM SMS_SCI_SysResUse WHERE NALType = 'Windows NT Server'"
    if (-not ($siteSystems))
    {
        Write-host "$(Get-date -Format u): No site systems found" -ForegroundColor Yellow
        exit
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
    
    $outObject = New-Object System.Collections.ArrayList
    foreach ($system in $siteSystems)
    {
        switch ($system.RoleName)
        {
            'SMS SQL Server' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'SQLServerRole'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            'SMS Site Server' 
            {
                switch ($system.Type)
                {
                    1 {$roleName = 'SecondarySite'}
                    2 {$roleName = 'PrimarySite'}
                    4 {$roleName = 'CentralAdministrationSite'}
                    #8 {$roleName = 'NotCoLocatedWithSiteServer'}
                }
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = $roleName
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            'SMS Provider' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'SMSProvider'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            'SMS Software Update Point' 
            {
                $useParentWSUS = $system.Props | Where-Object {$_.PropertyName -eq 'UseParentWSUS'}
                if ($useParentWSUS.Value -eq 0)
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                    $tmpObj.Role = 'PrimarySoftwareUpdatePoint'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
                    [void]$outObject.Add($tmpObj)
                }
                
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'SoftwareUpdatePoint'            
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            'SMS Endpoint Protection Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'EndpointProtectionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            'SMS Distribution Point' 
            {
                $isPullDP = $system.Props | Where-Object {$_.PropertyName -eq 'IsPullDP'}
                if ($isPullDP.Value -eq 1)
                {
                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                    $tmpObj.Role = 'PullDistributionPoint'
                    $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                    $tmpObj.SiteCode = $system.SiteCode
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
                                    $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                                    $tmpObj.Role = 'PullDistributionPointSource'
                                    $tmpObj.FullQualifiedDomainName = ($Matches[2])
                                    $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($Matches[2]) -Type $IPType
                                    $tmpObj.SiteCode = $system.SiteCode
                                    [void]$outObject.Add($tmpObj)
                                }
                                else
                                {
                                    Write-host "$(Get-date -Format u): No DP sources found for PullDP" -ForegroundColor Yellow
                                }
                            }
                    }
                }
    
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'DistributionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            'SMS Management Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'ManagementPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            'SMS SRS Reporting Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'ReportingServicePoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            'SMS Dmp Connector' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'ServiceConnectionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            'Data Warehouse Service Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'DataWarehouseServicePoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            'SMS Cloud Proxy Connector' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'CMGConnectionPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            'SMS State Migration Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'StateMigrationPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            'SMS Fallback Status Point' 
            {
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'FallbackStatusPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
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
                $tmpObj = New-Object pscustomobject | Select-Object FullQualifiedDomainName, IPAddress, Role, SiteCode
                $tmpObj.Role = 'CertificateRegistrationPoint'
                $tmpObj.FullQualifiedDomainName = $system.NetworkOSPath -replace '\\\\'
                $tmpObj.IPAddress = Get-IPAddressFromName -SystemName ($tmpObj.FullQualifiedDomainName) -Type $IPType
                $tmpObj.SiteCode = $system.SiteCode
                [void]$outObject.Add($tmpObj)
            }
            #>
            Default 
            {
                Write-host "$(Get-date -Format u): Role `"$($system.RoleName)`" not supported by the script at the moment. Create you own firewallrules and definitions in the config fiel if desired." -ForegroundColor Yellow
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
    
    $global:bla = $outObject | Group-Object -Property FullQualifiedDomainName

    $systemsArrayList = New-Object System.Collections.ArrayList
    foreach ($itemGroup in ($outObject | Group-Object -Property FullQualifiedDomainName))
    {
        $roleList = @()
        foreach ($item in $itemGroup.Group)
        {
            $roleList += $item.Role
        }
       
        $itemList = [ordered]@{
            FullQualifiedDomainName = $itemGroup.Name
            IPAddress = $itemGroup.Group[0].IPAddress -join ','
            SiteCode = $itemGroup.Group[0].SiteCode
            Description = ""
            RoleList = $roleList
        }
            
        [void]$systemsArrayList.Add($itemList)
    
    }
    
    $tmpObjRuleDefinition = New-Object pscustomobject | Select-Object FirewallRuleDefinition
    $tmpObjDefinitions = New-Object pscustomobject | Select-Object SystemAndRoleList, RuleDefinition, ServiceDefinition
    
    # Example Rule Definition
    $tmpRuleArrayList = New-Object System.Collections.ArrayList
    $servicesList = @("RPC","RPCUDP","RPCServicesDynamic","HTTPS")
    $exampleRule = [ordered]@{
                RuleName = "MECM Console to SMS provider"
                Source = "MECMConsole"
                Destination = "SiteServer"
                Direction = "Inbound"
                Action = "Allow"
                Profile = "Any"
                Group = "MECM"
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

if (-NOT ($ShowConfig -or $ShowCommands -or $ShowGPOCommands -or $SetRulesLocally -or $AddRulesToGPO -or $ExportMECMSystemRoleInformation))
{
    $ShowCommands = $true    
}

[string]$scriptName = $MyInvocation.MyCommand -replace '.ps1', ''
[string]$exportFileName = '{0}\{1}-Config-{2}.json' -f $PSScriptRoot, $scriptName, ((Get-Date -Format u) -replace '-|:|Z' -replace ' ', '_')

if ($ExportMECMSystemRoleInformation)
{
    if (([string]::IsNullOrEmpty($ProviderMachineName)) -and ([string]::IsNullOrEmpty($SiteCode)))
    {
        Write-Host "$(Get-date -Format u): ProviderMachineName or SiteCode parameter missing" -ForegroundColor Yellow
        break
    }

    Export-SystemRoleInformation -ProviderMachineName $ProviderMachineName -SiteCode $SiteCode -OutputFilePath $exportFileName
    break
}

# reading config file
if (-NOT $DestinationSystemFQDN)
{
    $DestinationSystemFQDN = Get-LocalSystemFQDN 
}

if ($DefinitionFilePath)
{
    $DefinitionFile = Get-Content $DefinitionFilePath | ConvertFrom-Json
}
else 
{
    $DefinitionFileSelection = Get-ChildItem (Split-Path -path $PSCommandPath) -Filter '*.json' | Select-Object Name, Length, LastWriteTime, FullName | Out-GridView -Title 'STEP 1: Choose a JSON configfile' -OutputMode Single
    if (-NOT($DefinitionFileSelection))
    {
        break
    }
    else 
    {
        $DefinitionFile = Get-Content $DefinitionFileSelection.FullName | ConvertFrom-Json
    }
}


if ($ShowConfig)
{
    $DefinitionFile.FirewallRuleDefinition.SystemAndRoleList | Out-GridView -Title 'System-Definition'
    $DefinitionFile.FirewallRuleDefinition.RuleDefinition | Out-GridView -Title 'Firewallrule-Definition'
    $DefinitionFile.FirewallRuleDefinition.ServiceDefinition | Out-GridView -Title 'Service-Definition'
    break
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

Write-Host "$(Get-date -Format u): Searching rules for: `"$DestinationSystemFQDN`"" -ForegroundColor Green
$destinationSystemObject = $DefinitionFile.FirewallRuleDefinition.SystemAndRoleList.Where({$_.FullQualifiedDomainName -eq $DestinationSystemFQDN})
if ($destinationSystemObject)
{
    # Making sure we have any IPAddress for the source system
    # We also check the provided IPAddress with what DNS tells us
    $IPAdressesOfSelectedSystem = @()
    $IPAdressesOfSelectedSystem = Get-IPAddressFromName -SystemName ($destinationSystemObject.FullQualifiedDomainName) -Type $IPType

    if ($IPAdressesOfSelectedSystem)
    {
        if(-NOT ([string]::IsNullOrEmpty($destinationSystemObject.IPAddress)))
        {
            [array]$destinationSystemObjectIPAddresses = $destinationSystemObject.IPAddress -split ','
            if ($destinationSystemObject.IPAddress -notin $destinationSystemObjectIPAddresses) 
            {
                Write-Host "$(Get-date -Format u): WARNING: IPAddress in config file differs from DNS lookup result. Config: `"$($destinationSystemObject.IPAddress)`" DNS: `"$($IPAdressesOfSelectedSystem -join ',')`"" -ForegroundColor Yellow
                Exit
            }
        }
    }
    else 
    {
        if(([string]::IsNullOrEmpty($destinationSystemObject.IPAddress)))
        {
            Write-Host "$(Get-date -Format u): WARNING: No IPAddress found for system: `"$DestinationSystemFQDN`" Neither in config file nor via DNS!" -ForegroundColor Yellow
            exit
        }
        else 
        {
            $IPAdressesOfSelectedSystem = $destinationSystemObject.IPAddress -split ','  
        }  
    }
}
else 
{
    Write-Host "$(Get-date -Format u): WARNING: System not found in configFile `"$DestinationSystemFQDN`"" -ForegroundColor Yellow
    break
}

[int]$iteration = 1
$outParamObject = New-Object System.Collections.ArrayList
foreach ($role in $destinationSystemObject.RoleList)
{
    $requiredRules = $null
    [array]$requiredRules = $DefinitionFile.FirewallRuleDefinition.RuleDefinition.Where({$_.Destination -eq $role})

    if ($iteration -eq 1)     
    {
        # Include ANY or INTERNET destination rules once
        [array]$requiredRules += $DefinitionFile.FirewallRuleDefinition.RuleDefinition.Where({$_.Destination -eq 'Any' -or $_.Destination -eq 'Internet'})
        $iteration++
    }

    # Create two seperate rules for in and outbound in case we have one rule with both in and out as direction
    $requiredRulesArrayList = New-Object System.Collections.ArrayList
    foreach ($firewallRule in $requiredRules)
    {
        if ($firewallRule.Direction -match '(inbound|outbound),(inbound|outbound)')
        {
            # Create two seperate rules for in and outbound
            $firewallRule.Direction = 'Inbound'
            [void]$requiredRulesArrayList.Add($firewallRule) 

            $firewallRule.Direction = 'Outbound'
            [void]$requiredRulesArrayList.Add($firewallRule) 
        }
        else 
        {
            [void]$requiredRulesArrayList.Add($firewallRule)   
        }       
    }

    foreach ($firewallRule in $requiredRulesArrayList)
    {
        $status = "OK"
        $statusDescription = ''
        $IPAddressList = @()
        $remoteAddressString = ""

        if ($firewallRule.Direction -eq 'Inbound')
        {
            $searchString = $firewallRule.Source
        }
        else 
        {
            $searchString = $firewallRule.Destination
        }

        if ($searchString -notin ('Any','Internet'))
        {
            Write-Host "$(Get-date -Format u): Getting all source systems for role: `"$($searchString)`"" -ForegroundColor Green
            $SourceSystems = $null


            # if CAS or secondary, do other stuff

            # if source or destination is another site, don't restrict the result to the sitecode
            if (($firewallRule.Source -in ("CentralAdministrationSite","PrimarySite","SecondarySite")) -and ($firewallRule.Destination -in ("CentralAdministrationSite","PrimarySite","SecondarySite")))
            {
                $SourceSystems = $DefinitionFile.FirewallRuleDefinition.SystemAndRoleList.Where({$_.RoleList -eq $searchString})
            }
            else
            {
                # using the sitecode to make sure we string the right systems together
                $SourceSystems = $DefinitionFile.FirewallRuleDefinition.SystemAndRoleList.Where({$_.RoleList -eq $searchString -and $_.SiteCode -eq $destinationSystemObject.SiteCode})
            }

            if (-NOT $SourceSystems)
            {
                Write-Host "$(Get-date -Format u): WARNING: No systems with role: `"$($searchString)`" found in configfile" -ForegroundColor Yellow
                $status = "NOT OK"
                $statusDescription = 'No system with specified role found'
            }
            else 
            {
                foreach ($SourceSystem in $SourceSystems)
                {
                    # If  system is local system then skip system
                    $ipAddressesOfSystem = Get-IPAddressFromName -SystemName ($SourceSystem.FullQualifiedDomainName) -Type $IPType
                    if ($ipAddressOfSystem)
                    {
                        if([string]::IsNullOrEmpty($SourceSystem.IPAddress))
                        {
                            $IPAddressList += $ipAddressesOfSystem
                        }
                        else 
                        {
                            [array]$ipAddressesFromConfigFile = $SourceSystem.IPAddress -split ','
                            foreach ($ip in $ipAddressesFromConfigFile)
                            {
                                # validate if we got the same IP result as what is configured in the config file
                                if (-NOT ($ipAddressOfSystem.Contains($ip)))
                                {
                                    Write-Host "$(Get-date -Format u): WARNING: IPAddress in config file differs from DNS lookup result. Config: `"$($SourceSystem.IPAddress)`" DNS: `"$($ipAddressesOfSystem -join ',')`"" -ForegroundColor Yellow
                                }
                            }
                        }
                    }
                    else 
                    {
                        if([string]::IsNullOrEmpty($SourceSystem.IPAddress))
                        {
                            Write-Host "$(Get-date -Format u): WARNING: No IPAdress information found for `"$($SourceSystem.FullQualifiedDomainName)`"" -ForegroundColor Yellow
                            $status = "NOT OK"  
                            $statusDescription = 'No IP info found for system'  
                            
                        }
                        else 
                        {
                            $IPAddressList += $SourceSystem.IPAddress -split ','
                        }
                    } 
                }
            }

            if ($IPAddressList)
            {
                # validate if destination system is the only system in a rule. If so, skip the rule.
                $IPAddressList = $IPAddressList | Where-Object {$_ -notin $IPAdressesOfSelectedSystem}
                if (-NOT $IPAddressList) # if we don't have an IP at all, skip the rule
                {
                    $status = "NOT OK"
                    $statusDescription = 'Source IP equals destination IP'
                    Write-Host "$(Get-date -Format u): WARNING: Source system is equal to destination system. That's expected if the role is installed on the destination system!" -ForegroundColor Yellow
                }
            } 

        }
        else 
        {
            $remoteAddressString = $searchString
        }

        # lets now get all the defined services and create a rule object
        foreach ($service in $firewallRule.Services)
        {
            $requiredServices = $DefinitionFile.FirewallRuleDefinition.ServiceDefinition.Where({$_.Name -eq $service})

            if (-NOT ($requiredServices))
            {
                Write-Host "$(Get-date -Format u): WARNING: Service not found in config file: `"$service`" " -ForegroundColor Yellow
                $status = "NOT OK"
                $statusDescription = "Service not found in config file: `"$service`""
            }

            foreach ($requiredService in $requiredServices)
            {
                $tmpObj = New-Object pscustomobject | Select-Object Status, StatusDescription, DisplayName, Direction, LocalName, LocalAddress, RemoteAddress, Protocol, LocalPort, Profile, Action, Group, Program, Description
                $tmpObj.Status = $status
                $tmpObj.StatusDescription = $statusDescription
                $tmpObj.DisplayName = $firewallRule.RuleName
                $tmpObj.Direction = $firewallRule.Direction
                $tmpObj.LocalName = $DestinationSystemFQDN
                $tmpObj.LocalAddress = if ($UseAnyAsLocalAddress){'Any'}else{$IPAdressesOfSelectedSystem}
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
    } # foreach firewallrule
} # foreach role

if ($ShowAllRules)
{
        $selectedFirewallRules = $outParamObject | Sort-Object -Property Status, Direction, DisplayName -Descending | Out-GridView -Title "STEP 2: Select firewall rules for system `"$DestinationSystemFQDN`"" -OutputMode Multiple    
}
else 
{
    $selectedFirewallRules = $outParamObject | Where-Object {$_.Status -eq 'OK' } | Sort-Object -Property Status, Direction, DisplayName | Out-GridView -Title "STEP 2: Select firewall rules for system `"$DestinationSystemFQDN`"" -OutputMode Multiple
}

$commandOutput = New-Object System.Collections.ArrayList
if ($ShowGPOCommands)
{
    $RuleString = '$gpoSession = Open-NetGPO -PolicyStore "{0}\{1}"' -f $DomainName, $GPOName
    [void]$commandOutput.Add($RuleString)                      
}

if ($AddRulesToGPO)
{
    $policyPath = '{0}}\{1}}' -f $DomainName, $GPOName    
    $gpoSession = Open-NetGPO -PolicyStore $policyPath
    if (-NOT ($gpoSession))
    {
        Write-Host "$(Get-date -Format u): ERROR: No conection to GPO" -ForegroundColor Red
        exit
    }
}


foreach($selectedRule in $selectedFirewallRules)
{
    if ($selectedRule.Status -eq 'OK')
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

        if (-NOT ([string]::IsNullOrEmpty($selectedRule.Description)))
        {
            $paramSplatting.add("Description", "$($selectedRule.Description)")
        }

        if (-NOT ([string]::IsNullOrEmpty($selectedRule.Program)))
        {
            $programPath = ($selectedRule.Program).Replace('\\','\')
            $paramSplatting.add("Program", "$($programPath)")
        }

        if ($selectedRule.LocalAddress -ne 'Any')
        {
            $paramSplatting.add("LocalAddress", $selectedRule.LocalAddress)
        }


        if ( $AddRulesToGPO -or $ShowGPOCommands)
        {
            $paramSplatting.add("GPOSession", $gpoSession)
        }

        if ($SetRulesLocally -or $AddRulesToGPO)
        {
            try
            {
                Write-Host "$(Get-date -Format u): New-NetFirewallRule -> `"$($selectedRule.DisplayName)`"" -ForegroundColor Green
                $retval = New-NetFirewallRule @paramSplatting -ErrorAction Stop
            }
            Catch
            {
                Write-Host "$(Get-date -Format u): ERROR: Not able to create rule" -ForegroundColor Red
                Write-Host "$(Get-date -Format u): $($error[0].Exception)"
            }
        }
        elseif ($ShowCommands -or $ShowGPOCommands)
        {
            $RuleString = 'New-NetFirewallRule'
            $paramSplatting.GetEnumerator() | ForEach-Object {

                If ($_.Name -eq 'RemoteAddress')
                {
                    if($_.Value -eq 'Any' -or $_.Value -eq 'Internet')
                    {
                        $RuleString = "{0} -{1} {2}" -f $RuleString, $_.Name, $_.Value
                    }
                    else
                    {
                        $AdressList = $_.Value -join '","'
                        $AdressList = '("{0}")' -f $AdressList                        
                        $RuleString = '{0} -{1} {2}' -f $RuleString, $_.Name, $AdressList                            
                    }
                }
                elseif ($_.Name -eq 'GPOSession')
                {
                    $RuleString = '{0} -{1} $gpoSession' -f $RuleString, $_.Name
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
        Write-Host "$(Get-date -Format u): WARNING: Selected rule was marked as not okay. Will be skipped. `"$($selectedRule.DisplayName)`"" -ForegroundColor Yellow  
    }
}

# Write rules to GPO
if ($gpoSession)
{
    Write-Host "$(Get-date -Format u): Saving rules to GPO" -ForegroundColor Green
    Save-NetGPO -GPOSession $gpoSession
}

# Output rule commands either with GPO parameters or not
if ($ShowCommands -or $ShowGPOCommands)
{
    if ($ShowGPOCommands)
    {
        $RuleString = 'Save-NetGPO -GPOSession $gpoSession'
        [void]$commandOutput.Add($RuleString)
    }   
    $commandOutput | Out-GridView -Title "STEP 3: List of commands to add firewall rules to: `"$DestinationSystemFQDN`""
}
#endregion

