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
.SYNOPSIS
    Script to test connections to a list of servers and ports.

.DESCRIPTION
    This script tests the connection to a list of servers and ports. It checks if a DNS entry exists and if a connection can be established.
    The script uses the Resolve-DnsName cmdlet to check for a DNS entry. If a DNS entry is found, the script tries to establish a connection 
    to the server and port using the .NET class System.Net.Sockets.TcpClient.

    The script returns a list of objects with the following properties:
    - Server: The server name
    - Port: The port number
    - Info: A message about the result of the test

.LINK
    https://github.com/jonasatgit/scriptrepo    
#>

$serverList = @(
    @{
        Server = "server1.contoso.local"
        Ports = @(80, 443, 10123)
    },
    @{
        Server = "server2.contoso.local"
        Ports = @(80, 443, 8530, 8531)
    },
    @{
        Server = "server3.contoso.local"
        Ports = @(80, 443)
    }
)

$outArray = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($server in $serverList) {
    # Check DNS entry
    $dnsEntry = Resolve-DnsName -Name $server.Server -ErrorAction SilentlyContinue
    if ($dnsEntry) {
        $outArray.Add([pscustomobject]@{
            Server = $server.Server
            Port = ""
            Info = "DNS entry found"
        })

        foreach ($port in $server.Ports) {
            # using .NET classes to avoid the long timeout of Test-NetConnection and the yellow output
            # $portResult = Test-NetConnection -ComputerName $server.Server -Port $port -InformationLevel Quiet
            $socket = New-Object System.Net.Sockets.TcpClient
            $result = $socket.BeginConnect($server.Server, $port, $null, $null)
            $success = $result.AsyncWaitHandle.WaitOne(1000, $false)

            if ($success) {
                $outArray.Add([pscustomobject]@{
                    Server = $server.Server
                    Port = $port
                    Info = "Connection successful"
                })
                $socket.EndConnect($result) | Out-Null
            } else {
                $outArray.Add([pscustomobject]@{
                    Server = $server.Server
                    DNS = $dnsEntry.NameHost
                    Port = $port
                    Info = "Connection failed"
                })
            }
            $socket.Close()
        }
    } else {
        $outArray.Add([pscustomobject]@{
            Server = $server.Server
            Port = ""
            Info = "No DNS entry found"
        })
    }
}

$outArray
