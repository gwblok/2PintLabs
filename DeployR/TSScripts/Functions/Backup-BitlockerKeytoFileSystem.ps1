[CmdletBinding()]
param(
	[Parameter(Mandatory = $false)]
	[string]$MountPoint = "C:",

	[Parameter(Mandatory = $false)]
	[string]$OutputFolder = "C:\ProgramData\BitLockerRecovery",

	[Parameter(Mandatory = $false)]
	[switch]$AddRecoveryProtectorIfMissing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$preferredLogFolder = "C:\_2P\Logs"
if (Test-Path -LiteralPath $preferredLogFolder -PathType Container) {
	$OutputFolder = $preferredLogFolder
}

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
	throw "This script must be run in an elevated PowerShell session."
}

Import-Module BitLocker -ErrorAction Stop

$bitLockerVolume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
$recoveryProtectors = @($bitLockerVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" })

if ($recoveryProtectors.Count -eq 0 -and $AddRecoveryProtectorIfMissing.IsPresent) {
	Add-BitLockerKeyProtector -MountPoint $MountPoint -RecoveryPasswordProtector -ErrorAction Stop | Out-Null
	$bitLockerVolume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
	$recoveryProtectors = @($bitLockerVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" })
}

if ($recoveryProtectors.Count -eq 0) {
	throw "No RecoveryPassword protector found on $MountPoint. Re-run with -AddRecoveryProtectorIfMissing to create one."
}

$selectedProtector = $recoveryProtectors | Where-Object { -not [string]::IsNullOrWhiteSpace($_.RecoveryPassword) } | Select-Object -First 1

if ($null -eq $selectedProtector) {
	throw "A RecoveryPassword protector exists but no recovery password value was returned."
}

New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null

$timeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeMountPoint = ($MountPoint -replace "[:\\]", "").Trim()
$outputFileName = "$($env:COMPUTERNAME)-$safeMountPoint-BitLockerRecovery-$timeStamp.txt"
$outputPath = Join-Path -Path $OutputFolder -ChildPath $outputFileName

$fileLines = @(
	"ComputerName: $($env:COMPUTERNAME)",
	"MountPoint: $MountPoint",
	"DateUtc: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))",
	"KeyProtectorId: $($selectedProtector.KeyProtectorId)",
	"RecoveryPassword: $($selectedProtector.RecoveryPassword)"
)

Set-Content -Path $outputPath -Value $fileLines -Encoding UTF8

Write-Host "BitLocker recovery key saved to: $outputPath" -ForegroundColor Green
