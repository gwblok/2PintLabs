<# 
Import-Module DeployR.Utility

# Get the provided variables
[String]$TargetSystemDrive = ${TSEnv:OSDTARGETSYSTEMDRIVE}
[String]$LogPath = ${TSEnv:_DEPLOYRLOGPATH}
#>

Install-Module -Name Lenovo.Client.Scripting -Force

Function Create-NewLenovoDriverPackWinPE {
    [CmdletBinding()]
    param(
    [Parameter(Mandatory = $false)]
    [string]$TargetSystemDrive = "S:",
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "S:\_2P\Logs",
    [Parameter(Mandatory = $false)]
    [switch]$ApplyDrivers = $false,
    [Parameter(Mandatory = $false)]
    [Switch]$IncludeGraphics = $false,
    [Parameter(Mandatory = $false)]
    [Switch]$IncludeAudio = $false
    )
    
    Write-Host "==================================================================="
    Write-Host "     Starting Process to Build Driver Pack while in WinPE"
    Write-Host "==================================================================="
    
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
    $DownloadContentPath = "$TargetSystemDrive\_2P\content\Drivers"
    if (!(Test-Path -Path $DownloadContentPath)) {
        New-Item -ItemType Directory -Path $DownloadContentPath -Force | Out-Null
    }
    $ExtractedDriverLocation = "$DownloadContentPath\Extracted"
    if (!(Test-Path -Path $ExtractedDriverLocation)) {
        New-Item -ItemType Directory -Path $ExtractedDriverLocation -Force | Out-Null
    }
    
    $LenovoUpdates = Find-LnvUpdate -MachineType (Get-LnvMachineType) -ListAll
    $Drivers = $LenovoUpdates | Where-Object {$_.Name -notmatch "BIOS"}
    if ($IncludeGraphics -eq $false) {
        $Drivers = $Drivers | Where-Object {$_.Name -notmatch "Graphics"}
    }
    if ($IncludeAudio -eq $false) {
        $Drivers = $Drivers | Where-Object {$_.Name -notmatch "Audio"}
    }
    Foreach ($Driver in $Drivers){
        Write-Host "Driver: $($Driver.Name) - $($Driver.Category)" -ForegroundColor Magenta
        if ($null -ne $Driver.PackageExe){
            Write-Host "Downloading Driver from: $($Driver.PackageExe)" -ForegroundColor Cyan
            $ExpandFile = "$DownloadContentPath\$($Driver.id).exe"
            write-host "Downloading to: $ExpandFile" -ForegroundColor Green
            $DestinationPath = "$ExtractedDriverLocation\$($Driver.id)"
            #Start-BitsTransfer -Source "https://$($Driver.PackageExe)" -Destination "$DownloadContentPath\$($Driver.id).exe" -DisplayName $Driver.Name -Description $Driver.Description -ErrorAction SilentlyContinue
            try {
                Request-DeployRCustomContent -ContentName $($Driver.Id) -ContentFriendlyName $($Driver.Name) -URL "https://$($Driver.PackageExe)" -DestinationPath $ExpandFile -ErrorAction SilentlyContinue
            } catch {
                Write-Host "Failed to download driver: $($Driver.Name)" -ForegroundColor red
                Write-Host "Going to try again with Invoke-WebRequest" -ForegroundColor Yellow
                Invoke-WebRequest -Uri $Driver.PackageExe -OutFile $ExpandFile -UseBasicParsing
            }
            if (Test-Path -Path $ExpandFile) {
                Write-Host "Driver downloaded successfully: $($Driver.Name)"
                write-Host "Expanding Driver Pack to $ExtractedDriverLocation"
                #Start-Process -FilePath $SevenZipPath -ArgumentList "x $ExpandFile -o$DestinationPath -y" -Wait -NoNewWindow -PassThru
                Start-Process -FilePath $InnoExtractPath -ArgumentList "-e -d $DestinationPath $ExpandFile" -Wait -NoNewWindow -PassThru
            }
            else {
                Write-Host "Failed to download driver: $($Driver.Name)" -ForegroundColor Red
            }
        }
        else {
            Write-Host "No URL found for this driver, skipping download."
        }
    }
    #Apply Drivers in ExtractedDriverLocation to Offline OS
    if ($ApplyDrivers -eq $false){
        Write-Host "Skipping Driver Application to Offline OS"
        return
    }
    else {
        Write-Host -ForegroundColor Cyan "Applying Drivers to Offline OS at $TargetSystemDrive from $ExtractedDriverLocation"
        Add-WindowsDriver -Path "$($TargetSystemDrive)\" -Driver "$ExtractedDriverLocation" -Recurse -ErrorAction SilentlyContinue -LogPath $LogPath\AddDrivers.log
    }
}

