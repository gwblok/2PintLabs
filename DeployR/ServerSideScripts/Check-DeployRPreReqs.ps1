<#Tests
- Check if all required applications are installed
- Validate server configuration settings
- Ensure firewall rules are correctly set
- Checks Connectivity for DeployR / StifleR URLs & Ports based on Registry Entries
- Check if BranchCache is enabled
- Check if IIS components are installed
- Check if IIS Virtual Web Directory is Setup
- Check if IIS MIME types added
- Check StifleR Dashboard URLs in Registry & Server Config File
- Check for Certificate set in StifleR & DeployR is same and that the thumbprint exists
- Check if all required services are running
- Check for SQL String Connection based on DeployR Registry



Remediation at end will prompt to remediate:
- Missing IIS MIME types
- Missing IIS Virtual Directories
- Missing Windows Components

Change Log
- 2025-10-22 - Updated .NET version to 8.0.21
#>

#Ensure Several things are installed, as well as configurations are done to help troubleshoot DeployR installations

#Keep this updated as needed 
$DotNetMinVersion = '8.0.21'



#PowerShell Table of Pre-Req Applications:
$PreReqApps = @(
[PSCustomObject]@{Title = 'Microsoft .NET Runtime'; Installed = $false ; MinVersion = $DotNetMinVersion; URL = 'https://dotnet.microsoft.com/en-us/download/dotnet/8.0'}
[PSCustomObject]@{Title = 'Microsoft Windows Desktop Runtime'; Installed = $false ; MinVersion = $DotNetMinVersion; URL = 'https://dotnet.microsoft.com/en-us/download/dotnet/8.0'}
[PSCustomObject]@{Title = 'Microsoft ASP.NET Core'; Installed = $false ; MinVersion = $DotNetMinVersion; URL = 'https://dotnet.microsoft.com/en-us/download/dotnet/8.0'}
[PSCustomObject]@{Title = 'Windows Assessment and Deployment Kit Windows Preinstallation Environment'; Installed = $false; URL = 'https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install'}
[PSCustomObject]@{Title = 'PowerShell 7-x64'; Installed = $false; URL = 'https://aka.ms/powershell-release?tag=lts'}
[PSCustomObject]@{Title = 'Microsoft SQL Server'; Installed = $false; URL = 'https://www.microsoft.com/en-us/download/details.aspx?id=104781'}
[PSCustomObject]@{Title = 'SQL Server Management Studio'; Installed = $false; URL = 'https://learn.microsoft.com/en-us/ssms/install/install'}
[PSCustomObject]@{Title = 'Microsoft Visual C++ 2015-2022 Redistributable (x64)'; Installed = $false; URL = 'https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170'}
[PSCustomObject]@{Title = '2Pint Software DeployR'; Installed = $false}
[PSCustomObject]@{Title = '2Pint Software StifleR Server'; Installed = $false}
[PSCustomObject]@{Title = '2Pint Software StifleR Dashboards'; Installed = $false}
[PSCustomObject]@{Title = '2Pint Software StifleR WmiAgent'; Installed = $false}
)
$FirewallRules = @(
[PSCustomObject]@{DisplayName = '2Pint DeployR HTTPS 7281'; Port = 7281; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint DeployR HTTP 7282'; Port = 7282; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint Software StifleR API 9000'; Port = 9000; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint Software StifleR SignalR 1414 TCP'; Port = 1414; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint Software StifleR SignalR 1414 UDP'; Port = 1414; Protocol = 'UDP'}
[PSCustomObject]@{DisplayName = '2Pint iPXE WebService 8051'; Port = 8051; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint iPXE WebService 8052'; Port = 8052; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint 2PXE 8050'; Port = 8050; Protocol = 'TCP'}
[PSCustomObject]@{DisplayName = '2Pint 2PXE 4011'; Port = 4011; Protocol = 'UDP'}
)

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
function Test-SQLConnection {
    param(
    [Parameter(Mandatory=$true)]
    [string]$ConnectionString
    )
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $connection.Open()
        Write-Host "Connection successful!" -ForegroundColor Green
        $connection.Close()
    }
    catch {
        Write-Host "Connection failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$TranscriptFilePath = "$($env:windir)temp\Check-DeployRPreReqs.log"
if (Test-Path -Path $TranscriptFilePath) {
    Remove-Item -Path $TranscriptFilePath -Force
}   
Start-Transcript -Path $TranscriptFilePath -Force

# Executing Script
Write-Host "=========================================================================" -ForegroundColor DarkGray
#Test if Applications are installed
$installedApps = Get-InstalledApps | Where-Object {$_.DisplayName -notmatch " - Shared framework"}
Write-Host "Checking for Pre-Requisite Applications..." -ForegroundColor Cyan
$PreReqAppsStatus = @()
foreach ($app in $PreReqApps) {
    $found = $installedApps | Where-Object { 
        $_.DisplayName -match [regex]::Escape($app.Title) -or
        $_.DisplayName -like "*$($app.Title)*"
    }
    
    if ($found) {
        
        if (($found | Select-Object -Unique DisplayName | Measure-Object).Count -gt 1) {
            #Write-Host "Multiple versions of $($app.Title) found:" -ForegroundColor Yellow
            #$found | Select-Object -Unique DisplayName | ForEach-Object { Write-Host " - $($_.DisplayName) Version: $($_.DisplayVersion)" -ForegroundColor Yellow }
            foreach ($appitem in $found) {
                $Version = $found.DisplayVersion
                if ($app.Url -match "dotnet"){
                    Write-Host "Testing $($found.DisplayName)"
                    if ($found.DisplayName -match "\d+\.\d+\.\d+") {
                        $Version = $matches[0]
                        #Write-Host "   Found .NET version: $Version" -ForegroundColor DarkGray
                    }
                }
                
                $PreReqAppsStatus += [PSCustomObject]@{
                    Title       = $app.Title
                    Installed   = $true
                    URL         = $app.URL
                    InstallDate = $appitem.InstallDate
                    Version     = $Version
                    DisplayName = $appitem.DisplayName
                    MinVersion  = $app.MinVersion
                }
            }
        }
        else{
            $found = $found | Select-Object -First 1
            $Version = $found.DisplayVersion
            if ($app.Url -match "dotnet"){
                #Write-Host "Testing $($found.DisplayName)"
                if ($found.DisplayName -match "\d+\.\d+\.\d+") {
                    $Version = $matches[0]
                    #Write-Host "   Found .NET version: $Version" -ForegroundColor DarkGray
                }
            }
            $PreReqAppsStatus += [PSCustomObject]@{
                Title       = $app.Title
                Installed   = $true
                URL         = $app.URL
                InstallDate = $found.InstallDate
                Version     = $Version
                DisplayName = $found.DisplayName
                MinVersion  = $app.MinVersion
            }
        }
        
        
        New-Variable -Name "Installed_$($app.Title.Replace(' ', '_'))" -Value $true -Scope Global -Force
        
    }
    
    else {
        New-Variable -Name "Installed_$($app.Title.Replace(' ', '_'))" -Value $false -Scope Global -Force
        $PreReqAppsStatus += [PSCustomObject]@{
            Title    = $app.Title
            Installed = $false
            URL      = $app.URL
        }
    }
}
#Display App Status, Green Arrow next to Installed Apps and Red X next to Missing Apps

foreach ($app in $PreReqAppsStatus) {
    
    if ($app.Installed) {
        if ($app.MinVersion -and $app.Version -and ([version]$app.Version -lt [version]$app.MinVersion)) {
            Write-Host " ✗  $($app.Title)  " -ForegroundColor Red
            Write-Host "   Installed Version: $($app.Version)" -ForegroundColor DarkGray
            Write-Host "   Minimum Required Version: $($app.MinVersion)" -ForegroundColor DarkGray
        }
        else {
            Write-Host " ✓  $($app.Title)  " -ForegroundColor Green
            Write-Host "   Installed Version: $($app.Version)" -ForegroundColor DarkGray
            Write-Host "   Display Name: $($app.DisplayName)" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host " ✗  $($app.Title)" -ForegroundColor Red
    }
}

$MissingApps = $PreReqAppsStatus | Where-Object { $_.Installed -eq $false }
if ($MissingApps) {
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "The following Pre-Requisite Applications are NOT installed:" -ForegroundColor Red
    foreach ($app in $MissingApps) {
        $appName = $app.Title -replace 'Installed_', '' -replace '_', ' '
        
        Write-Host " - $appName" -ForegroundColor Yellow
        if ($app.URL) {
            Write-Host "   Download URL: $($app.URL)" -ForegroundColor DarkGray
        }
    }
    Write-Host "Please install the missing applications and re-run this script." -ForegroundColor Yellow
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    #return
}


Write-Host "=========================================================================" -ForegroundColor DarkGray
Write-Host "Confirming Windows Features for DeployR" -ForegroundColor Cyan
#Confirm Windows Components
$RequiredWindowsComponents = @(
"BranchCache",
"Web-Server",
"Web-Http-Errors",
"Web-Static-Content",
"Web-Digest-Auth",
"Web-Windows-Auth",
"Web-Mgmt-Console"
)

foreach ($Component in $RequiredWindowsComponents) {
    if (Get-WindowsFeature -Name $Component -ErrorAction SilentlyContinue) {
        Write-Host "✓ $Component is installed." -ForegroundColor Green
    } else {
        Write-Host "✗ $Component is NOT installed." -ForegroundColor Red
        $MissingComponents += $Component
    }
}
if ($MissingComponents) {
    Write-Host "The following required components are missing:" -ForegroundColor Red
    Write-Host "Remediation: Run following Command"
    write-host -ForegroundColor darkgray "Add-WindowsFeature Web-Server, Web-Http-Errors, Web-Static-Content, Web-Digest-Auth, Web-Windows-Auth, Web-Mgmt-Console, BranchCache"
    
}

Write-Host "=========================================================================" -ForegroundColor DarkGray
Write-Host "Confirm IIS MIME Types" -ForegroundColor Cyan
# Table of required MIME types for iPXE and related boot files
$RequiredMimeTypes = @(
[PSCustomObject]@{ Extension = ".efi";  MimeType = "application/octet-stream"; Description = "EFI loader files" },
[PSCustomObject]@{ Extension = ".com";  MimeType = "application/octet-stream"; Description = "BIOS boot loaders" },
[PSCustomObject]@{ Extension = ".n12";  MimeType = "application/octet-stream"; Description = "BIOS loaders without F12 key press" },
[PSCustomObject]@{ Extension = ".sdi";  MimeType = "application/octet-stream"; Description = "boot.sdi file" },
[PSCustomObject]@{ Extension = ".bcd";  MimeType = "application/octet-stream"; Description = "boot.bcd boot configuration files" },
[PSCustomObject]@{ Extension = ".";     MimeType = "application/octet-stream"; Description = "BCD file (with no extension)" },
[PSCustomObject]@{ Extension = ".wim";  MimeType = "application/octet-stream"; Description = "winpe images (optional)" },
[PSCustomObject]@{ Extension = ".pxe";  MimeType = "application/octet-stream"; Description = "iPXE BIOS loader files" },
[PSCustomObject]@{ Extension = ".kpxe"; MimeType = "application/octet-stream"; Description = "UNDIonly version of iPXE" },
[PSCustomObject]@{ Extension = ".iso";  MimeType = "application/octet-stream"; Description = ".iso file type" },
[PSCustomObject]@{ Extension = ".img";  MimeType = "application/octet-stream"; Description = ".img file type" },
[PSCustomObject]@{ Extension = ".ipxe"; MimeType = "text/plain";                Description = ".ipxe file" }
)



try {
    Import-Module WebAdministration -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}
catch {
    write-host "Catch block executed"
}

if (Get-Module -name WebAdministration) {
    $IISMimeTypes = Get-WebConfigurationProperty -Filter /system.webServer/staticContent/mimeMap -Name "fileExtension" -PSPath "IIS:\Sites\Default Web Site"
    # Loop through required MIME types and check if present in IIS
    foreach ($mime in $RequiredMimeTypes) {
        if ($IISMimeTypes.value -contains $mime.Extension) {
            Write-Host ("✓ IIS MIME type for {0} ({1}) is configured." -f $mime.Extension, $mime.Description) -ForegroundColor Green
        } else {
            Write-Host ("✗ IIS MIME type for {0} ({1}) is NOT configured." -f $mime.Extension, $mime.Description) -ForegroundColor Red
            Write-Host "Remediation: Run following Command" -ForegroundColor Yellow
            Write-Host ("New-WebMimeType -FileExtension '{0}' -MimeType '{1}' -PSPath 'IIS:\Sites\Default Web Site'" -f $mime.Extension, $mime.MimeType) -ForegroundColor DarkGray
            $IISMimeTypeUpdateRequired = $true
        }
    }
    if ($IISMimeTypeUpdateRequired) {
        write-host -ForegroundColor Magenta "Run this Script to enable MIME Types"
        write-Host -ForegroundColor DarkGray "https://github.com/materrill/miketerrill.net/blob/master/Software%20Install%20Scripts/Configure-IISMIMETypes.ps1"
    }
}
Write-Host "=========================================================================" -ForegroundColor DarkGray
Write-Host "Checking for Services..." -ForegroundColor Cyan
#Test Services if App Installed
#Test SQL Express
if ($Installed_Microsoft_SQL_Server){
    $SQLService = Get-Service -Name 'MSSQL$SQLEXPRESS'
    if ($SQLService.Status -eq 'Running') {
        Write-Host "Microsoft SQL Server service is running." -ForegroundColor Green
        Write-Host "  Display Name: $($SQLService.DisplayName)" -ForegroundColor DarkGray
        Write-Host "  Service Name: $($SQLService.Name)" -ForegroundColor DarkGray
        Write-Host "  Start Type:   $($SQLService.StartType)" -ForegroundColor DarkGray
        $Global:SQLServiceRunning = $true
    }
    else {
        Write-Host "Microsoft SQL Server service is NOT running." -ForegroundColor Red
        Write-Host " Attempting to start service..." -ForegroundColor Yellow
        Start-Service -Name 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue
        if ($?) {
            Write-Host "Service started successfully." -ForegroundColor Green
        }
        else {
            Write-Host "Failed to start service." -ForegroundColor Red
        }
        $Global:SQLServiceRunning = $false
    }
}
#Test StifleR Service
if ($Installed_2Pint_Software_StifleR_Server){
    $StifleRService = Get-Service -Name '2Pint Software StifleR Server'
    if ($StifleRService.Status -eq 'Running') {
        Write-Host "2Pint StifleR Server service is running." -ForegroundColor Green
        Write-Host "  Display Name: $($StifleRService.DisplayName)" -ForegroundColor DarkGray
        Write-Host "  Service Name: $($StifleRService.Name)" -ForegroundColor DarkGray
        Write-Host "  Start Type:   $($StifleRService.StartType)" -ForegroundColor DarkGray
        $Global:StifleRServiceRunning = $true
    }
    else {
        Write-Host "2Pint StifleR Server service is NOT running." -ForegroundColor Red
        Write-Host " Attempting to start service..." -ForegroundColor Yellow
        Start-Service -Name '2Pint Software StifleR Server' -ErrorAction SilentlyContinue
        if ($?) {
            Write-Host "Service started successfully." -ForegroundColor Green
            Write-Host " Waiting for service to start additional processes..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
        else {
            Write-Host "Failed to start service." -ForegroundColor Red
        }
        $Global:StifleRServiceRunning = $false
    }
}
#Test DeployR Service
if ($Installed_2Pint_Software_DeployR){
    $DeployRService = Get-Service -Name '2Pint Software DeployR Service'
    if ($DeployRService.Status -eq 'Running') {
        Write-Host "2Pint DeployR service is running." -ForegroundColor Green
        Write-Host "  Display Name: $($DeployRService.DisplayName)" -ForegroundColor DarkGray
        Write-Host "  Service Name: $($DeployRService.Name)" -ForegroundColor DarkGray
        Write-Host "  Start Type:   $($DeployRService.StartType)" -ForegroundColor DarkGray
        $Global:DeployRServiceRunning = $true
    }
    else {
        Write-Host "2Pint DeployR service is NOT running." -ForegroundColor Red
        Write-Host " Attempting to start service..." -ForegroundColor Yellow
        Start-Service -Name '2Pint Software DeployR Service' -ErrorAction SilentlyContinue
        if ($?) {
            Write-Host "Service started successfully." -ForegroundColor Green
        }
        else {
            Write-Host "Failed to start service." -ForegroundColor Red
        }
        $Global:DeployRServiceRunning = $false
    }
}

#Confirm StifleR Registry Settings
if ($Installed_2Pint_Software_StifleR_Server){
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "Testing StifleR Registry Settings..." -ForegroundColor Cyan
    $StifleRRegPath = "HKLM:\SOFTWARE\2Pint Software\StifleR\Server\GeneralSettings"
    $StifleRRegData = Get-ItemProperty -Path $StifleRRegPath -ErrorAction SilentlyContinue
    
    #Note, this is no longer used in newer releases
    if ($StifleRRegData -and $StifleRRegData.DeployRUrl) {
        Write-Host "DeployR API URL: $($StifleRRegData.DeployRUrl)" -ForegroundColor Green
    }
    else {
        #Write-Host "DeployR API URL is NOT configured." -ForegroundColor Red
    }
    $StifleRCertThumbprint = $StifleRRegData.WSCertificateThumbprint
    Write-Host "StifleR Using Certificate with Thumbprint: $($StifleRCertThumbprint)" -ForegroundColor Cyan
    #Get Certificate from Local Machine Store that matches
    $CertThumbprint = Get-ChildItem -Path Cert:\LocalMachine\My  | Where-Object { $_.Thumbprint -match $StifleRCertThumbprint }
    if ($CertThumbprint) {
        Write-Host "Found certificate in local store: $($CertThumbprint.Thumbprint)" -ForegroundColor Green
        write-host " DNSNameList:    $($CertThumbprint.DNSNameList -join ', ')" -ForegroundColor DarkGray
        write-host " Subject:        $($CertThumbprint.Subject)" -ForegroundColor DarkGray
        write-host " Issuer:         $($CertThumbprint.Issuer)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "Certificate NOT found." -ForegroundColor Red
    }
    
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "Checking for StifleRDashboard Web Virtual Directory..." -ForegroundColor Cyan
    
    try {
        $vdir = Get-WebVirtualDirectory -Site "Default Web Site" -Name "StifleRDashboard" -ErrorAction SilentlyContinue
        if ($vdir) {
            Write-Host "✓ StifleRDashboard Web Virtual Directory exists in Default Web Site." -ForegroundColor Green
            Write-Host "  Physical Path: $($vdir.PhysicalPath)" -ForegroundColor DarkGray
        } else {
            Write-Host "✗ StifleRDashboard Web Virtual Directory is NOT present in Default Web Site." -ForegroundColor Red
            Write-Host "Remediation: Run the following command:" -ForegroundColor Yellow
            Write-Host "New-WebVirtualDirectory -Site 'Default Web Site' -Name 'StifleRDashboard' -PhysicalPath 'C:\Program Files\2Pint Software\StifleR Dashboards\Dashboard Files'" -ForegroundColor DarkGray
            $IISVirtualDirMissing = $true
        }
    } catch {
        Write-Host "Error checking for StifleRDashboard Web Virtual Directory: $_" -ForegroundColor Red
    }
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    
    Write-Host "Testing Dashboard Registry Settings for URLs" -ForegroundColor Cyan
    $DashReg = "HKLM:\SOFTWARE\2Pint Software\StifleR\Dashboard"
    $DashRegData = Get-ItemProperty -Path $DashReg -ErrorAction SilentlyContinue
    
    if ($DashRegData -and $DashRegData.HubUrl) {
        if ($($DashRegData.HubUrl) -match "localhost") {
            Write-Host " Hub URL is configured to use localhost." -ForegroundColor Red
        }
        else{
            Write-Host " Hub URL: $($DashRegData.HubUrl)" -ForegroundColor Green
        }
    }
    else {
        Write-Host " Hub URL is NOT configured." -ForegroundColor Red
    }
    
    if ($DashRegData -and $DashRegData.ServiceUrl) {
        if ($($DashRegData.ServiceUrl) -match "localhost") {
            Write-Host " Service URL is configured to use localhost." -ForegroundColor Red
        }
        else{
            Write-Host " Service URL: $($DashRegData.ServiceUrl)" -ForegroundColor Green
        }
    }
    else {
        Write-Host " Service URL is NOT configured." -ForegroundColor Red
    }
    Write-Host "Testing Dashboard Config Settings for URLs" -ForegroundColor Cyan
    if (Test-Path -Path "C:\Program Files\2Pint Software\StifleR Dashboards\Dashboard Files\assets\config\server.json") {
        Write-Host "  Server configuration file exists." -ForegroundColor Green
        $ServerConfigJSON = Get-Content -Path "C:\Program Files\2Pint Software\StifleR Dashboards\Dashboard Files\assets\config\server.json" -Raw | ConvertFrom-Json
        if ($ServerConfigJSON -and $ServerConfigJSON.server.hub) {
            if ($($ServerConfigJSON.server.hub) -match "localhost") {
                Write-Host "Hub URL is configured to use localhost." -ForegroundColor Red
            }
            else{
                Write-Host " Hub URL: $($ServerConfigJSON.server.hub)" -ForegroundColor Green
            }
        }
        else {
            Write-Host " Hub URL is NOT configured." -ForegroundColor Red
        }
        
        if ($ServerConfigJSON -and $ServerConfigJSON.server.controller) {
            if ($($ServerConfigJSON.server.controller) -match "localhost") {
                Write-Host " Service URL is configured to use localhost." -ForegroundColor Red
            }
            else{
                Write-Host " Service URL: $($ServerConfigJSON.server.controller)" -ForegroundColor Green
            }
        }
        else {
            Write-Host " Service URL is NOT configured." -ForegroundColor Red
        }
    }
    else {
        Write-Host " Server configuration file is missing." -ForegroundColor Red
    }
    #Check to ensure Registry Values match Config Values
    if ($DashRegData -and $ServerConfigJSON) {
        if ($DashRegData.HubUrl -ne $ServerConfigJSON.server.hub) {
            Write-Host " Hub URL in Registry does not match Config file." -ForegroundColor Red
        }
        if ($DashRegData.ServiceUrl -ne $ServerConfigJSON.server.controller) {
            Write-Host " Service URL in Registry does not match Config file." -ForegroundColor Red
        }
    }
}
Start-Sleep -Seconds 2

#Confirm DeployR Registry Settings
if ($Installed_2Pint_Software_DeployR){
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    
    $RegPath = "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"
    $DeployRRegData = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
    
    if ($DeployRRegData -and $DeployRRegData.ConnectionString) {
        Write-Host "Testing DeployR SQL Connection string from Registry... " -ForegroundColor Cyan
        write-host " $($DeployRRegData.ConnectionString)"
        Test-SQLConnection -ConnectionString $DeployRRegData.ConnectionString
    }
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "Testing DeployR Certificate..." -ForegroundColor Cyan
    #Test Certificate
    $CertThumbprintRegValue = $DeployRRegData.CertificateThumbprint
    Write-Host "DeployR Using Certificate with Thumbprint: $($CertThumbprintRegValue)" -ForegroundColor Cyan
    #Get Certificate from Local Machine Store that matches
    $CertThumbprint = Get-ChildItem -Path Cert:\LocalMachine\My  | Where-Object { $_.Thumbprint -match $CertThumbprintRegValue }
    if ($CertThumbprint) {
        Write-Host "Found certificate in local store: $($CertThumbprint.Thumbprint)" -ForegroundColor Green
    }
    else {
        Write-Host "Certificate NOT found." -ForegroundColor Red
    }
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    #Test StifleR Server URL
    Write-Host "Testing Network Connections..." -ForegroundColor Cyan
    #StifleR Server URL = $DeployRRegData.StifleRServerApiUrl without Port Number
    $StifleRServerURL = $DeployRRegData.StifleRServerApiUrl
    $StifleRServerURL = $StifleRServerURL.Split(':')[0..1] -join ':'
    $StifleRServerName = $StifleRServerURL.Split('/')[2]
    $DeployRURL = $DeployRRegData.ClientURL
    $DeployRURL = $DeployRURL.Split(':')[0..1] -join ':'
    $DeployRServerName = $DeployRURL.Split('/')[2]
    
    
    
    Write-Host "Testing StifleR Server URL... $($StifleRServerURL)" -ForegroundColor Cyan
    $StifleRTest = Test-Url -Url $StifleRServerURL
    if ($StifleRTest) {
        Write-Host "StifleR Server URL is accessible." -ForegroundColor Green
        $Test443 = Test-NetConnection -ComputerName $StifleRServerName -Port 443
        if ($Test443) {
            Write-Host "StifleR Server Port 443 is accessible." -ForegroundColor Green
        }
        $Test9000 = Test-NetConnection -ComputerName $StifleRServerName -Port 9000
        if ($Test9000) {
            Write-Host "StifleR Server Port 9000 is accessible." -ForegroundColor Green
        }
    }
    else {
        Write-Host "StifleR Server URL is NOT accessible." -ForegroundColor Red
    }
    Write-Host "Testing DeployR Server URL... $($DeployRURL)" -ForegroundColor Cyan
    $DeployRTest = Test-Url -Url $DeployRURL
    if ($DeployRTest) {
        
        
        
        $Test7281 = Test-NetConnection -ComputerName $DeployRServerName -Port 7281
        if ($Test7281) {
            Write-Host "DeployR Server Port 7281 is accessible." -ForegroundColor Green
        }
        $Test7282 = Test-NetConnection -ComputerName $DeployRServerName -Port 7282
        if ($Test7282) {
            Write-Host "DeployR Server Port 7282 is accessible." -ForegroundColor Green
        }
    }
    else {
        Write-Host "DeployR Server URL is NOT accessible." -ForegroundColor Red
    }
    
}
Write-Host "=========================================================================" -ForegroundColor DarkGray
write-host "Checking Certificate... on Ports 443 & 9000" -ForegroundColor Cyan
# Get the certificate hash from the HTTP.SYS binding for port 443
$certHash = netsh http show sslcert ipport=0.0.0.0:443 | Select-String "Certificate Hash" | ForEach-Object { ($_ -split ": ")[1].Trim() }

if ($certHash) {
    Write-Host  "Certificate Thumbprint for HTTPS (port 443): $certHash" -ForegroundColor Green
    if ($certHash -eq $CertThumbprintRegValue) {
        Write-Host "The certificate hash matches the DeployR configuration." -ForegroundColor Green
    }
    else {
        Write-Host "The certificate hash does NOT match the DeployR configuration." -ForegroundColor Red
    }
} else {
    Write-Host  "No SSL binding found for port 443. Trying all IPs..." -ForegroundColor Yellow
    # Fallback: Scan common IPs (adjust as needed)
    $ips = @("0.0.0.0", "*")  # Add specific IPs if known, e.g., "192.168.1.100"
    $found = $false
    foreach ($ip in $ips) {
        $hash = netsh http show sslcert ipport="$ip`:443" | Select-String "Certificate Hash" | ForEach-Object { ($_ -split ": ")[1].Trim() }
        if ($hash) {
            Write-Host "Certificate Thumbprint for HTTPS (port 443) on $ip`: $hash" -ForegroundColor Yellow
            $found = $true
            break
        }
    }
    if (-not $found) { Write-Host "No binding found." -ForegroundColor Red }
}
$certHash = netsh http show sslcert ipport=0.0.0.0:9000 | Select-String "Certificate Hash" | ForEach-Object { ($_ -split ": ")[1].Trim() }

if ($certHash) {
    Write-Host  "Certificate Thumbprint for HTTPS (port 9000): $certHash" -ForegroundColor Green
    if ($certHash -eq $CertThumbprintRegValue) {
        Write-Host "The certificate hash matches the DeployR configuration." -ForegroundColor Green
    }
    else {
        Write-Host "The certificate hash does NOT match the DeployR configuration." -ForegroundColor Red
    }
} else {
    Write-Host  "No SSL binding found for port 443. Trying all IPs..." -ForegroundColor Yellow
    # Fallback: Scan common IPs (adjust as needed)
    $ips = @("0.0.0.0", "*")  # Add specific IPs if known, e.g., "192.168.1.100"
    $found = $false
    foreach ($ip in $ips) {
        $hash = netsh http show sslcert ipport="$ip`:443" | Select-String "Certificate Hash" | ForEach-Object { ($_ -split ": ")[1].Trim() }
        if ($hash) {
            Write-Host "Certificate Thumbprint for HTTPS (port 443) on $ip`: $hash" -ForegroundColor Yellow
            $found = $true
            break
        }
    }
    if (-not $found) { Write-Host "No binding found." -ForegroundColor Red }
}
#Testing Firewall Rules:

Write-Host "=========================================================================" -ForegroundColor DarkGray
write-host "Checking Firewall Rules to ensure Ports are Open" -ForegroundColor Cyan
$Ports = Get-NetFirewallPortFilter
$InboundRules = Get-NetFirewallRule -Direction Inbound
foreach ($FirewallRule in $FirewallRules){
    Write-Host "Checking Firewall Rule: $($FirewallRule.DisplayName)" -ForegroundColor Yellow
    $RulePorts = $Ports | Where-Object { $_.LocalPort -eq $FirewallRule.Port -and $_.Protocol -eq $FirewallRule.Protocol } | Select-Object -first 1
    if ($RulePorts){
        foreach ($Port in $RulePorts){
            $NetFirewallRule = $InboundRules | Where-Object { $_.InstanceID -eq $Port.InstanceID }
            Write-Host " Found Firewall Rule: $($NetFirewallRule.DisplayName)" -ForegroundColor Green
            Write-Host "  Enabled: $($NetFirewallRule.Enabled) | Action:  $($NetFirewallRule.Action) | Profile: $($NetFirewallRule.Profile)" -ForegroundColor DarkGray
            Write-Host "  Port: $($Port.LocalPort) | Protocol: $($Port.Protocol)" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "No matching ports found for Firewall Rule: $($FirewallRule.DisplayName)" -ForegroundColor Red
    }
}

if ($Installed_2Pint_Software_StifleR_WmiAgent) {
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    write-host "Checking for StifleR Infrastructure Approval for DeployR" -ForegroundColor Cyan
    $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
    try {
        if ($InfraServices) {
            Write-Host "StifleR Infrastructure Services found." -ForegroundColor Green
        } else {
            Write-Host "No StifleR Infrastructure Services found." -ForegroundColor Red
        }
    } catch {
        Write-Host "Failed to retrieve StifleR Infrastructure Services." -ForegroundColor Red
        write-host "Waiting for a minute and going to try again..."
        Start-Sleep -seconds 10
        write-host " 50..."
        Start-Sleep -seconds 10
        write-Host " 40..."
        Start-Sleep -seconds 10
        write-host " 30..."
        Start-Sleep -seconds 10
        write-host " 20..."
        Start-Sleep -seconds 10
        write-host " 10..."
        Start-Sleep -seconds 10
        try {
            $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "Error occurred while retrieving StifleR Infrastructure Services." -ForegroundColor Red
        }
    }
    if (!$InfraServices) {
        
        Write-Host "Sometimes if the service just started, this can take a bit"
        write-host "Waiting for a minute and going to try again..."
        Start-Sleep -seconds 10
        $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
        write-host " 50..."
        Start-Sleep -seconds 10
        $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
        write-Host " 40..."
        Start-Sleep -seconds 10
        $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
        write-host " 30..."
        Start-Sleep -seconds 10
        $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
        write-host " 20..."
        Start-Sleep -seconds 10
        $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
        write-host " 10..."
        Start-Sleep -seconds 10
        $InfraServices = Get-CimInstance -ClassName "InfrastructureServices" -Namespace root\stifler -ErrorAction SilentlyContinue
    }
    if ($InfraServices) {
        $DeployR = $InfraServices | Where-Object {$_.Type -eq "DeployR"}
        if ($DeployR){
            Write-Host "StifleR Infrastructure for DeployR found." -ForegroundColor Green
            if ($DeployR.Status -eq "IsApproved") {
                Write-Host "DeployR Status: Approved" -ForegroundColor Green
            } else {
                Write-Host "DeployR Status: NOT Approved" -ForegroundColor Red
            }
        }
        else{
            Write-Host "No StifleR Infrastructure for DeployR found." -ForegroundColor Red
        }
    } else {
        Write-Host "StifleR Infrastructure Services are NOT available." -ForegroundColor Red
    }
}
#Remediation 
#prompt user to do installs
Write-Host "=========================================================================" -ForegroundColor DarkGray
if ($MissingComponents) {
    Write-Host "Would you like to install the missing Windows Features now? (Y/N): " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    if ($response -eq 'Y' -or $response -eq 'y') {
        Write-Host "Remediation: Run the following command to install missing Windows Features:" -ForegroundColor Yellow
        Write-Host "Add-WindowsFeature $($MissingComponents -join ', ')" -ForegroundColor DarkGray
    }
}
if ($IISVirtualDirMissing) {
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "Running Remediation for StifleRDashboard virtual directory"
    if (Test-Path -path "C:\Program Files\2Pint Software\StifleR Dashboards\Dashboard Files"){
        Write-Host "✓ StifleRDashboard directory exists." -ForegroundColor Green
    } else {
        Write-Host "✗ StifleRDashboard directory is missing." -ForegroundColor Red
    }
    Write-Host "Would you like to create the StifleRDashboard virtual directory now? (Y/N): " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    if ($response -eq 'Y' -or $response -eq 'y') {
        try {
            New-WebVirtualDirectory -Site 'Default Web Site' -Name 'StifleRDashboard' -PhysicalPath 'C:\Program Files\2Pint Software\StifleR Dashboards\Dashboard Files' -ErrorAction Stop
            Write-Host "✓ StifleRDashboard virtual directory created successfully." -ForegroundColor Green
        } catch {
            Write-Host "✗ Failed to create virtual directory: $_" -ForegroundColor Red
            Write-Host "Please run the command manually with elevated permissions." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Skipping virtual directory creation." -ForegroundColor DarkGray
    }
}
if ($IISMimeTypeUpdateRequired) {
    Write-Host "=========================================================================" -ForegroundColor DarkGray
    Write-Host "Would you like to add the missing IIS MIME types now? (Y/N): " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    if ($response -eq 'Y' -or $response -eq 'y') {
        Write-Host "Adding missing IIS MIME types..." -ForegroundColor Yellow
        #Set the MIME types for the iPXE boot files, etc. 
        Import-Module WebAdministration
        #EFI loader files  
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.efi';mimeType='application/octet-stream'}  
        #BIOS boot loaders  
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.com';mimeType='application/octet-stream'}  
        #BIOS loaders without F12 key press  
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.n12';mimeType='application/octet-stream'}  
        #For the boot.sdi file  
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.sdi';mimeType='application/octet-stream'}  
        #For the boot.bcd boot configuration files  & BCD file (with no extension)
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.bcd';mimeType='application/octet-stream'}
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.';mimeType='application/octet-stream'}   
        #For the winpe images itself (already added on newer/patched versions of Windows Server
        #Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.wim';mimeType='application/octet-stream'}  
        #for the iPXE BIOS loader files  
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.pxe';mimeType='application/octet-stream'}  
        #For the UNDIonly version of iPXE  
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.kpxe';mimeType='application/octet-stream'}  
        #For the .iso file type
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.iso';mimeType='application/octet-stream'}  
        #For the .img file type
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.img';mimeType='application/octet-stream'}  
        #For the .ipxe file 
        Add-WebConfigurationProperty //staticContent -name collection -value @{fileExtension='.ipxe';mimeType='text/plain'}
        Write-Host "✓ Missing IIS MIME types added successfully." -ForegroundColor Green
    }
}

Stop-Transcript