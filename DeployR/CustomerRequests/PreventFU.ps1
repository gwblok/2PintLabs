# ================================================
# PowerShell Script: Pin Windows 11 to 24H2
# Prevents automatic feature update to 25H2 (or newer)
# via the official TargetReleaseVersion policy
# ================================================

# Requires Administrator rights
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as administrator', then try again." -ForegroundColor Yellow
    Pause
    exit 1
}

# Registry path (Microsoft recommended location for policy settings)
$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# Create the registry key/path if it does not exist
if (-not (Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
    Write-Host "Created registry path: $RegPath" -ForegroundColor Cyan
}

# Set the three required registry values to lock the device to Windows 11 24H2
# ProductVersion     = "Windows 11"     (tells Windows this is a Windows 11 device)
# TargetReleaseVersion = 1              (enables the target version pinning)
# TargetReleaseVersionInfo = "24H2"     (the exact release we want to stay on)

Set-ItemProperty -Path $RegPath -Name "ProductVersion"          -Value "Windows 11" -Type String -Force
Set-ItemProperty -Path $RegPath -Name "TargetReleaseVersion"    -Value 1          -Type DWord  -Force
Set-ItemProperty -Path $RegPath -Name "TargetReleaseVersionInfo" -Value "24H2"     -Type String -Force

Write-Host "`nSUCCESS: Registry values have been set!" -ForegroundColor Green
Write-Host "   • ProductVersion          = Windows 11" -ForegroundColor White
Write-Host "   • TargetReleaseVersion    = 1 (enabled)" -ForegroundColor White
Write-Host "   • TargetReleaseVersionInfo = 24H2" -ForegroundColor White
Write-Host "`nThis device will now stay on Windows 11 24H2 and will NOT automatically download or install the 25H2 feature update." -ForegroundColor Green

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Restart the computer (recommended)" -ForegroundColor White
Write-Host "2. Open Windows Update (Settings → Windows Update) and click 'Check for updates'" -ForegroundColor White
Write-Host "   → You should no longer see the 25H2 upgrade offer." -ForegroundColor White

Write-Host "`nTo undo this change later (allow 25H2 or newer):" -ForegroundColor Yellow
Write-Host "   Set-ItemProperty -Path '$RegPath' -Name 'TargetReleaseVersion' -Value 0 -Type DWord -Force" -ForegroundColor Gray
Write-Host "   (or simply delete the three values above)" -ForegroundColor Gray

Write-Host "`nScript completed. Press any key to exit..." -ForegroundColor White
Pause