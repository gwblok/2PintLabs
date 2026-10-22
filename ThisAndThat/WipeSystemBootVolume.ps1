#Requires -Version 5.1
<#
.SYNOPSIS
Previews or removes all files from the current Windows EFI System Partition.

.DESCRIPTION
Uses the IsSystem disk and partition flags, as in Update-BootMgr2023.ps1, to
identify the EFI System Partition. Only a single GPT, FAT32 EFI system volume
is accepted. The Windows OS partition (IsBoot) must not be the target.

By default, this script only reports the target and its top-level contents.
With -Execute, it requires elevation and confirmation before deleting ALL
contents, including hidden and system files. The partition and FAT32 filesystem
remain intact. This is NOT a format, a conversion to RAW, or a secure erase.

WARNING: Removing these files can prevent this device from booting again.
Other operating systems or OEM tools using this EFI partition are also affected.
Have external recovery media and any BitLocker recovery keys available first.
There is no automatic reboot, backup, or rollback. An interrupted/failed removal
may leave a partially emptied, unbootable partition; failures are terminating.

Windows blocks formatting active system/critical partitions. This script does
not bypass that protection, delete the partition, or write raw disk sectors.
Formatting reference:
https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/format-msft-volume

.PARAMETER Execute
Enables deletion. Without this switch, no files are changed.

.EXAMPLE
.\WipeSystemBootVolume.ps1
Reports the detected EFI partition and its top-level entries without changes.

.EXAMPLE
.\WipeSystemBootVolume.ps1 -Execute -WhatIf
Shows the proposed deletion without changing files. Run elevated.

.EXAMPLE
.\WipeSystemBootVolume.ps1 -Execute
Run elevated on the intended device ONLY. Prompts before emptying the EFI
System Partition, which can leave the device unbootable.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'

if ($Execute) {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object -TypeName System.Security.Principal.WindowsPrincipal -ArgumentList $identity
        if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Execution requires an elevated PowerShell session.'
        }
    }
    finally {
        $identity.Dispose()
    }
}

$systemDisks = @(Get-Disk | Where-Object { $_.IsSystem })
if ($systemDisks.Count -ne 1) {
    throw "Expected exactly one system disk; found $($systemDisks.Count). No files were changed."
}
$systemDisk = $systemDisks[0]
if ($systemDisk.PartitionStyle -ne 'GPT' -or $systemDisk.IsOffline -or $systemDisk.IsReadOnly) {
    throw 'The system disk must be online, writable, and GPT. No files were changed.'
}

$systemPartitions = @(Get-Partition -DiskNumber $systemDisk.Number | Where-Object { $_.IsSystem })
if ($systemPartitions.Count -ne 1) {
    throw "Expected exactly one system partition; found $($systemPartitions.Count). No files were changed."
}
$systemPartition = $systemPartitions[0]
$efiPartitionType = [guid]'c12a7328-f81f-11d2-ba4b-00a0c93ec93b'
if ($systemPartition.IsBoot -or [guid]$systemPartition.GptType -ne $efiPartitionType) {
    throw 'The system partition is not a separate EFI System Partition. No files were changed.'
}
if ($systemPartition.IsReadOnly -or $systemPartition.IsOffline) {
    throw 'The EFI partition must be online and writable. No files were changed.'
}

# Resolve the volume through its partition association, not a drive letter or GUID substring.
$systemVolumes = @($systemPartition | Get-Volume)
if ($systemVolumes.Count -ne 1) {
    throw "Expected exactly one EFI volume; found $($systemVolumes.Count). No files were changed."
}
$systemVolume = $systemVolumes[0]
if ($systemVolume.FileSystemType -ne 'FAT32' -or $systemVolume.DriveType -ne 'Fixed') {
    throw 'The EFI volume must be a fixed FAT32 volume. No files were changed.'
}
$volumePath = $systemVolume.Path
if ($volumePath -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\}\\$') {
    throw 'The EFI volume did not provide an unambiguous volume GUID path. No files were changed.'
}
if (-not (Test-Path -LiteralPath $volumePath -PathType Container)) {
    throw "Cannot access EFI volume '$volumePath'. Try an elevated session. No files were changed."
}

$entries = @(Get-ChildItem -LiteralPath $volumePath -Force)
[pscustomobject]@{
    DiskNumber = $systemDisk.Number
    PartitionNumber = $systemPartition.PartitionNumber
    VolumePath = $volumePath
    FileSystem = $systemVolume.FileSystemType
    SizeBytes = $systemPartition.Size
    TopLevelEntries = @($entries.Name)
    Mode = if ($Execute) { 'Execute' } else { 'Preview - no changes' }
}

if (-not $Execute) {
    return
}

Write-Warning 'Removing ALL EFI partition contents can leave this device unbootable. Windows/data partitions will not be targeted. This is not a secure erase.'
$target = "EFI volume $volumePath (disk $($systemDisk.Number), partition $($systemPartition.PartitionNumber))"
if ($PSCmdlet.ShouldProcess($target, 'Permanently remove ALL files and directories; device may no longer boot')) {
    # Reject junctions/symlinks before recursive deletion so their targets cannot be followed.
    $allEntries = @(Get-ChildItem -LiteralPath $volumePath -Force -Recurse)
    if (@($allEntries | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw 'The EFI volume contains a reparse point. Refusing deletion.'
    }

    foreach ($entry in $entries) {
        Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop
    }

    $remainingEntries = @(Get-ChildItem -LiteralPath $volumePath -Force)
    if ($remainingEntries.Count -ne 0) {
        throw "EFI cleanup incomplete: $($remainingEntries.Count) top-level entries remain. The device may already be unbootable."
    }
    [pscustomobject]@{
        Status = 'Emptied'
        VolumePath = $volumePath
        RemainingEntries = 0
        FileSystem = 'FAT32'
    }
}