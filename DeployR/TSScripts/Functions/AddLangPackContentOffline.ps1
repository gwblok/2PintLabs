<#
.SYNOPSIS
Installs en-AU language packages into the offline Windows image.
.DESCRIPTION
Run elevated in a DeployR WinPE task sequence with Windows on S: and CABs
provided by _Content-Content. Uses S:\_2P\Temp for DISM scratch space instead
of the WinPE RAM drive. Requires at least 1 GB free on S: before servicing;
package installation may require additional space. Creates the scratch
directory if needed and does not delete this shared directory or its contents.
.EXAMPLE
.\AddLangPackContentOffline.ps1
.NOTES
Author: Not specified
Created: Not specified
Change History:
2026-11-19 - Added disk-backed DISM scratch space at S:\_2P\Temp.
#>

$WindowsPath = "S:\"
$CabPath     = ${tsenv:_Content-Content}
$ScratchPath = "S:\_2P\Temp"

Write-Host "Installing en-AU language packages"
Write-Host "Windows : $WindowsPath"
Write-Host "CAB Path: $CabPath"
Write-Host "Scratch : $ScratchPath"
Write-Host ""

# Get all en-AU CABs from the script's directory
$CabFiles = Get-ChildItem -Path $CabPath -Filter "*en-au*.cab" -File

if (-not $CabFiles) {
    Write-Error "No en-AU CAB files found in $CabPath"
    exit 1
}

# Install Basic first because the other language features may depend on it
$CabFiles = $CabFiles | Sort-Object {
    if ($_.Name -like "*LanguageFeatures-Basic-en-au*") {
        0
    }
    else {
        1
    }
}

# Avoid WinPE's limited RAM-backed default scratch directory.
try {
    $ScratchDrive = Get-PSDrive -Name S -PSProvider FileSystem -ErrorAction Stop
    if ($ScratchDrive.Free -lt 1GB) {
        throw "At least 1 GB of free space is required on S: for DISM scratch files."
    }
    New-Item -Path $ScratchPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
catch {
    Write-Error "Unable to prepare DISM scratch space: $($_.Exception.Message)"
    exit 1
}

foreach ($Cab in $CabFiles) {

    Write-Host "Installing: $($Cab.Name)" -ForegroundColor Yellow

    $Process = Start-Process `
        -FilePath "dism.exe" `
        -ArgumentList @(
            "/Image:$WindowsPath"
            "/Add-Package"
            "/PackagePath:`"$($Cab.FullName)`""
            "/ScratchDir:`"$ScratchPath`""
            "/NoRestart"
        ) `
        -Wait `
        -PassThru `
        -NoNewWindow

    if ($Process.ExitCode -eq 0) {
        Write-Host "SUCCESS: $($Cab.Name)" -ForegroundColor Green
    }
    elseif ($Process.ExitCode -eq 3010) {
        Write-Host "SUCCESS: $($Cab.Name) - reboot required" -ForegroundColor Green
    }
    else {
        Write-Error "FAILED: $($Cab.Name) - DISM exit code $($Process.ExitCode)"
        exit $Process.ExitCode
    }

    Write-Host ""
}

Write-Host "All en-AU packages installed successfully." -ForegroundColor Green
exit 0