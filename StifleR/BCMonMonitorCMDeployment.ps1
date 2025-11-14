#Update the $BCMonServerDir with where you're keeping the latest copy of the BCMON tool



# Local and server directories
$BCMonLocalDir = "C:\Windows\System32"
$BCMonServerDir = "\\src\src$\Apps\2pint\BCMon-2.6.2511.1"
$fileList = @("BCMon.Net.exe", "appsettings.json", "BCMon.Net.exe.config")


# Full paths to the EXE used for comparison
$BCMonLocalPath = Join-Path -Path $BCMonLocalDir -ChildPath "BCMon.Net.exe"
$BCMonServerPath = Join-Path -Path $BCMonServerDir -ChildPath "BCMon.Net.exe"

function Get-FileProductVersion {
    param(
        [string]$Path
    )
    if (-not (Test-Path $Path)) { return $null }
    try {
        $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        if ($info.FileVersion) { return $info.FileVersion }
        if ($info.ProductVersion) { return $info.ProductVersion }
    }
    catch {
        return $null
    }
    return $null
}

function Parse-VersionSafe {
    param([string]$ver)
    if (-not $ver) { return $null }
    try { return [version]($ver -replace '[^0-9\.]','') }
    catch { return $null }
}

Write-Host "Checking BCMon local and server files..." -ForegroundColor Cyan

# Ensure server EXE exists
if (-not (Test-Path -Path $BCMonServerPath)) {
    Write-Warning "Server EXE not reachable: $BCMonServerPath. Aborting update check."
}
else {
    $localExists = Test-Path -Path $BCMonLocalPath
    if (-not $localExists) {
        Write-Host "Local BCMon not found. Copying files from server..." -ForegroundColor Yellow
        foreach ($f in $fileList) {
            $src = Join-Path $BCMonServerDir $f
            if (Test-Path $src) {
                Copy-Item -Path $src -Destination $BCMonLocalDir -Force
                Write-Host "  Copied: $src -> $BCMonLocalDir" -ForegroundColor Green
            }
            else { Write-Warning "  Missing on server: $src" }
        }
    }
    else {
        # Compare server EXE version/timestamp only. If server EXE is newer, copy all files in list.
        $serverVerStr = Get-FileProductVersion -Path $BCMonServerPath
        $localVerStr  = Get-FileProductVersion -Path $BCMonLocalPath

        $serverVer = Parse-VersionSafe $serverVerStr
        $localVer  = Parse-VersionSafe $localVerStr

        $shouldUpdate = $false
        if ($serverVer -and $localVer) {
            Write-Host "Local version: $localVerStr  | Server version: $serverVerStr" -ForegroundColor Gray
            if ($serverVer -gt $localVer) { $shouldUpdate = $true }
        }
        else {
            # Fallback to LastWriteTime comparison when version info not available
            $serverTime = (Get-Item $BCMonServerPath).LastWriteTimeUtc
            $localTime  = (Get-Item $BCMonLocalPath).LastWriteTimeUtc
            Write-Host "Local timestamp: $localTime  | Server timestamp: $serverTime" -ForegroundColor Gray
            if ($serverTime -gt $localTime) { $shouldUpdate = $true }
        }

        if ($shouldUpdate) {
            Write-Host "Server EXE is newer. Copying all files to local folder..." -ForegroundColor Yellow
            foreach ($f in $fileList) {
                $src = Join-Path $BCMonServerDir $f
                if (Test-Path $src) {
                    Copy-Item -Path $src -Destination $BCMonLocalDir -Force
                    Write-Host "  Copied: $src -> $BCMonLocalDir" -ForegroundColor Green
                }
                else { Write-Warning "  Missing on server: $src" }
            }
        }
        else {
            Write-Host "Local BCMon is up-to-date." -ForegroundColor Green
        }
    }
}

# Monitor jobs Live
write-host "Looking for CM BITS jobs to Monitor" -ForegroundColor Cyan
$jobs = (Get-BitsTransfer -AllUsers | Where-Object {$_.DisplayName -match "CCMDTS"})
if ($jobs){
    write-host "Found Jobs, BCMonning them now"
}
else{
    Write-Host "Bummer, no CM jobs to monitor" -ForegroundColor Yellow
}
foreach ($Job in $jobs) {
    Write-Host "Starting Monitor of $($Job.JobId)" -ForegroundColor Green
    write-Host " - $($Job.DisplayName),  $($Job.Description)"
    write-host " - $($job.FileList.remotename[0])"
    Start-Process cmd.exe -ArgumentList "/k BCMon.Net.exe BITS Realtime $($job.jobid)"
}

# Get Overview (example commands left commented)
# $BCInfo = Start-Process cmd.exe -ArgumentList "/c /wait bcmon /BITS /Analyse" -PassThru
# bcmon.net /BITS /Analyse
#bcmon.net /BITS /Analyse