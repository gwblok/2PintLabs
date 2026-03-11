#Requires -Version 5
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter()] [String[]] [alias("Architecture")] $platforms = @("amd64", "arm64"),
    [Parameter()] [string] $DeployRClientPath = "",
    [Parameter()] [string] $CertPath = "",
    [Parameter()] [string] $DriverPath = "",
    [Parameter()] [string] $StifleRPath = "",
    [Parameter()] [string] $WinREPath = "",
    [Parameter()] [string] $ExtraFilesPath = "",
    [Parameter()] [Switch] $GenerateISO = $false,
    [Parameter()] [Switch] $Regenerate
)

#region --------------------------------------------------[Initialisations]--------------------------------------------------------

# Set Error Action
$ErrorActionPreference = 'Stop'
$maxlogfilesize = 5Mb
$VerboseLogging = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent
if ($PSBoundParameters['Verbose']) {
    $PSDefaultParameterValues = @{"*:Verbose" = $true }
}

#endregion ------------------------------------------------[Initialisations]--------------------------------------------------------

#region --------------------------------------------------[Logging Functions]-------------------------------------------------------

Function Start-Log {
    [CmdletBinding()]
    param (
        [ValidateScript({ Split-Path $_ -Parent | Test-Path })]
        [string]$FilePath
    )

    try {
        if (!(Test-Path $FilePath)) {
            $filepath = (New-Item $FilePath -Type File).FullName
        }
        else {
            $FilePath = (Get-Item $FilePath).FullName
        }
  
        $global:ScriptLogFilePath = $FilePath
        [int32]$LogTimeZoneBiasInt = [timezone]::CurrentTimeZone.GetUtcOffset([datetime]::Now).TotalMinutes
        if ($LogTimeZoneBiasInt -ge 0) {
            [string]$script:LogTimeZoneBias = "+{0:D3}" -f $LogTimeZoneBiasInt
        }
        else {
            [string]$script:LogTimeZoneBias = "{0:D3}" -f $LogTimeZoneBiasInt
        }
    }
    catch {
        Write-Log -Message $_.Exception.Message -LogLevel 3 -Verbose
    }
}

Function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
    
        [Parameter()]
        [ValidateSet(1, 2, 3)]
        [int]$LogLevel = 1
    )    
    [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
    [string]$TimeGenerated = $LogTime + $script:LogTimeZoneBias
    $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
    
    if ($MyInvocation.ScriptName) {
        $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "$($MyInvocation.ScriptName | Split-Path -Leaf):$($MyInvocation.ScriptLineNumber)", $LogLevel
    }
    else {
        $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "Unknown", $LogLevel
    }
    $Line = $Line -f $LineFormat
  
    # Always write to log file
    if (Test-Path $ScriptLogFilePath) { 
        if ((Get-Item $ScriptLogFilePath).length -ge $maxlogfilesize) {
            if (Test-Path "$($ScriptLogFilePath.Substring(0,$ScriptLogFilePath.Length-1))_") {
                Remove-Item -Path "$($ScriptLogFilePath.Substring(0,$ScriptLogFilePath.Length-1))_" -Force
            }
            Rename-Item -Path $ScriptLogFilePath -NewName "$($ScriptLogFilePath.Substring(0,$ScriptLogFilePath.Length-1))_" -Force
        }
    }
  
    # Write to console 
    switch ($LogLevel) {
        1 { $TextColor = "Gray" }   # Normal messages
        2 { $TextColor = "Yellow" } # Warning messages
        3 { $TextColor = "Red" }    # Error messages
        Default { $TextColor = "Gray" }
    }
    Write-Host -ForegroundColor $TextColor "$LogTime - $Message"
  
    $stream = [System.IO.StreamWriter]::new($ScriptLogFilePath, $true, ([System.Text.Utf8Encoding]::new()))
    $stream.WriteLine("$Line")
    $stream.close()
}

#endregion -------------------------------------------------[Logging Functions]-------------------------------------------------------

#region --------------------------------------------------[Core Functions]-----------------------------------------------------------

Function Get-AdkPaths {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet('amd64', 'x86', 'arm64')]
        [string]$Arch = $Env:PROCESSOR_ARCHITECTURE
    )
    $InstalledRoots32 = 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots'
    $InstalledRoots64 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots'
    if (Test-Path $InstalledRoots64) {
        $KitsRoot10 = Get-ItemPropertyValue -Path $InstalledRoots64 -Name 'KitsRoot10'
    }
    elseif (Test-Path $InstalledRoots32) {
        $KitsRoot10 = Get-ItemPropertyValue -Path $InstalledRoots32 -Name 'KitsRoot10'
    }
    else {
        Write-Log -Message "Unable to determine ADK Path" -LogLevel 2 -Verbose
        Break
    }
    $AdkRoot = Join-Path $KitsRoot10 'Assessment and Deployment Kit'
    $WinPERoot = Join-Path $AdkRoot 'Windows Preinstallation Environment'
    if (-NOT (Test-Path $WinPERoot -PathType Container)) {
        Write-Log -Message "Cannot find WinPERoot: $WinPERoot" -LogLevel 2 -Verbose
        $WinPERoot = $null
        break
    }
    $PathDeploymentTools = Join-Path $AdkRoot (Join-Path 'Deployment Tools' $Arch)
    $Results = [PSCustomObject] @{
        AdkRoot             = $AdkRoot
        PathBCDBoot         = Join-Path $PathDeploymentTools 'BCDBoot'
        PathDeploymentTools = $PathDeploymentTools
        PathDISM            = Join-Path $PathDeploymentTools 'DISM'
        PathOscdimg         = Join-Path $PathDeploymentTools 'Oscdimg'
        PathUsmt            = Join-Path $AdkRoot (Join-Path 'User State Migration Tool' $Arch)
        PathWinPE           = Join-Path $WinPERoot $Arch
        PathWinPEMedia      = Join-Path (Join-Path $WinPERoot $Arch) 'Media'
        PathWinSetup        = Join-Path $AdkRoot (Join-Path 'Windows Setup' $Arch)
        WinPEOCs            = Join-Path (Join-Path $WinPERoot $Arch) 'WinPE_OCs'
        WinPERoot           = $WinPERoot
        WimSourcePath       = Join-Path (Join-Path $WinPERoot $Arch) 'en-us\winpe.wim'
        
        bcdbootexe          = Join-Path $PathDeploymentTools (Join-Path 'BCDBoot' 'bcdboot.exe')
        bcdeditexe          = Join-Path $PathDeploymentTools (Join-Path 'BCDBoot' 'bcdedit.exe')
        bootsectexe         = Join-Path $PathDeploymentTools (Join-Path 'BCDBoot' 'bootsect.exe')
        dismexe             = Join-Path $PathDeploymentTools (Join-Path 'DISM' 'dism.exe')
        efisysbin           = Join-Path $PathDeploymentTools (Join-Path 'Oscdimg' 'efisys.bin')
        efisysnopromptbin   = Join-Path $PathDeploymentTools (Join-Path 'Oscdimg' 'efisys_noprompt.bin')
        etfsbootcom         = Join-Path $PathDeploymentTools (Join-Path 'Oscdimg' 'etfsboot.com')
        imagexexe           = Join-Path $PathDeploymentTools (Join-Path 'DISM' 'imagex.exe')
        oa3toolexe          = Join-Path $PathDeploymentTools (Join-Path 'Licensing\OA30' 'oa3tool.exe')
        oscdimgexe          = Join-Path $PathDeploymentTools (Join-Path 'Oscdimg' 'oscdimg.exe')
        pkgmgrexe           = Join-Path $PathDeploymentTools (Join-Path 'DISM' 'pkgmgr.exe')
    }
    Return $Results
}

Function Set-RegistryKeyOwnership {
    param (
        [Parameter(Mandatory)]
        [string]$RegistryKeyPath
    )

    $Owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RegistryKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::takeownership)
    $acl = New-Object System.Security.AccessControl.RegistrySecurity
    $acl.SetOwner([System.Security.Principal.NTAccount]"$Owner")
    $key.SetAccessControl($acl)

    $acl = $key.GetAccessControl()
    $rule = New-Object System.Security.AccessControl.RegistryAccessRule ("$Owner", "FullControl", "Allow")
    $acl.AddAccessRule($rule)
    $key.SetAccessControl($acl)
    $key.Close()

    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RegistryKeyPath, $true)
    $subKeys = $key.GetSubKeyNames()
    if ($subKeys) {
        foreach ($subKey in $subKeys) {
            Set-RegistryKeyOwnership -RegistryKeyPath "$RegistryKeyPath\$subKey"
        }
        $key.Close()
    }
}

Function Install-WinPEPackage {
    param(
        [string]$PackageName,
        [string]$BasePath,
        [string]$MountPath
    )
    
    Write-Log -Message "Adding package: $PackageName" -LogLevel 1
    
    try {
        IF (Test-Path -path "$BasePath\$PackageName.cab") { 
            Add-WindowsPackage -PackagePath "$BasePath\$PackageName.cab" -Path $MountPath -ErrorAction Stop | Out-Null 
            Write-Log -Message "Successfully added $PackageName" -LogLevel 1
        }
        IF (Test-Path -path "$BasePath\en-us\$PackageName`_en-us.cab") { 
            Add-WindowsPackage -PackagePath "$BasePath\en-us\$PackageName`_en-us.cab" -Path $MountPath -ErrorAction Stop | Out-Null 
            Write-Log -Message "Successfully added $PackageName`_en-us.cab" -LogLevel 1
        }
        return $true
    }
    catch {
        Write-Log -Message "Failed to add $PackageName : $_" -LogLevel 2
        return $false
    }
}

function New-TemporaryDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    [string] $name = [System.Guid]::NewGuid()
    $newDir = New-Item -ItemType Directory -Path (Join-Path $parent $name)
    return $newDir.FullName
}

function Copy-File {
    param (
        [string]$path,
        [string]$Destination,
        [switch]$Force = $false,
        [switch]$Recurse = $false
    )
    if (Test-Path $path) {
        if ($Recurse) {
            Write-Log -Message "Recursively copying $path to $Destination" -LogLevel 1
            Copy-Item -Path $path -Destination $Destination -Recurse -Force:$Force
        }
        else {

            Write-Log -Message "Copying $path to $Destination" -LogLevel 1
            Copy-Item -Path $path -Destination $Destination -Force:$Force
        }
    }
    else {
        Write-Log -Message "Source file not found: $path" -LogLevel 2
    }
}

#endregion --------------------------------------------------[Core Functions]-----------------------------------------------------------

# Start logging
Start-Log -FilePath "$TempDir\$(Split-Path -Leaf $MyInvocation.MyCommand.Name).log"
Write-Log -Message "Starting PEPrep script." -LogLevel 1

# Get settings
$InstallDir = Resolve-Path "$PSScriptRoot\..\.."
Write-Log -Message "DeployR is installed at $InstalLDir"
Import-Module "$InstallDir\Client\PSModules\DeployR.Utility" -Force
$ContentLocation = Get-DeployRSetting "ContentLocation"
Write-Log -Message "ContentLocation set to $ContentLocation" -LogLevel 1
$DownloadsLocation = "$ContentLocation\Downloads"
if (-not (Test-Path "$DownloadsLocation\DownloadInfo.json")) {
    throw "Needed content has not yet been downloaded, unable to continue."
}
$DownloadInfo = Get-Content "$DownloadsLocation\DownloadInfo.json" | ConvertFrom-Json
$TempDir = "$ContentLocation\Content\TEMP"

# Find CMTrace
$cmTrace = ""
if (Test-Path ".\CMTrace.exe") {
    $cmTrace = ".\CMTrace.exe"
} 
elseif (Test-Path "HKLM:\Software\Microsoft\SMS\Setup") {
    $cmDir = Get-ItemPropertyValue -Path "HKLM:\Software\Microsoft\SMS\Setup" -Name "Installation Directory"
    if (Test-Path "$cmDir\OSD\bin\x64\cmtrace.exe") {
        $cmTrace = "$cmDir\OSD\bin\x64\cmtrace.exe"
    }
}

# Create temporary folder if it doesn't exist.  We don't want to use %TEMP%.
if (-not (Test-Path $TempDir)) {
    New-Item -Path $TempDir -ItemType Directory | Out-Null
}

$Destination = "$ContentLocation\Content\Boot"
if (-Not (Test-Path $Destination)) {
    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
}

$platforms | ForEach-Object {

    $platform = $_
    if ($platform -eq "amd64") {
        $shortPlatform = "x64"
    }
    else {
        $shortPlatform = $platform
    }

    $ScratchDir = "$TempDir\Scratch_$platform"
    if (-not (Test-Path $ScratchDir)) {
        New-Item -Path $ScratchDir -ItemType Directory | Out-Null
    }
    
    # Validate ADK and other essential files
    $ADKPaths = Get-AdkPaths -Arch $platform -ErrorAction SilentlyContinue
    if (!($ADKPaths)) {
        Write-Log -Message "NO ADK Found, aborting script..." -LogLevel 3
        Break
    }
    $ADKWinPE = Get-ChildItem -Path $ADKPaths.PathWinPE -Filter *.wim -Recurse
    $ADKWinPEInfo = Get-WindowsImage -ImagePath $ADKWinPE.FullName -Index 1

    $peRoot = $ADKPaths.WinPERoot
    $adkRoot = $ADKPaths.AdkRoot

    Write-Log -Message "ADK WinPE Version: $($ADKWinPEInfo.Version)" -LogLevel 1
    Write-Log -Message "ADK WinPE Architecture: $($ADKWinPEInfo.ImageName)" -LogLevel 1
    
    # Validate needed downloads are present
    "aspnetcore-runtime", "dotnet-runtime", "windowsdesktop-runtime" | ForEach-Object {
        $found = Get-ChildItem "$DownloadsLocation\$_*-win-$shortPlatform.zip"
        if ($found.Count -eq 0)
        {
            throw "Error building Windows PE: Unable to find $_*-win-$shortPlatform.zip"     
        }
    }
    if (-not (Test-Path "$DownloadsLocation\PowerShell-$($DownloadInfo.PowerShellVersion)-win-$shortPlatform.zip"))
    {
        throw "Error building Windows PE: Unable to find PowerShell-$($DownloadInfo.PowerShellVersion)-win-$shortPlatform.zip"     
    }

    ############################################
    # Phase 1:  Generate a base Windows PE image
    ############################################

    if (-not (Test-Path "$Destination\winpe_base_$platform.wim") -or $Regenerate) {
 
        # ********
        # Initialization
        # ********

        # Copy the BCD file to the destination
        Copy-File ".\BCD" "$Destination" -Force
        
        # Make a copy of either the WinRE wim (if specified) or the ADK WinPE wim
        if (Test-Path "$WinREPath\winre.wim") {
            $peFile = "$WinREPath\winre.wim"
            Write-Log -Message "Using Windows RE file $peFile as base."
        }
        else {
            $peFile = "$peRoot\$platform\en-us\winpe.wim";
            Write-Log -Message "No Windows RE file found, using vanilla WinPE as base."
        }
        if (-not (Test-Path $peFile)) {
            Write-Log -Message "Windows PE file " + $peFile + " does not exist." -LogLevel 3
            return 3
        }
        $peNew = "$TempDir\winpe_base_$platform.wim"
        $peExported = "$Destination\winpe_base_$platform.wim"
        Copy-File -Path $peFile -Destination $peNew -Force

        # Check the version
        $imageInfo = Get-WindowsImage -ImagePath $peFile -Index 1 
        Write-Log -Message "Windows PE build: $($imageInfo.Version)"
        $peBuild = ([version]$imageInfo.Version).Build
        $adkBuild = ([version]$ADKWinPEInfo.Version).Build
        if ($peBuild -ne $adkBuild) {
            Write-Log -Message "Windows PE version ($peBuild) does not match the ADK version ($adkBuild)" -LogLevel 2
        }

        # Mount the winpe.wim
        $peMount = "$TempDir\mount_$platform"
        if (-not (Test-Path $peMount)) {
            New-Item -ItemType Directory -Path $peMount -Force | Out-Null
        }

        if (Get-ChildItem -Path $peMount) {
            # Clean up old mountpoint
            Write-Log -Message "Cleaning up old mountpoint."
            [GC]::Collect()
            reg.exe unload HKLM\PESystem | Write-Verbose
            reg.exe unload HKLM\PESoftware | Write-Verbose
            Dismount-WindowsImage -Path $peMount -Discard -ErrorAction SilentlyContinue | Write-Verbose
        }        

        Write-Log -Message "Mounting Windows PE image."
        Mount-WindowsImage -Path $peMount -ImagePath $peNew -Index 1 -ScratchDirectory $ScratchDir | Write-Verbose

        # ********
        # Add/remove optional components
        # ********

        # Add the needed components to it
        $featuresToEnable = @(
            "WinPE-WMI",
            "WinPE-NetFX",
            "WinPE-PowerShell",
            "WinPE-SecureStartup",
            "WinPE-StorageWMI",
            "WinPE-DismCmdlets",
            "WinPE-EnhancedStorage",
            "WinPE-SecureBootCmdlets",
            "WinPE-x64-Support"
        )
        
        $WinOCPath = "$($ADKPaths.WinPERoot)\$platform\WinPE_OCs"
        $featuresToEnable | ForEach-Object {
            Install-WinPEPackage -PackageName $_ -BasePath $WinOCPath -MountPath $peMount | Out-Null
        }

        $featuresToDisable = @(
            "Microsoft-Windows-WinPE-Speech-TTS-Package",
            "Microsoft-Windows-WinPE-ATBroker-Package",
            "Microsoft-Windows-WinPE-Narrator-Package",
            "Microsoft-Windows-WinPE-AudioDrivers-Package",
            "Microsoft-Windows-WinPE-AudioCore-Package",
            "Microsoft-Windows-WinPE-SRH-Package",
            "WinPE-HTA",
            "WinPE-Scripting"
            "WinPE-WDS-Tools"
        )
        $featuresToDisable | ForEach-Object {
            Write-Log -Message "Removing $_" -LogLevel 1
            & DISM /Image:$peMount /Disable-Feature /FeatureName:$_ /Remove > $null 2>&1
        }

        # Log the list of features
        Write-Log -Message "Current feature list:"
        & DISM /Image:$peMount /get-features /format:table

        # ********
        # Registry work.  Do it now so that there aren't any in-use errors later on.
        # ********

        # Mount the registry
        Write-Log -Message "Mounting registry hives."
        reg.exe load HKLM\PESystem "$peMount\Windows\system32\config\SYSTEM" | Write-Verbose
        reg.exe load HKLM\PESoftware "$peMount\Windows\system32\config\SOFTWARE" | Write-Verbose
        Write-Log -Message "Making registry edits."

        # Copy timezone info from the server
        Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\TimeZoneInformation" | Select-Object -ExcludeProperty "PS*" | Set-ItemProperty -Path "HKLM:\PESystem\ControlSet001\Control\TimeZoneInformation" -Force

        # Force real time clock to be UTC
        Set-ItemProperty -Path "HKLM:\PESystem\ControlSet001\Control\TimeZoneInformation" -Name "RealTimeIsUniversal" -Value 1

        # Make sure the background points to winpe.jgp (doesn't by default for WinRE)
        Set-ItemProperty -Path "HKLM:\PESoftware\Microsoft\Windows NT\CurrentVersion\WinPE" -Name "CustomBackground" -Value "%SystemRoot%\system32\winpe.jpg" -Type ExpandString

        # Update the dotnet shared version location
        New-Item -ItemType Directory -Path "HKLM:\PESoftware\dotnet\Setup\InstalledVersions\$shortPlatform\sharedhost" -Force | Out-Null
        Set-ItemProperty -Path "HKLM:\PESoftware\dotnet\Setup\InstalledVersions\$shortPlatform\sharedhost" -Name "Path" -Value "X:\Program Files\dotnet\" | Out-Null

        # Update the path
        $RegistryKey = "HKLM:\PESystem\ControlSet001\Control\Session Manager\Environment"
        $path = (Get-Item -Path $RegistryKey).GetValue(
            'PATH', # the registry-value name
            $null, # the default value to return if no such value exists.
            'DoNotExpandEnvironmentNames' # the option that suppresses expansion
        )
        $path += ";X:\Program Files\dotnet\;X:\Program Files\PowerShell\7"
        Set-ItemProperty -Path $RegistryKey -Name Path -Value $path -Type ExpandString | Out-Null

        # Update the PSModulePath
        $CurrentPSModulePath = (Get-Item -path $RegistryKey).GetValue('PSModulePath', '', 'DoNotExpandEnvironmentNames')
        $NewPSModulePath = $CurrentPSModulePath + ";%ProgramFiles%\PowerShell\;%ProgramFiles%\PowerShell\7\;%SystemRoot%\system32\config\systemprofile\Documents\PowerShell\Modules\"
        New-ItemProperty -Path $RegistryKey -Name "PSModulePath" -PropertyType ExpandString -Value $NewPSModulePath -Force | Out-Null

        # Add registry keys for PowerShell Gallery support
        $APPDATA = "%SystemRoot%\System32\Config\SystemProfile\AppData\Roaming"
        New-ItemProperty -Path $RegistryKey -Name "APPDATA" -PropertyType ExpandString -Value $APPDATA -Force | Out-Null
        $HOMEDRIVE = "%SystemDrive%"
        New-ItemProperty -Path $RegistryKey -Name "HOMEDRIVE" -PropertyType ExpandString -Value $HOMEDRIVE -Force | Out-Null
        $HOMEPATH = "%SystemRoot%\System32\Config\SystemProfile"
        New-ItemProperty -Path $RegistryKey -Name "HOMEPATH" -PropertyType ExpandString -Value $HOMEPATH -Force | Out-Null
        $LOCALAPPDATA = "%SystemRoot%\System32\Config\SystemProfile\AppData\Local"
        New-ItemProperty -Path $RegistryKey -Name "LOCALAPPDATA" -PropertyType ExpandString -Value $LOCALAPPDATA -Force | Out-Null

        # Avoid PowerShell telling you about new versions
        New-ItemProperty -Path $RegistryKey -Name "POWERSHELL_UPDATECHECK" -Value "LTS" -Force | Out-Null

        # ********
        # Whacking.
        # ********

        # Whack PowerShell 5.1 and .NET Framework to save space
        #Write-Host "Whacking..."
        #takeown /f "$peMount\Windows\Microsoft.NET" /r
        #icacls "$peMount\Windows\Microsoft.NET" /grant *S-1-1-0:f /t | Write-Verbose
        #Remove-Item "$peMount\Windows\Microsoft.NET" -Recurse -Force

        #takeown /f "$peMount\Windows\WinSXS\*.*" /r
        #icacls "$peMount\Windows\WinSXS\*.*" /grant *S-1-1-0:f /t | Write-Verbose
        #Remove-Item "$peMount\Windows\WinSXS\*.*" -Recurse -Force

        # Causes issues with driver injection with ARM64 boot images
        #takeown /f "$peMount\Windows\SysWOW64\*.*" /r
        #icacls "$peMount\Windows\SysWOW64\*.*" /grant *S-1-1-0:f /t | Write-Verbose
        #Remove-Item "$peMount\Windows\SysWOW64\*.*" -Recurse -Force

        takeown /f "$peMount\Windows\System32\WindowsPowerShell\v1.0\*.*" | Write-Verbose
        icacls "$peMount\Windows\System32\WindowsPowerShell\v1.0\*.*" /grant *S-1-1-0:f | Write-Verbose
        Get-ChildItem "$peMount\Windows\System32\WindowsPowerShell\v1.0\*.*" -File | Remove-Item -Force

        # ********
        # Add other stuff
        # ********

        # Create the needed folders, one level at a time (due to ACL inheritance)
        if (-not (Test-Path "$peMount\Windows\Boot\DVD"))
        {
            takeown /f "$peMount\Windows\Boot" /r | Write-Verbose
            icacls "$peMount\Windows\Boot" /grant *S-1-1-0:f | Write-Verbose
            New-Item -ItemType Directory -Path "$peMount\Windows\Boot\DVD" -Force -ErrorAction SilentlyContinue | Out-Null
        }
        if (-not (Test-Path "$peMount\Windows\Boot\DVD\EFI"))
        {
            takeown /f "$peMount\Windows\Boot\DVD" /r | Write-Verbose
            icacls "$peMount\Windows\Boot\DVD" /grant *S-1-1-0:f | Write-Verbose
            New-Item -ItemType Directory -Path "$peMount\Windows\Boot\DVD\EFI" -Force -ErrorAction SilentlyContinue | Out-Null
        }
        # Add files for wimboot to find if they aren't already present
        if (-not (Test-Path "$peMount\Windows\Boot\DVD\EFI\boot.sdi"))
        {
            takeown /f "$peMount\Windows\Boot\DVD\EFI" /r | Write-Verbose
            icacls "$peMount\Windows\Boot\DVD\EFI" /grant *S-1-1-0:f | Write-Verbose

            Write-Log -Message "Adding boot.sdi to \Windows\Boot\DVD\EFI\"
            Copy-File "$peRoot\$platform\Media\Boot\boot.sdi" "$peMount\Windows\Boot\DVD\EFI\"
        }
        if (-not (Test-Path "$peMount\Windows\Boot\DVD\EFI\BCD"))
        {
            takeown /f "$peMount\Windows\Boot\DVD\EFI" /r | Write-Verbose
            icacls "$peMount\Windows\Boot\DVD\EFI" /grant *S-1-1-0:f | Write-Verbose

            Write-Log -Message "Adding BCD to \Windows\Boot\DVD\EFI\"
            Copy-File "$peRoot\$platform\Media\EFI\Microsoft\Boot\BCD" "$peMount\Windows\Boot\DVD\EFI\"
        }

        # Add .NET 8 (defaults to the latest LTS release)
        Write-Log -Message "Adding .NET 8"
        "aspnetcore-runtime", "dotnet-runtime", "windowsdesktop-runtime" | ForEach-Object {
            Get-ChildItem "$DownloadsLocation\$_*-win-$shortPlatform.zip" | ForEach-Object {
                Write-Log -Message "Extracting $($_.FullName) to $peMount\Program Files\dotnet"
                Expand-Archive -Path $_.FullName -DestinationPath "$peMount\Program Files\dotnet" -Force
            }
        }

        # Set the .NET 8 version
        $version = $DownloadInfo.DotNetVersion  # Default, just in case
        Get-ChildItem "$peMount\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App" -Directory | Measure-Object -Property Name -Maximum | ForEach-Object {
            $version = $_.Maximum
            Write-Log -Message "Found version $version of .NET Core"
        }
        Set-ItemProperty -Path "HKLM:\PESoftware\dotnet\Setup\InstalledVersions\$shortPlatform\sharedhost" -Name "Version" -Value $version | Out-Null
    
        # Add PowerShell
        Write-Log -Message "Adding PowerShell 7"
        $ps7File = "$DownloadsLocation\PowerShell-$($DownloadInfo.PowerShellVersion)-win-$shortPlatform.zip"
        New-Item -ItemType Directory -Path "$peMount\Program Files\PowerShell\7" | Out-Null
        Write-Log -Message "Extracting $ps7File to $peMount\Program Files\PowerShell\7"
        Expand-Archive -Path $ps7File -DestinationPath "$peMount\Program Files\PowerShell\7"

        # Add the StifleR Client
        if ($StifleRPath -ne "" -and (Test-Path $StifleRPath)) {

            Write-Log -Message "Adding StifleR Client App"

            # Get the files
            $msiFile = Get-ChildItem "$StifleRPath\*.msi" -File | Select-Object -First 1
            Write-Log -Message "StifleR client app MSI file: $msiFile"
            $configFile = Get-ChildItem "$StifleRPath\*.2psimport" -File | Select-Object -First 1
            Write-Log -Message "StifleR client app config file: $configFile"

            # Extract the MSI
            if (Test-Path "$TempDir\StifleRClientApp") {
                Remove-Item "$TempDir\StifleRClientApp" -Recurse
            }
            New-Item -ItemType Directory -Path "$TempDir\StifleRClientApp" | Out-Null
            Push-Location "$InstallDir\WebServer\Imports\ContentItems\00000000-0000-0000-0000-000000000002\1\Tools\x64\ExtractMSI"
            .\TwoPint.DeployR.ExtractMSI.exe $msiFile "$TempDir\StifleRClientApp" | Write-Verbose
            Pop-location

            # Whack what we don't need to reduce the size
            $ps = (Get-Item "$TempDir\StifleRClientApp\**\2Pint Software").FullName
            "$ps\StifleR Client\TwoPint.Peerdist.BlueGreenLeader","$ps\StifleR Client\iPerf3","$ps\StifleR Client\TwoPint.SnmpAnalyzer" | ForEach-Object {
                if (Test-Path $_)
                {
                    Write-Log "Removing unneeded folder: $_"
                    Remove-Item $_ -Recurse -Force
                }
            }

            # Copy it to the right place
            New-Item -ItemType Directory -Path "$peMount\Program Files\2Pint Software" | Out-Null
            Copy-File "$ps\*" "$peMount\Program Files\2Pint Software\" -Recurse -Force

            # Copy the config file
            if ($null -eq $configFile) {
                Write-Warning "No StifleR Client config file found to include, StifleR client will not be able to communicate with the StifleR server."
            }
            elseif (Test-Path $configFile) {
                Copy-File $configFile "$peMount\Program Files\2Pint Software\StifleR Client\" -Force
            }
            else {
                Write-Warning "File not found: $configFile"
            }

            # Create the service
            $RegistryKey = "HKLM:\PESystem\ControlSet001\Services\StifleRClient"
            New-Item -Path "HKLM:\PESystem\ControlSet001\Services" -Name "StifleRClient" | Out-Null
            New-ItemProperty -Path $RegistryKey -Name "ImagePath" -PropertyType ExpandString -Value "%ProgramFiles%\2Pint Software\StifleR Client\StifleR.ClientApp.exe" -Force | Out-Null
            New-ItemProperty -Path $RegistryKey -Name "ObjectName" -PropertyType String -Value "LocalSystem" -Force | Out-Null
            New-ItemProperty -Path $RegistryKey -Name "Start" -PropertyType DWord -Value 3 -Force | Out-Null
            New-ItemProperty -Path $RegistryKey -Name "ErrorControl" -PropertyType DWord -Value 1 -Force | Out-Null
            New-ItemProperty -Path $RegistryKey -Name "Type" -PropertyType DWord -Value 16 -Force | Out-Null
        }

        # Unmount the registry
        [GC]::Collect()
        Write-Log -Message "Unmounting registry hives."
        reg.exe unload HKLM\PESystem | Write-Verbose
        reg.exe unload HKLM\PESoftware | Write-Verbose

        # Inject any needed update
        if (Test-Path ".\$platform\Updates") {
            Write-Log -Message "Injecting updates from .\$platform\Updates"
            Get-ChildItem -Path ".\$platform\Updates" | ForEach-Object {
                $Update = $_
                Write-Log -Message "Injecting update $($Update.Name)"
                try {
                    Add-WindowsPackage -Path $peMount -PackagePath $Update.FullName -ErrorAction Stop
                } catch {
                    Write-Log -Message "Failed to add update $($Update.Name) : $_"
                }
            }
        }

        # Unmount and commit
        Write-Log -Message "Unmounting base Windows PE image."
        Dismount-WindowsImage -Path $peMount -Save | Write-Verbose

        # Export the image to reduce its size
        Write-Log -Message "Exporting base Windows PE image to reduce size."
        if (Test-Path $peExported) {
            Remove-Item $peExported -Force  
        }
        Export-WindowsImage -SourceImagePath $peNew -DestinationImagePath $peExported -SourceIndex 1 | Out-Null
    }

    ############################################
    # Phase 2: Add latest DeployR files, drivers, etc.
    ############################################

    # Copy the base winpe.wim
    $peFile = "$Destination\winpe_base_$platform.wim";
    if (-not (Test-Path $peFile)) {
        Write-Log -Message "Base Windows RE file " + $peFile + " does not exist." -LogLevel 3
        return 3
    }
    $peNew = "$TempDir\winpe_$platform.wim"
    $peExported = "$Destination\winpe_$platform.wim"
    Copy-File -Path $peFile -Destination $peNew -Force

    # Mount the winpe.wim
    $peMount = "$TempDir\mount_$platform"
    if (-not (Test-Path $peMount)) {
        New-Item -ItemType Directory -Path $peMount -Force | Out-Null
    }
    Write-Log -Message "Mounting boot image for WinPE cleanup." -LogLevel 1
    if (Get-ChildItem -Path $peMount) {
        # Clean up old mountpoint
        Dismount-WindowsImage -Path $peMount -Discard -ErrorAction SilentlyContinue | Write-Verbose
    }
    Mount-WindowsImage -Path $peMount -ImagePath $peNew -Index 1 -ScratchDirectory $ScratchDir | Write-Verbose

    if ($DefaultWifiProfile) {
        Write-Log -Message "Copying default WiFi profile." -LogLevel 1
        Copy-File -Path $DefaultWifiProfile -Destination "$peMount\Windows\System32" -Force
    }

    # Inject WifiSupport
    if (Test-Path ".\WifiSupport\$shortPlatform") {
        $DLLs = Get-ChildItem -Path ".\WifiSupport\$shortPlatform" -Filter *.dll
        foreach ($DLL in $DLLs) {
            Write-Log -Message "Copying DLL $($DLL.Name)" -LogLevel 1
            Copy-File -Path $DLL.FullName -Destination "$peMount\Windows\System32" -Force
            # Write-Log -Message $($(Copy-File -Path $DLL.FullName -Destination "$peMount\Windows\System32" -Force) 4>&1) -LogLevel 1
        }
    }

    Write-Log -Message "Saving extra files, modules and performing final cleanup." -LogLevel 1
    if ($AddSMSTSiniFile -eq $true) {
        if (!(Test-Path "$BuildRoot\ExtraFiles\Windows\smsts.ini")) {
            $SMSTSini | Out-File -FilePath "$BuildRoot\ExtraFiles\Windows\smsts.ini" -Encoding utf8
        }
    }


    # ********
    # Inject drivers, certs, etc.
    # ********

    # Inject any needed drivers
    if ($DriverPath -ne "" -and (Test-Path $DriverPath)) {
        Write-Log -Message "Injecting drivers from $DriverPath"
        Add-WindowsDriver -Path $peMount -Driver $DriverPath -Recurse -ForceUnsigned
    }
    else {
        Write-Log -Message "No drivers found in .\$platform\Drivers" -LogLevel 2
    }

    # Create the _2P directory structure
    Write-log -Message "Creating _2P directory structure." -LogLevel 1
    New-Item -Path "$peMount\_2P\Client\Certs" -ItemType Directory -Force | Out-Null

    # Add the 2Pint root cert if it exists in the root cert store
    Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Issuer -like "CN=2PintSoftware.com,*" } | ForEach-Object {
        Write-Log -Message "Exporting 2Pint trusted root cert $($_.Issuer) with thumbprint $($_.Thumbprint) for inclusion in the boot image" -LogLevel 1
        $_ | Export-Certificate -FilePath "$peMount\_2P\Client\Certs\$($_.Thumbprint).crt"
    }

    # Export any 2Pint-generated certs (disabled for now)
    # New-Item -Path "$peMount\_2P\Client\Certs\My" -ItemType Directory | Out-Null
    # Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Issuer -like "CN=2PintSoftware.com,*" } | ForEach-Object {
    #    Write-Log -Message "Exporting 2Pint-generated cert $($_.Issuer) with thumbprint $($_.Thumbprint) for inclusion in the boot image" -LogLevel 1
    #    $_ | Export-PfxCertificate -FilePath "$peMount\_2P\Client\Certs\My\$($_.Thumbprint).pfx" -Password (ConvertTo-SecureString "2PintSoftware" -AsPlainText -Force)
    # }

    # If a path was passed in, copy the certs from there
    if ($CertPath -ne "" -and (Test-Path $CertPath)) {
        Write-Log -Message "Adding certs from $CertPath into boot image" -LogLevel 1
        Copy-File "$CertPath\*" "$peMount\_2P\Client\Certs" -Recurse -Force
    }

    # Copy self-signed cert if it exists
    if (Test-Path "$($env:ProgramData)\2Pint Software\CertificateStorage\*.crt") {
        Write-Log -Message "Adding certs from $($env:ProgramData)\2Pint Software\CertificateStorage into boot image" -LogLevel 1
        Copy-File "$($env:ProgramData)\2Pint Software\CertificateStorage\*.crt" "$peMount\_2P\Client\Certs" -Force
    }

    # Log the total number of certs injected
    $certCount = @(Get-ChildItem "$peMount\_2P\Client\Certs" -File -Recurse).Length
    Write-Log -Message "Count of certs: $certCount"

    # Remove the old background and copy in the new one
    if (Test-Path "$peMount\Windows\System32\winpe.jpg") {
        Write-Log -Message "Replacing background image."
        takeown /f "$peMount\Windows\system32\winpe.jpg" | Write-Verbose
        icacls "$peMount\Windows\system32\winpe.jpg" /grant *S-1-1-0:f | Write-Verbose
        Remove-Item "$peMount\Windows\system32\winpe.jpg"
    }
    Copy-File -Path "winpe.jpg" -Destination "$peMount\Windows\system32\winpe.jpg" -Force

    # Add extra files
    if ($ExtraFilesPath -ne "" -and (Test-Path $ExtraFilesPath)) {
        Write-Log -Message "Adding files from $ExtraFilesPath into boot image" -LogLevel 1
        Copy-File "$ExtraFilesPath\*" "$peMount\" -Recurse -Force
    }

    # ********
    # Other random stuff
    # ********

    # Registry tweaks
    Write-Log -Message "Mounting registry hives."
    reg.exe load HKLM\PESystem "$peMount\Windows\system32\config\SYSTEM" | Write-Verbose
    Write-Log -Message "Making registry edits."

    # Networking adjustments
    Set-ItemProperty -Path "HKLM:\PESystem\ControlSet001\Services\Tcpip\Parameters" -Name "TcpTimedWaitDelay" -Value 30
    Set-ItemProperty -Path "HKLM:\PESystem\ControlSet001\Services\Tcpip\Parameters" -Name "MaxUserPort" -Value 65534
    Set-ItemProperty -Path "HKLM:\PESystem\ControlSet001\Services\Tcpip\Parameters" -Name "TcpNumConnections" -Value 16777214
    Set-ItemProperty -Path "HKLM:\PESystem\ControlSet001\Services\Tcpip\Parameters" -Name "TcpMaxDataRetransmissions" -Value 5

    # Unmount the registry
    [GC]::Collect()
    Write-Log -Message "Unmounting registry hives."
    reg.exe unload HKLM\PESystem | Write-Verbose

    # ********
    # DeployR files
    # ********

    # Add the needed files
    Write-Log -Message "Adding DeployR files"

    Copy-File "$DeployRClientPath\*" "$peMount\_2P\Client\" -Recurse -Force
    if ($cmTrace -ne "") {
        Copy-File $cmTrace "$peMount\Windows\System32" -Force
        Copy-File $cmTrace "$peMount\_2P\Client" -Force
    }
    Copy-File "C:\Windows\system32\certutil.exe" "$peMount\_2P\Client" -Force

    # Add startup files
    Copy-File -Path "winpeshl.ini" -Destination "$peMount\windows\system32" -Force
    Copy-File -Path "Unattend_PE_$platform.xml" -Destination "$peMount\unattend.xml" -Force

    # Always copy Bootstrap.json in case the version in the client content item isn't up to date (requires cycling DeployR service)
    Copy-File -Path "$InstallDir\Client\Bootstrap.json" "$peMount\_2P\Client\" -Force

    # ********
    # Cleanup
    # ********

    # Unmount and commit
    Write-Log -Message "Unmounting Windows PE WIM image"
    Dismount-WindowsImage -Path $peMount -Save | Write-Verbose

    # Export the image to reduce its size
    if (Test-Path $peExported) {
        Remove-Item $peExported -Force  
    }
    Write-Log -Message "Exporting Windows PE WIM image to $peExported"
    Export-WindowsImage -SourceImagePath $peNew -DestinationImagePath $peExported -SourceIndex 1 | Out-Null

    # Try to copy the boot image files to 2PXE
    $remoteInstallPath = Get-DeployRSetting "RemoteInstall"
    if (Test-Path $remoteInstallPath) {
        # Make sure the folders exist
        if (-not (Test-Path "$remoteInstallPath\Sources\DeployR_$shortPlatform")) {
            New-Item -ItemType Directory -Path "$remoteInstallPath\Sources\DeployR_$shortPlatform" | Out-Null
        }

        # Copy the boot.sdi file if it isn't already there
        if (-not (Test-Path "$remoteInstallPath\Sources\DeployR_$shortPlatform\boot.sdi")) {
            Write-Log "Copying boot.sdi to $remoteInstallPath\Sources\DeployR_$shortPlatform"
            Copy-File -Path "$peRoot\$platform\Media\Boot\boot.sdi" -Destination "$remoteInstallPath\Sources\DeployR_$shortPlatform\boot.sdi" -Force
        }

        # Copy the exported boot image to that location
        Write-Log "Copying updated boot image to 2PXE at $remoteInstallPath\Sources\DeployR_$shortPlatform"
        Copy-File -Path $peExported -Destination "$remoteInstallPath\Sources\DeployR_$shortPlatform" -Force
    }

    # Clean up old .genci files
    if (Test-Path "$peExported.genci") {
        Remove-Item "$peExported.genci" -Force
    }

    # Clean up files and folders
    if (Test-Path "$TempDir\mount_$platform") {
        Remove-Item -Path "$TempDir\mount_$platform" -Recurse -Force
    }    
    if (Test-Path "$TempDir\Media") {
        Remove-Item -Path "$TempDir\Media" -Recurse -Force
    }
    if (Test-Path "$TempDir\winpe_$platform.wim") {
        Remove-Item -Path "$TempDir\winpe_$platform.wim" -Force
    }
    if (Test-Path $ScratchDir) {
        Remove-Item -Path $ScratchDir -Recurse -Force
    }

    # Report completion
    Write-Log -Message "Windows PE generated: $peExported"

    # ********
    # Generate ISO
    # ********

    if ($GenerateISO) {

        $isoNew = "$Destination\DeployR_$shortPlatform.iso"

        # Create a temporary folder
        $isoTemp = "$TempDir\Media"
        if (Test-Path $isoTemp) {
            Remove-Item $isoTemp -Recurse -Force
        }
        New-Item -Path $isoTemp -ItemType Directory | Out-Null

        # Copy the boot files to the media
        Write-Log -Message "Copying boot files"
        Copy-File -Path "$peRoot\$platform\Media\*" -Destination "$($isoTemp)\" -Recurse -Force

        # Copy the PE WIM to the \Sources folder
        Write-Log -Message "Copying Windows PE boot image"
        New-Item -Path "$($isoTemp)\Sources" -ItemType Directory | Out-Null
        Copy-File -Path $peExported -Destination "$($isoTemp)\Sources\boot.wim" -Force

        # Turn off driver integrity checks
        #& bcdedit.exe /store "$isoTemp\EFI\Microsoft\Boot\BCD" /set "{default}" nointegritychecks on
        #& bcdedit.exe /store "$isoTemp\EFI\Microsoft\Boot\BCD" /set "{default}" testsigning on
        #& bcdedit.exe /store "$isoTemp\Boot\BCD" /set "{default}" nointegritychecks on
        #& bcdedit.exe /store "$isoTemp\Boot\BCD" /set "{default}" testsigning on

        # Capture the ISO
        # We need some files that match the boot image architecture
        $oscdimgDir = "$adkRoot\Deployment Tools\$platform\Oscdimg"
        # But OSCDIMG.EXE itself needs to match this OS'es architecture
        $oscdimg = "$adkRoot\Deployment Tools\$($env:PROCESSOR_ARCHITECTURE)\Oscdimg\OSCDIMG.EXE"
        if ($platform -ieq "arm64") {
            # No BIOS support, so only add the UEFI boot sector
            $proc = Start-Process -WorkingDirectory $oscdimgDir -FilePath $oscdimg -ArgumentList "-m -o -u2 -udfver102 -bootdata:1#pEF,e,bEfisys.bin `"$isoTemp`" `"$isoNew`"" -NoNewWindow -PassThru -Wait
        }
        else {
            # Use dual boot sectors
            $proc = Start-Process -WorkingDirectory $oscdimgDir -FilePath $oscdimg -ArgumentList "-m -o -u2 -udfver102 -bootdata:2#p0,e,betfsboot.com#pEF,e,bEfisys.bin `"$isoTemp`" `"$isoNew`"" -NoNewWindow -PassThru -Wait
        }
        if ($proc.ExitCode -ne 0) {
            throw "Failed to generate ISO: $($proc.ExitCode)"
        }
        Write-Log -Message "ISO generated: $isoNew"

        $isoNew = "$Destination\DeployR_$($shortPlatform)_noprompt.iso"
        if ($platform -ieq "arm64") {
            $proc = Start-Process -WorkingDirectory $oscdimgDir -FilePath $oscdimg -ArgumentList "-m -o -u2 -udfver102 -bootdata:1#pEF,e,bEfisys_noprompt.bin `"$isoTemp`" `"$isoNew`"" -NoNewWindow -PassThru -Wait
        }
        else {
            $proc = Start-Process -WorkingDirectory $oscdimgDir -FilePath $oscdimg -ArgumentList "-m -o -u2 -udfver102 -bootdata:2#p0,e,betfsboot.com#pEF,e,bEfisys_noprompt.bin `"$isoTemp`" `"$isoNew`"" -NoNewWindow -PassThru -Wait
        }
        if ($proc.ExitCode -ne 0) {
            throw "Failed to generate ISO: $($proc.ExitCode)"
        }
        Write-Log -Message "ISO generated: $isoNew"

    }
    
}

# SIG # Begin signature block
# MIIvCwYJKoZIhvcNAQcCoIIu/DCCLvgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC0ebkE58YuwOpJ
# PoFnlUFkxQJRhKmKe2a3esBqJ8sjhaCCE5owggWQMIIDeKADAgECAhAFmxtXno4h
# MuI5B72nd3VcMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0xMzA4MDExMjAwMDBaFw0z
# ODAxMTUxMjAwMDBaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0
# IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# AL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/z
# G6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZ
# anMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7s
# Wxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL
# 2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfb
# BHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3
# JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3c
# AORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqx
# YxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0
# viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aL
# T8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjQjBAMA8GA1Ud
# EwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgGGMB0GA1UdDgQWBBTs1+OC0nFdZEzf
# Lmc/57qYrhwPTzANBgkqhkiG9w0BAQwFAAOCAgEAu2HZfalsvhfEkRvDoaIAjeNk
# aA9Wz3eucPn9mkqZucl4XAwMX+TmFClWCzZJXURj4K2clhhmGyMNPXnpbWvWVPjS
# PMFDQK4dUPVS/JA7u5iZaWvHwaeoaKQn3J35J64whbn2Z006Po9ZOSJTROvIXQPK
# 7VB6fWIhCoDIc2bRoAVgX+iltKevqPdtNZx8WorWojiZ83iL9E3SIAveBO6Mm0eB
# cg3AFDLvMFkuruBx8lbkapdvklBtlo1oepqyNhR6BvIkuQkRUNcIsbiJeoQjYUIp
# 5aPNoiBB19GcZNnqJqGLFNdMGbJQQXE9P01wI4YMStyB0swylIQNCAmXHE/A7msg
# dDDS4Dk0EIUhFQEI6FUy3nFJ2SgXUE3mvk3RdazQyvtBuEOlqtPDBURPLDab4vri
# RbgjU2wGb2dVf0a1TD9uKFp5JtKkqGKX0h7i7UqLvBv9R0oN32dmfrJbQdA75PQ7
# 9ARj6e/CVABRoIoqyc54zNXqhwQYs86vSYiv85KZtrPmYQ/ShQDnUBrkG5WdGaG5
# nLGbsQAe79APT0JsyQq87kP6OnGlyE0mpTX9iV28hWIdMtKgK1TtmlfB2/oQzxm3
# i0objwG2J5VT6LaJbVu8aNQj6ItRolb58KaAoNYes7wPD1N1KarqE3fk3oyBIa0H
# EEcRrYc9B9F1vM/zZn4wggawMIIEmKADAgECAhAIrUCyYNKcTJ9ezam9k67ZMA0G
# CSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0
# IFRydXN0ZWQgUm9vdCBHNDAeFw0yMTA0MjkwMDAwMDBaFw0zNjA0MjgyMzU5NTla
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEz
# ODQgMjAyMSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDVtC9C
# 0CiteLdd1TlZG7GIQvUzjOs9gZdwxbvEhSYwn6SOaNhc9es0JAfhS0/TeEP0F9ce
# 2vnS1WcaUk8OoVf8iJnBkcyBAz5NcCRks43iCH00fUyAVxJrQ5qZ8sU7H/Lvy0da
# E6ZMswEgJfMQ04uy+wjwiuCdCcBlp/qYgEk1hz1RGeiQIXhFLqGfLOEYwhrMxe6T
# SXBCMo/7xuoc82VokaJNTIIRSFJo3hC9FFdd6BgTZcV/sk+FLEikVoQ11vkunKoA
# FdE3/hoGlMJ8yOobMubKwvSnowMOdKWvObarYBLj6Na59zHh3K3kGKDYwSNHR7Oh
# D26jq22YBoMbt2pnLdK9RBqSEIGPsDsJ18ebMlrC/2pgVItJwZPt4bRc4G/rJvmM
# 1bL5OBDm6s6R9b7T+2+TYTRcvJNFKIM2KmYoX7BzzosmJQayg9Rc9hUZTO1i4F4z
# 8ujo7AqnsAMrkbI2eb73rQgedaZlzLvjSFDzd5Ea/ttQokbIYViY9XwCFjyDKK05
# huzUtw1T0PhH5nUwjewwk3YUpltLXXRhTT8SkXbev1jLchApQfDVxW0mdmgRQRNY
# mtwmKwH0iU1Z23jPgUo+QEdfyYFQc4UQIyFZYIpkVMHMIRroOBl8ZhzNeDhFMJlP
# /2NPTLuqDQhTQXxYPUez+rbsjDIJAsxsPAxWEQIDAQABo4IBWTCCAVUwEgYDVR0T
# AQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUaDfg67Y7+F8Rhvv+YXsIiGX0TkIwHwYD
# VR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNV
# HR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkUm9vdEc0LmNybDAcBgNVHSAEFTATMAcGBWeBDAEDMAgGBmeBDAEEATAN
# BgkqhkiG9w0BAQwFAAOCAgEAOiNEPY0Idu6PvDqZ01bgAhql+Eg08yy25nRm95Ry
# sQDKr2wwJxMSnpBEn0v9nqN8JtU3vDpdSG2V1T9J9Ce7FoFFUP2cvbaF4HZ+N3HL
# IvdaqpDP9ZNq4+sg0dVQeYiaiorBtr2hSBh+3NiAGhEZGM1hmYFW9snjdufE5Btf
# Q/g+lP92OT2e1JnPSt0o618moZVYSNUa/tcnP/2Q0XaG3RywYFzzDaju4ImhvTnh
# OE7abrs2nfvlIVNaw8rpavGiPttDuDPITzgUkpn13c5UbdldAhQfQDN8A+KVssIh
# dXNSy0bYxDQcoqVLjc1vdjcshT8azibpGL6QB7BDf5WIIIJw8MzK7/0pNVwfiThV
# 9zeKiwmhywvpMRr/LhlcOXHhvpynCgbWJme3kuZOX956rEnPLqR0kq3bPKSchh/j
# wVYbKyP/j7XqiHtwa+aguv06P0WmxOgWkVKLQcBIhEuWTatEQOON8BUozu3xGFYH
# Ki8QxAwIZDwzj64ojDzLj4gLDb879M4ee47vtevLt/B3E+bnKD+sEq6lLyJsQfmC
# XBVmzGwOysWGw/YmMwwHS6DTBwJqakAwSEs0qFEgu60bhQjiWQ1tygVQK+pKHJ6l
# /aCnHwZ05/LWUpD9r4VIIflXO7ScA+2GRfS0YW6/aOImYIbqyK+p/pQd52MbOoZW
# eE4wggdOMIIFNqADAgECAhAN71g6LHT9/A9aiuXA2FCaMA0GCSqGSIb3DQEBCwUA
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEz
# ODQgMjAyMSBDQTEwHhcNMjUwMzEzMDAwMDAwWhcNMjgwMzE0MjM1OTU5WjBWMQsw
# CQYDVQQGEwJTRTEPMA0GA1UEBwwGSG92w6VzMRowGAYDVQQKExEyUGludCBTb2Z0
# d2FyZSBBQjEaMBgGA1UEAxMRMlBpbnQgU29mdHdhcmUgQUIwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQC10zuqpoxAwME7Dyqaqzl38pplYh/iqqodmehw
# cL61MlFBNzfz2AL3UAOuwqkqjJhlos48CrHZ5R9yJbmLpghkssYof2ot3z2hnHTB
# kMyskNP4ayjvhFI2a9MbueEi5zI0wXFd2Sn0aEmfI0J2RnWkYwvdbd8lYwO/0gws
# TOYyblYRoKUwJ2mBrKfSe/dxsWUc1mzVjrHOUkhkHsI2ICkBBfOrP8G3gPTi8vAE
# 89q4GpNekAcXeWXffN4iio1oxjGXF9yAa+pugiLqPQDd1AU1twLWFqWg9peXKaa/
# 7IMUZUfyzEPXl7GQAyT7SSgzf6OIl7/LKnecg6uM8dAfDHKlLYIvoyy+Alh00Zc5
# 7uuXW2ZBdpXsU5eCpW/d0DbnnQGp23dvWS+Eoq5HwdNVcfpMoaAaDfgnRLtyrHIS
# jaicOy2lpydH/mS348nEvplTmgP4CAOoPER31icv5jUtxbX4jyAQuddv4uwLKuDg
# N6UNSlRTO1E8bsNG6CrisB3xtEa97A0bVQjrPdZxxOdr3N49S96CI1rnjOfOjscI
# eATLtYuf7/o/2U5aXPwfvCdY/dNJ9zsvmZ48P+tdVAAxlupDCIKmX98obZl8NJsG
# 1U0WFoENvKyZ4gTx3O4DImFdCgpRhZpDvQkR1xxfBbgxcW7E3fItPUKv5vRbE8ld
# VMMnDQIDAQABo4ICAzCCAf8wHwYDVR0jBBgwFoAUaDfg67Y7+F8Rhvv+YXsIiGX0
# TkIwHQYDVR0OBBYEFLqTMurQaa9F0Tyodk6Rtg7KS0hFMD4GA1UdIAQ3MDUwMwYG
# Z4EMAQQBMCkwJwYIKwYBBQUHAgEWG2h0dHA6Ly93d3cuZGlnaWNlcnQuY29tL0NQ
# UzAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwgbUGA1UdHwSB
# rTCBqjBToFGgT4ZNaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1
# c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAyMUNBMS5jcmwwU6BRoE+G
# TWh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNENvZGVT
# aWduaW5nUlNBNDA5NlNIQTM4NDIwMjFDQTEuY3JsMIGUBggrBgEFBQcBAQSBhzCB
# hDAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMFwGCCsGAQUF
# BzAChlBodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVk
# RzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNydDAJBgNVHRMEAjAA
# MA0GCSqGSIb3DQEBCwUAA4ICAQAvVkmDb8Wg/Z/s1TfdlF0GEwuJ1iA62uTvnLbc
# L8RgLCYKue+BrJFIaJXVT3EoUNh9TB2uAaKxqU0JsL1p1JfKM6f7n1Zf/f7GiLkf
# 0LJ/z0EJAVk1ZvDb1TLOyZQb6lqPCbE7ZTijVHNZ6WmnbB/vAECrRzx2ojag9RjQ
# gsQ+lY93xOLjNU85eshmu/cI8kUsfDzonIp9sXjbCJLnVljD0X+Oo8utY3z0Kjgb
# oGAIXu3wX8/UEUkDLFgbrM6pdeXeB+B8Dc9eKYaekVvI/PeKqcUGQW9rTDnEowN6
# E6Pmld1zZ5U3Ous31/27NGM+mdPESxL4/P32w7cPfQGKtcDn1/e3ThvBbi2YQSWp
# xeS/CHde1j0JkhpXPRALphKsPG5+XZixUqlTkR4ruSPsS/CHFMKycZr1BUxjzu5z
# OMZEo7cUIY7EX9YPMian4qTkaKp6wLOh/jq3jNdmfrHGkT14XTaNVKqgqirP6+5g
# 2rCrEpYO0bW2bZ/rKegiE4D0uRYfg700BIg97LVkEvqUtZskaCEV31FQGhh4tBg5
# ATt1vSdwz5y8kwJVM3ImVeagBoIy4buE+j4gUBkHUsfTJ9aVVHUbqexr7WrhFRB4
# P0P+qd5ZsniXjqpZR17ROIwd1iSy68EPG5YQ4SuExebmUS2BwWqW9vFuRWC+6Bd6
# Pl9vvDGCGscwghrDAgEBMH0waTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lD
# ZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IENvZGUgU2ln
# bmluZyBSU0E0MDk2IFNIQTM4NCAyMDIxIENBMQIQDe9YOix0/fwPWorlwNhQmjAN
# BglghkgBZQMEAgEFAKCBojAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgDX/ifz3E
# tM1MkDwV0I9SLrzGK54OxpFh/eyMaKIsUnswNgYKKwYBBAGCNwIBDDEoMCagAoAA
# oSCAHmh0dHBzOi8vd3d3LjJwaW50c29mdHdhcmUuY29tIDANBgkqhkiG9w0BAQEF
# AASCAgCRw6XA2AgEB9y9lhWoOrT/CNbE5yy5pga/Mj+zs0YfQuS8FFgzYGE722Jr
# va18KUB9AtgY3rldB377MUrQTozc57NkZNuQnS/SER1gny4hk/Qe+kLf/MTEC8Fu
# jjtStU46sso5DqWXoPqTv9dDwBkTEzzhmG1PctCPZbDEsQoEM+mNwoMpb9bMNWiW
# FiV0aAuoyJllS43OC8FoQOgxM7P5EzbinGRxmcMw645jwyuAbmjXboZO54HZJhUH
# 5JAcl5bKXPy+aQBv143/y5RSt4Tq11yqnr57rLo1XDGZvNU5zd8r4YFPhkjYBDXj
# MXVARWswh9b6VSD/QsZBsmfGEAGANrnTO0gqHXEj26CgfllZU3iQE+tCRAvdD6h5
# LUyqkh1EXm3duhOzw/8on0V56Xo7nZHHUj4qEGSC/f6ua3UWMk+ghKeE+mMrXJlL
# imUG4TXWfvrl7Fw7QLXab+4Wb5fRJEWkxEUCdLsVKBj13jVav/WSbdwCn9+70Rbp
# uzAJPsbr/cCW5/StGOHgy6LETFW8lpagDjTF4Qch2TyMQT5G7ly6vpHmhjgAnoLK
# LbtEiTQUQAXC3y91iUARH+GYfiBbVKaiSCZ5YgyLFx+mR4J2cY21rAlORzMdLCWz
# QrqYdRQg+qusKWoyOTBQGXdG9mY6zY4KDjAo3o22q+QCZFiPK6GCF3YwghdyBgor
# BgEEAYI3AwMBMYIXYjCCF14GCSqGSIb3DQEHAqCCF08wghdLAgEDMQ8wDQYJYIZI
# AWUDBAIBBQAwdwYLKoZIhvcNAQkQAQSgaARmMGQCAQEGCWCGSAGG/WwHATAxMA0G
# CWCGSAFlAwQCAQUABCD8ySEX+/4wMJ/w9QlVl1ERalaQ7TTiu0k2Ey+/1UVeHgIQ
# IQkqjuTpW9PTNUR8IjqGsBgPMjAyNjAzMDYyMzU4MDBaoIITOjCCBu0wggTVoAMC
# AQICEAqA7xhLjfEFgtHEdqeVdGgwDQYJKoZIhvcNAQELBQAwaTELMAkGA1UEBhMC
# VVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBU
# cnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENBMTAe
# Fw0yNTA2MDQwMDAwMDBaFw0zNjA5MDMyMzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcw
# FQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2
# IFJTQTQwOTYgVGltZXN0YW1wIFJlc3BvbmRlciAyMDI1IDEwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDQRqwtEsae0OquYFazK1e6b1H/hnAKAd/KN8wZ
# QjBjMqiZ3xTWcfsLwOvRxUwXcGx8AUjni6bz52fGTfr6PHRNv6T7zsf1Y/E3IU8k
# gNkeECqVQ+3bzWYesFtkepErvUSbf+EIYLkrLKd6qJnuzK8Vcn0DvbDMemQFoxQ2
# Dsw4vEjoT1FpS54dNApZfKY61HAldytxNM89PZXUP/5wWWURK+IfxiOg8W9lKMqz
# dIo7VA1R0V3Zp3DjjANwqAf4lEkTlCDQ0/fKJLKLkzGBTpx6EYevvOi7XOc4zyh1
# uSqgr6UnbksIcFJqLbkIXIPbcNmA98Oskkkrvt6lPAw/p4oDSRZreiwB7x9ykrjS
# 6GS3NR39iTTFS+ENTqW8m6THuOmHHjQNC3zbJ6nJ6SXiLSvw4Smz8U07hqF+8CTX
# aETkVWz0dVVZw7knh1WZXOLHgDvundrAtuvz0D3T+dYaNcwafsVCGZKUhQPL1naF
# KBy1p6llN3QgshRta6Eq4B40h5avMcpi54wm0i2ePZD5pPIssoszQyF4//3DoK2O
# 65Uck5Wggn8O2klETsJ7u8xEehGifgJYi+6I03UuT1j7FnrqVrOzaQoVJOeeStPe
# ldYRNMmSF3voIgMFtNGh86w3ISHNm0IaadCKCkUe2LnwJKa8TIlwCUNVwppwn4D3
# /Pt5pwIDAQABo4IBlTCCAZEwDAYDVR0TAQH/BAIwADAdBgNVHQ4EFgQU5Dv88jHt
# /f3X85FxYxlQQ89hjOgwHwYDVR0jBBgwFoAU729TSunkBnx6yuKQVvYv1Ensy04w
# DgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMIGVBggrBgEF
# BQcBAQSBiDCBhTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29t
# MF0GCCsGAQUFBzAChlFodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lD
# ZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5nUlNBNDA5NlNIQTI1NjIwMjVDQTEuY3Js
# MCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsF
# AAOCAgEAZSqt8RwnBLmuYEHs0QhEnmNAciH45PYiT9s1i6UKtW+FERp8FgXRGQ/Y
# AavXzWjZhY+hIfP2JkQ38U+wtJPBVBajYfrbIYG+Dui4I4PCvHpQuPqFgqp1PzC/
# ZRX4pvP/ciZmUnthfAEP1HShTrY+2DE5qjzvZs7JIIgt0GCFD9ktx0LxxtRQ7vll
# KluHWiKk6FxRPyUPxAAYH2Vy1lNM4kzekd8oEARzFAWgeW3az2xejEWLNN4eKGxD
# J8WDl/FQUSntbjZ80FU3i54tpx5F/0Kr15zW/mJAxZMVBrTE2oi0fcI8VMbtoRAm
# aaslNXdCG1+lqvP4FbrQ6IwSBXkZagHLhFU9HCrG/syTRLLhAezu/3Lr00GrJzPQ
# FnCEH1Y58678IgmfORBPC1JKkYaEt2OdDh4GmO0/5cHelAK2/gTlQJINqDr6Jfwy
# YHXSd+V08X1JUPvB4ILfJdmL+66Gp3CSBXG6IwXMZUXBhtCyIaehr0XkBoDIGMUG
# 1dUtwq1qmcwbdUfcSYCn+OwncVUXf53VJUNOaMWMts0VlRYxe5nK+At+DI96HAlX
# HAL5SlfYxJ7La54i71McVWRP66bW+yERNpbJCjyCYG2j+bdpxo/1Cy4uPcU3AWVP
# Grbn5PhDBf3Froguzzhk++ami+r3Qrx5bIbY3TVzgiFI7Gq3zWcwgga0MIIEnKAD
# AgECAhANx6xXBf8hmS5AQyIMOkmGMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYT
# AlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2Vy
# dC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yNTA1
# MDcwMDAwMDBaFw0zODAxMTQyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQK
# Ew5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBU
# aW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQC0eDHTCphBcr48RsAcrHXbo0ZodLRRF51NrY0N
# lLWZloMsVO1DahGPNRcybEKq+RuwOnPhof6pvF4uGjwjqNjfEvUi6wuim5bap+0l
# gloM2zX4kftn5B1IpYzTqpyFQ/4Bt0mAxAHeHYNnQxqXmRinvuNgxVBdJkf77S2u
# PoCj7GH8BLuxBG5AvftBdsOECS1UkxBvMgEdgkFiDNYiOTx4OtiFcMSkqTtF2hfQ
# z3zQSku2Ws3IfDReb6e3mmdglTcaarps0wjUjsZvkgFkriK9tUKJm/s80FiocSk1
# VYLZlDwFt+cVFBURJg6zMUjZa/zbCclF83bRVFLeGkuAhHiGPMvSGmhgaTzVyhYn
# 4p0+8y9oHRaQT/aofEnS5xLrfxnGpTXiUOeSLsJygoLPp66bkDX1ZlAeSpQl92QO
# MeRxykvq6gbylsXQskBBBnGy3tW/AMOMCZIVNSaz7BX8VtYGqLt9MmeOreGPRdtB
# x3yGOP+rx3rKWDEJlIqLXvJWnY0v5ydPpOjL6s36czwzsucuoKs7Yk/ehb//Wx+5
# kMqIMRvUBDx6z1ev+7psNOdgJMoiwOrUG2ZdSoQbU2rMkpLiQ6bGRinZbI4OLu9B
# MIFm1UUl9VnePs6BaaeEWvjJSjNm2qA+sdFUeEY0qVjPKOWug/G6X5uAiynM7Bu2
# ayBjUwIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU
# 729TSunkBnx6yuKQVvYv1Ensy04wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6
# mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsG
# AQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29t
# MEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3Js
# My5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAE
# GTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBABfO
# +xaAHP4HPRF2cTC9vgvItTSmf83Qh8WIGjB/T8ObXAZz8OjuhUxjaaFdleMM0lBr
# yPTQM2qEJPe36zwbSI/mS83afsl3YTj+IQhQE7jU/kXjjytJgnn0hvrV6hqWGd3r
# LAUt6vJy9lMDPjTLxLgXf9r5nWMQwr8Myb9rEVKChHyfpzee5kH0F8HABBgr0Udq
# irZ7bowe9Vj2AIMD8liyrukZ2iA/wdG2th9y1IsA0QF8dTXqvcnTmpfeQh35k5zO
# CPmSNq1UH410ANVko43+Cdmu4y81hjajV/gxdEkMx1NKU4uHQcKfZxAvBAKqMVuq
# te69M9J6A47OvgRaPs+2ykgcGV00TYr2Lr3ty9qIijanrUR3anzEwlvzZiiyfTPj
# LbnFRsjsYg39OlV8cipDoq7+qNNjqFzeGxcytL5TTLL4ZaoBdqbhOhZ3ZRDUphPv
# SRmMThi0vw9vODRzW6AxnJll38F0cuJG7uEBYTptMSbhdhGQDpOXgpIUsWTjd6xp
# R6oaQf/DJbg3s6KCLPAlZ66RzIg9sC+NJpud/v4+7RWsWCiKi9EOLLHfMR2ZyJ/+
# xhCx9yHbxtl5TPau1j/1MIDpMPx0LckTetiSuEtQvLsNz3Qbp7wGWqbIiOWCnb5W
# qxL3/BAPvIXKUjPSxyZsq8WhbaM2tszWkPZPubdcMIIFjTCCBHWgAwIBAgIQDpsY
# jvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJVUzEVMBMG
# A1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQw
# IgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAw
# MDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhE
# aWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57
# G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9o
# k3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFh
# mzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463J
# T17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFw
# q1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yh
# Tzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU
# 75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LV
# jHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJ
# bOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+whX8Qg
# UWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IB
# OjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6
# mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/
# BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3Au
# ZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4
# oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJv
# b3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBw
# oL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0
# E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtD
# IeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlU
# sLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAIDyyCwrFig
# DkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwY
# w02fc7cBqZ9Xql4o4rmUMYIDfDCCA3gCAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUG
# A1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQg
# RzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43x
# BYLRxHanlXRoMA0GCWCGSAFlAwQCAQUAoIHRMBoGCSqGSIb3DQEJAzENBgsqhkiG
# 9w0BCRABBDAcBgkqhkiG9w0BCQUxDxcNMjYwMzA2MjM1ODAwWjArBgsqhkiG9w0B
# CRACDDEcMBowGDAWBBTdYjCshgotMGvaOLFoeVIwB/tBfjAvBgkqhkiG9w0BCQQx
# IgQgyIwfTcn3nu0nZyfxW4Cdef5vmZ9BcWMqRRb2ugFbCqcwNwYLKoZIhvcNAQkQ
# Ai8xKDAmMCQwIgQgSqA/oizXXITFXJOPgo5na5yuyrM/420mmqM08UYRCjMwDQYJ
# KoZIhvcNAQEBBQAEggIAp2L89OkiCrFJTguwIVLxnsJuaUEYb1pHvez7cvUbtCtB
# iDmkPPYqDxXGUGbnta7U8hjS9HjoAnCqiISNUNgzg+JR0KWYhodUBRv79sX+rd7I
# tjdSVDZnIS7ueuxqkMQJM9uY5OHB+Ths8rkpWO4K432wpCj2D1cCJRSnXAqqYMkB
# Hpojj/rmUkgn465c5l/p6qDt+D6Y0uZOmTsJEBCSsB7rchKinwnvdjLfF4XEWffT
# JQ7uONazBuFSyJfMvZZQ2fDKS+jpT1XAnZZj39+KMDd7sIPdUTHURy8rKUS/OP17
# kpmW+tmnNJ8nW5O1wacIAynZGRfq55XbDDlZN2/lOFlexIFCpqwuw2UYU0DWIHOC
# LOqhxN62fl3kLrmwvrMUHuYhim5GV2hRuVsgUf9AIxSHs55OknGpHQm0OxHpIHWc
# FroT7qjl9lJXZXkDr7SztEEhGj+RIdxWSAGVXfddc2cwascpv9hAPUS8BaTuU8IP
# eMd0No2MBMC3KD/ImHMqS3SMeEeBC9vcURE+zgQEjMfvJUQ9/TEKgUBP4BrPmE55
# 3BIDSIliMQRxLmZD38M8DLX+eGMHER2DsOG7vF8DyvDrOSrfPpOwN93XBcpRgqKe
# U+G4wc4Z9rMPVIe9e80vnJ0SmJLJj2FGEDSWWdns0Oy0yC92stc2jARhTuBevcY=
# SIG # End signature block
