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
#
# Source: https://github.com/jonasatgit/scriptrepo

<#
.Synopsis
    Script to download wsusscn2.cab and copy it to the package source folder of the WSUS Offline Scan package in ConfigMgr

.DESCRIPTION
    The script will download wsusscn2.cab from the Microsoft Update Catalog and copy it to the package source folder of the WSUS Offline Scan package in ConfigMgr.

.EXAMPLE
    .\New-WSUSOfflineScanLogic.ps1
.EXAMPLE
    .\New-WSUSOfflineScanLogic.ps1 -SiteCode 'P01'
.PARAMETER SiteCode
    ConfigMgr SiteCode
.PARAMETER ProviderMachineName
    Name of the ConfigMgr SMS Provider server
.PARAMETER PackageSourcePath
    UNC path to package source folder. Will be used to store the offline scan package
.PARAMETER PackageVersion
    Version of the offline scan package. Will be the current date in the format of yyyyMMdd by default. 
.PARAMETER ScanPackageName
    Name if the offline scan packge in the ConfigMgr console
.PARAMETER TaskSequenceName
    Name of the wsusscn2.cab download task sequence
.PARAMETER ProxyURIandPort
    URI and port of the proxy server. Example: proxy.domain.local:3128
.PARAMETER ProxyConnectionUser
    User for proxy authentication
.PARAMETER ProxyDomainName
    Domain of user for proxy authentication
.PARAMETER ProxyPWString
    Password of user for proxy authentication
.LINK
    https://github.com/jonasatgit/scriptrepo
#>
[CmdletBinding()]
param
(
    # ConfigMgr SiteCode
    [Parameter(Mandatory=$true)]
    [string]$SiteCode,

    # SMS Provider Server FQDN
    [Parameter(Mandatory=$true)]
    [string]$ProviderMachineName,

    # PackageID of WSUS Offline Scan Package
    [Parameter(Mandatory=$true)]
    [string]$PackageID,

    # Download URL for wsusscn2.cab
    [Parameter(Mandatory=$false)]
    [string]$DownloadURL = 'https://go.microsoft.com/fwlink/?LinkID=74689', #'http://download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab',

    # Download temp folder to store wsusscn2.cab
    [Parameter(Mandatory=$false)]
    [string]$DownloadTempFolder = $env:temp,

    # Update DPs the package is distributed to
    [Parameter(Mandatory=$false)]
    [switch]$UpdateDPs,

    # set to use BITS for file download
    #[Parameter(Mandatory=$false)]
    #[switch]$UseBitsToDownload,

    # log path
    [Parameter(Mandatory=$false)]
    [string]$LogPath,

    # log path
    [Parameter(Mandatory=$false)]
    [switch]$UseProxy,

    # log path
    [Parameter(Mandatory=$false)]
    [string]$ProxyURI,

    # log path
    [Parameter(Mandatory=$false)]
    [string]$ProxyUser,

    # log path
    [Parameter(Mandatory=$false)]
    [string]$ProxyDomain,

    # log path
    [Parameter(Mandatory=$false)]
    [string]$ProxyPassword

)

if ($LogPath)
{
     $Global:LogFilePath = '{0}\Download-Wsusscn2CabFile.ps1.log' -f $LogPath
}
else
{
    $Global:LogFilePath = "$($env:windir)\Temp\Download-Wsusscn2CabFile.ps1.log"
}


#region Write-CMTraceLog
<#
.Synopsis
    Write-CMTraceLog will writea logfile readable via cmtrace.exe .DESCRIPTION
    Write-CMTraceLog will writea logfile readable via cmtrace.exe (https://www.bing.com/search?q=cmtrace.exe)
.EXAMPLE
    Write-CMTraceLog -Message "file deleted" => will log to the current directory and will use the scripts name as logfile name #> 
function Write-CMTraceLog {
    [CmdletBinding()]
    Param
    (
        #Path to the log file
        [parameter(Mandatory=$false)]
        [String]$LogFile=$Global:LogFilePath,

        #The information to log
        [parameter(Mandatory=$true)]
        [String]$Message,

        #The source of the error
        [parameter(Mandatory=$false)]
        [String]$Component=(Split-Path $PSCommandPath -Leaf),

        #severity (1 - Information, 2- Warning, 3 - Error) for better reading purposes this variable as string
        [parameter(Mandatory=$false)]
        [ValidateSet("Information","Warning","Error")]
        [String]$Severity="Information",

        # write to console only
        [Parameter(Mandatory=$false)]
        [switch]$ConsoleOutputOnly
    )


    # save severity in single for cmtrace severity
    [single]$cmSeverity=1
    switch ($Severity)
        {
            "Information" {$cmSeverity=1; $color = [System.ConsoleColor]::Green; break}
            "Warning" {$cmSeverity=2; $color = [System.ConsoleColor]::Yellow; break}
            "Error" {$cmSeverity=3; $color = [System.ConsoleColor]::Red; break}
        }


    $console = $Message

    If($ConsoleOutputOnly)
    {

        Write-Host $console -ForegroundColor $color
    }
    else
    {
        Write-Host $console -ForegroundColor $color

        #Obtain UTC offset
        $DateTime = New-Object -ComObject WbemScripting.SWbemDateTime
        $DateTime.SetVarDate($(Get-Date))
        $UtcValue = $DateTime.Value
        $UtcOffset = $UtcValue.Substring(21, $UtcValue.Length - 21)

        #Create the line to be logged
        $LogLine =  "<![LOG[$Message]LOG]!>" +`
                    "<time=`"$(Get-Date -Format HH:mm:ss.mmmm)$($UtcOffset)`" " +`
                    "date=`"$(Get-Date -Format M-d-yyyy)`" " +`
                    "component=`"$Component`" " +`
                    "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
                    "type=`"$cmSeverity`" " +`
                    "thread=`"$PID`" " +`
                    "file=`"`">"

        #Write the line to the passed log file
        $LogLine | Out-File -Append -Encoding UTF8 -FilePath $LogFile
    }

}
#endregion



Write-CMTraceLog -Message "Script started: $(Split-Path $PSCommandPath -Leaf)"

$CMPackage = Get-WmiObject -ComputerName $ProviderMachineName -Namespace "root\sms\site_$SiteCode" -Query "SELECT * FROM SMS_Package WHERE PackageID = '$($PackageID)'" -ErrorAction SilentlyContinue
if($CMPackage)
{
    Write-CMTraceLog -Message "Package with PackageID $PackageID found. Name: $($CMPackage.Name)"
    $CMPackageSourcePath = $CMPackage.PkgSourcePath
    $OutFilePath = "$DownloadTempFolder\wsusscn2.cab"

    try
    {
        <#
        if($UseBitsToDownload)
        {
            # BITS only works if the user has administrative rights
            Write-CMTraceLog -Message "Start to download wsusscn2.cab..."
            Write-CMTraceLog -Message "Start-BitsTransfer -DisplayName 'wsusscn2.cab' -Source $DownloadURL -Destination $OutFilePath -ProxyUsage SystemDefault"
            Start-BitsTransfer -DisplayName 'wsusscn2.cab' -Source $DownloadURL -Destination $OutFilePath -ProxyUsage SystemDefault
        }
        #>

        if ($UseProxy)
        {
            Write-CMTraceLog -Message "Start to download wsusscn2.cab using proxy: `"$ProxyURI`""
            $webClient = New-Object System.Net.WebClient
            $Credentials = New-Object Net.NetworkCredential($ProxyUser,$ProxyPassword,$ProxyDomain)
            $WebProxy = New-Object System.Net.WebProxy($ProxyURI,$true,$null,$Credentials)
            $webClient.Proxy = $WebProxy
            Write-CMTraceLog -Message "(New-Object System.Net.WebClient).DownloadFile($DownloadURL, $OutFilePath)"
            $webClient.DownloadFile($DownloadURL, $OutFilePath)
        }
        else
        {
            Write-CMTraceLog -Message "Start to download wsusscn2.cab..."
            Write-CMTraceLog -Message "(New-Object System.Net.WebClient).DownloadFile($DownloadURL, $OutFilePath)"
            (New-Object System.Net.WebClient).DownloadFile($DownloadURL, $OutFilePath)
        }

        Write-CMTraceLog -Message "Copy: $OutFilePath to $CMPackageSourcePath..."
        Copy-Item -Path $OutFilePath -Destination "Microsoft.PowerShell.Core\FileSystem::$CMPackageSourcePath" -Force

        Write-CMTraceLog -Message "Delete temp file: $OutFilePath"
        Remove-Item -Path $OutFilePath -Force

        if($UpdateDPs)
        {
            Write-CMTraceLog -Message "Update Distribution Points for package..."
            [void]$CMPackage.RefreshPkgSource()
        }
        else
        {
            Write-CMTraceLog -Message "Distribution Points for package NOT updated. Manual update needed!" -Severity Warning
        }

        Write-CMTraceLog -Message "Create wsusscn2-versioninfo.txt..."
        Set-Location "C:\"
        Get-Date -Format "yyyyMMdd" | Out-File "$CMPackageSourcePath\wsusscn2-versioninfo.txt" -Force
        "This file was created by $($MyInvocation.MyCommand.Name) and will be used for WSUS-OfflineScan.ps1" | Out-File "$CMPackageSourcePath\wsusscn2-versioninfo.txt" -Append
        "DO NOT CHANGE THIS FILE" | Out-File "$CMPackageSourcePath\wsusscn2-versioninfo.txt" -Append
    }
    Catch
    {
        Write-CMTraceLog -Message "error while getting current wsusscn2.cab file" -Severity Error
        Write-CMTraceLog -Message "$($Error[0].Exception)" -Severity Error
        exit -1
    }

}
else
{
    Write-CMTraceLog -Message "Package with PackageID: $PackageID not found!" -Severity Warning
    Write-CMTraceLog -Message "Package might be missing or user rights might be missing" -Severity Information
    exit -1
}
Write-CMTraceLog -Message "Script end"