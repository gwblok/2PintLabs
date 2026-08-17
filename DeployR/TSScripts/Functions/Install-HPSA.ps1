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
$hpsaSoftPaq = Get-SoftpaqList | Where-Object { $_.Name -match "HP Support Assistant" } | Select-Object -First 1

if ($null -ne $hpsaSoftPaq -and $null -ne $hpsaSoftPaq.id) {
	$HPSANumber = [string]$hpsaSoftPaq.id
	Write-Host "Found HP Support Assistant SoftPaq ID: $HPSANumber"
}
else {
	$HPSANumber = $SoftPackFallBackNumber
	Write-Host "HP Support Assistant not found in catalog. Using fallback SoftPaq ID: $HPSANumber"
}

Write-Host "Running get-softpaq -Number $HPSANumber -Action silentinstall"
Get-Softpaq -Number $HPSANumber -Action SilentInstall
Write-Host "SoftPaq silent install command complete."

Write-Host "Searching C:\SWSetup for InstallHPSA.exe..."
$installHpsaExe = Get-ChildItem -Path "C:\SWSetup" -Filter "InstallHPSA.exe" -Recurse -ErrorAction SilentlyContinue |
	Sort-Object -Property LastWriteTime -Descending |
	Select-Object -First 1

if ($null -eq $installHpsaExe) {
	throw "InstallHPSA.exe was not found under C:\SWSetup after SoftPaq install."
}

Write-Host "Found InstallHPSA.exe: $($installHpsaExe.FullName)"
Write-Host "Launching InstallHPSA.exe with /s..."
$installProcess = Start-Process -FilePath $installHpsaExe.FullName -ArgumentList "/s" -PassThru -Wait
Write-Host "InstallHPSA.exe finished with exit code: $($installProcess.ExitCode)"

if ($installProcess.ExitCode -ne 0) {
	throw "InstallHPSA.exe failed with exit code $($installProcess.ExitCode)."
}

Write-Host "============================================================"
Write-Host "HP Support Assistant install workflow completed successfully"
Write-Host "============================================================"



