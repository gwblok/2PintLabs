param(
    [string]$FilePath   = "C:\Users\GaryBlok\Downloads\IPXEAnywhere35.sql",
    [string]$TableName  = "dbo.RequestStatusInfo",
    [string]$OutputFile = "C:\Users\GaryBlok\Downloads\IPXEAnywhere35_Extracted_$($TableName.Replace('.','_')).sql",
    [int]   $TopRows    = 10   # 0 = all rows; set to e.g. 10 to return first 10
)

function Get-SqlTableRows {
    <#
    .SYNOPSIS
        Parses INSERT lines from a SQL Server script export and returns rows as objects.
    .PARAMETER Lines
        The collected lines (CREATE TABLE + INSERTs) already filtered to one table.
    .PARAMETER Columns
        Ordered list of column names from the CREATE TABLE block.
    .PARAMETER Top
        Return at most this many rows. 0 = all rows.
    #>
    param(
        [string[]]$Lines,
        [string[]]$Columns,
        [int]$Top = 0
    )

    # SSMS exports INSERTs as:
    #   INSERT [dbo].[Table] ([Col1], [Col2], ...) VALUES (val1, val2, ...)
    # Values can be: NULL, numeric literals, N'string', 'string', 0x hex blobs
    $rowCount = 0
    foreach ($line in $Lines) {
        if ($line -notmatch 'INSERT\s+(?:INTO\s+)?\[?.+?\]?\.\[?.+?\]?\s*\(') { continue }

        # Extract the VALUES(...) portion
        if ($line -notmatch 'VALUES\s*\((.+)\)\s*$') { continue }
        $valuesRaw = $Matches[1]

        # Tokenise values — handle: NULL, numbers, N'...' strings, 0x... blobs
        $values = [System.Collections.Generic.List[string]]::new()
        $pos    = 0
        while ($pos -lt $valuesRaw.Length) {
            # Skip leading whitespace/comma
            while ($pos -lt $valuesRaw.Length -and $valuesRaw[$pos] -in @(' ', ',')) { $pos++ }
            if ($pos -ge $valuesRaw.Length) { break }

            if ($valuesRaw[$pos] -eq 'N' -and $pos+1 -lt $valuesRaw.Length -and $valuesRaw[$pos+1] -eq "'") {
                # N'string' — skip the N then fall through to string parsing
                $pos++
            }

            if ($valuesRaw[$pos] -eq "'") {
                # Quoted string — handle escaped '' inside
                $pos++  # skip opening quote
                $sb = [System.Text.StringBuilder]::new()
                while ($pos -lt $valuesRaw.Length) {
                    if ($valuesRaw[$pos] -eq "'" -and $pos+1 -lt $valuesRaw.Length -and $valuesRaw[$pos+1] -eq "'") {
                        [void]$sb.Append("'"); $pos += 2
                    } elseif ($valuesRaw[$pos] -eq "'") {
                        $pos++; break
                    } else {
                        [void]$sb.Append($valuesRaw[$pos]); $pos++
                    }
                }
                $values.Add($sb.ToString())
            } else {
                # Unquoted token (NULL, number, 0x hex, GETDATE(), etc.)
                $start = $pos
                while ($pos -lt $valuesRaw.Length -and $valuesRaw[$pos] -ne ',') { $pos++ }
                $values.Add($valuesRaw.Substring($start, $pos - $start).Trim())
            }
        }

        # Build an ordered hashtable mapping column->value
        $row = [ordered]@{}
        for ($i = 0; $i -lt $Columns.Count; $i++) {
            $row[$Columns[$i]] = if ($i -lt $values.Count) { $values[$i] } else { $null }
        }
        [PSCustomObject]$row

        $rowCount++
        if ($Top -gt 0 -and $rowCount -ge $Top) { break }
    }
}

function Get-BootStartsByMonth {
    <#
    .SYNOPSIS
        Summarizes boot starts by month for the last year of data.
    .PARAMETER Rows
        Parsed row objects from Get-SqlTableRows.
    .PARAMETER DateProperty
        The date property to evaluate. Defaults to BootStartDate.
    .PARAMETER MonthsBack
        Number of months to include, including the current month.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [psobject[]]$Rows,
        [string]$DateProperty = 'BootStartDate',
        [ValidateRange(1, 120)]
        [int]$MonthsBack = 12
    )

    if (-not $Rows -or $Rows.Count -eq 0) {
        return @()
    }

    $availableProps = $Rows[0].PSObject.Properties.Name
    if ($availableProps -notcontains $DateProperty) {
        throw "Property '$DateProperty' was not found on the parsed rows."
    }

    $now = Get-Date
    $startMonth = (Get-Date -Year $now.Year -Month $now.Month -Day 1).AddMonths(-($MonthsBack - 1))
    $parsedDates = [System.Collections.Generic.List[datetime]]::new()

    foreach ($row in $Rows) {
        $value = $row.$DateProperty
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value) -or $value -eq 'NULL') {
            continue
        }

        $parsedDate = $null
        if ($value -is [datetime]) {
            $parsedDate = $value
        } else {
            try {
                $parsedDate = [datetime]::Parse([string]$value)
            } catch {
                continue
            }
        }

        if ($parsedDate -ge $startMonth) {
            $parsedDates.Add($parsedDate)
        }
    }

    $report = foreach ($i in 0..($MonthsBack - 1)) {
        $monthStart = $startMonth.AddMonths($i)
        $nextMonthStart = $monthStart.AddMonths(1)
        $count = ($parsedDates | Where-Object { $_ -ge $monthStart -and $_ -lt $nextMonthStart }).Count

        [PSCustomObject]@{
            Month = $monthStart.ToString('yyyy-MM')
            MonthName = $monthStart.ToString('yyyy MMM')
            Count = $count
        }
    }

    return $report
}

# Match both [dbo].[RequestStatusInfo] and dbo.RequestStatusInfo (SQL Server export formats)
$schema, $table = $TableName -split '\.', 2
$tablePattern = "(\[$schema\]\.\[$table\]|$([regex]::Escape($TableName)))"

$inCreateBlock   = $false
$createTableSeen = $false
$output          = [System.Collections.Generic.List[string]]::new()

foreach ($line in (Get-Content $FilePath -Encoding UTF8)) {

    # Start collecting at the SSMS object comment or at CREATE TABLE
    if (-not $inCreateBlock) {
        if ($line -match "Object:\s+Table\s+$tablePattern" -or
            $line -match "CREATE TABLE\s+$tablePattern") {
            $inCreateBlock   = $true
            $createTableSeen = $line -match "CREATE TABLE\s+$tablePattern"
        }
    }

    # Collect the CREATE TABLE schema block
    if ($inCreateBlock) {
        $output.Add($line)

        if ($line -match "CREATE TABLE\s+$tablePattern") { $createTableSeen = $true }

        # End the schema block on the first GO after the CREATE TABLE line
        if ($createTableSeen -and $line.Trim() -eq 'GO') {
            $inCreateBlock   = $false
            $createTableSeen = $false
        }
    }

    # Collect INSERT statements for this table wherever they appear in the file
    if (-not $inCreateBlock -and $line -match "INSERT\s+(INTO\s+)?$tablePattern") {
        $output.Add($line)
    }
}

if ($output.Count -gt 0) {
    $output | Set-Content $OutputFile -Encoding UTF8
    Write-Host "Extracted $($output.Count) lines for '$TableName'"
    Write-Host "Output: $OutputFile"

    # Parse column names from the CREATE TABLE block
    # SQL Server exports each column as:  [ColumnName] [datatype] NULL/NOT NULL,
    $inCreate  = $false
    $columns   = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $output) {
        if ($line -match "CREATE TABLE\s+$tablePattern") { $inCreate = $true; continue }
        if ($inCreate) {
            if ($line.Trim() -match '^\)') { break }                         # end of column list
            if ($line.Trim() -match '^\[(.+?)\]\s+\[') {                    # column definition line
                $columns.Add($Matches[1])
            }
        }
    }

    if ($columns.Count -gt 0) {
        Write-Host "`nColumns in '$TableName' ($($columns.Count) total):"
        $columns | ForEach-Object { Write-Host "  $_" }

        if ($TopRows -ne 0 -or ($output | Where-Object { $_ -match 'INSERT' })) {
            $allRows = Get-SqlTableRows -Lines $output -Columns $columns -Top 0
            $label = if ($TopRows -gt 0) { "first $TopRows" } else { "all" }
            Write-Host "`nReturning $label rows from '$TableName':"
            $rows = if ($TopRows -gt 0) { $allRows | Select-Object -First $TopRows } else { $allRows }
            $rows | Format-Table -AutoSize

            if ($allRows -and $columns -contains 'BootStartDate') {
                Write-Host "`nDiagnosing BootStartDate column:" -ForegroundColor Yellow
                Write-Host "  Total rows parsed: $($allRows.Count)"
                
                # Sample the first few non-null BootStartDate values
                $samples = $allRows | Where-Object { $_.BootStartDate -and $_.BootStartDate -ne 'NULL' } | Select-Object -First 5 -ExpandProperty BootStartDate
                if ($samples) {
                    Write-Host "  Sample BootStartDate values:"
                    $samples | ForEach-Object { Write-Host "    $_" }
                } else {
                    Write-Host "  WARNING: All BootStartDate values are NULL or empty"
                }

                $bootDateValues = foreach ($row in $allRows) {
                    $value = $row.BootStartDate
                    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value) -or $value -eq 'NULL') {
                        continue
                    }

                    try {
                        [datetime]::Parse([string]$value)
                    } catch {
                        continue
                    }
                }

                Write-Host "  Successfully parsed: $($bootDateValues.Count) dates"
                if ($bootDateValues) {
                    $minDate = ($bootDateValues | Measure-Object -Minimum).Minimum
                    $maxDate = ($bootDateValues | Measure-Object -Maximum).Maximum
                    Write-Host ("  Date range: {0:yyyy-MM-dd} to {1:yyyy-MM-dd}" -f $minDate, $maxDate)
                }

                $bootStartReport = Get-BootStartsByMonth -Rows $allRows -DateProperty 'BootStartDate' -MonthsBack 12
                if ($bootStartReport.Count -gt 0) {
                    Write-Host "`nBoot starts by month for the past year:" -ForegroundColor Cyan
                    $bootStartReport | Format-Table Month, MonthName, Count -AutoSize
                }
            }
        }
    }
} else {
    Write-Warning "Table '$TableName' not found in: $FilePath"
}