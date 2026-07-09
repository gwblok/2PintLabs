<#
.SYNOPSIS
Creates an IntuneWin package for the StifleR Client from the local source folder.

.DESCRIPTION
Finds the StifleR Client MSI already staged in the DeployR source folder
(populated by Update-StifleRClientAppInDeployRCI.ps1), reads its version,
and runs IntuneWinAppUtil.exe to produce a .intunewin file.
Output is written to a version-named subfolder under the IntuneWin output root.

.NOTES
Run as: Administrator
#>

#Region Variables
$SourceFolder      = 'D:\DeployRSources\Applications\2Pint Software\StifleRClient'
$OutputRootFolder  = 'D:\DeployRSources\Applications\2Pint Software\StifleRClientIntuneWin'
$IntuneUtilPath    = 'D:\IntuneWin\AppUtil\Microsoft-Win32-Content-Prep-Tool\IntuneWinAppUtil.exe'
$IntuneUtilURL     = 'https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe'
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
        Write-Warning "COM method failed, falling back to FileVersionInfo: $_"
        return (Get-Item $MSIPath).VersionInfo.ProductVersion
    }
}

#EndRegion

#Region Validate source folder and find MSI
Write-Host "Source folder: $SourceFolder" -ForegroundColor Cyan

if (-not (Test-Path $SourceFolder)) {
    throw "Source folder not found: $SourceFolder`nRun Update-StifleRClientAppInDeployRCI.ps1 first to stage the MSI."
}

$ClientMSI = Get-ChildItem -Path $SourceFolder -Filter '*Client*.msi' |
             Sort-Object LastWriteTime -Descending |
             Select-Object -First 1

if (-not $ClientMSI) {
    # Fallback: any MSI in the folder
    $ClientMSI = Get-ChildItem -Path $SourceFolder -Filter '*.msi' |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1
}

if (-not $ClientMSI) {
    throw "No MSI found in $SourceFolder"
}

Write-Host "MSI: $($ClientMSI.Name)" -ForegroundColor Green

$MSIVersion = Get-MSIProductVersion -MSIPath $ClientMSI.FullName
if ([string]::IsNullOrWhiteSpace($MSIVersion)) {
    throw "Could not determine product version from: $($ClientMSI.FullName)"
}
Write-Host "MSI Version: $MSIVersion" -ForegroundColor Green
#EndRegion

#Region Ensure IntuneWinAppUtil.exe is available
$IntuneUtilDir = Split-Path $IntuneUtilPath -Parent
if (-not (Test-Path $IntuneUtilDir)) {
    New-Item -ItemType Directory -Path $IntuneUtilDir -Force | Out-Null
}
if (-not (Test-Path $IntuneUtilPath)) {
    Write-Host "Downloading IntuneWinAppUtil.exe..." -ForegroundColor Yellow
    Invoke-WebRequest -UseBasicParsing -Uri $IntuneUtilURL -OutFile $IntuneUtilPath
    Write-Host "Downloaded: $IntuneUtilPath" -ForegroundColor Green
}
else {
    Write-Host "IntuneWinAppUtil: $IntuneUtilPath" -ForegroundColor Green
}
#EndRegion

#Region Determine setup entry point (CMD > EXE > MSI)
$SetupFile = Get-ChildItem -Path $SourceFolder -Filter '*.cmd' | Select-Object -First 1
if (-not $SetupFile) {
    $SetupFile = Get-ChildItem -Path $SourceFolder -Filter '*.exe' | Select-Object -First 1
}
if (-not $SetupFile) {
    $SetupFile = $ClientMSI
}
Write-Host "Setup entry point: $($SetupFile.Name)" -ForegroundColor Green
#EndRegion

#Region Create version-named output subfolder
$OutputFolder = Join-Path $OutputRootFolder $MSIVersion
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-Host "Created output folder: $OutputFolder" -ForegroundColor Green
}
else {
    Write-Host "Output folder exists: $OutputFolder" -ForegroundColor Yellow
}
#EndRegion

#Region Run IntuneWinAppUtil
Write-Host "`nCreating IntuneWin package..." -ForegroundColor Cyan
Write-Host "  Source : $SourceFolder" -ForegroundColor Gray
Write-Host "  Setup  : $($SetupFile.Name)" -ForegroundColor Gray
Write-Host "  Output : $OutputFolder" -ForegroundColor Gray

& $IntuneUtilPath -c $SourceFolder -s $SetupFile.FullName -o $OutputFolder -q

$IntuneWinFile = Get-ChildItem -Path $OutputFolder -Filter '*.intunewin' | Select-Object -First 1
if ($IntuneWinFile) {
    Write-Host "`nSuccess! IntuneWin package created:" -ForegroundColor Green
    Write-Host "  $($IntuneWinFile.FullName)" -ForegroundColor Green
    Write-Host "  Version : $MSIVersion" -ForegroundColor Gray
    Write-Host "  Size    : $([math]::Round($IntuneWinFile.Length / 1MB, 2)) MB" -ForegroundColor Gray
}
else {
    Write-Warning "IntuneWinAppUtil completed but no .intunewin file found in $OutputFolder"
}
#EndRegion