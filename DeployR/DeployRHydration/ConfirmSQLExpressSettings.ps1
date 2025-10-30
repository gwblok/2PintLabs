

function Get-SqlPrincipalRights {
    <#
.SYNOPSIS
    Get the server-role membership for a SQL Server principal.

.DESCRIPTION
    Get-SqlPrincipalRights connects to a SQL Server instance (Invoke-Sqlcmd if available, otherwise sqlcmd)
    and returns a PSCustomObject describing whether the specified principal exists and whether it is a member
    of the server roles 'sysadmin' and 'dbcreator'. Defaults to checking the local SQLEXPRESS instance and
    the principal 'NT AUTHORITY\SYSTEM'.

.PARAMETER ServerInstance
    SQL Server instance name to query (defaults to local COMPUTERNAME\SQLEXPRESS)

.PARAMETER Username
    The server principal name to check (defaults to 'NT AUTHORITY\SYSTEM')

.PARAMETER SqlCmdPath
    Path to sqlcmd.exe for fallback usage.

.PARAMETER Diagnostic
    Print diagnostic information (whoami and raw results) useful for troubleshooting.
#>

    [CmdletBinding()]
    param(
        [string]$ServerInstance = "$env:COMPUTERNAME\SQLEXPRESS",
        [string]$Username = 'NT AUTHORITY\SYSTEM',
        [string]$SqlCmdPath = 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd',
        [switch]$Diagnostic
    )

    # Escape single quotes in the username for safely embedding in SQL
    $escapedUser = $Username.Replace("'", "''")

    $query = @"
SET NOCOUNT ON;
SELECT 'LoginExists=' + CAST(CASE WHEN EXISTS(SELECT 1 FROM sys.server_principals WHERE name = '$escapedUser') THEN 1 ELSE 0 END AS VARCHAR(5)) AS KVP;
SELECT 'IsSrvRoleMember_sysadmin=' + CAST(ISNULL(CAST(IS_SRVROLEMEMBER('sysadmin','$escapedUser') AS INT),0) AS VARCHAR(5)) AS KVP;
SELECT 'IsSrvRoleMember_dbcreator=' + CAST(ISNULL(CAST(IS_SRVROLEMEMBER('dbcreator','$escapedUser') AS INT),0) AS VARCHAR(5)) AS KVP;
SELECT 'Role_sysadmin_exists=' + CAST(CASE WHEN EXISTS(
    SELECT 1 FROM sys.server_role_members rm
    JOIN sys.server_principals r ON rm.role_principal_id = r.principal_id
    JOIN sys.server_principals m ON rm.member_principal_id = m.principal_id
    WHERE r.name = 'sysadmin' AND m.name = '$escapedUser'
) THEN 1 ELSE 0 END AS VARCHAR(5)) AS KVP;
SELECT 'Role_dbcreator_exists=' + CAST(CASE WHEN EXISTS(
    SELECT 1 FROM sys.server_role_members rm
    JOIN sys.server_principals r ON rm.role_principal_id = r.principal_id
    JOIN sys.server_principals m ON rm.member_principal_id = m.principal_id
    WHERE r.name = 'dbcreator' AND m.name = '$escapedUser'
) THEN 1 ELSE 0 END AS VARCHAR(5)) AS KVP;
SELECT 'ServerName=' + ISNULL(CAST(@@SERVERNAME AS VARCHAR(200)), '') AS KVP;
SELECT 'ProductVersion=' + ISNULL(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(100)), '') AS KVP;
"@

    if ($Diagnostic) { Write-Host "[Diagnostic] Querying $ServerInstance for principal '$Username'" }

    # Try Invoke-Sqlcmd first
    if (Get-Command -Name Invoke-Sqlcmd -ErrorAction SilentlyContinue) {
        try {
            $rows = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $query -QueryTimeout 30 -ErrorAction Stop
            if ($Diagnostic) {
                Write-Host "[Diagnostic] whoami: $(whoami)"
                Write-Host "[Diagnostic] raw Invoke-Sqlcmd rows:"; $rows | Format-Table -AutoSize
            }

            # Parse KVP rows
            $map = @{}
            foreach ($r in $rows) {
                # prefer a property named KVP, otherwise find any string property containing '='
                $kvVal = $null
                if ($r.PSObject.Properties['KVP']) { $kvVal = $r.KVP }
                else {
                    foreach ($p in $r.PSObject.Properties) {
                        if ($p.Value -and ($p.Value -is [string]) -and ($p.Value -match '=')) { $kvVal = $p.Value; break }
                    }
                }
                if ($kvVal) {
                    $parts = $kvVal -split '=',2
                    $map[$parts[0]] = $parts[1]
                }
            }

            # Prefer the explicit role existence checks if present, otherwise fall back to IS_SRVROLEMEMBER values
            $isSysadminVal = 0
            $isDbCreatorVal = 0
            if ($map.ContainsKey('Role_sysadmin_exists')) { $isSysadminVal = ([int]$map['Role_sysadmin_exists']) }
            elseif ($map.ContainsKey('IsSrvRoleMember_sysadmin')) { $isSysadminVal = ([int]$map['IsSrvRoleMember_sysadmin']) }
            if ($map.ContainsKey('Role_dbcreator_exists')) { $isDbCreatorVal = ([int]$map['Role_dbcreator_exists']) }
            elseif ($map.ContainsKey('IsSrvRoleMember_dbcreator')) { $isDbCreatorVal = ([int]$map['IsSrvRoleMember_dbcreator']) }

            return [PSCustomObject]@{
                Username         = $Username
                ServerInstance   = $ServerInstance
                LoginExists      = if ($map['LoginExists'] -match '^[0-9]+$') { [int]$map['LoginExists'] } else { 0 }
                PrincipalId      = $null
                SidHex           = $null
                IsSysadmin       = $isSysadminVal
                IsDbCreator      = $isDbCreatorVal
                RawMap           = $map
            }
        } catch {
            if ($Diagnostic) { Write-Warning "[Diagnostic] Invoke-Sqlcmd failed: $($_.Exception.Message)" }
        }
    }

    # Fallback to sqlcmd - write temp file
    $temp = [System.IO.Path]::Combine($env:TEMP, ("GetSqlPrincipalRights_{0}.sql" -f ([guid]::NewGuid())))
    $query | Out-File -FilePath $temp -Encoding ASCII -Force
    try {
        $args = @('-S', $ServerInstance, '-i', $temp, '-h', '-1', '-W')
        $out = & $SqlCmdPath @args 2>&1
        $exit = $LASTEXITCODE
        if ($exit -ne 0) { throw "sqlcmd failed (exit $exit): $($out -join "`n")" }

        # Parse sqlcmd textual output: we look for principal row by name and KVP lines
        $loginExists = 0
        $isSysadmin = 0
        $isDbCreator = 0
        $principalId = $null
        $sidHex = $null

        foreach ($line in $out) {
            $l = $line.Trim()
            if (-not $l) { continue }
            # KVP lines like IsSysadmin=1
            if ($l -match '=') {
                $parts = $l -split '=',2
                switch ($parts[0]) {
                    'IsSysadmin' { if ($parts[1] -match '^[0-9]+$') { $isSysadmin = [int]$parts[1] } }
                    'IsDbCreator' { if ($parts[1] -match '^[0-9]+$') { $isDbCreator = [int]$parts[1] } }
                    'SystemLoginExists' { if ($parts[1] -match '^[0-9]+$') { $loginExists = [int]$parts[1] } }
                }
                continue
            }
            # Principal row: look for username in the line
            if ($l -like "*$Username*") {
                $loginExists = 1
                # try to extract principal_id and sid hex if present (best-effort)
                $cols = ($l -split '\s+') | Where-Object { $_ -ne '' }
                if ($cols.Count -ge 1) { $principalId = $cols[0] }
                if ($cols.Count -ge 4) { $sidHex = $cols[3] }
            }
            # Role lines: 'sysadmin    NT AUTHORITY\SYSTEM'
            if ($l -match '^(\S+)\s+(.+)$') {
                $rname = $matches[1]
                $mname = $matches[2]
                if ($mname -eq $Username) {
                    if ($rname -eq 'sysadmin') { $isSysadmin = 1 }
                    if ($rname -eq 'dbcreator') { $isDbCreator = 1 }
                }
            }
        }

        return [PSCustomObject]@{
            Username         = $Username
            ServerInstance   = $ServerInstance
            LoginExists      = $loginExists
            PrincipalId      = $principalId
            SidHex           = $sidHex
            IsSysadmin       = $isSysadmin
            IsDbCreator      = $isDbCreator
        }
    } finally {
        if (Test-Path $temp) { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
    }
}

