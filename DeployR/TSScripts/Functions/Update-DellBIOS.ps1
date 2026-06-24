<#
This Script will Detect and Update BIOS on the Dell Device - FULL OS ONLY - NOT WINPE
This is only going to work on NEWER Dell Devices, typically 2018 and newer, with BIOS that support native WMI BIOS Management.  
If you have an older Dell Device, this script will not work for you, it could be modified to be more simple, removing the checks for a BIOS password, and just running the BIOS update.
#>

#Set Variables (Just BIOS Password)
$BIOSPassword = 'P@ssw0rd'

#If you want to pull the BIOS Password from a TS Variable, use this section below after you've created a TS Variable called SECRETBIOSPASSWORD and set it to the BIOS Password you want to use.  
#This is not really any moresecure than hardcoding the password in this script.
<#
try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
    $Global:BIOSPassword = ${TSEnv:SECRETBIOSPASSWORD}
}
catch {
}
#>

#Region Functions
function Test-DellBIOSPassword {
    
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
function Test-DellBIOSWMISupport {
    
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
Function Get-DUPExitInfo {
    [CmdletBinding()]
    param(
    [ValidateRange(0,4000)]
    [int]$DUPExit
    )
    $DUPExitInfo = @(
    # Generic application return codes
    @{ExitCode = -1; DisplayName = "Unsuccessful"; Description = "DCU terminating the BIOS execution due to timeout."}
    @{ExitCode = 0; DisplayName = "Success"; Description = "The operation completed successfully."}
    @{ExitCode = 1; DisplayName = "Unsuccessful"; Description = "An error occurred during the update process; the update was not successful."}
    @{ExitCode = 2; DisplayName = "Reboot required"; Description = "Reboot the system to complete the operation."}
    @{ExitCode = 3; DisplayName = "Soft dependency error"; Description = "You attempted to update to the same version of the software or You tried to downgrade to a previous version of the software."}
    @{ExitCode = 4; DisplayName = "Hard dependency error"; Description = "The required prerequisite software was not found on your computer."}
    @{ExitCode = 5; DisplayName = "Qualification error"; Description = "A QUAL_HARD_ERROR cannot be suppressed by using the /f switch."}
    @{ExitCode = 6; DisplayName = "Rebooting computer"; Description = "The computer is being rebooted."}
    @{ExitCode = 7; DisplayName = "Password validation error"; Description = "Password not provided or incorrect password provided for BIOS execution"}
    @{ExitCode = 8; DisplayName = "Requested Downgrade is not allowed."; Description = "Downgrading the BIOS to the version run is not allowed."}
    @{ExitCode = 8; DisplayName = "RPM verification has failed"; Description = "The Linux DUP framework uses RPM verification to ensure the security of all DUP-dependent Linux utilities. If security is compromised, the framework displays a message and an RPM Verify Legend, and then exits with exit code 9."}
    @{ExitCode = 8; DisplayName = "Some other error"; Description = "This exit code is for all errors that have not been specified in BIOS exit codes 0-9. That is, battery error, EC error, HW failure, so forth."}
    )
    $DUPExitInfo | Where-Object {$_.ExitCode -eq $DUPExit}
}
Function Get-DellBIOSUpdates {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory=$False)]
    [ValidateLength(4,4)]    
    [string]$SystemSKUNumber,
    [switch]$Latest,
    [switch]$Check, #This will find the latest BIOS update and compare it to the current BIOS version
    [switch]$Flash,
    [string]$Password,
    [string]$DownloadPath
    
    )
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    if (!($SystemSKUNumber)) {
        if ($Manufacturer -notmatch "Dell"){return "This Function is only for Dell Systems, or please provide a SKU"}
        $SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    }
    
    if ($Check){
        if ($Manufacturer -notmatch "Dell"){return "This Function is only for Dell Systems"}
        else{
            [Version]$CurrentBIOSVersion = (Get-CimInstance -ClassName Win32_BIOS).SMBIOSBIOSVersion
            $LatestBIOS = Get-DCUUpdateList -SystemSKUNumber $SystemSKUNumber -updateType BIOS -Latest | Sort-Object -Property ReleaseDate -Descending
            if ($LatestBIOS.count -gt 1){
                $LatestBIOS = $LatestBIOS | Select-Object -First 1
            }
            [version]$LatestVersion = ($LatestBIOS).DellVersion
            
            if ($CurrentBIOSVersion -lt $LatestVersion){
                Write-Verbose "Current BIOS Version: $CurrentBIOSVersion"
                Write-Verbose "Latest BIOS Version: $LatestVersion"
                Write-Verbose "New BIOS Update Available"
                return $false
            }
            else {
                Write-Verbose "Current BIOS Version: $CurrentBIOSVersion"
                Write-Verbose "Latest BIOS Version: $LatestVersion"
                Write-Verbose "No New BIOS Update Available"
                return $true
            }
        }
    }
    if ($Flash){
        #Test for Bitlocker
        $BitlockerStatus = Get-BitLockerVolume -MountPoint $env:SystemDrive
        if ($BitlockerStatus -ne $null){
            if ($BitlockerStatus.ProtectionStatus -eq "On"){
                Write-Host "Bitlocker is On, Please Suspend Bitlocker before Flashing BIOS"
                return
            }
        }
        #https://www.dell.com/support/kbdoc/en-us/000136752/command-line-switches-for-dell-bios-updates
        $Updates = Get-DCUUpdateList -SystemSKUNumber $SystemSKUNumber -updateType BIOS -Latest
        $Update = $Updates | Select-Object -First 1
        $UpdatePath = $Update.Path
        $UpdateFileName = $UpdatePath -split "/" | Select-Object -Last 1
        $UpdateLocalPath = "$env:windir\temp\$UpdateFileName"
        Start-BitsTransfer -DisplayName $UpdateFileName -Source $UpdatePath -Destination $UpdateLocalPath -Description "Downloading $UpdateFileName" -RetryInterval 60 #-CustomHeaders "User-Agent:Bob" 
        if (Test-Path -Path $UpdateLocalPath){
            Write-Host "Installing $UpdateFileName, logfile: $($UpdateLocalPath).log"
            $IsPasswordSet = Test-DellBIOSPassword
            if ($IsPasswordSet -and -not $Password){
                Write-Host "BIOS Password is set, please provide the password to flash the BIOS"
                return
            }
            if ($Password -and -not $IsPasswordSet){
                $BIOSArgs = "/s /l=$UpdateLocalPath.log"
            }
            if ($Password){
                $BIOSArgs = "/s /l=$UpdateLocalPath.log /p=$Password"
            }
            else {
                $BIOSArgs = "/s /l=$UpdateLocalPath.log"
            }
            $InstallUpdate = Start-Process -FilePath $UpdateLocalPath -ArgumentList $BIOSArgs -Wait -PassThru
            Write-Host "Exit Code: $($InstallUpdate.ExitCode)"
            if ($InstallUpdate.ExitCode -ne 0){
                $ExitInfo = Get-DUPExitInfo -DUPExit $InstallUpdate.ExitCode
                Write-Host "Exit: $($InstallUpdate.ExitCode)"
                Write-Host "Code Name: $($ExitInfo.DisplayName)"
                Write-Host "Description: $($ExitInfo.Description)"
            }
            return
        }
        else {
            Write-Host "File Not Found: $UpdateFileName"
            return
        }
    }
    if ($DownloadPath){
        [void][System.IO.Directory]::CreateDirectory($DownloadPath)
        $Updates = Get-DCUUpdateList -SystemSKUNumber $SystemSKUNumber -updateType BIOS -Latest
        $Update = $Updates | Select-Object -First 1
        $UpdatePath = $Update.Path
        $UpdateFileName = $UpdatePath -split "/" | Select-Object -Last 1
        $UpdateLocalPath = "$DownloadPath\$UpdateFileName"
        Start-BitsTransfer -DisplayName $UpdateFileName -Source $UpdatePath -Destination $UpdateLocalPath -Description "Downloading $UpdateFileName" -RetryInterval 60 #-CustomHeaders "User-Agent:Bob"
        return $UpdateLocalPath
    }
    if ($Latest){
        $Updates = Get-DCUUpdateList -SystemSKUNumber $SystemSKUNumber -updateType BIOS -Latest
    }
    else {
        $Updates = Get-DCUUpdateList -SystemSKUNumber $SystemSKUNumber -updateType BIOS
    }
    return $Updates |Select-Object -Property "PackageID","Name","ReleaseDate","DellVersion" | Sort-Object -Property ReleaseDate -Descending
}

function Get-DCUUpdateList {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory=$False)]
    [ValidateLength(4,4)]    
    [string]$SystemSKUNumber,
    [ValidateSet('bios','firmware','driver','application')]
    [String[]]$updateType,
    [ValidateSet('audio','video','network','chipset','storage','BIOS','Application')]
    [String[]]$updateDeviceCategory,
    [switch]$RAWXML,
    [switch]$Latest,
    [switch]$TLDR
    )
    
    
    $temproot = "$env:windir\temp"
    #$SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    $CabPathIndexModel = "$temproot\DellCabDownloads\CatalogIndexModel.cab"
    $DellCabExtractPath = "$temproot\DellCabDownloads\DellCabExtract"
    if (!(Test-Path $DellCabExtractPath)){$null = New-Item -Path $DellCabExtractPath -ItemType Directory -Force}
    
    
    if (!($SystemSKUNumber)) {
        if ($Manufacturer -notmatch "Dell"){return "This Function is only for Dell Systems"}
        $SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    }
    $DellSKU = Get-DellSupportedModels | Where-Object {$_.systemID -match $SystemSKUNumber} | Select-Object -First 1
    if (!($DellSKU)){
        return "System SKU not found"
    }
    if (Test-Path $CabPathIndexModel){Remove-Item -Path $CabPathIndexModel -Force}
    
    
    Invoke-WebRequest -Uri "http://downloads.dell.com/$($DellSKU.URL)" -OutFile $CabPathIndexModel -UseBasicParsing
    if (Test-Path $CabPathIndexModel){
        $null = expand $CabPathIndexModel $DellCabExtractPath\CatalogIndexPCModel.xml
        [xml]$XMLIndexCAB = Get-Content "$DellCabExtractPath\CatalogIndexPCModel.xml"
        
        #DCUAppsAvailable = $XMLIndexCAB.Manifest.SoftwareComponent | Where-Object {$_.ComponentType.value -eq "APAC"}
        #$AppNames = $DCUAppsAvailable.name.display.'#cdata-section' | Select-Object -Unique
        $BaseURL = "https://$($XMLIndexCAB.Manifest.baseLocation)"
        $Components = $XMLIndexCAB.Manifest.SoftwareComponent
        if ($RAWXML){
            return $Components
        }
        $ComponentsObject = @()
        foreach ($Component in $Components){
            $Item = New-Object -TypeName PSObject
            $Item | Add-Member -MemberType NoteProperty -Name "PackageID" -Value "$($Component.packageID)"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "Category" -Value "$($Component.Category.Display.'#cdata-section')"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "Type" -Value "$($component.ComponentType.Display.'#cdata-section')"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "Name" -Value "$($Component.Name.Display.'#cdata-section')" -Force
            $Item | Add-Member -MemberType NoteProperty -Name "ReleaseDate" -Value $([DateTime]($Component.releaseDate)) -Force
            $Item | Add-Member -MemberType NoteProperty -Name "DellVersion" -Value "$($Component.dellVersion)"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "VendorVersion" -Value "$($Component.vendorVersion)"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "PackageType" -Value "$($Component.packageType)"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "Path" -Value "$BaseURL/$($Component.path)" -Force		
            $Item | Add-Member -MemberType NoteProperty -Name "Description" -Value "$($component.Description.Display.'#cdata-section')" -Force		
            $ComponentsObject += $Item 
        }
        if ($updateType){
            $ComponentsObject = $ComponentsObject | Where-Object {$_.Type -in $updateType}
        }
        if ($updateDeviceCategory){
            $ComponentsObject = $ComponentsObject | Where-Object {$_.Category -in $updateDeviceCategory}
        }
        if ($TLDR) {
            $ComponentsObject = $ComponentsObject | Select-Object -Property Name,ReleaseDate,DellVersion,Path
        }
        if ($Latest){
            $ComponentsObject = $ComponentsObject | Sort-Object -Property ReleaseDate -Descending
            $hash = @{}
            foreach ($ComponentObject in $ComponentsObject) {
                if (-not $hash.ContainsKey($ComponentObject.Name)) {
                    $hash[$ComponentObject.Name] = $ComponentObject
                }
            }
            $ComponentsObject = $hash.Values 
        }
        return $ComponentsObject
    }
}
function Get-DellSupportedModels {
    [CmdletBinding()]
    
    $CabPathIndex = "$env:ProgramData\EMPS\DellCabDownloads\CatalogIndexPC.cab"
    $DellCabExtractPath = "$env:ProgramData\EMPS\DellCabDownloads\DellCabExtract"
    
    # Pull down Dell XML CAB used in Dell Command Update ,extract and Load
    if (!(Test-Path $DellCabExtractPath)){$null = New-Item -Path $DellCabExtractPath -ItemType Directory -Force}
    Write-Verbose "Downloading Dell Cab"
    Invoke-WebRequest -Uri "https://downloads.dell.com/catalog/CatalogIndexPC.cab" -OutFile $CabPathIndex -UseBasicParsing -Proxy $ProxyServer
    If(Test-Path "$DellCabExtractPath\DellSDPCatalogPC.xml"){Remove-Item -Path "$DellCabExtractPath\DellSDPCatalogPC.xml" -Force}
    Start-Sleep -Seconds 1
    if (test-path $DellCabExtractPath){Remove-Item -Path $DellCabExtractPath -Force -Recurse}
    $null = New-Item -Path $DellCabExtractPath -ItemType Directory
    Write-Verbose "Expanding the Cab File..." 
    $null = expand $CabPathIndex $DellCabExtractPath\CatalogIndexPC.xml
    
    Write-Verbose "Loading Dell Catalog XML.... can take awhile"
    [xml]$XMLIndex = Get-Content "$DellCabExtractPath\CatalogIndexPC.xml"
    
    
    $SupportedModels = $XMLIndex.ManifestIndex.GroupManifest
    $SupportedModelsObject = @()
    foreach ($SupportedModel in $SupportedModels){
        $SPInventory = New-Object -TypeName PSObject
        $SPInventory | Add-Member -MemberType NoteProperty -Name "SystemID" -Value "$($SupportedModel.SupportedSystems.Brand.Model.systemID)" -Force
        $SPInventory | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($SupportedModel.SupportedSystems.Brand.Model.Display.'#cdata-section')"  -Force
        $SPInventory | Add-Member -MemberType NoteProperty -Name "URL" -Value "$($SupportedModel.ManifestInformation.path)" -Force
        $SPInventory | Add-Member -MemberType NoteProperty -Name "Date" -Value "$($SupportedModel.ManifestInformation.version)" -Force		
        $SupportedModelsObject += $SPInventory 
    }
    return $SupportedModelsObject
}

#endregion Functions

#Main Script

Write-Host "Checking for Dell BIOS updates..."
$Status = Get-DellBIOSUpdates -Check -Verbose

#If the status is false, then we have a new BIOS update available, so we will flash it now
if ($Status -eq $false){
    Write-Host "Dell BIOS update available. Flashing now..."
    Get-DellBIOSUpdates -Flash -Password $BIOSPassword
    Write-Host "Dell BIOS update complete, will update upon reboot..."
    $tsenv:SMSTSRebootRequested = "true"
}
else {
    Write-Host "No Dell BIOS updates available."
}