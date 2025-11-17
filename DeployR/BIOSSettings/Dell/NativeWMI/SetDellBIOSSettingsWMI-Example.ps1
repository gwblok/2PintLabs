<#
.SYNOPSIS
    Example script for configuring multiple Dell BIOS settings via native WMI/CIM

.DESCRIPTION
    This script demonstrates how to configure multiple Dell BIOS settings in a single execution.
    It uses native Dell WMI classes to query and modify BIOS settings without requiring external tools.
    
    The script performs the following operations:
    1. Tests if the device supports Dell BIOS WMI management (devices from 2018+)
    2. Loops through a defined list of desired BIOS settings
    3. For each setting:
       - Retrieves the current value from the device
       - Validates the setting exists and is not read-only
       - Skips if already set to the desired value (idempotent behavior)
       - Validates enumeration values against possible options
       - Applies the change if needed
    4. Provides detailed reporting with color-coded console output
    5. Exports results to a timestamped log file in %TEMP%
    6. Returns appropriate exit codes for automation/task sequences
    
    Key Features:
    - Idempotent: Only changes settings that need to be changed
    - Validation: Checks for valid values before attempting changes
    - Error handling: Gracefully handles missing settings or read-only values
    - Detailed logging: Tracks success, failures, and skipped items
    - BIOS password support: Handles both password-protected and non-protected scenarios

.NOTES
    Author: Gary Blok (@gwblok) - 2PintLabs
    Version: 1.0
    Created: November 2025
    
    Credits:
    - Sven Riebe (@SvenRiebe) for the original Dell BIOS management implementation
    - Reference: https://github.com/svenriebedell/Intune/blob/main/Remediation/Intune_11_Detection_BIOS_setting_compliant.ps1
    
    Requirements:
    - Dell device with WMI BIOS support (manufactured after 2018)
    - Administrative privileges
    - PowerShell 5.1 or higher
    
    Exit Codes:
    - 0: Success (all settings applied or no changes needed)
    - 1: Failure (device incompatible or one or more settings failed)

.EXAMPLE
    Run the script with no BIOS password:
    .\SetDellBIOSSettingsWMI-Example.ps1
    
.EXAMPLE
    Modify the script to include BIOS password:
    Edit line 4: $BIOSPassword = "YourBIOSPassword"
    
.EXAMPLE
    Customize the settings list (lines 7-16):
    Add or modify settings in the $BIOSSettings array with BIOSSettingName and BIOSSettingValue

.LINK
    https://github.com/gwblok/2PintLabs

.LINK
    https://github.com/svenriebedell/Intune/blob/main/Remediation/Intune_11_Detection_BIOS_setting_compliant.ps1

#>

#########################################################################################################
####                                    Configuration Section                                        ####
#########################################################################################################

#BIOS Password (if you have one configured)
$BIOSPassword = ""  #Set your BIOS Admin Password here, if applicable. Leave empty if no password is set.

#Define your desired BIOS settings and values here:
#To find available settings and values, run: Get-DellBIOSSetting | Select-Object AttributeName, CurrentValue, PossibleValues
$BIOSSettings = @(
    [PSCustomObject]@{BIOSSettingName = "AutoOSRecoveryThreshold"; BIOSSettingValue = "OFF"}
    [PSCustomObject]@{BIOSSettingName = "SupportAssistOSRecovery"; BIOSSettingValue = "Disabled"}
    [PSCustomObject]@{BIOSSettingName = "BIOSConnect"; BIOSSettingValue = "Enabled"}
    [PSCustomObject]@{BIOSSettingName = "FastBoot"; BIOSSettingValue = "Auto"}
    [PSCustomObject]@{BIOSSettingName = "WakeOnAc"; BIOSSettingValue = "Enabled"}
    [PSCustomObject]@{BIOSSettingName = "USBPowerShare"; BIOSSettingValue = "Enabled"}
    [PSCustomObject]@{BIOSSettingName = "WakeOnLan"; BIOSSettingValue = "LanOnly"}
    [PSCustomObject]@{BIOSSettingName = "CapsuleFirmwareUpdate"; BIOSSettingValue = "Enabled"}
)


#Region Functions

function Test-DellBIOSWMISupport
    {

        <#
        .Synopsis
        Tests if the Dell BIOS WMI namespaces are available on the current device

        .Description
        This function checks if the required Dell WMI namespaces are available on the device.
        It verifies the presence of the biosattributes and wmisecurity namespaces required for BIOS management.
        This is used to determine if the device supports Dell BIOS management via WMI (typically devices from 2018 or newer).
        
        Returns $true if Dell BIOS WMI is supported, $false if not supported.
        
        .Outputs
        System.Boolean
        Returns $true if WMI support is available, $false otherwise

        Changelog:
            1.0.0 Initial Version

        .Example
        Test if Dell BIOS WMI support is available and proceed conditionally

        if (Test-DellBIOSWMISupport) {
            Write-Host "Dell BIOS WMI is supported on this device"
            $settings = Get-DellBIOSSetting
        } else {
            Write-Host "This device does not support Dell BIOS WMI"
        }

        #>
        [CmdletBinding()]
        param()

        #########################################################################################################
        ####                                    Program Section                                              ####
        #########################################################################################################

        try
            {
                # Test for biosattributes namespace
                $biosNamespace = Get-CimInstance -Namespace root/dcim/sysman/biosattributes -ClassName EnumerationAttribute -ErrorAction Stop | Select-Object -First 1
                
                if ($null -eq $biosNamespace)
                    {
                        Write-Verbose "Dell BIOS WMI namespace exists but returned no data"
                        return $false
                    }
                
                # Test for wmisecurity namespace
                $securityNamespace = Get-CimInstance -Namespace root/dcim/sysman/wmisecurity -ClassName SecurityInterface -ErrorAction Stop
                
                if ($null -eq $securityNamespace)
                    {
                        Write-Verbose "Dell Security WMI namespace exists but returned no data"
                        return $false
                    }
                
                Write-Verbose "Dell BIOS WMI support is available"
                return $true
            }
        catch
            {
                $errMsg = $_.Exception.Message
                Write-Verbose "Dell BIOS WMI support is not available: $errMsg"
                return $false
            }
    }


function Test-DellBIOSPassword
    {

        <#
        .Synopsis
        Tests if a BIOS password is currently set on the Dell device

        .Description
        This function checks if a BIOS Admin or System password is set on the device by querying
        the PasswordObject WMI class. It can check for Admin password, System password, or both.
        
        Returns $true if the specified password type is set, $false if not set.
        Useful for conditional logic before attempting BIOS changes.
        
        .Parameter PasswordType
        Specifies which password type to check. Valid values are:
        - "Admin" (default) - Checks BIOS Admin password
        - "System" - Checks System password
        - "Both" - Checks if either Admin or System password is set
        
        .Outputs
        System.Boolean
        Returns $true if the password is set, $false if not set

        Changelog:
            1.0.0 Initial Version

        .Example
        Check if Admin password is set

        if (Test-DellBIOSPassword) {
            Write-Host "BIOS Admin password is set"
        } else {
            Write-Host "No BIOS Admin password"
        }

        .Example
        Check if System password is set

        if (Test-DellBIOSPassword -PasswordType "System") {
            Write-Host "System password is set"
        }
        
        .Example
        Check if either password type is set
        
        if (Test-DellBIOSPassword -PasswordType "Both") {
            Write-Host "At least one password is set"
        }

        #>
        [CmdletBinding()]
        param(
            [Parameter(mandatory=$false)]
            [ValidateSet("Admin", "System", "Both")]
            [String]$PasswordType = "Admin"
        )

        #########################################################################################################
        ####                                    Program Section                                              ####
        #########################################################################################################

        # Check if Dell BIOS WMI is supported on this device
        if (-not (Test-DellBIOSWMISupport))
            {
                Write-Error "Error: This device does not support Dell BIOS WMI management. This feature is typically available on Dell devices manufactured after 2018."
                return $false
            }

        try
            {
                switch ($PasswordType)
                    {
                        "Admin" {
                            Write-Verbose "Checking if Admin password is set..."
                            $PasswordObject = Get-CimInstance -Namespace root/dcim/sysman/wmisecurity -ClassName PasswordObject -Filter "NameId='Admin'" -ErrorAction Stop
                            
                            if ($null -eq $PasswordObject)
                                {
                                    Write-Verbose "Unable to retrieve Admin password status"
                                    return $false
                                }
                            
                            if ($PasswordObject.IsPasswordSet -eq 1)
                                {
                                    Write-Verbose "Admin password is set"
                                    return $true
                                }
                            else
                                {
                                    Write-Verbose "Admin password is not set"
                                    return $false
                                }
                        }
                        
                        "System" {
                            Write-Verbose "Checking if System password is set..."
                            $PasswordObject = Get-CimInstance -Namespace root/dcim/sysman/wmisecurity -ClassName PasswordObject -Filter "NameId='System'" -ErrorAction Stop
                            
                            if ($null -eq $PasswordObject)
                                {
                                    Write-Verbose "Unable to retrieve System password status"
                                    return $false
                                }
                            
                            if ($PasswordObject.IsPasswordSet -eq 1)
                                {
                                    Write-Verbose "System password is set"
                                    return $true
                                }
                            else
                                {
                                    Write-Verbose "System password is not set"
                                    return $false
                                }
                        }
                        
                        "Both" {
                            Write-Verbose "Checking if Admin or System password is set..."
                            $AdminPassword = Get-CimInstance -Namespace root/dcim/sysman/wmisecurity -ClassName PasswordObject -Filter "NameId='Admin'" -ErrorAction Stop
                            $SystemPassword = Get-CimInstance -Namespace root/dcim/sysman/wmisecurity -ClassName PasswordObject -Filter "NameId='System'" -ErrorAction Stop
                            
                            $AdminSet = ($null -ne $AdminPassword) -and ($AdminPassword.IsPasswordSet -eq 1)
                            $SystemSet = ($null -ne $SystemPassword) -and ($SystemPassword.IsPasswordSet -eq 1)
                            
                            if ($AdminSet -or $SystemSet)
                                {
                                    Write-Verbose "At least one password is set (Admin: $AdminSet, System: $SystemSet)"
                                    return $true
                                }
                            else
                                {
                                    Write-Verbose "No passwords are set"
                                    return $false
                                }
                        }
                    }
            }
        catch
            {
                $errMsg = $_.Exception.Message
                Write-Error "Error: Failed to check BIOS password status - $errMsg"
                return $false
            }
    }


function Get-DellBIOSSetting
    {

        <#
        .Synopsis
        Retrieves Dell Client BIOS Settings via WMI/CIM

        .Description
        This function retrieves BIOS settings from Dell devices using both the EnumerationAttribute and StringAttribute WMI classes.
        By default, it returns all BIOS settings from both classes. You can optionally filter by a specific setting name.
        
        The function returns PSCustomObjects with the following properties:
        - AttributeType: "Enumeration" or "String"
        - AttributeName: Name of the BIOS setting
        - CurrentValue: Current value of the setting
        - DefaultValue: Factory default value
        - DisplayName: Human-readable display name
        - PossibleValues: Array of possible values (Enumeration type only)
        - MinLength/MaxLength: Character limits (String type only)
        - ReadOnly: Boolean indicating if setting is read-only

        .Parameter SettingName
        Optional parameter to retrieve a specific BIOS setting by name. If not specified, all settings are returned.
        
        .Outputs
        System.Management.Automation.PSCustomObject[]
        Returns an array of PSCustomObjects containing BIOS setting information

        Changelog:
            1.0.0 Initial Version
            1.0.1 Added support for StringAttribute class to retrieve string-based BIOS settings
            1.0.2 Added pipeline support for Set-DellBIOSSetting

        .Example
        Retrieve all BIOS settings from the device

        Get-DellBIOSSetting

        .Example
        Retrieve a specific BIOS setting and display its properties

        $setting = Get-DellBIOSSetting -SettingName "ChasIntrusion"
        Write-Host "Current Value: $($setting.CurrentValue)"
        Write-Host "Possible Values: $($setting.PossibleValues -join ', ')"

        .Example
        Export all BIOS settings to a CSV file for documentation

        Get-DellBIOSSetting | Export-Csv -Path "C:\Temp\BIOSSettings.csv" -NoTypeInformation
        
        .Example
        Filter and display only string-type settings
        
        Get-DellBIOSSetting | Where-Object { $_.AttributeType -eq "String" } | Select-Object AttributeName, CurrentValue, MaxLength

        #>
        [CmdletBinding()]
        param
            (
                [Parameter(mandatory=$false)] 
                [String]$SettingName
            )


        #########################################################################################################
        ####                                    Program Section                                              ####
        #########################################################################################################

        # Check if Dell BIOS WMI is supported on this device
        if (-not (Test-DellBIOSWMISupport))
            {
                Write-Error "Error: This device does not support Dell BIOS WMI management. This feature is typically available on Dell devices manufactured after 2018."
                return $null
            }

        # Connect to BIOS Interface and retrieve settings
        try
            {
                Write-Verbose "Connecting to Dell BIOS WMI Interface..."

                if ($SettingName)
                    {
                        # Get specific BIOS setting from EnumerationAttribute
                        Write-Verbose "Retrieving BIOS setting: $SettingName from EnumerationAttribute"
                        $EnumSettings = Get-CimInstance -Namespace root/dcim/sysman/biosattributes -ClassName EnumerationAttribute -Filter "AttributeName='$SettingName'" -ErrorAction SilentlyContinue
                        
                        # Get specific BIOS setting from StringAttribute
                        Write-Verbose "Retrieving BIOS setting: $SettingName from StringAttribute"
                        $StringSettings = Get-CimInstance -Namespace root/dcim/sysman/biosattributes -ClassName StringAttribute -Filter "AttributeName='$SettingName'" -ErrorAction SilentlyContinue
                        
                        # Combine results
                        $BIOSSettings = @()
                        if ($EnumSettings) { $BIOSSettings += $EnumSettings }
                        if ($StringSettings) { $BIOSSettings += $StringSettings }
                        
                        if ($BIOSSettings.Count -eq 0)
                            {
                                Write-Warning "BIOS setting '$SettingName' not found in either EnumerationAttribute or StringAttribute classes"
                                return $null
                            }
                    }
                else
                    {
                        # Get all BIOS settings from EnumerationAttribute
                        Write-Verbose "Retrieving all BIOS settings from EnumerationAttribute..."
                        $EnumSettings = Get-CimInstance -Namespace root/dcim/sysman/biosattributes -ClassName EnumerationAttribute -ErrorAction SilentlyContinue
                        
                        # Get all BIOS settings from StringAttribute
                        Write-Verbose "Retrieving all BIOS settings from StringAttribute..."
                        $StringSettings = Get-CimInstance -Namespace root/dcim/sysman/biosattributes -ClassName StringAttribute -ErrorAction SilentlyContinue
                        
                        # Combine results
                        $BIOSSettings = @()
                        if ($EnumSettings) { $BIOSSettings += $EnumSettings }
                        if ($StringSettings) { $BIOSSettings += $StringSettings }
                    }

                Write-Information "Successfully retrieved $($BIOSSettings.Count) BIOS settings" -InformationAction Continue
            }
        catch
            {
                $errMsg = $_.Exception.Message
                Write-Error "Error: Failed to access BIOS interface or retrieve settings - $errMsg"
                return $null
            }

        # Process and return settings as PSCustomObjects
        try
            {
                $BIOSSettingsOutput = @()

                foreach ($Setting in $BIOSSettings)
                    {
                        # Determine the attribute type based on properties
                        $AttributeType = if ($null -ne $Setting.PossibleValue) { "Enumeration" } else { "String" }
                        
                        # Build common properties
                        $SettingObject = [PSCustomObject]@{
                            PSTypeName              = 'DellBIOSSetting'
                            AttributeType           = $AttributeType
                            AttributeName           = $Setting.AttributeName
                            CurrentValue            = $Setting.CurrentValue
                            DefaultValue            = $Setting.DefaultValue
                            DisplayName             = $Setting.DisplayName
                            DisplayNameLangCode     = $Setting.DisplayNameLangCode
                            ReadOnly                = if ($Setting.ReadOnly -eq 1) { $true } else { $false }
                            Modifiers               = $Setting.Modifiers
                            InstanceName            = $Setting.InstanceName
                        }
                        
                        # Add type-specific properties
                        if ($AttributeType -eq "Enumeration")
                            {
                                $SettingObject | Add-Member -MemberType NoteProperty -Name PossibleValues -Value $Setting.PossibleValue
                                $SettingObject | Add-Member -MemberType NoteProperty -Name PossibleValueCount -Value $Setting.PossibleValueCount
                                $SettingObject | Add-Member -MemberType NoteProperty -Name ValueModifiers -Value $Setting.ValueModifiers
                                $SettingObject | Add-Member -MemberType NoteProperty -Name ValueModifierCount -Value $Setting.ValueModifierCount
                                $SettingObject | Add-Member -MemberType NoteProperty -Name MinLength -Value $null
                                $SettingObject | Add-Member -MemberType NoteProperty -Name MaxLength -Value $null
                            }
                        else
                            {
                                $SettingObject | Add-Member -MemberType NoteProperty -Name PossibleValues -Value $null
                                $SettingObject | Add-Member -MemberType NoteProperty -Name PossibleValueCount -Value $null
                                $SettingObject | Add-Member -MemberType NoteProperty -Name ValueModifiers -Value $null
                                $SettingObject | Add-Member -MemberType NoteProperty -Name ValueModifierCount -Value $null
                                $SettingObject | Add-Member -MemberType NoteProperty -Name MinLength -Value $Setting.MinLength
                                $SettingObject | Add-Member -MemberType NoteProperty -Name MaxLength -Value $Setting.MaxLength
                            }

                        $BIOSSettingsOutput += $SettingObject
                    }

                Write-Verbose "Successfully processed $($BIOSSettingsOutput.Count) BIOS setting(s)"
                return $BIOSSettingsOutput
            }
        catch
            {
                $errMsg = $_.Exception.Message
                Write-Error "Error: Failed to process BIOS settings - $errMsg"
                return $null
            }
    }


function Set-DellBIOSSetting
    {

        <#
        .Synopsis
        Modifies Dell Client BIOS Settings via WMI/CIM

        .Description
        This function allows you to set BIOS passwords or change BIOS settings on Dell devices.
        It automatically detects if a BIOS password is set and handles the authentication accordingly.
        
        The function supports:
        - Setting regular BIOS settings (with or without password protection)
        - Setting BIOS Admin/System passwords for the first time
        - Changing existing BIOS passwords
        - Clearing BIOS passwords
        - Pipeline input from Get-DellBIOSSetting
        
        Note: A system reboot may be required for some settings to take effect.

        .Parameter SettingName
        The name of the BIOS setting to modify. Use "Admin" or "System" for password operations.
        This parameter accepts pipeline input from Get-DellBIOSSetting via the AttributeName property.

        .Parameter SettingValue
        The new value for the BIOS setting. For enumeration settings, use one of the PossibleValues.
        For string settings (like Asset Tag), provide the desired string value.
        Use "ClearPWD" as the value when clearing a BIOS password.

        .Parameter BIOSPW
        The existing BIOS Admin password. Required only if a BIOS password is already set on the device.
        Omit this parameter if no BIOS password is currently configured.
        
        .Outputs
        System.Boolean
        Returns $true if the setting was successfully applied, $false if it failed

        Changelog:
            1.0.0 Initial Version
            1.0.1 Added return for setting returncode to the mainscript
            1.0.2 Switched from Write-Host to Write-Information, Write-Verbose and Write-Error
            1.0.3 Added pipeline support to accept input from Get-DellBIOSSetting
            1.0.4 Added device compatibility check via Test-DellBIOSWMISupport
            1.0.5 Enhanced to use Test-DellBIOSPassword and validate password before operations


        .Example
        This example will set the Chassis Intrusion detection to SilentEnable, if the Device has no BIOS Admin Password.

        Set-DellBIOSSetting -SettingName ChasIntrusion -SettingValue SilentEnable

        .Example
        This example will set the Chassis Intrusion detection to SilentEnable, if the Device has BIOS Admin Password.

        Set-DellBIOSSetting -SettingName ChasIntrusion -SettingValue SilentEnable -BIOSPW <Your BIOS Admin PWD>

        .Example
        This example will set a new BIOS Admin Password for the first time

        Set-DellBIOSSetting -SettingName Admin -SettingValue <Your BIOS Admin PWD>

        .Example
        This example will change BIOS Admin Password

        Set-DellBIOSSetting -SettingName Admin -SettingValue <Your NEW BIOS Admin PWD> -BIOSPW <Your OLD BIOS Admin PWD>

        .Example
        This example will Clear BIOS Admin Password

        Set-DellBIOSSetting -SettingName Admin -SettingValue ClearPWD -BIOSPW <Your OLD BIOS Admin PWD>

        .Example
        This example will use pipeline input from Get-DellBIOSSetting to set a BIOS setting value

        Get-DellBIOSSetting -SettingName "Asset" | Set-DellBIOSSetting -SettingValue "98765"

        #>
        [CmdletBinding()]
        param
            (

                [Parameter(mandatory=$true, ValueFromPipelineByPropertyName=$true)] 
                [Alias('AttributeName')]
                [String]$SettingName,
                [Parameter(mandatory=$true)] [String]$SettingValue,
                [Parameter(mandatory=$false)] [String]$BIOSPW

            )


        #########################################################################################################
        ####                                    Program Section                                              ####
        #########################################################################################################

        # Check if Dell BIOS WMI is supported on this device
        if (-not (Test-DellBIOSWMISupport))
            {
                Write-Error "Error: This device does not support Dell BIOS WMI management. This feature is typically available on Dell devices manufactured after 2018."
                return $false
            }

        # connect BIOS Interface
        try
            {
                # get BIOS WMI Interface
                $BIOSInterface = Get-CimInstance -Namespace root\dcim\sysman\biosattributes -Class BIOSAttributeInterface -ErrorAction Stop
                $SecurityInterface = Get-CimInstance -Namespace root\dcim\sysman\wmisecurity -Class SecurityInterface -ErrorAction Stop
                Write-Information "BIOS Interface connected" -InformationAction Continue
            }
        catch
            {
                Write-Error "Error : BIOS interface access denied or unreachable"
                Write-Information "Status : false" -InformationAction Continue
                Return $false
            }


        # Check if BIOS Admin password is set and validate provided password
        try
            {
                # Use Test-DellBIOSPassword to check if password is set
                $PasswordIsSet = Test-DellBIOSPassword -PasswordType "Admin"

                if ($PasswordIsSet)
                    {
                        Write-Information "BIOS Admin password is set on this device" -InformationAction Continue

                        # Verify password was provided
                        If ([string]::IsNullOrEmpty($BIOSPW))
                            {
                                Write-Error "Error: BIOS Admin password is set but BIOSPW parameter was not provided"
                                Write-Information "Message: Required parameter BIOSPW is empty" -InformationAction Continue
                                Return $false
                            }
                        
                        Write-Verbose "BIOS password provided, will use for authentication"

                        #Get encoder for encoding password
                        $encoder = New-Object System.Text.UTF8Encoding

                        #encode the password
                        $AdminBytes = $encoder.GetBytes($BIOSPW)

                        If (($SettingName -ne "Admin") -and ($SettingName -ne "System"))
                            {
                                ######################################
                                ####  BIOS Setting with Admin PWD ####
                                ######################################

                                try
                                    {
                                        # Argument
                                        $argumentsWithPWD = @{
                                                                AttributeName=$SettingName;
                                                                AttributeValue=$SettingValue;
                                                                SecType=1;
                                                                SecHndCount=$AdminBytes.Length;
                                                                SecHandle=$AdminBytes;
                                                            }

                                        # Set a BIOS Attribute
                                        Write-Information "Set Bios" -InformationAction Continue
                                        $SetResult = Invoke-CimMethod -InputObject $BIOSInterface -MethodName SetAttribute -Arguments $argumentsWithPWD -ErrorAction Stop

                                        If ($SetResult.Status -eq 0)
                                            {
                                                Write-Information "Message : BIOS setting success" -InformationAction Continue
                                                return $true
                                            }
                                        else
                                            {
                                                switch ( $SetResult.Status )
                                                    {
                                                        0 { $result = 'Success' }
                                                        1 { $result = 'Failed' }
                                                        2 { $result = 'Invalid Parameter' }
                                                        3 { $result = 'Access Denied'  }
                                                        4 { $result = 'Not Supported' }
                                                        5 { $result = 'Memory Error'  }
                                                        6 { $result = 'Protocol Error' }
                                                        default { $result ='Unknown' }
                                                    }
                                                Write-Information "Message : BIOS setting $result" -InformationAction Continue
                                                return $false, $SetResult.Status
                                            }
                                    }
                                catch
                                    {
                                        $errMsg = $_.Exception.Message
                                        Write-Information $errMsg -InformationAction Continue
                                        If ($SetResult.Status -eq 0)
                                            {
                                                Write-Information "Message : BIOS setting success" -InformationAction Continue
                                                return $true
                                            }
                                        else
                                            {
                                                        switch ( $SetResult.Status )
                                                            {
                                                                0 { $result = 'Success' }
                                                                1 { $result = 'Failed' }
                                                                2 { $result = 'Invalid Parameter' }
                                                                3 { $result = 'Access Denied'  }
                                                                4 { $result = 'Not Supported' }
                                                                5 { $result = 'Memory Error'  }
                                                                6 { $result = 'Protocol Error' }
                                                                default { $result ='Unknown' }
                                                            }
                                                        Write-Information "Message : BIOS Password setting $result" -InformationAction Continue
                                                        return $false, $SetResult.Status
                                                        Return $false
                                            }
                                    }
                            }
                        else
                            {
                                ################################################
                                ####  BIOS Change/Delete Admin or Sytem PWD ####
                                ################################################
                                try
                                    {
                                        If($SettingValue -eq "ClearPWD")
                                            {
                                                Write-Information "Admin PWD clear" -InformationAction Continue
                                                # Argument
                                                $argumentsWithPWD = @{
                                                                        NameId=$SettingName;
                                                                        NewPassword="";
                                                                        OldPassword=$BIOSPW;
                                                                        SecType=1;
                                                                        SecHndCount=$AdminBytes.Length;
                                                                        SecHandle=$AdminBytes;
                                                                    }
                                            }
                                        else
                                            {
                                                Write-Information "Admin PWD change" -InformationAction Continue
                                                # Argument
                                                $argumentsWithPWD = @{
                                                                        NameId=$SettingName;
                                                                        NewPassword=$SettingValue;
                                                                        OldPassword=$BIOSPW;
                                                                        SecType=1;
                                                                        SecHndCount=$AdminBytes.Length;
                                                                        SecHandle=$AdminBytes;
                                                                    }
                                            }


                                        # Set a BIOS Attribute
                                        $SetResult = Invoke-CimMethod -InputObject $SecurityInterface -MethodName SetnewPassword -Arguments $argumentsWithPWD #-ErrorAction Stop

                                        If ($SetResult.Status -eq 0)
                                            {
                                                Write-Information "Message : BIOS Password setting success" -InformationAction Continue
                                                return $true
                                            }
                                        else
                                            {
                                                switch ( $SetResult.Status )
                                                    {
                                                        0 { $result = 'Success' }
                                                        1 { $result = 'Failed' }
                                                        2 { $result = 'Invalid Parameter' }
                                                        3 { $result = 'Access Denied'  }
                                                        4 { $result = 'Not Supported' }
                                                        5 { $result = 'Memory Error'  }
                                                        6 { $result = 'Protocol Error' }
                                                        default { $result ='Unknown' }
                                                    }
                                                Write-Information "Message : BIOS Password setting $result" -InformationAction Continue
                                                return $false, $SetResult.Status
                                            }
                                    }
                                catch
                                    {
                                        $errMsg = $_.Exception.Message
                                        Write-Information $errMsg -InformationAction Continue
                                        If ($SetResult.Status -eq 0)
                                            {
                                                Write-Information "Message : BIOS Password setting success" -InformationAction Continue
                                                return $true
                                            }
                                        else
                                            {
                                                switch ( $SetResult.Status )
                                                    {
                                                        0 { $result = 'Success' }
                                                        1 { $result = 'Failed' }
                                                        2 { $result = 'Invalid Parameter' }
                                                        3 { $result = 'Access Denied'  }
                                                        4 { $result = 'Not Supported' }
                                                        5 { $result = 'Memory Error'  }
                                                        6 { $result = 'Protocol Error' }
                                                        default { $result ='Unknown' }
                                                    }
                                                Write-Information "Message : BIOS Password setting $result" -InformationAction Continue
                                                return $false, $SetResult.Status
                                                Return $false
                                            }
                                    }
                            }
                    }
                Else
                    {
                        Write-Information "No BIOS Admin password is set on this device" -InformationAction Continue
                        
                        # Warn if password was provided but not needed
                        if (-not [string]::IsNullOrEmpty($BIOSPW))
                            {
                                Write-Warning "BIOS password parameter was provided but no password is set on the device. The password will be ignored."
                            }

                        If (($SettingName -ne "Admin") -and ($SettingName -ne "System"))
                            {
                                #########################################
                                ####  BIOS Setting without Admin PWD ####
                                #########################################
                                try
                                    {
                                        # Argument
                                        $argumentsNoPWD = @{
                                                                AttributeName=$SettingName;
                                                                AttributeValue=$SettingValue;
                                                                SecType=0;
                                                                SecHndCount=0;
                                                                SecHandle=@()
                                                            }

                                        Write-Information "Set Bios Settings" -InformationAction Continue
                                        # Set a BIOS Attribute ChasIntrusion to EnabledSilent (BIOS password is not set)
                                        $SetResult = Invoke-CimMethod -InputObject $BIOSInterface -MethodName SetAttribute -Arguments $argumentsNoPWD -ErrorAction Stop

                                        If ($SetResult.Status -eq 0)
                                            {
                                                Write-Information "Message : BIOS setting success" -InformationAction Continue
                                                return $true
                                            }
                                        else
                                            {
                                                switch ( $SetResult.Status )
                                                    {
                                                        0 { $result = 'Success' }
                                                        1 { $result = 'Failed' }
                                                        2 { $result = 'Invalid Parameter' }
                                                        3 { $result = 'Access Denied'  }
                                                        4 { $result = 'Not Supported' }
                                                        5 { $result = 'Memory Error'  }
                                                        6 { $result = 'Protocol Error' }
                                                        default { $result ='Unknown' }
                                                    }
                                                Write-Information "Message : BIOS setting $result" -InformationAction Continue
                                                return $false, $SetResult.Status
                                            }
                                    }
                                catch
                                    {
                                        $errMsg = $_.Exception.Message
                                        Write-Information $errMsg -InformationAction Continue
                                        Write-Information "Message : BIOS setting failed" -InformationAction Continue
                                        return $false, $SetResult.Status
                                        Return $false
                                    }


                            }
                        else
                            {
                                ######################################
                                ####  BIOS Set Admin or Sytem PWD ####
                                ######################################
                                try
                                    {

                                        # Argument
                                        $argumentsNoPWD = @{
                                                                NameId=$SettingName;
                                                                NewPassword=$SettingValue;
                                                                OldPassword="";
                                                                SecType=0;
                                                                SecHndCount=0;
                                                                SecHandle=@();
                                                            }

                                        Write-Information "Set Password" -InformationAction Continue

                                        # Set a BIOS Passwords
                                        $SetResult = Invoke-CimMethod -InputObject $SecurityInterface -MethodName SetnewPassword -Arguments $argumentsNoPWD -ErrorAction Stop

                                        If ($SetResult.Status -eq 0)
                                            {
                                                Write-Information "Message : BIOS Password setting success" -InformationAction Continue
                                                return $true
                                            }
                                        else
                                            {
                                                switch ( $SetResult.Status )
                                                    {
                                                        0 { $result = 'Success' }
                                                        1 { $result = 'Failed' }
                                                        2 { $result = 'Invalid Parameter' }
                                                        3 { $result = 'Access Denied'  }
                                                        4 { $result = 'Not Supported' }
                                                        5 { $result = 'Memory Error'  }
                                                        6 { $result = 'Protocol Error' }
                                                        default { $result ='Unknown' }
                                                    }
                                                Write-Information "Message : BIOS setting $result" -InformationAction Continue
                                                return $false, $SetResult.Status
                                            }
                                    }
                                catch
                                    {
                                        $errMsg = $_.Exception.Message
                                        Write-Information $errMsg -InformationAction Continue
                                        Write-Information "Message : BIOS setting failed" -InformationAction Continue
                                        return $false, $SetResult.Status
                                        Return $false
                                    }
                            }
                    }
            }
        catch
            {
                $errMsg = $_.Exception.Message
                Write-Information $errMsg -InformationAction Continue
                If ($SetResult.Status -eq 0)
                    {
                        Write-Information "Message : BIOS setting success" -InformationAction Continue
                        return $true
                    }
                else
                    {
                        switch ( $SetResult.Status )
                            {
                                0 { $result = 'Success' }
                                1 { $result = 'Failed' }
                                2 { $result = 'Invalid Parameter' }
                                3 { $result = 'Access Denied'  }
                                4 { $result = 'Not Supported' }
                                5 { $result = 'Memory Error'  }
                                6 { $result = 'Protocol Error' }
                                default { $result ='Unknown' }
                            }
                        Write-Information "Message : BIOS Password setting $result" -InformationAction Continue
                        return $false, $SetResult.Status
                    }
                Write-Information "Status : False" -InformationAction Continue
                Return $false
            }
    }

#EndRegion Functions


#########################################################################################################
####                                    Main Script Execution                                        ####
#########################################################################################################

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Dell BIOS Settings Configuration Script" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Test if the device supports Dell BIOS WMI
Write-Host "Checking Dell BIOS WMI support..." -ForegroundColor Yellow
if (-not (Test-DellBIOSWMISupport)) {
    Write-Host "ERROR: This device does not support Dell BIOS WMI management." -ForegroundColor Red
    Write-Host "This feature is typically available on Dell devices manufactured after 2018.`n" -ForegroundColor Red
    exit 1
}
Write-Host "SUCCESS: Dell BIOS WMI is supported on this device`n" -ForegroundColor Green

# Initialize results tracking
$Results = @()
$SuccessCount = 0
$FailureCount = 0
$SkippedCount = 0

Write-Host "Processing $($BIOSSettings.Count) BIOS settings...`n" -ForegroundColor Cyan

# Loop through each BIOS setting
foreach ($Setting in $BIOSSettings) {
    Write-Host "Processing: $($Setting.BIOSSettingName)" -ForegroundColor Yellow
    
    # Get current setting value to check if change is needed
    $CurrentSetting = Get-DellBIOSSetting -SettingName $Setting.BIOSSettingName
    
    if ($null -eq $CurrentSetting) {
        Write-Host "  [SKIPPED] Setting not found on this device" -ForegroundColor Magenta
        $Results += [PSCustomObject]@{
            SettingName = $Setting.BIOSSettingName
            DesiredValue = $Setting.BIOSSettingValue
            CurrentValue = "N/A"
            Status = "Skipped - Not Found"
            Message = "Setting does not exist on this device"
        }
        $SkippedCount++
        continue
    }
    
    # Check if setting is read-only
    if ($CurrentSetting.ReadOnly -eq $true) {
        Write-Host "  [SKIPPED] Setting is read-only" -ForegroundColor Magenta
        $Results += [PSCustomObject]@{
            SettingName = $Setting.BIOSSettingName
            DesiredValue = $Setting.BIOSSettingValue
            CurrentValue = $CurrentSetting.CurrentValue
            Status = "Skipped - Read-Only"
            Message = "Setting cannot be modified"
        }
        $SkippedCount++
        continue
    }
    
    # Check if value is already set correctly
    if ($CurrentSetting.CurrentValue -eq $Setting.BIOSSettingValue) {
        Write-Host "  [SKIPPED] Already set to desired value: $($Setting.BIOSSettingValue)" -ForegroundColor Gray
        $Results += [PSCustomObject]@{
            SettingName = $Setting.BIOSSettingName
            DesiredValue = $Setting.BIOSSettingValue
            CurrentValue = $CurrentSetting.CurrentValue
            Status = "Skipped - Already Correct"
            Message = "Value already matches desired state"
        }
        $SkippedCount++
        continue
    }
    
    # Validate desired value for enumeration types
    if ($CurrentSetting.AttributeType -eq "Enumeration") {
        if ($CurrentSetting.PossibleValues -notcontains $Setting.BIOSSettingValue) {
            Write-Host "  [FAILED] Invalid value. Possible values: $($CurrentSetting.PossibleValues -join ', ')" -ForegroundColor Red
            $Results += [PSCustomObject]@{
                SettingName = $Setting.BIOSSettingName
                DesiredValue = $Setting.BIOSSettingValue
                CurrentValue = $CurrentSetting.CurrentValue
                Status = "Failed - Invalid Value"
                Message = "Possible values: $($CurrentSetting.PossibleValues -join ', ')"
            }
            $FailureCount++
            continue
        }
    }
    
    # Apply the setting
    Write-Host "  Current Value: $($CurrentSetting.CurrentValue)" -ForegroundColor White
    Write-Host "  Setting to: $($Setting.BIOSSettingValue)" -ForegroundColor White
    
    try {
        # Check if BIOS password is actually set on the device
        $DeviceHasPassword = Test-DellBIOSPassword -PasswordType "Admin"
        
        if ($DeviceHasPassword) {
            Write-Host "  BIOS password is set on device" -ForegroundColor Gray
            
            # Verify we have a password to use
            if ([string]::IsNullOrEmpty($BIOSPassword)) {
                Write-Host "  [FAILED] BIOS password is required but not provided in script" -ForegroundColor Red
                $Results += [PSCustomObject]@{
                    SettingName = $Setting.BIOSSettingName
                    DesiredValue = $Setting.BIOSSettingValue
                    CurrentValue = $CurrentSetting.CurrentValue
                    Status = "Failed - Password Required"
                    Message = "BIOS password is set on device but not provided in script configuration"
                }
                $FailureCount++
                Write-Host ""
                continue
            }
            
            # Apply setting with password
            $SetResult = Set-DellBIOSSetting -SettingName $Setting.BIOSSettingName -SettingValue $Setting.BIOSSettingValue -BIOSPW $BIOSPassword
        }
        else {
            Write-Host "  No BIOS password set on device" -ForegroundColor Gray
            
            # Warn if password was provided but not needed
            if (-not [string]::IsNullOrEmpty($BIOSPassword)) {
                Write-Host "  [WARNING] Password provided but not required" -ForegroundColor Yellow
            }
            
            # Apply setting without password
            $SetResult = Set-DellBIOSSetting -SettingName $Setting.BIOSSettingName -SettingValue $Setting.BIOSSettingValue
        }
        
        if ($SetResult -eq $true) {
            Write-Host "  [SUCCESS] Setting applied successfully" -ForegroundColor Green
            $Results += [PSCustomObject]@{
                SettingName = $Setting.BIOSSettingName
                DesiredValue = $Setting.BIOSSettingValue
                CurrentValue = $CurrentSetting.CurrentValue
                Status = "Success"
                Message = "Setting changed successfully"
            }
            $SuccessCount++
        }
        else {
            Write-Host "  [FAILED] Setting could not be applied" -ForegroundColor Red
            $Results += [PSCustomObject]@{
                SettingName = $Setting.BIOSSettingName
                DesiredValue = $Setting.BIOSSettingValue
                CurrentValue = $CurrentSetting.CurrentValue
                Status = "Failed"
                Message = "Set operation returned false"
            }
            $FailureCount++
        }
    }
    catch {
        Write-Host "  [FAILED] Error: $($_.Exception.Message)" -ForegroundColor Red
        $Results += [PSCustomObject]@{
            SettingName = $Setting.BIOSSettingName
            DesiredValue = $Setting.BIOSSettingValue
            CurrentValue = $CurrentSetting.CurrentValue
            Status = "Failed - Exception"
            Message = $_.Exception.Message
        }
        $FailureCount++
    }
    
    Write-Host ""
}

#########################################################################################################
####                                    Results Summary                                              ####
#########################################################################################################

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "BIOS Configuration Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Settings Processed: $($BIOSSettings.Count)" -ForegroundColor White
Write-Host "Successfully Changed:     $SuccessCount" -ForegroundColor Green
Write-Host "Failed:                   $FailureCount" -ForegroundColor $(if ($FailureCount -gt 0) { "Red" } else { "White" })
Write-Host "Skipped:                  $SkippedCount" -ForegroundColor $(if ($SkippedCount -gt 0) { "Magenta" } else { "White" })
Write-Host "========================================`n" -ForegroundColor Cyan

# Display detailed results table
Write-Host "Detailed Results:" -ForegroundColor Cyan
$Results | Format-Table SettingName, CurrentValue, DesiredValue, Status -AutoSize

# Export results to log file (optional)
$LogPath = "$env:TEMP\DellBIOSConfig_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$Results | Export-Csv -Path $LogPath -NoTypeInformation
Write-Host "Detailed log saved to: $LogPath`n" -ForegroundColor Gray

# Exit with appropriate code
if ($FailureCount -gt 0) {
    Write-Host "Script completed with errors. Some settings could not be applied.`n" -ForegroundColor Yellow
    exit 1
}
elseif ($SuccessCount -gt 0) {
    Write-Host "Script completed successfully. $SuccessCount setting(s) were changed.`n" -ForegroundColor Green
    Write-Host "NOTE: A system reboot may be required for some changes to take effect.`n" -ForegroundColor Yellow
    exit 0
}
else {
    Write-Host "Script completed. No changes were necessary.`n" -ForegroundColor Gray
    exit 0
}