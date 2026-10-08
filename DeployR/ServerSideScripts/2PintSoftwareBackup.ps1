<#
.SYNOPSIS
	Creates a registry-driven backup of the local 2Pint DeployR and StifleR installation.

.DESCRIPTION
	Backs up the 2Pint registry hive, the StifleR databases listed in the
	registry, and the DeployR content location. If DeployR uses SQL Server,
	the script also creates a native SQL Server database backup. DeployR
	SQLite databases live in the content location and are included in that
	folder backup.

.NOTES
	Restoring the DeployR SQL Server database to a new SQL Express instance:

	1. Copy the .bak file from '<BackupRoot>\DeployRSqlDatabase' to the new server.
	2. Restore it with SQL Server Management Studio, or sqlcmd (requires the SqlServer
	   PowerShell module if you'd rather use Restore-SqlDatabase instead), e.g.:

		sqlcmd -S ".\SQLEXPRESS" -Q "RESTORE DATABASE [DeployR] FROM DISK = N'C:\Restore\DeployR.bak' WITH REPLACE, STATS = 10;"

	   or with T-SQL (adjust the logical file names/paths for the target instance -
	   run "RESTORE FILELISTONLY FROM DISK = N'C:\Restore\DeployR.bak';" first to see them):

		RESTORE DATABASE [DeployR]
		FROM DISK = N'C:\Restore\DeployR.bak'
		WITH MOVE 'DeployR' TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\DeployR.mdf',
			 MOVE 'DeployR_log' TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\DeployR_log.ldf',
			 REPLACE, STATS = 10;

	3. Update the new server's registry (HKLM:\Software\2Pint Software\DeployR\GeneralSettings)
	   so 'SqlConnectionBy' is 'ServerInstanceAndDB' and, if the instance name or database
	   name differs from the default (.\SQLEXPRESS / DeployR), set 'ConnectionString' to
	   match, e.g. 'Server=.\SQLEXPRESS;Database=DeployR;Trusted_Connection=True;MultipleActiveResultSets=true;TrustServerCertificate=True'.
	4. Grant the DeployR service account (commonly NT AUTHORITY\SYSTEM) db_owner on the
	   restored database, then restart the DeployR service.
#>
[CmdletBinding()]
param(
	[string]$BackupPath = 'D:\2PintSoftwareBackup',

	# Select which backup steps to run. Defaults to all steps.
	[ValidateSet('All', 'Registry', 'StifleR', 'DeployRContent', 'DeployRSql')]
	[string[]]$Tasks = @('All')
)


$ErrorActionPreference = 'Stop'

function Test-BackupTask {
	param([Parameter(Mandatory)][string]$Name)
	return ($Tasks -contains 'All' -or $Tasks -contains $Name)
}
$2PintRegPath = 'HKLM:\Software\2Pint Software'
$StifleRRegPath = Join-Path $2PintRegPath 'StifleR\Server'
$DeployRRegPath = Join-Path $2PintRegPath 'DeployR\GeneralSettings'
$DateStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupRoot = Join-Path $BackupPath "2PintSoftware-$DateStamp"

function Copy-BackupFolder {
	param(
		[Parameter(Mandatory)]
		[string]$SourcePath,

		[Parameter(Mandatory)]
		[string]$DestinationPath,

		[Parameter(Mandatory)]
		[string]$Description,

		# Directory names (wildcards allowed) to skip, matched at any depth under SourcePath.
		[string[]]$ExcludeDirectories = @()
	)

	if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
		Write-Warning "$Description was not found: $SourcePath"
		return $false
	}

	Write-Host "Backing up $Description from $SourcePath" -ForegroundColor Cyan
	New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null

	# robocopy is used instead of Copy-Item so excluded directory names can be matched at any depth.
	$robocopyArgs = @($SourcePath, $DestinationPath, '/E', '/COPY:DAT', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS')
	if ($ExcludeDirectories) {
		$robocopyArgs += '/XD'
		$robocopyArgs += $ExcludeDirectories
	}

	& robocopy.exe @robocopyArgs | Out-Null
	if ($LASTEXITCODE -ge 8) {
		throw "Robocopy failed with exit code $LASTEXITCODE while backing up $Description."
	}

	return $true
}

function Get-StifleRDatabasePaths {
	if (-not (Test-Path -LiteralPath $StifleRRegPath)) {
		Write-Warning "StifleR registry key was not found: $StifleRRegPath"
		return @()
	}

	$settings = Get-ItemProperty -LiteralPath $StifleRRegPath
	$databasePaths = @(
		$settings.MainDatabasePath
		$settings.HistoryDatabasePath
		$settings.LocationDatabasePath
		$settings.NewLocationDatabasePath
	) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

	if (-not $databasePaths) {
		$databasePaths = @("$env:ProgramData\2Pint Software\StifleR\Server\Databases")
		Write-Warning 'No StifleR database paths were set in the registry; using the default path.'
	}

	return $databasePaths
}

function Get-DeployRSqlConnectionString {
	param(
		[Parameter(Mandatory)]
		[psobject]$DeployRSettings
	)

	if (-not [string]::IsNullOrWhiteSpace($DeployRSettings.ConnectionString)) {
		return $DeployRSettings.ConnectionString
	}

	# DeployR falls back to a local SQL Express instance with Windows auth when no ConnectionString is stored in the registry.
	$instanceSuffix = if (Get-Service -Name 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue) { '\SQLEXPRESS' } else { '' }
	$defaultConnectionString = "Server=.$instanceSuffix;Database=DeployR;Trusted_Connection=True;MultipleActiveResultSets=true;TrustServerCertificate=True"
	Write-Warning "DeployR ConnectionString was not set in the registry; using the default local SQL Server connection: $defaultConnectionString"
	return $defaultConnectionString
}

function Backup-DeployRSqlDatabase {
	param(
		[Parameter(Mandatory)]
		[string]$ConnectionString,

		[Parameter(Mandatory)]
		[string]$DestinationPath
	)

	$builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnectionString)
	# DbConnectionStringBuilder implements IDictionary, so PowerShell resolves .DataSource/.InitialCatalog
	# through the indexer instead of the real properties; use the actual keyword names instead.
	$dataSource = $builder['Data Source']
	$initialCatalog = $builder['Initial Catalog']
	if ([string]::IsNullOrWhiteSpace($dataSource) -or [string]::IsNullOrWhiteSpace($initialCatalog)) {
		throw 'DeployR ConnectionString must include Server/Data Source and Database/Initial Catalog.'
	}

	$databaseName = $initialCatalog
	$builder['Initial Catalog'] = 'master'
	$databaseBackupPath = Join-Path $DestinationPath "$databaseName.bak"
	$quotedDatabaseName = '[' + $databaseName.Replace(']', ']]') + ']'
	$quotedBackupPath = $databaseBackupPath.Replace("'", "''")
	$query = "BACKUP DATABASE $quotedDatabaseName TO DISK = N'$quotedBackupPath' WITH COPY_ONLY, INIT, STATS = 10;"

	Write-Host "Backing up DeployR SQL Server database '$databaseName'." -ForegroundColor Cyan
	$connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
	$command = $connection.CreateCommand()
	$command.CommandText = $query
	$command.CommandTimeout = 0

	try {
		$connection.Open()
		[void]$command.ExecuteNonQuery()
	}
	finally {
		$command.Dispose()
		$connection.Dispose()
	}

	if (-not (Test-Path -LiteralPath $databaseBackupPath -PathType Leaf)) {
		throw "SQL Server reported success but the backup was not created: $databaseBackupPath"
	}
}

function Stop-2PintSoftwareServices {
	$runningServices = Get-Service | Where-Object {
		$_.DisplayName -like '2Pint Software*' -and $_.Status -eq 'Running'
	}

	foreach ($service in $runningServices) {
		Write-Host "Stopping service: $($service.DisplayName)" -ForegroundColor Yellow
		Stop-Service -Name $service.Name -Force
		(Get-Service -Name $service.Name).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromMinutes(2))
	}

	return @($runningServices.Name)
}

function Start-2PintSoftwareServices {
	param(
		[string[]]$ServiceNames
	)

	foreach ($serviceName in $ServiceNames) {
		try {
			$service = Get-Service -Name $serviceName -ErrorAction Stop
			if ($service.Status -ne 'Running') {
				Write-Host "Starting service: $($service.DisplayName)" -ForegroundColor Yellow
				Start-Service -Name $serviceName -ErrorAction Stop
				(Get-Service -Name $serviceName).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromMinutes(2))
			}
		}
		catch {
			Write-Warning "Could not restart service '$serviceName': $($_.Exception.Message)"
		}
	}
}

$servicesToRestart = @()

# Only stop services when a task that touches live files is selected.
$needsServiceStop = (Test-BackupTask 'StifleR') -or (Test-BackupTask 'DeployRContent')

try {
	if ($needsServiceStop) {
		$servicesToRestart = Stop-2PintSoftwareServices
	}

	New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

	Write-Host "Creating 2Pint Software backup at $BackupRoot" -ForegroundColor Green

	if (Test-BackupTask 'Registry') {
		New-Item -ItemType Directory -Path (Join-Path $BackupRoot 'Registry') -Force | Out-Null
		Write-Host 'Exporting the 2Pint Software registry hive.' -ForegroundColor Cyan
		& reg.exe export 'HKLM\Software\2Pint Software' (Join-Path $BackupRoot 'Registry\2PintSoftware.reg') /y | Out-Null
		if ($LASTEXITCODE -ne 0) {
			throw "Registry export failed with exit code $LASTEXITCODE."
		}
	}

	if (Test-BackupTask 'StifleR') {
		$stifleRBackupRoot = Join-Path $BackupRoot 'StifleRDatabases'
		foreach ($databasePath in Get-StifleRDatabasePaths) {
			$destinationName = Split-Path -Path $databasePath -Leaf
			if ([string]::IsNullOrWhiteSpace($destinationName)) {
				$destinationName = 'Databases'
			}

			Copy-BackupFolder -SourcePath $databasePath -DestinationPath (Join-Path $stifleRBackupRoot $destinationName) -Description 'StifleR database folder' | Out-Null
		}
	}

	if ((Test-BackupTask 'DeployRContent') -or (Test-BackupTask 'DeployRSql')) {
		if (-not (Test-Path -LiteralPath $DeployRRegPath)) {
			Write-Warning "DeployR registry key was not found: $DeployRRegPath"
		}
		else {
			$deployRSettings = Get-ItemProperty -LiteralPath $DeployRRegPath

			if (Test-BackupTask 'DeployRContent') {
				$deployRContentPath = $deployRSettings.ContentLocation
				if ([string]::IsNullOrWhiteSpace($deployRContentPath)) {
					$deployRContentPath = "$env:ProgramData\2Pint Software\DeployR"
					Write-Warning "DeployR ContentLocation was not set; using the default path: $deployRContentPath"
				}

				Copy-BackupFolder -SourcePath $deployRContentPath -DestinationPath (Join-Path $BackupRoot 'DeployRContent') -Description 'DeployR content folder' -ExcludeDirectories @('Downloads', 'Downloads.old', 'Logs', '00000000-*') | Out-Null
			}

			if (Test-BackupTask 'DeployRSql') {
				switch ($deployRSettings.SqlConnectionBy) {
					'SQLite' {
						Write-Host 'DeployR is configured for SQLite; its database is included with the DeployR content backup.' -ForegroundColor Green
					}
					'ServerInstanceAndDB' {
						$sqlConnectionString = Get-DeployRSqlConnectionString -DeployRSettings $deployRSettings

						$sqlBackupPath = Join-Path $BackupRoot 'DeployRSqlDatabase'
						New-Item -ItemType Directory -Path $sqlBackupPath -Force | Out-Null
						Backup-DeployRSqlDatabase -ConnectionString $sqlConnectionString -DestinationPath $sqlBackupPath
					}
					default {
						Write-Warning "DeployR SqlConnectionBy is '$($deployRSettings.SqlConnectionBy)'; no separate DeployR database backup was created."
					}
				}
			}
		}
	}

	Write-Host "2Pint Software backup completed: $BackupRoot" -ForegroundColor Green
}
finally {
	if ($needsServiceStop) {
		Start-2PintSoftwareServices -ServiceNames $servicesToRestart
	}
}
