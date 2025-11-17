<#
.SYNOPSIS
    Dell BIOS Settings Management via Native WMI/CIM

.DESCRIPTION
    This script provides functions to get and set Dell BIOS settings using the native Dell WMI classes.
    It supports both EnumerationAttribute (settings with predefined values) and StringAttribute (text-based settings like Asset Tag).
    
    The script includes five main functions:
    - Test-DellBIOSWMISupport: Verifies if the device supports Dell BIOS WMI management
    - Test-DellBIOSPassword: Checks if a BIOS Admin or System password is currently set
    - Get-DellBIOSSetting: Retrieves BIOS settings from the device
    - Set-DellBIOSSetting: Modifies BIOS settings on the device
    - Set-DellBIOSAdminPassword: Simplified function to set, change, or remove BIOS Admin password

.NOTES
    Version: 1.0
    Author: Gary Blok (@gwblok) - 2PintLabs
    Creation Date: November 2025
    
    Credits: 
    - Sven Riebe (@SvenRiebe) for the original Dell BIOS management implementation
    - Reference implementation: https://github.com/svenriebedell/Intune/blob/main/Remediation/Intune_11_Detection_BIOS_setting_compliant.ps1
    
    Requirements:
    - Dell device with WMI BIOS support (devices manufactured after 2018)
    - Administrative privileges for setting BIOS values (Set function only)
    - Dell WMI Provider (typically pre-installed on Dell devices)
    - PowerShell 5.1 or higher
    
    WMI Namespaces Used:
    - root/dcim/sysman/biosattributes (EnumerationAttribute, StringAttribute)
    - root/dcim/sysman/wmisecurity (SecurityInterface, PasswordObject)

.EXAMPLE
    # Check if the device supports Dell BIOS WMI management
    if (Test-DellBIOSWMISupport) {
        Write-Host "This device supports Dell BIOS WMI management"
    } else {
        Write-Host "This device does not support Dell BIOS WMI management"
    }
    
.EXAMPLE
    # Get all BIOS settings
    $allSettings = Get-DellBIOSSetting
    
.EXAMPLE
    # Get a specific BIOS setting
    $asset = Get-DellBIOSSetting -SettingName "Asset"
    Write-Host "Current Asset Tag: $($asset.CurrentValue)"
    
.EXAMPLE
    # Set a BIOS setting without password protection
    Set-DellBIOSSetting -SettingName "ChasIntrusion" -SettingValue "SilentEnable"
    
.EXAMPLE
    # Set a BIOS setting with password protection
    Set-DellBIOSSetting -SettingName "ChasIntrusion" -SettingValue "SilentEnable" -BIOSPW "YourPassword"
    
.EXAMPLE
    # Use pipeline to get and set a BIOS setting
    Get-DellBIOSSetting -SettingName "Asset" | Set-DellBIOSSetting -SettingValue "98765"
    
.EXAMPLE
    # Set BIOS Admin Password for the first time
    Set-DellBIOSSetting -SettingName "Admin" -SettingValue "NewPassword123"
    
.EXAMPLE
    # Change existing BIOS Admin Password
    Set-DellBIOSSetting -SettingName "Admin" -SettingValue "NewPassword456" -BIOSPW "NewPassword123"
    
.EXAMPLE
    # Clear BIOS Admin Password
    Set-DellBIOSSetting -SettingName "Admin" -SettingValue "ClearPWD" -BIOSPW "NewPassword456"

.EXAMPLE
    # Check if BIOS Admin password is set
    if (Test-DellBIOSPassword) {
        Write-Host "BIOS Admin password is set"
    } else {
        Write-Host "No BIOS Admin password"
    }

.EXAMPLE
    # Set BIOS Admin password for the first time (simplified method)
    Set-DellBIOSAdminPassword -NewPassword "MySecurePassword123"

.EXAMPLE
    # Change existing BIOS Admin password (simplified method)
    Set-DellBIOSAdminPassword -CurrentPassword "OldPassword123" -NewPassword "NewPassword456"

.EXAMPLE
    # Remove BIOS Admin password (simplified method)
    Set-DellBIOSAdminPassword -CurrentPassword "CurrentPassword123" -RemovePassword
    
.EXAMPLE
    # Export all BIOS settings to CSV for documentation
    Get-DellBIOSSetting | Export-Csv -Path "C:\Temp\DellBIOSSettings.csv" -NoTypeInformation
    
.EXAMPLE
    # Find all read-only BIOS settings
    Get-DellBIOSSetting | Where-Object { $_.ReadOnly -eq $true }
    
.EXAMPLE
    # View string-type settings (like Asset Tag, Service Tag, etc.)
    Get-DellBIOSSetting | Where-Object { $_.AttributeType -eq "String" } | Format-Table AttributeName, CurrentValue, MinLength, MaxLength

.LINK
    https://github.com/gwblok/2PintLabs
    
.LINK
    https://github.com/svenriebedell/Intune/blob/main/Remediation/Intune_11_Detection_BIOS_setting_compliant.ps1

#>


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


function Set-DellBIOSAdminPassword
    {

        <#
        .Synopsis
        Sets, changes, or removes the Dell BIOS Admin password

        .Description
        This function manages the Dell BIOS Admin password by automatically detecting if a password
        is currently set and performing the appropriate operation:
        - If no password is set: Sets the new password
        - If a password is set: Changes from current to new password
        - If RemovePassword switch is used: Removes the current password
        
        The function uses the Test-DellBIOSPassword function to determine the current state
        and handles the password encoding and WMI operations accordingly.
        
        Note: This function does not write any information to the registry.
        
        .Parameter CurrentPassword
        The current BIOS Admin password. Required when changing or removing an existing password.
        If no password is currently set, this parameter will be ignored.

        .Parameter NewPassword
        The new BIOS Admin password to set or change to.
        This parameter is required unless RemovePassword switch is used.
        Must meet Dell BIOS password requirements.
        
        .Parameter RemovePassword
        Switch parameter to remove the current BIOS Admin password.
        When used, CurrentPassword is required but NewPassword should not be provided.
        
        .Outputs
        System.Boolean
        Returns $true if the password was successfully set, changed, or removed, $false if the operation failed

        Changelog:
            1.0.0 Initial Version
            1.0.1 Added RemovePassword parameter to support clearing BIOS Admin password

        .Example
        Set a BIOS Admin password for the first time (no current password)

        Set-DellBIOSAdminPassword -NewPassword "MySecurePassword123"

        .Example
        Change the BIOS Admin password from current to new

        Set-DellBIOSAdminPassword -CurrentPassword "OldPassword123" -NewPassword "NewPassword456"

        .Example
        Remove the BIOS Admin password

        Set-DellBIOSAdminPassword -CurrentPassword "CurrentPassword123" -RemovePassword

        .Example
        Conditional password setting with detection

        if (Test-DellBIOSPassword) {
            # Password is set, change it
            Set-DellBIOSAdminPassword -CurrentPassword "Current123" -NewPassword "New456"
        } else {
            # No password set, set new one
            Set-DellBIOSAdminPassword -NewPassword "New456"
        }

        #>
        [CmdletBinding(DefaultParameterSetName='SetOrChange')]
        param(
            [Parameter(mandatory=$false, ParameterSetName='SetOrChange')]
            [Parameter(mandatory=$true, ParameterSetName='Remove')]
            [String]$CurrentPassword,
            
            [Parameter(mandatory=$true, ParameterSetName='SetOrChange')]
            [String]$NewPassword,
            
            [Parameter(mandatory=$true, ParameterSetName='Remove')]
            [Switch]$RemovePassword
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

        # Validate parameters based on operation
        if (-not $RemovePassword)
            {
                # For Set/Change operations, NewPassword is required
                if ([string]::IsNullOrEmpty($NewPassword))
                    {
                        Write-Error "Error: NewPassword parameter cannot be empty"
                        return $false
                    }
            }
        else
            {
                # For Remove operation, ensure NewPassword wasn't provided
                if (-not [string]::IsNullOrEmpty($NewPassword))
                    {
                        Write-Warning "NewPassword parameter was provided with RemovePassword switch. NewPassword will be ignored."
                    }
            }

        # Connect to SecurityInterface WMI class
        try
            {
                Write-Verbose "Connecting to Dell Security WMI Interface..."
                $SecurityInterface = Get-CimInstance -Namespace root\dcim\sysman\wmisecurity -Class SecurityInterface -ErrorAction Stop
                Write-Information "Security Interface connected" -InformationAction Continue
            }
        catch
            {
                $errMsg = $_.Exception.Message
                Write-Error "Error: Security interface access denied or unreachable - $errMsg"
                return $false
            }

        # Check if BIOS Admin password is currently set
        try
            {
                # Use Test-DellBIOSPassword to check current state
                $PasswordIsSet = Test-DellBIOSPassword -PasswordType "Admin"

                if (-not $PasswordIsSet)
                    {
                        # Check if user is trying to remove password when none is set
                        if ($RemovePassword)
                            {
                                Write-Warning "No BIOS Admin password is currently set. Nothing to remove."
                                return $true
                            }
                        
                        #################################################
                        #### Set BIOS Admin Password for First Time ####
                        #################################################
                        
                        Write-Information "No BIOS Admin password is currently set. Setting new password..." -InformationAction Continue
                        
                        # Argument for setting password (no current password)
                        $arguments = @{
                            NameId      = "Admin"
                            NewPassword = $NewPassword
                            OldPassword = ""
                            SecType     = 0
                            SecHndCount = 0
                            SecHandle   = @()
                        }

                        # Set the new BIOS Admin password
                        $SetResult = Invoke-CimMethod -InputObject $SecurityInterface -MethodName SetNewPassword -Arguments $arguments -ErrorAction Stop

                        if ($SetResult.Status -eq 0)
                            {
                                Write-Information "Message: BIOS Admin password set successfully" -InformationAction Continue
                                return $true
                            }
                        else
                            {
                                $result = switch ($SetResult.Status)
                                    {
                                        0 { 'Success' }
                                        1 { 'Failed' }
                                        2 { 'Invalid Parameter' }
                                        3 { 'Access Denied' }
                                        4 { 'Not Supported' }
                                        5 { 'Memory Error' }
                                        6 { 'Protocol Error' }
                                        default { 'Unknown' }
                                    }
                                Write-Error "Error: Failed to set BIOS Admin password - Status: $result (Code: $($SetResult.Status))"
                                return $false
                            }
                    }
                else
                    {
                        # Verify CurrentPassword was provided for change or remove operations
                        if ([string]::IsNullOrEmpty($CurrentPassword))
                            {
                                $operation = if ($RemovePassword) { "remove" } else { "change" }
                                Write-Error "Error: BIOS Admin password is set but CurrentPassword parameter was not provided"
                                Write-Information "Message: CurrentPassword is required to $operation an existing BIOS password" -InformationAction Continue
                                return $false
                            }

                        Write-Verbose "Encoding current password for authentication..."
                        
                        # Encode the current password
                        $Encoder = New-Object System.Text.UTF8Encoding
                        $Bytes = $Encoder.GetBytes($CurrentPassword)

                        if ($RemovePassword)
                            {
                                ##########################################
                                #### Remove BIOS Admin Password      ####
                                ##########################################
                                
                                Write-Information "BIOS Admin password is set. Removing password..." -InformationAction Continue

                                # Argument for removing password (set new password to empty string)
                                $arguments = @{
                                    NameId      = "Admin"
                                    NewPassword = ""
                                    OldPassword = $CurrentPassword
                                    SecType     = 1
                                    SecHndCount = $Bytes.Length
                                    SecHandle   = $Bytes
                                }

                                # Remove the BIOS Admin password
                                $SetResult = Invoke-CimMethod -InputObject $SecurityInterface -MethodName SetNewPassword -Arguments $arguments -ErrorAction Stop

                                if ($SetResult.Status -eq 0)
                                    {
                                        Write-Information "Message: BIOS Admin password removed successfully" -InformationAction Continue
                                        return $true
                                    }
                                else
                                    {
                                        $result = switch ($SetResult.Status)
                                            {
                                                0 { 'Success' }
                                                1 { 'Failed' }
                                                2 { 'Invalid Parameter' }
                                                3 { 'Access Denied - Current password may be incorrect' }
                                                4 { 'Not Supported' }
                                                5 { 'Memory Error' }
                                                6 { 'Protocol Error' }
                                                default { 'Unknown' }
                                            }
                                        Write-Error "Error: Failed to remove BIOS Admin password - Status: $result (Code: $($SetResult.Status))"
                                        return $false
                                    }
                            }
                        else
                            {
                                ##############################################
                                #### Change Existing BIOS Admin Password ####
                                ##############################################
                                
                                Write-Information "BIOS Admin password is already set. Changing password..." -InformationAction Continue

                                # Argument for changing password (with current password authentication)
                                $arguments = @{
                                    NameId      = "Admin"
                                    NewPassword = $NewPassword
                                    OldPassword = $CurrentPassword
                                    SecType     = 1
                                    SecHndCount = $Bytes.Length
                                    SecHandle   = $Bytes
                                }

                                # Change the BIOS Admin password
                                $SetResult = Invoke-CimMethod -InputObject $SecurityInterface -MethodName SetNewPassword -Arguments $arguments -ErrorAction Stop

                                if ($SetResult.Status -eq 0)
                                    {
                                        Write-Information "Message: BIOS Admin password changed successfully" -InformationAction Continue
                                        return $true
                                    }
                                else
                                    {
                                        $result = switch ($SetResult.Status)
                                            {
                                                0 { 'Success' }
                                                1 { 'Failed' }
                                                2 { 'Invalid Parameter' }
                                                3 { 'Access Denied - Current password may be incorrect' }
                                                4 { 'Not Supported' }
                                                5 { 'Memory Error' }
                                                6 { 'Protocol Error' }
                                                default { 'Unknown' }
                                            }
                                        Write-Error "Error: Failed to change BIOS Admin password - Status: $result (Code: $($SetResult.Status))"
                                        return $false
                                    }
                            }
                    }
            }
        catch
            {
                $errMsg = $_.Exception.Message
                Write-Error "Error: Failed to manage BIOS Admin password - $errMsg"
                return $false
            }
    }