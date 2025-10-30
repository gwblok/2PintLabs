<#
.SYNOPSIS
Imports device inventory CSV and populates DeployR FrontEnd RoleDatabase.json

.DESCRIPTION
This script reads a CSV (path provided), extracts the following fields and maps them to the RoleDatabase JSON format:
 - Make
 - Model
 - Serial Number
 - Primary User UPN
 - MAC Addresses (normalized to semicolon-separated)
 - Computer Name
 - Role (mapped from Category)

It will merge into an existing RoleDatabase.json (array of objects) if present, or create a new file.

.PARAMETER CsvPath
Path to the source CSV file. Default: the Downloads path used in the conversation.

.PARAMETER OutJson
Path to the RoleDatabase.json to write. Default: ./RoleDatabase.json in this script's folder.

.EXAMPLE
.
Import-RoleDatabaseFromCSV.ps1 -CsvPath "$env:USERPROFILE\Downloads\DevicesWithInventory_...csv"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$CsvPath = "$env:USERPROFILE\Downloads\DevicesWithInventory_cf661164-d216-4541-9ef7-d641c9d8c6ad\DevicesWithInventory_cf661164-d216-4541-9ef7-d641c9d8c6ad.csv",
    [Parameter(Mandatory=$false)]
    [string]$OutJson = (Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) -ChildPath 'RoleDatabase.json')
)

function Convert-ToMacList {
    param([string]$value)
    if (-not $value) { return '' }
    # Many inventory exporters use commas, semicolons, or pipe. Normalize to semicolon separated.
    $parts = $value -split '[:;,|]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    # Upper-case and format without separators if needed - but keep original formatting mostly.
    $parts = $parts | ForEach-Object { $_.ToUpperInvariant() }
    return ($parts -join ';')
}

Write-Host "Importing CSV:`n  $CsvPath`nOutput JSON:`n  $OutJson"

if (-not (Test-Path -Path $CsvPath)) {
    throw "CSV file not found: $CsvPath"
}

# Read the CSV with PowerShell's Import-Csv
$rows = Import-Csv -Path $CsvPath -ErrorAction Stop

if (-not $rows -or $rows.Count -eq 0) {
    Write-Host "No rows found in CSV. Exiting."; exit 0
}

# We map exact column names later (case-insensitive). No candidate arrays required.

$out = @()
foreach ($r in $rows) {
    # Map exact fields requested (case-insensitive). Use helper: try exact name, then case-insensitive match.
    function GetFieldExact {
        param($row, $name)
        if ($row.PSObject.Properties.Name -contains $name) { return $row.$name }
        # case-insensitive match on property names
        $match = $row.PSObject.Properties.Name | Where-Object { $_.ToLower() -eq $name.ToLower() } | Select-Object -First 1
        if ($match) { return $row.$match }
        # substring fallback
        $match2 = $row.PSObject.Properties.Name | Where-Object { $_.ToLower().Contains($name.ToLower()) } | Select-Object -First 1
        if ($match2) { return $row.$match2 }
        return $null
    }

    $deviceName = GetFieldExact -row $r -name 'Device name'
    $azureRegistered = GetFieldExact -row $r -name 'Azure AD registered'
    $serial = GetFieldExact -row $r -name 'Serial number'
    $manufacturer = GetFieldExact -row $r -name 'Manufacturer'
    $model = GetFieldExact -row $r -name 'Model'
    $wifiMacRaw = GetFieldExact -row $r -name 'Wi-Fi MAC'
    $ethMacRaw = GetFieldExact -row $r -name 'EthernetMAC'
    $category = GetFieldExact -row $r -name 'Category'
    $primaryUPN = GetFieldExact -row $r -name 'Primary user UPN'
    $primaryDisplayName = GetFieldExact -row $r -name 'Primary user display name'

    # For Primary user UPN, only keep the part before '@'
    if ($primaryUPN) {
        $primaryUPN = $primaryUPN.ToString().Trim()
        if ($primaryUPN -match '@') { $primaryUPN = $primaryUPN.Split('@')[0] }
    }

    # Helper to convert field names to PascalCase (remove non-alphanum and spaces, capitalize first letter of each word)
    function ToPascalCaseFieldName {
        param([string]$s)
        if (-not $s) { return $s }
        $tokens = $s -split '\s+'
        $outName = ''
        foreach ($t in $tokens) {
            $clean = ($t -replace '[^0-9A-Za-z]','')
            if ($clean -ne '') {
                $first = $clean.Substring(0,1).ToUpper()
                if ($clean.Length -gt 1) { $rest = $clean.Substring(1) } else { $rest = '' }
                $outName += ($first + $rest)
            }
        }
        if ([string]::IsNullOrWhiteSpace($outName)) { return 'Field' + ([guid]::NewGuid().ToString('N').Substring(0,6)) }
        return $outName
    }

    # Normalize MAC fields separately
    $wifiMac = Convert-ToMacList -value $wifiMacRaw
    $ethMac = Convert-ToMacList -value $ethMacRaw

    if (-not $category -or ($category.ToString().Trim() -eq '')) { $category = 'Generic' }

    # Exclude devices in Category 'production' (case-insensitive)
    if ($category -and ($category.ToString().Trim().ToLower() -eq 'production')) {
        continue
    }

    # Build PascalCase record - compute field names first to avoid parser issues
    $fnDeviceName = ToPascalCaseFieldName 'Device name'
    $fnAzureRegistered = ToPascalCaseFieldName 'Azure AD registered'
    $fnSerial = ToPascalCaseFieldName 'Serial number'
    $fnManufacturer = ToPascalCaseFieldName 'Manufacturer'
    $fnModel = ToPascalCaseFieldName 'Model'
    $fnWiFi = ToPascalCaseFieldName 'Wi-Fi MAC'
    $fnEther = ToPascalCaseFieldName 'EthernetMAC'
    $fnCategory = ToPascalCaseFieldName 'Category'
    $fnPrimaryUPN = ToPascalCaseFieldName 'Primary user UPN'
    $fnPrimaryDisplay = ToPascalCaseFieldName 'Primary user display name'

    $rec = [ordered]@{}
    $rec[$fnDeviceName] = $deviceName
    $rec[$fnAzureRegistered] = $azureRegistered
    $rec[$fnSerial] = $serial
    $rec[$fnManufacturer] = $manufacturer
    $rec[$fnModel] = $model
    $rec[$fnWiFi] = $wifiMac
    $rec[$fnEther] = $ethMac
    $rec[$fnCategory] = $category
    $rec[$fnPrimaryUPN] = $primaryUPN
    $rec[$fnPrimaryDisplay] = $primaryDisplayName
    $out += New-Object PSObject -Property $rec
}

# Read existing JSON if present and merge (simple append)
if (Test-Path -Path $OutJson) {
    try {
        $existing = Get-Content -Path $OutJson -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $existing) { $existing = @() }
    } catch {
        Write-Host "Existing JSON parse failed, overwriting."; $existing = @()
    }
} else { $existing = @() }

$function:GetKey = $null
function GetKey {
    param($o)
    # Prefer Serial (various casings), fallback to DeviceName (various casings)
    $possibleSerialProps = @('Serial number','Serial Number','SerialNumber','SerialNum','Serial')
    foreach ($p in $possibleSerialProps) { if ($o.PSObject.Properties.Name -contains $p) { $s = $o.$p; if ($s) { return $s.ToString().Trim().ToUpperInvariant() } } }
    $possibleDeviceProps = @('Device name','Device Name','DeviceName','Name')
    foreach ($p in $possibleDeviceProps) { if ($o.PSObject.Properties.Name -contains $p) { $d = $o.$p; if ($d) { return $d.ToString().Trim().ToUpperInvariant() } } }
    return ([guid]::NewGuid().ToString())
}

function Merge-Entries {
    param($existingEntry, $newEntry)
    # Fields to merge
    $fields = @('DeviceName','AzureADRegistered','SerialNumber','Manufacturer','Model','WiFiMAC','EthernetMAC','Category','PrimaryUserUPN','PrimaryUserDisplayName')
    $result = [ordered]@{}
    foreach ($f in $fields) {
        $eVal = $null; $nVal = $null
        if ($existingEntry -and $existingEntry.PSObject.Properties.Name -contains $f) { $eVal = $existingEntry.$f }
        if ($newEntry -and $newEntry.PSObject.Properties.Name -contains $f) { $nVal = $newEntry.$f }

        if ($f -in @('WiFiMAC','EthernetMAC')) {
            # union MAC lists (semicolon separated)
            $listE = @()
            $listN = @()
            if ($eVal) { $listE = ($eVal -split ';' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ -ne '' }) }
            if ($nVal) { $listN = ($nVal -split ';' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ -ne '' }) }
            $union = @($listE + $listN) | Select-Object -Unique
            $result[$f] = ($union -join ';')
        } else {
            # prefer non-empty new value, else existing
            if ($null -ne $nVal -and ($nVal.ToString().Trim() -ne '')) { $result[$f] = $nVal }
            else { $result[$f] = $eVal }
        }
    }
    return [PSCustomObject]$result
}

# Build an index from existing entries using key (Serial Number or Computer Name)
$index = @{}
foreach ($e in $existing) {
    $k = GetKey $e
    if (-not $index.ContainsKey($k)) { $index[$k] = $e } else { $index[$k] = Merge-Entries $index[$k] $e }
}

# Merge/append new entries with deduplication
foreach ($n in $out) {
    $k = GetKey $n
    if ($index.ContainsKey($k)) {
        $index[$k] = Merge-Entries $index[$k] $n
    } else {
        $index[$k] = $n
    }
}

# Final merged list - sort by DeviceName if available
$merged = $index.Values | Sort-Object @{Expression={ if ($_.PSObject.Properties.Name -contains 'DeviceName') { $_.DeviceName } elseif ($_.PSObject.Properties.Name -contains 'Device name') { $_.'Device name' } else { '' } }}

# Write JSON with indentation
$merged | ConvertTo-Json -Depth 4 | Out-File -FilePath $OutJson -Encoding UTF8

Write-Host "Wrote $($merged.Count) entries to $OutJson (deduplicated)"

return $merged
