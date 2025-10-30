<#
.SYNOPSIS
Import device inventory from Microsoft Graph (Intune) and populate RoleDatabase.json

.DESCRIPTION
Connects to Microsoft Graph, pulls managed devices from Intune, maps fields to the project's RoleDatabase schema (PascalCase field names), normalizes MACs, sets Category to 'Generic' when empty, excludes Category 'production', and merges/deduplicates into the existing RoleDatabase.json.

.NOTES
Requires Microsoft.Graph PowerShell SDK. Example scopes requested: DeviceManagementManagedDevices.Read.All, Directory.Read.All
#>

function Import-RoleDatabaseFromGraph {
    param(
        [string]$OutJson = (Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) -ChildPath 'RoleDatabase.json'),
        [string[]]$ExcludeCategories = @('production'),
        [switch]$DryRun,
        [int]$First,
        [int]$Last,
        [switch]$ForceConnect,
        [switch]$ReplaceExisting
    )

    function Convert-ToMacList {
    param([string]$value)
    if (-not $value) { return '' }
    $parts = $value -split '[:;,|]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    $parts = $parts | ForEach-Object { $_.ToUpperInvariant() }
    return ($parts -join ';')
}

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

function GetKey {
    param($o)
    $possibleSerialProps = @('Serial number','Serial Number','SerialNumber','SerialNum','Serial','SerialNumber')
    foreach ($p in $possibleSerialProps) { if ($o.PSObject.Properties.Name -contains $p) { $s = $o.$p; if ($s) { return $s.ToString().Trim().ToUpperInvariant() } } }
    $possibleDeviceProps = @('Device name','Device Name','DeviceName','deviceName','Name')
    foreach ($p in $possibleDeviceProps) { if ($o.PSObject.Properties.Name -contains $p) { $d = $o.$p; if ($d) { return $d.ToString().Trim().ToUpperInvariant() } } }
    return ([guid]::NewGuid().ToString())
}

function Merge-Entries {
    param($existingEntry, $newEntry)
    $fields = @('DeviceName','AzureADRegistered','SerialNumber','Manufacturer','Model','WiFiMAC','EthernetMAC','Category','PrimaryUserUPN','PrimaryUserDisplayName')
    $result = [ordered]@{}
    foreach ($f in $fields) {
        $eVal = $null; $nVal = $null
        if ($existingEntry -and $existingEntry.PSObject.Properties.Name -contains $f) { $eVal = $existingEntry.$f }
        if ($newEntry -and $newEntry.PSObject.Properties.Name -contains $f) { $nVal = $newEntry.$f }

        if ($f -in @('WiFiMAC','EthernetMAC')) {
            $listE = @()
            $listN = @()
            if ($eVal) { $listE = ($eVal -split ';' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ -ne '' }) }
            if ($nVal) { $listN = ($nVal -split ';' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ -ne '' }) }
            $union = @($listE + $listN) | Select-Object -Unique
            $result[$f] = ($union -join ';')
        } else {
            if ($null -ne $nVal -and ($nVal.ToString().Trim() -ne '')) { $result[$f] = $nVal }
            else { $result[$f] = $eVal }
        }
    }
    return [PSCustomObject]$result
}

    function Connect-GraphAuth {
        param([switch]$Force)
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
            throw 'Microsoft.Graph module not available. Run: Install-Module Microsoft.Graph'
        }
        if ($Force -or -not (Get-MgContext -ErrorAction SilentlyContinue)) {
            Write-Host 'Connecting to Microsoft Graph... you will be prompted to sign-in and consent to scopes.'
            Connect-MgGraph -Scopes 'DeviceManagementManagedDevices.Read.All','Directory.Read.All'
        }
    }

    Connect-GraphAuth -Force:$ForceConnect

    # Retrieve managed devices from Intune
    Write-Host 'Retrieving managed devices from Microsoft Graph (Intune)...'
try {
    $devices = @()
    # Try the high-level SDK cmdlet first
    try {
        $devices = Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop
    } catch {
        # Fallback to direct Graph request with paging
        $resp = Invoke-MgGraphRequest -Method GET -Uri '/deviceManagement/managedDevices'
        if ($resp.value) { $devices += $resp.value }
        while ($resp.'@odata.nextLink') {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
            if ($resp.value) { $devices += $resp.value }
        }
    }
} catch {
    throw "Failed to retrieve devices from Graph: $_"
}

    if (-not $devices -or $devices.Count -eq 0) { Write-Host 'No devices returned from Intune.'; return @() }

    # Helper to safely get a possibly-missing property from the Graph object
    function Get-GraphProperty {
        param($obj, [string[]]$names)
        foreach ($n in $names) {
            if ($null -ne $obj -and $obj.PSObject.Properties.Name -contains $n) { return $obj.$n }
        }
        return $null
    }

    # Pre-filter devices by excluded categories (case-insensitive) BEFORE applying -First/-Last
    if ($ExcludeCategories -and $ExcludeCategories.Count -gt 0) {
        $beforeFilter = $devices.Count
        $devices = $devices | Where-Object {
            $cat = Get-GraphProperty $_ @('deviceCategoryDisplayName','deviceCategory','category')
            if (-not $cat -or ($cat.ToString().Trim() -eq '')) { $cat = 'Generic' }
            $skip = $false
            foreach ($ex in $ExcludeCategories) {
                if ($ex -and ($cat.ToString().Trim().ToLower() -eq $ex.ToString().Trim().ToLower())) { $skip = $true; break }
            }
            -not $skip
        }
        Write-Host "Filtered devices by ExcludeCategories (removed $($beforeFilter - $devices.Count) devices). Remaining: $($devices.Count)"
    }

    # Allow selecting a subset for testing: -First N or -Last N (mutually exclusive)
    if ($First -and $Last) { throw 'Specify only one of -First or -Last' }
    if ($First) {
        Write-Host "Selecting first $First devices for processing (of $($devices.Count) available after filtering)"
        $devices = $devices | Select-Object -First $First
    } elseif ($Last) {
        Write-Host "Selecting last $Last devices for processing (of $($devices.Count) available after filtering)"
        $devices = $devices | Select-Object -Last $Last
    }

    # Map Graph device properties to our schema
    $out = @()
    foreach ($d in $devices) {
    # Graph properties (try multiple candidate names)
    $deviceName = Get-GraphProperty $d @('deviceName','DeviceName','displayName')
    $azureRegistered = Get-GraphProperty $d @('azureAdRegistered','azureRegistered')
    $serial = Get-GraphProperty $d @('serialNumber','SerialNumber')
    $manufacturer = Get-GraphProperty $d @('manufacturer')
    $model = Get-GraphProperty $d @('model')
    # MAC candidates - safe property access
    $wifiMacRaw = Get-GraphProperty $d @('wifiMac','wiFiMacAddress','wifiMacAddress','wiFiMac')
    $ethMacRaw = Get-GraphProperty $d @('ethernetMac','ethernetMacAddress','macAddress')
    $category = Get-GraphProperty $d @('deviceCategoryDisplayName','deviceCategory','category')
    $primaryUPN = Get-GraphProperty $d @('userPrincipalName')
    $primaryDisplayName = Get-GraphProperty $d @('userDisplayName','userDisplayName')

    # Primary UPN prefix only
    if ($primaryUPN) { $primaryUPN = $primaryUPN.ToString().Split('@')[0] }

    $wifiMac = Convert-ToMacList -value $wifiMacRaw
    $ethMac = Convert-ToMacList -value $ethMacRaw

    # Normalize category: treat null, empty, or 'unknown' as 'Generic'
    if (-not $category -or ($category.ToString().Trim() -eq '') -or ($category.ToString().Trim().ToLower() -eq 'unknown')) { $category = 'Generic' }

    # Build PascalCase record
    $rec = [ordered]@{}
    $rec.DeviceName = $deviceName
    $rec.AzureADRegistered = $azureRegistered
    $rec.SerialNumber = $serial
    $rec.Manufacturer = $manufacturer
    $rec.Model = $model
    $rec.WiFiMAC = $wifiMac
    $rec.EthernetMAC = $ethMac
    $rec.Category = $category
    $rec.PrimaryUserUPN = $primaryUPN
    $rec.PrimaryUserDisplayName = $primaryDisplayName
    $out += New-Object PSObject -Property $rec
    }

    # Merge with existing RoleDatabase.json (or replace if requested)
    if ($ReplaceExisting) {
        # When replacing, ignore the on-disk file and write only the processed items
        $existing = @()
        $index = @{}
        $existingCount = 0
        foreach ($n in $out) { $k = GetKey $n; if ($index.ContainsKey($k)) { $index[$k] = Merge-Entries $index[$k] $n } else { $index[$k] = $n } }
        $finalCount = $index.Count
        $added = $finalCount - $existingCount
        $merged = $index.Values | Sort-Object @{Expression={ if ($_.PSObject.Properties.Name -contains 'DeviceName') { $_.DeviceName } else { '' } }}
    }
    else {
        if (Test-Path -Path $OutJson) {
            try { $existing = Get-Content -Path $OutJson -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $existing = @() }
        } else { $existing = @() }

        $index = @{}
        foreach ($e in $existing) { $k = GetKey $e; if (-not $index.ContainsKey($k)) { $index[$k] = $e } else { $index[$k] = Merge-Entries $index[$k] $e } }
        $existingCount = $index.Count
        foreach ($n in $out) { $k = GetKey $n; if ($index.ContainsKey($k)) { $index[$k] = Merge-Entries $index[$k] $n } else { $index[$k] = $n } }
        $finalCount = $index.Count
        $added = ($finalCount - $existingCount)

        $merged = $index.Values | Sort-Object @{Expression={ if ($_.PSObject.Properties.Name -contains 'DeviceName') { $_.DeviceName } else { '' } }}
    }

    if ($DryRun) {
        Write-Host "DryRun: Retrieved $($devices.Count) devices; Existing=$existingCount; Final=$finalCount; Added=$added"
        return $merged
    }

    $merged | ConvertTo-Json -Depth 4 | Out-File -FilePath $OutJson -Encoding UTF8

    Write-Host "Wrote $($merged.Count) entries to $OutJson (merged from Graph)"

    return $merged
}
