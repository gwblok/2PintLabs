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

<#
try {
    # Define the OU or search base (change as needed)
    $SearchBase = "DC=2P,DC=garytown,DC=com"

    # Retrieve BitLocker recovery keys from AD
    $BitLockerKeys = Get-ADObject -SearchBase $SearchBase `
        -Filter 'objectClass -eq "msFVE-RecoveryInformation"' `
        -Properties 'msFVE-RecoveryPassword', 'msFVE-KeyPackage', 'whenCreated' |
        Select-Object `
            @{Name='ComputerName';Expression={($_.DistinguishedName -split ',')[1] -replace '^CN=',''}},
            @{Name='RecoveryPassword';Expression={$_.'msFVE-RecoveryPassword'}},
            @{Name='KeyPackage';Expression={$_.'msFVE-KeyPackage'}},
            @{Name='Created';Expression={$_.whenCreated}}

    # Output to console
    $BitLockerKeys | Format-Table -AutoSize

    # Export to CSV
    $ExportPath = "C:\Temp\BitLockerKeys.csv"
    $BitLockerKeys | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8

    Write-Host "BitLocker recovery keys exported to $ExportPath" -ForegroundColor Green
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
#>