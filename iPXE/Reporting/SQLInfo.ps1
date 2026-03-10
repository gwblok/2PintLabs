param(
    [string]$FilePath   = "C:\Users\GaryBlok\Downloads\IPXEAnywhere35.sql",
    [string]$TableName  = "dbo.RequestStatusInfo",
    [string]$OutputFile = "C:\Users\GaryBlok\Downloads\IPXEAnywhere35Extracted_$TableName.sql"
)

$inBlock = $false
$insertBlock = $false
$createSeen = $false

Get-Content $FilePath -ReadCount 1000 | ForEach-Object {
    foreach ($line in $_) {

        # Start collecting when we hit the CREATE TABLE for our table
        if ($line -match "CREATE TABLE.*\b$([regex]::Escape($TableName))\b") {
            $inBlock = $true
            $createSeen = $true
            $insertBlock = $false
        }

        # Also catch the data part
        if ($inBlock -and $line -match "Dumping data for table.*\b$([regex]::Escape($TableName))\b") {
            $insertBlock = $true
        }

        # Write lines while inside our table section
        if ($inBlock) {
            $line | Out-File -FilePath $OutputFile -Append -Encoding utf8
        }

        # Rough end condition — adjust if your dump uses different markers
        if ($inBlock -and $createSeen -and $line -match "UNLOCK TABLES|SET character_set_client") {
            # Give some extra lines after unlock
            if (++$linesAfter -le 20) { continue }
            $inBlock = $false
            $insertBlock = $false
            $createSeen = $false
            "Finished extracting $TableName" | Out-Host
            break   # ← remove this if you want ALL occurrences (rare)
        }
    }
}

Write-Host "Extraction saved to: $OutputFile"