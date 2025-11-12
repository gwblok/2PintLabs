<#
.SYNOPSIS
Set the built-in local Administrator account password.

.DESCRIPTION
Set-LocalAdministratorPassword sets the password of the built-in local Administrator account.
It prefers the LocalAccounts module (Get-LocalUser/Set-LocalUser). If that's unavailable it falls
back to using the local "net user" command discovered via the Win32_UserAccount SID (RID -500).

.PARAMETER NewPassword
The new password. Accepts a SecureString or a plain string.

.EXAMPLE
# Provide a plain text password (script must run elevated)
Set-LocalAdministratorPassword -NewPassword 'P@ssw0rd!'

.EXAMPLE
# Provide a SecureString
$sec = Read-Host -AsSecureString "Enter password"
Set-LocalAdministratorPassword -NewPassword $sec
#>
Import-Module microsoft.powershell.localaccounts -UseWindowsPowerShell

#Pull Vars from TS:
try {
    Import-Module DeployR.Utility
}
catch {}
# Get the provided variables
if (Get-Module -name "DeployR.Utility"){
    $LocalAdminPass = ${TSEnv:LocalAdminPass}
}
else{
    $LocalAdminPass = "P@ssw0rd"
}
if ($env:SystemDrive -eq "X:"){
    Write-Host "Running in WinPE environment, Runs only in Full OS"
    exit 0
}

function Set-LocalAdministratorPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [Object]$NewPassword
    )

    # Require elevation
    $isElevated = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isElevated) {
        throw "This function must be run with Administrator privileges."
    }

    # Convert to SecureString
    if ($NewPassword -is [System.Security.SecureString]) {
        $secure = $NewPassword
    } elseif ($NewPassword -is [string]) {
        $secure = ConvertTo-SecureString $NewPassword -AsPlainText -Force
    } else {
        throw "Parameter NewPassword must be a string or SecureString."
    }

    # Try modern LocalAccounts approach first
    try {
        $admin = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -match '-500$' } | Select-Object -First 1
    } catch {
        $admin = $null
    }

    if ($admin) {
        try {
            Set-LocalUser -Name $admin.Name -Password $secure -ErrorAction Stop
            return $true
        } catch {
            throw "Failed to set password via Set-LocalUser: $($_.Exception.Message)"
        }
    }

    # Fallback: locate built-in admin via Win32_UserAccount (SID ends with -500)
    try {
        $wmiAdmin = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount=True" -ErrorAction Stop |
                    Where-Object { $_.SID -match '-500$' } | Select-Object -First 1
    } catch {
        $wmiAdmin = $null
    }

    if (-not $wmiAdmin) {
        throw "Could not locate the built-in Administrator account on this system."
    }

    $acctName = $wmiAdmin.Name

    # Prepare plaintext password for net user if necessary
    $plain = $null
    $secureHandled = $false
    if ($NewPassword -is [System.Security.SecureString]) {
        # Convert SecureString to plain temporarily (and zero BSTR afterwards)
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($NewPassword)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        $secureHandled = $true
    } else {
        $plain = [string]$NewPassword
    }

    if (-not $plain) {
        throw "Failed to obtain plaintext password for fallback method."
    }

    # Use net user command to change the local account password
    & net user $acctName $plain > $null 2>&1
    $rc = $LASTEXITCODE

    # Attempt to clear plaintext variable
    if ($secureHandled) {
        $plain = $null
    }

    if ($rc -eq 0) {
        return $true
    } else {
        throw "Failed to set password using 'net user'. Exit code: $rc"
    }
}

$LocalAdminPassSS = ConvertTo-SecureString -String $LocalAdminPass -AsPlainText -Force
Set-LocalAdministratorPassword -NewPassword $LocalAdminPassSS