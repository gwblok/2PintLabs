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
[String]$WMIEFromCloud = ${TSEnv:WMIEFromCloud}
[String]$WMIEContentItem = ${TSEnv:_CONTENT-WMIEContentItem}

#region functions
Function New-AppIcon {
        param(
        [string]$SourceExePath = "$env:windir\system32\control.exe",
        [string]$ArgumentsToSourceExe,
        [string]$ShortCutName = "AppName"

        )
        #Build ShortCut Information

        $ShortCutFolderPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
        $DestinationPath = "$ShortCutFolderPath\$($ShortCutName).lnk"
        Write-Output "Shortcut Creation Path: $DestinationPath"

        if ($ArgumentsToSourceExe){
            Write-Output "Shortcut = $SourceExePath -$($ArgumentsToSourceExe)"
        }
        Else {
            Write-Output "Shortcut = $SourceExePath"
        }
        

        #Create Shortcut
        $WshShell = New-Object -comObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($DestinationPath)
        $Shortcut.IconLocation = "$SourceExePath, 0"
        $Shortcut.TargetPath = $SourceExePath
        if ($ArgumentsToSourceExe){$Shortcut.Arguments = $ArgumentsToSourceExe}
        $Shortcut.Save()

        Write-Output "Shortcut Created"
    }

$ExpandPath = "$env:windir\system32"
$AppPath = "$ExpandPath\WMIExplorer.exe"

if ($WMIEContentItem -ne ""){
    Write-Output "Installing WMI Explorer from Content Item"
    $StoragePath = "$env:SystemDrive\_2P\content"
    if (-not (Test-Path -Path $StoragePath)) {New-Item -Path $StoragePath -ItemType Directory | Out-Null}
    $WMIEContentItemPath = "$WMIEContentItem\WMIExplorer.exe"
    if (Test-Path $WMIEContentItemPath){
        Write-Output "Found WMI Explorer in Content Item"
        copy-item -Path $WMIEContentItemPath -Destination $ExpandPath -Force -Verbose
        New-AppIcon -SourceExePath $AppPath -ShortCutName "WMIExplorer"
        exit 0    
    }
    else{
        Write-Output "Did not find WMI Explorer in Content Item - Please confirm CONTENT-WMIEContentItem is correct."
    }
}

if ($WMIEFromCloud -eq "True"){
    Write-Output "Installing WMI Explorer from Cloud"
    $AppName = "WMIExplorer"
    $FileName = "WMIExplorer.zip"
    $ExpandPath = "$env:windir\system32"
    $URL = "https://github.com/vinaypamnani/wmie2/releases/download/v2.0.0.2/WmiExplorer_2.0.0.2.zip"
    $AppPath = "$ExpandPath\WMIExplorer.exe"
    $ShortCutFolderPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"

    #Download & Extract to System32
    Write-Output "Downloading $URL"
    Invoke-WebRequest -UseBasicParsing -Uri $URL -OutFile $env:TEMP\$FileName
    if (Test-Path -Path $env:TEMP\$FileName){Write-Output "Successfully Downloaded"}
    else{Write-Output "Failed Downloaded"; exit 255}
    Write-Output "Starting Extraction of $AppName to $ExpandPath"
    Expand-Archive -Path $env:TEMP\$FileName -DestinationPath $ExpandPath -Force
    if (Test-Path -Path $AppPath){
        Write-Output "Successfully Extracted Zip File"
        New-AppIcon -SourceExePath $AppPath -ShortCutName "WMIExplorer"
    }
    else{Write-Output "Failed Extract"; exit 255}
}


