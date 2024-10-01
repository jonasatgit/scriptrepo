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



$TestOnly = $true
$netFrameworkVersions = @('v2.0.50727', 'v4.0.30319')
$architecturePath = @('HKLM:\SOFTWARE\Microsoft\.NETFramework', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework')

foreach ($netFrameworkVersion in $netFrameworkVersions)
{
    foreach ($path in $architecturePath)
    {
        $regPath = '{0}\{1}' -f $path, $netFrameworkVersion
        if ($TestOnly)
        {
            Get-ItemPropertyValue -Path $regPath -Name 'SystemDefaultTlsVersions' -ErrorAction SilentlyContinue
            Get-ItemPropertyValue -Path $regPath -Name 'SchUseStrongCrypto' -ErrorAction SilentlyContinue
        }
        else 
        {
            if (-not (Test-Path $regPath))
            {
                New-Item -Path $regPath -Force | Out-Null
            }
            New-ItemProperty -Path $regPath -Name 'SystemDefaultTlsVersions' -Value '1' -PropertyType 'DWord' -Force | Out-Null
            New-ItemProperty -Path $regPath -Name 'SchUseStrongCrypto' -Value '1' -PropertyType 'DWord' -Force | Out-Null          
        }
        
        
    }

    

}  
<#
If (-Not (Test-Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'))
{
    New-Item 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319' -Force | Out-Null
}
New-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319' -Name 'SystemDefaultTlsVersions' -Value '1' -PropertyType 'DWord' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -PropertyType 'DWord' -Force | Out-Null

If (-Not (Test-Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'))
{
    New-Item 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' -Force | Out-Null
}
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' -Name 'SystemDefaultTlsVersions' -Value '1' -PropertyType 'DWord' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -PropertyType 'DWord' -Force | Out-Null

If (-Not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'))
{
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server' -Force | Out-Null
}
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server' -Name 'Enabled' -Value '1' -PropertyType 'DWord' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server' -Name 'DisabledByDefault' -Value '0' -PropertyType 'DWord' -Force | Out-Null

If (-Not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'))
{
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -Force | Out-Null
}
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -Name 'Enabled' -Value '1' -PropertyType 'DWord' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -Name 'DisabledByDefault' -Value '0' -PropertyType 'DWord' -Force | Out-Null

Write-Host 'TLS 1.2 has been enabled. You must restart the Windows Server for the changes to take affect.' -ForegroundColor Cyan

#>

function Test-SCHANNELSettings
{
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    Write-Verbose "$commandName`: https://docs.microsoft.com/en-us/troubleshoot/windows-server/windows-security/restrict-cryptographic-algorithms-protocols-schannel"

    $desiredProtocolStates = [ordered]@{
        "SSL 2.0" = "Disabled"; # Disabled, will automatically validate DisabledByDefault with the opposite value, to ensure the same settings
        "SSL 3.0" = "Disabled"; # Disabled, will automatically validate DisabledByDefault with the opposite value, to ensure the same settings
        "TLS 1.0" = "Disabled"; # Disabled, will automatically validate DisabledByDefault with the opposite value, to ensure the same settings
        "TLS 1.1" = "Disabled"; # Disabled, will automatically validate DisabledByDefault with the opposite value, to ensure the same settings
        "TLS 1.2" = "Enabled"  # Enabled, will automatically validate DisabledByDefault with the opposite value, to ensure the same settings
    }

    [array]$subKeyCollection = ("Client","Server")
    [bool]$expectedValuesSet = $true

    $desiredProtocolStates.GetEnumerator() | ForEach-Object {

        foreach ($subKey in $subKeyCollection)
        {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\{0}\{1}" -f ($_.Name), $subKey
            Write-Verbose "$commandName`: Working on: `"$regPath`""
            $regProperties = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
            if ($regProperties)
            {
                $disabledByDefaultValue = if ($_.Value -eq 'Disabled'){1}else{0} 

                $enabledValue = if ($_.Value -eq 'Enabled'){1}else{0} # enabled is 1

                Write-Verbose "$commandName`: DisabledByDefault = $($regProperties.DisabledByDefault)"
                Write-Verbose "$commandName`: Enabled = $($regProperties.Enabled)"
                # both values schould be set
                if (($regProperties.DisabledByDefault -ne $disabledByDefaultValue) -or ($regProperties.Enabled -ne $enabledValue))
                {
                    $expectedValuesSet = $false
                    Write-Verbose "$commandName`: Wrong settings"
                }
                else
                {
                    Write-Verbose "$commandName`: Settings okay"
                }  

            }
            else
            {
                $expectedValuesSet = $false
                Write-Verbose "$commandName`: No values found"
            }
        }
    }
    return $expectedValuesSet
}