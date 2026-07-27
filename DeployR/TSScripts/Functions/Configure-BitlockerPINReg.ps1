$propertyName = 'UseTPMPIN'
$propertyValue = 1
$isWinPE = $env:SystemDrive.TrimEnd('\\').ToUpper() -eq 'X:'

$offlineHiveName = 'OFFLINE_SOFTWARE'
$offlineHiveRoot = "Registry::HKEY_LOCAL_MACHINE\$offlineHiveName"
$offlineWindowsPath = 'S:\Windows'
$offlineSoftwareHivePath = Join-Path -Path $offlineWindowsPath -ChildPath 'System32\config\SOFTWARE'

$regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
$offlineHiveLoaded = $false

try {
	Write-Host "[Configure-BitlockerPINReg] Starting registry configuration..." -ForegroundColor Cyan

	if ($isWinPE) {
		Write-Host "[Configure-BitlockerPINReg] WinPE detected (SystemDrive=$env:SystemDrive). Using offline registry on $offlineWindowsPath." -ForegroundColor Yellow

		if (-not (Test-Path -Path $offlineSoftwareHivePath)) {
			throw "Offline SOFTWARE hive not found at $offlineSoftwareHivePath"
		}

		if (Test-Path -Path $offlineHiveRoot) {
			Write-Host "[Configure-BitlockerPINReg] Existing mounted hive found at HKLM\$offlineHiveName. Unloading it first..." -ForegroundColor Yellow
			& reg.exe unload "HKLM\$offlineHiveName" | Out-Null
			if ($LASTEXITCODE -ne 0) {
				throw "Failed to unload existing HKLM\$offlineHiveName hive. Exit code: $LASTEXITCODE"
			}
		}

		Write-Host "[Configure-BitlockerPINReg] Loading offline SOFTWARE hive into HKLM\$offlineHiveName..." -ForegroundColor Cyan
		& reg.exe load "HKLM\$offlineHiveName" "$offlineSoftwareHivePath" | Out-Null
		if ($LASTEXITCODE -ne 0) {
			throw "Failed to load offline SOFTWARE hive from $offlineSoftwareHivePath. Exit code: $LASTEXITCODE"
		}

		$offlineHiveLoaded = $true
		$regPath = "$offlineHiveRoot\Policies\Microsoft\FVE"
	}
	else {
		Write-Host "[Configure-BitlockerPINReg] Online OS detected (SystemDrive=$env:SystemDrive). Using local registry." -ForegroundColor Green
	}

	if (-not (Test-Path -Path $regPath)) {
		Write-Host "[Configure-BitlockerPINReg] Registry path not found. Creating: $regPath" -ForegroundColor Yellow
		New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
	}
	else {
		Write-Host "[Configure-BitlockerPINReg] Registry path exists: $regPath" -ForegroundColor Green
	}

	Write-Host "[Configure-BitlockerPINReg] Setting $propertyName to $propertyValue (DWORD)..." -ForegroundColor Cyan
	New-ItemProperty -Path $regPath -Name $propertyName -Value $propertyValue -PropertyType DWord -Force -ErrorAction Stop | Out-Null

	Write-Host "[Configure-BitlockerPINReg] Successfully configured $propertyName." -ForegroundColor Green
}
catch {
	Write-Host "[Configure-BitlockerPINReg] Failed to configure registry setting. $($_.Exception.Message)" -ForegroundColor Red
	throw
}
finally {
	if ($offlineHiveLoaded) {
		Write-Host "[Configure-BitlockerPINReg] Unloading offline hive HKLM\$offlineHiveName..." -ForegroundColor Cyan
		& reg.exe unload "HKLM\$offlineHiveName" | Out-Null
		if ($LASTEXITCODE -ne 0) {
			Write-Host "[Configure-BitlockerPINReg] Warning: failed to unload HKLM\$offlineHiveName. Exit code: $LASTEXITCODE" -ForegroundColor Yellow
		}
	}
}