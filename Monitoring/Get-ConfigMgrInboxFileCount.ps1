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
    Script to monitor ConfigMgr/MECM performance counter
    Version: 2022-03-23
    
.DESCRIPTION
    The script reads from an in script hashtable called "$referenceData" to validate a list of specific performance counter
    The inbox perf counter refresh intervall is 15 minutes. It therefore makes no sense to validate a counter more often. 
    Get the full list of available inbox perf counter via the following command:
    Get-WmiObject Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox | select Name, FileCurrentCount
   Source: https://github.com/jonasatgit/scriptrepo

.PARAMETER GridViewOutput
    Switch parameter to be able to output the results in a GridView instead of compressed JSON

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1 -GridViewOutput

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
#Ensure that the Script is running with elevated permissions
if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Warning 'The script needs admin rights to run. Start PowerShell with administrative rights and run the script again'
    return 
}
# Get the full list of available inbox perf counter via the following command:
# Get-WmiObject Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox | select Name, FileCurrentCount

# String "MaxValue=" just for readability. Will be removed later.
$referenceData = @{}                                                                                                                                                                                                           
$referenceData.add('hman.box>ForwardingMsg','MaxValue=500')                                                                                                                                                                                         
#$referenceData.add('schedule.box>outboxes>LAN ','MaxValue=500')                                                                                                                                                                                      
$referenceData.add('schedule.box>requests','MaxValue=500')                                                                                                                                                                                         
$referenceData.add('dataldr.box','MaxValue=500')                                                                                                                                                                                                      
$referenceData.add('sinv.box','MaxValue=500')                                                                                                                                                                                                         
$referenceData.add('despoolr.box>receive','MaxValue=500')                                                                                                                                                                                             
$referenceData.add('replmgr.box>incoming','MaxValue=500')                                                                                                                                                                                             
$referenceData.add('ddm.box','MaxValue=500')                                                                                                                                                                                                          
$referenceData.add('rcm.box','MaxValue=500')                                                                                                                                                                                                          
$referenceData.add('bgb.box','MaxValue=500')                                                                                                                                                                                                          
$referenceData.add('bgb.box>bad','MaxValue=500')                                                                                                                                                                                                      
#$referenceData.add('notictrl.box','MaxValue=500')                                                                                                                                                                                                     
#$referenceData.add('AIKbMgr.box>RETRY','MaxValue=500')                                                                                                                                                                                                
$referenceData.add('COLLEVAL.box','MaxValue=500')                                                                                                                                                                                                     
#$referenceData.add('amtproxymgr.box>disc.box','MaxValue=500')                                                                                                                                                                                         
#$referenceData.add('amtproxymgr.box>om.box','MaxValue=500')                                                                                                                                                                                           
#$referenceData.add('amtproxymgr.box>wol.box','MaxValue=500')                                                                                                                                                                                          
#$referenceData.add('amtproxymgr.box>prov.box','MaxValue=500')                                                                                                                                                                                         
$referenceData.add('COLLEVAL.box>RETRY','MaxValue=500')                                                                                                                                                                                               
#$referenceData.add('amtproxymgr.box>BAD','MaxValue=500')
#$referenceData.add('amtproxymgr.box>mtn.box','MaxValue=500')                                                                                                                                                                                         
$referenceData.add('offermgr.box>INCOMING','MaxValue=500')                                                                                                                                                                                           
#$referenceData.add('amtproxymgr.box','MaxValue=500')                                                                                                                                                                                                 
#$referenceData.add('aikbmgr.box','MaxValue=500')                                                                                                                                                                                                     
$referenceData.add('auth>ddm.box','MaxValue=500')                                                                                                                                                                                                    
$referenceData.add('auth>ddm.box>userddrsonly','MaxValue=500')                                                                                                                                                                                       
$referenceData.add('auth>ddm.box>regreq','MaxValue=500')                                                                                                                                                                                             
$referenceData.add('auth>sinv.box','MaxValue=500')                                                                                                                                                                                                   
$referenceData.add('auth>dataldr.box','MaxValue=500')                                                                                                                                                                                                
$referenceData.add('statmgr.box>statmsgs','MaxValue=500')                                                                                                                                                                                            
$referenceData.add('swmproc.box>usage','MaxValue=500')                                                                                                                                                                                               
$referenceData.add('distmgr.box>incoming','MaxValue=500')                                                                                                                                                                                            
$referenceData.add('auth>statesys.box>incoming','MaxValue=500')                                                                                                                                                                                      
$referenceData.add('polreq.box','MaxValue=500')                                                                                                                                                                                                      
$referenceData.add('auth>statesys.box>incoming>low','MaxValue=500')                                                                                                                                                                                  
$referenceData.add('auth>statesys.box>incoming>high','MaxValue=2000')                                                                                                                                                                                 
#$referenceData.add('OGprocess.box','MaxValue=500')                                                                                                                                                                                                   


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

$inboxCounterList = Get-WmiObject Win32_PerfRawData_SMSINBOXMONITOR_SMSInbox | Select-Object Name, FileCurrentCount -ErrorAction SilentlyContinue
if ($inboxCounterList)
{
    
    foreach ($inboxCounter in $inboxCounterList)
    {
        $counterValue = $null
        $counterValue = $referenceData[($inboxCounter.Name)]
        if ($counterValue)
        {
            # split "MaxValue=500"
            [array]$counterMaxValue = $counterValue -split '='

            if ($inboxCounter.FileCurrentCount -gt $counterMaxValue[1])
            {
                # Temp object for results
                # Status: 0=OK, 1=Warning, 2=Critical, 3=Unknown
                $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
                $tmpResultObject.Name = $systemName
                $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
                $tmpResultObject.Status = 1
                $tmpResultObject.ShortDescription = '{0} files in {1} over limit of {2}' -f $inboxCounter.FileCurrentCount, $inboxCounter.Name, $counterMaxValue[1]
                $tmpResultObject.Debug = ''
                [void]$resultsObject.Add($tmpResultObject)
                $badResult = $true      
            }
        }
    }

    # validate script reference data by looking for counter in actual local counter list
    $referenceData.GetEnumerator() | ForEach-Object {
        
        if ($inboxCounterList.name -notcontains $_.Key)
        {
            # Temp object for results
            # Status: 0=OK, 1=Warning, 2=Critical, 3=Unknown
            $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
            $tmpResultObject.Name = $systemName
            $tmpResultObject.Epoch = 0 # FORMAT: [int][double]::Parse((Get-Date (get-date).touniversaltime() -UFormat %s))
            $tmpResultObject.Status = 1
            $tmpResultObject.ShortDescription = 'Counter: `"{0}`" not found on machine! ' -f $_.key
            $tmpResultObject.Debug = ''
            [void]$resultsObject.Add($tmpResultObject) 
            $badResult = $true 
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

if ($GridViewOutput)
{
    $outObject.Results | Out-GridView
}
else
{
    $outObject | ConvertTo-Json -Compress
}
