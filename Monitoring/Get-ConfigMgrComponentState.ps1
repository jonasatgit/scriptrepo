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

<#
.Synopsis
    Script to monitor ConfigMgr component states
    
.DESCRIPTION
    The script will read the available ConfigMgr components which are monitored by ConfigMgr itself. 
    If one of those components is not in "Availability State" of 0, the script will out put the specific component in JSON format.
    You can exclude components like this: $excludedComponents = ('SMS_WSUS_SYNC_MANAGER','SMS_WSUS_CONFIGURATION_MANAGER')
    Source: https://github.com/jonasatgit/scriptrepo

.PARAMETER GridViewOutput
    Switch parameter to be able to output the results in a GridView instead of compressed JSON

.EXAMPLE
    Get-ConfigMgrComponentState.ps1

.EXAMPLE
    Get-ConfigMgrComponentState.ps1 -GridViewOutput

.INPUTS
   None

.OUTPUTS
   Compressed JSON string 
    
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [Switch]$GridViewOutput
)

# exclude specific components if needed
$excludedComponents = ('')

<#
.Synopsis
   function Test-ConfigMgrActiveSiteSystemNode 

.DESCRIPTION
   Test if a given FQDN is the active ConfigMgr Site System node
   Function to read from HKLM:\SOFTWARE\Microsoft\SMS\Identification' 'Site Servers' and determine the active site server node
   Possible values could be: 
        1;server1.contoso.local;
       1;server1.contoso.local;0;server2.contoso.local;
        0;server1.contoso.local;1;server2.contoso.local;

.PARAMETER SiteSystemFQDN
   FQDN of site system

.EXAMPLE
   Test-ConfigMgrActiveSiteSystemNode -SiteSystemFQDN 'server1.contoso.local'
#>
function Test-ConfigMgrActiveSiteSystemNode
{
    param
    (
        [string]$SiteSystemFQDN
    )

    $siteServers = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\SMS\Identification' -Name 'Site Servers' -ErrorAction SilentlyContinue
    if ($siteServers)
    {
        # Extract site system values from registry property 
        $siteSystemHashTable = @{}
        $siteSystems = [regex]::Matches(($siteServers.'Site Servers'),'(\d;[a-zA-Z0-9._-]+)')
        if($siteSystems.Count -gt 1)
        {
            # HA site systems found
            foreach ($SiteSystemNode in $siteSystems)
            {
                $tmpArray = $SiteSystemNode.value -split ';'
                $siteSystemHashTable.Add($tmpArray[1].ToLower(),$tmpArray[0]) 
            }
        }
        else
        {
            # single site system found
            $tmpArray = $siteSystems.value -split ';'
            $siteSystemHashTable.Add($tmpArray[1].ToLower(),$tmpArray[0]) 
        }
        
        return $siteSystemHashTable[($SiteSystemFQDN).ToLower()]
    }
    else
    {
        return $null
    }
}

# get system FQDN if possible
$win32Computersystem = Get-WmiObject -Class win32_computersystem -ErrorAction SilentlyContinue
if ($win32Computersystem)
{
    $systemName = '{0}.{1}' -f $win32Computersystem.Name, $win32Computersystem.Domain   
}
else
{
    $systemName = $env:COMPUTERNAME
}

# temp results object
$resultsObject = New-Object System.Collections.ArrayList
[bool]$badResult = $false
switch (Test-ConfigMgrActiveSiteSystemNode -SiteSystemFQDN $systemName)
{
    1 ## ACTIVE NODE FOUND. Run checks
    {
        $componentList = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\SMS\Operations Management\Components' 

        #$listOfMonitoredComponents = New-Object System.Collections.ArrayList
        foreach ($component in $componentList)
        {
            $componentName = ($component.Name | Split-Path -Leaf)

            if ($excludedComponents.Contains($componentName))
            {
                #skip component
            }
            else
            {
    
                $componentMonitoringType = $component | Get-ItemProperty -Name 'Site Component Manager Monitoring Type' -ErrorAction SilentlyContinue
                if($componentMonitoringType.'Site Component Manager Monitoring Type' -like 'Monitored*')
               {

                    $componentAvailabilityState = $component | Get-ItemProperty -Name 'Availability State' -ErrorAction SilentlyContinue
                    if($componentAvailabilityState.'Availability State' -ne 0)
                    {
                        # Temp object for results
                        # Status: 0=OK, 1=Warning, 2=Critical, 3=Unknown
                        $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
                        $tmpResultObject.Name = $systemName
                        $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
                        $tmpResultObject.Status = 2
                        $tmpResultObject.ShortDescription = 'Component failed: {0}' -f $componentName
                        $tmpResultObject.Debug = ''
                        [void]$resultsObject.Add($tmpResultObject)
                        $badResult = $true
                    }
                }
            }
        }


        # used as a temp object for JSON output
        $outObject = New-Object psobject | Select-Object InterfaceVersion, Results
        $outObject.InterfaceVersion = 1
        if ($badResult)
        {
            $outObject.Results = $resultsObject
        }
        else
        {
            $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
            $tmpResultObject.Name = $systemName
            $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
            $tmpResultObject.Status = 0
            $tmpResultObject.ShortDescription = 'ok'
            $tmpResultObject.Debug = ''
            [void]$resultsObject.Add($tmpResultObject)
            $outObject.Results = $resultsObject
        }
    }

    0 ## PASSIVE NODE FOUND. Nothing to do.
    {
        $outObject = New-Object psobject | Select-Object InterfaceVersion, Results
        $outObject.InterfaceVersion = 1
        
        $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
        $tmpResultObject.Name = $systemName
        $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
        $tmpResultObject.Status = 0
        $tmpResultObject.ShortDescription = 'ok'
        $tmpResultObject.Debug = ''
        [void]$resultsObject.Add($tmpResultObject)
        $outObject.Results = $resultsObject       

    }

    Default ## NO STATE FOUND
    {
        # No state found. Either no ConfigMgr Site System or script error
        $outObject = New-Object psobject | Select-Object InterfaceVersion, Results
        $outObject.InterfaceVersion = 1
        
        $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
        $tmpResultObject.Name = $systemName
        $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
        $tmpResultObject.Status = 1
        $tmpResultObject.ShortDescription = 'Error: No ConfigMgr Site System found'
        $tmpResultObject.Debug = ''
        [void]$resultsObject.Add($tmpResultObject)
        $outObject.Results = $resultsObject
    }
}

if ($GridViewOutput)
{
    $outObject.Results | Out-GridView
}
else
{
    $outObject | ConvertTo-Json -Compress
}  
