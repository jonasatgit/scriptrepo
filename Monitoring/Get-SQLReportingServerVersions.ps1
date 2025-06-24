<#
.SYNOPSIS
    This script will check the version of SQL Server Reporting Services and PowerBI Report Server and compare it to the version 
    of the SQL Server Reporting Services in a ConfigMgr environment.

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
    #************************************************************************************************************

    This script will check the version of SQL Server Reporting Services and PowerBI Report Server and compare it to the version 
    of the SQL Server Reporting Services in a ConfigMgr environment. The script will output the results in the console as a single object.

    The script will use the following websites to get the latest versions of SQL Server Reporting Services and PowerBI Report Server:
    https://learn.microsoft.com/en-us/sql/reporting-services/release-notes-reporting-services
    https://learn.microsoft.com/en-us/power-bi/report-server/changelog

    The script has different output modes. Use parameter -OutputMode to select the output mode which is best for you.

.PARAMETER ProviderMachineName
    The parameter ProviderMachineName is the name of the ConfigMgr Provider machine. Default is the local machine.

.PARAMETER SiteCode
    The parameter SiteCode is the ConfigMgr site code. If not provided, the script will try to get the site code from the SMS ProviderMachine.

.PARAMETER ForceWSMANConnection
    The parameter ForceWSMANConnection will force the script to use WSMAN for the CIMSession. Default is DCOM.

.PARAMETER ProxyURI
    The parameter ProxyURI is the URI of the proxy server to use for the web requests.

.PARAMETER OutputMode
    The parameter OutputMode has two possible options:
    "Object": Will show the results in the console as a single object

    "VersionList": Will show a GridView with all the versions found on the websites

    "HTMLMail": Will send an email containing a table with the results
    
    IMPOPRTANT: Send-CustomMonitoringMail.ps1 must be in the same folder as this script

.PARAMETER MailSubject
    The parameter MailSubject is the subject of the email. Default is 'Status about SQL Server Reporting Services Versions'.

.PARAMETER MailInfotext
    The parameter MailInfotext is the text of the email. Default is 'Status about SQL Server Reporting Services Versions'.

.PARAMETER SendMailOnlyWhenNewVersionsFound
    The parameter SendMailOnlyWhenNewVersionsFound will only send an email if new versions are found. Default is to send an email always.

.PARAMETER ReportServerVersionListURI
    The parameter ReportServerVersionListURI is the URI of the website where the script will get the versions of SQL Server Reporting Services. 
    Default is 'https://learn.microsoft.com/en-us/sql/reporting-services/release-notes-reporting-services'.

.PARAMETER PowerBIReportServerVersionListURI
    The parameter PowerBIReportServerVersionListURI is the URI of the website where the script will get the versions of PowerBI Report Server. 
    Default is 'https://learn.microsoft.com/en-us/power-bi/report-server/changelog'.

.LINK
    https://github.com/jonasatgit/scriptrepo

#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [string]$ProviderMachineName = $env:ComputerName,

    [Parameter(Mandatory=$false)]
    [string]$SiteCode,
 
    [Parameter(Mandatory=$false)]
    [Switch]$ForceWSMANConnection,
       
    [Parameter(Mandatory=$false)]
    [string]$ProxyURI,

    [Parameter(Mandatory=$false)]
    [ValidateSet("List","JSON","GridView", "MonAgentJSON", "MonAgentJSONCompressed","HTMLMail","PSObject","PrtgString","PrtgJSON")]
    [string]$OutputMode = 'List',

    [Parameter(Mandatory=$false)]
    [String]$MailSubject = 'Status about SQL Server Reporting Services Versions',

    [Parameter(Mandatory=$false)]
    [String]$MailInfotext = 'Status about SQL Server Reporting Services Versions',

    [Parameter(Mandatory=$false)]
    [switch]$SendMailOnlyWhenNewVersionsFound

    #[Parameter(Mandatory=$false)]
    #[string]$ReportServerVersionListURI = 'https://learn.microsoft.com/en-us/sql/reporting-services/release-notes-reporting-services',

    #[Parameter(Mandatory=$false)]
    #[string]$PowerBIReportServerVersionListURI = 'https://learn.microsoft.com/en-us/power-bi/report-server/changelog'
 
    #[Parameter(Mandatory=$false)]
    #[string]$ProxyUser,
 
    #[Parameter(Mandatory=$false)]
    #[string]$ProxyDomain,
 
    #[Parameter(Mandatory=$false)]
    #[string]$ProxyPassword
 
)




#region ConvertTo-CustomMonitoringObject
<# 
.Synopsis
   Function ConvertTo-CustomMonitoringObject

.DESCRIPTION
   Will convert a specific input object to a custom JSON like object
   Which then can be used as an input object for a custom monitoring solution

.PARAMETER InputObject
   Well defined input object

.EXAMPLE
   $CustomObject | ConvertTo-CustomMonitoringObject
#>
Function ConvertTo-CustomMonitoringObject
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [object]$InputObject,
        [Parameter(Mandatory=$true)]
        [ValidateSet("MonAgentObject", "PrtgObject")]
        [string]$OutputType,
        [Parameter(Mandatory=$false)]
        [string]$PrtgLookupFileName        
    )

    Begin
    {
        $resultsObject = New-Object System.Collections.ArrayList
        switch ($OutputType)
        {
            'MonAgentObject'
            {
                $outObject = New-Object psobject | Select-Object InterfaceVersion, Results
                $outObject.InterfaceVersion = 1  
            }
            'PrtgObject'
            {
                $outObject = New-Object psobject | Select-Object prtg
            }
        }  
    }
    Process
    {
        switch ($OutputType) 
        {
            'MonAgentObject' 
            {  
                # Adding infos to short description field
                Switch ($InputObject.CheckType)
                {
                    'Certificate'
                    {
                        [string]$shortDescription = $InputObject.Description -replace "\'", "" -replace '>','_' # Remove some chars like quotation marks or >    
                    }
                    'Inbox'
                    {
                        [string]$shortDescription = $InputObject.Description -replace "\'", "" -replace '>','_' # Remove some chars like quotation marks or >    
                    }
                    Default 
                    {
                        [string]$shortDescription = $InputObject.Description -replace "\'", "" -replace '>','_' # Remove some chars like quotation marks or >
                    }
                }

                # ShortDescription has a 300 character limit
                if ($shortDescription.Length -gt 300)
                {
                    $shortDescription = $shortDescription.Substring(0, 299) 
                } 


                switch ($InputObject.Status) 
                {
                    'Ok' {$outState = 0}
                    'Warning' {$outState = 1}
                    'Error' {$outState = 2}
                    Default {$outState = 3}
                }

                $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
                $tmpResultObject.Name = $InputObject.Name -replace "\'", "" -replace '>','_'
                $tmpResultObject.Epoch = 0 # NOT USED at the moment. FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
                $tmpResultObject.Status = $outState
                $tmpResultObject.ShortDescription = $shortDescription
                $tmpResultObject.Debug = ''
                [void]$resultsObject.Add($tmpResultObject)
            }
            'PrtgObject'
            {
                if ($PrtgLookupFileName)
                {
                    $tmpResultObject = New-Object psobject | Select-Object Channel, Value, ValueLookup
                    $tmpResultObject.ValueLookup = $PrtgLookupFileName
                }
                else 
                {
                    $tmpResultObject = New-Object psobject | Select-Object Channel, Value
                }
               
                $tmpResultObject.Channel = $InputObject.Name -replace "\'", "" -replace '>','_'
                if ($InputObject.Status -ieq 'Ok')
                {
                    $tmpResultObject.Value = 0
                }
                else
                {
                    $tmpResultObject.Value = 1
                }                    
                [void]$resultsObject.Add($tmpResultObject)  
            }
        }                  
    }
    End
    {
        switch ($OutputType)
        {
            'MonAgentObject'
            {
                $outObject.Results = $resultsObject
                $outObject
            }
            'PrtgObject'
            {
                $tmpPrtgResultObject = New-Object psobject | Select-Object result
                $tmpPrtgResultObject.result = $resultsObject
                $outObject.prtg = $tmpPrtgResultObject
                $outObject
            }
        }  

    }
}
#endregion

#region function Get-ReportServerMetadata
function Get-ReportServerMetadata
{
    param 
    (
        [Parameter(Mandatory=$false)]
        [string]$ProviderMachineName = $env:ComputerName,
 
        [Parameter(Mandatory=$false)]
        [string]$SiteCode,
 
        [Parameter(Mandatory=$false)]
        [Switch]$ForceWSMANConnection,

        [Parameter(Mandatory=$false)]
        [switch]$TestMode
    )

 
    $simplifiedListOfReportServers = [System.Collections.Generic.List[pscustomobject]]::new()

    if ($TestMode)
    {
        $simplifiedListOfReportServers.add([pscustomobject][ordered]@{
            ServerType = $null
            Servername = 'testserver1.contoso.local'
            ReportServerInstance = 'SSRS'
            VersionString = $null
            VersionStringLatest = $null
            BuildVersion = '15.0.1102.962'
            BuildVersionLatest = $null
            Status = $null
            DatabaseServerName = 'testserver1.contoso.local'
            ReportServerUri = 'https://testserver1.contoso.local/ReportServer'
            ReportManagerUri = 'https://testserver1.contoso.local/Reports'
        })

        $simplifiedListOfReportServers.add([pscustomobject][ordered]@{
            ServerType = $null
            Servername = 'testserver2.contoso.local'
            ReportServerInstance = 'PBIRS'
            VersionString = $null
            VersionStringLatest = $null
            BuildVersion = '15.0.1113.162'
            BuildVersionLatest = $null
            Status = $null
            DatabaseServerName = 'testserver2.contoso.local'
            ReportServerUri = 'https://testserver2.contoso.local/ReportServer'
            ReportManagerUri = 'https://testserver2.contoso.local/Reports'
        })

        return $simplifiedListOfReportServers
    }
    else 
    {
        #region CIMSession settings
        if (-NOT ($ForceWSMANConnection))
        {
            $cimSessionOption = New-CimSessionOption -Protocol Dcom
            $cimSession = New-CimSession -ComputerName $ProviderMachineName -SessionOption $cimSessionOption
            Write-Verbose "Using DCOM for CimSession"
        }
        else
        {
            $cimSession = New-CimSession -ComputerName $ProviderMachineName
            Write-Verbose "Using WSMAN for CimSession"
        }
        #endregion
        
        #region Get ConfigMgr sitecode
        if (-NOT($siteCode))
        {
            # getting sitecode
            $siteCode = Get-CimInstance -CimSession $cimSession -Namespace root\sms -Query 'Select SiteCode From SMS_ProviderLocation Where ProviderForLocalSite=1' -ErrorAction Stop | Select-Object -ExpandProperty SiteCode -First 1
        }
        #endregion
 
        [array]$listOfReportServers = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -query "select * from SMS_SCI_SysResUse where RoleName = 'SMS SRS Reporting Point'" -ErrorAction Stop
        $cimSession | Remove-CimSession -ErrorAction SilentlyContinue # session no longer needed
   
        Write-Verbose "$($siteCode) detected sitecode"
        
        foreach($server in $listOfReportServers)
        {
            $simplifiedListOfReportServers.add([pscustomobject][ordered]@{
                ServerType = $null
                Servername = ($server.Props.Where({$_.PropertyName -ieq 'Server Remote Name'})).Value1
                ReportServerInstance = ($server.Props.Where({$_.PropertyName -ieq 'ReportServerInstance'})).Value2
                VersionString = $null
                VersionStringLatest = $null
                BuildVersion = ($server.Props.Where({$_.PropertyName -ieq 'Version'})).Value2
                BuildVersionLatest = $null
                Status = $null
                DatabaseServerName = ($server.Props.Where({$_.PropertyName -ieq 'DatabaseServerName'})).Value2
                ReportServerUri = ($server.Props.Where({$_.PropertyName -ieq 'ReportServerUri'})).Value2
                ReportManagerUri = ($server.Props.Where({$_.PropertyName -ieq 'ReportManagerUri'})).Value2
            })
        
        }
        return $simplifiedListOfReportServers
    }
}
#endregion

#region function Get-ReportServerVersionList
function Get-ReportServerVersionList
{
    param 
    (
        [Parameter(Mandatory=$false)]
        [string]$ReportServerVersionListURI = 'https://learn.microsoft.com/en-us/sql/reporting-services/release-notes-reporting-services',
 
        [Parameter(Mandatory=$false)]
        [string]$PowerBIReportServerVersionListURI = 'https://learn.microsoft.com/en-us/power-bi/report-server/changelog',

        [Parameter(Mandatory=$false)]
        [string]$ProxyURI
    )
    
        # Initialize a list to hold the results
        $versionObjectList = [System.Collections.Generic.List[PSCustomObject]]::new()
 
        # GETTING DATA FOR SQL SERVER REPORTING SERVICES
        # SQL Server Report Server
        #try
        #{
            # Define the base parameters for Invoke-WebRequest
            $params = @{
                Uri = $ReportServerVersionListURI
                UseBasicParsing = $true
                ErrorAction = 'Stop'
            }
    
            # Check if a proxy URL is provided and add it to the parameters if it is
            if (-NOT ([string]::IsNullOrEmpty($ProxyURI))) 
            {
                $params['Proxy'] = $ProxyURI
            }
    
            # Use parameter splatting to invoke the web request with the defined parameters
            $webRequestResult = Invoke-WebRequest @params
        #}
        #catch
        #{
           # Write-Output "Failed to retrieve the page: $($uri)"
            #Write-Output "Error: $($_.Exception.Message)"
            #break
        #}
    
        # The site contains multiple sections all with a title called: "SQL Server <Version> Reporting Services"
        # In between each section there is a list of version for each of the SQL Server versions
        # We first need to find each section containing the version information
        $regexString = '(<h2 id="sql-server-\d+-reporting-services">SQL Server \d+ Reporting Services</h2>)(.*?)(?=<h2 id="sql-server-\d+-reporting-services"|<\/html>)'
        [array]$matchResultList = [regex]::Matches($webRequestResult.Content, $regexString, 'Singleline')
       
        # Iterate over each match to extract information
        foreach ($match in $matchResultList ) {
            $section = $match.Value
           
            # Extract the title
            $title = $match.Groups[1].Value -replace '<.*?>', ''
            # Extract version information within this section
            # looking for entries like the following:
            #   <h2 id="1406001763-20210628">14.0.600.1763, 2021/06/28</h2>
            #   <p><em>(Product Version: 14.0.600.1763)</em></p>
            $versionPattern = '<h2 id="[^"]+">(?<version>\d+\.\d+\.\d+\.\d+), (?<date>\d+/\d+/\d+)</h2>(?:\s*<p><em>\(Product Version: (?<productversion>\d+\.\d+\.\d+\.\d+)\)</em></p>)?'
            $versionMatches = [regex]::Matches($section, $versionPattern)
       
            # Process each version match
            foreach ($versionMatch in $versionMatches)
            {
                $version = [version]($versionMatch.Groups['version'].Value)
                $date = $versionMatch.Groups['date'].Value
                # If we don't find a build version, use the version instead
                $buildVersion = if($versionMatch.Groups['productversion'].Success){[version]($versionMatch.Groups['productversion'].Value)}else{$version}
               
                # Add to results
                $versionObjectList.Add([PSCustomObject]@{
                    ServerType = $title
                    Version = $version
                    Build = $buildVersion
                    VersionString = "$title - $version - Releasedate: $date"
                })
            }
        }
     
        # GETTING DATA FOR POWERBI REPORT SERVER
        # SQL Server PowerBi Report Server
        #try
        #{
            # Define the base parameters for Invoke-WebRequest
            $params = @{
                Uri = $PowerBIReportServerVersionListURI
                UseBasicParsing = $true
                ErrorAction = 'Stop'
            }
    
            # Check if a proxy URL is provided and add it to the parameters if it is
            if ($ProxyURI) {
                $params['Proxy'] = $ProxyURI
            }
    
            # Use parameter splatting to invoke the web request with the defined parameters
            $webRequestResult = Invoke-WebRequest @params
        #}
        #catch
        #{
        #    Write-Output "Failed to retrieve the page: $($uri)"
        #    Write-Output "Error: $($_.Exception.Message)"
        #    break
        #}          
     
        # Example strings we try to parse:
        # "Version:1.20.8944.34536 (build 15.0.1115.194), Released: June 27, 2024"
        # "Version: 1.18.8683.7488(build 15.0.1113.165), Released: October 10, 2023"
        $regexString = '(Version).*(?<versioninfo>\d+\.\d+\.\d+\.\d+).*(?<buildinfo>build.*\d+\.\d+\.\d+\.\d+).*\<\/em\>'
        [array]$matchResultList = [regex]::Matches($webRequestResult.Content, $regexString, 1) # 1 means not case sensitive
        Write-Verbose "Found $($matchResultList.count) versions listed on the page: `"$($uri)`""

        foreach($versionItem in $matchResultList)
        {
            $versionString = 'PowerBI Report Server - {0}' -f $versionItem.groups['0'].value -replace '<.*?>'
    
            $versionObjectList.Add([PSCustomObject]@{
                ServerType = 'SQL Server PowerBI Report Server'
                Version = [version]$versionItem.groups['versioninfo'].value
                Build = [version]($versionItem.groups['buildinfo'].value -replace 'build').Trim()
                VersionString = $versionString
            })
        }
        
        return $versionObjectList
        # Total List results
        Write-Verbose "Found $($versionObjectList.count) versions of Report Server"
}
#endregion


#region main script logic
$outList = [System.Collections.Generic.List[pscustomobject]]::new()

# object to store the status of the script
$scriptStatusObject = [pscustomobject]@{
    CheckType = 'SSRS'
    Name = "ScriptStatus"
    SystemName = $env:COMPUTERNAME
    Status = 'Ok'
    SiteCode = $null
    Description = $null
    PossibleActions = $null
}

[array]$listOfReportServers = Get-ReportServerMetadata -ProviderMachineName $ProviderMachineName -SiteCode $SiteCode -ForceWSMANConnection:$ForceWSMANConnection -TestMode:$TestMode 

$versionObjectList = Get-ReportServerVersionList -ProxyURI $ProxyURI

if ($listOfReportServers.count -gt 0)
{

    $finalServerList = [System.Collections.Generic.List[pscustomobject]]::new()
    # Lets now test the servers
    $newVersionFound = $false
    foreach($Server in $listOfReportServers)
    {
        # Find matching version to find SQL Reporting Server Type and related versions
        [array]$buildVersionListEqualServerVersion = $versionObjectList.Where({$_.Build -eq $Server.BuildVersion})
       
        if($buildVersionListEqualServerVersion.count -eq 0)
        {
            Write-Verbose "Report Server Build Version not found in list from version website: `"$($Server.BuildVersion)`""
            $Server.Status = "Report Server Build Version not found in list from version website: `"$($Server.BuildVersion)`""
        }
        else
        {
            # We need to check if the version is unique for all SQL versions
            If(($buildVersionListEqualServerVersion | Select-Object -Property ServerType -Unique).ServerType.count -ne 1)
            {
                $Server.Status = "Cannot determine SQL server type. Version seems not to be unique between SQL server versions"
            }
            else
            {
                $serverType = $buildVersionListEqualServerVersion[0].Servertype
                $Server.ServerType = $serverType
                $server.VersionString = $buildVersionListEqualServerVersion[0].VersionString

                [array]$buildVersionListGreaterEqualServerVersion = $versionObjectList.Where({($_.ServerType -eq $serverType) -and ($_.Build -ge $Server.BuildVersion)})
                $Server.BuildVersionLatest = ($buildVersionListGreaterEqualServerVersion | Select-Object -First 1).Build
                if($buildVersionListGreaterEqualServerVersion.count -eq 1)
                {
                    Write-Verbose "Report Server Build Version is latest version: `"$($Server.BuildVersion)`""
                    $Server.Status = "Report Server Build Version is latest version: `"$($Server.BuildVersion)`""
                    $server.VersionStringLatest = $buildVersionListEqualServerVersion[0].VersionString
                    $newVersionFound = $true
                }
                else
                {
                    $latestBuild = ($buildVersionListGreaterEqualServerVersion | Select-Object -First 1).Build
                    $outString = 'Report Server Build Version "{0}" is {1} version/s behind latest version: "{2}"' -f ($Server.BuildVersion), ($buildVersionListGreaterEqualServerVersion.count -1), $latestBuild
                    Write-Verbose $outString
                    $Server.Status = $outString
                    $server.VersionStringLatest = ($buildVersionListGreaterEqualServerVersion | Select-Object -First 1).VersionString
                    $newVersionFound = $true
                }
            }
        }
        $finalServerList.Add($server)
    }
}
else
{
    Write-Host "No Report Servers in ConfigMgr environment found"
    break
}


#  [ValidateSet("Object","JSON","GridView", "MonAgentJSON", "MonAgentJSONCompressed","HTMLMail","PSObject","PrtgString","PrtgJSON","VersionList")]
Switch ($OutputMode)
{
    "MonAgentJSON" 
    {
        $finalServerList | ConvertTo-CustomMonitoringObject -OutputType MonAgentObject | ConvertTo-Json -Depth 2
    }
    "MonAgentJSONCompressed"
    {
        $finalServerList | ConvertTo-CustomMonitoringObject -OutputType MonAgentObject | ConvertTo-Json -Depth 2 -Compress
    }
    'List'
    {
        $finalServerList | Format-List
    }
    "GridView"
    {
        $versionObjectList | Out-GridView
    }
    'HTMLMail'
    {
        if ($SendMailOnlyWhenNewVersionsFound -and ($newVersionFound -eq $false))
        {
            Write-Host 'No changes found. No email send.' -ForegroundColor Yellow
            Exit
        }

        # Reference email script
        .$PSScriptRoot\Send-CustomMonitoringMail.ps1

        $MailInfotext = '<br>{0}' -f $MailInfotext
        Send-CustomMonitoringMail -MailMessageObject $finalServerList -MailSubject $MailSubject -MailInfotext $MailInfotext        
    }
    "PSObject"
    {
        $finalServerList
    }
    "PRTGString"
    {
        $badResults = $finalServerList.Where({$_.Status -ine 'OK'}) 
        if ($badResults)
        {
            $resultString = '{0}:ConfigMgr Components in failure state' -f $badResults.count
            Write-Output $resultString
        }
        else
        {
            Write-Output "0:No active ConfigMgr component alerts"
        }
    }
    "PRTGJSON"
    {
        $finalServerList | ConvertTo-CustomMonitoringObject -OutputType PrtgObject -PrtgLookupFileName $PrtgLookupFileName | ConvertTo-Json -Depth 3
    }
    "JSON"
    {
        $finalServerList | ConvertTo-Json -Depth 5
    }
}
