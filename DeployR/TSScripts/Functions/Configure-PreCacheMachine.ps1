<#
.SYNOPSIS
    Configures the BranchCache cache on the local machine for pre-caching scenarios.

.DESCRIPTION
    Gathers current BranchCache cache statistics (location, current size, max size, percent used, etc.),
    reports them, then applies the following settings:

    - Client Mode: DistributedCache (enables peer-to-peer content sharing)
    - Cache Size: 25% of the disk volume
    - Max Cache Age: 365 days (1 year)
    - RepubQuorumr tSize: 100 (registry key that controls how many responses are needed
      before content is marked "not peerable"; default is 10, which can cause issues
      in environments with many devices - see 2Pint Software article:
      https://2pintsoftware.com/news/details/optimizing-branchcache-with-repubquorumsize-an-undocumented-yet-crucial-tweak)

.NOTES
    Requires elevation (Run as Administrator).
    Requires the BranchCache feature to be enabled. (Run after the Enable BranchCache Step)
    Restarts the BranchCache service (PeerDistSvc) after applying RepubQuorumSize.
#>

#Requires -RunAsAdministrator

# --- Gather Current BranchCache Cache Info ---

$BCStatus = Get-BCStatus
$BCDataCache = Get-BCDataCache
$CurrentClientMode = $BCStatus.ClientConfiguration.CurrentClientMode

# Get the cache file location
$CacheLocation = $BCDataCache.CacheFileDirectoryPath
if (-not $CacheLocation) {
    $CacheLocation = "$env:SystemDrive\Windows\ServiceProfiles\NetworkService\AppData\Local\PeerDistRepub"
}

# Get the volume where the cache resides
$CacheDriveLetter = (Split-Path -Path $CacheLocation -Qualifier)
$Volume = Get-Volume -DriveLetter ($CacheDriveLetter.TrimEnd(':'))

# Current cache stats
$CurrentSizeBytes = $BCDataCache.CurrentActiveCacheSize
$CurrentSizeOnDisk = $BCDataCache.CurrentSizeOnDiskAsNumberOfBytes
$MaxSizePercent = $BCDataCache.MaxCacheSizeAsPercentageOfDiskVolume
$MaxSizeBytes = $BCDataCache.MaxCacheSizeAsNumberOfBytes

if ($CurrentSizeBytes -gt 0 -and $MaxSizeBytes -gt 0) {
    $PercentUsed = [math]::Round(($CurrentSizeBytes / $MaxSizeBytes) * 100, 2)
} else {
    $PercentUsed = 0
}

# Format sizes for display
function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes Bytes"
}

$VolumeSize = $Volume.Size
$VolumeFreeSpace = $Volume.SizeRemaining

# RepubQuorumSize - controls how many responses before content is marked "not peerable" (default: 10)
$RepubQuorumRegPath = 'HKLM:\Software\Policies\Microsoft\PeerDist\DiscoveryManager'
$RepubQuorumValue = (Get-ItemProperty -Path $RepubQuorumRegPath -Name 'RepubQuorumSize' -ErrorAction SilentlyContinue).RepubQuorumSize
if ($null -eq $RepubQuorumValue) {
    $RepubQuorumDisplay = '10 (Default - not set)'
} else {
    $RepubQuorumDisplay = "$RepubQuorumValue"
}

# --- Report Current Stats ---

Write-Output "============================================"
Write-Output "  BranchCache Cache - Current Configuration"
Write-Output "============================================"
Write-Output "Client Mode          : $CurrentClientMode"
Write-Output "Cache Location       : $CacheLocation"
Write-Output "Cache Drive          : $CacheDriveLetter"
Write-Output "Volume Total Size    : $(Format-Size $VolumeSize)"
Write-Output "Volume Free Space    : $(Format-Size $VolumeFreeSpace)"
Write-Output "Current Cache Size   : $(Format-Size $CurrentSizeBytes)"
Write-Output "Size on Disk         : $(Format-Size $CurrentSizeOnDisk)"
Write-Output "Max Cache Size (%)   : $MaxSizePercent%"
Write-Output "Max Cache Size       : $(Format-Size $MaxSizeBytes)"
Write-Output "Cache Used           : $PercentUsed%"
Write-Output "RepubQuorumSize      : $RepubQuorumDisplay"
Write-Output "============================================"

# --- Ensure DistributedCache Mode ---

if ($CurrentClientMode -ne 'DistributedCache') {
    Write-Output ""
    Write-Output "Client mode is '$CurrentClientMode' - setting to DistributedCache..."
    Enable-BCDistributed -Force
    $BCStatus = Get-BCStatus
    Write-Output "Client mode is now: $($BCStatus.ClientConfiguration.CurrentClientMode)"
} else {
    Write-Output ""
    Write-Output "Client mode is already DistributedCache - no change needed."
}

# --- Configure New Settings ---

$NewMaxSizePercent = 25
$NewMaxAgeDays = 365  # 1 year

Write-Output ""
Write-Output "Applying new BranchCache cache settings..."
Write-Output "  New Max Cache Size : $NewMaxSizePercent% of disk"
Write-Output "  New Max Cache Age  : $NewMaxAgeDays days"

# Set cache size to 25% of the filesystem
Set-BCCache -Percentage $NewMaxSizePercent -Force

# Set max age to 1 year
Set-BCDataCacheEntryMaxAge -TimeDays $NewMaxAgeDays -Force

# Set RepubQuorumSize to 100 (increases responses needed before content marked "not peerable")
$NewRepubQuorumSize = 100
if (-not (Test-Path -Path $RepubQuorumRegPath)) {
    New-Item -Path $RepubQuorumRegPath -Force | Out-Null
}
Set-ItemProperty -Path $RepubQuorumRegPath -Name 'RepubQuorumSize' -Value $NewRepubQuorumSize -Type DWord -Force
Write-Output "  RepubQuorumSize set to $NewRepubQuorumSize - restarting BranchCache service..."
Restart-Service -Name PeerDistSvc -Force

# --- Verify New Settings ---

$BCDataCacheNew = Get-BCDataCache

$NewAppliedPercent = $BCDataCacheNew.MaxCacheSizeAsPercentageOfDiskVolume
$NewMaxSizeBytes = $BCDataCacheNew.MaxCacheSizeAsNumberOfBytes
$NewCurrentSizeBytes = $BCDataCacheNew.CurrentActiveCacheSize
$NewSizeOnDisk = $BCDataCacheNew.CurrentSizeOnDiskAsNumberOfBytes

Write-Output ""
$BCStatusNew = Get-BCStatus
$NewClientMode = $BCStatusNew.ClientConfiguration.CurrentClientMode

Write-Output "============================================"
Write-Output "  BranchCache Cache - Updated Configuration"
Write-Output "============================================"
Write-Output "Client Mode          : $NewClientMode"
Write-Output "Current Cache Size   : $(Format-Size $NewCurrentSizeBytes)"
Write-Output "Size on Disk         : $(Format-Size $NewSizeOnDisk)"
Write-Output "Max Cache Size (%)   : $NewAppliedPercent%"
Write-Output "Max Cache Size       : $(Format-Size $NewMaxSizeBytes)"
$NewRepubQuorumValue = (Get-ItemProperty -Path $RepubQuorumRegPath -Name 'RepubQuorumSize' -ErrorAction SilentlyContinue).RepubQuorumSize
Write-Output "RepubQuorumSize      : $NewRepubQuorumValue"
Write-Output "============================================"
Write-Output "BranchCache cache configuration complete."
