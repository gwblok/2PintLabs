

<#
Gary Blok - @gwblok - GARYTOWN.COM

.Description
Downloads & Installs VSCode from Cloud Sources
#>
Function Install-VSCode {
    [CmdletBinding()]
    param()
    
    # Define variables
    $downloadUrl = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"
    $installerPath = "$env:TEMP\VSCodeSetup.exe"
    $logPath = "$env:TEMP\VSCodeInstall.log"
    
    try {
        # Attempt download with Start-BitsTransfer
        Write-Host "Attempting to download VS Code installer using BITS..."
        try {
            Start-BitsTransfer -Source $downloadUrl -Destination $installerPath -ErrorAction Stop
        }
        catch {
            Write-Host "BITS download failed, falling back to Invoke-WebRequest..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -ErrorAction Stop
        }
        
        # Install VS Code silently
        Write-Host "Installing VS Code..."
        Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT /NORESTART /MERGETASKS=!runcode /LOG=$logPath" -Wait -ErrorAction Stop
        
        Write-Host "VS Code installed successfully."
    }
    catch {
        Write-Host "Error occurred: $_" -ForegroundColor Red
    }
    finally {
        # Clean up
        if (Test-Path $installerPath) {
            Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
}