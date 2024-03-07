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
    Example ConfigMgr Admin functions to be able to work with device extension data
 
.DESCRIPTION
    Example ConfigMgr Admin functions to be able to work with device extension data
    
#>


#region Get-ConfigMgrDeviceExtensionData
function Get-ConfigMgrDeviceExtensionData
{
    param
    (
        [Parameter(Mandatory=$true)]
        $DeviceResourceID,
        [Parameter(Mandatory=$true)]
        $AdminServiceServer,
        [Parameter(Mandatory=$false)]
        [ValidateSet("JSON", "Object")]
        $OutType = "Object"
    )

    $propsObject = $null

    $uri = 'https://{0}/AdminService/v1.0/Device({1})' -f $AdminServiceServer, $deviceResourceID
    try
    {
        $device = Invoke-RestMethod -Method Get -Uri $uri -UseDefaultCredentials -ErrorAction SilentlyContinue
    }
    catch
    {
        Write-Host "No device found for resourceID: $($deviceResourceID)"
        Write-Host "$($Error[0].Exception)"
        return $null
    }


    $uri = 'https://{0}/AdminService/v1.0/Device({1})/AdminService.GetExtensionData' -f $AdminServiceServer, $deviceResourceID
    try
    {
        $deviceExtensionData = Invoke-RestMethod -Method Get -Uri $uri -UseDefaultCredentials -ErrorAction SilentlyContinue
    }
    catch
    {
        Write-Host "No extension data found for device: $($device.Name)"
        Write-Host "$($Error[0].Exception)"
        return $null
    }


    if ($deviceExtensionData)
    {
        # if we have custom extension data, we will have mote than three properties of type NoteProperty
        if (($deviceExtensionData | Get-Member -MemberType NoteProperty).count -gt 3)
        {
            # We need to get rid of the default properties to be able to work with the "real" extension data
            $filteredExtensionData = $deviceExtensionData | Select-Object -Property * -ExcludeProperty '@odata.context','ExtendedType','InstanceKey' # -property * not required with powersehll 6
            
            if ($filteredExtensionData)
            {

                $propertiesHash = @{}
                $filteredExtensionData.PSObject.Properties | ForEach-Object { $propertiesHash[$_.Name] = $_.Value }
                # we have some custom properties
                # Lets create an object we can use to change the properties
                $propsObject = [hashtable]@{
                     ExtensionData =  $propertiesHash
                     #ExtensionData = $filteredExtensionData
                }
            }        
        }
        else
        {
            Write-Host "No extension data found for device: $($device.Name)"
            return $null
        }
   
    }
    else
    {
        Write-Host "No extension data found for device: $($device.Name)"
        return $null
    }

    if ($propsObject)
    {
        switch ($OutType)
        {
            'Object' {return $propsObject}
            'JSON' {return ($propsObject | ConvertTo-Json -Depth 4)}
        }
    
    }
    else
    {
        return $null
    }
}
#endregion

#region Set-ConfigMgrDeviceExtensionData
Function Set-ConfigMgrDeviceExtensionData
{
    param
    (
        [Parameter(Mandatory=$true)]
        $DeviceResourceID,
        [Parameter(Mandatory=$true)]
        $AdminServiceServer,
        [Parameter(Mandatory=$true)]
        $ExtensionData
    )

$exampleData = @'   
$exampleData = [hashtable]@{
    ExtensionData = [hashtable]@{
        Property1 = "Value1"
        Property2 = "Value2"
    }
}
'@

    $uri = 'https://{0}/AdminService/v1.0/Device({1})' -f $AdminServiceServer, $deviceResourceID
    try
    {
        $device = Invoke-RestMethod -Method Get -Uri $uri -UseDefaultCredentials -ErrorAction SilentlyContinue
    }
    catch
    {
        Write-Host "No device found for resourceID: $($deviceResourceID)"
        Write-Host "$($Error[0].Exception)"
        return $null
    }



    # making sure we have the right object type
    if ($ExtensionData.ExtensionData -and ($ExtensionData.ExtensionData -is [hashtable]))
    {
        $uri = 'https://{0}/AdminService/v1.0/Device({1})/AdminService.SetExtensionData' -f $AdminServiceServer, $deviceResourceID
        
        try
        {
            $body = $ExtensionData | ConvertTo-Json -Depth 4
            Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/json' -UseDefaultCredentials -ErrorAction SilentlyContinue
            $body
        }
        catch
        {
            Write-Host "Not able to set extension data for device: $($device.Name)"
            Write-Host "$($Error[0].Exception)"
            break
        } 
    }
    else
    {
        Write-Host "Data in wrong format"
        Write-Host "Data needs to look like this:"
        Write-Host "  "
        Write-Host $exampleData
    }
            
}
#endregion

#region Remove-ConfigMgrDeviceExtensionData
Function Remove-ConfigMgrDeviceExtensionData
{
    param
    (
        [Parameter(Mandatory=$true)]
        $DeviceResourceID,
        [Parameter(Mandatory=$true)]
        $AdminServiceServer
    )

    $uri = 'https://{0}/AdminService/v1.0/Device({1})/AdminService.DeleteExtensionData' -f $AdminServiceServer, $deviceResourceID
        
    try
    {
        Invoke-RestMethod -Method Post -Uri $uri -UseDefaultCredentials -ErrorAction SilentlyContinue
    }
    catch
    {
        Write-Host "Not able to delete extension data for resourceID: $($deviceResourceID)"
        Write-Host "$($Error[0].Exception)"
        return $null
    }      

}
#endregion

break

$ResourceID = 16777219
$AdminServiceServer = 'cm02.contoso.local'


#region GET DATA
# Read device extensiondata
$data = Get-ConfigMgrDeviceExtensionData -DeviceResourceID $ResourceID -OutType Object -AdminServiceServer $AdminServiceServer
#endregion



#region CHANGE VALUE OF PROPERTY
# "Property1" must exist
$data.ExtensionData.Property1 = 'TestValue'

# Set changed data
Set-ConfigMgrDeviceExtensionData -DeviceResourceID $ResourceID -ExtensionData $data -AdminServiceServer $AdminServiceServer
#endregion



#region NEW DATA (Will also add properties to existing entries)
# Create some example data
$exampleData = [hashtable]@{
    ExtensionData = [hashtable]@{
        Property3 = "Value1"
        Property4 = "Value2"
    }
}

# Set new example data. Data will be added. All existing data preserved
Set-ConfigMgrDeviceExtensionData -DeviceResourceID $ResourceID -ExtensionData $exampleData -AdminServiceServer $AdminServiceServer
#endregion



#region REMOVE PROPERTY
# To be able to remove a property we need to get all the properties
$data = Get-ConfigMgrDeviceExtensionData -DeviceResourceID $ResourceID -OutType Object -AdminServiceServer $AdminServiceServer

# Then remove the property from the data
$data.ExtensionData.Remove('Property1')

# Then remove all the properties, because there no such thing as replace
Remove-ConfigMgrDeviceExtensionData -DeviceResourceID $ResourceID -AdminServiceServer $AdminServiceServer

# And then write the manipulated data back
Set-ConfigMgrDeviceExtensionData -DeviceResourceID $ResourceID -ExtensionData $data -AdminServiceServer $AdminServiceServer
#endregion



#region DELETE ALL EXTENSION DATA
Remove-ConfigMgrDeviceExtensionData -DeviceResourceID $ResourceID -AdminServiceServer $AdminServiceServer
#endregion


