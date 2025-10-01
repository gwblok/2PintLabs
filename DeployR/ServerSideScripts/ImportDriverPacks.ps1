
function Import-DriverPack {
    param (
    [parameter(Mandatory=$true)]
    [string]$MakeAlias,
    [parameter(Mandatory=$true)]
    [string]$ModelAlias,
    [string]$FriendlyModel, # e.g., 'Latitude 5580' vs '07A8' ModelAlias
    [string]$OSVer,  # e.g., 'Win10' or 'Win11'
    [string]$URL,  # URL to download the driver pack
    [string]$InputSourceFolder, #Downloaded Extracted Driver Pack Source Folder
    [string]$DriverPackFileName = "", # If not provided, will be derived from URL
    [string]$ArchiveSourceFolder = "D:\DeployRContentItems\Source\DriverPacks",
    [string]$DeployRModulePath ='C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
    )
    
    
    if (-not $URL -and -not $InputSourceFolder) {
        Write-Error "Either URL or InputSourceFolder are required parameters. Exiting."
        Write-Host "Please provide either a URL to download the driver pack or a local InputSourceFolder path where the driver pack is already extracted." -ForegroundColor Yellow
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
            $DriverPackFileName = $URL.Split("/")[-1]
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
        if (Test-Path "$DriverPackSourcePath\$DriverPackFileFullName") {
            Write-Host "  Driver Pack already downloaded: $DriverPackFileFullName"
        }
        else {
            write-Host "  Downloading Driver Pack to $DriverPackSourcePath\$DriverPackFileFullName"
            Start-BitsTransfer -Source $URL -Destination "$DriverPackSourcePath\$DriverPackFileFullName" -RetryInterval 60 -RetryTimeout 3600
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
                Write-Host "  Executing EXE Driver Pack to extract contents to $DriverPackSourcePath\Extracted"
                $DriverPack = Get-Item -Path "$DriverPackSourcePath\$DriverPackFileFullName"
                if ($DriverPack.VersionInfo.FileDescription -match 'Dell') {
                    #Some EXE driver packs support silent extraction, others may not. This may need to be customized per manufacturer.
                try {
                    Start-Process -FilePath $DriverPack.FullName -ArgumentList "/s /e=`"$DriverPackSourcePath\Extracted`"" -Wait
                } catch {
                    Write-Error "Failed to extract Dell driver pack: $DriverPack"
                }
                }
            }
        }
        #Extract the Driver Pack
        
        #Create DeployR Content Item for the Driver Pack
        
        $NewCI = New-DeployRContentItem -Name "Driver Pack - $MakeAlias - $FolderModelAlias - $OSVer" -Type Folder -Purpose DriverPack -Description "File: $DriverPackFileName"
        $ContentId = $NewCI.id
        $NewVersion = New-DeployRContentItemVersion -ContentItemId $ContentId -Description "Source: $DriverPackSourcePath" -DriverManufacturer $MakeAlias -DriverModel $ModelAlias -SourceFolder "$DriverPackSourcePath\Extracted"
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
    [string]$DeployRModulePath ='C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
    )
    Write-Host "Importing Panasonic Driver Packs" -ForegroundColor Green
    #Ensure Source Folder exists
    if (-not (Test-Path $SourceFolder)) {
        New-Item -Path $SourceFolder -ItemType Directory -Force | Out-Null
    }
    #Get the Panasonic Driver Pack Catalog JSON
    
    
    Import-Module $DeployRModulePath
    $PanasonicCatalogURL = "https://pna-b2b-storage-mkt.s3.amazonaws.com/computer/software/apps/Panasonic.json"
    $JSONCatalog = Invoke-RestMethod -Uri $PanasonicCatalogURL
    $PanasonicDriverPacks = $JSONCatalog.PanasonicModels
    $MakeAlias = "Panasonic Corporation"
    
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
            Import-DriverPack -MakeAlias $MakeAlias -ModelAlias $ModelAlias -OSVer $OSVer -URL $URL -ArchiveSourceFolder $SourceFolder -DeployRModulePath $DeployRModulePath
        }
        if ($Model.URL11) {
            $OSVer = 'Win11'
            $URL = $model.URL11
            Write-Host "  Processing Windows $OSVer $URL" -foregroundColor Green
            Import-DriverPack -MakeAlias $MakeAlias -ModelAlias $ModelAlias -OSVer $OSVer -URL $URL -ArchiveSourceFolder $SourceFolder -DeployRModulePath $DeployRModulePath
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
        [switch]$Import,
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
    
    if ($Import) {
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
    else {
        return $DPSelect
    }

}
#endregion Dell Driver Packs Import





<# Backup
function Import-PanasonicDriverPacks {
param (
[string]$SourceFolder = "C:\DeployR\DriverPacks\Source",
[string]$DeployRModulePath ='C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
)
Write-Host "Importing Panasonic Driver Packs" -ForegroundColor Green
#Ensure Source Folder exists
if (-not (Test-Path $SourceFolder)) {
New-Item -Path $SourceFolder -ItemType Directory -Force | Out-Null
}
#Get the Panasonic Driver Pack Catalog JSON


Import-Module $DeployRModulePath
$PanasonicCatalogURL = "https://pna-b2b-storage-mkt.s3.amazonaws.com/computer/software/apps/Panasonic.json"
$JSONCatalog = Invoke-RestMethod -Uri $PanasonicCatalogURL
$PanasonicDriverPacks = $JSONCatalog.PanasonicModels
$Manufacturer = "Panasonic"
$ItemManufacturer = "Panasonic Corporation"

$TotalModels = (($PanasonicDriverPacks.PSObject.Properties).Count).Count
Write-Host "Total Panasonic Models to process: $TotalModels" -ForegroundColor Magenta
$CurrentCount = 0
foreach ($modelKey in $PanasonicDriverPacks.PSObject.Properties.Name) {
$CurrentCount++
Write-Host "Processing model $CurrentCount of $TotalModels" -ForegroundColor Cyan
$model = $PanasonicDriverPacks.$modelKey
$ModelAlias = $modelKey
Write-Host " Processing $Manufacturer - $ModelAlias" -ForegroundColor Cyan
if ($Model.URL10) {
$OSVer = 'Win10'
$Win10URL = $model.URL10
$DriverPackFileName = $Win10URL.Split("/")[-1]
#Version from URL File Name, part that starts with V
$DriverPackVersion = $DriverPackFileName.Split("_") | Where-Object { $_ -like "V*" }
Write-Host "  Processing Windows 10: $Win10URL" -foregroundColor Green
$DriverPackSourcePath = "$SourceFolder\$Manufacturer\$ModelAlias\$OSVer"
Write-Host "  Source Path: $DriverPackSourcePath"
if (Get-DeployRContentItem | Where-Object {$_.Name -eq "Driver Pack - $Manufacturer - $ModelAlias - $OSVer" -and $_.description -match "$DriverPackFileName"}){
Write-Host "  Driver Pack Content Item already exists for $Manufacturer - $ModelAlias - $OSVer with file $DriverPackFileName" -ForegroundColor Yellow
}
else {
#Create Source Folder Structure
New-Item -Path "$DriverPackSourcePath\Extracted" -ItemType Directory -Force | Out-Null
#Download the Driver Pack
if (Test-Path "$DriverPackSourcePath\$DriverPackFileName") {
Write-Host "  Driver Pack already downloaded: $DriverPackFileName"
}
else {
write-Host "  Downloading Driver Pack to $DriverPackSourcePath\$DriverPackFileName"
Start-BitsTransfer -Source $Win10URL -Destination "$DriverPackSourcePath\$DriverPackFileName" -RetryInterval 60 -RetryTimeout 3600
}

#Extract the Driver Pack
write-Host "  Extracting Driver Pack to $DriverPackSourcePath\Extracted"
Expand-Archive -Path "$DriverPackSourcePath\$DriverPackFileName" -DestinationPath "$DriverPackSourcePath\Extracted" -Force
#Create DeployR Content Item for the Driver Pack

$NewCI = New-DeployRContentItem -Name "Driver Pack - $Manufacturer - $ModelAlias - $OSVer" -Type Folder -Purpose DriverPack -Description "File: $DriverPackFileName"
$ContentId = $NewCI.id
$NewVersion = New-DeployRContentItemVersion -ContentItemId $ContentId -Description "Source: $DriverPackSourcePath" -DriverManufacturer $ItemManufacturer -DriverModel $ModelAlias -SourceFolder "$DriverPackSourcePath\Extracted"
$ContentVersion = $NewVersion.versionNo
#Upload the extracted driver pack to the DeployR Content Item
write-Host "  Uploading extracted Driver Pack to DeployR Content Item"
$ciVersion = update-DeployRContentItemContent -ContentId $ContentId -ContentVersion $ContentVersion -SourceFolder "$DriverPackSourcePath\Extracted"
}
}
if ($Model.URL11) {
$OSVer = 'Win11'
$Win11URL = $model.URL11
$DriverPackFileName = $Win11URL.Split("/")[-1]
#Version from URL File Name, part that starts with V
$DriverPackVersion = $DriverPackFileName.Split("_") | Where-Object { $_ -like "V*" }
Write-Host "  Processing Windows 11: $Win11URL" -foregroundColor Green
$DriverPackSourcePath = "$SourceFolder\$Manufacturer\$ModelAlias\$OSVer"
Write-Host "  Source Path: $DriverPackSourcePath"
#Create Source Folder Structure

if (Get-DeployRContentItem | Where-Object {$_.Name -eq "Driver Pack - $Manufacturer - $ModelAlias - $OSVer" -and $_.description -match "$DriverPackFileName"}){
Write-Host "  Driver Pack Content Item already exists for $Manufacturer - $ModelAlias - $OSVer with file $DriverPackFileName" -ForegroundColor Yellow
}
else {
New-Item -Path "$DriverPackSourcePath\Extracted" -ItemType Directory -Force | Out-Null
#Download the Driver Pack
if (Test-Path "$DriverPackSourcePath\$DriverPackFileName") {
Write-Host "  Driver Pack already downloaded: $DriverPackFileName"
}
else {
write-Host "  Downloading Driver Pack to $DriverPackSourcePath\$DriverPackFileName"
Start-BitsTransfer -Source $Win11URL -Destination "$DriverPackSourcePath\$DriverPackFileName" -RetryInterval 60 -RetryTimeout 3600
}

#Extract the Driver Pack
write-Host "  Extracting Driver Pack to $DriverPackSourcePath\Extracted"
Expand-Archive -Path "$DriverPackSourcePath\$DriverPackFileName" -DestinationPath "$DriverPackSourcePath\Extracted" -Force
#Create DeployR Content Item for the Driver Pack

$NewCI = New-DeployRContentItem -Name "Driver Pack - $Manufacturer - $ModelAlias - $OSVer" -Type Folder -Purpose DriverPack -Description "File: $DriverPackFileName"
$ContentId = $NewCI.id
$NewVersion = New-DeployRContentItemVersion -ContentItemId $ContentId -Description "Source: $DriverPackSourcePath" -DriverManufacturer $ItemManufacturer -DriverModel $ModelAlias -SourceFolder "$DriverPackSourcePath\Extracted"
$ContentVersion = $NewVersion.versionNo
#Upload the extracted driver pack to the DeployR Content Item
write-Host "  Uploading extracted Driver Pack to DeployR Content Item"
$ciVersion = update-DeployRContentItemContent -ContentId $ContentId -ContentVersion $ContentVersion -SourceFolder "$DriverPackSourcePath\Extracted"
}
}
}
}

#>