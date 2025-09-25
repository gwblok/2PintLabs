Function Create-FQDN2PXECert {
    param(
        [string]$domain = $null,
        [string]$fqdn = $null
    )

<#
.SYNOPSIS
    PowerShell script to reset certificates and a create a FQDN self-signed certificate
.DESCRIPTION
    This script will check the 2PXE self-signed certificates for the FQDN name of the system and will delete them
    It will then stop the 2PXE service, remove the 2PXE self-signed certificate files from ProgramData, edit the 2PXE config file,
    and then start the 2PXE service to generate a new FQDN self-signed certificate
    It verifies the import, and handles common errors.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 20, 2025
    Version: 25.07.20
    Requires: Administrative privileges, 64-bit Windows
#>

# Specify the new ExternalFQDNOverride value (e.g., dynamically constructed or static)
# Example: Construct FQDN dynamically using computer name and domain suffix - useful when system is not domain joined
if (!$domain) {
    $domain = [string](Get-DnsClient | Select-Object -ExpandProperty ConnectionSpecificSuffix)
}

if ($($domain.Trim()) -eq ""){
    Write-Host "No domain suffix found. Please provide a domain name."
    #prompt user for domain name
    $domain = Read-Host "Enter the domain name to use for FQDN (e.g., example.com)"
}
Write-Host "Using Domain: $domain"
if (!$fqdn) {
    $fqdn = "$($env:COMPUTERNAME.Trim()).$($domain.Trim())"
}
Write-Host "Using FQDN: $fqdn"

$newExternalFQDN = $fqdn  # Or set a static value, e.g., "2PINT.corp.viamonstra.com"
$match = $false
$delete = $true

# Ensure the script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

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
                    Write-Host "  - FQDN: $SANfqdn"
                    if ($SANfqdn -eq $fqdn) {$match = $true}
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

Write-Host "SAN FQDN equals system FQDN: $match"

if ($match -eq $false) {

    try {
    # Open the Local Machine's Personal certificate store
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        [System.Security.Cryptography.X509Certificates.StoreName]::My,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)

    # Find certificates where the issuer contains "2PintSoftware.com"
    $certificates = $store.Certificates | Where-Object { $_.Issuer -like "*2PintSoftware.com*" }

    if (-not $certificates) {
        Write-Host "No certificates found issued by 2PintSoftware.com in the Local Machine Personal store."
        $store.Close()
        exit 0
    }

    # Iterate through matching certificates
    $deletedCount = 0
    foreach ($cert in $certificates) {
        Write-Host "---------------------------------------------"
        Write-Host "Certificate Found:"
        Write-Host "Subject: $($cert.Subject)"
        Write-Host "Issuer: $($cert.Issuer)"
        Write-Host "Thumbprint: $($cert.Thumbprint)"
        Write-Host "Valid From: $($cert.NotBefore)"
        Write-Host "Valid Until: $($cert.NotAfter)"

        # Delete certificate if $delete is set to $true
        if ($delete -eq $true) {
            try {
                # Remove the certificate from the store
                $store.Remove($cert)
                Write-Host "Certificate with thumbprint $($cert.Thumbprint) deleted successfully."
                $deletedCount++
            }
            catch {
                Write-Error "Failed to delete certificate with thumbprint $($cert.Thumbprint): $_"
            }
        } else {
            Write-Host "Delete is set to false."
            Write-Host "Skipping deletion of certificate with thumbprint $($cert.Thumbprint)."
        }
        Write-Host "---------------------------------------------"
    }

    # Report summary
    Write-Host "Script completed. $deletedCount certificate(s) deleted."

    # Close the store
    $store.Close()
    }
    catch {
        Write-Error "An error occurred: $_"
        if ($store) { $store.Close() }
        exit 1
    }
}

# Verify no certificates remain
try {
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        [System.Security.Cryptography.X509Certificates.StoreName]::My,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
    $remainingCerts = $store.Certificates | Where-Object { $_.Issuer -like "*2PintSoftware.com*" }
    $store.Close()

    if (-not $remainingCerts) {
        Write-Host "Verification: No certificates issued by 2PintSoftware.com remain in the Personal store."
    } else {
        Write-Warning "Verification: $($remainingCerts.Count) certificate(s) issued by 2PintSoftware.com still remain in the Personal store."
    }
}
catch {
    Write-Error "Verification failed: $_"
}

# Clean up old 2PXE certificate files and generate a FQDL self-signed certificate
if ($match -eq $false) {

    #Stop the 2PXE Service
    try {
        # Check if the 2PXE service exists
        $service = Get-Service -Name "2PXE" -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Host "The 2PXE service was not found on this computer."
            exit 0
        }

        # Check the current status of the service
        Write-Host "Current status of 2PXE service: $($service.Status)"

        # Stop the service if it is running
        if ($service.Status -eq 'Running') {
            Write-Host "Stopping the 2PXE service..."
            Stop-Service -Name "2PXE" -Force -ErrorAction Stop
            Write-Host "Service stop command issued. Waiting for service to stop..."

            # Wait for the service to stop (up to 30 seconds)
            $service.WaitForStatus('Stopped', '00:00:30')

            # Verify the service status
            $service.Refresh()
            if ($service.Status -eq 'Stopped') {
                Write-Host "Verification: 2PXE service is now stopped."
            } else {
                Write-Warning "Verification: 2PXE service is still in state: $($service.Status)"
            }
        } else {
            Write-Host "The 2PXE service is already stopped or in state: $($service.Status)"
        }
    }
    catch {
        Write-Error "An error occurred while attempting to stop the 2PXE service: $_"
        exit 1
    }

    # Clean up the 2PXE ProgramData certificates
    $targetDir = "C:\ProgramData\2Pint Software\2PXE\Certificates"

    try {
        # Check if the directory exists
        if (-not (Test-Path -Path $targetDir)) {
            Write-Host "Directory not found: $targetDir"
            exit 0
        }

        # Get the directory contents
        $items = Get-ChildItem -Path $targetDir -Force
        if (-not $items) {
            Write-Host "No files or subdirectories found in: $targetDir"
            exit 0
        }

        # Display items to be deleted for confirmation
        Write-Host "The following items will be deleted from: $targetDir"
        foreach ($item in $items) {
            Write-Host "  - $($item.FullName)"
        }

        # Delete all contents
        Write-Host "Deleting contents of: $targetDir"
        foreach ($item in $items) {
            try {
                if ($item.PSIsContainer) {
                    # Remove directory and its contents recursively
                    Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                    Write-Host "Deleted directory: $($item.FullName)"
                } else {
                    # Remove file
                    Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                    Write-Host "Deleted file: $($item.FullName)"
                }
            }
            catch {
                Write-Warning "Failed to delete item: $($item.FullName). Error: $_"
            }
        }

        # Verify deletion
        $remainingItems = Get-ChildItem -Path $targetDir -Force
        if (-not $remainingItems) {
            Write-Host "Verification: All contents in $targetDir have been deleted."
        } else {
            Write-Warning "Verification: Some items remain in $targetDir."
            foreach ($item in $remainingItems) {
                Write-Warning "  - $($item.FullName)"
            }
        }
    }
    catch {
        Write-Error "An error occurred while attempting to delete contents of $targetDir : $_"
        exit 1
    }

    # Default path to the 2PXE configuration file
    $configFilePath = "C:\Program Files\2Pint Software\2PXE\2Pint.2PXE.Service.exe.config"  # Update with the actual file path

    # Function to create a backup of the configuration file
    function Backup-ConfigFile {
        param (
            [string]$FilePath
        )
        try {
            $backupPath = "$FilePath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Copy-Item -Path $FilePath -Destination $backupPath -Force
            Write-Host "Backup created at: $backupPath"
        }
        catch {
            Write-Error "Failed to create backup: $_"
            exit 1
        }
    }

    try {
        # Check if the configuration file exists
        if (-not (Test-Path -Path $configFilePath)) {
            Write-Error "Configuration file not found at: $configFilePath"
            exit 1
        }

        # Create a backup of the configuration file
        Backup-ConfigFile -FilePath $configFilePath

        # Load the XML configuration file
        [xml]$xml = Get-Content -Path $configFilePath -Raw

        # Locate the ExternalFQDNOverride key in appSettings
        $appSettings = $xml.configuration.appSettings
        $fqdnSetting = $appSettings.add | Where-Object { $_.key -eq "ExternalFQDNOverride" }

        if (-not $fqdnSetting) {
            Write-Error "ExternalFQDNOverride key not found in appSettings section."
            exit 1
        }

        # Update the value
        $oldValue = $fqdnSetting.value
        $fqdnSetting.value = $newExternalFQDN
        Write-Host "Updated ExternalFQDNOverride from '$oldValue' to '$newExternalFQDN'"

        # Save the modified XML back to the file
        $xml.Save($configFilePath)
        Write-Host "Configuration file updated successfully: $configFilePath"

        # Verify the change
        [xml]$updatedXml = Get-Content -Path $configFilePath -Raw
        $updatedValue = ($updatedXml.configuration.appSettings.add | Where-Object { $_.key -eq "ExternalFQDNOverride" }).value
        if ($updatedValue -eq $newExternalFQDN) {
            Write-Host "Verification: ExternalFQDNOverride is correctly set to '$updatedValue'"
        } else {
            Write-Warning "Verification: ExternalFQDNOverride is set to '$updatedValue', which does not match the intended value '$newExternalFQDN'"
        }
    }
    catch {
        Write-Error "An error occurred: $_"
        exit 1
    }

    # Start the 2PXE Service
    try {
        # Check if the 2PXE service exists
        $service = Get-Service -Name "2PXE" -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Host "The 2PXE service was not found on this computer."
            exit 0
        }

        # Check the current status of the service
        Write-Host "Current status of 2PXE service: $($service.Status)"

        # Start the service if it is not running
        if ($service.Status -ne 'Running') {
            Write-Host "Starting the 2PXE service..."
            Start-Service -Name "2PXE" -ErrorAction Stop
            Write-Host "Service start command issued. Waiting for service to start..."

            # Wait for the service to start (up to 30 seconds)
            $service.WaitForStatus('Running', '00:00:30')

            # Verify the service status
            $service.Refresh()
            if ($service.Status -eq 'Running') {
                Write-Host "Verification: 2PXE service is now running."
            } else {
                Write-Warning "Verification: 2PXE service is still in state: $($service.Status)"
            }
        } else {
            Write-Host "The 2PXE service is already running."
        }
    }
    catch {
        Write-Error "An error occurred while attempting to start the 2PXE service: $_"
        exit 1
    }

}

Write-Host "Create-FQDN2PXECert Script completed."
}