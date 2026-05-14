$ScriptVersion = '0.1.0'

function Write-CMTraceLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info','Warning','Error')][string]$Type = 'Info',
        [string]$Component = 'UIPlusPlusRipOff'
    )

    $prefix = "[$Component][$Type]"
    switch ($Type) {
        'Error' { Write-Host "$prefix $Message" -ForegroundColor Red }
        'Warning' { Write-Host "$prefix $Message" -ForegroundColor Yellow }
        default { Write-Host "$prefix $Message" -ForegroundColor Gray }
    }
}

function Get-DefaultConfig {
    [PSCustomObject]@{
        WindowTitle = 'POS Setup'
        HeaderTitle = 'Welcome to POS Setup'
        HeaderDescription = 'Configure this terminal for imaging. Required values are collected across tabs.'
        Roles = @('Cegid POS Terminal','Cegid CRES','NCR POS Terminal')
        Regions = @(
            [PSCustomObject]@{
                Name = 'Americas'
                Countries = @('United States','Canada','Mexico')
                DefaultOU = 'OU=NJL,OU=POS Terminals,OU=Retail,DC=tiffco,DC=net'
                WS10G = 'tco-amer-retail-Cgd'
            },
            [PSCustomObject]@{
                Name = 'EMEA'
                Countries = @('Spain','Sweden','Switzerland','United Kingdom')
                DefaultOU = 'OU=EMEA,OU=POS Terminals,OU=Retail,DC=tiffco,DC=net'
                WS10G = 'tco-emea-retail-Cgd'
            },
            [PSCustomObject]@{
                Name = 'APAC'
                Countries = @('Taiwan','Thailand','Singapore','Japan')
                DefaultOU = 'OU=APAC,OU=POS Terminals,OU=Retail,DC=tiffco,DC=net'
                WS10G = 'tco-apac-retail-Cgd'
            }
        )
        CountryCodes = [PSCustomObject]@{
            'United States' = 'US'
            'Canada' = 'CA'
            'Mexico' = 'MX'
            'Spain' = 'ES'
            'Sweden' = 'SE'
            'Switzerland' = 'CH'
            'United Kingdom' = 'UK'
            'Taiwan' = 'TW'
            'Thailand' = 'TH'
            'Singapore' = 'SG'
            'Japan' = 'JP'
        }
        RoleComputerNameSuffix = [PSCustomObject]@{
            'Cegid POS Terminal' = 'POS'
            'Cegid CRES' = 'POS'
            'NCR POS Terminal' = 'POS'
        }
        TimeZones = @(
            'Central Standard Time',
            'Eastern Standard Time',
            'Pacific Standard Time',
            'W. Europe Standard Time',
            'GMT Standard Time',
            'SE Asia Standard Time',
            'Tokyo Standard Time'
        )
    }
}

function Get-FrontendConfig {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptDirectory
    )

    $defaultConfig = Get-DefaultConfig
    $configPath = Join-Path -Path $ScriptDirectory -ChildPath 'FrontEndConfig-UIPlusPlusRipOff.json'

    if (-not (Test-Path -Path $configPath)) {
        Write-CMTraceLog -Message "Config file not found at $configPath. Using built-in defaults." -Type Warning
        return $defaultConfig
    }

    try {
        $raw = Get-Content -Path $configPath -Raw -ErrorAction Stop
        $fromFile = $raw | ConvertFrom-Json -ErrorAction Stop
        Write-CMTraceLog -Message "Loaded config from $configPath"
        return $fromFile
    }
    catch {
        Write-CMTraceLog -Message "Failed to parse config at $configPath. Using built-in defaults. $_" -Type Warning
        return $defaultConfig
    }
}

function Get-HardwareSummary {
    $model = 'Unknown'
    $manufacturer = 'Unknown'
    $serial = 'Unknown'

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs.Manufacturer) { $manufacturer = $cs.Manufacturer }
        if ($cs.Model) { $model = $cs.Model }
    }
    catch {}

    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        if ($bios.SerialNumber) { $serial = $bios.SerialNumber }
    }
    catch {}

    [PSCustomObject]@{
        Manufacturer = $manufacturer
        Model = $model
        Serial = $serial
        ComputerName = $env:COMPUTERNAME
    }
}

function Get-MapValue {
    param(
        [Parameter(Mandatory = $true)]$Map,
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Default = ''
    )

    if ($null -eq $Map) { return $Default }

    try {
        if ($Map -is [System.Collections.IDictionary]) {
            if ($Map.Contains($Key)) { return [string]$Map[$Key] }
            return $Default
        }

        $prop = $Map.PSObject.Properties[$Key]
        if ($prop) { return [string]$prop.Value }
    }
    catch {}

    return $Default
}

function Resolve-ComputedValues {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$Region,
        [Parameter(Mandatory = $true)][string]$Country,
        [Parameter(Mandatory = $true)][string]$SiteCode,
        [Parameter(Mandatory = $true)][string]$TerminalIdentifier,
        [Parameter(Mandatory = $true)][string]$TimeZone
    )

    $regionObj = $Config.Regions | Where-Object { $_.Name -eq $Region } | Select-Object -First 1
    $countryCode = Get-MapValue -Map $Config.CountryCodes -Key $Country -Default ''
    if ([string]::IsNullOrWhiteSpace($countryCode)) {
        $countryCode = (($Country -replace '[^A-Za-z]','').ToUpper() + 'XX').Substring(0,2)
    }

    $suffix = Get-MapValue -Map $Config.RoleComputerNameSuffix -Key $Role -Default 'POS'
    $safeSiteCode = ($SiteCode -replace '[^A-Za-z0-9]','').ToUpper()
    $safeTerminal = ($TerminalIdentifier -replace '[^A-Za-z0-9]','').ToUpper()

    $osdComputerName = "$countryCode-$safeSiteCode-$suffix-$safeTerminal"
    if ($osdComputerName.Length -gt 15) {
        $osdComputerName = $osdComputerName.Substring(0,15)
    }

    [PSCustomObject]@{
        OSDComputerName = $osdComputerName
        OSDDomainOUName = if ($regionObj -and $regionObj.DefaultOU) { [string]$regionObj.DefaultOU } else { '' }
        OSDTimeZone = $TimeZone
        WS10G = if ($regionObj -and $regionObj.WS10G) { [string]$regionObj.WS10G } else { '' }
        CountryCode = $countryCode
        Role = $Role
        Region = $Region
        Country = $Country
        SiteCode = $safeSiteCode
        TerminalIdentifier = $safeTerminal
    }
}

function Get-InputFormData {
    param(
        [Parameter(Mandatory = $true)]$Config
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore

    $hardware = Get-HardwareSummary

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="POS Setup"
        Height="760"
        Width="980"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResizeWithGrip"
        Background="#F4F6F8">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="White" CornerRadius="8" Padding="16" Margin="0,0,0,12">
            <StackPanel>
                <TextBlock Name="txtHeaderTitle" FontSize="32" FontWeight="Bold" Foreground="#1F2937" Text="Welcome to POS Setup"/>
                <TextBlock Name="txtHeaderDescription" FontSize="14" Margin="0,4,0,10" Foreground="#374151" Text="Configure this terminal for imaging. Required values are collected across tabs."/>
                <TextBlock Name="txtHardware" FontSize="13" Foreground="#4B5563" TextWrapping="Wrap"/>
            </StackPanel>
        </Border>

        <TabControl Grid.Row="1" Name="tabMain" Background="White" BorderBrush="#D1D5DB" BorderThickness="1" Padding="8">
            <TabItem Header="Role">
                <Grid Margin="16">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" FontSize="30" FontWeight="Bold" Foreground="#111827" Text="Configuration Options"/>
                    <TextBlock Grid.Row="1" Margin="0,8,0,16" FontSize="16" Text="Please choose a role."/>
                    <ComboBox Grid.Row="2" Name="cmbRole" Height="34" FontSize="16"/>
                </Grid>
            </TabItem>

            <TabItem Header="Region">
                <Grid Margin="16">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" FontSize="30" FontWeight="Bold" Foreground="#111827" Text="Configuration Options"/>
                    <TextBlock Grid.Row="1" Margin="0,8,0,8" FontSize="16" Text="Please select your region."/>
                    <ComboBox Grid.Row="2" Name="cmbRegion" Height="34" FontSize="16"/>
                    <TextBlock Grid.Row="3" Margin="0,16,0,8" FontSize="16" Text="Select this PC's country"/>
                    <ComboBox Grid.Row="4" Name="cmbCountry" Height="34" FontSize="16"/>
                </Grid>
            </TabItem>

            <TabItem Header="Site">
                <Grid Margin="16">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" FontSize="30" FontWeight="Bold" Foreground="#111827" Text="Configuration Options"/>
                    <TextBlock Grid.Row="1" Margin="0,8,0,8" FontSize="16" Text="Site Code Identifier"/>
                    <TextBox Grid.Row="2" Name="txtSiteCode" Height="34" FontSize="16" MaxLength="3"/>
                    <TextBlock Grid.Row="3" Margin="0,10,0,8" FontSize="13" Foreground="#6B7280" Text="Enter a 3-character site code (example: NJL)."/>
                    <TextBlock Grid.Row="4" Margin="0,10,0,8" FontSize="16" Text="Terminal Identifier"/>
                    <TextBox Grid.Row="5" Name="txtTerminalIdentifier" Height="34" FontSize="16" MaxLength="6"/>
                </Grid>
            </TabItem>

            <TabItem Header="Time Zone">
                <Grid Margin="16">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" FontSize="30" FontWeight="Bold" Foreground="#111827" Text="Time Zone Selection"/>
                    <TextBlock Grid.Row="1" Margin="0,8,0,16" FontSize="16" Text="Select your preferred time zone."/>
                    <ComboBox Grid.Row="2" Name="cmbTimeZone" Height="34" FontSize="16"/>
                </Grid>
            </TabItem>

            <TabItem Header="Verify">
                <Grid Margin="16">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" FontSize="30" FontWeight="Bold" Foreground="#111827" Text="Variable Verification"/>
                    <TextBlock Grid.Row="1" Margin="0,8,0,12" FontSize="16" Text="Review variables that will be set in task sequence context."/>
                    <Border Grid.Row="2" Background="#ECFDF5" BorderBrush="#D1FAE5" BorderThickness="1" CornerRadius="6" Padding="12">
                        <TextBlock Name="txtVerification" FontSize="15" Foreground="#0F766E" FontFamily="Consolas" TextWrapping="Wrap"/>
                    </Border>
                </Grid>
            </TabItem>
        </TabControl>

        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <TextBlock Name="txtValidation" VerticalAlignment="Center" Margin="0,0,12,0" Foreground="#B45309"/>
            <Button Name="btnCancel" Width="110" Height="36" Margin="0,0,10,0" Content="Cancel"/>
            <Button Name="btnSubmit" Width="110" Height="36" IsEnabled="False" Content="Create Variables"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $window.Title = [string]$Config.WindowTitle

    $txtHeaderTitle = $window.FindName('txtHeaderTitle')
    $txtHeaderDescription = $window.FindName('txtHeaderDescription')
    $txtHardware = $window.FindName('txtHardware')

    $cmbRole = $window.FindName('cmbRole')
    $cmbRegion = $window.FindName('cmbRegion')
    $cmbCountry = $window.FindName('cmbCountry')
    $txtSiteCode = $window.FindName('txtSiteCode')
    $txtTerminalIdentifier = $window.FindName('txtTerminalIdentifier')
    $cmbTimeZone = $window.FindName('cmbTimeZone')
    $txtVerification = $window.FindName('txtVerification')
    $txtValidation = $window.FindName('txtValidation')
    $btnSubmit = $window.FindName('btnSubmit')
    $btnCancel = $window.FindName('btnCancel')

    $txtHeaderTitle.Text = [string]$Config.HeaderTitle
    $txtHeaderDescription.Text = [string]$Config.HeaderDescription
    $txtHardware.Text = "Manufacturer: $($hardware.Manufacturer)  |  Model: $($hardware.Model)  |  Serial: $($hardware.Serial)  |  Current Name: $($hardware.ComputerName)"

    foreach ($role in $Config.Roles) { [void]$cmbRole.Items.Add([string]$role) }
    foreach ($region in $Config.Regions) { [void]$cmbRegion.Items.Add([string]$region.Name) }
    foreach ($tz in $Config.TimeZones) { [void]$cmbTimeZone.Items.Add([string]$tz) }

    if ($cmbRole.Items.Count -gt 0) { $cmbRole.SelectedIndex = 0 }
    if ($cmbRegion.Items.Count -gt 0) { $cmbRegion.SelectedIndex = 0 }
    if ($cmbTimeZone.Items.Count -gt 0) { $cmbTimeZone.SelectedIndex = 0 }

    $selected = [ordered]@{
        Role = ''
        Region = ''
        Country = ''
        SiteCode = ''
        TerminalIdentifier = ''
        TimeZone = ''
        OSDComputerName = ''
        OSDDomainOUName = ''
        OSDTimeZone = ''
        WS10G = ''
        CountryCode = ''
    }

    function Update-Countries {
        $cmbCountry.Items.Clear()
        $regionObj = $Config.Regions | Where-Object { $_.Name -eq $cmbRegion.SelectedItem } | Select-Object -First 1
        if ($regionObj -and $regionObj.Countries) {
            foreach ($country in $regionObj.Countries) {
                [void]$cmbCountry.Items.Add([string]$country)
            }
        }
        if ($cmbCountry.Items.Count -gt 0) { $cmbCountry.SelectedIndex = 0 }
    }

    function Update-Preview {
        $selected.Role = [string]$cmbRole.SelectedItem
        $selected.Region = [string]$cmbRegion.SelectedItem
        $selected.Country = [string]$cmbCountry.SelectedItem
        $selected.SiteCode = ([string]$txtSiteCode.Text).Trim().ToUpper()
        $selected.TerminalIdentifier = ([string]$txtTerminalIdentifier.Text).Trim().ToUpper()
        $selected.TimeZone = [string]$cmbTimeZone.SelectedItem

        $isSiteValid = $selected.SiteCode -match '^[A-Z0-9]{3}$'
        $isTerminalValid = $selected.TerminalIdentifier -match '^[A-Z0-9]{1,6}$'
        $hasRequiredSelections = -not [string]::IsNullOrWhiteSpace($selected.Role) -and
            -not [string]::IsNullOrWhiteSpace($selected.Region) -and
            -not [string]::IsNullOrWhiteSpace($selected.Country) -and
            -not [string]::IsNullOrWhiteSpace($selected.TimeZone)

        if ($hasRequiredSelections -and $isSiteValid -and $isTerminalValid) {
            $computed = Resolve-ComputedValues -Config $Config -Role $selected.Role -Region $selected.Region -Country $selected.Country -SiteCode $selected.SiteCode -TerminalIdentifier $selected.TerminalIdentifier -TimeZone $selected.TimeZone
            $selected.OSDComputerName = $computed.OSDComputerName
            $selected.OSDDomainOUName = $computed.OSDDomainOUName
            $selected.OSDTimeZone = $computed.OSDTimeZone
            $selected.WS10G = $computed.WS10G
            $selected.CountryCode = $computed.CountryCode

            $txtValidation.Text = ''
            $btnSubmit.IsEnabled = $true
        }
        else {
            $btnSubmit.IsEnabled = $false
            if (-not $isSiteValid) {
                $txtValidation.Text = 'Site code must be 3 alphanumeric characters.'
            }
            elseif (-not $isTerminalValid) {
                $txtValidation.Text = 'Terminal identifier must be 1-6 alphanumeric characters.'
            }
            else {
                $txtValidation.Text = 'Select all required values.'
            }
        }

        $txtVerification.Text = @(
            "OSDComputerName: $($selected.OSDComputerName)",
            "OSDDomainOUName: $($selected.OSDDomainOUName)",
            "OSDTimeZone: $($selected.OSDTimeZone)",
            "WS10G: $($selected.WS10G)",
            "SelectedUserRole: $($selected.Role)",
            "FrontEndRegion: $($selected.Region)",
            "FrontEndCountry: $($selected.Country)",
            "SiteCode: $($selected.SiteCode)",
            "TerminalIdentifier: $($selected.TerminalIdentifier)"
        ) -join [Environment]::NewLine
    }

    $cmbRegion.Add_SelectionChanged({ Update-Countries; Update-Preview })
    $cmbCountry.Add_SelectionChanged({ Update-Preview })
    $cmbRole.Add_SelectionChanged({ Update-Preview })
    $cmbTimeZone.Add_SelectionChanged({ Update-Preview })
    $txtSiteCode.Add_TextChanged({ Update-Preview })
    $txtTerminalIdentifier.Add_TextChanged({ Update-Preview })

    $result = $null

    $btnSubmit.Add_Click({
        if (-not $btnSubmit.IsEnabled) { return }

        $result = [PSCustomObject]@{
            FormSubmitted = $true
            SelectedUserRole = $selected.Role
            FrontEndRegion = $selected.Region
            FrontEndCountry = $selected.Country
            SiteCode = $selected.SiteCode
            TerminalIdentifier = $selected.TerminalIdentifier
            OSDComputerName = $selected.OSDComputerName
            OSDDomainOUName = $selected.OSDDomainOUName
            OSDTimeZone = $selected.OSDTimeZone
            WS10G = $selected.WS10G
            CountryCode = $selected.CountryCode
        }
        $window.DialogResult = $true
        $window.Close()
    })

    $btnCancel.Add_Click({
        $result = [PSCustomObject]@{ FormSubmitted = $false }
        $window.DialogResult = $false
        $window.Close()
    })

    Update-Countries
    Update-Preview
    [void]$window.ShowDialog()

    if ($null -eq $result) {
        return [PSCustomObject]@{ FormSubmitted = $false }
    }

    return $result
}

function Set-CMTaskSequenceVariables {
    param(
        [Parameter(Mandatory = $true)]$FormResults,
        $TsEnv
    )

    if (-not $TsEnv) { return }

    Write-CMTraceLog -Message 'Setting ConfigMgr task sequence variables...'

    $TsEnv.Value('SelectedUserRole') = $FormResults.SelectedUserRole
    $TsEnv.Value('FrontEndRegion') = $FormResults.FrontEndRegion
    $TsEnv.Value('FrontEndCountry') = $FormResults.FrontEndCountry
    $TsEnv.Value('SiteCode') = $FormResults.SiteCode
    $TsEnv.Value('TerminalIdentifier') = $FormResults.TerminalIdentifier

    $TsEnv.Value('OSDComputerName') = $FormResults.OSDComputerName
    $TsEnv.Value('OSDDomainOUName') = $FormResults.OSDDomainOUName
    $TsEnv.Value('OSDTimeZone') = $FormResults.OSDTimeZone
    $TsEnv.Value('WS10G') = $FormResults.WS10G

    $TsEnv.Value('ComputerName') = $FormResults.OSDComputerName
    $TsEnv.Value('DomainJoinOU') = $FormResults.OSDDomainOUName
    $TsEnv.Value('TimeZone') = $FormResults.OSDTimeZone
}

function Set-DeployRTaskSequenceVariables {
    param(
        [Parameter(Mandatory = $true)]$FormResults
    )

    $isDeployRUtility = (Get-Module -Name 'DeployR.Utility') -and (-not (Test-Path -Path 'HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings'))
    if (-not $isDeployRUtility) { return }

    Write-CMTraceLog -Message 'Setting DeployR TSENV variables...'

    $toSet = @{
        SelectedUserRole = $FormResults.SelectedUserRole
        FrontEndRegion = $FormResults.FrontEndRegion
        FrontEndCountry = $FormResults.FrontEndCountry
        SiteCode = $FormResults.SiteCode
        TerminalIdentifier = $FormResults.TerminalIdentifier
        OSDComputerName = $FormResults.OSDComputerName
        OSDDomainOUName = $FormResults.OSDDomainOUName
        OSDTimeZone = $FormResults.OSDTimeZone
        WS10G = $FormResults.WS10G
        ComputerName = $FormResults.OSDComputerName
        DomainJoinOU = $FormResults.OSDDomainOUName
        OU = $FormResults.OSDDomainOUName
        TimeZone = $FormResults.OSDTimeZone
    }

    foreach ($kv in $toSet.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$kv.Value)) { continue }
        try {
            Set-Item -Path ("TSENV:" + $kv.Key) -Value ([string]$kv.Value)
            Write-CMTraceLog -Message ("TSENV " + $kv.Key + " = " + [string]$kv.Value)
        }
        catch {
            Write-CMTraceLog -Message ("Failed to set TSENV variable " + $kv.Key + ". " + $_) -Type Warning
        }
    }
}

function Set-LocalTestVariables {
    param(
        [Parameter(Mandatory = $true)]$FormResults
    )

    $toSet = @{
        SelectedUserRole = $FormResults.SelectedUserRole
        FrontEndRegion = $FormResults.FrontEndRegion
        FrontEndCountry = $FormResults.FrontEndCountry
        SiteCode = $FormResults.SiteCode
        TerminalIdentifier = $FormResults.TerminalIdentifier
        OSDComputerName = $FormResults.OSDComputerName
        OSDDomainOUName = $FormResults.OSDDomainOUName
        OSDTimeZone = $FormResults.OSDTimeZone
        WS10G = $FormResults.WS10G
    }

    foreach ($kv in $toSet.GetEnumerator()) {
        [System.Environment]::SetEnvironmentVariable([string]$kv.Key, [string]$kv.Value, 'Process')
    }

    Write-CMTraceLog -Message 'No TS environment detected. Set process environment variables for local testing.' -Type Warning
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
}

Write-Host "Starting FrontEnd-UIPlusPlusRipOff.ps1 version $ScriptVersion" -ForegroundColor Cyan

$config = Get-FrontendConfig -ScriptDirectory $scriptDir
$formResults = Get-InputFormData -Config $config

if (-not $formResults.FormSubmitted) {
    Write-CMTraceLog -Message 'Form cancelled by user.' -Type Warning
    return
}

$tsEnv = $null
try {
    $tsEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
}
catch {
    Write-CMTraceLog -Message 'Task Sequence COM object not available. Continuing with local testing behavior.' -Type Warning
}

Set-CMTaskSequenceVariables -FormResults $formResults -TsEnv $tsEnv
Set-DeployRTaskSequenceVariables -FormResults $formResults

if (-not $tsEnv -and -not ((Get-Module -Name 'DeployR.Utility') -and (-not (Test-Path -Path 'HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings')))) {
    Set-LocalTestVariables -FormResults $formResults
}

Write-CMTraceLog -Message 'Completed setting front-end variables.'
