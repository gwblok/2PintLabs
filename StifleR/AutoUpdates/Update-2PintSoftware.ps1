<#
.SYNOPSIS
Updates 2Pint products with StifleR-first orchestration.

.DESCRIPTION
Detects installed StifleR Server and DeployR versions, compares against release metadata,
and then performs download, extraction, and installation steps.
Checks for update metadata from releases.2pintsoftware.com and downloads release artifacts from the same service.
Writes CMTrace-compatible logs to C:\ProgramData\2Pint Software\Maintenance\Update-2PintSoftware.log.
Log entries are appended for each run.

StifleR is always processed first. The StifleR bundle extraction supports nested zip files
and installs matching components (Server, Dashboards, WmiAgent, ActionHub, Beacon) when
those components are currently installed.

Default download root behavior:
- User context: current user's Downloads folder
- SYSTEM context: C:\Windows\Temp

.PARAMETER Auto
Runs without interactive confirmation prompts.

.PARAMETER IncludePreview
Allows preview releases to be selected as target versions when a preview channel is newer.

.PARAMETER DownloadOnly
Downloads and extracts packages but skips installer execution.

.PARAMETER InstallMissing
When set, products that are not currently installed are allowed to install from the release feed.

.PARAMETER ForceDownload
Forces a re-download even when package files already exist.

.PARAMETER Products
Optional product filter. Supported values are StifleR Server and DeployR.

.PARAMETER DownloadPath
Overrides the default root path used for package downloads and extraction.

.EXAMPLE
.\Update-2PintSoftware.ps1 -Auto

.EXAMPLE
.\Update-2PintSoftware.ps1 -IncludePreview -Auto -WhatIf

.EXAMPLE
.\Update-2PintSoftware.ps1 -DownloadOnly -Auto
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Auto,
    [switch]$IncludePreview,
    [switch]$DownloadOnly,
    [switch]$InstallMissing,
    [switch]$ForceDownload,
    [string[]]$Products = @('StifleR Server', 'DeployR'),
    [string]$DownloadPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Global:LogFilePath = $null

# Note: Creates the CMTrace log directory path if it does not exist.
function Start-CMTraceLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $directory = Split-Path -Path $Path -Parent

    if ([string]::IsNullOrWhiteSpace($directory)) {
        return
    }

    if (-not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
    }
}

# Note: Writes a single CMTrace-compatible log line.
function Write-CMTraceLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$LogPath = $($Global:LogFilePath),

        [Parameter()]
        [ValidateSet(1, 2, 3)]
        [int]$LogLevel = 1,

        [Parameter()]
        [string]$Component = 'Update-2PintSoftware',

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Type
    )

    switch ($Type) {
        'Info' { $LogLevel = 1 }
        'Warning' { $LogLevel = 2 }
        'Error' { $LogLevel = 3 }
    }

    $timeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
    $line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
    $lineFormat = $Message, $timeGenerated, (Get-Date -Format MM-dd-yyyy), $Component, $LogLevel
    $line = $line -f $lineFormat

    try {
        if (-not $LogPath) {
            return
        }

        $directory = Split-Path -Path $LogPath -Parent
        if (-not (Test-Path -Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
        }

        Add-Content -Value $line -Path $LogPath -WhatIf:$false
    }
    catch {
        # Do not interrupt update flow due to logging failures.
    }
}

# Note: Resolves the default staging path based on whether the script runs as user or SYSTEM.
function Get-DefaultDownloadPath {
    # Default to Downloads for user context and Windows Temp for SYSTEM.
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($identity -match '^NT AUTHORITY\\SYSTEM$') {
        return 'C:\Windows\Temp'
    }

    $downloadsPath = Join-Path -Path ([Environment]::GetFolderPath('UserProfile')) -ChildPath 'Downloads'
    if ([string]::IsNullOrWhiteSpace($downloadsPath)) {
        return 'C:\Windows\Temp'
    }

    return $downloadsPath
}

# Note: Returns installed applications from registry uninstall keys.
function Get-InstalledApps {
    # Read uninstall registry entries from both native and Wow6432Node hives.
    if (![Environment]::Is64BitProcess) {
        $regPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    }
    else {
        $regPath = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
    }

    Get-ItemProperty $regPath |
        Where-Object {
            $_.PSObject.Properties.Match('DisplayName').Count -gt 0 -and
            $_.PSObject.Properties.Match('UninstallString').Count -gt 0 -and
            $_.DisplayName -and $_.UninstallString
        } |
        Select-Object DisplayName, Publisher, InstallDate, DisplayVersion, UninstallString, InstallLocation |
        Sort-Object DisplayName
}

# Note: Converts version text to [version] when possible.
function ConvertTo-VersionObject {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $versionText = [regex]::Match($Value, '\d+(?:\.\d+){1,3}').Value
    if ([string]::IsNullOrWhiteSpace($versionText)) {
        $versionText = $Value.Trim()
    }

    try {
        return [version]$versionText
    }
    catch {
        return $null
    }
}

# Note: Extracts a major.minor channel string from a version value.
function Get-VersionChannel {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Version
    )

    $parsedVersion = ConvertTo-VersionObject -Value $Version
    if (-not $parsedVersion) {
        return $null
    }

    return '{0}.{1}' -f $parsedVersion.Major, $parsedVersion.Minor
}

# Note: Queries a release endpoint and returns the latest channel metadata.
function Get-ReleaseInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [switch]$ExcludePreview,

        [Parameter(Mandatory = $false)]
        [switch]$PreviewOnly
    )

    Write-Host "Querying release metadata for $DisplayName from $Uri" -ForegroundColor DarkCyan
    Write-CMTraceLog -Message "Querying release metadata for '$DisplayName' from '$Uri'" -Type Info -Component 'Discovery'
    $release = Invoke-RestMethod -Uri $Uri -Method Get -ErrorAction Stop
    $channels = foreach ($channel in $release.channels.PSObject.Properties) {
        [pscustomobject]@{
            Channel      = $channel.Name
            Version      = $channel.Value.version
            Timestamp    = $channel.Value.timestamp
            BuildId      = $channel.Value.build_id
            Commit       = $channel.Value.commit
            IsPreview    = ($channel.Name -match 'preview')
            ArtifactName = ($channel.Value.artifacts.PSObject.Properties | Select-Object -First 1).Name
            ArtifactPath = ($channel.Value.artifacts.PSObject.Properties | Select-Object -First 1).Value
        }
    }

    if ($ExcludePreview) {
        $channels = $channels | Where-Object { $_.Channel -notmatch 'preview' }
    }

    if ($PreviewOnly) {
        $channels = $channels | Where-Object { $_.Channel -match 'preview' }
    }

    if (-not $channels) {
        return [pscustomobject]@{
            ProductName     = $DisplayName
            ProductId       = $release.product
            SourceUrl       = $Uri
            LatestVersion   = $null
            LatestChannel   = $null
            LatestTimestamp = $null
            BuildId         = $null
            Commit          = $null
            IsPreview       = $false
            ArtifactName    = $null
            ArtifactPath    = $null
            DownloadUrl     = $null
        }
    }

    $latestChannel = $channels |
        Where-Object { ConvertTo-VersionObject $_.Version } |
        Sort-Object -Property @{ Expression = { ConvertTo-VersionObject $_.Version } }, @{ Expression = { $_.Timestamp } } -Descending |
        Select-Object -First 1

    if (-not $latestChannel) {
        $latestChannel = $channels | Sort-Object Channel -Descending | Select-Object -First 1
    }

    [pscustomobject]@{
        ProductName     = $DisplayName
        ProductId       = $release.product
        SourceUrl       = $Uri
        LatestVersion   = $latestChannel.Version
        LatestChannel   = $latestChannel.Channel
        LatestTimestamp = $latestChannel.Timestamp
        BuildId         = $latestChannel.BuildId
        Commit          = $latestChannel.Commit
        IsPreview       = $latestChannel.IsPreview
        ArtifactName    = $latestChannel.ArtifactName
        ArtifactPath    = $latestChannel.ArtifactPath
        DownloadUrl     = if ($latestChannel.ArtifactPath) { 'https://releases.2pintsoftware.com/' + $latestChannel.ArtifactPath } else { $null }
    }
}

# Note: Finds the best installed product match from display name patterns.
function Get-LatestInstalledApp {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$InstalledApps,

        [Parameter(Mandatory = $true)]
        [string[]]$Patterns,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    $matches = @(
        foreach ($pattern in $Patterns) {
            $InstalledApps | Where-Object { $_.DisplayName -match $pattern }
        }
    )

    if (-not $matches) {
        return [pscustomobject]@{
            Found                  = $false
            DisplayName            = $DisplayName
            InstalledName          = $null
            InstalledVersion       = $null
            InstalledVersionObject = $null
            InstallDate            = $null
        }
    }

    $candidates = foreach ($match in $matches) {
        [pscustomobject]@{
            DisplayName     = $match.DisplayName
            DisplayVersion  = $match.DisplayVersion
            VersionObject   = ConvertTo-VersionObject $match.DisplayVersion
            InstallDate     = $match.InstallDate
            Publisher       = $match.Publisher
            InstallLocation = $match.InstallLocation
        }
    }

    $installed = $candidates |
        Sort-Object -Property @{ Expression = { if ($_.VersionObject) { $_.VersionObject } else { [version]'0.0.0.0' } } }, @{ Expression = { $_.InstallDate } } -Descending |
        Select-Object -First 1

    return [pscustomobject]@{
        Found                  = $true
        DisplayName            = $DisplayName
        InstalledName          = $installed.DisplayName
        InstalledVersion       = $installed.DisplayVersion
        InstalledVersionObject = $installed.VersionObject
        InstallDate            = $installed.InstallDate
    }
}

# Note: Builds update status objects for StifleR Server and DeployR.
function Get-2PintVersionStatus {
    param(
        [switch]$IncludePreview,
        [string[]]$Products
    )

    $releaseDefinitions = @(
        [pscustomobject]@{
            ProductKey      = 'StifleRServer'
            DisplayName     = 'StifleR Server'
            Uri             = 'https://releases.2pintsoftware.com/stifler/release.json'
            InstalledRegex  = @('(?i)2Pint Software StifleR Server', '(?i)StifleR Server')
            ExcludePreview  = $true
            InstallerRegex  = '(?i)stifler.*server|server.*stifler|stifler(?!.*client)'
            InstallerArgs   = '/qb! /norestart'
        },
        [pscustomobject]@{
            ProductKey      = 'DeployR'
            DisplayName     = 'DeployR'
            Uri             = 'https://releases.2pintsoftware.com/deployr/release.json'
            InstalledRegex  = @('(?i)^2Pint Software DeployR(?:\s+\d[\d\.]*)?$', '(?i)^DeployR(?:\s+\d[\d\.]*)?$')
            ExcludePreview  = $true
            InstallerRegex  = '(?i)deployr'
            InstallerArgs   = '/qb! /norestart'
        }
    )

    if ($Products -and $Products.Count -gt 0) {
        $lookup = $Products | ForEach-Object { $_.ToLowerInvariant() }
        $releaseDefinitions = $releaseDefinitions | Where-Object {
            $key = $_.ProductKey.ToLowerInvariant()
            $name = $_.DisplayName.ToLowerInvariant()
            ($lookup -contains $key) -or ($lookup -contains $name)
        }
    }

    Write-Host 'Scanning installed applications from registry...' -ForegroundColor DarkCyan
    Write-CMTraceLog -Message 'Scanning installed applications from registry uninstall keys.' -Type Info -Component 'Discovery'
    $installedApps = Get-InstalledApps

    foreach ($definition in $releaseDefinitions) {
        Write-Host "Evaluating product: $($definition.DisplayName)" -ForegroundColor DarkCyan
        Write-CMTraceLog -Message "Evaluating product '$($definition.DisplayName)'" -Type Info -Component 'Discovery'
        $releaseStable = Get-ReleaseInfo -Uri $definition.Uri -DisplayName $definition.DisplayName -ExcludePreview:($definition.ExcludePreview)
        $releaseAny = Get-ReleaseInfo -Uri $definition.Uri -DisplayName $definition.DisplayName
        $releasePreview = Get-ReleaseInfo -Uri $definition.Uri -DisplayName $definition.DisplayName -PreviewOnly

        $installedInfo = Get-LatestInstalledApp -InstalledApps $installedApps -Patterns $definition.InstalledRegex -DisplayName $definition.DisplayName

        $installedVersionObject = $installedInfo.InstalledVersionObject
        $stableVersionObject = ConvertTo-VersionObject -Value $releaseStable.LatestVersion
        $latestAnyVersionObject = ConvertTo-VersionObject -Value $releaseAny.LatestVersion

        $installedChannel = Get-VersionChannel -Version $installedInfo.InstalledVersion
        $stableChannel = Get-VersionChannel -Version $releaseStable.LatestVersion
        $anyChannel = Get-VersionChannel -Version $releaseAny.LatestVersion

        $updateAvailable = $false
        $upgradeAvailable = $false

        if ($installedInfo.Found -and $installedVersionObject -and $stableVersionObject -and $installedVersionObject -lt $stableVersionObject) {
            if ($installedChannel -eq $stableChannel) {
                $updateAvailable = $true
            }
            else {
                $upgradeAvailable = $true
            }
        }

        if ($installedInfo.Found -and $installedVersionObject -and $latestAnyVersionObject -and $installedVersionObject -lt $latestAnyVersionObject) {
            if ($installedChannel -eq $anyChannel) {
                $updateAvailable = $true
            }
            else {
                $upgradeAvailable = $true
            }
        }

        $stableStatus = if (-not $installedInfo.Found) {
            'Not Installed'
        }
        elseif ($installedInfo.Found -and $installedVersionObject -and $stableVersionObject -and $installedVersionObject -lt $stableVersionObject) {
            if ($installedChannel -eq $stableChannel) { 'Update Available' } else { 'Upgrade Available' }
        }
        else {
            'Up To Date'
        }

        $overallStatus = if (-not $installedInfo.Found) {
            'Not Installed'
        }
        elseif ($updateAvailable -and $upgradeAvailable) {
            'Update and Upgrade Available'
        }
        elseif ($upgradeAvailable) {
            'Upgrade Available'
        }
        elseif ($updateAvailable) {
            'Update Available'
        }
        else {
            'Up To Date'
        }

        $targetRelease = $releaseStable
        $targetVersionObject = $stableVersionObject
        if ($IncludePreview -and $releaseAny.IsPreview -and $latestAnyVersionObject) {
            $targetRelease = $releaseAny
            $targetVersionObject = $latestAnyVersionObject
        }

        $targetVersion = $targetRelease.LatestVersion
        $actionRequired = $false
        if ($installedInfo.Found -and $installedVersionObject -and $targetVersionObject) {
            $actionRequired = $installedVersionObject -lt $targetVersionObject
        }

        [pscustomobject]@{
            ProductKey                 = $definition.ProductKey
            Product                    = $definition.DisplayName
            Installed                  = $installedInfo.Found
            InstalledDisplayName       = $installedInfo.InstalledName
            InstalledVersion           = $installedInfo.InstalledVersion
            CurrentChannel             = $installedChannel
            LatestVersion              = $releaseStable.LatestVersion
            LatestChannel              = $releaseStable.LatestChannel
            LatestAvailableVersion     = $releaseAny.LatestVersion
            LatestAvailableChannel     = $releaseAny.LatestChannel
            LatestAvailableIsPreview   = $releaseAny.IsPreview
            PreviewVersion             = $releasePreview.LatestVersion
            PreviewChannel             = $releasePreview.LatestChannel
            StableStatus               = $stableStatus
            Status                     = $overallStatus
            UpdateAvailable            = $updateAvailable
            UpgradeAvailable           = $upgradeAvailable
            TargetVersion              = $targetVersion
            TargetChannel              = $targetRelease.LatestChannel
            TargetIsPreview            = $targetRelease.IsPreview
            TargetDownloadUrl          = $targetRelease.DownloadUrl
            TargetArtifact             = $targetRelease.ArtifactName
            TargetVersionObject        = $targetVersionObject
            ActionRequired             = $actionRequired
            InstallerRegex             = $definition.InstallerRegex
            InstallerArgs              = $definition.InstallerArgs
        }
    }
}

# Note: Prompts until a valid yes or no answer is provided.
function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    while ($true) {
        $response = Read-Host "$Prompt [Y/N]"
        if ($response -match '^(?i)y(?:es)?$') { return $true }
        if ($response -match '^(?i)n(?:o)?$') { return $false }
        Write-Host 'Please answer Y or N.' -ForegroundColor Yellow
    }
}

# Note: Selects the most appropriate installer file from extracted content.
function Get-ProductInstaller {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExtractFolder,

        [Parameter(Mandatory = $true)]
        [string]$InstallerRegex,

        [Parameter(Mandatory = $true)]
        [string]$TargetVersion
    )

    $allInstallers = Get-ChildItem -Path $ExtractFolder -Recurse -File -Include *.msi,*.exe |
        Sort-Object FullName

    $filtered = $allInstallers | Where-Object { $_.Name -match $InstallerRegex }
    if (-not $filtered) {
        $filtered = $allInstallers
    }

    $versionFiltered = $filtered | Where-Object { $_.Name -match [regex]::Escape($TargetVersion) }
    if ($versionFiltered) {
        $filtered = $versionFiltered
    }

    $ranked = $filtered |
        Sort-Object -Property @{ Expression = { if ($_.Extension -eq '.msi') { 0 } else { 1 } } }, @{ Expression = { $_.Length }; Descending = $true }

    return $ranked | Select-Object -First 1
}

# Note: Executes an MSI or EXE installer and returns exit code and log path.
function Invoke-ProductInstall {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$Installer,

        [Parameter(Mandatory = $true)]
        [string]$ProductKey,

        [Parameter(Mandatory = $true)]
        [string]$InstallerArgs,

        [Parameter(Mandatory = $true)]
        [string]$LogFolder
    )

    $logPath = Join-Path -Path $LogFolder -ChildPath ('{0}-{1:yyyyMMddHHmmss}.log' -f $ProductKey, (Get-Date))

    Write-Host "Starting installer: $($Installer.FullName)" -ForegroundColor Cyan
    Write-CMTraceLog -Message "Starting installer '$($Installer.FullName)'" -Type Info -Component 'Install'
    if ($Installer.Extension -eq '.msi') {
        $args = '/i "{0}" {1} /l*v "{2}"' -f $Installer.FullName, $InstallerArgs, $logPath
        Write-Host "Installer type MSI, arguments: $args" -ForegroundColor DarkGray
        Write-CMTraceLog -Message "Installer type MSI. LogPath='$logPath'" -Type Info -Component 'Install'
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru -NoNewWindow
    }
    else {
        $args = '/quiet /norestart'
        Write-Host "Installer type EXE, arguments: $args" -ForegroundColor DarkGray
        Write-CMTraceLog -Message "Installer type EXE. Arguments='$args'" -Type Info -Component 'Install'
        $process = Start-Process -FilePath $Installer.FullName -ArgumentList $args -Wait -PassThru -NoNewWindow
    }

    Write-Host "Installer exit code: $($process.ExitCode)" -ForegroundColor DarkGray
    Write-CMTraceLog -Message "Installer completed. ExitCode=$($process.ExitCode) File='$($Installer.FullName)'" -Type Info -Component 'Install'

    [pscustomobject]@{
        ExitCode = $process.ExitCode
        LogPath  = $logPath
    }
}

# Note: Expands StifleR top-level and nested zips, then flattens installer files.
function Expand-StifleRBundle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ZipPath,

        [Parameter(Mandatory = $true)]
        [string]$ExtractFolder
    )

    Write-Host "Extracting StifleR top-level bundle: $ZipPath" -ForegroundColor Cyan
    Write-CMTraceLog -Message "Extracting StifleR top-level bundle '$ZipPath' to '$ExtractFolder'" -Type Info -Component 'Extract'
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractFolder -Force

    $nestedZipFiles = Get-ChildItem -Path $ExtractFolder -Filter *.zip -Recurse -File
    Write-Host "Found $($nestedZipFiles.Count) nested zip file(s) in StifleR bundle" -ForegroundColor DarkGray
    Write-CMTraceLog -Message "Found $($nestedZipFiles.Count) nested zip file(s) in StifleR bundle." -Type Info -Component 'Extract'
    foreach ($nestedZip in $nestedZipFiles) {
        $destination = Join-Path -Path $ExtractFolder -ChildPath $nestedZip.BaseName
        if (Test-Path -Path $destination) {
            Remove-Item -Path $destination -Recurse -Force
        }

        Write-Host "Extracting nested zip: $($nestedZip.Name)" -ForegroundColor DarkGray
        Write-CMTraceLog -Message "Extracting nested zip '$($nestedZip.FullName)'" -Type Info -Component 'Extract'
        Expand-Archive -Path $nestedZip.FullName -DestinationPath $destination -Force
    }

    # Flatten installers to the StifleR extract root for predictable matching.
    Write-Host 'Flattening nested installer files to the StifleR extract root...' -ForegroundColor DarkGray
    Get-ChildItem -Path $ExtractFolder -Recurse -File |
        Where-Object { $_.Extension -in '.msi', '.exe' } |
        ForEach-Object {
            $destinationFile = Join-Path -Path $ExtractFolder -ChildPath $_.Name
            if ($_.FullName -ne $destinationFile) {
                Move-Item -Path $_.FullName -Destination $destinationFile -Force
            }
        }
}

# Note: Starts a StifleR service if it exists on the machine.
function Start-StifleRServiceIfPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "Ensuring service is started: $Name" -ForegroundColor DarkGray
        Set-Service -Name $Name -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name $Name -ErrorAction SilentlyContinue
    }
}

# Note: Installs only StifleR components that are already installed locally.
function Install-StifleRComponents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExtractFolder,

        [Parameter(Mandatory = $true)]
        [object[]]$InstalledApps,

        [Parameter(Mandatory = $false)]
        [switch]$InstallMissingBase,

        [Parameter(Mandatory = $true)]
        [string]$LogFolder
    )

    $componentMap = @(
        [pscustomobject]@{ Component = 'StifleR Server'; MatchRegex = '(?i)StifleR Server'; InstallerRegex = '(?i)server.*\.msi$|stifler.*server.*\.msi$'; ServiceName = 'StifleRServer' }
        [pscustomobject]@{ Component = 'StifleR Dashboards'; MatchRegex = '(?i)StifleR Dashboards'; InstallerRegex = '(?i)dashboard.*\.msi$'; ServiceName = $null }
        [pscustomobject]@{ Component = 'StifleR WmiAgent'; MatchRegex = '(?i)StifleR WmiAgent'; InstallerRegex = '(?i)wmi.*\.msi$'; ServiceName = 'StifleRWmiAgent' }
        [pscustomobject]@{ Component = 'StifleR ActionHub'; MatchRegex = '(?i)StifleR ActionHub'; InstallerRegex = '(?i)actionhub.*\.msi$'; ServiceName = 'StifleRActionHub' }
        [pscustomobject]@{ Component = 'StifleR Beacon'; MatchRegex = '(?i)StifleR Beacon'; InstallerRegex = '(?i)beacon.*\.msi$'; ServiceName = 'StifleRBeacon' }
    )

    $results = @()

    Write-Host 'Installing detected StifleR components...' -ForegroundColor Cyan
    Write-CMTraceLog -Message 'Installing detected StifleR components.' -Type Info -Component 'Install'
    foreach ($component in $componentMap) {
        $isInstalled = $InstalledApps | Where-Object { $_.DisplayName -match $component.MatchRegex }
        $installAsMissingBase = (-not $isInstalled) -and $InstallMissingBase -and ($component.Component -eq 'StifleR Server')

        if ((-not $isInstalled) -and (-not $installAsMissingBase)) {
            Write-Host "Skipping component (not installed): $($component.Component)" -ForegroundColor DarkGray
            Write-CMTraceLog -Message "Skipping component '$($component.Component)' because it is not installed." -Type Info -Component 'Install'
            continue
        }

        if ($installAsMissingBase) {
            Write-Host "Component is missing but will be installed as base product: $($component.Component)" -ForegroundColor Yellow
            Write-CMTraceLog -Message "Component '$($component.Component)' is missing but will be installed due to InstallMissing." -Type Warning -Component 'Install'
        }

        Write-Host "Preparing install for component: $($component.Component)" -ForegroundColor Cyan

        $installer = Get-ChildItem -Path $ExtractFolder -File |
            Where-Object { $_.Name -match $component.InstallerRegex } |
            Select-Object -First 1

        if (-not $installer) {
            Write-Host "No matching installer found for component: $($component.Component)" -ForegroundColor Yellow
            Write-CMTraceLog -Message "No matching installer found for component '$($component.Component)'." -Type Warning -Component 'Install'
            $results += [pscustomobject]@{
                Component = $component.Component
                ExitCode  = -1
                Success   = $false
                LogPath   = $null
                Message   = 'No matching MSI found in extracted StifleR bundle.'
            }
            continue
        }

        $installResult = Invoke-ProductInstall -Installer $installer -ProductKey ($component.Component -replace '[^a-zA-Z0-9]', '') -InstallerArgs '/qb! /norestart' -LogFolder $LogFolder
        Write-CMTraceLog -Message "Component '$($component.Component)' install finished with exit code $($installResult.ExitCode)." -Type Info -Component 'Install'

        if ($installResult.ExitCode -in @(0, 3010) -and $component.ServiceName) {
            Start-StifleRServiceIfPresent -Name $component.ServiceName
        }

        $results += [pscustomobject]@{
            Component = $component.Component
            ExitCode  = $installResult.ExitCode
            Success   = ($installResult.ExitCode -in @(0, 3010))
            LogPath   = $installResult.LogPath
            Message   = if ($installResult.ExitCode -in @(0, 3010)) { 'Installed' } else { 'Installer returned non-success exit code' }
        }
    }

    return $results
}

$resolvedDownloadPath = if ($PSBoundParameters.ContainsKey('DownloadPath') -and -not [string]::IsNullOrWhiteSpace($DownloadPath)) {
    $DownloadPath
}
else {
    Get-DefaultDownloadPath
}

$rootFolder = Join-Path -Path $resolvedDownloadPath -ChildPath '2PintSoftware'
$packageFolder = Join-Path -Path $rootFolder -ChildPath 'Packages'
$extractRoot = Join-Path -Path $rootFolder -ChildPath 'Extracted'
$logFolder = Join-Path -Path $rootFolder -ChildPath 'Logs'

$cmTraceRoot = Join-Path -Path $env:ProgramData -ChildPath '2Pint Software\Maintenance'
$Global:LogFilePath = Join-Path -Path $cmTraceRoot -ChildPath 'Update-2PintSoftware.log'
Start-CMTraceLog -Path $Global:LogFilePath
$runId = [guid]::NewGuid().ToString()
Write-CMTraceLog -Message "Run started. RunId=$runId Auto=$Auto IncludePreview=$IncludePreview DownloadOnly=$DownloadOnly InstallMissing=$InstallMissing ForceDownload=$ForceDownload" -Type Info -Component 'Init'

$null = New-Item -Path $packageFolder -ItemType Directory -Force
$null = New-Item -Path $extractRoot -ItemType Directory -Force
$null = New-Item -Path $logFolder -ItemType Directory -Force

Write-Host "Using download root: $rootFolder" -ForegroundColor Cyan
Write-CMTraceLog -Message "Using download root '$rootFolder'." -Type Info -Component 'Init'
if ($DownloadOnly) {
    Write-Host 'DownloadOnly enabled: packages will be downloaded and extracted, installer execution is skipped.' -ForegroundColor DarkYellow
    Write-CMTraceLog -Message 'DownloadOnly mode enabled.' -Type Info -Component 'Init'
}
if ($InstallMissing) {
    Write-Host 'InstallMissing enabled: missing products can be installed from release packages.' -ForegroundColor DarkYellow
    Write-CMTraceLog -Message 'InstallMissing mode enabled.' -Type Info -Component 'Init'
}
if ($IncludePreview) {
    Write-Host 'IncludePreview enabled: preview releases can be selected when newer.' -ForegroundColor DarkYellow
    Write-CMTraceLog -Message 'IncludePreview mode enabled.' -Type Info -Component 'Init'
}

$status = Get-2PintVersionStatus -IncludePreview:$IncludePreview -Products $Products
$status = $status | Sort-Object -Property @{ Expression = { if ($_.ProductKey -eq 'StifleRServer') { 0 } else { 1 } } }, Product
$installedAppsForInstall = Get-InstalledApps

if (-not $status) {
    Write-Warning 'No matching products found from filter.'
    return
}

Write-Host ''
Write-Host 'Detected product status:' -ForegroundColor Cyan
$status |
    Select-Object Product, Installed, InstalledVersion, LatestVersion, LatestAvailableVersion, StableStatus, Status, ActionRequired |
    Format-Table -AutoSize

$results = @()

foreach ($item in $status) {
    Write-Host "Processing product: $($item.Product)" -ForegroundColor Cyan
    Write-CMTraceLog -Message "Processing product '$($item.Product)'. Installed=$($item.Installed) ActionRequired=$($item.ActionRequired) TargetVersion=$($item.TargetVersion)" -Type Info -Component 'Process'

    $missingInstall = $false

    if (-not $item.Installed) {
        if (-not $InstallMissing) {
            Write-Host "Product is not installed, skipping: $($item.Product)" -ForegroundColor DarkGray
            Write-CMTraceLog -Message "Product '$($item.Product)' is not installed and InstallMissing is not set. Skipping." -Type Info -Component 'Process'
            $results += [pscustomobject]@{
                Product = $item.Product
                InstalledVersion = $item.InstalledVersion
                TargetVersion = $item.TargetVersion
                Action = 'Skipped'
                Reason = 'Product not installed'
                ExitCode = $null
                Installer = $null
                DownloadedFile = $null
                LogPath = $null
            }
            continue
        }

        Write-Host "Product is not installed, preparing fresh install: $($item.Product)" -ForegroundColor Yellow
        Write-CMTraceLog -Message "Product '$($item.Product)' is not installed. Fresh install path selected." -Type Warning -Component 'Process'
        $missingInstall = $true
    }

    if ((-not $item.ActionRequired) -and (-not $missingInstall)) {
        Write-Host "No action required for: $($item.Product)" -ForegroundColor DarkGray
        Write-CMTraceLog -Message "No action required for '$($item.Product)' under selected channel policy." -Type Info -Component 'Process'
        $results += [pscustomobject]@{
            Product = $item.Product
            InstalledVersion = $item.InstalledVersion
            TargetVersion = $item.TargetVersion
            Action = 'Skipped'
            Reason = 'Already current for selected channel policy'
            ExitCode = $null
            Installer = $null
            DownloadedFile = $null
            LogPath = $null
        }
        continue
    }

    if (-not $item.TargetDownloadUrl) {
        Write-Host "No download URL found for: $($item.Product)" -ForegroundColor Yellow
        Write-CMTraceLog -Message "No download URL found for '$($item.Product)'." -Type Error -Component 'Process'
        $results += [pscustomobject]@{
            Product = $item.Product
            InstalledVersion = $item.InstalledVersion
            TargetVersion = $item.TargetVersion
            Action = 'Failed'
            Reason = 'No download URL available'
            ExitCode = $null
            Installer = $null
            DownloadedFile = $null
            LogPath = $null
        }
        continue
    }

    $doInstall = $Auto
    if (-not $Auto) {
        $channelType = if ($item.TargetIsPreview) { 'Preview' } else { 'Stable' }
        if ($DownloadOnly) {
            $actionText = 'Download'
        }
        elseif ($missingInstall) {
            $actionText = 'Install missing product'
        }
        else {
            $actionText = 'Download and install'
        }
        $prompt = '{0} {1} {2} ({3})?' -f $actionText, $item.Product, $item.TargetVersion, $channelType
        $doInstall = Read-YesNo -Prompt $prompt
    }

    if (-not $doInstall) {
        Write-Host "User declined action for: $($item.Product)" -ForegroundColor Yellow
        Write-CMTraceLog -Message "User declined action for '$($item.Product)'." -Type Warning -Component 'Process'
        $results += [pscustomobject]@{
            Product = $item.Product
            InstalledVersion = $item.InstalledVersion
            TargetVersion = $item.TargetVersion
            Action = 'Skipped'
            Reason = 'User declined'
            ExitCode = $null
            Installer = $null
            DownloadedFile = $null
            LogPath = $null
        }
        continue
    }

    if ($WhatIfPreference) {
        Write-Host "WhatIf active, planning only for: $($item.Product)" -ForegroundColor DarkGray
        Write-CMTraceLog -Message "WhatIf active for '$($item.Product)'. Action planned only." -Type Info -Component 'Process'
        $results += [pscustomobject]@{
            Product = $item.Product
            InstalledVersion = $item.InstalledVersion
            TargetVersion = $item.TargetVersion
            Action = 'Planned'
            Reason = 'WhatIf mode - download and install were not executed'
            ExitCode = $null
            Installer = $null
            DownloadedFile = $null
            LogPath = $null
        }
        continue
    }

    $artifactFile = if ($item.TargetArtifact) { $item.TargetArtifact } else { '{0}-{1}.zip' -f $item.ProductKey, $item.TargetVersion }
    $downloadFile = Join-Path -Path $packageFolder -ChildPath $artifactFile
    $extractFolder = Join-Path -Path $extractRoot -ChildPath ('{0}-{1}' -f $item.ProductKey, $item.TargetVersion)

    try {
        if ($ForceDownload -or -not (Test-Path -Path $downloadFile)) {
            if ($PSCmdlet.ShouldProcess($downloadFile, 'Download package')) {
                Write-Host "Downloading package for $($item.Product): $($item.TargetDownloadUrl)" -ForegroundColor Cyan
                Write-CMTraceLog -Message "Downloading package for '$($item.Product)' from '$($item.TargetDownloadUrl)' to '$downloadFile'." -Type Info -Component 'Download'
                Invoke-WebRequest -Uri $item.TargetDownloadUrl -OutFile $downloadFile -UseBasicParsing
                Write-Host "Downloaded to: $downloadFile" -ForegroundColor Green
                Write-CMTraceLog -Message "Download completed for '$($item.Product)'. File='$downloadFile'." -Type Info -Component 'Download'
            }
        }
        else {
            Write-Host "Using existing downloaded package: $downloadFile" -ForegroundColor DarkGray
            Write-CMTraceLog -Message "Using existing package for '$($item.Product)': '$downloadFile'." -Type Info -Component 'Download'
        }

        if (Test-Path -Path $extractFolder) {
            Remove-Item -Path $extractFolder -Recurse -Force
        }

        if ($PSCmdlet.ShouldProcess($extractFolder, 'Extract package')) {
            if ($item.ProductKey -eq 'StifleRServer') {
                Expand-StifleRBundle -ZipPath $downloadFile -ExtractFolder $extractFolder
            }
            else {
                Write-Host "Extracting package for $($item.Product) to $extractFolder" -ForegroundColor Cyan
                Write-CMTraceLog -Message "Extracting package for '$($item.Product)' to '$extractFolder'." -Type Info -Component 'Extract'
                Expand-Archive -Path $downloadFile -DestinationPath $extractFolder -Force
            }
        }

        if ($DownloadOnly) {
            Write-CMTraceLog -Message "DownloadOnly active for '$($item.Product)'. Installation skipped after extraction." -Type Info -Component 'Process'
            $results += [pscustomobject]@{
                Product = $item.Product
                InstalledVersion = $item.InstalledVersion
                TargetVersion = $item.TargetVersion
                Action = 'Downloaded'
                Reason = 'Package downloaded and extracted; installation skipped by DownloadOnly'
                ExitCode = $null
                Installer = $null
                DownloadedFile = $downloadFile
                LogPath = $null
            }
            continue
        }

        if ($item.ProductKey -eq 'StifleRServer') {
            Write-Host 'Running StifleR multi-component install sequence...' -ForegroundColor Cyan
            Write-CMTraceLog -Message "Starting StifleR multi-component install sequence for '$($item.Product)'." -Type Info -Component 'Install'
            $stifleRInstallResults = Install-StifleRComponents -ExtractFolder $extractFolder -InstalledApps $installedAppsForInstall -InstallMissingBase:$missingInstall -LogFolder $logFolder
            $failedCount = ($stifleRInstallResults | Where-Object { -not $_.Success }).Count
            Write-Host "StifleR component install complete. Failed components: $failedCount" -ForegroundColor $(if ($failedCount -eq 0) { 'Green' } else { 'Yellow' })
            Write-CMTraceLog -Message "StifleR component install sequence completed. FailedComponents=$failedCount" -Type $(if ($failedCount -eq 0) { 'Info' } else { 'Warning' }) -Component 'Install'
            $results += [pscustomobject]@{
                Product = $item.Product
                InstalledVersion = $item.InstalledVersion
                TargetVersion = $item.TargetVersion
                Action = if ($failedCount -eq 0) { 'Updated' } else { 'Failed' }
                Reason = if ($failedCount -eq 0) { 'Installed all detected StifleR components' } else { 'One or more StifleR component installs failed' }
                ExitCode = if ($failedCount -eq 0) { 0 } else { -1 }
                Installer = ($stifleRInstallResults | ForEach-Object { $_.Component }) -join '; '
                DownloadedFile = $downloadFile
                LogPath = ($stifleRInstallResults | ForEach-Object { $_.LogPath } | Where-Object { $_ }) -join '; '
            }
            continue
        }

        $installer = Get-ProductInstaller -ExtractFolder $extractFolder -InstallerRegex $item.InstallerRegex -TargetVersion $item.TargetVersion
        if (-not $installer) {
            throw "No installer file found in $extractFolder"
        }

        Write-Host "Selected installer for $($item.Product): $($installer.FullName)" -ForegroundColor Cyan
        Write-CMTraceLog -Message "Selected installer for '$($item.Product)': '$($installer.FullName)'." -Type Info -Component 'Install'

        $installResult = [pscustomobject]@{ ExitCode = $null; LogPath = $null }
        if ($PSCmdlet.ShouldProcess($installer.FullName, 'Install product update')) {
            $installResult = Invoke-ProductInstall -Installer $installer -ProductKey $item.ProductKey -InstallerArgs $item.InstallerArgs -LogFolder $logFolder
        }

        $resultAction = if ($installResult.ExitCode -in @(0, 3010, $null)) { 'Updated' } else { 'Failed' }
        $resultReason = if ($resultAction -eq 'Updated') {
            if ($installResult.ExitCode -eq 3010) { 'Installed, reboot required' } else { 'Installed successfully' }
        }
        else {
            'Installer returned non-success exit code'
        }

        $results += [pscustomobject]@{
            Product = $item.Product
            InstalledVersion = $item.InstalledVersion
            TargetVersion = $item.TargetVersion
            Action = $resultAction
            Reason = $resultReason
            ExitCode = $installResult.ExitCode
            Installer = $installer.FullName
            DownloadedFile = $downloadFile
            LogPath = $installResult.LogPath
        }
    }
    catch {
        Write-CMTraceLog -Message "Product '$($item.Product)' failed with error: $($_.Exception.Message)" -Type Error -Component 'Process'
        $results += [pscustomobject]@{
            Product = $item.Product
            InstalledVersion = $item.InstalledVersion
            TargetVersion = $item.TargetVersion
            Action = 'Failed'
            Reason = $_.Exception.Message
            ExitCode = $null
            Installer = $null
            DownloadedFile = $downloadFile
            LogPath = $null
        }
    }
}

Write-Host ''
Write-Host 'Update summary:' -ForegroundColor Cyan
$results | Format-Table -AutoSize

$failedTotal = @($results | Where-Object { $_.Action -eq 'Failed' }).Count
$updatedTotal = @($results | Where-Object { $_.Action -eq 'Updated' }).Count
$downloadedTotal = @($results | Where-Object { $_.Action -eq 'Downloaded' }).Count
$skippedTotal = @($results | Where-Object { $_.Action -eq 'Skipped' }).Count
Write-CMTraceLog -Message "Run complete. Updated=$updatedTotal Downloaded=$downloadedTotal Skipped=$skippedTotal Failed=$failedTotal" -Type $(if ($failedTotal -gt 0) { 'Warning' } else { 'Info' }) -Component 'Summary'

$results
