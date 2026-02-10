<#
.SYNOPSIS
    Adds a BitLocker Recovery Password protector (if missing) and backs it up to Active Directory.
.DESCRIPTION
    Targets the OS drive (C: by default). Safe to run on already-encrypted volumes.
.EXAMPLE
    .\Backup-BitLockerToAD.ps1 -MountPoint "C:"
    .\Backup-BitLockerToAD.ps1  # Defaults to C:
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$MountPoint = "C:"
)

<#
# Refresh Group Policy (non-fatal) - try twice, wait up to 60s each
Write-Host "Refreshing Group Policy (gpupdate /force /wait:60) - up to 2 attempts..." -ForegroundColor Cyan
for ($attempt = 1; $attempt -le 2; $attempt++) {
    try {
        Start-Process -FilePath "gpupdate.exe" -ArgumentList "/force","/wait:60" -Wait -WindowStyle Hidden -ErrorAction Stop
        Write-Host "Group Policy refresh completed (attempt $attempt)." -ForegroundColor Green
        break
    }
    catch {
        Write-Warning "Group Policy refresh attempt $attempt failed: $($_.Exception.Message)"
        if ($attempt -lt 2) {
            Write-Host "Retrying in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
        else {
            Write-Warning "Group Policy refresh failed after $attempt attempts. Continuing without aborting."
        }
    }
}
#>
#region Create GPO Values:
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\FVE"


#write out the current Registry Values for the relevant GPO settings for reference (optional)
Get-ItemProperty -Path $regPath | Format-List



# Ensure path exists
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
    Write-Host "Created: $regPath" -ForegroundColor Green
}

# No helper function: use Set-ItemProperty directly below

Write-Host "Applying BitLocker AD escrow registry settings for OS drives..." -ForegroundColor Cyan

# Global enablement
function Ensure-DWord {
    param(
        [string]$Name,
        [int]$DesiredValue
    )

    $existing = (Get-ItemProperty -Path $regPath -Name $Name -ErrorAction SilentlyContinue).$Name

    if ($existing -ne $DesiredValue) {
        Set-ItemProperty -Path $regPath -Name $Name -Value $DesiredValue -Type DWord -Force
        Write-Host "Set $Name = $DesiredValue" -ForegroundColor Green
    }
    else {
        Write-Host "$Name already set to $DesiredValue" -ForegroundColor DarkGray
    }
}

# Global enablement
Ensure-DWord -Name "ActiveDirectoryBackup" -DesiredValue 1
Ensure-DWord -Name "RequireActiveDirectoryBackup" -DesiredValue 1
Ensure-DWord -Name "ActiveDirectoryInfoToStore" -DesiredValue 1

# OS drive specific (the critical missing pieces)
Ensure-DWord -Name "OSActiveDirectoryBackup" -DesiredValue 1
Ensure-DWord -Name "OSRequireActiveDirectoryBackup" -DesiredValue 0
Ensure-DWord -Name "OSActiveDirectoryInfoToStore" -DesiredValue 1

# Recommended recovery policy options for OS drives
Ensure-DWord -Name "OSRecovery" -DesiredValue 1    # Enable recovery page config
Ensure-DWord -Name "OSRecoveryPassword" -DesiredValue 2    # Require 48-digit numerical password
#Ensure-DWord -Name "OSRecoveryKey" -DesiredValue 1        # Allow external key (optional) [Don't do this, it breaks stuff]
Ensure-DWord -Name "OSHideRecoveryPage" -DesiredValue 1   # Omit/hide recovery options in wizard
Ensure-DWord -Name "OSManageDRA" -DesiredValue 1          # Allow data recovery agent

#endregion

# Import the BitLocker module (usually auto-loaded, but explicit is safer)
Import-Module BitLocker -ErrorAction SilentlyContinue

Write-Host "Checking BitLocker status on $MountPoint ..." -ForegroundColor Cyan

try {
    $blv = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop

    if ($blv.VolumeStatus -ne "FullyEncrypted") {
        Write-Warning "Volume $MountPoint is not fully encrypted (Status: $($blv.VolumeStatus))."
        
    }
    else {
        Write-Host "Volume $($blv.MountPoint) is FullyEncrypted. Checking protectors..." -ForegroundColor Green
    }

    

    # Find existing RecoveryPassword protector(s)
    $recoveryProtectors = $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }

    if ($recoveryProtectors.Count -gt 0) {
        Write-Host "Found $($recoveryProtectors.Count) existing Recovery Password protector(s)." -ForegroundColor Green
        
        foreach ($rp in $recoveryProtectors) {
            Write-Host "  - ID: $($rp.KeyProtectorId)"
            Write-Host "  - Password: $($rp.RecoveryPassword)" -ForegroundColor Yellow
            
            # Backup to AD
            Write-Host "Backing up protector $($rp.KeyProtectorId) to AD DS..." -ForegroundColor Cyan
            Backup-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $rp.KeyProtectorId -ErrorAction Stop
            Write-Host "Successfully backed up to Active Directory." -ForegroundColor Green
        }
    }
    else {
        Write-Host "No RecoveryPassword protector found. Adding one now..." -ForegroundColor Yellow
        
        # Add a new recovery password protector (auto-generates 48-digit password)
        Add-BitLockerKeyProtector -MountPoint $MountPoint -RecoveryPasswordProtector -ErrorAction Stop
        
        # Refresh the volume object to get the new protector
        $blv = Get-BitLockerVolume -MountPoint $MountPoint
        
        $newRP = $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" } | Select-Object -Last 1
        
        if ($newRP) {
            Write-Host "New Recovery Password added:" -ForegroundColor Green
            Write-Host "  - ID: $($newRP.KeyProtectorId)"
            Write-Host "  - Password: $($newRP.RecoveryPassword)" -ForegroundColor Yellow
            
            # Backup the new one to AD
            Write-Host "Backing up new protector to AD DS..." -ForegroundColor Cyan
            Backup-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $newRP.KeyProtectorId -ErrorAction Stop
            Write-Host "Successfully backed up to Active Directory." -ForegroundColor Green
        }
        else {
            Write-Error "Failed to retrieve the newly added recovery protector."
        }
    }
}
catch {
    Write-Error "Error: $($_.Exception.Message)"
    Write-Warning "Common causes: Not domain-joined, GPO not allowing escrow, insufficient AD permissions, or BitLocker module issue."
}

Write-Host "`nDone. Check the BitLocker Recovery tab in ADUC for the computer object." -ForegroundColor Cyan