<#

This Script creates several functions, the 3 Main functions are
Import-PanasonicDriverPacks (I still plan to modify this more in the future)
Find-DellDriverPacks
Find-HPDriverPacks

Using those, it will automatically create the DeployR Content Items and load up the Driver Packs.  You might want to look over some of the paths used in the script and update if needed.

Examples 

## Dell ##
Find-DellDriverPacks will provide a list of supported devices
Find-DellDriverPacks -ImportBySKU (or -ImportByModel) will import all found driver packs into DeployR Content Items
Find-DellDriverPacks -ImportBySKU will import the Device and leverage the SKU as the identifier (Great for HP, or Dell when a SKU matches several Model Names)
Find-DellDriverPacks -ImportByName will import the Device and leverage the Model Name as the identifier (Great for Dell when a Model Name matches several SKUs)
Find-DellDriverPacks -ImportBySKU (or -ImportByName) -SourceFolder "D:\MySourceFolder" to specify a different source folder for downloaded/extracted driver packs

## HP ##
Find-HPDriverPacks will provide a list of supported HP devices
Find-HPDriverPacks  -SourceFolder "D:\MySourceFolder" to specify a different source folder for downloaded/extracted driver packs

You'll want to update this variable: $ArchiveSourceFolder to a place you want the driver packs to be downloaded and extracted to before being imported into DeployR or use the -SourceFolder parameter when calling the functions.
#>


function Import-DriverPack {
    param (
    [parameter(Mandatory=$true)]
    [string]$MakeAlias,
    [parameter(Mandatory=$true)]
    [switch]$ImportByName,
    [string]$ModelAlias,
    [string]$FriendlyModel, # e.g., 'Latitude 5580' vs '07A8' ModelAlias
    [string]$OSVer,  # e.g., 'Win10' or 'Win11'
    [string]$URL,  # URL to download the driver pack
    [string]$CabPath, #If you already downloaded the CAB file and use that instead of the URL
    [string]$InputSourceFolder, #Downloaded Extracted Driver Pack Source Folder
    [string]$DriverPackFileName = "", # If not provided, will be derived from URL
    [string]$ArchiveSourceFolder = "D:\DeployRContentItems\Source\DriverPacks",
    [string]$DeployRModulePath ='C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility',
    [bool]$SkipArchive
    )
    
    
    if (-not $URL -and -not $InputSourceFolder -and -not $CabPath) {
        Write-Error "Either URL, CabPath, or InputSourceFolder are required parameters. Exiting."
        Write-Host "Please provide either a URL to download the driver pack, a local CabPath to the CAB file, or a local InputSourceFolder path where the driver pack is already extracted." -ForegroundColor Yellow
        return
    }
    
    
    #Ensure Source Folder exists
    if (-not (Test-Path $ArchiveSourceFolder)) {
        Write-Error "Source Folder $ArchiveSourceFolder does not exist. Exiting."
        return
    }
    Import-Module $DeployRModulePath
    #Get the latest version number of the Content Item
    if ($InputSourceFolder -and (Test-Path $InputSourceFolder)) {
        #Write-Host "  Using provided Input Source Folder: $InputSourceFolder"
        $DriverPackFileName = (Get-Item $InputSourceFolder).Name
        #Copy-Item -Path $InputSourceFolder -Destination "$DriverPackSourcePath\$DriverPackFileName" -Force
    }
    else {
        if (-not $DriverPackFileName) {
            if ($CabPath) {
                $DriverPackFileName = (Get-Item $CabPath).Name
            }
            else {
                $DriverPackFileName = $URL.Split("/")[-1]
            }
            $DriverPackFileFullName = $DriverPackFileName
            #Get Extension
            $DriverPackFileNameExt = $DriverPackFileName.Split(".")[-1]
            
            #Drop Extension
            $DriverPackFileName = [System.IO.Path]::GetFileNameWithoutExtension($DriverPackFileName)
            
        }
    }
    
    if (-not $FriendlyModel) {
        $FriendlyModel = $ModelAlias
        $FolderModelAlias = $ModelAlias
    }
    else {
        $FolderModelAlias = "$FriendlyModel - $ModelAlias"
    }
    $DriverPackSourcePath = "$ArchiveSourceFolder\$MakeAlias\$FolderModelAlias\$OSVer"
    Write-Host "  File Name: $DriverPackFileFullName"
    Write-Host "  Source Path: $DriverPackSourcePath"
    #if (Get-DeployRContentItem | Where-Object {$_.Name -eq "Driver Pack - $MakeAlias - $ModelAlias - $OSVer" -and $_.description -match "$DriverPackFileName"}){
    if (Get-DeployRContentItem | Where-Object {$_.Name -eq "Driver Pack - $MakeAlias - $FolderModelAlias - $OSVer"}){
        Write-Host "  Driver Pack Content Item already exists for $MakeAlias - $FolderModelAlias - $OSVer" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Driver Pack Content Item does not exist for $MakeAlias - $FolderModelAlias - $OSVer. Creating new one."
        #Create Source Folder Structure
        New-Item -Path "$DriverPackSourcePath\Extracted" -ItemType Directory -Force | Out-Null
        #Download the Driver Pack
        if ($InputSourceFolder -and (Test-Path $InputSourceFolder)) {
            Write-Host "  Using provided Input Source Folder: $InputSourceFolder"
            $DriverPackFileName = (Get-Item $InputSourceFolder).Name
            Copy-Item -Path $InputSourceFolder -Destination "$DriverPackSourcePath\Extracted" -Force
        }
        if ($CabPath -and (Test-Path $CabPath)) {
            Write-Host "  Using provided CAB Path: $CabPath" -ForegroundColor Green
            write-HOst "  Copying CAB to Source Folder: $DriverPackSourcePath\$DriverPackFileFullName"
            Copy-Item -Path $CabPath -Destination "$DriverPackSourcePath\$DriverPackFileFullName" -Force
        }
        if (Test-Path "$DriverPackSourcePath\$DriverPackFileFullName") {
            Write-Host "  Driver Pack already downloaded: $DriverPackFileFullName"
        }
        else {
            write-Host "  Downloading Driver Pack to $DriverPackSourcePath\$DriverPackFileFullName"
            Start-BitsTransfer -Source $URL -Destination "$DriverPackSourcePath\$DriverPackFileFullName" -RetryInterval 60 -RetryTimeout 3600   -CustomHeaders "User-Agent:Bob" -ErrorAction Stop
        }
        if (Test-Path "$DriverPackSourcePath\$DriverPackFileFullName") {
            
            if ($DriverPackFileNameExt -eq "zip"){
                write-Host "  Extracting Zip Driver Pack to $DriverPackSourcePath\Extracted"
                Expand-Archive -Path "$DriverPackSourcePath\$DriverPackFileFullName" -DestinationPath "$DriverPackSourcePath\Extracted" -Force
            }
            if ($DriverPackFileNameExt -eq "cab"){
                
                Write-Host -Verbose "Expanding CAB Driver Pack to $DriverPackSourcePath\Extracted"
                Expand -R "$DriverPackSourcePath\$DriverPackFileFullName" -F:* "$DriverPackSourcePath\Extracted" | Out-Null
            }
            if ($DriverPackFileNameExt -eq "exe") {
                Write-Host "  Starting Extraction of EXE Driver Pack...."
                $DriverPack = Get-Item -Path "$DriverPackSourcePath\$DriverPackFileFullName"
                if ($DriverPack) {
                    #Some EXE driver packs support silent extraction, others may not. This may need to be customized per manufacturer.
                    try {
                        if ($MakeAlias -eq "Dell"){
                            Write-Host "  Executing DELL EXE Driver Pack to extract contents to $DriverPackSourcePath\Extracted"
                            Start-Process -FilePath $DriverPack.FullName -ArgumentList "/s /e=`"$DriverPackSourcePath\Extracted`"" -Wait
                        }
                        elseif ($MakeAlias -eq "HP"){
                            Write-Host "  Executing HP EXE Driver Pack to extract contents to $DriverPackSourcePath\Extracted"
                            Start-Process -FilePath $DriverPack.FullName -ArgumentList "/s /e /f `"$DriverPackSourcePath\Extracted`"" -Wait
                        }
                        else{
                            Write-Host "This is not Dell or HP EXE file"
                        }
                    } catch {
                        Write-Error "Failed to extract driver pack: $DriverPack"
                        write-host "Failed to extract driver pack: $DriverPack" -ForegroundColor Red
                        return
                    }
                }
            }
        }
        else {
            Write-Error "Failed to Download"
            exit 1
        }
        #Extract the Driver Pack
        
        #Create DeployR Content Item for the Driver Pack
        
        $NewCI = New-DeployRContentItem -Name "Driver Pack - $MakeAlias - $FolderModelAlias - $OSVer" -Type Folder -Purpose DriverPack -Description "File: $DriverPackFileName"
        $ContentId = $NewCI.id
        if ($ImportByName){
            $NewVersion = New-DeployRContentItemVersion -ContentItemId $ContentId -Description "Source: $DriverPackSourcePath" -DriverManufacturer $MakeAlias -DriverModel $FriendlyModel -SourceFolder "$DriverPackSourcePath\Extracted"
        }
        else {
            $NewVersion = New-DeployRContentItemVersion -ContentItemId $ContentId -Description "Source: $DriverPackSourcePath" -DriverManufacturer $MakeAlias -DriverModel $ModelAlias -SourceFolder "$DriverPackSourcePath\Extracted"    
        }
        
        $ContentVersion = $NewVersion.versionNo
        #Upload the extracted driver pack to the DeployR Content Item
        write-Host "  Uploading extracted Driver Pack to DeployR Content Item"
        try {
            $ciVersion = update-DeployRContentItemContent -ContentId $ContentId -ContentVersion $ContentVersion -SourceFolder "$DriverPackSourcePath\Extracted"
            write-Host "  Successfully uploaded Driver Pack content to DeployR!  Content Item Info:" -ForegroundColor Green
            write-Host "    CI driverManufacturer:   $($ciVersion.driverManufacturer)" -ForegroundColor DarkGray
            write-Host "    CI driverModel:          $($ciVersion.driverModel)" -ForegroundColor DarkGray
            write-Host "    CI ID:                   $($ciVersion.contentItemId), Version: $($ciVersion.versionNo)" -ForegroundColor DarkGray
            write-Host "    CI path:                 $($ciVersion.relativePath)" -ForegroundColor DarkGray
            write-Host "    CI Status:               $($ciVersion.status)" -ForegroundColor DarkGray
            write-Host "    CI Size:                 $([math]::round($ciVersion.contentSize / 1MB, 2)) MB" -ForegroundColor DarkGray
        }
        catch {
            Write-Error "  Failed to upload Driver Pack content to DeployR Content Item for $ManufacturerAlias - $FriendlyModel - $OSVer. Error: $_"
        }
    }
}


#region Panasonic Driver Packs Import
function Import-PanasonicDriverPacks {
    param (
    [string]$SourceFolder = "D:\DeployRContentItems\Source\DriverPacks",
    [string]$DeployRModulePath ='C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility',
    [string]$CabPath,
    [string]$ModelAlias
    )
    Write-Host "Importing Panasonic Driver Packs" -ForegroundColor Green
    #Ensure Source Folder exists
    if (-not (Test-Path $SourceFolder)) {
        New-Item -Path $SourceFolder -ItemType Directory -Force | Out-Null
    }
    $MakeAlias = "Panasonic Corporation"
    if ($CabPath -and (Test-Path $CabPath)) {
        if (-not $ModelAlias) {
            Write-Error "ModelAlias parameter is required when using CabPath. Exiting."
            return
        }
        Write-Host "  Using provided CAB Path: $CabPath"
        #Assumes the CAB contains the extracted driver packs in the correct folder structure
        #Copy the CAB to the source folder and extract it
        $DriverPackFileName = (Get-Item $CabPath).Name
        $OSVer = if ($DriverPackFileName -match "Win11") {'Win11'} else {'Win10'}
        Write-Host "  Processing Windows $OSVer $URL" -foregroundColor Green
        Import-DriverPack -MakeAlias $MakeAlias -ModelAlias $ModelAlias -OSVer $OSVer -CabPath $CabPath -ArchiveSourceFolder $SourceFolder -DeployRModulePath $DeployRModulePath -ImportByName:$false
    }
    else{
        #Get the Panasonic Driver Pack Catalog JSON
        Import-Module $DeployRModulePath
        $PanasonicCatalogURL = "https://pna-b2b-storage-mkt.s3.amazonaws.com/computer/software/apps/Panasonic.json"
        $JSONCatalog = Invoke-RestMethod -Uri $PanasonicCatalogURL
        $PanasonicDriverPacks = $JSONCatalog.PanasonicModels
        

        $TotalModels = (($PanasonicDriverPacks.PSObject.Properties).Count).Count
        Write-Host "Total Panasonic Models to process: $TotalModels" -ForegroundColor Magenta
        $CurrentCount = 0
        foreach ($modelKey in $PanasonicDriverPacks.PSObject.Properties.Name) {
            $CurrentCount++
            Write-Host "Processing model $CurrentCount of $TotalModels" -ForegroundColor Cyan
            $model = $PanasonicDriverPacks.$modelKey
            $ModelAlias = $modelKey
            Write-Host " Processing $MakeAlias - $ModelAlias" -ForegroundColor Cyan
            if ($Model.URL10) {
                $OSVer = 'Win10'
                $URL = $model.URL10
                Write-Host "  Processing Windows $OSVer $URL" -foregroundColor Green
                Import-DriverPack -MakeAlias $MakeAlias -ModelAlias $ModelAlias -OSVer $OSVer -URL $URL -ArchiveSourceFolder $SourceFolder -DeployRModulePath $DeployRModulePath -ImportByName:$false
            }
            if ($Model.URL11) {
                $OSVer = 'Win11'
                $URL = $model.URL11
                Write-Host "  Processing Windows $OSVer $URL" -foregroundColor Green
                Import-DriverPack -MakeAlias $MakeAlias -ModelAlias $ModelAlias -OSVer $OSVer -URL $URL -ArchiveSourceFolder $SourceFolder -DeployRModulePath $DeployRModulePath -ImportByName:$false
            }
        }
    }
}

#endregion Panasonic Driver Packs Import



#region Dell Driver Packs Import
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
function Get-DellDeviceDetails {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory=$False)]
    [ValidateLength(4,4)]    
    [string]$SystemSKUNumber,
    [string]$ModelLike
    )
    
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    
    
    if ((!($SystemSKUNumber)) -and (!($ModelLike))) {
        if ($Manufacturer -notmatch "Dell"){return "This Function is only for Dell Systems, or please provide a SKU"}
        $SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    }
    <#
    if (!($ModelLike)){
    $DellSKU = Get-DellSupportedModels | Where-Object {$_.systemID -match $SystemSKUNumber} | Select-Object -First 1
    }
    else {
    $DellSKU = Get-DellSupportedModels | Where-Object { $_.Model -match $ModelLike}
    }
    
    return $DellSKU | Select-Object -Property SystemID,Model
    #>
    $MoreData = Get-DellDriverPackXML
    if (!($ModelLike)){
        $DrillDown = $MoreData.DriverPackManifest.DriverPackage.SupportedSystems.brand.model | Where-Object {$_.systemid -eq $SystemSKUNumber} | Select-Object -First 1
        $RDSDate = [DATETIME]"$($DrillDown.rtsDate)"
        $DeviceOutput = New-Object -TypeName PSObject
        $DeviceOutput | Add-Member -MemberType NoteProperty -Name "SystemID" -Value "$($DrillDown.systemID)" -Force
        $DeviceOutput | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($DrillDown.name)"  -Force
        $DeviceOutput | Add-Member -MemberType NoteProperty -Name "RTSDate" -Value $([DATETIME]$RDSDate) -Force
        return $DeviceOutput		
    }
    else{
        $DrillDown = $MoreData.DriverPackManifest.DriverPackage.SupportedSystems.brand.model | Where-Object {$_.name -match $ModelLike}
        if ($DrillDown.count -gt 1){
            $SystemIDs = $DrillDown.systemID | Select-Object -Unique
            $DeviceOutputObject = @()
            foreach ($SystemID in $SystemIDs){
                $DrillDown = $MoreData.DriverPackManifest.DriverPackage.SupportedSystems.brand.model | Where-Object {$_.systemid -eq $SystemID}| Select-Object -First 1
                $RDSDate = [DATETIME]"$($DrillDown.rtsDate)"
                $DeviceOutput = New-Object -TypeName PSObject
                $DeviceOutput | Add-Member -MemberType NoteProperty -Name "SystemID" -Value "$($DrillDown.systemID)" -Force
                $DeviceOutput | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($DrillDown.name)"  -Force
                $DeviceOutput | Add-Member -MemberType NoteProperty -Name "RTSDate" -Value $([DATETIME]$RDSDate) -Force
                $DeviceOutputObject += $DeviceOutput 
            }
            return $DeviceOutputObject | Sort-Object -Property RTSDate
        }
    }
}
function Get-DellDriverPackXML {
    [CmdletBinding()]
    
    $CabPathIndex = "$env:ProgramData\EMPS\DellCabDownloads\CatalogIndexPC.cab"
    $DellCabExtractPath = "$env:ProgramData\EMPS\DellCabDownloads\DellCabExtract"
    
    # Pull down Dell XML CAB used in Dell Command Update ,extract and Load
    if (!(Test-Path $DellCabExtractPath)){$null = New-Item -Path $DellCabExtractPath -ItemType Directory -Force}
    Write-Verbose "Downloading Dell Cab"
    Invoke-WebRequest -Uri "https://downloads.dell.com/catalog/DriverPackCatalog.cab" -OutFile $CabPathIndex -UseBasicParsing -Proxy $ProxyServer
    If(Test-Path "$DellCabExtractPath\DellSDPCatalogPC.xml"){Remove-Item -Path "$DellCabExtractPath\DellSDPCatalogPC.xml" -Force}
    Start-Sleep -Seconds 1
    if (test-path $DellCabExtractPath){Remove-Item -Path $DellCabExtractPath -Force -Recurse}
    $null = New-Item -Path $DellCabExtractPath -ItemType Directory
    Write-Verbose "Expanding the Cab File..." 
    $null = expand $CabPathIndex $DellCabExtractPath\DriverPackCatalog.xml
    
    Write-Verbose "Loading Dell Catalog XML.... can take awhile"
    [xml]$XMLIndex = Get-Content "$DellCabExtractPath\DriverPackCatalog.xml"
    
    return $XMLIndex
}
function Get-DellDeviceDriverPack {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory=$False)]
    [ValidateLength(4,4)]    
    [string]$SystemSKUNumber,
    [ValidateSet('Windows10','Windows11')]
    [string]$OSVer
    )
    
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    
    
    if (!($SystemSKUNumber)) {
        if ($Manufacturer -notmatch "Dell"){return "This Function is only for Dell Systems, or please provide a SKU"}
        $SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    }
    
    $MoreData = Get-DellDriverPackXML
    $DriverPacks = $MoreData.DriverPackManifest.DriverPackage | Where-Object {$_.SupportedSystems.brand.model.systemid -eq $SystemSKUNumber}
    $DeviceDetails = $MoreData.DriverPackManifest.DriverPackage.SupportedSystems.brand.model | Where-Object {$_.systemid -eq $SystemSKUNumber} | Select-Object -First 1
    $DriverPacksOBject = @()
    foreach ($DriverPack in $DriverPacks){
        $URL = "http://$($MoreData.DriverPackManifest.baseLocation)/$($DriverPack.path)"
        $FileName = $DriverPack.path -split "/" | Select-Object -Last 1
        $DeviceDriverPack = New-Object -TypeName PSObject
        $MetaDataVersion = $MoreData.DriverPackManifest.version
        $SizeinMB = [Math]::Round($DriverPack.size/1MB,2)
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "SystemID" -Value "$($DeviceDetails.systemID)" -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($DeviceDetails.name)"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "MetaDataVersion" -Value "$MetaDataVersion"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "FileName" -Value "$FileName"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "ReleaseID" -Value "$($DriverPack.releaseID)"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "URL" -Value "$URL"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "DateTime" -Value $([DATETIME]$DriverPack.dateTime) -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "hashMD5" -Value $($DriverPack.hashMD5) -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "SizeinMB" -Value $SizeinMB -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "OSSupported" -Value $($DriverPack.SupportedOperatingSystems.OperatingSystem.osCode) -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "OsArch" -Value $($DriverPack.SupportedOperatingSystems.OperatingSystem.osArch) -Force
        $DriverPacksOBject += $DeviceDriverPack 
    }
    
    if ($OSVer){
        $DriverPacksOBject = $DriverPacksOBject | Where-Object {$_.OSSupported -match $OSVer}
    }
    
    return $DriverPacksOBject 
    
}

function Import-DellDriverPackBySKU {
    param (
    [string]$DellSKU,
    [string]$SourceFolder = "D:\DeployRContentItems\Source\DriverPacks",
    [string]$DeployRModulePath ='C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
    )
    
    #region functions
    
    
    #endregion functions
    Write-Host "Importing Dell Driver Packs" -ForegroundColor Green
    #Ensure Source Folder exists
    if (-not (Test-Path $SourceFolder)) {
        New-Item -Path $SourceFolder -ItemType Directory -Force | Out-Null
    }
    #Assumes that the Dell Driver Packs are already downloaded and extracted in the SourceFolder
    #The folder structure should be:
    # $SourceFolder\<ModelAlias>\<OSVer>\ (e.g., D:\DeployRContentItems\Source\DriverPacks\Dell\XPS15_9500\Win10\)
    
    Import-Module $DeployRModulePath
    $MakeAlias = "Dell"
    
    $DriverPackInfo = Get-DellDeviceDriverPack -SystemSKUNumber $DellSKU | Where-Object {$_.OSSupported -match 'Windows10|Windows11'}
    if ($DriverPackInfo.Count -gt 1) {
        $DriverPackInfo = $DriverPackInfo | Where-Object { $_.OSSupported -match 'Windows11' } | Select-Object -Last 1
    }
    
    if (-not $DriverPackInfo) {
        Write-Error "No Driver Pack found for Dell SKU: $DellSKU"
        return
    }
    $FriendlyModel = $DriverPackInfo.Model -replace '[\/:*?"<>|]', '_'  # Sanitize for folder name
    $ModelAlias = $DellSKU
    $OSVer = if ($DriverPackInfo.OSSupported -match 'Windows11') {'Win11'} else {'Win10'}
    $URL = $DriverPackInfo.URL
    Import-DriverPack -MakeAlias $MakeAlias -FriendlyModel $FriendlyModel -ModelAlias $ModelAlias -OSVer $OSVer -URL $URL -ArchiveSourceFolder $SourceFolder -DeployRModulePath $DeployRModulePath
}


Function Find-DellDriverPacks {
    [CmdletBinding()]
    param (
    [switch]$ImportByModel,
    [switch]$ImportBySKU,
    [string]$SourceFolder = "D:\DeployRContentItems\Source\DriverPacks",
    [string]$DeployRModulePath ='C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
    )
    
    $Data = Get-DellDriverPackXML
    $DriverPacks = $Data.DriverPackManifest.DriverPackage
    $DriverPacks = $DriverPacks | Where-Object {$_.SupportedOperatingSystems.OperatingSystem.osCode -match 'Windows10|Windows11'}
    $DriverPacks = $DriverPacks | Where-Object {$_.SupportedOperatingSystems.OperatingSystem.osArch -match 'x64'}
    $DriverPacksOBject = @()
    foreach ($DriverPack in $DriverPacks){
        $URL = "http://$($Data.DriverPackManifest.baseLocation)/$($DriverPack.path)"
        $FileName = $DriverPack.path -split "/" | Select-Object -Last 1
        $DeviceDriverPack = New-Object -TypeName PSObject
        $MetaDataVersion = $Data.DriverPackManifest.version
        $SizeinMB = [Math]::Round($DriverPack.size/1MB,2)
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "SystemID" -Value "$($Driverpack.SupportedSystems.Brand.model.systemid)" -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($Driverpack.SupportedSystems.Brand.model.name | Select-Object -Unique)"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "MetaDataVersion" -Value "$MetaDataVersion"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "FileName" -Value "$FileName"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "ReleaseID" -Value "$($DriverPack.releaseID)"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "URL" -Value "$URL"  -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "DateTime" -Value $([DATETIME]$DriverPack.dateTime) -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "hashMD5" -Value $($DriverPack.hashMD5) -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "SizeinMB" -Value $SizeinMB -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "OSSupported" -Value $($DriverPack.SupportedOperatingSystems.OperatingSystem.osCode) -Force
        $DeviceDriverPack | Add-Member -MemberType NoteProperty -Name "OsArch" -Value $($DriverPack.SupportedOperatingSystems.OperatingSystem.osArch) -Force
        $DriverPacksOBject += $DeviceDriverPack 
    }
    $DPSelect = $DriverPacksOBject | Out-GridView -PassThru -Title "Select the Dell Driver Packs to Import"
    
    if ($ImportBySKU) {
        foreach ($DP in $DPSelect) {
            $SystemIDs = $DP.SystemID.Split(" ")
            foreach ($SystemID in $SystemIDs) {
                $FriendlyModel = $DP.Model -replace '[\/:*?"<>|]', '_'  # Sanitize for folder name
                $ModelAlias = $SystemID
                $OSVer = if ($DP.OSSupported -match 'Windows11') {'Win11'} else {'Win10'}
                $URL = $DP.URL
                Import-DriverPack -MakeAlias "Dell" -FriendlyModel $FriendlyModel -ModelAlias $ModelAlias -OSVer $OSVer -URL $URL -ArchiveSourceFolder $SourceFolder -DeployRModulePath $DeployRModulePath
            }
        }
    }
    elseif ($ImportByModel) {
        foreach ($DP in $DPSelect) {
            $FriendlyModel = $DP.Model -replace '[\/:*?"<>|]', '_'  # Sanitize for folder name
            $ModelAlias = $DP.SystemID
            
            $OSVer = if ($DP.OSSupported -match 'Windows11') {'Win11'} else {'Win10'}
            $URL = $DP.URL
            Import-DriverPack -MakeAlias "Dell" -FriendlyModel $FriendlyModel -ModelAlias $ModelAlias -OSVer $OSVer -URL $URL -ArchiveSourceFolder $SourceFolder -DeployRModulePath $DeployRModulePath -ImportByName
        }
    }
    else {
        return $DPSelect
    }
    
}
#endregion Dell Driver Packs Import

#region HP Driver Pack
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
                    $DriverPack = Get-HPSoftPaqItems -osver $($SupportedWinXXBuilds[$loop_index]) -os $OS -Platform $MachinePlatform -ErrorAction SilentlyContinue | Where-Object {$_.Category -match "Driver Pack"}
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
                        $DriverPack = Get-HPSoftPaqItems -osver $($SupportedWinXXBuilds[$loop_index]) -os $OS -Platform $MachinePlatform -ErrorAction SilentlyContinue | Where-Object {$_.Category -match "Driver Pack"}
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
function Get-HPPlatforms{
    
    $CabPath = "$env:TEMP\platformList.cab"
    $XMLPath = "$env:TEMP\platformList.xml"
    $PlatformListCabURL = "https://hpia.hpcloud.hp.com/ref/platformList.cab"
    if (!(Test-Path $CabPath)){
        Invoke-WebRequest -Uri $PlatformListCabURL -OutFile $CabPath -UseBasicParsing
    }
    if (!(Test-Path $XMLPath)){
        $Expand = expand $CabPath $XMLPath
    }
    [xml]$XML = Get-Content $XMLPath
    
    $Platforms = $XML.ImagePal.Platform
    $Platforms = $Platforms | Where-Object {$_.ProductName.DPBCompliant -eq 'true'}
    
    #Create PSObject of the Platforms, it will include the SystemID and the ProductName.#Text (model name)
    #Expand each ProductName into its own row
    $ExpandedPlatforms = @()
    foreach ($Platform in $Platforms) {
        $ProductNames = $Platform.ProductName.'#text'
        
        # Handle both single and multiple ProductNames
        if ($ProductNames -is [array]) {
            foreach ($ProductName in $ProductNames) {
                $ExpandedPlatforms += [PSCustomObject]@{
                    SystemID = $Platform.SystemID.ToUpper()
                    ProductName = $ProductName
                }
            }
        }
        else {
            $ExpandedPlatforms += [PSCustomObject]@{
                SystemID = $Platform.SystemID.ToUpper()
                ProductName = $ProductNames
            }
        }
    }
    
    return $ExpandedPlatforms
}

function Find-HPDriverPacks {
    [CmdletBinding()]
    param (
    [switch]$ImportByModel,
    [switch]$ImportBySKU,
    [string]$SourceFolder = "D:\DeployRContentItems\Source\DriverPacks",
    [string]$DeployRModulePath ='C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
    )
    $AvailableModels = Get-HPPlatforms
    $DPSelect = $AvailableModels | sort-object ProductName | Out-GridView -PassThru -Title "Select the HP Models you'd like to Generate DriverPacks for:"
    
    Foreach ($DP in $DPSelect){
        $DPDetails = Get-HPDriverPackLatest -Platform $DP.SystemID | select-object -First 1
        
        $FriendlyModel = $DP.ProductName -replace '[\/:*?"<>|]', '_'  # Sanitize for folder name
        $ModelAlias = $DP.SystemID
        $OSVer = if ($DPDetails.Name -match 'Windows 11') {'Win11'} else {'Win10'}
        $URL = "https://$($DPDetails.URL)"
        Import-DriverPack -MakeAlias "HP" -FriendlyModel $FriendlyModel -ModelAlias $ModelAlias -OSVer $OSVer -URL $URL -ArchiveSourceFolder $SourceFolder -DeployRModulePath $DeployRModulePath -ImportByName
        
    }
}
