<#
.SYNOPSIS
Looks up a BitLocker recovery password in Active Directory by PasswordId (GUID).
Run this script as an administrator to use the -RunAsSystem switch, which starts a LocalSystem child process with PsExec to validate access using the server computer account context.
The script will activate the functions in it, then allow you to run them, look at the examples below for usage.

This was to help determine if the DeployR server computer account has access to the BitLocker recovery password in Active Directory.

.NOTES
- Save this script to a local path before running it.
- Dot-source the saved script file to load the function.
- Run PowerShell as Administrator when using -RunAsSystem.
- -RunAsSystem starts a LocalSystem child process with PsExec to validate


.EXAMPLE
. This will test the function in the current user session: (as the logged-in user)
. "D:\GitHub\2PintLabs\DeployR\ServerSideScripts\Get-BitlockerRecovery.ps1"
Get-BitLockerRecoveryPasswordById -PasswordId "966E6BB0-E30B-482C-AC30-B825BEF33968"

.EXAMPLE
. using the -RunAsSystem switch will test the function in a LocalSystem child process: (as the DeployR server computer account)
. "D:\GitHub\2PintLabs\DeployR\ServerSideScripts\Get-BitlockerRecovery.ps1"
Get-BitLockerRecoveryPasswordById -PasswordId "966E6BB0-E30B-482C-AC30-B825BEF33968" -RunAsSystem
#>

# Ensure the ActiveDirectory module is loaded
Import-Module ActiveDirectory -ErrorAction Stop

$script:GetBitLockerRecoveryScriptPath = $PSCommandPath

function ConvertTo-SingleQuotedPowerShellString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    return $Value.Replace("'", "''")
}

function Get-PsExecPath {
    [CmdletBinding()]
    param()

    $downloadRoot = Join-Path -Path $env:TEMP -ChildPath 'PSTools'
    $zipPath = Join-Path -Path $downloadRoot -ChildPath 'PSTools.zip'
    $exePath = Join-Path -Path $downloadRoot -ChildPath 'PsExec64.exe'

    if (Test-Path -Path $exePath) {
        return $exePath
    }

    New-Item -Path $downloadRoot -ItemType Directory -Force | Out-Null

    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/PSTools.zip' -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $zipPath -DestinationPath $downloadRoot -Force
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }

    if (-not (Test-Path -Path $exePath)) {
        throw "PsExec64.exe was not found after extracting '$zipPath'."
    }

    return $exePath
}

function Get-BitLockerRecoveryPasswordById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PasswordId,

        [Parameter()]
        [string]$SearchBase,

        [Parameter()]
        [switch]$RunAsSystem,

        [Parameter()]
        [string]$PsExecPath
    )

    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    if ($RunAsSystem -and $currentIdentity -ne 'NT AUTHORITY\SYSTEM') {
        $scriptPath = $MyInvocation.MyCommand.ScriptBlock.File

        if (-not $scriptPath) {
            $scriptPath = $script:GetBitLockerRecoveryScriptPath
        }

        if (-not $scriptPath) {
            throw 'RunAsSystem requires the function to be invoked from its saved script file.'
        }

        if (-not $PsExecPath) {
            $PsExecPath = Get-PsExecPath
        }

        if (-not (Test-Path -Path $PsExecPath)) {
            throw "PsExec was not found at '$PsExecPath'."
        }

        $scriptPathLiteral = ConvertTo-SingleQuotedPowerShellString -Value $scriptPath
        $passwordIdLiteral = ConvertTo-SingleQuotedPowerShellString -Value $PasswordId
        $searchBaseArgument = ''

        if ($PSBoundParameters.ContainsKey('SearchBase')) {
            $searchBaseLiteral = ConvertTo-SingleQuotedPowerShellString -Value $SearchBase
            $searchBaseArgument = " -SearchBase '$searchBaseLiteral'"
        }

        $childCommand = "& { . '$scriptPathLiteral'; `$result = Get-BitLockerRecoveryPasswordById -PasswordId '$passwordIdLiteral'$searchBaseArgument; if (`$null -ne `$result) { Write-Output `$result } }"
        $psexecOutput = & $PsExecPath -accepteula -nobanner -s powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $childCommand 2>&1
        $psexecExitCode = $LASTEXITCODE
        $psexecText = ($psexecOutput | Out-String).Trim()

        if ($psexecExitCode -ne 0) {
            throw "PsExec failed with exit code $psexecExitCode. $psexecText"
        }

        return $psexecText
    }

    if (-not $SearchBase) {
        $SearchBase = (Get-ADDomain).DistinguishedName
    }

    try {
        $normalizedPasswordId = ([guid]$PasswordId).ToString().ToUpperInvariant()
    }
    catch {
        throw "PasswordId '$PasswordId' is not a valid GUID."
    }

    $match = Get-ADObject -SearchBase $SearchBase `
        -Filter 'objectClass -eq "msFVE-RecoveryInformation"' `
        -Properties 'msFVE-RecoveryGuid', 'msFVE-RecoveryPassword', 'name' |
        Where-Object {
            $candidateId = $null
            $guidValue = $_.'msFVE-RecoveryGuid'

            if ($guidValue -is [byte[]] -and $guidValue.Length -eq 16) {
                $candidateId = ([guid]::new($guidValue)).ToString().ToUpperInvariant()
            }
            elseif ($guidValue) {
                try {
                    $candidateId = ([guid]([string]$guidValue).Trim('{}')).ToString().ToUpperInvariant()
                }
                catch {
                    $candidateId = $null
                }
            }

            if (-not $candidateId -and $_.Name -match '([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})') {
                $candidateId = ([guid]$matches[1]).ToString().ToUpperInvariant()
            }

            $candidateId -eq $normalizedPasswordId
        } |
        Select-Object -First 1

    if (-not $match) {
        throw "No BitLocker recovery entry found for PasswordId '$PasswordId' in '$SearchBase'."
    }

    return $match.'msFVE-RecoveryPassword'
}
