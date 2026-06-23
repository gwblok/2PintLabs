# THIS SCRIPT MUST BE RUN First, it allows you to choose what you want to cache then creates a JSON file of that information for the next script to use.
# THIS SCRIPT requires the "Run COMMAND LINE Script" with the command: pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ".\FrontEnd-PreCacheChooser.ps1" -Wait -NoNewWindow -PassThru
#   You will need to have this in a content item and have the content item associated with this step.


$ScriptVersion = '26.2.17.21.12'


#Region Functions
# Helper function to stop transcription

Function Get-InputFormData {
    
    
    Add-Type -AssemblyName PresentationFramework
    
    $ContentItems = Get-DeployRContentItemVersion -Status Any | Where-Object { $null -ne $_.relativePath -and $_.relativePath -ne "" } 
    $Other = $ContentItems | Where-Object { $_.contentItemPurpose -eq "Other" }
    $Application = $ContentItems | Where-Object { $_.contentItemPurpose -eq "Application" }
    $DriverPack = $ContentItems | Where-Object { $_.contentItemPurpose -eq "DriverPack" }
    $OperatingSystem = $ContentItems | Where-Object { $_.contentItemPurpose -eq "OperatingSystem" }
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
    $WindowTitle = "PreCache Content Chooser"
    $HeaderText = "System Configuration - $Usage"
    $DomainSuffixLabel = if ($Usage -eq "ConfigMgr") { "Domain Suffix, used as Domain for Domain Join:" } else { "Domain Suffix (optional):" }
    $DomainJoinRadioLabel = if ($Usage -eq "ConfigMgr") { "Domain Join" } else { "Offline Domain Join" }

    # XAML Form Definition
    [xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="$WindowTitle" 
    Height="700" 
        Width="540"
        MinHeight="400"
        MinWidth="520"
        WindowStartupLocation="CenterScreen"
        Topmost="True"
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
            <TabItem Header="PreCache">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8">
                    <StackPanel Margin="0,6,0,0">
                        <TextBlock Text="PreCache Configuration" FontSize="14" FontWeight="Bold" Margin="0,0,0,10"/>

                        <TextBlock Text="DeployR Server" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,4"/>
                        <TextBlock Name="txtDeployRServer" Text="" FontSize="11" Foreground="Gray" Margin="12,0,0,8" TextWrapping="Wrap"/>

                        <Separator Margin="0,4,0,8"/>

                        <TextBlock Text="Auto-Selection" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,4"/>
                        <TextBlock FontSize="11" Foreground="Gray" Margin="12,0,0,4" TextWrapping="Wrap" Text="Items with Active status and the highest version number are automatically selected for pre-caching."/>
                        <TextBlock FontSize="11" Foreground="Gray" Margin="12,0,0,8" TextWrapping="Wrap" Text="You can adjust selections on each tab before confirming. Pre-caching will begin once this dialog is closed by clicking OK."/>

                        <Separator Margin="0,4,0,8"/>

                        <TextBlock Text="Boot Images" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,4"/>
                        <CheckBox x:Name="chkPreCacheBootImages" Content="PreCache all Boot Images" Margin="12,4,0,0" FontSize="12"/>

                        <Separator Margin="0,8,0,8"/>

                        <TextBlock Text="Bulk Selection" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,4"/>
                        <TextBlock FontSize="11" Foreground="Gray" Margin="12,0,0,6" TextWrapping="Wrap" Text="Select or deselect all content items across all tabs."/>
                        <StackPanel Orientation="Horizontal" Margin="12,0,0,0">
                            <Button x:Name="btnSelectAll" Content="Select All" Width="100" Height="28" Margin="0,0,8,0" FontSize="11"/>
                            <Button x:Name="btnDeselectAll" Content="Deselect All" Width="100" Height="28" Margin="0,0,0,0" FontSize="11"/>
                        </StackPanel>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
            
            <TabItem Header="Operating Systems">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8">
                    <StackPanel Margin="0,6,0,0">
                        <TextBlock Text="Operating Systems" FontSize="13" FontWeight="Bold" Margin="0,0,0,5"/>
                        <StackPanel Name="spOperatingSystemsList" Margin="6,4,0,0" />
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
            
            <TabItem Header="Drivers">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8">
                    <StackPanel Margin="0,6,0,0">
                        <TextBlock Text="Driver Packs" FontSize="13" FontWeight="Bold" Margin="0,0,0,5"/>
                        <StackPanel Name="spDriverPacksList" Margin="6,4,0,0" />
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
            
            <TabItem Header="Other">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8">
                    <StackPanel Margin="0,6,0,0">
                        <TextBlock Text="Other" FontSize="13" FontWeight="Bold" Margin="0,0,0,5"/>
                        <StackPanel Name="spOtherList" Margin="6,4,0,0" />
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
            
            <TabItem Header="Applications">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8">
                    <StackPanel Margin="0,6,0,0">
                        <TextBlock Text="Applications" FontSize="13" FontWeight="Bold" Margin="0,0,0,8"/>
                        <StackPanel Name="spApplicationsList" Margin="6,4,0,0" />
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
    $txtStatus = $Window.FindName("txtStatus")
    $txtWarning = $Window.FindName("txtWarning")
    $btnOK = $Window.FindName("btnOK")
    $btnCancel = $Window.FindName("btnCancel")
    $spApplicationsList = $Window.FindName("spApplicationsList")
    $chkPreCacheBootImages = $Window.FindName("chkPreCacheBootImages")
    $txtDeployRServer = $Window.FindName("txtDeployRServer")
    $spOperatingSystemsList = $Window.FindName("spOperatingSystemsList")
    $spDriverPacksList = $Window.FindName("spDriverPacksList")
    $spOtherList = $Window.FindName("spOtherList")
    $btnSelectAll = $Window.FindName("btnSelectAll")
    $btnDeselectAll = $Window.FindName("btnDeselectAll")
    
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

    # Populate DeployR server info on PreCache tab
    try {
        $deployRHost = Get-DeployRHost
        if ($deployRHost) {
            $serverInfo = @()
            if ($deployRHost.ServerUrl) { $serverInfo += "Server: $($deployRHost.ServerUrl)" }
            if ($deployRHost.HostName) { $serverInfo += "Host: $($deployRHost.HostName)" }
            if ($deployRHost.Version) { $serverInfo += "Version: $($deployRHost.Version)" }
            $txtDeployRServer.Text = if ($serverInfo.Count -gt 0) { $serverInfo -join "`n" } else { $deployRHost.ToString() }
        } else {
            $txtDeployRServer.Text = "Not connected"
        }
    }
    catch {
        $txtDeployRServer.Text = "Unable to retrieve server info"
    }

    # Populate Operating Systems list from $OperatingSystem
    if ($OperatingSystem -and $OperatingSystem.Count -gt 0) {
        # Determine which items to auto-check: Active status with highest versionNo per name
        $osAutoCheck = @{}
        $OperatingSystem | Where-Object { $_.status -eq 'Active' } | Group-Object -Property Name | ForEach-Object {
            $highest = $_.Group | Sort-Object -Property versionNo -Descending | Select-Object -First 1
            $osAutoCheck[$highest.Id] = $true
        }
        foreach ($os in ($OperatingSystem | Sort-Object -Property Name)) {
            try {
                # Create a StackPanel to hold the checkbox with details
                $osPanel = New-Object System.Windows.Controls.StackPanel
                $osPanel.Orientation = 'Vertical'
                $osPanel.Margin = '0,2,0,6'

                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Margin = '6,0,0,0'
                $cb.FontSize = 12
                $cb.FontWeight = 'SemiBold'
                $cb.Tag = @{ Id = $os.Id; ContentItemId = $os.contentItemId; Name = $os.Name; Description = $os.Description; VersionNo = $os.versionNo; Status = $os.status }
                if ($osAutoCheck.ContainsKey($os.Id)) { $cb.IsChecked = $true }

                # Build display: Name (vN)
                $displayText = $os.Name
                if ($os.versionNo) { $displayText += " (v$($os.versionNo))" }
                $cb.Content = $displayText
                $osPanel.Children.Add($cb) | Out-Null

                # Add description as a sub-label if available
                if ($os.Description) {
                    $descText = New-Object System.Windows.Controls.TextBlock
                    $descText.Text = $os.Description
                    $descText.FontSize = 11
                    $descText.Foreground = [System.Windows.Media.Brushes]::Gray
                    $descText.Margin = '24,0,0,0'
                    $descText.TextWrapping = 'Wrap'
                    $osPanel.Children.Add($descText) | Out-Null
                }

                # Add status info
                if ($os.status) {
                    $detailText = New-Object System.Windows.Controls.TextBlock
                    $detailText.Text = "Status: $($os.status)"
                    $detailText.FontSize = 10
                    $detailText.Foreground = [System.Windows.Media.Brushes]::DarkGray
                    $detailText.Margin = '24,0,0,0'
                    $osPanel.Children.Add($detailText) | Out-Null
                }

                $spOperatingSystemsList.Children.Add($osPanel) | Out-Null
            }
            catch {
                Write-Warning "Failed to add OS '$($os.Name)': $_"
            }
        }
    }
    else {
        $noOsText = New-Object System.Windows.Controls.TextBlock
        $noOsText.Text = "No operating systems available"
        $noOsText.FontSize = 11
        $noOsText.Foreground = [System.Windows.Media.Brushes]::Gray
        $noOsText.Margin = '6,4,0,4'
        $spOperatingSystemsList.Children.Add($noOsText) | Out-Null
    }

    # Populate Driver Packs list from $DriverPack
    if ($DriverPack -and $DriverPack.Count -gt 0) {
        $dpAutoCheck = @{}
        $DriverPack | Where-Object { $_.status -eq 'Active' } | Group-Object -Property Name | ForEach-Object {
            $highest = $_.Group | Sort-Object -Property versionNo -Descending | Select-Object -First 1
            $dpAutoCheck[$highest.Id] = $true
        }
        foreach ($dp in ($DriverPack | Sort-Object -Property Name)) {
            try {
                $dpPanel = New-Object System.Windows.Controls.StackPanel
                $dpPanel.Orientation = 'Vertical'
                $dpPanel.Margin = '0,2,0,6'

                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Margin = '6,0,0,0'
                $cb.FontSize = 12
                $cb.FontWeight = 'SemiBold'
                $cb.Tag = @{ Id = $dp.Id; ContentItemId = $dp.contentItemId; Name = $dp.Name; Description = $dp.Description; VersionNo = $dp.versionNo; Status = $dp.status }
                if ($dpAutoCheck.ContainsKey($dp.Id)) { $cb.IsChecked = $true }
                $displayText = $dp.Name
                if ($dp.versionNo) { $displayText += " (v$($dp.versionNo))" }
                $cb.Content = $displayText
                $dpPanel.Children.Add($cb) | Out-Null

                if ($dp.Description) {
                    $descText = New-Object System.Windows.Controls.TextBlock
                    $descText.Text = $dp.Description
                    $descText.FontSize = 11
                    $descText.Foreground = [System.Windows.Media.Brushes]::Gray
                    $descText.Margin = '24,0,0,0'
                    $descText.TextWrapping = 'Wrap'
                    $dpPanel.Children.Add($descText) | Out-Null
                }

                if ($dp.status) {
                    $detailText = New-Object System.Windows.Controls.TextBlock
                    $detailText.Text = "Status: $($dp.status)"
                    $detailText.FontSize = 10
                    $detailText.Foreground = [System.Windows.Media.Brushes]::DarkGray
                    $detailText.Margin = '24,0,0,0'
                    $dpPanel.Children.Add($detailText) | Out-Null
                }

                $spDriverPacksList.Children.Add($dpPanel) | Out-Null
            }
            catch {
                Write-Warning "Failed to add Driver Pack '$($dp.Name)': $_"
            }
        }
    }
    else {
        $noDpText = New-Object System.Windows.Controls.TextBlock
        $noDpText.Text = "No driver packs available"
        $noDpText.FontSize = 11
        $noDpText.Foreground = [System.Windows.Media.Brushes]::Gray
        $noDpText.Margin = '6,4,0,4'
        $spDriverPacksList.Children.Add($noDpText) | Out-Null
    }

    # Populate Other list from $Other
    if ($Other -and $Other.Count -gt 0) {
        $otherAutoCheck = @{}
        $Other | Where-Object { $_.status -eq 'Active' } | Group-Object -Property Name | ForEach-Object {
            $highest = $_.Group | Sort-Object -Property versionNo -Descending | Select-Object -First 1
            $otherAutoCheck[$highest.Id] = $true
        }
        foreach ($otherItem in ($Other | Sort-Object -Property Name)) {
            try {
                $otherPanel = New-Object System.Windows.Controls.StackPanel
                $otherPanel.Orientation = 'Vertical'
                $otherPanel.Margin = '0,2,0,6'

                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Margin = '6,0,0,0'
                $cb.FontSize = 12
                $cb.FontWeight = 'SemiBold'
                $cb.Tag = @{ Id = $otherItem.Id; ContentItemId = $otherItem.contentItemId; Name = $otherItem.Name; Description = $otherItem.Description; VersionNo = $otherItem.versionNo; Status = $otherItem.status }
                if ($otherAutoCheck.ContainsKey($otherItem.Id)) { $cb.IsChecked = $true }
                $displayText = $otherItem.Name
                if ($otherItem.versionNo) { $displayText += " (v$($otherItem.versionNo))" }
                $cb.Content = $displayText
                $otherPanel.Children.Add($cb) | Out-Null

                if ($otherItem.Description) {
                    $descText = New-Object System.Windows.Controls.TextBlock
                    $descText.Text = $otherItem.Description
                    $descText.FontSize = 11
                    $descText.Foreground = [System.Windows.Media.Brushes]::Gray
                    $descText.Margin = '24,0,0,0'
                    $descText.TextWrapping = 'Wrap'
                    $otherPanel.Children.Add($descText) | Out-Null
                }

                if ($otherItem.status) {
                    $detailText = New-Object System.Windows.Controls.TextBlock
                    $detailText.Text = "Status: $($otherItem.status)"
                    $detailText.FontSize = 10
                    $detailText.Foreground = [System.Windows.Media.Brushes]::DarkGray
                    $detailText.Margin = '24,0,0,0'
                    $otherPanel.Children.Add($detailText) | Out-Null
                }

                $spOtherList.Children.Add($otherPanel) | Out-Null
            }
            catch {
                Write-Warning "Failed to add Other item '$($otherItem.Name)': $_"
            }
        }
    }
    else {
        $noOtherText = New-Object System.Windows.Controls.TextBlock
        $noOtherText.Text = "No other items available"
        $noOtherText.FontSize = 11
        $noOtherText.Foreground = [System.Windows.Media.Brushes]::Gray
        $noOtherText.Margin = '6,4,0,4'
        $spOtherList.Children.Add($noOtherText) | Out-Null
    }

    # Populate Applications list from $Application
    if ($Application -and $Application.Count -gt 0) {
        $appAutoCheck = @{}
        $Application | Where-Object { $_.status -eq 'Active' } | Group-Object -Property Name | ForEach-Object {
            $highest = $_.Group | Sort-Object -Property versionNo -Descending | Select-Object -First 1
            $appAutoCheck[$highest.Id] = $true
        }
        foreach ($app in ($Application | Sort-Object -Property Name)) {
            try {
                $appPanel = New-Object System.Windows.Controls.StackPanel
                $appPanel.Orientation = 'Vertical'
                $appPanel.Margin = '0,2,0,6'

                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Margin = '6,0,0,0'
                $cb.FontSize = 12
                $cb.FontWeight = 'SemiBold'
                $cb.Tag = @{ Id = $app.Id; ContentItemId = $app.contentItemId; Name = $app.Name; Description = $app.Description; VersionNo = $app.versionNo; Status = $app.status }
                if ($appAutoCheck.ContainsKey($app.Id)) { $cb.IsChecked = $true }
                $displayText = $app.Name
                if ($app.versionNo) { $displayText += " (v$($app.versionNo))" }
                $cb.Content = $displayText
                $appPanel.Children.Add($cb) | Out-Null

                if ($app.Description) {
                    $descText = New-Object System.Windows.Controls.TextBlock
                    $descText.Text = $app.Description
                    $descText.FontSize = 11
                    $descText.Foreground = [System.Windows.Media.Brushes]::Gray
                    $descText.Margin = '24,0,0,0'
                    $descText.TextWrapping = 'Wrap'
                    $appPanel.Children.Add($descText) | Out-Null
                }

                if ($app.status) {
                    $detailText = New-Object System.Windows.Controls.TextBlock
                    $detailText.Text = "Status: $($app.status)"
                    $detailText.FontSize = 10
                    $detailText.Foreground = [System.Windows.Media.Brushes]::DarkGray
                    $detailText.Margin = '24,0,0,0'
                    $appPanel.Children.Add($detailText) | Out-Null
                }

                $spApplicationsList.Children.Add($appPanel) | Out-Null
            }
            catch {
                Write-Warning "Failed to add application '$($app.Name)': $_"
            }
        }
    }
    else {
        $noAppsText = New-Object System.Windows.Controls.TextBlock
        $noAppsText.Text = "No applications available"
        $noAppsText.FontSize = 11
        $noAppsText.Foreground = [System.Windows.Media.Brushes]::Gray
        $noAppsText.Margin = '6,4,0,4'
        $spApplicationsList.Children.Add($noAppsText) | Out-Null
    }

    # Initialize option OU script variable
    $script:OptionOU = $null
    $script:SelectedApplications = @()

    # Load Logo from file path BEFORE showing the form
    if (!$logoLoaded -and ![string]::IsNullOrWhiteSpace($LogoPath) -and (Test-Path $LogoPath)) {
        try {
            $stream = [System.IO.File]::OpenRead($LogoPath)
            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.StreamSource = $stream
            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.EndInit()
            $bitmap.Freeze()
            $stream.Close()
            $stream.Dispose()
            $imgLogo.Source = $bitmap
            $logoLoaded = $true
        }
        catch {
            Write-Warning "Failed to load logo from file: $LogoPath - $_"
            try {
                $imgLogo.Source = $LogoPath
                $logoLoaded = $true
            } catch {}
        }
    }
    
    if (!$logoLoaded) {
        $imgLogo.Visibility = "Collapsed"
    }
    
    # Register button click events BEFORE showing the form
    $btnOK.Add_Click({
        try { if ($script:AutoCloseTimer) { $script:AutoCloseTimer.Stop() } } catch {}
        $Window.DialogResult = $true
        $Window.Close()
    })
    
    $btnCancel.Add_Click({
        try { if ($script:AutoCloseTimer) { $script:AutoCloseTimer.Stop() } } catch {}
        $Window.DialogResult = $false
        $Window.Close()
    })

    # Select All / Deselect All button handlers
    $btnSelectAll.Add_Click({
        $chkPreCacheBootImages.IsChecked = $true
        foreach ($sp in @($spOperatingSystemsList, $spDriverPacksList, $spOtherList, $spApplicationsList)) {
            if ($null -ne $sp) {
                foreach ($panel in $sp.Children) {
                    if ($panel -is [System.Windows.Controls.StackPanel]) {
                        foreach ($child in $panel.Children) {
                            if ($child -is [System.Windows.Controls.CheckBox]) { $child.IsChecked = $true }
                        }
                    }
                }
            }
        }
    })

    $btnDeselectAll.Add_Click({
        $chkPreCacheBootImages.IsChecked = $false
        foreach ($sp in @($spOperatingSystemsList, $spDriverPacksList, $spOtherList, $spApplicationsList)) {
            if ($null -ne $sp) {
                foreach ($panel in $sp.Children) {
                    if ($panel -is [System.Windows.Controls.StackPanel]) {
                        foreach ($child in $panel.Children) {
                            if ($child -is [System.Windows.Controls.CheckBox]) { $child.IsChecked = $false }
                        }
                    }
                }
            }
        }
    })
    
    # Setup auto-close timer BEFORE showing the form
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

    # Show the form
    $result = $Window.ShowDialog()
    
    # Capture selections AFTER window closes
    if ($result -eq $true) {
        # Capture selected operating systems
        $script:SelectedOperatingSystems = @()
        try {
            if ($null -ne $spOperatingSystemsList -and $spOperatingSystemsList.Children.Count -gt 0) {
                foreach ($panel in $spOperatingSystemsList.Children) {
                    if ($panel -is [System.Windows.Controls.StackPanel]) {
                        foreach ($child in $panel.Children) {
                            if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsChecked) {
                                $tagData = $child.Tag
                                $script:SelectedOperatingSystems += [PSCustomObject]@{
                                    Id = $tagData.Id
                                    ContentItemId = $tagData.ContentItemId
                                    Name = $tagData.Name
                                    Description = $tagData.Description
                                    VersionNo = $tagData.VersionNo
                                    Status = $tagData.Status
                                }
                            }
                        }
                    }
                }
            }
            Write-Host "Captured $($script:SelectedOperatingSystems.Count) selected operating systems" -ForegroundColor Cyan
        }
        catch {
            Write-Host "Error capturing operating systems: $_" -ForegroundColor Yellow
        }

        # Capture selected driver packs
        $script:SelectedDriverPacks = @()
        try {
            if ($null -ne $spDriverPacksList -and $spDriverPacksList.Children.Count -gt 0) {
                foreach ($panel in $spDriverPacksList.Children) {
                    if ($panel -is [System.Windows.Controls.StackPanel]) {
                        foreach ($child in $panel.Children) {
                            if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsChecked) {
                                $tagData = $child.Tag
                                $script:SelectedDriverPacks += [PSCustomObject]@{
                                    Id = $tagData.Id
                                    ContentItemId = $tagData.ContentItemId
                                    Name = $tagData.Name
                                    Description = $tagData.Description
                                    VersionNo = $tagData.VersionNo
                                    Status = $tagData.Status
                                }
                            }
                        }
                    }
                }
            }
            Write-Host "Captured $($script:SelectedDriverPacks.Count) selected driver packs" -ForegroundColor Cyan
        }
        catch {
            Write-Host "Error capturing driver packs: $_" -ForegroundColor Yellow
        }

        # Capture selected other items
        $script:SelectedOther = @()
        try {
            if ($null -ne $spOtherList -and $spOtherList.Children.Count -gt 0) {
                foreach ($panel in $spOtherList.Children) {
                    if ($panel -is [System.Windows.Controls.StackPanel]) {
                        foreach ($child in $panel.Children) {
                            if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsChecked) {
                                $tagData = $child.Tag
                                $script:SelectedOther += [PSCustomObject]@{
                                    Id = $tagData.Id
                                    ContentItemId = $tagData.ContentItemId
                                    Name = $tagData.Name
                                    Description = $tagData.Description
                                    VersionNo = $tagData.VersionNo
                                    Status = $tagData.Status
                                }
                            }
                        }
                    }
                }
            }
            Write-Host "Captured $($script:SelectedOther.Count) selected other items" -ForegroundColor Cyan
        }
        catch {
            Write-Host "Error capturing other items: $_" -ForegroundColor Yellow
        }

        # Capture selected applications
        $script:SelectedApplications = @()
        try {
            if ($null -ne $spApplicationsList -and $spApplicationsList.Children.Count -gt 0) {
                foreach ($panel in $spApplicationsList.Children) {
                    if ($panel -is [System.Windows.Controls.StackPanel]) {
                        foreach ($child in $panel.Children) {
                            if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsChecked) {
                                $tagData = $child.Tag
                                $script:SelectedApplications += [PSCustomObject]@{
                                    Id = $tagData.Id
                                    ContentItemId = $tagData.ContentItemId
                                    Name = $tagData.Name
                                    Description = $tagData.Description
                                    VersionNo = $tagData.VersionNo
                                    Status = $tagData.Status
                                }
                            }
                        }
                    }
                }
            }
            Write-Host "Captured $($script:SelectedApplications.Count) selected applications" -ForegroundColor Cyan
        }
        catch {
            Write-Host "Error capturing applications: $_" -ForegroundColor Yellow
        }
    }
    
    # Create and return PSObject with form results
    if ($result -eq $true) {
        $FormResults = [PSCustomObject]@{
            FormSubmitted = $true
            PreCacheAllBootImages = ($chkPreCacheBootImages.IsChecked -eq $true)
            SelectedOperatingSystems = $script:SelectedOperatingSystems
            OperatingSystemCount = $script:SelectedOperatingSystems.Count
            SelectedDriverPacks = $script:SelectedDriverPacks
            DriverPackCount = $script:SelectedDriverPacks.Count
            SelectedOther = $script:SelectedOther
            OtherCount = $script:SelectedOther.Count
            SelectedApplications = $script:SelectedApplications
            ApplicationCount = $script:SelectedApplications.Count
            HardwareInfo = @{
                Make = $LocalInfo['Make']
                Model = $LocalInfo['ModelAlias']
                System = $LocalInfo['SystemAlias']
                SerialNumber = $SerialNumber
                Memory = $Memory
                MAC = $macList
                IP = $ipList
                Gateway = $gwList
                AssetTag = $AssetTag
            }
        }
        
        Write-Host "`n=== Form Results ===" -ForegroundColor Cyan
        Write-Host "Applications Selected: $($FormResults.ApplicationCount)" -ForegroundColor Green
        if ($script:SelectedApplications.Count -gt 0) {
            Write-Host "Selected Applications:" -ForegroundColor Green
            foreach ($app in $script:SelectedApplications) {
                Write-Host "  - $($app.DisplayName) (ID: $($app.Id))" -ForegroundColor Green
            }
        }
        Write-Host "`n=== Hardware Information ===" -ForegroundColor Cyan
        Write-Host "Make: $($LocalInfo['Make'])" -ForegroundColor Green
        Write-Host "Model: $($LocalInfo['ModelAlias'])" -ForegroundColor Green
        Write-Host "System: $($LocalInfo['SystemAlias'])" -ForegroundColor Green
        Write-Host "Serial Number: $SerialNumber" -ForegroundColor Green
        
        try { Stop-FrontendTranscription } catch {}
        return $FormResults
        
    } else {
        Write-Host "`nForm was cancelled." -ForegroundColor Yellow
        try { Stop-FrontendTranscription } catch {}
        return [PSCustomObject]@{
            FormSubmitted = $false
            HardwareInfo = @{}
        }
    }
}

#Function to Test if URL exists
Function Test-URLExists {
    param (
    [string]$URL
    )
    try {
        $request = [System.Net.WebRequest]::Create($URL)
        $request.Method = "HEAD"
        $response = $request.GetResponse()
        $response.Close()
        return $true
    }
    catch {
        return $false
    }
}







#
#endregion Functions


#######################################################
# SCRIPT Execution
#######################################################
#Region Script to Run Frontend and gather Info
try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
    $Global:LogFolderPath = ${TSEnv:_DEPLOYRLOGS}
}
catch {
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
try {
    if ($Global:LogFolderPath) {
        if (!(Test-Path -Path $Global:LogFolderPath)) { New-Item -ItemType Directory -Path $Global:LogFolderPath -Force | Out-Null }
        $transcriptPath = "$Global:LogFolderPath\FrontendTranscription.log"
        Start-Transcript -Path $transcriptPath -Force -ErrorAction SilentlyContinue
        Write-Host "Started PowerShell transcription to $transcriptPath" -ForegroundColor Green
    } else {
        Write-Warning "Transcript not started: LogFolderPath is not set."
    }
} catch {
    Write-Warning "Failed to start transcript: $_"
}



write-host "=====================================================" -ForegroundColor DarkGray
Write-Host "Starting Script version $ScriptVersion" -ForegroundColor Green
write-host "=====================================================" -ForegroundColor DarkGray

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

$FormResults = Get-InputFormData

#Output FormResults to JSON file for use by other processes if needed
if ($FormResults -and $Global:LogFolderPath) {
    $jsonPath = Join-Path -Path $Global:LogFolderPath -ChildPath "FrontendFormResults.json"
    try {
        $FormResults | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding UTF8
        Write-Host "Form results saved to JSON file: $jsonPath" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to save form results to JSON file: $_"
    }
}

#endregion Script to Run Frontend and gather Info
