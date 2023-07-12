
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

# Test script to get the log data from the Intune Management Extension log file
# The script will parse the log file and extract the JSON data from the log entries
# The script will then create a custom object for each JSON entry and add it to an array

   $logEntryHash = @{}

   $arrayList = New-Object System.Collections.ArrayList
   
   $imeLogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log"
   
   
        $paramSplat = @{
            Path       = $imeLogPath
            Pattern    = '^{0}' -f [regex]::escape('<![LOG[Get policies = [{"Id":')
            AllMatches = $true
        }

        $stringMatchList = Select-String @paramSplat

        $i = 0
        foreach($stringMatch in $stringMatchList)
        {
            $rawDataString = $stringMatch.Line -ireplace [regex]::Escape("<![LOG[Get policies = [") -replace ([regex]::Escape("]]LOG]!>") + ".*")

            # trying to extract the time the log entry was written
            $logDateTime = $null
            try
            {
                if($stringMatch.Line -match '(?<time>time="\d{2}:\d{2}:\d{2}).*(?<date>date="\d{1,2}-\d{1,2}-\d{4})')
                {
                     $datetimeString = "{0} {1}" -f ($Matches.date -replace '(Date=")', ''), ($Matches.time -replace '(Time=")', '')
                     $logDateTime = [Datetime]::ParseExact($datetimeString, 'd-MM-yyyy HH:mm:ss', $null)
                }
            }Catch{}
            
            # There might be multiple JSON entries in one log entry
            # We need to split and store them individually
            $jsonList = $rawDataString -split '},{"Id":'
            # We now need to add the missing pieces backto the string where we used split
            
            foreach($jsonString in $jsonList)
            {
                # Start of string
                if(-NOT($jsonString -match '^{"Id":'))
                {
                    $jsonString = '{0}"Id":{1}' -f "{", $jsonString
                }

                # End of string
                if(-NOT($jsonString -match '}$'))
                {
                    $jsonString = '{0}{1}' -f $jsonString, '}'
                }
                $i++

                $dataObject =  $jsonString | ConvertFrom-Json # No deph support in Powershell 5.1
               
                # It helps to have some more objects created for different properties of an app
                $dataObject.DetectionRule = $dataObject.DetectionRule | ConvertFrom-Json
                $dataObject.RequirementRules = $dataObject.RequirementRules | ConvertFrom-Json
                $dataObject.InstallEx = $dataObject.InstallEx | ConvertFrom-Json
                $dataObject.ReturnCodes = $dataObject.ReturnCodes | ConvertFrom-Json

                # Lets add the log entry datetime in case we have one
                if($logDateTime)
                {
                    $dataObject | Add-Member -MemberType NoteProperty -Name 'LogDateTime' -Value $logDateTime 
                }
                else
                {
                    $dataObject | Add-Member -MemberType NoteProperty -Name 'LogDateTime' -Value (Get-date '01-01-1900') # dummy time entry
                }

                #[void]$logEntryHash.Add($i, $dataObject)
                [void]$arrayList.Add($dataObject)

            }
        }

        $arrayList | Group-Object -Property id | ForEach-Object {
        
           $id = $_.Name 

           $logEntry = $_.Group | Sort-Object -Descending -Property LogDateTime | Select-Object -First 1

           [void]$logEntryHash.Add($id, $logEntry)
        
        }

        $logEntryHash

