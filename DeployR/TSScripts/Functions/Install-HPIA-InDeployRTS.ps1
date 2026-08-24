<#
Notes:
- This wrapper writes an inner payload script to C:\Windows\Temp, then launches it with pwsh.exe.
- The payload contains the full HP Support Assistant install flow (HPCMSL check/install/import, SoftPaq lookup, fallback, install).
- The wrapper waits for completion and exits with the payload process exit code.
#>

$ErrorActionPreference = "Stop"

$payloadScriptBlock = {
	param(
		[string]$LogDirectory
	)

	# Fallback SoftPaq id used only if catalog search does not return HP Support Assistant.
	$SoftPackFallBackNumber = "173774"
	$ErrorActionPreference = "Stop"

	function Resolve-DeployRLogDirectory {
		param(
			[string]$OverridePath
		)

		if (-not [string]::IsNullOrWhiteSpace($OverridePath)) {
			return $OverridePath
		}

		$moduleImported = $false
		try {
			Import-Module DeployR.Utility -ErrorAction SilentlyContinue
			if (Get-Module -Name DeployR.Utility) {
				$moduleImported = $true
			}
		}
		catch {
			# Ignore import failures and continue with fallback.
		}

		if ($moduleImported) {
			try {
				$tsLogPath = ${TSEnv:_DEPLOYRLOGS}
				if (-not [string]::IsNullOrWhiteSpace($tsLogPath)) {
					return $tsLogPath
				}
			}
			catch {
				# DeployR TS variable provider not available in this context.
			}
		}

		return (Join-Path -Path $env:windir -ChildPath "Temp\DeployR")
	}

	$transcriptDirectory = Resolve-DeployRLogDirectory -OverridePath $LogDirectory
	$transcriptTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
	$transcriptPath = Join-Path -Path $transcriptDirectory -ChildPath "InstallHPSA-$transcriptTimestamp.txt"
	$transcriptStarted = $false
	$currentStep = "Initializing"
	$dismStdOutPath = Join-Path -Path $transcriptDirectory -ChildPath "InstallHPSA-DISM-$transcriptTimestamp.stdout.log"
	$dismStdErrPath = Join-Path -Path $transcriptDirectory -ChildPath "InstallHPSA-DISM-$transcriptTimestamp.stderr.log"
	$installStdOutPath = Join-Path -Path $transcriptDirectory -ChildPath "InstallHPSA-Setup-$transcriptTimestamp.stdout.log"
	$installStdErrPath = Join-Path -Path $transcriptDirectory -ChildPath "InstallHPSA-Setup-$transcriptTimestamp.stderr.log"
	$failureSummaryPath = Join-Path -Path $transcriptDirectory -ChildPath "InstallHPSA-Failure-$transcriptTimestamp.log"
	$installHpsaExe = $null
	$installWorkingDirectory = $null
	$hpsa9xPath = $null

	function Set-CurrentStep {
		param(
			[Parameter(Mandatory = $true)]
			[string]$StepName
		)

		$currentStep = $StepName
		Write-Host "STEP: $currentStep"
	}

	function Write-DiagnosticError {
		param(
			[Parameter(Mandatory = $true)]
			[System.Management.Automation.ErrorRecord]$ErrorRecord
		)

		Write-Host "ERROR: HP Support Assistant install workflow failed."
		Write-Host "CurrentStep: $currentStep"
		Write-Host "Message: $($ErrorRecord.Exception.Message)"
		Write-Host "Category: $($ErrorRecord.CategoryInfo)"
		Write-Host "FullyQualifiedErrorId: $($ErrorRecord.FullyQualifiedErrorId)"
		Write-Host "ScriptStackTrace: $($ErrorRecord.ScriptStackTrace)"

		if ($null -ne $ErrorRecord.InvocationInfo) {
			Write-Host "Command: $($ErrorRecord.InvocationInfo.MyCommand)"
			Write-Host "Line: $($ErrorRecord.InvocationInfo.ScriptLineNumber)"
			Write-Host "Position: $($ErrorRecord.InvocationInfo.OffsetInLine)"
			Write-Host "LineText: $($ErrorRecord.InvocationInfo.Line.Trim())"
		}

		if ($null -ne $ErrorRecord.Exception.InnerException) {
			Write-Host "InnerException: $($ErrorRecord.Exception.InnerException.Message)"
		}
	}

	function Write-FailureSummary {
		param(
			[Parameter(Mandatory = $true)]
			[System.Management.Automation.ErrorRecord]$ErrorRecord
		)

		$summaryLines = @(
			"Timestamp: $(Get-Date -Format o)"
			"CurrentStep: $currentStep"
			"TranscriptPath: $transcriptPath"
			"FailureSummaryPath: $failureSummaryPath"
			"PayloadStdOutPath: $installStdOutPath"
			"PayloadStdErrPath: $installStdErrPath"
			"DismStdOutPath: $dismStdOutPath"
			"DismStdErrPath: $dismStdErrPath"
			"InstallExePath: $($installHpsaExe.FullName)"
			"InstallWorkingDirectory: $installWorkingDirectory"
			"HpsaPayloadPath: $hpsa9xPath"
			"ExceptionMessage: $($ErrorRecord.Exception.Message)"
			"CategoryInfo: $($ErrorRecord.CategoryInfo)"
			"FullyQualifiedErrorId: $($ErrorRecord.FullyQualifiedErrorId)"
			"ScriptStackTrace: $($ErrorRecord.ScriptStackTrace)"
		)

		if ($null -ne $ErrorRecord.InvocationInfo) {
			$summaryLines += "Command: $($ErrorRecord.InvocationInfo.MyCommand)"
			$summaryLines += "ScriptLineNumber: $($ErrorRecord.InvocationInfo.ScriptLineNumber)"
			$summaryLines += "OffsetInLine: $($ErrorRecord.InvocationInfo.OffsetInLine)"
			$summaryLines += "LineText: $($ErrorRecord.InvocationInfo.Line.Trim())"
		}

		if ($null -ne $ErrorRecord.Exception.InnerException) {
			$summaryLines += "InnerException: $($ErrorRecord.Exception.InnerException.Message)"
		}

		Set-Content -Path $failureSummaryPath -Value $summaryLines -Encoding UTF8 -Force
		Write-Host "Failure summary: $failureSummaryPath"
	}

	function Write-SWSetupDiagnostics {
		if (-not (Test-Path -Path "C:\SWSetup")) {
			Write-Host "Diagnostics: C:\SWSetup does not exist."
			return
		}

		Write-Host "Diagnostics: Recent InstallHPSA.exe matches under C:\SWSetup"
		$recentInstallers = Get-ChildItem -Path "C:\SWSetup" -Filter "InstallHPSA.exe" -Recurse -ErrorAction SilentlyContinue |
			Sort-Object -Property LastWriteTime -Descending |
			Select-Object -First 5 -Property FullName, LastWriteTime

		if ($recentInstallers) {
			$recentInstallers | Format-Table -AutoSize | Out-String | Write-Host
		}
		else {
			Write-Host "Diagnostics: No InstallHPSA.exe files were found under C:\SWSetup."
		}
	}

	New-Item -Path $transcriptDirectory -ItemType Directory -Force | Out-Null
	try {
		Start-Transcript -Path $transcriptPath -Force | Out-Null
		$transcriptStarted = $true
	}
	catch {
		Write-Warning "Unable to start transcript at $transcriptPath. $($_.Exception.Message)"
	}

	try {
		if ($transcriptStarted) {
			Write-Host "Transcript started: $transcriptPath"
		}
		else {
			Write-Host "Transcript unavailable. Continuing with console logging only."
		}
		Write-Host "============================================================"
		Write-Host "Starting HP Support Assistant install workflow"
		Write-Host "============================================================"
		Write-Host "PowerShell version: $($PSVersionTable.PSVersion)"
		Write-Host "Running as user: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
		try {
			$deployRTSName = ${TSEnv:DEPLOYRTASKSEQUENCENAME}
			if (-not [string]::IsNullOrWhiteSpace($deployRTSName)) {
				Write-Host "Running in DeployR TS: $deployRTSName"
			}
		}
		catch {
			# Not running with DeployR TS variable provider.
		}
		Write-Host "Transcript/log directory: $transcriptDirectory"

		Set-CurrentStep -StepName "Checking HPCMSL module"
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
			Set-CurrentStep -StepName "Installing HPCMSL module"
			Write-Host "HPCMSL is not installed for all users. Installing now..."
			Install-Module -Name "HPCMSL" -Scope AllUsers -AcceptLicense -Force
			Write-Host "HPCMSL install complete."
		}
		else {
			Write-Host "HPCMSL is already installed for all users."
		}

		Set-CurrentStep -StepName "Importing HPCMSL module"
		Write-Host "Importing HPCMSL module..."
		Import-Module -Name "HPCMSL" -Force
		Write-Host "HPCMSL import complete."

		Set-CurrentStep -StepName "Searching SoftPaq catalog"
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

		Set-CurrentStep -StepName "Downloading and installing SoftPaq $HPSANumber"
		Write-Host "Running get-softpaq -Number $HPSANumber -Action silentinstall"
		Get-Softpaq -Number $HPSANumber -Action SilentInstall -ErrorAction Stop
		Write-Host "SoftPaq silent install command complete."

		Set-CurrentStep -StepName "Locating InstallHPSA.exe"
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

		Set-CurrentStep -StepName "Validating extracted HPSA payload"
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

		Set-CurrentStep -StepName "Provisioning HPSA AppX with DISM"
		Write-Host "Running DISM to provision HPSA APPX for all users..."
		Write-Host "DISM stdout log: $dismStdOutPath"
		Write-Host "DISM stderr log: $dismStdErrPath"
		$dismProcess = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -PassThru -Wait -RedirectStandardOutput $dismStdOutPath -RedirectStandardError $dismStdErrPath
		Write-Host "DISM finished with exit code: $($dismProcess.ExitCode)"
		Write-Host "DISM servicing log: C:\Windows\Logs\DISM\dism.log"
		Write-Host "CBS servicing log: C:\Windows\Logs\CBS\CBS.log"

		if ($dismProcess.ExitCode -ne 0) {
			throw "DISM APPX provisioning failed with exit code $($dismProcess.ExitCode)."
		}

		Write-Host "DISM APPX provisioning completed successfully."

		Set-CurrentStep -StepName "Creating per-user HPSA registration"
		Write-Host "Creating per-user HPSA AppX registration script for first logon..."
		$hpsaUserScriptDir = "C:\ProgramData\2Pint\Scripts"
		$hpsaUserScriptPath = Join-Path -Path $hpsaUserScriptDir -ChildPath "Register-HPSA-Appx-PerUser.ps1"
		New-Item -Path $hpsaUserScriptDir -ItemType Directory -Force | Out-Null

		$hpsaUserScript = @"

	`$ErrorActionPreference = "Stop"
	`$hpsaRoot = "$hpsa9xPath"
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

		Set-CurrentStep -StepName "Running InstallHPSA.exe"
		Write-Host "Launching InstallHPSA.exe with /s..."
		Write-Host "InstallHPSA.exe stdout log: $installStdOutPath"
		Write-Host "InstallHPSA.exe stderr log: $installStdErrPath"
		$installProcess = Start-Process -FilePath $installHpsaExe.FullName -ArgumentList "/s" -WorkingDirectory $installWorkingDirectory -PassThru -Wait -RedirectStandardOutput $installStdOutPath -RedirectStandardError $installStdErrPath
		Write-Host "InstallHPSA.exe finished with exit code: $($installProcess.ExitCode)"

		if ($installProcess.ExitCode -ne 0) {
			throw "InstallHPSA.exe failed with exit code $($installProcess.ExitCode)."
		}

		Write-Host "============================================================"
		Write-Host "HP Support Assistant install workflow completed successfully"
		Write-Host "============================================================"
	}
	catch {
		Write-DiagnosticError -ErrorRecord $_
		Write-FailureSummary -ErrorRecord $_
		Write-Host "Diagnostic logs:"
		Write-Host " - Failure summary: $failureSummaryPath"
		Write-Host " - DISM stdout: $dismStdOutPath"
		Write-Host " - DISM stderr: $dismStdErrPath"
		Write-Host " - Setup stdout: $installStdOutPath"
		Write-Host " - Setup stderr: $installStdErrPath"
		Write-SWSetupDiagnostics
		throw
	}
	finally {
		if ($transcriptStarted) {
			Stop-Transcript | Out-Null
		}
	}
}

function Resolve-DeployRLogDirectory {
	$moduleImported = $false
	try {
		Import-Module DeployR.Utility -ErrorAction SilentlyContinue
		if (Get-Module -Name DeployR.Utility) {
			$moduleImported = $true
		}
	}
	catch {
		# Ignore import failures and continue with fallback.
	}

	if ($moduleImported) {
		try {
			$tsName = ${TSEnv:DEPLOYRTASKSEQUENCENAME}
			$tsLogPath = ${TSEnv:_DEPLOYRLOGS}

			if (-not [string]::IsNullOrWhiteSpace($tsName)) {
				Write-Host "Running in DeployR TS: $tsName"
			}

			if (-not [string]::IsNullOrWhiteSpace($tsLogPath)) {
				Write-Host "Using DeployR TS log folder from _DEPLOYRLOGS: $tsLogPath"
				return $tsLogPath
			}
		}
		catch {
			Write-Host "DeployR TS variable provider not available. Using fallback log folder."
		}
	}
	else {
		Write-Host "DeployR.Utility module not available. Using fallback log folder."
	}

	$defaultLogPath = Join-Path -Path $env:windir -ChildPath "Temp\DeployR"
	Write-Host "Using fallback log folder: $defaultLogPath"
	return $defaultLogPath
}

$wrapperLogDirectory = Resolve-DeployRLogDirectory
$wrapperTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$payloadStdOutPath = Join-Path -Path $wrapperLogDirectory -ChildPath "InstallHPSA-Payload-$wrapperTimestamp.stdout.log"
$payloadStdErrPath = Join-Path -Path $wrapperLogDirectory -ChildPath "InstallHPSA-Payload-$wrapperTimestamp.stderr.log"
New-Item -Path $wrapperLogDirectory -ItemType Directory -Force | Out-Null

$payloadPath = Join-Path -Path $env:windir -ChildPath "Temp\Install-HPSA-Payload.ps1"
Write-Host "Writing payload script to: $payloadPath"
$payloadScriptBlock.ToString() | Set-Content -Path $payloadPath -Encoding UTF8 -Force

$pwshExe = "pwsh.exe"
$pwshArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $payloadPath, "-LogDirectory", $wrapperLogDirectory)
$pwshCommandLine = "$pwshExe $($pwshArgs -join ' ')"

Write-Host "Launching payload with command line:"
Write-Host $pwshCommandLine
Write-Host "Payload stdout log: $payloadStdOutPath"
Write-Host "Payload stderr log: $payloadStdErrPath"

$payloadProcess = Start-Process -FilePath $pwshExe -ArgumentList $pwshArgs -PassThru -Wait -RedirectStandardOutput $payloadStdOutPath -RedirectStandardError $payloadStdErrPath
Write-Host "Payload pwsh.exe finished with exit code: $($payloadProcess.ExitCode)"

exit $payloadProcess.ExitCode



