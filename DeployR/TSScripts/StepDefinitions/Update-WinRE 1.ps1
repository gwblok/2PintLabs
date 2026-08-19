<#
.SYNOPSIS
    Exports necessary drivers for WinRE, mounts the WinRE WIM file, adds the drivers, performs cleanup, and unmounts the WIM.

.DESCRIPTION
    This script automates the process of updating the Windows Recovery Environment (WinRE) WIM file by exporting the necessary
    drivers from the full OS, mounting the WinRE.wim, adding drivers, performing a cleanup operation, unmounting the WIM with 
    changes committed, and cleaning up temporary directories. It includes error handling, logging, and validation for robustness.

.EXAMPLE
    .\Update-WinRE.ps1 

.USAGE
    - Requires administrative privileges.
    - Must be run on a Windows system with DISM and Reagentc.exe available.
    - Ensure the WinRE WIM is accessible and not corrupted.
    - Logs are saved to a file in the same directory as the script.

.NOTES
    AUTHOR: Mike Terrill/2Pint Software
    CONTACT: @miketerrill
    VERSION: 25.04.26

.CHANGELOG
    25.04.22  : Initial version
    25.04.23  : Updated for Surface devices and TOUGHBOOKS
    25.04.25  : Updated for ThinkCentre
    25.04.26  : Updated for ThinkPad

#>

# Define variables
$LogFile = "C:\Windows\Temp\Update-WinRE.log"
$WinREDrivers = "C:\Windows\Temp\WinREDrivers"
$WinREMount = "C:\Windows\Temp\WinREMount"

function Write-Log {
         [CmdletBinding()]
    Param (
		    [Parameter(Mandatory=$false)]
		    $Message,
		    [Parameter(Mandatory=$false)]
		    $ErrorMessage,
		    [Parameter(Mandatory=$false)]
		    $Component = "Script",
		    [Parameter(Mandatory=$false)]
		    [int]$Type
	    )
    <#
    Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
    #>
	    $Time = Get-Date -Format "HH:mm:ss.ffffff"
	    $Date = Get-Date -Format "MM-dd-yyyy"
	    if ($ErrorMessage -ne $null) {$Type = 3}
	    if ($Component -eq $null) {$Component = " "}
	    if ($Type -eq $null) {$Type = 1}
	    $LogMessage = "<![LOG[$Message $ErrorMessage" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
	    $LogMessage.Replace("`0","") | Out-File -Append -Encoding UTF8 -FilePath $LogFile
    }

# Start logging
Write-Log -Message "Starting Update-WinRE" -Type 1

# Check for administrative privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log -Message "This script requires administrative privileges. Please run as Administrator." -ErrorMessage "ERROR"
    exit 1
}

# Validate that DISM and Reagentc are available
if (-not (Get-Command "dism.exe" -ErrorAction SilentlyContinue)) {
    Write-Log -Message "DISM.exe is not available on this system." -ErrorMessage "ERROR"
    exit 1
}
if (-not (Get-Command "reagentc.exe" -ErrorAction SilentlyContinue)) {
    Write-Log -Message "Reagentc.exe is not available on this system." -ErrorMessage "ERROR"
    exit 1
}

# List of target INF files (case-insensitive comparison)
$TargetInfFiles = @(
    "e1d.inf",                        #TOUGHBOOK
    "e1dn.inf",                       #TOUGHBOOK
    "dlcdcncm.inf",                   #Dell D6000 Dock, ThinkPad
    "dlidusb.inf",                    #ThinkPad
    "dlusbaudio.inf",                 #ThinkPad
    "e2f.inf",                        #ThinkPad
    "e2f_ext.inf",                    #ThinkPad
    "heci.inf",                       #Surface
    "iaLPSS2_GPIO2_ADL.inf",          #Dell, TOUGHBOOK, ThinkPad
    "iaLPSS2_GPIO2_CNL.inf",          #TOUGHBOOK
    "iaLPSS2_GPIO2_MTL.inf",          #TOUGHBOOK
    "iaLPSS2_GPIO2_TGL.inf",          #Surface, TOUGHBOOK
    "iaLPSS2_I2C_ADL.inf",            #Dell, TOUGHBOOK, ThinkPad
    "iaLPSS2_I2C_CNL.inf",            #TOUGHBOOK
    "iaLPSS2_I2C_MTL.inf",            #TOUGHBOOK
    "iaLPSS2_I2C_TGL.inf",            #Surface, TOUGHBOOK
    "iaLPSS2_I3C_MTL.inf",            #TOUGHBOOK
    "iaLPSS2_SPI_ADL.inf",            #Dell, TOUGHBOOK, ThinkPad
    "iaLPSS2_SPI_CNL.inf",            #TOUGHBOOK
    "iaLPSS2_SPI_MTL.inf",            #TOUGHBOOK
    "iaLPSS2_SPI_TGL.inf",            #TOUGHBOOK
    "iaLPSS2_UART2_ADL.inf",          #Dell, TOUGHBOOK, ThinkPad
    "iaLPSS2_UART2_CNL.inf",          #TOUGHBOOK
    "iaLPSS2_UART2_MTL.inf",          #TOUGHBOOK
    "iaLPSS2_UART2_TGL.inf",          #Surface, TOUGHBOOK
    "iaStorHsa_Ext.inf",              #Dell, TOUGHBOOK
    "iaStorHsaComponent.inf",         #Dell, TOUGHBOOK
    "iaStorVD.inf",                   #Dell, TOUGHBOOK
    "msu53cx22x64sta.INF",            #Surface
    "msu56cx22x64sta.INF",            #Surface
    "Netwtw04.INF",                   #Dell, TOUGHBOOK
    "Netwtw06.INF",                   #Dell
    "Netwtw6e.INF",                   #Dell, TOUGHBOOK
    "Netwtw08.INF",                   #Dell, Surface, TOUGHBOOK
    "PieComponent.INF",               #TOUGHBOOK
    "PieExtension.INF",               #TOUGHBOOK
    "rt25cx21x64.inf",                #Dell
    "rt25dcx21x64.inf",               #Dell
    "rt68cx21x64.inf",                #Dell
    "rt68dcx21x64.inf",               #Dell
    "rt640x64.inf",                   #Dell, ThinkCentre
    "rtots640x64.inf",                #Dell
    "rtump64x64.INF",                 #Dell
    "rtvdevw10x64.inf",               #ThinkCentre
    "rtvdevx64_ext.inf",              #ThinkCentre
    "SurfaceAlsDriver.inf",           #Surface
    "SurfaceBattery.inf",             #Surface
    "SurfaceButton.inf",              #Surface
    "SurfaceDockIntegration.inf",     #Surface
    "SurfaceHidMiniDriver.inf",       #Surface
    "SurfaceIntegrationDriver.inf",   #Surface
    "SurfaceSerialHubDriver.inf",     #Surface
    "SurfaceServiceNullDriver.inf",   #Surface
    "SurfaceTimeAlarmAcpiFilter.inf", #Surface
    "SurfaceUcmUcsiHidClient.inf",    #Surface
    "TigerlakePCH-LPSystem.inf"       #Surface
    "WifiDrv04Customizations.inf",    #TOUGHBOOK
    "WifiDrv08Customizations.inf"     #TOUGHBOOK
)

# Creating the WinREDrivers directory
Write-Log -Message "Creating WinRE drivers directory: $WinREDrivers"
try {
    if (Test-Path -Path $WinREDrivers) {
        Write-Log -Message "Cleaning up previously created directory: $WinREDrivers"
        Remove-Item $WinREDrivers -Force -Verbose -Recurse | Out-Null
    }
     
    New-Item -ItemType Directory -Path $WinREDrivers -Force -ErrorAction Stop | Out-Null
    
} catch {
    Write-Log -Message "Failed to create WinRE drivers directory: $WinREDrivers" -ErrorMessage "ERROR"
    exit 1
}

# Get all installed drivers and filter by target INF files
Write-Log -Message "Getting all of the drivers for WinRE"
try {
    $Drivers = Get-WindowsDriver -Online -All | Where-Object { 
        $_.OriginalFileName -and ($TargetInfFiles -contains [System.IO.Path]::GetFileName($_.OriginalFileName).ToLower())
    }
} catch {
    Write-Log "Failed to retrieve drivers using Get-WindowsDriver: $_" -ErrorMessage "ERROR"
    exit
}

# Create a hashtable to store the newest driver for each INF
$DriverTable = @{}

# Iterate through drivers to find the newest version for each INF
foreach ($Driver in $Drivers) {
    $InfName = [System.IO.Path]::GetFileName($Driver.OriginalFileName).ToLower()
    $DriverVersion = $Driver.Version

    # Skip if InfName is empty (shouldn't happen due to filter)
    if (-not $InfName) { continue }

    # Convert DriverVersion to a Version object for comparison
    try {
        $Version = [Version]$DriverVersion
    } catch {
        Write-Log -Message "Unable to parse version for driver with INF: $InfName. Skipping." -ErrorMessage "ERROR"
        continue
    }

    # If INF is not in the hashtable or the current driver has a newer version, update the hashtable
    if (-not $DriverTable.ContainsKey($InfName) -or [Version]$DriverTable[$InfName].Version -lt $Version) {
        $DriverTable[$InfName] = $Driver
    }
}

# Check if any drivers were found
if ($DriverTable.Count -eq 0) {
    Write-Log -Message "No drivers found for the specified INF files...exiting script." 
    exit
}

# Export the newest drivers
foreach ($InfName in $DriverTable.Keys) {
    $Driver = $DriverTable[$InfName]
    $DriverVersion = $Driver.Version
    $DriverInf = $InfName
    $ProviderName = $Driver.ProviderName
    $DriverOemInf = $Driver.Driver  # Use Driver property (OEM INF name, e.g., oemXX.inf)

    # Extract subdirectory name from OriginalFileName
    $OriginalFileName = $Driver.OriginalFileName
    $SubDirName = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($OriginalFileName))
    $ExportSubDir = Join-Path -Path $WinREDrivers -ChildPath $SubDirName

    # Create subdirectory for this driver
    if (-not (Test-Path -Path $ExportSubDir)) {
        New-Item -ItemType Directory -Path $ExportSubDir -Force | Out-Null
    }

    Write-Log -Message "Exporting driver: $ProviderName (INF: $DriverInf, Version: $DriverVersion, OEM INF: $DriverOemInf, Subdirectory: $SubDirName)" 

    # Use pnputil to export the driver using the Driver property
    try {
        $PnPUtilCommand = "pnputil.exe /export-driver $DriverOemInf `"$ExportSubDir`""
        $Result = Invoke-Expression $PnPUtilCommand 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Message "Failed to export driver $DriverOemInf to $ExportSubDir. Error: $Result" -ErrorMessage "ERROR"
        } else {
            Write-Log -Message "Successfully exported $DriverOemInf to $ExportSubDir" 
        }
    } catch {
        Write-Log -Message "Error exporting driver $DriverOemInf to $ExportSubDir : $_"
    }
}

# Driver Export Finish
Write-Log -Message "Driver export completed."

# Creating the WinREMount directory
Write-Log -Message "Creating WinRE Mount directory: $WinREMount"
try {
    if (Test-Path -Path $WinREMount) {
        Write-Log -Message "Cleaning up previously created directory: $WinREMount"
        Remove-Item $WinREMount -Force -Verbose -Recurse | Out-Null
    } 

    New-Item -ItemType Directory -Path $WinREMount -Force -ErrorAction Stop | Out-Null
    
} catch {
    Write-Log -Message "Failed to create WinRE mount directory: $WinREMount" -ErrorMessage "ERROR"
    exit 1
}

# Mount WinRE.wim
Write-Log "Mounting WinRE WIM to: $WinREMount"
try {
    $mountResult = reagentc.exe /mountre /path $WinREMount 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Message "Failed to mount WinRE WIM. Error: $mountResult" -ErrorMessage "ERROR"
        exit 1
    }
    Write-Log -Message "Successfully mounted WinRE WIM"
} catch {
    Write-Log -Message "Exception while mounting WinRE WIM: $_" -ErrorMessage "ERROR"
    exit 1
}

# Add drivers to WinRE
Write-Log -Message "Adding drivers from: $WinREDrivers"
try {
    $dismResult = dism /Image:$WinREMount /Add-Driver /Driver:$WinREDrivers /Recurse 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Message "Failed to add drivers to WinRE. Error: $dismResult" -ErrorMessage "ERROR"
        # Attempt to unmount without committing changes
        try {
            reagentc.exe /unmountre /path $WinREMount /discard | Out-Null
            Write-Log -Message "Unmounted WinRE WIM without committing changes"
        } catch {
            Write-Log -Message "Failed to unmount WinRE WIM after driver add failure: $_" -ErrorMessage "ERROR"
        }
        exit 1
    }
    Write-Log "Successfully added drivers to WinRE"
} catch {
    Write-Log "Exception while adding drivers: $_" -Level "ERROR"
    exit 1
}

# Perform cleanup
Write-Log -Message "Performing cleanup on WinRE image"
try {
    $cleanupResult = dism /Image:$WinREMount /Cleanup-Image /StartComponentCleanup 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Message "Failed to perform cleanup on WinRE image. Error: $cleanupResult" -ErrorMessage "ERROR"
        # Continue to unmount, as cleanup failure is not critical
    } else {
        Write-Log -Message "Successfully performed cleanup on WinRE image"
    }
} catch {
    Write-Log -Message "Exception during image cleanup: $_" -ErrorMessage "ERROR"
}

# Unmount and commit WinRE.wim
Write-Log -Message "Unmounting and committing WinRE WIM"
try {
    $unmountResult = reagentc.exe /unmountre /path $WinREMount /commit 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Message "Failed to unmount and commit WinRE WIM. Error: $unmountResult" -ErrorMessage "ERROR"
        exit 1
    }
    Write-Log -Message "Successfully unmounted and committed WinRE WIM"
} catch {
    Write-Log -Message "Exception while unmounting WinRE WIM: $_" -ErrorMessage "ERROR"
    exit 1
}

# Clean up scratch directories
Write-Log -Message "Cleaning up directories: $WinREDrivers, $WinREMount"
try {
    if (Test-Path -Path $WinREDrivers) {
        Remove-Item -Path $WinREDrivers -Recurse -Force -ErrorAction Stop
        Write-Log -Message "Deleted directory: $WinREDrivers"
    }
    if (Test-Path -Path $WinREMount) {
        Remove-Item -Path $WinREMount -Recurse -Force -ErrorAction Stop
        Write-Log -Message "Deleted directory: $WinREMount"
    }
} catch {
    Write-Log -Message "Failed to clean up directories: $_" -ErrorMessage "WARNING"
}

# Final summary
Write-Log -Message "WinRE update process completed successfully"