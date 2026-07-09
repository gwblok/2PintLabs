<#
.SYNOPSIS
Updates the StifleR Client App content item in DeployR.

.DESCRIPTION
Finds the extracted StifleR Client MSI (produced by Update-2PintStifleRFromZip.ps1),
reads the version from the MSI, and compares it against the version stored in the
Description field of version 1 of the DeployR Content Item named by $StifleRAppName.
If the MSI is newer, copies it to the DeployR source folder and overwrites version 1
of the CI with the new content.

.NOTES
Requires: DeployR.Utility PowerShell module
Run as: Administrator on the DeployR server
#>

#Region Variables
$StifleRAppName    = 'StifleR 3.1 Client'
$MSISourceFolder   = "$env:USERPROFILE\Downloads\StifleR\Extracted"
$DeployRDestFolder = 'D:\DeployRSources\Applications\2Pint Software\StifleRClient'
#EndRegion

#Region Functions

function Get-MSIProductVersion {
    param([string]$MSIPath)
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database  = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($MSIPath, 0))
        $view      = $database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $database, @("SELECT Value FROM Property WHERE Property = 'ProductVersion'"))
        $null      = $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
        $record    = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
        $version   = $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, @(1))
        [Runtime.InteropServices.Marshal]::ReleaseComObject($view)     | Out-Null
        [Runtime.InteropServices.Marshal]::ReleaseComObject($database) | Out-Null
        [Runtime.InteropServices.Marshal]::ReleaseComObject($installer)| Out-Null
        return $version
    }
    catch {
        Write-Warning "COM method failed for MSI version, falling back to FileVersionInfo: $_"
        return (Get-Item $MSIPath).VersionInfo.ProductVersion
    }
}

#EndRegion

#Region Connect to DeployR
$ModulePath = 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
if ((Get-Service -Name DeployRService).Status -ne 'Running') {
    Write-Host "DeployR Service is not running. Starting Service." -ForegroundColor Yellow
    Start-Service -Name DeployRService
    Start-Sleep -Seconds 10
}
Import-Module $ModulePath

if (Test-Path "HKLM:\software\2Pint Software\DeployR\GeneralSettings") {
    $DeployRReg     = Get-Item -Path "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"
    $ClientPasscode = $DeployRReg.GetValue("ClientPasscode")
    Connect-DeployR -Passcode $ClientPasscode -ErrorAction Stop
}
elseif (Test-Path "D:\DeployRPasscode.txt") {
    $ClientPasscode = (Get-Content "D:\DeployRPasscode.txt" -Raw)
    Connect-DeployR -Passcode $ClientPasscode -ErrorAction Stop
}
else {
    throw "Cannot find DeployR Client Passcode in registry or D:\DeployRPasscode.txt"
}
#EndRegion

#Region Find StifleR Client MSI
Write-Host "Looking for StifleR Client MSI in: $MSISourceFolder" -ForegroundColor Cyan

if (-not (Test-Path $MSISourceFolder)) {
    throw "StifleR extracted source folder not found: $MSISourceFolder`nRun Update-2PintStifleRFromZip.ps1 first to extract the StifleR zip."
}

$ClientMSI = Get-ChildItem -Path $MSISourceFolder -Filter '*Client*.msi' |
             Sort-Object LastWriteTime -Descending |
             Select-Object -First 1

if (-not $ClientMSI) {
    throw "No StifleR Client MSI found in $MSISourceFolder (pattern: *Client*.msi)"
}

Write-Host "Found MSI: $($ClientMSI.Name)" -ForegroundColor Green

$MSIVersion = Get-MSIProductVersion -MSIPath $ClientMSI.FullName
if ([string]::IsNullOrWhiteSpace($MSIVersion)) {
    throw "Could not determine product version from MSI: $($ClientMSI.FullName)"
}
Write-Host "MSI Product Version: $MSIVersion" -ForegroundColor Green
#EndRegion

#Region Get DeployR CI and compare versions
Write-Host "`nLooking for DeployR Content Item: '$StifleRAppName'" -ForegroundColor Cyan

$AllApps    = Get-DeployRApplication
$StifleRApp = $AllApps | Where-Object { $_.Name -eq $StifleRAppName }

if (-not $StifleRApp) {
    throw "DeployR Content Item '$StifleRAppName' not found. Verify the app name exists in DeployR."
}

# Get version 1 — the lowest versionNo
$VersionV1 = $StifleRApp.versions | Sort-Object versionNo | Select-Object -First 1

if (-not $VersionV1) {
    throw "No versions found for DeployR Content Item '$StifleRAppName'."
}

$CIVersion = $VersionV1.description
Write-Host "DeployR CI Version 1 Description: $CIVersion" -ForegroundColor Green

try {
    $versionMSI = [version]$MSIVersion
    $versionCI  = [version]$CIVersion
}
catch {
    throw "Version comparison failed. MSI='$MSIVersion'  CI='$CIVersion'. Ensure both are standard version strings (e.g. 3.1.2.456)."
}

if ($versionMSI -le $versionCI) {
    Write-Host "`nMSI version ($MSIVersion) is not newer than CI version ($CIVersion). No update needed." -ForegroundColor Yellow
    exit 0
}

Write-Host "`nMSI ($MSIVersion) is newer than CI ($CIVersion). Proceeding with update..." -ForegroundColor Green
#EndRegion

#Region Copy new MSI to DeployR source folder
Write-Host "`nCopying new MSI to DeployR source folder: $DeployRDestFolder" -ForegroundColor Cyan

if (-not (Test-Path $DeployRDestFolder)) {
    New-Item -ItemType Directory -Path $DeployRDestFolder -Force | Out-Null
    Write-Host "Created destination folder: $DeployRDestFolder" -ForegroundColor Green
}

# Remove any existing MSI files in the destination folder before copying
$ExistingMSIs = Get-ChildItem -Path $DeployRDestFolder -Filter '*.msi'
foreach ($existing in $ExistingMSIs) {
    Write-Host "Removing existing MSI: $($existing.Name)" -ForegroundColor Yellow
    Remove-Item -Path $existing.FullName -Force
}

Copy-Item -Path $ClientMSI.FullName -Destination $DeployRDestFolder -Force
Write-Host "Copied: $($ClientMSI.Name) -> $DeployRDestFolder" -ForegroundColor Green
#EndRegion

#Region Update DeployR CI — overwrite version 1
Write-Host "`nUpdating DeployR CI '$StifleRAppName' (version $($VersionV1.versionNo)) with new content..." -ForegroundColor Cyan

# Preserve the existing install command — do not modify it
$ExistingInstallCommand = $VersionV1.installationCommandLine
Write-Host "Existing install command: $ExistingInstallCommand" -ForegroundColor Gray

# Update only the version description in metadata; install command is left unchanged
$VersionV1.description = $MSIVersion
$VersionV1 | Set-DeployRMetadata -Type ContentItemVersion

# Upload the new MSI content, replacing what was previously in version 1
Update-DeployRContentItemContent -ContentId $VersionV1.contentItemId -ContentVersion $VersionV1.versionNo -SourceFolder $DeployRDestFolder

Write-Host "`nSuccess! DeployR CI '$StifleRAppName' has been updated to version $MSIVersion." -ForegroundColor Green
#EndRegion
