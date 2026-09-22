<#  2Pintlabs FrontEnd-JSONBasedDynamic.ps1
    This is community, no official support

    Change Log: 
    26.7.6 - Added Checkbox for P2P Enablement to allow user to choose if they want to enable P2P for the rest of the task sequence
        - It will default what the peering variable is already set to, but user can uncheck if they do not want to enable P2P


#>
[CmdletBinding()]
param(
    [string]$AvaloniaPath
)

$ScriptVersion = '26.7.6.8.55'


#Region Functions
# Helper function to stop transcription
function Stop-FrontendTranscription {
    try {
        if ($Global:FrontendTranscriptStarted -and (Get-Command Stop-Transcript -ErrorAction SilentlyContinue)) {
            Stop-Transcript -ErrorAction SilentlyContinue
            $Global:FrontendTranscriptStarted = $false
            Write-CMTraceLog -Message "Stopped PowerShell transcription" -Type "Info" -Component "Main"
        }
    } catch {}
}

Function Get-InputFormData {
    
    <#
.SYNOPSIS
    Creates an Avalonia form to collect user input including computer naming strategy and user role selection.
    
.DESCRIPTION
    This script displays an Avalonia form with:
    - Radio buttons to select computer naming strategy:
    * Do not set computer name
    * Use custom computer name (manual entry, max 15 characters)
    * Use hardware-based name (prefix + serial number or MAC address)
    - A dropdown list for selecting user role from predefined options
    
    The form returns a PSObject with the user's selections.
    
.EXAMPLE
    $result = .\New-InputForm.ps1
    if ($result.FormSubmitted) {
    Write-Host "Naming Strategy: $($result.NamingStrategy)"
    Write-Host "Generated Name: $($result.GeneratedComputerName)"
    Write-Host "User Role: $($result.SelectedUserRole)"
    }
    
.NOTES
    Author: Created for 2PintLabs by Gary Blok
    Date: October 20, 2025
    #>
    
    # Load the Avalonia assemblies shipped with the DeployR client.
    $deployRoot = ${TSEnv:DEPLOYRROOT}
    if ([string]::IsNullOrWhiteSpace($AvaloniaPath)) {
        $AvaloniaPath = if ($deployRoot) { Join-Path $deployRoot 'Client' } else { $null }
    }
    $avaloniaPath = $AvaloniaPath
    if (-not $avaloniaPath -or -not (Test-Path (Join-Path $avaloniaPath 'Avalonia.Base.dll'))) {
        $avaloniaPath = Join-Path ${env:ProgramFiles} '2Pint Software\DeployR\Client'
    }
    $avaloniaAssemblies = @(
        'Avalonia.Base.dll', 'Avalonia.dll', 'Avalonia.Controls.dll',
        'Avalonia.Desktop.dll', 'Avalonia.Dialogs.dll', 'Avalonia.Markup.dll',
        'Avalonia.Markup.Xaml.dll', 'Avalonia.Markup.Xaml.Loader.dll',
        'Avalonia.Metal.dll', 'Avalonia.MicroCom.dll', 'Avalonia.OpenGL.dll',
        'Avalonia.Remote.Protocol.dll', 'Avalonia.Skia.dll',
        'Avalonia.Themes.Fluent.dll', 'Avalonia.Vulkan.dll', 'Avalonia.Win32.dll',
        'SkiaSharp.dll', 'HarfBuzzSharp.dll', 'MicroCom.Runtime.dll'
    )
    $nativePath = if ([Environment]::Is64BitProcess) {
        Join-Path $avaloniaPath 'runtimes\win-x64\native'
    } else {
        Join-Path $avaloniaPath 'runtimes\win-x86\native'
    }
    $runtimePaths = @($avaloniaPath)
    if (Test-Path $nativePath) { $runtimePaths += $nativePath }
    $env:PATH = (($runtimePaths -join ';') + ";$env:PATH")
    foreach ($assemblyName in $avaloniaAssemblies) {
        $assemblyPath = Join-Path $avaloniaPath $assemblyName
        if (Test-Path $assemblyPath) {
            try { [System.Reflection.Assembly]::LoadFrom($assemblyPath) | Out-Null } catch {}
        }
    }
    if (-not ([System.Management.Automation.PSTypeName]'Avalonia.AppBuilder').Type) {
        throw "Avalonia assemblies were not found in '$avaloniaPath'. Install the DeployR Avalonia client files first."
    }
    $avaloniaBuilder = [Avalonia.AppBuilder]::Configure[Avalonia.Application]()
    [Avalonia.AppBuilderDesktopExtensions]::UsePlatformDetect($avaloniaBuilder)
    $avaloniaBuilder.SetupWithoutStarting() | Out-Null
    [Avalonia.Application]::Current.Styles.Add([Avalonia.Themes.Fluent.FluentTheme]::new())
    
    
    # If no explicit LogoPath was provided earlier, try to use Logo-blue.png located
    # in the same directory as this script.
    # Resolve script directory robustly to support dot-sourcing and different PowerShell hosts
    $scriptDir = $null
    if ((Get-Module -name "DeployR.Utility") -and (-not (test-path -path "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"))) {
        $scriptDir = ${TSEnv:_CONTENT-CONTENT}
        Write-Host "Resolved script directory via TS Var _CONTENT-CONTENT: $scriptDir" -ForegroundColor Cyan
    }
    if (-not $scriptDir){
        try { $scriptDir = $PSScriptRoot } catch {}
        if (-not $scriptDir) {
            try {
                if ($PSCommandPath) { $scriptDir = Split-Path -Parent $PSCommandPath }
                elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Definition) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
                elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
                else { $scriptDir = (Get-Location).Path }
            }
            catch{}
        }
        if (-not $scriptDir){ $scriptDir = (Get-Location).Path }
        Write-Host "Resolved script directory via fallback methods: $scriptDir" -ForegroundColor Cyan
    }
    
    # Load FrontEndConfig.json from the script directory into $JSONConfig
    $JSONFallbackConfigURL = 'https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/FrontEnd/FrontEndJSONDrivenDynamicAppsAvalonia/FrontEndConfig.json'
    $JSONConfig = $null
    try {
        if ($scriptDir) {
            Write-Host "Attempting to load FrontEndConfig.json from script directory: $scriptDir" -ForegroundColor Cyan
            $configPath = Join-Path -Path $scriptDir -ChildPath 'FrontEndConfig.json'
            if (Test-Path -Path $configPath) {
                Write-Host "Found FrontEndConfig.json at $configPath" -ForegroundColor Green
                $JSONConfig = Get-Content -Path $configPath -Raw | ConvertFrom-Json -ErrorAction Stop
                try { Write-CMTraceLog -Message "Loaded FrontEndConfig.json from $configPath" -Type "Info" -Component "Config" } catch {}
            }
        }
        $configPath = Join-Path -Path $scriptDir -ChildPath 'FrontEndConfig.json' -ErrorAction SilentlyContinue
        
        if (-not $JSONConfig) {
            Write-Verbose "FrontEndConfig.json not found at $configPath"
            try { Write-CMTraceLog -Message "FrontEndConfig.json not found at $configPath" -Type "Warning" -Component "Config" } catch {}
            # Attempt to load JSON config from fallback URL. Use Invoke-RestMethod first
            # (it returns a parsed object). If that fails, fetch raw content and
            # ConvertFrom-Json explicitly.
            try {
                Write-Host "Attempting to load FrontEndConfig.json from fallback URL: $JSONFallbackConfigURL" -ForegroundColor Cyan
                try {
                    $JSONConfig = Invoke-RestMethod -Uri $JSONFallbackConfigURL -ErrorAction Stop
                } catch {
                    # Fallback to raw content parsing
                    $content = (Invoke-WebRequest -Uri $JSONFallbackConfigURL -ErrorAction Stop).Content
                    $JSONConfig = $content | ConvertFrom-Json -ErrorAction Stop
                }
                Write-Host "Successfully loaded FrontEndConfig.json from fallback URL" -ForegroundColor Green
                try { Write-CMTraceLog -Message "Loaded FrontEndConfig.json from fallback URL: $JSONFallbackConfigURL" -Type "Info" -Component "Config" } catch {}
            } catch {
                Write-Warning "Failed to load FrontEndConfig.json from fallback URL: $_"
                try { Write-CMTraceLog -Message "Failed to load FrontEndConfig.json from fallback URL: $_" -Type "Warning" -Component "Config" } catch {}
            }
        }
    }
    catch {
        Write-Warning "Failed to load or parse FrontEndConfig.json: $_"
        try { Write-CMTraceLog -Message "Failed to load or parse FrontEndConfig.json: $_" -Type "Warning" -Component "Config" } catch {}
    }
    ###########################################
    #Build Data from JSON
    ##########################################
    
    #Usage (DeployR or ConfigMgr)
    $Usage = $JSONConfig.Usage
    if (-not $Usage) { $Usage = "DeployR" }  # Default to DeployR if not specified
    
    ###########################################
    #Build Data from JSON
    ##########################################
    
    #Usage (DeployR or ConfigMgr)
    $Usage = $JSONConfig.Usage
    if (-not $Usage) { $Usage = "DeployR" }  # Default to DeployR if not specified
    
    #Logo File Name
    $LogoFileName = $JSONConfig.LogoFileName
    if (-not (Get-Variable -Name LogoPath -ErrorAction SilentlyContinue)) {
        $LogoPath = $null
    }
    write-host "Logo file name from JSON config: $LogoFileName" -ForegroundColor Cyan
    try {
        if ([string]::IsNullOrWhiteSpace($LogoPath) -and (Test-Path $scriptDir)) {
            $possibleLogo = Join-Path -Path $scriptDir -ChildPath $LogoFileName
            if (Test-Path -Path $possibleLogo) { 
                $LogoPath = $possibleLogo 
                Write-Host "Using logo image at $LogoPath" -ForegroundColor Green
            }
        }

        if ([string]::IsNullOrWhiteSpace($LogoPath)) {
            #Download Default Logo from GitHub and save to temp path
            $2PintLogoDefaultURL = 'https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/FrontEnd/FrontEndJSONDriven/Logo.png'
            $tempLogoPath = Join-Path -Path $env:TEMP -ChildPath $LogoFileName
            Write-Host "Downloading default logo from $2PintLogoDefaultURL to $tempLogoPath" -ForegroundColor Cyan
            try {
                Invoke-WebRequest -Uri $2PintLogoDefaultURL -OutFile $tempLogoPath -ErrorAction Stop
                if (Test-Path -Path $tempLogoPath) {
                    $LogoPath = $tempLogoPath
                    Write-Host "Successfully downloaded default logo to $LogoPath" -ForegroundColor Green
                }
                else {
                    Write-Warning "Failed to download default logo to $tempLogoPath"
                }
            }
            catch {
                Write-Warning "Error downloading default logo $_"
            }
        }
        
    } catch {}
    
    #Default Domain Suffix
    $DefaultDomainSuffix = $JSONConfig.DomainSuffix
    
    #OU Options
    $OUOptions = @()
    $JSONConfig.OUs | ForEach-Object {
        $OUOptions += $_
    }
    
    #Autopilot Group Tags
    $AutopilotGroupTagOptions = @()
    $JSONConfig.AutopilotGroupTags | ForEach-Object {
        $AutopilotGroupTagOptions += $_
    }
    
    #Role Options
    $RoleOptions = @()
    $JSONConfig.Roles | ForEach-Object {
        $RoleOptions += $_
    }
    
    # Software options - try to pull dynamically from DeployR, fall back to static list if unavailable
    # Try to get apps dynamically from DeployR
    $UseDeployRSoftwareList = $JSONConfig.SoftwareFromDeployR
    $SoftwareTagForDeployR = $JSONConfig.SoftwareFromDeployRTag
    $SoftwareOptions = $null
    $DeployRRetrievalFailed = $false
    
    # Only attempt DeployR retrieval if explicitly enabled in JSON config
    if ($UseDeployRSoftwareList -eq "True") {
        Write-Host "Attempting to retrieve software list from DeployR..." -ForegroundColor Cyan
        try {
            # Call the function that's defined later in this script
            $script:DeployRApps = Get-DeployRFrontEndApps -Tag $SoftwareTagForDeployR -ErrorAction Stop
            
            if ($script:DeployRApps -and $script:DeployRApps.Count -gt 0) {
                Write-Host "Successfully retrieved $($script:DeployRApps.Count) apps from DeployR" -ForegroundColor Green
                # Build PSObject array with DisplayName and Id (Id = name without spaces)
                $SoftwareOptions = @()
                foreach ($app in $script:DeployRApps) {
                    $SoftwareOptions += [PSCustomObject]@{
                        DisplayName = $app.Name
                        Id = $app.Id  
                        AppID = $app.Id
                    }
                }
            }
            else {
                # DeployR call succeeded but returned no apps
                $DeployRRetrievalFailed = $true
            }
        }
        catch {
            $msg = "Could not retrieve apps from DeployR: $($_.Exception.Message)"
            Write-Warning $msg
            try { Write-CMTraceLog -Message $msg -Type "Warning" -Component "DeployR" } catch {}
            $DeployRRetrievalFailed = $true
        }
    }
    else {
        Write-Host "DeployR software retrieval disabled in config - using static list from JSON" -ForegroundColor Cyan
    }
    
    # Fall back to static list if:
    # 1. DeployR was not enabled, OR
    # 2. DeployR retrieval was attempted but failed
    if (-not $SoftwareOptions -or $SoftwareOptions.Count -eq 0) {
        $msg = "Using static software list from JSON config"
        Write-Host $msg -ForegroundColor Yellow
        try { Write-CMTraceLog -Message $msg -Type "Info" -Component "Software" } catch {}
        $SoftwareOptions = @()
        $JSONConfig.Software | ForEach-Object {
            $SoftwareOptions += [PSCustomObject]@{
                DisplayName = $_.DisplayName
                Id = $_.Id
            }
        }
    }
    
    # Define hardware ID type options (If you change this, you'll need to also update methods to gather this info)
    $HardwareIdOptions = @(
    "Serial Number",
    "MAC Address",
    "Asset Tag"
    )
    
    #Region Collection Hardware Information:
    
    $LocalInfo = @{}		
    $LocalInfo['IsDesktop'] = "False"
    $LocalInfo['IsLaptop'] = "False"
    $LocalInfo['IsServer'] = "False"
    $LocalInfo['IsSFF'] = "False"
    $LocalInfo['IsTablet'] = "False"
    Get-CimInstance -ClassName Win32_SystemEnclosure | ForEach-Object {
        if ($_.ChassisTypes[0] -in "8", "9", "10", "11", "12", "14", "18", "21") { $LocalInfo['IsLaptop'] = "True"; $LocalInfo['Chassis'] = "Laptop"}
        if ($_.ChassisTypes[0] -in "3", "4", "5", "6", "7", "15", "16") { $LocalInfo['IsDesktop'] = "True"; $LocalInfo['Chassis'] = "Desktop"}
        if ($_.ChassisTypes[0] -in "23") { $LocalInfo['IsServer'] = "True"; $LocalInfo['Chassis'] = "Server"}
        if ($_.ChassisTypes[0] -in "34", "35", "36") { $LocalInfo['IsSFF'] = "True"; $LocalInfo['Chassis'] = "Small Form Factor"}
        if ($_.ChassisTypes[0] -in "13", "31", "32", "30") {$LocalInfo['IsTablet'] = "True"; $LocalInfo['Chassis'] = "Tablet"}
    }
    # Chassis info collected into LocalInfo if needed
    
    $macList = @()
    Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 1" | ForEach-Object {
        $_.MacAddress | ForEach-Object { $macList += $_ }
    }
    $ipList = @()
    Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 1" | ForEach-Object {
        $_.IPAddress | ForEach-Object { $ipList += $_ }
        
    }
    $gwList = @()
    Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 1" | ForEach-Object {
        if ($_.DefaultIPGateway) {
            $_.DefaultIPGateway | ForEach-Object { $gwList += $_ }
        }
    }
    $SerialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
    #Round Memory to Nearest GB
    $Memory = [math]::Round((Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1024 / 1024 / 1024) 
    
    $LocalInfo = @{}
    $LocalInfo['Make'] = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer.Trim()	
    $LocalInfo['IsVM'] = "False"
    Switch -Wildcard ($LocalInfo['Make']) {
        "*Microsoft*" {
            $LocalInfo['MakeAlias'] = "Microsoft"
            $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
            $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemSKU
            # Logic for Hyper-V Testing
            If ($LocalInfo['ModelAlias'] -eq "Virtual Machine") {
                $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemVersion
                $LocalInfo['IsVM'] = "True"
            }
        }
        "*HP*" {
            $LocalInfo['MakeAlias'] = "HP"
            $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
            $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi).BaseBoardProduct.Trim()
        }
        "*VMWare*" {
            $LocalInfo['MakeAlias'] = "VMWare"
            # $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim() # Default, sets alias to same as model
            # $LocalInfo['ModelAlias'] = ((Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()).replace(",","_") # Remove the "," and replace with "_"
            $LocalInfo['ModelAlias'] = ((Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()).replace(" ","_").replace(",","_") # Remove the "," and replace with "_", Remove the " " and replace with "_"
            
            $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemSKU
            $LocalInfo['IsVM'] = "True"
        }
        "*QEMU*" {
            $LocalInfo['MakeAlias'] = "QEMU"
            $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
            $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemSKU
            $LocalInfo['IsVM'] = "True"
        }
        "*Innotek*" {
            $LocalInfo['MakeAlias'] = "Innotek"
            $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
            $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemSKU
            $LocalInfo['IsVM'] = "True"
        }
        "*Hewlett-Packard*" {
            $LocalInfo['MakeAlias'] = "HP"
            $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
            $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi).BaseBoardProduct.Trim()
        }
        "*Dell*" {
            $LocalInfo['MakeAlias'] = "Dell"
            $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
            $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi ).SystemSku.Trim()
        }
        "*Lenovo*" {
            $LocalInfo['MakeAlias'] = "Lenovo"
            $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version).Trim()
            $LocalInfo['SystemAlias'] = ((Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).SubString(0, 4)).Trim()
        }
        "*Intel(R) Client Systems*" {
            $LocalInfo['MakeAlias'] = "Intel(R) Client Systems"
            $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version).Trim()
            $LocalInfo['SystemAlias'] = ((Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim())
            $LocalInfo['SystemAlias'] = $LocalInfo['SystemAlias'].SubString(0, $LocalInfo['SystemAlias'].IndexOf("i")).Trim()
        }
        "*Panasonic*" {
            $LocalInfo['MakeAlias'] = "Panasonic Corporation"
            $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
            $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi ).BaseBoardProduct.Trim()
        }
        "*Viglen*" {
            $LocalInfo['MakeAlias'] = "Viglen"
            $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
            $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -ExpandProperty SKU).Trim()
        }
        "*AZW*" {
            $LocalInfo['MakeAlias'] = "AZW"
            $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
            $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi ).BaseBoardProduct.Trim()
        }
        "*Fujitsu*" {
            $LocalInfo['MakeAlias'] = "Fujitsu"
            $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
            $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -ExpandProperty SKU).Trim()
        }
        Default {
            $LocalInfo['MakeAlias'] = "NA"
            $LocalInfo['ModelAlias'] = "NA"
            $LocalInfo['SystemAlias'] = "NA"
        }
        # Closing for switch block
    }
    $MakeAlias = $LocalInfo['MakeAlias']
    $ModelAlias = $LocalInfo['ModelAlias']
    $SystemAlias = $LocalInfo['SystemAlias']
    $AssetTag = (Get-CimInstance -ClassName Win32_SystemEnclosure).SMBIOSAssetTag.Trim()
    
    
    
    
    # Function to get hardware information
    function Get-HardwareId {
        param(
        [string]$Type
        )
        
        try {
            if ($Type -eq "Serial Number") {
                $serial = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
                return $serial
            }
            elseif ($Type -eq "MAC Address") {
                $mac = (Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction SilentlyContinue | 
                Where-Object { $_.PhysicalAdapter -and $_.MACAddress } | 
                Select-Object -First 1).MACAddress
                # Remove colons and dashes from MAC address
                if ($mac) {
                    return $mac -replace '[:-]', ''
                }
            }
            elseif ($Type -eq "Asset Tag") {
                try {
                    $assetObj = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($assetObj -and $assetObj.SMBIOSAssetTag -and -not [string]::IsNullOrWhiteSpace($assetObj.SMBIOSAssetTag)) {
                        return $assetObj.SMBIOSAssetTag.Trim()
                    }
                }
                catch {
                    # ignore and fall through to UNKNOWN
                }
            }
        }
        catch {
            return "UNKNOWN"
        }
        return "UNKNOWN"
    }
    #endregion Hardware 
    
    # Build dynamic UI strings based on Usage
    $WindowTitle = "System Configuration - $Usage OSD"
    $HeaderText = "System Configuration - $Usage"
    $DomainSuffixLabel = if ($Usage -eq "ConfigMgr") { "Domain Suffix, used as Domain for Domain Join:" } else { "Domain Suffix (optional):" }
    $DomainJoinRadioLabel = if ($Usage -eq "ConfigMgr") { "Domain Join" } else { "Offline Domain Join" }
    
    # XAML Form Definition
    [xml]$XAML = @"
<Window xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="$WindowTitle" 
    Height="820" 
        Width="900"
        MinHeight="650"
        MinWidth="820"
        WindowStartupLocation="CenterScreen"
    Topmost="True"
        CanResize="True">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Logo above the tabs -->
        <DockPanel Grid.Row="0">
            <Image Name="imgLogo"
                   Stretch="Uniform"
                   MaxHeight="90"
                   Margin="0,0,0,15"
                   HorizontalAlignment="Center"
                   DockPanel.Dock="Top"/>
            <!-- Tabs for content -->
            <TabControl Margin="0,0,0,10"
                        HorizontalContentAlignment="Stretch"
                        VerticalContentAlignment="Stretch">
                <TabControl.ItemsPanel>
                    <ItemsPanelTemplate>
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" />
                    </ItemsPanelTemplate>
                </TabControl.ItemsPanel>
            <TabItem Header="General">
                <!-- ScrollViewer for main content -->
                <ScrollViewer VerticalScrollBarVisibility="Auto" 
                              HorizontalScrollBarVisibility="Disabled"
                              Margin="0,0,0,10"
                              Padding="0,0,10,0">
                    <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Border Grid.Row="0"
                        Height="2"
                        Background="#FF1688D4"
                        HorizontalAlignment="Stretch"
                        Margin="0,0,0,12"/>
                
                <!-- Header -->
                <TextBlock Grid.Row="1" 
                           Text="$HeaderText" 
                           FontSize="18" 
                           FontWeight="Bold" 
                           Margin="0,0,0,15"/>
                
                <!-- Computer Naming Strategy Section -->
                <GroupBox Grid.Row="2" Header="Computer Naming Strategy" FontSize="13" FontWeight="Bold" Margin="0,0,0,15" Padding="10">
            <StackPanel>
                <!-- Radio Button 1: No Name -->
                <RadioButton Name="rbNoName" 
                             Content="Do not set computer name" 
                             FontSize="12" 
                             FontWeight="Normal"
                             GroupName="NamingStrategy"
                             IsChecked="True"
                             Margin="0,5,0,10"/>
                
                <!-- Radio Button 2: Manual Name -->
                <RadioButton Name="rbManualName" 
                             Content="Use custom computer name:" 
                             FontSize="12" 
                             FontWeight="Normal"
                             GroupName="NamingStrategy"
                             Margin="0,0,0,5"/>
                <TextBox Name="txtManualName" 
                         Height="25" 
                         FontSize="12"
                         MaxLength="15"
                         Margin="25,0,0,10"
                         IsEnabled="False"/>
                
                <!-- Radio Button 3: Hardware-Based Name -->
                <RadioButton Name="rbHardwareName" 
                             Content="Use hardware-based name:" 
                             FontSize="12" 
                             FontWeight="Normal"
                             GroupName="NamingStrategy"
                             Margin="0,0,0,5"/>
                <StackPanel Margin="25,0,0,5">
                    <TextBlock Name="lblPrefix" Text="Prefix (optional, max 10 chars):" 
                               FontSize="11" 
                               Margin="0,0,0,3"/>
                    <TextBox Name="txtPrefix" 
                             Height="25" 
                             FontSize="12"
                             MaxLength="10"
                             IsEnabled="False"/>
                </StackPanel>
                <StackPanel Margin="25,5,0,5">
                    <TextBlock Name="lblHardwareIdType" Text="Hardware ID Type:" 
                               FontSize="11" 
                               Margin="0,0,0,3"/>
                    <ComboBox Name="cmbHardwareId" 
                              Height="25" 
                              FontSize="12"
                              IsEnabled="False"/>
                </StackPanel>
                
                <!-- Domain Suffix -->
                <StackPanel Margin="0,5,0,10">
                    <TextBlock Text="$DomainSuffixLabel" 
                               FontSize="11" 
                               Margin="0,0,0,3"/>
                    <TextBox Name="txtDomainSuffix" 
                             Height="25" 
                             FontSize="12"
                             ToolTip.Tip="Optional: Enter domain suffix (e.g., contoso.local) to display full FQDN in preview"/>
                </StackPanel>
                
                <!-- Preview -->
                <Border BorderBrush="LightGray" BorderThickness="1" Background="#F5F5F5" Padding="8" Margin="0,5,0,0">
                    <StackPanel>
                        <TextBlock Text="Computer Name Preview:" 
                                   FontSize="11" 
                                   FontWeight="Bold"
                                   Foreground="#FF202020"
                                   Margin="0,0,0,3"/>
                        <TextBlock Name="txtPreview" 
                                   Text="(Not set)" 
                                   FontSize="12"
                                   FontFamily="Consolas"
                                   Foreground="DarkBlue"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </GroupBox>
        
        <!-- Workplace Join has been moved to its own tab (see below) -->
        
                <!-- User Role dropdown moved to the 'Roles' tab to avoid duplicate UI in General -->
                
                <!-- Status TextBlock (moved to bottom bar so it's always visible) -->
            </Grid>
                </ScrollViewer>
            </TabItem>
    
            <TabItem Header="Workplace Join">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8">
                    <StackPanel Margin="0,6,0,0">
                        <Border Height="2" Background="#FF1688D4" HorizontalAlignment="Stretch" Margin="0,0,0,12"/>
                        <GroupBox Header="Workplace Join" FontSize="13" FontWeight="Bold" Margin="0,0,0,15" Padding="10">
                            <StackPanel>
                                <RadioButton Name="rbWorkgroup" 
                                             Content="Local Workgroup" 
                                             FontSize="12" 
                                             FontWeight="Normal"
                                             GroupName="WorkplaceJoin"
                                             IsChecked="True"
                                             Margin="0,5,0,8"/>
                                
                                <RadioButton Name="rbEntraID" 
                                             Content="EntraID Join" 
                                             FontSize="12" 
                                             FontWeight="Normal"
                                             GroupName="WorkplaceJoin"
                                             Margin="0,0,0,8"/>
                                
                                <!-- Primary User UPN field (shown when EntraID is selected) -->
                                <StackPanel Name="spEntraIDOptions" IsVisible="False" Margin="20,0,0,8">
                                    <TextBlock Text="Primary User UPN:" FontSize="11" Margin="0,0,0,3"/>
                                    <TextBox Name="txtPrimaryUserUPN" Height="24" FontSize="11"/>
                                </StackPanel>
                                
                                <RadioButton Name="rbAutopilot" 
                                             Content="Autopilot Registration" 
                                             FontSize="12" 
                                             FontWeight="Normal"
                                             GroupName="WorkplaceJoin"
                                             Margin="0,0,0,8"/>
                                
                                <!-- Online Domain Join option removed -->
                                
                                <RadioButton Name="rbDomainJoin" 
                                             Content="$DomainJoinRadioLabel" 
                                             FontSize="12" 
                                             FontWeight="Normal"
                                             GroupName="WorkplaceJoin"
                                             Margin="0,0,0,5"/>
                            </StackPanel>
                        </GroupBox>
    
                        <!-- Autopilot Group Tag Dropdown (moved here) -->
                        <TextBlock Name="txtAutopilotLabel" Text="Autopilot Group Tag:" 
                                   FontSize="13" 
                                   FontWeight="Bold"
                                   Margin="0,0,0,5"/>
                        <ComboBox Name="cmbAutopilotGroupTag"
                                  Height="28"
                                  FontSize="12"/>
    
                        <!-- Domain Join OU Dropdown (shown when Online or Offline Domain Join selected) -->
                        <TextBlock Name="txtOptionOULabel" Text="Domain Join OU:" 
                                   FontSize="13" 
                                   FontWeight="Bold"
                                   Margin="0,10,0,5"
                                   IsVisible="False"/>
                        <ComboBox Name="cmbOptionOU"
                                  Height="28"
                                  FontSize="12"
                                  IsVisible="False"/>
    
                        <!-- Finish Action GroupBox -->
                        <GroupBox Header="Finish Action" FontSize="13" FontWeight="Bold" Margin="0,15,0,0" Padding="10">
                            <StackPanel>
                                <TextBlock Text="Select finish action:" FontSize="11" Margin="0,0,0,5"/>
                                <ComboBox Name="cmbFinishAction" Height="28" FontSize="12"/>
                            </StackPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
    
            <TabItem Header="Roles">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8">
                    <StackPanel Margin="0,6,0,0">
                        <Border Height="2" Background="#FF1688D4" HorizontalAlignment="Stretch" Margin="0,0,0,12"/>
                        <TextBlock Text="Select User's Role:" FontSize="13" FontWeight="Bold" Margin="0,0,0,5" />
                        <ComboBox Name="cmbUserRole" Height="28" FontSize="12"/>
                        <TextBlock Name="txtRoleSource" Text="" FontSize="10" Foreground="Gray" Margin="0,8,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
    
            <TabItem Header="Software">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8">
                    <StackPanel Margin="0,6,0,0">
                        <Border Height="2" Background="#FF1688D4" HorizontalAlignment="Stretch" Margin="0,0,0,12"/>
                        <TextBlock Text="Select software to install:" FontSize="13" FontWeight="Bold" Margin="0,0,0,8"/>
                        <!-- Dynamic software list populated from SoftwareList.json -->
                                <StackPanel Name="spSoftwareList" Margin="6,4,0,0" />
                                <!-- Warning displayed when dynamic retrieval fails and static list is used -->
                                <TextBlock Name="txtSoftwareFallback" Text="" FontSize="11" Foreground="OrangeRed" IsVisible="False" Margin="6,8,0,0" TextWrapping="Wrap"/>
                                <TextBlock Name="txtSoftwareTagInfo" Text="" FontSize="11" Foreground="Gray" Margin="6,10,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
    
            <TabItem Header="Hardware">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8">
                    <StackPanel Margin="0,6,0,0">
                        <Border Height="2" Background="#FF1688D4" HorizontalAlignment="Stretch" Margin="0,0,0,12"/>
                        <TextBlock Text="Hardware Information" FontSize="13" FontWeight="Bold" Margin="0,0,0,12"/>
                        
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="140"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            
                            <!-- Make -->
                            <TextBlock Grid.Row="0" Grid.Column="0" Text="Make:" FontWeight="Bold" Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="0" Grid.Column="1" Name="txtHwMake" Text="" Margin="0,0,0,8" TextWrapping="Wrap"/>
                            
                            <!-- Model -->
                            <TextBlock Grid.Row="1" Grid.Column="0" Text="Model:" FontWeight="Bold" Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="1" Grid.Column="1" Name="txtHwModel" Text="" Margin="0,0,0,8" TextWrapping="Wrap"/>
                            
                            <!-- System -->
                            <TextBlock Grid.Row="2" Grid.Column="0" Text="System:" FontWeight="Bold" Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2" Grid.Column="1" Name="txtHwSystem" Text="" Margin="0,0,0,8" TextWrapping="Wrap"/>
                            
                            <!-- Serial Number -->
                            <TextBlock Grid.Row="3" Grid.Column="0" Text="Serial Number:" FontWeight="Bold" Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="3" Grid.Column="1" Name="txtHwSerial" Text="" Margin="0,0,0,8" TextWrapping="Wrap"/>
                            
                            <!-- Memory -->
                            <TextBlock Grid.Row="4" Grid.Column="0" Text="Memory:" FontWeight="Bold" Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="4" Grid.Column="1" Name="txtHwMemory" Text="" Margin="0,0,0,8" TextWrapping="Wrap"/>
                            
                            <!-- MAC List -->
                            <TextBlock Grid.Row="5" Grid.Column="0" Text="MAC Address(es):" FontWeight="Bold" Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="5" Grid.Column="1" Name="txtHwMacList" Text="" Margin="0,0,0,8" TextWrapping="Wrap"/>
                            
                            <!-- IP List -->
                            <TextBlock Grid.Row="6" Grid.Column="0" Text="IP Address(es):" FontWeight="Bold" Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="6" Grid.Column="1" Name="txtHwIpList" Text="" Margin="0,0,0,8" TextWrapping="Wrap"/>
                            
                            <!-- Gateway List -->
                            <TextBlock Grid.Row="7" Grid.Column="0" Text="Gateway(s):" FontWeight="Bold" Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="7" Grid.Column="1" Name="txtHwGwList" Text="" Margin="0,0,0,8" TextWrapping="Wrap"/>
                            
                                <!-- Asset Tag -->
                                <TextBlock Grid.Row="8" Grid.Column="0" Text="Asset Tag:" FontWeight="Bold" Margin="0,0,0,8"/>
                                <TextBlock Grid.Row="8" Grid.Column="1" Name="txtHwAssetTag" Text="" Margin="0,0,0,8" TextWrapping="Wrap"/>
                        </Grid>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
    </TabControl>
    </DockPanel>
        
    <!-- Bottom bar: status on left, buttons on right (always visible) -->
    <Grid Grid.Row="1" Margin="0,0,0,0">
        <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*" />
        <ColumnDefinition Width="Auto" />
        </Grid.ColumnDefinitions>
    
        <StackPanel Grid.Column="0" Orientation="Vertical" VerticalAlignment="Center" Margin="0,0,12,0">
            <TextBlock Name="txtWarning" Text="" FontSize="12" Foreground="OrangeRed" IsVisible="False" TextWrapping="Wrap" Margin="0,0,0,2"/>
            <TextBlock Name="txtStatus" Text="" FontSize="11" Foreground="OrangeRed" TextWrapping="Wrap"/>
            <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                <ToggleSwitch Name="chkEnableP2P"
                              Content="Enable P2P for rest of the task sequence"
                              IsChecked="True"
                              FontSize="11"
                              Margin="0,0,24,0"/>
                <ToggleSwitch Name="tglThemeMode"
                              Content="Dark mode"
                              IsChecked="True"
                              FontSize="11"/>
            </StackPanel>
        </StackPanel>
    
        <StackPanel Grid.Column="1"
            Orientation="Horizontal"
            HorizontalAlignment="Right">
        <Button Name="btnOK"
            Content="OK"
            Width="90"
            Height="32"
            Margin="0,0,10,0"
            IsDefault="True"/>
        <Button Name="btnCancel"
            Content="Cancel"
            Width="90"
            Height="32"
            IsCancel="True"/>
        </StackPanel>
    </Grid>
    </Grid>
</Window>
"@
    
    # Load XAML and resolve controls through Avalonia's name scope.
    $xamlText = $XAML.OuterXml -replace '\sName="', ' x:Name="'
    $Window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse[Avalonia.Controls.Window](
        $xamlText,
        [Avalonia.Controls.Window].Assembly
    )
    $windowIconBase64 = [string]$JSONConfig.WindowIconBase64
    $windowIconStream = [System.IO.MemoryStream]::new([Convert]::FromBase64String($windowIconBase64))
    try { $Window.Icon = [Avalonia.Controls.WindowIcon]::new($windowIconStream) } catch { Write-Warning "Unable to load embedded window icon: $($_.Exception.Message)" }
    function Get-AvaloniaControl {
        param($Root, [string]$Name)
        $scope = [Avalonia.Controls.NameScope]::GetNameScope($Root)
        if ($null -eq $scope) { throw "Avalonia name scope was not created for '$Name'." }
        $control = $scope.Find($Name)
        if ($null -eq $control) { throw "Avalonia control '$Name' was not found." }
        return $control
    }
    
    # Get Form Controls
    $imgLogo = Get-AvaloniaControl $Window "imgLogo"
    $rbNoName = Get-AvaloniaControl $Window "rbNoName"
    $rbManualName = Get-AvaloniaControl $Window "rbManualName"
    $rbHardwareName = Get-AvaloniaControl $Window "rbHardwareName"
    $txtManualName = Get-AvaloniaControl $Window "txtManualName"
    $txtPrefix = Get-AvaloniaControl $Window "txtPrefix"
    $cmbHardwareId = Get-AvaloniaControl $Window "cmbHardwareId"
    $txtDomainSuffix = Get-AvaloniaControl $Window "txtDomainSuffix"
    $txtPreview = Get-AvaloniaControl $Window "txtPreview"
    $chkEnableP2P = Get-AvaloniaControl $Window "chkEnableP2P"
    $rbWorkgroup = Get-AvaloniaControl $Window "rbWorkgroup"
    $rbEntraID = Get-AvaloniaControl $Window "rbEntraID"
    $rbAutopilot = Get-AvaloniaControl $Window "rbAutopilot"
    # rbOnlineDomainJoin removed - no FindName required
    $rbDomainJoin = Get-AvaloniaControl $Window "rbDomainJoin"
    $spEntraIDOptions = Get-AvaloniaControl $Window "spEntraIDOptions"
    $txtPrimaryUserUPN = Get-AvaloniaControl $Window "txtPrimaryUserUPN"
    $cmbUserRole = Get-AvaloniaControl $Window "cmbUserRole"
    $txtRoleSource = Get-AvaloniaControl $Window "txtRoleSource"
    $cmbAutopilotGroupTag = Get-AvaloniaControl $Window "cmbAutopilotGroupTag"
    $txtAutopilotLabel = Get-AvaloniaControl $Window "txtAutopilotLabel"
    $txtOptionOULabel = Get-AvaloniaControl $Window "txtOptionOULabel"
    $cmbOptionOU = Get-AvaloniaControl $Window "cmbOptionOU"
    $txtStatus = Get-AvaloniaControl $Window "txtStatus"
    $tglThemeMode = Get-AvaloniaControl $Window "tglThemeMode"
    $txtWarning = Get-AvaloniaControl $Window "txtWarning"
    $btnOK = Get-AvaloniaControl $Window "btnOK"
    $btnCancel = Get-AvaloniaControl $Window "btnCancel"
    $spSoftwareList = Get-AvaloniaControl $Window "spSoftwareList"
    $txtSoftwareFallback = Get-AvaloniaControl $Window "txtSoftwareFallback"
    $txtSoftwareTagInfo = Get-AvaloniaControl $Window "txtSoftwareTagInfo"
    
    # Hardware tab controls
    $txtHwMake = Get-AvaloniaControl $Window "txtHwMake"
    $txtHwModel = Get-AvaloniaControl $Window "txtHwModel"
    $txtHwSystem = Get-AvaloniaControl $Window "txtHwSystem"
    $txtHwSerial = Get-AvaloniaControl $Window "txtHwSerial"
    $txtHwMemory = Get-AvaloniaControl $Window "txtHwMemory"
    $txtHwMacList = Get-AvaloniaControl $Window "txtHwMacList"
    $txtHwIpList = Get-AvaloniaControl $Window "txtHwIpList"
    $txtHwGwList = Get-AvaloniaControl $Window "txtHwGwList"
    $txtHwAssetTag = Get-AvaloniaControl $Window "txtHwAssetTag"

    $validationBrush = [Avalonia.Media.Brush]::Parse('#FFC02626')
    $previewGrayBrush = [Avalonia.Media.Brush]::Parse('#FF6E6E6E')
    $previewGreenBrush = [Avalonia.Media.Brush]::Parse('#FF1E7B34')
    $previewRedBrush = [Avalonia.Media.Brush]::Parse('#FFC02626')
    function Show-ValidationError {
        param([string]$Message)
        $txtStatus.Foreground = $validationBrush
        $txtStatus.Text = $Message
    }

    $tglThemeMode.add_IsCheckedChanged({
        try {
            [Avalonia.Application]::Current.RequestedThemeVariant = if ($tglThemeMode.IsChecked) {
                [Avalonia.Styling.ThemeVariant]::Dark
            } else {
                [Avalonia.Styling.ThemeVariant]::Light
            }
        } catch {
            Write-Warning "Avalonia theme switch failed: $($_.Exception.Message)"
        }
    })
    
    # Populate hardware information
    $txtHwMake.Text = if ($MakeAlias) { $MakeAlias } else { "N/A" }
    $txtHwModel.Text = if ($ModelAlias) { $ModelAlias } else { "N/A" }
    $txtHwSystem.Text = if ($SystemAlias) { $SystemAlias } else { "N/A" }
    $txtHwSerial.Text = if ($SerialNumber) { $SerialNumber } else { "N/A" }
    $txtHwMemory.Text = if ($Memory) { "$Memory GB" } else { "N/A" }
    $txtHwMacList.Text = if ($macList -and $macList.Count -gt 0) { $macList -join "`n" } else { "N/A" }
    $txtHwIpList.Text = if ($ipList -and $ipList.Count -gt 0) { $ipList -join "`n" } else { "N/A" }
    $txtHwGwList.Text = if ($gwList -and $gwList.Count -gt 0) { $gwList -join "`n" } else { "N/A" }
    # Asset Tag (from SMBIOS) - show NA when not present or empty
    $txtHwAssetTag.Text = if ($AssetTag) { $AssetTag } else { "N/A" }
    
    # Initialize option OU script variable
    $script:OptionOU = $null

    # Initialize Enable P2P checkbox from existing TSEnv:Peering (default True if not set)
    $existingPeering = ${TSEnv:Peering}
    if (-not [string]::IsNullOrWhiteSpace($existingPeering) -and $existingPeering -ieq 'False') {
        $chkEnableP2P.IsChecked = $false
    } else {
        $chkEnableP2P.IsChecked = $true
    }
    
    # Helper to toggle Autopilot controls visibility/enabled state
    function Set-AutopilotControlsState {
        param(
        [bool]$Enabled
        )
        if ($Enabled) {
            $txtAutopilotLabel.IsVisible = $true
            $cmbAutopilotGroupTag.IsEnabled = $true
            $cmbAutopilotGroupTag.IsVisible = $true
        }
        else {
            $txtAutopilotLabel.IsVisible = $false
            $cmbAutopilotGroupTag.IsEnabled = $false
            $cmbAutopilotGroupTag.IsVisible = $false
        }
    }
    
    function Set-DomainJoinControlsState {
        param([bool]$Enabled)
        if ($Enabled) {
            $txtOptionOULabel.IsVisible = $true
            $cmbOptionOU.IsVisible = $true
            $cmbOptionOU.IsEnabled = $true
        }
        else {
            $txtOptionOULabel.IsVisible = $false
            $cmbOptionOU.IsVisible = $false
            $cmbOptionOU.IsEnabled = $false
        }
    }
    
    function Set-EntraIDOptionsState {
        param([bool]$Enabled)
        if ($Enabled) {
            $spEntraIDOptions.IsVisible = $true
        }
        else {
            $spEntraIDOptions.IsVisible = $false
        }
    }

    function Register-AvaloniaCheckedHandler {
        param([Avalonia.Controls.Primitives.ToggleButton]$Control)
        $handler = [System.EventHandler[Avalonia.Interactivity.RoutedEventArgs]]{
            param($sender, $eventArgs)
            try { Update-AvaloniaSelectionState } catch { Write-Warning "Avalonia radio event failed: $($_.Exception.Message)" }
        }
        $Control.add_IsCheckedChanged($handler)
    }
    
    function Update-FinishActionOptions {
        param([string]$WorkplaceJoinType)
        
        # Define which options are available for each workplace join type
        $availableOptions = @()
        
        switch ($WorkplaceJoinType) {
            'Workgroup' {
                # Local Workgroup: All options available
                $availableOptions = @('Shutdown', 'Restart', 'Reseal', 'Log Off', 'Nothing')
            }
            'EntraID' {
                # EntraID Join: Reseal NOT available
                $availableOptions = @('Shutdown', 'Restart', 'Log Off', 'Nothing')
            }
            'Autopilot' {
                # Autopilot Registration: Only Reseal available
                $availableOptions = @('Reseal')
            }
            'ODJ' {
                # Offline Domain Join: Reseal NOT available
                $availableOptions = @('Shutdown', 'Restart', 'Log Off', 'Nothing')
            }
            default {
                # Default: All options available
                $availableOptions = @('Shutdown', 'Restart', 'Reseal', 'Log Off', 'Nothing')
            }
        }
        
        # Remember current selection if it's still available
        $currentSelection = $cmbFinishAction.SelectedItem
        
        # Clear and repopulate the dropdown
        $cmbFinishAction.Items.Clear()
        foreach ($action in $availableOptions) {
            $cmbFinishAction.Items.Add($action) | Out-Null
        }
        
        # Try to restore the previous selection if it's still available, otherwise select first item
        if ($currentSelection -and $availableOptions -contains $currentSelection) {
            $cmbFinishAction.SelectedItem = $currentSelection
        } else {
            # Default to 'Restart' if available, otherwise first item
            if ($availableOptions -contains 'Restart') {
                $cmbFinishAction.SelectedItem = 'Restart'
            } else {
                $cmbFinishAction.SelectedIndex = 0
            }
        }
    }
    
    # Load logo from base64 or file path
    $logoLoaded = $false
    
    
    # Load Logo from file path
    if (!$logoLoaded -and ![string]::IsNullOrWhiteSpace($LogoPath) -and (Test-Path $LogoPath)) {
        try {
            $bitmap = [Avalonia.Media.Imaging.Bitmap]::new($LogoPath)
            $imgLogo.Source = $bitmap
            $logoLoaded = $true
        }
        catch {
            Write-Warning "Failed to load logo from file: $LogoPath - $_"
            # Last resort: try direct assignment
            try {
                $imgLogo.Source = $LogoPath
                $logoLoaded = $true
            } catch {}
        }
    }
    
    # Hide the logo control if nothing loaded
    if (!$logoLoaded) {
        $imgLogo.IsVisible = $false
    }
    
    # Populate User Role ComboBox from $RoleOptions
    foreach ($role in $RoleOptions) {
        $comboItem = [Avalonia.Controls.ComboBoxItem]::new()
        $comboItem.Content = $role.DisplayName
        $comboItem.Tag = $role.Value
        $cmbUserRole.Items.Add($comboItem) | Out-Null
    }
    
    # select first item by default if present
    if ($cmbUserRole.Items.Count -gt 0) { $cmbUserRole.SelectedIndex = 0 }
    
    # Update role source label
    $txtRoleSource.Text = "Roles populated from JSON config"
    
    # Populate Autopilot Group Tag ComboBox
    foreach ($tag in $AutopilotGroupTagOptions) {
        $cmbAutopilotGroupTag.Items.Add($tag) | Out-Null
    }
    $cmbAutopilotGroupTag.SelectedIndex = 0
    
    # Populate Online OU ComboBox From $OUOptions
    foreach ($ou in $OUOptions) {
        $cmbOptionOU.Items.Add($ou) | Out-Null
    }
    $cmbOptionOU.SelectedIndex = 0
    
    # Populate Finish Action ComboBox - Initial load based on default Workgroup selection
    $cmbFinishAction = Get-AvaloniaControl $Window "cmbFinishAction"
    # Start with the default workplace join type (Local Workgroup)
    Update-FinishActionOptions -WorkplaceJoinType 'Workgroup'
    
    # Check if there's an existing FINISHACTION value from TSEnv
    $existingFinishAction = ${TSEnv:FINISHACTION}
    if (-not [string]::IsNullOrWhiteSpace($existingFinishAction)) {
        # Try to find the existing value in the dropdown
        $index = $cmbFinishAction.Items.IndexOf($existingFinishAction)
        if ($index -ge 0) {
            $cmbFinishAction.SelectedIndex = $index
        } else {
            # If not found exactly, try case-insensitive match
            $index = 0
            foreach ($item in $cmbFinishAction.Items) {
                if ($item -eq $existingFinishAction -or $item.ToLower() -eq $existingFinishAction.ToLower()) {
                    $cmbFinishAction.SelectedIndex = $index
                    break
                }
                $index++
            }
            # If still not found, default to first available option
            if ($cmbFinishAction.SelectedIndex -lt 0) {
                $cmbFinishAction.SelectedIndex = 0
            }
        }
    }
    
    # Populate Hardware ID Type ComboBox
    foreach ($hwType in $HardwareIdOptions) {
        $cmbHardwareId.Items.Add($hwType) | Out-Null
    }
    $cmbHardwareId.SelectedIndex = 0
    
    # Populate software list from in-script $SoftwareOptions. Edit $SoftwareOptions at top of script.
    $script:SelectedSoftware = @()
    $script:SelectedSoftwareCsv = ""
    if ($SoftwareOptions -and $SoftwareOptions.Count -gt 0) {
        foreach ($item in $SoftwareOptions) {
            try {
                $cb = [Avalonia.Controls.CheckBox]::new()
                $cb.Content = $item.DisplayName
                $cb.Tag = $item.Id
                $cb.Margin = [Avalonia.Thickness]::new(6, 4, 0, 4)
                $cb.FontSize = 12
                $spSoftwareList.Children.Add($cb) | Out-Null
            } catch {
                Write-Warning "Failed to add software entry '$($item.DisplayName)': $_"
            }
        }
    }
    
    # Show which DeployR tag is used for dynamic software query
    try {
        $displayTag = if ([string]::IsNullOrWhiteSpace([string]$SoftwareTagForDeployR)) { "(not set)" } else { [string]$SoftwareTagForDeployR }
        $txtSoftwareTagInfo.Text = "Apps dynamically queried from DeployR based on the tag '$displayTag'"
    } catch {}
    
    # Only show warning if DeployR was supposed to be used (SoftwareFromDeployR = True) but failed
    try {
        if ($UseDeployRSoftwareList -eq "True" -and $DeployRRetrievalFailed) {
            $txtSoftwareFallback.Text = "Warning: Could not retrieve software list from DeployR - using built-in static list."
            $txtSoftwareFallback.IsVisible = $true
        }
    } catch {}
    
    # Get DNS suffix from the machine
    $dnsSuffix = $null
    try {
        # Try to get primary DNS suffix from network adapter configuration
        $adapter = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 1" -ErrorAction SilentlyContinue | 
        Where-Object { $_.DNSDomain } | 
        Select-Object -First 1
        if ($adapter -and $adapter.DNSDomain) {
            $dnsSuffix = $adapter.DNSDomain.Trim()
        }
        
        # Fallback: try to get from computer system
        if (-not $dnsSuffix) {
            $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
            if ($computerSystem -and $computerSystem.Domain -and $computerSystem.Domain -ne 'WORKGROUP') {
                $dnsSuffix = $computerSystem.Domain.Trim()
            }
        }
    }
    catch {
        Write-Warning "Failed to retrieve DNS suffix: $_"
    }
    
    # Initialize Domain Suffix field with DNS suffix from machine, or fall back to default value
    if (-not [string]::IsNullOrWhiteSpace($dnsSuffix)) {
        $txtDomainSuffix.Text = $dnsSuffix
    }
    elseif (-not [string]::IsNullOrWhiteSpace($DefaultDomainSuffix)) {
        $txtDomainSuffix.Text = $DefaultDomainSuffix
    }
    
    # Initialize Autopilot controls visibility based on current selection
    Set-AutopilotControlsState -Enabled:([bool]$rbAutopilot.IsChecked)
    
    # Function to update preview
    function Update-Preview {
        $domainSuffix = if ($null -ne $txtDomainSuffix.Text) { $txtDomainSuffix.Text.Trim() } else { '' }
        # Ignore the default placeholder value
        if ($domainSuffix -eq "contoso.local") {
            $domainSuffix = ""
        }
        
        if ($rbNoName.IsChecked) {
            $txtPreview.Text = "(Not set)"
            $txtPreview.Foreground = $previewGrayBrush
        }
        elseif ($rbManualName.IsChecked) {
            $name = $txtManualName.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($name)) {
                $txtPreview.Text = "(Enter a name)"
                $txtPreview.Foreground = $previewGrayBrush
            }
            else {
                # Validate computer name characters
                if ($name -match '^[a-zA-Z0-9-]+$') {
                    $displayName = $name.ToUpper()
                    # Add domain suffix if provided
                    if (-not [string]::IsNullOrWhiteSpace($domainSuffix)) {
                        $displayName = "$displayName.$domainSuffix"
                    }
                    $txtPreview.Text = $displayName
                    $txtPreview.Foreground = $previewGreenBrush
                    $txtStatus.Text = ""
                }
                else {
                    $txtPreview.Text = $name.ToUpper() + " (Invalid characters)"
                    $txtPreview.Foreground = $previewRedBrush
                    $txtStatus.Text = "Only letters, numbers, and hyphens are allowed"
                }
            }
        }
        elseif ($rbHardwareName.IsChecked) {
            $prefix = if ($null -ne $txtPrefix.Text) { $txtPrefix.Text.Trim().ToUpper() } else { '' }
            $hwType = [string]$cmbHardwareId.SelectedItem
            if ([string]::IsNullOrWhiteSpace($hwType)) { $hwType = 'Serial Number' }
            $hwId = Get-HardwareId -Type $hwType
            if ([string]::IsNullOrWhiteSpace($hwId)) { $hwId = 'UNKNOWN' }
            
            # If Asset Tag selected but not available, show a warning in the status area
            if ($hwType -eq "Asset Tag" -and ([string]::IsNullOrWhiteSpace($hwId) -or $hwId -eq "UNKNOWN")) {
                $txtWarning.Text = "Warning: Asset Tag not available - generated name may be invalid"
                $txtWarning.IsVisible = $true
                $txtPreview.Foreground = $previewRedBrush
            }
            else {
                # Clear any previous warning
                try { $txtWarning.Text = ""; $txtWarning.IsVisible = $false } catch {}
            }
            
            if ([string]::IsNullOrWhiteSpace($prefix)) {
                # If no prefix, ensure hardware id is truncated to max 15 chars (keep tail)
                if (-not [string]::IsNullOrWhiteSpace($hwId) -and $hwId.Length -gt 15) {
                    $hwId = $hwId.Substring($hwId.Length - 15, 15)
                }
                $generatedName = $hwId
            }
            else {
                # Validate prefix characters
                if ($prefix -match '^[a-zA-Z0-9-]+$') {
                    # Compute maximum length allowed for hardware id portion
                    $maxHwLen = 15 - ($prefix.Length + 1) # 1 for dash
                    if ($maxHwLen -lt 1) {
                        # Prefix is too long; truncate prefix to allow at least 1 char for hw id
                        $maxPrefix = 14
                        $prefix = $prefix.Substring(0, [Math]::Min($prefix.Length, $maxPrefix))
                        $maxHwLen = 15 - ($prefix.Length + 1)
                    }
                    
                    if (-not [string]::IsNullOrWhiteSpace($hwId) -and $hwId.Length -gt $maxHwLen) {
                        # Keep the rightmost characters of the hardware id when truncating
                        $truncatedHw = $hwId.Substring($hwId.Length - $maxHwLen, $maxHwLen)
                        $generatedName = "$prefix-$truncatedHw"
                        $txtStatus.Text = "Hardware ID truncated to fit 15 characters"
                    }
                    else {
                        $generatedName = "$prefix-$hwId"
                    }
                }
                else {
                    $txtPreview.Text = "$prefix-$hwId (Invalid prefix)"
                    $txtPreview.Foreground = $previewRedBrush
                    $txtStatus.Text = "Prefix can only contain letters, numbers, and hyphens"
                    return
                }
            }
            # Ensure final generated name does not exceed 15 chars (safety)
            if ($generatedName.Length -gt 15) {
                # As a safety, keep the rightmost 15 characters so serial tail is preserved
                $generatedName = $generatedName.Substring($generatedName.Length - 15, 15)
                $txtStatus.Text = "Name truncated to 15 characters"
            }
            
            $displayName = $generatedName
            # Add domain suffix if provided
            if (-not [string]::IsNullOrWhiteSpace($domainSuffix)) {
                $displayName = "$displayName.$domainSuffix"
            }
            $txtPreview.Text = $displayName
            $txtPreview.Foreground = $previewGreenBrush
            if (-not $txtStatus.Text) { $txtStatus.Text = "" }
        }
    }
    
    # Radio Button Events
    function Set-PanelVisualState {
        param(
        [bool]$noNameSelected,
        [bool]$manualSelected,
        [bool]$hardwareSelected
        )
        try {
            # Use opacity for reliable visual de-emphasis across themes/control templates
            $rbNoName.Opacity = (if ($noNameSelected) { 1.0 } else { 0.5 })
            $rbManualName.Opacity = (if ($manualSelected) { 1.0 } else { 0.5 })
            $rbHardwareName.Opacity = (if ($hardwareSelected) { 1.0 } else { 0.5 })
        } catch {}
        try { $lblPrefix.Opacity = (if ($hardwareSelected) { 1.0 } else { 0.5 }) } catch {}
        try { $lblHardwareIdType.Opacity = (if ($hardwareSelected) { 1.0 } else { 0.5 }) } catch {}
    }
    
    function Update-AvaloniaSelectionState {
        $manualSelected = [bool]$rbManualName.IsChecked
        $hardwareSelected = [bool]$rbHardwareName.IsChecked
        $workplaceType = if ($rbEntraID.IsChecked) { 'EntraID' } elseif ($rbAutopilot.IsChecked) { 'Autopilot' } elseif ($rbDomainJoin.IsChecked) { 'ODJ' } else { 'Workgroup' }

        $txtManualName.IsEnabled = $manualSelected
        $txtPrefix.IsEnabled = $hardwareSelected
        $cmbHardwareId.IsEnabled = $hardwareSelected
        try { $txtWarning.Text = ''; $txtWarning.IsVisible = $false } catch {}
        Set-PanelVisualState -noNameSelected (-not $manualSelected -and -not $hardwareSelected) -manualSelected $manualSelected -hardwareSelected $hardwareSelected
        Set-AutopilotControlsState -Enabled:([bool]$rbAutopilot.IsChecked)
        Set-DomainJoinControlsState -Enabled:([bool]$rbDomainJoin.IsChecked)
        Set-EntraIDOptionsState -Enabled:([bool]$rbEntraID.IsChecked)
        if ($null -ne $cmbFinishAction) { Update-FinishActionOptions -WorkplaceJoinType $workplaceType }
        Update-Preview
        if ($manualSelected) { try { $txtManualName.Focus() | Out-Null } catch {} }
    }

    Register-AvaloniaCheckedHandler $rbNoName
    Register-AvaloniaCheckedHandler $rbManualName
    Register-AvaloniaCheckedHandler $rbHardwareName
    Register-AvaloniaCheckedHandler $rbWorkgroup
    Register-AvaloniaCheckedHandler $rbEntraID
    Register-AvaloniaCheckedHandler $rbAutopilot
    Register-AvaloniaCheckedHandler $rbDomainJoin
    
    # Ensure Online Domain Join also turns off Autopilot controls when selected
    # Online Domain Join removed - Autopilot controls handled by other radio handlers
    
    # Text Changed Events
    $txtManualName.Add_TextChanged({
        Update-Preview
    })
    
    $txtPrefix.Add_TextChanged({
        Update-Preview
    })
    
    $cmbHardwareId.add_SelectionChanged({ Update-Preview })
    
    $txtDomainSuffix.Add_TextChanged({
        Update-Preview
    })
    
    # OK Button Click Event
    $btnOK.Add_Click({
        # Determine naming strategy and validate
        if ($rbNoName.IsChecked) {
            $script:NamingStrategy = "None"
            $script:GeneratedComputerName = $null
            $script:HardwareIdType = $null
        }
        elseif ($rbManualName.IsChecked) {
            $manualName = $txtManualName.Text.Trim()
            
            # Validate manual name
            if ([string]::IsNullOrWhiteSpace($manualName)) {
                Show-ValidationError "Please enter a computer name or select a different naming strategy."
                return
            }
            
            if ($manualName -notmatch '^[a-zA-Z0-9-]+$') {
                Show-ValidationError "Computer name can only contain letters, numbers, and hyphens."
                return
            }
            
            if ($manualName.Length -gt 15) {
                Show-ValidationError "Computer name cannot exceed 15 characters."
                return
            }
            
            $script:NamingStrategy = "Manual"
            $script:GeneratedComputerName = $manualName.ToUpper()
            $script:HardwareIdType = $null
        }
        elseif ($rbHardwareName.IsChecked) {
            $prefix = $txtPrefix.Text.Trim().ToUpper()
            $hwType = $cmbHardwareId.SelectedItem
            $hwId = Get-HardwareId -Type $hwType
            
            # Validate prefix if provided
            if (![string]::IsNullOrWhiteSpace($prefix) -and $prefix -notmatch '^[a-zA-Z0-9-]+$') {
                Show-ValidationError "Prefix can only contain letters, numbers, and hyphens."
                return
            }
            
            # Generate computer name
            if ([string]::IsNullOrWhiteSpace($prefix)) {
                # Truncate hardware id if needed (keep tail)
                if (-not [string]::IsNullOrWhiteSpace($hwId) -and $hwId.Length -gt 15) {
                    $hwId = $hwId.Substring($hwId.Length - 15, 15)
                }
                $generatedName = $hwId
            }
            else {
                # Ensure generated name fits 15 chars by truncating hw id portion
                $maxHwLen = 15 - ($prefix.Length + 1)
                if ($maxHwLen -lt 1) {
                    $maxPrefix = 14
                    $prefix = $prefix.Substring(0, [Math]::Min($prefix.Length, $maxPrefix))
                    $maxHwLen = 15 - ($prefix.Length + 1)
                }
                
                if (-not [string]::IsNullOrWhiteSpace($hwId) -and $hwId.Length -gt $maxHwLen) {
                    # Keep rightmost characters of hwId when truncating for prefix
                    $hwId = $hwId.Substring($hwId.Length - $maxHwLen, $maxHwLen)
                }
                $generatedName = "$prefix-$hwId"
            }
            
            # Validate total length
            # Final safety: truncate to 15 chars if still longer
            if ($generatedName.Length -gt 15) {
                # Safety: preserve serial tail by keeping rightmost 15 chars
                $generatedName = $generatedName.Substring($generatedName.Length - 15, 15)
            }
            
            $script:NamingStrategy = "HardwareBased"
            $script:GeneratedComputerName = $generatedName
            # Store simplified hardware type value
            if ($hwType -eq "Serial Number") { $script:HardwareIdType = "Serial" }
            elseif ($hwType -eq "MAC Address") { $script:HardwareIdType = "MAC" }
            elseif ($hwType -eq "Asset Tag") { $script:HardwareIdType = "AssetTag" }
            else { $script:HardwareIdType = $null }
        }
        
        # Determine workplace join method
        if ($rbWorkgroup.IsChecked) {
            $script:WorkplaceJoin = "Workgroup"
        }
        elseif ($rbEntraID.IsChecked) {
            $script:WorkplaceJoin = "EntraID"
        }
        elseif ($rbAutopilot.IsChecked) {
            $script:WorkplaceJoin = "Autopilot"
        }
        elseif ($rbDomainJoin.IsChecked) {
            $script:WorkplaceJoin = "ODJ"
            # Capture the selected OU from the Domain Join OU combo (now used for ODJ)
            $script:OptionOU = $cmbOptionOU.SelectedItem
        }
        
        # Store user role - use the Avalonia ComboBoxItem Tag value.
        $selectedItem = $cmbUserRole.SelectedItem
        if ($selectedItem -is [Avalonia.Controls.ComboBoxItem]) {
            $script:SelectedUserRole = $selectedItem.Tag
        } else {
            # Fallback if something unexpected happened
            $script:SelectedUserRole = $null
        }
        
        # Map Autopilot Group Tag display value to return value
        $selectedAutopilot = $cmbAutopilotGroupTag.SelectedItem
        switch ($selectedAutopilot) {
            'Hub Self Deploy' { $script:AutopilotGroupTag = 'Hub' }
            default { $script:AutopilotGroupTag = $selectedAutopilot }
        }
        
        # Capture Enable P2P checkbox
        $script:EnableP2P = [bool]$chkEnableP2P.IsChecked

        # Store domain suffix (ignore if it's the default placeholder value)
        $script:DomainSuffix = $txtDomainSuffix.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($script:DomainSuffix) -or $script:DomainSuffix -eq "contoso.local") {
            $script:DomainSuffix = $null
        }
        
        # Store Primary User UPN if EntraID is selected
        $script:EntraIDUserUPN = $null
        if ($rbEntraID.IsChecked -and $txtPrimaryUserUPN) {
            $upn = $txtPrimaryUserUPN.Text.Trim()
            if (-not [string]::IsNullOrWhiteSpace($upn)) {
                $script:EntraIDUserUPN = $upn
            }
        }
        # Capture software selections from dynamic 'Software' tab
        # Build a map of DisplayName -> bool and a list of selected software objects
        $script:SelectedSoftware = @()
        $script:SelectedSoftwareMap = [ordered]@{}
        foreach ($child in $spSoftwareList.Children) {
            try {
                if ($child) {
                    $id = [string]$child.Tag
                    $DisplayName = [string]$child.Content
                    if (-not $id) { $id = ([string]$child.Content).Replace(' ', '').ToLower() }
                    $isChecked = [bool]$child.IsChecked
                    $script:SelectedSoftwareMap[$DisplayName] = $isChecked
                    if ($isChecked) {
                        $script:SelectedSoftware += [PSCustomObject]@{
                            Id = $id
                            DisplayName = $DisplayName
                        }
                    }
                }
            } catch {}
        }
        # CSV representation: id=true,id=false,... for all defined options
        $script:SelectedSoftwareCsv = ($script:SelectedSoftwareMap.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, $_.Value } ) -join ','
        
        # Validation: if hardware naming is selected and Asset Tag chosen but not available, block OK
        if ($rbHardwareName.IsChecked) {
            $selectedHwType = $cmbHardwareId.SelectedItem
            if ($selectedHwType -eq "Asset Tag") {
                $selectedHwId = Get-HardwareId -Type $selectedHwType
                if ([string]::IsNullOrWhiteSpace($selectedHwId) -or $selectedHwId -eq "UNKNOWN") {
                    Show-ValidationError "Asset Tag was selected as the Hardware ID Type but no Asset Tag was found. Please choose a different Hardware ID Type or ensure the device has an Asset Tag."
                    return
                }
            }
        }
        
        # Stop auto-close timer (if running), then record the result and close.
        try { if ($script:AutoCloseTimer) { $script:AutoCloseTimer.Stop() } } catch {}
        $script:FormAccepted = $true
        $Window.Close()
    })
    
    # Cancel Button Click Event
    $btnCancel.Add_Click({
        try { if ($script:AutoCloseTimer) { $script:AutoCloseTimer.Stop() } } catch {}
        $script:FormAccepted = $false
        $Window.Close()
    })
    
    # Auto-close timer: close the window after 5 minutes (300 seconds)
    # Uses a DispatcherTimer so UI thread updates are safe. Updates txtStatus with countdown.
    $timeoutSeconds = 300
    $script:AutoCloseTimer = [Avalonia.Threading.DispatcherTimer]::new()
    $script:AutoCloseTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:AutoCloseRemaining = [int]$timeoutSeconds
    $txtStatus.Text = "Auto-close in {0}m {1}s" -f ([math]::Floor($script:AutoCloseRemaining/60)), ($script:AutoCloseRemaining%60)
    $script:AutoCloseTimer.Add_Tick({
        try {
            $script:AutoCloseRemaining = $script:AutoCloseRemaining - 1
            if ($script:AutoCloseRemaining -lt 0) {
                try { $script:AutoCloseTimer.Stop() } catch {}
                $script:FormAccepted = $false
                try { $Window.Close() } catch {}
                return
            }
            $m = [math]::Floor($script:AutoCloseRemaining/60)
            $s = $script:AutoCloseRemaining % 60
            $txtStatus.Text = "Auto-close in ${m}m ${s}s"
        } catch {}
    })
    $script:AutoCloseTimer.Start()
    
    # Apply initial visual state for radios and labels
    try { Set-PanelVisualState -noNameSelected ([bool]$rbNoName.IsChecked) -manualSelected ([bool]$rbManualName.IsChecked) -hardwareSelected ([bool]$rbHardwareName.IsChecked) } catch {}
    
    # Show the form and drive Avalonia's dispatcher until it closes.
    $script:FormAccepted = $false
    $cancellationSource = [System.Threading.CancellationTokenSource]::new()
    $Window.Add_Closed({
        [Avalonia.Threading.Dispatcher]::UIThread.Post(
            [System.Action]{ $cancellationSource.Cancel() },
            [Avalonia.Threading.DispatcherPriority]::Background
        )
    })
    $Window.Show()
    try {
        $dispatcher = [Avalonia.Threading.Dispatcher]::UIThread
        if ($null -eq $dispatcher) { throw 'Avalonia UI dispatcher was not initialized.' }
        $dispatcher.MainLoop($cancellationSource.Token)
    }
    catch [System.OperationCanceledException] {}
    catch { Write-Warning "Avalonia UI loop failed: $($_.Exception.Message)" }
    try { [Avalonia.Threading.Dispatcher]::UIThread.RunJobs() } catch {}
    $result = $script:FormAccepted
    
    # Capture Finish Action selection before form closes
    $script:FinishAction = $cmbFinishAction.SelectedItem
    
    # Create and return PSObject with form results
    if ($result -eq $true) {
        $FormResults = [PSCustomObject]@{
            NamingStrategy = $script:NamingStrategy
            GeneratedComputerName = $script:GeneratedComputerName
            DomainSuffix = $script:DomainSuffix
            HardwareIdType = $script:HardwareIdType
            WorkplaceJoin = $script:WorkplaceJoin
            SelectedUserRole = $script:SelectedUserRole
            AutopilotGroupTag = $script:AutopilotGroupTag
            DomainJoinOU = $script:OptionOU
            FinishAction = $script:FinishAction
            AssetTag = if ($LocalInfo.ContainsKey('AssetTag') -and -not [string]::IsNullOrWhiteSpace($LocalInfo['AssetTag'])) { $LocalInfo['AssetTag'] } else { 'NA' }
            DomainJoinSelected = ($script:WorkplaceJoin -eq 'ODJ')
            EntraIDUserUPN = $script:EntraIDUserUPN
            SelectedSoftware = $script:SelectedSoftware
            SelectedSoftwareMap = $script:SelectedSoftwareMap
            SelectedSoftwareCsv = $script:SelectedSoftwareCsv
            EnableP2P = $script:EnableP2P
            FormSubmitted = $true
        }
        
        Write-Host "`n=== Form Input Results ===" -ForegroundColor Cyan
        Write-Host "Naming Strategy: $($FormResults.NamingStrategy)" -ForegroundColor Green
        
        if ([string]::IsNullOrWhiteSpace($FormResults.GeneratedComputerName)) {
            Write-Host "Generated Computer Name: (Not set)" -ForegroundColor Yellow
        }
        else {
            Write-Host "Generated Computer Name: $($FormResults.GeneratedComputerName)" -ForegroundColor Green
        }
        
        if (-not [string]::IsNullOrWhiteSpace($FormResults.DomainSuffix)) {
            Write-Host "Domain Suffix: $($FormResults.DomainSuffix)" -ForegroundColor Green
            if (-not [string]::IsNullOrWhiteSpace($FormResults.GeneratedComputerName)) {
                Write-Host "Full FQDN: $($FormResults.GeneratedComputerName).$($FormResults.DomainSuffix)" -ForegroundColor Cyan
            }
        }
        
        if ($FormResults.HardwareIdType) {
            Write-Host "Hardware ID Type: $($FormResults.HardwareIdType)" -ForegroundColor Green
        }
        
        Write-Host "Workplace Join: $($FormResults.WorkplaceJoin)" -ForegroundColor Green
        Write-Host "Selected User Role: $($FormResults.SelectedUserRole)" -ForegroundColor Green
        Write-Host "Enable P2P: $($FormResults.EnableP2P)" -ForegroundColor Green
        Write-Host "Peering: $(if ($FormResults.EnableP2P) { 'True' } else { 'False' })" -ForegroundColor Green
        if ($FormResults.FinishAction) {
            Write-Host "Finish Action: $($FormResults.FinishAction)" -ForegroundColor Green
        }
        if ($FormResults.DomainJoinOU) {
            Write-Host "Domain Join OU: $($FormResults.DomainJoinOU)" -ForegroundColor Green
        }
        if ($FormResults.EntraIDUserUPN) {
            Write-Host "Entra ID User UPN: $($FormResults.EntraIDUserUPN)" -ForegroundColor Green
        }
        if ($FormResults.AutopilotGroupTag) {
            Write-Host "Autopilot Group Tag: $($FormResults.AutopilotGroupTag)" -ForegroundColor Green
        }
        if ($FormResults.AssetTag -and $FormResults.AssetTag -ne 'NA') {
            Write-Host "Asset Tag: $($FormResults.AssetTag)" -ForegroundColor Green
        }
        
        # Example: Use the returned object in your script
        # if (![string]::IsNullOrWhiteSpace($FormResults.GeneratedComputerName)) {
        #     Rename-Computer -NewName $FormResults.GeneratedComputerName -Force
        # }
        # 
        # Switch based on workplace join method
        # switch ($FormResults.WorkplaceJoin) {
        #     "Workgroup" { # Configure workgroup settings }
        #     "EntraID" { # Perform Azure AD/Entra ID join }
        #     "Autopilot" { # Register device with Autopilot }
        #     "ODJ" { # Apply offline domain join blob }
        # }
        # 
        # Switch based on user role for additional configuration
        # switch ($FormResults.SelectedUserRole) {
        #     "Family" { # Apply family-specific settings }
        #     "HR" { # Apply HR lab settings }
        #     "IT" { # Apply IT lab settings }
        #     "Execs" { # Apply executive lab settings }
        # }
        
        # Stop transcription before returning
        try { Stop-FrontendTranscription } catch {}
        return $FormResults
        
    } else {
        Write-Host "`nForm was cancelled." -ForegroundColor Yellow
        
        # Return object indicating cancellation
        # Stop transcription before returning
        try { Stop-FrontendTranscription } catch {}
        return [PSCustomObject]@{
            NamingStrategy = $null
            GeneratedComputerName = $null
            DomainSuffix = $null
            HardwareIdType = $null
            WorkplaceJoin = $null
            SelectedUserRole = $null
            AutopilotGroupTag = $null
            DomainJoinOU = $null
            AssetTag = $null
            SelectedSoftware = @()
            SelectedSoftwareCsv = ""
            FormSubmitted = $false
        }
    }
    
}


function Start-CMTraceLog {
    # Checks for path to log file and creates if it does not exist
    param (
    [Parameter(Mandatory = $true)]
    [string]$Path
    )
    
    $indexoflastslash = $Path.lastindexof('\')
    $directory = $Path.substring(0, $indexoflastslash)
    
    if (!(test-path -path $directory)){
        New-Item -ItemType Directory -Path $directory
    }
    else{
        # Directory Exists, do nothing    
    }
}

function Write-CMTraceLog {
    param (
    [Parameter(Mandatory = $true)]
    [string]$Message,
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = $($Global:LogFilePath),
    
    [Parameter()]
    [ValidateSet(1, 2, 3)]
    [int]$LogLevel = 1,
    
    [Parameter()]
    [string]$Component,
    
    [Parameter()]
    [ValidateSet('Info','Warning','Error')]
    [string]$Type
    )
    Switch ($Type) {
        Info {$LogLevel = 1}
        Warning {$LogLevel = 2}
        Error {$LogLevel = 3}
    }
    # Get Date message was triggered
    $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
    $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
    $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), $Component, $LogLevel
    $Line = $Line -f $LineFormat
    # Write new line in the log file
    try {
        if (-not $LogPath) {
            if ($env:TEMP) { $defaultDir = Join-Path -Path $env:TEMP -ChildPath 'DeployRLogs' } else { $defaultDir = Join-Path -Path $env:USERPROFILE -ChildPath 'DeployRLogs' }
            if (!(Test-Path -Path $defaultDir)) { New-Item -ItemType Directory -Path $defaultDir -Force | Out-Null }
            $LogPath = Join-Path -Path $defaultDir -ChildPath 'FrontEnd.log'
        } else {
            $indexoflastslash = $LogPath.lastindexof('\')
            $directory = $LogPath.substring(0, $indexoflastslash)
            if (!(Test-Path -Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        }
        Add-Content -Value $Line -Path $LogPath
    } catch {
        # Swallow this to avoid breaking the UI flow
    }
    # Roll log file over at size threshold
    if ($Global:LogFilePath -and (Test-Path -Path $Global:LogFilePath)) {
        if ((Get-Item $Global:LogFilePath).Length / 1KB -gt $Global:LogFileSize) {
            $log = $Global:LogFilePath
            Remove-Item ($log.Replace(".log", ".lo_")) -ErrorAction SilentlyContinue
            Rename-Item $Global:LogFilePath ($log.Replace(".log", ".lo_")) -Force
        }
    }
} 

function Get-DeployRFrontEndApps {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory = $true)]
    [string]$Tag
    )
    #This will connect with the DeployR Server and pull a list of Apps that are specified to show in the front end
    
    try {
        if (Test-Path -path 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'){
            Import-Module 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility' -ErrorAction SilentlyContinue
        }
        if (!(Get-Module -Name DeployR.Utility)) {
            Write-Host "Importing DeployR.Utility module from default PSModule path"
            Import-Module DeployR.Utility -ErrorAction SilentlyContinue
        }
    }
    catch {}
    <#
    if ((Get-Module -name "DeployR.Utility") -and (-not (test-path -path "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"))) {
    IF ($null -ne ${TSEnv:DEPLOYRCLIENTPASSCODE}){
    Write-Host "Using DeployR Client Passcode from TS Environment Variable"
    $ClientPasscode = ${TSEnv:DEPLOYRCLIENTPASSCODE}
    Connect-DeployR -Passcode $ClientPasscode -ErrorAction Stop
    }
    
    }
    else{
    if (Test-Path "HKLM:\software\2Pint Software\DeployR\GeneralSettings") {
    $DeployRReg = Get-Item -Path "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"
    $ClientPasscode = $DeployRReg.GetValue("ClientPasscode")
    Connect-DeployR -Passcode $ClientPasscode -ErrorAction Stop
    }
    elseif (Test-Path "D:\DeployRPasscode.txt") {
    $ClientPasscode = (Get-Content "D:\DeployRPasscode.txt" -Raw)
    Connect-DeployR -Passcode $ClientPasscode -ErrorAction Stop
    }
    else {
    throw "Cannot find DeployR Client Passcode in registry or D:\DeployRPasscode.txt"
    }
    }
    #>
    write-host "Retrieving DeployR Applications with tag '$Tag'..." -ForegroundColor Cyan
    $Apps = Get-DeployRApplication
    if ($Apps){
        if ($Apps.count -eq 0) {
            Write-Host "No applications found on DeployR Server." -ForegroundColor Yellow
            return @()
        }
    }
    else{
        Write-Host "Failed to retrieve applications from DeployR Server." -ForegroundColor Red
    }
    $FrontEndApps = $apps | Where-Object {$_.tags -match $Tag}
    return $FrontEndApps
}
#
#endregion Functions


#######################################################
# SCRIPT Execution
#######################################################

try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
    $Global:LogFolderPath = ${TSEnv:_DEPLOYRLOGS}
    $Global:Peering = ${TSEnv:Peering}
    $ModuleImported = $true
}
catch {
    write-host "DeployR.Utility module not found or failed to import. Continuing without it." -ForegroundColor Yellow
    $ModuleImported = $false
}

if ($ModuleImported) {
    $TSName = ${TSEnv:DEPLOYRTASKSEQUENCENAME}
    if ($TSName) {
        Write-Host "Running in TS: $TSName" -ForegroundColor Green
        $Global:IsRunningTS = $true
    } else {
        Write-Host "Dam, This is not running in a TS, Sorry Brah" -ForegroundColor Yellow
        $Global:IsRunningTS = $false
    }
}


# Start up the logs paths for DeployR / ConfigMgr or Local Testing
if (!($Global:LogFolderPath)) {
    if ($env:SystemDrive -eq "X:") {
        if (!(Test-Path -Path "$env:SystemDrive\_2P")) {
            $Global:LogFolderPath = "$env:temp\Logs"
            Write-Output "System Drive is X:, and _2P folder not found. Log Path set to $Global:LogFolderPath"
        }
        else {
            $Global:LogFolderPath = "$env:SystemDrive\_2P\Logs"
            Write-Output "System Drive is X:, Log Path set to $Global:LogFolderPath"
        }
    }
    else {
        # Prefer user-writable temp folder to avoid permission issues when not elevated
        if ($env:TEMP) {
            $Global:LogFolderPath = Join-Path -Path $env:TEMP -ChildPath 'DeployRLogs'
            Write-Output "Using TEMP folder for logs: $Global:LogFolderPath"
        }
        elseif (Test-Path -Path 'C:\Windows\Temp') {
            $Global:LogFolderPath = 'C:\Windows\Temp\DeployRLogs'
            Write-Output "Using Windows Temp folder for logs: $Global:LogFolderPath"
        }
    }
}
# Start a PowerShell transcription to capture verbose output in a separate file
$Global:FrontendTranscriptStarted = $false
try {
    if ($Global:LogFolderPath) {
        if (!(Test-Path -Path $Global:LogFolderPath)) { New-Item -ItemType Directory -Path $Global:LogFolderPath -Force | Out-Null }
        $transcriptPath = Join-Path $Global:LogFolderPath "FrontendTranscription-$PID.log"
        Start-Transcript -Path $transcriptPath -Force -ErrorAction Stop
        $Global:FrontendTranscriptStarted = $true
        Write-CMTraceLog -Message "Started PowerShell transcription to $transcriptPath" -Type "Info" -Component "Main"
    } else {
        Write-Warning "Transcript not started: LogFolderPath is not set."
    }
} catch {
    Write-Warning "Failed to start transcript: $_"
}

$Global:LogFilePath = "$($Global:LogFolderPath)\FrontEnd.log"
$Global:LogFileSize   = "40"
Start-CMTraceLog -Path $Global:LogFilePath
Write-CMTraceLog -Message "=====================================================" -Type "Info" -Component "Main"
Write-CMTraceLog -Message "Starting Script..." -Type "Info" -Component "Main"
Write-CMTraceLog -Message "=====================================================" -Type "Info" -Component "Main"
write-host "=====================================================" -ForegroundColor DarkGray
Write-Host "Starting Script version $ScriptVersion" -ForegroundColor Green
write-host "=====================================================" -ForegroundColor DarkGray
$FormResults = Get-InputFormData


# Set Variables in DeployR TS Environment if DeployR.Utility is available and no existing installation
if ((Get-Module -name "DeployR.Utility") -and (-not (test-path -path "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"))) {
    $DEPLOYRCLIENTPASSCODE = ${TSEnv:DEPLOYRCLIENTPASSCODE}
    if ($FormResults.NamingStrategy){
        ${TSEnv:NamingStrategy} = $FormResults.NamingStrategy
    }
    if ($FormResults.GeneratedComputerName){
        ${TSEnv:ComputerName} = $FormResults.GeneratedComputerName
    }
    if ($FormResults.DomainSuffix){
        ${TSEnv:DomainSuffix} = $FormResults.DomainSuffix
    }
    if ($FormResults.HardwareIdType){
        ${TSEnv:HardwareIdType} = $FormResults.HardwareIdType
    }
    if ($FormResults.WorkplaceJoin){
        ${TSEnv:WorkplaceJoin} = $FormResults.WorkplaceJoin
    }
    if ($FormResults.EntraIDUserUPN) {
        ${TSEnv:EntraIDUserUPN} = $FormResults.EntraIDUserUPN
        ${TSEnv:ENTRAUPN} = $FormResults.EntraIDUserUPN
    }
    if ($FormResults.DomainJoinOU) {
        ${TSEnv:DomainJoinOU} = $FormResults.DomainJoinOU
        ${TSEnv:OU} = $FormResults.DomainJoinOU
    }
    # Export AssetTag as TS variable
    if ($FormResults.AssetTag) {
        ${TSEnv:AssetTag} = $FormResults.AssetTag
    }
    if (($FormResults.WorkplaceJoin) -eq "Autopilot"){
        if ($FormResults.AutopilotGroupTag) {
            ${TSEnv:AutopilotGroupTag} = $FormResults.AutopilotGroupTag
            ${TSEnv:GROUPTAG} = $FormResults.AutopilotGroupTag
            ${TSEnv:FINISHACTION} = "RESEAL"
        }
    }
    if ($FormResults.SelectedUserRole){
        ${TSEnv:SelectedUserRole} = $FormResults.SelectedUserRole
    }
    if ($FormResults.FinishAction){
        ${TSEnv:FINISHACTION} = $FormResults.FinishAction
    }
    # Set Peering TS variable based on Enable P2P checkbox
    ${TSEnv:Peering} = if ($FormResults.EnableP2P) { 'True' } else { 'False' }
    try { Write-CMTraceLog -Message "Peering = $(${TSEnv:Peering})" -Type "Info" -Component "Main" } catch {}
    if ($FormResults.SelectedSoftwareCsv){
        ${TSEnv:SelectedSoftwareCsv} = $FormResults.SelectedSoftwareCsv
    }
    
    #Write Info to Log File about the variables we just set for visibility
    try { Write-CMTraceLog -Message  "Set DeployR TS Environment Variables:" -Type "Info" -Component "Main" } catch {}
    try { Write-CMTraceLog -Message "NamingStrategy = $(${TSEnv:NamingStrategy})" -Type "Info" -Component "Main" } catch {}
    try { Write-CMTraceLog -Message "ComputerName = $(${TSEnv:ComputerName})" -Type "Info" -Component "Main" } catch {}
    try { Write-CMTraceLog -Message "DomainSuffix = $(${TSEnv:DomainSuffix})" -Type "Info" -Component "Main" } catch {}
    try { Write-CMTraceLog -Message "HardwareIdType = $(${TSEnv:HardwareIdType})" -Type "Info" -Component "Main" } catch {}
    try { Write-CMTraceLog -Message "WorkplaceJoin = $(${TSEnv:WorkplaceJoin})" -Type "Info" -Component "Main" } catch {}
    if ($FormResults.EntraIDUserUPN){
        try { Write-CMTraceLog -Message "EntraIDUserUPN = $(${TSEnv:EntraIDUserUPN})" -Type "Info" -Component "Main" } catch {}
    }
    if ($FormResults.AutopilotGroupTag){
        try { Write-CMTraceLog -Message "AutopilotGroupTag = $(${TSEnv:AutopilotGroupTag})" -Type "Info" -Component "Main" } catch {}
    }
    if ($FormResults.FinishAction){
        try { Write-CMTraceLog -Message "FinishAction = $(${TSEnv:FINISHACTION})" -Type "Info" -Component "Main" } catch {}
    }
    if ($FormResults.DomainJoinOU){
        try { Write-CMTraceLog -Message "DomainJoinOU = $(${TSEnv:DomainJoinOU})" -Type "Info" -Component "Main" } catch {}
    }
    if ($FormResults.AssetTag -and $FormResults.AssetTag -ne 'NA'){
        try { Write-CMTraceLog -Message "AssetTag = $(${TSEnv:AssetTag})" -Type "Info" -Component "Main" } catch {}
    }
    try { Write-CMTraceLog -Message "SelectedUserRole = $(${TSEnv:SelectedUserRole})" -Type "Info" -Component "Main" } catch {}
    
    # Export individual software selections as Install_<id> = 'True'/'False'
    try {
        foreach ($kv in $FormResults.SelectedSoftwareMap.GetEnumerator()) {
            $key = $kv.Key
            $val = if ($kv.Value) { 'True' } else { 'False' }
            $varName = "Install_$($key)"
            Set-Item -Path "TSENV:$VarName" -Value $val
            try { Write-CMTraceLog -Message "$varName = $val" -Type "Info" -Component "Main" } catch {}
        }
    } catch {
        Write-Warning "Failed to export individual software TS variables: $_"
    }
    #Create the Variable List for Dynamic App Installs, needs to look like
    <#
    https://documentation.2pintsoftware.com/deployr/reference/step-definitions/install-multiple-applications
    $tsenvlist:Applications = @("d7775b33-9cfe-4fcd-b3a2-dc129cfc769e:1","c2032a9a-d15a-4275-97a2-e317a84f3437:1","2ae9d965-e89f-4e10-89e1-e55caeda997b:1","ebe17300-286a-4bf2-a172-aa8a4d64b186:1")
    #>
    $DeployRAppDetails = @()
    if ($FormResults.SelectedSoftware -and $FormResults.SelectedSoftware.Count -gt 0){
        foreach ($App in $FormResults.SelectedSoftware){
            #Get Details about App from DeployR Server
            $script:DeployRApps | where-object { $_.Id -eq $App.id } | ForEach-Object {
                $DeployRAppDetails += $_
            }
        }
    }
    #Grab the Latest Version of the Apps Available to use
    $AppList = @()
    foreach ($AppDetail in $DeployRAppDetails){
        $LatestVersion = $AppDetail.Versions | Sort-Object -Property VersionNumber -Descending | Select-Object -First 1
        if ($LatestVersion) {
            Write-Host "Adding application to TSENV list: $($AppDetail.Name) with Version Number $($LatestVersion.versionNo)" -ForegroundColor Green
            $AppList += "$($AppDetail.Id):$($LatestVersion.versionNo)"
            try { Write-CMTraceLog -Message "Added application to TSENV list: $($AppDetail.Name) with Version Number $($LatestVersion.versionNo)" -Type "Info" -Component "Main" } catch {}
            try { Write-CMTraceLog -Message "$tsenvlist:Applications += $($AppDetail.Id):$($LatestVersion.versionNo)" -Type "Info" -Component "Main" } catch {}
        }
        else {
            #Write-Warning "No versions found for application $($AppDetail.Name), skipping TSENV list addition."
        }
    }
    if ($AppList.Count -gt 0){
        $tsenvlist:Applications = $AppList
        try { Write-CMTraceLog -Message "Final TSENV list of applications to install: $($tsenvlist:Applications -join ', ')" -Type "Info" -Component "Main" } catch {}
    }
}
#If testing in Full OS outside of DeployR, just write out the results to console
else{
    $env:NamingStrategy = $FormResults.NamingStrategy
    $env:ComputerName = $FormResults.GeneratedComputerName
    $env:DomainSuffix = $FormResults.DomainSuffix
    $env:HardwareIdType = $FormResults.HardwareIdType
    $env:WorkplaceJoin = $FormResults.WorkplaceJoin
    if ($FormResults.EntraIDUserUPN) {
        $env:EntraIDUserUPN = $FormResults.EntraIDUserUPN
    }
    if ($FormResults.AutopilotGroupTag) {
        $env:AutopilotGroupTag = $FormResults.AutopilotGroupTag
    }
    if ($FormResults.FinishAction) {
        $env:FinishAction = $FormResults.FinishAction
    }
    $env:Peering = if ($FormResults.EnableP2P) { 'True' } else { 'False' }
    if ($FormResults.DomainJoinOU) {
        $env:DomainJoinOU = $FormResults.DomainJoinOU
    }
    if ($FormResults.AssetTag -and $FormResults.AssetTag -ne 'NA') {
        $env:AssetTag = $FormResults.AssetTag
    }
    $env:SelectedUserRole = $FormResults.SelectedUserRole
    
    $env:SelectedSoftwareCsv = $FormResults.SelectedSoftwareCsv
    # Export individual software selections as environment variables for testing
    try {
        foreach ($kv in $FormResults.SelectedSoftwareMap.GetEnumerator()) {
            $key = $kv.Key
            $val = if ($kv.Value) { 'True' } else { 'False' }
            $envVarName = 'Install_' + $key
            try {
                [System.Environment]::SetEnvironmentVariable($envVarName, $val, 'Process')
                $current = [System.Environment]::GetEnvironmentVariable($envVarName, 'Process')
                write-Host "$envVarName = $current" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to set environment variable $envVarName $_"
            }
        }
    } catch {}
    write-Host "Set Environment Variables for Testing outside DeployR:" -ForegroundColor Cyan
    write-Host "NamingStrategy = $($env:NamingStrategy)" -ForegroundColor Green
    write-Host "ComputerName = $($env:ComputerName)" -ForegroundColor Green
    write-Host "DomainSuffix = $($env:DomainSuffix)" -ForegroundColor Green
    if ($env:HardwareIdType) { write-Host "HardwareIdType = $($env:HardwareIdType)" -ForegroundColor Green }
    write-Host "WorkplaceJoin = $($env:WorkplaceJoin)" -ForegroundColor Green
    write-Host "Peering = $($env:Peering)" -ForegroundColor Green
    if ($env:FinishAction) { write-Host "FinishAction = $($env:FinishAction)" -ForegroundColor Green }
    if ($env:DomainJoinOU) { write-Host "DomainJoinOU = $($env:DomainJoinOU)" -ForegroundColor Green }
    if ($env:AssetTag -and $env:AssetTag -ne 'NA') { write-Host "AssetTag = $($env:AssetTag)" -ForegroundColor Green }
    if ($env:EntraIDUserUPN) { write-Host "EntraIDUserUPN = $($env:EntraIDUserUPN)" -ForegroundColor Green }
    write-Host "SelectedUserRole = $($env:SelectedUserRole)" -ForegroundColor Green
    write-Host "AutopilotGroupTag = $($env:AutopilotGroupTag)" -ForegroundColor Green
    write-Host "SelectedSoftwareCsv = $($env:SelectedSoftwareCsv)" -ForegroundColor Green
}
if ($Global:FrontendTranscriptStarted) {
    Stop-FrontendTranscription
}


