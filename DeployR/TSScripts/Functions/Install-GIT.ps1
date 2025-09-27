# Simple Git for Windows installer (64-bit, latest release)

# Ensure TLS 1.2 for GitHub API
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Get latest Git for Windows release info
$apiUrl = "https://api.github.com/repos/git-for-windows/git/releases/latest"
$release = Invoke-RestMethod -Uri $apiUrl -Method Get

# Find the 64-bit installer asset
$asset = $release.assets | Where-Object { $_.name -like "*64-bit.exe" } | Select-Object -First 1
$downloadUrl = $asset.browser_download_url
$packageName = $asset.name

# Download to temp folder
$tempDir = [System.IO.Path]::GetTempPath()
$packagePath = Join-Path $tempDir $packageName

Write-Host "Downloading Git installer..."
try {
    Start-BitsTransfer -Source $downloadUrl -Destination $packagePath -ErrorAction Stop
} catch {
    Write-Warning "Start-BitsTransfer failed, falling back to Invoke-WebRequest."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $packagePath
}

Write-Host "Installing Git silently..."
Start-Process $packagePath -ArgumentList "/VERYSILENT" -Wait

Write-Host "Git installation complete."