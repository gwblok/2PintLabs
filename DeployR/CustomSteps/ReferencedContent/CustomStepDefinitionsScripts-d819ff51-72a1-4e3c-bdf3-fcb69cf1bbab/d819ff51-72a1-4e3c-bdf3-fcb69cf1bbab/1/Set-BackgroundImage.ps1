<# Set Background

Replaces Default Windows Background with your own

DeployR
#>
if ($env:SystemDrive -eq "X:"){
    Write-Host "Running in WinPE, this step requires a full Windows environment to run properly."
    exit 0
}
Import-Module DeployR.Utility

# Get the provided variables
[String]$URL = ${TSEnv:BrandingBackgroundImageURL}
[String]$ImageFileName = ${TSEnv:BrandingBackgroundImageFileName}
[String]$ImageFileContentItem = ${TSEnv:CONTENT-BrandingBackgroundImageCI}
[String]$BrandingBackgroundImageSystemMode = ${TSEnv:BrandingBackgroundImageSystemMode}

#Report Variables:
if ($URL -ne ""){
    Write-Output "Background Image URL: $URL"
}
if ($ImageFileName -ne ""){
    Write-Output "Background Image File Name: $ImageFileName"
}
if ($ImageFileContentItem -ne ""){
    Write-Output "Background Image Content Item: $ImageFileContentItem"
}
if ($BrandingBackgroundImageSystemMode -eq "True"){
    
    $SystemMode = "Dark"
}
else {
    $SystemMode = "Light"
}
Write-Output "Background Image System Mode: $SystemMode"

Function Set-BackgroundImage {
    <#
    .SYNOPSIS
    Sets the Background Image to a custom image.
    .DESCRIPTION
    This function sets the Background image to a custom image, typically downloaded from a URL.
    .PARAMETER exitcode
    The exit code to return after execution.
    .EXAMPLE
    Set-BackgroundImage 
    #>
    [CmdletBinding()]
    param(
    [String]$ImageURL,
    [String]$ImageFileName, 
    [String]$ImageFileContentItem,
    [String]$SystemMode = "Dark" # Default to Dark Mode

    )
    
$ThemeFile = @"

; Copyright  Microsoft Corp.

[Theme]
DisplayName=DeployR OSD Theme
SetLogonBackground=0

; Computer - SHIDI_SERVER
[CLSID\{20D04FE0-3AEA-1069-A2D8-08002B30309D}\DefaultIcon]
DefaultValue=%SystemRoot%\System32\imageres.dll,-109

; UsersFiles - SHIDI_USERFILES
[CLSID\{59031A47-3F72-44A7-89C5-5595FE6B30EE}\DefaultIcon]
DefaultValue=%SystemRoot%\System32\imageres.dll,-123

; Network - SHIDI_MYNETWORK
[CLSID\{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}\DefaultIcon]
DefaultValue=%SystemRoot%\System32\imageres.dll,-25

; Recycle Bin - SHIDI_RECYCLERFULL SHIDI_RECYCLER
[CLSID\{645FF040-5081-101B-9F08-00AA002F954E}\DefaultIcon]
Full=%SystemRoot%\System32\imageres.dll,-54
Empty=%SystemRoot%\System32\imageres.dll,-55

[Control Panel\Cursors]
AppStarting=%SystemRoot%\cursors\aero_working.ani
Arrow=%SystemRoot%\cursors\aero_arrow.cur
Crosshair=
Hand=%SystemRoot%\cursors\aero_link.cur
Help=%SystemRoot%\cursors\aero_helpsel.cur
IBeam=
No=%SystemRoot%\cursors\aero_unavail.cur
NWPen=%SystemRoot%\cursors\aero_pen.cur
SizeAll=%SystemRoot%\cursors\aero_move.cur
SizeNESW=%SystemRoot%\cursors\aero_nesw.cur
SizeNS=%SystemRoot%\cursors\aero_ns.cur
SizeNWSE=%SystemRoot%\cursors\aero_nwse.cur
SizeWE=%SystemRoot%\cursors\aero_ew.cur
UpArrow=%SystemRoot%\cursors\aero_up.cur
Wait=%SystemRoot%\cursors\aero_busy.ani
DefaultValue=Windows Default
DefaultValue.MUI=@main.cpl,-1020

[Control Panel\Desktop]
Wallpaper=%SystemRoot%\web\wallpaper\DeployROSD\DeployROSD.jpg
TileWallpaper=0
WallpaperStyle=10
Pattern=

[VisualStyles]
Path=%ResourceDir%\Themes\Aero\Aero.msstyles
ColorStyle=NormalColor
Size=NormalSize
AutoColorization=0
ColorizationColor=0XC40078D7
SystemMode=$SystemMode
AppMode=$SystemMode

[boot]
SCRNSAVE.EXE=

[MasterThemeSelector]
MTSM=RJSPBS

[Sounds]
; IDS_SCHEME_DEFAULT
SchemeName=@%SystemRoot%\System32\mmres.dll,-800

"@

    $StoragePath = "$env:SystemDrive\_2P\content"
    
    if ($ImageFileName){
        $ImageFilePath = "$ImageFileContentItem\$ImageFileName"
        if (Test-Path $ImageFilePath){
            Copy-item -Path $ImageFilePath -Destination "$StoragePath\Background.jpg" -Force -Verbose
        }
        else{
            Write-Output "Did not find $ImageFileName in current directory - Please confirm ImageFileName is correct."
        }
    }
    else{
        if ($ImageURL){
            $BackgroundURL = $ImageURL
        }
        else{
            $BackgroundURL = "https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/2PintImages/2pint-desktop-stripes-dark-1920x1080.png"
        }
        Write-Output "Downloading Background Image from $BackgroundURL"
        #Download the image from the URL
        Invoke-WebRequest -UseBasicParsing -Uri $BackgroundURL -OutFile "$StoragePath\Background.jpg"
    }
    

    # STEP 2: Configure background
    if (Test-Path -Path "$StoragePath\Background.jpg"){
    Write-Host "Setting up OSD theme"
    Write-Host "Confirmed Background.jpg exists, proceeding to set as background via Theme."
    New-Item -Path "C:\Windows\Resources\OEM Themes" -ItemType Directory -Force | Out-Null
    Write-Host "Creating DeployROSD.theme file in C:\Windows\Resources\OEM Themes"
    $ThemeFile | Out-File -FilePath "C:\Windows\Resources\OEM Themes\DeployROSD.theme" -Force -Encoding UTF8
    New-Item -Path  "C:\Windows\web\wallpaper\DeployROSD" -ItemType Directory -Force | Out-Null
    Write-Host "Copying Background.jpg to C:\Windows\web\wallpaper\DeployROSD\DeployROSD.jpg"
    Copy-Item "$StoragePath\Background.jpg" "C:\Windows\web\wallpaper\DeployROSD\DeployROSD.jpg" -Force
    if (Test-Path -Path "C:\Windows\Web\Wallpaper\DeployROSD\DeployROSD.jpg"){
        Write-Host "Background Image successfully copied to Wallpaper folder."
    }
    else{
        Write-Output "Failed to copy Background Image to Wallpaper folder."
    }
    Write-Host "Setting DeployROSD theme as the new user default"
    
    [GC]::Collect()
    start-sleep -Milliseconds 500
    Write-Host " Mounting Default User Registry Hive (REG LOAD HKLM\Default C:\Users\Default\NTUSER.DAT)"
    REG LOAD HKLM\Default C:\Users\Default\NTUSER.DAT
    $reg = New-ItemProperty -Path "HKLM:\Default\Software\Microsoft\Windows\CurrentVersion\Themes" -Name "InstallTheme" -Value "%SystemRoot%\resources\OEM Themes\DeployROSD.theme" -PropertyType String -Force | Out-Null
    $reg = New-ItemProperty -Path "HKLM:\Default\Software\Microsoft\Windows\CurrentVersion\Themes" -Name "CurrentTheme" -Value "%SystemRoot%\resources\OEM Themes\DeployROSD.theme" -PropertyType String -Force | Out-Null

    #& reg.exe add "HKLM\TempUser\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes" /v InstallTheme /t REG_EXPAND_SZ /d "%SystemRoot%\resources\OEM Themes\DeployROSD.theme" /f /reg:64 2>&1 | Out-Null
    #& reg.exe add "HKLM\TempUser\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes" /v CurrentTheme /t REG_EXPAND_SZ /d "%SystemRoot%\resources\OEM Themes\DeployROSD.theme" /f /reg:64 2>&1 | Out-Null
    
    [GC]::Collect()
    start-sleep -Milliseconds 500
    Write-Host " Unmounting Default User Registry Hive (REG UNLOAD HKLM\Default)"
    REG UNLOAD HKLM\Default

    }
    else{
        Write-Output "Did not find Background.jpg in temp folder - Please confirm URL or ImageFileName is correct."
    }
}



if ($URL -ne ""){
    Write-Output "Background Image URL is set to $URL"
    Set-BackgroundImage -ImageURL $URL -SystemMode $SystemMode
}
if ($ImageFileName -ne ""){
    Write-Output "Background Image File Name is set to $ImageFileName"
    
}
if ($ImageFileContentItem -ne ""){
    Write-Output "Background Image Content Item is set to $ImageFileContentItem"
    Set-BackgroundImage -ImageFileName $ImageFileName -ImageFileContentItem $ImageFileContentItem -SystemMode $SystemMode
}

