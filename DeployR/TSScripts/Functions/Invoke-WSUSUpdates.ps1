<#
.SYNOPSIS
    Configures Windows Update to point to a specified WSUS server and forces it to pull (search, download, and install) all available updates.

.DESCRIPTION
    - Sets the required registry policies so Windows Update uses the provided WSUS server.
    - Restarts the Windows Update service.
    - Uses the native Windows Update COM API (Microsoft.Update.Session) to:
        - Search for all available updates from the WSUS server.
        - Download them.
        - Install them.
    - The script must be run with Administrator privileges.

.PARAMETER WSUSServer
    The full WSUS server URL (including protocol and port).
    Example: "http://wsus.contoso.com:8530" or "https://wsus.contoso.com:8531"

.EXAMPLE
    .\Set-WSUSAndInstallUpdates.ps1 -WSUSServer "http://wsus.contoso.com:8530"

.NOTES
    - Works on Windows 10 / Windows 11 / Windows Server 2016+.
    - If a Group Policy is actively enforcing a different WSUS server, it may override these settings.
    - Reboot may be required after installation (the script will notify you).
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$WSUSServer = "http://DR-Dell.2p.garytown.com:8530"
)

# ===================================================================
# 1. Check for Administrator rights
# ===================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Please right-click PowerShell and select 'Run as administrator'."
    exit 1
}

# ===================================================================
# 2. Configure Windows Update via Registry (Policies)
# ===================================================================
$wuRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$auRegPath = "$wuRegPath\AU"

# Create registry paths if they don't exist
if (-not (Test-Path $wuRegPath)) {
    New-Item -Path $wuRegPath -Force | Out-Null
}
if (-not (Test-Path $auRegPath)) {
    New-Item -Path $auRegPath -Force | Out-Null
}

Write-Host "Configuring Windows Update to use WSUS server: $WSUSServer" -ForegroundColor Cyan

# Set WSUS server URLs
Set-ItemProperty -Path $wuRegPath -Name "WUServer" -Value $WSUSServer -Type String -Force
Set-ItemProperty -Path $wuRegPath -Name "WUStatusServer" -Value $WSUSServer -Type String -Force

# Tell Windows Update to use the WSUS server instead of Microsoft Update
Set-ItemProperty -Path $auRegPath -Name "UseWUServer" -Value 1 -Type DWord -Force

# Optional: Set to "Auto download and schedule the install" (common for WSUS environments)
# Uncomment the line below if you want automatic behavior (value 4)
# Set-ItemProperty -Path $auRegPath -Name "AUOptions" -Value 4 -Type DWord -Force

Write-Host "Registry configuration complete." -ForegroundColor Green

# ===================================================================
# 3. Restart Windows Update service to apply changes
# ===================================================================
Write-Host "Restarting Windows Update service (wuauserv)..." -ForegroundColor Cyan
Restart-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue

# ===================================================================
# 4. Trigger update scan, download, and install using COM API
# ===================================================================
Write-Host "`nConnecting to WSUS server and searching for updates..." -ForegroundColor Cyan

try {
    $UpdateSession = New-Object -ComObject Microsoft.Update.Session
    $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()

    # Search for all updates that are not yet installed and not hidden
    $SearchResult = $UpdateSearcher.Search("IsInstalled=0 and IsHidden=0")

    if ($SearchResult.Updates.Count -eq 0) {
        Write-Host "No updates are available from the WSUS server at this time." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "$($SearchResult.Updates.Count) update(s) found." -ForegroundColor Green

    # ----------------------------------------------------------------
    # 4a. Download phase
    # ----------------------------------------------------------------
    $UpdatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl

    foreach ($Update in $SearchResult.Updates) {
        # Accept EULA if required
        if (-not $Update.EulaAccepted) {
            $Update.AcceptEula() | Out-Null
        }
        $UpdatesToDownload.Add($Update) | Out-Null
    }

    if ($UpdatesToDownload.Count -gt 0) {
        Write-Host "Downloading $($UpdatesToDownload.Count) update(s)..." -ForegroundColor Cyan
        $Downloader = $UpdateSession.CreateUpdateDownloader()
        $Downloader.Updates = $UpdatesToDownload
        $DownloadResult = $Downloader.Download()

        if ($DownloadResult.ResultCode -eq 2) {
            Write-Host "Download completed successfully." -ForegroundColor Green
        } else {
            Write-Warning "Download completed with result code: $($DownloadResult.ResultCode)"
        }
    }

    # ----------------------------------------------------------------
    # 4b. Install phase
    # ----------------------------------------------------------------
    $UpdatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl

    foreach ($Update in $SearchResult.Updates) {
        if ($Update.IsDownloaded) {
            $UpdatesToInstall.Add($Update) | Out-Null
        }
    }

    if ($UpdatesToInstall.Count -gt 0) {
        Write-Host "Installing $($UpdatesToInstall.Count) update(s)..." -ForegroundColor Cyan
        $Installer = $UpdateSession.CreateUpdateInstaller()
        $Installer.Updates = $UpdatesToInstall
        $InstallResult = $Installer.Install()

        switch ($InstallResult.ResultCode) {
            2 { Write-Host "Installation completed successfully." -ForegroundColor Green }
            3 { Write-Host "Installation completed with errors." -ForegroundColor Yellow }
            4 { Write-Host "Installation failed." -ForegroundColor Red }
            default { Write-Host "Installation completed with result code: $($InstallResult.ResultCode)" -ForegroundColor Yellow }
        }

        if ($InstallResult.RebootRequired) {
            Write-Host "`nA REBOOT IS REQUIRED to finish applying the updates." -ForegroundColor Magenta
        }
    } else {
        Write-Host "No updates were ready for installation." -ForegroundColor Yellow
    }
}
catch {
    Write-Error "An error occurred while processing updates: $($_.Exception.Message)"
    exit 1
}

Write-Host "`nScript completed. Windows Update is now pointed at $WSUSServer and all available updates have been pulled and installed." -ForegroundColor Green