#TO DO: add the ability for when looking at the TS to grab all of the referenced step definitions used.

<#
.SYNOPSIS
Interactive backup script for DeployR content items.

.DESCRIPTION
Connects to DeployR and provides an interactive menu to select content types
(Applications, Task Sequences, OS Packages, Driver Packs, etc.) and specific
items to backup to a configured location.

.PARAMETER BackupPath
The root directory where backups will be stored.
Default: D:\DeployRBackups

.EXAMPLE
.\Backup-DeployRContent.ps1

.EXAMPLE
.\Backup-DeployRContent.ps1 -BackupPath "C:\Backups\DeployR"

.NOTES
Author: Gary Blok
Date: December 18, 2025
Requires: DeployR.Utility module
#>

[CmdletBinding()]
param(
[Parameter()]
[string]$BackupPath = "D:\DeployRBackups",

[Parameter()]
[string]$ReferenceJsonPath,

[Parameter()]
[object]$ReferenceJsonObject
)

#region Functions

function Connect-ToDeployR {
    try {
        # Check if module is available
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
        #Set-DeployRHost "http://localhost:7282"
        
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

 
function Get-DeployRContentReferences {
    [CmdletBinding(DefaultParameterSetName = "Path")]
    param(
    [Parameter(Mandatory = $true, ParameterSetName = "Path")]
    [string]$JsonFilePath,
    
    [Parameter(Mandatory = $true, ParameterSetName = "Object")]
    [object]$JsonObject,
    
    [Parameter(Mandatory = $false)]
    [switch]$ExportResults
    )
    
    # Load JSON based on input mode
    if ($PSCmdlet.ParameterSetName -eq "Path") {
        if (-not (Test-Path $JsonFilePath)) {
            Write-Error "File not found: $JsonFilePath"
            return $null
        }
        Write-Verbose "Loading JSON file: $JsonFilePath"
        $jsonContent = Get-Content $JsonFilePath -Raw | ConvertFrom-Json
        $sourceLabel = $JsonFilePath
    }
    else {
        if (-not $JsonObject) {
            Write-Error "JsonObject is null or empty."
            return $null
        }
        $jsonContent = $JsonObject
        $sourceLabel = "ObjectInput"
    }
    
    # Normalize to array of items
    if ($jsonContent -is [array]) { $items = $jsonContent } else { $items = @($jsonContent) }
    
    # Filter: we only care about objects that have versions with steps
    $items = $items | Where-Object { $_.versions -and $_.versions.Count -gt 0 }
    
    # Collector
    $allExtracted = @()
    
    filter Extract-StepReferences {
        param(
        [Parameter(ValueFromPipeline = $true)]
        [object]$Step,
        
        [Parameter(Mandatory = $false)]
        [int]$DepthLevel = 0
        )
        
        if ($null -eq $Step) { return }
        
        $indent = "  " * $DepthLevel
        $stepName = $Step.name
        $stepId = $Step.id
        $typeId = $Step.typeId
        
        # Emit step summary
        [PSCustomObject]@{
            Type       = "Step"
            Name       = $stepName
            Id         = $stepId
            TypeId     = $typeId
            IsGroup    = $Step.isGroup
            DepthLevel = $DepthLevel
            Enabled    = $Step.enabled
        }
        
        # Child task sequence
        if ($typeId -eq "00000001-0000-0000-0000-00000000000d" -and $Step.settings -and $Step.settings.childTaskSequenceId) {
            $childTsId = $Step.settings.childTaskSequenceId.Split(':')[0]
            Write-Verbose "${indent}[Child TS] $stepName -> $childTsId"
            [PSCustomObject]@{
                Type                = "ChildTaskSequence"
                StepName            = $stepName
                StepId              = $stepId
                ChildTaskSequenceId = $childTsId
                DepthLevel          = $DepthLevel
                TypeId              = $typeId
            }
        }
        
        # Content references
        if ($Step.contentItems) {
            $props = $Step.contentItems | Get-Member -MemberType NoteProperty
            foreach ($p in $props) {
                $propertyName = $p.Name
                $propertyValue = $Step.contentItems.$propertyName
                if ($propertyValue) {
                    $contentId = $propertyValue.Split(':')[0]
                    Write-Verbose "${indent}[Content] $stepName -> $propertyName : $contentId"
                    [PSCustomObject]@{
                        Type          = "ContentReference"
                        StepName      = $stepName
                        StepId        = $stepId
                        PropertyName  = $propertyName
                        ContentId     = $contentId
                        FullValue     = $propertyValue
                        DepthLevel    = $DepthLevel
                        TypeId        = $typeId
                    }
                }
            }
        }
        
        # Recurse group members
        if ($Step.groupMembers -and $Step.groupMembers.Count -gt 0) {
            Write-Verbose "${indent}[Group] $($Step.groupMembers.Count) member(s)"
            $Step.groupMembers | Extract-StepReferences -DepthLevel ($DepthLevel + 1)
        }
    }
    
    # Process items
    foreach ($item in $items) {
        foreach ($version in $item.versions) {
            if ($version.steps) {
                $allExtracted += @($version.steps | Extract-StepReferences -DepthLevel 1)
            }
        }
    }
    
    # Separate results
    $stepSummary = @($allExtracted | Where-Object { $_.Type -eq "Step" })
    $allContentReferences = @($allExtracted | Where-Object { $_.Type -eq "ContentReference" })
    $allTaskSequenceReferences = @($allExtracted | Where-Object { $_.Type -eq "ChildTaskSequence" })
    
    # Flattened unique IDs for easy downstream use (e.g. backup)
    $contentIdsUnique = @($allContentReferences.ContentId | Where-Object { $_ } | Select-Object -Unique)
    $childTaskSequenceIdsUnique = @($allTaskSequenceReferences.ChildTaskSequenceId | Where-Object { $_ } | Select-Object -Unique)
    
    # Build results object
    $results = [PSCustomObject]@{
        ExportDate              = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Source                  = $sourceLabel
        TotalSteps              = $stepSummary.Count
        TotalContentReferences  = $allContentReferences.Count
        TotalTaskSequences      = $allTaskSequenceReferences.Count
        ContentReferences       = $allContentReferences
        TaskSequenceReferences  = $allTaskSequenceReferences
        StepSummary             = $stepSummary
        ContentIds              = $contentIdsUnique
        ChildTaskSequenceIds    = $childTaskSequenceIdsUnique
    }
    
    # Export results to JSON if requested
    if ($ExportResults) {
        $outputPath = "$([System.IO.Path]::GetDirectoryName($JsonFilePath))\ParsedReferences.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding UTF8
        Write-Host "Results exported to: $outputPath" -ForegroundColor Green
    }
    
    # Print summary
    Write-Host ""
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "SUMMARY REPORT" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "STATISTICS" -ForegroundColor Yellow
    Write-Host "  Total Steps Found: $($stepSummary.Count)"
    Write-Host "  Total Content References: $($allContentReferences.Count)"
    Write-Host "  Total Child Task Sequences: $($allTaskSequenceReferences.Count)"
    Write-Host ""
    
    if ($allTaskSequenceReferences.Count -gt 0) {
        Write-Host "CHILD TASK SEQUENCE REFERENCES" -ForegroundColor Yellow
        $allTaskSequenceReferences | Format-Table -AutoSize @(
        @{ Label = "Step Name"; Expression = { $_.StepName } },
        @{ Label = "Step ID"; Expression = { $_.StepId } },
        @{ Label = "Child TS ID"; Expression = { $_.ChildTaskSequenceId } },
        @{ Label = "Depth"; Expression = { $_.DepthLevel } }
        )
        Write-Host ""
    }
    
    if ($allContentReferences.Count -gt 0) {
        Write-Host "CONTENT ITEM REFERENCES" -ForegroundColor Yellow
        $allContentReferences | Format-Table -AutoSize @(
        @{ Label = "Step Name"; Expression = { $_.StepName } },
        @{ Label = "Content ID"; Expression = { $_.ContentId } },
        @{ Label = "Property"; Expression = { $_.PropertyName } },
        @{ Label = "Depth"; Expression = { $_.DepthLevel } }
        )
        Write-Host ""
    }
    
    return $results
}

function Backup-DeployRContentItem {
    <#
    .SYNOPSIS
    Backs up a DeployR content item.
    
    .PARAMETER ContentItem
    The content item to backup.
    
    .PARAMETER BackupPath
    The destination path for the backup.
    
    .PARAMETER ContentType
    The type of content being backed up.
    
    .PARAMETER QueryType
    Whether this is a Metadata or ContentItem type.
    #>
    [CmdletBinding()]
    param(
    [Parameter(Mandatory)]
    [object]$ContentItem,
    
    [Parameter(Mandatory)]
    [string]$BackupPath,
    
    [Parameter(Mandatory)]
    [string]$ContentType,
    
    [Parameter(Mandatory)]
    [string]$QueryType
    )
    
    try {
        # Create type-specific subfolder
        $typeFolder = Join-Path -Path $BackupPath -ChildPath $ContentType
        if (-not (Test-Path $typeFolder)) {
            New-Item -ItemType Directory -Path $typeFolder -Force | Out-Null
        }
        
        # Create item folder with name and ID (like your existing script)
        $itemName = $ContentItem.Name -replace '[\\/:*?"<>|]', '_'
        $backupFolder = Join-Path -Path $typeFolder -ChildPath "$itemName-$($ContentItem.Id)"
        
        if (-not (Test-Path $backupFolder)) {
            New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
        }
        
        # Export the content item using appropriate command
        Write-Host "  Backing up: $($ContentItem.Name) | $($ContentItem.Id)..." -ForegroundColor Cyan
        
        if ($QueryType -eq "Metadata") {
            # Use Export-DeployRTaskSequence or Export-DeployRStepDefinition
            if ($ContentType -eq "Task Sequences") {
                Export-DeployRTaskSequence -Id $ContentItem.Id -DestinationFolder $backupFolder -ErrorAction Stop
            }
            elseif ($ContentType -eq "Step Definitions") {
                Export-DeployRStepDefinition -Id $ContentItem.Id -DestinationFolder $backupFolder -ErrorAction Stop
            }
        }
        else {
            # Use Export-DeployRContentItem for all content items
            Export-DeployRContentItem -Id $ContentItem.Id -DestinationFolder $backupFolder -ErrorAction Stop
        }
        
        Write-Host "    ✓ Backed up to: $backupFolder" -ForegroundColor Green
        
        return [PSCustomObject]@{
            Name = $ContentItem.Name
            Id = $ContentItem.Id
            Type = $ContentType
            BackupPath = $backupFolder
            Success = $true
        }
    }
    catch {
        Write-Warning "    ✗ Failed to backup $($ContentItem.Name): $_"
        
        return [PSCustomObject]@{
            Name = $ContentItem.Name
            Id = $ContentItem.Id
            Type = $ContentType
            BackupPath = $null
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

#endregion

#region Main Script

Clear-Host
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  DeployR Content Backup Tool" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Ensure backup path exists
if (-not (Test-Path $BackupPath)) {
    Write-Host "Creating backup directory: $BackupPath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
}
#Create Backup Subfolder with DateTime
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupPath = Join-Path -Path $BackupPath -ChildPath "DeployRBackup_$timestamp"
New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null


Write-Host "Backup Location: $BackupPath" -ForegroundColor White
Write-Host ""

# Connect to DeployR
if (-not (Connect-ToDeployR)) {
    Write-Error "Cannot proceed without DeployR connection."
    exit 1
}

Write-Host ""

# Define content types
$contentTypes = @(
[PSCustomObject]@{ DisplayName = "Applications"; QueryType = "ContentItem"; Purpose = "Application" },
[PSCustomObject]@{ DisplayName = "Task Sequences"; QueryType = "Metadata"; MetadataType = "TaskSequence" },
[PSCustomObject]@{ DisplayName = "OS Packages"; QueryType = "ContentItem"; Purpose = "OperatingSystem" },
[PSCustomObject]@{ DisplayName = "Driver Packs"; QueryType = "ContentItem"; Purpose = "DriverPack" },
[PSCustomObject]@{ DisplayName = "Step Definitions"; QueryType = "Metadata"; MetadataType = "StepDefinition" },
[PSCustomObject]@{ DisplayName = "Other Content"; QueryType = "ContentItem"; Purpose = "Other" }
)

# Select content types to backup
Write-Host "Step 1: Select content types to backup" -ForegroundColor Cyan
Write-Host ""
$selectedTypes = $contentTypes | Out-GridView -Title "Select Content Types to Backup (Hold Ctrl to select multiple)" -OutputMode Multiple

if ($selectedTypes.Count -eq 0) {
    Write-Host "No content types selected. Exiting." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Selected content types:" -ForegroundColor Green
$selectedTypes | ForEach-Object { Write-Host "  • $($_.DisplayName)" -ForegroundColor White }
Write-Host ""
$totalSelectedItems = @()
if ($selectedTypes -contains ($contentTypes | Where-Object { $_.DisplayName -eq "Task Sequences" })) {
    Write-Host "Gathering Task Sequence Information..." -ForegroundColor Yellow
    $DBTaskSequences = Get-DeployRMetadata -Type TaskSequence
    Write-Host "Found $($DBTaskSequences.Count) Task Sequences in DeployR." -ForegroundColor Green
    Write-Host "Select which Task Sequences to backup..." -ForegroundColor Gray
    $totalSelectedTaskSequences = @()
    $totalSelectedTaskSequences += $DBTaskSequences | Out-GridView -Title "Select $($type.DisplayName) to Backup (Hold Ctrl to select multiple)" -OutputMode Multiple
    $totalSelectedItems += $totalSelectedTaskSequences
}
if ($selectedTypes -contains ($contentTypes | Where-Object { $_.DisplayName -eq "Step Definitions" }) ) {
    Write-Host "Gathering Step Definition Information..." -ForegroundColor Yellow
    $DBStepDefinitions = Get-DeployRMetadata -Type StepDefinition | Where-Object{$_.id -notlike '0000*'}
    Write-Host "Found $($DBStepDefinitions.Count) Step Definitions in DeployR." -ForegroundColor Green
    Write-Host "Select which Step Definitions to backup..." -ForegroundColor Gray
    $totalSelectedStepDefinitions = @()
    $totalSelectedStepDefinitions += $DBStepDefinitions | Out-GridView -Title "Select $($type.DisplayName) to Backup (Hold Ctrl to select multiple)" -OutputMode Multiple
    $totalSelectedItems += $totalSelectedStepDefinitions
}
$DBContentItems = Get-DeployRMetadata -Type ContentItem | Where-Object{$_.id -notlike '00000000-*'}
if ($selectedTypes | Where-Object { $_.QueryType -eq "ContentItem" }) {
    Write-Host "Found $($DBContentItems.Count) Content Items in DeployR." -ForegroundColor Green
    Write-Host "We'll now select specific content items for the selected content types." -ForegroundColor Gray
    foreach ($type in $selectedTypes | Where-Object { $_.QueryType -eq "ContentItem" }) {
        Write-Host "Select which $($type.DisplayName) to backup..." -ForegroundColor Gray
        $itemsToSelect = $DBContentItems | Where-Object { $_.contentItemPurpose -match $type.Purpose }
        $totalSelectedItems += $itemsToSelect | Out-GridView -Title "Select $($type.DisplayName) to Backup (Hold Ctrl to select multiple)" -OutputMode Multiple
    }
}

# Optional: pull referenced content/task sequences from an exported JSON
$extraContentFromJsonCombine = @()
$extraChildTsFromJsonCombine = @()
foreach ($ReferenceJsonObject in $totalSelectedTaskSequences){
    if ($ReferenceJsonPath -or $ReferenceJsonObject) {
        $parsedReferences = $null
        $extraContentFromJson = @()
        $extraChildTsFromJson = @()
        if (Get-Command Get-DeployRContentReferences -ErrorAction SilentlyContinue) {
            # Determine which input mode to use
            if ($ReferenceJsonObject) {
                Write-Host "Parsing task sequence object for references..." -ForegroundColor Gray
                $parsedReferences = Get-DeployRContentReferences -JsonObject $ReferenceJsonObject
            }
            elseif ($ReferenceJsonPath) {
                if (-not (Test-Path $ReferenceJsonPath)) {
                    Write-Warning "ReferenceJsonPath not found: $ReferenceJsonPath"
                }
                else {
                    Write-Host "Parsing JSON file for references: $ReferenceJsonPath" -ForegroundColor Gray
                    $parsedReferences = Get-DeployRContentReferences -JsonFilePath $ReferenceJsonPath
                }
            }
            
            # Process parsed results
            if ($parsedReferences) {
                $extraContentIds = $parsedReferences.ContentIds | Where-Object { $_ -and $_ -notlike '00000000-*' }
                $extraChildTsIds = $parsedReferences.ChildTaskSequenceIds | Where-Object { $_ }
                if ($extraContentIds.Count -gt 0) {
                    $extraContentFromJson = $DBContentItems | Where-Object { $extraContentIds -contains $_.id }
                    Write-Host "Including $($extraContentFromJson.Count) content item(s) from JSON references" -ForegroundColor Yellow
                    $extraContentFromJsonCombine += $extraContentFromJson
                }
                if ($extraChildTsIds.Count -gt 0) {
                    if (-not $DBTaskSequences) {
                        $DBTaskSequences = Get-DeployRMetadata -Type TaskSequence
                    }
                    $extraChildTsFromJson = $DBTaskSequences | Where-Object { $extraChildTsIds -contains $_.id }
                    Write-Host "Including $($extraChildTsFromJson.Count) child task sequence(s) from JSON references" -ForegroundColor Yellow
                    $extraChildTsFromJsonCombine += $extraChildTsFromJson
                }
            }
        }
    }
}


# Process each selected content type
$backupResults = @()
$referencedContentToBackup = @()

# Fold in JSON-derived references
if ($extraChildTsFromJsonCombine.Count -gt 0) {
    if (-not $totalSelectedTaskSequences) { $totalSelectedTaskSequences = @() }
    $totalSelectedTaskSequences += $extraChildTsFromJsonCombine
    $totalSelectedTaskSequences = $totalSelectedTaskSequences | Sort-Object id -Unique
}
if ($extraContentFromJsonCombine.Count -gt 0) {
    $referencedContentToBackup += $extraContentFromJsonCombine
    $referencedContentToBackup = $referencedContentToBackup | Sort-Object id -Unique
}

foreach ($type in $selectedTypes) {
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Processing: $($type.DisplayName)" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    # Get content items for this type
    Write-Host "Retrieving $($type.DisplayName) from DeployR..." -ForegroundColor Gray
    
    if ($type.QueryType -eq "Metadata") {
        if ($type.DisplayName -eq "Task Sequences") {
            $selectedItems = $totalSelectedTaskSequences
        }
        elseif ($type.DisplayName -eq "Step Definitions") {
            $selectedItems = $totalSelectedStepDefinitions
        }
    }
    else {
        $selectedItems = $totalSelectedItems | Where-Object { $_.contentItemPurpose -match $type.Purpose }
    }
    
    #backup Content Items here
    
    
    # If Task Sequences are selected, analyze for referenced content
    if ($type.DisplayName -eq "Task Sequences") {
        Write-Host ""
        Write-Host "Analyzing Task Sequences for referenced content..." -ForegroundColor Cyan
        $referencedIds = $referencedContentToBackup.id
        
        if ($referencedIds.Count -gt 0) {
            Write-Host "  Found $($referencedIds.Count) referenced content item(s)" -ForegroundColor Yellow
            
            # Get the full content item details
            $referencedContent = $referencedContentToBackup
            $referencedTaskSequences = $extraChildTsFromJsonCombine
            if ($referencedContent) {
                # Show referenced content to user
                Write-Host ""
                Write-Host "The selected Task Sequences reference the following content items:" -ForegroundColor Yellow
                $referencedContent | ForEach-Object { 
                    Write-Host "  • $($_.name) ($($_.contentItemPurpose))" -ForegroundColor Gray 
                }
                Write-Host ""
                
                # Prompt user to include referenced content in backup
                $userChoice = Read-Host "Would you like to include these referenced content items in the backup? (Y/N)"
                if ($userChoice -eq 'Y' -or $userChoice -eq 'y') {
                    Write-Host "  Referenced content will be included in backup" -ForegroundColor Green
                    $referencedContentToBackup = $referencedContent
                }
                else {
                    Write-Host "  Referenced content will NOT be backed up" -ForegroundColor Yellow
                }
            }
            if ($referencedTaskSequences) {
                Write-Host ""
                Write-Host "The selected Task Sequences also reference the following Task Sequences:" -ForegroundColor Yellow
                $referencedTaskSequences | ForEach-Object { 
                    Write-Host "  • $($_.name)" -ForegroundColor Gray 
                }
                Write-Host "They will also be backed up" -ForegroundColor Yellow
                Write-Host ""
            }
        }
        else {
            Write-Host "  No referenced content found" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "Backing up $($selectedItems.Count) $($type.DisplayName)..." -ForegroundColor Cyan
    Write-Host ""
    
    # Backup each selected item
    foreach ($item in $selectedItems) {
        $result = Backup-DeployRContentItem -ContentItem $item -BackupPath $BackupPath -ContentType $type.DisplayName -QueryType $type.QueryType
        $backupResults += $result
    }
    
    Write-Host ""
}


# Backup any referenced content that was identified from Task Sequences
if ($referencedContentToBackup.Count -gt 0) {
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Backing up Referenced Content from Task Sequences" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Backing up $($referencedContentToBackup.Count) referenced content item(s)..." -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($item in $referencedContentToBackup) {
        # Determine the content type based on purpose
        $contentTypeName = switch ($item.contentItemPurpose) {
            "Application" { "Applications" }
            "OSPackage" { "OS Packages" }
            "DriverPack" { "Driver Packs" }
            default { "Other Content" }
        }
        
        if ($item.id -in $backupResults.Id) {
            Write-Host "  • $($item.name) already backed up, skipping..." -ForegroundColor Gray
            continue
        }   
        $result = Backup-DeployRContentItem -ContentItem $item -BackupPath $BackupPath -ContentType $contentTypeName -QueryType "ContentItem"
        $backupResults += $result
    }
    
    Write-Host ""
}

# Summary
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Backup Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$successCount = ($backupResults | Where-Object { $_.Success -eq $true }).Count
$failCount = ($backupResults | Where-Object { $_.Success -eq $false }).Count

Write-Host "Total Items Backed Up: $successCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "Failed Backups: $failCount" -ForegroundColor Red
}
Write-Host ""
Write-Host "Backup Location: $BackupPath" -ForegroundColor White
Write-Host ""

# Show detailed results
if ($backupResults.Count -gt 0) {
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    $backupResults | Format-Table -Property Name, Type, Success -AutoSize
}

Write-Host "Backup process complete!" -ForegroundColor Green

#endregion
