
#Set the Log Folder:
$LogFolder = "$env:SystemDrive\Windows\Temp\"
Start-Transcript -Path "$LogFolder\StifleR_Client_Install_Transcript.log" -Append

$StifleRSettingsConfigFileName = "settings.2psImport"
$STIFLERSERVERS = 'https://214-StifleR.2p.garytown.com:1414'
$STIFLERULEZURL = 'https://raw.githubusercontent.com/2pintsoftware/StifleRRules/master/StifleRulez.xml'
$OPTIONS = @"
{"SettingsOptions":{"StifleRulezURL":"$STIFLERULEZURL","StiflerServers":"[\u0022$STIFLERSERVERS\u0022]","VPNStrings":"[\u0022VPN\u0022,\u0022Cisco%20AnyConnect\u0022,\u0022Virtual%20Private%20Network\u0022,\u0022SonicWall\u0022,\u0022WireGuard\u0022,\u0022PanGP\u0022,\u0022Virtual%20Private%20Network\u0022]","EnableDebugTelemetry":"True","UseServerAsClient":"True","SignalRLogging":"True","RemoteToolsCapabilitiesFlag":"FileExplorer,%20FileContent,%20RegistryViewer,%20WmiViewer,%20EventLogs,%20PerformanceCounters,%20ResourceMonitor,%20TaskManager,%20DeviceInformation,%20RemoteAssistance,%20Rdp,%20RemoteCli,%20TsData,%20Intune,%20TunnelRdp"}}
"@


if (Test-Path -Path .\$StifleRSettingsConfigFileName) {
    Write-Host "Found $StifleRSettingsConfigFileName file in the current directory, using settings from file." -ForegroundColor Green
    $OptionsFile = $true
    $OPTIONS = Get-Content -Path .\$StifleRSettingsConfigFileName -Raw
    
}
else{
    Write-Host -ForegroundColor Red "No $StifleRSettingsConfigFileName file found in the current directory"
}

$JSON = $OPTIONS | ConvertFrom-Json
$STIFLERSERVERS = $JSON.SettingsOptions.StiflerServers -replace '[\[\]\\u0022]' -replace '"',' '
$STIFLERULEZURL = $JSON.SettingsOptions.StifleRulezURL -replace '[\[\]\\u0022]'
$VPNSTRINGS = $JSON.SettingsOptions.VPNStrings -replace '[\[\]\\u0022]' -replace '%',' '


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
Write-Host "Testing Connection to StifleR Server: $STIFLERSERVERS before proceeding with installation..."
$StifleRServerBaseName = $STIFLERSERVERS.Replace('https://', '').Replace(':1414', '')
write-Host "Running... Test-NetConnection -ComputerName $StifleRServerBaseName -Port 1414:"
if ((Test-NetConnection -ComputerName $StifleRServerBaseName -Port 1414 -WarningAction SilentlyContinue).TcpTestSucceeded -eq $false) {
    Write-Host -ForegroundColor Red "StifleR Server is not reachable. Please check the server address and port."
    Stop-Transcript
    return
}
Write-Host -ForegroundColor Green "StifleR Server is reachable. Proceeding with installation..."

$MSI = (Get-ChildItem -Path .\ -Filter *.msi -Recurse).FullName
if (-not $MSI) {
    Write-Host -ForegroundColor Red "No MSI file found in the current directory. Please ensure the StifleR Client MSI is present."
    Stop-Transcript
    return
}


Write-Host -ForegroundColor DarkGray "-------------------------------------------------------"
Write-Host -ForegroundColor Cyan "Installing StifleR Client with the following options:"
if ($OptionsFile) {write-host -ForegroundColor Green "Found Options File ($StifleRSettingsConfigFileName): $OptionsFile"}
else {write-host -ForegroundColor Yellow "No 2psImport file found in the current directory, reverting to defaults."}
write-host -ForegroundColor Green "StifleR Servers: $STIFLERSERVERS"
write-host -ForegroundColor Green "StifleR Rulez URL: $STIFLERULEZURL"
write-host -ForegroundColor Green "VPN Strings: $VPNSTRINGS"

Write-Host -ForegroundColor DarkGray "-------------------------------------------------------"
#Write out the contents of the $Options Variables
write-host -ForegroundColor DarkGray "OPTIONS being used for install in $StifleRSettingsConfigFileName"
Write-Host -ForegroundColor gray "$OPTIONS"
Write-Host -ForegroundColor DarkGray "-------------------------------------------------------"


write-host " Start-Process -FilePath msiexec.exe -ArgumentList `"/i $MSI /l*v $LogFolder\StifleR_Client_Install_MSI.log /quiet OPTIONS=$OPTIONS AUTOSTART=1`" -Wait -PassThru"
$Install = Start-Process -FilePath msiexec.exe -ArgumentList "/i $MSI /l*v $LogFolder\StifleR_Client_Install_MSI.log /quiet OPTIONS=$OPTIONS AUTOSTART=1" -Wait -PassThru

if ($Install.ExitCode -eq 0) {
    Write-Host -ForegroundColor Green "Installation completed successfully."
}
else {
    Write-Host -ForegroundColor Red "Installation failed with exit code: $($Install.ExitCode)"
}

Start-Sleep -Seconds 5
Get-InstalledApps | Where-Object { $_.DisplayName -like "*StifleR*" } | Format-Table -AutoSize

$StifleRService = get-service -Name StifleRClient -ErrorAction SilentlyContinue
if (-not $StifleRService) {
    Write-Host -ForegroundColor Red "StifleR Client service not found. Please check the installation."
    Stop-Transcript
    return
}
else{
    if ($StifleRService.Status -ne 'Running'){
        Start-Service -Name StifleRClient -ErrorAction SilentlyContinue
    }
    if ($StifleRService.StartType -ne 'Automatic'){
        Set-Service -Name StifleRClient -StartupType Automatic -ErrorAction SilentlyContinue
    }
}
