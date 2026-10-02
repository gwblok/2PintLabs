param(
    [string]$Tag = 'FrontEnd'
)

$selectedIds = [string]${TSEnv:SelectedApplicationIds}
if ([string]::IsNullOrWhiteSpace($selectedIds)) {
    Write-Host 'No WebUI applications selected.'
    return
}

Import-Module DeployR.Utility -ErrorAction Stop
$availableApps = @(Get-DeployRApplication | Where-Object { $_.Tags -match [regex]::Escape($Tag) })
$applicationList = @()

foreach ($selectedId in ($selectedIds -split ',' | ForEach-Object { $_.Trim() } | Select-Object -Unique)) {
    $parsedId = [guid]::Empty
    if (-not [guid]::TryParse($selectedId, [ref]$parsedId)) {
        throw "Invalid DeployR application ID: $selectedId"
    }

    $app = @($availableApps | Where-Object { $_.Id -eq $selectedId })
    if ($app.Count -ne 1) {
        throw "Application $selectedId was not found with tag '$Tag'."
    }

    $latestVersion = $app[0].Versions | Sort-Object -Property VersionNumber -Descending | Select-Object -First 1
    if (-not $latestVersion -or $null -eq $latestVersion.VersionNo) {
        throw "Application $selectedId has no installable version."
    }

    $applicationList += "$($app[0].Id):$($latestVersion.VersionNo)"
}

$tsenvlist:Applications = $applicationList
Write-Host "Prepared $($applicationList.Count) DeployR application(s) for installation."