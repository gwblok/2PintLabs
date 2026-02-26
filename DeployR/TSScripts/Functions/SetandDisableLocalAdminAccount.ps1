function Set-LocalAdministratorAccount {
<#
.SYNOPSIS
    Sets the password for the built-in local Administrator account and optionally disables it.

.DESCRIPTION
    This function sets a password for the built-in local Administrator account (SID ending in -500).
    You can provide your own password or have it generate a strong random password.
    Optionally, you can disable the account after setting the password.

.PARAMETER Password
    The password to set for the Administrator account. If not provided, a random password will be generated.

.PARAMETER Length
    The length of the randomly generated password if no password is provided. Default is 24 characters.

.PARAMETER DisableAccount
    If specified, the Administrator account will be disabled after setting the password. Default is false.

.EXAMPLE
    Set-LocalAdministratorAccount
    Generates a random 24-character password and sets it for the Administrator account (account remains enabled).

.EXAMPLE
    Set-LocalAdministratorAccount -Password "P@ssw0rd"
    Sets the Administrator password to "P@ssw0rd" (account remains enabled).

.EXAMPLE
    Set-LocalAdministratorAccount -DisableAccount
    Generates a random password, sets it, and disables the Administrator account.

.EXAMPLE
    Set-LocalAdministratorAccount -Password "MyCustomP@ss123!" -DisableAccount
    Sets a custom password and disables the Administrator account.

.NOTES
    Author: Gary Blok
    Date: November 5, 2025
    Requires: Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Password,
    
    [Parameter(Mandatory=$false)]
    [int]$Length = 24,
    
    [Parameter(Mandatory=$false)]
    [switch]$DisableAccount
)

function New-RandomPassword {
    param([int]$Length = 24)

    $upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $lower = 'abcdefghijklmnopqrstuvwxyz'
    $digits = '0123456789'
    $special = '!@#$%^&*()-_=+[]{};:,.<>?'
    $all = $upper + $lower + $digits + $special

    if ($Length -lt 8) { throw "Password length must be at least 8." }

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    # ensure at least one of each required class
    $passwordChars = @()
    $passwordChars += $upper[(Get-Random -Maximum $upper.Length)]
    $passwordChars += $lower[(Get-Random -Maximum $lower.Length)]
    $passwordChars += $digits[(Get-Random -Maximum $digits.Length)]
    $passwordChars += $special[(Get-Random -Maximum $special.Length)]

    for ($i = $passwordChars.Count; $i -lt $Length; $i++) {
        $byte = New-Object 'System.Byte[]' (1)
        $rng.GetBytes($byte)
        $idx = $byte[0] % $all.Length
        $passwordChars += $all[$idx]
    }

    # shuffle
    $shuffled = ($passwordChars | Get-Random -Count $passwordChars.Count) -join ''
    return $shuffled
}

# require elevated
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This function must be run as Administrator."
    return
}

try {
    # Use provided password or generate a random one
    if ([string]::IsNullOrWhiteSpace($Password)) {
        $Password = New-RandomPassword -Length $Length
        $UsingGenerated = $true
        Write-Host "Generated random password (length $Length)" -ForegroundColor Cyan
    } else {
        Write-Host "Using provided password" -ForegroundColor Cyan
    }

    # find built-in Administrator account (SID ends with -500) even if renamed
    if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
        $admin = Get-LocalUser | Where-Object { $_.SID -and $_.SID.Value.EndsWith('-500') }
        if (-not $admin) { throw "Built-in Administrator account not found." }

        $secure = ConvertTo-SecureString $Password -AsPlainText -Force
        Set-LocalUser -Name $admin.Name -Password $secure -ErrorAction Stop
        Write-Host "✓ Password set for account: $($admin.Name)" -ForegroundColor Green
        
        if ($DisableAccount) {
            Disable-LocalUser -Name $admin.Name -ErrorAction Stop
            Write-Host "✓ Account has been disabled" -ForegroundColor Green
        } else {
            Write-Host "ℹ Account remains enabled" -ForegroundColor Yellow
        }

        Write-Host "`nAdministrator account name: $($admin.Name)" -ForegroundColor White
        if ($UsingGenerated) {
            Write-Host "Password: $Password" -ForegroundColor White
        }
    }
    else {
        # fallback for older systems without LocalAccounts module
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $adminAccount = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount=True AND SID LIKE '%-500'" -ErrorAction Stop | Select-Object -First 1
        }
        else {
            $adminAccount = Get-WmiObject -Class Win32_UserAccount -Filter "LocalAccount=True AND SID LIKE '%-500'" -ErrorAction Stop | Select-Object -First 1
        }

        $adminName = $adminAccount.Name
        if (-not $adminName) { throw "Built-in Administrator account not found via CIM/WMI." }

        net user "$adminName" "$Password" /Y | Out-Null
        Write-Host "✓ Password set for account: $adminName" -ForegroundColor Green
        
        if ($DisableAccount) {
            net user "$adminName" /active:no | Out-Null
            Write-Host "✓ Account has been disabled" -ForegroundColor Green
        } else {
            Write-Host "ℹ Account remains enabled" -ForegroundColor Yellow
        }

        Write-Host "`nAdministrator account name: $adminName" -ForegroundColor White
        if ($UsingGenerated) {
            Write-Host "Password: $Password" -ForegroundColor White
        }
    }
}
catch {
    Write-Error "Failed: $_"
    return
}
} # End of Set-LocalAdministratorAccount function

# Call the function with default password
Set-LocalAdministratorAccount -Password "P@ssw0rd"