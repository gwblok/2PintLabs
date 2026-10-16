<#
.SYNOPSIS
    Publishes the latest StifleR Client MSI into DeployR: copies it to the content source folder,
    creates/updates the DeployR content item, and regenerates the boot image when something changed.

.DESCRIPTION
    Builds off Update-2PintStifleRFromZip.ps1, which extracts the StifleR Client MSI to
    $env:USERPROFILE\Downloads\StifleR\Extracted. It is kept separate for now and is intended to be
    merged into that script later.

    Run it on the DeployR server, from PowerShell 7, in an elevated session (elevation is only
    needed for the boot image regeneration; see -SkipRegenerate).

    What it does, in order:
      1. Validates the MSI and source paths (creates the source folder if only the folder is missing).
      2. Copies the MSI to the source folder and verifies the copy.
      3. Writes the embedded settings file (dr-2pintlabs.2psImport) next to the MSI. The file is
         rebuilt on every run from the JSON embedded in this script, so edit it here, not on disk.
      4. Reads the MSI ProductVersion and connects to the local DeployR server.
      5. Looks up the content item by name:
           - missing                      -> creates it (Folder / Application) with version 1
           - present, MSI version differs -> overwrites the current version (no new version is added)
           - present and already current  -> does nothing (unless -Force)
      6. Only if step 5 created or updated the item, regenerates the boot image by running DeployR's
         Generate.ps1 -Id <BootImageId> -Regenerate. If the item was already current, no
         regeneration is triggered.

    DeployR content item layout (matches the existing StifleR Client item in the console):
      Item Description    : MSI ProductVersion (also used to decide whether the item is current)
      Version Description : UNC path of the source folder (falls back to the local path)
      Install command line: msiexec /i <msi> AUTOSTART=1 REBOOT=ReallySuppress
                            OPTIONS="%WorkingDir%\dr-2pintlabs.2psImport" /qn /l*v "C:\Windows\Temp\StifleRClientInstall.log"
      Version status      : Active

    "Current" only compares the MSI version. If you change the embedded .2psImport settings without a
    new MSI version, run with -Force. Likewise, if a previous run updated the item but the
    regeneration failed, re-run with -Force (or run Generate.ps1 yourself), because the item will
    look current.

    Exit codes: 0 = success or nothing to do, 1 = a check, the DeployR update or the regeneration failed.

.PARAMETER SourceLocation
    Content source folder for the StifleR Client application (MSI and .2psImport live here and the
    whole folder is uploaded as the content item).
    Default: D:\SourceRepo\Applications\2PintSoftware\StifleRClient

.PARAMETER ExtractedMsiPath
    Full path to the extracted StifleR Client MSI produced by Update-2PintStifleRFromZip.ps1.
    Default: $env:USERPROFILE\Downloads\StifleR\Extracted\StifleR-ClientApp-x64.msi

.PARAMETER ContentItemName
    Name of the DeployR content item to create or update. Pass the name of an existing item to update
    it instead of creating a new one. Default: '2Pint StifleR Client'

.PARAMETER SourceUncPath
    UNC path stored in the version description. If omitted, it is derived from a local SMB share
    covering SourceLocation, falling back to the local SourceLocation path.

.PARAMETER SkipDeployR
    Only copy the MSI and create the .2psImport file; do not touch DeployR at all.

.PARAMETER Force
    Update the content item even if it already has the current MSI version. This also triggers the
    boot image regeneration, since the item was updated.

.PARAMETER BootImageId
    DeployR boot image to regenerate after the content item is created or updated.
    Default: 00000003-0000-0000-0000-000000000001 (Windows PE x64).

.PARAMETER GenerateScriptPath
    Path to DeployR's Generate.ps1.
    Default: C:\Program Files\2Pint Software\DeployR\WebServer\Scripts\Generate.ps1

.PARAMETER SkipRegenerate
    Do not regenerate the boot image (also skips the elevation and Generate.ps1 checks).

.EXAMPLE
    .\Update-2PintStifleRClientContentItem.ps1
    Normal run: publishes the MSI and regenerates the Windows PE x64 boot image only if the content item changed.

.EXAMPLE
    .\Update-2PintStifleRClientContentItem.ps1 -ContentItemName '2Pint Software StifleR Client 3.1' -SkipRegenerate
    Updates an existing, differently named item without regenerating the boot image.

.EXAMPLE
    .\Update-2PintStifleRClientContentItem.ps1 -Force
    Re-uploads the content and regenerates the boot image even though the version has not changed.

.NOTES
    Requires: PowerShell 7 (Set-DeployRMetadata fails on Windows PowerShell), the DeployR Client
    module (DeployR.Utility) on this machine, and the DeployR client passcode (read from
    HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings, or D:\DeployRPasscode.txt as a fallback).
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$SourceLocation = 'D:\SourceRepo\Applications\2PintSoftware\StifleRClient',
    [string]$ExtractedMsiPath = (Join-Path -Path $env:USERPROFILE -ChildPath 'Downloads\StifleR\Extracted\StifleR-ClientApp-x64.msi'),
    [string]$ContentItemName = '2Pint StifleR Client',
    [string]$SourceUncPath,
    [switch]$SkipDeployR,
    [switch]$Force,
    [string]$BootImageId = '00000003-0000-0000-0000-000000000001',
    [string]$GenerateScriptPath = 'C:\Program Files\2Pint Software\DeployR\WebServer\Scripts\Generate.ps1',
    [switch]$SkipRegenerate
)

$ErrorActionPreference = 'Stop'
$ImportFileName = 'dr-2pintlabs.2psImport'

# Embedded .2psImport content (single-quoted here-string so the \u0022 escapes are kept literally)
$ImportFileContent = @'
{"SettingsOptions":{"StifleRulezURL":"https://raw.githubusercontent.com/2pintsoftware/StifleRRules/master/StifleRulez.xml","LogEventLevel":"Verbose","StiflerServers":"[\u0022https://dr.2pintlabs.com:1414\u0022]","DefaultNonRedLeaderBITSPolicy":"2560","DefaultNonRedLeaderDOPolicy":"2560","DefaultDisconnectedBITSPolicy":"51200","DefaultDisconnectedDOPolicy":"51200","EnableDebugTelemetry":"False","UseServerAsClient":"True","VPNStrings":"[\u0022VPN\u0022,\u0022Cisco%20AnyConnect\u0022,\u0022Virtual%20Private%20Network\u0022,\u0022SonicWall\u0022,\u0022WireGuard\u0022,\u0022Global%20Protect\u0022,\u0022Secure%20Access\u0022]","SignalRLogging":"True","OOBEBandwidth":"1024000","RemoteToolsCapabilitiesFlag":"FileExplorer,%20FileContent,%20RegistryViewer,%20WmiViewer,%20EventLogs,%20PerformanceCounters,%20ResourceMonitor,%20TaskManager,%20DeviceInformation,%20RemoteAssistance,%20Rdp,%20RemoteCli,%20TsData,%20Intune,%20TunnelRdp,%20ReadLog","MomURLList":"[\u0022*.hp.com\u0022,\u0022*.lenovo.com\u0022,\u0022*.dell.com\u0022,\u0022*.microsoft.com\u0022,\u0022*.adobe.com\u0022,\u0022*.2pintlabs.com\u0022]"}}
'@.Trim()

#region Functions
# Reads ProductVersion from the MSI Property table via the Windows Installer COM object.
# Every COM object is released explicitly so the MSI is not left locked by this session
# (late-bound InvokeMember calls are required because the COM objects expose no type information).
function Get-MsiProductVersion {
    param([string]$Path)
    $Installer = $null; $Database = $null; $View = $null; $Record = $null
    try {
        $Installer = New-Object -ComObject WindowsInstaller.Installer
        $Database = $Installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $Installer, @($Path, 0))
        $View = $Database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $Database, @("SELECT Value FROM Property WHERE Property = 'ProductVersion'"))
        $View.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $View, $null) | Out-Null
        $Record = $View.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $View, $null)
        $Version = $Record.GetType().InvokeMember('StringData', 'GetProperty', $null, $Record, 1)
        $View.GetType().InvokeMember('Close', 'InvokeMethod', $null, $View, $null) | Out-Null
        return $Version
    }
    finally {
        foreach ($ComObject in @($Record, $View, $Database, $Installer)) {
            if ($null -ne $ComObject) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ComObject) }
        }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }
}

# Builds a UNC path for a local folder using the most specific non-administrative SMB share that contains it.
# Returns the original local path when no share covers it (or shares cannot be read).
function Get-SourceUncPath {
    param([string]$Path)
    try {
        $Full = (Resolve-Path -Path $Path).ProviderPath.TrimEnd('\')
        # Match on a path boundary so D:\Source does not match D:\SourceRepo; longest share path wins
        $Share = Get-SmbShare -ErrorAction Stop |
            Where-Object { $_.Path -and $_.Name -notmatch '\$$' -and ($Full -eq $_.Path.TrimEnd('\') -or $Full.StartsWith($_.Path.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) } |
            Sort-Object { $_.Path.Length } -Descending | Select-Object -First 1
        if ($Share) {
            $Rest = $Full.Substring($Share.Path.TrimEnd('\').Length)
            $HostName = [Net.Dns]::GetHostEntry('').HostName
            return "\\$HostName\$($Share.Name)$Rest"
        }
    }
    catch { }
    return $Path
}

# Imports DeployR.Utility and authenticates with the local client passcode.
# Connect-DeployR stores the token in $env:DeployRToken, which Generate.ps1 later inherits as a child process.
function Connect-ToDeployR {
    $ModulePath = 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
    if (Test-Path -Path $ModulePath) { Import-Module $ModulePath -ErrorAction Stop }
    elseif (Get-Module -ListAvailable -Name DeployR.Utility) { Import-Module DeployR.Utility -ErrorAction Stop }
    else { throw 'DeployR.Utility module not found. Ensure the DeployR Client is installed on this machine.' }

    $RegPath = 'HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings'
    if (Test-Path -Path $RegPath) {
        $Passcode = (Get-Item -Path $RegPath).GetValue('ClientPasscode')
    }
    elseif (Test-Path -Path 'D:\DeployRPasscode.txt') {
        $Passcode = (Get-Content -Path 'D:\DeployRPasscode.txt' -Raw).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($Passcode)) {
        throw 'Cannot find the DeployR client passcode in the registry or D:\DeployRPasscode.txt.'
    }
    Connect-DeployR -Passcode $Passcode -ErrorAction Stop | Out-Null
}
#endregion Functions

#region Path checks
# The MSI must exist (run Update-2PintStifleRFromZip.ps1 first to produce it)
if (-not (Test-Path -Path $ExtractedMsiPath -PathType Leaf)) {
    Write-Host "StifleR Client MSI not found: $ExtractedMsiPath" -ForegroundColor Red
    Write-Host "Run Update-2PintStifleRFromZip.ps1 first to extract the latest download." -ForegroundColor Yellow
    exit 1
}
if ([IO.Path]::GetExtension($ExtractedMsiPath) -ne '.msi') {
    Write-Host "Expected an .msi file but got: $ExtractedMsiPath" -ForegroundColor Red
    exit 1
}

# Only create the leaf folder when the drive exists, so a typo in the drive letter is not silently "fixed"
$SourceRoot = [IO.Path]::GetPathRoot($SourceLocation)
if ([string]::IsNullOrWhiteSpace($SourceRoot) -or -not (Test-Path -Path $SourceRoot)) {
    Write-Host "Drive/root for source location does not exist: $SourceLocation" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -Path $SourceLocation -PathType Container)) {
    Write-Host "Source location does not exist, creating: $SourceLocation" -ForegroundColor Yellow
    try {
        New-Item -ItemType Directory -Path $SourceLocation -Force | Out-Null
    }
    catch {
        Write-Host "Failed to create source location: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
#endregion Path checks

#region Copy MSI
$MsiFile = Get-Item -Path $ExtractedMsiPath
$DestinationMsi = Join-Path -Path $SourceLocation -ChildPath $MsiFile.Name
# Always overwrite so the source folder holds the latest MSI; verify by file size
try {
    Copy-Item -Path $MsiFile.FullName -Destination $DestinationMsi -Force
}
catch {
    Write-Host "Failed to copy MSI to $DestinationMsi : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -Path $DestinationMsi -PathType Leaf) -or (Get-Item $DestinationMsi).Length -ne $MsiFile.Length) {
    Write-Host "MSI copy verification failed: $DestinationMsi" -ForegroundColor Red
    exit 1
}
Write-Host "Copied $($MsiFile.Name) to $SourceLocation" -ForegroundColor Green
#endregion Copy MSI

#region Create .2psImport
$ImportFilePath = Join-Path -Path $SourceLocation -ChildPath $ImportFileName
try {
    # UTF-8 without BOM
    [IO.File]::WriteAllText($ImportFilePath, $ImportFileContent, (New-Object System.Text.UTF8Encoding($false)))
    $null = $ImportFileContent | ConvertFrom-Json   # sanity check the embedded JSON
}
catch {
    Write-Host "Failed to create $ImportFilePath : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host "Created $ImportFileName in $SourceLocation" -ForegroundColor Green
#endregion Create .2psImport

if ($SkipDeployR) {
    Write-Host 'SkipDeployR specified, not touching DeployR.' -ForegroundColor Yellow
    exit 0
}

#region DeployR content item
try {
    # The MSI version doubles as the item description, which is what the "is it current" check compares
    $MsiVersion = Get-MsiProductVersion -Path $DestinationMsi
    if ([string]::IsNullOrWhiteSpace($MsiVersion)) { throw "Could not read ProductVersion from $DestinationMsi" }
    if (-not $SourceUncPath) { $SourceUncPath = Get-SourceUncPath -Path $SourceLocation }
    # %WorkingDir% is expanded by DeployR at install time to the folder the content is applied to
    $InstallCommandLine = "msiexec /i $($MsiFile.Name) AUTOSTART=1 REBOOT=ReallySuppress OPTIONS=`"%WorkingDir%\$ImportFileName`" /qn /l*v `"C:\Windows\Temp\StifleRClientInstall.log`""

    Write-Host "Connecting to DeployR..." -ForegroundColor Cyan
    Connect-ToDeployR

    # Get-DeployRApplication only returns Application-purpose items, matched here by exact name
    $FoundItems = @(Get-DeployRApplication | Where-Object { $_.Name -eq $ContentItemName })
    if ($FoundItems.Count -gt 1) {
        Write-Warning "Found $($FoundItems.Count) content items named '$ContentItemName', using the first one ($($FoundItems[0].id))."
    }

    # Current = same MSI version in the item description and the latest version has content.
    # $ContentUpdated is what later gates the boot image regeneration.
    $ContentUpdated = $false
    $IsCurrent = $false
    if ($FoundItems.Count -ge 1 -and -not $Force) {
        $ExistingVersion = $FoundItems[0].versions | Sort-Object versionNo -Descending | Select-Object -First 1
        $IsCurrent = ($FoundItems[0].description -eq $MsiVersion) -and $ExistingVersion -and ([int64]$ExistingVersion.contentSize -gt 0)
    }

    if ($IsCurrent) {
        Write-Host "Content item '$ContentItemName' is already at version $MsiVersion, nothing to update (use -Force to overwrite)." -ForegroundColor Yellow
        $ItemId = $FoundItems[0].id
    }
    else {
        # Preflight the regeneration requirements before changing anything, so a missing script or a
        # non-elevated session does not leave a freshly updated item with no regeneration (PEPrep.ps1 requires admin)
        if (-not $SkipRegenerate) {
            if (-not (Test-Path -Path $GenerateScriptPath -PathType Leaf)) { throw "Generate.ps1 not found: $GenerateScriptPath" }
            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                throw 'Boot image regeneration requires an elevated session. Run as Administrator (or use -SkipRegenerate).'
            }
        }
        $ContentUpdated = $true

        if ($FoundItems.Count -eq 0) {
            Write-Host "Creating content item '$ContentItemName' (version $MsiVersion)..." -ForegroundColor Cyan
            $NewItem = New-DeployRContentItem -Type Folder -Name $ContentItemName -Description $MsiVersion -Purpose Application
            New-DeployRContentItemVersion -ContentItemId $NewItem.id -SourceFolder $SourceLocation -InstallationCommandLine $InstallCommandLine -Description $SourceUncPath -Status Active | Out-Null
            $ItemId = $NewItem.id
        }
        else {
            $ItemId = $FoundItems[0].id
            Write-Host "Updating existing content item '$ContentItemName' (version $MsiVersion), overwriting the current version..." -ForegroundColor Cyan

            # Item metadata first: it carries the versions array, so do it before the version/content changes
            $Item = Get-DeployRMetadata -Type ContentItem | Where-Object { $_.id -eq $ItemId }
            $Item.description = $MsiVersion
            Set-DeployRMetadata -Type ContentItem -Object $Item | Out-Null

            # Overwrite the latest version in place (metadata first, then re-upload the content) rather than adding a new version
            $Current = (Get-DeployRApplication | Where-Object { $_.id -eq $ItemId }).versions | Sort-Object versionNo -Descending | Select-Object -First 1
            if ($Current) {
                $Current.installationCommandLine = $InstallCommandLine
                $Current.description = $SourceUncPath
                $Current | Set-DeployRMetadata -Type ContentItemVersion | Out-Null
                Update-DeployRContentItemContent -ContentId $Current.contentItemId -ContentVersion $Current.versionNo -SourceFolder $SourceLocation | Out-Null
            }
            else {
                Write-Warning 'Content item has no versions, adding one.'
                New-DeployRContentItemVersion -ContentItemId $ItemId -SourceFolder $SourceLocation -InstallationCommandLine $InstallCommandLine -Description $SourceUncPath -Status Active | Out-Null
            }

            # Re-fetch after the content upload and make sure the version is Active
            $Final = (Get-DeployRApplication | Where-Object { $_.id -eq $ItemId }).versions | Sort-Object versionNo -Descending | Select-Object -First 1
            if ($Final -and $Final.status -ne 'Active') {
                $Final.status = 'Active'
                $Final | Set-DeployRMetadata -Type ContentItemVersion | Out-Null
            }
        }
    }

    # Show the final state as read back from DeployR
    $Result = Get-DeployRApplication | Where-Object { $_.id -eq $ItemId }
    $ResultVersion = $Result.versions | Sort-Object versionNo -Descending | Select-Object -First 1
    Write-Host "DeployR content item ready:" -ForegroundColor Green
    Write-Host "  Name:         $($Result.name)"
    Write-Host "  Description:  $($Result.description)"
    Write-Host "  Version:      $($ResultVersion.versionNo) ($($ResultVersion.status))"
    Write-Host "  Version desc: $($ResultVersion.description)"
    Write-Host "  Content size: $($ResultVersion.contentSize) B"
    Write-Host "  Command line: $($ResultVersion.installationCommandLine)"
}
catch {
    Write-Host "DeployR update failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
#endregion DeployR content item

#region Regenerate boot image
# Only regenerate when this run actually created or updated the content item
if (-not $ContentUpdated) {
    Write-Host 'Content item was not changed, skipping boot image regeneration.' -ForegroundColor Yellow
    exit 0
}
if ($SkipRegenerate) {
    Write-Host 'SkipRegenerate specified, not regenerating the boot image.' -ForegroundColor Yellow
    exit 0
}

Write-Host "Regenerating boot image $BootImageId..." -ForegroundColor Cyan
try {
    # Child process inherits $env:DeployRToken from Connect-DeployR; Generate.ps1 uses relative paths so it must run from its own folder
    $GenerateArgs = @('-NoProfile', '-File', "`"$GenerateScriptPath`"", '-Id', $BootImageId, '-Regenerate')
    $Generate = Start-Process -FilePath (Join-Path -Path $PSHOME -ChildPath 'pwsh.exe') -ArgumentList $GenerateArgs -WorkingDirectory (Split-Path -Path $GenerateScriptPath -Parent) -Wait -NoNewWindow -PassThru
    if ($Generate.ExitCode -ne 0) { throw "Generate.ps1 exited with code $($Generate.ExitCode)" }
}
catch {
    Write-Host "Boot image regeneration failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host "Boot image $BootImageId regenerated." -ForegroundColor Green

