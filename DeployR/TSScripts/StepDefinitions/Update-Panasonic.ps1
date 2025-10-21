write-Host "Installing PanasonicCommandUpdate Module"

# Ensure TLS 1.2 for gallery downloads
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Test-PowerShellGalleryConnectivity {
    <# Returns $true if cdn.powershellgallery.com:443 is reachable #>
    try {
        if (Get-Command -Name Test-NetConnection -ErrorAction SilentlyContinue) {
            $res = Test-NetConnection -ComputerName 'cdn.powershellgallery.com' -Port 443 -WarningAction SilentlyContinue
            return [bool]$res.TcpTestSucceeded
        } else {
            # Fallback using TcpClient
            $client = New-Object System.Net.Sockets.TcpClient
            $iar = $client.BeginConnect('cdn.powershellgallery.com', 443, $null, $null)
            $wait = $iar.AsyncWaitHandle.WaitOne(5000) # 5s
            if ($wait -and $client.Connected) { $client.EndConnect($iar); $client.Close(); return $true } else { return $false }
        }
    } catch {
        return $false
    }
}

function Invoke-PanasonicFallbackInstaller {
    param(
        [string]$FallbackUrl = 'https://dl-pc-support.connect.panasonic.com/public/soft_first/store_app/PanasonicCommandUpdate_SetupFiles_2.10311.0.0_4ec6da73_d20254473.exe'
    )
    try {
        $packageName = [System.IO.Path]::GetFileName($FallbackUrl)
        $tempDir = [System.IO.Path]::GetTempPath()
        $installerPath = Join-Path $tempDir $packageName
        Write-Host "Downloading fallback installer to: $installerPath"
        try {
            Start-BitsTransfer -Source $FallbackUrl -Destination $installerPath -ErrorAction Stop
        } catch {
            Write-Warning "BITS transfer failed or not available, falling back to Invoke-WebRequest: $_"
            Invoke-WebRequest -Uri $FallbackUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        }

        if (Test-Path $installerPath) {
            Write-Host "Fallback installer downloaded: $installerPath"
            try {
                Write-Host "Launching fallback installer (interactive)..."
                Start-Process -FilePath $installerPath -Wait -NoNewWindow -PassThru
            } catch {
                Write-Warning "Failed to launch fallback installer: $_"
            }
        } else {
            Write-Warning "Fallback installer was not downloaded."
        }
    } catch {
        Write-Warning "Fallback download failed: $_"
    }
}

# If the gallery CDN is unreachable, skip Install-Module and use the fallback installer
if (-not (Test-PowerShellGalleryConnectivity)) {
    Write-Warning "Cannot reach PowerShellGallery CDN (cdn.powershellgallery.com). Skipping Install-Module and using fallback installer."
    Invoke-PanasonicFallbackInstaller
} else {
    try {
        # Ensure NuGet package provider is available
        try { Install-PackageProvider -Name NuGet -Force -Scope AllUsers -ErrorAction SilentlyContinue } catch {}
        Install-Module -Name PanasonicCommandUpdate -Force -Verbose -Scope AllUsers -ErrorAction Stop
    }
    catch {
        Write-Warning "Install-Module failed: $($_.Exception.Message) -- falling back to manual installer."
        Invoke-PanasonicFallbackInstaller
    }
}

if (!(Get-Module -Name PanasonicCommandUpdate)){
    Write-Warning "Install-Module failed, attempting fallback download of PanasonicCommandUpdate installer..."
    try {
        $fallbackUrl = 'https://dl-pc-support.connect.panasonic.com/public/soft_first/store_app/PanasonicCommandUpdate_SetupFiles_2.10311.0.0_4ec6da73_d20254473.exe'
        $packageName = [System.IO.Path]::GetFileName($fallbackUrl)
        $tempDir = [System.IO.Path]::GetTempPath()
        $installerPath = Join-Path $tempDir $packageName
        Write-Host "Downloading fallback installer to: $installerPath"
        try {
            Start-BitsTransfer -Source $fallbackUrl -Destination $installerPath -ErrorAction Stop
        } catch {
            Write-Warning "BITS transfer failed or not available, falling back to Invoke-WebRequest: $_"
            Invoke-WebRequest -Uri $fallbackUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        }

        if (Test-Path $installerPath) {
            Write-Host "Fallback installer downloaded: $installerPath"
            try {
                Write-Host "Launching fallback installer (interactive)..."
                Start-Process -FilePath $installerPath -ArgumentList "-s" -Wait -NoNewWindow -PassThru
            } catch {
                Write-Warning "Failed to launch fallback installer: $_"
            }
        } else {
            Write-Warning "Fallback installer was not downloaded."
        }
    } catch {
        Write-Warning "Fallback download failed: $_"
    }
}

if (Get-Module -Name PanasonicCommandUpdate) {
    $ModulePath = (Get-Module -Name PanasonicCommandUpdate).ModuleBase | Split-Path
    Write-Host "PanasonicCommandUpdate Module installed successfully. Copying Files for PS 5." -ForegroundColor Green
    Copy-Item -Path "$ModulePath\*" -Destination "$env:ProgramFiles\WindowsPowerShell\Modules\PanasonicCommandUpdate" -Recurse -Force
} else {
    Write-Host "Failed to install PanasonicCommandUpdate Module." -ForegroundColor Red
    Exit 1
}

Write-Host "Launching Panasonic Update Tool to list Updates in PowerShell v5"
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -command Show-PanasonicUpdate -AcceptLicense" -Wait -PassThru -NoNewWindow

Write-Host "Starting Update Process for Panasonic Drivers and BIOS in PowerShell v5"
Write-Host " Logging to $env:systemdrive\_2p\Logs\PanasonicUpdateOutput.txt"
write-Host '$Updates = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -command Install-PanasonicUpdate -AcceptLicense -Force -Verbose" -PassThru -NoNewWindow -RedirectStandardOutput $Output'
$Output = "$env:systemdrive\_2p\Logs\PanasonicUpdateOutput.txt"
$Updates = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -command Install-PanasonicUpdate -AcceptLicense -Force -Verbose" -PassThru -NoNewWindow -RedirectStandardOutput $Output

$SameLastLine = $null
do {  #Continous loop while PSUPDATE is running
    Start-Sleep -Milliseconds 300
    
    #Read in the DISM Logfile
    $Content = Get-Content -Path $Output -ReadCount 1
    $LastLine = $Content | Select-Object -Last 1
    if ($LastLine){
        if ($SameLastLine -ne $LastLine){ #Only continue if PSUPDATE log has changed
            $SameLastLine = $LastLine
            Write-Output $LastLine
            if ($LastLine -match "Downloading catalog"){
                #Write-Output $LastLine
                $PercentComplete = 1
                Write-Progress -Activity "Updates" -Status 'Downloading catalog...' -PercentComplete $PercentComplete
            }
            elseif ($LastLine -match "Parsing") {
                $PercentComplete = 3
                Write-Progress -Activity "Updates" -Status 'Parsing XML...' -PercentComplete $PercentComplete
            }
            elseif ($LastLine -match "Scanning updates") {
                $PercentComplete = 5
                Write-Progress -Activity "Updates" -Status 'Scanning updates...' -PercentComplete $PercentComplete
            }
            elseif ($LastLine -match "Download updates") {
                $PercentComplete = 10
                Write-Progress -Activity "Updates" -Status 'Download updates...' -PercentComplete $PercentComplete
            }
            elseif ($LastLine -match "Install updates") {
                $PercentComplete = 15
                Write-Progress -Activity "Updates" -Status 'Installing updates...' -PercentComplete $PercentComplete
            }
            elseif ($LastLine -match "RebootRequired") {
                $PercentComplete = 100
                Write-Progress -Activity "Updates" -Status 'Reboot Required' -PercentComplete $PercentComplete
                Start-Sleep -Seconds 3
                break
            }
            elseif ($LastLine -match "downloading :") {
                $ToRemove = "VERBOSE:     "
                $Message = $LastLine.Replace($ToRemove,"")
                # Try to extract a counter/total such as "2 / 3" or "2 of 3" and compute a percent
                $PercentComplete = 0
                if ($Message -match '(?:Installing\s+)?(\d+)\s*/\s*(\d+)') {
                    $counter = [int]$matches[1]
                    $total = [int]$matches[2]
                    if ($total -gt 0) { $PercentComplete = [math]::Round(($counter / $total) * 100) }
                }
                elseif ($Message -match '(?:Installing\s+)?(\d+)\s*of\s*(\d+)') {
                    $counter = [int]$matches[1]
                    $total = [int]$matches[2]
                    if ($total -gt 0) { $PercentComplete = [math]::Round(($counter / $total) * 100) }
                }
                Write-Progress -Activity "Downloading Updates" -Status $Message -PercentComplete $PercentComplete
            }
            elseif ($LastLine -match "installing :") {
                $ToRemove = "VERBOSE: "
                $Message = $LastLine.Replace($ToRemove,"")
                # Try to extract a counter/total such as "2 / 3" or "2 of 3" and compute a percent
                $PercentComplete = 0
                if ($Message -match '(?:Installing\s+)?(\d+)\s*/\s*(\d+)') {
                    $counter = [int]$matches[1]
                    $total = [int]$matches[2]
                    if ($total -gt 0) { $PercentComplete = [math]::Round(($counter / $total) * 100) }
                }
                elseif ($Message -match '(?:Installing\s+)?(\d+)\s*of\s*(\d+)') {
                    $counter = [int]$matches[1]
                    $total = [int]$matches[2]
                    if ($total -gt 0) { $PercentComplete = [math]::Round(($counter / $total) * 100) }
                }
                Write-Progress -Activity "Installing Updates" -Status $Message -PercentComplete $PercentComplete
            }
            else  {
                $PercentComplete = $PercentComplete #AKA, Use the last PercentComplete value available
                $Message = $null
                Write-Progress -Activity "Panasonic Update" -Status $Message -PercentComplete $PercentComplete
            }
        }
    }
    
}
until (!(Get-Process -Id $Updates.Id -ErrorAction SilentlyContinue))