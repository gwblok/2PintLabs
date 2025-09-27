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

function Install-StifleRDashBoard {
    [CmdletBinding()]
    param (
        [string]$msifile,
        [string]$domain = $null,
        [string]$fqdn = $null
    )
    <#
.SYNOPSIS
    PowerShell script to perform an unattended install of StifleR Dashboard 
.DESCRIPTION
    This script automates installing StifleR Dashboard and will determine the FQDN of the server and use
    it for the dashboard configuration. Make sure 2PXE is installed first and a FQDN cert
    has been generated and the IIS 443 bindings have been configured. It will also create the IIS virtual
    directory for the dashboard.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: August 4, 2025
    Version: 25.08.04
    Requires: Administrative privileges, 64-bit Windows
#>

# Set path to MSI file
#$msifile = "$PSScriptRoot\StifleR-Dashboard-x64.msi"
if (-not $msifile) {
    Write-Error "Please provide the path to the StifleR Dashboard MSI file."
    exit 1
}
if (!(Test-Path $msifile)) {
    Write-Error "MSI file not found at $msifile. Please provide the correct path to the StifleR Dashboard MSI."
    exit 1
}
# Ensure the script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

# This will use the connection specific suffix for the fqdn - useful when system is not domain joined
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

if (!$domain) {
    $domain = [string](Get-DnsClient | Select-Object -ExpandProperty ConnectionSpecificSuffix)
}
if ($($domain.Trim()) -eq ""){
    $partofdomain = $false
    
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

$STIFLERSERVER = "STIFLERSERVER=https://$($fqdn):1414"
$STIFLERLOCSERVER = "STIFLERLOCSERVER=https://$($fqdn):9000"

$arguments = "/i `"$msifile`" $STIFLERSERVER $STIFLERLOCSERVER /qn /norestart /l*v C:\Windows\Temp\StifleRDashboardInstall.log"

write-host "Using the following install commands: $arguments" #uncomment this line to see the command line

# Install the StifleR Dashboard
start-process "msiexec.exe" -arg $arguments -Wait

# Create the StifleR Dashboard IIS Virtual Directory
Import-Module WebAdministration
New-WebVirtualDirectory -Site "Default Web Site" -Name "StifleRDashboard" -PhysicalPath 'C:\Program Files\2Pint Software\StifleR Dashboards\Dashboard Files'

# Accessing server locally with fqdn can cause authentication prompt loop on workgroup server
if ($partofdomain -eq $false) {
    Write-Host "Server is not member of a domain. Configuring BackConnectionHostNames."
    $multiStringData = @("$fqdn")
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "BackConnectionHostNames" -Value $multiStringData -Type MultiString
}

Write-Host "Script completed."
}