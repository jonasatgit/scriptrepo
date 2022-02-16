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

#
# Very basic script to export SSRS Reports
# Source: https://github.com/jonasatgit/scriptrepo
#

param 
(
    # Change output path if needed. 
    # Folder needs to exist
    [string]$BackupPath = "E:\CUSTOM\Reports",

    # Change URL: "http://server.contoso.local/reportserver" to actual URL
    [string]$ReportServerUri = "http://dp01.contoso.local/reportserver"
)

$ReportServerUri = "$ReportServerUri/ReportService2010.asmx?wsdl"
#$ReportServerUri

Write-Host "Connecting to: `"$ReportServerUri`""
$Proxy = New-WebServiceProxy -Uri $ReportServerUri -Namespace "SSRS" -UseDefaultCredential ;

#http://msdn.microsoft.com/en-us/library/aa225878(v=SQL.80).aspx

#second parameter means recursive
$items = $Proxy.ListChildren("/", $true) | Select-Object TypeName, Path, ID, Name | Where-Object {$_.TypeName -eq "Report" -or $_.TypeName -eq "DataSet"};

#create a new folder where we will save the files
#PowerShell datetime format codes http://technet.microsoft.com/en-us/library/ee692801.aspx

#create a timestamped folder, format similar to 2011-Mar-28-0850PM
$folderName = "SSRS-Backup_{0}" -f (Get-Date -format u).Replace(":","").Replace(" ","_")
$fullFolderName = "$BackupPath\$folderName";
[System.IO.Directory]::CreateDirectory($fullFolderName) | out-null
Write-Host "Exporting $($items.Count) reports to: `"$fullFolderName`""
$i = 0
foreach($item in $items)
{
    #need to figure out if it has a folder name
    $subfolderName = split-path $item.Path;
    $reportName = split-path $item.Path -Leaf;
    $fullSubfolderName = $fullFolderName + $subfolderName;
    if(-not(Test-Path $fullSubfolderName))
    {
        #note this will create the full folder hierarchy
        [System.IO.Directory]::CreateDirectory($fullSubfolderName) | out-null
    }


    if($item.TypeName -eq 'DataSet')
    {

        $fullReportFileName = $fullSubfolderName + "\" + $item.Name +  ".rsd";
    }
    else
    {
        $fullReportFileName = $fullSubfolderName + "\" + $item.Name +  ".rdl";
    }

    if($fullReportFileName.Length -ge 256)
    {
        Write-Host "Not able to export report since the name is $($fullReportFileName.Length) characters long!" -ForegroundColor Yellow
    }
    else
    {
        $i++
        Write-Verbose "FileNameLength: $(($fullReportFileName.Length).ToString("000")) => `"$fullReportFileName`""
        Write-Progress -Activity "Saving reports to: `"$fullSubfolderName`"" -Status ($item.Name) -PercentComplete ($i/$items.Count*100)
        $bytes = $Proxy.GetItemDefinition($item.Path)
        [System.IO.File]::WriteAllBytes("$fullReportFileName", $bytes)
    }
}