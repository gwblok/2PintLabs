if ($env:SystemDrive -eq "X:"){
    Write-Host "Running in WinPE, this step requires a full Windows environment to run properly."
    exit 0
}

Import-Module DeployR.Utility

[String]$ContentItem = ${TSEnv:_CONTENT-CONTENT}
[String]$BrandedContentItem = ${TSEnv:_CONTENT-BRANDINGStartLayoutCI}



Write-Host "===================================================================="
Write-Host "Setting Start menu layout for Windows 11..."
if (([System.Environment]::OSVersion.Version).Build -lt 22000) {
	Write-Host "This script is intended for Windows 11 only. Exiting..."
	exit 0
}

if ($BrandedContentItem -ne "") {
	Write-Host "Using branded content item: $BrandedContentItem"
	$ContentLocation = $BrandedContentItem
} else {
	Write-Host "Using default content item: $ContentItem"
	$ContentLocation = "$ContentItem\Win11StartLayout"
}

if (-not (Test-Path "$ContentLocation\Start2.bin")) {
	Write-Host "Start2.bin location does not exist: $ContentLocation. Exiting..."
	exit 0
}
if (-not (Test-Path "$ContentLocation\settings.dat")) {
	Write-Host "settings.dat location does not exist: $ContentLocation. Exiting..."
	exit 0
}
Write-Host "Copying Start menu layout: $ContentLocation\Start2.bin"
New-Item -ItemType Directory -Path "C:\Users\Default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState" -Force -ErrorAction SilentlyContinue | Out-Null
Copy-Item "$ContentLocation\Start2.bin" "C:\Users\Default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\Start2.bin" -Force
Write-Host "Copying Start menu settings: $ContentLocation\settings.dat"
New-Item -ItemType Directory -Path "C:\Users\Default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\Settings" -Force -ErrorAction SilentlyContinue | Out-Null
Copy-Item "$ContentLocation\settings.dat" "C:\Users\Default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\Settings\settings.dat" -Force

Write-Host "Completed setting Start menu layout for Windows 11."
Write-Host "===================================================================="