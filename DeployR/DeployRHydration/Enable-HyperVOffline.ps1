<#
.SYNOPSIS
    Enables Hyper-V on an offline Windows Server installation

.DESCRIPTION
    This script enables Hyper-V features on an offline Windows Server OS that is mounted at S:\
    Designed to run from Windows PE during deployment/imaging scenarios.

.PARAMETER OfflinePath
    The path where the offline Windows installation is mounted (default: S:\)

.EXAMPLE
    .\Enable-HyperVOffline.ps1
    
.EXAMPLE
    .\Enable-HyperVOffline.ps1 -OfflinePath "D:\Windows"

.NOTES
    Author: Gary Blok
    Date: November 5, 2025
    Requires: DISM, Windows PE or elevated environment
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OfflinePath = "S:\"
)

# Ensure path ends with backslash
if (-not $OfflinePath.EndsWith('\')) {
    $OfflinePath += '\'
}

Write-Host "`n===================================" -ForegroundColor Cyan
Write-Host "Enable Hyper-V on Offline OS" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

# Verify offline OS path exists
if (-not (Test-Path $OfflinePath)) {
    Write-Host "✗ Offline OS path not found: $OfflinePath" -ForegroundColor Red
    Write-Host "  Please ensure the Windows installation is mounted at the specified path" -ForegroundColor Yellow
    exit 1
}

# Verify it looks like a Windows installation
$windowsFolder = Join-Path -Path $OfflinePath -ChildPath "Windows"
if (-not (Test-Path $windowsFolder)) {
    Write-Host "✗ Windows folder not found at: $windowsFolder" -ForegroundColor Red
    Write-Host "  This does not appear to be a valid Windows installation" -ForegroundColor Yellow
    exit 1
}

Write-Host "Offline OS Path: $OfflinePath" -ForegroundColor Cyan
Write-Host ""

# Define Hyper-V features to enable (Server edition)
$hypervFeatures = @(
    "Microsoft-Hyper-V",
    "Microsoft-Hyper-V-Management-PowerShell",
    "Microsoft-Hyper-V-Management-Clients",
    "RSAT-Hyper-V-Tools-Feature"
)

Write-Host "=== Enabling Hyper-V Features ===" -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$failCount = 0

foreach ($feature in $hypervFeatures) {
    Write-Host "Processing: $feature" -ForegroundColor Gray
    
    try {
        # Check if feature exists first
        $featureInfo = Get-WindowsOptionalFeature -Path $OfflinePath -FeatureName $feature -ErrorAction SilentlyContinue
        
        if (-not $featureInfo) {
            Write-Host "  ⚠ Feature not found, skipping..." -ForegroundColor Yellow
            continue
        }
        
        if ($featureInfo.State -eq 'Enabled') {
            Write-Host "  ✓ Already enabled" -ForegroundColor Green
            $successCount++
            continue
        }
        
        # Enable the feature
        $result = Enable-WindowsOptionalFeature -Path $OfflinePath -FeatureName $feature -All -NoRestart -ErrorAction Stop
        
        if ($result.RestartNeeded) {
            Write-Host "  ✓ Enabled (restart required after boot)" -ForegroundColor Green
        }
        else {
            Write-Host "  ✓ Enabled successfully" -ForegroundColor Green
        }
        $successCount++
    }
    catch {
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

# Summary
Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Offline OS Path: $OfflinePath" -ForegroundColor Gray
Write-Host "Features Processed: $($hypervFeatures.Count)" -ForegroundColor Gray
Write-Host "Successfully Enabled: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if($failCount -gt 0){"Red"}else{"Gray"})
Write-Host ""

if ($successCount -gt 0) {
    Write-Host "✓ Hyper-V has been enabled on the offline OS" -ForegroundColor Green
    Write-Host "  The changes will take effect when the system boots into the OS" -ForegroundColor Gray
    exit 0
}
else {
    Write-Host "✗ No Hyper-V features were enabled" -ForegroundColor Red
    exit 1
}
