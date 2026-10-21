# Assumes you downloaded the items from the DeployRSuite link and placed in your Downloads folder in a folder named DeployRSuite
# Will extract all of the zip files to a new folder named Extracted, then move all of the installers to the Extracted folder and remove any empty folders and zip files
# Each installed component (StifleR Server, Dashboards, WMI Agent, ActionHub, Beacon, DeployR) is only updated when the
# extracted MSI ProductVersion is newer than the installed DisplayVersion. Use -Force to install regardless of version.
# If DeployR itself was upgraded, the boot image is regenerated after a short delay (see -SkipRegenerate / -RegenerateDelaySeconds).

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipRegenerate,
    [string]$BootImageId = '00000003-0000-0000-0000-000000000001',   # Windows PE x64
    [string]$GenerateScriptPath = 'C:\Program Files\2Pint Software\DeployR\WebServer\Scripts\Generate.ps1',
    [int]$RegenerateDelaySeconds = 60
)

$sourceFolder = "$env:USERPROFILE\Downloads\"
$targetFolder = "$env:USERPROFILE\Downloads\StifleR\Extracted"


#region Functions

# Reads ProductVersion from the MSI Property table via the Windows Installer COM object.
# Every COM object is released explicitly: otherwise the MSI stays locked by this session until garbage collection,
# which breaks overwriting/moving the file when the script is re-run in the same (e.g. dot-sourced) session.
function Get-MsiProductVersion
{
    param([string]$Path)
    $Installer = $null; $Database = $null; $View = $null; $Record = $null
    try {
        $Installer = New-Object -ComObject WindowsInstaller.Installer
        $Database = $Installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $Installer, @($Path, 0))
        $View = $Database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $Database, @("SELECT Value FROM Property WHERE Property = 'ProductVersion'"))
        $View.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $View, $null) | Out-Null
        $Record = $View.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $View, $null)
        $Version = $Record.GetType().InvokeMember('StringData', 'GetProperty', $null, $Record, 1)
        $View.GetType().InvokeMember('Close', 'InvokeMethod', $null, $View, $null) | Out-Null
        return $Version
    }
    finally {
        foreach ($ComObject in @($Record, $View, $Database, $Installer)) {
            if ($null -ne $ComObject) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ComObject) }
        }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }
}

# Parses a version string into a 4-part [version] so 3.1.2642 and 3.1.2642.0 compare as equal. Returns $null if unparseable.
function ConvertTo-NormalizedVersion
{
    param([string]$Text)
    try {
        $v = [version]$Text
        return [version]::new($v.Major, $v.Minor, [Math]::Max($v.Build, 0), [Math]::Max($v.Revision, 0))
    }
    catch { return $null }
}

# Returns $true when the MSI should be installed: its ProductVersion is newer than the installed DisplayVersion.
# Returns $false (and says why) when it is the same/older, or when there is no MSI to install.
# If either version cannot be determined it returns $true, so a parsing problem never blocks an update.
function Test-InstallNeeded
{
    param(
        [string]$Title,
        $Msi,
        $InstalledApps
    )

    if (-not $Msi) {
        Write-Host "No $Title MSI found in the extracted files. Skipping update." -ForegroundColor Yellow
        return $false
    }

    # Prefer an exact name match; fall back to a partial match and use the highest installed version
    $Matched = @($InstalledApps | Where-Object { $_.DisplayName -eq $Title })
    if ($Matched.Count -eq 0) { $Matched = @($InstalledApps | Where-Object { $_.DisplayName -like "*$Title*" }) }
    $InstalledVersion = $Matched | ForEach-Object { ConvertTo-NormalizedVersion $_.DisplayVersion } |
        Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1

    try { $MsiVersion = ConvertTo-NormalizedVersion (Get-MsiProductVersion -Path $Msi.FullName) }
    catch { $MsiVersion = $null }

    if (-not $MsiVersion -or -not $InstalledVersion) {
        Write-Host "Could not compare versions for $Title (MSI: '$MsiVersion', installed: '$InstalledVersion'). Installing anyway." -ForegroundColor Yellow
        return $true
    }
    if ($Force) {
        Write-Host "$Title installed $InstalledVersion, MSI $MsiVersion. -Force specified, installing." -ForegroundColor Cyan
        return $true
    }
    if ($MsiVersion -gt $InstalledVersion) {
        Write-Host "$Title installed $InstalledVersion, MSI $MsiVersion is newer. Updating." -ForegroundColor Cyan
        return $true
    }
    Write-Host "$Title installed $InstalledVersion, MSI $MsiVersion is not newer. Skipping update." -ForegroundColor Yellow
    return $false
}

# Imports DeployR.Utility and authenticates with the local client passcode.
# Connect-DeployR stores the token in $env:DeployRToken, which Generate.ps1 inherits when run as a child process.
function Connect-ToDeployR
{
    $ModulePath = 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
    # -Force so the module that was just upgraded is loaded, not a stale copy from this session
    if (Test-Path -Path $ModulePath) { Import-Module $ModulePath -Force -ErrorAction Stop }
    elseif (Get-Module -ListAvailable -Name DeployR.Utility) { Import-Module DeployR.Utility -Force -ErrorAction Stop }
    else { throw 'DeployR.Utility module not found. Ensure the DeployR Client is installed on this machine.' }

    $RegPath = 'HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings'
    if (Test-Path -Path $RegPath) {
        $Passcode = (Get-Item -Path $RegPath).GetValue('ClientPasscode')
    }
    elseif (Test-Path -Path 'D:\DeployRPasscode.txt') {
        $Passcode = (Get-Content -Path 'D:\DeployRPasscode.txt' -Raw).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($Passcode)) {
        throw 'Cannot find the DeployR client passcode in the registry or D:\DeployRPasscode.txt.'
    }
    Connect-DeployR -Passcode $Passcode -ErrorAction Stop | Out-Null
}

# Regenerates a DeployR boot image by running DeployR's Generate.ps1 -Id <id> -Regenerate.
# Generate.ps1 uses relative paths, so it runs from its own folder. Returns $true on success.
function Invoke-BootImageRegeneration
{
    param(
        [string]$BootImageId,
        [string]$GenerateScriptPath
    )
    try {
        if (-not (Test-Path -Path $GenerateScriptPath -PathType Leaf)) { throw "Generate.ps1 not found: $GenerateScriptPath" }
        Write-Host "Connecting to DeployR..." -ForegroundColor Cyan
        Connect-ToDeployR

        Write-Host "Regenerating boot image $BootImageId..." -ForegroundColor Cyan
        $GenerateArgs = @('-NoProfile', '-File', "`"$GenerateScriptPath`"", '-Id', $BootImageId, '-Regenerate')
        $Generate = Start-Process -FilePath (Join-Path -Path $PSHOME -ChildPath 'pwsh.exe') -ArgumentList $GenerateArgs -WorkingDirectory (Split-Path -Path $GenerateScriptPath -Parent) -Wait -NoNewWindow -PassThru -ErrorAction Stop
        if ($Generate.ExitCode -ne 0) { throw "Generate.ps1 exited with code $($Generate.ExitCode)" }
        Write-Host "Boot image $BootImageId regenerated." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Boot image regeneration failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-InstalledApps
{
    if (![Environment]::Is64BitProcess) {
        $regpath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    }
    else {
        $regpath = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
    }
    
    # Get all installed apps, filter out those without InstallDate, and keep only the latest version of each
    $allApps = Get-ItemProperty -Path $regpath -ErrorAction SilentlyContinue |
    Where-Object {
        $_.PSObject.Properties['DisplayName'] -and
        $_.PSObject.Properties['UninstallString'] -and
        $_.DisplayName -and
        $_.UninstallString
    } |
    Select DisplayName, Publisher, InstallDate, DisplayVersion, UninstallString, InstallLocation
    
    # Filter out apps without InstallDate and group by DisplayName to keep only the latest
    $filteredApps = $allApps | Where-Object { $_.InstallDate -and $_.InstallDate -ne '' } | 
    Group-Object -Property DisplayName | 
    ForEach-Object {
        $_.Group | Sort-Object -Property InstallDate -Descending | Select-Object -First 1
    }
    
    return $filteredApps | Sort-Object DisplayName
}

#endregion Functions


if (!(Test-Path -Path $sourceFolder)) {
    Write-Host "Source folder does not exist: $sourceFolder"
    exit
}
if (!(Test-Path -Path $targetFolder)) {
    New-Item -ItemType Directory -Path $targetFolder | Out-Null
}

#Unblock any Zip files in the source folder
Get-ChildItem -Path $sourceFolder -Filter *.zip | Unblock-File

#Extract each zip file to the target folder, creating a subfolder for each zip file based on its name
$StifleRZipFiles = @(Get-ChildItem -Path $sourceFolder -Filter StifleR*.zip)
if ($StifleRZipFiles.Count -eq 0) {
    Write-Host "No StifleR zip files found in source folder: $sourceFolder"
    exit
}
if ($StifleRZipFiles.Count -gt 1) {
    Write-Host "Multiple StifleR zip files found in source folder: $sourceFolder. Lets look for the latest one." -ForegroundColor Green
    $latestZip = $StifleRZipFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "Latest StifleR zip file found: $($latestZip.Name)"
}
else {
    $latestZip = $StifleRZipFiles
    Write-Host "Single StifleR zip file found: $($latestZip.Name)"
}
$latestZip | ForEach-Object {
    $zipFile = $_.FullName
    $fileName = $_.Name
    $destination = Join-Path -Path $targetFolder -ChildPath $_.BaseName
    Expand-Archive -Path $zipFile -DestinationPath $destination -Force
    Write-Host "Extracted: $fileName to $destination" -ForegroundColor DarkGray
    #Confirm it Extracted Successfully by checking for the presence of the extracted folder
    if (Test-Path -Path $destination) {
        Write-Host "Successfully extracted: $fileName" -ForegroundColor Green
    } else {
        Write-Host "Failed to extract: $fileName" -ForegroundColor Red
    }
}

#Dig into the StifleR folder and extract all of the additional zip files found there to the target folder, creating subfolders for each zip file based on their names
$stifleRFolder = (Get-ChildItem -Path $targetFolder -Directory | Where-Object { $_.Name -like "StifleR*" } | Select-Object -First 1).FullName
if (Test-Path -Path $stifleRFolder) {
    Get-ChildItem -Path $stifleRFolder -Filter *.zip | ForEach-Object {
        $zipFile = $_.FullName
        $destination = Join-Path -Path $targetFolder -ChildPath $_.BaseName
        Expand-Archive -Path $zipFile -DestinationPath $destination -Force
        Write-Host "Extracted: $zipFile to $destination"
    }
} else {
    Write-Host "StifleR folder not found: $stifleRFolder"
}
#Dig into the extracted folders and move the contents to the target folder, then remove the now empty subfolders
Get-ChildItem -Path $targetFolder -Directory | ForEach-Object {
    $subFolder = $_.FullName
    Get-ChildItem -Path $subFolder -Recurse | Move-Item -Destination $targetFolder -Force
    Remove-Item -Path $subFolder -Recurse -Force
    Write-Host "Moved contents of: $subFolder to $targetFolder and removed $subFolder"
}
#Delete all .wixpdb files from the target folder
Get-ChildItem -Path $targetFolder -Filter *.wixpdb | Remove-Item

#Cleanup all empty folders from the target folder
Get-ChildItem -Path $targetFolder -Directory -Recurse | Where-Object { $_.GetFileSystemInfos().Count -eq 0 } | Remove-Item -Force

#Cleanup all .zip files from the target folder
Get-ChildItem -Path $targetFolder -Filter *.zip | Remove-Item -Force

#Move any installers from subfolders to the target folder and remove the now empty subfolders (MSI or EXE files)
Get-ChildItem -Path $targetFolder -Directory | ForEach-Object {
    $subFolder = $_.FullName
    Get-ChildItem -Path $subFolder -Filter *.exe -Recurse | Move-Item -Destination $targetFolder -Force
    Get-ChildItem -Path $subFolder -Filter *.msi -Recurse | Move-Item -Destination $targetFolder -Force
    Remove-Item -Path $subFolder -Recurse -Force
    Write-Host "Moved installers from: $subFolder to $targetFolder and removed $subFolder"
}

$MSIFiles = Get-ChildItem -Path $targetFolder  -Filter *.msi
$Dashboard = $MSIFiles | Where-Object { $_.Name -like "*Dashboard*.msi" } | Select-Object -First 1
$StiflerRServer = $MSIFiles | Where-Object { $_.Name -like "*Server*.msi" } | Select-Object -First 1 
$WMIAgent = $MSIFiles | Where-Object { $_.Name -like "*WMI*.msi" } | Select-Object -First 1  
$ActionHub = $MSIFiles | Where-Object { $_.Name -like "*ActionHub*.msi" } | Select-Object -First 1
$Beacon = $MSIFiles | Where-Object { $_.Name -like "*Beacon*.msi" } | Select-Object -First 1

$PreReqApps = @(
[PSCustomObject]@{Title = '2Pint Software DeployR'; Installed = $false; Notes = 'Required for DeployR Servers'; URL = 'https://documentation.2pintsoftware.com/deployr'}
[PSCustomObject]@{Title = '2Pint Software StifleR Server'; Installed = $false; Notes = 'Required for DeployR Servers'; URL = 'https://documentation.2pintsoftware.com/stifler'}
[PSCustomObject]@{Title = '2Pint Software StifleR Dashboards'; Installed = $false; Notes = 'Required for DeployR Servers'; URL = 'https://documentation.2pintsoftware.com/stifler'}
[PSCustomObject]@{Title = '2Pint Software StifleR Beacon'; Installed = $false; Notes = 'OPTIONAL for DeployR Servers'; URL = 'https://documentation.2pintsoftware.com/stifler'}
[PSCustomObject]@{Title = '2Pint Software StifleR WmiAgent'; Installed = $false; Notes = 'OPTIONAL for DeployR Servers'; URL = 'https://documentation.2pintsoftware.com/stifler'}
[PSCustomObject]@{Title = '2Pint Software StifleR ActionHub'; Installed = $false; Notes = 'OPTIONAL for DeployR Servers'; URL = 'https://documentation.2pintsoftware.com/stifler'}
[PSCustomObject]@{Title = '2Pint Software iPXE Anywhere WebService'; Installed = $false; Notes = 'OPTIONAL for DeployR Servers'; URL = 'https://documentation.2pintsoftware.com/ipxe-ws'}
[PSCustomObject]@{Title = '2Pint Software PXE Server'; Installed = $false; Notes = 'OPTIONAL for DeployR Servers'; URL = 'https://documentation.2pintsoftware.com/2pxe-server'}

)

#Test if Applications are installed
$installedApps = Get-InstalledApps | Where-Object {$_.DisplayName -notmatch " - Shared framework"}
$installedApps = $installedApps | Where-Object {$_.DisplayName -notmatch "SDK"}
$installedApps = $installedApps | Where-Object {$_.DisplayName -notmatch "AppHost"}


$PreReqStatus = @()

foreach ($app in $PreReqApps) {
    $found = $installedApps | Where-Object {
        $_.DisplayName -match [regex]::Escape($app.Title) -or
        $_.DisplayName -like "*$($app.Title)*"
    }

    if ($found) {
        $app.Installed = $true
        New-Variable -Name "Installed_$($app.Title.Replace(' ', '_'))" -Value $true -Scope Global -Force -Verbose
    }
    else {
        $app.Installed = $false
        New-Variable -Name "Installed_$($app.Title.Replace(' ', '_'))" -Value $false -Scope Global -Force
    }

    $PreReqStatus += [PSCustomObject]@{
        Title            = $app.Title
        'Installed Status' = $app.Installed
    }
}

#Close Event Viewer and 2Pint Config Editor before any product installer starts
$BlockingUiProcesses = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'mmc.exe' OR Name = 'eventvwr.exe' OR Name = 'TwoPint.ConfigEditor.Wpf.exe'" -ErrorAction Stop |
    Where-Object {
        $_.Name -eq 'eventvwr.exe' -or
        $_.Name -eq 'TwoPint.ConfigEditor.Wpf.exe' -or
        $_.CommandLine -match '(?i)\beventvwr\.msc\b'
    })
if ($BlockingUiProcesses.Count -gt 0) {
    Write-Host "Closing Event Viewer and 2Pint Config Editor before installing updates. Unsaved work may be lost." -ForegroundColor Yellow
    foreach ($BlockingUiProcess in $BlockingUiProcesses) {
        $ProcessDescription = if ($BlockingUiProcess.Name -eq 'TwoPint.ConfigEditor.Wpf.exe') { '2Pint Config Editor' } else { 'Event Viewer' }
        Write-Host "Closing $ProcessDescription (PID $($BlockingUiProcess.ProcessId))" -ForegroundColor DarkGray
        Stop-Process -Id $BlockingUiProcess.ProcessId -Force -ErrorAction Stop
    }
}

#Install StifleR
if ($Installed_2Pint_Software_StifleR_Server -and (Test-InstallNeeded -Title '2Pint Software StifleR Server' -Msi $StiflerRServer -InstalledApps $installedApps)) {
    Write-Host "StifleR Server is installed. Installing StifleR Server update..."
    $ServerInstall = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($StiflerRServer.FullName)`" /qb! /l*v C:\Windows\Temp\StifleRServerInstall.log" -Wait -NoNewWindow -PassThru
    if ($ServerInstall.ExitCode -eq 0) {
        Write-Host "StifleR Server update installed successfully. Starting Service" -ForegroundColor Green
        Set-Service -Name StifleRServer -StartupType Automatic
        Start-Service -Name StifleRServer
    } else {
        Write-Host "StifleR Server update installation failed with exit code: $($ServerInstall.ExitCode)" -ForegroundColor Red
    }
    
} else {
    Write-Host "StifleR Server is not installed or is already up to date. Skipping update."
}

#Install DashBoard

if ($Installed_2Pint_Software_StifleR_Dashboards -and (Test-InstallNeeded -Title '2Pint Software StifleR Dashboards' -Msi $Dashboard -InstalledApps $installedApps)) {
    Write-Host "StifleR Dashboard is installed. Installing StifleR Dashboard update..."
    $DashboardInstall = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($Dashboard.FullName)`" /qb! /l*v C:\Windows\Temp\StifleRDashboardInstall.log" -Wait -NoNewWindow -PassThru
    if ($DashboardInstall.ExitCode -eq 0) {
        Write-Host "StifleR Dashboard update installed successfully." -ForegroundColor Green
    } else {
        Write-Host "StifleR Dashboard update installation failed with exit code: $($DashboardInstall.ExitCode)" -ForegroundColor Red
    }
    
} else {
    Write-Host "StifleR Dashboard is not installed or is already up to date. Skipping update."
}

#Install WMIAgent

if ($Installed_2Pint_Software_StifleR_WmiAgent -and (Test-InstallNeeded -Title '2Pint Software StifleR WmiAgent' -Msi $WMIAgent -InstalledApps $installedApps)) {
    Write-Host "StifleR WMI Agent is installed. Installing StifleR WMI Agent update..."
    $WMIAgentInstall = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($WMIAgent.FullName)`" /qb! /l*v C:\Windows\Temp\WMIAgentInstall.log" -Wait -NoNewWindow -PassThru
    if ($WMIAgentInstall.ExitCode -eq 0) {
        Write-Host "StifleR WMI Agent update installed successfully." -ForegroundColor Green
        Set-Service -Name StifleRWmiAgent -StartupType Automatic
        Start-Service -Name StifleRWmiAgent
    } else {
        Write-Host "StifleR WMI Agent update installation failed with exit code: $($WMIAgentInstall.ExitCode)" -ForegroundColor Red
    }
    
} else {
    Write-Host "StifleR WMI Agent is not installed or is already up to date. Skipping update."
}

#Install ActionHub
if ($Installed_2Pint_Software_StifleR_ActionHub -and (Test-InstallNeeded -Title '2Pint Software StifleR ActionHub' -Msi $ActionHub -InstalledApps $installedApps)) {
    Write-Host "StifleR ActionHub is installed. Installing StifleR ActionHub update..."
    $ActionHubInstall = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($ActionHub.FullName)`" /qb! /l*v C:\Windows\Temp\StifleRActionHubInstall.log" -Wait -NoNewWindow -PassThru
    if ($ActionHubInstall.ExitCode -eq 0) {
        Write-Host "StifleR ActionHub update installed successfully." -ForegroundColor Green
        Set-Service -Name StifleRActionHub -StartupType Automatic
        Start-Service -Name StifleRActionHub
    } else {
        Write-Host "StifleR ActionHub update installation failed with exit code: $($ActionHubInstall.ExitCode)" -ForegroundColor Red
    }
    
} else {
    Write-Host "StifleR ActionHub is not installed or is already up to date. Skipping update."
}
#Install Beacon
if ($Installed_2Pint_Software_StifleR_Beacon -and (Test-InstallNeeded -Title '2Pint Software StifleR Beacon' -Msi $Beacon -InstalledApps $installedApps)) {
    Write-Host "StifleR Beacon is installed. Installing StifleR Beacon update..."
    $BeaconInstall = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($Beacon.FullName)`" /qb! /l*v C:\Windows\Temp\StifleRBeaconInstall.log" -Wait -NoNewWindow -PassThru
    if ($BeaconInstall.ExitCode -eq 0) {
        Write-Host "StifleR Beacon update installed successfully." -ForegroundColor Green
        Set-Service -Name StifleRBeacon -StartupType Automatic
        Start-Service -Name StifleRBeacon
    } else {
        Write-Host "StifleR Beacon update installation failed with exit code: $($BeaconInstall.ExitCode)" -ForegroundColor Red
    }
    
} else {
    Write-Host "StifleR Beacon is not installed or is already up to date. Skipping update."
}


#Processes for DeployR
if ($Installed_2Pint_Software_DeployR) {
    Write-Host "DeployR is installed. Looking for the latest DeployR update..."
    $DeployRZip = Get-ChildItem -Path $sourceFolder -Filter 'DeployR-*.zip' -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($DeployRZip) {
        try {
            Write-Host "Latest DeployR zip file found: $($DeployRZip.Name)"
            $DeployRTargetFolder = Join-Path -Path "$env:USERPROFILE\Downloads\DeployR\Extracted" -ChildPath ([guid]::NewGuid().ToString())
            Expand-Archive -Path $DeployRZip.FullName -DestinationPath $DeployRTargetFolder -Force -ErrorAction Stop
            $DeployRNestedZips = @(Get-ChildItem -Path $DeployRTargetFolder -Filter '*.zip' -File -Recurse)
            foreach ($DeployRNestedZip in $DeployRNestedZips) {
                $DeployRNestedDestination = Join-Path -Path $DeployRNestedZip.DirectoryName -ChildPath $DeployRNestedZip.BaseName
                Expand-Archive -Path $DeployRNestedZip.FullName -DestinationPath $DeployRNestedDestination -Force -ErrorAction Stop
            }
            $DeployRInstallers = @(Get-ChildItem -Path $DeployRTargetFolder -Filter '*DeployR*.msi' -File -Recurse |
                Where-Object { $_.Name -notmatch 'Community|Client' })
            if ($DeployRInstallers.Count -ne 1) {
                throw "Expected one DeployR server MSI in the selected archive; found $($DeployRInstallers.Count)."
            }
            $DeployRInstaller = $DeployRInstallers[0]
            Unblock-File -Path $DeployRInstaller.FullName -ErrorAction Stop
            # Check the version before closing the Log Viewer; only continue when the extracted MSI is newer than what is installed
            if (Test-InstallNeeded -Title '2Pint Software DeployR' -Msi $DeployRInstaller -InstalledApps $installedApps) {
                $DeployRLogViewerProcesses = @(Get-Process -Name 'TwoPint.DeployR.LogViewer' -ErrorAction SilentlyContinue)
                foreach ($DeployRLogViewerProcess in $DeployRLogViewerProcesses) {
                    Write-Host "Closing DeployR Log Viewer (PID $($DeployRLogViewerProcess.Id))" -ForegroundColor DarkGray
                    Stop-Process -Id $DeployRLogViewerProcess.Id -Force -ErrorAction Stop
                }
                Write-Host "Installing DeployR update: $($DeployRInstaller.Name)"
                # /qb! shows the basic progress bar (no Cancel button) so the upgrade can be watched
                $DeployRInstall = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$($DeployRInstaller.FullName)`" /qb! /norestart MSIRESTARTMANAGERCONTROL=0 MSIRMSHUTDOWN=1 /l*v C:\Windows\Temp\DeployRInstall.log" -Wait -NoNewWindow -PassThru -ErrorAction Stop
                if ($DeployRInstall.ExitCode -in @(0, 3010, 1641)) {
                    Write-Host "DeployR update installed successfully." -ForegroundColor Green
                    if ($DeployRInstall.ExitCode -ne 0) {
                        # Service is not started until the reboot, so the boot image cannot be regenerated yet
                        Write-Host "A restart is required to complete the DeployR update. Restart, then regenerate boot image $BootImageId (Generate.ps1 -Id $BootImageId -Regenerate)." -ForegroundColor Yellow
                    }
                    else {
                        Set-Service -Name DeployRService -StartupType Automatic -ErrorAction Stop
                        Start-Service -Name DeployRService -ErrorAction Stop

                        # DeployR was upgraded, so the boot image needs to be rebuilt; give the service time to come up first
                        if ($SkipRegenerate) {
                            Write-Host 'SkipRegenerate specified, not regenerating the boot image.' -ForegroundColor Yellow
                        }
                        else {
                            Write-Host "Waiting $RegenerateDelaySeconds seconds for DeployR to settle before regenerating the boot image..." -ForegroundColor Cyan
                            Start-Sleep -Seconds $RegenerateDelaySeconds
                            [void](Invoke-BootImageRegeneration -BootImageId $BootImageId -GenerateScriptPath $GenerateScriptPath)
                        }
                    }
                }
                else {
                    Write-Host "DeployR update installation failed with exit code: $($DeployRInstall.ExitCode). See C:\Windows\Temp\DeployRInstall.log" -ForegroundColor Red
                }
            }
        }
        catch {
            Write-Host "DeployR update failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "No DeployR zip files found in source folder: $sourceFolder. Skipping update." -ForegroundColor Yellow
    }
} else {
    Write-Host "DeployR is not installed. Skipping update."
}
