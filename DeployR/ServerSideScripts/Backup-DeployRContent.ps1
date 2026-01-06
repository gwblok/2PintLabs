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
    [string]$BackupPath = "D:\DeployRBackups"
)

#region Functions

function Connect-ToDeployR {
    <#
    .SYNOPSIS
        Connects to DeployR server.
    #>
    
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

function Get-StepContentReferences {
    <#
    .SYNOPSIS
        Recursively extracts content IDs from a step and its nested groupMembers.
    
    .PARAMETER Step
        The step object to analyze.
    
    .OUTPUTS
        Array of content item IDs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Step
    )
    
    $contentIds = @()
    

    # Extract content IDs from contentItems (PSCustomObject)
    if ($Step.contentItems) {
        # Access the properties of the PSCustomObject
        $Step.contentItems.psobject.Properties | ForEach-Object {
            # Values are in format "ID:1", extract just the ID part
            $contentId = $_.Value.Split(':')[0]
            if ($contentId) {
                $contentIds += $contentId
            }
        }
    }
    

    # Recursively process groupMembers if they exist
    if ($Step.groupMembers -and $Step.groupMembers.Count -gt 0) {
        $script:GroupMember = $Step.groupMembers
        foreach ($groupMember in $Step.groupMembers) {
            Write-Host "Processing nested group member step: $($groupMember.name)" -ForegroundColor Gray
            $contentIds += Get-StepContentReferences -Step $groupMember
        }
    }
    
    return $contentIds
}

function Get-TaskSequenceReferencedContent {
    <#
    .SYNOPSIS
        Analyzes Task Sequences to find all referenced content items at any nesting level.
    
    .PARAMETER TaskSequences
        Array of task sequence objects to analyze.
    
    .OUTPUTS
        Array of content item IDs referenced in the task sequences.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$TaskSequences,
        [object[]]$AllTaskSequences
    )
    
    $referencedContentIds = @()
    $referencedTaskSequences = @()

    foreach ($ts in $TaskSequences) {
        try {
            if ($ts.versions) {
                foreach ($version in $ts.versions) {
                    if ($version.steps) {
                        # Process each top-level step recursively
                        foreach ($step in $version.steps) {
                            #$contentIds = Get-StepContentReferences -Step $step
                            $contentIds = @()
    
                            if ($Step.typeId -eq "00000001-0000-0000-0000-00000000000d") {
                                Write-Host "Processing Child Task Sequence: $($Step.name)" -ForegroundColor Gray
                                $ChildTS = ($Step.settings.childTaskSequenceId).Split(':')[0]
                                $CurrentTaskSequence = $DBTaskSequences | Where-Object {$_.id -eq "$ChildTS"}
                                $referencedTaskSequences += $CurrentTaskSequence
                                Get-TaskSequenceReferencedContent -TaskSequences $CurrentTaskSequence -AllTaskSequences $DBTaskSequences
                            }
                            # Extract content IDs from contentItems (PSCustomObject)
                            if ($Step.contentItems) {
                                # Access the properties of the PSCustomObject
                                $Step.contentItems.psobject.Properties | ForEach-Object {
                                    # Values are in format "ID:1", extract just the ID part
                                    $contentId = $_.Value.Split(':')[0]
                                    if ($contentId) {
                                        $contentIds += $contentId
                                    }
                                }
                            }
                            
                            # Recursively process groupMembers if they exist
                            if ($Step.groupMembers -and $Step.groupMembers.Count -gt 0) {
                                $script:GroupMember = $Step.groupMembers
                                foreach ($groupMember in $Step.groupMembers) {
                                    Write-Host "Processing nested group member step: $($groupMember.name)" -ForegroundColor Gray
                                    if ($groupMember.typeId -eq "00000001-0000-0000-0000-00000000000d") {
                                        Write-Host "Processing Child Task Sequence: $($groupMember.name)" -ForegroundColor Gray
                                        $ChildTS = ($groupMember.settings.childTaskSequenceId).Split(':')[0]
                                        $CurrentTaskSequence = $DBTaskSequences | Where-Object {$_.id -eq "$ChildTS"}
                                        $referencedTaskSequences += $CurrentTaskSequence
                                        Get-TaskSequenceReferencedContent -TaskSequences $CurrentTaskSequence -AllTaskSequences $DBTaskSequences
                                    }
                                    $contentIds += Get-StepContentReferences -Step $groupMember
                                }
                            }
                            # Filter out built-in content IDs
                            foreach ($cid in $contentIds) {
                                if ($cid -and $cid -notlike '00000000-*' -and $cid -notlike '{00000000-*') {
                                    $referencedContentIds += $cid
                                }
                            }
                        }
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to analyze task sequence $($ts.name): $_"
        }
    }
    
    # Return unique IDs
    #Create a PS Object of the referenced Task Sequences & Content Items to return
    $result = [PSCustomObject]@{
        referencedContentIDs = ($referencedContentIds | Select-Object -Unique)
        referenceTaskSequences = ($referencedTaskSequences | Select-Object -Unique)
    }
    
    return $result
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
    [PSCustomObject]@{ DisplayName = "OS Packages"; QueryType = "ContentItem"; Purpose = "OSPackage" },
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
    $totalSelectedTaskSequences = $DBTaskSequences | Out-GridView -Title "Select $($type.DisplayName) to Backup (Hold Ctrl to select multiple)" -OutputMode Multiple
    $totalSelectedItems += $totalSelectedTaskSequences
}
if ($selectedTypes -contains ($contentTypes | Where-Object { $_.DisplayName -eq "Step Definitions" }) ) {
    Write-Host "Gathering Step Definition Information..." -ForegroundColor Yellow
    $DBStepDefinitions = Get-DeployRMetadata -Type StepDefinition | Where-Object{$_.id -notlike '0000*'}
    Write-Host "Found $($DBStepDefinitions.Count) Step Definitions in DeployR." -ForegroundColor Green
    Write-Host "Select which Step Definitions to backup..." -ForegroundColor Gray
    $totalSelectedStepDefinitions = $DBStepDefinitions | Out-GridView -Title "Select $($type.DisplayName) to Backup (Hold Ctrl to select multiple)" -OutputMode Multiple
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



# Process each selected content type
$backupResults = @()
$referencedContentToBackup = @()

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
        $referencedIds = Get-TaskSequenceReferencedContent -TaskSequences $selectedItems -AllTaskSequences $DBTaskSequences
        
        if ($referencedIds.Count -gt 0) {
            Write-Host "  Found $($referencedIds.Count) referenced content item(s)" -ForegroundColor Yellow
            
            # Get the full content item details
            $allContentItems = $DBContentItems #Get-DeployRContentItem -ErrorAction SilentlyContinue
            $referencedContent = $allContentItems | Where-Object { $referencedIds -contains $_.id }
            
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
                    $referencedContentToBackup += $referencedContent
                }
                else {
                    Write-Host "  Referenced content will NOT be backed up" -ForegroundColor Yellow
                }
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
    catch {
        Write-Warning "Failed to retrieve $($type.DisplayName): $_"
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
