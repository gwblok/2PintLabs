function Get-UniFiClientByMac {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[ValidatePattern('^(?:(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}|[0-9A-Fa-f]{12})$')]
		[string]$MacAddress,

		[Parameter(Mandatory)]
		[string]$ConsoleAddress,

		[string]$SiteId,

		[string]$ApiKeyPath = 'C:\Users\GaryBlok\OneDrive\APIKeys\UnifIAPI.txt',

		[switch]$SkipCertificateCheck
	)

	if (-not (Test-Path -LiteralPath $ApiKeyPath -PathType Leaf)) {
		throw "UniFi API key file was not found: $ApiKeyPath"
	}

	$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw -ErrorAction Stop).Trim().Trim('"', "'")
	if ([string]::IsNullOrWhiteSpace($apiKey)) {
		throw "UniFi API key file is empty: $ApiKeyPath"
	}

	$rawMacAddress = ($MacAddress -replace '[^0-9A-Fa-f]', '').ToUpper()
	$normalizedMacAddress = (0..5 | ForEach-Object { $rawMacAddress.Substring($_ * 2, 2) }) -join ':'
	$normalizedConsoleAddress = $ConsoleAddress.TrimEnd('/')
	if ($normalizedConsoleAddress -notmatch '^https?://') {
		$normalizedConsoleAddress = "https://$normalizedConsoleAddress"
	}

	$headers = @{ 'X-API-Key' = $apiKey }
	$requestParameters = @{
		Headers = $headers
		ErrorAction = 'Stop'
	}
	if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
		$requestParameters.SkipCertificateCheck = $true
	}

	try {
		if (-not $SiteId) {
			$sitesResponse = Invoke-RestMethod @requestParameters -Uri "$normalizedConsoleAddress/proxy/network/integration/v1/sites"
			$sites = @($sitesResponse.data)
			if ($sites.Count -eq 0) {
				throw 'No UniFi sites were returned by the API.'
			}
			if ($sites.Count -gt 1) {
				$siteList = $sites | ForEach-Object { "$($_.name) [$($_.id)]" } -join ', '
				throw "More than one UniFi site was returned. Specify -SiteId. Sites: $siteList"
			}
			$SiteId = $sites[0].id
		}

		$filter = [uri]::EscapeDataString("macAddress.eq('$normalizedMacAddress')")
		$clientsResponse = Invoke-RestMethod @requestParameters -Uri "$normalizedConsoleAddress/proxy/network/integration/v1/sites/$SiteId/clients?filter=$filter"
		$clients = @($clientsResponse.data)

		if ($clients.Count -eq 0) {
			Write-Verbose "No connected UniFi client was found for MAC address $MacAddress."
			return
		}

		$clients
	}
	catch {
		$statusCode = $null
		if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
			$statusCode = [int]$_.Exception.Response.StatusCode
		}
		if ($statusCode -eq 401) {
			throw "UniFi rejected the API key with HTTP 401. Confirm the key was created for UniFi API access, has access to this console, and that the key file contains only the key value."
		}
		throw
	}
	finally {
		Remove-Variable apiKey -ErrorAction SilentlyContinue
	}
}

function Get-UniFiDevices {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConsoleAddress,

		[string]$SiteId,

		[string]$ApiKeyPath = 'C:\Users\GaryBlok\OneDrive\APIKeys\UnifIAPI.txt',

		[ValidateRange(1, 200)]
		[int]$PageSize = 200,

		[switch]$SkipCertificateCheck
	)

	if (-not (Test-Path -LiteralPath $ApiKeyPath -PathType Leaf)) {
		throw "UniFi API key file was not found: $ApiKeyPath"
	}

	$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw -ErrorAction Stop).Trim().Trim('"', "'")
	if ([string]::IsNullOrWhiteSpace($apiKey)) {
		throw "UniFi API key file is empty: $ApiKeyPath"
	}

	$normalizedConsoleAddress = $ConsoleAddress.TrimEnd('/')
	if ($normalizedConsoleAddress -notmatch '^https?://') {
		$normalizedConsoleAddress = "https://$normalizedConsoleAddress"
	}

	$headers = @{ 'X-API-Key' = $apiKey }
	$requestParameters = @{
		Headers = $headers
		ErrorAction = 'Stop'
	}
	if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
		$requestParameters.SkipCertificateCheck = $true
	}

	try {
		if (-not $SiteId) {
			$sitesResponse = Invoke-RestMethod @requestParameters -Uri "$normalizedConsoleAddress/proxy/network/integration/v1/sites"
			$sites = @($sitesResponse.data)
			if ($sites.Count -eq 0) {
				throw 'No UniFi sites were returned by the API.'
			}
			if ($sites.Count -gt 1) {
				$siteList = $sites | ForEach-Object { "$($_.name) [$($_.id)]" } -join ', '
				throw "More than one UniFi site was returned. Specify -SiteId. Sites: $siteList"
			}
			$SiteId = $sites[0].id
		}

		$offset = 0
		do {
			$uri = "$normalizedConsoleAddress/proxy/network/integration/v1/sites/$SiteId/devices?offset=$offset&limit=$PageSize"
			$response = Invoke-RestMethod @requestParameters -Uri $uri
			$devices = @($response.data)
			$devices
			$offset += $devices.Count
		} while ($devices.Count -gt 0 -and $offset -lt [int64]$response.totalCount)
	}
	catch {
		$statusCode = $null
		if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
			$statusCode = [int]$_.Exception.Response.StatusCode
		}
		if ($statusCode -eq 401) {
			throw "UniFi rejected the API key with HTTP 401. Confirm the key was created for UniFi API access, has access to this console, and that the key file contains only the key value."
		}
		throw
	}
	finally {
		Remove-Variable apiKey -ErrorAction SilentlyContinue
	}
}

function Get-UniFiEndpoints {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConsoleAddress,

		[string]$SiteId,

		[string]$ApiKeyPath = 'C:\Users\GaryBlok\OneDrive\APIKeys\UnifIAPI.txt',

		[ValidateRange(1, 200)]
		[int]$PageSize = 200,

		[switch]$SkipCertificateCheck
	)

	if (-not (Test-Path -LiteralPath $ApiKeyPath -PathType Leaf)) {
		throw "UniFi API key file was not found: $ApiKeyPath"
	}

	$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw -ErrorAction Stop).Trim().Trim('"', "'")
	if ([string]::IsNullOrWhiteSpace($apiKey)) {
		throw "UniFi API key file is empty: $ApiKeyPath"
	}

	$normalizedConsoleAddress = $ConsoleAddress.TrimEnd('/')
	if ($normalizedConsoleAddress -notmatch '^https?://') {
		$normalizedConsoleAddress = "https://$normalizedConsoleAddress"
	}

	$headers = @{ 'X-API-Key' = $apiKey }
	$requestParameters = @{
		Headers = $headers
		ErrorAction = 'Stop'
	}
	if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
		$requestParameters.SkipCertificateCheck = $true
	}

	try {
		if (-not $SiteId) {
			$sitesResponse = Invoke-RestMethod @requestParameters -Uri "$normalizedConsoleAddress/proxy/network/integration/v1/sites"
			$sites = @($sitesResponse.data)
			if ($sites.Count -eq 0) {
				throw 'No UniFi sites were returned by the API.'
			}
			if ($sites.Count -gt 1) {
				$siteList = $sites | ForEach-Object { "$($_.name) [$($_.id)]" } -join ', '
				throw "More than one UniFi site was returned. Specify -SiteId. Sites: $siteList"
			}
			$SiteId = $sites[0].id
		}

		$offset = 0
		do {
			$uri = "$normalizedConsoleAddress/proxy/network/integration/v1/sites/$SiteId/clients?offset=$offset&limit=$PageSize"
			$response = Invoke-RestMethod @requestParameters -Uri $uri
			$endpoints = @($response.data)
			$endpoints
			$offset += $endpoints.Count
		} while ($endpoints.Count -gt 0 -and $offset -lt [int64]$response.totalCount)
	}
	catch {
		$statusCode = $null
		if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
			$statusCode = [int]$_.Exception.Response.StatusCode
		}
		if ($statusCode -eq 401) {
			throw "UniFi rejected the API key with HTTP 401. Confirm the key was created for UniFi API access, has access to this console, and that the key file contains only the key value."
		}
		throw
	}
	finally {
		Remove-Variable apiKey -ErrorAction SilentlyContinue
	}
}

function Get-UniFiLegacyEndpoints {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConsoleAddress,

		[string]$SiteName,

		[ValidatePattern('^(?:(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}|[0-9A-Fa-f]{12})$')]
		[string]$MacAddress,

		[switch]$Wired,

		[switch]$Online,

		[switch]$ShowAll,

		[string]$ApiKeyPath = 'C:\Users\GaryBlok\OneDrive\APIKeys\UnifIAPI.txt',

		[switch]$SkipCertificateCheck
	)

	if (-not (Test-Path -LiteralPath $ApiKeyPath -PathType Leaf)) {
		throw "UniFi API key file was not found: $ApiKeyPath"
	}

	$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw -ErrorAction Stop).Trim().Trim('"', "'")
	if ([string]::IsNullOrWhiteSpace($apiKey)) {
		throw "UniFi API key file is empty: $ApiKeyPath"
	}

	$normalizedConsoleAddress = $ConsoleAddress.TrimEnd('/')
	if ($normalizedConsoleAddress -notmatch '^https?://') {
		$normalizedConsoleAddress = "https://$normalizedConsoleAddress"
	}

	$headers = @{ 'X-API-Key' = $apiKey }
	$requestParameters = @{
		Headers = $headers
		ErrorAction = 'Stop'
	}
	if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
		$requestParameters.SkipCertificateCheck = $true
	}

	try {
		if (-not $SiteName) {
			$sitesResponse = Invoke-RestMethod @requestParameters -Uri "$normalizedConsoleAddress/proxy/network/integration/v1/sites"
			$sites = @($sitesResponse.data)
			if ($sites.Count -eq 0) {
				throw 'No UniFi sites were returned by the API.'
			}
			if ($sites.Count -gt 1) {
				$siteList = $sites | ForEach-Object { "$($_.name) [$($_.internalReference)]" } -join ', '
				throw "More than one UniFi site was returned. Specify -SiteName. Sites: $siteList"
			}
			$SiteName = $sites[0].internalReference
		}

		$uri = "$normalizedConsoleAddress/proxy/network/api/s/$([uri]::EscapeDataString($SiteName))/stat/sta"
		$legacyResponse = Invoke-RestMethod @requestParameters -Uri $uri
		$endpoints = @($legacyResponse.data)

		if ($MacAddress) {
			$rawMacAddress = ($MacAddress -replace '[^0-9A-Fa-f]', '').ToUpper()
			$normalizedMacAddress = (0..5 | ForEach-Object { $rawMacAddress.Substring($_ * 2, 2) }) -join ':'
			$endpoints = @($endpoints | Where-Object {
				($_.mac -replace '[^0-9A-Fa-f]', '').ToUpper() -eq ($normalizedMacAddress -replace ':', '')
			})
		}

		if ($Wired) {
			$endpoints = @($endpoints | Where-Object { $_.is_wired -eq $true })
		}

		if ($Online) {
			$onlineCutoff = [DateTimeOffset]::Now.ToUnixTimeSeconds() - 300
			$endpoints = @($endpoints | Where-Object {
				$activityTimestamps = @(
					[long]$_.last_seen,
					[long]$_._last_reachable_by_gw,
					[long]$_._last_seen_by_usw
				) | Where-Object { $_ -gt 0 }
				$latestActivity = $activityTimestamps | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
				$latestActivity -ge $onlineCutoff
			})
		}

		if (-not $ShowAll) {
			$endpoints = @($endpoints | Where-Object {
				-not $_.PSObject.Properties['unifi_device_info_from_ucore'] -or
				$null -eq $_.unifi_device_info_from_ucore
			})
		}

		if ($ShowAll) {
			$endpoints
		}
		else {
			$hiddenProperties = @(
				'sw_depth',
				'unifi_device_info_from_ucore',
				'product_line',
				'fw_version',
				'site_id',
				'dev_cat',
				'usergroup_id',
				'last_uplink_mac',
				'last_connection_network_name',
				'_uptime_by_usw',
				'_last_seen_by_usw',
				'_is_guest_by_usw',
				'sw_mac',
				'_id',
				'satisfaction',
				'anomalies',
				'satisfaction_avg',
				'uptime',
				'eagerly_discovered',
				'_uptime_by_ugw',
				'_last_seen_by_ugw',
				'_is_guest_by_ugw',
				'gw_mac',
				'gw_vlan',
				'_last_reachable_by_gw',
				'wired-tx_bytes',
				'wired-rx_bytes',
				'wired-tx_packets',
				'wired-rx_packets',
				'tx_retries',
				'wifi_tx_attempts',
				'wifi_tx_dropped',
				'wifi_tx_retries_percentage',
				'qos_policy_applied',
				'wired-tx_bytes-r',
				'wired-rx_bytes-r',
				'ipv6_addresses',
				'last_1x_identity',
				'assoc_time',
				'latest_assoc_time',
				'user_id',
				'first_seen',
				'last_seen',
				'is_guest',
				'fingerprint_engine_version',
				'disconnect_timestamp',
				'last_ipv6',
				'dev_family',
				'confidence',
				'last_uplink_remote_port',
				'fingerprint_source',
				'dev_id',
				'noted',
				'last_connection_network_id',
				'network_id'
			)
			$endpoints | Select-Object * -ExcludeProperty $hiddenProperties
		}
	}
	catch {
		$statusCode = $null
		if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
			$statusCode = [int]$_.Exception.Response.StatusCode
		}
		if ($statusCode -eq 401) {
			throw "The legacy UniFi endpoint rejected the API key with HTTP 401. This undocumented API may require local UniFi credentials instead of an API key."
		}
		throw
	}
	finally {
		Remove-Variable apiKey -ErrorAction SilentlyContinue
	}
}
