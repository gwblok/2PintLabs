<#
.SYNOPSIS
    Downloads and installs the Windows Assessment and Deployment Kit (ADK) with only the Deployment Tools option.
.DESCRIPTION
    This script automates the download, silent installation, and verification of the Windows ADK (version 10.1.26100.2454 for Windows 11) with the Deployment Tools feature.
    It logs the process and handles common errors, suitable for large-scale Windows deployment scenarios.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 19, 2025
    Version: 25.07.19
    Requires: Administrative privileges, 64-bit Windows (10/11, Server 2016+), internet access
    Source: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
#>

# Configuration 
$DownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2289980"  # Official Microsoft URL for Windows ADK 10.1.26100.2454
$InstallerPath = "$env:TEMP\adksetup.exe"  # Temporary location for the installer
$LogFile = "$env:TEMP\ADK_Install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$InstallDir = "C:\Program Files (x86)\Windows Kits\10"  # Default ADK installation directory

# Function to write to log file
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFile -Append
}

# Function to check if the script is running as administrator
function Test-Admin {
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($CurrentUser)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to verify ADK Deployment Tools installation
function Test-ADKDeploymentToolsInstalled {
    param (
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )

    $RegistryPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
    $DeploymentToolsPath = "$InstallDir\Assessment and Deployment Kit\Deployment Tools"

    Write-Log -Message "Checking if ADK Deployment Tools are installed..." -LogFile $LogFile

    try {
        # Check registry for ADK installation
        if (Test-Path $RegistryPath) {
            $ADKVersion = (Get-ItemProperty -Path $RegistryPath -Name "KitsRoot10" -ErrorAction Stop).KitsRoot10
            if ($ADKVersion -and (Test-Path $DeploymentToolsPath)) {
                # Verify key Deployment Tools executables (e.g., DISM, oscdimg)
                $DismPath = "$DeploymentToolsPath\amd64\DISM\dism.exe"
                $OscdimgPath = "$DeploymentToolsPath\amd64\Oscdimg\oscdimg.exe"
                if ((Test-Path $DismPath) -and (Test-Path $OscdimgPath)) {
                    $DismVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($DismPath).FileVersion
                    Write-Log -Message "ADK Deployment Tools installed. DISM version: $DismVersion at $DeploymentToolsPath" -LogFile $LogFile
                    return $true
                } else {
                    Write-Log -Message "ADK Deployment Tools directory found, but key executables (dism.exe or oscdimg.exe) are missing." -LogFile $LogFile
                    return $false
                }
            } else {
                Write-Log -Message "ADK registry key found, but Deployment Tools directory not found at $DeploymentToolsPath." -LogFile $LogFile
                return $false
            }
        } else {
            Write-Log -Message "ADK is not installed (registry key $RegistryPath not found)." -Log elek
            return $false
        }
    } catch {
        Write-Log -Message "ERROR: Failed to verify ADK installation. Error: $($_.Exception.Message)" -LogFile $LogFile
        return $false
    }
}

# Start logging
Write-Log -Message "Starting Windows ADK (Deployment Tools) installation script." -LogFile $LogFile

# Check for administrative privileges
if (-not (Test-Admin)) {
    Write-Log -Message "ERROR: Script must be run as an administrator." -LogFile $LogFile
    Write-Error "This script requires administrative privileges. Please run PowerShell as an administrator."
    exit 1
}

# Check if ADK Deployment Tools are already installed
if (Test-ADKDeploymentToolsInstalled -LogFile $LogFile) {
    Write-Host "Windows ADK Deployment Tools are already installed. Exiting."
    Write-Log -Message "Script terminated: ADK Deployment Tools are already installed." -LogFile $LogFile
    exit 0
}

# Download the ADK installer
Write-Log -Message "Downloading Windows ADK from $DownloadUrl..." -LogFile $LogFile
try {
    $ProgressPreference = 'SilentlyContinue'  # Suppress progress bar for faster download
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -ErrorAction Stop
    Write-Log -Message "Download successful: $InstallerPath" -LogFile $LogFile
} catch {
    Write-Log -Message "ERROR: Failed to download ADK installer. Error: $($_.Exception.Message)" -LogFile $LogFile
    Write-Error "Failed to download Windows ADK installer. Error: $($_.Exception.Message)"
    exit 1
}

# Verify the downloaded file exists
if (-not (Test-Path $InstallerPath)) {
    Write-Log -Message "ERROR: Installer file not found at $InstallerPath." -LogFile $LogFile
    Write-Error "Installer file not found at $InstallerPath."
    exit 1
}

# Install ADK with only Deployment Tools
Write-Log -Message "Installing Windows ADK with Deployment Tools..." -LogFile $LogFile
try {
    $Arguments = "/quiet /norestart /installpath `"$InstallDir`" /features OptionId.DeploymentTools OptionId.ImagingAndConfigurationDesigner"
    $Process = Start-Process -FilePath $InstallerPath -ArgumentList $Arguments -Wait -PassThru -ErrorAction Stop
    Write-Log -Message "Installation exit code: $($Process.ExitCode)" -LogFile $LogFile
    
    if ($Process.ExitCode -eq 0) {
        Write-Log -Message "Installation completed successfully." -LogFile $LogFile
    } elseif ($Process.ExitCode -eq 3010) {
        Write-Log -Message "Installation completed successfully, but a reboot is required." -LogFile $LogFile
        Write-Host "Installation completed successfully, but a reboot is required."
    } else {
        Write-Log -Message "ERROR: Installation failed with exit code $($Process.ExitCode). Check logs in %APPDATA%\Microsoft\Windows Kits\Logs" -LogFile $LogFile
        Write-Error "Installation failed with exit code $($Process.ExitCode). Check logs in %APPDATA%\Microsoft\Windows Kits\Logs"
        exit $Process.ExitCode
    }
} catch {
    Write-Log -Message "ERROR: Installation process failed. Error: $($_.Exception.Message)" -LogFile $LogFile
    Write-Error "Installation process failed. Error: $($_.Exception.Message)"
    exit 1
}

# Verify installation
if (Test-ADKDeploymentToolsInstalled -LogFile $LogFile) {
    Write-Host "Windows ADK Deployment Tools installed successfully."
    Write-Log -Message "Verification: ADK Deployment Tools installed successfully." -LogFile $LogFile
} else {
    Write-Log -Message "ERROR: Verification failed. ADK Deployment Tools not detected after installation." -LogFile $LogFile
    Write-Error "Verification failed. ADK Deployment Tools not detected after installation."
    exit 1
}

Write-Log -Message "Script completed successfully." -LogFile $LogFile
Write-Host "Windows ADK Deployment Tools installed. Log file: $LogFile"