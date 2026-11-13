<#
.SYNOPSIS
Installs or updates Devolutions Jiffshot from the latest GitHub release.

.DESCRIPTION
Checks the Windows uninstall registry for an installed Jiffshot version and
compares it with the latest release from github.com/Devolutions/jiffshot.
When Jiffshot is missing or older, downloads the MSI for the OS architecture
using BITS, falling back to Invoke-WebRequest, verifies its SHA-256 digest,
and installs it silently with msiexec.

Requires internet access to api.github.com and github.com, and administrative
rights for the MSI installation. Downloads to the temp folder and writes an
msiexec log there.

.PARAMETER DownloadPath
Folder used for the downloaded MSI and install log. Defaults to the temp folder.

.PARAMETER Force
Reinstalls the latest version even if the installed version is current.

.EXAMPLE
.\Install-JiffshotFromCloud.ps1

.EXAMPLE
.\Install-JiffshotFromCloud.ps1 -Force -Verbose

.NOTES
Author: Not specified
Created: 2026-11-12
Change History:
2026-11-12 - Initial version.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $DownloadPath = $env:TEMP,

    [Parameter()]
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Get-InstalledJiffshot {
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*Jiffshot*' -and $_.DisplayVersion } |
        Sort-Object { [version]$_.DisplayVersion } -Descending |
        Select-Object -First 1
}

function Save-FileWithFallback {
    param (
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [string] $Destination
    )
    try {
        Write-Output "Downloading via BITS: $Uri"
        Start-BitsTransfer -Source $Uri -Destination $Destination -ErrorAction Stop
    }
    catch {
        Write-Warning "BITS download failed ($($_.Exception.Message)); falling back to Invoke-WebRequest."
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing
    }
}

try {
    # Query the latest release
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Devolutions/jiffshot/releases/latest' -UseBasicParsing -Headers @{ 'User-Agent' = 'Install-JiffshotFromCloud' }
    $latestVersion = [version]($release.tag_name.TrimStart('v'))
    Write-Output "Latest Jiffshot release: $latestVersion"

    # Compare with the installed version
    $installed = Get-InstalledJiffshot
    if ($installed) {
        $installedVersion = [version]$installed.DisplayVersion
        Write-Output "Installed Jiffshot version: $installedVersion"
        # Normalize to Major.Minor.Build; MSI versions may report a fourth component
        $installedComparable = [version]::new($installedVersion.Major, $installedVersion.Minor, [math]::Max($installedVersion.Build, 0))
        if ($installedComparable -ge $latestVersion -and -not $Force) {
            Write-Output 'Jiffshot is up to date. No action required.'
            exit 0
        }
    }
    else {
        Write-Output 'Jiffshot is not installed.'
    }

    # Select the MSI for the OS architecture; PROCESSOR_ARCHITEW6432 covers 32-bit hosts on 64-bit Windows
    $osArch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $assetArch = if ($osArch -eq 'ARM64') { 'arm64' } else { 'x64' }
    $asset = $release.assets | Where-Object { $_.name -like "Devolutions.Jiffshot-windows-$assetArch-*.msi" } | Select-Object -First 1
    if (-not $asset) {
        throw "No Windows $assetArch MSI found in release $($release.tag_name)."
    }

    # Download the installer
    if (-not (Test-Path -LiteralPath $DownloadPath)) {
        New-Item -Path $DownloadPath -ItemType Directory -Force | Out-Null
    }
    $msiPath = Join-Path -Path $DownloadPath -ChildPath $asset.name
    Save-FileWithFallback -Uri $asset.browser_download_url -Destination $msiPath

    # Verify the download against the digest published by GitHub
    if ($asset.digest -match '^sha256:(?<hash>[0-9a-fA-F]{64})$') {
        $actualHash = (Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash
        if ($actualHash -ne $Matches.hash) {
            Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue
            throw "SHA-256 mismatch for $($asset.name). Expected $($Matches.hash), got $actualHash."
        }
        Write-Output 'SHA-256 verified.'
    }
    else {
        Write-Warning 'No SHA-256 digest published for this asset; skipping hash verification.'
    }

    # Install silently
    $logPath = Join-Path -Path $DownloadPath -ChildPath "Jiffshot-$latestVersion-install.log"
    Write-Output "Installing $($asset.name)..."
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$msiPath`" /qn /norestart /l*v `"$logPath`"" -Wait -PassThru
    if ($process.ExitCode -notin 0, 3010) {
        throw "msiexec failed with exit code $($process.ExitCode). See $logPath."
    }

    Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue
    Write-Output "Jiffshot $latestVersion installed successfully (exit code $($process.ExitCode))."
    exit $process.ExitCode
}
catch {
    Write-Error "Jiffshot install/update failed: $($_.Exception.Message)"
    exit 1
}
