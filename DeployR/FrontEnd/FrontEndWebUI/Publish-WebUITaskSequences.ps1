[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'tasksequences.json'),

    [string]$Tag = 'FrontEnd'
)

$ErrorActionPreference = 'Stop'
$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    throw "WebUI output directory does not exist: $outputDirectory"
}

if (-not (Get-Command Get-DeployRMetadata -ErrorAction SilentlyContinue)) {
    $clientModule = 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
    if (Test-Path -LiteralPath $clientModule) {
        Import-Module $clientModule -ErrorAction Stop
    } else {
        Import-Module DeployR.Utility -ErrorAction Stop
    }
}

$taskSequences = @(Get-DeployRMetadata -Type TaskSequence -ErrorAction Stop)
if ($taskSequences.Count -eq 0) {
    throw 'DeployR returned no task sequences; keeping the last published catalog.'
}

$catalog = @(
    foreach ($taskSequence in $taskSequences) {
        if (@($taskSequence.Tags) -notcontains $Tag) { continue }
        $sequenceId = [guid]::Empty
        if (-not [guid]::TryParse([string]$taskSequence.Id, [ref]$sequenceId)) {
            throw "Task sequence '$($taskSequence.Name)' has an invalid DeployR ID."
        }
        [pscustomobject]@{
            id = [string]$taskSequence.Id
            displayName = [string]$taskSequence.Name
        }
    }
)

$json = ConvertTo-Json -InputObject $catalog -Depth 3 -Compress
$temporaryPath = Join-Path $outputDirectory ('.tasksequences-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $OutputPath -Force
} finally {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
}

Write-Host "Published $($catalog.Count) tagged task sequence(s) to $OutputPath."