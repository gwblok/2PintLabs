[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'applications.json'),

    [string]$Tag = 'FrontEnd'
)

$ErrorActionPreference = 'Stop'
$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    throw "WebUI output directory does not exist: $outputDirectory"
}

if (-not (Get-Command Get-DeployRApplication -ErrorAction SilentlyContinue)) {
    $clientModule = 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
    if (Test-Path -LiteralPath $clientModule) {
        Import-Module $clientModule -ErrorAction Stop
    } else {
        Import-Module DeployR.Utility -ErrorAction Stop
    }
}

$deployRApps = @(Get-DeployRApplication -ErrorAction Stop)
if ($deployRApps.Count -eq 0) {
    throw 'DeployR returned no applications; keeping the last published catalog.'
}

$catalog = @(
    foreach ($app in $deployRApps) {
        if (@($app.Tags) -notcontains $Tag) { continue }
        $appId = [guid]::Empty
        if (-not [guid]::TryParse([string]$app.Id, [ref]$appId)) {
            throw "Application '$($app.Name)' has an invalid DeployR ID."
        }
        [pscustomobject]@{
            id = [string]$app.Id
            displayName = [string]$app.Name
        }
    }
)

$json = ConvertTo-Json -InputObject $catalog -Depth 3 -Compress
$temporaryPath = Join-Path $outputDirectory ('.applications-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $OutputPath -Force
} finally {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
}

Write-Host "Published $($catalog.Count) tagged application(s) to $OutputPath."