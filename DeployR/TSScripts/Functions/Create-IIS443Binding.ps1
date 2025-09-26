function Create-IIS443Binding {
        param(
        [string]$domain = $null,
        [string]$fqdn = $null
    )
<#
.SYNOPSIS
    PowerShell script to add an HTTPS site binding in IIS and assign the FQDN certificate issued by 2PintSoftware.com 
.DESCRIPTION
    This script creates the HTTPS binding on port 443 using the 2Pint Software FQDN self-signed certificate
    Make sure 2PXE is installed first and a FQDN cert has been generated.
    It verifies the import, and handles common errors.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 20, 2025
    Version: 25.07.20
    Requires: Administrative privileges, 64-bit Windows
#>

# Ensure the script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

# Parameters (update these as needed)
# This will use the connection specific suffix for the fqdn - useful when system is not domain joined
if (!$domain) {
    $domain = [string](Get-DnsClient | Select-Object -ExpandProperty ConnectionSpecificSuffix)
}
if ($($domain.Trim()) -eq ""){
    Write-Host "No domain suffix found. Please provide a domain name."
    
    $configFilePath = "C:\Program Files\2Pint Software\2PXE\2Pint.2PXE.Service.exe.config"  # Update with the actual file path
    if (Test-Path $configFilePath) {
        [xml]$configXml = Get-Content $configFilePath
        $appSettings = $configXml.configuration.appSettings
        $fqdnSetting = $appSettings.add | Where-Object { $_.key -eq "ExternalFQDNOverride" }
        $fqdn = $fqdnSetting.value
        $domain = ($fqdn.Split(".") | Select-Object -Skip 1) -Join "."
        if (-not $fqdnSetting) {
            Write-Host "ExternalFQDNOverride key not found in appSettings section."
            
        }
    } else {
        Write-Warning "Configuration file not found at $configFilePath. Assuming not part of a domain."
    }
    if (-not $domain) {
        Write-Host "Domain name could not be determined from 2PXE config. Please provide a domain name."
        $domain = Read-Host "Enter the domain name to use for FQDN (e.g., example.com)"
    }
}
Write-Host "Using Domain: $domain"
if (!$fqdn) {
    $fqdn = "$($env:COMPUTERNAME.Trim()).$($domain.Trim())"
}
Write-Host "Using FQDN: $fqdn"
Write-Host "Using FQDN: $fqdn"
$siteName = "Default Web Site"  # Name of the IIS website to add the binding to
$hostName = $fqdn  # FQDN for the HTTPS binding
$port = 443  # Standard HTTPS port
$protocol = "https"
$issuerMatch = "*2PintSoftware.com*"  # Pattern to match the certificate issuer

try {
    # Import the WebAdministration module
    Import-Module WebAdministration -ErrorAction Stop

    # Check if the website exists
    $site = Get-Website -Name $siteName -ErrorAction SilentlyContinue
    if (-not $site) {
        Write-Error "Website '$siteName' not found in IIS."
        exit 1
    }

    # Check if the HTTPS binding already exists
    $existingBinding = Get-WebBinding -Name $siteName | Where-Object { $_.protocol -eq $protocol -and ($_.bindingInformation -split ':')[1] -eq $port -and $_.bindingInformation -eq "*:$($port):$($hostName)" }
    if ($existingBinding) {
        Write-Warning "HTTPS binding for '$hostName' on port $port already exists for '$siteName'."
        exit 0
    }

    # Find the certificate in the Local Machine Personal store issued by 2PintSoftware.com
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        [System.Security.Cryptography.X509Certificates.StoreName]::My,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
    $certificates = $store.Certificates | Where-Object { $_.Issuer -like $issuerMatch }
    $store.Close()

    if (-not $certificates) {
        Write-Error "No certificates found issued by 2PintSoftware.com in the Local Machine Personal store."
        exit 1
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
                    if ($SANfqdn -eq $fqdn) {
                        $thumbprint = $cert.Thumbprint
                        Write-Host "  - Thumbprint: $thumbprint"
                    }
                    break
                }
            } else {
                Write-Host "  No DNS Names found in SAN."
            }
        } else {
            Write-Host "No Subject Alternative Name extension found."
        }
        Write-Host "---------------------------------------------"
    }

    # Add the HTTPS binding
    New-WebBinding -Name $siteName -IPAddress "*" -Port $port -HostHeader $hostName -Protocol $protocol -ErrorAction Stop
    Write-Host "Added HTTPS binding for '$hostName' on port $port to '$siteName'."

    # Assign the certificate to the binding using netsh
    $appId = [Guid]::NewGuid().ToString("B")  # Generate a unique AppID
    $bindingInfo = "0.0.0.0:$port"

    # Construct the netsh command arguments
    $netshArgs = "http add sslcert ipport=$bindingInfo certhash=$thumbprint appid=$appId"

    # Execute netsh using Start-Process to avoid parsing issues
    Write-Host "Executing netsh command: netsh $netshArgs"
    $process = Start-Process -FilePath "netsh" -ArgumentList $netshArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput "netsh_output.txt" -RedirectStandardError "netsh_error.txt"
    
    # Read output and error files
    $netshOutput = Get-Content -Path "netsh_output.txt" -Raw
    $netshError = Get-Content -Path "netsh_error.txt" -Raw
    Remove-Item -Path "netsh_output.txt", "netsh_error.txt" -ErrorAction SilentlyContinue

    if ($process.ExitCode -eq 0) {
        Write-Host "Assigned certificate with thumbprint $thumbprint to the HTTPS binding."
        if ($netshOutput) { Write-Host "Netsh Output: $netshOutput" }
    } else {
        Write-Error "Failed to assign certificate to the HTTPS binding. Exit Code: $($process.ExitCode)"
        if ($netshOutput) { Write-Error "Netsh Output: $netshOutput" }
        if ($netshError) { Write-Error "Netsh Error: $netshError" }
        exit 1
    }

    # Verify the binding with explicit port extraction
    $updatedBinding = Get-WebBinding -Name $siteName | Where-Object { $_.protocol -eq $protocol -and ($_.bindingInformation -split ':')[1] -eq $port -and $_.bindingInformation -eq "*:$($port):$($hostName)" }
    if ($updatedBinding) {
        Write-Host "Verification: HTTPS binding for '$hostName' on port $port successfully added."
        # Display binding details with extracted port
        $bindingDetails = $updatedBinding | Select-Object protocol, bindingInformation, @{
            Name = 'Port';
            Expression = { ($_.bindingInformation -split ':')[1] }
        }, certificateHash, certificateStoreName
        Write-Host "Binding Details:"
        $bindingDetails | Format-Table -AutoSize
        # Check certificate binding
        $sslBinding = netsh http show sslcert ipport=$bindingInfo | Select-String $thumbprint
        if ($sslBinding) {
            Write-Host "Verification: Certificate with thumbprint $thumbprint is correctly assigned to the binding."
        } else {
            Write-Warning "Verification: Certificate binding may not have been applied correctly."
        }
    } else {
        Write-Warning "Verification: HTTPS binding for '$hostName' on port $port was not found."
    }
}
catch {
    Write-Error "An error occurred: $_"
    if ($store) { $store.Close() }
    exit 1
}

Write-Host "Script completed."
}   
