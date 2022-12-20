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
    Reads WMI security settings from a given namespace and prints them out in readable form by converting SDDL bindary data to string values

.EXAMPLE
    Get-WMISecurityDescriptor.ps1 -WMINameSpaceName 'Root'

.EXAMPLE
   Get-WMISecurityDescriptor.ps1 -WMINameSpaceName 'Root/Cimv2'

.PARAMETER WMINameSpaceName
    Name of WMI namespace

.OUTPUT
    Account           : Administrators
    AccessType        : ACCESS_ALLOWED
    Flags             : {CONTAINER_INHERIT, INHERITED}
    Rights            : {ADS_RIGHT_DS_CREATE_CHILD, ADS_RIGHT_DS_DELETE_CHILD, ADS_RIGHT_ACTRL_DS_LIST, ADS_RIGHT_DS_SELF...}
    ObjectGuid        : 
    InheritObjectGuid : 

    Account           : Network Service
    AccessType        : ACCESS_ALLOWED
    Flags             : {CONTAINER_INHERIT, INHERITED}
    Rights            : {ADS_RIGHT_DS_CREATE_CHILD, ADS_RIGHT_DS_DELETE_CHILD, ADS_RIGHT_DS_READ_PROP}
    ObjectGuid        : 
    InheritObjectGuid : 

    Account           : Local Service
    AccessType        : ACCESS_ALLOWED
    Flags             : {CONTAINER_INHERIT, INHERITED}
    Rights            : {ADS_RIGHT_DS_CREATE_CHILD, ADS_RIGHT_DS_DELETE_CHILD, ADS_RIGHT_DS_READ_PROP}
    ObjectGuid        : 
    InheritObjectGuid : 

    Account           : Authenticated Users
    AccessType        : ACCESS_ALLOWED
    Flags             : {CONTAINER_INHERIT, INHERITED}
    Rights            : {ADS_RIGHT_DS_CREATE_CHILD, ADS_RIGHT_DS_DELETE_CHILD, ADS_RIGHT_DS_READ_PROP}
    ObjectGuid        : 
    InheritObjectGuid : 
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [string]$WMINameSpaceName='root/cimv2'
)


# https://learn.microsoft.com/en-us/windows/win32/secauthz/ace-strings
$aceType = @{
'A'='ACCESS_ALLOWED'
'D'='ACCESS_DENIED'
'OA'='OBJECT_ACCESS_ALLOWED'
'OD'='OBJECT_ACCESS_DENIED'
'AU'='AUDIT'
'AL'='ALARM'
'OU'='OBJECT_AUDIT'
'OL'='OBJECT_ALARM'
'ML'='MANDATORY_LABEL'
'XA'='CALLBACK_ACCESS_ALLOWED'
'XD'='CALLBACK_ACCESS_DENIED'
'RA'='RESOURCE_ATTRIBUTE'
'SP'='SCOPED_POLICY_ID'
'XU'='CALLBACK_AUDIT'
'ZA'='CALLBACK_OBJECT_ACCESS_ALLOWED'
'TL'='PROCESS_TRUST_LABEL'
'FL'='ACCESS_FILTER'
}

  
$aceFlags = @{
'CI'='CONTAINER_INHERIT'
'OI'='OBJECT_INHERIT'
'NP'='NO_PROPAGATE'
'IO'='INHERIT_ONLY'
'ID'='INHERITED'
'SA'='AUDIT_SUCCESS'
'FA'='AUDIT_FAILURE'
'TP'='TRUST_PROTECTED_FILTER'
'CR'='CRITICAL'
}


$aceRights = @{
'GA'='GENERIC_ALL'
'GR'='GENERIC_READ'
'GW'='GENERIC_WRITE'
'GX'='GENERIC_EXECUTE'
'RC'='READ_CONTROL'
'SD'='STANDARD_DELETE'
'WD'='WRITE_DAC'
'WO'='WRITE_OWNER'
'RP'='ADS_RIGHT_DS_READ_PROP'
'WP'='ADS_RIGHT_DS_WRITE_PROP'
'CC'='ADS_RIGHT_DS_CREATE_CHILD'
'DC'='ADS_RIGHT_DS_DELETE_CHILD'
'LC'='ADS_RIGHT_ACTRL_DS_LIST'
'SW'='ADS_RIGHT_DS_SELF'
'LO'='ADS_RIGHT_DS_LIST_OBJECT'
'DT'='ADS_RIGHT_DS_DELETE_TREE'
'CR'='ADS_RIGHT_DS_CONTROL_ACCESS'
'FA'='FILE_ALL_ACCESS'
'FR'='FILE_GENERIC_READ'
'FW'='FILE_GENERIC_WRITE'
'FX'='FILE_GENERIC_EXECUTE'
'KA'='KEY_ALL_ACCESS'
'KR'='KEY_READ'
'KW'='KEY_WRITE'
'KX'='KEY_EXECUTE'
'NR'='SYSTEM_MANDATORY_LABEL_NO_READ_UP'
'NW'='SYSTEM_MANDATORY_LABEL_NO_WRITE_UP'
'NX'='SYSTEM_MANDATORY_LABEL_NO_EXECUTE_UP'

}

$aceAccountType = @{
    'AU'='Authenticated Users'
    'LS'='Local Service'
    'NS'='Network Service'
    'BA'='Administrators'
}



$securityDescriptor = Invoke-CimMethod -Namespace $WMINameSpaceName -ClassName __SystemSecurity -MethodName GetSD

$currentWMISDDL = Invoke-CimMethod -Namespace root/cimv2 -ClassName Win32_SecurityDescriptorHelper -MethodName BinarySDToSDDL -Arguments @{BinarySD = $securityDescriptor.SD}

$SDDLList = $currentWMISDDL.SDDL -split '\)\(' -replace '\)'


<#
    SDDL structure:
    ace_type;ace_flags;rights;object_guid;inherit_object_guid;account_sid;(resource_attribute)
#>

$outArrayList = New-Object System.Collections.ArrayList
foreach ($SDDLItem in ($currentWMISDDL.SDDL -split '\)\(' -replace '\)'))
{
    $tmpObj = New-Object PSCustomObject | Select-Object Account, AccessType, Flags, Rights, ObjectGuid, InheritObjectGuid
    Write-Output " "
    $SDDLItemParts = $SDDLItem -split ';'
    if ($SDDLItemParts[0] -match '\(')
    {
        # Clean string from header like "O:BAG:BAD:(" from "O:BAG:BAD:(A;CIID;CCDCLCSWRPWPRCWD;;;BA"
        $tmpArray = $null
        $tmpArray = $SDDLItemParts[0] -split '\('
        $SDDLItemParts[0] = $tmpArray[1]
    }
    

    # account_sid
    if (-NOT ($aceAccountType[$SDDLItemParts[5]]))
    {
        $tmpObj.Account = $SDDLItemParts[5]
    }
    else
    {
        $tmpObj.Account = $aceAccountType[$SDDLItemParts[5]]
    }
    
    # ace_typ
    $tmpObj.AccessType = $aceType[$SDDLItemParts[0]]

    # split every second character to get list of ace_flags
    $aceFlagsList = @()
    $aceFlagsArray = [regex]::Matches($SDDLItemParts[1],'([A-Za-z]{2})')
    foreach ($AceFlag in $aceFlagsArray.value)
    {
        $aceFlagsList += $aceFlags[$AceFlag]
    }
    $tmpObj.Flags = $aceFlagsList

    # split every second character to get list of rights
    $aceRightsList = @()
    $aceRightsArray = [regex]::Matches($SDDLItemParts[2],'([A-Za-z]{2})')
    foreach ($AceRight in $aceRightsArray.value)
    {
        $aceRightsList += $aceRights[$AceRight]
    }
    $tmpObj.Rights = $aceRightsList

    # object_guid
    $tmpObj.ObjectGuid = $SDDLItemParts[3]

    # inherit_object_guid
    $tmpObj.InheritObjectGuid = $SDDLItemParts[4]
    
    [void]$outArrayList. Add($tmpObj)
}

$outArrayList