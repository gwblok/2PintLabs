<#
.SYNOPSIS
    Parses DeployR JSON export to extract all content and task sequence references.

.DESCRIPTION
    This script contains a function that reads a DeployR JSON export file and extracts:
    - All content item references from steps
    - All child task sequence references (typeId = 00000001-0000-0000-0000-00000000000d)
    - Handles nested group members at any depth

.EXAMPLE
    . "d:\GitHub\2PintLabs\Parse-DeployRContent.ps1"
    $results = Get-DeployRContentReferences -JsonFilePath "d:\test.json"

.NOTES
    Author: Gary Blok
    Date: January 7, 2026
#>

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
