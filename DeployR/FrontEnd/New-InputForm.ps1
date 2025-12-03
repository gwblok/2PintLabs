Function Get-InputFormData {
    
    <#
.SYNOPSIS
    Creates a WPF form to collect user input including computer naming strategy and user role selection.
    
.DESCRIPTION
    This script displays a Windows Presentation Foundation (WPF) form with:
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
    
    Add-Type -AssemblyName PresentationFramework
    
    # Configuration: Logo (set to $null or empty string to disable logo)
    #
    # USAGE NOTES FOR LOGO CONVERSION:
    # This script includes a companion tool "Convert-ImageToBase64.ps1" that can resize and convert images
    # to base64 format. This is useful when you want to embed the logo directly in the script for portability.
    #
    # To use the conversion function:
    #   1. Load the function: . .\Convert-ImageToBase64.ps1
    #   2. Convert your image: $result = Convert-ImageToBase64 -ImagePath "C:\path\to\your\logo.png"
    #   3. Copy to clipboard: $result.Base64String | Set-Clipboard
    #   4. Paste into $LogoBase64 variable below
    #
    # The function automatically resizes images to 100px height (maintaining aspect ratio) before conversion,
    # which significantly reduces the base64 string length while maintaining good visual quality.
    #
    # Option 1: File path to image (useful during development)
    #$LogoPath = "c:\Users\GaryBlok\OneDrive - garytown\Pictures\2PintSoftware\Logo-blue.png"
    
    # Option 2: Base64 encoded image string (best for production/distribution)
    # This example shows a resized version of 2Pint Logo-blue.png (425x100, ~13KB)
    # $LogoBase64 = "iVBORw0KGg..."  # Your base64 string here
    $LogoBase64 = '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'
    
    # User role options - edit this array to add/remove roles (DisplayName and Value)
    # Each entry is a PSCustomObject with DisplayName (shown in UI) and Value (returned)
    $UserRoleOptions = @(
    [PSCustomObject]@{ DisplayName = 'Default - None'; Value = $null },
    [PSCustomObject]@{ DisplayName = 'Lab Computer - HR'; Value = 'HR' },
    [PSCustomObject]@{ DisplayName = 'Lab Computer - IT'; Value = 'IT' },
    [PSCustomObject]@{ DisplayName = 'Lab Computer - Execs'; Value = 'Execs' },
    [PSCustomObject]@{ DisplayName = 'Family Computer'; Value = 'Family' }
    )
    
    # Default domain suffix (optional - set to $null or empty string to leave blank)
    $DefaultDomainSuffix = "contoso.local"  # Change this to your domain or set to $null
    
    # Define hardware ID type options
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
    $Chassis = $LocalInfo['Chassis']
    
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

    #endregion
    
    
    # (Workplace join radio buttons are defined directly in XAML; the explicit options array was removed)
    
    # Software options - try to pull dynamically from DeployR, fall back to static list if unavailable
    # Try to get apps dynamically from DeployR
    $SoftwareOptions = $null
    try {
        # Call the function that's defined later in this script
        $DeployRApps = Get-DeployRFrontEndApps -ErrorAction Stop
        
        if ($DeployRApps -and $DeployRApps.Count -gt 0) {
            Write-Host "Successfully retrieved $($DeployRApps.Count) apps from DeployR" -ForegroundColor Green
            # Build PSObject array with DisplayName and Id (Id = name without spaces)
            $SoftwareOptions = @()
            foreach ($app in $DeployRApps) {
                $SoftwareOptions += [PSCustomObject]@{
                    DisplayName = $app.Name
                    Id = $app.Name -replace '\s+', ''  # Remove all spaces for Id
                }
            }
        }
    }
    catch {
        Write-Warning "Could not retrieve apps from DeployR: $($_.Exception.Message)"
    }
    
    # Fall back to static list if dynamic retrieval failed
    if (-not $SoftwareOptions -or $SoftwareOptions.Count -eq 0) {
        Write-Host "Using static software list as fallback" -ForegroundColor Yellow
        $SoftwareOptions = @(
        [PSCustomObject]@{ DisplayName = 'GreenShot'; Id = 'greenshot' },
        [PSCustomObject]@{ DisplayName = 'Office 365'; Id = 'office365' },
        [PSCustomObject]@{ DisplayName = 'Adobe Reader'; Id = 'adobereader' },
        [PSCustomObject]@{ DisplayName = 'Notepad++'; Id = 'notepadplusplus' },
        [PSCustomObject]@{ DisplayName = 'WMIExplorer'; Id = 'wmiexplorer' },
        [PSCustomObject]@{ DisplayName = 'Google Chrome'; Id = 'googlechrome' },
        [PSCustomObject]@{ DisplayName = '7-Zip'; Id = '7zip' },
        [PSCustomObject]@{ DisplayName = 'VLC Media Player'; Id = 'vlc' }
        )
    }
    
    
    
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
    
    # XAML Form Definition
    [xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="System Configuration Input Form" 
    Height="700" 
        Width="540"
        MinHeight="400"
        MinWidth="520"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Logo above the tabs -->
        <DockPanel Grid.Row="0">
            <Image Name="imgLogo"
                   Stretch="Uniform"
                   MaxHeight="80"
                   Margin="0,0,0,15"
                   HorizontalAlignment="Center"
                   DockPanel.Dock="Top"/>
            <!-- Tabs for content -->
            <TabControl Margin="0,0,0,10">
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
                
                <!-- Header -->
                <TextBlock Grid.Row="1" 
                           Text="System Configuration" 
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
                    <TextBlock Text="Domain Suffix (optional):" 
                               FontSize="11" 
                               Margin="0,0,0,3"/>
                    <TextBox Name="txtDomainSuffix" 
                             Height="25" 
                             FontSize="12"
                             ToolTip="Optional: Enter domain suffix (e.g., contoso.local) to display full FQDN in preview"/>
                </StackPanel>
                
                <!-- Preview -->
                <Border BorderBrush="LightGray" BorderThickness="1" Background="#F5F5F5" Padding="8" Margin="0,5,0,0">
                    <StackPanel>
                        <TextBlock Text="Computer Name Preview:" 
                                   FontSize="11" 
                                   FontWeight="Bold"
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
                                <StackPanel Name="spEntraIDOptions" Visibility="Collapsed" Margin="20,0,0,8">
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
                                             Content="Offline Domain Join" 
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
                        <TextBlock Name="txtOnlineOULabel" Text="Domain Join OU:" 
                                   FontSize="13" 
                                   FontWeight="Bold"
                                   Margin="0,10,0,5"
                                   Visibility="Collapsed"/>
                        <ComboBox Name="cmbOnlineOU"
                                  Height="28"
                                  FontSize="12"
                                  Visibility="Collapsed"/>
                        <TextBlock Name="txtOnlineJoinInfo"
                                   Text="Account: CM_DJ    Domain: 2P.GARYTOWN.COM"
                                   FontSize="11"
                                   Foreground="Gray"
                                   Margin="0,5,0,0"
                                   Visibility="Collapsed"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
    
            <TabItem Header="Roles">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8">
                    <StackPanel Margin="0,6,0,0">
                        <TextBlock Text="Select User's Role:" FontSize="13" FontWeight="Bold" Margin="0,0,0,5" />
                        <ComboBox Name="cmbUserRole" Height="28" FontSize="12"/>
                        <TextBlock Name="txtRoleSource" Text="" FontSize="10" Foreground="Gray" Margin="0,8,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
    
            <TabItem Header="Software">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8">
                    <StackPanel Margin="0,6,0,0">
                        <TextBlock Text="Select software to install:" FontSize="13" FontWeight="Bold" Margin="0,0,0,8"/>
                        <!-- Dynamic software list populated from SoftwareList.json -->
                        <StackPanel Name="spSoftwareList" Margin="6,4,0,0" />
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
    
            <TabItem Header="Hardware">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8">
                    <StackPanel Margin="0,6,0,0">
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
            <TextBlock Name="txtWarning" Text="" FontSize="12" Foreground="OrangeRed" Visibility="Collapsed" TextWrapping="Wrap" Margin="0,0,0,2"/>
            <TextBlock Name="txtStatus" Text="" FontSize="11" Foreground="OrangeRed" TextWrapping="Wrap"/>
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
    
    # Load XAML
    $reader = New-Object System.Xml.XmlNodeReader $XAML
    $Window = [Windows.Markup.XamlReader]::Load($reader)
    
    # Get Form Controls
    $imgLogo = $Window.FindName("imgLogo")
    $rbNoName = $Window.FindName("rbNoName")
    $rbManualName = $Window.FindName("rbManualName")
    $rbHardwareName = $Window.FindName("rbHardwareName")
    $txtManualName = $Window.FindName("txtManualName")
    $txtPrefix = $Window.FindName("txtPrefix")
    $cmbHardwareId = $Window.FindName("cmbHardwareId")
    $txtDomainSuffix = $Window.FindName("txtDomainSuffix")
    $txtPreview = $Window.FindName("txtPreview")
    $rbWorkgroup = $Window.FindName("rbWorkgroup")
    $rbEntraID = $Window.FindName("rbEntraID")
    $rbAutopilot = $Window.FindName("rbAutopilot")
    # rbOnlineDomainJoin removed - no FindName required
    $rbDomainJoin = $Window.FindName("rbDomainJoin")
    $spEntraIDOptions = $Window.FindName("spEntraIDOptions")
    $txtPrimaryUserUPN = $Window.FindName("txtPrimaryUserUPN")
    $cmbUserRole = $Window.FindName("cmbUserRole")
    $txtRoleSource = $Window.FindName("txtRoleSource")
    $cmbAutopilotGroupTag = $Window.FindName("cmbAutopilotGroupTag")
    $txtAutopilotLabel = $Window.FindName("txtAutopilotLabel")
    $txtOnlineOULabel = $Window.FindName("txtOnlineOULabel")
    $cmbOnlineOU = $Window.FindName("cmbOnlineOU")
    $txtOnlineJoinInfo = $Window.FindName("txtOnlineJoinInfo")
    $txtStatus = $Window.FindName("txtStatus")
    $txtWarning = $Window.FindName("txtWarning")
    $btnOK = $Window.FindName("btnOK")
    $btnCancel = $Window.FindName("btnCancel")
    $spSoftwareList = $Window.FindName("spSoftwareList")
    
    # Hardware tab controls
    $txtHwMake = $Window.FindName("txtHwMake")
    $txtHwModel = $Window.FindName("txtHwModel")
    $txtHwSystem = $Window.FindName("txtHwSystem")
    $txtHwSerial = $Window.FindName("txtHwSerial")
    $txtHwMemory = $Window.FindName("txtHwMemory")
    $txtHwMacList = $Window.FindName("txtHwMacList")
    $txtHwIpList = $Window.FindName("txtHwIpList")
    $txtHwGwList = $Window.FindName("txtHwGwList")
    $txtHwAssetTag = $Window.FindName("txtHwAssetTag")
    
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
    
    # Initialize online OU script variable
    $script:OnlineOU = $null
    
    # Helper to toggle Autopilot controls visibility/enabled state
    function Set-AutopilotControlsState {
        param(
        [bool]$Enabled
        )
        if ($Enabled) {
            $txtAutopilotLabel.Visibility = 'Visible'
            $cmbAutopilotGroupTag.IsEnabled = $true
            $cmbAutopilotGroupTag.Visibility = 'Visible'
        }
        else {
            $txtAutopilotLabel.Visibility = 'Collapsed'
            $cmbAutopilotGroupTag.IsEnabled = $false
            $cmbAutopilotGroupTag.Visibility = 'Collapsed'
        }
    }
    
    function Set-OnlineDomainJoinControlsState {
        param([bool]$Enabled)
        if ($Enabled) {
            $txtOnlineOULabel.Visibility = 'Visible'
            $cmbOnlineOU.Visibility = 'Visible'
            $cmbOnlineOU.IsEnabled = $true
            $txtOnlineJoinInfo.Visibility = 'Visible'
        }
        else {
            $txtOnlineOULabel.Visibility = 'Collapsed'
            $cmbOnlineOU.Visibility = 'Collapsed'
            $cmbOnlineOU.IsEnabled = $false
            $txtOnlineJoinInfo.Visibility = 'Collapsed'
        }
    }
    
    function Set-EntraIDOptionsState {
        param([bool]$Enabled)
        if ($Enabled) {
            $spEntraIDOptions.Visibility = 'Visible'
        }
        else {
            $spEntraIDOptions.Visibility = 'Collapsed'
        }
    }
    
    # Load logo from base64 or file path
    $logoLoaded = $false
    
    # Try to load from base64 first (if provided)
    if (![string]::IsNullOrWhiteSpace($LogoBase64)) {
        try {
            $imageBytes = [Convert]::FromBase64String($LogoBase64)
            $ms = New-Object System.IO.MemoryStream($imageBytes, 0, $imageBytes.Length)
            $ms.Write($imageBytes, 0, $imageBytes.Length)
            $bitmapImage = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmapImage.BeginInit()
            $bitmapImage.StreamSource = $ms
            $bitmapImage.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmapImage.EndInit()
            $bitmapImage.Freeze()
            $imgLogo.Source = $bitmapImage
            $logoLoaded = $true
        }
        catch {
            Write-Warning "Failed to load logo from base64 string: $_"
        }
    }
    
    # If base64 didn't work, try file path
    if (!$logoLoaded -and ![string]::IsNullOrWhiteSpace($LogoPath) -and (Test-Path $LogoPath)) {
        try {
            $imgLogo.Source = $LogoPath
            $logoLoaded = $true
        }
        catch {
            Write-Warning "Failed to load logo from file: $LogoPath"
        }
    }
    
    # Hide the logo control if nothing loaded
    if (!$logoLoaded) {
        $imgLogo.Visibility = "Collapsed"
    }
    
    # Resolve script directory robustly to support dot-sourcing and different PowerShell hosts
    $scriptDir = $null
    try { $scriptDir = $PSScriptRoot } catch {}
    if (-not $scriptDir) {
        if ($PSCommandPath) { $scriptDir = Split-Path -Parent $PSCommandPath }
        elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Definition) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
        elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
        else { $scriptDir = (Get-Location).Path }
    }
    
    # Load RoleDatabase.json early to match device and pre-populate fields
    $script:MatchedDevice = $null
    $script:RoleDbData = $null
    $script:DeviceFound = $false
    $script:GitHubJSONDB = $false
    
    # Get current device serial number
    $currentSerial = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
    
    # Try to load RoleDatabase.json from GitHub
    $roleDatabaseUrl = 'https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/FrontEnd/RoleDatabase.json'
    try {
        $script:RoleDbData = Invoke-RestMethod -Uri $roleDatabaseUrl -UseBasicParsing -ErrorAction Stop
        if ($script:RoleDbData -and $script:RoleDbData.Count -gt 0) {
            $script:GitHubJSONDB = $true
            # Try to match current device by serial number
            if ($currentSerial) {
                foreach ($device in $script:RoleDbData) {
                    if ($device.SerialNumber -and ($device.SerialNumber.ToString().Trim() -eq $currentSerial.Trim())) {
                        $script:MatchedDevice = $device
                        $script:DeviceFound = $true
                        Write-Host "Device match found in RoleDatabase.json for serial: $currentSerial"
                        break
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to fetch RoleDatabase.json from GitHub for device matching: $_"
    }
    
    # If no match from GitHub, try local RoleDatabase.json
    if (-not $script:DeviceFound) {
        $localRoleDbPath = Join-Path -Path $scriptDir -ChildPath 'RoleDatabase.json'
        if (Test-Path $localRoleDbPath) {
            try {
                $script:RoleDbData = Get-Content -Path $localRoleDbPath -Raw | ConvertFrom-Json
                if ($script:RoleDbData -and $currentSerial) {
                    foreach ($device in $script:RoleDbData) {
                        if ($device.SerialNumber -and ($device.SerialNumber.ToString().Trim() -eq $currentSerial.Trim())) {
                            $script:MatchedDevice = $device
                            $script:DeviceFound = $true
                            Write-Host "Device match found in local RoleDatabase.json for serial: $currentSerial"
                            break
                        }
                    }
                }
            }
            catch {
                Write-Warning "Failed to load local RoleDatabase.json: $_"
            }
        }
    }
    
    # Try to load roles from GitHub RoleDatabase.json (fetch Category values)
    $roleSource = "built-in script"
    $roleDatabaseUrl = 'https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/FrontEnd/RoleDatabase.json'
    try {
        # Re-use already loaded data if available
        $roleDbData = if ($script:RoleDbData) { $script:RoleDbData } else { Invoke-RestMethod -Uri $roleDatabaseUrl -UseBasicParsing -ErrorAction Stop }
        if ($roleDbData -and $roleDbData.Count -gt 0) {
            # Extract unique Category values (case-insensitive)
            $categories = @()
            foreach ($entry in $roleDbData) {
                if ($entry.Category -and ($entry.Category.ToString().Trim() -ne '')) {
                    $categories += $entry.Category.ToString().Trim()
                }
            }
            $uniqueCategories = $categories | Sort-Object -Unique
            
            if ($uniqueCategories.Count -gt 0) {
                # Replace UserRoleOptions with GitHub categories
                $UserRoleOptions = @([PSCustomObject]@{ DisplayName = 'Default - None'; Value = $null })
                foreach ($cat in $uniqueCategories) {
                    $UserRoleOptions += [PSCustomObject]@{ DisplayName = $cat; Value = $cat }
                }
                $roleSource = "GitHub RoleDatabase.json"
            }
        }
    }
    catch {
        Write-Warning "Failed to fetch RoleDatabase.json from GitHub; using built-in roles: $_"
    }
    
    # Try to load roles from Roles.json (optional). Expected format: { "roles": [ { "DisplayName": "Lab Computer - IT", "Value": "IT" }, ... ] }
    $rolesJsonPath = Join-Path -Path $scriptDir -ChildPath 'Roles.json'
    if (Test-Path $rolesJsonPath) {
        try {
            $rolesData = Get-Content -Path $rolesJsonPath -Raw | ConvertFrom-Json
            if ($rolesData -and $rolesData.roles) {
                $loaded = @()
                foreach ($r in $rolesData.roles) {
                    $loaded += [PSCustomObject]@{ DisplayName = $r.DisplayName; Value = (if ($r.Value) { $r.Value } else { $null }) }
                }
                if ($loaded.Count -gt 0) { 
                    $UserRoleOptions = $loaded
                    $roleSource = "local Roles.json"
                }
            }
        }
        catch {
            Write-Warning "Failed to parse Roles.json; falling back to built-in roles: $_"
        }
    }
    
    # Populate User Role ComboBox with display names (in defined order)
    foreach ($role in $UserRoleOptions) {
        try {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $role.DisplayName
            $item.Tag = $role.Value
            $cmbUserRole.Items.Add($item) | Out-Null
        } catch { }
    }
    # select first item by default if present
    if ($cmbUserRole.Items.Count -gt 0) { $cmbUserRole.SelectedIndex = 0 }
    
    # Update status to show where roles were loaded from
    $txtStatus.Text = "Roles populated from: $roleSource"
    $txtRoleSource.Text = "Roles populated from: $roleSource"
    
    # Populate Autopilot Group Tag ComboBox
    $cmbAutopilotGroupTag.Items.Add("Enterprise") | Out-Null
    $cmbAutopilotGroupTag.Items.Add("Hub Self Deploy") | Out-Null
    $cmbAutopilotGroupTag.SelectedIndex = 0
    
    # Populate Online OU ComboBox
    $cmbOnlineOU.Items.Add("OU=Workstations,OU=2PintTown,DC=2P,DC=garytown,DC=com") | Out-Null
    $cmbOnlineOU.Items.Add("OU=Servers,OU=2PintTown,DC=2P,DC=garytown,DC=com") | Out-Null
    $cmbOnlineOU.SelectedIndex = 0
    
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
                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Content = $item.DisplayName
                $cb.Tag = $item.Id
                $cb.Margin = '6,4,0,4'
                $cb.FontSize = 12
                $spSoftwareList.Children.Add($cb) | Out-Null
            } catch {
                Write-Warning "Failed to add software entry '$($item.DisplayName)': $_"
            }
        }
    }
    else {
        # Fallback: populate with a few defaults if no software options defined
        $defaults = @('GreenShot','Office 365','Adobe Reader')
        foreach ($d in $defaults) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $d
            $cb.Margin = '6,4,0,4'
            $cb.FontSize = 12
            $spSoftwareList.Children.Add($cb) | Out-Null
        }
    }
    
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
        $domainSuffix = $txtDomainSuffix.Text.Trim()
        # Ignore the default placeholder value
        if ($domainSuffix -eq "contoso.local") {
            $domainSuffix = ""
        }
        
        if ($rbNoName.IsChecked) {
            $txtPreview.Text = "(Not set)"
            $txtPreview.Foreground = "Gray"
        }
        elseif ($rbManualName.IsChecked) {
            $name = $txtManualName.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($name)) {
                $txtPreview.Text = "(Enter a name)"
                $txtPreview.Foreground = "Gray"
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
                    $txtPreview.Foreground = "DarkGreen"
                    $txtStatus.Text = ""
                }
                else {
                    $txtPreview.Text = $name.ToUpper() + " (Invalid characters)"
                    $txtPreview.Foreground = "Red"
                    $txtStatus.Text = "Only letters, numbers, and hyphens are allowed"
                }
            }
        }
        elseif ($rbHardwareName.IsChecked) {
            $prefix = $txtPrefix.Text.Trim().ToUpper()
            $hwType = $cmbHardwareId.SelectedItem
            $hwId = Get-HardwareId -Type $hwType

            # If Asset Tag selected but not available, show a warning in the status area
            if ($hwType -eq "Asset Tag" -and ([string]::IsNullOrWhiteSpace($hwId) -or $hwId -eq "UNKNOWN")) {
                $txtWarning.Text = "Warning: Asset Tag not available — generated name may be invalid"
                $txtWarning.Visibility = 'Visible'
                $txtPreview.Foreground = "Red"
            }
            else {
                # Clear any previous warning
                try { $txtWarning.Text = ""; $txtWarning.Visibility = 'Collapsed' } catch {}
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
                    $txtPreview.Foreground = "Red"
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
            $txtPreview.Foreground = "DarkGreen"
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

    $rbNoName.Add_Checked({
        # No-name: disable manual and hardware panels
        $txtManualName.IsEnabled = $false
        $txtPrefix.IsEnabled = $false
        $cmbHardwareId.IsEnabled = $false
        # Clear any asset-tag warnings
        try { $txtWarning.Text = ""; $txtWarning.Visibility = 'Collapsed' } catch {}
        Set-PanelVisualState -noNameSelected $true -manualSelected $false -hardwareSelected $false
        Update-Preview
    })
    
    $rbManualName.Add_Checked({
        # Manual name selected: enable manual controls, disable hardware controls
        $txtManualName.IsEnabled = $true
        $txtPrefix.IsEnabled = $false
        $cmbHardwareId.IsEnabled = $false
        # Clear any asset-tag warnings
        try { $txtWarning.Text = ""; $txtWarning.Visibility = 'Collapsed' } catch {}
        $txtManualName.Focus()
        Set-PanelVisualState -noNameSelected $false -manualSelected $true -hardwareSelected $false
        Update-Preview
    })
    
    $rbHardwareName.Add_Checked({
        # Hardware name selected: enable hardware controls, disable manual controls
        $txtManualName.IsEnabled = $false
        $txtPrefix.IsEnabled = $true
        $cmbHardwareId.IsEnabled = $true
        # Clear any previous warning; Update-Preview will re-evaluate and show if still missing
        try { $txtWarning.Text = ""; $txtWarning.Visibility = 'Collapsed' } catch {}
        Set-PanelVisualState -noNameSelected $false -manualSelected $false -hardwareSelected $true
        Update-Preview
    })
    
    # Wire Workplace Join radio buttons to toggle Autopilot controls
    $rbWorkgroup.Add_Checked({ Set-AutopilotControlsState -Enabled:$false })
    $rbEntraID.Add_Checked({ Set-AutopilotControlsState -Enabled:$false })
    $rbAutopilot.Add_Checked({ Set-AutopilotControlsState -Enabled:$true })
    $rbDomainJoin.Add_Checked({ Set-AutopilotControlsState -Enabled:$false })
    # Wire Online Domain Join radio handlers
    $rbWorkgroup.Add_Checked({ Set-OnlineDomainJoinControlsState -Enabled:$false })
    $rbEntraID.Add_Checked({ Set-OnlineDomainJoinControlsState -Enabled:$false })
    $rbAutopilot.Add_Checked({ Set-OnlineDomainJoinControlsState -Enabled:$false })
    # Online Domain Join removed - keep Domain Join (offline) enabling OU controls
    # Show the Domain Join OU controls for both Online and Offline Domain Join selections
    $rbDomainJoin.Add_Checked({ Set-OnlineDomainJoinControlsState -Enabled:$true })
    
    # Wire EntraID options visibility
    $rbWorkgroup.Add_Checked({ Set-EntraIDOptionsState -Enabled:$false })
    $rbEntraID.Add_Checked({ Set-EntraIDOptionsState -Enabled:$true })
    $rbAutopilot.Add_Checked({ Set-EntraIDOptionsState -Enabled:$false })
    # Online Domain Join removed - EntraID options handled by other radio handlers
    $rbDomainJoin.Add_Checked({ Set-EntraIDOptionsState -Enabled:$false })
    
    # Ensure Online Domain Join also turns off Autopilot controls when selected
    # Online Domain Join removed - Autopilot controls handled by other radio handlers
    
    # Text Changed Events
    $txtManualName.Add_TextChanged({
        Update-Preview
    })
    
    $txtPrefix.Add_TextChanged({
        Update-Preview
    })
    
    $cmbHardwareId.Add_SelectionChanged({
        Update-Preview
    })
    
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
                [System.Windows.MessageBox]::Show(
                "Please enter a computer name or select a different naming strategy.",
                "Validation Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
                )
                return
            }
            
            if ($manualName -notmatch '^[a-zA-Z0-9-]+$') {
                [System.Windows.MessageBox]::Show(
                "Computer name can only contain letters, numbers, and hyphens.",
                "Validation Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
                )
                return
            }
            
            if ($manualName.Length -gt 15) {
                [System.Windows.MessageBox]::Show(
                "Computer name cannot exceed 15 characters.",
                "Validation Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
                )
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
                [System.Windows.MessageBox]::Show(
                "Prefix can only contain letters, numbers, and hyphens.",
                "Validation Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
                )
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
            $script:OnlineOU = $cmbOnlineOU.SelectedItem
        }
        
        # Store user role - use ComboBoxItem.Tag (Value) when available
        $selectedItem = $cmbUserRole.SelectedItem
        if ($selectedItem -is [System.Windows.Controls.ComboBoxItem]) {
            $script:SelectedUserRole = $selectedItem.Tag
        } else {
            # Fallback: if for some reason the combo contains plain strings, attempt lookup
            $selectedDisplayName = [string]$selectedItem
            $match = $UserRoleOptions | Where-Object { $_.DisplayName -eq $selectedDisplayName }
            $script:SelectedUserRole = if ($match) { $match.Value } else { $null }
        }
        
        # Map Autopilot Group Tag display value to return value
        $selectedAutopilot = $cmbAutopilotGroupTag.SelectedItem
        switch ($selectedAutopilot) {
            'Hub Self Deploy' { $script:AutopilotGroupTag = 'Hub' }
            default { $script:AutopilotGroupTag = $selectedAutopilot }
        }
        
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
        # Build a map of Id -> bool and a list of selected Ids
        $script:SelectedSoftware = @()
        $script:SelectedSoftwareMap = [ordered]@{}
        foreach ($child in $spSoftwareList.Children) {
            try {
                if ($child) {
                    $id = [string]$child.Tag
                    if (-not $id) { $id = ([string]$child.Content).Replace(' ', '').ToLower() }
                    $isChecked = [bool]$child.IsChecked
                    $script:SelectedSoftwareMap[$id] = $isChecked
                    if ($isChecked) { $script:SelectedSoftware += $id }
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
                    [System.Windows.MessageBox]::Show(
                        "Asset Tag was selected as the Hardware ID Type but no Asset Tag was found. Please choose a different Hardware ID Type or ensure the device has an Asset Tag.",
                        "Validation Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    )
                    return
                }
            }
        }

        # Stop auto-close timer (if running), then set dialog result and close
        try { if ($script:AutoCloseTimer) { $script:AutoCloseTimer.Stop() } } catch {}
        # Set dialog result and close
        $Window.DialogResult = $true
        $Window.Close()
    })
    
    # Cancel Button Click Event
    $btnCancel.Add_Click({
        try { if ($script:AutoCloseTimer) { $script:AutoCloseTimer.Stop() } } catch {}
        $Window.DialogResult = $false
        $Window.Close()
    })
    
    # Auto-close timer: close the window after 5 minutes (300 seconds)
    # Uses a DispatcherTimer so UI thread updates are safe. Updates txtStatus with countdown.
    $timeoutSeconds = 300
    $script:AutoCloseTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:AutoCloseTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:AutoCloseRemaining = [int]$timeoutSeconds
    $txtStatus.Text = "Auto-close in {0}m {1}s" -f ([math]::Floor($script:AutoCloseRemaining/60)), ($script:AutoCloseRemaining%60)
    $script:AutoCloseTimer.Add_Tick({
        try {
            $script:AutoCloseRemaining = $script:AutoCloseRemaining - 1
            if ($script:AutoCloseRemaining -lt 0) {
                try { $script:AutoCloseTimer.Stop() } catch {}
                try { $Window.DialogResult = $false } catch {}
                try { $Window.Close() } catch {}
                return
            }
            $m = [math]::Floor($script:AutoCloseRemaining/60)
            $s = $script:AutoCloseRemaining % 60
            $txtStatus.Text = "Auto-close in ${m}m ${s}s"
        } catch {}
    })
    $script:AutoCloseTimer.Start()
    
    # Apply device-specific defaults if matched in RoleDatabase.json
    if ($script:DeviceFound -and $script:MatchedDevice) {
        # Pre-populate device name from JSON if available
        if ($script:MatchedDevice.DeviceName) {
            $rbManualName.IsChecked = $true
            $txtManualName.Text = $script:MatchedDevice.DeviceName.ToString().Trim()
        }
        
        # Set default to EntraID Join
        $rbEntraID.IsChecked = $true
        
        # Pre-populate Primary User UPN if available
        if ($script:MatchedDevice.PrimaryUserUPN) {
            $txtPrimaryUserUPN.Text = $script:MatchedDevice.PrimaryUserUPN.ToString().Trim()
        }
        
        # Set the role based on Category from JSON
        if ($script:MatchedDevice.Category) {
            $categoryValue = $script:MatchedDevice.Category.ToString().Trim()
            # Find and select the matching role in the ComboBox
            for ($i = 0; $i -lt $cmbUserRole.Items.Count; $i++) {
                $item = $cmbUserRole.Items[$i]
                if ($item.Content -eq $categoryValue) {
                    $cmbUserRole.SelectedIndex = $i
                    break
                }
            }
        }
    }
    else {
        # No device match or no JSON found - default to Local Workgroup
        $rbWorkgroup.IsChecked = $true
    }
    
    # Apply initial visual state for radios and labels
    try { Set-PanelVisualState -noNameSelected ([bool]$rbNoName.IsChecked) -manualSelected ([bool]$rbManualName.IsChecked) -hardwareSelected ([bool]$rbHardwareName.IsChecked) } catch {}

    # Show the form
    $result = $Window.ShowDialog()
    
    # Create and return PSObject with form results
    if ($result -eq $true) {
        $FormResults = [PSCustomObject]@{
            JSONDBMatch = $script:DeviceFound
            GitHubJSONDB = $script:GitHubJSONDB
            NamingStrategy = $script:NamingStrategy
            GeneratedComputerName = $script:GeneratedComputerName
            DomainSuffix = $script:DomainSuffix
            HardwareIdType = $script:HardwareIdType
            WorkplaceJoin = $script:WorkplaceJoin
            SelectedUserRole = $script:SelectedUserRole
            AutopilotGroupTag = $script:AutopilotGroupTag
            DomainJoinOU = $script:OnlineOU
            AssetTag = if ($LocalInfo.ContainsKey('AssetTag') -and -not [string]::IsNullOrWhiteSpace($LocalInfo['AssetTag'])) { $LocalInfo['AssetTag'] } else { 'NA' }
            DomainJoinSelected = ($script:WorkplaceJoin -eq 'ODJ')
            EntraIDUserUPN = $script:EntraIDUserUPN
            SelectedSoftware = $script:SelectedSoftware
            SelectedSoftwareMap = $script:SelectedSoftwareMap
            SelectedSoftwareCsv = $script:SelectedSoftwareCsv
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
        
        return $FormResults
        
    } else {
        Write-Host "`nForm was cancelled." -ForegroundColor Yellow
        
        # Return object indicating cancellation
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
    Add-Content -Value $Line -Path $LogPath
    # Roll log file over at size threshold
    if ((Get-Item $Global:LogFilePath).Length / 1KB -gt $Global:LogFileSize) {
        $log = $Global:LogFilePath
        Remove-Item ($log.Replace(".log", ".lo_"))
        Rename-Item $Global:LogFilePath ($log.Replace(".log", ".lo_")) -Force
    }
} 

function Get-DeployRFrontEndApps {
    #This will connect with the DeployR Server and pull a list of Apps that are specified to show in the front end
    
    try {
        if (Test-Path -path 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'){
            Import-Module 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility' -ErrorAction SilentlyContinue
        }
        if (!(Get-Module -Name DeployR.Utility)) {
            Import-Module DeployR.Utility -ErrorAction SilentlyContinue
        }
    }
    catch {}
    if ((Get-Module -name "DeployR.Utility") -and (-not (test-path -path "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"))) {
        IF ( ${TSEnv:DEPLOYRCLIENTPASSCODE} -ne $null){
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
    $Apps = Get-DeployRApplication
    $FrontEndApps = $apps | Where-Object {$_.description -match "Frontend = TRUE"}
    return $FrontEndApps
}
#
$FormResults = Get-InputFormData
try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
    # Fucntion for Logging
    #Borrowed from https://github.com/hypercube33/SCCM/blob/master/Detect_Report_Remove_1909_G3%20Scrubbed.ps1
    $Global:LogFolderPath = ${TSEnv:_DEPLOYRLOGS}
    
}
catch {
    Write-Warning "DeployR.Utility module not found. Environment variables will be set in the standard environment."
}
# Start up the logs
if (!($Global:LogFolderPath)) {
    if ($env:SystemDrive -eq "X:") {
        $Global:LogFolderPath = "$env:SystemDrive\_2P\Logs"
    }
    else {
        # Prefer user-writable temp folder to avoid permission issues when not elevated
        if ($env:TEMP) { $Global:LogFolderPath = Join-Path -Path $env:TEMP -ChildPath 'DeployRLogs' }
        elseif (Test-Path -Path 'C:\Windows\Temp') { $Global:LogFolderPath = 'C:\Windows\Temp\DeployRLogs' }
        else { $Global:LogFolderPath = Join-Path -Path $env:USERPROFILE -ChildPath 'DeployRLogs' }
    }
}
$Global:LogFilePath = "$($Global:LogFolderPath)\FrontEnd.log"
$Global:LogFileSize   = "40"

Start-CMTraceLog -Path $Global:LogFilePath
Write-CMTraceLog -Message "=====================================================" -Type "Info" -Component "Main"
Write-CMTraceLog -Message "Starting Script..." -Type "Info" -Component "Main"
Write-CMTraceLog -Message "=====================================================" -Type "Info" -Component "Main"
write-host "========================================" -ForegroundColor DarkGray
# Set the provided variables
if ((Get-Module -name "DeployR.Utility") -and (-not (test-path -path "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"))) {
    $DEPLOYRCLIENTPASSCODE = ${TSEnv:DEPLOYRCLIENTPASSCODE}
    ${TSEnv:GitHubJSONDB} = $script:GitHubJSONDB
    ${TSEnv:JSONDBMatch} = $FormResults.JSONDBMatch
    ${TSEnv:NamingStrategy} = $FormResults.NamingStrategy
    ${TSEnv:ComputerName} = $FormResults.GeneratedComputerName
    ${TSEnv:DomainSuffix} = $FormResults.DomainSuffix
    ${TSEnv:HardwareIdType} = $FormResults.HardwareIdType
    ${TSEnv:WorkplaceJoin} = $FormResults.WorkplaceJoin
    if ($FormResults.EntraIDUserUPN) {
        ${TSEnv:EntraIDUserUPN} = $FormResults.EntraIDUserUPN
        ${TSEnv:ENTRAUPN} = $FormResults.EntraIDUserUPN
    }
    if ($FormResults.DomainJoinOU) {
        ${TSEnv:DomainJoinOU} = $FormResults.DomainJoinOU
    }
    # Export AssetTag as TS variable
    if ($FormResults.AssetTag) {
        ${TSEnv:AssetTag} = $FormResults.AssetTag
    }
    if (($FormResults.WorkplaceJoin) -eq "Autopilot"){
        if ($FormResults.AutopilotGroupTag) {
            ${TSEnv:AutopilotGroupTag} = $FormResults.AutopilotGroupTag
        }
    }
    
    ${TSEnv:SelectedUserRole} = $FormResults.SelectedUserRole
    ${TSEnv:SelectedSoftwareCsv} = $FormResults.SelectedSoftwareCsv
    
    Write-CMTraceLog -Message  "Set DeployR TS Environment Variables:" -Type "Info" -Component "Main"
    Write-CMTraceLog -Message "GitHubJSONDB = $(${TSEnv:GitHubJSONDB})" -Type "Info" -Component "Main"
    Write-CMTraceLog -Message "JSONDBMatch = $(${TSEnv:JSONDBMatch})" -Type "Info" -Component "Main"
    Write-CMTraceLog -Message "NamingStrategy = $(${TSEnv:NamingStrategy})" -Type "Info" -Component "Main"
    Write-CMTraceLog -Message "ComputerName = $(${TSEnv:ComputerName})" -Type "Info" -Component "Main"
    Write-CMTraceLog -Message "DomainSuffix = $(${TSEnv:DomainSuffix})" -Type "Info" -Component "Main"
    Write-CMTraceLog -Message "HardwareIdType = $(${TSEnv:HardwareIdType})" -Type "Info" -Component "Main"
    Write-CMTraceLog -Message "WorkplaceJoin = $(${TSEnv:WorkplaceJoin})" -Type "Info" -Component "Main"
    if ($FormResults.EntraIDUserUPN){
        Write-CMTraceLog -Message "EntraIDUserUPN = $(${TSEnv:EntraIDUserUPN})" -Type "Info" -Component "Main"
    }
    if ($FormResults.AutopilotGroupTag){
        Write-CMTraceLog -Message "AutopilotGroupTag = $(${TSEnv:AutopilotGroupTag})" -Type "Info" -Component "Main"
    }
    if ($FormResults.DomainJoinOU){
        Write-CMTraceLog -Message "DomainJoinOU = $(${TSEnv:DomainJoinOU})" -Type "Info" -Component "Main"
    }
    if ($FormResults.AssetTag -and $FormResults.AssetTag -ne 'NA'){
        Write-CMTraceLog -Message "AssetTag = $(${TSEnv:AssetTag})" -Type "Info" -Component "Main"
    }
    Write-CMTraceLog -Message "SelectedUserRole = $(${TSEnv:SelectedUserRole})" -Type "Info" -Component "Main"
    
    # Export individual software selections as Install_<id> = 'True'/'False'
    try {
        foreach ($kv in $FormResults.SelectedSoftwareMap.GetEnumerator()) {
            $key = $kv.Key
            $val = if ($kv.Value) { 'True' } else { 'False' }
            $varName = "Install_$($key)"
            Set-Item -Path "TSENV:$VarName" -Value $val
            Write-CMTraceLog -Message "$varName = $val" -Type "Info" -Component "Main"
        }
    } catch {
        Write-Warning "Failed to export individual software TS variables: $_"
    }
    
}
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
    write-Host "ComputerName = $($env:ComputerName)" -ForegroundColor Green
    write-Host "DomainSuffix = $($env:DomainSuffix)" -ForegroundColor Green
    if ($env:HardwareIdType) { write-Host "HardwareIdType = $($env:HardwareIdType)" -ForegroundColor Green }
    write-Host "WorkplaceJoin = $($env:WorkplaceJoin)" -ForegroundColor Green
    if ($env:DomainJoinOU) { write-Host "DomainJoinOU = $($env:DomainJoinOU)" -ForegroundColor Green }
    if ($env:AssetTag -and $env:AssetTag -ne 'NA') { write-Host "AssetTag = $($env:AssetTag)" -ForegroundColor Green }
    if ($env:EntraIDUserUPN) { write-Host "EntraIDUserUPN = $($env:EntraIDUserUPN)" -ForegroundColor Green }
    write-Host "SelectedUserRole = $($env:SelectedUserRole)" -ForegroundColor Green
    write-Host "AutopilotGroupTag = $($env:AutopilotGroupTag)" -ForegroundColor Green
    write-Host "SelectedSoftwareCsv = $($env:SelectedSoftwareCsv)" -ForegroundColor Green
}