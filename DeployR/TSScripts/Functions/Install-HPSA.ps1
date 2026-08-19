<#
Notes:
- This script installs HP Support Assistant by using HP CMSL to locate and install the latest HPSA SoftPaq.
- The script first guarantees HPCMSL is available for all users, then imports it for this session.
- It queries Get-SoftpaqList for "HP Support Assistant" and uses the first matching SoftPaq id.
- If no catalog match is returned, it falls back to $SoftPackFallBackNumber.
- After Get-Softpaq silent install, it finds InstallHPSA.exe in C:\SWSetup and runs it with /s.
- The installer depends on a relative HPSA9x payload folder, so WorkingDirectory is set to the extracted SoftPaq folder.
- Non-zero exit from InstallHPSA.exe is treated as failure and throws.

About #sym:$SoftPackFallBackNumber:
- #sym:$SoftPackFallBackNumber is an editor/copilot symbol reference label (metadata), not PowerShell syntax.
- It indicates the selected symbol in the editor context so chat can refer to that variable.
- In this script, the real variable is $SoftPackFallBackNumber and it is used when catalog lookup does not find HPSA.
#>

# Fallback SoftPaq id used only if catalog search does not return HP Support Assistant.
$SoftPackFallBackNumber = "173774"
$ErrorActionPreference = "Stop"

Write-Host "============================================================"
Write-Host "Starting HP Support Assistant install workflow"
Write-Host "============================================================"

$allUsersModulePaths = @(
	Join-Path -Path $env:ProgramFiles -ChildPath "WindowsPowerShell\Modules\HPCMSL"
	Join-Path -Path $env:ProgramFiles -ChildPath "PowerShell\Modules\HPCMSL"
)

$isInstalledAllUsers = $false
foreach ($modulePath in $allUsersModulePaths) {
	if (Test-Path -Path $modulePath) {
		$isInstalledAllUsers = $true
		Write-Host "HPCMSL found in all-users path: $modulePath"
		break
	}
}

if (-not $isInstalledAllUsers) {
	Write-Host "HPCMSL is not installed for all users. Installing now..."
	Install-Module -Name "HPCMSL" -Scope AllUsers -AcceptLicense -Force
	Write-Host "HPCMSL install complete."
}
else {
	Write-Host "HPCMSL is already installed for all users."
}

Write-Host "Importing HPCMSL module..."
Import-Module -Name "HPCMSL" -Force
Write-Host "HPCMSL import complete."

Write-Host "Searching SoftPaq catalog for HP Support Assistant..."
# Query HP CMSL catalog and keep only the first HPSA match.
$hpsaSoftPaq = Get-SoftpaqList | Where-Object { $_.Name -match "HP Support Assistant" } | Select-Object -First 1

if ($null -ne $hpsaSoftPaq -and $null -ne $hpsaSoftPaq.id) {
	$HPSANumber = [string]$hpsaSoftPaq.id
	Write-Host "Found HP Support Assistant SoftPaq ID: $HPSANumber"
}
else {
	# No online match found; use known-good fallback SoftPaq id.
	$HPSANumber = $SoftPackFallBackNumber
	Write-Host "HP Support Assistant not found in catalog. Using fallback SoftPaq ID: $HPSANumber"
}

Write-Host "Running get-softpaq -Number $HPSANumber -Action silentinstall"
Get-Softpaq -Number $HPSANumber -Action SilentInstall
Write-Host "SoftPaq silent install command complete."

Write-Host "Searching C:\SWSetup for InstallHPSA.exe..."
# Pick the newest extracted installer in case multiple SoftPaq folders exist.
$installHpsaExe = Get-ChildItem -Path "C:\SWSetup" -Filter "InstallHPSA.exe" -Recurse -ErrorAction SilentlyContinue |
	Sort-Object -Property LastWriteTime -Descending |
	Select-Object -First 1

if ($null -eq $installHpsaExe) {
	throw "InstallHPSA.exe was not found under C:\SWSetup after SoftPaq install."
}

Write-Host "Found InstallHPSA.exe: $($installHpsaExe.FullName)"
if ($null -eq $installHpsaExe.Directory) {
	throw "Unable to resolve the InstallHPSA.exe directory."
}

$installWorkingDirectory = $installHpsaExe.Directory.FullName
$hpsa9xPath = Join-Path -Path $installWorkingDirectory -ChildPath "HPSA9x"

Write-Host "Install working directory: $installWorkingDirectory"
# HPSA installer expects this relative payload folder to exist under working directory.
if (-not (Test-Path -Path $hpsa9xPath)) {
	throw "Expected HPSA payload folder not found: $hpsa9xPath"
}
Write-Host "Verified HPSA payload folder: $hpsa9xPath"

Write-Host "Launching InstallHPSA.exe with /s..."
$installProcess = Start-Process -FilePath $installHpsaExe.FullName -ArgumentList "/s" -WorkingDirectory $installWorkingDirectory -PassThru -Wait
Write-Host "InstallHPSA.exe finished with exit code: $($installProcess.ExitCode)"

if ($installProcess.ExitCode -ne 0) {
	throw "InstallHPSA.exe failed with exit code $($installProcess.ExitCode)."
}

Write-Host "============================================================"
Write-Host "HP Support Assistant install workflow completed successfully"
Write-Host "============================================================"



