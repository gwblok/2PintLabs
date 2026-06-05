# Get the driver letter of the CD/DVD that contains DeployR-Media.ps1
try {
    # Create a Windows Media Player COM object
    $wmp = New-Object -ComObject WMPlayer.OCX

    # Access the CD-ROM drives collection
    $cdromCollection = $wmp.cdromCollection

    if ($cdromCollection.Count -eq 0) {
        Write-Host "No CD/DVD drives detected." -ForegroundColor Yellow
        return
    }

    # Loop through all detected drives and toggle tray state
    for ($i = 0; $i -lt $cdromCollection.Count; $i++) {
        $cdrom = $cdromCollection.Item($i)
        #$cdrom.Eject()  # This toggles: ejects if closed, closes if open
        Write-Host "Toggled tray for drive: $($cdrom.DriveSpecifier)" -ForegroundColor Green
        if (Test-Path -Path "$($cdrom.DriveSpecifier)\DeployR-Media.ps1") {
            Write-Host "Found DeployR-Media.ps1 on drive $($cdrom.DriveSpecifier)." -ForegroundColor Green
            $ISODriveLetter = $cdrom.DriveSpecifier
        }

    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    # Clean up COM object
    if ($wmp) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wmp) | Out-Null }
}

# Now get the full path to the ISO
$ISODriveLetter = $ISODriveLetter.TrimEnd(':')  # Remove the colon for Get-Volume
$DeployRISO = (Get-Volume -DriveLetter $ISODriveLetter | Get-DiskImage).ImagePath

Write-Output "Original ISO location: $DeployRISO"
$tsenv:DeployRISO = $DeployRISO