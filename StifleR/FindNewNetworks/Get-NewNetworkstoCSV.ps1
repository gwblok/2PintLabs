<#
.SYNOPSIS
Creates a StifleR network baseline or exports networks missing from it.
.DESCRIPTION
NewBaseline creates or replaces the baseline with all current networks, without
exporting a CSV. UpdateBaseline exports networks missing from the baseline and
adds them after a successful export. Without either switch, the script exports
missing networks without updating the baseline. Comparison uses network GUIDs,
not subnet addresses. Previously known networks are retained during updates.
A previous baseline is retained as NetworkBaseline.json.bak.
Run with access to root\StifleR. Create a baseline before reporting or updating.
.PARAMETER StateDirectory
Directory holding the baseline, lock file, and timestamped CSV reports.
.PARAMETER CimSession
Optional session to a remote StifleR server. Without it, queries run locally.
.PARAMETER NewBaseline
Create or replace the baseline with all current networks. No CSV is generated.
.PARAMETER UpdateBaseline
Export networks missing from the baseline, then add them to the baseline.
.PARAMETER AllowEmptySnapshot
Allow an empty query result when an existing baseline is present.
.PARAMETER Region
Value for the reference CSV Region column; defaults to AM.
.EXAMPLE
.\Get-NewNetworkstoCSV.ps1 -NewBaseline -StateDirectory C:\Temp\StifleRNetworks
.EXAMPLE
.\Get-NewNetworkstoCSV.ps1 -StateDirectory C:\Temp\StifleRNetworks
.EXAMPLE
.\Get-NewNetworkstoCSV.ps1 -UpdateBaseline -StateDirectory C:\Temp\StifleRNetworks
.EXAMPLE
.\Get-NewNetworkstoCSV.ps1 -CimSession (New-CimSession -ComputerName StifleRServer)
#>
[CmdletBinding(DefaultParameterSetName = 'Report')]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$StateDirectory = "$env:ProgramData\2Pint Software\StifleR\Server\NewNetworks\",

    [Parameter()]
    [Microsoft.Management.Infrastructure.CimSession]$CimSession,

    [Parameter(Mandatory = $true, ParameterSetName = 'NewBaseline')]
    [switch]$NewBaseline,

    [Parameter(Mandatory = $true, ParameterSetName = 'UpdateBaseline')]
    [switch]$UpdateBaseline,

    [Parameter()]
    [switch]$AllowEmptySnapshot,

    [Parameter()]
    [string]$Region = 'AM'
)

function Get-NetworkKey {
    param ([object]$Id)

    $parsedId = [guid]::Empty
    if (-not [guid]::TryParse([string]$Id, [ref]$parsedId) -or $parsedId -eq [guid]::Empty) {
        throw "Invalid network GUID '$Id'. The baseline has not been updated."
    }
    $parsedId.ToString('D')
}

function Get-SubnetBitMask {
    param ([string]$SubnetMask)

    $address = [System.Net.IPAddress]::Parse($SubnetMask)
    if ($address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Expected an IPv4 subnet mask, received '$SubnetMask'."
    }
    $bits = ($address.GetAddressBytes() | ForEach-Object {
        [Convert]::ToString($_, 2).PadLeft(8, '0')
    }) -join ''
    if ($bits -notmatch '^1*0*$') {
        throw "Subnet mask '$SubnetMask' is not contiguous."
    }
    '/' + ($bits -replace '0', '').Length
}

$queryParameters = @{ Namespace = 'root\StifleR'; ErrorAction = 'Stop' }
if ($CimSession) {
    $queryParameters.CimSession = $CimSession
    $server = $CimSession.ComputerName
}
else {
    $server = [Environment]::MachineName
}

$null = New-Item -Path $StateDirectory -ItemType Directory -Force -ErrorAction Stop
$StateDirectory = (Resolve-Path -LiteralPath $StateDirectory -ErrorAction Stop).ProviderPath
$baselinePath = Join-Path $StateDirectory 'NetworkBaseline.json'
$lockPath = Join-Path $StateDirectory 'NetworkTracking.lock'
$baselineTemporaryPath = Join-Path $StateDirectory ([guid]::NewGuid().ToString() + '.baseline.tmp')
$reportTemporaryPath = Join-Path $StateDirectory ([guid]::NewGuid().ToString() + '.csv.tmp')
$lock = $null
$reportPath = $null

try {
    $lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

    $hasBaseline = Test-Path -LiteralPath $baselinePath -ErrorAction Stop
    $previousIds = @{}
    $baseline = $null
    if (-not $NewBaseline -and -not $hasBaseline) {
        throw 'No baseline exists. Run with -NewBaseline first.'
    }
    if ($hasBaseline -and -not $NewBaseline) {
        $baseline = Get-Content -LiteralPath $baselinePath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        if ($baseline.SchemaVersion -ne 1 -or $baseline.Server -ne $server -or
            $null -eq $baseline.Networks -or -not $baseline.LastSuccessfulRunUtc) {
            throw 'The baseline is invalid or belongs to a different server. Use a separate state directory per server.'
        }
        $null = [datetimeoffset]::Parse($baseline.LastSuccessfulRunUtc)
        foreach ($entry in $baseline.Networks) {
            $key = Get-NetworkKey -Id $entry.Id
            if ($previousIds.ContainsKey($key)) {
                throw "Duplicate network GUID '$key' in the baseline."
            }
            $previousIds[$key] = $true
        }
    }

    $networks = @(Get-CimInstance @queryParameters -ClassName Networks)
    if ($hasBaseline -and ($NewBaseline -or $previousIds.Count -gt 0) -and $networks.Count -eq 0 -and -not $AllowEmptySnapshot) {
        throw 'StifleR returned no networks. The baseline was preserved. Use -AllowEmptySnapshot to accept this result.'
    }

    $currentIds = @{}
    $snapshot = @()
    $networksToExport = @()
    foreach ($network in $networks) {
        $key = Get-NetworkKey -Id $network.Id
        if ($currentIds.ContainsKey($key)) {
            throw "StifleR returned duplicate network GUID '$key'."
        }
        $currentIds[$key] = $true
        $snapshotMask = [string]$network.SubnetMask
        if (-not $snapshotMask) { $snapshotMask = [string]$network.NetworkMask }
        $snapshot += [pscustomobject][ordered]@{
            Id = $key
            NetworkId = $network.NetworkId
            SubnetMask = $snapshotMask
            GatewayMAC = $network.GatewayMAC
            NetworkGroupId = $network.NetworkGroupId
        }
        if (-not $NewBaseline -and -not $previousIds.ContainsKey($key)) {
            $networksToExport += $network
        }
    }

    $runTime = [datetime]::UtcNow
    $rows = @()
    if ($networksToExport.Count -gt 0) {
        $groupsById = @{}
        foreach ($group in @(Get-CimInstance @queryParameters -ClassName NetworkGroups)) {
            $groupsById[[string]$group.Id] = $group
        }
        $locationsById = @{}
        foreach ($location in @(Get-CimInstance @queryParameters -ClassName Locations)) {
            $locationsById[[string]$location.Id] = $location
        }

        foreach ($network in $networksToExport) {
            $group = $groupsById[[string]$network.NetworkGroupId]
            if (-not $group) {
                throw "Network '$($network.Id)' has no matching network group."
            }
            $locationId = $group.LocationId
            if (-not $locationId) { $locationId = $network.LocationId }
            $location = $locationsById[[string]$locationId]
            if (-not $location) {
                throw "Network '$($network.Id)' has no matching location."
            }
            $methodParameters = @{ InputObject = $network; MethodName = 'GetDiscoveryData'; ErrorAction = 'Stop' }
            if ($CimSession) { $methodParameters.CimSession = $CimSession }
            $discoveryResult = Invoke-CimMethod @methodParameters
            $discovery = $discoveryResult.ReturnValue | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $discovery -or $discovery -isnot [pscustomobject]) {
                throw "Network '$($network.Id)' returned invalid discovery data."
            }
            $subnetMask = [string]$network.SubnetMask
            if (-not $subnetMask) { $subnetMask = [string]$network.NetworkMask }
            $vpn = [string]$group.VPN -match '^(True|1)$'
            $locationName = $location.Name
            if (-not $locationName) { $locationName = $location.LocationName }
            if ($discovery.ComputerName) {
                $locationName = 'Added Record created by ' + $discovery.ComputerName
            }
            $notes = "First observed by this script $($runTime.ToString('o')); StifleR network Id $($network.Id)"
            if ($location.DateAdded) { $notes += "; Location created $($location.DateAdded)" }

            $rows += [pscustomobject][ordered]@{
                Prefix = 'SUB'
                Location = $locationName
                Type = $null
                SubnetID = $network.NetworkId
                BitMask = Get-SubnetBitMask -SubnetMask $subnetMask
                SubnetMask = $subnetMask
                Gateway = $discovery.GatewayIP
                SubnetAddresses = $network.NetworkId
                SiteSystems = $null
                BeaconServer = $null
                VPN = $vpn
                LocationGroupName = $group.Name
                PercentOfMaxDownstream = $(if (-not $vpn) { $group.PercentOfMaxDownstream })
                Country = $null
                Region = $Region
                WellConnected = $(if (-not $vpn) { 'True' })
                TargetBandwidth = $(if ($vpn) { $group.TargetBandwidth })
                MaxBandwidthDownstream = $(if (-not $vpn) { $group.MaxBandwidthDownstream })
                DirectRoute = $discovery.DirectRoute
                Notes = $notes
            }
        }

        $reportName = 'NewNetworks_{0}_{1}.csv' -f $runTime.ToString('yyyy-MM-dd_HH-mm-ss-fff'), [guid]::NewGuid().ToString('N')
        $reportPath = Join-Path $StateDirectory $reportName
        $rows | Export-Csv -LiteralPath $reportTemporaryPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $reportTemporaryPath -Destination $reportPath -ErrorAction Stop
    }

    $baselineWritten = $false
    if ($NewBaseline -or $UpdateBaseline) {
        if ($NewBaseline) {
            $baselineNetworks = $snapshot
        }
        else {
            $baselineNetworks = @($baseline.Networks) + @($snapshot | Where-Object {
                -not $previousIds.ContainsKey($_.Id)
            })
        }
        $baseline = [pscustomobject][ordered]@{
            SchemaVersion = 1
            Server = $server
            LastSuccessfulRunUtc = $runTime.ToString('o')
            Networks = @($baselineNetworks | Sort-Object Id)
        }
        $baseline | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $baselineTemporaryPath -Encoding UTF8 -ErrorAction Stop

        if ($hasBaseline) {
            [System.IO.File]::Replace($baselineTemporaryPath, $baselinePath, "$baselinePath.bak")
        }
        else {
            [System.IO.File]::Move($baselineTemporaryPath, $baselinePath)
        }
        $baselineWritten = $true
    }

    [pscustomobject][ordered]@{
        Server = $server
        Mode = $(if ($NewBaseline) { 'NewBaseline' } elseif ($UpdateBaseline) { 'UpdateBaseline' } else { 'Report' })
        BaselineCreated = $NewBaseline -and -not $hasBaseline
        BaselineUpdated = $baselineWritten
        BaselineNetworkCount = @($baseline.Networks).Count
        CurrentNetworkCount = $networks.Count
        ExportedNetworkCount = $rows.Count
        CsvPath = $reportPath
        BaselinePath = $baselinePath
        LastSuccessfulRunUtc = $baseline.LastSuccessfulRunUtc
        RunTimeUtc = $runTime.ToString('o')
    }
}
finally {
    foreach ($temporaryPath in @($baselineTemporaryPath, $reportTemporaryPath)) {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
    if ($lock) { $lock.Dispose() }
}