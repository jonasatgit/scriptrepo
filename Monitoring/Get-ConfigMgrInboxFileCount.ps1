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
    Script to monitor ConfigMgr/MECM performance counters
    
.DESCRIPTION
    The script reads from an in script hashtable called "$referenceData" to validate a specific performance counter
    Each counter takes about one second to read. Take this into account when validating a large number of perf counters
    Exclude Counters by simply uncomment them in the list of "$referenceData"
    Source: https://github.com/jonasatgit/scriptrepo

.EXAMPLE
    Get-ConfigMgrInboxFileCount.ps1

.INPUTS
   None

.OUTPUTS
   Compressed JSON string 
    
#>
[CmdletBinding()]
# String "MaxValue=" just for readability. Will be removed later.
$referenceData = @{}
$referenceData.add('\SMS Inbox(aikbmgr.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(AIKbMgr.box>RETRY)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(amtproxymgr.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(amtproxymgr.box>BAD)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(amtproxymgr.box>disc.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(amtproxymgr.box>mtn.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(amtproxymgr.box>om.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(amtproxymgr.box>prov.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(amtproxymgr.box>wol.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(auth>dataldr.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(auth>ddm.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(auth>ddm.box>regreq)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(auth>ddm.box>userddrsonly)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(auth>sinv.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(auth>statesys.box>incoming)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(auth>statesys.box>incoming>high)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(auth>statesys.box>incoming>low)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(bgb.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(bgb.box>bad)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(COLLEVAL.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(COLLEVAL.box>RETRY)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(dataldr.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(ddm.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(despoolr.box>receive)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(distmgr.box>incoming)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(hman.box>ForwardingMsg)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(notictrl.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(offermgr.box>INCOMING)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(OGprocess.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(polreq.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(rcm.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(replmgr.box>incoming)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(schedule.box>outboxes>LAN)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(schedule.box>requests)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(sinv.box)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(statmgr.box>statmsgs)\File Current Count','MaxValue=500')
$referenceData.add('\SMS Inbox(swmproc.box>usage)\File Current Count','MaxValue=500')


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


$referenceData.GetEnumerator() | ForEach-Object {

    $maxValue = $_.value -split '='

    $counterResult = Get-Counter -Counter $_.key -MaxSamples 1 -ErrorAction SilentlyContinue
    if ($counterResult)
    {
        # Check if counter readings over the limit and output the counter if so
        $readings = $counterResult.Readings -split ':'
        if ($readings[1] -gt $maxValue[1])
        {
            # Temp object for results
            # Status: 0=OK, 1=Warning, 2=Critical, 3=Unknown
            $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
            $tmpResultObject.Name = $systemName
            $tmpResultObject.Epoch = 0
            $tmpResultObject.Status = 1
            $tmpResultObject.ShortDescription = 'Counter: {0} Value: {1} Over limit: {2}' -f $_.key, $readings[1], $maxValue[1]
            $tmpResultObject.Debug = ''
            [void]$resultsObject.Add($tmpResultObject)
        }
    }
    else
    {
        # Temp object for results
        # Status: 0=OK, 1=Warning, 2=Critical, 3=Unknown
        $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
        $tmpResultObject.Name = $systemName
        $tmpResultObject.Epoch = 0
        $tmpResultObject.Status = 1
        $tmpResultObject.ShortDescription = 'Counter: {0} NOT found!' -f $_.key
        $tmpResultObject.Debug = ''
        [void]$resultsObject.Add($tmpResultObject)        
    }

}


# used as a temp object for JSON output
$outObject = New-Object psobject | Select-Object InterfaceVersion, Results
$outObject.InterfaceVersion = 1
if ($resultsObject)
{
    $outObject.Results = $resultsObject
}
else
{
    $tmpResultObject = New-Object psobject | Select-Object Name, Epoch, Status, ShortDescription, Debug
    $tmpResultObject.Name = $systemName
    $tmpResultObject.Epoch = 0
    $tmpResultObject.Status = 0
    $tmpResultObject.ShortDescription = ''
    $tmpResultObject.Debug = ''

    $outObject.Results = $tmpResultObject
}


$outObject | ConvertTo-Json -Compress 
