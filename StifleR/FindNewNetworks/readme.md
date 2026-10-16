# Track New StifleR Networks

Run `Get-NewNetworkstoCSV.ps1` on the StifleR server with permission to query
`root\StifleR` and write to the tracking directory. The script reads StifleR;
it does not change networks, network groups, or locations.

## Run Locally

```powershell
# Create or replace the baseline with all current networks. No CSV is generated.
.\Get-NewNetworkstoCSV.ps1 -NewBaseline

# Export networks missing from the baseline WITHOUT updating it.
.\Get-NewNetworkstoCSV.ps1

# Export networks missing from the baseline, then add them to it.
.\Get-NewNetworkstoCSV.ps1 -UpdateBaseline

# Choose a writable directory and a different Region value for the CSV.
.\Get-NewNetworkstoCSV.ps1 -StateDirectory C:\Temp\StifleRNetworks -Region EU
```

The default directory is
`C:\ProgramData\2Pint Software\StifleR\Server\NewNetworks\` (using
`$env:ProgramData`). Always reuse the same directory for successive runs.
Create a baseline with `-NewBaseline` before reporting or updating. The two
baseline switches cannot be combined. `-ExportExisting` is no longer supported.
Existing JSON baselines from the previous version remain compatible.

For example, when using a custom directory:

```powershell
.\Get-NewNetworkstoCSV.ps1 -NewBaseline -StateDirectory C:\Temp\StifleRNetworks
.\Get-NewNetworkstoCSV.ps1 -StateDirectory C:\Temp\StifleRNetworks
.\Get-NewNetworkstoCSV.ps1 -UpdateBaseline -StateDirectory C:\Temp\StifleRNetworks
```

## Run Remotely

```powershell
$session = New-CimSession -ComputerName StifleRServer
try {
  # Use -NewBaseline once to initialize this directory before reporting.
    .\Get-NewNetworkstoCSV.ps1 -CimSession $session -StateDirectory C:\Temp\StifleRServerNetworks
}
finally {
    Remove-CimSession -CimSession $session
}
```

Remote CIM access must be configured. Files are written on the computer running
the script, not on the remote server. Use one state directory per server and a
consistent server name; a baseline from another server is rejected when reporting
or updating. `-NewBaseline` explicitly replaces the baseline for the target server.

## Output and Comparison

- `NetworkBaseline.json`: known network GUIDs and identifying fields, server,
  schema version, and last successful baseline write time in UTC.
- `NetworkBaseline.json.bak`: baseline from before the most recent baseline write.
- `NewNetworks_<timestamp>_<unique-id>.csv`: created only when networks are exported.
- `NetworkTracking.lock`: prevents concurrent runs using the same directory.
  The file remains after the run, but the lock is released automatically.

The script returns a summary object with the mode, whether the baseline was
updated, counts, and the paths to the baseline and any CSV. `LastSuccessfulRunUtc`
is the baseline write time; `RunTimeUtc` is the current run time.

"Changes" means network GUIDs not already present in the baseline. Comparison
uses StifleR's `Id` GUID, not its `NetworkId` subnet address. Two records sharing
a subnet can both be reported. Changes to an existing record's settings or group
are not exported. Updates add new records and retain previously known records,
even if they are no longer in StifleR. A known network that disappears and returns
is therefore not reported again. `-NewBaseline` discards that history and starts
from the current networks. Networks created and deleted between runs cannot be
detected.

Report-only runs do not change the baseline or its backup. Until you use
`-UpdateBaseline`, repeated report-only runs export the same unrecorded networks
to separate CSVs. No CSV is created when there are no new networks, or when using
`-NewBaseline`.

The CSV preserves the reference column names and order. When `GetDiscoveryData`
provides a hostname, `Location` is set to `Added Record created by <hostname>`;
otherwise, it falls back to the current StifleR location name. Network group
names come from the current StifleR objects; Gateway and DirectRoute come from
`GetDiscoveryData`. Unpopulated reference columns remain blank. The reference's
VPN/non-VPN bandwidth mapping, non-VPN `WellConnected = True`, and default
`Region = AM` are retained. `WellConnected` is a reference default, not a
measured connectivity result. Notes include the observation time and GUID;
location creation time is included when available.

## Failure and Recovery

In update mode, queries, discovery JSON, GUIDs, group/location relationships,
subnet masks, and CSV writes must succeed before the baseline advances. New
baseline mode only queries and records network identities; no CSV enrichment is
needed. Baseline replacement is atomic and retains a backup. Do not edit the
tracking JSON as part of normal use; edit or consume the CSV separately.

An unexpectedly empty query is rejected when a populated baseline exists. To
explicitly reset an existing baseline to an empty server, use `-NewBaseline
-AllowEmptySnapshot`. Updates never remove known records, even with the override.

If the CSV is saved but baseline replacement fails, the CSV remains available
and the old baseline stays in place. A retry can therefore export those networks
again; the GUID in Notes helps identify duplicate reports.

To start over, use `-NewBaseline`; the prior baseline is saved as the backup. This
also lets you replace a damaged baseline without parsing it. To retain additional
history, archive older backups separately. To recover a damaged baseline without
starting over, restore a known-good backup while no run is active; networks added
since that backup will be reported again. Do not delete the lock file while a run
is active.

For recurring use, schedule `-UpdateBaseline` to export each newly discovered
network once after successful updates, or use neither switch to keep reporting
all networks missing from a fixed baseline. Use a stable state directory and an
account that has CIM and filesystem access. Retain CSVs as needed;
automatic report cleanup is not performed.

