# Ensure the ActiveDirectory module is loaded
Import-Module ActiveDirectory -ErrorAction Stop

function Get-BitLockerRecoveryPasswordById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PasswordId,

        [Parameter()]
        [string]$SearchBase
    )

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