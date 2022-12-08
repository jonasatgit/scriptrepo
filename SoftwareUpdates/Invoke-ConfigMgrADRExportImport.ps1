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
    [string]$FilePath,
    [Parameter(Mandatory=$false)]
    [bool]$AddExample = $true
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


#region XML example 
$xmlExampleForDocumentation = @'
<ADR-DOCUMENNTATION>
    <!--Name of ADR -->
    <Name>SRV-2019</Name>
    <!--ID of ADR -->
    <ID>1</ID>
    <!--Run schedule string of ADR. Can be converted with "Convert-CMSchedule -ScheduleString '50E74D00001A2000'"-->
    <Schedule>50E74D00001A2000</Schedule>
    <!--Information about update package. Not set if ADR is set to not use a pachage and point clients to Windows Update online service -->
    <ContentTemplate>
        <PackageID>P0200011</PackageID>
        <ContentLocales>
            <Locale>Locale:9</Locale>
            <Locale>Locale:0</Locale>
        </ContentLocales>
        <O365ContentLocales>
            <Locale>Locale:1033</Locale>
            <Locale>Locale:0</Locale>
        </O365ContentLocales>
        <ContentSources>
            <Source Name="Internet" Order="1" />
            <Source Name="WSUS" Order="2" />
            <Source Name="UNC" Order="3" Location="" />
        </ContentSources>
    </ContentTemplate>
    <DeploymentProperties>
        <!-- DeploymentId has no value. This is just the general deployment setting for all deployments -->
        <DeploymentId />
        <!-- Name of deployment -->
        <DeploymentName>SRV-2019</DeploymentName>
        <!-- DeploymentDescription has no value -->
        <DeploymentDescription />
        <!-- Unique_ID of update group the ADR will update or use for deployments -->
        <UpdateGroupId>ScopeId_0C192617-7E7D-422B-979B-31FF58D765E6/AuthList_84be3235-3bd9-47ce-999c-904671d5c94a</UpdateGroupId>
        <!-- ADR language LocaleId -->
        <LocaleId>1033</LocaleId>
        <!-- If "True" the ADR will update the same update group. If "false" the ADR will create a new group each time new updates are detected -->
        <UseSameDeployment>false</UseSameDeployment>
        <!-- If "True" the deployment will be anabled. If "false" the deployment will be disabled -->
        <EnableAfterCreate>true</EnableAfterCreate>
        <NoEULAUpdates>false</NoEULAUpdates>
        <AlignWithSyncSchedule>false</AlignWithSyncSchedule>
        <ScopeIDs>
            <ScopeID>SMS00UNA</ScopeID>
        </ScopeIDs>
        <EnableFailureAlert>true</EnableFailureAlert>
        <IsServicingPlan>false</IsServicingPlan>
    </DeploymentProperties>
    <ADRDeployments>
        <Deployment>
            <DeploymentId>{3ca7adc3-6b15-4fec-ad86-518ec59aa270}</DeploymentId>
            <DeploymentNumber>0</DeploymentNumber>
            <CollectionId>SMS00001</CollectionId>
            <IncludeSub>true</IncludeSub>
            <Utc>false</Utc>
            <Duration>1</Duration>
            <DurationUnits>Days</DurationUnits>
            <AvailableDeltaDuration>1</AvailableDeltaDuration>
            <AvailableDeltaDurationUnits>Days</AvailableDeltaDurationUnits>
            <SoftDeadlineEnabled>false</SoftDeadlineEnabled>
            <SuppressServers>Unchecked</SuppressServers>
            <SuppressWorkstations>Unchecked</SuppressWorkstations>
            <PersistOnWriteFilterDevices>Unchecked</PersistOnWriteFilterDevices>
            <RequirePostRebootFullScan>Checked</RequirePostRebootFullScan>
            <AllowRestart>false</AllowRestart>
            <DisableMomAlert>false</DisableMomAlert>
            <GenerateMomAlert>false</GenerateMomAlert>
            <UseRemoteDP>true</UseRemoteDP>
            <UseUnprotectedDP>true</UseUnprotectedDP>
            <UseBranchCache>true</UseBranchCache>
            <EnableDeployment>true</EnableDeployment>
            <EnableWakeOnLan>false</EnableWakeOnLan>
            <AllowDownloadOutSW>false</AllowDownloadOutSW>
            <AllowInstallOutSW>true</AllowInstallOutSW>
            <EnableAlert>false</EnableAlert>
            <AlertThresholdPercentage>0</AlertThresholdPercentage>
            <AlertDuration>2</AlertDuration>
            <AlertDurationUnits>Weeks</AlertDurationUnits>
            <EnableNAPEnforcement>false</EnableNAPEnforcement>
            <UserNotificationOption>DisplayAll</UserNotificationOption>
            <LimitStateMessageVerbosity>true</LimitStateMessageVerbosity>
            <StateMessageVerbosity>1</StateMessageVerbosity>
            <AllowWUMU>true</AllowWUMU>
            <AllowUseMeteredNetwork>true</AllowUseMeteredNetwork>
            <PreDownloadUpdateContent>false</PreDownloadUpdateContent>
        </Deployment>
    </ADRDeployments>
    <UpdateDefinition>
        <UpdateXMLDescriptionItems>
            <UpdateXMLDescriptionItem PropertyName="LocalizedDisplayName" UIPropertyName="">
                <MatchRules>
                    <string>-Itanium</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="ArticleID" UIPropertyName="">
                <MatchRules>
                    <string>-Kb123456</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="BulletinID" UIPropertyName="">
                <MatchRules>
                    <string>-MS16-100</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="ContentSize" UIPropertyName="">
                <MatchRules>
                    <string>&gt;=100</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="CustomSeverity" UIPropertyName="">
                <MatchRules>
                    <string>2</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="DateRevised" UIPropertyName="">
                <MatchRules>
                    <string>0:0:28:0</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="LocalizedDescription" UIPropertyName="">
                <MatchRules>
                    <string>-Best update ever</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="IsDeployed" UIPropertyName="">
                <MatchRules>
                    <string>true</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="UpdateLocales" UIPropertyName="">
                <MatchRules>
                    <string>Locale:5</string>
                    <string>Locale:6</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="_Product" UIPropertyName="">
                <MatchRules>
                    <string>Product:12c24e87-bd40-451b-9477-2c2bf501e0d7|Visual Studio 2022</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="NumMissing" UIPropertyName="">
                <MatchRules>
                    <string>&lt;=40</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="Severity" UIPropertyName="">
                <MatchRules>
                    <string>8</string>
                    <string>2</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="IsSuperseded" UIPropertyName="">
                <MatchRules>
                    <string>true</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="LocalizedDisplayName" UIPropertyName="">
                <MatchRules>
                    <string>-.Net</string>
                    <string>-Security only</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="_UpdateClassification" UIPropertyName="">
                <MatchRules>
                    <string>UpdateClassification:0fa1201d-4330-4fa8-8ae9-b877473b6441|Security Updates</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="CMTag" UIPropertyName="">
                <MatchRules>
                    <string>0</string>
                    <string>2</string>
                    <string>3</string>
                    <string>1</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
            <UpdateXMLDescriptionItem PropertyName="_Company" UIPropertyName="">
                <MatchRules>
                    <string>Company:56309036-4c77-4dd9-951a-99ee9c246a94|Microsoft</string>
                </MatchRules>
            </UpdateXMLDescriptionItem>
        </UpdateXMLDescriptionItems>
    </UpdateDefinition>
</ADR-DOCUMENNTATION>
'@
#enregion

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
            # Let's remove invalid filename chars
            [char[]]$invalidFileNameChars = [IO.Path]::GetinvalidFileNameChars()
            $fileName = $adr.Name -replace ('[{0}]' -f ([regex]::Escape($invalidFileNameChars -join '')))
            $fileName = $fileName.Trim()

            $adrFileName = "{0}\{1}_{2}.xml" -f $PSScriptRoot, $fileName, (Get-Date -f 'yyyyMMdd-hhmm')
            $xmlWriter = New-Object System.XMl.XmlTextWriter($adrFileName,$Null)
            $xmlWriter.Formatting = 'Indented'
            $xmlWriter.Indentation = 1
            $XmlWriter.IndentChar = "`t"
            $xmlWriter.WriteStartDocument()
            $xmlWriter.WriteComment('ADR Settings')
            $xmlWriter.WriteStartElement('ADRList')
        }

        if ($AddExample -and ($adrCounter -eq 1))
        {
            [xml]$tmpXMLData = $xmlExampleForDocumentation
            $tmpXMLData.WriteContentTo($xmlWriter) 
        }

        $xmlWriter.WriteComment("ADR $($adrCounter.ToString('000')) of $(($adrList.count).ToString('000')) ADRs")
        $xmlWriter.WriteStartElement('ADR')
        $xmlWriter.WriteElementString('Name',($adr.Name))
        $xmlWriter.WriteElementString('ID',($adr.AutoDeploymentID))
        $xmlWriter.WriteElementString('Schedule',($adr.Schedule))
        
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
