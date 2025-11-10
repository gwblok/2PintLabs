<#
.SYNOPSIS
    Downloads the DeployR ISO using BITS transfer

.DESCRIPTION
    This script downloads the DeployR_x64_noprompt.iso file from the 2Pint Labs server
    using Background Intelligent Transfer Service (BITS) for reliable downloading.

.PARAMETER Url
    The URL to download from

.PARAMETER Destination
    The destination folder path where the file will be saved

.EXAMPLE
    .\DownloadDeployRIso.ps1

.NOTES
    Author: Gary Blok
    Date: November 5, 2025
#>

function Download-FileWithBITS {
    <#
    .SYNOPSIS
        Downloads a file using BITS (Background Intelligent Transfer Service)
    
    .DESCRIPTION
        Uses BITS to download a file with automatic resume capability and efficient bandwidth usage.
        Falls back to Invoke-WebRequest if BITS is not available.
    
    .PARAMETER Url
        The URL of the file to download
    
    .PARAMETER Destination
        The full path where the file should be saved (including filename)
    
    .EXAMPLE
        Download-FileWithBITS -Url "https://example.com/file.iso" -Destination "C:\Downloads\file.iso"
    
    .OUTPUTS
        Returns a PSCustomObject with download results including Success, FilePath, and any error Message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        
        [Parameter(Mandatory=$true)]
        [string]$Destination,

        [Parameter(Mandatory=$false)]
        [string]$ID = "DeployR_Iso"
    )
    
    
    try {
        Write-Host "Downloading from: $Url" -ForegroundColor Cyan
        Write-Host "Destination: $Destination" -ForegroundColor Cyan
        
        # Ensure destination directory exists
        $destFolder = Split-Path -Parent $Destination
        if (-not (Test-Path $destFolder)) {
            Write-Host "Creating destination folder: $destFolder" -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
        }
        
        # Check if file already exists
        if (Test-Path $Destination) {
            $overwrite = Read-Host "File already exists at $Destination. Overwrite? (Y/N)"
            if ($overwrite -ne 'Y') {
                Write-Host "Download cancelled by user." -ForegroundColor Yellow
                return [PSCustomObject]@{
                    Success = $false
                    FilePath = $Destination
                    Message = "Download cancelled - file already exists"
                }
            }
            Remove-Item $Destination -Force
        }
        
        #Try Using DeployR built in download first
        try { 
            $Name = $Url.Split('/')[-1]
            $ID = $Name
            $destFile = Request-DeployRCustomContent -ContentName $ID -ContentFriendlyName $Name -URL $URL
            $GetItemOutFile = Get-Item $destFile
            $DownloadedFile = $GetItemOutFile.FullName
            if (Test-Path -path $DownloadedFile){
                Copy-Item -Path $DownloadedFile -Destination $Destination -Force
                Write-Host "Download completed successfully using DeployR custom content!" -ForegroundColor Green
                return [PSCustomObject]@{
                    Success = $true
                    FilePath = $Destination
                    Message = "Downloaded successfully using DeployR custom content"
                }
            }
            Write-Verbose -Message "DriverPack: $DownloadedFile"
        } catch {
            Write-Error "Failed to request DeployR custom content: $($_.Exception.Message)"
        }


        # Try using BITS first
        try {
            Write-Host "Starting BITS transfer..." -ForegroundColor Green
            
            # Start BITS transfer
            $bitsJob = Start-BitsTransfer -Source $Url -Destination $Destination -DisplayName "DeployR ISO Download" -Description "Downloading DeployR ISO" -Asynchronous
            
            # Monitor progress
            $lastProgress = -1
            while (($bitsJob.JobState -eq 'Transferring') -or ($bitsJob.JobState -eq 'Connecting')) {
                $progress = [int](($bitsJob.BytesTransferred / $bitsJob.BytesTotal) * 100)
                if ($progress -ne $lastProgress) {
                    $downloadedMB = [math]::Round($bitsJob.BytesTransferred / 1MB, 2)
                    $totalMB = [math]::Round($bitsJob.BytesTotal / 1MB, 2)
                    Write-Progress -Activity "Downloading file" -Status "$progress% Complete ($downloadedMB MB / $totalMB MB)" -PercentComplete $progress
                    $lastProgress = $progress
                }
                Start-Sleep -Milliseconds 500
            }
            
            # Complete the transfer
            Complete-BitsTransfer -BitsJob $bitsJob
            Write-Progress -Activity "Downloading file" -Completed
            
            Write-Host "Download completed successfully using BITS!" -ForegroundColor Green
            
            return [PSCustomObject]@{
                Success = $true
                FilePath = $Destination
                Message = "Downloaded successfully using BITS"
            }
        }
        catch {
            Write-Warning "BITS transfer failed: $($_.Exception.Message)"
            Write-Host "Falling back to Invoke-WebRequest..." -ForegroundColor Yellow
            
            # Fallback to Invoke-WebRequest
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
            $ProgressPreference = 'Continue'
            
            Write-Host "Download completed successfully using Invoke-WebRequest!" -ForegroundColor Green
            
            return [PSCustomObject]@{
                Success = $true
                FilePath = $Destination
                Message = "Downloaded successfully using Invoke-WebRequest (BITS fallback)"
            }
        }
    }
    catch {
        Write-Error "Download failed: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Success = $false
            FilePath = $Destination
            Message = "Download failed: $($_.Exception.Message)"
        }
    }
}

# Main Script Execution
Write-Host "`n===================================" -ForegroundColor Cyan
Write-Host "DeployR ISO Downloader" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan

# Define download parameters
$isoUrl = "https://dr.2pintlabs.com:7281/Content/Boot/DeployR_x64_noprompt.iso"
$destinationFolder = "C:\HyperVLab"
$fileName = "DeployR_x64_noprompt.iso"
$destinationPath = Join-Path -Path $destinationFolder -ChildPath $fileName

# Execute download
$result = Download-FileWithBITS -Url $isoUrl -Destination $destinationPath

# Display results
Write-Host "`n===================================" -ForegroundColor Cyan
Write-Host "Download Summary" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Success: $($result.Success)" -ForegroundColor $(if($result.Success){"Green"}else{"Red"})
Write-Host "File Path: $($result.FilePath)" -ForegroundColor Cyan
Write-Host "Message: $($result.Message)" -ForegroundColor Cyan

if ($result.Success) {
    $fileSize = [math]::Round((Get-Item $result.FilePath).Length / 1GB, 2)
    Write-Host "File Size: $fileSize GB" -ForegroundColor Cyan
}
