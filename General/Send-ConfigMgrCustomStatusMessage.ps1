

<#
.Synopsis
    Script to send custom ConfigMgr client status messages using PowerShell.
 
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

    Will send a custom status message to the ConfigMgr site server from the local client.
    All messages will appear in the ConfigMgr console under Monitoring
    The info category has message ID 39997, warning 39998, and error 39999.

.PARAMETER MessageType
    Type of status message: Info, Warning, or Error. Default is Info.

.PARAMETER InsertionString1
    The first insertion string for the status message. (Mandatory)
    Can be any message text you want to include.
    Maximum length is 255 characters.

.PARAMETER InsertionString2
    The second insertion string for the status message. (Optional)

.PARAMETER InsertionString3
    The third insertion string for the status message. (Optional)

.PARAMETER InsertionString4
    The fourth insertion string for the status message. (Optional)

.PARAMETER InsertionString5
    The fifth insertion string for the status message. (Optional)
    
#>

Function Send-ConfigMgrCustomStatusMessage
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error")]
        [string]$MessageType = 'Info',

        [Parameter(Mandatory = $true)]
        [ValidateLength(0,255)]        
        [string]$InsertionString1,

        [Parameter(Mandatory = $false)]
        [ValidateLength(0,255)]
        [string]$InsertionString2,

        [Parameter(Mandatory = $false)]
        [ValidateLength(0,255)]
        [string]$InsertionString3,

        [Parameter(Mandatory = $false)]
        [ValidateLength(0,255)]
        [string]$InsertionString4,

        [Parameter(Mandatory = $false)]
        [ValidateLength(0,255)]
        [string]$InsertionString5
        # up to 10 insertion strings are supported, but usually 5 should be more than enough
    )

    try
    {
        switch ($MessageType) 
        {
            'Info'    { $eventType = 'SMS_GenericStatusMessage_Info' }
            'Warning' { $eventType = 'SMS_GenericStatusMessage_Warning' }
            'Error'   { $eventType = 'SMS_GenericStatusMessage_Error' }

        }

        # Sends a simple informational (Generic) status message from the local client
        $ev = New-Object -ComObject Microsoft.SMS.Event
        $ev.EventType = $eventType     # Info | Warning | Error
        $ev.SetProperty('Attribute403', 'GenericMsg_SeeInsertionStrings')  # required "category" marker

        if (-NOT [string]::IsNullOrEmpty($InsertionString1)) 
        {
            $ev.SetProperty('InsertionString1', $InsertionString1)
        }

        if (-NOT [string]::IsNullOrEmpty($InsertionString2)) 
        {
            $ev.SetProperty('InsertionString2', $InsertionString2)
        }

        if (-NOT [string]::IsNullOrEmpty($InsertionString3)) 
        {
            $ev.SetProperty('InsertionString3', $InsertionString3)
        }

        if (-NOT [string]::IsNullOrEmpty($InsertionString4)) 
        {
            $ev.SetProperty('InsertionString4', $InsertionString4)
        }

        if (-NOT [string]::IsNullOrEmpty($InsertionString5)) 
        {
            $ev.SetProperty('InsertionString5', $InsertionString5)
        }

        $ev.Submit()    # or: $ev.SubmitPending($null, 0)
        return $true
    }
    Catch
    {
        return $false
    }
}