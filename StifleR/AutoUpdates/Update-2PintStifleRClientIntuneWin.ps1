<#
.SYNOPSIS
Builds the StifleR Client Intune package after validating the MSI version.

.DESCRIPTION
Reads the StifleR 3.x version from the published client JSON and requires exactly one
local MSI whose ProductVersion matches it before invoking IntuneWinAppUtil.
Requires Windows, Windows Installer COM, internet access to the JSON and (if missing)
the packaging utility, and write access to the configured source and output folders.
Creates missing folders, downloads the packaging utility if needed, and writes the Intune package.
Packages are written beneath the output folder in a subfolder named for the validated MSI
ProductVersion (for example, StifleRClientIntuneWin\3.1.2645.1019).

.EXAMPLE
.\Update-2PintStifleRClientIntuneWin.ps1
Validates the local MSI against the published JSON version and builds the Intune package.

.NOTES
Author: Gary Blok
Created: Not specified
Change History:
    2026-11-10 - Capture MSI ProductVersion and block packaging when it differs from JSON.
    2026-11-10 - Write each Intune package to its MSI version subfolder.
#>



#Build App Intune Installer
$IntuneAppRootPath = "D:\SourceRepo\IntuneWin\AppUtil"

#Path to App Folder you want to Convert
$SourceAppPathRoot = "D:\SourceRepo\Applications\2PintSoftware"
$SourceAppPath = "$SourceAppPathRoot\StifleRClient"


$JSONContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/GARYTOWN/StifleR-ClientApp.json"
$settingsConfigURL = 'https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/GARYTOWN/30/dr2pintlabs.2psImport'
$CMD = @"
msiexec /i StifleR-ClientApp-x64.msi AUTOSTART=1 OPTIONS="settings.2psImport" /quiet /l*v "C:\Windows\Temp\StifleRClientInstall.log"
"@
$StifleR30 = $JSONContent | Where-Object {$_.Version -like "3.*"} | Select-Object -First 1
$StifleR30URL = $StifleR30.URL
$OutputAppRootPath = "D:\SourceRepo\Applications\2PintSoftware\StifleRClientIntuneWin"
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

<#Do Stuff
Write-Host "Downloading StifleR 3.0 from $StifleR30URL" -ForegroundColor Green
Invoke-WebRequest -Uri $StifleR30URL -OutFile "$SourceAppPathRoot\StifleR-ClientApp.zip"
#Download settings.2psImport
Invoke-WebRequest -Uri $settingsConfigURL -OutFile "$SourceAppPathRoot\settings.2psImport"
#Create the CMD file for install
$CMDPath = "$SourceAppPath\Install.cmd"
$CMD | Out-File -FilePath $CMDPath -Encoding ASCII
#Extract ZIP
Expand-Archive -Path "$SourceAppPathRoot\StifleR-ClientApp.zip" -DestinationPath $SourceAppPath -Force
#>

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

# Keep packages for different MSI versions in separate output folders.
$OutputAppPath = Join-Path -Path $OutputAppRootPath -ChildPath $MsiVersion
if (-not (Test-Path -LiteralPath $OutputAppPath -PathType Container)) {
    New-Item -Path $OutputAppPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Write-Host "Created $OutputAppPath" -ForegroundColor Green
}
else {
    Write-Host "Using Output: $OutputAppPath" -ForegroundColor Green
}

$App = get-item -Path $SourceAppPath
$SetupCMD = Get-ChildItem -Path $App.FullName -Filter *.cmd
if (!($SetupCMD)){
    $SetupEXE = Get-ChildItem -Path $App.FullName -Filter *.exe
    if (!($SetupEXE)){$SetupEXE = Get-ChildItem -Path $App.FullName -Filter *.msi}
}
else {
    $SetupEXE = $SetupCMD
}
$SetupFolder = $App.FullName
#$CreateIntuneApp = Start-Process -FilePath $IntuneUtilPath -ArgumentList "-c $SetupFolder -s $SetupEXEPath -o $OutPutPath -q" -Wait -PassThru
Write-Host "Starting Intune Package Creation" -ForegroundColor Green
write-Host "& $IntuneUtilPath -c $SetupFolder -s $($SetupEXE.FullName) -o $OutputAppPath -q"
& $IntuneUtilPath -c $SetupFolder -s $SetupEXE.FullName -o $OutputAppPath -q

Write-Host "Finished App for Intune: $OutputAppPath" -ForegroundColor Green
if ($MSI){Write-Output "Product Code: $ProductCode"}