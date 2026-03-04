
#region Functions

Function Get-ContentFromGitHub {<#
.SYNOPSIS
    Downloads DeployR CustomSteps from GitHub repository and imports them into DeployR
    
.DESCRIPTION
    This script downloads the contents of the DeployR CustomSteps folder from the GitHub repository
    and prepares them for import into DeployR. It uses the GitHub API to enumerate folder contents
    and downloads each file to a local directory.
    
.PARAMETER DownloadPath
    Local path where the CustomSteps will be downloaded. Defaults to current directory + CustomSteps
    
.PARAMETER GitHubRepo
    GitHub repository in format "owner/repo". Defaults to "gwblok/2PintLabs"
    
.PARAMETER GitHubPath
    Path within the repository. Defaults to "DeployR/CustomSteps"
    
.EXAMPLE
    .\DeployR-ImportFromGithub.ps1
    Downloads CustomSteps to .\CustomSteps using default parameters
    
.EXAMPLE
    .\DeployR-ImportFromGithub.ps1 -DownloadPath "C:\Temp\CustomSteps"
    Downloads CustomSteps to specified path
    #>
    
    
    param(
    [string]$DownloadPath = "$env:Windows\Temp\iPXE\Scripts",
    [string]$GitHubRepo = "2pintsoftware/2Pint-iPXEAnywhere",
    [string]$GitHubPath = "Scripts"
    )
    
    # GitHub URLs
    $GitHubBrowseUrl = "https://github.com/$GitHubRepo/tree/main/$GitHubPath"
    $GitHubApiUrl = "https://api.github.com/repos/$GitHubRepo/contents/$GitHubPath"
    $GitHubRawUrl = "https://raw.githubusercontent.com/$GitHubRepo/main"

    Write-Host "$GitHubRepo GitHub Importer" -ForegroundColor Green
    Write-Host "====================================" -ForegroundColor Green
    Write-Host "Repository: $GitHubBrowseUrl" -ForegroundColor Cyan
    #Write-Host "Download Path: $((Resolve-Path $DownloadPath -ErrorAction SilentlyContinue) ?? (Join-Path (Get-Location) $DownloadPath))" -ForegroundColor Cyan
    Write-Host ""
    
    # Create download directory if it doesn't exist
    if (Test-Path $DownloadPath) {
        Write-Host "Download directory already exists: $DownloadPath" -ForegroundColor Green
        #Delete And Recreate the Directory
        Remove-Item -Path $DownloadPath -Recurse -Force
        New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
        Write-Host "Recreated download directory: $DownloadPath" -ForegroundColor Yellow
    }
    else {
        Write-Host "Creating download directory: $DownloadPath" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
    }
    
    # Function to download file from GitHub
    function Get-GitHubFile {
        param(
        [string]$FileUrl,
        [string]$LocalPath,
        [string]$RelativePath
        )
        
        try {
            Write-Host "Downloading: $RelativePath" -ForegroundColor White
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($FileUrl, $LocalPath)
            Write-Host "  -> Downloaded to: $LocalPath" -ForegroundColor Gray
            return $true
        }
        catch {
            Write-Warning "Failed to download $RelativePath : $($_.Exception.Message)"
            return $false
        }
    }
    
    # Function to recursively download directory contents
    function Get-GitHubDirectory {
        param(
        [string]$ApiUrl,
        [string]$LocalBasePath,
        [string]$RelativeBasePath = ""
        )
        
        try {
            Write-Host "Fetching directory contents from: $ApiUrl" -ForegroundColor Cyan
            $response = Invoke-RestMethod -Uri $ApiUrl -ErrorAction Stop
            
            $downloadCount = 0
            $successCount = 0
            
            foreach ($item in $response) {
                $relativePath = if ($RelativeBasePath) { "$RelativeBasePath/$($item.name)" } else { $item.name }
                $localPath = Join-Path $LocalBasePath $relativePath
                
                if ($item.type -eq "file") {
                    # Download file
                    $downloadCount++
                    $fileUrl = "$GitHubRawUrl/$GitHubPath/$relativePath"
                    
                    # Create directory if needed
                    $localDir = Split-Path $localPath -Parent
                    if (!(Test-Path $localDir)) {
                        New-Item -ItemType Directory -Path $localDir -Force | Out-Null
                    }
                    
                    if (Get-GitHubFile -FileUrl $fileUrl -LocalPath $localPath -RelativePath $relativePath) {
                        $successCount++
                    }
                }
                elseif ($item.type -eq "dir") {
                    # Recursively download subdirectory
                    Write-Host "Entering directory: $relativePath" -ForegroundColor Yellow
                    $subApiUrl = $item.url
                    $subCounts = Get-GitHubDirectory -ApiUrl $subApiUrl -LocalBasePath $LocalBasePath -RelativeBasePath $relativePath
                    $downloadCount += $subCounts.Total
                    $successCount += $subCounts.Success
                }
            }
            
            return @{ Total = $downloadCount; Success = $successCount }
        }
        catch {
            Write-Error "Failed to fetch directory contents from $ApiUrl : $($_.Exception.Message)"
            return @{ Total = 0; Success = 0 }
        }
    }
    
    # Main execution
    Write-Host "Starting download from GitHub..." -ForegroundColor Green
    
    $results = Get-GitHubDirectory -ApiUrl $GitHubApiUrl -LocalBasePath $DownloadPath
    
    Write-Host ""
    Write-Host "Download Summary:" -ForegroundColor Green
    Write-Host "=================" -ForegroundColor Green
    Write-Host "Total files: $($results.Total)" -ForegroundColor White
    Write-Host "Successfully downloaded: $($results.Success)" -ForegroundColor Green
    Write-Host "Failed downloads: $($results.Total - $results.Success)" -ForegroundColor $(if ($results.Total - $results.Success -eq 0) { "Green" } else { "Red" })
    
    if ($results.Success -gt 0) {
        Write-Host ""
        Write-Host "CustomSteps have been downloaded to: $DownloadPath" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next Steps for DeployR Import:" -ForegroundColor Yellow
        Write-Host "1. Open DeployR Management Console" -ForegroundColor White
        Write-Host "2. Navigate to Custom Steps" -ForegroundColor White
        Write-Host "3. Import the downloaded CustomSteps from: $DownloadPath" -ForegroundColor White
        Write-Host "4. Each subdirectory typically represents a separate custom step" -ForegroundColor White
        Write-Host ""
        
        # List downloaded items
        if (Test-Path $DownloadPath) {
            $items = Get-ChildItem $DownloadPath -Directory | Sort-Object Name
            if ($items.Count -gt 0) {
                Write-Host "Downloaded CustomSteps:" -ForegroundColor Cyan
                foreach ($item in $items) {
                    Write-Host "  - $($item.Name)" -ForegroundColor White
                }
            }
        }
    }
    else {
        Write-Warning "No files were successfully downloaded. Please check your internet connection and try again."
    }
    
    Write-Host ""
    Write-Host "Scripts download completed." -ForegroundColor Green
    
}



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

Function Install-iPXEWS {
    [CmdletBinding()]
    param(
        [string]$msifile
    )

    <#
.SYNOPSIS
    PowerShell script to perform an unattended install of iPXE Webservice 
.DESCRIPTION
    This script automates installing iPXE Webservice and will grab the certificate thumbprint
    from a 2PXE FQDN self-signed certificate. Make sure 2PXE is installed first and a FQDN cert
    has been generated.
    It verifies the import, and handles common errors.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 20, 2025
    Version: 25.07.21
    Requires: Administrative privileges, 64-bit Windows
#>

# Set path to MSI file
#$msifile = "$PSScriptRoot\iPXEAnywhere.WebService.Installer64.msi"
if (-not $msifile) {
    Write-Error "Please provide the path to the StifleR Dashboard MSI file."
    exit 1
}
if (!(Test-Path $msifile)) {
    Write-Error "MSI file not found at $msifile. Please provide the correct path to the StifleR Dashboard MSI."
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
    Write-Host "No domain suffix found. Please provide a domain name."
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
                    $Thumbprint = $cert.Thumbprint
                    Write-Host "  - FQDN: $SANfqdn"
                    Write-Host "  - Thumbprint: $Thumbprint"
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

$arguments = @(
#Mandatory msiexec Arguments

    "/i"

    "`"$msiFile`""

#Mandatory 2Pint Arguments
    
    "ODBC_SERVER=`"$env:COMPUTERNAME\SQLEXPRESS`""   # Change to the correct database server and instance
    "CERTHASH=`"$Thumbprint`""                       # Certificate thumbprint detected above or change if previously known

#Non Mandatory 2Pint Arguments - Uncomment+change the settings that you need - otherwise the default will be used.

# "LICENSEKEY=`"ABC123`""                            # License key 
# "LICENSETYPE=`"#3`""                               # Uncomment if a license key was entered 

#Other MSIEXEC params
    "/qn" #Quiet - with basic interface - for NO interface use /qn instead

    "/norestart"

    "/l*v $env:windir\temp\iPXEWSInstall.log"    #Optional logging for the install

)

write-host "Using the following install commands: $arguments" #uncomment this line to see the command line

#Install the iPXE Webservice
$install = start-process "msiexec.exe" -arg $arguments -Wait


# Copy the iPXEWS Scripts to the iPXEWS default install directory
# The Scripts directory needs to be in the same directory as the installer script

$DownloadPath = "$env:Windows\Temp\iPXE\Scripts"
Get-ContentFromGitHub -DownloadPath $DownloadPath -GitHubRepo "2pintsoftware/2Pint-iPXEAnywhere" -GitHubPath "Scripts"
try {

    # Define source and destination paths
    $sourcePath = $DownloadPath 
    $destPath = "C:\Program Files\2Pint Software\iPXE AnywhereWS"
    
    # Check if source directory exists
    if (-not (Test-Path $sourcePath)) {
        Write-Error "Scripts directory not found at $sourcePath"
    }
    
    # Create destination directory if it doesn't exist
    if (-not (Test-Path $destPath)) {
        New-Item -ItemType Directory -Path $destPath -Force | Out-Null
    }
    
    # Copy the Scripts directory and all contents
    Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
    
    Write-Host "Successfully copied Scripts directory to $destPath"
}
catch {
    Write-Error "An error occurred while copying the directory: $_"
}

# Update the deployr.ps1 iPXE WS script default location with the correct FQDN
# Define the path to the deployr.ps1 file
$scriptPath = "C:\Program Files\2Pint Software\iPXE AnywhereWS\Scripts\Custom\deployr.ps1"

try {
    # Check if the file exists
    if (-not (Test-Path $scriptPath)) {
        Write-Error "deployr.ps1 file not found at $scriptPath"
    }

    # Read the content of the file
    $content = Get-Content $scriptPath -Raw

    # Replace the server.company.com with the new FQDN
    $newContent = $content -replace "server\.company\.com", $fqdn

    # Write the modified content back to the file
    Set-Content -Path $scriptPath -Value $newContent

    Write-Host "Successfully replaced 'server.company.com' with '$fqdn' in $scriptPath"
}
catch {
    Write-Error "An error occurred while updating the file: $_"
}

Write-Host "Script completed."
}

#endregion Functions


$sourceFolder = "$env:USERPROFILE\Downloads\DeployRSuite\Extracted"

$WorkingDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
if ($WorkingDir){
    if (!(Test-Path -Path $WorkingDir)) {
        Write-Host "Script directory not found: $WorkingDir"
    }
    $MSIFiles = Get-ChildItem -Path $WorkingDir -Filter *.msi
}


if (!$MSIFiles) {
    Write-Host "No MSI files found in script directory: $WorkingDir"
    write-Host "Falling back to target folder: $sourceFolder if it exists." -ForegroundColor Yellow
    if (Test-Path -Path $sourceFolder) {
        $MSIFiles = Get-ChildItem -Path $sourceFolder -Filter *.msi
        if (!$MSIFiles) {
            Write-Host "No MSI files found in target folder: $sourceFolder"
            exit 1
        } else {
            Write-Host "Found MSI files in target folder: $sourceFolder" -ForegroundColor Green
        }
    } else {
        Write-Host "Target folder not found: $sourceFolder"
        exit 1
    }
}

$iPXE = $MSIFiles | Where-Object { $_.Name -like "*iPXE*.msi" } | Select-Object -First 1

if (!$iPXE) {
    Write-Host "No MSI file matching *iPXE*.msi found in script directory or target folder."
    exit 1
} else {
    Write-Host "Found iPXE MSI: $($iPXE.FullName)" -ForegroundColor Green
}

Install-iPXEWS -msifile $iPXE.FullName