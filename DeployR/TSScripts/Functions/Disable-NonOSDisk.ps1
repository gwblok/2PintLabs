<#
.SYNOPSIS
Sets all non-OS disks offline while running in WinPE.

.DESCRIPTION
This script is intended for task sequence and WinPE scenarios where downstream
processes must interact with a specific OS disk without interference from
additional local disks. When running in WinPE, it finds every disk except the
protected disk number and sets those disks offline.

.NOTES
- The script only changes disk state when running in WinPE.
- The protected disk number defaults to 0 but can be overridden.
- Disks that are already offline are reported and skipped.

.EXAMPLE
Disable-NonOSDisk

.EXAMPLE
Disable-NonOSDisk -OSDiskNumber 1
#>

function Test-IsWinPE {
	[CmdletBinding()]
	param()

	if (Test-Path -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') {
		return $true
	}

	return $false
}

function Disable-NonOSDisk {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[int]$OSDiskNumber = 0
	)

	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host 'Disable Non-OS Disks' -ForegroundColor Cyan
	Write-Host '========================================' -ForegroundColor Cyan

	if (-not (Test-IsWinPE)) {
		Write-Host 'This script only takes action while running in WinPE. No disks were modified.' -ForegroundColor Yellow
		return
	}

	Write-Host ("WinPE detected. Preserving disk {0} and enumerating all other disks..." -f $OSDiskNumber) -ForegroundColor Yellow

	try {
		$nonOSDisks = Get-Disk -ErrorAction Stop | Where-Object { $_.Number -ne $OSDiskNumber } | Sort-Object Number
	}
	catch {
		Write-Host "Failed to enumerate disks: $($_.Exception.Message)" -ForegroundColor Red
		exit 1
	}

	if (-not $nonOSDisks) {
		Write-Host ("No disks other than disk {0} were found. No changes were needed." -f $OSDiskNumber) -ForegroundColor Green
		return
	}

	foreach ($disk in $nonOSDisks) {
		Write-Host ''
		Write-Host ("Disk {0}: {1}" -f $disk.Number, $disk.FriendlyName) -ForegroundColor White
		Write-Host ("  Current State : {0}" -f $disk.OperationalStatus)
		Write-Host ("  Is Offline    : {0}" -f $disk.IsOffline)

		if ($disk.IsOffline) {
			Write-Host '  Action        : Already offline, skipping.' -ForegroundColor DarkGray
			continue
		}

		try {
			Set-Disk -Number $disk.Number -IsOffline $true -ErrorAction Stop
			Write-Host '  Action        : Disk set offline successfully.' -ForegroundColor Green
		}
		catch {
			Write-Host ("  Action        : Failed to set disk offline - {0}" -f $_.Exception.Message) -ForegroundColor Red
			exit 1
		}
	}

	Write-Host ''
	Write-Host 'Completed processing non-OS disks.' -ForegroundColor Cyan
}

Disable-NonOSDisk
