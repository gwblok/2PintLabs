

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

function Install-VSCodePowerShellExtension {
    # PowerShell script to install the PowerShell extension for VS Code system-wide
# Run as Administrator

# Define paths
$sharedExtensionsDir = "C:\Program Files\Microsoft VS Code\resources\app\extensions"
$tempExtensionsDir = "$env:USERPROFILE\.vscode\extensions"
$extensionId = "ms-vscode.powershell"

# Ensure the shared extensions directory exists
New-Item -ItemType Directory -Force -Path $sharedExtensionsDir -ErrorAction Stop | Out-Null

# Install the PowerShell extension to the current user's profile temporarily
Write-Host "Installing PowerShell extension ($extensionId) to temporary profile..."
if (Test-Path -Path "C:\Program Files\Microsoft VS Code\bin\code.cmd"){
    & "C:\Program Files\Microsoft VS Code\bin\code.cmd" --install-extension $extensionId --extensions-dir $tempExtensionsDir
}
else{
    Write-Host "can't find code.cmd"
}
# Verify installation
if (Test-Path "$tempExtensionsDir\$extensionId*") {
    Write-Host "Extension installed successfully to temporary profile."

    # Copy the extension to the shared directory
    Write-Host "Copying extension to shared directory: $sharedExtensionsDir"
    Copy-Item -Path "$tempExtensionsDir\$extensionId*" -Destination $sharedExtensionsDir -Recurse -Force

    # Set permissions to ensure all users can access
    Write-Host "Setting permissions on shared extensions directory..."
    icacls "$sharedExtensionsDir" /grant "Users:(RX)" /T | Out-Null
    icacls "$sharedExtensionsDir" /grant "Administrators:(F)" /T | Out-Null

    Write-Host "PowerShell extension successfully preloaded for all users."
} else {
    Write-Error "Failed to install PowerShell extension to temporary profile."
    exit 1
}

# Optional: Clean up temporary user extensions
Write-Host "Cleaning up temporary extensions..."
Remove-Item -Path "$tempExtensionsDir\$extensionId*" -Recurse -Force -ErrorAction SilentlyContinue

# Instruct users to launch VS Code with the shared extensions directory (if needed)
Write-Host "To use the shared extensions, launch VS Code with: code --extensions-dir '$sharedExtensionsDir'"
Write-Host "Setup complete. Test by launching VS Code as a new user."
}