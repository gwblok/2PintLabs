
#Connect to DeployR.Utility Module if available and gaather FQDN
Write-Host "================================" -ForegroundColor Green
Write-Host "Starting DeployR Install & Configuration Script" -ForegroundColor Green
try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    Write-Warning "DeployR.Utility module not found. Environment variables will be set in the standard environment."
}

if (Get-Module -name "DeployR.Utility"){
    write-Host "Using DeployR.Utility Module to get FQDN" -ForegroundColor Green
    $FQDN = ${TSEnv:FormFQDN}
    $ContentLocation = ${TSEnv:CONTENT-CONTENT}
    write-Host "FQDN = $(${TSEnv:FormFQDN})" -ForegroundColor Green
}
else{
    Write-Host "Using Test Values for FQDN" -ForegroundColor Yellow
    $FQDN = "DeployR.2PintLabs.com"
    write-Host "FQDN = $FQDN" -ForegroundColor Yellow
    $ContentLocation = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
}

#region Functions
Function Get-FQDNFrom2PXEConfig {
    param (
        [string]$configFilePath = "C:\Program Files\2Pint Software\2PXE\2Pint.2PXE.Service.exe.config"
    )

    if (Test-Path $configFilePath) {
        [xml]$configXml = Get-Content $configFilePath
        $appSettings = $configXml.configuration.appSettings
        $fqdnSetting = $appSettings.add | Where-Object { $_.key -eq "ExternalFQDNOverride" }
        if ($fqdnSetting) {
            return $fqdnSetting.value
        } else {
            Write-Warning "ExternalFQDNOverride key not found in appSettings section."
            return $null
        }
    } else {
        Write-Warning "Configuration file not found at $configFilePath."
        return $null
    }
}

Function Get-FQDNFromCertSAN {
    #Loop Thought Certs in "MY" and get the SAN
    $certs = Get-ChildItem -Path Cert:\LocalMachine\My
    foreach ($cert in $certs) {
        $DNSName = $cert.DnsNameList.Unicode
        if ($DNSName) {
            return $DNSName
        }
    }
    return $null
}


function Set-DeployRServerConfiguration  {
    [CmdletBinding()]
    param (
        [string]$fqdn = $null
    )

<#
.SYNOPSIS
    PowerShell script to automate the basic configuration of DeployR after the install
.DESCRIPTION
    This script will check the 2PXE self-signed certificates for the FQDN name of the system and will grab the thumbprint
    It will update the required values (thumbprint, connection string, client URL, StifleR Server API URL) and any optional values (content location).
    It verifies the import, and handles common errors.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 23, 2025
    Version: 25.07.23
    Requires: Administrative privileges, 64-bit Windows
#>

# Ensure the script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

# Example: Construct FQDN dynamically using computer name and domain suffix - useful when system is not domain joined
if (!$fqdn) {
    $fqdn = Get-FQDNFrom2PXEConfig
}
if (!$fqdn) {
    $fqdn = Get-FQDNFromCertSAN
}
if ($fqdn) {
    Write-Host "Using FQDN : $fqdn"
    $domain = ($fqdn.Split(".") | Select-Object -Skip 1) -Join "."   
} else {
    Write-Host "No FQDN found"
}
$match = $false

# Required Settings
$ConnectionString = "Server=.\SQLEXPRESS;Database=DeployR;Trusted_Connection=True;MultipleActiveResultSets=true;TrustServerCertificate=True"
$ClientURL = "https://$($fqdn):7281"
$JoinInfrastructure = "True"
$StifleRServerApiUrl = "https://$($fqdn):9000"

# Optional Settings
# Uncomment and enter values
#$ContentLocation = "D:\DeployR"

# Define registry path
$regPath = "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"

try {
    # Open the Local Machine's Personal certificate store
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        [System.Security.Cryptography.X509Certificates.StoreName]::My,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)

    # Find certificates where the issuer contains "2PintSoftware.com"
    $certificates = $store.Certificates | Where-Object { $_.Issuer -like "*2PintSoftware.com*" }

    if (-not $certificates) {
        Write-Host "No certificates found issued by 2PintSoftware.com in the Local Machine Personal store."
        $store.Close()
        exit 0
    }

    # Iterate through matching certificates
    foreach ($cert in $certificates) {
        Write-Host "---------------------------------------------"
        Write-Host "Certificate Found:"
        Write-Host "Subject: $($cert.Subject)"
        Write-Host "Issuer: $($cert.Issuer)"
        Write-Host "Thumbprint: $($cert.Thumbprint)"
        Write-Host "Valid From: $($cert.NotBefore)"
        Write-Host "Valid Until: $($cert.NotAfter)"

        # Check for Subject Alternative Name extension
        $sanExtension = $cert.Extensions | Where-Object { $_.Oid.FriendlyName -eq "Subject Alternative Name" }

        if ($sanExtension) {
            Write-Host "Subject Alternative Names (SANs):"
            # Parse the SAN extension
            $sanRawData = $sanExtension.Format($true)
            # Split the SAN data into lines and look for DNS names
            $sanEntries = $sanRawData -split "`n" | Where-Object { $_ -match "DNS Name=" }
            
            if ($sanEntries) {
                foreach ($entry in $sanEntries) {
                    # Extract the FQDN from the DNS Name entry
                    $SANfqdn = $entry -replace "DNS Name=", "" -replace "\s", ""
                    $Thumbprint = $cert.Thumbprint
                    Write-Host "  - FQDN: $SANfqdn"
                    Write-Host "  - Thumbprint: $Thumbprint"
                    if ($SANfqdn -eq $fqdn) {
                        $match = $true
                        $Thumbprint = $cert.Thumbprint
                    }
                }
            } else {
                Write-Host "  No DNS Names found in SAN."
            }
        } else {
            Write-Host "No Subject Alternative Name extension found."
        }
        Write-Host "---------------------------------------------"
    }

    # Close the store
    $store.Close()
}
catch {
    Write-Error "An error occurred: $_"
    if ($store) { $store.Close() }
    exit 1
}

#Stop the DeployR Service
try {
    # Check if the DeployR service exists
    $service = Get-Service -Name "DeployRService" -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "The DeployR service was not found on this computer."
        exit 0
    }

    # Check the current status of the service
    Write-Host "Current status of DeployR service: $($service.Status)"

    # Stop the service if it is running
    if ($service.Status -eq 'Running') {
        Write-Host "Stopping the DeployR service..."
        Stop-Service -Name "DeployRService" -Force -ErrorAction Stop
        Write-Host "Service stop command issued. Waiting for service to stop..."

        # Wait for the service to stop (up to 30 seconds)
        $service.WaitForStatus('Stopped', '00:00:30')

        # Verify the service status
        $service.Refresh()
        if ($service.Status -eq 'Stopped') {
            Write-Host "Verification: DeployR service is now stopped."
        } else {
            Write-Warning "Verification: DeployR service is still in state: $($service.Status)"
        }
    } else {
        Write-Host "The DeployR service is already stopped or in state: $($service.Status)"
    }
}
catch {
    Write-Error "An error occurred while attempting to stop the DeployR service: $_"
    exit 1
}

# Create registry key if it doesn't exist
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

# Set registry values
Set-ItemProperty -Path $regPath -Name "CertificateThumbprint" -Value "$Thumbprint" -Type String
Set-ItemProperty -Path $regPath -Name "ConnectionString" -Value "$ConnectionString" -Type String
Set-ItemProperty -Path $regPath -Name "ClientURL" -Value "$ClientURL" -Type String
Set-ItemProperty -Path $regPath -Name "JoinInfrastructure" -Value "$JoinInfrastructure" -Type String
Set-ItemProperty -Path $regPath -Name "StifleRServerApiUrl" -Value "$StifleRServerApiUrl" -Type String
Set-ItemProperty -Path $regPath -Name "BypassAuthentication" -Value "True" -Type String
Set-ItemProperty -Path $regPath -Name "BypassLocalAuthentication" -Value "True" -Type String
Set-ItemProperty -Path $regPath -Name "ClientPasscode" -Value "P@ssw0rd" -Type String


# Set optional registry values
if ($ContentLocation) {
    Set-ItemProperty -Path $regPath -Name "ContentLocation" -Value "$ContentLocation" -Type String
}

Write-Host "Registry entries created successfully."

# Start the DeployR Service
try {
    # Check if the DeployR service exists
    $service = Get-Service -Name "DeployRService" -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "The DeployR service was not found on this computer."
        exit 0
    }

    # Check the current status of the service
    Write-Host "Current status of DeployR service: $($service.Status)"

    # Start the service if it is not running
    if ($service.Status -ne 'Running') {
        Write-Host "Starting the DeployR service..."
        Start-Service -Name "DeployRService" -ErrorAction Stop
        Write-Host "Service start command issued. Waiting for service to start..."

        # Wait for the service to start (up to 30 seconds)
        $service.WaitForStatus('Running', '00:00:30')

        # Verify the service status
        $service.Refresh()
        if ($service.Status -eq 'Running') {
            Write-Host "Verification: DeployR service is now running."
        } else {
            Write-Warning "Verification: DeployR service is still in state: $($service.Status)"
        }
    } else {
        Write-Host "The DeployR service is already running."
    }
}
catch {
    Write-Error "An error occurred while attempting to start the DeployR service: $_"
    exit 1
}

Write-Host "Function Set-DeployRServerConfiguration completed."

}
#endregion Functions

#$WorkingDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

$MSIFiles = Get-ChildItem -Path $ContentLocation -Filter *.msi

$DeployR = $MSIFiles | Where-Object { $_.Name -like "*DeployR*.msi" } | Select-Object -First 1

Write-Host "Installing DeployR from $($DeployR.FullName)" -ForegroundColor Green
$DeployRInstall = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($DeployR.FullName)`" /qb!" -Wait -PassThru -NoNewWindow
Write-Host "DeployR installation completed with exit code $($DeployRInstall.ExitCode)" -ForegroundColor Green


Set-DeployRServerConfiguration -fqdn $fqdn