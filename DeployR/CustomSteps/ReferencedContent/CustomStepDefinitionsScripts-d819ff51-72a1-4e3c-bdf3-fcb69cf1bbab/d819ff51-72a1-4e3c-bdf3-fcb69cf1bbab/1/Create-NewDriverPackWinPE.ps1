#Connect to DeployR
try {
    Import-Module DeployR.Utility
}
catch {}
if (Get-Module -name "DeployR.Utility"){
    # Get the provided variables
    [String]$IncludeGraphics = ${TSEnv:IncludeGraphics}
    [String]$IncludeAudio = ${TSEnv:IncludeAudio}
    [String]$IncludeGraphicsIntel = ${TSEnv:IncludeGraphicsIntel}
    [String]$Cleanup = ${TSEnv:Cleanup}
    [String]$TargetSystemDrive = ${TSEnv:OSDTARGETSYSTEMDRIVE}
    [String]$LogPath = ${TSEnv:_DEPLOYRLOGS}
    [String]$DriverPackOption = ${TSEnv:DriverPackOption}
    [switch]$ApplyDrivers = $true
    [String]$MakeAlias = ${TSEnv:MakeAlias}
    [String]$Make = ${TSEnv:Make}
    [String]$ModelAlias = ${TSEnv:ModelAlias}
    [int]$OSImageBuild = ${TSEnv:OSImageBuild}
}
else {
    <#Do this if a terminating exception happens#>
    [String]$IncludeGraphics = "False"
    [String]$IncludeAudio = "False"
    [String]$IncludeGraphicsIntel = "False"
    [String]$Cleanup = "False"
    [String]$TargetSystemDrive = "C:"
    [String]$LogPath = "C:\Windows\Temp\"
    [String]$DriverPackOption = "False"
    [switch]$ApplyDrivers = $true
    $Gather = iex (irm gather.garytown.com)
    [String]$MakeAlias = $Gather.MakeAlias
    [String]$Make = $Gather.Make
    [String]$ModelAlias = $Gather.ModelAlias
    [int]$OSImageBuild = $Gather.OSCurrentBuild
}


# Validate the Device Manufacturer
if ($MakeAlias -ne "Dell" -and $MakeAlias -ne "Lenovo" -and $MakeAlias -ne "HP" -and $MakeAlias -ne "Panasonic Corporation" -and $MakeAlias -ne "Microsoft" -and $Make -ne "Acer") {
    Write-Host "MakeAlias must be Microsoft, Dell, Lenovo, Panasonic, Acer or HP. Exiting script."
    Exit 0
}
if ($ModelAlias -eq "Virtual Machine") {
    Write-Host "ModelAlias is Virtual Machine, exiting script."
    Exit 0
}

${TSEnv:DriverPackMethod} = $DriverPackOption

if ($env:SystemDrive -eq "X:") {
    $dest = "S:\Drivers"
} else {
    $dest = "C:\Drivers"
}
if (!(Test-Path -Path $dest)) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
}

write-host "==================================================================="
write-host "Creating Driver Pack for WinPE for $MakeAlias $ModelAlias Devices"
write-host "Reporting Variables:"
write-host "IncludeGraphics (All):          $IncludeGraphics"
Write-Host "IncludeGraphics (Intel Only):   $IncludeGraphicsIntel"
write-host "IncludeAudio (All):             $IncludeAudio"
write-host "DriverPackOption:               $DriverPackOption"

#OEM Modules:
# Install Lenovo.Client.Scripting module
if ($MakeAlias -eq "Lenovo") {
    write-host "Installing Lenovo.Client.Scripting module if not already installed..."
    if (-not (Get-Module -Name Lenovo.Client.Scripting -ListAvailable)) {
        Write-Host "Lenovo.Client.Scripting module not found. Installing..."
        Install-Module -Name Lenovo.Client.Scripting -Force -SkipPublisherCheck
    } else {
        Write-Host "Lenovo.Client.Scripting module already installed."
    }
}
<# I don't think I need this for what I'm doing
if ($MakeAlias -eq 'HP'){
write-host "Installing HPCMSL module if not already installed..."
if (-not (Get-Module -Name HPCMSL -ListAvailable)) {
Write-Host "HPCMSL module not found. Installing..."
Install-Module -Name HPCMSL -Force -SkipPublisherCheck -AcceptLicense
} else {
Write-Host "HPCMSL module already installed."
}
}
#>

#region functions

#Function to get Surface Download Info
function Get-SurfaceDPDownloads {
    
    function Build-MSSurfaceSKUList {
        <#
        .SYNOPSIS
        Builds a list of Microsoft Surface SKUs from the GitHub repository
        
        .DESCRIPTION
        This function fetches the Surface SKU data from the Microsoft Docs GitHub repository,
        parses it, and returns a structured list of Surface devices with their system models and SKUs.
        
        .PARAMETER OutputPath
        Optional path to save the JSON output
        
        .EXAMPLE
        $skuData = Build-MSSurfaceSKUList
        Build-MSSurfaceSKUList -OutputPath ".\SurfaceSkus.json"
        #>
        
        [CmdletBinding()]
        param(
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter] $OutputJSON,
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter] $Details
        )
        
        
        
        function Get-SurfaceSkuFromGitHub {
            <#
            .SYNOPSIS
            Extracts Surface device information from the Microsoft Docs GitHub repository
            
            .DESCRIPTION
            Parses the raw markdown file from GitHub containing Surface SKU reference information
            and returns a PowerShell object with Device, System Model, and System SKU
            
            .PARAMETER OutputPath
            Optional path to save the JSON output
            
            .EXAMPLE
            $skuData = Get-SurfaceSkuFromGitHub
            Get-SurfaceSkuFromGitHub -OutputPath ".\SurfaceSkus.json"
            #>
            
            [CmdletBinding()]
            param(
            [Parameter(Mandatory = $false)]
            [string]$OutputPath,
            [Parameter(Mandatory = $false)]
            [System.Management.Automation.SwitchParameter] $Details
            )
            
            try {
                if ($Details){Write-Host "Fetching Surface SKU data from Microsoft Learn..." -ForegroundColor Cyan }
                
                $url = "https://learn.microsoft.com/en-us/surface/surface-system-sku-reference"
                
                # Use proper headers to avoid blocking
                $headers = @{
                    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
                    'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                    'Accept-Language' = 'en-US,en;q=0.5'
                    'Accept-Encoding' = 'gzip, deflate'
                    'Cache-Control' = 'no-cache'
                }
                
                # Fetch the content
                try {
                    $response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing
                    $content = $response.Content
                }
                catch {
                    Write-Warning "Failed to fetch with headers, trying basic request: $_"
                    $response = Invoke-WebRequest -Uri $url -UseBasicParsing
                    $content = $response.Content
                }
                
                if ($Details){Write-Host "Successfully fetched page content ($(($content.Length / 1024).ToString('F1')) KB)" -ForegroundColor Green}
                
                $devices = @()
                
                # Since we're now fetching HTML content instead of markdown, we need to parse HTML tables
                if ($Details){Write-Host "Parsing HTML content for Surface SKU tables..." -ForegroundColor Yellow}
                
                # Look for HTML tables containing Surface device information
                $tableMatches = [regex]::Matches($content, '<table[^>]*>.*?</table>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                
                if ($tableMatches.Count -eq 0) {
                    Write-Warning "No HTML tables found, trying to parse as markdown..."
                    
                    # Fallback to markdown parsing if no HTML tables found
                    $lines = $content -split "`n"
                    $inTable = $false
                    $headerFound = $false
                    
                    foreach ($line in $lines) {
                        $line = $line.Trim()
                        
                        # Skip empty lines
                        if (-not $line) {
                            continue
                        }
                        
                        # Check if we're entering a table
                        if ($line -match '^\|.*\|$') {
                            # Check if this is the header row we want
                            if ($line -match 'Device.*System\s+Model.*System\s+SKU' -or 
                            $line -match 'Device.*System Model.*System SKU') {
                                $inTable = $true
                                $headerFound = $true
                                if ($Details){Write-Host "  Found table header" -ForegroundColor DarkGray}
                                continue
                            }
                            
                            # Skip the separator line (|---|---|---|)
                            if ($headerFound -and $line -match '^\|[\s\-:]+\|') {
                                continue
                            }
                            
                            # Parse data rows
                            if ($inTable) {
                                # Exit table if we hit an empty line or non-table content
                                if (-not ($line -match '^\|.*\|$')) {
                                    $inTable = $false
                                    $headerFound = $false
                                    continue
                                }
                                
                                # Split the line by pipes and clean up
                                $cells = $line -split '\|' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() }
                                
                                # We expect at least 3 cells (Device, System Model, System SKU)
                                if ($cells.Count -ge 3) {
                                    $device = $cells[0].Trim()
                                    $systemModel = $cells[1].Trim()
                                    $systemSku = $cells[2].Trim()
                                    
                                    # Only add if we have a Surface device
                                    if ($device -match 'Surface' -and $device -notmatch '^\s*$') {
                                        $devices += @{
                                            Device = $device
                                            SystemModel = $systemModel
                                            SystemSKU = $systemSku
                                        }
                                        
                                        if ($Details){Write-Host "  Found: $device" -ForegroundColor Green}
                                    }
                                }
                            }
                        }
                    }
                }
                else {
                    if ($Details){Write-Host "Found $($tableMatches.Count) HTML table(s), parsing..." -ForegroundColor Green}
                    
                    foreach ($tableMatch in $tableMatches) {
                        $tableHtml = $tableMatch.Value
                        
                        # Check if this table contains Surface device information
                        if ($tableHtml -match 'Surface' -and ($tableHtml -match 'System.*Model' -or $tableHtml -match 'System.*SKU')) {
                            if ($Details){Write-Host "Processing Surface device table..." -ForegroundColor Cyan}
                            
                            # Parse HTML table rows
                            $rowMatches = [regex]::Matches($tableHtml, '<tr[^>]*>(.*?)</tr>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                            
                            $isHeaderProcessed = $false
                            
                            foreach ($rowMatch in $rowMatches) {
                                $rowHtml = $rowMatch.Groups[1].Value
                                
                                # Extract cell contents
                                $cellMatches = [regex]::Matches($rowHtml, '<t[hd][^>]*>(.*?)</t[hd]>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                                
                                if ($cellMatches.Count -ge 3) {
                                    $device = [System.Web.HttpUtility]::HtmlDecode($cellMatches[0].Groups[1].Value) -replace '<[^>]+>', '' -replace '\s+', ' '
                                    $systemModel = [System.Web.HttpUtility]::HtmlDecode($cellMatches[1].Groups[1].Value) -replace '<[^>]+>', '' -replace '\s+', ' '
                                    $systemSku = [System.Web.HttpUtility]::HtmlDecode($cellMatches[2].Groups[1].Value) -replace '<[^>]+>', '' -replace '\s+', ' '
                                    
                                    # Skip header row
                                    if ($device -match 'Device' -and $systemModel -match 'Model' -and $systemSku -match 'SKU') {
                                        $isHeaderProcessed = $true
                                        continue
                                    }
                                    
                                    # Only process data rows after header
                                    if ($isHeaderProcessed -and $device -match 'Surface' -and $device -notmatch '^\s*$') {
                                        # Clean up the values
                                        $device = $device.Trim()
                                        $systemModel = $systemModel.Trim()
                                        $systemSku = $systemSku.Trim()
                                        
                                        # Skip Consumer devices
                                        if ($device -match 'Consumer') {
                                            Write-Verbose "Skipping Consumer device: $device"
                                            continue
                                        }
                                        
                                        # Skip Surface 3 devices
                                        if ($device -match '^Surface 3\b') {
                                            Write-Verbose "Skipping Surface 3 device: $device"
                                            continue
                                        }
                                        
                                        # Create device object
                                        $shortDeviceName = Get-ShortDeviceName -DeviceName $device
                                        
                                        # Skip if Get-ShortDeviceName returns null (for excluded devices)
                                        if ($null -eq $shortDeviceName) {
                                            Write-Verbose "Skipping excluded device: $device"
                                            continue
                                        }
                                        
                                        $deviceObj = [PSCustomObject]@{
                                            Device = $device
                                            SystemModel = if ($systemModel -and $systemModel -ne '-' -and $systemModel -ne 'N/A') { $systemModel } else { "N/A" }
                                            SystemSKU = if ($systemSku -and $systemSku -ne '-' -and $systemSku -ne 'N/A') { $systemSku } else { "N/A" }
                                            ShortDevice = $shortDeviceName
                                        }
                                        
                                        $devices += $deviceObj
                                        if ($Details){Write-Host "  Found: $device" -ForegroundColor Green}
                                    }
                                }
                            }
                        }
                    }
                }
                
                # Remove duplicates based on all three properties
                $uniqueDevices = $devices | Sort-Object Device, SystemModel, SystemSKU -Unique
                
                if ($Details){Write-Host "`nTotal unique devices found: $($uniqueDevices.Count)" -ForegroundColor Yellow}
                
                # Display summary by device type
                $deviceTypes = $uniqueDevices | Group-Object { ($_.Device -split ' ')[0..1] -join ' ' } | Sort-Object Name
                if ($Details){
                    Write-Host "`nDevice Summary:" -ForegroundColor Cyan
                    foreach ($type in $deviceTypes) {
                        Write-Host "  $($type.Name): $($type.Count) models" -ForegroundColor Gray
                    }
                }
                # Convert to JSON if output path specified
                if ($OutputPath) {
                    $jsonOutput = $uniqueDevices | ConvertTo-Json -Depth 10
                    $jsonOutput | Out-File -FilePath $OutputPath -Encoding UTF8
                    Write-Host "`nData saved to: $OutputPath" -ForegroundColor Green
                }
                
                return $uniqueDevices
            }
            catch {
                Write-Error "Failed to get Surface SKU data from Microsoft Learn: $_"
                return $null
            }
        }
        
        # Function to display the data in a nice table format
        function Show-SurfaceSkuTable {
            <#
            .SYNOPSIS
            Displays Surface SKU data in a formatted table
            
            .PARAMETER SkuData
            The SKU data array from Get-SurfaceSkuFromGitHub
            
            .PARAMETER DeviceFilter
            Optional filter for specific device types (e.g., "Surface Pro", "Surface Laptop")
            
            .EXAMPLE
            Show-SurfaceSkuTable -SkuData $skuData
            Show-SurfaceSkuTable -SkuData $skuData -DeviceFilter "Surface Pro"
            #>
            
            [CmdletBinding()]
            param(
            [Parameter(Mandatory = $true)]
            [array]$SkuData,
            
            [Parameter(Mandatory = $false)]
            [string]$DeviceFilter
            )
            
            $displayData = $SkuData
            
            if ($DeviceFilter) {
                $displayData = $SkuData | Where-Object { $_.Device -like "*$DeviceFilter*" }
                Write-Host "Filtering for: $DeviceFilter" -ForegroundColor Yellow
            }
            
            $displayData | Format-Table -AutoSize
        }
        
        # Function to export to CSV
        function Export-SurfaceSkuToCsv {
            <#
            .SYNOPSIS
            Exports Surface SKU data to CSV file
            
            .PARAMETER SkuData
            The SKU data array from Get-SurfaceSkuFromGitHub
            
            .PARAMETER Path
            Path to save the CSV file
            
            .EXAMPLE
            Export-SurfaceSkuToCsv -SkuData $skuData -Path ".\SurfaceSkus.csv"
            #>
            
            [CmdletBinding()]
            param(
            [Parameter(Mandatory = $true)]
            [array]$SkuData,
            
            [Parameter(Mandatory = $true)]
            [string]$Path
            )
            
            try {
                $SkuData | Export-Csv -Path $Path -NoTypeInformation
                Write-Host "Data exported to CSV: $Path" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to export to CSV: $_"
            }
        }
        
        # Add this function before the Main execution section
        function Get-ShortDeviceName {
            <#
            .SYNOPSIS
            Creates a shortened, normalized device name
            
            .DESCRIPTION
            Removes inch specifications (13.5", 15", etc.), standardizes processor names,
            removes the word "Commercial", and adds parentheses around LTE/Wi-Fi.
            Special handling for Surface Laptop 7th Edition and Surface Pro 11th Edition.
            
            .PARAMETER DeviceName
            The original device name
            
            .EXAMPLE
            Get-ShortDeviceName "Surface Laptop 5 13.5" Intel"
            Returns: "Surface Laptop 5 with Intel processor"
            
            .EXAMPLE
            Get-ShortDeviceName "Surface Go 2 Commercial"
            Returns: "Surface Go 2"
            
            .EXAMPLE
            Get-ShortDeviceName "Surface Go 3 LTE"
            Returns: "Surface Go 3 (LTE)"
            #>
            
            [CmdletBinding()]
            param(
            [Parameter(Mandatory = $true)]
            [string]$DeviceName
            )
            
            # Skip Surface Pro 12-inch 1st Edition devices
            if ($DeviceName -match 'Surface Pro 12-inch 1st Edition') {
                return $null
            }
            
            # Skip Surface Hub devices
            if ($DeviceName -match 'Surface Hub') {
                return $null
            }
            
            $shortName = $DeviceName
            
            # Remove inch specifications (handles various formats)
            $shortName = $shortName -replace '\s*\d+(\.\d+)?["″]\s*', ' '
            $shortName = $shortName -replace '\s*\(\d+(\.\d+)?["″]\)\s*', ' '
            
            # Remove "Commercial" from the name
            $shortName = $shortName -replace '\s*Commercial\s*', ' '
            
            # Handle Surface Go 2, 3, and 4 specifically
            if ($shortName -match 'Surface Go 2') {
                $shortName = 'Surface Go 2'
            }
            elseif ($shortName -match 'Surface Go 3') {
                $shortName = 'Surface Go 3'
            }
            elseif ($shortName -match 'Surface Go 4') {
                $shortName = 'Surface Go 4'
            }
            # Handle Surface Pro 10 with 5G specifically
            elseif ($shortName -match '^Surface Pro 10 with 5G') {
                $shortName = 'Surface Pro 10 with 5G'
            }
            # Handle Surface Pro with 5G, 11th Edition specifically
            elseif ($shortName -match 'Surface Pro with 5G,?\s*11th Edition') {
                $shortName = 'Surface Pro 11th Edition, Intel processor'
            }
            # Handle Surface Pro 9 with 5G specifically
            elseif ($shortName -match '^Surface Pro 9 with 5G') {
                $shortName = 'Surface Pro 9 with Intel processor'
            }
            # Handle Surface Pro 9 specifically (not with 5G)
            elseif ($shortName -match '^Surface Pro 9\s*$') {
                $shortName = 'Surface Pro 9 with Intel processor'
            }
            # Handle Surface Laptop 7th Edition specifically
            elseif ($shortName -match 'Surface Laptop.*7th Edition') {
                if ($shortName -match 'Intel') {
                    $shortName = 'Surface Laptop 7th Edition, Intel processor'
                }
                elseif ($shortName -match 'Snapdragon') {
                    $shortName = 'Surface Laptop 7th Edition, Snapdragon processor'
                }
            }
            # Handle Surface Pro 11th Edition specifically
            elseif ($shortName -match 'Surface Pro 11') {
                if ($shortName -match 'Intel') {
                    $shortName = 'Surface Pro 11th Edition, Intel processor'
                }
                elseif ($shortName -match 'Snapdragon') {
                    $shortName = 'Surface Pro 11th Edition, Snapdragon processor'
                }
            }
            # Handle other devices with standard processor naming
            else {
                # Standardize processor names
                if ($shortName -match '\s+Intel\s*$') {
                    $shortName = $shortName -replace '\s+Intel\s*$', ' with Intel processor'
                }
                elseif ($shortName -match '\s+AMD\s*$') {
                    $shortName = $shortName -replace '\s+AMD\s*$', ' with AMD processor'
                }
                elseif ($shortName -match '\s+Intel\s+') {
                    $shortName = $shortName -replace '\s+Intel\s+', ' with Intel processor '
                }
                elseif ($shortName -match '\s+AMD\s+') {
                    $shortName = $shortName -replace '\s+AMD\s+', ' with AMD processor '
                }
            }
            
            # Add parentheses around LTE and Wi-Fi
            if ($shortName -match '\s+LTE\s*$') {
                $shortName = $shortName -replace '\s+LTE\s*$', ' (LTE)'
            }
            elseif ($shortName -match '\s+LTE\s+') {
                $shortName = $shortName -replace '\s+LTE\s+', ' (LTE) '
            }
            
            if ($shortName -match '\s+Wi-Fi\s*$') {
                $shortName = $shortName -replace '\s+Wi-Fi\s*$', ' (Wi-Fi)'
            }
            elseif ($shortName -match '\s+Wi-Fi\s+') {
                $shortName = $shortName -replace '\s+Wi-Fi\s+', ' (Wi-Fi) '
            }
            
            # Clean up extra spaces
            $shortName = $shortName -replace '\s+', ' '
            $shortName = $shortName.Trim()
            
            # Remove double "processor processor" if it exists (from the JSON example)
            $shortName = $shortName -replace 'processor processor', 'processor'
            
            return $shortName
        }
        if ($Details){
            # Main execution
            Write-Host "Surface SKU Reference Parser" -ForegroundColor Cyan
            Write-Host "===========================" -ForegroundColor Cyan
            Write-Host ""
        }
        # Get the SKU data
        $skuData = Get-SurfaceSkuFromGitHub
        
        if ($skuData) {
            # Save the SKU data to JSON
            
            if ($OutputJSON) {
                $jsonPath = Join-Path $PSScriptRoot "SurfaceSKUs.json"
                $skuData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
                Write-Host "`nExported SKU data to: $jsonPath" -ForegroundColor Green
            }
            if ($Details){
                # Display summary
                Write-Host "`nTotal devices found: $($skuData.Count)" -ForegroundColor Yellow
                
                # Show sample data
                Write-Host "`nSample data:" -ForegroundColor Cyan
                $skuData | Select-Object -First 5 | Format-Table Device, SystemModel, SystemSKU, ShortDevice -AutoSize
                
                # Usage examples
                Write-Host "`nUse these commands to work with the data:" -ForegroundColor Yellow
                Write-Host '  $skuData | Format-Table -AutoSize' -ForegroundColor White
                Write-Host '  $skuData | Where-Object { $_.Device -like "*Surface Go*" }' -ForegroundColor White
                Write-Host '  $skuData | Export-Csv -Path ".\SurfaceSkus.csv" -NoTypeInformation' -ForegroundColor White
                Write-Host '  Show-SurfaceSkuTable -SkuData $skuData -DeviceFilter "Surface Pro"' -ForegroundColor White
            }
        }
        else {
            Write-Error "Failed to retrieve Surface SKU data"
        }
        
        return $skuData
    }
    
    function Build-MSSurfaceURLList {
        <#
        .SYNOPSIS
        Builds a list of Microsoft Surface download URLs from Microsoft Learn
        
        .DESCRIPTION
        This function fetches the Surface download URL data from Microsoft Learn documentation,
        parses it, and returns a structured list of Surface devices with their download URLs.
        
        .PARAMETER OutputJSON
        Switch to export the data to a JSON file
        
        .EXAMPLE
        $urlData = Build-MSSurfaceURLList
        Build-MSSurfaceURLList -OutputJSON
        #>
        
        [CmdletBinding()]
        param(
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter] $OutputJSON,
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter] $Details
        )
        
        function Get-SurfaceDriverTable {
            Write-Host "Fetching Surface driver documentation from Microsoft Learn..." -ForegroundColor Yellow
            
            $url = "https://learn.microsoft.com/en-us/surface/manage-surface-driver-and-firmware-updates"
            
            try {
                # Use proper headers to avoid blocking
                $headers = @{
                    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
                    'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                    'Accept-Language' = 'en-US,en;q=0.5'
                    'Accept-Encoding' = 'gzip, deflate'
                    'Cache-Control' = 'no-cache'
                }
                
                $response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing
                $content = $response.Content
            }
            catch {
                Write-Error "Failed to fetch content from Microsoft Learn: $_"
                Write-Host "Trying alternative approach..." -ForegroundColor Yellow
                
                # Try without custom headers
                try {
                    $response = Invoke-WebRequest -Uri $url -UseBasicParsing
                    $content = $response.Content
                }
                catch {
                    Write-Error "Alternative approach failed: $_"
                    return $null
                }
            }
            
            if ($Details){Write-Host "Successfully fetched page content ($(($content.Length / 1024).ToString('F1')) KB)" -ForegroundColor Green}
            
            $devices = @()
            
            # Parse HTML content to find the table
            if ($Details){Write-Host "`nSearching for Surface device table..." -ForegroundColor Yellow}
            
            # Look for table patterns in the HTML
            # Microsoft Learn pages often have tables with specific classes or structures
            $tableMatches = [regex]::Matches($content, '<table[^>]*>.*?</table>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            
            if ($tableMatches.Count -eq 0) {
                Write-Warning "No tables found in the page content"
                if ($Details){Write-Host "Looking for markdown-style tables..." -ForegroundColor Yellow}
                
                # Split into lines and look for markdown tables
                $lines = $content -split "`r?`n"
                
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    $line = $lines[$i]
                    
                    # Look for table headers that might contain "Surface device" and download info
                    if ($line -match 'Surface device.*\|' -or 
                    $line -match '\|\s*Surface device\s*\|' -or
                    $line -match '\|\s*Device\s*\|.*download' -or
                    $line -match 'Device.*MSI') {
                        
                        if ($Details){Write-Host "Found potential table header at line $i" -ForegroundColor Green}
                        if ($Details){Write-Host "Header: $($line.Substring(0, [Math]::Min(100, $line.Length)))..." -ForegroundColor DarkGray}
                        
                        # Skip separator line if present
                        $i++
                        if ($i -lt $lines.Count -and $lines[$i] -match '^\|[\s-]+\|') {
                            $i++
                        }
                        
                        # Process table rows
                        while ($i -lt $lines.Count) {
                            $row = $lines[$i]
                            
                            # Check if we're still in the table
                            if ($row -notmatch '^\|' -or $row.Trim() -eq '') {
                                if ($Details){Write-Host "End of table at line $i" -ForegroundColor Yellow}
                                break
                            }
                            
                            # Parse cells
                            $cells = $row -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
                            
                            if ($cells.Count -ge 2) {
                                $firstCell = $cells[0]
                                $secondCell = $cells[1]
                                
                                # Clean up markdown formatting
                                $firstCell = $firstCell -replace '\*\*', '' -replace '\*', ''
                                
                                # Check if this is a Surface device category
                                if ($firstCell -match 'Surface\s+(Pro|Laptop|Book|Go|Studio|Hub|3)') {
                                    $currentCategory = $firstCell
                                    if ($Details){Write-Host "`nProcessing category: $currentCategory" -ForegroundColor Cyan}
                                    
                                    # Parse devices and URLs from the second cell
                                    $devices += Parse-DeviceCell -CategoryName $currentCategory -CellContent $secondCell
                                }
                            }
                            
                            $i++
                        }
                        
                        break
                    }
                }
            }
            else {
                if ($Details){Write-Host "Found $($tableMatches.Count) HTML table(s), parsing..." -ForegroundColor Green}
                
                foreach ($tableMatch in $tableMatches) {
                    $tableHtml = $tableMatch.Value
                    
                    # Check if this table contains Surface device information
                    if ($tableHtml -match 'Surface' -and ($tableHtml -match 'download' -or $tableHtml -match 'MSI')) {
                        if ($Details){Write-Host "Processing Surface device table..." -ForegroundColor Cyan}
                        
                        # Parse HTML table rows
                        $rowMatches = [regex]::Matches($tableHtml, '<tr[^>]*>(.*?)</tr>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                        
                        foreach ($rowMatch in $rowMatches) {
                            $rowHtml = $rowMatch.Groups[1].Value
                            
                            # Extract cell contents
                            $cellMatches = [regex]::Matches($rowHtml, '<t[hd][^>]*>(.*?)</t[hd]>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                            
                            if ($cellMatches.Count -ge 2) {
                                $firstCell = [System.Web.HttpUtility]::HtmlDecode($cellMatches[0].Groups[1].Value) -replace '<[^>]+>', '' -replace '\s+', ' '
                                $secondCell = $cellMatches[1].Groups[1].Value
                                
                                # Check if this is a Surface device category
                                if ($firstCell -match 'Surface\s+(Pro|Laptop|Book|Go|Studio|Hub|3)') {
                                    $currentCategory = $firstCell.Trim()
                                    if ($Details){Write-Host "`nProcessing category: $currentCategory" -ForegroundColor Cyan}
                                    
                                    # Parse devices and URLs from the second cell
                                    $devices += Parse-DeviceCell -CategoryName $currentCategory -CellContent $secondCell
                                }
                            }
                        }
                    }
                }
            }
            
            return $devices
        }
        
        function Parse-DeviceCell {
            param(
            [string]$CategoryName,
            [string]$CellContent,
            [Parameter(Mandatory = $false)]
            [System.Management.Automation.SwitchParameter] $Details
            )
            
            $deviceList = @()
            
            # Remove HTML tags and decode entities
            $cleanContent = [System.Web.HttpUtility]::HtmlDecode($CellContent) -replace '<[^>]+>', ''
            
            if ($Details){Write-Host "  Parsing devices from: $($cleanContent.Substring(0, [Math]::Min(100, $cleanContent.Length)))..." -ForegroundColor DarkGray}
            
            # Look for device links in format [Device Name](URL) or <a href="URL">Device Name</a>
            $linkMatches = [regex]::Matches($CellContent, '<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            
            if ($linkMatches.Count -eq 0) {
                # Try markdown format
                $linkMatches = [regex]::Matches($CellContent, '\[([^\]]+)\]\(([^\)]+)\)')
            }
            
            if ($linkMatches.Count -gt 0) {
                if ($Details){Write-Host "    Found $($linkMatches.Count) linked devices" -ForegroundColor Green}
                
                foreach ($match in $linkMatches) {
                    $deviceName = $match.Groups[2].Value.Trim()
                    $url = $match.Groups[1].Value.Trim()
                    
                    # Clean up device name
                    $deviceName = [System.Web.HttpUtility]::HtmlDecode($deviceName) -replace '\s+', ' '
                    
                    # Handle relative URLs
                    if ($url -notmatch '^https?://') {
                        if ($url -match '^/') {
                            $url = "https://www.microsoft.com$url"
                        }
                    }
                    
                    # Extract download ID
                    $downloadId = $null
                    if ($url -match 'id=(\d+)') {
                        $downloadId = $Matches[1]
                    }
                    
                    $deviceObj = [PSCustomObject]@{
                        Category = $CategoryName
                        Device = $deviceName
                        MsiDownloadUrl = $url
                        DownloadId = $downloadId
                    }
                    
                    $deviceList += $deviceObj
                    if ($Details){Write-Host "    Added: $deviceName" -ForegroundColor Gray}
                }
            }
            
            # Look for plain text devices (without links)
            $plainTextDevices = [regex]::Matches($cleanContent, '(?:^|\n|\r)\s*[-•]\s*([^-•\n\r]+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            
            foreach ($match in $plainTextDevices) {
                $deviceName = $match.Groups[1].Value.Trim()
                
                # Skip if already added as linked device or too short
                if (($deviceList | Where-Object { $_.Device -eq $deviceName }) -or $deviceName.Length -lt 5) {
                    continue
                }
                
                # Skip if it looks like a URL or other metadata
                if ($deviceName -match '^https?://' -or $deviceName -match '^\d+$') {
                    continue
                }
                
                $deviceObj = [PSCustomObject]@{
                    Category = $CategoryName
                    Device = $deviceName
                    MsiDownloadUrl = $null
                    DownloadId = $null
                }
                
                $deviceList += $deviceObj
                if ($Details){Write-Host "    Added (no URL): $deviceName" -ForegroundColor DarkGray}
            }
            
            return $deviceList
        }
        
        # Main execution
        if ($Details) {
            Write-Host "`nSurface Driver URL Parser" -ForegroundColor Cyan
            Write-Host "========================" -ForegroundColor Cyan
        }
        
        
        try {
            # Get the data
            $surfaceDevices = Get-SurfaceDriverTable
            
            if ($surfaceDevices -and $surfaceDevices.Count -gt 0) {
                if ($Details) {Write-Host "`nFound $($surfaceDevices.Count) total Surface devices" -ForegroundColor Green}
                
                # Count devices with and without URLs
                $devicesWithUrls = $surfaceDevices | Where-Object { $_.MsiDownloadUrl }
                $devicesWithoutUrls = $surfaceDevices | Where-Object { -not $_.MsiDownloadUrl }
                
                if ($Details) {
                    Write-Host "  - $($devicesWithUrls.Count) devices with download URLs" -ForegroundColor Green
                    Write-Host "  - $($devicesWithoutUrls.Count) devices without download URLs" -ForegroundColor Yellow
                }
                
                # Export all devices to JSON if requested
                if ($OutputJSON) {
                    $jsonPath = Join-Path $PSScriptRoot "SurfaceURLs.json"
                    $surfaceDevices | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
                    Write-Host "`nExported to: $jsonPath" -ForegroundColor Green
                }
                else {
                    Write-Host "Use -OutputJSON to export the data to a JSON file" -ForegroundColor Yellow
                }
                if ($Details) {
                    # Show summary by category
                    Write-Host "`nSummary by category:" -ForegroundColor Yellow
                    $surfaceDevices | Group-Object Category | Sort-Object Name | ForEach-Object {
                        Write-Host "  $($_.Name): $($_.Count) devices" -ForegroundColor Cyan
                    }
                    
                    # Show sample devices
                    Write-Host "`nSample devices found:" -ForegroundColor Yellow
                    $surfaceDevices | Group-Object Category | ForEach-Object {
                        Write-Host "`n$($_.Name):" -ForegroundColor Cyan
                        $_.Group | Select-Object -First 3 | ForEach-Object {
                            $urlStatus = if($_.MsiDownloadUrl) { "✓" } else { "✗" }
                            Write-Host "  [$urlStatus] $($_.Device)" -ForegroundColor Gray
                        }
                        if ($_.Group.Count -gt 3) {
                            Write-Host "  ... and $($_.Group.Count - 3) more" -ForegroundColor DarkGray
                        }
                    }
                }
            }
            else {
                Write-Warning "No Surface devices found in the documentation"
            }
        }
        catch {
            Write-Error "Failed to parse Surface driver table: $_"
            Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        # Always return the data for use by other scripts
        return $surfaceDevices
    }
    function Match-SurfaceData {
        [CmdletBinding()]
        param(
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter] $OutputJSON,
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter] $Details,
        [Parameter(Mandatory = $false)]
        [PSObject]$SkuData,
        [Parameter(Mandatory = $false)]
        [PSObject]$URLData
        )
        
        Write-Host "Loading SKU data..." -ForegroundColor Yellow
        if ($SkuData) {
            $skuData = $SkuData
        }
        else {
            $skuData = Build-MSSurfaceSKUList
        }
        
        Write-Host "Loading Driver Pack data..." -ForegroundColor Yellow
        if ($URLData) {
            $driverData = $URLData
        }
        else {
            $URLData = Build-MSSurfaceURLList
        }
        
        Write-Host "Found $($skuData.Count) SKUs and $($URLData.Count) driver packs" -ForegroundColor Green
        
        # Create a lookup table for driver packs
        $driverLookup = @{}
        foreach ($driver in $URLData) {
            # Skip if device name is null or empty
            if ([string]::IsNullOrWhiteSpace($driver.Device)) {
                Write-Warning "Skipping driver entry with no device name"
                continue
            }
            
            # Create multiple keys for better matching
            $keys = @()
            
            # Add the full device name as a key
            $keys += $driver.Device
            
            # Add simplified version without parentheses content
            $simplifiedName = $driver.Device -replace '\s*\([^)]+\)', ''
            if (-not [string]::IsNullOrWhiteSpace($simplifiedName)) {
                $keys += $simplifiedName
            }
            
            # Add version without "Surface" prefix for partial matching
            $withoutSurface = $driver.Device -replace '^Surface\s+', ''
            if (-not [string]::IsNullOrWhiteSpace($withoutSurface)) {
                $keys += $withoutSurface
            }
            
            foreach ($key in $keys | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
                if (-not $driverLookup.ContainsKey($key)) {
                    $driverLookup[$key] = $driver
                }
            }
        }
        
        Write-Host "Created lookup table with $($driverLookup.Count) entries" -ForegroundColor Green
        
        # Function to find best matching driver pack
        function Find-MatchingDriverPack {
            param($skuDevice, $shortDevice)
            
            # Validate inputs
            if ([string]::IsNullOrWhiteSpace($skuDevice)) {
                return $null
            }
            
            # Try exact match first
            if ($driverLookup.ContainsKey($skuDevice)) {
                return $driverLookup[$skuDevice]
            }
            
            # Try short device name
            if (-not [string]::IsNullOrWhiteSpace($shortDevice) -and $driverLookup.ContainsKey($shortDevice)) {
                return $driverLookup[$shortDevice]
            }
            
            # Try partial matching
            $potentialMatches = @()
            
            foreach ($key in $driverLookup.Keys) {
                # Check if SKU device contains driver key or vice versa
                if ($skuDevice -like "*$key*" -or $key -like "*$skuDevice*") {
                    $potentialMatches += $driverLookup[$key]
                }
                elseif (-not [string]::IsNullOrWhiteSpace($shortDevice) -and 
                ($shortDevice -like "*$key*" -or $key -like "*$shortDevice*")) {
                    $potentialMatches += $driverLookup[$key]
                }
            }
            
            # Return the first match if any found
            if ($potentialMatches.Count -gt 0) {
                return $potentialMatches[0]
            }
            
            # Special case matching for common patterns
            $patterns = @{
                'Pro 11' = 'Pro 11th Edition'
                'Pro 10' = 'Pro 10'
                'Pro 9' = 'Pro 9'
                'Pro 8' = 'Pro 8'
                'Pro 7\+' = 'Pro 7+'
                'Pro 7' = 'Pro 7'
                'Pro 6' = 'Pro 6'
                'Pro 5' = 'Pro 5'
                'Pro 4' = 'Pro 4'
                'Pro 3' = 'Pro 3'
                'Laptop 7' = 'Laptop 7th Edition'
                'Laptop 6' = 'Laptop 6'
                'Laptop 5' = 'Laptop 5'
                'Laptop 4' = 'Laptop 4'
                'Laptop 3' = 'Laptop 3'
                'Laptop 2' = 'Laptop 2'
                'Laptop Go 3' = 'Laptop Go 3'
                'Laptop Go 2' = 'Laptop Go 2'
                'Laptop Go' = 'Laptop Go'
                'Laptop Studio 2' = 'Laptop Studio 2'
                'Laptop Studio' = 'Laptop Studio'
                'Book 3' = 'Book 3'
                'Book 2' = 'Book 2'
                'Book' = 'Book'
                'Go 4' = 'Go 4'
                'Go 3' = 'Go 3'
                'Go 2' = 'Go 2'
                'Go' = 'Go'
                'Studio 2\+' = 'Studio 2+'
                'Studio 2' = 'Studio 2'
                'Studio' = 'Studio'
                'Hub 2S' = 'Hub 2S'
                'Hub 3' = 'Hub 3'
            }
            
            foreach ($pattern in $patterns.Keys) {
                if ($skuDevice -match $pattern -or (-not [string]::IsNullOrWhiteSpace($shortDevice) -and $shortDevice -match $pattern)) {
                    $searchKey = "Surface " + $patterns[$pattern]
                    if ($driverLookup.ContainsKey($searchKey)) {
                        return $driverLookup[$searchKey]
                    }
                    
                    # Try variations
                    foreach ($key in $driverLookup.Keys) {
                        if ($key -like "*$($patterns[$pattern])*") {
                            return $driverLookup[$key]
                        }
                    }
                }
            }
            
            return $null
        }
        
        # Combine the data
        $combinedData = @()
        $matchedCount = 0
        $unmatchedCount = 0
        
        foreach ($sku in $skuData) {
            # Skip invalid SKU entries
            if ([string]::IsNullOrWhiteSpace($sku.Device)) {
                Write-Warning "Skipping SKU entry with no device name"
                continue
            }
            
            $matchingDriver = Find-MatchingDriverPack -skuDevice $sku.Device -shortDevice $sku.ShortDevice
            
            if ($matchingDriver) {
                $matchedCount++
                $matchStatus = "Matched"
            } else {
                $unmatchedCount++
                $matchStatus = "No Match"
            }
            
            $combinedObj = [PSCustomObject]@{
                # SKU Information
                Device = $sku.Device
                ShortDevice = $sku.ShortDevice
                SystemModel = $sku.SystemModel
                SystemSKU = $sku.SystemSKU
                
                # Driver Pack Information
                DriverPackDevice = if ($matchingDriver) { $matchingDriver.Device } else { $null }
                MsiDownloadUrl = if ($matchingDriver) { $matchingDriver.MsiDownloadUrl } else { $null }
                DownloadId = if ($matchingDriver) { $matchingDriver.DownloadId } else { $null }
                
                # Match Status
                MatchStatus = $matchStatus
            }
            
            $combinedData += $combinedObj
        }
        
        Write-Host "`nMatching Results:" -ForegroundColor Yellow
        Write-Host "  Matched: $matchedCount SKUs" -ForegroundColor Green
        Write-Host "  Unmatched: $unmatchedCount SKUs" -ForegroundColor Red
        
        # Export combined data
        if ($OutputJSON) {
            Write-Host "Exporting combined data to JSON..." -ForegroundColor Yellow
            $outputPath = Join-Path $PSScriptRoot "SurfaceDeviceDetails.json"
            $combinedData | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding UTF8
            Write-Host "`nExported combined data to: $outputPath" -ForegroundColor Green
        } else {
            #Write-Host "Use -OutputJSON to export the combined data to a JSON file" -ForegroundColor Yellow
        }
        if ($Details) {
            # Show summary by device type
            Write-Host "`nSummary by Device Type:" -ForegroundColor Yellow
            $deviceGroups = $combinedData | ForEach-Object {
                $deviceType = if ($_.Device -match 'Surface (Pro|Laptop|Book|Go|Studio|Hub)') { $Matches[1] } else { "Other" }
                [PSCustomObject]@{
                    DeviceType = $deviceType
                    Device = $_
                }
            }
            
            $deviceGroups | Group-Object DeviceType | Sort-Object Name | ForEach-Object {
                $matched = ($_.Group | Where-Object { $_.Device.MatchStatus -eq "Matched" }).Count
                $total = $_.Count
                $percentage = if ($total -gt 0) { [math]::Round(($matched / $total) * 100, 1) } else { 0 }
                Write-Host "  Surface $($_.Name): $matched/$total matched ($percentage%)" -ForegroundColor Cyan
            }
            
            # Show unmatched SKUs
            $unmatched = $combinedData | Where-Object { $_.MatchStatus -eq "No Match" }
            if ($unmatched.Count -gt 0) {
                Write-Host "`nUnmatched SKUs (first 20):" -ForegroundColor Yellow
                $unmatched | Select-Object -First 20 | ForEach-Object {
                    Write-Host "  - $($_.Device) [$($_.ShortDevice)]" -ForegroundColor Red
                }
                if ($unmatched.Count -gt 20) {
                    Write-Host "  ... and $($unmatched.Count - 20) more" -ForegroundColor Red
                }
            }
            
            # Show matched examples
            Write-Host "`nMatched Examples:" -ForegroundColor Yellow
            $combinedData | Where-Object { $_.MsiDownloadUrl } | Select-Object -First 5 | ForEach-Object {
                Write-Host "  SKU: $($_.Device)" -ForegroundColor Green
                Write-Host "    Short Name: $($_.ShortDevice)" -ForegroundColor DarkGray
                Write-Host "    → Driver: $($_.DriverPackDevice)" -ForegroundColor DarkGray
                Write-Host "    → URL: $($_.MsiDownloadUrl)" -ForegroundColor DarkGray
            }
        }
        return $combinedData
    }
    
    
    function Get-SurfaceDriverPackMSIUrls {
        [CmdletBinding()]
        param(
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter] $OutputJSON,
        [Parameter(Mandatory = $false)]
        [string]$outputPath,
        [PSObject]$CombinedData
        )
        
        Write-Host "`nSurface Driver Pack MSI URL Extractor" -ForegroundColor Cyan
        Write-Host "=====================================" -ForegroundColor Cyan
        
        
        Write-Host "Loading combined Surface data..." -ForegroundColor Yellow
        
        if ($CombinedData) {
            $combinedData = $CombinedData
        } else {
            Write-Host "No combined data provided, fetching from Match-SurfaceData..." -ForegroundColor Yellow
            $combinedData = Match-SurfaceData
        }
        
        
        # Filter to only devices with download URLs
        $devicesWithUrls = $combinedData | Where-Object { $_.MsiDownloadUrl }
        Write-Host "Found $($devicesWithUrls.Count) devices with download URLs" -ForegroundColor Green
        
        $results = @()
        $processedUrls = @{}  # Cache to avoid processing the same URL multiple times
        
        foreach ($device in $devicesWithUrls) {
            # Skip if we've already processed this URL
            if ($processedUrls.ContainsKey($device.MsiDownloadUrl)) {
                Write-Host "  Using cached data for: $($device.Device)" -ForegroundColor DarkGray
                
                # Create result object with cached data
                $cachedData = $processedUrls[$device.MsiDownloadUrl]
                $resultObj = [PSCustomObject]@{
                    Device = $device.Device
                    ShortDevice = $device.ShortDevice
                    SystemSKU = $device.SystemSKU
                    DownloadPageUrl = $device.MsiDownloadUrl
                    DownloadId = $device.DownloadId
                    Windows11Url = $cachedData.Windows11Url
                    Windows11FileName = $cachedData.Windows11FileName
                    Windows11FileSize = $cachedData.Windows11FileSize
                    Windows10Url = $cachedData.Windows10Url
                    Windows10FileName = $cachedData.Windows10FileName
                    Windows10FileSize = $cachedData.Windows10FileSize
                    LastUpdated = $cachedData.LastUpdated
                    Status = $cachedData.Status
                }
                $results += $resultObj
                continue
            }
            
            Write-Host "`nProcessing: $($device.Device)" -ForegroundColor Yellow
            Write-Host "  URL: $($device.MsiDownloadUrl)" -ForegroundColor DarkGray
            
            try {
                # Fetch the download page
                $response = Invoke-WebRequest -Uri $device.MsiDownloadUrl -UseBasicParsing
                $content = $response.Content
                
                # Initialize variables
                $windows11Url = $null
                $windows11FileName = $null
                $windows11FileSize = $null
                $windows10Url = $null
                $windows10FileName = $null
                $windows10FileSize = $null
                $lastUpdated = $null
                
                # Microsoft download pages contain links to MSI files in different formats
                # Let's look for all .msi links first
                $msiUrls = @()
                
                # Pattern 1: Direct MSI links in href attributes
                $hrefPattern = 'href="([^"]+\.msi)"'
                $hrefMatches = [regex]::Matches($content, $hrefPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                foreach ($match in $hrefMatches) {
                    $msiUrls += $match.Groups[1].Value
                }
                
                # Pattern 2: MSI links in JavaScript or data attributes
                $jsPattern = '["''](https?://[^"'']+\.msi)["'']'
                $jsMatches = [regex]::Matches($content, $jsPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                foreach ($match in $jsMatches) {
                    $msiUrls += $match.Groups[1].Value
                }
                
                # Pattern 3: Look for download.microsoft.com URLs
                $downloadPattern = '(https?://download\.microsoft\.com/[^"''<>\s]+\.msi)'
                $downloadMatches = [regex]::Matches($content, $downloadPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                foreach ($match in $downloadMatches) {
                    $msiUrls += $match.Groups[1].Value
                }
                
                # Remove duplicates
                $msiUrls = $msiUrls | Select-Object -Unique
                
                Write-Host "  Found $($msiUrls.Count) MSI URLs" -ForegroundColor DarkGray
                
                # Categorize the MSI URLs
                foreach ($url in $msiUrls) {
                    $fileName = Split-Path $url -Leaf
                    
                    # Check for Windows 11
                    if ($fileName -match 'Win11|Windows.*11|_11_|Win11_|22000|22621|22631|226\d\d') {
                        if (-not $windows11Url) {
                            $windows11Url = $url
                            $windows11FileName = $fileName
                            Write-Host "    Windows 11: $fileName" -ForegroundColor Green
                        }
                    }
                    # Check for Windows 10
                    elseif ($fileName -match 'Win10|Windows.*10|_10_|Win10_|19041|19042|19043|19044|19045|190\d\d|17763|18362|18363') {
                        if (-not $windows10Url) {
                            $windows10Url = $url
                            $windows10FileName = $fileName
                            Write-Host "    Windows 10: $fileName" -ForegroundColor Green
                        }
                    }
                }
                
                # Look for file sizes if available
                # Microsoft sometimes shows file sizes in the page
                if ($windows11FileName) {
                    $sizePattern = [regex]::Escape($windows11FileName) + '.*?(\d+(?:\.\d+)?\s*[MG]B)'
                    $sizeMatch = [regex]::Match($content, $sizePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    if ($sizeMatch.Success) {
                        $windows11FileSize = $sizeMatch.Groups[1].Value
                    }
                }
                
                if ($windows10FileName) {
                    $sizePattern = [regex]::Escape($windows10FileName) + '.*?(\d+(?:\.\d+)?\s*[MG]B)'
                    $sizeMatch = [regex]::Match($content, $sizePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    if ($sizeMatch.Success) {
                        $windows10FileSize = $sizeMatch.Groups[1].Value
                    }
                }
                
                # Look for last updated date
                $datePatterns = @(
                'Date Published:?\s*</[^>]+>\s*([^<]+)',
                'Last Updated:?\s*([^<]+)',
                'Release Date:?\s*([^<]+)',
                '(\d{1,2}/\d{1,2}/\d{4})'
                )
                
                foreach ($pattern in $datePatterns) {
                    $dateMatch = [regex]::Match($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    if ($dateMatch.Success) {
                        $lastUpdated = $dateMatch.Groups[1].Value.Trim()
                        break
                    }
                }
                
                # Create result object
                $resultObj = [PSCustomObject]@{
                    Device = $device.Device
                    ShortDevice = $device.ShortDevice
                    SystemSKU = $device.SystemSKU
                    DownloadPageUrl = $device.MsiDownloadUrl
                    DownloadId = $device.DownloadId
                    Windows11Url = $windows11Url
                    Windows11FileName = $windows11FileName
                    Windows11FileSize = $windows11FileSize
                    Windows10Url = $windows10Url
                    Windows10FileName = $windows10FileName
                    Windows10FileSize = $windows10FileSize
                    LastUpdated = $lastUpdated
                    Status = if ($windows11Url -or $windows10Url) { "Found" } else { "Not Found" }
                }
                
                # Cache the result
                $processedUrls[$device.MsiDownloadUrl] = $resultObj
                $results += $resultObj
                
                # Status update
                $foundCount = 0
                if ($windows11Url) { $foundCount++ }
                if ($windows10Url) { $foundCount++ }
                
                if ($foundCount -gt 0) {
                    Write-Host "  Status: Found $foundCount driver pack(s)" -ForegroundColor Green
                } else {
                    Write-Host "  Status: No MSI files found" -ForegroundColor Yellow
                }
                
                # Be nice to the server
                Start-Sleep -Milliseconds 500
            }
            catch {
                Write-Error "  Failed to process $($device.Device): $_"
                
                # Add error result
                $resultObj = [PSCustomObject]@{
                    Device = $device.Device
                    ShortDevice = $device.ShortDevice
                    SystemSKU = $device.SystemSKU
                    DownloadPageUrl = $device.MsiDownloadUrl
                    DownloadId = $device.DownloadId
                    Windows11Url = $null
                    Windows11FileName = $null
                    Windows11FileSize = $null
                    Windows10Url = $null
                    Windows10FileName = $null
                    Windows10FileSize = $null
                    LastUpdated = $null
                    Status = "Error: $_"
                }
                $results += $resultObj
            }
        }
        
        # Export results
        if (-not $OutputJSON) {
            Write-Host "Use -OutputJSON to export the results to a JSON file" -ForegroundColor Yellow
            return $results
        }
        else {
            Write-Host "Exporting results to JSON..." -ForegroundColor Yellow
            if (-not $outputPath) {
                $outputPath = Join-Path $PSScriptRoot "Surface.json"
            }
            $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding UTF8
            Write-Host "`nExported MSI list to: $outputPath" -ForegroundColor Green
        }
        
        
        # Show summary
        Write-Host "`nSummary:" -ForegroundColor Yellow
        $foundCount = ($results | Where-Object { $_.Status -eq "Found" }).Count
        $notFoundCount = ($results | Where-Object { $_.Status -eq "Not Found" }).Count
        $errorCount = ($results | Where-Object { $_.Status -like "Error*" }).Count
        
        Write-Host "  Found driver packs: $foundCount" -ForegroundColor Green
        Write-Host "  Not found: $notFoundCount" -ForegroundColor Yellow
        Write-Host "  Errors: $errorCount" -ForegroundColor Red
        
        # Show devices with both Windows 10 and 11
        $bothVersions = $results | Where-Object { $_.Windows11Url -and $_.Windows10Url }
        Write-Host "`nDevices with both Windows 10 and 11 drivers: $($bothVersions.Count)" -ForegroundColor Cyan
        if ($bothVersions.Count -gt 0 -and $bothVersions.Count -le 10) {
            $bothVersions | ForEach-Object {
                Write-Host "  - $($_.Device)" -ForegroundColor Gray
            }
        }
        
        # Show devices with only one version
        $onlyWin11 = $results | Where-Object { $_.Windows11Url -and -not $_.Windows10Url }
        $onlyWin10 = $results | Where-Object { $_.Windows10Url -and -not $_.Windows11Url }
        
        if ($onlyWin11.Count -gt 0) {
            Write-Host "`nDevices with only Windows 11 drivers: $($onlyWin11.Count)" -ForegroundColor Yellow
        }
        
        if ($onlyWin10.Count -gt 0) {
            Write-Host "`nDevices with only Windows 10 drivers: $($onlyWin10.Count)" -ForegroundColor Yellow
        }
        
        return $results
    }
    
    $SystemSKU = (Get-CimInstance -Namespace root\wmi -ClassName MS_SystemInformation).SystemSKU
    #Test
    #$SystemSKU = 'Surface_Book_1793'
    $SKUs = Build-MSSurfaceSKUList | where-object { $_.SystemSKU -eq $SystemSKU }    
    
    $DeviceDetails = Match-SurfaceData -SkuData $SKUs
    $DriverPackUrls = Get-SurfaceDriverPackMSIUrls -CombinedData $DeviceDetails
    
    return $DriverPackUrls
    
}

# Function to get Dell supported models
function Test-HPIASupport {
    $CabPath = "$env:TEMP\platformList.cab"
    $XMLPath = "$env:TEMP\platformList.xml"
    $PlatformListCabURL = "https://hpia.hpcloud.hp.com/ref/platformList.cab"
    Invoke-WebRequest -Uri $PlatformListCabURL -OutFile $CabPath -UseBasicParsing
    $Expand = expand $CabPath $XMLPath
    [xml]$XML = Get-Content $XMLPath
    $Platforms = $XML.ImagePal.Platform.SystemID
    $MachinePlatform = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BaseBoard).Product
    if ($MachinePlatform -in $Platforms){$HPIASupport = $true}
    else {$HPIASupport = $false}
    return $HPIASupport
}
function Get-HPOSSupport {
    [CmdletBinding()]
    param(
    [Parameter(Position=0,mandatory=$false)]
    [string]$Platform,
    [switch]$Latest,
    [switch]$MaxOS,
    [switch]$MaxOSVer,
    [switch]$MaxOSNum
    )
    $CabPath = "$env:TEMP\platformList.cab"
    $XMLPath = "$env:TEMP\platformList.xml"
    if ($Platform){$MachinePlatform = $platform}
    else {$MachinePlatform = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BaseBoard).Product}
    $PlatformListCabURL = "https://hpia.hpcloud.hp.com/ref/platformList.cab"
    Invoke-WebRequest -Uri $PlatformListCabURL -OutFile $CabPath -UseBasicParsing
    $Expand = expand $CabPath $XMLPath
    [xml]$XML = Get-Content $XMLPath
    $XMLPlatforms = $XML.ImagePal.Platform
    $OSList = ($XMLPlatforms | Where-Object {$_.SystemID -match $MachinePlatform}).OS | Select-Object -Property OSReleaseIdDisplay, OSBuildId, OSDescription
    
    if ($Latest){
        [String]$MaxOSSupported = ($OSList.OSDescription | Where-Object {$_ -notmatch "LTSB"}| Select-Object -Unique| Measure-Object -Maximum).Maximum
        [String]$MaxOSVerion = (($OSList | Where-Object {$_.OSDescription -eq "$MaxOSSupported"}).OSReleaseIdDisplay | Measure-Object -Maximum).Maximum
        return "$MaxOSSupported $MaxOSVerion"
        break
    }
    if ($MaxOS){
        [String]$MaxOSSupported = ($OSList.OSDescription | Where-Object {$_ -notmatch "LTSB"}| Select-Object -Unique| Measure-Object -Maximum).Maximum
        if ($MaxOSSupported -Match "11"){[String]$MaxOSName = "Win11"}
        else {[String]$MaxOSName = "Win10"}
        return "$MaxOSName"
        break
    }
    if ($MaxOSVer){
        [String]$MaxOSSupported = ($OSList.OSDescription | Where-Object {$_ -notmatch "LTSB"}| Select-Object -Unique| Measure-Object -Maximum).Maximum
        [String]$MaxOSVersion = (($OSList | Where-Object {$_.OSDescription -eq "$MaxOSSupported"}).OSReleaseIdDisplay | Measure-Object -Maximum).Maximum
        return "$MaxOSVersion"
        break
    }
    if ($MaxOSNum){
        [String]$MaxOSSupported = ($OSList.OSDescription | Where-Object {$_ -notmatch "LTSB"}| Select-Object -Unique| Measure-Object -Maximum).Maximum
        if ($MaxOSSupported -Match "11"){[String]$MaxOSNumber = "11.0"}
        else {[String]$MaxOSNumber = "10.0"}
        return "$MaxOSNumber"
        break
    }
    return $OSList
}

function Get-HPSoftpaqListLatest {
    [CmdletBinding()]
    param(
    [Parameter(Position=0,mandatory=$false)]
    [string]$Platform,
    [switch]$SystemInfo,
    [switch]$MaxOSVer,
    [switch]$MaxOSNum
    )
    if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64"){
        $Arch = '64'
    }
    
    if ($Platform){$MachinePlatform = $platform}
    else {$MachinePlatform = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BaseBoard).Product}
    $OSNum = Get-HPOSSupport -MaxOSNum -Platform $MachinePlatform
    $ReleaseID = Get-HPOSSupport -MaxOSVer -Platform $MachinePlatform
    $BaseURL = ("https://hpia.hpcloud.hp.com/ref/$($MachinePlatform)/$($MachinePlatform)_$($Arch)_$($OSNum).$($ReleaseID).cab").ToLower()
    #https://hpia.hpcloud.hp.com/ref/83b2/83b2_64_11.0.23h2.cab
    $CabPath = "$env:TEMP\HPIA.cab"
    $XMLPath = "$env:TEMP\HPIA.xml"
    Write-Verbose "Invoke-WebRequest -Uri $BaseURL -OutFile $CabPath -UseBasicParsing"
    Invoke-WebRequest -Uri $BaseURL -OutFile $CabPath -UseBasicParsing -ErrorAction SilentlyContinue
    $Expand = expand $CabPath $XMLPath
    [xml]$XML = Get-Content $XMLPath
    $SoftpaqList = $XML.ImagePal.Solutions.UpdateInfo
    if ($SystemInfo){
        $SysInfo = $XML.ImagePal.SystemInfo.System
        return $SysInfo
        break
    }
    return $SoftpaqList
    
}

function Get-HPSoftPaqItems {
    [CmdletBinding()]
    param(
    [Parameter(Position=0,mandatory=$false)]
    [string] $Platform,
    [Parameter(Position=1,mandatory=$true)]
    [string] $osver,
    [Parameter(Position=2,mandatory=$true)]
    [ValidateSet("10.0","11.0")]
    [string] $os
    )
    
    
    
    if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64"){$Arch = '64'}
    $CabPath = "$env:TEMP\HPIA.cab"
    $XMLPath = "$env:TEMP\HPIA.xml"
    if ($Platform){$MachinePlatform = $platform}
    else {$MachinePlatform = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BaseBoard).Product}
    
    #Test Passed Parameters
    $OSList = Get-HPOSSupport -Platform $MachinePlatform
    if ($OS -eq "11.0"){
        $OK = $OSList | Where-Object {$_.OSDescription -match "Windows 11"}
        if ($null -eq $OK){
            Write-Error "Your option of OS: $OS is not valid, This platform does not support Windows 11"
            break
        }
    }
    if ($OS -eq "10.0"){
        $OK = $OSList | Where-Object {$_.OSDescription -match "Windows 10"}
        if ($null -eq $OK){
            Write-Error "Your option of OS: $OS is not valid, This platform does not support Windows 10"
            break
        }
    }
    $SupportedOSVers = $OSList.OSReleaseIdDisplay
    if ($osver -notin $SupportedOSVers){
        Write-Host -ForegroundColor red "Selected Release $OSVer is not supported by this Platform: $MachinePlatform"
        Write-Error " Use Get-HPOSSupport to find list of options"
        break
    }
    $BaseURL = ("https://hpia.hpcloud.hp.com/ref/$($MachinePlatform)/$($MachinePlatform)_$($Arch)_$($os).$($osver).cab").ToLower()
    Write-Verbose "Invoke-WebRequest -Uri $BaseURL -OutFile $CabPath -UseBasicParsing"
    Invoke-WebRequest -Uri $BaseURL -OutFile $CabPath -UseBasicParsing -ErrorAction SilentlyContinue
    $Expand = expand $CabPath $XMLPath
    [xml]$XML = Get-Content $XMLPath
    $SoftpaqList = $XML.ImagePal.Solutions.UpdateInfo
    
    return $SoftpaqList
    
}

function Get-HPDriverPackLatest {
    [CmdletBinding()]
    param(
    [Parameter(Position=0,mandatory=$false)]
    [string]$Platform,
    [switch]$URL,
    [switch]$download
    )
    if ($Platform){$MachinePlatform = $platform}
    else {$MachinePlatform = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BaseBoard).Product}
    $OSList = Get-HPOSSupport -Platform $MachinePlatform
    if (($OSList.OSDescription) -contains "Microsoft Windows 11"){
        $OS = "11.0"
        #Get the supported Builds for Windows 11 so we can loop through them
        $SupportedWinXXBuilds = ($OSList| Where-Object {$_.OSDescription -match "11"}).OSReleaseIdDisplay | Sort-Object -Descending
        if ($SupportedWinXXBuilds){
            write-Verbose "Checking for Win $OS Driver Pack"
            [int]$Loop_Index = 0
            do {
                Write-Verbose "Checking for Driver Pack for $OS $($SupportedWinXXBuilds[$loop_index])"
                try {
                    $DriverPack = Get-HPSoftPaqItems -osver $($SupportedWinXXBuilds[$loop_index]) -os $OS -Platform $MachinePlatform -ErrorAction SilentlyContinue  | Where-Object {$_.Category -match "Driver Pack"}
                    #$DriverPack = Get-SoftpaqList -Category Driverpack -OsVer $($SupportedWinXXBuilds[$loop_index]) -Os "Win11" -ErrorAction SilentlyContinue
                }
                catch {
                    <#Do this if a terminating exception happens#>
                }
                if (!($DriverPack)){$Loop_Index++;}
                if ($DriverPack){
                    Write-Verbose "Windows 11 $($SupportedWinXXBuilds[$loop_index]) Driver Pack Found"
                }
            }
            while ($null -eq $DriverPack -and $loop_index -lt $SupportedWinXXBuilds.Count)
        }
    }
    
    if (!($DriverPack)){ #If no Win11 Driver Pack found, check for Win10 Driver Pack
        if (($OSList.OSDescription) -contains "Microsoft Windows 10"){
            $OS = "10.0"
            #Get the supported Builds for Windows 10 so we can loop through them
            $SupportedWinXXBuilds = ($OSList| Where-Object {$_.OSDescription -match "10"}).OSReleaseIdDisplay | Sort-Object -Descending
            if ($SupportedWinXXBuilds){
                write-Verbose "Checking for Win $OS Driver Pack"
                [int]$Loop_Index = 0
                do {
                    Write-Verbose "Checking for Driver Pack for $OS $($SupportedWinXXBuilds[$loop_index])"
                    try {
                        $DriverPack = Get-HPSoftPaqItems -osver $($SupportedWinXXBuilds[$loop_index]) -os $OS  -Platform $MachinePlatform -ErrorAction SilentlyContinue | Where-Object {$_.Category -match "Driver Pack"}
                        #$DriverPack = Get-SoftpaqList -Category Driverpack -OsVer $($SupportedWinXXBuilds[$loop_index]) -Os "Win10" -ErrorAction SilentlyContinue
                    }
                    catch {
                        <#Do this if a terminating exception happens#>
                    }
                    if (!($DriverPack)){$Loop_Index++;}
                    if ($DriverPack){
                        Write-Verbose "Windows 10 $($SupportedWinXXBuilds[$loop_index]) Driver Pack Found"
                    }
                }
                while ($null-eq $DriverPack  -and $loop_index -lt $SupportedWinXXBuilds.Count)
            }
        }
    }
    if ($DriverPack){
        Write-Verbose "Driver Pack Found: $($DriverPack.Name) for Platform: $Platform"
        if($PSBoundParameters.ContainsKey('Download')){
            Save-WebFile -SourceUrl "https://$($DriverPack.URL)" -DestinationName "$($DriverPack.id).exe" -DestinationDirectory "C:\Drivers"
        }
        else{
            if($PSBoundParameters.ContainsKey('URL')){
                return "https://$($DriverPack.URL)"
            }
            else {
                return $DriverPack
            }
        }
    }
    else {
        Write-Verbose "No Driver Pack Found for Platform: $Platform"
        return $false
    }
}
function Get-DellSupportedModels {
    [CmdletBinding()]
    
    $CabPathIndex = "$env:ProgramData\EMPS\DellCabDownloads\CatalogIndexPC.cab"
    $DellCabExtractPath = "$env:ProgramData\EMPS\DellCabDownloads\DellCabExtract"
    
    # Pull down Dell XML CAB used in Dell Command Update ,extract and Load
    if (!(Test-Path $DellCabExtractPath)){$null = New-Item -Path $DellCabExtractPath -ItemType Directory -Force}
    Write-Verbose "Downloading Dell Cab"
    Invoke-WebRequest -Uri "https://downloads.dell.com/catalog/CatalogIndexPC.cab" -OutFile $CabPathIndex -UseBasicParsing -Proxy $ProxyServer
    If(Test-Path "$DellCabExtractPath\DellSDPCatalogPC.xml"){Remove-Item -Path "$DellCabExtractPath\DellSDPCatalogPC.xml" -Force}
    Start-Sleep -Seconds 1
    if (test-path $DellCabExtractPath){Remove-Item -Path $DellCabExtractPath -Force -Recurse}
    $null = New-Item -Path $DellCabExtractPath -ItemType Directory
    Write-Verbose "Expanding the Cab File..." 
    $null = expand $CabPathIndex $DellCabExtractPath\CatalogIndexPC.xml
    
    Write-Verbose "Loading Dell Catalog XML.... can take awhile"
    [xml]$XMLIndex = Get-Content "$DellCabExtractPath\CatalogIndexPC.xml"
    
    
    $SupportedModels = $XMLIndex.ManifestIndex.GroupManifest
    $SupportedModelsObject = @()
    foreach ($SupportedModel in $SupportedModels){
        $SPInventory = New-Object -TypeName PSObject
        $SPInventory | Add-Member -MemberType NoteProperty -Name "SystemID" -Value "$($SupportedModel.SupportedSystems.Brand.Model.systemID)" -Force
        $SPInventory | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($SupportedModel.SupportedSystems.Brand.Model.Display.'#cdata-section')"  -Force
        $SPInventory | Add-Member -MemberType NoteProperty -Name "URL" -Value "$($SupportedModel.ManifestInformation.path)" -Force
        $SPInventory | Add-Member -MemberType NoteProperty -Name "Date" -Value "$($SupportedModel.ManifestInformation.version)" -Force		
        $SupportedModelsObject += $SPInventory 
    }
    return $SupportedModelsObject
}
function Get-DCUUpdateList {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory=$False)]
    [ValidateLength(4,4)]    
    [string]$SystemSKUNumber,
    [ValidateSet('bios','firmware','driver','application')]
    [String[]]$updateType,
    [ValidateSet('audio','video','network','chipset','storage','BIOS','Application')]
    [String[]]$updateDeviceCategory,
    [switch]$RAWXML,
    [switch]$Latest,
    [switch]$TLDR
    )
    
    
    $temproot = "$env:windir\temp"
    #$SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    $CabPathIndexModel = "$temproot\DellCabDownloads\CatalogIndexModel.cab"
    $DellCabExtractPath = "$temproot\DellCabDownloads\DellCabExtract"
    if (!(Test-Path $DellCabExtractPath)){$null = New-Item -Path $DellCabExtractPath -ItemType Directory -Force}
    
    
    if (!($SystemSKUNumber)) {
        if ($Manufacturer -notmatch "Dell"){return "This Function is only for Dell Systems"}
        $SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    }
    $DellSKU = Get-DellSupportedModels | Where-Object {$_.systemID -match $SystemSKUNumber} | Select-Object -First 1
    if (!($DellSKU)){
        return "System SKU not found"
    }
    if (Test-Path $CabPathIndexModel){Remove-Item -Path $CabPathIndexModel -Force}
    
    
    Invoke-WebRequest -Uri "http://downloads.dell.com/$($DellSKU.URL)" -OutFile $CabPathIndexModel -UseBasicParsing
    if (Test-Path $CabPathIndexModel){
        $null = expand $CabPathIndexModel $DellCabExtractPath\CatalogIndexPCModel.xml
        [xml]$XMLIndexCAB = Get-Content "$DellCabExtractPath\CatalogIndexPCModel.xml"
        
        #DCUAppsAvailable = $XMLIndexCAB.Manifest.SoftwareComponent | Where-Object {$_.ComponentType.value -eq "APAC"}
        #$AppNames = $DCUAppsAvailable.name.display.'#cdata-section' | Select-Object -Unique
        $BaseURL = "https://$($XMLIndexCAB.Manifest.baseLocation)"
        $Components = $XMLIndexCAB.Manifest.SoftwareComponent
        if ($RAWXML){
            return $Components
        }
        $ComponentsObject = @()
        foreach ($Component in $Components){
            $Item = New-Object -TypeName PSObject
            $Item | Add-Member -MemberType NoteProperty -Name "PackageID" -Value "$($Component.packageID)"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "Category" -Value "$($Component.Category.Display.'#cdata-section')"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "Type" -Value "$($component.ComponentType.Display.'#cdata-section')"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "Name" -Value "$($Component.Name.Display.'#cdata-section')" -Force
            $Item | Add-Member -MemberType NoteProperty -Name "ReleaseDate" -Value $([DateTime]($Component.releaseDate)) -Force
            $Item | Add-Member -MemberType NoteProperty -Name "DellVersion" -Value "$($Component.dellVersion)"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "VendorVersion" -Value "$($Component.vendorVersion)"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "PackageType" -Value "$($Component.packageType)"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "Path" -Value "$BaseURL/$($Component.path)" -Force		
            $Item | Add-Member -MemberType NoteProperty -Name "Description" -Value "$($component.Description.Display.'#cdata-section')" -Force		
            $ComponentsObject += $Item 
        }
        if ($updateType){
            $ComponentsObject = $ComponentsObject | Where-Object {$_.Type -in $updateType}
        }
        if ($updateDeviceCategory){
            $ComponentsObject = $ComponentsObject | Where-Object {$_.Category -in $updateDeviceCategory}
        }
        if ($TLDR) {
            $ComponentsObject = $ComponentsObject | Select-Object -Property Name,ReleaseDate,DellVersion,Path
        }
        if ($Latest){
            $ComponentsObject = $ComponentsObject | Sort-Object -Property ReleaseDate -Descending
            $hash = @{}
            foreach ($ComponentObject in $ComponentsObject) {
                if (-not $hash.ContainsKey($ComponentObject.Name)) {
                    $hash[$ComponentObject.Name] = $ComponentObject
                }
            }
            $ComponentsObject = $hash.Values 
        }
        return $ComponentsObject
    }
}
function Get-DellDeviceDetails {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory=$False)]
    [ValidateLength(4,4)]    
    [string]$SystemSKUNumber,
    [string]$ModelLike
    )
    
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    
    
    if ((!($SystemSKUNumber)) -and (!($ModelLike))) {
        if ($Manufacturer -notmatch "Dell"){return "This Function is only for Dell Systems, or please provide a SKU"}
        $SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    }
    <#
    if (!($ModelLike)){
    $DellSKU = Get-DellSupportedModels | Where-Object {$_.systemID -match $SystemSKUNumber} | Select-Object -First 1
    }
    else {
    $DellSKU = Get-DellSupportedModels | Where-Object { $_.Model -match $ModelLike}
    }
    
    return $DellSKU | Select-Object -Property SystemID,Model
    #>
    $MoreData = Get-DellDriverPackXML
    if (!($ModelLike)){
        $DrillDown = $MoreData.DriverPackManifest.DriverPackage.SupportedSystems.brand.model | Where-Object {$_.systemid -eq $SystemSKUNumber} | Select-Object -First 1
        $RDSDate = [DATETIME]"$($DrillDown.rtsDate)"
        $DeviceOutput = New-Object -TypeName PSObject
        $DeviceOutput | Add-Member -MemberType NoteProperty -Name "SystemID" -Value "$($DrillDown.systemID)" -Force
        $DeviceOutput | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($DrillDown.name)"  -Force
        $DeviceOutput | Add-Member -MemberType NoteProperty -Name "RTSDate" -Value $([DATETIME]$RDSDate) -Force
        return $DeviceOutput		
    }
    else{
        $DrillDown = $MoreData.DriverPackManifest.DriverPackage.SupportedSystems.brand.model | Where-Object {$_.name -match $ModelLike}
        if ($DrillDown.count -gt 1){
            $SystemIDs = $DrillDown.systemID | Select-Object -Unique
            $DeviceOutputObject = @()
            foreach ($SystemID in $SystemIDs){
                $DrillDown = $MoreData.DriverPackManifest.DriverPackage.SupportedSystems.brand.model | Where-Object {$_.systemid -eq $SystemID}| Select-Object -First 1
                $RDSDate = [DATETIME]"$($DrillDown.rtsDate)"
                $DeviceOutput = New-Object -TypeName PSObject
                $DeviceOutput | Add-Member -MemberType NoteProperty -Name "SystemID" -Value "$($DrillDown.systemID)" -Force
                $DeviceOutput | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($DrillDown.name)"  -Force
                $DeviceOutput | Add-Member -MemberType NoteProperty -Name "RTSDate" -Value $([DATETIME]$RDSDate) -Force
                $DeviceOutputObject += $DeviceOutput 
            }
            return $DeviceOutputObject | Sort-Object -Property RTSDate
        }
    }
}

function Get-DellDriverPackXML {
    [CmdletBinding()]
    
    $CabPathIndex = "$env:ProgramData\EMPS\DellCabDownloads\CatalogIndexPC.cab"
    $DellCabExtractPath = "$env:ProgramData\EMPS\DellCabDownloads\DellCabExtract"
    
    # Pull down Dell XML CAB used in Dell Command Update ,extract and Load
    if (!(Test-Path $DellCabExtractPath)){$null = New-Item -Path $DellCabExtractPath -ItemType Directory -Force}
    Write-Verbose "Downloading Dell Cab"
    Invoke-WebRequest -Uri "https://downloads.dell.com/catalog/DriverPackCatalog.cab" -OutFile $CabPathIndex -UseBasicParsing -Proxy $ProxyServer
    If(Test-Path "$DellCabExtractPath\DellSDPCatalogPC.xml"){Remove-Item -Path "$DellCabExtractPath\DellSDPCatalogPC.xml" -Force}
    Start-Sleep -Seconds 1
    if (test-path $DellCabExtractPath){Remove-Item -Path $DellCabExtractPath -Force -Recurse}
    $null = New-Item -Path $DellCabExtractPath -ItemType Directory
    Write-Verbose "Expanding the Cab File..." 
    $null = expand $CabPathIndex $DellCabExtractPath\DriverPackCatalog.xml
    
    Write-Verbose "Loading Dell Catalog XML.... can take awhile"
    [xml]$XMLIndex = Get-Content "$DellCabExtractPath\DriverPackCatalog.xml"
    
    return $XMLIndex
}

function Get-DellDeviceDriverPack {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory=$False)]
    [ValidateLength(4,4)]    
    [string]$SystemSKUNumber,
    [ValidateSet('Windows10','Windows11')]
    [string]$OSVer
    )
    
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    
    
    if (!($SystemSKUNumber)) {
        if ($Manufacturer -notmatch "Dell"){return "This Function is only for Dell Systems, or please provide a SKU"}
        $SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    }
    
    $MoreData = Get-DellDriverPackXML
    $DriverPacks = $MoreData.DriverPackManifest.DriverPackage | Where-Object {$_.SupportedSystems.brand.model.systemid -eq $SystemSKUNumber}
    $DeviceDetails = $MoreData.DriverPackManifest.DriverPackage.SupportedSystems.brand.model | Where-Object {$_.systemid -eq $SystemSKUNumber} | Select-Object -First 1
    $DriverPacksOBject = @()
    foreach ($DriverPack in $DriverPacks){
        $URL = "http://$($MoreData.DriverPackManifest.baseLocation)/$($DriverPack.path)"
        $FileName = $DriverPack.path -split "/" | Select-Object -Last 1
        $DeviceDriverPack = New-Object -TypeName PSObject
        $MetaDataVersion = $MoreData.DriverPackManifest.version
        $SizeinMB = [Math]::Round($DriverPack.size/1MB,2)
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "SystemID" -Value "$($DeviceDetails.systemID)" -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($DeviceDetails.name)"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "MetaDataVersion" -Value "$MetaDataVersion"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "FileName" -Value "$FileName"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "ReleaseID" -Value "$($DriverPack.releaseID)"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "URL" -Value "$URL"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "DateTime" -Value $([DATETIME]$DriverPack.dateTime) -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "hashMD5" -Value $($DriverPack.hashMD5) -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "SizeinMB" -Value $SizeinMB -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "OSSupported" -Value $($DriverPack.SupportedOperatingSystems.OperatingSystem.osCode) -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "OsArch" -Value $($DriverPack.SupportedOperatingSystems.OperatingSystem.osArch) -Force
        $DriverPacksOBject += $DeviceDriverPack 
    }
    
    if ($OSVer){
        $DriverPacksOBject = $DriverPacksOBject | Where-Object {$_.OSSupported -match $OSVer}
    }
    
    return $DriverPacksOBject 
    
}

function Invoke-DriverDownloadExpand {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory=$true)]
    [string]$URL,
    [Parameter(Mandatory=$true)]
    [string]$Name,
    [Parameter(Mandatory=$true)]
    [string]$ID,
    [Parameter(Mandatory=$true)]
    [string]$ToolsPath,
    [Parameter(Mandatory=$false)]
    [string]$DestinationPath,
    [Parameter(Mandatory=$false)]
    [string]$Cleanup = "True"
    )
    if ($DestinationPath){
        $dest = $DestinationPath
    }
    else {
        if ($env:SystemDrive -eq "X:") {
            $dest = "S:\Drivers"
        } else {
            $dest = "C:\Drivers"
        }
    }
    if (!(Test-Path -Path $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }
    
    Write-Host "Downloading: $URL"
    $destFile = Request-DeployRCustomContent -ContentName $ID -ContentFriendlyName $Name -URL $URL
    # Invoke-WebRequest -Uri $driverPack.Url -OutFile $destFile
    $GetItemOutFile = Get-Item $destFile
    
    if ($Cleanup -eq "False") {
        Write-Host "Cleanup is False, so copying the original file to $dest\Dls"
        Copy-Item -Path $GetItemOutFile.FullName -Destination "$dest\Dls" -Force
    }
    # Expand
    $ExpandFile = $GetItemOutFile.FullName
    Write-Verbose -Message "DriverPack: $ExpandFile"
    Write-Progress -Activity "Expanding Driver Pack" -Status "Expanding $ExpandFile" -PercentComplete 50
    #=================================================
    #   Cab
    #=================================================
    if ($GetItemOutFile.Extension -eq '.cab') {
        $DestinationPath = Join-Path $dest $GetItemOutFile.BaseName
        
        if (-NOT (Test-Path "$DestinationPath")) {
            New-Item $DestinationPath -ItemType Directory -Force -ErrorAction Ignore | Out-Null
            
            Write-Verbose -Verbose "Expanding CAB Driver Pack to $DestinationPath"
            Expand -R "$ExpandFile" -F:* "$DestinationPath" | Out-Null
        }
        return
    }
    #=================================================
    #   Dell
    #=================================================
    if ($GetItemOutFile.Extension -eq '.exe') {
        if ($GetItemOutFile.VersionInfo.FileDescription -match 'Dell') {
            Write-Verbose -Verbose "FileDescription: $($GetItemOutFile.VersionInfo.FileDescription)"
            Write-Verbose -Verbose "ProductVersion: $($GetItemOutFile.VersionInfo.ProductVersion)"
            
            $DestinationPath = Join-Path $dest $GetItemOutFile.BaseName
            
            if (-NOT (Test-Path "$DestinationPath")) {
                Write-Verbose -Verbose "Expanding Dell Driver Pack to $DestinationPath"
                $null = New-Item -Path $DestinationPath -ItemType Directory -Force -ErrorAction Ignore | Out-Null
                try {
                    Start-Process -FilePath $ExpandFile -ArgumentList "/s /e=`"$DestinationPath`"" -Wait                
                } catch {
                    Write-Error "Failed to extract Dell driver pack: $ExpandFile"
                }
                
            }
            return
        }
    }
    #=================================================
    #   HP
    #=================================================
    if ($GetItemOutFile.Extension -eq '.exe') {
        if (($GetItemOutFile.VersionInfo.InternalName -match 'hpsoftpaqwrapper') -or ($GetItemOutFile.VersionInfo.OriginalFilename -match 'hpsoftpaqwrapper.exe') -or ($GetItemOutFile.VersionInfo.FileDescription -like "HP *")) {
            Write-Verbose -Message "FileDescription: $($GetItemOutFile.VersionInfo.FileDescription)"
            Write-Verbose -Message "InternalName: $($GetItemOutFile.VersionInfo.InternalName)"
            Write-Verbose -Message "OriginalFilename: $($GetItemOutFile.VersionInfo.OriginalFilename)"
            Write-Verbose -Message "ProductVersion: $($GetItemOutFile.VersionInfo.ProductVersion)"
            
            $DestinationPath = Join-Path $dest $GetItemOutFile.BaseName
            
            if (-NOT (Test-Path "$DestinationPath")) {
                Write-Verbose -Verbose "Expanding HP Driver Pack to $DestinationPath"
                try {
                    & "$ToolsPath\7za.exe" -y x "$ExpandFile" -o"$DestinationPath" | Out-Host
                }
                catch {
                    Write-Error "Failed to extract HP driver pack: $ExpandFile"
                }
                
            }
            return
        }
    }
    #=================================================
    #   Lenovo
    #=================================================
    if ($GetItemOutFile.Extension -eq '.exe') {
        if (($GetItemOutFile.VersionInfo.FileDescription -match 'Lenovo') -or ($GetItemOutFile.Name -match 'tc_') -or ($GetItemOutFile.Name -match 'tp_') -or ($GetItemOutFile.Name -match 'ts_') -or ($GetItemOutFile.Name -match '500w') -or ($GetItemOutFile.Name -match 'sccm_') -or ($GetItemOutFile.Name -match 'm710e') -or ($GetItemOutFile.Name -match 'tp10') -or ($GetItemOutFile.Name -match 'tp8') -or ($GetItemOutFile.Name -match 'yoga')) {
            Write-Verbose -Message "FileDescription: $($GetItemOutFile.VersionInfo.FileDescription)"
            Write-Verbose -Message "ProductVersion: $($GetItemOutFile.VersionInfo.ProductVersion)"
            
            #$DestinationPath = Join-Path $dest $GetItemOutFile.BaseName
            $computer = Get-CimInstance -Class "Win32_ComputerSystemProduct" -Namespace "root/cimv2"
            $MachineType = $computer.Name.Substring(0, 4)
            $DestinationPath = Join-Path $dest $MachineType
            if (-NOT (Test-Path "$DestinationPath")) {
                Write-Verbose -Verbose "Expanding Lenovo Driver Pack to $DestinationPath"
                try {
                    & "$ToolsPath\innoextract.exe" -e -d "$DestinationPath" "$ExpandFile" | Out-Host
                } catch {
                    Write-Error "Failed to extract Lenovo driver pack: $ExpandFile"
                }
                return
                <# This doesn't work as the extracted folder name is too long to even extract to, so this is too late to help.
                #Rename the extracted folder to "Lenovo"
                Get-ChildItem -Path "$DestinationPath" -Directory | ForEach-Object {
                $newName = Join-Path $DestinationPath "Lenovo"
                if (-not (Test-Path $newName)) {
                Rename-Item -Path $_.FullName -NewName "Lenovo" -Force
                } else {
                Write-Warning "Destination folder already exists: $newName"
                }
                }
                #>
            }
        }
    }
    #=================================================
    #   MSI
    #=================================================
    if ($GetItemOutFile.Extension -eq '.msi') {
        $DestinationPath = Join-Path $dest $GetItemOutFile.BaseName
        
        if (-NOT (Test-Path "$DestinationPath")) {
            Write-Verbose -Verbose "Extracting MSI file to $DestinationPath"
            & "$ToolsPath\ExtractMSI\TwoPint.DeployR.ExtractMSI.exe" "$ExpandFile" "$DestinationPath" | Out-Host
        }
        return
    }
    #=================================================
    #   Zip
    #=================================================
    if ($GetItemOutFile.Extension -eq '.zip') {
        $DestinationPath = Join-Path $dest $GetItemOutFile.BaseName
        
        if (-NOT (Test-Path "$DestinationPath")) {
            Write-Verbose -Verbose "Expanding ZIP Driver Pack to $DestinationPath"
            Expand-Archive -Path $ExpandFile -DestinationPath $DestinationPath -Force
        }
        return
    }
    #=================================================
    #   Everything Else
    #=================================================
    Write-Warning "Unable to expand $ExpandFile"
}

function Migrate-WinPEDrivers {
    [CmdletBinding()]
    param(
    [string]$OfflineOSPath
    )
    
    $startTime = Get-Date
    $WindowsPath = $OfflineOSPath
    
    function timeDuration() {
        $totalSeconds = [int]$args[0]
        if ($totalSeconds -gt 0) { $time = New-TimeSpan -Seconds $totalSeconds }
        else { $time = New-TimeSpan -Seconds 600 }
        if ($time.Hours -gt 0) {
            if ($time.Hours -eq 1) { $output += "$($time.Hours) Hour" }
            else { $output += "$($time.Hours) Hours" }
        }
        if ($time.Minutes -gt 0) { 
            if ($time.Minutes -eq 1) { $output += " $($time.Minutes) Minute" } 
            else { $output += " $($time.Minutes) Minutes" }
        }
        if ($time.Seconds -gt 0) { 
            if ($time.Seconds -eq 1) { $output += " $($time.Seconds) Second" }
            else { $output += " $($time.Seconds) Seconds" }
        } 
        $output
    }
    
    Write-Host "Grabbing all the drivers..."
    $windrivers = Get-WindowsDriver -Online
    $runningDrivers = Get-CimInstance -ClassName win32_systemdriver | Where-Object State -eq 'Running'
    Write-Host "Found $($windrivers.Count) imported drivers and $($runningDrivers.Count) running drivers"
    
    $matchedDrivers = [System.Collections.Generic.List[PSCustomObject]]::new()
    Write-Host "Starting match driver process..."
    foreach ($run in $runningDrivers) {
        $runName = $run.Name                       # e.g. "iaStorVD"
        $runPath = $run.PathName                   # e.g. X:\Windows\System32\drivers\iaStorVD.sys
        $baseNoExt = [IO.Path]::GetFileNameWithoutExtension($runPath)
        
        # get the hash of the running .sys file
        $runHash = (Get-FileHash -Path $runPath -Algorithm SHA256).Hash
        
        # Find all packages for this driver base name
        $candidates = $windrivers | Where-Object {
            [IO.Path]::GetFileNameWithoutExtension($_.CatalogFile) -ieq $baseNoExt
        }
        $foundOne = $false
        foreach ($pkg in $candidates) {
            # Derive the driver‐store folder from the INF path
            $storeFolder = Split-Path -Path $pkg.OriginalFileName
            
            # Build the path to the .sys in that folder
            $candidateSys = Join-Path $storeFolder ("$baseNoExt.sys")
            if (-not (Test-Path $candidateSys)) {
                Write-Host "Skipping $($pkg.CatalogFile) - no SYS file at $candidateSys" -Severity 2
                continue
            }
            
            try {
                $candHash = (Get-FileHash -Path $candidateSys -Algorithm SHA256).Hash
            }
            catch {
                Write-Host "ERROR: Could not hash $candidateSys : $_" -Severity 3
                continue
            }
            
            
            if (Test-Path $candidateSys) {
                $candHash = (Get-FileHash -Path $candidateSys -Algorithm SHA256).Hash
                #We are doing a hash match as different versions of the same driver can be imported
                if ($candHash -eq $runHash) {
                    # WOW! (hubble reference)
                    $matchedDrivers.Add([PSCustomObject]@{
                        DriverName       = $runName
                        DriverPath       = $runPath
                        CatalogFile      = $pkg.CatalogFile
                        OriginalFileName = $pkg.OriginalFileName
                        ClassName        = $pkg.ClassName
                        ClassGuid        = $pkg.ClassGuid
                    })
                    Write-Host "Matched $runName -> $($pkg.CatalogFile) (store = $storeFolder)"
                    $foundOne = $true
                    break
                }
            }
        }
        # You can uncomment this line for extreme verbose messages, but typically not needed
        # if (-not $foundOne) {
        #     Write-Host "WARNING: No hash match found for $runName among $($candidates.Count) candidates" -Severity 2
        # }
    }
    if ($matchedDrivers.Count -eq 0) {
        Write-Host "ERROR: No matched drivers at all. Exiting script." -Severity 3
        exit 0
    }
    Write-Host "Completing matching imported and running drivers. Found $($matchedDrivers.count) matched drivers total."
    ${TSEnv:DriverMigrateCount} = $($matchedDrivers.count)
    # set up drivers folder
    $exportRoot = "$($env:SystemDrive)\ExportedDrivers"
    
    # create it if it doesn't already exist
    if (-not (Test-Path $exportRoot)) {
        Write-Host "Creating $exportRoot to export drivers"
        New-Item -Path $exportRoot -ItemType Directory | Out-Null
    }
    Write-Host "Starting export process for injection"
    foreach ($m in $matchedDrivers) {
        # OriginalFileName is the path to the .inf in its DriverStore folder
        $storeFolder = Split-Path -Path $m.OriginalFileName
        
        # pull just the leaf folder name (i.e. "iastorvd.inf_amd64_da06297c4b8e9167")
        $leafName = Split-Path -Path $storeFolder -Leaf
        $destFolder = Join-Path $exportRoot $leafName
        
        # copy the entire folder 
        Copy-Item -Path $storeFolder -Destination $destFolder -Recurse -Force
        Write-Host "Copied $storeFolder -> $destFolder"
    }
    
    Write-Host "Starting DISM injection: /Image:$WindowsPath /Add-Driver /Driver:$exportRoot /Recurse"
    $Output = "$env:systemdrive\_2p\Logs\DISMMigrateDriversOutput.txt"
    $DISM = Start-Process DISM.EXE -ArgumentList "/image:$($WindowsPath)\ /Add-Driver /driver:$exportRoot /recurse" -PassThru -NoNewWindow -RedirectStandardOutput $Output
    #& Dism /Image:$WindowsPath /Add-Driver /Driver:$exportRoot /Recurse
    $SameLastLine = $null
    do {  #Continous loop while DISM is running
        Start-Sleep -Milliseconds 300
        
        #Read in the DISM Logfile
        $Content = Get-Content -Path $Output -ReadCount 1
        $LastLine = $Content | Select-Object -Last 1
        if ($LastLine){
            if ($SameLastLine -ne $LastLine){ #Only continue if DISM log has changed
                $SameLastLine = $LastLine
                Write-Output $LastLine
                if ($LastLine -match "Searching for driver packages to install..."){
                    #Write-Output $LastLine
                    Write-Progress -Activity "Migrating Drivers" -Status $LastLine -PercentComplete 5
                }
                elseif ($LastLine -match "Installing"){
                    #Write-Output $LastLine
                    $Message = $Content | Where-Object {$_ -match "Installing"} | Select-Object -Last 1
                    if ($Message){
                        $ToRemove = $Message.Split(':') | Select-Object -Last 1
                        $Message = $Message.Replace(":$($ToRemove)","")
                        $Message = $Message.Replace($exportRoot,"")
                        $Total = (($Message.Split("-")[0]).Split("of") | Select-Object -Last 1).replace(" ","")
                        $Counter = ((($Message.Split("-")[0]).Split("of") | Select-Object -First 1).replace(" ","")).replace("Installing","")
                        if ($Counter -eq "0"){$Counter = 1}
                        $Total = $Total + 1 #So that when it gets to 3 of 3, it doesn't show 100% complete while it is still installing
                        $PercentComplete = [math]::Round(($Counter / $Total) * 100)
                        Write-Progress -Activity "Migrating Drivers" -Status $LastLine -PercentComplete $PercentComplete
                        
                    }
                }
                elseif ($LastLine -match "The operation completed successfully."){
                    Write-Progress -Activity "Migrating Drivers" -Status $LastLine -Completed
                }
                else{
                    Write-Progress -Activity "Migrating Drivers" -Status $LastLine -Completed
                }
            }
        }
        
    }
    until (!(Get-Process -Name DISM -ErrorAction SilentlyContinue))
    
    Write-Output "Dism Step Complete"
    Write-Output "See DISM log for more Details: $Output"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: DISM exited with $LASTEXITCODE" -Severity 3
    }
    else {
        Write-Host "DISM injection completed successfully."
    }
    $endTime = Get-Date
    $ScriptDuration = timeDuration $((New-TimeSpan -Start $startTime -End $endTime).TotalSeconds)
    $ScriptDuration = $ScriptDuration.Trim()
    Write-Output "Total export process took: $ScriptDuration"
    
}
#endregion

#_______________________________________________________________________________________#
# Doing Stuff Now...

#Region migrate active drivers from WinPE into Full OS
Write-Host "Attempting to Migrate WInPE Drivers to Offline OS as fallback"
if ($env:SystemDrive -eq "X:"){
    Migrate-WinPEDrivers -OfflineOSPath "$($TargetSystemDrive)\"
}
#endregion

if ($Make -eq "Acer"){
    Write-Host "Acer Systems do not have a Driver Pack Option, exiting script."
    exit 0
}

write-host "=============================================================="
write-host "Continuing with OEM Feeds to Get Drivers"
#Confirm compatibility with HP Model if HP Device
if ($MakeAlias -eq "HP"){
    if (Test-HPIASupport){
        Write-Host "This Platform is supported by HPIA"
    }
    else {
        Write-Host "This Platform is not supported by HPIA"
        exit 0
    }
}


if ($MakeAlias -eq "Panasonic Corporation"){
    $PanasonicCatalogURL = "https://na.panasonic.com/computer/software/apps/Panasonic.json"
    $JSONCatalog = Invoke-RestMethod -Uri $PanasonicCatalogURL
    $PanasonicDriverPacks = $JSONCatalog.PanasonicModels.$ModelAlias
    if ($null -eq $PanasonicDriverPacks) {
        Write-Host "No Panasonic Driver Packs found for the specified model $ModelAlias."
        exit 0
    }
    if ($OSImageBuild -lt 22000){
        $PanasonicDriverPack = $PanasonicDriverPacks.URL10
    }
    else {
        $PanasonicDriverPack = $PanasonicDriverPacks.URL11
    }
}

if ($DriverPackOption -eq "Migrate Only"){
    Write-Host "Driver Pack Option is set to MigrateOnly, exiting script."
    exit 0
}
#Find extraction tools
if (Test-path -Path "X:\_2P\content\00000000-0000-0000-0000-000000000002\Tools\x64"){
    $ToolsPath = "X:\_2P\content\00000000-0000-0000-0000-000000000002\Tools\x64"
    $SevenZipPath = "$ToolsPath\7za.exe"
    $InnoExtractPath = "$ToolsPath\innoextract.exe"
} elseif (Test-path -Path "S:\_2P\content\00000000-0000-0000-0000-000000000002\Tools\x64"){
    $ToolsPath = "S:\_2P\content\00000000-0000-0000-0000-000000000002\Tools\x64"
    $SevenZipPath = "$ToolsPath\7za.exe"
    $InnoExtractPath = "$ToolsPath\innoextract.exe"
} else {
    Write-Host "Unable to find Tools Path, please ensure the Tools are available in the expected location."
    Exit 1
}
if (Test-Path -path $SevenZipPath){
    Write-Host "Found 7-Zip at $SevenZipPath"
} else {
    Write-Host "Unable to find 7-Zip at $SevenZipPath, please ensure the Tools are available in the expected location."
    Exit 1
}   
if (Test-Path -path $InnoExtractPath){
    Write-Host "Found InnoExtract at $InnoExtractPath"
} else {
    Write-Host "Unable to find InnoExtract at $InnoExtractPath, please ensure the Tools are available in the expected location."
    Exit 1
}

#Import DeployR.Utility module
if (-not (Get-Module -Name DeployR.Utility)) {
    Import-Module X:\_2P\Client\PSModules\DeployR.Utility\DeployR.Utility.psd1 -Force -ErrorAction Stop
}

#Build Download Content Location
$DownloadContentPath = "$TargetSystemDrive\Drivers\Dls"
if (!(Test-Path -Path $DownloadContentPath)) {
    New-Item -ItemType Directory -Path $DownloadContentPath -Force | Out-Null
}
$ExtractedDriverLocation = "$TargetSystemDrive\Drivers\Ex"
if (!(Test-Path -Path $ExtractedDriverLocation)) {
    New-Item -ItemType Directory -Path $ExtractedDriverLocation -Force | Out-Null
}

#Using the Traditional Driver Pack from the OEM
#Panasonic Corporation is a special case, as it does not have a Driver Update Catalog Option yet, but rather a single driver download
write-host ""
Write-Host "---------------------------------------------------------------------------"
if ($DriverPackOption -eq "Standard" -or $MakeAlias -eq "Panasonic Corporation" -or $MakeAlias -eq "Microsoft") {
    Write-Host "Using Standard Driver Pack for WinPE"
    if ($MakeAlias -eq "Lenovo"){
        $DriverPack = Find-LnvDriverPack -MachineType (Get-LnvMachineType) -Latest
        if ($null -ne $DriverPack) {
            $URL = $DriverPack.'#text'
            $Name = ($DriverPack.'#text').split("/") | Select-Object -last 1
            $ID = (Get-LnvMachineType)
        }
    }
    if ($MakeAlias -eq "HP"){
        $DriverPack = Get-HPDriverPackLatest
        if ($null -ne $DriverPack) {
            $URL = "http://$($DriverPack.url)"
            $Name = $DriverPack.Name
            $ID = $DriverPack.id
        }
    }
    if ($MakeAlias -eq "Dell"){
        
        $DriverPack = Get-DellDeviceDriverPack | Select-Object -first 1
        if ($null -ne $DriverPack) {
            $URL = $DriverPack.URL
            $Name = $DriverPack.FileName
            $ID = $DriverPack.ReleaseID
        }
    }
    if ($MakeAlias -eq "Panasonic Corporation"){
        
        $DriverPack = $PanasonicDriverPack
        if ($null -ne $DriverPack) {
            $URL = $DriverPack
            $NameChunks = (($DriverPack.split("/") | Select-Object -last 1).split("_") | select-object -first 2)
            $Name = $NameChunks -join "_"
            $ID = $ModelAlias
        }
    }
    if ($MakeAlias -eq "Microsoft") {
        $DriverPack = Get-SurfaceDPDownloads
        if ($null -ne $DriverPack) {
            if ($OSImageBuild -lt 22000){
                $URL = $DriverPack.Windows10Url
                $Name = $DriverPack.Windows10FileName
                $ID = $DriverPack.SystemSKU
            }
            else {
                $URL = $DriverPack.Windows11Url
                $Name = $DriverPack.Windows11FileName
                $ID = $DriverPack.SystemSKU
            }
        }
    }        
    if ($null -ne $DriverPack) {
        Write-Host "Found Driver Pack"
        ${TSEnv:DriverPackURL} = $URL
        ${TSEnv:DriverPackName} = $Name
        ${TSEnv:DriverPackID} = $ID
        ${TSEnv:DriverPackCustom} = $false
        Write-Output $DriverPack
        Write-Host "Downloading and extracting  Driver Pack to $ExtractedDriverLocation"
        write-host "Invoke-DriverDownloadExpand -URL $URL -Name $Name -ID $ID -ToolsPath $ToolsPath -DestinationPath $ExtractedDriverLocation"
        Invoke-DriverDownloadExpand -URL $URL -Name $Name -ID $ID -ToolsPath $ToolsPath -DestinationPath $ExtractedDriverLocation -Cleanup $Cleanup
    } else {
        Write-Host "No Driver Pack found for the specified model."
        exit 0
    }
    
}
#Downloading Driver Updates directly from the OEM, extracting and applying them to the Offline OS
else {
    Write-Host "Scanning for $MakeAlias Drivers to Apply to Offline OS"
    if ($MakeAlias -eq "Dell") {
        
        $Drivers = Get-DCUUpdateList -Latest -updateType driver
        #Prune Bluetooth, Wi-Fi, Firmware
        $Drivers = $Drivers | Where-Object {$_.Name -notmatch "Bluetooth"}
        $Drivers = $Drivers | Where-Object {$_.Name -notmatch "Wi-Fi"}
        $Drivers = $Drivers | Where-Object {$_.Name -notmatch "Firmware"}
        Write-Host "Found $($Drivers.Count) drivers to process. [Including Graphics & Audio]"
        #Graphics
        #If Intel, and several available, only grab latest
        if ($IncludeGraphicsIntel -eq "true") {
            $Graphics = $Drivers | Where-Object {($_.Category -match "Video" -and $_.Name -match "Intel")}
            if ($Graphics.Count -gt 1) {
                Write-Host "Reducing Graphic Options, Currently Selected"
                foreach ($Graphic in $Graphics){
                    write-host "$($Graphic.Name) | $($Graphic.VendorVersion) | $($Graphic.ReleaseDate)"
                }
                $Graphics = $Graphics | Sort-Object -Property "ReleaseDate" | Select-Object -Last 1
                Write-Host "Narrowed down to $($Graphics.Name) | $($Graphics.VendorVersion) | $($Graphics.ReleaseDate)"
            }
        }
        #If not limited, just grab everything, including multiples of the same vendor
        if ($IncludeGraphics -eq "true") {
            $Graphics = $Drivers | Where-Object {$_.Category -match "Video" }
        }
        #Clear out Graphics Drivers from Object
        $Drivers = $Drivers | Where-Object {$_.Name -notmatch "Graphics"}
        #If Graphics are supposed to be there, put them back in.
        if ($Graphics){
            $Drivers += $Graphics
        }
        
        #Audio
        if ($IncludeAudio -ne "true") {
            $Drivers = $Drivers | Where-Object {$_.Name -notmatch "Audio"}
        }
        Write-Host "Found $($Drivers.Count) drivers to process after Cleanup"
    }
    if ($MakeAlias -eq "HP") {
        $Drivers = Get-HPSoftpaqListLatest | where-object {$_.Category -match "Driver" -and $_.Category -notmatch "Firmware" -and $_.Category -notmatch "Manageability" -and $_.Category -notmatch "Enabling"}
        #Graphics
        if ($IncludeGraphicsIntel -eq "true") {
            $Graphics = $Drivers | Where-Object {($_.Category -match "Graphics" -and $_.Name -match "Intel")}
        }
        if ($IncludeGraphics -eq "true") {
            $Graphics = $Drivers | Where-Object {$_.Category -match "Graphics" }
        }
        #Clear out Graphics Drivers from Object
        $Drivers = $Drivers | Where-Object {$_.Category -notmatch "Graphics"}
        #If Graphics are supposed to be there, put them back in.
        if ($Graphics){
            $Drivers += $Graphics
        }
        
        #Audio
        if ($IncludeAudio -ne "true") {
            $Drivers = $Drivers | Where-Object {$_.Name -notmatch "Audio"}
        }
        Write-Host "Found $($Drivers.Count) drivers to process after Cleanup"
    }
    if ($MakeAlias -eq "Lenovo") {
        $Drivers = Find-LnvUpdate -MachineType (Get-LnvMachineType) -ListAll -WindowsVersion 11
        $Drivers = $Drivers | Where-Object {$_.Name -notmatch "BIOS" -and $_.Name -notmatch "Firmware" -and $_.Name -notmatch "FW"  -and $_.Name -notmatch "Lenovo Base Utility"  -and $_.Name -notmatch "WAN"}
        #Graphics
        if ($IncludeGraphicsIntel -eq "true") {
            $Graphics = $Drivers | Where-Object {($_.Category -match "Graphics" -and $_.Name -match "Intel")}
        }
        if ($IncludeGraphics -eq "true") {
            $Graphics = $Drivers | Where-Object {$_.Category -match "Graphics" }
        }
        #Clear out Graphics Drivers from Object
        $Drivers = $Drivers | Where-Object {$_.Category -notmatch "Graphics"}
        #If Graphics are supposed to be there, put them back in.
        if ($Graphics){
            $Drivers += $Graphics
        }
        #Audio
        if ($IncludeAudio -ne "true") {
            $Drivers = $Drivers | Where-Object {$_.Category -notmatch "Audio"}
        }
    }
    if ($Drivers.Count -eq 0) {
        Write-Host "No drivers found for the specified criteria." -ForegroundColor Red
        exit 0
    }
    Write-Host "Found $($Drivers.Count) drivers to process."
    Write-Output $Drivers.Name
    
    write-host ""
    Write-Host "---------------------------------------------------------------------------"
    Write-Host "Starting Downloading Drivers to $DownloadContentPath"
    
    Foreach ($Driver in $Drivers){
        
        #Generalize Variable Names
        if ($MakeAlias -eq "Dell") {
            $Name = $Driver.Name
            $URL = $Driver.Path
            $ID = $Driver.PackageID
        }
        if ($MakeAlias -eq "HP") {
            $Name = $Driver.Name
            $URL = "https://$($Driver.Url)"
            $ID = $Driver.Id
        }
        if ($MakeAlias -eq "Lenovo") {
            $Name = $Driver.Name
            $URL = $Driver.PackageExe
            $ID = $Driver.Id
        }
        
        Write-Host "Driver: $NAME" -ForegroundColor Magenta
        
        
        
        if ($null -ne $URL){
            
            
            Write-Host "Downloading Driver from: $URL" -ForegroundColor Cyan
            
            #Start-BitsTransfer -Source "https://$($Driver.PackageExe)" -Destination "$DownloadContentPath\$($Driver.id).exe" -DisplayName $Driver.Name -Description $Driver.Description -ErrorAction SilentlyContinue
            try {
                #Request-DeployRCustomContent -ContentName $($Driver.Id) -ContentFriendlyName $($Driver.Name) -URL "$($Driver.PackageExe)" -DestinationPath $DownloadContentPath -ErrorAction SilentlyContinue
                $destFile = Request-DeployRCustomContent -ContentName $ID -ContentFriendlyName $NAME -URL $URL -DestinationPath $DownloadContentPath -ErrorAction SilentlyContinue
                $GetItemOutFile = Get-Item $destFile
                $ExpandFile = $GetItemOutFile.FullName
                if (Test-Path -path $ExpandFile) {
                    Write-Host "Downloaded driver to: $ExpandFile" -ForegroundColor Green
                }
            } catch {
                Write-Host "Failed to download driver: $Name" -ForegroundColor red
                Write-Host "Going to try again with Invoke-WebRequest" -ForegroundColor Yellow
                $ExpandFile = Join-Path -Path $DownloadContentPath -ChildPath "$ID.exe"
                Invoke-WebRequest -Uri $URL -OutFile $ExpandFile -UseBasicParsing
            }
        }
        else {
            Write-Host "No URL found for this driver, skipping download."
        }
    }
    write-host ""
    Write-Host "---------------------------------------------------------------------------"
    Write-Host "Starting Extracting Drivers to $ExtractedDriverLocation"
    $DriversDownloads = Get-ChildItem -Path $DownloadContentPath -Filter *.exe -Recurse
    if ($DriversDownloads) {
        $TotalDrivers = $DriversDownloads.Count
        ${TSEnv:DriverPackCustom} = $true
        ${TSEnv:DriverPackCustomCount} = $TotalDrivers
        $DriverCurrentCount = 0
        foreach ($DriverDownload in $DriversDownloads) {
            $DriverCurrentCount++
            $PercentComplete = [math]::Round(($DriverCurrentCount / $TotalDrivers) * 100)
            Write-Host "Found Driver Download: $($DriverDownload.Name)"
            $FolderName = $DriverDownload.Name -replace '.exe',''
            $ExpandFile = $DriverDownload.FullName
            $ExtractedDriverPath = "$ExtractedDriverLocation\$FolderName"
            if (!(Test-Path -Path $ExtractedDriverPath)) {
                New-Item -ItemType Directory -Path $ExtractedDriverPath -Force | Out-Null
            }
            Write-Host "Expanding Driver to $ExtractedDriverPath"
            Write-Progress -Activity "Extracting Drivers" -Status "Extracting $ExpandFile" -PercentComplete $PercentComplete
            if ($MakeAlias -eq "Dell") {
                try {
                    Start-Process -FilePath $ExpandFile -ArgumentList "/s /e=`"$ExtractedDriverPath`"" -Wait -NoNewWindow -PassThru
                } catch {
                    try {
                        Write-Host "Failed to expand Dell driver, trying with 7zip" -ForegroundColor Yellow
                        Start-Process -FilePath $SevenZipPath -ArgumentList "x $ExpandFile -o$ExtractedDriverPath -y" -Wait -NoNewWindow -PassThru
                    } catch {
                        try { 
                            Write-Host "Failed to expand Dell driver with Inno" -ForegroundColor Red
                            Start-Process -FilePath $InnoExtractPath -ArgumentList "-e -d $ExtractedDriverPath $ExpandFile" -Wait -NoNewWindow -PassThru
                        }
                        catch{
                            write-Host "Unable to Extract Driver File with any of the 3 methods."
                        }
                    }
                }
                #Start-Process -FilePath $ExpandFile -ArgumentList "/s /e=`"$ExtractedDriverPath`"" -Wait -NoNewWindow -PassThru
                #Start-Process -FilePath $SevenZipPath -ArgumentList "x $ExpandFile -o$ExtractedDriverPath -y" -Wait -NoNewWindow -PassThru
            }
            if ($MakeAlias -eq "HP") {
                Start-Process -FilePath $SevenZipPath -ArgumentList "x $ExpandFile -o$ExtractedDriverPath -y" -Wait -NoNewWindow -PassThru
            }
            if ($MakeAlias -eq "Lenovo") {
                Start-Process -FilePath $InnoExtractPath -ArgumentList "-e -d $ExtractedDriverPath $ExpandFile" -Wait -NoNewWindow -PassThru
            }
            
        }
    } 
    else {
        Write-Host "No Downloaded Driver EXE files Found" -ForegroundColor Red
    }
}
#Apply Drivers in ExtractedDriverLocation to Offline OS
if ($ApplyDrivers -eq $false){
    Write-Host "Skipping Driver Application to Offline OS"
    return
}
else {
    Write-Host -ForegroundColor Cyan "Applying Drivers to Offline OS at $TargetSystemDrive from $ExtractedDriverLocation"
    #Add-WindowsDriver -Path "$($TargetSystemDrive)\" -Driver "$ExtractedDriverLocation" -Recurse -ErrorAction SilentlyContinue -LogPath $LogPath\AddDrivers.log
    
    #& Dism /Image:"$($TargetSystemDrive)\" /Add-Driver /Driver:$ExtractedDriverLocation /Recurse
    $Output = "S:\_2p\Logs\DISMApplyDriversOutput.txt"
    try {
        $DISM = Start-Process DISM.EXE -ArgumentList "/image:$($TargetSystemDrive)\ /Add-Driver /driver:$ExtractedDriverLocation /recurse" -PassThru -NoNewWindow -RedirectStandardOutput $Output
    }
    catch {
        <#Do this if a terminating exception happens#>
    }
    
    
    #& Dism /Image:$WindowsPath /Add-Driver /Driver:$exportRoot /Recurse
    $SameLastLine = $null
    do {  #Continous loop while DISM is running
        Start-Sleep -Milliseconds 300
        
        #Read in the DISM Logfile
        $Content = Get-Content -Path $Output -ReadCount 1
        $LastLine = $Content | Select-Object -Last 1
        if ($LastLine){
            if ($SameLastLine -ne $LastLine){ #Only continue if DISM log has changed
                $SameLastLine = $LastLine
                Write-Output $LastLine
                if ($LastLine -match "Searching for driver packages to install..."){
                    #Write-Output $LastLine
                    Write-Progress -Activity "Applying Drivers" -Status $LastLine -PercentComplete 5
                }
                elseif ($LastLine -match "Installing"){
                    #Write-Output $LastLine
                    $Message = $Content | Where-Object {$_ -match "Installing"} | Select-Object -Last 1
                    if ($Message){
                        $ToRemove = $Message.Split(':') | Select-Object -Last 1
                        $Message = $Message.Replace(":$($ToRemove)","")
                        $Message = $Message.Replace($ExtractedDriverLocation,"")
                        $Total = (($Message.Split("-")[0]).Split("of") | Select-Object -Last 1).replace(" ","")
                        [int]$Counter = ((($Message.Split("-")[0]).Split("of") | Select-Object -First 1).replace(" ","")).replace("Installing","")
                        if ([int]$Counter -eq "0"){[int]$Counter = 1}
                        [int]$Total = [int]$Total + 1 #So that when it gets to 3 of 3, it doesn't show 100% complete while it is still installing
                        $PercentComplete = [math]::Round(($Counter / $Total) * 100)
                        Write-Progress -Activity "Applying Drivers" -Status $LastLine -PercentComplete $PercentComplete
                        
                    }
                }
                elseif ($LastLine -match "The operation completed successfully."){
                    Write-Progress -Activity "Migrating Drivers" -Status $LastLine -Completed
                }
                else{
                    Write-Progress -Activity "Migrating Drivers" -Status $LastLine -Completed
                }
            }
        }
        
    }
    until (!(Get-Process -Name DISM -ErrorAction SilentlyContinue))
    
    if ($Cleanup -eq "True"){
        Remove-Item -Path $dest  -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Cleaned up driver files at $dest"
    }
    exit 0
}
