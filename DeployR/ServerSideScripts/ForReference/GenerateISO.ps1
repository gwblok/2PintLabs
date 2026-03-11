#region functions
function Copy-File {
    param (
        [string]$path,
        [string]$Destination,
        [switch]$Force = $false,
        [switch]$Recurse = $false
    )
    if (Test-Path $path) {
        if ($Recurse) {
            Write-Host "Recursively copying $path to $Destination" -ForegroundColor Green
            Copy-Item -Path $path -Destination $Destination -Recurse -Force:$Force
        }
        else {

            Write-Host "Copying $path to $Destination" -ForegroundColor Green
            Copy-Item -Path $path -Destination $Destination -Force:$Force
        }
    }
    else {
        Write-Host "Source file not found: $path" -ForegroundColor Green
    }
}
Function Get-AdkPaths {
    [CmdletBinding()]
    param (
    [Parameter(Position = 0, ValueFromPipelineByPropertyName = $true)]
    [ValidateSet('amd64', 'x86', 'arm64')]
    [string]$Arch = $Env:PROCESSOR_ARCHITECTURE
    )
    $InstalledRoots32 = 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots'
    $InstalledRoots64 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots'
    if (Test-Path $InstalledRoots64) {
        $KitsRoot10 = Get-ItemPropertyValue -Path $InstalledRoots64 -Name 'KitsRoot10'
    }
    elseif (Test-Path $InstalledRoots32) {
        $KitsRoot10 = Get-ItemPropertyValue -Path $InstalledRoots32 -Name 'KitsRoot10'
    }
    else {
        Write-Host "Unable to determine ADK Path" -ForegroundColor Green
        Break
    }
    $AdkRoot = Join-Path $KitsRoot10 'Assessment and Deployment Kit'
    $WinPERoot = Join-Path $AdkRoot 'Windows Preinstallation Environment'
    if (-NOT (Test-Path $WinPERoot -PathType Container)) {
        Write-Host "Cannot find WinPERoot: $WinPERoot" -ForegroundColor Green
        $WinPERoot = $null
        break
    }
    $PathDeploymentTools = Join-Path $AdkRoot (Join-Path 'Deployment Tools' $Arch)
    $Results = [PSCustomObject] @{
        AdkRoot             = $AdkRoot
        PathBCDBoot         = Join-Path $PathDeploymentTools 'BCDBoot'
        PathDeploymentTools = $PathDeploymentTools
        PathDISM            = Join-Path $PathDeploymentTools 'DISM'
        PathOscdimg         = Join-Path $PathDeploymentTools 'Oscdimg'
        PathUsmt            = Join-Path $AdkRoot (Join-Path 'User State Migration Tool' $Arch)
        PathWinPE           = Join-Path $WinPERoot $Arch
        PathWinPEMedia      = Join-Path (Join-Path $WinPERoot $Arch) 'Media'
        PathWinSetup        = Join-Path $AdkRoot (Join-Path 'Windows Setup' $Arch)
        WinPEOCs            = Join-Path (Join-Path $WinPERoot $Arch) 'WinPE_OCs'
        WinPERoot           = $WinPERoot
        WimSourcePath       = Join-Path (Join-Path $WinPERoot $Arch) 'en-us\winpe.wim'
        
        bcdbootexe          = Join-Path $PathDeploymentTools (Join-Path 'BCDBoot' 'bcdboot.exe')
        bcdeditexe          = Join-Path $PathDeploymentTools (Join-Path 'BCDBoot' 'bcdedit.exe')
        bootsectexe         = Join-Path $PathDeploymentTools (Join-Path 'BCDBoot' 'bootsect.exe')
        dismexe             = Join-Path $PathDeploymentTools (Join-Path 'DISM' 'dism.exe')
        efisysbin           = Join-Path $PathDeploymentTools (Join-Path 'Oscdimg' 'efisys.bin')
        efisysnopromptbin   = Join-Path $PathDeploymentTools (Join-Path 'Oscdimg' 'efisys_noprompt.bin')
        etfsbootcom         = Join-Path $PathDeploymentTools (Join-Path 'Oscdimg' 'etfsboot.com')
        imagexexe           = Join-Path $PathDeploymentTools (Join-Path 'DISM' 'imagex.exe')
        oa3toolexe          = Join-Path $PathDeploymentTools (Join-Path 'Licensing\OA30' 'oa3tool.exe')
        oscdimgexe          = Join-Path $PathDeploymentTools (Join-Path 'Oscdimg' 'oscdimg.exe')
        pkgmgrexe           = Join-Path $PathDeploymentTools (Join-Path 'DISM' 'pkgmgr.exe')
    }
    Return $Results
}

#endregion functions


$transcriptPath = "C:\Windows\Temp\DeployR_ISO_Generation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber
$TempDir = "C:\Windows\Temp\DeployR_ISO"
$ADKPaths = Get-AdkPaths
$adkRoot = $ADKPaths.AdkRoot
$peRoot = $ADKPaths.WinPERoot
$platform = "amd64"
$shortPlatform = 'x64'
$RegPath = "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"
$DeployRRegData = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
if ($DeployRRegData -and $DeployRRegData.ContentLocation) {
    Write-Host " DeployR ContentLocation: $($DeployRRegData.ContentLocation)" -ForegroundColor Green
    $DeployRContentPath = $DeployRRegData.ContentLocation
}
else {
    if (Test-Path "$env:ProgramData\2Pint Software\DeployR\Content") {
        Write-Host " DeployR ContentLocation (Default): $env:ProgramData\2Pint Software\DeployR" -ForegroundColor Yellow
        $DeployRContentPath = "$env:ProgramData\2Pint Software\DeployR\Content"
    }
    else {
        Write-Host " DeployR ContentLocation is NOT found in Registry and not in Default Location." -ForegroundColor Red
    }
}
$BootFolderPath = "$($DeployRContentPath)Content\Boot"
$WIMLocation = "$BootFolderPath\winpe_amd64.wim"
if (-not (Test-Path $WIMLocation)) {
    throw "PE WIM not found at expected location: $WIMLocation"
}
else {
    Write-Host "PE WIM found: $WIMLocation" -ForegroundColor Green
}


$isoNew = "$BootFolderPath\DeployR_$shortPlatform.iso"

# Create a temporary folder
$isoTemp = "$TempDir\Media"
if (Test-Path $isoTemp) {
    Remove-Item $isoTemp -Recurse -Force
}
Write-Host "Creating temporary directory: $isoTemp" -ForegroundColor Green
New-Item -Path $isoTemp -ItemType Directory | Out-Null

# Copy the boot files to the media
Write-Host "Copying boot files" -ForegroundColor Green
Copy-File -Path "$peRoot\$platform\Media\*" -Destination "$($isoTemp)\" -Recurse -Force

# Copy the PE WIM to the \Sources folder
Write-Host "Copying Windows PE boot image" -ForegroundColor Green
New-Item -Path "$($isoTemp)\Sources" -ItemType Directory | Out-Null
Copy-File -Path $peExported -Destination "$($isoTemp)\Sources\boot.wim" -Force

# Turn off driver integrity checks
#& bcdedit.exe /store "$isoTemp\EFI\Microsoft\Boot\BCD" /set "{default}" nointegritychecks on
#& bcdedit.exe /store "$isoTemp\EFI\Microsoft\Boot\BCD" /set "{default}" testsigning on
#& bcdedit.exe /store "$isoTemp\Boot\BCD" /set "{default}" nointegritychecks on
#& bcdedit.exe /store "$isoTemp\Boot\BCD" /set "{default}" testsigning on

# Capture the ISO
# We need some files that match the boot image architecture
$oscdimgDir = "$adkRoot\Deployment Tools\$platform\Oscdimg"
# But OSCDIMG.EXE itself needs to match this OS'es architecture
$oscdimg = "$adkRoot\Deployment Tools\$($env:PROCESSOR_ARCHITECTURE)\Oscdimg\OSCDIMG.EXE"
if (-not (Test-Path $oscdimg)) {
    throw "OSCDIMG.EXE not found at expected location: $oscdimg"
}
else {
    Write-Host "OSCDIMG.EXE found: $oscdimg" -ForegroundColor Green
}
if ($platform -ieq "arm64") {
    # No BIOS support, so only add the UEFI boot sector
    $proc = Start-Process -WorkingDirectory $oscdimgDir -FilePath $oscdimg -ArgumentList "-m -o -u2 -udfver102 -bootdata:1#pEF,e,bEfisys.bin `"$isoTemp`" `"$isoNew`"" -NoNewWindow -PassThru -Wait
}
else {
    # Use dual boot sectors
    $proc = Start-Process -WorkingDirectory $oscdimgDir -FilePath $oscdimg -ArgumentList "-m -o -u2 -udfver102 -bootdata:2#p0,e,betfsboot.com#pEF,e,bEfisys.bin `"$isoTemp`" `"$isoNew`"" -NoNewWindow -PassThru -Wait
}
if ($proc.ExitCode -ne 0) {
    throw "Failed to generate ISO: $($proc.ExitCode)"
}
Write-Host "ISO generated: $isoNew" -ForegroundColor Green

$isoNew = "$Destination\DeployR_$($shortPlatform)_noprompt.iso"
if ($platform -ieq "arm64") {
    $proc = Start-Process -WorkingDirectory $oscdimgDir -FilePath $oscdimg -ArgumentList "-m -o -u2 -udfver102 -bootdata:1#pEF,e,bEfisys_noprompt.bin `"$isoTemp`" `"$isoNew`"" -NoNewWindow -PassThru -Wait
}
else {
    $proc = Start-Process -WorkingDirectory $oscdimgDir -FilePath $oscdimg -ArgumentList "-m -o -u2 -udfver102 -bootdata:2#p0,e,betfsboot.com#pEF,e,bEfisys_noprompt.bin `"$isoTemp`" `"$isoNew`"" -NoNewWindow -PassThru -Wait
}
if ($proc.ExitCode -ne 0) {
    throw "Failed to generate ISO: $($proc.ExitCode)"
}
Write-Host "ISO generated: $isoNew" -ForegroundColor Green
Stop-Transcript