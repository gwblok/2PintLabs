

Import-Module DeployR.Utility

#region Functions
#Get the next available drive letter available.
function Get-NextAvailableDriveLetter {
	$allLetters = 68..90 | ForEach-Object {[char]$_ + ":"} #Starting at D:
	$usedLetters = Get-CimInstance -ClassName win32_logicaldisk | Select-Object -expand deviceid
	$freeLetters = $allLetters | Where-Object {$usedLetters -notcontains $_}
	return ($freeLetters | Select-Object -First 1).replace(":", "")
}
function Get-SystemDisk {
	#Pull info from TS Step
	$gwmiParams = @{
		Namespace = 'root\microsoft\windows\storage'
		Query = 'select Number,Size,BusType,Model from MSFT_Disk where BusType <> 6 and BusType <> 7 and BusType <> 9 and BusType <> 16'
	}
	
	$sortParams = @{
		Property = @(
		@{ Expression = { if ($_.BusType -eq 17) { -1 } else { $_.BusType } }; Descending = $false },
		@{ Expression = 'Size'; Descending = $false }
		)
	}
	$OSDDiskIndex = (Get-CimInstance @gwmiParams | Sort-Object @sortParams | Select-Object -First 1).Number
	return $OSDDiskIndex
}

#endregion

# Get the specified disk index - Pull info from TS Step
$diskIndex = ${TSEnv:DiskIndex}
$autoPickSmallestFastestDisk = ${TSEnv:autoPickSmallestFastestDisk}
[int]$efiPartitionSizeMB = ${TSEnv:EFIPartitionSizeMB}
[int]$recoveryPartitionSizeMB = ${TSEnv:RecoveryPartitionSizeMB}

[int]$msrPartitionSizeMB = 128
$formatExtraDisks = ${TSEnv:formatExtraDisks}

#Report Variables
Write-Host "------------------------------------------------------------"
Write-Host "Format Disk Step"
write-host "Starting Variables based on Step Definition"
Write-Host " DiskIndex = $diskIndex"
Write-Host " AutoPickSmallestFastestDisk = $autoPickSmallestFastestDisk"
Write-Host " EFIPartitionSizeMB = $efiPartitionSizeMB"
Write-Host " MSRPartitionSizeMB = $msrPartitionSizeMB"
Write-Host " RecoveryPartitionSizeMB = $recoveryPartitionSizeMB"
Write-Host " formatExtraDisks = $formatExtraDisks"

Write-Host "------------------------------------------------------------"

#Defaults
if ($efiPartitionSizeMB -lt 360) { 
	$efiPartitionSizeMB = 984
	write-host "Updated EFIPartitionSizeMB to $efiPartitionSizeMB because it was less than 360"
}

if ($recoveryPartitionSizeMB -lt 984) { 
	$recoveryPartitionSizeMB = 984
	write-host "Updated RecoveryPartitionSizeMB to $recoveryPartitionSizeMB because it was less than 984"
}
if ($autoPickSmallestFastestDisk -eq "true") {
	Write-Host "Auto picking smallest fastest disk"
	$diskIndex = Get-SystemDisk
	Write-Host "Picked disk $diskIndex"
}
if ($null -eq $diskIndex){
	$diskIndex = ${TSEnv:DiskIndex}
}
try {
	$disk = Get-Disk -Number $diskIndex
} catch {
	Write-Host "Failed to get disk information: $_"
	exit 1
}
Write-Host "Using Disk: $($disk.FriendlyName)"
write-Host " Serial Number: $($disk.SerialNumber)"
write-Host " Size:          $([math]::Round($disk.Size / 1GB)) GB"
Write-Host " Bus Type:      $($disk.BusType)"
Write-Host " Model:         $($disk.Model)"

Write-Host "------------------------------------------------------------"
# Calculate the OS partition size by subtracting the other sizes
# Calculate the OS partition size by subtracting the other sizes
$efiPartitionSize = $efiPartitionSizeMB * 1024 * 1024
$msrPartitionSize = $msrPartitionSizeMB * 1024 * 1024
$recoveryPartitionSize = $recoveryPartitionSizeMB * 1024 * 1024
$osSize = $disk.Size - $efiPartitionSize - $msrPartitionSize - $recoveryPartitionSize - 20480000
Write-Host "Calculated OS Partition Size: $osSize ($([math]::Round($osSize / 1GB)) GB)"
# Clean the disk if it isn't already raw
if ($disk.PartitionStyle -ne "RAW")
{
	Write-Host "Clearing disk"
	Clear-Disk -Number $diskIndex -RemoveData -RemoveOEM -Confirm:$false
}

# Initialize the disk as a GPT disk (UEFI)
Write-Host "Initializing disk"
$null = Initialize-Disk -Number $diskIndex -PartitionStyle GPT

# Partition as needed

Write-Host "Partitioning Boot Disk"
Write-Host " Creating EFI Partition of size $efiPartitionSizeMB MB"
$efi = New-Partition -DiskNumber $diskIndex -Size $efiPartitionSize -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
Write-Host " Creating MSR Partition of size $msrPartitionSizeMB MB"
$msr = New-Partition -DiskNumber $diskIndex -Size $msrPartitionSize -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'
Write-Host " Creating OS Partition of size $([math]::Round($osSize / 1GB)) GB"
$os = New-Partition -DiskNumber $diskIndex -Size $osSize
Write-Host " Creating Recovery Partition of size $recoveryPartitionSizeMB MB"
$recovery = New-Partition -DiskNumber $diskIndex -UseMaximumSize -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'


# Assign drive letters
Write-Host "Assigning drive letters"
Write-Host " Assigning EFI Partition to W:"
$efi | Set-Partition -NewDriveLetter W
Write-Host " Assigning OS Partition to S:"
$os | Set-Partition -NewDriveLetter S

# Format
Write-Host "Formatting"
Write-Host " Formatting EFI Partition"
$null = $efi | Format-Volume -FileSystem FAT32 -NewFileSystemLabel "Boot"
Write-Host " Formatting OS Partition"
$null = $os | Format-Volume -FileSystem NTFS -NewFileSystemLabel "OS"
Write-Host " Formatting Recovery Partition"
$null = $recovery | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Recovery"

# Copy the state to the new drive and update variables to point to the new location
Write-Host "Copying state"
Copy-Item "X:\_2P" "S:\_2P" -Recurse # -Verbose
$tsenv:DeployRRoot = "S:\_2P"
$tsenv:DeployRState = "S:\_2P\state"
$tsenv:DeployRContent = "S:\_2P\content"
$tsenv:_DeployRLogs = "S:\_2P\logs"


if ($formatExtraDisks -ne "NO") {
	#Get Disks
	if ($formatExtraDisks -eq "RAWDisks") {
		$Disks = get-disk | Where-Object {$_.PartitionStyle -eq "RAW" -and $_.Number -ne $diskIndex -and $_.BusType -ne "USB"}
	}
	elseif ($formatExtraDisks -eq "AllDisks") {
		$Disks = get-disk | Where-Object {$_.Number -ne $diskIndex -and $_.BusType -ne "USB"}
	}
	if ($Disks) {
		Write-Host "Found $($Disks.Count) extra disks to format"
		

		#Change CD Drive to A Drive temporary
		$cd = Get-CimInstance -ClassName Win32_CDROMDrive -ErrorAction SilentlyContinue
		if ($cd){
			Write-Host " Found CD Drive: $($cd.DeviceID)"
			Write-Host " Changing CD Drive Letter to A:"
			$driveletter = $cd.drive
			$DriveInfo = Get-CimInstance -class win32_volume | Where-Object {$_.DriveLetter -eq $driveletter} |Set-CimInstance -Arguments @{DriveLetter='A:'}
		}
		Write-Host "Formatting extra disks"
		foreach ($Disk in $Disks)#{}
		{
			Write-Host " Starting Process on Disk $($Disk.Number)"
			Write-Host "  Size:          $([math]::Round($disk.Size / 1GB)) GB"
			Write-Host "  Bus Type:      $($disk.BusType)"
			Write-Host "  Model:         $($disk.Model)"
			$Size = [math]::Round($Disk.size / 1024 / 1024 / 1024)
			if ($disk.PartitionStyle -ne "RAW"){
				Write-Host "  Clearing disk $($Disk.Number)"
				Clear-Disk -Number $Disk.Number -RemoveData -RemoveOEM -Confirm:$false
				start-sleep -Seconds 1
			}
			Write-Host "  Initializing disk"
			$null = Initialize-Disk -PartitionStyle GPT -Number $Disk.Number
			$DriveLetter = (Get-NextAvailableDriveLetter)
			Write-Host "  Creating partition with Drive Letter $DriveLetter and Formatting NTFS"
			New-Partition -DiskNumber $Disk.Number -DriveLetter $DriveLetter -UseMaximumSize |
			Format-Volume -FileSystem NTFS -NewFileSystemLabel "Storage-$($Size)GB" -Confirm:$false
		}
		if ($cd){
			#Set CD to next available Drive Letter
			$CDDriveLetter = "$(Get-NextAvailableDriveLetter):"
			Write-Host " Changing CD Drive Letter to $CDDriveLetter"
			$DriveInfo = Get-CimInstance -class win32_volume | Where-Object {$_.DriveLetter -eq "A:"} |Set-CimInstance -Arguments @{DriveLetter=$CDDriveLetter}
		}
	}
	else {
		Write-Host "No extra disks found to format"
	}
}


# Clean up the log to make it clear that it moved
Remove-Item "X:\_2P\logs\DeployR.log" -Force
