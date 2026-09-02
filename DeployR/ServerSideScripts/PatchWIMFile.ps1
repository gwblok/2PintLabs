<#
.SYNOPSIS
    Mounts a WIM found in the "source" folder, applies all MSU/CAB patches from the
    "Patches" folder (oldest KB first), then saves the serviced WIM into the "updated" folder.

.DESCRIPTION
    Folder layout expected under -RootPath:
        <RootPath>\source\*.wim   - the base WIM to service (only one .wim expected)
        <RootPath>\Patches\*.msu  - patches to apply, sorted oldest KB -> newest KB
        <RootPath>\updated        - destination for the fully patched WIM
        <RootPath>\Mount          - temporary mount folder (created/cleaned automatically)

    Each image index in the WIM is mounted, serviced with every patch in KB order, then
    dismounted and committed. When all indexes are serviced, the resulting WIM is exported
    (compacted) into the updated folder.

.PARAMETER RootPath
    Root folder containing the source, Patches and updated subfolders.

.PARAMETER Index
    Optional. Restrict servicing to a single image index. Default is all indexes in the WIM.

.EXAMPLE
    .\PatchWIMFile.ps1 -RootPath "D:\SourceRepo\OperatingSystems\ClientOS\Win1021H2LTSB"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RootPath,

    [int[]]$Index
)

$ErrorActionPreference = 'Stop'

$SourceFolder  = Join-Path $RootPath 'source'
$PatchesFolder = Join-Path $RootPath 'Patches'
$UpdatedFolder = Join-Path $RootPath 'updated'
$MountFolder   = Join-Path $RootPath 'Mount'

foreach ($folder in @($SourceFolder, $PatchesFolder)) {
    if (-not (Test-Path -LiteralPath $folder)) {
        throw "Required folder not found: $folder"
    }
}
if (-not (Test-Path -LiteralPath $UpdatedFolder)) { New-Item -Path $UpdatedFolder -ItemType Directory -Force | Out-Null }
if (-not (Test-Path -LiteralPath $MountFolder))   { New-Item -Path $MountFolder -ItemType Directory -Force | Out-Null }

$wimFile = Get-ChildItem -LiteralPath $SourceFolder -Filter '*.wim' -File | Select-Object -First 1
if (-not $wimFile) { throw "No .wim file found in $SourceFolder" }
Write-Host "Source WIM: $($wimFile.FullName)"

# Sort patches oldest -> newest based on the KB number embedded in the file name
$patches = Get-ChildItem -LiteralPath $PatchesFolder -Include '*.msu', '*.cab' -File -Recurse |
    ForEach-Object {
        $kb = 0
        if ($_.BaseName -match 'kb(\d+)') { $kb = [int]$Matches[1] }
        [pscustomobject]@{ File = $_; KB = $kb }
    } |
    Sort-Object KB |
    Select-Object -ExpandProperty File

if (-not $patches) { throw "No .msu/.cab patches found in $PatchesFolder" }
Write-Host "Found $($patches.Count) patch(es), applying oldest to newest:"
$patches | ForEach-Object { Write-Host "  $($_.Name)" }

$imageIndexes = if ($Index) { $Index } else {
    (Get-WindowsImage -ImagePath $wimFile.FullName).ImageIndex
}

foreach ($idx in $imageIndexes) {
    Write-Host "`n=== Servicing index $idx ==="
    Mount-WindowsImage -ImagePath $wimFile.FullName -Index $idx -Path $MountFolder | Out-Null

    try {
        foreach ($patch in $patches) {
            Write-Host "Applying $($patch.Name) ..."
            try {
                Add-WindowsPackage -Path $MountFolder -PackagePath $patch.FullName | Out-Null
            }
            catch {
                # Already-installed / not-applicable patches shouldn't abort the whole run
                Write-Warning "Skipping $($patch.Name): $($_.Exception.Message)"
            }
        }
    }
    finally {
        Dismount-WindowsImage -Path $MountFolder -Save | Out-Null
    }
}

$updatedWimPath = Join-Path $UpdatedFolder $wimFile.Name
if (Test-Path -LiteralPath $updatedWimPath) { Remove-Item -LiteralPath $updatedWimPath -Force }

Write-Host "`nExporting serviced WIM to $updatedWimPath ..."
foreach ($idx in $imageIndexes) {
    Export-WindowsImage -SourceImagePath $wimFile.FullName -SourceIndex $idx -DestinationImagePath $updatedWimPath | Out-Null
}

Remove-Item -LiteralPath $MountFolder -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Done. Updated WIM: $updatedWimPath"
