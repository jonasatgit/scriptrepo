[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Local", "Remote")]
    [string]$RunType = 'Local',
    [Parameter(Mandatory=$false)]
    [string]$RemoteSystemName = 'cm00.contoso.local'
)


$scriptName = 'Get-ConfigMgrComponentState.ps1'     
$filePath = '{0}\{1}' -f ($PSScriptRoot), $scriptName


switch ($RunType) {
    'Local' 
    {  
        .$filePath -OutputMode 'JSON'
    }

    'Remote'
    {
      
        $psSession = New-PSSession -ComputerName $RemoteSystemName
        
        $retVal = Invoke-Command -Session $psSession -FilePath $filePath -ArgumentList 'JSON'
        
        $retVal 
        #$retVal | Out-GridView -Title 'Stuff'
        
        $psSession | Remove-PSSession
    }
}
