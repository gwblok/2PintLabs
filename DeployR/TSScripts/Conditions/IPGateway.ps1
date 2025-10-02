$NoPeeringGateways = @(
'192.168.20.1'
'192.168.214.1'
)

$gwList = @()
Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 1" | ForEach-Object {
	if ($_.DefaultIPGateway) {
		$_.DefaultIPGateway | ForEach-Object { $gwList += $_ }
	}
}

#If any gateway is in the no list, return true
foreach ($gw in $gwList) {
    if ($NoPeeringGateways -contains $gw) {
        Write-Host "Found Gateway $gw in No Peering List"
        return $true
    }
}