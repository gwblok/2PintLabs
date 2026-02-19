# https://github.com/ip7z/7zip/releases

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
function Install-7ZipFromCloud {
    [CmdletBinding()]
    param(
        [ValidateSet('x64', 'x86')]
        [string]$Architecture = 'x64',

        [string]$DownloadPath = $env:TEMP
    )

    # Get latest 7-Zip info
    $7ZipInfo = Get-7ZipLatestUrl -Architecture $Architecture
    if (-not $7ZipInfo) {
        Write-Error "Failed to retrieve 7-Zip download information."
        return
    }

    $fileName   = [System.IO.Path]::GetFileName($7ZipInfo.URL)
    $destFile   = Join-Path -Path $DownloadPath -ChildPath $fileName

    Write-Verbose "Downloading $($7ZipInfo.AppName) $($7ZipInfo.Version) from $($7ZipInfo.URL)"
    Write-Verbose "Destination: $destFile"

    # --- Download: try BITS first, fall back to Invoke-WebRequest ---
    $downloaded = $false

    try {
        Start-BitsTransfer -Source $7ZipInfo.URL -Destination $destFile -ErrorAction Stop
        $downloaded = $true
        Write-Verbose "Downloaded via BITS successfully."
    }
    catch {
        Write-Warning "BITS transfer failed: $_. Falling back to Invoke-WebRequest."
        try {
            Invoke-WebRequest -Uri $7ZipInfo.URL -OutFile $destFile -UseBasicParsing -ErrorAction Stop
            $downloaded = $true
            Write-Verbose "Downloaded via Invoke-WebRequest successfully."
        }
        catch {
            Write-Error "Invoke-WebRequest also failed: $_"
        }
    }

    if (-not $downloaded) {
        Write-Error "Could not download 7-Zip installer. Aborting installation."
        return
    }

    # --- Install ---
    $installCmd = $7ZipInfo.SilentInstallCommand -replace 'FILENAME', "`"$destFile`""
    Write-Verbose "Running install command: $installCmd"

    $executable = ($installCmd -split ' ')[0]
    $arguments  = $installCmd.Substring($executable.Length).Trim()

    $process = Start-Process -FilePath $executable -ArgumentList $arguments -Wait -PassThru -ErrorAction Stop
    if ($process.ExitCode -eq 0) {
        Write-Verbose "$($7ZipInfo.AppName) $($7ZipInfo.Version) installed successfully."
    }
    else {
        Write-Warning "$($7ZipInfo.AppName) installer exited with code $($process.ExitCode)."
    }

    # Clean up installer
    if (Test-Path $destFile) {
        Remove-Item -Path $destFile -Force -ErrorAction SilentlyContinue
        Write-Verbose "Installer file removed: $destFile"
    }
}

# Run installation
Install-7ZipFromCloud -Verbose