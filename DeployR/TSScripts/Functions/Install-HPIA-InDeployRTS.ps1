<#
Notes:
- This wrapper writes an inner payload script to C:\Windows\Temp, then launches it with pwsh.exe.
- The payload contains the full HP Support Assistant install flow (HPCMSL check/install/import, SoftPaq lookup, fallback, install).
- The wrapper waits for completion and exits with the payload process exit code.
#>

$ErrorActionPreference = "Stop"

$payloadScriptBlock = {
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
	if ($null -eq $installHpsaExe.Directory) {
		throw "Unable to resolve the InstallHPSA.exe directory."
	}

	$installWorkingDirectory = $installHpsaExe.Directory.FullName
	$hpsa9xPath = Join-Path -Path $installWorkingDirectory -ChildPath "HPSA9x"

	Write-Host "Install working directory: $installWorkingDirectory"
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
}

$payloadPath = Join-Path -Path $env:windir -ChildPath "Temp\Install-HPSA-Payload.ps1"
Write-Host "Writing payload script to: $payloadPath"
$payloadScriptBlock.ToString() | Set-Content -Path $payloadPath -Encoding UTF8 -Force

$pwshExe = "pwsh.exe"
$pwshArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $payloadPath)
$pwshCommandLine = "$pwshExe $($pwshArgs -join ' ')"

Write-Host "Launching payload with command line:"
Write-Host $pwshCommandLine

$payloadProcess = Start-Process -FilePath $pwshExe -ArgumentList $pwshArgs -PassThru -Wait
Write-Host "Payload pwsh.exe finished with exit code: $($payloadProcess.ExitCode)"

exit $payloadProcess.ExitCode



