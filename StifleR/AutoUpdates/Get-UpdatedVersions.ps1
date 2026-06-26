function Get-InstalledApps
{
    if (![Environment]::Is64BitProcess) {
        $regpath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    }
    else {
        $regpath = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
    }

    $allApps = Get-ItemProperty $regpath | .{process{if($_.DisplayName -and $_.UninstallString) { $_ } }} |
    Select-Object DisplayName, Publisher, InstallDate, DisplayVersion, UninstallString, InstallLocation

    return $allApps | Sort-Object DisplayName
}

function ConvertTo-VersionObject
{
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

function Get-VersionChannel
{
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

function Get-ReleaseInfo
{
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
            Checksums    = $channel.Value.checksums
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
            Checksums       = $null
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
        Checksums       = $latestChannel.Checksums
    }
}

function Get-LatestInstalledApp
{
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$InstalledApps,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    $matches = $InstalledApps | Where-Object { $_.DisplayName -match $Pattern }
    if (-not $matches) {
        return [pscustomobject]@{
            Found                 = $false
            DisplayName           = $DisplayName
            InstalledName         = $null
            InstalledVersion      = $null
            InstalledVersionObject = $null
            InstallDate           = $null
        }
    }

    $candidates = foreach ($match in $matches) {
        [pscustomobject]@{
            DisplayName    = $match.DisplayName
            DisplayVersion = $match.DisplayVersion
            VersionObject  = ConvertTo-VersionObject $match.DisplayVersion
            InstallDate    = $match.InstallDate
            Publisher      = $match.Publisher
            InstallLocation = $match.InstallLocation
        }
    }

    $installed = $candidates |
        Sort-Object -Property @{ Expression = { if ($_.VersionObject) { $_.VersionObject } else { [version]'0.0.0.0' } } }, @{ Expression = { $_.InstallDate } } -Descending |
        Select-Object -First 1

    return [pscustomobject]@{
        Found                 = $true
        DisplayName           = $DisplayName
        InstalledName         = $installed.DisplayName
        InstalledVersion      = $installed.DisplayVersion
        InstalledVersionObject = $installed.VersionObject
        InstallDate           = $installed.InstallDate
    }
}

function Get-UpdatedVersions
{
    $releaseDefinitions = @(
        [pscustomobject]@{
            DisplayName    = 'DeployR'
            Uri            = 'https://releases.2pintsoftware.com/deployr/release.json'
            Pattern        = '(?i)DeployR(?!\s*Community)'
            ExcludePreview  = $false
        },
        [pscustomobject]@{
            DisplayName    = 'DeployR Community'
            Uri            = 'https://releases.2pintsoftware.com/deployrcommunity/release.json'
            Pattern        = '(?i)DeployR\s*Community|DeployRCommunity'
            ExcludePreview  = $false
        },
        [pscustomobject]@{
            DisplayName    = 'StifleR Server'
            Uri            = 'https://releases.2pintsoftware.com/stifler/release.json'
            Pattern        = '(?i)StifleR Server'
            ExcludePreview  = $true
        }
    )

    $installedApps = Get-InstalledApps

    foreach ($definition in $releaseDefinitions) {
        $releaseInfo = Get-ReleaseInfo -Uri $definition.Uri -DisplayName $definition.DisplayName -ExcludePreview:($definition.ExcludePreview)
        $releaseInfoAny = Get-ReleaseInfo -Uri $definition.Uri -DisplayName $definition.DisplayName
        $releasePreview = Get-ReleaseInfo -Uri $definition.Uri -DisplayName $definition.DisplayName -PreviewOnly
        $installedInfo = Get-LatestInstalledApp -InstalledApps $installedApps -Pattern $definition.Pattern -DisplayName $definition.DisplayName

        $latestVersionObject = ConvertTo-VersionObject $releaseInfo.LatestVersion
        $latestAnyVersionObject = ConvertTo-VersionObject $releaseInfoAny.LatestVersion
        $installedVersionObject = $installedInfo.InstalledVersionObject
        $installedChannel = Get-VersionChannel -Version $installedInfo.InstalledVersion
        $latestStableChannel = Get-VersionChannel -Version $releaseInfo.LatestVersion
        $latestAnyChannel = Get-VersionChannel -Version $releaseInfoAny.LatestVersion

        $updateAvailable = $false
        $upgradeAvailable = $false

        if ($installedInfo.Found -and $installedVersionObject -and $latestVersionObject) {
            if ($installedChannel -eq $latestStableChannel) {
                $updateAvailable = $installedVersionObject -lt $latestVersionObject
            }
            elseif ($installedVersionObject -lt $latestVersionObject) {
                $upgradeAvailable = $true
            }
        }

        if ($installedInfo.Found -and $installedVersionObject -and $latestAnyVersionObject) {
            if ($installedVersionObject -lt $latestAnyVersionObject) {
                if ($installedChannel -eq $latestAnyChannel) {
                    $updateAvailable = $true
                }
                else {
                    $upgradeAvailable = $true
                }
            }
        }

        $stableStatus = if (-not $installedInfo.Found) {
            'Not Installed'
        }
        elseif ($installedInfo.Found -and $installedVersionObject -and $latestVersionObject -and $installedVersionObject -lt $latestVersionObject) {
            if ($installedChannel -eq $latestStableChannel) {
                'Update Available'
            }
            else {
                'Upgrade Available'
            }
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

        [pscustomobject]@{
            Product             = $definition.DisplayName
            Installed           = $installedInfo.Found
            InstalledVersion    = $installedInfo.InstalledVersion
            CurrentChannel      = $installedChannel
            LatestVersion       = $releaseInfo.LatestVersion
            LatestChannel       = $releaseInfo.LatestChannel
            LatestTimestamp     = $releaseInfo.LatestTimestamp
            LatestAvailableVersion = $releaseInfoAny.LatestVersion
            LatestAvailableChannel = $releaseInfoAny.LatestChannel
            LatestAvailableIsPreview = $releaseInfoAny.IsPreview
            PreviewVersion      = $releasePreview.LatestVersion
            PreviewChannel      = $releasePreview.LatestChannel
            UpdateAvailable     = $updateAvailable
            UpgradeAvailable    = $upgradeAvailable
            StableStatus        = $stableStatus
            Status              = $overallStatus
            DownloadUrl         = $releaseInfo.DownloadUrl
            ReleaseArtifact     = $releaseInfo.ArtifactName
            LatestAvailableDownloadUrl = $releaseInfoAny.DownloadUrl
            SourceUrl           = $releaseInfo.SourceUrl
            InstalledDisplayName = $installedInfo.InstalledName
            InstalledInstallDate = $installedInfo.InstallDate
        }
    }
}

if ($MyInvocation.MyCommand.Path -eq $PSCommandPath) {
    Get-UpdatedVersions
}