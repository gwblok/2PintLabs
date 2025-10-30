<#
.SYNOPSIS
Confirm that the local SYSTEM account (NT AUTHORITY\SYSTEM) is a member of the sysadmin and dbcreator server roles

.DESCRIPTION
Connects to a SQL Server instance (default: localhost\SQLEXPRESS) and verifies whether the built-in
Windows principal 'NT AUTHORITY\SYSTEM' is a member of the server roles 'sysadmin' and 'dbcreator'.

.PARAMETER Instance
The SQL Server instance name to check. Default is 'localhost\SQLEXPRESS'.

.PARAMETER UseInvokeSqlCmd
If set, uses Invoke-Sqlcmd (requires SqlServer module). Otherwise uses a .NET SqlConnection and T-SQL.

.OUTPUTS
PSCustomObject with properties: Instance, LoginExists, IsSysadmin, IsDbCreator, Error
#>
function Test-SystemSqlPermissions {
    [CmdletBinding()]
    param(
    [string]
    $Instance = 'localhost\SQLEXPRESS',
    
    [switch]
    $UseInvokeSqlCmd
    )
    
    $result = [PSCustomObject]@{
        Instance    = $Instance
        LoginExists = $false
        IsSysadmin  = $false
        IsDbCreator = $false
        Error       = $null
    }
    
    try {
        # T-SQL to check if NT AUTHORITY\\SYSTEM exists as a login and check role membership
        # Try matching by SID first; if SID is NULL (unlikely), fall back to name search for principals containing 'system'
        $tsql = @"
SET NOCOUNT ON;
DECLARE @loginname sysname = N'NT AUTHORITY\\SYSTEM';
DECLARE @sid varbinary(85) = SUSER_SID(@loginname);
        
;WITH principals AS (
    SELECT principal_id, name, sid
    FROM sys.server_principals
    WHERE (sid IS NOT NULL AND sid = @sid)
    OR ( @sid IS NULL AND LOWER(name) LIKE '%system%')
    OR (LOWER(name) LIKE '%nt authority%system%')
)
SELECT
    CASE WHEN EXISTS(SELECT 1 FROM principals) THEN 1 ELSE 0 END AS LoginExists,
    CASE WHEN EXISTS(
        SELECT 1 FROM principals p
        JOIN sys.server_role_members srm ON p.principal_id = srm.member_principal_id
        JOIN sys.server_principals r ON srm.role_principal_id = r.principal_id
        WHERE r.name = 'sysadmin') THEN 1 ELSE 0 END AS IsSysadmin,
    CASE WHEN EXISTS(
        SELECT 1 FROM principals p
        JOIN sys.server_role_members srm ON p.principal_id = srm.member_principal_id
        JOIN sys.server_principals r ON srm.role_principal_id = r.principal_id
        WHERE r.name = 'dbcreator') THEN 1 ELSE 0 END AS IsDbCreator;
"@
        
        if ($UseInvokeSqlCmd) {
            if (-not (Get-Module -ListAvailable -Name SqlServer)) {
                throw "SqlServer module is not available; install it or run without -UseInvokeSqlCmd."
            }
            $rows = Invoke-Sqlcmd -ServerInstance $Instance -Query $tsql -ErrorAction Stop
            if ($rows) {
                $result.LoginExists = [bool]$rows.LoginExists
                $result.IsSysadmin  = [bool]$rows.IsSysadmin
                $result.IsDbCreator = [bool]$rows.IsDbCreator
            }
        }
        else {
            # Use System.Data.SqlClient to run the query
            $connString = "Server=$Instance;Integrated Security=True;Connection Timeout=5;"
            $conn = New-Object System.Data.SqlClient.SqlConnection $connString
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $tsql
            $conn.Open()
            $reader = $cmd.ExecuteReader()
            if ($reader.Read()) {
                $loginExists = $reader['LoginExists'] -as [int]
                $isSys = $reader['IsSysadmin'] -as [int]
                $isDb  = $reader['IsDbCreator'] -as [int]
                $result.LoginExists = ($loginExists -eq 1)
                $result.IsSysadmin  = ($isSys -eq 1)
                $result.IsDbCreator = ($isDb -eq 1)
            }
            $reader.Close()
            $conn.Close()
        }
        
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    
    return $result
}

<#
.SYNOPSIS
Get all databases on a SQL Server instance

.DESCRIPTION
Connects to a SQL Server instance (default: localhost\SQLEXPRESS) and retrieves 
information about all databases.

.PARAMETER Instance
The SQL Server instance name to check. Default is 'localhost\SQLEXPRESS'.

.PARAMETER UseInvokeSqlCmd
If set, uses Invoke-Sqlcmd (requires SqlServer module). Otherwise uses a .NET SqlConnection and T-SQL.

.OUTPUTS
PSCustomObject with properties: Instance, Databases (array of database objects), Error
#>
function Test-SqlDatabases {
    [CmdletBinding()]
    param(
    [string]
    $Instance = 'localhost\SQLEXPRESS',
    
    [switch]
    $UseInvokeSqlCmd
    )
    
    $result = [PSCustomObject]@{
        Instance  = $Instance
        Databases = @()
        Error     = $null
    }
    
    try {
        # Get all databases from the instance (excluding system databases)
        $tsql = @"
SET NOCOUNT ON;
SELECT 
    d.name AS DatabaseName,
    d.database_id AS DatabaseId,
    d.create_date AS CreateDate,
    d.state_desc AS State,
    d.recovery_model_desc AS RecoveryModel
FROM sys.databases d
WHERE d.name NOT IN ('master', 'tempdb', 'model', 'msdb')
ORDER BY d.name;
"@
        
        if ($UseInvokeSqlCmd) {
            if (-not (Get-Module -ListAvailable -Name SqlServer)) {
                throw "SqlServer module is not available; install it or run without -UseInvokeSqlCmd."
            }
            $rows = Invoke-Sqlcmd -ServerInstance $Instance -Query $tsql -ErrorAction Stop
            foreach ($row in $rows) {
                $result.Databases += [PSCustomObject]@{
                    Name          = $row.DatabaseName
                    DatabaseId    = $row.DatabaseId
                    CreateDate    = $row.CreateDate
                    State         = $row.State
                    RecoveryModel = $row.RecoveryModel
                }
            }
        }
        else {
            # Use System.Data.SqlClient to run the query
            $connString = "Server=$Instance;Integrated Security=True;Connection Timeout=5;"
            $conn = New-Object System.Data.SqlClient.SqlConnection $connString
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $tsql
            $conn.Open()
            $reader = $cmd.ExecuteReader()
            while ($reader.Read()) {
                $result.Databases += [PSCustomObject]@{
                    Name          = $reader['DatabaseName'] -as [string]
                    DatabaseId    = $reader['DatabaseId'] -as [int]
                    CreateDate    = $reader['CreateDate'] -as [DateTime]
                    State         = $reader['State'] -as [string]
                    RecoveryModel = $reader['RecoveryModel'] -as [string]
                }
            }
            $reader.Close()
            $conn.Close()
        }
        
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    
    return $result
}

<#
.SYNOPSIS
Check if NT AUTHORITY\SYSTEM has db_owner role in specific databases

.DESCRIPTION
Connects to a SQL Server instance and verifies whether NT AUTHORITY\SYSTEM is a member 
of the db_owner role in specified databases. By default checks 'DeployR' and 'iPXEAnywhere35'.

.PARAMETER Instance
The SQL Server instance name to check. Default is 'localhost\SQLEXPRESS'.

.PARAMETER DatabaseNames
Array of database names to check. Default is @('DeployR', 'iPXEAnywhere35').

.PARAMETER UseInvokeSqlCmd
If set, uses Invoke-Sqlcmd (requires SqlServer module). Otherwise uses a .NET SqlConnection and T-SQL.

.OUTPUTS
PSCustomObject with properties: Instance, DatabasePermissions (array of permission status objects), Error
#>
function Test-SystemDatabaseOwnership {
    [CmdletBinding()]
    param(
    [string]
    $Instance = 'localhost\SQLEXPRESS',
    
    [string[]]
    $DatabaseNames = @('DeployR', 'iPXEAnywhere35'),
    
    [switch]
    $UseInvokeSqlCmd
    )
    
    $result = [PSCustomObject]@{
        Instance            = $Instance
        DatabasePermissions = @()
        Error               = $null
    }
    
    try {
        # For each database, check if SYSTEM has db_owner role
        foreach ($dbName in $DatabaseNames) {
            $tsql = @"
SET NOCOUNT ON;
DECLARE @dbName sysname = (SELECT TOP 1 name FROM sys.databases WHERE name = '$dbName');
DECLARE @sql nvarchar(max);
DECLARE @hasDbOwner bit = 0;
DECLARE @loginSid varbinary(85) = SUSER_SID(N'NT AUTHORITY\SYSTEM');
            
IF @dbName IS NOT NULL
BEGIN
    -- Check if the login's SID is mapped to a user in the database and if that user is in db_owner role
    -- This handles cases where the login is mapped as 'dbo' or another username
    SET @sql = N'USE [' + @dbName + N'];
    SELECT @hasDbOwner = CASE 
        WHEN EXISTS(
            SELECT 1 FROM sys.database_principals dp
            JOIN sys.database_role_members drm ON dp.principal_id = drm.member_principal_id
            JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id
            WHERE dp.sid = @loginSid AND r.name = ''db_owner''
        ) THEN 1
        WHEN EXISTS(
            SELECT 1 FROM sys.database_principals dp
            WHERE dp.sid = @loginSid AND dp.name = ''dbo''
        ) THEN 1
        ELSE 0
    END;';
    EXEC sp_executesql @sql, N'@loginSid varbinary(85), @hasDbOwner bit OUTPUT', @loginSid = @loginSid, @hasDbOwner = @hasDbOwner OUTPUT;
END
            
SELECT @dbName AS ActualDbName, CASE WHEN @dbName IS NULL THEN 0 ELSE 1 END AS DbExists, @hasDbOwner AS HasDbOwner;
"@
            
            if ($UseInvokeSqlCmd) {
                if (-not (Get-Module -ListAvailable -Name SqlServer)) {
                    throw "SqlServer module is not available; install it or run without -UseInvokeSqlCmd."
                }
                $row = Invoke-Sqlcmd -ServerInstance $Instance -Query $tsql -ErrorAction Stop
                $result.DatabasePermissions += [PSCustomObject]@{
                    SearchName   = $dbName
                    ActualDbName = $row.ActualDbName
                    DbExists     = [bool]$row.DbExists
                    HasDbOwner   = [bool]$row.HasDbOwner
                }
            }
            else {
                # Use System.Data.SqlClient to run the query
                $connString = "Server=$Instance;Integrated Security=True;Connection Timeout=5;"
                $conn = New-Object System.Data.SqlClient.SqlConnection $connString
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = $tsql
                $conn.Open()
                $reader = $cmd.ExecuteReader()
                if ($reader.Read()) {
                    $result.DatabasePermissions += [PSCustomObject]@{
                        SearchName   = $dbName
                        ActualDbName = if ($reader['ActualDbName'] -isnot [DBNull]) { $reader['ActualDbName'] -as [string] } else { $null }
                        DbExists     = (($reader['DbExists'] -as [int]) -eq 1)
                        HasDbOwner   = (($reader['HasDbOwner'] -as [int]) -eq 1)
                    }
                }
                $reader.Close()
                $conn.Close()
            }
        }
        
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    
    return $result
}

# Quick self-test when run directly

Write-Host "Testing NT AUTHORITY\SYSTEM permissions on local SQL Express..." -ForegroundColor Cyan
$out = Test-SystemSqlPermissions -Instance 'localhost\SQLEXPRESS'
if ($out.Error) {
    Write-Host "Error: $($out.Error)" -ForegroundColor Red
}
else {
    Write-Host "Instance: $($out.Instance)" -ForegroundColor Green
    Write-Host "  LoginExists: $($out.LoginExists)" -ForegroundColor ($(if ($out.LoginExists) {'Green'} else {'Red'}))
    Write-Host "  IsSysadmin : $($out.IsSysadmin)" -ForegroundColor ($(if ($out.IsSysadmin) {'Green'} else {'Yellow'}))
    Write-Host "  IsDbCreator: $($out.IsDbCreator)" -ForegroundColor ($(if ($out.IsDbCreator) {'Green'} else {'Yellow'}))
}

Write-Host "`nChecking NT AUTHORITY\SYSTEM db_owner permissions for all databases..." -ForegroundColor Cyan
$dbOut = Test-SqlDatabases -Instance 'localhost\SQLEXPRESS'
if ($dbOut.Error) {
    Write-Host "Error: Cannot check permissions - failed to get database list" -ForegroundColor Red
}
elseif ($dbOut.Databases.Count -eq 0) {
    Write-Host "No user databases found to check" -ForegroundColor Yellow
}
else {
    # Extract database names and check permissions
    $dbNames = $dbOut.Databases | ForEach-Object { $_.Name }
    $dbOwnerOut = Test-SystemDatabaseOwnership -Instance 'localhost\SQLEXPRESS' -DatabaseNames $dbNames
    
    if ($dbOwnerOut.Error) {
        Write-Host "Error: $($dbOwnerOut.Error)" -ForegroundColor Red
    }
    else {
        Write-Host "Instance: $($dbOwnerOut.Instance)" -ForegroundColor Green
        foreach ($dbPerm in $dbOwnerOut.DatabasePermissions) {
            if (-not $dbPerm.DbExists) {
                Write-Host "  Database '$($dbPerm.SearchName)': DATABASE NOT FOUND" -ForegroundColor Red
            }
            else {
                $color = if ($dbPerm.HasDbOwner) {'Green'} else {'Red'}
                $status = if ($dbPerm.HasDbOwner) {'HAS db_owner'} else {'MISSING db_owner'}
                Write-Host "  Database '$($dbPerm.ActualDbName)': $status" -ForegroundColor $color
            }
        }
    }
}

