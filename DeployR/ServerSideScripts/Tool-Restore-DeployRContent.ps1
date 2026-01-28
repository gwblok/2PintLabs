#TO DO: add the ability for when looking at the TS to grab all of the referenced step definitions used.

<#
.SYNOPSIS
Interactive restore script for DeployR content items.

.DESCRIPTION
Connects to DeployR, inspects a backup set created by Tool-Backup-DeployRContent.ps1,
and imports each item (step definitions, content items, and task sequences) in a
safe order. If a content item already exists, its versions are updated instead of
re-created.

.PARAMETER BackupPath
The root directory where backups are stored or the specific backup set folder
(DeployRBackup_yyyyMMdd_HHmmss). Defaults to D:\DeployRBackups and automatically
selects the newest DeployRBackup_* child if a set is not specified.

.EXAMPLE
.\Tool-Restore-DeployRContent.ps1

.EXAMPLE
.\Tool-Restore-DeployRContent.ps1 -BackupPath "E:\Backups\DeployRBackup_20260101_120000"

.NOTES
Author: Gary Blok
Date: January 9, 2026
Requires: DeployR.Utility module
#>

[CmdletBinding()]
param(
[Parameter()]
[string]$BackupPath = "D:\DeployRBackups"
)

#region Functions

function Connect-ToDeployR {
    try {
        if (Test-Path 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility') {
            Import-Module 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility' -ErrorAction Stop
        }
        elseif (Get-Module -ListAvailable -Name DeployR.Utility) {
            Import-Module DeployR.Utility -ErrorAction Stop
        }
        else {
            throw "DeployR.Utility module not found. Please ensure DeployR Client is installed."
        }
        
        Write-Host "Connecting to DeployR..." -ForegroundColor Cyan
        Import-Module 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
        
        if (Test-Path "HKLM:\software\2Pint Software\DeployR\GeneralSettings") {
            $DeployRReg = Get-Item -Path "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"
            $ClientPasscode = $DeployRReg.GetValue("ClientPasscode")
            Connect-DeployR -Passcode $ClientPasscode -ErrorAction Stop
        }
        elseif (Test-Path "D:\DeployRPasscode.txt") {
            $ClientPasscode = (Get-Content "D:\DeployRPasscode.txt" -Raw)
            Connect-DeployR -Passcode $ClientPasscode -ErrorAction Stop
        }
        else {
            throw "Cannot find DeployR Client Passcode in registry or D:\DeployRPasscode.txt"
            Connect-DeployR
        }
        
        Write-Host "Connected to DeployR" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to connect to DeployR: $_"
        return $false
    }
}

function Resolve-BackupFolder {
    param(
    [Parameter(Mandatory)]
    [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Backup path not found: $Path"
    }

    $candidate = Get-Item -LiteralPath $Path
    $typeMarkers = @("Applications", "OS Packages", "Driver Packs", "Step Definitions", "Task Sequences", "Other Content")
    $hasMarkers = $typeMarkers | Where-Object { Test-Path (Join-Path -Path $candidate.FullName -ChildPath $_) }

    if ($hasMarkers.Count -gt 0) {
        return $candidate.FullName
    }

    $childBackups = Get-ChildItem -Path $candidate.FullName -Directory | Where-Object { $_.Name -like "DeployRBackup_*" } | Sort-Object LastWriteTime -Descending
    if ($childBackups.Count -gt 0) {
        Write-Host "Using latest backup set: $($childBackups[0].FullName)" -ForegroundColor Yellow
        return $childBackups[0].FullName
    }

    throw "Backup folder does not contain a DeployR backup set: $Path"
}

function Import-StepDefinitions {
    param(
    [Parameter(Mandatory)]
    [string]$FolderPath
    )

    $results = @()
    Get-ChildItem -Path $FolderPath -Directory | ForEach-Object {
        $stepFolder = $_.FullName
        $definitionFile = Get-ChildItem -Path $stepFolder -Filter *.json -File | Select-Object -First 1
        if (-not $definitionFile) {
            Write-Warning "No step definition file found in $stepFolder"
            return
        }

        Write-Host "Importing step definition from: $($definitionFile.FullName)" -ForegroundColor Cyan
        try {
            Import-DeployRStepDefinition -SourceFile $definitionFile.FullName -Force -ErrorAction Stop | Out-Null
            $results += [PSCustomObject]@{ Name = $_.Name; Type = "StepDefinition"; Path = $definitionFile.FullName; Success = $true }
        }
        catch {
            Write-Warning "Failed to import step definition $($definitionFile.FullName): $($_.Exception.Message)"
            $results += [PSCustomObject]@{ Name = $_.Name; Type = "StepDefinition"; Path = $definitionFile.FullName; Success = $false; Error = $_.Exception.Message }
        }
    }

    return $results
}

function Update-ContentVersions {
    param(
    [Parameter(Mandatory)]
    [string]$ContentId,
    [Parameter(Mandatory)]
    [string]$ItemFolder
    )

    $versionFolders = Get-ChildItem -Path $ItemFolder -Directory
    foreach ($version in $versionFolders) {
        try {
            Write-Host "  Updating content version $($version.Name)" -ForegroundColor DarkGray
            Update-DeployRContentItemContent -ContentId $ContentId -SourceFolder $version.FullName -ContentVersion $version.Name -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Warning "  Failed to update version $($version.Name) for $ContentId : $($_.Exception.Message)"
        }
    }
}

function Import-ContentItems {
    param(
    [Parameter(Mandatory)]
    [string]$FolderPath,
    [Parameter(Mandatory)]
    [string]$Label
    )

    $results = @()
    Get-ChildItem -Path $FolderPath -Directory | ForEach-Object {
        $itemFolder = $_.FullName
        $contentFile = Get-ChildItem -Path $itemFolder -Filter *.json -File | Select-Object -First 1
        if (-not $contentFile) {
            Write-Warning "No content JSON found in $itemFolder"
            return
        }

        $contentJson = Get-Content -Path $contentFile.FullName -Raw | ConvertFrom-Json
        $contentId = $contentJson.id
        $contentName = $contentJson.name

        Write-Host "[$Label] $contentName | $contentId" -ForegroundColor Cyan

        $exists = $null
        try {
            $exists = Get-DeployRContentItem -Id $contentId -ErrorAction SilentlyContinue
        }
        catch {
            $exists = $null
        }

        try {
            if ($exists) {
                Write-Host "  Content item exists, updating versions" -ForegroundColor Yellow
                Update-ContentVersions -ContentId $contentId -ItemFolder $itemFolder
                $action = "Update"
            }
            else {
                Write-Host "  Importing new content item" -ForegroundColor Green
                Import-DeployRContentItem -SourceFile $contentFile.FullName -Force -ErrorAction Stop | Out-Null
                Update-ContentVersions -ContentId $contentId -ItemFolder $itemFolder
                $action = "Import"
            }

            $results += [PSCustomObject]@{ Name = $contentName; Id = $contentId; Type = $Label; Path = $itemFolder; Success = $true; Action = $action }
        }
        catch {
            Write-Warning "  Failed to import/update $contentName ($contentId): $($_.Exception.Message)"
            $results += [PSCustomObject]@{ Name = $contentName; Id = $contentId; Type = $Label; Path = $itemFolder; Success = $false; Error = $_.Exception.Message }
        }
    }

    return $results
}

function Import-TaskSequences {
    param(
    [Parameter(Mandatory)]
    [string]$FolderPath
    )

    $results = @()
    Get-ChildItem -Path $FolderPath -Directory | ForEach-Object {
        $tsFolder = $_.FullName
        $tsFile = Get-ChildItem -Path $tsFolder -Filter *.json -File | Select-Object -First 1
        if (-not $tsFile) {
            Write-Warning "No task sequence JSON found in $tsFolder"
            return
        }

        $tsJson = Get-Content -Path $tsFile.FullName -Raw | ConvertFrom-Json
        $tsId = $tsJson.id
        $tsName = $tsJson.name

        Write-Host "[Task Sequence] $tsName | $tsId" -ForegroundColor Cyan
        try {
            Import-DeployRTaskSequence -SourceFile $tsFile.FullName -Force -ErrorAction Stop | Out-Null
            $results += [PSCustomObject]@{ Name = $tsName; Id = $tsId; Type = "TaskSequence"; Path = $tsFolder; Success = $true }
        }
        catch {
            Write-Warning "  Failed to import task sequence $tsName ($tsId): $($_.Exception.Message)"
            $results += [PSCustomObject]@{ Name = $tsName; Id = $tsId; Type = "TaskSequence"; Path = $tsFolder; Success = $false; Error = $_.Exception.Message }
        }
    }

    return $results
}

#endregion

#region Main Script

Clear-Host
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  DeployR Content Restore Tool" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

try {
    $resolvedBackup = Resolve-BackupFolder -Path $BackupPath
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

Write-Host "Backup Set: $resolvedBackup" -ForegroundColor White
Write-Host ""

if (-not (Connect-ToDeployR)) {
    Write-Error "Cannot proceed without DeployR connection."
    exit 1
}

$importPlan = @(
    @{ Name = "Step Definitions"; Path = Join-Path -Path $resolvedBackup -ChildPath "Step Definitions"; Handler = { Import-StepDefinitions -FolderPath $args[0] } },
    @{ Name = "Applications"; Path = Join-Path -Path $resolvedBackup -ChildPath "Applications"; Handler = { Import-ContentItems -FolderPath $args[0] -Label "Applications" } },
    @{ Name = "OS Packages"; Path = Join-Path -Path $resolvedBackup -ChildPath "OS Packages"; Handler = { Import-ContentItems -FolderPath $args[0] -Label "OS Packages" } },
    @{ Name = "Driver Packs"; Path = Join-Path -Path $resolvedBackup -ChildPath "Driver Packs"; Handler = { Import-ContentItems -FolderPath $args[0] -Label "Driver Packs" } },
    @{ Name = "Other Content"; Path = Join-Path -Path $resolvedBackup -ChildPath "Other Content"; Handler = { Import-ContentItems -FolderPath $args[0] -Label "Other Content" } },
    @{ Name = "Task Sequences"; Path = Join-Path -Path $resolvedBackup -ChildPath "Task Sequences"; Handler = { Import-TaskSequences -FolderPath $args[0] } }
)

Write-Host "Scanning backup set..." -ForegroundColor Cyan
$available = $importPlan | Where-Object { Test-Path $_.Path }
if ($available.Count -eq 0) {
    Write-Error "No known content folders found under $resolvedBackup"
    exit 1
}

foreach ($item in $available) {
    $itemCount = (Get-ChildItem -Path $item.Path -Directory -ErrorAction SilentlyContinue).Count
    Write-Host "  • $($item.Name): $itemCount item folder(s)" -ForegroundColor Gray
}

Write-Host "" 
Write-Host "Starting import in dependency order (steps -> content -> task sequences)..." -ForegroundColor Cyan
Write-Host ""

$restoreResults = @()
foreach ($item in $available) {
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Importing $($item.Name)" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    $restoreResults += & $item.Handler $item.Path
    Write-Host ""
}

$successCount = ($restoreResults | Where-Object { $_.Success }).Count
$failCount = ($restoreResults | Where-Object { -not $_.Success }).Count

Write-Host "Restore complete." -ForegroundColor Green
Write-Host "  Imported/updated: $successCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  Failed: $failCount" -ForegroundColor Red
    $faileditems = ($restoreResults | Where-Object { -not $_.Success })
    foreach ($fail in $faileditems) {
        Write-Host "    • $($fail.Type): $($fail.Name) - Error: $($fail.Error)" -ForegroundColor Red
    }
}

if ($restoreResults.Count -gt 0) {
    Write-Host "" 
    Write-Host "Details:" -ForegroundColor Cyan
    $restoreResults | Format-Table -Property Name, Type, Success, Action -AutoSize
}

#endregion
