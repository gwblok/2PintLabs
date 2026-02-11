function Get-StifleRClientData {
    <#
    .SYNOPSIS
        Retrieves and merges StifleR client data with hardware information, removes duplicates based on MAC address.
    
    .PARAMETER ExportCsv
        Switch parameter to export the results to a CSV file. File will be saved in the OutputFolder as "StifleRClientData_<timestamp>.csv"
    
    .PARAMETER ExportJson
        Switch parameter to export the results to a JSON file. File will be saved in the OutputFolder as "StifleRClientData_<timestamp>.json"
    
    .PARAMETER OutputFolder
        The folder path where CSV and JSON files will be exported. Default is "c:\windows\temp"
    
    .EXAMPLE
        Get-StifleRClientData
        # Returns merged client data with duplicates removed
    
    .EXAMPLE
        Get-StifleRClientData -ExportCsv
        # Returns data and exports to CSV file
    
    .EXAMPLE
        Get-StifleRClientData -ExportJson
        # Returns data and exports to JSON file
    #>
    
    [CmdletBinding()]
    param (
        [switch]$ExportCsv,
        [switch]$ExportJson,
        [string]$OutputFolder = "c:\windows\temp"
    )

    $namespace = "ROOT\StifleR"
    $classname = "Clients"

    $ClientData = Get-CimInstance -Class $classname -Namespace $namespace 
    $ClientData = $ClientData | Select-Object -Property ComputerName, ClientVersion, MacAddress, AgentID, NetId, NetworkGroupId, LocationId, DateAdded, DateConnected, ClientHardwareDataId, OSVersion
    $ClientHardware = Get-CimInstance -class 'Hardware' -Namespace $namespace

    # For Each Client in Client Data, build PSObject to merge the data from ClientData & ClientHardware where ClientHardware ID = ClientData ClientHardwareDataId
    $MergedClientData = foreach ($Client in $ClientData) {
        $Hardware = $ClientHardware | Where-Object { $_.ID -eq $Client.ClientHardwareDataId }
        
        [PSCustomObject]@{
            ComputerName = $Client.ComputerName
            OSVersion = $Client.OSVersion
            ClientVersion = $Client.ClientVersion
            MacAddress = $Client.MacAddress
            AgentID = $Client.AgentID
            NetId = $Client.NetId
            NetworkGroupId = $Client.NetworkGroupId
            LocationId = $Client.LocationId
            DateAdded = $Client.DateAdded
            DateConnected = $Client.DateConnected
            BaseBoardProduct = $Hardware.BaseBoardProduct
            ModelAlias = $Hardware.ModelAlias
            SystemAlias = $Hardware.SystemAlias
            SystemFamily = $Hardware.SystemFamily
            SystemManufacturer = $Hardware.SystemManufacturer
            SystemProductName = $Hardware.SystemProductName
            ClientHardwareDataId = $Client.ClientHardwareDataId
            SystemSKU = $Hardware.SystemSKU
        }
    }

    # Count devices before cleanup
    $DeviceCountBefore = $MergedClientData.Count
    Write-Host "=== DEVICE CLEANUP SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Total Devices Before Cleanup: $DeviceCountBefore" -ForegroundColor Cyan

    # Remove devices starting with MININT or OSD
    $DeviceNamesRemoved = @()
    $MergedClientData = $MergedClientData | Where-Object {
        if ($_.ComputerName -match '^(MININT|OSD)') {
            $DeviceNamesRemoved += $_
            Write-Host "Filtering out: ComputerName=$($_.ComputerName) (matches MININT/OSD pattern)" -ForegroundColor Yellow
            $false
        }
        else {
            $true
        }
    }

    if ($DeviceNamesRemoved.Count -gt 0) {
        Write-Host "Removed $($DeviceNamesRemoved.Count) device(s) with MININT/OSD naming pattern" -ForegroundColor Yellow
    }

    # Remove duplicates based on MacAddress, keeping the one with the latest DateAdded
    $MacDuplicatesFound = $false
    $MergedClientData = $MergedClientData | 
        Sort-Object -Property DateAdded -Descending |
        Group-Object -Property MacAddress |
        ForEach-Object { 
            if ($_.Group.Count -gt 1) {
                $MacDuplicatesFound = $true
                $MacAddress = $_.Name
                Write-Host "Found $($_.Group.Count) duplicates for MAC Address: $MacAddress" -ForegroundColor Yellow
                
                $Keep = $_.Group | Select-Object -First 1
                $Remove = $_.Group | Select-Object -Skip 1
                
                foreach ($Entry in $Remove) {
                    Write-Host "  Removing: ComputerName=$($Entry.ComputerName), AgentID=$($Entry.AgentID), DateAdded=$($Entry.DateAdded)" -ForegroundColor Red
                }
                Write-Host "  Keeping: ComputerName=$($Keep.ComputerName), AgentID=$($Keep.AgentID), DateAdded=$($Keep.DateAdded)" -ForegroundColor Green
            }
            $_.Group | Select-Object -First 1
        }

    # Remove duplicates based on ComputerName, keeping the one with the latest DateAdded
    $ComputerNameDuplicatesFound = $false
    $MergedClientData = $MergedClientData | 
        Sort-Object -Property DateAdded -Descending |
        Group-Object -Property ComputerName |
        ForEach-Object { 
            if ($_.Group.Count -gt 1) {
                $ComputerNameDuplicatesFound = $true
                $ComputerName = $_.Name
                Write-Host "Found $($_.Group.Count) duplicates for ComputerName: $ComputerName" -ForegroundColor Yellow
                
                $Keep = $_.Group | Select-Object -First 1
                $Remove = $_.Group | Select-Object -Skip 1
                
                foreach ($Entry in $Remove) {
                    Write-Host "  Removing: MacAddress=$($Entry.MacAddress), AgentID=$($Entry.AgentID), DateAdded=$($Entry.DateAdded)" -ForegroundColor Red
                }
                Write-Host "  Keeping: MacAddress=$($Keep.MacAddress), AgentID=$($Keep.AgentID), DateAdded=$($Keep.DateAdded)" -ForegroundColor Green
            }
            $_.Group | Select-Object -First 1
        }

    # Count devices after cleanup
    $DeviceCountAfter = $MergedClientData.Count
    $DevicesRemoved = $DeviceCountBefore - $DeviceCountAfter

    if (-not $MacDuplicatesFound) {
        Write-Host "No duplicates found based on MAC Address" -ForegroundColor Green
    }

    if (-not $ComputerNameDuplicatesFound) {
        Write-Host "No duplicates found based on ComputerName" -ForegroundColor Green
    }

    Write-Host "Total Devices After Cleanup: $DeviceCountAfter" -ForegroundColor Cyan
    Write-Host "Total Devices Removed: $DevicesRemoved" -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan

    # Export to CSV if requested
    if ($ExportCsv) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $csvPath = Join-Path -Path $OutputFolder -ChildPath "StifleRClientData_$timestamp.csv"
        $MergedClientData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Data successfully exported to CSV: $csvPath" -ForegroundColor Green
    }

    # Export to JSON if requested
    if ($ExportJson) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $jsonPath = Join-Path -Path $OutputFolder -ChildPath "StifleRClientData_$timestamp.json"
        $MergedClientData | ConvertTo-Json | Out-File -FilePath $jsonPath -Encoding UTF8
        Write-Host "Data successfully exported to JSON: $jsonPath" -ForegroundColor Green
    }

    # Return the data only if not exporting
    if (-not ($ExportCsv -or $ExportJson)) {
        return $MergedClientData
    }
}
