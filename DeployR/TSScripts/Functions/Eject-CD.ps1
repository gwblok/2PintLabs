# Eject or close the CD/DVD drive tray using PowerShell.
#
# Process:
# 1. Try the Windows Media Player COM interface (WMPlayer.OCX) to access
#    the CD-ROM collection and toggle each detected tray.
# 2. If that COM object is unavailable, fails, or reports no optical drives,
#    fall back to the Shell.Application COM interface and invoke the Eject verb
#    for any items reported as CD drives.
#
# The primary method is typically the most direct option on systems where the
# Windows Media Player COM components are present. The fallback covers systems
# where that interface is missing or does not enumerate the drive correctly.

# Helper function for the fallback path.
# Uses the Windows shell view of "My Computer" (namespace 17) to find items
# reported as CD drives, then invokes the built-in Eject shell verb for each.
# Returns $true when at least one drive is found and processed; otherwise $false.
function Invoke-ShellTrayEject {
    $shell = $null

    try {
        # Shell.Application provides a second way to discover optical drives
        # without depending on the Windows Media Player COM registration.
        $shell = New-Object -ComObject Shell.Application
        $cdDrives = @($shell.Namespace(17).Items() | Where-Object { $_.Type -eq 'CD Drive' })

        if ($cdDrives.Count -eq 0) {
            Write-Host "No CD/DVD drives detected." -ForegroundColor Yellow
            return $false
        }

        foreach ($cdDrive in $cdDrives) {
            $cdDrive.InvokeVerb('Eject')
            Write-Host "Toggled tray for drive: $($cdDrive.Name)" -ForegroundColor Green
        }

        return $true
    }
    catch {
        Write-Host "Fallback eject failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        if ($shell) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null }
    }
}

try {
    # Primary method: use the Windows Media Player COM object to enumerate
    # optical drives through its cdromCollection interface.
    $wmp = New-Object -ComObject WMPlayer.OCX

    # Access the CD-ROM drives collection
    $cdromCollection = $wmp.cdromCollection

    if ($cdromCollection.Count -eq 0) {
        # If the primary enumeration path cannot see any optical drives,
        # try the shell-based fallback before giving up.
        Write-Host "Primary eject method found no CD/DVD drives. Trying fallback method..." -ForegroundColor Yellow
        Invoke-ShellTrayEject | Out-Null
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
    # If the WMP COM object is unavailable or fails during enumeration/eject,
    # fall back to the shell verb approach.
    Write-Host "Primary eject method failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Trying fallback method..." -ForegroundColor Yellow
    Invoke-ShellTrayEject | Out-Null
}
finally {
    # Clean up COM object
    if ($wmp) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wmp) | Out-Null }
}
