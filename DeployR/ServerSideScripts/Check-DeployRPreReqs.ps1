<#Tests
- Check if all required applications are installed
- Validate server configuration settings
- Ensure firewall rules are correctly set
- Checks Connectivity for DeployR / StifleR URLs & Ports based on Registry Entries
- Check if BranchCache is enabled
- Check if IIS components are installed
- Check if IIS Virtual Web Directory is Setup
- Check if IIS MIME types added
- Check StifleR Dashboard URLs in Registry & Server Config File
- Check for Certificate set in StifleR & DeployR is same and that the thumbprint exists
- Check if all required services are running
- Check for SQL String Connection based on DeployR Registry
- Check for SQL Permissions of NT AUTHORITY\SYSTEM for sysadmin and dbcreator roles
- Check for SQL Permissions of NT AUTHORITY\SYSTEM for db_owner on all databases



Remediation at end will prompt to remediate:
- Missing IIS MIME types
- Missing IIS Virtual Directories
- Missing Windows Components

Change Log
- 2025.10.22 - Updated .NET version to 8.0.21
- 2025.10.29 - Updated PowerShell version to 7.4.13
- 2025.10.29 - Added SQL Permissions checks for NT AUTHORITY\SYSTEM


To DO
- Add if Statements for SQL Permissions checks and remediation, first check connection string to get instance name
#>

#Ensure Several things are installed, as well as configurations are done to help troubleshoot DeployR installations

#Keep this updated as needed 
$DotNetMinVersion = '8.0.21'
$PowerShellMinVersion = '7.4.13'



#PowerShell Table of Pre-Req Applications:
$PreReqApps = @(
[PSCustomObject]@{Title = 'Microsoft .NET Runtime'; Installed = $false ; MinVersion = $DotNetMinVersion; URL = 'https://dotnet.microsoft.com/en-us/download/dotnet/8.0'}
[PSCustomObject]@{Title = 'Microsoft Windows Desktop Runtime'; Installed = $false ; MinVersion = $DotNetMinVersion; URL = 'https://dotnet.microsoft.com/en-us/download/dotnet/8.0'}
[PSCustomObject]@{Title = 'Microsoft ASP.NET Core'; Installed = $false ; MinVersion = $DotNetMinVersion; URL = 'https://dotnet.microsoft.com/en-us/download/dotnet/8.0'}
[PSCustomObject]@{Title = 'Windows Assessment and Deployment Kit Windows Preinstallation Environment'; Installed = $false; URL = 'https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install'}
[PSCustomObject]@{Title = 'PowerShell 7-x64'; Installed = $false; ; MinVersion = $PowerShellMinVersion; URL = 'https://aka.ms/powershell-release?tag=lts'}
[PSCustomObject]@{Title = 'Microsoft SQL Server'; Installed = $false; URL = 'https://www.microsoft.com/en-us/download/details.aspx?id=104781'}
[PSCustomObject]@{Title = 'SQL Server Management Studio'; Installed = $false; URL = 'https://learn.microsoft.com/en-us/ssms/install/install'}
[PSCustomObject]@{Title = 'Microsoft Visual C++ 2015-2022 Redistributable (x64)'; Installed = $false; URL = 'https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170'}
[PSCustomObject]@{Title = '2Pint Software DeployR'; Installed = $false}
[PSCustomObject]@{Title = '2Pint Software StifleR Server'; Installed = $false}
[PSCustomObject]@{Title = '2Pint Software StifleR Dashboards'; Installed = $false}
[PSCustomObject]@{Title = '2Pint Software StifleR WmiAgent'; Installed = $false}
)
$FirewallRules = @(
[PSCustomObject]@{DisplayName = '2Pint DeployR HTTPS 7281'; Port = 7281; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint DeployR HTTP 7282'; Port = 7282; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint Software StifleR API 9000'; Port = 9000; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint Software StifleR SignalR 1414 TCP'; Port = 1414; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint Software StifleR SignalR 1414 UDP'; Port = 1414; Protocol = 'UDP'}
[PSCustomObject]@{DisplayName = '2Pint iPXE WebService 8051'; Port = 8051; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint iPXE WebService 8052'; Port = 8052; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint 2PXE 8050'; Port = 8050; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint 2PXE 4011'; Port = 4011; Protocol = 'UDP'}
)

#region Functions
function Get-SqlInstances {
    <#
    .SYNOPSIS
    Finds SQL Server instances installed on the local server.
    
    .DESCRIPTION
    Queries the registry and services to discover SQL Server instances on the local machine.
    Returns information about each instance including name, version, edition, and running status.
    
    .EXAMPLE
    $instances = Get-SqlInstances
    $instances | Format-Table -AutoSize
    
    .OUTPUTS
    PSCustomObject with properties: InstanceName, ServiceName, IsRunning, Version, Edition, InstancePath
    #>
    [CmdletBinding()]
    param()
    
    $instances = @()
    
    try {
        # Check for SQL Server instances in registry
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server'
        
        if (Test-Path $regPath) {
            # Get installed instances
            $installedInstances = Get-ItemProperty -Path "$regPath" -Name InstalledInstances -ErrorAction SilentlyContinue
            
            if ($installedInstances.InstalledInstances) {
                foreach ($instanceName in $installedInstances.InstalledInstances) {
                    # Determine service name
                    if ($instanceName -eq 'MSSQLSERVER') {
                        $serviceName = 'MSSQLSERVER'
                        $displayName = '(Default Instance)'
                        $connectionName = '.'
                    }
                    else {
                        $serviceName = "MSSQL`$$instanceName"
                        $displayName = $instanceName
                        $connectionName = ".\$instanceName"
                    }
                    
                    # Get service status
                    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                    $isRunning = $service.Status -eq 'Running'
                    
                    # Try to get instance details from registry
                    $instanceRegPath = "$regPath\Instance Names\SQL"
                    $instanceKey = Get-ItemProperty -Path $instanceRegPath -Name $instanceName -ErrorAction SilentlyContinue
                    
                    $version = 'Unknown'
                    $edition = 'Unknown'
                    $instancePath = 'Unknown'
                    
                    if ($instanceKey) {
                        $instanceId = $instanceKey.$instanceName
                        $setupPath = "$regPath\$instanceId\Setup"
                        
                        if (Test-Path $setupPath) {
                            $setupInfo = Get-ItemProperty -Path $setupPath -ErrorAction SilentlyContinue
                            $version = $setupInfo.Version
                            $edition = $setupInfo.Edition
                            $instancePath = $setupInfo.SQLPath
                        }
                    }
                    
                    $instances += [PSCustomObject]@{
                        InstanceName = $displayName
                        ConnectionString = $connectionName
                        ServiceName = $serviceName
                        IsRunning = $isRunning
                        Status = if ($service) { $service.Status } else { 'Not Found' }
                        Version = $version
                        Edition = $edition
                        InstancePath = $instancePath
                    }
                }
            }
        }
        
        # If no instances found in registry, check for running SQL services
        if ($instances.Count -eq 0) {
            $sqlServices = Get-Service -Name "MSSQL*" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^MSSQL\$' -or $_.Name -eq 'MSSQLSERVER' }
            
            foreach ($service in $sqlServices) {
                if ($service.Name -eq 'MSSQLSERVER') {
                    $instanceName = '(Default Instance)'
                    $connectionName = '.'
                }
                else {
                    $instanceName = $service.Name -replace '^MSSQL\$', ''
                    $connectionName = ".\$instanceName"
                }
                
                $instances += [PSCustomObject]@{
                    InstanceName = $instanceName
                    ConnectionString = $connectionName
                    ServiceName = $service.Name
                    IsRunning = $service.Status -eq 'Running'
                    Status = $service.Status
                    Version = 'Unknown'
                    Edition = 'Unknown'
                    InstancePath = 'Unknown'
                }
            }
        }
    }
    catch {
        Write-Error "Failed to enumerate SQL instances: $_"
    }
    
    if ($instances.Count -eq 0) {
        Write-Warning "No SQL Server instances found on this server."
    }
    
    return $instances
}

function Get-InstalledApps
{
    if (![Environment]::Is64BitProcess) {
        $regpath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    }
    else {
        $regpath = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
    }
    Get-ItemProperty $regpath | .{process{if($_.DisplayName -and $_.UninstallString) { $_ } }} | Select DisplayName, Publisher, InstallDate, DisplayVersion, UninstallString |Sort DisplayName
}

function Set-SqlServerPermissions {
    <#
    .SYNOPSIS
    Configures the permissions and firewall rules for Microsoft SQL Server.
    
    .DESCRIPTION
    This function grants permissions to NT AUTHORITY\SYSTEM (sysadmin and dbcreator roles) 
    and configures the firewall rules for SQL Server default instance and Browser service.
    
    .PARAMETER InstanceName
    The name of the SQL Server instance. Use 'MSSQLSERVER' for the default instance.
    Default is 'SQLEXPRESS'.
    
    .PARAMETER SkipFirewall
    If specified, skips creating firewall rules.
    
    .EXAMPLE
    Set-SqlServerPermissionsAndFirewall -InstanceName 'SQLEXPRESS'
    
    .EXAMPLE
    Set-SqlServerPermissionsAndFirewall -InstanceName 'MSSQLSERVER' -SkipFirewall
    
    .NOTES
    Author: Mike Terrill/2Pint Software
    Date: August 4, 2025
    Version: 25.08.04
    Requires: Administrative privileges, 64-bit Windows, sqlcmd installed
    #>
    [CmdletBinding()]
    param(
    [Parameter()]
    [string]$InstanceName = 'SQLEXPRESS'
    
    )
    
    # Ensure the script runs with elevated privileges
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This function requires administrative privileges. Please run PowerShell as Administrator."
        return $false
    }
    
    # Determine server instance connection string
    if ($InstanceName -eq 'MSSQLSERVER') {
        $ServerInstance = '.'
    }
    else {
        $ServerInstance = ".\$InstanceName"
    }
    
    # Find sqlcmd.exe
    $SqlCmdPath = $null
    $possiblePaths = @(
    "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\190\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\160\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\150\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\140\Tools\Binn\sqlcmd.exe"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $SqlCmdPath = $path
            break
        }
    }
    
    if (-not $SqlCmdPath) {
        Write-Error "sqlcmd.exe not found. Please ensure SQL Server client tools are installed."
        return $false
    }
    
    Write-Host "Using sqlcmd at: $SqlCmdPath" -ForegroundColor Cyan
    
    # Grant NT AUTHORITY\SYSTEM sysadmin and dbcreator rights
    Write-Host "Granting permissions to NT AUTHORITY\SYSTEM on $ServerInstance..." -ForegroundColor Cyan
    
    $TsqlQuery = "IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'NT AUTHORITY\SYSTEM') CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS; EXEC sp_addsrvrolemember @loginame = 'NT AUTHORITY\SYSTEM', @rolename = 'sysadmin'; EXEC sp_addsrvrolemember @loginame = 'NT AUTHORITY\SYSTEM', @rolename = 'dbcreator';"
    
    try {
        $Process = Start-Process -FilePath $SqlCmdPath -ArgumentList "-S `"$ServerInstance`" -Q `"$TsqlQuery`"" -NoNewWindow -PassThru -Wait -ErrorAction Stop
        if ($Process.ExitCode -eq 0) {
            Write-Host "Successfully granted sysadmin and dbcreator roles to NT AUTHORITY\SYSTEM on $ServerInstance." -ForegroundColor Green
        }
        else {
            Write-Error "sqlcmd failed with exit code $($Process.ExitCode)."
            return $false
        }
    }
    catch {
        Write-Error "Failed to execute sqlcmd. Error: $($_.Exception.Message)"
        Write-Host "Ensure sqlcmd is installed and the SQL Server instance ($ServerInstance) is running." -ForegroundColor Yellow
        return $false
    }
    
    return $true
}
function Test-Url {
    param (
    [string]$Url
    )
    
    try {
        $request = [System.Net.WebRequest]::Create($Url)
        $request.Method = "HEAD"  # Uses HEAD to check status without downloading content
        $request.Timeout = 5000   # 5 second timeout
        
        $response = $request.GetResponse()
        $status = [int]$response.StatusCode
        
        if ($status -eq 200) {
            #Write-Output "URL is active: $Url"
            return $true
        }
        else {
            #Write-Output "URL responded with status code $status $Url"
            return $false
        }
        $response.Close()
    }
    catch {
        Write-Output "URL is not accessible: $Url - Error: $_"
    }
}
function Test-SQLConnection {
    param(
    [Parameter(Mandatory=$true)]
    [string]$ConnectionString
    )
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $connection.Open()
        Write-Host "Connection successful!" -ForegroundColor Green
        $connection.Close()
    }
    catch {
        Write-Host "Connection failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
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


#endregion
$TempFolder = "$env:USERPROFILE\Downloads\DeployR_TroubleShootingLogs"
if (!(Test-Path -Path $TempFolder)){New-Item -Path $TempFolder -ItemType Directory -Force | Out-Null}
$TranscriptFilePath = "$TempFolder\Check-DeployR_TroubleShooting_PreReqs.log"
if (Test-Path -Path $TranscriptFilePath) {
    Remove-Item -Path $TranscriptFilePath -Force
}   
Start-Transcript -Path $TranscriptFilePath -Force

# Executing Script
Write-Host "=========================================================================" -ForegroundColor DarkGray
#Test if Applications are installed
$installedApps = Get-InstalledApps | Where-Object {$_.DisplayName -notmatch " - Shared framework"}

#Testing Specific Applications
#$installedApps = Get-InstalledApps | Where-Object {$_.DisplayName -match "PowerShell 7"}

Write-Host "Checking for Pre-Requisite Applications..." -ForegroundColor Cyan
$PreReqAppsStatus = @()
foreach ($app in $PreReqApps) {
    $found = $installedApps | Where-Object { 
        $_.DisplayName -match [regex]::Escape($app.Title) -or
        $_.DisplayName -like "*$($app.Title)*"
    }
    
    if ($found) {
        
        if (($found | Select-Object -Unique DisplayName | Measure-Object).Count -gt 1) {
            #Write-Host "Multiple versions of $($app.Title) found:" -ForegroundColor Yellow
            #$found | Select-Object -Unique DisplayName | ForEach-Object { Write-Host " - $($_.DisplayName) Version: $($_.DisplayVersion)" -ForegroundColor Yellow }
            foreach ($appitem in $found) {
                $Version = $found.DisplayVersion
                if ($app.Url -match "dotnet"){
                    Write-Host "Testing $($found.DisplayName)"
                    if ($found.DisplayName -match "\d+\.\d+\.\d+") {
                        $Version = $matches[0]
                        #Write-Host "   Found .NET version: $Version" -ForegroundColor DarkGray
                    }
                }
                
                $PreReqAppsStatus += [PSCustomObject]@{
                    Title       = $app.Title
                    Installed   = $true
                    URL         = $app.URL
                    InstallDate = $appitem.InstallDate
                    Version     = $Version
                    DisplayName = $appitem.DisplayName
                    MinVersion  = $app.MinVersion
                }
            }
        }
        else{
            $found = $found | Select-Object -First 1
            $Version = $found.DisplayVersion
            if ($app.Url -match "dotnet"){
                #Write-Host "Testing $($found.DisplayName)"
                if ($found.DisplayName -match "\d+\.\d+\.\d+") {
                    $Version = $matches[0]
                    #Write-Host "   Found .NET version: $Version" -ForegroundColor DarkGray
                }
            }
            $PreReqAppsStatus += [PSCustomObject]@{
                Title       = $app.Title
                Installed   = $true
                URL         = $app.URL
                InstallDate = $found.InstallDate
                Version     = $Version
                DisplayName = $found.DisplayName
                MinVersion  = $app.MinVersion
            }
        }
        
        
        New-Variable -Name "Installed_$($app.Title.Replace(' ', '_'))" -Value $true -Scope Global -Force
        
    }
    
    else {
        New-Variable -Name "Installed_$($app.Title.Replace(' ', '_'))" -Value $false -Scope Global -Force
        $PreReqAppsStatus += [PSCustomObject]@{
            Title    = $app.Title
            Installed = $false
            URL      = $app.URL
        }
    }
}
#Display App Status, Green Arrow next to Installed Apps and Red X next to Missing Apps

foreach ($app in $PreReqAppsStatus) {
    
    if ($app.Installed) {
        if ($app.MinVersion -and $app.Version -and ([version]$app.Version -lt [version]$app.MinVersion)) {
            Write-Host " ✗  $($app.Title)  " -ForegroundColor Red
            Write-Host "   Installed Version: $($app.Version)" -ForegroundColor DarkGray
            Write-Host "   Minimum Required Version: $($app.MinVersion)" -ForegroundColor DarkGray
        }
        else {
            Write-Host " ✓  $($app.Title)  " -ForegroundColor Green
            Write-Host "   Installed Version: $($app.Version)" -ForegroundColor DarkGray
            Write-Host "   Display Name: $($app.DisplayName)" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host " ✗  $($app.Title)" -ForegroundColor Red
    }
}

#Double Check PowerShell is NOT 7.5 or above    
$PowerShellVersionInstalled = $PSVersionTable.PSVersion.ToString()
if ([version]$PowerShellVersionInstalled -ge [version]'7.5') {
    Write-Host "=========================================================================" -ForegroundColor Red
    Write-Host "✗ PowerShell 7.5.X is NOT supported." -ForegroundColor Red
    Write-Host "   Installed Version: $PowerShellVersionInstalled" -ForegroundColor DarkGray
    Write-Host "   Required  Version: $PowerShellMinVersion" -ForegroundColor DarkGray
    Write-Host "=========================================================================" -ForegroundColor Red
}
#Double Check PowerShell is NOT 7.5 or above    
$PowerShellVersionInstalled = $installedApps | Where-Object { $_.DisplayName -match "PowerShell 7" } | Select-Object -First 1 | ForEach-Object {
    if ($_.DisplayVersion -match "\d+\.\d+\.\d+") {
        if ($matches[0] -ge [version]'7.5') {
            Write-Host "=========================================================================" -ForegroundColor Red
            Write-Host "✗ PowerShell 7.5.X is NOT supported." -ForegroundColor Red
            Write-Host "   Installed Version: $PowerShellVersionInstalled" -ForegroundColor DarkGray
            Write-Host "   Required  Version: $PowerShellMinVersion" -ForegroundColor DarkGray
            Write-Host "=========================================================================" -ForegroundColor Red
        }
    }
}



$MissingApps = $PreReqAppsStatus | Where-Object { $_.Installed -eq $false }
if ($MissingApps) {
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "The following Pre-Requisite Applications are NOT installed:" -ForegroundColor Red
    foreach ($app in $MissingApps) {
        $appName = $app.Title -replace 'Installed_', '' -replace '_', ' '
        
        Write-Host " - $appName" -ForegroundColor Yellow
        if ($app.URL) {
            Write-Host "   Download URL: $($app.URL)" -ForegroundColor DarkGray
        }
    }
    Write-Host "Please install the missing applications and re-run this script." -ForegroundColor Yellow
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    #return
}


Write-Host "=========================================================================" -ForegroundColor DarkGray
Write-Host "Confirming Windows Features for DeployR" -ForegroundColor Cyan
#Confirm Windows Components
$RequiredWindowsComponents = @(
"BranchCache",
"Web-Server",
"Web-Http-Errors",
"Web-Static-Content",
"Web-Digest-Auth",
"Web-Windows-Auth",
"Web-Mgmt-Console"
)

foreach ($Component in $RequiredWindowsComponents) {
    if (Get-WindowsFeature -Name $Component -ErrorAction SilentlyContinue) {
        Write-Host "✓ $Component is installed." -ForegroundColor Green
    } else {
        Write-Host "✗ $Component is NOT installed." -ForegroundColor Red
        $MissingComponents += $Component
    }
}
if ($MissingComponents) {
    Write-Host "The following required components are missing:" -ForegroundColor Red
    Write-Host "Remediation: Run following Command"
    write-host -ForegroundColor darkgray "Add-WindowsFeature Web-Server, Web-Http-Errors, Web-Static-Content, Web-Digest-Auth, Web-Windows-Auth, Web-Mgmt-Console, BranchCache"
    
}

Write-Host "=========================================================================" -ForegroundColor DarkGray
Write-Host "Confirm IIS MIME Types" -ForegroundColor Cyan
# Table of required MIME types for iPXE and related boot files
$RequiredMimeTypes = @(
[PSCustomObject]@{ Extension = ".efi";  MimeType = "application/octet-stream"; Description = "EFI loader files" },
[PSCustomObject]@{ Extension = ".com";  MimeType = "application/octet-stream"; Description = "BIOS boot loaders" },
[PSCustomObject]@{ Extension = ".n12";  MimeType = "application/octet-stream"; Description = "BIOS loaders without F12 key press" },
[PSCustomObject]@{ Extension = ".sdi";  MimeType = "application/octet-stream"; Description = "boot.sdi file" },
[PSCustomObject]@{ Extension = ".bcd";  MimeType = "application/octet-stream"; Description = "boot.bcd boot configuration files" },
[PSCustomObject]@{ Extension = ".";     MimeType = "application/octet-stream"; Description = "BCD file (with no extension)" },
[PSCustomObject]@{ Extension = ".wim";  MimeType = "application/octet-stream"; Description = "winpe images (optional)" },
[PSCustomObject]@{ Extension = ".pxe";  MimeType = "application/octet-stream"; Description = "iPXE BIOS loader files" },
[PSCustomObject]@{ Extension = ".kpxe"; MimeType = "application/octet-stream"; Description = "UNDIonly version of iPXE" },
[PSCustomObject]@{ Extension = ".iso";  MimeType = "application/octet-stream"; Description = ".iso file type" },
[PSCustomObject]@{ Extension = ".img";  MimeType = "application/octet-stream"; Description = ".img file type" },
[PSCustomObject]@{ Extension = ".ipxe"; MimeType = "text/plain";                Description = ".ipxe file" }
)



try {
    Import-Module WebAdministration -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}
catch {
    write-host "Catch block executed"
}

if (Get-Module -name WebAdministration) {
    $IISMimeTypes = Get-WebConfigurationProperty -Filter /system.webServer/staticContent/mimeMap -Name "fileExtension" -PSPath "IIS:\Sites\Default Web Site"
    # Loop through required MIME types and check if present in IIS
    foreach ($mime in $RequiredMimeTypes) {
        if ($IISMimeTypes.value -contains $mime.Extension) {
            Write-Host ("✓ IIS MIME type for {0} ({1}) is configured." -f $mime.Extension, $mime.Description) -ForegroundColor Green
        } else {
            Write-Host ("✗ IIS MIME type for {0} ({1}) is NOT configured." -f $mime.Extension, $mime.Description) -ForegroundColor Red
            Write-Host "Remediation: Run following Command" -ForegroundColor Yellow
            Write-Host ("New-WebMimeType -FileExtension '{0}' -MimeType '{1}' -PSPath 'IIS:\Sites\Default Web Site'" -f $mime.Extension, $mime.MimeType) -ForegroundColor DarkGray
            $IISMimeTypeUpdateRequired = $true
        }
    }
    if ($IISMimeTypeUpdateRequired) {
        write-host -ForegroundColor Magenta "Run this Script to enable MIME Types"
        write-Host -ForegroundColor DarkGray "https://github.com/materrill/miketerrill.net/blob/master/Software%20Install%20Scripts/Configure-IISMIMETypes.ps1"
    }
}
#Region Services
Write-Host "=========================================================================" -ForegroundColor DarkGray
Write-Host "Checking for Services..." -ForegroundColor Cyan
#Test Services if App Installed
#Test SQL Express
$SQLInstances = Get-SqlInstances
if ($SQLInstances.Count -eq 0) {
    Write-Host "No SQL Server instances found on this server." -ForegroundColor Red
    $Global:Installed_Microsoft_SQL_Server = $false
} else {
    $SQLServiceName = $SQLInstances.ServiceName
}

if (($Installed_Microsoft_SQL_Server) -and ($SQLServiceName)){
    $SQLService = Get-Service -Name $SQLServiceName
    if ($SQLService.Status -eq 'Running') {
        Write-Host "Microsoft SQL Server service is running." -ForegroundColor Green
        Write-Host "  Display Name: $($SQLService.DisplayName)" -ForegroundColor DarkGray
        Write-Host "  Service Name: $($SQLService.Name)" -ForegroundColor DarkGray
        Write-Host "  Start Type:   $($SQLService.StartType)" -ForegroundColor DarkGray
        $Global:SQLServiceRunning = $true
    }
    else {
        Write-Host "Microsoft SQL Server service is NOT running." -ForegroundColor Red
        Write-Host " Attempting to start service..." -ForegroundColor Yellow
        Start-Service -Name $SQLServiceName -ErrorAction SilentlyContinue
        if ($?) {
            Write-Host "Service started successfully." -ForegroundColor Green
        }
        else {
            Write-Host "Failed to start service." -ForegroundColor Red
        }
        $Global:SQLServiceRunning = $false
    }
}
#Test StifleR Service
if ($Installed_2Pint_Software_StifleR_Server){
    $StifleRService = Get-Service -Name '2Pint Software StifleR Server'
    if ($StifleRService.Status -eq 'Running') {
        Write-Host "2Pint StifleR Server service is running." -ForegroundColor Green
        Write-Host "  Display Name: $($StifleRService.DisplayName)" -ForegroundColor DarkGray
        Write-Host "  Service Name: $($StifleRService.Name)" -ForegroundColor DarkGray
        Write-Host "  Start Type:   $($StifleRService.StartType)" -ForegroundColor DarkGray
        $Global:StifleRServiceRunning = $true
    }
    else {
        Write-Host "2Pint StifleR Server service is NOT running." -ForegroundColor Red
        Write-Host " Attempting to start service..." -ForegroundColor Yellow
        Start-Service -Name '2Pint Software StifleR Server' -ErrorAction SilentlyContinue
        if ($?) {
            Write-Host "Service started successfully." -ForegroundColor Green
            Write-Host " Waiting for service to start additional processes..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
        else {
            Write-Host "Failed to start service." -ForegroundColor Red
        }
        $Global:StifleRServiceRunning = $false
    }
}
#Test DeployR Service
if ($Installed_2Pint_Software_DeployR){
    $DeployRService = Get-Service -Name '2Pint Software DeployR Service'
    if ($DeployRService.Status -eq 'Running') {
        Write-Host "2Pint DeployR service is running." -ForegroundColor Green
        Write-Host "  Display Name: $($DeployRService.DisplayName)" -ForegroundColor DarkGray
        Write-Host "  Service Name: $($DeployRService.Name)" -ForegroundColor DarkGray
        Write-Host "  Start Type:   $($DeployRService.StartType)" -ForegroundColor DarkGray
        $Global:DeployRServiceRunning = $true
    }
    else {
        Write-Host "2Pint DeployR service is NOT running." -ForegroundColor Red
        Write-Host " Attempting to start service..." -ForegroundColor Yellow
        Start-Service -Name '2Pint Software DeployR Service' -ErrorAction SilentlyContinue
        if ($?) {
            Write-Host "Service started successfully." -ForegroundColor Green
        }
        else {
            Write-Host "Failed to start service." -ForegroundColor Red
        }
        $Global:DeployRServiceRunning = $false
    }
}
#endRegion Services

#Confirm StifleR Registry Settings
if ($Installed_2Pint_Software_StifleR_Server){
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "Testing StifleR Registry Settings..." -ForegroundColor Cyan
    $StifleRRegPath = "HKLM:\SOFTWARE\2Pint Software\StifleR\Server\GeneralSettings"
    $StifleRRegData = Get-ItemProperty -Path $StifleRRegPath -ErrorAction SilentlyContinue
    
    #Note, this is no longer used in newer releases
    if ($StifleRRegData -and $StifleRRegData.DeployRUrl) {
        Write-Host "DeployR API URL: $($StifleRRegData.DeployRUrl)" -ForegroundColor Green
    }
    else {
        #Write-Host "DeployR API URL is NOT configured." -ForegroundColor Red
    }
    $StifleRCertThumbprint = $StifleRRegData.WSCertificateThumbprint
    Write-Host "StifleR Using Certificate with Thumbprint: $($StifleRCertThumbprint)" -ForegroundColor Cyan
    #Get Certificate from Local Machine Store that matches
    $CertThumbprint = Get-ChildItem -Path Cert:\LocalMachine\My  | Where-Object { $_.Thumbprint -match $StifleRCertThumbprint }
    if ($CertThumbprint) {
        Write-Host "Found certificate in local store: $($CertThumbprint.Thumbprint)" -ForegroundColor Green
        write-host " DNSNameList:    $($CertThumbprint.DNSNameList -join ', ')" -ForegroundColor DarkGray
        write-host " Subject:        $($CertThumbprint.Subject)" -ForegroundColor DarkGray
        write-host " Issuer:         $($CertThumbprint.Issuer)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "Certificate NOT found." -ForegroundColor Red
    }
    
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "Checking for StifleRDashboard Web Virtual Directory..." -ForegroundColor Cyan
    
    try {
        $vdir = Get-WebVirtualDirectory -Site "Default Web Site" -Name "StifleRDashboard" -ErrorAction SilentlyContinue
        if ($vdir) {
            Write-Host "✓ StifleRDashboard Web Virtual Directory exists in Default Web Site." -ForegroundColor Green
            Write-Host "  Physical Path: $($vdir.PhysicalPath)" -ForegroundColor DarkGray
        } else {
            Write-Host "✗ StifleRDashboard Web Virtual Directory is NOT present in Default Web Site." -ForegroundColor Red
            Write-Host "Remediation: Run the following command:" -ForegroundColor Yellow
            Write-Host "New-WebVirtualDirectory -Site 'Default Web Site' -Name 'StifleRDashboard' -PhysicalPath 'C:\Program Files\2Pint Software\StifleR Dashboards\Dashboard Files'" -ForegroundColor DarkGray
            $IISVirtualDirMissing = $true
        }
    } catch {
        Write-Host "Error checking for StifleRDashboard Web Virtual Directory: $_" -ForegroundColor Red
    }
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    
    Write-Host "Testing Dashboard Registry Settings for URLs" -ForegroundColor Cyan
    $DashReg = "HKLM:\SOFTWARE\2Pint Software\StifleR\Dashboard"
    $DashRegData = Get-ItemProperty -Path $DashReg -ErrorAction SilentlyContinue
    
    if ($DashRegData -and $DashRegData.HubUrl) {
        if ($($DashRegData.HubUrl) -match "localhost") {
            Write-Host " Hub URL is configured to use localhost." -ForegroundColor Red
        }
        else{
            Write-Host " Hub URL: $($DashRegData.HubUrl)" -ForegroundColor Green
        }
    }
    else {
        Write-Host " Hub URL is NOT configured." -ForegroundColor Red
    }
    
    if ($DashRegData -and $DashRegData.ServiceUrl) {
        if ($($DashRegData.ServiceUrl) -match "localhost") {
            Write-Host " Service URL is configured to use localhost." -ForegroundColor Red
        }
        else{
            Write-Host " Service URL: $($DashRegData.ServiceUrl)" -ForegroundColor Green
        }
    }
    else {
        Write-Host " Service URL is NOT configured." -ForegroundColor Red
    }
    Write-Host "Testing Dashboard Config Settings for URLs" -ForegroundColor Cyan
    if (Test-Path -Path "C:\Program Files\2Pint Software\StifleR Dashboards\Dashboard Files\assets\config\server.json") {
        Write-Host "  Server configuration file exists." -ForegroundColor Green
        $ServerConfigJSON = Get-Content -Path "C:\Program Files\2Pint Software\StifleR Dashboards\Dashboard Files\assets\config\server.json" -Raw | ConvertFrom-Json
        if ($ServerConfigJSON -and $ServerConfigJSON.server.hub) {
            if ($($ServerConfigJSON.server.hub) -match "localhost") {
                Write-Host "Hub URL is configured to use localhost." -ForegroundColor Red
            }
            else{
                Write-Host " Hub URL: $($ServerConfigJSON.server.hub)" -ForegroundColor Green
            }
        }
        else {
            Write-Host " Hub URL is NOT configured." -ForegroundColor Red
        }
        
        if ($ServerConfigJSON -and $ServerConfigJSON.server.controller) {
            if ($($ServerConfigJSON.server.controller) -match "localhost") {
                Write-Host " Service URL is configured to use localhost." -ForegroundColor Red
            }
            else{
                Write-Host " Service URL: $($ServerConfigJSON.server.controller)" -ForegroundColor Green
            }
        }
        else {
            Write-Host " Service URL is NOT configured." -ForegroundColor Red
        }
    }
    else {
        Write-Host " Server configuration file is missing." -ForegroundColor Red
    }
    #Check to ensure Registry Values match Config Values
    if ($DashRegData -and $ServerConfigJSON) {
        if ($DashRegData.HubUrl -ne $ServerConfigJSON.server.hub) {
            Write-Host " Hub URL in Registry does not match Config file." -ForegroundColor Red
        }
        if ($DashRegData.ServiceUrl -ne $ServerConfigJSON.server.controller) {
            Write-Host " Service URL in Registry does not match Config file." -ForegroundColor Red
        }
    }
}
Start-Sleep -Seconds 2

#Confirm DeployR Registry Settings
if ($Installed_2Pint_Software_DeployR){
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    
    $RegPath = "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"
    $DeployRRegData = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
    
    if ($DeployRRegData -and $DeployRRegData.ConnectionString) {
        $DeployRegDataSQLServerInstanceString = (($DeployRRegData.ConnectionString).Split(';') | Where-Object { $_ -match '^Server=' }).Split('\')[1]
        if ($DeployRegDataSQLServerInstanceString -eq $SQLInstances.InstanceName) {
            Write-Host "DeployR SQL Server Instance in Registry matches detected SQL Instance: $($SQLInstances.InstanceName)" -ForegroundColor Green
        }
        else {
            Write-Host "!!!!!=============================================================================!!!!!" -ForegroundColor Red
            Write-Host "     DeployR SQL Server Instance in Registry does NOT match detected SQL Instance." -ForegroundColor Red
            Write-Host "      Registry Instance: $($DeployRegDataSQLServerInstanceString)" -ForegroundColor DarkGray
            Write-Host "      Detected Instance: $($SQLInstances.InstanceName)" -ForegroundColor DarkGray
            Write-Host "!!!!!=============================================================================!!!!!" -ForegroundColor Red
        }
        Write-Host "Testing DeployR SQL Connection string from Registry... " -ForegroundColor Cyan
        write-host " $($DeployRRegData.ConnectionString)"
        Test-SQLConnection -ConnectionString $DeployRRegData.ConnectionString
    }
    #Check SQL Principal Rights for NT AUTHORITY\SYSTEM
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "Testing NT AUTHORITY\SYSTEM permissions on local SQL Express..." -ForegroundColor Cyan
    $out = Test-SystemSqlPermissions -Instance $SQLInstances.ConnectionString
    if ($out.Error) {
        Write-Host "Error: $($out.Error)" -ForegroundColor Red
        Write-Host "Please Manually Check Permissions on Database Instances" -ForegroundColor Cyan
        Write-Host "Would you like to try to automatically add SYSTEM to the Instance $($SQLInstances.InstanceName)  (Y/N): " -ForegroundColor Yellow -NoNewline
        $response = Read-Host
        if ($response -eq 'Y' -or $response -eq 'y') {
            try {
                $SetSQLPerm = Set-SqlServerPermissions -InstanceName $($SQLInstances.InstanceName)
            }
            catch {
                Write-Host "Failed to set permissions: $_" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "Instance: $($out.Instance)" -ForegroundColor Green
        Write-Host "  LoginExists: $($out.LoginExists)" -ForegroundColor ($(if ($out.LoginExists) {'Green'} else {'Red'}))
        Write-Host "  IsSysadmin : $($out.IsSysadmin)" -ForegroundColor ($(if ($out.IsSysadmin) {'Green'} else {'Yellow'}))
        Write-Host "  IsDbCreator: $($out.IsDbCreator)" -ForegroundColor ($(if ($out.IsDbCreator) {'Green'} else {'Yellow'}))
    }
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "Checking NT AUTHORITY\SYSTEM db_owner permissions for all databases..." -ForegroundColor Cyan
    $dbOut = Test-SqlDatabases -Instance $SQLInstances.ConnectionString
    if ($dbOut.Error) {
        Write-Host "Error: Cannot check permissions - failed to get database list" -ForegroundColor Red
    }
    elseif ($dbOut.Databases.Count -eq 0) {
        Write-Host "No user databases found to check" -ForegroundColor Yellow
    }
    else {
        # Extract database names and check permissions
        $dbNames = $dbOut.Databases | ForEach-Object { $_.Name }
        $dbOwnerOut = Test-SystemDatabaseOwnership -Instance $SQLInstances.ConnectionString -DatabaseNames $dbNames
        
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
    
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "Testing DeployR Certificate..." -ForegroundColor Cyan
    #Test Certificate
    $CertThumbprintRegValue = $DeployRRegData.CertificateThumbprint
    Write-Host "DeployR Using Certificate with Thumbprint: $($CertThumbprintRegValue)" -ForegroundColor Cyan
    #Get Certificate from Local Machine Store that matches
    $CertThumbprint = Get-ChildItem -Path Cert:\LocalMachine\My  | Where-Object { $_.Thumbprint -match $CertThumbprintRegValue }
    if ($CertThumbprint) {
        Write-Host "Found certificate in local store: $($CertThumbprint.Thumbprint)" -ForegroundColor Green
    }
    else {
        Write-Host "Certificate NOT found." -ForegroundColor Red
    }
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    #Test StifleR Server URL
    Write-Host "Testing Network Connections..." -ForegroundColor Cyan
    #StifleR Server URL = $DeployRRegData.StifleRServerApiUrl without Port Number
    $StifleRServerURL = $DeployRRegData.StifleRServerApiUrl
    $StifleRServerURL = $StifleRServerURL.Split(':')[0..1] -join ':'
    $StifleRServerName = $StifleRServerURL.Split('/')[2]
    $DeployRURL = $DeployRRegData.ClientURL
    $DeployRURL = $DeployRURL.Split(':')[0..1] -join ':'
    $DeployRServerName = $DeployRURL.Split('/')[2]
    
    
    
    Write-Host "Testing StifleR Server URL... $($StifleRServerURL)" -ForegroundColor Cyan
    $StifleRTest = Test-Url -Url $StifleRServerURL
    if ($StifleRTest) {
        Write-Host "StifleR Server URL is accessible." -ForegroundColor Green
        $Test443 = Test-NetConnection -ComputerName $StifleRServerName -Port 443
        if ($Test443) {
            Write-Host "StifleR Server Port 443 is accessible." -ForegroundColor Green
        }
        $Test9000 = Test-NetConnection -ComputerName $StifleRServerName -Port 9000
        if ($Test9000) {
            Write-Host "StifleR Server Port 9000 is accessible." -ForegroundColor Green
        }
    }
    else {
        Write-Host "StifleR Server URL is NOT accessible." -ForegroundColor Red
    }
    Write-Host "Testing DeployR Server URL... $($DeployRURL)" -ForegroundColor Cyan
    $DeployRTest = Test-Url -Url $DeployRURL
    if ($DeployRTest) {
        
        
        
        $Test7281 = Test-NetConnection -ComputerName $DeployRServerName -Port 7281
        if ($Test7281) {
            Write-Host "DeployR Server Port 7281 is accessible." -ForegroundColor Green
        }
        $Test7282 = Test-NetConnection -ComputerName $DeployRServerName -Port 7282
        if ($Test7282) {
            Write-Host "DeployR Server Port 7282 is accessible." -ForegroundColor Green
        }
    }
    else {
        Write-Host "DeployR Server URL is NOT accessible." -ForegroundColor Red
    }
    
}
Write-Host "=========================================================================" -ForegroundColor DarkGray
write-host "Checking Certificate... on Ports 443 & 9000" -ForegroundColor Cyan
# Get the certificate hash from the HTTP.SYS binding for port 443
$certHash = netsh http show sslcert ipport=0.0.0.0:443 | Select-String "Certificate Hash" | ForEach-Object { ($_ -split ": ")[1].Trim() }

if ($certHash) {
    Write-Host  "Certificate Thumbprint for HTTPS (port 443): $certHash" -ForegroundColor Green
    if ($certHash -eq $CertThumbprintRegValue) {
        Write-Host "The certificate hash matches the DeployR configuration." -ForegroundColor Green
    }
    else {
        Write-Host "The certificate hash does NOT match the DeployR configuration." -ForegroundColor Red
    }
} else {
    Write-Host  "No SSL binding found for port 443. Trying all IPs..." -ForegroundColor Yellow
    # Fallback: Scan common IPs (adjust as needed)
    $ips = @("0.0.0.0", "*")  # Add specific IPs if known, e.g., "192.168.1.100"
    $found = $false
    foreach ($ip in $ips) {
        $hash = netsh http show sslcert ipport="$ip`:443" | Select-String "Certificate Hash" | ForEach-Object { ($_ -split ": ")[1].Trim() }
        if ($hash) {
            Write-Host "Certificate Thumbprint for HTTPS (port 443) on $ip`: $hash" -ForegroundColor Yellow
            $found = $true
            break
        }
    }
    if (-not $found) { Write-Host "No binding found." -ForegroundColor Red }
}
$certHash = netsh http show sslcert ipport=0.0.0.0:9000 | Select-String "Certificate Hash" | ForEach-Object { ($_ -split ": ")[1].Trim() }

if ($certHash) {
    Write-Host  "Certificate Thumbprint for HTTPS (port 9000): $certHash" -ForegroundColor Green
    if ($certHash -eq $CertThumbprintRegValue) {
        Write-Host "The certificate hash matches the DeployR configuration." -ForegroundColor Green
    }
    else {
        Write-Host "The certificate hash does NOT match the DeployR configuration." -ForegroundColor Red
    }
} else {
    Write-Host  "No SSL binding found for port 443. Trying all IPs..." -ForegroundColor Yellow
    # Fallback: Scan common IPs (adjust as needed)
    $ips = @("0.0.0.0", "*")  # Add specific IPs if known, e.g., "192.168.1.100"
    $found = $false
    foreach ($ip in $ips) {
        $hash = netsh http show sslcert ipport="$ip`:443" | Select-String "Certificate Hash" | ForEach-Object { ($_ -split ": ")[1].Trim() }
        if ($hash) {
            Write-Host "Certificate Thumbprint for HTTPS (port 443) on $ip`: $hash" -ForegroundColor Yellow
            $found = $true
            break
        }
    }
    if (-not $found) { Write-Host "No binding found." -ForegroundColor Red }
}
#Testing Firewall Rules:

Write-Host "=========================================================================" -ForegroundColor DarkGray
write-host "Checking Firewall Rules to ensure Ports are Open" -ForegroundColor Cyan
$Ports = Get-NetFirewallPortFilter
$InboundRules = Get-NetFirewallRule -Direction Inbound
foreach ($FirewallRule in $FirewallRules){
    Write-Host "Checking Firewall Rule: $($FirewallRule.DisplayName)" -ForegroundColor Yellow
    $RulePorts = $Ports | Where-Object { $_.LocalPort -eq $FirewallRule.Port -and $_.Protocol -eq $FirewallRule.Protocol } | Select-Object -first 1
    if ($RulePorts){
        foreach ($Port in $RulePorts){
            $NetFirewallRule = $InboundRules | Where-Object { $_.InstanceID -eq $Port.InstanceID }
            Write-Host " Found Firewall Rule: $($NetFirewallRule.DisplayName)" -ForegroundColor Green
            Write-Host "  Enabled: $($NetFirewallRule.Enabled) | Action:  $($NetFirewallRule.Action) | Profile: $($NetFirewallRule.Profile)" -ForegroundColor DarkGray
            Write-Host "  Port: $($Port.LocalPort) | Protocol: $($Port.Protocol)" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "No matching ports found for Firewall Rule: $($FirewallRule.DisplayName)" -ForegroundColor Red
    }
}

if ($Installed_2Pint_Software_StifleR_WmiAgent) {
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    write-host "Checking for StifleR Infrastructure Approval for DeployR" -ForegroundColor Cyan
    $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
    try {
        if ($InfraServices) {
            Write-Host "StifleR Infrastructure Services found." -ForegroundColor Green
        } else {
            Write-Host "No StifleR Infrastructure Services found." -ForegroundColor Red
        }
    } catch {
        Write-Host "Failed to retrieve StifleR Infrastructure Services." -ForegroundColor Red
        write-host "Waiting for a minute and going to try again..."
        Start-Sleep -seconds 10
        write-host " 50..."
        Start-Sleep -seconds 10
        write-Host " 40..."
        Start-Sleep -seconds 10
        write-host " 30..."
        Start-Sleep -seconds 10
        write-host " 20..."
        Start-Sleep -seconds 10
        write-host " 10..."
        Start-Sleep -seconds 10
        try {
            $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "Error occurred while retrieving StifleR Infrastructure Services." -ForegroundColor Red
        }
    }
    if (!$InfraServices) {
        
        Write-Host "Sometimes if the service just started, this can take a bit"
        write-host "Waiting for a minute and going to try again..."
        Start-Sleep -seconds 10
        $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
        write-host " 50..."
        Start-Sleep -seconds 10
        $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
        write-Host " 40..."
        Start-Sleep -seconds 10
        $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
        write-host " 30..."
        Start-Sleep -seconds 10
        $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
        write-host " 20..."
        Start-Sleep -seconds 10
        $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
        write-host " 10..."
        Start-Sleep -seconds 10
        $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
    }
    if ($InfraServices) {
        $DeployR = $InfraServices | Where-Object {$_.Type -eq "DeployR"}
        if ($DeployR){
            Write-Host "StifleR Infrastructure for DeployR found." -ForegroundColor Green
            if ($DeployR.Status -eq "IsApproved") {
                Write-Host "DeployR Status: Approved" -ForegroundColor Green
            } else {
                Write-Host "DeployR Status: NOT Approved" -ForegroundColor Red
            }
        }
        else{
            Write-Host "No StifleR Infrastructure for DeployR found." -ForegroundColor Red
        }
    } else {
        Write-Host "StifleR Infrastructure Services are NOT available." -ForegroundColor Red
    }
}
#Remediation 
#prompt user to do installs
Write-Host "=========================================================================" -ForegroundColor DarkGray
if ($MissingComponents) {
    Write-Host "Would you like to install the missing Windows Features now? (Y/N): " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    if ($response -eq 'Y' -or $response -eq 'y') {
        Write-Host "Remediation: Run the following command to install missing Windows Features:" -ForegroundColor Yellow
        Write-Host "Add-WindowsFeature $($MissingComponents -join ', ')" -ForegroundColor DarkGray
    }
}
if ($IISVirtualDirMissing) {
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "Running Remediation for StifleRDashboard virtual directory"
    if (Test-Path -path "C:\Program Files\2Pint Software\StifleR Dashboards\Dashboard Files"){
        Write-Host "✓ StifleRDashboard directory exists." -ForegroundColor Green
    } else {
        Write-Host "✗ StifleRDashboard directory is missing." -ForegroundColor Red
    }
    Write-Host "Would you like to create the StifleRDashboard virtual directory now? (Y/N): " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    if ($response -eq 'Y' -or $response -eq 'y') {
        try {
            New-WebVirtualDirectory -Site 'Default Web Site' -Name 'StifleRDashboard' -PhysicalPath 'C:\Program Files\2Pint Software\StifleR Dashboards\Dashboard Files' -ErrorAction Stop
            Write-Host "✓ StifleRDashboard virtual directory created successfully." -ForegroundColor Green
        } catch {
            Write-Host "✗ Failed to create virtual directory: $_" -ForegroundColor Red
            Write-Host "Please run the command manually with elevated permissions." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Skipping virtual directory creation." -ForegroundColor DarkGray
    }
}
if ($IISMimeTypeUpdateRequired) {
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "Would you like to add the missing IIS MIME types now? (Y/N): " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    if ($response -eq 'Y' -or $response -eq 'y') {
        Write-Host "Adding missing IIS MIME types..." -ForegroundColor Yellow
        #Set the MIME types for the iPXE boot files, etc. 
        Import-Module WebAdministration
        #EFI loader files  
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.efi';mimeType='application/octet-stream'}  
        #BIOS boot loaders  
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.com';mimeType='application/octet-stream'}  
        #BIOS loaders without F12 key press  
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.n12';mimeType='application/octet-stream'}  
        #For the boot.sdi file  
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.sdi';mimeType='application/octet-stream'}  
        #For the boot.bcd boot configuration files  & BCD file (with no extension)
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.bcd';mimeType='application/octet-stream'}
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.';mimeType='application/octet-stream'}   
        #For the winpe images itself (already added on newer/patched versions of Windows Server
        #Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.wim';mimeType='application/octet-stream'}  
        #for the iPXE BIOS loader files  
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.pxe';mimeType='application/octet-stream'}  
        #For the UNDIonly version of iPXE  
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.kpxe';mimeType='application/octet-stream'}  
        #For the .iso file type
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.iso';mimeType='application/octet-stream'}  
        #For the .img file type
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.img';mimeType='application/octet-stream'}  
        #For the .ipxe file 
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.ipxe';mimeType='text/plain'}
        Write-Host "✓ Missing IIS MIME types added successfully." -ForegroundColor Green
    }
}

Stop-Transcript