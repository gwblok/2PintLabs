if ($env:SystemDrive -eq "X:"){
    Write-Host "Running in WinPE, this step requires a full Windows environment to run properly."
    exit 0
}
#Pull Vars from TS:
Import-Module DeployR.Utility

[String]$MakeAlias = ${TSEnv:MakeAlias}
if ($MakeAlias -ne "Lenovo") {
    Write-Host "MakeAlias must be Lenovo. Exiting script."
    Exit 0
}

# Get the provided variables
$WarrantyInfoHide = ${TSEnv:LCVWarrantyInfoHide}
$MyDevicePageHide = ${TSEnv:LCVMyDevicePageHide}
$WiFiSecurityPageHide = ${TSEnv:LCVWiFiSecurityPageHide}
$HardwareScanPageHide = ${TSEnv:LCVHardwareScanPageHide}
$GiveFeedbackPageHide = ${TSEnv:LCVGiveFeedbackPageHide}
$TurnOffMicrophoneSettings = ${TSEnv:LCVTurnOffMicrophoneSettings}

Write-Host "==================================================================="
write-host "Installing LCV on  $MakeAlias $ModelAlias Devices"
write-host "Reporting Variables:"
write-host "WarrantyInfoHide: $WarrantyInfoHide"
write-host "MyDevicePageHide: $MyDevicePageHide" 
write-host "WiFiSecurityPageHide: $WiFiSecurityPageHide"
write-host "HardwareScanPageHide: $HardwareScanPageHide"
write-host "GiveFeedbackPageHide: $GiveFeedbackPageHide"
write-host "TurnOffMicrophoneSettings: $TurnOffMicrophoneSettings"


#region Functions
function Install-LenovoVantage {
    [CmdletBinding()]
    param (
    [switch]$IncludeSUHelper = $true
    )
    # Define the URL and temporary file path - https://support.lenovo.com/us/en/solutions/hf003321-lenovo-vantage-for-enterprise
    #$url = "https://download.lenovo.com/pccbbs/thinkvantage_en/metroapps/Vantage/LenovoCommercialVantage_10.2401.29.0.zip"
    
    #Jan 25 release - seems to be the best working version.
    $url = "https://download.lenovo.com/pccbbs/thinkvantage_en/metroapps/Vantage/LenovoCommercialVantage_10.2501.15.0_v3.zip"
    
    #July 2025 Release - having issues, fails to install during OSD
    #$url = 'https://download.lenovo.com/pccbbs/thinkvantage_en/metroapps/Vantage/LenovoCommercialVantage_20.2506.39.0_v17.zip'
    
    #$tempFilePath = "C:\Windows\Temp\lenovo_vantage.zip"
    $tempExtractPath = "C:\Windows\Temp\LCV\Extract"
    $tempDownloadPath = "C:\Windows\Temp\LCV\Download"
    $NAME = "Lenovo Vantage"
    try {
        #Request-DeployRCustomContent -ContentName $($Driver.Id) -ContentFriendlyName $($Driver.Name) -URL "$($Driver.PackageExe)" -DestinationPath $DownloadContentPath -ErrorAction SilentlyContinue
        $destFile = Request-DeployRCustomContent -ContentName "LCV" -ContentFriendlyName $NAME -URL $URL -DestinationPath $tempDownloadPath -ErrorAction SilentlyContinue
        $GetItemOutFile = Get-Item $destFile
        $ExpandFile = $GetItemOutFile.FullName
        if (Test-Path -path $ExpandFile) {
            Write-Host "Downloaded Content to: $ExpandFile" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to download Content: $Name" -ForegroundColor red
        Write-Host "Going to try again with Invoke-WebRequest" -ForegroundColor Yellow
        $ExpandFile = Join-Path -Path $DownloadContentPath -ChildPath "$ID.exe"
        Invoke-WebRequest -Uri $URL -OutFile $ExpandFile -UseBasicParsing
    }
    <# switched to process above.  Will leave this here for reference for now

        # Create a new BITS transfer job
        $bitsJob = Start-BitsTransfer -Source $url -Destination $tempFilePath -DisplayName "Downloading to $tempFilePath"
        
        # Wait for the BITS transfer job to complete
        while ($bitsJob.JobState -eq "Transferring") {
            Start-Sleep -Seconds 2
        }

    #>
    
    # Check if the transfer was successful
    if (Test-Path -Path $ExpandFile) {
        # Start the installation process
        Write-Host -ForegroundColor Green "Installation file downloaded successfully. Starting installation..."
        Write-Host -ForegroundColor Cyan " Extracting $ExpandFile to $tempExtractPath"
        if (test-path -path $tempExtractPath) {Remove-Item -Path $tempExtractPath -Recurse -Force}
        Expand-Archive -Path $ExpandFile -Destination $tempExtractPath
        
    } else {
        Write-Host "Failed to download the file."
        return
    }
    
    #Lenovo Vantage Service
    Write-Host -ForegroundColor Cyan " Installing Lenovo Vantage Service..."
    Write-Host "Launching $tempExtractPath\VantageService\Install-VantageService.ps1"
    Invoke-Expression -command "$tempExtractPath\VantageService\Install-VantageService.ps1"
    
    #July Version - Having issues with during OSD, reverting back
    #write-host "Launching $tempExtractPath\VantageInstaller.exe Install -Vantage"
    #Invoke-Expression -command "$tempExtractPath\VantageInstaller.exe Install -Vantage"
    
    #Lenovo Vantage Batch File
    write-host -ForegroundColor Cyan " Installing Lenovo Vantage...batch file..."
    $ArgumentList = "/c $($tempExtractPath)\setup-commercial-vantage.bat"
    $InstallProcess = Start-Process -FilePath "cmd.exe" -ArgumentList $ArgumentList -Wait -PassThru
    if ($InstallProcess.ExitCode -eq 0) {
        Write-Host -ForegroundColor Green "Lenovo Vantage completed successfully."
        $RegistryPath = "HKLM:\SOFTWARE\Policies\Lenovo\Commercial Vantage"
        New-Item -Path $RegistryPath -ItemType Directory -Force |Out-Null
        New-ItemProperty -Path $RegistryPath -Name "AcceptEULAAutomatically" -Value 1 -PropertyType dword -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name "wmi.warranty" -Value 1 -PropertyType dword -Force | Out-Null
    } else {
        Write-Host -ForegroundColor Red "Lenovo Vantage failed with exit code $($InstallProcess.ExitCode)."
    }
    
    Write-Host "Launching $tempExtractPath\lenovo-commercial-vantage-install.ps1"
    #Get Current Path
    $CurrentPath = Get-Location
    Set-Location -Path $tempExtractPath
    try {
        Invoke-Expression -command "$tempExtractPath\lenovo-commercial-vantage-install.ps1"
    }
    catch {
        Write-Host "Had issues with $($_.Exception.Message)"
    }
    
    Set-Location -Path $CurrentPath

    if ($IncludeSUHelper){
        $InstallProcess = Start-Process -FilePath $tempExtractPath\SystemUpdate\SUHelperSetup.exe -ArgumentList "/VERYSILENT /NORESTART" -Wait -PassThru
        if ($InstallProcess.ExitCode -eq 0) {
            Write-Host -ForegroundColor Green "Lenovo SU Helper completed successfully."
        } else {
            Write-Host -ForegroundColor Red "Lenovo SU Helper failed with exit code $($InstallProcess.ExitCode)."
        }
    }
}


function Set-LenovoVantage {
    [CmdletBinding()]
    param (
    [ValidateSet('True','False')]
    [string]$AcceptEULAAutomatically = 'True',
    [ValidateSet('True','False')]
    [string]$WarrantyInfoHide,
    [ValidateSet('True','False')]
    [string]$WarrantyWriteWMI = 'True',
    [ValidateSet('True','False')]
    [string]$MyDevicePageHide,
    [ValidateSet('True','False')]
    [string]$WiFiSecurityPageHide,
    [ValidateSet('True','False')]
    [string]$HardwareScanPageHide,
    [ValidateSet('True','False')]
    [string]$GiveFeedbackPageHide,
    [ValidateSet('True','False')]
    [string]$TurnOffMicrophoneSettings = 'True'    
    )
    
    
    $RegistryPath = "HKLM:\SOFTWARE\Policies\Lenovo\Commercial Vantage"
    if (!(Test-Path -Path $RegistryPath)){
        return "Lenovo Vantage is not installed. Please install Lenovo Vantage first."
    }
    # Check if Lenovo Vantage is installed
    if (Test-Path "C:\Program Files (x86)\Lenovo\VantageService") {
        #Write-Host "Lenovo Vantage is already installed."
    } else {
        Write-Host "Lenovo Vantage is not installed. Installing..."
        Install-LenovoVantage
    }
    # Check if the registry path exists
    if (Test-Path $RegistryPath) {
        #Write-Host "Registry path already exists"
    } else {
        New-Item -Path $RegistryPath -Force | Out-Null
    }
    
    # Set the registry values
    if ($AcceptEULAAutomatically) {
        if ($AcceptEULAAutomatically -eq $true){
            Write-Host "Setting AcceptEULAAutomatically to 1"
            New-ItemProperty -Path $RegistryPath -Name "AcceptEULAAutomatically" -Value 1 -PropertyType dword -Force | Out-Null
        }
        else {
            Write-Host "Setting AcceptEULAAutomatically to 0"
            New-ItemProperty -Path $RegistryPath -Name "AcceptEULAAutomatically" -Value 0 -PropertyType dword -Force | Out-Null
        }
    }
    
    if ($WarrantyInfoHide) {
        if ($WarrantyInfoHide -eq $true){
            Write-Host "Setting WarrantyInfoHide to 1"
            New-ItemProperty -Path $RegistryPath -Name "feature.warranty" -Value 1 -PropertyType dword -Force | Out-Null
        }
        else {
            Write-Host "Setting WarrantyInfoHide to 0"
            New-ItemProperty -Path $RegistryPath -Name "feature.warranty" -Value 0 -PropertyType dword -Force | Out-Null
        }
    }
    if ($WarrantyWriteWMI) {
        if ($WarrantyWriteWMI -eq $true){
            Write-Host "Setting WarrantyWriteWMI to 1"
            New-ItemProperty -Path $RegistryPath -Name "wmi.warranty" -Value 1 -PropertyType dword -Force | Out-Null
        }
        else {
            Write-Host "Setting WarrantyWriteWMI to 0"
            New-ItemProperty -Path $RegistryPath -Name "wmi.warranty" -Value 0 -PropertyType dword -Force | Out-Null
        }
    }
    
    if ($MyDevicePageHide) {
        if ($MyDevicePageHide -eq $true){
            Write-Host "Setting MyDevicePageHide to 1"
            New-ItemProperty -Path $RegistryPath -Name "page.myDevice" -Value 1 -PropertyType dword -Force | Out-Null
        }
        else {
            Write-Host "Setting MyDevicePageHide to 0"
            New-ItemProperty -Path $RegistryPath -Name "page.myDevice" -Value 0 -PropertyType dword -Force | Out-Null
        }
    }
    
    if ($WiFiSecurityPageHide) {
        if ($WiFiSecurityPageHide -eq $true){
            Write-Host "Setting WiFiSecurityPageHide to 1"
            New-ItemProperty -Path $RegistryPath -Name "page.wifiSecurity" -Value 1 -PropertyType dword -Force | Out-Null
        }
        else {
            Write-Host "Setting WiFiSecurityPageHide to 0"
            New-ItemProperty -Path $RegistryPath -Name "page.wifiSecurity" -Value 0 -PropertyType dword -Force | Out-Null
        }
    }
    
    if ($HardwareScanPageHide) {
        if ($HardwareScanPageHide -eq $true){
            Write-Host "Setting HardwareScanPageHide to 1"
            New-ItemProperty -Path $RegistryPath -Name "page.hardwareScan" -Value 1 -PropertyType dword -Force | Out-Null
        }
        else {
            Write-Host "Setting HardwareScanPageHide to 0"
            New-ItemProperty -Path $RegistryPath -Name "page.hardwareScan" -Value 0 -PropertyType dword -Force | Out-Null
        }
    }
    
    if ($GiveFeedbackPageHide) {
        if ($GiveFeedbackPageHide -eq $true){
            Write-Host "Setting GiveFeedbackPageHide to 1"
            New-ItemProperty -Path $RegistryPath -Name "feature.giveFeedback" -Value 1 -PropertyType dword -Force | Out-Null
        }
        else {
            Write-Host "Setting GiveFeedbackPageHide to 0"
            New-ItemProperty -Path $RegistryPath -Name "feature.giveFeedback" -Value 0 -PropertyType dword -Force | Out-Null
        }
    }
    if ($TurnOffMicrophoneSettings) {
        if ($TurnOffMicrophoneSettings -eq $true){
            Write-Host "Setting TurnOffMicrophoneSettings to 1"
            New-ItemProperty -Path $RegistryPath -Name "feature.device-settings.audio.microphone-settings" -Value 1 -PropertyType dword -Force | Out-Null
        }
        else {
            Write-Host "Setting TurnOffMicrophoneSettings to 0"
            New-ItemProperty -Path $RegistryPath -Name "feature.device-settings.audio.microphone-settings" -Value 0 -PropertyType dword -Force | Out-Null
        }
    }   
}

#Endregion Functions

# Install Lenovo Vantage
Write-Host "Launching Install-LenovoVantage"
Install-LenovoVantage

# Set Lenovo Vantage Settings
Write-Host "Setting Lenovo Vantage Settings"

Set-LenovoVantage -AcceptEULAAutomatically $true `
-WarrantyInfoHide $WarrantyInfoHide `
-WarrantyWriteWMI $true `
-MyDevicePageHide $MyDevicePageHide `
-WiFiSecurityPageHide $WiFiSecurityPageHide `
-HardwareScanPageHide $HardwareScanPageHide `
-GiveFeedbackPageHide $GiveFeedbackPageHide


