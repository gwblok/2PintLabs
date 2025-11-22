<#

CURRENT ISSUES:
GreenShot hangs and waits for user input
VLC is saying it's a 16bit app, so check the download

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

# Configure root download path
$RootPath = "D:\DeployRSources\Applications"


if (Test-Path 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility') {
    Write-Host "DeployR.Utility module found."
    Import-Module 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
    #Set-DeployRHost "http://localhost:7282"
    $Passcode = (Get-Item -path 'HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings').GetValue("ClientPasscode")
    Connect-DeployR -Passcode $Passcode -ErrorAction Stop
    $AllApps = Get-DeployRApplication

} else {
    Write-Host "DeployR.Utility module not found. Please ensure DeployR Client is installed."
}
#region Functions
#Function to Create Apps in DeployR
Function New-DeployRApp {
    Param (
        [string]$AppName,
        [string]$AppSourceFolder,
        [string]$AppDescription = "No Description Provided",
        [string]$InstallationCommandLine = ""
    )

    $NewDRCI = New-DeployRContentItem -Type Folder -Name $AppName -Description "Script Generated" -Purpose Application
    New-DeployRContentItemVersion -ContentItemId $NewDRCI.id -SourceFolder $AppSourceFolder -InstallationCommandLine $InstallationCommandLine -Description $AppDescription
}
Function Test-DeployRAppExists {
    Param (
        [string]$AppName,
        [string]$AppVersion,
        [Parameter(Mandatory=$false)]
        [PSObject[]]$AllApps
    )

    # Use provided AllApps collection if available, otherwise query DeployR
    if ($null -eq $AllApps -or $AllApps.Count -eq 0) {
        $AllApps = Get-DeployRApplication
    }

    $existingApp = $AllApps | Where-Object { $_.Name -eq $AppName } -ErrorAction SilentlyContinue
    if ($null -ne $existingApp) {
        $LatestVersion = ($existingApp.versions | Select-Object -ExpandProperty Description | Sort-Object -Descending | Select-Object -First 1)
        return [PSCustomObject]@{
            Name          = $existingApp.Name
            LatestVersion = $LatestVersion
        }
    } else {
        return $false
    }
}


Function Update-DeployRApp {
    Param (
        [string]$AppName,
        [string]$AppVersion = "No Description Provided",
        [string]$AppSourceFolder,
        [string]$InstallationCommandLine = "",
        [Parameter(Mandatory=$false)]
        [PSObject[]]$AllApps
    )

    # Use provided AllApps collection if available, otherwise query DeployR
    if ($null -eq $AllApps -or $AllApps.Count -eq 0) {
        $existingApp = Get-DeployRApplication -Name $AppName -ErrorAction Stop
    } else {
        $existingApp = $AllApps | Where-Object { $_.Name -eq $AppName } -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    
    if ($null -ne $existingApp) {
        Write-Host "Updating DeployR Application: $AppName"
        $NewDRCIV = New-DeployRContentItemVersion -ContentItemId $existingApp.id -SourceFolder $AppSourceFolder -InstallationCommandLine $InstallationCommandLine -Description $AppVersion
    } else {
        Write-Host "DeployR Application not found: $AppName"
    }
}

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
        # Mozilla uses 'win64' and 'win' (not 'winx64' and 'winx86')
        # Using MSI installer for enterprise deployment
        $osParam = if ($Architecture -eq 'x64') { 'win64' } else { 'win' }
        $downloadPage = "https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=$osParam&lang=$Language"
        
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
            SilentInstallCommand = "msiexec.exe /i FILENAME /qn"
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
        # Mozilla uses 'win64' and 'win' (not 'winx64' and 'winx86')
        # Using MSI installer for enterprise deployment
        $osParam = if ($Architecture -eq 'x64') { 'win64' } else { 'win' }
        $downloadPage = "https://download.mozilla.org/?product=thunderbird-msi-latest-ssl&os=$osParam&lang=$Language"
        
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
            SilentInstallCommand = "msiexec.exe /i FILENAME /qn"
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
                SilentInstallCommand = "FILENAME /S"
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
        # Get version from VLC's last release directory
        $lastUrl = "https://get.videolan.org/vlc/last/"
        $page = Invoke-WebRequest -Uri $lastUrl -UseBasicParsing -ErrorAction Stop
        
        # Extract version from tar.xz filename (e.g., vlc-3.0.21.tar.xz)
        if ($page.Content -match 'vlc-([\d.]+)\.tar\.xz') {
            $version = $matches[1]
        }
        else {
            throw "Could not determine VLC version"
        }
        
        # Construct download URL using version number (direct from videolan.org, no mirror redirect)
        $archPath = if ($Architecture -eq 'x64') { 'win64' } else { 'win32' }
        $url = "https://download.videolan.org/vlc/$version/$archPath/vlc-$version-$archPath.exe"
        
        Write-Verbose "VLC URL: $url"
        Write-Verbose "VLC Version: $version"
        
        return [PSCustomObject]@{
            AppName = "VLC Media Player"
            Version = $version
            URL = $url
            SilentInstallCommand = "FILENAME /L=1033 /S"
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
        # Use GitHub API to get latest release
        $apiUrl = "https://api.github.com/repos/ip7z/7zip/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        
        $version = $release.tag_name
        
        # Get MSI installer based on architecture
        if ($Architecture -eq 'x64') {
            $installer = $release.assets | Where-Object { $_.name -match '^7z\d+-x64\.msi$' } | Select-Object -First 1
        }
        else {
            $installer = $release.assets | Where-Object { $_.name -match '^7z\d+\.msi$' -and $_.name -notmatch 'x64' } | Select-Object -First 1
        }
        
        if ($installer) {
            Write-Verbose "7-Zip URL: $($installer.browser_download_url)"
            Write-Verbose "7-Zip Version: $version"
            
            return [PSCustomObject]@{
                AppName = "7-Zip"
                Version = $version
                URL = $installer.browser_download_url
                SilentInstallCommand = "msiexec.exe /i FILENAME /quiet /norestart"
            }
        }
        else {
            Write-Error "Could not find 7-Zip MSI installer in latest release"
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
                SilentInstallCommand = "FILENAME /VERYSILENT"
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
                SilentInstallCommand = "FILENAME /auto DESKTOPSHORTCUT=0"
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
                    SilentInstallCommand = "FILENAME /auto DESKTOPSHORTCUT=0"
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

# Function to get latest OBS Studio download URL
function Get-OBSStudioLatestUrl {
    [CmdletBinding()]
    param(
        [ValidateSet('x64', 'arm64')]
        [string]$Architecture = 'x64'
    )
    
    try {
        $apiUrl = "https://api.github.com/repos/obsproject/obs-studio/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        
        $version = $release.tag_name -replace '^v?', ''
        
        # Look for Windows installer based on architecture
        if ($Architecture -eq 'x64') {
            $installer = $release.assets | Where-Object { $_.name -match 'OBS-Studio-.+-Windows-x64-Installer\.exe$' } | Select-Object -First 1
        }
        else {
            $installer = $release.assets | Where-Object { $_.name -match 'OBS-Studio-.+-Windows-arm64-Installer\.exe$' } | Select-Object -First 1
        }
        
        if ($installer) {
            Write-Verbose "OBS Studio URL: $($installer.browser_download_url)"
            Write-Verbose "OBS Studio Version: $version"
            
            return [PSCustomObject]@{
                AppName = "OBS Studio"
                Version = $version
                URL = $installer.browser_download_url
                SilentInstallCommand = "FILENAME /S"
            }
        }
        else {
            Write-Error "Could not find OBS Studio installer in latest release"
            return $null
        }
    }
    catch {
        Write-Error "Failed to get OBS Studio info: $_"
        return $null
    }
}

# Function to get latest VS Code download URL
function Get-VSCodeLatestUrl {
    [CmdletBinding()]
    param(
        [ValidateSet('x64', 'arm64')]
        [string]$Architecture = 'x64'
    )
    
    try {
        # VS Code uses a stable download URL that redirects to the latest version
        if ($Architecture -eq 'x64') {
            $downloadUrl = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"
        }
        else {
            $downloadUrl = "https://code.visualstudio.com/sha/download?build=stable&os=win32-arm64"
        }
        
        # Get version from the updates page
        $updatesPage = Invoke-WebRequest -Uri "https://code.visualstudio.com/updates" -UseBasicParsing -ErrorAction Stop
        
        # Extract version from the page title or header (e.g., "September 2025 (version 1.105)")
        if ($updatesPage.Content -match 'version\s+([\d.]+)') {
            $version = $matches[1]
        }
        else {
            $version = "Latest"
        }
        
        Write-Verbose "VS Code URL: $downloadUrl"
        Write-Verbose "VS Code Version: $version"
        
        return [PSCustomObject]@{
            AppName = "VS Code"
            Version = $version
            URL = $downloadUrl
            SilentInstallCommand = "FILENAME /VERYSILENT /NORESTART /MERGETASKS=!runcode"
        }
    }
    catch {
        Write-Error "Failed to get VS Code info: $_"
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
        OBSStudio = Get-OBSStudioLatestUrl -Architecture $Architecture
        VSCode = Get-VSCodeLatestUrl -Architecture $Architecture
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


function Save-AppInstaller {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        # Root folder that will contain AppName\Version
        [Parameter(Mandatory, Position=0)]
        [string]$RootPath,

        # Either pass a PSCustomObject with AppName, Version, URL...
        [Parameter(ParameterSetName='Object', Mandatory, ValueFromPipeline)]
        [PSObject]$InputObject,

        # ...or pass explicit fields
        [Parameter(ParameterSetName='Fields', Mandatory)]
        [string]$AppName,

        [Parameter(ParameterSetName='Fields', Mandatory)]
        [string]$Version,

        [Parameter(ParameterSetName='Fields', Mandatory)]
        [Uri]$Url,

        # Overwrite existing file if present
        [switch]$Force,

        # BITS priority (Foreground is fastest)
        [ValidateSet('Foreground','High','Normal','Low')]
        [string]$BitsPriority = 'Foreground'
    )

    begin {
        # Ensure root exists
        if (-not (Test-Path -Path $RootPath -PathType Container)) {
            New-Item -Path $RootPath -ItemType Directory -Force | Out-Null
        }

        function Get-FileNameFromUrl {
            param([Uri]$ResolvedUrl, [string]$FallbackName)
            
            # Helper function to decode URL-encoded strings
            function Decode-UrlString {
                param([string]$EncodedString)
                return [System.Uri]::UnescapeDataString($EncodedString)
            }
            
            # First, try to follow redirects to get the final filename
            try {
                $resp = Invoke-WebRequest -Uri $ResolvedUrl -Method Head -MaximumRedirection 0 -ErrorAction Stop
                # If server responds 200, check content-disposition
                $cd = $resp.Headers['Content-Disposition']
                if ($cd -and $cd -match 'filename="?([^";]+)"?') {
                    $name = Decode-UrlString -EncodedString $Matches[1]
                    Write-Verbose "Got filename from Content-Disposition: $name"
                    return $name
                }
                
                # Get filename from the current URL
                $name = [System.IO.Path]::GetFileName($ResolvedUrl.AbsolutePath)
                if ($name -and $name -match '\.(exe|msi|zip)$') {
                    $decoded = Decode-UrlString -EncodedString $name
                    Write-Verbose "Got filename from URL path: $decoded"
                    return $decoded
                }
            } catch {
                # If redirect (302, 301), follow the Location header
                if ($_.Exception.Response) {
                    # Try accessing Location as a property (returns System.Uri)
                    $loc = $_.Exception.Response.Headers.Location
                    if ($loc) {
                        try {
                            # Location is already a Uri object
                            $redir = $loc
                            $redirName = [System.IO.Path]::GetFileName($redir.AbsolutePath)
                            if ($redirName -and $redirName -match '\.(exe|msi|zip)$') {
                                $decoded = Decode-UrlString -EncodedString $redirName
                                Write-Verbose "Got filename from redirect Location header: $decoded"
                                return $decoded
                            }
                        } catch { 
                            Write-Verbose "Failed to process redirect: $($_.Exception.Message)"
                        }
                    }
                }
            }
            
            # Last resort: try to get filename from URL path
            $name = [System.IO.Path]::GetFileName($ResolvedUrl.AbsolutePath)
            if ($name -and $name -match '\.(exe|msi|zip)$') {
                $decoded = Decode-UrlString -EncodedString $name
                Write-Verbose "Got filename from URL path (last resort): $decoded"
                return $decoded
            }
            
            # Fallback - but preserve extension if we can detect it from URL
            if ($ResolvedUrl.AbsoluteUri -match '\.(msi|exe|zip)($|\?)') {
                Write-Verbose "Using fallback with detected extension: .$($Matches[1])"
                return "$FallbackName.$($Matches[1])"
            }
            
            Write-Verbose "Using fallback with .exe extension"
            return "$FallbackName.exe"
        }
    }

    process {
        # Normalize inputs for both parameter sets
        if ($PSCmdlet.ParameterSetName -eq 'Object') {
            $App = $InputObject.AppName
            $Ver = $InputObject.Version
            $U   = $InputObject.URL
            if ($U -and -not ($U -is [Uri])) {
                try { $U = [Uri]$U } catch { }
            }
        } else {
            $App = $AppName
            $Ver = $Version
            $U   = $Url
        }

        if (-not $App) { throw "AppName not provided." }
        if (-not $Ver) { throw "Version not provided." }
        if (-not $U)   { throw "URL not provided." }
        if (-not ($U.Scheme -in @('http','https'))) { throw "URL must be HTTP/HTTPS." }

        $targetDir = Join-Path $RootPath $App | Join-Path -ChildPath $Ver
        if (-not (Test-Path $targetDir)) {
            if ($PSCmdlet.ShouldProcess($targetDir, "Create directory")) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
        }

        $fallbackName = "$App-$Ver"
        $fileName = Get-FileNameFromUrl -ResolvedUrl $U -FallbackName $fallbackName
        $destPath = Join-Path $targetDir $fileName

        if ((Test-Path $destPath) -and -not $Force) {
            Write-Verbose "File already exists, skipping: $destPath"
            
            # Build install command even for skipped files
            $installCmd = ""
            if ($PSCmdlet.ParameterSetName -eq 'Object' -and $InputObject.SilentInstallCommand) {
                $installCmd = $InputObject.SilentInstallCommand
                
                # Get the actual installer filename from the destination path
                $actualInstallerFileName = [System.IO.Path]::GetFileName($destPath)
                
                # If it's a directory (for extracted ZIPs), find the actual installer
                $destDir = [System.IO.Path]::GetDirectoryName($destPath)
                if (Test-Path $destDir) {
                    $installerFile = Get-ChildItem -Path $destDir | Where-Object { -not $_.PSIsContainer -and $_.Name -match '\.(exe|msi)$' } | Select-Object -First 1
                    if ($installerFile) {
                        $actualInstallerFileName = $installerFile.Name
                    }
                }
                
                # Build dynamic install command if one was provided
                $installCmd = ""
                if ($PSCmdlet.ParameterSetName -eq 'Object' -and $InputObject.SilentInstallCommand) {
                    $installCmd = $InputObject.SilentInstallCommand
                    
                    # Replace the simple FILENAME placeholder with quoted actual installer filename
                    $installCmd = $installCmd -replace 'FILENAME', "`"$actualInstallerFileName`""
                }
            }
            
            return [PSCustomObject]@{
                AppName        = $App
                Version        = $Ver
                URL            = $U.AbsoluteUri
                Destination    = $destPath
                Skipped        = $true
                Reason         = "File exists"
                ActualInstallCommand = $installCmd
            }
        }

        $jobName = "$App $Ver"
        if ($PSCmdlet.ShouldProcess($destPath, "BITS download from $($U.AbsoluteUri)")) {
            try {
                # Ensure destination directory exists (in case of race)
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

                if ((Test-Path $destPath) -and $Force) {
                    Remove-Item -Path $destPath -Force -ErrorAction SilentlyContinue
                }

                # Try BITS first
                $bitsSuccess = $false
                try {
                    $bitsParams = @{
                        Source = $U.AbsoluteUri
                        Destination = $destPath
                        DisplayName = $jobName
                        Description = "Downloading $App $Ver"
                        Priority = $BitsPriority
                        ErrorAction = 'Stop'
                    }
                    Start-BitsTransfer @bitsParams
                    
                    $bitsSuccess = $true
                    Write-Verbose "Downloaded via BITS: $destPath"
                }
                catch {
                    Write-Warning "BITS transfer failed for $App $Ver, falling back to Invoke-WebRequest: $($_.Exception.Message)"
                    
                    # Fallback to Invoke-WebRequest for URLs that BITS can't handle (like GitHub releases)
                    try {
                        Invoke-WebRequest -Uri $U.AbsoluteUri -OutFile $destPath -UseBasicParsing -ErrorAction Stop
                        $bitsSuccess = $true
                        Write-Verbose "Downloaded via Invoke-WebRequest: $destPath"
                    }
                    catch {
                        throw "Both BITS and Invoke-WebRequest failed: $($_.Exception.Message)"
                    }
                }

                # Extract ZIP file if downloaded
                $extractedFiles = @()
                $actualInstallerFileName = [System.IO.Path]::GetFileName($destPath)
                
                if ([System.IO.Path]::GetExtension($destPath) -eq '.zip') {
                    Write-Verbose "ZIP file detected, extracting contents..."
                    try {
                        $extractPath = [System.IO.Path]::GetDirectoryName($destPath)
                        Expand-Archive -Path $destPath -DestinationPath $extractPath -Force -ErrorAction Stop
                        Write-Verbose "Extracted ZIP contents to: $extractPath"
                        
                        # Get list of extracted files
                        $extractedFiles = Get-ChildItem -Path $extractPath | Where-Object { -not $_.PSIsContainer -and $_.FullName -ne $destPath } | Select-Object -ExpandProperty FullName
                        
                        # Find the actual installer file (.exe or .msi) for the install command
                        $installerFile = Get-ChildItem -Path $extractPath | Where-Object { -not $_.PSIsContainer -and $_.Name -match '\.(exe|msi)$' } | Select-Object -First 1
                        if ($installerFile) {
                            $actualInstallerFileName = $installerFile.Name
                            Write-Verbose "Found installer file: $actualInstallerFileName"
                        }
                        
                        # Remove the ZIP file
                        Remove-Item -Path $destPath -Force -ErrorAction Stop
                        Write-Verbose "Cleaned up ZIP file: $destPath"
                    }
                    catch {
                        Write-Warning "Failed to extract or cleanup ZIP file: $($_.Exception.Message)"
                    }
                }

                # Build dynamic install command if one was provided
                $installCmd = ""
                if ($PSCmdlet.ParameterSetName -eq 'Object' -and $InputObject.SilentInstallCommand) {
                    $installCmd = $InputObject.SilentInstallCommand
                    
                    # Replace the simple FILENAME placeholder with quoted actual installer filename
                    $installCmd = $installCmd -replace 'FILENAME', "`"$actualInstallerFileName`""
                }

                return [PSCustomObject]@{
                    AppName        = $App
                    Version        = $Ver
                    URL            = $U.AbsoluteUri
                    Destination    = $destPath
                    ExtractedFiles = $extractedFiles
                    Skipped        = $false
                    Success        = $true
                    ActualInstallCommand = $installCmd
                }
            }
            catch {
                $errorMsg = "Download failed for $App $Ver : $($_.Exception.Message)"
                Write-Error $errorMsg
                return [PSCustomObject]@{
                    AppName        = $App
                    Version        = $Ver
                    URL            = $U.AbsoluteUri
                    Destination    = $destPath
                    Skipped        = $false
                    Success        = $false
                    Error          = $_.Exception.Message
                    ActualInstallCommand = ""
                }
            }
        }
    }
}

# Examples:
# Get-FirefoxLatestUrl | Save-AppInstaller -RootPath 'D:\Installers' -Verbose
# Save-AppInstaller -RootPath 'D:\Installers' -AppName '7-Zip' -Version '23.01' -Url 'https://www.7-zip.org/a/7z2301-x64.exe' -Verbose



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
#endregion

#region Execution Area
# =============================================================================
# EXECUTION AREA - Download All Applications
# =============================================================================


$Architecture = 'x64'

Write-Host "`n=== Starting Application Downloads ===" -ForegroundColor Cyan
Write-Host "Root Path: $RootPath" -ForegroundColor Gray
Write-Host "Architecture: $Architecture" -ForegroundColor Gray

# Create input objects for each application
Write-Host "`n--- Retrieving Application Information ---" -ForegroundColor Yellow

$Firefox = Get-FirefoxLatestUrl -Architecture $Architecture
$Thunderbird = Get-ThunderbirdLatestUrl -Architecture $Architecture
$NotepadPlusPlus = Get-NotepadPlusPlusLatestUrl -Architecture $Architecture
$VLC = Get-VLCLatestUrl -Architecture $Architecture
$SevenZip = Get-7ZipLatestUrl -Architecture $Architecture
$Greenshot = Get-GreenshotLatestUrl
$PaintDotNet = Get-PaintDotNetLatestUrl
$OBSStudio = Get-OBSStudioLatestUrl -Architecture $Architecture
$VSCode = Get-VSCodeLatestUrl -Architecture $Architecture

# Display retrieved application info
$apps = @($Firefox, $Thunderbird, $NotepadPlusPlus, $VLC, $SevenZip, $Greenshot, $PaintDotNet, $OBSStudio, $VSCode)
#$apps = @($SevenZip)
foreach ($app in $apps) {
    if ($app) {
        Write-Host "  ✓ $($app.AppName) v$($app.Version)" -ForegroundColor Green
    }
}
# Download each application
Write-Host "`n--- Downloading Applications ---" -ForegroundColor Yellow

$results = @()
$deployRStats = @{
    Updated = @()
    Created = @()
    Skipped = @()
    Failed = @()
}

Foreach ($app in $apps) {
    Write-Output "Testing DeployR for $($app.AppName) v$($app.Version)"
    $AppTestResults = Test-DeployRAppExists -AppName $app.AppName -AppVersion $app.Version -AllApps $AllApps
    if ($AppTestResults) {
        write-Host " Testing Version $($AppTestResults.LatestVersion) vs $($app.Version)" -ForegroundColor Yellow
        if ($AppTestResults.LatestVersion -eq $app.Version) {
            Write-Host "  ⊙ $($app.AppName) already exists in DeployR with the latest version. Skipping upload." -ForegroundColor Yellow
            $deployRStats.Skipped += [PSCustomObject]@{
                AppName = $app.AppName
                Version = $app.Version
                Action = "Skipped - Already up to date"
            }
        } else {
            Write-Host "  ✗ $($app.AppName) exists in DeployR but is outdated. Will proceed to upload after download." -ForegroundColor Red
            $result = Save-AppInstaller -RootPath $RootPath -InputObject $app -Verbose
            $results += $result
            # Check if download succeeded OR file was already present (skipped)
            if ($result.Success -or $result.Skipped) {
                Write-Host " Updating DeployR Application for $($app.AppName) to version $($app.Version)" -ForegroundColor Cyan
                try {
                    # Use the actual install command from the download result if available
                    $installCommand = if ($result.ActualInstallCommand) { $result.ActualInstallCommand } else { $app.SilentInstallCommand }
                    Write-Host "    Install Command: $installCommand" -ForegroundColor Gray
                    Update-DeployRApp -AppName $app.AppName -AppVersion $app.Version -AppSourceFolder ($result.Destination | Split-Path) -InstallationCommandLine "$installCommand" -AllApps $AllApps
                    $deployRStats.Updated += [PSCustomObject]@{
                        AppName = $app.AppName
                        Version = $app.Version
                        PreviousVersion = $AppTestResults.LatestVersion
                        Action = "Updated"
                    }
                }
                catch {
                    Write-Error "Failed to update DeployR app: $_"
                    $deployRStats.Failed += [PSCustomObject]@{
                        AppName = $app.AppName
                        Version = $app.Version
                        Action = "Failed to update in DeployR"
                        Error = $_.Exception.Message
                    }
                }
            }
            else {
                $deployRStats.Failed += [PSCustomObject]@{
                    AppName = $app.AppName
                    Version = $app.Version
                    Action = "Failed to download"
                    Error = $result.Error
                }
            }
        }
    } else {
        Write-Host "  ✗ $($app.AppName) does not exist in DeployR or is outdated. Will proceed to upload after download." -ForegroundColor Red
        $result = Save-AppInstaller -RootPath $RootPath -InputObject $app -Verbose
        $results += $result
        # Check if download succeeded OR file was already present (skipped)
        if ($result.Success -or $result.Skipped) {
            Write-Host " Creating New DeployR Application for $($app.AppName) version $($app.Version)" -ForegroundColor Cyan
            try {
                # Use the actual install command from the download result if available
                $installCommand = if ($result.ActualInstallCommand) { $result.ActualInstallCommand } else { $app.SilentInstallCommand }
                Write-Host "    Install Command: $installCommand" -ForegroundColor Gray
                $NewApp = New-DeployRApp -AppName $app.AppName -AppSourceFolder ($result.Destination | Split-Path) -AppDescription "$($app.Version)" -InstallationCommandLine "$installCommand"
                $deployRStats.Created += [PSCustomObject]@{
                    AppName = $app.AppName
                    Version = $app.Version
                    Action = "Created"
                }
            }
            catch {
                Write-Error "Failed to create DeployR app: $_"
                $deployRStats.Failed += [PSCustomObject]@{
                    AppName = $app.AppName
                    Version = $app.Version
                    Action = "Failed to create in DeployR"
                    Error = $_.Exception.Message
                }
            }
        }
        else {
            $deployRStats.Failed += [PSCustomObject]@{
                AppName = $app.AppName
                Version = $app.Version
                Action = "Failed to download"
                Error = $result.Error
            }
        }
    }
}

<#
$results += Save-AppInstaller -RootPath $RootPath -InputObject $Firefox -Verbose
$results += Save-AppInstaller -RootPath $RootPath -InputObject $Thunderbird -Verbose
$results += Save-AppInstaller -RootPath $RootPath -InputObject $NotepadPlusPlus -Verbose
$results += Save-AppInstaller -RootPath $RootPath -InputObject $VLC -Verbose
$results += Save-AppInstaller -RootPath $RootPath -InputObject $SevenZip -Verbose
$results += Save-AppInstaller -RootPath $RootPath -InputObject $Greenshot -Verbose
$results += Save-AppInstaller -RootPath $RootPath -InputObject $PaintDotNet -Verbose
#>

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan

# Download Statistics
Write-Host "`n--- Download Statistics ---" -ForegroundColor Yellow
$downloadSuccessCount = ($results | Where-Object { $_.Success -eq $true }).Count
$downloadSkippedCount = ($results | Where-Object { $_.Skipped -eq $true }).Count
$downloadFailedCount = ($results | Where-Object { $_.Success -eq $false -and $_.Skipped -eq $false }).Count

Write-Host "  Downloaded: $downloadSuccessCount" -ForegroundColor Green
Write-Host "  Skipped (file exists): $downloadSkippedCount" -ForegroundColor Yellow
Write-Host "  Failed: $downloadFailedCount" -ForegroundColor $(if ($downloadFailedCount -gt 0) { 'Red' } else { 'Gray' })

# DeployR Statistics
Write-Host "`n--- DeployR Statistics ---" -ForegroundColor Yellow
Write-Host "  Created: $($deployRStats.Created.Count)" -ForegroundColor Green
Write-Host "  Updated: $($deployRStats.Updated.Count)" -ForegroundColor Cyan
Write-Host "  Skipped (up to date): $($deployRStats.Skipped.Count)" -ForegroundColor Yellow
Write-Host "  Failed: $($deployRStats.Failed.Count)" -ForegroundColor $(if ($deployRStats.Failed.Count -gt 0) { 'Red' } else { 'Gray' })

# Detailed DeployR Actions
if ($deployRStats.Created.Count -gt 0) {
    Write-Host "`n--- Created in DeployR ---" -ForegroundColor Green
    foreach ($item in $deployRStats.Created) {
        Write-Host "  ✓ $($item.AppName) v$($item.Version)" -ForegroundColor Green
    }
}

if ($deployRStats.Updated.Count -gt 0) {
    Write-Host "`n--- Updated in DeployR ---" -ForegroundColor Cyan
    foreach ($item in $deployRStats.Updated) {
        Write-Host "  ↑ $($item.AppName) v$($item.PreviousVersion) → v$($item.Version)" -ForegroundColor Cyan
    }
}

if ($deployRStats.Skipped.Count -gt 0) {
    Write-Host "`n--- Skipped (Already Up to Date) ---" -ForegroundColor Yellow
    foreach ($item in $deployRStats.Skipped) {
        Write-Host "  ⊙ $($item.AppName) v$($item.Version)" -ForegroundColor Yellow
    }
}

if ($deployRStats.Failed.Count -gt 0) {
    Write-Host "`n--- Failed Operations ---" -ForegroundColor Red
    foreach ($item in $deployRStats.Failed) {
        Write-Host "  ✗ $($item.AppName) v$($item.Version) - $($item.Action)" -ForegroundColor Red
        if ($item.Error) {
            Write-Host "    Error: $($item.Error)" -ForegroundColor DarkRed
        }
    }
}

# Download Details (if any downloads occurred)
if ($results.Count -gt 0) {
    Write-Host "`n--- Download Details ---" -ForegroundColor Yellow
    foreach ($result in $results) {
        $status = if ($result.Success) { "✓" } elseif ($result.Skipped) { "⊙" } else { "✗" }
        $color = if ($result.Success) { "Green" } elseif ($result.Skipped) { "Yellow" } else { "Red" }
        
        Write-Host "  $status $($result.AppName) v$($result.Version)" -ForegroundColor $color
        if ($result.ExtractedFiles -and $result.ExtractedFiles.Count -gt 0) {
            Write-Host "    Extracted: $($result.ExtractedFiles.Count) file(s)" -ForegroundColor Gray
        }
    }
}

Write-Host "`n=== Complete ===" -ForegroundColor Cyan

#endregion
