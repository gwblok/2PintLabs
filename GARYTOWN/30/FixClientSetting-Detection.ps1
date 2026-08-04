param(
	[string]$TelemetryRegPath = 'HKLM:\SOFTWARE\2Pint Software\StifleR\Client\SettingsOptions',
	[string]$TelemetryValueName = 'EnableDebugTelemetry',
	[string]$LogFilePath = 'C:\ProgramData\2Pint Software\StifleR\Client\MicrosoftWindowsKernelProcess.log'
)

$ErrorActionPreference = 'Stop'

try {
	if (Test-Path -LiteralPath $LogFilePath) {
		Write-Output "Detection failed: log file exists at $LogFilePath"
		exit 1
	}

	if (Test-Path -Path $TelemetryRegPath) {
		$telemetryValue = Get-ItemPropertyValue -Path $TelemetryRegPath -Name $TelemetryValueName -ErrorAction SilentlyContinue
		if ($null -ne $telemetryValue -and "$telemetryValue" -ieq 'True') {
			Write-Output "Detection failed: $TelemetryValueName is True"
			exit 1
		}
	}

	Write-Output 'Detection passed: log file missing and telemetry is not True.'
	exit 0
}
catch {
	Write-Output "Detection script error: $($_.Exception.Message)"
	exit 1
}
