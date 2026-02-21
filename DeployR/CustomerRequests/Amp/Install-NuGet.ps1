# Run as Administrator

Write-Host "Setting TLS 1.2..." -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls

# Optional: Trust PSGallery (common source of issues)
$PSGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
if ($PSGallery -and $PSGallery.InstallationPolicy -ne 'Trusted') {
    Write-Host "Setting PSGallery to Trusted..." -ForegroundColor Yellow
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
}

# Check current NuGet status
$nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue | 
         Where-Object { [version]$_.Version -ge [version]"2.8.5.201" } | 
         Select-Object -First 1

if ($nuget) {
    Write-Host "NuGet $($nuget.Version) is already installed and meets the requirement." -ForegroundColor Green
} else {
    Write-Host "Installing/Updating NuGet provider (minimum 2.8.5.201)..." -ForegroundColor Cyan
    
    try {
        # Try bootstrap install first
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop
        Write-Host "NuGet installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Warning "Standard install failed. Trying fallback with PowerShellGet update..."
        
        # Update PowerShellGet first (often fixes provider discovery)
        Install-Module -Name PowerShellGet -Force -AllowClobber -Scope AllUsers -ErrorAction SilentlyContinue
        
        # Then retry NuGet
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
    }
}

# Final verification
$nugetAfter = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
if ($nugetAfter -and [version]$nugetAfter.Version -ge [version]"2.8.5.201") {
    Write-Host "Success! NuGet $($nugetAfter.Version) is ready." -ForegroundColor Green
} else {
    Write-Error "NuGet still not installed correctly. Check internet, proxy, antivirus, or try manual download from https://www.powershellgallery.com/packages/NuGet"
}