function Get-AcerSCCMDriverPacks {
    param (
        [string]$Url = "https://community.acer.com/en/kb/articles/15378-microsoft-system-center-configuration-manager-sccm"
    )

    Write-Host "Downloading Acer SCCM driver pack page..." -ForegroundColor Cyan
    
    try {
        # Download the page content
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content
        
        Write-Host "Page downloaded successfully" -ForegroundColor Green
        
        # Save raw HTML for debugging
        #$html | Out-File ".\AcerSCCMPage.html" -Encoding UTF8
        #Write-Host "Raw HTML saved to AcerSCCMPage.html for inspection" -ForegroundColor Yellow
        
        # Initialize results array
        $driverPacks = @()
        
        # First, let's look for table structures
        # The page might use different table formats, so we'll try multiple patterns
        
        # Pattern 1: Look for driver download links with model information
        $linkPattern = '<a[^>]*href="([^"]*global-download\.acer\.com[^"]*\.zip)"[^>]*>([^<]+)</a>'
        $linkMatches = [regex]::Matches($html, $linkPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        Write-Host "Found $($linkMatches.Count) download links" -ForegroundColor Cyan
        
        if ($linkMatches.Count -eq 0) {
            # Try alternative pattern for links
            $linkPattern2 = 'href="([^"]*\.zip)"'
            $linkMatches = [regex]::Matches($html, $linkPattern2, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            Write-Host "Alternative search found $($linkMatches.Count) ZIP links" -ForegroundColor Cyan
        }
        
        # Pattern 2: Look for model names near download links
        # Models are typically in format: Aspire XXX, TravelMate XXX, etc.
        $modelPattern = '(Aspire|TravelMate|Veriton|Predator|Swift|Spin|Nitro|Extensa|Enduro|ConceptD|Chromebook)\s+[A-Z0-9\-\s]+(?=.*?href="[^"]*\.zip")'
        $modelMatches = [regex]::Matches($html, $modelPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
        
        Write-Host "Found $($modelMatches.Count) model references" -ForegroundColor Cyan
        
        # Pattern 3: Look for table rows containing model and download information
        $tableRowPattern = '<tr[^>]*>(.*?)</tr>'
        $rowMatches = [regex]::Matches($html, $tableRowPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
        
        Write-Host "Found $($rowMatches.Count) table rows" -ForegroundColor Cyan
        
        # Process table rows to extract model and download information
        $modelData = @{
        }
        
        foreach ($row in $rowMatches) {
            $rowContent = $row.Groups[1].Value
            
            # Skip header rows
            if ($rowContent -match '<th[^>]*>' -or $rowContent -match 'Model.*Windows') {
                continue
            }
            
            # Extract cells from row
            $cellPattern = '<td[^>]*>(.*?)</td>'
            $cells = [regex]::Matches($rowContent, $cellPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
            
            if ($cells.Count -ge 2) {
                # First cell typically contains model name
                $modelCell = $cells[0].Groups[1].Value -replace '<[^>]+>', '' -replace '&nbsp;', ' ' -replace '\s+', ' '
                $modelName = $modelCell.Trim()
                
                # Look for Windows 10 and Windows 11 download links in the row
                $win10Link = $null
                $win11Link = $null
                
                # Extract all links from the row
                $rowLinkPattern = 'href="([^"]+)"'
                $rowLinks = [regex]::Matches($rowContent, $rowLinkPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                
                foreach ($link in $rowLinks) {
                    $url = $link.Groups[1].Value
                    
                    # Determine if it's Win10 or Win11 based on context or URL
                    if ($rowContent -match "Windows\s*10.*?$([regex]::Escape($url))" -or $url -match 'W10|Win10|Windows10') {
                        $win10Link = $url
                    }
                    elseif ($rowContent -match "Windows\s*11.*?$([regex]::Escape($url))" -or $url -match 'W11|Win11|Windows11') {
                        $win11Link = $url
                    }
                    elseif ($url -match '\.zip$') {
                        # If we can't determine, check position in row
                        if (-not $win10Link) {
                            $win10Link = $url
                        }
                        elseif (-not $win11Link) {
                            $win11Link = $url
                        }
                    }
                }
                
                # Only add if we have a valid model name and at least one link
                if ($modelName -and $modelName.Length -gt 2 -and ($win10Link -or $win11Link)) {
                    if (-not $modelData.ContainsKey($modelName)) {
                        $modelData[$modelName] = @{
                            Windows10 = $win10Link
                            Windows11 = $win11Link
                        }
                    }
                    else {
                        # Update existing entry if we found new links
                        if ($win10Link -and -not $modelData[$modelName].Windows10) {
                            $modelData[$modelName].Windows10 = $win10Link
                        }
                        if ($win11Link -and -not $modelData[$modelName].Windows11) {
                            $modelData[$modelName].Windows11 = $win11Link
                        }
                    }
                }
            }
        }
        
        # If table parsing didn't work well, try a simpler approach
        if ($modelData.Count -eq 0) {
            Write-Host "Table parsing unsuccessful, trying alternative method..." -ForegroundColor Yellow
            
            # Find all model names and their associated links
            $contentBlocks = $html -split '<tr[^>]*>|<div[^>]*>|<p[^>]*>'
            
            foreach ($block in $contentBlocks) {
                # Look for model name
                if ($block -match '(Aspire|TravelMate|Veriton|Predator|Swift|Spin|Nitro|Extensa|Enduro|ConceptD|Chromebook)\s+([A-Z0-9\-]+)') {
                    $modelName = "$($matches[1]) $($matches[2])"
                    
                    # Look for download links in the same block
                    $blockLinks = [regex]::Matches($block, 'href="([^"]*\.zip)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    
                    if ($blockLinks.Count -gt 0) {
                        $win10Link = $null
                        $win11Link = $null
                        
                        foreach ($link in $blockLinks) {
                            $url = $link.Groups[1].Value
                            
                            if ($block -match "Windows\s*10" -and -not $win10Link) {
                                $win10Link = $url
                            }
                            elseif ($block -match "Windows\s*11" -and -not $win11Link) {
                                $win11Link = $url
                            }
                        }
                        
                        if ($win10Link -or $win11Link) {
                            $modelData[$modelName] = @{
                                Windows10 = $win10Link
                                Windows11 = $win11Link
                            }
                        }
                    }
                }
            }
        }
        
        # Convert hashtable to array of PSObjects
        foreach ($model in $modelData.Keys | Sort-Object) {
            $driverPacks += [PSCustomObject]@{
                Model = $model
                Windows10URL = $modelData[$model].Windows10
                Windows11URL = $modelData[$model].Windows11
            }
        }
        
        Write-Host "`nExtracted $($driverPacks.Count) models with driver packs" -ForegroundColor Green
        
        return $driverPacks
    }
    catch {
        Write-Error "Failed to retrieve Acer SCCM page: $($_.Exception.Message)"
        return $null
    }
}

# Run the function
$AcerDriverPacks = Get-AcerSCCMDriverPacks

if ($AcerDriverPacks) {
    # Display results
    Write-Host "`nAcer SCCM Driver Packs:" -ForegroundColor Cyan
    $AcerDriverPacks | Format-Table -AutoSize
    
    # Export to JSON
    #$AcerDriverPacks | ConvertTo-Json -Depth 3 | Out-File ".\AcerSCCMDriverPacks.json" -Encoding UTF8
    #Write-Host "`nExported to AcerSCCMDriverPacks.json" -ForegroundColor Green
    
    # Export to CSV
    #$AcerDriverPacks | Export-Csv -Path ".\AcerSCCMDriverPacks.csv" -NoTypeInformation
    #Write-Host "Exported to AcerSCCMDriverPacks.csv" -ForegroundColor Green
    
    # Show summary
    $totalModels = $AcerDriverPacks.Count
    $win10Count = ($AcerDriverPacks | Where-Object { $_.Windows10URL }).Count
    $win11Count = ($AcerDriverPacks | Where-Object { $_.Windows11URL }).Count
    
    Write-Host "`nSummary:" -ForegroundColor Magenta
    Write-Host "  Total Models: $totalModels" -ForegroundColor White
    Write-Host "  Models with Windows 10 drivers: $win10Count" -ForegroundColor White
    Write-Host "  Models with Windows 11 drivers: $win11Count" -ForegroundColor White
}
else {
    Write-Host "No driver packs found. Check AcerSCCMPage.html for manual inspection." -ForegroundColor Yellow
}

