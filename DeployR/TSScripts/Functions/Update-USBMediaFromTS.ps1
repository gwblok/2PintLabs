#Script from our friends in Canada, Thanks, you know who you are... if you want more credit, let me know!

# Variables Declaration
$FileName = "DeployR_x64_noprompt.iso"
$ContentName = "BootImage"

$SourceURI = "${TSEnv:DeployRHost}/Content/Boot/$FileName"

# Check if Client and Server version are the same
if ($TSEnv:DeployRClientVersion -ne $TSEnv:DeployRServerVersion)
{
    # Find USB Boot Partition Key
    Write-Host "Getting Boot Volume"
    $BootVolume = Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "PEBootRamDiskSourceDrive"

    # Exit if partition doesn't exist
    if (-not $BootVolume)
    {
        Write-Host "Could not find Boot Drive."
        exit 1
    }

    # Download File
    try
    {
        $ISOPath = Request-DeployRCustomContent -ContentName $ContentName -ContentFriendlyName "Latest Boot ISO" -Url $SourceURI
        Write-Host "Destination File: $ISOPath"
    }
    catch
    {
        Write-Host "Unable to download $ISOPath due to error: $_"
        exit 1
    }

    # Mount ISO
    Write-Host "Mounting ISO from $ISOPath"
    $MountedISO = Mount-DiskImage -ImagePath $ISOPath -PassThru
    $ISODriveLetter = $MountedISO | Get-Volume | Select-Object -ExpandProperty DriveLetter

    # Copy ISO content to USB drive
    Start-Sleep -Seconds 5
    Write-Host "Copying ISO Content ($($ISODriveLetter):) to USB Drive ($BootVolume)"
    robocopy "$($ISODriveLetter):" "$BootVolume" /mir

    # Dismount ISO and clean it up
    Write-Host "Dismount ISO"
    $null = Dismount-DiskImage -ImagePath $ISOPath

    Write-Host "Clean up ISO file"
    Remove-Item -Path $ISOPath -Force

    exit 0
}
else
{
    Write-Host "Client and Server are on the same version. Skipping..."
}