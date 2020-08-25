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
# source https://github.com/jonasatgit/scriptrepo/blob/master/General/Show-FolderSize.ps1
# Tiny script to format the results of SysinternalsSuite du.exe to find folders with the most data in it 

param
(
    $pathToCheck = "C:\",
    $pathLevel = 3, # how deep should the search go?
    $commandPath = "D:\CUSTOM\Tools\SysinternalsSuite\du.exe",
    $tempPath = "$($env:temp)\duoutput$(Get-Random).csv",
    $commandParameter = "/c /l $pathLevel -noBanner $pathToCheck", # c = output as csv, l = sub directory level
    $minFolderSize = 10
)


function Show-FolderSize
{
    param
    (
        $pathToCheck,
        $pathLevel = 3,
        $commandPath,
        $tempPath,
        $commandParameter = "/c /l $pathLevel -noBanner $pathToCheck", # c = output as csv, l = sub directory level
        $minFolderSize = 10
    )

    Write-host "Will check $pathToCheck" -ForegroundColor Green

    $minFolderSizeTmp = $minFolderSize * 1MB

    Write-Host "Starting: `"$commandPath`" `"$commandParameter`"" -ForegroundColor Green
    $measure = Measure-Command {$process = Start-Process -FilePath $commandPath -ArgumentList $commandParameter -Wait -RedirectStandardOutput $tempPath -WindowStyle Hidden }
    
    $csv = Import-Csv $tempPath -Delimiter ','

    Write-host "The command took: $($measure.totalseconds) seconds to read $($csv.count) folder." -ForegroundColor Green

    Remove-Item $tempPath -Force

    $selectOutput = $csv | Where-Object {[int64]$_.DirectorySizeOnDisk -ge $minFolderSizeTmp} `
     | Sort-Object {[int64]$_.DirectorySizeOnDisk} -Descending `
     | Select-Object Path, CurrentFileCount, CurrentFileSize, FileCount, DirectoryCount, DirectorySize, DirectorySizeOnDisk, @{Expression={"{0:0}" -f ([int64]$_.DirectorySizeOnDisk / 1MB)};Label="DirectorySizeOnDiskInMB"} `
     | Out-GridView -Title 'Folder Size' -OutputMode Multiple

    if($selectOutput)
    {
        foreach($item in $selectOutput)
        {
            Show-FolderSize -pathToCheck ($item.path) -pathLevel $pathLevel -commandPath $commandPath -tempPath $tempPath -minFolderSize $minFolderSize
        }
    }
}


Show-FolderSize -pathToCheck $pathToCheck -pathLevel $pathLevel -commandPath $commandPath -tempPath $tempPath -commandParameter $commandParameter -minFolderSize $minFolderSize

