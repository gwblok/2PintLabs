$targets = @(
	[pscustomobject]@{ Name = '_2P Folder'; Paths = @('C:\_2P') }
	[pscustomobject]@{ Name = '2Pint_Downloads Folder'; Paths = @('C:\2Pint_Downloads') }
	[pscustomobject]@{ Name = 'DeployR Folder'; Paths = @('C:\DeployR') }
	[pscustomobject]@{ Name = '2PintLicenseKeys'; Paths = @('C:\2PintLicenseKeys.reg', 'C:\2PintLicenseKeys') }
	[pscustomobject]@{ Name = 'DeployR-BuildLabKit'; Paths = @('C:\DeployR-BuildLabKit.ps1', 'C:\DeployR-BuildLabKit') }
	[pscustomobject]@{ Name = 'DeployRMedia.json'; Paths = @('C:\DeployRMedia.json') }
	[pscustomobject]@{ Name = 'DeployR-Media'; Paths = @('C:\DeployR-Media.ps1', 'C:\DeployR-Media') }
)

foreach ($target in $targets) {
	$existingPath = $null

	foreach ($candidatePath in $target.Paths) {
		if (Test-Path -LiteralPath $candidatePath) {
			$existingPath = $candidatePath
			break
		}
	}

	if (-not $existingPath) {
		Write-Output "Not found, skipping: $($target.Name)"
		continue
	}

	try {
		Write-Output "Deleting: $existingPath"
		Remove-Item -LiteralPath $existingPath -Recurse -Force -ErrorAction Stop
		Write-Output "Deleted: $existingPath"
	}
	catch {
		Write-Output "Failed to delete $existingPath : $($_.Exception.Message)"
	}
}
