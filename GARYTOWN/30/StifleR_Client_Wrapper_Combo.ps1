Function Install-StifleRClient {
[CmdletBinding()]
param (
[string]$ClientURL,
[string]$STIFLERSERVERS = 'https://dr.2pintlabs.com:1414',
[string]$STIFLERULEZURL = 'https://raw.githubusercontent.com/2pintsoftware/StifleRRules/master/StifleRulez.xml',
[string]$STIFLERSETTINGSURL = "https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/GARYTOWN/30/dr2pintlabs.2psImport",
[AllowNull()]
[ValidateSet('3.0','2.10', IgnoreCase=$true)]
[String]$ForceVersion,
[Switch]$UseCurrentStifleRServer = $false
)

#Gather Current Info (as long as I remember to update it)
$JSONContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/GARYTOWN/StifleR-ClientApp.json"
if ($JSONContent -eq $null -or $JSONContent.Count -eq 0) {
    Write-Host "Failed to retrieve StifleR Client JSON content." -ForegroundColor Red
    return
}
#Set the Log Folder:
$LogFolder = "$env:SystemDrive\Windows\Temp"
Start-Transcript -Path "$LogFolder\StifleR_Client_Install_Transcript.log" -Append



#Region Functions
function Get-InstalledApps
{
    if (![Environment]::Is64BitProcess) {
        $regpath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    }
    else {
        $regpath = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
    }
    Get-ItemProperty $regpath | .{process{if($_.DisplayName -and $_.UninstallString) { $_ } }} | Select DisplayName, Publisher, InstallDate, DisplayVersion, UninstallString |Sort DisplayName
}
function Test-Url {
    param (
    [string]$Url
    )
    
    try {
        $request = [System.Net.WebRequest]::Create($Url)
        $request.Method = "HEAD"  # Uses HEAD to check status without downloading content
        $request.Timeout = 5000   # 5 second timeout
        
        $response = $request.GetResponse()
        $status = [int]$response.StatusCode
        
        if ($status -eq 200) {
            #Write-Output "URL is active: $Url"
            return $true
        }
        else {
            #Write-Output "URL responded with status code $status $Url"
            return $false
        }
        $response.Close()
    }
    catch {
        Write-Output "URL is not accessible: $Url - Error: $_"
    }
}
function Get-StifleRServerFromClientInstallation {
    #Get Server for 3.0 Installs
    if (Test-Path -Path 'HKLM:\SOFTWARE\2Pint Software\StifleR\Client\SettingsOptions') {
    
        $StifleRClientValues = Get-Item -Path 'HKLM:\SOFTWARE\2Pint Software\StifleR\Client\SettingsOptions' -ErrorAction SilentlyContinue
        $STIFLERSERVERS = $StifleRClientValues.GetValue('StiflerServers')
        if ($STIFLERSERVERS) {
            $STIFLERSERVERS = ($STIFLERSERVERS -replace '[\[\]]', '' -replace '"',' ').Trim()
            Write-Host "Using existing StifleR Servers from installed client: $STIFLERSERVERS" -ForegroundColor Yellow
        }
        else {
            Write-Host "No existing StifleR Servers found in installed client, which is really odd, you might want to look into that!" -ForegroundColor Yellow
        }
    }
    #Get Server for 2.10 Installs
    else {
        if (Test-Path -Path "C:\Program Files\2Pint Software\StifleR Client\StifleR.ClientApp.exe.Config") {
            [xml]$configXml = Get-Content -Path "C:\Program Files\2Pint Software\StifleR Client\StifleR.ClientApp.exe.Config"
            $serverNode = $configXml.configuration.appSettings.add | Where-Object { $_.key -eq 'StifleRServers' }
            if ($serverNode) {
                $STIFLERSERVERS = $serverNode.value
                Write-Host "Using existing StifleR Servers from config file: $STIFLERSERVERS" -ForegroundColor Yellow
            }
            else {
                Write-Host "No existing StifleR Servers found in config file, which is really odd, you might want to look into that!" -ForegroundColor Yellow
            }
        }
    }
    if ($null -eq $STIFLERSERVERS -or $STIFLERSERVERS -eq '') {
        Write-Host "No existing StifleR Servers found in installed client." -ForegroundColor Yellow
        return $null
    }
    return $STIFLERSERVERS
}
#endRegion Functions

if ($ForceVersion){
    Write-Host "ForceVersion parameter provided, using version $ForceVersion from JSON" -ForegroundColor Yellow
    try {
        $requestedVersion = [version]$ForceVersion
    } catch {
        Write-Host "Invalid ForceVersion format: $ForceVersion" -ForegroundColor Red
        return
    }
    
    # Try to find an exact major.minor match first
    $MatchedEntry = $JSONContent |
    Where-Object {
        try {
            $v = [version]($_.Version.ToString())
            ($v.Major -eq $requestedVersion.Major) -and ($v.Minor -eq $requestedVersion.Minor)
        } catch { $false }
    } |
    Select-Object -First 1
    
    if (-not $MatchedEntry) {
        Write-Host "No exact major.minor match for $ForceVersion. Attempting to match major version $($requestedVersion.Major)..." -ForegroundColor Yellow
    }
    # Try to find a matching major version
}
else {
    #Get Current Installed Version
    $StifleRClientAppInfo = Get-InstalledApps | Where-Object {$_.DisplayName -match "StifleR Client"}
    
    #If StifleR Client is installed, then get corresponding Target Version from JSON
    if ($StifleRClientAppInfo) {
        Write-Host "StifleR Client is installed. Version: $($StifleRClientAppInfo.DisplayVersion)" -ForegroundColor Green
        [Version]$CurrentVersion = $StifleRClientAppInfo.DisplayVersion
        
        # collect versions from JSONContent
        $VERSIONS = $JSONContent |
        ForEach-Object {
            try { [version]($_.Version.ToString()) } catch { $null }
        } |
        Where-Object { $_ -ne $null } |
        Sort-Object -Unique
        
        # find JSON entry that matches the installed major version
        $MatchedEntry = $JSONContent |
        Where-Object {
            try { ([version]($_.Version.ToString())).Major -eq $CurrentVersion.Major } catch { $false }
        } |
        Select-Object -First 1
        
        
    }
    # If No StifleR Client or Match, just get the latest Version info from JSON
    if (!($MatchedEntry)) {
        # fallback: pick the highest available version if no major match
        $MatchedEntry = $JSONContent |
        Where-Object {
            try { ([version]($_.Version.ToString())) -eq ($VERSIONS | Sort-Object -Descending | Select-Object -First 1) } catch { $false }
        } |
        Select-Object -First 1
    }
}

#Set the URL for the Target Version
if ($null -eq $ClientURL -or $ClientURL -eq '') {   
    $ClientURL = $MatchedEntry.URL
    Write-Host "No ClientURL provided, using URL from JSON for version $($MatchedEntry.Version): $ClientURL" -ForegroundColor Yellow
}
else {
    Write-Host "Using provided ClientURL: $ClientURL" -ForegroundColor Yellow
}

#Set Target Version
try {
    $TargetVersion = ([version]($MatchedEntry.Version.ToString())).ToString()
    $TargetVersionMajor = ([version]($MatchedEntry.Version.ToString())).Major 
    $TargetVersionMinor = ([version]($MatchedEntry.Version.ToString())).Minor
    $TargetVersionMajorMinor = "$TargetVersionMajor.$TargetVersionMinor"
} catch {
    Write-Host "Failed to parse Target Version from JSON entry." -ForegroundColor Red
    return
}

#Grab StifleR Server settings from existing install if requested
if ($UseCurrentStifleRServer) {
    Write-Host "UseCurrentStifleRServer switch provided, using current StifleR Server settings from installed client." -ForegroundColor Yellow
    $STIFLERSERVERS = Get-StifleRServerFromClientInstallation   
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "Testing Connection to StifleR Server: $STIFLERSERVERS before proceeding with installation..."
$StifleRServerBaseName = $STIFLERSERVERS.Replace('https://', '').Replace(':1414', '')
if ((Test-NetConnection -ComputerName $StifleRServerBaseName -Port 1414 -WarningAction SilentlyContinue).TcpTestSucceeded -eq $false) {
    Write-Host -ForegroundColor Red "StifleR Server is not reachable. Please check the server address and port."
    return
}
Write-Host -ForegroundColor Green "StifleR Server is reachable. Proceeding with installation..."

#Create Temp Directory
$tempDir = Join-Path ("$env:SystemDrive\Windows\Temp") ([System.IO.Path]::GetRandomFileName())

#Download the StifleR Client Package
$packageName = $ClientURL.Split('/')[-1]
If (Test-Path -path "C:\_2P\Installers\$packageName"){
    $packagePath = "C:\_2P\Installers\$packageName"
}
else {
    $null = New-Item -ItemType Directory -Path $tempDir -Force -ErrorAction SilentlyContinue
    $packagePath = Join-Path -Path $tempDir -ChildPath $packageName
    
    #Test URLs
    if (-not (Test-Url -Url $ClientURL)) {
        Write-Output "URL is not accessible: $ClientURL"
        return
    }
    
    #Download the package
    Write-Host -ForegroundColor Cyan "Starting download and extraction of $packageName"
    try {
        Write-Host "Using BITS to download $ClientURL to $packagePath"
        Start-BitsTransfer -Source $ClientURL -Destination $packagePath
    }
    catch {
        Write-Host "BITS download failed, falling back to Invoke-WebRequest"
        Invoke-WebRequest -Uri $ClientURL -OutFile $packagePath -UseBasicParsing
    }    
}
#Prepare for Installing of Agent 3.0
if ($TargetVersionMajorMinor -eq '3.0'){
    Write-Host "Target Version is 3.0, preparing settings for StifleR Client 3.0"
    #Get Settings File From GitHub
    Write-Host "Downloading settings.2psImport from $STIFLERSETTINGSURL"
    Invoke-WebRequest -Uri $STIFLERSETTINGSURL -OutFile "$tempDir\settings.2psImport"

    if (Test-Path -Path "$tempDir\settings.2psImport") {
        Write-Host "Found settings.2psImport file in the temp directory after download, using settings from file." -ForegroundColor Green
        $OptionsFile = $true
        $OPTIONS = Get-Content -Path "$tempDir\settings.2psImport" -Raw
        
    }
    else{
        Write-Host -ForegroundColor Red "No $tempDir\settings.2psImport file found in the current directory"
    }
}
#Prepare for Installing of Agent 2.10
else {
    Write-Host "Target Version is $TargetVersionMajorMinor, preparing settings for StifleR Client 2.10"
    $ClientInstallScript = 'https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/StifleR/StifleR_Client_Installer.ps1'
    write-host -ForegroundColor DarkGray "Invoke-WebRequest -UseBasicParsing -Uri $ClientInstallScript -OutFile $tempDir\StifleR_Client_Installer.ps1"
    Invoke-WebRequest -UseBasicParsing -Uri $ClientInstallScript -OutFile "$tempDir\StifleR_Client_Installer.ps1"

    if (Test-path -path "$tempDir\StifleR_Client_Installer.ps1" ) {
        Write-Output "Successfully Created $tempDir\StifleR_Client_Installer.ps1"  
    }
    else{
        Write-Output "Failed to create $tempDir\StifleR_Client_Installer.ps1"
        exit 253
    }
    #Build Defaults.ini
    $StifleRDefaultsini = @"
[MSIPARAMS]
INSTALLFOLDER=C:\Program Files\2Pint Software\StifleR Client
STIFLERSERVERS=$STIFLERSERVERS
STIFLERULEZURL=$STIFLERULEZURL
DEBUGLOG=0
RULESTIMER=86400
MSILOGFILE=C:\Windows\Temp\StifleRClientMSI.log


[CONFIG]
VPNStrings=Citrix VPN, Cisco AnyConnect, WireGuard
ForceVPN=0
Logfile=C:\Windows\Temp\StifleRInstaller.log
Features=Power, PerformanceCounters, AdminElevatedTracking,EventLog
BranchCachePort=1337
BlueLeaderProxyPort=1338
GreenLeaderOfferPort=1339
BranchCachePortForGreenLeader=1336
DefaultNonRedLeaderDOPolicy=102400
DefaultNonRedLeaderBITSPolicy=768000
DefaultDisconnectedDOPolicy=25600
DefaultDisconnectedBITSPolicy=25600

[CUSTOM]
;This section is used for custom actions that are not part of the standard installation
;These settings are used if the EnableSiteDetection param is set to true/1
DOMAIN=2P
ProductionStifleRServers=$STIFLERSERVERS
ProductionStifleRulezUrl=$STIFLERULEZURL
PreProductionStifleRServers=$STIFLERSERVERS
PreProductionStifleRServers=$STIFLERULEZURL
ProductionSMSSiteCode=2CM
"@
    $StifleRDefaultsini | Out-File -FilePath "$tempDir\StifleRDefaults.ini" -Force -Encoding utf8
    if (Test-path -path "$tempDir\StifleRDefaults.ini") {
        Write-Output "Successfully Created $tempDir\StifleRDefaults.ini"  
    }
}


#$JSON = $OPTIONS | ConvertFrom-Json
#Pull out the brackets and quotes
#$STIFLERSERVERS = ($JSON.SettingsOptions.StiflerServers -replace '[\[\]]', '' -replace '"',' ').Trim()
#$STIFLERSERVERS = $JSON.SettingsOptions.StiflerServers -replace '[\[\]\\u0022]' -replace '"',' '
#$STIFLERULEZURL = ($JSON.SettingsOptions.StifleRulezURL -replace '[\[\]]', '' -replace '"',' ').Trim()
#$VPNSTRINGS = ($JSON.SettingsOptions.VPNStrings -replace '[\[\]]', '' -replace '"',' ').Trim()




#Extract the package
if (Test-Path -Path $packagePath){
    Write-Host -ForegroundColor Cyan "Extracting package to $tempDir"
}
else {
    Write-Host -ForegroundColor Red "Package not found at $packagePath"
    exit 1
}
Expand-Archive -Path $packagePath -DestinationPath $tempDir -Force

if (Test-Path -Path $tempDir){
    Write-Host -ForegroundColor Green "Download and extraction completed successfully."
    $MSI = (Get-ChildItem -Path $tempDir -Filter *.msi -Recurse).FullName
}
else {
    Write-Host -ForegroundColor Red "Download or extraction failed."
    exit 1
}
if (Test-Path -Path $MSI){
    Write-Host -ForegroundColor Green "MSI found: $MSI"
}
else {
    Write-Host -ForegroundColor Red "MSI not found in the extracted files."
    return
}

<# Not using anymore, leaving here for reference

#Create Fall back if didn't find settings file
$OPTIONS = @"
{"SettingsOptions":{"StifleRulezURL":"$STIFLERULEZURL","StiflerServers":"[\u0022$STIFLERSERVERS\u0022]","VPNStrings":"[\u0022VPN\u0022,\u0022Cisco%20AnyConnect\u0022,\u0022Virtual%20Private%20Network\u0022,\u0022SonicWall\u0022,\u0022WireGuard\u0022]","EnableDebugTelemetry":"True","UseServerAsClient":"True","SignalRLogging":"True","RemoteToolsCapabilitiesFlag":"FileExplorer,%20FileContent,%20RegistryViewer,%20WmiViewer,%20EventLogs,%20PerformanceCounters,%20ResourceMonitor,%20TaskManager,%20DeviceInformation,%20RemoteAssistance,%20Rdp,%20RemoteCli,%20TsData,%20Intune,%20TunnelRdp"}}
"@
#Use these Settings if found settings file
if (Test-Path -Path .\settings.2psImport) {
$OPTIONS = Get-Content -Path .\settings.2psImport -Raw
}
#>


Write-Host -ForegroundColor DarkGray "-------------------------------------------------------"
Write-Host -ForegroundColor Cyan "Installing StifleR Client with the following options:"
write-host -ForegroundColor Green "StifleR Servers: $STIFLERSERVERS"
write-host -ForegroundColor Green "StifleR Rulez URL: $STIFLERULEZURL"
Write-Host -ForegroundColor DarkGray "-------------------------------------------------------"
#Write-Host "$Options"

Write-Host -ForegroundColor DarkGray "-------------------------------------------------------"
#Install the MSI
write-host -ForegroundColor Cyan "Starting installation of StifleR Client..."

if ($TargetVersionMajorMinor -eq '3.0'){
    Write-Host " Start-Process -FilePath msiexec.exe -ArgumentList `"/i $MSI /l*v $LogFolder\StifleR_Client_Install_MSI.log /quiet AUTOSTART=1 OPTIONS=$tempDir\settings.2psImport`" -Wait -PassThru"
    $Install = Start-Process -FilePath msiexec.exe -ArgumentList "/i $MSI /l*v $LogFolder\StifleR_Client_Install_MSI.log /quiet AUTOSTART=1 OPTIONS=`"$tempDir\settings.2psImport`"" -Wait -PassThru
if ($Install.ExitCode -eq 0) {
    Write-Host -ForegroundColor Green "Installation completed successfully."
}
else {
    Write-Host -ForegroundColor Red "Installation failed with exit code: $($Install.ExitCode)"
    if (Test-Path -path 'HKLM:\SOFTWARE\2Pint Software'){
        Write-Host -ForegroundColor Yellow "Attempting to remove existing StifleR Client Registry and Try Install Again."
        Remove-Item -Path 'HKLM:\SOFTWARE\2Pint Software' -Recurse -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Write-Host -ForegroundColor Cyan "Retrying installation..."
        $Install = Start-Process -FilePath msiexec.exe -ArgumentList "/i $MSI /l*v $tempDir\install.log /quiet OPTIONS=$OPTIONS AUTOSTART=1" -Wait -PassThru
        if ($Install.ExitCode -eq 0) {
            Write-Host -ForegroundColor Green "Installation completed successfully."
        }
        else {
            Write-Host -ForegroundColor Red "Installation failed again with exit code: $($Install.ExitCode)"
            Write-Host -ForegroundColor Yellow "Please check the install.log file in $tempDir for more details."
            Write-Host -ForegroundColor Yellow "You may need to manually remove the StifleR Client from Programs and Features."
            Write-Host -ForegroundColor Yellow "Hey, at least we tried again, that's what matters, right?"
            return
        }
    }
    else {
        return
    }
}
}
else {
    #Build CMD file
    $RunPScmd = @"
REM - this CMD file checks the platform (x86/64) and then runs the correct PS command line


PUSHD %~dp0
If "%PROCESSOR_ARCHITEW6432%"=="AMD64" GOTO 64bit
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -Command ".\StifleR_Client_Installer.ps1 -Defaults .\StifleRDefaults.ini -DebugPreference Continue"
GOTO END
:64bit
"%WinDir%\Sysnative\windowsPowershell\v1.0\Powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command ".\StifleR_Client_Installer.ps1 -Defaults .\StifleRDefaults.ini -DebugPreference Continue"
:END
POPD
"@

    $RunPScmd | Out-File -FilePath "$tempDir\RunPS.cmd" -Force -Encoding utf8
    if (Test-path -path "$tempDir\RunPS.cmd") {
        Write-Output "Successfully Created $tempDir\RunPS.cmd"  
    }
    #Trigger RunPS.cmd
    Write-Host "Running $tempDir\RunPS.cmd" -ForegroundColor Green
    $Install = Start-Process -FilePath "$tempDir\RunPS.cmd" -Wait
}


Start-Sleep -Seconds 5
Get-InstalledApps | Where-Object { $_.DisplayName -like "*StifleR*" } | Format-Table -AutoSize

$StifleRService = get-service -Name StifleRClient -ErrorAction SilentlyContinue
if (-not $StifleRService) {
    Write-Host -ForegroundColor Red "StifleR Client service not found. Please check the installation."
    return
}
else{
    if ($StifleRService.Status -ne 'Running'){
        Start-Service -Name StifleRClient
    }
    if ($StifleRService.StartType -ne 'Automatic'){
        Set-Service -Name StifleRClient -StartupType Automatic
    }
}
Stop-Transcript
}