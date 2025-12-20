<#
    .Synopsis
        Script to run the WinPEGen.exe tool, adding BranchCache and StifleR to your boot image(s)

    .REQUIREMENTS
       Must have a copy of an installed StifleR Client folder

    .USAGE
       Set the parameters to match your environment in the parameters region

   .NOTES
    AUTHOR: 2Pint Software
    EMAIL: support@2pintsoftware.com
    VERSION: 1.0.0.5
    DATE:09/16/2025
    
    CHANGE LOG: 
    1.0.0.0 : 11/26/2019  : Initial version of script 
    1.0.0.1 : 11/26/2019  : Added version checks for WinPEGen.exe and StifleR Client
    1.0.0.2 : 10/21/2022  : Added Backup and Certificate Import
    1.0.0.3 : 05/31/2023  : Version check fix
    1.0.0.4 : 09/10/2025  : Added Stifler Client 2.14 support using StiflerClient.2psImport JSON file
    1.0.0.4 : 09/10/2025  : Added Stifler Client 2.14 support to extract from MSI if needed

   .LINK
    https://2pintsoftware.com
#>
# Requires the script to be run under an administrative account context.
#Requires -RunAsAdministrator

#region --------------------------------------------------[Script Parameters]------------------------------------------------------

# Set OS Image to get BranchCache binaries from. The OS version (build number, e.g. patch-level) must match boot image version.
# If using a newer Windows 11 image, patch the boot media to same level
$Windows11Media = "E:\Sources\OSD\OS\Windows 11 Enterprise x64 v22H2April23\sources\install.wim"
$Windows11Index = "3" #  Index 3 is Enterprise if using the WIM from a Microsoft ISO

# Set path to StifleR Client installation source file (containing the MSI)
$StifleRSource = "E:\Sources\Software\2Pint\Stifler.Client\StifleR-ClientApp-2.14.2535.81"

# Get the StifleR Client config file from a Stifler Client Config tool export (2psImport)
$StiflerConfigJSON = "E:\Sources\Software\2Pint\Stifler.Client\StiflerClient.2psImport"

# Path to WinPEGen.exe
$OSDToolkitPath = "E:\Sources\Software\2Pint\OSD Toolkit 3.1.9.0 Full\x64"

# Set other parameters
$BackupBootMedia = "E:\Sources\OSD\Boot\2Pint Boot\Win1122H2_2.13\Backup\winpe.wim" # Optional, only needed when running the script multiple times
$BootMedia = "E:\Sources\OSD\Boot\2Pint Boot\Win1122H2_2.13\winpe.wim"
$BootIndex = "1"

# Optional Parameters
# Add the Root CA if using internal PKI for StifleR (certutil -ca.cert C:\Setup\Cert\CustomerRootCA.cer)
# Comment below if not used (add # infront)
$Cert = "E:\Setup\Cert\ViaMonstraRootCA.cer"
$MountPath = "E:\Mount" # Used to mount bootimage before injecting certificat, required if $Cert is used.

#endregion -----------------------------------------------[Script Parameters]------------------------------------------------------

function Set-RegistryFromJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryBasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$JsonFilePath
    )
    
    try {
        # Read and parse JSON file
        if (-not (Test-Path $JsonFilePath)) {
            throw "JSON file not found: $JsonFilePath"
        }
        
        $jsonContent = Get-Content -Path $JsonFilePath -Raw | ConvertFrom-Json
        Write-Verbose "Successfully loaded JSON from: $JsonFilePath"
        
        # Convert PowerShell registry path to .NET format and clean it up
        $registryBasePath = $RegistryBasePath -replace "^HKLM:", "" -replace "^HKEY_LOCAL_MACHINE\\", ""
        $registryBasePath = $registryBasePath.TrimStart('\')
        
        Write-Verbose "Base registry path: $registryBasePath"
        
        # Process each key in the JSON
        foreach ($keyName in $jsonContent.PSObject.Properties.Name) {
            $keyData = $jsonContent.$keyName
            $fullRegistryPath = if ($registryBasePath) { "$registryBasePath\$keyName" } else { $keyName }
            
            Write-Verbose "Processing registry key: $fullRegistryPath"
            
            # Create the registry key hierarchy step by step
            $pathParts = $fullRegistryPath -split '\\'
            $currentPath = ""
            $registryKey = $null
            
            try {
                # Build path incrementally and create each level
                for ($i = 0; $i -lt $pathParts.Length; $i++) {
                    if ($i -eq 0) {
                        $currentPath = $pathParts[$i]
                    }
                    else {
                        $currentPath = "$currentPath\$($pathParts[$i])"
                    }
                    
                    Write-Verbose "Creating/Opening: $currentPath"
                    
                    if ($i -eq ($pathParts.Length - 1)) {
                        # This is the final key where we'll set values
                        $registryKey = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($currentPath)
                    }
                    else {
                        # Just ensure intermediate keys exist
                        $tempKey = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($currentPath)
                        if ($tempKey) { $tempKey.Close() }
                    }
                }
                
                if ($null -eq $registryKey) {
                    throw "Failed to create or open registry key: $fullRegistryPath"
                }
                
                # Set each value in the key
                foreach ($valueName in $keyData.PSObject.Properties.Name) {
                    $valueData = $keyData.$valueName
                    
                    # URL decode the value data if needed
                    $decodedValue = [System.Web.HttpUtility]::UrlDecode($valueData)
                    
                    <#
                    if($valueName -eq "Features")
                    {
                        if($decodedValue -like "*EventLog*")
                        {
                            $newvalue = $null
                            $newvalue = ($decodedValue -split ",").Trim() | Where-Object { $_ –ne "EventLog" }
                            $decodedValue = $newvalue -join ","

                        }
                    }
                    #>

                    # Set the registry value as REG_SZ (String)
                    $registryKey.SetValue($valueName, $decodedValue, [Microsoft.Win32.RegistryValueKind]::String)
                    Write-Verbose "Set $valueName = $decodedValue"
                }
                
                Write-Host "Successfully configured registry key: HKLM:\$fullRegistryPath" -ForegroundColor Green
            }
            finally {
                # Always close the registry key
                if ($registryKey) {
                    $registryKey.Close()
                }
            }
        }
    }
    catch {
        Write-Error "Failed to set registry values: $($_.Exception.Message)"
    }
}

function Invoke-ExtractStiflerClientMSI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MsiPath
    )

    $Destination = $MsiPath + "\extracted"
    if (Test-Path -LiteralPath $Destination) {
        Write-Host "Already Extracted to: $Destination"
        Write-Host "To extract again, remove $Destination and rerun the script"
    }
    else {

        try {
            $MsiFilePath = (Get-ChildItem -Path $MsiPath -Filter "*.msi" | Select-Object -First 1).FullName
            $msi = (Resolve-Path -LiteralPath $MsiFilePath -ErrorAction Stop).ProviderPath
            if ([IO.Path]::GetExtension($msi).ToLowerInvariant() -ne '.msi') {
                throw "Input must be an .msi file."
            }

            if ([string]::IsNullOrWhiteSpace($Destination)) {
                $name = [IO.Path]::GetFileNameWithoutExtension($msi)
                $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                $Destination = Join-Path $env:TEMP "MSI_${name}_$stamp"
            }

            if (-not (Test-Path -LiteralPath $Destination)) {
                $null = New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop
            }

            $args = @(
                '/a'                                   # Administrative install (extract)
                "`"$msi`""
                '/qn'                                  # Quiet, no UI
                "TARGETDIR=`"$Destination`""           # Extraction target
                'REBOOT=ReallySuppress'                # Never prompt for reboot
            )

            Write-Verbose "Running: msiexec.exe $($args -join ' ')"
            $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru -NoNewWindow

            if ($p.ExitCode -ne 0) {
                $map = @{
                    1602 = 'User canceled.'
                    1603 = 'Fatal error during extraction.'
                    1605 = 'This action is only valid for products that are installed.'
                    1618 = 'Another installation is already in progress.'
                    1619 = 'MSI file could not be opened.'
                    1620 = 'MSI is of an invalid format.'
                    1624 = 'Error applying transform.'
                    1639 = 'Invalid command line.'
                }
                $msg = $map[$p.ExitCode]
                if (-not $msg) { $msg = 'Unknown error.' }
                throw "msiexec failed with exit code $($p.ExitCode): $msg"
            }

            Write-Host "Extracted to: $Destination"
        }
        catch {
            Write-Error $_.Exception.Message
            exit 1
        }
    }
}
Push-Location

# Validation
$WinPEGenVersion = [version](Get-ItemProperty "$OSDToolkitPath\WinPEGen.exe").VersionInfo.FileVersion
If ($WinPEGenVersion -lt [version]"3.0.2.0") { Write-Warning "WinPEGen version too old. Aborting script..."; Break }
If (!(Test-Path $Windows11Media)) { Write-Warning "$Windows11Media missing, aborting script..."; Break }

If (!(Test-Path $StifleRSource)) { Write-Warning "$StifleRSource missing, aborting script..."; Break }
# Check if StiflerSource contains StifleR.ClientApp.exe
If (!(Test-Path "$StifleRSource\StifleR.ClientApp.exe")) {
    if (Test-Path "$StiflerSource\extracted\PFiles64\2Pint Software\StifleR Client\StifleR.ClientApp.exe") {
        $StifleRSource = "$StifleRSource\extracted\PFiles64\2Pint Software\StifleR Client"
        Write-Host "Found existing extracted StifleR Client, using $StifleRSource"
    }
    else {
        Write-Host "StifleR.ClientApp.exe not found in $StifleRSource, checking for MSI to extract..."
        IF (test-path "$StiflerSource\extracted") { 
            Write-host "Cleaning up existing extracted folder..."
            Remove-Item "$StiflerSource\extracted" -Recurse -Force 
        }
        $MSIFiles = (Get-ChildItem -Path $StifleRSource -Filter "*.msi" | Select-Object -First 1).FullName
        If ($MSIFiles.Count -eq 1) {
            Write-Host "Found $($MSIFiles.Name) MSI file, extracting..."
            Invoke-ExtractStiflerClientMSI -MsiPath $StifleRSource 
            Write-Host "Extracted MSI file, using $StifleRSource"
            $StifleRSource = "$StifleRSource\extracted\PFiles64\2Pint Software\StifleR Client"
        }
        Else { 
            Write-Warning "StifleR.ClientApp.exe missing in $StifleRSource, aborting script..."; Break 
        } 
    }
}
$StifleRClientVersion = [version](Get-ItemProperty "$StifleRSource\StifleR.ClientApp.exe").VersionInfo.FileVersion
If ($StifleRClientVersion -lt [version]"2.6.9.0") { Write-Warning "StifleR Client version too old. Aborting script..."; Break }

If (!(Test-Path $StiflerConfigJSON)) { Write-Warning "$StifleRClientRules missing, aborting script..."; Break }
If (!(Test-Path $OSDToolkitPath)) { Write-Warning "$OSDToolkitPath missing, aborting script..."; Break }
If (!(Test-Path $BackupBootMedia)) { Write-Warning "$BackupBootMedia missing, aborting script..."; Break }

# Restore boot image from backup copy
If (Test-Path $BackupBootMedia) {
    If (Test-Path $BootMedia) { Remove-Item $BootMedia -Force }
    Copy-item $BackupBootMedia $BootMedia
}

# Set working directory to OSDToolkitPath, and start Running WinPEGen.exe
Set-Location $OSDToolkitPath
.\WinPEGen.exe $Windows11Media $Windows11Index $Bootmedia $BootIndex /Add-StifleR /StifleRSource:$StifleRSource #/StifleRConfig:$StifleRClientRules

# Delete the WinPEGen Backup
Remove-Item -Path "$($BootMedia)_original_backup" -Force

# Add Stifler Config to registry
Mount-WindowsImage -ImagePath $BootMedia -Index 1 -Path $MountPath
$TempKey = "HKLM\TempHive"
$RegistryFilePath = "$MountPath\Windows\System32\config\SOFTWARE"
try {
    Write-host "Loading registry hive..."
    reg.exe load $TempKey $RegistryFilePath

    Set-RegistryFromJson -RegistryBasePath "HKLM:\TempHive\2Pint Software\StifleR\Client" -JsonFilePath $StiflerConfigJSON
    # Read-Host -Prompt "Press Enter to Continue"
}
catch {
    write-error "An error occurred: $_"
}
finally {
    Write-host "Unloading registry hive..."
    [gc]::Collect()
    Start-Sleep -Seconds 2
    reg.exe unload $TempKey
    Write-host "Registry hive processing completed." -ForegroundColor Green
}

if ($Cert) {
    Copy-Item -Path $Cert -Destination "$MountPath\Windows\System32" -Force 
}
Dismount-WindowsImage -Path $MountPath -Save

Pop-Location

# Friendly reminder
Write-Host ""
Write-Host "All done, but do NOT forget to add .NET Framework to the boot image"
