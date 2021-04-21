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
    Script to validate the activated WSUS update categories and products of a ConfigMgr environment.
    
.DESCRIPTION
    The script is intended to compare a given set of WSUS update categories and products with the current state. 
    It is designed to either run within a ConfigMgr configuration item and a baseline or as a standalone script. 
    The script mode can be set via the parameter "OutputMode" and the default value is "CompareData" to be able to use the script as part of a 
    ConfigMgr configuration item.
    NOTE: Do not run the script in PowerShell ISE since that might give strange results. 
    For more information run "Get-Help .\Compare-WSUSSubscriptions.ps1 -Detailed"
    Source: https://github.com/jonasatgit/scriptrepo

.PARAMETER OutputMode
    The parameter OutputMode has four possible options:
    "CompareData":
        CompareData is the default value and will output the difference between the known state and the current state.
    "ShowData": 
        ShowData will open a GridView with active WSUS update categories and products.
    "ExportAsCSV":
        Will create a csv files in the same directory as the script containing all WSUS update categories and products.
    "CreateScript":
        CreateScript will create a new script (in the same directory) containing the same contant but will replace the known state with
        the current state for each WSUS update category and product.  
        The new script name will contain the old script name and the date and time of creation. 
        The new script can be used in a ConfigMgr configuration item directly without any extra changes to it. 
    
.PARAMETER ProviderMachineName
    Name/FQDN of the ConfigMgr SMS provider machine. 
    Default value is the local system

.PARAMETER SiteCode
    ConfigMgr sitecode.
    Will be detected automatically, but might be needed in some circumstances.

.PARAMETER ForceWSMANConnection
    Can be used to force Get-CimInstance to use WSMAN instead of DCOM for WMI queries. 

.EXAMPLE
    Compare knonw list of WSUS update categories and products with the current state.
    .\Compare-WSUSSubscriptions.ps1
    .\Compare-WSUSSubscriptions.ps1 -Verbose

.EXAMPLE
    Show WSUS update category and product state
    .\Compare-WSUSSubscriptions.ps1 -OutputMode ShowData

.EXAMPLE
    Export WSUS update category and product state
    .\Compare-WSUSSubscriptions.ps1 -OutputMode ExportAsCSV

.EXAMPLE
    Will create a new script containing the current WSUS update category and product state.
    .\Compare-WSUSSubscriptions.ps1 -OutputMode CreateScript

.EXAMPLE
    .\Compare-WSUSSubscriptions.ps1 -OutputMode ShowData -ForceWSMANConnection

.LINK 
    https://github.com/jonasatgit/scriptrepo
    
#>



#region Parameters
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [string]$ProviderMachineName = $env:COMPUTERNAME,
    [Parameter(Mandatory=$false)]
    [string]$SiteCode,
    [Parameter(Mandatory=$false)]
    [switch]$ForceWSMANConnection,
    [Parameter(Mandatory=$false)]
    [ValidateSet("ShowData", "ExportAsCSV", "CreateScript","CompareData")]
    [string]$OutputMode = 'CompareData'
)
#endregion

#region Initializing
$scriptPathAndName = ($MyInvocation.InvocationName)
$scriptName = $scriptPathAndName | Split-Path -Leaf
#endregion

#region reference data
$referenceData = @{}
$referenceData.add('Product:cb263e3f-6c5a-4b71-88fa-1706f9549f51','Product|Windows Internet Explorer 7 Dynamic Installer|True|False')
$referenceData.add('ProductFamily:523a2448-8b6c-458b-9336-307e1df6d6a6','ProductFamily|Microsoft Application Virtualization|True|False')
$referenceData.add('ProductFamily:116a3557-3847-4858-9f03-38e94b977456','ProductFamily|Antigen|True|False')
$referenceData.add('ProductFamily:0580151d-fd22-4401-aa2b-ce1e3ae62bc9','ProductFamily|Internet Security and Acceleration Server|True|False')
$referenceData.add('Product:8508af86-b85e-450f-a518-3b6f8f204eea','Product|New Dictionaries for Microsoft IMEs|True|False')
$referenceData.add('UpdateClassification:e0789628-ce08-4437-be74-2495b842f43b','UpdateClassification|Definition Updates|True|False')
$referenceData.add('ProductFamily:2425de84-f071-4358-aac9-6bbd6e0bfaa7','ProductFamily|Works|True|False')
$referenceData.add('Product:2cdbfa44-e2cb-4455-b334-fce74ded8eda','Product|Internet Security and Acceleration Server 2006|True|False')
$referenceData.add('Product:22bf57a8-4fe1-425f-bdaa-32b4f655284b','Product|Office Communications Server 2007 R2|True|False')
$referenceData.add('Product:26bb6be1-37d1-4ca6-baee-ec00b2f7d0f1','Product|Exchange Server 2007|True|False')
$referenceData.add('Product:c96c35fc-a21f-481b-917c-10c4f64792cb','Product|SQL Server Feature Pack|True|False')
$referenceData.add('Product:b627a8ff-19cd-45f5-a938-32879dd90123','Product|Internet Security and Acceleration Server 2004|True|False')
$referenceData.add('Product:90e135fb-ef48-4ad0-afb5-10c4ceb4ed16','Product|Windows Vista Dynamic Installer|True|False')
$referenceData.add('ProductFamily:477b856e-65c4-4473-b621-a8b230bb70d9','ProductFamily|Office|True|False')
$referenceData.add('Product:5d6a452a-55ba-4e11-adac-85e180bda3d6','Product|Antigen for Exchange/SMTP|True|False')
$referenceData.add('Product:569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5','Product|Windows Server 2016|True|True')
$referenceData.add('Product:83a83e29-7d55-44a0-afed-aea164bc35e6','Product|Exchange 2000 Server|True|False')
$referenceData.add('Product:575d68e2-7c94-48f9-a04f-4b68555d972d','Product|Windows Small Business Server 2008|True|False')
$referenceData.add('Product:7f44c2a7-bc36-470b-be3b-c01b6dc5dd4e','Product|Windows Server 2003, Datacenter Edition|True|False')
$referenceData.add('UpdateClassification:b4832bd8-e735-4761-8daf-37f882276dab','UpdateClassification|Tools|True|False')
$referenceData.add('Product:e88a19fb-a847-4e3d-9ae2-13c2b84f58a6','Product|Windows Media Dynamic Installer|True|False')
$referenceData.add('UpdateClassification:68c5b0a3-d1a6-4553-ae49-01d3a7827828','UpdateClassification|Service Packs|True|False')
$referenceData.add('Product:d22b3d16-bc75-418f-b648-e5f3d32490ee','Product|System Center Configuration Manager 2007|True|False')
$referenceData.add('Product:5964c9f1-8e72-4891-a03a-2aed1c4115d2','Product|HPC Pack 2008|True|False')
$referenceData.add('Product:e164fc3d-96be-4811-8ad5-ebe692be33dd','Product|Office Communications Server 2007|True|False')
$referenceData.add('Product:7e5d0309-78dd-4f52-a756-0259f88b634b','Product|Microsoft System Center Virtual Machine Manager 2008|True|False')
$referenceData.add('UpdateClassification:e6cf1350-c01b-414d-a61f-263d14d133b4','UpdateClassification|Critical Updates|True|True')
$referenceData.add('ProductFamily:5ef2c723-3e0b-4f87-b719-78b027e38087','ProductFamily|Microsoft System Center Data Protection Manager|True|False')
$referenceData.add('ProductFamily:ca9e8c72-81c4-11dc-8284-f47156d89593','ProductFamily|Expression|True|False')
$referenceData.add('Product:e9c87080-a759-475a-a8fa-55552c8cd3dc','Product|Microsoft Works 9|True|False')
$referenceData.add('ProductFamily:352f9494-d516-4b40-a21a-cd2416098982','ProductFamily|Exchange|True|False')
$referenceData.add('Product:8bc19572-a4b6-4910-b70d-716fecffc1eb','Product|Office Communicator 2007 R2|True|False')
$referenceData.add('Company:7c40e8c2-01ae-47f5-9af2-6e75a0582518','Company|Local Publisher|True|False')
$referenceData.add('ProductFamily:68623613-134c-4b18-bcec-7497ac1bfcb0','ProductFamily|Windows Small Business Server|True|False')
$referenceData.add('Product:c8a4436c-1043-4288-a065-0f37e9640d60','Product|Virtual PC|True|False')
$referenceData.add('UpdateClassification:77835c8d-62a7-41f5-82ad-f28d1af1e3b1','UpdateClassification|Driver Sets|False|False')
$referenceData.add('Product:6248b8b1-ffeb-dbd9-887a-2acf53b09dfe','Product|Office XP|True|False')
$referenceData.add('ProductFamily:6d992428-3b47-4957-bb1a-157bd8c73d38','ProductFamily|Virtual Server|True|False')
$referenceData.add('ProductFamily:0a4c6c73-8887-4d7f-9cbe-d08fa8fa9d1e','ProductFamily|SQL|True|False')
$referenceData.add('Product:3b4b8621-726e-43a6-b43b-37d07ec7019f','Product|Windows 2000 family|True|False')
$referenceData.add('Product:ce62f77a-28f3-4d4b-824f-0f9b53461d67','Product|Search Enhancement Pack|True|False')
$referenceData.add('Product:032e3af5-1ac5-4205-9ae5-461b4e8cd26d','Product|Windows Small Business Server 2003|True|False')
$referenceData.add('Product:4e487029-f550-4c22-8b31-9173f3f95786','Product|Windows Server Manager – Windows Server Update Services (WSUS) Dynamic Installer|True|False')
$referenceData.add('Product:5108d510-e169-420c-9a4d-618bdb33c480','Product|Expression Media 2|True|False')
$referenceData.add('Product:5cc25303-143f-40f3-a2ff-803a1db69955','Product|Locally published packages|True|False')
$referenceData.add('Product:5a456666-3ac5-4162-9f52-260885d6533a','Product|Systems Management Server 2003|True|False')
$referenceData.add('UpdateClassification:0fa1201d-4330-4fa8-8ae9-b877473b6441','UpdateClassification|Security Updates|True|True')
$referenceData.add('Product:60916385-7546-4e9b-836e-79d65e517bab','Product|SQL Server 2005|True|False')
$referenceData.add('UpdateClassification:cd5ffd1e-e932-4e3a-bf74-18bf0b1bbd83','UpdateClassification|Updates|True|False')
$referenceData.add('Product:784c9f6d-959a-433f-b7a3-b2ace1489a18','Product|Host Integration Server 2004|True|False')
$referenceData.add('UpdateClassification:ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0','UpdateClassification|Drivers|False|False')
$referenceData.add('ProductFamily:78f4e068-1609-4e7a-ac8e-174288fa70a1','ProductFamily|Systems Management Server|True|False')
$referenceData.add('Product:558f4bc3-4827-49e1-accf-ea79fd72d4c9','Product|Windows XP family|True|False')
$referenceData.add('Product:f61ce0bd-ba78-4399-bb1c-098da328f2cc','Product|Virtual Server|True|False')
$referenceData.add('UpdateClassification:5c9376ab-8ce6-464a-b136-22113dd69801','UpdateClassification|Applications|False|False')
$referenceData.add('ProductFamily:9476d3f6-a119-4d6e-9952-8ad28a55bba6','ProductFamily|System Center Virtual Machine Manager|True|False')
$referenceData.add('ProductFamily:2b496c37-f722-4e7b-8467-a7ad1e29e7c1','ProductFamily|Bing|True|False')
$referenceData.add('Product:eac7e88b-d8d4-4158-a828-c8fc1325a816','Product|Host Integration Server 2006|True|False')
$referenceData.add('Product:6966a762-0c7c-4261-bd07-fb12b4673347','Product|Windows Essential Business Server 2008 Setup Updates|True|False')
$referenceData.add('Product:ac615cb5-1c12-44be-a262-fab9cd8bf523','Product|Compute Cluster Pack|True|False')
$referenceData.add('Product:5669bd12-c6ab-4831-8643-0d5f6638228f','Product|Max|False|False')
$referenceData.add('Product:4217668b-66f0-42a0-911e-a334a5e4dbad','Product|Network Monitor 3|True|False')
$referenceData.add('ProductFamily:4f93eb69-8b97-4677-8de4-d3fca7ed10e6','ProductFamily|HPC Pack|True|False')
$referenceData.add('Product:7145181b-9556-4b11-b659-0162fa9df11f','Product|SQL Server 2000|True|False')
$referenceData.add('ProductFamily:6964aab4-c5b5-43bd-a17d-ffb4346a8e1d','ProductFamily|Windows|True|False')
$referenceData.add('UpdateClassification:28bc880e-0592-4cbf-8f95-c79b17911d5f','UpdateClassification|Update Rollups|True|False')
$referenceData.add('ProductFamily:ed036c16-1bd6-43ab-b546-87c080dfd819','ProductFamily|BizTalk Server|True|False')
$referenceData.add('Product:a901c1bd-989c-45c6-8da0-8dde8dbb69e0','Product|Windows Vista Ultimate Language Packs|True|False')
$referenceData.add('Product:b790e43b-f4e4-48b4-9f0c-499194f00841','Product|Microsoft Works 8|True|False')
$referenceData.add('UpdateClassification:b54e7d24-7add-428f-8b75-90a396fa584f','UpdateClassification|Feature Packs|True|False')
$referenceData.add('Product:a4bedb1d-a809-4f63-9b49-3fe31967b6d0','Product|Windows XP 64-Bit Edition Version 2003|True|False')
$referenceData.add('Product:5312e4f1-6372-442d-aeb2-15f2132c9bd7','Product|Windows Internet Explorer 8 Dynamic Installer|True|False')
$referenceData.add('Product:dbf57a08-0d5a-46ff-b30c-7715eb9498e9','Product|Windows Server 2003 family|True|False')
$referenceData.add('ProductFamily:41dce4a6-71dd-4a02-bb36-76984107376d','ProductFamily|Windows Essential Business Server|True|False')
$referenceData.add('ProductFamily:35c4463b-35dc-42ac-b0ba-1d9b5c505de2','ProductFamily|Network Monitor|True|False')
$referenceData.add('ProductFamily:1eed49a4-0c4b-467f-be3a-f4edd5813472','ProductFamily|Microsoft Codename Max|False|False')
$referenceData.add('Product:1403f223-a63f-f572-82ba-c92391218055','Product|Office 2003|True|False')
$referenceData.add('Product:e7441a84-4561-465f-9e0e-7fc16fa25ea7','Product|Windows Ultimate Extras|True|False')
$referenceData.add('ProductFamily:504ae250-57c5-484a-8a10-a2c35ea0689b','ProductFamily|Office Communications Server And Office Communicator|True|False')
$referenceData.add('Product:d8584b2b-3ac5-4201-91cb-caf6d240dc0b','Product|Expression Media V1|True|False')
$referenceData.add('Product:3cf32f7c-d8ee-43f8-a0da-8b88a6f8af1a','Product|Exchange Server 2003|True|False')
$referenceData.add('Company:56309036-4c77-4dd9-951a-99ee9c246a94','Company|Microsoft Corporation|True|False')
$referenceData.add('UpdateClassification:051f8713-e600-4bee-b7b7-690d43c78948','UpdateClassification|WSUS Infrastructure Updates|False|False')
$referenceData.add('Product:e9b56b9a-0ca9-4b3e-91d4-bdcf1ac7d94d','Product|Windows Essential Business Server 2008|True|False')
$referenceData.add('Product:eb658c03-7d9f-4bfa-8ef3-c113b7466e73','Product|Data Protection Manager 2006|True|False')
$referenceData.add('Product:ec9aaca2-f868-4f06-b201-fb8eefd84cef','Product|Windows Server 2008 Server Manager Dynamic Installer|True|False')
#endregion


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

if (-NOT($siteCode))
{
    # stopping script, no sitecode means script cannot run
    $cimSession | Remove-CimSession -ErrorAction SilentlyContinue
    exit 1
}
Write-Verbose "$($siteCode) detected sitecode"
#endregion


#region get wsus update categories
[array]$SMSCategoryInstance = Get-CimInstance -CimSession $cimSession -Namespace "root\sms\site_$siteCode" -Query "select * from SMS_UpdateCategoryInstance"
write-verbose "$($SMSCategoryInstance.count) wsus categories found"
if (-NOT($SMSCategoryInstance))
{
    exit 1
}

$WSUSCategoryHash = @{}
foreach ($WSUScategoryItem in $SMSCategoryInstance) 
{
    $propertyString = "{0}|{1}|{2}|{3}" -f $WSUScategoryItem.CategoryTypeName, $WSUScategoryItem.LocalizedCategoryInstanceName, $WSUScategoryItem.AllowSubscription, $WSUScategoryItem.IsSubscribed
    $WSUSCategoryHash.add(($WSUScategoryItem.CategoryInstance_UniqueID),($propertyString))    
}
#endregion

# Show data
if ($OutputMode -eq "ShowData")
{
    $gridViewTitle = 'WSUS update categories and products  -  Use filter criteria "IsSubscribed equals True" to see all activated categories and products'
    $propertiesArray = ("CategoryInstance_UniqueID","CategoryInstanceID","CategoryTypeName","LocalizedCategoryInstanceName","LocalizedInformation","LocalizedPropertyLocaleID","ParentCategoryInstanceID","SourceSite","AllowSubscription","IsSubscribed")
    $SMSCategoryInstance | Sort-Object -Property CategoryTypeName, LocalizedCategoryInstanceName | Select-Object -Property $propertiesArray | Out-GridView -Title $gridViewTitle
}
#endregion

#region Export data as csv
if ($OutputMode -eq "ExportAsCSV")
{
    $propertiesArray = ("CategoryInstance_UniqueID","CategoryInstanceID","CategoryTypeName","LocalizedCategoryInstanceName","LocalizedInformation","LocalizedPropertyLocaleID","ParentCategoryInstanceID","SourceSite","AllowSubscription","IsSubscribed")
    $exportPathAndNameAll = "{0}\{1}-WSUS-subscription-info-{2}.csv" -f (Split-Path $scriptPathAndName -Parent), ($scriptName -replace ".ps1",""), (Get-Date -Format 'yyyyMMdd-hhmm')
    $SMSCategoryInstance | Select-Object -Property $propertiesArray | Export-Csv -Path $exportPathAndNameAll -NoTypeInformation -Delimiter ';' -Force
}
#endregion

#region Create new script file
# creating new script for current HINV client setting settings 
if ($OutputMode -eq "CreateScript")
{
    # create new script file first
    # name like: Compare-HINVClasses_Default-Client-Setting_20210411-1138.ps1
    $newScriptName = "{0}_{1}.ps1" -f ($scriptName -replace ".ps1","") ,(Get-Date -Format 'yyyyMMdd-hhmm')
    $newFile = New-Item -Path (Split-Path $scriptPathAndName -Parent) -Name $newScriptName -ItemType File -Force

    # reading existing script and replacing classes for comparison
    $i = 0
    $referenceDataReplaced = $false
    foreach ($scriptLine in (Get-Content -Path $scriptPathAndName))
    {
        if ($scriptLine -match '\$referenceData.add\(')
        {
            if (-NOT($referenceDataReplaced))
            {
                $referenceDataReplaced = $true
                # replacing data for comparison
                $WSUSCategoryHash.GetEnumerator() | ForEach-Object {
                    # output will look like this: 
                    # $referenceData.add('UpdateClassification:e0789628-ce08-4437-be74-2495b842f43b','UpdateClassification|Definition Updates|True|False')
                    $outputString = "{0}(`'{1}`',`'{2}`')" -f '$referenceData.add', ($_.Key), ($_.Value)
                    $outputString | Out-File -FilePath ($newFile.FullName) -Append -Encoding utf8
                }              
            }
            $i++
        }
        else
        {
            if ($i -eq 0)
            {
                # starting file
                $scriptLine | Out-File -FilePath ($newFile.FullName) -Force -Encoding utf8
            }
            else
            {
                $scriptLine | Out-File -FilePath ($newFile.FullName) -Append -Encoding utf8
            }            
            $i++
        }
   
    } 
    Write-Output "New script created: `"$($newFile.FullName)`""
}
#endregion


#region Compare data for compliance checks
if ($OutputMode -eq "CompareData")
{
    $compareResultArrayList = New-Object system.collections.arraylist
    
    # test if new categories were added or if any category were activated or deacticated
    $WSUSCategoryHash.GetEnumerator() | ForEach-Object {
        # Test if the category has been added
        $refData = $null
        $refData = $referenceData[$_.Key]
        if (-NOT ($refData))
        {
            $tmpObj = New-Object pscustomobject | Select-Object TypeName, InstanceName, Action
            $currentDataArray = $_.Value -split '\|'
            $tmpObj.TypeName = $currentDataArray[0]
            $tmpObj.InstanceName = $currentDataArray[1]
            $tmpObj.Action = 'NewCategory'
            [void]$compareResultArrayList.Add($tmpObj)
        }
        else 
        {
            # test setting changes            
            $referenceArray = $refData -split '\|'
            $currentDataArray = $_.Value -split '\|'
            if ($referenceArray[3] -ne $currentDataArray[3])
            {
                $tmpObj = New-Object pscustomobject | Select-Object TypeName, InstanceName, Action
                # looks like a setting has been changed
                $tmpObj.TypeName = $referenceArray[0]
                $tmpObj.InstanceName = $referenceArray[1]
                if ($currentDataArray[3] -ieq 'True')
                {
                    $tmpObj.Action = 'Activated'
                    [void]$compareResultArrayList.Add($tmpObj)                      
                }
                else 
                {
                    $tmpObj.Action = 'Deactivated'
                    [void]$compareResultArrayList.Add($tmpObj)                    
                }
            }
        }
    }

    # test if any category were removed
    $referenceData.GetEnumerator() | ForEach-Object {
        
        if (-NOT($WSUSCategoryHash[$_.Key]))
        {
            $tmpObj = New-Object pscustomobject | Select-Object TypeName, InstanceName, Action
            $referenceDataArray = $_.Value -split '\|'
            $tmpObj.TypeName = $referenceDataArray[0]
            $tmpObj.InstanceName = $referenceDataArray[1]
            $tmpObj.Action = 'RemovedCategory'
            [void]$compareResultArrayList.Add($tmpObj)
        }
    }

    if ($compareResultArrayList)
    {
        Write-Verbose "$($compareResultArrayList.count) compare results"
        if ([Security.Principal.WindowsIdentity]::GetCurrent().Name -ieq 'NT AUTHORITY\SYSTEM')
        {
            # formatting output in case the script is running in system context, for readability in COnfigMgr config item. 
            $compareResultArrayList | Sort-Object -Property TypeName, InstanceName | Format-Table -HideTableHeaders @{Label="TMP"; Expression={"{0};{1};{2}" -f $_.TypeName, $_.InstanceName, $_.Action }}
        }
        else
        {
            $compareResultArrayList | Sort-Object -Property TypeName, InstanceName
        }
        
    }
    else
    {
        Write-Output 'Compliant'
    }
}
#endregion


#region cleanup
if ($cimSession){$cimSession | Remove-CimSession -ErrorAction SilentlyContinue}
#endregion