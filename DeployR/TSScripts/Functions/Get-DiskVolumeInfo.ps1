<#
.SYNOPSIS
Collects and displays disk, partition, volume, and BitLocker details.

.DESCRIPTION
Queries local storage configuration and writes a readable report to the console.
For each disk, the script enumerates partitions, maps partitions to volumes where
possible, and adds BitLocker protection/protector details for each volume.

.NOTES
- Intended for interactive troubleshooting and inventory visibility.
- Output is console-focused (Write-Host) for easy reading in task sequence logs
  and live PowerShell sessions.
- Some partition types (MSR/EFI/Recovery) may not expose full volume or
  BitLocker metadata.

.EXAMPLE
Get-DiskVolumeInfo
#>

function Get-DiskVolumeInfo {
	[CmdletBinding()]
	param()

	# Header for the inventory report.
	Write-Host "=== Disk and Volume Information ===" -ForegroundColor Cyan

	# Gather all disks first so we can provide a structured report.
	try {
		$disks = Get-Disk | Sort-Object Number
	}
	catch {
		Write-Host "Failed to retrieve disk information: $($_.Exception.Message)" -ForegroundColor Red
		return
	}

	if (-not $disks) {
		Write-Host "No disks were found on this system." -ForegroundColor Yellow
		return
	}

	# Walk each disk and then drill down into partitions and volumes.
	foreach ($disk in $disks) {
		Write-Host "" 
		Write-Host ("Disk {0}: {1}" -f $disk.Number, $disk.FriendlyName) -ForegroundColor Green
		Write-Host ("  Serial Number : {0}" -f ($disk.SerialNumber | ForEach-Object { if ([string]::IsNullOrWhiteSpace($_)) { 'N/A' } else { $_ } }))
		Write-Host ("  Bus Type      : {0}" -f $disk.BusType)
		Write-Host ("  PartitionStyle: {0}" -f $disk.PartitionStyle)
		Write-Host ("  Operational   : {0}" -f $disk.OperationalStatus)
		Write-Host ("  Health Status : {0}" -f $disk.HealthStatus)
		Write-Host ("  Is Boot       : {0}" -f $disk.IsBoot)
		Write-Host ("  Is System     : {0}" -f $disk.IsSystem)
		Write-Host ("  Size (GB)     : {0:N2}" -f ($disk.Size / 1GB))

		# Query partitions on this disk. Continue to next disk if that fails.
		$partitions = @()
		try {
			$partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction Stop | Sort-Object PartitionNumber
		}
		catch {
			Write-Host "  Unable to read partitions for this disk." -ForegroundColor Yellow
			continue
		}

		if (-not $partitions) {
			Write-Host "  No partitions found on this disk." -ForegroundColor Yellow
			continue
		}

		# Report each partition and enrich with volume/BitLocker details when available.
		foreach ($partition in $partitions) {
			# Normalize drive letter display for partitions that do not have one assigned.
			$driveLetter = 'N/A'
			if ("$($partition.DriveLetter)" -match '^[A-Z]$') {
				$driveLetter = "$($partition.DriveLetter)"
			}

			# Not all partitions map to a volume object; keep this non-fatal.
			$volume = $null
			try {
				$volume = $partition | Get-Volume -ErrorAction Stop
			}
			catch {
				# Some partitions do not expose a volume (for example: MSR, recovery, EFI).
			}

			Write-Host ("  Partition {0}" -f $partition.PartitionNumber) -ForegroundColor White
			Write-Host ("    Type             : {0}" -f $partition.Type)
			Write-Host ("    Drive Letter     : {0}" -f $driveLetter)
			Write-Host ("    Gpt Type         : {0}" -f ($(if ([string]::IsNullOrWhiteSpace($partition.GptType)) { 'N/A' } else { $partition.GptType })))
			Write-Host ("    Size (GB)        : {0:N2}" -f ($partition.Size / 1GB))
			Write-Host ("    Offset (MB)      : {0:N2}" -f ($partition.Offset / 1MB))

			if ($volume) {
				# Initialize defaults in case BitLocker data cannot be resolved.
				$bitLockerStatus = 'N/A'
				$protectorTypes = 'N/A'

				# Resolve BitLocker data from a usable mount point (drive letter or volume path).
				try {
					$mountPoint = $null
					if ($driveLetter -ne 'N/A') {
						$mountPoint = "${driveLetter}:"
					}
					elseif (-not [string]::IsNullOrWhiteSpace($volume.Path)) {
						$mountPoint = $volume.Path
					}

					# If BitLocker metadata exists, capture status and unique protector types.
					if (-not [string]::IsNullOrWhiteSpace($mountPoint)) {
						$bitLockerVolume = Get-BitLockerVolume -MountPoint $mountPoint -ErrorAction Stop
						if ($null -ne $bitLockerVolume) {
							$bitLockerStatus = "$($bitLockerVolume.ProtectionStatus)"
							if ($bitLockerVolume.KeyProtector) {
								$protectorTypeList = $bitLockerVolume.KeyProtector |
									Select-Object -ExpandProperty KeyProtectorType -Unique
								if ($protectorTypeList) {
									$protectorTypes = $protectorTypeList -join ', '
								}
								else {
									$protectorTypes = 'None'
								}
							}
							else {
								$protectorTypes = 'None'
							}
						}
					}
				}
				catch {
					# BitLocker details might not be available for all volume types or environments.
				}

				# Write volume details, including encryption status.
				Write-Host ("    Volume Label     : {0}" -f ($(if ([string]::IsNullOrWhiteSpace($volume.FileSystemLabel)) { 'N/A' } else { $volume.FileSystemLabel })))
				Write-Host ("    File System      : {0}" -f $volume.FileSystem)
				Write-Host ("    Volume Health    : {0}" -f $volume.HealthStatus)
				Write-Host ("    BitLocker Status : {0}" -f $bitLockerStatus)
				Write-Host ("    Protector Types  : {0}" -f $protectorTypes)
				Write-Host ("    Size RemainingGB : {0:N2}" -f ($volume.SizeRemaining / 1GB))
				Write-Host ("    Size TotalGB     : {0:N2}" -f ($volume.Size / 1GB))
			}
			else {
				Write-Host "    Volume           : N/A" -ForegroundColor DarkGray
			}

			# Visual break between partition/volume blocks for readability.
			Write-Host ""
		}
	}
}

# Auto-run when this script file is executed directly.
Get-DiskVolumeInfo 