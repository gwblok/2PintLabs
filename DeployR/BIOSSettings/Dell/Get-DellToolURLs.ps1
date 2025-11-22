<#
.SYNOPSIS
    Get Dell tools information from the mkaptano/tools GitHub repository.

.DESCRIPTION
    This function reads the Dell tools markdown table from GitHub and returns
    structured PowerShell objects containing tool information including:
    - Tool Name
    - Driver ID
    - Version
    - Release Date
    - Auto-Update Availability
    - Download Link
    - Comments

.PARAMETER IncludeNA
    Include tools where Driver ID or other fields are marked as "na" or not applicable.

.EXAMPLE
    Get-DellToolURLs
    Returns all Dell tools with their details.

.EXAMPLE
    Get-DellToolURLs | Where-Object {$_.ToolName -like "*Command*"}
    Get only Dell Command tools.

.EXAMPLE
    Get-DellToolURLs | Where-Object {$_.AutoUpdate -eq "yes"}
    Get tools that support auto-update.

.EXAMPLE
    Get-DellToolURLs | Export-Csv -Path "C:\Temp\DellTools.csv" -NoTypeInformation
    Export the tool list to CSV.

.NOTES
    Source: https://github.com/mkaptano/tools
    Maintained by: Mesut Kaptanoğlu (Dell Product Manager)
#>

function Get-DellToolURLs {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeNA
    )

    $url = "https://raw.githubusercontent.com/mkaptano/tools/refs/heads/main/README.md"
    
    try {
        Write-Verbose "Fetching Dell tools information from GitHub..."
        $content = Invoke-RestMethod -Uri $url -UseBasicParsing -ErrorAction Stop
        
        # Split content into lines
        $lines = $content -split "`n"
        
        # Find the table start (header row with columns)
        $tableStartIndex = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '\|Dell Tool\s*\|\s*Driver ID\s*\|') {
                $tableStartIndex = $i
                break
            }
        }
        
        if ($tableStartIndex -eq -1) {
            throw "Could not find the Dell tools table in the markdown"
        }
        
        # Skip header and separator rows
        $dataStartIndex = $tableStartIndex + 2
        
        $tools = @()
        
        # Parse each row
        for ($i = $dataStartIndex; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()
            
            # Skip empty lines or lines that don't look like table rows
            if ([string]::IsNullOrWhiteSpace($line) -or $line -notmatch '^\|.*\|$') {
                continue
            }
            
            # Skip if it's a section header (like "# tools")
            if ($line -match '^#') {
                continue
            }
            
            # Split by pipe and clean up
            $columns = $line -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            
            # Need at least 6 columns (Tool, ID, Version, Date, AutoUpdate, Link, Comments)
            if ($columns.Count -lt 6) {
                continue
            }
            
            # Extract tool name (remove markdown bold markers ***)
            $toolName = $columns[0] -replace '\*\*\*', '' -replace '\*\*', ''
            
            # Skip if tool name is empty or looks like a header
            if ([string]::IsNullOrWhiteSpace($toolName) -or $toolName -eq 'Dell Tool') {
                continue
            }
            
            $driverID = $columns[1].Trim()
            $version = $columns[2].Trim()
            $releaseDate = $columns[3].Trim()
            $autoUpdate = $columns[4].Trim()
            
            # Extract URL from markdown link format [text](url) or plain URL
            $linkText = $columns[5].Trim()
            $downloadLink = if ($linkText -match '\[([^\]]+)\]\(([^\)]+)\)') {
                $matches[2]
            } elseif ($linkText -match 'https?://[^\s]+') {
                $matches[0]
            } else {
                $linkText
            }
            
            # Comments might be in column 6 if present
            $comments = if ($columns.Count -ge 7) {
                $columns[6].Trim()
            } else {
                ''
            }
            
            # Remove markdown link formatting from comments
            $comments = $comments -replace '\[([^\]]+)\]\(([^\)]+)\)', '$1 ($2)'
            
            # Skip rows marked as "na" if IncludeNA is not set
            if (-not $IncludeNA -and $driverID -eq 'na') {
                Write-Verbose "Skipping tool with no Driver ID: $toolName"
                continue
            }
            
            # Create object
            $tool = [PSCustomObject]@{
                ToolName = $toolName
                DriverID = $driverID
                Version = $version
                ReleaseDate = $releaseDate
                AutoUpdate = $autoUpdate
                DownloadLink = $downloadLink
                Comments = $comments
                DirectDriverUrl = if ($driverID -ne 'na') {
                    "https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=$driverID"
                } else {
                    $null
                }
            }
            
            $tools += $tool
            Write-Verbose "Parsed: $toolName (v$version)"
        }
        
        if ($tools.Count -eq 0) {
            Write-Warning "No tools were parsed from the table. The format may have changed."
        } else {
            Write-Verbose "Successfully parsed $($tools.Count) Dell tools"
        }
        
        return $tools
    }
    catch {
        Write-Error "Failed to retrieve Dell tools information: $_"
        return $null
    }
}

# Example usage and helper functions

function Get-DellToolByName {
    <#
    .SYNOPSIS
        Get a specific Dell tool by name (supports wildcards).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    Get-DellToolURLs | Where-Object { $_.ToolName -like "*$Name*" }
}

function Get-LatestDellCommandConfigure {
    <#
    .SYNOPSIS
        Get the latest Dell Command Configure tool information.
    #>
    [CmdletBinding()]
    param()
    
    Get-DellToolURLs | Where-Object { $_.ToolName -like "*Command Configure*" }
}

function Get-DellToolsWithAutoUpdate {
    <#
    .SYNOPSIS
        Get all Dell tools that support auto-update.
    #>
    [CmdletBinding()]
    param()
    
    Get-DellToolURLs | Where-Object { $_.AutoUpdate -eq 'yes' }
}

# Export functions
#Export-ModuleMember -Function Get-DellToolURLs, Get-DellToolByName, Get-LatestDellCommandConfigure, Get-DellToolsWithAutoUpdate
