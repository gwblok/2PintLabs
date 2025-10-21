<#
.SYNOPSIS
    Downloads and installs the latest GreenShot release from GitHub.

.DESCRIPTION
    Queries the GitHub Releases API for the latest release of greenshot/greenshot,
    chooses an MSI if present (preferred) or an EXE installer, downloads it via
    BITS (falls back to Invoke-WebRequest), and performs a silent install.

.PARAMETER Force
    If specified, reinstall even if Greenshot appears to be installed.

.EXAMPLE
    Install-GreenShot -Force
#>
function Install-GreenShot {
    [CmdletBinding()]
    param(
        [switch]$Force,
        [switch]$Upgrade,
        [string]$DestinationPath
    )

    Write-Host "Installing GreenShot (latest from GitHub)"

    # Ensure TLS 1.2 for GitHub API
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    # Detect if Greenshot is already installed (basic check)
    $installed = Get-ItemProperty -ErrorAction SilentlyContinue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" |
        Where-Object { $_.DisplayName -and ($_.DisplayName -match 'Greenshot') } | Select-Object -First 1
    $installedVersion = if ($installed) { $installed.DisplayVersion } else { $null }

    $apiUrl = 'https://api.github.com/repos/greenshot/greenshot/releases/latest'
    Write-Host "Querying GitHub API: $apiUrl"
    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
    } catch {
        Write-Error "Failed to query GitHub API: $_"
        return $false
    }

    if (-not $release -or -not $release.assets) {
        Write-Error "No release assets found for Greenshot."
        return $false
    }

    # Prefer EXE assets (prefer x64/installer variants), Greenshot provides an EXE installer
    $asset = $release.assets | Where-Object { $_.name -match '\.exe$' -and ($_.name -match '64|x64|installer|Installer|Setup|setup') } | Select-Object -First 1
    if (-not $asset) {
        # fallback to any exe
        $asset = $release.assets | Where-Object { $_.name -match '\.exe$' } | Select-Object -First 1
    }

    if (-not $asset) {
        Write-Error "No installer asset (.msi or .exe) found in the latest Greenshot release."
        return $false
    }

    # Get latest version information
    $latestVersion = $release.tag_name
    if (-not $latestVersion) { $latestVersion = $release.name }
    Write-Host "Latest Greenshot version available: $latestVersion" -ForegroundColor Cyan
    Write-Verbose "Release name: $($release.name); tag: $($release.tag_name)"
    if ($installedVersion) {
        Write-Host "Currently installed Greenshot version: $installedVersion" -ForegroundColor Yellow
        Write-Verbose "Installed product: $($installed.DisplayName)"
    } else {
        Write-Host "Greenshot is not currently installed." -ForegroundColor Green
    }

    # If already installed and user did not request upgrade/force, exit after reporting
    if ($installedVersion -and -not ($Force -or $Upgrade)) {
        Write-Host "Use -Upgrade or -Force to reinstall/upgrade Greenshot." -ForegroundColor Yellow
        return $true
    }

    $downloadUrl = $asset.browser_download_url
    $packageName = $asset.name

    $tempDir = if ($DestinationPath) { Split-Path -Parent $DestinationPath } else { [System.IO.Path]::GetTempPath() }
    $packagePath = if ($DestinationPath) { $DestinationPath } else { Join-Path $tempDir $packageName }

    Write-Host "Selected asset: $packageName"
    Write-Host "Downloading to: $packagePath"

    # Download with BITS, fallback to Invoke-WebRequest
    try {
        Start-BitsTransfer -Source $downloadUrl -Destination $packagePath -ErrorAction Stop
    } catch {
        Write-Warning "Start-BitsTransfer failed (or not available). Falling back to Invoke-WebRequest: $_"
        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $packagePath -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Error "Failed to download Greenshot installer: $_"
            return $false
        }
    }

    # If installer will run, ensure Greenshot is not running. Attempt graceful close, then force kill.
    try {
        $gsProcs = Get-Process -Name 'Greenshot' -ErrorAction SilentlyContinue
        if ($gsProcs) {
            Write-Host "Detected running Greenshot process(es). Attempting to close them before install..." -ForegroundColor Yellow
            foreach ($p in $gsProcs) {
                try {
                    # Try to close the main window first if present
                    if ($p.MainWindowHandle -and $p.MainWindowHandle -ne 0) {
                        Write-Verbose "Sending close to main window for process Id $($p.Id)"
                        $p.CloseMainWindow() | Out-Null
                    }
                } catch {
                    Write-Verbose "Error sending CloseMainWindow to process Id $($p.Id): $_"
                }
            }

            # Wait for graceful exit up to a timeout, then force kill remaining
            $timeout = 15
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt $timeout) {
                $stillRunning = Get-Process -Name 'Greenshot' -ErrorAction SilentlyContinue
                if (-not $stillRunning) { break }
                Start-Sleep -Seconds 1
            }
            $sw.Stop()

            $stillRunning = Get-Process -Name 'Greenshot' -ErrorAction SilentlyContinue
            if ($stillRunning) {
                Write-Host "Force-stopping remaining Greenshot processes..." -ForegroundColor Yellow
                foreach ($p in $stillRunning) {
                    try {
                        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                        Write-Verbose "Stopped process Id $($p.Id)"
                    } catch {
                        Write-Warning "Failed to force-stop process Id $($p.Id): $_"
                    }
                }
            } else {
                Write-Verbose "Greenshot processes exited gracefully." 
            }
        }
    } catch {
        Write-Verbose "Error while checking/stopping Greenshot processes: $_"
    }

    # Expect an EXE installer and run with /VERYSILENT
    $ext = [System.IO.Path]::GetExtension($packagePath).ToLowerInvariant()
    if ($ext -ne '.exe') {
        Write-Error "Expected an .exe installer but found '$ext'"
        return $false
    }
    Write-Host "Running EXE installer with /VERYSILENT..."
    try {
        $proc = Start-Process -FilePath $packagePath -ArgumentList "/VERYSILENT" -PassThru -NoNewWindow -ErrorAction Stop
        Write-Verbose "Launched installer PID $($proc.Id). Monitoring until it exits..."

        # Monitor the installer process in a loop and timeout if it takes too long
        $timeoutSeconds = 600 # 10 minutes
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt $timeoutSeconds) {
            try {
                $proc.Refresh()
                if ($proc.HasExited) { break }
            } catch {
                # If Refresh failed, check with Get-Process; if it's gone, break
                if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
            }
            Start-Sleep -Seconds 1
        }
        $sw.Stop()

        # Final refresh and exit-code check
        try { $proc.Refresh() } catch {}
        if (-not $proc.HasExited) {
            Write-Warning "Installer did not exit within $timeoutSeconds seconds. Attempting to continue, but installation may be incomplete."
        }
        $exit = $null
        try { $exit = $proc.ExitCode } catch {}
        if ($exit -ne $null -and $exit -ne 0) { Write-Error "Installer returned exit code $exit"; return $false }
    } catch {
        Write-Error "Failed to launch or monitor installer: $_"
        return $false
    }

    Write-Host "GreenShot installation finished. Cleaning up downloaded file."
    try { Remove-Item -Path $packagePath -Force -ErrorAction SilentlyContinue } catch {}

    return $true
}
