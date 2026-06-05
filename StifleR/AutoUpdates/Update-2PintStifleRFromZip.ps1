# Assumes you downloaded the items from the DeployRSuite link and placed in your Downloads folder in a folder named DeployRSuite
# Will extract all of the zip files to a new folder named Extracted, then move all of the installers to the Extracted folder and remove any empty folders and zip files

$sourceFolder = "$env:USERPROFILE\Downloads\"
$targetFolder = "$env:USERPROFILE\Downloads\StifleR\Extracted"


#region Functions

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
    $allApps = Get-ItemProperty $regpath | .{process{if($_.DisplayName -and $_.UninstallString) { $_ } }} | 
    Select DisplayName, Publisher, InstallDate, DisplayVersion, UninstallString, InstallLocation
    
    # Filter out apps without InstallDate and group by DisplayName to keep only the latest
    $filteredApps = $allApps | Where-Object { $_.InstallDate -and $_.InstallDate -ne '' } | 
    Group-Object -Property DisplayName | 
    ForEach-Object {
        $_.Group | Sort-Object -Property InstallDate -Descending | Select-Object -First 1
    }
    
    return $allApps | Sort-Object DisplayName
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
$StifleRZipFiles = Get-ChildItem -Path $sourceFolder -Filter StifleR*.zip
if ($StifleRZipFiles.Count -eq 0) {
    Write-Host "No StifleR zip files found in source folder: $sourceFolder"
    exit
}
if ($StifleRZipFiles.Count -gt 1) {
    Write-Host "Multiple StifleR zip files found in source folder: $sourceFolder. Lets look for the latest one." -ForegroundColor Green
    $latestZip = $StifleRZipFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "Latest StifleR zip file found: $($latestZip.Name)"
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

#Install StifleR
if ($Installed_2Pint_Software_StifleR_Server) {
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
    Write-Host "StifleR Server is not installed. Skipping update."
}

#Install DashBoard

if ($Installed_2Pint_Software_StifleR_Dashboards) {
    Write-Host "StifleR Dashboard is installed. Installing StifleR Dashboard update..."
    $DashboardInstall = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($Dashboard.FullName)`" /qb! /l*v C:\Windows\Temp\StifleRDashboardInstall.log" -Wait -NoNewWindow -PassThru
    if ($DashboardInstall.ExitCode -eq 0) {
        Write-Host "StifleR Dashboard update installed successfully." -ForegroundColor Green
    } else {
        Write-Host "StifleR Dashboard update installation failed with exit code: $($DashboardInstall.ExitCode)" -ForegroundColor Red
    }
    
} else {
    Write-Host "StifleR Dashboard is not installed. Skipping update."
}

#Install WMIAgent

if ($Installed_2Pint_Software_StifleR_WmiAgent) {
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
    Write-Host "StifleR WMI Agent is not installed. Skipping update."
}

#Install ActionHub
if ($Installed_2Pint_Software_StifleR_ActionHub) {
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
    Write-Host "StifleR ActionHub is not installed. Skipping update."
}
#Install Beacon
if ($Installed_2Pint_Software_StifleR_Beacon) {
    Write-Host "StifleR Beacon is installed. Installing StifleR Beacon update..."
    $BeaconInstall = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($Beacon.FullName)`" /qb! /l*v C:\Windows\Temp\StifleRBeaconInstall.log" -Wait -NoNewWindow -PassThru
    if ($BeaconInstall.ExitCode -eq 0) {
        Write-Host "StifleR Beacon update installed successfully." -ForegroundColor Green
    } else {
        Write-Host "StifleR Beacon update installation failed with exit code: $($BeaconInstall.ExitCode)" -ForegroundColor Red
    }
    
} else {
    Write-Host "StifleR Beacon is not installed. Skipping update."
}



