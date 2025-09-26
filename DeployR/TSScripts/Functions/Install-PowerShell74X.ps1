# PowerShell script to download and install the latest PowerShell 7.4.x on Windows

# Function to check for the latest PowerShell 7.4.x release

function Install-PowerShell74X {
    [CmdletBinding()]
    param()
    function Get-LatestRelease {
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases"
        $latest = $releases | Where-Object { $_.tag_name -match '^v7\.4\.\d+$' } | Select-Object -First 1
        return $latest.tag_name.Substring(1) # Remove 'v' from version
    }

    # Function to download file with Start-BitsTransfer and fallback to Invoke-WebRequest
    function Download-File {
        param ($Url, $OutputPath)
        Write-Host "Attempting to download PowerShell using BITS..."
        try {
            Start-BitsTransfer -Source $Url -Destination $OutputPath -ErrorAction Stop
            Write-Host "Download completed using BITS."
        } catch {
            Write-Host "BITS transfer failed: $_"
            Write-Host "Falling back to Invoke-WebRequest..."
            try {
                Invoke-WebRequest -Uri $Url -OutFile $OutputPath -ErrorAction Stop
                Write-Host "Download completed using Invoke-WebRequest."
            } catch {
                Write-Host "Failed to download PowerShell: $_"
                exit 1
            }
        }
    }

    # Function to install PowerShell on Windows
    function Install-Windows {
        param ($Version)
        Write-Host "Downloading PowerShell $Version for Windows..."
        $url = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/PowerShell-$Version-win-x64.msi"
        $tempFile = "$env:USERPROFILE\pwsh-install.msi"

        Download-File -Url $url -OutputPath $tempFile

        Write-Host "Installing PowerShell..."
        $Install = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $tempFile /quiet /norestart" -Wait -NoNewWindow

        if ($Install.ExitCode -ne 0) {
            Write-Host "Installation failed with exit code $($Install.ExitCode)."
        }
        else {
            Write-Host "PowerShell $Version installed successfully."
        }


    }

    # Main script
    $version = Get-LatestRelease
    if (-not $version) {
        Write-Host "Could not find a PowerShell 7.4.x release."
        exit 0
    }

    Install-Windows -Version $version
}