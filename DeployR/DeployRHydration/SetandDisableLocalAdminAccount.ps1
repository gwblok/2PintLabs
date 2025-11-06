# SetandDisableLocalAdminAccount.ps1
# Generates a strong random password, sets it for the built-in local Administrator account, writes the password to host, then disables the account.
# Run this script as Administrator.

[CmdletBinding()]
param(
    [int]$Length = 24
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
    $password = ($passwordChars | Get-Random -Count $passwordChars.Count) -join ''
    return $password
}

# require elevated
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

try {
    $password = New-RandomPassword -Length $Length

    # find built-in Administrator account (SID ends with -500) even if renamed
    if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
        $admin = Get-LocalUser | Where-Object { $_.SID -and $_.SID.Value.EndsWith('-500') }
        if (-not $admin) { throw "Built-in Administrator account not found." }

        $secure = ConvertTo-SecureString $password -AsPlainText -Force
        Set-LocalUser -Name $admin.Name -Password $secure -ErrorAction Stop
        Disable-LocalUser -Name $admin.Name -ErrorAction Stop

        Write-Host "Administrator account name: $($admin.Name)"
        Write-Host "New password: $password"
        Write-Host "Account has been disabled."
    }
    else {
        # fallback using net user (older systems)
        $adminName = (wmic useraccount where "sid like '%-500'" get name | Select-Object -Skip 1).Trim()
        if (-not $adminName) { throw "Built-in Administrator account not found via WMI." }

        net user "$adminName" "$password" /Y | Out-Null
        net user "$adminName" /active:no | Out-Null

        Write-Host "Administrator account name: $adminName"
        Write-Host "New password: $password"
        Write-Host "Account has been disabled."
    }
}
catch {
    Write-Error "Failed: $_"
    exit 1
}