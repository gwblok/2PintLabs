<# Set Lock Screen

Replaces Default Windows Lock Screen with your own

DeployR
#>
if ($env:SystemDrive -eq "X:"){
    Write-Host "Running in WinPE, this step requires a full Windows environment to run properly."
    exit 0
}
Import-Module DeployR.Utility

# Get the provided variables
[String]$URL = ${TSEnv:BrandingLockScreenImageURL}
[String]$ImageFileName = ${TSEnv:BrandingLockScreenImageFileName}
[String]$ImageFileContentItem = ${TSEnv:_CONTENT-BrandingLockScreenImageCI}
[String]$BrandingLockScreenImageEnforce = ${TSEnv:BrandingLockScreenImageEnforce}

#Report Variables:
Write-Output "Lock Screen Image URL: $URL"
Write-Output "Lock Screen Image File Name: $ImageFileName"
Write-Output "Lock Screen Image Content Item: $ImageFileContentItem"
Write-Output "Lock Screen Image Enforce: $BrandingLockScreenImageEnforce"


Function Set-LockScreenImage {
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
    [String]$ImageFileName, 
    [String]$ImageFileContentItem,
    [string]$BrandingLockScreenImageEnforce = "false"
    )
    
    
    $StoragePath = "$env:SystemDrive\_2P\content"
    
    if ($ImageFileName){
        $ImageFilePath = "$ImageFileContentItem\$ImageFileName"
        if (Test-Path $ImageFilePath){
            Copy-item -Path $ImageFilePath -Destination "$StoragePath\lockscreen.jpg" -Force -Verbose
        }
        else{
            Write-Output "Did not find $ImageFileName in current directory - Please confirm ImageFileName is correct."
        }
    }
    else{
        if ($ImageURL){
            $LockScreenURL = $ImageURL
        }
        else{
            $LockScreenURL = "https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/2PintImages/2pint-desktop-stripes-dark-1920x1080.png"
        }
        Write-Output "Downloading Lock Screen Image from $LockScreenURL"
        #Download the image from the URL
        Invoke-WebRequest -UseBasicParsing -Uri $LockScreenURL -OutFile "$StoragePath\lockscreen.jpg"
    }
    
    
    #Copy the 2 files into place
    if (Test-Path -Path "$StoragePath\lockscreen.jpg"){
        Write-Output "Running Command: Copy-Item $StoragePath\lockscreen.jpg C:\windows\web\Screen\img100.jpg -Force -Verbose"
        Copy-Item "$StoragePath\lockscreen.jpg" C:\windows\web\Screen\img100.jpg -Force -Verbose
        Write-Output "Running Command: Copy-Item $StoragePath\lockscreen.jpg C:\windows\web\Screen\img105.jpg -Force -Verbose"
        Copy-Item "$StoragePath\lockscreen.jpg" C:\windows\web\Screen\img105.jpg -Force -Verbose
    }
    else{
        Write-Output "Did not find lockscreen.jpg in temp folder - Please confirm URL or ImageFileName is correct."
    }
    if ($BrandingLockScreenImageEnforce -eq "true") {
    Write-Output "Enforcing Lock Screen Image"
    $LockScreenImagePath = "C:\windows\web\Screen\EnforcedLockScreenImage.jpg"
    Copy-Item "$StoragePath\lockscreen.jpg" $LockScreenImagePath -Force -Verbose
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
    if (!(Test-Path -Path $RegPath)) {
            New-Item -Path $RegPath -Force | Out-Null
        }
    New-ItemProperty -Path $RegPath -Name LockScreenImagePath -Value $LockScreenImagePath -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegPath -Name LockScreenImageUrl -Value $LockScreenImagePath -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegPath -Name LockScreenImageStatus -Value 1 -PropertyType DWORD -Force | Out-Null
    } 
    else {
        Write-Output "Not enforcing Lock Screen Image"
    }
}



if ($URL -ne ""){
    Write-Output "Lock Screen Image URL is set to $URL"
    Set-LockScreenImage -ImageURL $URL -BrandingLockScreenImageEnforce $BrandingLockScreenImageEnforce
}
if ($ImageFileName -ne ""){
    Write-Output "Lock Screen Image File Name is set to $ImageFileName"
    
}
if ($ImageFileContentItem -ne ""){
    Write-Output "Lock Screen Image Content Item is set to $ImageFileContentItem"
    Set-LockScreenImage -ImageFileName $ImageFileName -ImageFileContentItem $ImageFileContentItem -BrandingLockScreenImageEnforce $BrandingLockScreenImageEnforce
}

