
Import-Module DeployR.Utility

# Get the provided variables
[String]$IncludeGraphics = ${TSEnv:IncludeGraphics}
[String]$IncludeAudio = ${TSEnv:IncludeAudio}
[String]$TargetSystemDrive = ${TSEnv:OSDTARGETSYSTEMDRIVE}
[String]$LogPath = ${TSEnv:_DEPLOYRLOGS}
[String]$UseStandardLenovoDriverPack = ${TSEnv:UseStandardLenovoDriverPack}
[switch]$ApplyDrivers = $true
$MakeAlias = ${TSEnv:MakeAlias}
$ModelAlias = ${TSEnv:ModelAlias}

If ($MakeAlias -ne "Lenovo") {
    Write-Host "This script is intended for Lenovo devices only. Exiting..."
    exit 0
}

# Install Lenovo.Client.Scripting module
write-host "Installing Lenovo.Client.Scripting module if not already installed..."
if (-not (Get-Module -Name Lenovo.Client.Scripting -ListAvailable)) {
    Write-Host "Lenovo.Client.Scripting module not found. Installing..."
    Install-Module -Name Lenovo.Client.Scripting -Force -SkipPublisherCheck
} else {
    Write-Host "Lenovo.Client.Scripting module already installed."
}

write-host "==================================================================="
write-host "Creating Driver Pack for WinPE for Lenovo devices Type: $(Get-LnvMachineType)"
write-host "Reporting Variables:"
write-host "IncludeGraphics: $IncludeGraphics"
write-host "IncludeAudio: $IncludeAudio"






#Find 7za.exe
if (Test-path -Path "X:\_2P\content\00000000-0000-0000-0000-000000000002\Tools\x64\7za.exe"){
    $SevenZipPath = "X:\_2P\content\00000000-0000-0000-0000-000000000002\Tools\x64\7za.exe"
    $InnoExtractPath = "X:\_2P\content\00000000-0000-0000-0000-000000000002\Tools\x64\InnoExtract.exe"
}
else {
    Write-Host "7za.exe not found in expected path. Please ensure it is available in the Tools directory."
    Exit 1
}


#Import DeployR.Utility module
if (-not (Get-Module -Name DeployR.Utility)) {
    Import-Module X:\_2P\Client\PSModules\DeployR.Utility\DeployR.Utility.psd1 -Force -ErrorAction Stop
}

#Build Download Content Location
$DownloadContentPath = "$TargetSystemDrive\Drivers\Downloads"
if (!(Test-Path -Path $DownloadContentPath)) {
    New-Item -ItemType Directory -Path $DownloadContentPath -Force | Out-Null
}
$ExtractedDriverLocation = "$TargetSystemDrive\Drivers\Extracted"
if (!(Test-Path -Path $ExtractedDriverLocation)) {
    New-Item -ItemType Directory -Path $ExtractedDriverLocation -Force | Out-Null
}

if ($UseStandardLenovoDriverPack -eq "true") {
    Write-Host "Using custom Lenovo Driver Pack for WinPE"
    $DriverPack = Find-LnvDriverPack -MachineType (Get-LnvMachineType) -Latest
    if ($DriverPack -ne $null) {
        $URL = $DriverPack.'#text'
        $Name = ($DriverPack.'#text').split("/") | Select-Object -last 1
        Write-Host "Found Lenovo Driver Pack: $($Name)"
        Write-Host "Downloading and extracting Lenovo Driver Pack to $ExtractedDriverLocation"
        Request-DeployRCustomContent -ContentName $Name -ContentFriendlyName $Name -URL "$($URL)" -DestinationPath $DownloadContentPath -ErrorAction SilentlyContinue
        $ExpandFile = (get-childitem -path $DownloadContentPath -Filter *.exe -Recurse).FullName
        Start-Process -FilePath $InnoExtractPath -ArgumentList "-e -d $ExtractedDriverLocation $ExpandFile" -Wait -NoNewWindow -PassThru
    } else {
        Write-Host "No Lenovo Driver Pack found for the specified machine type."
    }
}
else {


    $LenovoUpdates = Find-LnvUpdate -MachineType (Get-LnvMachineType) -ListAll -WindowsVersion 11
    $Drivers = $LenovoUpdates | Where-Object {$_.Name -notmatch "BIOS" -and $_.Name -notmatch "Firmware" -and $_.Name -notmatch "FW"  -and $_.Name -notmatch "Lenovo Base Utility"  -and $_.Name -notmatch "WAN"}
    if ($IncludeGraphics -eq $false) {
        $Drivers = $Drivers | Where-Object {$_.Name -notmatch "Graphics"}
    }
    if ($IncludeAudio -eq $false) {
        $Drivers = $Drivers | Where-Object {$_.Name -notmatch "Audio"}
    }
    Write-Host "Found $($Drivers.Count) drivers to process."
    Write-Output $Drivers.Name

    Write-Host "Starting Downloading Drivers to $DownloadContentPath"
    Foreach ($Driver in $Drivers){
        Write-Host "Driver: $($Driver.Name) - $($Driver.Category)" -ForegroundColor Magenta
        if ($null -ne $Driver.PackageExe){
            Write-Host "Downloading Driver from: $($Driver.PackageExe)" -ForegroundColor Cyan
            $ExpandFile = "$DownloadContentPath\$($Driver.id).exe"
            write-host "Downloading to: $ExpandFile" -ForegroundColor Green
            $DestinationPath = "$ExtractedDriverLocation\$($Driver.id)"
            #Start-BitsTransfer -Source "https://$($Driver.PackageExe)" -Destination "$DownloadContentPath\$($Driver.id).exe" -DisplayName $Driver.Name -Description $Driver.Description -ErrorAction SilentlyContinue
            try {
                Request-DeployRCustomContent -ContentName $($Driver.Id) -ContentFriendlyName $($Driver.Name) -URL "$($Driver.PackageExe)" -DestinationPath $DownloadContentPath -ErrorAction SilentlyContinue

            } catch {
                Write-Host "Failed to download driver: $($Driver.Name)" -ForegroundColor red
                Write-Host "Going to try again with Invoke-WebRequest" -ForegroundColor Yellow
                Invoke-WebRequest -Uri $Driver.PackageExe -OutFile $ExpandFile -UseBasicParsing
            }
     }
        else {
            Write-Host "No URL found for this driver, skipping download."
        }
    }
    Write-Host "Starting Extracting Drivers to $ExtractedDriverLocation"
    $DriversDownloads = get-childitem -path $DownloadContentPath -Filter *.exe -Recurse
    if ($DriversDownloads) {
        foreach ($DriverDownload in $DriversDownloads) {
            Write-Host "Found Driver Download: $($DriverDownload.Name)"
            $FolderName = $DriverDownload.Name -replace '.exe',''
            $ExpandFile = $DriverDownload.FullName
            $ExtractedDriverPath = "$ExtractedDriverLocation\$FolderName"
            if (!(Test-Path -Path $ExtractedDriverPath)) {
                New-Item -ItemType Directory -Path $ExtractedDriverPath -Force | Out-Null
            }
            Write-Host "Expanding Driver Pack to $ExtractedDriverPath"
            Start-Process -FilePath $InnoExtractPath -ArgumentList "-e -d $ExtractedDriverPath $ExpandFile" -Wait -NoNewWindow -PassThru
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

    & Dism /Image:"$($TargetSystemDrive)\" /Add-Driver /Driver:$ExtractedDriverLocation /Recurse
}
