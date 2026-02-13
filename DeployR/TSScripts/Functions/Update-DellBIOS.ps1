#This Script will Detect and Update BIOS on the Dell Device - FULL OS ONLY - NOT WINPE

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

Write-Host "Checking for Dell BIOS updates..."
$Status = Get-DellBIOSUpdates -Check -Verbose
if ($Status -eq $false){
    Write-Host "Dell BIOS update available. Flashing now..."
    Get-DellBIOSUpdates -Flash
    Write-Host "Dell BIOS update complete, rebooting now..."
    exit 3010
}
else {
    Write-Host "No Dell BIOS updates available."
    
}