if ($env:SystemDrive -eq "X:"){
    Write-Host "Running in WinPE, this step requires a full Windows environment to run properly."
    exit 0
}
<# Set Default Generic User Image

Replaces Default Windows Lock Screen with your own

DeployR
#>

Import-Module DeployR.Utility

# Get the provided variables
[String]$URL = ${TSEnv:BrandingImageURL}
[String]$FinishAction = ${TSEnv:FinishAction}
[String]$ImageFileName = ${TSEnv:BrandingImageFileName}
[String]$ImageFileContentItem = ${TSEnv:_CONTENT-BrandingImageCI}

Function Resize-Image {
    [CmdletBinding()]
    param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath,
    [int]$Quality = 80,
    [string]$ResizeMethod = 'width',
    [int]$MaxWidth = 500,
    [int]$MaxHeight = 500,
    [double]$ResizePercent = 0.5
    )
    
    Add-Type -AssemblyName System.Drawing
    
    
    $imageQuality = $Quality
    $imageQuality = [math]::Max(1, [math]::Min([int]$imageQuality, 100))
    
    $OutputFolderPath = (get-item -Path $ImagePath).DirectoryName
    $imagename = [System.IO.Path]::GetFileNameWithoutExtension($ImagePath)
    $image = [System.Drawing.Image]::FromFile($ImagePath)
    
    # Calculate the new dimensions
    $ratio = $image.Width / $image.Height
    $newWidth = [math]::Min($maxWidth, $image.Width)
    $newHeight = $newWidth / $ratio

    #Calculate height and width to ensure neither are over 500, but maintain aspect ratio
    if ($newHeight -gt $MaxHeight) {
        $newHeight = $MaxHeight
        $newWidth = $newHeight * $ratio
    }
    #Round the dimensions to the nearest integer
    [int]$newWidth = [math]::Round($newWidth)
    [int]$newHeight = [math]::Round($newHeight)

    # Create the resized image
    $newImage = New-Object System.Drawing.Bitmap $newWidth, $newHeight
    $graphic = [System.Drawing.Graphics]::FromImage($newImage)
    $graphic.DrawImage($image, 0, 0, $newWidth, $newHeight)
    
    # Encoder parameter for image quality
    $encoderInfo = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/png' }
    $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, $imageQuality)
    
    # Save the new image with the specified quality and filename
    $newFileName = "{0}-{1}.png" -f $imagename, $newWidth
    $newImagePath = [System.IO.Path]::Combine($OutputFolderPath, $newFileName)
    $newImage.Save($newImagePath, $encoderInfo, $encoderParams)
    
    # Dispose of the objects to free up resources
    $graphic.Dispose()
    $newImage.Dispose()
    $image.Dispose()
    
    return $newImagePath
}
Function Set-GenericUserImage {
    <#
    .SYNOPSIS
    Sets the Lock Screen Image to a custom image.
    .DESCRIPTION
    This function sets the lock screen image to a custom image, typically downloaded from a URL.
    .PARAMETER exitcode
    The exit code to return after execution.
    .EXAMPLE
    Set-LockScreenImage 
    #>
    [CmdletBinding()]
    param(
    [String]$ImageURL,
    [String]$FinishAction,
    [String]$ImageFileName, 
    [String]$ImageFileContentItem 
    )
    
    
    $StoragePath = "$env:SystemDrive\_2P\content"
    if (!(Test-Path -Path $StoragePath)) {
        New-Item -ItemType Directory -Path $StoragePath -Force | Out-Null
    }
    if ($ImageURL){
        Write-Output "Downloading Image from $ImageURL"
        #Download the image from the URL
        Invoke-WebRequest -UseBasicParsing -Uri $ImageURL -OutFile "$StoragePath\user-original.png"
        if (Test-Path -Path "$StoragePath\user-original.png") {
            Write-Output "Image downloaded successfully."
        } else {
            Write-Output "Failed to download image from $ImageURL"
            exit 1
        }
    }
    if ($ImageFileName){
        $ImageFilePath = "$ImageFileContentItem\$ImageFileName"
        if (Test-Path $ImageFilePath){
            Write-Output "Copying Image from Content Item to $StoragePath\user-original.png"
            Copy-item -Path $ImageFilePath -Destination "$StoragePath\user-original.png" -Force -Verbose
        }
        else{
            Write-Output "Did not find $ImageFileName in current directory - Please confirm ImageFileName is correct."
            exit 1
        }
    }
    if (Test-Path -Path "$StoragePath\user-original.png") {
        Write-Output "Image found at $StoragePath\user-original.png, Continuing..."
    } else {
        Write-Output "Image not found at $StoragePath\user-original.png"
        exit 1
    }
    $Image = Get-Item -Path "$StoragePath\user-original.png"
    Copy-Item -path $Image.FullName -Destination "$env:temp\user-original.png" -Force
    #Get Image Pixel Size
    $ImageSize = [System.Drawing.Image]::FromFile($Image.FullName)
    Write-Output "Image Size: $($ImageSize.Width) x $($ImageSize.Height)"
    if ($ImageSize.Width -gt 500 -or $ImageSize.Height -gt 500) {
        Write-Output "Image is larger than 500x500 pixels, resizing..."
        $MainImage = Resize-Image -ImagePath $Image.FullName -MaxWidth 500 -MaxHeight 500
        Copy-Item -Path $MainImage -Destination "$env:ProgramData\Microsoft\User Account Pictures\user.png" -Force
        Copy-Item -Path $MainImage -Destination "$env:ProgramData\Microsoft\User Account Pictures\guest.png" -Force
        Copy-Item -Path $MainImage -Destination "$env:ProgramData\Microsoft\User Account Pictures\user-32.png" -Force
        Copy-Item -Path $MainImage -Destination "$env:ProgramData\Microsoft\User Account Pictures\user-40.png" -Force
        Copy-Item -Path $MainImage -Destination "$env:ProgramData\Microsoft\User Account Pictures\user-48.png" -Force
        Copy-Item -Path $MainImage -Destination "$env:ProgramData\Microsoft\User Account Pictures\user-192.png" -Force
        Copy-Item -Path $MainImage -Destination "$env:ProgramData\Microsoft\User Account Pictures\user-200.png" -Force
        Move-Item -Path $MainImage -Destination "$env:temp\user-modified.png" -Force
    } else {
        Write-Output "Image is within the acceptable size range."
        Copy-Item -Path $Image.FullName -Destination "$env:ProgramData\Microsoft\User Account Pictures\user.png" -Force
        Copy-Item -Path $Image.FullName -Destination "$env:ProgramData\Microsoft\User Account Pictures\guest.png" -Force
        Copy-Item -Path $Image.FullName -Destination "$env:ProgramData\Microsoft\User Account Pictures\user-32.png" -Force
        Copy-Item -Path $Image.FullName -Destination "$env:ProgramData\Microsoft\User Account Pictures\user-40.png" -Force
        Copy-Item -Path $Image.FullName -Destination "$env:ProgramData\Microsoft\User Account Pictures\user-48.png" -Force
        Copy-Item -Path $Image.FullName -Destination "$env:ProgramData\Microsoft\User Account Pictures\user-192.png" -Force
        Copy-Item -Path $Image.FullName -Destination "$env:ProgramData\Microsoft\User Account Pictures\user-200.png" -Force
    }
    if ($FinishAction -eq "Reseal"){
        Write-Host "Skipping setting UseDefaultTile as FinishAction is Reseal"
    }
    else {
        Write-Output "Setting UseDefaultTile to 1"
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "UseDefaultTile" -Value 1 -Type Dword -Force
    }
}



if ($URL -ne "") {
    write-host "Branding Image URL is set to $URL"
    $URLExtension = [System.IO.Path]::GetExtension($URL)
    if ($URLExtension -ne ".png") {
        Write-Output "The URL provided does not point to a PNG image. Please provide a valid PNG image URL."
        exit 1
    }
    Set-GenericUserImage -ImageURL $URL -FinishAction $FinishAction
}

if ($ImageFileName -ne "") {
    Write-Output "Generic User Image File Name is set to $ImageFileName"
    Write-Output "Content Item for Image is set to $ImageFileContentItem"
    Set-GenericUserImage -ImageFileName $ImageFileName -ImageFileContentItem $ImageFileContentItem -FinishAction $FinishAction
}