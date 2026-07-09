<#
.SYNOPSIS
Updates the StifleR Client App ZIP served via IIS and the companion JSON file.

.DESCRIPTION
Finds the extracted StifleR Client MSI (produced by Update-2PintStifleRFromZip.ps1),
reads its product version, then checks the version stored in the StifleR-ClientApp.json
file on GitHub (D:\GitHub\2PintLabs\GARYTOWN\StifleR-ClientApp.json).
If the MSI is newer, it:
  1. Compresses the MSI into StifleR-ClientApp.zip at the IIS web root path.
  2. Updates the matching version entry in the JSON file.

.NOTES
Run as: Administrator (IIS web root write access required)
#>

#Region Variables
$MSISourceFolder = "$env:USERPROFILE\Downloads\StifleR\Extracted"
$IISZipPath      = 'C:\inetpub\wwwroot\3.0\StifleR-ClientApp.zip'
$JSONFilePath    = 'D:\GitHub\2PintLabs\GARYTOWN\StifleR-ClientApp.json'
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

#Region Find StifleR Client MSI
Write-Host "Looking for StifleR Client MSI in: $MSISourceFolder" -ForegroundColor Cyan

if (-not (Test-Path $MSISourceFolder)) {
    throw "StifleR extracted source folder not found: $MSISourceFolder`nRun Update-2PintStifleRFromZip.ps1 first."
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

#Region Read JSON and find matching entry
Write-Host "`nReading JSON: $JSONFilePath" -ForegroundColor Cyan

if (-not (Test-Path $JSONFilePath)) {
    throw "JSON file not found: $JSONFilePath"
}

$JsonContent = Get-Content -Path $JSONFilePath -Raw | ConvertFrom-Json
$MSIMajor    = ([version]$MSIVersion).Major

# Match the entry whose Version shares the same major version as the MSI
$MatchingEntry = $JsonContent | Where-Object { ([version]$_.Version).Major -eq $MSIMajor }

if (-not $MatchingEntry) {
    throw "No JSON entry found with major version $MSIMajor. Entries present: $(($JsonContent | Select-Object -ExpandProperty Version) -join ', ')"
}

$JSONVersion = $MatchingEntry.Version
Write-Host "Matching JSON entry — Version: $JSONVersion  URL: $($MatchingEntry.URL)" -ForegroundColor Green
#EndRegion

#Region Compare versions
try {
    $versionMSI  = [version]$MSIVersion
    $versionJSON = [version]$JSONVersion
}
catch {
    throw "Version comparison failed. MSI='$MSIVersion'  JSON='$JSONVersion'. Ensure both are standard version strings (e.g. 3.1.2.456)."
}

if ($versionMSI -le $versionJSON) {
    Write-Host "`nMSI version ($MSIVersion) is not newer than JSON version ($JSONVersion). No update needed." -ForegroundColor Yellow
    exit 0
}

Write-Host "`nMSI ($MSIVersion) is newer than JSON ($JSONVersion). Proceeding with update..." -ForegroundColor Green
#EndRegion

#Region Update IIS ZIP file
Write-Host "`nUpdating IIS ZIP: $IISZipPath" -ForegroundColor Cyan

$IISDir = Split-Path $IISZipPath -Parent
if (-not (Test-Path $IISDir)) {
    New-Item -ItemType Directory -Path $IISDir -Force | Out-Null
    Write-Host "Created IIS directory: $IISDir" -ForegroundColor Green
}

# Remove existing zip before recreating
if (Test-Path $IISZipPath) {
    Write-Host "Removing existing ZIP: $IISZipPath" -ForegroundColor Yellow
    Remove-Item -Path $IISZipPath -Force
}

# Compress the MSI into the zip (zip contains only the MSI file)
Compress-Archive -Path $ClientMSI.FullName -DestinationPath $IISZipPath -CompressionLevel Optimal
Write-Host "Created ZIP: $IISZipPath  (contains: $($ClientMSI.Name))" -ForegroundColor Green
#EndRegion

#Region Update JSON file
Write-Host "`nUpdating JSON version from $JSONVersion to $MSIVersion..." -ForegroundColor Cyan

$MatchingEntry.Version = $MSIVersion

# ConvertTo-Json depth 3 keeps array structure intact; format matches original
$UpdatedJson = $JsonContent | ConvertTo-Json -Depth 3
Set-Content -Path $JSONFilePath -Value $UpdatedJson -Encoding UTF8

Write-Host "JSON updated: $JSONFilePath" -ForegroundColor Green
#EndRegion

Write-Host "`nDone. StifleR Client App updated to version $MSIVersion." -ForegroundColor Green
Write-Host "  ZIP : $IISZipPath" -ForegroundColor Gray
Write-Host "  JSON: $JSONFilePath" -ForegroundColor Gray
