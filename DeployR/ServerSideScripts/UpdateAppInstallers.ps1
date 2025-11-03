<#
.SYNOPSIS
    Functions to retrieve the latest download URLs for popular applications.

.DESCRIPTION
    This script provides functions to automatically find and return the latest download URLs for:
    - Firefox
    - Thunderbird
    - Notepad++
    - VLC Media Player
    - 7-Zip
    - GreenShot
    - Paint.Net

.NOTES
    Author: Gary Blok
    Date: November 3, 2025
#>

# Function to get latest Firefox download URL
function Get-FirefoxLatestUrl {
    [CmdletBinding()]
    param(
        [ValidateSet('x64', 'x86')]
        [string]$Architecture = 'x64',
        
        [ValidateSet('en-US', 'de', 'fr', 'es-ES')]
        [string]$Language = 'en-US'
    )
    
    try {
        $downloadPage = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win$Architecture&lang=$Language"
        
        # Get version from Mozilla's product details API
        $versionApi = "https://product-details.mozilla.org/1.0/firefox_versions.json"
        $versions = Invoke-RestMethod -Uri $versionApi -UseBasicParsing -ErrorAction Stop
        $version = $versions.LATEST_FIREFOX_VERSION
        
        Write-Verbose "Firefox URL: $downloadPage"
        Write-Verbose "Firefox Version: $version"
        
        return [PSCustomObject]@{
            AppName = "Firefox"
            Version = $version
            URL = $downloadPage
        }
    }
    catch {
        Write-Error "Failed to get Firefox info: $_"
        return $null
    }
}

# Function to get latest Thunderbird download URL
function Get-ThunderbirdLatestUrl {
    [CmdletBinding()]
    param(
        [ValidateSet('x64', 'x86')]
        [string]$Architecture = 'x64',
        
        [ValidateSet('en-US', 'de', 'fr', 'es-ES')]
        [string]$Language = 'en-US'
    )
    
    try {
        $downloadPage = "https://download.mozilla.org/?product=thunderbird-latest-ssl&os=win$Architecture&lang=$Language"
        
        # Get version from Mozilla's product details API
        $versionApi = "https://product-details.mozilla.org/1.0/thunderbird_versions.json"
        $versions = Invoke-RestMethod -Uri $versionApi -UseBasicParsing -ErrorAction Stop
        $version = $versions.LATEST_THUNDERBIRD_VERSION
        
        Write-Verbose "Thunderbird URL: $downloadPage"
        Write-Verbose "Thunderbird Version: $version"
        
        return [PSCustomObject]@{
            AppName = "Thunderbird"
            Version = $version
            URL = $downloadPage
        }
    }
    catch {
        Write-Error "Failed to get Thunderbird info: $_"
        return $null
    }
}

# Function to get latest Notepad++ download URL
function Get-NotepadPlusPlusLatestUrl {
    [CmdletBinding()]
    param(
        [ValidateSet('x64', 'x86')]
        [string]$Architecture = 'x64'
    )
    
    try {
        $apiUrl = "https://api.github.com/repos/notepad-plus-plus/notepad-plus-plus/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        
        $version = $release.tag_name -replace '^v', ''
        
        $archSuffix = if ($Architecture -eq 'x64') { '.x64' } else { '' }
        $installer = $release.assets | Where-Object { $_.name -match "npp\.\d+\.\d+(\.\d+)?\.Installer$archSuffix\.exe$" } | Select-Object -First 1
        
        if ($installer) {
            Write-Verbose "Notepad++ URL: $($installer.browser_download_url)"
            Write-Verbose "Notepad++ Version: $version"
            
            return [PSCustomObject]@{
                AppName = "Notepad++"
                Version = $version
                URL = $installer.browser_download_url
            }
        }
        else {
            Write-Error "Could not find Notepad++ installer in latest release"
            return $null
        }
    }
    catch {
        Write-Error "Failed to get Notepad++ info: $_"
        return $null
    }
}

# Function to get latest VLC Media Player download URL
function Get-VLCLatestUrl {
    [CmdletBinding()]
    param(
        [ValidateSet('x64', 'x86')]
        [string]$Architecture = 'x64'
    )
    
    try {
        $vlcPage = Invoke-WebRequest -Uri "https://www.videolan.org/vlc/" -UseBasicParsing -ErrorAction Stop
        
        if ($Architecture -eq 'x64') {
            $downloadLink = $vlcPage.Links | Where-Object { $_.href -match 'vlc-([\d.]+)(-\d+)?-win64\.exe$' } | Select-Object -First 1
        }
        else {
            $downloadLink = $vlcPage.Links | Where-Object { $_.href -match 'vlc-([\d.]+)(-\d+)?-win32\.exe$' } | Select-Object -First 1
        }
        
        if ($downloadLink) {
            $url = $downloadLink.href
            if ($url -notmatch '^https?://') {
                $url = "https://www.videolan.org$url"
            }
            
            # Extract version from URL
            if ($url -match 'vlc-([\d.]+)') {
                $version = $matches[1]
            }
            else {
                $version = "Unknown"
            }
            
            Write-Verbose "VLC URL: $url"
            Write-Verbose "VLC Version: $version"
            
            return [PSCustomObject]@{
                AppName = "VLC Media Player"
                Version = $version
                URL = $url
            }
        }
        else {
            Write-Error "Could not find VLC download link"
            return $null
        }
    }
    catch {
        Write-Error "Failed to get VLC info: $_"
        return $null
    }
}

# Function to get latest 7-Zip download URL
function Get-7ZipLatestUrl {
    [CmdletBinding()]
    param(
        [ValidateSet('x64', 'x86')]
        [string]$Architecture = 'x64'
    )
    
    try {
        $7zipPage = Invoke-WebRequest -Uri "https://www.7-zip.org/download.html" -UseBasicParsing -ErrorAction Stop
        
        if ($Architecture -eq 'x64') {
            $downloadLink = $7zipPage.Links | Where-Object { $_.href -match '7z(\d+)-x64\.exe$' } | Select-Object -First 1
        }
        else {
            $downloadLink = $7zipPage.Links | Where-Object { $_.href -match '7z(\d+)\.exe$' -and $_.href -notmatch 'x64' } | Select-Object -First 1
        }
        
        if ($downloadLink) {
            $url = "https://www.7-zip.org/$($downloadLink.href)"
            
            # Extract version from URL (e.g., 7z2301.exe -> 23.01)
            if ($downloadLink.href -match '7z(\d+)') {
                $versionNum = $matches[1]
                # Convert 2301 to 23.01
                $version = "$($versionNum.Substring(0,2)).$($versionNum.Substring(2))"
            }
            else {
                $version = "Unknown"
            }
            
            Write-Verbose "7-Zip URL: $url"
            Write-Verbose "7-Zip Version: $version"
            
            return [PSCustomObject]@{
                AppName = "7-Zip"
                Version = $version
                URL = $url
            }
        }
        else {
            Write-Error "Could not find 7-Zip download link"
            return $null
        }
    }
    catch {
        Write-Error "Failed to get 7-Zip info: $_"
        return $null
    }
}

# Function to get latest Greenshot download URL
function Get-GreenshotLatestUrl {
    [CmdletBinding()]
    param()
    
    try {
        $apiUrl = "https://api.github.com/repos/greenshot/greenshot/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        
        $version = $release.tag_name -replace '^v', ''
        
        $installer = $release.assets | Where-Object { $_.name -match 'Greenshot-INSTALLER.*\.exe$' } | Select-Object -First 1
        
        if ($installer) {
            Write-Verbose "Greenshot URL: $($installer.browser_download_url)"
            Write-Verbose "Greenshot Version: $version"
            
            return [PSCustomObject]@{
                AppName = "Greenshot"
                Version = $version
                URL = $installer.browser_download_url
            }
        }
        else {
            Write-Error "Could not find Greenshot installer in latest release"
            return $null
        }
    }
    catch {
        Write-Error "Failed to get Greenshot info: $_"
        return $null
    }
}

# Function to get latest Paint.NET download URL
function Get-PaintDotNetLatestUrl {
    [CmdletBinding()]
    param()
    
    try {
        # Paint.NET requires scraping their website as they don't have a direct API
        $paintPage = Invoke-WebRequest -Uri "https://www.getpaint.net/download.html" -UseBasicParsing -ErrorAction Stop
        
        # Look for the download link pattern
        $downloadLink = $paintPage.Links | Where-Object { $_.href -match 'paintdotnet\.[\d.]+\.install\.x64\.zip$' } | Select-Object -First 1
        
        if ($downloadLink) {
            $url = $downloadLink.href
            if ($url -notmatch '^https?://') {
                $url = "https://www.getpaint.net$url"
            }
            
            # Extract version from filename pattern like paintdotnet.5.0.13.install.x64.zip
            if ($url -match 'paintdotnet\.([\d.]+)\.install') {
                $version = $matches[1]
            }
            else {
                $version = "Unknown"
            }
            
            Write-Verbose "Paint.NET URL: $url"
            Write-Verbose "Paint.NET Version: $version"
            
            return [PSCustomObject]@{
                AppName = "Paint.NET"
                Version = $version
                URL = $url
            }
        }
        else {
            # Fallback to direct GitHub releases
            $apiUrl = "https://api.github.com/repos/paintdotnet/release/releases/latest"
            $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
            
            $version = $release.tag_name -replace '^v', ''
            
            $installer = $release.assets | Where-Object { $_.name -match 'paint\.net.*\.install\.x64\.zip$' } | Select-Object -First 1
            
            if ($installer) {
                Write-Verbose "Paint.NET URL: $($installer.browser_download_url)"
                Write-Verbose "Paint.NET Version: $version"
                
                return [PSCustomObject]@{
                    AppName = "Paint.NET"
                    Version = $version
                    URL = $installer.browser_download_url
                }
            }
            else {
                Write-Error "Could not find Paint.NET download link"
                return $null
            }
        }
    }
    catch {
        Write-Error "Failed to get Paint.NET info: $_"
        return $null
    }
}

# Function to get all latest URLs
function Get-AllLatestUrls {
    [CmdletBinding()]
    param(
        [ValidateSet('x64', 'x86')]
        [string]$Architecture = 'x64'
    )
    
    Write-Host "`n=== Retrieving Latest Download URLs ===" -ForegroundColor Cyan
    
    $urls = @{
        Firefox = Get-FirefoxLatestUrl -Architecture $Architecture
        Thunderbird = Get-ThunderbirdLatestUrl -Architecture $Architecture
        NotepadPlusPlus = Get-NotepadPlusPlusLatestUrl -Architecture $Architecture
        VLC = Get-VLCLatestUrl -Architecture $Architecture
        SevenZip = Get-7ZipLatestUrl -Architecture $Architecture
        Greenshot = Get-GreenshotLatestUrl
        PaintDotNet = Get-PaintDotNetLatestUrl
    }
    
    Write-Host "`n=== Results ===" -ForegroundColor Cyan
    foreach ($app in $urls.Keys | Sort-Object) {
        $appInfo = $urls[$app]
        if ($appInfo) {
            Write-Host "✓ $app" -ForegroundColor Green -NoNewline
            Write-Host " (v$($appInfo.Version))" -ForegroundColor Cyan -NoNewline
            Write-Host ": $($appInfo.URL)" -ForegroundColor Gray
        }
        else {
            Write-Host "✗ $app" -ForegroundColor Red -NoNewline
            Write-Host ": Failed to retrieve information" -ForegroundColor Yellow
        }
    }
    
    return $urls
}

# Example usage
<#
# Get individual app URLs
$firefoxUrl = Get-FirefoxLatestUrl -Architecture x64
$notepadUrl = Get-NotepadPlusPlusLatestUrl -Architecture x64

# Get all URLs at once
$allUrls = Get-AllLatestUrls -Architecture x64

# Access specific URLs from the hashtable
Write-Host "Firefox URL: $($allUrls.Firefox)"
Write-Host "Notepad++ URL: $($allUrls.NotepadPlusPlus)"
#>

