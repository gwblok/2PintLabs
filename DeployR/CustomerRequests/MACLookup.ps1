<#
.SYNOPSIS
Look up a computer name by MAC from MACLookup.json (or built-in map if file missing).

.DESCRIPTION
`Get-ComputerByMac` normalizes the provided MAC and attempts to load a JSON map named
`MACLookup.json` from the same folder as this script. If the JSON is missing the
function prints a message and falls back to an embedded lookup.

.EXAMPLE
Import-Module .\MACLookup.ps1
Get-ComputerByMac -MacAddress 'CC:BF:E0:E7:3D:7E'
#>

param()

$DefaultJson = Join-Path -Path $PSScriptRoot -ChildPath 'MACLookup.json'

# Embedded mapping (fallback)
$InitialLookup = @{
    '39:0C:8C:7D:72:47' = 'ygg-tg03-01'
    '34:2C:D8:10:0F:2F' = 'ygg-tg03-02'
    '6F:77:0D:65:D6:70' = 'ygg-tg03-03'
    'E5:8E:03:51:D8:AE' = 'ygg-tg03-04'
    '8E:4F:6E:AC:34:2F' = 'ygg-tg03-05'
    'C2:31:B7:B0:87:16' = 'ygg-tg03-06'
    'EB:3F:C1:28:96:B9' = 'ygg-tg03-07'
    '62:23:17:74:94:28' = 'ygg-tg03-08'
    '77:33:C2:8E:E8:BA' = 'ygg-tg03-09'
    '53:BD:B5:6B:88:24' = 'ygg-tg03-10'
    '57:7D:53:EC:C2:8A' = 'ygg-tg03-11'
    '70:A6:1C:75:10:A1' = 'ygg-tg03-12'
    'CD:89:21:6C:A1:6C' = 'ygg-tg03-13'
    'FF:CA:EA:49:87:47' = 'ygg-tg03-14'
    '7E:86:DB:CC:B9:70' = 'ygg-tg03-15'
    '46:FC:2E:18:38:4E' = 'ygg-tg03-16'
    '51:D8:20:C5:C3:EF' = 'ygg-tg03-17'
    '80:05:3A:88:AE:39' = 'ygg-tg03-18'
    '96:DE:50:E8:01:86' = 'ygg-tg03-19'
    '5B:36:98:65:4E:BF' = 'ygg-tg03-20'
    '52:00:A5:FA:09:39' = 'ygg-tg03-21'
    'B9:9D:7A:1D:7B:28' = 'ygg-tg03-22'
    '2B:F8:23:40:41:F3' = 'ygg-tg03-23'
    '54:87:D8:6C:66:9F' = 'ygg-tg03-24'
    'CC:BF:E0:E7:3D:7E' = 'ygg-tg03-25'
    '73:20:AD:0A:75:70' = 'ygg-tg03-26'
    '03:24:1E:75:22:10' = 'ygg-tg03-27'
    'A9:24:79:8E:F8:6D' = 'ygg-tg03-28'
    '43:F2:7C:F2:D0:61' = 'ygg-tg03-29'
    '30:31:DC:B5:D8:D2' = 'ygg-tg03-30'
}

function Normalize-Mac {
    param([Parameter(Mandatory=$true)][string]$Mac)
    $m = $Mac.Trim().ToUpper()
    $m = $m -replace '[.\-]', ':'
    if ($m -match '^[0-9A-F]{12}$') {
        $m = ($m -split '(.{2})' | Where-Object { $_ -ne '' }) -join ':'
    }
    return $m
}

function Get-ComputerByMac {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $MacAddress,
        [string]$JsonPath = $DefaultJson
    )

    # Accept arrays or other types; coerce to a single string for normalization
    if ($MacAddress -is [System.Array]) { $MacAddress = ($MacAddress -join '') }
    $MacAddress = [string]$MacAddress

    $mac = Normalize-Mac -Mac $MacAddress

    if (Test-Path -Path $JsonPath) {
        try {
            $jsonObj = Get-Content -Raw -Path $JsonPath | ConvertFrom-Json
            # Normalize keys to uppercase for robust lookup
            $map = @{}
            foreach ($p in $jsonObj.PSObject.Properties) { $map[$p.Name.ToUpper()] = $p.Value }
        }
        catch {
            Write-Host "Failed to read JSON at $($JsonPath): $($_.Exception.Message)" -ForegroundColor Yellow
            $map = @{}
            foreach ($k in $InitialLookup.Keys) { $map[$k.ToUpper()] = $InitialLookup[$k] }
        }
    }
    else {
        Write-Host "No MACLookup.json found in folder ($($PSScriptRoot)); using embedded pre-defined lookup" -ForegroundColor Yellow
        $map = @{}
        foreach ($k in $InitialLookup.Keys) { $map[$k.ToUpper()] = $InitialLookup[$k] }
    }

    if ($map.ContainsKey($mac)) { return $map[$mac] }
    return $null
}

#If DeployR Task Sequence, take the return and set the TS Computer Name Variable

try {
    Import-Module DeployR.Utility
}
catch {}

if (Get-Module -name "DeployR.Utility"){
    $MACAddress = ${TSEnv:MacAddress}
}
else{
    Write-Host "Running outside of DeployR, using Gather to get MAC Address for Testing" -ForegroundColor Yellow
    $Gather = iex (irm gather.garytown.com)
    $MACAddress = $Gather.MacAddress
}

Write-Host "Looking up computer name for MAC address: $MACAddress" -ForegroundColor Cyan

$tsCompName = Get-ComputerByMac -MacAddress $MACAddress
if ($tsCompName) {
    Write-Host "Setting Task Sequence Computer Name to: $tsCompName" -ForegroundColor Green
    if (Get-Module -name "DeployR.Utility"){
        $tsenv:COMPUTERNAME = $tsCompName
    }
}
else {
    Write-Host "No computer name found for MAC address: $($env:DEPLOYR_MACADDRESS)" -ForegroundColor Red
}

