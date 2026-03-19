
Import-Module DeployR.Utility
[string]$OfflineDrive  = ${TSEnv:OSDTARGETSYSTEMDRIVE} 


# Source = current script/working directory (where the .cab files live)
$SourcePath = ${TSEnv:_CONTENT-CONTENT} 

# Normalize offline Windows path
$letter    = $OfflineDrive -replace '[:\\]',''
$MountPath = "${letter}:\Windows"

Write-Host "Enable .NET Framework 3.5 (NetFx3) - Offline Servicing" -ForegroundColor Cyan
Write-Host "  Target offline Windows : $MountPath"
Write-Host "  Source folder (current) : $SourcePath"
Write-Host ""

# Quick existence checks
if (-not (Test-Path "$MountPath\System32\config\SYSTEM")) {
    Write-Warning "No valid Windows installation found at $MountPath"
    Write-Warning "Common WinPE letters: C:, D:, E: → use -OfflineDrive parameter"
    Write-Host "Example: .\Enable-NetFx3-Offline-CurrentDir.ps1 -OfflineDrive D:" -ForegroundColor Yellow
    exit 1
}

# Check for at least one expected .cab file in current directory
$cabFound = Get-ChildItem -Path $SourcePath -Filter "microsoft-windows-netfx3-ondemand*.cab" -File -ErrorAction SilentlyContinue
if (-not $cabFound) {
    Write-Warning "No NetFx3 source files (*.cab) found in current folder: $SourcePath"
    Write-Warning "This script expects to be run from the folder containing the NetFx3 .cab files directly"
    Write-Warning "(usually copied from \sources\sxs on install media)"
    exit 1
}

Write-Host "`nEnabling NetFx3 on offline image..." -ForegroundColor Yellow

try {
    $params = @{
        Path        = $MountPath
        FeatureName = "NetFx3"
        All         = $true
        Source      = $SourcePath          # ← current folder
        LimitAccess = $true
        NoRestart   = $true
        ErrorAction = "Stop"
    }

    Write-Host "Command being executed:" -ForegroundColor DarkGray
    Write-Host "Enable-WindowsOptionalFeature -Path '$MountPath' -FeatureName 'NetFx3' -All -Source '$SourcePath' -LimitAccess -NoRestart" -ForegroundColor DarkGray

    Enable-WindowsOptionalFeature @params | Out-Default

    Write-Host "`n.NET Framework 3.5 enabled successfully!" -ForegroundColor Green
}
catch {
    $errMsg = $_.Exception.Message

    if ($errMsg -match "already installed|0x800f0f08") {
        Write-Host "`nNetFx3 is already enabled in the offline image." -ForegroundColor Cyan
    }
    elseif ($errMsg -match "source files could not be found|0x800f081f") {
        Write-Warning "Source files not recognized in current folder."
        Write-Warning "Make sure these files exist directly here:"
        Write-Warning "  - microsoft-windows-netfx3-ondemand-package*.cab"
        Write-Warning "  (must match the OS build/edition/architecture)"
    }
    elseif ($errMsg -match "0x800f0954") {
        Write-Warning "Error 0x800f0954 - usually source mismatch or corrupted cab"
        Write-Warning "Verify files came from matching Windows ISO (same build)"
    }
    else {
        Write-Warning "Failed: $errMsg"
    }
}

Write-Host "`nDone." -ForegroundColor DarkCyan
Write-Host "Tip: If it fails with source error, double-check drive letter and that .cab files are not in a subfolder." -ForegroundColor DarkYellow
