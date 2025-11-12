<#
.SYNOPSIS
    Removes Azure Arc agent from a Windows machine

.DESCRIPTION
    This script completely removes the Azure Arc (Connected Machine Agent) from a Windows system.
    It stops services, uninstalls the agent, removes Windows capabilities, and cleans up any remaining files.
    Supports both online (running OS) and offline (mounted OS) scenarios.

.PARAMETER OfflinePath
    Path where the offline Windows installation is mounted (e.g., S:\). If not specified, runs in online mode.

.EXAMPLE
    .\RemoveAzureArc.ps1
    Removes Azure Arc from the running OS

.EXAMPLE
    .\RemoveAzureArc.ps1 -OfflinePath "S:\"
    Removes Azure Arc from an offline OS mounted at S:\

.NOTES
    Author: Gary Blok
    Date: November 7, 2025
    Requires: Administrator privileges


    Tested in DeployR Task Sequence in Offline Mode with Server 2025 - 25.7.11
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OfflinePath = 'S:\'
)

# Determine if running in offline mode
$isOffline = $false
if ($OfflinePath) {
    # Ensure path ends with backslash
    if (-not $OfflinePath.EndsWith('\')) {
        $OfflinePath += '\'
    }
    
    # Verify offline OS path exists
    if (-not (Test-Path $OfflinePath)) {
        Write-Host "✗ Offline OS path not found: $OfflinePath" -ForegroundColor Red
        exit 1
    }
    
    # Verify it looks like a Windows installation
    $windowsFolder = Join-Path -Path $OfflinePath -ChildPath "Windows"
    if (-not (Test-Path $windowsFolder)) {
        Write-Host "✗ Windows folder not found at: $windowsFolder" -ForegroundColor Red
        Write-Host "  This does not appear to be a valid Windows installation" -ForegroundColor Yellow
        exit 1
    }
    
    $isOffline = $true
}

Write-Host "`n===================================" -ForegroundColor Cyan
Write-Host "Azure Arc Removal Script" -ForegroundColor Cyan
if ($isOffline) {
    Write-Host "(Offline Mode - Target: $OfflinePath)" -ForegroundColor Yellow
}
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

# Check if Azure Arc is installed
Write-Host "Checking for Azure Arc installation..." -ForegroundColor Yellow

try {
    if ($isOffline) {
        $arcCapability = Get-WindowsCapability -Path $OfflinePath -Name "AzureArcSetup*" -ErrorAction Stop
    }
    else {
        $arcCapability = Get-WindowsCapability -Online -Name "AzureArcSetup*" -ErrorAction Stop
    }
    
    if ($arcCapability.State -ne 'Installed') {
        Write-Host "✓ Azure Arc is not installed on this system" -ForegroundColor Green
        exit 0
    }
    
    Write-Host "Found Azure Arc installation: $($arcCapability.Name)" -ForegroundColor Yellow
}
catch {
    # If "Element not found" error, Azure Arc might be partially installed or corrupted
    if ($_.Exception.Message -match "Element not found") {
        Write-Host "⚠ Azure Arc capability not found in clean state, will attempt cleanup anyway" -ForegroundColor Yellow
        $arcCapability = [PSCustomObject]@{ Name = "AzureArcSetup~~~~"; State = "Unknown" }
    }
    else {
        Write-Host "✗ Error checking Azure Arc status: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# Stop Azure Arc services (online mode only)
if (-not $isOffline) {
    Write-Host "=== Stopping Azure Arc Services ===" -ForegroundColor Cyan
    $arcServices = @(
        "himds",
        "GCArcService",
        "ExtensionService"
    )

    foreach ($serviceName in $arcServices) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -eq 'Running') {
                Write-Host "  Stopping service: $serviceName" -ForegroundColor Gray
                try {
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    Write-Host "  ✓ Stopped $serviceName" -ForegroundColor Green
                }
                catch {
                    Write-Host "  ⚠ Failed to stop $serviceName : $_" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "  Service $serviceName is already stopped" -ForegroundColor Gray
            }
        }
    }

    Write-Host ""
}
else {
    Write-Host "=== Skipping Service Operations (Offline Mode) ===" -ForegroundColor Gray
    Write-Host ""
}

# Disconnect from Azure Arc (online mode only, if azcmagent is available)
if (-not $isOffline) {
    Write-Host "=== Disconnecting from Azure ===" -ForegroundColor Cyan
    $azcmagentPath = "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe"

    if (Test-Path $azcmagentPath) {
        Write-Host "  Running azcmagent disconnect..." -ForegroundColor Gray
        try {
            $disconnectResult = & $azcmagentPath disconnect --force-local-only 2>&1
            Write-Host "  ✓ Disconnected from Azure Arc" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠ Disconnect may have failed, continuing with removal..." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  azcmagent not found, skipping disconnect step" -ForegroundColor Gray
    }

    Write-Host ""
}
else {
    Write-Host "=== Skipping Disconnect Operations (Offline Mode) ===" -ForegroundColor Gray
    Write-Host ""
}

# Uninstall Azure Connected Machine Agent (online mode only, if installed via MSI)
if (-not $isOffline) {
    Write-Host "=== Removing Azure Connected Machine Agent ===" -ForegroundColor Cyan

    $arcAgent = Get-WmiObject -Class Win32_Product -Filter "Name LIKE '%Azure Connected Machine Agent%'" -ErrorAction SilentlyContinue

    if ($arcAgent) {
        Write-Host "  Found: $($arcAgent.Name)" -ForegroundColor Gray
        Write-Host "  Uninstalling Azure Connected Machine Agent..." -ForegroundColor Yellow
        try {
            $arcAgent.Uninstall() | Out-Null
            Write-Host "  ✓ Agent uninstalled successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠ Failed to uninstall agent: $_" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  No MSI-installed agent found" -ForegroundColor Gray
    }

    Write-Host ""
}
else {
    Write-Host "=== Skipping MSI Uninstall (Offline Mode) ===" -ForegroundColor Gray
    Write-Host ""
}

# Remove Azure Arc Windows Capability
Write-Host "=== Removing Azure Arc Windows Capability ===" -ForegroundColor Cyan

try {
    Write-Host "  Removing capability: $($arcCapability.Name)" -ForegroundColor Gray
    if ($isOffline) {
        Remove-WindowsCapability -Path $OfflinePath -Name $arcCapability.Name -ErrorAction Stop | Out-Null
    }
    else {
        Remove-WindowsCapability -Online -Name $arcCapability.Name -ErrorAction Stop | Out-Null
    }
    Write-Host "  ✓ Azure Arc capability removed successfully" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Failed to remove capability: $_" -ForegroundColor Red
}

Write-Host ""

# Clean up remaining files and folders
Write-Host "=== Cleaning Up Remaining Files ===" -ForegroundColor Cyan

# Build cleanup paths based on online/offline mode
if ($isOffline) {
    $cleanupPaths = @(
        (Join-Path $OfflinePath "Windows\AzureArcSetup"),
        (Join-Path $OfflinePath "ProgramData\Microsoft\Windows\Start Menu\Programs\Azure Arc Setup.lnk")
    )
}
else {
    $cleanupPaths = @(
        "$env:SystemRoot\AzureArcSetup",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Azure Arc Setup.lnk"
    )
}

foreach ($path in $cleanupPaths) {
    if (Test-Path $path) {
        Write-Host "  Removing: $path" -ForegroundColor Gray
        try {
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            Write-Host "  ✓ Removed $path" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠ Could not remove $path : $_" -ForegroundColor Yellow
        }
    }
}

Write-Host ""

# Verify removal
Write-Host "=== Verifying Removal ===" -ForegroundColor Cyan

try {
    if ($isOffline) {
        $verifyCapability = Get-WindowsCapability -Path $OfflinePath -Name "AzureArcSetup*" -ErrorAction Stop
    }
    else {
        $verifyCapability = Get-WindowsCapability -Online -Name "AzureArcSetup*" -ErrorAction Stop
    }
    
    if ($verifyCapability.State -ne 'Installed') {
        Write-Host "✓ Azure Arc has been successfully removed!" -ForegroundColor Green
    }
    else {
        Write-Host "⚠ Azure Arc may still be present on the system" -ForegroundColor Yellow
        Write-Host "  Current state: $($verifyCapability.State)" -ForegroundColor Yellow
    }
}
catch {
    # If Get-WindowsCapability throws "Element not found", it means the capability is completely removed
    if ($_.Exception.Message -match "Element not found") {
        Write-Host "✓ Azure Arc has been successfully removed!" -ForegroundColor Green
    }
    else {
        Write-Host "⚠ Could not verify removal status: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Removal Complete" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""
