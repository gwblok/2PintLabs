#Pull Vars from TS:
try {
    Import-Module DeployR.Utility
}
catch {}

function Test-WindowsDesktopRuntime8 {
	[CmdletBinding()]
	param(
		[string]$RequiredBaseVersion = '8.0'
	)

	[version]$requiredVersion = $null
	if (-not [version]::TryParse($RequiredBaseVersion, [ref]$requiredVersion)) {
		return $false
	}

	$requiredMajor = $requiredVersion.Major
	$requiredMinor = $requiredVersion.Minor
	$matchingVersions = New-Object System.Collections.Generic.HashSet[string]

	function Add-MatchingVersion {
		param(
			[string]$VersionText
		)

		if ([string]::IsNullOrWhiteSpace($VersionText)) {
			return
		}

		[version]$candidateVersion = $null
		if ([version]::TryParse($VersionText, [ref]$candidateVersion)) {
			if ($candidateVersion.Major -eq $requiredMajor -and $candidateVersion.Minor -eq $requiredMinor) {
				$null = $matchingVersions.Add($candidateVersion.ToString())
			}
		}
	}

	# Source 1: dotnet CLI runtime inventory (authoritative)
	try {
		$dotnetLines = & dotnet --list-runtimes 2>$null
		foreach ($line in $dotnetLines) {
			if ($line -match '^Microsoft\.WindowsDesktop\.App\s+([0-9]+\.[0-9]+(?:\.[0-9]+(?:\.[0-9]+)?)?)\s+') {
				Add-MatchingVersion -VersionText $matches[1]
			}
		}
	} catch {}

	# Source 2: shared runtime folder (authoritative)
	$desktopSharedPath = Join-Path -Path $env:ProgramFiles -ChildPath 'dotnet\shared\Microsoft.WindowsDesktop.App'
	if (Test-Path -Path $desktopSharedPath) {
		Get-ChildItem -Path $desktopSharedPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
			Add-MatchingVersion -VersionText $_.Name
		}
	}

	# Source 3: sharedfx registry keys (authoritative)
	$registryPaths = @(
		'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App',
		'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x86\sharedfx\Microsoft.WindowsDesktop.App'
	)
	foreach ($path in $registryPaths) {
		if (Test-Path -Path $path) {
			Get-ChildItem -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
				Add-MatchingVersion -VersionText $_.PSChildName
			}
		}
	}

	return ($matchingVersions.Count -gt 0)
}

[String]$WinDesktopRuntime8Installed = Test-WindowsDesktopRuntime8
${TSEnv:WinDesktopRuntime8Installed} = $WinDesktopRuntime8Installed