# Eject or close the CD/DVD drive tray using PowerShell
# Works on most Windows systems with Windows Media Player installed

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
        $cdrom.Eject()  # This toggles: ejects if closed, closes if open
        Write-Host "Toggled tray for drive: $($cdrom.DriveSpecifier)" -ForegroundColor Green
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    # Clean up COM object
    if ($wmp) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wmp) | Out-Null }
}