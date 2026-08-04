param(
	[string]$ServiceName = 'StifleRClient',
	[string]$TelemetryRegPath = 'HKLM:\SOFTWARE\2Pint Software\StifleR\Client\SettingsOptions',
	[string]$TelemetryValueName = 'EnableDebugTelemetry',
	[string]$TelemetryValueData = 'False',
	[string]$LogFilePath = 'C:\ProgramData\2Pint Software\StifleR\Client\MicrosoftWindowsKernelProcess.log'
)

$ErrorActionPreference = 'Stop'

Write-Output "Starting remediation for StifleR client settings and log file cleanup."

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
	Write-Output "Service '$ServiceName' was not found. Proceeding with registry and file operations only."
}

try {
	if ($service -and $service.Status -ne 'Stopped') {
		Write-Output "Stopping service '$ServiceName'..."
		Stop-Service -Name $ServiceName -Force -ErrorAction Stop
		(Get-Service -Name $ServiceName).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
		Write-Output "Service '$ServiceName' is stopped."
	}
	elseif ($service) {
		Write-Output "Service '$ServiceName' is already stopped."
	}

	Write-Output "Setting '$TelemetryValueName' to '$TelemetryValueData' in '$TelemetryRegPath'."
	if (-not (Test-Path -Path $TelemetryRegPath)) {
		throw "Registry path not found: $TelemetryRegPath"
	}

	New-ItemProperty -Path $TelemetryRegPath -Name $TelemetryValueName -Value $TelemetryValueData -PropertyType String -Force | Out-Null
	Write-Output "Updated registry value '$TelemetryValueName' to '$TelemetryValueData'."

	if (Test-Path -LiteralPath $LogFilePath) {
		Write-Output "Deleting log file: $LogFilePath"
		Remove-Item -LiteralPath $LogFilePath -Force -ErrorAction Stop
		Write-Output "Deleted log file successfully."
	}
	else {
		Write-Output "Log file not found, nothing to delete: $LogFilePath"
	}
}
catch {
	Write-Output "Remediation action failed: $($_.Exception.Message)"
}
finally {
	if ($service) {
		try {
			Write-Output "Starting service '$ServiceName'..."
			Start-Service -Name $ServiceName -ErrorAction Stop
			(Get-Service -Name $ServiceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
			Write-Output "Service '$ServiceName' is running."
		}
		catch {
			Write-Output "Failed to start service '$ServiceName': $($_.Exception.Message)"
		}
	}
}

Write-Output "Remediation script finished."
