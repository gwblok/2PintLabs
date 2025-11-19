Import-Module DeployR.Utility
try {
    $PATH = "$(${TSEnv:OSDTARGETSYSTEMDRIVE})\"
    $LogFolder = ${TSEnv:_DEPLOYRLOGS}
}
catch {
    $LogFolder = "$env:Temp"
    $Path = $null
}

Start-Transcript -Path "$LogFolder\StifleR_Client_Install.log" -Append

$STIFLERSERVERS = 'https://214-StifleR.2p.garytown.com:1414'
$STIFLERULEZURL = 'https://raw.githubusercontent.com/2pintsoftware/StifleRRules/master/StifleRulez.xml'
#$ClientURL = 'https://214-StifleR.2p.garytown.com/StifleR-ClientApp.zip'

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

<#
{"SettingsOptions":{"StifleRulezURL":"https://raw.githubusercontent.com/2pintsoftware/StifleRRules/master/StifleRulez.xml","LogEventLevel":"Verbose","StiflerServers":"[\u0022https://dr.2pintlabs.com:1414\u0022]","EnableDebugTelemetry":"True","UseServerAsClient":"True","SignalRLogging":"True","RemoteToolsCapabilitiesFlag":"FileExplorer,%20FileContent,%20RegistryViewer,%20WmiViewer,%20EventLogs,%20PerformanceCounters,%20ResourceMonitor,%20TaskManager,%20DeviceInformation,%20RemoteAssistance,%20Rdp,%20RemoteCli,%20TsData,%20IntuneLogs,%20TunnelRdp"}}

$OPTIONS = @"
{"SettingsOptions":{"StifleRulezURL":"$STIFLERULEZURL","StiflerServers":"[\u0022$STIFLERSERVERS\u0022]","VPNStrings":"[\u0022VPN\u0022,\u0022Cisco%20AnyConnect\u0022,\u0022Virtual%20Private%20Network\u0022,\u0022SonicWall\u0022,\u0022WireGuard\u0022]","EnableDebugTelemetry":"True","UseServerAsClient":"True","SignalRLogging":"True","RemoteToolsCapabilitiesFlag":"FileExplorer,%20FileContent,%20RegistryViewer,%20WmiViewer,%20EventLogs,%20PerformanceCounters,%20ResourceMonitor,%20TaskManager,%20DeviceInformation,%20RemoteAssistance,%20Rdp,%20RemoteCli,%20TsData,%20IntuneLogs,%20TunnelRdp"}}
"@
#>
$OPTIONS = @"
{"SettingsOptions":{"StifleRulezURL":"$STIFLERULEZURL","StiflerServers":"[\u0022$STIFLERSERVERS\u0022]","VPNStrings":"[\u0022VPN\u0022,\u0022Cisco%20AnyConnect\u0022,\u0022Virtual%20Private%20Network\u0022,\u0022SonicWall\u0022,\u0022WireGuard\u0022]","EnableDebugTelemetry":"True","UseServerAsClient":"True","SignalRLogging":"True","RemoteToolsCapabilitiesFlag":"FileExplorer,%20FileContent,%20RegistryViewer,%20WmiViewer,%20EventLogs,%20PerformanceCounters,%20ResourceMonitor,%20TaskManager,%20DeviceInformation,%20RemoteAssistance,%20Rdp,%20RemoteCli,%20TsData,%20Intune,%20TunnelRdp"}}
"@
if (Test-Path -Path .\settings.2psImport) {
    $OptionsFile = $true
    $OPTIONS = Get-Content -Path .\settings.2psImport -Raw
}

$OPTIONS = Get-Content -Path .\settings.2psImport -Raw
Write-Host -ForegroundColor DarkGray "-------------------------------------------------------"
Write-Host -ForegroundColor Cyan "Installing StifleR Client with the following options:"
write-host -ForegroundColor Green "StifleR Servers: $STIFLERSERVERS"
write-host -ForegroundColor Green "StifleR Rulez URL: $STIFLERULEZURL"
write-host -ForegroundColor Green "VPN Strings: VPN, Cisco AnyConnect, Virtual Private Network, SonicWall, WireGuard"
write-host -ForegroundColor Green "Found Options File (settings.2psImport): $OptionsFile"
Write-Host -ForegroundColor DarkGray "-------------------------------------------------------"
#Write out the contents of the $Options Variables
Write-Host -ForegroundColor gray "$OPTIONS"
Write-Host -ForegroundColor DarkGray "-------------------------------------------------------"
Write-Host "$Options"

write-host " Start-Process -FilePath msiexec.exe -ArgumentList `"/i $MSI /l*v $LogFolder\install.log /quiet OPTIONS=$OPTIONS AUTOSTART=1`" -Wait -PassThru"
$Install = Start-Process -FilePath msiexec.exe -ArgumentList "/i $MSI /l*v $LogFolder\install.log /quiet OPTIONS=$OPTIONS AUTOSTART=1" -Wait -PassThru

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
        $Install = Start-Process -FilePath msiexec.exe -ArgumentList "/i $MSI /l*v $LogFolder\install.log /quiet OPTIONS=$OPTIONS" -Wait -PassThru
        if ($Install.ExitCode -eq 0) {
            Write-Host -ForegroundColor Green "Installation completed successfully."
        }
        else {
            Write-Host -ForegroundColor Red "Installation failed again with exit code: $($Install.ExitCode)"
            Write-Host -ForegroundColor Yellow "Please check the install.log file in $LogFolder for more details."
            Write-Host -ForegroundColor Yellow "You may need to manually remove the StifleR Client from Programs and Features."
            Write-Host -ForegroundColor Yellow "Hey, at least we tried again, that's what matters, right?"
            Stop-Transcript
            return
        }
    }
    else {
        Stop-Transcript
        return
    }
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
