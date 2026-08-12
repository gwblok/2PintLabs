<#
.SYNOPSIS
	Updates 2Pint registry thumbprints after certificate renewal.

.DESCRIPTION
	Finds the newest certificate in the LocalMachine\My store issued by
	CN=YR1, O=Let's Encrypt, C=US and updates the StifleR and DeployR
	registry settings that reference that certificate thumbprint.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
	[string]$IssuerMatch = 'CN=YR1, O=Let''s Encrypt, C=US'
)

$ErrorActionPreference = 'Stop'

$logRoot = 'D:\ServerAutomationLogs'
if (-not (Test-Path -Path $logRoot)) {
	New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
}

$logFile = Join-Path $logRoot ("PostCertRenewalUpdates_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Start-Transcript -Path $logFile -Force | Out-Null

#region Functions
function Get-RegistryThumbprintTarget {
	param(
		[Parameter(Mandatory)]
		[string]$Path,

		[Parameter(Mandatory)]
		[string[]]$Names
	)

	[pscustomobject]@{
		Path  = $Path
		Names = $Names
	}
}

function Get-NewestMatchingCertificate {
	param(
		[Parameter(Mandatory)]
		[string]$IssuerFilter
	)

	$certificates = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {
		$_.Issuer -like "*$IssuerFilter*" -and
		$_.NotAfter -gt (Get-Date)
	}

	if (-not $certificates) {
		throw "No valid certificate was found in Cert:\LocalMachine\My with issuer '$IssuerFilter'."
	}

	$certificates | Sort-Object NotAfter -Descending | Select-Object -First 1
}

function Set-RegistryThumbprintValue {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[Parameter(Mandatory)]
		[string]$Path,

		[Parameter(Mandatory)]
		[string[]]$Names,

		[Parameter(Mandatory)]
		[string]$Thumbprint
	)

	foreach ($name in $Names) {
		$targetDescription = "$Path -> $name"
		$previousThumbprint = $null

		if (Test-Path -Path $Path) {
			try {
				$previousThumbprint = (Get-ItemProperty -Path $Path -Name $name -ErrorAction Stop).$name
			}
			catch {
				$previousThumbprint = $null
			}
		}

		if ($PSCmdlet.ShouldProcess($targetDescription, "Set thumbprint to $Thumbprint")) {
			if (-not (Test-Path -Path $Path)) {
				New-Item -Path $Path -Force | Out-Null
			}

			Set-ItemProperty -Path $Path -Name $name -Value $Thumbprint -Type String
			Write-Host "Updated $Path -> $name" -ForegroundColor Green
			Write-Host " Previous: $previousThumbprint" -ForegroundColor DarkGray
			Write-Host " New:      $Thumbprint" -ForegroundColor Green
		}
		else {
			Write-Host "Would update $Path -> $name" -ForegroundColor Yellow
			Write-Host " Previous: $previousThumbprint" -ForegroundColor DarkGray
			Write-Host " New:      $Thumbprint" -ForegroundColor Yellow
		}
	}
}

function Restart-ServiceWithWait {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[Parameter(Mandatory)]
		[string]$Name,

		[Parameter(Mandatory)]
		[string]$DisplayName
	)

	$service = Get-Service -Name $Name -ErrorAction SilentlyContinue
	if (-not $service) {
		Write-Warning "Service $DisplayName ($Name) was not found; skipping restart."
		return
	}

	$actionDescription = "Restart $DisplayName ($Name)"

	if ($PSCmdlet.ShouldProcess($actionDescription, "Stop, start, and wait for the service to be running")) {
		Write-Host "Restarting $DisplayName service ($Name)..." -ForegroundColor Cyan
		Write-Host " Current status: $($service.Status)" -ForegroundColor DarkGray

		if ($service.Status -ne 'Stopped') {
			Stop-Service -Name $Name -Force -ErrorAction Stop
			$service.WaitForStatus('Stopped', '00:00:30')
			$service.Refresh()
			Write-Host " Stopped: $($service.Status)" -ForegroundColor Green
		}
		else {
			Write-Host " Service is already stopped." -ForegroundColor DarkGray
		}

		Start-Service -Name $Name -ErrorAction Stop
		$service.WaitForStatus('Running', '00:00:30')
		$service.Refresh()
		Write-Host " Running: $($service.Status)" -ForegroundColor Green
	}
	else {
		Write-Host "Would restart $DisplayName service ($Name)." -ForegroundColor Yellow
		Write-Host " Current status: $($service.Status)" -ForegroundColor DarkGray
	}
}

function Remove-CertificateFromStore {
	param(
		[Parameter(Mandatory)]
		[string]$StoreName,

		[Parameter(Mandatory)]
		[string]$Thumbprint,

		[string]$StoreLocation = 'LocalMachine'
	)

	if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
		Write-Host "No thumbprint supplied for removal from $StoreLocation\\$StoreName." -ForegroundColor DarkGray
		return $false
	}

	$normalizedThumbprint = $Thumbprint.Trim().Replace(' ', '').ToUpperInvariant()
	$store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
		[System.Security.Cryptography.X509Certificates.StoreName]::$StoreName,
		[System.Security.Cryptography.X509Certificates.StoreLocation]::$StoreLocation
	)

	$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
	$certificates = @($store.Certificates | Where-Object {
		($_.Thumbprint.Trim().Replace(' ', '').ToUpperInvariant()) -eq $normalizedThumbprint
	})

	if (-not $certificates) {
		Write-Host "No certificate with thumbprint $Thumbprint was found in $StoreLocation\\$StoreName." -ForegroundColor DarkGray
		$store.Close()
		return $false
	}

	foreach ($certificate in $certificates) {
		$store.Remove($certificate)
		Write-Host "Removed certificate with thumbprint $($certificate.Thumbprint) from $StoreLocation\\$StoreName." -ForegroundColor Yellow
	}

	$store.Close()
	return $true
}

function Add-CertificateToRootStore {
	param(
		[Parameter(Mandatory)]
		[System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
	)

	$store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
		[System.Security.Cryptography.X509Certificates.StoreName]::Root,
		[System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
	)

	$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
	$existing = @($store.Certificates | Where-Object {
		($_.Thumbprint.Trim().Replace(' ', '').ToUpperInvariant()) -eq ($Certificate.Thumbprint.Trim().Replace(' ', '').ToUpperInvariant())
	})

	if ($existing) {
		Write-Host "Certificate with thumbprint $($Certificate.Thumbprint) is already present in LocalMachine\Root." -ForegroundColor DarkGray
		$store.Close()
		return $true
	}

	$store.Add($Certificate)
	Write-Host "Copied certificate to LocalMachine\Root with thumbprint $($Certificate.Thumbprint)." -ForegroundColor Green
	$store.Close()
	return $true
}

#endregion

try {
	Write-Host "Searching for renewal certificate..." -ForegroundColor Cyan
	$certificate = Get-NewestMatchingCertificate -IssuerFilter $IssuerMatch

	Write-Host "Using certificate:" -ForegroundColor Cyan
	Write-Host " Subject:    $($certificate.Subject)" -ForegroundColor DarkGray
	Write-Host " Issuer:     $($certificate.Issuer)" -ForegroundColor DarkGray
	Write-Host " Thumbprint: $($certificate.Thumbprint)" -ForegroundColor Green
	Write-Host " Valid To:   $($certificate.NotAfter)" -ForegroundColor DarkGray

	$momRegistryPath = 'HKLM:\SOFTWARE\2Pint Software\StifleR\Mom\GeneralSettings'
	$currentMomThumbprint = $null

	if (Test-Path -Path $momRegistryPath) {
		try {
			$currentMomThumbprint = (Get-ItemProperty -Path $momRegistryPath -Name 'CertificateThumbprint' -ErrorAction Stop).'CertificateThumbprint'
			if (-not [string]::IsNullOrWhiteSpace($currentMomThumbprint)) {
				Write-Host "Current MOM certificate thumbprint: $currentMomThumbprint" -ForegroundColor Cyan
				Remove-CertificateFromStore -StoreName Root -Thumbprint $currentMomThumbprint -StoreLocation 'LocalMachine'
			}
		}
		catch {
			Write-Host "Unable to read current MOM thumbprint from $momRegistryPath; continuing." -ForegroundColor DarkGray
		}
	}
	else {
		Write-Host "MOM registry path $momRegistryPath was not found; continuing with root-store cleanup only." -ForegroundColor DarkGray
	}

	Add-CertificateToRootStore -Certificate $certificate

	$targets = @(
		Get-RegistryThumbprintTarget -Path 'HKLM:\SOFTWARE\2Pint Software\StifleR\Server\GeneralSettings' -Names @('SignalRCertificateThumbprint', 'WSCertificateThumbprint')
		Get-RegistryThumbprintTarget -Path $momRegistryPath -Names @('CertificateThumbprint')
		Get-RegistryThumbprintTarget -Path 'HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings' -Names @('CertificateThumbprint')
	)

	foreach ($target in $targets) {
		Set-RegistryThumbprintValue -Path $target.Path -Names $target.Names -Thumbprint $certificate.Thumbprint
	}

	Write-Host "Registry thumbprints updated successfully." -ForegroundColor Cyan

	$serviceTargets = @(
		@{ Name = 'DeployRService'; DisplayName = 'DeployR' }
		@{ Name = 'StifleRMom'; DisplayName = 'MOM' }
		@{ Name = 'StifleRServer'; DisplayName = 'StifleR' }
	)

	foreach ($serviceTarget in $serviceTargets) {
		Restart-ServiceWithWait -Name $serviceTarget.Name -DisplayName $serviceTarget.DisplayName
	}

	Write-Host "Service restarts completed successfully." -ForegroundColor Cyan
}
finally {
	Stop-Transcript | Out-Null
}
