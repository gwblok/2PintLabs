<#
Purpose:
- Enable Remote Desktop
- Disable Network Level Authentication (NLA) requirement (the checkbox in Settings)
- Enable Remote Desktop firewall rules

Designed for:
- OSD task sequence execution in SYSTEM context
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "============================================================"
Write-Host "EnableRDP - Starting"
Write-Host "============================================================"

try {
	# 1) Enable Remote Desktop (allow RDP connections)
	Write-Host "Enabling Remote Desktop (fDenyTSConnections = 0)..."
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Type DWord -Value 0

	# 2) Disable NLA requirement (uncheck: Require devices to use Network Level Authentication)
	Write-Host "Disabling NLA requirement (UserAuthentication = 0)..."
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Type DWord -Value 0

	# Optional but helpful in some baselines: use classic RDP security layer when NLA is disabled
	Write-Host "Setting RDP security layer to negotiate (SecurityLayer = 1)..."
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "SecurityLayer" -Type DWord -Value 1

	# 3) Ensure firewall rules for Remote Desktop are enabled
	Write-Host "Enabling Windows Firewall rules for Remote Desktop..."
	Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

	# 4) Ensure Remote Desktop Services is configured/running
	Write-Host "Ensuring TermService startup is Automatic and service is running..."
	Set-Service -Name "TermService" -StartupType Automatic
	Start-Service -Name "TermService"

	# 5) Verification output
	$rdpEnabled = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections").fDenyTSConnections
	$nlaValue = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication").UserAuthentication
	$securityLayer = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "SecurityLayer").SecurityLayer
	$fwEnabledCount = (Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq "True" }).Count

	Write-Host ""
	Write-Host "Verification:"
	Write-Host " - fDenyTSConnections: $rdpEnabled (expected 0)"
	Write-Host " - UserAuthentication : $nlaValue (expected 0)"
	Write-Host " - SecurityLayer      : $securityLayer (expected 1)"
	Write-Host " - Enabled RD FW rules: $fwEnabledCount"

	if (($rdpEnabled -ne 0) -or ($nlaValue -ne 0)) {
		throw "RDP configuration validation failed."
	}

	Write-Host "============================================================"
	Write-Host "EnableRDP - Completed successfully"
	Write-Host "============================================================"
	exit 0
}
catch {
	Write-Error "EnableRDP failed: $($_.Exception.Message)"
	exit 1
}

