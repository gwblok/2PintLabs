#Requires -Version 5.1
# Run with Invoke-Pester. All storage discovery and deletion commands are mocked.
$script:scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'WipeSystemBootVolume.ps1'

# Accept synthetic partitions without the Storage module's CIM parameter binding.
function Get-Volume {
    param (
        [Parameter(ValueFromPipeline)]
        $Partition
    )
    throw 'Get-Volume must be mocked in these tests.'
}

Describe 'WipeSystemBootVolume safety and execution' {
    BeforeEach {
        $script:disk = [pscustomobject]@{
            Number = 2
            IsSystem = $true
            PartitionStyle = 'GPT'
            IsOffline = $false
            IsReadOnly = $false
        }
        $script:partition = [pscustomobject]@{
            DiskNumber = 2
            PartitionNumber = 1
            IsSystem = $true
            IsBoot = $false
            IsOffline = $false
            IsReadOnly = $false
            GptType = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
            Size = 104857600
        }
        $script:volume = [pscustomobject]@{
            FileSystemType = 'FAT32'
            DriveType = 'Fixed'
            Path = '\\?\Volume{11111111-2222-3333-4444-555555555555}\'
        }
        $script:entries = @(
            [pscustomobject]@{
                Name = 'EFI'
                FullName = $script:volume.Path + 'EFI'
                Attributes = [System.IO.FileAttributes]::Directory
            }
            [pscustomobject]@{
                Name = 'hidden.dat'
                FullName = $script:volume.Path + 'hidden.dat'
                Attributes = [System.IO.FileAttributes]::Hidden
            }
        )
        $script:extraEntries = @()
        $script:removedPaths = @()
        $script:accessible = $true
        $script:administrator = $true
        $script:deletionFails = $false
        $script:leaveEntries = $false

        Mock Get-Disk { $script:disk }
        Mock Get-Partition { $script:partition }
        Mock Get-Volume { $script:volume }
        Mock Test-Path { $script:accessible }
        Mock Get-ChildItem {
            if ($Recurse) {
                $script:entries
                $script:extraEntries
            }
            elseif ($script:removedPaths.Count -lt $script:entries.Count -or $script:leaveEntries) {
                $script:entries
            }
        }
        Mock Remove-Item {
            if ($script:deletionFails) {
                throw 'Simulated deletion failure'
            }
            $script:removedPaths += $LiteralPath
        }
        Mock New-Object {
            $principal = [pscustomobject]@{}
            $principal | Add-Member -MemberType ScriptMethod -Name IsInRole -Value { $script:administrator }
            $principal
        } -ParameterFilter { $TypeName -eq 'System.Security.Principal.WindowsPrincipal' }
    }

    It 'previews without requesting elevation or deleting anything' {
        $result = . $script:scriptPath
        $result.Mode | Should Be 'Preview - no changes'
        $result.DiskNumber | Should Be 2
        $result.PartitionNumber | Should Be 1
        $result.VolumePath | Should Be $script:volume.Path
        $result.TopLevelEntries.Count | Should Be 2
        Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
        Assert-MockCalled New-Object -Times 0 -Exactly -Scope It
        Assert-MockCalled Get-Partition -Times 1 -Exactly -Scope It -ParameterFilter { $DiskNumber -eq 2 }
    }

    It 'honors WhatIf even with Execute and confirmation disabled' {
        . $script:scriptPath -Execute -WhatIf -Confirm:$false | Out-Null
        Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
    }

    It 'removes only literal EFI child paths including hidden entries and verifies emptiness' {
        $result = @(. $script:scriptPath -Execute -Confirm:$false)
        $result[-1].Status | Should Be 'Emptied'
        $result[-1].RemainingEntries | Should Be 0
        $script:removedPaths.Count | Should Be 2
        $script:removedPaths[0] | Should Be ($script:volume.Path + 'EFI')
        $script:removedPaths[1] | Should Be ($script:volume.Path + 'hidden.dat')
        Assert-MockCalled Remove-Item -Times 2 -Exactly -Scope It -ParameterFilter {
            $Recurse -and $Force
        }
    }

    It 'requires elevation before discovery for Execute' {
        $script:administrator = $false
        { . $script:scriptPath -Execute -Confirm:$false } | Should Throw 'elevated'
        Assert-MockCalled Get-Disk -Times 0 -Exactly -Scope It
        Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
    }

    It 'rejects missing or ambiguous system disks' {
        $script:disk = @()
        { . $script:scriptPath } | Should Throw 'exactly one system disk'
        $script:disk = @([pscustomobject]@{ IsSystem = $true }, [pscustomobject]@{ IsSystem = $true })
        { . $script:scriptPath } | Should Throw 'exactly one system disk'
        Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
    }

    It 'rejects legacy MBR disks' {
        $script:disk.PartitionStyle = 'MBR'
        { . $script:scriptPath } | Should Throw 'GPT'
    }

    It 'rejects offline or read-only disks' {
        $script:disk.IsOffline = $true
        { . $script:scriptPath } | Should Throw 'online, writable'
        $script:disk.IsOffline = $false
        $script:disk.IsReadOnly = $true
        { . $script:scriptPath } | Should Throw 'online, writable'
    }

    It 'rejects missing or ambiguous system partitions' {
        $original = $script:partition
        $script:partition = @()
        { . $script:scriptPath } | Should Throw 'exactly one system partition'
        $script:partition = @($original, $original)
        { . $script:scriptPath } | Should Throw 'exactly one system partition'
    }

    It 'refuses the Windows boot partition' {
        $script:partition.IsBoot = $true
        { . $script:scriptPath -Execute -Confirm:$false } | Should Throw 'separate EFI'
        Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
    }

    It 'refuses non-EFI partition types' {
        $script:partition.GptType = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
        { . $script:scriptPath } | Should Throw 'separate EFI'
    }

    It 'rejects offline or read-only partitions' {
        $script:partition.IsOffline = $true
        { . $script:scriptPath } | Should Throw 'online and writable'
        $script:partition.IsOffline = $false
        $script:partition.IsReadOnly = $true
        { . $script:scriptPath } | Should Throw 'online and writable'
    }

    It 'requires exactly one associated volume' {
        $original = $script:volume
        $script:volume = @()
        { . $script:scriptPath } | Should Throw 'exactly one EFI volume'
        $script:volume = @($original, $original)
        { . $script:scriptPath } | Should Throw 'exactly one EFI volume'
    }

    It 'rejects non-FAT32 or removable volumes' {
        $script:volume.FileSystemType = 'NTFS'
        { . $script:scriptPath } | Should Throw 'fixed FAT32'
        $script:volume.FileSystemType = 'FAT32'
        $script:volume.DriveType = 'Removable'
        { . $script:scriptPath } | Should Throw 'fixed FAT32'
    }

    It 'rejects drive letters and non-root volume paths' {
        $original = $script:volume.Path
        foreach ($path in @('C:\', '', ($original + 'EFI'))) {
            $script:volume.Path = $path
            { . $script:scriptPath } | Should Throw 'volume GUID path'
        }
    }

    It 'fails explicitly when the volume cannot be accessed' {
        $script:accessible = $false
        { . $script:scriptPath } | Should Throw 'Cannot access EFI volume'
    }

    It 'refuses reparse points before deleting any entries' {
        $script:extraEntries = @([pscustomobject]@{ Attributes = [System.IO.FileAttributes]::ReparsePoint })
        { . $script:scriptPath -Execute -Confirm:$false } | Should Throw 'reparse point'
        Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
    }

    It 'propagates deletion failures instead of reporting success' {
        $script:deletionFails = $true
        { . $script:scriptPath -Execute -Confirm:$false } | Should Throw 'Simulated deletion failure'
        Assert-MockCalled Remove-Item -Times 1 -Exactly -Scope It
    }

    It 'reports failure if any entries remain' {
        $script:leaveEntries = $true
        { . $script:scriptPath -Execute -Confirm:$false } | Should Throw 'cleanup incomplete'
    }
}
