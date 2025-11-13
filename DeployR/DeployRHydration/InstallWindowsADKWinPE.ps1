<#
.SYNOPSIS
    Downloads and installs the Windows PE add-on for the Windows ADK 10.1.26100.2454 (December 2024).
.DESCRIPTION
    This script automates the download, silent installation, and verification of the Windows PE add-on for the Windows ADK.
    It uses registry-based detection with the correct uninstall key and logs the process for troubleshooting.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 19, 2025
    Version: 25.07.19
    Requires: Administrative privileges, 64-bit Windows (10/11, Server 2016+), Windows ADK 10.1.26100.2454, internet access
    Source: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
#>

# Configuration
$DownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2289981"  # Corrected Microsoft URL for Windows PE add-on 10.1.26100.2454
$InstallerPath = "$env:TEMP\adkwinpesetup.exe"  # Temporary location for the installer
$LogFile = "$env:TEMP\WinPE_Install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

# Function to verify Windows ADK is installed
function Test-ADKInstalled {
    param (
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )

    $RegistryPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
    Write-Log -Message "Checking if Windows ADK is installed..." -LogFile $LogFile

    try {
        if (Test-Path $RegistryPath) {
            $ADKVersion = (Get-ItemProperty -Path $RegistryPath -Name "KitsRoot10" -ErrorAction Stop).KitsRoot10
            if ($ADKVersion -and (Test-Path "$ADKVersion\Assessment and Deployment Kit\Deployment Tools")) {
                Write-Log -Message "Windows ADK found at $ADKVersion." -LogFile $LogFile
                return $true
            } else {
                Write-Log -Message "Windows ADK registry key found, but Deployment Tools not installed." -LogFile $LogFile
                return $false
            }
        } else {
            Write-Log -Message "Windows ADK is not installed (registry key $RegistryPath not found)." -LogFile $LogFile
            return $false
        }
    } catch {
        Write-Log -Message "ERROR: Failed to verify ADK installation. Error: $($_.Exception.Message)" -LogFile $LogFile
        return $false
    }
}

# Function to verify WinPE add-on installation
function Test-WinPEAddOnInstalled {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )

    $RegistryPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{e0f929f8-610d-469c-bfa1-7961a14eb91b}"

    Write-Log -Message "Checking if WinPE add-on is installed via registry at $RegistryPath..." -LogFile $LogFile

    try {
        if (Test-Path $RegistryPath) {
            $WinPEProduct = Get-ItemProperty -Path $RegistryPath -ErrorAction Stop
            $DisplayName = $WinPEProduct.DisplayName
            $DisplayVersion = $WinPEProduct.DisplayVersion
            Write-Log -Message "WinPE add-on found in registry. DisplayName: $DisplayName, Version: $DisplayVersion" -LogFile $LogFile
            
            # Optional: Verify key WinPE files for additional confirmation
            $WinPEPath = "$InstallDir\Assessment and Deployment Kit\Windows Preinstallation Environment"
            $CopyPEPath = "$WinPEPath\copype.cmd"
            if (Test-Path $CopyPEPath) {
                Write-Log -Message "Confirmed WinPE add-on files at $WinPEPath." -LogFile $LogFile
            } else {
                Write-Log -Message "Warning: WinPE add-on registered, but copype.cmd not found at $CopyPEPath." -LogFile $LogFile
            }
            return $true
        } else {
            Write-Log -Message "WinPE add-on not found in registry at $RegistryPath." -LogFile $LogFile
            return $false
        }
    } catch {
        Write-Log -Message "ERROR: Failed to verify WinPE add-on installation via registry. Error: $($_.Exception.Message)" -LogFile $LogFile
        Write-Error "Failed to verify WinPE add-on installation. Error: $($_.Exception.Message)"
        return $false
    }
}

# Start logging
Write-Log -Message "Starting Windows PE add-on for ADK 10.1.26100.2454 installation script." -LogFile $LogFile

# Check for administrative privileges
if (-not (Test-Admin)) {
    Write-Log -Message "ERROR: Script must be run as an administrator." -LogFile $LogFile
    Write-Error "This script requires administrative privileges. Please run PowerShell as an administrator."
    exit 1
}

# Check if Windows ADK is installed
if (-not (Test-ADKInstalled -LogFile $LogFile)) {
    Write-Log -Message "ERROR: Windows ADK (with Deployment Tools) is required but not installed." -LogFile $LogFile
    Write-Error "Windows ADK is required. Please install it with Deployment Tools first."
    exit 1
}

# Check if WinPE add-on is already installed
if (Test-WinPEAddOnInstalled -LogFile $LogFile) {
    Write-Host "Windows PE add-on for ADK is already installed. Exiting."
    Write-Log -Message "Script terminated: WinPE add-on is already installed." -LogFile $LogFile
    exit 0
}

# Download the WinPE add-on installer
Write-Log -Message "Downloading WinPE add-on from $DownloadUrl..." -LogFile $LogFile
try {
    $ProgressPreference = 'SilentlyContinue'  # Suppress progress bar for faster download
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -ErrorAction Stop
    Write-Log -Message "Download successful: $InstallerPath" -LogFile $LogFile
} catch {
    Write-Log -Message "ERROR: Failed to download WinPE add-on installer. Error: $($_.Exception.Message)" -LogFile $LogFile
    Write-Error "Failed to download WinPE add-on installer. Error: $($_.Exception.Message)"
    exit 1
}

# Verify the downloaded file exists
if (-not (Test-Path $InstallerPath)) {
    Write-Log -Message "ERROR: Installer file not found at $InstallerPath." -LogFile $LogFile
    Write-Error "Installer file not found at $InstallerPath."
    exit 1
}

# Install WinPE add-on silently
Write-Log -Message "Installing Windows PE add-on for ADK..." -LogFile $LogFile
try {
    $Arguments = "/quiet /norestart /installpath `"$InstallDir`" /features OptionId.WindowsPreinstallationEnvironment"
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
if (Test-WinPEAddOnInstalled -LogFile $LogFile) {
    Write-Host "Windows PE add-on for ADK installed successfully."
    Write-Log -Message "Verification: WinPE add-on installed successfully." -LogFile $LogFile
} else {
    Write-Log -Message "ERROR: Verification failed. WinPE add-on not detected after installation." -LogFile $LogFile
    Write-Error "Verification failed. WinPE add-on not detected after installation."
    exit 1
}

Write-Log -Message "Script completed successfully." -LogFile $LogFile
Write-Host "Windows PE add-on for ADK installed. Log file: $LogFile"