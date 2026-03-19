# DownloadDocs.ps1 - Mirror multiple doc sites in parallel using wget

$WebDownloads = @(
    #[PSCustomObject]@{ BaseUrl = "https://documentation.2pintsoftware.com/"; OutputDir = "C:\LocalDocs\2PintDocs" }
    [PSCustomObject]@{ BaseUrl = "https://ipxe.org/";                   OutputDir = "C:\LocalDocs\iPXE_Docs" }
)

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmm'

# Download-wget-to-temp.ps1
# Downloads standalone wget.exe (x64) from eternallybored.org to %TEMP%
# Run as normal user - no admin rights needed

$ErrorActionPreference = 'Stop'

# Config - latest known direct link (as of March 2026 - 1.21.4 x64)
$wgetUrl      = "https://eternallybored.org/misc/wget/1.21.4/64/wget.exe"
$localPath    = Join-Path $env:TEMP "wget.exe"
$backupPath   = Join-Path $env:TEMP "wget.exe.bak"   # if already exists

Write-Host "Downloading wget.exe to: $localPath" -ForegroundColor Cyan

# Optional: Backup existing if present
if (Test-Path $localPath) {
    Write-Host "Existing wget.exe found in temp - renaming to .bak" -ForegroundColor Yellow
    if (Test-Path $backupPath) { Remove-Item $backupPath -Force -ErrorAction SilentlyContinue }
    Rename-Item $localPath $backupPath -Force
}

try {
    # Download with progress
    Invoke-WebRequest -Uri $wgetUrl -OutFile $localPath -UseBasicParsing

    # Verify it exists and is executable-ish
    if (Test-Path $localPath) {
        Write-Host "Download successful!" -ForegroundColor Green
        
        # Quick version check (runs wget --version)
        Write-Host "`nwget version info:" -ForegroundColor Cyan
        & $localPath --version | Select-Object -First 3   # shows first few lines

        Write-Host "`nDone. You can now use it like:" -ForegroundColor Green
        Write-Host "  & '$localPath' -h" -ForegroundColor White
        Write-Host "  # Or copy to a permanent location (e.g. C:\Tools\wget.exe) and add to PATH"
    } else {
        throw "File not found after download"
    }
}
catch {
    Write-Host "Error during download or verification:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host "`nTry these alternatives:"
    Write-Host "1. Visit https://eternallybored.org/misc/wget/ in browser"
    Write-Host "   Click [EXE] under x64 for 1.21.4 (direct wget.exe)"
    Write-Host "2. Or install via Chocolatey (admin PS):"
    Write-Host "   choco install wget"
    exit 1
}

# Optional: Make it easier to use right away (temporary PATH for this session)
$env:PATH = "$env:TEMP;$env:PATH"
Write-Host "`nFor this PowerShell session only: wget.exe is now in PATH (type 'wget --help' to test)" -ForegroundColor DarkCyan

# Ensure output dirs exist for all sites
foreach ($site in $WebDownloads) {
    if (-not (Test-Path $site.OutputDir)) {
        New-Item -Path $site.OutputDir -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $($site.OutputDir)" -ForegroundColor DarkGray
    }
}

# wget flags:
# -m        : mirror mode (recursive, timestamps, etc.)
# -k        : convert links for offline
# -E        : add .html extensions to pages
# -np       : no parent (stay in domain)
# -N        : timestamping - only download newer/changed files
# -w 2      : polite 2-sec delay
# --reject-regex : skip non-content assets to keep it lean
# -P        : prefix output dir
# --no-check-certificate : handle any SSL quirks
if (Test-Path -Path $localPath) {
    $wgetCmd = $localPath
} else {
    Write-Host "wget.exe not found at expected location: $localPath" -ForegroundColor Red
    Write-Host "Please ensure wget.exe is downloaded and available at that path, or adjust the script." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Starting parallel mirror of $($WebDownloads.Count) sites" -ForegroundColor Cyan
Write-Host " $(Get-Date)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Launch all wget processes in parallel
$jobs = @()
foreach ($site in $WebDownloads) {
    $logFile = Join-Path $site.OutputDir "mirror_${Timestamp}.log"
    $siteName = ([Uri]$site.BaseUrl).Host

    Write-Host "[START]  $siteName" -ForegroundColor Yellow
    Write-Host "         URL : $($site.BaseUrl)" -ForegroundColor DarkGray
    Write-Host "         Dir : $($site.OutputDir)" -ForegroundColor DarkGray
    Write-Host "         Log : $logFile" -ForegroundColor DarkGray

    $proc = Start-Process -FilePath $wgetCmd -ArgumentList @(
        '-m', '-k', '-E', '-np', '-N', '-w', '2',
        '--reject-regex', '"(.*)\.(jpg|jpeg|png|gif|svg|webp|css|js|woff|ttf|ico|map|json)$"',
        '--no-check-certificate',
        "--output-file=`"$logFile`"",
        "`"$($site.BaseUrl)`"",
        '-P', "`"$($site.OutputDir)`""
    ) -PassThru -NoNewWindow

    $jobs += [PSCustomObject]@{
        SiteName = $siteName
        BaseUrl  = $site.BaseUrl
        OutputDir = $site.OutputDir
        LogFile  = $logFile
        Process  = $proc
    }

    Write-Host "[PID $($proc.Id)] wget launched for $siteName" -ForegroundColor Green
}

Write-Host "`n--- All $($jobs.Count) wget processes launched. Waiting for completion... ---`n" -ForegroundColor Cyan

# Wait for all processes and report results
foreach ($job in $jobs) {
    $job.Process.WaitForExit()
    $exitCode = $job.Process.ExitCode
    $duration = ($job.Process.ExitTime - $job.Process.StartTime).ToString("hh\:mm\:ss")

    if ($exitCode -eq 0) {
        Write-Host "[DONE]   $($job.SiteName) completed successfully (${duration})" -ForegroundColor Green
    } else {
        Write-Host "[WARN]   $($job.SiteName) exited with code $exitCode (${duration})" -ForegroundColor Yellow
        Write-Host "         Check log: $($job.LogFile)" -ForegroundColor Yellow
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " All mirrors finished at $(Get-Date)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
foreach ($job in $jobs) {
    Write-Host "  $($job.SiteName) -> $($job.OutputDir)  [Log: $($job.LogFile)]" -ForegroundColor DarkGray
}
Write-Host "Review logs for errors; only new/changed files are downloaded each run." -ForegroundColor DarkCyan