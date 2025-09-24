<# 
Import-Module DeployR.Utility

# Get the provided variables
[String]$TargetSystemDrive = ${TSEnv:OSDTARGETSYSTEMDRIVE}
[String]$LogPath = ${TSEnv:_DEPLOYRLOGS}
#>

Function Create-NewHPDriverPackWinPE {
    [CmdletBinding()]
    param(
    [Parameter(Mandatory = $false)]
    [string]$TargetSystemDrive = "S:",
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "S:\_2P\Logs",
    [Parameter(Mandatory = $false)]
    [switch]$ApplyDrivers = $false
    )
    
    
    Write-Host "==================================================================="
    Write-Host "     Starting Process to Build HP Driver Pack while in WinPE"
    Write-Host "==================================================================="
    
    #Find 7za.exe
    if (Test-path -Path "X:\_2P\content\00000000-0000-0000-0000-000000000002\Tools\x64\7za.exe"){
        $SevenZipPath = "X:\_2P\content\00000000-0000-0000-0000-000000000002\Tools\x64\7za.exe"
    }
    else {
        Write-Host "7za.exe not found in expected path. Please ensure it is available in the Tools directory."
        Exit 1
    }
    #Import DeployR.Utility module
    if (-not (Get-Module -Name DeployR.Utility)) {
        Import-Module X:\_2P\Client\PSModules\DeployR.Utility\DeployR.Utility.psd1 -Force -ErrorAction Stop
    }
    
    #Build Download Content Location
    $DownloadContentPath = "$TargetSystemDrive\_2P\content\Drivers"
    if (!(Test-Path -Path $DownloadContentPath)) {
        New-Item -ItemType Directory -Path $DownloadContentPath -Force | Out-Null
    }
    $ExtractedDriverLocation = "$TargetSystemDrive\_2P\content\Drivers\Extracted"
    if (!(Test-Path -Path $ExtractedDriverLocation)) {
        New-Item -ItemType Directory -Path $ExtractedDriverLocation -Force | Out-Null
    }
    
    
    #Region Functions
    function Test-HPIASupport {
        $CabPath = "$env:TEMP\platformList.cab"
        $XMLPath = "$env:TEMP\platformList.xml"
        $PlatformListCabURL = "https://hpia.hpcloud.hp.com/ref/platformList.cab"
        Invoke-WebRequest -Uri $PlatformListCabURL -OutFile $CabPath -UseBasicParsing
        $Expand = expand $CabPath $XMLPath
        [xml]$XML = Get-Content $XMLPath
        $Platforms = $XML.ImagePal.Platform.SystemID
        $MachinePlatform = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BaseBoard).Product
        if ($MachinePlatform -in $Platforms){$HPIASupport = $true}
        else {$HPIASupport = $false}
        return $HPIASupport
    }
    
    function Get-HPOSSupport {
        [CmdletBinding()]
        param(
        [Parameter(Position=0,mandatory=$false)]
        [string]$Platform,
        [switch]$Latest,
        [switch]$MaxOS,
        [switch]$MaxOSVer,
        [switch]$MaxOSNum
        )
        $CabPath = "$env:TEMP\platformList.cab"
        $XMLPath = "$env:TEMP\platformList.xml"
        if ($Platform){$MachinePlatform = $platform}
        else {$MachinePlatform = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BaseBoard).Product}
        $PlatformListCabURL = "https://hpia.hpcloud.hp.com/ref/platformList.cab"
        Invoke-WebRequest -Uri $PlatformListCabURL -OutFile $CabPath -UseBasicParsing
        $Expand = expand $CabPath $XMLPath
        [xml]$XML = Get-Content $XMLPath
        $XMLPlatforms = $XML.ImagePal.Platform
        $OSList = ($XMLPlatforms | Where-Object {$_.SystemID -match $MachinePlatform}).OS | Select-Object -Property OSReleaseIdDisplay, OSBuildId, OSDescription
        
        if ($Latest){
            [String]$MaxOSSupported = ($OSList.OSDescription | Where-Object {$_ -notmatch "LTSB"}| Select-Object -Unique| Measure-Object -Maximum).Maximum
            [String]$MaxOSVerion = (($OSList | Where-Object {$_.OSDescription -eq "$MaxOSSupported"}).OSReleaseIdDisplay | Measure-Object -Maximum).Maximum
            return "$MaxOSSupported $MaxOSVerion"
            break
        }
        if ($MaxOS){
            [String]$MaxOSSupported = ($OSList.OSDescription | Where-Object {$_ -notmatch "LTSB"}| Select-Object -Unique| Measure-Object -Maximum).Maximum
            if ($MaxOSSupported -Match "11"){[String]$MaxOSName = "Win11"}
            else {[String]$MaxOSName = "Win10"}
            return "$MaxOSName"
            break
        }
        if ($MaxOSVer){
            [String]$MaxOSSupported = ($OSList.OSDescription | Where-Object {$_ -notmatch "LTSB"}| Select-Object -Unique| Measure-Object -Maximum).Maximum
            [String]$MaxOSVersion = (($OSList | Where-Object {$_.OSDescription -eq "$MaxOSSupported"}).OSReleaseIdDisplay | Measure-Object -Maximum).Maximum
            return "$MaxOSVersion"
            break
        }
        if ($MaxOSNum){
            [String]$MaxOSSupported = ($OSList.OSDescription | Where-Object {$_ -notmatch "LTSB"}| Select-Object -Unique| Measure-Object -Maximum).Maximum
            if ($MaxOSSupported -Match "11"){[String]$MaxOSNumber = "11.0"}
            else {[String]$MaxOSNumber = "10.0"}
            return "$MaxOSNumber"
            break
        }
        return $OSList
    }
    
    function Get-HPSoftpaqListLatest {
        [CmdletBinding()]
        param(
        [Parameter(Position=0,mandatory=$false)]
        [string]$Platform,
        [switch]$SystemInfo,
        [switch]$MaxOSVer,
        [switch]$MaxOSNum
        )
        if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64"){
            $Arch = '64'
        }
        
        if ($Platform){$MachinePlatform = $platform}
        else {$MachinePlatform = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BaseBoard).Product}
        $OSNum = Get-HPOSSupport -MaxOSNum -Platform $MachinePlatform
        $ReleaseID = Get-HPOSSupport -MaxOSVer -Platform $MachinePlatform
        $BaseURL = ("https://hpia.hpcloud.hp.com/ref/$($MachinePlatform)/$($MachinePlatform)_$($Arch)_$($OSNum).$($ReleaseID).cab").ToLower()
        #https://hpia.hpcloud.hp.com/ref/83b2/83b2_64_11.0.23h2.cab
        $CabPath = "$env:TEMP\HPIA.cab"
        $XMLPath = "$env:TEMP\HPIA.xml"
        Write-Verbose "Invoke-WebRequest -Uri $BaseURL -OutFile $CabPath -UseBasicParsing"
        Invoke-WebRequest -Uri $BaseURL -OutFile $CabPath -UseBasicParsing
        $Expand = expand $CabPath $XMLPath
        [xml]$XML = Get-Content $XMLPath
        $SoftpaqList = $XML.ImagePal.Solutions.UpdateInfo
        if ($SystemInfo){
            $SysInfo = $XML.ImagePal.SystemInfo.System
            return $SysInfo
            break
        }
        return $SoftpaqList
        
    }
    
    function Get-HPSoftPaqItems {
        [CmdletBinding()]
        param(
        [Parameter(Position=0,mandatory=$false)]
        [string] $Platform,
        [Parameter(Position=1,mandatory=$true)]
        [string] $osver,
        [Parameter(Position=2,mandatory=$true)]
        [ValidateSet("10.0","11.0")]
        [string] $os
        )
        
        
        
        if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64"){$Arch = '64'}
        $CabPath = "$env:TEMP\HPIA.cab"
        $XMLPath = "$env:TEMP\HPIA.xml"
        if ($Platform){$MachinePlatform = $platform}
        else {$MachinePlatform = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BaseBoard).Product}
        
        #Test Passed Parameters
        $OSList = Get-HPOSSupport -Platform $MachinePlatform
        if ($OS -eq "11.0"){
            $OK = $OSList | Where-Object {$_.OSDescription -match "Windows 11"}
            if ($null -eq $OK){
                Write-Error "Your option of OS: $OS is not valid, This platform does not support Windows 11"
                break
            }
        }
        if ($OS -eq "10.0"){
            $OK = $OSList | Where-Object {$_.OSDescription -match "Windows 10"}
            if ($null -eq $OK){
                Write-Error "Your option of OS: $OS is not valid, This platform does not support Windows 10"
                break
            }
        }
        $SupportedOSVers = $OSList.OSReleaseIdDisplay
        if ($osver -notin $SupportedOSVers){
            Write-Host -ForegroundColor red "Selected Release $OSVer is not supported by this Platform: $MachinePlatform"
            Write-Error " Use Get-HPOSSupport to find list of options"
            break
        }
        $BaseURL = ("https://hpia.hpcloud.hp.com/ref/$($MachinePlatform)/$($MachinePlatform)_$($Arch)_$($os).$($osver).cab").ToLower()
        Write-Verbose "Invoke-WebRequest -Uri $BaseURL -OutFile $CabPath -UseBasicParsing"
        Invoke-WebRequest -Uri $BaseURL -OutFile $CabPath -UseBasicParsing
        $Expand = expand $CabPath $XMLPath
        [xml]$XML = Get-Content $XMLPath
        $SoftpaqList = $XML.ImagePal.Solutions.UpdateInfo
        
        return $SoftpaqList
        
    }
    
    function Get-HPDriverPackLatest {
        [CmdletBinding()]
        param(
        [Parameter(Position=0,mandatory=$false)]
        [string]$Platform,
        [switch]$URL,
        [switch]$download
        )
        if ($Platform){$MachinePlatform = $platform}
        else {$MachinePlatform = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BaseBoard).Product}
        $OSList = Get-HPOSSupport -Platform $MachinePlatform
        if (($OSList.OSDescription) -contains "Microsoft Windows 11"){
            $OS = "11.0"
            #Get the supported Builds for Windows 11 so we can loop through them
            $SupportedWinXXBuilds = ($OSList| Where-Object {$_.OSDescription -match "11"}).OSReleaseIdDisplay | Sort-Object -Descending
            if ($SupportedWinXXBuilds){
                write-Verbose "Checking for Win $OS Driver Pack"
                [int]$Loop_Index = 0
                do {
                    Write-Verbose "Checking for Driver Pack for $OS $($SupportedWinXXBuilds[$loop_index])"
                    try {
                        $DriverPack = Get-HPSoftPaqItems -osver $($SupportedWinXXBuilds[$loop_index]) -os $OS -Platform $MachinePlatform | Where-Object {$_.Category -match "Driver Pack"}
                        #$DriverPack = Get-SoftpaqList -Category Driverpack -OsVer $($SupportedWinXXBuilds[$loop_index]) -Os "Win11" -ErrorAction SilentlyContinue
                    
                    }
                    catch {
                        <#Do this if a terminating exception happens#>
                    }
                    if (!($DriverPack)){$Loop_Index++;}
                    if ($DriverPack){
                        Write-Verbose "Windows 11 $($SupportedWinXXBuilds[$loop_index]) Driver Pack Found"
                    }
                }
                while ($null -eq $DriverPack -and $loop_index -lt $SupportedWinXXBuilds.Count)
            }
        }
        
        if (!($DriverPack)){ #If no Win11 Driver Pack found, check for Win10 Driver Pack
            if (($OSList.OSDescription) -contains "Microsoft Windows 10"){
                $OS = "10.0"
                #Get the supported Builds for Windows 10 so we can loop through them
                $SupportedWinXXBuilds = ($OSList| Where-Object {$_.OSDescription -match "10"}).OSReleaseIdDisplay | Sort-Object -Descending
                if ($SupportedWinXXBuilds){
                    write-Verbose "Checking for Win $OS Driver Pack"
                    [int]$Loop_Index = 0
                    do {
                        Write-Verbose "Checking for Driver Pack for $OS $($SupportedWinXXBuilds[$loop_index])"
                        try {
                            $DriverPack = Get-HPSoftPaqItems -osver $($SupportedWinXXBuilds[$loop_index]) -os $OS -Platform $MachinePlatform | Where-Object {$_.Category -match "Driver Pack"}
                            #$DriverPack = Get-SoftpaqList -Category Driverpack -OsVer $($SupportedWinXXBuilds[$loop_index]) -Os "Win10" -ErrorAction SilentlyContinue
                        }
                        catch {
                            <#Do this if a terminating exception happens#>
                        }
                        if (!($DriverPack)){$Loop_Index++;}
                        if ($DriverPack){
                            Write-Verbose "Windows 10 $($SupportedWinXXBuilds[$loop_index]) Driver Pack Found"
                        }
                    }
                    while ($null-eq $DriverPack  -and $loop_index -lt $SupportedWinXXBuilds.Count)
                }
            }
        }
        if ($DriverPack){
            Write-Verbose "Driver Pack Found: $($DriverPack.Name) for Platform: $Platform"
            if($PSBoundParameters.ContainsKey('Download')){
                Save-WebFile -SourceUrl "https://$($DriverPack.URL)" -DestinationName "$($DriverPack.id).exe" -DestinationDirectory "C:\Drivers"
            }
            else{
                if($PSBoundParameters.ContainsKey('URL')){
                    return "https://$($DriverPack.URL)"
                }
                else {
                    return $DriverPack
                }
            }
        }
        else {
            Write-Verbose "No Driver Pack Found for Platform: $Platform"
            return $false
        }
    }
    #EndRegion Functions

    if (Test-HPIASupport){
        Write-Host "This Platform is supported by HPIA"
    }
    else {
        Write-Host "This Platform is not supported by HPIA"
        exit 0
    }
    $Drivers = Get-HPSoftpaqListLatest | Where-Object {$_.Category -match "Driver -"} 
    if ($Drivers.Count -eq 0){
        Write-Host "No Drivers found for this platform, exiting."
        exit 0
    }
    else {
        Write-Host "Found $($Drivers.Count) Drivers for this platform."
    }
    Foreach ($Driver in $Drivers){
        Write-Host "Driver: $($Driver.Name) - $($Driver.Description)" -ForegroundColor Magenta
        if ($null -ne $Driver.URL){
            Write-Host "Downloading Driver from: $($Driver.URL)" -ForegroundColor Cyan
            $DownloadedFile = "$TargetSystemDrive\_2P\content\Drivers\$($Driver.id).exe"
            write-host "Downloading to: $DownloadedFile" -ForegroundColor Green
            $DestinationPath = "$ExtractedDriverLocation\$($Driver.id)"
            #Start-BitsTransfer -Source "https://$($Driver.URL)" -Destination "$TargetSystemDrive\_2P\content\Drivers\$($Driver.id).exe" -DisplayName $Driver.Name -Description $Driver.Description -ErrorAction SilentlyContinue
            try {
                Request-DeployRCustomContent -ContentName $($Driver.Id) -ContentFriendlyName $($Driver.Name) -URL "https://$($Driver.URL)" -DestinationPath $DownloadedFile -ErrorAction SilentlyContinue
            } catch {
                Write-Host "Failed to download driver: $($Driver.Name)" -ForegroundColor red
                Write-Host "Going to try again with Invoke-WebRequest" -ForegroundColor Yellow
                Invoke-WebRequest -Uri $Driver.URL -OutFile $DownloadedFile -UseBasicParsing
            }
            if (Test-Path -Path $DownloadedFile) {
                Write-Host "Driver downloaded successfully: $($Driver.Name)"
                write-Host "Expanding Driver Pack to $ExtractedDriverLocation"
                Start-Process -FilePath $SevenZipPath -ArgumentList "x $DownloadedFile -o$DestinationPath -y" -Wait -NoNewWindow -PassThru
            }
            else {
                Write-Host "Failed to download driver: $($Driver.Name)" -ForegroundColor Red
            }
        }
        else {
            Write-Host "No URL found for this driver, skipping download."
        }
    }
    #Apply Drivers in ExtractedDriverLocation to Offline OS
    if ($ApplyDrivers -eq $false){
        Write-Host "Skipping Driver Application to Offline OS"
        return
    }
    else {
        Write-Host -ForegroundColor Cyan "Applying Drivers to Offline OS at $TargetSystemDrive from $ExtractedDriverLocation"
        Add-WindowsDriver -Path "$($TargetSystemDrive)\" -Driver "$ExtractedDriverLocation" -Recurse -ErrorAction SilentlyContinue -LogPath $LogPath\AddDrivers.log
    }
}

