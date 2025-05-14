<#
.SYNOPSIS
Script to check and or set TLS 1.2 settings

.DESCRIPTION
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

Script to check and or set TLS 1.2 settings
#>

# If set to true, the script will set the registry keys to enable TLS 1.2
# If set to false, the script will only check the registry keys
$Remediate = $false


Function Get-TLSState
{
    [CmdletBinding()]
    Param
    (
        # Registry Path
        [Parameter(Mandatory=$true,Position=0)]
        [string]$Path,

        # Registry Name
        [Parameter(Mandatory=$true,Position=1)]
        [string]$Name,

        [Parameter(Mandatory=$true,Position=2)]
        $Value
    )
    
    $regItem = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Ignore

    if ($null -eq $regItem)
    {
        return 'NotCompliant'
    }
    else 
    {
        if ($regItem.$Name -eq $Value)
        {
            return 'Compliant'
        }
        else 
        {
            return 'NotCompliant'
        }
    }
}


if ($Remediate -eq $false)
{

    $regSettings = @()
    $regKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v2.0.50727'
    $regSettings += Get-TLSState -Path $regKey -Name 'SystemDefaultTlsVersions' -Value 1
    $regSettings += Get-TLSState -Path $regKey -Name 'SchUseStrongCrypto' -Value 1

    $regKey = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727'
    $regSettings += Get-TLSState -Path $regKey -Name 'SystemDefaultTlsVersions' -Value 1
    $regSettings += Get-TLSState -Path $regKey -Name 'SchUseStrongCrypto' -Value 1

    $regKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'
    $regSettings += Get-TLSState -Path $regKey -Name 'SystemDefaultTlsVersions' -Value 1
    $regSettings += Get-TLSState -Path $regKey -Name 'SchUseStrongCrypto' -Value 1

    $regKey = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
    $regSettings += Get-TLSState -Path $regKey -Name 'SystemDefaultTlsVersions' -Value 1
    $regSettings += Get-TLSState -Path $regKey -Name 'SchUseStrongCrypto' -Value 1

    $regKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'
    $regSettings += Get-TLSState -Path $regKey -Name 'Enabled' -Value 1
    $regSettings += Get-TLSState -Path $regKey -Name 'DisabledByDefault' -Value 0

    $regKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'
    $regSettings += Get-TLSState -Path $regKey -Name 'Enabled' -Value 1
    $regSettings += Get-TLSState -Path $regKey -Name 'DisabledByDefault' -Value 0

    # If there is any setting 'NotCompliant' all are validated as 'NotCompliant'
    If($regSettings | Where-Object {$_ -eq 'NotCompliant'})
    {
        Write-Host 'NotCompliant'
    }
    else 
    {
        Write-Host 'Compliant'
    }
}
else 
{
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
     
     
    If (-Not (Test-Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v2.0.50727'))
    {
        New-Item 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v2.0.50727' -Force | Out-Null
    }
    New-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v2.0.50727' -Name 'SystemDefaultTlsVersions' -Value '1' -PropertyType 'DWord' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v2.0.50727' -Name 'SchUseStrongCrypto' -Value '1' -PropertyType 'DWord' -Force | Out-Null
     
    If (-Not (Test-Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727'))
    {
        New-Item 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727' -Force | Out-Null
    }
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727' -Name 'SystemDefaultTlsVersions' -Value '1' -PropertyType 'DWord' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727' -Name 'SchUseStrongCrypto' -Value '1' -PropertyType 'DWord' -Force | Out-Null
    
     
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
     
}
# End of script