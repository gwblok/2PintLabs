<#
.SYNOPSIS
Builds separate Demo and Labs StifleR Client Intune packages after validating the MSI version.

.DESCRIPTION
Reads the StifleR 3.x version from the published client JSON and requires exactly one
local MSI whose ProductVersion matches it before invoking IntuneWinAppUtil.
Requires Windows, Windows Installer COM, internet access to the JSON and (if missing)
the packaging utility, and write access to the configured source and output folders.
Requires settings.2psImport in both Configs-2PintDemo and Configs-2PintLabs beneath
D:\SourceRepo\Applications\2PintSoftware\StifleRClientIntuneWin.
Creates missing folders and downloads the packaging utility if needed. Each build uses an
isolated staging folder containing only the validated MSI, the variant's settings, and its
generated install command. Temporary staging is removed on success or failure.
Packages are written beneath StifleRClientIntuneWin\2PintDemo\<ProductVersion> and
StifleRClientIntuneWin\2PintLabs\<ProductVersion>, replacing the same variant/version package
when rerun. Other source files and existing packages for other versions are not changed.
The final summary lists both package filenames and output folders, the MSI version, and
the MSI ProductCode.

.EXAMPLE
.\Update-2PintStifleRClientIntuneWin.ps1
Validates the local MSI against JSON and builds both Demo and Labs Intune packages.

.NOTES
Author: Gary Blok
Created: Not specified
Change History:
    2026-11-10 - Capture MSI ProductVersion and block packaging when it differs from JSON.
    2026-11-10 - Write each Intune package to its MSI version subfolder.
    2026-11-10 - Build isolated Demo and Labs packages with variant-specific settings.
    2026-11-10 - Summarize created packages, output folders, MSI version, and ProductCode.
#>

$ErrorActionPreference = 'Stop'

#Build App Intune Installer
$IntuneAppRootPath = "D:\SourceRepo\IntuneWin\AppUtil"

#Path to App Folder you want to Convert
$SourceAppPathRoot = "D:\SourceRepo\Applications\2PintSoftware"
$SourceAppPath = "$SourceAppPathRoot\StifleRClient"
$StagingTempPath = "D:\SourceRepo\Applications\2PintSoftware\StifleRClientIntuneWin\StagingTemp"


$JSONContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/GARYTOWN/StifleR-ClientApp.json"
$StifleR30 = $JSONContent | Where-Object {$_.Version -like "3.*"} | Select-Object -First 1
$OutputAppRootPath = "D:\SourceRepo\Applications\2PintSoftware\StifleRClientIntuneWin"
$PackageVariants = @('2PintDemo', '2PintLabs')
$IntuneUtilFolderPath = "$IntuneAppRootPath\Microsoft-Win32-Content-Prep-Tool"
$IntuneUtilPath = "$IntuneUtilFolderPath\IntuneWinAppUtil.exe"
$IntuneUtilURL = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
#https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/blob/master/IntuneWinAppUtil.exe




#Test Folder Structure and Build if needed
if (!(Test-Path -Path $SourceAppPathRoot)){
    New-item -Path $SourceAppPathRoot -ItemType Directory -Force | Out-Null
    Write-Host "Created $SourceAppPathRoot" -ForegroundColor Green
    Write-Host "Place your SOURCE HERE!!!" -ForegroundColor Red
}
else {
    Write-Host "Using Source: $SourceAppPathRoot" -ForegroundColor Green
}

if (!(Test-Path -Path $IntuneUtilFolderPath)){
    New-item -Path $IntuneUtilFolderPath -ItemType Directory -Force | Out-Null
    Write-Host "Created $IntuneUtilFolderPath" -ForegroundColor Green
}
else {
    Write-Host "Using IntuneUtilFolder: $IntuneUtilFolderPath" -ForegroundColor Green
}
if (!(Test-Path -Path $IntuneUtilPath)){
    Invoke-WebRequest -UseBasicParsing -Uri $IntuneUtilURL -OutFile $IntuneUtilPath
    Write-Host "Downloaded IntuneWinAppUtil.exe to $IntuneUtilPath" -ForegroundColor Green
}
else{
    Write-Host "Using IntuneWinAppUtil: $IntuneUtilPath" -ForegroundColor Green
}

# Read both MSI properties and reject stale source content before packaging.
$MsiFiles = @(Get-ChildItem -LiteralPath $SourceAppPath -Filter *.msi -File -ErrorAction Stop)
if ($MsiFiles.Count -ne 1) {
    throw "Expected exactly one MSI in '$SourceAppPath', found $($MsiFiles.Count)."
}
$MSI = $MsiFiles[0]
$WindowsInstaller = $null
$Database = $null
$View = $null
$Record = $null
$ProductCode = $null
$MsiVersion = $null
try {
    $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
    $Database = $WindowsInstaller.OpenDatabase($MSI.FullName, 0)
    $View = $Database.OpenView("SELECT Property, Value FROM Property WHERE Property = 'ProductCode' OR Property = 'ProductVersion'")
    $View.Execute()
    while ($null -ne ($Record = $View.Fetch())) {
        try {
            switch ($Record.StringData(1)) {
                'ProductCode' { $ProductCode = $Record.StringData(2) }
                'ProductVersion' { $MsiVersion = $Record.StringData(2) }
            }
        }
        finally {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Record)
            $Record = $null
        }
    }
    $View.Close()
}
finally {
    foreach ($ComObject in @($Record, $View, $Database, $WindowsInstaller)) {
        if ($null -ne $ComObject) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ComObject)
        }
    }
}
if ([string]::IsNullOrWhiteSpace($ProductCode)) {
    throw "ProductCode not found in '$($MSI.FullName)'."
}
if ([string]::IsNullOrWhiteSpace($MsiVersion)) {
    throw "ProductVersion not found in '$($MSI.FullName)'."
}
if ([string]::IsNullOrWhiteSpace($StifleR30.Version)) {
    throw 'StifleR 3.x version not found in the client JSON.'
}
Write-Output "Product Code: $ProductCode"
Write-Output "MSI Version: $MsiVersion"
Write-Output "JSON Version: $($StifleR30.Version)"
if ([version]$MsiVersion -ne [version]$StifleR30.Version) {
    throw "MSI version '$MsiVersion' does not match JSON version '$($StifleR30.Version)'. Update the source MSI before creating the Intune package."
}
Write-Host 'MSI version matches JSON version.' -ForegroundColor Green

# Validate both configurations before creating either package.
foreach ($Variant in $PackageVariants) {
    $SettingsPath = Join-Path -Path $OutputAppRootPath -ChildPath "Configs-$Variant\settings.2psImport"
    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
        throw "Settings file for $Variant not found: $SettingsPath"
    }
}

$CreatedPackages = @()
$RunStagingPath = Join-Path -Path $StagingTempPath -ChildPath ([guid]::NewGuid().ToString())
try {
    foreach ($Variant in $PackageVariants) {
        $SettingsPath = Join-Path -Path $OutputAppRootPath -ChildPath "Configs-$Variant\settings.2psImport"
        $SetupFolder = Join-Path -Path $RunStagingPath -ChildPath "$Variant\Source"
        $BuildOutputPath = Join-Path -Path $RunStagingPath -ChildPath "$Variant\Output"
        $OutputAppPath = Join-Path -Path $OutputAppRootPath -ChildPath "$Variant\$MsiVersion"
        New-Item -Path $SetupFolder, $BuildOutputPath, $OutputAppPath -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $MSI.FullName -Destination $SetupFolder
        Copy-Item -LiteralPath $SettingsPath -Destination (Join-Path $SetupFolder 'settings.2psImport')

        # Distinct setup names also give the resulting packages distinct filenames.
        $SetupFileName = "Install-$Variant.cmd"
        $SetupPath = Join-Path -Path $SetupFolder -ChildPath $SetupFileName
        $InstallCommand = @"
@echo off
msiexec /i "%~dp0$($MSI.Name)" AUTOSTART=1 OPTIONS="%~dp0settings.2psImport" /quiet /l*v "C:\Windows\Temp\StifleRClientInstall.log"
exit /b %errorlevel%
"@
        Set-Content -LiteralPath $SetupPath -Value $InstallCommand -Encoding ASCII

        Write-Host "Creating $Variant Intune package for MSI version $MsiVersion..." -ForegroundColor Green
        & $IntuneUtilPath -c $SetupFolder -s $SetupPath -o $BuildOutputPath -q
        if ($LASTEXITCODE -ne 0) {
            throw "IntuneWinAppUtil failed for $Variant with exit code $LASTEXITCODE."
        }
        $PackagePath = Join-Path -Path $BuildOutputPath -ChildPath "Install-$Variant.intunewin"
        if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf) -or (Get-Item -LiteralPath $PackagePath).Length -eq 0) {
            throw "IntuneWinAppUtil did not create a nonempty package for $Variant."
        }
        Move-Item -LiteralPath $PackagePath -Destination $OutputAppPath -Force
        $CreatedPackages += [pscustomobject]@{
            Variant = $Variant
            FileName = "Install-$Variant.intunewin"
            Folder = $OutputAppPath
        }
        Write-Host "Finished $Variant package: $OutputAppPath\Install-$Variant.intunewin" -ForegroundColor Green
    }
}
finally {
    if (Test-Path -LiteralPath $RunStagingPath -PathType Container) {
        Remove-Item -LiteralPath $RunStagingPath -Recurse -Force
    }
}

Write-Output ''
Write-Output 'Intune package creation summary'
foreach ($Package in $CreatedPackages) {
    Write-Output "$($Package.Variant): $($Package.FileName)"
    Write-Output "  Folder: $($Package.Folder)"
}
Write-Output "MSI Version: $MsiVersion"
Write-Output "MSI Product Code: $ProductCode"