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
    Script to send custom HTML emails about ConfigMgr states.
    
.DESCRIPTION
    This script should have the basic variables set in order to work correctly with other monitoring scripts. 
    Currently referenced in:
        Get-ConfigMgrComponentState.ps1
        Get-ConfigMgrLogState.ps1
        Get-ConfigMgrInboxFileCount.ps1
        Get-ConfigMgrCertificateState.ps1

        Source: https://github.com/jonasatgit/scriptrepo

.PARAMETER MailMessageObject
    List of objects coming from one of the main monitoring scripts. Each object type is slightly different. 

.PARAMETER MailSubject
    Subject of email. Will alwas contain state (Either ok or failed) and name of the system running the script

.PARAMETER MailInfotext
    Header text to the table of objects in the email

.PARAMETER MailServer
    Fqdn of mailserver

.PARAMETER MailFrom
    Emailadress of the sender

.PARAMETER MailToList
    String array of emailadresses to be put in the to line

.PARAMETER MailCCList
    String array of emailadresses to be put in the CC line

.PARAMETER LogPath
    Path to a logfile. Default path is the same as the script.

.PARAMETER HTMLFileOnly
    Switch parameter to just output a HTML file instead of sending an email. Good for testing

.PARAMETER LogActions
    Can be used to write actions to a logfile

.EXAMPLE
    Send-CustomMonitoringMail.ps1

.OUTPUTS
   Email or html file

.LINK
    https://github.com/jonasatgit/scriptrepo
#>
Function Send-CustomMonitoringMail
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [object]$MailMessageObject,
        [Parameter(Mandatory=$true)]
        [string]$MailSubject,
        [Parameter(Mandatory=$true)]
        [string]$MailInfotext,
        [Parameter(Mandatory=$false)]
        [string]$MailServer= "server1.domain.local",
        [Parameter(Mandatory=$false)]
        [string]$MailFrom = 'name@domain.suffix',
        [Parameter(Mandatory=$false)]
        [array]$MailToList = ('name@domain.suffix','name1@domain.suffix'),
        [Parameter(Mandatory=$false)]
        [array]$MailCCList,
        [Parameter(Mandatory=$false)]
        [string]$LogPath,
        [Parameter(Mandatory=$false)]
        [switch]$HTMLFileOnly,
        [Parameter(Mandatory=$false)]
        [switch]$LogActions       
    )

    If([string]::IsNullOrEmpty($LogPath))
    {
        $LogPath = '{0}\{1}.log' -f $PSScriptRoot, $MyInvocation.MyCommand.Name
    }

$cssForHTMLMail = @'
<style>
{
  font-family: Arial, Helvetica, sans-serif;
  border-collapse: collapse;
  width: 70%;
}

h1 {
  text-align: center;
  font-size: 18px;
}

td, th {
  border: 1px solid #ddd;
  padding: 8px;
}

tr:nth-child(even){background-color: #f2f2f2;}

tr:hover {background-color: #ddd;}

tr {
  font-size: 14px;
}

th {
  padding-top: 12px;
  padding-bottom: 12px;
  text-align: left;
  font-size: 14px;
  background-color: #04AA6D;
  color: white;
}

span {
  font-size: 14px;
  font-weight: bold;
  color: red;
}

.center {
  margin-left: auto;
  margin-right: auto;
}

</style>
'@

    if ($LogActions){ "$(Get-date -Format 'yyyyMMdd mm:ss') Adding custom css entries to output of `"ConvertTo-Html`"..." | Out-File $LogPath -Append}
    [array]$outHTMLArray = ""
    $MailMessageObject | ConvertTo-Html | ForEach-Object {

        $contents = $_

        switch ($contents)
        {
            {$contents -ieq "<head>"} 
            {
                $outHTMLArray += $contents
                $outHTMLArray += $cssForHTMLMail
            }
            {$contents -ilike "*<body>*"} 
            {
                $outHTMLArray += $contents
                $outHTMLArray += '<br>'
                $outHTMLArray += '<h1>{0}</h1>' -f $MailInfotext
                $outHTMLArray += '<br>'
            }
            {$contents -ilike "<title>*"} 
            {
                $outHTMLArray += '<title>{0}</title>' -f $MailSubject
            }
            {$contents -eq "<table>"}
            {
                $outHTMLArray += '<table class="center">'
            }
            {$contents -like "*NOK*"}
            {
                $outHTMLArray += $contents -replace 'NOK', '<span>NOK</span>'
            }
            Default 
            {
                $outHTMLArray += $contents
            }
        }
      
    }
    
    $MailBody = $outHTMLArray | out-string

    try
    {

        if ($HTMLFileOnly)
        {
            $htmlFileName = '{0}\{1}_{2}.html' -f ($LogPath | Split-Path -Parent), (Get-date -Format 'yyyyMMdd_mmss') ,($MyInvocation.MyCommand)
            if ($LogActions){ "$(Get-date -Format 'yyyyMMdd mm:ss') Output as HTML: `"$($htmlFileName)`"" | Out-File $LogPath -Append}
            $MailBody | Out-File $htmlFileName -Force
        }
        else 
        {
            if ($LogActions){ "$(Get-date -Format 'yyyyMMdd mm:ss') Trying to send email..." | Out-File $LogPath -Append}
            $paramsplatting = @{
                SmtpServer = $MailServer
                Subject = $MailSubject
                From = $MailFrom
                Body = $MailBody
                To = $MailToList
            }  
            
            if ($MailCCList)
            {
                $paramsplatting.add("Cc", $MailCCList)
            }

            Send-MailMessage @paramsplatting -BodyAsHtml -ErrorAction Stop
        }
    }
    catch
    {
        if ($LogActions){ "$(Get-date -Format 'yyyyMMdd mm:ss') Failed!" | Out-File $LogPath -Append}
        if ($LogActions){ $Error[0].Exception | Out-File $LogPath -Append}
    }
    if ($LogActions){ "$(Get-date -Format 'yyyyMMdd mm:ss') Script done!" | Out-File $LogPath -Append}
}
