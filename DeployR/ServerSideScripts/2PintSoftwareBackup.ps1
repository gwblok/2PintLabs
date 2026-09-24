<#
.SYNOPSIS
	Creates a registry-driven backup of the local 2Pint DeployR and StifleR installation.

.DESCRIPTION
	Backs up the 2Pint registry hive, the StifleR databases listed in the
	registry, and the DeployR content location. If DeployR uses SQL Server,
	the script also creates a native SQL Server database backup. DeployR
	SQLite databases live in the content location and are included in that
	folder backup.
#>
[CmdletBinding()]
param(
	[string]$BackupPath = 'D:\2PintSoftwareBackup'
)

$ErrorActionPreference = 'Stop'
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
		[string]$Description
	)

	if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
		Write-Warning "$Description was not found: $SourcePath"
		return $false
	}

	Write-Host "Backing up $Description from $SourcePath" -ForegroundColor Cyan
	New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
	Get-ChildItem -LiteralPath $SourcePath -Force | Copy-Item -Destination $DestinationPath -Recurse -Force
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

function Backup-DeployRSqlDatabase {
	param(
		[Parameter(Mandatory)]
		[string]$ConnectionString,

		[Parameter(Mandatory)]
		[string]$DestinationPath
	)

	$builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnectionString)
	if ([string]::IsNullOrWhiteSpace($builder.DataSource) -or [string]::IsNullOrWhiteSpace($builder.InitialCatalog)) {
		throw 'DeployR ConnectionString must include Server/Data Source and Database/Initial Catalog.'
	}

	$databaseName = $builder.InitialCatalog
	$builder.InitialCatalog = 'master'
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

try {
	$servicesToRestart = Stop-2PintSoftwareServices

	New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
	New-Item -ItemType Directory -Path (Join-Path $BackupRoot 'Registry') -Force | Out-Null

	Write-Host "Creating 2Pint Software backup at $BackupRoot" -ForegroundColor Green

	Write-Host 'Exporting the 2Pint Software registry hive.' -ForegroundColor Cyan
	& reg.exe export 'HKLM\Software\2Pint Software' (Join-Path $BackupRoot 'Registry\2PintSoftware.reg') /y | Out-Null
	if ($LASTEXITCODE -ne 0) {
		throw "Registry export failed with exit code $LASTEXITCODE."
	}

	$stifleRBackupRoot = Join-Path $BackupRoot 'StifleRDatabases'
	foreach ($databasePath in Get-StifleRDatabasePaths) {
		$destinationName = Split-Path -Path $databasePath -Leaf
		if ([string]::IsNullOrWhiteSpace($destinationName)) {
			$destinationName = 'Databases'
		}

		Copy-BackupFolder -SourcePath $databasePath -DestinationPath (Join-Path $stifleRBackupRoot $destinationName) -Description 'StifleR database folder' | Out-Null
	}

	if (-not (Test-Path -LiteralPath $DeployRRegPath)) {
		Write-Warning "DeployR registry key was not found: $DeployRRegPath"
		return
	}

	$deployRSettings = Get-ItemProperty -LiteralPath $DeployRRegPath
	$deployRContentPath = $deployRSettings.ContentLocation
	if ([string]::IsNullOrWhiteSpace($deployRContentPath)) {
		$deployRContentPath = "$env:ProgramData\2Pint Software\DeployR"
		Write-Warning "DeployR ContentLocation was not set; using the default path: $deployRContentPath"
	}

	Copy-BackupFolder -SourcePath $deployRContentPath -DestinationPath (Join-Path $BackupRoot 'DeployRContent') -Description 'DeployR content folder' | Out-Null

	switch ($deployRSettings.SqlConnectionBy) {
		'SQLite' {
			Write-Host 'DeployR is configured for SQLite; its database is included with the DeployR content backup.' -ForegroundColor Green
		}
		'ServerInstanceAndDB' {
			if ([string]::IsNullOrWhiteSpace($deployRSettings.ConnectionString)) {
				throw 'DeployR is configured for SQL Server but ConnectionString is not set in the registry.'
			}

			$sqlBackupPath = Join-Path $BackupRoot 'DeployRSqlDatabase'
			New-Item -ItemType Directory -Path $sqlBackupPath -Force | Out-Null
			Backup-DeployRSqlDatabase -ConnectionString $deployRSettings.ConnectionString -DestinationPath $sqlBackupPath
		}
		default {
			Write-Warning "DeployR SqlConnectionBy is '$($deployRSettings.SqlConnectionBy)'; no separate DeployR database backup was created."
		}
	}

	Write-Host "2Pint Software backup completed: $BackupRoot" -ForegroundColor Green
}
finally {
	Start-2PintSoftwareServices -ServiceNames $servicesToRestart
}
