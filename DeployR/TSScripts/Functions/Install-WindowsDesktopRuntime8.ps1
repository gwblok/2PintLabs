function Install-WindowsDesktopRuntime8 {
    [CmdletBinding()]
    param(
        [string]$InitialVersion = '8.0.21',
        [string]$DownloadDirectory = "$env:TEMP\.NET8Installers"
    )

    function Test-UrlExists {
        param (
            [string]$Url
        )
        try {
            $response = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -ErrorAction Stop
            return $response.StatusCode -eq 200
        } catch {
            return $false
        }
    }

    function Get-LatestWindowsDesktopRuntime8Version {
        param(
            [string]$BaseVersion
        )

        $baseUrl = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/{0}/windowsdesktop-runtime-{0}-win-x64.exe"
        $latestVersion = $BaseVersion
        $maxAttempts = 100

        Write-Host "Searching for the latest Windows Desktop Runtime 8 version starting from $BaseVersion..."

        $versionParts = $BaseVersion.Split('.')
        $major = [int]$versionParts[0]
        $minor = [int]$versionParts[1]
        $patch = [int]$versionParts[2]

        for ($i = 0; $i -lt $maxAttempts; $i++) {
            $currentPatch = $patch + $i
            $currentVersion = "$major.$minor.$currentPatch"
            $url = $baseUrl -f $currentVersion

            if (Test-UrlExists -Url $url) {
                $latestVersion = $currentVersion
                Write-Host "Found valid version: $latestVersion"
            } else {
                if ($currentPatch -gt $patch) {
                    break
                }
            }
        }

        return $latestVersion
    }

    function Download-File {
        param (
            [string]$Url,
            [string]$FilePath
        )
        try {
            if (-not (Test-Path -Path $FilePath)) {
                Write-Host "Attempting to download from $Url using BITS..."
                Start-BitsTransfer -Source $Url -Destination $FilePath -ErrorAction Stop
                Write-Host "Download completed using BITS: $FilePath"
            } else {
                Write-Host "File already exists: $FilePath"
            }
        } catch {
            Write-Host "BITS transfer failed, falling back to Invoke-WebRequest for $Url..."
            if (-not (Test-Path -Path $FilePath)) {
                Invoke-WebRequest -Uri $Url -OutFile $FilePath -UseBasicParsing -ErrorAction Stop
                Write-Host "Download completed using Invoke-WebRequest: $FilePath"
            } else {
                Write-Host "File already exists: $FilePath"
            }
        }
    }

    $latestVersion = Get-LatestWindowsDesktopRuntime8Version -BaseVersion $InitialVersion
    Write-Host "Latest version detected: $latestVersion"

    $desktopRuntimeUrl = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/$latestVersion/windowsdesktop-runtime-$latestVersion-win-x64.exe"
    Write-Host "Identified URL for download:"
    Write-Host "- Windows Desktop Runtime: $desktopRuntimeUrl"

    if (-not (Test-Path -Path $DownloadDirectory)) {
        New-Item -ItemType Directory -Path $DownloadDirectory -Force | Out-Null
    }

    $desktopRuntimeFile = Join-Path -Path $DownloadDirectory -ChildPath "windowsdesktop-runtime-$latestVersion-win-x64.exe"

    Download-File -Url $desktopRuntimeUrl -FilePath $desktopRuntimeFile

    Write-Host "Installing Windows Desktop Runtime $latestVersion..."
    if (Test-Path -Path $desktopRuntimeFile) {
        Start-Process -FilePath $desktopRuntimeFile -ArgumentList "/quiet", "/norestart" -Wait -NoNewWindow
        Write-Host "Windows Desktop Runtime installation completed."
        return $true
    }

    Write-Host "Windows Desktop Runtime installer not found. Skipping installation."
    return $false
}