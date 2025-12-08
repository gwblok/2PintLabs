function Convert-ImageToBase64 {
    <#
    .SYNOPSIS
        Resizes an image to 100px height (maintaining aspect ratio) and converts it to Base64.
    
    .DESCRIPTION
        Takes an image file path, resizes it to 100 pixels in height while maintaining the aspect ratio,
        and returns a PSObject containing the Base64 encoded string and size information.
    
    .PARAMETER ImagePath
        The full path to the image file to convert.
    
    .EXAMPLE
        $result = Convert-ImageToBase64 -ImagePath "C:\Images\logo.png"
        Write-Host "Original: $($result.OriginalResolution) ($($result.OriginalSizeKB) KB)"
        Write-Host "Resized: $($result.ResizedResolution) ($($result.ResizedSizeKB) KB)"
        Write-Host "Base64 length: $($result.Base64String.Length) characters"
    
    .OUTPUTS
        PSCustomObject with properties:
        - Base64String: The Base64 encoded image string
        - OriginalResolution: Original image resolution (e.g., "1920x1080")
        - OriginalSizeKB: Original file size in KB
        - ResizedResolution: Resized image resolution (e.g., "178x100")
        - ResizedSizeKB: Resized image size in KB
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$ImagePath
    )
    
    try {
        # Load required assembly
        Add-Type -AssemblyName System.Drawing
        
        # Get original file size
        $originalFileInfo = Get-Item $ImagePath
        $originalSizeKB = [math]::Round($originalFileInfo.Length / 1KB, 2)
        
        # Load the original image
        $originalImage = [System.Drawing.Image]::FromFile($ImagePath)
        $originalWidth = $originalImage.Width
        $originalHeight = $originalImage.Height
        $originalResolution = "${originalWidth}x${originalHeight}"
        
        Write-Verbose "Original image: $originalResolution ($originalSizeKB KB)"
        
        # Calculate new dimensions maintaining aspect ratio
        $targetHeight = 100
        $aspectRatio = $originalWidth / $originalHeight
        $targetWidth = [int]($targetHeight * $aspectRatio)
        
        Write-Verbose "Resizing to: ${targetWidth}x${targetHeight}"
        
        # Create resized bitmap
        $resizedBitmap = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight)
        $graphics = [System.Drawing.Graphics]::FromImage($resizedBitmap)
        
        # Set high quality rendering
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        
        # Draw the resized image
        $graphics.DrawImage($originalImage, 0, 0, $targetWidth, $targetHeight)
        $graphics.Dispose()
        
        # Convert to PNG in memory
        $memoryStream = New-Object System.IO.MemoryStream
        $resizedBitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
        
        # Get the byte array and calculate size
        $imageBytes = $memoryStream.ToArray()
        $resizedSizeKB = [math]::Round($imageBytes.Length / 1KB, 2)
        
        # Convert to Base64
        $base64String = [Convert]::ToBase64String($imageBytes)
        
        Write-Verbose "Resized image: ${targetWidth}x${targetHeight} ($resizedSizeKB KB)"
        Write-Verbose "Base64 string length: $($base64String.Length) characters"
        
        # Clean up
        $memoryStream.Dispose()
        $resizedBitmap.Dispose()
        $originalImage.Dispose()
        
        # Return result object
        return [PSCustomObject]@{
            Base64String       = $base64String
            OriginalResolution = $originalResolution
            OriginalSizeKB     = $originalSizeKB
            ResizedResolution  = "${targetWidth}x${targetHeight}"
            ResizedSizeKB      = $resizedSizeKB
        }
    }
    catch {
        Write-Error "Failed to process image: $_"
        throw
    }
}

# Example usage if run directly
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "`nImage to Base64 Converter" -ForegroundColor Cyan
    Write-Host "=========================" -ForegroundColor Cyan
    
    $imagePath = Read-Host "`nEnter the full path to your image file"
    
    if (Test-Path $imagePath) {
        Write-Host "`nProcessing image..." -ForegroundColor Yellow
        
        $result = Convert-ImageToBase64 -ImagePath $imagePath -Verbose
        
        Write-Host "`n=== Results ===" -ForegroundColor Green
        Write-Host "Original: $($result.OriginalResolution) ($($result.OriginalSizeKB) KB)" -ForegroundColor White
        Write-Host "Resized:  $($result.ResizedResolution) ($($result.ResizedSizeKB) KB)" -ForegroundColor White
        Write-Host "Base64 length: $($result.Base64String.Length) characters" -ForegroundColor White
        
        # Copy to clipboard
        $result.Base64String | Set-Clipboard
        Write-Host "`nBase64 string copied to clipboard!" -ForegroundColor Green
        
        # Optionally save to file
        $saveToFile = Read-Host "`nSave Base64 string to file? (Y/N)"
        if ($saveToFile -eq 'Y') {
            $outputPath = Read-Host "Enter output file path (e.g., C:\output.txt)"
            $result.Base64String | Out-File -FilePath $outputPath -Encoding UTF8
            Write-Host "Base64 string saved to: $outputPath" -ForegroundColor Green
        }
    }
    else {
        Write-Host "Error: Image file not found at $imagePath" -ForegroundColor Red
    }
}
