<#
.SYNOPSIS
    Perform internet and DeployR server speed tests and store results in Task Sequence variables.

.DESCRIPTION
    This function performs download speed tests from both internet sources and the DeployR server.
    Results are written to Task Sequence variables for use in deployment logic.
    
    Tests performed:
    - Internet download speed using Speedtest CLI (or fallback to direct download test)
    - DeployR server download speed using a test file from the server
    - Upload speed (when using Speedtest CLI)
    - Ping and latency metrics

.PARAMETER DeployRServerPath
    UNC path to DeployR server. If not specified, attempts to get from TSEnv:DEPLOYR-SERVER variable.

.PARAMETER TestFileSize
    Size of test file to download from DeployR server. Options: Small (10MB), Medium (100MB), Large (500MB).
    Default: Medium

.PARAMETER SkipInternetTest
    Skip the internet speed test and only test DeployR server connection.

.PARAMETER OutputPath
    Optional path to save detailed results as JSON. Useful for logging and troubleshooting.

.EXAMPLE
    Invoke-SpeedTest
    Runs both internet and DeployR server speed tests, stores results in TS variables.

.EXAMPLE
    Invoke-SpeedTest -DeployRServerPath "\\deployr-server\DeployRContent" -TestFileSize Large
    Tests with a large file from the specified DeployR server.

.EXAMPLE
    Invoke-SpeedTest -SkipInternetTest -OutputPath "C:\Logs\speedtest.json"
    Only tests DeployR server speed and saves results to file.

.NOTES
    Task Sequence Variables Created:
    - SPEEDTEST-InternetDownloadMbps
    - SPEEDTEST-InternetUploadMbps
    - SPEEDTEST-InternetPingMs
    - SPEEDTEST-DeployRDownloadMbps
    - SPEEDTEST-DeployRPingMs
    - SPEEDTEST-ISP
    - SPEEDTEST-Timestamp
#>

function Invoke-SpeedTest {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$DeployRServerPath,
        
        [Parameter()]
        [ValidateSet('Small', 'Medium', 'Large')]
        [string]$TestFileSize = 'Medium',
        
        [Parameter()]
        [switch]$SkipInternetTest,
        
        [Parameter()]
        [string]$OutputPath
    )
    
    # Try to import DeployR.Utility module for TS integration
    $inTaskSequence = $false
    try {
        Import-Module DeployR.Utility -ErrorAction Stop
        $inTaskSequence = $true
        Write-Host "Running in Task Sequence context" -ForegroundColor Cyan
    }
    catch {
        Write-Host "Running outside Task Sequence (standalone mode)" -ForegroundColor Yellow
    }
    
    # Initialize results object
    $results = [PSCustomObject]@{
        Timestamp = Get-Date
        InternetTest = $null
        DeployRTest = $null
        Success = $true
        Errors = @()
    }
    
    #region Internet Speed Test
    if (-not $SkipInternetTest) {
        Write-Host "`n=== Internet Speed Test ===" -ForegroundColor Green
        
        try {
            $internetResult = Test-InternetSpeed
            $results.InternetTest = $internetResult
            
            Write-Host "  ISP: $($internetResult.ISP)" -ForegroundColor White
            Write-Host "  Download: $($internetResult.DownloadMbps) Mbps" -ForegroundColor Cyan
            Write-Host "  Upload: $($internetResult.UploadMbps) Mbps" -ForegroundColor Cyan
            Write-Host "  Ping: $($internetResult.PingMs) ms" -ForegroundColor Cyan
            
            # Set TS Variables for Internet Test
            if ($inTaskSequence) {
                Set-TSVariable -Name "SPEEDTEST-InternetDownloadMbps" -Value $internetResult.DownloadMbps
                Set-TSVariable -Name "SPEEDTEST-InternetUploadMbps" -Value $internetResult.UploadMbps
                Set-TSVariable -Name "SPEEDTEST-InternetPingMs" -Value $internetResult.PingMs
                Set-TSVariable -Name "SPEEDTEST-ISP" -Value $internetResult.ISP
                Write-Host "  TS Variables set for internet test" -ForegroundColor Gray
            }
        }
        catch {
            $errorMsg = "Internet speed test failed: $_"
            Write-Warning $errorMsg
            $results.Errors += $errorMsg
            $results.Success = $false
        }
    }
    #endregion
    
    #region DeployR Server Speed Test
    Write-Host "`n=== DeployR Server Speed Test ===" -ForegroundColor Green
    
    # Determine DeployR server path
    if (-not $DeployRServerPath) {
        if ($inTaskSequence) {
            $DeployRServerPath = Get-TSVariable -Name "DEPLOYR-SERVER" -ErrorAction SilentlyContinue
        }
        
        if (-not $DeployRServerPath) {
            # Try common default paths
            $possiblePaths = @(
                "\\deployr\DeployRContent",
                "\\deployr-server\DeployRContent",
                "\\deployr.corp.local\DeployRContent"
            )
            
            foreach ($path in $possiblePaths) {
                if (Test-Path $path -ErrorAction SilentlyContinue) {
                    $DeployRServerPath = $path
                    Write-Host "  Auto-detected DeployR server: $DeployRServerPath" -ForegroundColor Gray
                    break
                }
            }
        }
    }
    
    if ($DeployRServerPath) {
        try {
            $deployRResult = Test-DeployRSpeed -ServerPath $DeployRServerPath -TestFileSize $TestFileSize
            $results.DeployRTest = $deployRResult
            
            Write-Host "  Server: $DeployRServerPath" -ForegroundColor White
            Write-Host "  Download: $($deployRResult.DownloadMbps) Mbps" -ForegroundColor Cyan
            Write-Host "  Ping: $($deployRResult.PingMs) ms" -ForegroundColor Cyan
            Write-Host "  File Size: $($deployRResult.FileSizeMB) MB" -ForegroundColor Gray
            Write-Host "  Duration: $($deployRResult.DurationSeconds) seconds" -ForegroundColor Gray
            
            # Set TS Variables for DeployR Test
            if ($inTaskSequence) {
                Set-TSVariable -Name "SPEEDTEST-DeployRDownloadMbps" -Value $deployRResult.DownloadMbps
                Set-TSVariable -Name "SPEEDTEST-DeployRPingMs" -Value $deployRResult.PingMs
                Set-TSVariable -Name "SPEEDTEST-DeployRServer" -Value $DeployRServerPath
                Write-Host "  TS Variables set for DeployR test" -ForegroundColor Gray
            }
        }
        catch {
            $errorMsg = "DeployR server speed test failed: $_"
            Write-Warning $errorMsg
            $results.Errors += $errorMsg
            $results.Success = $false
        }
    }
    else {
        $errorMsg = "DeployR server path not specified or detected"
        Write-Warning $errorMsg
        $results.Errors += $errorMsg
    }
    #endregion
    
    # Set timestamp variable
    if ($inTaskSequence) {
        Set-TSVariable -Name "SPEEDTEST-Timestamp" -Value $results.Timestamp.ToString("yyyy-MM-dd HH:mm:ss")
    }
    
    # Save results to file if requested
    if ($OutputPath) {
        try {
            $results | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Force
            Write-Host "`nResults saved to: $OutputPath" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to save results to file: $_"
        }
    }
    
    # Summary
    Write-Host "`n=== Speed Test Summary ===" -ForegroundColor Green
    if ($results.InternetTest) {
        Write-Host "Internet Download: $($results.InternetTest.DownloadMbps) Mbps" -ForegroundColor White
    }
    if ($results.DeployRTest) {
        Write-Host "DeployR Download: $($results.DeployRTest.DownloadMbps) Mbps" -ForegroundColor White
    }
    if ($results.Errors.Count -gt 0) {
        Write-Host "Errors encountered: $($results.Errors.Count)" -ForegroundColor Red
    }
    
    return $results
}

function Test-InternetSpeed {
    <#
    .SYNOPSIS
        Test internet speed using Speedtest CLI or fallback method
    #>
    [CmdletBinding()]
    param()
    
    $speedtestExe = "$env:TEMP\speedtest.exe"
    
    # Try to use Speedtest CLI
    if (Test-Path $speedtestExe) {
        Write-Host "  Using cached Speedtest CLI" -ForegroundColor Gray
    }
    else {
        Write-Host "  Downloading Speedtest CLI..." -ForegroundColor Gray
        try {
            # Download Speedtest CLI
            $url = "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip"
            $zipPath = "$env:TEMP\speedtest.zip"
            
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -TimeoutSec 30
            Expand-Archive -Path $zipPath -DestinationPath $env:TEMP -Force
            Remove-Item $zipPath -Force
            
            if (-not (Test-Path $speedtestExe)) {
                throw "Speedtest CLI extraction failed"
            }
        }
        catch {
            Write-Warning "  Failed to download Speedtest CLI, using fallback method"
            return Test-InternetSpeedFallback
        }
    }
    
    # Run Speedtest CLI
    try {
        Write-Host "  Running Speedtest CLI (this may take 30-60 seconds)..." -ForegroundColor Gray
        $jsonResult = & $speedtestExe --accept-license --accept-gdpr --format=json 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "Speedtest CLI returned error code $LASTEXITCODE"
        }
        
        $result = $jsonResult | ConvertFrom-Json
        
        return [PSCustomObject]@{
            ISP = $result.isp
            Server = $result.server.name
            ServerLocation = $result.server.location
            DownloadMbps = [math]::Round($result.download.bandwidth / 125000, 2)
            UploadMbps = [math]::Round($result.upload.bandwidth / 125000, 2)
            PingMs = [math]::Round($result.ping.latency, 2)
            Jitter = [math]::Round($result.ping.jitter, 2)
            PacketLoss = $result.packetLoss
            ResultUrl = $result.result.url
            Method = "SpeedtestCLI"
        }
    }
    catch {
        Write-Warning "  Speedtest CLI failed: $_, using fallback method"
        return Test-InternetSpeedFallback
    }
}

function Test-InternetSpeedFallback {
    <#
    .SYNOPSIS
        Fallback internet speed test using direct download
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "  Using fallback download test..." -ForegroundColor Gray
    
    # List of test file URLs (try multiple sources for reliability)
    $testFiles = @(
        @{ Url = "http://speedtest.tele2.net/100MB.zip"; Size = 100 },
        @{ Url = "http://ipv4.download.thinkbroadband.com/100MB.zip"; Size = 100 },
        @{ Url = "http://proof.ovh.net/files/100Mb.dat"; Size = 100 }
    )
    
    $tempFile = "$env:TEMP\speedtest_download.tmp"
    
    foreach ($testFile in $testFiles) {
        try {
            Write-Host "  Testing download from: $($testFile.Url)" -ForegroundColor Gray
            
            $start = Get-Date
            Invoke-WebRequest -Uri $testFile.Url -OutFile $tempFile -UseBasicParsing -TimeoutSec 60
            $end = Get-Date
            
            $duration = ($end - $start).TotalSeconds
            $fileSize = (Get-Item $tempFile).Length
            $speedMbps = [math]::Round(($fileSize * 8 / $duration / 1MB), 2)
            
            # Clean up
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            
            # Try to get ISP info from ipinfo.io
            $isp = "Unknown"
            try {
                $ipInfo = Invoke-RestMethod -Uri "https://ipinfo.io/json" -TimeoutSec 5
                $isp = $ipInfo.org
            }
            catch {
                Write-Verbose "Could not retrieve ISP info"
            }
            
            return [PSCustomObject]@{
                ISP = $isp
                Server = $testFile.Url
                ServerLocation = "Internet"
                DownloadMbps = $speedMbps
                UploadMbps = 0  # Not tested in fallback
                PingMs = 0      # Not tested in fallback
                Jitter = 0
                PacketLoss = 0
                ResultUrl = $null
                Method = "FallbackDownload"
            }
        }
        catch {
            Write-Verbose "Test file failed: $($testFile.Url) - $_"
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            continue
        }
    }
    
    throw "All internet speed test methods failed"
}

function Test-DeployRSpeed {
    <#
    .SYNOPSIS
        Test download speed from DeployR server
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerPath,
        
        [Parameter()]
        [ValidateSet('Small', 'Medium', 'Large')]
        [string]$TestFileSize = 'Medium'
    )
    
    # Verify server is accessible
    if (-not (Test-Path $ServerPath)) {
        throw "DeployR server path not accessible: $ServerPath"
    }
    
    # Determine test file size
    $fileSizeMB = switch ($TestFileSize) {
        'Small'  { 10 }
        'Medium' { 100 }
        'Large'  { 500 }
    }
    
    # Create or locate test file on server
    $testFileName = "SpeedTest_$($fileSizeMB)MB.dat"
    $serverTestFile = Join-Path $ServerPath $testFileName
    $localTestFile = "$env:TEMP\deployr_speedtest.tmp"
    
    # Check if test file exists, create if not
    if (-not (Test-Path $serverTestFile)) {
        Write-Host "  Creating test file on server ($fileSizeMB MB)..." -ForegroundColor Gray
        try {
            # Create a file filled with random data
            $bytes = New-Object byte[] (1MB)
            $random = New-Object System.Random
            
            $stream = [System.IO.File]::OpenWrite($serverTestFile)
            for ($i = 0; $i -lt $fileSizeMB; $i++) {
                $random.NextBytes($bytes)
                $stream.Write($bytes, 0, $bytes.Length)
            }
            $stream.Close()
            
            Write-Host "  Test file created successfully" -ForegroundColor Gray
        }
        catch {
            throw "Failed to create test file on server: $_"
        }
    }
    
    # Test ping/latency to server
    $serverName = ($ServerPath -split '\\')[2]
    $pingMs = 0
    try {
        $pingResult = Test-Connection -ComputerName $serverName -Count 3 -ErrorAction Stop
        $pingMs = [math]::Round(($pingResult | Measure-Object -Property ResponseTime -Average).Average, 2)
        Write-Host "  Server ping: $pingMs ms" -ForegroundColor Gray
    }
    catch {
        Write-Verbose "Ping test failed: $_"
    }
    
    # Perform download speed test
    Write-Host "  Downloading test file from DeployR server..." -ForegroundColor Gray
    
    $start = Get-Date
    Copy-Item -Path $serverTestFile -Destination $localTestFile -Force
    $end = Get-Date
    
    $duration = ($end - $start).TotalSeconds
    $fileSize = (Get-Item $localTestFile).Length
    $speedMbps = [math]::Round(($fileSize * 8 / $duration / 1MB), 2)
    
    # Clean up local test file
    Remove-Item $localTestFile -Force -ErrorAction SilentlyContinue
    
    return [PSCustomObject]@{
        ServerPath = $ServerPath
        ServerName = $serverName
        FileSizeMB = [math]::Round($fileSize / 1MB, 2)
        DurationSeconds = [math]::Round($duration, 2)
        DownloadMbps = $speedMbps
        PingMs = $pingMs
        TestFileUsed = $testFileName
    }
}

# Helper functions for TS variable management when not in TS
function Set-TSVariable {
    param($Name, $Value)
    
    if (Get-Command -Name "Set-TSVariable" -ErrorAction SilentlyContinue) {
        # Use actual TS command
        Microsoft.BDD.TaskSequenceModule\Set-TSVariable -Name $Name -Value $Value
    }
    else {
        # Store in environment variable for standalone testing
        [Environment]::SetEnvironmentVariable("TS_$Name", $Value, "Process")
        Write-Verbose "Set environment variable: TS_$Name = $Value"
    }
}

function Get-TSVariable {
    param($Name)
    
    if (Get-Command -Name "Get-TSVariable" -ErrorAction SilentlyContinue) {
        return Microsoft.BDD.TaskSequenceModule\Get-TSVariable -Name $Name
    }
    else {
        return [Environment]::GetEnvironmentVariable("TS_$Name", "Process")
    }
}

# Export the main function
Export-ModuleMember -Function Invoke-SpeedTest
