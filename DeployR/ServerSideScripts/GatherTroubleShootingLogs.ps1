<#
Grab the DeployR Registry Key info to get Path Information
Grab several logs and package them into a zip file for troubleshooting


#>


$TempFolder = "$env:USERPROFILE\Downloads\DeployR_TroubleShootingLogs"
if (!(Test-Path -Path $TempFolder)){New-Item -Path $TempFolder -ItemType Directory -Force | Out-Null}


Function Find-EventLogs {
    <#
    .SYNOPSIS
        Finds StifleR-related event logs on the system.
    
    .DESCRIPTION
        By default, lists all StifleR event log providers and their associated logs.
        Optionally exports the logs to a specified directory.
    
    .PARAMETER Export
        If specified, exports the found event logs to the OutputDirectory.
    
    .PARAMETER OutputDirectory
        Directory where event logs will be exported (only used with -Export).
        Default: $env:USERPROFILE\Downloads\DeployR_TroubleShootingLogs
    
    .PARAMETER LogNameFilter
        Filter for log provider names. Default: *StifleR*
    
    .EXAMPLE
        Find-EventLogs
        Lists all StifleR event logs found on the system.
    
    .EXAMPLE
        Find-EventLogs -Export
        Finds and exports all StifleR event logs to the default directory.
    
    .EXAMPLE
        Find-EventLogs -Export -OutputDirectory "C:\Logs"
        Finds and exports event logs to C:\Logs.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]$Export,
        
        [Parameter()]
        [string]$OutputDirectory = "$env:USERPROFILE\Downloads\DeployR_TroubleShootingLogs",
        
        [Parameter()]
        [string]$LogNameFilter = "*DeployR*"
    )

    # Get all StifleR event log providers
    Write-Host "Searching for event logs matching: $LogNameFilter" -ForegroundColor Cyan
    $Providers = Get-WinEvent -ListProvider $LogNameFilter -ErrorAction SilentlyContinue

    if (-not $Providers) {
        Write-Warning "No event log providers found matching '$LogNameFilter'"
        return
    }

    $foundLogs = @()

    # Process each provider
    foreach ($provider in $Providers) {
        $providerName = $provider.ProviderName
        $events = (Get-WinEvent -ListProvider $providerName -ErrorAction SilentlyContinue).Events
        
        if ($events) {
            $logLinks = $provider.LogLinks.LogName
            
            foreach ($logLink in $logLinks) {
                $foundLogs += [PSCustomObject]@{
                    ProviderName = $providerName
                    LogName = $logLink
                    EventCount = $events.Count
                }
            }
        }
    }

    # Display found logs
    if ($foundLogs.Count -gt 0) {
        Write-Host "`nFound $($foundLogs.Count) event log(s):" -ForegroundColor Green
        $foundLogs | Format-Table -AutoSize
    }
    else {
        Write-Warning "No event logs found with events for providers matching '$LogNameFilter'"
        return
    }

    # Export if requested
    if ($Export) {
        Write-Host "`nExporting event logs..." -ForegroundColor Cyan
        
        # Ensure the output directory exists
        if (-not (Test-Path -Path $OutputDirectory)) {
            New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
            Write-Host "Created output directory: $OutputDirectory" -ForegroundColor Gray
        }

        $exportCount = 0
        
        # Export each event log
        foreach ($provider in $Providers) {
            $logName = $provider.ProviderName
            $logFilePath = Join-Path -Path $OutputDirectory -ChildPath "$logName"
            $events = (Get-WinEvent -ListProvider $logName -ErrorAction SilentlyContinue).Events
            
            if ($events) {
                # Export event definitions to CSV
                $events | Export-Csv -Path "$logFilePath.csv" -Force -NoTypeInformation
                Write-Host "  Exported: $logName.csv" -ForegroundColor Gray
                
                # Export actual event logs
                $logLinks = $provider.LogLinks.LogName
                foreach ($logLink in $logLinks) {
                    $safeLogName = $logLink.Replace('/', '_')
                    $evtxFilePath = Join-Path -Path $OutputDirectory -ChildPath "$safeLogName"
                    
                    try {
                        Start-Process wevtutil.exe -ArgumentList "export-log `"$logLink`" `"$evtxFilePath.evtx`"" -NoNewWindow -Wait -ErrorAction Stop
                        Write-Host "  Exported: $safeLogName.evtx" -ForegroundColor Gray
                        $exportCount++
                    }
                    catch {
                        Write-Warning "  Failed to export: $logLink - $_"
                    }
                }
            }
        }

        Write-Host "`nExport complete! $exportCount log file(s) exported to: $OutputDirectory" -ForegroundColor Green
    }
    
    return $foundLogs
}


#Get DeployR Log Files
$DeployRRegPath = "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"
$ContentLocation = (Get-ItemProperty -Path $DeployRRegPath).ContentLocation
$LogFiles = Get-ChildItem -Path "$ContentLocation" -Filter "*.log" -Recurse

foreach ($LogFile in $LogFiles){
    Copy-Item -Path $LogFile.FullName -Destination $TempFolder -Force
}

#Get DeployR Event Logs
Find-EventLogs -Export -OutputDirectory $TempFolder -LogNameFilter "*DeployR*"

#Compress the logs into a zip file (with time stamp)
$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ZipFilePath = "$env:USERPROFILE\Downloads\DeployR_TroubleShootingLogs_$TimeStamp.zip"
if (Test-Path -Path $ZipFilePath){
    Remove-Item -Path $ZipFilePath -Force
}
Compress-Archive -Path "$TempFolder\*" -DestinationPath $ZipFilePath -Force 
