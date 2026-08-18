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

	Write-Host "Preparing DISM APPX provisioning from extracted HPSA payload..."
	$hpsaAppxBundle = Get-ChildItem -Path $hpsa9xPath -Filter "*.appxbundle" -File -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($null -eq $hpsaAppxBundle) {
		throw "No .appxbundle file was found in $hpsa9xPath"
	}

	Write-Host "Found HPSA APPX bundle: $($hpsaAppxBundle.FullName)"
	$dependencyPackages = Get-ChildItem -Path (Join-Path -Path $hpsa9xPath -ChildPath "Dependencies") -Filter "*.appx" -Recurse -File -ErrorAction SilentlyContinue |
		Sort-Object -Property FullName

	$dismArgs = @(
		"/Online"
		"/Add-ProvisionedAppxPackage"
		"/PackagePath:$($hpsaAppxBundle.FullName)"
		"/SkipLicense"
	)

	if ($null -ne $dependencyPackages -and $dependencyPackages.Count -gt 0) {
		Write-Host "Including dependency packages for DISM provisioning:"
		foreach ($dependencyPackage in $dependencyPackages) {
			Write-Host " - $($dependencyPackage.FullName)"
			$dismArgs += "/DependencyPackagePath:$($dependencyPackage.FullName)"
		}
	}
	else {
		Write-Host "No dependency .appx files were found under $hpsa9xPath\Dependencies"
	}

	Write-Host "Running DISM to provision HPSA APPX for all users..."
	$dismProcess = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -PassThru -Wait -NoNewWindow
	Write-Host "DISM finished with exit code: $($dismProcess.ExitCode)"

	if ($dismProcess.ExitCode -ne 0) {
		throw "DISM APPX provisioning failed with exit code $($dismProcess.ExitCode)."
	}

	Write-Host "DISM APPX provisioning completed successfully."

	Write-Host "Creating per-user HPSA AppX registration script for first logon..."
	$hpsaUserScriptDir = "C:\ProgramData\2Pint\Scripts"
	$hpsaUserScriptPath = Join-Path -Path $hpsaUserScriptDir -ChildPath "Register-HPSA-Appx-PerUser.ps1"
	New-Item -Path $hpsaUserScriptDir -ItemType Directory -Force | Out-Null

	$hpsaUserScript = @"

	`$ErrorActionPreference = "Stop"
	`$hpsaRoot = "C:\SWSetup\sp173774\HPSA9x"
	`$bundle = Get-ChildItem -Path `$hpsaRoot -Filter "*.appxbundle" -File -ErrorAction SilentlyContinue | Select-Object -First 1

	if (`$null -eq `$bundle) {
		Write-Output "HPSA per-user register: appxbundle not found at `$hpsaRoot"
		exit 1
	}

	`$packageName = [System.IO.Path]::GetFileNameWithoutExtension(`$bundle.Name)
	`$existing = Get-AppxPackage -Name `$packageName -ErrorAction SilentlyContinue
	if (`$null -ne `$existing) {
		Write-Output "HPSA per-user register: package already present for user."
		exit 0
	}

	`$arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
	`$dependencyPath = Join-Path -Path `$hpsaRoot -ChildPath "Dependencies\`$arch"
	`$dependencyPackages = @()
	if (Test-Path -Path `$dependencyPath) {
		`$dependencyPackages = Get-ChildItem -Path `$dependencyPath -Filter "*.appx" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
	}

	if (`$dependencyPackages.Count -gt 0) {
		Add-AppxPackage -Path `$bundle.FullName -DependencyPath `$dependencyPackages -ForceUpdateFromAnyVersion -ErrorAction Stop
	}
	else {
		Add-AppxPackage -Path `$bundle.FullName -ForceUpdateFromAnyVersion -ErrorAction Stop
	}

	Write-Output "HPSA per-user register: package installed for current user."
	exit 0

"@

	Set-Content -Path $hpsaUserScriptPath -Value $hpsaUserScript -Encoding UTF8 -Force
	Write-Host "Per-user script written to: $hpsaUserScriptPath"

	Write-Host "Registering Active Setup for per-user HPSA AppX registration..."
	$activeSetupKeyPath = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\2Pint.RegisterHPSAAppx"
	New-Item -Path $activeSetupKeyPath -Force | Out-Null
	Set-ItemProperty -Path $activeSetupKeyPath -Name "(Default)" -Value "Register HP Support Assistant AppX per user" -Type String
	Set-ItemProperty -Path $activeSetupKeyPath -Name "Version" -Value "1,0,0,0" -Type String
	Set-ItemProperty -Path $activeSetupKeyPath -Name "IsInstalled" -Value 1 -Type DWord
	Set-ItemProperty -Path $activeSetupKeyPath -Name "StubPath" -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$hpsaUserScriptPath`"" -Type String
	Write-Host "Active Setup registration complete."

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



