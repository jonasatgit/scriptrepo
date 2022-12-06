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
    Script to export or import Automatic Depployment Rules
    
.DESCRIPTION
    Script to export or import Automatic Depployment Rules

    IMPORTANT: Import not implemented yet

    Source: https://github.com/jonasatgit/scriptrepo

.PARAMETER ProviderMachineName
    Name of SMS Provider machine. If not set the local system is used. Will be used to get the SiteCode and to read or set ADR information

.PARAMETER ForceDCOMConnection
    Switch parameter to force Get-CimInstacne to use DCOM (WMI) instead of WinRM

.PARAMETER IndividualFiles
    Switch parameter to create individual files per ADR.

.PARAMETER ImportADRsFromFile
    Switch parameter to import ADRs instead of exporting them

.PARAMETER FilePath
    Path to an XML file containing ADR information to be imported

.EXAMPLE
    Invoke-ConfigMgrADRExportImport.ps1

.EXAMPLE
    Invoke-ConfigMgrADRExportImport.ps1 -IndividualFiles

.INPUTS
     None

.OUTPUTS
    XML file in root directory of script.

.LINK
    https://github.com/jonasatgit/scriptrepo
#>


[CmdletBinding(DefaultParametersetName='Default')]
param 
(
    [Parameter(Mandatory=$false)]
    [string]$ProviderMachineName = $env:COMPUTERNAME,
    [Parameter(Mandatory=$false)]
    [switch]$ForceDCOMConnection,
    [Parameter(ParameterSetName = 'Export',Mandatory=$false)]
    [switch]$IndividualFiles,
    [Parameter(ParameterSetName = 'Import',Mandatory=$false)]
    [switch]$ImportADRsFromFile,
    [Parameter(ParameterSetName = 'Import',Mandatory=$true)]
    [string]$FilePath
)


#region CIMSession settings
if ($ForceDCOMConnection)
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

if (-NOT($siteCode))
{
    # stopping script, no sitecode means script cannot run
    $cimSession | Remove-CimSession -ErrorAction SilentlyContinue
    exit 1
}
Write-Verbose "$($siteCode) detected sitecode"
#endregion

try 
{
    [array]$SMSCategoryInstance = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "select * from SMS_UpdateCategoryInstance"
    # Get list of ADRs
    [array]$adrList = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "select * from SMS_AutoDeployment"
    # Get list of ADR deployments 
    [array]$adrDeploymentList = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "select * from SMS_ADRDeploymentSettings"   
}
catch 
{
    $Error[0].Exception
    $cimSession | Remove-cimSession
}

#region main export logic
if (-NOT ($ImportADRsFromFile))
{
    if (-NOT ($IndividualFiles))
    {
        $adrFileName = "{0}\ADRExport_{1}.xml" -f $PSScriptRoot, (Get-Date -f 'yyyyMMdd-hhmm')
        $xmlWriter = New-Object System.XMl.XmlTextWriter($adrFileName,$Null)
        $xmlWriter.Formatting = 'Indented'
        $xmlWriter.Indentation = 1
        $XmlWriter.IndentChar = "`t"
        $xmlWriter.WriteStartDocument()
        $xmlWriter.WriteComment('List of exported Automatic Deployment Rules')
        $xmlWriter.WriteStartElement('ADRList')
    }

    $adrCounter=0
    foreach ($adr in $adrList)
    {
        $adrCounter++
        # Load lazy properties
        $adr = $adr | Get-CimInstance -CimSession $cimSession
        # Let's replace uneeded single quote sign
        $updateRuleString = $adr.UpdateRuleXML -replace '>''','>' -replace '''<','<'
        # Let's find all uniqueIDs and add a readable names to it
        $regExResult = [regex]::Matches($updateRuleString,'(Company:[0-9a-f-]*)|(Product:[0-9a-f-]*)|(UpdateClassification:[0-9a-f-]*)')
        foreach ($resultItem in $regExResult)
        {
            # Looking for the LocalizedName
            $searchResult = $SMSCategoryInstance.Where({$_.CategoryInstance_UniqueID -eq $resultItem.Value})
            $newStringValue = '{0}|{1}' -f $resultItem.Value, $searchResult.LocalizedCategoryInstanceName
            # Replace GUID like entry and add LocalizedName to it for better readability
            $updateRuleString = $updateRuleString -replace ($resultItem.Value), ($newStringValue)
        }

        # Getting list of deployments for ADR
        [array]$adrDeployments = $adrDeploymentList.where({$_.RuleId -eq $adr.AutoDeploymentID}) 
        # Load lazy properties of deployments
        $adrDeployments = $adrDeployments | Get-CimInstance -CimSession $cimSession

        if ($IndividualFiles)
        {
            $adrFileName = "{0}\{1}_{2}.xml" -f $PSScriptRoot, $adr.Name, (Get-Date -f 'yyyyMMdd-hhmm')
            $xmlWriter = New-Object System.XMl.XmlTextWriter($adrFileName,$Null)
            $xmlWriter.Formatting = 'Indented'
            $xmlWriter.Indentation = 1
            $XmlWriter.IndentChar = "`t"
            $xmlWriter.WriteStartDocument()
            $xmlWriter.WriteComment('ADR Settings')
            $xmlWriter.WriteStartElement('ADRList')
        }

        $xmlWriter.WriteComment("ADR $($adrCounter.ToString('000')) of $(($adrList.count).ToString('000')) ADRs")
        $xmlWriter.WriteStartElement('ADR')
        $xmlWriter.WriteElementString('Name',($adr.Name))
        
        #region ContentTemplate
        $xmlWriter.WriteComment('ContentTemplate settings')
        $xmlWriter.WriteStartElement('ContentTemplate')
        [xml]$ContentTemplate = $adr.ContentTemplate
        $ContentTemplate.ContentActionXML.WriteContentTo($xmlWriter)       
        $xmlWriter.WriteEndElement()
        #endregion

        #region DeploymentProperties
        $xmlWriter.WriteComment('General deployment properties')
        $xmlWriter.WriteStartElement('DeploymentProperties')
        [xml]$DeploymentProperties = $adr.AutoDeploymentProperties
        $DeploymentProperties.AutoDeploymentRule.WriteContentTo($xmlWriter)
        $xmlWriter.WriteEndElement()
        #endregion

        #region DeploymentTemplate
        # Not really required since it will be part of "ADRDeployments"
        <#
        $xmlWriter.WriteStartElement('DeploymentTemplate')
        [xml]$DeploymentTemplate = $adr.DeploymentTemplate
        $DeploymentTemplate.DeploymentCreationActionXML.WriteContentTo($xmlWriter)
        $xmlWriter.WriteEndElement()
        #>
        #endregion

        #region ADR deployments
        $xmlWriter.WriteComment('List of deployments per ADR')
        $xmlWriter.WriteStartElement('ADRDeployments')
        $i=0
        foreach ($deployment in $adrDeployments)
        {
            $i++
            $xmlWriter.WriteComment("Deployment $($i.ToString('000')) of $(($adrDeployments.count).ToString('000')) deployments")
            $xmlWriter.WriteStartElement('Deployment')
            [xml]$DeploymentTemplate = $deployment.DeploymentTemplate
            $DeploymentTemplate.DeploymentCreationActionXML.WriteContentTo($xmlWriter)
            $xmlWriter.WriteEndElement()
        }
        $xmlWriter.WriteEndElement()
        #endregion

        #region DeploymentTemplate
        $xmlWriter.WriteComment('List of update definitions the ADR will search for')
        $xmlWriter.WriteStartElement('UpdateDefinition')
        [xml]$UpdateRuleXML = $updateRuleString
        $UpdateRuleXML.UpdateXML.WriteContentTo($xmlWriter)
        $xmlWriter.WriteEndElement()
        #endregion
        
        # End of ADR element
        $xmlWriter.WriteEndElement()

        # We need to close the file in case we have to create seperate files for each ADR
        if ($IndividualFiles)
        {
            $xmlWriter.WriteEndElement()
            $xmlWriter.WriteEndDocument()
            $xmlWriter.Flush()
            $xmlWriter.Close()
        }
    }

    # We need to close the file in case we have just ine file for all ADRs
    if (-NOT($IndividualFiles))
    {
        $xmlWriter.WriteEndElement()
        $xmlWriter.WriteEndDocument()
        $xmlWriter.Flush()
        $xmlWriter.Close()
    }

    # Let's remove our open session
    $cimSession | Remove-cimSession
}

