# .SYNOPSIS
# Waits for local port 1337 to remain free of active TCP connections.
#
# .DESCRIPTION
# Polls TCP connections on local port 1337 and exits successfully only after the
# port has remained free of active peer sessions for the quiet period. This checks
# connection state, not traffic sent over an already-established connection.
#
# .PARAMETER PollIntervalSeconds
# Number of seconds to wait between connection checks. Defaults to 1.
#
# .PARAMETER QuietPeriodSeconds
# Number of seconds the port must remain without active connections before success.
# Defaults to 30.
#
# .EXAMPLE
# .\WaitForBCConnections.ps1
#
# .EXAMPLE
# .\WaitForBCConnections.ps1 -PollIntervalSeconds 2
#
# .EXAMPLE
# .\WaitForBCConnections.ps1 -QuietPeriodSeconds 60
#
# .NOTES
# Author: Not specified
# Created: 2026-11-05
# Change History:
# 2026-11-05 - Initial version.

[CmdletBinding()]
param (
	[Parameter()]
	[ValidateRange(1, 3600)]
	[int] $PollIntervalSeconds = 1,

	[Parameter()]
	[ValidateRange(1, 86400)]
	[int] $QuietPeriodSeconds = 30
)

$InactiveStates = @('Listen', 'TimeWait', 'Closed', 'DeleteTcb', 'Bound')
$QuietSince = [datetime]::UtcNow

try {
	while ($true) {
		$ActiveConnections = @(
			Get-NetTCPConnection -LocalPort 1337 -ErrorAction Stop |
				Where-Object {
					$_.RemotePort -gt 0 -and $_.State.ToString() -notin $InactiveStates
				}
		)

		if ($ActiveConnections.Count -gt 0) {
			$QuietSince = [datetime]::UtcNow
			Write-Verbose "$($ActiveConnections.Count) active TCP connection(s) remain on local port 1337."
		}
		elseif (([datetime]::UtcNow - $QuietSince).TotalSeconds -ge $QuietPeriodSeconds) {
			Write-Output 'No active TCP connections remain on local port 1337.'
			exit 0
		}
		Start-Sleep -Seconds $PollIntervalSeconds
	}
}
catch {
	Write-Error "Failed to check TCP connections on local port 1337: $($_.Exception.Message)"
	exit 1
}
