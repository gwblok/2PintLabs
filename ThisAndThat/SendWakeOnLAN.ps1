# Source - https://stackoverflow.com/a/72853503
# Posted by lauxjpn, modified by community. See post 'Timeline' for change history
# Retrieved 2026-09-10, License - CC BY-SA 4.0

<#List of My MACS:
HP-Z2-SFF-G5 = 00:68:eb:bf:3b:ba


#>


function Send-WakeOnLan {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^(?:(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}|[0-9A-Fa-f]{12})$')]
        [string]$MacAddress,

        [ValidateScript({
            $parsedAddress = $null
            [System.Net.IPAddress]::TryParse($_, [ref]$parsedAddress) -and $parsedAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
        })]
        [string]$BroadcastAddress = '255.255.255.255',

        [ValidateRange(1, 65535)]
        [int]$Port = 9
    )

    $targetPhysicalAddress = [System.Net.NetworkInformation.PhysicalAddress]::Parse(($MacAddress -replace '[^0-9A-Fa-f]', '').ToUpper())
    $targetPhysicalAddressBytes = $targetPhysicalAddress.GetAddressBytes()
    $packet = [byte[]](,0xFF * 102)

    for ($index = 6; $index -lt $packet.Length; $index++) {
        $packet[$index] = $targetPhysicalAddressBytes[($index % 6)]
    }

    $targetEndpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($BroadcastAddress), $Port)

    [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object {
            $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback -and
            $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up
        } |
        ForEach-Object {
            $networkInterface = $_
            $networkInterface.GetIPProperties().UnicastAddresses |
                Where-Object { $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
                ForEach-Object {
                    $localEndpoint = [System.Net.IPEndPoint]::new($_.Address, 0)
                    $client = [System.Net.Sockets.UdpClient]::new($localEndpoint)
                    try {
                        $client.EnableBroadcast = $true
                        $client.Send($packet, $packet.Length, $targetEndpoint) | Out-Null
                        [pscustomobject]@{
                            Status = 'Sent'
                            MacAddress = $MacAddress
                            Interface = $networkInterface.Name
                            LocalAddress = $_.Address.IPAddressToString
                            BroadcastAddress = $BroadcastAddress
                            Port = $Port
                            BytesSent = $packet.Length
                        }
                        Write-Verbose "Wake-on-LAN packet sent for $MacAddress via $($networkInterface.Name)"
                    }
                    finally {
                        $client.Dispose()
                    }
                }
        }
}
