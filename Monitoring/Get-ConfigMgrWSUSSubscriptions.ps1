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
    It will do that by using a JSON file with a name like this: [yyyyMMdd-hhmm]_[NameOfThisScript].ps1.json
    to compare the state of a given ConfigMgr WSUS installation. 
    The script will use the last JSON file (based on datetime string prefix) and will compare the result with the WMI class
    "SMS_UpdateCategoryInstance". The script will then create a new JSON file for the next runtime to compare against that file 
    The parameter "OutputMode" with value "HTMLMail" can helpt to create some king of notifications about WSUS changes. Like new products
    or subscription changes. Subscription means, a product or catagory has been selected to be synched againt Microsoft Update. 

    The output contains the following information:
    TypeName        = Type of item. Like: UpdateClassification, Company, ProductFamily or Product 
    InstanceName    = Name of item. Like: Windows 10, Windows 11 or Updates, Security Updates
    Action          = Can be one of the following:
            NewCategory     = A new item was added to WSUS
            RemovedCategory = An item has been removed from WSUS
            Activated       = An item has been activated and will be synct from Microsoft Update
            Deactivated     =  An item has been deactivated and will no longer be synct from Microsoft Update
       
    Source: https://github.com/jonasatgit/scriptrepo

.PARAMETER OutputMode
    The parameter OutputMode has two possible options:
    "GridView":
        Will show changes in a GridView
    "HTMLMail": 
        Will send an email containing a list of changes
    
.PARAMETER ProviderMachineName
    Name/FQDN of the ConfigMgr SMS provider machine. 
    Default value is the local system

.PARAMETER SiteCode
    ConfigMgr sitecode.
    Will be detected automatically, but might be needed in some circumstances.

.PARAMETER ForceWSMANConnection
    Can be used to force Get-CimInstance to use WSMAN instead of DCOM for WMI queries. 

.PARAMETER MailSubject
    Subject of an email

.PARAMETER MailInfotext
    Infotext as a header for the table of changes in an email

.PARAMETER SendMailOnlyWhenChangesFound
    Switch parameter to only send an email if the scripts detected changes. This might help to prevent avoidable emails.

.EXAMPLE
    Get-ConfigMgrWSUSSubscriptions.ps1

.EXAMPLE
    Get-ConfigMgrWSUSSubscriptions.ps1 -ForceWSMANConnection

.EXAMPLE
    Get-ConfigMgrWSUSSubscriptions.ps1 -OutputMode 'HTMLMail'

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
    [ValidateSet("GridView", "HTMLMail")]
    [string]$OutputMode = 'GridView',
    [Parameter(Mandatory=$false)]
    [String]$MailSubject = 'Status about WSUS subscription changes',
    [Parameter(Mandatory=$false)]
    [String]$MailInfotext = 'Status about WSUS subscription changes',
    [Parameter(Mandatory=$false)]
    [switch]$SendMailOnlyWhenChangesFound
)
#endregion

#region Initializing
$scriptPath = $PSScriptRoot
$scriptName = $MyInvocation.MyCommand.Name
$jsonFileName = '{0}\{1}_{2}.json' -f $scriptPath,(Get-Date -Format 'yyyyMMdd-hhmm'), $scriptName
#endregion

$VerbosePreference = 'SilentlyContinue'

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
write-verbose "$($SMSCategoryInstance.count) WSUS categories found"
if (-NOT($SMSCategoryInstance))
{
    if ($cimSession){$cimSession | Remove-CimSession -ErrorAction SilentlyContinue}
    exit 1
}
#endregion


#region Export JSON if script has never run or JSON was deleted
[array]$listOfJsonFiles = Get-ChildItem -Filter "*$($scriptName).json" -Path $scriptPath
if (-NOT ($listOfJsonFiles))
{
    $SMSCategoryInstance | Select-Object CategoryInstance_UniqueID, CategoryTypeName, LocalizedCategoryInstanceName, AllowSubscription, IsSubscribed | ConvertTo-Json | Out-File $jsonFileName -Encoding utf8 -Force
}
#endregion

#region Cleanup old files
$maxFiles = 10
if ($listOfJsonFiles.count -ge $maxFiles)
{
    write-verbose "Found more than $($maxFiles) json files. Will delete some."  
    $listOfJsonFiles | Sort-Object -Property Name -Descending | Select-Object -Skip $maxFiles| Remove-Item -Force  
}
#endregion

#region get latest json definition and output new file
$latestJsonDefinitionFile = Get-ChildItem -Filter "*$($scriptName).json" -Path $scriptPath | Sort-Object -Property Name -Descending | Select-Object -First 1
$latestJsonDefinitionObject = Get-content -Path $latestJsonDefinitionFile.FullName | ConvertFrom-Json

#region Test if new items have arrived or if settings have changed
$compareResultArrayList = New-Object system.collections.arraylist
foreach ($CategoryInstance in $SMSCategoryInstance) 
{
    $referenceObject = $latestJsonDefinitionObject.Where({$_.CategoryInstance_UniqueID -eq $CategoryInstance.CategoryInstance_UniqueID})
    if(-NOT($referenceObject))
    {
        $tmpObj = New-Object pscustomobject | Select-Object TypeName, InstanceName, Action
        $tmpObj.TypeName = $CategoryInstance.CategoryTypeName
        $tmpObj.InstanceName = $CategoryInstance.LocalizedCategoryInstanceName
        $tmpObj.Action = 'NewCategory'
        [void]$compareResultArrayList.Add($tmpObj)
    }
    else 
    {
        if ($referenceObject.IsSubscribed -ine $CategoryInstance.IsSubscribed)
        {
            $tmpObj = New-Object pscustomobject | Select-Object TypeName, InstanceName, Action
            # looks like a setting has been changed
            $tmpObj.TypeName = $CategoryInstance.CategoryTypeName
            $tmpObj.InstanceName = $CategoryInstance.LocalizedCategoryInstanceName
            if ($CategoryInstance.IsSubscribed -ieq 'True')
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
#endregion

#region Test for removed items 
foreach ($CategoryInstance in $latestJsonDefinitionObject) 
{
    $referenceObject = $SMSCategoryInstance.Where({$_.CategoryInstance_UniqueID -eq $CategoryInstance.CategoryInstance_UniqueID})
    if(-NOT($referenceObject))
    {
        $tmpObj = New-Object pscustomobject | Select-Object TypeName, InstanceName, Action
        $tmpObj.TypeName = $CategoryInstance.CategoryTypeName
        $tmpObj.InstanceName = $CategoryInstance.LocalizedCategoryInstanceName
        $tmpObj.Action = 'RemovedCategory'
        [void]$compareResultArrayList.Add($tmpObj)
    }
}
#endregion

if ($compareResultArrayList.count -eq 0)
{
    $tmpObj = New-Object pscustomobject | Select-Object TypeName, InstanceName, Action
    $tmpObj.TypeName = 'Unknown'
    $tmpObj.InstanceName = 'Unknown'
    $tmpObj.Action = 'No changes'
    [void]$compareResultArrayList.Add($tmpObj)    
}
#endregion

#region cleanup
if ($cimSession){$cimSession | Remove-CimSession -ErrorAction SilentlyContinue}
#endregion

# Output a new file for future tests
$SMSCategoryInstance | Select-Object CategoryInstance_UniqueID, CategoryTypeName, LocalizedCategoryInstanceName, AllowSubscription, IsSubscribed | ConvertTo-Json | Out-File $jsonFileName -Encoding utf8 -Force
#endregion

#region Compare data for compliance checks
Switch ($OutputMode)
{
    'GridView'
    {
        $compareResultArrayList | Out-GridView -Title 'List of WSUS subscription changes'
    }
    'HTMLMail'
    {
        if ($SendMailOnlyWhenChangesFound -and ($compareResultArrayList[0].Action -eq 'No changes'))
        {
            Write-Host 'No changes found. No email send.' -ForegroundColor Yellow
            Exit
        }
        # Reference email script
        .$PSScriptRoot\Send-CustomMonitoringMail.ps1

        $MailInfotext = '<br>{0}' -f $MailInfotext
        Send-CustomMonitoringMail -MailMessageObject $compareResultArrayList -MailSubject $MailSubject -MailInfotext $MailInfotext        
    }
}
#endregion